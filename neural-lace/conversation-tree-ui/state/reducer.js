'use strict';
// ADR-032 §2/§3/§4/§6 — deterministic left-fold of `events` into `snapshot`.
// The events array is the source of truth (Pin 3); this reducer is the ONLY
// definition of how it derives the snapshot, so torn-snapshot recovery (§7a)
// = "discard snapshot, run this reducer over events" is byte-deterministic.
//
// Invariants asserted HERE, not by the writer (ADR-032 §3/§6):
//   - strict-tree (FR-1): every node exactly one parent (or null root); no
//     cycle, no second parent. A `branch-opened`/`re-parented`/`promoted`/
//     `backlog-activated` that would violate this is REJECTED (event retained
//     in the log — NFR-2 nothing-silently-dropped — but not applied; the
//     rejection is recorded so C1 can surface it).
//   - `concluded` rejected if the node still has an unchecked item (FR-7).
//   - unknown `type` within the same major is SKIPPED, never an error
//     (forward-tolerant additive evolution, §1).
//   - deferred is a STATE not a kind (§4): only `defer-cleared` flips it back.

const { ITEM_KINDS } = require('./schema.js');

function emptySnapshot() {
  // `rejections` is the §6 "nothing silently dropped" surface (C1 anomaly UX).
  return { nodes: [], backlog: [], rejections: [] };
}

function findNode(snap, nodeId) {
  for (const n of snap.nodes) if (n.node_id === nodeId) return n;
  return null;
}
function findItem(node, itemId) {
  if (!node) return null;
  for (const it of node.items) if (it.item_id === itemId) return it;
  return null;
}

// Would attaching `nodeId` under `parentId` create a cycle? (parent chain walk)
function wouldCycle(snap, nodeId, parentId) {
  let cur = parentId;
  const seen = new Set();
  while (cur != null) {
    if (cur === nodeId) return true;          // parent chain leads back to self
    if (seen.has(cur)) return true;            // pre-existing cycle guard
    seen.add(cur);
    const p = findNode(snap, cur);
    cur = p ? p.parent_id : null;
  }
  return false;
}

function reject(snap, ev, reason) {
  snap.rejections.push({
    event_id: ev.event_id, type: ev.type, reason: reason, ts: ev.ts,
  });
}

function newNode(nodeId, parentId, title, treeId) {
  return {
    node_id: nodeId,
    parent_id: parentId == null ? null : parentId,
    title: title == null ? '' : String(title),
    tree_id: treeId || 'global',
    state: 'open',
    items: [],
    draft: null,
    cross_links: [],
    bound_sessions: [],
  };
}

