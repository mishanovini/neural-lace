#!/usr/bin/env bash
# Synthetic Scenario: secret-paste
#
# Exercises pre-push-scan.sh — the pre-push credential scanner. Bad case:
# a push range whose diff contains a synthetic AWS-shaped credential →
# gate BLOCKS. Good case: a clean push range with no credential-shaped
# content → gate ALLOWS.
#
# Invocation contract (mirrors evals/golden/credential-push-blocked.sh):
# the gate is invoked as `bash <gate.sh> <remote-name> <remote-url>` with
# the git pre-push stdin protocol line
# "<local-sha> <local-sha> <ref> <remote-sha-zeros>" piped via stdin.
# Exit 0 = allowed (push proceeds), non-zero = blocked.
#
# GOLDEN-EVAL-ENV-01 dodge (docs/backlog.md): on any machine with
# `git config --global core.hooksPath` pointed at the harness git-hooks
# dispatcher, the machine-global pre-commit credential scan intercepts
# the FIXTURE SETUP commit (which stages a synthetic AWS key) before this
# scenario's actual pre-push assertion runs. Fixture commits in this
# scenario use `git -c core.hooksPath=/dev/null commit` (scoped to the
# temp repo's git invocation only) so the local machine's global hooks
# never see the fixture setup, and only the pre-push-scan.sh gate under
# test is exercised.
#
# Expected: bad case blocked (non-zero), good case allowed (rc 0).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$NL_ROOT/adapters/claude-code/hooks/pre-push-scan.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: pre-push-scan.sh not found at $GATE"
  exit 1
fi

FAILS=0
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# ---- Bad case: commit contains a synthetic AWS-shaped credential ----
BAD_REPO="$TEMP_DIR/bad-repo"
mkdir -p "$BAD_REPO"
(
  cd "$BAD_REPO" || exit 1
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false 2>/dev/null || true

  # Credential constructed at runtime (concatenation) so this scenario
  # file itself never contains the literal pattern the scanner detects,
  # and so harness-hygiene-scan.sh never flags this file either.
  FAKE_KEY="AKI""AIOSFODNN7EXAMPLE"
  echo "AWS_ACCESS_KEY_ID=$FAKE_KEY" > leaked.txt
  git add leaked.txt
  # Scoped hooksPath override — dodges GOLDEN-EVAL-ENV-01 on machines
  # with a global core.hooksPath wired to the harness git-hooks dispatcher.
  git -c core.hooksPath=/dev/null commit -q -m "initial"

  git init -q --bare "$BAD_REPO/remote.git"
  git remote add origin "$BAD_REPO/remote.git"
)

BAD_SHA="$(cd "$BAD_REPO" && git rev-parse HEAD)"
RC=0
(
  cd "$BAD_REPO" || exit 1
  printf '%s %s refs/heads/main 0000000000000000000000000000000000000000\n' "$BAD_SHA" "$BAD_SHA" \
    | bash "$GATE" origin "$BAD_REPO/remote.git"
) >/dev/null 2>&1
RC=$?

if [[ "$RC" -ne 0 ]]; then
  echo "PASS: push containing a credential-shaped pattern was correctly blocked (rc=$RC)"
else
  echo "FAIL: push containing a credential-shaped pattern should have been blocked (rc=$RC, expected non-zero)"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: clean commit, no credential-shaped content ----
GOOD_REPO="$TEMP_DIR/good-repo"
mkdir -p "$GOOD_REPO"
(
  cd "$GOOD_REPO" || exit 1
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false 2>/dev/null || true

  echo "hello world, nothing sensitive here" > clean.txt
  git add clean.txt
  git -c core.hooksPath=/dev/null commit -q -m "initial"

  git init -q --bare "$GOOD_REPO/remote.git"
  git remote add origin "$GOOD_REPO/remote.git"
)

GOOD_SHA="$(cd "$GOOD_REPO" && git rev-parse HEAD)"
RC=0
(
  cd "$GOOD_REPO" || exit 1
  printf '%s %s refs/heads/main 0000000000000000000000000000000000000000\n' "$GOOD_SHA" "$GOOD_SHA" \
    | bash "$GATE" origin "$GOOD_REPO/remote.git"
) >/dev/null 2>&1
RC=$?

if [[ "$RC" -eq 0 ]]; then
  echo "PASS: clean push was correctly allowed (rc=$RC)"
else
  echo "FAIL: clean push should have been allowed (rc=$RC, expected 0)"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-secret-paste: ALL PASSED"
  exit 0
fi
echo "scenario-secret-paste: $FAILS FAILURE(S)"
exit 1
