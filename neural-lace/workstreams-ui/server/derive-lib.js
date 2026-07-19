'use strict';
// server/derive-lib.js — requireable local-disk derivation library.
//
// EXTRACTED from server.js (cockpit-v2-push-materialized-store plan, Task 2,
// amendment A4 — binding): server.js's module load unconditionally binds an
// HTTP port (`server.listen(PORT, HOST, ...)`, server.js's bottom section)
// and its own single-instance guard calls `process.exit(0)` SILENTLY on
// EADDRINUSE (server.js's `server.on('error', ...)` handler) — a plain
// `require('./server.js')` from a CLI (the exporter, server/export-state.js)
// run alongside a LIVE cockpit server would exit 0 having exported NOTHING,
// while looking like success. This module carries every pure-disk-read /
// derive function both server.js's HTTP handlers and the exporter need, with
// ZERO side effects at require time — no listen(), no timers, no child
// spawns until a function is actually called.
//
// Behavior-identical extraction: every function below is the SAME logic that
// lived in server.js before this refactor; server.js now requires this
// module and calls straight through (no shape change). server.selftest.js's
// existing full black-box HTTP suite is the pre-existing oracle proving this
// refactor changed nothing observable (Prime Directive: a passing suite here
// is necessary, not sufficient — the suite already covers the endpoints this
// module's functions feed).
//
// ONE deliberate signature change from the original server.js bodies:
// computePlanRows(reg, events) read the module-scope `auditor` singleton
// (Task 12's background drift auditor) directly for its badges. That
// singleton is an HTTP-server-only concern this library must not assume
// exists (the exporter has no auditor), so computePlanRows here takes an
// OPTIONAL third arg `getBadgesForAsk(askId) -> array` (default: `() => []`
// — no badges). server.js passes its real `auditor.getBadgesForAsk`; the
// exporter omits it (drift-badge propagation into the export is Task 7's
// concern, out of this task's scope).

const fs = require('fs');
const os = require('os');
const path = require('path');
const projects = require('../config/projects.js');

// ============================================================
// State-dir resolution — mirrors the shell writer libs (progress-log-lib.sh
// / ask-registry.sh / needs-you.sh / dispatch-provenance.sh /
// session-heartbeat-lib.sh) so the SAME env-var overrides sandbox every side
// for a manual walkthrough or an automated test: PROGRESS_LOG_STATE_DIR /
// ASK_REGISTRY_STATE_DIR / DISPATCH_PROVENANCE_STATE_DIR / HEARTBEAT_STATE_DIR,
// else the real $HOME/.claude/state/* paths.
// ============================================================
function progressLogStateDir() {
  return process.env.PROGRESS_LOG_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'progress-logs');
}
function askRegistryFile() {
  const dir = process.env.ASK_REGISTRY_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state');
  return path.join(dir, 'ask-registry.jsonl');
}
function dispatchProvenanceStateDir() {
  return process.env.DISPATCH_PROVENANCE_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'dispatch-provenance');
}
function heartbeatStateDir() {
  return process.env.HEARTBEAT_STATE_DIR ||
    path.join(process.env.HOME || os.homedir(), '.claude', 'state', 'heartbeats');
}

// mainRepoRoot() — best-effort "this repo's root" for resolving plan files
// (and, in server.js, NEEDS-YOU.md/operator-todo.md/backlog.md) when a
// per-ask `repo` field is absent/unreachable. config/projects.js's
// selfRepoRoot() already computes exactly this (the conv-tree-ui repo root,
// worktree-pool-aware) — reused rather than re-derived (no git dependency at
// read time).
function mainRepoRoot() {
  try { return projects.selfRepoRoot(); } catch (_) { return process.cwd(); }
}

// readJsonlLines(file) — best-effort JSONL reader: a missing file or a
// corrupt/unparseable line is silently skipped (readers never crash on one
// bad record).
function readJsonlLines(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); } catch (_) { return []; }
  return raw.split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch (_) { return null; } })
    .filter(Boolean);
}

function readAskRegistry() { return readJsonlLines(askRegistryFile()); }

function readAskEvents(askId) {
  const dir = progressLogStateDir();
  const file = path.join(dir, (askId || 'unlinked') + '.jsonl');
  return readJsonlLines(file);
}

// ----------------------------------------------------------------------
// foldAskRegistry() — read ALL ask-registry.jsonl records and fold them per
// the reader FOLD CONTRACT documented in ask-registry.sh's header:
// "last-write-wins per NON-EMPTY field, in timestamp order" for the mutable
// scalar fields, PLUS an accumulated `plan_slugs[]` (every `plan_linked`
// record's plan_slug, deduped — a list, never a last-wins scalar, since an
// ask can link >1 plan).
// ----------------------------------------------------------------------
function foldAskRegistry() {
  const lines = readAskRegistry().slice().sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const byAsk = {};
  lines.forEach((rec) => {
    if (!rec || !rec.ask_id) return;
    const cur = byAsk[rec.ask_id] || { plan_slugs: [] };
    ['repo', 'project', 'summary', 'verbatim_ref', 'status'].forEach((f) => {
      if (rec[f]) cur[f] = rec[f];
    });
    if (rec.record_type === 'plan_linked' && rec.plan_slug && cur.plan_slugs.indexOf(rec.plan_slug) === -1) {
      cur.plan_slugs.push(rec.plan_slug);
    }
    if (rec.record_type === 'created' && rec.ts) {
      cur.created_ts = rec.ts;
    }
    byAsk[rec.ask_id] = cur;
  });
  Object.keys(byAsk).forEach((k) => {
    if (!byAsk[k].status) byAsk[k].status = 'active';
  });
  return byAsk;
}

