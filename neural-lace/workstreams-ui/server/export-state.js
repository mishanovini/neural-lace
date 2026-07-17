'use strict';
// server/export-state.js — cockpit-v2-push-materialized-store Task 2: the
// per-machine EXPORT CLI.
//
// Re-derives the cockpit's plan/session state from LOCAL DISK ONLY, at
// export time, via server/derive-lib.js — NEVER via server.js. A4 (BINDING):
// server.js's module load unconditionally binds an HTTP port
// (`server.listen(...)`) and its single-instance guard calls
// `process.exit(0)` SILENTLY on EADDRINUSE; a plain `require('./server.js')`
// from this CLI, run while the real cockpit server is up, would exit 0
// having exported NOTHING while looking like success. Every read below goes
// through derive-lib.js's pure fs functions, so this CLI is safe to run
// whether the cockpit HTTP server is up or down (Scenario H of the self-test
// below proves the "up" case concretely, by actually binding a real server
// instance and exporting alongside it).
//
// Usage:
//   node server/export-state.js                 — one export run
//   node server/export-state.js --self-test      — sandboxed fixture suite
//
// Env:
//   EXPORT_DIR         — REQUIRED (unless --self-test): directory to write
//                        the per-hostname export JSON into. Task 3 (coord
//                        transport) points this at the coord-repo clone;
//                        this task only writes to whatever directory it's
//                        given.
//   EXPORT_HOSTNAME    — override os.hostname() (A5, binding): lets one
//                        machine simulate two peers for the task 8
//                        acceptance drill, and lets this self-test avoid
//                        touching the real machine's hostname.
//   (state-dir overrides — ASK_REGISTRY_STATE_DIR / PROGRESS_LOG_STATE_DIR /
//   DISPATCH_PROVENANCE_STATE_DIR / HEARTBEAT_STATE_DIR — identical to
//   server.js/derive-lib.js's own env vars, so a sandboxed run never touches
//   real machine state.)

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync, spawn } = require('child_process');
const deriveLib = require('./derive-lib.js');

const SCHEMA_VERSION = 1;

// A3ii (BINDING): refresh `exported_at` at least every 60min even when the
// derived content hash is UNCHANGED. Without this, a peer that has gone
// idle (nothing new to export) looks identical to a peer whose exporter
// died — both show a frozen `exported_at`. The keepalive rewrite is what
// lets a reader tell "peer idle" (content steady, exported_at still fresh)
// apart from "peer unreachable" (exported_at stuck past the threshold, plan
// task 4's "peer unreachable since <ts>" state). Also caps idle churn at
// 24 writes/day/machine (1440min / 60min).
const KEEPALIVE_MS = 60 * 60 * 1000;

function hostname() { return process.env.EXPORT_HOSTNAME || os.hostname(); }

// gitField(args, cwd) — best-effort single-line git read. Fail-open: no git
// binary, no .git dir, or any error -> '' (Edge Cases: exporter never
// crashes on a missing/broken git checkout; provenance just carries empty
// fields, which the peer-view reader (task 4) renders honestly rather than
// guessing).
function gitField(args, cwd) {
  try {
    return String(execFileSync('git', args, { cwd: cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })).trim();
  } catch (_) { return ''; }
}

