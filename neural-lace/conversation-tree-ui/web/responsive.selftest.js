'use strict';
/* Conversation Tree UI — v1.1 responsive-layout regression self-test.
 * Dependency-free (Node stdlib only, no build step, no headless-browser dep —
 * consistent with state/selftest.js). Locks the load-bearing CSS/HTML/JS
 * invariants the four-viewport behavior depends on (DEC-A revised). A live
 * headless-browser walk-through is done separately via the preview MCP; this
 * is the fast deterministic guard that fails CI if a future edit regresses
 * the breakpoint contract. Run: `node web/responsive.selftest.js`. */
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
// collapse whitespace for resilient substring matching
const C = css.replace(/\s+/g, ' ');

// --- Item 1: the off-screen bug is gone -------------------------------------
// Scope to the `body { ... }` declaration block only — 1440px legitimately
// appears in the @media breakpoint bounds (that is the FIX, not the bug).
const bodyBlock = (C.match(/(^|})\s*body\s*\{([^}]*)\}/) || [,, ''])[2];
ok('R1 body{} no longer min-width:1440px / min-height:900px (the off-screen bug)',
  bodyBlock.length > 0
  && !/min-width:\s*1440px/.test(bodyBlock)
  && !/min-height:\s*900px/.test(bodyBlock));
