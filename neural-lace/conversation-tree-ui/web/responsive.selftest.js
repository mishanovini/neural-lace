'use strict';
/* Conversation Tree UI — v2 responsive-layout regression self-test.
 * Dependency-free (Node stdlib only, no build step, no headless-browser dep).
 *
 * V2 redesign (2026-05-23) — per Misha's feedback:
 *   - Tree pane FIXED narrow width (clamp 260-340px), full vertical height,
 *     always visible. Never has content stacked below it.
 *   - ONE side panel right of the tree, hosting Waiting + Backlog as TABS.
 *     Persistent column at >=1024px; off-canvas DRAWER at <1024px.
 *   - Detail (ex-ctxPanel), Doc viewer, Dispatch composer are CENTERED
 *     MODALS — they NEVER shift the persistent #layout.
 *   - Active tab persists across reload (localStorage key ctree-pane-tab).
 *   - UX-VR-13: backlog context is a multi-line TEXTAREA (not single-line).
 *
 * State model is class-based on <body> to avoid CSS specificity puzzles
 * with dataset attributes:
 *   .pane-tab-waiting / .pane-tab-backlog
 *   .side-open (drawer open at <1024px) / .side-hidden (explicit hide at wide)
 *
 * Run: `node web/responsive.selftest.js`. */
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

// --- v2 layout fundamentals ---------------------------------------------
const bodyBlock = (C.match(/(^|})\s*body\s*\{([^}]*)\}/) || [,, ''])[2];
ok('R1 body{} no off-screen min-width:1440px / min-height:900px bug',
  bodyBlock.length > 0
  && !/min-width:\s*1440px/.test(bodyBlock)
  && !/min-height:\s*900px/.test(bodyBlock));
