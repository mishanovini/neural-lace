# Evidence — Tasks 3 / 4 / 5 (cockpit · waiting-on-you · per-project tree)

Plan: `docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md`
Branch: `worker-ws-cockpit` · Code commit: `f830be4`
Builder: plan-phase-builder (PARALLEL protocol — task-verifier NOT invoked; orchestrator runs it post-merge)

Files changed (all in declared plan scope):
- `neural-lace/workstreams-ui/web/app.js` — cockpit / drill / waiting renderers + predicates
- `neural-lace/workstreams-ui/web/app.css` — status-surface styles + C6 color-class retirement
- `neural-lace/workstreams-ui/web/index.html` — "Awaiting me" chip relabeled "Waiting on you"
- `neural-lace/workstreams-ui/scripts/regression.e2e.js` — relocked to the new design (17 assertions)
- `docs/plans/...-evidence/*.jpg` — six runtime screenshots (1280 / 768 / 390)

Runtime environment: server `node server/server.js` (port 7799) against a local COPY of the
operator's live `tree-state.json` (123 items / 78 nodes / lopsided: neural-lace 35, global 60,
cortex-one 2) so click-testing could not mutate the operator's real state file. All browser
evidence is headless Chrome via the project's puppeteer-core harness.

---

## Task 3 — Cockpit (done-when mapping)

| Prove-it step | Evidence |
|---|---|
| 1. open the GUI | e2e T0/T1 (fresh page, localStorage cleared → cockpit is the default left pane). Screenshot `cockpit-1280.jpg`. |
| 2. one row per project with now/next/waiting/done counts | T1: `ckRows=6 4pills=true numeric=true`, repo-grouped (4 repo heads), sticky NOW/NEXT/WAITING/DONE column header. |
| 3. counts match the reduced state | T2: per-project cross-check against an `/api/state` oracle that independently re-derives the buckets — `all 6 project rows match the reduced state`. Header summary `20 waiting · 9 now · 35 next · 52 done`. |
| 4. dozens of items → a NUMBER, not overflowing chips | T1 `treeItemsInCockpit=0`; T3 row heights `36..36px` constant — the 60-item Cross-project root and 35-item neural-lace each occupy exactly one row. |

Wire checks (static): `web/app.js` `renderTree`→`cockpitRows`→`allWorkItems`/`statusCounts` reads the
snapshot the reducer (`state/reducer.js`) folds; served by `server/server.js` (`/`, `/api/state`, SSE).
Integration: `curl localhost:7799/` returns the cockpit DOM shell; `/api/health` ok (T15).

## Task 4 — Waiting-on-you list (done-when mapping)

