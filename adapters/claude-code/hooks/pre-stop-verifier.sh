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

if [[ ${#PLAN_DIRS[@]} -eq 0 ]]; then
  exit 0
fi

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
  echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
  echo "" >&2
  echo "================================================================" >&2
  echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
  echo "================================================================" >&2
  echo "$BLOCKER_MSG" >&2
  echo "" >&2
  exit 1
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
  echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
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
  exit 1
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
  echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
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
  exit 1
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
    echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "To resolve: re-generate malformed evidence blocks by re-invoking" >&2
    echo "the task-verifier agent on affected tasks." >&2
    echo "" >&2
    exit 1
  fi

  # Ensure every evidence block has a PASS verdict (failures shouldn't be
  # left in the plan as evidence of completion)
  FAIL_VERDICTS=$(echo "$EVIDENCE_SECTION" | grep -cE '^Verdict:[[:space:]]*(FAIL|INCOMPLETE)' || echo "0")
  FAIL_VERDICTS=$(echo "$FAIL_VERDICTS" | tr -d '[:space:]')

  if [[ "$FAIL_VERDICTS" -gt 0 ]]; then
    BLOCKER_MSG="Evidence Log contains $FAIL_VERDICTS FAIL or INCOMPLETE verdict(s). Tasks with failing evidence should not be checked. Either resolve the issues and re-verify, or remove the failing evidence blocks and uncheck the tasks."
    echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    exit 1
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
    echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
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
    exit 1
  fi

  # 4b: execute every runtime verification line via the executor
  # Write evidence to a temp file so the executor can read it
  EXEC_TMP=$(mktemp 2>/dev/null || echo "/tmp/rve-tmp-$$")
  echo "$EVIDENCE_SECTION" > "$EXEC_TMP"

  if ! bash ~/.claude/hooks/runtime-verification-executor.sh "$EXEC_TMP" 2>/tmp/rve-errors; then
    EXEC_ERRORS=$(cat /tmp/rve-errors 2>/dev/null)
    rm -f "$EXEC_TMP" /tmp/rve-errors

    BLOCKER_MSG="One or more 'Runtime verification:' entries failed to execute. Fake/unparseable strings are no longer accepted. See stderr for details."
    echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
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
    exit 1
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
    echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
    echo "" >&2
    echo "================================================================" >&2
    echo "PRE-STOP VERIFIER: SESSION BLOCKED (Check 4c — correspondence)" >&2
    echo "================================================================" >&2
    echo "$BLOCKER_MSG" >&2
    echo "" >&2
    echo "$RVR_ERRORS" >&2
    echo "" >&2
    exit 1
  fi
  rm -f /tmp/rvr-errors
fi

# ============================================================
# All checks passed
# ============================================================

exit 0
