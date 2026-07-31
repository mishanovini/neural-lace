#!/usr/bin/env bash
# Synthetic Scenario: commit-without-tests
#
# Exercises pre-commit-tdd-gate.sh (Layer 1: new runtime files require a
# matching test file). Bad case: a new API route file staged with no
# co-located test → gate BLOCKS (rc 1). Good case: the same route file
# staged alongside a co-located test → gate ALLOWS (rc 0).
#
# Invocation contract (verified against the gate's own --self-test
# fixtures): the gate is invoked with `bash <gate.sh>` from inside the
# target repo directory; it reads `git diff --cached` itself — no stdin,
# no CLI args. Exit 0 = allowed, exit 1 = blocked.
#
# Expected: both cases behave as named above (rc 1 bad, rc 0 good).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$NL_ROOT/adapters/claude-code/hooks/pre-commit-tdd-gate.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: pre-commit-tdd-gate.sh not found at $GATE"
  exit 1
fi

FAILS=0

_mkrepo() {
  local dir="$1"
  git init -q "$dir" >/dev/null 2>&1
  (
    cd "$dir" || exit 1
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false 2>/dev/null || true
  )
}

_run_gate() {
  local dir="$1"
  local rc=0
  ( cd "$dir" && bash "$GATE" ) >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# ---- Bad case: new API route, no co-located test → expect BLOCK (rc 1) ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
_mkrepo "$BAD_DIR"
mkdir -p "$BAD_DIR/src/app/api/widgets"
cat > "$BAD_DIR/src/app/api/widgets/route.ts" <<'EOF'
export async function GET() {
  return new Response("ok");
}
EOF
( cd "$BAD_DIR" && git add -A ) >/dev/null 2>&1

RC=$(_run_gate "$BAD_DIR")
if [[ "$RC" == "1" ]]; then
  echo "PASS: new route.ts without a co-located test was correctly blocked (rc=$RC)"
else
  echo "FAIL: new route.ts without a co-located test should have been blocked (rc=$RC, expected 1)"
  FAILS=$((FAILS + 1))
fi

# ---- Good case: same route, WITH a co-located test → expect ALLOW (rc 0) ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
_mkrepo "$GOOD_DIR"
mkdir -p "$GOOD_DIR/src/app/api/widgets" "$GOOD_DIR/tests/api"
cat > "$GOOD_DIR/src/app/api/widgets/route.ts" <<'EOF'
export async function GET() {
  return new Response("ok");
}
EOF
cat > "$GOOD_DIR/tests/api/widgets.test.ts" <<'EOF'
import { describe, it, expect } from "vitest";

describe("widgets route", () => {
  it("returns 200 with the expected body", async () => {
    const res = await fetch("/api/widgets");
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toBe("ok");
  });
});
EOF
( cd "$GOOD_DIR" && git add -A ) >/dev/null 2>&1

RC=$(_run_gate "$GOOD_DIR")
if [[ "$RC" == "0" ]]; then
  echo "PASS: new route.ts with a co-located non-trivial test was correctly allowed (rc=$RC)"
else
  echo "FAIL: new route.ts with a co-located test should have been allowed (rc=$RC, expected 0)"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-commit-without-tests: ALL PASSED"
  exit 0
fi
echo "scenario-commit-without-tests: $FAILS FAILURE(S)"
exit 1
