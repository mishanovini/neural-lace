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
// Phase D (2026-06-09) — the all-work filter set now tracks work to DEPLOYED:
// `shipped-not-deployed` (efforts that did NOT reach prod) + `deployed` joined
// the original seven.
const FILTERS = ['awaiting-me', 'in-flight', 'blocked', 'shipped-not-deployed',
  'deployed', 'recently-shipped', 'orphaned', 'backlog', 'all'];
ok('R6 filter chip bar present with all seven filters',
  /id="filterBar"/.test(html) && FILTERS.every(f => new RegExp('data-filter="' + f + '"').test(html)));
ok('R7 stacked Waiting/Backlog/Decisions/Questions accordion is GONE',
  !/data-panel-toggle/.test(html) && !/class="apanel/.test(html) && !/id="paneStack"/.test(html));
ok('R8 default active filter = awaiting-me (non-complete by default)',
  /workstreams\.activeFilter['"]\)\s*\|\|\s*['"]awaiting-me['"]/.test(js));
// Phase D (2026-06-09) — the detail view is now a dismissible MODAL OVERLAY
// (id="detailModal" + scrim), NOT a list-replacing card. The filter list stays
// put behind it (overlay model). This is Misha's repeatedly-flagged regression
// fix: selecting an item must open a modal in front of everything, not fill the
// right pane.
ok('R9 detail is a dismissible MODAL OVERLAY (scrim + modal, list stays behind)',
  /id="detailModal"/.test(html) && /id="detailScrim"/.test(html)
  && /class="modal-card detail-modal"/.test(html) && /\.detail-modal\s*\{/.test(C));

// --- wire-check function chains (Tasks 3 / 4 / 5) -------------------------
const TASK3 = ['renderTree', 'collectWorkstreams', 'renderWorkstream', 'collectWorkItems'];
const TASK4 = ['setActiveFilter', 'renderFilteredItems', 'applyFilter'];
// Phase D — the detail handler is openDetailModal (the modal opener), plus the
// new context-appropriate action-button builder and the decision-recorder.
const TASK5 = ['openDetailModal', 'closeDetailModal', 'collectProvenance',
  'collectSubtasks', 'buildActionButtons', 'recordDecision'];
function defines(fn) { return new RegExp('function\\s+' + fn + '\\s*\\(').test(js); }
ok('R10 Task-3 tree chain defined (renderTree → collectWorkstreams → renderWorkstream → collectWorkItems)',
  TASK3.every(defines));
ok('R11 Task-4 filter chain defined (setActiveFilter → renderFilteredItems → applyFilter)',
  TASK4.every(defines));
ok('R12 Task-5 detail chain defined (openDetailModal → buildActionButtons → recordDecision; collectProvenance/collectSubtasks)',
  TASK5.every(defines));

// --- four-tier hierarchy + sessions-as-provenance -------------------------
ok('R13 sessions (sess-*/sub-*) are hidden from the tree (isSession predicate)',
  /function\s+isSession\s*\([^)]*\)\s*\{[^}]*\/\^\(sess\|sub\)-\//.test(js));
ok('R14 tiered render: Repo → Project → Workstream → WorkItem via guide-rail containers',
  // Repo top tier (renderRepoGroup + reposOf) + Project rows + derived Workstream
  // tier (renderDerivedWorkstreams) + guide-rail nesting (.tree-kids) + per-row
  // data-depth. The OLD per-depth `tree-item d<n>` classes AND the wrong
  // kind-grouping (renderKindGroups) are both retired — indent comes from the
  // nesting container, kinds are per-item badges not a nesting axis (2026-06-03).
  /function\s+renderRepoGroup\s*\(/.test(js) && /function\s+reposOf\s*\(/.test(js)
  && /function\s+renderDerivedWorkstreams\s*\(/.test(js)
  && /['"]proj['"]/.test(js) && /['"]ws['"]/.test(js)
  && /['"]tree-kids/.test(js) && /setAttribute\(['"]data-depth['"]/.test(js)
  && !/renderKindGroups/.test(js));
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

// --- Phase D: context-appropriate action buttons (requirement 3) ----------
// Decision/question resolution emits `answered` + records the choice via
// `item-details-set`; actions emit `action-done`; EVERY item can `action-responded`
// (respond-with-details / ask-clarifying without resolving).
ok('R23 context-appropriate buttons emit answered / action-done / action-responded / item-details-set',
  /type:\s*['"]answered['"]/.test(js)
  && /type:\s*['"]action-done['"]/.test(js)
  && /type:\s*['"]action-responded['"]/.test(js)
  && /type:\s*['"]item-details-set['"]/.test(js));

// --- Phase D: track ALL work to DEPLOYED (requirement 4) ------------------
// New filters surface efforts that did NOT reach prod (shipped-not-deployed)
// and those that did (deployed); a Mark-deployed button emits item-deployed.
ok('R24 deploy-tracking: shipped-not-deployed + deployed filters + item-deployed event',
  /case 'shipped-not-deployed'/.test(js) && /case 'deployed'/.test(js)
  && /function\s+isDeployed\s*\(/.test(js)
  && /type:\s*['"]item-deployed['"]/.test(js));

// --- Phase D / I5 (Task 10): modal dismissal via the OVERLAY STACK ---------
// The two ad-hoc document-level Esc handlers and the per-overlay scrim
// listeners are RETIRED; ONE overlay-stack manager owns Esc (topmost layer
// only), scrim clicks (own layer only), focus trap, and focus restore.
ok('R25 modal dismissal wired through the overlay stack (✕ + bindScrim; ad-hoc Esc/scrim handlers retired)',
  /var overlayStack = \(function \(\)/.test(js)
  && /dmClose\.addEventListener\(['"]click['"],\s*closeDetailModal\)/.test(js)
  && /overlayStack\.bindScrim\(detailScrim\)/.test(js)
  && /overlayStack\.bindScrim\(docScrim\)/.test(js)
  && !/detailScrim\.addEventListener/.test(js)              // old direct scrim hook gone
  && !/docScrim\.addEventListener/.test(js)                 // old combined docs scrim hook gone
  && !/e\.key === 'Escape' && !detailModal\.hidden/.test(js)); // old ad-hoc Esc gone
ok('R29 overlay stack invariants: Esc closes TOPMOST only; focus trap + restore on close',
  /if \(e\.key === 'Escape'\) \{ e\.preventDefault\(\); close\(t\.el\); return; \}/.test(js)
  && /layer\.prevFocus = document\.activeElement/.test(js)
  && /scrimStillNeeded/.test(js)                            // shared docScrim stays while a layer uses it
  && /if \(e\.key !== 'Tab'\) return;/.test(js));           // focus trap wraps Tab inside the top layer

// --- Phase D: full Phase-C context renders inside the modal ---------------
ok('R26 modal renders full Phase-C context via renderItemDetails (Background/options/recommendation/links)',
  /dmBody\.appendChild\(renderItemDetails\(/.test(js)
  && /function\s+renderItemDetails\s*\(/.test(js));

// --- R5 render fix (2026-06-09): fence fields render WITHOUT _category -----
// The R1-enriched onboarding items carry background / about / the_ask /
// why_asking / why_assigned in `details` with NO `_category` stamp; the old
// renderer dropped those rows because every fence-grammar content row was
// gated behind `details._category` (the R4 root cause, app.js ~line 852).
// Invariant: inside renderItemDetails, all five rows are emitted by
// presence-based detailRow calls, and NO content row is gated on a
// category-equality check or a block-form `if (dcCat) {` gate — `_category`
// only selects the Kind/urgency header chip via dcCategoryHeader().
const ridStart = js.indexOf('function renderItemDetails');
const ridEnd = js.indexOf('function openDetailModal');
const rid = (ridStart >= 0 && ridEnd > ridStart) ? js.slice(ridStart, ridEnd) : '';
ok('R27 background/about/the_ask/why_asking/why_assigned render without _category',
  rid.length > 0
  && /detailRow\('About',\s*de\.about/.test(rid)
  && /detailRow\('Background',\s*de\.background/.test(rid)
  && /detailRow\('The ask',\s*de\.the_ask/.test(rid)
  && /detailRow\('Why asking',\s*de\.why_asking/.test(rid)
  && /detailRow\('Why assigned',\s*de\.why_assigned/.test(rid)
  && !/dcCat\s*===/.test(rid)            // no category-equality content gates
  && !/if\s*\(dcCat\)\s*\{/.test(rid)    // no block-form gate that could swallow rows
  && /function\s+dcCategoryHeader\s*\(/.test(js)); // chips extra still exists, gated

// --- In-modal doc links open IN-APP (2026-06-11, operator-directed) --------
// Doc references in details text (docs/… paths AND bare *.md names like
// REDESIGN-PRD-DRAFT-2026-06-10.md) render as clickable button chips that open
// the doc in the in-app Docs viewer: openDocSmart probes /api/doc candidates
// (item project → neural-lace → workstreams-coordination; bare names try the
// coordination repo first) → openDocInApp bridge → openDocModal. The viewer
// layers ABOVE the detail modal (#docScrim 61 / #docModal 62 vs modal-card 60)
// and Esc closes the viewer first — since I5 (Task 10) that ordering comes
// from the overlay STACK (the viewer is the topmost pushed layer), not from
// a hand-rolled early-return. DOM built via textContent only — no innerHTML.
ok('R28 doc references in the detail modal are clickable and open in-app',
  /function\s+openDocSmart\s*\(/.test(js)
  && /openDocInApp\s*=\s*openDocModal/.test(js)
  && js.indexOf("el('button', 'det-link det-link-doc'") !== -1
  && js.indexOf('var DOC_REF_RE') !== -1
  && js.indexOf('\\.md\\b') !== -1                       // bare *.md names match
  && /workstreams-coordination/.test(js)                  // coordination-repo candidate
  && /el: docModal, scrim: docScrim/.test(js)             // viewer is an overlay-stack layer (Esc pops it first)
  && /button\.det-link-doc/.test(C)
  && /#docScrim\s*\{\s*z-index:\s*61/.test(C)
  && /#docModal\s*\{\s*z-index:\s*62/.test(C));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