function gitDirty(cwd) {
  try {
    const out = String(execFileSync('git', ['status', '--porcelain'], { cwd: cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
    return out.trim().length > 0;
  } catch (_) { return false; }
}

// provenance() — F3/F8/A2's own writer-side stamp: WHO wrote this (host),
// WHAT tree state it was derived from (branch/head_sha/dirty). Never a
// classification of freshness (that's receive-time, on the reader — F2,
// plan task 4); this is purely "what was true on disk when this ran."
function provenance() {
  const root = deriveLib.mainRepoRoot();
  return {
    hostname: hostname(),
    branch: gitField(['rev-parse', '--abbrev-ref', 'HEAD'], root),
    head_sha: gitField(['rev-parse', 'HEAD'], root),
    dirty: gitDirty(root),
  };
}

// derivePlanRecords() — folds the WHOLE ask registry (fail-open: no
// registry file -> {} -> []), computing plan rows per ask via derive-lib's
// computePlanRows — the SAME event-log join server.js's own /api/ask/<id>
// uses (F1: in_flight is the join RESULT computed NOW, a point-in-time
// snapshot; re-running the join at read time on the peer would need the
// peer to have this machine's progress-log/ask-registry files, which is
// exactly what the export is standing in for). No getBadgesForAsk is
// passed — drift-badge propagation into the export is Task 7's concern
// (C3b), out of this task's scope; rows here simply carry no badges.
//
// Re-keyed from per-ask to per-(repo, slug): the plan file + its task
// events are ground truth regardless of which ask discovered them, so if
// more than one ask links the same plan, the first one folded wins (stable
// because foldAskRegistry's own iteration order is insertion order over
// Object.keys, which for a single export run is deterministic) — a
// duplicate is redundant data, not a conflict to resolve.
function derivePlanRecords() {
  const registry = deriveLib.foldAskRegistry();
  const byKey = {};
  Object.keys(registry).forEach((askId) => {
    const reg = registry[askId];
    reg.ask_id = askId;
    const events = deriveLib.readAskEvents(askId);
    const rows = deriveLib.computePlanRows(reg, events);
    rows.forEach((row) => {
      const key = (reg.repo || '') + '|' + row.plan_slug;
      if (byKey[key]) return; // first-wins — see header note above
      byKey[key] = {
        repo: reg.repo || '',
        plan_slug: row.plan_slug,
        plan_doc: row.plan_doc,
        tasks: row.tasks.map((t) => ({ id: t.id, done: t.done, in_flight: t.in_flight, evidence_link: t.evidence_link })),
        progress: deriveLib.aggregatePlanProgress([row]),
      };
    });
  });
  return Object.keys(byKey).sort().map((k) => byKey[k]);
}

// deriveSessionsBlock() — A3c (BINDING): RAW `last_heartbeat_at` per
// session, role/plan metadata folded in, NEVER a baked live/stale/crashed
// label. classifySessions()'s hb_classify call (derive-lib.js) is for the
// SERVER's own LOCAL render only — a classification computed here would be
// stale-by-construction the moment it crosses the transport (this
// machine's "live" a minute ago says nothing about "live" once a peer reads
// it 20 minutes later); the peer's reader (plan task 4) classifies by AGE
// against ITS OWN receive-time clock instead. Role/plan_slug/task_id
// enrichment reuses derive-lib's buildSessions (the SAME per-ask lineage
// join server.js's /api/ask/<id> uses) across every ask in the registry,
// merged by session_id; heartbeat rows for a session with NO ask lineage
// (e.g. a standalone/orchestrator session) still appear, role/plan blank.
function deriveSessionsBlock() {
  const registry = deriveLib.foldAskRegistry();
  const markers = deriveLib.readDispatchProvenanceMarkers();
  const bySession = {};
  Object.keys(registry).forEach((askId) => {
    const events = deriveLib.readAskEvents(askId);
    deriveLib.buildSessions(askId, events, markers).forEach((s) => {
      bySession[s.session_id] = Object.assign({}, bySession[s.session_id] || {}, s);
    });
  });
  deriveLib.listRawHeartbeats().forEach((hb) => {
    const prev = bySession[hb.session_id] || {
      session_id: hb.session_id, role: '', resumed_from: '', plan_slug: '', task_id: '',
    };
    bySession[hb.session_id] = Object.assign({}, prev, {
      last_heartbeat_at: hb.last_activity_ts || '',
      branch: hb.branch || '',
      repo_root: hb.repo_root || '',
      worktree_root: hb.worktree_root || '',
    });
  });
  return Object.keys(bySession).sort().map((k) => bySession[k]);
}

function buildPayload() {
  return {
    schema_version: SCHEMA_VERSION,
    provenance: provenance(),
    plans: derivePlanRecords(),
    sessions: deriveSessionsBlock(),
  };
}

// stableStringify/contentHash — deterministic (sorted-key) JSON hash of the
// derived payload EXCLUDING exported_at/content_hash themselves (those are
// added by the caller after hashing). The hash-gate's whole point is "did
// anything besides the clock change" (A3ii); sorted keys mean field-order
// jitter (e.g. Object.keys ordering across Node versions) never perturbs it.
function stableStringify(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stableStringify).join(',') + ']';
  const keys = Object.keys(value).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableStringify(value[k])).join(',') + '}';
}
function contentHash(payload) {
  return crypto.createHash('sha256').update(stableStringify(payload)).digest('hex');
}

function exportFilePath(dir) { return path.join(dir, hostname() + '.json'); }

// atomicWriteJson(filePath, obj) — tmp file + rename, the SAME
// discipline every other atomic writer in this codebase uses
// (writeBacklogAtomic / writeOperatorTodoAtomic in server.js): a reader
// polling this path (task 4/coord-pull) never observes a torn/partial file,
// because it only ever sees the old inode or the fully-written new one.
function atomicWriteJson(filePath, obj) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = filePath + '.export-tmp-' + process.pid + '-' + Date.now();
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  fs.renameSync(tmp, filePath);
}

