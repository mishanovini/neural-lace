'use strict';
/* Workstreams UI — status-precedence + show-completed-filter behavioral self-test.
 *
 * Originating bug (2026-06-17, operator report): `PLAN: … [ACTIVE]` work-items were
 * badged "shipped" and shown in the left Projects tree even with "show completed"
 * OFF. Two interacting defects, both fixed in web/app.js:
 *   (1) Status mismatch — itemState() returned 'shipped' for an item whose own text
 *       declared the plan still [ACTIVE] (a past PR-merge/deploy emitter wrote
 *       item-shipped while the plan was ACTIVE — "bookkeeping debt"). The merge
 *       signal overrode the plan's authoritative ACTIVE status.
 *   (2) Filter leak — branchGroup's `allDone || visibleInTree(r)` short-circuit
 *       rendered a single-item all-done branch's (falsely-)shipped item regardless
 *       of the show-completed filter.
 *
 * This test exercises the REAL functions extracted from web/app.js source (no
 * replica): the pure predicates itemState / planStatusSaysOpen / isComplete are
 * lifted verbatim and run in a Node sandbox, with the DOM-bound visibleInTree
 * given stubbed show-completed / show-archived globals. It additionally validates
 * the fix against the live snapshot when one is reachable (best-effort, skipped if
 * absent). Dependency-free; runs in CI.
 *
 * Run: `node state/filter-status.selftest.js`  (exit 0 OK / 1 FAIL)
 */
const fs = require('fs');
const path = require('path');

const APP_JS = path.join(__dirname, '..', 'web', 'app.js');
const src = fs.readFileSync(APP_JS, 'utf8');

let pass = 0, fail = 0;
function ok(name, cond) {
  if (cond) { pass++; console.log('  PASS  ' + name); }
  else { fail++; console.log('  FAIL  ' + name); }
}

// ---- extract a named function declaration's source via balanced-brace scan ----
function extractFn(name) {
  const re = new RegExp('function\\s+' + name + '\\s*\\(');
  const m = re.exec(src);
  if (!m) return null;
  let i = src.indexOf('{', m.index);
  if (i < 0) return null;
  let depth = 0;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(m.index, i + 1); }
  }
  return null;
}

const srcItemState = extractFn('itemState');
const srcPlanOpen = extractFn('planStatusSaysOpen');
const srcIsComplete = extractFn('isComplete');
const srcVisibleInTree = extractFn('visibleInTree');

ok('E1 itemState() extractable from app.js', !!srcItemState);
ok('E2 planStatusSaysOpen() extractable (the precedence guard exists)', !!srcPlanOpen);
ok('E3 isComplete() extractable', !!srcIsComplete);
ok('E4 visibleInTree() extractable', !!srcVisibleInTree);

// ---- build a sandbox that hosts the real functions ----
// COMPLETE_STATES is referenced by isComplete; the show* checkboxes by
// visibleInTree. Provide them as stubs the real source closes over.
const showArchived = { checked: false };
const showCompleted = { checked: false };
const COMPLETE_STATES = { shipped: 1 };

// eslint-disable-next-line no-eval
const factory = new Function(
  'showArchived', 'showCompleted', 'COMPLETE_STATES',
  [
    srcPlanOpen,
    srcItemState,
    srcIsComplete,
    srcVisibleInTree,
    'return { planStatusSaysOpen: planStatusSaysOpen, itemState: itemState,'
    + ' isComplete: isComplete, visibleInTree: visibleInTree };',
  ].join('\n')
);
const F = factory(showArchived, showCompleted, COMPLETE_STATES);

// ---- (A) status precedence: a [ACTIVE]-text item is never 'shipped' ----------
const activeButShipped = {
  text: 'PLAN: Import Pipeline Overhaul — C-09 / C-10 [ACTIVE]',
  state: 'shipped', checked: true,
};
ok('A1 [ACTIVE] item with state=shipped derives a non-complete state',
  F.itemState(activeButShipped) !== 'shipped');
ok('A2 [ACTIVE] item derives in-flight (truthful open state)',
  F.itemState(activeButShipped) === 'in-flight');
ok('A3 [ACTIVE] item is NOT isComplete',
  F.isComplete(activeButShipped) === false);

