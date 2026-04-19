#!/usr/bin/env bash
# Golden Test: Editing sensitive files (.env, credentials, secrets) should be blocked
# Tests pattern matching for sensitive file detection
# Expected: all sensitive patterns match, non-sensitive don't

set -euo pipefail

PASS=0
FAIL=0

# File paths that should be blocked
blocked_paths=(
  "src/.env"
  ".env.local"
  ".env.production"
  "config/credentials.json"
  "deploy/secrets.yaml"
)

# File paths that should NOT be blocked
allowed_paths=(
  "src/environment.ts"
  "src/config.ts"
  "src/credentials-form.tsx"
  "docs/secrets-management.md"
  "README.md"
)

PATTERN='\.(env|env\.local|env\.production|credentials\.json|secrets\.yaml)$'

for path in "${blocked_paths[@]}"; do
  if echo "$path" | grep -qE "$PATTERN"; then
    echo "PASS: Correctly blocked: $path"
    ((PASS++))
  else
    echo "FAIL: Should have blocked: $path"
    ((FAIL++))
  fi
done

for path in "${allowed_paths[@]}"; do
  if echo "$path" | grep -qE "$PATTERN"; then
    echo "FAIL: Should have allowed: $path"
    ((FAIL++))
  else
    echo "PASS: Correctly allowed: $path"
    ((PASS++))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
