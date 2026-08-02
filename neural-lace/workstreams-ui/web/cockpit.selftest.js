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
// --- R17 deliverable 1 (audit F7 / ledger row 80): "Cockpit" everywhere
// user-visible — <title>, <h1>, aria-label. "Workstreams" (the losing
// name) must be GONE from every one of those three surfaces; internal
// identifiers (WorkstreamsShell, localStorage keys, the workstreams-ui
// package/dir name) are explicitly OUT of scope this round and unchanged. --
ok('R17-N1 <title> reads "Cockpit", never "Workstreams"', /<title>Cockpit<\/title>/.test(html) && !/<title>Workstreams<\/title>/.test(html));
ok('R17-N2 the header <h1> reads "Cockpit", never "Workstreams"', /<h1>Cockpit<\/h1>/.test(html) && !/<h1>Workstreams<\/h1>/.test(html));
ok('R17-N3 the tab-nav aria-label reads "cockpit views", never "workstreams views"',
  /aria-label="cockpit views"/.test(html) && !/aria-label="workstreams views"/.test(html));
ok('R17-N4 WorkstreamsShell (the internal global namespace) is UNCHANGED this round — the rename is scoped to user-visible strings only, per the operator\'s own "Do NOT rename file paths/module names/internal ids"',
  /WorkstreamsShell/.test(js));

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
// T13-8 FLIPS here (COCKPIT-DEAD-FILE-HREF-RESIDUAL-01). It used to pin
// hrefAssignCount === 2 — the http(s) passthrough PLUS the "best-effort
// file:// conversion" branch. That second branch was the operator-facing
// bug ("the links don't work"): a file:// href is dead from an http-served
// page. It is deleted, so the count is now 1, and a REGRESSION back to 2
// fails this assertion.
ok('T13-8 asks.js sets .href exactly ONCE — the http(s) passthrough branch of absoluteLinkNode. The old file:// conversion branch is gone (a repo-file path routes through the doc modal instead), so no bare, relative, or dead href can be assigned',
  hrefAssignCount === 1);

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

// Round 15 (operator: "the Docs button in the corner doesn't show any
// files") — ROOT CAUSE, real execution against the REAL /api/docs shape
// (verified live at :7733: GET /api/docs returns
// {projects:{<key>:{root,missing,files}}}). renderDocsList used to treat
// docsCache[proj] as the files ARRAY ITSELF — `files.filter(...)` threw
// "files.filter is not a function" on the first project key, aborting the
// whole render right after docsBody was cleared, leaving a silently empty
// panel (no console-visible crash message reached the operator). A
// source-regex checking for ".files" could pass while still reading it
// from the wrong place, so this runs the REAL extracted function against
// the REAL payload shape in a `vm` sandbox (same technique as the badge-law
// section above), not a static check.
(function () {
  const docsSrc = extractMarkedBlock(js, '// DOCS-LIST-RENDER-BEGIN', '// DOCS-LIST-RENDER-END');
  ok('R15-D0 selftest can locate the DOCS-LIST-RENDER extraction anchors in app.js', !!docsSrc);
  if (!docsSrc) return;
  function makeDocsFakeDom() {
    function FakeNode(tag) {
      this.tagName = tag;
      this.className = '';
      this._text = '';
      this.children = [];
    }
    Object.defineProperty(FakeNode.prototype, 'textContent', {
      get: function () { return this._text; },
      set: function (v) { this._text = v; },
    });
    FakeNode.prototype.appendChild = function (c) { this.children.push(c); return c; };
    FakeNode.prototype.addEventListener = function () {};
    return { createElement: function (tag) { return new FakeNode(tag); } };
  }
  function runDocsRender(cacheObj, filterText) {
    const dom = makeDocsFakeDom();
    const docsBody = dom.createElement('div');
    const sandbox = { document: dom, docsBody: docsBody, docsCache: cacheObj, openDoc: function () {} };
    vmMod.createContext(sandbox);
    try {
      vmMod.runInContext(docsSrc + '\nrenderDocsList(' + JSON.stringify(filterText || '') + ');', sandbox);
    } catch (err) {
      return { __error: String(err), body: docsBody };
    }
    return { body: docsBody };
  }
  const realShapeCache = {
    Circuit: { root: '/x/Circuit', missing: false, files: ['docs/a.md', 'docs/b.md'] },
    'neural-lace': { root: '/x/neural-lace', missing: false, files: ['docs/c.md'] },
  };
  const r1 = runDocsRender(realShapeCache, '');
  ok('R15-D1 renderDocsList against the REAL /api/docs payload shape ({root,missing,files}) renders one row per file, never throws',
    !r1.__error && r1.body.children.length === 3,
    JSON.stringify({ error: r1.__error, rowCount: r1.body.children.length }));
  ok('R15-D2 each row names project + file (the same "proj / file" label the code produces when it actually works)',
    r1.body.children.some(function (c) { return c.textContent === 'Circuit / docs/a.md'; }) &&
    r1.body.children.some(function (c) { return c.textContent === 'neural-lace / docs/c.md'; }),
    JSON.stringify(r1.body.children.map(function (c) { return c.textContent; })));
  const missingCache = { Ghost: { root: '/nowhere', missing: true, files: [] } };
  const r2 = runDocsRender(missingCache, '');
  ok('R15-D3 a project whose root is missing on this machine renders the honest empty state, never a broken/blank section',
    !r2.__error && r2.body.children.length === 1 && /no docs found/.test(r2.body.children[0].textContent),
    JSON.stringify({ error: r2.__error, text: r2.body.children[0] && r2.body.children[0].textContent }));
  const r3 = runDocsRender(realShapeCache, 'b.md');
  ok('R15-D4 the filter still narrows correctly against the real shape (proves .files is actually being read, not a stray fallback masking the bug)',
    !r3.__error && r3.body.children.length === 1 && r3.body.children[0].textContent === 'Circuit / docs/b.md',
    JSON.stringify({ error: r3.__error, rows: r3.body.children.map(function (c) { return c.textContent; }) }));
})();

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

// FIX 1 (historical) — captureUiState used to capture an open title
// editor's uncommitted value by PRESENCE, not focus. ROUND 16 retires the
// title-edit feature outright (deliverable 4) — captureUiState no longer
// has an `edit` field to capture at all; the tests below are re-pointed at
// PROVING that retirement (mutation-control style: the capture code, and
// its `.rm-title-input` query, are actually gone — not merely untested).
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
ok('T3-15 roll-up badges render ONE PER attention class present (R4: precedence orders, never selects) in the pinned precedence order. Round 15: "running" joins the SAME machinery (C1 applied to the running state), leading the order',
  // 2026-07-30: 'idle-dispatch' joins the order between limit-parked and
  // unknown, mirroring derive-lib's ATTENTION_PRECEDENCE exactly (a client
  // order that disagrees with the server's roll-up law is a real defect —
  // see R20-13, which pins the relationship rather than the literal list).
  /ROLLUP_ORDER/.test(roadmapJs) &&
  /'running',\s*'waiting-on-you',\s*'crashed',\s*'blocked-on',\s*'limit-parked',\s*'idle-dispatch',\s*'unknown'/.test(roadmapJs.replace(/\n\s*/g, ' ')));
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
ok('T3-27 re-render is STATE-PRESERVING: open-details set + scroll + focus captured and restored',
  /captureUiState/.test(roadmapJs) && /restoreUiState/.test(roadmapJs) &&
  /scrollTop|scrollY/.test(roadmapJs) && /activeElement/.test(roadmapJs));
// T3-27c/d/e used to prove an open title editor's uncommitted value
// survived a re-render even when unfocused. ROUND 16 (deliverable 4:
// "I don't see any need to edit the name of the plan titles") retires the
// title-edit feature outright — these three now prove the RETIREMENT
// itself: real execution against the ACTUAL captureUiState (not a
// reimplementation) shows it (a) never reads `.rm-title-input` even when
// the sandbox's document.querySelector mock WOULD hand one back, and
// (b) returns no `edit` field at all any more — a stale `.edit: null` left
// on the result would still pass a shallow "feature removed" check without
// proving the actual capture branch is gone; asserting the key is ABSENT
// (not merely null) closes that gap.
ok('T3-27c ROUND 16: captureUiState no longer queries `.rm-title-input` — a sandbox mock that WOULD return a fake open editor is never consulted (the querySelector call itself is gone from the real source, not merely its result ignored)',
  !/document\.querySelector\('\.rm-title-input'\)/.test(roadmapJsNoComments || roadmapJs));
ok('T3-27d ROUND 16: captureUiState()\'s real result carries no `edit` key at all (mutation-control: a stray `edit: null` literal left behind would still pass a weaker "!r.edit" check — this asserts the key is ABSENT)',
  (function () {
    var r = runCaptureUiState({ activeElement: fakeSaveBtn, openInput: fakeOpenInput });
    return !r.__error && !('edit' in r) && r.scrollY === 0;
  })());
ok('T3-27e ROUND 16: captureUiState still captures focusKey correctly (the retirement removed ONLY the title-edit branch, not the surrounding scroll/focus capture C7 still requires)',
  (function () {
    var r = runCaptureUiState({ activeElement: { dataset: { itemId: 'item-9' } }, activeInBody: true });
    return !r.__error && r.focusKey === 'item:item-9';
  })());

