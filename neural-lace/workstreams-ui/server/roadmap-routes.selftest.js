'use strict';
// roadmap-routes.selftest.js — sandboxed self-test for the Roadmap view's
// server surface (cockpit-roadmap-redesign Task 3). Lives in its OWN file
// (not server.selftest.js) because Task 1 concurrently owns server.js +
// server.selftest.js — this file only requires roadmap-routes.js and mounts
// it on a private http server, so the two tasks never race on one file.
//
// REAL-SCENARIO discipline (no mocking the SUT): fixtures are REAL files —
// a real ask-registry.jsonl, real progress-log JSONL, a real plan .md in a
// fixture repo — under a mktemp sandbox selected via the SAME env overrides
// the shell writer libs already honor (ASK_REGISTRY_STATE_DIR /
// PROGRESS_LOG_STATE_DIR). Requests are REAL HTTP GET/POSTs against the
// mounted handler. HARNESS_SELFTEST=1 is set for parity with the repo's
// selftest convention (nothing here shells the real estate either way).
//
// Run: `node server/roadmap-routes.selftest.js`. Exit 0 PASS / 1 FAIL.
// Extra mode: `node server/roadmap-routes.selftest.js --serve` keeps the
// fixture server alive (prints the port) for a manual browser livesmoke
// against the real web/ assets + this fixture estate.

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

process.env.HARNESS_SELFTEST = '1';

let PASSED = 0, FAILED = 0;
function ok(name, cond, detail) {
  if (cond) { PASSED++; console.log('  PASS: ' + name); }
  else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
}

function httpGet(port, urlPath) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: port, path: urlPath, agent: false }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) { /* left null (static assets) */ }
        resolve({ status: res.statusCode, headers: res.headers, body: body, json: parsed });
      });
    }).on('error', reject);
  });
}

function httpPostJson(port, urlPath, obj) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(obj || {});
    const req = http.request({
      host: '127.0.0.1', port: port, path: urlPath, method: 'POST', agent: false,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
    }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) {}
        resolve({ status: res.statusCode, body: body, json: parsed });
      });
    });
    req.on('error', reject);
    req.end(payload);
  });
}

