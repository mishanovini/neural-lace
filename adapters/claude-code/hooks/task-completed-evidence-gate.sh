#!/bin/bash
# task-completed-evidence-gate.sh
#
# TaskCompleted event hook for Anthropic's Agent Teams feature.
# Three layered modes (two blocking, one warning):
#
#   1. Evidence enforcement (§D.0.5 PLAN-SCOPED, NL Overhaul Wave D.6):
#      verifies that an evidence block exists (in <plan>-evidence.md or
#      in the plan's ## Evidence Log section) referencing the same task
#      ID before allowing the task to be marked complete. BLOCKS
#      completion if missing, but ONLY when the task_id is declared by
#      an ACTIVE plan's own task list (task_id_declared_by_active_plan).
#      An ad-hoc / session-log task completion (task_id not named by any
#      active plan) gets a non-blocking signal-ledger warn instead — see
#      docs/plans/nl-overhaul-program-2026-07-specs-d.md §D.0.5 for the
#      collision this plan-scoping fix kills (workstreams-task-binding's
#      retired Stop-block used to force exactly this invented-task shape
#      into this gate's block wall; mutually unsatisfiable for any
#      session whose work is outside the current ACTIVE plans).
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
#   3. Functionality demonstration warning (non-blocking):
#      operationalizes the harness's most important rule —
#      FUNCTIONALITY OVER COMPONENTS (~/.claude/doctrine/planning.md).
#      After Layer 1 passes, inspects the task's evidence section
#      for at least one functionality marker (playwright, curl,
#      Wire check executed, runtime_evidence, Prove it works,
#      Runtime verification (after), Runtime verification: sql).
#      If the evidence contains only component-level markers
#      (`test <file>` lines, file-existence greps, typecheck/lint),
#      emits a WARNING to stderr but does NOT block.
#
#      Non-blocking because some legitimate tasks (pure refactors,
#      harness-internal config edits, doc-only changes) have no
#      user-facing surface to demonstrate. The warning is the
#      auditable signal that the verifier and the human reader
#      should look closer.
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
#   - task_id not declared by any ACTIVE plan → allow + ledger warn
#     (§D.0.5 plan-scoping; ad-hoc/session-log task completions)
#   - Bypass via TASK_COMPLETED_BYPASS=1 env (maintainer escape hatch,
#     process-level only; usage logged to
#     $(state_dir)/task-completed-bypass.log for periodic review).
#     The event-field bypass_evidence_check hatch that used to exist
#     here was DELETED at Wave D.6 (§D.0.5): it was PROVEN unreachable
#     — read from the TaskCompleted event JSON at the old line ~395,
#     but no agent-facing tool surface (TaskUpdate has no such param;
#     task metadata does not flow into the hook event) could ever set
#     it. If you are reading old docs/history that mention
#     "bypass_evidence_check: true on the event input" — that valve no
#     longer exists; use TASK_COMPLETED_BYPASS=1 or fix the plan-scoping
#     (declare the task, or don't — ad-hoc tasks warn instead of block).
#
# Exit codes:
#   0 — task completion allowed (silent)
#   2 — task completion blocked (stderr explains)
#
# Self-test:
#   bash task-completed-evidence-gate.sh --self-test
# Expected: 10/10 PASS, exit 0.

set -e

# ============================================================
# Self-test entry point (handled BEFORE input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