| Prove-it step | Evidence |
|---|---|
| 1. open the GUI | default filter is `awaiting-me` (relabeled "Waiting on you"). Screenshot `waiting-1280.jpg`. |
| 2. ONLY items needing the operator | T10: `waitRows=20 (oracle=20)` — bounded; row set === isWaitingOnYou set (unanswered Misha-asks + blocked). |
| 3. background + recommendation inline; empty details ≠ bare actionable title | T10 `bare=0` — every row carries either an inline context summary or the visible neutral "context incomplete — needs enrichment" marker (the live data's 20 waiting items are all detail-less → all 20 flagged, none painted decision-ready). Context-COMPLETE path proven by live round-trip: POSTed a decision + `item-details-set` (background/options/recommendation) via `/api/event`, row rendered `wait-bg` = the background sentence and `wait-rec` = "→ option B — launch Tuesday…" with no incomplete badge. Screenshot `waiting-context-complete-1280.jpg`. |

Wire checks: `web/app.js` `renderWaitingInto`→`applyFilter('awaiting-me')`→`isWaitingOnYou`→
`itemState`/`isAwaitingMe` over the reducer-derived snapshot (`state/reducer.js` item fields
`state/checked/contested/deferred/backlogged/responded/details`).

## Task 5 — Per-project drill tree (done-when mapping)

| Prove-it step | Evidence |
|---|---|
| 1. click a project in the cockpit | T4: drill renders bounded to that project (`title="neural-lace"`, 35 items, 10 branch groups). C4: persistent `← All projects` breadcrumb + project header + master-detail rail at 1280 (T4 `rail=true`); T9 breadcrumb returns to cockpit; T16 at 390px rail hides (full swap) and the breadcrumb remains. Screenshots `drill-1280.jpg`, `drill-390.jpg`. |
| 2. nested with guide lines | T4: `.tree-kids` guide rails present, item indent +29px under branch heads. |
| 3. amber marks ONLY needs-you/blocked | T5: amber-marked row set === oracle needs-set (`amberRows=10 mismatches=0`); T6: zero kind-color classes in the whole DOM (`.k-*`/`.ti-badge`/`.li-kind.*` = 0), kind expressed by 35 neutral glyph icons. Branch rows carry the amber needs-dot + open-count badge (visible in `drill-1280.jpg`). |
| 4. keyboard expand/collapse | T7: focusable `<button class="twisty" aria-expanded>` flips `true → false` on keyboard Enter. |
| done/archived collapsed + "show done" | T8: in the max-done project (global, 12 all-done branches) `expandedByDefault=0`; the `show done` toggle reveals `8→22` items and reverts. |

Wire checks: `web/app.js` `renderDrill`/`renderProjectTree`/`branchGroup`/`treeItemRow` →
`web/app.css` `.ck-*`/`.drill-*`/`.needs-dot`/`.ws-open-badge`/`@media (max-width:560px)` full-swap.

## Mechanical / runtime evidence (commands + outputs)

```
node state/selftest.js                      → 21 passed, 0 failed   (no state/ regression — state/ untouched)
node web/responsive.selftest.js             → 28 passed, 0 failed
node state/reconciler.selftest.js           → 33 passed, 0 failed
node scripts/work-in-motion-sweep.selftest.js → 37 passed, 0 failed
WS_URL=http://127.0.0.1:7799/ SHOT_DIR=<evidence-dir> node scripts/regression.e2e.js
  → === Workstreams GUI regression 17/17 PASS ===  (T0 pageErrors=0; full transcript in commit message f830be4)
node --check web/app.js                     → clean
grep window.prompt( web/app.js              → 8 call sites, all pre-existing (Task-8 context-card surface) + 1 comment; ZERO added (C5)
grep '\.k-action|\.k-decision|\.k-question|li-kind\.action|kind-action|ti-badge' web/app.css → 2 hits, both retirement comments (C6 sweep clean)
```

Notes on superseded e2e assertions: old bugs #1/#9 (global repo-tree tiers) and #4 (COLORED kind
badges) encoded the retired design — #1/#9 are superseded by T1–T4 (cockpit + drill tiers), #4 is
INVERTED into T6 (kind colors must be absent) per binding correction C6. The still-valid locks
(modal overlay + selection sync, Esc dismissal, subagent-orphan exclusion, docs drawer, /api/health)
carried over as T11–T15.

Known residuals (in-scope tasks for OTHER builders, not gaps in 3/4/5): the 8 `window.prompt`
call sites in the detail modal are Task 8's surface (C5 retirement there); overlay-stack
consolidation is Task 10 (I5) — no new overlay/Esc handler was added by this work.

---

## Comprehension Articulation

### Task 3 — Spec meaning
The cockpit is the global glance: one fixed-height row per project showing lifecycle COUNTS
(now / next / waiting / done), never items — O(projects) density that survives the real lopsided
data (one project with 60 items, another with 2). The waiting count is the accented bottleneck
signal; clicking a row is the entry point to the bounded per-project drill. Counts must be the
same numbers the reducer-derived state produces, not a parallel computation that can drift.

### Task 3 — Edge cases covered
- Lopsided volume: pills are fixed-size numbers on a shared grid (`web/app.css:998` `.ck-cols, .ck-row`
  shared `grid-template-columns`), proven constant-height at `web/app.js:1012` `cockpitRow` (e2e T3, 36px for all rows).
- Bucket totality/disjointness (C3): `statusCounts` (`web/app.js:259`) routes shipped→done,
  isWaitingOnYou→waiting, committed→next, else→now — every item lands in exactly one bucket; the
  unreachable `proposed`/`closed` states were dropped from `STATE_ICON`/`COMPLETE_STATES`.
- Roots that aren't proper projects: `cockpitRows` (`web/app.js:894`) includes any root owning visible
  items (the `global` cross-cutting container gets a row, displayed as "Cross-project") and excludes
  the item-less account-name nodes; item-less real projects still get a row (empty-state, not vanish).
- Zero counts render as muted pills (class `zero`) so columns stay aligned; waiting accent only when >0
  (`web/app.js:1021-1026`).
