#!/usr/bin/env node
'use strict';
// surface-pending-asks.js — surface the orchestrator's CURRENT pending
// asks into the Workstreams UI so the operator's "awaiting me" view is a
// live frame of reference (not empty).
//
// WHY THIS EXISTS (2026-06-05): the decision-context emit pipeline is
// healthy end-to-end (decision-context-gate.sh --self-test 29/29; the gate
// attaches items to the `proj-<slug>` project root via state.js appendEvent,
// which renders cleanly under that project). The GUI was empty ONLY because
// no decision FENCE had ever been emitted to this state — the audit log held
// only branch-opened + concluded events, zero decision/question/action
// events. orchestrator-prime authors its asks as fences, but the gate is a
// Stop hook and orchestrator-prime is a long-running loop whose Stop rarely
// fires, so its asks had not flushed into the state the GUI reads.
//
// This utility is the manual surface: it emits the named pending asks via
// the SAME facade + node target the gate uses (state.js appendEvent →
// proj-<slug>), so they render identically to an auto-emitted fence. It is
// IDEMPOTENT (deterministic event_ids; the facade dedupes per event_id), so
// re-running is a no-op. As orchestrator-prime's own fences flush, the gate
// replaces these brief seeds with the rich fence payloads (same item_ids ⇒
// item-details-set just enriches; no duplication).
//
// Usage:
//   node scripts/surface-pending-asks.js          # emit the default asks
//   node scripts/surface-pending-asks.js --list    # print current items, no write
//
// Each ask carries surfaced_by:"surface-pending-asks" + a source pointer so
// provenance is honest — these summarise asks whose full context lives in the
// orchestrator-prime session thread.

const path = require('path');
const st = require(path.join(__dirname, '..', 'state', 'state.js'));

// The project root the gate attaches to (decision-context-gate.sh
// _project_root() → proj-<slug> for cwd under claude-projects/neural-lace).
const ROOT_ID = 'proj-neural-lace';
const ROOT_TITLE = 'neural-lace';
const SOURCE = 'orchestrator-prime session (full fence context lives there)';

// The orchestrator-prime's current pending asks (2026-06-05). Slugs are the
// fence ids named in the spawn brief; text is an honest one-line summary, not
// a fabricated decision body. When orchestrator-prime emits the real fence,
// the gate's item-details-set (same item_id) enriches these in place.
const ASKS = [
  {
    id: 'DEC-2026-06-05-apply-m162',
    category: 'decision',
    title: 'Apply migration m162?',
    text: 'Decision pending: apply migration m162. Surfaced from orchestrator-prime; full options/tradeoffs in the orchestrator-prime thread.',
  },
  {
    id: 'R23-reframe',
    category: 'decision',
    title: 'R23 reframe',
    text: 'Decision pending: the R23 reframe. Surfaced from orchestrator-prime; full framing in the orchestrator-prime thread.',
  },
  {
    id: 'deploy-isolation-Q1',
    category: 'question',
    title: 'Deploy-isolation Q1',
    text: 'Question pending: deploy-isolation Q1. Surfaced from orchestrator-prime; full question context in the orchestrator-prime thread.',
  },
];

function categoryToType(cat) {
  if (cat === 'decision') return 'decision-raised';
  if (cat === 'question') return 'question-raised';
  if (cat === 'action_item_for_user' || cat === 'action') return 'action-added';
  throw new Error('unknown category: ' + cat);
}

function list() {
  const s = st.readState();
  const node = s.snapshot.nodes.find((n) => n.node_id === ROOT_ID);
  const items = (node && node.items) || [];
  process.stdout.write('Items on ' + ROOT_ID + ': ' + items.length + '\n');
  items.forEach((it) => {
    process.stdout.write('  - [' + it.kind + '] ' + (it.checked ? '✓' : '◐') + ' ' +
      it.item_id + ' — ' + String(it.text || '').slice(0, 70) + '\n');
  });
}

function emit() {
  // 1. Defensive root branch-opened (idempotent on event_id; facade dedupes
  //    if --on-session-start already seeded proj-neural-lace).
  st.appendEvent({
    event_id: 'spa-bo-' + ROOT_ID,
    type: 'branch-opened',
    node_id: ROOT_ID,
    parent_id: null,
    title: ROOT_TITLE,
    actor: 'dispatch',
  });

  let emitted = 0;
  for (const ask of ASKS) {
    const itemId = 'item-' + ask.id;
    const evType = categoryToType(ask.category);
    const kind = ask.category === 'decision' ? 'decision'
      : ask.category === 'question' ? 'question' : 'action';
    const details = {
      id: ask.id, title: ask.title, about: ask.text,
      _category: ask.category, surfaced_by: 'surface-pending-asks', source: SOURCE,
    };
    // Primary event (decision-raised / question-raised) — attaches the item.
    st.appendEvent({
      event_id: 'spa-pr-' + ask.id,
      type: evType,
      node_id: ROOT_ID,
      item_id: itemId,
      actor: 'dispatch',
      title: ask.title,
      text: ask.text,
      details,
    });
    // Sibling item-details-set carries the rich payload (matches the gate).
    st.appendEvent({
      event_id: 'spa-ids-' + ask.id,
      type: 'item-details-set',
      node_id: ROOT_ID,
      item_id: itemId,
      details,
    });
    emitted++;
    process.stdout.write('emitted [' + kind + '] ' + itemId + '\n');
  }
  process.stdout.write('Done. ' + emitted + ' ask(s) surfaced on ' + ROOT_ID + '.\n');
}

if (require.main === module) {
  if (process.argv.includes('--list')) { list(); }
  else { emit(); list(); }
}

module.exports = { ASKS, ROOT_ID, emit, list };