function readDispatchProvenanceMarkers() {
  const dir = dispatchProvenanceStateDir();
  let files;
  try { files = fs.readdirSync(dir); } catch (_) { return []; }
  const out = [];
  files.forEach((f) => {
    if (!/\.json$/.test(f)) return;
    try {
      const obj = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (obj) out.push(obj);
    } catch (_) { /* corrupt marker — skip, never crash */ }
  });
  return out;
}

// buildSessions(askId, events, markers) — union of every session this ask's
// own events name (ask_registered/session_attached/task_started) PLUS the
// dispatch-provenance markers matching this ask, each with a lineage edge
// (parent dispatching session -> child_id).
function buildSessions(askId, events, markers) {
  const bySession = {};
  function touch(sid, patch) {
    if (!sid) return;
    const prev = bySession[sid] || { session_id: sid, role: '', resumed_from: '', plan_slug: '', task_id: '' };
    bySession[sid] = Object.assign({}, prev, patch, { role: (patch.role && !prev.role) ? patch.role : (prev.role || patch.role || '') });
  }
  events.forEach((e) => {
    if (!e) return;
    if (e.type === 'ask_registered' && e.session_id) touch(e.session_id, { role: 'origin' });
    if (e.type === 'session_attached' && e.session_id) touch(e.session_id, { role: 'attached', resumed_from: e.session_id === '' ? '' : (bySession[e.session_id] || {}).resumed_from || '' });
    if (e.type === 'task_started' && e.session_id) touch(e.session_id, { role: 'dispatcher', plan_slug: e.plan_slug || '', task_id: e.task_id || '' });
  });
  markers.filter((m) => m && m.ask_id === askId).forEach((m) => {
    if (m.session_id) touch(m.session_id, { role: 'dispatcher', plan_slug: m.plan_slug || '', task_id: m.task_id || '' });
    if (m.child_id && !bySession[m.child_id]) {
      bySession[m.child_id] = {
        session_id: m.child_id, role: 'child', resumed_from: m.session_id || '',
        plan_slug: m.plan_slug || '', task_id: m.task_id || '',
      };
    }
  });
  return Object.keys(bySession).map((k) => bySession[k]);
}

// ----------------------------------------------------------------------
// Plan-file task counting (plan progress bars / drill-down rows) — SEAM
// CLOSED (cockpit-v2 Task 1 + Task 2 integration): this lib delegates to
// plan-parse.js, the ONE canonical grammar (numeric + lettered ids,
// checklist-bullet negatives, archive-aware resolver). The inline
// numeric-only TASK_LINE_RE this block briefly carried during the parallel
// build is gone — a THIRD grammar never ships.
// ----------------------------------------------------------------------
const planParse = require('./plan-parse.js');

// thin wrapper preserving the prior return shape (array | null) for the
// call sites below; loadPlanFile's honest absent/damaged distinction is
// available to consumers via planParse.loadPlanFile directly.
function countPlanTasks(absPath) {
  const r = planParse.loadPlanFile(absPath);
  return r.ok ? r.tasks : null;
}

// resolvePlanAbsPath(repo, slug) — the ask's own `repo` first (its plans
// live at <repo>/docs/plans/<slug>.md), falling back to this repo's own root
// (the common case for harness-development asks). Null when neither
// resolves — the caller renders an honest "no plan file found" empty row
// rather than crashing.
function resolvePlanAbsPath(repo, slug) {
  // ask's own repo first, then this repo's root — the SAME priority order
  // as before; planParse.resolvePlanAbsPath checks docs/plans/ AND
  // docs/plans/archive/ under EACH root (Task 1's M5 fix), so archived
  // plans resolve here too.
  if (repo) {
    const p = planParse.resolvePlanAbsPath(repo, slug);
    if (p) return p;
  }
  return planParse.resolvePlanAbsPath(mainRepoRoot(), slug);
}

// projectDocRefFor(absPath) — best-effort {project, path} pair resolving
// absPath against config/projects.js's loadProjects() map (deepest matching
// root wins), so a caller can drill down through the EXISTING /api/doc +
// /api/doc/open resolver instead of a bespoke absolute-path opener.
function projectDocRefFor(absPath) {
  if (!absPath) return null;
  try {
    const map = projects.loadProjects();
    const target = path.resolve(absPath);
    let best = null, bestLen = -1;
    Object.keys(map).forEach((k) => {
      let root;
      try { root = path.resolve(map[k]); } catch (_) { return; }
      if (target === root || target.indexOf(root + path.sep) === 0) {
        if (root.length > bestLen) { best = k; bestLen = root.length; }
      }
    });
    if (!best) return null;
    const rel = path.relative(path.resolve(map[best]), target).split(path.sep).join('/');
    return { project: best, path: rel };
  } catch (_) { return null; }
}

