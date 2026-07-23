'use strict';
/* Workstreams cockpit — DOM-free structural self-test (NL Observability
 * Program Wave O, task O.4, specs-o §O.4). Same technique as the retired
 * responsive.selftest.js it supersedes (see attic/README.md): reads the
 * three web/ source files as text and asserts the load-bearing structural
 * invariants of the six-question cockpit rebuild. No build step, no
 * headless-browser dependency. Behavioral rendering against live data is
 * covered by server/server.selftest.js (wiring) and the end-user-advocate's
 * runtime acceptance run (the ten scenarios in
 * docs/reviews/2026-07-06-o4-acceptance-scenarios.md).
 *
 * Run: `node web/cockpit.selftest.js`. Exit 0 PASS / 1 FAIL.
 */
const fs = require('fs');
const path = require('path');
const D = __dirname;
const css = fs.readFileSync(path.join(D, 'app.css'), 'utf8');
const html = fs.readFileSync(path.join(D, 'index.html'), 'utf8');
const js = fs.readFileSync(path.join(D, 'app.js'), 'utf8');
const asksJs = fs.readFileSync(path.join(D, 'asks.js'), 'utf8');
// todo.js was RETIRED (cockpit-roadmap-redesign Task 8 item 5 / A10) and
// salvaged to attic/todo.js — no longer served, no longer read here. Its
// hygiene assertions (formerly T16-11/T16-13 below) were repointed to
// inbox.js's "My items" section, the functional replacement — read here
// (not down near the rest of the T4 block) so the T16 section (which runs
// much earlier in this file) can reference it too.
let inboxJs = '';
try { inboxJs = fs.readFileSync(path.join(D, 'inbox.js'), 'utf8'); } catch (_) { /* T16/T3-3/T4 checks fail honestly below */ }
const backlogJs = fs.readFileSync(path.join(D, 'backlog.js'), 'utf8');

let pass = 0, fail = 0;
function ok(name, cond) {
  if (cond) { pass++; console.log('  PASS  ' + name); }
  else { fail++; console.log('  FAIL  ' + name); }
}
const C = css.replace(/\s+/g, ' ');

// --- six-question surfaces present -----------------------------------------
ok('R1 all six panes present (needsMe/status/health/costs/shipped/backlog)',
  /id="paneNeedsMe"/.test(html) && /id="paneStatus"/.test(html) && /id="paneHealth"/.test(html) &&
  /id="paneCosts"/.test(html) && /id="paneShipped"/.test(html) && /id="paneBacklog"/.test(html));

// --- attention-semantics: Q2 (needs-me) appears BEFORE Q1 (status) in
// SOURCE ORDER (ux-review amendment 9: "Q2 on top") ------------------------
ok('R2 Q2 (needs-me) precedes Q1 (status) in document source order',
  html.indexOf('id="paneNeedsMe"') < html.indexOf('id="paneStatus"'));

// --- interrupt-priority strip present, ahead of the six panes --------------
ok('R3 interrupt-priority strip present and precedes the six-pane grid',
  html.indexOf('id="interruptStrip"') !== -1 && html.indexOf('id="interruptStrip"') < html.indexOf('id="cockpit"'));

// --- reconciler badge present ------------------------------------------------
ok('R4 reconciler badge present in the header', /id="reconcilerBadge"/.test(html));

// --- Q3 last-look + explicit Mark-seen control (ux-review amendment 3) -----
ok('R5 Q3 has a visible last-look anchor + explicit Mark-seen button',
  /id="lastLookAnchor"/.test(html) && /id="markSeenBtn"/.test(html));

// --- visible Refresh control (ux-review amendment 4) -----------------------
ok('R6 visible Refresh control with feedback element', /id="refreshBtn"/.test(html) && /id="refreshFeedback"/.test(html));

// --- Q6 why-drawer: role=dialog, Esc-closeable, focus-managed --------------
ok('R7 why-drawer is role=dialog with a close control', /id="whyDrawer"[^>]*role="dialog"/.test(html) && /id="whyClose"/.test(html));
ok('R8 why-drawer Esc-close wired in app.js', /Escape/.test(js) && /closeWhyDrawer/.test(js));
ok('R9 why-drawer focus-return on close (whyLastFocused)', /whyLastFocused/.test(js));

// --- NO legacy write affordances survive (trust-path retirement) -----------
const RETIRED_IDS = ['addBacklogBtn', 'backlogCapture', 'detailModal', 'showCompleted', 'showArchived', 'treePane', 'filterBar'];
ok('R10 no legacy write-affordance / tree-pane ids survive in the new index.html',
  RETIRED_IDS.every((id) => html.indexOf('id="' + id + '"') === -1));
