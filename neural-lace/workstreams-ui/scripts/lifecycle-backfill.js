'use strict';
/* Workstreams Phase 3 — lifecycle backfill (2026-06-01).
 *
 * Walks the live snapshot and assigns explicit WorkItem lifecycle states by
 * inference, per workstreams-design-v2-2026-05-30.md §6 (Phase 3):
 *
 *   checked                         -> shipped     (render-derived; NOT emitted)
 *   unchecked + bound session       -> in-flight   (render-derived; NOT emitted)
 *   unchecked + no bound session    -> committed   (EMIT item-committed)
 *   raised, no action               -> proposed    (render-derived; folded — see below)
 *
 * Why only `committed` is EMITTED, and the other states are render-derived:
 *   The renderer (web/app.js itemState()) ALREADY derives shipped (checked),
 *   in-flight (default for unchecked), and blocked (contested) from the legacy
 *   flags. The schema has events ONLY for committed/shipped/blocked — there is
 *   no item-in-flight or item-proposed event. So the backfill's honest,
 *   non-redundant job is to STAMP `committed` on parked items (unchecked with
 *   no live session), which REFINES the renderer's default (which would
 *   otherwise show them as "in flight"). shipped/in-flight/proposed stay
 *   render-derived — storing them would duplicate what the renderer computes.
 *
 *   `session-bound` is new in Phase 3, so NO legacy item has a bound session:
 *   bucket-2 (in-flight) is empty for existing data and bucket-3 (committed)
 *   absorbs all unchecked items. That is correct — nothing has a live session
 *   bound yet; the new emit machinery populates in-flight going forward.
 *
 *   `shipped` is intentionally NOT stamped for legacy checked items: emitting
 *   item-shipped would set shipped_ts = now, which would falsely surface every
 *   old checked item under "Recently shipped (7d)". Legacy checked items render
 *   as shipped via the renderer's checked->shipped derivation and are correctly
 *   excluded from the recently-shipped window (no shipped_ts).
 *
 * Idempotent: each emitted item-committed carries a deterministic event_id
 * (wsbf-ic-<sha1(node_id|item_id)>), so re-running --apply is a per-file no-op
 * (the store dedupes by event_id). Items already carrying an explicit
 * it.state (committed/blocked/shipped) are left alone.
 *
 * Usage:
 *   node scripts/lifecycle-backfill.js                 # dry-run (default; no writes)
 *   node scripts/lifecycle-backfill.js --apply         # emit item-committed events
 *   node scripts/lifecycle-backfill.js --apply --state <path>
 *   node scripts/lifecycle-backfill.js --self-test
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const state = require('../state/state.js');

// Session nodes are provenance, not work items — they never carry WorkItems we
// stamp. Mirrors the renderer's isSession() (sp-/ss-/sub-/sess- prefixes).
function isSessionNode(n) {
  return /^(sp-|ss-|sub-|sess-)/.test(n.node_id || '');
}

const COMMIT_REASON = 'lifecycle-backfill: parked (no bound session)';

function eventIdFor(nodeId, itemId) {
  return 'wsbf-ic-' + crypto.createHash('sha1')
    .update(String(nodeId) + '|' + String(itemId)).digest('hex').slice(0, 32);
}

// Classify one item -> { bucket, emit } where emit is the event to append (or
// null for render-derived buckets).
function classify(node, it) {
  // Already explicitly stamped (committed/blocked/shipped) -> leave alone.
  if (it.state === 'shipped' || it.state === 'committed' || it.state === 'blocked') {
    return { bucket: it.state, emit: null, reason: 'already-stamped' };
  }
  if (it.checked) return { bucket: 'shipped', emit: null, reason: 'render-derived (checked)' };
  if (it.contested) return { bucket: 'blocked', emit: null, reason: 'render-derived (contested)' };
  var bound = Array.isArray(node.bound_sessions) && node.bound_sessions.length > 0;
  if (bound) return { bucket: 'in-flight', emit: null, reason: 'render-derived (bound session)' };
  // unchecked + no bound session -> committed (the one bucket we stamp).
  return {
    bucket: 'committed',
    reason: 'no bound session',
    emit: {
      event_id: eventIdFor(node.node_id, it.item_id),
      type: 'item-committed',
      node_id: node.node_id,
      item_id: it.item_id,
      reason: COMMIT_REASON,
      actor: 'dispatch',
    },
  };
}

function planFrom(snapshot) {
  var buckets = { shipped: 0, 'in-flight': 0, committed: 0, blocked: 0, 'already-stamped': 0 };
  var emits = [];
  (snapshot.nodes || []).forEach(function (n) {
    if (isSessionNode(n)) return;
    (n.items || []).forEach(function (it) {
      var c = classify(n, it);
      if (c.reason === 'already-stamped') buckets['already-stamped']++;
      else buckets[c.bucket] = (buckets[c.bucket] || 0) + 1;
      if (c.emit) emits.push({ ev: c.emit, label: it.text, node_id: n.node_id, item_id: it.item_id });
    });
  });
  return { buckets: buckets, emits: emits, total: emits.length };
}

function emit(plan, opts) {
  var emitOpts = opts && opts.statePath ? { statePath: opts.statePath } : undefined;
  var emitted = 0;
  plan.emits.forEach(function (j) {
    state.appendEvent(j.ev, emitOpts);
    emitted++;
  });
  return { emitted: emitted, planned: plan.total };
}

// ---- CLI ----
function parseArgs(argv) {
  var a = { apply: false, statePath: null, selfTest: false };
  for (var i = 2; i < argv.length; i++) {
    if (argv[i] === '--apply') a.apply = true;
    else if (argv[i] === '--state' && argv[i + 1]) { a.statePath = argv[i + 1]; i++; }
    else if (argv[i] === '--self-test') a.selfTest = true;
  }
  return a;
}

function runCli() {
  var args = parseArgs(process.argv);
  if (args.selfTest) return runSelfTest();
  var readOpts = args.statePath ? { statePath: args.statePath } : undefined;
  var st = state.readState(readOpts);
  var p = planFrom(st.snapshot || {});
  process.stdout.write('lifecycle-backfill: inference over ' +
    ((st.snapshot && st.snapshot.nodes || []).filter(function (n) { return !isSessionNode(n); }).length) +
    ' work-item node(s)\n');
  process.stdout.write('  bucket counts (render-derived unless noted):\n');
  process.stdout.write('    shipped         ' + p.buckets['shipped'] + '   (render-derived; not emitted)\n');
  process.stdout.write('    in-flight       ' + p.buckets['in-flight'] + '   (render-derived; not emitted)\n');
  process.stdout.write('    blocked         ' + p.buckets['blocked'] + '   (render-derived; not emitted)\n');
  process.stdout.write('    committed       ' + p.buckets['committed'] + '   <- EMIT item-committed\n');
  process.stdout.write('    already-stamped ' + p.buckets['already-stamped'] + '   (explicit state present; left alone)\n');
  process.stdout.write('  planned ' + p.total + ' item-committed event(s):\n');
  p.emits.slice(0, 40).forEach(function (j) {
    var lbl = typeof j.label === 'string' ? (j.label.length > 70 ? j.label.slice(0, 70) + '…' : j.label) : '';
    process.stdout.write('    + ' + j.node_id + ' / ' + j.item_id + '  "' + lbl + '"\n');
  });
  if (p.total > 40) process.stdout.write('    …(+' + (p.total - 40) + ' more)\n');
  if (args.apply) {
    var r = emit(p, { statePath: args.statePath });
    process.stdout.write('lifecycle-backfill: EMITTED ' + r.emitted + ' / ' + r.planned + ' item-committed event(s)\n');
  } else {
    process.stdout.write('(dry-run; pass --apply to emit)\n');
  }
}

// ---- self-test --------------------------------------------------------------
function runSelfTest() {
  var os = require('os');
  var RESULTS = []; var PASS = 0, FAIL = 0;
  function check(name, cond, detail) {
    if (cond) { PASS++; RESULTS.push('  PASS  ' + name); }
    else { FAIL++; RESULTS.push('  FAIL  ' + name + (detail ? '  — ' + detail : '')); }
  }
  function freshDir() { return fs.mkdtempSync(path.join(os.tmpdir(), 'wsbf-')); }
  function cleanup(d) { try { fs.rmSync(d, { recursive: true, force: true }); } catch (_) {} }
  function optsFor(d) { return { statePath: path.join(d, 'tree-state.json'), treeId: 'global' }; }

  // B1: classifier correctness across the four buckets.
  (function B1() {
    var bound = { node_id: 'n1', bound_sessions: ['s1'], items: [] };
    var nobound = { node_id: 'n2', bound_sessions: [], items: [] };
    var okShipped = classify(nobound, { item_id: 'a', checked: true }).bucket === 'shipped';
    var okBlocked = classify(nobound, { item_id: 'b', contested: { note: 'x' } }).bucket === 'blocked';
    var okInflight = classify(bound, { item_id: 'c', checked: false }).bucket === 'in-flight';
    var okCommitted = classify(nobound, { item_id: 'd', checked: false }).bucket === 'committed';
    var committedEmits = !!classify(nobound, { item_id: 'd', checked: false }).emit;
    var inflightNoEmit = classify(bound, { item_id: 'c', checked: false }).emit === null;
    var stampedLeft = classify(nobound, { item_id: 'e', checked: false, state: 'committed' }).reason === 'already-stamped';
    check('B1 classifier: shipped/blocked/in-flight/committed + only committed emits + stamped left alone',
      okShipped && okBlocked && okInflight && okCommitted && committedEmits && inflightNoEmit && stampedLeft);
  })();

  // B2: end-to-end planFrom -> emit -> reducer stamps committed; render-derived
  // buckets untouched; session nodes skipped; idempotent on re-run.
  (function B2() {
    var dir = freshDir(); var o = optsFor(dir);
    try {
      state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'Proj' }, o);
      // parked (unchecked, no bound session) -> committed
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'parked', text: 'parked task' }, o);
      // checked -> shipped (render-derived; not emitted)
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'done', text: 'done task' }, o);
      state.appendEvent({ type: 'action-done', node_id: 'n1', item_id: 'done' }, o);
      // bound session + unchecked on a NON-session work node -> in-flight
      // (render-derived; not emitted). NB: planFrom SKIPS sp-/ss-/sub-/sess-
      // session nodes (provenance), so the in-flight branch is only reachable
      // for an item on a real work node that itself carries a bound session.
      state.appendEvent({ type: 'branch-opened', node_id: 'n2', parent_id: 'n1', title: 'work' }, o);
      state.appendEvent({ type: 'session-bound', node_id: 'n2', session_id: 'sess-1' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n2', item_id: 'flying', text: 'in flight' }, o);

      var snap0 = state.readState(o).snapshot;
      var p = planFrom(snap0);
      var planOk = p.total === 1 && p.emits[0].item_id === 'parked'
        && p.buckets['shipped'] === 1 && p.buckets['in-flight'] === 1 && p.buckets['committed'] === 1;

      emit(p, { statePath: o.statePath });
      var snap1 = state.readState(o).snapshot;
      var n1 = snap1.nodes.find(function (n) { return n.node_id === 'n1'; });
      var parked = n1.items.find(function (it) { return it.item_id === 'parked'; });
      var done = n1.items.find(function (it) { return it.item_id === 'done'; });
      var spx = snap1.nodes.find(function (n) { return n.node_id === 'n2'; });
      var flying = spx.items.find(function (it) { return it.item_id === 'flying'; });
      var appliedOk = parked.state === 'committed'      // stamped
        && done.state === undefined && done.checked === true   // shipped render-derived, not stamped
        && flying.state === undefined;                          // in-flight render-derived, not stamped

      // idempotent: re-run emits same deterministic event_id -> no new committed events
      emit(p, { statePath: o.statePath });
      var events2 = state.readState(o).events.filter(function (e) { return e.type === 'item-committed'; });
      var idempotent = events2.length === 1;

      check('B2 e2e: parked->committed; shipped/in-flight untouched; session node skipped; idempotent',
        planOk && appliedOk && idempotent,
        'planOk=' + planOk + ' appliedOk=' + appliedOk + ' idempotent=' + idempotent + ' committedEvents=' + events2.length);
    } catch (e) { check('B2 end-to-end', false, e.message); }
    finally { cleanup(dir); }
  })();

  // B3: dry-run does not write (no item-committed events appended).
  (function B3() {
    var dir = freshDir(); var o = optsFor(dir);
    try {
      state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'P' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a', text: 'parked' }, o);
      var p = planFrom(state.readState(o).snapshot);
      // intentionally do NOT emit
      var committed = state.readState(o).events.filter(function (e) { return e.type === 'item-committed'; });
      check('B3 dry-run plans but does not write', p.total === 1 && committed.length === 0);
    } catch (e) { check('B3 dry-run', false, e.message); }
    finally { cleanup(dir); }
  })();

  process.stdout.write('\nlifecycle-backfill self-test\n');
  process.stdout.write(RESULTS.join('\n') + '\n');
  process.stdout.write('\n' + PASS + ' passed, ' + FAIL + ' failed\n');
  process.exit(FAIL === 0 ? 0 : 1);
}

module.exports = { classify, planFrom, emit, eventIdFor, isSessionNode };

if (require.main === module) runCli();
