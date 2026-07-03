#!/bin/bash
# tool-call-budget.sh — Generation 5 (team-aware + deferred-audit)
#
# PreToolUse hook that enforces a mid-session attention-decay mitigation.
#
# Two modes:
#
# 1. SOLO MODE (no team config matches current session):
#    Counter keyed by CLAUDE_SESSION_ID. At counter == 30, blocks the next
#    tool call until the builder invokes plan-evidence-reviewer to audit
#    work-so-far. Acknowledged via `--ack`. This is the original behavior
#    from Gen 4 and is unchanged for backwards compatibility.
#
# 2. AGENT-TEAM MODE (current session is a member of a team per
#    ~/.claude/teams/<team>/config.json):
#    Counter is keyed by team_name (so all teammates contribute to the
#    same counter). At counter == 30, INSTEAD of blocking, the hook
#    writes a flag at ~/.claude/state/audit-pending.<team> with the
#    current task_id and timestamp. The flag is consumed by the
#    TaskCompleted hook (task-completed-evidence-gate.sh) which runs
#    plan-evidence-reviewer before allowing the task to complete.
#
#    Hard ceiling: a per-teammate sub-counter at
#    ~/.claude/state/tool-call-since-task.<session_id> tracks calls
#    since the last TaskCompleted clearing event. If a single teammate
#    accumulates >= 90 calls without an intervening clear, mid-stream
#    blocking returns. This catches runaway-task drift while leaving
#    normal-length tasks uninterrupted.
#
# Acknowledgment protocol (solo mode):
#   - The builder must invoke plan-evidence-reviewer via the Task tool.
#   - The reviewer writes its output to a file in $STATE_DIR/reviews/.
#   - `--ack` only succeeds if a reviewer output file exists that was
#     created in the last 5 minutes AND contains specific sentinel lines
#     (REVIEW COMPLETE + VERDICT: ...).
#
# Concurrency: counter increments are protected by flock(1) when
# available, with a PID-keyed fallback for environments without flock
# (Windows Git Bash without msys flock package). The fallback isn't
# perfect but covers the common-case race.
#
# Matcher scope: wired to Edit|Write|Bash only. Passive exploration
# doesn't burn budget — only actions that modify state or spawn
# subprocesses count.

set -u

STATE_DIR="$HOME/.claude/state"
REVIEW_DIR="$STATE_DIR/reviews"
TEAMS_DIR="$HOME/.claude/teams"
mkdir -p "$STATE_DIR" "$REVIEW_DIR" 2>/dev/null

SESSION_ID="${CLAUDE_SESSION_ID:-${PPID:-$$}}"

