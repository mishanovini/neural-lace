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
    '{"schema":1,"oracle":"od_costs","total":{"input_tokens":10,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"throttle_events":0,"est_minutes_lost":0,"truncated_to_recent":false,"sessions":[]}',
    'JSON',
    '    ;;',
    '  backlog)',
    '    cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_backlog_health","open_total":1,"terminal_total":0,"priority":{"high":0,"medium":1,"low":0,"unlabeled":0},"age":{"0_7d":1,"8_30d":0,"31_90d":0,"over_90d":0,"undated":0},"flow_7d":{"adds":1,"terminal":0,"terminal_undated":0},"tiers":{"high_days":7,"medium_days":30,"low_days":90}}',
    'JSON',
    '    ;;',
    '  why)',
    '    sid="${1:-}"',
    '    if [[ "$sid" == "sess-024-fixture" ]]; then',
    '      cat <<\'JSON\'',
    '{"schema":1,"oracle":"od_why","session_id":"sess-024-fixture","transcript_status":"present","chain":[{"ts":"2026-07-06T00:00:00Z","gate":"workstreams-emit","event":"spawn-dispatched","detail":"branch=build/x"},{"ts":"2026-07-06T00:00:05Z","gate":"workstreams-state-gate","event":"block","detail":"no live node for branch"}]}',
    'JSON',
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

  process.env.NL_BIN = stubPath;
  process.env.CTREE_PORT = '0'; // resolved below to an ephemeral port via a wrapper
  const PORT = 17733 + (process.pid % 1000); // deterministic-ish, avoids common collisions
  process.env.CTREE_PORT = String(PORT);
  process.env.OBS_REFRESH_MS = '999999'; // don't let the timer refire during the test

  delete require.cache[require.resolve('./derive-cache.js')];
  delete require.cache[require.resolve('./reconciler.js')];
  delete require.cache[require.resolve('./server.js')];
  const { server, cache } = require('./server.js');

  // Give the initial refreshAll() (triggered by cache.start() in server.js)
  // a moment to finish its synchronous spawnSync calls — they're
  // synchronous so by the time require() returns they're already done, but
  // we wait one tick for the HTTP server's listen() callback to fire.
  await new Promise((resolve) => setTimeout(resolve, 300));

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

    const costs = await httpGet(PORT, '/api/pane/costs');
    ok('S5 /api/pane/costs returns fixture totals', costs.json && costs.json.rc === 0 &&
      costs.json.data && costs.json.data.total && costs.json.data.total.input_tokens === 10);

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
