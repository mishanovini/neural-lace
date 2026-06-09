'use strict';
/* backfill-phasec-background.js — Phase C (2026-06-09) one-shot backfill.
 *
 * THE PROBLEM (Misha, 2026-06-09): the canonical Workstreams state file has
 * ~39 OPEN items with `details: NULL` — the GUI renders them with the "No
 * detailed instructions recorded" fallback (the "INCOMPLETE METADATA" he saw).
 * For an operator who "completely forgot what we're doing," a bare item text
 * with no Background is useless.
 *
 * This script enumerates every OPEN item with NULL details and emits ONE
 * additive `item-details-set` event per item through the SOLE-NORMATIVE state.js
 * facade (never a raw JSON write). The `details` payload is assembled via the
 * shared assembleItemDetails() so it carries the SAME self-contained shape the
 * turn-emit + fence paths now produce: a Background memory-trigger paragraph +
 * the actionable field + _category.
 *
 * HONESTY CONTRACT (vaporware-prevention + the existing backfill-details.js
 * precedent): Background is grounded ONLY in what is verifiably present in the
 * state file — the owning node's TITLE (the workstream context) + the item's
 * own TEXT (the ask). It does NOT fabricate options / pros-cons /
 * recommendations from absent external docs. Where the item text itself names
 * a docs/* path, that path is surfaced as a `links` entry so the operator can
 * open the source.
 *
 * GARBAGE GUARD: items whose owning node is a `turn-*` noise node, or whose
 * text is a fragment (leading escape/punct/short), are SKIPPED — they are the
 * historical garbage the every-turn-emit rewrite now prevents; backfilling a
 * fragment with a Background does not make it a real item. They are listed in
 * the report so the operator can prune them.
 *
 * Usage:
 *   node state/backfill-phasec-background.js            # dry-run (default)
 *   node state/backfill-phasec-background.js --apply    # emit item-details-set
 *   node state/backfill-phasec-background.js --apply --state <path>
 *   node state/backfill-phasec-background.js --self-test
 *
 * Idempotent: the event_id is deterministic per (item_id) and the facade
 * dedupes on event_id; re-running --apply is a no-op. Last-writer-wins means a
 * later richer details (a fence emit) overrides this baseline.
 */
const path = require('path');
const state = require('./state.js');
const schema = require('./decision-context-schema.js');

// Map an item kind (decision/question/action) to the details _category.
function kindToCategory(kind) {
  if (kind === 'decision') return 'decision';
  if (kind === 'question') return 'question';
  return 'action_item_for_user'; // action
}

// Fragment / garbage guard — mirrors the turn-emit hook's isCleanItem leading
// rule (escaping-agnostic). A fragment cannot be made self-contained by adding
// a Background, so we skip it.
const FRAGMENT_LEADER_CODES = [
  92, 34, 39, 96, 41, 93, 125, 44, 59, 58, 46, 45, 124, 62, 42, 95, 126, 40,
  8220, 8221, 8216, 8217,
];
function isFragment(text) {
  const s = String(text == null ? '' : text).replace(/\s+/g, ' ').trim();
  if (s.length < 12) return true;
  if (FRAGMENT_LEADER_CODES.indexOf(s.charCodeAt(0)) !== -1) return true;
  if (/^[A-Za-z0-9._\/-]+$/.test(s)) return true; // bare path/identifier
  if (!/\s/.test(s)) return true;                  // single token
  return false;
}

// Assemble a self-contained Background from the node title + item text. Honest:
// grounded only in state-file content; never fabricated.
function buildBackground(nodeTitle, itemText, kind) {
  const title = String(nodeTitle || '').replace(/\s+/g, ' ').trim();
  const text = String(itemText || '').replace(/\s+/g, ' ').trim();
  const kindWord = kind === 'decision' ? 'A decision is awaiting you'
    : kind === 'question' ? 'A question is awaiting your answer'
    : 'An action is assigned to you';
  const parts = [];
  if (title) parts.push('Part of the workstream: "' + title + '".');
  parts.push(kindWord + '.');
  // The "why it matters" is the item text itself — the only verifiable signal.
  if (text) parts.push('The item: ' + text);
  let bg = parts.join(' ').replace(/\s+/g, ' ').trim();
  if (bg.length > 700) bg = bg.slice(0, 697) + '...';
  return bg;
}