# ============================================================
# resolve_effective_session_id
# ============================================================
# If the current CLAUDE_SESSION_ID matches a member.session_id in any
# ~/.claude/teams/<team>/config.json, returns the team_name. Otherwise
# echoes the raw session id (solo mode).
#
# The team config schema follows Anthropic's documented shape:
#   { "team_name": "...", "members": [ { "session_id": "..." }, ... ] }
# If the schema differs at runtime, falls back to per-session.
resolve_effective_session_id() {
  local sid="$SESSION_ID"
  local override_dir="${TEAMS_DIR_OVERRIDE:-$TEAMS_DIR}"
  if [ -z "$sid" ]; then
    echo ""
    return
  fi
  if [ ! -d "$override_dir" ]; then
    echo "$sid"
    return
  fi
  # Iterate teams; any match wins (first found)
  shopt -s nullglob 2>/dev/null
  for team_config in "$override_dir"/*/config.json; do
    [ -f "$team_config" ] || continue
    if command -v jq >/dev/null 2>&1; then
      if jq -e --arg sid "$sid" '.members[]? | select(.session_id == $sid)' "$team_config" >/dev/null 2>&1; then
        local team_name
        team_name=$(jq -r '.team_name // empty' "$team_config" 2>/dev/null)
        if [ -n "$team_name" ]; then
          # Sanitize team_name for filename safety: alphanumeric + dash + underscore only.
          # Use printf (no trailing newline) to avoid sanitizing \n into _.
          team_name=$(printf '%s' "$team_name" | tr -c '[:alnum:]_-' '_' | cut -c1-64)
          printf '%s' "$team_name"
          return
        fi
      fi
    else
      # Fallback grep heuristic if jq missing (less reliable)
      if grep -q "\"session_id\"[[:space:]]*:[[:space:]]*\"$sid\"" "$team_config" 2>/dev/null; then
        local team_name
        team_name=$(grep -oE '"team_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$team_config" | head -1 | sed -E 's/.*"team_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        if [ -n "$team_name" ]; then
          team_name=$(printf '%s' "$team_name" | tr -c '[:alnum:]_-' '_' | cut -c1-64)
          printf '%s' "$team_name"
          return
        fi
      fi
    fi
  done
  echo "$sid"
}

# ============================================================
# atomic_increment_counter <counter_file>
# ============================================================
# Atomically reads, increments, and writes the counter. Uses flock(1)
# when available; otherwise PID-keyed lock with brief busy-wait.
#
# Echoes the new (post-increment) value on stdout.
atomic_increment_counter() {
  local counter_file="$1"
  local new_value=0

  if command -v flock >/dev/null 2>&1; then
    # flock is available: use it
    # We lock on the counter file directly (creating it as the lock target).
    # -w 5: wait up to 5s for the lock; -x: exclusive
    touch "$counter_file" 2>/dev/null
    {
      flock -w 5 -x 200
      local current
      current=$(cat "$counter_file" 2>/dev/null || echo "0")
      [[ "$current" =~ ^[0-9]+$ ]] || current=0
      new_value=$((current + 1))
      echo "$new_value" > "$counter_file"
    } 200>"$counter_file"
  else
    # PID-keyed fallback: write our PID to <file>.lock; if we lose the
    # race, briefly busy-wait. Stale locks (>10s) are stolen.
    local lock_file="${counter_file}.lock"
    local self_pid=$$
    local attempts=0
    local max_attempts=50  # 50 * 100ms = 5s
    while [ $attempts -lt $max_attempts ]; do
      if (set -o noclobber; echo "$self_pid" > "$lock_file") 2>/dev/null; then
        # We got the lock
        break
      fi
      # Lock exists; check staleness
      local lock_holder
      lock_holder=$(cat "$lock_file" 2>/dev/null || echo "")
      local lock_mtime
      lock_mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo 0)
      local now_secs
      now_secs=$(date +%s)
      if [ $((now_secs - lock_mtime)) -gt 10 ]; then
        # Stale; steal it
        echo "$self_pid" > "$lock_file" 2>/dev/null
        break
      fi
      sleep 0.1 2>/dev/null || sleep 1
      attempts=$((attempts + 1))
    done
    # Critical section
    local current
    current=$(cat "$counter_file" 2>/dev/null || echo "0")
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    new_value=$((current + 1))
    echo "$new_value" > "$counter_file"
    # Release lock if we own it
    if [ "$(cat "$lock_file" 2>/dev/null || echo "")" = "$self_pid" ]; then
      rm -f "$lock_file" 2>/dev/null
    fi
  fi

  echo "$new_value"
}

# ============================================================
# write_audit_flag <team>
# ============================================================
# Writes ~/.claude/state/audit-pending.<team> with task_id + timestamp.
# Idempotent: if the flag already exists, doesn't overwrite (preserves
# the original task_id/timestamp from the first 30-call milestone).
write_audit_flag() {
  local team="$1"
  local flag_file="$STATE_DIR/audit-pending.${team}"
  if [ -f "$flag_file" ]; then
    return 0  # already pending
  fi
  local task_id="${CLAUDE_TASK_ID:-${TASK_ID:-unknown}}"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
  cat > "$flag_file" <<EOF
{
  "task_id": "$task_id",
  "team_name": "$team",
  "session_id": "$SESSION_ID",
  "timestamp": "$timestamp",
  "reason": "tool-call counter reached 30 in agent-team mode"
}
EOF
}

# ============================================================
# Main hook logic
# ============================================================

# Allow override of teams dir for testing
TEAMS_DIR_OVERRIDE="${TEAMS_DIR_OVERRIDE:-}"
# Allow override of state dir for testing
if [ -n "${STATE_DIR_OVERRIDE:-}" ]; then
  STATE_DIR="$STATE_DIR_OVERRIDE"
  REVIEW_DIR="$STATE_DIR/reviews"
  mkdir -p "$STATE_DIR" "$REVIEW_DIR" 2>/dev/null
fi

EFFECTIVE_ID=$(resolve_effective_session_id)
if [ -z "$EFFECTIVE_ID" ]; then
  EFFECTIVE_ID="$$"
fi

COUNTER_FILE="$STATE_DIR/tool-call-count.$EFFECTIVE_ID"
ACK_FILE="$STATE_DIR/audit-ack.$EFFECTIVE_ID"
SUB_COUNTER_FILE="$STATE_DIR/tool-call-since-task.$SESSION_ID"

# Determine mode: agent-team if EFFECTIVE_ID differs from raw SESSION_ID
IS_TEAM_MODE=0
if [ "$EFFECTIVE_ID" != "$SESSION_ID" ]; then
  IS_TEAM_MODE=1
fi

# ============================================================
# --ack: builder ran the audit and is acknowledging (solo mode only;
# in team mode, TaskCompleted hook handles flag clearing instead)
# ============================================================
if [[ "${1:-}" == "--ack" ]]; then
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

# ============================================================
# --self-test: exercise scenarios
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d 2>/dev/null || mktemp -d -t toolcallbudget)
  if [[ -z "$TMPDIR_SELFTEST" ]] || [[ ! -d "$TMPDIR_SELFTEST" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT

  SCRIPT_PATH="${BASH_SOURCE[0]}"
  case "$SCRIPT_PATH" in
    /*) ;;
    [A-Za-z]:[/\\]*) ;;
    *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
  esac

  PASSED=0
  FAILED=0

  # Synthetic state + teams dirs for the test
  SYN_STATE="$TMPDIR_SELFTEST/state"
  SYN_TEAMS="$TMPDIR_SELFTEST/teams"
  mkdir -p "$SYN_STATE" "$SYN_STATE/reviews" "$SYN_TEAMS"

  # Helper: write a synthetic team config
  # $1 = team_name, $2... = session_ids of members
  write_team_config() {
    local tname="$1"; shift
    local tdir="$SYN_TEAMS/$tname"
    mkdir -p "$tdir"
    {
      echo "{"
      echo "  \"team_name\": \"$tname\","
      echo "  \"members\": ["
      local first=1
      for sid in "$@"; do
        if [ $first -eq 1 ]; then
          first=0
        else
          echo "    ,"
        fi
        echo "    { \"session_id\": \"$sid\" }"
      done
      echo "  ]"
      echo "}"
    } > "$tdir/config.json"
  }

  # Helper: run hook with given env, capture exit + stderr
  run_hook() {
    # All args become env-var assignments (KEY=val) before the call
    local env_assigns=("$@")
    (
      for a in "${env_assigns[@]}"; do
        export "$a"
      done
      bash "$SCRIPT_PATH" </dev/null 2>/dev/null
    )
    echo $?
  }

  expect_exit_with_stderr() {
    local desc="$1"; shift
    local expected="$1"; shift
    local stderr_pattern="$1"; shift
    # remaining args = env vars
    local actual_exit
    local actual_stderr
    actual_stderr=$(
      for a in "$@"; do
        export "$a"
      done
      bash "$SCRIPT_PATH" </dev/null 2>&1 >/dev/null
    )
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected" ] && { [ -z "$stderr_pattern" ] || echo "$actual_stderr" | grep -q "$stderr_pattern"; }; then
      echo "self-test [$desc]: PASS (exit=$actual_exit)" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test [$desc]: FAIL (expected exit=$expected, got=$actual_exit; stderr-pattern='$stderr_pattern' actual-stderr='$actual_stderr')" >&2
      FAILED=$((FAILED+1))
    fi
  }

  expect_exit() {
    expect_exit_with_stderr "$1" "$2" "" "${@:3}"
  }

  reset_state() {
    rm -rf "$SYN_STATE"/* 2>/dev/null || true
    mkdir -p "$SYN_STATE/reviews"
  }

  # ---- E1: solo mode, counter at 1 → exit 0 (passthrough) ----
  reset_state
  expect_exit "E1-solo-passthrough-at-1" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=solo-abc"

  # ---- E2: solo mode at counter 30 → exit 1 (block) ----
  reset_state
  echo 29 > "$SYN_STATE/tool-call-count.solo-abc"
  expect_exit_with_stderr "E2-solo-blocks-at-30" 1 "TOOL-CALL BUDGET EXCEEDED" \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=solo-abc"

  # ---- E3: solo mode after ack → resumes ----
  reset_state
  echo 35 > "$SYN_STATE/tool-call-count.solo-abc"
  echo 35 > "$SYN_STATE/audit-ack.solo-abc"
  expect_exit "E3-solo-after-ack" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=solo-abc"

  # ---- E4: --ack rejected when no fresh review ----
  reset_state
  echo 30 > "$SYN_STATE/tool-call-count.solo-abc"
  actual_exit=$(
    export STATE_DIR_OVERRIDE="$SYN_STATE"
    export TEAMS_DIR_OVERRIDE="$SYN_TEAMS"
    export CLAUDE_SESSION_ID="solo-abc"
    bash "$SCRIPT_PATH" --ack </dev/null >/dev/null 2>/dev/null
    echo $?
  )
  if [ "$actual_exit" -eq 1 ]; then
    echo "self-test [E4-ack-rejected-no-review]: PASS (exit=$actual_exit)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [E4-ack-rejected-no-review]: FAIL (expected exit=1, got=$actual_exit)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- E5: --ack accepted when fresh review present ----
  reset_state
  echo 30 > "$SYN_STATE/tool-call-count.solo-abc"
  cat > "$SYN_STATE/reviews/test-$(date +%s).md" <<EOF
REVIEW COMPLETE
VERDICT: PASS
EOF
  actual_exit=$(
    export STATE_DIR_OVERRIDE="$SYN_STATE"
    export TEAMS_DIR_OVERRIDE="$SYN_TEAMS"
    export CLAUDE_SESSION_ID="solo-abc"
    bash "$SCRIPT_PATH" --ack </dev/null >/dev/null 2>/dev/null
    echo $?
  )
  if [ "$actual_exit" -eq 0 ]; then
    echo "self-test [E5-ack-accepted-with-review]: PASS (exit=$actual_exit)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [E5-ack-accepted-with-review]: FAIL (expected exit=0, got=$actual_exit)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- E6: counter file persists value across calls (solo) ----
  reset_state
  expect_exit "E6a-first-call-of-fresh-session" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=fresh-session"
  # After one call, counter should be 1
  if [ -f "$SYN_STATE/tool-call-count.fresh-session" ] && [ "$(cat "$SYN_STATE/tool-call-count.fresh-session")" = "1" ]; then
    echo "self-test [E6b-counter-persisted-as-1]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [E6b-counter-persisted-as-1]: FAIL (counter=$(cat "$SYN_STATE/tool-call-count.fresh-session" 2>/dev/null))" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- E7: missing CLAUDE_SESSION_ID falls back to PPID/PID ----
  reset_state
  expect_exit "E7-no-session-id-still-runs" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS"
  # We don't unset CLAUDE_SESSION_ID — it's just not set in this subshell

  # ---- E8: solo mode, counter=29 → still passthrough on this call to 30 ----
  reset_state
  echo 28 > "$SYN_STATE/tool-call-count.solo-xyz"
  # Now we do a call: should increment to 29 and let through (since SINCE_ACK = 29 < 30)
  expect_exit "E8-solo-at-29-passthrough" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=solo-xyz"

  # ============================================================
  # NEW SCENARIOS (team-aware + deferred-audit)
  # ============================================================

  # ---- N1: solo session falls back to session_id (regression) ----
  reset_state
  # No team configs at all
  expect_exit "N1-solo-no-team-config" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=solo-N1"
  # Counter file should be keyed by session_id (not a team)
  if [ -f "$SYN_STATE/tool-call-count.solo-N1" ]; then
    echo "self-test [N1b-counter-keyed-by-session]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [N1b-counter-keyed-by-session]: FAIL (counter file not present)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- N2: team member uses team name ----
  reset_state
  rm -rf "$SYN_TEAMS"/* 2>/dev/null
  write_team_config "ravens" "tm-N2-leader" "tm-N2-builder1"
  expect_exit "N2-team-member-resolves-to-team" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=tm-N2-leader"
  if [ -f "$SYN_STATE/tool-call-count.ravens" ]; then
    echo "self-test [N2b-counter-keyed-by-team-name]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [N2b-counter-keyed-by-team-name]: FAIL (expected tool-call-count.ravens; have $(ls "$SYN_STATE" | tr '\n' ' '))" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- N3: non-member uses own session_id ----
  reset_state
  rm -rf "$SYN_TEAMS"/* 2>/dev/null
  write_team_config "ravens" "tm-N3-leader"
  expect_exit "N3-nonmember-uses-session-id" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=tm-N3-stranger"
  if [ -f "$SYN_STATE/tool-call-count.tm-N3-stranger" ] && [ ! -f "$SYN_STATE/tool-call-count.ravens" ]; then
    echo "self-test [N3b-stranger-bypassed-team]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [N3b-stranger-bypassed-team]: FAIL (expected tool-call-count.tm-N3-stranger; got $(ls "$SYN_STATE" | tr '\n' ' '))" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- N4: agent-team mode at counter 25 passes through (no flag) ----
  reset_state
  rm -rf "$SYN_TEAMS"/* 2>/dev/null
  write_team_config "eagles" "tm-N4-leader"
  echo 24 > "$SYN_STATE/tool-call-count.eagles"
  expect_exit "N4-team-mode-at-25-no-flag" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=tm-N4-leader"
  if [ ! -f "$SYN_STATE/audit-pending.eagles" ]; then
    echo "self-test [N4b-no-flag-at-counter-25]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [N4b-no-flag-at-counter-25]: FAIL (flag should not exist yet)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- N5: agent-team mode at counter 30 sets flag (no block) ----
  reset_state
  rm -rf "$SYN_TEAMS"/* 2>/dev/null
  write_team_config "eagles" "tm-N5-leader"
  echo 29 > "$SYN_STATE/tool-call-count.eagles"
  # Should NOT block at counter 30 in team mode; should set flag
  expect_exit "N5a-team-mode-at-30-no-block" 0 \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=tm-N5-leader" \
    "CLAUDE_TASK_ID=task-T-001"
  if [ -f "$SYN_STATE/audit-pending.eagles" ]; then
    echo "self-test [N5b-flag-file-created]: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test [N5b-flag-file-created]: FAIL (flag missing; ls $SYN_STATE = $(ls "$SYN_STATE" | tr '\n' ' '))" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- N6: agent-team mode at sub-counter 90 blocks (hard ceiling) ----
  reset_state
  rm -rf "$SYN_TEAMS"/* 2>/dev/null
  write_team_config "eagles" "tm-N6-leader"
  echo 100 > "$SYN_STATE/tool-call-count.eagles"
  echo 89 > "$SYN_STATE/tool-call-since-task.tm-N6-leader"
  expect_exit_with_stderr "N6-hard-ceiling-blocks-at-90" 1 "Hard ceiling" \
    "STATE_DIR_OVERRIDE=$SYN_STATE" \
    "TEAMS_DIR_OVERRIDE=$SYN_TEAMS" \
    "CLAUDE_SESSION_ID=tm-N6-leader"

  echo "" >&2
  echo "self-test summary: $PASSED PASS, $FAILED FAIL" >&2
  if [ "$FAILED" -gt 0 ]; then
    exit 2
  fi
  exit 0
fi

# ============================================================
# Normal hook execution (PreToolUse)
# ============================================================

# Atomically increment per-session-or-per-team counter
COUNT=$(atomic_increment_counter "$COUNTER_FILE")

# Maintain per-teammate sub-counter when in team mode
SUB_COUNT=0
if [ "$IS_TEAM_MODE" -eq 1 ]; then
  SUB_COUNT=$(atomic_increment_counter "$SUB_COUNTER_FILE")
fi

LAST_ACK=$(cat "$ACK_FILE" 2>/dev/null || echo "0")
[[ "$LAST_ACK" =~ ^[0-9]+$ ]] || LAST_ACK=0
SINCE_ACK=$((COUNT - LAST_ACK))

BUDGET=30
HARD_CEILING=90

if [ "$IS_TEAM_MODE" -eq 1 ]; then
  # ============================================================
  # AGENT-TEAM MODE
  # ============================================================

  # Hard ceiling: per-teammate sub-counter
  if [ "$SUB_COUNT" -ge "$HARD_CEILING" ]; then
    cat >&2 <<EOF

================================================================
TOOL-CALL HARD CEILING — teammate blocked
================================================================

Hard ceiling reached: teammate has accumulated $SUB_COUNT tool calls
without TaskCompleted clearing the audit flag. This is the agent-team
mode safety net for runaway tasks.

Audit required before continuing. Steps:
  1. Invoke plan-evidence-reviewer via the Task tool (see ack docs).
  2. Address any findings.
  3. Trigger TaskCompleted to clear the flag at:
     $STATE_DIR/audit-pending.$EFFECTIVE_ID
  4. The TaskCompleted hook will reset both per-team and per-teammate
     counters once the audit verdict is PASS.

If TaskCompleted hooks are unavailable in your environment, you can
manually reset by deleting:
  - $SUB_COUNTER_FILE
  - $STATE_DIR/audit-pending.$EFFECTIVE_ID
after running the audit.

EOF
    exit 1
  fi

  # Deferred-audit at counter 30: set flag, allow tool call
  if [ "$SINCE_ACK" -ge "$BUDGET" ]; then
    write_audit_flag "$EFFECTIVE_ID"
  fi

  exit 0
else
  # ============================================================
  # SOLO MODE (unchanged behavior)
  # ============================================================
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
fi
