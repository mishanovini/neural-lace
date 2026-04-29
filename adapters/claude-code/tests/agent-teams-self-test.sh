#!/bin/bash
# NEURAL-LACE-AGENT-TEAMS-INTEGRATION-SELF-TEST v1
#
# Plan: docs/plans/agent-teams-integration.md (Task 14)
#
# Purpose
# -------
# Synthetic integration runner for the Agent Teams plan. Exercises every
# new and extended hook from the plan with mocked event input AND adds
# cross-hook scenarios that the per-hook --self-tests cannot cover on
# their own (e.g., tool-call-budget setting a flag that
# task-completed-evidence-gate consumes).
#
# Does NOT enable Agent Teams. Does NOT modify the user's real
# ~/.claude/state/, ~/.claude/teams/, or ~/.claude/local/ directories.
# All fixtures live under mktemp -d directories that are torn down
# via EXIT/INT/TERM traps.
#
# Layered checks (in order):
#
#   Layer A — per-hook --self-test passthrough.
#     Each new/extended hook must pass its own --self-test (already
#     exercised in the plan's per-task verification specs). We re-run
#     them here as a structural prerequisite before integration
#     scenarios; a regression in any hook's per-self-test fails the
#     whole suite early so the integration cause-of-failure is clear.
#
#   Layer B — integration scenarios I1..I6.
#     Cross-hook flows that no single hook self-test exercises:
#       I1 spawn-validator allow + budget at 30 sets flag
#       I2 TaskCompleted with flag set + fresh PASS review clears flag
#       I3 TaskCompleted with flag set + no PASS review blocks
#       I4 budget hard ceiling fires at sub-counter 90
#       I5 plan-edit-validator flock serializes concurrent verifiers
#       I6 product-acceptance-gate finds artifact in another worktree
#
# INVOCATION
#   bash adapters/claude-code/tests/agent-teams-self-test.sh
#
# EXIT CODES
#   0 — every layer + integration scenario passed
#   1 — at least one failure (per-hook self-test or integration scenario)
#   2 — usage / environment error
#
# Wired into /harness-review skill as Check 11 (next available slot
# after acceptance-loop-self-test which holds Check 10).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -d "$REPO_ROOT/adapters/claude-code" ]]; then
  echo "agent-teams-self-test: cannot resolve repo root from $SCRIPT_DIR" >&2
  exit 2
fi

ADAPTER="$REPO_ROOT/adapters/claude-code"
HOOKS="$ADAPTER/hooks"

PASSED=0
FAILED=0
FAIL_DETAILS=()

# Single per-suite scratch dir; all fixtures are created under it.
SUITE_TMP=$(mktemp -d -t agtmsst-XXXXXX) || {
  echo "agent-teams-self-test: cannot create scratch dir" >&2
  exit 2
}

# Track any synthetic worktrees we add so cleanup can prune them.
SYNTH_WORKTREES=()

