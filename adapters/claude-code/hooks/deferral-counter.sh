#!/bin/bash
# deferral-counter.sh — Stop hook (A5 — Generation 6 mechanism)
#
# Forces the agent's FINAL user-facing message to enumerate every deferral
# in the session. Without this, deferrals get buried in middle-of-work
# narration that the user never sees — only the end-of-effort summary
# is reliably read.
#
# WHY THIS EXISTS
# ===============
# On 2026-04-26 the agent marked a plan COMPLETED while having written
# "deferred to user", "PHASE6-FOLLOWUP-01", "first run is user-driven
# decision" three times across PR bodies, commit messages, and
# SCRATCHPAD. None of those appeared in the final session-summary the
# user read. The user's stated principle: "Only the text provided to me
# at the end of your effort is what we can count on me actually seeing."
#
# This hook closes that gap. It scans the session transcript for
# deferral phrases, collects them, and blocks session end UNTIL the
# agent's final user-facing message includes a "## Deferrals not
# executed in this session" section enumerating them.
#
# The agent CAN avoid the section by avoiding deferrals — actually do
# the work, leave nothing un-done. That's the desired escape: do the
# thing instead of writing about not doing it.
#
# DESIGN
# ======
# Pass conditions (any of these):
#   - Zero deferrals detected in session -> pass.
#   - Last assistant message contains the literal heading
#     "## Deferrals not executed in this session" followed by
#     at least one bullet line.
#   - DEFERRAL_COUNTER_DISABLE=1 in env (escape hatch for harness work)
#
# Fail mode:
#   - Session has deferrals but last message does NOT include the
#     required section -> BLOCK with a specific block message that
#     lists the deferrals verbatim so the agent can paste them in.
#
# READS RAW TRANSCRIPT, NOT NARRATIVE
# ===================================
# The hook reads $TRANSCRIPT_PATH JSONL which Claude Code writes; the
# agent cannot edit it. Pattern matching is against a comprehensive
# synonym list of phrases meaning "I didn't do this." Single-synonym
# bypass works for an individual phrase but the agent cannot use ZERO
# synonyms while still describing a real deferral.

set -u

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi

