---
title: Plan template gains `## In-flight scope updates` section; gate redesign deferred to plan
date: 2026-05-04
type: process
status: decided
auto_applied: true
originating_context: D1 of the D1-D5 educational re-do dialogue 2026-05-03/04; user reframed the waiver-system question
decision_needed: n/a — auto-applied (template addition is reversible)
predicted_downstream:
  - ~/.claude/templates/plan-template.md (template now suggests the new section)
  - adapters/claude-code/templates/plan-template.md (mirror)
  - All future plan files (will include the new section by default)
  - scope-enforcement-gate.sh (must be updated to read this section; deferred to dedicated plan)
  - Future cleanup of waiver files (rare-and-meaningful instead of routine)
---

# Plan template gains `## In-flight scope updates` section; gate redesign deferred to plan

## What was discovered

The user reframed the waiver-system friction from a tactical question ("how do we reduce the friction?") into an architectural one ("plans aren't omniscient predictions; we need to allow for surprises during build process; should plans have space for in-flight updates?"). The structurally-correct answer to out-of-scope files isn't a waiver — it's updating the plan to reflect the actual scope, with a substantive reason. The current scope-enforcement-gate's block-message rewards the wrong path (waiver = easy, plan-update = friction).

## Why it matters

Plans become living artifacts that match actual scope rather than static predictions. Waivers become rare-and-meaningful (genuinely cross-plan work) rather than routine. Future readers can see when scope expanded, by what, and why — directly in the plan file. The gate becomes a teacher (here's how to update the plan correctly) rather than a blocker (write a waiver and continue).

## Options considered

- **A — Add new `## In-flight scope updates` section to plan template; update gate to read it; tier the gate's block-message options.** Selected.
- **B — Use the existing `## Decisions Log` for these.** Rejected — Decisions Log is for plan-time-decisions-with-interface-impact (per planning.md), not for mid-execution scope adjustments. Different abstraction.
- **C — Auto-update `## Files to Modify/Create` directly without a separate section.** Rejected — loses the audit trail of WHEN something was added; the original scope declaration becomes mixed with in-flight additions.
- **D — Use the discovery protocol for all scope expansions.** Rejected — overweight for mechanical "I forgot a file" cases. The discovery protocol IS used for architectural learnings; the in-flight-scope-updates section handles the lighter-weight mechanical case.

## Recommendation

A. The new section captures mechanical scope expansions IN the plan; the discovery protocol handles broader architectural learnings; the two compose.

## Decision

A applied — partial. The plan-template addition is auto-applied now (reversible; small change). The actual gate redesign (updating `scope-enforcement-gate.sh` to read the new section + restructuring the block-message into three tiered options) is deferred to a dedicated plan because it's a load-bearing hook change and warrants its own plan + self-tests.

## Implementation log

**Auto-applied this session:**
- `~/.claude/templates/plan-template.md`: new `## In-flight scope updates` section added after `## Files to Modify/Create`. Template comment explains: format, when to use vs the discovery protocol, gate-integration intent. Default content: `(no in-flight changes yet)` so empty plans don't trigger the gate.
- `adapters/claude-code/templates/plan-template.md`: mirrored.

**Deferred to dedicated plan:**
- `scope-enforcement-gate.sh` redesign — read `## In-flight scope updates` alongside `## Files to Modify/Create`; restructure block-message to surface three tiered options (update plan; defer to other plan; waive). Estimated ~3-4 hours; warrants its own plan with self-test scenarios.

**Migration notes for the deferred plan:**
- Existing plans don't have the new section. The hook should treat missing section as empty (no-op), preserving backward compatibility.
- Existing `.claude/state/scope-waiver-*.txt` files don't need conversion; they remain valid as historical records.
- After the gate redesign ships, future scope expansions naturally use the new section; waivers become rare.

**Pattern for the educational format inside the gate's new block-message:**

```
================================================================
SCOPE ENFORCEMENT GATE — COMMIT BLOCKED
================================================================

This commit stages files outside the active plan's declared scope.

Out-of-scope staged files:
  • <file1>
  • <file2>

Three options, in order of structural-correctness:

  1. UPDATE THE PLAN (recommended for mechanical "this file is part of
     the work but wasn't listed").
     Add to <plan-path>'s `## In-flight scope updates` section:
       - 2026-05-04: <file> — <one-line reason>
     Then re-stage and re-commit.

  2. DEFER TO A DIFFERENT PLAN (recommended when this is genuinely
     unrelated work).
     Unstage the file: `git restore --staged <file>`
     Add a backlog entry or new plan to claim it.

  3. WAIVE (only when work is genuinely cross-plan; e.g., touching
     files governed by a different active plan).
     Write a substantive justification to:
       .claude/state/scope-waiver-<plan-slug>-<timestamp>.txt
================================================================
```

## Cross-references

- `~/.claude/rules/discovery-protocol.md` — discoveries-vs-scope-updates split
- `scope-enforcement-gate.sh` — the hook that needs updating (deferred)
- HARNESS-GAP-10 — sub-gaps catalog where the gate-redesign work will be sequenced
