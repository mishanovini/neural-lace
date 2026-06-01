'use strict';
/* conv-tree-ui v1.1 item 9 — rich-details backfill.
 *
 * Enumerates every OPEN action/decision/question item in the state file and
 * emits one additive `item-details-set` event per item so the GUI's
 * rich-details disclosure has content.
 *
 * HONESTY CONTRACT (vaporware-prevention + friction-reflexion):
 * The deep per-item enrichment item 9 describes (TCPA 8 decision cards with
 * pros/cons, Phase 6 ratification specifics, etc.) is sourced from external
 * Dispatch docs (`docs/reviews/tcpa-decision-options-2026-05-17`,
 * `docs/plans/phase-6-preventive-controls.md`, the Phase 7 audit docs).
 * Those docs are NOT present in any repo under ~/claude-projects on this
 * machine (verified). This script therefore does NOT fabricate sourced
 * options/pros-cons/recommendations — that would be placeholder content
 * dressed as sourced. It grounds each payload ONLY in what is verifiably
 * available in the state file itself:
 *   description      = the item text (verbatim)
 *   context          = the owning branch (node title + state)
 *   links            = any docs/* path the item text itself references,
 *                       else a pointer to the owning branch
 *   blocking_input   = derived ONLY when the item text unambiguously says so
 *   instructions/options/recommendation = LEFT NULL (require the absent docs)
 *
 * `--enrich <file.json>` is the documented path to layer in the real
 * doc-sourced payloads when the source docs are available (a map of
 * item_id -> partial details, deep-merged; `item-details-set` is
 * last-writer-wins so re-running with --enrich is safe + idempotent).
 *
 * Usage:
 *   node state/backfill-details.js                 # dry-run (default; no writes)
 *   node state/backfill-details.js --apply         # emit item-details-set events
 *   node state/backfill-details.js --apply --state <path>   # target a state file
 *   node state/backfill-details.js --apply --enrich enrich.json
 *   node state/backfill-details.js --self-test
 */
const fs = require('fs');
const path = require('path');
const state = require('./state.js');
const projects = require('../config/projects.js'); // item 19/23 cross-repo map

