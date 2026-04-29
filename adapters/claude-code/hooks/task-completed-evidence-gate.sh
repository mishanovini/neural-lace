#!/bin/bash
# task-completed-evidence-gate.sh
#
# TaskCompleted event hook for Anthropic's Agent Teams feature.
# Two layered enforcement modes:
#
#   1. Evidence enforcement: verifies that an evidence block exists
#      (in <plan>-evidence.md or in the plan's ## Evidence Log
#      section) referencing the same task ID before allowing the
#      task to be marked complete. Blocks completion if missing.
#
#   2. Deferred-audit enforcement: checks for the audit-pending
#      flag at ~/.claude/state/audit-pending.<team_name>.
#      The flag is set by tool-call-budget.sh in agent-team mode
#      at counter == 30 (Task 6 of the plan). When the flag exists,
#      this hook BLOCKS task completion until a fresh
#      plan-evidence-reviewer review file appears at
#      ~/.claude/state/reviews/<timestamp>.md with VERDICT: PASS
#      (mirrors the tool-call-budget --ack mechanism).
#
#      A PASS review clears the audit-pending flag and allows
#      completion. Absence of a fresh PASS review keeps the
#      flag set and blocks completion.
#
#      The hook does NOT directly invoke plan-evidence-reviewer
#      (sub-agents cannot be spawned from hook scripts — see
#      backlog HARNESS-GAP). Instead, it surfaces an actionable
#      stderr message instructing the user to invoke the agent.
#
# Coordination with Task 6 (tool-call-budget):
#   Task 6 writes ~/.claude/state/audit-pending.<team_name> at
#   counter==30 in agent-team mode. Task 6 also tracks a per-
#   teammate sub-counter at
#   ~/.claude/state/tool-call-since-task.<session_id>. This hook
#   resets that sub-counter on every TaskCompleted event so the
#   per-teammate "since last completion" budget restarts at 0.
#
# Plan: docs/plans/agent-teams-integration.md (Task 8)
# Decision: Decisions Log → "Tool-call budget scope + audit cadence"
#
# Defaults to ALLOW when ambiguous:
#   - Missing event input → allow
#   - Missing task_id → log warning, allow (handles graceful)
#   - No team_name → solo session; skip team-aware logic
#   - No active plans → allow (team-init case)
#   - Bypass via TASK_COMPLETED_BYPASS=1 env or
#     bypass_evidence_check: true field
#
# Exit codes:
#   0 — task completion allowed (silent)
#   2 — task completion blocked (stderr explains)
#
# Self-test:
#   bash task-completed-evidence-gate.sh --self-test
# Expected: 6/6 PASS, exit 0.

set -e

# ============================================================
# Self-test entry point (handled BEFORE input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

# ============================================================
# Input loading — support both CLAUDE_TOOL_INPUT and stdin
# ============================================================
load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  printf '%s' "$input"
}

# ============================================================
# State directory resolution. Allow override for self-test.
# ============================================================
state_dir() {
  printf '%s' "${CLAUDE_STATE_DIR_OVERRIDE:-$HOME/.claude/state}"
}

reviews_dir() {
  printf '%s/reviews' "$(state_dir)"
}

audit_pending_flag() {
  local team="$1"
  printf '%s/audit-pending.%s' "$(state_dir)" "$team"
}

# Per-teammate sub-counter (Task 6 coordination)
tool_call_since_task_file() {
  local session="$1"
  printf '%s/tool-call-since-task.%s' "$(state_dir)" "$session"
}

# ============================================================
# Reject helper — exit 2 with structured stderr + JSON stdout.
# ============================================================
emit_block() {
  local title="$1"
  local body="$2"
  cat >&2 <<MSG

================================================================
BLOCKED: task-completed-evidence-gate — $title
================================================================
$body
MSG
  printf '{"continue": false, "stopReason": "%s"}\n' "$title" || true
  exit 2
}

