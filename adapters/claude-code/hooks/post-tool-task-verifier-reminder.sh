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

# Find the latest active plan
PLAN_DIR=""
if [[ -d "docs/plans" ]]; then
  PLAN_DIR="docs/plans"
fi
[[ -z "$PLAN_DIR" ]] && exit 0

LATEST_PLAN=$(ls -t "$PLAN_DIR"/*.md 2>/dev/null | grep -v -- '-evidence\.md$' | head -1)
[[ -z "$LATEST_PLAN" ]] && exit 0

# Only fire if the plan is ACTIVE
if ! grep -qE '^Status:\s*ACTIVE' "$LATEST_PLAN" 2>/dev/null; then
  exit 0
fi

# Extract basename without extension for matching
BASE=$(basename "$FILE_PATH_NORM")
STEM="${BASE%.*}"

# Look for unchecked tasks that mention the file path or basename
MATCHING_TASKS=$(grep -nE "^- \[ \].*($BASE|$STEM)" "$LATEST_PLAN" 2>/dev/null | head -3)

if [[ -z "$MATCHING_TASKS" ]]; then
  exit 0
fi

# Print a reminder to stderr (shows up in the builder's tool output stream)
cat >&2 <<EOF

==================================================================
TASK-VERIFIER REMINDER
==================================================================
You just edited: $FILE_PATH_NORM

The active plan ($LATEST_PLAN) has unchecked tasks that mention
this file or a closely related one:

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
