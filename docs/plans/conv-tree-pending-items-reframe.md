# Plan: Conversation Tree reframe — projects → open pending items, sessions invisible
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal conversation-tree GUI; the "user" is Misha viewing his own tracker. Acceptance = GUI renders projects→pending-items with sessions hidden, verified in a browser against the live :7733 server; state-lib + emit self-tests pass.
Backlog items absorbed: none

## Goal
Misha's 2026-05-27 reframe: the Conversation Tree is NOT a session-tracker. It tracks (1) conversation flow = projects/workstreams as top-level nodes, and (2) open actions/decisions/questions still waiting on Misha = the LEAVES under each project. Sessions (`sess-*`/`sub-*`) are agent bookkeeping and must be INVISIBLE in the rendered tree (kept in the event log for provenance only). Items disappear (move to closed-state) when Misha acts on them — the tree shows active backlog, not history. Builds directly on the shipped project-root topology (PR #20).

## Scope
- IN:
  - Tree pane (`web/app.js`): render project nodes as roots; under each project, render its OPEN pending items (`isWaiting`) collected from the project's whole subtree (project + descendant `sess-*`/`sub-*` nodes) as leaves; do NOT render `sess-*`/`sub-*` node rows.
  - `conversation-tree-extract-pending.sh`: anchor extracted items to the project root (via `_project_root`) instead of a self-created `sess-<hash>` node; record originating session as provenance on the item.
  - Verify the existing close/resolve interactions (`action-done`/`answered`/`contest-resolved`/`item-backlogged` + per-item GUI buttons) work in the new project-grouped tree.
- OUT:
  - NO new close-item event type — already exists (`action-done`/`answered`/`contest-resolved`/`item-backlogged`). Misha's "Stage B" is already built; this plan verifies it, not rebuilds it.
  - NO change to the frozen ADR-032 reducer/snapshot contract. Session nodes REMAIN in `snapshot.nodes` (for the conv-tree-state-gate's branch-presence check + provenance); they are hidden at RENDER time, not removed from state. (Honors "sessions can remain in the event log for provenance.")
  - NO removal of the "Waiting on you" actions pane (the flat cross-project sorted list stays; the tree adds the project-grouped pending view).
  - NO item-move migration: existing items stay on their session nodes in state; the tree's descendant-collection lifts them under the project at render time.

## Tasks
- [ ] 1. `web/app.js`: project-grouped pending-item tree render; hide `sess-*`/`sub-*` rows. Verification: full
- [ ] 2. `conversation-tree-extract-pending.sh`: anchor items to project root + session provenance; update self-tests. Verification: mechanical
- [ ] 3. Verify close/resolve interactions + A1–A42 items appear under their project (cross-cutting → cross-repo node or multi-attach). Verification: full

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.js` — tree-render change (projects → collected open pending items; hide session/sub rows).
- `adapters/claude-code/hooks/conversation-tree-extract-pending.sh` — anchor to project root + provenance; self-test updates.
- `docs/plans/conv-tree-pending-items-reframe.md` — this plan.

## In-flight scope updates
- 2026-05-27: `neural-lace/conversation-tree-ui/web/app.css` — minimal styles for the new pending-item leaf classes (`.tpending`, `.tpending-text`, `.tpending-prov`, `.tpending-empty`).
- 2026-05-27: **Task 2 (extract-pending → project anchor) DROPPED as unnecessary.** Under the approved render-collection design, the hook's `sess-<hash>` node is parented under its project, so `collectWaitingItems` already lifts its items to the project at render time WITH "from: <session>" provenance. Changing the hook to flatten items directly onto the project would LOSE per-session provenance and churn the hook's self-tests for no visible gain. Verified against live state: 62 existing items group correctly under 4 projects with zero hook change. (Surfaced to Misha — he asked to attach-to-project; the render-collection design he approved makes this a no-op that actually preserves more provenance.)

## Assumptions
- The GUI is dual-pane (verified): Tree pane (`treeCanvas`, node-structure rows, no inline items) + "Waiting on you" pane (`actionsBody`, flat `isWaiting` items with full controls) + Backlog pane.
- Close/resolve already exists (verified at `web/app.js`): `action-done` (line ~1050), `answered`/`contest-resolved` (Respond flow ~1093), `item-backlogged` (~1202), `item-unchecked` undo; `isWaiting(it)` = `(!checked || deferred || contested) && !backlogged`.
- Session nodes parent under their project after PR #20, so a project's descendant-walk reaches all its sessions' items.
- Keeping session nodes in `snapshot.nodes` (hidden at render) avoids breaking `conversation-tree-state-gate.sh` (which asserts a live `snapshot.nodes` element names a spawned branch).

## Edge Cases
- A project with zero open items: render the project header with an empty/"nothing waiting" affordance (don't dead-end).
- An item on the project node directly (from the reworked extract-pending) vs on a descendant session: both collected; dedupe by item_id.
- Cross-cutting A-items not tied to one repo: a synthetic `proj-cross-repo` project node, OR attach to the most-relevant project (design call — default: cross-repo node).
- Resolved/closed items (`!isWaiting`): excluded from the tree (active-backlog-only); still visible via "show concluded"/history toggles if present.
- Provenance display: item leaf shows which session surfaced it (small, de-emphasized) without rendering the session as a node.

## Testing Strategy
- Tree render: load live :7733 in a browser; confirm roots = projects, leaves = open pending items, NO `sess-*`/`sub-*` rows; resolve an item and confirm it disappears from the tree. (Browser verification REQUIRED — frontend change.)
- `responsive.selftest.js` (GUI self-test) passes.
- extract-pending: `--self-test` updated + passes; a crafted transcript's items anchor to the project node (not a `sess-*` node), verified against a temp sink.
- `/api/state` data check: project nodes carry/collect the pending items; session nodes present-but-not-rendered.

## Walking Skeleton
Thinnest end-to-end slice: in `renderTree()`, for ONE project root, collect its subtree's `isWaiting` items and render them as leaves while skipping session rows — confirm in the browser that that project shows its pending items with no session nodes. Proves the render model before generalizing to all projects + wiring resolve-from-tree.

## Decisions Log
### Decision: Hide sessions at render, not remove from state (frozen-contract + gate safety)
- **Tier:** 2
- **Chosen:** Session nodes stay in `snapshot.nodes`; the GUI tree does not render them and lifts their open items to the project. Provenance kept.
- **Alternatives:** (a) Reducer filters session nodes out of `snapshot.nodes` — rejected: changes the frozen ADR-032 snapshot contract AND risks `conversation-tree-state-gate.sh` (which reads `snapshot.nodes` for branch-presence). (b) Item-move migration re-parenting items off sessions onto projects — rejected: needs a new move-item event + a fragile migration; render-collection achieves the same visible outcome with zero state churn.
- **Reasoning:** Equivalent visible outcome (projects→items, sessions invisible) at far lower risk; honors Misha's "sessions can remain in the event log for provenance."
- **Surfaced to user:** flagged in the session response as the one interface-impact design choice.

## Definition of Done
- [ ] Tree pane renders projects → open pending items; no session/sub rows (browser-verified).
- [ ] Resolving an item removes it from the tree (close interactions work).
- [ ] extract-pending anchors new items to the project; self-tests pass.
- [ ] A1–A42 items visible under their project.
- [ ] Merged to master + auto-update working.
