#!/bin/bash
# plan-edit-validator.sh — Generation 4
#
# PreToolUse hook that blocks casual plan-checkbox self-edits.
#
# Rule: the only entity allowed to flip "- [ ]" → "- [x]" in a plan file
# under docs/plans/ is the task-verifier agent. Direct edits by the builder
# are blocked.
#
# The hook reads the tool invocation JSON from stdin (Claude Code's
# PreToolUse convention), inspects it for plan-file edits, and exits 1
# if the edit would flip a checkbox without task-verifier authorization.
#
# Escape hatches (legitimate use cases):
#   1. File matches *-evidence.md → evidence files are written by the
#      verifier output. Allowed (the evidence content is validated at
#      session-end by the runtime-verification-executor).
#   2. The file isn't under docs/plans/ at all → pass through.
#   3. The file is under docs/plans/ but the edit is evidence-first
#      authorized (see check_evidence_first below).
#
# PREVIOUSLY this hook honored a TASK_VERIFIER_MODE=1 environment
# variable as an escape hatch. That was a plaintext back door: any
# bash -c 'TASK_VERIFIER_MODE=1 ...' wrapper bypassed the gate. It has
# been removed. The ONLY authorized path is evidence-first.
#
# Exit codes:
#   0 — edit is allowed
#   1 — edit is blocked (stderr explains why)

set -e

# Read the tool invocation JSON from whichever input mode Claude Code uses.
# PreToolUse hooks may receive input via stdin OR via the CLAUDE_TOOL_INPUT
# env var depending on Claude Code version. Support both.
#
# The other hooks in this settings.json (e.g., .env blocker, lockfile
# blocker, force-push blocker) all use $CLAUDE_TOOL_INPUT. An earlier
# version of this hook only read stdin, which silently no-op'd because
# stdin was empty. That bug was caught by the adversarial harness review.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  # Fall back to stdin
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

# If there's still no input (direct manual invocation), nothing to check
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Some hook-input formats nest under .tool_input, others put the tool
# input at the top level. Check both and extract the key fields.
HAS_NESTED=$(echo "$INPUT" | jq -r 'has("tool_input")' 2>/dev/null || echo "false")

# Evidence-first authorization (the ONLY legitimate path)
# Instead of a forgeable marker file, the plan edit is authorized only if
# the corresponding evidence file (<plan>-evidence.md) has been modified
# in the last 120 seconds AND contains a Task ID: line matching the task
# being checked.
#
# This ties authorization to an actual artifact: the task-verifier must
# write real evidence before flipping the checkbox. The evidence is
# subject to runtime-verification-executor validation at session-end, so
# a builder cannot fabricate evidence without also writing real
# Runtime verification: commands that execute successfully.
#
# A manual "touch" cannot bypass this because touch-ing the evidence file
# doesn't insert a Task ID: line.

# This check runs after we know FILE_PATH is a plan file (see below).
# We'll evaluate the escape hatch inline at the checkbox-transition point.

