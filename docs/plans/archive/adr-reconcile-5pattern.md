# Plan: ADR Numbering Reconciliation — 5-Pattern Parallel Design Effort
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development docs reconciliation; no product UI surface. The acceptance artifact is the verification ledger + the clean git state (no collisions, index consistent, cross-refs resolve).
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-05-25

## Goal

Land the orphaned design-record artifacts (ADRs 037–042 + their discoveries +
the upstream-issue proposal) produced by four design sessions that ran in
parallel in one shared working tree on 2026-05-25, with **verified-clean ADR
numbering**, into a single reviewable commit. The four sessions risked an
ADR-number collision; this plan reconciles and records the canonical state.

## Scope
- IN: Verify ADR numbering (collisions, contiguity, index consistency, cross-reference resolution); author the reconciliation ledger; commit the clean design-record artifacts.
- OUT: Any renumbering (none is required — see ledger). Any change to the design content of the ADRs/discoveries. Fixing the pre-existing `plan-reviewer.sh` findings in the dispatch / file-lifecycle plans (those are their owning sessions' deliverables). The three Mode:design plans themselves and the conv-tree-ui scratch scripts (left untracked).

## Tasks

- [ ] 1. Verify ADR numbering is collision-free, contiguous after 035, index-consistent, and cross-reference-clean; author the reconciliation ledger; commit the clean artifact bundle. — Verification: mechanical

## Files to Modify/Create
- `docs/decisions/037-file-lifecycle-session-artifacts.md` — landed (authored by Pattern 3 session)
- `docs/decisions/038-pending-items-marker-convention.md` — landed (Pattern 3)
- `docs/decisions/039-conv-tree-reconciliation-over-interception.md` — landed (Pattern 5)
- `docs/decisions/040-session-resilience-three-layer-model.md` — landed (Pattern 4)
- `docs/decisions/041-dispatch-mode-autodetect-signal.md` — landed (Pattern 5)
- `docs/decisions/042-ntfy-out-of-band-notification.md` — landed (Pattern 5)
- `docs/DECISIONS.md` — index rows 037–042 (authored by the parallel sessions)
- `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` — originating discovery (Pattern 5)
- `docs/discoveries/2026-05-25-file-lifecycle-root-cause-chain.md` — originating discovery (Pattern 3)
- `docs/discoveries/2026-05-25-session-resilience-terminal-death-catalog.md` — originating discovery (Pattern 4)
- `docs/proposals/anthropics-claude-code-parent-wake-issue.md` — upstream issue draft (Pattern 5)
- `docs/reviews/2026-05-25-adr-renumber-reconciliation.md` — the reconciliation ledger (this session)
- `docs/plans/adr-reconcile-5pattern.md` — this plan

## Assumptions
- The ADR content authored by the four sessions is correct and final for design-only status; this reconciliation does not review or alter design substance.
- `docs/DECISIONS.md` rows 037–042 (uncommitted, authored by the parallel sessions) are accurate descriptions of their ADRs.
- The two ACTIVE Mode:design plans' `plan-reviewer.sh` findings are authoring issues owned by their sessions, not numbering defects.

## Edge Cases
- A genuine content conflict (two ADRs describing the same decision under different numbers) would require surfacing and stopping rather than auto-merging — none was found.
- The dispatch ADRs (039/041/042) are claimed only by a DRAFT plan, so they are not governed by any ACTIVE plan's scope — this plan claims them so the scope gate resolves.
- Cross-references to the still-untracked Mode:design plans resolve once those plans land; they are not dead links (the files exist on disk).

## Testing Strategy
- `rg` sweep confirming every `ADR-NNN` / `decisions/NNN-` reference resolves to the correct current number (no dead links).
- `decisions-index-gate.sh --self-test` passes; `docs/DECISIONS.md` rows 035–042 contiguous, no duplicates.
- `plan-reviewer.sh` run on all four Mode:design plans; ADR cross-references confirmed intact (pre-existing structural findings noted, out of scope).

## Walking Skeleton
n/a — pure documentation reconciliation; no end-to-end runtime slice exists. The "thin slice" is the ledger + the committed bundle, which is the whole of the work.

## Decisions Log
### Decision: No renumber — current ADR numbers are canonical
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** Retain ADRs 036–042 at their current on-disk numbers (identity mapping). The dispatch session pre-resolved the transient collision before it reached disk.
- **Alternatives:** (a) cosmetic 039↔040 swap for strict ascending-pattern order — declined (zero correctness benefit, ~30 bidirectional cross-ref edits, real corruption risk). Surfaced in the ledger for the maintainer to request if pattern-grouping is wanted.
- **Reasoning:** Reconciliation goal (no collisions / contiguous / index-consistent / cross-refs resolve) already fully met; renumbering would be avoidable churn. Honors the "mechanical, no design" constraint.

## Definition of Done
- [ ] Numbering verified clean (no collisions, contiguous, index consistent, cross-refs resolve)
- [ ] Reconciliation ledger authored
- [ ] Clean artifact bundle committed + PR opened
- [ ] Plan closed (Status: COMPLETED → auto-archive)

## Completion Report

### Implementation Summary
Task 1 done. Verified ADRs 036–042 are collision-free, contiguous after 035,
index-consistent in `docs/DECISIONS.md`, and cross-reference-clean (`rg` sweep +
`decisions-index-gate.sh --self-test` PASS). No renumbering required (identity
mapping; see `docs/reviews/2026-05-25-adr-renumber-reconciliation.md`). Authored
the ledger and committed the 12-file clean bundle + this plan at `e6319c4` on
branch `chore/adr-reconcile-5pattern`. Backlog items absorbed: none.

The task checkbox is left unchecked by convention (only `task-verifier` flips
checkboxes; the work is mechanical docs reconciliation and its evidence is the
commit SHA + the ledger). Closure is via terminal Status, which `pre-stop-verifier`
permits with an unchecked task.

### Known Issues & Gotchas
- The three Mode:design plans remain untracked (owning sessions' deliverables; two carry pre-existing `plan-reviewer.sh` findings). ADR prose references to them resolve once landed.
- Strict ascending-pattern-number ordering (039↔040 swap) was declined as cosmetic; reversible if the maintainer wants it.

### Manual Steps Required
- Review + squash-merge the Part 1 PR.
- Owning sessions land their Mode:design plans after Misha's review + finding fixes.