- Archived roots: excluded the same way the right-pane filters exclude them (both read `allWorkItems`),
  so cockpit and filters can never disagree; an archived root shown under "show archived" is suffixed `· archived`.

### Task 3 — Edge cases NOT covered
- A project whose items live on nodes whose ROOT is archived while the item-node itself is not (and
  vice versa) follows `allWorkItems`'s per-item-node archived check — coherent with the filters, but a
  root-level "archived" suffix may not appear for such hybrid cases (none exist in live data).
- `reposOf` still uses the hardcoded default repo map for unknown projects (→ "Other") — repo-map
  override via `S.repoMap`/node `repo` field is honored but no UI exists to edit it (pre-existing).
- Cockpit ordering (waiting-desc within repo) is fixed; no user-configurable sort (not in plan scope).

### Task 3 — Assumptions
- "Counts match the reduced state" means: derived from the same `allWorkItems()` flattening the
  right-pane filters use (sessions excluded, archived item-nodes excluded) — the e2e T2 oracle
  re-derives this independently from `/api/state`.
- The plan's now/next/waiting/done columns map to in-flight / committed / isWaitingOnYou / shipped;
  blocked items sit in WAITING per the plan spine ("blocked (incl. blocked-on-operator = waiting on
  you)"). Live data has 0 blocked items, so this choice is currently count-invisible.