// Extract docs/* links from the item text (honest cross-link, no fabrication).
function extractLinks(itemText, nodeTitle) {
  const links = [];
  const re = /docs\/[A-Za-z0-9._\/-]+/g;
  let m;
  const t = String(itemText || '');
  while ((m = re.exec(t)) !== null) links.push(m[0]);
  // Always include a pointer back to the owning branch for orientation.
  if (nodeTitle) links.push('(see branch: ' + String(nodeTitle).replace(/\s+/g, ' ').trim() + ')');
  return links.length ? links : undefined;
}

function deterministicEventId(itemId) {
  const crypto = require('crypto');
  return 'pcbg-' + crypto.createHash('sha1').update(String(itemId)).digest('hex').slice(0, 24);
}

// Core: enumerate, classify, (optionally) emit.
function run(opts) {
  opts = opts || {};
  const apply = !!opts.apply;
  const statePath = opts.statePath;
  const readOpts = statePath ? { statePath: statePath } : undefined;
  const st = state.readState(readOpts);

  const result = { scanned: 0, backfilled: 0, skippedFragment: 0, skippedHasDetails: 0, skippedChecked: 0, emitted: [], skipped: [] };

  st.snapshot.nodes.forEach(function (n) {
    const isTurnNode = /^turn-/.test(n.node_id);
    (n.items || []).forEach(function (it) {
      result.scanned++;
      if (it.checked) { result.skippedChecked++; return; }
      if (it.details) { result.skippedHasDetails++; return; }
      if (isTurnNode || isFragment(it.text)) {
        result.skippedFragment++;
        result.skipped.push({ node: n.node_id, item: it.item_id, text: String(it.text || '').slice(0, 60), reason: isTurnNode ? 'turn-node' : 'fragment' });
        return;
      }
      const cat = kindToCategory(it.kind);
      const fields = {
        background: buildBackground(n.title, it.text, it.kind),
        surfaced_by: 'backfill-phasec-background',
        source: 'backfill-phasec-background',
        links: extractLinks(it.text, n.title),
      };
      // actionable field per category — the item text IS the ask/question.
      if (cat === 'decision' || cat === 'question') fields.question = String(it.text || '').trim();
      else fields.the_ask = String(it.text || '').trim();

      const details = schema.assembleItemDetails(cat, fields);
      if (!details) {
        // Shouldn't happen (we just supplied background + an actionable field),
        // but honor the contract: if not self-contained, do not emit garbage.
        result.skippedFragment++;
        result.skipped.push({ node: n.node_id, item: it.item_id, text: String(it.text || '').slice(0, 60), reason: 'not-self-contained' });
        return;
      }

      const ev = {
        event_id: deterministicEventId(it.item_id),
        type: 'item-details-set',
        node_id: n.node_id,
        item_id: it.item_id,
        details: details,
        actor: 'dispatch',
      };
      if (apply) {
        state.appendEvent(ev, readOpts);
      }
      result.backfilled++;
      result.emitted.push({ node: n.node_id, item: it.item_id, kind: it.kind, bgLen: details.background.length });
    });
  });

  return result;
}

