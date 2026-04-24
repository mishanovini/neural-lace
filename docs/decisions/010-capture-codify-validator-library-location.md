# Decision 010: Validator library lives at `.github/scripts/` (not `adapters/claude-code/`)

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

The PR template validator is sourced by both the CI workflow (`.github/workflows/pr-template-check.yml`) and the local pre-push hook (`adapters/claude-code/git-hooks/pre-push-pr-template.sh`). To prevent regex drift between the two call sites, the validation logic lives in a shared library file that both sources. The location of that library affects rollout simplicity and discoverability.

Two natural locations:
- `.github/scripts/validate-pr-template.sh` — alongside the workflow that uses it; ships when `.github/` is copied to a downstream repo.
- `adapters/claude-code/git-hooks/validate-pr-template.sh` — proper harness location, alongside the hook that also uses it.

## Decision

Library lives at `.github/scripts/validate-pr-template.sh`. Both the workflow and the local hook source it from this single location.

## Alternatives Considered

- **`adapters/claude-code/git-hooks/validate-pr-template.sh`** (the "proper" harness location) — rejected because:
  - Downstream repos receiving the rollout do NOT have an `adapters/claude-code/` tree. The rollout script would need to either copy that subtree (heavy, leaks harness paths into the downstream repo) or rewrite the workflow's `source` path at install time (brittle, hard to keep in sync if the workflow is ever edited).
  - `.github/scripts/` is a path that exists naturally in any GitHub-hosted repo using GitHub Actions — no special tree required.
  - Rollout becomes trivially `cp -r .github/ <target>/` with zero path rewriting.
- **Duplicate the validation logic in both call sites** — rejected because regex drift between CI and local would produce inconsistent failure messages and is the failure mode the shared library is meant to prevent.
- **Embed in the workflow's `run:` step inline** — rejected because the local hook can't source from a workflow YAML file; it would have to duplicate the logic.

## Consequences

- **Enables:** trivial rollout (`cp -r .github/ <target>/`), single source of truth for regex patterns and stderr messages, no path rewriting.
- **Costs:** the validator library is technically a harness asset but lives outside the `adapters/claude-code/` tree. Discoverability cost: a maintainer browsing `adapters/claude-code/` won't see the validator. Mitigated by (a) a one-line cross-reference in `docs/harness-architecture.md` pointing at the `.github/scripts/` location; (b) the harness-review skill checks both trees.
- **Blocks:** none.

## Implementation reference

`.github/scripts/validate-pr-template.sh` (the library), sourced by `.github/workflows/pr-template-check.yml` line 27 and `adapters/claude-code/git-hooks/pre-push-pr-template.sh` line 50. Architecture doc cross-reference in `docs/harness-architecture.md` "Capture-Codify PR Template" section. Plan section 10, Decision 7.