// computePlanRows(reg, events, getBadgesForAsk) — per linked plan: the real
// checkbox state from the plan FILE (ground truth) crossed with this ask's
// own `task_started`/`task_done` events to derive in-flight (a task is
// in_flight when it has a task_started event and NO task_done event yet, and
// its checkbox is still unflipped) — this is the correct-at-read-time
// snapshot (F1: the exporter calls this at export time and the RESULT is
// what gets shipped, not a live re-join on the peer side).
// `getBadgesForAsk` is OPTIONAL (server.js passes its real
// auditor.getBadgesForAsk; a caller with no auditor — the exporter — omits
// it and gets an empty badge set on every row).
function computePlanRows(reg, events, getBadgesForAsk) {
  const badgesFn = typeof getBadgesForAsk === 'function' ? getBadgesForAsk : () => [];
  const slugs = (reg.plan_slugs || []).slice();
  const startedByPlan = {};
  const doneEvByPlan = {};
  events.forEach((e) => {
    if (!e || !e.plan_slug || !e.task_id) return;
    if (e.type === 'task_started') {
      startedByPlan[e.plan_slug] = startedByPlan[e.plan_slug] || {};
      startedByPlan[e.plan_slug][e.task_id] = true;
    }
    if (e.type === 'task_done') {
      doneEvByPlan[e.plan_slug] = doneEvByPlan[e.plan_slug] || {};
      doneEvByPlan[e.plan_slug][e.task_id] = e.evidence_link || '';
    }
  });
  const askBadges = badgesFn(reg.ask_id);
  return slugs.map((slug) => {
    const absPath = resolvePlanAbsPath(reg.repo, slug);
    const planTasks = absPath ? countPlanTasks(absPath) : null;
    const startedSet = startedByPlan[slug] || {};
    const doneMap = doneEvByPlan[slug] || {};
    const tasks = (planTasks || []).map((t) => {
      const inFlight = !t.done && !!startedSet[t.id] && !doneMap[t.id];
      const rowBadges = askBadges.filter((b) => b.plan_slug === slug && b.task_id === t.id);
      return { id: t.id, done: t.done, in_flight: inFlight, evidence_link: doneMap[t.id] || '', drift_badges: rowBadges };
    });
    return { plan_slug: slug, plan_doc: projectDocRefFor(absPath), tasks: tasks };
  });
}

function aggregatePlanProgress(planRows) {
  let done = 0, inFlight = 0, total = 0;
  planRows.forEach((row) => {
    row.tasks.forEach((t) => {
      total++;
      if (t.done) done++;
      else if (t.in_flight) inFlight++;
    });
  });
  return { done: done, in_flight: inFlight, not_started: total - done - inFlight, total: total };
}

// classifySessions(sessionIds) — reuses hooks/lib/session-heartbeat-lib.sh's
// hb_classify (live|stale|throttled|crashed|missing) via a single batched
// bash spawn. Best-effort: any failure (missing lib, spawn error, timeout)
// resolves an EMPTY map rather than hanging or crashing the caller. This is
// the SERVER's own local-render classification path (unchanged by this
// refactor) — the exporter does NOT use this (see A3c / listRawHeartbeats
// below): a baked live/stale label can't survive transport to a peer
// machine, so the export carries raw timestamps and the peer's reader
// classifies by age against its own receive-time clock.
function sessionHeartbeatLibPath() {
  return process.env.SESSION_HEARTBEAT_LIB ||
    path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'lib', 'session-heartbeat-lib.sh');
}
function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function classifySessions(sessionIds) {
  return new Promise((resolve) => {
    const ids = (sessionIds || []).filter(Boolean);
    if (!ids.length) return resolve({});
    const lib = sessionHeartbeatLibPath();
    if (!fs.existsSync(lib)) return resolve({});
    let bashBin, spawnEnv;
    try {
      const dc = require('./derive-cache.js');
      bashBin = dc.bashBin; spawnEnv = dc.spawnEnv;
    } catch (_) { return resolve({}); }
    const dir = heartbeatStateDir();
    const script = [
      'source ' + shQuote(lib) + ' 2>/dev/null || exit 0',
      'for sid in ' + ids.map(shQuote).join(' ') + '; do',
      '  f=' + shQuote(dir) + '"/$sid.json"',
      '  cls="$(hb_classify "$f" 2>/dev/null)"',
      '  printf "%s\\t%s\\n" "$sid" "${cls:-missing}"',
      'done',
    ].join('\n');
    let settled = false;
    const done = (result) => { if (!settled) { settled = true; resolve(result); } };
    let child;
    const { spawn } = require('child_process');
    try { child = spawn(bashBin(), ['-lc', script], { env: spawnEnv() }); }
    catch (_) { return done({}); }
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('error', () => done({}));
    child.on('close', () => {
      const map = {};
      out.split('\n').forEach((line) => {
        const idx = line.indexOf('\t');
        if (idx === -1) return;
        const sid = line.slice(0, idx).trim();
        const cls = line.slice(idx + 1).trim();
        if (sid) map[sid] = cls || 'missing';
      });
      done(map);
    });
    // 180s budget — this environment's own login-shell bash spawns have
    // been directly measured at 94s and 119s (Windows/Git-Bash + AV
    // scan-on-spawn). A short timeout here would misclassify a merely-slow
    // spawn as "no sessions available" on every request.
    setTimeout(() => done({}), 180000);
  });
}

// listRawHeartbeats() — A3c (BINDING, cockpit-v2-push-materialized-store
// Task 2): enumerate every `<session-id>.json` in heartbeatStateDir() and
// return its RAW parsed fields (schema, session_id, pid, cwd, repo_root,
// worktree_root, branch, model, last_activity_ts, last_event, marker_state)
// — NO hb_classify call, NO live/stale/crashed label. A baked classification
// is a lie by the time it crosses a transport (the peer machine's clock and
// the export's transit time are both unknown to the writer); the ONLY
// honest thing to ship is the timestamp itself, so a reader on the peer
// machine can classify by AGE against its own receive-time clock. Fail-open:
// a missing heartbeat dir or an unreadable/corrupt file is skipped, never a
// crash (mirrors readDispatchProvenanceMarkers' same discipline above).
function listRawHeartbeats() {
  const dir = heartbeatStateDir();
  let files;
  try { files = fs.readdirSync(dir); } catch (_) { return []; }
  const out = [];
  files.forEach((f) => {
    if (!/\.json$/.test(f)) return;
    try {
      const obj = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (obj && obj.session_id) out.push(obj);
    } catch (_) { /* corrupt heartbeat file — skip, never crash */ }
  });
  return out;
}

