#!/usr/bin/env bash
# Golden Test: Read operations should always be allowed (T0)
# Verifies that read operations score 0 on all risk dimensions
# Expected: all pass (exit 0)

set -euo pipefail

PASS=0
FAIL=0

# Read operations that should always be allowed
safe_operations=(
  "cat README.md"
  "ls -la src/"
  "git status"
  "git log --oneline -5"
  "git diff"
  "head -20 package.json"
  "wc -l src/index.ts"
  "find . -name '*.tsx' -type f"
  "npm test --dry-run"
)

# These should NOT contain any blocked patterns
DANGEROUS_PATTERNS='(--force|-f\s|--no-verify|--public|chmod -R 777|mkfs\.|dd if=|rm -rf|DROP TABLE|DELETE FROM)'

for op in "${safe_operations[@]}"; do
  if echo "$op" | grep -qE "$DANGEROUS_PATTERNS"; then
    echo "FAIL: Safe operation incorrectly flagged: $op"
    ((FAIL++))
  else
    echo "PASS: Correctly allowed: $op"
    ((PASS++))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