# Extract file_path (present for both Edit and Write)
# Support both nested (.tool_input.file_path) and flat (.file_path) formats
if [[ "$HAS_NESTED" == "true" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
else
  FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // ""' 2>/dev/null)
  # For flat format, we can't easily know the tool name; infer from fields
  if [[ -n "$(echo "$INPUT" | jq -r '.old_string // ""' 2>/dev/null)" ]]; then
    TOOL_NAME="Edit"
  elif [[ -n "$(echo "$INPUT" | jq -r '.content // ""' 2>/dev/null)" ]]; then
    TOOL_NAME="Write"
  else
    TOOL_NAME="Unknown"
  fi
fi

# If the invocation has no file_path, it's not a file-edit tool — pass through
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize path separators (Windows Git Bash uses forward slashes in JSON)
FILE_PATH_NORM=$(echo "$FILE_PATH" | tr '\\' '/')

# Check if the file is under docs/plans/ (either repo-relative or absolute)
if [[ ! "$FILE_PATH_NORM" =~ docs/plans/.*\.md$ ]]; then
  exit 0
fi

# Escape hatch: evidence files are allowed (they're written by the verifier)
if [[ "$FILE_PATH_NORM" =~ -evidence\.md$ ]]; then
  exit 0
fi

# Escape hatch: new plan files are allowed (Write creating a fresh plan)
# We allow fresh plan creation but block modifications that check boxes
# on existing plans. Detect "new" by whether the file exists on disk.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Helper: check if the task ID is backed by a fresh evidence entry.
#
# Returns 0 if:
#   1. The evidence file was modified in the last 120 seconds (mtime check)
#   2. The evidence file contains an EVIDENCE BLOCK whose `Task ID:` line
#      matches the task being checked
#   3. That same block contains at least one `Runtime verification:` line
#      between the matching Task ID and the next EVIDENCE BLOCK marker
#      (or end-of-file)
#
# The per-block parsing closes the replay attack where one legitimate
# verification for task A.1 authorized all subsequent edits within 120s.
# Now the Task ID line and the Runtime verification line must appear in
# the SAME block, which means a single evidence block authorizes exactly
# one checkbox flip.
check_evidence_first() {
  local plan_file="$1"
  local task_id="$2"
  local evidence_file="${plan_file%.md}-evidence.md"

  [[ -f "$evidence_file" ]] || return 1

  # Evidence file must be recent (modified in last 120 seconds)
  local now mtime age
  now=$(date +%s)
  mtime=$(stat -c %Y "$evidence_file" 2>/dev/null || echo 0)
  age=$((now - mtime))
  if [[ "$age" -gt 120 ]]; then
    return 1
  fi

  # Parse the evidence file into per-block sections. A block starts with
  # a line containing "EVIDENCE BLOCK" and ends at the next one or EOF.
  # For each block: extract its Task ID line and its Runtime verification
  # lines. If any block has Task ID matching $task_id AND has at least
  # one Runtime verification line, the authorization succeeds.
  #
  # We use awk for a single-pass parse that handles multiple blocks.
  local result
  result=$(awk -v wanted_id="$task_id" '
    BEGIN { in_block = 0; task_id = ""; has_runtime = 0; }
    /^EVIDENCE BLOCK/ {
      # Starting a new block — check if the previous one matched
      if (in_block && task_id == wanted_id && has_runtime) {
        print "MATCH"
        exit 0
      }
      in_block = 1
      task_id = ""
      has_runtime = 0
      next
    }
    /^Task ID:/ {
      if (in_block) {
        # Extract task ID (strip prefix and trailing whitespace)
        sub(/^Task ID:[[:space:]]*/, "", $0)
        sub(/[[:space:]].*$/, "", $0)
        task_id = $0
      }
      next
    }
    /^Runtime verification:/ {
      if (in_block) has_runtime = 1
      next
    }
    END {
      # Final block at EOF
      if (in_block && task_id == wanted_id && has_runtime) {
        print "MATCH"
      }
    }
  ' "$evidence_file")

  if [[ "$result" == "MATCH" ]]; then
    return 0
  fi
  return 1
}

# For Edit calls: look at old_string vs new_string
if [[ "$TOOL_NAME" == "Edit" ]]; then
  if [[ "$HAS_NESTED" == "true" ]]; then
    OLD_STR=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
  else
    OLD_STR=$(echo "$INPUT" | jq -r '.old_string // ""' 2>/dev/null)
    NEW_STR=$(echo "$INPUT" | jq -r '.new_string // ""' 2>/dev/null)
  fi

  # Does the old string contain an unchecked box AND the new string contain
  # a checked box? If yes, this is a checkbox flip.
  if echo "$OLD_STR" | grep -qE '^\s*-\s*\[\s*\]'; then
    if echo "$NEW_STR" | grep -qE '^\s*-\s*\[\s*[xX]\s*\]'; then
      # Extract the task ID from the new_string (format: - [x] A.1 ...)
      TASK_ID=$(echo "$NEW_STR" | grep -oE '\[[xX]\][[:space:]]+[A-Z]+\.[0-9]+(\.[0-9]+)*' | grep -oE '[A-Z]+\.[0-9]+(\.[0-9]+)*' | head -1)

      # Evidence-first escape hatch
      if [[ -n "$TASK_ID" ]] && check_evidence_first "$FILE_PATH" "$TASK_ID"; then
        exit 0
      fi
      cat >&2 <<'ERR'

================================================================
PLAN EDIT BLOCKED — Generation 4 plan-edit-validator
================================================================

You are trying to flip a plan task checkbox from [ ] to [x] by
editing the plan file directly. This is forbidden.

The authorized path (evidence-first): before editing the plan file,
append a valid evidence block to the companion evidence file:

    ${FILE_PATH%.md}-evidence.md

The evidence block must:
  1. Have been written in the last 120 seconds (the hook checks mtime)
  2. Contain a line: "Task ID: <id>" matching the task you are checking
  3. Contain at least one "Runtime verification:" line in one of the
     replayable formats (test/curl/sql/playwright/file)

Only AFTER the evidence file is written may the plan checkbox flip.
The runtime verification will be re-executed at session-end by the
pre-stop-verifier hook — fabricated evidence is caught there.

Why this works where a marker file didn't:
  A marker file is a 1-command bypass. Writing a real evidence block
  with a Runtime verification: command that actually succeeds when
  executed requires doing the actual work. The adversarial review
  killed the marker-file escape hatch; this is the replacement.

ERR
      exit 1
    fi
  fi

  # Also block Status: <non-COMPLETED> → Status: COMPLETED transitions
  # unless an evidence file already exists for the plan
  if echo "$OLD_STR" | grep -qE '^Status:\s*(ACTIVE|DEFERRED)'; then
    if echo "$NEW_STR" | grep -qE '^Status:\s*COMPLETED'; then
      # Derive the evidence file path: foo.md -> foo-evidence.md
      EVIDENCE_FILE="${FILE_PATH_NORM%.md}-evidence.md"
      if [[ ! -f "$EVIDENCE_FILE" ]]; then
        cat >&2 <<ERR

================================================================
PLAN EDIT BLOCKED — Status COMPLETED without evidence file
================================================================

You are trying to mark a plan as Status: COMPLETED, but there is
no evidence file at:

  $EVIDENCE_FILE

A plan cannot be marked COMPLETED without evidence blocks for every
task. The task-verifier agent writes evidence to this file as it
verifies each task.

To resolve: run the task-verifier on every unchecked task first.
Once each task has an evidence block, COMPLETED is allowed.

To defer the plan instead, set Status: DEFERRED with a reason.
To abandon, set Status: ABANDONED with a reason.

ERR
        exit 1
      fi
    fi
  fi
fi

# For Write calls: compare the count of [x] boxes in old vs new content
if [[ "$TOOL_NAME" == "Write" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)

  # If the file doesn't exist yet, it's a new plan file — allow
  if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
  fi

  OLD_CHECKED=$(grep -cE '^\s*-\s*\[\s*[xX]\s*\]' "$FILE_PATH" 2>/dev/null || echo "0")
  OLD_CHECKED=$(echo "$OLD_CHECKED" | tr -d '[:space:]')
  NEW_CHECKED=$(echo "$NEW_CONTENT" | grep -cE '^\s*-\s*\[\s*[xX]\s*\]' 2>/dev/null || echo "0")
  NEW_CHECKED=$(echo "$NEW_CHECKED" | tr -d '[:space:]')

  if [[ "$NEW_CHECKED" -gt "$OLD_CHECKED" ]]; then
    cat >&2 <<ERR

================================================================
PLAN WRITE BLOCKED — checkbox count increased via Write
================================================================

You are trying to Write the plan file with MORE checked boxes
($NEW_CHECKED) than currently exist on disk ($OLD_CHECKED).

This is a bypass attempt on the Edit-level block. Write operations
cannot be used to self-check tasks either. Only the task-verifier
agent is authorized.

To resolve: invoke the task-verifier agent via the Task tool.

ERR
    exit 1
  fi

  # Same Status-COMPLETED check for Write
  if echo "$NEW_CONTENT" | grep -qE '^Status:\s*COMPLETED' 2>/dev/null; then
    if ! grep -qE '^Status:\s*COMPLETED' "$FILE_PATH" 2>/dev/null; then
      EVIDENCE_FILE="${FILE_PATH_NORM%.md}-evidence.md"
      if [[ ! -f "$EVIDENCE_FILE" ]]; then
        cat >&2 <<ERR

================================================================
PLAN WRITE BLOCKED — Status COMPLETED without evidence file
================================================================

Cannot write Status: COMPLETED to this plan. No evidence file at:
  $EVIDENCE_FILE

Run task-verifier on every unchecked task first.

ERR
        exit 1
      fi
    fi
  fi
fi

exit 0
