#!/bin/bash
# task-created-validator.sh
#
# TaskCreated event hook for Anthropic's Agent Teams feature.
# Validates that newly-created teammate tasks have substantive
# subjects and reference an active plan file with acceptance
# criteria, before allowing the task to be dispatched.
#
# Plan: docs/plans/agent-teams-integration.md (Task 7)
# Rule: adapters/claude-code/rules/agent-teams.md (lands with Task 11)
#
# Three rejection conditions:
#   (a) task_subject is too short or generic — under 10 chars OR
#       a single generic word (TODO/fix/bug/wip).
#   (b) task_description doesn't reference any active plan file
#       (slug from docs/plans/*.md or path docs/plans/<slug>.md).
#       Skipped (allow) if no ACTIVE plans exist — team-init case.
#   (c) task_description doesn't reference acceptance criteria
#       or a Done-when clause.
#
# Defaults to ALLOW when ambiguous:
#   - Missing event input → allow (event semantics not active)
#   - Missing team_name → allow (solo session)
#   - No active plans found → allow (team initialization)
#   - Bypass via TASK_CREATED_BYPASS=1 env or bypass_validation: true
#     (both ledger-logged as a "waiver" signal — F.5 waiver-parity audit
#     row 2 / ADR 059 D4 fix: the previous env/field bypass was NOT
#     ledger-logged, so it could not be audited via ledger_tail like
#     every other waiver in the harness. Fixed here.)
#   - Fresh (<1h) structured waiver file naming BOTH purpose clauses
#     (lib/waiver-purpose-clause.sh) at
#     .claude/state/task-created-waiver-*.txt — the D4-shaped hatch
#     for a substantive one-off, distinct from the env/field bypasses
#     above (which are unconditional, session-wide switches).
#
# Exit codes:
#   0 — task creation allowed (silent)
#   2 — task creation blocked (stderr explains; PreToolUse "block"
#       convention)
#
# Self-test:
#   bash task-created-validator.sh --self-test
# Expected all PASS, exit 0.

set -e

# ============================================================
# Shared libs (best-effort; hook degrades gracefully if absent)
# ============================================================
_TCV_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/signal-ledger.sh
source "$_TCV_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_TCV_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true

# ============================================================
# Fresh substantive structured-waiver release valve (ADR 059 D4;
# F.5 waiver-parity audit row 2). Mirrors bug-persistence-gate.sh /
# workstreams-state-gate.sh: a fresh (<1h) .claude/state/
# task-created-waiver-*.txt file naming BOTH purpose clauses.
# ============================================================
TCV_STATE_DIR="${CLAUDE_STATE_DIR:-.claude/state}"
TCV_WAIVER_GLOB='task-created-waiver-*.txt'

