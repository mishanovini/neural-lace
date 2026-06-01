'use strict';
/*
 * add-pending-items.js — append today's pending items (decisions, actions,
 * questions, backlog) to the Conv Tree state file.
 *
 * Schema mapping (state/schema.js):
 *   decision-raised : node_id + item_id + text   -> "Waiting on you" pane
 *   question-raised : node_id + item_id + text   -> "Waiting on you" pane
 *   action-added    : node_id + item_id + text   -> "Waiting on you" pane
 *   backlog-added   : item_id + tree_id + priority + text -> "Backlog" pane
 *
 * Anchor strategy:
 *   - Project-specific items attach to the matching proj-* node.
 *   - Cross-cutting / harness-wide items attach to today-20260520.
 *   - Harness gaps with no committed branch go to backlog (orphan), low pri.
 *
 * Idempotent: deterministic event_id + item_id from sha1(prefix|text|anchor).
 * Re-running emits the same ids; state library dedupes by event_id (§2).
 */
const path = require('path');
const crypto = require('crypto');

const STATE_LIB = path.resolve(__dirname, '..', 'state', 'state.js');
const SINK = process.argv.includes('--sink')
  ? process.argv[process.argv.indexOf('--sink') + 1]
  : path.resolve(__dirname, '..', 'state', 'tree-state.json');
const DRY_RUN = process.argv.includes('--dry-run');
const s = require(STATE_LIB);

function sha1(...parts) {
  return crypto.createHash('sha1').update(parts.join('|'), 'utf8').digest('hex');
}
function id(prefix, ...parts) { return prefix + '-' + sha1(...parts).slice(0, 24); }

// Existing tree nodes (from backfill — must match node_ids already in state).
const N_TODAY = 'today-20260520';
const N_FORESIGHT = 'proj-foresight';
const N_CORTEX = 'proj-cortex-one';
const N_CIRCUIT = 'proj-circuit';
const N_NEURAL = 'proj-neural-lace';

// ---- 9 decisions ----------------------------------------------------------
const DECISIONS = [
  [N_FORESIGHT, 'Foresight pipeline-override-remediation acceptance gate: (a) run runtime advocate → real PASS / (b) move Status to DEFERRED until Phase 1 / (c) accept per-session waiver friction'],
  [N_FORESIGHT, 'Foresight 74 unattributable RULE rows: accept as known-limitation OR flip categorizationSource to MANUAL'],
  [N_FORESIGHT, 'Foresight 2,783 false `never_matched` audit-panel: (A) one-time backfill of categorizingRuleId / (B) audit UI redesign with filters/grouping/virtualization / (C) increase grace period 7→60 days'],
  [N_CORTEX,    'Cortex One uncommitted WIP (3 files: .gitignore + 2 supabase ingest functions for calendar/gmail): yours and need committing OR stale and removable'],
  [N_NEURAL,    'accounts.config.json placeholder: fill now to unblock auto-account-switching OR live with manual gh auth switch'],
  [N_NEURAL,    'Three doctrine moves from harness analysis: pick which to draft — (a) rules/workstream-memory.md ecology rule / (b) heartbeats amendment to automation-modes.md / (c) pre-existing-oracle paragraph in planning.md'],
  [N_NEURAL,    'Cross-repo doctrine map: which downstream gets next propagation push — Circuit / Foresight / write bootstrap-downstream.sh first / both in parallel'],
  [N_NEURAL,    'FM-catalog adoption strategy: each downstream owns its own docs/failure-modes.md, OR downstream projects defer to NL\'s catalog'],
  [N_NEURAL,    'Propagation-mechanism formalization: manual per-project plan / bootstrap-downstream.sh script / per-element opt-in flags in NL doctrine docs'],
];