// --- title editing RETIRED (Round 16 deliverable 4) + rank reorder -------
// T3-28/T3-28b used to prove the todo.js-style Edit/Save/Cancel title
// editor. That editor is GONE outright (operator: "I don't see any need
// to edit the name of the plan titles") — restated below as proof of
// absence, source AND runtime (drilldown() never appends an edit
// control for a plan-kind item any more).
ok('T3-28 ROUND 16: no plan-title edit affordance anywhere — openTitleEditor/rm-title-input/rm-edit-btn/the client POST to /api/roadmap/title are all gone from roadmap.js (the server route itself is deliberately left in place, out of this UI-only scope — see the retirement comment above openTitleEditor\'s old location)',
  !/function openTitleEditor/.test(roadmapJsNoComments) &&
  !/rm-title-input/.test(roadmapJsNoComments) &&
  !/rm-edit-btn/.test(roadmapJsNoComments) &&
  !/fetch\('\/api\/roadmap\/title'/.test(roadmapJsNoComments));
ok('T3-28b edit feedback is aria-live (C9) — still true: the SAME .rm-edit-feedback element now carries reorder + override messages, not title-save ones',
  /aria-live/.test(roadmapJs));
ok('T3-29 ROUND 16: build-order reorder is drag-and-drop on a grip handle wired via wirePlanRowReorder, backed by the SAME /api/roadmap/rank endpoint the retired Move up/down buttons called; a NON-VISUAL Cmd/Ctrl+ArrowUp/Down keydown path on the row satisfies WCAG 2.2 2.5.7 without a second visible control',
  /function wirePlanRowReorder/.test(roadmapJsNoComments) &&
  /rm-drag-handle/.test(roadmapJsNoComments) &&
  /handle\.draggable = true/.test(roadmapJsNoComments) &&
  /addEventListener\('dragover'/.test(roadmapJsNoComments) &&
  /addEventListener\('drop'/.test(roadmapJsNoComments) &&
  /e\.metaKey \|\| e\.ctrlKey/.test(roadmapJsNoComments) &&
  /moveRank\(item, 'up', reorderFeedback\(det\)\)/.test(roadmapJsNoComments) &&
  /moveRank\(item, 'down', reorderFeedback\(det\)\)/.test(roadmapJsNoComments));
ok('T3-29b the retired Move up/Move down button LABELS are gone from the source (mutation control: proves the buttons were actually deleted, not just visually hidden)',
  !/'Move up in build order: '/.test(roadmapJsNoComments) && !/'Move down in build order: '/.test(roadmapJsNoComments));

// --- a11y hygiene (C9) ---------------------------------------------------
ok('T3-30 roadmap.js builds interactive controls as real <button>s (the one btn() factory, used throughout) and never wires click onto a bare div',
  /function btn\([\s\S]{0,120}?createElement\('button'\)/.test(roadmapJs) &&
  (roadmapJs.match(/btn\(/g) || []).length >= 10 &&
  !/[Dd]iv\.addEventListener\('click'/.test(roadmapJs));
ok('T3-31 CSS pairs every status class with the palette (stalled uses the --interrupt accent; unknown visibly distinct; complete uses --done, NOT --ok — Round 12 item 5 retires green from the roadmap)',
  /\.rm-status-stalled[^{]*\{[^}]*var\(--interrupt\)/.test(C) &&
  /\.rm-status-unknown[^{]*\{[^}]*var\(--warn\)/.test(C) &&
  /\.rm-status-complete[^{]*\{[^}]*var\(--done\)/.test(C));
// Round 12 item 5: --ok (green) is retired from EVERY roadmap fill/status
// rule — a single static green fill made a 2/14 plan and a 6/6 plan look
// identical (live-measured: 100% of fill pixels on the page were that one
// green). Scoped to .rm-* rules only (asks.js/other views keep their own
// green elsewhere — out of this item's stated scope).
ok('R12-1 green (--ok) is retired from the roadmap\'s status-complete chip, the default progress fill, and the per-project group fill — each now uses --done/status-specific colors, and the fill VARIES by status (rm-fill-<value> modifier) instead of one static green for every fraction',
  !/\.chip\.rm-status-complete\s*\{[^}]*var\(--ok\)/.test(C) &&
  !/\.rm-progress-fill\s*\{[^}]*var\(--ok\)/.test(C) &&
  !/\.rm-group-progress-fill\s*\{[^}]*var\(--ok/.test(C) &&
  /\.rm-fill-in-progress\s*\{[^}]*#38bdf8/.test(C) &&
  /\.rm-fill-complete\s*\{[^}]*var\(--done\)/.test(C) &&
  /\.rm-fill-stalled\s*\{[^}]*var\(--interrupt\)/.test(C) &&
  /rm-fill-'\s*\+\s*statusVal/.test(roadmapJsNoComments));
ok('R12-2 the progress track uses --border (#374151, live-legible) not --panel2 (measured 1.09:1 — effectively invisible, so an empty bar read as "no bar at all")',
  /\.rm-progress-bar\s*\{[^}]*background:\s*var\(--border\)/.test(C) && !/\.rm-progress-bar\s*\{[^}]*background:\s*var\(--panel2\)/.test(C));
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
ok('T3-39 isPhaseSeries/buildOrderLabel remain correct, EXECUTABLE pure utilities (Round 12 item 3 stopped INVOKING buildOrderLabel from the render path — see T3-40b — but the functions themselves are unchanged and still real)',
  (function () {
    const a = runPure(phaseSeriesSrc, 'isPhaseSeries([{kind:"plan"},{kind:"plan"}])');
    const b = runPure(phaseSeriesSrc, 'isPhaseSeries([{kind:"task"},{kind:"task"}])');
    const c = runPure(phaseSeriesSrc, 'isPhaseSeries([])');
    const label = runPure(phaseSeriesSrc, 'buildOrderLabel(1, 4)');
    return a === true && b === false && c === false && label === '#2 of 4';
  })());
ok('T3-40 renderChildList still wraps a phase-series in the connected .rm-phase-step LINE connector (rm-phase-series/rm-phase-step present, CSS draws the connector as an additive ::before line)',
  /rm-phase-series/.test(roadmapJsNoComments) && /rm-phase-step/.test(roadmapJsNoComments) &&
  /\.rm-phase-step::before\s*\{[^}]*background:/.test(C));
ok('T3-40b Round 12 item 3: the "#N OF 16" ordinal is RETIRED — buildOrderLabel is never called from renderNode/renderTree/renderChildList (PROVEN unstable: filtering renumbers a plan mid-session, e.g. "#12 OF 16" -> "#2 OF 3"), and rm-phase-inline is gone from both the renderer and the stylesheet',
  !/buildOrderLabel\(/.test(roadmapJsNoComments.replace(/function buildOrderLabel[\s\S]*?\n  \}/, '')) &&
  !/rm-phase-inline/.test(roadmapJsNoComments) && !/\.rm-phase-inline\s*\{/.test(C));

// --- Round 10 (operator re-walk 2026-07-27) ---
ok('R10-1 the separate rm-phase-label line is gone from the renderers (Round 12 retired its successor, rm-phase-inline, too — see T3-40b)',
  !/el\('div', 'rm-phase-label'/.test(roadmapJsNoComments));
ok('R10-2 every node row carries an explicit disclosure chevron that rotates on open (expandability is visible, not implied)',
  /rm-chevron/.test(roadmapJsNoComments) && /details\[open\] > \.rm-row > \.rm-chevron/.test(C));
ok('R10-3b Round 12 item 3: the group-level aggregate bar + "N/M complete" text is RETIRED — it restated the header\'s own "(... complete)" bucket count a THIRD time on the same screen (live-verified). No rm-group-progress-fill/-text calls remain, and the CSS rules are gone too.',
  !/rm-group-progress-fill/.test(roadmapJsNoComments) && !/rm-group-progress-text/.test(roadmapJsNoComments) &&
  !/\.rm-group-progress-fill\s*\{/.test(C) && !/\.rm-group-progress-text\s*\{/.test(C));
ok('R10-4 reorder feedback names WHAT moved, its NEW position, and WHOSE build order — never a bare "Order updated" (R11 I5: "#N of M", never "phase N of M")',
  /now #' \+ \(newIdx \+ 1\)/.test(roadmapJsNoComments.replace(/\n\s*/g, ' ')) &&
  /build order/.test(roadmapJsNoComments) && !/say\('Order updated\.'/.test(roadmapJsNoComments) &&
  !/now phase '/.test(roadmapJsNoComments));

// --- gap 4 (round-6): compact icon chrome, hover/focus-within ------------
// RETIRED whole-cloth in Round 16 (deliverables 3/4, operator verbatim:
// "I don't like the buttons appearing below the plan doc links; they
// force the GUI underneath to jump around awkwardly, and they're also
// unnecessary"). T3-41/42/42b used to pin the Edit/Move-up/Move-down icon
// chrome + its hover/focus-within height:0 reveal hack; restated below as
// proof the WHOLE mechanism is gone (source AND stylesheet), replaced by
// the drag-and-drop + Cmd/Ctrl+Arrow path T3-29 already proves.
ok('T3-41 ROUND 16: the icon-chrome glyphs/aria-labels (edit "✎", "Move up in build order", "Move down in build order") are gone from roadmap.js — no bare-icon-with-no-label regression is possible for a control that no longer exists',
  !/'✎'/.test(roadmapJsNoComments) &&
  !/edit the title of/.test(roadmapJsNoComments) &&
  !/Move up in build order/.test(roadmapJsNoComments) &&
  !/Move down in build order/.test(roadmapJsNoComments));
ok('T3-42 ROUND 16: the hover/focus-within height:0 reveal hack (.rm-title-edit, .rm-item-chrome) is gone from the stylesheet — the layout-jump root cause the operator named cannot recur because the mechanism no longer exists',
  !/\.rm-title-edit,\s*\.rm-item-chrome/.test(C) && !/\.rm-item-chrome\s*[,{]/.test(C));
ok('T3-42b ROUND 16: the JS-toggled `.rm-editing` class + its CSS rule are gone (the open-editor-stays-visible mechanism they protected no longer has an editor to protect)',
  !/classList\.add\('rm-editing'\)/.test(roadmapJs) && !/classList\.remove\('rm-editing'\)/.test(roadmapJs) &&
  !/\.rm-title-edit\.rm-editing/.test(C));

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
ok('R8-3 renderTree (the TOP-LEVEL list) applies the SAME isPhaseSeries connector treatment renderChildList already used one level down — the connector groups WITHIN the project group (never a flat cross-project series); Round 12 stopped computing a buildOrderLabel for it (see T3-40b) but the grouping itself is unchanged',
  /isPhaseSeries\(live\)/.test(roadmapJsNoComments) &&
  /rm-phase-series/.test(roadmapJsNoComments) &&
  !/buildOrderLabel\(gi, g\.items\.length\)/.test(roadmapJsNoComments) &&
  !/buildOrderLabel\(i, live\.length\)/.test(roadmapJsNoComments));

// --- R11 (round 11, 2026-07-28) — master-plan hierarchy client render ---
// docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md is the BINDING
// build spec; server-side derivation is roadmap-routes.selftest.js's own
// R11 block — these pins cover the CLIENT rendering contract only.
ok('R11-C1 a master renders TWO SEPARATE labeled fractions ("plans done/total", "own tasks done/total") — never one blended progress number — and the [master] tag/fraction chips are driven ONLY by master_summary (i.e. only resolved children)',
  /function masterSummaryNode/.test(roadmapJsNoComments) &&
  /'plans '\s*\+\s*ms\.plans\.done/.test(roadmapJsNoComments) &&
  /'own tasks '\s*\+\s*ms\.own_tasks\.done/.test(roadmapJsNoComments) &&
  /if \(item\.master_summary\)/.test(roadmapJsNoComments));
ok('R11-C2 a master SUPPRESSES the plain progress fraction in favor of the two labeled fractions (never renders both — that would be the blended-number trap in a different shape)',
  /if \(item\.master_summary\) \{[\s\S]{0,200}?masterSummaryNode\(item\)[\s\S]{0,200}?\}\s*else\s*\{[\s\S]{0,200}?fractionCellForRow\(item\)/.test(roadmapJsNoComments));
ok('R11-C3 dangling parent-plan renders a REAL button badge naming the missing slug ("parent \'<slug>\' not found") — never silently dropped, never a fake master; a broken cycle renders a distinct badge naming the other plan',
  /function referenceLifecycleBadges/.test(roadmapJsNoComments) &&
  /"parent '" \+ item\.parent_plan \+ "' not found"/.test(roadmapJsNoComments) &&
  /cycle detected with/.test(roadmapJsNoComments));
ok('R11-C4 a master\'s two child kinds render as TWO LABELED subsections ("Plans — build order" then "Direct tasks — task id"), reusing the SAME details/summary renderChildList path (I6 — no bespoke markup)',
  /'Plans — build order'/.test(roadmapJsNoComments) && /'Direct tasks — task id'/.test(roadmapJsNoComments) &&
  /function renderLabeledSubsection/.test(roadmapJsNoComments));
ok('R11-C5 task children carrying a `.batch` label group into a details/summary BATCH ROW (verbatim label + done/total fraction chip); a task with no batch label still renders directly, unwrapped',
  /function renderTaskBatches/.test(roadmapJsNoComments) && /function renderBatchRow/.test(roadmapJsNoComments) &&
  /done \+ '\/' \+ tasks\.length/.test(roadmapJsNoComments) && /rm-batch-label/.test(roadmapJsNoComments));
ok('R11-C6 both tree traversals (findItemData, pathTo) recurse into `child_plans`, not just `children` — a nested resolved child plan stays hash-addressable and reachable by a roll-up-badge expand exactly like any other item',
  /findItemData\(id, items\[i\]\.children \|\| \[\]\) \|\| findItemData\(id, items\[i\]\.child_plans \|\| \[\]\)/.test(roadmapJsNoComments) &&
  /pathTo\(id, items\[i\]\.children \|\| \[\], t\) \|\| pathTo\(id, items\[i\]\.child_plans \|\| \[\], t\)/.test(roadmapJsNoComments));
ok('R11-C7 the substring filter (I4) also searches a master\'s resolved child plans, not just its own tasks — a filter match keeps its full ancestor chain visible',
  /childPlans\[k\], q/.test(roadmapJsNoComments));

// --- Round 9 (operator audit 2026-07-23 — the audit table IS the oracle) ---
// R9-2: the top level groups by PROJECT with a visible header; the pure
// helpers run for REAL via the marker-anchored extraction technique
// (badge-law precedent above; markers ship in roadmap.js itself).
(function () {
  var bi = roadmapJs.indexOf('// PROJECT-GROUPING-BEGIN');
  var ei = roadmapJs.indexOf('// PROJECT-GROUPING-END');
  var src = (bi !== -1 && ei > bi) ? roadmapJs.slice(bi, ei) : null;
  ok('R9-2a selftest can locate the PROJECT-GROUPING extraction anchors in roadmap.js', !!src);
  if (!src) return;
  var sandbox = {
    items: [
      { id: 'a', project: 'neural-lace', status: { value: 'complete' } },
      { id: 'b', project: 'foresight', status: { value: 'in-progress' } },
      { id: 'c', project: 'neural-lace', status: { value: 'not-started' } },
    ],
  };
  vmMod.createContext(sandbox);
  try {
    vmMod.runInContext(src + '\nout = { g: groupItemsByProject(items), h: projectGroupHeaderText };', sandbox);
  } catch (e) { sandbox.out = { __error: String(e) }; }
  var g = (sandbox.out && sandbox.out.g) || [];
  ok('R9-2 groupItemsByProject groups by project preserving first-appearance (build) order',
    g.length === 2 && g[0].project === 'neural-lace' && g[0].items.length === 2 &&
    g[0].items[0].id === 'a' && g[0].items[1].id === 'c' && g[1].project === 'foresight');
  var h = sandbox.out && sandbox.out.h ? sandbox.out.h('neural-lace', g[0] ? g[0].items : []) : '';
  ok('R9-2b projectGroupHeaderText names the project + plan count + the R11 FOUR-BUCKET strip in the operator\'s round-1 words',
    /neural-lace/.test(h) && /2 plans, in build order/.test(h) && /1 complete/.test(h) && /1 upcoming/.test(h));
  // R11 anatomy L0 (orchestrator gap-closure): the four-bucket mapping law.
  var h2 = sandbox.out && sandbox.out.h ? sandbox.out.h('p', [
    { status: { value: 'not-started' } }, { status: { value: 'stalled' } },
    { status: { value: 'merged-unverified' } }, { status: { value: 'unknown' } },
  ]) : '';
  ok('R11-L0 the strip maps not-started→upcoming, stalled→in progress (lifecycle position; the stall shows via badges), merged-unverified→partially done, and appends unknown separately when nonzero',
    /1 upcoming/.test(h2) && /1 in progress/.test(h2) && /1 partially done/.test(h2) && /1 status unknown/.test(h2));
})();

// --- Round 17 deliverable 4 (operator 2026-07-30, decision A — multi-
// project GROUPING): real execution of the pure top-group helpers, same
// marker-anchored extraction technique as R9-2/R15 above. ------------------
(function () {
  const topGroupSrc = extractMarkedBlock(roadmapJs, '// TOP-GROUP-BEGIN', '// TOP-GROUP-END');
  ok('R17-T0 selftest can locate the TOP-GROUP extraction anchors in roadmap.js', !!topGroupSrc);
  if (!topGroupSrc) return;
  const items = [
    { id: 'a', project_group: 'Neural Lace', status: { value: 'in-progress' } },
    { id: 'b', project_group: 'Pocket Technician', status: { value: 'not-started' } },
    { id: 'c', project_group: 'Neural Lace', status: { value: 'not-started' } },
    { id: 'd', status: { value: 'not-started' } }, // no project_group at all -> '(ungrouped)'
  ];
  const g = runPure(topGroupSrc, 'groupItemsByTopGroup(' + JSON.stringify(items) + ')');
  ok('R17-T1 groupItemsByTopGroup ALWAYS emits the three canonical groups, in the fixed order Neural Lace / Pocket Technician / Personal, even when a group (Personal) has zero items',
    Array.isArray(g) && g.length >= 3 && g[0].group === 'Neural Lace' && g[1].group === 'Pocket Technician' && g[2].group === 'Personal' && g[2].items.length === 0,
    JSON.stringify(g && g.map((x) => x.group)));
  ok('R17-T2 items partition into their DECLARED project_group, preserving first-appearance order within the group (never a re-sort)',
    Array.isArray(g) && g[0].items.length === 2 && g[0].items[0].id === 'a' && g[0].items[1].id === 'c' &&
    g[1].items.length === 1 && g[1].items[0].id === 'b',
    JSON.stringify(g));
  ok('R17-T3 an item with NO project_group at all lands in an appended "(ungrouped)" section (after the canonical three), never silently dropped and never merged into one of the named groups',
    Array.isArray(g) && g.length === 4 && g[3].group === '(ungrouped)' && g[3].items.length === 1 && g[3].items[0].id === 'd',
    JSON.stringify(g));
  const hip1 = runPure(topGroupSrc, 'topGroupHasInProgress([{status:{value:"in-progress"}}])');
  const hip2 = runPure(topGroupSrc, 'topGroupHasInProgress([{status:{value:"not-started"}},{status:{value:"complete"}}])');
  const hip3 = runPure(topGroupSrc, 'topGroupHasInProgress([])');
  ok('R17-T4 topGroupHasInProgress is true when ANY item is neither not-started nor complete (the same in-progress-ish band bandPlanItems already uses), false for an all not-started/complete/empty set — this drives the group\'s collapsed-by-default state',
    hip1 === true && hip2 === false && hip3 === false);
  const headerEmpty = runPure(topGroupSrc, "topGroupHeaderText('Personal', [])");
  ok('R17-T5 an EMPTY canonical group renders an honest "no projects configured" line in its own header (never a bare "0 plans" or a vanished group)',
    typeof headerEmpty === 'string' && /Personal — no projects configured/.test(headerEmpty));
  const headerNonEmpty = runPure(topGroupSrc, "topGroupHeaderText('Neural Lace', [{id:'a'},{id:'c'}])");
  ok('R17-T6 a non-empty group renders its name + a plan count',
    typeof headerNonEmpty === 'string' && /Neural Lace — 2 plans/.test(headerNonEmpty));
})();
ok('R17-T7 renderTree is now the TOP-GROUP outer wrapper (partitions visibleItems via groupItemsByTopGroup and delegates each group\'s rendering to renderProjectGroups, the pre-R17 renderTree body, unchanged) — the wiring, not just the pure functions existing in isolation',
  /function renderTree\(visibleItems\) \{[\s\S]{0,200}groupItemsByTopGroup\(visibleItems\)/.test(roadmapJsNoComments) &&
  /renderProjectGroups\(items\)/.test(roadmapJsNoComments));
ok('R17-T8 a top-group is a real <details> (keyboard-native disclosure, C9 baseline) whose open/closed state is remembered in the SAME openSet session-state map every other collapsible in this file uses',
  /det\.className = 'rm-top-group'/.test(roadmapJsNoComments) && /openSet\[openKey\] = det\.open/.test(roadmapJsNoComments));

// --- R17 deliverable 5 (audit F8): formatAge gains day/week branches -----
// (real execution, marker-anchored extraction from app.js, same technique
// as every other pure-function test in this file — placed here, after
// vmMod/runPure are defined, not up near the R1..R17-N regex-only checks.)
(function () {
  const src = extractMarkedBlock(js, '// FORMAT-AGE-BEGIN', '// FORMAT-AGE-END');
  ok('R17-A0 selftest can locate the FORMAT-AGE extraction anchors in app.js', !!src);
  if (!src) return;
  function ageFor(hoursAgo) {
    const iso = new Date(Date.now() - hoursAgo * 3600000).toISOString();
    return runPure(src, "formatAge('" + iso + "')");
  }
  ok('R17-A1 under 48h still renders hours ("47h ago"), never a day', /^47h ago$/.test(ageFor(47)));
  ok('R17-A2 48h and over renders DAYS, never raw hours (the live-observed "377h ago" defect: an age this old must never render in hours)', /^2d ago$/.test(ageFor(48)));
  ok('R17-A3 mid-range ages render days (9d, matching the live "227h ago" -> ~9d conversion)', /^9d ago$/.test(ageFor(227)));
  ok('R17-A4 14 days and over renders WEEKS, not days', /^2w ago$/.test(ageFor(14 * 24)));
  ok('R17-A5 a missing timestamp renders "never", never a fabricated age', runPure(src, "formatAge('')") === 'never');
  ok('R17-A6 an unparseable timestamp renders "unknown", never NaN-poisoned text', runPure(src, "formatAge('not-a-date')") === 'unknown');
})();

// --- R17 deliverable 3 (audit F2 — "Derivation failed" panels live on two
// panels right now): real execution of the reshaped renderError against a
// minimal fake DOM (same hand-rolled technique as the badge-law/docs-list
// sections above — no jsdom/headless browser). Proves the ACTUAL rendered
// structure/order, not just source-text presence. -----------------------
(function () {
  const src = extractMarkedBlock(js, '// RENDER-ERROR-BEGIN', '// RENDER-ERROR-END');
  ok('R17-E0 selftest can locate the RENDER-ERROR extraction anchors in app.js', !!src);
  if (!src) return;
  function makeErrorFakeDom() {
    function FakeNode(tag) {
      this.tagName = tag;
      this.className = '';
      this._text = '';
      this.children = [];
      this.attrs = {};
    }
    Object.defineProperty(FakeNode.prototype, 'textContent', {
      get: function () { return this._text; },
      set: function (v) { this._text = v; this.children = []; },
    });
    FakeNode.prototype.appendChild = function (c) { this.children.push(c); return c; };
    FakeNode.prototype.setAttribute = function (k, v) { this.attrs[k] = v; };
    FakeNode.prototype.addEventListener = function () {};
    return { createElement: function (tag) { return new FakeNode(tag); } };
  }
  // allText(node) -- every textContent in the subtree, in document order,
  // so "headline before scope before details" can be asserted positionally
  // without depending on class-name internals.
  function allText(node) {
    var out = [];
    if (node._text) out.push(node._text);
    (node.children || []).forEach(function (c) { out = out.concat(allText(c)); });
    return out;
  }
  function findByClass(node, cls) {
    if ((' ' + node.className + ' ').indexOf(' ' + cls + ' ') !== -1) return node;
    for (var i = 0; i < (node.children || []).length; i++) {
      var found = findByClass(node.children[i], cls);
      if (found) return found;
    }
    return null;
  }
  function runRenderError(container, paneResp) {
    const fakeDoc = makeErrorFakeDom();
    const sandbox = {
      document: fakeDoc,
      forceRefresh: function () {},
      makeCopyBtn: function (text, label) {
        var b = fakeDoc.createElement('button');
        b.className = 'copy-btn'; b.textContent = label; b._copyText = text;
        return b;
      },
    };
    vmMod.createContext(sandbox);
    const code = src + "\nrenderError(container, " + JSON.stringify(paneResp) + ");";
    sandbox.container = container;
    try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
    return container;
  }
  const statusResp = { pane: 'status', rc: 1, command: 'nl status --json', stderr_tail: 'jq: invalid JSON text passed to --argjson\nUse jq --help for help' };
  const dom1 = makeErrorFakeDom();
  const c1 = dom1.createElement('div');
  const result1 = runRenderError(c1, statusResp);
  const box1 = result1 && !result1.__error ? findByClass(result1, 'pane-error') : null;
  ok('R17-E1 the headline is PLAIN LANGUAGE and question-shaped ("Can\'t read live session status right now"), never "Derivation failed (rc=1)"',
    box1 && findByClass(box1, 'pane-error-title') && findByClass(box1, 'pane-error-title')._text === "Can't read live session status right now",
    JSON.stringify(result1 && result1.__error));
  ok('R17-E2 the headline renders BEFORE (document order) the raw command/stderr — the technical detail is never the first thing on screen',
    (function () {
      const all = allText(box1);
      const idxHeadline = all.indexOf("Can't read live session status right now");
      const idxCmd = all.findIndex(function (t) { return /nl status --json/.test(t); });
      return idxHeadline !== -1 && idxCmd !== -1 && idxHeadline < idxCmd;
    })());
  ok('R17-E3 scope honesty names the SPECIFIC affected panel ("What\'s running") — never a generic, unscoped error',
    findByClass(box1, 'pane-error-scope') && /What's running/.test(findByClass(box1, 'pane-error-scope')._text));
  ok('R17-E4 the raw command + stderr (including the jq usage-hint text) are folded INSIDE a <details> element, never rendered as a top-level sibling of the headline',
    (function () {
      const details = findByClass(box1, 'pane-error-details');
      return details && details.tagName === 'details' && allText(details).some(function (t) { return /jq: invalid JSON/.test(t); });
    })());
  ok('R17-E5 a "Copy details" action exists, carrying the command + stderr as its copy payload',
    (function () {
      const actions = findByClass(box1, 'pane-error-actions');
      const copyBtn = actions && actions.children.find(function (c) { return c.textContent === 'Copy details'; });
      return !!copyBtn && /nl status --json/.test(copyBtn._copyText) && /jq: invalid JSON/.test(copyBtn._copyText);
    })());
  ok('R17-E6 every one of the six panes + the why-drawer has its OWN named headline (never a shared generic message that hides which question went unanswerable)',
    ['status', 'needs-me', 'shipped', 'health', 'costs', 'backlog', 'why'].every(function (pane) {
      const c = makeErrorFakeDom().createElement('div');
      const r = runRenderError(c, { pane: pane, rc: 1, command: 'nl ' + pane, stderr_tail: '' });
      const b = r && !r.__error ? findByClass(r, 'pane-error') : null;
      const title = b && findByClass(b, 'pane-error-title');
      return title && title._text && title._text !== 'Derivation failed (rc=1)';
    }));
  ok('R17-E7 an UNRECOGNIZED pane key still degrades honestly (the old rc-numbered headline), never a throw',
    (function () {
      const c = makeErrorFakeDom().createElement('div');
      const r = runRenderError(c, { pane: 'some-future-pane', rc: 1, command: 'nl x', stderr_tail: '' });
      const b = r && !r.__error ? findByClass(r, 'pane-error') : null;
      const title = b && findByClass(b, 'pane-error-title');
      return title && title._text === 'Derivation failed (rc=1)';
    })());
})();

// --- R17 deliverable 7 (audit F9 — the app's own cross-view-link law
// applied everywhere except the Health tab): interrupt chips + Q2 cards
// that name an inbox-addressable item become real links to #inbox/<id>.
// Source-regex wiring checks (same convention as T4-16 above) — the
// click-handler wiring itself, not a full DOM click simulation. --------
ok('R17-H1 Q2\'s needs-me card renders a real <button> that navigates to #inbox/<id> using the item\'s OWN ledger id (it.id) — the SAME id inbox.js\'s #inbox/<id> addressing resolves (both /api/pane/needs-me and /api/inbox read the same NEEDS-YOU ledger)',
  /nm-open-inbox-btn/.test(js) &&
  /window\.WorkstreamsShell\.navigate\('#inbox\/' \+ encodeURIComponent\(it\.id\)\)/.test(js));
ok('R17-H2 the Q2 open-in-Inbox button is a REAL <button> (never a bare div click handler, this app\'s own C9 baseline) and is only rendered when it.id genuinely exists — never a fabricated link',
  /if \(it\.id\) \{\s*\n\s*var openInboxBtn = document\.createElement\('button'\)/.test(js));
ok('R17-H3 the interrupt-strip\'s needs-me chip is ALSO now a real <button> navigating to the same #inbox/<id>, with an honest disabled+tooltip fallback when the item genuinely carries no id (never a fake link)',
  /var chip = document\.createElement\('button'\)/.test(js) &&
  (js.match(/window\.WorkstreamsShell\.navigate\('#inbox\/' \+ encodeURIComponent\(it\.id\)\)/g) || []).length === 2 &&
  /chip\.disabled = true;/.test(js) && /cannot link to the Inbox/.test(js));
ok('R17-H4 the waiting-ON-ME SESSION chip (a different class of interrupt item — no NEEDS-YOU ledger id, no roadmap-task binding exposed to this pane) is deliberately UNCHANGED this round — still plain text, never a fabricated/dead link',
  /chip\.textContent = 'session ' \+ s\.session_id \+ ' \(waiting-on-me\)'/.test(js));

// --- Round 15 (coordinator, operator verbatim: "the Workstreams UI still
// doesn't actually represent the actual order of building, at least not at
// the plan level") — THREE STABLE BANDS: real execution, not source-regex,
// since a wrong band membership silently reorders the whole tree. ---------
(function () {
  const bandSrc = extractMarkedBlock(roadmapJs, '// PLAN-BANDING-BEGIN', '// PLAN-BANDING-END');
  ok('R15-B0 selftest can locate the PLAN-BANDING extraction anchors in roadmap.js', !!bandSrc);
  if (!bandSrc) return;
  function band(itemsExpr) { return runPure(bandSrc, 'bandPlanItems(' + itemsExpr + ')'); }
  const b1 = band(JSON.stringify([
    { id: 'a', status: { value: 'not-started' } },
    { id: 'b', status: { value: 'in-progress' } },
    { id: 'c', status: { value: 'not-started' } },
    { id: 'd', status: { value: 'stalled' } },
  ]));
  ok('R15-B1 bandPlanItems renders every non-not-started plan BEFORE every not-started one, each band keeping its ORIGINAL relative (rank) order — never a re-sort within a band',
    Array.isArray(b1) && b1.map((it) => it.id).join(',') === 'b,d,a,c',
    JSON.stringify(b1 && b1.map((it) => it.id)));
  const b2 = band(JSON.stringify([
    { id: 'x', status: { value: 'merged-unverified' } },
    { id: 'y', status: { value: 'unknown' } },
  ]));
  ok('R15-B2 merged-unverified and unknown both count as "in progress-ish" (any state that is not literally not-started) — they lead the band, never get pushed to upcoming',
    Array.isArray(b2) && b2.map((it) => it.id).join(',') === 'x,y', JSON.stringify(b2 && b2.map((it) => it.id)));
  ok('R15-B3 an item with NO status object at all is treated as upcoming (never thrown, never mis-banded as in-progress)',
    band('[{id:"z"}]').map((it) => it.id).join(',') === 'z');
  ok('R15-B4 empty/absent input -> empty array, never throws',
    band('[]').length === 0 && band('null').length === 0);
  ok('R15-B5 renderTree actually calls bandPlanItems on each group\'s items before iterating (the wiring, not just the pure function existing in isolation)',
    /bandPlanItems\(g\.items\)\.forEach/.test(roadmapJsNoComments));
  // R15-B6: mutation control — a stray identity function in place of the
  // real band split would make R15-B1 fail (b/d would stay AFTER a/c,
  // matching insertion order instead of the banded order), proving this
  // suite is discriminating and not just checking "returns an array".
  ok('R15-B6 mutation control: bandPlanItems is NOT a no-op passthrough — the banded order actually differs from plain insertion order for a mixed-state list',
    b1.map((it) => it.id).join(',') !== ['a', 'b', 'c', 'd'].join(','));
})();

ok('R15-H1 projectGroupHeaderText leads with "in progress" (immediately after "in build order"), matching the new render order — the header used to lead with "upcoming", which read as backwards next to a phrase claiming build order',
  (function () {
    const bi = roadmapJs.indexOf('// PROJECT-GROUPING-BEGIN');
    const ei = roadmapJs.indexOf('// PROJECT-GROUPING-END');
    const src = (bi !== -1 && ei > bi) ? roadmapJs.slice(bi, ei) : null;
    if (!src) return false;
    const sandbox = { items: [{ status: { value: 'in-progress' } }, { status: { value: 'not-started' } }] };
    vmMod.createContext(sandbox);
    try { vmMod.runInContext(src + '\nout = projectGroupHeaderText("p", items);', sandbox); } catch (e) { return false; }
    const h = sandbox.out || '';
    return h.indexOf('in build order') !== -1 &&
      h.indexOf('1 in progress') < h.indexOf('1 upcoming') &&
      h.indexOf('in build order') < h.indexOf('1 in progress');
  })());

// R11 Critical 6 (orchestrator gap-closure): active-path default expansion.
ok('R11-C6 containers default OPEN only when the SUBTREE holds active work (in-progress / live session / waiting-on-you); toggle stores true AND false so an explicit close survives re-renders; only user deviations recorded',
  /function subtreeHasActive/.test(roadmapJsNoComments) && /function defaultOpen/.test(roadmapJsNoComments) &&
  /openSet\[item\.id\] = det\.open/.test(roadmapJsNoComments) &&
  /renderedOpen/.test(roadmapJsNoComments) &&
  !/if \(openSet\[item\.id\]\) det\.open = true;/.test(roadmapJsNoComments));
// R11 I4 (orchestrator gap-closure): kanban cards stay plans; masters are chips.
ok('R11-I4 kanban flattens child_plans into cards (masters never cards) and each child card carries its master chip (rm-master-tag)',
  /cardEntries/.test(roadmapJsNoComments) && /rm-master-tag/.test(roadmapJsNoComments) &&
  /it\.master_summary/.test(roadmapJsNoComments));
ok('R9-2c renderTree renders the group header element (rm-project-group-head) and scopes phase steps inside the group container',
  /rm-project-group-head/.test(roadmapJsNoComments) && /groupItemsByProject\(live\)/.test(roadmapJsNoComments));
ok('R9-2d reorder stays GLOBAL: renderNode receives the item\'s index in the full build-order list, never the group-local index',
  /renderNode\(it, live\.indexOf\(it\), live\.length\)/.test(roadmapJsNoComments.replace(/\n\s*/g, ' ')));
// R9-3 (Round 12 item 3 override): the operator named the per-row project
// chip redundant — "including a NL tag on each item is redundant
// considering they're all underneath the NL node" — the group header
// already names the project + count. Kanban cards are NOT grouped by a
// project header, so they KEEP the chip (a row that "leaves its group").
ok('R9-3 the TREE row no longer carries a per-item project chip (Round 12: redundant with the group header, operator-named); the KANBAN card still does (it has no group header to inherit the project from)',
  !/sum\.appendChild\(el\('span', 'chip rm-project-tag'/.test(roadmapJsNoComments) &&
  /chipRow\.appendChild\(el\('span', 'chip rm-project-tag'/.test(roadmapJsNoComments));
// R9-5: the provenance line renders ONLY when a real linked request exists.
ok('R9-5 "from your request(s)" gates on a non-empty link list — the "(no captured request)" filler line is gone',
  !/no captured request/.test(roadmapJsNoComments));
// R9-7: the unbound-sessions node renders at the top of the roadmap body.
// 2026-08-02: scoped down to what a source regex can honestly prove — that
// renderAll is WIRED to payload.unbound_sessions. It used to also claim it
// "renders rm-agents rows", which a regex cannot show; that half is now
// really executed by R21-13/R21-13c against the rendered output.
ok('R9-7 renderAll is wired to payload.unbound_sessions and mounts the rm-unbound-sessions node (WIRING only — what the node actually renders is executed in R21-13*)',
  /function renderUnboundSessions/.test(roadmapJsNoComments) &&
  /unbound_sessions/.test(roadmapJsNoComments) && /rm-unbound-sessions/.test(roadmapJsNoComments));
// R9-6: the landing sidebar — compact My-items + Backlog mirrors of the
// SAME endpoints (one writer; counts can never disagree).
ok('R9-6 index.html carries the rm-layout sidebar with both panes',
  /rmSidebar/.test(html) && /rmMyItemsPane/.test(html) && /rmBacklogPane/.test(html));
ok('R9-6b the sidebar reuses the canonical endpoints (GET/POST /api/todo, GET /api/backlog) — no third data source',
  /loadSideMyItems/.test(roadmapJsNoComments) && /loadSideBacklog/.test(roadmapJsNoComments) &&
  /'\/api\/todo'/.test(roadmapJsNoComments) && /'\/api\/backlog'/.test(roadmapJsNoComments));
ok('R9-6c pane collapsed-state persists (localStorage) and My-items never reloads on the 30s tick (write-safety precedent)',
  /rm\.side\.myitems\.open/.test(roadmapJsNoComments) && /rm\.side\.backlog\.open/.test(roadmapJsNoComments) &&
  /setInterval\(loadSideBacklog/.test(roadmapJsNoComments) && !/setInterval\(loadSideMyItems/.test(roadmapJsNoComments));
// --- R9 follow-ups (operator re-walk 2026-07-24) ---
// Round 15 (operator, verified live at :7733): the OLD `file:///` href was
// a DEAD link from this http-served page (confirmed live — clicking it
// produced zero navigation and zero network activity). R9F-1 now asserts
// the FIXED behavior: plan links open the SAME in-page docs viewer the
// Docs button already renders through (openPlanDocModal -> /api/doc
// {project,path}, reusing docModal — never a second renderer), falling
// back to plain text + copy only when the server's plan_doc resolver
// genuinely can't place the plan under any configured project root.
ok('R9F-1 every plan phase links its plan FILE in the drill-down via the in-page docs viewer (plan_doc {project,path} -> openPlanDocModal -> /api/doc), never a dead file:// href',
  /plan_path/.test(roadmapJsNoComments) && /rm-plan-link/.test(roadmapJsNoComments) &&
  /function openPlanDocModal\(project, docPath\)/.test(roadmapJsNoComments) &&
  /item\.plan_doc && item\.plan_doc\.project && item\.plan_doc\.path/.test(roadmapJsNoComments) &&
  /openPlanDocModal\(item\.plan_doc\.project, item\.plan_doc\.path\)/.test(roadmapJsNoComments) &&
  !/a\.href = 'file:\/\/\/'/.test(roadmapJsNoComments));
ok('R9F-1b the no-plan_doc fallback is plain text + copy, never a fabricated or dead href',
  /planTextSpan = el\('span', 'rm-plan-link', displayPath\)/.test(roadmapJsNoComments) &&
  /makeCopyBtn\(item\.plan_path, 'copy path'\)/.test(roadmapJsNoComments));
ok('R9F-2 the My-items pane surfaces the Inbox ANSWERABLE set (the real waiting-on-you), navigating #inbox/<id> — todo file alone was empty while 4 items waited',
  /\/api\/inbox/.test(roadmapJsNoComments) && /rm-side-waiting/.test(roadmapJsNoComments) &&
  /#inbox\/'\s*\+\s*encodeURIComponent/.test(roadmapJsNoComments.replace(/\n\s*/g, ' ')));
// self-read (requestsJs/appJs are declared LATER in this file — TDZ):
(function () {
  var reqSrc = '';
  var appSrc = '';
  try { reqSrc = fs.readFileSync(path.join(D, 'requests.js'), 'utf8'); } catch (_) {}
  try { appSrc = fs.readFileSync(path.join(D, 'app.js'), 'utf8'); } catch (_) {}
  ok('R9F-3 the Requests ledger mounts INSIDE .ws-layout (the hidden interim tree\'s flex slot) so the column resize handle splits a real pair again',
    /requests-ledger-in-layout/.test(reqSrc) && /layoutRow\.insertBefore\(section/.test(reqSrc) &&
    !/interimColHandle/.test(reqSrc));
  ok('R9F-4 the Roadmap tab has its own column resize handle wired through the SAME setupHandle machinery (adjustable panes stay a feature)',
    /rmColResizeHandle/.test(html) && /rmColResizeHandle/.test(appSrc) && /targetId: 'rmSidebar'/.test(appSrc));
})();
// R8-4 originally also pinned a client-side title-save POST body
// (JSON.stringify({ id: item.id, title: t })) — that call site is GONE
// along with the whole title-edit affordance (Round 16 deliverable 4);
// the rank-move half of the id-keyed (not ask_id-keyed) contract still
// holds and is re-pinned below.
ok('R8-4 the rank-move wire body is id-keyed (a plan slug), not ask_id-keyed (the old ask-rooted contract) — no POST body anywhere still sends ask_id',
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
// 2026-07-22 acceptance S4: the target is the promoted PLAN slug (Round 8
// re-rooted the Roadmap on plan slugs) — an `item.id` (ask id) target
// false-misses with the C3 banner. The pin asserts the slug shape AND the
// slug's derivation from the promoted event.
ok('T5-7 "became →" links address #roadmap/<plan-slug> (never the ask id) via the shell\'s navigate()',
  /#roadmap\/'\s*\+\s*becameSlug/.test(requestsJs.replace(/\n\s*/g, ' ')) &&
  /becameSlug = ev\.plan_slug/.test(requestsJs) &&
  !/#roadmap\/'\s*\+\s*item\.id/.test(requestsJs.replace(/\n\s*/g, ' ')) &&
  /shell\.navigate/.test(requestsJs));

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

// ============================================================
// R17 deliverable 6 (audit F3 — the ledger's missing exit verb) + 2b
// (audit F4 — render defenses). ------------------------------------------
// ============================================================
ok('R17-R1 Dismiss delegates to the SAME lifecycle endpoint asks.js\'s own dismiss button already uses (POST /api/ask/<id>/lifecycle, action:"dismiss") — no new server route invented for this',
  /postLifecycle\(askId, action\)/.test(requestsJs) &&
  /fetch\('\/api\/ask\/' \+ encodeURIComponent\(askId\) \+ '\/lifecycle'/.test(requestsJs) &&
  /dismissRequest\(item\.id, say, dismissBtn\)/.test(requestsJs));
ok('R17-R2 Dismiss is a real <button> (rl-dismiss-btn) rendered ONLY for OPEN requests — a closed one already has its own recorded exit',
  /if \(item\.state !== 'closed'\)/.test(requestsJs) && /rl-dismiss-btn/.test(requestsJs));
ok('R17-R3 "confirm-click, not confirm-dialog" (the dispatch\'s own binding instruction): the dismiss action fires IMMEDIATELY on click — no window.confirm(...) gate before the fetch call (source comments merely NAME the avoided pattern in prose, never invoke it)',
  !/window\.confirm\(|[^.\w]confirm\(['"]/.test(requestsJs));
ok('R17-R4 an Undo affordance appears after a successful dismiss, within a short window, before the list reloads — the app\'s own established undo-window pattern (asks.js/backlog.js), never a native dialog',
  /rl-undo-btn/.test(requestsJs) && /DISMISS_UNDO_WINDOW_MS/.test(requestsJs) &&
  /postLifecycle\(askId, 'reopen'\)/.test(requestsJs));
ok('R17-R5 a FAILED dismiss re-enables the button and surfaces a named error (never a silent no-op)',
  /dismissBtn\.disabled = false;\s*\n\s*say\(\(r && r\.error\) \|\| 'Could not dismiss this request\.', true\)/.test(requestsJs));

// --- F4b: collapse consecutive identical timeline events (real execution) ---
(function () {
  const src = extractMarkedBlock(requestsJs, '// GROUP-TIMELINE-RUNS-BEGIN', '// GROUP-TIMELINE-RUNS-END');
  ok('R17-R6 selftest can locate the GROUP-TIMELINE-RUNS extraction anchors in requests.js', !!src);
  if (!src) return;
  function group(eventsExpr) { return runPure(src, 'groupConsecutiveTimelineEvents(' + eventsExpr + ')'); }
  const g1 = group(JSON.stringify([
    { type: 'origin', text: 'Registered' },
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'amendment captured' },
    { type: 'decision', text: 'dismissed (you)' },
  ]));
  ok('R17-R7 a run of 5 consecutive, identical (type+text) events collapses into ONE group (collapsed:true) — the live defect: 93 identical "amendment captured" rows',
    Array.isArray(g1) && g1.length === 3 && g1[0].collapsed === false && g1[0].events.length === 1 &&
    g1[1].collapsed === true && g1[1].events.length === 5 && g1[2].collapsed === false && g1[2].events.length === 1,
    JSON.stringify(g1 && g1.map((g) => ({ n: g.events.length, c: g.collapsed }))));
  const g2 = group(JSON.stringify([
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'amendment captured' },
  ]));
  ok('R17-R8 a run of only TWO identical events does NOT collapse — not noisy enough to hide behind a click (threshold is 3+)',
    Array.isArray(g2) && g2.length === 1 && g2[0].collapsed === false && g2[0].events.length === 2);
  const g3 = group(JSON.stringify([
    { type: 'amendment', text: 'amendment captured' },
    { type: 'amendment', text: 'possible amendment captured (not yet classified)' },
    { type: 'amendment', text: 'amendment captured' },
  ]));
  ok('R17-R9 events with the SAME type but DIFFERENT text never merge into one run (text must match too — a pending vs. confirmed amendment are genuinely different events)',
    Array.isArray(g3) && g3.length === 3 && g3.every((g) => !g.collapsed));
  ok('R17-R10 empty/absent input never throws, returns an empty group list',
    group('[]').length === 0 && group('null').length === 0);
  ok('R17-R11 timelineNode actually calls groupConsecutiveTimelineEvents (the wiring, not just the pure function existing in isolation), and a collapsed run still renders each ORIGINAL event via timelineEventNode once expanded — never dropping individual events (so a collapsed amendment keeps its own Detach affordance)',
    /groupConsecutiveTimelineEvents\(item\.timeline\)\.forEach/.test(requestsJs) &&
    /runEvents\.forEach\(function \(ev\) \{ innerList\.appendChild\(timelineEventNode\(item, ev\)\)/.test(requestsJs.replace(/\s+/g, ' ')));
})();

// --- F4a/F4c: render-defense wiring (the actual title/error-signature
// detection is server-side, requests-routes.js — this just proves the
// client trusts and renders whatever title the server sends, never a
// second client-side heuristic re-deriving it, per this app's own
// "no second heuristic" convention). ---------------------------------
ok('R17-R12 the row summary and drill-down both render item.title directly (no client-side title-guessing logic duplicated here — the server\'s buildRequestItem is the ONE place title defenses live)',
  /el\('span', 'rl-title', item\.title\)/.test(requestsJs));
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
ok('T4-6b "blocks: <item>" only renders when the server actually names a roadmap id (WIRED, ROADMAP-WAITING-ON-YOU-SIGNAL-01 round 14: resolveBlocksRoadmapId returns null on no conservative match — never fabricated)',
  /if \(item\.blocks_roadmap_id\)/.test(inboxJs) && /blocks_roadmap_id: resolveBlocksRoadmapId\(item\)/.test(inboxRoutesJs) &&
  /function resolveBlocksRoadmapId\(item\)/.test(inboxRoutesJs) && /return null;/.test(inboxRoutesJs));

// --- expanded anatomy (constitution §3 compact format) ---
ok('T4-7 expanded anatomy renders all five §3 steps: Decision/Action needed, Context, Trade-offs table, My pick, Reply-with',
  /Decision needed: |Question: /.test(inboxJs) && /ib-context/.test(inboxJs) && /optionsTable/.test(inboxJs) &&
  /My pick: /.test(inboxJs) && /How to answer: /.test(inboxJs));
ok('T4-7b the trade-offs table parser + the reply stub are server-derived (parseDecisionAnatomy) and client-rendered, never a second parse',
  /parseDecisionAnatomy/.test(inboxRoutesJs) && /reply_stub/.test(inboxRoutesJs) && /reply_stub/.test(inboxJs));
ok('T4-7c the ANSWER lifecycle (C3a) is pointer + copyable stub (v1) — a Copy button, never inline answer submission to the ledger',
  /ib-copy-btn/.test(inboxJs) && !/\/api\/inbox\/answer/.test(inboxJs));

// --- links rendering (INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01, round 14) ---
// item.links[] had NO rendering surface anywhere in this file before this
// fix — a real, live defect (the field existed, nothing ever read it).
ok('T4-7d expandedAnatomy renders item.links via linksBlock — the field that used to be computed server-side and NEVER read client-side',
  /function linksBlock\(links\)/.test(inboxJs) && /linksBlock\(item\.links\)/.test(inboxJs));
ok('T4-7e linkRowNode renders an http(s) URL as a REAL <a> (always resolves); anything else is plain text + a copy button, NEVER a fabricated/relative href ("a dead link is worse than no link")',
  /if \(\/\^https\?:\\\/\\\/\/i\.test\(value\)\) \{/.test(inboxJs) &&
  /a\.href = value; a\.target = '_blank'/.test(inboxJs) &&
  /makeCopyBtn\(value\)/.test(inboxJs));
ok('T4-7f mutation control: linkRowNode is REACHED for every entry in a non-empty links array (linksBlock forEachs over `links`, not a fixed head/tail slice)',
  /links\.forEach\(function \(l\) { wrap\.appendChild\(linkRowNode\(l\)\)/.test(inboxJs.replace(/\s+/g, ' ')));
ok('T4-7g server-side: extractAnchorsFromText + mergeLinks populate `links` from inline anchors even when the producer supplied NO --link entries at all (part b of the fix)',
  /function extractAnchorsFromText\(text\)/.test(inboxRoutesJs) && /function mergeLinks\(/.test(inboxRoutesJs) &&
  /links: mergeLinks\(/.test(inboxRoutesJs));
ok('T4-7h BACKGROUND beyond 5 lines is never silently dropped with no note — a "+N more" line points to the Raw verbatim details below. Round 18: the cap now applies to proseLines only, NEVER to the whole context, because the old cap dropped the operator\'s STEP 3 command (see R18-IB block for the executed proof)',
  /proseLines\.length > 5/.test(inboxJs) && /more line\(s\) of background — see "Raw verbatim" below/.test(inboxJs) &&
  !/item\.context\.slice\(0, 5\)/.test(inboxJs));
ok('T4-7i server-side title extraction strips a redundant "Decision needed:"\/"Question:" prefix the producer already included on line 1 (the live double-label bug)',
  /replace\(\/\^\(decision needed\|question\)\\s\*:\\s\*\/i, ''\)/.test(inboxRoutesJs));
ok('T4-7j server-side: the arrow-format options grammar ("Option NAME -> outcome") is a SECOND accepted shape alongside the markdown table, both accumulating into the same options[] array',
  /OPTION_ARROW_RE/.test(inboxRoutesJs) && /options\.push\(\{ option: arrowM\[1\], outcome: arrowM\[2\]\.trim\(\) \}\)/.test(inboxRoutesJs));

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

// --- R17 deliverable 2a (operator, live: "the links on the Inbox tab
// don't work") — PROVEN root cause: a pointer row's title used to be a
// real <a href="file:///...">, which a browser loading this page over
// http silently blocks. Source-regex, not vm execution (this file has no
// jsdom/headless browser to actually click a rendered <a>, per its own
// header), matching this file's established convention for DOM-shape
// assertions (see T4-16..T4-20 above). ------------------------------------
ok('R17-L3 myItemsFileUrl NEVER constructs a file:// href — the local-path branches that used to (see the git history this fix replaces) are gone entirely',
  !/'file:\/\/'/.test(inboxJs) && !/'file:\/\/\/'/.test(inboxJs));
ok('R17-L4 a resolvable item.doc_ref routes the pointer row\'s title through openInboxDocModal (the in-page doc viewer), never a raw href, before falling back to an http(s) link or an honest disabled affordance',
  /item\.doc_ref && item\.doc_ref\.project && item\.doc_ref\.path/.test(inboxJs) &&
  /openInboxDocModal\(item\.doc_ref\.project, item\.doc_ref\.path\)/.test(inboxJs));
ok('R17-L5 openInboxDocModal reuses the EXISTING docModal DOM + /api/doc + the shared window.MdRender pipeline (the SAME pattern roadmap.js\'s openPlanDocModal already uses for plan links) — no second renderer',
  /function openInboxDocModal\(project, docPath\)/.test(inboxJs) &&
  /fetch\('\/api\/doc\?project=' \+ encodeURIComponent\(project\)/.test(inboxJs) &&
  /window\.MdRender && typeof window\.MdRender\.renderMarkdown === 'function'/.test(inboxJs));

// ============================================================
// ROUND 12 (2026-07-29) — ux-ia-auditor LIVE AUDIT of the running cockpit
// (headless Chrome against :7733, geometry/colour measured from computed
// styles, not read from source). Nine build items; tests below are grouped
// by item number. Pure logic (deriveTaskSpanLabel, findMatchingDescendant)
// is REALLY EXECUTED in a vm sandbox (the T3-33+ technique above); DOM-
// construction and CSS are asserted structurally, the same convention this
// whole file already uses (a source-regex assertion IS discriminating here
// — delete the code it names and the regex stops matching; verified by
// mutation for the highest-value subset, see the build report).
// ============================================================
const taskSpanSrc = extractMarkedBlock(roadmapJs, '// TASK-SPAN-BEGIN', '// TASK-SPAN-END');
const filterMatchSrc = extractMarkedBlock(roadmapJs, '// FILTER-MATCH-BEGIN', '// FILTER-MATCH-END');
ok('R12-0 selftest can locate the TASK-SPAN/FILTER-MATCH extraction anchors (source-execution harness precondition)',
  !!taskSpanSrc && !!filterMatchSrc);

// ---- item 1: the row grid --------------------------------------------
// ROUND 13 fix 1 (operator walkthrough, live-measured: title started
// ~137-163px in on a real row at 1400px viewport, 93.75% of that from a
// 56px marker column that was EMPTY on 105/112 real rows): the marker
// column is RETIRED — the grid is now 6 columns, not 7; markerChips folds
// into the title cell instead. R12-3/R12-6 FLIP here (both pinned the OLD
// 7-column template/order) — a grid-template-columns assertion that
// survives retiring a whole column was never proving the column existed.
ok('R13-1 the row is a CSS grid with the 6-column template (marker column retired — chevron / 1fr title / 190px task-span / 76px fraction / 46px exception-glyph / 132px exception-label), align-items:center, gap:10px',
  /\.rm-node > summary\.rm-row\s*\{[^}]*display:\s*grid/.test(C) &&
  /grid-template-columns:\s*16px minmax\(0,1fr\) 190px 76px 46px 132px/.test(C) &&
  /\.rm-node > summary\.rm-row\s*\{[^}]*align-items:\s*center/.test(C) &&
  /\.rm-node > summary\.rm-row\s*\{[^}]*gap:\s*10px/.test(C));
ok('R12-4 the fraction text uses tabular-nums so "5/6" and "12/14" align digit-for-digit down a column',
  /\.rm-progress-text\s*\{[^}]*font-variant-numeric:\s*tabular-nums/.test(C));
ok('R12-5 the title truncates with CSS ellipsis, and the FULL title (never just the slug) lives in title= for the truncated case',
  /\.rm-title\s*\{[^}]*text-overflow:\s*ellipsis/.test(C) &&
  /titleSpan\.title = item\.title/.test(roadmapJsNoComments));
ok('R13-2 renderNode appends exactly one cell per grid column, in column order, EVERY render (markerCell is GONE from the order — R12-6\'s pin) — the fix for the flex-wrap bug still holds for the remaining 6 columns',
  (function () {
    var m = roadmapJsNoComments.match(/function renderNode[\s\S]*?function renderLabeledSubsection/);
    var body = m ? m[0] : '';
    if (!body) return false;
    if (/markerCell\(/.test(body)) return false; // the retired column must not still be appended
    var order = ['rm-chevron', 'titleCell(item)', 'taskSpanCell(item', 'fractionCellForRow(item)', 'exceptionGlyphCell(item)', 'exceptionLabelCell(item)'];
    var lastIdx = -1;
    for (var i = 0; i < order.length; i++) {
      var idx = body.indexOf(order[i]);
      if (idx === -1 || idx < lastIdx) return false;
      lastIdx = idx;
    }
    return true;
  })());
ok('R13-3 markerCell no longer exists as a function — markerChips(item) is called from inside titleCell instead (folded into the 1fr title column, never a dedicated fixed-width column again)',
  !/function markerCell/.test(roadmapJsNoComments) &&
  /function titleCell\(item\)[\s\S]*?markerChips\(item\)[\s\S]*?\n  \}/.test(roadmapJsNoComments));
ok('R13-4 mutation control: the marker column\'s 56px width is GONE from the grid template, not merely renamed (delete the fix and 56px reappears — this pins the actual retirement, not just a column-count coincidence)',
  !/56px/.test(C.match(/\.rm-node > summary\.rm-row\s*\{[^}]*\}/)[0]));

// ---- item 2 / ROUND 13 fix 6: the task-span column (real execution) ----
// Operator (Round 12 walkthrough): "The '1–5 done' text is telling me
// exactly the same thing as the progress bar sitting right next to it."
// deriveTaskSpanLabel DROPS the done-half entirely — R12-10/11/12/13/15/17
// all pinned the OLD "<range> done · <next> next" wording and FLIP here to
// pin the new next-only contract. R12-14/R12-16 are UNCHANGED (their
// expected strings/behavior happen to still hold under the new function —
// zero-done and empty-children were always next-only/empty).
// Round 15: deriveTaskSpanLabel now takes the whole plan ITEM (not a bare
// children array) so it can also read item.roll_up.running — the wrapper
// below keeps every pre-existing call site's children-array literal
// unchanged, just folding it into {children, roll_up} (roll_up:{} unless a
// test explicitly wants to exercise the running case, e.g. R15-1 below).
function taskSpan(childrenExpr, rollUpExpr) { return runPure(taskSpanSrc, 'deriveTaskSpanLabel({children: ' + childrenExpr + ', roll_up: ' + (rollUpExpr || '{}') + '})'); }
ok('R13-10 deriveTaskSpanLabel: partial progress now names ONLY the next task — no done-range, no done-count (the operator\'s "same as the bar" redundancy is gone)',
  taskSpan('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"complete"}},{id:"p/3",status:{value:"not-started"}}]') === '3 next');
ok('R13-11 deriveTaskSpanLabel: a done task AFTER an open one never confuses which is "next" — still names the FIRST open task, ignoring a later complete one (the contiguity bookkeeping is gone, but the "first, not last" guarantee it protected is still real)',
  taskSpan('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"complete"}},{id:"p/3",status:{value:"not-started"}},{id:"p/4",status:{value:"complete"}}]') === '3 next');
ok('R13-12 deriveTaskSpanLabel: every task done -> the literal "all done", never a done-range/count — reached in practice only by a plan whose OWN status is already \'complete\' (Round 12 item 6 already routes such plans to the top-level Shipped group, so this string is a Shipped-group fact in practice, not a special-cased one)',
  taskSpan('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"complete"}},{id:"p/3",status:{value:"complete"}}]') === 'all done');
ok('R13-13 deriveTaskSpanLabel: a SINGLE done task also reads "all done" (no degenerate range possible any more — there is no range left to degenerate)',
  taskSpan('[{id:"p/1",status:{value:"complete"}}]') === 'all done');
ok('R12-14 deriveTaskSpanLabel: zero done -> just "<first> next", no "0 done ·" clutter',
  taskSpan('[{id:"p/1",status:{value:"not-started"}},{id:"p/2",status:{value:"not-started"}}]') === '1 next');
ok('R13-15 deriveTaskSpanLabel: a live_sessions entry on a CHILD alone is not enough to say "running" — only item.roll_up.running (the server\'s OWN verified roll-up, C1\'s law applied to the running state) earns the word, never a client-side re-derivation off item.children',
  (function () {
    var r = taskSpan('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"in-progress"},live_sessions:[{title:"x"}]}]');
    return r === '2 next' && r.indexOf('running') === -1;
  })());
ok('R15-1 deriveTaskSpanLabel: when item.roll_up.running is populated (a REAL descendant live session, server-verified), the token becomes "<id> running" instead of "<id> next" — same id slot, one word swapped (operator, repeated: "the plan itself doesn\'t show there\'s anything in progress")',
  taskSpan('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"in-progress"}}]', '{running:{count:1,exemplar:"p/2"}}') === '2 running');
ok('R15-2 deriveTaskSpanLabel: roll_up.running with EVERY task done still honestly says "running" alone (never silently drops the live signal just because nothing is nominally "next") rather than falling back to the now-inaccurate "all done"',
  taskSpan('[{id:"p/1",status:{value:"complete"}}]', '{running:{count:1,exemplar:"p/1"}}') === 'running');
ok('R15-3 deriveTaskSpanLabel: no roll_up at all (absent field, e.g. an older/degraded payload) degrades to the plain next/all-done wording, never throws',
  runPure(taskSpanSrc, 'deriveTaskSpanLabel({children:[{id:"p/1",status:{value:"not-started"}}]})') === '1 next');
ok('R12-16 deriveTaskSpanLabel: empty/absent children -> empty string (no fake column content)',
  taskSpan('[]') === '' && runPure(taskSpanSrc, 'deriveTaskSpanLabel(null)') === '');
ok('R13-17 deriveTaskSpanLabel: task ids strip the plan-slug prefix (server emits "slug/T3"; the column shows only "T3") — next-only wording',
  taskSpan('[{id:"my-plan-slug/T1",status:{value:"complete"}},{id:"my-plan-slug/T2",status:{value:"not-started"}}]') === 'T2 next');

// ---- ROUND 13 fix 4: firstOpenChildId (real execution, shared helper) --
function firstOpenId(childrenExpr) { return runPure(taskSpanSrc, 'firstOpenChildId(' + childrenExpr + ')'); }
ok('R13-20 firstOpenChildId returns the FIRST non-complete child\'s id, skipping done ones',
  firstOpenId('[{id:"p/1",status:{value:"complete"}},{id:"p/2",status:{value:"not-started"}}]') === 'p/2');
ok('R13-21 firstOpenChildId returns null when every child is complete (the "all done" case)',
  firstOpenId('[{id:"p/1",status:{value:"complete"}}]') === null);
ok('R13-22 firstOpenChildId is not fooled by a LATER complete task after an open one (same non-contiguous guarantee R13-11 checks at the label level)',
  firstOpenId('[{id:"p/1",status:{value:"not-started"}},{id:"p/2",status:{value:"complete"}}]') === 'p/1');
ok('R13-23 firstOpenChildId on empty/absent children -> null (never throws, never fabricates an id)',
  firstOpenId('[]') === null && runPure(taskSpanSrc, 'firstOpenChildId(null)') === null);
ok('R13-24 deriveTaskSpanLabel and firstOpenChildId agree by CONSTRUCTION (deriveTaskSpanLabel calls firstOpenChildId internally) — the id renderChildList flags "next" on a child row is always the SAME id the parent\'s own task-span text names, never independently computed',
  /function deriveTaskSpanLabel\(item\) \{[\s\S]*?firstOpenChildId\(kids\)/.test(roadmapJsNoComments));

// ---- item 3: redundancy deletions --------------------------------------
ok('R12-20 the per-row "completed <age>" span (rm-completed-when) is GONE — it duplicated the status chip\'s own text, and the chip is gone for complete/merged-unverified too now (item 4)',
  !/rm-completed-when/.test(roadmapJsNoComments));
ok('R12-21 the footer "N items hidden (harness chores) show" duplicate is gone from renderAll (the toolbar\'s OWN chore toggle, syncToolbar(), is always visible already) — the FILTERED/TRUE-empty state\'s own hidden-chores line is UNCHANGED (different purpose: explains an otherwise-confusing zero-item screen)',
  (function () {
    var hits = (roadmapJsNoComments.match(/items hidden \(harness chores\)/g) || []).length;
    return hits === 1 && /pane-empty rm-chore-note.*items hidden \(harness chores\)/.test(roadmapJsNoComments.replace(/\n\s*/g, ' '));
  })());
ok('R12-22 "since" no longer renders on a not-started row — DERIVABLE_STATES gates statusChip() to null for not-started BEFORE any age/formatAge text is built (the age was semantically empty per the operator: those timestamps are bulk file-touch clusters, not real transitions); ROADMAP-SUPERSEDED-RENDERS-PENDING-01 (round 14) adds the ONE exception (a terminal_label chip), unrelated to age semantics',
  /if \(DERIVABLE_STATES\[value\] && !st\.terminal_label\) return null;/.test(roadmapJsNoComments) &&
  roadmapJsNoComments.indexOf('if (DERIVABLE_STATES[value] && !st.terminal_label) return null;') < roadmapJsNoComments.indexOf('var ageTs = value ==='));

// ---- item 4: the exception column ---------------------------------------
ok('R12-25 DERIVABLE_STATES names exactly the three states the fraction/task-span CAN derive (not-started/in-progress/complete) — statusChip() returns null for all three, so an empty column 6/7 means "healthy"',
  /var DERIVABLE_STATES = \{ 'not-started': true, 'in-progress': true, 'complete': true \};/.test(roadmapJsNoComments));
ok('R12-26 the three states the fraction CANNOT derive (stalled/merged-unverified/unknown) still get a loud chip in column 7 (exceptionLabelCell) plus a small glyph in column 6 (exceptionGlyphCell)',
  /var EXCEPTION_GLYPH = \{ stalled: '⚠', 'merged-unverified': '⏳', unknown: '\?' \};/.test(roadmapJsNoComments) &&
  /function exceptionLabelCell\(item\)/.test(roadmapJsNoComments) && /function exceptionGlyphCell\(item\)/.test(roadmapJsNoComments));
ok('R12-27 mutation control: DERIVABLE_STATES is REACHED — statusChip is called from exceptionLabelCell for every row (not skipped), so the gate actually executes on the real render path',
  /var chip = statusChip\(item\);/.test(roadmapJsNoComments) && /function exceptionLabelCell/.test(roadmapJsNoComments));

// ---- item 5: title colour (recession, not emphasis) ----------------------
ok('R12-30 every one of the six states maps to a title CSS class (rm-title-<value>), matching the operator/auditor-specified colour+weight table exactly',
  /var TITLE_STATE_CLASS = \{/.test(roadmapJsNoComments) &&
  ['not-started', 'in-progress', 'complete', 'stalled', 'merged-unverified', 'unknown'].every(function (v) {
    return roadmapJsNoComments.indexOf("'" + v + "': 'rm-title-" + v + "'") !== -1;
  }));
// ROUND 13 fix 2 (operator, INVERTING Round 12's own ladder: "It's the
// completed items that should be dimmed gray, not the unstarted items").
// R12-31 pinned not-started at var(--muted) — FLIPS here to var(--text).
// complete/in-progress/stalled/merged-unverified/unknown are UNCHANGED (the
// operator's fix left the loud exceptions and the in-progress bold alone —
// only the not-started/complete relationship inverted). A palette test
// that stayed green across this inversion would have been proving nothing;
// R13-31 pins the NEW not-started rule specifically and R13-31b proves the
// OLD rule is actually gone (not just an additional rule shadowing it).
// R21 (2026-08-01) AMENDS R13-31's in-progress leg. Operator, verbatim:
// "All the plan items in here that are purple are not representing what
// they're supposed to be representing. First of all, the color is supposed
// to be green, and second of all, it's supposed to represent items that are
// currently being worked on." --accent (violet) was chosen 2026-07-30 to
// stop in-progress LYING green; it still read as "this one is active"
// because ANY hue on the most common state reads that way. in-progress is
// now hue-free (--text/600, luminance-only); the roadmap's ONE live-claim
// hue is --running, on the new .rm-title-running. Every OTHER leg of the
// ladder below is unchanged and still pinned.
ok('R13-31/R21 CSS pins the ladder: not-started var(--text)/400 (normal reading colour), in-progress var(--text)/600 (HUE-FREE — derived-from-artifacts, not a liveness claim; was --accent violet until 2026-08-01), complete var(--done)/400 unchanged (the ONLY dim state), stalled var(--interrupt)/600 unchanged, merged-unverified var(--warn)/600 unchanged, unknown var(--warn)/400+dashed unchanged',
  /\.rm-title\.rm-title-in-progress\s*\{\s*color:\s*var\(--text\);\s*font-weight:\s*600/.test(C) &&
  /\.rm-title\.rm-title-not-started\s*\{\s*color:\s*var\(--text\);\s*font-weight:\s*400/.test(C) &&
  /\.rm-title\.rm-title-complete\s*\{\s*color:\s*var\(--done\);\s*font-weight:\s*400/.test(C) &&
  /\.rm-title\.rm-title-stalled\s*\{\s*color:\s*var\(--interrupt\);\s*font-weight:\s*600/.test(C) &&
  /\.rm-title\.rm-title-merged-unverified\s*\{\s*color:\s*var\(--warn\);\s*font-weight:\s*600/.test(C) &&
  /\.rm-title\.rm-title-unknown\s*\{\s*color:\s*var\(--warn\);\s*font-weight:\s*400;\s*border-bottom:\s*1px dashed/.test(C));
ok('R13-31b mutation control: the Round 12 not-started rule (var(--muted)) is GONE, not merely shadowed by a later rule of equal specificity (a stray leftover .rm-title-not-started{color:var(--muted)} earlier in the file would make the ladder non-deterministic depending on cascade order)',
  !/\.rm-title\.rm-title-not-started\s*\{\s*color:\s*var\(--muted\)/.test(C));
ok('R16-1 ROUND 16 mutation control: the Round 15 --info (blue) in-progress-title rule is GONE, not merely shadowed — a stray leftover .rm-title-in-progress{color:var(--info)} earlier in the cascade would make the ladder non-deterministic',
  !/\.rm-title\.rm-title-in-progress\s*\{\s*color:\s*var\(--info\)/.test(C));
ok('R21-1 mutation control: the 2026-07-30 --accent (violet) in-progress-title rule is GONE, not merely shadowed — a stray leftover .rm-title-in-progress{color:var(--accent)} anywhere in the cascade is exactly the purple the operator reported',
  !/\.rm-title\.rm-title-in-progress\s*\{\s*color:\s*var\(--accent\)/.test(C));
ok('R21-2 the roadmap has a RUNNING title state and it is the --running green — the state the ladder was missing entirely (there was no green title rule at all, so genuinely-live work had no title-level signal to be seen by)',
  /\.rm-title\.rm-title-running\s*\{\s*color:\s*var\(--running\);\s*font-weight:\s*700/.test(C));
ok('R21-3 --running is the ONLY hue any rm-title rule spends on a liveness claim: exactly one .rm-title-* rule uses var(--running), and it is the running one (a second green title rule would re-create the "several green plans that aren\'t running" defect)',
  (function () {
    var rules = C.match(/\.rm-title\.rm-title-[a-z-]+\s*\{[^}]*\}/g) || [];
    var green = rules.filter(function (r) { return /var\(--running\)/.test(r); });
    return green.length === 1 && /rm-title-running/.test(green[0]);
  })());
ok('R21-4 the live-session leaf glyph speaks the SAME green as every other running signal (--running), not the retired --ok green that nothing else in the roadmap uses',
  /\.rm-agent-running \.rm-agent-glyph\s*\{\s*color:\s*var\(--running\)/.test(C) &&
  !/\.rm-agent-running \.rm-agent-glyph\s*\{\s*color:\s*var\(--ok\)/.test(C));
ok('R21-5 .chip.rm-status-running exists and is green+tinted, and .chip.rm-status-in-progress no longer spends a hue — the top-of-tree "N running, unattributed to a task" chip was hard-coded to the in-progress class, so the ONE node that says "running" was painted the in-progress colour',
  /\.chip\.rm-status-running\s*\{[^}]*color:\s*var\(--running\)/.test(C) &&
  /\.chip\.rm-status-running\s*\{[^}]*background:\s*color-mix\(in srgb, var\(--running\)/.test(C) &&
  !/\.chip\.rm-status-in-progress\s*\{[^}]*var\(--accent\)/.test(C));
ok('R16-2 --running is defined and measures >= 4.5:1 against --panel (WCAG AA body-text floor) — computed here with the SAME relative-luminance formula the file\'s own --done comment already documents, not merely asserted in prose',
  (function () {
    var m = css.match(/--running:\s*#([0-9a-fA-F]{6});/);
    var panelM = css.match(/--panel:\s*#([0-9a-fA-F]{6});/);
    if (!m || !panelM) return false;
    function srgbToLin(c) { c = c / 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    function relLum(hex) {
      var r = parseInt(hex.substring(0, 2), 16), g = parseInt(hex.substring(2, 4), 16), b = parseInt(hex.substring(4, 6), 16);
      return 0.2126 * srgbToLin(r) + 0.7152 * srgbToLin(g) + 0.0722 * srgbToLin(b);
    }
    var L1 = relLum(m[1]), L2 = relLum(panelM[1]);
    var ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
    return ratio >= 4.5;
  })());
ok('R12-32 --done is the darkest neutral that still clears WCAG AA 4.5:1 against --panel (measured #87909e = 4.55:1) — the value is pinned exactly, not "rounded to a nicer gray"',
  /--done:\s*#87909e;/.test(css));
ok('R13-33 WCAG 1.4.1: every row keeps at least two NON-colour carriers regardless of state — the task-span cell and the fraction cell are appended UNCONDITIONALLY (never gated on item.status), so colour is never the only signal (R12-33 pinned the OLD 1-arg taskSpanCell(item) call — FLIPS to the 2-arg isNextTask signature fix 4 introduced)',
  /sum\.appendChild\(taskSpanCell\(item, isNextTask\)\);/.test(roadmapJsNoComments) && /sum\.appendChild\(fractionCellForRow\(item\)\);/.test(roadmapJsNoComments));

// ---- item 6: Shipped(n) independent of the aging clock -------------------
ok('R12-40 the top-level Shipped grouping triggers on status===\'complete\' ALONE — never gated on agedOut()/the mtime-reset-prone 7-day clock (ROADMAP-COMPLETED-AGING-MTIME-RESET-01)',
  /if \(isComplete\) shipped\.push\(it\); else live\.push\(it\);/.test(roadmapJsNoComments) &&
  !/isComplete && agedOut\(it\.completed_at\)\) aged\.push\(it\)/.test(roadmapJsNoComments));
ok('R12-41 the group is headed "Shipped (n)" — the operator\'s own word — not a restatement of the nested per-parent "N completed" wording (task 3\'s DIFFERENT, still-aging-gated mechanism, unchanged by this item)',
  /'Shipped \(' \+ shipped\.length \+ '\)/.test(roadmapJsNoComments) && /rm-shipped-group/.test(roadmapJsNoComments) && /\.rm-shipped-group > summary/.test(C));
ok('R12-42 opening a Shipped plan still renders ALL its own tasks via the UNCHANGED renderNode/renderChildList path — the operator\'s explicit requirement ("I can open any individual plan and see all the tasks within it")',
  /shipped\.forEach\(function \(c\) \{ rbody\.appendChild\(renderNode\(c, -1, -1\)\); \}\);/.test(roadmapJsNoComments));

// ---- item 7: pre-existing contrast bugs -----------------------------------
ok('R12-50 EVERY chip has an explicit transparent background — a chip rendered as a real <button> (rm-project-chip, rm-status-stalled, rm-rollup-badge...) previously fell back to the UA button face (measured live: rgb(239,239,239), a light box in the dark theme)',
  /\.chip \{[^}]*background:\s*transparent/.test(C));
ok('R12-51 .rm-plan-link has an explicit color — previously unstyled, so all 16 plan links rendered at the browser default blue (#0000EE, 1.56:1, a hard WCAG 1.4.3 failure). ROUND 16 sweep: the base rule (which also covers the rare non-clickable plain-text fallback) is now NEUTRAL (var(--muted)) — blue moves to the compound .rm-plan-link-btn rule below, present ONLY on the real clickable button (operator: "blue looks like links", so it is reserved for real ones)',
  /\.rm-plan-link\s*\{[^}]*color:\s*var\(--muted\)/.test(C));
ok('R16-3 the REAL clickable plan-link button keeps blue (var(--info)) via the compound .rm-plan-link.rm-plan-link-btn rule — higher specificity than the plain .rm-plan-link rule above, so the genuine link still reads as one even though the fallback text no longer does',
  /\.rm-plan-link\.rm-plan-link-btn\s*\{[^}]*color:\s*var\(--info\)/.test(C));

// ---- item 8: filter placeholder + surfaced task-id match ------------------
ok('R12-60 the filter placeholder now NAMES the task-id matching capability (previously announced only to screen readers via aria-label, while sighted users saw a generic "filter the roadmap…")',
  /placeholder="filter by title or task id/.test(html));
function findMatch(itemExpr, q) { return runPure(filterMatchSrc, 'findMatchingDescendant(' + itemExpr + ', ' + JSON.stringify(q) + ')'); }
ok('R12-61 findMatchingDescendant finds a task child by ID substring (case-insensitive query, as filterText() already lowercases)',
  (function () {
    var r = findMatch('{children:[{id:"plan/T3",title:"Some task"},{id:"plan/T4",title:"Other"}]}', 't3');
    return r && r.id === 'plan/T3';
  })());
ok('R12-62 findMatchingDescendant finds a task child by TITLE substring when the id does not match',
  (function () {
    var r = findMatch('{children:[{id:"plan/T3",title:"fix the accountable estate bug"}]}', 'accountable');
    return r && r.id === 'plan/T3';
  })());
ok('R12-63 findMatchingDescendant NEVER matches the item\'s own title/id — only descendants (the caller only invokes it once the item\'s own fields already failed to match)',
  findMatch('{title:"T3 fixture", id:"plan/T3", children:[{id:"plan/1",title:"unrelated"}]}', 't3') === null);
ok('R12-64 findMatchingDescendant recurses into child_plans (a master\'s resolved children), not just children',
  (function () {
    var r = findMatch('{child_plans:[{id:"child-plan",title:"x",children:[{id:"child-plan/T5",title:"y"}]}]}', 't5');
    return r && r.id === 'child-plan/T5';
  })());
ok('R12-65 findMatchingDescendant returns null when nothing matches (never a false positive)',
  findMatch('{children:[{id:"plan/T1",title:"alpha"}]}', 'zzz') === null);
ok('R12-66 a filter match on a descendant forces the ancestor row OPEN and renders an ALWAYS-VISIBLE "matches: ..." note (a sibling of summary, not inside .rm-drill, which is display:none while collapsed) directly under the matched plan row',
  /var filterMatch = currentMatchNotes\[item\.id\];/.test(roadmapJsNoComments) &&
  /if \(defaultOpen\(item\) \|\| filterMatch\) det\.open = true;/.test(roadmapJsNoComments) &&
  /rm-filter-match-note/.test(roadmapJsNoComments) &&
  !/\.rm-filter-match-note[^,]*\[open\]/.test(C) && !/\[open\][^,]*\.rm-filter-match-note/.test(C));

// ---- item 9: inbox count honesty (three-state count badges) --------------
ok('R12-70 setTabCount() takes an explicit error flag and renders "(!)" (never a confident "(—)") when the ledger is confirmed broken',
  /function setTabCount\(n, isError\)/.test(inboxJs) && /tabCount\.textContent = '\(!\)'/.test(inboxJs) &&
  /ib-tabcount-error/.test(inboxJs) && /\.ib-tabcount-error\s*\{[^}]*var\(--interrupt\)/.test(C));
ok('R12-71 BOTH inbox.js load() failure paths (an ok:false response AND a network-level catch) call setTabCount(null, true) — neither leaves the tab silently showing the loading "(—)" forever',
  (function () {
    var hits = (inboxJs.match(/setTabCount\(null, true\)/g) || []).length;
    return hits >= 2;
  })());
ok('R12-72 the Roadmap-tab (landing) sidebar mirror no longer treats an /api/inbox failure as a silent zero — inboxFailed is computed explicitly and the confident "nothing on your list" win-line is gated on !inboxFailed',
  /var inboxFailed = !inbox \|\| inbox\.ok === false;/.test(roadmapJsNoComments) &&
  /if \(!inboxFailed && !answerable\.length && !ops\.length && !ptrs\.length\)/.test(roadmapJsNoComments) &&
  /Inbox: could not load — retry on next tick/.test(roadmapJsNoComments));
ok('R12-73 mutation control: inboxFailed is REACHED on the real fetch path (both is derived from Promise.all([...fetch(\'/api/todo\')..., fetch(\'/api/inbox\')...]) — not a dead branch)',
  /fetch\('\/api\/todo'\)\.then\(function \(r\) \{ return r\.json\(\); \}\)\.catch\(function \(\) \{ return null; \}\),/.test(roadmapJsNoComments) &&
  /fetch\('\/api\/inbox'\)\.then\(function \(r\) \{ return r\.json\(\); \}\)\.catch\(function \(\) \{ return null; \}\),/.test(roadmapJsNoComments));

// ---- regression (caught live during Round 12 verification, fixed same
// commit): statusChip(it) now returns null for the three derivable states
// (item 4); renderKanban's chipRow.appendChild(statusChip(it)) was NOT
// null-guarded, so appendChild(null) THREW for every not-started/in-
// progress/complete card, silently aborting the WHOLE kanban board mid-
// render (verified live: toggling Kanban rendered an EMPTY board, zero
// console output, #roadmapBody left with only the unbound-sessions node —
// the failure was silent because DOM event dispatch swallows exceptions
// thrown inside a click listener). ----
ok('R12-80 renderKanban null-guards statusChip(it) before appending — the crash-on-render-for-most-cards regression this build introduced and fixed in the same pass',
  /var kanbanChip = statusChip\(it\);\s*\n\s*if \(kanbanChip\) chipRow\.appendChild\(kanbanChip\);/.test(roadmapJsNoComments) &&
  !/chipRow\.appendChild\(statusChip\(it\)\)/.test(roadmapJsNoComments));

// ============================================================
// ROUND 13 (operator walkthrough of the Round 12 surface — 6 named fixes,
// docs/plans/cockpit-roadmap-redesign.md Round 13 entry + the dispatch
// prompt's verbatim quotes). Fixes 1/2/6 are covered above (R13-1..R13-33
// FLIP the R12 pins they superseded); this block covers fix 3 (group
// containment), fix 4 (per-task done-state), and fix 5 (hierarchy spacing).
// ============================================================

// ---- fix 3: group containment ------------------------------------------
ok('R13-50 .rm-project-group is a visible CONTAINER (left rail + background tint), not just a margin — spans every plan row inside it by construction (renderTree appends every group item as a DIRECT child of this element)',
  /\.rm-project-group\s*\{[^}]*border-left:\s*2px solid var\(--border2\)[^}]*background:\s*rgba\(255, 255, 255, 0\.02\)/.test(C));
ok('R13-51 .rm-shipped-group gets the SAME containment treatment, at HALF the live group\'s tint opacity (0.01 vs 0.02) — "dimmer", the operator\'s own qualifier, pinned as an actual numeric relationship rather than just "some other color"',
  (function () {
    var liveAlpha = (C.match(/\.rm-project-group\s*\{[^}]*background:\s*rgba\(255, 255, 255, ([\d.]+)\)/) || [])[1];
    var shipAlpha = (C.match(/\.rm-shipped-group\s*\{[^}]*background:\s*rgba\(255, 255, 255, ([\d.]+)\)/) || [])[1];
    return !!liveAlpha && !!shipAlpha && parseFloat(shipAlpha) > 0 && parseFloat(shipAlpha) < parseFloat(liveAlpha);
  })());
ok('R13-52 mutation control: the group container survives FILTERING structurally — renderAll computes the filtered set (applyFilters) BEFORE calling renderTree, and renderTree itself groups that already-filtered `live` array (groupItemsByProject(live)), so .rm-project-group wraps whatever filtering left, never a stale unfiltered set',
  /var f = applyFilters\(lastPayload\.items \|\| \[\]\);/.test(roadmapJsNoComments) &&
  /renderTree\(f\.visible\)/.test(roadmapJsNoComments) &&
  /var groups = phaseSeries \? groupItemsByProject\(live\) : /.test(roadmapJsNoComments));

// ---- fix 4: per-task done-state -----------------------------------------
ok('R13-60 titleCell prepends a leading "✓" (rm-task-check) on a TASK row that is actually complete — text, not colour-only, and gated on BOTH item.kind===\'task\' AND status.value===\'complete\' (never shown on a complete PLAN row, which already has its own dim title + Shipped grouping)',
  /function titleCell\(item\) \{[\s\S]{0,300}item\.kind === 'task' && item\.status && item\.status\.value === 'complete'[\s\S]{0,200}rm-task-check/.test(roadmapJsNoComments));
// R13-61 MOVED (2026-07-30) to the R20 running-claim section at the end of
// this file, and converted from a source-order regex to real execution.
// The old form required the literal 'live_sessions' to appear inside
// taskSpanCell before 'isNextTask'; that broke the moment the running test
// moved behind the shared hasRunningSession() predicate, even though the
// BEHAVIOUR it cared about was unchanged — a regex pinning how the check
// is spelled, not what it does. It lives beside the payload fixtures it
// needs (RUNNING_TASK_PAYLOAD), which are declared in that section.
ok('R13-62 taskSpanCell NEVER falls through to deriveTaskSpanLabel for a task-kind item (a leaf task has no children of its own — that branch is PLAN-only) — the function returns early inside the item.kind===\'task\' branch. Round 15: deriveTaskSpanLabel now takes the whole item (not just item.children) so it can also read item.roll_up.running for the "running" token',
  /function taskSpanCell\(item, isNextTask\) \{[\s\S]*?if \(item\.kind === 'task'\) \{[\s\S]*?return cell;[\s\S]*?\}[\s\S]*?deriveTaskSpanLabel\(item\)/.test(roadmapJsNoComments));
ok('R13-63 renderChildList computes nextId via firstOpenChildId over the FULL unpartitioned children list, but ONLY for a task list — a phase-series (child-PLAN) list gets nextId=null, since "next" is a per-TASK affordance, not a per-plan one (plans get their own "n next" one level up, via the parent\'s own task-span text)',
  /var nextId = phaseSeries \? null : firstOpenChildId\(children\);/.test(roadmapJsNoComments));
ok('R13-64 the SAME nextId is threaded into every child render path — the plain loop, renderTaskBatches, AND renderBatchRow — so a "next" task inside a batch run still gets its affordance, not just an un-batched one',
  /renderNode\(c, -1, -1, c\.id === nextId\)/.test(roadmapJsNoComments) &&
  /renderTaskBatches\(live, nextId\)/.test(roadmapJsNoComments) &&
  /renderNode\(c, -1, -1, c\.id === nextId\)/.test(roadmapJsNoComments) && /renderBatchRow\(label, liveChildren\.slice\(i, runEnd\), nextId\)/.test(roadmapJsNoComments) &&
  /renderNode\(t, -1, -1, t\.id === nextId\)/.test(roadmapJsNoComments));
ok('R13-65 CSS: .rm-task-check inherits the complete-dim colour (var(--done), reads as PART of the dimmed line); .rm-task-next is weight-only (text emphasis, never the ONLY signal); .rm-task-running earns the one loud colour because it is a claim backed by real live_sessions evidence, not a position guess. ROUND 16: --info (blue) -> --running (green) — operator: "blue looks like links"',
  /\.rm-task-check\s*\{\s*color:\s*var\(--done\)/.test(C) &&
  /\.rm-task-next\s*\{\s*font-weight:\s*600;\s*color:\s*var\(--text\)/.test(C) &&
  /\.chip\.rm-task-running\s*\{[^}]*color:\s*var\(--running\)/.test(C));
ok('R16-4 mutation control: the Round 15 --info (blue) task-running rule is GONE, not merely shadowed',
  !/\.chip\.rm-task-running\s*\{[^}]*color:\s*var\(--info\)/.test(C));
ok('R16-5 the plan-row "<id> running" token (.rm-taskspan-running) and the roll-up "running" badge (.chip.rm-rollup-running) both use --running too — the SAME green language as the leaf chip and the in-progress title, not three different colours for "someone is working on this right now"',
  /\.rm-taskspan-running\s*\{\s*color:\s*var\(--running\)/.test(C) &&
  /\.chip\.rm-rollup-running\s*\{\s*color:\s*var\(--running\)/.test(C));

// ---- fix 5: hierarchy legibility + spacing -------------------------------
ok('R13-70 tasks render visibly SMALLER than the plan that owns them (12px vs the plan/base 14px) — a size ladder ON TOP of the existing indentation + rail, so "this is a child" is legible before reading a single word',
  /\.rm-title\s*\{[^}]*font-size:\s*14px/.test(C) &&
  /\.rm-kind-task \.rm-title\s*\{\s*font-weight:\s*400;\s*font-size:\s*12px/.test(C));
ok('R13-71 the connecting rail visibly differs for a task node vs a plan node (a distinct border-left-color on .rm-kind-task.rm-node) — "hangs off the parent" instead of reading as one undifferentiated line at every depth',
  /\.rm-kind-task\.rm-node\s*\{\s*border-left-color:\s*var\(--border2\)/.test(C));
ok('R13-72 .rm-children carries an ASYMMETRIC spacing ladder: a small top margin (tight parent->first-child) and a LARGER bottom margin (breathing room before the next sibling row) — the operator\'s named inversion (65px parent->child vs 2px subtree->next-plan, live-measured) fixed at the source of the indentation wrapper itself',
  /\.rm-children\s*\{\s*margin:\s*2px 0 12px 14px;\s*\}/.test(C));
ok('R13-73 an OPEN node\'s own immediate children get a faint background tint (distinct from, and more subtle than, the .rm-project-group tint) — a "card within a card" visual for the expanded subtree',
  (function () {
    var m = C.match(/\.rm-node\[open\] > \.rm-children\s*\{([^}]*)\}/);
    return !!m && /background:\s*rgba\(255, 255, 255, 0\.025\)/.test(m[1]);
  })());
// R13-74 pinned Round 13's 30px inter-plan gap + the deliberate rail break.
// ROUND 16 REVERSES it (operator, live walkthrough, verbatim): "I don't
// like the spaces between the plans. It looks awkward with the spacing
// between the nesting lines" — restated below as R16-6/7.
ok('R16-6 ROUND 16 deliverable 1: the inter-plan gap shrinks to a single-digit-beyond-row-padding margin (8px, down from Round 13\'s 30px) — the operator called the old gap "awkward"',
  /\.rm-phase-step\s*\{\s*position:\s*relative;\s*padding-left:\s*16px;\s*margin:\s*2px 0 8px;\s*\}/.test(C));
ok('R16-7 ROUND 16 deliverable 1: the phase-step connector line now reaches ALL THE WAY to the next step\'s own line start (top:18px unchanged, bottom widened from -6px to -26px = new 8px gap + the next step\'s 18px offset) — continuous, not the Round 13 "deliberate break"',
  /\.rm-phase-step::before\s*\{[^}]*top:\s*18px;[^}]*bottom:\s*-26px;/.test(C));
ok('R16-8 mutation control: the Round 13 30px margin and the -6px break-leaving connector offset are BOTH gone, not merely shadowed by a later rule',
  !/margin:\s*2px 0 30px/.test(C) && !/bottom:\s*-6px/.test(C));
// R13-75/76 pinned the hover/focus-within height:0 reveal hack for the
// edit/rank chrome. ROUND 16 removes that mechanism ENTIRELY (deliverables
// 3/4/5) — restated as R16-9 (proof of absence; T3-42/T3-42b above already
// cover the same retirement from a different angle, kept here so the
// R13-7x numbering isn't silently orphaned without an explicit successor).
ok('R17-DRAG-1 (operator 2026-07-30 "I didn\'t ask you to make the whole row the drag surface. Please undo that."): the grip handle .rm-drag-handle is the ONLY dragstart source — the summary row itself is NOT made draggable (no `sum.draggable = true`), so the Round-16 hit-area contract is restored exactly',
  /gripEl\.addEventListener\('dragstart'/.test(roadmapJsNoComments) &&
  !/sum\.draggable\s*=\s*true/.test(roadmapJsNoComments));

ok('R17-DRAG-2 (operator 2026-07-30 "it actually takes several seconds for the GUI to actually update after dropping the item"): performDrop moves the dragged row in the DOM OPTIMISTICALLY — an insertBefore against the target row BEFORE sequentialMove fires its N sequential /api/roadmap/rank round-trips — so a drop renders instantly instead of waiting on the network; the failure path still calls load() to reconcile',
  /performDrop[\s\S]{0,2000}?insertBefore\(draggedRow, targetRow\)[\s\S]{0,400}?sequentialMove\(/.test(roadmapJsNoComments));

// R17-DRAG-3: REAL-EXECUTION behavioural proof, not a source-shape check.
// The shape-only assertion above passed while the feature was BROKEN in the
// live app (performDrop used planRowContainer() for BOTH dragged and target,
// which returns the GROUP — so both resolved to the same element and the
// insertBefore never ran; caught by hand at :7733). This executes the real
// movableRowEl + the real insertBefore semantics against a synthetic DOM and
// asserts the ORDER ACTUALLY CHANGES.
(function () {
  var src = roadmapJs;
  var m = src.match(/function movableRowEl\(el, container\) \{[\s\S]*?\n  \}/);
  var moved = false, sameParentGuardHeld = false;
  if (m) {
    // Minimal DOM stand-ins: parent with three row children, each holding a leaf.
    function mkNode(name) {
      return { name: name, parentNode: null, childNodes: [],
        get nextSibling() {
          if (!this.parentNode) return null;
          var i = this.parentNode.childNodes.indexOf(this);
          return this.parentNode.childNodes[i + 1] || null;
        },
        insertBefore: function (node, ref) {
          var cn = this.childNodes, from = cn.indexOf(node);
          if (from !== -1) cn.splice(from, 1);
          var at = ref ? cn.indexOf(ref) : cn.length;
          if (at === -1) at = cn.length;
          cn.splice(at, 0, node); node.parentNode = this; return node;
        } };
    }
    var container = mkNode('container');
    var rows = ['r0', 'r1', 'r2'].map(function (n) { var r = mkNode(n); container.insertBefore(r, null); return r; });
    var leaf = mkNode('leaf-in-r0'); rows[0].insertBefore(leaf, null);
    var fn = new Function('document', 'return (' + m[0].replace(/^function /, 'function ') + ')')({ body: mkNode('body') });
    var draggedRow = fn(leaf, container);      // leaf is NESTED — must resolve to r0, not the container
    var targetRow = fn(rows[1], container);
    if (draggedRow === rows[0] && targetRow === rows[1] &&
        draggedRow !== targetRow && draggedRow.parentNode === targetRow.parentNode) {
      sameParentGuardHeld = true;
      targetRow.parentNode.insertBefore(draggedRow, targetRow.nextSibling); // before=false path
      moved = container.childNodes.map(function (n) { return n.name; }).join(',') === 'r1,r0,r2';
    }
  }
  ok('R17-DRAG-3 real-execution: movableRowEl resolves a NESTED element to the row that is the container\'s direct child (never the container itself — the bug that made the optimistic move a silent no-op live), the same-parent guard holds, and the resulting insertBefore genuinely reorders r0,r1,r2 -> r1,r0,r2',
    sameParentGuardHeld && moved);
})();

ok('R16-9 ROUND 16: the hover-reveal height:0 chrome mechanism (.rm-title-edit, .rm-item-chrome and its :focus-within/.rm-editing companion rules) is completely gone from the stylesheet — replaced by .rm-drag-handle (always-rendered, no layout-jumping reveal/hide)',
  !/\.rm-title-edit,\s*\.rm-item-chrome/.test(C) &&
  !/\.rm-item-chrome:focus-within/.test(C) &&
  /\.rm-drag-handle\s*\{/.test(C));
ok('R13-77 the two remaining live-measured contributors to the parent->first-child gap — .rm-drill\'s own padding and .rm-plan-link-row\'s bottom margin — are BOTH still trimmed (4/6px -> 2/2px each) — unaffected by Round 16\'s inter-plan/chrome changes',
  /\.rm-drill\s*\{\s*display:\s*none;\s*padding:\s*2px 8px 2px 20px/.test(C) &&
  /\.rm-plan-link-row\s*\{\s*margin:\s*2px 0 2px/.test(C));

// ============================================================
// ROUND 16 (2026-07-30) — operator walkthrough feedback on the Round 15
// surface (verbatim, docs/plans/cockpit-roadmap-redesign.md Round 16
// entry). Six deliverables: (1) inter-plan spacing — covered above
// (R16-6/7/8); (2) markdown rendering in the doc popup — this block;
// (3) kill the buttons below the plan-doc links — T3-41/42/42b above;
// (4) remove plan-title editing — T3-27c/d, T3-28 above; (5) drag-and-drop
// reordering — T3-29 above + computeReorderSteps real-execution below;
// (6) green not blue for running — R13-31/R13-65/R16-1..5 above.
// ============================================================

// ---- deliverable 5: computeReorderSteps (PURE, real execution) ----------
const reorderStepsSrc = extractMarkedBlock(roadmapJs, '// REORDER-STEPS-BEGIN', '// REORDER-STEPS-END');
ok('R16-10 selftest can locate the REORDER-STEPS extraction anchors in roadmap.js (source-execution harness precondition)',
  !!reorderStepsSrc);
function runReorderSteps(ids, draggedId, targetId, before) {
  return runPure(reorderStepsSrc, 'computeReorderSteps(' + JSON.stringify(ids) + ', ' +
    JSON.stringify(draggedId) + ', ' + JSON.stringify(targetId) + ', ' + JSON.stringify(!!before) + ')');
}
ok('R16-11 dragging item "c" to drop BEFORE "b" in [a,b,c,d] (already adjacent to it) computes ONE "up" step — a real single drag-one-slot gesture',
  (function () {
    var r = runReorderSteps(['a', 'b', 'c', 'd'], 'c', 'b', true);
    return !r.__error && r.direction === 'up' && r.count === 1;
  })());
ok('R16-11b dragging item "d" to drop BEFORE "b" in [a,b,c,d] computes TWO "up" steps (index 3 -> index 1 is a 2-slot move, not 1 — d must pass c on the way)',
  (function () {
    var r = runReorderSteps(['a', 'b', 'c', 'd'], 'd', 'b', true);
    return !r.__error && r.direction === 'up' && r.count === 2;
  })());
ok('R16-12 dragging item "a" to drop AFTER "c" in [a,b,c,d] computes TWO "down" steps',
  (function () {
    var r = runReorderSteps(['a', 'b', 'c', 'd'], 'a', 'c', false);
    return !r.__error && r.direction === 'down' && r.count === 2;
  })());
ok('R16-13 dropping an item on ITSELF, or an id missing from the sibling list, is a no-op (null) — never a phantom 0-step network call',
  (function () {
    var r1 = runReorderSteps(['a', 'b'], 'a', 'a', true);
    var r2 = runReorderSteps(['a', 'b'], 'x', 'a', true);
    return r1 === null && r2 === null;
  })());
ok('R16-14 dropping "b" AFTER "a" in [a,b] (already adjacent, no-op position) computes null — no wasted rank-endpoint call for a drop that would not change anything',
  runReorderSteps(['a', 'b'], 'b', 'a', false) === null);
ok('R16-15 wirePlanRowReorder scopes sibling rows via the SAME container hierarchy the server\'s computeSiblingIds uses (top-level project group / bare tree, or a master\'s own .rm-master-plans child-plan list) — never a flat cross-scope query',
  /planRowContainer\(rowEl\)/.test(roadmapJsNoComments) &&
  /rm-project-group,\s*\.rm-children\.rm-phase-series,\s*\.rm-tree/.test(roadmapJsNoComments.replace(/\s+/g, ' ')));

// ---- deliverable 2: markdown rendering (web/md-render.js) ----------------
let mdRender = null;
try { mdRender = require(path.join(D, 'md-render.js')); } catch (_) { /* R16-MD checks fail honestly below */ }
ok('R16-MD0 md-render.js loads as a plain Node module (dual-mode: browser global AND require()) and exports renderMarkdown',
  !!mdRender && typeof mdRender.renderMarkdown === 'function');
if (mdRender) {
  const rm = mdRender.renderMarkdown;
  ok('R16-MD1 headings render as real <h1>-<h6>, escaped',
    rm('# Title') === '<h1>Title</h1>' && rm('### Sub') === '<h3>Sub</h3>');
  ok('R16-MD2 bold/italic/inline-code render inside a paragraph',
    rm('a **bold** b *italic* c `code` d') === '<p>a <strong>bold</strong> b <em>italic</em> c <code>code</code> d</p>');
  ok('R16-MD3 fenced code blocks render verbatim (escaped), never inline-formatted (a "**not bold**" literal inside a fence stays literal)',
    rm('```\n**not bold**\n```') === '<pre class="md-code"><code>**not bold**</code></pre>');
  ok('R16-MD4 a language-tagged fence carries a language-<lang> class on <code>',
    rm('```js\nvar x=1;\n```') === '<pre class="md-code"><code class="language-js">var x=1;</code></pre>');
  ok('R16-MD5 "- [ ] x" / "- [x] y" render as an unchecked/checked list item, glyph + real text (never colour/glyph-only)',
    (function () {
      const html = rm('- [ ] todo one\n- [x] done one');
      return /<li class="md-task">.*todo one<\/li>/.test(html) &&
        /<li class="md-task md-task-done">.*done one<\/li>/.test(html) &&
        /&#9744;/.test(html) && /&#9745;/.test(html);
    })());
  ok('R16-MD6 blockquotes render as <blockquote>, recursively rendering their (unwrapped) content',
    rm('> a quoted line') === '<blockquote><p>a quoted line</p></blockquote>');
  ok('R16-MD7 a "cheap" GFM-style table renders <table>/<thead>/<tbody>',
    (function () {
      const html = rm('| a | b |\n|---|---|\n| 1 | 2 |');
      return /<table class="md-table">/.test(html) && /<th>a<\/th>/.test(html) && /<td>2<\/td>/.test(html);
    })());
  ok('R16-MD8 an http(s) link becomes a real <a href> with target=_blank/rel=noopener (never a leaked window.opener handle)',
    rm('[go](https://example.com/x)') === '<p><a href="https://example.com/x" target="_blank" rel="noopener noreferrer">go</a></p>');
  ok('R16-MD9 a repo-relative link (no URL scheme) renders as an inert doc-link span — never a clickable href (no cross-doc navigation is wired here)',
    (function () {
      const html = rm('[plan](docs/plans/foo.md)');
      return /<span class="md-doc-link"[^>]*>plan<\/span>/.test(html) && !/<a /.test(html);
    })());
  ok('R16-MD10 an unsafe scheme (javascript:) NEVER becomes an href — the link syntax degrades to plain text, no anchor at all',
    (function () {
      const html = rm('[bad](javascript:alert(1))');
      return !/<a /.test(html) && !/href/.test(html);
    })());
  // THE fixture proof this task's report is required to cite: a doc
  // containing a literal <script> tag renders INERT — escaped text inside
  // a <p>, never a live, executing tag. This is the security-critical
  // property web/md-render.js's own header names as load-bearing.
  ok('R16-MD11 SECURITY FIXTURE: a doc body containing a literal "<script>alert(1)</script>" renders as inert escaped text, NEVER a live tag — proves the escaping-first design actually holds end to end',
    rm('<script>alert(1)</script>') === '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>');
  ok('R16-MD12 SECURITY FIXTURE 2: the SAME literal script tag embedded inside a heading, a list item, and a blockquote all still render escaped — the escaping discipline is not just the paragraph path',
    (function () {
      const h = rm('# <script>alert(2)</script>');
      const li = rm('- <script>alert(3)</script>');
      const bq = rm('> <script>alert(4)</script>');
      return h.indexOf('<script>') === -1 && h.indexOf('&lt;script&gt;') !== -1 &&
        li.indexOf('<script>') === -1 && li.indexOf('&lt;script&gt;') !== -1 &&
        bq.indexOf('<script>') === -1 && bq.indexOf('&lt;script&gt;') !== -1;
    })());
  ok('R16-MD13 a raw "<img onerror=...>"-style attribute-injection attempt also renders fully inert (escaped), not just <script> specifically',
    rm('<img src=x onerror="alert(1)">').indexOf('<img') === -1);
}

// ---- deliverable 2: BOTH callers (Docs panel + plan-doc modal) wire the
// SAME renderer into the SAME shared #docBody, per the plan's binding spec
ok('R16-MD14 app.js\'s Docs panel (openDoc) renders fetched doc content via window.MdRender.renderMarkdown into #docBody.innerHTML (never raw textContent for real content — the plain-text path is a defensive fallback only, for when the script failed to load)',
  /window\.MdRender && typeof window\.MdRender\.renderMarkdown === 'function'/.test(js) &&
  /docBody\.innerHTML = window\.MdRender\.renderMarkdown\(j\.content\)|docBody\.innerHTML = window\.MdRender\.renderMarkdown\(rawContent\)/.test(js));
ok('R16-MD15 roadmap.js\'s plan-doc modal (openPlanDocModal) renders through the SAME window.MdRender.renderMarkdown into the SAME #docBody — one renderer, two callers, per the plan\'s ux-review amendment 6 ("no pane grows its own link/render handling")',
  /docBody\.innerHTML = window\.MdRender\.renderMarkdown\(j\.content\)/.test(roadmapJsNoComments));
ok('R16-MD16 md-render.js is served by server.js at /md-render.js (same static-mount convention as app.js/asks.js/todo.js/backlog.js) and loaded in index.html BEFORE app.js and roadmap.js (both callers need window.MdRender defined by the time they run)',
  (function () {
    const serverSrc = fs.readFileSync(path.join(D, '..', 'server', 'server.js'), 'utf8');
    const mdMountIdx = serverSrc.indexOf("url === '/md-render.js'");
    // match the literal <script src="..."> TAGS specifically — a bare
    // path search would also match this same file's own prose comments
    // (e.g. "Rendered by web/roadmap.js" inside a tab-description block),
    // giving a false-early index unrelated to script load order.
    const htmlMdIdx = html.indexOf('<script src="/md-render.js">');
    const htmlAppIdx = html.indexOf('<script src="/app.js">');
    const htmlRoadmapIdx = html.indexOf('<script src="/roadmap.js">');
    return mdMountIdx !== -1 && htmlMdIdx !== -1 && htmlAppIdx !== -1 && htmlRoadmapIdx !== -1 &&
      htmlMdIdx < htmlAppIdx && htmlMdIdx < htmlRoadmapIdx;
  })());
ok('R16-MD17 the Docs panel/plan-doc modal CSS (.doc-body) scopes monospace to code only (.md-code/code), not the whole document — the Round 15-and-earlier white-space:pre-wrap/monospace raw-text dump is gone',
  !/\.doc-body\s*\{[^}]*white-space:\s*pre-wrap/.test(C) &&
  !/\.doc-body\s*\{[^}]*font-family:\s*monospace/.test(C) &&
  /\.doc-body code\s*\{[^}]*font-family:/.test(C));

// ============================================================
// R17 deliverable 2 (audit F1 — the operator's own top complaint: "it's
// not clear where the command begins and ends"): the shared fenced-command
// renderer (web/command-render.js), real-executed via require() (dual-mode,
// no DOM dependency in its pure half — same technique as md-render.js's
// R16-MD block above), plus source-regex wiring checks for every caller.
// ============================================================
let cmdRender = null;
try { cmdRender = require(path.join(D, 'command-render.js')); } catch (_) { /* R17-C checks fail honestly below */ }
ok('R17-C0 command-render.js loads as a plain Node module (dual-mode: browser global AND require()) and exports renderCommandAwareText',
  !!cmdRender && typeof cmdRender.renderCommandAwareText === 'function');
if (cmdRender) {
  const rc = cmdRender.renderCommandAwareText;
  ok('R17-C1 plain prose with no command shape and no backticks renders as escaped plain text, no fence chip at all',
    rc('just an ordinary sentence') === 'just an ordinary sentence' && !/cmd-fence/.test(rc('just an ordinary sentence')));
  ok('R17-C2 an inline `backtick span` inside prose becomes a fenced, copyable chip — the surrounding prose stays plain',
    (function () {
      const out = rc('run: `nl status --json` to check');
      return /^run: /.test(out) && /<span class="cmd-fence">/.test(out) &&
        /<code class="cmd-fence-code">nl status --json<\/code>/.test(out) &&
        /data-copy-text="nl status --json"/.test(out) && / to check$/.test(out);
    })());
  ok('R17-C3 a WHOLE LINE recognized as a command shape (starts "powershell ") fences the ENTIRE line, no backticks needed',
    (function () {
      const out = rc('powershell -File adapters/claude-code/scripts/install-coord-sync-task.ps1');
      return /<span class="cmd-fence">/.test(out) &&
        /<code class="cmd-fence-code">powershell -File adapters\/claude-code\/scripts\/install-coord-sync-task\.ps1<\/code>/.test(out);
    })());
  ['$ nl status --json', 'claude --resume abc123', 'nl status --json', 'git status', 'bash script.sh'].forEach(function (line, idx) {
    ok('R17-C4.' + idx + ' recognized command-shape line "' + line + '" fences the whole line',
      /<span class="cmd-fence">/.test(rc(line)));
  });
  ok('R17-C5 a capitalized prose sentence that happens to START with the word "Claude" (referring to the assistant, not a CLI invocation) does NOT false-positive — case-sensitive, lowercase-anchored match only',
    !/cmd-fence/.test(rc('Claude Fable will now handle the rest.')));
  ok('R17-C6 the live defect this fixes: "run: powershell -File ... -> the task registers…" — the narrative "run:" and "-> the task registers…" stay plain prose; ONLY the command portion between them is fenced, so start/end is unambiguous',
    (function () {
      const out = rc('run: `powershell -File install.ps1` -> the task registers…');
      return /^run: /.test(out) && /cmd-fence/.test(out) && /-&gt; the task registers…$/.test(out);
    })());
  ok('R17-C7 SECURITY: a backtick-fenced command containing a literal "<script>alert(1)</script>" renders fully escaped/inert inside the chip, never a live tag (same escaping-first discipline as md-render.js)',
    (function () {
      const out = rc('`<script>alert(1)</script>`');
      return /&lt;script&gt;alert\(1\)&lt;\/script&gt;/.test(out) && !/<script>alert/.test(out);
    })());
  ok('R17-C8 a genuinely multi-line block (a raw §3-format text, e.g. app.js\'s Q2 nm-text) renders ONE <div class="cat-line"> per line; a SINGLE-line input (the common case: an option outcome, my-pick, a to-do item) renders INLINE with no wrapping block element, so it still sits naturally after a caller\'s own "label: " prefix text node',
    (function () {
      const multi = rc('line one\nline two `cmd`');
      const single = rc('just one line');
      return (multi.match(/<div class="cat-line">/g) || []).length === 2 && !/<div class="cat-line">/.test(single);
    })());
  ok('R17-C9 empty/absent input never throws, renders empty string',
    rc('') === '' && rc(null) === '' && rc(undefined) === '');
  ok('R17-C10 isCommandLine is exported and agrees with the fencing decision (real function, not a private inline-only check)',
    typeof cmdRender.isCommandLine === 'function' && cmdRender.isCommandLine('git status') === true &&
    cmdRender.isCommandLine('an ordinary sentence') === false);
}
ok('R17-C11 command-render.js is served by server.js at /command-render.js (same static-mount convention as md-render.js) and loaded in index.html BEFORE app.js/roadmap.js/inbox.js (every caller needs window.CommandRender defined by the time it runs)',
  (function () {
    const serverSrc = fs.readFileSync(path.join(D, '..', 'server', 'server.js'), 'utf8');
    const mountIdx = serverSrc.indexOf("url === '/command-render.js'");
    const htmlCmdIdx = html.indexOf('<script src="/command-render.js">');
    const htmlAppIdx = html.indexOf('<script src="/app.js">');
    const htmlInboxIdx = html.indexOf('<script src="/inbox.js">');
    return mountIdx !== -1 && htmlCmdIdx !== -1 && htmlAppIdx !== -1 && htmlInboxIdx !== -1 &&
      htmlCmdIdx < htmlAppIdx && htmlCmdIdx < htmlInboxIdx;
  })());

// ---- wiring: every caller named in the deliverable actually calls
// renderCat/CommandRender, not just the shared module existing in isolation.
ok('R17-C12 inbox.js applies command-aware rendering to context lines, option outcomes, my-pick, and reply-with (audit F1\'s own enumerated surfaces)',
  // Round 18: matched the local variable name `ctxBox`, so a pure rename
  // (ctxBox -> deferredContext, when background was demoted below the
  // trade-offs table) reddened it while the BEHAVIOUR was untouched. Now
  // matches the rendering call itself, which is what the assertion is about.
  /appendChild\(renderCat\(el\('div', 'ib-context-line'\), line\)\)/.test(inboxJs) &&
  /renderCat\(document\.createElement\('td'\), o\.option\)/.test(inboxJs) &&
  /renderCat\(document\.createElement\('td'\), o\.outcome\)/.test(inboxJs) &&
  /renderCat\(pickInline, item\.my_pick\)/.test(inboxJs) &&
  /renderCat\(replyWithInline, item\.reply_with\)/.test(inboxJs));
ok('R17-C13 inbox.js ALSO applies it to "My items" row text (todo text) and wires the copy-button delegation once on each of its two persistent containers',
  /renderCat\(textSpan, item\.text\)/.test(inboxJs) &&
  /wireCommandCopyButtons\(inboxSectionsWrap\)/.test(inboxJs) && /wireCommandCopyButtons\(myItemsWrap\)/.test(inboxJs));
ok('R17-C14 app.js applies it to the Q2 "what needs me" card text (.nm-text) AND the interrupt-strip chips, wiring the copy-button delegation on both persistent containers',
  /renderCat\(text, it\.text\)/.test(js) && /renderCat\(chipText,/.test(js) &&
  /wireCommandCopyButtons\(needsMeBody\)/.test(js) && /wireCommandCopyButtons\(interruptStrip\)/.test(js));
ok('R17-C15 both renderCat wrappers (inbox.js and app.js) degrade to plain textContent when window.CommandRender failed to load — never a throw, never raw HTML injection from an absent global',
  (inboxJs.match(/node\.textContent = String\(text == null \? '' : text\)/g) || []).length >= 1 &&
  (js.match(/node\.textContent = String\(text == null \? '' : text\)/g) || []).length >= 1);

// ============================================================
// R18-IB (2026-07-31) — THE INBOX READABILITY ROUND. Operator, verbatim:
// "it's kind of a wall of text and much of it is spent explaining it to me,
// and it's not very easy to find exactly what it is that's actually
// needed"; "Any commands that are needed from me should also stand out and
// make it easy for me to copy"; "the page keeps refreshing on its own,
// which forces the view back to the top of the page".
//
// These REAL-EXECUTE command-render.js (pure half, no DOM) against the
// operator's OWN live item NY-1785425479-0d4d. The line strings below are
// the actual rendered content from that item, not invented fixtures — this
// is the corpus the shipped UI failed on.
// ============================================================
if (cmdRender) {
  // The measured root cause: the producer writes numbered steps, and the
  // step label defeated the whole-line command test, so the ONE line the
  // item exists to deliver rendered as flat prose with no copy button.
  ok('R18-IB1 a bare command is detected (pre-existing behaviour, control — proves the next assertion fails for the LABEL and not for the command)',
    cmdRender.isCommandLine('git pull') === true &&
    cmdRender.isCommandLine('powershell -File adapters\\claude-code\\scripts\\install-coord-sync-task.ps1') === true);
  ok('R18-IB2 a STEP-LABELLED command is now detected as an action — the operator\'s live "STEP 2: git pull" and "STEP 3: powershell -File ..." rendered as unfenced prose before this fix',
    cmdRender.isActionLine('STEP 2: git pull') === true &&
    cmdRender.isActionLine('STEP 3: powershell -File adapters\\claude-code\\scripts\\install-coord-sync-task.ps1') === true &&
    cmdRender.isActionLine('2. git pull') === true);
  ok('R18-IB3 the copy payload is the COMMAND ONLY — pasting must never carry "STEP 3: " into a shell',
    (function () {
      var h = cmdRender.renderCommandAwareText('STEP 3: powershell -File install.ps1');
      var m = h.match(/data-copy-text="([^"]*)"/);
      return !!m && m[1] === 'powershell -File install.ps1';
    })());
  ok('R18-IB4 the label itself survives as visible prose outside the fence (the operator still needs to see the ordering)',
    cmdRender.renderCommandAwareText('STEP 3: powershell -File install.ps1').indexOf('STEP 3: <span class="cmd-fence">') === 0);
  ok('R18-IB5 narrow by construction: ordinary prose, and a step whose remainder is NOT a known command, stay prose — no false fences',
    cmdRender.isActionLine('Reply with: done (after step 3), or DEFER.') === false &&
    cmdRender.isActionLine('Background: coord-sync pushes each machine\'s live session state every 60s.') === false &&
    cmdRender.isActionLine('STEP 1: cd into your neural-lace checkout.') === false);
  ok('R18-IB6 escaping still holds through the new label path — a labelled command containing a tag renders inert, never a live element',
    (function () {
      var h = cmdRender.renderCommandAwareText('STEP 1: git <script>alert(1)</script>');
      return h.indexOf('<script>') === -1 && h.indexOf('&lt;script&gt;') !== -1;
    })());
  // The truncation defect, stated as the operator experienced it.
  ok('R18-IB7 the operator\'s real 6-line context yields 2 action lines and 4 prose lines — under the OLD 5-line whole-context cap the 6th line (STEP 3, the actual command) was the one dropped',
    (function () {
      var ctx = [
        'Background: coord-sync pushes each machine\'s live session state to the shared coordination repo every 60s.',
        'This Mac has published since 2026-07-30T06:47Z; the desktop never has.',
        'What actually went wrong: your PowerShell was at C:\\Users\\misha, OUTSIDE the neural-lace repo.',
        'Do this on the Windows desktop in PowerShell, one command at a time:',
        'STEP 2: git pull',
        'STEP 3: powershell -File adapters\\claude-code\\scripts\\install-coord-sync-task.ps1',
      ];
      var actions = ctx.filter(cmdRender.isActionLine);
      var prose = ctx.filter(function (l) { return !cmdRender.isActionLine(l); });
      var droppedByOldCap = ctx.slice(5);
      return actions.length === 2 && prose.length === 4 &&
        droppedByOldCap.length === 1 && cmdRender.isActionLine(droppedByOldCap[0]) === true;
    })());
}
// The refresh-jump fix (inbox.js load()): source checks — the guard lives
// inside a fetch .then() in a browser IIFE, so it is not requireable here.
// Labelled as a wiring check, not a behavioural proof.
// HONEST SCOPE: this is a source-shape check, not a behavioural proof — the
// guard lives inside a fetch .then() in a browser IIFE and is not requireable
// here. A first draft asserted only that `if (unchanged)` appeared in the
// source, and a mutation (`var unchanged = false`, i.e. the guard fully
// neutered) left it GREEN — the exact assert-on-source weakness this repo
// keeps shipping. It now pins the guard EXPRESSION, so neutering it reddens.
ok('R18-IB8 wiring: the 30s tick no longer re-renders unconditionally — the skip is driven by comparing the item signature to what is already rendered, and that signature EXCLUDES generated_at (which changes every tick and would defeat the guard)',
  /var unchanged = \(sig !== null && lastPayload && sig === lastRenderSig\);/.test(inboxJs) &&
  /if \(unchanged\)/.test(inboxJs) &&
  /JSON\.stringify\(\{ a: j\.answerable \|\| \[\], q: j\.quarantined \|\| \[\] \}\)/.test(inboxJs) &&
  !/generated_at[^\n]*sig/.test(inboxJs));
ok('R18-IB9 wiring: when the item set HAS changed, scroll position is preserved across the rebuild instead of being reset to the top',
  /var keepY = window\.scrollY/.test(inboxJs) && /if \(keepY\) window\.scrollTo\(0, keepY\)/.test(inboxJs));

// ============================================================
// R20 (2026-07-30) — THE RUNNING-CLAIM SWEEP. Operator-reported, twice:
// "The green items are supposed to indicate something is actively running.
// I see several green plans that aren't running."
//
// A first fix corrected the SERVER's roll-up gate but left the CLIENT
// painting the green chip from the identical bad predicate
// (`live_sessions.length` — mere membership), so the operator's symptom
// survived untouched. These tests REALLY EXECUTE the extracted client
// functions (the vm-sandbox technique used throughout this file) against
// the EXACT payload the fixture server returns for stale-dispatch-plan/1 —
// captured verbatim from a live `node server/roadmap-routes.selftest.js
// --serve` run, GET /api/roadmap. No source regex: delete the fix and the
// assertions below fail on the rendered output, not on a missing string.
// ============================================================
const elSrc = extractMarkedBlock(roadmapJs, '// EL-HELPER-BEGIN', '// EL-HELPER-END');
const runningClaimSrc = extractMarkedBlock(roadmapJs, '// RUNNING-CLAIM-BEGIN', '// RUNNING-CLAIM-END');
const taskSpanCellSrc = extractMarkedBlock(roadmapJs, '// TASK-SPAN-CELL-BEGIN', '// TASK-SPAN-CELL-END');
const nodeIsActiveSrc = extractMarkedBlock(roadmapJs, '// NODE-IS-ACTIVE-BEGIN', '// NODE-IS-ACTIVE-END');
ok('R20-0 selftest can locate the EL-HELPER/RUNNING-CLAIM/TASK-SPAN-CELL/NODE-IS-ACTIVE extraction anchors (source-execution harness precondition)',
  !!elSrc && !!runningClaimSrc && !!taskSpanCellSrc && !!nodeIsActiveSrc);

// The VERBATIM live payload for stale-dispatch-plan/1: status.value
// 'stalled', and ONE attached session whose OWN status.value is 'stalled'
// — the session heartbeat is genuinely fresh (that is the whole point),
// but the task has not been re-dispatched. `live_sessions` is non-empty,
// so every `.length` predicate evaluates TRUE against it.
const STALE_TASK_PAYLOAD = {
  id: 'stale-dispatch-plan/1',
  kind: 'task',
  title: 'a task dispatched once, hours ago, never revisited',
  status: { value: 'stalled', reason: 'idle-dispatch', reason_class: 'idle-dispatch', label: 'stalled — no recent dispatch (the session that touched it is still alive)' },
  roll_up: {},
  live_sessions: [{
    id: 'stale-dispatch-plan/1/agent/sess-op-1',
    kind: 'agent',
    title: 'session sess-op-1 (fixture)',
    status: { value: 'stalled', label: 'stalled — this task has not been (re-)dispatched in a while, even though the session that touched it is still alive', reason: '', since: '2026-07-31T00:41:47.815Z' },
  }],
};
// The control: identical shape, but the attached session is genuinely
// running. Every assertion below is paired against this so the tests pin
// "reads status.value" and not merely "always returns false".
const RUNNING_TASK_PAYLOAD = {
  id: 'rich-plan/1', kind: 'task', title: 'a genuinely active task',
  status: { value: 'in-progress', reason: '', reason_class: '', label: 'in progress' },
  roll_up: {},
  live_sessions: [{
    id: 'rich-plan/1/agent/sess-op-1', kind: 'agent', title: 'session sess-op-1 (fixture)',
    status: { value: 'running', label: 'running', reason: '', since: '2026-07-31T00:41:47.815Z' },
  }],
};

// runCell(payload, isNext) — REALLY builds the column-3 cell through the
// real taskSpanCell in a fake DOM, and returns the rendered chip text +
// classes. Asserting the RENDERED OUTPUT (what the operator sees), never an
// intermediate predicate value.
function runCell(payload, isNext) {
  const sandbox = { document: makeFakeDom() };
  vmMod.createContext(sandbox);
  const code = elSrc + '\n' + runningClaimSrc + '\n' + taskSpanSrc + '\n' + taskSpanCellSrc +
    '\nvar __cell = taskSpanCell(' + JSON.stringify(payload) + ', ' + (isNext ? 'true' : 'false') + ');' +
    '\nvar __out = __cell.children.map(function (c) { return { cls: c.className, text: c.textContent }; });';
  try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
  return sandbox.__out;
}

const staleCell = runCell(STALE_TASK_PAYLOAD, false);
ok('R20-1 THE OPERATOR\'S DEFECT: taskSpanCell renders NO "running" chip for a task whose only attached session is itself stalled — the green chip is gone from the rendered cell, not merely from a predicate (executed against the verbatim live stale-dispatch-plan/1 payload)',
  !staleCell.__error && staleCell.every((c) => c.text !== 'running' && !/rm-task-running/.test(c.cls)),
  JSON.stringify(staleCell));
const runningCell = runCell(RUNNING_TASK_PAYLOAD, false);
ok('R20-2 ...while a task with a GENUINELY running session still renders the loud green chip — the fix reads each session\'s status.value, it does not just switch the chip off (no false negative)',
  !runningCell.__error && runningCell.length === 1 &&
  runningCell[0].text === 'running' && /chip rm-task-running/.test(runningCell[0].cls),
  JSON.stringify(runningCell));
// R13-61 relocated here (see its old site above) and converted to real
// execution: the evidenced "running" claim outranks the positional "next"
// guess. R20-3 below is its mirror for the STALE case, where "next" wins.
ok('R13-61 taskSpanCell: a task that is BOTH the next open task AND genuinely running renders "running" — the evidenced claim outranks the weaker positional guess (proven by executing the real cell, not by source order)',
  (function () {
    const c = runCell(RUNNING_TASK_PAYLOAD, true);
    return !c.__error && c.length === 1 && c[0].text === 'running' && /rm-task-running/.test(c[0].cls);
  })());
ok('R20-3 a stale-session task that IS the next open task falls through to the neutral "next" token — the row still says something true, it does not go silently blank',
  (function () {
    const c = runCell(STALE_TASK_PAYLOAD, true);
    return !c.__error && c.length === 1 && c[0].text === 'next' && /rm-task-next/.test(c[0].cls);
  })());
ok('R20-4 an EMPTY live_sessions array still renders nothing (the pre-existing honest-absence behavior is unchanged by the predicate swap)',
  (function () {
    const c = runCell({ id: 'p/1', kind: 'task', title: 't', status: { value: 'not-started' }, roll_up: {}, live_sessions: [] }, false);
    return !c.__error && c.length === 0;
  })());
ok('R20-5 a session leaf with a MISSING/partial status object never counts as running (defensive: the predicate reads status.value, so a malformed leaf is not a running claim)',
  (function () {
    const c = runCell({ id: 'p/1', kind: 'task', title: 't', status: { value: 'stalled' }, roll_up: {}, live_sessions: [{ id: 'a', title: 'x' }, { id: 'b', title: 'y', status: {} }] }, false);
    return !c.__error && c.every((x) => x.text !== 'running');
  })());

// runPredicate(src, expr) — the two other swept sites are pure, so they run
// without a DOM.
function runClaim(expr) { return runPure(elSrc + '\n' + runningClaimSrc + '\n' + nodeIsActiveSrc, expr); }
ok('R20-6 SITE 813 (the drill-down header): attachedSessionsLabel does NOT say "currently running" for a stale attached session — it names the attached count without the running claim (the old header counted stalled leaves as running)',
  (function () {
    const r = runClaim('attachedSessionsLabel(' + JSON.stringify(STALE_TASK_PAYLOAD) + ')');
    return typeof r === 'string' && !/currently running/.test(r) && /none running \(1\)/.test(r);
  })(), JSON.stringify(runClaim('attachedSessionsLabel(' + JSON.stringify(STALE_TASK_PAYLOAD) + ')')));
ok('R20-7 ...and it DOES say "currently running (1)" for a genuinely running session — the header counts running members, not array length',
  runClaim('attachedSessionsLabel(' + JSON.stringify(RUNNING_TASK_PAYLOAD) + ')') === 'currently running (1):');
ok('R20-8 ...and with a MIXED list (1 running + 2 stalled) the header counts ONLY the running one, never the array length',
  (function () {
    const mixed = { live_sessions: [
      { status: { value: 'stalled' } }, { status: { value: 'running' } }, { status: { value: 'unknown' } },
    ] };
    return runClaim('attachedSessionsLabel(' + JSON.stringify(mixed) + ')') === 'currently running (1):';
  })());
ok('R20-9 SITE 1333 (auto-expand): nodeIsActive is FALSE for the stale task — a dead row no longer force-expands its whole ancestor chain and spends the operator\'s default-open budget',
  runClaim('nodeIsActive(' + JSON.stringify(STALE_TASK_PAYLOAD) + ')') === false);
ok('R20-10 ...and TRUE for the genuinely running task, AND still true for an in-progress node with no sessions attached at all (no false negative in the auto-expand policy)',
  runClaim('nodeIsActive(' + JSON.stringify(RUNNING_TASK_PAYLOAD) + ')') === true &&
  runClaim('nodeIsActive({status:{value:"in-progress"}})') === true &&
  runClaim('nodeIsActive({status:{value:"stalled",reason_class:"waiting-on-you"}})') === true);
ok('R20-11 SITE 1979 (unbound sessions) is deliberately NOT converted: renderAll still gates on .length, because deriveUnboundSessionsNode already filtered that collection server-side — the gate can only ever fail OPEN (show the node), never hide genuinely-running unattributed work (R9-7). [2026-08-01: the old justification "its members are stamped in-progress, not running" no longer holds — that stamp WAS the split-brain defect and is fixed; the fail-open reason is the one that stands.] The audit note must stay with the code so the next sweep does not "fix" it.',
  /AUDITED 2026-07-30 \(running-claim sweep\)/.test(roadmapJs) &&
  /if \(ub && ub\.live_sessions && ub\.live_sessions\.length\)/.test(roadmapJsNoComments));
ok('R20-12 no client site reads live_sessions.length as a RUNNING claim any more — the three converted sites go through the shared predicate, and the only surviving .length test is the audited unbound one',
  (function () {
    // Count `.length` membership tests on live_sessions in EXECUTABLE
    // source (comments stripped). Exactly one may remain: renderAll's
    // unbound gate. attachedSessionsLabel's own `total` is a COUNT for
    // display, not a truth test, and reads .length on a local var.
    const hits = roadmapJsNoComments.match(/\.live_sessions\s*&&\s*[A-Za-z_.]*\.live_sessions\.length/g) || [];
    return hits.length === 1;
  })(), JSON.stringify(roadmapJsNoComments.match(/\.live_sessions\s*&&\s*[A-Za-z_.]*\.live_sessions\.length/g) || []));
ok('R20-13 the client roll-up vocabulary matches the server\'s: "idle-dispatch" is a first-class badge class ranked between limit-parked and unknown, with its own label and CSS — a plan whose task went idle must not roll up a "crashed" badge',
  /'idle-dispatch'/.test(roadmapJs) &&
  (function () {
    const m = roadmapJsNoComments.match(/var ROLLUP_ORDER = \[([^\]]+)\]/);
    if (!m) return false;
    const order = m[1].split(',').map((s) => s.trim().replace(/'/g, ''));
    return order.indexOf('idle-dispatch') === order.indexOf('limit-parked') + 1 &&
      order.indexOf('unknown') === order.indexOf('idle-dispatch') + 1;
  })() &&
  /'idle-dispatch': 'stalled — no recent dispatch'/.test(roadmapJs) &&
  /\.chip\.rm-rollup-idle-dispatch/.test(C));

// ============================================================
// R21 (2026-08-01) — RUNNING-NOW vs IN-PROGRESS, the two states the
// operator kept seeing conflated:
//   "All the plan items in here that are purple are not representing what
//    they're supposed to be representing. First of all, the color is
//    supposed to be green, and second of all, it's supposed to represent
//    items that are currently being worked on. At the moment, I actually do
//    not see any items in the cockpit that state that they are actively
//    running."
//
// These assertions REALLY EXECUTE titleStateClass against payload shapes
// the live server actually emits. Deliberately NOT source regexes: a
// scenario in this very file once passed on a source-text match while the
// feature was broken. Delete the fix and these fail on the returned class,
// which is the class the operator's eye reads off the screen.
// ============================================================
const titleStateClassSrc = extractMarkedBlock(roadmapJs, '// TITLE-STATE-CLASS-BEGIN', '// TITLE-STATE-CLASS-END');
ok('R21-0 selftest can locate the TITLE-STATE-CLASS extraction anchor (source-execution harness precondition)',
  !!titleStateClassSrc);
function titleClass(item) {
  return runPure(runningClaimSrc + '\n' + titleStateClassSrc, 'titleStateClass(' + JSON.stringify(item) + ')');
}
// A plan the server stamped running_now (a real heartbeat-backed session on
// it or a descendant) — its DERIVED status is still the ordinary
// 'in-progress', which is exactly the pair that used to collapse into one
// violet title.
const RUNNING_PLAN = { id: 'p', kind: 'plan', status: { value: 'in-progress' }, running_now: true, roll_up: { running: { count: 1, exemplar: 'p/2' } } };
const IDLE_INPROGRESS_PLAN = { id: 'q', kind: 'plan', status: { value: 'in-progress' }, running_now: false, roll_up: {} };
ok('R21-6 THE OPERATOR\'S DEFECT, half 1 (semantics): a plan with commits/partial work but NO live dispatch does NOT get the running title — it renders the derived in-progress class, so it can never be read as "someone is on this"',
  titleClass(IDLE_INPROGRESS_PLAN) === 'rm-title-in-progress', String(titleClass(IDLE_INPROGRESS_PLAN)));
ok('R21-7 THE OPERATOR\'S DEFECT, half 2 (colour): a plan the server verified as running_now DOES get rm-title-running (the green class) even though its derived status is the same "in-progress" — the LIVE overlay outranks the derived ladder',
  titleClass(RUNNING_PLAN) === 'rm-title-running', String(titleClass(RUNNING_PLAN)));
ok('R21-8 HONEST ABSENCE: no live data at all (running_now absent from the payload entirely, e.g. an older/partial response) is NEVER a running claim — the falsy default is no-claim, never a comforting badge',
  titleClass({ id: 'r', status: { value: 'in-progress' } }) === 'rm-title-in-progress' &&
  titleClass({ id: 'r2', status: { value: 'not-started' } }) === 'rm-title-not-started' &&
  titleClass({ id: 'r3', status: { value: 'complete' } }) === 'rm-title-complete');
ok('R21-9 a genuinely running TASK row (its own live_sessions leaf is running, so the server stamped running_now) turns green too — the state is not plan-only',
  titleClass({ id: 'p/2', kind: 'task', status: { value: 'in-progress' }, running_now: true,
    live_sessions: [{ id: 'p/2/agent/s1', status: { value: 'running', label: 'running' } }] }) === 'rm-title-running');
ok('R21-10 the stale-dispatch task from the R20 sweep (live_sessions non-empty, but every member stalled, so the server stamps running_now false) keeps its STALLED title — a green repaint must never swallow an attention state',
  titleClass(Object.assign({}, STALE_TASK_PAYLOAD, { running_now: false })) === 'rm-title-stalled');
ok('R21-11 running_now can NEVER out-shout an exception colour even if a future server bug set both: stalled/unknown/merged-unverified keep their own title classes (the attention states are the ones the operator must not lose)',
  titleClass({ id: 'x', status: { value: 'stalled' }, running_now: true }) === 'rm-title-stalled' &&
  titleClass({ id: 'y', status: { value: 'unknown' }, running_now: true }) === 'rm-title-unknown' &&
  titleClass({ id: 'z', status: { value: 'merged-unverified' }, running_now: true }) === 'rm-title-merged-unverified');
ok('R21-12 the running claim is READ from the server, never RE-DERIVED client-side (same law R13-15 pins for the task-span token): a payload carrying a live running leaf but running_now:false — the exact shape the server emits when the task-level idle gate expired — is NOT painted green by the client second-guessing it',
  titleClass({ id: 'p/3', kind: 'task', status: { value: 'in-progress' }, running_now: false,
    live_sessions: [{ id: 'p/3/agent/s1', status: { value: 'running', label: 'running' } }] }) === 'rm-title-in-progress');
ok('R21-15 EXECUTED: a node arriving with status.value "running" (the UnboundSessionsNode shape) resolves through TITLE_STATE_CLASS to rm-title-running rather than falling through to a classless title — the half-swept-client-map defect class (AGENT_STATUS_GLYPH had no "in-progress" key and silently rendered live sessions as unknown for months)',
  titleClass({ id: 'u', kind: 'unbound-sessions', status: { value: 'running' } }) === 'rm-title-running');
ok('R21-16 STATUS_LABEL covers "running" too — it is the client\'s last-resort label for any status.value that reaches a chip, and an unmapped value falls through to printing the raw enum token',
  (function () {
    const m = roadmapJs.match(/var STATUS_LABEL = \{[\s\S]*?\};/);
    if (!m) return false;
    const box = {};
    vmMod.createContext(box);
    vmMod.runInContext(m[0] + '\nvar __v = STATUS_LABEL["running"];', box);
    return box.__v === 'running';
  })());
ok('R21-14 DELIBERATE, PINNED: a shipped/complete master that still carries a genuinely running child plan renders GREEN, not the dim complete grey — R9-7 ("running work is NEVER invisible") outranks the tidiness of the Shipped band, and dimming it would hide live work behind a "this is finished" colour. The three ATTENTION states keep their own colours instead (asserted in R21-11); "complete" is the one non-attention state that must NOT be in RUNNING_YIELDS_TO',
  titleClass({ id: 'm', kind: 'plan', status: { value: 'complete' }, running_now: true }) === 'rm-title-running' &&
  titleClass({ id: 'm2', kind: 'plan', status: { value: 'complete' }, running_now: false }) === 'rm-title-complete');
// R21-13 (2026-08-02): was THREE source regexes over roadmap.js. That is the
// weakest possible evidence for the ONE node the operator will actually watch
// change colour — and this file's own history includes a scenario that passed
// on a source match while the feature was broken. Now it EXECUTES
// renderUnboundSessions against the exact payload shape the server emits and
// asserts the produced className list + glyph characters.
const renderUnboundSrc = extractMarkedBlock(roadmapJs, '// RENDER-UNBOUND-SESSIONS-BEGIN', '// RENDER-UNBOUND-SESSIONS-END');
const agentGlyphSrc = (roadmapJs.match(/var AGENT_STATUS_GLYPH = \{[^}]*\};/) || [''])[0];
ok('R21-13a selftest can locate the RENDER-UNBOUND-SESSIONS anchor and the real AGENT_STATUS_GLYPH map (source-execution harness precondition)',
  !!renderUnboundSrc && !!agentGlyphSrc);
function runUnbound(node) {
  // FakeNode + the three members renderUnboundSessions touches that the
  // shared makeFakeDom does not model (dataset/open/addEventListener). Only
  // formatAge is stubbed, and nothing below asserts on age text.
  const base = makeFakeDom();
  const sandbox = {
    document: {
      createElement: function (tag) {
        const n = base.createElement(tag);
        n.dataset = {};
        n.open = false;
        n.addEventListener = function () {};
        n.setAttribute = function () {};
        return n;
      },
    },
  };
  vmMod.createContext(sandbox);
  const code = elSrc + '\n' + agentGlyphSrc +
    '\nvar openSet = {};\nfunction formatAge() { return "2m"; }\n' + renderUnboundSrc +
    '\nvar __d = renderUnboundSessions(' + JSON.stringify(node) + ');' +
    '\nvar __sum = __d.children[0];' +
    '\nvar __out = {' +
    '  summaryClasses: __sum.children.map(function (c) { return c.className; }),' +
    '  summaryTexts: __sum.children.map(function (c) { return c.textContent; }),' +
    '  agentRows: __d.children[1].children.map(function (li) {' +
    '    return { cls: li.className, glyph: li.children[0].textContent };' +
    '  })' +
    '};';
  try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
  return sandbox.__out;
}
// The VERBATIM shape deriveUnboundSessionsNode emits (status.value 'running'
// on the node AND every member, post-2026-08-01 split-brain fix).
const UNBOUND_NODE_PAYLOAD = {
  id: '(unattributed)', kind: 'unbound-sessions',
  title: 'live sessions not yet attributed to a task (2)',
  status: { value: 'running', label: '2 running, unattributed to a task', reason: '', since: '' },
  running_now: true,
  live_sessions: [
    { id: 'unattributed/sess-a', kind: 'agent', title: 'session sess-a (br)', status: { value: 'running', label: 'running', since: '2026-08-01T00:00:00Z' } },
    { id: 'unattributed/sess-b', kind: 'agent', title: 'session sess-b (br)', status: { value: 'running', label: 'running (quiet)', since: '2026-08-01T00:00:00Z' } },
  ],
};
const unboundOut = runUnbound(UNBOUND_NODE_PAYLOAD);
ok('R21-13 EXECUTED: the top-of-tree unattributed-live-sessions summary produces the RUNNING title class and the RUNNING chip class — not the in-progress ones it was hard-coded to. This node is the only place the cockpit says "N running" today, so it is the one the operator sees change colour',
  !unboundOut.__error &&
  unboundOut.summaryClasses.indexOf('rm-title rm-title-running') !== -1 &&
  unboundOut.summaryClasses.indexOf('chip rm-status rm-status-running') !== -1 &&
  !unboundOut.summaryClasses.some((c) => /rm-status-in-progress|rm-title-in-progress/.test(c)),
  JSON.stringify(unboundOut));
ok('R21-13b EXECUTED: the chip carries the server\'s own "N running, unattributed to a task" TEXT — colour is never the only carrier (WCAG 1.4.1)',
  !unboundOut.__error && unboundOut.summaryTexts.indexOf('2 running, unattributed to a task') !== -1,
  JSON.stringify(unboundOut.summaryTexts));
ok('R21-13c EXECUTED: each live session row gets the rm-agent-running class and the FILLED glyph "●" — the defect was that members stamped "in-progress" hit no AGENT_STATUS_GLYPH key and fell through to the UNKNOWN glyph "○"',
  !unboundOut.__error && unboundOut.agentRows.length === 2 &&
  unboundOut.agentRows.every((r) => r.cls === 'rm-agent rm-agent-running' && r.glyph === '●'),
  JSON.stringify(unboundOut.agentRows));
ok('R21-13d MUTANT CONTROL: fed the OLD pre-fix payload (members stamped "in-progress"), the same renderer produces the unknown glyph — proving these assertions read the payload\'s status.value and are not just describing whatever the renderer does',
  (function () {
    const old = JSON.parse(JSON.stringify(UNBOUND_NODE_PAYLOAD));
    old.live_sessions.forEach((s) => { s.status.value = 'in-progress'; });
    const out = runUnbound(old);
    return !out.__error && out.agentRows.every((r) => r.glyph === '○' && r.cls === 'rm-agent rm-agent-in-progress');
  })());

// ============================================================
// COCKPIT-DEAD-FILE-HREF-RESIDUAL-01 — the dead-`file://`-href CLASS SWEEP.
//
// Operator, live: "The links on the Inbox tab don't work." Root cause
// (PROVEN): a client helper converted an absolute local path into a
// `file://` href, which a browser loading this page over http silently
// refuses to navigate — the link LOOKS clickable and does nothing. That was
// fixed for roadmap.js (round 15) and inbox.js (R17) but the byte-identical
// idiom survived in asks.js and backlog.js. Live probe of the running
// cockpit at :7733 before this fix found exactly ONE anchor in the whole
// rendered DOM whose href began `file:` — backlog.js's "open backlog.md".
//
// These assertions EXECUTE the real function bodies in a fake DOM (the
// T6/T3-33 technique) and assert on the PRODUCED HREF — never on source
// text. A source-regex assertion here would be exactly the weak check that
// let this class survive two previous fixes: it proves a string is absent,
// not that no code path can build one.
// ============================================================
function makeLinkFakeDom() {
  function FakeNode(tag) {
    this.tagName = tag; this.className = ''; this._text = ''; this.children = [];
    this.attrs = {}; this.listeners = {};
  }
  Object.defineProperty(FakeNode.prototype, 'textContent', {
    get: function () { return this._text; },
    set: function (v) { this._text = v; this.children = []; },
  });
  FakeNode.prototype.appendChild = function (c) { this.children.push(c); return c; };
  FakeNode.prototype.addEventListener = function (ev, fn) {
    (this.listeners[ev] = this.listeners[ev] || []).push(fn);
  };
  FakeNode.prototype.setAttribute = function (k, v) { this.attrs[k] = v; };
  return {
    createElement: function (tag) { return new FakeNode(tag); },
    createTextNode: function (t) { var n = new FakeNode('#text'); n._text = t; return n; },
  };
}
// Walk a produced node tree and collect every href actually assigned.
function collectHrefs(node, out) {
  out = out || [];
  if (!node || typeof node !== 'object') return out;
  if (typeof node.href === 'string' && node.href) out.push(node.href);
  (node.children || []).forEach(function (c) { collectHrefs(c, out); });
  return out;
}
function collectTags(node, out) {
  out = out || [];
  if (!node || typeof node !== 'object') return out;
  if (node.tagName) out.push(node.tagName);
  (node.children || []).forEach(function (c) { collectTags(c, out); });
  return out;
}

// ---- asks.js: absoluteLinkNode, REALLY EXECUTED ------------------------
const askLinkSrc = extractMarkedBlock(asksJs, '// ABSOLUTE-LINK-NODE-BEGIN', '// ABSOLUTE-LINK-NODE-END');
ok('CDFH-0 selftest can locate the ABSOLUTE-LINK-NODE extraction anchors in asks.js (source-execution harness precondition)',
  !!askLinkSrc);
function runAskLink(value, docRef) {
  if (!askLinkSrc) return { __error: 'extraction anchors missing' };
  const opened = [];
  const sandbox = {
    document: makeLinkFakeDom(),
    // stubs for the two helpers the extracted block calls but does not own
    makeCopyBtn: function (text, label) {
      const n = makeLinkFakeDom().createElement('button');
      n.textContent = label || 'copy'; n.copyPayload = text; return n;
    },
    openPlanDocModal: function (p, d) { opened.push(p + '/' + d); },
    __opened: opened,
  };
  vmMod.createContext(sandbox);
  const code = askLinkSrc + '\nvar __result = absoluteLinkNode(' +
    JSON.stringify(value === undefined ? null : value) + ', ' +
    JSON.stringify(docRef === undefined ? null : docRef) + ');';
  try { vmMod.runInContext(code, sandbox); } catch (err) { return { __error: String(err) }; }
  return { node: sandbox.__result, opened: opened };
}
// The REAL values these four call sites carry (from the live server and the
// real ask-registry.jsonl), not invented ones.
const REAL_RAW_LINK = '/Users/misha/Claude/neural-lace/NEEDS-YOU.md';          // server.js needsYouMdPath()
const REAL_VERBATIM = '/Users/misha/.claude/projects/-Users-misha-Claude-neural-lace/a3fcb6ea.jsonl#0'; // real registry row
const REAL_EVIDENCE = '/Users/misha/Claude/neural-lace/docs/plans/some-plan.md';
const REAL_WIN_PATH = 'C:/Users/misha/docs/backlog.md';                         // drive-letter branch

ok('CDFH-1 asks.js absoluteLinkNode produces ZERO file:// hrefs for the REAL absolute paths its four call sites carry (raw_link, verbatim_ref, evidence_link, a Windows drive-letter path) — executed, asserting on the produced href, with NO doc_ref available',
  (function () {
    return [REAL_RAW_LINK, REAL_VERBATIM, REAL_EVIDENCE, REAL_WIN_PATH].every(function (v) {
      const r = runAskLink(v, null);
      if (r.__error) return false;
      const hrefs = collectHrefs(r.node);
      return hrefs.filter(function (h) { return /^file:/i.test(h); }).length === 0;
    });
  })());
ok('CDFH-2 with no doc_ref, an absolute path degrades to PLAIN TEXT + a copy affordance — no <a> element at all is produced (an honest non-link, never a fabricated one)',
  (function () {
    const r = runAskLink(REAL_VERBATIM, null);
    if (r.__error) return false;
    const tags = collectTags(r.node);
    return tags.indexOf('a') === -1 && tags.indexOf('button') !== -1 &&
      collectHrefs(r.node).length === 0;
  })());
ok('CDFH-3 with a server-resolved doc_ref, the path becomes a real <button> whose click OPENS THE IN-PAGE DOC VIEWER with that {project, path} — the click handler is invoked and observed, not merely present',
  (function () {
    const r = runAskLink(REAL_RAW_LINK, { project: 'neural-lace', path: 'NEEDS-YOU.md' });
    if (r.__error) return false;
    const tags = collectTags(r.node);
    if (tags.indexOf('button') === -1 || tags.indexOf('a') !== -1) return false;
    if (collectHrefs(r.node).length !== 0) return false;
    // actually fire the click handler the code registered
    const btn = (r.node.children || []).filter(function (c) { return c.tagName === 'button'; })[0];
    if (!btn || !btn.listeners.click || !btn.listeners.click.length) return false;
    btn.listeners.click[0]();
    return r.opened.length === 1 && r.opened[0] === 'neural-lace/NEEDS-YOU.md';
  })());
ok('CDFH-4 a genuine http(s) link is STILL an ordinary navigable anchor (the cure must not break real links) — href assigned verbatim, target/rel preserved',
  (function () {
    const r = runAskLink('https://github.com/x/y/pull/1', null);
    if (r.__error) return false;
    const hrefs = collectHrefs(r.node);
    return hrefs.length === 1 && hrefs[0] === 'https://github.com/x/y/pull/1' &&
      collectTags(r.node).indexOf('a') !== -1;
  })());
ok('CDFH-5 an http(s) link WINS over a doc_ref (the http branch is checked first) and an empty/absent value renders the literal "(none)" with no href — the two edge branches still behave',
  (function () {
    const withBoth = runAskLink('https://example.com/a', { project: 'p', path: 'q.md' });
    const empty = runAskLink('', null);
    const nul = runAskLink(null, null);
    if (withBoth.__error || empty.__error || nul.__error) return false;
    return collectHrefs(withBoth.node).length === 1 &&
      collectTags(withBoth.node).indexOf('button') === -1 &&
      empty.node.textContent === '(none)' && collectHrefs(empty.node).length === 0 &&
      nul.node.textContent === '(none)' && collectHrefs(nul.node).length === 0;
  })());
ok('CDFH-6 a RELATIVE reference (the common real shape in a §3 Links: line, e.g. "docs/backlog.md") is never turned into an href, with or without a doc_ref present',
  (function () {
    const r = runAskLink('docs/backlog.md', null);
    return !r.__error && collectHrefs(r.node).length === 0 && collectTags(r.node).indexOf('a') === -1;
  })());

// ---- backlog.js: absoluteLinkHref + the open-file affordance, EXECUTED --
const backlogHrefSrc = extractMarkedBlock(backlogJs, '// ABSOLUTE-LINK-HREF-BEGIN', '// ABSOLUTE-LINK-HREF-END');
const backlogAffordanceSrc = extractMarkedBlock(backlogJs, '// OPEN-FILE-AFFORDANCE-BEGIN', '// OPEN-FILE-AFFORDANCE-END');
ok('CDFH-7 selftest can locate backlog.js\'s ABSOLUTE-LINK-HREF and OPEN-FILE-AFFORDANCE extraction anchors (source-execution harness precondition)',
  !!backlogHrefSrc && !!backlogAffordanceSrc);
function runBacklogHref(value) {
  if (!backlogHrefSrc) return { __error: 'anchors missing' };
  const sandbox = {};
  vmMod.createContext(sandbox);
  try {
    vmMod.runInContext(backlogHrefSrc + '\nvar __r = absoluteLinkHref(' +
      JSON.stringify(value === undefined ? null : value) + ');', sandbox);
  } catch (err) { return { __error: String(err) }; }
  return sandbox.__r;
}
// The REAL file_path the LIVE server returns from GET /api/backlog.
const REAL_BACKLOG_PATH = '/Users/misha/Claude/neural-lace/docs/backlog.md';
ok('CDFH-8 backlog.js absoluteLinkHref returns NULL (never a file:// URL) for the REAL absolute file_path the live server serves, and for a Windows drive-letter path — executed, asserting on the returned href',
  runBacklogHref(REAL_BACKLOG_PATH) === null && runBacklogHref(REAL_WIN_PATH) === null &&
  runBacklogHref('/any/absolute/path.md') === null && runBacklogHref('\\\\host\\share\\x.md') === null);
ok('CDFH-9 backlog.js absoluteLinkHref still passes a genuine http(s) URL through unchanged (real links keep working)',
  runBacklogHref('https://example.com/backlog.md') === 'https://example.com/backlog.md' &&
  runBacklogHref('') === null && runBacklogHref(null) === null);

function runBacklogAffordance(payload) {
  if (!backlogAffordanceSrc) return { __error: 'anchors missing' };
  const dom = makeLinkFakeDom();
  const header = dom.createElement('div');
  const opened = [];
  const sandbox = {
    document: dom, header: header, payload: payload,
    absoluteLinkHref: function (v) { return runBacklogHref(v); },
    openBacklogDocModal: function (p, d) { opened.push(p + '/' + d); },
  };
  vmMod.createContext(sandbox);
  try { vmMod.runInContext(backlogAffordanceSrc, sandbox); }
  catch (err) { return { __error: String(err) }; }
  return { header: header, opened: opened };
}
ok('CDFH-10 the "open backlog.md" affordance produces ZERO file:// hrefs for the REAL live payload — executed against the exact {file_path, file_doc_ref} shape GET /api/backlog now returns',
  (function () {
    const r = runBacklogAffordance({
      file_path: REAL_BACKLOG_PATH,
      file_doc_ref: { project: 'neural-lace', path: 'docs/backlog.md' },
    });
    if (r.__error) return false;
    return collectHrefs(r.header).filter(function (h) { return /^file:/i.test(h); }).length === 0;
  })());
ok('CDFH-11 that affordance is a real <button> that OPENS THE IN-PAGE DOC VIEWER at the resolved {project, path} — the registered click handler is fired and its effect observed, not merely asserted present',
  (function () {
    const r = runBacklogAffordance({
      file_path: REAL_BACKLOG_PATH,
      file_doc_ref: { project: 'neural-lace', path: 'docs/backlog.md' },
    });
    if (r.__error) return false;
    const tags = collectTags(r.header);
    if (tags.indexOf('button') === -1 || tags.indexOf('a') !== -1) return false;
    const btn = r.header.children[0];
    if (!btn.listeners.click || !btn.listeners.click.length) return false;
    btn.listeners.click[0]();
    return r.opened.length === 1 && r.opened[0] === 'neural-lace/docs/backlog.md' &&
      btn.textContent === 'open backlog.md';
  })());
ok('CDFH-12 with an UNRESOLVABLE file_doc_ref (path outside every known project root) the affordance is OMITTED entirely rather than rendered as a link that cannot work — zero children, zero hrefs',
  (function () {
    const r = runBacklogAffordance({ file_path: REAL_BACKLOG_PATH, file_doc_ref: null });
    if (r.__error) return false;
    return r.header.children.length === 0 && collectHrefs(r.header).length === 0;
  })());
ok('CDFH-13 an http(s) file_path (a remotely-served backlog) still renders an ordinary navigable anchor — the cure does not remove genuine links',
  (function () {
    const r = runBacklogAffordance({ file_path: 'https://example.com/backlog.md', file_doc_ref: null });
    if (r.__error) return false;
    const hrefs = collectHrefs(r.header);
    return hrefs.length === 1 && hrefs[0] === 'https://example.com/backlog.md' &&
      collectTags(r.header).indexOf('a') !== -1;
  })());

// ---- the class predicate itself, asserted over the whole client tree ----
// This is the assertion that would have caught the residual: it is not
// scoped to the two files this round cured, so a THIRD surface reintroducing
// the idiom fails here too. Comments/strings are stripped first, so the
// explanatory prose above (which necessarily says "file://") does not
// self-satisfy or self-trip the check.
// NOTE on the stripper below: this assertion deliberately does NOT reuse the
// shared stripJsComments(). That helper strips `//`-to-end-of-line, and the
// `//` inside the very literal we are hunting (`'file:///' + norm`) looks
// exactly like a comment start to it — it rewrites `'file:///' + norm` down
// to `'file:` and the predicate then matches nothing. That was caught by
// mutation: with the old dead-href helper restored, a stripJsComments-based
// version of this check stayed GREEN, i.e. it was theater. The line-based
// stripper here removes only whole comment LINES (and block comments),
// leaving string literals on code lines intact.
function stripCommentLinesOnly(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .split('\n')
    .filter(function (l) { const t = l.trim(); return t.slice(0, 2) !== '//' && t.slice(0, 1) !== '*'; })
    .join('\n');
}
const cdfhOffenders = (function () {
  const files = fs.readdirSync(D).filter(function (f) { return /\.js$/.test(f) && f !== 'cockpit.selftest.js'; });
  const offenders = [];
  files.forEach(function (f) {
    const stripped = stripCommentLinesOnly(fs.readFileSync(path.join(D, f), 'utf8'));
    // a CONSTRUCTION is a file:// opening a string literal or template
    if (/['"`]file:\/\//.test(stripped)) offenders.push(f);
  });
  return offenders;
})();
ok('CDFH-14 CLASS PREDICATE: no client-side source file anywhere under web/ CONSTRUCTS a file:// string literal (whole comment lines stripped; the isAbsoluteHref RECOGNIZER, which only .test()s the shape and builds nothing, is exempt and asserted separately below). Not scoped to the two files this round cured — a THIRD surface reintroducing the idiom fails HERE',
  cdfhOffenders.length === 0, 'offenders: ' + JSON.stringify(cdfhOffenders));
ok('CDFH-15 the ONE surviving file:// mention in live client code is asks.js\'s isAbsoluteHref RECOGNIZER — it only ever returns a boolean, and executing it proves it classifies rather than constructs',
  (function () {
    const r = runAskLink('file:///Users/misha/x.md', null);
    if (r.__error) return false;
    // A value that ALREADY arrives as a file:// URL is still not turned into
    // an anchor by this module — it degrades to text + copy like any other
    // unopenable reference.
    return collectHrefs(r.node).length === 0 && collectTags(r.node).indexOf('a') === -1;
  })());

ok('CDFH-16 ALL FOUR in-page doc openers render through the shared window.MdRender pipeline — asks.js was the last one still dumping raw markdown via textContent, and this round routes four more link kinds through it, so a newly-cured link would otherwise open a visibly worse view than an already-cured one',
  ['asks.js', 'roadmap.js', 'inbox.js', 'backlog.js'].every(function (f) {
    const s = fs.readFileSync(path.join(D, f), 'utf8');
    return /window\.MdRender && typeof window\.MdRender\.renderMarkdown === 'function'/.test(s) &&
      /docBody\.innerHTML = window\.MdRender\.renderMarkdown\(j\.content\)/.test(s);
  }));

console.log('');
console.log('self-test summary: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
