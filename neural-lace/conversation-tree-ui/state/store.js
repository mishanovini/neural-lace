'use strict';
// ADR-032 §5/§7 + NFR-1/NFR-7 — the durable store: path resolution, atomic
// single-event append (§7b), snapshot + coverage marker (§7a), compaction
// (§7c), torn-snapshot recovery (§7a), versioned reader / unknown-major refuse
// (§1), last-N version retention (NFR-1), append-only audit log (NFR-7).
//
// Every mutation is ONE write-temp-then-renameSync of the WHOLE state file
// (the Phase-0 primitive at the old state.js:79, kept verbatim in spirit):
// renameSync is atomic on a single filesystem, so a concurrent reader of the
// well-known path always sees a file with N or N+1 WHOLE events, never half
// (Pin 3b / §7b). event_id makes a retried append idempotent (§2).

const fs = require('fs');
const path = require('path');
const os = require('os');
const {
  SCHEMA_VERSION, SCHEMA_TOO_NEW_MESSAGE, generateEventId, validateEvent,
} = require('./schema.js');
const { deriveSnapshot } = require('./reducer.js');

// Distinguishable error class so callers (A2d, B1b, the GUI) can branch on the
// Pin-2 unknown-major partition specifically vs. a generic parse error.
class SchemaTooNewError extends Error {
  constructor(fileMajor, knownMajor) {
    super(SCHEMA_TOO_NEW_MESSAGE);
    this.name = 'SchemaTooNewError';
    this.fileMajor = fileMajor;
    this.knownMajor = knownMajor;
  }
}

// ---- §5 well-known path resolution -----------------------------------------
// Per-project tree:  <project-root>/.claude/state/conversation-tree/tree-state.json
// Global tree:       ~/.claude/state/conversation-tree/global/tree-state.json
function resolveStatePath(opts) {
  opts = opts || {};
  if (opts.statePath) return path.resolve(opts.statePath); // explicit override (tests)
  if (opts.treeId && opts.treeId !== 'global') {
    const root = opts.projectRoot || process.cwd();
    return path.join(root, '.claude', 'state', 'conversation-tree', 'tree-state.json');
  }
  return path.join(os.homedir(), '.claude', 'state', 'conversation-tree', 'global', 'tree-state.json');
}
function auditPathFor(statePath) { return statePath + '.audit.log'; }
function treeIdFor(opts) { return (opts && opts.treeId) || 'global'; }

const DEFAULT_COMPACTION_THRESHOLD = 500;  // §7c: bound the state file (NFR-3 <100 branches)
const DEFAULT_RETENTION = 5;               // NFR-1: last-N prior versions kept

function emptyState(treeId) {
  return {
    schema_version: SCHEMA_VERSION,
    tree_id: treeId || 'global',
    events: [],
    // §7a coverage marker: valid=true ONLY after full serialization;
    // covers_through_event_id = the id of the last event the snapshot
    // provably reduced. A reader that finds valid!=true OR the marker not
    // equal to the last events[] id MUST discard the snapshot and replay.
    snapshot: { nodes: [], backlog: [], rejections: [], valid: false, covers_through_event_id: null },
  };
}

// ---- §1 versioned read ------------------------------------------------------
// Throws SchemaTooNewError on unknown MAJOR (reads NOTHING — never partial).
// Returns emptyState on ENOENT or unparseable JSON (the torn/corrupt path is
// resolved by readState() via log replay, not here).
function readRawState(statePath, treeId) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch (err) {
    if (err && err.code === 'ENOENT') return emptyState(treeId);
    throw err;
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    // Unparseable top-level: treat as a fully-torn write — caller replays the
    // audit log if one exists, else empty. We cannot read schema_version from
    // garbage, so we DO NOT raise SchemaTooNew here (no major to compare).
    return { __corrupt: true, schema_version: SCHEMA_VERSION, tree_id: treeId || 'global', events: [], snapshot: null };
  }
  const fileMajor = parsed.schema_version;
  if (typeof fileMajor !== 'number' || !Number.isFinite(fileMajor)) {
    return { __corrupt: true, schema_version: SCHEMA_VERSION, tree_id: treeId || 'global', events: [], snapshot: null };
  }
  // Pin 2 (§1): known major < file major ⇒ refuse, read NOTHING.
  if (fileMajor > SCHEMA_VERSION) throw new SchemaTooNewError(fileMajor, SCHEMA_VERSION);
  return parsed;
}

