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
//   P3 compaction-truncation-correctness  (Pin 3c / §7c — ORIGINAL A2
//      truncate-covered-prefix behavior, DEC-D (d): the post-compaction
//      on-disk events[] holds EXACTLY the freshest snapshot-committed
//      attestation, NO domain events; audit never truncated (NFR-7))
//   P4 unknown-major-refused, distinct message, NOTHING read  (Pin 2 / §1 / A2d)
//   P5 last-N-version retention  (NFR-1 / A2e)
//   P6 event_id idempotency — a re-applied append is a no-op  (§2)
//   P7 FR-2 N=3 fixture — 3 items one thread => 0 extra branches; divergence => exactly 1
//   P8 strict-tree invariant (FR-1) — cycle / second-parent re-parent rejected, retained
//
//   --- DEC-D (d) snapshot-integrity attestation proofs (ADR-032 §8 r2;
//       supersede the deleted (b) P9/P10) ---
//   P9  (d-i)   after a snapshot commit, the most-recent snapshot-committed
//               .hash equals the canonical-JSON sha256 of the ON-DISK snapshot
//   P10 (d-ii)  §8-gate simulation: a VERIFIED snapshot resolves branch-
//               presence from snapshot.nodes for a re-opened, a promoted, AND
//               a backlog-activated node (DEC-E/DEC-F moot under (d))
//   P11 (d-iii) a byte-tampered snapshot ⇒ canonical-hash mismatch ⇒ §8 gate
//               REFUSES + the existing A2 torn-snapshot-recovery engages
//   P12 (d-iv)  the NL-FINDING-004 FR-24 trace — 7-event tree, non-branch-
//               opened final event, compaction fires: post-compaction
//               readState() PRESERVES items/checked-states/drafts/conclusions
//               (the (b) regression is GONE — compaction is original-behavior
//               + §8 reads the verified snapshot)
//   P13 (d-v)   the latest snapshot-committed SURVIVES compaction naturally
//               (DEC-D rule 2: appended post-truncation, always freshest)
//   P14 (r2.1)  the ACTUAL sanctioned §8 gate path, end-to-end: a REAL `node`
//               subprocess (child_process) — the exact `node -e …
//               require("./state.js") … verifySnapshotAttested` shape the
//               corrected §8 r2.1 text sanctions — reading the on-disk file
//               reports verified===true + digest === on-disk
//               snapshot-committed.hash on the untampered file, and NOT
//               verified on a byte-tampered file. Proves writer↔verifier
//               equivalence via the REAL path (not the in-process call P9–P13
//               use), closing the §8-contract-vs-implemented-path false-signal
//               gap systems-designer FAILed r2 on (same shape as NL-FINDING-004).

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
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
    // DEC-D (d) — ORIGINAL A2 compaction restored (the (b) gateRelevantRetention
    // is REMOVED; no per-gate carve-out). Post-compaction the on-disk events[]
    // is truncated of the entire provably-covered prefix, so it holds EXACTLY
    // ONE record: the freshest snapshot-committed attestation appended AFTER
    // truncation (DEC-D rule 1/2 — same atomic publish, survives naturally).
    // ZERO domain events remain on disk; the snapshot still has all 8 nodes
    // (its hash matches the attestation ⇒ §8 would verify-then-read it).
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const onDiskEvents = onDisk.events.length;
    const onlyAttestation = onDiskEvents === 1
      && onDisk.events[0].type === store.SNAPSHOT_COMMITTED_TYPE;
    const noDomainEvents = !onDisk.events.some(function (e) {
      return e.type !== store.SNAPSHOT_COMMITTED_TYPE;
    });
    const snapNodes = after.snapshot.nodes.length;
    // §8 verify-then-read: the on-disk snapshot is attestation-verified.
    const v = store.verifySnapshotAttested(onDisk);
    // readState() returns DOMAIN-only events (attestation is an on-disk
    // meta-record, never consumer-facing). The full prefix was covered + the
    // on-disk domain log truncated, so consumer-facing state is reconstructed
    // via the never-truncated audit log (original A2 §7a deep-recovery):
    // all 8 domain events + 8 nodes are recovered (Pin-3a unchanged).
    const recovered = after.events.length === 8 && after.snapshot.nodes.length === 8;
    // Audit log (NFR-7) is never truncated: all 8 events still replayable.
    const audit = store.replayAuditLog(store.auditPathFor(o.statePath));
    check('P3 compaction-truncation-correctness + audit-never-truncated',
      last.compacted === true && onlyAttestation && noDomainEvents
        && snapNodes === 8 && v.verified === true && recovered
        && audit.length === 8,
      'compacted=' + last.compacted + ' onDiskEvents=' + onDiskEvents
        + ' onlyAttestation=' + onlyAttestation + ' noDomainEvents=' + noDomainEvents
        + ' snapNodes=' + snapNodes + ' verified=' + v.verified
        + ' recovered=' + recovered + ' audit=' + audit.length);
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


