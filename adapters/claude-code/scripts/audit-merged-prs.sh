#!/usr/bin/env bash
# audit-merged-prs.sh — Run the PR template validator against the last N merged PRs.
#
# Iterates `gh pr list --state merged --limit N` and runs the shared validator
# library against each PR's body. Reports per-PR PASS/FAIL plus a summary count
# of pre-rollout PRs that would have failed the new check. Used in the runbook
# entry for retroactive audit (plan section 10, runbook).
#
# This script does NOT modify any PR or post any comment. Read-only.
#
# USAGE
#   audit-merged-prs.sh [--limit N] [--repo OWNER/REPO]
#   audit-merged-prs.sh --self-test
#
# OPTIONS
#   --limit N      Number of merged PRs to audit (default 20).
#   --repo OWNER/REPO   Override the target repo (default: current repo via gh).
#   --self-test    Run internal assertions on the validator with synthetic
#                  PR bodies; print OK/FAIL; exit. Does NOT call gh.
#
# EXIT CODES
#   0 — audit complete (regardless of how many PRs failed the check)
#   1 — invalid arguments / gh not authenticated
#   2 — validator library missing in the harness repo
#
# CROSS-REFERENCES
#   - Plan: docs/plans/capture-codify-pr-template.md (Task A.12)
#   - Validator: .github/scripts/validate-pr-template.sh

set -eo pipefail

# --- Resolve harness paths ---------------------------------------------------

HARNESS_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VALIDATOR_LIB="$HARNESS_ROOT/.github/scripts/validate-pr-template.sh"

if [ ! -f "$VALIDATOR_LIB" ]; then
  echo "audit-merged-prs: validator library missing: $VALIDATOR_LIB" >&2
  exit 2
fi

# --- Self-test mode ----------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  # shellcheck disable=SC1090
  source "$VALIDATOR_LIB"

  PASS_BODY='## Summary
Fix.

## What changed and why
A change.

## What mechanism would have caught this?
### a) Existing catalog entry
FM-001 — bug-persistence trigger.

## Testing performed
ran tests'

  FAIL_BODY='## Summary
Fix.

## What changed and why
A change.

## Testing performed
ran tests'

  set +e
  validate_pr_body "$PASS_BODY" >/dev/null 2>&1
  RC_PASS=$?
  validate_pr_body "$FAIL_BODY" >/dev/null 2>&1
  RC_FAIL=$?
  set -e

  if [ "$RC_PASS" -ne 0 ]; then
    echo "self-test: FAIL — well-formed body should validate (got rc=$RC_PASS)" >&2
    exit 1
  fi
  if [ "$RC_FAIL" -eq 0 ]; then
    echo "self-test: FAIL — body missing mechanism section should reject (got rc=0)" >&2
    exit 1
  fi
  echo "self-test: case 'pass body validates' OK"
  echo "self-test: case 'fail body rejects' OK"
  echo "self-test: OK"
  exit 0
fi

# --- Argument parsing --------------------------------------------------------

LIMIT=20
REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --limit=*)
      LIMIT="${1#--limit=}"
      shift
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --repo=*)
      REPO="${1#--repo=}"
      shift
      ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "audit-merged-prs: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "audit-merged-prs: gh CLI not installed; cannot fetch PR list" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "audit-merged-prs: gh CLI not authenticated; run 'gh auth login'" >&2
  exit 1
fi

# --- Fetch and audit ---------------------------------------------------------

# shellcheck disable=SC1090
source "$VALIDATOR_LIB"

GH_ARGS="pr list --state merged --limit $LIMIT --json number,title,body,mergedAt"
if [ -n "$REPO" ]; then
  GH_ARGS="$GH_ARGS --repo $REPO"
fi

# Fetch PR list as JSON. Emit each PR as a row.
PR_JSON="$(gh $GH_ARGS)"

# Iterate via jq one row at a time. -c gives compact JSON per line.
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

# Use process substitution to feed lines into the loop. printf for safety
# with shells that lack readarray.
while IFS= read -r row; do
  TOTAL=$((TOTAL + 1))
  PR_NUM="$(printf '%s' "$row" | jq -r '.number')"
  PR_TITLE="$(printf '%s' "$row" | jq -r '.title')"
  PR_BODY="$(printf '%s' "$row" | jq -r '.body // ""')"
  PR_MERGED="$(printf '%s' "$row" | jq -r '.mergedAt')"

  # Run validator. Suppress its stdout/stderr so this script can produce a
  # clean tabular summary. Capture verdict from exit code.
  set +e
  validate_pr_body "$PR_BODY" >/dev/null 2>&1
  RC=$?
  set -e

  if [ "$RC" -eq 0 ]; then
    VERDICT="PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    VERDICT="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  printf '%-6s  PR #%-5s  merged=%s  %s\n' "$VERDICT" "$PR_NUM" "$PR_MERGED" "$PR_TITLE"
done < <(printf '%s' "$PR_JSON" | jq -c '.[]')

# --- Summary ------------------------------------------------------------------

printf '\n'
printf 'audit-merged-prs: scanned %d merged PRs\n' "$TOTAL"
printf '  PASS: %d\n' "$PASS_COUNT"
printf '  FAIL: %d\n' "$FAIL_COUNT"
if [ "$TOTAL" -gt 0 ]; then
  PCT=$(( PASS_COUNT * 100 / TOTAL ))
  printf '  Compliance: %d%%\n' "$PCT"
fi
printf '\n'

if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'Note: pre-rollout PRs are expected to FAIL — they predate the template.\n'
  printf 'Use this audit to (a) verify the validator is sound, (b) measure baseline\n'
  printf 'compliance, (c) track post-rollout improvement.\n'
fi

exit 0
