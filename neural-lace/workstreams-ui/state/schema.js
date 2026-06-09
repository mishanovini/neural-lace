'use strict';
// ADR-032 §1/§2 — schema constants, event-type enum, version semantics.
// This module owns the FROZEN contract surface: changing/removing a required
// field of an existing event, or the snapshot/marker contract, is a MAJOR bump
// (ADR-032 §1). Adding a new event type to EVENT_TYPES is additive (no bump).

// §1 — schema_version is a single integer = the MAJOR version. v1 = 1.
// (Unchanged from the Phase-0 skeleton's SCHEMA_VERSION = 1: A2's field
// renames are pre-freeze shaping within major 1, NOT a major bump — ADR-032
// §1 + the systems-designer pre-freeze-baseline ruling.)
const SCHEMA_VERSION = 1;

// The distinct refuse message a reader emits for an unknown MAJOR (Pin 2 /
// ADR-032 §1/§8). Exact string — gates + GUI key off it.
const SCHEMA_TOO_NEW_MESSAGE = 'schema too new — upgrade the GUI/gate';

// §2 — finalized v1 event-type enum (closed set; new types are additive).
const EVENT_TYPES = Object.freeze([
  'branch-opened',
  'decision-raised',
  'question-raised',
  'action-added',
  'answered',
  'action-done',
  'concluded',
  're-opened',
  'archived',
  'deferred',
  'defer-cleared',
  'draft-saved',
  'draft-cleared',
  'cross-linked',
  're-parented',
  'promoted',
  'backlog-added',
  'backlog-activated',
  'context-attached',
  'reordered',
  'annotated',
  'session-bound',
  'session-unbound',
  'contested',
  'contest-resolved',
  // v1.1-ux (items 9/10/7) — ADDITIVE within schema major 1 (ADR-032 §1:
  // "Adding a new event type to EVENT_TYPES is additive (no bump)"). None
  // changes/removes a required field of an existing event; schema_version
  // stays 1; the conv-tree gates key off the major and are unaffected.
  'item-details-set',
  'action-responded',
  'item-unchecked',
  // v1.1.2 item 28 — "Defer → until further notice — move to Backlog".
  // ADDITIVE within schema major 1 (same rule/precedent as the v1.1-ux trio
  // above): a new event type, no required-field change to any existing
  // event, schema_version stays 1, conv-tree gates key off the major and are
  // unaffected. Parks an item out of "Waiting on you" without checking it
  // (NOT a quiet-resolve); the Backlog "Activate" button is the return path.
  'item-backlogged',
  // v1.1.2 items 33+34+35 — ADDITIVE within schema major 1 (same precedent
  // as the v1.1-ux trio + item 28's item-backlogged). All three are
  // last-writer-wins on the target's optional fields; reducer treats
  // re-emission for the same target as idempotent.
  'priority-assigned',          // item 33+34: P1–P5 on action/decision/question/backlog
  'branch-note-add',            // item 35: explicit "Send to Dispatch" send of a staged note
  // v2 redesign 2026-05-23 — UX-VR-13 context-as-textarea: edit the context
  // text of an existing backlog item. ADDITIVE within schema major 1
  // (same precedent as the other v1.1/v1.1.2 additions above): no
  // required-field change to any existing event, schema_version stays 1.
  // Last-writer-wins on the target's context_text field. Idempotent on
  // event_id per the standard envelope.
  'backlog-context-set',
  // Workstreams reframe 2026-05-30 (Phase 1) — explicit WorkItem lifecycle
  // transitions. ADDITIVE within schema major 1 (same rule/precedent as every
  // addition above): three new event types, NO required-field change to any
  // existing event, schema_version stays 1; the conv-tree/workstreams gates
  // key off the major and are unaffected. Each sets the target item's derived
  // `state` (proposed → committed → in-flight → blocked → shipped/closed) and
  // is last-writer-wins on that field; re-emission for the same event_id is an
  // idempotent no-op per the standard envelope. `item-shipped` additionally
  // marks the item `checked` (shipped ⇒ the work is done, leaves the waiting
  // set). The OPTIONAL `tier` + `serves_item_id` fields on `branch-opened`
  // (read in the reducer; NOT added to EVENT_REQUIRED_FIELDS) carry the
  // four-tier hierarchy + the session→work-item link — both optional so every
  // existing branch-opened event parses unchanged.
  'item-committed',
  'item-shipped',
  'item-blocked',
  // decision-context-gate-2026-05-29 (DEC-2 + forthcoming ADR-037):
  // ADDITIVE within schema major 1 (ADR-032 §1 — "Adding a new event type
  // to EVENT_TYPES is additive (no bump)"; no required-field change to any
  // existing event; schema_version stays 1; conv-tree gates key off the
  // major and are unaffected). Emitted ONLY by the `autonomous_action`
  // fence-grammar category — a fait-accompli log entry of an action the
  // agent took unilaterally, distinct from `decision-raised` /
  // `question-raised` / `action-added` (those are PENDING items requiring
  // the user). The `details` payload is the validated autonomous_action
  // fence payload (action_taken / reasoning / reversibility / references)
  // — the reducer's forward-tolerance accepts any sub-shape and does NOT
  // declare sub-fields at the schema layer (the
  // decision-context-schema.js Zod module is the SOLE NORMATIVE validator
  // for the payload's interior). See docs/plans/decision-context-gate-2026-05-29.md
  // Section B grammar + DEC-2.
  'autonomous-action-logged',
  // Phase D (2026-06-09) — explicit "merged work reached production" transition.
  // ADDITIVE within schema major 1 (ADR-032 §1: a new event type is additive,
  // no required-field change to any existing event, schema_version stays 1; the
  // conv-tree/workstreams gates key off the major and are unaffected). Lets the
  // tracker distinguish "merged/shipped" from "live in production" so Misha can
  // see every effort that did NOT reach deployed. `item-shipped` additionally
  // gained an OPTIONAL `deployed:true` flag (reducer-read-only, not a required
  // field) to record merged-AND-deployed in one event.
  'item-deployed',
]);

