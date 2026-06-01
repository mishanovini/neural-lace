'use strict';
/* conv-tree-ui v1.1.2 item 34 — priority backfill (P1..P3 only; P5 default
 * = unassigned, no event emitted).
 *
 * Enumerates every OPEN action/decision/question item AND backlog entry in
 * the state file and emits one additive `priority-assigned` event per item
 * whose text matches a Tier-1/2/3 pattern from Misha's spec
 * (actor='dispatch'; LWW; idempotent on re-run — reducer treats the same
 * priority for the same target_id as a no-op).
 *
 * Categories (verbatim from Misha 2026-05-19):
 *   P1: TCPA 8 decisions; TWLO-006 (twilio_config wire); A2P portal paste
 *       (Blocks A-F); Phase 6 plan ratification.
 *   P2: RESEND_FROM_EMAIL + DKIM; npx supabase db push (migration 137);
 *       Wizard copy rewrite (JOURNEY-023).
 *   P3: PRIV-003 (CSV consent); A11Y-001 (WCAG-AA scope);
 *       JOURNEY-009 (voice setup signal); JOURNEY-023 (wizard content);
 *       Phase 7 DR-001 + DR-002.
 *   Default P5 (no event emitted): everything else.
 *
 * Usage:
 *   node state/backfill-priorities.js                 # dry-run (default; no writes)
 *   node state/backfill-priorities.js --apply         # emit priority-assigned events
 *   node state/backfill-priorities.js --apply --state <path>
 *   node state/backfill-priorities.js --self-test
 */
const fs = require('fs');
const path = require('path');
const state = require('./state.js');

// ---- pattern map: regex (case-insensitive) → priority -----------------------
// Order matters: first match wins. Anchored to common keywords from Misha's
// canonical list so the matcher is precise enough to avoid false positives.
const PATTERNS = [
  // P1 — must-do, blocking
  { p: 1, re: /\btcpa\b/i },                                  // TCPA 8 decisions
  { p: 1, re: /\btwlo-?006\b|twilio_config|twilio config/i }, // TWLO-006 twilio_config wire
  { p: 1, re: /a2p (portal )?paste|a2p .*block\s*[a-f]\b/i }, // A2P portal paste blocks A-F
  { p: 1, re: /phase\s*6.*ratif|ratif.*phase\s*6/i },         // Phase 6 plan ratification
  // P2 — important, near-term
  { p: 2, re: /resend.*dkim|resend_from_email/i },            // RESEND_FROM_EMAIL + DKIM
  { p: 2, re: /supabase db push|migration\s*137\b/i },        // supabase migration 137
  { p: 2, re: /wizard copy rewrite|journey-?023/i },          // Wizard copy rewrite JOURNEY-023
  // P3 — meaningful, not urgent
  { p: 3, re: /\bpriv-?003\b/i },                             // CSV consent
  { p: 3, re: /\ba11y-?001\b/i },                             // WCAG-AA scope
  { p: 3, re: /\bjourney-?009\b/i },                          // voice setup signal
  { p: 3, re: /\bjourney-?023\b/i },                          // wizard content (also P2 above — first match wins)
  { p: 3, re: /phase\s*7.*dr-?00[12]|dr-?00[12].*phase\s*7/i },// Phase 7 DR-001/002
];

function matchPriority(text) {
  if (typeof text !== 'string' || !text) return null;
  for (var i = 0; i < PATTERNS.length; i++) {
    if (PATTERNS[i].re.test(text)) return PATTERNS[i].p;
  }
  return null; // no match → leaves P5 default
}

function planFrom(snapshot) {
  var plan = [];
  // Open action/decision/question items on each node.
  (snapshot.nodes || []).forEach(function (n) {
    (n.items || []).forEach(function (it) {
      // Already-effectively-prioritised items (P1..P4) are no-ops on re-run
      // via LWW, but emitting again is harmless. We still emit only when our
      // matcher resolves a non-P5 priority.
      var p = matchPriority(it.text);
      if (p != null) {
        plan.push({ target_id: it.item_id, kind: 'item', label: it.text, priority: p, node_id: n.node_id });
      }
    });
  });
  // Backlog entries.
  (snapshot.backlog || []).forEach(function (b) {
    var p = matchPriority(b.text);
    if (p != null) {
      plan.push({ target_id: b.item_id, kind: 'backlog', label: b.text, priority: p });
    }
  });
  return { items: plan, total: plan.length };
}