// Apply ONE event to the in-progress snapshot (mutates `snap`).
function applyEvent(snap, ev, treeId) {
  switch (ev.type) {
    case 'branch-opened': {
      if (findNode(snap, ev.node_id)) { reject(snap, ev, 'node_id already exists'); return; }
      if (ev.parent_id !== null) {
        const parent = findNode(snap, ev.parent_id);
        if (!parent) { reject(snap, ev, 'parent_id does not resolve'); return; }
        if (wouldCycle(snap, ev.node_id, ev.parent_id)) { reject(snap, ev, 'would create a cycle'); return; }
      }
      // D5/FR-18: a branch-opened MAY carry an optional `tree_id` to partition
      // per-project trees within the single v1 state file (DEC-G). Optional
      // field, reducer-read only — additive, no required-field change, no major
      // bump. Absent ⇒ the file/global tree (Phase-0 behavior unchanged).
      snap.nodes.push(newNode(ev.node_id, ev.parent_id, ev.title, ev.tree_id || treeId));
      return;
    }
    case 'decision-raised':
    case 'question-raised':
    case 'action-added': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      if (findItem(node, ev.item_id)) { reject(snap, ev, 'item_id already exists on node'); return; }
      const kind = ev.type === 'decision-raised' ? 'decision'
        : ev.type === 'question-raised' ? 'question' : 'action';
      node.items.push({
        item_id: ev.item_id, kind: kind, text: String(ev.text),
        checked: false, deferred: false, scheduled_for: null, contested: null,
      });
      return;
    }
    case 'answered':
    case 'action-done': {
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      const expectAction = ev.type === 'action-done';
      if (expectAction && it.kind !== 'action') { reject(snap, ev, 'action-done on a non-action item'); return; }
      if (!expectAction && it.kind === 'action') { reject(snap, ev, 'answered on an action item (use action-done)'); return; }
      it.checked = true;
      return;
    }
    case 'concluded': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      // FR-7 invariant enforced in the reducer, not the writer.
      const hasUnchecked = node.items.some(function (it) { return !it.checked; });
      if (hasUnchecked) { reject(snap, ev, 'concluded while node has an unchecked item (FR-7)'); return; }
      const hasContested = node.items.some(function (it) { return it.contested; });
      if (hasContested) { reject(snap, ev, 'concluded while node has a contested item (D2/FR-7)'); return; }
      node.state = 'concluded';
      return;
    }
    case 're-opened': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      node.state = 'open';                       // reverses concluded, no data loss
      return;
    }
    case 'archived': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      node.state = 'archived';
      return;
    }
    case 'deferred': {
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.deferred = true;                        // §4 state tag (NOT a kind)
      it.scheduled_for = ev.scheduled_for == null ? null : String(ev.scheduled_for);
      // v1.1.2 item 28 — OPTIONAL additive local-time fields so a deferred
      // time re-displays unambiguously on any machine (scheduled_for stays
      // the canonical cross-machine ISO value; checkDefers still keys off it).
      // Absent ⇒ left undefined (Phase-0/v1.1 events unchanged).
      if (ev.scheduled_for_local != null) it.scheduled_for_local = String(ev.scheduled_for_local);
      if (ev.tz_offset_min != null) it.tz_offset_min = Number(ev.tz_offset_min);
      return;
    }
    case 'defer-cleared': {
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.deferred = false;                       // ONLY explicit user action clears it
      it.scheduled_for = null;
      return;
    }
    case 'draft-saved': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      node.draft = String(ev.draft_text);
      return;
    }
    case 'draft-cleared': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      node.draft = null;
      return;
    }
    case 'cross-linked': {
      const node = findNode(snap, ev.from_node);
      if (!node) { reject(snap, ev, 'from_node does not resolve'); return; }
      // §5: a non-hierarchical association; NEVER a parent edge.
      node.cross_links.push({ to: String(ev.to_node), tag: String(ev.tag) });
      return;
    }
    case 're-parented': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      const np = ev.new_parent_id;
      if (np !== null) {
        if (!findNode(snap, np)) { reject(snap, ev, 'new_parent_id does not resolve'); return; }
        if (np === ev.node_id) { reject(snap, ev, 're-parent onto self'); return; }
        if (wouldCycle(snap, ev.node_id, np)) { reject(snap, ev, 're-parent would create a cycle (FR-1)'); return; }
      }
      node.parent_id = np === null ? null : np;   // single parent preserved
      return;
    }
    case 'promoted': {
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      if (findNode(snap, ev.new_node_id)) { reject(snap, ev, 'new_node_id already exists'); return; }
      // FR-3/C5: the ONLY way one item becomes its own branch. New branch is a
      // child of the item's current node (strict tree preserved — single parent).
      const promoted = newNode(ev.new_node_id, node.node_id, it.text, node.tree_id);
      promoted.items.push({
        item_id: it.item_id, kind: it.kind, text: it.text,
        checked: it.checked, deferred: it.deferred, scheduled_for: it.scheduled_for,
      });
      snap.nodes.push(promoted);
      return;
    }
    case 'backlog-added': {
      for (const b of snap.backlog) if (b.item_id === ev.item_id) { reject(snap, ev, 'backlog item_id exists'); return; }
      snap.backlog.push({
        item_id: ev.item_id, tree_id: String(ev.tree_id),
        priority: String(ev.priority), text: String(ev.text),
        activated: false,
      });
      return;
    }
    case 'backlog-activated': {
      let b = null;
      for (const x of snap.backlog) if (x.item_id === ev.item_id) b = x;
      if (!b) { reject(snap, ev, 'backlog item not found'); return; }
      if (findNode(snap, ev.new_node_id)) { reject(snap, ev, 'new_node_id already exists'); return; }
      b.activated = true;
      b.activated_node = ev.new_node_id;
      // FR-22: emits the equivalent of a branch-opened root, carrying the
      // backlog item's context. `origin` drives the BF-1 persistent on-node
      // `▸ ready to start in Dispatch` handoff badge until Dispatch acts on it.
      var an = newNode(ev.new_node_id, null, b.text, b.tree_id);
      an.origin = 'backlog-activated';
      an.context_refs = (b.context_refs || []).slice();
      snap.nodes.push(an);
      return;
    }
    case 'context-attached': {
      // FR-21: attach to a node OR a backlog item. Recorded on whichever resolves.
      const node = findNode(snap, ev.target);
      if (node) {
        node.context_refs = node.context_refs || [];
        node.context_refs.push(String(ev.context_ref));
        return;
      }
      let b = null;
      for (const x of snap.backlog) if (x.item_id === ev.target) b = x;
      if (b) {
        b.context_refs = b.context_refs || [];
        b.context_refs.push(String(ev.context_ref));
        return;
      }
      reject(snap, ev, 'context-attached target does not resolve');
      return;
    }
    case 'reordered': {
      // FR-29: persist explicit ordering. Recorded as a snapshot-level hint;
      // the GUI applies it at render time.
      snap.order = snap.order || {};
      snap.order[String(ev.scope)] = Array.isArray(ev.ordered_ids)
        ? ev.ordered_ids.slice() : [];
      return;
    }
    case 'annotated': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      node.annotations = node.annotations || [];
      node.annotations.push({ text: String(ev.text), ts: ev.ts });
      return;
    }
    case 'session-bound': {
      // FR-15: a node may track many Claude Code sessions (many-to-many).
      // Additive within schema major 1 (no contract break) — closes the
      // systems-designer A1 non-blocking finding (in-flight note 2026-05-17).
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      if (node.bound_sessions.indexOf(ev.session_id) === -1) {
        node.bound_sessions.push(String(ev.session_id));
      }
      return;
    }
    case 'session-unbound': {
      const node = findNode(snap, ev.node_id);
      if (!node) { reject(snap, ev, 'node_id does not resolve'); return; }
      const ix = node.bound_sessions.indexOf(ev.session_id);
      if (ix !== -1) node.bound_sessions.splice(ix, 1);
      return;
    }
    case 'contested': {
      // D2 / FR-9 low-emphasis safety net. Additive event type (ADR-032 §1
      // additive rule — no major bump). A contested item is a derived
      // `it.contested` annotation; it counts as NOT checked for FR-7
      // auto-conclude (enforced in the `concluded` case below).
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.contested = { direction: String(ev.direction), note: String(ev.note), ts: ev.ts };
      return;
    }
    case 'contest-resolved': {
      const node = findNode(snap, ev.node_id);
      const it = findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      // Resolution is explicit-only, never silent/auto (UX-C1, SM-4).
      it.contested = null;
      if (ev.resolution === 'accept-theirs') it.checked = true;
      else if (ev.resolution === 'keep-mine-reopen') it.checked = false;
      return;
    }
    // v1.1-ux item 9 — rich item content. ADDITIVE (ADR-032 §1). Sets the
    // optional `it.details` payload; last-writer-wins (idempotent backfill).
    case 'item-details-set': {
      const node = findNode(snap, ev.node_id);
      const it = node && findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.details = (ev.details && typeof ev.details === 'object') ? ev.details : null;
      return;
    }
    // v1.1-ux item 10 — inline response. ADDITIVE. The item stays !checked
    // (still "waiting") but carries `it.responded`; the GUI derives the
    // "responded — awaiting confirmation" de-emphasis. NOT a conclude.
    case 'action-responded': {
      const node = findNode(snap, ev.node_id);
      const it = node && findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.responded = { text: String(ev.response_text), ts: ev.ts };
      return;
    }
    // v1.1-ux item 7 — Undo of mark-done/answered. ADDITIVE inverse event
    // (the append-only log has no built-in uncheck). Re-surfaces the item.
    case 'item-unchecked': {
      const node = findNode(snap, ev.node_id);
      const it = node && findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.checked = false;
      it.backlogged = false;                     // un-park too (round-trip)
      return;
    }
    // v1.1.2 item 28 — "Defer → until further notice — move to Backlog".
    // ADDITIVE. Parks the item out of "Waiting on you" WITHOUT checking it
    // (it is not done — the GUI also posts a backlog-added so the work is
    // tracked; the Backlog "Activate" button is the return path). The GUI's
    // isWaiting() treats a backlogged item as not-waiting.
    case 'item-backlogged': {
      const node = findNode(snap, ev.node_id);
      const it = node && findItem(node, ev.item_id);
      if (!it) { reject(snap, ev, 'item not found'); return; }
      it.backlogged = true;
      return;
    }
    // v1.1.2 items 33+34 — priority assignment on any item (actions on a
    // node OR backlog entries) by `target_id`. P1..P5 integer; P5 = default
    // unassigned (display: no badge). Last-writer-wins; same target_id
    // re-emission is idempotent. Both GUI (actor='gui') and Dispatch
    // (actor='dispatch') can assign — same event shape, actor differs.
    case 'priority-assigned': {
      const p = Number(ev.priority);
      if (!(p >= 1 && p <= 5)) { reject(snap, ev, 'priority must be integer 1..5'); return; }
      // Resolve target: node item first, then backlog entry.
      for (const node of snap.nodes) {
        const it = findItem(node, ev.target_id);
        if (it) { it.priority = p; return; }
      }
      for (const b of snap.backlog) {
        if (b.item_id === ev.target_id) { b.priority_num = p; return; }
      }
      reject(snap, ev, 'priority-assigned target_id does not resolve');
      return;
    }
    // v1.1.2 item 35 — explicit "Send to Dispatch" of a staged note.
    // Appends to the node's notes_sent history (preserves audit trail);
    // exposes last_sent_note for the GUI's ✓-sent indicator. The reader
    // hook surfaces these events to Dispatch (additive filter).
    case 'branch-note-add': {
      const node = findNode(snap, ev.target);
      if (!node) { reject(snap, ev, 'branch-note-add target does not resolve'); return; }
      node.notes_sent = node.notes_sent || [];
      const entry = { text: String(ev.note_text), ts: ev.ts, actor: ev.actor };
      node.notes_sent.push(entry);
      node.last_sent_note = entry;          // GUI badge target
      return;
    }
    default:
      // §1 forward-tolerance: unknown type within the same major is skipped,
      // never an error, never a major bump.
      return;
  }
}

// Pure: events[] -> snapshot (the §7a recovery primitive). Backward-compatible
// alias fields (id / opened_at) are added so the Phase-0 web/app.js renderer
// keeps working unchanged (regression baseline) — in-scope reader glue.
function deriveSnapshot(events, treeId) {
  const snap = emptySnapshot();
  for (const ev of events) {
    if (!ev || typeof ev.type !== 'string') continue;
    applyEvent(snap, ev, treeId);
  }
  snap.nodes = snap.nodes.map(function (n) {
    const opened = (events.find(function (e) {
      return e.type === 'branch-opened' && e.node_id === n.node_id;
    }) || {}).ts || null;
    return Object.assign({}, n, { id: n.node_id, opened_at: opened });
  });
  return snap;
}

module.exports = { emptySnapshot, deriveSnapshot, applyEvent, wouldCycle };
