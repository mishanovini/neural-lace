#!/bin/bash
# pre-commit-gate.sh
#
# Runs before every git commit in Claude Code sessions.
# Exits non-zero to BLOCK the commit if any check fails.
#
# Checks:
#   0. TDD gate — new runtime-feature files must have matching test files
#      (anti-vaporware; runs FIRST because it's cheapest to fail)
#   1. Unit tests pass (npm test)
#   2. Build succeeds (npm run build)
#   3. API consumer audit (no unstaged consumers of changed API routes)

set -eo pipefail

echo "" >&2
echo "╔══════════════════════════════════════════╗" >&2
echo "║        PRE-COMMIT VERIFICATION           ║" >&2
echo "╚══════════════════════════════════════════╝" >&2
echo "" >&2

# 0. TDD gate — anti-vaporware (new + modified runtime files)
TDD_GATE="$HOME/.claude/hooks/pre-commit-tdd-gate.sh"
if [[ -x "$TDD_GATE" ]]; then
  echo "[0a/5] TDD gate (new + modified runtime files must have tests)..." >&2
  if ! bash "$TDD_GATE" >&2; then
    echo "" >&2
    echo "✗ BLOCKED: TDD gate failed. See message above for missing tests." >&2
    exit 1
  fi
  echo "✓ TDD gate passed" >&2
  echo "" >&2
fi

# 0b. Plan-reviewer — any staged docs/plans/*.md files must pass mechanical review
PLAN_REVIEWER="$HOME/.claude/hooks/plan-reviewer.sh"
if [[ -x "$PLAN_REVIEWER" ]]; then
  STAGED_PLANS=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '^docs/plans/[^/]+\.md$' | grep -v -- '-evidence\.md$' || true)
  if [[ -n "$STAGED_PLANS" ]]; then
    echo "[0b/5] Plan-reviewer adversarial check..." >&2
    while IFS= read -r plan; do
      [[ -z "$plan" ]] && continue
      if ! bash "$PLAN_REVIEWER" "$plan" >&2; then
        echo "" >&2
        echo "✗ BLOCKED: plan-reviewer rejected $plan" >&2
        exit 1
      fi
    done <<< "$STAGED_PLANS"
    echo "✓ Plan-reviewer passed" >&2
    echo "" >&2
  fi
fi

# 1. Unit tests
echo "[1/4] Running unit tests..." >&2
if ! npm test 2>&1 | tail -3 >&2; then
  echo "" >&2
  echo "✗ BLOCKED: Unit tests failed. Fix tests before committing." >&2
  exit 1
fi
echo "✓ Tests passed" >&2
echo "" >&2

# 2. Build
echo "[2/4] Running build..." >&2
if ! npm run build 2>&1 | tail -5 >&2; then
  echo "" >&2
  echo "✗ BLOCKED: Build failed. Fix build errors before committing." >&2
  exit 1
fi
echo "✓ Build passed" >&2
echo "" >&2

# 3. API consumer audit
echo "[3/4] Auditing API consumers..." >&2
if [ -f "scripts/audit-api-consumers.sh" ]; then
  if ! bash scripts/audit-api-consumers.sh 2>&2; then
    echo "" >&2
    echo "✗ BLOCKED: API route changed with unstaged consumers." >&2
    echo "  Stage the consumer files or verify backward compatibility." >&2
    exit 1
  fi
  echo "✓ API audit passed" >&2
else
  echo "- API audit script not found, skipping" >&2
fi

echo "" >&2
echo "═══ ALL PRE-COMMIT CHECKS PASSED ═══" >&2
echo "" >&2
