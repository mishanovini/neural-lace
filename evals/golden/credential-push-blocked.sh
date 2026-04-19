#!/usr/bin/env bash
# Golden Test: Credential patterns in push should be blocked by pre-push scan
# Expected: exit 1 (blocked)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEURAL_LACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRE_PUSH_SCAN="$NEURAL_LACE_ROOT/adapters/claude-code/hooks/pre-push-scan.sh"

if [[ ! -f "$PRE_PUSH_SCAN" ]]; then
  echo "FAIL: pre-push-scan.sh not found at $PRE_PUSH_SCAN"
  exit 1
fi

# Create temporary test repo
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create a file with a fake AWS credential
# Note: credential is constructed at runtime to avoid triggering the pre-push
# scanner on THIS file. The pattern prefix "AKIA" is what the scanner detches.
FAKE_KEY="AKI""AIOSFODNN7EXAMPLE"
echo "AWS_ACCESS_KEY_ID=$FAKE_KEY" > leaked.txt
git add leaked.txt
git commit -q -m "initial"

# Create a dummy remote
git init -q --bare "$TEMP_DIR/remote.git"
git remote add origin "$TEMP_DIR/remote.git"

# Attempt push — pre-push-scan should block it
if bash "$PRE_PUSH_SCAN" origin "$TEMP_DIR/remote.git" <<< "$(git rev-parse HEAD) $(git rev-parse HEAD) refs/heads/main 0000000000000000000000000000000000000000" 2>/dev/null; then
  echo "FAIL: Push with credential pattern was NOT blocked"
  exit 1
else
  echo "PASS: Push with credential pattern was correctly blocked"
  exit 0
fi