// ---- v1.1.1 item 23: cross-repo doc-sourced extraction ---------------------
// The v1.1 honesty contract deferred deep enrichment because the source docs
// were not on the machine. They ARE now (in the mapped external repos), so the
// honest move is to READ them and extract real content — never fabricate.
//
// resolveDocPath: given a node's project tag + a docs/… path, find the doc in
// ANY mapped project (try the node's own tag first, then every other root).
function resolveDocPath(projectTag, docRel) {
  var tries = [];
  if (projectTag) tries.push(projectTag);
  var map = projects.loadProjects();
  Object.keys(map).forEach(function (k) { if (tries.indexOf(k) === -1) tries.push(k); });
  for (var i = 0; i < tries.length; i++) {
    var r = projects.resolveDoc(tries[i], docRel);
    if (r.ok) return r.abs;
  }
  return null;
}
// extractFromDoc: pull real description/options/recommendation/blocking_input
// out of a markdown doc. Section-aware: if a `## ` heading shares tokens with
// the item text, that section is the source; else the whole doc. Anything not
// present in the doc stays NULL (no fabrication — honesty contract preserved).
function extractFromDoc(abs, itemText) {
  var raw;
  try { raw = fs.readFileSync(abs, 'utf8'); } catch (_) { return null; }
  var lines = raw.split(/\r?\n/);
  // index ## / ### sections
  var secs = [], cur = null;
  lines.forEach(function (ln) {
    var h = ln.match(/^(#{2,3})\s+(.*)$/);
    if (h) { if (cur) secs.push(cur); cur = { title: h[2].trim(), body: [] }; }
    else if (cur) cur.body.push(ln);
    else { /* preamble */ }
  });
  if (cur) secs.push(cur);
  function toks(s) { return String(s).toLowerCase().match(/[a-z0-9]{3,}/g) || []; }
  var itTok = toks(itemText), best = null, bestScore = 0;
  secs.forEach(function (s) {
    var st = toks(s.title), hit = 0;
    st.forEach(function (t) { if (itTok.indexOf(t) !== -1) hit++; });
    if (hit > bestScore) { bestScore = hit; best = s; }
  });
  var scopeLines = best ? best.body : lines;
  var scopeText = scopeLines.join('\n').trim();
  if (best && bestScore === 0) { best = null; }
  // description = the matched section's first real content. Prefer a plain
  // paragraph; fall back to the first bullet (many sections are bullet-only);
  // final fallback = the section body, joined + capped (still real doc text,
  // never fabricated).
  var desc = null;
  for (var i = 0; i < scopeLines.length; i++) {
    var t = scopeLines[i].trim();
    if (t && !/^#{1,6}\s/.test(t) && !/^[-*]\s/.test(t)) { desc = t.replace(/\*\*/g, ''); break; }
  }
  if (!desc) {
    for (var j = 0; j < scopeLines.length; j++) {
      var b = scopeLines[j].trim();
      if (/^[-*]\s+/.test(b)) { desc = b.replace(/^[-*]\s+/, '').replace(/\*\*/g, ''); break; }
    }
  }
  if (!desc) {
    var joined = scopeLines.join(' ').replace(/\s+/g, ' ').trim();
    if (joined) desc = joined.slice(0, 400);
  }
  // options: `Option A`, `**Option A**`, `### Option`, or `pick A / B / C`
  var options = [];
  scopeLines.forEach(function (ln) {
    var mo = ln.match(/^[-*\s>]*(?:\*\*|###\s*)?Option\s+([A-Z0-9][\w-]*)\s*[:.\-—)]*\s*(.*)$/i);
    if (mo) options.push({ label: ('Option ' + mo[1] + (mo[2] ? ' — ' + mo[2].replace(/\*\*/g, '').trim() : '')).trim() });
  });
  if (options.length === 0) {
    var pk = scopeText.match(/pick\s+([A-Z](?:\s*\/\s*[A-Z])+)/i);
    if (pk) options = pk[1].split('/').map(function (x) { return { label: 'Option ' + x.trim() }; });
  }
  // recommendation: a "## Recommendation" section, or a line with "recommend"
  var rec = null;
  for (var r = 0; r < secs.length; r++) {
    if (/^recommend/i.test(secs[r].title)) { rec = secs[r].body.join(' ').replace(/\s+/g, ' ').trim(); break; }
  }
  if (!rec) {
    var rl = scopeText.split(/\n/).find(function (x) { return /recommend(ed|ation)?:/i.test(x); });
    if (rl) rec = rl.replace(/\*\*/g, '').trim();
  }
  // blocking_input: "What you need from <person>", "you need from", "need to ship"
  var bi = null;
  var bl = scopeText.split(/\n/).find(function (x) {
    return /\*\*what you need from|you need from|need(s|ed)? (you|the operator|to ship)/i.test(x);
  });
  if (bl) bi = bl.replace(/\*\*/g, '').trim();
  return {
    description: desc,
    section: best ? best.title : null,
    options: options.length ? options : null,
    recommendation: rec || null,
    blocking_input: bi || null,
  };
}

function extractDocLinks(text) {
  // grab docs/...md, docs/reviews/..., docs/plans/... tokens embedded in the
  // item text (several live items name their source doc inline).
  var out = [];
  var re = /docs\/[A-Za-z0-9._\/-]+/g, m;
  while ((m = re.exec(String(text))) !== null) out.push(m[0]);
  return out;
}
function deriveBlockingInput(text) {
  var t = String(text).toLowerCase();
  if (/launch-?blocker/.test(t)) return 'Launch-blocker — needs Misha to action/confirm before launch.';
  if (/needs?-?(misha|decision|input)|waiting on misha|paste-ready/.test(t)) return 'Needs Misha: action/decision required to proceed.';
  return null;
}
// Build the honest, state-grounded payload for one item on one node.
function payloadFor(node, it, enrichMap) {
  var links = extractDocLinks(it.text);
  var base = {
    description: String(it.text),
    context: 'Branch: "' + (node.title || node.node_id) + '" (' + node.state + ') — a tracked Dispatch conversation. '
      + 'Full source detail lives in the linked Dispatch doc (not in the tracker state).',
    instructions: null,
    options: null,
    recommendation: null,
    blocking_input: deriveBlockingInput(it.text),
    links: links.length ? links : ['(see branch: ' + (node.title || node.node_id) + ')'],
  };
  // item 23: cross-repo doc-sourced enrichment. If the item names a docs/…
  // path resolvable in any mapped project, READ it and fill the rich fields
  // from the actual doc (no fabrication — anything absent stays as-is/null).
  var docRel = links.find(function (l) { return /^docs\//.test(l); });
  if (docRel) {
    var abs = resolveDocPath(node.tree_id || node.project || null, docRel);
    if (abs) {
      var ex2 = extractFromDoc(abs, it.text);
      if (ex2) {
        // description stays the verbatim item text (honesty + back-compat);
        // the doc's content enriches context/instructions/options/rec/blocking.
        base.context = 'Branch: "' + (node.title || node.node_id) + '" (' + node.state + '). '
          + 'Sourced from ' + docRel + (ex2.section ? ' § "' + ex2.section + '"' : '') + '.';
        if (ex2.description) base.instructions = ex2.description;
        if (ex2.options) base.options = ex2.options;
        if (ex2.recommendation) base.recommendation = ex2.recommendation;
        if (ex2.blocking_input) base.blocking_input = ex2.blocking_input;
      }
    }
  }
  // optional explicit enrichment override (deep-merge LAST — highest priority)
  var ex = enrichMap && (enrichMap[it.item_id] || enrichMap[node.node_id + ':' + it.item_id]);
  if (ex && typeof ex === 'object') {
    Object.keys(ex).forEach(function (k) { if (ex[k] != null) base[k] = ex[k]; });
  }
  return base;
}
function sameDetails(a, b) {
  try { return JSON.stringify(a) === JSON.stringify(b); } catch (_) { return false; }
}

function plan(opts) {
  opts = opts || {};
  var readOpts = opts.statePath ? { statePath: opts.statePath } : undefined;
  var snap = state.readState(readOpts).snapshot;
  var enrichMap = null;
  if (opts.enrichPath) enrichMap = JSON.parse(fs.readFileSync(opts.enrichPath, 'utf8'));
  var jobs = [];
  (snap.nodes || []).forEach(function (n) {
    (n.items || []).forEach(function (it) {
      if (it.checked || it.deferred) return;            // only OPEN, waiting items
      var pl = payloadFor(n, it, enrichMap);
      if (sameDetails(pl, it.details)) return;          // idempotent — skip no-op
      jobs.push({ node_id: n.node_id, item_id: it.item_id, text: it.text, details: pl });
    });
  });
  return { jobs: jobs, total: jobs.length, snap: snap };
}

function apply(opts) {
  var p = plan(opts);
  var emitOpts = opts.statePath ? { statePath: opts.statePath } : undefined;
  var emitted = 0;
  p.jobs.forEach(function (j) {
    state.appendEvent({ type: 'item-details-set', node_id: j.node_id, item_id: j.item_id, details: j.details }, emitOpts);
    emitted++;
  });
  return { emitted: emitted, planned: p.total };
}

// ---- self-test (dependency-free; temp state file) -------------------------
function selfTest() {
  var os = require('os');
  var tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bf-'));
  var sp = path.join(tmp, 'tree-state.json');
  var o = { statePath: sp };
  var pass = 0, fail = 0;
  function ok(name, c) { if (c) { pass++; console.log('  PASS  ' + name); } else { fail++; console.log('  FAIL  ' + name); } }
  try {
    state.appendEvent({ type: 'branch-opened', node_id: 'n1', parent_id: null, title: 'TCPA work' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a1', text: 'TCPA: see docs/reviews/tcpa-decision-options-2026-05-17' }, o);
    state.appendEvent({ type: 'decision-raised', node_id: 'n1', item_id: 'd1', text: 'launch-blocker — wire twilio_config' }, o);
    state.appendEvent({ type: 'action-added', node_id: 'n1', item_id: 'a2', text: 'already done thing' }, o);
    state.appendEvent({ type: 'action-done', node_id: 'n1', item_id: 'a2' }, o);

    var pl = plan(o);
    ok('B1 plans only open items (2 of 3; checked one excluded)', pl.total === 2);
    var a1 = pl.jobs.find(function (j) { return j.item_id === 'a1'; });
    ok('B2 description = item text verbatim', a1.details.description.indexOf('TCPA:') === 0);
    ok('B3 doc link extracted from item text', a1.details.links.indexOf('docs/reviews/tcpa-decision-options-2026-05-17') !== -1);
    ok('B4 context names the owning branch', /TCPA work/.test(a1.details.context));
    ok('B5 NOT fabricated: options/recommendation null', a1.details.options === null && a1.details.recommendation === null);
    var d1 = pl.jobs.find(function (j) { return j.item_id === 'd1'; });
    ok('B6 blocking_input derived from "launch-blocker"', /Launch-blocker/.test(d1.details.blocking_input));

    var ap = apply(o);
    ok('B7 apply emits one item-details-set per planned job', ap.emitted === 2);
    var afterSnap = state.readState(o).snapshot;
    var it = afterSnap.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    ok('B8 details landed on the item via the reducer', it.details && it.details.description.indexOf('TCPA:') === 0);

    var ap2 = apply(o);
    ok('B9 idempotent: re-run emits 0 (no-op skip)', ap2.emitted === 0);

    // enrich override deep-merges and supersedes (last-writer-wins)
    var ep = path.join(tmp, 'enrich.json');
    fs.writeFileSync(ep, JSON.stringify({ a1: { recommendation: 'Adopt option A', options: [{ label: 'A', pros: 'fast', cons: 'risk' }] } }));
    var ap3 = apply({ statePath: sp, enrichPath: ep });
    var it2 = state.readState(o).snapshot.nodes[0].items.find(function (x) { return x.item_id === 'a1'; });
    ok('B10 --enrich supersedes (recommendation+options now set; desc preserved)',
      ap3.emitted >= 1 && it2.details.recommendation === 'Adopt option A'
      && Array.isArray(it2.details.options) && it2.details.description.indexOf('TCPA:') === 0);

    // ---- item 23: cross-repo doc-sourced extraction ----------------------
    var fxDir = path.join(tmp, 'fx');
    fs.mkdirSync(fxDir, { recursive: true });
    var fxDoc = path.join(fxDir, 'rich.md');
    fs.writeFileSync(fxDoc,
      '# Doc Title\n\n' +
      '## QUIET-HOURS — wrong timezone on every send\n\n' +
      'Quiet-hours are computed against the org timezone, not the recipient.\n\n' +
      '- Option A: use the recipient-resolved timezone\n' +
      '- Option B: fail closed and block marketing on unknown TZ\n\n' +
      '**What you need from the operator to ship:** pick A or B and confirm fail-closed.\n\n' +
      '## Recommendation\n\nBlock marketing on unknown TZ; transactional still sends.\n\n' +
      '## UNRELATED — nothing matches here\n\nFiller.\n');
    var ex23 = extractFromDoc(fxDoc, 'quiet-hours wrong timezone on send');
    ok('B12 extractFromDoc matched the right section',
      ex23 && /QUIET-HOURS/.test(ex23.section));
    ok('B13 options + recommendation + blocking_input doc-sourced (not null)',
      ex23 && Array.isArray(ex23.options) && ex23.options.length === 2
      && /recipient-resolved/.test(ex23.options[0].label)
      && /Block marketing/.test(ex23.recommendation || '')
      && /pick A or B/.test(ex23.blocking_input || '')
      && ex23.description && /Quiet-hours/.test(ex23.description));
    var fxBare = path.join(fxDir, 'bare.md');
    fs.writeFileSync(fxBare, '# Plain\n\nJust prose, no options, no recommendation section.\n');
    var ex23b = extractFromDoc(fxBare, 'plain prose');
    ok('B14 NOT fabricated: no options/recommendation in a bare doc -> null',
      ex23b && ex23b.options === null && ex23b.recommendation === null);
    // payloadFor integration: a same-repo doc resolvable via projects.js gets
    // doc-sourced instructions/context (no external project needed).
    // Use a PERMANENT same-repo docs/ file (the decisions index is never
    // archived/renamed — unlike plan files, which move on closure; that
    // fragility caused a v1.1.2 B15 regression and is now designed out).
    var selfDocRel = 'docs/DECISIONS.md';
    var pf = payloadFor({ node_id: 'nz', title: 'plan work', state: 'open', tree_id: 'neural-lace' },
      { item_id: 'iz', text: 'see ' + selfDocRel + ' for the decisions index' }, null);
    ok('B15 payloadFor enriches from a resolvable same-repo doc',
      pf.instructions != null && /DECISIONS\.md/.test(pf.context)
      && pf.description === 'see ' + selfDocRel + ' for the decisions index');

    // tree integrity: node count unchanged by the backfill (append-only)
    ok('B11 append-only: node count unchanged (1)', afterSnap.nodes.length === 1
      && state.readState(o).snapshot.nodes.length === 1);
  } catch (e) { fail++; console.log('  FAIL  self-test threw: ' + e.message); }
  finally { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {} }
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

// ---- CLI ------------------------------------------------------------------
if (require.main === module) {
  var args = process.argv.slice(2);
  if (args.indexOf('--self-test') !== -1) return selfTest();
  var opts = {};
  var si = args.indexOf('--state'); if (si !== -1) opts.statePath = args[si + 1];
  var ei = args.indexOf('--enrich'); if (ei !== -1) opts.enrichPath = args[ei + 1];
  if (args.indexOf('--apply') !== -1) {
    var r = apply(opts);
    console.log('[backfill] emitted ' + r.emitted + ' item-details-set event(s) (planned ' + r.planned + ')');
  } else {
    var p = plan(opts);
    console.log('[backfill] DRY-RUN — would emit ' + p.total + ' item-details-set event(s):');
    p.jobs.forEach(function (j) { console.log('  - ' + j.item_id + '  «' + String(j.text).slice(0, 56) + '»  links=' + JSON.stringify(j.details.links)); });
    console.log('  (re-run with --apply to write; --enrich <json> to layer doc-sourced payloads)');
  }
}

module.exports = { plan: plan, apply: apply, payloadFor: payloadFor, extractDocLinks: extractDocLinks };