# ============================================================
# signal-ledger — non-blocking observability for every warn/allow
# decision this gate makes (ADR 058 D6 / NL Overhaul Wave D).
# ============================================================
_TCEG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/signal-ledger.sh
source "$_TCEG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

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
# §D.0.5 plan-scoping — is task_id DECLARED by an ACTIVE plan's own task
# list (as opposed to merely having an evidence block referencing it,
# which is what evidence_exists_for_task checks)?
#
# A plan declares a task via its checklist line:
#   - [ ] T.N <description>
#   - [x] T.N <description>
# where T.N is a dotted task id (letters/digits/dots — matches the
# convention pre-stop-verifier.sh already uses:
#   ^- \[x\] [A-Z]+\.[0-9]+(\.[0-9]+)*  for CHECKED tasks).
# Here we accept EITHER checkbox state ([ ] or [x]) since a task can be
# completed (TaskCompleted fires) before or as part of the box being
# checked — declaration in the plan's task list is what matters, not
# checked-state.
#
# This is the §D.0.5 fix: Layer 1 (evidence enforcement) must block
# ONLY when the plan itself names this task_id. An ad-hoc / session-log
# task (invented to satisfy workstreams-task-binding's mutation-count
# demand, or any other free-floating TaskCreate/TaskComplete not tied to
# plan work) belongs to no plan's task list and must NOT block — it gets
# a ledger warn instead (the collision this fixes: workstreams-task-
# binding's Stop-block used to force exactly this invented-task shape,
# which then hit this gate's block wall; §D.0.5 kills the collision by
# retiring the Stop-block AND narrowing this gate to plan-declared work).
#
# Returns 0 if ANY active plan declares task_id in its task list, 1
# otherwise.
# ============================================================
task_id_declared_by_active_plan() {
  local task_id="$1"
  [[ -z "$task_id" ]] && return 1

  local esc
  esc=$(printf '%s' "$task_id" | sed 's/[][\\/.^$*+?(){}|]/\\&/g')

  local plan
  while IFS= read -r plan; do
    [[ -z "$plan" ]] && continue
    if grep -qE "^- \[[ xX]\][[:space:]]+${esc}([[:space:]]|$)" "$plan" 2>/dev/null; then
      return 0
    fi
  done < <(list_active_plans)

  return 1
}

