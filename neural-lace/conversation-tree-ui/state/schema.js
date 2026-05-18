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
