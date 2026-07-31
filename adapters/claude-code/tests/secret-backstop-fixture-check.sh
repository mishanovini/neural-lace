#!/usr/bin/env bash
# secret-backstop-fixture-check.sh
#
# Local RED/GREEN oracle proof for SECRET-SCAN-CI-BACKSTOP-01
# (docs/backlog.md; .github/workflows/secret-backstop.yml).
#
# GitHub Actions cannot be dispatched live from this environment, so this
# script exercises the SAME two scanner scripts the workflow invokes
# (adapters/claude-code/hooks/pre-push-scan.sh,
# adapters/claude-code/hooks/harness-hygiene-scan.sh) against a real,
# disposable temp git repo — proving the oracle the backlog entry names:
#   - a seeded fixture secret in a test branch -> scanner exit 1 (RED)
#   - a normal/clean branch -> scanner exit 0 (GREEN)
#
# ALL writes happen under a mktemp -d sandbox; nothing in the real repo or
# the operator's HOME is touched (per environment discipline: self-tests
# sandbox ALL writes).
#
# Usage: bash adapters/claude-code/tests/secret-backstop-fixture-check.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR"
ADAPTER_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PRE_PUSH_SCAN="$ADAPTER_DIR/hooks/pre-push-scan.sh"
HYGIENE_SCAN="$ADAPTER_DIR/hooks/harness-hygiene-scan.sh"

if [ ! -f "$PRE_PUSH_SCAN" ]; then
  echo "FAIL: pre-push-scan.sh not found at $PRE_PUSH_SCAN" >&2
  exit 1
fi
if [ ! -f "$HYGIENE_SCAN" ]; then
  echo "FAIL: harness-hygiene-scan.sh not found at $HYGIENE_SCAN" >&2
  exit 1
fi

PASS=0
FAIL=0

# AWS's own public documentation placeholder access-key ID. It matches the
# scanner's AKIA[0-9A-Z]{16} shape structurally (real flagless shape) but is
# NOT a live credential — it is the canonical example AWS publishes in its
# own SDK docs specifically so tooling/tests can reference "an AWS-key-
# shaped string" without planting anything real. See DEC-2 in
# docs/plans/secret-scan-ci-backstop-skip.md.
FIXTURE_AWS_KEY="AKIAIOSFODNN7EXAMPLE"

ZERO_SHA="0000000000000000000000000000000000000000"

setup_sandbox_repo() {
  local sandbox
  sandbox=$(mktemp -d -t secret-backstop-test.XXXXXX 2>/dev/null) || sandbox="/tmp/secret-backstop-test.$$"
  (
    cd "$sandbox" || exit 1
    git init -q .
    # Never let a global hooksPath intercept fixture commits in this
    # sandbox (project_global_hookspath_fires_in_all_test_fixtures class).
    git config core.hooksPath ""
    git config user.email "selftest@example.com"
    git config user.name "selftest"
    echo "base file" > base.txt
    git add base.txt
    git commit -q -m "base commit"
  ) >/dev/null 2>&1
  printf '%s' "$sandbox"
}

# ---------------------------------------------------------------------------
# Scenario 1 (RED): a branch whose new commit plants the fixture AWS key.
# pre-push-scan.sh must BLOCK (exit 1) and name the offending file.
# ---------------------------------------------------------------------------

