'use strict';
// roadmap-routes.selftest.js — sandboxed self-test for the Roadmap view's
// server surface. RE-ROOTED per the 2026-07-21 design-input Round 8
// operator decision (docs/reviews/2026-07-17-cockpit-ux-design-input.md,
// "Round 8"): the tree roots on PLAN FILES now, not the ask-registry — this
// suite's fixtures and assertions were rewritten end to end to match.
//
// REAL-SCENARIO discipline (no mocking the SUT): fixtures are REAL files —
// a real ask-registry.jsonl, real progress-log JSONL, real plan .md files
// in a fixture repo — under a mktemp sandbox selected via the SAME env
// overrides the shell writer libs already honor (ASK_REGISTRY_STATE_DIR /
// PROGRESS_LOG_STATE_DIR), PLUS a dedicated ROADMAP_PLAN_SCAN_ROOT override
// so the plan-file DISCOVERY scan never touches the real checkout's own
// docs/plans/. Requests are REAL HTTP GET/POSTs against the mounted
// handler.
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
  fs.mkdirSync(path.join(repoDir, 'docs', 'plans', 'archive'), { recursive: true });
  fs.mkdirSync(heartbeatDir, { recursive: true });

  process.env.ASK_REGISTRY_STATE_DIR = stateDir;
  process.env.PROGRESS_LOG_STATE_DIR = progressDir;
  process.env.HEARTBEAT_STATE_DIR = heartbeatDir;
  // Round 8: the plan-file DISCOVERY scan root is now independently
  // sandboxable — never the real checkout's docs/plans/.
  process.env.ROADMAP_PLAN_SCAN_ROOT = repoDir;
  fs.writeFileSync(path.join(heartbeatDir, 'sess-op-1.json'), JSON.stringify({
    schema: 1, session_id: 'sess-op-1', pid: 1, cwd: repoDir, repo_root: repoDir,
    worktree_root: repoDir, branch: 'fixture', model: 'fixture',
    last_activity_ts: new Date().toISOString(), last_event: 'fixture', marker_state: 'active',
  }));
  // Point the CLI delegation at a nonexistent path by default: the rank
  // endpoint must fall back to its overlay store honestly, and the title
  // endpoint must return a NAMED error, never a silent success.
  process.env.ASK_REGISTRY_CLI = path.join(tmp, 'no-such-cli.sh');

  // GHOST-BOUNDING fixture timestamps (2026-07-21 fix): computed relative
  // to the ACTUAL test-run time, not a fixed 2026-07 date string, so the
  // recent/ancient distinction holds regardless of when this suite runs.
  const RECENT_ASK_TS = new Date(Date.now() - 2 * 86400000).toISOString(); // 2 days ago
  const ANCIENT_ASK_TS = new Date(Date.now() - 400 * 86400000).toISOString(); // well over a year ago

  // ---- fixture plan files -------------------------------------------------
  // demo-plan: 3 tasks — 1 done, 1 started-in-flight, 1 untouched. Linked
  // to ask-alpha.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'demo-plan.md'), [
    '# Plan: demo', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [x] 1. build the first thing',
    '- [ ] 2. build the second thing',
    '- [ ] 3. build the third thing',
    '',
  ].join('\n'));
  // shipped-plan: all tasks done -> the no-signal oracle class must render
  // as merged-unverified, OUTSIDE complete (A4 binding rule). Linked to
  // ask-shipped.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'shipped-plan.md'), [
    '# Plan: shipped', '', 'Status: COMPLETED', '', '## Tasks', '',
    '- [x] 1. everything',
    '- [x] 2. is checked',
    '',
  ].join('\n'));
  // rich-plan: ONE task with the real "**Bold lead-in.** prose — - **Label:**
  // body — - **Label2:** body2" convention this repo's own plans use
  // (round-6/7 fixture). Linked to ask-rich.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'rich-plan.md'), [
    '# Plan: rich', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. [serial] **Derived top-level status foundation.** Per-item status',
    '  computed, never declared. Fixes the done-renders-ACTIVE defect.',
    '  - **Enum (C5):** not-started / in-progress / complete / stalled(reason).',
    '    When any derivation input fails the item renders unknown(reason), never',
    '    a confident bucket.',
    '  - **Complete oracle (A4):** per-project completion-oracle config with',
    '    three named classes.',
    '',
  ].join('\n'));
  // ROUND 8 (b): redesign-plan has NO linked ask at all — the operator's
  // own "active plan with no ask" scenario (the real defect round 8
  // fixes: this plan used to be invisible under the ask-rooted tree).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'redesign-plan.md'), [
    '# Plan: redesign', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [x] 1. re-root the tree on plans',
    '- [ ] 2. verify junk is hidden',
    '',
  ].join('\n'));
  // done-plan: linked to ask-done, which the operator marks done/merged
  // manually (A4 labeled override) — some tasks are STILL unchecked, so
  // this proves the override wins regardless of raw checkbox counts.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'done-plan.md'), [
    '# Plan: done', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [x] 1. first part shipped',
    '- [ ] 2. second part still unchecked',
    '',
  ].join('\n'));
  // dismissed-linked-plan: linked ONLY to a DISMISSED ask — proves a real
  // plan file still roots the tree (8A is unconditional on ask status) but
  // carries NO from_requests (a dismissed ask's linkage is not honored as
  // provenance).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'dismissed-linked-plan.md'), [
    '# Plan: dismissed-linked', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. still a real plan even though its only linked ask was dismissed',
    '',
  ].join('\n'));
  // spec-appendix: Status: REFERENCE ("not an independent plan") — must be
  // EXCLUDED (matches the real corpus's nl-overhaul-program specs-b/c/d/e/f
  // shape found in the whole-corpus scan, 2026-07-21).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'spec-appendix.md'), [
    '# Spec appendix', '', 'Status: REFERENCE (spec appendix, not an independent plan)', '',
    'Just prose, no task list.', '',
  ].join('\n'));
  // some-evidence: NO Status: header at all — matches the real corpus's
  // `*-evidence*.md` dumps (0/20 carry a Status header) — must be EXCLUDED.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'some-evidence.md'), [
    '# Evidence dump', '', 'Just captured command output, no plan structure.', '',
  ].join('\n'));
  // archive/old-plan: COMPLETED, with NO recency evidence at all (no ask
  // link, no progress-log event) — "ancient archived plans stay out"
  // (round 8). NOTE (2026-07-21 fix): eligibility is EVIDENCE-gated, not
  // mtime-gated — file mtime is untrustworthy in a git-worktree checkout
  // (every file reads as "just checked out" regardless of true history;
  // see roadmap-routes.js's scanPlanDir header for the full real-data
  // proof), so this fixture deliberately does NOT rely on fs.utimesSync
  // to prove exclusion — the absence of any evidence is what excludes it,
  // exactly like production.
  const oldPlanAbs = path.join(repoDir, 'docs', 'plans', 'archive', 'old-plan.md');
  fs.writeFileSync(oldPlanAbs, [
    '# Plan: old', '', 'Status: COMPLETED', '', '## Tasks', '',
    '- [x] 1. ancient work',
    '',
  ].join('\n'));
  // archive/recent-plan: COMPLETED, no linked ask, but a REAL progress-log
  // task_done event within the aging window (the shared "unlinked" lane) —
  // the worktree-independent recency EVIDENCE that includes it (2026-07-21
  // fix: bare mtime no longer counts at all, since it cannot be trusted).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'archive', 'recent-plan.md'), [
    '# Plan: recent', '', 'Status: COMPLETED', '', '## Tasks', '',
    '- [x] 1. recently finished work',
    '',
  ].join('\n'));
  // ghost-plan deliberately DOES NOT EXIST on disk -> unknown(reason).

  // ---- fixture registry --------------------------------------------------
  const reg = [
    // ask-alpha: operator ask, demo-plan linked (in-progress overall).
    { ask_id: 'ask-alpha', record_type: 'created', ts: '2026-07-10T10:00:00Z', summary: 'Build the alpha feature', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-1', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-alpha', record_type: 'plan_linked', ts: '2026-07-10T10:05:00Z', plan_slug: 'demo-plan' },
    // ask-rich: operator ask, rich-plan linked (round-6/7 fixture).
    { ask_id: 'ask-rich', record_type: 'created', ts: '2026-07-13T10:00:00Z', summary: 'Rich structured ask', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-1', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-rich', record_type: 'plan_linked', ts: '2026-07-13T10:05:00Z', plan_slug: 'rich-plan' },
    // ask-beta: operator ask, ghost-plan linked (derivation input missing ->
    // unknown). RECENT (2 days ago) — this is the real C5 signal ("current
    // work went dark"), which must still surface as an honest unknown root.
    { ask_id: 'ask-beta', record_type: 'created', ts: RECENT_ASK_TS, summary: 'Beta effort', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-2', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-beta', record_type: 'plan_linked', ts: RECENT_ASK_TS, plan_slug: 'ghost-plan' },
    // ask-ancient-ghost: linked to a plan slug that ALSO never existed on
    // disk, but its ONLY link is 400 days old — GHOST-BOUNDING (2026-07-21):
    // must be EXCLUDED from items entirely (never a permanent dead root)
    // and counted in stale_links_omitted instead.
    { ask_id: 'ask-ancient-ghost', record_type: 'created', ts: ANCIENT_ASK_TS, summary: 'Ancient effort, long since forgotten', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-6', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-ancient-ghost', record_type: 'plan_linked', ts: ANCIENT_ASK_TS, plan_slug: 'ancient-ghost-plan' },
    // ask-shipped: all-done plan, no deploy signal -> merged-unverified.
    { ask_id: 'ask-shipped', record_type: 'created', ts: '2026-07-09T10:00:00Z', summary: 'Ship the widget', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-3', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-shipped', record_type: 'plan_linked', ts: '2026-07-09T10:05:00Z', plan_slug: 'shipped-plan' },
    // ask-done: operator marked done (manual override, labeled) — linked to
    // done-plan, which still has an unchecked task (proves override wins).
    { ask_id: 'ask-done', record_type: 'created', ts: '2026-07-01T10:00:00Z', summary: 'Old finished thing', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-4', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-done', record_type: 'plan_linked', ts: '2026-07-01T10:05:00Z', plan_slug: 'done-plan' },
    { ask_id: 'ask-done', record_type: 'status_change', ts: '2026-07-02T10:00:00Z', status: 'done', emitter: 'operator-ui' },
    // ask-dismissed: linked to dismissed-linked-plan, but its OWN status is
    // dismissed -> its linkage must NOT surface as provenance.
    { ask_id: 'ask-dismissed', record_type: 'created', ts: '2026-07-03T10:00:00Z', summary: 'Abandoned idea', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-5', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-dismissed', record_type: 'plan_linked', ts: '2026-07-03T10:05:00Z', plan_slug: 'dismissed-linked-plan' },
    { ask_id: 'ask-dismissed', record_type: 'status_change', ts: '2026-07-04T10:00:00Z', status: 'dismissed', emitter: 'operator-ui' },
    // ROUND 8 (c): junk conversational captures with NO plan_linked record
    // AT ALL — the real production-data shapes found in ~/.claude/state/
    // ask-registry.jsonl (2026-07-21 spot-check), reproduced verbatim as the
    // fixture. These must NEVER appear on a plan-rooted Roadmap.
    { ask_id: 'ask-junk1', record_type: 'created', ts: '2026-07-05T10:00:00Z', summary: 'The computer rebooted.', repo: repoDir, project: '', origin_session: '', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-junk2', record_type: 'created', ts: '2026-07-06T10:00:00Z', summary: 'is that really the cleanest way to manage this process?', repo: repoDir, project: '', origin_session: '', status: 'active', emitter: 'ask-registry' },
    // ask-chore: machine-filed, ALSO no plan_linked — a second, distinct
    // junk shape (mechanism-filed rather than conversational fragment).
    { ask_id: 'ask-chore', record_type: 'created', ts: '2026-07-12T10:00:00Z', summary: 'nl-issue: tighten a gate message', repo: repoDir, project: 'neural-lace', origin_session: '', status: 'active', emitter: 'auto-sweep' },
  ];
  fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'),
    reg.map((r) => JSON.stringify(r)).join('\n') + '\n');

  // ---- fixture progress events ------------------------------------------
  fs.writeFileSync(path.join(progressDir, 'ask-alpha.jsonl'), [
    JSON.stringify({ type: 'task_started', ts: '2026-07-15T09:00:00Z', plan_slug: 'demo-plan', task_id: '2', session_id: 'sess-op-1' }),
    JSON.stringify({ type: 'task_done', ts: '2026-07-14T18:00:00Z', plan_slug: 'demo-plan', task_id: '1', session_id: 'sess-op-1', evidence_link: '' }),
  ].join('\n') + '\n');
  // rich-plan's task 1 is in-progress with TWO attached sessions — sess-op-1
  // (the LIVE fixture heartbeat, fresh last_activity_ts) and sess-ghost (a
  // session with NO heartbeat file at all) — the 7B-i fixture, covering
  // both the "running" and the "unknown, no heartbeat evidence" leaf.
  fs.writeFileSync(path.join(progressDir, 'ask-rich.jsonl'), [
    JSON.stringify({ type: 'task_started', ts: '2026-07-15T09:00:00Z', plan_slug: 'rich-plan', task_id: '1', session_id: 'sess-op-1' }),
    JSON.stringify({ type: 'task_started', ts: '2026-07-15T09:05:00Z', plan_slug: 'rich-plan', task_id: '1', session_id: 'sess-ghost' }),
  ].join('\n') + '\n');
  // redesign-plan and recent-plan are both UNLINKED — their task_done
  // events land in the shared "unlinked" orphan lane (progress-log-lib.sh's
  // own documented fallback for events emitted with no ask_id), keyed only
  // by plan_slug. recent-plan's event uses RECENT_ASK_TS (relative to NOW,
  // not a fixed 2026-07 date) — this IS the worktree-independent recency
  // EVIDENCE that includes it in the archive scan (2026-07-21 fix).
  fs.writeFileSync(path.join(progressDir, 'unlinked.jsonl'), [
    JSON.stringify({ type: 'task_done', ts: '2026-07-20T09:00:00Z', plan_slug: 'redesign-plan', task_id: '1' }),
    JSON.stringify({ type: 'task_done', ts: RECENT_ASK_TS, plan_slug: 'recent-plan', task_id: '1' }),
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
    // ---- S1: payload shape + default build order --------------------------
    const r1 = await httpGet(PORT, '/api/roadmap');
    ok('S1 GET /api/roadmap returns ok:true with items[]', r1.status === 200 && r1.json && r1.json.ok === true && Array.isArray(r1.json.items));
    const items = (r1.json && r1.json.items) || [];
    const topIds = items.map((i) => i.id);

    // ---- ROUND 8 (a): the roots are PLANS, never asks ----------------------
    ok('R8a every top-level item is kind:"plan" (the tree roots on plan files, never on asks/intents)',
      items.length > 0 && items.every((i) => i.kind === 'plan'), topIds.join(','));
    ok('R8a no ask id ever appears as a top-level id (the old ask-rooted ids are gone)',
      topIds.every((id) => id.indexOf('ask-') !== 0), topIds.join(','));

    ok('S1b build order: the 4 explicitly-2026-07-dated items sort by their (linked-ask-inherited) added_ts ascending (ghost-plan is asserted separately below — its recency-gating timestamp is relative to NOW, not a fixed 2026-07 date, so it does not belong in this fixed chain)',
      topIds.indexOf('done-plan') < topIds.indexOf('shipped-plan') &&
      topIds.indexOf('shipped-plan') < topIds.indexOf('demo-plan') &&
      topIds.indexOf('demo-plan') < topIds.indexOf('rich-plan'),
      topIds.join(','));
    ok('S1c the unlinked/mtime-or-recency-fallback items all appear, order unasserted (redesign-plan, dismissed-linked-plan, recent-plan: mtime/now fallback; ghost-plan: RECENT per the ghost-bounding fix, still a real C5 unknown root)',
      topIds.indexOf('redesign-plan') !== -1 && topIds.indexOf('dismissed-linked-plan') !== -1 &&
      topIds.indexOf('recent-plan') !== -1 && topIds.indexOf('ghost-plan') !== -1,
      topIds.join(','));
    ok('S1d payload carries the single completed-aging tunable (completed_age_days)',
      typeof (r1.json && r1.json.completed_age_days) === 'number');
    ok('S1e exactly 8 top-level plans (the ones that qualify) — no more, no less; ancient-ghost-plan is correctly EXCLUDED (not a 9th item)',
      items.length === 8, topIds.join(','));

    // ---- GHOST-BOUNDING (2026-07-21 fix): a recently-linked missing plan
    // still renders as an honest unknown root; an ANCIENT one (its only
    // link 400 days old) is excluded entirely but counted, never silently
    // dropped and never a permanent dead root.
    ok('ghost-bounding: an ANCIENT ghost link (400 days old) never becomes a root',
      topIds.indexOf('ancient-ghost-plan') === -1, topIds.join(','));
    ok('ghost-bounding: the ancient ghost is COUNTED in stale_links_omitted (named aggregate, never a silent drop)',
      r1.json.stale_links_omitted === 1, JSON.stringify(r1.json.stale_links_omitted));

    // ---- ROUND 8 (b): an active plan with NO linked ask still appears -----
    const redesign = findItem(items, 'redesign-plan');
    ok('R8b redesign-plan (NO linked ask at all) still appears as a top-level root',
      !!redesign && redesign.kind === 'plan');
    ok('R8b redesign-plan carries an empty from_requests (never a fabricated provenance link)',
      redesign && Array.isArray(redesign.from_requests) && redesign.from_requests.length === 0);
    ok('R8b redesign-plan derives real task status from the UNLINKED progress-log lane (task 1 done via the shared "unlinked" file)',
      findItem(items, 'redesign-plan/1') && findItem(items, 'redesign-plan/1').status.value === 'complete');
    ok('R8b redesign-plan task 2 (never touched) renders not-started',
      findItem(items, 'redesign-plan/2') && findItem(items, 'redesign-plan/2').status.value === 'not-started');

    // ---- ROUND 8 (c): junk asks with no plan never appear ------------------
    ok('R8c "The computer rebooted." (a real junk capture, no plan_linked) does not appear anywhere on the roadmap',
      topIds.indexOf('ask-junk1') === -1 && JSON.stringify(items).indexOf('The computer rebooted') === -1);
    ok('R8c "is that really the cleanest way..." (a real junk capture, no plan_linked) does not appear anywhere on the roadmap',
      topIds.indexOf('ask-junk2') === -1 && JSON.stringify(items).indexOf('cleanest way') === -1);
    ok('R8c a machine-filed chore ask with no plan_linked also never appears (8B is unconditional on provenance, not just conversational junk)',
      topIds.indexOf('ask-chore') === -1 && JSON.stringify(items).indexOf('tighten a gate message') === -1);

    // ---- provenance: a plan linked ONLY to a DISMISSED ask still roots the
    // tree (8A does not depend on ask status) but carries no from_requests.
    const dismissedLinked = findItem(items, 'dismissed-linked-plan');
    ok('a plan linked only to a dismissed ask still appears (a real plan file is real build work regardless of the linking ask\'s fate)',
      !!dismissedLinked);
    ok('...but its from_requests is empty (a dismissed ask\'s link is never honored as provenance, C6)',
      dismissedLinked && Array.isArray(dismissedLinked.from_requests) && dismissedLinked.from_requests.length === 0);

    // ---- REFERENCE/NORMATIVE + header-less exclusion (the plan-file
    // eligibility filter, documented in roadmap-routes.js's own header) ----
    ok('a Status: REFERENCE file ("not an independent plan") never becomes a root',
      topIds.indexOf('spec-appendix') === -1);
    ok('a file with NO Status: header at all (an evidence-dump shape) never becomes a root',
      topIds.indexOf('some-evidence') === -1);

    // ---- archive aging: EVIDENCE-gated, not mtime-gated (2026-07-21 fix) --
    // File mtime is untrustworthy (a git-worktree checkout resets it
    // regardless of true archival history — see scanPlanDir's header for
    // the real-data proof); old-plan has NO recency evidence at all (no ask
    // link, no progress event) and must be excluded on that basis alone.
    ok('an archived plan with NO recency evidence at all (no ask link, no progress-log event) is EXCLUDED entirely ("ancient archived plans stay out")',
      topIds.indexOf('old-plan') === -1);
    const recent = findItem(items, 'recent-plan');
    ok('an archived plan WITH a real progress-log event inside the aging window is included',
      !!recent);
    ok('its completed_at is sourced from the real task_done event (not a guessed/mtime-derived timestamp)',
      recent && !!recent.completed_at);

    // ---- S2: six-value enum only, everywhere -------------------------------
    const ENUM = ['not-started', 'in-progress', 'merged-unverified', 'complete', 'stalled', 'unknown'];
    const badStatuses = [];
    (function walk(list) {
      (list || []).forEach((it) => {
        if (!it.status || ENUM.indexOf(it.status.value) === -1) badStatuses.push(it.id + '=' + (it.status && it.status.value));
        walk(it.children);
      });
    })(items);
    ok('S2 every item status is one of the six enum values (no seventh state, no missing status)', badStatuses.length === 0, badStatuses.join(','));

    // ---- S3: task-level statuses from real plan checkboxes + events --------
    const t1 = findItem(items, 'demo-plan/1');
    const t2 = findItem(items, 'demo-plan/2');
    const t3 = findItem(items, 'demo-plan/3');
    ok('S3 checked task renders complete', t1 && t1.status.value === 'complete');
    ok('S3b started-unchecked task renders in-progress with a since timestamp',
      t2 && t2.status.value === 'in-progress' && !!t2.status.since);
    ok('S3c untouched task renders not-started', t3 && t3.status.value === 'not-started');
    const demoPlan = findItem(items, 'demo-plan');
    ok('S3d parent with an in-progress child renders in-progress', demoPlan && demoPlan.status.value === 'in-progress');
    ok('S3e progress carries child counts (1 done of 3)', demoPlan && demoPlan.progress && demoPlan.progress.done === 1 && demoPlan.progress.total === 3);

    // ---- S4: derivation-input failure -> unknown(reason), never a guess ----
    const ghostPlan = findItem(items, 'ghost-plan');
    ok('S4 missing plan file renders unknown, never a confident bucket',
      ghostPlan && ghostPlan.status.value === 'unknown');
    ok('S4b unknown carries a named reason + label ("status unknown — …")',
      ghostPlan && !!ghostPlan.status.reason && /status unknown — /.test(ghostPlan.status.label || ''));

    // ---- S5: all-done + no deploy signal -> merged-unverified, OUTSIDE complete (A4)
    const shipped = findItem(items, 'shipped-plan');
    ok('S5 all-tasks-done with no deploy signal renders merged-unverified (never complete)',
      shipped && shipped.status.value === 'merged-unverified');
    ok('S5b merged-unverified label is the distinct operator copy ("merged — deploy unverified")',
      shipped && /merged — deploy unverified/.test(shipped.status.label || ''));

    // ---- S7: from-your-request links (C6) propagate to descendants --------
    ok('S7 plan + task children carry from_requests naming the originating ask',
      ghostPlan && Array.isArray(ghostPlan.from_requests) && ghostPlan.from_requests.length === 1 &&
      ghostPlan.from_requests[0].id === 'ask-beta' && !!ghostPlan.from_requests[0].title);

    // ---- S8: rank move endpoint (now id-keyed, plan-slug-scoped) -----------
    // ghost-plan's default position is no longer a fixed 2026-07 slot (its
    // recency-gating timestamp is relative to NOW — the ghost-bounding
    // fix), so this asserts the MOVE mechanically (an adjacent swap with
    // whoever preceded it) rather than a specific named neighbor.
    const ghostIdxBefore = topIds.indexOf('ghost-plan');
    const predecessorBefore = topIds[ghostIdxBefore - 1];
    const move = await httpPostJson(PORT, '/api/roadmap/rank', { id: 'ghost-plan', direction: 'up' });
    ok('S8 POST /api/roadmap/rank succeeds (overlay fallback when the registry verb is absent)',
      move.status === 200 && move.json && move.json.ok === true, move.body && move.body.slice(0, 160));
    const r2 = await httpGet(PORT, '/api/roadmap');
    const topIds2 = ((r2.json && r2.json.items) || []).map((i) => i.id);
    ok('S8b a subsequent GET reflects the new build order: ghost-plan moved up exactly one slot, swapping with its prior predecessor',
      topIds2.indexOf('ghost-plan') === ghostIdxBefore - 1 && topIds2[ghostIdxBefore] === predecessorBefore,
      topIds2.join(','));

    // ---- S9: /roadmap.js is served by this handler (single mount line) ----
    const asset = await httpGet(PORT, '/roadmap.js');
    ok('S9 GET /roadmap.js serves the client module with a JS content type',
      asset.status === 200 && /javascript/.test(asset.headers['content-type'] || '') && asset.body.length > 1000);

    // ---- S10: operator manual done = complete, labeled as an override -----
    const donePlan = findItem(items, 'done-plan');
    ok('S10 a linked ask marked done renders its PLAN complete, even with an unchecked task (A4 override wins over raw checkbox counts)',
      donePlan && donePlan.status.value === 'complete' && !!donePlan.completed_at);
    ok('S10b manual done is LABELED as an operator override, never silent',
      donePlan && /override/.test(donePlan.status.label || ''));

    // ---- S11: title endpoint delegates to the registry CLI; absent CLI =
    // named honest error (never a silent success, never a second title store)
    const title = await httpPostJson(PORT, '/api/roadmap/title', { id: 'demo-plan', title: 'A better name' });
    ok('S11 title update with no registry CLI returns ok:false with a plain-language error',
      title.json && title.json.ok === false && typeof title.json.error === 'string' && title.json.error.length > 10);
    ok('S11c title update on an UNLINKED plan (no ask to delegate through) returns a DIFFERENT, honest "no linked request" error — never a silent success, never inventing a store',
      (await httpPostJson(PORT, '/api/roadmap/title', { id: 'redesign-plan', title: 'x' })).json.error === 'this plan has no linked request to attach a title edit to yet');
    // Now point at a fixture CLI that records its argv and accepts set-title.
    const cliLog = path.join(tmp, 'cli-args.log');
    const fakeCli = path.join(tmp, 'fake-ask-registry.sh');
    fs.writeFileSync(fakeCli, '#!/bin/bash\necho "$@" >> ' + JSON.stringify(cliLog.replace(/\\/g, '/')) + '\nexit 0\n');
    fs.chmodSync(fakeCli, 0o755);
    process.env.ASK_REGISTRY_CLI = fakeCli;
    const title2 = await httpPostJson(PORT, '/api/roadmap/title', { id: 'demo-plan', title: 'A better name' });
    const cliArgs = fs.existsSync(cliLog) ? fs.readFileSync(cliLog, 'utf8') : '';
    ok('S11b with the CLI present, the title edit DELEGATES (one-writer discipline) to demo-plan\'s FIRST linked ask (ask-alpha): set-title --title-source operator',
      title2.json && title2.json.ok === true && /set-title/.test(cliArgs) && /ask-alpha/.test(cliArgs) &&
      /--title-source operator/.test(cliArgs) && /A better name/.test(cliArgs),
      cliArgs.slice(0, 200));

    // ---- S12: rank move via CLI-present path prefers the registry verb ----
    const move2 = await httpPostJson(PORT, '/api/roadmap/rank', { id: 'ghost-plan', direction: 'down' });
    ok('S12 rank move with the CLI present delegates set-rank to ghost-plan\'s linked ask-beta',
      move2.json && move2.json.ok === true && /set-rank/.test(fs.readFileSync(cliLog, 'utf8')) && /ask-beta/.test(fs.readFileSync(cliLog, 'utf8')));
    ok('S12b rank move on an UNLINKED plan still reorders (the plan-rank overlay is unconditional) but honestly reports registry_recorded:false (no ask to delegate through)',
      (await httpPostJson(PORT, '/api/roadmap/rank', { id: 'redesign-plan', direction: 'up' })).json.registry_recorded === false);

    // ---- S13: title precedence — set-title's REAL write shape
    // (summary_updated + title_source:"operator") must survive a NEWER auto
    // summary_updated (the async distiller re-running) AND report
    // title_source:"operator" correctly on /api/roadmap, now read off the
    // PLAN node (demo-plan) rather than an ask/intent node.
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
    const demoPlan13 = findItem((r13.json && r13.json.items) || [], 'demo-plan');
    ok('S13 operator set-title survives a NEWER auto summary_updated (distiller re-run) — title AND title_source:"operator" both correct on the PLAN node',
      demoPlan13 && demoPlan13.title === 'Alpha feature (operator title)' && demoPlan13.title_source === 'operator',
      demoPlan13 && JSON.stringify({ title: demoPlan13.title, title_source: demoPlan13.title_source }));

    // ---- S13b: a candidate_classified amendment LABEL must never retitle --
    fs.appendFileSync(regFile, JSON.stringify({
      ask_id: 'ask-alpha', record_type: 'candidate_classified', ts: '2026-07-16T11:00:00Z',
      summary: 'Scope grew to include the sidebar', title_source: '', classification: 'amendment', candidate_id: 'cand-1',
    }) + '\n');
    const r13b = await httpGet(PORT, '/api/roadmap');
    const demoPlan13b = findItem((r13b.json && r13b.json.items) || [], 'demo-plan');
    ok('S13b a candidate_classified amendment label never retitles the plan — title stays the operator title, unchanged',
      demoPlan13b && demoPlan13b.title === 'Alpha feature (operator title)', demoPlan13b && demoPlan13b.title);

    // ---- S15-S19: round-6 gap 1 + round-7 7A/7B/7B-i — task-leaf
    // distillation, sentence-split lists, sub-bullet structure, live-agent
    // leaves — against the REAL rich-plan fixture, now at its plan-rooted
    // id (rich-plan/1, no more ask-rich/ prefix).
    const richTask = findItem(items, 'rich-plan/1');
    ok('S15 the task-leaf TITLE is the distilled bold lead-in, never the raw folded plan-markdown wall (gap 1)',
      richTask && richTask.title === 'task 1: Derived top-level status foundation',
      richTask && richTask.title);
    ok('S15b the raw folded text (Enum/Complete-oracle sub-bullet prose) never appears in the title',
      richTask && richTask.title.indexOf('Complete oracle') === -1 && richTask.title.length < 80,
      richTask && richTask.title);
    ok('S16 the task carries lead_points as an ARRAY of sentences (7A: list, never a paragraph), covering the text the title did not consume',
      richTask && Array.isArray(richTask.lead_points) && richTask.lead_points.length >= 1 &&
      richTask.lead_points.every((p) => typeof p === 'string') &&
      richTask.lead_points.join(' ').indexOf('Per-item status') !== -1,
      richTask && JSON.stringify(richTask.lead_points));
    ok('S17 the task carries its sub-bullets as REAL subtask nodes (round 7B: visible task -> subtask hierarchy), each with a distilled title',
      richTask && Array.isArray(richTask.subtasks) && richTask.subtasks.length === 2 &&
      richTask.subtasks[0].title === 'Enum (C5)' && richTask.subtasks[1].title === 'Complete oracle (A4)',
      richTask && JSON.stringify(richTask.subtasks.map((s) => s.title)));
    ok('S17b each subtask body is ALSO a sentence-split array, never a raw paragraph blob',
      richTask && Array.isArray(richTask.subtasks[0].body_points) && richTask.subtasks[0].body_points.length >= 2,
      richTask && JSON.stringify(richTask.subtasks[0].body_points));
    ok('S18 an in-progress task with an attached LIVE-heartbeat session carries it as a live_sessions agent leaf, status=running (round 7B-i)',
      richTask && Array.isArray(richTask.live_sessions) && richTask.live_sessions.length === 2 &&
      richTask.live_sessions.some((a) => a.kind === 'agent' && a.title.indexOf('sess-op-1') !== -1 && a.status.value === 'running'),
      richTask && JSON.stringify(richTask.live_sessions));
    ok('S19 a task attached to a session with NO matching heartbeat file renders that agent leaf as unknown (named-absence, never a guessed "running")',
      richTask && richTask.live_sessions.some((a) => a.title.indexOf('sess-ghost') !== -1 &&
        a.status.value === 'unknown' && /no heartbeat/i.test(a.status.label || '')),
      richTask && JSON.stringify(richTask.live_sessions));
    const demoT1 = findItem(items, 'demo-plan/1'); // done task -> no live agents (work is finished)
    ok('S19b a DONE task carries NO live_sessions (finished work has no "currently running" agent)',
      demoT1 && Array.isArray(demoT1.live_sessions) && demoT1.live_sessions.length === 0,
      demoT1 && JSON.stringify(demoT1.live_sessions));

    // ---- S14: error honesty — a torn registry file never crashes the route,
    // AND (round 8) the roadmap now SURVIVES a corrupt registry entirely,
    // since plan files are the root and are read independent of the
    // registry — this is a deliberate, positive consequence of 8A, not a
    // regression: the old ask-rooted design went fully empty on this exact
    // input.
    fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'), '{"broken json\n');
    const r3 = await httpGet(PORT, '/api/roadmap');
    ok('S14 corrupt registry never crashes the route (still ok:true)',
      r3.status === 200 && r3.json && r3.json.ok === true && Array.isArray(r3.json.items));
    const idsAfterCorrupt = (r3.json.items || []).map((i) => i.id);
    ok('S14b ...and the plan files STILL root the tree (filesystem-native, independent of the now-unreadable registry) — a corrupt registry no longer means an empty Roadmap',
      idsAfterCorrupt.indexOf('demo-plan') !== -1 && idsAfterCorrupt.indexOf('redesign-plan') !== -1,
      idsAfterCorrupt.join(','));
    const demoPlanAfterCorrupt = findItem(r3.json.items, 'demo-plan');
    ok('S14c ...with from_requests honestly empty (provenance genuinely cannot be derived from an unreadable registry — never fabricated)',
      demoPlanAfterCorrupt && Array.isArray(demoPlanAfterCorrupt.from_requests) && demoPlanAfterCorrupt.from_requests.length === 0);
  } finally {
    server.close();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('roadmap-routes self-test: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
