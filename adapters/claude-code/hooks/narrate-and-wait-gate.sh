#!/bin/bash
# narrate-and-wait-gate.sh — Stop hook
#
# Detects the "narrate-and-wait" anti-pattern where the agent stops
# mid-autonomous-work to narrate progress and implicitly wait for user
# confirmation, instead of continuing. Blocks session end when:
#
#   1. The user has established a keep-going / autonomous directive
#      somewhere in the session transcript.
#   2. The FINAL assistant message trails off with a narrate-and-wait
#      phrase (question, permission-seeking, "let me know if you want").
#
# This is the mechanical counterpart to a repeated behavioral failure:
# the agent treats each work-unit boundary as a natural pause point,
# even when the user has said "keep going" multiple times. A Stop hook
# catches the symptom at the last possible moment — if the agent is
# about to stop, force it to reconsider whether stopping is actually
# authorized.
#
# Escape hatches:
#
#   - If the user's most recent message AFTER establishing keep-going
#     is itself a "stop" / "pause" / "that's enough" directive, the
#     hook allows termination (user has revoked the directive).
#   - If the agent creates .claude/state/autonomous-done-YYYY-MM-DD-HHMM.txt
#     with a one-line justification, the hook allows termination
#     (genuine completion; no more work authorized).
#
# Exit codes:
#   0 — session may terminate
#   2 — session is blocked; stderr explains why and JSON decision is
#       emitted on stdout per Claude Code Stop-hook contract.

set -u

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
fi

# No transcript → no-op. Better to let session end than block falsely.
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't distinguish roles; don't block on best-effort text scan.
  exit 0
fi

# --- Step 1: look for a keep-going directive from the user in this session ---
# These are phrases the user has explicitly used to say "don't pause, don't
# wait for me, just keep working." If none are present, we don't enforce
# anything — the user might actually want a pause between work units.
KEEP_GOING_PATTERNS=(
  'keep going'
  'keep-going'
  'don.?t stop'
  'don.?t wait'
  'don.?t pause'
  'stop stopping'
  'why do you keep stopping'
  'why did you stop'
  'are you still working'
  'are you actually (continuing|working)'
  'just continue'
  'please continue'
  'full auto'
  'full-auto'
  'autonomous'
  'do not pause'
  'do not stop'
  'do not wait'
  'no need to (check|ask|confirm)'
)