# ============================================================
# Extract the evidence section text for a given task_id across
# active plans. Returns the section text on stdout (lines from the
# matching task header up to the next task header or EOF). Returns
# empty stdout if no section found.
#
# Handles two header forms:
#   - "## Task <id>"
#   - "Task ID: <id>" / "Task: <id>"
#
# Used by the non-blocking FUNCTIONALITY OVER COMPONENTS warning.
# ============================================================
extract_task_evidence_section() {
  local task_id="$1"
  [[ -z "$task_id" ]] && return 0

  local esc
  esc=$(printf '%s' "$task_id" | sed 's/[][\\/.^$*+?(){}|]/\\&/g')

  local plan
  while IFS= read -r plan; do
    [[ -z "$plan" ]] && continue
    local ev="${plan%.md}-evidence.md"
    local src
    for src in "$ev" "$plan"; do
      [[ -f "$src" ]] || continue
      # Find first line matching this task's header
      local start_line
      start_line=$(grep -nEi "(^##[[:space:]]+Task[[:space:]]+${esc}([[:space:]]|$)|Task[[:space:]]*(ID)?[[:space:]]*[:#][[:space:]]*${esc}([[:space:]]|$))" "$src" 2>/dev/null | head -1 | cut -d: -f1)
      [[ -z "$start_line" ]] && continue
      # Find next task header after start_line for a DIFFERENT task
      # id. The current task may have continuation lines like
      # "Task ID: <id>" right after the "## Task <id>" heading; those
      # are NOT section boundaries. Boundary = next "## Task <other>"
      # heading or "Task ID: <other>" / "Task: <other>" line whose id
      # differs from this task.
      local next_line
      next_line=$(awk -v start="$start_line" -v id="$esc" '
        function is_any_task_header(line) {
          return (line ~ /^##[[:space:]]+Task[[:space:]]+[A-Za-z0-9]/) ||
                 (line ~ /^Task[[:space:]]*(ID)?[[:space:]]*[:#][[:space:]]*[A-Za-z0-9]/)
        }
        function is_self_task_header(line, id) {
          return (line ~ ("^##[[:space:]]+Task[[:space:]]+" id "([[:space:]]|$)")) ||
                 (line ~ ("^Task[[:space:]]*(ID)?[[:space:]]*[:#][[:space:]]*" id "([[:space:]]|$)"))
        }
        NR > start && is_any_task_header($0) && !is_self_task_header($0, id) { print NR; exit }
      ' "$src" 2>/dev/null || true)
      local end_line
      if [[ -n "$next_line" ]]; then
        end_line=$((next_line - 1))
      else
        end_line=$(wc -l < "$src" 2>/dev/null | tr -d '[:space:]')
        [[ -z "$end_line" || "$end_line" == "0" ]] && end_line="$start_line"
      fi
      sed -n "${start_line},${end_line}p" "$src" 2>/dev/null || true
      return 0
    done
  done < <(list_active_plans)

  return 0
}

# ============================================================
# Returns 0 if the evidence section contains at least one
# functionality marker (i.e. demonstrates user-observable
# behavior), 1 if only component-level signals are present.
#
# Functionality markers (any one is sufficient):
#   - "playwright" (E2E driving the UI)
#   - "curl " (live endpoint hit with real payload)
#   - "Wire check executed" (end-to-end trace captured)
#   - "runtime_evidence" (structured .evidence.json with runtime check)
#   - "Prove it works" (per-task scenario block executed)
#   - "Runtime verification (after)" (fix-task after-state)
#   - "Runtime verification: sql" (DB-state confirmation of a side effect)
#
# Component-only signals (these alone trigger the warning):
#   - "test <file>::<unit-name>" (unit test in isolation)
#   - "file <path>::<pattern>" (existence/regex grep)
#   - "typecheck" / "lint" / "compiles"
# ============================================================
evidence_has_functionality_demonstration() {
  local section="$1"
  [[ -z "$section" ]] && return 1
  if printf '%s\n' "$section" | grep -qiE '(playwright|curl[[:space:]]|Wire[[:space:]]+check[[:space:]]+executed|runtime_evidence|Prove[[:space:]]+it[[:space:]]+works|Runtime[[:space:]]+verification[[:space:]]+\(after\)|Runtime[[:space:]]+verification:[[:space:]]*sql)'; then
    return 0
  fi
  return 1
}

# ============================================================
# Non-blocking warning emitter. Calls extract + functionality
# check; if the evidence is component-only, emits a stderr
# warning. Always returns 0 — never blocks.
# ============================================================
check_functionality_demonstration() {
  local task_id="$1"
  [[ -z "$task_id" ]] && return 0
  local section
  section=$(extract_task_evidence_section "$task_id" 2>/dev/null || echo "")
  [[ -z "$section" ]] && return 0
  if evidence_has_functionality_demonstration "$section"; then
    return 0
  fi
  cat >&2 <<MSG

================================================================
WARNING: task-completed-evidence-gate — functionality demonstration not detected
================================================================
Task ${task_id} has an evidence block, but the evidence appears to
demonstrate only component behavior (unit tests, file existence,
typecheck/lint, "compiles successfully") — NOT user-facing
functionality.

The harness's most important rule
(~/.claude/doctrine/planning.md "FUNCTIONALITY OVER COMPONENTS")
says: a task is done when a user can perform the action the task
describes and get the expected result, not when the components
compile and unit tests pass.

Functionality demonstration would include at least one of:
  - playwright <spec>::<test-name>    UI flow against running app
  - curl <command>                    live endpoint hit with real payload
  - sql SELECT/INSERT/UPDATE/DELETE   DB-state confirmation
  - "Wire check executed:" line       end-to-end trace
  - Runtime verification (after):     fix-task after-state
  - runtime_evidence array            structured .evidence.json

If the task is genuinely component-only (harness-internal refactor
with no user-facing surface, doc-only change, pure config edit),
this warning is informational. Otherwise, re-substantiate with
functionality evidence before relying on this completion.

This is a WARNING, not a BLOCK. TaskCompleted is allowed to
proceed — but the verifier and any human reader should look closer.
================================================================
MSG
  return 0
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
  local hook_event task_id team_name session_id
  hook_event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
  task_id=$(printf '%s' "$input" | jq -r '.task_id // ""' 2>/dev/null || echo "")
  team_name=$(printf '%s' "$input" | jq -r '.team_name // ""' 2>/dev/null || echo "")
  session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")

  # Resetting the per-teammate sub-counter happens unconditionally
  # before any blocking decisions: regardless of audit/evidence
  # outcome, this TaskCompleted event marks a natural restart point
  # for the per-teammate counter (Task 6 contract).
  if [[ -n "$session_id" ]]; then
    reset_per_teammate_counter "$session_id"
  fi

  # ---------- Bypass path (§D.0.5: the bypass_evidence_check EVENT FIELD
  # hatch is DELETED — PROVEN unreachable, nothing on the agent tool
  # surface can set it; TaskUpdate has no such param and task metadata
  # does not flow into the hook event. The only legitimate valves left
  # are: this env-level maintainer escape hatch, the plan-scoping fix
  # below (which removes the false-positive class that made a bypass
  # tempting in the first place), and HARNESS_SELFTEST sandboxing.)
  if [[ "${TASK_COMPLETED_BYPASS:-0}" == "1" ]]; then
    # Audit log: record bypass usage
    local logd
    logd="$(state_dir)/task-completed-bypass.log"
    {
      printf '%s task=%s team=%s session=%s reason=env\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown-time')" \
        "${task_id:-<none>}" "${team_name:-<none>}" "${session_id:-<none>}"
    } >> "$logd" 2>/dev/null || true
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-completed-evidence-gate" "waiver" "env-bypass task=${task_id:-<none>}"
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

  # ---------- Layer 1: evidence enforcement (§D.0.5 PLAN-SCOPED)
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

    # §D.0.5: block ONLY when the completed task_id is DECLARED by an
    # ACTIVE plan's own task list (evidence_exists_for_task already
    # confirmed no matching evidence block exists — this second check
    # decides whether that absence is blocking or merely a warn). An
    # ad-hoc / session-log task completion (invented to satisfy some
    # other mechanism's demand, e.g. workstreams-task-binding's retired
    # mutation-count Stop-block) belongs to no plan and gets a
    # non-blocking ledger warn instead of a block — the collision this
    # kills is documented in §D.0.5.
    if ! task_id_declared_by_active_plan "$task_id"; then
      printf 'task-completed-evidence-gate: warning — task_id "%s" is not declared by any ACTIVE plan (ad-hoc/session-log completion); evidence check downgraded to warn\n' "$task_id" >&2
      command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-completed-evidence-gate" "warn" "ad-hoc task_id=${task_id} no evidence, not plan-declared"
      return 0
    fi

    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-completed-evidence-gate" "block" "plan-declared task_id=${task_id} missing evidence"
    emit_block "no evidence block found for task_id \"$task_id\"" "\
The TaskCompleted event references task_id=\"$task_id\", which IS
declared in an ACTIVE plan's task list, but no matching evidence block
was found.

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
  - Or, for env-level bypass: set TASK_COMPLETED_BYPASS=1 (maintainer
    escape hatch; usage is logged to $(state_dir)/task-completed-bypass.log
    for periodic review).

This block exists because evidence-first is the harness's
load-bearing anti-vaporware mechanism (see
~/.claude/doctrine/vaporware-prevention.md)."
  fi

  # ---------- Layer 3: FUNCTIONALITY OVER COMPONENTS warning
  # Evidence exists. Check whether it demonstrates user-facing
  # functionality or only component behavior. NON-BLOCKING.
  check_functionality_demonstration "$task_id"

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

  # Active plan with evidence companion containing Task 3.2 block.
  # §D.0.5: Layer 1 is now plan-scoped, so the plan's OWN task list
  # must declare a task_id for that id's absent-evidence case to BLOCK.
  # 9.9 and 3.2/3.3 are declared here; 42.1 (used by the new ad-hoc
  # scenario) is deliberately NOT declared anywhere.
  cat > "$scratch/docs/plans/p1.md" <<'PLAN'
# Plan: P1
Status: ACTIVE

## Tasks
- [ ] 9.9 undeclared-evidence probe task
- [x] 3.2 Build duplicate
- [x] 3.3 Component-only fixture
PLAN
  cat > "$scratch/docs/plans/p1-evidence.md" <<'EV'
# Evidence Log

## Task 3.2 — Build duplicate
Task ID: 3.2
Verdict: PASS
Notes: did the work
Runtime verification: curl http://localhost:3000/api/foo

## Task 3.3 — Component-only fixture
Task ID: 3.3
Verdict: PASS
Notes: typecheck clean, lint clean
Runtime verification: test src/foo.spec.ts::should compute correctly
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
  # evidence file BUT IS declared in p1.md's ## Tasks list (§D.0.5
  # plan-scoping requires declaration for the block to fire); team_name
  # set so we go through full flow → BLOCK
  run_scenario "D1. rejects missing evidence (plan-declared) → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCompleted","task_id":"9.9","team_name":"demo","session_id":"s1"}'

  # D2 — allows-evidence-present: task_id="3.2" present in p1-evidence.md
  run_scenario "D2. allows evidence present → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.2","team_name":"demo","session_id":"s2"}'

  # D3 — allows env-level bypass (TASK_COMPLETED_BYPASS=1). The
  # event-field bypass_evidence_check hatch this scenario used to
  # exercise was DELETED at Wave D.6 (§D.0.5 — PROVEN unreachable: no
  # agent-facing tool surface could ever set it). The only bypass valve
  # left is this env var.
  run_scenario "D3. allows env-level TASK_COMPLETED_BYPASS=1 → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"9.9","team_name":"demo","session_id":"s3"}' \
    'export TASK_COMPLETED_BYPASS=1' \
    'unset TASK_COMPLETED_BYPASS'

  # D3b (§D.0.5 MANDATED): ad-hoc task completes without evidence →
  # allow + warn. task_id="42.1" is NOT declared by ANY active plan's
  # task list (see p1.md above) — this is the session-log/invented-task
  # shape workstreams-task-binding's retired Stop-block used to force.
  # Must ALLOW (not block) and emit a warning to stderr.
  run_scenario "D3b. ad-hoc task (not plan-declared) completes without evidence → ALLOW + warn" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"42.1","team_name":"demo","session_id":"s3b"}' \
    '' \
    'grep -q "not declared by any ACTIVE plan" "$scratch/err-$total.log"'

  # D3c (§D.0.5 MANDATED): plan-declared task completes without evidence
  # → block. Same assertion as D1 restated explicitly under the
  # mandated scenario name/wording from the plan spec, using a
  # DIFFERENT declared-but-evidence-less id so it's independent of D1's
  # fixture state.
  run_scenario "D3c. plan-declared task completes without evidence → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCompleted","task_id":"9.9","team_name":"demo","session_id":"s3c"}'

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

  # D7 — FUNCTIONALITY OVER COMPONENTS: component-only evidence emits
  # warning to stderr but does NOT block. Task 3.3 has only
  # "Runtime verification: test ..." — a unit test reference with no
  # functionality marker.
  run_scenario "D7. component-only evidence → ALLOW + warning emitted" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.3","team_name":"demo","session_id":"s7"}' \
    '' \
    'grep -q "functionality demonstration not detected" "$scratch/err-$total.log"'

  # D8 — FUNCTIONALITY OVER COMPONENTS: evidence with functionality
  # marker (curl) suppresses the warning. Task 3.2 has a curl line
  # in its evidence.
  run_scenario "D8. functionality marker present → ALLOW + no warning" \
    0 \
    '{"hook_event_name":"TaskCompleted","task_id":"3.2","team_name":"demo","session_id":"s8"}' \
    '' \
    '! grep -q "functionality demonstration not detected" "$scratch/err-$total.log"'

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
