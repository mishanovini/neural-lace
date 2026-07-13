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
const { spawn, spawnSync } = require('child_process');
const payloadSchema = require('./payload-schema.js');
const projects = require('../config/projects.js');

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

function httpPostJson(port, urlPath, obj) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(obj || {});
    const req = http.request({
      host: '127.0.0.1', port: port, path: urlPath, method: 'POST',
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

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'o4-server-st-'));
  // Hoisted (not `const` inside the try block below) so the `finally`
  // block's cleanup can see it regardless of where inside `try` it's
  // assigned — see the Task 11 ask-rooted-workstreams fixture section.
  let planAbsPath;

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
  // Task 12 — the background auditor auto-starts (immediate cycle + a
  // cadence timer) the moment server.js's 'listening' callback fires, which
  // happens WELL BEFORE this test's own ask-fixture section (below) gets a
  // chance to point PROGRESS_LOG_STATE_DIR/ASK_REGISTRY_STATE_DIR/etc at
  // this test's sandbox. Without this gate, requiring server.js here would
  // fire a REAL auditor cycle against production ~/.claude/state and real
  // git repos (self-test pollution, constraint 4) before any sandboxing is
  // in place. Scenario 28 below re-enables it via a direct, manual
  // `auditor.runCycle()` call once every env var is safely sandboxed.
  process.env.AUDITOR_DISABLED = '1';

  delete require.cache[require.resolve('./derive-cache.js')];
  delete require.cache[require.resolve('./reconciler.js')];
  delete require.cache[require.resolve('./auditor.js')];
  delete require.cache[require.resolve('./server.js')];
  const { server, cache, auditor } = require('./server.js');
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
      health.json && health.json.data && Array.isArray(health.json.data.gates) &&
      health.json.data.gates[0] && health.json.data.gates[0].dominant === 'waiver' &&
      health.json.data.gates[1] && health.json.data.gates[1].dominant === 'block');

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

    // ---- Scenario 19 (2026-07-09 cockpit-lobotomy regression lock, part
    // 1 — bash by bare name): bashBin() must honor the NL_BASH override,
    // then probe the two standard Git-for-Windows locations IN ORDER, then
    // fall back to bare 'bash'. A bare-'bash' spawn under the logon
    // scheduled task's minimal registry env (PATH has Git\cmd only, no
    // bash.exe dir) failed rc=127 ENOENT for every pane, all day.
    const prevNlBash = process.env.NL_BASH;
    process.env.NL_BASH = '/custom/override/bash';
    ok('S19 bashBin() honors the NL_BASH env override', dc3.bashBin() === '/custom/override/bash',
      'got ' + dc3.bashBin());
    delete process.env.NL_BASH;
    const gitBash = 'C:\\Program Files\\Git\\bin\\bash.exe';
    const gitUsrBash = 'C:\\Program Files\\Git\\usr\\bin\\bash.exe';
    const expectedProbe = fs.existsSync(gitBash) ? gitBash
      : (fs.existsSync(gitUsrBash) ? gitUsrBash : 'bash');
    ok('S19b bashBin() probe order: Git\\bin, then Git\\usr\\bin, then bare bash fallback',
      dc3.bashBin() === expectedProbe, 'got ' + dc3.bashBin() + ' expected ' + expectedProbe);
    ok('S19c bashBin() without override resolves an absolute existing bash or the literal fallback',
      dc3.bashBin() === 'bash' || (path.isAbsolute(dc3.bashBin()) && fs.existsSync(dc3.bashBin())),
      'got ' + dc3.bashBin());
    if (prevNlBash !== undefined) process.env.NL_BASH = prevNlBash;

    // ---- Scenario 20 (2026-07-09 lobotomy regression lock, part 2 — the
    // /api/health flag the launcher keys restart-on-lobotomy off).
    // isLobotomized is the REAL exported function the /api/health handler
    // calls, exercised with fabricated cache states + uptimes (a live
    // >120s-uptime all-panes-failed server can't be produced inside this
    // test's time budget).
    const { isLobotomized } = require('./server.js');
    const allFail = { get: () => ({ data: null, rc: 127, stderr_tail: 'spawn bash ENOENT', derived_at: '2026-07-09T00:00:00Z' }) };
    const oneOk = { get: (s) => (s === 'costs'
      ? { data: {}, rc: 0, stderr_tail: '', derived_at: '2026-07-09T00:00:00Z' }
      : { data: null, rc: 127, stderr_tail: 'spawn bash ENOENT', derived_at: '2026-07-09T00:00:00Z' }) };
    const neverSettled = { get: () => ({ data: null, rc: null, stderr_tail: '', derived_at: null }) };
    ok('S20 lobotomized: EVERY pane failed + uptime past the 120s grace -> true (the incident shape)',
      isLobotomized(allFail, 120001) === true);
    ok('S20b lobotomized: every pane failed but uptime <= 120s -> false (fresh-instance grace = the no-restart-loop bound)',
      isLobotomized(allFail, 120000) === false && isLobotomized(allFail, 30000) === false);
    ok('S20c lobotomized: one healthy pane -> false even at high uptime',
      isLobotomized(oneOk, 600000) === false);
    ok('S20d lobotomized: rc=null (never settled) is loading, not failure -> false',
      isLobotomized(neverSettled, 600000) === false);
    const healthGlobal2 = await httpGet(PORT, '/api/health');
    ok('S20e /api/health carries server_uptime_ms + lobotomized (false on this healthy fixture server)',
      healthGlobal2.json && typeof healthGlobal2.json.server_uptime_ms === 'number' &&
      healthGlobal2.json.server_uptime_ms >= 0 && healthGlobal2.json.lobotomized === false,
      JSON.stringify(healthGlobal2.json));

    // ---- Scenario 21 (2026-07-09 lobotomy regression lock, part 3 — the
    // discarded-stderr hour): a child that exits 0 with unparseable/empty
    // stdout but a REAL error on stderr (the exact minimal-env shape:
    // profile-less bash, jq missing -> empty stdout + 'command not found'
    // on stderr) must surface that stderr in the pane entry instead of
    // discarding it.
    const garbageStub = path.join(tmp, 'nl-garbage-stub.sh');
    fs.writeFileSync(garbageStub, [
      '#!/bin/bash',
      'echo "jq: command not found (fixture)" >&2',
      'exit 0',
    ].join('\n'));
    fs.chmodSync(garbageStub, 0o755);
    process.env.NL_BIN = garbageStub;
    delete require.cache[require.resolve('./derive-cache.js')];
    const dc4 = require('./derive-cache.js');
    const c4 = new dc4.DeriveCache({});
    const parseFailEntry = await c4.refreshOne('status');
    ok('S21 parse-failure entry (rc=1 synthetic) carries the child\'s REAL stderr, never discards it',
      parseFailEntry.rc === 1 && parseFailEntry.stderr_tail.includes('jq: command not found (fixture)'),
      JSON.stringify(parseFailEntry));
    ok('S21b parse-failure entry still names the non-JSON symptom alongside the child stderr',
      parseFailEntry.stderr_tail.includes('produced non-JSON output'));
    process.env.NL_BIN = prevNlBin;

    // ---- Scenario 22 (2026-07-09 environment-independence smoke — THE
    // incident shape, end to end): a CHILD node process with a STRIPPED
    // environment (registry-minimal PATH with no bash dir, HOME absent —
    // exactly what the logon scheduled task hands the server) must still
    // complete runNl('status') with rc=0 and parseable JSON, because
    // bashBin() resolves bash by ABSOLUTE path (PATH-independent) and '-l'
    // (login shell) rebuilds the full user environment from the profile,
    // while spawnEnv() fills HOME from USERPROFILE.
    const smokeChild = path.join(tmp, 'minimal-env-smoke.js');
    fs.writeFileSync(smokeChild, [
      'const dc = require(' + JSON.stringify(path.join(__dirname, 'derive-cache.js')) + ');',
      "dc.runNl('status').then((r) => {",
      '  let parsed = null;',
      '  try { parsed = JSON.parse(r.stdout); } catch (_) {}',
      "  console.log(JSON.stringify({ rc: r.rc, parsed_ok: !!parsed, bash: dc.bashBin(), stderr: String(r.stderr).slice(0, 200) }));",
      '  process.exit(r.rc === 0 && parsed ? 0 : 1);',
      '});',
    ].join('\n'));
    const minimalEnv = process.platform === 'win32'
      ? {
          PATH: 'C:\\Windows\\System32;C:\\Windows', // registry-minimal: NO bash dir, NO ~/bin
          SystemRoot: process.env.SystemRoot || 'C:\\Windows',
          USERPROFILE: process.env.USERPROFILE,      // HOME deliberately ABSENT -> spawnEnv fallback path
          NL_BIN: stubPath,
        }
      : { PATH: '/usr/bin:/bin', HOME: process.env.HOME, NL_BIN: stubPath };
    const smokeResult = await new Promise((resolve) => {
      const ch = spawn(process.execPath, [smokeChild], { env: minimalEnv });
      let out = '', errOut = '';
      ch.stdout.on('data', (d) => { out += d; });
      ch.stderr.on('data', (d) => { errOut += d; });
      const killer = setTimeout(() => { try { ch.kill(); } catch (_) {} resolve({ code: 'timeout', out: out, errOut: errOut }); }, 30000);
      ch.on('exit', (code) => { clearTimeout(killer); resolve({ code: code, out: out, errOut: errOut }); });
    });
    ok('S22 runNl succeeds (rc=0, JSON parsed) from a child with the registry-minimal logon-task env (absolute bash + login-shell rebuild + HOME fallback)',
      smokeResult.code === 0,
      'exit=' + smokeResult.code + ' out=' + String(smokeResult.out).slice(0, 300).replace(/\n/g, ' | ') +
      ' err=' + String(smokeResult.errOut).slice(0, 200).replace(/\n/g, ' | '));
    console.log('  S22 smoke evidence: ' + String(smokeResult.out).trim());

    // ========================================================
    // Ask-rooted-workstreams-p1 Task 11 — "Server read surface" scenarios
    // (S23+). Sandboxed under this test's own `tmp` dir via the SAME
    // env-var overrides the shell writer libs use (PROGRESS_LOG_STATE_DIR /
    // ASK_REGISTRY_STATE_DIR / NEEDS_YOU_MD_PATH / DISPATCH_PROVENANCE_STATE_DIR
    // / HEARTBEAT_STATE_DIR) — constraint 4 sandboxing, never the real
    // machine state.
    // ========================================================
    const askTmp = path.join(tmp, 'ask-p1');
    const plStateDir = path.join(askTmp, 'progress-logs');
    const arStateDir = path.join(askTmp, 'ar-state');
    const dpStateDir = path.join(askTmp, 'dispatch-provenance');
    const hbStateDir = path.join(askTmp, 'heartbeats');
    const nyStateDir = path.join(askTmp, 'ny-state');
    const nyMdPath = path.join(askTmp, 'NEEDS-YOU.md');
    const fixtureRepoDir = path.join(askTmp, 'fixture-repo');
    fs.mkdirSync(plStateDir, { recursive: true });
    fs.mkdirSync(arStateDir, { recursive: true });
    fs.mkdirSync(dpStateDir, { recursive: true });
    fs.mkdirSync(hbStateDir, { recursive: true });
    fs.mkdirSync(nyStateDir, { recursive: true });
    fs.mkdirSync(path.join(fixtureRepoDir, 'docs', 'plans'), { recursive: true });

    process.env.PROGRESS_LOG_STATE_DIR = plStateDir;
    process.env.ASK_REGISTRY_STATE_DIR = arStateDir;
    process.env.DISPATCH_PROVENANCE_STATE_DIR = dpStateDir;
    process.env.HEARTBEAT_STATE_DIR = hbStateDir;
    process.env.NEEDS_YOU_MD_PATH = nyMdPath;
    // Task 12 auditor's operator-todo.md path — sandboxed for the SAME
    // reason NEEDS_YOU_MD_PATH is above: without this, a manual
    // auditor.runCycle() call (Scenario 28 below) would fall back to
    // `mainRepoRoot()`'s real self-repo root and could read/rewrite a REAL
    // docs/operator-todo.md if one exists on disk (self-test pollution).
    const operatorTodoPath = path.join(askTmp, 'operator-todo.md');
    process.env.OPERATOR_TODO_PATH = operatorTodoPath;

    // ---- fixture plan file (ground truth for plan_progress derivation).
    // Deliberately placed under the REAL self-repo root (config/projects.js's
    // stable `neural-lace` alias — projects.selfRepoRoot()), NOT the
    // sandboxed temp dir: this is the ONLY way to exercise plan_doc's
    // {project, path} resolution positively (it resolves through the REAL
    // projects.js map, which only knows registered project roots — an
    // arbitrary temp dir is correctly unresolvable, per that function's own
    // documented behavior). Cleaned up in the `finally` block below since it
    // lives outside `tmp`.
    const planRepoRoot = projects.selfRepoRoot();
    const fixtureSlug = 'selftest-task11-fixture-plan';
    planAbsPath = path.join(planRepoRoot, 'docs', 'plans', fixtureSlug + '.md');
    fs.writeFileSync(planAbsPath, [
      '# Plan: Fixture',
      '',
      '- [x] 1. Task one done.',
      '- [ ] 2. Task two dispatched, not yet done (in-flight).',
      '- [ ] 3. Task three not started.',
      '',
    ].join('\n'));

    // ---- fixture ask-registry.jsonl (raw lines per the documented FOLD
    // CONTRACT: ask-fix-1 active w/ a linked plan; ask-fix-2 completed
    // (done); ask-fix-3 active planless (defect-form waiting item);
    // ask-fix-4 active planless (lifecycle endpoint round-trip)).
    function regLine(fields) {
      return JSON.stringify(Object.assign({
        ask_id: '', record_type: '', ts: '', user: 't', machine: 'm', repo: '', project: '',
        summary: '', verbatim_ref: '', origin_session: '', status: '', plan_slug: '',
        session_id: '', resumed_from: '', merged_into: '', emitter: 'ask-registry',
      }, fields));
    }
    const registryLines = [
      regLine({ ask_id: 'ask-fix-1', record_type: 'created', ts: '2026-07-01T00:00:00Z', repo: planRepoRoot, project: 'demo-project', summary: 'Fixture ask one', origin_session: 'sess-orig-1', status: 'active' }),
      regLine({ ask_id: 'ask-fix-1', record_type: 'plan_linked', ts: '2026-07-01T00:01:00Z', plan_slug: fixtureSlug }),
      regLine({ ask_id: 'ask-fix-2', record_type: 'created', ts: '2026-07-02T00:00:00Z', project: 'demo-project', summary: 'Fixture ask two (completed)', status: 'active' }),
      regLine({ ask_id: 'ask-fix-2', record_type: 'status_change', ts: '2026-07-03T00:00:00Z', status: 'done', emitter: 'auditor' }),
      regLine({ ask_id: 'ask-fix-3', record_type: 'created', ts: '2026-07-01T05:00:00Z', project: 'other-project', summary: 'Fixture ask three', status: 'active' }),
      regLine({ ask_id: 'ask-fix-4', record_type: 'created', ts: '2026-07-01T06:00:00Z', project: 'demo-project', summary: 'Fixture ask four (lifecycle)', status: 'active' }),
    ].join('\n') + '\n';
    fs.writeFileSync(path.join(arStateDir, 'ask-registry.jsonl'), registryLines);

    // ---- fixture NEEDS-YOU.md via the REAL needs-you.sh (Integration
    // point: "parser fixture pinned against needs-you.sh --self-test
    // output, not a hand-written sample" — this is that same real render
    // path, not a hand-typed markdown sample). Uses derive-cache.js's
    // bashBin() (absolute-path bash, not a bare 'bash' spawn) for the same
    // minimal-env robustness every other child spawn in this file relies on.
    const needsYouSh = path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'needs-you.sh');
    let goodNeedsYouId = '', badNeedsYouId = '';
    if (fs.existsSync(needsYouSh)) {
      const dcForNy = require('./derive-cache.js');
      const nyBash = dcForNy.bashBin();
      const nyEnv = Object.assign({}, process.env, { NEEDS_YOU_STATE_DIR: nyStateDir, NEEDS_YOU_MD_PATH: nyMdPath });
      const goodText = 'Ship the fixture tonight?\nThe fixture (docs/plans/demo-plan-fixture.md) has been green for 3 days; shipping now vs later only changes who is on call.\nMy pick: ship tonight.';
      const goodRes = spawnSync(nyBash, [needsYouSh, 'add', '--section', 'decision', '--text', goodText, '--session', 'sess-orig-1', '--link', 'https://example.test/pr/1'], { env: nyEnv, encoding: 'utf8' });
      goodNeedsYouId = String(goodRes.stdout || '').trim();
      const badRes = spawnSync(nyBash, [needsYouSh, 'add', '--section', 'decision', '--text', 'x', '--session', 'sess-orig-1'], { env: nyEnv, encoding: 'utf8' });
      badNeedsYouId = String(badRes.stdout || '').trim();
    }
    ok('S22b (setup) needs-you.sh fixture produced a good and a bad NY- id via the REAL script',
      /^NY-/.test(goodNeedsYouId) && /^NY-/.test(badNeedsYouId) && goodNeedsYouId !== badNeedsYouId,
      'good=' + goodNeedsYouId + ' bad=' + badNeedsYouId);

    // ---- fixture progress-log events for ask-fix-1 ----
    function mkEvent(overrides) {
      return JSON.stringify(Object.assign({
        v: 1, event_id: 'ev-' + Math.random().toString(36).slice(2), ts: '2026-07-01T00:00:00Z',
        ask_id: 'ask-fix-1', type: '', plan_slug: '', task_id: '', sha: '', needs_you_id: '',
        session_id: '', summary: '', evidence_link: '', emitter: 'plan-lifecycle', provenance: 'known',
        user: 't', machine: 'm', repo: fixtureRepoDir,
      }, overrides));
    }
    const ask1Events = [
      mkEvent({ type: 'task_started', plan_slug: fixtureSlug, task_id: '1', session_id: 'sess-orch-1', summary: 'task 1 dispatched', ts: '2026-07-01T00:05:00Z' }),
      mkEvent({ type: 'task_done', plan_slug: fixtureSlug, task_id: '1', sha: 'abc1234', evidence_link: planAbsPath, summary: 'task 1 verified done', ts: '2026-07-01T00:10:00Z' }),
      mkEvent({ type: 'task_started', plan_slug: fixtureSlug, task_id: '2', session_id: 'sess-orch-1', summary: 'task 2 dispatched', ts: '2026-07-01T00:11:00Z' }),
      mkEvent({ type: 'waiting_on_operator', needs_you_id: goodNeedsYouId, session_id: 'sess-orig-1', ts: '2026-07-01T00:12:00Z' }),
      mkEvent({ type: 'waiting_on_operator', needs_you_id: badNeedsYouId, session_id: 'sess-orig-1', ts: '2026-07-01T00:13:00Z' }),
      mkEvent({ type: 'waiting_on_operator', needs_you_id: 'NY-does-not-exist-at-all', session_id: 'sess-orig-1', ts: '2026-07-01T00:14:00Z' }),
      mkEvent({ type: 'merged', sha: 'def5678', evidence_link: planAbsPath, ts: '2026-07-01T00:15:00Z' }),
    ].join('\n') + '\n';
    fs.writeFileSync(path.join(plStateDir, 'ask-fix-1.jsonl'), ask1Events);

    // ---- fixture dispatch-provenance marker (lineage edge: sess-orch-1 -> sess-child-2) ----
    fs.writeFileSync(path.join(dpStateDir, 'fixture-marker__1.json'), JSON.stringify({
      v: 1, ts: '2026-07-01T00:05:00Z', ask_id: 'ask-fix-1', plan_slug: fixtureSlug,
      task_id: '2', session_id: 'sess-orch-1', child_id: 'sess-child-2', worktree_path: '',
    }));

    // ---- fixture heartbeat (sess-orig-1 fresh -> should classify live) ----
    fs.writeFileSync(path.join(hbStateDir, 'sess-orig-1.json'), JSON.stringify({
      schema: 1, session_id: 'sess-orig-1', pid: process.pid, cwd: fixtureRepoDir, repo_root: fixtureRepoDir,
      worktree_root: fixtureRepoDir, branch: 'main', model: 'sonnet',
      last_activity_ts: new Date().toISOString(), last_event: 'turn-end', marker_state: 'none',
    }));

    // ---- Scenario 23: GET /api/asks default (status:active) groups by
    // project, newest activity first, plan_progress derived from the real
    // fixture plan file + this ask's own task_started/task_done events.
    const landing = await httpGet(PORT, '/api/asks');
    ok('S23 /api/asks returns ok:true with status_filter=active by default',
      landing.json && landing.json.ok === true && landing.json.status_filter === 'active',
      JSON.stringify(landing.json && landing.json.status_filter));
    const demoGroup = landing.json && (landing.json.groups || []).find((g) => g.project === 'demo-project');
    ok('S23b landing groups by project (demo-project present)', !!demoGroup, JSON.stringify(landing.json && landing.json.groups));
    const card1 = demoGroup && demoGroup.asks.find((a) => a.ask_id === 'ask-fix-1');
    ok('S23c ask-fix-1 card present under demo-project', !!card1);
    ok('S23d plan_progress derived from the fixture plan file + events (1 done, 1 in-flight, 1 not-started, total 3)',
      card1 && card1.plan_progress && card1.plan_progress.done === 1 && card1.plan_progress.in_flight === 1 &&
      card1.plan_progress.not_started === 1 && card1.plan_progress.total === 3,
      JSON.stringify(card1 && card1.plan_progress));
    ok('S23e ask-fix-4 (planless, active) also present under demo-project', !!(demoGroup && demoGroup.asks.find((a) => a.ask_id === 'ask-fix-4')));
    ok('S23f ask-fix-2 (status:done) is NOT in the active demo-project group', !(demoGroup && demoGroup.asks.find((a) => a.ask_id === 'ask-fix-2')));
    ok('S23g waiting_count counts only OPEN needs-you entries (good+bad-but-open=2; the unresolvable id is not counted)',
      card1 && card1.waiting_count === 2, JSON.stringify(card1 && card1.waiting_count));

    // ---- Scenario 24: completed group always present, independent of filter.
    ok('S24 completed group carries ask-fix-2 (done) with a count + newest_completed_ts',
      landing.json && landing.json.completed && landing.json.completed.count >= 1 &&
      landing.json.completed.asks.some((a) => a.ask_id === 'ask-fix-2') &&
      typeof landing.json.completed.newest_completed_ts === 'string',
      JSON.stringify(landing.json && landing.json.completed));

    // ---- Scenario 24b: ?status=done filters the main groups to done asks
    // (a real filter, not just the always-on completed group).
    const landingDone = await httpGet(PORT, '/api/asks?status=done');
    const doneGroupAsks = ((landingDone.json && landingDone.json.groups) || []).reduce((acc, g) => acc.concat(g.asks), []);
    ok('S24b ?status=done groups contain ask-fix-2 and status_filter echoes back',
      landingDone.json && landingDone.json.status_filter === 'done' && doneGroupAsks.some((a) => a.ask_id === 'ask-fix-2'),
      JSON.stringify(landingDone.json && landingDone.json.status_filter));

    // ---- Scenario 25: GET /api/ask/<id> full detail — chronological
    // narrative, plan_rows matching the fixture plan file's real
    // checkboxes, a REAL §3 waiting item, the never-terminal defect form
    // for a thin/unresolvable needs_you_id, artifacts from the merged
    // event, and sessions/lineage.
    const detail = await httpGet(PORT, '/api/ask/ask-fix-1');
    ok('S25 /api/ask/ask-fix-1 returns ok:true', detail.json && detail.json.ok === true, JSON.stringify(detail.json));
    ok('S25b narrative is chronological (task 1 dispatched before task 1 verified done)',
      detail.json && detail.json.narrative && detail.json.narrative.length >= 2 &&
      detail.json.narrative[0].summary === 'task 1 dispatched' && detail.json.narrative[1].summary === 'task 1 verified done',
      JSON.stringify(detail.json && detail.json.narrative));
    const planRow1 = detail.json && detail.json.plan_rows && detail.json.plan_rows.find((r) => r.plan_slug === fixtureSlug);
    ok('S25c plan_rows carries per-task done/in_flight rows matching the real plan file (3 tasks)',
      planRow1 && planRow1.tasks.length === 3 &&
      planRow1.tasks[0].done === true && planRow1.tasks[1].in_flight === true && planRow1.tasks[2].done === false && !planRow1.tasks[2].in_flight,
      JSON.stringify(planRow1));
    ok('S25d plan_doc resolves a REAL {project, path} pair through the EXISTING projects.js resolver (no new link handling)',
      planRow1 && planRow1.plan_doc && typeof planRow1.plan_doc.project === 'string' && planRow1.plan_doc.path === 'docs/plans/' + fixtureSlug + '.md',
      JSON.stringify(planRow1 && planRow1.plan_doc));
    const goodWaiting = detail.json && detail.json.waiting_items && detail.json.waiting_items.find((w) => w.needs_you_id === goodNeedsYouId);
    ok('S25e a well-formed §3 decision resolves to a real context block (defect:false, title/body/links present)',
      goodWaiting && goodWaiting.defect === false && /Ship the fixture tonight/.test(goodWaiting.title) &&
      goodWaiting.links.length === 1 && goodWaiting.body.length > 0,
      JSON.stringify(goodWaiting));
    const badWaiting = detail.json && detail.json.waiting_items && detail.json.waiting_items.find((w) => w.needs_you_id === badNeedsYouId);
    ok('S25f a thin (bare) decision entry renders the NEVER-TERMINAL defect form (defect:true, violation message, absolute raw_link, session id) — never a bare id',
      badWaiting && badWaiting.defect === true && /context missing/.test(badWaiting.message) &&
      payloadSchema.isAbsoluteHref(badWaiting.raw_link) && badWaiting.session_id === 'sess-orig-1',
      JSON.stringify(badWaiting));
    const missingWaiting = detail.json && detail.json.waiting_items && detail.json.waiting_items.find((w) => w.needs_you_id === 'NY-does-not-exist-at-all');
    ok('S25g an unresolvable needs_you_id ALSO renders the defect form (never dropped, never a bare id)',
      missingWaiting && missingWaiting.defect === true && payloadSchema.isAbsoluteHref(missingWaiting.raw_link));
    ok('S25h artifacts carries the merged event\'s sha', detail.json && detail.json.artifacts && detail.json.artifacts.some((a) => a.sha === 'def5678'));
    ok('S25i sessions includes the dispatching session and the dispatch-provenance lineage child, each with a heartbeat-classified state (reused from session-heartbeat-lib.sh, not re-derived)',
      detail.json && detail.json.sessions &&
      detail.json.sessions.some((s) => s.session_id === 'sess-orch-1') &&
      detail.json.sessions.some((s) => s.session_id === 'sess-child-2' && s.resumed_from === 'sess-orch-1') &&
      detail.json.sessions.every((s) => ['live', 'stale', 'throttled', 'crashed', 'missing'].indexOf(s.state) !== -1),
      JSON.stringify(detail.json && detail.json.sessions));

    // ---- Scenario 25j: /api/ask/<unknown-id> is a clean 404, never a crash.
    const detailMissing = await httpGet(PORT, '/api/ask/ask-does-not-exist');
    ok('S25j /api/ask/<unknown> is a clean 404', detailMissing.status === 404 && detailMissing.json && detailMissing.json.ok === false);

    // ---- Scenario 26: POST /api/ask/<id>/lifecycle — the
    // operator-override exit path (constraint 7), delegating to the REAL
    // ask-registry.sh CLI (Task 8) so this proves actual delegation, not a
    // fake.
    const dismissRes = await httpPostJson(PORT, '/api/ask/ask-fix-4/lifecycle', { action: 'dismiss' });
    ok('S26 lifecycle dismiss returns ok:true with the new status', dismissRes.json && dismissRes.json.ok === true && dismissRes.json.status === 'dismissed', JSON.stringify(dismissRes.json));
    const regAfterDismiss = fs.readFileSync(path.join(arStateDir, 'ask-registry.jsonl'), 'utf8');
    ok('S26b the REAL ask-registry.sh appended a status_change record (status=dismissed, emitter=operator-ui) — real delegation, not a fake',
      /"ask_id":"ask-fix-4".*"record_type":"status_change".*"status":"dismissed".*"emitter":"operator-ui"/.test(regAfterDismiss));
    const landingAfterDismiss = await httpGet(PORT, '/api/asks');
    const demoGroupAfter = landingAfterDismiss.json && (landingAfterDismiss.json.groups || []).find((g) => g.project === 'demo-project');
    ok('S26c dismissed ask leaves the active landing and appears in completed',
      !(demoGroupAfter && demoGroupAfter.asks.find((a) => a.ask_id === 'ask-fix-4')) &&
      landingAfterDismiss.json.completed.asks.some((a) => a.ask_id === 'ask-fix-4'));
    const lifecycleMissing = await httpPostJson(PORT, '/api/ask/ask-does-not-exist/lifecycle', { action: 'done' });
    ok('S26d lifecycle on an unknown ask is a clean 404', lifecycleMissing.status === 404);
    const lifecycleBadAction = await httpPostJson(PORT, '/api/ask/ask-fix-1/lifecycle', { action: 'bogus' });
    ok('S26e lifecycle with an unknown action is a clean 400', lifecycleBadAction.status === 400);
    const lifecycleMergeNoInto = await httpPostJson(PORT, '/api/ask/ask-fix-1/lifecycle', { action: 'merge' });
    ok('S26f lifecycle merge without "into" is a clean 400', lifecycleMergeNoInto.status === 400);

    // ---- Scenario 27: the TWO negative fixtures the plan requires,
    // verbatim ("payload with a gate identifier field -> FAIL"; "payload
    // with a relative href -> FAIL"), run directly against payload-schema.js
    // (fast/deterministic; the live-server scenarios above already prove
    // the SAME checks run at serve time via server.js's own
    // schema-validation branch).
    const cleanLanding = {
      ok: true, status_filter: 'active', generated_at: '2026-07-01T00:00:00Z',
      groups: [{ project: 'demo', asks: [{
        ask_id: 'a', summary: 'a clean summary', project: 'demo', repo: '', status: 'active',
        activity_ts: '2026-07-01T00:00:00Z', plan_progress: { done: 1, in_flight: 0, not_started: 0, total: 1 },
        waiting_count: 0, drift_badges: [], narrative_excerpt: 'task 1 verified done',
      }] }],
      completed: { count: 0, newest_completed_ts: null, asks: [] },
    };
    ok('S27 a clean, real-shaped landing payload PASSES validateLanding (no false positive)',
      payloadSchema.validateLanding(cleanLanding).ok, JSON.stringify(payloadSchema.validateLanding(cleanLanding).errors));

    const gateIdentifierLanding = JSON.parse(JSON.stringify(cleanLanding));
    gateIdentifierLanding.groups[0].asks[0].narrative_excerpt = 'blocked by workstreams-state-gate.sh';
    const gateCheck = payloadSchema.validateLanding(gateIdentifierLanding);
    ok('S27a NEGATIVE FIXTURE (required by plan): a payload with a gate/hook identifier field FAILS validateLanding',
      gateCheck.ok === false && gateCheck.errors.some((e) => /gate\/hook identifier/.test(e)),
      JSON.stringify(gateCheck.errors));

    const cleanDetail = {
      ok: true, ask_id: 'a', summary: 's', project: 'p', repo: '', status: 'active', verbatim_ref: '',
      plan_slugs: [], narrative: [{ ts: '2026-07-01T00:00:00Z', summary: 'ok', evidence_link: '' }],
      plan_rows: [], waiting_items: [], artifacts: [], sessions: [],
    };
    ok('S27b a clean, real-shaped detail payload PASSES validateAskDetail (no false positive)',
      payloadSchema.validateAskDetail(cleanDetail).ok, JSON.stringify(payloadSchema.validateAskDetail(cleanDetail).errors));

    const relativeHrefDetail = JSON.parse(JSON.stringify(cleanDetail));
    relativeHrefDetail.narrative[0].evidence_link = 'docs/plans/foo.md';
    const hrefCheck = payloadSchema.validateAskDetail(relativeHrefDetail);
    ok('S27c NEGATIVE FIXTURE (required by plan): a payload with a relative href FAILS validateAskDetail',
      hrefCheck.ok === false && hrefCheck.errors.some((e) => /relative href/.test(e)),
      JSON.stringify(hrefCheck.errors));

    // A relative path carried inside the EXEMPT plan_doc {project, path}
    // shape must NOT trip the absolute-href check (ux-review amendment 6 —
    // "no new link handling", the existing /api/doc resolver's own contract).
    const planDocDetail = JSON.parse(JSON.stringify(cleanDetail));
    planDocDetail.plan_rows = [{ plan_slug: 'x', plan_doc: { project: 'demo', path: 'docs/plans/x.md' }, tasks: [] }];
    ok('S27d plan_doc {project, path} is EXEMPT from the absolute-href check (the existing /api/doc resolver contract, not a rendered href)',
      payloadSchema.validateAskDetail(planDocDetail).ok, JSON.stringify(payloadSchema.validateAskDetail(planDocDetail).errors));

    // ========================================================================
    // Scenario 28 (ask-rooted-workstreams-p1 Task 12 — background auditor):
    // WIRING proof. AUDITOR_DISABLED (set above) only gates the autostart
    // timer/immediate-fire at server-listen time; a DIRECT auditor.runCycle()
    // call is unaffected — this proves the server.js merge (getBadgesForAsk
    // reaching /api/asks + /api/ask/<id>), not just auditor.js in isolation
    // (already proven end-to-end by auditor.js's own --self-test).
    // ========================================================================
    const slug5 = 'selftest-task12-fixture-plan';
    const plan5Path = path.join(fixtureRepoDir, 'docs', 'plans', slug5 + '.md');
    fs.writeFileSync(plan5Path, [
      '# Plan: Task 12 fixture', 'Status: ACTIVE', '',
      '- [ ] 1. task one — log will say done, file stays open (Class E fixture).', '',
    ].join('\n'));
    fs.appendFileSync(path.join(arStateDir, 'ask-registry.jsonl'), [
      regLine({ ask_id: 'ask-fix-5', record_type: 'created', ts: '2026-07-04T00:00:00Z', repo: fixtureRepoDir, project: 'demo-project', summary: 'Fixture ask five (drift)', status: 'active' }),
      regLine({ ask_id: 'ask-fix-5', record_type: 'plan_linked', ts: '2026-07-04T00:01:00Z', plan_slug: slug5 }),
    ].join('\n') + '\n');
    fs.writeFileSync(path.join(plStateDir, 'ask-fix-5.jsonl'),
      mkEvent({ ask_id: 'ask-fix-5', type: 'task_done', plan_slug: slug5, task_id: '1', sha: 'fix5sha', evidence_link: plan5Path, summary: 'task 1 verified done', ts: '2026-07-04T00:02:00Z' }) + '\n');

    // Confine the merge-scan lane to a nonexistent dir so this manual cycle
    // never walks the real machine's project set via config/projects.js's
    // discovery (merge-scan-lib.sh's scan-repo is a documented no-op when
    // `git -C <root> rev-parse` fails — see its own header).
    process.env.AUDITOR_REPO_ROOTS = path.join(askTmp, 'no-such-repo-root');

    await auditor.runCycle();

    const landing5 = await httpGet(PORT, '/api/asks');
    const demoGroup5 = landing5.json && (landing5.json.groups || []).find((g) => g.project === 'demo-project');
    const card5 = demoGroup5 && demoGroup5.asks.find((a) => a.ask_id === 'ask-fix-5');
    ok('S28 the auditor\'s log-ahead-of-truth badge (Class E: task_done event, checkbox unflipped) reaches /api/asks card-level drift_badges',
      card5 && card5.drift_badges && card5.drift_badges.some((b) => b.divergence_class === 'log_ahead_task_not_flipped' && b.task_id === '1' && !!b.detail_ref),
      JSON.stringify(card5 && card5.drift_badges));
    ok('S28b landing still validates against payload-schema.js with the new badge fields present (no allowlist regression)',
      landing5.json && landing5.json.ok === true, JSON.stringify(landing5.json && landing5.json.ok));

    const detail5 = await httpGet(PORT, '/api/ask/ask-fix-5');
    ok('S28c the SAME badge reaches /api/ask/<id>\'s ask-level drift_badges',
      detail5.json && detail5.json.drift_badges && detail5.json.drift_badges.some((b) => b.divergence_class === 'log_ahead_task_not_flipped'),
      JSON.stringify(detail5.json && detail5.json.drift_badges));
    const planRow5 = detail5.json && detail5.json.plan_rows && detail5.json.plan_rows.find((r) => r.plan_slug === slug5);
    ok('S28d the SAME badge is ALSO attached to the matching task ROW (plan_rows[].tasks[].drift_badges), routed by plan_slug+task_id',
      planRow5 && planRow5.tasks[0] && planRow5.tasks[0].drift_badges &&
      planRow5.tasks[0].drift_badges.some((b) => b.divergence_class === 'log_ahead_task_not_flipped'),
      JSON.stringify(planRow5));
    ok('S28e the auditor NEVER auto-flips the checkbox (constraint 6) — the fixture plan file still reads `- [ ]`',
      /- \[ \] 1\./.test(fs.readFileSync(plan5Path, 'utf8')));

    // ---- Latency: a concurrent, real auditor cycle must never slow down
    // /api/asks (Behavioral Contracts perf budget — "no oracle shelling on
    // the landing path"; the auditor is entirely off it).
    const cyclePromise2 = auditor.runCycle();
    const latencyStart = Date.now();
    const landingDuringCycle = await httpGet(PORT, '/api/asks');
    const latencyMs = Date.now() - latencyStart;
    ok('S28f /api/asks stays fast (<300ms, the same p95 budget Task 11 pins) while an auditor cycle is concurrently in flight (auditor is off-path)',
      landingDuringCycle.json && landingDuringCycle.json.ok === true && latencyMs < 300,
      'latencyMs=' + latencyMs);
    await cyclePromise2;

    // ========================================================
    // Ask-rooted-workstreams-p1 Task 14 — "My To-Do pane" scenarios (S29+).
    // Reuses the SAME sandboxed `operatorTodoPath`/`nyMdPath`/`nyStateDir`
    // (constraint 4) the Task 11/12 fixture section above already set up —
    // S22b's REAL needs-you.sh invocations already appended two AUTO pointer
    // bullets (goodNeedsYouId, badNeedsYouId) into this file, so S29 reads
    // real mechanism-written state, not a hand-typed sample.
    // ========================================================
    const todoGet = () => httpGet(PORT, '/api/todo');
    const todoPost = (body) => httpPostJson(PORT, '/api/todo', body);

    const todoS29 = await todoGet();
    ok('S29 GET /api/todo returns ok:true with the two REAL needs-you.sh pointer bullets from S22b (no UI action taken)',
      todoS29.json && todoS29.json.ok === true && Array.isArray(todoS29.json.pointer_items) && todoS29.json.pointer_items.length === 2,
      JSON.stringify(todoS29.json));
    ok('S29b operator_items is empty (nothing added yet)',
      todoS29.json && Array.isArray(todoS29.json.operator_items) && todoS29.json.operator_items.length === 0);
    const goodPointer = todoS29.json && todoS29.json.pointer_items.find((p) => p.needs_you_id === goodNeedsYouId);
    ok('S29c the good pointer carries its §3 title (first line of the needs-you.sh --text) and full body from the REAL rendered NEEDS-YOU.md',
      goodPointer && goodPointer.title === 'Ship the fixture tonight?' && /My pick: ship tonight\./.test(goodPointer.body || ''),
      JSON.stringify(goodPointer));
    ok('S29d the good pointer is unchecked, not an operator override, and carries an ABSOLUTE raw_link to NEEDS-YOU.md',
      goodPointer && goodPointer.checked === false && goodPointer.operator_override === false &&
      typeof goodPointer.raw_link === 'string' && payloadSchema.isAbsoluteHref(goodPointer.raw_link) && goodPointer.raw_link.indexOf('NEEDS-YOU.md') !== -1,
      JSON.stringify(goodPointer));
    ok('S29e session_id/tier/section parsed from the real bullet (session=sess-orig-1, tier=untiered since S22b passed none)',
      goodPointer && goodPointer.session_id === 'sess-orig-1' && goodPointer.tier === 'untiered' && goodPointer.section === 'decision',
      JSON.stringify(goodPointer));

    // ---- S30/S31/S32: operator add/toggle/edit round-trip, each persisted
    // to the REAL file (never a parallel store) and visible on the next GET.
    const addRes = await todoPost({ action: 'add', text: 'buy more coffee' });
    ok('S30 POST add appends an operator item and returns its index',
      addRes.json && addRes.json.ok === true && addRes.json.index === 0 && addRes.json.text === 'buy more coffee',
      JSON.stringify(addRes.json));
    const todoAfterAdd = fs.readFileSync(operatorTodoPath, 'utf8');
    ok('S30b the REAL file now contains the operator bullet in the Operator items section (before AUTO:START)',
      /- \[ \] buy more coffee/.test(todoAfterAdd) && todoAfterAdd.indexOf('- [ ] buy more coffee') < todoAfterAdd.indexOf('<!-- AUTO:START -->'),
      todoAfterAdd);

    const toggleRes = await todoPost({ action: 'toggle', index: 0 });
    ok('S31 POST toggle flips the operator item to checked', toggleRes.json && toggleRes.json.ok === true && toggleRes.json.checked === true, JSON.stringify(toggleRes.json));
    const todoGetAfterToggle = await todoGet();
    ok('S31b GET reflects the persisted checked state (file is truth, UI is a view)',
      todoGetAfterToggle.json && todoGetAfterToggle.json.operator_items[0] && todoGetAfterToggle.json.operator_items[0].checked === true);

    const editRes = await todoPost({ action: 'edit', index: 0, text: 'buy even more coffee' });
    ok('S32 POST edit changes the text and PRESERVES the checked state', editRes.json && editRes.json.ok === true && editRes.json.text === 'buy even more coffee' && editRes.json.checked === true, JSON.stringify(editRes.json));

    // ---- S33: mistake recovery — an out-of-range index is a named,
    // recoverable 404, never a crash or a silent no-op.
    const toggleBad = await todoPost({ action: 'toggle', index: 99 });
    ok('S33 toggle on an out-of-range index is a clean 404 with a recoverable message', toggleBad.status === 404 && toggleBad.json && toggleBad.json.ok === false);
    const editBad = await todoPost({ action: 'edit', index: 99, text: 'x' });
    ok('S33b edit on an out-of-range index is a clean 404', editBad.status === 404 && editBad.json && editBad.json.ok === false);

    // ---- S34 NEGATIVE FIXTURE (anti-noise, constraint 1): adding text that
    // mentions a gate/hook identifier is REJECTED at write time (never
    // reaches the durable file), mirroring S27a/S27c's payload-level
    // negative-fixture discipline for the write path instead of the read
    // path.
    const beforeBadAdd = fs.readFileSync(operatorTodoPath, 'utf8');
    const badAdd = await todoPost({ action: 'add', text: 'check work-integrity-gate output' });
    ok('S34 NEGATIVE FIXTURE: adding text with a denylisted gate identifier is rejected (400, never written)',
      badAdd.status === 400 && badAdd.json && badAdd.json.ok === false, JSON.stringify(badAdd.json));
    const afterBadAdd = fs.readFileSync(operatorTodoPath, 'utf8');
    ok('S34b the rejected text never reached the durable file', afterBadAdd === beforeBadAdd);

    // ---- S35: the constraint-7 operator-override escape hatch ("Mark
    // handled" — for when the auditor's ledger-derived resolution can't see
    // a decision that WAS actually resolved).
    const overrideRes = await todoPost({ action: 'pointer_override', needs_you_id: goodNeedsYouId });
    ok('S35 POST pointer_override marks the pointer checked + operator_override:true',
      overrideRes.json && overrideRes.json.ok === true && overrideRes.json.checked === true && overrideRes.json.operator_override === true,
      JSON.stringify(overrideRes.json));
    const todoAfterOverride = fs.readFileSync(operatorTodoPath, 'utf8');
    ok('S35b the REAL file carries the checked box + the operator-override marker on the exact pointer line',
      new RegExp('- \\[x\\] AUTO: .*' + goodNeedsYouId + '.*\\(marked handled by operator, ').test(todoAfterOverride),
      todoAfterOverride);
    const overrideAgain = await todoPost({ action: 'pointer_override', needs_you_id: goodNeedsYouId });
    ok('S35c overriding an already-handled pointer is a clean 409 (mistake recovery: no silent double-write)', overrideAgain.status === 409 && overrideAgain.json && overrideAgain.json.ok === false);

    // ---- S35d (Prove-it-works step 5): the REAL Task 12 auditor cycle
    // NEVER reverts/fights the operator override — autoCheckOperatorTodo
    // only ever flips an UNCHECKED bullet (see its own header); this pointer
    // is already checked, so a full real auditor cycle (even one that
    // thinks the id is still "open" ground truth) must leave the file byte
    // -for-byte unchanged.
    await auditor.runCycle();
    const todoAfterAuditorCycle = fs.readFileSync(operatorTodoPath, 'utf8');
    ok('S35d a REAL auditor.runCycle() never reverts the operator-override (auditor "respects, never fights" by construction, not special-casing)',
      todoAfterAuditorCycle === todoAfterOverride, todoAfterAuditorCycle);

    // ---- S36: concurrent-writer safety (Integration point: "Concurrent
    // writes (session appends pointer while operator edits) — marker-
    // delimited sections + atomic rewrite of only the touched section").
    // Interleaves a SECOND real needs-you.sh append (an independent bash
    // read-modify-write of the SAME file) with this test's own operator
    // writes above, then verifies every prior write (both operator items AND
    // both original pointers AND the override) survived untouched, and the
    // new pointer is ALSO present — proving the two writers' marker-scoped
    // sections never clobber each other across sequential interleaving (the
    // achievable guarantee this codebase's atomic-rewrite-no-locking model
    // provides; a true simultaneous-write race is last-writer-wins by
    // design, same accepted tradeoff as Task 12's autoCheckOperatorTodo).
    const thirdRes = spawnSync(nyBash, [needsYouSh, 'add', '--section', 'question', '--text', 'Third fixture pointer for the concurrency check', '--session', 'sess-smoke-3'], { env: nyEnv, encoding: 'utf8' });
    const thirdNeedsYouId = String(thirdRes.stdout || '').trim();
    ok('S36 (setup) a THIRD real needs-you.sh add produced a new NY- id', /^NY-/.test(thirdNeedsYouId) && thirdNeedsYouId !== goodNeedsYouId && thirdNeedsYouId !== badNeedsYouId, thirdNeedsYouId);

    const todoS36 = await todoGet();
    const opItems36 = (todoS36.json && todoS36.json.operator_items) || [];
    const ptrItems36 = (todoS36.json && todoS36.json.pointer_items) || [];
    ok('S36b the operator item survives the interleaved needs-you.sh write, unchanged',
      opItems36.length === 1 && opItems36[0].text === 'buy even more coffee' && opItems36[0].checked === true, JSON.stringify(opItems36));
    ok('S36c all THREE pointers are present (good override + bad + the new third), none clobbered by the other writer',
      ptrItems36.length === 3 &&
      ptrItems36.some((p) => p.needs_you_id === goodNeedsYouId && p.checked === true && p.operator_override === true) &&
      ptrItems36.some((p) => p.needs_you_id === badNeedsYouId && p.checked === false) &&
      ptrItems36.some((p) => p.needs_you_id === thirdNeedsYouId && p.checked === false && p.section === 'question'),
      JSON.stringify(ptrItems36));

    // ---- S37 NEGATIVE FIXTURE (anti-noise, read path): a foreign/hand-
    // edited line in the Operator items section carrying a denylisted
    // identifier fails GET's defensive scan (500, never leaks to the UI) —
    // this exercises the SAME containsDenylistedIdentifier scanner
    // /api/asks already relies on, on the read side this time. Runs last
    // (this test's own tmp dir is discarded in `finally` right after) so no
    // restore is needed.
    const foreignText = fs.readFileSync(operatorTodoPath, 'utf8').replace(
      '<!-- AUTO:START -->',
      '- [ ] check the work-integrity-gate output\n<!-- AUTO:START -->'
    );
    fs.writeFileSync(operatorTodoPath, foreignText);
    const todoS37 = await todoGet();
    ok('S37 NEGATIVE FIXTURE: GET /api/todo fails closed (500, diagnostic error) on a foreign line carrying a gate identifier, never leaking it',
      todoS37.status === 500 && todoS37.json && todoS37.json.ok === false, JSON.stringify(todoS37.json));

    // ========================================================
    // Ask-rooted-workstreams-p1 Task 15 — "Backlog pane" scenarios (S40-49).
    // Sandboxed via BACKLOG_MD_PATH (server.js's backlogMdPath() env
    // override, matching the O.9 golden oracle's own env var name so a
    // fixture pointed at it is honored identically by both readers —
    // constraint 4 sandboxing, never the real docs/backlog.md). A small,
    // deterministic fixture (not the real ~1000-line file — that parity was
    // hand-verified separately against a live run of the real oracle,
    // per this task's build evidence) covering one row per tier + one
    // pre-existing terminal row + one pre-existing in-flight row.
    // ========================================================
    const backlogFixturePath = path.join(tmp, 'backlog-fixture.md');
    const BACKLOG_FIXTURE_TEMPLATE = [
      '# Fixture Backlog',
      '',
      '## Open work — substantive deferrals',
      '',
      '- **FIX-HIGH-ROW-01 — a high priority fixture row** (added 2026-06-01; priority:high). High tier body text.',
      '- **FIX-MED-ROW-01 — a medium priority fixture row** (added 2026-06-15; priority:medium). Medium tier body text.',
      '- **FIX-LOW-ROW-01 — a low priority fixture row** (added 2026-07-01; priority:low). Low tier body text.',
      '- **FIX-NOPRIO-ROW-01 — an unlabeled fixture row** (added 2026-07-05). No priority label at all.',
      '- **FIX-TERM-ROW-01 — a pre-marked-done fixture row** (added 2026-05-01; priority:medium). **WONTFIX 2026-05-02** (pre-existing fixture disposition).',
      '- **FIX-INFLIGHT-ROW-01 — a pre-marked-answered fixture row** (added 2026-06-10; priority:high). **SCHEDULED 2026-06-11** (pre-existing fixture disposition).',
      '',
      '## Open work — telemetry-gated (dont pick up yet)',
      '',
      '- **FIX-OTHER-SECTION-01 — a row in a different section** (added 2026-06-01; priority:low). Must never be touched by an insert targeting the substantive-deferrals section.',
      '',
    ].join('\n');
    fs.writeFileSync(backlogFixturePath, BACKLOG_FIXTURE_TEMPLATE);
    process.env.BACKLOG_MD_PATH = backlogFixturePath;
    process.env.BACKLOG_COMPACT_CAP = '2';

    const backlogGet = () => httpGet(PORT, '/api/backlog');
    const backlogPost = (body) => httpPostJson(PORT, '/api/backlog', body);

    const bl40 = await backlogGet();
    ok('S40 GET /api/backlog returns ok:true against the fixture with the expected open/inflight/terminal counts (4 open, 1 inflight, 1 terminal; the other-section row never counted against this section)',
      bl40.status === 200 && bl40.json && bl40.json.ok === true &&
      bl40.json.counts.open_total === 5 && bl40.json.counts.inflight_total === 1 && bl40.json.counts.terminal_total === 1,
      JSON.stringify(bl40.json && bl40.json.counts));
    ok('S40b full[] includes every row from BOTH sections (7 total: 5 open + 1 inflight + 1 terminal, incl. FIX-OTHER-SECTION-01)',
      bl40.json && Array.isArray(bl40.json.full) && bl40.json.full.length === 7 &&
      !!bl40.json.full.find((r) => r.id === 'FIX-OTHER-SECTION-01'),
      JSON.stringify(bl40.json && bl40.json.full.map((r) => r.id)));
    const termRow40 = bl40.json.full.find((r) => r.id === 'FIX-TERM-ROW-01');
    ok('S40c the pre-existing terminal fixture row carries status:terminal + disposition_word:WONTFIX',
      !!termRow40 && termRow40.status === 'terminal' && termRow40.disposition_word === 'WONTFIX', JSON.stringify(termRow40));
    ok('S40d the pre-existing in-flight fixture row carries status:inflight + disposition_word:SCHEDULED, and is excluded from every tier bucket (never re-nags)',
      bl40.json.full.find((r) => r.id === 'FIX-INFLIGHT-ROW-01').status === 'inflight' &&
      bl40.json.full.find((r) => r.id === 'FIX-INFLIGHT-ROW-01').disposition_word === 'SCHEDULED' &&
      !bl40.json.compact.high.rows.find((r) => r.id === 'FIX-INFLIGHT-ROW-01'));

    // ---- S41: compact top-N-per-tier capping (BACKLOG_COMPACT_CAP=2 above;
    // each tier here has exactly 1 open row so `rows` == `total`, still
    // proving the shape both fields are meant to carry).
    ok('S41 compact.high carries exactly the 1 high-priority open row (total===rows.length===1)',
      bl40.json.compact.high.total === 1 && bl40.json.compact.high.rows.length === 1 &&
      bl40.json.compact.high.rows[0].id === 'FIX-HIGH-ROW-01');
    ok('S41b compact.unlabeled carries the no-priority-label row bucketed separately from "low"',
      bl40.json.compact.unlabeled.rows.length === 1 && bl40.json.compact.unlabeled.rows[0].id === 'FIX-NOPRIO-ROW-01' &&
      bl40.json.compact.low.rows.every((r) => r.id !== 'FIX-NOPRIO-ROW-01'));

    // ---- S42: add appends a well-formed row at the END of "Open work —
    // substantive deferrals" (Prove-it-works step 2: "in the right
    // section") and persists on reload; the sibling section's row is
    // untouched (Prove-it-works step 4: "no other row disturbed").
    const backlogAddRes = await backlogPost({ action: 'add', title: 'a new fixture add', priority: 'high', description: 'added by S42.' });
    ok('S42 POST add returns ok:true with a generated ID matching the reId grammar', backlogAddRes.json && backlogAddRes.json.ok === true && /^[A-Z][A-Z0-9-]{3,}$/.test(backlogAddRes.json.id), JSON.stringify(backlogAddRes.json));
    const afterAddText = fs.readFileSync(backlogFixturePath, 'utf8');
    const addLines = afterAddText.split('\n');
    const otherSectionIdx = addLines.findIndex((l) => l.indexOf('FIX-OTHER-SECTION-01') !== -1);
    const nextHeadingIdx = addLines.findIndex((l) => l.trim() === '## Open work — telemetry-gated (dont pick up yet)');
    const newRowIdx = addLines.findIndex((l) => l.indexOf(backlogAddRes.json.id) !== -1);
    ok('S42b the new row lands BEFORE the next section heading (right section) and the sibling-section row is unmoved',
      newRowIdx !== -1 && nextHeadingIdx !== -1 && newRowIdx < nextHeadingIdx && otherSectionIdx > nextHeadingIdx);
    ok('S42c reload (a second GET) reflects the persisted add (file is truth)',
      (await backlogGet()).json.counts.open_total === 6);

    // ---- S43: mistake recovery — empty title is a clean 400, never written.
    const addBadRes = await backlogPost({ action: 'add', title: '   ', priority: 'low' });
    ok('S43 POST add with a blank title is a clean 400, not written', addBadRes.status === 400 && addBadRes.json && addBadRes.json.ok === false);
    ok('S43b the rejected add never touched the file (byte-identical to just before it)', fs.readFileSync(backlogFixturePath, 'utf8') === afterAddText);

    // ---- S44: WONTFIX dispose — row-scoped (Prove-it-works step 4: "no
    // other row disturbed") + loop-parseable (verified structurally here;
    // this task's build evidence additionally cross-checked the SAME writer
    // against a live run of the real od_backlog_health oracle).
    const beforeWontfix = fs.readFileSync(backlogFixturePath, 'utf8');
    const wontfixRes = await backlogPost({ action: 'dispose', id: 'FIX-MED-ROW-01', disposition: 'wontfix', reason: 'no longer relevant' });
    ok('S44 POST dispose wontfix returns ok:true, terminal:true, and the exact appended suffix',
      wontfixRes.json && wontfixRes.json.ok === true && wontfixRes.json.terminal === true && /\*\*WONTFIX \d{4}-\d{2}-\d{2}\*\*/.test(wontfixRes.json.appended_suffix),
      JSON.stringify(wontfixRes.json));
    const bl44 = await backlogGet();
    ok('S44b GET now shows FIX-MED-ROW-01 as status:terminal, disposition_word:WONTFIX, no longer in compact.medium',
      bl44.json.full.find((r) => r.id === 'FIX-MED-ROW-01').status === 'terminal' &&
      bl44.json.full.find((r) => r.id === 'FIX-MED-ROW-01').disposition_word === 'WONTFIX' &&
      !bl44.json.compact.medium.rows.find((r) => r.id === 'FIX-MED-ROW-01'));
    const afterWontfixLines = fs.readFileSync(backlogFixturePath, 'utf8').split('\n');
    const beforeWontfixLines = beforeWontfix.split('\n');
    const changedLineCount = afterWontfixLines.filter((l, i) => l !== beforeWontfixLines[i]).length;
    ok('S44c EXACTLY ONE line changed in the whole file (row-scoped writer — Prove-it-works step 4: "no other row disturbed")', changedLineCount === 1, 'changed=' + changedLineCount);

    // ---- S45: DEMOTE dispose + undo — byte-exact restore (Prove-it-works
    // step 3: "undo restores the row unchanged").
    const beforeDemote = fs.readFileSync(backlogFixturePath, 'utf8');
    const demoteRes = await backlogPost({ action: 'dispose', id: 'FIX-HIGH-ROW-01', disposition: 'demote' });
    ok('S45 POST dispose demote returns ok:true, terminal:false, word DEMOTED', demoteRes.json && demoteRes.json.ok === true && demoteRes.json.terminal === false && demoteRes.json.word === 'DEMOTED', JSON.stringify(demoteRes.json));
    const bl45 = await backlogGet();
    ok('S45b GET now shows FIX-HIGH-ROW-01 as status:inflight (dispositioned-in-flight — not terminal, not open, never re-nags)',
      bl45.json.full.find((r) => r.id === 'FIX-HIGH-ROW-01').status === 'inflight');
    const undoRes = await backlogPost({ action: 'undo', id: 'FIX-HIGH-ROW-01', appended_suffix: demoteRes.json.appended_suffix });
    ok('S45c POST undo returns ok:true', undoRes.json && undoRes.json.ok === true, JSON.stringify(undoRes.json));
    ok('S45d the file is BYTE-IDENTICAL to before the demote (true undo, not just a status flip)', fs.readFileSync(backlogFixturePath, 'utf8') === beforeDemote);
    ok('S45e GET now shows FIX-HIGH-ROW-01 back to status:open', (await backlogGet()).json.full.find((r) => r.id === 'FIX-HIGH-ROW-01').status === 'open');

    // ---- S46: undo mistake recovery — a stale/wrong suffix is a clean 409,
    // never silently truncates or corrupts the line.
    const beforeStaleUndo = fs.readFileSync(backlogFixturePath, 'utf8');
    const staleUndoRes = await backlogPost({ action: 'undo', id: 'FIX-HIGH-ROW-01', appended_suffix: ' **DEMOTED 2099-01-01** (fabricated, never applied)' });
    ok('S46 POST undo with a suffix that was never applied is a clean 409, file untouched',
      staleUndoRes.status === 409 && staleUndoRes.json && staleUndoRes.json.ok === false &&
      fs.readFileSync(backlogFixturePath, 'utf8') === beforeStaleUndo);

    // ---- S47/S48: dispose mistake recovery.
    const disposeMissingRes = await backlogPost({ action: 'dispose', id: 'FIX-DOES-NOT-EXIST-01', disposition: 'schedule' });
    ok('S47 POST dispose on a nonexistent id is a clean 404', disposeMissingRes.status === 404 && disposeMissingRes.json && disposeMissingRes.json.ok === false);
    const disposeBadWordRes = await backlogPost({ action: 'dispose', id: 'FIX-LOW-ROW-01', disposition: 'bogus' });
    ok('S48 POST dispose with an unrecognized disposition word is a clean 400, never written', disposeBadWordRes.status === 400 && disposeBadWordRes.json && disposeBadWordRes.json.ok === false);

    // ---- S49: FOLD (optional target) round-trips through the SAME
    // in-flight classification as SCHEDULE/DEMOTE, and the anti-noise law is
    // deliberately NOT applied to row text (a title containing a `.sh`/
    // `-gate` token must still render — see server.js's header rationale).
    const foldRes = await backlogPost({ action: 'dispose', id: 'FIX-LOW-ROW-01', disposition: 'fold', target: 'my plan!!' });
    ok('S49 POST dispose fold with a target slugifies it into FOLD-INTO-<slug>', foldRes.json && foldRes.json.ok === true && foldRes.json.word === 'FOLD-INTO-my-plan', JSON.stringify(foldRes.json));
    const antiNoiseAddRes = await backlogPost({ action: 'add', title: 'audit needs-you.sh and the work-integrity-gate output', priority: 'low' });
    ok('S49b a title naming real hook/gate identifiers is accepted (backlog content is legitimately ABOUT harness internals — anti-noise law is scoped to the ask-tree/My-To-Do narrative, not this pane; see server.js header)',
      antiNoiseAddRes.json && antiNoiseAddRes.json.ok === true, JSON.stringify(antiNoiseAddRes.json));

  } finally {
    server.close();
    cache.stop();
    auditor.stop(); // no-op here (AUDITOR_DISABLED kept the timer from ever starting) — symmetry with cache.stop()
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
    // planAbsPath (Task 11 ask-rooted-workstreams fixture) is deliberately
    // OUTSIDE `tmp` (it lives under the real self-repo root so plan_doc
    // resolution has a real project root to resolve against) — clean it up
    // explicitly so this self-test never leaves a fixture file behind in
    // the real docs/plans/ directory.
    try { if (typeof planAbsPath === 'string') fs.rmSync(planAbsPath, { force: true }); } catch (_) {}
  }

  console.log('');
  console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('self-test crashed:', err);
  process.exit(1);
});
