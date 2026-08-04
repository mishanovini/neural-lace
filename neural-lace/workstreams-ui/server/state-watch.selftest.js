'use strict';
// state-watch.selftest.js — sandboxed self-test for server/state-watch.js
// (2026-08-02 subprocess-storm fix: push fast path + anti-entropy floor).
//
// Every scenario counts REAL subprocess spawns (a stub NL_BIN /
// NL_DERIVE_LIB script appends one line to a spawn-log file per
// invocation, mirroring server.selftest.js's own stub convention) rather
// than just counting in-process trigger() calls — the golden case this
// fixes (2026-08-02, 45/93 live bash processes = `nl.sh status --json`) is
// about REAL OS processes, so the proof has to be at that level too.
//
// EACH SCENARIO gets its OWN stub scripts + spawn-log file (writeStubs
// below) rather than sharing one global log: a real bash -l spawn on this
// machine was directly measured taking well over a second end-to-end
// (login-shell profile load), so a scenario's own child processes can
// still be completing when the NEXT scenario starts — a shared log would
// misattribute a slow straggler from scenario N to scenario N+1's count.
// Per-scenario isolation makes every assertion exact regardless of timing.
//
// Run: `node server/state-watch.selftest.js`. Exit 0 PASS / 1 FAIL.

const fs = require('fs');
const os = require('os');
const path = require('path');

let PASSED = 0, FAILED = 0;
function ok(name, cond, detail) {
  if (cond) { PASSED++; console.log('  PASS: ' + name); }
  else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
}

function spawnCount(spawnLog) {
  try { return fs.readFileSync(spawnLog, 'utf8').split('\n').filter(Boolean).length; } catch (_) { return 0; }
}

// waitUntil(predicate, timeoutMs) -> Promise<boolean> — POLLS (never a
// fixed sleep), matching server.selftest.js's own settle-loop discipline:
// spawns are async (child_process.spawn) and this machine's real bash -l
// login-shell spawn cost was directly measured well over a second, so a
// generous timeout is used throughout rather than a guessed fixed delay.
function waitUntil(predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve) => {
    (function poll() {
      if (predicate()) return resolve(true);
      if (Date.now() >= deadline) return resolve(false);
      setTimeout(poll, 50);
    })();
  });
}

// waitSettled(cache, subCommandKeys, timeoutMs) — waits until EVERY
// subcommand's cache entry has a non-null derived_at, i.e. at least one
// refresh attempt has SETTLED for each — the same semantics
// server.selftest.js's own boot-settle loop uses ("a cache entry has
// settled once its rc is no longer the initial null sentinel").
function waitSettled(cache, subCommandKeys, timeoutMs) {
  return waitUntil(() => subCommandKeys.every((s) => cache.get(s).derived_at != null), timeoutMs);
}

// snapshotDerivedAt/waitAllAdvanced — for proving a SECOND full cycle
// completed (not just the fastest lane member): waitSettled alone can't
// tell "still the first cycle's value" from "a fresh cycle already
// finished", so scenarios that trigger a second change snapshot every
// subcommand's derived_at first and wait until ALL of them have moved past
// that snapshot — i.e. the WHOLE cycle (both lanes) settled again, not just
// whichever subcommand happens to run first in its lane.
function snapshotDerivedAt(cache, subCommandKeys) {
  const m = {};
  subCommandKeys.forEach((s) => { m[s] = cache.get(s).derived_at; });
  return m;
}
function waitAllAdvanced(cache, subCommandKeys, prior, timeoutMs) {
  return waitUntil(() => subCommandKeys.every((s) => cache.get(s).derived_at != null && cache.get(s).derived_at !== prior[s]), timeoutMs);
}

