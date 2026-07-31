# Plan: Workstreams UI — "show completed" filter + ACTIVE-plan-badged-shipped fix
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Workstreams GUI filter fix; state self-tests + a new filter/status-precedence unit test are the acceptance artifact (no product user; the GUI's user is the operator and the local self-tests are the maintainer-observable check)
tier: 2
rung: 1
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal
Fix an operator-reported bug in the Workstreams UI (`neural-lace/workstreams-ui/`):
the GUI badges `PLAN: … [ACTIVE]` work-items as **shipped** and shows them even
when the header "show completed" checkbox is OFF. Two interacting defects:

1. **Status mismatch** — a work-item whose own text declares the plan is `[ACTIVE]`
   derives `itemState() === 'shipped'`, because a past PR-merge/deploy signal emitted
   `item-shipped` while the plan file was still ACTIVE (event reason verbatim:
   "Work merged: PR #350 … Plan file still ACTIVE = bookkeeping debt"). The merge
   signal overrode the plan's authoritative ACTIVE status.
2. **Filter leak** — once an item is (falsely) shipped, the single-item branch it
   lives in is `allDone`, and `branchGroup`'s `allDone || visibleInTree(r)` bypass
   (app.js:1685) renders the shipped item in the left Projects tree even with
   "show completed" OFF.

The fix establishes a **status precedence rule at the display layer** (the only
layer where it can land — the event log is append-only and the bad `item-shipped`
events are immutable history): a work-item whose text declares the plan is still
`[ACTIVE]` is NOT shipped, regardless of a stale merge-derived state. Fixing the
state cascades to fix the filter (a non-shipped item is not `isComplete`, so the
branch is not `allDone`, so the `allDone` bypass no longer leaks it).

## User-facing Outcome
With "show completed" OFF, the left Projects tree shows only genuinely in-flight
work and hides shipped/completed/deployed/archived items — including single-item
"all done" branches. A `PLAN: … [ACTIVE]` item is rendered as in-flight, not
badged shipped. Toggling "show completed" ON brings the genuinely-shipped items
back.

## Scope
- IN:
  - `neural-lace/workstreams-ui/web/app.js` — `itemState()` status-precedence
    override (a `[ACTIVE]`/`[DEFERRED-but-still-listed]` plan-status marker in the
    item text wins over a stale `shipped` state); a small unit-test block.
  - `neural-lace/workstreams-ui/web/app.js` — `branchGroup` `allDone` bypass: stop
    leaking complete items through the `allDone` short-circuit when show-completed
    is off (show the "N done hidden" affordance instead).
  - new test `neural-lace/workstreams-ui/state/filter-status.selftest.js` — proves
    the precedence + filter behavior in isolation (app.js's pure predicates lifted
    into a testable form, or a focused replica of the predicates with the exact
    fix).
- OUT:
  - `work-in-motion-sweep.js` (PR #61 territory — deploy-detection); the emit-time
    fix is a separate concern and is held by PR #61. This plan is the DISPLAY-layer
    filter + status-precedence fix, complementary to #61.
  - Re-emitting / rewriting the historical `item-shipped` events (append-only log).
  - The right-pane chip filters (already correct: `awaiting-me`/`in-flight` exclude
    shipped via `isWaitingOnYou`/`isInFlightItem`).

## Tasks

- [x] 1. Add a status-precedence override to `itemState()` in `web/app.js`: when an
      item's text carries a plan-status marker that means "still open" (`[ACTIVE]`),
      do not return `shipped` even if `it.state==='shipped'`/`it.checked`. Derive
      the truthful open state instead (`in-flight`, or `blocked` if contested).
      Verification: mechanical
- [x] 2. Fix `branchGroup` so the `allDone` short-circuit does not bypass the
      show-completed filter: a branch's items still obey `visibleInTree`, and an
      all-complete branch shows the "N done hidden — use show done" affordance when
      show-completed is off (rather than rendering the completed items). Keep the
      "explicit expand reveals done items" intent only when show-completed/archived
      is on. Verification: mechanical
- [x] 3. Add `state/filter-status.selftest.js` proving: (a) a `[ACTIVE]`-text item
      with `state:'shipped'` derives a non-complete state and is INCLUDED when
      show-completed=false; (b) a genuinely-shipped item (no `[ACTIVE]` marker) is
      EXCLUDED when show-completed=false and INCLUDED when true. Run existing
      `state/selftest.js` + `state/reducer.selftest.js` + the new test; all pass.
      Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/web/app.js` — `itemState()` precedence override + `branchGroup` allDone-filter fix.
- `neural-lace/workstreams-ui/state/filter-status.selftest.js` — new unit test for the precedence + filter logic.
- `docs/plans/workstreams-completed-filter-fix-2026-06-17.md` — this plan.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- A `PLAN: … [ACTIVE]` marker in a work-item's text is the authoritative
  reflection of the plan file's `Status: ACTIVE` (written by `work-in-motion-sweep.js`
  `desiredNodesFor`, app.js sees it verbatim). Verified in live state: 21
  `wim-plan-*` items, all 10 "shipped" ones carry `[ACTIVE]`; 0 carry
  `[COMPLETED]`/`[DEFERRED]`. So the rule has no false-positive risk in current data.
- The historical bad `item-shipped` events cannot be un-emitted (append-only log);
  the display layer is the correct and only place to fix the operator-visible bug.
- `isComplete()` keys off `itemState()`, so fixing `itemState()` cascades to
  `branchGroup`'s `allDone`, `visibleInTree`, and `statusCounts` consistently.

## Edge Cases
- An item legitimately shipped whose title still says `[ACTIVE]`: by design the
  sweep updates the title when a plan leaves ACTIVE, so this combination only
  occurs for the bug class. The override treats it as in-flight — the safe default
  (surface the work rather than hide it as done). Confirmed zero genuine collisions
  in live data.
- A `[ACTIVE]` item that is also `blocked`/`contested`: precedence preserves the
  blocked signal (returns `blocked`, not `shipped`).
- Cockpit "done" counts: an over-counted "done" pill that included these false
  shipped items now correctly drops them to "now/in-flight" — this is the intended
  correction, not a regression.
- PR #61 conflict: #61 edits `isShippedNotDeployed` (app.js:395) + the sweep; this
  plan edits `itemState` (app.js:278) + `branchGroup` (app.js:1660). Disjoint lines.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal GUI fix; state self-tests are the artifact)

## Out-of-scope scenarios
n/a

## Testing Strategy
- `node neural-lace/workstreams-ui/state/filter-status.selftest.js` — the new unit
  test (precedence + filter inclusion/exclusion).
- `node neural-lace/workstreams-ui/state/selftest.js` and
  `node neural-lace/workstreams-ui/state/reducer.selftest.js` — existing suites, must stay green.
- Cross-check against live `/api/state`: the count of `[ACTIVE]`+shipped items
  drops to 0 in the UI's derived view (verified via the same predicate in the test
  harness against the snapshot).

## Walking Skeleton
The thinnest slice: `itemState()` gains a single guard that downgrades a stale
`shipped` to the truthful open state when the item text says `[ACTIVE]`. That one
change is end-to-end observable — the badge flips and the filter stops leaking —
because every consumer (`isComplete`, `branchGroup.allDone`, `visibleInTree`,
`statusCounts`, `itemRow` badge, `treeItemRow` ✓) reads through `itemState()`.

## Decisions Log
### Decision: fix at the display/derivation layer, not at emit time
- **Tier:** 1 (isolated, reversible)
- **Status:** proceeded with recommendation
- **Chosen:** Override `itemState()` so a `[ACTIVE]` plan-status marker in the item
  text takes precedence over a stale merge-derived `shipped` state.
- **Alternatives:** (a) re-emit `item-unchecked`/`item-committed` to correct the
  historical events — rejected: the bad events are already concluded-or-open in the
  log and a data migration is out of scope + risky + PR-#61-adjacent; (b) fix the
  audit-emitter that produced "PR merged ⇒ shipped while ACTIVE" — that emitter is
  not in this module's files and overlaps #61's deploy-detection; surface as a
  follow-up.
- **Reasoning:** the operator-visible bug is a DISPLAY bug; the display layer is
  where every reader converges (`itemState`), so one guard fixes both reported
  problems and cannot be undone by future bad emits (the title marker is the
  authoritative anchor). Append-only log stays intact.
- **Checkpoint:** N/A
- **To reverse:** remove the guard clause in `itemState()` and the `branchGroup` filter line.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code plan, not Mode: design.
- S2 (Existing-Code-Claim Verification): swept — app.js:278 (itemState), :289 (isComplete), :1660-1701 (branchGroup/visibleInTree), :395 (isShippedNotDeployed, PR-#61 line) all read against the actual file at audit time.
- S3 (Cross-Section Consistency): n/a — Mode: code.
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters.
- S5 (Scope-vs-Analysis Check): swept — every "Add/Modify" targets a file in Files-to-Modify; nothing targets a Scope-OUT file.

## Definition of Done
- [ ] All tasks checked off
- [ ] state self-tests + new filter test pass
- [ ] SCRATCHPAD updated (n/a — builder worktree, no SCRATCHPAD per convention)
- [ ] Completion report appended

## Completion Report

_Generated by close-plan.sh on 2026-07-02T21:08:20Z._

### 1. Implementation Summary

Plan: `docs/plans/workstreams-completed-filter-fix-2026-06-17.md` (slug: `workstreams-completed-filter-fix-2026-06-17`).

Files touched (per plan's `## Files to Modify/Create`):

- `docs/plans/workstreams-completed-filter-fix-2026-06-17.md`
- `neural-lace/workstreams-ui/state/filter-status.selftest.js`
- `neural-lace/workstreams-ui/web/app.js`

Commits referencing these files:

```
0de8da4 feat(workstreams-ui): Tasks 7/8 — backlog surface + context-card gate (salvage + fix + style)
259c3f1 plan(nl-overhaul): fold harness-reviewer REFORMULATE findings (12/12) — task-ID regex fix, estate freeze (B.11), retry-guard verification-class pin, additionalContext pin, shim-based cutover safety; add Wave-B spec appendix (B.0)
29b4048 r2: stale-tab auto-reload - /api/health ui_build_ms + client reload-on-change
2bdc33a fix(workstreams-ui): render fence-grammar detail rows on field presence, not _category (R5)
347cdd8 feat(workstreams): Phase D - item-detail MODAL, context-appropriate action buttons, deploy-tracking
37503dc feat(workstreams-ui): port decision-context fence rendering into four-tier renderer
3da37b1 fix(workstreams-ui): real tier nesting in tree — kill the flat-list
43be5c8 refactor(workstreams): rename neural-lace/conversation-tree-ui → neural-lace/workstreams-ui
536e813 feat(workstreams-ui): operator-authoring substrate + My-tasks surface (Tasks 1/2/6)
58db4d9 wip(workstreams-ui): ORPHANED partial Tasks 7/8 work — builder died mid-session; UNVERIFIED, review before trusting
9142f2a fix(workstreams-ui): repair 8 browser-verified GUI regressions post-reconcile
ac29415 fix(workstreams): reflect real deploy status + stop builder-dispatch noise polluting shipped-not-deployed (#61)
ad1ebd0 feat(workstreams-ui): event-sourced text repair (item-text-set/branch-retitled) + discriminating Awaiting-me/In-flight filters
cada6ac feat(workstreams): Phase 4 — configurable orphan/recently-shipped windows
cdd42cf feat(workstreams-ui): in-modal doc links open in-app via the Docs viewer
d4ce1f3 fix(workstreams): [ACTIVE] plan status wins over stale shipped; show-completed hides done (#62)
e1b5fad feat(workstreams-ui): Task 10 — a11y overlay stack + amber re-key + rename sweep + polish
ebc0453 fix(workstreams-ui): real Repo→Project→Workstream→WorkItem tiers (replace wrong kind-grouping)
ed17f52 feat(workstreams): Phase-2 renderer reframe — four-tier hierarchy + filter panel + detail card + adjustable divider
f830be4 feat(workstreams-ui): cockpit + waiting list + project tree (Tasks 3/4/5)
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
