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

# Gate Philosophy Law retrofit (R3.4, harness-execution-redesign-2026-08
# Task 2): structured block-message fields + a --check pre-flight mode, both
# reached through the SAME per-site block function so the two can never
# disagree. See adapters/claude-code/hooks/lib/gate-contract-lib.sh.
_PCG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/gate-contract-lib.sh
source "$_PCG_SELF_DIR/lib/gate-contract-lib.sh" 2>/dev/null || true
# Freeze the script's own argv[1] into a plain (non-positional) variable
# BEFORE any function call. _pcg_block below is a FUNCTION; once execution
# is inside it, bash's "$1" refers to THAT function's own first argument
# (the block's "what" text), not the script's argv — a dynamic-scoping trap
# that silently broke the --self-test/--check exemption below the moment
# the block path moved from inline top-level code into a shared function.
_PCG_ARGV1="${1:-}"
GC_MODE="$(gc_mode "$_PCG_ARGV1" 2>/dev/null || echo enforce)"

# NL-FINDING-016 (compound-command gate trap): if this gate blocks (any
# non-zero, non-self-test, non-check exit), print the banner explaining that
# the ENTIRE Bash call — including any fix/edit/git-add prefix before the
# git commit — never ran. A trap on EXIT covers every block path in this
# file uniformly. --check is exempted too: it never gates a real command, so
# the "nothing was executed" framing would be misleading noise there. Reads
# the FROZEN _PCG_ARGV1 (see above), not "$1" — a trap fired from inside
# _pcg_block would otherwise see that function's own positional parameters.
_pcg_finding016_trap() {
  local rc=$?
  if [[ "$rc" -ne 0 ]] && [[ "${1:-}" != "--self-test" ]] && [[ "${1:-}" != "--check" ]]; then
    echo "" >&2
    echo "NOTE: this block prevented the ENTIRE command from running — including any" >&2
    echo "fix/edit/git add prefix before the git commit. Nothing was executed. Re-run" >&2
    echo "the non-commit part as its own call first, then commit separately." >&2
  fi
}
trap '_pcg_finding016_trap "$_PCG_ARGV1"' EXIT