// writeStubs(tmp, tag) -> {stubPath, deriveLibPath, spawnLog, failSentinel,
// snapshotPath}
//
// Generates a FRESH NL_BIN stub + NL_DERIVE_LIB stub, each writing to a
// spawn-log file unique to `tag` — see the file header for why isolation
// matters here. `sub=status` fails (rc=3) whenever failSentinel exists,
// mirroring server.selftest.js's own FAIL_STATUS convention.
//
// snapshotPath (FIX2, operator directive 2026-08-04): every scenario below
// now goes through derive-cache.js's disk-persistence path too (refreshAll()
// persists after every settled cycle — see derive-cache.js's own header),
// so EACH scenario needs its own isolated OBS_DERIVE_SNAPSHOT_PATH for the
// SAME reason it already needs its own spawn-log/fail-sentinel: without
// this, scenario B's refreshAll() would persist to the real default path
// (unsandboxed HOME in this suite), and a LATER scenario's `new
// dc.DeriveCache(...)` construction would silently load that leftover
// snapshot — breaking scenario A's "still the unpopulated initial sentinel"
// assertion on any run after the first, and weakening scenario F's
// "generated_at ADVANCES" proof by seeding a stale non-null derived_at
// before the real trigger fires. A per-tag tmp path (never pre-existing)
// keeps every scenario exactly as isolated as it already is for spawns.
function writeStubs(tmp, tag) {
  const spawnLog = path.join(tmp, 'spawn-log-' + tag + '.txt').replace(/\\/g, '/');
  const failSentinel = path.join(tmp, 'FAIL-' + tag + '.txt').replace(/\\/g, '/');
  const snapshotPath = path.join(tmp, 'snapshot-' + tag + '.json');
  const stubPath = path.join(tmp, 'nl-stub-' + tag + '.sh');
  fs.writeFileSync(stubPath, [
    '#!/bin/bash',
    'set -u',
    'sub="${1:-}"; shift || true',
    'echo "spawn $sub" >> "' + spawnLog + '"',
    'if [[ "$sub" == "status" ]] && [[ -f "' + failSentinel + '" ]]; then',
    '  echo "simulated nl status failure" >&2',
    '  exit 3',
    'fi',
    'case "$sub" in',
    '  status) echo \'{"schema":1,"oracle":"nl-status","sessions":[],"doctor":{"verdict":"[doctor] GREEN","ts":"2026-08-02T00:00:00Z","exit_code":"0"}}\' ;;',
    '  needs-me) echo \'{"schema":1,"oracle":"od_needs_me","items":[]}\' ;;',
    '  shipped) echo \'{"schema":1,"oracle":"od_shipped_since","since":"2026-08-01T00:00:00Z","shas":[],"decisions":[],"failures":0}\' ;;',
    '  costs) echo \'{"schema":1,"oracle":"od_costs","total":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"throttle_events":0,"est_minutes_lost":0,"truncated_to_recent":false,"sessions":[]}\' ;;',
    '  backlog) echo \'{"schema":1,"oracle":"od_backlog_health","open_total":0,"terminal_total":0,"priority":{"high":0,"medium":0,"low":0,"unlabeled":0},"age":{"0_7d":0,"8_30d":0,"31_90d":0,"over_90d":0,"undated":0},"flow_7d":{"adds":0,"terminal":0,"terminal_undated":0},"tiers":{"high_days":7,"medium_days":30,"low_days":90}}\' ;;',
    '  *) echo "nl-stub: unknown subcommand $sub" >&2; exit 1 ;;',
    'esac',
  ].join('\n'));
  fs.chmodSync(stubPath, 0o755);

  const deriveLibPath = path.join(tmp, 'derive-lib-stub-' + tag + '.sh');
  fs.writeFileSync(deriveLibPath, [
    '#!/bin/bash',
    'od_harness_health() {',
    '  echo "spawn health" >> "' + spawnLog + '"',
    '  echo \'{"schema":1,"oracle":"od_harness_health","doctor":{"verdict":"[doctor] GREEN","ts":"2026-08-02T00:00:00Z","exit_code":"0"},"gates":[]}\'',
    '}',
  ].join('\n'));
  fs.chmodSync(deriveLibPath, 0o755);

  return { stubPath: stubPath, deriveLibPath: deriveLibPath, spawnLog: spawnLog, failSentinel: failSentinel, snapshotPath: snapshotPath };
}