// ============================================================
// STATUS DERIVATION — Task 1 (cockpit-roadmap-redesign plan, binding:
// architecture-review C5/A4/A6, ux-review C1/C5).
//
// Per-item status is COMPUTED here, never declared: no caller of
// deriveItemStatus reads an ask's own `status` field or a plan's `Status:`
// header as the rendered truth (foldAskRegistry's `status` and
// plan-parse.js's `parsePlanStatus` remain available for OTHER purposes —
// e.g. the Requests ledger's own "open/closed" concept — but neither feeds
// the six-value roadmap enum below). This is the fix for the
// done-renders-ACTIVE defect: an ask fully done (18/18 tasks checked,
// plan `Status: COMPLETED`) whose OWN registry `status` field defaults to
// 'active' forever (foldAskRegistry never flips it) used to render
// whatever the ask's stale `status` field said; deriveItemStatus below
// computes complete/in-progress/stalled/unknown from the plan's REAL
// checkbox ground truth + session activity + the completion-oracle
// instead.
//
// NO DEFAULT-GUESS BRANCH ANYWHERE IN THIS SECTION (selftest-pinned): every
// derivation input failure (an unreadable/damaged plan file, an
// unparseable heartbeat) renders 'unknown' with a reason string; nothing
// here falls through to a bare "not-started"/"in-progress" guess when its
// own inputs could not be read.
// ============================================================

const completionOracle = require('./completion-oracle.js');

// STATUS_VALUES — the six-value enum (C5). 'stalled' and 'unknown' both
// carry a `reason` string (see deriveItemStatus's return shape); neither
// is ever rendered bare.
const STATUS_VALUES = Object.freeze([
  'not-started', 'in-progress', 'merged-deploy-unverified', 'complete', 'stalled', 'unknown',
]);

// STALLED_REASONS — the four named stalled sub-reasons.
const STALLED_REASONS = Object.freeze(['waiting-on-you', 'crashed', 'blocked-on', 'limit-parked']);

// ATTENTION_PRECEDENCE — roll-up badge DISPLAY ORDER (C1 + delta
// adjudication (b)): waiting-on-you > crashed > blocked-on > limit-parked >
// unknown. Precedence governs which badge sorts FIRST when an ancestor's
// subtree carries more than one attention class — it never governs which
// one is SHOWN: rollUpAttentionBadges (below) emits one counted badge per
// class actually present, always (delta R4's multiplicity law — a higher
// class never masks a lower one).
const ATTENTION_PRECEDENCE = Object.freeze(['waiting-on-you', 'crashed', 'blocked-on', 'limit-parked', 'unknown']);

// activityThresholdsMs() — A6's "T~24h activity window" (the proposal's
// disjunct, restored), env-injectable per this codebase's established
// threshold convention (peer-view.js#thresholds precedent). `activeMs` is
// the tight "still heartbeating" window (default 30min, matching
// session-heartbeat-lib.sh's own OBS_STALE_MIN default so the two
// classifiers agree on what "fresh" means); `activityWindowMs` is the
// WIDE grace window past which a quiet session is presumed genuinely gone
// — wide specifically so an AV-pressure throttle or a long API-retry pause
// (session-heartbeat-lib.sh's own throttled/stale states) cannot flap a
// long-running build between in-progress and "stalled: crashed" (F6).
function activityThresholdsMs() {
  return {
    activeMs: Number(process.env.COCKPIT_SESSION_ACTIVE_MIN || 30) * 60 * 1000,
    activityWindowMs: Number(process.env.COCKPIT_SESSION_ACTIVITY_WINDOW_MIN || 24 * 60) * 60 * 1000,
  };
}

// classifyHeartbeatAge(ageMs, th) -> 'live' | 'quiet' | 'crashed'
//
// PURE age-only classification (A6: NO pid check, NO transcript read, NO
// spawn — safe on any GET path). Deliberately coarser than
// session-heartbeat-lib.sh's hb_classify (live/throttled/stale/crashed/
// missing — see that lib's own header): hb_classify's throttled-vs-stale
// distinction needs a live pid check + a transcript-tail read, both of
// which are either a spawn or an unproven cross-platform syscall on this
// estate (that lib's own header documents the MSYS pid-table caveat).
// 'quiet' folds throttled+stale together — both mean "the heartbeat has
// gone quiet; we cannot (and must not try to) prove why" — and is
// reported as STILL in-progress, never stalled: the activity window is
// exactly what keeps a merely-quiet heartbeat from flapping to
// "stalled: crashed" (F6's AV-pressure scenario). Only a heartbeat OLDER
// than the activity window renders 'crashed'.
function classifyHeartbeatAge(ageMs, th) {
  if (ageMs == null || isNaN(ageMs)) return 'crashed'; // no usable age -> never a guessed "live"
  if (ageMs <= th.activeMs) return 'live';
  if (ageMs <= th.activityWindowMs) return 'quiet';
  return 'crashed';
}

// sessionActivityForIds(sessionIds, heartbeats, nowMs, th) -> 'live' |
// 'quiet' | 'crashed' | 'no-heartbeat'
//
// Given the session ids attached to ONE roadmap item (its task_started /
// dispatch-provenance sessions), finds the FRESHEST matching raw heartbeat
// (from listRawHeartbeats(), passed in by the caller — this function never
// reads disk itself) and classifies its age. 'no-heartbeat' — none of the
// item's sessions has ANY heartbeat file — is a legitimate NAMED outcome,
// not a derivation failure: listRawHeartbeats() already fails open on a
// missing/unreadable heartbeat dir (see that function's own header), so an
// empty match here honestly means "no live signal was ever found for this
// item", which the caller treats as crashed (conservative: an in-flight
// item with zero activity evidence is never rendered as "in-progress" by
// default).
function sessionActivityForIds(sessionIds, heartbeats, nowMs, th) {
  const ids = {};
  (sessionIds || []).forEach((sid) => { if (sid) ids[sid] = true; });
  if (!Object.keys(ids).length) return 'no-heartbeat';
  let freshest = null;
  (heartbeats || []).forEach((hb) => {
    if (!hb || !ids[hb.session_id]) return;
    const ts = Date.parse(hb.last_activity_ts);
    if (isNaN(ts)) return;
    if (freshest === null || ts > freshest) freshest = ts;
  });
  if (freshest === null) return 'no-heartbeat';
  return classifyHeartbeatAge(nowMs - freshest, th);
}

