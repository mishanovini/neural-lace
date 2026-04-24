#!/bin/bash
# record-test-pass.sh
#
# Write a "test-pass receipt" for the current repo + branch + HEAD SHA
# so that pre-push-test-gate.sh allows a push to master/main.
#
# USAGE:
#   Run AFTER a successful test run:
#     npm test && ~/.claude/scripts/record-test-pass.sh
#
#   The caller is responsible for only invoking this when tests
#   actually passed. The script itself doesn't re-run tests — it just
#   records the claim that they did.
#
# EFFECT:
#   Writes .claude/state/test-receipt-<branch-slug>-<head-sha>.txt in
#   the current repo with the token TESTS_PASSED_FOR_SHA=<sha>.
#
# Repo must have .claude/pre-push-test-gate.enabled for the gate to
# check, but the receipt file is always written if invoked in a repo.

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  echo "[record-test-pass] not inside a git repo" >&2
  exit 2
fi

head_sha=$(git rev-parse HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)
branch_slug=$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]-')

mkdir -p "$repo_root/.claude/state"
receipt="$repo_root/.claude/state/test-receipt-${branch_slug}-${head_sha}.txt"

cat > "$receipt" <<RECEIPT
# Test-pass receipt
# Recorded by: ${USER:-${USERNAME:-unknown}}
# Date:        $(date -Iseconds)
# Branch:      $branch
# HEAD SHA:    $head_sha
#
# This file certifies that the test suite was run and passed for the
# above commit. pre-push-test-gate.sh will consume this receipt to
# authorize a push of this SHA to a protected branch.
#
# Authoritative line (do not edit):
TESTS_PASSED_FOR_SHA=$head_sha
RECEIPT

echo "[record-test-pass] wrote $receipt"
