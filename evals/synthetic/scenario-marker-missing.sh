#!/usr/bin/env bash
# Synthetic Scenario: marker-missing
#
# Exercises session-honesty-gate.sh's marker-format check (condition a):
# the final assistant message's last non-empty line must carry EXACTLY
# ONE marker of DONE: / PAUSING: / BLOCKED: / CONTINUING:. Bad case: the
# final message has no marker at all -> gate BLOCKS (rc 2). Good case:
# the final message ends with a single valid marker -> gate ALLOWS
# (rc 0).
#
# Invocation contract (verified against the gate's own --self-test
# fixtures): Stop hook, invoked with a JSON payload piped via stdin:
# {"transcript_path":"<jsonl>","session_id":"<sid>"}. The transcript is a
# JSONL file of assistant/user events; the gate reads the LAST assistant
# message's text. Exit 0 = allowed, exit 2 = blocked.
#
# Expected: bad case (no marker) blocked (rc 2); good case (single DONE:
# marker on the last line) allowed (rc 0).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$NL_ROOT/adapters/claude-code/hooks/session-honesty-gate.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: session-honesty-gate.sh not found at $GATE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for this scenario"
  exit 1
fi

FAILS=0

# Writes a synthetic transcript JSONL whose final assistant message is
# the given text. Echoes the transcript path.
_write_transcript() {
  local dir="$1" text="$2"
  local tfile="$dir/transcript.jsonl"
  : > "$tfile"
  printf '%s\n' "$(jq -cn --arg t "please proceed" '{"type":"user","message":{"role":"user","content":[{"type":"text","text":$t}]}}')" >> "$tfile"
  printf '%s\n' "$(jq -cn --arg t "$text" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":$t}]}}')" >> "$tfile"
  echo "$tfile"
}

_run_gate() {
  local transcript="$1" sid="$2" tmp="$3"
  local input
  input=$(jq -cn --arg t "$transcript" --arg s "$sid" '{"transcript_path":$t,"session_id":$s}')
  (
    export HARNESS_SELFTEST=1
    export SIGNAL_LEDGER_PATH="$tmp/ledger.jsonl"
    export RETRY_GUARD_STATE_DIR="$tmp/.claude/state"
    export RETRY_GUARD_THRESHOLD=3
    unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
    printf '%s' "$input" | CLAUDE_SESSION_ID="$sid" bash "$GATE" >/dev/null 2>"$tmp/err.txt"
  )
  echo $?
}

# ---- Bad case: final message has no marker at all ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
mkdir -p "$BAD_DIR/.claude/state"
TRANSCRIPT=$(_write_transcript "$BAD_DIR" $'Investigated the issue and made some changes.\n\nLet me know if you want me to keep going.')

RC=$(_run_gate "$TRANSCRIPT" "sess-marker-missing-bad" "$BAD_DIR")
if [[ "$RC" == "2" ]]; then
  echo "PASS: final message with no marker was correctly blocked (rc=$RC)"
else
  echo "FAIL: final message with no marker should have been blocked (rc=$RC, expected 2)"
  echo "--- gate stderr ---"
  cat "$BAD_DIR/err.txt" 2>/dev/null
  FAILS=$((FAILS + 1))
fi

# ---- Good case: final message ends with exactly one valid marker ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
mkdir -p "$GOOD_DIR/.claude/state"
TRANSCRIPT=$(_write_transcript "$GOOD_DIR" $'Investigated the issue and shipped the fix.\n\nDONE: fixed the null-pointer bug, merged abc1234')

RC=$(_run_gate "$TRANSCRIPT" "sess-marker-missing-good" "$GOOD_DIR")
if [[ "$RC" == "0" ]]; then
  echo "PASS: final message with a single valid marker was correctly allowed (rc=$RC)"
else
  echo "FAIL: final message with a single valid marker should have been allowed (rc=$RC, expected 0)"
  echo "--- gate stderr ---"
  cat "$GOOD_DIR/err.txt" 2>/dev/null
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-marker-missing: ALL PASSED"
  exit 0
fi
echo "scenario-marker-missing: $FAILS FAILURE(S)"
exit 1