// deriveStalledReason(signals) -> one of STALLED_REASONS | null
//
// Per-item single-reason selection, using the SAME precedence order as the
// roll-up law (ATTENTION_PRECEDENCE) so a leaf's own reason and its
// ancestors' rolled-up badges never disagree about which class "wins" when
// more than one signal is true for the same item. `signals` is a plain
// object the CALLER supplies; this task wires a REAL data source only for
// `crashed` (sessionActivityForIds, above, backed by listRawHeartbeats).
// `waitingOnYouId` (needs-you ledger cross-reference — task 4's Inbox
// context contract), `blockedOnTaskId` (predecessor dependency — no such
// field exists in the registry today, F7-class gap), and
// `limitParkedUntil` (session-resumer park state) have NO reader/writer at
// this layer yet; they are accepted here as an HONEST, explicit extension
// point (Chesterton's-Fence-respecting: this function does not invent a
// mechanism for them) so tasks 2-4 wire real signals in once their own
// data lands, rather than this task re-deriving them speculatively.
function deriveStalledReason(signals) {
  signals = signals || {};
  if (signals.waitingOnYouId) return 'waiting-on-you';
  if (signals.crashed) return 'crashed';
  if (signals.blockedOnTaskId) return 'blocked-on';
  if (signals.limitParkedUntil) return 'limit-parked';
  return null;
}

// deriveItemStatus(input) -> { status, reason, oracle_class?, overridden? }
//
// THE ONE STATUS FUNCTION every roadmap item (a plan-level row or a
// task-level row) calls. See the section header for the no-default-guess
// invariant. Input fields (all optional except where noted):
//
//   planLoad          - the loadPlanFile() result for the OWNING plan, when
//                        this item is plan-backed (null/omitted for an
//                        item with no plan file at all, e.g. an
//                        un-plan-linked ask — that is NOT a failure, just
//                        "not applicable", so it is not checked here).
//                        `{ok:false}` (absent OR damaged) IS a genuine
//                        derivation-input failure -> unknown.
//   done               - bool (required): the item's own ground-truth
//                        checkbox/completion state.
//   startedEvent       - bool: a task_started (or equivalent) event exists
//                        with no matching task_done — "this began".
//   mergedAtMs         - number|null: this item's merge/ship timestamp.
//   projectKey         - string: resolves the completion-oracle class.
//   deployReadyAtMs    - number|null: an already-collected deploy signal
//                        (see completion-oracle.js — never collected here).
//   overrideComplete   - bool: a labeled manual "done" override (A4).
//   sessionIds         - string[]: sessions attached to this item.
//   heartbeats         - the caller's ALREADY-READ listRawHeartbeats()
//                        array (read ONCE per request, passed to every
//                        item's derivation — this function never touches
//                        disk).
//   nowMs              - number (defaults to Date.now(); pass explicitly
//                        for deterministic tests).
//   thresholds         - override for activityThresholdsMs() (tests).
//   stalledSignals     - see deriveStalledReason.
function deriveItemStatus(input) {
  input = input || {};

  // ---- unknown: a genuine derivation-input failure, never a guessed
  // bucket (C5). Checked FIRST — every other branch below assumes its own
  // inputs are at least readable.
  if (input.planLoad && input.planLoad.ok === false) {
    return { status: 'unknown', reason: 'plan parse failed (' + input.planLoad.reason + ')' };
  }

  const th = input.thresholds || activityThresholdsMs();
  const nowMs = typeof input.nowMs === 'number' ? input.nowMs : Date.now();

  // ---- done/merged: the completion-oracle decides complete vs the
  // distinct merged-deploy-unverified state (A4). Never silently complete.
  if (input.done) {
    const oracleClass = completionOracle.oracleClassForProject(input.projectKey);
    const evald = completionOracle.evaluateComplete({
      oracleClass: oracleClass,
      mergedAtMs: input.mergedAtMs != null ? input.mergedAtMs : null,
      deployReadyAtMs: input.deployReadyAtMs != null ? input.deployReadyAtMs : null,
      overrideComplete: !!input.overrideComplete,
    });
    return {
      status: evald.state, // 'complete' | 'merged-deploy-unverified'
      reason: null,
      oracle_class: oracleClass,
      overridden: evald.overridden,
    };
  }

  // ---- not-started: no start signal at all.
  if (!input.startedEvent) {
    return { status: 'not-started', reason: null };
  }

  // ---- in-flight: classify by session activity (A6 — pure-JS age, no
  // spawn, the T~24h window absorbs AV-pressure/API-throttle quiet spells).
  const activity = sessionActivityForIds(input.sessionIds, input.heartbeats || [], nowMs, th);
  if (activity === 'live' || activity === 'quiet') {
    return { status: 'in-progress', reason: null };
  }

  // ---- stalled: derive the reason. `crashed` is real here (heartbeat-
  // backed); the other three ride whatever the caller supplied (see
  // deriveStalledReason) and fall back to 'crashed' — the one reason this
  // task can always prove — when nothing more specific is known.
  const reason = deriveStalledReason(Object.assign({}, input.stalledSignals, {
    crashed: activity === 'crashed' || activity === 'no-heartbeat',
  }));
  return { status: 'stalled', reason: reason || 'crashed' };
}

