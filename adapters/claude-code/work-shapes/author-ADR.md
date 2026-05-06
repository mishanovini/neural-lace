---
shape_id: author-ADR
category: decision
required_files:
  - "docs/decisions/NNN-<slug>.md"
  - "docs/DECISIONS.md row pointing at the new ADR"
mechanical_checks:
  - "test -f docs/decisions/NNN-<slug>.md"
  - "grep -q '^# ADR ' docs/decisions/NNN-<slug>.md"
  - "grep -q '^**Date:**' docs/decisions/NNN-<slug>.md"
  - "grep -q '^**Status:**' docs/decisions/NNN-<slug>.md"
  - "grep -q '## Context' docs/decisions/NNN-<slug>.md && grep -q '## Decision' docs/decisions/NNN-<slug>.md && grep -q '## Alternatives' docs/decisions/NNN-<slug>.md && grep -q '## Consequences' docs/decisions/NNN-<slug>.md"
  - "grep -q 'NNN-<slug>' docs/DECISIONS.md"
worked_example: docs/decisions/026-harness-catches-up-to-doctrine.md
---

# Work Shape — Author ADR

## When to use

When the work makes a Tier 2 or Tier 3 architectural / process decision that must outlive the current plan — a choice between valid implementations, a new cross-file architecture pattern, a scope-shape decision, a process convention, anything the user explicitly asks about ("which approach?"), or anything per `~/.claude/rules/planning.md` "every Tier 2+ decision gets a decision record in the same commit." A short entry in a plan's Decisions Log is necessary but not sufficient — that entry disappears once the plan is archived; the ADR persists.

## Structure

A compliant ADR produces two artifacts:

1. **The ADR file** at `docs/decisions/NNN-<slug>.md`, where NNN is the next zero-padded number (per `docs/DECISIONS.md`'s most recent row). Required sections:
   - **`# ADR NNN — <Title>`** as H1.
   - **`**Date:**`**, **`**Status:**`** (Active / Implemented / Deferred / Reverted), **`**Stakeholders:**`** as bold-line metadata.
   - **`## Context`** — what problem drove the decision.
   - **`## Decision`** — what was chosen, in unambiguous prose.
   - **`## Alternatives`** (or `## Alternatives Considered`) — every other option weighed, each with a 1-2 line "why rejected."
   - **`## Consequences`** — what this enables, what it costs, what it blocks.
2. **Index row** added to `docs/DECISIONS.md` linking to the new ADR.

The ADR file AND the index row land in the **same commit** as the implementation that operationalizes the decision (per `decisions-index-gate.sh` atomicity).

## Common pitfalls

- **No alternatives recorded.** ADRs without alternatives are press releases, not decisions. Future readers cannot evaluate whether the choice still holds.
- **NNN reused.** The next number is whatever the most recent row in `docs/DECISIONS.md` plus one — verify before writing. The hook `decisions-index-gate.sh` blocks duplicate or out-of-order NNNs.
- **Index row in a separate commit.** Atomicity matters — splitting the commit lets one of the two land without the other, breaking the index. Stage both together.
- **Plan-only Decisions Log entry without ADR.** The Decisions Log entry is the local note; the ADR is the durable record. Both are required for Tier 2+ decisions.
- **Status not updated when the decision evolves.** If a later ADR supersedes this one, flip Status to `Superseded by ADR NNN` and add a one-line note.
- **Vague Context.** Without the failure mode that prompted the decision, future readers cannot tell if the underlying problem still exists.

## Worked example walk-through

`docs/decisions/026-harness-catches-up-to-doctrine.md` exemplifies the shape:

- H1: `# ADR 026 — Harness Catches Up to Doctrine`.
- Bold-line metadata for Date, Status, Stakeholders.
- Context section names the failure: two months of failsafe stacking produced a verification stack costing more than the work it gates (~13 sub-agent dispatches, ~65K tokens to close a 7-task plan).
- Decision section states the corrective architecture explicitly.
- Alternatives weighed with rejection rationale.
- Consequences enumerate what the decision enables, costs, and blocks.
- Indexed in `docs/DECISIONS.md` row 026 in the same commit as the file's creation.
