'use strict';
// derive-cache-persist.selftest.js — sandboxed self-test for derive-cache.js's
// disk-persistence fix (FIX2, operator directive 2026-08-04: "it still
// spends a few seconds deriving the content ... it should already be
// stored"). Own file (not folded into server.selftest.js or
// state-watch.selftest.js) — same per-concern-file rationale those suites'
// own headers give (inbox-routes.selftest.js / requests-routes.selftest.js /
// maintenance-pane.selftest.js all follow this convention already).
//
// Three parts:
//   PART 1 (S1-S8)   — unit coverage of loadPersistedEntries/persistEntries
//                      directly: shape validation, atomicity, honesty
//                      (derived_at never re-stamped, error entries never
//                      smoothed into a fake success).
//   PART 2 (S9-S13)  — DeriveCache construction: a pre-existing snapshot is
//                      served INSTANTLY (no refreshAll() call at all), then
//                      a real refreshAll() flips source to 'live' and
//                      re-persists, proving the full cold-start -> live ->
//                      persisted -> cold-start-again round trip.
//   PART 3 (S14-S17) — the actual user-facing path (constitution §4,
//                      "functionality over components"): a real HTTP GET
//                      against a real server.js instance, proving the page
//                      renders real content immediately on a cold start
//                      instead of a loading state, while a slow background
//                      refresh is still in flight.
//
// Run: `node server/derive-cache-persist.selftest.js`. Exit 0 PASS / 1 FAIL.

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
    http.get({ host: '127.0.0.1', port: port, path: urlPath, agent: false }, (res) => {
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

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'o4-dc-persist-st-'));

  delete require.cache[require.resolve('./derive-cache.js')];
  const dc = require('./derive-cache.js');
  const SUBS = Object.keys(dc.SUBCOMMANDS);

  try {
    // ================================================================
    // PART 1 — unit coverage of loadPersistedEntries / persistEntries.
    // ================================================================
    const p1 = path.join(tmp, 'part1-snapshot.json');
    process.env.OBS_DERIVE_SNAPSHOT_PATH = p1;

    // S1 — no file on disk yet: honest null, not a crash, not an empty object.
    ok('S1 loadPersistedEntries returns null when no snapshot file exists yet',
      dc.loadPersistedEntries(SUBS) === null);
    ok('S1b snapshotPath() honors OBS_DERIVE_SNAPSHOT_PATH', dc.snapshotPath() === p1, dc.snapshotPath());

    // S2 — malformed JSON on disk: honest null, never a throw ("never trust, verify").
    fs.mkdirSync(path.dirname(p1), { recursive: true });
    fs.writeFileSync(p1, '{not valid json');
    let threwS2 = false;
    let s2Result;
    try { s2Result = dc.loadPersistedEntries(SUBS); } catch (_) { threwS2 = true; }
    ok('S2 malformed JSON on disk never throws', !threwS2);
    ok('S2b malformed JSON on disk degrades to null (cold start proceeds with the loading state)', s2Result === null);

    // S3 — valid JSON but missing the `entries` key (unrecognized shape):
    // honest null, not a crash trying to read parsed.entries[sub].
    fs.writeFileSync(p1, JSON.stringify({ schema: 1, written_at: '2026-08-04T00:00:00Z' }));
    ok('S3 valid JSON missing the entries key -> null (unrecognized shape)',
      dc.loadPersistedEntries(SUBS) === null);

    // S4 — a full, well-formed snapshot: every sub comes back with
    // source:'snapshot' and derived_at PRESERVED VERBATIM (the
    // honesty-critical field — never re-stamped to "now").
    const OLD_TS = '2026-07-01T03:04:05.000Z'; // deliberately far from "now" so a re-stamp bug is unmissable
    const fixtureEntries = {};
    SUBS.forEach((sub) => {
      fixtureEntries[sub] = { data: { oracle: 'fixture-' + sub, n: 42 }, rc: 0, stderr_tail: '', derived_at: OLD_TS };
    });
    fs.writeFileSync(p1, JSON.stringify({ schema: 1, written_at: OLD_TS, entries: fixtureEntries }));
    const loaded4 = dc.loadPersistedEntries(SUBS);
    ok('S4 a well-formed snapshot loads every subcommand', loaded4 && SUBS.every((s) => !!loaded4[s]),
      JSON.stringify(loaded4 && Object.keys(loaded4)));
    ok('S4b loaded entries carry source:"snapshot"', loaded4 && SUBS.every((s) => loaded4[s].source === 'snapshot'));
    ok('S4c derived_at is preserved EXACTLY as written, never re-stamped to "now" (the honesty-critical field, requirement (c))',
      loaded4 && SUBS.every((s) => loaded4[s].derived_at === OLD_TS),
      JSON.stringify(loaded4 && loaded4.status && loaded4.status.derived_at));
    ok('S4d loaded entries carry the fixture data verbatim',
      loaded4 && loaded4.status.data.oracle === 'fixture-status' && loaded4.status.data.n === 42);

    // S5 — a PARTIAL snapshot (only one sub present, e.g. an older schema or
    // a write that raced a schema change): fills in only what's usable,
    // leaves the rest for the caller's normal placeholder.
    fs.writeFileSync(p1, JSON.stringify({ schema: 1, written_at: OLD_TS, entries: { status: fixtureEntries.status } }));
    const loaded5 = dc.loadPersistedEntries(SUBS);
    ok('S5 a partial snapshot loads only the sub that is actually present',
      loaded5 && loaded5.status && !loaded5['needs-me'] && !loaded5.backlog,
      JSON.stringify(loaded5));

    // S6 — requirement (d): a PERSISTED ERROR entry (rc!=0) round-trips
    // exactly — persistence must never smooth a known failure into a fake
    // success.
    const errorEntries = {};
    SUBS.forEach((sub) => {
      errorEntries[sub] = { data: null, rc: 124, stderr_tail: 'nl ' + sub + ' timed out after 180000ms (child tree killed)', derived_at: OLD_TS };
    });
    fs.writeFileSync(p1, JSON.stringify({ schema: 1, written_at: OLD_TS, entries: errorEntries }));
    const loaded6 = dc.loadPersistedEntries(SUBS);
    ok('S6 a persisted ERROR entry (rc!=0) is honestly reloaded as an error, not smoothed into a fake success (requirement (d))',
      loaded6 && loaded6.status.rc === 124 && loaded6.status.data === null &&
      /timed out/.test(loaded6.status.stderr_tail),
      JSON.stringify(loaded6 && loaded6.status));

    // S7/S8 — persistEntries: atomic write, parent-dir creation, no leftover
    // tmp files, and the round-trip is byte-faithful.
    const p2 = path.join(tmp, 'nested', 'deeper', 'part1b-snapshot.json'); // parent dir does NOT exist yet
    process.env.OBS_DERIVE_SNAPSHOT_PATH = p2;
    ok('S7 the snapshot parent directory does not exist yet (precondition)', !fs.existsSync(path.dirname(p2)));
    const liveEntries = {};
    SUBS.forEach((sub) => { liveEntries[sub] = { data: { oracle: 'live-' + sub }, rc: 0, stderr_tail: '', derived_at: '2026-08-04T12:00:00.000Z', source: 'live' }; });
    dc.persistEntries(liveEntries);
    ok('S7b persistEntries creates the missing parent directory', fs.existsSync(path.dirname(p2)));
    ok('S7c the final snapshot file exists after persistEntries', fs.existsSync(p2));
    const leftoverTmp = fs.readdirSync(path.dirname(p2)).filter((f) => f.indexOf('.tmp-') !== -1);
    ok('S7d no leftover .tmp-* file remains after a successful persist (atomic tmp+rename, never a torn file)',
      leftoverTmp.length === 0, JSON.stringify(leftoverTmp));
    const roundTrip = JSON.parse(fs.readFileSync(p2, 'utf8'));
    ok('S8 the persisted file parses back with schema:1 and a written_at stamp', roundTrip.schema === 1 && !!roundTrip.written_at);
    ok('S8b the persisted file carries every subcommand\'s entry byte-faithfully',
      SUBS.every((s) => roundTrip.entries[s] && roundTrip.entries[s].data.oracle === 'live-' + s));

    // S8c — persistEntries never throws even when the target path itself is
    // unwritable-by-construction (e.g. a path component is actually a FILE,
    // not a directory) — best-effort, matching every other on-disk writer in
    // this codebase.
    const blockerFile = path.join(tmp, 'blocker-is-a-file');
    fs.writeFileSync(blockerFile, 'x');
    process.env.OBS_DERIVE_SNAPSHOT_PATH = path.join(blockerFile, 'snapshot.json'); // parent "dir" is actually a file
    let threwS8c = false;
    try { dc.persistEntries(liveEntries); } catch (_) { threwS8c = true; }
    ok('S8c persistEntries degrades gracefully (never throws) when its target is unwritable', !threwS8c);

    // ================================================================
    // PART 2 — DeriveCache construction: instant cold-start serve, then a
    // real refreshAll() flips source to 'live' and re-persists.
    // ================================================================
    const p3 = path.join(tmp, 'part2-snapshot.json');
    process.env.OBS_DERIVE_SNAPSHOT_PATH = p3;
    const coldEntries = {};
    SUBS.forEach((sub) => { coldEntries[sub] = { data: { oracle: 'cold-' + sub }, rc: 0, stderr_tail: '', derived_at: OLD_TS }; });
    fs.mkdirSync(path.dirname(p3), { recursive: true });
    fs.writeFileSync(p3, JSON.stringify({ schema: 1, written_at: OLD_TS, entries: coldEntries }));

    // NL_BIN stub for this part: answers every subcommand with LIVE fixture
    // data DISTINCT from the cold snapshot (so a flip from cold->live data is
    // unambiguous), and sleeps 1.5s first so the "instant serve" assertion
    // below (S9, taken with ZERO await between construction and the read) is
    // not just winning a race by luck — matches server.selftest.js's own
    // SLOW_SENTINEL idiom for proving an async-not-blocking property.
    const stubPath = path.join(tmp, 'nl-stub-part2.sh');
    fs.writeFileSync(stubPath, [
      '#!/bin/bash',
      'set -u',
      'sub="${1:-}"; shift || true',
      'sleep 1.5',
      'echo "{\\"schema\\":1,\\"oracle\\":\\"live-$sub\\"}"',
    ].join('\n'));
    fs.chmodSync(stubPath, 0o755);
    process.env.NL_BIN = stubPath;
    process.env.NL_DERIVE_LIB = stubPath; // health's `source ... && od_harness_health` — irrelevant here, health isn't asserted on in Part 2

    const cache2 = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    // S9 — construction alone (no refreshAll() called yet) serves the
    // persisted snapshot's data INSTANTLY.
    ok('S9 a fresh DeriveCache instantly serves the persisted snapshot\'s data at construction, before any refresh has run',
      cache2.get('status').data && cache2.get('status').data.oracle === 'cold-status',
      JSON.stringify(cache2.get('status')));
    ok('S9b the instantly-served entry carries source:"snapshot"', cache2.get('status').source === 'snapshot');
    ok('S9c the instantly-served entry\'s derived_at is the OLD snapshot timestamp, not "now" (requirement (c))',
      cache2.get('status').derived_at === OLD_TS, cache2.get('status').derived_at);
    ok('S9d rc is carried through from the snapshot (0, not the null "still loading" sentinel)', cache2.get('status').rc === 0);

    // S10 — a real refreshAll() (against the slow stub above) eventually
    // flips source to 'live' and replaces the data.
    const refreshPromise = cache2.refreshAll();
    ok('S10 immediately after calling refreshAll(), the OLD snapshot data is still what get() returns (proves the live derivation runs in the BACKGROUND, not blocking the read)',
      cache2.get('status').data.oracle === 'cold-status' && cache2.get('status').source === 'snapshot');
    await refreshPromise;
    ok('S10b once refreshAll() settles, source flips to "live"', cache2.get('status').source === 'live');
    ok('S10c once refreshAll() settles, the data reflects the LIVE derivation, not the stale snapshot',
      cache2.get('status').data.oracle === 'live-status', JSON.stringify(cache2.get('status').data));

    // S11/S12 — the settled cycle re-persisted to disk; a FRESH DeriveCache
    // constructed against the SAME path now cold-starts on the LIVE data
    // (full round trip: snapshot -> live -> persisted -> snapshot again).
    const onDiskAfterCycle = JSON.parse(fs.readFileSync(p3, 'utf8'));
    ok('S11 the settled refreshAll() cycle re-persisted the live data to disk',
      onDiskAfterCycle.entries.status.data.oracle === 'live-status', JSON.stringify(onDiskAfterCycle.entries.status));
    const cache3 = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    ok('S12 a SECOND fresh DeriveCache cold-starts on the just-persisted live data (full round trip proven)',
      cache3.get('status').data.oracle === 'live-status' && cache3.get('status').source === 'snapshot',
      JSON.stringify(cache3.get('status')));

    // S13 — requirement (d) proven at the DeriveCache level too: if the
    // LAST live attempt failed, the re-persisted snapshot honestly says so,
    // and the next cold start serves that same honest error.
    const failStubPath = path.join(tmp, 'nl-stub-fail.sh');
    fs.writeFileSync(failStubPath, ['#!/bin/bash', 'echo "simulated failure" >&2', 'exit 7'].join('\n'));
    fs.chmodSync(failStubPath, 0o755);
    process.env.NL_BIN = failStubPath;
    const p4 = path.join(tmp, 'part2b-snapshot.json');
    process.env.OBS_DERIVE_SNAPSHOT_PATH = p4;
    const cache4 = new dc.DeriveCache({ refreshIntervalMs: 999999 }); // no snapshot yet -> null placeholders
    await cache4.refreshAll();
    ok('S13 a live refresh failure (rc!=0) is what gets persisted (never smoothed away)',
      cache4.get('status').rc !== 0, cache4.get('status').rc);
    const cache5 = new dc.DeriveCache({ refreshIntervalMs: 999999 });
    ok('S13b the NEXT cold start honestly re-serves that same failure (requirement (d): persistence is not a license to hide a failing derivation)',
      cache5.get('status').rc !== 0 && cache5.get('status').source === 'snapshot',
      JSON.stringify(cache5.get('status')));

    // ================================================================
    // PART 3 — the real user-facing path: HTTP GET against a live server.js
    // instance (constitution §4: exercise the actual path, not components).
    // ================================================================
    delete require.cache[require.resolve('./reconciler.js')];
    delete require.cache[require.resolve('./auditor.js')];
    delete require.cache[require.resolve('./state-watch.js')];
    delete require.cache[require.resolve('./derive-cache.js')];
    delete require.cache[require.resolve('./server.js')];

    const p5 = path.join(tmp, 'part3-snapshot.json');
    const SUBS3 = Object.keys(require('./derive-cache.js').SUBCOMMANDS);
    const seedEntries = {};
    SUBS3.forEach((sub) => {
      seedEntries[sub] = { data: { schema: 1, oracle: 'seed-' + sub }, rc: 0, stderr_tail: '', derived_at: '2026-07-15T09:00:00.000Z' };
    });
    fs.mkdirSync(path.dirname(p5), { recursive: true });
    fs.writeFileSync(p5, JSON.stringify({ schema: 1, written_at: '2026-07-15T09:00:00.000Z', entries: seedEntries }));

    // A stub that sleeps 2.5s before answering EVERY subcommand — long
    // enough that the immediate GET below (fired with zero artificial
    // delay right after require('./server.js')) unambiguously beats it.
    const slowStub = path.join(tmp, 'nl-stub-part3.sh');
    fs.writeFileSync(slowStub, [
      '#!/bin/bash',
      'set -u',
      'sub="${1:-}"; shift || true',
      'sleep 1.5',
      'echo "{\\"schema\\":1,\\"oracle\\":\\"fresh-$sub\\"}"',
    ].join('\n'));
    fs.chmodSync(slowStub, 0o755);
    const slowDeriveLib = path.join(tmp, 'derive-lib-stub-part3.sh');
    fs.writeFileSync(slowDeriveLib, [
      '#!/bin/bash',
      'od_harness_health() { sleep 1.5; echo \'{"schema":1,"oracle":"fresh-health"}\'; }',
    ].join('\n'));
    fs.chmodSync(slowDeriveLib, 0o755);

    process.env.NL_BIN = slowStub;
    process.env.NL_DERIVE_LIB = slowDeriveLib;
    process.env.OBS_DERIVE_SNAPSHOT_PATH = p5;
    process.env.CTREE_PORT = String(19733 + (process.pid % 1000));
    const PORT3 = Number(process.env.CTREE_PORT);
    process.env.OBS_REFRESH_MS = '999999';
    process.env.AUDITOR_DISABLED = '1';
    process.env.OBS_WATCH_DISABLED = '1';

    const { server: server3, cache: cache3http } = require('./server.js');

    // S14 — the FIRST GET, fired immediately (no settle-wait), must render
    // real content from the snapshot — never the loading state — while the
    // 2.5s-slow live refresh is still in flight in the background. A short,
    // fixed grace delay (not a settle-poll) just lets the HTTP listener
    // itself finish binding; it is far shorter than the 2.5s stub sleep, so
    // this is still "before the live refresh could possibly have settled".
    await new Promise((resolve) => setTimeout(resolve, 200));
    const immediate = await httpGet(PORT3, '/api/pane/status');
    ok('S14 GET /api/pane/status immediately after a cold start renders REAL content (rc=0, real data), not a loading state — requirement (b)',
      immediate.json && immediate.json.rc === 0 && immediate.json.data && immediate.json.data.oracle === 'seed-status',
      JSON.stringify(immediate.json));
    ok('S14b the immediate response is explicitly marked source:"snapshot" so the client can tell it has not been revalidated yet — requirement (c)',
      immediate.json && immediate.json.source === 'snapshot', JSON.stringify(immediate.json && immediate.json.source));
    ok('S14c derived_at on the immediate response is the OLD seed timestamp, not "now"',
      immediate.json && immediate.json.derived_at === '2026-07-15T09:00:00.000Z', immediate.json && immediate.json.derived_at);

    const healthImmediate = await httpGet(PORT3, '/api/health');
    ok('S15 /api/health\'s snapshot diagnostics report every pane still snapshot-sourced immediately after cold start',
      healthImmediate.json && healthImmediate.json.snapshot && healthImmediate.json.snapshot.panes_from_snapshot === SUBS3.length,
      JSON.stringify(healthImmediate.json && healthImmediate.json.snapshot));
    ok('S15b /api/health names the resolved snapshot path (be-the-interface: an operator can go look at the file)',
      healthImmediate.json && healthImmediate.json.snapshot && healthImmediate.json.snapshot.path === p5,
      JSON.stringify(healthImmediate.json && healthImmediate.json.snapshot));

    // S16 — once the slow live refresh actually settles, the SAME pane
    // flips to live, fresh data. Waits for the WHOLE cycle (every sub, both
    // lanes — see derive-cache.js's two-lane refreshAll), not just 'status'
    // (which is merely the first member of its lane to settle — the other
    // five subs, split across two serially-chained lanes, legitimately
    // still take longer; state-watch.selftest.js's own waitAllAdvanced
    // discipline is the same fix for the same shape of undercounting bug).
    const settled = await waitUntil(() => SUBS3.every((s) => cache3http.get(s).source === 'live'), 20000);
    ok('S16 the background live refresh eventually settles (ALL panes) and flips source to "live"', settled,
      JSON.stringify(SUBS3.map((s) => [s, cache3http.get(s).source])));
    const afterLive = await httpGet(PORT3, '/api/pane/status');
    ok('S16b once live, the pane serves the FRESH derivation, not the stale seed',
      afterLive.json && afterLive.json.data && afterLive.json.data.oracle === 'fresh-status' && afterLive.json.source === 'live',
      JSON.stringify(afterLive.json));

    const healthAfter = await httpGet(PORT3, '/api/health');
    ok('S17 /api/health\'s panes_from_snapshot counts down to 0 once every pane has revalidated live',
      healthAfter.json && healthAfter.json.snapshot && healthAfter.json.snapshot.panes_from_snapshot === 0,
      JSON.stringify(healthAfter.json && healthAfter.json.snapshot));

    await new Promise((resolve) => server3.close(resolve));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
    delete process.env.OBS_DERIVE_SNAPSHOT_PATH;
  }

  console.log('');
  console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
  process.exit(FAILED === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL: ' + (e && e.stack || e));
  process.exit(1);
});