# _pcg_block <what> <why> <fix> <escape> — the ONE per-site block emitter.
# Prints "✗ BLOCKED: <what>." (unchanged wording contract every existing
# call site already used) plus the four structured [GATE:*] fields, then
# exits via gc_exit_code so --check reports would-block (1) while enforce
# keeps its pre-existing exit code (1) byte-for-byte.
_pcg_block() {
  local what="$1" why="$2" fix="$3" escape="$4"
  local prefix
  prefix="$(gc_header "✗ BLOCKED" "$GC_MODE")"
  echo "" >&2
  echo "${prefix}: ${what}." >&2
  gc_block "$what" "$why" "$fix" "$escape" >&2
  echo "This gate: ~/.claude/hooks/pre-commit-gate.sh (source: adapters/claude-code/hooks/pre-commit-gate.sh)" >&2
  exit "$(gc_exit_code "$GC_MODE" 1)"
}

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

  # --- Gate Philosophy Law scenarios: exercise the real _pcg_block decision
  # site (unit-tests check) end-to-end via a subprocess re-invocation of this
  # script, both in enforce mode and --check mode, and assert the two carry
  # IDENTICAL structured fields (the "one shared decision, no drift"
  # guarantee) while differing only in exit code / header framing. A fake,
  # empty HOME makes the FRESHNESS_GATES/TDD-gate/plan-reviewer chain no-op
  # ([ -x "$gate_path" ] is false for all of them), isolating the test to
  # this file's own unit-tests block — the external gates it delegates to
  # are separate files with their own self-tests, not this scenario's job.
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  FAKE_HOME="$ST_TMP/fakehome"
  mkdir -p "$FAKE_HOME"
  mkdir -p "$ST_TMP/s7"
  printf '{"scripts":{"test":"exit 1"}}' > "$ST_TMP/s7/package.json"

  S7_ENFORCE_OUT="$ST_TMP/s7-enforce.txt"
  S7_ENFORCE_RC=0
  ( cd "$ST_TMP/s7" && HOME="$FAKE_HOME" bash "$SELF_TEST_HOOK" >/dev/null 2>"$S7_ENFORCE_OUT" ) || S7_ENFORCE_RC=$?
  S7_ENFORCE_ERR=$(cat "$S7_ENFORCE_OUT" 2>/dev/null || echo "")
  S7_ENFORCE_OK=0
  if [[ "$S7_ENFORCE_RC" == "1" ]] \
     && [[ "$S7_ENFORCE_ERR" == *"✗ BLOCKED: Unit tests failed"* ]] \
     && [[ "$S7_ENFORCE_ERR" == *"[GATE:WHAT] Unit tests failed"* ]] \
     && [[ "$S7_ENFORCE_ERR" == *"[GATE:WHY]"* ]] \
     && [[ "$S7_ENFORCE_ERR" == *"[GATE:FIX] run 'npm test'"* ]] \
     && [[ "$S7_ENFORCE_ERR" == *"[GATE:ESCAPE]"* ]] \
     && [[ "$S7_ENFORCE_ERR" != *"WOULD BLOCK"* ]]; then
    S7_ENFORCE_OK=1
  fi
  _st_expect s7-enforce-unit-test-fail-blocks-with-fields "1" "$S7_ENFORCE_OK"

  S7_CHECK_OUT="$ST_TMP/s7-check.txt"
  S7_CHECK_RC=0
  ( cd "$ST_TMP/s7" && HOME="$FAKE_HOME" bash "$SELF_TEST_HOOK" --check >/dev/null 2>"$S7_CHECK_OUT" ) || S7_CHECK_RC=$?
  S7_CHECK_ERR=$(cat "$S7_CHECK_OUT" 2>/dev/null || echo "")
  S7_CHECK_OK=0
  if [[ "$S7_CHECK_RC" == "1" ]] \
     && [[ "$S7_CHECK_ERR" == *"WOULD BLOCK (--check pre-flight, not enforced)"* ]] \
     && [[ "$S7_CHECK_ERR" == *"[GATE:WHAT] Unit tests failed"* ]] \
     && [[ "$S7_CHECK_ERR" == *"[GATE:FIX] run 'npm test'"* ]]; then
    S7_CHECK_OK=1
  fi
  _st_expect s8-check-mode-would-block-same-fields "1" "$S7_CHECK_OK"

  # Clean fixture (no test/build scripts) — both modes pass silently (exit 0).
  mkdir -p "$ST_TMP/s8"
  S8_ENFORCE_RC=0
  ( cd "$ST_TMP/s8" && HOME="$FAKE_HOME" bash "$SELF_TEST_HOOK" >/dev/null 2>/dev/null ) || S8_ENFORCE_RC=$?
  S8_CHECK_RC=0
  ( cd "$ST_TMP/s8" && HOME="$FAKE_HOME" bash "$SELF_TEST_HOOK" --check >/dev/null 2>/dev/null ) || S8_CHECK_RC=$?
  S8_OK=0
  [[ "$S8_ENFORCE_RC" == "0" ]] && [[ "$S8_CHECK_RC" == "0" ]] && S8_OK=1
  _st_expect s9-clean-fixture-passes-both-modes "1" "$S8_OK"

  if [[ "$st_fails" -eq 0 ]]; then
    echo "ALL SELF-TESTS PASSED (11/11)" >&2
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
    _pcg_block \
      "TDD gate failed (invoked ~/.claude/hooks/pre-commit-tdd-gate.sh — see message above for missing tests)" \
      "anti-vaporware: new/modified runtime-feature files must ship with matching tests, or a merged feature silently has zero test coverage" \
      "add or extend a test file covering the new/changed runtime code (see the TDD gate's own message above for exactly which file), re-stage, and re-commit" \
      "none from this wrapper — the TDD gate itself may name a narrow allowlist path (config/fixture-only files); no generic bypass exists here"
  fi
  echo "✓ TDD gate passed" >&2
  echo "" >&2
