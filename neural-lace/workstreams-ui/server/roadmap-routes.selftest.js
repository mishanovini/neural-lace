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
const { spawnSync } = require('child_process');

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

// findItem(items, id) — depth-first search over the payload tree. Recurses
// into BOTH `children` (a plan's own tasks) and `child_plans` (R11: a
// master's RESOLVED child plans, nested per Critical 3/4 — no longer
// present at the top level once resolved).
function findItem(items, id) {
  for (let i = 0; i < (items || []).length; i++) {
    if (items[i].id === id) return items[i];
    const hit = findItem(items[i].children, id) || findItem(items[i].child_plans, id);
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
  // pid: process.pid (2026-08-04 phantom-running fix) — every fixture
  // heartbeat meant to render 'running'/'live' now needs a pid that is
  // GENUINELY alive at test time, since roadmap-routes.js's classification
  // path is now pid-aware (classifyHeartbeatLiveness). This self-test
  // process's own pid is alive for the test's entire duration — the
  // realistic stand-in for "a real dispatcher session's heartbeat carries
  // its own real, live pid". A small fixed integer (the pre-fix fixture
  // value) is essentially never a real running process and would now
  // (correctly) classify crashed.
  fs.writeFileSync(path.join(heartbeatDir, 'sess-op-1.json'), JSON.stringify({
    schema: 1, session_id: 'sess-op-1', pid: process.pid, cwd: repoDir, repo_root: repoDir,
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

  // RECENT_TASK_STARTED_TS_* (false-eternal-running fix, 2026-07-30):
  // task_started fixture timestamps must now be relative to the ACTUAL
  // test-run time, not a fixed 2026-07-15 date — deriveItemStatus's new
  // task_started idle-expiry (COCKPIT_TASK_STARTED_IDLE_MIN, default
  // 60min) would otherwise treat every pre-existing "in-progress" fixture
  // below as stale-by-construction regardless of when this suite runs
  // (same worktree-mtime-independence concern RECENT_ASK_TS/ANCIENT_ASK_TS
  // already solve for plan-archival recency, applied to this new axis).
  // Two distinct values (10min, 9min ago) preserve rich-plan/1's original
  // two-events-in-order shape (the second event is the more recent one).
  const RECENT_TASK_STARTED_TS = new Date(Date.now() - 10 * 60000).toISOString(); // 10 min ago
  const RECENT_TASK_STARTED_TS_2 = new Date(Date.now() - 9 * 60000).toISOString(); // 9 min ago
  const STALE_TASK_STARTED_TS = new Date(Date.now() - 2 * 60 * 60000).toISOString(); // 2h ago — past the 60min default idle window

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
  // R11-A fixtures (operator round 11): the master/child mechanical link
  // (`parent-plan:` header) + lettered-batch task ids — the shapes the old
  // grammar silently dropped.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'master-fixture.md'), [
    '# Plan: The Master Sequence', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. direct master task',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'child-a-fixture.md'), [
    '# Plan: Child A', '', 'Status: ACTIVE', 'parent-plan: master-fixture', '', '## Tasks', '',
    '- [x] A1. lettered foundations task',
    '- [ ] B2. lettered engine task',
    '- [ ] 3. unlettered task',
    '',
  ].join('\n'));
  // R11 Critical 4(2): a `parent-plan:` reference that never resolves — the
  // child must render STANDALONE + `dangling_parent: true`, never silently
  // dropped, never a fake master materialized for it.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'dangling-child-fixture.md'), [
    '# Plan: Dangling Child', '', 'Status: ACTIVE', 'parent-plan: no-such-master-anywhere', '',
    '## Tasks', '', '- [ ] 1. a task whose declared parent never resolves', '',
  ].join('\n'));
  // R11 Critical 4(1): PINNING — an archived master with NO recency evidence
  // (would normally be excluded entirely by the aging gate — see
  // scanPlanDir's header note) must still render when a NON-TERMINAL child
  // plan references it.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'archive', 'pinned-master-fixture.md'), [
    '# Plan: Pinned Master', '', 'Status: COMPLETED', '', '## Tasks', '',
    '- [x] 1. old master task, long since archived, zero recency evidence', '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'pinned-child-fixture.md'), [
    '# Plan: Pinned Child', '', 'Status: ACTIVE', 'parent-plan: pinned-master-fixture', '',
    '## Tasks', '', '- [ ] 1. still active work under an archived-and-aged-out master', '',
  ].join('\n'));
  // R11 Critical 2: a MULTI-task letter run must render the mechanical span
  // "Tasks <first>-<last>", never a bare letter, never a prose gloss.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'batch-run-fixture.md'), [
    '# Plan: Batch Run', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [x] A1 first foundations task',
    '- [ ] A2 second foundations task',
    '- [ ] A3 third foundations task',
    '- [ ] B1 first engine task',
    '- [ ] B2 second engine task',
    '',
  ].join('\n'));
  // R11 Critical 1/2: `###` sub-headings inside `## Tasks` are the batch
  // label source, VERBATIM, taking priority (these tasks are plain
  // numeric — the heading is the ONLY possible batch signal here).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'heading-batch-fixture.md'), [
    '# Plan: Heading Batch', '', 'Status: ACTIVE', '', '## Tasks', '',
    '### Phase B — Foundations', '',
    '- [x] 1. first task under the heading',
    '- [ ] 2. second task under the heading',
    '### Phase C — Engine', '',
    '- [ ] 3. a task under a different heading',
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
  // stale-dispatch-plan (false-eternal-running fix, 2026-07-30 — the
  // OPERATOR-REPORTED real defect: three roadmap tasks rendered "running"
  // for hours because the DISPATCHING session that once touched them was
  // still alive, even though none of them had been re-dispatched in a
  // while). ONE task, task_started attached to sess-op-1 — the SAME
  // fixture session rich-plan/1 uses, whose heartbeat file is written
  // fresh at suite-start (genuinely live the whole run) — but its
  // task_started event (below) is deliberately STALE (2h ago, well past
  // the 60min default idle window), unlike rich-plan/1's recent one. This
  // is the exact real-world shape: alive dispatcher, abandoned task.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'stale-dispatch-plan.md'), [
    '# Plan: Stale Dispatch', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. a task dispatched once, hours ago, never revisited',
    '',
  ].join('\n'));
  // UNBINDABLE-DISPATCH FIXTURES (2026-08-02). Two DEDICATED plans, neither
  // of which has any bound running task — so every assertion about the new
  // deriveUnbindableDispatchLeaves path is proved by that path alone. (The
  // first draft hung this off rich-plan, which already had a bound running
  // task, so `running_now === true` there was satisfied by the pre-existing
  // path and proved nothing — harness-reviewer Major 3.)
  //   unbindable-plan       : dispatch ts RECENT  -> leaf 'running'
  //   unbindable-stale-plan : dispatch ts 2h old  -> leaf 'stalled', AND its
  //                           session must STILL be counted by the
  //                           unattributed node (the Critical: binding a
  //                           non-running leaf hid live sessions from the one
  //                           surface that says "N running").
  // Both sessions' heartbeats are written fresh at suite start, so the ONLY
  // variable between them is the dispatch timestamp.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'unbindable-plan.md'), [
    '# Plan: Unbindable Dispatch', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. a task nobody dispatched by its real id',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'unbindable-stale-plan.md'), [
    '# Plan: Unbindable Stale Dispatch', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. a task whose only dispatch named a bogus id, hours ago',
    '',
  ].join('\n'));
  // corrupt-ts-plan (MALFORMED-IS-NOT-ABSENT fix, 2026-07-30): ONE task
  // whose task_started event is PRESENT but carries an unparseable `ts`
  // (a truncated/corrupt write). Attached to sess-op-1, the same
  // genuinely-live heartbeat session — so before the fix the unparseable
  // timestamp collapsed to null, the idle gate silently switched OFF, and
  // the task rendered a green in-progress from evidence nobody could read.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'corrupt-ts-plan.md'), [
    '# Plan: Corrupt Timestamp', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. a task whose task_started timestamp cannot be parsed',
    '',
  ].join('\n'));
  // waiting-plan (ROADMAP-WAITING-ON-YOU-SIGNAL-01, round 14): ONE task,
  // started (task_started event below, unlinked lane) by a session with NO
  // heartbeat file at all -- reaches deriveItemStatus's stalled branch via
  // activity:'no-heartbeat', the real precondition buildWaitingOnYouMap's
  // stalledSignals.waitingOnYouId needs to actually win the precedence over
  // the 'crashed' fallback (see derive-lib.js's deriveStalledReason).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'waiting-plan.md'), [
    '# Plan: Waiting', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. a task genuinely stalled, waiting on an operator decision',
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

  // ---- R9-1 fixture: an H1 that reads nothing like the slug (proves the
  // renderer uses the H1, not the slug, when no operator title/linked ask
  // title is present) --------------------------------------------------
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'h1-title-fixture.md'), [
    '<!-- scaffold-created: 2026-07-23T00:00:00Z by start-plan.sh slug=h1-title-fixture -->',
    '# Plan: A Completely Different Human Title', '', 'Status: ACTIVE', '', '## Tasks', '',
    '- [ ] 1. something',
    '',
  ].join('\n'));

  // ---- R9-4 fixtures: plan-level provenance classification ---------------
  // Machine-slug-heuristic positives (no linked ask at all — the exact
  // shape the pre-fix classifier was inert on).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'harness-chore-fixture.md'), [
    '# Plan: Harness Chore Fixture', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'nl-finding-999-chore-fixture.md'), [
    '# Plan: NL Finding Chore Fixture', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'agent-watchdog-fixture.md'), [
    '# Plan: Agent Watchdog Fixture', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  // Negative case: "sweeper" must NOT false-positive the "sweep" word
  // heuristic (hyphen-bounded on purpose).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'worktree-sweeper-fixture.md'), [
    '# Plan: Worktree Sweeper Fixture', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  // Explicit header OVERRIDES the heuristic in BOTH directions.
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'harness-explicit-operator-override.md'), [
    '# Plan: Harness Explicit Operator Override', '', 'Status: ACTIVE', 'provenance: operator', '',
    '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'not-chore-shaped-explicit-machine.md'), [
    '# Plan: Not Chore Shaped Explicit Machine', '', 'Status: ACTIVE', 'provenance: machine', '',
    '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));
  // A machine-SHAPED slug that IS linked to a real ask must stay 'operator'
  // (A9: provenance = PROVENANCE, never subject matter — a linked ask is an
  // operator REQUEST regardless of the plan's own slug shape).
  fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'harness-linked-to-operator-ask.md'), [
    '# Plan: Harness Linked To Operator Ask', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. x', '',
  ].join('\n'));

  // ---- R9-8 fixture: a SECOND repo with its own docs/plans/, plus a THIRD
  // configured repo with NO docs/plans/ at all (honest absence) ------------
  const otherRepoDir = path.join(tmp, 'other-repo');
  fs.mkdirSync(path.join(otherRepoDir, 'docs', 'plans'), { recursive: true });
  fs.writeFileSync(path.join(otherRepoDir, 'docs', 'plans', 'other-repo-plan.md'), [
    '# Plan: Other Repo Effort', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. do the other-repo thing', '',
  ].join('\n'));
  const emptyRepoDir = path.join(tmp, 'empty-repo-no-plans');
  fs.mkdirSync(emptyRepoDir, { recursive: true });
  // R17 (2026-07-30, decision A — multi-project GROUPING) fixture: a
  // FOURTH configured repo using the LEGACY flat-string config form (no
  // `group` declared) — its plans must land in the honest '(ungrouped)'
  // catch-all, never a silently-guessed default group.
  const flatRepoDir = path.join(tmp, 'flat-repo');
  fs.mkdirSync(path.join(flatRepoDir, 'docs', 'plans'), { recursive: true });
  fs.writeFileSync(path.join(flatRepoDir, 'docs', 'plans', 'flat-project-plan.md'), [
    '# Plan: Flat Project Effort', '', 'Status: ACTIVE', '', '## Tasks', '', '- [ ] 1. do the flat-project thing', '',
  ].join('\n'));
  // The projects-config env override starts pointed at a NONEXISTENT file —
  // configuredRepoRoots() must degrade to [] honestly, so the zero-config
  // default (S1-era GETs below) stays single-repo (R9-8's own binding rule).
  process.env.ROADMAP_PROJECTS_CONFIG = path.join(tmp, 'no-such-projects-config.json');

  // ---- R9-7b fixture: a heartbeat for a session attached to NO task
  // anywhere (a CRASHED one, written up front — proves the "crashed
  // sessions never count as unattributed-and-RUNNING" exclusion; a FRESH
  // one is added later, mid-test, to prove the null -> non-null transition
  // honestly rather than starting from a state that already has one). -----
  fs.writeFileSync(path.join(heartbeatDir, 'sess-unbound-crashed.json'), JSON.stringify({
    schema: 1, session_id: 'sess-unbound-crashed', pid: 2, cwd: repoDir, repo_root: repoDir,
    worktree_root: repoDir, branch: 'fixture', model: 'fixture',
    last_activity_ts: new Date(Date.now() - 30 * 86400000).toISOString(), // 30 days — well past crashed
    last_event: 'fixture', marker_state: 'none',
  }));

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
    // ask-harness-linked: a REAL operator ask linked to a machine-SHAPED
    // slug (R9-4) — proves the linked-ask precedence beats the slug
    // heuristic (A9: never hide operator-requested harness work).
    { ask_id: 'ask-harness-linked', record_type: 'created', ts: '2026-07-14T10:00:00Z', summary: 'Please fix the harness gate message', repo: repoDir, project: 'fixture-proj', origin_session: 'sess-op-1', status: 'active', emitter: 'ask-registry' },
    { ask_id: 'ask-harness-linked', record_type: 'plan_linked', ts: '2026-07-14T10:05:00Z', plan_slug: 'harness-linked-to-operator-ask' },
  ];
  fs.writeFileSync(path.join(stateDir, 'ask-registry.jsonl'),
    reg.map((r) => JSON.stringify(r)).join('\n') + '\n');

  // ---- fixture progress events ------------------------------------------
  fs.writeFileSync(path.join(progressDir, 'ask-alpha.jsonl'), [
    JSON.stringify({ type: 'task_started', ts: RECENT_TASK_STARTED_TS, plan_slug: 'demo-plan', task_id: '2', session_id: 'sess-op-1' }),
    JSON.stringify({ type: 'task_done', ts: '2026-07-14T18:00:00Z', plan_slug: 'demo-plan', task_id: '1', session_id: 'sess-op-1', evidence_link: '' }),
  ].join('\n') + '\n');
  // rich-plan's task 1 is in-progress with TWO attached sessions — sess-op-1
  // (the LIVE fixture heartbeat, fresh last_activity_ts) and sess-ghost (a
  // session with NO heartbeat file at all) — the 7B-i fixture, covering
  // both the "running" and the "unknown, no heartbeat evidence" leaf.
  fs.writeFileSync(path.join(progressDir, 'ask-rich.jsonl'), [
    JSON.stringify({ type: 'task_started', ts: RECENT_TASK_STARTED_TS, plan_slug: 'rich-plan', task_id: '1', session_id: 'sess-op-1' }),
    JSON.stringify({ type: 'task_started', ts: RECENT_TASK_STARTED_TS_2, plan_slug: 'rich-plan', task_id: '1', session_id: 'sess-ghost' }),
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
    // waiting-plan/1: started by a session with NO heartbeat file anywhere
    // -- sessionActivityForIds returns 'no-heartbeat' (never 'crashed' via
    // an old timestamp; genuinely absent), reaching the stalled branch.
    JSON.stringify({ type: 'task_started', ts: '2026-07-10T09:00:00Z', plan_slug: 'waiting-plan', task_id: '1', session_id: 'sess-waiting-ghost' }),
    // stale-dispatch-plan/1 (false-eternal-running fix): task_started
    // attached to sess-op-1 — the SAME live-heartbeat session rich-plan/1
    // uses — but 2h in the past, well past the 60min default idle window.
    // The "alive dispatcher, abandoned task" shape the real deployed
    // roadmap showed for hours (operator report, 2026-07-30).
    JSON.stringify({ type: 'task_started', ts: STALE_TASK_STARTED_TS, plan_slug: 'stale-dispatch-plan', task_id: '1', session_id: 'sess-op-1' }),
    // corrupt-ts-plan/1 (MALFORMED-IS-NOT-ABSENT fix): the event EXISTS and
    // names a real live session, but its ts is unparseable — Date.parse ->
    // NaN. The pre-fix code mapped that NaN to null (== "no evidence"),
    // which disabled the idle gate and rendered green. It must render
    // 'unknown' instead: we cannot read this task's own start evidence.
    JSON.stringify({ type: 'task_started', ts: 'not-a-timestamp', plan_slug: 'corrupt-ts-plan', task_id: '1', session_id: 'sess-op-1' }),
    // UNBINDABLE ATTRIBUTED DISPATCH (2026-08-01) — the real shape observed
    // on this machine: an NL-ATTRIBUTION header named a REAL plan but a
    // task= id that is not a task id in it ("cockpit-running-representation"
    // against a plan whose ids are T1..T14; plan-parse's TASK_ID_TOKEN_RE
    // requires digits, so a pure slug can never be one). Pre-fix this event
    // was dropped in BOTH directions: no task matched it, and the session
    // was excluded from the unattributed node too — a genuinely running,
    // genuinely attributed agent, invisible everywhere.
    // ts is RECENT and the session is the LIVE-heartbeat sess-op-1, so the
    // running case is the one under test (the stale case is covered by
    // rich-plan/stale-dispatch-plan above and asserted below).
    JSON.stringify({ type: 'task_started', ts: RECENT_TASK_STARTED_TS, plan_slug: 'unbindable-plan', task_id: 'a-slug-not-a-task-id', session_id: 'sess-unbindable' }),
    // The NEGATIVE case, and the Critical's regression guard: same shape,
    // same fresh heartbeat, dispatch ts 2h old (past taskStartedIdleMs).
    JSON.stringify({ type: 'task_started', ts: STALE_TASK_STARTED_TS, plan_slug: 'unbindable-stale-plan', task_id: 'another-slug-not-a-task-id', session_id: 'sess-unbindable-stale' }),
  ].join('\n') + '\n');
  // Both sessions' heartbeats are FRESH, so the only thing that can stop
  // either rendering "running" is the dispatch timestamp / the task-id join.
  fs.writeFileSync(path.join(heartbeatDir, 'sess-unbindable.json'), JSON.stringify({
    schema: 1, session_id: 'sess-unbindable', pid: process.pid, cwd: repoDir, repo_root: repoDir,
    worktree_root: repoDir, branch: 'fixture-unbindable', model: 'fixture',
    last_activity_ts: new Date().toISOString(), last_event: 'fixture', marker_state: 'none',
  }));
  // sess-unbindable-stale's heartbeat is deliberately NOT written here. It is
  // written LATE (in the R9-7b section) precisely because a fresh heartbeat
  // for it makes it a genuinely live, genuinely unattributed session — which
  // is the whole point of the Critical's regression guard, but would also
  // change the population every pre-existing R9-7b assertion pins. Writing it
  // after those keeps their coverage exactly as strong as it was.

  // ROADMAP-WAITING-ON-YOU-SIGNAL-01 (round 14): the needs-you ledger
  // sandbox buildWaitingOnYouMap's lazy require('./inbox-routes.js') reads.
  // A real, answerable decision item explicitly naming docs/plans/waiting-
  // plan.md + "task 1" -- the ONLY conservative match shape this producer
  // accepts (plan-parse.js's extractPlanTaskReferences).
  const needsYouStateDir = path.join(tmp, 'needs-you-state');
  fs.mkdirSync(needsYouStateDir, { recursive: true });
  process.env.NEEDS_YOU_STATE_DIR = needsYouStateDir;
  fs.writeFileSync(path.join(needsYouStateDir, 'ledger.json'), JSON.stringify({
    schema_version: 1,
    items: [{
      id: 'NY-waiting-1', section: 'decision', state: 'open', created_at: '2026-07-10T10:00:00Z',
      lint_warnings: [],
      text: '### Which approach for the stuck task?\n' +
        'docs/plans/waiting-plan.md -- task 1 is blocked on this call.\n' +
        '| Option | What happens |\n|---|---|\n| A | goes one way |\n| B | goes the other |\n' +
        'My pick: A.\nReply with: "a" or "b".',
    }],
  }));

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
    // ---- scan_provenance (2026-08-04 stale-checkout fix, part b — the
    // non-silence class fix): present on EVERY payload, never conditional.
    // This fixture sets ROADMAP_PLAN_SCAN_ROOT explicitly, so resolved_via
    // must say exactly that (an override, not a mainRepoRoot() derivation)
    // — and repoDir is a plain tmp dir, not a git repo, so head_sha/
    // behind_origin_master are honestly undeterminable, never fabricated.
    const prov = r1.json && r1.json.scan_provenance;
    ok('S1f scan_provenance is present with the pinned shape (root/resolved_via/head_sha/behind_origin_master/checked_at)',
      !!prov && typeof prov.root === 'string' && typeof prov.resolved_via === 'string' &&
      typeof prov.head_sha === 'string' && typeof prov.checked_at === 'string' &&
      (prov.behind_origin_master === null || typeof prov.behind_origin_master === 'number'),
      JSON.stringify(prov));
    ok('S1g scan_provenance.root is the SANDBOXED fixture repo, never the real checkout (ROADMAP_PLAN_SCAN_ROOT honored)',
      prov && path.resolve(prov.root) === path.resolve(repoDir), JSON.stringify(prov));
    ok('S1h scan_provenance.resolved_via is "env-override" — ROADMAP_PLAN_SCAN_ROOT was set, so this is NOT deriveLib.mainRepoRoot()\'s own worktree/self resolution',
      prov && prov.resolved_via === 'env-override', JSON.stringify(prov));
    ok('S1i scan_provenance honestly reports head_sha:\'\'/behind_origin_master:null for this non-git fixture dir — never a fabricated sha or count',
      prov && prov.head_sha === '' && prov.behind_origin_master === null, JSON.stringify(prov));
    ok('S1e exactly 26 TOP-LEVEL plans (17 pre-R11-fixture-expansion + dangling-child + pinned-master [pinned in] + batch-run + heading-batch + waiting-plan [ROADMAP-WAITING-ON-YOU-SIGNAL-01 round-14 fixture] + stale-dispatch-plan [false-eternal-running fix, 2026-07-30] + corrupt-ts-plan [malformed-is-not-absent fix, 2026-07-30] + unbindable-plan and unbindable-stale-plan [unbindable-attributed-dispatch fix, 2026-08-02]; child-a-fixture and pinned-child-fixture are NESTED, not top-level roots — Critical 3/4) — no more, no less; ancient-ghost-plan is correctly EXCLUDED',
      items.length === 26, topIds.join(','));
    ok('R11 child-a-fixture no longer appears in the TOP-LEVEL list (it renders once, nested under its master)',
      topIds.indexOf('child-a-fixture') === -1, topIds.join(','));

    // ---- R11 (round 11): the mechanical master/child hierarchy ----
    const masterFixture = findItem(items, 'master-fixture');
    const childA = findItem(items, 'child-a-fixture');
    ok('R11-A1 a plan with a `parent-plan:` header carries parent_plan=<master slug>; plans without it carry \'\' (standalone — never inferred)',
      childA && childA.parent_plan === 'master-fixture' &&
      masterFixture && masterFixture.parent_plan === '' &&
      findItem(items, 'demo-plan').parent_plan === '',
      childA && childA.parent_plan);
    ok('R11 Critical 3/4: master-fixture resolves child-a-fixture into `child_plans` (the RENDERED grouping, not merely a supported field) and NEVER masters an unrelated plan',
      !!masterFixture && Array.isArray(masterFixture.child_plans) && masterFixture.child_plans.length === 1 &&
      masterFixture.child_plans[0].id === 'child-a-fixture' &&
      childA.resolved_parent === 'master-fixture' && childA.dangling_parent === false,
      masterFixture && JSON.stringify(masterFixture.child_plans && masterFixture.child_plans.map((c) => c.id)));
    ok('R11 Critical 5: master_summary carries TWO SEPARATE labeled fractions (plans done/total, own_tasks done/total) — never one blended number',
      !!masterFixture.master_summary &&
      masterFixture.master_summary.plans.total === 1 && masterFixture.master_summary.plans.done === 0 &&
      masterFixture.master_summary.own_tasks.total === 1 && masterFixture.master_summary.own_tasks.done === 0,
      JSON.stringify(masterFixture.master_summary));
    ok('R11 a plan with NO resolved children carries master_summary: null (the `[master]` tag is driven ONLY by resolved children)',
      findItem(items, 'demo-plan').master_summary === null);

    // ---- R11 Critical 1/2: batch derivation — mechanical span, NEVER a bare letter ----
    ok('R11 lettered task ids PARSE (the old grammar silently dropped them); a length-1 letter run renders the mechanical "Task <id>" span, never a bare letter or a prose gloss',
      !!findItem(items, 'child-a-fixture/A1') && findItem(items, 'child-a-fixture/A1').batch === 'Task A1' &&
      findItem(items, 'child-a-fixture/A1').status && findItem(items, 'child-a-fixture/A1').status.value === 'complete' &&
      !!findItem(items, 'child-a-fixture/B2') && findItem(items, 'child-a-fixture/B2').batch === 'Task B2' &&
      !!findItem(items, 'child-a-fixture/3') && findItem(items, 'child-a-fixture/3').batch === '');
    ok('R11-A3 the lettered plan\'s PROGRESS counts all three tasks (1/3 done) — the dropped-task data hole under "progress seems random" is closed',
      childA && childA.progress && childA.progress.done === 1 && childA.progress.total === 3,
      childA && JSON.stringify(childA.progress));

    // ---- R11 Critical 2: multi-task letter run -> mechanical SPAN label ----
    ok('R11 Critical 2: a multi-task letter run renders the mechanical span "Tasks <first>-<last>", never a bare letter, never a prose gloss ("foundations"/"engine")',
      findItem(items, 'batch-run-fixture/A1').batch === 'Tasks A1–A3' &&
      findItem(items, 'batch-run-fixture/A2').batch === 'Tasks A1–A3' &&
      findItem(items, 'batch-run-fixture/A3').batch === 'Tasks A1–A3' &&
      findItem(items, 'batch-run-fixture/B1').batch === 'Tasks B1–B2' &&
      findItem(items, 'batch-run-fixture/B2').batch === 'Tasks B1–B2',
      JSON.stringify(['A1', 'A2', 'A3', 'B1', 'B2'].map((id) => findItem(items, 'batch-run-fixture/' + id) && findItem(items, 'batch-run-fixture/' + id).batch)));

    // ---- R11 Critical 1/2: `###` sub-heading batch source, VERBATIM, takes priority ----
    ok('R11 Critical 1/2: `###` sub-headings inside `## Tasks` supply the batch label VERBATIM (plain numeric ids here — the heading is the ONLY possible source)',
      findItem(items, 'heading-batch-fixture/1').batch === 'Phase B — Foundations' &&
      findItem(items, 'heading-batch-fixture/2').batch === 'Phase B — Foundations' &&
      findItem(items, 'heading-batch-fixture/3').batch === 'Phase C — Engine',
      JSON.stringify(['1', '2', '3'].map((id) => findItem(items, 'heading-batch-fixture/' + id) && findItem(items, 'heading-batch-fixture/' + id).batch)));

    // ---- R11 Critical 4(2): dangling parent-plan reference ----
    const danglingChild = findItem(items, 'dangling-child-fixture');
    ok('R11 Critical 4(2): a dangling parent-plan reference renders the child STANDALONE + dangling_parent:true (badge "parent \'<slug>\' not found" is client-rendered from these two fields) — never silently dropped, never a fake master',
      !!danglingChild && danglingChild.dangling_parent === true &&
      danglingChild.parent_plan === 'no-such-master-anywhere' && danglingChild.resolved_parent === '' &&
      topIds.indexOf('dangling-child-fixture') !== -1,
      danglingChild && JSON.stringify({ dp: danglingChild.dangling_parent, pp: danglingChild.parent_plan, rp: danglingChild.resolved_parent }));

    // ---- R11 Critical 4(1): PINNING an aged-out master with a live child ----
    const pinnedMaster = findItem(items, 'pinned-master-fixture');
    ok('R11 Critical 4(1): a master normally EXCLUDED by archive-aging (zero recency evidence) is PINNED on the tree because a non-terminal child still references it',
      !!pinnedMaster && pinnedMaster.pinned === true && topIds.indexOf('pinned-master-fixture') !== -1,
      JSON.stringify(pinnedMaster && { pinned: pinnedMaster.pinned, reason: pinnedMaster.pinned_reason }));
    ok('R11 the pinned master correctly resolves its child + aggregates the two labeled counts (Critical 5)',
      !!pinnedMaster && Array.isArray(pinnedMaster.child_plans) && pinnedMaster.child_plans.length === 1 &&
      pinnedMaster.child_plans[0].id === 'pinned-child-fixture' && !!pinnedMaster.master_summary &&
      topIds.indexOf('pinned-child-fixture') === -1,
      pinnedMaster && JSON.stringify(pinnedMaster.child_plans && pinnedMaster.child_plans.map((c) => c.id)));

    // ---- R11 Critical 4(3)/(4) UNIT tests: applyMasterHierarchy in isolation
    // (same-project scoping + cycle-breaking) — no filesystem/HTTP involved,
    // deterministic regardless of file-mtime ordering. ----
    (function () {
      function fakeNode(id, project, parentPlan) {
        return { id: id, project: project, parent_plan: parentPlan || '', status: { value: 'in-progress' }, progress: null, roll_up: {} };
      }
      const crossProjItems = [fakeNode('master-x', 'projX', ''), fakeNode('child-wrong-project', 'projY', 'master-x')];
      const crossHier = roadmapRoutes.applyMasterHierarchy(crossProjItems);
      const childWrong = crossHier.topLevel.find((x) => x.id === 'child-wrong-project');
      ok('R11 Critical 4(3) unit: a parent_plan slug match in a DIFFERENT project is treated as unresolved (dangling) — cross-repo resolution is out of scope this round',
        !!childWrong && childWrong.dangling_parent === true && childWrong.resolved_parent === '',
        JSON.stringify(childWrong));

      const cycleItems = [fakeNode('cyc-a', 'projZ', 'cyc-b'), fakeNode('cyc-b', 'projZ', 'cyc-a')];
      const cycleHier = roadmapRoutes.applyMasterHierarchy(cycleItems);
      const cycA = cycleItems.find((x) => x.id === 'cyc-a');
      const cycB = cycleItems.find((x) => x.id === 'cyc-b');
      ok('R11 Critical 4(4) unit: an A<->B parent-plan cycle flags BOTH plans, each naming the other',
        cycA.cycle_flag === true && cycB.cycle_flag === true &&
        cycA.cycle_with === 'cyc-b' && cycB.cycle_with === 'cyc-a',
        JSON.stringify({ a: { f: cycA.cycle_flag, w: cycA.cycle_with }, b: { f: cycB.cycle_flag, w: cycB.cycle_with } }));
      ok('R11 Critical 4(4) unit: the cycle is broken at exactly ONE edge — exactly one of the two is a top-level root, the other nests under it (never both roots, never both vanish)',
        cycleHier.topLevel.some((x) => x.id === 'cyc-a') !== cycleHier.topLevel.some((x) => x.id === 'cyc-b'),
        JSON.stringify(cycleHier.topLevel.map((x) => x.id)));
    })();

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

    // ---- Round 15 (operator, repeated): "if I expand a plan I can see the
    // tasks in progress, but the plan itself doesn't show anything is in
    // progress" — rich-plan/1 genuinely carries a live_sessions entry
    // (S18 above), so the OWNING PLAN (rich-plan) must roll that up as a
    // counted "running" attention class (C1's roll-up law applied to the
    // running state, real execution against the SAME fixture S18 uses —
    // not a synthetic one). ----
    const richPlan = findItem(items, 'rich-plan');
    ok('S20 the running roll-up propagates from a live task to its OWNING PLAN (rich-plan.roll_up.running.count >= 1, exemplar names the actual running task)',
      richPlan && richPlan.roll_up && richPlan.roll_up.running && richPlan.roll_up.running.count >= 1 &&
      richPlan.roll_up.running.exemplar === 'rich-plan/1',
      richPlan && JSON.stringify(richPlan.roll_up));
    // redesign-plan is PARTIALLY DONE (task 1 checked, task 2 never
    // started — status.value='in-progress' purely from done>0) but has NO
    // live task anywhere: exactly the distinction this whole fix protects
    // — merely-partial must never be confused with actively-running.
    // ---- S20c-e: false-eternal-running fix (2026-07-30, operator-reported
    // real defect) — stale-dispatch-plan/1 is attached to sess-op-1, the
    // SAME live-heartbeat session rich-plan/1 uses (S18/S20 above prove
    // that session genuinely renders "running" when its task_started is
    // recent). The ONLY difference here is task_started age (2h vs
    // ~10min) — isolating that this is what the fix keys on, not merely
    // "sess-op-1 is somehow different." ----
    const staleTask = findItem(items, 'stale-dispatch-plan/1');
    ok('S20c a task whose ONLY attached session has a LIVE heartbeat, but whose own task_started is 2h stale (past the 60min default idle window), renders status.value=stalled — NOT in-progress (the exact operator-reported defect: dispatching session alive, task itself abandoned)',
      staleTask && staleTask.status && staleTask.status.value === 'stalled' && staleTask.status.reason_class === 'idle-dispatch',
      staleTask && JSON.stringify(staleTask.status));
    // S20c-reason (2026-07-30 reason-code split): the badge must not claim
    // a crash. sess-op-1's heartbeat is written FRESH at suite start (this
    // fixture's own premise, shared with S18/S20), so "stalled — crashed"
    // was a demonstrably false statement that pointed the operator at a
    // dead-session investigation which does not exist. Asserting the
    // negative explicitly: the previous code produced exactly 'crashed'
    // here, so this line is what fails if the fold ever returns.
    ok('S20c-reason the stale task\'s reason_class is "idle-dispatch" and NEVER "crashed" — its session heartbeat is fresh by construction, so a crash claim would be false (constitution §1)',
      staleTask && staleTask.status.reason_class !== 'crashed' &&
      staleTask.status.reason_class === 'idle-dispatch' &&
      /still alive/.test(staleTask.status.label),
      staleTask && JSON.stringify(staleTask.status));
    ok('S20d that same task\'s live_sessions leaf for sess-op-1 ALSO renders stalled (not "running") despite the session\'s heartbeat genuinely being live — the leaf and the task-level badge must agree',
      staleTask && Array.isArray(staleTask.live_sessions) && staleTask.live_sessions.length === 1 &&
      staleTask.live_sessions[0].status.value === 'stalled',
      staleTask && JSON.stringify(staleTask.live_sessions));
    const staleDispatchPlan = findItem(items, 'stale-dispatch-plan');
    ok('S20e the OWNING PLAN carries NO running roll-up entry for the stale-dispatched task (this is the actual rollup-gate fix: a merely non-empty live_sessions array no longer counts as "running" by itself — line 1314\'s original bug)',
      staleDispatchPlan && (!staleDispatchPlan.roll_up || !staleDispatchPlan.roll_up.running),
      staleDispatchPlan && JSON.stringify(staleDispatchPlan.roll_up));
    // S20e-reason: the roll-up badge the operator actually SEES on the plan
    // row must carry the honest class too. The leaf, the task badge and the
    // plan roll-up previously DISAGREED — the leaf said "still alive", the
    // task badge and this roll-up both said "crashed".
    ok('S20e-reason the owning plan rolls up an "idle-dispatch" attention badge, NOT a "crashed" one — the plan row, the task badge and the session leaf now tell the operator the same story',
      staleDispatchPlan && staleDispatchPlan.roll_up &&
      staleDispatchPlan.roll_up['idle-dispatch'] && staleDispatchPlan.roll_up['idle-dispatch'].count === 1 &&
      !staleDispatchPlan.roll_up.crashed,
      staleDispatchPlan && JSON.stringify(staleDispatchPlan.roll_up));

    // ---- S20g: MALFORMED IS NOT ABSENT, proven end-to-end through the
    // real route (not just the derive unit). corrupt-ts-plan/1's
    // task_started exists and names the LIVE sess-op-1, but its ts cannot
    // be parsed — pre-fix this rendered a green in-progress.
    const corruptTask = findItem(items, 'corrupt-ts-plan/1');
    ok('S20g a task whose task_started event is PRESENT but carries an unparseable ts renders status.value=unknown through the real /api/roadmap route — never the pre-fix green in-progress derived from evidence that could not be read',
      corruptTask && corruptTask.status && corruptTask.status.value === 'unknown' &&
      corruptTask.status.value !== 'in-progress' &&
      /unparseable/.test(corruptTask.status.label),
      corruptTask && JSON.stringify(corruptTask.status));
    ok('S20h that same task contributes an "unknown" attention badge to its owning plan (an unreadable input surfaces to the operator instead of vanishing into a confident green)',
      (function () {
        const p = findItem(items, 'corrupt-ts-plan');
        return p && p.roll_up && p.roll_up.unknown && p.roll_up.unknown.count === 1 && !p.roll_up.running;
      })(),
      JSON.stringify((findItem(items, 'corrupt-ts-plan') || {}).roll_up));

    ok('S20b a merely-partial plan (redesign-plan: 1/2 done, task 2 never started, no live session anywhere) carries NO running roll-up entry — status.value can be "in-progress" from done>0 alone, which must NOT be confused with a REAL live session',
      redesign && redesign.status && redesign.status.value === 'in-progress' &&
      redesign.roll_up && !redesign.roll_up.running,
      redesign && JSON.stringify({ status: redesign.status, roll_up: redesign.roll_up }));

    // ---- S21: running_now — the API's own answer to "is anyone working on
    // this RIGHT NOW", added 2026-08-01 (operator, repeated: the coloured
    // plan titles "are supposed to represent items that are currently being
    // worked on ... I actually do not see any items in the cockpit that
    // state that they are actively running"). The whole point is that this
    // field DISAGREES with status.value: every fixture below is derived
    // 'in-progress', and they split on live evidence alone. Asserted on the
    // real HTTP payload, so a client reading `running_now` gets exactly
    // what these lines pin. ----
    ok('S21 running_now is TRUE for a task with a genuinely running live session (rich-plan/1 — the SAME fixture S18 proves renders a running leaf)',
      richTask && richTask.running_now === true,
      richTask && JSON.stringify({ status: richTask.status.value, running_now: richTask.running_now }));
    ok('S21b running_now propagates to the OWNING PLAN (rich-plan) — the operator scans plan titles, so an ancestor of live work must answer yes too',
      richPlan && richPlan.running_now === true,
      richPlan && JSON.stringify({ status: richPlan.status.value, running_now: richPlan.running_now }));
    ok('S21c THE DISTINCTION: redesign-plan is derived status.value "in-progress" (1/2 done) with NO live session anywhere, and running_now is FALSE — derived-from-artifacts progress is not a liveness claim, which is the entire defect this field fixes',
      redesign && redesign.status.value === 'in-progress' && redesign.running_now === false,
      redesign && JSON.stringify({ status: redesign.status.value, running_now: redesign.running_now }));
    ok('S21d HONEST ABSENCE: the stale-dispatch task (live_sessions NON-EMPTY, but its only member is stalled — a live dispatching session that abandoned this task) is running_now FALSE, and so is its owning plan. A non-empty array is never a running claim',
      staleTask && staleTask.running_now === false &&
      staleDispatchPlan && staleDispatchPlan.running_now === false,
      JSON.stringify({ task: staleTask && staleTask.running_now, plan: staleDispatchPlan && staleDispatchPlan.running_now }));
    ok('S21e a DONE task is never running_now (finished work has no live claim), and neither is a not-started one',
      demoT1 && demoT1.running_now === false,
      demoT1 && JSON.stringify({ status: demoT1.status.value, running_now: demoT1.running_now }));
    ok('S21f EVERY node in the payload carries the field — a client can read it uniformly and never has to fall back to guessing from live_sessions.length (the predicate that caused the original false-green)',
      (function () {
        let missing = [];
        const walk = (n) => {
          if (typeof n.running_now !== 'boolean') missing.push(n.id);
          (n.children || []).forEach(walk);
          (n.child_plans || []).forEach(walk);
        };
        items.forEach(walk);
        return missing.length === 0;
      })());
    // ---- S22: the UNBINDABLE ATTRIBUTED DISPATCH (2026-08-01). Observed
    // live: a dispatch header named plan=accountable-estate-program-2026-07
    // task=cockpit-running-representation; the plan resolved, the task id
    // did not (real ids T1..T14). Pre-fix the event vanished from BOTH
    // surfaces — no task claimed it, and the unattributed node excludes it
    // too. R9-7 forbids exactly that ("running work is NEVER invisible").
    // Every dereference below is guarded to a default rather than chained off
    // a bare truthiness check (harness-reviewer Major 2): under a mutant that
    // makes deriveUnbindableDispatchLeaves return [], the old S22b/S22c threw
    // `TypeError: reading 'title'` and the suite died with NO summary, taking
    // S22c-f, S21g, every R9-7b-* and R9-8 down silently. A mutant must make
    // ONE assertion fail loudly, never erase the run.
    const unbPlan = findItem(items, 'unbindable-plan');
    const unbLeaf = (unbPlan && (unbPlan.live_sessions || [])[0]) || {};
    ok('S22 an attributed dispatch whose task= id matches NO task in the named plan surfaces on the PLAN row as a live session — not silently dropped (the invisible-running defect). Asserted on a plan with NO bound running task, so this path alone can satisfy it',
      unbPlan && Array.isArray(unbPlan.live_sessions) && unbPlan.live_sessions.length === 1,
      unbPlan && JSON.stringify(unbPlan.live_sessions));
    ok('S22b the leaf names the id the dispatch ACTUALLY sent, verbatim and quoted, and says plainly that it is not a task id in this plan — the operator can see what was mis-sent without reading a log',
      /dispatched for task "a-slug-not-a-task-id", which is not a task id in this plan/.test(unbLeaf.title || ''),
      JSON.stringify(unbLeaf.title || null));
    ok('S22c it is a REAL running claim, gated exactly like a task-bound one (fresh heartbeat + task_started inside the idle window), so the plan is running_now and renders green — and unbindable-plan has no bound running task, so nothing else could have set it',
      (unbLeaf.status || {}).value === 'running' && unbPlan && unbPlan.running_now === true,
      JSON.stringify({ leaf: unbLeaf.status || null, running_now: unbPlan && unbPlan.running_now }));
    ok('S22d NEVER promoted to a task row: no task node anywhere claims either unbindable session — the fix surfaces the dispatch at the level it could honestly be attributed to (the plan), and does not guess which task was meant',
      (function () {
        let claimed = [];
        const walk = (n) => {
          if (n.kind === 'task' && (n.live_sessions || []).some((s) => /sess-unbindable/.test(s.id || ''))) claimed.push(n.id);
          (n.children || []).forEach(walk);
          (n.child_plans || []).forEach(walk);
        };
        items.forEach(walk);
        return claimed.length === 0;
      })());
    ok('S22e a RUNNING unbindable leaf marks its session bound, so it is not ALSO listed as unattributed — exactly one surface claims a session the tree already shows as running',
      (function () {
        const ub = r1.json.unbound_sessions;
        return !ub || !(ub.live_sessions || []).some((a) => /sess-unbindable$/.test(a.id || ''));
      })());
    ok('S22f a plan with NO unbindable dispatch carries an EMPTY live_sessions array, not a fabricated node — and the field exists on every plan so the shape is uniform',
      redesign && Array.isArray(redesign.live_sessions) && redesign.live_sessions.length === 0 &&
      staleDispatchPlan && Array.isArray(staleDispatchPlan.live_sessions) && staleDispatchPlan.live_sessions.length === 0,
      JSON.stringify({ redesign: redesign && redesign.live_sessions, stale: staleDispatchPlan && staleDispatchPlan.live_sessions }));

    // S22g-j (the negative case) + S23d live in the R9-7b section below —
    // they need sess-unbindable-stale's heartbeat, which is written late on
    // purpose (see its note in setup).

    // ---- S23: MAJOR 1 — the roll-up must see a node's OWN live sessions,
    // or the plan row goes green with no "running" WORD anywhere on it
    // (colour-only, which app.css's WCAG 1.4.1 note promises never happens).
    ok('S23 a plan whose ONLY running evidence is its own unbindable-dispatch leaf gets a running ROLL-UP — before this, computeRollUps aggregated only children, so roll_up was {} and the client printed "<id> next" beside a green title',
      unbPlan && unbPlan.roll_up && unbPlan.roll_up.running && unbPlan.roll_up.running.count === 1 &&
      unbPlan.roll_up.running.exemplar === 'unbindable-plan',
      unbPlan && JSON.stringify(unbPlan.roll_up));
    ok('S23b COUNTED EXACTLY ONCE: rich-plan has one bound running task and no unbindable dispatch, so its running roll-up is still count 1 with the TASK as exemplar — the self-stamp must not double-count what the parent already counts',
      richPlan && richPlan.roll_up.running && richPlan.roll_up.running.count === 1 &&
      richPlan.roll_up.running.exemplar === 'rich-plan/1',
      richPlan && JSON.stringify(richPlan.roll_up));
    ok('S23c a TASK row never self-stamps a running roll-up — its own green "running" chip already carries the claim, and a "1 running" badge beside it would be the same fact twice',
      (function () {
        let selfStamped = [];
        const walk = (n) => {
          if (n.kind === 'task' && n.roll_up && n.roll_up.running) selfStamped.push(n.id);
          (n.children || []).forEach(walk);
          (n.child_plans || []).forEach(walk);
        };
        items.forEach(walk);
        return selfStamped.length === 0;
      })());

    ok('S21g running_now is NEVER true without a running leaf beneath it — swept across the WHOLE payload, not just the fixtures named above (a class assertion: any node claiming running must have live evidence somewhere in its subtree)',
      (function () {
        let liars = [];
        const hasRunningLeaf = (n) => {
          if ((n.live_sessions || []).some((s) => s && s.status && s.status.value === 'running')) return true;
          return (n.children || []).some(hasRunningLeaf) || (n.child_plans || []).some(hasRunningLeaf);
        };
        const walk = (n) => {
          if (n.running_now && !hasRunningLeaf(n)) liars.push(n.id);
          (n.children || []).forEach(walk);
          (n.child_plans || []).forEach(walk);
        };
        items.forEach(walk);
        return liars.length === 0;
      })());

    // ---- Round 15: plan_doc {project,path} — the plan-link fix (the old
    // client-side `file:///` href was a DEAD link, live-verified; plan_doc
    // reuses the EXISTING /api/doc resolver, same helper server.selftest.js
    // S25d already proves resolves a REAL project root). This sandbox's
    // fixture plans live under a mktemp repo no project config maps to, so
    // the HONEST value here is null — the "never a fabricated link"
    // fallback path this suite CAN exercise; the happy-path resolution
    // itself is S25d's job (same deriveLib.projectDocRefFor call).
    ok('S21 plan_doc is present (possibly null) on every plan node — a fixture repo outside every configured project root resolves null, never a guessed/fabricated {project,path}',
      richPlan && ('plan_doc' in richPlan) && richPlan.plan_doc === null,
      richPlan && JSON.stringify(richPlan.plan_doc));
    ok('S21b plan_path is unchanged (still the absolute path) — plan_doc is an ADDITION, not a replacement',
      richPlan && typeof richPlan.plan_path === 'string' && richPlan.plan_path.indexOf('rich-plan.md') !== -1,
      richPlan && richPlan.plan_path);

    // ============================================================
    // ROUND 9 (2026-07-23) — the operator's cold-start walkthrough FAIL,
    // docs/reviews/2026-07-17-cockpit-ux-design-input.md "Round 9" — the
    // 8-fix audit table is the oracle for this block.
    // ============================================================

    // ---- R9-1: the plan file's own H1 title, not the raw slug ---------
    const h1Fixture = findItem(items, 'h1-title-fixture');
    ok('R9-1 a plan renders its own H1 TITLE ("A Completely Different Human Title"), never the raw slug ("h1-title-fixture") — the H1 is found even past a leading scaffold HTML comment',
      h1Fixture && h1Fixture.title === 'A Completely Different Human Title' && h1Fixture.title !== h1Fixture.id,
      h1Fixture && h1Fixture.title);
    ok('R9-1b a plan with NO linked ask AND NO H1-shaped heading falls all the way back to the slug (redesign-plan\'s H1 is "redesign", proving the H1 itself is honored, not just this fixture)',
      redesign && redesign.title === 'redesign' && redesign.title !== redesign.id,
      redesign && redesign.title);
    ok('R9-1c the plan H1 title outranks an auto-distilled ASK title (demo-plan carries BOTH: H1 "demo" and ask-alpha\'s auto summary "Build the alpha feature") — an ask summary is a best-effort prompt distillation (round 1: "not a good reference for what my actual ask was"); the plan\'s own deliberately-authored H1 wins whenever no operator edit exists',
      demoPlan && demoPlan.title === 'demo' && demoPlan.title_source === 'auto',
      demoPlan && JSON.stringify({ title: demoPlan.title, title_source: demoPlan.title_source }));

    // ---- R9-4: plan-level provenance classification --------------------
    const harnessChore = findItem(items, 'harness-chore-fixture');
    ok('R9-4 a "harness-" prefixed slug with NO linked ask classifies as provenance:machine (the chore classifier is no longer inert on plan-rooted rows)',
      harnessChore && harnessChore.provenance === 'machine', harnessChore && harnessChore.provenance);
    const nlFindingChore = findItem(items, 'nl-finding-999-chore-fixture');
    ok('R9-4b an "nl-finding-" prefixed slug classifies as provenance:machine',
      nlFindingChore && nlFindingChore.provenance === 'machine', nlFindingChore && nlFindingChore.provenance);
    const watchdogChore = findItem(items, 'agent-watchdog-fixture');
    ok('R9-4c a slug containing "watchdog" (mid-slug, not just a prefix) classifies as provenance:machine',
      watchdogChore && watchdogChore.provenance === 'machine', watchdogChore && watchdogChore.provenance);
    const sweeperFixture = findItem(items, 'worktree-sweeper-fixture');
    ok('R9-4d "sweeper" does NOT false-positive the "sweep" word heuristic (hyphen-bounded on purpose) — stays provenance:operator',
      sweeperFixture && sweeperFixture.provenance === 'operator', sweeperFixture && sweeperFixture.provenance);
    const explicitOperatorOverride = findItem(items, 'harness-explicit-operator-override');
    ok('R9-4e an explicit `provenance: operator` plan-header field OVERRIDES the "harness-" slug heuristic (never hides an operator-marked plan)',
      explicitOperatorOverride && explicitOperatorOverride.provenance === 'operator',
      explicitOperatorOverride && explicitOperatorOverride.provenance);
    const explicitMachineOverride = findItem(items, 'not-chore-shaped-explicit-machine');
    ok('R9-4f an explicit `provenance: machine` plan-header field OVERRIDES a non-matching slug in the OTHER direction too',
      explicitMachineOverride && explicitMachineOverride.provenance === 'machine',
      explicitMachineOverride && explicitMachineOverride.provenance);
    const harnessLinked = findItem(items, 'harness-linked-to-operator-ask');
    ok('R9-4g a machine-SHAPED slug ("harness-...") that IS linked to a real operator ask stays provenance:operator (A9: classifier keys on PROVENANCE, never subject matter — a linked ask always wins over the slug heuristic)',
      harnessLinked && harnessLinked.provenance === 'operator', harnessLinked && harnessLinked.provenance);
    const hiddenChoreCount = items.filter((i) => i.provenance === 'machine').length;
    ok('R9-4h the hidden-count is now TRUE/non-zero — the pre-fix defect was "0 hidden" while chore-shaped plans rendered; exactly the 4 real machine-classified fixtures above (harness-chore, nl-finding-999-chore, agent-watchdog, not-chore-shaped-explicit-machine), never more, never fewer',
      hiddenChoreCount === 4, hiddenChoreCount + ': ' + items.filter((i) => i.provenance === 'machine').map((i) => i.id).join(','));

    // ---- R9-7b: unbound (unattributed) live sessions -------------------
    ok('R9-7b honest absence: with only a BOUND session (sess-op-1, attached to rich-plan/1) and a CRASHED unbound one, unbound_sessions is null — never a fake/empty node',
      r1.json.unbound_sessions === null || r1.json.unbound_sessions === undefined,
      JSON.stringify(r1.json.unbound_sessions));
    // Now attach a genuinely RUNNING session with NO task binding anywhere —
    // the real-world shape this fix targets (a live heartbeat the tree
    // cannot attribute to any task).
    fs.writeFileSync(path.join(heartbeatDir, 'sess-unbound-running.json'), JSON.stringify({
      schema: 1, session_id: 'sess-unbound-running', pid: process.pid, cwd: repoDir, repo_root: repoDir,
      worktree_root: repoDir, branch: 'fixture-branch', model: 'fixture',
      last_activity_ts: new Date().toISOString(), last_event: 'fixture', marker_state: 'none',
    }));
    const r9r7 = await httpGet(PORT, '/api/roadmap');
    const unbound = r9r7.json.unbound_sessions;
    ok('R9-7b a genuinely running, unattributed session now surfaces the top-of-tree node, named + counted',
      unbound && unbound.kind === 'unbound-sessions' && /1\)/.test(unbound.title),
      JSON.stringify(unbound));
    ok('R9-7b-2 the node lists the session (short-form id + branch + running status), never a color-only signal',
      unbound && Array.isArray(unbound.live_sessions) && unbound.live_sessions.length === 1 &&
      unbound.live_sessions[0].id.indexOf('sess-unbound-running'.slice(0, 8)) !== -1 &&
      /running/.test(unbound.live_sessions[0].status.label),
      unbound && JSON.stringify(unbound.live_sessions));
    ok('R9-7b-3 sess-op-1 (bound to rich-plan/1) is NEVER listed as unattributed — attribution, not mere existence, is what is being tested',
      unbound && !unbound.live_sessions.some((a) => a.id.indexOf('sess-op-1') !== -1),
      unbound && JSON.stringify(unbound.live_sessions));
    ok('R9-7b-4 the CRASHED unbound heartbeat (30 days stale) never counts as "running, unattributed" — crashed is excluded, not just unbound',
      unbound && !unbound.live_sessions.some((a) => a.id.indexOf('sess-unbound-crashed') !== -1),
      unbound && JSON.stringify(unbound.live_sessions));
    // SPLIT-BRAIN FIX (2026-08-01): these members were stamped
    // status.value 'in-progress' while their own label said "running" — the
    // one node in the tree that is a pure live-heartbeat truth claim was
    // the one whose machine-readable value denied it. The client's
    // AGENT_STATUS_GLYPH has no 'in-progress' key, so every live session
    // rendered with the UNKNOWN glyph, and the summary chip was hard-coded
    // to the in-progress (violet) class — literally the operator's "the
    // purple items ... are supposed to be green".
    ok('R9-7b-5 the unattributed node AND each of its session members carry status.value "running" — the value agrees with the label it has always printed (a client keying colour/glyph off .value now gets the running treatment, not the unknown fallback)',
      unbound && unbound.status.value === 'running' &&
      unbound.live_sessions.every((a) => a.status && a.status.value === 'running'),
      unbound && JSON.stringify({ node: unbound.status, members: unbound.live_sessions.map((a) => a.status.value) }));
    ok('R9-7b-6 the unattributed node is running_now — the tree\'s ONE live-work surface answers the same question every plan/task node now answers',
      unbound && unbound.running_now === true,
      unbound && JSON.stringify(unbound.running_now));
    // R9-7b-7: sess-unbound-running's heartbeat is written with
    // `new Date().toISOString()` above, i.e. seconds old — classifyHeartbeatAge
    // returns 'live' for it. The label branch compared against 'active', a
    // token that function NEVER returns ('live' | 'quiet' | 'crashed'), so the
    // freshest possible session was labelled "running (live)". The old
    // /running/ regex in R9-7b-2 passed either way; this pins the actual word.
    ok('R9-7b-7 a heartbeat that is seconds old is labelled plain "running", NOT "running (live)" — the label branch compared against "active", which classifyHeartbeatAge can never return, so the freshest session carried a spurious parenthetical on the one surface that says "running" out loud',
      unbound && ((unbound.live_sessions || [])[0] || {}).status &&
      unbound.live_sessions[0].status.label === 'running',
      unbound && JSON.stringify((unbound.live_sessions || []).map((a) => a.status && a.status.label)));

    // ---- R9-7b-8..10: THE PHANTOM-RUNNING FIX (2026-08-04, operator-flagged
    // Defect A) — a heartbeat whose PID IS VERIFIABLY DEAD but whose
    // last_activity_ts is only 2h old (well within the quiet grace window,
    // the EXACT "running (quiet), 2h/17h/22h ago" shape the operator's own
    // sampled evidence showed for 5 real sessions, all with dead pids). The
    // pid is a REAL just-exited child process (spawnSync blocks until it has
    // fully exited), not a guessed-nonexistent integer — the same "just-
    // exited subshell" proof idiom session-heartbeat-lib.sh's own self-test
    // uses. Pre-fix (classifyHeartbeatAge, age-only) this heartbeat renders
    // 'quiet' -> counted as "running, unattributed". Post-fix
    // (classifyHeartbeatLiveness) the dead pid overrides that verdict to
    // 'crashed' -> excluded, exactly like the already-covered 30-day-old
    // sess-unbound-crashed fixture (R9-7b-4), but proven here via a FRESH-
    // LOOKING timestamp + a dead pid rather than an old timestamp alone —
    // the one shape R9-7b-4 does NOT cover.
    const deadChildRt = spawnSync(process.execPath, ['-e', 'process.exit(0)']);
    fs.writeFileSync(path.join(heartbeatDir, 'sess-unbound-phantom.json'), JSON.stringify({
      schema: 1, session_id: 'sess-unbound-phantom', pid: deadChildRt.pid, cwd: repoDir, repo_root: repoDir,
      worktree_root: repoDir, branch: 'fixture-phantom', model: 'fixture',
      last_activity_ts: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(), // 2h ago
      last_event: 'fixture', marker_state: 'none',
    }));
    const rPhantom = await httpGet(PORT, '/api/roadmap');
    const unboundPhantom = rPhantom.json.unbound_sessions;
    ok('R9-7b-8 THE PHANTOM-RUNNING FIX: a heartbeat 2h old (quiet-window-fresh, age-only would say "running (quiet)") with a PROVEN-DEAD pid is EXCLUDED from the unattributed node — never rendered running',
      unboundPhantom && !unboundPhantom.live_sessions.some((a) => a.id.indexOf('sess-unbound-phantom') !== -1),
      unboundPhantom && JSON.stringify(unboundPhantom.live_sessions));
    ok('R9-7b-9 ...the genuinely-alive sess-unbound-running is UNAFFECTED by the new dead-pid exclusion — still counted, still exactly 1',
      unboundPhantom && unboundPhantom.live_sessions.length === 1 &&
      unboundPhantom.live_sessions[0].id.indexOf('sess-unbound-running') !== -1,
      unboundPhantom && JSON.stringify(unboundPhantom.live_sessions));
    ok('R9-7b-10 ...and the node title\'s count stays "(1)", not "(2)" — the dead-pid session never inflates the "N running, unattributed" figure the operator reads',
      unboundPhantom && /\(1\)$/.test(unboundPhantom.title),
      unboundPhantom && unboundPhantom.title);

    // ---- S22g-j + S23d: THE NEGATIVE CASE for the new unbindable path, and
    // the Critical's regression guard. Until this round the new function had
    // NO negative test at all — its header promised "a quiet dispatch is
    // still stalled, not green" and nothing checked it (harness-reviewer
    // Major 3). unbindable-stale-plan is the same fixture shape as
    // unbindable-plan with the SAME freshness of heartbeat; ONLY the dispatch
    // timestamp differs (2h vs 10min), so the idle gate is isolated.
    // The heartbeat is written HERE, after every assertion above that pins
    // the unattributed population, so none of their coverage is diluted.
    fs.writeFileSync(path.join(heartbeatDir, 'sess-unbindable-stale.json'), JSON.stringify({
      schema: 1, session_id: 'sess-unbindable-stale', pid: process.pid, cwd: repoDir, repo_root: repoDir,
      worktree_root: repoDir, branch: 'fixture-unbindable-stale', model: 'fixture',
      last_activity_ts: new Date().toISOString(), last_event: 'fixture', marker_state: 'none',
    }));
    const rStale = await httpGet(PORT, '/api/roadmap');
    const unbStale = findItem(rStale.json.items, 'unbindable-stale-plan');
    const unbStaleLeaf = (unbStale && (unbStale.live_sessions || [])[0]) || {};
    ok('S22g an unbindable dispatch older than the 60min idle window renders STALLED, not running — the new path inherits the same task-level idle gate, it is not a colour shortcut around it',
      (unbStaleLeaf.status || {}).value === 'stalled',
      JSON.stringify(unbStaleLeaf.status || null));
    ok('S22h ...and its plan is therefore NOT running_now and NOT green — the whole distinction this change exists to draw, proved on the new path rather than assumed from it',
      unbStale && unbStale.running_now === false,
      JSON.stringify(unbStale && unbStale.running_now));
    ok('S22i THE CRITICAL REGRESSION GUARD: this session\'s heartbeat is SECONDS old, so it is genuinely live — it must STILL be counted by the unattributed node. Binding every session the function touches (not just the running ones) silently removed live sessions from the ONE surface that says "N running"',
      (function () {
        const ub = rStale.json.unbound_sessions;
        return !!ub && (ub.live_sessions || []).some((a) => /sess-unbindable-stale/.test(a.id || ''));
      })(),
      JSON.stringify(((rStale.json.unbound_sessions || {}).live_sessions || []).map((a) => a.id)));
    ok('S22j ...and the two surfaces do not contradict each other: the plan row says the DISPATCH went quiet, the unattributed node says the SESSION is alive. Both true, and the leaf text says which is which',
      /dispatched for task "another-slug-not-a-task-id", which is not a task id in this plan/.test(unbStaleLeaf.title || '') &&
      /still alive/.test((unbStaleLeaf.status || {}).label || ''),
      JSON.stringify({ title: unbStaleLeaf.title || null, label: (unbStaleLeaf.status || {}).label || null }));
    ok('S23d the stale unbindable plan gets NO running roll-up — the roll-up follows the leaf value, so it cannot manufacture a "running" word the colour is not entitled to either',
      unbStale && (!unbStale.roll_up || !unbStale.roll_up.running),
      unbStale && JSON.stringify(unbStale.roll_up));
    ok('S22k a RUNNING unbindable leaf still binds its session — sess-unbindable (fresh heartbeat, recent dispatch) is claimed by unbindable-plan and stays OUT of the unattributed node, so the scoping is a scoping and not a blanket removal',
      (function () {
        const ub = rStale.json.unbound_sessions;
        return !!ub && !(ub.live_sessions || []).some((a) => /sess-unbindable$/.test(a.id || ''));
      })(),
      JSON.stringify(((rStale.json.unbound_sessions || {}).live_sessions || []).map((a) => a.id)));

    // ---- R9-8: multi-repo roots -----------------------------------------
    ok('R9-8 zero-config default: with no projects config, a second repo\'s plan never appears (single-repo behavior unchanged)',
      topIds.indexOf('other-repo-plan') === -1);
    const projectsConfigPath = path.join(tmp, 'fixture-projects.json');
    fs.writeFileSync(projectsConfigPath, JSON.stringify({
      // Object form (R17): declares a top-level display group explicitly.
      'other-project': { root: otherRepoDir, group: 'Pocket Technician' },
      'empty-project': emptyRepoDir,
      // Legacy flat-string form (R17): no group -> honest '(ungrouped)'.
      'flat-project': flatRepoDir,
    }));
    process.env.ROADMAP_PROJECTS_CONFIG = projectsConfigPath;
    const rMulti = await httpGet(PORT, '/api/roadmap');
    const multiItems = (rMulti.json && rMulti.json.items) || [];
    const multiIds = multiItems.map((i) => i.id);
    ok('R9-8b once a repo is CONFIGURED, its docs/plans/ plan roots the tree too, attributed to ITS OWN project (not "self"/neural-lace)',
      multiIds.indexOf('other-repo-plan') !== -1 &&
      findItem(multiItems, 'other-repo-plan').project === 'other-repo',
      JSON.stringify({ ids: multiIds, project: findItem(multiItems, 'other-repo-plan') && findItem(multiItems, 'other-repo-plan').project }));
    ok('R9-8c the self repo\'s own plans are UNCHANGED by adding other configured repos (this repo is still scanned, still first)',
      multiIds.indexOf('demo-plan') !== -1 && multiIds.indexOf('redesign-plan') !== -1);
    ok('R9-8d a THIRD configured repo with NO docs/plans/ at all contributes NOTHING — honest absence, never a crash, never a synthesized item',
      rMulti.status === 200 && rMulti.json.ok === true);

    // ---- R17 (2026-07-30, decision A): multi-project display GROUPING --
    // redesign-plan (not demo-plan): demo-plan is linked to ask-alpha, whose
    // OWN registry `project` field ('fixture-proj') wins over the path-
    // derived one (see the `projectKey` precedence in derivePlanRootNode) —
    // an unrelated pre-existing quirk this test must not trip over.
    // redesign-plan has NO linked ask, so its project is purely
    // planProjectFromPath(absPath) === path.basename(repoDir), the exact
    // self-detection this test verifies.
    const selfPlanForGroup = findItem(multiItems, 'redesign-plan');
    ok('R17-G1 the self repo\'s own plans carry project_group "Neural Lace" (intrinsic — this app\'s own home repo has no config/projects.json entry to read a group from)',
      selfPlanForGroup && selfPlanForGroup.project_group === 'Neural Lace',
      selfPlanForGroup && selfPlanForGroup.project_group);
    const otherRepoItem = findItem(multiItems, 'other-repo-plan');
    ok('R17-G2 a configured repo using the OBJECT config form ({root, group}) carries the DECLARED group ("Pocket Technician") on its plans — never a hardcoded default',
      otherRepoItem && otherRepoItem.project_group === 'Pocket Technician',
      otherRepoItem && otherRepoItem.project_group);
    const flatRepoItem = findItem(multiItems, 'flat-project-plan');
    ok('R17-G3 a configured repo using the LEGACY flat-string config form (no group declared) lands its plans in the honest "(ungrouped)" catch-all, never silently defaulted into one of the named groups',
      flatRepoItem && flatRepoItem.project_group === '(ungrouped)',
      flatRepoItem && flatRepoItem.project_group);

    // ------------------------------------------------------------------
    // ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 (2026-07-29 round 14) —
    // a SCANNED plan file (docs/plans/, not registry-linked) with a
    // surviving-but-unrecognized Status: token, or an unreadable scan
    // read, must NEVER render a confident not-started bucket, and must
    // NEVER silently vanish from the tree. Placed BEFORE S14 below (which
    // permanently corrupts the ask-registry for the rest of this run) —
    // these fixtures include a registry-override-backed "done-plan" sanity
    // check that needs the registry still readable.
    // ------------------------------------------------------------------

    // (a) live repro of the advocate's fx-corrupt2 fixture: a Status:
    // header survives ("WHAT") but is outside the known enum, plus
    // binary garbage bytes in the body -- zero parseable tasks.
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-corrupt2.md'),
      Buffer.from('garbage\nStatus: WHAT\n\x01\xff\n', 'binary'));
    const rCorruptA = await httpGet(PORT, '/api/roadmap');
    const corruptAItem = findItem(rCorruptA.json.items, 'fx-corrupt2');
    ok('S15 a scanned plan with an unrecognized Status: token ("WHAT") renders unknown("plan parse failed"), NEVER a confident not-started bucket (ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01a)',
      corruptAItem && corruptAItem.status.value === 'unknown' && /plan parse failed/.test(corruptAItem.status.reason) &&
      /unrecognized Status/.test(corruptAItem.status.reason),
      JSON.stringify(corruptAItem && corruptAItem.status));

    // A KNOWN status (ACTIVE) but a genuinely fresh, taskless plan stub
    // (ordinary prose, no `## Tasks` yet) must STAY not-started — the
    // corruption signature (binary/control bytes), not mere taskless-ness,
    // is what distinguishes a corrupt plan from a legitimately new one.
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-fresh-stub.md'),
      '# Plan: Fresh Stub\n\nStatus: ACTIVE\n\nTasks not written yet -- just an idea.\n');
    const rFreshStub = await httpGet(PORT, '/api/roadmap');
    const freshStubItem = findItem(rFreshStub.json.items, 'fx-fresh-stub');
    ok('S15b a genuinely fresh, taskless plan stub (ordinary prose, KNOWN status) still renders not-started -- taskless-ness ALONE never triggers the corruption path',
      freshStubItem && freshStubItem.status.value === 'not-started',
      JSON.stringify(freshStubItem && freshStubItem.status));

    // A KNOWN status (ACTIVE) but taskless AND corrupt (binary/control
    // bytes, zero tasks) -- the OTHER half of the required fix.
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-corrupt-taskless.md'),
      Buffer.from('# Plan: Corrupt Taskless\n\nStatus: ACTIVE\n\n\x01\x02\xff garbage, no real tasks\n', 'binary'));
    const rCorruptTaskless = await httpGet(PORT, '/api/roadmap');
    const corruptTasklessItem = findItem(rCorruptTaskless.json.items, 'fx-corrupt-taskless');
    ok('S15c a KNOWN-status plan that is BOTH taskless AND shows the binary-corruption signature renders unknown("plan parse failed"), never not-started (ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01, "zero tasks AND unparseable structure" clause)',
      corruptTasklessItem && corruptTasklessItem.status.value === 'unknown' && /plan parse failed/.test(corruptTasklessItem.status.reason),
      JSON.stringify(corruptTasklessItem && corruptTasklessItem.status));

    // (e) ROADMAP-STATUSLESS-CORRUPT-VANISH-01 (advocate re-run S7 residual):
    // the header itself is DESTROYED — no Status: line survives at all — but
    // the body carries the binary-corruption signature. Pre-fix this file
    // VANISHED from the tree (the no-header branch returned silently); the
    // fix surfaces it as unknown. Its control: a clean header-less evidence
    // stub must STILL be excluded — flooding the tree with every .md was
    // Round 14's correct fear, and the corruption signature is the line.
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-corrupt3.md'),
      Buffer.from('\x01\x02\xffgarbage where the header was\n\n- [x] 1. a task that survived\n- [ ] 2. another\n', 'binary'));
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-clean-stub-evidence.md'),
      '# Evidence — some plan\n\nOrdinary prose, no Status header, no corruption.\n');
    const rHeaderless = await httpGet(PORT, '/api/roadmap');
    const headerlessItem = findItem(rHeaderless.json.items, 'fx-corrupt3');
    const cleanStubItem = findItem(rHeaderless.json.items, 'fx-clean-stub-evidence');
    ok('S15e a plan whose HEADER was destroyed (no Status: line + binary-corruption signature) surfaces as unknown("header destroyed"), NEVER vanishes (ROADMAP-STATUSLESS-CORRUPT-VANISH-01)',
      headerlessItem && headerlessItem.status.value === 'unknown' && /no Status header/.test(headerlessItem.status.reason),
      JSON.stringify(headerlessItem && headerlessItem.status));
    ok('S15f a CLEAN header-less .md (evidence stub) stays EXCLUDED — the corruption signature, not header-less-ness, is the trigger (no tree flooding)',
      !cleanStubItem, JSON.stringify(cleanStubItem || null));
    fs.rmSync(path.join(repoDir, 'docs', 'plans', 'fx-corrupt3.md'), { force: true });
    fs.rmSync(path.join(repoDir, 'docs', 'plans', 'fx-clean-stub-evidence.md'), { force: true });

    // (c) an unreadable (EACCES) scanned plan file must surface as an
    // unknown root, never silently skipped by the scan's catch. chmod 000
    // is a no-op for root/some sandboxes -- probe first, skip honestly.
    {
      const probePath2 = path.join(repoDir, 'docs', 'plans', '.eacces-probe2');
      fs.writeFileSync(probePath2, 'x');
      fs.chmodSync(probePath2, 0o000);
      let probeBlocked2 = true;
      try { fs.readFileSync(probePath2, 'utf8'); probeBlocked2 = false; } catch (_) { probeBlocked2 = true; }
      fs.chmodSync(probePath2, 0o644);
      fs.rmSync(probePath2, { force: true });
      if (!probeBlocked2) {
        console.log('  SKIP: S15d EACCES-scanned-plan scenario -- chmod 000 is a no-op in this sandbox (likely running as root)');
      } else {
        fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-unreadable.md'), '# Plan: Unreadable\n\nStatus: ACTIVE\n\n## Tasks\n\n- [ ] 1. x\n');
        fs.chmodSync(path.join(repoDir, 'docs', 'plans', 'fx-unreadable.md'), 0o000);
        const rUnreadable = await httpGet(PORT, '/api/roadmap');
        const unreadableItem = findItem(rUnreadable.json.items, 'fx-unreadable');
        ok('S15d a scanned plan file that exists but cannot be READ (EACCES) surfaces as unknown("plan file unreadable"), NEVER silently skipped/vanished (ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01c)',
          unreadableItem && unreadableItem.status.value === 'unknown' && /plan file unreadable/.test(unreadableItem.status.reason),
          JSON.stringify(unreadableItem && unreadableItem.status));
        fs.chmodSync(path.join(repoDir, 'docs', 'plans', 'fx-unreadable.md'), 0o644);
      }
    }

    // ------------------------------------------------------------------
    // ROADMAP-SUPERSEDED-RENDERS-PENDING-01 (2026-07-29 round 14) — an
    // authored Status: SUPERSEDED/ABANDONED plan must render `complete`
    // (so it joins the client's existing Shipped grouping) with a
    // distinct terminal_label, NEVER as an ordinary pending item.
    // ------------------------------------------------------------------
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-superseded.md'), [
      '# Plan: Old Polish Plan', '', 'Status: SUPERSEDED', '', '## Tasks', '',
      '- [ ] 1. never finished before being superseded',
      '', // deliberately NOT all-done — the pre-fix bug applied the task-count ladder regardless
    ].join('\n'));
    fs.writeFileSync(path.join(repoDir, 'docs', 'plans', 'fx-abandoned.md'), [
      '# Plan: Abandoned Idea', '', 'Status: ABANDONED', '', '## Tasks', '',
      '- [ ] 1. never started',
      '',
    ].join('\n'));
    const rSuperseded = await httpGet(PORT, '/api/roadmap');
    const supersededItem = findItem(rSuperseded.json.items, 'fx-superseded');
    ok('S16 a Status: SUPERSEDED plan (with UNDONE tasks) renders status.value:"complete" (joins Shipped), never "not-started"/"in-progress" among live work',
      supersededItem && supersededItem.status.value === 'complete',
      JSON.stringify(supersededItem && supersededItem.status));
    ok('S16b ...carrying a distinct terminal_label:"superseded" (so the client renders it as its OWN labeled chip, never indistinguishable from ordinary shipped work)',
      supersededItem && supersededItem.status.terminal_label === 'superseded',
      JSON.stringify(supersededItem && supersededItem.status));
    const abandonedItem = findItem(rSuperseded.json.items, 'fx-abandoned');
    ok('S16c a Status: ABANDONED plan renders the same complete+terminal_label pattern, labeled "abandoned"',
      abandonedItem && abandonedItem.status.value === 'complete' && abandonedItem.status.terminal_label === 'abandoned',
      JSON.stringify(abandonedItem && abandonedItem.status));
    const completedFixtureItem = findItem(rSuperseded.json.items, 'done-plan');
    ok('S16d a genuinely complete plan (done-plan, S10\'s operator-override fixture) is UNCHANGED by this fix — still complete, but with NO terminal_label (ordinary shipped work, not a superseded/abandoned one)',
      completedFixtureItem && completedFixtureItem.status.value === 'complete' && !completedFixtureItem.status.terminal_label,
      JSON.stringify(completedFixtureItem && completedFixtureItem.status));

    // ------------------------------------------------------------------
    // ROADMAP-WAITING-ON-YOU-SIGNAL-01 (2026-07-29 round 14, the S6
    // blocker) — buildWaitingOnYouMap's END-TO-END wiring: a real needs-you
    // ledger item conservatively matched to waiting-plan/1 (fixture set up
    // at the top of this file) must make THAT task -- and only that task --
    // render stalled(waiting-on-you) with a real #inbox/<id> unblock link,
    // never a generic 'crashed' fallback.
    // ------------------------------------------------------------------
    const rWaiting = await httpGet(PORT, '/api/roadmap');
    const waitingTask = findItem(rWaiting.json.items, 'waiting-plan/1');
    ok('S17 waiting-plan/1 (started, no heartbeat anywhere, referenced by a real needs-you ledger item) renders stalled(waiting-on-you) -- the waitingOnYouId signal WINS over the generic crashed fallback',
      waitingTask && waitingTask.status.value === 'stalled' && waitingTask.status.reason_class === 'waiting-on-you',
      JSON.stringify(waitingTask && waitingTask.status));
    ok('S17b ...carrying a real status.unblock {label, hash} pointing at #inbox/NY-waiting-1 -- the PRE-EXISTING, previously-never-populated consumer field (this file\'s own header, line ~96) the client already renders as a real link',
      waitingTask && waitingTask.status.unblock && waitingTask.status.unblock.hash === '#inbox/NY-waiting-1',
      JSON.stringify(waitingTask && waitingTask.status.unblock));
    // Roll-up: the plan-level ancestor must show the counted waiting-on-you
    // badge (C1 roll-up law), never masked by the plan's own in-progress-ish
    // status.
    const waitingPlanRoot = findItem(rWaiting.json.items, 'waiting-plan');
    ok('S17c the waiting-plan ROOT rolls up the waiting-on-you badge from its stalled descendant (C1: attention states propagate to every collapsed ancestor)',
      waitingPlanRoot && waitingPlanRoot.roll_up && waitingPlanRoot.roll_up['waiting-on-you'] && waitingPlanRoot.roll_up['waiting-on-you'].count === 1,
      JSON.stringify(waitingPlanRoot && waitingPlanRoot.roll_up));
    // Conservative matching: a plan/task pair NOT explicitly named anywhere
    // in the ledger must NEVER be marked waiting-on-you (no fuzzy matching).
    const unrelatedTask = findItem(rWaiting.json.items, 'demo-plan/2');
    ok('S17d conservative matching: an UNRELATED task (demo-plan/2, never mentioned in the ledger) is NEVER marked waiting-on-you -- no fuzzy/global matching',
      unrelatedTask && unrelatedTask.status.reason_class !== 'waiting-on-you',
      JSON.stringify(unrelatedTask && unrelatedTask.status));

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
