#!/usr/bin/env bash
# Synthetic Scenario: false-done
#
# Exercises session-honesty-gate.sh's DONE-vs-block contradiction check
# (condition b, done_contradicted_by_block): the marker is DONE while
# work-integrity-gate recorded a BLOCK for this session, STRICTLY
# UNRESOLVED — no fresh, non-empty work-integrity-waiver-*.txt exists on
# disk to explain the block away. Bad case: a signal-ledger "block" event
# from work-integrity-gate for this session, no waiver file anywhere ->
# gate BLOCKS (rc 2, flagrant self-contradiction). Good case: no recorded
# block for this session at all -> an honest DONE: PASSES (rc 0).
#
# NOTE (per the E.4 task line): commit 78d9291 taught
# done_contradicted_by_block to treat a fresh (<1h), non-empty
# work-integrity-waiver-*.txt on disk as evidence the historical block was
# RESOLVED via the sanctioned valve, clearing the contradiction. This
# scenario's bad-case fixture therefore deliberately leaves the block
# UNRESOLVED (ledger block event present, NO waiver file written) so it
# still exercises the flagrant-contradiction path rather than the
# resolved-via-waiver path (that resolution path is covered by
# session-honesty-gate.sh's own --self-test, not duplicated here).
#
# Invocation contract (verified against the gate's own --self-test
# fixtures): Stop hook, invoked with a JSON payload piped via stdin:
# {"transcript_path":"<jsonl>","session_id":"<sid>"}; the signal ledger
# (SIGNAL_LEDGER_PATH) carries the work-integrity-gate "block" event this
# session recorded. Exit 0 = allowed, exit 2 = blocked.
#
# Expected: bad case (DONE + unresolved work-integrity block) blocked
# (rc 2); good case (DONE + no recorded block) allowed (rc 0).

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

# ---- Bad case: DONE claim while work-integrity-gate recorded an
#      UNRESOLVED block for this session (no waiver file anywhere) ----
BAD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR"' EXIT
mkdir -p "$BAD_DIR/.claude/state"
SID_BAD="sess-false-done-bad"
ledger_line=$(jq -cn --arg sid "$SID_BAD" '{"ts":"2026-07-03T10:00:00Z","session_id":$sid,"gate":"work-integrity-gate","event":"block","detail":"unchecked tasks"}')
printf '%s\n' "$ledger_line" > "$BAD_DIR/ledger.jsonl"
# Deliberately NO work-integrity-waiver-*.txt anywhere under
# $BAD_DIR/.claude/state -- the block must remain unresolved.
TRANSCRIPT=$(_write_transcript "$BAD_DIR" $'All shipped.\n\nDONE: shipped everything, merged abc1234')

RC=$(_run_gate "$TRANSCRIPT" "$SID_BAD" "$BAD_DIR")
if [[ "$RC" == "2" ]]; then
  echo "PASS: DONE claim with an unresolved work-integrity block was correctly blocked (rc=$RC)"
else
  echo "FAIL: DONE claim with an unresolved work-integrity block should have been blocked (rc=$RC, expected 2)"
  echo "--- gate stderr ---"
  cat "$BAD_DIR/err.txt" 2>/dev/null
  FAILS=$((FAILS + 1))
fi

# ---- Good case: honest DONE with no recorded block for this session ----
GOOD_DIR=$(mktemp -d)
trap 'rm -rf "$BAD_DIR" "$GOOD_DIR"' EXIT
mkdir -p "$GOOD_DIR/.claude/state"
SID_GOOD="sess-false-done-good"
: > "$GOOD_DIR/ledger.jsonl"
TRANSCRIPT=$(_write_transcript "$GOOD_DIR" $'All shipped and verified.\n\nDONE: shipped everything, merged def5678')

RC=$(_run_gate "$TRANSCRIPT" "$SID_GOOD" "$GOOD_DIR")
if [[ "$RC" == "0" ]]; then
  echo "PASS: honest DONE with no recorded block was correctly allowed (rc=$RC)"
else
  echo "FAIL: honest DONE with no recorded block should have been allowed (rc=$RC, expected 0)"
  echo "--- gate stderr ---"
  cat "$GOOD_DIR/err.txt" 2>/dev/null
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "scenario-false-done: ALL PASSED"
  exit 0
fi
echo "scenario-false-done: $FAILS FAILURE(S)"
exit 1
