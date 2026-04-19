#!/bin/bash
# tool-call-budget.sh — Generation 4 (hard-blocking version)
#
# PreToolUse hook that enforces a mid-session attention-decay mitigation
# with HARD BLOCKING. Every 30 tool calls, the next tool call is blocked
# until the builder invokes plan-evidence-reviewer to audit work-so-far.
#
# The earlier version was PostToolUse and could only print reminders
# (self-admitted theater, flagged by the harness-reviewer). This version
# is a PreToolUse hook that exits 1 to block the next tool call until
# the audit is acknowledged.
#
# Acknowledgment protocol:
#   - The builder must invoke plan-evidence-reviewer via the Task tool
#   - The reviewer writes its output to a file in $STATE_DIR/reviews/
#   - `--ack` only succeeds if a reviewer output file exists that was
#     created in the last 5 minutes AND contains specific sentinel lines
#     the reviewer is instructed to emit (REVIEW COMPLETE + VERDICT: ...)
#   - Manually creating an ack file without running the reviewer will
#     fail because the sentinel file won't exist
#
# This replaces the prior "echo $COUNT > $ACK_FILE" protocol, which had
# a prose warning in its own error message saying "do not bypass by
# setting this file manually." A warning inside theater is still theater.
#
# Session tracking: per-pid, so each Claude Code session has its own
# counter. Reset on session start.
#
# Matcher scope: wired to Edit|Write|Bash only (not Read/Grep/Glob).
# Passive exploration doesn't burn budget — only actions that modify
# state or spawn subprocesses count. Tuned to ~30 real actions, not
# ~30 file reads.

set -u

STATE_DIR="$HOME/.claude/state"
REVIEW_DIR="$STATE_DIR/reviews"
mkdir -p "$STATE_DIR" "$REVIEW_DIR" 2>/dev/null

SESSION_ID="${CLAUDE_SESSION_ID:-${PPID:-$$}}"
COUNTER_FILE="$STATE_DIR/tool-call-count.$SESSION_ID"
ACK_FILE="$STATE_DIR/audit-ack.$SESSION_ID"

# Handle --ack flag (builder ran the audit and is acknowledging)
if [[ "${1:-}" == "--ack" ]]; then
  # Require a fresh plan-evidence-reviewer output file as attestation.
  # The reviewer is instructed (in its agent prompt) to write its output
  # to ~/.claude/state/reviews/<timestamp>.md with sentinel markers.
  #
  # Look for a review file modified in the last 5 minutes that contains
  # both "REVIEW COMPLETE" and "VERDICT:" lines. If none exists, the
  # builder hasn't actually run the reviewer and cannot ack.
  now=$(date +%s)
  fresh_review=""
  for f in "$REVIEW_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    age=$((now - mtime))
    if [[ "$age" -le 300 ]]; then
      if grep -q '^REVIEW COMPLETE' "$f" && grep -q '^VERDICT:' "$f"; then
        fresh_review="$f"
        break
      fi
    fi
  done
  if [[ -z "$fresh_review" ]]; then
    cat >&2 <<EOF

================================================================
tool-call-budget --ack REJECTED
================================================================

No fresh plan-evidence-reviewer output found in $REVIEW_DIR.

To acknowledge the tool-call budget, you must actually invoke the
plan-evidence-reviewer agent (via the Task tool). Its output file
must be written within the last 5 minutes and must contain both
a "REVIEW COMPLETE" line and a "VERDICT:" line (the reviewer's
prompt instructs it to emit these).

Manually creating an ack file does not count. The attestation is
tied to the reviewer's actual output.
EOF
    exit 1
  fi
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  echo "$COUNT" > "$ACK_FILE"
  echo "tool-call-budget: audit acknowledged at call $COUNT (attested by $fresh_review)" >&2
  exit 0
fi

# Increment counter
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

LAST_ACK=$(cat "$ACK_FILE" 2>/dev/null || echo "0")
SINCE_ACK=$((COUNT - LAST_ACK))

# Block threshold: 30 tool calls since the last acknowledged audit
BUDGET=30

if [[ "$SINCE_ACK" -ge "$BUDGET" ]]; then
  cat >&2 <<EOF

================================================================
TOOL-CALL BUDGET EXCEEDED — session blocked
================================================================

You have made $SINCE_ACK tool calls since the last acknowledged audit
(call $LAST_ACK). The budget is $BUDGET tool calls per audit cycle.

This hook exists to mitigate attention decay in long autonomous
sessions. Every $BUDGET tool calls, you must pause and audit what's
been done so far before continuing.

REQUIRED next action:
  1. Invoke plan-evidence-reviewer via the Task tool:
     - Input: the active plan file, its -evidence.md file, recent commits
     - Ask: "is anything I've marked complete actually incomplete or
       missing evidence? are the runtime verifications corresponding
       to the tasks? flag anything suspicious."
  2. Read the review and address any findings
  3. Acknowledge this audit:
     bash ~/.claude/hooks/tool-call-budget.sh --ack
  4. Continue with your work

This block will fire on every subsequent tool call until you
acknowledge. Do NOT bypass by setting the ack file manually — that's
the same kind of self-enforced workaround that shipped Failures 1-4
in the 2026-04-14 postmortem.

EOF
  exit 1
fi

exit 0
