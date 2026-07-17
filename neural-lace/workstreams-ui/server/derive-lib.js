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
};
