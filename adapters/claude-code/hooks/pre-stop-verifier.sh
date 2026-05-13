#!/bin/bash
# pre-stop-verifier.sh
#
# Stop hook that verifies plan integrity before allowing session termination.
#
# Replaces the old stop_guard.sh with evidence-aware checks:
#
#   1. Existing stop_guard behavior: blocks if the active plan has unchecked
#      tasks and its status is not ABANDONED/DEFERRED/COMPLETED
#
#   2. NEW: For every checked task in the active plan, verify there is a
#      matching evidence block in the plan's Evidence Log section
#
#   3. NEW: Flag missing or malformed evidence blocks as blocking issues
#
#   4. NEW: Log plan integrity issues with enough detail for the builder
#      to fix them
#
# NOTE: The semantic reasoning verification (invoking the plan-evidence-reviewer
# subagent per checked task) is designed to run inside the Claude Code session
# itself via Task tool, not from this shell hook. This hook handles the
# mechanical checks that don't require Claude reasoning. The builder is
# expected to have invoked plan-evidence-reviewer (or task-verifier) as part
# of completing each task — this hook is the backstop that catches cases where
# they didn't.
#
# Exit codes:
#   0 — session may terminate
#   1 — session is blocked; error printed to stderr and JSON to stdout

# ============================================================
# --self-test: exercise Check 5 (M1) and the A2 extension against
# three synthetic plan fixtures
# ============================================================
#
# Three fixtures live under tests/dod-artifact-gate/:
#
#   fixture-plan-completed-artifact-missing.md
#       Status: COMPLETED, all DoD `[x]`, declares a `## DoD Artifacts`
#       section with an artifact that does NOT exist on disk → BLOCK.
#   fixture-plan-completed-artifact-present.md
#       Same shape, but the declared artifact exists on disk with the
#       required content → ALLOW.
#   fixture-plan-no-artifacts-section.md
#       Status: COMPLETED, all DoD `[x]`, NO `## DoD Artifacts` section
#       → ALLOW (A2 is a no-op when the section is absent).
#
# The fixtures are ALSO acceptance-exempt and have all task checkboxes
# checked + an evidence block, so the only check that exercises them
# is Check 5 (and its A2 extension).

