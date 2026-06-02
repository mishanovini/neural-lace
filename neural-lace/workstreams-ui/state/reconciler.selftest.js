'use strict';
// Component B — reconciler self-test. Pure (no I/O); run: `node reconciler.selftest.js`.
// Covers the DoD scenarios from docs/plans/orchestrator-reconciler-component-b.md
// Testing Strategy: S1 cascade→spawnable, S2 stall detection, S3 slot mgmt,
// S4 pending-Misha, S5 idempotency, S6 spawn-command construction.

const { reconcile, buildSpawnCommand } = require('./reconciler.js');

let pass = 0, fail = 0;
function ok(cond, msg) {
  if (cond) { pass++; console.log('PASS ' + msg); }
  else { fail++; console.log('FAIL ' + msg); }
}

// ---- snapshot builders ------------------------------------------------------
function item(id, kind, o) {
  return Object.assign({ item_id: id, kind: kind, text: id + ' text', checked: false }, o || {});
}
function node(id, items, o) {
  return Object.assign({ node_id: id, title: id + ' branch', items: items, bound_sessions: [] }, o || {});
}
function snap(nodes) { return { nodes: nodes, backlog: [] }; }

const NOW = 1_700_000_000_000; // fixed epoch ms for determinism

// ── S1: completion cascade → spawnable ──────────────────────────────────────
(function S1() {
  const A = item('A', 'action', { state: 'shipped', checked: true });
  const B = item('B', 'action', { state: 'blocked', blocked_on: 'A' });
  const r = reconcile({
    snapshot: snap([node('N1', [A, B])]),
    liveSessions: [], claims: {}, now: NOW,
    config: { maxConcurrent: 4, machineId: 'local' },
  });
  ok(r.cascades.length === 1 && r.cascades[0].item_id === 'B' && r.cascades[0].unblocked_by === 'A',
    'S1 cascade: B unblocked by A');
  ok(r.emittedEvents.some(function (e) { return e.type === 'item-committed' && e.item_id === 'B'; }),
    'S1 emits item-committed for B');
  ok(r.spawnable.some(function (s) { return s.item_id === 'B'; }), 'S1 B is spawnable');
  ok(r.spawnPlan.some(function (p) { return p.item_id === 'B'; }), 'S1 free slot → B in spawnPlan');
  ok(r.spawnable.find(function (s) { return s.item_id === 'B'; }).cascaded_this_pass === true,
    'S1 B tagged cascaded_this_pass (unblock-recency priority boost)');
})();

// ── S2: stall detection (in-flight, all bound sessions stale → orphan) ───────
(function S2() {
  const C = item('C', 'action', {}); // no lifecycle state, unchecked → in-flight (node is bound)
  const n = node('N2', [C], { bound_sessions: ['sess-stale'] });
  const r = reconcile({
    snapshot: snap([n]),
    liveSessions: [{ session_id: 'sess-stale', fresh: false, age_min: 120 }],
    claims: { C: { machine_id: 'local', claimed_at: NOW - 3 * 3600_000, lease_ttl_min: 30 } },
    now: NOW, config: { maxConcurrent: 4, machineId: 'local', stallMinutes: 60 },
  });
  ok(r.orphans.length === 1 && r.orphans[0].item_id === 'C', 'S2 orphan: C stalled');
  ok(r.orphans[0].oldest_age_min === 120, 'S2 orphan oldest_age_min reported');
  ok(r.emittedEvents.some(function (e) { return e.type === 'claim-released' && e.item_id === 'C'; }),
    'S2 emits claim-released for orphaned C');
  // A FRESH bound session must NOT orphan.
  const r2 = reconcile({
    snapshot: snap([node('N2b', [item('D', 'action', {})], { bound_sessions: ['sess-fresh'] })]),
    liveSessions: [{ session_id: 'sess-fresh', fresh: true, age_min: 2 }],
    claims: {}, now: NOW, config: { machineId: 'local', stallMinutes: 60 },
  });
  ok(r2.orphans.length === 0, 'S2 fresh bound session is NOT orphaned');
})();

// ── S3: slot management ──────────────────────────────────────────────────────
(function S3() {
  const items = [];
  for (let i = 0; i < 6; i++) items.push(item('K' + i, 'action', { state: 'committed' }));
  const r = reconcile({
    snapshot: snap([node('N3', items)]),
    liveSessions: [
      { session_id: 's1', fresh: true, age_min: 1 },
      { session_id: 's2', fresh: true, age_min: 1 },
    ],
    claims: {}, now: NOW, config: { maxConcurrent: 4, machineId: 'local' },
  });
  ok(r.liveCount === 2, 'S3 liveCount=2');
  ok(r.freeSlots === 2, 'S3 freeSlots = 4 - 2 = 2');
  ok(r.spawnable.length === 6, 'S3 6 committed items spawnable');
  ok(r.spawnPlan.length === 2, 'S3 spawnPlan fills exactly the 2 free slots');
  ok(r.spawnDeferredCount === 4, 'S3 4 deferred (no silent cap)');
})();

