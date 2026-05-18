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

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
