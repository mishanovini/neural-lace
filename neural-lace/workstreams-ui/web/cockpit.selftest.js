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

console.log('');
console.log('self-test summary: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