function readExistingExport(filePath) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch (_) { return null; }
}

// runExport(exportDir) -> { written, reason: 'initial'|'changed'|'keepalive'|'unchanged', file }
//
// Hash-gated (BINDING): unchanged content + a fresh (<60min) last export ->
// no write at all. Unchanged content + a STALE (>=60min) last export ->
// A3ii keepalive rewrite (fresh exported_at, same content_hash). Changed
// content -> always written. Fail-open throughout: a missing/corrupt
// previous export file is treated as "no previous export" (reason:
// 'initial'), never a crash.
function runExport(exportDir) {
  if (!exportDir) throw new Error('EXPORT_DIR is required');
  const payload = buildPayload();
  const hash = contentHash(payload);
  const filePath = exportFilePath(exportDir);
  const prev = readExistingExport(filePath);
  const now = new Date();
  if (prev && prev.content_hash === hash) {
    const prevMs = Date.parse(prev.exported_at || '');
    const age = isNaN(prevMs) ? Infinity : (now.getTime() - prevMs);
    if (age < KEEPALIVE_MS) {
      return { written: false, reason: 'unchanged', file: filePath };
    }
    const out = Object.assign({}, payload, { content_hash: hash, exported_at: now.toISOString() });
    atomicWriteJson(filePath, out);
    return { written: true, reason: 'keepalive', file: filePath };
  }
  const out = Object.assign({}, payload, { content_hash: hash, exported_at: now.toISOString() });
  atomicWriteJson(filePath, out);
  return { written: true, reason: prev ? 'changed' : 'initial', file: filePath };
}

module.exports = {
  runExport, buildPayload, contentHash, stableStringify, provenance,
  derivePlanRecords, deriveSessionsBlock, exportFilePath, hostname,
  KEEPALIVE_MS,
};

