'use strict';
// Property / self-test suite for the ADR-032 state library (plan Testing
// Strategy + Edge Cases). Each property is independently named so the
// orchestrator-mediated verification can cite which passed.
//
//   run:  node neural-lace/conversation-tree-ui/state/selftest.js
//   exit: 0 = all properties hold; 1 = a property failed (with detail).
//
// Properties:
//   P1 atomic-append-under-simulated-crash  (Pin 3b / §7b)
//   P2 torn-snapshot -> deterministic log-replay  (Pin 3a / §7a)
//   P3 compaction-truncation-correctness  (Pin 3c / §7c) + audit never truncated (NFR-7)
//   P4 unknown-major-refused, distinct message, NOTHING read  (Pin 2 / §1 / A2d)
//   P5 last-N-version retention  (NFR-1 / A2e)
//   P6 event_id idempotency — a re-applied append is a no-op  (§2)
//   P7 FR-2 N=3 fixture — 3 items one thread => 0 extra branches; divergence => exactly 1
//   P8 strict-tree invariant (FR-1) — cycle / second-parent re-parent rejected, retained

const fs = require('fs');
const os = require('os');
const path = require('path');
const state = require('./state.js');
const store = require('./store.js');

let PASS = 0, FAIL = 0;
const RESULTS = [];
function check(name, cond, detail) {
  if (cond) { PASS++; RESULTS.push('  PASS  ' + name); }
  else { FAIL++; RESULTS.push('  FAIL  ' + name + (detail ? '  — ' + detail : '')); }
}
function freshDir() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'ctree-selftest-'));
  return d;
}
function optsFor(dir) {
  return { statePath: path.join(dir, 'tree-state.json'), treeId: 'global' };
}
function cleanup(dir) { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {} }

