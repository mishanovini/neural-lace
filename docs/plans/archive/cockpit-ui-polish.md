# Plan: Cockpit UI polish — the operator's four usability items

Status: SUPERSEDED
Superseded-by: docs/plans/cockpit-roadmap-redesign.md (2026-07-18 — all four items absorbed
verbatim into its task 8; the badge law moved to its task 6)
Mode: build
rung: 2
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## Goal

The operator's four UI items from the 2026-07-14 live-cockpit review (verbatim list; "there is no
item 5" confirmed). These were task 7 of cockpit-v2 v3; the architecture review's m2 finding split
them out ("unrelated to the data architecture") and the v4 rewrite dropped them without a home —
this plan is that home. Pure web-surface work (`web/*.css/js/html`), file-disjoint from cockpit-v2's
remaining acceptance task.

## User-facing Outcome

The operator can: resize the sidebar panes and scroll within each independently; scan the backlog as
a compact list and expand rows on demand; read WHAT each task is (its description text) in the plan
drill-down without the noise of a repeated per-row plan link; and never see the Artifacts wall again.

## Scope

IN: `neural-lace/workstreams-ui/web/{app.css,asks.js,todo.js,backlog.js,index.html,cockpit.selftest.js}`
and any server payload addition needed to carry task descriptions to the UI (the schema carve-out
ALREADY landed — cockpit-v2 Task 6: `description` in DETAIL_ALLOWED_KEYS + DENYLIST_EXEMPT_KEYS —
this plan wires a producer + renderer onto it).
OUT: any data-architecture change; the peers section (cockpit-v2); Harness Health tab internals.

## Tasks

- [ ] 1. [serial] **Resizable + independently scrollable panes** (operator item 1): drag-resize
  between the ask-tree column and the sidebar, and between sidebar panes; each pane body scrolls
  independently (`overflow-y:auto` + min-heights). MUST NOT regress the shipped flex-clip fix
  (`.sidebar>.pane` flex-shrink guard — the todo-clip acceptance bug) or the <1200px stacked
  layout. CSS-first; a small drag handle in JS if pure CSS resize is insufficient — Verification: full
- [ ] 2. [serial] **Compact, expandable backlog rows** (item 2): rows render one-line collapsed
  (id + title + tier + age), click/keyboard-expandable to full detail; disposition buttons live in
  the expanded state; "N more" behavior preserved; keyboard accessible (real buttons, aria-expanded) —
  Verification: full
- [ ] 3. [serial] **Task descriptions in the drill-down + de-duplicate links** (item 3, render half):
  the ask detail's per-task rows show each task's DESCRIPTION text (source: `plan-parse.js`'s
  per-task description via the server detail payload — the carve-out landed in cockpit-v2 Task 6;
  wire `buildAskDetailPayload` to include it, capped per the schema). DROP the repeated per-task
  plan-path hyperlink — the single "View live plan doc" button covers it; keep per-task evidence
  links (those differ per row) — Verification: full
- [ ] 4. [serial] **Remove the Artifacts section** (item 4): delete the artifacts list from the ask
  detail render (and its payload field if nothing else consumes it — check consumers first; if the
  field stays for API compat, the UI simply stops rendering it) — Verification: full
- [ ] 5. [serial] **Acceptance**: end-user-advocate runtime pass at 1920×1080 and 1024px: resize
  works and persists sanely; backlog scannable + expandable; descriptions readable; no Artifacts;
  no regression of the todo-clip fix; cockpit.selftest.js extended (real-button/aria checks) and
  green — Verification: full

## Files to Modify/Create
`web/app.css`, `web/asks.js`, `web/todo.js`, `web/backlog.js`, `web/index.html`,
`web/cockpit.selftest.js`, `server/server.js` (detail payload description wiring only),
`server/server.selftest.js` (payload scenario).

## In-flight scope updates
(none yet)

## Assumptions
- cockpit-v2 Task 6's schema carve-out is the settled contract for descriptions (by-KEY exemption,
  2000-char cap) — this plan adds the producer/renderer, no schema change.
- Drag-resize state persists per-browser (localStorage) — no server persistence needed.
- The plan drill-down's current per-row link is fully redundant with "View live plan doc"
  (operator's own observation); evidence links are NOT redundant and stay.

## Edge Cases
- Long/multiline descriptions: clamp with expand affordance; quotes/newlines already JSON-safe via
  plan-parse. Missing description (old plans): render nothing, no placeholder noise.
- Resize to extremes: min-width floors both columns; double-click handle resets.
- Backlog keyboard nav: expanded state reachable and closable without a mouse.

## Acceptance Scenarios
(see task 5 — advocate-executed at both breakpoints; artifacts under .claude/state/acceptance/)

## Out-of-scope scenarios
Peers-section styling (cockpit-v2 owns it); Harness Health tab internals; any mobile-specific work.

## Closure Contract
Closes when all 5 tasks verified (rung-2 comprehension applies to Verification: full tasks),
advocate pass green at both breakpoints, cockpit.selftest green, deployed to :7733.

## Testing Strategy
cockpit.selftest.js structural checks (real buttons, aria, no-artifacts, description rendering) +
server.selftest.js payload scenario + the advocate runtime pass as the user-path oracle.

## Walking Skeleton
Task 3's payload wire (one description through to one rendered row) first — proves the
carve-out→producer→renderer chain end-to-end before the visual work.

## Decisions Log
- (2026-07-17) Split from cockpit-v2 per its architecture review (m2: "unrelated to the data
  architecture; only 7(c) depends on it"). Sequenced to build AFTER cockpit-v2's Task 8 acceptance
  runs (this plan changes the UI under test), unless the operator wants it sooner.
