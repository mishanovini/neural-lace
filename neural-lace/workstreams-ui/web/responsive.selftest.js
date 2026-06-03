'use strict';
/* Workstreams UI — v2 work-first reframe structural regression self-test.
 * Dependency-free (Node stdlib only; reads the three web/ source files as text
 * and greps for the load-bearing invariants of the reframe). No build step, no
 * headless-browser dep — runs in CI. Behavioural rendering against live data is
 * covered separately (the headless render harness + Misha's browser confirm).
 *
 * Supersedes the v3-accordion responsive selftest: the stacked Waiting/Backlog/
 * Decisions/Questions accordion is gone, replaced by a filter-driven single
 * pane + detail card + adjustable divider (per workstreams-design-v2).
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

// --- rename ---------------------------------------------------------------
ok('R1 product renamed to Workstreams (title + h1)',
  /<title>\s*Workstreams\s*<\/title>/.test(html) && /<h1>\s*Workstreams\s*<\/h1>/.test(html));

// --- layout fundamentals --------------------------------------------------
const bodyBlock = (C.match(/(^|})\s*body\s*\{([^}]*)\}/) || [, , ''])[2];
ok('R2 body{} no off-screen min-width:1440px / min-height:900px bug',
  bodyBlock.length > 0 && !/min-width:\s*1440px/.test(bodyBlock) && !/min-height:\s*900px/.test(bodyBlock));
ok('R3 #layout is CSS grid', /#layout\s*\{[^}]*display:\s*grid/.test(C));
ok('R4 adjustable divider: grid uses --tree-w + a "divider" grid area',
  /grid-template-columns:\s*var\(--tree-w[^)]*\)\s*6px\s*1fr/.test(C)
  && /grid-template-areas:\s*"tree divider side"/.test(C));
ok('R5 divider element present + draggable (col-resize cursor)',
  /id="divider"/.test(html) && /#divider[^}]*cursor:\s*col-resize/.test(C));

// --- filter-driven side panel (replaces the accordion) --------------------
const FILTERS = ['awaiting-me', 'in-flight', 'blocked', 'recently-shipped', 'orphaned', 'backlog', 'all'];
ok('R6 filter chip bar present with all seven filters',
  /id="filterBar"/.test(html) && FILTERS.every(f => new RegExp('data-filter="' + f + '"').test(html)));
ok('R7 stacked Waiting/Backlog/Decisions/Questions accordion is GONE',
  !/data-panel-toggle/.test(html) && !/class="apanel/.test(html) && !/id="paneStack"/.test(html));
ok('R8 default active filter = awaiting-me (non-complete by default)',
  /workstreams\.activeFilter['"]\)\s*\|\|\s*['"]awaiting-me['"]/.test(js));
ok('R9 detail card slot present (replaces filter view on selection)',
  /id="detailCard"/.test(html) && /\.detail-card\s*\{/.test(C));

// --- wire-check function chains (Tasks 3 / 4 / 5) -------------------------
const TASK3 = ['renderTree', 'collectWorkstreams', 'renderWorkstream', 'collectWorkItems'];
const TASK4 = ['setActiveFilter', 'renderFilteredItems', 'applyFilter'];
const TASK5 = ['renderDetailCard', 'collectProvenance', 'collectSubtasks'];
function defines(fn) { return new RegExp('function\\s+' + fn + '\\s*\\(').test(js); }
ok('R10 Task-3 tree chain defined (renderTree → collectWorkstreams → renderWorkstream → collectWorkItems)',
  TASK3.every(defines));
ok('R11 Task-4 filter chain defined (setActiveFilter → renderFilteredItems → applyFilter)',
  TASK4.every(defines));
ok('R12 Task-5 detail chain defined (renderDetailCard → collectProvenance → collectSubtasks)',
  TASK5.every(defines));

// --- four-tier hierarchy + sessions-as-provenance -------------------------
ok('R13 sessions (sess-*/sub-*) are hidden from the tree (isSession predicate)',
  /function\s+isSession\s*\([^)]*\)\s*\{[^}]*\/\^\(sess\|sub\)-\//.test(js));
ok('R14 hierarchy render: project rows, kind-group intermediate tier, guide-rail nesting',
  // Project + Workstream rows + the derived Kind-group tier (renderKindGroups)
  // + nesting via .tree-kids guide-rail containers + per-row data-depth. The
  // OLD per-depth `tree-item d<n>` margin classes were retired (flat-list bug,
  // 2026-06-02) because they styled tiers the data never produced — indent now
  // comes from the nesting container, so depth is carried as a data attribute.
  /['"]proj['"]/.test(js) && /['"]ws['"]/.test(js)
  && /function\s+renderKindGroups\s*\(/.test(js)
  && /['"]tree-group/.test(js) && /['"]tree-kids['"]/.test(js)
  && /setAttribute\(['"]data-depth['"]/.test(js));
ok('R15 orphan surface present (section + Orphaned filter, session-based)',
  /id="orphanSection"/.test(html) && /function\s+staleSessions\s*\(/.test(js));

// --- Phase-1 lifecycle events emitted from the detail card ----------------
ok('R16 detail card action buttons emit item-shipped / item-blocked / item-committed',
  /type:\s*['"]item-shipped['"]/.test(js)
  && /type:\s*['"]item-blocked['"]/.test(js)
  && /type:\s*['"]item-committed['"]/.test(js));

// --- preserved plumbing ----------------------------------------------------
ok('R17 reads file-contract via SSE (/api/events "state") + writes via POST /api/event',
  /new EventSource\(['"]\/api\/events['"]\)/.test(js)
  && /fetch\(['"]\/api\/event['"]/.test(js));
ok('R18 POST /api/event retried once with backoff (no silent loss)',
  /attempt\(\s*Math\.min\(delay\s*\*\s*2/.test(js));
ok('R19 backlog capture: multi-line context TEXTAREA preserved (UX-VR-13)',
  /<textarea id="blContext"/.test(html) && /type:\s*['"]backlog-added['"]/.test(js));
ok('R20 localStorage persistence keys for filter + pane split',
  /workstreams\.activeFilter/.test(js) && /workstreams\.paneSplit/.test(js));
ok('R21 Option-2 invariant: no spawn/continue/resume/feed affordance',
  !/\/api\/(spawn|continue|resume|feed|steer)/.test(js));

// --- narrow-width responsiveness ------------------------------------------
ok('R22 narrow width (<=860px) stacks the two panes single-column',
  /@media\s*\(max-width:\s*860px\)[^}]*#layout\s*\{[^}]*grid-template-areas:\s*"tree"\s*"side"/.test(C.replace(/\s+/g, ' ')));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
