#!/usr/bin/env bash
# Golden Test: Force push should be blocked by PreToolUse hook
# Tests the pattern matching that would be in settings.json
# Expected: pattern matches (exit 0 from grep = hook would block)

set -euo pipefail

PASS=0
FAIL=0

# Test cases that should be blocked
blocked_patterns=(
  "git push --force origin main"
  "git push -f origin main"
  "git push --force-with-lease origin feature"
  "git push -f"
)

# Test cases that should NOT be blocked
allowed_patterns=(
  "git push origin main"
  "git push -u origin feature/new"
  "git push"
)

PATTERN='git\s+push\s+.*(-f|--force)'

for cmd in "${blocked_patterns[@]}"; do
  if echo "$cmd" | grep -qE "$PATTERN"; then
    echo "PASS: Correctly blocked: $cmd"
    ((PASS++))
  else
    echo "FAIL: Should have blocked: $cmd"
    ((FAIL++))
  fi
done

for cmd in "${allowed_patterns[@]}"; do
  if echo "$cmd" | grep -qE "$PATTERN"; then
    echo "FAIL: Should have allowed: $cmd"
    ((FAIL++))
  else
    echo "PASS: Correctly allowed: $cmd"
    ((PASS++))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
