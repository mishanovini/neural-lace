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

// SCHEMA_VERSION 2 (cross-machine-plan-inventory): the plans block is now
// the SHARED disk-scan inventory (derive-lib.discoverPlanFiles — the same
// derivation the cockpit's Roadmap reads) instead of the ask-registry
// "plan_linked" fold, and every plan row carries a NAMED plan_state.
//
// The bump is load-bearing, not cosmetic. A version-2 reader seeing a
// version-1 export must NOT default the missing plan_state to 'parsed' —
// that would re-launder the exact bug this change removes (an unreadable
// plan reappearing as a healthy 0/0). peer-view.js renders any
// schema_version < 2 plan row as the named state 'legacy-unlabelled'
// instead. Old readers are safe in the other direction by construction:
// peer-view's projection is an explicit field pick, so fields it does not
// know about are dropped rather than mishandled. Self-heals within one
// sync cycle per host.
const SCHEMA_VERSION = 2;

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
    scan: scanProvenance(),
  };
}

// scanProvenance() — WHAT THIS HOST ACTUALLY SCANNED, as a declared state.
//
// config/projects.json is gitignored and machine-local, so multi-repo
// coverage genuinely DIFFERS per machine: a host without that file scans
// only its own repo and is entirely correct to do so. The requirement is
// that the difference is NAMED, never silent — an operator comparing three
// hosts must be able to read "this host scans 1 repo (projects_config:
// absent)" instead of inferring absence from a short list.
//
// `projects_config` is the distinction configuredRepoRoots() itself throws
// away: its catch degrades BOTH "no file" and "unparseable file" to the same
// empty list. `completed_age_days` names the archive-recency ceiling that is
// what actually bounds this payload's size — legible rather than incidental.
function scanProvenance() {
  const scanRoot = deriveLib.planScanRoot();
  const roots = [{ key: 'self', root: scanRoot }].concat(deriveLib.configuredRepoRoots());
  return {
    root: scanRoot,
    projects_config: deriveLib.configuredRepoRootsState(),
    completed_age_days: deriveLib.COMPLETED_AGE_DAYS,
    repo_roots: roots.map((r) => ({
      key: r.key, root: r.root,
      present: fs.existsSync(path.join(r.root, 'docs', 'plans')),
    })),
  };
}

// derivePlanRecords() -> {records, ghost_count}
//
// THE FIX (cross-machine-plan-inventory, defect 1). This used to fold the
// ask registry and emit one record per ask-linked plan slug. derive-lib's
// foldAskRegistry appends plan_slugs ONLY from records with record_type
// "plan_linked", and the sole writer of those is guarded on an ask id — so
// any plan started without one was never linked, and this export contained
// a couple of plans BY CONSTRUCTION while the cockpit next to it scanned
// every plan document on disk. Three machines each rendered an independent
// local derivation and never agreed.
//
// It now drives the SAME derive-lib.discoverPlanFiles the cockpit's Roadmap
// drives, off the SAME planScanRoot, joined with the SAME eventsForSlug.
// One derivation, two consumers — divergence is not detected, it is
// unrepresentable, because there is no second derivation left to diverge.
//
// A4 (BINDING) is respected and, if anything, reinforced: every read here
// still goes through derive-lib.js's pure local-disk functions. Nothing in
// this file requires server.js — nor roadmap-routes.js, which is a route
// module owning handle(req, res); the shared scan was moved INTO derive-lib
// precisely so this file never needs an edge to an HTTP surface.
//
// `repo` comes from repoRootFromAbsPath(the scanned file's own path), NOT
// from a registry `repo` field — that field is empty on the live sentinel
// records and is the direct cause of today's hollow rows.
function derivePlanRecords() {
  const folded = deriveLib.foldAskRegistry();
  const links = deriveLib.planAskLinkIndex(folded);
  const scanRoot = deriveLib.planScanRoot();
  const discovered = deriveLib.discoverPlanFiles(scanRoot, links);

  const records = discovered.files.map((pf) => {
    const linkedAsks = links[pf.slug] || [];
    // The named-absence resolver: `tasks` is an Array if and only if
    // state === 'parsed'. A scanIssue from the scan (unrecognized Status:
    // token, destroyed header, unreadable file) is carried straight through
    // as 'ineligible' rather than being re-derived or silently zeroed.
    const res = deriveLib.resolvePlanTasks('', pf.slug, { absPath: pf.absPath, scanIssue: pf.scanIssue });
    const rec = {
      plan_slug: pf.slug,
      repo: repoRootFromAbsPath(pf.absPath),
      plan_doc: deriveLib.projectDocRefFor(pf.absPath),
      archived: !!pf.archived,
      // NAMED, never inferred by the reader. Deliberately NOT called
      // `source`: that key already exists in the landing payload's
      // allowlist with an unrelated meaning (my_coord_refresh.source), so a
      // plan-record `source` would validate cleanly while silently
      // overloading it.
      discovery: pf.discovery === 'ask-link' ? 'ask-link' : 'scan',
      plan_state: res.state,
      plan_state_reason: res.reason,
      tasks: null,
      progress: null,
    };
    if (res.state !== 'parsed') return rec; // INVARIANT: tasks/progress stay null
    // Same event join the cockpit runs — every linked ask's lane PLUS the
    // shared unlinked orphan lane, which for a scan-discovered plan with no
    // ask is the ONLY source of task_started/task_done.
    const events = deriveLib.eventsForSlug(pf.slug, linkedAsks);
    const started = {}; const doneEv = {};
    events.forEach((e) => {
      if (!e || !e.task_id) return;
      if (e.type === 'task_started') started[e.task_id] = true;
      if (e.type === 'task_done') doneEv[e.task_id] = e.evidence_link || '';
    });
    rec.tasks = res.tasks.map((t) => ({
      id: t.id,
      done: t.done,
      in_flight: !t.done && !!started[t.id] && !doneEv[t.id],
      evidence_link: doneEv[t.id] || '',
    }));
    rec.progress = deriveLib.aggregatePlanProgress([{ tasks: rec.tasks }]);
    return rec;
  }).sort((a, b) => a.plan_slug.localeCompare(b.plan_slug));

  // ghostCount is surfaced as a NAMED aggregate (the same one the cockpit
  // already shows) — ask-linked slugs with no readable file and no recent
  // evidence are excluded from the inventory but never silently dropped.
  return { records: records, ghost_count: discovered.ghostCount };
}