# ============================================================
# Active-plan enumeration. Returns one path per line.
# (Top-level docs/plans/ only; archive excluded.)
# ============================================================
list_active_plans() {
  local plans_dir="${PLANS_DIR_OVERRIDE:-docs/plans}"
  [[ -d "$plans_dir" ]] || return 0
  local f
  for f in "$plans_dir"/*.md; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *-evidence.md) continue ;;
    esac
    local status
    status=$(grep -m1 -oE '^Status:[[:space:]]*[A-Z]+' "$f" 2>/dev/null | awk '{print $2}')
    case "$status" in
      ACTIVE) printf '%s\n' "$f" ;;
    esac
  done
}

# ============================================================
# Search for an evidence block matching the given task_id across:
#   1. Each ACTIVE plan's companion <plan>-evidence.md (if any)
#   2. Each ACTIVE plan's inline ## Evidence Log section
#
# An "evidence block" is identified by lines like:
#   Task ID: <id>
#   Task: <id>
#   ## Task <id>
# (case-insensitive on "Task")
#
# Returns 0 if a match is found, 1 otherwise.
# ============================================================
evidence_exists_for_task() {
  local task_id="$1"
  [[ -z "$task_id" ]] && return 1

  # Build a regex that matches the task id with common framings.
  # Escape regex metacharacters in task_id (allow . - _ digits).
  local esc
  esc=$(printf '%s' "$task_id" | sed 's/[][\\/.^$*+?(){}|]/\\&/g')

  local plan
  while IFS= read -r plan; do
    [[ -z "$plan" ]] && continue
    # Companion evidence file
    local ev="${plan%.md}-evidence.md"
    if [[ -f "$ev" ]]; then
      if grep -qiE "(^|[[:space:]])Task[[:space:]]*(ID)?[[:space:]]*[:#][[:space:]]*${esc}([[:space:]]|$)" "$ev"; then
        return 0
      fi
      # Also accept "## Task <id>" headings
      if grep -qiE "^##[[:space:]]+Task[[:space:]]+${esc}([[:space:]]|$)" "$ev"; then
        return 0
      fi
    fi
    # Inline ## Evidence Log section in the plan itself
    if grep -qiE "(^|[[:space:]])Task[[:space:]]*(ID)?[[:space:]]*[:#][[:space:]]*${esc}([[:space:]]|$)" "$plan"; then
      return 0
    fi
  done < <(list_active_plans)

  return 1
}

# ============================================================
# Fresh-PASS-review check. Returns 0 if a review file exists
# under reviews_dir, modified within the last 5 minutes (matching
# tool-call-budget.sh's window), AND containing both
#   "REVIEW COMPLETE"
#   "VERDICT: PASS"
# Returns 1 otherwise.
# ============================================================
fresh_pass_review_exists() {
  local rdir
  rdir=$(reviews_dir)
  [[ -d "$rdir" ]] || return 1
  local now mtime age f
  now=$(date +%s 2>/dev/null || echo 0)
  for f in "$rdir"/*.md; do
    [[ -f "$f" ]] || continue
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    age=$((now - mtime))
    if [[ "$age" -le 300 ]]; then
      if grep -q '^REVIEW COMPLETE' "$f" && grep -qE '^VERDICT:[[:space:]]*PASS' "$f"; then
        return 0
      fi
    fi
  done
  return 1
}

# ============================================================
# Reset the per-teammate sub-counter on TaskCompleted (Task 6
# coordination). No-op if the file doesn't exist.
# ============================================================
reset_per_teammate_counter() {
  local session="$1"
  [[ -z "$session" ]] && return 0
  local f
  f=$(tool_call_since_task_file "$session")
  if [[ -f "$f" ]]; then
    rm -f "$f" 2>/dev/null || true
  fi
}

# ============================================================
# Inspect the event input and apply both enforcement layers.
# ============================================================
inspect_task_completed() {
  local input="$1"

  # Extract event fields
  local hook_event task_id team_name session_id bypass
  hook_event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
  task_id=$(printf '%s' "$input" | jq -r '.task_id // ""' 2>/dev/null || echo "")
  team_name=$(printf '%s' "$input" | jq -r '.team_name // ""' 2>/dev/null || echo "")
  session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")
  bypass=$(printf '%s' "$input" | jq -r '.bypass_evidence_check // empty' 2>/dev/null || echo "")

  # Resetting the per-teammate sub-counter happens unconditionally
  # before any blocking decisions: regardless of audit/evidence
  # outcome, this TaskCompleted event marks a natural restart point
  # for the per-teammate counter (Task 6 contract).
  if [[ -n "$session_id" ]]; then
    reset_per_teammate_counter "$session_id"
  fi

  # ---------- Bypass paths
  if [[ "${TASK_COMPLETED_BYPASS:-0}" == "1" ]]; then
    # Audit log: record bypass usage
    local logd
    logd="$(state_dir)/task-completed-bypass.log"
    {
      printf '%s task=%s team=%s session=%s reason=env\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown-time')" \
        "${task_id:-<none>}" "${team_name:-<none>}" "${session_id:-<none>}"
    } >> "$logd" 2>/dev/null || true
    return 0
  fi
  if [[ "$bypass" == "true" ]]; then
    local logd
    logd="$(state_dir)/task-completed-bypass.log"
    {
      printf '%s task=%s team=%s session=%s reason=event-field\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown-time')" \
        "${task_id:-<none>}" "${team_name:-<none>}" "${session_id:-<none>}"
    } >> "$logd" 2>/dev/null || true
    return 0
  fi

  # ---------- Layer 2: deferred-audit enforcement (team-aware)
  # If team_name set and audit-pending flag exists, require a fresh
  # PASS review before allowing TaskCompleted. PASS clears the flag.
  if [[ -n "$team_name" ]]; then
    local flag
    flag=$(audit_pending_flag "$team_name")
    if [[ -f "$flag" ]]; then
      if fresh_pass_review_exists; then
        # PASS — clear the flag and allow.
        rm -f "$flag" 2>/dev/null || true
        printf 'task-completed-evidence-gate: deferred audit cleared (PASS); flag removed for team=%s\n' "$team_name" >&2
        # Continue to evidence layer below.
      else
        emit_block "deferred audit pending for team \"$team_name\"" "\
The team has hit the tool-call budget threshold (30 calls in
agent-team mode) and a deferred audit was scheduled at:
  $flag

Before this TaskCompleted event is allowed, you must:

  1. Invoke plan-evidence-reviewer via the Task tool against the
     team's active plan + evidence file:
        \"is anything marked complete actually incomplete or
         missing evidence? Are runtime verifications corresponding
         to the tasks? Flag anything suspicious.\"

  2. The reviewer must write its output to:
        $(reviews_dir)/<timestamp>.md
     containing both:
        REVIEW COMPLETE
        VERDICT: PASS
     (the reviewer agent prompt instructs it to emit these.)

  3. Re-fire TaskCompleted. The hook will detect the fresh PASS
     review, clear the flag, and allow completion.

  If the review's verdict is FAIL, address the findings BEFORE
  marking the task complete. Forcibly clearing the flag (rm -f) is
  the same self-enforced workaround that shipped the 2026-04-14
  vaporware failures and should not be used."
      fi
    fi
  fi

  # ---------- Layer 1: evidence enforcement
  # Skip when no task_id (graceful) — log warning, allow.
  if [[ -z "$task_id" ]]; then
    printf 'task-completed-evidence-gate: warning — TaskCompleted event has no task_id; evidence check skipped\n' >&2
    return 0
  fi

  if ! evidence_exists_for_task "$task_id"; then
    # Allow when no active plans exist (team-init case)
    local active
    active=$(list_active_plans)
    if [[ -z "$active" ]]; then
      printf 'task-completed-evidence-gate: warning — no ACTIVE plans found; evidence check skipped (team-init case)\n' >&2
      return 0
    fi
    emit_block "no evidence block found for task_id \"$task_id\"" "\
The TaskCompleted event references task_id=\"$task_id\", but no
matching evidence block was found in any active plan.

Searched in (for each ACTIVE plan):
  - <plan>-evidence.md companion file
  - The plan's inline ## Evidence Log section

An evidence block is recognized by lines of the form:
  Task ID: <id>
  Task: <id>
  ## Task <id>

Active plans:
$(printf '%s\n' "$active" | sed 's/^/  - /')

Resolution:
  - Verify the task is actually complete; have task-verifier write
    the evidence block FIRST, then fire TaskCompleted.
  - Or set bypass_evidence_check: true on the event input AND
    document why in your TaskCompleted prompt.
  - Or, for env-level bypass: set TASK_COMPLETED_BYPASS=1.

This block exists because evidence-first is the harness's
load-bearing anti-vaporware mechanism (see
~/.claude/rules/vaporware-prevention.md)."
  fi

  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local total=0 passed=0 failed_names=""

  # Scratch dir as state dir + plans dir + reviews dir
  local scratch
  scratch=$(mktemp -d -t taskcomp-XXXXXX) || { echo "mktemp FAIL"; exit 1; }
  trap 'rm -rf "$scratch"' EXIT

  mkdir -p "$scratch/state/reviews"
  mkdir -p "$scratch/docs/plans"

  # Active plan with evidence companion containing Task 3.2 block
  cat > "$scratch/docs/plans/p1.md" <<'PLAN'
# Plan: P1
Status: ACTIVE
PLAN
  cat > "$scratch/docs/plans/p1-evidence.md" <<'EV'
# Evidence Log

## Task 3.2 — Build duplicate
Task ID: 3.2
Verdict: PASS
Notes: did the work
EV

  # run_scenario <name> <expect-exit> <event-json> [pre-setup-bash] [post-checks-bash]
  run_scenario() {
    local name="$1"
    local expect="$2"
    local event_input="$3"
    local pre="${4:-}"
    local post="${5:-}"
    total=$((total+1))

    # Reset state dir contents per scenario
    rm -rf "$scratch/state"
    mkdir -p "$scratch/state/reviews"

    if [[ -n "$pre" ]]; then
      eval "$pre"
    fi

    local exit_code
    set +e
    env CLAUDE_STATE_DIR_OVERRIDE="$scratch/state" \
      PLANS_DIR_OVERRIDE="$scratch/docs/plans" \
      CLAUDE_TOOL_INPUT="$event_input" \
      bash "$SELF_PATH" >"$scratch/out-$total.log" 2>"$scratch/err-$total.log"
    exit_code=$?
    set -e

    local pass_post=1
    if [[ -n "$post" ]]; then
      if ! eval "$post"; then
        pass_post=0
      fi
    fi

    if [[ "$exit_code" == "$expect" && "$pass_post" == "1" ]]; then
      passed=$((passed+1))
      printf '  ok   %-3d %s\n' "$total" "$name"
    else
      printf '  FAIL %-3d %s (expected exit=%s, got exit=%s, post-check=%s)\n' \
        "$total" "$name" "$expect" "$exit_code" "$pass_post"
      printf '       stderr: %s\n' "$(head -3 "$scratch/err-$total.log" | tr '\n' ' ')"
      failed_names="$failed_names\n  - $name"
    fi
  }

  echo "task-completed-evidence-gate self-test"
  echo "======================================="

  # D1 — rejects-missing-evidence: task_id="9.9" doesn't exist in
  # evidence file; team_name set so we go through full flow → BLOCK
  run_scenario "D1. rejects missing evidence → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCompleted","task_id":"9.9","team_name":"demo","session_id":"s1"}'

  # D2 — allows-evidence-present: task_id="3.2" present in p1-evidence.md
  run_scenario "D2. allows evidence present → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.2","team_name":"demo","session_id":"s2"}'

  # D3 — allows-explicit-bypass via event field
  run_scenario "D3. allows explicit bypass field → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"99.99","team_name":"demo","session_id":"s3","bypass_evidence_check":true}'

  # D4 — handles missing task_id gracefully → ALLOW (with warning)
  run_scenario "D4. handles missing task_id → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCompleted","team_name":"demo","session_id":"s4"}'

  # D5 — runs-audit-when-flag-set-and-PASS-clears-flag
  # Pre-setup: write the flag AND a fresh PASS review.
  run_scenario "D5. flag set + fresh PASS review → ALLOW + flag cleared" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.2","team_name":"demo","session_id":"s5"}' \
    'echo "pending t1 timestamp" > "$scratch/state/audit-pending.demo"
     mkdir -p "$scratch/state/reviews"
     cat > "$scratch/state/reviews/r1.md" <<EOF
REVIEW COMPLETE
VERDICT: PASS
EOF
     touch "$scratch/state/reviews/r1.md"' \
    '! [[ -f "$scratch/state/audit-pending.demo" ]]'

  # D6 — runs-audit-when-flag-set-and-FAIL-blocks-completion
  # Pre-setup: flag exists; no review (or stale/FAIL review)
  run_scenario "D6. flag set + no fresh PASS review → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.2","team_name":"demo","session_id":"s6"}' \
    'echo "pending t1 timestamp" > "$scratch/state/audit-pending.demo"' \
    '[[ -f "$scratch/state/audit-pending.demo" ]]'

  echo "======================================="
  echo "passed: $passed / $total"
  if [[ $passed -ne $total ]]; then
    printf 'FAILURES:%b\n' "$failed_names"
    exit 1
  fi
  echo "self-test: OK"
  exit 0
}

# ============================================================
# Entry point
# ============================================================

# Resolve own path for self-test re-entry
SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) ;;
  *) SELF_PATH="$PWD/$SELF_PATH" ;;
esac

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  run_self_test
fi

# Production path
INPUT=$(load_input)
[[ -z "$INPUT" ]] && exit 0

inspect_task_completed "$INPUT"
exit 0
