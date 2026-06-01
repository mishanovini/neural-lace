'use strict';
/*
 * migrate-topology-to-project-roots.js — one-shot, log-preserving migration of
 * the Conversation-Tree state from date-root topology to PROJECT-root topology.
 *
 * Why: the original backfill parented project nodes under `today-<date>` day
 * nodes, and made the project node a global singleton (first creator wins).
 * Because the reducer rejects a duplicate node_id, every project stayed pinned
 * under the FIRST date that created it, so later-date sessions rendered under
 * an old day node (the bug Misha reported). Dispatch is single-threaded, so
 * per-project chronological order is implicit — date grouping is unnecessary.
 *
 * Target topology: project nodes are top-level roots (parent_id: null);
 * sessions stay under their project; subagents under sessions; no date roots.
 *
 * Approach (per Misha's constraint — DO NOT blow away the append-only log):
 *   - The events[] array is the source of truth. This migration APPENDS new
 *     events the reducer already understands:
 *       * `re-parented` (new_parent_id: null) for every `proj-*` node whose
 *         current parent_id is not already null.
 *       * `archived` for every `today-*` date node (so they stop rendering as
 *         empty roots; the GUI hides archived nodes by default).
 *   - No event is rewritten or deleted. Replaying the (now longer) log through
 *     the unchanged reducer yields the new topology deterministically.
 *
 * Idempotent: deterministic event_ids; the state library dedups by event_id,
 * so a second run appends nothing new.
 *
 * Usage:
 *   node scripts/migrate-topology-to-project-roots.js              # migrate (with auto-backup)
 *   node scripts/migrate-topology-to-project-roots.js --dry-run    # show planned events, write nothing
 *   node scripts/migrate-topology-to-project-roots.js --sink /path/to/tree-state.json
 *   node scripts/migrate-topology-to-project-roots.js --no-backup  # skip the .bak copy
 */
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
function flag(name) { return argv.includes(name); }
function val(name, dflt) { const i = argv.indexOf(name); return (i >= 0 && argv[i + 1]) ? argv[i + 1] : dflt; }

const DRY_RUN = flag('--dry-run');
const NO_BACKUP = flag('--no-backup');

const STATE_LIB = path.resolve(__dirname, '..', 'state', 'state.js');
const s = require(STATE_LIB);
const SINK = val('--sink', s.STATE_FILE);

function isProjectNode(id) { return /^proj-/.test(id); }
function isDateNode(id) { return /^today-/.test(id); }

function main() {
  if (!fs.existsSync(SINK)) {
    console.error('[migrate] state file not found:', SINK);
    process.exit(1);
  }

  // Read current state + derive the live snapshot to decide what needs moving.
  const state = s.readState({ statePath: SINK });
  const snap = state.snapshot && state.snapshot.nodes
    ? state.snapshot
    : s.deriveSnapshot(state.events || [], state.tree_id || 'global');

  const projToReparent = snap.nodes.filter(function (n) {
    return isProjectNode(n.node_id) && n.parent_id !== null;
  });
  const datesToArchive = snap.nodes.filter(function (n) {
    return isDateNode(n.node_id) && n.state !== 'archived';
  });

  console.log('[migrate] sink:', SINK);
  console.log('[migrate] dry-run:', DRY_RUN);
  console.log('[migrate] project nodes to re-parent -> null:', projToReparent.length);
  projToReparent.forEach(function (n) { console.log('   re-parent', n.node_id, '(was under', n.parent_id + ')'); });
  console.log('[migrate] date nodes to archive:', datesToArchive.length);
  datesToArchive.forEach(function (n) { console.log('   archive', n.node_id); });

  if (projToReparent.length === 0 && datesToArchive.length === 0) {
    console.log('[migrate] nothing to do — topology already project-rooted.');
    return;
  }

  // Build the migration events (deterministic ids -> idempotent re-runs).
  const ts = new Date().toISOString();
  const events = [];
  for (const n of projToReparent) {
    events.push({
      event_id: 'cte-migrate-reparent-' + n.node_id,
      type: 're-parented',
      node_id: n.node_id,
      new_parent_id: null,
      actor: 'dispatch',
      ts: ts,
    });
  }
  for (const n of datesToArchive) {
    events.push({
      event_id: 'cte-migrate-archive-' + n.node_id,
      type: 'archived',
      node_id: n.node_id,
      actor: 'dispatch',
      ts: ts,
    });
  }

  if (DRY_RUN) {
    console.log('---');
    console.log('[dry-run] would append', events.length, 'event(s):');
    events.forEach(function (e) { console.log('  ', e.type, e.node_id, '->', e.new_parent_id === undefined ? '(archived)' : e.new_parent_id); });
    return;
  }

  // Back up the live state file before any write.
  if (!NO_BACKUP) {
    const stamp = ts.replace(/[:.]/g, '-');
    const bak = SINK + '.bak.' + stamp;
    fs.copyFileSync(SINK, bak);
    console.log('[migrate] backup written:', bak);
  }

  let appended = 0, skipped = 0;
  for (const ev of events) {
    try { s.appendEvent(ev, { statePath: SINK }); appended++; }
    catch (e) { skipped++; process.stderr.write('skip ' + ev.type + ' ' + ev.node_id + ': ' + (e && e.message || e) + '\n'); }
  }

  // Verify the post-migration snapshot.
  const after = s.readState({ statePath: SINK });
  const afterSnap = after.snapshot && after.snapshot.nodes
    ? after.snapshot
    : s.deriveSnapshot(after.events || [], after.tree_id || 'global');
  const stillNonRootProjects = afterSnap.nodes.filter(function (n) {
    return isProjectNode(n.node_id) && n.parent_id !== null;
  });
  const liveRoots = afterSnap.nodes.filter(function (n) {
    return n.parent_id === null && n.state !== 'archived';
  });

  console.log('---');
  console.log('[migrate] events appended:', appended, '(skipped:', skipped + ')');
  console.log('[migrate] project nodes still non-root (should be 0):', stillNonRootProjects.length);
  console.log('[migrate] live (non-archived) roots after migration:', liveRoots.map(function (n) { return n.node_id; }).join(', '));
  if (stillNonRootProjects.length > 0) {
    console.error('[migrate] WARNING: some project nodes are still not roots:', stillNonRootProjects.map(function (n) { return n.node_id; }).join(', '));
    process.exit(2);
  }
  console.log('[migrate] OK — topology is project-rooted.');
}

main();
