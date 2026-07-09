'use strict';
// server.selftest.js — sandboxed server unit self-test (specs-o §O.4
// "Self-test" clause). Uses an NL_BIN fixture stub (a bash script emulating
// `nl <sub> --json` for every subcommand) so this test asserts the WIRING
// (pane endpoint -> derive-cache -> nl invocation -> JSON response) without
// depending on the real estate. Also seeds a tree-state fixture reproducing
// a divergence so the reconciler's mismatch-flagging is exercised.
//
// Run: `node server/server.selftest.js`. Exit 0 PASS / 1 FAIL. Node stdlib
// + http requests only — no external test framework (matches the existing
// workstreams-ui *.selftest.js convention, e.g. web/responsive.selftest.js).

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const net = require('net');
const { spawn } = require('child_process');

let PASSED = 0, FAILED = 0;
function ok(name, cond, detail) {
  if (cond) { PASSED++; console.log('  PASS: ' + name); }
  else { FAILED++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
}

function httpGet(port, urlPath) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: port, path: urlPath }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) { /* left null */ }
        resolve({ status: res.statusCode, body: body, json: parsed });
      });
    }).on('error', reject);
  });
}

function httpPost(port, urlPath) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: port, path: urlPath, method: 'POST' }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(body); } catch (_) {}
        resolve({ status: res.statusCode, body: body, json: parsed });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'o4-server-st-'));

  // ---- Fixture NL_BIN stub: a bash script that answers every subcommand
  // this server calls with a fixed, schema-valid JSON payload, and lets
  // ONE subcommand (`why` for a magic session id, and `status` when a
  // sentinel file exists) simulate an rc!=0 failure so the error-path
  // (rc!=0 renders error, never empty) is exercised too.
  const stubPath = path.join(tmp, 'nl-stub.sh');
  const failSentinel = path.join(tmp, 'FAIL_STATUS');
  fs.writeFileSync(stubPath, [
    '#!/bin/bash',
    'set -u',
    'sub="${1:-}"; shift || true',
    'if [[ "$sub" == "status" ]] && [[ -f "' + failSentinel.replace(/\\/g, '/') + '" ]]; then',
    '  echo "simulated nl status failure" >&2',
    '  exit 3',
    'fi',
    // SLOW_SENTINEL: when present, `nl backlog --json` sleeps 4s before
    // answering — reproduces the real livesmoke bug (a slow subcommand
    // blocking the WHOLE server via spawnSync) so this self-test proves the
    // async spawn fix: the server must stay responsive to OTHER pane
    // requests while this one is still in flight.
    'if [[ "$sub" == "backlog" ]] && [[ -f "' + path.join(tmp, 'SLOW_SENTINEL').replace(/\\/g, '/') + '" ]]; then',
    '  sleep 4',
    'fi',
    'case "$sub" in',
    '  status)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"nl-status","sessions":[{"session_id":"sess-fixture","state":"working","branch":"main","worktree_root":"/x","marker_state":"none","detail":""}],"doctor":{"verdict":"[doctor] GREEN","ts":"2026-07-06T00:00:00Z","exit_code":"0"}}',
    'JSON',
    '    ;;',
    '  needs-me)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_needs_me","items":[{"id":"ny-fixture","created_at":"2026-07-06T00:00:00Z","updated_at":"2026-07-06T00:00:00Z","section":"question","text":"fixture question","links":[],"session":"sess-fixture","tier":null,"state":"open","resolved_at":null,"resolution_note":null}]}',
    'JSON',
    '    ;;',
    '  shipped)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_shipped_since","since":"2026-07-05T00:00:00Z","shas":[{"sha":"abc1234","subject":"fixture commit"}],"decisions":[],"failures":0}',
    'JSON',
    '    ;;',
    '  costs)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_costs","total":{"input_tokens":10,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"throttle_events":0,"est_minutes_lost":0,"truncated_to_recent":false,"sessions":[{"session_id":"sess-fixture","input_tokens":10,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"transcript_status":"fresh"}]}',
    'JSON',
    '    ;;',
    '  backlog)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_backlog_health","open_total":1,"terminal_total":0,"priority":{"high":0,"medium":1,"low":0,"unlabeled":0},"age":{"0_7d":1,"8_30d":0,"31_90d":0,"over_90d":0,"undated":0},"flow_7d":{"adds":1,"terminal":0,"terminal_undated":0},"tiers":{"high_days":7,"medium_days":30,"low_days":90}}',
    'JSON',
    '    ;;',
    '  why)',
    '    sid="${1:-}"',
    '    json_mode=0',
    '    for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done',
    '    if [[ "$sid" == "sess-024-fixture" ]]; then',
    '      if [[ "$json_mode" == "1" ]]; then',
    '        cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_why","session_id":"sess-024-fixture","transcript_status":"present","chain":[{"ts":"2026-07-06T00:00:00Z","gate":"workstreams-emit","event":"spawn-dispatched","detail":"branch=build/x"},{"ts":"2026-07-06T00:00:05Z","gate":"workstreams-state-gate","event":"block","detail":"no live node for branch"}]}',
    'JSON',
    '      else',
    // TEXT mode for the SAME fixture session — used by the Q6 verdict
    // fallback (O.4-fix1 item 3): the JSON branch above deliberately
    // omits "verdict" (reproducing the real lib gap) so runWhy() falls
    // back to shelling THIS text-mode branch and lifting the final
    // "verdict: ..." line, exactly as it would against the real
    // od_why (whose JSON mode has the same gap today).
    '        echo "2 event(s) for session sess-024-fixture (oracle: od_why, transcript: present)"',
    '        echo "2026-07-06T00:00:00Z  workstreams-emit  spawn-dispatched  branch=build/x"',
    '        echo "2026-07-06T00:00:05Z  workstreams-state-gate  block  no live node for branch"',
    '        echo "verdict: blocked by workstreams-state-gate (no live node for branch); next: none n/a"',
    '      fi',
    '    else',
    '      echo "od_why: session-id required" >&2',
    '      exit 1',
    '    fi',
    '    ;;',
    '  *)',
    '    echo "nl-stub: unknown subcommand $sub" >&2',
    '    exit 1',
    '    ;;',
    'esac',
  ].join('\n'));
  fs.chmodSync(stubPath, 0o755);

  // ---- Fixture derive-lib stub (O.4-fix1 item 1 regression lock): a
  // minimal bash "lib" exporting an od_harness_health function shaped like
  // the real hooks/lib/observability-derive.sh one, so runHealth()'s
  // `source <lib> && od_harness_health --json` shells out to THIS fixture
  // instead of the real estate's lib/doctor-cache/ledger. Asserts the
  // health pane surfaces .gates[] (the exact data the acceptance drill
  // found missing) without depending on real doctor-cache/ledger state.
  const deriveLibPath = path.join(tmp, 'derive-lib-stub.sh');
  fs.writeFileSync(deriveLibPath, [
    '#!/bin/bash',
    'od_harness_health() {',
    '  echo \'{"schema":1,"oracle":"od_harness_health","doctor":{"verdict":"[doctor] GREEN","ts":"2026-07-06T00:00:00Z","exit_code":"0"},"gates":[{"gate":"work-integrity-gate","block_7d":33,"waiver_7d":41,"downgrade_7d":6,"dominant":"waiver"},{"gate":"task-completed-evidence-gate","block_7d":10,"waiver_7d":5,"downgrade_7d":0,"dominant":"block"}]}\'',
    '}',
  ].join('\n'));
  fs.chmodSync(deriveLibPath, 0o755);

  process.env.NL_BIN = stubPath;
  process.env.NL_DERIVE_LIB = deriveLibPath;
  process.env.CTREE_PORT = '0'; // resolved below to an ephemeral port via a wrapper
  const PORT = 17733 + (process.pid % 1000); // deterministic-ish, avoids common collisions
  process.env.CTREE_PORT = String(PORT);
  process.env.OBS_REFRESH_MS = '999999'; // don't let the timer refire during the test

  delete require.cache[require.resolve('./derive-cache.js')];
  delete require.cache[require.resolve('./reconciler.js')];
  delete require.cache[require.resolve('./server.js')];
  const { server, cache } = require('./server.js');
  const derive = require('./derive-cache.js');

  // Wait for the initial refreshAll() (triggered by cache.start() in
  // server.js) to actually SETTLE every subcommand before running any
  // assertion — this is a POLL, not a fixed sleep, because the refresh
  // spawns are asynchronous (child_process.spawn, never spawnSync — see
  // derive-cache.js's header) and their real wall-clock time depends on
  // machine load, which is NOT deterministic (a fixed short sleep was
  // flaky on a loaded machine once `health` became a 6th concurrent
  // subcommand in the initial burst — S5/S5b intermittently saw
  // costs.json.data still null). A cache entry has settled once its `rc`
  // is no longer the initial `null` sentinel (see derive-cache.js's
  // DeriveCache constructor / server.js's isLoading()).
  const allSubs = Object.keys(derive.SUBCOMMANDS);
  const settleDeadline = Date.now() + 15000;
  while (Date.now() < settleDeadline) {
    if (allSubs.every((s) => cache.get(s).rc !== null)) break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  try {
    // ---- Scenario 1-6: each pane endpoint returns derived JSON from the stub.
    const status = await httpGet(PORT, '/api/pane/status');
    ok('S1 /api/pane/status returns rc=0 + fixture session', status.json && status.json.rc === 0 &&
      JSON.stringify(status.json.data).includes('sess-fixture'), JSON.stringify(status.json));

    const needsMe = await httpGet(PORT, '/api/pane/needs-me');
    ok('S2 /api/pane/needs-me returns fixture item', needsMe.json && needsMe.json.rc === 0 &&
      JSON.stringify(needsMe.json.data).includes('fixture question'));

    const shipped = await httpGet(PORT, '/api/pane/shipped');
    ok('S3 /api/pane/shipped returns fixture SHA', shipped.json && shipped.json.rc === 0 &&
      JSON.stringify(shipped.json.data).includes('abc1234'));

    const health = await httpGet(PORT, '/api/pane/health');
    ok('S4 /api/pane/health carries the doctor verdict', health.json && health.json.rc === 0 &&
      JSON.stringify(health.json.data).includes('GREEN'));
    ok('S4b /api/pane/health carries per-gate 7d block/waiver/downgrade counts (O.4-fix1 item 1 regression lock)',
      health.json && health.json.rc === 0 && Array.isArray(health.json.data.gates) &&
      health.json.data.gates.length === 2 &&
      health.json.data.gates[0].gate === 'work-integrity-gate' &&
      health.json.data.gates[0].block_7d === 33 && health.json.data.gates[0].waiver_7d === 41,
      JSON.stringify(health.json && health.json.data));
    ok('S4c waiver-dominant gate is flagged in the gate data (dominant field)',
      health.json && health.json.data.gates[0].dominant === 'waiver' &&
      health.json.data.gates[1].dominant === 'block');

    const costs = await httpGet(PORT, '/api/pane/costs');
    ok('S5 /api/pane/costs returns fixture totals', costs.json && costs.json.rc === 0 &&
      costs.json.data && costs.json.data.total && costs.json.data.total.input_tokens === 10);
    ok('S5b /api/pane/costs carries per-session rows (O.4-fix1 item 2 regression lock: was 0 rows vs a 10-session oracle)',
      costs.json && Array.isArray(costs.json.data.sessions) && costs.json.data.sessions.length === 1 &&
      costs.json.data.sessions[0].session_id === 'sess-fixture' && costs.json.data.sessions[0].transcript_status === 'fresh',
      JSON.stringify(costs.json && costs.json.data));

    const backlog = await httpGet(PORT, '/api/pane/backlog');
    ok('S6 /api/pane/backlog returns fixture counts', backlog.json && backlog.json.rc === 0 &&
      backlog.json.data && backlog.json.data.open_total === 1);

    // ---- Scenario 6b (regression lock — real bug found during O.4
    // livesmoke): a SLOW subcommand (nl backlog taking ~51s on the real
    // estate) must NOT block the server from answering OTHER pane requests
    // concurrently. The initial spawnSync-based implementation blocked the
    // entire Node event loop for the full duration of ANY refresh,
    // including server.listen()'s ability to accept connections — this
    // scenario seeds a 4s-sleeping backlog stub, triggers a refresh via
    // POST /api/refresh (fire-and-forget from this test's perspective), and
    // asserts /api/pane/status answers promptly WHILE the slow backlog
    // refresh is still in flight.
    fs.writeFileSync(path.join(tmp, 'SLOW_SENTINEL'), '1');
    const refreshStarted = Date.now();
    const refreshPromise = httpPost(PORT, '/api/refresh'); // will take >=4s to resolve
    await new Promise((resolve) => setTimeout(resolve, 500)); // let the slow refresh actually start
    const concurrentStart = Date.now();
    const concurrentStatus = await httpGet(PORT, '/api/pane/status');
    const concurrentElapsedMs = Date.now() - concurrentStart;
    ok('S6b server answers /api/pane/status in <2s while a 4s backlog refresh is in flight (async spawn, not spawnSync)',
      concurrentStatus.status === 200 && concurrentElapsedMs < 2000,
      'elapsed=' + concurrentElapsedMs + 'ms');
    await refreshPromise; // let the slow refresh finish before continuing
    fs.unlinkSync(path.join(tmp, 'SLOW_SENTINEL'));
    ok('S6c the slow refresh itself still completed successfully (not just abandoned)',
      Date.now() - refreshStarted >= 4000);

    // ---- Scenario 7: Q6 why-drawer, 024-class fixture causal chain.
    const why = await httpGet(PORT, '/api/pane/why?session=sess-024-fixture&last_block=1');
    ok('S7 /api/pane/why returns the 024-class causal chain', why.json && why.json.rc === 0 &&
      JSON.stringify(why.json.data).includes('spawn-dispatched') &&
      JSON.stringify(why.json.data).includes('workstreams-state-gate'));
    // O.4-fix1 item 3 regression lock: the JSON fixture branch (S7, above)
    // deliberately omits "verdict" (reproducing the real od_why --json
    // gap); runWhy() must fall back to the TEXT-mode fixture branch and
    // attach the lifted "verdict: ..." line onto data.verdict.
    ok('S7b /api/pane/why attaches a verdict line via the text-mode fallback when JSON omits one (O.4-fix1 item 3)',
      why.json && why.json.data && typeof why.json.data.verdict === 'string' &&
      /^verdict: blocked by workstreams-state-gate/.test(why.json.data.verdict),
      JSON.stringify(why.json && why.json.data));

    // ---- Scenario 8: Q6 with no ?session= is a clear 400, not a crash.
    const whyMissing = await httpGet(PORT, '/api/pane/why');
    ok('S8 /api/pane/why without ?session= is a clean 400', whyMissing.status === 400);

    // ---- Scenario 9: rc!=0 renders an ERROR payload, never an empty one.
    fs.writeFileSync(failSentinel, '1');
    await new Promise((resolve, reject) => {
      const req = http.request({ host: '127.0.0.1', port: PORT, path: '/api/refresh', method: 'POST' }, (res) => {
        res.on('data', () => {}); res.on('end', resolve);
      });
      req.on('error', reject); req.end();
    });
    const statusAfterFail = await httpGet(PORT, '/api/pane/status');
    ok('S9 rc!=0 pane response carries rc!=0 + stderr_tail (never silently empty)',
      statusAfterFail.json && statusAfterFail.json.rc !== 0 &&
      statusAfterFail.json.stderr_tail && statusAfterFail.json.stderr_tail.includes('simulated nl status failure'),
      JSON.stringify(statusAfterFail.json));
    ok('S9b rc!=0 pane response still carries the exact failing nl command line',
      statusAfterFail.json && statusAfterFail.json.command === 'nl status --json');
    fs.unlinkSync(failSentinel);

    // ---- Scenario 10: reconciler flags a seeded mismatch. We can't easily
    // inject a real tree-state file here (state.js resolves a real path),
    // so this asserts the reconciler MODULE directly (unit-level, still
    // exercising the real check() function server.js calls) with a fake
    // stateLib returning a snapshot with a ghost session claim absent from
    // the (stubbed) derived truth.
    const reconciler = require('./reconciler.js');
    const fakeStateLib = {
      readState: () => ({
        snapshot: {
          nodes: [
            { node_id: 'n1', title: 'ghost-branch', state: 'open', bound_sessions: ['sess-ghost-not-in-derived'] },
          ],
        },
      }),
    };
    let emittedGate = null, emittedEvent = null;
    const fakeEmit = (gate, event) => { emittedGate = gate; emittedEvent = event; return 'fake-event-id'; };
    const result = reconciler.check(fakeStateLib, cache, fakeEmit);
    ok('S10 reconciler flags a seeded ghost claim as drift', result.drift_count === 1 &&
      result.mismatches[0].session_id === 'sess-ghost-not-in-derived', JSON.stringify(result));
    ok('S10b reconciler emits a ledger warn on gate=cockpit-reconciler for the mismatch',
      emittedGate === 'cockpit-reconciler' && emittedEvent === 'warn');

    // ---- Scenario 11: reconciler quiet state when claims agree (0 drift).
    const cleanStateLib = { readState: () => ({ snapshot: { nodes: [] } }) };
    const resultClean = reconciler.check(cleanStateLib, cache, fakeEmit);
    ok('S11 reconciler reports 0 drift for an empty claim set (quiet state)', resultClean.drift_count === 0);

    // ---- Scenario 11b (O.4-fix1 item 5 regression lock — degradation
    // honesty): when the derived-truth oracle itself is unavailable (the
    // `status` cache entry's last refresh failed, rc!=0, with no
    // last-known-good session data), check() must report
    // oracle_unavailable:true and drift_count:null — NEVER a drift count
    // computed by diffing real tree claims against an empty derived set
    // (the real S8 bug: reported "drift: 9" during a simulated CLI
    // outage, which reads as 9 REAL drifted sessions instead of "unknown
    // right now"). Uses a fake cache (not the real one) so this is
    // independent of the live cache's current refresh state.
    const fakeCacheDown = { get: (sub) => (sub === 'status' ? { data: null, rc: 3, stderr_tail: 'simulated outage', derived_at: '2026-07-07T00:00:00Z' } : cache.get(sub)) };
    const resultDown = reconciler.check(fakeStateLib, fakeCacheDown, fakeEmit);
    ok('S11b reconciler reports oracle_unavailable (not a fabricated drift count) when the status oracle is down',
      resultDown.oracle_unavailable === true && resultDown.drift_count === null && resultDown.mismatches.length === 0,
      JSON.stringify(resultDown));

    // ---- Scenario 12: /api/reconciler endpoint responds (integration wiring).
    const reconEndpoint = await httpGet(PORT, '/api/reconciler');
    ok('S12 /api/reconciler endpoint returns a well-shaped badge payload',
      reconEndpoint.json && typeof reconEndpoint.json.drift_count === 'number' &&
      typeof reconEndpoint.json.checked_at === 'string');

    // ---- Scenario 13: retired write endpoint is GONE (404, not a
    // silently-accepting stub) — asserts the trust-path retirement of
    // POST /api/event actually removed the route rather than leaving it
    // reachable.
    const retiredEvent = await httpPost(PORT, '/api/event');
    ok('S13 POST /api/event (retired legacy write path) is gone (404)', retiredEvent.status === 404);

    // ---- Scenario 14: /api/health (global freshness) still answers.
    const healthGlobal = await httpGet(PORT, '/api/health');
    ok('S14 /api/health returns global freshness fields', healthGlobal.json && healthGlobal.json.ok === true &&
      'oldest_pane_age_ms' in healthGlobal.json);

    // ---- Scenario 15: docs browser kept (link-resolver backend).
    const docsListing = await httpGet(PORT, '/api/docs');
    ok('S15 /api/docs (kept as link-resolver backend) still responds ok:true or a clean error',
      docsListing.json && typeof docsListing.json.ok === 'boolean');

    // ---- Scenario 16 (O.4-fix1 item 6 regression lock — backlog pane
    // permanent rc=124): OBS_NL_TIMEOUT_MS_BACKLOG (per-subcommand
    // override) beats the global OBS_NL_TIMEOUT_MS, which beats backlog's
    // own 180s built-in default, which beats every other subcommand's 60s
    // default. The acceptance drill measured `nl backlog --json` at
    // 80-162s on the real estate vs the (then-global-only) 60s default,
    // so the backlog pane showed a permanent timeout error on every
    // refresh cycle — this asserts the override chain directly (unit
    // level; a real 180s-sleeping stub would make this test itself
    // impractically slow).
    delete require.cache[require.resolve('./derive-cache.js')];
    const dc2 = require('./derive-cache.js');
    ok('S16 backlog gets a higher built-in default (360s, comfortably above the measured ~258s) that beats the old fixed 60s causing permanent rc=124',
      dc2.timeoutMsFor('backlog') === 360000, 'got ' + dc2.timeoutMsFor('backlog'));
    // [39] (NL-FINDING-040/FM-037 incident review): the global default is
    // now 180s, NOT 60s — the incident measured `nl status --json` at 93s
    // SOLO and rc=124 at 150s under contention, so the old 60s default was
    // killing healthy-but-slow derivations on this estate and re-spawning
    // them every cycle (timeout-kill -> retry churn amplifying load).
    ok('S16b every other subcommand defaults to 180s ([39]: 60s killed healthy-but-slow derivations — 93s solo status measured)',
      dc2.timeoutMsFor('status') === 180000 && dc2.timeoutMsFor('costs') === 180000,
      'status=' + dc2.timeoutMsFor('status') + ' costs=' + dc2.timeoutMsFor('costs'));
    process.env.OBS_NL_TIMEOUT_MS = '90000';
    ok('S16c OBS_NL_TIMEOUT_MS (global override) applies to backlog too when set',
      dc2.timeoutMsFor('backlog') === 90000);
    process.env.OBS_NL_TIMEOUT_MS_BACKLOG = '240000';
    ok('S16d OBS_NL_TIMEOUT_MS_BACKLOG (per-subcommand override) beats the global override',
      dc2.timeoutMsFor('backlog') === 240000 && dc2.timeoutMsFor('status') === 90000);
    delete process.env.OBS_NL_TIMEOUT_MS;
    delete process.env.OBS_NL_TIMEOUT_MS_BACKLOG;

    // ---- Scenario 17 ([37], NL-FINDING-040/FM-037 regression lock —
    // refresh-cycle single-flight): when oracle latency exceeds the poll
    // interval, the timer must SKIP the tick, not start a new cycle on top
    // of the running one. The per-sub inFlight dedup already prevented
    // duplicate child processes per subcommand, but a piled-on cycle still
    // resolved immediately with stale entries and fired _notify() — a
    // spurious SSE refresh broadcast per tick, every 30s, forever, on every
    // one of the N instances at the incident. Asserts: (a) a second
    // refreshAll while the first is in flight is counted as skipped, (b) a
    // skipped cycle never notifies listeners, (c) after the cycle settles
    // the next refreshAll runs normally.
    const slowAllStub = path.join(tmp, 'nl-slow-all-stub.sh');
    fs.writeFileSync(slowAllStub, [
      '#!/bin/bash',
      'sleep 1.5',
      'echo "{}"',
    ].join('\n'));
    fs.chmodSync(slowAllStub, 0o755);
    const prevNlBin = process.env.NL_BIN;
    process.env.NL_BIN = slowAllStub;
    delete require.cache[require.resolve('./derive-cache.js')];
    const dc3 = require('./derive-cache.js');
    const c3 = new dc3.DeriveCache({});
    let notifyCount = 0;
    c3.onRefresh(() => { notifyCount++; });
    const firstCycle = c3.refreshAll();
    const secondCycle = c3.refreshAll(); // fired while the first is mid-flight (stub sleeps 1.5s)
    ok('S17 refreshAll while a cycle is in flight is SKIPPED and counted ([37] single-flight guard)',
      c3.skippedCycles === 1, 'skippedCycles=' + c3.skippedCycles);
    await secondCycle;
    ok('S17b a skipped cycle never notifies listeners (no spurious SSE refresh from stale entries)',
      notifyCount === 0, 'notifyCount=' + notifyCount);
    await firstCycle;
    ok('S17c the real cycle still completes and notifies exactly once', notifyCount === 1,
      'notifyCount=' + notifyCount);
    await c3.refreshAll();
    ok('S17d the next cycle after settlement runs normally (not skipped)',
      c3.skippedCycles === 1 && notifyCount === 2,
      'skippedCycles=' + c3.skippedCycles + ' notifyCount=' + notifyCount);
    process.env.NL_BIN = prevNlBin;

    // ---- Scenario 18 ([55], NL-FINDING-040/FM-037 regression lock —
    // single-instance guard): at the 2026-07-08 incident, 15+ worktree-
    // launched server instances EACH started the 30s nl.sh polling loop
    // unconditionally BEFORE listen(), then crashed (or worse, kept
    // polling) on EADDRINUSE — N independent poll loops amplifying oracle
    // load ~Nx. The listen success is now the mutex: a second instance on
    // an occupied port must exit 0 cleanly, log one line, and NEVER spawn
    // a single nl child. The nl stub for the child writes a marker file on
    // ANY invocation; its absence is the no-poll proof.
    const blocker = net.createServer();
    await new Promise((resolve) => blocker.listen(0, '127.0.0.1', resolve));
    const busyPort = blocker.address().port;
    const pollMarker = path.join(tmp, 'SECOND_INSTANCE_POLLED');
    const markerStub = path.join(tmp, 'nl-marker-stub.sh');
    fs.writeFileSync(markerStub, [
      '#!/bin/bash',
      'echo polled > "' + pollMarker.replace(/\\/g, '/') + '"',
      'echo "{}"',
    ].join('\n'));
    fs.chmodSync(markerStub, 0o755);
    const childEnv = Object.assign({}, process.env, {
      CTREE_PORT: String(busyPort),
      NL_BIN: markerStub,
      OBS_REFRESH_MS: '999999',
    });
    const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], { env: childEnv });
    let childOut = '';
    child.stdout.on('data', (d) => { childOut += d; });
    child.stderr.on('data', (d) => { childOut += d; });
    const childExit = await new Promise((resolve) => {
      const killer = setTimeout(() => { try { child.kill(); } catch (_) {} resolve('timeout-killed'); }, 10000);
      child.on('exit', (code) => { clearTimeout(killer); resolve(code); });
    });
    // Give any (buggy, pre-listen) poll spawn time to land its marker —
    // the bash stub outlives the node child, so a short settle window
    // keeps this assertion honest rather than racing the stub's write.
    await new Promise((resolve) => setTimeout(resolve, 750));
    ok('S18 second instance on an occupied port exits 0 ([55] single-instance guard)',
      childExit === 0, 'exit=' + childExit + ' out=' + childOut.slice(0, 300).replace(/\n/g, ' | '));
    ok('S18b second instance logs the one-line guard message', childOut.includes('single-instance guard'),
      childOut.slice(0, 300).replace(/\n/g, ' | '));
    ok('S18c second instance NEVER starts the poll loop (no nl spawn side-effect marker)',
      !fs.existsSync(pollMarker));
    await new Promise((resolve) => blocker.close(resolve));

  } finally {
    server.close();
    cache.stop();
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  }

  console.log('');
  console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('self-test crashed:', err);
  process.exit(1);
});