// ---- 6 action items -------------------------------------------------------
const ACTIONS = [
  [N_NEURAL,  'Paste other-machine hook settings: `cat ~/.claude/settings.json | jq \'.hooks.Stop, .hooks.SubagentStop, .hooks.Notification\'` from the desktop'],
  [N_TODAY,   'Identify prd-v1.1 (NL-FINDING-005 / HARNESS-GAP-36) ownership: which downstream project, did the 2026-05-17 spawned remediation session complete'],
  [N_TODAY,   'Set up ntfy.sh for phone notifications (the real fix for the Dispatch wake-up gap): install app, get private topic URL, share back'],
  [N_CIRCUIT, 'Provision prod test-org for Circuit launch readiness; run test:api / test:journey / test:e2e from other machine on current master'],
  [N_NEURAL,  'File Dispatch-architecture issue on anthropics/claude-code, adding voice to #40070'],
  [N_NEURAL,  'Run `bash ~/.claude/hooks/conversation-tree-emit.sh --self-test` to sanity-check the jq fix (should be 17/17)'],
];

// ---- 5 questions ----------------------------------------------------------
const QUESTIONS = [
  [N_TODAY,  'Which downstream matters most to harden first — Circuit (more mature, customer-facing) or Foresight (more under-adopted, structurally simpler)?'],
  [N_TODAY,  'Propagation philosophy: ship a bootstrap-downstream.sh, OR keep per-project opt-in (Decision 011 framing)?'],
  [N_NEURAL, 'Conv Tree framing: downstream project or harness-internal?'],
  [N_TODAY,  'FM-catalog convention (Decision 033) absence in Circuit/Foresight: intentional (waiting for pilot) or oversight?'],
  [N_TODAY,  'Husky delegate absence in both: deliberate (no lint-staged need) or never propagated?'],
];

// ---- 4 harness-gap backlog items (orphan, low priority) -------------------
const BACKLOG = [
  'The ~/claude-projects/ fallback path in conversation-tree-emit.sh (hardcoded, doesn\'t exist on this machine)',
  'No operator-facing breadcrumb for the empty Conv Tree on first install',
  'session-wrap.sh refresh line 259 only edits an existing SCRATCHPAD; silent no-op if missing → produces 1666666-min stale sentinel and Stop-hook loop',
  'Auto-detect dispatch-mode at SessionStart via CLAUDE_CODE_ENTRYPOINT=claude-desktop',
];

// ---- emit -----------------------------------------------------------------
const NOW = new Date().toISOString();
let emitted = 0, skipped = 0;

function emit(ev) {
  if (DRY_RUN) { console.log('[dry-run]', ev.type, ev.node_id || ev.tree_id, '-', (ev.text || '').slice(0, 70)); emitted++; return; }
  try { s.appendEvent(ev, { statePath: SINK }); emitted++; }
  catch (e) { skipped++; process.stderr.write('skip ' + ev.type + ': ' + (e && e.message || e) + '\n'); }
}

function emitItem(eventType, anchorNode, text, prefix) {
  const itemId = id('it-' + prefix, anchorNode, text);
  emit({
    event_id: id('cte-' + prefix, anchorNode, itemId),
    type: eventType,
    node_id: anchorNode,
    item_id: itemId,
    text: text,
    actor: 'dispatch',
    ts: NOW,
  });
}

console.log('[items] sink:', SINK);
console.log('[items] dry-run:', DRY_RUN);
console.log('---');

for (const [anchor, text] of DECISIONS) emitItem('decision-raised', anchor, text, 'd');
for (const [anchor, text] of ACTIONS)   emitItem('action-added',    anchor, text, 'a');
for (const [anchor, text] of QUESTIONS) emitItem('question-raised', anchor, text, 'q');

for (const text of BACKLOG) {
  const itemId = id('it-bl', text);
  emit({
    event_id: id('cte-bl', itemId),
    type: 'backlog-added',
    item_id: itemId,
    tree_id: 'global',
    priority: 'low',
    text: text,
    actor: 'dispatch',
    ts: NOW,
  });
}

console.log('---');
console.log('[items] emitted:', emitted, 'skipped:', skipped);
console.log('[items] breakdown: 9 decisions + 6 actions + 5 questions + 4 backlog = 24 items');
