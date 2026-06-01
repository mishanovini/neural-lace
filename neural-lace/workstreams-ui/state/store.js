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
const crypto = require('crypto');
const {
  SCHEMA_VERSION, SCHEMA_TOO_NEW_MESSAGE, generateEventId, validateEvent,
} = require('./schema.js');
const { deriveSnapshot } = require('./reducer.js');

// ---- DEC-D (d) snapshot-integrity attestation ------------------------------
// ADR-032 §8 r2 GENERAL PRIMITIVE (Misha-confirmed 2026-05-17; supersedes the
// earlier (b)): a snapshot is trustworthy iff its canonical-JSON sha256 equals
// the `hash` of the most-recent `snapshot-committed` record in `events[]`.
// Every snapshot write atomically appends that record as part of the SAME
// write-temp-then-rename publish (NOT a separate step). Any future gate gets
// snapshot-trust for free via the same attestation — there are NO per-gate
// compaction carve-outs, ever. This replaces the (b) gateRelevantRetention
// approach entirely (it dissolved NL-FINDING-004 by removing the marker-vs-
// published-subset invariant the (b) attempt broke).
const SNAPSHOT_COMMITTED_TYPE = 'snapshot-committed';

// Deterministic serialization: recursively emit object keys in sorted order so
// the writer (here) and the §8 verifier produce byte-identical input to
// sha256. This determinism is LOAD-BEARING — if the two ever canonicalize
// differently the hashes never match and every snapshot reads as torn.
function canonicalJSON(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) {
    return '[' + value.map(canonicalJSON).join(',') + ']';
  }
  const keys = Object.keys(value).sort();
  const parts = [];
  for (const k of keys) {
    if (value[k] === undefined) continue; // JSON.stringify drops undefined; mirror it
    parts.push(JSON.stringify(k) + ':' + canonicalJSON(value[k]));
  }
  return '{' + parts.join(',') + '}';
}

// sha256 of the snapshot serialized with canonical key ordering. Prefixed
// `sha256:` so the algorithm is self-describing in the on-disk record.
function hashSnapshot(snapshot) {
  const digest = crypto.createHash('sha256')
    .update(canonicalJSON(snapshot), 'utf8')
    .digest('hex');
  return 'sha256:' + digest;
}

// Build the attestation meta-record for a snapshot. Called as part of any
// commit that updates the snapshot (see appendEvent's atomic publish). It is
// NOT a domain event: it is absent from EVENT_TYPES, the reducer skips it
// (forward-tolerant default branch), and the §7a coverage marker ignores it.
function attestSnapshot(snapshot) {
  return {
    event_id: generateEventId(),
    type: SNAPSHOT_COMMITTED_TYPE,
    hash: hashSnapshot(snapshot),
    at: Date.now(),
    ts: new Date().toISOString(),
    actor: 'system',
  };
}

// §8 r2 verify-then-read primitive. Given a parsed on-disk state, recompute the
// snapshot's canonical-JSON hash and compare it to the hash of the MOST-RECENT
// `snapshot-committed` record in events[]. Match ⇒ the snapshot is verified-
// trustworthy and a gate may read `snapshot.nodes` for branch-presence.
// Mismatch / no attestation / no snapshot ⇒ torn ⇒ the gate refuses and the
// existing §7a torn-snapshot-recovery engages. This is the general primitive:
// any future gate calls this once and gets snapshot-trust for free.
function verifySnapshotAttested(parsed) {
  if (!parsed || !parsed.snapshot || parsed.snapshot.valid !== true) {
    return { verified: false, reason: 'no-valid-snapshot' };
  }
  const events = Array.isArray(parsed.events) ? parsed.events : [];
  let latest = null;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i] && events[i].type === SNAPSHOT_COMMITTED_TYPE) { latest = events[i]; break; }
  }
  if (!latest) return { verified: false, reason: 'no-attestation' };
  const expected = hashSnapshot(parsed.snapshot);
  if (latest.hash !== expected) {
    return { verified: false, reason: 'hash-mismatch', expected: expected, found: latest.hash };
  }
  return { verified: true, hash: expected };
}