// §2 — per-event required fields IN ADDITION TO the envelope
// (event_id, type, ts, actor). Used by validateEvent + the reducer.
const EVENT_REQUIRED_FIELDS = Object.freeze({
  'branch-opened': ['node_id', 'parent_id', 'title'],
  'decision-raised': ['node_id', 'item_id', 'text'],
  'question-raised': ['node_id', 'item_id', 'text'],
  'action-added': ['node_id', 'item_id', 'text'],
  'answered': ['node_id', 'item_id'],
  'action-done': ['node_id', 'item_id'],
  'concluded': ['node_id'],
  're-opened': ['node_id'],
  'archived': ['node_id'],
  'deferred': ['node_id', 'item_id', 'scheduled_for'],
  'defer-cleared': ['node_id', 'item_id'],
  'draft-saved': ['node_id', 'draft_text'],
  'draft-cleared': ['node_id'],
  'cross-linked': ['from_node', 'to_node', 'tag'],
  're-parented': ['node_id', 'new_parent_id'],
  'promoted': ['node_id', 'item_id', 'new_node_id'],
  'backlog-added': ['item_id', 'tree_id', 'priority', 'text'],
  'backlog-activated': ['item_id', 'new_node_id'],
  'context-attached': ['target', 'context_ref'],
  'reordered': ['scope', 'ordered_ids'],
  'annotated': ['node_id', 'text'],
  'session-bound': ['node_id', 'session_id'],
  'session-unbound': ['node_id', 'session_id'],
  'contested': ['node_id', 'item_id', 'direction', 'note'],
  'contest-resolved': ['node_id', 'item_id', 'resolution'],
  // v1.1-ux additive (see EVENT_TYPES note above)
  'item-details-set': ['node_id', 'item_id', 'details'],
  'action-responded': ['node_id', 'item_id', 'response_text'],
  'item-unchecked': ['node_id', 'item_id'],
  // v1.1.2 item 28 additive (see EVENT_TYPES note above). The `deferred`
  // event additionally accepts OPTIONAL `scheduled_for_local` + `tz_offset_min`
  // for unambiguous local re-display — those are NOT added here (optional, no
  // contract change). `item-backlogged` requires only the item locator.
  'item-backlogged': ['node_id', 'item_id'],
  // v1.1.2 items 33+34+35
  'priority-assigned': ['target_id', 'priority'],   // P1=1..P5=5; both GUI and Dispatch emit (actor differs)
  'branch-note-add':   ['target', 'note_text'],     // explicit Send of a staged note to Dispatch (target=node_id)
  // v2 redesign 2026-05-23 — UX-VR-13: edit context_text on a backlog item.
  'backlog-context-set': ['item_id', 'context_text'],
  // Workstreams reframe 2026-05-30 (Phase 1) — three WorkItem lifecycle
  // transitions. Each requires only the item locator (node_id + item_id);
  // OPTIONAL payloads (`reason` on committed/blocked, `evidence` =
  // commit-SHA/PR-URL on shipped) are NOT required-fields (additive, no
  // contract change). The `tier` + `serves_item_id` optional fields ride on
  // `branch-opened` and are deliberately absent here (optional ⇒ not required).
  // Component B (orchestration-architecture §3) adds one more OPTIONAL payload:
  // `blocked_on` on `item-blocked` (the WorkItem id this item is blocked ON) —
  // also NOT a required field (absent ⇒ a blocked item with no declared
  // dependency). The reconciler keys its cascade off it; reducer captures
  // `it.blocked_on`. Additive, no contract change, schema_version stays 1.
  'item-committed': ['node_id', 'item_id'],
  'item-shipped':   ['node_id', 'item_id'],
  'item-blocked':   ['node_id', 'item_id'],
  // decision-context-gate-2026-05-29 (DEC-2): autonomous_action fence
  // category emits this event. node_id locates the branch; text is a
  // short human-readable summary (matches branch-note-add's text
  // convention); details is the FULL validated autonomous_action payload
  // (action_taken / reasoning / reversibility / references[]). The
  // reducer treats `details` as forward-tolerant — unknown sub-fields are
  // preserved on read, NO sub-fields are validated at the schema layer
  // (the Zod module decision-context-schema.js is the SOLE NORMATIVE
  // validator for the payload interior).
  'autonomous-action-logged': ['node_id', 'text', 'details'],
  // Phase D (2026-06-09): requires only the item locator. OPTIONAL `evidence`
  // (deploy URL / prod SHA) is captured by the reducer but NOT a required field
  // (additive, no contract change, schema_version stays 1).
  'item-deployed': ['node_id', 'item_id'],
});