// ============================================================================
// --self-test — sandboxed fixture suite. Mirrors server.selftest.js's Task
// 11 fixture conventions (same env-var names, same JSONL/heartbeat/marker
// shapes) so this exercises the SAME join real requests exercise, just
// through derive-lib.js directly instead of over HTTP.
// ============================================================================
async function selfTest() {
  let passed = 0, failed = 0;
  function ok(name, cond, detail) {
    if (cond) { passed++; console.log('  PASS: ' + name); }
    else { failed++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'export-state-st-'));
  const savedEnv = {};
  const ENV_KEYS = [
    'ASK_REGISTRY_STATE_DIR', 'PROGRESS_LOG_STATE_DIR', 'DISPATCH_PROVENANCE_STATE_DIR',
    'HEARTBEAT_STATE_DIR', 'EXPORT_HOSTNAME',
  ];
  ENV_KEYS.forEach((k) => { savedEnv[k] = process.env[k]; });

  function sandbox(name) {
    const dir = path.join(tmp, name);
    const arDir = path.join(dir, 'ar');
    const plDir = path.join(dir, 'pl');
    const dpDir = path.join(dir, 'dp');
    const hbDir = path.join(dir, 'hb');
    fs.mkdirSync(arDir, { recursive: true });
    fs.mkdirSync(plDir, { recursive: true });
    fs.mkdirSync(dpDir, { recursive: true });
    fs.mkdirSync(hbDir, { recursive: true });
    process.env.ASK_REGISTRY_STATE_DIR = arDir;
    process.env.PROGRESS_LOG_STATE_DIR = plDir;
    process.env.DISPATCH_PROVENANCE_STATE_DIR = dpDir;
    process.env.HEARTBEAT_STATE_DIR = hbDir;
    return { dir, arDir, plDir, dpDir, hbDir };
  }

  function regLine(fields) {
    return JSON.stringify(Object.assign({
      ask_id: '', record_type: '', ts: '', repo: '', project: '', summary: '',
      verbatim_ref: '', status: '', plan_slug: '', emitter: 'ask-registry',
    }, fields));
  }
  function mkEvent(askId, overrides) {
    return JSON.stringify(Object.assign({
      v: 1, event_id: 'ev-' + Math.random().toString(36).slice(2), ts: '2026-07-01T00:00:00Z',
      ask_id: askId, type: '', plan_slug: '', task_id: '', session_id: '', evidence_link: '',
    }, overrides));
  }

  try {
    // ---- Scenario 1: full export from a fixture estate — in_flight
    // snapshot correct per the join (1 done, 1 in-flight, 1 not-started).
    const s1 = sandbox('s1-full');
    const planRepoRoot = path.join(s1.dir, 'repo');
    fs.mkdirSync(path.join(planRepoRoot, 'docs', 'plans'), { recursive: true });
    const slug = 'fixture-plan';
    const planAbsPath = path.join(planRepoRoot, 'docs', 'plans', slug + '.md');
    fs.writeFileSync(planAbsPath, [
      '# Plan: Fixture', '',
      '- [x] 1. Task one done.',
      '- [ ] 2. Task two dispatched, in-flight.',
      '- [ ] 3. Task three not started.', '',
    ].join('\n'));
    fs.writeFileSync(path.join(s1.arDir, 'ask-registry.jsonl'), [
      regLine({ ask_id: 'ask-1', record_type: 'created', ts: '2026-07-01T00:00:00Z', repo: planRepoRoot, project: 'demo', summary: 'fixture ask', status: 'active' }),
      regLine({ ask_id: 'ask-1', record_type: 'plan_linked', ts: '2026-07-01T00:01:00Z', plan_slug: slug }),
    ].join('\n') + '\n');
    fs.writeFileSync(path.join(s1.plDir, 'ask-1.jsonl'), [
      mkEvent('ask-1', { type: 'task_started', plan_slug: slug, task_id: '1', session_id: 'sess-a', ts: '2026-07-01T00:05:00Z' }),
      mkEvent('ask-1', { type: 'task_done', plan_slug: slug, task_id: '1', evidence_link: planAbsPath, ts: '2026-07-01T00:06:00Z' }),
      mkEvent('ask-1', { type: 'task_started', plan_slug: slug, task_id: '2', session_id: 'sess-a', ts: '2026-07-01T00:07:00Z' }),
    ].join('\n') + '\n');
    fs.writeFileSync(path.join(s1.hbDir, 'sess-a.json'), JSON.stringify({
      schema: 1, session_id: 'sess-a', pid: process.pid, branch: 'build/x',
      repo_root: planRepoRoot, worktree_root: planRepoRoot,
      last_activity_ts: new Date().toISOString(), last_event: 'turn-end', marker_state: 'none',
    }));
    process.env.EXPORT_HOSTNAME = 'host-a';
    const exportDirA = path.join(s1.dir, 'export');
    const r1 = runExport(exportDirA);
    const payload1 = JSON.parse(fs.readFileSync(r1.file, 'utf8'));
    const row1 = payload1.plans.find((p) => p.plan_slug === slug);
    ok('1. full export: in_flight snapshot correct (1 done, 1 in-flight, 1 not-started)',
      row1 && row1.tasks.length === 3 &&
      row1.tasks[0].done === true && !row1.tasks[0].in_flight &&
      row1.tasks[1].in_flight === true && !row1.tasks[1].done &&
      row1.tasks[2].done === false && !row1.tasks[2].in_flight &&
      row1.progress.done === 1 && row1.progress.in_flight === 1 && row1.progress.not_started === 1,
      JSON.stringify(row1));
    ok('1b. sessions block carries RAW last_heartbeat_at, never a baked classification field',
      payload1.sessions.some((s) => s.session_id === 'sess-a' && typeof s.last_heartbeat_at === 'string' && s.last_heartbeat_at.length > 0) &&
      payload1.sessions.every((s) => !('state' in s)),
      JSON.stringify(payload1.sessions));
    ok('1c. sessions block carries role/plan metadata folded in from ask lineage',
      payload1.sessions.some((s) => s.session_id === 'sess-a' && s.plan_slug === slug && s.task_id === '2'),
      JSON.stringify(payload1.sessions));
    ok('1d. provenance stamps schema_version/hostname/exported_at/content_hash',
      payload1.schema_version === 1 && payload1.provenance.hostname === 'host-a' &&
      typeof payload1.exported_at === 'string' && typeof payload1.content_hash === 'string',
      JSON.stringify({ schema_version: payload1.schema_version, provenance: payload1.provenance }));

    // ---- Scenario 2: descriptions with quotes/newlines survive as valid JSON.
    const s2 = sandbox('s2-quotes');
    fs.writeFileSync(path.join(s2.arDir, 'ask-registry.jsonl'),
      regLine({ ask_id: 'ask-2', record_type: 'created', ts: '2026-07-01T00:00:00Z', project: 'demo', summary: 'A "quoted" summary\nwith a newline and a \\backslash\\.', status: 'active' }) + '\n');
    process.env.EXPORT_HOSTNAME = 'host-quotes';
    const exportDirB = path.join(s2.dir, 'export');
    runExport(exportDirB);
    let parsedOk = false, rawText = '';
    try { rawText = fs.readFileSync(exportFilePath(exportDirB), 'utf8'); JSON.parse(rawText); parsedOk = true; } catch (_) { parsedOk = false; }
    ok('2. an estate with quotes/newlines in registry text still produces valid JSON', parsedOk, rawText.slice(0, 200));

    // ---- Scenario 3: zero-plan estate -> valid minimal export, never a crash.
    const s3 = sandbox('s3-empty');
    process.env.EXPORT_HOSTNAME = 'host-empty';
    const exportDirC = path.join(s3.dir, 'export');
    let threw = null;
    let r3 = null;
    try { r3 = runExport(exportDirC); } catch (e) { threw = e; }
    const payload3 = threw ? null : JSON.parse(fs.readFileSync(r3.file, 'utf8'));
    ok('3. zero-plan/zero-registry estate -> valid minimal export (plans:[], sessions:[]), never a crash',
      !threw && payload3 && Array.isArray(payload3.plans) && payload3.plans.length === 0 &&
      Array.isArray(payload3.sessions) && payload3.sessions.length === 0,
      threw ? String(threw && threw.message) : JSON.stringify(payload3));

    // ---- Scenario 4: hash-gate — unchanged estate + fresh last export -> no write.
    const s4 = sandbox('s4-hashgate');
    fs.writeFileSync(path.join(s4.arDir, 'ask-registry.jsonl'),
      regLine({ ask_id: 'ask-4', record_type: 'created', ts: '2026-07-01T00:00:00Z', project: 'demo', summary: 'steady state', status: 'active' }) + '\n');
    process.env.EXPORT_HOSTNAME = 'host-gate';
    const exportDirD = path.join(s4.dir, 'export');
    const r4a = runExport(exportDirD);
    const mtimeAfterFirst = fs.statSync(r4a.file).mtimeMs;
    const r4b = runExport(exportDirD);
    const mtimeAfterSecond = fs.statSync(r4b.file).mtimeMs;
    ok('4. hash-gate: unchanged estate + fresh (<60min) last export -> no write (reason:unchanged, mtime untouched)',
      r4a.reason === 'initial' && r4b.reason === 'unchanged' && mtimeAfterFirst === mtimeAfterSecond,
      'r4a=' + r4a.reason + ' r4b=' + r4b.reason);

    // ---- Scenario 5: A3ii keepalive — unchanged content + STALE (>=60min)
    // last export -> rewritten with a fresh exported_at, same content_hash.
    const staleFile = exportFilePath(exportDirD);
    const staleExport = JSON.parse(fs.readFileSync(staleFile, 'utf8'));
    staleExport.exported_at = new Date(Date.now() - (61 * 60 * 1000)).toISOString();
    fs.writeFileSync(staleFile, JSON.stringify(staleExport, null, 2) + '\n');
    const oldExportedAt = staleExport.exported_at;
    const r5 = runExport(exportDirD);
    const payload5 = JSON.parse(fs.readFileSync(r5.file, 'utf8'));
    ok('5. A3ii keepalive: unchanged content + stale (>=60min) exported_at -> rewritten with a fresh exported_at, same content_hash',
      r5.reason === 'keepalive' && r5.written === true &&
      payload5.content_hash === staleExport.content_hash && payload5.exported_at !== oldExportedAt,
      'reason=' + r5.reason + ' old=' + oldExportedAt + ' new=' + payload5.exported_at);

    // ---- Scenario 6: EXPORT_HOSTNAME override honored (file name + payload field).
    const s6 = sandbox('s6-hostname');
    process.env.EXPORT_HOSTNAME = 'peer-simulated-b';
    const exportDirE = path.join(s6.dir, 'export');
    const r6 = runExport(exportDirE);
    const payload6 = JSON.parse(fs.readFileSync(r6.file, 'utf8'));
    ok('6. EXPORT_HOSTNAME override honored in both the file name and provenance.hostname',
      path.basename(r6.file) === 'peer-simulated-b.json' && payload6.provenance.hostname === 'peer-simulated-b',
      r6.file + ' / ' + payload6.provenance.hostname);

    // ---- Scenario 7: atomicity — no partial file on a simulated write
    // failure. Monkey-patches fs.renameSync to throw exactly once (the last
    // step of atomicWriteJson), then confirms the PRE-EXISTING target file
    // is byte-for-byte unchanged (a reader concurrently polling this path
    // never observes a torn/partial file — tmp+rename means the target is
    // always either fully-old or fully-new, never in between).
    const s7 = sandbox('s7-atomic');
    process.env.EXPORT_HOSTNAME = 'host-atomic';
    const exportDirF = path.join(s7.dir, 'export');
    const r7a = runExport(exportDirF); // establishes a real prior export
    const beforeBytes = fs.readFileSync(r7a.file, 'utf8');
    // A heartbeat file (unlike a plan-less ask-registry row) directly
    // changes deriveSessionsBlock()'s output, so this genuinely perturbs
    // the content hash — the earlier draft of this fixture wrote an
    // ask-registry row with no linked plan, which is correctly INERT to
    // the derived payload (computePlanRows only emits rows for
    // reg.plan_slugs) and so never exercised the "changed" write path.
    fs.writeFileSync(path.join(s7.hbDir, 'sess-7.json'), JSON.stringify({
      schema: 1, session_id: 'sess-7', pid: process.pid, branch: 'build/atomic-fixture',
      last_activity_ts: new Date().toISOString(), last_event: 'turn-end', marker_state: 'none',
    }));
    const realRename = fs.renameSync;
    let renameThrew = false;
    fs.renameSync = function () { throw new Error('simulated rename failure (self-test fault injection)'); };
    try {
      runExport(exportDirF);
    } catch (e) {
      renameThrew = /simulated rename failure/.test(String(e && e.message));
    } finally {
      fs.renameSync = realRename;
    }
    const afterBytes = fs.readFileSync(r7a.file, 'utf8');
    const leftoverTmp = fs.readdirSync(path.dirname(r7a.file)).some((f) => /\.export-tmp-/.test(f));
    ok('7. atomicity: a simulated rename failure propagates (never silently swallowed) and the PRE-EXISTING target file is untouched (no partial write ever observable at the real path)',
      renameThrew && afterBytes === beforeBytes,
      'renameThrew=' + renameThrew + ' unchanged=' + (afterBytes === beforeBytes) + ' leftoverTmp=' + leftoverTmp);

    // ---- Scenario 8 (A4 trap, explicitly): exporter succeeds with a LIVE
    // cockpit server bound to a real port over the SAME sandboxed estate.
    // This is the concrete runtime proof that export-state.js never
    // requires server.js: if it did, this scenario would EADDRINUSE against
    // the child below and process.exit(0) silently (server.js's own
    // single-instance guard) instead of writing a real export.
    const s8 = sandbox('s8-server-up');
    fs.writeFileSync(path.join(s8.arDir, 'ask-registry.jsonl'),
      regLine({ ask_id: 'ask-8', record_type: 'created', ts: '2026-07-01T00:00:00Z', project: 'demo', summary: 'server-up scenario', status: 'active' }) + '\n');
    process.env.EXPORT_HOSTNAME = 'host-server-up';
    const exportDirG = path.join(s8.dir, 'export');
    const stubPath = path.join(s8.dir, 'nl-stub.sh');
    fs.writeFileSync(stubPath, '#!/bin/bash\necho \'{"schema":1}\'\n');
    try { fs.chmodSync(stubPath, 0o755); } catch (_) { /* best-effort on platforms without chmod semantics */ }
    const serverPort = 20111 + (process.pid % 500);
    const serverPath = path.join(__dirname, 'server.js');
    const child = spawn(process.execPath, [serverPath], {
      env: Object.assign({}, process.env, {
        CTREE_PORT: String(serverPort),
        NL_BIN: stubPath,
        AUDITOR_DISABLED: '1',
        OBS_REFRESH_MS: '999999',
        ASK_REGISTRY_STATE_DIR: s8.arDir,
        PROGRESS_LOG_STATE_DIR: s8.plDir,
        DISPATCH_PROVENANCE_STATE_DIR: s8.dpDir,
        HEARTBEAT_STATE_DIR: s8.hbDir,
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let serverOut = '';
    child.stdout.on('data', (d) => { serverOut += d; });
    child.stderr.on('data', (d) => { serverOut += d; });
    // A genuine async poll (setTimeout ticks, event loop free to run the
    // child's stdout 'data' callbacks between checks) — NOT a synchronous
    // busy-wait, which would never let those callbacks fire.
    const listeningDeadline = Date.now() + 20000;
    while (!/listening on/.test(serverOut) && Date.now() < listeningDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    const serverWasUp = /listening on/.test(serverOut);
    let r8 = null, r8err = null;
    try { r8 = runExport(exportDirG); } catch (e) { r8err = e; }
    try { child.kill(); } catch (_) { /* best-effort */ }
    const payload8 = (!r8err && r8) ? JSON.parse(fs.readFileSync(r8.file, 'utf8')) : null;
    ok('8. (A4 trap) exporter succeeds and writes a real export while a LIVE cockpit server holds the port — proves no require(./server.js), no EADDRINUSE interference',
      serverWasUp && !r8err && payload8 && Array.isArray(payload8.plans) && payload8.provenance.hostname === 'host-server-up',
      'serverWasUp=' + serverWasUp + ' err=' + String(r8err && r8err.message) + ' payload=' + JSON.stringify(payload8 && payload8.provenance));
  } finally {
    ENV_KEYS.forEach((k) => {
      if (savedEnv[k] === undefined) delete process.env[k];
      else process.env[k] = savedEnv[k];
    });
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort cleanup */ }
  }

  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  return failed === 0 ? 0 : 1;
}

if (require.main === module) {
  if (process.argv.indexOf('--self-test') !== -1) {
    selfTest().then((code) => process.exit(code));
  } else {
    const dir = process.env.EXPORT_DIR;
    if (!dir) {
      process.stderr.write('[export-state] EXPORT_DIR is required\n');
      process.exit(1);
    }
    try {
      const r = runExport(dir);
      process.stdout.write('[export-state] ' + r.reason + ' -> ' + r.file + '\n');
      process.exit(0);
    } catch (e) {
      process.stderr.write('[export-state] failed: ' + String(e && e.message || e) + '\n');
      process.exit(1);
    }
  }
}