// ---- self-test --------------------------------------------------------------
function selfTest() {
  const fs = require('fs');
  const os = require('os');
  let pass = 0, fail = 0;
  function ck(name, cond) { if (cond) { console.log('PASS: ' + name); pass++; } else { console.log('FAIL: ' + name); fail++; } }

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pcbg-st-'));
  const sp = path.join(dir, 'tree-state.json');

  // Seed: a real branch + a genuine open decision (NULL details) + a fragment
  // item on a turn-node + an already-detailed item.
  state.appendBranchOpened({ id: 'r1', parentId: null, title: 'R23 launch prep' }, { statePath: sp });
  state.appendEvent({ type: 'decision-raised', node_id: 'r1', item_id: 'gi1', text: 'Apply migration m162 to production now or wait for backup?', actor: 'dispatch' }, { statePath: sp });
  state.appendBranchOpened({ id: 'turn-x-1', parentId: 'r1', title: 'Turn 99' }, { statePath: sp });
  state.appendEvent({ type: 'action-added', node_id: 'turn-x-1', item_id: 'frag1', text: '\\" decisions (the class it missed)', actor: 'dispatch' }, { statePath: sp });

  const dry = run({ statePath: sp, apply: false });
  ck('ST1 dry-run scans items', dry.scanned >= 2);
  ck('ST1 dry-run backfills the genuine decision', dry.backfilled === 1);
  ck('ST1 dry-run skips the turn-node fragment', dry.skippedFragment === 1);
  // dry-run did NOT write
  let st1 = state.readState({ statePath: sp });
  let gi1 = null; st1.snapshot.nodes.forEach(function (n) { (n.items || []).forEach(function (it) { if (it.item_id === 'gi1') gi1 = it; }); });
  ck('ST1 dry-run did NOT write details', gi1 && !gi1.details);

  const ap = run({ statePath: sp, apply: true });
  ck('ST2 apply backfills 1', ap.backfilled === 1);
  let st2 = state.readState({ statePath: sp });
  let gi2 = null; st2.snapshot.nodes.forEach(function (n) { (n.items || []).forEach(function (it) { if (it.item_id === 'gi1') gi2 = it; }); });
  ck('ST2 genuine item now has details', gi2 && !!gi2.details);
  ck('ST2 details carry _category', gi2 && gi2.details._category === 'decision');
  ck('ST2 details carry background', gi2 && /R23 launch prep/.test(gi2.details.background));
  ck('ST2 details carry the question', gi2 && /m162/.test(gi2.details.question || ''));
  // fragment item still NULL
  let fr = null; st2.snapshot.nodes.forEach(function (n) { (n.items || []).forEach(function (it) { if (it.item_id === 'frag1') fr = it; }); });
  ck('ST2 fragment item still has NO details (skipped)', fr && !fr.details);

  // idempotent
  const ap2 = run({ statePath: sp, apply: true });
  let st3 = state.readState({ statePath: sp });
  const idsEvents = st3.events.filter(function (e) { return e.type === 'item-details-set' && e.item_id === 'gi1'; });
  ck('ST3 re-apply is idempotent (one details event)', idsEvents.length === 1);

  fs.rmSync(dir, { recursive: true, force: true });
  console.log('\nself-test: ' + pass + ' pass, ' + fail + ' fail');
  if (fail === 0) { console.log('self-test: OK ' + pass + '/' + (pass + fail)); process.exit(0); }
  console.log('self-test: FAIL'); process.exit(1);
}

// ---- CLI --------------------------------------------------------------------
if (require.main === module) {
  const argv = process.argv.slice(2);
  if (argv.indexOf('--self-test') !== -1) { selfTest(); }
  const apply = argv.indexOf('--apply') !== -1;
  let statePath;
  const si = argv.indexOf('--state');
  if (si !== -1 && argv[si + 1]) statePath = argv[si + 1];

  const res = run({ apply: apply, statePath: statePath });
  console.log((apply ? 'APPLIED' : 'DRY-RUN') + ' — Phase C Background backfill');
  console.log('  scanned: ' + res.scanned
    + ' | backfilled: ' + res.backfilled
    + ' | skipped (fragment/turn-node): ' + res.skippedFragment
    + ' | skipped (already had details): ' + res.skippedHasDetails
    + ' | skipped (checked): ' + res.skippedChecked);
  if (res.emitted.length) {
    console.log('\n  Backfilled items:');
    res.emitted.forEach(function (e) { console.log('    [' + e.kind + '] ' + e.node + ' :: ' + e.item + ' (bg ' + e.bgLen + ' chars)'); });
  }
  if (res.skipped.length) {
    console.log('\n  Skipped (NOT self-containable — historical garbage; prune manually):');
    res.skipped.forEach(function (sk) { console.log('    ' + sk.reason + ' — ' + sk.node + ' :: ' + JSON.stringify(sk.text)); });
  }
  if (!apply) console.log('\n  (dry-run — re-run with --apply to emit item-details-set events)');
}

module.exports = { run: run, isFragment: isFragment, buildBackground: buildBackground, kindToCategory: kindToCategory };
