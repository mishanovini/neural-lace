# Decision 018 — Spec-section divergence from SCRATCHPAD: Build Doctrine §6 chosen as authoritative; `## Provides`/`## Consumes`/`## Dependencies` deferred

**Date:** 2026-05-04
**Status:** Open (decision recorded; reversal cost is low — adding the three sections later is a follow-up plan, not a revert)
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (Status: ACTIVE)
**Related discovery:** `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md`

## Context

During phase 1d-C-2 planning, SCRATCHPAD's notes referenced extending the C2 spec-freeze gate to also enforce three new plan sections — `## Provides`, `## Consumes`, `## Dependencies` — that would describe what a plan exports to other plans, what it imports from prior plans, and what external dependencies it requires. The phrase used was "per the original C2 extension."

When researching the source-of-truth for these sections, the planner found:

- **No decision document** — `docs/decisions/` does not contain any prior record specifying these sections, their content schemas, or the validation rules a hook would apply to them.
- **No Build Doctrine reference** — `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 (the C1/C2/C16 source-of-truth) does not mention `## Provides`/`## Consumes`/`## Dependencies`. The Build Doctrine equivalent of "behavioral contract" is C16's `## Behavioral Contracts` section with four sub-entries (idempotency, performance budget, retry semantics, failure modes).
- **No committed proposal** — `docs/plans/` does not contain a plan or draft authoring the three sections.

The phrase in SCRATCHPAD is unsourced. Three plausible explanations:

1. A chat-only conversation between the user and the previous session approved the sections without writing them down.
2. The previous session's planner made an aspirational note without intending to lock the design.
3. The previous session confused the section names with C16's `## Behavioral Contracts`.

Building a hook against undefined section semantics produces vaporware: the hook fires, but what it validates is unclear. Validation rules need committed specs.

## Decision

### Decision 018a — Build Doctrine §6 is authoritative for C1, C2, and C16

The Phase 1d-C-2 implementation follows Build Doctrine §6's specs:

- C1: PRD-validity gate with 7 required PRD sections (Decision 015)
- C2: spec-freeze gate with `frozen: true|false` semantics (Decision 016)
- C16: `## Behavioral Contracts` section with four sub-entries at `rung: 3+` (Task 6 of the parent plan)

`## Provides`, `## Consumes`, and `## Dependencies` are NOT implemented in Phase 1d-C-2.

### Decision 018b — Defer the three sections until user specifies semantics

If the user later wants `## Provides`/`## Consumes`/`## Dependencies` sections, that becomes a follow-up plan. The follow-up plan must:

1. Define the content schema of each section (what goes in, what does NOT go in)
2. Specify the hook's validation rules (presence-only? substance check? cross-plan resolution?)
3. Decide whether the sections gate `Status: ACTIVE` (like the 5-field header schema) or just inform reviewers (like `## Walking Skeleton`)
4. Specify how the three sections compose with C16's `## Behavioral Contracts` (do they overlap? are they orthogonal axes?)

Estimated work for the follow-up plan: 1-3 hours of design + a hook implementation similar to plan-reviewer Check 11. Reversal cost is low.

### Decision 018c — Status: Open (until user confirms or amends)

This decision is auto-applied per the discovery-protocol's decide-and-apply discipline (the choice is reversible — adding the three sections later is straightforward). The auto-application is recorded in the discovery file at `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md` so the user sees it at next SessionStart and can confirm, amend, or override.

If the user confirms: this decision moves to `Status: Active`; no follow-up plan is created.

If the user wants the three sections added: a follow-up plan is opened claiming this decision; on completion, this decision moves to `Status: Superseded` with a pointer to the follow-up plan and the corresponding new decision record.

If the user wants different semantics (different section names, different fields, different validation): the same follow-up plan path applies, with the user's amended specs.

## Alternatives considered

- **Implement the three sections per Build Doctrine §6 verbatim (the chosen path).** Sources are explicit; behavior is well-defined; the hook implementation is straightforward.
- **Implement SCRATCHPAD's three sections without specs.** Rejected — there are no specs to implement against. Building a hook that fires on `## Provides` presence without knowing what content is valid produces a hook that doesn't bind; it's enforcement-shaped without enforcement-content.
- **Surface to the user via `AskUserQuestion` before proceeding.** Considered. The discovery-protocol's reversibility test classifies this as a reversible decision (a follow-up plan adds the sections if the user clarifies). Auto-applying lets C1+C2+C16 work proceed without a blocking checkpoint; the discovery file surfaces the choice at next SessionStart for user review.
- **Implement a stub hook that validates only section presence (not content).** Rejected — a presence-only check on undefined-content sections is theatre; planners would write `## Provides` with empty body and the gate would pass.

## Consequences

**Enables:**
- Phase 1d-C-2 ships C1+C2+C16 against committed source-of-truth (Build Doctrine §6) without blocking on undefined design.
- The user reviews the divergence at next SessionStart (via the discovery file) and decides whether to amend.
- Future follow-up plan can adopt or reject the three sections cleanly without disturbing the now-shipped C1+C2+C16.

**Costs:**
- If the user did intend the three sections all along, an extra session is needed to author the follow-up plan. Estimated cost: 1-3 hours of plan-time + a hook similar to Check 11.
- The existing SCRATCHPAD note becomes stale (still references the three sections as "the original C2 extension"). SCRATCHPAD should be updated on the next session to point at this decision.

**Blocks:**
- Nothing structural. Phase 1d-C-2's work proceeds against the Build Doctrine source-of-truth.

## Discovery file pointer

The auto-application of this decision is captured in `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md` so it surfaces at next SessionStart via `discovery-surfacer.sh`. The discovery file's body explains the divergence, lists options, and points at this decision for the resolved direction.

## Cross-references

- `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md` — the discovery file that surfaces this decision
- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — the implementing plan; declares this decision in its Decisions Log under "Use Build Doctrine §6 as authoritative; defer SCRATCHPAD's sections"
- Decision 015 — PRD-validity gate (C1)
- Decision 016 — spec-freeze gate (C2)
- Decision 017 — 5-field plan-header schema (the header fields are orthogonal to the deferred section schema; both can coexist if the user later wants both)
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 — the source-of-truth chosen
- `~/.claude/rules/discovery-protocol.md` — the decide-and-apply discipline that licensed auto-application
