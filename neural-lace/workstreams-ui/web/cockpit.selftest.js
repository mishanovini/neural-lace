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
const todoJs = fs.readFileSync(path.join(D, 'todo.js'), 'utf8');
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
ok('T13-26 drift badges render as real <summary> elements with visible text (never color-only), forward-compatible with Task 12',
  /sum\.className = 'chip ask-badge'/.test(asksJs) && /sum\.textContent = String\(label\)/.test(asksJs));
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
// in the landing (#tabAsksPanel) portion of the document. -----------------
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

// --- Harness Health tab wire check: index.html tab shell -> app.js router
// (the plan's own Wire checks block). ---------------------------------
ok('T16-3 index.html defines the tab nav (#tabAsksBtn / #tabHealthBtn) driving app.js\'s router',
  /id="tabAsksBtn"/.test(html) && /id="tabHealthBtn"/.test(html) &&
  /id="tabAsksPanel"/.test(html) && /id="tabHealthPanel"/.test(html));
ok('T16-4 app.js implements initHarnessHealthTab() which clones the template and activateTab() which drives the tab nav',
  /function initHarnessHealthTab/.test(js) && /function activateTab/.test(js) &&
  /harnessHealthTemplate\.content\.cloneNode\(true\)/.test(js));
ok('T16-5 Asks is the default landing tab (activateTab(\'asks\') called at load, #tabHealthPanel starts hidden)',
  /activateTab\('asks'\)/.test(js) && /id="tabHealthPanel"[^>]*\bhidden\b/.test(html));

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
  ['ask-badge', asksJsNoComments, /sum\.textContent = String\(label\)/],
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
// assembled landing (index.html's tab nav + todo.js + backlog.js; asks.js
// already covered by T13-22/23) is a real <button>/<a>, never a clickable
// <div>. ------------------------------------------------------------------
ok('T16-10 the tab-nav controls are real <button> elements, never clickable divs',
  /<button[^>]+id="tabAsksBtn"/.test(html) && /<button[^>]+id="tabHealthBtn"/.test(html));
ok('T16-11 todo.js never wires a click handler onto a bare div (real buttons/inputs only)',
  !/[Dd]iv\.addEventListener\('click'/.test(todoJs));
ok('T16-12 backlog.js never wires a click handler onto a bare div (real buttons only)',
  !/[Dd]iv\.addEventListener\('click'/.test(backlogJs));
ok('T16-13 todo.js and backlog.js build their interactive controls with createElement(\'button\'), not divs',
  (todoJs.match(/createElement\('button'\)/g) || []).length >= 3 &&
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

console.log('');
console.log('self-test summary: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