// The §7a coverage marker tracks the last DOMAIN event, never the attestation
// meta-record. This helper returns the events[] with snapshot-committed
// records stripped — used for the reducer, dedupe, and the marker comparison.
function domainEvents(events) {
  return events.filter(function (e) { return e && e.type !== SNAPSHOT_COMMITTED_TYPE; });
}

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
  let rawEvents = Array.isArray(parsed.events) ? parsed.events : [];
  // domain events (no snapshot-committed meta-records) feed the reducer +
  // the §7a marker. A fully-torn / empty DOMAIN log triggers audit replay.
  let domain = dedupeById(domainEvents(rawEvents));
  if (parsed.__corrupt || domain.length === 0) {
    // Fully-torn state file: reconstruct from the append-only audit log
    // (NFR-7 — never truncated, so it is the deepest recoverable truth).
    const fromAudit = replayAuditLog(auditPathFor(statePath));
    if (fromAudit.length > 0) domain = dedupeById(domainEvents(fromAudit));
  }

  const snap = parsed.snapshot;
  const lastId = domain.length ? domain[domain.length - 1].event_id : null;
  // §7a marker check (unchanged in spirit): the cached snapshot may be trusted
  // only if valid AND its coverage marker equals the last DOMAIN event's id
  // (the snapshot-committed meta-record is never the marker target).
  const markerOk = snap && snap.valid === true
    && snap.covers_through_event_id === lastId;
  // DEC-D (d) STRENGTHENING: the §7a marker alone cannot detect a snapshot
  // whose CONTENT was corrupted without touching the marker (a torn / tampered
  // snapshot block). The attestation closes that — trust the cache only if the
  // marker holds AND the snapshot's canonical-JSON hash matches the most-recent
  // snapshot-committed record. Mismatch ⇒ torn ⇒ discard + replay (§7a). This
  // is the general primitive: §8 (and any future gate) calls
  // verifySnapshotAttested on the RAW file; readState applies the same check so
  // a tampered cache is never silently trusted via the bare marker.
  const att = verifySnapshotAttested(parsed);
  const trustCache = markerOk && att.verified === true;

  let snapshot;
  if (trustCache) {
    snapshot = snap;                       // marker + attestation prove it
  } else {
    // §7a mandatory: discard the (untrustworthy / torn / tampered) snapshot
    // and deterministically replay the DOMAIN log.
    snapshot = deriveSnapshot(domain, treeId);
    snapshot.valid = true;
    snapshot.covers_through_event_id = lastId;
  }
  // The returned events[] is DOMAIN-only — the snapshot-committed attestation
  // is an on-disk meta-record, never part of the consumer-facing event log
  // (web/app.js, the property suite, FR-2 cardinality all count domain
  // events). The §8 verifier reads the RAW on-disk file (jq /
  // verifySnapshotAttested over `parsed`), not this return shape, so trust
  // re-derivation is unaffected by stripping the meta-record here.
  return { schema_version: SCHEMA_VERSION, tree_id: treeId, events: domain, snapshot: snapshot };
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

  // Read current truth (torn-snapshot-safe). Strip prior snapshot-committed
  // attestation meta-records: only DOMAIN events accumulate / feed the
  // reducer / count toward the compaction threshold. Exactly one fresh
  // attestation is re-appended at publish time below (it is never carried
  // forward — a stale attestation hash would no longer match the new
  // snapshot anyway).
  const cur = readState(opts);
  const events = domainEvents(cur.events.slice());

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

  // §7c compaction (DEC-D (d) 2026-05-17 — ORIGINAL A2 behavior restored):
  // when the log exceeds the threshold, fold a full snapshot, mark its
  // coverage, and truncate ONLY the provably-covered prefix. There is NO
  // per-gate compaction carve-out (the (b) gateRelevantRetention is removed):
  // the snapshot covers ALL events, so the post-compaction domain log is
  // empty and the marker proves coverage — a reader replays from "nothing
  // after coverId". The audit log (above) is never touched, so nothing is
  // ever actually lost. §8 trust comes from the snapshot-integrity
  // attestation appended below, NOT from retaining events[].
  let publishedEvents = events;
  let snapshot;
  let didCompact = false;
  if (events.length > threshold) {
    didCompact = true;
    const fullSnap = deriveSnapshot(events, treeId);
    const coverId = events[events.length - 1].event_id;
    fullSnap.valid = true;
    fullSnap.covers_through_event_id = coverId;
    // Retain ONLY events strictly after the covered point. The snapshot
    // covers ALL events, so the post-compaction domain log is empty but the
    // marker proves coverage (original A2 §7c semantics — Pin-3a unchanged).
    publishedEvents = [];
    snapshot = fullSnap;
  } else {
    snapshot = deriveSnapshot(events, treeId);
    snapshot.valid = true;
    snapshot.covers_through_event_id = ev.event_id;
  }

  // DEC-D (d): atomically append the snapshot-integrity attestation as part
  // of THIS publish (NOT a separate write). The hash is over the final
  // snapshot object exactly as it will be written. Appending it AFTER the
  // compaction-truncation decision means the freshest snapshot-committed is
  // always the last events[] element and SURVIVES compaction naturally — it
  // is never inside the covered prefix because it is appended post-truncation.
  // It is NOT a domain event (absent from EVENT_TYPES; reducer skips it; the
  // §7a marker tracks the last DOMAIN event id, set above).
  const attestation = attestSnapshot(snapshot);
  publishedEvents = publishedEvents.concat([attestation]);

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
  // DEC-D (d) snapshot-integrity attestation primitive (ADR-032 §8 r2):
  SNAPSHOT_COMMITTED_TYPE,
  canonicalJSON,
  hashSnapshot,
  attestSnapshot,
  verifySnapshotAttested,
};