run_red_scenario() {
  local sandbox base_sha
  sandbox=$(setup_sandbox_repo)
  base_sha=$(cd "$sandbox" && git rev-parse HEAD)

  (
    cd "$sandbox" || exit 1
    git checkout -q -b feature-with-secret
    printf 'aws_secret_access_key = "%s"\naws_access_key_id = "%s"\n' \
      "not-a-real-secret-value-000000000000000" "$FIXTURE_AWS_KEY" > config.txt
    git add config.txt
    git commit -q -m "add config (planted fixture secret)"
  ) >/dev/null 2>&1

  local head_sha
  head_sha=$(cd "$sandbox" && git rev-parse HEAD)

  local stdin_line="refs/heads/feature-with-secret $head_sha refs/heads/master $base_sha"
  local out rc
  out=$(cd "$sandbox" && printf '%s\n' "$stdin_line" | bash "$PRE_PUSH_SCAN" origin "https://example.invalid/repo.git" 2>&1)
  rc=$?

  rm -rf "$sandbox"

  if [ "$rc" -ne 1 ]; then
    echo "FAIL (red-scenario): expected pre-push-scan.sh exit 1 on planted AWS key, got $rc" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  if ! printf '%s' "$out" | grep -q "AKIA"; then
    echo "FAIL (red-scenario): block output did not reference the AWS key pattern" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  if ! printf '%s' "$out" | grep -q "config.txt"; then
    echo "FAIL (red-scenario): block output did not name the offending file (config.txt)" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS (red-scenario): pre-push-scan.sh blocked the planted fixture AWS key (exit 1, named config.txt)"
  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------
# Scenario 2 (GREEN): a branch whose new commit is clean. Must exit 0.
# ---------------------------------------------------------------------------

run_green_scenario() {
  local sandbox base_sha
  sandbox=$(setup_sandbox_repo)
  base_sha=$(cd "$sandbox" && git rev-parse HEAD)

  (
    cd "$sandbox" || exit 1
    git checkout -q -b feature-clean
    printf 'just an ordinary code change\nno secrets here\n' > feature.txt
    git add feature.txt
    git commit -q -m "add feature (clean)"
  ) >/dev/null 2>&1

  local head_sha
  head_sha=$(cd "$sandbox" && git rev-parse HEAD)

  local stdin_line="refs/heads/feature-clean $head_sha refs/heads/master $base_sha"
  local out rc
  out=$(cd "$sandbox" && printf '%s\n' "$stdin_line" | bash "$PRE_PUSH_SCAN" origin "https://example.invalid/repo.git" 2>&1)
  rc=$?

  rm -rf "$sandbox"

  if [ "$rc" -ne 0 ]; then
    echo "FAIL (green-scenario): expected pre-push-scan.sh exit 0 on clean diff, got $rc" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS (green-scenario): pre-push-scan.sh allowed the clean diff (exit 0)"
  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------
# Scenario 3 (RED, denylist layer): harness-hygiene-scan.sh --full-tree
# against a temp repo carrying a denylist-matching business identifier.
# Proves the SECOND scanner the workflow invokes also fires.
# ---------------------------------------------------------------------------

run_hygiene_red_scenario() {
  local sandbox
  sandbox=$(mktemp -d -t secret-backstop-hygiene-test.XXXXXX 2>/dev/null) || sandbox="/tmp/secret-backstop-hygiene-test.$$"

  mkdir -p "$sandbox/adapters/claude-code/patterns"
  # Minimal denylist matching the real harness-denylist.txt's provenance
  # (same file the real scanner reads) but self-contained so this test
  # does not depend on the real repo's denylist contents drifting.
  printf '%s\n' '# test denylist (mirrors adapters/claude-code/patterns/harness-denylist.txt shape)' \
    'SECRET_BACKSTOP_TEST_TOKEN' > "$sandbox/adapters/claude-code/patterns/harness-denylist.txt"

  (
    cd "$sandbox" || exit 1
    git init -q .
    git config core.hooksPath ""
    git config user.email "selftest@example.com"
    git config user.name "selftest"
    git add -A
    git commit -q -m "seed denylist"
  ) >/dev/null 2>&1

  echo "this file contains SECRET_BACKSTOP_TEST_TOKEN which must be caught" > "$sandbox/leaky.txt"

  local out rc
  out=$(cd "$sandbox" && bash "$HYGIENE_SCAN" "leaky.txt" 2>&1)
  rc=$?

  rm -rf "$sandbox"

  if [ "$rc" -ne 1 ]; then
    echo "FAIL (hygiene-red-scenario): expected harness-hygiene-scan.sh exit 1 on denylist match, got $rc" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  if ! printf '%s' "$out" | grep -q "SECRET_BACKSTOP_TEST_TOKEN"; then
    echo "FAIL (hygiene-red-scenario): block output did not mention the matched denylist token" >&2
    echo "output was:" >&2
    echo "$out" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS (hygiene-red-scenario): harness-hygiene-scan.sh blocked the denylist match (exit 1)"
  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------

run_red_scenario
run_green_scenario
run_hygiene_red_scenario

echo
echo "secret-backstop-fixture-check: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
