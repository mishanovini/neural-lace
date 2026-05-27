# Plan: Worktree-Per-Session Convention (Part 2 of the 5-pattern cleanup)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development convention doc; no product UI surface. The acceptance artifact is the committed convention doc cross-referencing the existing worktree rules.
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-05-25

## Goal

Document the worktree-per-session convention for the implementation sessions
ahead, so the SCRATCHPAD race + ADR-number collision that the 2026-05-25 parallel
design sessions hit (all sharing one main checkout) cannot recur. Capture the
verified worktree-creation paths, the doc-propagation mechanism, cleanup, and the
surfaced harness gaps.

## Scope
- IN: Author `docs/conventions/worktree-per-session.md` (verified worktree mechanics, the one-session-one-worktree rule, PR-based propagation, cleanup, harness gaps), cross-referencing existing rules rather than duplicating them.
- OUT: Building any new worktree-spawn primitive or ADR-number-allocation gate (surfaced as gaps, not built). Modifying the existing rules.

## Tasks

- [ ] 1. Author the worktree-per-session convention doc with verified mechanics, propagation guidance, cleanup, and surfaced gaps. — Verification: mechanical

## Files to Modify/Create
- `docs/conventions/worktree-per-session.md` — the convention doc (this session)
- `docs/plans/worktree-per-session-convention.md` — this plan

## Assumptions
- The verified worktree behavior (`start_code_task` auto-creates `.claude/worktrees/<name-hash>`; `worktree-prune.sh` is cleanup-only; `docs-publish-on-stop.sh` unbuilt) holds for the implementation phase.
- The existing rules (automation-modes, orchestrator-pattern, git-discipline, agent-teams) remain the authoritative mechanics; this doc is the per-phase convention that points at them.

## Edge Cases
- Interactive (non-dispatched) sessions are NOT auto-isolated; the convention's launch discipline is the only safeguard until a mechanical occupancy guard exists.
- ADR-number selection remains a manual hazard across parallel sessions — surfaced as a gap.

## Testing Strategy
- `plan-reviewer.sh` clean on this plan.
- Doc renders with resolvable cross-references to the four existing worktree rules + `worktree-prune.sh` + ADR 037.

## Walking Skeleton
n/a — single documentation deliverable; the doc itself is the whole slice.

## Decisions Log
### Decision: PR-based merge is the propagation mechanism (not publish-on-stop)
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** Recommend PR-based merge (git-discipline Rule 2) for both design-time and implementation-time doc propagation.
- **Alternatives:** publish-on-stop (ADR 037 D3) — rejected as the recommendation because it is design-only / NOT BUILT; presenting it as available would be a false promise.
- **Reasoning:** Use the mechanism that actually exists; note publish-on-stop as the future lighter path once the file-lifecycle redesign ships.

## Definition of Done
- [ ] Convention doc authored in docs/conventions/
- [ ] Harness gaps surfaced (worktree-spawn enforcement, ADR-number allocation, publish-on-stop unbuilt)
- [ ] Committed
- [ ] Plan closed (Status: COMPLETED → auto-archive)

## Completion Report

### Implementation Summary
Task 1 done. Authored `docs/conventions/worktree-per-session.md` documenting the
verified worktree mechanics (Dispatch auto-creates `.claude/worktrees/<name-hash>`;
Agent `isolation:"worktree"`; manual `git worktree add`), the one-session-one-worktree
rule, PR-based propagation (publish-on-stop noted as unbuilt), `worktree-prune.sh`
cleanup, and three surfaced harness gaps. Cross-references the four existing
worktree rules rather than duplicating them. Backlog items absorbed: none.
Task checkbox left unchecked by convention (only task-verifier flips checkboxes;
evidence is the committed doc + this report); closure via terminal Status.

### Known Issues & Gotchas
- The surfaced gaps (no worktree-spawn enforcement for interactive sessions; no ADR-number allocation primitive; publish-on-stop unbuilt) are recommendations, not built mechanisms.

### Manual Steps Required
- Maintainer decides whether to build the ADR-number allocation gate / interactive-session occupancy guard.