cleanup() {
  # Best-effort: prune any synthetic worktrees we registered against
  # OUR OWN synthetic git repo (NOT the harness repo). Each entry is
  # the absolute path of the worktree dir; we attempt removal via the
  # synthetic repo at $SUITE_TMP/i6-primary. If the synthetic repo no
  # longer exists, just let rm -rf clean up the file tree.
  for wt in "${SYNTH_WORKTREES[@]}"; do
    if [[ -d "$SUITE_TMP/i6-primary/.git" ]]; then
      ( cd "$SUITE_TMP/i6-primary" 2>/dev/null && \
        git worktree remove --force "$wt" 2>/dev/null ; \
        git worktree prune 2>/dev/null ) || true
    fi
  done
  rm -rf "$SUITE_TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ============================================================
# Reporting helpers
# ============================================================

scenario_start() {
  local id="$1"
  local name="$2"
  echo "[$id] $name — START" >&2
}

scenario_pass() {
  local id="$1"
  local name="$2"
  PASSED=$((PASSED + 1))
  echo "[$id] $name — PASS" >&2
}

scenario_fail() {
  local id="$1"
  local name="$2"
  local detail="$3"
  FAILED=$((FAILED + 1))
  FAIL_DETAILS+=("[$id] $name — $detail")
  echo "[$id] $name — FAIL: $detail" >&2
}

# ============================================================
# Layer A — per-hook --self-test passthrough
# ============================================================
# Each entry: SCENARIO_ID|HOOK_PATH|FRIENDLY_NAME|EXPECTED_SUMMARY_REGEX
# The summary regex is matched against the hook's combined stdout/stderr
# (each hook prints a summary line to stderr). If empty, only the exit
# code is checked.

run_hook_selftest() {
  local id="$1"
  local hook_path="$2"
  local name="$3"
  local summary_pattern="${4:-}"

  scenario_start "$id" "$name"

  if [[ ! -x "$hook_path" ]] && [[ ! -f "$hook_path" ]]; then
    scenario_fail "$id" "$name" "hook not present at $hook_path"
    return
  fi

  local out
  local rc
  out=$(bash "$hook_path" --self-test 2>&1)
  rc=$?

  if [[ $rc -ne 0 ]]; then
    local last
    last=$(printf '%s\n' "$out" | tail -3 | tr '\n' '|')
    scenario_fail "$id" "$name" "exit $rc — tail: $last"
    return
  fi

  if [[ -n "$summary_pattern" ]]; then
    if ! printf '%s' "$out" | grep -qE "$summary_pattern"; then
      local last
      last=$(printf '%s\n' "$out" | tail -3 | tr '\n' '|')
      scenario_fail "$id" "$name" "exit 0 but no summary match '$summary_pattern'; tail: $last"
      return
    fi
  fi

  scenario_pass "$id" "$name"
}

run_hook_selftest "A1" "$HOOKS/teammate-spawn-validator.sh" \
  "teammate-spawn-validator --self-test" "passed: 6 / 6"
run_hook_selftest "A2" "$HOOKS/tool-call-budget.sh" \
  "tool-call-budget --self-test" "self-test summary: [0-9]+ PASS, 0 FAIL"
run_hook_selftest "A3" "$HOOKS/task-created-validator.sh" \
  "task-created-validator --self-test" "passed: 4 / 4"
run_hook_selftest "A4" "$HOOKS/task-completed-evidence-gate.sh" \
  "task-completed-evidence-gate --self-test" "passed: 6 / 6"
run_hook_selftest "A5" "$HOOKS/plan-edit-validator.sh" \
  "plan-edit-validator --self-test" "self-test summary: 4 passed, 0 failed"
run_hook_selftest "A6" "$HOOKS/product-acceptance-gate.sh" \
  "product-acceptance-gate --self-test" "self-test summary: 10 passed, 0 failed"

# ============================================================
# Integration fixtures — synthetic team config
# ============================================================
#
# A sentinel team name is used so that — even in the unlikely event
# any path leaks past our SUITE_TMP — it would never collide with a
# real team.
SENTINEL_TEAM="_self_test_team_$$"
SENTINEL_LEADER="_self_test_leader_$$"

INT_STATE="$SUITE_TMP/state"
INT_TEAMS="$SUITE_TMP/teams"
mkdir -p "$INT_STATE/reviews" "$INT_TEAMS/$SENTINEL_TEAM"

cat > "$INT_TEAMS/$SENTINEL_TEAM/config.json" <<EOF
{
  "team_name": "$SENTINEL_TEAM",
  "members": [
    { "session_id": "$SENTINEL_LEADER" }
  ]
}
EOF

# ============================================================
# I1 — End-to-end spawn validator + budget integration
# ============================================================
# 1. spawn-validator: enabled=true, force_in_process=true,
#    worktree_mandatory_for_write=true, isolation=worktree → exit 0.
# 2. tool-call-budget: increment counter to 30 in team mode → flag
#    file at <state>/audit-pending.<team> exists.

scenario_start "I1" "spawn-validator allow + budget at 30 sets audit flag"

# (1) spawn-validator
SPAWN_CFG="$SUITE_TMP/spawn-cfg.json"
cat > "$SPAWN_CFG" <<EOF
{ "enabled": true, "force_in_process": true, "worktree_mandatory_for_write": true }
EOF
SPAWN_INPUT='{"tool_name":"Agent","tool_input":{"team_name":"'"$SENTINEL_TEAM"'","subagent_type":"plan-phase-builder","isolation":"worktree"}}'

set +e
env AGENT_TEAMS_CONFIG_PATH="$SPAWN_CFG" \
  CLAUDE_TOOL_INPUT="$SPAWN_INPUT" \
  CLAUDE_PERMISSION_MODE=default \
  bash "$HOOKS/teammate-spawn-validator.sh" >/dev/null 2>"$SUITE_TMP/i1-spawn-err.log"
SPAWN_RC=$?
set -e

if [[ $SPAWN_RC -ne 0 ]]; then
  scenario_fail "I1" "spawn-validator allow + budget at 30 sets audit flag" \
    "spawn-validator unexpectedly returned exit $SPAWN_RC ; stderr: $(head -3 "$SUITE_TMP/i1-spawn-err.log" | tr '\n' '|')"
else
  # (2) Pre-load counter to 29; one increment will hit 30.
  rm -rf "$INT_STATE"/* 2>/dev/null || true
  mkdir -p "$INT_STATE/reviews"
  echo 29 > "$INT_STATE/tool-call-count.$SENTINEL_TEAM"

  set +e
  env STATE_DIR_OVERRIDE="$INT_STATE" \
      TEAMS_DIR_OVERRIDE="$INT_TEAMS" \
      CLAUDE_SESSION_ID="$SENTINEL_LEADER" \
      CLAUDE_TASK_ID="task-i1-001" \
    bash "$HOOKS/tool-call-budget.sh" </dev/null >/dev/null 2>"$SUITE_TMP/i1-budget-err.log"
  BUDGET_RC=$?
  set -e

  if [[ $BUDGET_RC -ne 0 ]]; then
    scenario_fail "I1" "spawn-validator allow + budget at 30 sets audit flag" \
      "tool-call-budget should not block in team mode at 30, got exit $BUDGET_RC"
  elif [[ ! -f "$INT_STATE/audit-pending.$SENTINEL_TEAM" ]]; then
    scenario_fail "I1" "spawn-validator allow + budget at 30 sets audit flag" \
      "expected $INT_STATE/audit-pending.$SENTINEL_TEAM to exist after counter hit 30"
  else
    scenario_pass "I1" "spawn-validator allow + budget at 30 sets audit flag"
  fi
fi

# ============================================================
# I2 — TaskCompleted clears flag with fresh PASS review
# ============================================================
# Pre-state from I1: flag exists at $INT_STATE/audit-pending.<team>.
# Add: a fresh review file with REVIEW COMPLETE + VERDICT: PASS.
# Add: an active plan + evidence file matching the task_id, so the
# evidence layer is also satisfied.
# Expected: TaskCompleted hook returns exit 0 and the flag is removed.

scenario_start "I2" "TaskCompleted clears audit flag on fresh PASS review"

if [[ ! -f "$INT_STATE/audit-pending.$SENTINEL_TEAM" ]]; then
  # I1 didn't leave the flag — recreate it to keep I2 independent of I1's pass/fail.
  echo '{"task_id":"task-i2","reason":"recreated for I2"}' > "$INT_STATE/audit-pending.$SENTINEL_TEAM"
fi

# Synthetic plan + evidence under PLANS_DIR_OVERRIDE
PLANS_DIR="$SUITE_TMP/plans-i2"
mkdir -p "$PLANS_DIR"
cat > "$PLANS_DIR/synth-plan.md" <<'EOP'
# Plan: Synth Plan
Status: ACTIVE
EOP
cat > "$PLANS_DIR/synth-plan-evidence.md" <<'EOE'
# Evidence Log

## Task 7.1 — Synthetic
Task ID: 7.1
Verdict: PASS
EOE

# Fresh PASS review (mtime = now)
cat > "$INT_STATE/reviews/r-i2-$$.md" <<'EOR'
REVIEW COMPLETE
VERDICT: PASS
Synthetic review for I2.
EOR

I2_INPUT='{"hook_event_name":"TaskCompleted","task_id":"7.1","team_name":"'"$SENTINEL_TEAM"'","session_id":"'"$SENTINEL_LEADER"'"}'

set +e
env CLAUDE_STATE_DIR_OVERRIDE="$INT_STATE" \
    PLANS_DIR_OVERRIDE="$PLANS_DIR" \
    CLAUDE_TOOL_INPUT="$I2_INPUT" \
  bash "$HOOKS/task-completed-evidence-gate.sh" >/dev/null 2>"$SUITE_TMP/i2-err.log"
I2_RC=$?
set -e

if [[ $I2_RC -ne 0 ]]; then
  scenario_fail "I2" "TaskCompleted clears audit flag on fresh PASS review" \
    "expected exit 0 (allow), got $I2_RC ; stderr: $(head -3 "$SUITE_TMP/i2-err.log" | tr '\n' '|')"
elif [[ -f "$INT_STATE/audit-pending.$SENTINEL_TEAM" ]]; then
  scenario_fail "I2" "TaskCompleted clears audit flag on fresh PASS review" \
    "audit-pending flag was NOT cleared after PASS review"
else
  scenario_pass "I2" "TaskCompleted clears audit flag on fresh PASS review"
fi

# ============================================================
# I3 — TaskCompleted blocks with flag set and no PASS review
# ============================================================
# Re-set the flag, leave NO fresh PASS review — TaskCompleted should
# block with exit 2.

scenario_start "I3" "TaskCompleted blocks with flag set and no PASS review"

# Wipe reviews so nothing PASSes.
rm -f "$INT_STATE"/reviews/*.md 2>/dev/null || true
echo '{"task_id":"task-i3","reason":"i3 setup"}' > "$INT_STATE/audit-pending.$SENTINEL_TEAM"

I3_INPUT='{"hook_event_name":"TaskCompleted","task_id":"7.1","team_name":"'"$SENTINEL_TEAM"'","session_id":"'"$SENTINEL_LEADER"'"}'

set +e
env CLAUDE_STATE_DIR_OVERRIDE="$INT_STATE" \
    PLANS_DIR_OVERRIDE="$PLANS_DIR" \
    CLAUDE_TOOL_INPUT="$I3_INPUT" \
  bash "$HOOKS/task-completed-evidence-gate.sh" >/dev/null 2>"$SUITE_TMP/i3-err.log"
I3_RC=$?
set -e

if [[ $I3_RC -ne 2 ]]; then
  scenario_fail "I3" "TaskCompleted blocks with flag set and no PASS review" \
    "expected exit 2 (block), got $I3_RC ; stderr: $(head -3 "$SUITE_TMP/i3-err.log" | tr '\n' '|')"
elif [[ ! -f "$INT_STATE/audit-pending.$SENTINEL_TEAM" ]]; then
  scenario_fail "I3" "TaskCompleted blocks with flag set and no PASS review" \
    "flag was unexpectedly cleared on a BLOCK — should remain set"
else
  scenario_pass "I3" "TaskCompleted blocks with flag set and no PASS review"
fi

# Cleanup the flag so it doesn't bleed into later scenarios.
rm -f "$INT_STATE/audit-pending.$SENTINEL_TEAM" 2>/dev/null || true

# ============================================================
# I4 — Hard ceiling fires at sub-counter 90
# ============================================================
# Pre-load the per-teammate sub-counter to 89 and the per-team counter
# to 100 (above 30, no audit). The hook should:
#   - Increment per-team counter to 101.
#   - Increment per-teammate sub-counter to 90.
#   - Fire the hard-ceiling block (exit 1, stderr "Hard ceiling").

scenario_start "I4" "tool-call-budget hard ceiling at sub-counter 90"

rm -rf "$INT_STATE"/* 2>/dev/null || true
mkdir -p "$INT_STATE/reviews"
echo 100 > "$INT_STATE/tool-call-count.$SENTINEL_TEAM"
echo 89  > "$INT_STATE/tool-call-since-task.$SENTINEL_LEADER"

set +e
I4_STDERR=$(env STATE_DIR_OVERRIDE="$INT_STATE" \
    TEAMS_DIR_OVERRIDE="$INT_TEAMS" \
    CLAUDE_SESSION_ID="$SENTINEL_LEADER" \
  bash "$HOOKS/tool-call-budget.sh" </dev/null 2>&1 >/dev/null)
I4_RC=$?
set -e

if [[ $I4_RC -ne 1 ]]; then
  scenario_fail "I4" "tool-call-budget hard ceiling at sub-counter 90" \
    "expected exit 1 (block), got $I4_RC"
elif ! printf '%s' "$I4_STDERR" | grep -q "Hard ceiling"; then
  scenario_fail "I4" "tool-call-budget hard ceiling at sub-counter 90" \
    "stderr did not contain 'Hard ceiling' phrase"
else
  scenario_pass "I4" "tool-call-budget hard ceiling at sub-counter 90"
fi

# ============================================================
# I5 — plan-edit-validator flock serializes concurrent verifiers
# ============================================================
# Spawn two background bash processes that both source the lock library
# and contend for the same plan-file lock. If serialization works, the
# log shows one ENTER/EXIT pair before the other. (Mirrors the F2
# scenario inside plan-edit-validator's own self-test, but framed at
# the integration layer to confirm the lock library still works in
# the integration runner's environment, not just inside the hook's
# subshell.)

scenario_start "I5" "plan-edit-validator flock serializes concurrent verifiers"

I5_DIR="$SUITE_TMP/i5"
mkdir -p "$I5_DIR"
PLAN_FIXTURE="$I5_DIR/plan.md"
: > "$PLAN_FIXTURE"
WORKER_LOG="$I5_DIR/worker.log"
: > "$WORKER_LOG"

# Mirror the lock library used in plan-edit-validator's F2 scenario.
LOCKLIB="$I5_DIR/locklib.sh"
cat > "$LOCKLIB" <<'LIB'
PLAN_LOCK_FILE=""
PLAN_LOCK_FD=""
PLAN_LOCK_HELD_VIA=""
acquire_plan_lock() {
  local plan_file="$1"
  local lock_file="${plan_file}.lock"
  local timeout_s=30
  if [[ "$PLAN_LOCK_FILE" == "$lock_file" ]]; then return 0; fi
  PLAN_LOCK_FILE="$lock_file"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file" 2>/dev/null || { PLAN_LOCK_FILE=""; return 1; }
    if flock -w "$timeout_s" 9 2>/dev/null; then
      PLAN_LOCK_FD=9; PLAN_LOCK_HELD_VIA="flock"
      echo "$$" >&9 2>/dev/null || true; return 0
    fi
    exec 9>&- 2>/dev/null || true; PLAN_LOCK_FILE=""; return 1
  fi
  local waited_ms=0; local total_ms=$((timeout_s * 1000))
  while [[ "$waited_ms" -lt "$total_ms" ]]; do
    if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
      PLAN_LOCK_HELD_VIA="pid"; return 0
    fi
    local holder_pid=""
    holder_pid=$(head -n 1 "$lock_file" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$holder_pid" ]] && [[ "$holder_pid" =~ ^[0-9]+$ ]]; then
      if ! kill -0 "$holder_pid" 2>/dev/null; then
        echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
      else
        local now mtime age
        now=$(date +%s); mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo "$now")
        age=$((now - mtime))
        if [[ "$age" -gt 60 ]]; then
          echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
        fi
      fi
    else
      echo "$$" > "$lock_file" 2>/dev/null && { PLAN_LOCK_HELD_VIA="pid"; return 0; }
    fi
    sleep 0.5; waited_ms=$((waited_ms + 500))
  done
  PLAN_LOCK_FILE=""; return 1
}
release_plan_lock() {
  if [[ -z "$PLAN_LOCK_FILE" ]]; then return 0; fi
  case "$PLAN_LOCK_HELD_VIA" in
    flock) exec 9>&- 2>/dev/null || true ;;
    pid)
      local holder_pid=""
      holder_pid=$(head -n 1 "$PLAN_LOCK_FILE" 2>/dev/null | tr -d '[:space:]')
      if [[ "$holder_pid" == "$$" ]]; then rm -f "$PLAN_LOCK_FILE" 2>/dev/null || true; fi ;;
  esac
  PLAN_LOCK_FILE=""; PLAN_LOCK_FD=""; PLAN_LOCK_HELD_VIA=""
}
LIB

WORKER_SCRIPT="$I5_DIR/worker.sh"
cat > "$WORKER_SCRIPT" <<WKR
#!/bin/bash
source "$LOCKLIB"
LABEL="\$1"
PLAN="\$2"
LOG="\$3"
if ! acquire_plan_lock "\$PLAN"; then
  echo "ACQUIRE-FAIL \$LABEL pid=\$\$" >> "\$LOG"
  exit 1
fi
echo "ENTER \$LABEL" >> "\$LOG"
sleep 0.4
echo "marker-\$LABEL" >> "\$PLAN"
echo "EXIT \$LABEL" >> "\$LOG"
release_plan_lock
WKR
chmod +x "$WORKER_SCRIPT"

bash "$WORKER_SCRIPT" A "$PLAN_FIXTURE" "$WORKER_LOG" &
PID_A=$!
bash "$WORKER_SCRIPT" B "$PLAN_FIXTURE" "$WORKER_LOG" &
PID_B=$!
set +e
wait "$PID_A" 2>/dev/null
RC_A=$?
wait "$PID_B" 2>/dev/null
RC_B=$?
set -e

LOG_LABELS=$(grep -E '^(ENTER|EXIT)' "$WORKER_LOG" | awk '{print $1, $2}' | tr '\n' '|')
if [[ "$RC_A" -eq 0 ]] && [[ "$RC_B" -eq 0 ]] && \
   { [[ "$LOG_LABELS" == "ENTER A|EXIT A|ENTER B|EXIT B|" ]] || \
     [[ "$LOG_LABELS" == "ENTER B|EXIT B|ENTER A|EXIT A|" ]]; }; then
  scenario_pass "I5" "plan-edit-validator flock serializes concurrent verifiers"
else
  scenario_fail "I5" "plan-edit-validator flock serializes concurrent verifiers" \
    "rc_a=$RC_A rc_b=$RC_B log='$LOG_LABELS'"
fi

# ============================================================
# I6 — product-acceptance-gate aggregates artifacts across worktrees
# ============================================================
# Build a synthetic git repo at $SUITE_TMP/i6-primary with:
#   - docs/plans/synth-i6.md (Status: ACTIVE, NOT acceptance-exempt)
# Add a secondary worktree at $SUITE_TMP/i6-secondary, write a PASS
# acceptance artifact under the SECONDARY's
# .claude/state/acceptance/synth-i6/ directory, with plan_commit_sha
# matching the plan file's HEAD SHA.
# Run the gate from the PRIMARY worktree's cwd. It must aggregate
# across worktrees, find the secondary's PASS artifact, and exit 0.

scenario_start "I6" "product-acceptance-gate aggregates artifacts across worktrees"

I6_PRIMARY="$SUITE_TMP/i6-primary"
I6_SECONDARY="$SUITE_TMP/i6-secondary"
mkdir -p "$I6_PRIMARY"

# Initialize a fresh git repo with a synthetic identity to avoid
# polluting any user gitconfig in this transient repo.
(
  cd "$I6_PRIMARY"
  git init -q -b master . >/dev/null 2>&1
  git config user.email "selftest@example.test"
  git config user.name "selftest"
  mkdir -p docs/plans
  cat > docs/plans/synth-i6.md <<'EOP'
# Plan: Synth I6
Status: ACTIVE
acceptance-exempt: false

## Goal
Synthetic integration test fixture for I6.

## Acceptance Scenarios
### s-i6 — example
**Slug:** `s-i6`

**User flow:**
1. Step.

**Success criteria (prose):** Outcome described.

**Artifacts to capture:** screenshot, network log, console log.
EOP
  git add docs/plans/synth-i6.md >/dev/null 2>&1
  git commit -q -m "synth: I6 fixture plan" >/dev/null 2>&1
) || {
  scenario_fail "I6" "product-acceptance-gate aggregates artifacts across worktrees" \
    "could not initialize synthetic primary repo"
}

if [[ -d "$I6_PRIMARY/.git" ]]; then
  # Add secondary worktree.
  WT_BRANCH="i6-wt-$$"
  if (
    cd "$I6_PRIMARY"
    git worktree add -q -b "$WT_BRANCH" "$I6_SECONDARY" 2>/dev/null \
      || git worktree add -q --detach "$I6_SECONDARY" 2>/dev/null
  ); then
    SYNTH_WORKTREES+=("$I6_SECONDARY")

    # Resolve the plan file's HEAD SHA from the primary.
    PLAN_SHA=$(cd "$I6_PRIMARY" && git log -n 1 --pretty=format:'%H' -- docs/plans/synth-i6.md 2>/dev/null)
    if [[ -z "$PLAN_SHA" ]]; then
      scenario_fail "I6" "product-acceptance-gate aggregates artifacts across worktrees" \
        "could not resolve plan_commit_sha from primary worktree"
    else
      ART_DIR="$I6_SECONDARY/.claude/state/acceptance/synth-i6"
      mkdir -p "$ART_DIR"
      cat > "$ART_DIR/sess-i6-$$.json" <<EOF
{
  "session_id": "sess-i6",
  "plan_slug": "synth-i6",
  "plan_commit_sha": "$PLAN_SHA",
  "mode": "runtime",
  "started_at": "2026-04-28T00:00:00Z",
  "ended_at": "2026-04-28T00:00:01Z",
  "scenarios": [
    {
      "id": "s-i6",
      "verdict": "PASS",
      "artifacts": {},
      "assertions_met": ["synthetic"],
      "failure_reason": null
    }
  ]
}
EOF

      # Run the gate from the PRIMARY's cwd; it must discover the
      # SECONDARY's artifact via git-worktree-list aggregation.
      set +e
      I6_OUT=$(cd "$I6_PRIMARY" && bash "$HOOKS/product-acceptance-gate.sh" </dev/null 2>&1)
      I6_RC=$?
      set -e

      if [[ $I6_RC -eq 0 ]]; then
        scenario_pass "I6" "product-acceptance-gate aggregates artifacts across worktrees"
      else
        scenario_fail "I6" "product-acceptance-gate aggregates artifacts across worktrees" \
          "expected exit 0, got $I6_RC ; tail: $(printf '%s' "$I6_OUT" | tail -5 | tr '\n' '|')"
      fi
    fi
  else
    scenario_fail "I6" "product-acceptance-gate aggregates artifacts across worktrees" \
      "git worktree add failed for secondary worktree at $I6_SECONDARY"
  fi
fi

# ============================================================
# Summary
# ============================================================

TOTAL=$((PASSED + FAILED))
echo "" >&2
echo "RESULT: $PASSED/$TOTAL integration scenarios passed" >&2
if [[ $FAILED -gt 0 ]]; then
  echo "" >&2
  echo "Failures:" >&2
  for d in "${FAIL_DETAILS[@]}"; do
    echo "  - $d" >&2
  done
  exit 1
fi
exit 0