### Task 4 — Spec meaning
The waiting-on-you list is the ONLY globally-rendered item list, bounded by construction to what
actually needs the operator: unanswered Misha-asks (decision/question/action_item_for_user) plus
blocked work. Each row must pass the cold-read bar at summary level — background + recommendation
inline — and an item whose `details` cannot support that summary must be visibly flagged
"context incomplete" rather than painted as an actionable bare choice (the full enrichment gate UI
is Task 8; this task's obligation is to never lie about readiness).

### Task 4 — Edge cases covered
- Empty/absent `details`: `waitingSummary` (`web/app.js:498`) returns null → the row renders the
  neutral dashed `ctx-incomplete-badge` (`web/app.js:519` `waitingRow`, style `web/app.css:1098`) —
  exactly the live-data case (20/20 waiting items flagged; e2e T10 `bare=0`).
- Title-echo descriptions: a `details.description` that just repeats the item text (or ≤20 chars) is
  NOT treated as context (`web/app.js:503-507`) — prevents fake-complete rows.
- Recommendation shape duality: legacy string AND fence-schema `{option_key, reasoning}` both render
  (`web/app.js:510-514`); proven live with the fence shape (`waiting-context-complete-1280.jpg`).
- Blocked items: badge shows `blocked` (+ `on <item>` when a `blocked_on` dependency edge exists)
  instead of "waiting on you", so the operator sees WHY it's in the list (`web/app.js:543-544`).
- Responded items: `isAwaitingMe` excludes items with an inline response (back in the agent's court),
  so the list never re-asks what the operator already answered (pre-existing predicate, reused).
- Boundedness: count cross-checked against the oracle (T10 `waitRows=20 (oracle=20)`); grouped by
  project for scanability.

### Task 4 — Edge cases NOT covered
- The summary check is presence-based (background/about/the_ask/question/instructions or a
  recommendation), NOT the full per-kind required-field validation — `validateItemDetails`/
  `assembleItemDetails` consumption and action-suppression-on-incomplete (I2) are Task 8's scope.
  A decision with a background but option-less/meaningless options would summary-render here and
  must be caught by Task 8's gate when opened.
- `wait-bg` clamps to 2 lines (CSS line-clamp); very long backgrounds are truncated with no inline
  "more" expander — progressive disclosure beyond the row lives in the detail card (Task 8).
- Backlog entries are out of this list by design (they have their own surface, Task 7).

### Task 4 — Assumptions
- "Blocked-on-operator" has no machine-readable flag in the schema, so ALL blocked items are included
  in the waiting list (the safe direction: stalled work is never hidden from the operator); the
  `blocked_on` edge is surfaced in the badge so pipeline-blocked items are distinguishable. 0 blocked
  items exist in live data, so this is currently invisible either way.
- Keeping the chip's `data-filter="awaiting-me"` id (relabeled "Waiting on you") preserves the
  structural selftests and stored operator preferences; the SEMANTIC change (now includes blocked) is
  intended per the plan's Surface-2 definition.

### Task 5 — Spec meaning
Drilling into a project shows its work as a bounded, readable tree: branch groups (real child nodes
+ theme-derived workstreams) with guide-line nesting; color carries STATUS (gray structure, amber
exclusively for needs-you/blocked, muted green check for done) while ICON carries KIND; branch rows
aggregate (open-count badge + amber dot if anything inside needs the operator); disclosure twists
are real focusable buttons with `aria-expanded`; done branches start collapsed behind a "show done"
toggle; and per C4 the drill can never dead-end — a persistent breadcrumb returns to the cockpit,
with a master-detail rail at wide widths and a full swap at phone width.

### Task 5 — Edge cases covered
- C6 class sweep, not just new code: deleted `.li-kind.*` color variants, `.li.kind-*` borders/tints
  (+ `.hl` variants + `.li.kind-* .li-details` selectors), `.k-*` chips, `.ti-badge.k-*`, blue
  `.ws-state.st-active`, purple/blue `.b-await`/`.b-flight` badges, purple repo-head tint; re-keyed
  `.st-committed`/`.st-in-flight` to grays (`web/app.css:875-885`). Proven in DOM: e2e T6
  `kindColorClasses=0`; T5 amber-set === oracle needs-set (mismatches=0 in both directions).
- Keyboard a11y: twisty is a `<button>` with `aria-expanded` + `aria-label` (`web/app.js:1198`
  `branchGroup`); e2e T7 flips it via keyboard Enter; cockpit repo headers are buttons too.
- Done-branch defaults: all-done branches collapse by default (`branchExpanded` default `!allDone`,
  `web/app.js:1183`); explicitly expanding a done branch reveals its items even while "show done" is
  off (`allDone || visibleInTree(r)` filter) — avoids the expand-to-nothing trap; an active branch
  whose open items are visible but done items hidden shows a "N done hidden" note instead of silence.
- Branch-state persistence is keyed per project (`drillProject + '::' + key`), so collapsing a theme
  in one project does not collapse the same-named theme elsewhere.
- Items on descendant nodes: `renderProjectTree` (`web/app.js:1108`) buckets refs by containing node —
  real branch nodes render under their own titles (via `renderWorkstream`), direct items go through
  the theme-derived workstreams; nothing in `refs` can be dropped (covered exactly once).
- C4 return path: `← All projects` breadcrumb (`web/app.js:1064`), rail at wide width
  (`web/app.css:1034`), full swap ≤560px (`web/app.css:1079`); e2e T9 + T16 (390px: rail hidden,
  breadcrumb present); drill persists across reload via `workstreams.drillProject` (`web/app.js:59`).
- Modal/selection locks preserved: drill rows keep `tree-item` + `data-node`/`data-item`, so
  `openDetailModal`/`syncTreeSelection` work unchanged (e2e T11/T12).

### Task 5 — Edge cases NOT covered
- Sub-task tier nesting (items on grandchild nodes render as flat branch groups keyed by their own
  node, not indented under their parent branch) — today's data has no such nodes; the old renderer's
  `ws-subhead` handling was equally flat in practice.
- The drill rail at wide width lists projects with waiting badges only (no full 4-pill matrix) — the
  full matrix is one breadcrumb-click away; intentional density choice, not validated with the operator.
- The `show done` toggle is backed by the global `showCompleted` checkbox (one source of truth), so
  toggling it in one project affects done-visibility everywhere — acceptable single-source behavior,
  noted in case the operator expects per-project memory.
- Amber `.chip-warn` on two right-pane filter COUNT chips (shipped-not-deployed / stale-sessions)
  remains — those are filter-bar UI, not item/branch rows; the C6 prove-it ("amber on any
  non-needs-you ROW = zero") holds; a stricter whole-app sweep belongs to Task 10 polish.

### Task 5 — Assumptions
- The derived theme buckets (`WS_THEMES`/`workstreamOf`) remain the approved best-guess workstream
  tier until real workstream nodes exist (operator-approved 2026-06-03; unchanged by this work).
- `visibleInTree` honoring `showArchived` OR `showCompleted` for done items is the intended
  "show done" semantic (matches prior behavior; the drill toggle drives `showCompleted`).
- The 560px rail-hide breakpoint satisfies C4's "≤390px full swap" (390 < 560; between 391–560px the
  full swap also applies because the rail would be unusably cramped there — judgment call).