// repoRootFromAbsPath(absPath) — the repo root a scanned plan file belongs
// to: walk up from <root>/docs/plans[/archive]/<slug>.md. Kept here (a
// three-line path walk) rather than imported from roadmap-routes.js, which
// is a route module this file must not depend on (A4's spirit).
function repoRootFromAbsPath(absPath) {
  if (!absPath) return '';
  const norm = String(absPath).replace(/\\/g, '/');
  const m = /^(.*)\/docs\/plans\/(?:archive\/)?[^/]+$/.exec(norm);
  return m ? m[1] : '';
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
  const planned = derivePlanRecords();
  const prov = provenance();
  // The named aggregate for ask-linked slugs that resolved to nothing and
  // had no recent evidence — excluded from the inventory, never silently
  // dropped. Same figure the cockpit's own Roadmap surfaces.
  prov.scan.stale_links_omitted = planned.ghost_count;
  return {
    schema_version: SCHEMA_VERSION,
    provenance: prov,
    plans: planned.records,
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
    // cross-machine-plan-inventory: the exporter now derives its plan
    // inventory by SCANNING docs/plans from disk (the same derivation the
    // cockpit reads) instead of folding ask-registry "plan_linked" records.
    // That makes the plan scan root a state path this suite must sandbox
    // like every other one — without these two, every scenario below would
    // read the developer's REAL checkout and the fixtures would be drowned
    // in a hundred live plans.
    'ROADMAP_PLAN_SCAN_ROOT', 'ROADMAP_PROJECTS_CONFIG',
  ];
  ENV_KEYS.forEach((k) => { savedEnv[k] = process.env[k]; });

  function sandbox(name) {
    const dir = path.join(tmp, name);
    const arDir = path.join(dir, 'ar');
    const plDir = path.join(dir, 'pl');
    const dpDir = path.join(dir, 'dp');
    const hbDir = path.join(dir, 'hb');
    // The scan root every scenario's plan fixtures already live under.
    const repoDir = path.join(dir, 'repo');
    fs.mkdirSync(arDir, { recursive: true });
    fs.mkdirSync(plDir, { recursive: true });
    fs.mkdirSync(dpDir, { recursive: true });
    fs.mkdirSync(hbDir, { recursive: true });
    fs.mkdirSync(path.join(repoDir, 'docs', 'plans'), { recursive: true });
    process.env.ASK_REGISTRY_STATE_DIR = arDir;
    process.env.PROGRESS_LOG_STATE_DIR = plDir;
    process.env.DISPATCH_PROVENANCE_STATE_DIR = dpDir;
    process.env.HEARTBEAT_STATE_DIR = hbDir;
    process.env.ROADMAP_PLAN_SCAN_ROOT = repoDir;
    // Point the multi-repo config at a path that does not exist, so the
    // sandbox scans exactly one repo and `projects_config` reports the
    // NAMED 'absent' state rather than picking up this machine's real
    // (gitignored, machine-local) config/projects.json.
    process.env.ROADMAP_PROJECTS_CONFIG = path.join(dir, 'no-projects.json');
    return { dir, arDir, plDir, dpDir, hbDir, repoDir };
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
      // A `Status:` header is what makes a docs/plans/*.md file an actual
      // PLAN rather than an evidence stub or fragment. The exporter now
      // applies the SAME eligibility rule the cockpit's Roadmap applies (one
      // derivation, defect 1), so this fixture has to be a well-formed plan
      // — the old registry-fold exporter accepted anything an ask happened
      // to link, which is part of why the two views could never agree.
      '# Plan: Fixture', '',
      'Status: ACTIVE', '',
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
      payload1.schema_version === 2 && payload1.provenance.hostname === 'host-a' &&
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
    // A plain child.kill() was observed to leave the spawned server.js
    // instance (and its bound port) alive on Windows — `taskkill /T /F`
    // (kill the process tree, forceful) is the reliable Windows-safe
    // teardown; non-Windows keeps the ordinary child.kill().
    if (child.pid) {
      if (process.platform === 'win32') {
        try { execFileSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' }); } catch (_) { /* best-effort */ }
      } else {
        try { child.kill(); } catch (_) { /* best-effort */ }
      }
    }
    const payload8 = (!r8err && r8) ? JSON.parse(fs.readFileSync(r8.file, 'utf8')) : null;
    ok('8. (A4 trap) exporter succeeds and writes a real export while a LIVE cockpit server holds the port — proves no require(./server.js), no EADDRINUSE interference',
      serverWasUp && !r8err && payload8 && Array.isArray(payload8.plans) && payload8.provenance.hostname === 'host-server-up',
      'serverWasUp=' + serverWasUp + ' err=' + String(r8err && r8err.message) + ' payload=' + JSON.stringify(payload8 && payload8.provenance));

    // ==================================================================
    // Scenarios 9-13 — cross-machine-plan-inventory (2026-08-06).
    // ==================================================================

    // ---- Scenario 9: THE DEFECT ITSELF. The export's plan inventory is
    // the DISK SCAN, not the ask-registry "plan_linked" fold.
    //
    // Fixture: 120 well-formed plan files on disk, of which exactly TWO are
    // ask-linked. The old exporter emitted one record per plan_linked
    // record and would therefore ship 2 while the cockpit beside it showed
    // 120 — which is precisely why three machines never agreed. Both
    // numbers are asserted, so this fails loudly in EITHER direction: too
    // few (the fold came back) or a scan that silently disagrees with the
    // cockpit's own.
    const s9 = sandbox('s9-inventory');
    const PLAN_COUNT = 120;
    const s9PlansDir = path.join(s9.repoDir, 'docs', 'plans');
    for (let i = 1; i <= PLAN_COUNT; i++) {
      const n = String(i).padStart(3, '0');
      fs.writeFileSync(path.join(s9PlansDir, 'scanned-plan-' + n + '.md'), [
        '# Plan: scanned ' + n, '', 'Status: ACTIVE', '',
        '- [x] 1. First task.',
        '- [ ] 2. Second task.', '',
      ].join('\n'));
    }
    fs.writeFileSync(path.join(s9.arDir, 'ask-registry.jsonl'), [
      regLine({ ask_id: 'ask-9', record_type: 'created', ts: '2026-07-01T00:00:00Z', repo: s9.repoDir, project: 'demo', summary: 'only two plans are linked', status: 'active' }),
      regLine({ ask_id: 'ask-9', record_type: 'plan_linked', ts: '2026-07-01T00:01:00Z', plan_slug: 'scanned-plan-001' }),
      regLine({ ask_id: 'ask-9', record_type: 'plan_linked', ts: '2026-07-01T00:02:00Z', plan_slug: 'scanned-plan-002' }),
    ].join('\n') + '\n');
    process.env.EXPORT_HOSTNAME = 'host-inventory';
    const r9 = runExport(path.join(s9.dir, 'export'));
    const payload9 = JSON.parse(fs.readFileSync(r9.file, 'utf8'));
    const linkedCount9 = Object.keys(deriveLib.planAskLinkIndex(deriveLib.foldAskRegistry())).length;
    ok('9. THE FIX: the export carries the whole SCANNED plan inventory (' + PLAN_COUNT + ' plans on disk), not the ' + linkedCount9 + ' the ask-registry "plan_linked" fold would have produced',
      payload9.plans.length === PLAN_COUNT && linkedCount9 === 2,
      'exported=' + payload9.plans.length + ' plan_linked=' + linkedCount9);

    // ---- Scenario 9b: ONE DERIVATION, not two that agree by luck. The
    // exporter's slug set is compared against the SAME derive-lib scan the
    // cockpit's Roadmap route drives (roadmap-routes.js re-exports it as a
    // pass-through). Set equality, not just a matching count.
    const cockpitScan9 = deriveLib.discoverPlanFiles(
      deriveLib.planScanRoot(), deriveLib.planAskLinkIndex(deriveLib.foldAskRegistry()));
    const exportSlugs9 = payload9.plans.map((p) => p.plan_slug).sort().join(',');
    const cockpitSlugs9 = cockpitScan9.files.map((f) => f.slug).sort().join(',');
    ok('9b. the exporter and the cockpit read ONE derivation: identical slug SETS from derive-lib.discoverPlanFiles (' + cockpitScan9.files.length + ' files), never two inventories that could drift',
      exportSlugs9 === cockpitSlugs9 && cockpitScan9.files.length === PLAN_COUNT,
      'export=' + payload9.plans.length + ' cockpit=' + cockpitScan9.files.length);

    // ---- Scenario 9c: a scan-discovered plan with NO ask is fully
    // populated — real repo, real plan_doc, real tasks. Today's live export
    // ships hollow rows (repo:"", plan_doc:null, tasks:[]) precisely because
    // it read `repo` off a registry record instead of the file's own path.
    const unlinked9 = payload9.plans.find((p) => p.plan_slug === 'scanned-plan-099');
    // `repo` is derived from the scanned file's OWN absolute path, never
    // from a registry `repo` field — that field is empty on the live
    // sentinel records and is the direct cause of today's hollow rows.
    // NOTE on plan_doc: it resolves through config/projects.js, which maps
    // absolute paths to CONFIGURED projects and has no env override, so a
    // throwaway temp repo legitimately resolves to null here. Real plan_doc
    // population is exercised by the end-to-end run against this machine's
    // actual checkout, not by this sandbox.
    ok('9c. a scan-discovered plan with NO linked ask is fully populated from the FILE (real repo path + real tasks + real progress), never today\'s hollow row',
      unlinked9 && unlinked9.repo === s9.repoDir.replace(/\\/g, '/') &&
      Array.isArray(unlinked9.tasks) && unlinked9.tasks.length === 2 &&
      unlinked9.discovery === 'scan' && unlinked9.archived === false &&
      unlinked9.progress.done === 1 && unlinked9.progress.total === 2,
      JSON.stringify(unlinked9));

    // ---- Scenario 10: NAMED ABSENCE. An ask-linked plan slug whose file
    // does not exist anywhere must export a NAMED state, never a
    // fully-formed, healthy-looking 0/0.
    //
    // This is the exact laundering that used to happen: resolvePlanAbsPath
    // returned null -> countPlanTasks was skipped -> `(planTasks || [])`
    // produced [] -> aggregatePlanProgress counted over [] and returned
    // {done:0, in_flight:0, not_started:0, total:0}, which the exporter
    // shipped with rc 0. Absence was byte-identical to emptiness.
    const s10 = sandbox('s10-named-absence');
    // A REAL, healthy, genuinely EMPTY plan (zero checkboxes) sits beside
    // the missing one. The whole point of the invariant is that these two
    // stay distinguishable, so both are asserted together.
    fs.writeFileSync(path.join(s10.repoDir, 'docs', 'plans', 'genuinely-empty.md'),
      ['# Plan: genuinely empty', '', 'Status: ACTIVE', '', 'No tasks written yet.', ''].join('\n'));
    fs.writeFileSync(path.join(s10.arDir, 'ask-registry.jsonl'), [
      regLine({ ask_id: 'ask-10', record_type: 'created', ts: new Date().toISOString(), repo: s10.repoDir, project: 'demo', summary: 'links a plan that does not exist', status: 'active' }),
      regLine({ ask_id: 'ask-10', record_type: 'plan_linked', ts: new Date().toISOString(), plan_slug: 'no-such-plan-anywhere' }),
    ].join('\n') + '\n');
    process.env.EXPORT_HOSTNAME = 'host-absence';
    const r10 = runExport(path.join(s10.dir, 'export'));
    const payload10 = JSON.parse(fs.readFileSync(r10.file, 'utf8'));
    const missing10 = payload10.plans.find((p) => p.plan_slug === 'no-such-plan-anywhere');
    ok('10. an UNRESOLVABLE plan file exports a NAMED absence (plan_state + reason, tasks:null, progress:null) — never a fabricated healthy 0/0',
      missing10 && missing10.plan_state !== 'parsed' && missing10.tasks === null &&
      missing10.progress === null && typeof missing10.plan_state_reason === 'string' &&
      missing10.plan_state_reason.length > 0,
      JSON.stringify(missing10));
    const empty10 = payload10.plans.find((p) => p.plan_slug === 'genuinely-empty');
    ok('10b. ...and a GENUINELY empty plan is still a healthy zero (parsed, tasks:[], progress 0/0) — the two states stay distinguishable, which is the entire point',
      empty10 && empty10.plan_state === 'parsed' && Array.isArray(empty10.tasks) &&
      empty10.tasks.length === 0 && empty10.progress && empty10.progress.total === 0,
      JSON.stringify(empty10));
    ok('10c. THE INVARIANT holds across every row of a real export: `tasks` is an Array if and only if plan_state === "parsed"',
      payload10.plans.every((p) => Array.isArray(p.tasks) === (p.plan_state === 'parsed')) &&
      payload9.plans.every((p) => Array.isArray(p.tasks) === (p.plan_state === 'parsed')),
      JSON.stringify(payload10.plans.map((p) => [p.plan_slug, p.plan_state, Array.isArray(p.tasks)])));

    // ---- Scenario 11: an INELIGIBLE plan (readable bytes, but a Status:
    // value outside the harness's own enum) is named too, rather than being
    // bucketed confidently or vanishing. 12 real files on this machine
    // carry exactly this shape.
    const s11 = sandbox('s11-ineligible');
    fs.writeFileSync(path.join(s11.repoDir, 'docs', 'plans', 'weird-status.md'),
      ['# Plan: weird status', '', 'Status: SHIPPED TO PRODUCTION 2026-07-30', '', '- [ ] 1. A task.', ''].join('\n'));
    process.env.EXPORT_HOSTNAME = 'host-ineligible';
    const r11 = runExport(path.join(s11.dir, 'export'));
    const payload11 = JSON.parse(fs.readFileSync(r11.file, 'utf8'));
    const weird11 = payload11.plans.find((p) => p.plan_slug === 'weird-status');
    ok('11. a plan whose Status: value is outside the known enum exports plan_state:"ineligible" with the offending value QUOTED — never a confident bucket, never a silent drop',
      weird11 && weird11.plan_state === 'ineligible' && weird11.tasks === null &&
      weird11.progress === null && /SHIPPED TO PRODUCTION/.test(weird11.plan_state_reason),
      JSON.stringify(weird11));

    // ---- Scenario 12: the per-machine multi-repo difference is a DECLARED
    // state. config/projects.json is gitignored and machine-local, so a Mac
    // with no config legitimately scans one repo — the operator must be able
    // to READ that, not infer it from a short plan list.
    ok('12. provenance.scan NAMES what this host scanned (root, projects_config state, the aging ceiling, per-repo presence, omitted stale links) so a per-machine coverage difference is declared, never silent',
      payload11.provenance.scan &&
      payload11.provenance.scan.projects_config === 'absent' &&
      payload11.provenance.scan.completed_age_days === deriveLib.COMPLETED_AGE_DAYS &&
      Array.isArray(payload11.provenance.scan.repo_roots) &&
      payload11.provenance.scan.repo_roots.length === 1 &&
      payload11.provenance.scan.repo_roots[0].present === true &&
      typeof payload11.provenance.scan.stale_links_omitted === 'number',
      JSON.stringify(payload11.provenance.scan));
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