// ============================================================================
// DEC-D (d) snapshot-integrity attestation proofs (ADR-032 §8 r2).
// These SUPERSEDE the deleted (b) P9/P10 (gateRelevantRetention / events[]-only
// jq). The (b) approach is GONE: compaction is original-behavior + §8 reads the
// attestation-VERIFIED snapshot. (b) superseded by (d) per Misha 2026-05-17.
// ============================================================================

// ---- P9 (d-i) attestation hash == canonical-JSON sha256 of on-disk snapshot -
// Once a snapshot commit lands (no compaction; small tree), the most-recent
// snapshot-committed.hash MUST equal store.hashSnapshot(on-disk snapshot) — the
// determinism that makes the §8 verifier able to trust the cache (DEC-D rule
// 1/4). Also assert the §8 verify primitive returns verified:true.
(function P9() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'Root' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'n2', parent_id: 'n1', title: 'Sub' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'd1', text: 'pick X' }, o);
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    // most-recent snapshot-committed record
    let att = null;
    for (let i = onDisk.events.length - 1; i >= 0; i--) {
      if (onDisk.events[i].type === store.SNAPSHOT_COMMITTED_TYPE) { att = onDisk.events[i]; break; }
    }
    const expected = store.hashSnapshot(onDisk.snapshot);
    const hashMatches = att && att.hash === expected && /^sha256:[0-9a-f]{64}$/.test(att.hash);
    const v = store.verifySnapshotAttested(onDisk);
    // Determinism cross-check: re-hash the SAME object twice => identical.
    const stable = store.hashSnapshot(onDisk.snapshot) === store.hashSnapshot(onDisk.snapshot);
    check('P9 (d-i) snapshot-committed.hash == canonical-JSON sha256 of on-disk snapshot',
      !!hashMatches && v.verified === true && stable,
      'hashMatches=' + !!hashMatches + ' verified=' + v.verified + ' stable=' + stable
        + ' att.hash=' + (att && att.hash));
  } catch (e) { check('P9 (d-i) attestation hash == canonical sha256', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P10 (d-ii) §8-gate sim: verified snapshot resolves branch-presence -----
// from snapshot.nodes for a re-opened node, a promoted node, AND a backlog-
// activated node — proving DEC-E (archive→compact→re-open) and DEC-F
// (promoted/backlog-activated) are MOOT under (d): §8 reads snapshot.nodes,
// which already contains every still-live node, AFTER verifying the snapshot.
(function P10() {
  const dir = freshDir(); const o = Object.assign(optsFor(dir), { compactionThreshold: 6 });
  try {
    // re-opened path: open -> conclude -> re-open (must end up live in snapshot)
    state.appendEvent({ type: 'branch-opened', node_id: 'reop', parent_id: null, title: 'ReopenedBranch' }, o);
    state.appendEvent({ type: 'concluded', node_id: 'reop' }, o);
    state.appendEvent({ type: 're-opened', node_id: 'reop' }, o);
    // promoted path: an item on a host node promoted to its own branch
    state.appendEvent({ type: 'branch-opened', node_id: 'host', parent_id: null, title: 'Host' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'host', item_id: 'i1', text: 'do thing' }, o);
    state.appendEvent({ type: 'promoted', node_id: 'host', item_id: 'i1', new_node_id: 'prom' }, o);
    // backlog-activated path: backlog item -> activated as a root node
    state.appendEvent({ type: 'backlog-added', item_id: 'b1', tree_id: 'global', priority: 'P1', text: 'BacklogBranch' }, o);
    let last = state.appendEvent({ type: 'backlog-activated', item_id: 'b1', new_node_id: 'bka' }, o);
    // force compaction with extra events so the prefix is covered + truncated
    for (let i = 0; i < 6; i++) {
      last = state.appendEvent({ type: 'branch-opened', node_id: 'x' + i, parent_id: null, title: 'X' + i }, o);
    }
    const compacted = last.compacted === true;
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    // §8 r2: verify the snapshot FIRST, then read snapshot.nodes for presence.
    const v = store.verifySnapshotAttested(onDisk);
    function gateResolves(idOrTitle) {
      if (!v.verified) return false;                // mismatch => gate refuses
      return onDisk.snapshot.nodes.some(function (n) {
        return (n.node_id === idOrTitle || n.title === idOrTitle) && n.state !== 'archived';
      });
    }
    const reopResolves = gateResolves('reop') && gateResolves('ReopenedBranch');
    const promResolves = gateResolves('prom');           // DEC-F: promoted node present
    const bkaResolves = gateResolves('bka') && gateResolves('BacklogBranch'); // DEC-F: backlog-activated
    check('P10 (d-ii) §8 verified snapshot resolves re-opened + promoted + backlog-activated (DEC-E/DEC-F moot)',
      compacted && v.verified === true && reopResolves && promResolves && bkaResolves,
      'compacted=' + compacted + ' verified=' + v.verified
        + ' reop=' + reopResolves + ' prom=' + promResolves + ' bka=' + bkaResolves);
  } catch (e) { check('P10 (d-ii) §8 verified-snapshot branch-presence', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P11 (d-iii) byte-tamper ⇒ hash mismatch ⇒ gate refuses + torn-recovery -
// Tamper a single byte of the on-disk snapshot. The canonical-JSON hash no
// longer matches the most-recent snapshot-committed ⇒ verifySnapshotAttested
// returns verified:false (gate REFUSES) AND the existing A2 §7a torn-snapshot-
// recovery still reconstructs correct state from the domain log (Pin-3a).
(function P11() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'Trusted' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'n2', parent_id: 'n1', title: 'Sub' }, o);
    const before = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const vPre = store.verifySnapshotAttested(before);
    // Byte-tamper: mutate a node title inside the snapshot WITHOUT updating the
    // attestation (simulates a torn / corrupted snapshot block).
    const tampered = JSON.parse(JSON.stringify(before));
    tampered.snapshot.nodes[0].title = 'TAMPERED';
    fs.writeFileSync(o.statePath, JSON.stringify(tampered, null, 2), 'utf8');
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const vPost = store.verifySnapshotAttested(onDisk);
    const gateRefuses = vPost.verified === false && vPost.reason === 'hash-mismatch';
    // §7a torn-recovery: readState() must DISCARD the tampered snapshot and
    // replay the domain log => the original (un-tampered) titles are restored.
    const recovered = state.readState(o);
    const n1 = recovered.snapshot.nodes.find(function (n) { return n.node_id === 'n1'; });
    const tornRecoveryEngaged = !!n1 && n1.title === 'Trusted'
      && recovered.snapshot.nodes.length === 2;
    check('P11 (d-iii) byte-tamper ⇒ §8 refuses (hash-mismatch) + §7a torn-recovery engages',
      vPre.verified === true && gateRefuses && tornRecoveryEngaged,
      'vPre=' + vPre.verified + ' gateRefuses=' + gateRefuses
        + ' reason=' + vPost.reason + ' tornRecovery=' + tornRecoveryEngaged);
  } catch (e) { check('P11 (d-iii) byte-tamper ⇒ refuse + torn-recovery', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P12 (d-iv) NL-FINDING-004 FR-24 trace — regression GONE under (d) ------
// The exact (b)-regression fixture: a 7-DOMAIN-event tree (1 branch-opened + 3
// items + answer/done + a conclusion) whose FINAL pre-compaction event is NOT a
// branch-opened, with compaction firing. With (b) the marker pointed past the
// published subset ⇒ readState() discarded the valid snapshot ⇒ items/checked/
// drafts/conclusions silently lost. With (d): compaction is original-behavior,
// the snapshot is attestation-verified, the §7a marker tracks the last DOMAIN
// event ⇒ post-compaction readState() PRESERVES all node state. Regression GONE.
(function P12() {
  const dir = freshDir(); const o = Object.assign(optsFor(dir), { compactionThreshold: 6 });
  try {
    // The EXACT NL-FINDING-004 FR-24 trace: a 7-DOMAIN-event tree =
    // 1 branch-opened + 3 items + 3 answer/done on ONE live node, the FINAL
    // event being a non-branch-opened (action-done) — plus a draft (FR-27)
    // mid-trace. With (b) the marker pointed past the published subset so
    // readState() discarded the valid snapshot and re-derived from the lossy
    // 1-event-per-live-node subset → items/checked/draft silently destroyed.
    // With (d) this CANNOT arise: compaction is original-behavior, the §7a
    // marker tracks the last DOMAIN event, the snapshot is attestation-verified.
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'LiveThread' }, o); // 1
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'i1', text: 'D1' }, o);          // 2
    state.appendEvent({ type: 'question-raised', node_id: 'n1', item_id: 'i2', text: 'Q1' }, o);          // 3
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'i3', text: 'A1' }, o);             // 4
    state.appendEvent({ type: 'draft-saved', node_id: 'n1', draft_text: 'FR-27 work in progress' }, o);   // 5 (FR-27 draft)
    state.appendEvent({ type: 'answered', node_id: 'n1', item_id: 'i1' }, o);                             // 6
    state.appendEvent({ type: 'answered', node_id: 'n1', item_id: 'i2' }, o);                             // 7
    const last = state.appendEvent({ type: 'action-done', node_id: 'n1', item_id: 'i3' }, o);            // 8 non-branch-opened FINAL
    const compacted = last.compacted === true; // threshold 6 < 8 ⇒ compaction fired
    // Post-compaction read MUST preserve every piece of node state (the (b)
    // regression discarded exactly these).
    const after = state.readState(o);
    const n1 = after.snapshot.nodes.find(function (n) { return n.node_id === 'n1'; });
    const itemsPreserved = !!n1 && n1.items.length === 3;
    const allChecked = !!n1 && n1.items.every(function (it) { return it.checked === true; });
    const draftPreserved = !!n1 && (n1.draft === 'FR-27 work in progress' || n1.draft_text === 'FR-27 work in progress');
    // Separately prove a CONCLUDED node's state survives compaction too: all
    // items checked above, so a conclude now applies (FR-7) and must persist.
    const cc = state.appendEvent({ type: 'concluded', node_id: 'n1' }, o);
    const after2 = state.readState(o);
    const n1b = after2.snapshot.nodes.find(function (n) { return n.node_id === 'n1'; });
    const concludedPreserved = !!n1b && n1b.state === 'concluded'
      && n1b.items.length === 3
      && (n1b.draft === 'FR-27 work in progress' || n1b.draft_text === 'FR-27 work in progress');
    // And the on-disk snapshot is attestation-verified (the §8 path the gate uses).
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const v = store.verifySnapshotAttested(onDisk);
    check('P12 (d-iv) NL-FINDING-004 FR-24 trace — items/checked/draft/concluded preserved post-compaction (regression GONE)',
      compacted && itemsPreserved && allChecked && draftPreserved
        && concludedPreserved && v.verified === true,
      'compacted=' + compacted + ' items=' + (n1 && n1.items.length)
        + ' allChecked=' + allChecked + ' draft=' + draftPreserved
        + ' concluded=' + concludedPreserved + ' verified=' + v.verified
        + ' cc.compacted=' + cc.compacted);
  } catch (e) { check('P12 (d-iv) NL-FINDING-004 FR-24 regression-gone', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P13 (d-v) latest snapshot-committed survives compaction naturally ------
// DEC-D rule 2: the attestation is appended AFTER the compaction-truncation
// decision, so it is never inside the covered prefix — it is always the
// freshest events[] record and survives compaction with NO carve-out. Prove:
// after many compactions, on-disk events[] holds EXACTLY ONE snapshot-committed
// (the freshest) and ZERO domain events, and each compaction's attestation
// matches that round's snapshot.
(function P13() {
  const dir = freshDir(); const o = Object.assign(optsFor(dir), { compactionThreshold: 4 });
  try {
    let last;
    for (let i = 0; i < 15; i++) {                 // many compactions across rounds
      last = state.appendEvent({ type: 'branch-opened', node_id: 'n' + i, parent_id: null, title: 'T' + i }, o);
    }
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const att = onDisk.events.filter(function (e) { return e.type === store.SNAPSHOT_COMMITTED_TYPE; });
    const domainOnDisk = onDisk.events.filter(function (e) { return e.type !== store.SNAPSHOT_COMMITTED_TYPE; });
    const exactlyOneFreshAttestation = att.length === 1;
    const zeroDomainOnDisk = domainOnDisk.length === 0;
    const lastIsAttestation = onDisk.events.length > 0
      && onDisk.events[onDisk.events.length - 1].type === store.SNAPSHOT_COMMITTED_TYPE;
    // The surviving attestation matches the current snapshot (still trustworthy
    // after every compaction round — survived naturally, not via a carve-out).
    const v = store.verifySnapshotAttested(onDisk);
    check('P13 (d-v) latest snapshot-committed survives compaction naturally (DEC-D rule 2)',
      last.compacted === true && exactlyOneFreshAttestation && zeroDomainOnDisk
        && lastIsAttestation && v.verified === true,
      'compacted=' + last.compacted + ' attCount=' + att.length
        + ' domainOnDisk=' + domainOnDisk.length + ' lastIsAtt=' + lastIsAttestation
        + ' verified=' + v.verified);
  } catch (e) { check('P13 (d-v) latest snapshot-committed survives compaction', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P14 (r2.1) real-subprocess sanctioned §8 gate path --------------------
// systems-designer FAILed r2 because the §8 text presented a jq-shell hash
// shape and CLAIMED it was canonicalJSON-equivalent (it is NOT). P9–P13 are
// green only because they call the in-process Node verifier, never the path
// the §8 contract hands a gate builder. P14 closes that false-signal gap by
// exercising the ACTUAL sanctioned path: a REAL `node` subprocess (the exact
// `node -e … require(state.js) … verifySnapshotAttested` shape the corrected
// §8 r2.1 text sanctions) reads the on-disk file. Assert: (i) verified===true
// on the untampered file, (ii) its computed digest === on-disk most-recent
// snapshot-committed.hash, (iii) on a byte-tampered snapshot the SAME real-path
// command reports NOT verified. Writer↔verifier equivalence proven via the
// real path — verified, not asserted.
(function P14() {
  const dir = freshDir(); const o = optsFor(dir);
  // The exact node -e the §8 r2.1 text sanctions: require the state library by
  // absolute path (cwd-independent), verify the on-disk file, print the digest,
  // exit 0 iff verified. argv[1] = state file.
  const MODULE = path.resolve(__dirname, 'state.js').replace(/\\/g, '\\\\');
  const SCRIPT =
    'const s=require("' + MODULE + '");const fs=require("fs");' +
    'const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));' +
    'const r=s.verifySnapshotAttested(p);' +
    'process.stdout.write(JSON.stringify({verified:r.verified,hash:r.hash||""}));' +
    'process.exit(r.verified?0:1)';
  function runGate(stateFile) {
    try {
      const out = cp.execFileSync(process.execPath, ['-e', SCRIPT, stateFile],
        { encoding: 'utf8' });
      return { code: 0, parsed: JSON.parse(out) };
    } catch (e) {
      // non-zero exit ⇒ not verified. stdout still captured on execFileSync err.
      let parsed = null;
      try { parsed = JSON.parse((e.stdout || '').toString()); } catch (_) {}
      return { code: e.status == null ? -1 : e.status, parsed: parsed };
    }
  }
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'rp1', parent_id: null, title: 'RealPathBranch' }, o);
    state.appendEvent({ type: 'branch-opened', node_id: 'rp2', parent_id: 'rp1', title: 'RealPathSub' }, o);
    const onDisk = JSON.parse(fs.readFileSync(o.statePath, 'utf8'));
    const att = onDisk.events.filter(function (e) { return e.type === store.SNAPSHOT_COMMITTED_TYPE; });
    const onDiskHash = att.length ? att[att.length - 1].hash : null;

    // (i)+(ii): untampered file via REAL subprocess ⇒ verified + digest match.
    const ok = runGate(o.statePath);
    const verifiedTrue = ok.code === 0 && ok.parsed && ok.parsed.verified === true;
    const digestMatchesOnDisk = !!ok.parsed && ok.parsed.hash === onDiskHash && !!onDiskHash;

    // (iii): byte-tamper the snapshot WITHOUT updating attestation; SAME real
    // command must report NOT verified (non-zero exit, verified:false).
    const tampered = JSON.parse(JSON.stringify(onDisk));
    tampered.snapshot.nodes[0].title = 'TAMPERED-REALPATH';
    fs.writeFileSync(o.statePath, JSON.stringify(tampered, null, 2), 'utf8');
    const bad = runGate(o.statePath);
    const tamperRefused = bad.code !== 0 && (!bad.parsed || bad.parsed.verified === false);

    check('P14 (r2.1) REAL node subprocess on sanctioned §8 path: untampered ⇒ verified + digest==on-disk hash; byte-tampered ⇒ NOT verified',
      verifiedTrue && digestMatchesOnDisk && tamperRefused,
      'verifiedTrue=' + verifiedTrue + ' digestMatch=' + digestMatchesOnDisk
        + ' (gate=' + (ok.parsed && ok.parsed.hash) + ' onDisk=' + onDiskHash + ')'
        + ' tamperRefused=' + tamperRefused + ' tamperCode=' + bad.code);
  } catch (e) { check('P14 (r2.1) real-subprocess sanctioned §8 gate path', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P15 v1.1-ux additive events (item-details-set / action-responded /
//      item-unchecked) — ADDITIVE within schema major 1 (ADR-032 §1) --------
(function P15() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'T' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a1', text: 'do X' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'd1', text: 'pick' }, o);

    const s0 = state.readState(o);
    const majorStill1 = s0.schema_version === 1;   // no major bump

    state.appendEvent({ type: 'item-details-set', node_id: 'n1', item_id: 'a1',
      details: { description: 'd', context: 'c', instructions: 'i' } }, o);
    let it = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    const detailsSet = it.details && it.details.description === 'd' && it.details.instructions === 'i';

    state.appendEvent({ type: 'item-details-set', node_id: 'n1', item_id: 'a1',
      details: { description: 'd2' } }, o);
    it = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    const detailsLWW = it.details.description === 'd2'
      && state.readState(o).snapshot.nodes[0].items.length === 2;   // no duplicate item

    state.appendEvent({ type: 'action-responded', node_id: 'n1', item_id: 'd1',
      response_text: 'my answer' }, o);
    it = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'd1'; });
    const respondedSet = it.responded && it.responded.text === 'my answer' && it.checked === false;

    state.appendEvent({ type: 'action-done', node_id: 'n1', item_id: 'a1' }, o);
    const checkedAfterDone = state.readState(o).snapshot.nodes[0].items
      .find(function (x) { return x.item_id === 'a1'; }).checked === true;
    state.appendEvent({ type: 'item-unchecked', node_id: 'n1', item_id: 'a1' }, o);
    const uncheckedRoundTrip = state.readState(o).snapshot.nodes[0].items
      .find(function (x) { return x.item_id === 'a1'; }).checked === false;

    let rejectedUnknown = true;
    try {
      state.appendEvent({ type: 'item-unchecked', node_id: 'n1', item_id: 'nope' }, o);
      rejectedUnknown = state.readState(o).snapshot.nodes[0].items.length === 2;
    } catch (_) { rejectedUnknown = true; }

    check('P15 v1.1-ux additive events: details-set(LWW) + action-responded(stays !checked) + item-unchecked(round-trip) + schema_version still 1 + unknown-item rejected',
      majorStill1 && detailsSet && detailsLWW && respondedSet && checkedAfterDone
        && uncheckedRoundTrip && rejectedUnknown,
      'major1=' + majorStill1 + ' detailsSet=' + detailsSet + ' LWW=' + detailsLWW
        + ' responded=' + respondedSet + ' done=' + checkedAfterDone
        + ' uncheck=' + uncheckedRoundTrip + ' rejUnknown=' + rejectedUnknown);
  } catch (e) { check('P15 v1.1-ux additive events', false, e.message); }
  finally { cleanup(dir); }
})();

// ---- P16 v1.1.2 item 28 additive: item-backlogged + deferred local-time
//      fields — ADDITIVE within schema major 1 (ADR-032 §1) -----------------
(function P16() {
  const dir = freshDir(); const o = optsFor(dir);
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'T' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a1', text: 'do X' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'd1', text: 'pick' }, o);

    const majorStill1 = state.readState(o).schema_version === 1;   // no major bump

    // deferred carries OPTIONAL additive local-time fields; scheduled_for
    // stays the canonical cross-machine ISO value (unchanged contract).
    const iso = '2026-06-01T13:00:00.000Z';
    state.appendEvent({ type: 'deferred', node_id: 'n1', item_id: 'a1',
      scheduled_for: iso, scheduled_for_local: '2026-06-01T15:00', tz_offset_min: -120 }, o);
    let a1 = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    const deferLocal = a1.deferred === true && a1.scheduled_for === iso
      && a1.scheduled_for_local === '2026-06-01T15:00' && a1.tz_offset_min === -120;

    // a plain deferred (no local fields) is unchanged — fields stay absent.
    state.appendEvent({ type: 'deferred', node_id: 'n1', item_id: 'd1', scheduled_for: null }, o);
    let d1 = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'd1'; });
    const deferPlainUnchanged = d1.deferred === true && d1.scheduled_for === null
      && d1.scheduled_for_local === undefined && d1.tz_offset_min === undefined;

    // item-backlogged parks the item WITHOUT checking it (NOT a quiet-resolve).
    state.appendEvent({ type: 'item-backlogged', node_id: 'n1', item_id: 'a1' }, o);
    a1 = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    const parked = a1.backlogged === true && a1.checked === false;

    // item-unchecked un-parks too (round-trip).
    state.appendEvent({ type: 'item-unchecked', node_id: 'n1', item_id: 'a1' }, o);
    a1 = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    const unparkRoundTrip = a1.backlogged === false && a1.checked === false;

    // item-backlogged on an unknown item is rejected (retained, not applied).
    let rejectedUnknown = true;
    try {
      state.appendEvent({ type: 'item-backlogged', node_id: 'n1', item_id: 'nope' }, o);
      rejectedUnknown = state.readState(o).snapshot.nodes[0].items.length === 2;
    } catch (_) { rejectedUnknown = true; }

    const majorStill1After = state.readState(o).schema_version === 1;

    check('P16 v1.1.2 item 28 additive: item-backlogged(park, !checked) + deferred local-time fields + plain-defer unchanged + unpark round-trip + unknown rejected + schema_version still 1',
      majorStill1 && deferLocal && deferPlainUnchanged && parked && unparkRoundTrip
        && rejectedUnknown && majorStill1After,
      'major1=' + majorStill1 + ' deferLocal=' + deferLocal
        + ' plainUnchanged=' + deferPlainUnchanged + ' parked=' + parked
        + ' unpark=' + unparkRoundTrip + ' rejUnknown=' + rejectedUnknown
        + ' major1After=' + majorStill1After);
  } catch (e) { check('P16 v1.1.2 item 28 additive', false, e.message); }
  finally { cleanup(dir); }
})();

process.stdout.write('\nADR-032 state library — property self-test\n');
process.stdout.write(RESULTS.join('\n') + '\n');
process.stdout.write('\n' + PASS + ' passed, ' + FAIL + ' failed\n');
process.exit(FAIL === 0 ? 0 : 1);
