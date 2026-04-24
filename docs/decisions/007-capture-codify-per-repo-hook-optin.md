# Decision 007: Per-repo opt-in for the pre-push PR template hook

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

The local pre-push hook (`pre-push-pr-template.sh`) needs to be installed somewhere to fire. Two choices: install globally (every git repo on the developer's machine inherits the hook via `~/.claude/git-hooks/` or `core.hooksPath`), or install per-repo (the rollout script copies it into a target repo's `.git/hooks/pre-push` only when the user explicitly opts in).

## Decision

Install per-repo via the rollout script `adapters/claude-code/scripts/install-pr-template.sh <target-repo>`. The hook is NOT installed globally. Each downstream repo opts in at rollout time by running the script.

## Alternatives Considered

- **Global install via `core.hooksPath`** — rejected because not every harness-equipped repo uses GitHub PRs. The maintainer works on personal scripts, throwaway experiments, and forks of upstream projects with different review conventions. A global hook would fire on every push everywhere and produce false-positive blocks on repos that have no PR-template convention.
- **Global install with auto-skip on missing template** — softer version of the above. Rejected because "missing template" detection requires reading the target repo's `.github/` directory, which is fragile (some repos store templates elsewhere, some have no templates at all). The auto-skip logic itself becomes a maintenance burden.
- **No local hook at all (CI-only)** — covered in Decision 006; rejected because the local hook saves a CI roundtrip and surfaces the omission at push time rather than 30-60s later.

## Consequences

- **Enables:** clean opt-in semantics. Repos that want the discipline get it; repos that don't are unaffected. The user has explicit control.
- **Costs:** the rollout script must be re-run for each new repo. Acceptable: rollout is a one-time setup step per repo, similar to running `npm install` after cloning.
- **Blocks:** none.

## Implementation reference

`adapters/claude-code/git-hooks/pre-push-pr-template.sh` (the hook), `adapters/claude-code/scripts/install-pr-template.sh` (the rollout). Plan section 10, Decision 4.