# Extract user messages only.
USER_TEXT=$(jq -r 'select(.role == "user" or .message.role == "user") | (.content // .text // .message.content // empty) | if type == "string" then . else (. | tostring) end' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

if [[ -z "$USER_TEXT" ]]; then
  exit 0
fi

DIRECTIVE_FOUND=0
for pattern in "${KEEP_GOING_PATTERNS[@]}"; do
  if echo "$USER_TEXT" | grep -iqE "$pattern"; then
    DIRECTIVE_FOUND=1
    break
  fi
done

# No keep-going directive → respect natural pause. Exit clean.
if [[ "$DIRECTIVE_FOUND" -eq 0 ]]; then
  exit 0
fi

# --- Step 2: check whether the user has REVOKED the directive ---
# If the user's most recent message is a stop / pause / that's enough
# instruction, the directive is revoked and we allow termination.
LAST_USER=$(jq -r 'select(.role == "user" or .message.role == "user") | (.content // .text // .message.content // empty) | if type == "string" then . else (. | tostring) end' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

REVOKE_PATTERNS=(
  "that.?s enough"
  "^stop( now|\.| here|,)"
  "[^t] stop now"
  "please stop"
  "stop for now"
  "let.?s stop"
  "take a break"
  "call it (here|a day|a night|for (now|today))"
  "we.?re done"
  "good stopping point"
  "pause here"
  "hold (on|up)"
  "can we pause"
)

for pattern in "${REVOKE_PATTERNS[@]}"; do
  if echo "$LAST_USER" | grep -iqE "$pattern"; then
    # Additional guardrail: "don't stop" / "never stop" must NOT count.
    if echo "$LAST_USER" | grep -iqE "don.?t stop|never stop|not stop|no need to stop"; then
      continue
    fi
    exit 0
  fi
done

# --- Step 3: extract the FINAL assistant turn and check for narrate-and-wait ---
# We only want the LAST assistant message — earlier messages may legitimately
# end with questions that the user has since addressed.
LAST_ASSISTANT=$(jq -r 'select(.role == "assistant" or .message.role == "assistant") | (.content // .text // .message.content // empty) | if type == "string" then . else (. | tostring) end' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

if [[ -z "$LAST_ASSISTANT" ]]; then
  exit 0
fi

# Focus on the trailing 500 characters — that's where narrate-and-wait
# phrases cluster (closing sentences). A long message body may legitimately
# contain questions that are discussed and resolved within the same turn.
TRAILING=$(echo "$LAST_ASSISTANT" | tail -c 600)

# Narrate-and-wait phrases. Each is a pattern that signals the agent is
# stopping to seek permission or narrate a decision point instead of
# continuing.
WAIT_PATTERNS=(
  'want me to (continue|proceed|go ahead|move on)'
  'would you like me to'
  'do you want me to'
  'shall I (continue|proceed|go ahead)'
  'should I (continue|proceed|go ahead|move on)'
  'let me know (if|when|what)'
  'ready to (continue|proceed|move on) when'
  'awaiting (your|confirmation|approval|go)'
  'waiting (for|on) your'
  'once you (confirm|approve|give|say)'
  'if you.?d like me to'
  'if you want me to'
  'next step.? would be'
  'what.?s next[?.]?\s*$'
  'any thoughts[?.]?\s*$'
  'thoughts[?.]?\s*$'
  'sound good[?.]?\s*$'
  'does that (work|sound)'
  'please (confirm|advise|let me know)'
  'let me know (how|if) you.?d like to proceed'
)

MATCHED_PHRASE=""
for pattern in "${WAIT_PATTERNS[@]}"; do
  match=$(echo "$TRAILING" | grep -iEo "$pattern" | head -1)
  if [[ -n "$match" ]]; then
    MATCHED_PHRASE="$match"
    break
  fi
done

if [[ -z "$MATCHED_PHRASE" ]]; then
  # No narrate-and-wait phrase in the tail. Session ends clean.
  exit 0
fi

# --- Step 4: check attestation escape hatch ---
ATTEST_DIR=".claude/state"
if [[ -d "$ATTEST_DIR" ]]; then
  if find "$ATTEST_DIR" -type f -name 'autonomous-done-*.txt' -newermt '30 minutes ago' 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# --- BLOCK ---
TRAIL_PREVIEW=$(echo "$TRAILING" | tr '\n' ' ' | tail -c 300)

cat >&2 <<MSG
================================================================
NARRATE-AND-WAIT GATE — BLOCKED
================================================================

The user has established a keep-going / autonomous directive in
this session, but your final message ends with a narrate-and-wait
phrase instead of continuing work.

Matched phrase (tail of last assistant message):
  "$MATCHED_PHRASE"

Trailing context:
  ...${TRAIL_PREVIEW}

Before the session can end, do ONE of:

  1. CONTINUE. If there's remaining work authorized by the plan,
     backlog, or the user's standing directive, pick the next
     concrete item and keep working. The user has explicitly said
     not to stop between work units.

  2. REPORT COMPLETION. If the authorized work is genuinely done,
     say so explicitly — not with a question, but with a clear
     "all authorized work complete" status. Cite the plan file or
     backlog items that were addressed. Then create
     .claude/state/autonomous-done-YYYY-MM-DD-HHMM.txt with a
     one-line justification (what scope was completed). The
     state directory is gitignored; create it if needed.

  3. BLOCKED. If you've hit a genuine blocker (missing credentials,
     ambiguous product decision, dependency on another person),
     describe the blocker with enough detail that a future session
     can pick it up cold. A blocker is not the same as "next logical
     step is X — want me to do it?"

Do NOT simply rephrase the same narrate-and-wait message. The
rule exists because rephrased permission-seeking is still
permission-seeking.

See: ~/.claude/rules/orchestrator-pattern.md ("The main session is
lean, not idle") and the user's repeated feedback in this session
memory about narrate-and-wait as a failure mode.

================================================================
MSG

cat <<'JSON'
{"decision": "block", "reason": "Narrate-and-wait gate: user established a keep-going directive but the final message trails off with a permission-seeking / wait-for-confirmation phrase. Continue, explicitly report completion, or describe a concrete blocker. See stderr for details."}
JSON

exit 2
