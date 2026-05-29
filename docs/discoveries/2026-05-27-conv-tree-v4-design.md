---
title: Conv-Tree v4 — the redesign Misha asked for already exists (unmerged); adopt it
date: 2026-05-27
type: architectural-learning
status: pending
auto_applied: false
originating_context: Misha's screenshot+feedback on PR #24 (flat-list, sidebar dump). Build a v4 that (1) shows real branching, (2) uses a centered modal, (3) shows curated response-ready details.
decision_needed: Adopt the existing unmerged accordion redesign onto master (recommended), and decide the fork-reconciliation path for landing it. Plus 4 UX calls listed below.
predicted_downstream:
  - neural-lace/conversation-tree-ui/web/{app.js,app.css,index.html,responsive.selftest.js}
  - neural-lace/conversation-tree-ui/state/{reducer.js,schema.js}
  - neural-lace/conversation-tree-ui/server/server.js
  - adapters/claude-code/hooks/conversation-tree-emit.sh  (write-side: Dispatch must emit item `details`)
---

## TL;DR

The conversation-tree redesign Misha is asking for — **real branching tree, centered
modal item-detail, curated per-kind details** — was **already built** and sits on the
unmerged branch `origin/feat/conv-tree-accordion-panels-2026-05-27` (the "v2/v3" work,
PRs #32–#39 on the personal remote; mirrored to PT/origin as that branch). It was
**never merged to master**. Master still carries PR #24 (the flat-list "sessions hidden"
render Misha complained about). This is a casualty of the Neural-Lace fork divergence:
the redesign landed on one fork line, #24 landed on the other, and the two never met.

**Recommendation: adopt the accordion redesign as the new conv-tree UI rather than build
a v4 from scratch.** Rebuilding what already exists would violate "drive to completion,
don't redo." I have staged the adoption in a worktree (`conv-tree-v4-accordion-adoption`,
based on origin/master) by overlaying the 7 redesigned conv-tree-ui files, and verified
it loads cleanly against the live `tree-state.json`.

## What was discovered

### The data model already supports branching (req #1)

`tree-state.json` is an event-sourced log. `snapshot.nodes` is a **tree** via `parent_id`:
`today-root → proj-X → sess-Y (a session/conversation branch) → …`. Items
(`{item_id, kind, text, checked, deferred, details?}`) live inside their owning node.
Event types include `branch-opened`, `decision-raised`, `action-added`,
`question-raised`, `re-parented`, `concluded`, `archived`.

PR #24 did **not** lack the branching data — it **deliberately hid it**. Master's
`app.js:920`: *"session/sub nodes (kids) contribute their items but are not drawn as
rows."* That single design choice is exactly Misha's complaint #1 ("no longer shaped
like a tree — just a list under each project").

The accordion branch renders the real hierarchy: `forest()` builds roots + a `kids` map
by `parent_id`; `renderTreeNode()` recurses, nesting children in `.tkids` at `depth+1`,
with disclosure twist-glyphs, depth styling, drag-drop re-parenting (emits `re-parented`),
and a **"promote to branch"** button (`.btn-up`, posts `{type:'promoted', node_id,
item_id, new_node_id}`) that turns an item into its own child branch. This is the
`promote to branch` affordance Misha saw — it exists on the redesign, not on master.

### The detail view is a centered modal on the redesign (req #2)

- Master #24: item detail expands **inline in the list** (`renderItemDetails` appended to
  the `<li>` on expand, `app.js:1097/1107`) — i.e. the right-side/inline pane Misha
  dislikes.
- Accordion: a **centered modal** — `#ctxPanel.modal-card.ctx-modal` over a
  `#ctxScrim.modal-scrim` backdrop. Code comment: *"ctxPanel is a centred MODAL (was a
  docked side pane). It NEVER shifts the persistent #layout."* Dismissal: click-outside
  (scrim click → `closeCtx`), `Esc`, and the ✕ button. Exactly what Misha asked for.
  (The accordion side-panel hosts the *lists* — Waiting/Decisions/Questions — not the
  per-item detail.)

### Curated details: render exists in BOTH; the DATA is empty (req #3)

This is the important honest nuance. **Both** master and the accordion branch have a
`renderItemDetails()` that lays out structured fields — `instructions`, `recommendation`,
`blocking_input`, `description`. The accordion version is richer: it **adds** an
options block with per-option **+ pros / − cons**, branch-link jump parsing
(`(see branch: Title)` → clickable), a graceful "No detailed instructions recorded"
fallback, an **"incomplete metadata"** badge, and kind-specific action buttons
(decisions/questions get **Respond** + send/copy-for-Dispatch; actions get **mark done**
+ **defer**; contested get accept/keep). There is **no raw session-text dump** and no
context-textarea in the item detail (the textarea Misha disliked is the *backlog-capture*
form, a different surface).

BUT — verified against the live state file — **0 of 62 items currently have `details`
populated.** So even after adopting the redesign, items render the graceful
"incomplete metadata" fallback (text + a generic "see linked Dispatch doc" line) until
`details` get populated. Reason (per discovery `2026-05-18-conv-tree-backfill-source-docs-not-on-machine.md`):
the backfill reads the *Dispatch source docs* to extract options/recommendation, those
docs aren't on this machine, and the backfill refuses to fabricate (honesty contract).