// findItem(items, id) — depth-first search over the payload tree.
function findItem(items, id) {
  for (let i = 0; i < (items || []).length; i++) {
    if (items[i].id === id) return items[i];
    const hit = findItem(items[i].children, id);
    if (hit) return hit;
  }
  return null;
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'roadmap-t3-st-'));
  const stateDir = path.join(tmp, 'state');
  const progressDir = path.join(tmp, 'progress');
  const repoDir = path.join(tmp, 'fixture-repo');
  const heartbeatDir = path.join(tmp, 'heartbeats');
  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(progressDir, { recursive: true });
  fs.mkdirSync(path.join(repoDir, 'docs', 'plans'), { recursive: true });
  fs.mkdirSync(heartbeatDir, { recursive: true });

  process.env.ASK_REGISTRY_STATE_DIR = stateDir;
  process.env.PROGRESS_LOG_STATE_DIR = progressDir;
  // Task-1 wiring (derive-lib.js's deriveItemStatus) now requires REAL
  // heartbeat evidence for a task's in-progress classification (the stub's
  // prior "task_started + unflipped -> in-progress" shortcut is gone — see
  // roadmap-routes.js's STATUS DERIVATION header). Sandboxed like every
  // other state dir above; a fresh heartbeat for sess-op-1 (ask-alpha's
  // demo-plan task 2, started per the fixture events below) keeps S3b/S3d
  // passing under the real derivation instead of the old mechanical one.
  process.env.HEARTBEAT_STATE_DIR = heartbeatDir;
  fs.writeFileSync(path.join(heartbeatDir, 'sess-op-1.json'), JSON.stringify({
    schema: 1, session_id: 'sess-op-1', pid: 1, cwd: repoDir, repo_root: repoDir,
    worktree_root: repoDir, branch: 'fixture', model: 'fixture',
    last_activity_ts: new Date().toISOString(), last_event: 'fixture', marker_state: 'active',
  }));
  // Point the CLI delegation at a nonexistent path by default: the rank
  // endpoint must fall back to its overlay store honestly, and the title
  // endpoint must return a NAMED error, never a silent success.
  process.env.ASK_REGISTRY_CLI = path.join(tmp, 'no-such-cli.sh');

  // ---- fixture plan files ------------------------------------------------
  // demo-plan: 3 tasks — 1 done, 1 started-in-flight, 1 untouched.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'demo-plan.md'), [
    '# Plan: demo', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [x] 1. build the first thing',
    '- [ ] 2. build the second thing',
    '- [ ] 3. build the third thing',
    '',
  ].join('\n'));
  // shipped-plan: all tasks done -> the no-signal oracle class must render
  // as merged-unverified, OUTSIDE complete (A4 binding rule).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'shipped-plan.md'), [
    '# Plan: shipped', '', 'Status: COMPLETED', '', '## Tasks', '',
    '- [x] 1. everything',
    '- [x] 2. is checked',
    '',
  ].join('\n'));
  // ghost-plan deliberately DOES NOT EXIST on disk -> unknown(reason).

  // ---- fixture registry --------------------------------------------------
  const reg = [
    // ask-alpha: operator ask, demo-plan linked (in-progress overall).
    { ask_id: 'ask-alpha', record_type: 'created', ts: '2026-07-10T10:00:00Z', summary: 'Build the alpha feature', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-1', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-alpha', record_type: 'plan_linked', ts: '2026-07-10T10:05:00Z', plan_slug: 'demo-plan' },
    // ask-beta: operator ask, ghost-plan linked (derivation input missing -> unknown).
    { ask_id: 'ask-beta', record_type: 'created', ts: '2026-07-11T10:00:00Z', summary: 'Beta effort', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-2', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-beta', record_type: 'plan_linked', ts: '2026-07-11T10:05:00Z', plan_slug: 'ghost-plan' },
    // ask-chore: machine-filed (auto-sweep emitter) -> provenance machine.
    { ask_id: 'ask-chore', record_type: 'created', ts: '2026-07-12T10:00:00Z', summary: 'nl-issue: tighten a gate message', repo: repoDir, project: 'neural-lace', origin_session: '', status: 'active', emitter: 'auto-sweep' },
    // ask-shipped: all-done plan, no deploy signal -> merged-unverified.
    { ask_id: 'ask-shipped', record_type: 'created', ts: '2026-07-09T10:00:00Z', summary: 'Ship the widget', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-3', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-shipped', record_type: 'plan_linked', ts: '2026-07-09T10:05:00Z', plan_slug: 'shipped-plan' },
    // ask-done: operator marked done (manual override, labeled).
    { ask_id: 'ask-done', record_type: 'created', ts: '2026-07-01T10:00:00Z', summary: 'Old finished thing', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-4', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-done', record_type: 'status_change', ts: '2026-07-02T10:00:00Z', status: 'done', emitter: 'operator-ui' },
    // ask-dismissed must NOT appear on the roadmap at all.
    { ask_id: 'ask-dismissed', record_type: 'created', ts: '2026-07-03T10:00:00Z', summary: 'Abandoned idea', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-5', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-dismissed', record_type: 'status_change', ts: '2026-07-04T10:00:00Z', status: 'dismissed', emitter: 'operator-ui' },
  ];
  fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'),
    reg.map((r) => JSON.stringify(r)).join('\n') + '\n');

  // ---- fixture progress events ------------------------------------------
  fs.writeFileSync(path.join(progressDir, 'ask-alpha.jsonl'), [
    JSON.stringify({ type: 'task_started', ts: '2026-07-15T09:00:00Z', plan_slug: 'demo-plan', task_id: '2', session_id: 'sess-op-1' }),
    JSON.stringify({ type: 'task_done', ts: '2026-07-14T18:00:00Z', plan_slug: 'demo-plan', task_id: '1', session_id: 'sess-op-1', evidence_link: '' }),
  ].join('\n') + '\n');

  delete require.cache[require.resolve('./roadmap-routes.js')];
  const roadmapRoutes = require('./roadmap-routes.js');

  const PORT = 18790 + (process.pid % 997);
  const server = http.createServer((req, res) => {
    if (roadmapRoutes.handle(req, res)) return;
    // --serve livesmoke mode also serves the real web assets so a browser
    // can exercise the actual shell against this fixture estate.
    const WEB = path.join(__dirname, '..', 'web');
    const clean = req.url.split('?')[0];
    const file = clean === '/' ? 'index.html' : clean.replace(/^\//, '');
    const abs = path.join(WEB, file);
    if (/\.(html|js|css)$/.test(file) && fs.existsSync(abs)) {
      const mime = /\.html$/.test(file) ? 'text/html' : /\.css$/.test(file) ? 'text/css' : 'text/javascript';
      res.writeHead(200, { 'Content-Type': mime + '; charset=utf-8' });
      res.end(fs.readFileSync(abs));
      return;
    }
    // minimal needs-me stub for the Inbox count in --serve mode
    if (clean === '/api/pane/needs-me') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ schema: 1, pane: 'needs-me', rc: 0, derived_at: new Date().toISOString(), data: { items: [
        { id: 'ny-1', section: 'decision', text: 'fixture decision waiting on you', links: [], session: 'sess-op-1', created_at: '2026-07-18T10:00:00Z', state: 'open' },
        { id: 'ny-2', section: 'question', text: 'context-less item', links: [], session: 'sess-op-2', created_at: '2026-07-18T11:00:00Z', state: 'open', lint_warnings: ['no-context'] },
      ] }, command: 'fixture' }));
      return;
    }
    res.writeHead(404); res.end('not found');
  });
  await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));

  if (process.argv.indexOf('--serve') !== -1) {
    console.log('[roadmap-routes.selftest] fixture server on http://127.0.0.1:' + PORT + ' (Ctrl-C to stop)');
    return; // leave server running for manual livesmoke
  }

  try {
    // ---- S1: payload shape + default build order = registry insertion ----
    const r1 = await httpGet(PORT, '/api/roadmap');
    ok('S1 GET /api/roadmap returns ok:true with items[]', r1.status === 200 && r1.json && r1.json.ok === true && Array.isArray(r1.json.items));
    const items = (r1.json && r1.json.items) || [];
    const topIds = items.map((i) => i.id);
    ok('S1b default build order = registry insertion order (created_ts ascending)',
      JSON.stringify(topIds) === JSON.stringify(['ask-done', 'ask-shipped', 'ask-alpha', 'ask-beta', 'ask-chore']),
      topIds.join(','));
    ok('S1c dismissed asks never appear on the roadmap', topIds.indexOf('ask-dismissed') === -1);
    ok('S1d payload carries the single completed-aging tunable (completed_age_days)',
      typeof (r1.json && r1.json.completed_age_days) === 'number');

    // ---- S2: six-value enum only, everywhere ----
    const ENUM = ['not-started', 'in-progress', 'merged-unverified', 'complete', 'stalled', 'unknown'];
    const badStatuses = [];
    (function walk(list) {
      (list || []).forEach((it) => {
        if (!it.status || ENUM.indexOf(it.status.value) === -1) badStatuses.push(it.id + '=' + (it.status && it.status.value));
        walk(it.children);
      });
    })(items);
    ok('S2 every item status is one of the six enum values (no seventh state, no missing status)', badStatuses.length === 0, badStatuses.join(','));

    // ---- S3: task-level statuses from real plan checkboxes + events ----
    const t1 = findItem(items, 'ask-alpha/demo-plan/1');
    const t2 = findItem(items, 'ask-alpha/demo-plan/2');
    const t3 = findItem(items, 'ask-alpha/demo-plan/3');
    ok('S3 checked task renders complete', t1 && t1.status.value === 'complete');
    ok('S3b started-unchecked task renders in-progress with a since timestamp',
      t2 && t2.status.value === 'in-progress' && !!t2.status.since);
    ok('S3c untouched task renders not-started', t3 && t3.status.value === 'not-started');
    const alpha = findItem(items, 'ask-alpha');
    ok('S3d parent with an in-progress child renders in-progress', alpha && alpha.status.value === 'in-progress');
    ok('S3e progress carries child counts (1 done of 3)', alpha && alpha.progress && alpha.progress.done === 1 && alpha.progress.total === 3);

    // ---- S4: derivation-input failure -> unknown(reason), never a guess --
    const ghostPlan = findItem(items, 'ask-beta/ghost-plan');
    ok('S4 missing plan file renders unknown, never a confident bucket',
      ghostPlan && ghostPlan.status.value === 'unknown');
    ok('S4b unknown carries a named reason + label ("status unknown — …")',
      ghostPlan && !!ghostPlan.status.reason && /status unknown — /.test(ghostPlan.status.label || ''));
    const beta = findItem(items, 'ask-beta');
    ok('S4c the ancestor ROLLS UP the unknown (counted, with an exemplar id) — C1',
      beta && beta.roll_up && beta.roll_up.unknown && beta.roll_up.unknown.count >= 1 && !!beta.roll_up.unknown.exemplar);
    ok('S4d an intent whose EVERY child is underivable renders unknown itself — never a confident not-started (C5)',
      beta && beta.status.value === 'unknown' && /status unknown — /.test(beta.status.label || ''));

    // ---- S5: all-done + no deploy signal -> merged-unverified, OUTSIDE complete (A4)
    const shipped = findItem(items, 'ask-shipped');
    ok('S5 all-tasks-done with no deploy signal renders merged-unverified (never complete)',
      shipped && shipped.status.value === 'merged-unverified');
    ok('S5b merged-unverified label is the distinct operator copy ("merged — deploy unverified")',
      shipped && /merged — deploy unverified/.test(shipped.status.label || ''));

    // ---- S6: provenance classifier (A9 — operator vs machine-filed) ----
    const chore = findItem(items, 'ask-chore');
    ok('S6 machine-filed ask classifies provenance=machine with a named reason',
      chore && chore.provenance === 'machine' && !!chore.provenance_reason);
    ok('S6b operator ask classifies provenance=operator', alpha && alpha.provenance === 'operator');

    // ---- S7: from-your-request links (C6) propagate to descendants ----
    ok('S7 plan + task children carry from_requests naming the originating ask',
      ghostPlan && Array.isArray(ghostPlan.from_requests) && ghostPlan.from_requests.length === 1 &&
      ghostPlan.from_requests[0].id === 'ask-beta' && !!ghostPlan.from_requests[0].title);

    // ---- S8: rank move endpoint — REAL user action, end to end ----
    const move = await httpPostJson(PORT, '/api/roadmap/rank', { ask_id: 'ask-beta', direction: 'up' });
    ok('S8 POST /api/roadmap/rank succeeds (overlay fallback when the registry verb is absent)',
      move.status === 200 && move.json && move.json.ok === true, move.body && move.body.slice(0, 160));
    const r2 = await httpGet(PORT, '/api/roadmap');
    const topIds2 = ((r2.json && r2.json.items) || []).map((i) => i.id);
    ok('S8b a subsequent GET reflects the new build order (beta moved above alpha)',
      topIds2.indexOf('ask-beta') === topIds2.indexOf('ask-alpha') - 1, topIds2.join(','));

    // ---- S9: /roadmap.js is served by this handler (single mount line) ----
    const asset = await httpGet(PORT, '/roadmap.js');
    ok('S9 GET /roadmap.js serves the client module with a JS content type',
      asset.status === 200 && /javascript/.test(asset.headers['content-type'] || '') && asset.body.length > 1000);

    // ---- S10: operator manual done = complete, labeled as an override ----
    const done = findItem(items, 'ask-done');
    ok('S10 operator-done ask renders complete with completed_at set',
      done && done.status.value === 'complete' && !!done.completed_at);
    ok('S10b manual done is LABELED as an operator override, never silent',
      done && /override/.test(done.status.label || ''));

    // ---- S11: title endpoint delegates to the registry CLI; absent CLI =
    // named honest error (never a silent success, never a second title store)
    const title = await httpPostJson(PORT, '/api/roadmap/title', { ask_id: 'ask-alpha', title: 'A better name' });
    ok('S11 title update with no registry CLI returns ok:false with a plain-language error',
      title.json && title.json.ok === false && typeof title.json.error === 'string' && title.json.error.length > 10);
    // Now point at a fixture CLI that records its argv and accepts set-title.
    const cliLog = path.join(tmp, 'cli-args.log');
    const fakeCli = path.join(tmp, 'fake-ask-registry.sh');
    fs.writeFileSync(fakeCli, '#!/bin/bash\necho "$@" >> ' + JSON.stringify(cliLog.replace(/\\/g, '/')) + '\nexit 0\n');
    fs.chmodSync(fakeCli, 0o755);
    process.env.ASK_REGISTRY_CLI = fakeCli;
    const title2 = await httpPostJson(PORT, '/api/roadmap/title', { ask_id: 'ask-alpha', title: 'A better name' });
    const cliArgs = fs.existsSync(cliLog) ? fs.readFileSync(cliLog, 'utf8') : '';
    ok('S11b with the CLI present, the title edit DELEGATES (one-writer discipline): set-title --title-source operator',
      title2.json && title2.json.ok === true && /set-title/.test(cliArgs) && /--title-source operator/.test(cliArgs) && /A better name/.test(cliArgs),
      cliArgs.slice(0, 200));

    // ---- S12: rank move via CLI-present path prefers the registry verb ----
    const move2 = await httpPostJson(PORT, '/api/roadmap/rank', { ask_id: 'ask-beta', direction: 'down' });
    ok('S12 rank move with the CLI present delegates set-rank to the registry',
      move2.json && move2.json.ok === true && /set-rank/.test(fs.readFileSync(cliLog, 'utf8')));

    // ---- S13: title precedence (D2 task-verifier FAIL fix) — set-title's
    // REAL write shape (summary_updated + title_source:"operator", NOT the
    // title_set{title} shape no writer produces) must survive a NEWER auto
    // summary_updated (the async distiller re-running) AND report
    // title_source:"operator" correctly (not misreported "auto") on
    // /api/roadmap.
    const regFile = path.join(stateDir, 'ask-registry.jsonl');
    fs.appendFileSync(regFile, JSON.stringify({
      ask_id: 'ask-alpha', record_type: 'summary_updated', ts: '2026-07-16T09:00:00Z',
      summary: 'Alpha feature (operator title)', title_source: 'operator', emitter: 'operator-ui',
    }) + '\n');
    fs.appendFileSync(regFile, JSON.stringify({
      ask_id: 'ask-alpha', record_type: 'summary_updated', ts: '2026-07-16T10:00:00Z',
      summary: 'Alpha feature (distiller re-run, should be ignored)', title_source: 'auto', emitter: 'ask-registry',
    }) + '\n');
    const r13 = await httpGet(PORT, '/api/roadmap');
    const alpha13 = findItem((r13.json && r13.json.items) || [], 'ask-alpha');
    ok('S13 operator set-title (summary_updated + title_source:operator) survives a NEWER auto summary_updated (distiller re-run) — title AND title_source:"operator" both correct on /api/roadmap',
      alpha13 && alpha13.title === 'Alpha feature (operator title)' && alpha13.title_source === 'operator',
      alpha13 && JSON.stringify({ title: alpha13.title, title_source: alpha13.title_source }));

    // ---- S13b: a candidate_classified amendment LABEL (task 2's timeline
    // classifier — summary carries the distilled label, title_source is
    // EMPTY, never "operator"/"auto") must never retitle the ask (D1's rule,
    // applied identically at this route's own fold).
    fs.appendFileSync(regFile, JSON.stringify({
      ask_id: 'ask-alpha', record_type: 'candidate_classified', ts: '2026-07-16T11:00:00Z',
      summary: 'Scope grew to include the sidebar', title_source: '', classification: 'amendment', candidate_id: 'cand-1',
    }) + '\n');
    const r13b = await httpGet(PORT, '/api/roadmap');
    const alpha13b = findItem((r13b.json && r13b.json.items) || [], 'ask-alpha');
    ok('S13b a candidate_classified amendment label never retitles the ask — title stays the operator title, unchanged',
      alpha13b && alpha13b.title === 'Alpha feature (operator title)', alpha13b && alpha13b.title);

    // ---- S14: error honesty — a torn registry file never crashes the route
    fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'), '{"broken json\n');
    const r3 = await httpGet(PORT, '/api/roadmap');
    ok('S14 corrupt registry degrades to an EMPTY-BUT-OK payload (readers skip bad records), never a 500 crash',
      r3.status === 200 && r3.json && r3.json.ok === true && Array.isArray(r3.json.items) && r3.json.items.length === 0);
  } finally {
    server.close();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('roadmap-routes self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
