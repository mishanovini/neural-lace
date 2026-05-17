'use strict';
// Minimal-but-real state contract for the Conversation Tree UI Walking Skeleton
// (ADR-031 Option 2, Phase 0 / Task 0.1). Forward-shaped toward ADR-032/Phase A;
// the full event-type enum + node shape is deliberately NOT pre-built here.
//
// Shape: one JSON file with
//   schema_version : int (starts at 1; ADR-032 will own the real layout)
//   events         : append-only array; Phase 0 has ONE type: "branch-opened"
//   snapshot       : derived { nodes: [...] } reduced from events
//
// Atomicity (ADR-031 r7 Pin 3b): every state mutation is ONE write-temp-then-
// rename. fs.renameSync is atomic on a single filesystem, so a concurrent
// reader of the well-known path always sees a whole file with N or N+1 whole
// events, never a half-written event. (Chosen over append+fsync because the
// snapshot must be recomputed and rewritten on every append anyway, so the
// whole file is replaced atomically in one rename — the simplest correct
// primitive for "reader sees N or N+1 whole events, never half".)

const fs = require('fs');
const path = require('path');

// Well-known path resolution (Phase 0: single global file; per-project +
// global-tree path resolution is ADR-032 / FR-18 / FR-25, NOT decided here).
const STATE_DIR = __dirname;
const STATE_FILE = path.join(STATE_DIR, 'tree-state.json');

const SCHEMA_VERSION = 1;

function emptyState() {
  return { schema_version: SCHEMA_VERSION, events: [], snapshot: { nodes: [] } };
}

function readState() {
  try {
    const raw = fs.readFileSync(STATE_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    if (typeof parsed.schema_version !== 'number') return emptyState();
    return parsed;
  } catch (err) {
    if (err && err.code === 'ENOENT') return emptyState();
    // Torn/corrupt file: Phase 0 returns empty; real torn-snapshot recovery
    // via log replay is Phase A (Pin 3a). Surface, do not silently swallow.
    process.stderr.write('[state] could not parse state file, treating as empty: ' + err.message + '\n');
    return emptyState();
  }
}

// Reduce events -> snapshot. Phase 0 reducer handles only "branch-opened".
function deriveSnapshot(events) {
  const nodes = [];
  for (const ev of events) {
    if (ev.type === 'branch-opened') {
      nodes.push({
        id: ev.id,
        parent_id: ev.parent_id,
        title: ev.title,
        opened_at: ev.timestamp,
      });
    }
  }
  return { nodes };
}

// Append ONE branch-opened event + rewrite snapshot, in ONE atomic rename.
function appendBranchOpened({ id, parentId = null, title }) {
  if (!id || !title) throw new Error('appendBranchOpened requires id and title');
  const state = readState();
  state.events.push({
    type: 'branch-opened',
    id: String(id),
    parent_id: parentId === null ? null : String(parentId),
    title: String(title),
    timestamp: new Date().toISOString(),
  });
  state.snapshot = deriveSnapshot(state.events);

  const tmp = STATE_FILE + '.tmp.' + process.pid + '.' + Date.now();
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2), 'utf8');
  fs.renameSync(tmp, STATE_FILE); // atomic single-fs publish (Pin 3b)
  return state;
}

module.exports = { STATE_FILE, SCHEMA_VERSION, emptyState, readState, deriveSnapshot, appendBranchOpened };

// CLI: `node state.js seed "Title"`  -> append a root branch-opened.
//      `node state.js seed "Title" <parentId>` -> append a child.
if (require.main === module) {
  const [, , cmd, title, parentId] = process.argv;
  if (cmd === 'seed') {
    if (!title) { process.stderr.write('usage: node state.js seed "<title>" [parentId]\n'); process.exit(2); }
    const id = 'n-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e4);
    const s = appendBranchOpened({ id, parentId: parentId || null, title });
    process.stdout.write('appended branch-opened id=' + id + '; total events=' + s.events.length +
      '; snapshot nodes=' + s.snapshot.nodes.length + '\n');
  } else {
    process.stderr.write('unknown command: ' + cmd + '\n');
    process.exit(2);
  }
}
