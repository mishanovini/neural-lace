#!/usr/bin/env bash
# Synthetic Scenario: scope-creep
#
# Exercises scope-enforcement-gate.sh — the PreToolUse gate that blocks
# `git commit` when staged files fall outside an ACTIVE plan's declared
# `## Files to Modify/Create` scope. Bad case: an ACTIVE plan claims file
# A; staging an out-of-scope file B alongside A → gate BLOCKS (rc 2).
# Good case: staging only the declared file A → gate ALLOWS (rc 0).
#
# Invocation contract (verified against the gate's own --self-test
# fixtures): PreToolUse hook, invoked with a JSON tool_input piped via
# stdin: {"tool_name":"Bash","tool_input":{"command":"git commit -m
# \"test\""}}, run from inside the target repo directory. Exit 0 =
# allowed, exit 2 = blocked (out-of-scope files).
#
# Expected: bad case blocked (rc 2), good case allowed (rc 0).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$NL_ROOT/adapters/claude-code/hooks/scope-enforcement-gate.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: scope-enforcement-gate.sh not found at $GATE"
  exit 1
fi

FAILS=0

PLAN_BODY='# Plan: synthetic-scope-test
Status: ACTIVE

## Goal
Synthetic fixture plan for scope-enforcement-gate scenario coverage.

## Files to Modify/Create
- `src/foo.ts` — the only file this plan claims

## Tasks
- [ ] 1. test
'

_mkrepo_with_plan() {
  local dir="$1"
  git init -q "$dir" >/dev/null 2>&1
  (
    cd "$dir" || exit 1
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false 2>/dev/null || true
    mkdir -p docs/plans
    printf '%s' "$PLAN_BODY" > docs/plans/synthetic-scope-test.md
    git add docs/plans/synthetic-scope-test.md
    git commit -q -m "init plan"
  )
}

_run_gate() {
  local dir="$1"
  local rc=0
  local input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
  ( cd "$dir" && printf '%s' "$input" | bash "$GATE" ) >/dev/null 2>&1
  rc=$?
  echo "$rc"
}

# ---- Bad case: stage the claimed file PLUS an out-of-scope file ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
_mkrepo_with_plan "$BAD_DIR"
mkdir -p "$BAD_DIR/src" "$BAD_DIR/unrelated"
echo "stub" > "$BAD_DIR/src/foo.ts"
echo "stub" > "$BAD_DIR/unrelated/file.ts"
( cd "$BAD_DIR" && git add src/foo.ts unrelated/file.ts ) >/dev/null 2>&1

RC=$(_run_gate "$BAD_DIR")
if [[ "$RC" == "2" ]]; then
  echo "PASS: staged out-of-scope file was correctly blocked (rc=$RC)"
else
  echo "FAIL: staged out-of-scope file should have been blocked (rc=$RC, expected 2)"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: stage only the plan-declared file ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
_mkrepo_with_plan "$GOOD_DIR"
mkdir -p "$GOOD_DIR/src"
echo "stub" > "$GOOD_DIR/src/foo.ts"
( cd "$GOOD_DIR" && git add src/foo.ts ) >/dev/null 2>&1

RC=$(_run_gate "$GOOD_DIR")
if [[ "$RC" == "0" ]]; then
  echo "PASS: staging only the plan-declared file was correctly allowed (rc=$RC)"
else
  echo "FAIL: staging only the plan-declared file should have been allowed (rc=$RC, expected 0)"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-scope-creep: ALL PASSED"
  exit 0
fi
echo "scenario-scope-creep: $FAILS FAILURE(S)"
exit 1
