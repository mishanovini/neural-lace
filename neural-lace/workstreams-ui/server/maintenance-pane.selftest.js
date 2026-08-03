'use strict';
// maintenance-pane.selftest.js — sandboxed self-test for the
// /api/pane/maintenance-budget endpoint (harness-execution-redesign-2026-08
// Task 3). A direct file read of nl-maintenance.sh's dashboard snapshot
// (buildMaintenancePane() in server.js), independent of the DeriveCache/
// `nl <sub> --json` machinery the six sketch-question panes use — so this
// suite is deliberately standalone rather than folded into the much larger
// server.selftest.js (matches the existing per-concern *.selftest.js
// convention: inbox-routes.selftest.js, requests-routes.selftest.js, etc.).
//
// Run: `node server/maintenance-pane.selftest.js`. Exit 0 PASS / 1 FAIL.

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

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'nl-maint-pane-st-'));

  // A stub NL_BIN that answers every subcommand with a trivial empty-ish
  // payload — this endpoint doesn't consume it, but server.js's cache.start()
  // fires refreshAll() on require, so a real `nl` binary must not be
  // depended on for this self-test to be hermetic.
  const stubPath = path.join(tmp, 'nl-stub.sh');
  fs.writeFileSync(stubPath, [
    '#!/bin/bash',
    'echo "{\\"schema\\":1}"',
  ].join('\n'));
  fs.chmodSync(stubPath, 0o755);

  process.env.NL_BIN = stubPath;
  process.env.HOME = tmp;
  process.env.AUDITOR_DISABLED = '1';
  process.env.OBS_REFRESH_MS = '999999';
  const PORT = 18733 + (process.pid % 1000);
  process.env.CTREE_PORT = String(PORT);

  delete require.cache[require.resolve('./derive-cache.js')];
  delete require.cache[require.resolve('./reconciler.js')];
  delete require.cache[require.resolve('./auditor.js')];
  delete require.cache[require.resolve('./server.js')];

  try {
    // ---- Scenario 1: no snapshot on disk yet -> honest rc!=0 empty state,
    // never a silent blank pane (ux-review amendment 1 discipline, same as
    // every other /api/pane/* endpoint).
    const { server } = require('./server.js');
    await new Promise((resolve) => setTimeout(resolve, 300));
    const r1 = await httpGet(PORT, '/api/pane/maintenance-budget');
    ok('S1 endpoint responds 200 (envelope-level success even when data is absent)', r1.status === 200, 'status=' + r1.status);
    ok('S1 rc=1 (no snapshot yet) is carried through explicitly', r1.json && r1.json.rc === 1, JSON.stringify(r1.json));
    ok('S1 data is null, not a fabricated empty object', r1.json && r1.json.data === null, JSON.stringify(r1.json));
    ok('S1 stderr_tail names the exact fix command', r1.json && /nl-maintenance\.sh --tick/.test(r1.json.stderr_tail || ''), JSON.stringify(r1.json && r1.json.stderr_tail));

    // ---- Scenario 2: a real snapshot exists -> served verbatim, schema
    // intact, rc=0.
    const snapDir = path.join(tmp, '.claude', 'state', 'nl-maintenance', 'snapshots');
    fs.mkdirSync(snapDir, { recursive: true });
    const fixture = {
      schema: 1,
      generated_at: '2026-08-03T00:00:00Z',
      generated_at_epoch: 1785715200,
      inventory: {
        hooks_per_bash: { template: 25, live: 25, target: 6 },
        sessionstart_spawns: { template: 8, live: 8, target: 2 },
        legacy_scheduled_tasks_enabled: { count: 0, target_max: 2 },
      },
      cost_budget: [{ id: 'coord-sync', managed_by: 'nl-maintenance', declared_cadence_seconds: 60, spawn_cost_ms: 152, fires_per_day: 1440, est_spawn_ms_per_day: 218880 }],
      gate_friction: { available: false, rows: [] },
    };
    fs.writeFileSync(path.join(snapDir, 'dashboard.json'), JSON.stringify(fixture));

    const r2 = await httpGet(PORT, '/api/pane/maintenance-budget');
    ok('S2 rc=0 once a real snapshot exists', r2.json && r2.json.rc === 0, JSON.stringify(r2.json));
    ok('S2 data.inventory.hooks_per_bash.live reflects the fixture verbatim (no server-side re-derivation)',
      r2.json && r2.json.data && r2.json.data.inventory.hooks_per_bash.live === 25, JSON.stringify(r2.json));
    ok('S2 data.cost_budget carries the fixture rows through unmodified',
      r2.json && Array.isArray(r2.json.data.cost_budget) && r2.json.data.cost_budget[0].id === 'coord-sync', JSON.stringify(r2.json));
    ok('S2 derived_at mirrors the snapshot\'s own generated_at (not a server-side re-stamp)',
      r2.json && r2.json.derived_at === '2026-08-03T00:00:00Z', JSON.stringify(r2.json));

    // ---- Scenario 3: malformed JSON on disk -> honest rc!=0, never a crash.
    fs.writeFileSync(path.join(snapDir, 'dashboard.json'), '{not valid json');
    const r3 = await httpGet(PORT, '/api/pane/maintenance-budget');
    ok('S3 malformed snapshot -> rc=1, server stays up (no crash)', r3.status === 200 && r3.json && r3.json.rc === 1, JSON.stringify(r3.json));

    await new Promise((resolve) => server.close(resolve));
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
