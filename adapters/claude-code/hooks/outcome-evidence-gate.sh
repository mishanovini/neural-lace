#!/bin/bash
# outcome-evidence-gate.sh — Generation 5
#
# PreToolUse hook that enforces the reproduction discipline for fix tasks.
#
# Rule: when a plan-file checkbox is flipped for a task whose description
# describes fixing a bug (match keywords: fix, bug, broken, doesn't work,
# not working, wrong, incorrect, regression, issue #N), the companion
# evidence file MUST contain:
#
#   Runtime verification (before): <command>
#     ... + "Expected: FAIL" or similar showing bug reproduces
#
#   Runtime verification (after): <command>
#     ... + "Expected: PASS" or similar showing bug resolved
#
# Both entries must share the same <command> — that's the proof the fix
# actually targets the bug. If the command passes before AND after, the
# command wasn't testing the broken behavior.
#
# This hook runs AFTER plan-edit-validator.sh, which handles the broader
# "is this edit authorized at all" check. This hook adds the fix-specific
# reproduction requirement on top.
#
# Escape hatches:
#   1. Task description doesn't match fix keywords → pass through (this
#      hook is only for fix/bug tasks, not new features or docs).
#   2. File isn't a plan file edit flipping a checkbox → pass through.
#   3. Task description includes a "Reproduction recipe:" block in the
#      evidence file → pass (the agent documented that automated repro
#      wasn't possible, and gave a manual recipe instead).
#
# Exit codes:
#   0 — edit is allowed (either not a fix task, or fix task with proper
#       before/after evidence)
#   1 — edit is blocked (fix task missing before/after reproduction)

set -e

# ============================================================
# Input loading — support both CLAUDE_TOOL_INPUT and stdin
# (same pattern as plan-edit-validator.sh)
# ============================================================
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

# Nothing to check — silent pass
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# ============================================================
# Fast-path: only care about Edit/Write on plan files
# ============================================================

# Extract file_path from the tool input (JSON). The field is
# `file_path` for both Edit and Write tools.
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // empty' 2>/dev/null || echo "")

