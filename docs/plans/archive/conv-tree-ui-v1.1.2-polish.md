# Plan: Conversation Tree UI v1.1.2 — live-feedback follow-up (drop item 20, add item 25)

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer is the live user verifying via the running GUI; the extended responsive self-test + the six conv-tree regression suites are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal
Immediately after v1.1.1 (items 14–23) merged (master `759923d`), the maintainer surfaced two live-use corrections: (a) the "promote → expand to branch" rename (item 20) is unwanted — "promote to branch is fine now that I understand what it is" — revert the label; (b) NEW item 25 — top-level project nodes (immediate children of root) must read as document-style H1/H2 headers so the tree hierarchy is instantly scannable. Ship as a small focused follow-up PR on the same branch.

## Scope
- IN: `neural-lace/conversation-tree-ui/web/app.js` (revert the item-20 label to "promote to branch"/"promoted to branch"; add depth tracking + a `.tnode-root` class for top-level nodes), `web/app.css` (`.tnode-row.tnode-root` header styling: larger/bolder font, more padding, subtle tint, top separator, larger twist), `web/responsive.selftest.js` (invert R40 to assert "promote to branch" retained + `promoted` event preserved; add R44 for the top-level header invariants), this plan.
- OUT: ADR-032 schema change (none — `promoted` event type unchanged; no new event). Item 22's `btn-up` purple class on the promote button STAYS (only the label text reverts; the maintainer asked for no label change, not a colour revert). Any change to items 14–19, 21–24 (all remain as shipped in v1.1.1).

## Tasks

- [x] 20R. Revert item 20: restore `'promote to branch'` button label + `'promoted to branch'` toast in app.js; keep the `btn-up` semantic class + the `type:'promoted'` event unchanged — Verification: full
  **Prove it works:** 1. Open ctx panel on a node with open items → the per-item button reads "promote to branch" (not "expand"). 2. `grep -n "expand to branch\|expanded to branch" web/app.js` → 0 hits. 3. Event still `type:'promoted'`; button still purple `btn-up`.
  **Wire checks:** `web/app.js` (`'expand to branch'`→`'promote to branch'`, `'expanded to branch'`→`'promoted to branch'`; `btn-up` + `type:'promoted'` untouched) → `web/responsive.selftest.js` (R40 inverted)
  **Integration points:** responsive.selftest R40 asserts the "promote to branch" label is present, no "expand to branch" remains, `promoted` event preserved.
- [x] 25. Top-level project nodes render as H1/H2-style headers: larger font (~1.18×), bolder weight, larger padding, subtle ~5% white tint + thin top separator, larger/distinct disclosure twist — applied ONLY to root-level nodes (immediate children of the forest root), not nested ones — Verification: full
  **Prove it works:** 1. Every forest-root branch the maintainer sees (the immediate children of the tree root) is visibly larger/bolder with more breathing room + a separator above each. 2. Nested sub-nodes are unchanged (normal size). 3. Hierarchy is instantly readable: top-level = header, indented = detail.
  **Wire checks:** `web/app.js` (`renderTreeNode` gains a `depth` arg — 0 for forest roots, +1 per recursion; depth 0 → add `tnode-root` class + larger twist glyph) → `web/app.css` (`.tnode-row.tnode-root` font-size ~1.18rem-equiv, font-weight 700, padding bump, `background` 5% white tint, `border-top` separator, `.tnode-root .twist` larger)
  **Integration points:** responsive.selftest R44 asserts `.tnode-root` CSS rule (font-weight + size + tint/separator) + the `renderTreeNode` depth-0 wiring token.
