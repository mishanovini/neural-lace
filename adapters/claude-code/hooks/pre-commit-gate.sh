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
#   3. Unit tests pass (npm test — skipped if the project has no "test" script)
#   4. Build succeeds (npm run build:gate if declared, else npm run build —
#      skipped if neither script exists; see the build-script-selection note below)
#   5. API consumer audit (no unstaged consumers of changed API routes)

set -eo pipefail

# NL-FINDING-016 (compound-command gate trap): if this gate blocks (any
# non-zero, non-self-test exit), print the banner explaining that the ENTIRE
# Bash call — including any fix/edit/git-add prefix before the git commit —
# never ran. A trap on EXIT covers every block path in this file uniformly.
_pcg_finding016_trap() {
  local rc=$?
  if [[ "$rc" -ne 0 ]] && [[ "${1:-}" != "--self-test" ]]; then
    echo "" >&2
    echo "NOTE: this block prevented the ENTIRE command from running — including any" >&2
    echo "fix/edit/git add prefix before the git commit. Nothing was executed. Re-run" >&2
    echo "the non-commit part as its own call first, then commit separately." >&2
  fi
}
trap '_pcg_finding016_trap "$1"' EXIT

# --- Build-script selection (DB-free gate validation) ----------------------
# A project's pre-commit build can couple code-correctness validation with
# DB-touching steps (e.g. `prisma migrate`, or build-time data fetching that
# needs DATABASE_URL). In a worktree with no DB connection those steps fail and
# the gate false-fires on an ENVIRONMENTAL problem, not a code defect. To
# validate compilation without a DB, a project may declare a `build:gate` npm
# script (a DB-free build subset — typically `tsc --noEmit` / `next build`
# without the migrate/seed steps); this gate prefers it over `build`. The full
# `build` still runs in CI. When neither script exists (a non-npm repo, or the
# harness repo itself), the build step is SKIPPED rather than 127-failed — the
# same "run only if the project defines it" convention the audit steps below
# already use. This narrows false-firing without weakening signal: a project
# that defines a normal `build` (and no `build:gate`) gets the full build
# exactly as before.

# _has_npm_script <name> — 0 if package.json defines the named npm script.
_has_npm_script() {
  [ -f package.json ] || return 1
  jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null 2>&1
}

# _select_build_script — echo the build script the gate should run:
#   "build:gate" if declared (DB-free subset), else "build" if declared,
#   else "" (nothing buildable — skip).
_select_build_script() {
  if _has_npm_script "build:gate"; then
    echo "build:gate"
  elif _has_npm_script "build"; then
    echo "build"
  else
    echo ""
  fi
}

# --- Self-test (run only on explicit --self-test; no-op in the commit chain) -
if [[ "${1:-}" == "--self-test" ]]; then
  ST_TMP="$(mktemp -d)"
  trap 'rm -rf "$ST_TMP"' EXIT
  st_fails=0
  _st_expect() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test ($1): PASS" >&2
    else
      echo "self-test ($1): FAIL (expected '$2', got '$3')" >&2
      st_fails=$((st_fails + 1))
    fi
  }
  _st_select() { ( cd "$1" && _select_build_script ) 2>/dev/null || true; }
  _st_test_state() { if ( cd "$1" && _has_npm_script test ); then echo defined; else echo absent; fi; }

  mkdir -p "$ST_TMP/s1"; printf '{"scripts":{"build":"next build"}}' > "$ST_TMP/s1/package.json"
  _st_expect s1-only-build-selects-build "build" "$(_st_select "$ST_TMP/s1")"

  mkdir -p "$ST_TMP/s2"; printf '{"scripts":{"build":"next build","build:gate":"tsc --noEmit"}}' > "$ST_TMP/s2/package.json"
  _st_expect s2-gate-and-build-prefers-gate "build:gate" "$(_st_select "$ST_TMP/s2")"

  mkdir -p "$ST_TMP/s3"; printf '{"scripts":{"test":"vitest"}}' > "$ST_TMP/s3/package.json"
  _st_expect s3-neither-build-skips "" "$(_st_select "$ST_TMP/s3")"

  mkdir -p "$ST_TMP/s4"
  _st_expect s4-no-package-json-skips "" "$(_st_select "$ST_TMP/s4")"
  _st_expect s4-no-package-json-test-absent "absent" "$(_st_test_state "$ST_TMP/s4")"

  mkdir -p "$ST_TMP/s5"; printf '{"scripts":{"build:gate":"tsc --noEmit"}}' > "$ST_TMP/s5/package.json"
  _st_expect s5-gate-only-selects-gate "build:gate" "$(_st_select "$ST_TMP/s5")"

  _st_expect s6-test-absent-when-no-test-script "absent" "$(_st_test_state "$ST_TMP/s1")"
  _st_expect s6b-test-present-when-declared "defined" "$(_st_test_state "$ST_TMP/s3")"

  if [[ "$st_fails" -eq 0 ]]; then
    echo "ALL SELF-TESTS PASSED (8/8)" >&2
    exit 0
  fi
  echo "$st_fails SELF-TEST(S) FAILED" >&2
  exit 1
fi

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
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh) invoked ~/.claude/hooks/pre-commit-tdd-gate.sh" >&2
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
        echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh) invoked ~/.claude/hooks/plan-reviewer.sh" >&2
        exit 1
      fi
    done <<< "$STAGED_PLANS"
    echo "✓ Plan-reviewer passed" >&2
    echo "" >&2
  fi
fi

# 1. Unit tests (run only if the project defines a "test" script — a non-npm
#    repo or one without tests is skipped rather than 127-failed).
if _has_npm_script test; then
  echo "[1/4] Running unit tests..." >&2
  if ! npm test 2>&1 | tail -3 >&2; then
    echo "" >&2
    echo "✗ BLOCKED: Unit tests failed. Fix tests before committing." >&2
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
    exit 1
  fi
  echo "✓ Tests passed" >&2
else
  echo "[1/4] No \"test\" script defined — skipping unit tests." >&2
fi
echo "" >&2

# 2. Build — prefer a DB-free `build:gate` subset when the project declares one
#    (see the build-script-selection note at the top of this file). Skip when
#    neither `build:gate` nor `build` exists, instead of 127-failing on a
#    non-npm repo.
BUILD_SCRIPT="$(_select_build_script)"
if [ -n "$BUILD_SCRIPT" ]; then
  echo "[2/4] Running build ($BUILD_SCRIPT)..." >&2
  if ! npm run "$BUILD_SCRIPT" 2>&1 | tail -5 >&2; then
    echo "" >&2
    echo "✗ BLOCKED: Build ($BUILD_SCRIPT) failed. Fix build errors before committing." >&2
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
    exit 1
  fi
  echo "✓ Build passed ($BUILD_SCRIPT)" >&2
else
  echo "[2/4] No \"build\" or \"build:gate\" script defined — skipping build." >&2
fi
echo "" >&2

# 3. API consumer audit
echo "[3/4] Auditing API consumers..." >&2
if [ -f "scripts/audit-api-consumers.sh" ]; then
  if ! bash scripts/audit-api-consumers.sh 2>&2; then
    echo "" >&2
    echo "✗ BLOCKED: API route changed with unstaged consumers." >&2
    echo "  Stage the consumer files or verify backward compatibility." >&2
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
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
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
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
    echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
    exit 1
  fi
  echo "✓ Connectivity passed" >&2
fi

echo "" >&2
echo "═══ ALL PRE-COMMIT CHECKS PASSED ═══" >&2
echo "" >&2
