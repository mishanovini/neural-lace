---
title: NL-implementation plans belong in docs/plans/, not ~/.claude/plans/
date: 2026-05-03
type: architectural-learning
status: decided
auto_applied: true
originating_context: phase-1d-c-1-low-risk-mechanisms.md plan execution; commit cc20cde
decision_needed: n/a — auto-applied
predicted_downstream:
  - docs/plans/ convention for NL-implementation plans
  - future plan-creation discipline across NL sessions
  - scope-enforcement-gate.sh's plan-discovery scope
---

# NL-implementation plans belong in docs/plans/, not ~/.claude/plans/

## What was discovered

The just-shipped `scope-enforcement-gate.sh` (C10 mechanism from Phase 1d-C-1) blocked a commit because it scopes its plan-discovery to the current repo's `docs/plans/` directory. Plans living at `~/.claude/plans/` are invisible to repo-scoped scope enforcement — the gate iterates over `docs/plans/*.md` to find ACTIVE plans, and a plan outside that tree is never matched.

The session had been writing NL-implementation plans at `~/.claude/plans/` historically, treating that directory as the canonical home for harness-development plans. With scope-enforcement-gate now load-bearing, that convention silently broke: every commit against a plan at `~/.claude/plans/` would either get blocked or require a scope-waiver as if the plan didn't exist.

## Why it matters

As scope-enforcement-gate becomes a routine gate on commits in the neural-lace repo, NL-implementation plans must be visible to it. Plans at `~/.claude/plans/` are invisible to the gate's repo-scoped discovery — meaning every legitimate harness-development commit would either get blocked or require a waiver, eroding the gate's signal-to-noise ratio.

## Options considered

- **(a) Keep plans at `~/.claude/plans/`.** Rejected — silently breaks scope-enforcement-gate's discovery; every harness-dev commit becomes a waiver.
- **(b) Move plans to NL's `docs/plans/`.** Chosen — aligns with how other repos use `docs/plans/`, makes plans visible to the gate without modification, and matches the rest of the harness's plan-tracking conventions.
- **(c) Extend scope-enforcement-gate to also scan `~/.claude/plans/`.** Rejected — couples a repo-scoped gate to a user-global directory, creating cross-repo bleed where one project's gate sees another project's plans.

## Recommendation

Option (b). The simplicity of one canonical location per repo dominates; cross-repo bleed from option (c) is a worse failure mode than the migration cost.

## Decision

Option (b) — NL-implementation plans live at `docs/plans/` going forward. Plans previously written at `~/.claude/plans/` will be migrated as they become relevant.

## Implementation log

- The agent-incentive-map plan was placed at `docs/plans/agent-incentive-map.md` (commit 18d3911).
- This discovery-protocol plan placed at `docs/plans/discovery-protocol.md`.
- Documented in commit cc20cde's commit message; pattern reinforced in Phase 1d-C-1's task descriptions.