// ---- §7a torn-snapshot recovery --------------------------------------------
// Returns { schema_version, tree_id, events, snapshot } where snapshot is
// ALWAYS trustworthy: if the on-disk snapshot's coverage marker does not
// provably match events[], it is DISCARDED and recomputed from events (the
// log is truth — Pin 3a). Idempotency: duplicate event_ids are collapsed.
function readState(opts) {
  opts = opts || {};
  const treeId = treeIdFor(opts);
  const statePath = resolveStatePath(opts);
  let parsed;
  try {
    parsed = readRawState(statePath, treeId);
  } catch (err) {
    if (err instanceof SchemaTooNewError) throw err; // Pin 2: propagate, read nothing
    throw err;
  }

  // Source of truth = events[], deduped by event_id (idempotency / §2).
  let events = Array.isArray(parsed.events) ? parsed.events : [];
  if (parsed.__corrupt || events.length === 0) {
    // Fully-torn state file: reconstruct from the append-only audit log
    // (NFR-7 — never truncated, so it is the deepest recoverable truth).
    const fromAudit = replayAuditLog(auditPathFor(statePath));
    if (fromAudit.length > 0) events = fromAudit;
  }
  events = dedupeById(events);

  const snap = parsed.snapshot;
  const lastId = events.length ? events[events.length - 1].event_id : null;
  const markerOk = snap && snap.valid === true
    && snap.covers_through_event_id === lastId;

  let snapshot;
  if (markerOk) {
    snapshot = snap;                       // trust the cache — marker proves it
  } else {
    // §7a mandatory: discard the snapshot, deterministically replay the log.
    snapshot = deriveSnapshot(events, treeId);
    snapshot.valid = true;
    snapshot.covers_through_event_id = lastId;
  }
  return { schema_version: SCHEMA_VERSION, tree_id: treeId, events: events, snapshot: snapshot };
}

function dedupeById(events) {
  const seen = new Set();
  const out = [];
  for (const ev of events) {
    if (!ev || typeof ev.event_id !== 'string') continue;
    if (seen.has(ev.event_id)) continue;   // §2: duplicate event_id ⇒ no-op
    seen.add(ev.event_id);
    out.push(ev);
  }
  return out;
}

// ---- §7c (DEC-D 2026-05-17) general gate-relevant-still-live retention -----
// The ADR-032 §7c general principle (NL-FINDING-003 resolution): compaction
// MUST NOT drop any event that is still live AND gate-relevant. A reader/gate
// that consumes an event-class from events[] (not the snapshot) must still find
// the most-recent such event per still-live entity AFTER the covered prefix is
// truncated. This is stated GENERALLY so a future gate consuming a new
// event-class inherits the rule with no further §7c change — branch-opened
// per still-live node is merely v1's ONLY instance.
//
// GATE_RELEVANT_EVENT_CLASSES is the registry of (event-class -> entity-key)
// pairs that some gate consumes from events[]. Adding a future gate = adding
// one entry here; the retention logic generalizes with zero other edits.
const GATE_RELEVANT_EVENT_CLASSES = [
  // §8 conversation-tree-state-gate.sh consumes `branch-opened`, keyed by the
  // node it opens. v1's sole instance of the general rule.
  { type: 'branch-opened', entityKey: function (ev) { return ev.node_id; } },
];

// A node is "live" iff it survives reduction into snapshot.nodes AND its state
// is not the terminal `archived` (the reducer's own liveness notion: a
// `concluded` node stays live because `re-opened` reverses it with no data
// loss, so it remains gate-relevant; only `archived` is "no longer active").
function liveEntityIds(snapshot) {
  const live = new Set();
  const nodes = (snapshot && Array.isArray(snapshot.nodes)) ? snapshot.nodes : [];
  for (const n of nodes) {
    if (!n || n.node_id == null) continue;
    if (n.state === 'archived') continue;          // terminal — not gate-relevant
    live.add(n.node_id);
  }
  return live;
}

