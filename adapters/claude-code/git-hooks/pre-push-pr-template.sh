#!/usr/bin/env bash
# Local pre-push hook: validate PR description against capture-codify template.
#
# This hook is OPT-IN per repo (copied by the rollout script
# `adapters/claude-code/scripts/install-pr-template.sh`, future Task A.11).
# It is NOT installed globally because not every harness-equipped repo uses
# GitHub PRs.
#
# Behavior:
#   1. If `.pr-description.md` exists in the repo root, validate that file's
#      contents (the convention is: developer writes `.pr-description.md`,
#      validates locally, then `gh pr create --body-file .pr-description.md`).
#   2. Otherwise, validate the latest commit message body (`git log -1
#      --format=%B`).
#   3. If the branch matches a WIP pattern (`wip-*`, contains `scratch`),
#      skip the check entirely. Bypass with `git push --no-verify` if needed.
#
# Bash 3.2+ compatible. Same canonical stderr messages as the CI workflow.
#
# Exit codes:
#   0 — pass (or skipped for WIP branch)
#   1 — fail (validation rejected the body)

set -eo pipefail

# Resolve the validator library. Two locations:
#   1. Repo-relative .github/scripts/validate-pr-template.sh — preferred
#      (matches the rollout convention; library lives next to the workflow).
#   2. Adapter-relative adapters/claude-code/.github/scripts/... — fallback
#      for development against the canonical neural-lace repo where the
#      library has not been split out into a project's own .github/.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
VALIDATOR_LIB="$REPO_ROOT/.github/scripts/validate-pr-template.sh"

if [[ ! -f "$VALIDATOR_LIB" ]]; then
  printf '[pr-template] FAIL: validator library not found at %s\n' "$VALIDATOR_LIB" >&2
  printf '[pr-template] hint: this hook expects .github/scripts/validate-pr-template.sh — run the rollout script to install it\n' >&2
  exit 1
fi

# WIP branch skip — read current branch.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
if [[ "$BRANCH" == wip-* ]] || [[ "$BRANCH" == *scratch* ]]; then
  printf '[pr-template] skip: branch "%s" matches WIP pattern; PR template check skipped\n' "$BRANCH" >&2
  exit 0
fi

# Source the validator library
# shellcheck disable=SC1090
source "$VALIDATOR_LIB"

# Determine the body source.
if [[ -f "$REPO_ROOT/.pr-description.md" ]]; then
  printf '[pr-template] validating .pr-description.md (used by `gh pr create --body-file`)\n' >&2
  PR_BODY="$(cat "$REPO_ROOT/.pr-description.md")"
else
  printf '[pr-template] validating latest commit message body (no .pr-description.md present)\n' >&2
  PR_BODY="$(git log -1 --format=%B)"
fi

# Run the validator. validate_pr_body emits stdout progress + stderr failure.
if validate_pr_body "$PR_BODY"; then
  exit 0
else
  printf '[pr-template] hint: edit .pr-description.md (or amend the commit message) to address the failure above\n' >&2
  printf '[pr-template] hint: bypass with `git push --no-verify` for genuine WIP, but CI will still gate the merge\n' >&2
  exit 1
fi
