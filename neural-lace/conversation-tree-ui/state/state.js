'use strict';
// Public facade for the Conversation Tree UI state library (ADR-032 §1–§7).
// Phase 0 shipped a minimal-but-real spine here; A2 evolves it ADDITIVELY
// within schema major 1 to the frozen ADR-032 contract. The Phase-0 public
// surface (STATE_FILE, readState, deriveSnapshot, appendBranchOpened, the
// `seed` CLI) is preserved so server.js / web/app.js keep working unchanged
// (the Walking Skeleton 3-step regression baseline). New surface: appendEvent
// (the general §2 enum), resolveStatePath (§5), SchemaTooNewError (§1/Pin 2).

const path = require('path');
const schema = require('./schema.js');
const reducer = require('./reducer.js');
const store = require('./store.js');

const SCHEMA_VERSION = schema.SCHEMA_VERSION;

// Phase-0 well-known path compatibility: the skeleton used a single file at
// state/tree-state.json. Keep that exact path as the DEFAULT so server.js
// (which destructures STATE_FILE) and the seed CLI behave identically. The
// real §5 per-project + global resolver is available via resolveStatePath /
// the opts.statePath / opts.treeId knobs on the new API.
const STATE_FILE = path.join(__dirname, 'tree-state.json');
const DEFAULT_OPTS = { statePath: STATE_FILE, treeId: 'global' };

// Backward-compatible reader. Returns { schema_version, tree_id, events,
// snapshot } where snapshot is torn-recovery-safe (§7a) AND carries the
// Phase-0 alias fields (node.id / node.opened_at) via the reducer so the
// unmodified web/app.js renderer still works (regression baseline).
// Pin 2 (§1): an unknown MAJOR throws SchemaTooNewError — callers that want
// the Phase-0 "treat as empty" leniency must catch it explicitly; the GUI
// glue in server.js does (distinct refuse, never a mis-parse).
function readState(opts) {
  return store.readState(Object.assign({}, DEFAULT_OPTS, opts || {}));
}

// Pure events[] -> snapshot (the §7a recovery primitive; also what the
// reducer uses internally). Kept exported for compatibility with any Phase-0
// caller + the property suite.
function deriveSnapshot(events, treeId) {
  return reducer.deriveSnapshot(events, treeId || 'global');
}

// General §2 append: one event, atomic single-fs publish, idempotent on
// event_id, compaction-aware, audit-logged. The envelope (event_id/ts/actor)
// is auto-filled when omitted.
function appendEvent(eventInput, opts) {
  return store.appendEvent(eventInput, Object.assign({}, DEFAULT_OPTS, opts || {}));
}

// Phase-0 convenience preserved verbatim in behavior: append ONE
// branch-opened. Maps the old { id, parentId, title } shape onto the §2
// envelope (node_id/parent_id/title + event_id/ts/actor auto-filled).
function appendBranchOpened(input, opts) {
  input = input || {};
  const nodeId = input.node_id || input.id;
  const title = input.title;
  if (!nodeId || !title) throw new Error('appendBranchOpened requires id/node_id and title');
  const parentId = (input.parentId === undefined ? input.parent_id : input.parentId);
  const r = appendEvent({
    type: 'branch-opened',
    node_id: String(nodeId),
    parent_id: parentId == null ? null : String(parentId),
    title: String(title),
    actor: input.actor || 'dispatch',
  }, opts);
  return r.state; // Phase-0 callers expect the resulting state object
}

module.exports = {
  STATE_FILE,
  SCHEMA_VERSION,
  SCHEMA_TOO_NEW_MESSAGE: schema.SCHEMA_TOO_NEW_MESSAGE,
  SchemaTooNewError: store.SchemaTooNewError,
  EVENT_TYPES: schema.EVENT_TYPES,
  resolveStatePath: store.resolveStatePath,
  auditPathFor: store.auditPathFor,
  replayAuditLog: store.replayAuditLog,
  generateEventId: schema.generateEventId,
  validateEvent: schema.validateEvent,
  emptyState: function (treeId) { return store.emptyState(treeId); },
  readState,
  deriveSnapshot,
  appendEvent,
  appendBranchOpened,
  __writeTornForTest: store.__writeTornForTest,
};

// CLI preserved (Phase-0 Walking Skeleton step 1 + step 3 driver):
//   node state.js seed "Title"            -> append a root branch-opened
//   node state.js seed "Title" <parentId> -> append a child
if (require.main === module) {
  const [, , cmd, title, parentId] = process.argv;
  if (cmd === 'seed') {
    if (!title) { process.stderr.write('usage: node state.js seed "<title>" [parentId]\n'); process.exit(2); }
    const id = 'n-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e4);
    const s = appendBranchOpened({ id: id, parentId: parentId || null, title: title });
    process.stdout.write('appended branch-opened node_id=' + id + '; total events=' + s.events.length +
      '; snapshot nodes=' + s.snapshot.nodes.length + '\n');
  } else {
    process.stderr.write('unknown command: ' + String(cmd) + '\n');
    process.exit(2);
  }
}
