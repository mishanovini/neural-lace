---
title: SCRATCHPAD's `## Provides`/`## Consumes`/`## Dependencies` sections are unsourced; Build Doctrine §6 chosen
date: 2026-05-04
type: architectural-learning
status: decided
auto_applied: true
originating_context: phase-1d-c-2 plan creation; researching SCRATCHPAD's note on the C2 extension's section schema
decision_needed: n/a — auto-applied
predicted_downstream:
  - docs/decisions/018-spec-section-divergence-from-scratchpad.md (recorded the chosen direction)
  - docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md (Scope OUT excludes the three sections)
  - Future follow-up plan (if user amends to require the sections after seeing this discovery)
---

## What was discovered

While planning Phase 1d-C-2 (PRD-validity gate C1 + spec-freeze gate C2 + plan-header schema + C16 behavioral contracts), the planner read SCRATCHPAD's reference to "the original C2 extension" — a note that an earlier session contemplated three additional plan sections (`## Provides`, `## Consumes`, `## Dependencies`) describing a plan's interface to other plans.

A source-of-truth check found:

- **No decision document** in `docs/decisions/` records the three sections.
- **No Build Doctrine reference** in `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 mentions them. The Build Doctrine equivalent of "behavioral contract" is C16's `## Behavioral Contracts` section with four sub-entries (idempotency, performance budget, retry semantics, failure modes).
- **No committed proposal** in `docs/plans/` defines content schema, validation rules, or composition with the rest of the plan template.

The SCRATCHPAD phrase is unsourced. Plausible origins:

1. A chat-only conversation between the user and a previous session that approved the sections without writing them down.
2. The previous session's planner made an aspirational note without intending to lock the design.
3. The previous session confused the section names with C16's `## Behavioral Contracts`.

The planner cannot tell from the available evidence which of these applies.

## Why it matters

Implementation of C2 needs to know whether the three sections are required and, if so, what their content schemas are. Building a hook against undefined section semantics produces enforcement-shaped vaporware: the hook fires on section presence but the validation rules are arbitrary because the content schema was never specified. Builders writing plans against the new shape would author placeholder content (`## Provides: TBD`) that passes the hook without conveying meaning.

The two paths forward are:

- Implement the three sections — but only with committed specs. Without specs, this path is blocked.
- Defer the three sections; ship C1+C2+C16 against Build Doctrine §6 (which has committed specs); record the divergence so the user can amend if needed.

## Options

- **A. Implement Build Doctrine §6 verbatim (chosen).** Sources are explicit; behavior is well-defined. C1, C2, C16 ship against committed specs.
- **B. Implement SCRATCHPAD's three sections without specs.** Rejected. Cannot validate sections whose content semantics are undefined; produces a hook that fires but doesn't bind.
- **C. Block on the user via `AskUserQuestion` before proceeding.** Considered. Per the discovery-protocol reversibility test, this decision is reversible — a follow-up plan adds the three sections if the user clarifies. Auto-applying is consistent with the user's continue-autonomously directive AND lets C1+C2+C16 proceed without an interactive blocking checkpoint.
- **D. Implement a stub hook that validates only section presence (not content).** Rejected. Presence-only checks on undefined-content sections are theatre; planners would write empty `## Provides` and the gate would pass. Worse than no hook because it gives false confidence.

## Recommendation

A. Build C1+C2+C16 against Build Doctrine §6 source-of-truth. Defer SCRATCHPAD's three sections to a follow-up plan if the user amends. Record the choice in Decision 018; surface here so the user reviews at next SessionStart.

## Decision

A. Auto-applied. The chosen direction is recorded in `docs/decisions/018-spec-section-divergence-from-scratchpad.md`. The decision is reversible — if the user wants the three sections, the follow-up plan adds them in 1-3 hours of design + a hook similar to plan-reviewer.sh Check 11. Auto-application is licensed by the discovery-protocol decide-and-apply discipline because the worst-case correction is "open one follow-up plan and re-edit a small number of files," not a structural revert.

## Implementation log

- `docs/decisions/018-spec-section-divergence-from-scratchpad.md` — created (records the chosen direction with full Context / Decision / Alternatives / Consequences)
- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — Decisions Log includes the inline entry "Use Build Doctrine §6 as authoritative; defer SCRATCHPAD's sections"; Scope OUT excludes `## Provides`/`## Consumes`/`## Dependencies`
- This file — surfaces the divergence to the user at next SessionStart via `discovery-surfacer.sh`

## Cross-references

- `docs/decisions/018-spec-section-divergence-from-scratchpad.md` — the recorded decision
- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — the implementing plan
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 — the source-of-truth chosen
- `~/.claude/rules/discovery-protocol.md` — the rule licensing auto-application of reversible decisions
- SCRATCHPAD.md (project root) — the file containing the unsourced phrase that motivated the divergence check; should be updated to point at this discovery and decision