function emit(plan, opts) {
  opts = opts || {};
  var emitOpts = opts.statePath ? { statePath: opts.statePath } : undefined;
  var emitted = 0;
  plan.items.forEach(function (j) {
    state.appendEvent({
      type: 'priority-assigned', target_id: j.target_id, priority: j.priority, actor: 'dispatch'
    }, emitOpts);
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
  process.stdout.write('priority-backfill: planned ' + p.total + ' priority-assigned event(s)\n');
  p.items.slice(0, 30).forEach(function (j) {
    process.stdout.write('  P' + j.priority + '  ' + j.kind + '  ' + j.target_id + '  ' +
      (typeof j.label === 'string' ? (j.label.length > 80 ? j.label.slice(0, 80) + '…' : j.label) : '') + '\n');
  });
  if (p.total > 30) process.stdout.write('  …(+' + (p.total - 30) + ' more)\n');
  if (args.apply) {
    var r = emit(p, { statePath: args.statePath });
    process.stdout.write('priority-backfill: EMITTED ' + r.emitted + ' / ' + r.planned + '\n');
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
  function freshDir() {
    var d = fs.mkdtempSync(path.join(os.tmpdir(), 'bf-prio-'));
    return d;
  }
  function cleanup(d) {
    try { fs.rmSync(d, { recursive: true, force: true }); } catch (_) {}
  }
  function optsFor(d) { return { statePath: path.join(d, 'tree-state.json'), treeId: 'global' }; }

  // P1: pattern matcher correctness
  (function P1() {
    var hits = [
      ['TCPA 8 decisions waiting', 1],
      ['TWLO-006 twilio_config wire', 1],
      ['A2P portal paste blocks A-F', 1],
      ['Phase 6 plan ratification', 1],
      ['RESEND_FROM_EMAIL DKIM setup', 2],
      ['npx supabase db push migration 137', 2],
      ['Wizard copy rewrite JOURNEY-023', 2],   // first-match (Wizard pattern is P2)
      ['PRIV-003 CSV consent', 3],
      ['A11Y-001 WCAG-AA scope', 3],
      ['JOURNEY-009 voice setup signal', 3],
      ['Phase 7 DR-001 implementation', 3],
      ['random unrelated text', null],
    ];
    var allOk = hits.every(function (h) { return matchPriority(h[0]) === h[1]; });
    check('B1 pattern matcher correctness across all categories + miss', allOk);
  })();

  // P2: end-to-end planFrom → emit → reducer applies priority correctly
  (function P2() {
    var dir = freshDir(); var o = optsFor(dir);
    try {
      state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'T' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a1', text: 'TCPA review blocked' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a2', text: 'PRIV-003 csv consent flow' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a3', text: 'unrelated cleanup' }, o);
      state.appendEvent({ type: 'backlog-added', item_id: 'b1', tree_id: 'global', priority: 'medium', text: 'Phase 6 plan ratification draft' }, o);
      var snap0 = state.readState(o).snapshot;
      var plan = planFrom(snap0);
      var planOk = plan.total === 3
        && plan.items.find(function (x) { return x.target_id === 'a1' && x.priority === 1; })
        && plan.items.find(function (x) { return x.target_id === 'a2' && x.priority === 3; })
        && plan.items.find(function (x) { return x.target_id === 'b1' && x.priority === 1; });
      emit(plan, { statePath: o.statePath });
      var snap1 = state.readState(o).snapshot;
      var a1 = snap1.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
      var a2 = snap1.nodes[0].items.find(function (x) { return x.item_id === 'a2'; });
      var a3 = snap1.nodes[0].items.find(function (x) { return x.item_id === 'a3'; });
      var b1 = snap1.backlog.find(function (x) { return x.item_id === 'b1'; });
      var appliedOk = a1.priority === 1 && a2.priority === 3
        && a3.priority === undefined           // unmatched → no event → P5 default
        && b1.priority_num === 1;
      // Idempotency: re-emit same plan; everything stays correct
      emit(plan, { statePath: o.statePath });
      var snap2 = state.readState(o).snapshot;
      var idempotent = snap2.nodes[0].items.find(function (x) { return x.item_id === 'a1'; }).priority === 1;
      check('B2 planFrom + emit + reducer: open items + backlog correctly prioritised; unmatched left default; idempotent',
        planOk && appliedOk && idempotent,
        'planOk=' + !!planOk + ' appliedOk=' + appliedOk + ' idempotent=' + idempotent);
    } catch (e) { check('B2 end-to-end backfill', false, e.message); }
    finally { cleanup(dir); }
  })();

  // P3: dry-run does not emit (snapshot unchanged)
  (function P3() {
    var dir = freshDir(); var o = optsFor(dir);
    try {
      state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'T' }, o);
      state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a1', text: 'TCPA blocked' }, o);
      var snap0 = state.readState(o).snapshot;
      var beforeLen = snap0.nodes[0].items[0].priority;
      var p = planFrom(snap0);
      // intentionally do NOT call emit()
      var snap1 = state.readState(o).snapshot;
      var afterLen = snap1.nodes[0].items[0].priority;
      check('B3 dry-run does not emit (priority undefined before AND after planFrom)',
        p.total === 1 && beforeLen === undefined && afterLen === undefined);
    } catch (e) { check('B3 dry-run', false, e.message); }
    finally { cleanup(dir); }
  })();

  process.stdout.write('\npriority-backfill self-test\n');
  process.stdout.write(RESULTS.join('\n') + '\n');
  process.stdout.write('\n' + PASS + ' passed, ' + FAIL + ' failed\n');
  process.exit(FAIL === 0 ? 0 : 1);
}

module.exports = { matchPriority, planFrom, emit };

if (require.main === module) runCli();