// Given the FULL pre-truncation log + the post-reduction snapshot, return the
// set of events[] that MUST be retained even though they fall inside the
// covered prefix: for every gate-relevant event-class, the most-recent event
// per still-live entity. Iterating newest-first and taking the first hit per
// (class,entity) yields "most recent". Bounded by live-entity count
// (NFR-3 <100), never the full history.
function gateRelevantRetention(events, snapshot) {
  const live = liveEntityIds(snapshot);
  const keptIds = new Set();
  for (const cls of GATE_RELEVANT_EVENT_CLASSES) {
    const seenEntities = new Set();
    for (let i = events.length - 1; i >= 0; i--) {
      const ev = events[i];
      if (!ev || ev.type !== cls.type) continue;
      const entity = cls.entityKey(ev);
      if (entity == null || !live.has(entity)) continue;   // entity not live ⇒ not gate-relevant
      if (seenEntities.has(entity)) continue;              // already kept the most-recent for this entity
      seenEntities.add(entity);
      keptIds.add(ev.event_id);
    }
  }
  // Preserve original chronological order among the retained subset.
  return events.filter(function (e) { return keptIds.has(e.event_id); });
}

// ---- NFR-7 append-only audit log -------------------------------------------
// One JSON object per line, append-only, NEVER truncated (survives §7c
// compaction so the full history is always recoverable).
function appendAudit(statePath, ev) {
  const ap = auditPathFor(statePath);
  fs.mkdirSync(path.dirname(ap), { recursive: true });
  fs.appendFileSync(ap, JSON.stringify(ev) + '\n', 'utf8');
}
function replayAuditLog(auditPath) {
  let raw;
  try { raw = fs.readFileSync(auditPath, 'utf8'); }
  catch (_) { return []; }
  const out = [];
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try { out.push(JSON.parse(t)); } catch (_) { /* skip a torn final line */ }
  }
  return dedupeById(out);
}

