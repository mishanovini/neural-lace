#!/bin/bash
# post-tool-task-verifier-reminder.sh — Generation 4
#
# PostToolUse hook that fires after Edit/Write to a source file under
# src/. Checks whether the active plan has an in-progress or unchecked
# task that matches the edited file, and if so, prints a reminder
# telling the builder to invoke task-verifier before continuing.
#
# The hook does not block (PostToolUse runs after the tool already
# completed). It's a persistent reminder that fires every time the
# builder edits runtime code while a plan is active.
#
# This is a partial mitigation for attention decay in long sessions —
# we can't force the verifier to run automatically (no subagent-from-hook
# spawn), but we can make "forget to verify" loud.

set -u

# Read the tool invocation JSON from stdin
INPUT=$(cat 2>/dev/null || echo "")
[[ -z "$INPUT" ]] && exit 0

# Only fire on Edit/Write tools
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Normalize path
FILE_PATH_NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Only fire on src/ files — not tests, not docs, not configs
# Match both "src/..." and "/src/..." (absolute and relative paths)
[[ "$FILE_PATH_NORM" =~ (^|/)src/.*\.(ts|tsx|js|jsx)$ ]] || exit 0
[[ "$FILE_PATH_NORM" =~ \.d\.ts$ ]] && exit 0

# Find the latest plan to consult.
#
# Active-dir lookup is preferred (an in-progress plan is by far the most
# common case). Archive lookup is a fallback for the rare situation where
# the only plan correlating with the edited source file lives in
# docs/plans/archive/ — for example, a session that re-opens an archived
# plan to revise it after discovering a follow-up issue.
#
# Resolution uses ~/.claude/scripts/find-plan-file.sh when available so
# the active-then-archive ordering matches every other harness consumer.
PLAN_DIR=""
ARCHIVE_DIR=""
if [[ -d "docs/plans" ]]; then
  PLAN_DIR="docs/plans"
  [[ -d "docs/plans/archive" ]] && ARCHIVE_DIR="docs/plans/archive"
fi
[[ -z "$PLAN_DIR" ]] && exit 0

# Extract basename without extension for matching (used both for the
# task-mention grep below and the file-correlation fallback).
BASE=$(basename "$FILE_PATH_NORM")
STEM="${BASE%.*}"

# Helper: pick the latest ACTIVE plan in a directory whose unchecked tasks
# mention the edited source file (by basename or stem). Returns empty if
# no such plan exists in that directory.
find_correlating_plan() {
  local dir="$1"
  local plan
  for plan in $(ls -t "$dir"/*.md 2>/dev/null | grep -v -- '-evidence\.md$'); do
    [[ -f "$plan" ]] || continue
    grep -qE '^Status:\s*ACTIVE' "$plan" 2>/dev/null || continue
    if grep -qE "^- \[ \].*($BASE|$STEM)" "$plan" 2>/dev/null; then
      printf '%s\n' "$plan"
      return 0
    fi
  done
  return 1
}

# Prefer active-dir match. If none, fall back to archive (a rare case
# but the right behavior when an archived plan is the only one whose
# unchecked tasks correlate with the edited source file — e.g., a session
# revisiting a previously-archived plan).
LATEST_PLAN=$(find_correlating_plan "$PLAN_DIR" || true)
RESOLVED_FROM_ARCHIVE=0
if [[ -z "$LATEST_PLAN" && -n "$ARCHIVE_DIR" ]]; then
  LATEST_PLAN=$(find_correlating_plan "$ARCHIVE_DIR" || true)
  [[ -n "$LATEST_PLAN" ]] && RESOLVED_FROM_ARCHIVE=1
fi

# If no correlating plan was found (active or archive), there is nothing
# to remind about. The original behavior fell back to the most-recently-
# modified active plan even when it had no matching tasks; that turned
# out to surface false-positive reminders. Tightening to "must mention
# this file" is a small behavior change that aligns with the helper's
# correlation contract.
[[ -z "$LATEST_PLAN" ]] && exit 0

# Re-extract matching tasks (already verified one exists; this fetches up
# to 3 for the reminder body).
MATCHING_TASKS=$(grep -nE "^- \[ \].*($BASE|$STEM)" "$LATEST_PLAN" 2>/dev/null | head -3)

if [[ -z "$MATCHING_TASKS" ]]; then
  exit 0
fi

ARCHIVE_NOTE=""
if [[ "$RESOLVED_FROM_ARCHIVE" -eq 1 ]]; then
  ARCHIVE_NOTE="
(NOTE: this plan was resolved from docs/plans/archive/. Archived plans
are normally terminal — if you're actively building tasks here, the
plan's Status field may be incorrect or the plan may need to be moved
back to docs/plans/ before continuing.)"
fi

# Print a reminder to stderr (shows up in the builder's tool output stream)
cat >&2 <<EOF

==================================================================
TASK-VERIFIER REMINDER
==================================================================
You just edited: $FILE_PATH_NORM

The active plan ($LATEST_PLAN) has unchecked tasks that mention
this file or a closely related one:$ARCHIVE_NOTE

$MATCHING_TASKS

If you believe this edit completes one of those tasks, invoke the
task-verifier agent to check it before continuing.

Do NOT flip the checkbox yourself — the plan-edit-validator hook
will block direct edits. Invoke task-verifier, which sets the
marker file and performs the edit authorized.

(This reminder fires on every edit to src/ files while an ACTIVE
plan has unchecked tasks matching your changes. To silence it,
either finish the tasks and have them verified, or set the plan
Status to DEFERRED/COMPLETED.)

EOF

exit 0