const ACTORS = Object.freeze(['dispatch', 'gui']);
const ITEM_KINDS = Object.freeze(['decision', 'question', 'action']);

// `parent_id: null` is an allowed required value (root node, ADR-032 §2) —
// these fields are "required to be PRESENT" but null is a legal value.
const NULLABLE_REQUIRED = Object.freeze(new Set([
  'parent_id', 'scheduled_for', 'new_parent_id',
]));

// Monotonic-ish, ASCII, globally-unique-within-file idempotency key
// (ADR-032 §2 `event_id`). ULID-shaped: 48-bit ms timestamp + 80 bits random,
// Crockford base32 — lexicographically sortable by creation time, no runtime dep.
const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function generateEventId() {
  let ts = Date.now();
  const timeChars = new Array(10);
  for (let i = 9; i >= 0; i--) { timeChars[i] = CROCKFORD[ts % 32]; ts = Math.floor(ts / 32); }
  let rand = '';
  for (let i = 0; i < 16; i++) rand += CROCKFORD[Math.floor(Math.random() * 32)];
  return timeChars.join('') + rand;
}

// Envelope + per-type required-field validation (ADR-032 §2). Returns the
// event on success; throws Error with a specific message on a violation.
function validateEvent(ev) {
  if (!ev || typeof ev !== 'object') throw new Error('event must be an object');
  if (typeof ev.type !== 'string' || EVENT_TYPES.indexOf(ev.type) === -1) {
    throw new Error('event.type must be one of the v1 enum; got: ' + String(ev.type));
  }
  if (typeof ev.event_id !== 'string' || ev.event_id.length === 0) {
    throw new Error('event.event_id (idempotency key) is required, non-empty string');
  }
  if (typeof ev.ts !== 'string' || ev.ts.length === 0) {
    throw new Error('event.ts (ISO-8601) is required');
  }
  if (ACTORS.indexOf(ev.actor) === -1) {
    throw new Error('event.actor must be "dispatch" or "gui"; got: ' + String(ev.actor));
  }
  const req = EVENT_REQUIRED_FIELDS[ev.type] || [];
  for (const f of req) {
    if (!(f in ev)) throw new Error(ev.type + ' requires field "' + f + '"');
    if (ev[f] === null && !NULLABLE_REQUIRED.has(f)) {
      throw new Error(ev.type + ' field "' + f + '" may not be null');
    }
    if (ev[f] === undefined) throw new Error(ev.type + ' field "' + f + '" may not be undefined');
  }
  return ev;
}

module.exports = {
  SCHEMA_VERSION,
  SCHEMA_TOO_NEW_MESSAGE,
  EVENT_TYPES,
  EVENT_REQUIRED_FIELDS,
  ACTORS,
  ITEM_KINDS,
  generateEventId,
  validateEvent,
};
