---
title: docs/reviews/ gitignore makes NL-self-reviews invisible to bug-persistence-gate
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: bug-persistence-gate session; commit 670550f
decision_needed: n/a — auto-applied
predicted_downstream:
  - bug-persistence-gate.sh detection logic
  - .gitignore refinement for NL-self-reviews
  - HARNESS-GAP-10 sub-gap H follow-up plan
---

# docs/reviews/ gitignore makes NL-self-reviews invisible to bug-persistence-gate

## What was discovered

`bug-persistence-gate.sh` could not see a freshly-written review file at `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md`. The gate uses `git ls-files --exclude-standard` and `git status --porcelain` to detect new persistence artifacts — both of which respect `.gitignore`. The neural-lace repo's gitignore broadly excludes `docs/reviews/` to prevent downstream-project reviews from accidentally being committed to the harness repo.

The exclusion is intentional and correct for downstream-project reviews. But it also blinds the gate to legitimate NL-self-reviews — review files genuinely produced about the harness itself, which SHOULD persist in the harness repo. The gate's mechanical detection cannot distinguish "downstream-project review accidentally written here" from "NL-self-review that belongs here." From the gate's perspective, both are equally invisible.

## Why it matters

The harness's own self-improvement mechanism (bug-persistence-gate's enforcement of "every bug surfaced gets persisted before session end") has a structural blind spot for legitimate NL-self-reviews. Persistence to gitignored paths counts as "not persisted" by the gate's mechanical detection — even though the data is durable and intentional. The result: NL-self-reviews require special handling (capture to backlog or discoveries instead) to satisfy the gate, which adds friction to exactly the path the harness wants to encourage.

## Options considered

- **(a) Refine gitignore to allow NL-self-reviews under a name pattern.** E.g., `docs/reviews/nl-self-*.md` is allowed; everything else is ignored. Long-term right answer; requires an explicit naming convention.
- **(b) Capture NL-self-findings to backlog instead.** Chosen for short-term — reuses the existing `docs/backlog.md` persistence path, which the gate already recognizes; no gitignore changes needed today.
- **(c) Extend gate to also scan ignored paths.** Rejected — risks false positives from genuine downstream-project files that landed in the wrong worktree.

## Recommendation

Short-term: option (b). Long-term: option (a) under HARNESS-GAP-10 sub-gap H follow-up plan.

## Decision

Option (b) for short-term — capture NL-self-findings to backlog. Long-term refinement (option a) captured as HARNESS-GAP-10 sub-gap H for follow-up.

## Implementation log

- HARNESS-GAP-10 added to `docs/backlog.md` (commit 670550f) with sub-gap H documenting the meta-finding.
- The discovery-protocol's `docs/discoveries/` directory provides an alternative durable-capture path that bypasses the gitignore problem entirely (this very file is an instance of the workaround).
- Sub-gap H tracked for future plan to refine gitignore rules.
