#!/bin/bash
# run-drill.sh — O.8 estate-coordination drill (specs-o §O.8 Done-when).
#
# Proves the classification + re-homing steps described in
# skills/coordinate-estate.md against a SEEDED stale-session fixture:
#   - stale-session-heartbeat.json: a dead heartbeat (C1 shape, frozen contract
#     specs-o §O.0.3) — last_activity_ts far in the past, pid not alive.
#   - stale-session-transcript.jsonl: a transcript whose LAST line is an
#     unanswered permission_request (the wedged-undeliverable terminal shape,
#     per the skill's Step 2 classification rules) with nothing after it.
#
# This drill does NOT depend on O.2's heartbeat-lib (not yet built in this
# batch — O.8 is file-disjoint, dispatched in the same batch as O.2, no
# ordering guarantee). It re-implements the two classification checks the
# skill documents in bash, directly against the fixture files, so it stands
# alone. When O.2/O.3 land, `nl status`/`hb_classify` become the live oracle
# for the SAME rule; this drill's checks are the mechanical pre-registration
# of that rule's expected verdict on this exact fixture (regression anchor).
#
# Usage: bash run-drill.sh
# Exit: 0 on all assertions passing, 1 otherwise (rc captured directly, no
# pipe — specs-o §O.0.1-6).
#
# Sandboxing: NL_ISSUES_PATH is overridden to a fixture-local sandbox file for
# THIS run only — never touches the real ~/.claude/state/nl-issues.jsonl or
# a repo docs/backlog.md (specs-o §O.0.1-3).

set -u

_DRILL_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
HEARTBEAT_FIXTURE="$_DRILL_SELF_DIR/stale-session-heartbeat.json"
TRANSCRIPT_FIXTURE="$_DRILL_SELF_DIR/stale-session-transcript.jsonl"

# nl-issue.sh lives at adapters/claude-code/scripts/nl-issue.sh; this fixture
# is at adapters/claude-code/tests/fixtures/wave-o/O.8/ — five levels up to
# adapters/claude-code/, then into scripts/.
NLI_BIN="$_DRILL_SELF_DIR/../../../../scripts/nl-issue.sh"

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

echo "O.8 estate-coordination drill: seeded stale-session fixture"

if [[ ! -f "$HEARTBEAT_FIXTURE" ]]; then
  fail "heartbeat fixture missing at $HEARTBEAT_FIXTURE"
  echo "drill summary: $PASSED passed, $FAILED failed"
  exit 1
fi
if [[ ! -f "$TRANSCRIPT_FIXTURE" ]]; then
  fail "transcript fixture missing at $TRANSCRIPT_FIXTURE"
  echo "drill summary: $PASSED passed, $FAILED failed"
  exit 1
fi
if [[ ! -x "$NLI_BIN" ]] && [[ ! -f "$NLI_BIN" ]]; then
  fail "nl-issue.sh not found at $NLI_BIN"
  echo "drill summary: $PASSED passed, $FAILED failed"
  exit 1
fi

# ------------------------------------------------------------
# Step A: classify via the heartbeat fixture (C1 shape, dead-pid + stale ts).
# ------------------------------------------------------------
echo "Step A: heartbeat-shape classification (dead pid + stale last_activity_ts)"