if [[ "${1:-}" == "--self-test" ]]; then
  SCRIPT="${BASH_SOURCE[0]}"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
  FIXTURE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/tests/dod-artifact-gate"

  if [[ ! -d "$FIXTURE_DIR" ]]; then
    echo "self-test: fixture dir missing at $FIXTURE_DIR" >&2
    exit 2
  fi

  FAILED=0

  run_case() {
    local name="$1" expected_exit="$2" fixture="$3"
    if [[ ! -f "$fixture" ]]; then
      echo "FAIL  $name (fixture missing: $fixture)"
      FAILED=$((FAILED+1))
      return
    fi
    local exit_code=0
    PRE_STOP_VERIFIER_FIXTURE_PLAN="$fixture" \
      bash "$SCRIPT" < /dev/null > /dev/null 2>&1 || exit_code=$?
    if [[ "$exit_code" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $exit_code)"
    else
      echo "FAIL  $name (expected exit $expected_exit, got $exit_code)"
      FAILED=$((FAILED+1))
    fi
  }

  # The "missing" fixture declares an artifact that does not exist → BLOCK (1).
  run_case "completed-artifact-missing-blocks"  1 "$FIXTURE_DIR/fixture-plan-completed-artifact-missing.md"
  # The "present" fixture's artifact resolves and matches → ALLOW (0).
  run_case "completed-artifact-present-allows"  0 "$FIXTURE_DIR/fixture-plan-completed-artifact-present.md"
  # The "no section" fixture lacks `## DoD Artifacts` → A2 is a no-op → ALLOW (0).
  run_case "completed-no-artifacts-section-allows" 0 "$FIXTURE_DIR/fixture-plan-no-artifacts-section.md"

  echo ""
  if [[ "$FAILED" -gt 0 ]]; then
    echo "Result: FAIL ($FAILED failed)"
    exit 1
  fi
  echo "Result: PASS (3/3)"
  exit 0
fi

# Shared retry-guard library — see lib/stop-hook-retry-guard.sh.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

# Read stdin to derive session_id; we don't otherwise consume INPUT.
PSV_INPUT=""
if [[ ! -t 0 ]]; then
  PSV_INPUT=$(cat 2>/dev/null || echo "")
fi
RG_SESSION_ID=$(retry_guard_session_id "$PSV_INPUT")

# Wrapper: each Check's block path calls this with a unique check label
# and a per-check signature snippet. The retry-guard library decides
# block-vs-downgrade. Function never returns.
#
# Args:
#   $1 = check label (e.g., "check1-pending"). Combined with $2 to form
#        the failure signature so different checks have different sigs.
#   $2 = signature data (e.g., "${PENDING}:${LATEST_PLAN}").
#   $3 = one-line error message used in the unresolved-stop-hooks log.
#   $4 = JSON envelope to stdout on block.
_pre_stop_block() {
  local check="$1"
  local sig="$2"
  local err_msg="$3"
  local block_json="$4"
  retry_guard_block_or_exit \
    "pre-stop-verifier" \
    "$RG_SESSION_ID" \
    "pre-stop:${check}:${sig}" \
    "$err_msg" \
    "$block_json" \
    1
}

# Plan directories: look in both the top-level docs/plans/ and any
# subproject's docs/plans/. Previously this hook hardcoded
# PLAN_DIR="docs/plans" which silently no-op'd for any project whose
# plan directory lived under a subdirectory.
#
# We discover plan directories dynamically: any directory matching
# (**/)?docs/plans/ within the current working directory (up to 3 levels
# deep) is scanned for the most recently modified plan file.

PLAN_DIRS=()
# Top-level
[[ -d "docs/plans" ]] && PLAN_DIRS+=("docs/plans")
# One level deep (e.g., platform/docs/plans)
for subdir in */docs/plans; do
  [[ -d "$subdir" ]] && PLAN_DIRS+=("$subdir")
done
# Two levels deep (e.g., apps/web/docs/plans)
for subdir in */*/docs/plans; do
  [[ -d "$subdir" ]] && PLAN_DIRS+=("$subdir")
done

# ============================================================
# Pre-check (non-blocking): uncommitted plan files
# ============================================================
#
# Warn — do NOT block — when the session is about to end with
# uncommitted plan files. Uncommitted plans are vulnerable to being
# wiped by a concurrent session's git operations, and they won't
# survive into future sessions if the working tree is reset.
#
# This runs BEFORE any of the exit conditions below so it surfaces
# regardless of plan state. It never affects the exit code.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  UNCOMMITTED_PLANS=""
  for dir in "${PLAN_DIRS[@]}"; do
    # `git status --porcelain` lists modified, added, untracked files.
    # We want any line whose path is under a plan directory (top-level
    # only — we don't warn about archived files since archival is
    # itself a staged rename that the session is expected to commit).
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # porcelain v1: first 2 chars are status, then space, then path
      # (rename lines look like "R  old -> new"; we still want the new path).
      path="${line:3}"
      # Strip rename arrow if present — keep destination path.
      case "$path" in
        *' -> '*) path="${path##* -> }" ;;
      esac
      # Only warn for top-level plan files (NOT archive subdirectory).
      # Bash's case glob `*` matches across `/`, so we have to check
      # that the suffix after `$dir/` contains no `/` before `.md`.
      suffix="${path#"$dir"/}"
      case "$path" in
        "$dir"/*.md)
          case "$suffix" in
            */*) ;;  # has another `/` → in a subdirectory (e.g. archive/)
            *) UNCOMMITTED_PLANS+="${path}"$'\n' ;;
          esac
          ;;
      esac
    done < <(git status --porcelain --untracked-files=all -- "$dir" 2>/dev/null)
  done

  if [[ -n "$UNCOMMITTED_PLANS" ]]; then
    echo "" >&2
    echo "================================================================" >&2
    echo "[uncommitted-plans-warn] PLAN FILES NOT COMMITTED" >&2
    echo "================================================================" >&2
    echo "The following plan files have uncommitted changes:" >&2
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      echo "  - $p" >&2
    done <<< "$UNCOMMITTED_PLANS"
    echo "" >&2
    echo "Uncommitted plan files can be wiped by concurrent sessions and" >&2
    echo "will not survive into future sessions if the working tree is" >&2
    echo "reset. Commit them before ending the session:" >&2
    echo "" >&2
    echo "  git add docs/plans/<slug>.md && git commit -m 'plan: <slug>'" >&2
    echo "" >&2
    echo "(This is a warning, not a block — session exit is not prevented.)" >&2
    echo "" >&2
  fi
fi

# Self-test override: allow `--self-test` (above) to point this hook at a
# specific plan file, bypassing normal plan-directory discovery. Production
# invocations never set this env var.
if [[ -n "${PRE_STOP_VERIFIER_FIXTURE_PLAN:-}" ]]; then
  if [[ ! -f "$PRE_STOP_VERIFIER_FIXTURE_PLAN" ]]; then
    echo "PRE_STOP_VERIFIER_FIXTURE_PLAN points at non-existent file: $PRE_STOP_VERIFIER_FIXTURE_PLAN" >&2
    exit 2
  fi
  LATEST_PLAN="$PRE_STOP_VERIFIER_FIXTURE_PLAN"