**So req #3 is a WRITE-side gap, not a render gap.** The emit hook
(`conversation-tree-emit.sh`) already supports the curated payload —
`--emit-item {kind,node_id,item_id,text,details:{instructions,options,recommendation,
links}}` and `--emit-details` (self-tests ST24/ST26). The fix going forward is that
**Dispatch must emit `details` when it raises an item** (and/or a one-time backfill once
the source docs are reachable). The render is ready for it today.

## Divergence analysis (why this isn't a clean merge)

Merge-base of master and the accordion branch is `fff2de3`. From there:
- **master** added: #3 (scripts), #20 (project-root topology + emit path-fallback fix),
  #24 (flat-list "sessions hidden" render).
- **accordion** added: #27 (toast fix), #32 (v2 modal+tabs), v3 (accordion panels) —
  the UI redesign — plus its own additive `state/reducer.js`(+16), `state/schema.js`(+9),
  `server/server.js`(+27).

Master never touched the accordion's `reducer.js/schema.js/server.js` (verified:
empty diff `fff2de3..master` on those paths), so the redesign's 7 files **overlay master
cleanly with zero conflict.** The only thing master has that the redesign lacks on the
data side is #20's topology/migration work — but the **live state already carries the
project-root topology** (the #20 migration already ran on it), and the redesign's tree
render reads `parent_id` generically, so it renders the current topology correctly.

## What I staged + verified

Worktree: `.claude/worktrees/conv-tree-v4`, branch `conv-tree-v4-accordion-adoption`,
based on `origin/master`. Overlaid the 7 redesigned conv-tree-ui files from the accordion
branch. Verified:

- `node --check` on app.js / reducer.js / server.js — **syntax OK**.
- State self-test (`state/selftest.js`) — **17/17 PASS** (accordion reducer+schema vs
  ADR-032 invariants, against live-shape data).
- Responsive/layout self-test (`web/responsive.selftest.js`) — **55/55 PASS** (the v3
  modal markers, accordion collapse, branch render contracts).
- Server starts and serves the redesigned DOM (`ctxPanel`, `ctxScrim`, `modal-card`,
  `modal-scrim`, `paneStack`, `treeCanvas`) and the live snapshot over HTTP.
- `readState()` against the live `tree-state.json` via the accordion reducer:
  `valid: true`, 50 nodes, 62 items, **0 with details** (see req #3 above).

## Honest gaps (could NOT verify / needs Misha)

1. **No automated browser screenshot.** The Preview MCP screenshot timed out twice — the
   GUI holds an open SSE/live-update connection that keeps the headless renderer from
   signaling "load complete." That's a screenshot-tool limitation, **not a render
   defect** (the server serves the page; all self-tests pass). To view it live, launch
   the worktree GUI yourself (command below).
2. **Curated details are empty for all 62 live items** (write-side gap, above). The
   render is ready; Dispatch needs to emit `details`, or backfill once source docs exist.
3. **Items are not nested inline under their branch in the tree pane** — the accordion
   shows a branch's open-item *count* as a badge on the node, and the items themselves
   live in the right-hand accordion list (clicking jumps/focuses). This satisfies "the
   tree shows branching," but if Misha specifically wants the actual action/decision/
   question rows nested *under* their branch node *inside the tree canvas*, that's an
   additional render change (design question #1 below).

## Design questions / UX calls for Misha

1. **Items inline in the tree vs. badge+list?** The redesign shows branches in the tree
   canvas with an "N open" badge per node; the items live in the right accordion list.
   Do you want the actual items nested *inside* the tree under their branch, or is
   tree=structure + list=items the right split?
2. **Fork reconciliation path.** To get this onto what you run (master), we adopt the
   redesign's 7 files onto master. Do you want: (A) land it via a normal PR to
   PT/origin master once the fork target is settled, or (B) also mirror to personal?
   (Blocked on the NL-fork decision — not pushing anything per your instruction.)
3. **Backfilling details for the existing 62 items.** Should I (a) leave them showing
   "incomplete metadata" until Dispatch re-emits them naturally, or (b) wire a backfill
   that reads the Dispatch source docs (requires those docs on the machine), or (c) have
   Dispatch start emitting `details` only for *new* items going forward?
4. **#20's topology/emit-path-fallback fix.** The redesign branch predates #20. The live
   state already has the topology, so render is fine — but should I also cherry-pick
   #20's *emit-path-fallback* hook fix onto the adoption branch so future emits land
   correctly? (Low-risk, recommended.)

## Decision

Pending Misha. Recommended: adopt the accordion redesign (req #1 + #2 satisfied
immediately; req #3 render-ready, data-empty), answer the 4 UX calls, then land via a
normal PR once the fork target is decided. NOT building a fresh v4 — the redesign exists.

## How to view it live

    cd ".claude/worktrees/conv-tree-v4/neural-lace/conversation-tree-ui"
    cp "<main-checkout>/neural-lace/conversation-tree-ui/state/tree-state.json" state/   # use real data
    CTREE_PORT=7790 node server/server.js     # 7733 is your live GUI — use a different port
    # open http://localhost:7790
