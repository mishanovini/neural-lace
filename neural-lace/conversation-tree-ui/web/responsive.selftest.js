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

// ===================== v1.1.1 polish invariants (14–23) =====================
const server = fs.readFileSync(path.join(D, '..', 'server', 'server.js'), 'utf8');
const backfill = fs.readFileSync(path.join(D, '..', 'state', 'backfill-details.js'), 'utf8');

// item 14 — type-colour palette: 3 vars + filled badge + per-card accent/tint
ok('R34 item14 type palette vars + filled .li-kind + .li.kind-* accent/tint',
  /--type-action:\s*#ef4444/i.test(C) && /--type-decision:\s*#f59e0b/i.test(C)
  && /--type-question:\s*#3b82f6/i.test(C)
  && /\.li-kind\.action\s*\{\s*background:\s*var\(--type-action\)/.test(C)
  && /\.li\.kind-action\s*\{\s*border-left:\s*5px solid var\(--type-action\)/.test(C)
  && /'li kind-' \+ it\.kind/.test(js));

// item 15 — title flex:1 + fixed-width icon jump button (text crumb removed)
ok('R35 item15 .li-text flex:1 + .li-jump 24px icon (no .li-crumb in renderActions)',
  /\.li-text\s*\{\s*flex:\s*1/.test(C) && /\.li-jump\s*\{[^}]*24px/.test(C)
  && /el\('button',\s*'li-jump',\s*'→'\)/.test(js)
  && /Jump to in tree/.test(js)
  && !/el\('span',\s*'li-crumb'/.test(js));

// item 16 — hide-concluded relocated into the tree pane-head + default=hide
ok('R36 item16 #showConcluded inside tree pane-head .viewtoggle + default OFF=hide',
  /class="viewtoggle"[\s\S]{0,140}id="showConcluded"/.test(html)
  && !/id="showConcluded"[^>]*>\s*show concluded\s*<\/label>\s*<span class="spacer"/.test(html)
  && /ctree-show-concluded'\)\s*===\s*'1'/.test(js)
  && /\.viewtoggle\s*\{/.test(C));

// item 17 — bidirectional interior wash + auto-scroll both directions
ok('R37 item17 .li.hl/.tnode-row.hl interior wash + bidirectional scroll wiring',
  /\.li\.hl,\s*\.tnode-row\.hl\s*\{[^}]*linear-gradient/.test(C)
  && /row\.classList\.add\('hl'\)/.test(js)
  && /selItem\s*=\s*it\.item_id;\s*focusNode/.test(js)
  && /actionsBody\.querySelector\('\.li\[data-node="'/.test(js)
  && /scrollIntoView\(\{\s*block:\s*'center',\s*behavior:\s*'smooth'/.test(js));

// item 18 — toast bottom-right (no left:50% in base) + arrive flash + RM clause
ok('R38 item18 toast bottom-right + @keyframes arrive + reduced-motion variant',
  /\.toast\s*\{\s*position:\s*fixed;\s*right:\s*1\.2rem;\s*bottom:\s*1\.2rem;/.test(C)
  && !/\.toast\s*\{[^}]*left:\s*50%/.test(C)
  && /@keyframes arrive/.test(C)
  && /\.arrive-static/.test(C)
  && /prefers-reduced-motion: reduce\)\s*\{[^}]*\.li\.arrive/.test(C)
  && /function arriveCls\s*\(\)/.test(js) && /function sweepArriveStatic\s*\(\)/.test(js));

// item 19 — cross-repo doc viewer end-to-end tokens
ok('R39 item19 server endpoints + projects two-layer + mdRender + modal/panel',
  /url === '\/api\/doc'/.test(server) && /url === '\/api\/docs'/.test(server)
  && /url === '\/api\/doc\/open'/.test(server)
  && /path traversal rejected/.test(fs.readFileSync(path.join(D,'..','config','projects.js'),'utf8'))
  && fs.existsSync(path.join(D,'..','config','projects.example.json'))
  && fs.existsSync(path.join(D,'..','config','.gitignore'))
  && /function mdRender\s*\(/.test(js) && /function openDocModal\s*\(/.test(js)
  && /function openDocsPanel\s*\(/.test(js) && /function linkifyDocs\s*\(/.test(js)
  && /id="docModal"/.test(html) && /id="docsPanel"/.test(html) && /id="docsBtn"/.test(html));

// item 20 — "promote"→"expand to branch"; event type stays `promoted`
ok('R40 item20 expand-to-branch rename; promoted event type preserved',
  !/promote to branch/i.test(js) && !/promoted to branch/i.test(js)
  && /'expand to branch'/.test(js) && /'expanded to branch'/.test(js)
  && /type:\s*'promoted'/.test(js));

// item 21 — robust priority sort: execute the extracted prioRank logic
(function () {
  var a = js.indexOf('function prioRank');
  var b = js.indexOf('function sortBacklog');
  var ok21 = false;
  if (a !== -1 && b !== -1 && b > a) {
    try {
      // eslint-disable-next-line no-eval
      var prioRank = eval('(' + js.slice(a, b).replace(/^function prioRank/, 'function') + ')');
      var input = ['P3', 'P1', 'P2'];
      var out = input.slice().sort(function (x, y) { return prioRank(x) - prioRank(y); });
      var mixed = ['low', 'high', 'medium'].slice().sort(function (x, y) { return prioRank(x) - prioRank(y); });
      ok21 = out.join(',') === 'P1,P2,P3'
        && mixed.join(',') === 'high,medium,low'
        && prioRank('high') === 0 && prioRank('1') === 0 && prioRank('zzz') === 9;
    } catch (e) { ok21 = false; }
  }
  ok('R41 item21 prioRank([P3,P1,P2]) → [P1,P2,P3] (and high/p1/1→0, unknown→9)', ok21);
})();

// item 22 — semantic button palette: 6 classes defined + applied in app.js
ok('R42 item22 six semantic btn classes defined + applied',
  /\.btn-go\s*\{/.test(C) && /\.btn-wait\s*\{/.test(C) && /\.btn-info\s*\{/.test(C)
  && /\.btn-up\s*\{/.test(C) && /\.btn-del\s*\{/.test(C) && /\.btn-neutral\s*\{/.test(C)
  && /\.outline\b/.test(C)
  && /'btn-go'/.test(js) && /'btn-wait'/.test(js) && /'btn-info'/.test(js)
  && /'btn-up'/.test(js) && /'btn-del outline'/.test(js) && /'btn-neutral/.test(js));

// item 23 — cross-repo doc-sourced enrichment present (no fabrication path)
ok('R43 item23 backfill resolveDocPath + extractFromDoc wired into payloadFor',
  /function resolveDocPath\s*\(/.test(backfill)
  && /function extractFromDoc\s*\(/.test(backfill)
  && /require\('\.\.\/config\/projects\.js'\)/.test(backfill)
  && /links\.find\(function \(l\) \{ return \/\^docs\\\//.test(backfill));

// --- v1.1.2 polish items 26/27/28 (item 25 = merged item 22, covered by R42)
ok('R44 item26: Details toggles IN PLACE (no renderActions rebuild) + scrollIntoView nearest (no scroll reset)',
  /disc\.addEventListener\('click', function \(\) \{[\s\S]*?li\.scrollIntoView\(\{ block: 'nearest' \}\);[\s\S]*?\}\);/.test(js)
  && /li\.querySelector\('\.li-details'\)/.test(js)
  && /li\.insertBefore\(d, disc\.nextSibling\)/.test(js)
  && /el\('button', 'ghost det-toggle',/.test(js));   // item-22 chose ghost; item 26 fixes scroll only

ok('R45 item27: decision/question resolve ONLY via Respond — done button gated to kind==="action", no "mark answered"',
  /if \(it\.kind === 'action'\) \{\s*\n?\s*var done = el\('button', 'btn-go', 'mark done'\)/.test(js)
  && !/mark answered/.test(js)
  && /function respondable\s*\(/.test(js));

ok('R46 item28: friendly Defer popover (presets + native datetime-local + to-Backlog) + item-backlogged ADDITIVE + deferred local-time fields + isWaiting excludes backlogged + SCHEMA_VERSION still 1',
  /function openDeferPop\s*\(/.test(js)
  && /dti\.type = 'datetime-local'/.test(js)
  && /Later today \(8 PM\)/.test(js) && /Tomorrow morning \(9 AM\)/.test(js)
  && /Next week \(Mon 9 AM\)/.test(js) && /Pick a specific time/.test(js)
  && /Until further notice — move to Backlog/.test(js)
  && /\.defer-pop\s*\{/.test(C)
  && !/prompt\('Defer until/.test(js)
  && /\(\(!it\.checked\) \|\| it\.deferred \|\| it\.contested\) && !it\.backlogged/.test(js)
  && /'item-backlogged'/.test(schema)
  && /'item-backlogged':\s*\['node_id',\s*'item_id'\]/.test(schema)
  && /case 'item-backlogged'/.test(reducer)
  && /it\.scheduled_for_local = String\(ev\.scheduled_for_local\)/.test(reducer)
  && /it\.tz_offset_min = Number\(ev\.tz_offset_min\)/.test(reducer)
  && /const SCHEMA_VERSION\s*=\s*1\s*;/.test(schema));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
