---
title: Plan-lifecycle archival on COMPLETED requires its own scope-waiver
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: agent-incentive-map plan archival; commit b7ceb2d
decision_needed: n/a — auto-applied
predicted_downstream:
  - scope-enforcement-gate may need exemption for plan-lifecycle.sh archival operations
  - plan-lifecycle.sh archival commit semantics
  - waiver-workflow friction reduction
---

# Plan-lifecycle archival on COMPLETED requires its own scope-waiver

## What was discovered

When an active plan flips to `Status: COMPLETED`, `plan-lifecycle.sh` (PostToolUse on Edit/Write under `docs/plans/`) auto-archives it via `git mv docs/plans/<slug>.md docs/plans/archive/<slug>.md`. The Status flip and the rename land in the same commit by the lifecycle hook's design.

The subsequent commit (the one that captures the rename) requires its own scope-waiver against any OTHER active plan's scope. From the perspective of `scope-enforcement-gate`, the archival commit touches `docs/plans/archive/<slug>.md` — a path that was NOT in the now-completed plan's declared scope (because the plan's scope was about its own implementation, not its archival), and NOT in any currently-ACTIVE plan's scope either. The gate sees an apparently-out-of-scope file change and blocks until a waiver is written.

This is a routine housekeeping commit, but the friction makes it feel like a bug.

## Why it matters

Routine archival commits should not require a scope-waiver dance. The friction adds noise to legitimate housekeeping and trains the operator to write waivers reflexively, which erodes the gate's signal. If every plan-completion produces a waiver-requiring commit, "scope-waiver" stops meaning "I have an exception" and starts meaning "I'm doing routine work."

## Options considered

- **(a) Accept the waiver dance as a minor friction cost.** Chosen for now. Frequency is low (one per plan completion); the explicit waiver creates an audit trail.
- **(b) Extend `scope-enforcement-gate` to detect `plan-lifecycle.sh` rename operations and auto-allow them when triggered by `Status: COMPLETED` on a recently-active plan.** Right long-term answer; requires gate-level introspection of which other hook fired the change.
- **(c) Bundle the archival into the COMPLETED-flip commit rather than a separate commit.** Changes `plan-lifecycle.sh` behavior; risks corrupting the audit trail because the Status-flip and the file-move would no longer be separately revertable.

## Recommendation

Option (a) for now; option (b) captured as a process-discovery for follow-up. Option (c) rejected on audit-trail grounds.

## Decision

Option (a) for now. Option (b) captured here as a discovery for follow-up plan; this discovery itself is `decided` (the choice is option (a)) but flags the long-term improvement path explicitly.

## Implementation log

- Scope-waiver written at `.claude/state/scope-waiver-pre-submission-audit-mechanical-enforcement-2026-05-03-211200.txt`.
- Archival landed in commit b7ceb2d.
- The long-term improvement (option b) is not blocked but not prioritized; if friction accumulates noticeably, the discovery resurfaces it for a focused fix plan.