# Without a transcript or jq, this hook is a no-op.
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Escape hatch
if [[ "${DEFERRAL_COUNTER_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

# ============================================================
# Synonym list — phrases meaning "I didn't do this"
# ============================================================

DEFERRAL_PATTERNS=(
  '\bdeferred?\b'
  '\bfollow-up\b'
  '\bfollow up\b'
  'PHASE[0-9]+-?FOLLOWUP'
  '\bTBD\b'
  '\bFIXME\b'
  '\bfor now\b'
  '\binitial pass\b'
  '\bfirst pass\b'
  '\bminimum viable\b'
  'walking[- ]skeleton'
  '\bstub(s|bed)?\b'
  '\bscaffold(ing|ed)?\b'
  '\bmock(ed|ing|s)?\b'
  '\bsimulated?\b'
  'user-?driven decision'
  'awaiting user'
  'requires user'
  'user must (decide|authorize|approve)'
  'pending (approval|review|user|authorization)'
  'future work'
  'next session'
  'subsequent (session|phase)'
  'in a future'
  'post-launch'
  'post-merge'
  'will be done later'
  'will be added'
  'add(ed)? later'
  'come back to'
  'DO NOT run'
  'DO NOT actually'
  'do not (run|execute|invoke)'
  'not yet executed'
  'not yet run'
  'never (ran|executed|invoked)'
  'haven.?t (run|executed|tested)'
  'didn.?t (run|execute|test)'
  'out of scope for this'
  'out-of-scope for this'
  'scope-limited'
  'scoped out'
  '\bDEFERRED\b'
  '\bPARTIAL\b'
  '\bABANDONED\b'
  'phase [0-9]+ later'
  '(deferred|moved|punted) to phase'
  'rubber-?stamp'
  'is not (actually|really|truly) done'
  'not (actually|really|truly) (done|complete|finished|validated)'
  'this isn.?t (done|complete|finished)'
  'never (completed|finished|validated|verified)'
)

# Required section heading the agent must include
REQUIRED_HEADING='## Deferrals not executed in this session'

# ============================================================
# Extract assistant message text + last assistant message
# ============================================================

ASSISTANT_TEXT=$(jq -r '
  select(.role == "assistant" or .message.role == "assistant")
  | (.content // .text // .message.content // empty)
  | if type == "string" then .
    elif type == "array" then
      [.[] | (.text // .content // "")] | join("\n")
    else (. | tostring) end
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

if [[ -z "$ASSISTANT_TEXT" ]]; then
  exit 0
fi

LAST_ASSISTANT=$(jq -r '
  select(.role == "assistant" or .message.role == "assistant")
  | (.content // .text // .message.content // empty)
  | if type == "string" then .
    elif type == "array" then
      [.[] | (.text // .content // "")] | join("\n")
    else (. | tostring) end
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

# ============================================================
# Match each pattern; count + collect canonical-form list
# ============================================================

TMP_MATCHES=$(mktemp /tmp/deferral-matches.XXXXXX)
trap "rm -f $TMP_MATCHES" EXIT

TOTAL_COUNT=0
for pattern in "${DEFERRAL_PATTERNS[@]}"; do
  matches=$(echo "$ASSISTANT_TEXT" | LC_ALL=C grep -E -i -n --no-messages "$pattern" 2>/dev/null | head -3)
  if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l)
    TOTAL_COUNT=$((TOTAL_COUNT + count))
    echo "$matches" | while IFS= read -r line; do
      truncated="${line:0:200}"
      [[ ${#line} -gt 200 ]] && truncated="${truncated}..."
      printf -- "- (%s) %s\n" "$pattern" "$truncated" >> "$TMP_MATCHES"
    done
  fi
done

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  exit 0
fi

# ============================================================
# Check whether last assistant message contains the required heading
# ============================================================

LAST_HAS_HEADING=0
if echo "$LAST_ASSISTANT" | LC_ALL=C grep -F -q "$REQUIRED_HEADING" 2>/dev/null; then
  LAST_HAS_HEADING=1
fi

if [[ "$LAST_HAS_HEADING" -eq 1 ]]; then
  # Verify the section has at least one bullet under it
  BULLETS_AFTER_HEADING=$(echo "$LAST_ASSISTANT" | awk -v h="$REQUIRED_HEADING" '
    index($0, h) { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^[[:space:]]*[-*] / { print }
  ' | wc -l)
  if [[ "$BULLETS_AFTER_HEADING" -gt 0 ]]; then
    exit 0
  fi
fi

# ============================================================
# BLOCK — final message lacks the required deferrals section
# ============================================================

DEFERRAL_LIST=$(cat "$TMP_MATCHES" | head -30)
TRUNCATED_NOTE=""
if [[ "$TOTAL_COUNT" -gt 30 ]]; then
  TRUNCATED_NOTE=" (showing first 30 of $TOTAL_COUNT)"
fi

BLOCKER_MSG="Session has $TOTAL_COUNT deferral references but your final user-facing message does NOT include the required '$REQUIRED_HEADING' section. The user only reliably reads end-of-effort text — middle-of-work deferrals get buried. Add the section to your next response with one bullet per deferral, then re-attempt Stop. Suppress with DEFERRAL_COUNTER_DISABLE=1 if this is a harness-development session where deferrals are inherent (e.g., editing the synonym list itself)."

echo "{\"result\": \"error\", \"message\": \"$BLOCKER_MSG\"}"
echo "" >&2
echo "================================================================" >&2
echo "DEFERRAL COUNTER (A5): SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2
echo "Deferrals detected${TRUNCATED_NOTE}:" >&2
echo "" >&2
echo "$DEFERRAL_LIST" >&2
echo "" >&2
echo "Add this section to your final response (paste verbatim and fill in):" >&2
echo "" >&2
echo "    $REQUIRED_HEADING" >&2
echo "    " >&2
echo "    - <verbatim deferral 1 — what you didn't do, and why>" >&2
echo "    - <verbatim deferral 2>" >&2
echo "    ..." >&2
echo "" >&2
exit 1