ok('R11 app.js contains NO POST to /api/event (the retired legacy write sink)',
  !/\/api\/event['"]/.test(js.replace(/\/api\/events/g, ''))); // /api/events (SSE, kept) must not false-positive

// --- docs browser KEPT (link-resolver backend, ux-review amendment 6) -----
ok('R12 docs browser markup present (kept as the link-resolver backend)',
  /id="docsPanel"/.test(html) && /id="docModal"/.test(html));
ok('R13 app.js has exactly ONE link-resolving function used by every pane (resolveLink)',
  (js.match(/function resolveLink/g) || []).length === 1 && /resolveLink\(/.test(js));

// --- error state renderer exists and is generic (ux-review amendment 1) ---
ok('R14 a single renderError() function backs every pane\'s error state',
  (js.match(/function renderError/g) || []).length === 1);
ok('R15 renderError renders the failing command line + stderr tail + a Retry control',
  /pane-error-cmd/.test(js) && /stderr_tail/.test(js) && /Retry/.test(js));

// --- chip a11y: state chips carry text content, not just a color class ----
ok('R16 state chips render textContent = state name (text + color, never color-only)',
  /chip\.textContent = s\.state/.test(js));

// --- ONE accent color reserved for interrupt-worthy classes ----------------
ok('R17 CSS defines exactly one --interrupt accent variable',
  (C.match(/--interrupt:/g) || []).length === 1);
ok('R18 --interrupt is used for waiting-on-me/crashed chips and the firing reconciler badge',
  /state-waiting-on-me\s*\{[^}]*var\(--interrupt\)/.test(C) &&
  /state-crashed\s*\{[^}]*var\(--interrupt\)/.test(C) &&
  /reconciler-firing\s*\{[^}]*var\(--interrupt\)/.test(C));

// --- responsive: single column below ~800px, Q2 (needsme) first in the
// mobile grid-template-areas too (ux-review amendment 13) ------------------
ok('R19 mobile breakpoint stacks single-column with needsme first',
  /max-width:\s*800px[^}]*\{[^]*?grid-template-areas:\s*"needsme"/.test(C));

// --- focus-visible baseline (WCAG 2.2 AA) -----------------------------------
ok('R20 a visible focus style is defined for buttons/links/tabbable elements',
  /focus-visible/.test(C));

// --- [hidden]-override regression lock (real bug found during O.4 browser
// livesmoke: .modal-card/#docsPanel set `display: flex` unconditionally,
// which beat the native [hidden] UA-stylesheet rule, so hidden===true
// modals still computed display:flex and stayed visually rendered) -------
ok('R21 every flex-styled hideable container (.modal-card, .modal-scrim, #docsPanel) has an explicit [hidden] { display: none } override',
  /\.modal-card\[hidden\]\s*\{[^}]*display:\s*none/.test(C) &&
  /\.modal-scrim\[hidden\]\s*\{[^}]*display:\s*none/.test(C) &&
  /#docsPanel\[hidden\]\s*\{[^}]*display:\s*none/.test(C));

// ============================================================
// O.4-fix1 regression locks (acceptance-drill FAILs, 2026-07-07)
// ============================================================

// --- item 4 (keyboard-only FAIL, part 1): #whyDrawer must be
// programmatically focusable (tabindex="-1") so app.js's whyDrawer.focus()
// on open actually moves focus into the role=dialog. Without tabindex,
// .focus() silently no-ops on a plain <div> — exactly the defect the
// acceptance drill's keyboard-only pass caught. --------------------------
ok('R22 #whyDrawer has tabindex so focus() can move into the dialog on open (keyboard-only FAIL fix)',
  /id="whyDrawer"[^>]*tabindex="-1"/.test(html) || /tabindex="-1"[^>]*id="whyDrawer"/.test(html));
ok('R22b app.js calls whyDrawer.focus() when opening the drawer',
  /whyDrawer\.focus\(\)/.test(js));
ok('R22c app.js implements a Tab-wrap focus trap scoped to the why-drawer (sensible trapping, not just Esc-close)',
  /focusableIn/.test(js) && /shiftKey/.test(js));

// --- item 4 (keyboard-only FAIL, part 2): the reconciler drift-badge
// mismatch detail must be keyboard-reachable, not hover-title-only. A
// <details>/<summary> disclosure is natively focusable + Enter/Space-
// activatable (no custom JS needed for the open/close mechanic itself). --
ok('R23 reconciler badge mismatch detail is a keyboard-reachable <details> disclosure, not hover-title-only',
  /<details id="reconcilerDetails"/.test(html) && /<summary id="reconcilerBadge"/.test(html) &&
  /id="reconcilerDisclosureBody"/.test(html));
ok('R23b app.js populates the disclosure body (renderBadgeDisclosure), not just badge.title',
  /function renderBadgeDisclosure/.test(js) && /renderBadgeDisclosure\(/.test(js));

// --- item 1 (Q4 strip FAIL): per-gate 7d block/waiver/downgrade table,
// waiver-dominant gates visibly flagged (text, not color-only). ----------
ok('R24 app.js renders a per-gate table from resp.data.gates (Q4 FAIL: was doctor-verdict-only)',
  /resp\.data\.gates/.test(js) && /health-gate-row/.test(js));
ok('R24b waiver-dominant gates get a visible text flag, not color-only',
  /health-gate-flag/.test(js) && /['"]waiver-dominant['"]/.test(js));

// --- item 2 (Q5 strip FAIL): per-session rows rendered from
// resp.data.sessions (was 0 rows against a 10-session oracle). -----------
ok('R25 app.js renders per-session cost rows from resp.data.sessions (Q5 FAIL: was 0 rows)',
  /costs-session-row/.test(js) && /d\.sessions/.test(js));
ok('R25b per-session transcript_status renders as a text+color chip (a11y baseline, never color-only)',
  /transcript_status/.test(js) && /costs-session-status/.test(js));

// --- item 3 (Q6 drawer FAIL): the mandated one-line verdict renders when
// the payload carries one. ------------------------------------------------
ok('R26 app.js renders resp.data.verdict as a visible why-verdict line',
  /resp\.data\.verdict/.test(js) && /why-verdict/.test(js));

// --- item 5 (reconciler degradation-honesty): an oracle-unavailable state
// distinct from a fabricated drift count. ---------------------------------
ok('R27 app.js and reconciler.js both handle an oracle_unavailable state (never a fabricated drift count on outage)',
  /oracle_unavailable/.test(js) && /oracle_unavailable/.test(fs.readFileSync(path.join(D, '..', 'server', 'reconciler.js'), 'utf8')));

// --- item 6 (backlog permanent rc=124): per-subcommand timeout override +
// a higher built-in default for the known-slow backlog oracle. -----------
ok('R28 derive-cache.js supports a per-subcommand timeout override with a higher backlog default',
  /OBS_NL_TIMEOUT_MS_/.test(fs.readFileSync(path.join(D, '..', 'server', 'derive-cache.js'), 'utf8')) &&
  /360000/.test(fs.readFileSync(path.join(D, '..', 'server', 'derive-cache.js'), 'utf8')));

// ============================================================
// cold-reader-lint (constitution §3 amendment 53d3bee, operator directive
// 2026-07-07): Q2 pane renders the lint_warnings anatomy honestly — a
// degraded "needs context" notice, never a rejected/dropped entry.
// ============================================================
ok('R29 app.js renders it.lint_warnings as a "needs context" notice on the Q2 card (never drops the entry)',
  /it\.lint_warnings/.test(js) && /needs context/.test(js));
ok('R29b the lint notice is text+color (a11y baseline): a chip element plus a detail text node, not color-only',
  /nm-lint-chip/.test(js) && /nm-lint-detail/.test(js));
ok('R29c CSS renders the lint chip with --warn (text+color, matching the health-gate waiver-dominant precedent)',
  /\.nm-lint-chip\s*\{[^}]*var\(--warn\)/.test(C));

// ============================================================
// ask-rooted-workstreams-p1 Task 13 — "UI landing — ask tree"
// (structural self-test extension). Same DOM-free technique as the rest
// of this file: source-text regex, not a headless-browser DOM check
// (behavioral rendering against the real /api/asks + /api/ask/<id> shapes
// is covered by this task's own Prove-it-works run against a sandboxed
// server instance — see the plan's Task 13 evidence).
// ============================================================

// The anti-noise denylist (constraint 1) is checked against RENDERED
// copy, not developer comments explaining the mechanism (this file itself
// is full of such comments, by convention, same as server.js/app.js) — so
// comments are stripped before scanning, matching what an operator would
// actually see on screen.
function stripJsComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}
const asksJsNoComments = stripJsComments(asksJs);
const GATE_HOOK_DENYLIST = [
  /\.sh\b/i,
  /\bod_[a-z0-9_]+\b/i,
  /[a-z0-9_-]*-gate\b/i,
  /\b(pretooluse|posttooluse|sessionstart|userpromptsubmit)\b/i,
  /\b(plan-lifecycle|workstreams-emit|workstreams-read|session-start-digest|post-commit|close-plan|ask-registry|dispatch-provenance|plan-auto-closure|plan-edit-validator)\b/i,
];

// --- ask-tree landing container present, and precedes the six-pane
// cockpit in source order (it is the PRIMARY view — User-facing Outcome:
// "opening / shows asks grouped by project") ---------------------------
ok('T13-1 ask-tree landing container present (#askTreeSection / #askTreeBody)',
  /id="askTreeSection"/.test(html) && /id="askTreeBody"/.test(html));
ok('T13-2 ask-tree section precedes the six-pane cockpit in document source order (primary landing)',
  html.indexOf('id="askTreeSection"') !== -1 && html.indexOf('id="askTreeSection"') < html.indexOf('id="cockpit"'));
ok('T13-3 the retired Task-1 walking-skeleton ids do not survive (asksSkeletonBody/paneAsksSkeleton)',
  html.indexOf('id="asksSkeletonBody"') === -1 && html.indexOf('id="paneAsksSkeleton"') === -1);
ok('T13-4 asks.js is included by index.html', /<script src="\/asks\.js"><\/script>/.test(html));

// --- anti-noise law (hard constraint 1): zero gate/hook identifiers in
// any rendered copy — comments stripped first (see stripJsComments above),
// same denylist server/payload-schema.js enforces at the wire. ----------
const asksDenylistHits = GATE_HOOK_DENYLIST.filter((re) => re.test(asksJsNoComments));
ok('T13-5 asks.js (comments stripped) contains ZERO gate/hook/oracle identifiers anywhere a user could see them',
  asksDenylistHits.length === 0,
  asksDenylistHits.map((re) => re.toString()).join(', '));

// --- absolute-links law (hard constraint 2): exactly ONE function ever
// assigns a real <a href>, and it gates on the same 5 absolute shapes
// payload-schema.js's isAbsoluteHref checks (mirrors R13's "one
// link-resolving function" precedent for app.js). ------------------------
ok('T13-6 asks.js has exactly ONE href-gating function (absoluteLinkNode) used for every link it ever renders',
  (asksJs.match(/function absoluteLinkNode/g) || []).length === 1 && /absoluteLinkNode\(/.test(asksJs));
ok('T13-7 asks.js mirrors payload-schema.js\'s 5-shape isAbsoluteHref check (https, file://, drive-letter, UNC, POSIX)',
  /function isAbsoluteHref/.test(asksJs) &&
  /\^https\?/.test(asksJs) && /file:\\\/\\\//.test(asksJs) && /A-Za-z\]:/.test(asksJs));
const hrefAssignCount = (asksJs.match(/\.href\s*=/g) || []).length;
ok('T13-8 asks.js sets .href only inside the two guarded branches of absoluteLinkNode (http(s) passthrough + best-effort file:// conversion) — never a bare/relative href',
  hrefAssignCount === 2);

// --- plan-doc links reuse the EXISTING docModal (ux-review amendment 6:
// "no pane grows its own link handling") — no second modal/viewer. ------
ok('T13-9 asks.js reuses the shared docModal/docTitle/docBody DOM (no new doc viewer)',
  /\$\('docModal'\)/.test(asksJs) && /\$\('docTitle'\)/.test(asksJs) && /\$\('docBody'\)/.test(asksJs));
ok('T13-9b asks.js does not define a second modal-scrim/close mechanism for docs (reuses app.js\'s existing close wiring)',
  !/docScrim2|planDocModal|planDocScrim/.test(asksJs));

// --- exit-mechanism law (constraint 7) / review round 1+2: lifecycle
// affordances, undo, and the collapsed completed group with its
// count+recency header, hidden entirely when empty. ---------------------
ok('T13-10 lifecycle actions call POST /api/ask/<id>/lifecycle for done/dismiss/merge/reopen',
  /\/api\/ask\/'\s*\+\s*encodeURIComponent\(askId\)\s*\+\s*'\/lifecycle'/.test(asksJs) &&
  /'done'/.test(asksJs) && /'dismiss'/.test(asksJs) && /'merge'/.test(asksJs) && /'reopen'/.test(asksJs));
ok('T13-11 every lifecycle action shows success feedback with an Undo affordance (constraint 9)',
  /ask-feedback-text/.test(asksJs) && /ask-undo-btn/.test(asksJs) && /UNDO_WINDOW_MS/.test(asksJs));
ok('T13-12 the completed group is HIDDEN entirely when count is 0 (never an expanded empty shell — review round 2)',
  /completed\.count === 0\) return null/.test(asksJs));
ok('T13-13 the completed-group header names the count + newest-completed recency (review round 2)',
  /'Completed \(' \+ completed\.count \+ ' · newest '/.test(asksJs));

// --- DRILL-DOWN SIGNIFIER (review round 1): an explicit control beside
// the bar, native <details>/<summary> (real chevron + keyboard/AT support,
// same convention as the reconciler badge / per-gate health rows). ------
ok('T13-14 the plan progress bar has an explicit drill-down control beside it (ask-drilldown-details), never itself the sole click target',
  /ask-drilldown-details/.test(asksJs) && /ask-progress-bar/.test(asksJs));
ok('T13-15 the drill-down control fetches /api/ask/<id> lazily on first expand only (perf budget: no oracle shelling on the landing path)',
  /details\.addEventListener\('toggle'/.test(asksJs) && /details\.open && !fetched/.test(asksJs));

// --- MULTI-PLAN CARDS (review round 2): per-plan blocks grouped by
// plan_slug, one live-doc link per plan. ---------------------------------
ok('T13-16 drill-down groups per-task rows BY PLAN (renderPlanBlock over plan_rows, one per plan_slug)',
  /function renderPlanBlock/.test(asksJs) && /planRows\.forEach/.test(asksJs));
ok('T13-16b one live-doc link per plan (View live plan doc button per plan_doc)',
  /View live plan doc/.test(asksJs));

// --- four UI states (constraint 8), operator-altitude copy (no od_*/
// oracle/gate/hook identifiers inherited from app.js's state copy). -----
ok('T13-17 landing empty state (no asks yet) names the capture mechanism, not a blank page',
  /No asks registered yet\. New sessions register their opening ask automatically/.test(asksJs));
ok('T13-18 no-plan-card empty state ("no plan linked yet") distinct from an error',
  /no plan linked yet/.test(asksJs));
ok('T13-19 drill-down-no-tasks empty state is an honest line, not silently blank',
  /no tasks found for this plan/.test(asksJs));
ok('T13-20 fetch-failure states render a named error + a real Retry control (server restarts are real)',
  (asksJs.match(/className = 'btn-go small'/g) || []).length >= 1 && /retry\.textContent = 'Retry'/.test(asksJs) &&
  /Could not load asks/.test(asksJs));
ok('T13-21 loading state is aria-busy and distinct from the error state (rc===null vs rc!==0 distinction, inherited convention)',
  /aria-busy="true">loading/.test(asksJs));

// --- a11y (constraint 9): real buttons (never clickable divs) for every
// interactive control this module renders; text+color for every chip. --
const askButtonCount = (asksJs.match(/createElement\('button'\)/g) || []).length;
ok('T13-22 every interactive control in asks.js is a real <button> (createElement(\'button\') used repeatedly, not a clickable div)',
  askButtonCount >= 8, 'count=' + askButtonCount);
ok('T13-23 asks.js never wires a click handler onto a bare div (no div.addEventListener(\'click\' pattern)',
  !/[Dd]iv\.addEventListener\('click'/.test(asksJs));
ok('T13-24 task-status chips render textContent from a label map (text + color, never color-only)',
  /chip\.textContent = TASK_STATUS_LABEL\[status\]/.test(asksJs));
ok('T13-25 session heartbeat-state chips render textContent from a label map (text + color, never color-only)',
  /chip\.textContent = HB_STATE_LABEL\[st\] \|\| st/.test(asksJs));
ok('T13-26 drift badges render as real <summary> elements with visible text (never color-only) — updated by cockpit-roadmap-redesign Task 6 to the class+count label (was String(label))',
  /sum\.className = 'chip ask-badge'/.test(asksJs) && /sum\.textContent = cls \+ ' ×' \+ members\.length/.test(asksJs));
ok('T13-27 session-id copy affordance carries the mandated resume microcopy verbatim',
  /copy session id — resume with `claude --resume ' \+ s\.session_id \+ '`/.test(asksJs));

// --- desktop deep-link spike (Task 13, timeboxed <=2h): guaranteed
// copy-button fallback ships regardless of spike outcome; no unverified
// claude:// affordance is rendered (the registered protocol's session-
// resume URL grammar is undocumented — shipping an unverified link would
// be a false affordance). -------------------------------------------------
ok('T13-28 no unverified claude:// deep-link is rendered as a clickable affordance (spike outcome: guaranteed copy-button fallback only)',
  !/claude:\/\//.test(asksJs));
ok('T13-29 the guaranteed copy-button + resume-microcopy fallback IS present for every session id (spike\'s committed path)',
  /Copy session id/.test(asksJs));

// --- [hidden]-override regression lock (REAL bug found via live-browser
// verification during this task's build: the merge chooser + feedback row
// rendered VISIBLE despite `.hidden = true` in asks.js, because their
// `display: flex` CSS beat the UA [hidden] default at equal specificity —
// same regression class R21 already locks for .modal-card/.modal-scrim/
// #docsPanel). ------------------------------------------------------------
ok('T13-30 every flex-styled element asks.js toggles via .hidden has an explicit [hidden] { display: none } override (ask-lifecycle-actions, ask-merge-chooser, ask-feedback-row)',
  /\.ask-lifecycle-actions\[hidden\][^{]*\{[^}]*display:\s*none/.test(C) &&
  /\.ask-merge-chooser\[hidden\][^{]*\{[^}]*display:\s*none/.test(C) &&
  /\.ask-feedback-row\[hidden\][^{]*\{[^}]*display:\s*none/.test(C));

// ============================================================
// cockpit-roadmap-redesign Task 6 — "Badge law + badge-storm fix" (the
// renderer half; the auditor half already shipped, commit 0cb4f9b).
// PRODUCTION DEFECT (docs/reviews/2026-07-17-cockpit-ux-redesign-proposal.md
// D4/§5, badge-storm nl-issue): 718 identical unmatched_dispatch badges
// rendered as 718 unlabeled "drift" chips (asks.js:213-238 pre-fix) —
// renderDriftBadges had no grouping/cap/dedup at all.
//
// FIX ROUND (2026-07-19, both gates on the FIRST pass, addressed below):
//   - task-verifier conf 7: the first pass CAPPED bookkeeping classes to
//     one on-card chip; §5 and Acceptance Scenario 4 require SUPPRESSION
//     (0 board chips; the counted summary belongs in Harness Health only).
//     T6-1/T6-2/T6-3 below pin the corrected suppression semantics.
//   - comprehension-reviewer conf 5: the drill-down materialized one DOM
//     node per badge instance unboundedly. T6-5/T6-6/T6-6b/T6-6c below pin
//     the DRILL_DOWN_LINE_CAP (50) + "+K more" bound.
//   - T6H-* is new: the Harness Health half (app.js) that the suppressed
//     bookkeeping classes now redirect to.
//
// Every other check in this file is DOM-free source-text regex (by design —
// see the file header). That technique can prove the SHAPE of the fix
// (a grouping/suppression construct exists) but cannot prove the fixture
// claims the plan makes ("700 bookkeeping badges -> 0 board chips",
// "718 badges -> drill-down capped at 51 elements") — that requires
// actually running the real function against fixture data and reading the
// output. So this section sandboxes the ACTUAL renderDriftBadges source
// (extracted verbatim between the BADGE-LAW-RENDER-BEGIN/END anchors in
// asks.js — not a reimplementation) inside a minimal hand-rolled fake DOM
// via Node's built-in `vm` module, staying dependency-free (no
// jsdom/headless browser, preserving this file's "no build step"
// property). The T6H-* section below does the same for app.js's
// bookkeepingDivergenceSummary (a pure function — no fake DOM needed).
// ============================================================
const vmMod = require('vm');
const badgeLawSrc = (function () {
  const beginMarker = '// BADGE-LAW-RENDER-BEGIN';
  const endMarker = '// BADGE-LAW-RENDER-END';
  const bi = asksJs.indexOf(beginMarker);
  const ei = asksJs.indexOf(endMarker);
  if (bi === -1 || ei === -1 || ei < bi) return null;
  return asksJs.slice(bi, ei);
})();
ok('T6-0 selftest can locate the BADGE-LAW-RENDER extraction anchors in asks.js (source-execution harness precondition)',
  !!badgeLawSrc);

function makeFakeDom() {
  function FakeNode(tag) {
    this.tagName = tag;
    this.className = '';
    this._text = '';
    this.children = [];
  }
  Object.defineProperty(FakeNode.prototype, 'textContent', {
    get: function () { return this._text; },
    set: function (v) { this._text = v; this.children = []; },
  });
  FakeNode.prototype.appendChild = function (c) { this.children.push(c); return c; };
  return { createElement: function (tag) { return new FakeNode(tag); } };
}
function runBadgeLaw(badgesArray) {
  if (!badgeLawSrc) return { __error: 'extraction anchors missing' };
  const sandbox = { document: makeFakeDom() };
  vmMod.createContext(sandbox);
  const code = badgeLawSrc + '\nvar __result = renderDriftBadges(' + JSON.stringify(badgesArray === undefined ? null : badgesArray) + ');';
  try {
    vmMod.runInContext(code, sandbox);
  } catch (err) {
    return { __error: String(err) };
  }
  return sandbox.__result;
}
function chipLabels(wrapNode) {
  return (wrapNode && wrapNode.children ? wrapNode.children : []).map((det) => det.children[0].textContent);
}

// --- FIX ROUND (task-verifier conf 7, Acceptance Scenario 4 literal shape):
// 700 identical BOOKKEEPING (unmatched_dispatch) badges -> ZERO board chips,
// not one. Suppression, not a cap. ------------------------------------------
function makeBadges(cls, n, labelPrefix) {
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push({ divergence_class: cls, message: (labelPrefix || cls) + ' instance ' + i, detail_ref: 'drift-x-' + cls + '-' + i, plan_slug: 'plan-x', task_id: String(i) });
  }
  return out;
}
const fixture700Bookkeeping = makeBadges('unmatched_dispatch', 700);
const result700 = runBadgeLaw(fixture700Bookkeeping);
ok('T6-1 Acceptance Scenario 4: 700 identical unmatched_dispatch (bookkeeping) badges render ZERO board chips (suppressed, not capped)',
  result700 === null, JSON.stringify(result700));

// --- the SAME 700-badge fixture's counted summary reaching Harness Health
// is proven below (T6H-2, against app.js's bookkeepingDivergenceSummary) —
// scenario 4's "0 board chips + Harness Health count present" is one claim
// split across the two files that actually implement it. -------------------

// --- mixed fixture: bookkeeping + belief-changing -> ONLY the
// belief-changing chip renders on the board. --------------------------------
const mixedBoard = []
  .concat(makeBadges('unmatched_dispatch', 5))
  .concat(makeBadges('orphaned_waiting_item', 2))
  .concat(makeBadges('unknown_provenance', 1))
  .concat([{ divergence_class: 'log_ahead_task_not_flipped', message: 'the progress log shows task 2 verified done, but the plan file still shows it open' }]);
const resultMixedBoard = runBadgeLaw(mixedBoard);
ok('T6-2 mixed bookkeeping+belief-changing fixture renders ONLY the belief-changing chip on the board (8 badges in, 1 chip out)',
  resultMixedBoard && resultMixedBoard.children && resultMixedBoard.children.length === 1 && chipLabels(resultMixedBoard)[0] === 'log_ahead_task_not_flipped ×1',
  JSON.stringify(chipLabels(resultMixedBoard)));

// --- precedence STILL sorts among belief-changing classes when more than
// one is present — using synthetic non-bookkeeping class names since
// log_ahead_task_not_flipped is currently the only REAL belief-changing
// class the auditor emits; this proves the ranked-then-stable-alphabetical
// sort mechanism generically, for whatever future belief-changing classes
// get added. ------------------------------------------------------------
const precedenceFixture = [
  { divergence_class: 'synthetic_zzz_belief_changing', message: 'm1' },
  { divergence_class: 'log_ahead_task_not_flipped', message: 'the progress log shows task 2 verified done, but the plan file still shows it open' },
  { divergence_class: 'synthetic_aaa_belief_changing', message: 'm2' },
];
const resultPrecedence = runBadgeLaw(precedenceFixture);
ok('T6-3 precedence still orders multiple belief-changing classes (ranked class first, unranked classes stable-alphabetical after) regardless of input order',
  JSON.stringify(chipLabels(resultPrecedence)) === JSON.stringify([
    'log_ahead_task_not_flipped ×1', 'synthetic_aaa_belief_changing ×1', 'synthetic_zzz_belief_changing ×1',
  ]),
  JSON.stringify(chipLabels(resultPrecedence)));

// --- fixture: zero badges -> NO chip, never an empty container ------------
ok('T6-4 zero badges (empty array) renders null, not an empty wrapping <span> (the pre-fix code always appended an empty container)',
  runBadgeLaw([]) === null);
ok('T6-4b zero badges (drift_badges omitted/undefined, the pre-Task-12 shape) also renders null',
  runBadgeLaw(undefined) === null);

// --- COMPREHENSION FIX (conf 5): the drill-down's own DOM footprint is
// capped at DRILL_DOWN_LINE_CAP (50) + one "+K more" line, regardless of
// upstream badge count -- using a belief-changing class here (bookkeeping
// classes never reach the board at all post-suppression-fix, so a
// bookkeeping fixture couldn't exercise the on-card drill-down anymore). ---
const fixture718BeliefChanging = makeBadges('log_ahead_task_not_flipped', 718);
const result718 = runBadgeLaw(fixture718BeliefChanging);
ok('T6-5 718 identical belief-changing badges still render as exactly ONE chip labeled "log_ahead_task_not_flipped ×718"',
  result718 && result718.children && result718.children.length === 1 && chipLabels(result718)[0] === 'log_ahead_task_not_flipped ×718',
  JSON.stringify(chipLabels(result718)));
ok('T6-6 the drill-down body is CAPPED at 51 elements (50 badge lines + one "+K more" line), not 718 -- the comprehension gate\'s fix',
  result718 && result718.children && result718.children[0].children[1].children.length === 51,
  result718 && result718.children && result718.children[0].children[1].children.length);
ok('T6-6b the "+K more" line reads "+668 more" (718 - 50) and is the LAST child of the detail body',
  result718 && result718.children && result718.children[0].children[1].children[50].textContent === '+668 more',
  result718 && result718.children && result718.children[0].children[1].children[50] && result718.children[0].children[1].children[50].textContent);
ok('T6-6c below the cap (5 badges, cap is 50), NO "+K more" line is appended -- the cap is a ceiling, never a floor',
  runBadgeLaw(makeBadges('log_ahead_task_not_flipped', 5)).children[0].children[1].children.length === 5);

// --- the live ask-card call site must only append the drift-badges node
// when non-null (source-text check: the DOM-execution fixtures above prove
// the FUNCTION's contract; this proves the CALL SITE honors it). -----------
ok('T6-7 the ask-card call site only appends the drift-badges node when non-null (never wires an empty container into the live card)',
  /var driftBadgesNode = renderDriftBadges\(ask\.drift_badges\);\s*\n\s*if \(driftBadgesNode\) statusRow\.appendChild\(driftBadgesNode\);/.test(asksJs));

// ============================================================
// Harness Health half of the fix (app.js) — bookkeeping classes suppressed
// from the board (above) must surface their counted summary here. Same
// vm-sandboxed real-source-execution technique; bookkeepingDivergenceSummary
// is a PURE function (no DOM), so no fake DOM is needed for these.
// ============================================================
const appDiagSrc = (function () {
  const beginMarker = '// BOOKKEEPING-DIAG-BEGIN';
  const endMarker = '// BOOKKEEPING-DIAG-END';
  const bi = js.indexOf(beginMarker);
  const ei = js.indexOf(endMarker);
  if (bi === -1 || ei === -1 || ei < bi) return null;
  return js.slice(bi, ei);
})();
ok('T6H-1 selftest can locate the BOOKKEEPING-DIAG extraction anchors in app.js (source-execution harness precondition)',
  !!appDiagSrc);

function runBookkeepingSummary(badgesByAsk) {
  if (!appDiagSrc) return { __error: 'extraction anchors missing' };
  const sandbox = {};
  vmMod.createContext(sandbox);
  const code = appDiagSrc + '\nvar __result = bookkeepingDivergenceSummary(' + JSON.stringify(badgesByAsk) + ');';
  try {
    vmMod.runInContext(code, sandbox);
  } catch (err) {
    return { __error: String(err) };
  }
  return sandbox.__result;
}

const summary700 = runBookkeepingSummary({ 'ask-x': fixture700Bookkeeping });
ok('T6H-2 Acceptance Scenario 4\'s Harness Health half: the SAME 700-bookkeeping-badge fixture summarizes to {total:700, classCount:1}',
  summary700 && summary700.total === 700 && summary700.classCount === 1, JSON.stringify(summary700));

const summaryMixedAcrossAsks = runBookkeepingSummary({
  'ask-a': makeBadges('unmatched_dispatch', 3).concat(makeBadges('log_ahead_task_not_flipped', 1)),
  'ask-b': makeBadges('orphaned_waiting_item', 2),
});
ok('T6H-3 bookkeeping summary aggregates ACROSS asks and excludes belief-changing classes from the count (3 unmatched_dispatch + 2 orphaned_waiting_item = 5 total, 2 classes; the 1 log_ahead_task_not_flipped is excluded)',
  summaryMixedAcrossAsks && summaryMixedAcrossAsks.total === 5 && summaryMixedAcrossAsks.classCount === 2,
  JSON.stringify(summaryMixedAcrossAsks));

// --- cross-file consistency: asks.js's board-suppression set and app.js's
// Harness Health set must name the SAME three bookkeeping classes -- there
// is no shared module system between these two plain-script files, so this
// is the mechanical guard against the two literal sets silently drifting
// apart (e.g. a class added to one suppression list but not the other would
// either vanish from both surfaces or double-count). ------------------------
const BOOKKEEPING_SET_RE = /unmatched_dispatch:\s*true,\s*\n\s*orphaned_waiting_item:\s*true,\s*\n\s*unknown_provenance:\s*true,/;
ok('T6H-4 asks.js and app.js declare the IDENTICAL BOOKKEEPING_DIVERGENCE_CLASSES literal (no drift between the two duplicated definitions)',
  BOOKKEEPING_SET_RE.test(asksJs) && BOOKKEEPING_SET_RE.test(js));

ok('T6H-5 the new Harness Health row sets visible textContent (text + color, never color-only), same a11y baseline as every other diag-row',
  /bookkeepingRow\.textContent = 'progress-log bookkeeping divergences: '/.test(js));

// ============================================================
// ask-rooted-workstreams-p1 Task 16 — "Layout integration + Harness Health
// demotion" (structural self-test extension, constraint 9). The six
// wave-O panes + reconciler + interrupt strip + why-drawer are quarantined
// inside <template id="harnessHealthTemplate"> in index.html — a native
// <template>'s content is inert (not parsed into the live document, not in
// the accessibility tree, not matched by document.getElementById) until
// app.js's initHarnessHealthTab() explicitly clones it in, the first time
// the operator opens the Harness Health tab. This section proves the
// quarantine holds at the source level (a), then re-verifies the
// color-only-signal and real-button invariants (b, c) across the FULLY
// ASSEMBLED landing surface — the point where every module (asks.js,
// todo.js, backlog.js, the new tab shell) comes together for the first
// time.
// ============================================================

// --- (a) anti-noise landing-DOM check: every pane-family id appears ONLY
// between the <template id="harnessHealthTemplate"> open/close tags, never
// in the landing (non-Harness-Health) portion of the document. ------------
const templateOpenTag = '<template id="harnessHealthTemplate">';
const templateOpenIdx = html.indexOf(templateOpenTag);
const templateCloseIdx = html.indexOf('</template>');
ok('T16-1 <template id="harnessHealthTemplate"> exists and wraps a closing </template>',
  templateOpenIdx !== -1 && templateCloseIdx !== -1 && templateCloseIdx > templateOpenIdx);

const PANE_FAMILY_IDS = ['paneNeedsMe', 'paneStatus', 'paneHealth', 'paneCosts', 'paneShipped', 'paneBacklog',
  'interruptStrip', 'reconcilerBadge', 'reconcilerDetails', 'whyDrawer', 'whyScrim', 'diagnosticsBody'];
const outsideTemplate = templateOpenIdx === -1 ? html
  : html.slice(0, templateOpenIdx) + html.slice(templateCloseIdx + '</template>'.length);
const paneLeaks = PANE_FAMILY_IDS.filter((id) => outsideTemplate.indexOf('id="' + id + '"') !== -1);
ok('T16-2 landing DOM (everything outside the Harness Health <template>) contains ZERO pane-family identifiers (anti-noise, mechanized)',
  paneLeaks.length === 0, paneLeaks.join(', '));

// every one of those ids DOES still exist somewhere (R1/R3/R4/R7 already
// assert this positively) — T16-2 additionally proves their ONLY home is
// inside the template, i.e. quarantined, not merely present twice.
ok('T16-2b every pane-family id is present inside the template (moved, not deleted)',
  PANE_FAMILY_IDS.every((id) => html.indexOf('id="' + id + '"') !== -1));

// --- Harness Health tab wire check: index.html tab shell -> app.js router.
// UPDATED by cockpit-roadmap-redesign Task 3 (C2): the two-tab Task 16
// shell became the four-tab navigation shell — Roadmap / Requests / Inbox /
// Harness Health, hash-routed; the Asks panel became the Requests tab's
// interim content (same registry — asks ARE requests; task 5 rebuilds the
// view). The Harness Health lazy-template quarantine is UNCHANGED.
ok('T16-3 index.html defines the four-tab nav driving app.js\'s router (Roadmap/Requests/Inbox/Health)',
  /id="tabRoadmapBtn"/.test(html) && /id="tabRequestsBtn"/.test(html) &&
  /id="tabInboxBtn"/.test(html) && /id="tabHealthBtn"/.test(html) &&
  /id="tabRequestsPanel"/.test(html) && /id="tabHealthPanel"/.test(html));
ok('T16-4 app.js implements initHarnessHealthTab() which clones the template and activateTab() which drives the tab nav',
  /function initHarnessHealthTab/.test(js) && /function activateTab/.test(js) &&
  /harnessHealthTemplate\.content\.cloneNode\(true\)/.test(js));
ok('T16-5 Roadmap is the default landing tab (router defaults to #roadmap; #tabHealthPanel starts hidden)',
  /'#roadmap'/.test(js) && /routeFromHash\(\)/.test(js) && /id="tabHealthPanel"[^>]*\bhidden\b/.test(html));

// --- no Team tab anywhere in P1 (review round 1 — no empty shell surfaces,
// binding constraint carried through Task 16's own assembly). -------------
ok('T16-6 no Team tab nav entry or markup exists anywhere in the assembled shell',
  !/Team/.test(html.replace(/<!--[\s\S]*?-->/g, '')) && !/tabTeamBtn|tabTeamPanel/.test(html) && !/tabTeamBtn|tabTeamPanel/.test(js));

// --- (b) COLOR-ONLY-SIGNAL check (WCAG 1.4.1), across the FULLY ASSEMBLED
// surface — every color-bearing state/badge class this app defines pairs
// its color rule with a textContent assignment in the module that renders
// it (aggregates the individual per-task precedents — R16/R24b/R25b/
// T13-24-26 — into one cross-cutting check, plus the NEW tab-active
// indicator and diagnostics counts Task 16 itself introduces). -----------
const badgeInvariants = [
  ['state-waiting-on-me', js, /chip\.textContent = s\.state/],
  ['doctor-red', js, /chip\.textContent = doctor\.verdict/],
  ['health-gate-flag', js, /flag\.textContent = 'waiver-dominant'/],
  ['costs-status-stale', js, /statusTd\.textContent = st/],
  ['ask-badge', asksJsNoComments, /sum\.textContent = cls \+ ' ×' \+ members\.length/],
  ['ask-task-status', asksJsNoComments, /chip\.textContent = TASK_STATUS_LABEL\[status\]/],
  ['backlog-badge', backlogJs, /badge\.textContent = row\.disposition_word/],
];
const badgeFailures = badgeInvariants.filter(([cls, src, textRe]) => !(new RegExp('\\.' + cls + '\\b').test(C)) || !textRe.test(src));
ok('T16-7 every color-bearing state/badge class across the assembled surface (session/doctor/gate/costs/ask/task/backlog) also sets visible text, never color-only (WCAG 1.4.1)',
  badgeFailures.length === 0, badgeFailures.map((f) => f[0]).join(', '));
ok('T16-8 the tab-active indicator carries a PROGRAMMATIC state (aria-selected) in addition to any visual underline, never color-only',
  /setAttribute\('aria-selected'/.test(js) && /aria-selected="true"/.test(html));
ok('T16-9 diagnostics healed/error counts render as visible TEXT, never a bare color dot',
  /diag-healed/.test(js) && /diag-errors/.test(js) && /healedRow\.textContent/.test(js) && /errRow\.textContent/.test(js));

// --- (c) REAL-BUTTON check — every interactive control across the
// assembled landing (index.html's tab nav + inbox.js's "My items" section
// [todo.js's retired replacement, cockpit-roadmap-redesign Task 8 item 5]
// + backlog.js; asks.js already covered by T13-22/23) is a real
// <button>/<a>, never a clickable <div>. ----------------------------------
ok('T16-10 the tab-nav controls are real <button> elements, never clickable divs',
  /<button[^>]+id="tabRoadmapBtn"/.test(html) && /<button[^>]+id="tabRequestsBtn"/.test(html) &&
  /<button[^>]+id="tabInboxBtn"/.test(html) && /<button[^>]+id="tabHealthBtn"/.test(html));
ok('T16-11 inbox.js\'s "My items" section (todo.js\'s retired replacement) never wires a click handler onto a bare div (real buttons/inputs only) — repointed from the retired todo.js',
  !/[Dd]iv\.addEventListener\('click'/.test(inboxJs));
ok('T16-12 backlog.js never wires a click handler onto a bare div (real buttons only)',
  !/[Dd]iv\.addEventListener\('click'/.test(backlogJs));
ok('T16-13 inbox.js\'s "My items" rows and backlog.js build their interactive controls with createElement(\'button\')/the shared btn() factory, not divs — repointed from the retired todo.js (the btn() factory itself + the add-form\'s explicit type="submit" button, which cannot use the type="button" factory, account for inbox.js\'s two literal call sites)',
  /function renderMyItemOperatorRow/.test(inboxJs) && /function renderMyItemPointerRow/.test(inboxJs) &&
  (inboxJs.match(/createElement\('button'\)/g) || []).length >= 2 &&
  (backlogJs.match(/createElement\('button'\)/g) || []).length >= 3);

// --- DOM-id collision regression lock (REAL bug found during this task's
// build: the pre-Task-16 markup gave the six-pane cockpit's "Backlog
// health" strip the SAME id="backlogBody" as the Task 15 sidebar Backlog
// pane — document.getElementById always resolves to the first match in
// document order, so app.js's renderBacklog() was silently racing
// backlog.js's sidebar pane for the same node. index.html now gives the
// six-pane strip its own id (backlogHealthBody); this locks the fix. -----
ok('T16-14 the six-pane cockpit\'s backlog-health strip has its OWN id (backlogHealthBody), distinct from the Task 15 sidebar\'s #backlogBody',
  /id="backlogHealthBody"/.test(html) && (html.match(/id="backlogBody"/g) || []).length === 1);
ok('T16-14b app.js\'s renderBacklog() targets backlogHealthBody, never the sidebar\'s backlogBody id',
  /backlogHealthBody/.test(js) && !/\$\('backlogBody'\)/.test(js));

// ============================================================
// cockpit-v2-push-materialized-store Task 4 — "Peers" section (structural
// self-test extension, PV-prefix). Same DOM-free source-regex technique as
// the rest of this file — the REAL wiring proof (fixture coord clone,
// real HTTP GET /api/asks) is server/server.selftest.js's S64-S69 above.
// Anti-noise (T13-5) and absolute-links (T13-6/7/8) already re-scan the
// WHOLE of asksJs, so this section's additions are automatically covered
// by those checks without duplicating them here.
// ============================================================

ok('PV-1 renderPeersSection() exists and is called from renderLanding on BOTH the normal path and the fully-empty (zero-asks) path — Peers is an independent capability from ask-tracking',
  /function renderPeersSection/.test(asksJsNoComments) &&
  (asksJsNoComments.match(/renderPeersSection\(payload\.peers\)/g) || []).length === 2);

ok('PV-2 the Peers <details> is COLLAPSED when there is no peer data yet, OPEN when there is (never hidden entirely, unlike the completed group)',
  /details\.open = !!peers\.has_data/.test(asksJsNoComments));

ok('PV-3 a peer plan row ALWAYS renders its provenance_label (F4: never a bare checkbox that could read as local truth)',
  /prov\.textContent = p\.provenance_label/.test(asksJsNoComments));

ok('PV-4 an unmerged peer row is visually distinguished via a dedicated CSS hook, not color alone (peer-unmerged class + textual "unmerged" in the label itself)',
  /peer-unmerged/.test(asksJsNoComments) && /peer-unmerged/.test(C));

ok('PV-5 peer-level state chip renders textContent = the full state_label (text + color, never color-only)',
  /chip\.className = 'chip peer-state peer-state-' \+ e\.state/.test(asksJsNoComments) &&
  /chip\.textContent = e\.state_label/.test(asksJsNoComments));

ok('PV-6 peer session chip renders textContent from a label map (text + color, never color-only)',
  /chip\.textContent = PEER_SESSION_STATE_LABEL\[st\] \|\| st/.test(asksJsNoComments));

ok('PV-7 "my coord view last refreshed" (the reader\'s OWN transport health) renders as visible text',
  /coordHealth\.textContent = \(peers\.my_coord_refresh/.test(asksJsNoComments));

ok('PV-8 peer plan-doc links reuse the EXISTING openPlanDocModal (no second doc-viewer surface for peer rows)',
  /openPlanDocModal\(p\.plan_doc\.project, p\.plan_doc\.path\)/.test(asksJsNoComments));

ok('PV-9 CSS defines all three named peer states (fresh-ish/estate-unchanged/peer-unreachable) as distinct text+color chip classes',
  /\.peer-state-fresh-ish\s*\{[^}]*var\(--ok\)/.test(C) &&
  /\.peer-state-estate-unchanged\s*\{[^}]*var\(--warn\)/.test(C) &&
  /\.peer-state-peer-unreachable\s*\{[^}]*var\(--interrupt\)/.test(C));

// ============================================================
// cockpit-roadmap-redesign Task 3 — "Roadmap tree view + the navigation
// shell" (T3-prefix). Same DOM-free source-regex technique as the rest of
// this file; the REAL wiring proof (fixture registry + plan files, real
// HTTP) is server/roadmap-routes.selftest.js. roadmap.js is read guarded so
// a missing file fails THESE checks instead of crashing the whole suite.
// ============================================================
let roadmapJs = '';
try { roadmapJs = fs.readFileSync(path.join(D, 'roadmap.js'), 'utf8'); } catch (_) { /* T3 checks fail honestly below */ }
const roadmapJsNoComments = stripJsComments(roadmapJs);

// inbox.js — already read near the top of this file (ahead of the T16
// section, which needs it too); this note stands in its old place so a
// reader following the T3/T4 block's original narrative still finds it.
// cockpit-roadmap-redesign Task 4 moved the Inbox (N) derivation out of
// app.js's interim renderer (REMOVED, not overridden — see the
// build/roadmap-t4 commit) into that file entirely.

// ---- T3 comprehension-gate fixes (both PROVEN, conf 6): the two checks
// below need real EXECUTION (not source-regex) to prove behavior, so they
// reuse the T6 badge-law technique — extract the REAL source between
// anchors / the REAL regex literal, run it in a minimal Node `vm` sandbox
// (no jsdom/headless browser, per this file's header). --------------------

// FIX 1 — captureUiState must capture an open title editor's uncommitted
// value by PRESENCE, not focus (a focus-gated capture silently loses the
// edit when focus is on Save/Cancel or has left the pane).
const captureUiStateSrc = (function () {
  const beginMarker = '// CAPTURE-UI-STATE-BEGIN';
  const endMarker = '// CAPTURE-UI-STATE-END';
  const bi = roadmapJs.indexOf(beginMarker);
  const ei = roadmapJs.indexOf(endMarker);
  if (bi === -1 || ei === -1 || ei < bi) return null;
  return roadmapJs.slice(bi, ei);
})();
ok('T3-27b selftest can locate the CAPTURE-UI-STATE extraction anchors in roadmap.js (source-execution harness precondition)',
  !!captureUiStateSrc);

function runCaptureUiState(opts) {
  opts = opts || {};
  if (!captureUiStateSrc) return { __error: 'extraction anchors missing' };
  const sandbox = {
    window: { scrollY: opts.scrollY || 0 },
    body: {
      scrollTop: opts.bodyScrollTop || 0,
      contains: function () { return opts.activeInBody !== false; },
    },
    document: {
      activeElement: opts.activeElement || null,
      querySelector: function (sel) { return sel === '.rm-title-input' ? (opts.openInput || null) : null; },
    },
  };
  vmMod.createContext(sandbox);
  const code = captureUiStateSrc + '\nvar __result = captureUiState();';
  try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
  return sandbox.__result;
}

const fakeSaveBtn = { tagName: 'BUTTON', dataset: {} };
const fakeOpenInput = {
  classList: { contains: function (c) { return c === 'rm-title-input'; } },
  dataset: { editFor: 'item-42' },
  value: 'uncommitted title text',
  selectionStart: 3, selectionEnd: 7,
};

// FIX 2 — hash id encode/decode symmetry: extract the REAL ITEM_HASH_RE
// regex literal from app.js AND the REAL '#request/' generation expression
// from roadmap.js (not reimplementations of either) and execute both.
const ITEM_HASH_RE = (function () {
  const marker = 'var ITEM_HASH_RE = ';
  const i = js.indexOf(marker);
  if (i === -1) return null;
  const end = js.indexOf(';', i);
  if (end === -1) return null;
  try { return eval(js.slice(i + marker.length, end)); } catch (_) { return null; }
})();

// Balanced-paren extraction of shell.navigate(...)'s argument expression,
// located by an unambiguous literal prefix present in BOTH the pre-fix
// ('#request/' + r.id) and post-fix ('#request/' + encodeURIComponent(r.id))
// source shapes, so this proves whatever the source ACTUALLY says today.
function extractCallArg(src, callPrefixMarker) {
  const i = src.indexOf(callPrefixMarker);
  if (i === -1) return null;
  const openIdx = src.indexOf('(', i);
  if (openIdx === -1) return null;
  let depth = 0, j = openIdx;
  for (; j < src.length; j++) {
    if (src[j] === '(') depth++;
    else if (src[j] === ')') { depth--; if (depth === 0) break; }
  }
  if (depth !== 0) return null;
  return src.slice(openIdx + 1, j);
}
const requestNavigateArg = extractCallArg(roadmapJs, "shell.navigate('#request/'");
ok('T3-4a selftest can extract the from-request shell.navigate() argument expression from roadmap.js (source-execution harness precondition)',
  !!requestNavigateArg);

// --- shell: four tabs, Roadmap lands (C2) --------------------------------
ok('T3-1 the shell defines all four tabs (Roadmap/Requests/Inbox/Harness Health) as real buttons + panels',
  /<button[^>]+id="tabRoadmapBtn"/.test(html) && /<button[^>]+id="tabRequestsBtn"/.test(html) &&
  /<button[^>]+id="tabInboxBtn"/.test(html) && /<button[^>]+id="tabHealthBtn"/.test(html) &&
  /id="tabRoadmapPanel"/.test(html) && /id="tabRequestsPanel"/.test(html) &&
  /id="tabInboxPanel"/.test(html) && /id="tabHealthPanel"/.test(html));
ok('T3-2 Roadmap is the LANDING tab (aria-selected at parse + the router defaults to #roadmap)',
  /id="tabRoadmapBtn"[^>]*aria-selected="true"/.test(html) && /'#roadmap'/.test(js));
ok('T3-3 the Inbox tab carries a LIVE count element and inbox.js derives N from ANSWERABLE items only (lint-quarantined excluded — I4/A10; moved off app.js by Task 4, see T4-* below for the full view)',
  /id="inboxTabCount"/.test(html) && /answerable/i.test(inboxJs) && !/loadInbox\(\)/.test(js));

// --- hash routing + the landed state (C2) --------------------------------
ok('T3-4 hash router handles the three item address families (#roadmap/<id> #request/<id> #inbox/<id>) + hashchange',
  /#\(\?:roadmap\|request\|inbox\)|\(roadmap\|request\|inbox\)/.test(js) && /hashchange/.test(js));
ok('T3-4b hash id encode/decode symmetry: an item id containing \'%\' and \'#\' round-trips generation→parse WITHOUT throwing and lands as the exact original id (the REAL roadmap.js generation expression + REAL app.js ITEM_HASH_RE/decode, extracted+executed — not reimplementations)',
  (function () {
    if (!ITEM_HASH_RE || !requestNavigateArg) return false;
    var rawId = 'weird%25-id#with-hash/slash';
    var hash, threw = false, family = null, decoded = null;
    try {
      // executes the ACTUAL source text found at roadmap.js's from-request
      // link (whatever it currently says — raw concat or encoded) against a
      // fake {id: rawId} request object.
      hash = new Function('r', 'encodeURIComponent', 'return (' + requestNavigateArg + ');')(
        { id: rawId }, encodeURIComponent);
      var m = ITEM_HASH_RE.exec(hash);
      family = m && m[1];
      decoded = m && decodeURIComponent(m[2]); // the app.js routeFromHash parse formula
    } catch (e) { threw = true; }
    return !threw && family === 'request' && decoded === rawId;
  })());
ok('T3-4c both in-scope hash-generation call sites encode their interpolated segment (encodeURIComponent), not raw concatenation',
  /'#request\/' \+ encodeURIComponent\(r\.id\)/.test(roadmapJs) &&
  /'#' \+ encodeURIComponent\(t\)/.test(js));
ok('T3-5 landed state = scroll + programmatic focus + a visible highlight class',
  /scrollIntoView/.test(js) && /landing-highlight/.test(js) && /\.focus\(\)/.test(js));
ok('T3-6 an explicit return affordance is injected on the landed item and drives history.back()',
  /landing-return/.test(js) && /history\.back\(\)/.test(js));
ok('T3-7 the miss rule renders a "resolved <when> — <outcome>" banner, never a blank/404',
  /resolved /.test(js) && /miss/i.test(js));
ok('T3-8 a view-registration API exists (tasks 4-5 register into the shell) and roadmap.js registers through it',
  /registerView/.test(js) && /WorkstreamsShell/.test(js) && /registerView\(/.test(roadmapJsNoComments));
ok('T3-8b Back restores the prior view WITH its expansion + scroll (snapshot/restore wired through the router)',
  /snapshotState/.test(js) && /restoreState/.test(js));

// --- tree: six-value chips, progress text, roll-ups (Outcome §2 / C1) ----
ok('T3-10 all six status enum values have a render class + label (not-started/in-progress/merged-unverified/complete/stalled/unknown)',
  ['not-started', 'in-progress', 'merged-unverified', 'complete', 'stalled', 'unknown']
    .every((v) => roadmapJs.indexOf("'" + v + "'") !== -1) && /rm-status-/.test(roadmapJs));
ok('T3-11 status chips render TEXT from the label map (text + color, never color-only)',
  /STATUS_LABEL/.test(roadmapJs) && /textContent/.test(roadmapJs));
ok('T3-12 the merged-unverified label is the distinct operator copy ("merged — deploy unverified"), outside Complete',
  /merged — deploy unverified/.test(roadmapJs));
ok('T3-13 progress bars ALWAYS carry the "n/m" text and are OMITTED for zero-tracked-children items',
  /progress\.done \+ '\/' \+ .*progress\.total|done \+ '\/' \+ /.test(roadmapJs) && /progress\.total/.test(roadmapJsNoComments));
ok('T3-14 the tree is nested native <details>/<summary> disclosure (C9 keyboard baseline)',
  /createElement\('details'\)/.test(roadmapJs) && /createElement\('summary'\)/.test(roadmapJs));
ok('T3-15 roll-up badges render ONE PER attention class present (R4: precedence orders, never selects) in the pinned precedence order',
  /ROLLUP_ORDER/.test(roadmapJs) &&
  /'waiting-on-you',\s*'crashed',\s*'blocked-on',\s*'limit-parked',\s*'unknown'/.test(roadmapJs.replace(/\n\s*/g, ' ')));
ok('T3-16 roll-up badges are counted + labeled real buttons whose click expands the path to the item',
  /rm-rollup-badge/.test(roadmapJs) && /expandPathTo/.test(roadmapJs));
ok('T3-17 CSS shows roll-up badges on COLLAPSED ancestors (hidden when the branch is open — the attention state is never masked while collapsed)',
  /details\[open\][^{]*>\s*summary[^{]*\.rm-rollups[^{]*\{[^}]*display:\s*none/.test(C));

// --- from-your-request links (C6) ----------------------------------------
ok('T3-18 every drill-down carries "from your request(s):" linking via #request/<id>',
  /from your request/.test(roadmapJs) && /#request\//.test(roadmapJs));

// --- recency (I1) + completed aging (round 4 + I2) -----------------------
ok('T3-19 status chips carry their transition age (formatAge on status.since / completed_at)',
  /formatAge/.test(roadmapJs) && /status\.since|completed_at/.test(roadmapJs));
ok('T3-19b transitions <24h old get a non-color-only "new" text marker',
  /rm-new-marker/.test(roadmapJs) && /'new'/.test(roadmapJs));
ok('T3-20 completed aging: in-place window + collapsed-subtree "completed <when>" headline + per-parent "N completed ▸ — latest: <title>" roll-up',
  /completed /.test(roadmapJs) && / completed ▸ — latest: /.test(roadmapJs) && /completed_age_days/.test(roadmapJs));
ok('T3-21 the "added mid-build" insertion marker is a labeled chip aging on the SAME tunable (one knob)',
  /added mid-build/.test(roadmapJs) && /agedOut|completed_age_days/.test(roadmapJs));

// --- kanban (I3 + R5) ----------------------------------------------------
ok('T3-22 kanban toggle is an aria-pressed button and the mode persists (localStorage)',
  /id="roadmapKanbanToggle"/.test(html) && /aria-pressed/.test(roadmapJs) && /roadmap\.viewMode/.test(roadmapJs));
ok('T3-22b kanban cards = TOP-LEVEL items; merged-unverified + unknown are EXCEPTIONAL columns rendered only when non-empty (R5)',
  /KANBAN_COLUMNS/.test(roadmapJs) && /EXCEPTIONAL/.test(roadmapJs));
ok('T3-22c the stalled kanban column is visually distinct via a dedicated class (text label + accent, never color-only)',
  /rm-kanban-col-stalled/.test(C) || /rm-kanban-col-stalled/.test(roadmapJs));

// --- filters: substring box (R6), project chips, chore exclusion (A9) ----
ok('T3-23 the tree ships its at-birth substring filter box (R6: chips are facets, not search)',
  /id="roadmapFilter"/.test(html) && /roadmapFilter/.test(roadmapJs));
ok('T3-23b project chips are aria-pressed toggles and persist (localStorage)',
  /roadmap\.projectChips/.test(roadmapJs) && /aria-pressed/.test(roadmapJs));
ok('T3-24 harness-chore exclusion keys on PROVENANCE (item.provenance), with hidden count + one-click reveal',
  /provenance/.test(roadmapJs) && /harness chores/.test(roadmapJs) && /roadmap\.showChores/.test(roadmapJs));

// --- four UI states (C4) -------------------------------------------------
ok('T3-25 loading state uses the mandated copy ("deriving roadmap…") and aria-busy',
  /deriving roadmap…/.test(roadmapJs) && /aria-busy/.test(roadmapJs));
ok('T3-25b error state = pane-error + Retry, NEVER the empty state on failure',
  /pane-error/.test(roadmapJs) && /Retry/.test(roadmapJs));
ok('T3-25c FILTERED-empty names the filter + hidden count + a one-click clear, distinct from TRUE-empty',
  /no items match/.test(roadmapJs) && /clear/i.test(roadmapJs) && /hidden/.test(roadmapJs));
ok('T3-25d TRUE-empty explains items arrive automatically from sessions (no setup ask)',
  /arrive automatically|appear here automatically/.test(roadmapJs));

// --- refresh model (C7) --------------------------------------------------
ok('T3-26 the view polls on the 30s tick and labels failures "derived <age> — STALE", never silent staleness',
  /30000|REFRESH_INTERVAL/.test(roadmapJs) && /STALE/.test(roadmapJs));
ok('T3-27 re-render is STATE-PRESERVING: open-details set + scroll + focus + uncommitted edits captured and restored',
  /captureUiState/.test(roadmapJs) && /restoreUiState/.test(roadmapJs) &&
  /scrollTop|scrollY/.test(roadmapJs) && /activeElement/.test(roadmapJs));
ok('T3-27c open-but-unfocused title editor (focus moved to the Save button, NOT the input) still has its uncommitted value CAPTURED by captureUiState — the pre-fix focus-gated code returned edit:null here and the 30s tick silently destroyed the editor',
  (function () {
    var r = runCaptureUiState({ activeElement: fakeSaveBtn, openInput: fakeOpenInput });
    return !r.__error && !!r.edit && r.edit.itemId === 'item-42' && r.edit.value === 'uncommitted title text';
  })());
ok('T3-27d open title editor survives capture even when focus has left the pane entirely (activeElement null/outside)',
  (function () {
    var r = runCaptureUiState({ activeElement: null, openInput: fakeOpenInput });
    return !r.__error && !!r.edit && r.edit.itemId === 'item-42';
  })());
ok('T3-27e no open editor in the DOM -> captureUiState.edit stays null (presence-based capture does not false-positive)',
  (function () {
    var r = runCaptureUiState({ activeElement: fakeSaveBtn, openInput: null });
    return !r.__error && r.edit === null;
  })());

// --- title editing + rank reorder (A3 / A7 / R2) -------------------------
ok('T3-28 title editing reuses the todo.js pattern: an explicit Edit button, Escape cancels, focus returns',
  /rm-title-edit|Edit/.test(roadmapJs) && /Escape/.test(roadmapJs) && /\.focus\(\)/.test(roadmapJs));
ok('T3-28b edit feedback is aria-live (C9)', /aria-live/.test(roadmapJs));
ok('T3-29 build-order reorder ships keyboard-operable move up/down REAL buttons (WCAG 2.2 2.5.7 — never drag-only)',
  /[Mm]ove up/.test(roadmapJs) && /[Mm]ove down/.test(roadmapJs) && /\/api\/roadmap\/rank/.test(roadmapJs));

// --- a11y hygiene (C9) ---------------------------------------------------
ok('T3-30 roadmap.js builds interactive controls as real <button>s (the one btn() factory, used throughout) and never wires click onto a bare div',
  /function btn\([\s\S]{0,120}?createElement\('button'\)/.test(roadmapJs) &&
  (roadmapJs.match(/btn\(/g) || []).length >= 10 &&
  !/[Dd]iv\.addEventListener\('click'/.test(roadmapJs));
ok('T3-31 CSS pairs every status class with the palette (stalled uses the --interrupt accent; unknown visibly distinct)',
  /\.rm-status-stalled[^{]*\{[^}]*var\(--interrupt\)/.test(C) &&
  /\.rm-status-unknown[^{]*\{[^}]*var\(--warn\)/.test(C) &&
  /\.rm-status-complete[^{]*\{[^}]*var\(--ok\)/.test(C));
ok('T3-32 landed items are programmatically focusable (tabindex="-1" set on item containers)',
  /tabindex.*-1|tabIndex = -1/.test(roadmapJs));

// ============================================================
// cockpit-roadmap-redesign ROUND-6/7 FOLLOW-ON FIX (T3-33+): the operator's
// live-surface walkthrough (docs/reviews/2026-07-17-cockpit-ux-design-
// input.md, Round 6+7) — text-wall leaves, verbatim-duplicated provenance,
// no immediate collapse for fully-complete nodes, chrome noise, no series
// structure, no paragraph-form ban, no visible task->subtask hierarchy.
// The three PURE (DOM-free) functions below are extracted from roadmap.js
// and REALLY EXECUTED in a `vm` sandbox (the same T3-27b/T6 technique) —
// real behavioral proof, not source-presence regex.
// ============================================================
function extractMarkedBlock(src, beginMarker, endMarker) {
  const bi = src.indexOf(beginMarker);
  const ei = src.indexOf(endMarker);
  if (bi === -1 || ei === -1 || ei < bi) return null;
  return src.slice(bi, ei);
}
function runPure(src, callExpr) {
  if (!src) return { __error: 'extraction anchors missing' };
  const sandbox = {};
  vmMod.createContext(sandbox);
  const code = src + '\nvar __result = (' + callExpr + ');';
  try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
  return sandbox.__result;
}

const provenanceDedupSrc = extractMarkedBlock(roadmapJs, '// PROVENANCE-DEDUP-BEGIN', '// PROVENANCE-DEDUP-END');
const collapseLawSrc = extractMarkedBlock(roadmapJs, '// COLLAPSE-LAW-BEGIN', '// COLLAPSE-LAW-END');
const phaseSeriesSrc = extractMarkedBlock(roadmapJs, '// PHASE-SERIES-BEGIN', '// PHASE-SERIES-END');
ok('T3-33 selftest can locate the PROVENANCE-DEDUP/COLLAPSE-LAW/PHASE-SERIES extraction anchors (source-execution harness precondition)',
  !!provenanceDedupSrc && !!collapseLawSrc && !!phaseSeriesSrc);

// --- gap 2: provenance dedup (real execution) -----------------------------
ok('T3-34 visibleFromRequests SUPPRESSES an entry whose (normalized) title is identical to the item\'s own title — no more self-duplicating "from your request(s)" on an intent\'s own drill-down',
  (function () {
    const r = runPure(provenanceDedupSrc, 'visibleFromRequests({title: "Build the Alpha Feature", from_requests: [{id: "ask-1", title: "  build the alpha feature  "}]})');
    return !r.__error && r.entries.length === 0 && r.allSuppressed === true;
  })());
ok('T3-34b visibleFromRequests keeps a GENUINELY different request title (never over-suppresses)',
  (function () {
    const r = runPure(provenanceDedupSrc, 'visibleFromRequests({title: "task 1: Derived status", from_requests: [{id: "ask-1", title: "Build the alpha feature"}]})');
    return !r.__error && r.entries.length === 1 && r.allSuppressed === false;
  })());
ok('T3-34c visibleFromRequests never reports allSuppressed when from_requests was ALREADY empty (a real "no captured request" case, distinct from an all-duplicate list)',
  (function () {
    const r = runPure(provenanceDedupSrc, 'visibleFromRequests({title: "x", from_requests: []})');
    return !r.__error && r.entries.length === 0 && r.allSuppressed === false;
  })());
ok('T3-35 the drill-down renders the from-requests row conditionally on allSuppressed (never inline-by-default, never a stale fallback when a dup was suppressed)',
  /frInfo\.allSuppressed/.test(roadmapJsNoComments) && /visibleFromRequests\(item\)/.test(roadmapJsNoComments));

// --- gap 3: immediate collapse of a fully-complete node's children --------
ok('T3-36 partitionChildren rolls up EVERY complete child immediately when parentFullyComplete=true, even ones well inside the 7-day "stay visible" window (the 18/18-recently-shipped case)',
  (function () {
    const kids = [
      { status: { value: 'complete' }, completed_at: new Date().toISOString() },
      { status: { value: 'complete' }, completed_at: new Date().toISOString() },
    ];
    const r = runPure(collapseLawSrc, 'partitionChildren(' + JSON.stringify(kids) + ', true, function(){ return false; })');
    return !r.__error && r.live.length === 0 && r.aged.length === 2;
  })());
ok('T3-36b partitionChildren still uses the PER-CHILD 7-day window (agedOutFn) when the parent is NOT fully complete (round-4\'s "recently completed stays in place" for an ACTIVE parent is unchanged)',
  (function () {
    const kids = [{ status: { value: 'complete' }, completed_at: new Date().toISOString() }];
    const r = runPure(collapseLawSrc, 'partitionChildren(' + JSON.stringify(kids) + ', false, function(){ return false; })');
    return !r.__error && r.live.length === 1 && r.aged.length === 0;
  })());
ok('T3-36c partitionChildren never touches a NOT-complete child regardless of parentFullyComplete (only complete children are ever rolled up)',
  (function () {
    const kids = [{ status: { value: 'in-progress' }, completed_at: '' }];
    const r = runPure(collapseLawSrc, 'partitionChildren(' + JSON.stringify(kids) + ', true, function(){ return true; })');
    return !r.__error && r.live.length === 1 && r.aged.length === 0;
  })());
ok('T3-37 renderNode computes parentFullyComplete from THIS item\'s own status (complete implies every child already shipped) and threads it into renderChildList',
  /parentFullyComplete\s*=\s*!!\(item\.status/.test(roadmapJsNoComments) &&
  /renderChildList\(kids, item\.id, parentFullyComplete\)/.test(roadmapJsNoComments));
ok('T3-38 the completed-rollup summary text uses the item\'s (already-distilled) TITLE, never a separate full-text field',
  / completed ▸ — latest: '\s*\+\s*\(aged\[0\]\.title/.test(roadmapJsNoComments));

// --- gap 6: connected phase series for sibling plan nodes -----------------
ok('T3-39 isPhaseSeries/phaseLabel: sibling PLAN children render as a numbered "Phase N of M" series; non-plan children (tasks under a plan, intents at top level) do not',
  (function () {
    const a = runPure(phaseSeriesSrc, 'isPhaseSeries([{kind:"plan"},{kind:"plan"}])');
    const b = runPure(phaseSeriesSrc, 'isPhaseSeries([{kind:"task"},{kind:"task"}])');
    const c = runPure(phaseSeriesSrc, 'isPhaseSeries([])');
    const label = runPure(phaseSeriesSrc, 'phaseLabel(1, 4)');
    return a === true && b === false && c === false && label === 'Phase 2 of 4';
  })());
ok('T3-40 renderChildList wraps a phase-series in a text-labeled connector (.rm-phase-step/.rm-phase-label), never color-only, and CSS draws the connector as an ADDITIVE line (never the only cue)',
  /rm-phase-series/.test(roadmapJsNoComments) && /rm-phase-step/.test(roadmapJsNoComments) &&
  /rm-phase-label/.test(roadmapJsNoComments) &&
  /\.rm-phase-step::before\s*\{[^}]*background:/.test(C) && /\.rm-phase-label\s*\{/.test(C));

// --- gap 4: compact icon chrome, hover/focus-within, never hover-only -----
ok('T3-41 Edit-title/Move-up/Move-down are compact icon buttons (short glyph text) carrying a full aria-label — never bare icons with no accessible name',
  /rm-icon-btn/.test(roadmapJs) && /'✎'/.test(roadmapJs) && /'↑'/.test(roadmapJs) && /'↓'/.test(roadmapJs) &&
  /edit the title of/.test(roadmapJs) && /Move up in build order/.test(roadmapJs) && /Move down in build order/.test(roadmapJs));
ok('T3-42 CSS hides the chrome by default and reveals it on hover OR :focus-within (never hover-only — WCAG 2.2 2.5.7)',
  /\.rm-title-edit,\s*\.rm-item-chrome\s*\{[^}]*opacity:\s*0/.test(C) &&
  /:hover[^{,]*\.rm-title-edit[\s\S]{0,80}:focus-within/.test(C.replace(/\n/g, ' ')));
ok('T3-42b an OPEN title editor stays visible through the whole edit (a JS-toggled class, not hover-state, keeps it shown — a stray mouseout never hides in-progress input/Save/Cancel)',
  /classList\.add\('rm-editing'\)/.test(roadmapJs) && /classList\.remove\('rm-editing'\)/.test(roadmapJs) &&
  /\.rm-title-edit\.rm-editing\s*\{/.test(C));

// --- 7A: no paragraph form anywhere; 7B: visible task->subtask hierarchy -
ok('T3-43 the task drill-down renders lead/subtask/live-agent content as bulleted LISTS (<ul>/<li>), never a single paragraph text blob',
  /createElement\('ul'\)|el\('ul'/.test(roadmapJs) && /rm-lead-points/.test(roadmapJs) && /rm-subtasks/.test(roadmapJs));
ok('T3-44 subtasks render each sub-bullet as its own labeled list item with a distilled title (round 7B: real visible task -> subtask structure, not a flat re-fold)',
  /rm-subtask-title/.test(roadmapJs) && /s\.title/.test(roadmapJs) && /s\.body_points/.test(roadmapJs));
ok('T3-45 currently-running sessions render as live agent leaves with a text status label (never color/glyph-only) under the task they serve (round 7B-i)',
  /rm-agents/.test(roadmapJs) && /aria-hidden/.test(roadmapJs) && /rm-agent-text/.test(roadmapJs) &&
  /AGENT_STATUS_GLYPH/.test(roadmapJs));

// ============================================================
// ROUND 8 (2026-07-21) — the Roadmap RE-ROOTS on PLAN FILES, not the
// ask-registry (docs/reviews/2026-07-17-cockpit-ux-design-input.md, "Round
// 8"). The server-side re-rooting + fixture proof is
// server/roadmap-routes.selftest.js's R8a-c block; these pins cover the
// CLIENT contract: 'intent' kind is gone, the top-level list is now itself
// the phase-series (reusing isPhaseSeries/phaseLabel, never reinvented, per
// the task's own instruction), and the title/rank wire fields are id-keyed
// (a plan slug), not ask_id-keyed.
// ============================================================
ok('R8-1 the "intent" kind is GONE from roadmap.js entirely — the tree roots on plans now, so there is no ask/intent tree level left to gate on',
  !/kind === 'intent'/.test(roadmapJsNoComments) && !/'rm-kind-intent'/.test(roadmapJsNoComments));
ok('R8-2 the compact edit/rank chrome (drilldown) now gates on kind:"plan" — plans are the new top-level, editable/reorderable object',
  /item\.kind === 'plan'/.test(roadmapJsNoComments));
ok('R8-3 renderTree (the TOP-LEVEL list) applies the SAME isPhaseSeries/phaseLabel connector treatment renderChildList already used one level down — reused, not reinvented, and now the top-level phases (round 6: "phase one through four") actually render connected',
  /isPhaseSeries\(live\)/.test(roadmapJsNoComments) &&
  /rm-phase-series/.test(roadmapJsNoComments) && /phaseLabel\(i, live\.length\)/.test(roadmapJsNoComments));
ok('R8-4 the rank-move and title-save wire bodies are id-keyed (a plan slug), not ask_id-keyed (the old ask-rooted contract) — no POST body anywhere still sends ask_id',
  /JSON\.stringify\(\{ id: item\.id, title: t \}\)/.test(roadmapJsNoComments) &&
  /JSON\.stringify\(\{ id: itemId, direction: direction \}\)/.test(roadmapJsNoComments) &&
  !/ask_id: item\.id/.test(roadmapJsNoComments) && !/ask_id: askId/.test(roadmapJsNoComments));
ok('R8-5 the merged-unverified "mark complete anyway" override resolves its ask-lifecycle target via the plan\'s first linked request (from_requests[0]) — never posts a plan slug where an ask id is required',
  /overrideTargetId\s*=\s*\(item\.from_requests/.test(roadmapJsNoComments) &&
  /encodeURIComponent\(overrideTargetId\)/.test(roadmapJsNoComments));
(function () {
  // R8-6: isPhaseSeries/phaseLabel EXECUTION proof at the shape the
  // top-level payload now actually sends (a flat array of plan-kind
  // roots, no wrapping intent) — real execution, not source-presence.
  const a = runPure(phaseSeriesSrc, 'isPhaseSeries([{kind:"plan", id:"demo-plan"},{kind:"plan", id:"redesign-plan"}])');
  ok('R8-6 isPhaseSeries recognizes a top-level plan-rooted list (no intent wrapper) as a phase series',
    a === true);
})();

// GHOST-BOUNDING (2026-07-21 fix, folded into the same round-8 rewiring):
// ask-linked plan slugs whose file cannot be resolved AND whose newest
// link is older than completed_age_days are excluded from the tree
// entirely (real-data proof: 154/164 roots were stale ghosts before this
// fix — server/roadmap-routes.selftest.js's dedicated pins) but named as
// ONE honest aggregate, never a silent drop (C5).
ok('R8-7 renderAll surfaces stale_links_omitted as a single honest count line, never a per-item dead root',
  /stale_links_omitted/.test(roadmapJsNoComments) &&
  /linked plan.*not found/.test(roadmapJsNoComments));

// cockpit-roadmap-redesign Task 7 — person-grouped peers (round 5:
// "Misha: desktop + laptop"). Same PV-prefix, same DOM-free technique;
// the server-side grouping derivation is peer-view.js's own self-test
// (scenarios 16-18); these pin the RENDERER's contract.
// ============================================================

ok('PV-10 renderPeerPersonGroups() exists and is the path renderPeersSection takes when peer data is present',
  /function renderPeerPersonGroups/.test(asksJsNoComments) &&
  /renderPeerPersonGroups\(body, peers\)/.test(asksJsNoComments));

ok('PV-11 the person-group header renders the round-5 literal shape: person + ": " + hosts joined by " + "',
  /g\.person \+ ': ' \+ \(g\.hosts \|\| \[\]\)\.join\(' \+ '\)/.test(asksJsNoComments));

ok('PV-12 an unmapped hostname renders under the literal named "unassigned" group (named state, never a guessed person) — incl. the older-server fallback when persons is absent',
  /'unassigned'/.test(asksJsNoComments));

ok('PV-13 a people_map_error (server-named map failure) renders as visible text NAMING the failing component + remediation, machines degrade to "unassigned" (framing law: system failed, labeled)',
  /peers\.people_map_error/.test(asksJsNoComments) &&
  /config\/people\.json/.test(asksJsNoComments));

ok('PV-14 I3 alternate-view law: person groups are <details> with open-state PERSISTED per person in localStorage (unit-of-card = person; persistence named)',
  /cockpit\.peers\.person\./.test(asksJsNoComments) &&
  /localStorage\.setItem\(storeKey/.test(asksJsNoComments) &&
  /localStorage\.getItem\(storeKey/.test(asksJsNoComments));

ok('PV-15 CSS styles the person group + summary (peer-person-group / peer-person-summary present in app.css)',
  /\.peer-person-group/.test(C) && /\.peer-person-summary/.test(C));

// ============================================================
// cockpit-roadmap-redesign Task 5 — "Requests ledger view" (T5-prefix).
// Same DOM-free source-regex technique as the T3 block above; the REAL
// wiring proof (fixture registry, real HTTP) is
// server/requests-routes.selftest.js. requests.js is read guarded so a
// missing file fails THESE checks instead of crashing the whole suite.
// ============================================================
let requestsJs = '';
try { requestsJs = fs.readFileSync(path.join(D, 'requests.js'), 'utf8'); } catch (_) { /* T5 checks fail honestly below */ }

// T5-1: unlike T13-4/T3's "included by index.html" checks, this task's
// dispatch explicitly excludes direct index.html edits (a shared shell
// file) — the script tag ships as docs/plans/fragments/roadmap-t5-shell-
// fragment.md for the orchestrator to apply at merge (same precedent as
// task 3's server-side fragments). This assertion pins the FRAGMENT's
// content (verifiable NOW, honestly) rather than asserting a live-index.html
// state this task is barred from creating; the fragment's own "Integration
// points" section calls for re-running this exact suite (T5-*) AFTER the
// line lands, at which point a live-DOM check becomes the orchestrator's to
// add if desired.
let shellFragment = '';
try {
  shellFragment = fs.readFileSync(path.join(D, '..', '..', '..', 'docs', 'plans', 'fragments', 'roadmap-t5-shell-fragment.md'), 'utf8');
} catch (_) { /* T5-1 fails honestly below if the fragment is missing */ }
ok('T5-1 the shell fragment pins the exact <script src="/requests.js"> line, ordered AFTER app.js/roadmap.js',
  /<script src="\/requests\.js"><\/script>/.test(shellFragment) &&
  shellFragment.indexOf('<script src="/app.js">') < shellFragment.indexOf('<script src="/requests.js">') &&
  shellFragment.indexOf('<script src="/roadmap.js">') < shellFragment.indexOf('<script src="/requests.js">'));

ok('T5-2 requests.js mounts itself at runtime (no static requests-ledger markup added to index.html) and does not touch asks.js',
  /getElementById\('tabRequestsPanel'\)/.test(requestsJs) && /insertBefore/.test(requestsJs) &&
  !/id="requestsLedgerSection"/.test(html));

ok('T5-3 requests.js registers a "requests" view adapter through the shell API (replacing app.js\'s interim placeholder)',
  /registerView/.test(requestsJs) && /WorkstreamsShell/.test(requestsJs) &&
  /registerView\('requests'/.test(requestsJs.replace(/\s+/g, ' ')));

// --- timeline anatomy (I6): collapsed one-liner + oldest-first expanded chronology ---
ok('T5-4 the collapsed one-liner distinguishes "became → <plan>" (closed/promoted) from "open, amended <age>"',
  /became → /.test(requestsJs) && /open, amended /.test(requestsJs) && /open, registered /.test(requestsJs));
ok('T5-5 the expanded timeline renders each event type distinctly (origin/promoted/amendment/etc. each own a dedicated CSS hook), trusting the server\'s oldest-first order (no client re-sort or reverse)',
  /rl-event-'\s*\+\s*ev\.type/.test(requestsJs) && /'promoted'/.test(requestsJs) &&
  /\.rl-event-origin/.test(C) && /\.rl-event-promoted/.test(C) &&
  !/timeline[\s\S]{0,40}\.reverse\(\)/.test(requestsJs));
ok('T5-6 amendment rows carry a Detach affordance (I6 correction) that posts to the pinned endpoint',
  /Detach/.test(requestsJs) && /\/api\/requests\/amend\/detach/.test(requestsJs) && /detachable/.test(requestsJs));
ok('T5-6b a missing detach verb surfaces a NAMED error in the row\'s aria-live feedback, never a silent success',
  /rl-event-feedback/.test(requestsJs) && /aria-live/.test(requestsJs) &&
  /Could not detach this amendment/.test(requestsJs));

// --- "became →" cross-view arrow (C6 reciprocal law, C2 shell rules) ---
ok('T5-7 "became →" links use #roadmap/<id> addressing via the shell\'s navigate()',
  /#roadmap\/'\s*\+\s*item\.id/.test(requestsJs.replace(/\n\s*/g, ' ')) && /shell\.navigate/.test(requestsJs));

// --- findability (C8): substring filter box + age-grouped closed requests ---
ok('T5-8 a substring filter box matches title + distilled intent + verbatim origin',
  /filterInput\.id = 'requestsFilter'/.test(requestsJs) && /distilled_intent/.test(requestsJs) && /verbatim_ref/.test(requestsJs));
ok('T5-9 closed requests are grouped into "this week / this month / older" (default-collapsed) and search reaches inside',
  /this week/.test(requestsJs) && /this month/.test(requestsJs) && /'older'/.test(requestsJs) &&
  /rl-age-group/.test(requestsJs));
ok('T5-9b an age group with zero items is never rendered as an expanded empty shell',
  /if \(!groupItems\.length\) return/.test(requestsJs));

// --- recency (I1) ---
ok('T5-10 every row carries "last amended <age>", with an honest fallback when never amended',
  /last amended /.test(requestsJs) && /no amendments yet/.test(requestsJs) && /formatAge/.test(requestsJs));

// --- title editing (A3: ALWAYS operator-editable) ---
ok('T5-11 title editing reuses the todo.js/roadmap.js pattern: an explicit Edit button, Escape cancels, focus returns',
  /rl-edit-btn/.test(requestsJs) && /Escape/.test(requestsJs) && /\.focus\(\)/.test(requestsJs) &&
  /\/api\/requests\/title/.test(requestsJs));

// --- four UI states (C4) ---
ok('T5-12 loading state is an honest, distinct copy with aria-busy',
  /loading requests…/.test(requestsJs) && /aria-busy/.test(requestsJs));
ok('T5-12b error state = pane-error + Retry, NEVER the empty state on failure',
  /pane-error/.test(requestsJs) && /Retry/.test(requestsJs));
ok('T5-12c FILTERED-empty names the filter substring + a one-click clear, distinct from TRUE-empty',
  /no requests match/.test(requestsJs) && /clear filter/.test(requestsJs));
ok('T5-12d TRUE-empty explains requests arrive automatically (no setup ask)',
  /appear here automatically/.test(requestsJs));

// --- refresh model (C7, task-3 law extended here) ---
ok('T5-13 the view polls on the 30s tick and labels failures "derived <age> — STALE", never silent staleness',
  /30000|REFRESH_INTERVAL/.test(requestsJs) && /STALE/.test(requestsJs));
ok('T5-13b re-render is STATE-PRESERVING: open-details set + scroll + focus + uncommitted title edit captured and restored',
  /captureUiState/.test(requestsJs) && /restoreUiState/.test(requestsJs) &&
  /scrollY/.test(requestsJs) && /activeElement/.test(requestsJs));

// --- cross-view landing (C2): shared shell contract ---
ok('T5-14 the adapter implements landOn/missInfo/snapshotState/restoreState (the same shell contract roadmap.js implements)',
  /landOn:/.test(requestsJs) && /missInfo:/.test(requestsJs) &&
  /snapshotState:/.test(requestsJs) && /restoreState:/.test(requestsJs));

// --- a11y hygiene (C9) ---
ok('T5-15 requests.js builds interactive controls as real <button>s (the one btn() factory) and never wires click onto a bare div',
  /function btn\([\s\S]{0,120}?createElement\('button'\)/.test(requestsJs) &&
  (requestsJs.match(/btn\(/g) || []).length >= 8 &&
  !/[Dd]iv\.addEventListener\('click'/.test(requestsJs));
ok('T5-16 the tree/rows use nested native <details>/<summary> disclosure (C9 keyboard baseline)',
  /createElement\('details'\)/.test(requestsJs) && /createElement\('summary'\)/.test(requestsJs));
ok('T5-17 edit/detach feedback rows are aria-live (C9)', (requestsJs.match(/aria-live/g) || []).length >= 2);
ok('T5-18 landed rows are programmatically focusable (tabindex="-1" set on row containers)',
  /tabIndex = -1/.test(requestsJs));
// cockpit-roadmap-redesign Task 8 — "UI polish absorbed" (the four operator
// items folded from the superseded cockpit-ui-polish.md, PLUS item 5, the
// standalone My-To-Do pane retirement (A10) — held back in an earlier pass
// of this task because task 4's Inbox "My items" section (its replacement
// destination) had not landed yet; task 4 has since landed and item 5 is
// completed here: #todoSection/#todoBody/#todoCount markup and the
// <script src="/todo.js"> tag are removed from index.html, todo.js is
// salvaged (git mv, never deleted) to attic/todo.js, and its operator/
// pointer item rendering + interactions live on in inbox.js's "My items"
// section — new assertions T8-15 onward, below the resize/backlog/
// description/Artifacts items this task already shipped).
// ============================================================

// --- item 1: resizable + independently scrollable panes -------------------
ok('T8-1 the column resize handle still exists in the DOM as an ARIA "window splitter" separator (role=separator, keyboard-focusable); the row handle is RETIRED alongside the standalone My-To-Do pane it used to split against Backlog (item 5 below) — nothing remains for it to split, so it is gone rather than left as a dead, non-functional control',
  /id="colResizeHandle"[^>]*role="separator"[^>]*tabindex="0"/.test(html) &&
  !/id="rowResizeHandle"/.test(html));
ok('T8-2 the resize feature is wired as its OWN additive IIFE in app.js (non-overlapping with the tab-router IIFE above it)',
  /function setupHandle/.test(js) && (js.match(/\(function \(\) \{/g) || []).length >= 2);
ok('T8-3 pointer drag is wired (pointerdown/pointermove + setPointerCapture) for the primary drag-resize interaction',
  /pointerdown/.test(js) && /pointermove/.test(js) && /setPointerCapture/.test(js));
ok('T8-4 a11y: resize is KEYBOARD-OPERABLE (arrow keys step + Home/End jump to min/max) — no pointer-only exception needed (WCAG 2.2 SC 2.5.7, same law as roadmap_rank reorder)',
  /ArrowLeft/.test(js) && /ArrowRight/.test(js) && /ArrowUp/.test(js) && /ArrowDown/.test(js) &&
  /e\.key === 'Home'/.test(js) && /e\.key === 'End'/.test(js));
ok('T8-5 resize state PERSISTS across reloads via localStorage, keyed distinctly per handle',
  /localStorage\.setItem\(key/.test(js) && /localStorage\.getItem\(key/.test(js) &&
  /cockpit\.paneResize\.sidebarWidthPx/.test(js) && /cockpit\.paneResize\.todoHeightPx/.test(js));
// REGRESSION LOCK (live-browser-caught): the target lives inside the
// Requests tab, hidden by default (Roadmap lands first, C2) — measuring
// the baseline size ONCE at setup time froze a bogus 0-clamped-to-min
// value every later interaction jumped from. Every interaction must
// re-measure fresh instead of trusting a cached baseline.
ok('T8-5b REGRESSION LOCK: no interaction trusts a setup-time-cached baseline — every commit re-measures fresh (currentSize(), never a stale closured "current")',
  /function currentSize\(\)/.test(js) && (js.match(/currentSize\(\)/g) || []).length >= 3 &&
  !/startVal = current;/.test(js) && !/commit\(current \+/.test(js));
ok('T8-5c a11y: aria-valuenow refreshes to the REAL current size on focus (not just after a value-changing action) — correct even if the target started on a hidden tab',
  /addEventListener\('focus'/.test(js) && /aria-valuenow', String\(Math\.round\(currentSize\(\)\)\)/.test(js));
ok('T8-6 REGRESSION LOCK: the todo-clip BUGFIX guard (`.sidebar > .pane { flex-shrink: 0 }`) survives this task untouched',
  /\.sidebar > \.pane\s*\{\s*flex-shrink:\s*0;?\s*\}/.test(C));
ok('T8-7 each resizable pane body gets independent scroll (overflow-y:auto) with a min-height floor so it is never fully collapsed',
  /\.todo-section \.pane-body,\s*\.backlog-section \.pane-body\s*\{[^}]*overflow-y:\s*auto[^}]*min-height/.test(C.replace(/\s+/g, ' ')));
(function () {
  var mediaIdx = C.indexOf('max-width: 1200px');
  var handleIdx = C.indexOf('.resize-handle-col');
  ok('T8-8 the column handle hides at the existing <1200px stacked breakpoint (stacking makes the column split meaningless; the row handle stays)',
    mediaIdx !== -1 && handleIdx !== -1 && handleIdx > mediaIdx && (handleIdx - mediaIdx) < 400 &&
    /\.resize-handle-col\s*\{\s*display:\s*none/.test(C));
})();

// --- item 2: compact, expandable backlog rows ------------------------------
ok('T8-9 open backlog rows render as a native <details> (collapsed by default — never given .open = true), matching this codebase\'s established keyboard-a11y disclosure convention',
  /createElement\('details'\)/.test(backlogJs) && !/wrap\.open\s*=\s*true/.test(backlogJs));
ok('T8-10 the collapsed summary is ONE line carrying id + title + tier + age',
  /backlog-row-summary-title/.test(backlogJs) && /backlog-row-summary-meta/.test(backlogJs));
ok('T8-11 disposition action buttons live INSIDE the expanded body only (appended to the detail wrapper, not the collapsed <details> root)',
  /detail\.appendChild\(actions\)/.test(backlogJs) && /detail\.className = 'backlog-row-detail'/.test(backlogJs));
ok('T8-11b "N more" per-tier overflow notice preserved',
  /backlog-tier-more/.test(backlogJs));
// REGRESSION LOCK (live-browser-caught during this task's build, same
// [hidden]-override footgun class R21 already locks for modals/docsPanel):
// `.backlog-row-detail`'s own `display: flex` beats the UA stylesheet's
// `details:not([open]) > *:not(summary) { display: none }` rule at higher
// specificity, so the collapsed row's body (incl. disposition buttons)
// rendered VISIBLE despite `open` being false — the one browser-only
// failure mode this DOM-free suite cannot see on its own without this
// explicit CSS-selector pin.
ok('T8-11c REGRESSION LOCK: a `:not([open])` override forces the detail body hidden while the <details> is closed (the collapsed-by-default guarantee actually holds in a real browser, not just in the JS/HTML source)',
  /\.backlog-row:not\(\[open\]\)\s*>\s*\.backlog-row-detail\s*\{\s*display:\s*none/.test(C));

// --- item 3: task descriptions rendered + de-duplicated plan links --------
ok('T8-12 per-task rows in the plan drill-down render each task\'s DESCRIPTION text',
  /ask-task-desc/.test(asksJs) && /t\.description/.test(asksJs));
ok('T8-12b a long description gets a native details clamp+expand (this codebase\'s established disclosure pattern), a short one renders plain',
  /ask-task-desc-details/.test(asksJs) && /ask-task-desc-summary/.test(asksJs) && /ask-task-desc-full/.test(asksJs));
ok('T8-13 exactly ONE per-plan "View live plan doc" link (ask-plan-doc-link) inside renderPlanBlock — no second, per-task plan-path link exists anywhere in the drill-down render path (peer-plan-doc-link, the unrelated peers-section link, is a DIFFERENT class and correctly excluded)',
  (asksJsNoComments.match(/ask-plan-doc-link/g) || []).length === 1 &&
  !/ask-task-row[\s\S]{0,400}ask-plan-doc-link/.test(asksJsNoComments));

// --- item 4: Artifacts section removed -------------------------------------
ok('T8-14 the Artifacts drill-down section is fully removed (no renderArtifact() call site, no ask-artifacts-section, no "Artifacts" header)',
  !/renderArtifact\(/.test(asksJsNoComments) &&
  !/ask-artifacts-section/.test(asksJsNoComments) &&
  !/artHead\.textContent = 'Artifacts'/.test(asksJsNoComments));

// --- item 5: standalone My-To-Do pane REMOVED (A10) ------------------------
ok('T8-15 the standalone My-To-Do pane markup (#todoSection/#todoBody/#todoCount) is fully REMOVED from index.html',
  !/id="todoSection"/.test(html) && !/id="todoBody"/.test(html) && !/id="todoCount"/.test(html));
ok('T8-16 the standalone <script src="/todo.js"> tag is REMOVED from index.html',
  !/<script src="\/todo\.js">/.test(html));
ok('T8-17 todo.js was salvaged to attic/todo.js (git mv), never deleted — the retired module still exists on disk for history',
  fs.existsSync(path.join(D, '..', 'attic', 'todo.js')));
ok('T8-18 inbox.js\'s "My items" section is the operator-authored items\' new home: it calls the SAME /api/todo endpoints (GET on load + POST toggle/edit/add/pointer_override), never a new parallel store',
  /fetch\('\/api\/todo'\)/.test(inboxJs) && /action: 'toggle'/.test(inboxJs) &&
  /action: 'edit'/.test(inboxJs) && /action: 'add'/.test(inboxJs) && /action: 'pointer_override'/.test(inboxJs));
ok('T8-19 "My items" respects the noise_flag marker convention (server respec 2026-07-19) — renders a marker, never hides the flagged content',
  /item\.noise_flag/.test(inboxJs) && /quotes internal identifiers/.test(inboxJs));
ok('T8-20 "My items" is rendered in its OWN persistent subtree (myItemsWrap), structurally separate from the Inbox\'s own poll-wiped subtree (inboxSectionsWrap) — renderAll()/renderLoadingState()/renderErrorState() only ever wipe inboxSectionsWrap; the My-items renderers only ever wipe myItemsWrap',
  /var myItemsWrap = document\.createElement/.test(inboxJs) && /var inboxSectionsWrap = document\.createElement/.test(inboxJs) &&
  (inboxJs.match(/inboxSectionsWrap\.innerHTML = ''/g) || []).length >= 3 &&
  (inboxJs.match(/myItemsWrap\.innerHTML = ''/g) || []).length >= 3 &&
  !/function renderAll\(\)[\s\S]{0,900}myItemsWrap\.innerHTML/.test(inboxJs) &&
  !/function loadMyItems\(\)[\s\S]{0,50}inboxSectionsWrap\.innerHTML/.test(inboxJs));

// ============================================================
// cockpit-roadmap-redesign Task 4 — "Inbox view + context contract
// enforcement" (T4-prefix). Same DOM-free source-regex technique as the
// T3/T5 blocks above; the REAL wiring proof (fixture ledger, real HTTP) is
// server/inbox-routes.selftest.js + server/auditor.js --self-test.
// inbox.js is read guarded (see the declaration above, ahead of T3-3) so a
// missing file fails these checks instead of crashing the whole suite.
// ============================================================
let needsYouSh = '';
try { needsYouSh = fs.readFileSync(path.join(D, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'needs-you.sh'), 'utf8'); } catch (_) { /* T4-13/14 fail honestly below */ }
let sessionHonestyGateSh = '';
try { sessionHonestyGateSh = fs.readFileSync(path.join(D, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'session-honesty-gate.sh'), 'utf8'); } catch (_) {}
let sessionResumerSh = '';
try { sessionResumerSh = fs.readFileSync(path.join(D, '..', '..', '..', 'adapters', 'claude-code', 'scripts', 'session-resumer.sh'), 'utf8'); } catch (_) {}
let stopVerdictDispatcherSh = '';
try { stopVerdictDispatcherSh = fs.readFileSync(path.join(D, '..', '..', '..', 'adapters', 'claude-code', 'hooks', 'stop-verdict-dispatcher.sh'), 'utf8'); } catch (_) {}
let inboxRoutesJs = '';
try { inboxRoutesJs = fs.readFileSync(path.join(D, '..', 'server', 'inbox-routes.js'), 'utf8'); } catch (_) {}
let auditorJs = '';
try { auditorJs = fs.readFileSync(path.join(D, '..', 'server', 'auditor.js'), 'utf8'); } catch (_) {}
let inboxShellFragment = '';
try { inboxShellFragment = fs.readFileSync(path.join(D, '..', '..', '..', 'docs', 'plans', 'fragments', 'roadmap-t4-shell-fragment.md'), 'utf8'); } catch (_) {}
let inboxServerFragment = '';
try { inboxServerFragment = fs.readFileSync(path.join(D, '..', '..', '..', 'docs', 'plans', 'fragments', 'roadmap-t4-server-fragment.md'), 'utf8'); } catch (_) {}

// T4-1: shell fragment (index.html is a shared shell file — same
// fragment-not-direct-edit precedent as T5-1) pins the exact new script
// line, ordered after app.js/roadmap.js.
ok('T4-1 the shell fragment pins the exact <script src="/inbox.js"> line, ordered AFTER app.js/roadmap.js',
  /<script src="\/inbox\.js"><\/script>/.test(inboxShellFragment) &&
  inboxShellFragment.indexOf('<script src="/app.js">') < inboxShellFragment.indexOf('<script src="/inbox.js">') &&
  inboxShellFragment.indexOf('<script src="/roadmap.js">') < inboxShellFragment.indexOf('<script src="/inbox.js">'));

// T4-2: UNLIKE requests.js/roadmap.js, inbox.js binds to task 3's EXISTING
// static markup (no NEW wrapper subtree inserted) — the tab already ships
// #inboxSection/#inboxBody/#inboxMissBanner.
ok('T4-2 inbox.js binds to the EXISTING static #inboxBody/#inboxTabCount markup (no new wrapper subtree inserted, unlike requests.js)',
  /getElementById\('inboxBody'\)/.test(inboxJs) && /\$\('inboxTabCount'\)/.test(inboxJs) &&
  !/insertBefore/.test(inboxJs));

// T4-3: registers 'inbox' via the shell API; app.js's interim adapter was
// REMOVED (not merely overridden) — its own independently-polled count
// timer would otherwise race inbox.js's (A10: "the two counts can never
// disagree").
ok('T4-3 inbox.js registers an "inbox" view adapter through the shell API',
  /registerView/.test(inboxJs) && /WorkstreamsShell/.test(inboxJs) &&
  /registerView\('inbox'/.test(inboxJs.replace(/\s+/g, ' ')));
ok('T4-3b app.js\'s interim Inbox renderer/count-timer was REMOVED (not left running to race inbox.js — A10 "counts can never disagree")',
  !/function answerableOf/.test(js) && !/function renderInboxInterim/.test(js) && !/loadInbox\(\);/.test(js));

// T4-4: server fragment pins the mount line.
ok('T4-4 the server fragment pins the exact server.js mount line for inbox-routes.js',
  /require\('\.\/inbox-routes\.js'\)/.test(inboxServerFragment) && /inboxRoutes\.handle\(req, res\)/.test(inboxServerFragment));

// --- CONTEXT CONTRACT (I4/A8): a context-less item cannot render answerable ---
ok('T4-5 the server pre-splits answerable/quarantined (no second heuristic client-side) — inbox-routes.js keys quarantine on lint_warnings, decision-section, open state only',
  /lint_warnings/.test(inboxRoutesJs) && /section !== .decision./.test(inboxRoutesJs.replace(/'/g, '.')) || /it\.section === 'decision'/.test(inboxRoutesJs));
ok('T4-5b inflight/decided sections are excluded ENTIRELY from the Inbox (never answerable, never quarantined) — needs-you.sh\'s own "waiting on the operator" scoping applied client-server',
  /'decision' && it\.section !== 'question'/.test(inboxRoutesJs.replace(/\s+/g, ' ')));
ok('T4-5c question items are NEVER quarantined (the lint is decision-only, T25 in needs-you.sh) — the server\'s quarantine test requires section === decision',
  /lintWarnings\.length > 0/.test(inboxRoutesJs) && /it\.section === 'decision' && lintWarnings\.length > 0/.test(inboxRoutesJs));

// --- item anatomy (I5) — collapsed row ---
ok('T4-6 collapsed row anatomy: type glyph+label, one imperative ask sentence, source chip, age',
  /typeGlyph/.test(inboxJs) && /typeLabel/.test(inboxJs) && /ib-ask-text/.test(inboxJs) &&
  /ib-source-chip/.test(inboxJs) && /formatAge\(item\.created_at\)/.test(inboxJs));
ok('T4-6b "blocks: <item>" only renders when the server actually names a roadmap id (never fabricated — HONEST LIMIT)',
  /if \(item\.blocks_roadmap_id\)/.test(inboxJs) && /blocks_roadmap_id: null/.test(inboxRoutesJs));

// --- expanded anatomy (constitution §3 compact format) ---
ok('T4-7 expanded anatomy renders all five §3 steps: Decision/Action needed, Context, Trade-offs table, My pick, Reply-with',
  /Decision needed: |Question: /.test(inboxJs) && /ib-context/.test(inboxJs) && /optionsTable/.test(inboxJs) &&
  /My pick: /.test(inboxJs) && /How to answer: /.test(inboxJs));
ok('T4-7b the trade-offs table parser + the reply stub are server-derived (parseDecisionAnatomy) and client-rendered, never a second parse',
  /parseDecisionAnatomy/.test(inboxRoutesJs) && /reply_stub/.test(inboxRoutesJs) && /reply_stub/.test(inboxJs));
ok('T4-7c the ANSWER lifecycle (C3a) is pointer + copyable stub (v1) — a Copy button, never inline answer submission to the ledger',
  /ib-copy-btn/.test(inboxJs) && !/\/api\/inbox\/answer/.test(inboxJs));

// --- quarantine (I4/A8) — system-failure framing ---
ok('T4-8 quarantine framing blames the SYSTEM, never the operator, and names what the system DOES know (lint_reasons)',
  /could not classify this as answerable/.test(inboxJs) && /ib-lint-reasons/.test(inboxJs) && /lint_reasons/.test(inboxJs));
ok('T4-8b the auto-defect line is HONEST about whether filing has actually happened yet (never claims "filed" before the auditor cycle runs)',
  /defect_filed[\s\S]{0,40}\?[\s\S]{0,80}has been filed/.test(inboxJs.replace(/\n\s*/g, ' ')) &&
  /will be filed at the next background audit cycle/.test(inboxJs));
ok('T4-8c "open source session" escape hatch is a copyable claude --resume command when a session is known, an honest no-session line otherwise (never a dead affordance)',
  /claude --resume /.test(inboxRoutesJs) && /has_session/.test(inboxJs) && /nothing to resume/.test(inboxJs));
ok('T4-8d every quarantined row still carries the SAME dismiss (RESOLVE) affordance as an answerable row — one lifecycle, two buckets',
  /ib-dismiss-btn/.test(inboxJs) && /isQuarantined[\s\S]{0,300}quarantineExtra/.test(inboxJs.replace(/\n\s*/g, ' ')));

// --- win state (C4, delta R1) ---
ok('T4-9 the win state is SCOPED to the answerable section only — a non-empty quarantine section renders independently below it, never defeating the win',
  /answerable\.length === 0/.test(inboxJs) && /quarantined\.length > 0/.test(inboxJs) &&
  /Nothing waiting on you/.test(inboxJs));

// --- four UI states (C4) ---
ok('T4-10 loading/error states are honest and distinct, error NEVER degrades to the win/empty state',
  /deriving your inbox…/.test(inboxJs) && /pane-error/.test(inboxJs) && /Retry/.test(inboxJs) &&
  /if \(!lastPayload\) renderErrorState/.test(inboxJs));

// --- refresh model (C7) ---
ok('T4-11 the view polls on the 30s tick and labels failures "derived <age> — STALE", never silent staleness',
  /30000|REFRESH_INTERVAL/.test(inboxJs) && /STALE/.test(inboxJs));
ok('T4-11b re-render is STATE-PRESERVING: open-details sets (BOTH sections) + scroll + focus captured and restored',
  /captureUiState/.test(inboxJs) && /restoreUiState/.test(inboxJs) && /openSetQ/.test(inboxJs) &&
  /scrollY/.test(inboxJs) && /activeElement/.test(inboxJs));
ok('T4-11c an uncommitted reply-stub edit survives a poll tick (typed-but-not-copied text is not silently destroyed)',
  /replyEdits\[item\.id\] = input\.value/.test(inboxJs) && /hasOwnProperty\.call\(replyEdits, item\.id\)/.test(inboxJs));

// --- cross-view landing (C2): shared shell contract ---
ok('T4-12 the adapter implements landOn/missInfo/snapshotState/restoreState (the same shell contract roadmap.js/requests.js implement)',
  /landOn:/.test(inboxJs) && /missInfo:/.test(inboxJs) &&
  /snapshotState:/.test(inboxJs) && /restoreState:/.test(inboxJs));
ok('T4-12b a followed link to a resolved/gone item renders an honest "resolved earlier" line, never blank (C3 STALE-LINK)',
  /resolved earlier/.test(inboxJs));

// --- Lint promotion (A1): interactive BLOCK vs mechanical STORE-AND-QUARANTINE ---
ok('T4-13 needs-you.sh: a --section decision lint failure BLOCKS (die, non-zero, nothing written) on the interactive path',
  /--mechanical\) mechanical=1/.test(needsYouSh) && /cold-reader lint BLOCKED this add/.test(needsYouSh));
ok('T4-13b mechanical callers (--mechanical) STORE-AND-QUARANTINE instead — never rejected, still exit 0',
  /MECHANICAL caller, stored \+ quarantined, never rejected/.test(needsYouSh));
ok('T4-13c constitution §10 compliance is recorded in needs-you.sh: golden scenario + expected FP rate + retirement condition',
  /GOLDEN SCENARIO/.test(needsYouSh) && /EXPECTED FALSE-POSITIVE RATE/.test(needsYouSh) && /RETIREMENT CONDITION/.test(needsYouSh));
ok('T4-14 every named mechanical caller (stop-verdict-dispatcher.sh, session-resumer.sh park, session-honesty-gate.sh PAUSING) passes --mechanical',
  /--mechanical/.test(stopVerdictDispatcherSh) && /--mechanical/.test(sessionResumerSh) && /--mechanical/.test(sessionHonestyGateSh));

// --- A8: auditor-cycle-only auto-defect filing (never on render) ---
ok('T4-15 the auditor files the quarantine auto-defect in its OWN cycle only (never in inbox-routes.js, which only READS whether one has been filed)',
  /fileNeedsYouQuarantineDefects/.test(auditorJs) && !/fileNeedsYouQuarantineDefects|runCli\(/.test(inboxRoutesJs) &&
  /readAuditorFiledIds/.test(inboxRoutesJs));
ok('T4-15b quarantine defects are keyed by ledger item id and reuse the SAME filed-once + recurrence-escalation state fileNlIssueDivergences already maintains',
  /'quarantine-' \+ item\.id/.test(auditorJs) && /loadNlIssueState\(statePath\)/.test(auditorJs) &&
  (auditorJs.match(/loadNlIssueState\(statePath\)/g) || []).length >= 2);
ok('T4-15c legacy no-producer items (no session) still file — keyed against the ledger id, never dropped',
  /unknown\/legacy producer/.test(auditorJs));

// --- a11y hygiene (C9) ---
ok('T4-16 inbox.js builds interactive controls as real <button>s (the one btn() factory) and never wires click onto a bare div',
  /function btn\([\s\S]{0,120}?createElement\('button'\)/.test(inboxJs) &&
  (inboxJs.match(/btn\(/g) || []).length >= 6 &&
  !/[Dd]iv\.addEventListener\('click'/.test(inboxJs));
ok('T4-16b rows use nested native <details>/<summary> disclosure (C9 keyboard baseline)',
  /createElement\('details'\)/.test(inboxJs));
ok('T4-16c write/copy feedback is aria-live (C9)', (inboxJs.match(/aria-live/g) || []).length >= 1);
ok('T4-16d landed rows are programmatically focusable (tabindex="-1"/tabIndex = -1 set on row containers)',
  /tabIndex = -1/.test(inboxJs));
ok('T4-16e every status/type signal is text + color, never color-only (type glyph carries a TEXT label chip alongside the glyph)',
  /typeLabel\(item\.kind\)/.test(inboxJs));

// --- "My items" (A10) — built here (task 8 item 5, the standalone pane's
// replacement destination; see file header) ---
ok('T4-17 inbox.js DOES build a "My items" section from /api/todo (A10 — task 8 relocated the retired standalone pane\'s content here), reusing the SAME endpoints the pane always used, never a new parallel store',
  /fetch\('\/api\/todo'\)/.test(inboxJs) && /My items/.test(inboxJs) && /function loadMyItems/.test(inboxJs));
ok('T4-18 "My items" rows are EXCLUDED from the Inbox (N) tab count — the one functional setTabCount() call site passes the /api/inbox `answerable` length; no call site anywhere derives it from /api/todo data',
  /setTabCount\(answerable\.length\)/.test(inboxJs) &&
  !/setTabCount\([^)]*(?:todo|operatorItems|pointerItems|openCount)/i.test(inboxJs));
ok('T4-19 "My items" preserves the retired pane\'s FULL interaction set: checkbox toggle, inline edit (Edit/Save/Cancel + Escape), the always-visible add form, and the pointer item\'s operator-override escape hatch — same POST verbs the pane always used',
  /action: 'toggle', index: item\.index/.test(inboxJs) && /action: 'edit', index: item\.index/.test(inboxJs) &&
  /action: 'add', text: text/.test(inboxJs) && /action: 'pointer_override'/.test(inboxJs) &&
  /e\.key === 'Escape'/.test(inboxJs));
ok('T4-20 "My items" is loaded ONCE at boot + after every write, deliberately NOT on the Inbox\'s 30s poll (so an in-progress edit is never destroyed by an unrelated tick) — the same load-once-then-reload-on-write discipline the retired pane used',
  /loadMyItems\(\);/.test(inboxJs) && !/setInterval\(function \(\) \{ loadMyItems/.test(inboxJs));

console.log('');
console.log('self-test summary: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