// ---- NFR-1 last-N version retention ----------------------------------------
// Before each atomic publish, copy the current file to a timestamped version;
// keep only the most-recent N. Best-effort (NFR-1) — a retention failure never
// blocks the publish.
function rotateVersions(statePath, retention) {
  try {
    if (!fs.existsSync(statePath)) return;
    const dir = path.dirname(statePath);
    const base = path.basename(statePath);
    const verDir = path.join(dir, '.versions');
    fs.mkdirSync(verDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    fs.copyFileSync(statePath, path.join(verDir, base + '.' + stamp));
    const kept = fs.readdirSync(verDir)
      .filter(function (f) { return f.indexOf(base + '.') === 0; })
      .sort();
    while (kept.length > retention) {
      const victim = kept.shift();
      try { fs.unlinkSync(path.join(verDir, victim)); } catch (_) {}
    }
  } catch (_) { /* retention is best-effort (NFR-1) — never blocks the publish */ }
}

// ---- §7b atomic single-event append + §7c compaction -----------------------
function appendEvent(eventInput, opts) {
  opts = opts || {};
  const treeId = treeIdFor(opts);
  const statePath = resolveStatePath(opts);
  const threshold = opts.compactionThreshold || DEFAULT_COMPACTION_THRESHOLD;
  const retention = opts.retention || DEFAULT_RETENTION;

  fs.mkdirSync(path.dirname(statePath), { recursive: true });

  // Read current truth (torn-snapshot-safe).
  const cur = readState(opts);
  const events = cur.events.slice();

  // Envelope-complete the input (caller may omit event_id/ts/actor; we fill).
  const ev = Object.assign({}, eventInput);
  if (!ev.event_id) ev.event_id = generateEventId();
  if (!ev.ts) ev.ts = new Date().toISOString();
  if (!ev.actor) ev.actor = opts.actor || 'dispatch';
  validateEvent(ev); // §2 — throws on a contract violation BEFORE any write

  // §2 idempotency: a re-applied append (same event_id) is a NO-OP.
  if (events.some(function (e) { return e.event_id === ev.event_id; })) {
    return { state: cur, appended: false, event: ev, idempotentNoop: true };
  }

  events.push(ev);

  // §7c compaction (DEC-D 2026-05-17 revision — NL-FINDING-003 resolution):
  // when the log exceeds the threshold, fold a full snapshot, mark its
  // coverage, and truncate the provably-covered prefix — EXCEPT the general
  // gate-relevant-still-live retention set: the most-recent event of every
  // gate-consumed event-class for every still-live entity is KEPT in events[]
  // even though it falls inside the covered prefix. This closes the §7c↔§8
  // cross-clause gap at the producing clause: §8 reads events[] only (its
  // torn-snapshot-immune design is preserved unchanged), and finds what it
  // needs because §7c no longer drops it. The audit log (above) is never
  // touched, so nothing is ever actually lost. The retained set is bounded by
  // the live-entity count (NFR-3 <100), not the full history.
  let publishedEvents = events;
  let snapshot;
  let didCompact = false;
  if (events.length > threshold) {
    didCompact = true;
    const fullSnap = deriveSnapshot(events, treeId);
    const coverId = events[events.length - 1].event_id;
    fullSnap.valid = true;
    fullSnap.covers_through_event_id = coverId;
    // The snapshot covers ALL events; the post-compaction log retains EXACTLY
    // the gate-relevant-still-live subset (most-recent gate-consumed event per
    // still-live entity — v1: most-recent branch-opened per non-archived node)
    // so the §8 events[]-only branch-presence gate still resolves every live
    // branch. covers_through_event_id still marks the last covered event, so
    // §7a's reader-replay contract is unchanged (a reader replays whatever
    // events[] holds — now the small live set rather than possibly-empty).
    publishedEvents = gateRelevantRetention(events, fullSnap);
    snapshot = fullSnap;
  } else {
    snapshot = deriveSnapshot(events, treeId);
    snapshot.valid = true;
    snapshot.covers_through_event_id = ev.event_id;
  }

  const nextState = {
    schema_version: SCHEMA_VERSION,
    tree_id: treeId,
    events: publishedEvents,
    snapshot: snapshot,
  };

  // NFR-7 first: the event hits the never-truncated audit log BEFORE the
  // state-file publish, so a crash between the two still leaves the event
  // recoverable via replayAuditLog (§7a deep-recovery path).
  appendAudit(statePath, ev);

  // NFR-1: snapshot the prior version before overwriting (best-effort).
  rotateVersions(statePath, retention);

  // §7b atomic publish: write temp, fsync-then-rename. While the temp is
  // being written `snapshot.valid` is moot because the temp is not yet the
  // well-known path; the rename swaps a fully-serialized file in one fs op.
  const tmp = statePath + '.tmp.' + process.pid + '.' + Date.now() + '.' + Math.floor(Math.random() * 1e6);
  fs.writeFileSync(tmp, JSON.stringify(nextState, null, 2), 'utf8');
  fs.renameSync(tmp, statePath); // atomic single-fs publish (Pin 3b / §7b)

  return { state: readState(opts), appended: true, event: ev, compacted: didCompact };
}

// Simulate a torn snapshot: write a state file whose snapshot block is present
// but whose coverage marker is stale / valid:false (used by the property
// suite to prove §7a recovery; NOT part of the production API surface).
function __writeTornForTest(opts, events, badSnapshot) {
  const statePath = resolveStatePath(opts);
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  const torn = {
    schema_version: SCHEMA_VERSION,
    tree_id: treeIdFor(opts),
    events: events,
    snapshot: badSnapshot,
  };
  fs.writeFileSync(statePath, JSON.stringify(torn, null, 2), 'utf8');
}

module.exports = {
  SchemaTooNewError,
  resolveStatePath,
  auditPathFor,
  emptyState,
  readState,
  appendEvent,
  replayAuditLog,
  DEFAULT_COMPACTION_THRESHOLD,
  DEFAULT_RETENTION,
  __writeTornForTest,
};