ok('R2 #layout is CSS grid (not the old flex)', /#layout\s*\{[^}]*display:\s*grid/.test(C));

// --- Item 1: default = vertical stack ---------------------------------------
ok('R3 default #layout vertical-stack grid-template-areas',
  /#layout\s*\{[^}]*grid-template-areas:\s*"tree\s+tree"\s*"actions\s+backlog"/.test(C));

// --- Item 1: (A) >=1440 = DEC-A ORIGINAL three-pane, unchanged ---------------
ok('R4 @media min-width:1440px three-pane grid (DEC-A unchanged)',
  /@media \(min-width:\s*1440px\)\s*\{[^@]*grid-template-areas:\s*"tree\s+actions"\s*"tree\s+backlog"/.test(C));
ok('R5 >=1440 keeps tree ~57% column', /@media \(min-width:\s*1440px\)\s*\{[^@]*grid-template-columns:\s*57%\s*43%/.test(C));

// --- Item 1: (C) small window = single-pane + tabs --------------------------
ok('R6 @media (max-width:1023.98px) and (max-height:1023.98px) single-pane',
  /@media \(max-width:\s*1023\.98px\)\s*and\s*\(max-height:\s*1023\.98px\)\s*\{[^@]*grid-template-areas:\s*"pane"/.test(C));
ok('R7 #tabBar shown (display:flex) only in the small-window media block',
  /@media \(max-width:\s*1023\.98px\)\s*and\s*\(max-height:\s*1023\.98px\)\s*\{[^@]*#tabBar\s*\{\s*display:\s*flex/.test(C)
  && /#tabBar\s*\{\s*display:\s*none/.test(C));

// --- Item 1: <700 narrow stacks actions over backlog ------------------------
ok('R8 @media max-width:699.98px stacks actions over backlog',
  /@media \(max-width:\s*699\.98px\)\s*\{[^@]*grid-template-areas:\s*"tree"\s*"actions"\s*"backlog"/.test(C));

// --- Item 2: the ✕ "does nothing" bug fix -----------------------------------
ok('R9 .ctx-panel[hidden] { display:none } overrides display:flex (✕ fix)',
  /\.ctx-panel\[hidden\]\s*\{\s*display:\s*none\s*!important/.test(C));
ok('R10 #ctxScrim backdrop rule present', /#ctxScrim\s*\{[^}]*position:\s*fixed/.test(C));
ok('R11 scrim suppressed (docked, no scrim) at >=1440',
  /@media \(min-width:\s*1440px\)\s*\{[^@]*#ctxScrim\s*\{\s*display:\s*none/.test(C));

// --- Item 5: fluid zoom canvas ---------------------------------------------
ok('R12 .tree-canvas width:100% base (item 5 fluid zoom)',
  /\.tree-canvas\s*\{[^}]*width:\s*100%/.test(C));

// --- HTML structural hooks --------------------------------------------------
ok('R13 #showConcluded toggle in header (item 3)', /id="showConcluded"/.test(html));
ok('R14 #tabBar with tree/actions/backlog buttons (item 1 mode C)',
  /id="tabBar"/.test(html) && /data-tab="tree"/.test(html) && /data-tab="actions"/.test(html) && /data-tab="backlog"/.test(html));
ok('R15 #ctxScrim element present (item 2)', /id="ctxScrim"/.test(html));

// --- JS behavior hooks ------------------------------------------------------
ok('R16 closeCtx() single dismiss path (item 2)', /function closeCtx\s*\(\)/.test(js));
ok('R17 ctxScrim click + Escape wired to closeCtx (item 2)',
  /ctxScrim\.addEventListener\('click',\s*closeCtx\)/.test(js) && /e\.key === 'Escape'[^}]*closeCtx/.test(js));
ok('R18 hide-concluded persisted via localStorage ctree-show-concluded (item 3)',
  /localStorage\.setItem\('ctree-show-concluded'/.test(js) && /localStorage\.getItem\('ctree-show-concluded'\)\s*===\s*'1'/.test(js));
ok('R19 concludedHiddenSet subtree filter (item 3)',
  /function concludedHiddenSet\s*\(\)/.test(js) && /allHiddenByConcluded/.test(js));
ok('R20 Fit measures natural bbox + applies scale + scroll origin (item 4)',
  /treeCanvas\.scrollWidth/.test(js) && /treeCanvas\.scrollHeight/.test(js)
  && /treeScroll\.scrollLeft\s*=\s*0;\s*treeScroll\.scrollTop\s*=\s*0/.test(js));
ok('R21 zoom reflow sets width:(100/zoom)% (item 5)',
  /treeCanvas\.style\.width\s*=\s*\(100\s*\/\s*zoom\)\s*\+\s*'%'/.test(js));
ok('R22 tab bar flips body[data-tab] (item 1 mode C, JS only flips a class)',
  /document\.body\.dataset\.tab\s*=\s*b\.dataset\.tab/.test(js));

// --- v1.1-ux items 7/8/9/10/12/13 ------------------------------------------
const schema = fs.readFileSync(path.join(D, '..', 'state', 'schema.js'), 'utf8');
const reducer = fs.readFileSync(path.join(D, '..', 'state', 'reducer.js'), 'utf8');

// item 7/12/13 — snackbar + undo + ✕
ok('R23 snackbar(): undo button + ✕, 10s vs 2.6s timer (items 7/12/13)',
  /function snackbar\s*\(/.test(js)
  && /sb-undo/.test(js) && /sb-x/.test(js)
  && /_pendingUndo\s*\?\s*10000\s*:\s*2600/.test(js));
ok('R24 ✕ → closeToast clears timer + cancels pending undo (item 13)',
  /function closeToast\s*\(\)/.test(js)
  && /toast\._pendingUndo\s*=\s*null/.test(js)
  && /x\.addEventListener\('click',\s*closeToast\)/.test(js));
ok('R25 actWithUndo: leave-anim → silent post → undo snackbar (item 7)',
  /function actWithUndo\s*\(/.test(js)
  && /function animateLeave\s*\(/.test(js)
  && /reducedMotion\s*\(\)/.test(js));
ok('R26 list enter/leave/flash keyframes + reduced-motion guard (item 7)',
  /@keyframes li-enter/.test(C) && /@keyframes li-leave/.test(C) && /@keyframes li-flash/.test(C)
  && /@media \(prefers-reduced-motion: reduce\)/.test(C));

// item 8 — +N new badge
ok('R27 per-pane "+N new" badge: spans + diff + clear-on-look (item 8)',
  /id="actionsNewBadge"/.test(html) && /id="backlogNewBadge"/.test(html)
  && /function diffNewIds\s*\(/.test(js) && /function updateNewBadges\s*\(/.test(js)
  && /clearNewBadge\('a'\)/.test(js) && /\.new-badge/.test(C));

// item 9 — rich details (additive schema + UI)
ok('R28 item-details-set additive event (schema enum+required+reducer case)',
  /'item-details-set'/.test(schema)
  && /'item-details-set':\s*\['node_id',\s*'item_id',\s*'details'\]/.test(schema)
  && /case 'item-details-set'/.test(reducer));
ok('R29 rich-details disclosure UI: renderItemDetails + .li-details (item 9)',
  /function renderItemDetails\s*\(/.test(js) && /det-toggle/.test(js)
  && /\.li-details\s*\{/.test(C));

// item 10 — inline response (additive schema + UI)
ok('R30 action-responded additive event (schema enum+required+reducer case)',
  /'action-responded'/.test(schema)
  && /'action-responded':\s*\['node_id',\s*'item_id',\s*'response_text'\]/.test(schema)
  && /case 'action-responded'/.test(reducer));
ok('R31 inline Respond UI + responded state + Copy-to-Dispatch (item 10)',
  /function respondable\s*\(/.test(js)
  && /function copyResponseForDispatch\s*\(/.test(js)
  && /respond-box/.test(js) && /responded — awaiting confirmation/.test(js)
  && /\.li\.responded\s*\{/.test(C));

// undo inverse event for done/answered
ok('R32 item-unchecked additive inverse event (schema+reducer+undo wiring)',
  /'item-unchecked'/.test(schema)
  && /'item-unchecked':\s*\['node_id',\s*'item_id'\]/.test(schema)
  && /case 'item-unchecked'/.test(reducer)
  && /type:\s*'item-unchecked'/.test(js));

// additive proof: schema_version constant unchanged (still 1, no major bump)
ok('R33 ADR-032 additive: SCHEMA_VERSION still 1 (3 new event types, no bump)',
  /const SCHEMA_VERSION\s*=\s*1\s*;/.test(schema));

// --- v1.1.1 polish items 14/15/16/17/18 ------------------------------------
ok('R34 item 14: type palette vars + AA-safe per-kind label/stripe',
  /--ty-action:\s*#f87171/.test(C) && /--ty-decision:\s*#fbbf24/.test(C) && /--ty-question:\s*#60a5fa/.test(C)
  && /--ty-action-rgb:\s*248 113 113/.test(C)
  && /\.li-kind\.action\s*\{[^}]*var\(--ty-action\)/.test(C)
  && /\.li\.kind-action\s*\{[^}]*border-left:\s*5px solid var\(--ty-action\)/.test(C)
  && /'li kind-' \+ it\.kind/.test(js));
ok('R35 item 15: title flex:1 + fixed 24px icon-button jump (no width-greedy crumb)',
  /\.li-text\s*\{[^}]*flex:\s*1/.test(C)
  && /\.li-jump\s*\{[^}]*width:\s*24px;\s*height:\s*24px/.test(C)
  && /el\('button',\s*'li-jump',\s*'→'\)/.test(js)
  && /Jump to in tree/.test(js));
ok('R36 item 16: prominent grouped View-filters toggle + default-hide preserved',
  /class="view-filters"/.test(html) && /class="toggle-prom"/.test(html) && /👁/.test(html)
  && /\.view-filters\s*\{/.test(C) && /\.toggle-prom\s*\{/.test(C)
  && /localStorage\.getItem\('ctree-show-concluded'\)\s*===\s*'1'/.test(js));   // absent => false => hide (default)
ok('R37 item 17: bidirectional link-select — selNodeLink + tint both sides + scrollIntoView',
  /var selNodeLink\s*=\s*null/.test(js)
  && /function linkSelect\s*\(/.test(js)
  && /function dominantKind\s*\(/.test(js)
  && /sel-link/.test(js) && /sel-tint/.test(js)
  && /\.li\.sel-link\.kind-action[^{]*\{[^}]*rgb\(var\(--ty-action-rgb\) \/ 0\.18\)/.test(C)
  && /scrollIntoView\(\{\s*block:\s*'center',\s*behavior:\s*'smooth'\s*\}\)/.test(js)
  && /linkSelect\(n\.node_id,\s*'fromTree'\)/.test(js));
ok('R38 item 18: toast bottom-right (+narrow bottom-center) + arrival-flash + reduced-motion',
  /\.toast\s*\{[^}]*right:\s*1rem;\s*bottom:\s*1\.2rem;\s*left:\s*auto/.test(C)
  && /@media \(max-width:\s*1023\.98px\) and \(max-height:\s*1023\.98px\)\s*\{\s*\.toast\s*\{[^}]*left:\s*50%/.test(C)
  && /@keyframes arrival-flash/.test(C)
  && /function arrivalFlash\s*\(/.test(js)
  && /reducedMotion\(\)\s*\?\s*1500\s*:\s*700/.test(js)
  && /@media \(prefers-reduced-motion: reduce\)\s*\{[^@]*\.arrival-flash\s*\{\s*animation:\s*none/.test(C));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