_tcv_has_fresh_waiver() {
  [[ -d "$TCV_STATE_DIR" ]] || return 1
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" && { printf '%s' "$f"; return 0; }
    fi
  done < <(find "$TCV_STATE_DIR" -maxdepth 1 -type f -name "$TCV_WAIVER_GLOB" -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================
# Self-test entry point (handled BEFORE input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

# ============================================================
# Generic single-word subjects that are never substantive enough
# to identify a task. Case-insensitive match.
# ============================================================
GENERIC_SUBJECTS=(
  "todo"
  "fix"
  "bug"
  "wip"
  "tbd"
  "stuff"
  "task"
  "thing"
  "asap"
  "do"
)

is_generic_subject() {
  local subj="$1"
  local lower
  lower=$(printf '%s' "$subj" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:][:punct:]')
  local g
  for g in "${GENERIC_SUBJECTS[@]}"; do
    if [[ "$lower" == "$g" ]]; then
      return 0
    fi
  done
  return 1
}

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
# Reject helper — exit 2 with a structured stderr message AND a
# Claude-Code-readable JSON block on stdout.
# ============================================================
emit_block() {
  local title="$1"
  local body="$2"
  cat >&2 <<MSG

================================================================
BLOCKED: task-created-validator — $title
================================================================
$body

This gate: ~/.claude/hooks/task-created-validator.sh (source: adapters/claude-code/hooks/task-created-validator.sh)
MSG
  # Some Claude Code event handlers honor stdout JSON. Emit a
  # block decision for completeness; stderr+exit-2 is the
  # canonical path.
  printf '{"continue": false, "stopReason": "%s"}\n' "$title" || true
  exit 2
}

# ============================================================
# Active-plan slug enumeration. Reads docs/plans/*.md (top-level
# only, archive excluded) and prints one slug per line. A slug is
# the basename minus .md and minus -evidence suffix.
# ============================================================
list_active_plan_slugs() {
  local plans_dir="${PLANS_DIR_OVERRIDE:-docs/plans}"
  [[ -d "$plans_dir" ]] || return 0
  local f
  for f in "$plans_dir"/*.md; do
    [[ -f "$f" ]] || continue
    # Skip evidence companions
    case "$f" in
      *-evidence.md) continue ;;
    esac
    # Optional Status filter — only emit ACTIVE plans
    local status
    status=$(grep -m1 -oE '^Status:[[:space:]]*[A-Z]+' "$f" 2>/dev/null | awk '{print $2}')
    case "$status" in
      ACTIVE|"") ;;  # ACTIVE or status unspecified: include
      *) continue ;;
    esac
    local base
    base=$(basename "$f" .md)
    printf '%s\n' "$base"
  done
}

# ============================================================
# Inspect the event input and apply validation rules.
# ============================================================
inspect_task_created() {
  local input="$1"

  # Extract event fields. All optional; missing → empty string.
  local hook_event task_id task_subject task_description team_name bypass
  hook_event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
  task_id=$(printf '%s' "$input" | jq -r '.task_id // ""' 2>/dev/null || echo "")
  task_subject=$(printf '%s' "$input" | jq -r '.task_subject // ""' 2>/dev/null || echo "")
  task_description=$(printf '%s' "$input" | jq -r '.task_description // ""' 2>/dev/null || echo "")
  team_name=$(printf '%s' "$input" | jq -r '.team_name // ""' 2>/dev/null || echo "")
  bypass=$(printf '%s' "$input" | jq -r '.bypass_validation // empty' 2>/dev/null || echo "")

  # ---------- Bypass paths (env / field — unconditional, session-wide;
  # now ledger-logged per F.5 waiver-parity audit row 2 / ADR 059 D4 fix)
  if [[ "${TASK_CREATED_BYPASS:-0}" == "1" ]]; then
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-created-validator" "waiver" "env-bypass task_id=${task_id:-<none>}"
    return 0
  fi
  if [[ "$bypass" == "true" ]]; then
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-created-validator" "waiver" "field-bypass task_id=${task_id:-<none>}"
    return 0
  fi

  # ---------- Structured-waiver release valve (ADR 059 D4; distinct
  # from the two unconditional switches above — a fresh, substantive,
  # purpose-clause-validated one-off for a single TaskCreated event).
  local tcv_waiver_file
  if tcv_waiver_file=$(_tcv_has_fresh_waiver); then
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "task-created-validator" "waiver" "structured-waiver task_id=${task_id:-<none>} file=$tcv_waiver_file"
    return 0
  fi

  # ---------- Solo session — no team_name → not a team task
  # Treat missing team_name as "not an Agent Teams event"; allow.
  if [[ -z "$team_name" ]]; then
    return 0
  fi

  # ---------- (a) subject substance
  # Rule: subject must be at least 10 non-whitespace chars AND
  # not a generic single-word subject.
  local subj_compact
  subj_compact=$(printf '%s' "$task_subject" | tr -d '[:space:]')
  local subj_len=${#subj_compact}
  if [[ "$subj_len" -lt 10 ]]; then
    emit_block "task_subject is too short" "\
Received task_subject=\"$task_subject\" (${subj_len} non-whitespace
chars). Tasks must have a subject of at least 10 chars that
identifies the work concretely.

Substantive examples:
  - \"Implement campaign-duplicate flow\"
  - \"Add RLS policy for contacts.notes column\"
  - \"Wire RequiredLabel into 14 forms (sweep)\"

Re-issue the TaskCreate with a subject that names the actual work.

Hatch (cost: bypasses ALL three checks in this hook, ledger-logged):
  1. One-off, substantive: write a fresh (<1h) structured waiver
     naming BOTH clauses (mirrors bug-persistence-gate.sh):
       mkdir -p .claude/state && printf \
         'Purpose: this gate exists to prevent <X>\nBecause: <Y>\n' \
         > .claude/state/task-created-waiver-\$(date +%s).txt
  2. Session-wide switch (cost: disables this hook for every
     TaskCreated event until unset): TASK_CREATED_BYPASS=1, or
     bypass_validation: true on the event input."
  fi
  if is_generic_subject "$task_subject"; then
    emit_block "task_subject is generic" "\
Received task_subject=\"$task_subject\". Single generic words like
\"TODO\", \"fix\", \"bug\", \"WIP\" do not identify work. The
teammate cannot align on what to build, the lead cannot verify
completion, and the audit trail is unrecoverable.

Re-issue the TaskCreate with a subject that names the actual work
this teammate will perform (verb + object + scope, ideally tied to
a plan task ID).

Hatch (cost: bypasses ALL three checks in this hook, ledger-logged):
  1. One-off, substantive: fresh (<1h) structured waiver naming
     BOTH clauses at .claude/state/task-created-waiver-*.txt
     (see lib/waiver-purpose-clause.sh).
  2. Session-wide switch: TASK_CREATED_BYPASS=1, or
     bypass_validation: true on the event input."
  fi

  # ---------- (b) plan reference
  # Build the list of active plan slugs. If the list is empty,
  # this is a team-init / no-plan case — allow.
  local active_slugs
  active_slugs=$(list_active_plan_slugs)
  if [[ -z "$active_slugs" ]]; then
    # No active plans found; nothing to reference.
    return 0
  fi

  local found=0
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    # Match the slug literally OR as docs/plans/<slug>.md path.
    if printf '%s' "$task_description" | grep -qF "$slug"; then
      found=1
      break
    fi
  done <<< "$active_slugs"

  if [[ "$found" == "0" ]]; then
    local sample
    sample=$(printf '%s\n' "$active_slugs" | head -3 | tr '\n' ' ')
    emit_block "task_description does not reference any active plan" "\
The task description does not reference any active plan file.
Active plans found in docs/plans/:
  $(printf '%s\n' "$active_slugs" | sed 's/^/  - /')

Update task_description to reference one of these plans, e.g.:
  \"Implements docs/plans/<slug>.md Task 3.2 acceptance criteria.\"

Hatch (cost: bypasses ALL three checks in this hook, ledger-logged):
  1. One-off, substantive: fresh (<1h) structured waiver naming
     BOTH clauses at .claude/state/task-created-waiver-*.txt
     (see lib/waiver-purpose-clause.sh) — for a task genuinely
     outside any active plan's scope.
  2. Session-wide switch: bypass_validation: true on the event
     input, or TASK_CREATED_BYPASS=1 — document the rationale in
     your TaskCreate prompt either way."
  fi

  # ---------- (c) acceptance criteria reference
  # The description should reference acceptance criteria, a
  # Done-when clause, or the plan task's checklist. Keep the
  # check broad — we just want a signal the teammate knows what
  # success looks like.
  local has_criteria=0
  if printf '%s' "$task_description" | grep -qiE 'done when:|acceptance|criteria|\bDone:|checkbox|done when\b|success criteria|task[[:space:]]*[0-9]'; then
    has_criteria=1
  fi
  if [[ "$has_criteria" == "0" ]]; then
    emit_block "task_description has no acceptance criteria" "\
The task description does not reference acceptance criteria, a
Done-when clause, or a plan task ID. Without these, the teammate
has no objective signal for completion and the lead has no basis
for verification.

Add one of:
  - \"Done when: <observable outcome>\"
  - \"Acceptance: <criteria from plan task X.Y>\"
  - Reference the plan task ID, e.g. \"plan task 3.2\"
  - Inline checkbox list of completion conditions

Hatch (cost: bypasses ALL three checks in this hook, ledger-logged):
  1. One-off, substantive: fresh (<1h) structured waiver naming
     BOTH clauses at .claude/state/task-created-waiver-*.txt
     (see lib/waiver-purpose-clause.sh).
  2. Session-wide switch: bypass_validation: true on the event
     input, or TASK_CREATED_BYPASS=1 — document why either way."
  fi

  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local total=0 passed=0 failed_names=""

  # Scratch dir for synthetic plan files
  local scratch
  scratch=$(mktemp -d -t taskcreate-XXXXXX) || { echo "mktemp FAIL"; exit 1; }
  trap 'rm -rf "$scratch"' EXIT

  # Build a synthetic plans dir with one ACTIVE plan
  mkdir -p "$scratch/docs/plans"
  cat > "$scratch/docs/plans/campaign-duplicate.md" <<'PLAN'
# Plan: Campaign Duplicate
Status: ACTIVE
## Tasks
- [ ] 1. Build duplicate
PLAN

  # run_scenario <name> <expect-exit:0|2> <event-input-json> [state-dir]
  run_scenario() {
    local name="$1"
    local expect="$2"
    local event_input="$3"
    local state_dir="${4:-$scratch/no-state}"
    total=$((total+1))

    local exit_code
    set +e
    env PLANS_DIR_OVERRIDE="$scratch/docs/plans" \
      CLAUDE_STATE_DIR="$state_dir" \
      CLAUDE_TOOL_INPUT="$event_input" \
      bash "$SELF_PATH" >"$scratch/out-$total.log" 2>"$scratch/err-$total.log"
    exit_code=$?
    set -e

    if [[ "$exit_code" == "$expect" ]]; then
      passed=$((passed+1))
      printf '  ok   %-3d %s\n' "$total" "$name"
    else
      printf '  FAIL %-3d %s (expected exit=%s, got exit=%s)\n' \
        "$total" "$name" "$expect" "$exit_code"
      printf '       stderr: %s\n' "$(head -3 "$scratch/err-$total.log" | tr '\n' ' ')"
      failed_names="$failed_names\n  - $name"
    fi
  }

  echo "task-created-validator self-test"
  echo "================================="

  # C1 — valid subject + plan reference + criteria → allow (exit 0)
  run_scenario "C1. valid subject + plan reference + criteria → ALLOW" \
    0 \
    '{"hook_event_name":"TaskCreated","task_id":"t1","team_name":"demo","task_subject":"Implement campaign-duplicate flow","task_description":"addresses docs/plans/campaign-duplicate.md acceptance criteria for plan task 3.2"}'

  # C2 — too-short subject ("fix") → reject (exit 2)
  run_scenario "C2. too-short subject → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCreated","task_id":"t2","team_name":"demo","task_subject":"fix","task_description":"docs/plans/campaign-duplicate.md plan task 3 acceptance"}'

  # C3 — missing plan reference (description has no slug) → reject
  run_scenario "C3. missing plan reference → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCreated","task_id":"t3","team_name":"demo","task_subject":"Implement something useful","task_description":"do the thing the user asked for; done when it works"}'

  # C4 — generic word subject (TODO) → reject
  run_scenario "C4. generic-word subject (TODO) → BLOCK" \
    2 \
    '{"hook_event_name":"TaskCreated","task_id":"t4","team_name":"demo","task_subject":"TODO","task_description":"docs/plans/campaign-duplicate.md acceptance for plan task 1"}'

  # ---------- Structured-waiver scenarios (F.5 waiver-parity audit row 2 /
  # ADR 059 D4). All three otherwise-blocking conditions (too-short subject,
  # missing plan reference, missing criteria) are exercised via ONE bad
  # event input (short generic subject, no plan ref, no criteria) so a
  # single waiver-honored/absent/stale trio proves the release valve
  # governs the whole hook, not just one condition.
  local waiver_bad_input='{"hook_event_name":"TaskCreated","task_id":"t5","team_name":"demo","task_subject":"fixit","task_description":"just do it"}'

  # W1 — waiver-absent-blocks: no waiver file at all → BLOCK (exit 2)
  local w_absent_dir="$scratch/state-absent/.claude/state"
  mkdir -p "$w_absent_dir"
  run_scenario "W1. waiver-absent → BLOCK" \
    2 \
    "$waiver_bad_input" \
    "$w_absent_dir"

  # W2 — waiver-honored: fresh (<1h) waiver with BOTH purpose clauses → ALLOW
  local w_honored_dir="$scratch/state-honored/.claude/state"
  mkdir -p "$w_honored_dir"
  {
    echo "Purpose: this gate exists to prevent under-specified teammate tasks"
    echo "Because: this is a self-test scenario exercising the waiver valve"
  } > "$w_honored_dir/task-created-waiver-selftest.txt"
  run_scenario "W2. waiver-honored (fresh + purpose-clauses) → ALLOW" \
    0 \
    "$waiver_bad_input" \
    "$w_honored_dir"

  # W3 — waiver-stale-rejected: waiver file has the purpose-clause pair but
  # is older than the 1h freshness window → BLOCK (exit 2), same as absent.
  local w_stale_dir="$scratch/state-stale/.claude/state"
  mkdir -p "$w_stale_dir"
  {
    echo "Purpose: this gate exists to prevent under-specified teammate tasks"
    echo "Because: this is a self-test scenario exercising the waiver valve"
  } > "$w_stale_dir/task-created-waiver-selftest.txt"
  # Backdate mtime to 2 hours ago so the <1h freshness window rejects it.
  if command -v touch >/dev/null 2>&1; then
    touch -d '2 hours ago' "$w_stale_dir/task-created-waiver-selftest.txt" 2>/dev/null \
      || touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$w_stale_dir/task-created-waiver-selftest.txt" 2>/dev/null \
      || true
  fi
  run_scenario "W3. waiver-stale (purpose-clauses but >1h old) → BLOCK" \
    2 \
    "$waiver_bad_input" \
    "$w_stale_dir"

  # W4 — regression guard: non-empty waiver WITHOUT the purpose-clause pair
  # does NOT open the valve (pin f) → BLOCK
  local w_weak_dir="$scratch/state-weak/.claude/state"
  mkdir -p "$w_weak_dir"
  printf 'just trust me on this one\n' > "$w_weak_dir/task-created-waiver-selftest.txt"
  run_scenario "W4. waiver present but lacks purpose-clauses → BLOCK" \
    2 \
    "$waiver_bad_input" \
    "$w_weak_dir"

  echo "================================="
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

inspect_task_created "$INPUT"
exit 0
