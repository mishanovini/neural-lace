#!/usr/bin/env bash
# Golden Test: Public repo creation/conversion should be blocked
# Tests pattern matching for gh repo create --public and visibility changes
# Expected: all dangerous patterns match (exit 0 from grep = hook would block)

set -euo pipefail

PASS=0
FAIL=0

# Test cases that should be blocked
blocked_patterns=(
  "gh repo create my-repo --public"
  "gh repo create --public my-repo"
  "gh repo edit --visibility public"
  "gh api repos/owner/repo --method PATCH -f visibility=public"
)

# Test cases that should NOT be blocked
allowed_patterns=(
  "gh repo create my-repo --private"
  "gh repo create my-repo"
  "gh repo edit --visibility private"
  "gh repo view"
)

PATTERN_CREATE='gh\s+repo\s+create.*--public'
PATTERN_EDIT='gh\s+repo\s+edit.*--visibility\s+public'
PATTERN_API='gh\s+api.*visibility.*public'

check_blocked() {
  echo "$1" | grep -qE "$PATTERN_CREATE" || \
  echo "$1" | grep -qE "$PATTERN_EDIT" || \
  echo "$1" | grep -qE "$PATTERN_API"
}

for cmd in "${blocked_patterns[@]}"; do
  if check_blocked "$cmd"; then
    echo "PASS: Correctly blocked: $cmd"
    ((PASS++))
  else
    echo "FAIL: Should have blocked: $cmd"
    ((FAIL++))
  fi
done

for cmd in "${allowed_patterns[@]}"; do
  if check_blocked "$cmd"; then
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