elif [[ ${#PLAN_DIRS[@]} -eq 0 ]]; then
  exit 0
else
  # Find the most recently modified plan across all discovered dirs
  LATEST_PLAN=""
  LATEST_MTIME=0
  for dir in "${PLAN_DIRS[@]}"; do
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      # Skip evidence files
      [[ "$f" == *-evidence.md ]] && continue
      mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      if [[ "$mtime" -gt "$LATEST_MTIME" ]]; then
        LATEST_MTIME="$mtime"
        LATEST_PLAN="$f"
      fi
    done
  done

  if [[ -z "$LATEST_PLAN" ]]; then
    exit 0
  fi

  # Prefer any ACTIVE plan over the most-recently-modified one. An active
  # plan in a subproject should win over a completed plan in the top level.
  for dir in "${PLAN_DIRS[@]}"; do
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$f" == *-evidence.md ]] && continue
      if grep -qiE '^Status:\s*ACTIVE' "$f" 2>/dev/null; then
        LATEST_PLAN="$f"
        break 2
      fi
    done
  done
fi

# Companion evidence file (new location for evidence blocks)
# Falls back gracefully — if it doesn't exist, checks below look at the plan file instead
EVIDENCE_FILE="${LATEST_PLAN%.md}-evidence.md"

# Plan status: determine which gate applies.
#   ABANDONED / DEFERRED — allow termination, skip all further checks.
#   COMPLETED — must verify that every task is actually complete
#     (checked + has evidence block). Previously this branch exited 0
#     immediately, which was a loophole: marking a plan COMPLETED let
#     you skip every task-verifier check even when no tasks were checked.
#     Now COMPLETED is the STRICTEST state: 100% of tasks must be
#     checked + verified before the session can end.
#   ACTIVE (or unspecified) — the original stop_guard behavior:
#     block if any task is unchecked.

if grep -qiE '^Status:\s*(ABANDONED|DEFERRED)' "$LATEST_PLAN" 2>/dev/null; then
  exit 0
fi

IS_COMPLETED=0
if grep -qiE '^Status:\s*COMPLETED' "$LATEST_PLAN" 2>/dev/null; then
  IS_COMPLETED=1
fi

# ============================================================
# Check 0: acceptance-loop awareness (Phase A.4 walking skeleton — Generation 5)
# ============================================================
#
# This is the Phase 1 walking-skeleton extension for the end-user-advocate
# acceptance loop (see docs/plans/end-user-advocate-acceptance-loop.md).
# At this stage the hook only RECOGNIZES the new plan-header field
# `acceptance-exempt: true` and LOGS whether a PASS artifact exists for
# non-exempt active plans. It does NOT yet block on missing artifacts —
# the full blocking gate is Phase D's standalone product-acceptance-gate.sh
# chained after this script. We add the recognition path now so the
# walking-skeleton smoke test (`docs/plans/acceptance-loop-smoke-test.md`,
# itself acceptance-exempt) can demonstrate that the control flow reaches
# this hook, sees the exemption, and exits cleanly.
#
# Two cases:
#   (a) Plan declares `acceptance-exempt: true` → log + skip (no further
#       acceptance check). Used by harness-dev plans and the bootstrap
#       skeleton plan that IS the loop.
#   (b) Plan does NOT declare exemption → look for a JSON artifact under
#       .claude/state/acceptance/<plan-slug>/ and log presence. NO blocking
#       at this skeleton stage; production blocking is Phase D.

PLAN_SLUG=$(basename "$LATEST_PLAN" .md)
ACCEPTANCE_DIR=".claude/state/acceptance/${PLAN_SLUG}"

if grep -qiE '^acceptance-exempt:\s*true' "$LATEST_PLAN" 2>/dev/null; then
  EXEMPT_REASON=$(grep -iE '^acceptance-exempt-reason:' "$LATEST_PLAN" 2>/dev/null | head -1 | sed 's/^[Aa]cceptance-exempt-reason:[[:space:]]*//')
  echo "[acceptance-gate] plan ${PLAN_SLUG} is acceptance-exempt; reason: ${EXEMPT_REASON:-<none provided>}" >&2
  # Note: production gate (Phase D.6) will BLOCK if exempt: true but no
  # reason. For the skeleton we just log.
elif [[ -d "$ACCEPTANCE_DIR" ]]; then
  ARTIFACT_COUNT=$(find "$ACCEPTANCE_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d '[:space:]')
  echo "[acceptance-gate] plan ${PLAN_SLUG}: ${ARTIFACT_COUNT} artifact(s) under ${ACCEPTANCE_DIR} (skeleton recognition only — production gate is Phase D)" >&2
else
  echo "[acceptance-gate] plan ${PLAN_SLUG}: no acceptance directory at ${ACCEPTANCE_DIR} (skeleton recognition only — production gate is Phase D)" >&2
fi

# ============================================================
# Check 1: unchecked tasks
# ============================================================
#
# For ACTIVE plans: blocks if ANY task is unchecked.
# For COMPLETED plans: blocks if ANY task is unchecked (stricter — a plan
# cannot legitimately be marked COMPLETED while tasks remain unchecked).

PENDING=$(grep -c '^- \[ \]' "$LATEST_PLAN" 2>/dev/null || echo "0")
# Strip whitespace (grep may emit leading spaces in some environments)
PENDING=$(echo "$PENDING" | tr -d '[:space:]')

if [[ "$PENDING" -gt 0 ]]; then
  if [[ "$IS_COMPLETED" -eq 1 ]]; then
    BLOCKER_MSG="Plan has Status: COMPLETED but $PENDING tasks are still unchecked in $LATEST_PLAN. A plan cannot be marked COMPLETED while any task remains unchecked. Either (a) actually build and verify those tasks, (b) set Status: ACTIVE to continue working on them, or (c) set Status: ABANDONED with a reason if they're being dropped."
  else
    BLOCKER_MSG="Cannot finish: $PENDING incomplete tasks remain in $LATEST_PLAN. Complete all tasks, or set 'Status: ABANDONED' in the plan file to stop early."
  fi
  echo "" >&2
  echo "================================================================" >&2
  echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
  echo "================================================================" >&2
  echo "$BLOCKER_MSG" >&2
  echo "" >&2
  _pre_stop_block "check1-pending" "${PENDING}:${LATEST_PLAN}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
fi

# ============================================================
# Check 2: every checked task has an evidence block
# ============================================================
#
# The plan format requires that:
#  - Tasks are marked with "- [x] T.N <description>" lines where T.N is a
#    task ID like "A.1" or "C.0.5.3"
#  - Each checked task must have a corresponding evidence block in the
#    ## Evidence Log section at the bottom of the file
#  - The evidence block must include the line "Task ID: T.N" matching
#    the checked task

# Extract all checked task IDs (format: "- [x] T.N ..." where T.N has
# letters-digits-dots)
# We look for a checkbox followed by an identifier pattern.
CHECKED_IDS=$(grep -oE '^- \[x\] [A-Z]+\.[0-9]+(\.[0-9]+)*' "$LATEST_PLAN" 2>/dev/null | sed 's/^- \[x\] //' | sort -u)

if [[ -z "$CHECKED_IDS" ]]; then
  # No checked tasks at all — nothing to verify. Also shouldn't be hit because
  # the previous check would have blocked on unchecked tasks, but handle it
  # defensively.
  exit 0
fi

# Confirm evidence exists somewhere: either in the companion evidence file
# (new location) or in an ## Evidence Log section in the plan file (old location).
# Both are acceptable for backward compatibility.
HAS_EVIDENCE_FILE=0
HAS_EVIDENCE_SECTION=0
[[ -f "$EVIDENCE_FILE" ]] && HAS_EVIDENCE_FILE=1
grep -q '^## Evidence Log' "$LATEST_PLAN" 2>/dev/null && HAS_EVIDENCE_SECTION=1

if [[ "$HAS_EVIDENCE_FILE" -eq 0 && "$HAS_EVIDENCE_SECTION" -eq 0 ]]; then
  BLOCKER_MSG="Plan has checked tasks but no evidence found. Expected companion file ${EVIDENCE_FILE} or an ## Evidence Log section in the plan file. Run the task-verifier agent on each task to generate evidence."
  echo "" >&2
  echo "================================================================" >&2
  echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
  echo "================================================================" >&2
  echo "$BLOCKER_MSG" >&2
  echo "" >&2
  echo "Checked tasks without evidence:" >&2
  while IFS= read -r id; do
    echo "  - $id" >&2
  done <<< "$CHECKED_IDS"
  echo "" >&2
  _pre_stop_block "check2-no-evidence" "${LATEST_PLAN}:${CHECKED_IDS}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
fi

# For each checked ID, verify an evidence block exists that references it.
# Check companion evidence file first (new), then plan file (old/fallback).
MISSING_EVIDENCE=""
MISSING_COUNT=0

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  # Look for "Task ID: <id>" in the companion file OR the plan file
  FOUND=0
  if [[ "$HAS_EVIDENCE_FILE" -eq 1 ]] && grep -qE "^Task ID:[[:space:]]*$id([[:space:]]|$)" "$EVIDENCE_FILE" 2>/dev/null; then
    FOUND=1
  fi
  if [[ "$FOUND" -eq 0 ]] && grep -qE "^Task ID:[[:space:]]*$id([[:space:]]|$)" "$LATEST_PLAN" 2>/dev/null; then
    FOUND=1
  fi
  if [[ "$FOUND" -eq 0 ]]; then
    MISSING_EVIDENCE+="  - $id"$'\n'
    MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
done <<< "$CHECKED_IDS"

if [[ "$MISSING_COUNT" -gt 0 ]]; then
  BLOCKER_MSG="Plan has $MISSING_COUNT checked task(s) without matching evidence blocks. Every completed task must be verified by the task-verifier agent, which generates an evidence block. Self-checking boxes without verification is not allowed."
  echo "" >&2
  echo "================================================================" >&2
  echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
  echo "================================================================" >&2
  echo "$BLOCKER_MSG" >&2
  echo "" >&2
  echo "Tasks missing evidence blocks:" >&2
  echo "$MISSING_EVIDENCE" >&2
  echo "" >&2
  echo "To resolve:" >&2
  echo "  1. Invoke the task-verifier agent for each missing task" >&2
  echo "  2. It will produce an evidence block and append it to ${EVIDENCE_FILE}" >&2
  echo "  3. If a task was checked by mistake, uncheck it manually" >&2
  echo "" >&2
  _pre_stop_block "check2-missing-task-evidence" "${LATEST_PLAN}:${MISSING_EVIDENCE}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
fi

# ============================================================
# Check 3: evidence block structural sanity
# ============================================================
#
# Verify each evidence block has the required fields: Task ID, Verified at, Verdict.
# Read from companion evidence file if it exists; otherwise fall back to the
# ## Evidence Log section in the plan file (backward compatibility).

if [[ "$HAS_EVIDENCE_FILE" -eq 1 ]]; then
  EVIDENCE_SECTION=$(cat "$EVIDENCE_FILE")
else
  EVIDENCE_LOG_START=$(grep -n '^## Evidence Log' "$LATEST_PLAN" | head -1 | cut -d: -f1)
  EVIDENCE_SECTION=$(tail -n +"$EVIDENCE_LOG_START" "$LATEST_PLAN")
fi

if [[ -n "$EVIDENCE_SECTION" ]]; then

  # Count how many "EVIDENCE BLOCK" markers there are
  BLOCK_COUNT=$(echo "$EVIDENCE_SECTION" | grep -c '^EVIDENCE BLOCK' || echo "0")
  BLOCK_COUNT=$(echo "$BLOCK_COUNT" | tr -d '[:space:]')

  # Count how many "Task ID:" lines there are
  ID_COUNT=$(echo "$EVIDENCE_SECTION" | grep -c '^Task ID:' || echo "0")
  ID_COUNT=$(echo "$ID_COUNT" | tr -d '[:space:]')

  # Count how many "Verdict:" lines there are
  VERDICT_COUNT=$(echo "$EVIDENCE_SECTION" | grep -c '^Verdict:' || echo "0")
  VERDICT_COUNT=$(echo "$VERDICT_COUNT" | tr -d '[:space:]')

  if [[ "$BLOCK_COUNT" -ne "$ID_COUNT" ]] || [[ "$BLOCK_COUNT" -ne "$VERDICT_COUNT" ]]; then
    BLOCKER_MSG="Evidence Log has malformed blocks. Found $BLOCK_COUNT block markers, $ID_COUNT Task ID lines, $VERDICT_COUNT Verdict lines. These counts should match."
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "To resolve: re-generate malformed evidence blocks by re-invoking" >&2
    echo "the task-verifier agent on affected tasks." >&2
    echo "" >&2
    _pre_stop_block "check3-malformed-evidence" "${LATEST_PLAN}:${BLOCK_COUNT}:${ID_COUNT}:${VERDICT_COUNT}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  fi

  # Ensure every evidence block has a PASS verdict (failures shouldn't be
  # left in the plan as evidence of completion)
  FAIL_VERDICTS=$(echo "$EVIDENCE_SECTION" | grep -cE '^Verdict:[[:space:]]*(FAIL|INCOMPLETE)' || echo "0")
  FAIL_VERDICTS=$(echo "$FAIL_VERDICTS" | tr -d '[:space:]')

  if [[ "$FAIL_VERDICTS" -gt 0 ]]; then
    BLOCKER_MSG="Evidence Log contains $FAIL_VERDICTS FAIL or INCOMPLETE verdict(s). Tasks with failing evidence should not be checked. Either resolve the issues and re-verify, or remove the failing evidence blocks and uncheck the tasks."
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    _pre_stop_block "check3-fail-verdicts" "${LATEST_PLAN}:${FAIL_VERDICTS}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  fi
fi

# ============================================================
# Check 4: Anti-vaporware — runtime verification for runtime features
# (Generation 4: replayable commands, not keyword scans)
# ============================================================
#
# See ~/.claude/rules/vaporware-prevention.md for rationale.
#
# The check now has two sub-layers:
#   4a. For plans with runtime-feature tasks, REQUIRE at least one
#       "Runtime verification:" line in the evidence. Blocks shipping
#       runtime features with zero verification entries.
#   4b. Call runtime-verification-executor.sh to EXECUTE each verification
#       entry. Fake strings like "manual test done" are rejected because
#       the executor can't parse them. Real commands (test/playwright/
#       curl/sql/file) are executed and must succeed.
#
# This replaces the previous keyword-only scan, which could be walked
# around by writing a single fake "Runtime verification: done" line.

RUNTIME_KEYWORDS='(page|route|button|form|component|UI|webhook|cron|scheduled job|trigger|endpoint|API|migration|column|table|state transition|side effect|send message|notification)'

# Collect runtime tasks from the plan (checked tasks that match keywords)
RUNTIME_TASKS=$(grep -iE "^- \[x\] .*${RUNTIME_KEYWORDS}" "$LATEST_PLAN" 2>/dev/null || true)

if [[ -n "$RUNTIME_TASKS" ]] && [[ -n "$EVIDENCE_SECTION" ]]; then
  # 4a: require at least one Runtime verification: entry
  RUNTIME_VERIF_COUNT=$(echo "$EVIDENCE_SECTION" | grep -cE '^Runtime verification:' || echo "0")
  RUNTIME_VERIF_COUNT=$(echo "$RUNTIME_VERIF_COUNT" | tr -d '[:space:]')

  if [[ "$RUNTIME_VERIF_COUNT" -eq 0 ]] && [[ "$BLOCK_COUNT" -gt 0 ]]; then
    BLOCKER_MSG="Plan contains runtime-feature tasks (UI/API/webhook/cron/migration), but the evidence log has ZERO 'Runtime verification:' entries. Runtime features must be verified at runtime, not just by static code inspection. Add a 'Runtime verification:' line to each evidence block."
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 4a — zero runtime verif)" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "Runtime tasks in this plan (first 10):" >&2
    echo "$RUNTIME_TASKS" | head -10 >&2
    echo "" >&2
    echo "To resolve: add a 'Runtime verification:' line in one of these formats:" >&2
    echo "  Runtime verification: test <file>::<test-name>" >&2
    echo "  Runtime verification: playwright <spec>::<test-name>" >&2
    echo "  Runtime verification: curl <full command>" >&2
    echo "  Runtime verification: sql <SELECT statement>" >&2
    echo "  Runtime verification: file <path>::<line-pattern>" >&2
    echo "" >&2
    _pre_stop_block "check4a-zero-runtime-verif" "${LATEST_PLAN}:${BLOCK_COUNT}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  fi

  # 4b: execute every runtime verification line via the executor
  # Write evidence to a temp file so the executor can read it
  EXEC_TMP=$(mktemp 2>/dev/null || echo "/tmp/rve-tmp-$$")
  echo "$EVIDENCE_SECTION" > "$EXEC_TMP"

  if ! bash ~/.claude/hooks/runtime-verification-executor.sh "$EXEC_TMP" 2>/tmp/rve-errors; then
    EXEC_ERRORS=$(cat /tmp/rve-errors 2>/dev/null)
    rm -f "$EXEC_TMP" /tmp/rve-errors

    BLOCKER_MSG="One or more 'Runtime verification:' entries failed to execute. Fake/unparseable strings are no longer accepted. See stderr for details."
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 4b — executor failures)" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "Executor output:" >&2
    echo "$EXEC_ERRORS" >&2
    echo "" >&2
    echo "To resolve: fix each failing verification entry. The accepted" >&2
    echo "formats are strict and each entry is executed, not just read:" >&2
    echo "  test <file>::<name>       — file must exist, test must be defined" >&2
    echo "  playwright <spec>::<name> — spec must exist, test must be defined" >&2
    echo "  curl <command>            — command replays and must succeed" >&2
    echo "  sql <SELECT>              — runs against test DB, must not error" >&2
    echo "  file <path>::<pattern>    — file must exist, pattern must match (min 5 literal chars)" >&2
    echo "" >&2
    _pre_stop_block "check4b-executor-failure" "${LATEST_PLAN}:${EXEC_ERRORS}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  fi
  rm -f "$EXEC_TMP" /tmp/rve-errors

  # 4c: correspondence review. The executor verifies commands succeed, but
  # does not check that they correspond to the task's modified files.
  # runtime-verification-reviewer.sh cross-references curl URLs against
  # modified routes, sql tables against modified migrations, and test/
  # playwright imports against modified source files.
  if ! bash ~/.claude/hooks/runtime-verification-reviewer.sh "$LATEST_PLAN" "$EVIDENCE_FILE" 2>/tmp/rvr-errors; then
    RVR_ERRORS=$(cat /tmp/rvr-errors 2>/dev/null)
    rm -f /tmp/rvr-errors

    BLOCKER_MSG="Runtime verification entries execute successfully but do not correspond to the tasks they claim to verify (e.g., curl hits a different route, SQL queries an unrelated table, test file imports no modified source)."
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 4c — correspondence)" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "$RVR_ERRORS" >&2
    echo "" >&2
    _pre_stop_block "check4c-correspondence" "${LATEST_PLAN}:${RVR_ERRORS}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  fi
  rm -f /tmp/rvr-errors
fi

# ============================================================
# Check 5 (M1 — Definition-of-Done gate, added 2026-04-26)
# ============================================================
#
# A plan may declare its own ## Definition of Done section listing
# acceptance bullets that are NOT individual tasks but ARE conditions
# the plan author committed to before claiming completion. Examples:
#   - "Loop converges on current master"
#   - "Human sign-off on 2 random contacts"
#   - "User reviews the apparatus end-to-end and confirms"
# These are real commitments — not just task checkboxes — and historically
# nothing prevented an agent from flipping Status: COMPLETED while DoD
# checkboxes remained unchecked.
#
# This check fires ONLY when the plan declares Status: COMPLETED. It
# parses ONLY the lines under "## Definition of Done" up to the next
# ## heading, looking for unchecked "- [ ]" markers. If any are found,
# the session is blocked with a remediation message.
#
# Rationale: the gap that caused the 2026-04-26 incident where
# flickering-marinating-pine.md was marked COMPLETED while its own DoD
# said "Loop converges on current master" was unchecked. The agent had
# the cognitive dissonance ("I wrote 'deferred to user' three times")
# but no mechanism stopped the Status flip. This is that mechanism.
#
# The check is plan-author-controlled in two senses:
#  - If a plan has no ## Definition of Done section, this check is a no-op
#  - If the author wants to mark a DoD item as accepted-but-not-met, they
#    can move it to a "## Out-of-scope" section or strike it through

if [[ "$IS_COMPLETED" -eq 1 ]]; then
  # Extract DoD section: from "## Definition of Done" line, up to (but not
  # including) the next "## " heading or end-of-file
  DOD_SECTION=$(awk '
    /^## Definition of Done[[:space:]]*$/ { in_dod=1; next }
    in_dod && /^## / { in_dod=0 }
    in_dod { print }
  ' "$LATEST_PLAN" 2>/dev/null)

  if [[ -n "$DOD_SECTION" ]]; then
    DOD_UNCHECKED=$(echo "$DOD_SECTION" | LC_ALL=C grep -cE '^- \[ \]' 2>/dev/null || echo "0")
    DOD_UNCHECKED=$(echo "$DOD_UNCHECKED" | tr -d '[:space:]')

    if [[ "$DOD_UNCHECKED" -gt 0 ]]; then
      DOD_LIST=$(echo "$DOD_SECTION" | LC_ALL=C grep -E '^- \[ \]' | head -10 | sed 's/^/    /')
      BLOCKER_MSG="Plan has Status: COMPLETED but its own ## Definition of Done section has $DOD_UNCHECKED unchecked items in $LATEST_PLAN. The DoD bullets are commitments the plan author made before claiming completion — they are not optional. Either (a) actually satisfy the DoD items and check them off, (b) set Status: ACTIVE to keep working, (c) set Status: PARTIAL with an explicit list of what's deferred, or (d) move accepted-as-out-of-scope DoD items to a ## Out-of-scope section."
      echo "" >&2
      echo "================================================================" >&2
      echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 5 — DoD-completion gate)" >&2
      echo "================================================================" >&2
      echo "$BLOCKER_MSG" >&2
      echo "" >&2
      echo "Unchecked Definition-of-Done items:" >&2
      echo "$DOD_LIST" >&2
      echo "" >&2
      _pre_stop_block "check5-dod-unchecked" "${LATEST_PLAN}:${DOD_UNCHECKED}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
    fi
  fi

  # ============================================================
  # Check 5 / A2 extension: artifact-presence DoD check
  # (added 2026-04-26 — see docs/plans/adversarial-validation-mechanisms.md A2)
  # ============================================================
  #
  # Plans may OPTIONALLY declare a `## DoD Artifacts` section that ties each
  # `## Definition of Done` bullet to a concrete artifact on disk. The base
  # M1 check (above) ensures the checkbox is `[x]`; this A2 extension
  # ensures the artifact actually exists with the declared content.
  #
  # Marking `[x]` doesn't satisfy the gate — the artifact does or doesn't
  # exist on disk. This raises the cost of fabrication above the cost of
  # actually doing the work for any DoD bullet that has a runtime-shaped
  # artifact requirement.
  #
  # Schema (parseable Markdown). Each spec is a `### bullet:` block with
  # bullet-list fields:
  #
  #   ### bullet: <substring of a DoD checkbox>
  #   - artifact: <path, optionally containing `<runId>` glob placeholder>
  #   - requires_field: <JSON field name>           (paired with requires_value)
  #   - requires_value: <expected value>            (paired with requires_field)
  #   - requires_pattern: <ERE regex matched in file content>
  #   - requires_min_length: <integer min file size in bytes>
  #
  # A spec may declare any one of: (requires_field+requires_value),
  # requires_pattern, or requires_min_length. Multiple may be declared for
  # the same artifact and ALL must hold.
  #
  # Path resolution: paths are resolved relative to (a) the plan file's
  # directory first, then (b) the current working directory if not found
  # under (a). The `<runId>` placeholder is glob-expanded — any directory
  # name matches. The first matching path that exists wins.
  #
  # No-op when:
  #   - The plan has no `## DoD Artifacts` section
  #   - The plan's `## DoD Artifacts` section is empty / placeholder-only

  DOD_ARTIFACTS_SECTION=$(awk '
    /^## DoD Artifacts[[:space:]]*$/ { in_da=1; next }
    in_da && /^## / { in_da=0 }
    in_da { print }
  ' "$LATEST_PLAN" 2>/dev/null)

  if [[ -n "$DOD_ARTIFACTS_SECTION" ]] && \
     echo "$DOD_ARTIFACTS_SECTION" | LC_ALL=C grep -qE '^### bullet:' 2>/dev/null; then

    # Re-extract the (possibly-already-extracted) DoD section since we may
    # have skipped that branch when DOD_UNCHECKED was 0.
    if [[ -z "$DOD_SECTION" ]]; then
      DOD_SECTION=$(awk '
        /^## Definition of Done[[:space:]]*$/ { in_dod=1; next }
        in_dod && /^## / { in_dod=0 }
        in_dod { print }
      ' "$LATEST_PLAN" 2>/dev/null)
    fi

    PLAN_DIR_OF_FILE=$(dirname "$LATEST_PLAN")
    DOD_ARTIFACT_FAILURES=""
    DOD_ARTIFACT_FAIL_COUNT=0

    # Parse specs by splitting on "### bullet:" headings. Use awk to emit
    # each spec as a NUL-separated record.
    while IFS= read -r -d '' SPEC; do
      [[ -z "$SPEC" ]] && continue

      SPEC_BULLET=$(echo "$SPEC" | head -1 | sed 's/^### bullet:[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [[ -z "$SPEC_BULLET" ]] && continue

      SPEC_ARTIFACT=$(echo "$SPEC" | LC_ALL=C grep -E '^- artifact:' | head -1 | sed 's/^- artifact:[[:space:]]*//' | sed 's/[[:space:]]*$//')
      SPEC_FIELD=$(echo "$SPEC" | LC_ALL=C grep -E '^- requires_field:' | head -1 | sed 's/^- requires_field:[[:space:]]*//' | sed 's/[[:space:]]*$//')
      SPEC_VALUE=$(echo "$SPEC" | LC_ALL=C grep -E '^- requires_value:' | head -1 | sed 's/^- requires_value:[[:space:]]*//' | sed 's/[[:space:]]*$//')
      SPEC_PATTERN=$(echo "$SPEC" | LC_ALL=C grep -E '^- requires_pattern:' | head -1 | sed 's/^- requires_pattern:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | sed 's/[[:space:]]*$//')
      SPEC_MIN_LEN=$(echo "$SPEC" | LC_ALL=C grep -E '^- requires_min_length:' | head -1 | sed 's/^- requires_min_length:[[:space:]]*//' | sed 's/[[:space:]]*$//')

      if [[ -z "$SPEC_ARTIFACT" ]]; then
        DOD_ARTIFACT_FAILURES+="    - bullet '${SPEC_BULLET}': missing 'artifact:' field"$'\n'
        DOD_ARTIFACT_FAIL_COUNT=$((DOD_ARTIFACT_FAIL_COUNT + 1))
        continue
      fi

      # Confirm the matching DoD checkbox exists. If not, that's a spec
      # error: the plan author declared an artifact for a bullet that
      # doesn't appear in `## Definition of Done`.
      if [[ -n "$DOD_SECTION" ]] && ! echo "$DOD_SECTION" | LC_ALL=C grep -qF "$SPEC_BULLET" 2>/dev/null; then
        DOD_ARTIFACT_FAILURES+="    - bullet '${SPEC_BULLET}': no matching line in ## Definition of Done section"$'\n'
        DOD_ARTIFACT_FAIL_COUNT=$((DOD_ARTIFACT_FAIL_COUNT + 1))
        continue
      fi

      # Resolve path. If the artifact contains `<runId>`, glob-expand it.
      # We try plan-dir-relative first, then cwd-relative.
      RESOLVED_PATH=""
      for BASE in "$PLAN_DIR_OF_FILE" "."; do
        CANDIDATE="${BASE}/${SPEC_ARTIFACT}"
        if [[ "$CANDIDATE" == *"<runId>"* ]]; then
          # Replace `<runId>` with a glob `*` and let the shell expand.
          GLOB_PATTERN="${CANDIDATE//<runId>/*}"
          for MATCH in $GLOB_PATTERN; do
            if [[ -f "$MATCH" ]]; then
              RESOLVED_PATH="$MATCH"
              break
            fi
          done
        elif [[ -f "$CANDIDATE" ]]; then
          RESOLVED_PATH="$CANDIDATE"
        fi
        [[ -n "$RESOLVED_PATH" ]] && break
      done

      if [[ -z "$RESOLVED_PATH" ]]; then
        DOD_ARTIFACT_FAILURES+="    - bullet '${SPEC_BULLET}': artifact not found at '${SPEC_ARTIFACT}' (looked under ${PLAN_DIR_OF_FILE}/ and ./)"$'\n'
        DOD_ARTIFACT_FAIL_COUNT=$((DOD_ARTIFACT_FAIL_COUNT + 1))
        continue
      fi

      # Run requires_* checks. Each that's declared must hold.
      SPEC_OK=1
      SPEC_REASON=""

      if [[ -n "$SPEC_FIELD" || -n "$SPEC_VALUE" ]]; then
        if [[ -z "$SPEC_FIELD" || -z "$SPEC_VALUE" ]]; then
          SPEC_OK=0
          SPEC_REASON="requires_field and requires_value must both be set (got field='${SPEC_FIELD}', value='${SPEC_VALUE}')"
        else
          # Try jq if available, else fall back to a grep-based check.
          if command -v jq >/dev/null 2>&1; then
            ACTUAL=$(jq -r --arg f "$SPEC_FIELD" '.[$f] // empty' "$RESOLVED_PATH" 2>/dev/null || echo "")
          else
            # Fallback: look for `"field": "value"` literal (handles JSON
            # files with simple key/value pairs).
            ACTUAL=$(LC_ALL=C grep -oE "\"${SPEC_FIELD}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$RESOLVED_PATH" 2>/dev/null | head -1 | sed -E "s/^\"${SPEC_FIELD}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/")
          fi
          if [[ "$ACTUAL" != "$SPEC_VALUE" ]]; then
            SPEC_OK=0
            SPEC_REASON="field '${SPEC_FIELD}' = '${ACTUAL:-<missing>}', expected '${SPEC_VALUE}'"
          fi
        fi
      fi

      if [[ "$SPEC_OK" -eq 1 && -n "$SPEC_PATTERN" ]]; then
        if ! LC_ALL=C grep -qE "$SPEC_PATTERN" "$RESOLVED_PATH" 2>/dev/null; then
          SPEC_OK=0
          SPEC_REASON="content does not match pattern: ${SPEC_PATTERN}"
        fi
      fi

      if [[ "$SPEC_OK" -eq 1 && -n "$SPEC_MIN_LEN" ]]; then
        ACTUAL_LEN=$(wc -c < "$RESOLVED_PATH" 2>/dev/null | tr -d '[:space:]')
        ACTUAL_LEN="${ACTUAL_LEN:-0}"
        if [[ "$ACTUAL_LEN" -lt "$SPEC_MIN_LEN" ]]; then
          SPEC_OK=0
          SPEC_REASON="content size ${ACTUAL_LEN} < required min ${SPEC_MIN_LEN}"
        fi
      fi

      if [[ "$SPEC_OK" -eq 0 ]]; then
        DOD_ARTIFACT_FAILURES+="    - bullet '${SPEC_BULLET}' (artifact ${RESOLVED_PATH}): ${SPEC_REASON}"$'\n'
        DOD_ARTIFACT_FAIL_COUNT=$((DOD_ARTIFACT_FAIL_COUNT + 1))
      fi
    done < <(awk '
      /^### bullet:/ { if (NR>1 && have) printf "%c", 0; have=1 }
      have { print }
      END { if (have) printf "%c", 0 }
    ' <<< "$DOD_ARTIFACTS_SECTION")

    if [[ "$DOD_ARTIFACT_FAIL_COUNT" -gt 0 ]]; then
      BLOCKER_MSG="Plan has Status: COMPLETED but $DOD_ARTIFACT_FAIL_COUNT declared DoD artifact spec(s) in $LATEST_PLAN failed verification. Marking ## Definition of Done bullets as [x] is not sufficient — the artifact files declared under ## DoD Artifacts must exist and match the requires_* conditions. Either (a) produce the missing artifacts by actually running the work, (b) set Status: ACTIVE to continue, (c) remove the artifact spec if the bullet was reframed, or (d) revise the requires_* conditions if they no longer reflect what success looks like."
      echo "" >&2
      echo "================================================================" >&2
      echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 5 / A2 — DoD artifact-presence gate)" >&2
      echo "================================================================" >&2
      echo "$BLOCKER_MSG" >&2
      echo "" >&2
      echo "Failing artifact specs:" >&2
      echo -n "$DOD_ARTIFACT_FAILURES" >&2
      echo "" >&2
      _pre_stop_block "check5-dod-artifacts" "${LATEST_PLAN}:${DOD_ARTIFACT_FAIL_COUNT}:${DOD_ARTIFACT_FAILURES}" "$BLOCKER_MSG" "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
    fi
  fi
fi

# ============================================================
# All checks passed
# ============================================================

exit 0