// attentionClassOf(item) -> a member of ATTENTION_PRECEDENCE | null
//
// The attention class a single derived-status item itself contributes to
// its ancestors' roll-up (a stalled item's own reason, or 'unknown' for an
// unknown-status item). Applies to EVERY leaf-derived attention signal
// (C1: "audited against the law, not just stalled") — an item that is
// merely not-started/in-progress/complete/merged-deploy-unverified
// contributes nothing.
function attentionClassOf(item) {
  if (!item) return null;
  if (item.status === 'stalled' && item.reason) return item.reason;
  if (item.status === 'unknown') return 'unknown';
  return null;
}

// rollUpAttentionBadges(rows) -> [{class, count}, ...] sorted by
// ATTENTION_PRECEDENCE, one entry per class actually present.
//
// ROLL-UP LAW (C1) + MULTIPLICITY (delta R4): an ancestor shows ONE badge
// PER attention class present anywhere in its subtree, each counted;
// precedence governs DISPLAY ORDER ONLY, never selection — a higher class
// never masks/replaces a lower one. `rows` is the array of this node's
// IMMEDIATE children, each already carrying its OWN derived
// `{status, reason}` (from deriveItemStatus) PLUS whatever `badges` array
// its OWN children already rolled up into it — so calling this function
// bottom-up (leaves first, each level folding its children's badges in)
// propagates a grandchild's attention state to EVERY collapsed ancestor,
// not just its immediate parent (the plan's Edge Cases: "a collapsed
// ancestor of a stalled/unknown descendant: roll-up badge always
// renders").
function rollUpAttentionBadges(rows) {
  const counts = {};
  (rows || []).forEach((row) => {
    const own = attentionClassOf(row);
    if (own) counts[own] = (counts[own] || 0) + 1;
    (row.badges || []).forEach((b) => {
      if (!b || !b.class) return;
      counts[b.class] = (counts[b.class] || 0) + (b.count || 0);
    });
  });
  return ATTENTION_PRECEDENCE
    .filter((cls) => counts[cls] > 0)
    .map((cls) => ({ class: cls, count: counts[cls] }));
}

module.exports = {
  // path resolvers
  progressLogStateDir,
  askRegistryFile,
  dispatchProvenanceStateDir,
  heartbeatStateDir,
  mainRepoRoot,
  // registry / event / marker readers
  readJsonlLines,
  readAskRegistry,
  readAskEvents,
  foldAskRegistry,
  readDispatchProvenanceMarkers,
  buildSessions,
  // plan derivation

  countPlanTasks,
  resolvePlanAbsPath,
  projectDocRefFor,
  computePlanRows,
  aggregatePlanProgress,
  // session classification (server-local) + raw export read
  sessionHeartbeatLibPath,
  shQuote,
  classifySessions,
  listRawHeartbeats,
  // status derivation (Task 1, cockpit-roadmap-redesign)
  STATUS_VALUES,
  STALLED_REASONS,
  ATTENTION_PRECEDENCE,
  activityThresholdsMs,
  classifyHeartbeatAge,
  sessionActivityForIds,
  deriveStalledReason,
  deriveItemStatus,
  attentionClassOf,
  rollUpAttentionBadges,
};

