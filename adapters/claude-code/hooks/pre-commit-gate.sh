#!/bin/bash
# pre-commit-gate.sh
#
# Runs before every git commit in Claude Code sessions.
# Exits non-zero to BLOCK the commit if any check fails.
#
# Checks:
#   0. Document Freshness gates — hygiene + atomicity rules (cheapest to fail)
#   1. TDD gate — new runtime-feature files must have matching test files
#      (anti-vaporware; still runs before tests/build because it's fast)
#   2. Plan-reviewer — adversarial review of any staged plan files
#   3. Unit tests pass (npm test)
#   4. Build succeeds (npm run build)
#   5. API consumer audit (no unstaged consumers of changed API routes)

set -eo pipefail

echo "" >&2
echo "╔══════════════════════════════════════════╗" >&2
echo "║        PRE-COMMIT VERIFICATION           ║" >&2
echo "╚══════════════════════════════════════════╝" >&2
echo "" >&2

# --- Document Freshness gates (fail fast) ---
# Run hygiene + atomicity hooks before any slower gates (TDD, tests, build).
# Each gate reads `git diff --cached` and exits non-zero on violation.
# Order within this block matters less — all are fast — but hygiene-scan
# runs first because it's the most common block path.
FRESHNESS_GATES=(
  "harness-hygiene-scan.sh"
  "decisions-index-gate.sh"
  "backlog-plan-atomicity.sh"
  "docs-freshness-gate.sh"
  "migration-claude-md-gate.sh"
  "review-finding-fix-gate.sh"
)
for gate in "${FRESHNESS_GATES[@]}"; do
  gate_path="$HOME/.claude/hooks/$gate"
  if [ -x "$gate_path" ]; then
    bash "$gate_path" || exit 1
  fi
done

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

# 3b. Event-coupling audit (integration-vaporware defense).
# Runs only if the project defines npm run audit:events. Catches
# broken-wire bugs where producer and consumer typecheck independently
# but the string-keyed channel between them is broken (e.g., PATCH
# /api/appointments writes status='completed' but nothing fires the
# corresponding state-machine event). See scripts/audit-event-coupling.ts
# in the project for the specific checks.
if grep -q '"audit:events"' package.json 2>/dev/null; then
  echo "[3b/4] Auditing event-coupling..." >&2
  if ! npm run audit:events 2>&1 | tail -20 >&2; then
    echo "" >&2
    echo "✗ BLOCKED: Event-coupling audit found broken wires." >&2
    echo "  Either fix the orphan emit/consumer, or if it's intentionally" >&2
    echo "  legacy / externally-fired, add to NON_EVENT_PREFIXES or" >&2
    echo "  knownExternal allowlist in scripts/audit-event-coupling.ts" >&2
    echo "  with a comment explaining why." >&2
    exit 1
  fi
  echo "✓ Event coupling passed" >&2
fi

# 3c. Connectivity audit (Knip) — orphan files / unreachable exports.
# Runs only if the project defines npm run audit:connectivity:files-only.
# Catches files that exist and typecheck but are never imported by any
# entry point. Complement to the event-coupling audit: connectivity
# covers dead code at the import-graph level; event-coupling covers
# dead code at the string-keyed-channel level.
if grep -q '"audit:connectivity:files-only"' package.json 2>/dev/null; then
  echo "[3c/4] Auditing connectivity (Knip)..." >&2
  if ! npm run audit:connectivity:files-only 2>&1 | tail -30 >&2; then
    echo "" >&2
    echo "✗ BLOCKED: Knip found unused files." >&2
    echo "  Either delete the file, wire it into a real entry point, or" >&2
    echo "  add it to knip.config.ts 'ignore' list with a comment" >&2
    echo "  explaining why it's intentionally unreferenced (e.g., backlog" >&2
    echo "  partial-implementation flag, manual-run tool)." >&2
    exit 1
  fi
  echo "✓ Connectivity passed" >&2
fi

echo "" >&2
echo "═══ ALL PRE-COMMIT CHECKS PASSED ═══" >&2
echo "" >&2