- [x] 26. Invert R40 + add R44 in `web/responsive.selftest.js`; full six-suite regression sweep green — Verification: full
  **Prove it works:** responsive.selftest passes with R40 inverted + new R44; state 15 / responsive (44) / backfill 15 / conv-tree state-gate 18 / stop-gate 8 / emit 17 all green.
  **Wire checks:** `web/responsive.selftest.js` → the six suites
  **Integration points:** re-run all suites; counts in the completion report.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.js` — revert item-20 label; add `depth` param to `renderTreeNode` + `tnode-root` class at depth 0 + larger root twist glyph.
- `neural-lace/conversation-tree-ui/web/app.css` — `.tnode-row.tnode-root` header styling + `.tnode-root .twist` sizing.
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — invert R40, add R44.
- `docs/plans/conv-tree-ui-v1.1.2-polish.md` — this plan + Decisions Log.

## In-flight scope updates
- 2026-05-18: neural-lace/conversation-tree-ui/state/backfill-details.js — B15 selftest path-fragility fix: it referenced `docs/plans/conv-tree-ui-v1.1.1-polish.md`, which the v1.1.1 closure renamed+archived, so the case regressed (14/1). Repointed B15 at the permanent `docs/DECISIONS.md` (never archived). In-scope under Task 26 "all six suites green"; light case, not a spec thaw.

## Testing Strategy
Each change locked by a `web/responsive.selftest.js` source-invariant assertion (the established pattern). Full six-suite regression sweep is Task 26's gate. Live browser verification is the post-merge `:7733` restart step.

## Walking Skeleton
Add a failing R44 assertion for the `.tnode-root` rule; implement the CSS rule + the depth-0 class in `renderTreeNode`; confirm the GUI still renders the tree. Item 20R is a pure label revert + R40 inversion.

## Decisions Log
### Decision: revert label only, keep btn-up purple + promoted event
- **Tier:** 1 (reversible)
- **Status:** proceeded with recommendation
- **Chosen:** revert ONLY the item-20 label text. The maintainer said "no label changes needed" (i.e., keep the original "promote to branch"); they did NOT ask to revert item 22's semantic colouring. The `btn-up` purple class (scope-up semantics) and the frozen `type:'promoted'` event are unchanged.
- **Alternatives:** also revert btn-up→ghost — REJECTED: out of the maintainer's stated ask; item 22 (semantic palette) shipped and stands.
- **Reasoning:** minimal change matching the exact correction; no scope creep.
- **To reverse:** N/A.

### Decision: "top-level" = forest-root depth 0, via a renderTreeNode depth param
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** thread a `depth` argument through `renderTreeNode` (0 for the roots `renderTree` iterates, +1 per recursion). Depth 0 → `.tnode-root`. This is exact and robust regardless of `parent_id` shape.
- **Alternatives:** detect "no parent / parent is synthetic root" inline — REJECTED: the forest already computes roots; a depth param is simpler and unambiguous than re-deriving root-ness inside the recursive renderer.
- **Reasoning:** the renderer already recurses; a depth counter is one added arg and zero ambiguity.
- **To reverse:** drop the class + CSS rule.

## Assumptions
- No ADR-032 change (label/CSS/JS-only; `promoted` event + schema untouched; `SCHEMA_VERSION` stays 1).
- "Top-level project nodes" = the forest roots `renderTree` already iterates (`orderedRoots`), i.e. depth 0 — matches the maintainer's listed examples.
- localStorage UI-pref substrate unchanged; no new pref.

## Edge Cases
- A root node that is also `concluded` (renders the concluded stub branch): the `.tnode-root` header styling still applies to its row; the concluded stub/✓ treatment composes (separator + size on the row, concluded colour on the title) without conflict.
- Single-root tree: still gets the header treatment (consistent), separator above the only root is harmless.
- Deeply nested trees: only depth 0 is a header; depth ≥ 1 unchanged (no regression to existing sub-node rendering, animations, drag-drop, badges).
- `.tnode-root` + `.hl` (item 17 selection wash) on the same root row: both apply (header size/weight + selection wash) — separate property sets, no clobber.

## Definition of Done
- [x] Tasks 20R, 25, 26 task-verified PASS (3/3)
- [x] Six regression suites green (state 15, responsive 44, backfill 15, state-gate 18, stop-gate 8, emit 17)
- [x] PR to master merged; main checkout synced; `:7733` restarted
- [x] Status → COMPLETED (auto-archived); completion report appended

## Completion Report

### 1. Implementation Summary
- **20R** (drop item 20): `web/app.js` per-item button reverted to `el('button','btn-up','promote to branch')`, toast `'promoted to branch'`; `btn-up` purple (item 22) + `type:'promoted'` event unchanged; zero "expand to branch" in `web/`. `b418f5c`.
- **25** (top-level headers): `renderTreeNode` gained a `depth` arg (0 for forest roots via `renderTree`'s `orderedRoots`, +1 per recursion); depth-0 rows get `.tnode-root` + a larger/distinct twist (▶/▼/◆). `.tnode-row.tnode-root` CSS: 1.18rem, padding bump, 5px left, 5% white tint, top separator (first-child exempt), title font-weight 800, larger accent twist. Nested rows unchanged. `b418f5c`.
- **26** (selftest + sweep): R40 inverted (asserts "promote to branch" retained, no "expand", `btn-up`+`promoted` kept); new R44 (six `.tnode-root` CSS invariants + three `renderTreeNode` depth wiring tokens). responsive 43→44. `b418f5c`.
- In-flight: B15 path-fragility fix — repointed from the v1.1.1-closure-archived plan path to the permanent `docs/DECISIONS.md`; backfill restored 15/15. `b418f5c`.
No backlog items absorbed.

### 2. Design Decisions & Plan Deviations
Two Decisions-Log entries (label-only revert keeping btn-up/promoted; "top-level" = forest-root depth-0 via a `renderTreeNode` depth param). One in-flight scope update (B15 path fragility — a real test-design defect surfaced by the v1.1.1 closure renaming the file B15 hard-coded; designed out by pointing at a never-archived index).

### 3. Known Issues & Gotchas
- `.tnode-root` is depth-0 only — correct for the maintainer's listed top-level branches. If a future change introduces a synthetic always-present root wrapper, depth-0 would shift; the forest already excludes synthetic roots so this is not a current risk.
- Same cross-repo doc caveat as v1.1.1 (per-machine `config/projects.json` for non-self projects) is unchanged here.

### 4. Manual Steps Required
- Post-merge `:7733` restart (done as the final delivery step) so the maintainer sees the reverted label + the header-styled top-level nodes on refresh.

### 5. Testing Performed & Recommended
state 15/0 · responsive 44/0 (R40 inverted PASS, R44 PASS) · backfill 15/0 (B15 stable) · conv-tree state-gate 18/0 · stop-gate 8/0 · emit 17/OK · `node --check` clean · `SCHEMA_VERSION`=1 unchanged. task-verifier PASS 3/3 with committed evidence log. Recommended: live browser refresh on `:7733`.

### 6. Cost Estimates
Zero incremental cost (label/CSS/JS-only; no dependency, no build step, no service).