function useStubs(fixture) {
  process.env.NL_BIN = fixture.stubPath;
  process.env.NL_DERIVE_LIB = fixture.deriveLibPath;
  process.env.OBS_DERIVE_SNAPSHOT_PATH = fixture.snapshotPath;
}

const SPAWN_WAIT_MS = 20000; // generous: this machine's real bash -l login-shell spawn was measured well over 1s each

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'o4-statewatch-st-'));
  const watchDir = path.join(tmp, 'watched');
  fs.mkdirSync(watchDir, { recursive: true });

  delete require.cache[require.resolve('./derive-cache.js')];
  delete require.cache[require.resolve('./state-watch.js')];
  const dc = require('./derive-cache.js');
  const stateWatch = require('./state-watch.js');
  const SUBS = Object.keys(dc.SUBCOMMANDS);
  const SUB_COUNT = SUBS.length; // one spawn per subcommand per refresh cycle

  try {
    // ================================================================
    // Scenario A — IDLE means ZERO spawns and ZERO recomputes (the
    // operator's own stated target metric). No cache.start() is ever
    // called in this suite (no timer), and the watcher is started with
    // NOTHING touched yet.
    // ================================================================
    const fxA = writeStubs(tmp, 'A'); useStubs(fxA);
    const cacheA = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    const watchA = stateWatch.startStateWatch({
      dirs: [watchDir],
      onTrigger: () => cacheA.refreshAll().catch(() => {}),
      waitMs: 150, maxWaitMs: 600,
    });
    ok('A1 watcher actually attached (no watchErrors on a real, existing dir)',
      watchA.stats.watchErrors.length === 0, JSON.stringify(watchA.stats.watchErrors));
    await new Promise((resolve) => setTimeout(resolve, 1500)); // idle window, well past the debounce
    ok('A2 idle window (no fs events) produces ZERO subprocess spawns', spawnCount(fxA.spawnLog) === 0,
      'spawns=' + spawnCount(fxA.spawnLog));
    ok('A3 idle window produces ZERO refreshAll triggers', watchA.stats.triggers === 0,
      'triggers=' + watchA.stats.triggers);
    ok('A4 every subcommand cache entry is still the unpopulated initial sentinel (no recompute happened)',
      SUBS.every((s) => cacheA.get(s).rc === null), JSON.stringify(SUBS.map((s) => cacheA.get(s).rc)));
    watchA.stop();

    // ================================================================
    // Scenario B — ONE real file change triggers EXACTLY one refresh
    // cycle (SUB_COUNT spawns total, one per subcommand), not zero and
    // not a storm.
    // ================================================================
    const fxB = writeStubs(tmp, 'B'); useStubs(fxB);
    const cacheB = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    const watchB = stateWatch.startStateWatch({
      dirs: [watchDir],
      onTrigger: () => cacheB.refreshAll().catch(() => {}),
      waitMs: 150, maxWaitMs: 600,
    });
    fs.writeFileSync(path.join(watchDir, 'change-1.txt'), 'x');
    const settledB = await waitSettled(cacheB, SUBS, SPAWN_WAIT_MS);
    ok('B1 a real file change triggers a refresh that settles within the debounce+spawn window', settledB,
      'spawns so far=' + spawnCount(fxB.spawnLog));
    ok('B2 exactly ONE refresh cycle ran (spawns == subcommand count, not a multiple)',
      spawnCount(fxB.spawnLog) === SUB_COUNT, 'spawns=' + spawnCount(fxB.spawnLog) + ' expected=' + SUB_COUNT);
    ok('B3 generated_at (derived_at) is populated on the pushed entry', !!cacheB.get('status').derived_at);
    watchB.stop();

    // ================================================================
    // Scenario C — a BURST of 20 rapid file changes (well within the
    // debounce window) collapses to exactly ONE refresh cycle — proves
    // spawns scale with CHANGE BURSTS, not with the number of individual
    // change events, and answers this task's "measure spawns per 20
    // events" requirement directly.
    // ================================================================
    const fxC = writeStubs(tmp, 'C'); useStubs(fxC);
    const cacheC = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    const watchC = stateWatch.startStateWatch({
      dirs: [watchDir],
      onTrigger: () => cacheC.refreshAll().catch(() => {}),
      waitMs: 300, maxWaitMs: 1500,
    });
    for (let i = 0; i < 20; i++) {
      fs.writeFileSync(path.join(watchDir, 'burst-' + i + '.txt'), String(i));
    }
    const settledC = await waitSettled(cacheC, SUBS, SPAWN_WAIT_MS);
    ok('C1 a 20-event burst settles into a refresh', settledC, 'spawns=' + spawnCount(fxC.spawnLog));
    ok('C2 20 rapid change events collapse to EXACTLY one refresh cycle (' + spawnCount(fxC.spawnLog) + ' spawns observed vs ' + SUB_COUNT + ' expected, would be ' + (20 * SUB_COUNT) + ' uncollapsed)',
      spawnCount(fxC.spawnLog) === SUB_COUNT);
    watchC.stop();

    // ================================================================
    // Scenario D — N CONCURRENT explicit refreshAll() calls (simulating N
    // concurrent triggers arriving at once) dedupe to AT MOST ONE
    // subprocess invocation per subcommand within the cycle (the
    // pre-existing single-flight guard, re-proven here as the property
    // this task's quality bar names explicitly).
    // ================================================================
    const fxD = writeStubs(tmp, 'D'); useStubs(fxD);
    const cacheD = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    const concurrent = [cacheD.refreshAll(), cacheD.refreshAll(), cacheD.refreshAll(), cacheD.refreshAll(), cacheD.refreshAll()];
    await Promise.all(concurrent);
    await waitSettled(cacheD, SUBS, SPAWN_WAIT_MS);
    ok('D1 5 concurrent refreshAll() calls produce exactly one cycle\'s worth of spawns (single-flight)',
      spawnCount(fxD.spawnLog) === SUB_COUNT, 'spawns=' + spawnCount(fxD.spawnLog) + ' expected=' + SUB_COUNT);
    ok('D2 the extra concurrent calls were counted as SKIPPED, not silently dropped or duplicated',
      cacheD.skippedCycles >= 1, 'skippedCycles=' + cacheD.skippedCycles);

    // ================================================================
    // Scenario E — a FAILED refresh serves last-good and does NOT trigger
    // a retry storm: after a failure, idle stays idle (zero further
    // spawns) until the NEXT real trigger.
    // ================================================================
    const fxE = writeStubs(tmp, 'E'); useStubs(fxE);
    const cacheE = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    await cacheE.refreshAll(); // establish a last-good baseline (status.data populated)
    await waitSettled(cacheE, SUBS, SPAWN_WAIT_MS);
    const goodData = cacheE.get('status').data;
    ok('E0 baseline refresh established last-good data', goodData && goodData.oracle === 'nl-status');
    const spawnsAfterBaseline = spawnCount(fxE.spawnLog);
    fs.writeFileSync(fxE.failSentinel, '1'); // status now fails on every subsequent invocation
    const watchE = stateWatch.startStateWatch({
      dirs: [watchDir],
      onTrigger: () => cacheE.refreshAll().catch(() => {}),
      waitMs: 150, maxWaitMs: 600,
    });
    // Wait for the WHOLE cycle (both lanes, all SUB_COUNT subcommands) to
    // settle again, not just 'status' (which runs first in its lane and
    // would otherwise report "done" while costs/backlog/needs-me/shipped/
    // health are still mid-flight — undercounting the cycle's spawns).
    const priorAllE = snapshotDerivedAt(cacheE, SUBS);
    fs.writeFileSync(path.join(watchDir, 'trigger-failure.txt'), 'x');
    await waitAllAdvanced(cacheE, SUBS, priorAllE, SPAWN_WAIT_MS);
    ok('E1 status rc is now non-zero (the simulated failure was observed)', cacheE.get('status').rc !== 0,
      'rc=' + cacheE.get('status').rc);
    ok('E2 status.data still holds the LAST-GOOD payload, not null/erased',
      cacheE.get('status').data && cacheE.get('status').data.oracle === 'nl-status');
    const spawnsAfterFailureCycle = spawnCount(fxE.spawnLog);
    ok('E2b one refresh cycle ran for the failure (baseline + one more cycle\'s worth)',
      spawnsAfterFailureCycle === spawnsAfterBaseline + SUB_COUNT,
      'baseline=' + spawnsAfterBaseline + ' after=' + spawnsAfterFailureCycle);
    await new Promise((resolve) => setTimeout(resolve, 2000)); // idle after the failure
    ok('E3 a failed refresh does NOT trigger a retry storm — spawn count stays flat while idle',
      spawnCount(fxE.spawnLog) === spawnsAfterFailureCycle,
      'after-failure=' + spawnsAfterFailureCycle + ' after-idle=' + spawnCount(fxE.spawnLog));
    watchE.stop();

    // ================================================================
    // Scenario F — generated_at ADVANCES on a push-triggered refresh
    // (proves freshness moves on real change, without waiting for the
    // 999999ms floor this suite pins every cache to).
    // ================================================================
    const fxF = writeStubs(tmp, 'F'); useStubs(fxF);
    const cacheF = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    const watchF = stateWatch.startStateWatch({
      dirs: [watchDir],
      onTrigger: () => cacheF.refreshAll().catch(() => {}),
      waitMs: 150, maxWaitMs: 600,
    });
    fs.writeFileSync(path.join(watchDir, 'f-change-1.txt'), 'x');
    // Wait for the FULL first cycle (all lanes) to settle before triggering
    // a second change — otherwise change-2's debounced trigger can land
    // while cycle 1 is still `_cycleInFlight`, and the single-flight guard
    // correctly (by design) SKIPS it rather than stacking a second cycle;
    // that's proven separately by scenario D, but here it would just make
    // 'status' never advance and this scenario would time out.
    const settledF1 = await waitSettled(cacheF, SUBS, SPAWN_WAIT_MS);
    ok('F0 the first push-triggered cycle settles fully before the second change is written', settledF1);
    const t1 = cacheF.get('status').derived_at;
    await new Promise((resolve) => setTimeout(resolve, 50)); // ensure a distinguishable ISO timestamp
    const priorAllF = snapshotDerivedAt(cacheF, SUBS);
    fs.writeFileSync(path.join(watchDir, 'f-change-2.txt'), 'x');
    await waitAllAdvanced(cacheF, SUBS, priorAllF, SPAWN_WAIT_MS);
    const t2 = cacheF.get('status').derived_at;
    ok('F1 generated_at is present after a push-triggered refresh', !!t1);
    ok('F2 generated_at ADVANCES on the next push-triggered refresh (Date.parse(t2) > Date.parse(t1))',
      Date.parse(t2) > Date.parse(t1), 't1=' + t1 + ' t2=' + t2);
    watchF.stop();

    // ================================================================
    // Scenario G — OBS_WATCH_DISABLED is honored (sandboxing kill switch,
    // mirrors AUDITOR_DISABLED).
    // ================================================================
    process.env.OBS_WATCH_DISABLED = '1';
    const watchG = stateWatch.startStateWatch({ dirs: [watchDir], onTrigger: () => {} });
    ok('G1 OBS_WATCH_DISABLED=1 returns a disabled handle', watchG.disabled === true);
    ok('G2 a disabled handle attaches NO watchers', watchG.watchedDirs.length === 0);
    watchG.stop(); // must not throw
    delete process.env.OBS_WATCH_DISABLED;

    // ================================================================
    // Scenario H — a MISSING directory never crashes the watcher; it is
    // recorded as a watch error and the server keeps running (same
    // best-effort discipline as every other reader in this codebase).
    // ================================================================
    const missingDir = path.join(tmp, 'does-not-exist', 'nested');
    let threwH = false;
    let watchH;
    try {
      watchH = stateWatch.startStateWatch({ dirs: [missingDir], onTrigger: () => {} });
    } catch (_) { threwH = true; }
    ok('H1 a missing watch directory does not throw', !threwH);
    ok('H2 the missing directory is recorded in stats.watchErrors', watchH && watchH.stats.watchErrors.length === 1,
      watchH ? JSON.stringify(watchH.stats.watchErrors) : 'no handle');
    if (watchH) watchH.stop();

    // ================================================================
    // Scenario I — env-var resolution: OBS_WATCH_DIRS fully overrides the
    // computed default list (test-sandboxing contract every other reader
    // in this codebase relies on).
    // ================================================================
    const dirX = path.join(tmp, 'envdir-x');
    const dirY = path.join(tmp, 'envdir-y');
    fs.mkdirSync(dirX, { recursive: true });
    fs.mkdirSync(dirY, { recursive: true });
    process.env.OBS_WATCH_DIRS = dirX + ',' + dirY;
    const resolved = stateWatch.resolveWatchDirs(() => tmp);
    ok('I1 OBS_WATCH_DIRS fully overrides the computed default list',
      resolved.length === 2 && resolved.indexOf(path.resolve(dirX)) !== -1 && resolved.indexOf(path.resolve(dirY)) !== -1,
      JSON.stringify(resolved));
    delete process.env.OBS_WATCH_DIRS;

    // Default computation sanity check: individual env-var overrides feed
    // defaultWatchDirs() the same way the real state readers resolve them.
    const savedHb = process.env.HEARTBEAT_STATE_DIR;
    process.env.HEARTBEAT_STATE_DIR = path.join(tmp, 'hb-override');
    const defaults = stateWatch.defaultWatchDirs(() => tmp);
    ok('I2 HEARTBEAT_STATE_DIR override is honored in the computed default list',
      defaults.indexOf(path.resolve(path.join(tmp, 'hb-override'))) !== -1, JSON.stringify(defaults));
    if (savedHb === undefined) delete process.env.HEARTBEAT_STATE_DIR; else process.env.HEARTBEAT_STATE_DIR = savedHb;

    // ================================================================
    // MEASUREMENT — subprocess spawns while idle vs while under sustained
    // real change, reported explicitly (this task's "measure before vs
    // after" requirement). See this task's report-back for the OLD
    // (pure-30s-timer) baseline, taken from the pre-fix code + the golden
    // case's own live measurement (45/93 processes) rather than re-run
    // here (a 30s+ real sleep is not worth spending in a self-test).
    // ================================================================
    console.log('');
    console.log('  MEASUREMENT: idle spawns over a 1.5s window with zero changes = 0 (scenario A)');
    console.log('  MEASUREMENT: 20 rapid change events -> ' + spawnCount(fxC.spawnLog) + ' spawns (one settled cycle), not ' + (20 * SUB_COUNT) + ' (uncollapsed)');
    console.log('  MEASUREMENT: 5 concurrent refreshAll() triggers -> ' + spawnCount(fxD.spawnLog) + ' spawns (one settled cycle), not ' + (5 * SUB_COUNT));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  console.log('');
  console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL: ' + (e && e.stack || e));
  process.exit(1);
});