// ============================================================
// --self-test — sandboxed fixture suite for the Task-1 status-derivation
// surface (unit-level; a real-data livesmoke run against this checkout's
// own ask-registry.jsonl + archived plan is the separate end-to-end proof
// — see the task's report-back evidence, not this fixture suite).
// ============================================================
async function selfTest() {
  let passed = 0, failed = 0;
  function ok(name, cond, detail) {
    if (cond) { passed++; console.log('  PASS: ' + name); }
    else { failed++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  const TH = { activeMs: 30 * 60 * 1000, activityWindowMs: 24 * 60 * 60 * 1000 };

  // ---- classifyHeartbeatAge boundaries.
  ok('1. classifyHeartbeatAge: fresh (0ms) -> live', classifyHeartbeatAge(0, TH) === 'live');
  ok('1b. classifyHeartbeatAge: exactly at the active boundary -> live', classifyHeartbeatAge(TH.activeMs, TH) === 'live');
  ok('1c. classifyHeartbeatAge: just past active, well within the window -> quiet (not crashed)',
    classifyHeartbeatAge(TH.activeMs + 1, TH) === 'quiet');
  ok('1d. classifyHeartbeatAge: exactly at the activity-window boundary -> still quiet',
    classifyHeartbeatAge(TH.activityWindowMs, TH) === 'quiet');
  ok('1e. classifyHeartbeatAge: just past the activity window -> crashed',
    classifyHeartbeatAge(TH.activityWindowMs + 1, TH) === 'crashed');
  ok('1f. classifyHeartbeatAge: no usable age (NaN) -> crashed, never a guessed live',
    classifyHeartbeatAge(NaN, TH) === 'crashed' && classifyHeartbeatAge(null, TH) === 'crashed');

  // ---- sessionActivityForIds.
  const now = Date.parse('2026-07-19T12:00:00Z');
  const hbFresh = { session_id: 'sess-a', last_activity_ts: new Date(now - 5 * 60 * 1000).toISOString() };
  const hbOld = { session_id: 'sess-b', last_activity_ts: new Date(now - 48 * 60 * 60 * 1000).toISOString() };
  const hbCorrupt = { session_id: 'sess-c', last_activity_ts: 'not-a-date' };
  ok('2. sessionActivityForIds: matching id with a 5min-old heartbeat -> live',
    sessionActivityForIds(['sess-a'], [hbFresh, hbOld], now, TH) === 'live');
  ok('2b. sessionActivityForIds: matching id with a 48h-old heartbeat -> crashed',
    sessionActivityForIds(['sess-b'], [hbFresh, hbOld], now, TH) === 'crashed');
  ok('2c. sessionActivityForIds: freshest-of-several wins (sess-a is fresh even though sess-b is ancient)',
    sessionActivityForIds(['sess-a', 'sess-b'], [hbFresh, hbOld], now, TH) === 'live');
  ok('2d. sessionActivityForIds: no session ids at all -> no-heartbeat, never a crash',
    sessionActivityForIds([], [hbFresh], now, TH) === 'no-heartbeat');
  ok('2e. sessionActivityForIds: ids given but none match any heartbeat -> no-heartbeat',
    sessionActivityForIds(['sess-zzz'], [hbFresh, hbOld], now, TH) === 'no-heartbeat');
  ok('2f. sessionActivityForIds: an unparseable last_activity_ts is skipped, never crashes the caller',
    sessionActivityForIds(['sess-c'], [hbCorrupt], now, TH) === 'no-heartbeat');

  // ---- deriveStalledReason precedence.
  ok('3. deriveStalledReason: waiting-on-you outranks every other signal',
    deriveStalledReason({ waitingOnYouId: 'ny-1', crashed: true, blockedOnTaskId: '2', limitParkedUntil: 'x' }) === 'waiting-on-you');
  ok('3b. deriveStalledReason: crashed outranks blocked-on/limit-parked',
    deriveStalledReason({ crashed: true, blockedOnTaskId: '2', limitParkedUntil: 'x' }) === 'crashed');
  ok('3c. deriveStalledReason: blocked-on outranks limit-parked',
    deriveStalledReason({ blockedOnTaskId: '2', limitParkedUntil: 'x' }) === 'blocked-on');
  ok('3d. deriveStalledReason: limit-parked alone is honored',
    deriveStalledReason({ limitParkedUntil: 'x' }) === 'limit-parked');
  ok('3e. deriveStalledReason: no signals at all -> null, never a guessed reason',
    deriveStalledReason({}) === null && deriveStalledReason() === null);

  // ---- deriveItemStatus: unknown (C5 — no default-guess branch).
  const unk = deriveItemStatus({ planLoad: { ok: false, reason: 'damaged' }, done: false });
  ok('4. deriveItemStatus: a damaged plan-load result -> unknown with the reason named, checked BEFORE any other branch',
    unk.status === 'unknown' && /damaged/.test(unk.reason), JSON.stringify(unk));
  const unk2 = deriveItemStatus({ planLoad: { ok: false, reason: 'absent' }, done: true }); // done=true would otherwise short-circuit
  ok('4b. deriveItemStatus: unknown wins even when done:true is also set (input-failure check runs first)',
    unk2.status === 'unknown' && /absent/.test(unk2.reason));

  // ---- deriveItemStatus: not-started.
  const ns = deriveItemStatus({ done: false, startedEvent: false });
  ok('5. deriveItemStatus: not done, never started -> not-started', ns.status === 'not-started' && ns.reason === null);

  // ---- deriveItemStatus: in-progress (live/quiet heartbeat).
  const ip = deriveItemStatus({
    done: false, startedEvent: true, sessionIds: ['sess-a'], heartbeats: [hbFresh], nowMs: now, thresholds: TH,
  });
  ok('6. deriveItemStatus: started + live heartbeat -> in-progress', ip.status === 'in-progress');
  const ipQuiet = deriveItemStatus({
    done: false, startedEvent: true, sessionIds: ['sess-quiet'], nowMs: now, thresholds: TH,
    heartbeats: [{ session_id: 'sess-quiet', last_activity_ts: new Date(now - 2 * 60 * 60 * 1000).toISOString() }],
  });
  ok('6b. deriveItemStatus: started + a QUIET (2h-old, within the 24h window) heartbeat -> STILL in-progress, never stalled (F6 anti-flap)',
    ipQuiet.status === 'in-progress');

  // ---- deriveItemStatus: stalled:crashed (heartbeat past the activity window).
  const stCrashed = deriveItemStatus({
    done: false, startedEvent: true, sessionIds: ['sess-b'], heartbeats: [hbOld], nowMs: now, thresholds: TH,
  });
  ok('7. deriveItemStatus: started + a 48h-old heartbeat (past the activity window) -> stalled:crashed',
    stCrashed.status === 'stalled' && stCrashed.reason === 'crashed', JSON.stringify(stCrashed));
  const stNoHb = deriveItemStatus({ done: false, startedEvent: true, sessionIds: ['sess-nope'], heartbeats: [], nowMs: now, thresholds: TH });
  ok('7b. deriveItemStatus: started but zero heartbeat evidence anywhere -> stalled:crashed (conservative, never a guessed in-progress)',
    stNoHb.status === 'stalled' && stNoHb.reason === 'crashed');

  // ---- deriveItemStatus: stalled with a caller-supplied reason outranking crashed.
  const stWaiting = deriveItemStatus({
    done: false, startedEvent: true, sessionIds: ['sess-b'], heartbeats: [hbOld], nowMs: now, thresholds: TH,
    stalledSignals: { waitingOnYouId: 'ny-42' },
  });
  ok('8. deriveItemStatus: a waiting-on-you signal outranks the heartbeat-derived crashed reason',
    stWaiting.status === 'stalled' && stWaiting.reason === 'waiting-on-you');

  // ---- deriveItemStatus: done -> complete-oracle decides the state (A4).
  const doneHarness = deriveItemStatus({ done: true, projectKey: 'neural-lace', mergedAtMs: 1000 });
  ok('9. deriveItemStatus: done under the harness project (merged-is-deployed) -> complete, complete-PROVEN',
    doneHarness.status === 'complete' && doneHarness.oracle_class === 'merged-is-deployed', JSON.stringify(doneHarness));
  const doneNoSignal = deriveItemStatus({ done: true, projectKey: 'some-unconfigured-project', mergedAtMs: 1000 });
  ok('10. deriveItemStatus: done under no-signal -> merged-deploy-unverified, OUTSIDE Complete, never a silent complete',
    doneNoSignal.status === 'merged-deploy-unverified' && doneNoSignal.oracle_class === 'no-signal');
  const doneOverride = deriveItemStatus({ done: true, projectKey: 'some-unconfigured-project', mergedAtMs: 1000, overrideComplete: true });
  ok('11. deriveItemStatus: an explicit labeled override renders complete even under no-signal',
    doneOverride.status === 'complete' && doneOverride.overridden === true);

  // ---- No-default-guess sweep: every scenario above returned a value from
  // the six-value enum — a class-level check, not just per-scenario.
  const allResults = [unk, unk2, ns, ip, ipQuiet, stCrashed, stNoHb, stWaiting, doneHarness, doneNoSignal, doneOverride];
  ok('12. every deriveItemStatus result above is one of the six named STATUS_VALUES (no stray/guessed status string)',
    allResults.every((r) => STATUS_VALUES.indexOf(r.status) !== -1),
    JSON.stringify(allResults.map((r) => r.status)));

  // ---- attentionClassOf.
  ok('13. attentionClassOf: a stalled item reports its own reason', attentionClassOf({ status: 'stalled', reason: 'blocked-on' }) === 'blocked-on');
  ok('13b. attentionClassOf: an unknown item reports "unknown"', attentionClassOf({ status: 'unknown', reason: 'plan parse failed' }) === 'unknown');
  ok('13c. attentionClassOf: complete/in-progress/not-started/merged-deploy-unverified contribute nothing',
    attentionClassOf({ status: 'complete' }) === null && attentionClassOf({ status: 'in-progress' }) === null &&
    attentionClassOf({ status: 'not-started' }) === null && attentionClassOf({ status: 'merged-deploy-unverified' }) === null);

  // ---- rollUpAttentionBadges: one badge per class, precedence-ordered,
  // MULTIPLICITY (delta R4) — a higher class never masks a lower one.
  const rows14 = [
    { status: 'stalled', reason: 'limit-parked' },
    { status: 'stalled', reason: 'crashed' },
    { status: 'unknown', reason: 'plan parse failed' },
    { status: 'complete' }, // contributes nothing
  ];
  const badges14 = rollUpAttentionBadges(rows14);
  ok('14. rollUpAttentionBadges: THREE distinct classes present -> three badges, none masked by precedence',
    badges14.length === 3, JSON.stringify(badges14));
  ok('14b. rollUpAttentionBadges: badge order follows ATTENTION_PRECEDENCE (crashed before limit-parked before unknown), not input order',
    badges14.map((b) => b.class).join(',') === 'crashed,limit-parked,unknown', JSON.stringify(badges14));
  ok('14c. rollUpAttentionBadges: each badge is counted (1 each here)', badges14.every((b) => b.count === 1));

  // ---- rollUpAttentionBadges: counted multiplicity — TWO items sharing the
  // same class fold into ONE badge with count:2, not two separate badges.
  const rows15 = [
    { status: 'stalled', reason: 'waiting-on-you' },
    { status: 'stalled', reason: 'waiting-on-you' },
    { status: 'stalled', reason: 'crashed' },
  ];
  const badges15 = rollUpAttentionBadges(rows15);
  ok('15. rollUpAttentionBadges: two waiting-on-you leaves fold into ONE counted badge (count:2), plus one crashed badge',
    badges15.length === 2 && badges15[0].class === 'waiting-on-you' && badges15[0].count === 2 &&
    badges15[1].class === 'crashed' && badges15[1].count === 1, JSON.stringify(badges15));

  // ---- rollUpAttentionBadges: bottom-up propagation through TWO levels — a
  // grandchild's attention state reaches the grandparent, not just the
  // immediate parent (Edge Cases: "a collapsed ancestor ... always renders").
  const grandchild = { status: 'stalled', reason: 'waiting-on-you' };
  const childBadges = rollUpAttentionBadges([grandchild]); // child folds its own child in
  const child = { status: 'in-progress', badges: childBadges }; // the child itself is healthy
  const grandparentBadges = rollUpAttentionBadges([child]); // grandparent folds the child in
  ok('16. rollUpAttentionBadges: a grandchild\'s waiting-on-you state reaches the grandparent via bottom-up folding',
    grandparentBadges.length === 1 && grandparentBadges[0].class === 'waiting-on-you' && grandparentBadges[0].count === 1,
    JSON.stringify({ childBadges: childBadges, grandparentBadges: grandparentBadges }));

  // ---- rollUpAttentionBadges: an empty/healthy subtree rolls up to zero
  // badges, never a phantom entry.
  ok('17. rollUpAttentionBadges: an all-healthy subtree rolls up to zero badges',
    rollUpAttentionBadges([{ status: 'complete' }, { status: 'in-progress' }, { status: 'not-started' }]).length === 0);

  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  return failed === 0 ? 0 : 1;
}

if (require.main === module) {
  if (process.argv.indexOf('--self-test') !== -1) {
    selfTest().then((code) => process.exit(code));
  } else {
    process.stdout.write('derive-lib.js is a requireable library — run with --self-test, or require() it directly.\n');
    process.exit(0);
  }
}