ok('R2 #layout is CSS grid', /#layout\s*\{[^}]*display:\s*grid/.test(C));

// v2 layout: single-row "tree side", no stacking below the tree
ok('R3 v2: default #layout grid-template-areas is single-row "tree side"',
  /#layout\s*\{[^}]*grid-template-areas:\s*"tree\s+side"/.test(C)
  && !/grid-template-areas:\s*"tree\s+tree"\s*"actions/.test(C));

// v2: tree column narrow + clamped via --tree-col
ok('R4 v2: tree column is clamp(260px, 22vw, 340px) via --tree-col',
  /--tree-col:\s*clamp\(260px,\s*22vw,\s*340px\)/.test(C)
  && /#layout\s*\{[^}]*grid-template-columns:\s*var\(--tree-col\)\s*1fr/.test(C)
  && !/grid-template-columns:\s*57%\s*43%/.test(C));

// v2: no legacy 1440px Layout-A 3-pane grid
ok('R5 v2: no @media (min-width:1440px) 3-pane grid override',
  !/@media \(min-width:\s*1440px\)[^@]*grid-template-areas:\s*"tree\s+actions"\s*"tree\s+backlog"/.test(C));

// v2 drawer mode at <1024px: single-column layout + side panel slides via `right`
ok('R6 v2: @media (max-width:1023.98px) collapses to single column + drawer slides via right (class-based .side-open)',
  /@media \(max-width:\s*1023\.98px\)\s*\{[^@]*grid-template-areas:\s*"tree"/.test(C)
  && /@media \(max-width:\s*1023\.98px\)\s*\{[\s\S]*?#layout \.side-panel\s*\{[^}]*right:\s*calc\(-1 \* min\(var\(--side-panel-w\)/.test(C)
  && /body\.side-open\s*#layout \.side-panel\s*\{\s*right:\s*0/.test(C));

// v2: old tabBar gone; new always-visible #paneTabs in its place
ok('R7 v2: legacy #tabBar removed from HTML; #paneTabs is the right-panel tab nav',
  !/id="tabBar"/.test(html)
  && /#paneTabs\s*\{/.test(C)
  && /#paneTabs button\[data-pane-tab\]\.active/.test(C));

// v2: no <700 stacking rule (single side panel now, tabs swap)
ok('R8 v2: no @media max-width:699.98px stacking-actions-over-backlog rule',
  !/@media \(max-width:\s*699\.98px\)\s*\{[^@]*grid-template-areas:\s*"tree"\s*"actions"\s*"backlog"/.test(C));

// v2 modal contract: .modal-card[hidden] hides cleanly; .modal-scrim is fixed
ok('R9 v2: .modal-card[hidden] overrides display:flex',
  /\.modal-card\[hidden\]\s*\{\s*display:\s*none\s*!important/.test(C));
ok('R10 v2: .modal-scrim is a fixed-position backdrop',
  /\.modal-scrim\s*\{[^}]*position:\s*fixed/.test(C)
  && /\.modal-scrim\s*\{[^}]*z-index:\s*59/.test(C));
ok('R11 v2: .modal-card is centered (translate(-50%,-50%)) and does NOT shift #layout',
  /\.modal-card\s*\{[^}]*top:\s*50%/.test(C)
  && /\.modal-card\s*\{[^}]*left:\s*50%/.test(C)
  && /\.modal-card\s*\{[^}]*transform:\s*translate\(-50%,\s*-50%\)/.test(C)
  // critical regression-guard: NO layout-shift rule
  && !/body\[data-ctx-pane="open"\]\s*#layout\s*\{[^}]*margin-right/.test(C)
  && !/body\[data-doc-pane="open"\]\s*#layout\s*\{[^}]*margin-right/.test(C));

ok('R12 .tree-canvas width:100% base (fluid zoom)',
  /\.tree-canvas\s*\{[^}]*width:\s*100%/.test(C));

// --- HTML structural hooks ----------------------------------------------
ok('R13 #showConcluded toggle in header', /id="showConcluded"/.test(html));
ok('R14 v2: #paneTabs with data-pane-tab="waiting" / "backlog" buttons',
  /id="paneTabs"/.test(html)
  && /data-pane-tab="waiting"/.test(html)
  && /data-pane-tab="backlog"/.test(html));
ok('R15 #ctxScrim element present', /id="ctxScrim"/.test(html));

// --- JS behavior hooks --------------------------------------------------
ok('R16 closeCtx() single dismiss path', /function closeCtx\s*\(\)/.test(js));
ok('R17 ctxScrim click + Escape wired to closeCtx',
  /ctxScrim\.addEventListener\('click',\s*closeCtx\)/.test(js)
  && /e\.key === 'Escape'[^}]*closeCtx/.test(js));
ok('R18 hide-concluded persisted via localStorage',
  /localStorage\.setItem\('ctree-show-concluded'/.test(js)
  && /localStorage\.getItem\('ctree-show-concluded'\)\s*===\s*'1'/.test(js));
ok('R19 concludedHiddenSet subtree filter',
  /function concludedHiddenSet\s*\(\)/.test(js) && /allHiddenByConcluded/.test(js));
ok('R20 Fit measures natural bbox + applies scale + scroll origin',
  /treeCanvas\.scrollWidth/.test(js) && /treeCanvas\.scrollHeight/.test(js)
  && /treeScroll\.scrollLeft\s*=\s*0;\s*treeScroll\.scrollTop\s*=\s*0/.test(js));
ok('R21 zoom reflow sets width:(100/zoom)%',
  /treeCanvas\.style\.width\s*=\s*\(100\s*\/\s*zoom\)\s*\+\s*'%'/.test(js));
ok('R22 v2: applyPaneTab uses class-based state (.pane-tab-*) and persists to ctree-pane-tab',
  /function applyPaneTab\s*\(/.test(js)
  && /classList\.add\('pane-tab-' \+ name\)/.test(js)
  && /localStorage\.setItem\(PANE_TAB_KEY,\s*name\)/.test(js)
  && /paneTabs\.addEventListener\('click'/.test(js));
ok('R22b v2: drawer toggles use class-based state (.side-open / .side-hidden) + paneToggle/rightClose/panePeek wired + resize listener',
  /function applySideState\s*\(/.test(js)
  && /classList\.add\('side-(open|hidden)'\)/.test(js)
  && /paneToggle\.addEventListener\('click'/.test(js)
  && /rightClose\.addEventListener\('click'/.test(js)
  && /panePeek\.addEventListener\('click'/.test(js)
  && /window\.addEventListener\('resize'/.test(js));

const schema = fs.readFileSync(path.join(D, '..', 'state', 'schema.js'), 'utf8');
const reducer = fs.readFileSync(path.join(D, '..', 'state', 'reducer.js'), 'utf8');

// snackbar + undo + ✕
ok('R23 snackbar() with undo button + ✕, 10s vs 2.6s timer',
  /function snackbar\s*\(/.test(js)
  && /sb-undo/.test(js) && /sb-x/.test(js)
  && /_pendingUndo\s*\?\s*10000\s*:\s*2600/.test(js));
ok('R24 ✕ → closeToast clears timer + cancels pending undo',
  /function closeToast\s*\(\)/.test(js)
  && /toast\._pendingUndo\s*=\s*null/.test(js)
  && /x\.addEventListener\('click',\s*closeToast\)/.test(js));
ok('R25 actWithUndo: leave-anim → silent post → undo snackbar',
  /function actWithUndo\s*\(/.test(js)
  && /function animateLeave\s*\(/.test(js)
  && /reducedMotion\s*\(\)/.test(js));
ok('R26 list enter/leave/flash keyframes + reduced-motion guard',
  /@keyframes li-enter/.test(C) && /@keyframes li-leave/.test(C) && /@keyframes li-flash/.test(C)
  && /@media \(prefers-reduced-motion: reduce\)/.test(C));

ok('R27 per-pane "+N new" badge: spans + diff + clear-on-look',
  /id="actionsNewBadge"/.test(html) && /id="backlogNewBadge"/.test(html)
  && /function diffNewIds\s*\(/.test(js) && /function updateNewBadges\s*\(/.test(js)
  && /clearNewBadge\('a'\)/.test(js) && /\.new-badge/.test(C));

ok('R28 item-details-set additive event',
  /'item-details-set'/.test(schema)
  && /'item-details-set':\s*\['node_id',\s*'item_id',\s*'details'\]/.test(schema)
  && /case 'item-details-set'/.test(reducer));
ok('R29 rich-details disclosure UI: renderItemDetails + .li-details',
  /function renderItemDetails\s*\(/.test(js) && /det-toggle/.test(js)
  && /\.li-details\s*\{/.test(C));

ok('R30 action-responded additive event',
  /'action-responded'/.test(schema)
  && /'action-responded':\s*\['node_id',\s*'item_id',\s*'response_text'\]/.test(schema)
  && /case 'action-responded'/.test(reducer));
ok('R31 inline Respond UI + responded state + Copy-to-Dispatch',
  /function respondable\s*\(/.test(js)
  && /function copyResponseForDispatch\s*\(/.test(js)
  && /respond-box/.test(js) && /responded — awaiting confirmation/.test(js)
  && /\.li\.responded\s*\{/.test(C));

ok('R32 item-unchecked additive inverse event',
  /'item-unchecked'/.test(schema)
  && /'item-unchecked':\s*\['node_id',\s*'item_id'\]/.test(schema)
  && /case 'item-unchecked'/.test(reducer)
  && /type:\s*'item-unchecked'/.test(js));

ok('R33 SCHEMA_VERSION still 1 (all v2 additions are additive)',
  /const SCHEMA_VERSION\s*=\s*1\s*;/.test(schema));

// ----- v2 redesign 2026-05-23 — modal contract -------------------------
ok('R57 v2: doc viewer is a CENTERED MODAL (NOT a resizable side drawer) and does NOT shift #layout',
  /id="docModal"[^>]*class="modal-card doc-modal"/.test(html)
  && /\.doc-modal\s*\{[^}]*width:\s*min\(820px,\s*92vw\)/.test(C)
  && !/#docModal\s*\{[^}]*right:\s*0/.test(C)
  && !/body\[data-doc-pane="open"\]\s*#layout\s*\{[^}]*margin-right/.test(C)
  && !/document\.body\.dataset\.docPane\s*=\s*'open'/.test(js)
  && !/function ensureDocResizeHandle\s*\(/.test(js)
  && !/DOC_PANE_W_KEY/.test(js)
  && /docScrim\.hidden\s*=\s*false/.test(js));

ok('R66 v2: openCtx does NOT set body.dataset.ctxPane (modal contract — no layout shift)',
  !/document\.body\.dataset\.ctxPane\s*=\s*['"]open['"]/.test(js));
ok('R67 v2: closeCtx does NOT touch body.dataset.ctxPane',
  !/delete document\.body\.dataset\.ctxPane;/.test(js));
ok('R68 v2: CSS contains NO body[data-ctx-pane=open] #layout margin-shift rule',
  !/body\[data-ctx-pane="open"\]\s*#layout\s*\{[\s\S]*?margin-right/.test(C));
ok('R69 v2: ctxPanel uses .modal-card .ctx-modal contract',
  /class="modal-card ctx-modal"/.test(html)
  && /\.ctx-modal\s*\{[^}]*width:\s*min\(640px,\s*92vw\)/.test(C)
  && !/\.ctx-panel[^}]*width:\s*var\(--ctx-pane-w/.test(C));
ok('R70 v2: dispatch composer modal #dispatchModal exists + wired open/close + branch-note-add emit',
  /id="dispatchModal"/.test(html)
  && /id="dispatchScrim"/.test(html)
  && /function openDispatchModal\s*\(nodeId/.test(js)
  && /function closeDispatchModal\s*\(\)/.test(js)
  && /post\(\{\s*type:\s*'branch-note-add'/.test(js)
  && /dispatchSend\.addEventListener\('click'/.test(js));

ok('R71 v2: tree pane full-height + uses --tree-col fixed-narrow column',
  /\.tree-pane\s*\{\s*grid-area:\s*tree/.test(C)
  && /grid-template-rows:\s*1fr/.test(C));
ok('R72 v2: no #layout grid-template-areas that stacks anything below the tree',
  !/grid-template-areas:\s*"tree\s+tree"/.test(C)
  && !/grid-template-areas:\s*"tree"\s+"actions"\s+"backlog"/.test(C)
  && !/grid-template-areas:\s*"tree"\s+"actions"/.test(C));
ok('R73 v2: #panePeek peek pill exists + click handler wired',
  /id="panePeek"/.test(html)
  && /\.pane-peek\s*\{/.test(C)
  && /panePeek\.addEventListener\('click'/.test(js));
ok('R74 v2: active right-panel tab persists across reload via ctree-pane-tab',
  /PANE_TAB_KEY\s*=\s*'ctree-pane-tab'/.test(js)
  && /localStorage\.getItem\(PANE_TAB_KEY\)\s*\|\|\s*'waiting'/.test(js));

// ----- v2 redesign UX-VR-13 — context-as-textarea pattern ---------------
ok('R75 UX-VR-13: schema has additive backlog-context-set event + reducer case',
  /'backlog-context-set'/.test(schema)
  && /'backlog-context-set':\s*\['item_id',\s*'context_text'\]/.test(schema)
  && /case 'backlog-context-set':/.test(reducer));
ok('R76 UX-VR-13: backlog capture form has a <textarea id="blContext"> (not <input>)',
  /<textarea id="blContext"/.test(html)
  && !/<input id="blContext"\s+type="text"/.test(html));
ok('R77 UX-VR-13: backlog-added carries context_text on capture (reducer persists it on the backlog item)',
  /post\(\{\s*type:\s*'backlog-added',[\s\S]{0,400}context_text:\s*ctx/.test(js)
  && /context_text:\s*ctxOnAdd/.test(reducer));
ok('R78 UX-VR-13: per-item context disclosure + edit textarea + "Add context →" affordance for empty items',
  /li-context-toggle/.test(js)
  && /\.li-context-toggle\s*\{/.test(C)
  && /\.li-context-toggle\.empty/.test(C)
  && /\+ Add context →/.test(js)
  && /\.context-area\s*\{[^}]*resize:\s*vertical/.test(C)
  && /post\(\{\s*type:\s*'backlog-context-set',\s*item_id:\s*b\.item_id,\s*context_text:\s*nv\s*\}/.test(js));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