// ── S4: pending-Misha surfacing ──────────────────────────────────────────────
(function S4() {
  // Regression for the real-data class (Phase-3 lifecycle-backfill sets EVERY
  // unchecked item to state:'committed', incl. decisions/questions): a COMMITTED
  // decision/question must still be pending-Misha-only, never spawnable.
  const dec = item('DEC', 'decision', { state: 'committed' }); // committed but → needs Misha
  const q = item('Q', 'question', { state: 'committed' });     // committed but → needs Misha
  const act = item('ACT', 'action', { state: 'committed' });   // spawnable, NOT pending-Misha
  const r = reconcile({
    snapshot: snap([node('N4', [dec, q, act])]),
    liveSessions: [], claims: {}, now: NOW, config: { machineId: 'local' },
  });
  ok(r.pendingMisha.some(function (m) { return m.item_id === 'DEC'; }), 'S4 decision → pendingMisha');
  ok(r.pendingMisha.some(function (m) { return m.item_id === 'Q'; }), 'S4 question → pendingMisha');
  ok(!r.spawnable.some(function (s) { return s.item_id === 'DEC' || s.item_id === 'Q'; }),
    'S4 decision/question are NOT spawnable');
  ok(r.spawnable.some(function (s) { return s.item_id === 'ACT'; }), 'S4 committed action IS spawnable');
  // retry-exhausted item → pending-Misha (not spawnable)
  const r2 = reconcile({
    snapshot: snap([node('N4b', [item('RX', 'action', { state: 'committed', retry_count: 2 })])]),
    liveSessions: [], claims: {}, now: NOW, config: { machineId: 'local', retryMax: 2 },
  });
  ok(r2.pendingMisha.some(function (m) { return m.item_id === 'RX'; }), 'S4 retry-exhausted → pendingMisha');
  ok(!r2.spawnable.some(function (s) { return s.item_id === 'RX'; }), 'S4 retry-exhausted NOT spawnable');
})();

// ── S5: idempotency (cascade fires once) ─────────────────────────────────────
(function S5() {
  const A = item('A', 'action', { state: 'shipped', checked: true });
  const B = item('B', 'action', { state: 'blocked', blocked_on: 'A' });
  const s = snap([node('N5', [A, B])]);
  const cfg = { maxConcurrent: 4, machineId: 'local' };
  const r1 = reconcile({ snapshot: s, liveSessions: [], claims: {}, now: NOW, config: cfg });
  ok(r1.cascades.length === 1, 'S5 first pass: 1 cascade');
  // Apply the emitted item-committed exactly as the reducer would: state→committed,
  // blocked_on cleared.
  B.state = 'committed'; B.blocked_on = null;
  const r2 = reconcile({ snapshot: s, liveSessions: [], claims: {}, now: NOW, config: cfg });
  ok(r2.cascades.length === 0, 'S5 second pass: 0 cascades (idempotent)');
  ok(!r2.emittedEvents.some(function (e) { return e.type === 'item-committed'; }),
    'S5 second pass emits no cascade event');
  ok(r2.spawnable.some(function (s2) { return s2.item_id === 'B'; }),
    'S5 B still spawnable on second pass (committed)');
})();

// ── S6: spawn-command construction (Component-A DoD carried inline) ──────────
(function S6() {
  const A = item('A', 'action', {
    state: 'committed',
    text: 'Wire evals into the PR workflow',
    details: { dod: 'CI runs evals on every PR and blocks merge on failure',
               verification: 'open a test PR; observe the eval check fail then pass' },
  });
  const r = reconcile({
    snapshot: snap([node('N6', [A])]),
    liveSessions: [], claims: {}, now: NOW,
    config: { maxConcurrent: 4, machineId: 'local',
              runnerKindMap: { action: 'headless-local' } }, // arm executable path
  });
  const plan = r.spawnPlan[0];
  ok(plan && plan.runner_kind === 'headless-local', 'S6 runner_kind from config map');
  ok(plan && plan.executable === true, 'S6 headless-local → executable');
  ok(plan && Array.isArray(plan.argv) && plan.argv.indexOf('-p') !== -1, 'S6 argv has -p (print mode)');
  ok(plan && plan.prompt.indexOf('Definition of done: CI runs evals') !== -1, 'S6 prompt carries the DoD');
  ok(plan && plan.prompt.indexOf('Verification command / evidence:') !== -1, 'S6 prompt carries verification');
  ok(plan && plan.prompt.indexOf('disqualify') !== -1 || plan.prompt.indexOf('proxy signals') !== -1,
    'S6 prompt carries inline /goal-style anti-proxy audit clause');
  // A non-executable runner_kind (code-task) is surfaced, not launchable.
  const r2 = reconcile({
    snapshot: snap([node('N6b', [item('CT', 'action', { state: 'committed' })])]),
    liveSessions: [], claims: {}, now: NOW, config: { machineId: 'local' }, // default map → code-task
  });
  ok(r2.spawnPlan[0] && r2.spawnPlan[0].executable === false,
    'S6 code-task runner_kind → executable=false (surfaced for Dispatch, not launched)');
  // buildSpawnCommand directly:
  const cmd = buildSpawnCommand({ runner_kind: 'headless-local', prompt: 'hello' }, { machineId: 'local' });
  ok(cmd.executable === true && cmd.argv[1] === 'hello', 'S6 buildSpawnCommand argv shape');
})();

// ── S7: empty / no-lifecycle state → clean no-op (today's real state) ────────
(function S7() {
  // 50 nodes of plain items with no lifecycle state, none checked → nothing
  // spawnable, no cascade, no orphan. This mirrors production today (0 lifecycle
  // events until Phase 3 ships).
  const nodes = [];
  for (let i = 0; i < 5; i++) nodes.push(node('P' + i, [item('p' + i, 'action', {})]));
  const r = reconcile({ snapshot: snap(nodes), liveSessions: [], claims: {}, now: NOW, config: { machineId: 'local' } });
  ok(r.cascades.length === 0 && r.orphans.length === 0 && r.spawnable.length === 0 && r.emittedEvents.length === 0,
    'S7 no-lifecycle state → clean no-op (cascade/orphan/spawnable/events all empty)');
})();

console.log('\n── reconciler.selftest: ' + pass + ' passed, ' + fail + ' failed ──');
process.exit(fail === 0 ? 0 : 1);
