# Decision 009: Do not change repo squash-merge commit-message setting

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

GitHub's squash-merge feature has a per-repo `squash_merge_commit_message` setting controlling what populates the squashed merge commit's body. neural-lace's setting is `null` (unset), which defaults to `COMMIT_MESSAGES` (concatenated messages of the squashed commits). The mechanism analysis lives in the PR body, NOT in any individual commit message. This means after squash-merge to master, the mechanism analysis is NOT in the master commit log — it's only retrievable by querying the closed PR.

The question: change the repo setting to `PR_BODY` so the mechanism analysis lands in the master commit log automatically?

## Decision

Do NOT change the repo's `squash_merge_commit_message` setting. Leave it at the default. Traceability of the mechanism field comes from PR-list aggregation (`gh pr list --state merged --search FM-NNN`), not from `git log` over master.

## Alternatives Considered

- **Change to `PR_BODY`** — rejected because (a) it would change ALL squash-merge bodies repo-wide, not just the mechanism section. PRs frequently have long bodies with screenshots, test plans, design notes — concatenating all of that into every master commit message creates noise that future `git log` readers must skim past; (b) the PR-list aggregation provides equivalent traceability without the side effect; (c) the change is reversible later if the absence of mechanism-in-git-log proves painful in practice.
- **Change to `BLANK`** — rejected; would lose the existing useful per-commit messages from the squashed commits.
- **Hybrid: edit the squashed commit message manually at merge time to include just the mechanism section** — rejected; manual + error-prone + would require a wrapper around `gh pr merge`.

## Consequences

- **Enables:** master commit log stays clean and focused on the per-commit "what changed" intent. Mechanism analyses remain queryable via PR search.
- **Costs:** future archaeology requires `gh pr list --search` rather than `git log --grep`. Documented in plan section 2 trace and section 6 observability. Acknowledged limitation.
- **Reversible:** if the limitation proves painful, change the setting in one `gh api` call. The decision can be revisited after the 30-day operational measurement (plan section 1 outcome).

## Implementation reference

No code change — this decision is "do nothing." Documented in plan section 2 (T=4 trace step) and section 10 Decision 6.