HB_PID="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$HEARTBEAT_FIXTURE")"
HB_TS="$(sed -n 's/.*"last_activity_ts":"\([^"]*\)".*/\1/p' "$HEARTBEAT_FIXTURE")"
HB_MARKER="$(sed -n 's/.*"marker_state":"\([^"]*\)".*/\1/p' "$HEARTBEAT_FIXTURE")"

if [[ -n "$HB_PID" ]] && ! kill -0 "$HB_PID" 2>/dev/null; then
  pass "fixture pid $HB_PID is not alive (crashed-shape signal per C1)"
else
  fail "fixture pid $HB_PID unexpectedly alive or unparseable — fixture must simulate a dead process"
fi

HB_EPOCH="$(date -u -d "$HB_TS" '+%s' 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$HB_TS" '+%s' 2>/dev/null || echo 0)"
NOW_EPOCH="$(date -u '+%s')"
if [[ "$HB_EPOCH" -gt 0 ]]; then
  AGE_MIN=$(( (NOW_EPOCH - HB_EPOCH) / 60 ))
else
  AGE_MIN=0
fi
# C1 staleness rule: now - last_activity_ts > OBS_STALE_MIN (default 30).
OBS_STALE_MIN="${OBS_STALE_MIN:-30}"
if [[ "$AGE_MIN" -gt "$OBS_STALE_MIN" ]]; then
  pass "fixture last_activity_ts is ${AGE_MIN}min old (> OBS_STALE_MIN=${OBS_STALE_MIN}min) -> stale per C1"
else
  fail "fixture timestamp is only ${AGE_MIN}min old — fixture must be older than OBS_STALE_MIN=${OBS_STALE_MIN}"
fi

if [[ "$HB_MARKER" == "CONTINUING" ]]; then
  pass "fixture marker_state is CONTINUING (a live-looking marker on a dead session — the exact false-resume risk this classification exists to catch)"
else
  fail "expected marker_state CONTINUING in fixture, got '$HB_MARKER'"
fi

# ------------------------------------------------------------
# Step B: classify via the transcript fixture (terminal state = unanswered
# permission_request, nothing after it -> wedged-undeliverable per the
# skill's Step 2 rule #4).
# ------------------------------------------------------------
echo "Step B: transcript-shape classification (terminal state = pending permission dialog)"

LAST_LINE="$(tail -n 1 "$TRANSCRIPT_FIXTURE")"
if printf '%s' "$LAST_LINE" | grep -q '"subtype":"permission_request"'; then
  pass "transcript's LAST line is an unanswered permission_request (nothing after it)"
else
  fail "expected transcript's last line to be a permission_request, got: $LAST_LINE"
fi

CLASSIFICATION="unknown"
if printf '%s' "$LAST_LINE" | grep -q '"subtype":"permission_request"'; then
  CLASSIFICATION="wedged-undeliverable"
fi
if [[ "$CLASSIFICATION" == "wedged-undeliverable" ]]; then
  pass "combined classification = wedged-undeliverable (dead heartbeat + unanswered dialog terminal state)"
else
  fail "expected classification wedged-undeliverable, computed '$CLASSIFICATION'"
fi

# ------------------------------------------------------------
# Step C: re-home the orphan task via nl-issue.sh into a SANDBOXED ledger.
# ------------------------------------------------------------
echo "Step C: orphan re-homing (nl-issue.sh, sandboxed NL_ISSUES_PATH)"

DRILL_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'o8drill')"
trap 'rm -rf "$DRILL_TMP"' EXIT
SANDBOX_LEDGER="$DRILL_TMP/nl-issues-sandbox.jsonl"

HB_SID="$(sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' "$HEARTBEAT_FIXTURE")"
HB_BRANCH="$(sed -n 's/.*"branch":"\([^"]*\)".*/\1/p' "$HEARTBEAT_FIXTURE")"
ORPHAN_NOTE="orphaned from wedged session ${HB_SID}: fix the scope-gate false-hatch bug (branch ${HB_BRANCH})"

( export NL_ISSUES_PATH="$SANDBOX_LEDGER"; bash "$NLI_BIN" "$ORPHAN_NOTE" >/dev/null )
rc=$?

if [[ "$rc" == "0" ]]; then
  pass "nl-issue.sh exited 0 on the re-homing append"
else
  fail "nl-issue.sh exited $rc on the re-homing append"
fi

if [[ -f "$SANDBOX_LEDGER" ]]; then
  LINE_COUNT="$(wc -l < "$SANDBOX_LEDGER" 2>/dev/null | tr -d ' ')"
  if [[ "$LINE_COUNT" == "1" ]]; then
    pass "exactly ONE nl-issue line landed in the sandboxed ledger"
  else
    fail "expected exactly 1 line in sandbox ledger, got $LINE_COUNT"
  fi
  if grep -q "$HB_SID" "$SANDBOX_LEDGER" 2>/dev/null; then
    pass "the landed line names the orphaned session id ($HB_SID)"
  else
    fail "landed line does not mention session id $HB_SID: $(cat "$SANDBOX_LEDGER" 2>/dev/null)"
  fi
  if grep -q '"triage_status":"untriaged"' "$SANDBOX_LEDGER" 2>/dev/null; then
    pass "the landed line is untriaged (awaiting the weekly triage pass)"
  else
    fail "landed line missing untriaged status: $(cat "$SANDBOX_LEDGER" 2>/dev/null)"
  fi
else
  fail "sandbox ledger $SANDBOX_LEDGER was never created"
fi

# Confirm the REAL machine-wide ledger and this repo's real backlog were
# never touched by this drill (sandboxing proof, mirrors nl-issue.sh's own
# self-test Scenario 9 discipline).
REAL_LEDGER="${HOME:-}/.claude/state/nl-issues.jsonl"
if [[ -f "$REAL_LEDGER" ]]; then
  if ! grep -qF "$ORPHAN_NOTE" "$REAL_LEDGER" 2>/dev/null; then
    pass "the REAL ~/.claude/state/nl-issues.jsonl was not touched by this drill"
  else
    fail "the drill's orphan note leaked into the REAL ledger at $REAL_LEDGER"
  fi
else
  pass "no real ledger present to pollute (nothing to check further)"
fi

echo ""
echo "drill summary: $PASSED passed, $FAILED failed"
if [[ "$FAILED" == "0" ]]; then
  exit 0
else
  exit 1
fi