// blocked signal is preserved through the override
const activeButContested = { text: 'PLAN: X [ACTIVE]', state: 'shipped', contested: true };
ok('A4 [ACTIVE] + contested derives blocked (block signal preserved)',
  F.itemState(activeButContested) === 'blocked');

// deferred-but-still-listed [ACTIVE] preserves committed
const activeDeferred = { text: 'PLAN: Y [ACTIVE]', state: 'shipped', deferred: true };
ok('A5 [ACTIVE] + deferred derives committed',
  F.itemState(activeDeferred) === 'committed');

// ---- (B) genuine shipped (no [ACTIVE] marker) still ships --------------------
const reallyShipped = { text: 'PLAN: Old Plan [COMPLETED]', state: 'shipped', checked: true };
ok('B1 genuinely-shipped item (no [ACTIVE]) stays shipped',
  F.itemState(reallyShipped) === 'shipped');
ok('B2 genuinely-shipped item is isComplete',
  F.isComplete(reallyShipped) === true);
const legacyChecked = { text: 'some shipped task', checked: true };
ok('B3 legacy checked item (no state, no [ACTIVE]) stays shipped',
  F.itemState(legacyChecked) === 'shipped');

// ---- (C) show-completed filter inclusion/exclusion ---------------------------
// The fixed [ACTIVE] item: not complete => visible even with show-completed OFF
showCompleted.checked = false; showArchived.checked = false;
ok('C1 [ACTIVE]-fixed item is INCLUDED with show-completed=false (it is in-flight)',
  F.visibleInTree({ item: activeButShipped }) === true);
// A genuinely-shipped item: hidden with show-completed OFF, shown with it ON
ok('C2 genuinely-shipped item is EXCLUDED with show-completed=false',
  F.visibleInTree({ item: reallyShipped }) === false);
showCompleted.checked = true;
ok('C3 genuinely-shipped item is INCLUDED with show-completed=true',
  F.visibleInTree({ item: reallyShipped }) === true);
showCompleted.checked = false; showArchived.checked = true;
ok('C4 genuinely-shipped item is INCLUDED with show-archived=true',
  F.visibleInTree({ item: reallyShipped }) === true);
showArchived.checked = false;

// ---- (D) branchGroup no longer bypasses the filter via allDone ---------------
// Structural guard: the old `allDone || visibleInTree(r)` short-circuit is gone;
// the visible set is filtered by visibleInTree alone.
ok('D1 branchGroup visible-set filters by visibleInTree (allDone bypass removed)',
  /var visible = refs\.filter\(function \(r\) \{ return visibleInTree\(r\); \}\);/.test(src)
  && !/return allDone \|\| visibleInTree\(r\);/.test(src));

// ---- (E) live-snapshot validation (best-effort; skipped if unreachable) ------
(function liveCheck() {
  let resolver;
  try { resolver = require('./resolve-state-path.js'); } catch (_) { return; }
  let sp;
  try { sp = resolver.resolveWorkstreamsStatePath(null); } catch (_) { return; }
  if (!sp) { console.log('  SKIP  E (no canonical state path configured)'); return; }
  let S;
  try { S = JSON.parse(fs.readFileSync(sp, 'utf8')); } catch (_) {
    console.log('  SKIP  E (state file unreadable: ' + sp + ')'); return;
  }
  const snap = S.snapshot || S;
  const nodes = snap.nodes || {};
  const all = Array.isArray(nodes) ? nodes : Object.values(nodes);
  let activeShippedAfterFix = 0, totalActiveText = 0;
  for (const n of all) {
    for (const it of (n.items || [])) {
      if (!/\[ACTIVE\]/i.test(String(it.text || ''))) continue;
      totalActiveText++;
      if (F.itemState(it) === 'shipped') activeShippedAfterFix++;
    }
  }
  if (totalActiveText === 0) { console.log('  SKIP  E (no [ACTIVE] items in live state)'); return; }
  ok('E5 LIVE: zero [ACTIVE]-text items derive shipped after the fix ('
    + totalActiveText + ' [ACTIVE] items checked)', activeShippedAfterFix === 0);
})();

console.log('\nfilter-status self-test: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