# Not a file edit we care about
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Not a plan file — pass through. Plans live under docs/plans/ by convention.
if [[ "$FILE_PATH" != *docs/plans/* ]]; then
  exit 0
fi

# Evidence files are companion files, not plan files — let them through.
if [[ "$FILE_PATH" == *-evidence.md ]]; then
  exit 0
fi

# ============================================================
# Identify if this edit is flipping a checkbox
# ============================================================

# Extract the new_string the edit would write. For Edit tool it's
# `new_string`; for Write tool we'd need to diff the whole content which
# is out of scope for this hook. We focus on Edit.
NEW_STRING=$(echo "$INPUT" | jq -r '.new_string // .tool_input.new_string // empty' 2>/dev/null || echo "")
OLD_STRING=$(echo "$INPUT" | jq -r '.old_string // .tool_input.old_string // empty' 2>/dev/null || echo "")

# If there's no checkbox flip in the edit, not our concern
if [[ "$OLD_STRING" != *"- [ ]"* ]] || [[ "$NEW_STRING" != *"- [x]"* ]]; then
  exit 0
fi

# ============================================================
# Extract the task ID and description being flipped
# ============================================================

# Task lines look like: "- [x] A.1 Task description here..."
# or: "- [x] 1. Task description..."
# Grab the first line of new_string that has the flipped checkbox.
FLIPPED_LINE=$(echo "$NEW_STRING" | grep -m1 '^[[:space:]]*- \[x\]' || echo "")

if [[ -z "$FLIPPED_LINE" ]]; then
  # Checkbox characters present but no proper task line format — let
  # plan-edit-validator handle this edge case.
  exit 0
fi

# Parse task ID (e.g., "A.1", "3.2", "7") and description
# Format: "- [x] <ID> <description>" or "- [x] <ID>. <description>"
TASK_ID=$(echo "$FLIPPED_LINE" | sed -nE 's/^[[:space:]]*- \[x\][[:space:]]+([A-Z0-9]+(\.[0-9]+)*)\.?[[:space:]].*/\1/p' | head -1)
TASK_DESC=$(echo "$FLIPPED_LINE" | sed -nE 's/^[[:space:]]*- \[x\][[:space:]]+[A-Z0-9]+(\.[0-9]+)*\.?[[:space:]]+(.*)$/\2/p' | head -1)

if [[ -z "$TASK_ID" ]]; then
  # Couldn't parse — not a task line we recognize, pass through
  exit 0
fi

# ============================================================
# Check if task description matches fix patterns
# ============================================================

# Case-insensitive match against the fix keyword set. Word boundaries
# prevent matches inside unrelated words (e.g., "prefix" matching "fix").
FIX_PATTERN='\b(fix|fixes|fixing|fixed|bug|broken|doesn'\''t[[:space:]]+work|not[[:space:]]+working|wrong|incorrect|should[[:space:]]+(be|have|not)|regression|issue[[:space:]]*#[0-9]+)\b'

if ! echo "$TASK_DESC" | grep -qiE "$FIX_PATTERN"; then
  # Not a fix task — this hook doesn't apply. Pass through.
  exit 0
fi

# ============================================================
# Fix task detected. Require before/after reproduction evidence.
# ============================================================

# Derive the companion evidence file path
EVIDENCE_FILE="${FILE_PATH%.md}-evidence.md"

if [[ ! -f "$EVIDENCE_FILE" ]]; then
  cat >&2 <<MSG
BLOCKED: outcome-evidence-gate

Task $TASK_ID is a fix task (matches pattern: fix/bug/broken/etc.)
but no companion evidence file exists at:
  $EVIDENCE_FILE

Fix tasks require before/after reproduction evidence. See
~/.claude/agents/task-verifier.md → "Reproduction-based
verification for FIX tasks" for the required format.

The task-verifier agent must produce this evidence before the
checkbox can be flipped.
MSG
  exit 1
fi

# ============================================================
# Scan the evidence file for the before/after structure
# ============================================================
#
# We look for the relevant task's evidence block and within it:
#   - At least one "Runtime verification (before):" line
#   - At least one "Runtime verification (after):" line
#
# If the evidence file has a "Reproduction recipe:" block for this
# task instead, that's the manual-repro escape hatch — accept it.

# Extract just the section for this task ID. A task section starts at
# "Task ID: <id>" and ends at the next "Task ID:" or EOF.
TASK_SECTION=$(awk -v id="$TASK_ID" '
  /^Task ID:/ {
    if (in_section) exit
    if ($0 ~ "Task ID:[[:space:]]*" id "$") { in_section = 1 }
  }
  in_section { print }
' "$EVIDENCE_FILE")

if [[ -z "$TASK_SECTION" ]]; then
  cat >&2 <<MSG
BLOCKED: outcome-evidence-gate

Task $TASK_ID is a fix task but its evidence block was not found
in the evidence file:
  $EVIDENCE_FILE

Expected a section starting with:
  Task ID: $TASK_ID

The task-verifier agent must add this evidence block before the
checkbox can be flipped.
MSG
  exit 1
fi

# Check for before/after OR the manual reproduction recipe escape hatch.
# grep -c always emits a single integer; the `|| echo 0` pattern doubles
# up on a match (grep exits 0, echo also runs). Use simpler count pipeline.
HAS_BEFORE=$(echo "$TASK_SECTION" | grep -cE 'Runtime verification[[:space:]]*\(before\)' 2>/dev/null | tr -cd '[:digit:]')
HAS_AFTER=$(echo "$TASK_SECTION" | grep -cE 'Runtime verification[[:space:]]*\(after\)' 2>/dev/null | tr -cd '[:digit:]')
HAS_RECIPE=$(echo "$TASK_SECTION" | grep -cE 'Reproduction recipe[[:space:]]*\(' 2>/dev/null | tr -cd '[:digit:]')

# Default to 0 if anything came back empty
HAS_BEFORE=${HAS_BEFORE:-0}
HAS_AFTER=${HAS_AFTER:-0}
HAS_RECIPE=${HAS_RECIPE:-0}

if [[ $HAS_RECIPE -ge 1 ]]; then
  # Manual reproduction recipe — acceptable for cases where automated
  # before-state isn't possible (buggy code already overwritten, etc.)
  exit 0
fi

if [[ $HAS_BEFORE -lt 1 ]] || [[ $HAS_AFTER -lt 1 ]]; then
  cat >&2 <<MSG
BLOCKED: outcome-evidence-gate

Task $TASK_ID is a fix task:
  "$TASK_DESC"

The evidence block at $EVIDENCE_FILE is missing the required
before/after reproduction structure.

Found: "Runtime verification (before)" lines: $HAS_BEFORE
       "Runtime verification (after)" lines: $HAS_AFTER

Required for fix tasks:

  Runtime verification (before): <replayable command>
    Commit: <SHA before fix>
    Expected: FAIL — demonstrates the bug
    Observed: <what the command shows>

  Runtime verification (after): <same replayable command>
    Commit: <SHA after fix>
    Expected: PASS — bug resolved
    Observed: <what the command shows now>

Both entries must use the same command. If they pass before AND after,
the command wasn't testing the broken behavior — that's not proof of fix.

If automated before-state truly can't be captured (bug-causing code
was overwritten, or bug requires production data), add a section:
  Reproduction recipe (could not replay automated):
    1. Revert commit <SHA>
    2. Run <command>
    3. Observe: ...
(Use this only when automated reproduction is genuinely impossible —
a test that CAN be written should be.)

See ~/.claude/agents/task-verifier.md → "Reproduction-based
verification for FIX tasks" for full format.
MSG
  exit 1
fi

# All checks passed
exit 0