// ---- P1 atomic-append-under-simulated-crash --------------------------------
// renameSync is the atomic unit: a reader of the well-known path sees N or
// N+1 WHOLE events. We simulate a crashed half-write by leaving a .tmp file
// containing garbage alongside a valid published file, then assert the reader
// only ever observes the valid published content (the temp is never the
// well-known path until rename completes).
(function P1() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'A' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'n2', parent_id: 'n1', title: 'B' }, o);
    // Simulate a crashed mid-write: a stray temp with a half event. The
    // well-known path must still read exactly 2 whole events.
    fs.writeFileSync(o.statePath + '.tmp.crash', '{ "events": [ {"type":"branch-', 'utf8');
    const s = state.readState(o);
    check('P1 atomic-append-under-simulated-crash',
      s.events.length === 2 && s.snapshot.nodes.length === 2,
      'events=' + s.events.length + ' nodes=' + s.snapshot.nodes.length);
  } catch (e) { check('P1 atomic-append-under-simulated-crash', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P2 torn-snapshot -> deterministic log-replay --------------------------
(function P2() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'r', parent_id: null, title: 'Root' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'c', parent_id: 'r', title: 'Child' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'r', item_id: 'd1', text: 'pick X' }, o);
    const truthEvents = state.readState(o).events;

    // (a) snapshot.valid=false  -> must discard + replay
    store.__writeTornForTest(o, truthEvents, { nodes: [], valid: false, covers_through_event_id: null });
    const a = state.readState(o);
    // (b) stale coverage marker (points at an old event) -> must discard + replay
    store.__writeTornForTest(o, truthEvents, { nodes: [{ node_id: 'STALE' }], valid: true, covers_through_event_id: truthEvents[0].event_id });
    const b = state.readState(o);
    // (c) snapshot entirely absent -> must replay
    store.__writeTornForTest(o, truthEvents, null);
    const c = state.readState(o);

    const ok = a.snapshot.nodes.length === 2 && b.snapshot.nodes.length === 2 && c.snapshot.nodes.length === 2 &&
      b.snapshot.nodes.every(function (n) { return n.node_id !== 'STALE'; }) &&
      a.snapshot.nodes[0].items.length === 1; // decision replayed onto 'r'
    check('P2 torn-snapshot -> deterministic log-replay', ok,
      'a=' + a.snapshot.nodes.length + ' b=' + b.snapshot.nodes.length + ' c=' + c.snapshot.nodes.length);
  } catch (e) { check('P2 torn-snapshot -> deterministic log-replay', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P3 compaction-truncation-correctness + audit never truncated ----------
(function P3() {
  const dir = freshDir(); const o = Object.assign(optsFor(dir), { compactionThreshold: 5 });
  try {
    let last;
    for (let i = 0; i < 8; i++) {
      last = state.appendEvent({ type: 'branch-opened', node_id: 'n' + i, parent_id: null, title: 'T' + i }, o);
    }
    const after = state.readState(o);
    // Post-compaction the on-disk events[] is truncated to the provably-
    // covered prefix (here: empty, with a coverage marker proving it), yet
    // the reconstructed snapshot still has all 8 nodes (marker => trust cache).
    const onDiskEvents = JSON.parse(fs.readFileSync(o.statePath, 'utf8')).events.length;
    const snapNodes = after.snapshot.nodes.length;
    // Audit log (NFR-7) is never truncated: all 8 events still replayable.
    const audit = store.replayAuditLog(store.auditPathFor(o.statePath));
    check('P3 compaction-truncation-correctness + audit-never-truncated',
      last.compacted === true && onDiskEvents === 0 && snapNodes === 8 && audit.length === 8,
      'compacted=' + last.compacted + ' onDiskEvents=' + onDiskEvents + ' snapNodes=' + snapNodes + ' audit=' + audit.length);
  } catch (e) { check('P3 compaction-truncation-correctness + audit-never-truncated', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P4 unknown-major-refused (distinct message, NOTHING read) -------------
(function P4() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'A' }, o);
    // Forge a file with a NEWER major than the reader knows.
    const forged = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    forged.schema_version = state.SCHEMA_VERSION + 1;
    fs.writeFileSync(o.statePath, JSON.stringify(forged, null, 2), 'utf8');
    let threw = false, msg = '', readNothing = true;
    try {
      state.readState(o);
    } catch (err) {
      threw = err instanceof state.SchemaTooNewError;
      msg = err.message;
      // "reads NOTHING" — the error carries no events/snapshot payload.
      readNothing = !('events' in err) && !('snapshot' in err);
    }
    check('P4 unknown-major-refused, distinct message, nothing read',
      threw && msg === state.SCHEMA_TOO_NEW_MESSAGE && readNothing,
      'threw=' + threw + ' msg="' + msg + '" readNothing=' + readNothing);
  } catch (e) { check('P4 unknown-major-refused, distinct message, nothing read', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P5 last-N-version retention -------------------------------------------
(function P5() {
  const dir = freshDir(); const o = Object.assign(optsFor(dir), { retention: 3 });
  try {
    for (let i = 0; i < 7; i++) {
      state.appendEvent({ type: 'branch-opened', node_id: 'n' + i, parent_id: null, title: 'T' + i }, o);
    }
    const verDir = path.join(dir, '.versions');
    const versions = fs.existsSync(verDir) ? fs.readdirSync(verDir) : [];
    check('P5 last-N-version retention',
      versions.length === 3,
      'kept=' + versions.length + ' (expected exactly retention=3)');
  } catch (e) { check('P5 last-N-version retention', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P6 event_id idempotency (re-applied append = no-op) -------------------
(function P6() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    const r1 = state.appendEvent({ event_id: 'FIXED-ID-1', type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'A' }, o);
    const r2 = state.appendEvent({ event_id: 'FIXED-ID-1', type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'A' }, o);
    const s = state.readState(o);
    check('P6 event_id idempotency (re-applied append = no-op)',
      r1.appended === true && r2.appended === false && r2.idempotentNoop === true &&
      s.events.length === 1 && s.snapshot.nodes.length === 1,
      'r1.appended=' + r1.appended + ' r2.noop=' + r2.idempotentNoop + ' events=' + s.events.length);
  } catch (e) { check('P6 event_id idempotency (re-applied append = no-op)', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P7 FR-2 N=3 fixture (ADR-032 §3) --------------------------------------
(function P7() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    // 3 items in ONE thread => 0 extra branches.
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'thread' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'i1', text: 'd' }, o);
    state.appendEvent({ type: 'question-raised', node_id: 'n1', item_id: 'i2', text: 'q' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'i3', text: 'a' }, o);
    const s1 = state.readState(o);
    const oneNodeThreeItems = s1.snapshot.nodes.length === 1 && s1.snapshot.nodes[0].items.length === 3;
    const branchOpenedCount1 = s1.events.filter(function (e) { return e.type === 'branch-opened'; }).length;

    // Contrast: genuine divergence => exactly 1 NEW branch (child of n1).
    state.appendEvent({ type: 'branch-opened', node_id: 'n2', parent_id: 'n1', title: 'sub-investigation' }, o);
    const s2 = state.readState(o);
    const branchOpenedCount2 = s2.events.filter(function (e) { return e.type === 'branch-opened'; }).length;
    const exactlyOneNew = (branchOpenedCount2 - branchOpenedCount1) === 1 && s2.snapshot.nodes.length === 2;

    check('P7 FR-2 N=3: 3 items one thread => 0 extra branches; divergence => exactly 1',
      oneNodeThreeItems && branchOpenedCount1 === 1 && exactlyOneNew,
      'oneNodeThreeItems=' + oneNodeThreeItems + ' bo1=' + branchOpenedCount1 + ' bo2=' + branchOpenedCount2);
  } catch (e) { check('P7 FR-2 N=3 fixture', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P8 strict-tree invariant (FR-1) ---------------------------------------
(function P8() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'a', parent_id: null, title: 'A' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'b', parent_id: 'a', title: 'B' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'c', parent_id: 'b', title: 'C' }, o);
    // Re-parent 'a' under 'c' would create a cycle a->b->c->a. The event must
    // be RETAINED in the log (nothing silently dropped — NFR-2) but REJECTED
    // by the reducer (not applied), surfaced in snapshot.rejections (C1 UX).
    state.appendEvent({ type: 're-parented', node_id: 'a', new_parent_id: 'c' }, o);
    const s = state.readState(o);
    const aNode = s.snapshot.nodes.find(function (n) { return n.node_id === 'a'; });
    const cycleRejected = aNode.parent_id === null &&
      s.snapshot.rejections.some(function (r) { return r.type === 're-parented' && /cycle/.test(r.reason); });
    const eventRetained = s.events.some(function (e) { return e.type === 're-parented'; }); // log keeps it
    check('P8 strict-tree invariant (FR-1) — cycle rejected, event retained',
      cycleRejected && eventRetained,
      'cycleRejected=' + cycleRejected + ' eventRetained=' + eventRetained);
  } catch (e) { check('P8 strict-tree invariant (FR-1)', false, e.message); }
  finally { cleanup(dir); }
})();

process.stdout.write('\nADR-032 state library — property self-test\n');
process.stdout.write(RESULTS.join('\n') + '\n');
process.stdout.write('\n' + PASS + ' passed, ' + FAIL + ' failed\n');
process.exit(FAIL === 0 ? 0 : 1);