fi

# 0b. Plan-reviewer — any staged docs/plans/*.md files must pass mechanical review
PLAN_REVIEWER="$HOME/.claude/hooks/plan-reviewer.sh"
if [[ -x "$PLAN_REVIEWER" ]]; then
  # Exclusion covers the whole evidence-file class: -evidence.md AND the
  # -evidence-t<N>.md / -evidence-<suffix>.md siblings (>=10 in-tree; the
  # fd48741 review proved the single-suffix exclusion was already
  # incomplete — plan-reviewer rejects these as malformed plans).
  STAGED_PLANS=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '^docs/plans/[^/]+\.md$' | grep -vE -- '-evidence(-[A-Za-z0-9_-]+)?\.md$' || true)
  if [[ -n "$STAGED_PLANS" ]]; then
    echo "[0b/5] Plan-reviewer adversarial check..." >&2
    while IFS= read -r plan; do
      [[ -z "$plan" ]] && continue
      if ! bash "$PLAN_REVIEWER" "$plan" >&2; then
        _pcg_block \
          "plan-reviewer rejected $plan (invoked ~/.claude/hooks/plan-reviewer.sh)" \
          "a plan that fails mechanical review (missing required sections, malformed header, etc.) is not a reliable contract for the build/verification work downstream" \
          "fix the specific defect plan-reviewer printed above for $plan, re-stage, and re-commit" \
          "none — plan-reviewer has no bypass flag; fix the named defect"
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
    _pcg_block \
      "Unit tests failed. Fix tests before committing" \
      "a commit that ships failing tests breaks the pre-existing oracle for every consumer of this code" \
      "run 'npm test' locally, fix the failing test(s) or the code they cover, re-stage, and re-commit" \
      "none from this gate — fix the failing test(s); an intentionally-updated fixture still must pass green before commit"
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
    _pcg_block \
      "Build ($BUILD_SCRIPT) failed. Fix build errors before committing" \
      "a commit that doesn't build breaks every consumer who pulls it, and CI will reject it anyway — catching it locally is cheaper" \
      "run 'npm run $BUILD_SCRIPT' locally, fix the build error(s), re-stage, and re-commit" \
      "none from this gate — a DB-touching failure specifically may mean the project needs a build:gate script (see the note at the top of this file); that is a project config change, not a bypass"
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
    _pcg_block \
      "API route changed with unstaged consumers" \
      "shipping a changed API contract without its consumers staged in the same commit produces a broken-wire bug the moment this lands" \
      "stage the consumer file(s) audit-api-consumers.sh named above, or verify and document backward compatibility, re-stage, and re-commit" \
      "none from this gate — stage the consumers or restore backward compatibility"
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
    _pcg_block \
      "Event-coupling audit found broken wires" \
      "a string-keyed event channel can typecheck on both ends while the wire between them is actually broken — this is the class check for that" \
      "fix the orphan emit/consumer named above" \
      "add it to NON_EVENT_PREFIXES or the knownExternal allowlist in scripts/audit-event-coupling.ts with a comment explaining why (cost: a permanent, reviewable exception in tracked source, not a bypass flag) if it is intentionally legacy/externally-fired"
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
    _pcg_block \
      "Knip found unused files" \
      "a file that typechecks but is never imported by any entry point is dead weight that erodes the signal that 'this code does something'" \
      "delete the file(s) named above, or wire them into a real entry point" \
      "add it to knip.config.ts 'ignore' list with a comment explaining why it is intentionally unreferenced, e.g. a backlog partial-implementation flag or a manual-run tool (cost: a permanent, reviewable exception, not a bypass flag)"
  fi
  echo "✓ Connectivity passed" >&2
fi

echo "" >&2
echo "═══ ALL PRE-COMMIT CHECKS PASSED ═══" >&2
echo "" >&2
