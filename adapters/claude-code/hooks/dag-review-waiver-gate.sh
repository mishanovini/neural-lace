#!/bin/bash
# dag-review-waiver-gate.sh — C7-DAG-waiver
#
# PreToolUse hook on the `Task` tool. Blocks the FIRST `Task` invocation
# in a session for a Tier 3+ active plan unless a DAG-approval waiver
# exists at:
#   .claude/state/dag-approved-<plan-slug>-*.txt
# with >=40 chars of substantive content.
#
# Plan: docs/plans/phase-1d-c-1-low-risk-mechanisms.md (Task T3)
# Rule: ~/.claude/rules/vaporware-prevention.md (T5 lands the row)
#
# Operationalizes the Builder/Planner role boundary at dispatch time.
# Plans dispatching at Tier 3+ without DAG review ship work whose
# dependencies, parallelism, and decomposition haven't been validated.
#
# Behavior:
#   - Tool != Task               -> allow (silent, exit 0)
#   - No active plan             -> allow (gate doesn't apply)
#   - Tier < 3 or no Tier field  -> allow
#   - Per-session marker present -> allow (already gated this session)
#   - Substantive waiver present -> allow + write per-session marker
#   - Otherwise                  -> BLOCK (exit 2, JSON decision on stdout)
#
# Multiple ACTIVE plans: ALL must allow; block on first failing plan.
#
# Self-test: bash dag-review-waiver-gate.sh --self-test
# Expected: 6/6 PASS, exit 0.
#
# Exit codes:
#   0 — Task may dispatch
#   2 — Task is blocked; stderr explains why; stdout has JSON block decision

set -u

# ============================================================
# Self-test entry point (handled BEFORE any input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

# ============================================================
# Resolve own path for self-test re-entry
# ============================================================
SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) ;;
  *) SELF_PATH="$PWD/$SELF_PATH" ;;
esac

# ============================================================
# Helpers
# ============================================================

# Read stdin JSON or CLAUDE_TOOL_INPUT env var. Emit on stdout.
load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  printf '%s' "$input"
}

# Discover active plans under docs/plans/*.md (top-level only).
# Emits one path per line on stdout.
discover_active_plans() {
  local plans_dir="${PLANS_DIR_OVERRIDE:-docs/plans}"
  [[ -d "$plans_dir" ]] || return 0
  local f
  for f in "$plans_dir"/*.md; do
    [[ -f "$f" ]] || continue
    # Look for "Status: ACTIVE" in the first 30 lines (case-sensitive
    # for canonical form; also accept "status: ACTIVE" variant).
    if head -n 30 "$f" 2>/dev/null | grep -qiE '^[[:space:]]*\**[[:space:]]*Status[[:space:]]*:?\**[[:space:]]*ACTIVE'; then
      echo "$f"
    fi
  done
}

# Parse the Tier value from a plan's first 30 lines.
# Accepted forms (lenient on whitespace, quoting, bold markers):
#   Tier: <N>
#   tier: <N>
#   **Tier:** <N>
#   Work-sizing tier: <N>
#   work-sizing-tier: <N>
#   Tier: "<N>"  (YAML frontmatter style)
# Emits the integer value (or 1 if not found, treating no-tier as Tier 1).
parse_tier() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || { echo "1"; return; }

  local header
  header=$(head -n 30 "$plan_file" 2>/dev/null)
  [[ -z "$header" ]] && { echo "1"; return; }

  # Try patterns in order. Take first non-zero match.
  # Pattern 1: any "tier" or "work-sizing-tier" line (case-insensitive)
  # capturing the first integer that follows.
  local val
  val=$(printf '%s' "$header" | grep -iE '^[[:space:]]*\**[[:space:]]*(work[- ]sizing[- ]tier|tier)[[:space:]]*:?\**' | \
        head -n 1 | \
        grep -oE '[0-9]+' | \
        head -n 1 || true)

  if [[ -n "$val" && "$val" =~ ^[0-9]+$ && "$val" != "0" ]]; then
    echo "$val"
    return
  fi

  echo "1"
}

# Compute the plan slug (basename minus .md, ASCII-normalized).
plan_slug() {
  local plan_file="$1"
  local base
  base=$(basename "$plan_file" .md)
  # Defensive ASCII normalization: replace anything outside [A-Za-z0-9._-] with '-'.
  printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Compute the session marker filename for a given plan slug.
session_marker_path() {
  local slug="$1"
  local state_dir="${STATE_DIR_OVERRIDE:-.claude/state}"
  local sid="${CLAUDE_SESSION_ID:-default}"
  # Sanitize session id similarly.
  sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
  [[ -z "$sid" ]] && sid="default"
  echo "${state_dir}/dag-checked-${sid}-${slug}.txt"
}

# Look for any waiver file matching .claude/state/dag-approved-<slug>-*.txt
# whose content has >=40 non-whitespace chars. Emit the first matching path
# on stdout if found; otherwise emit nothing.
find_substantive_waiver() {
  local slug="$1"
  local state_dir="${STATE_DIR_OVERRIDE:-.claude/state}"
  [[ -d "$state_dir" ]] || return 1

  local f content_chars
  for f in "$state_dir"/dag-approved-"$slug"-*.txt; do
    [[ -f "$f" ]] || continue
    # Count non-whitespace chars
    content_chars=$(tr -d '[:space:]' < "$f" 2>/dev/null | wc -c | tr -d '[:space:]')
    [[ -z "$content_chars" ]] && content_chars=0
    if [[ "$content_chars" -ge 40 ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# Write the per-session marker (idempotent).
write_session_marker() {
  local slug="$1"
  local waiver_path="$2"
  local marker
  marker=$(session_marker_path "$slug")
  local marker_dir
  marker_dir=$(dirname "$marker")
  mkdir -p "$marker_dir" 2>/dev/null || return 1
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
  printf 'dag-approved at %s via waiver %s\n' "$ts" "$waiver_path" > "$marker" 2>/dev/null || return 1
  return 0
}

# Emit the structured block message + JSON decision, then exit 2.
emit_block() {
  local plan_path="$1"
  local tier="$2"
  local slug="$3"

  cat >&2 <<MSG
================================================================
DAG-WAIVER GATE — BLOCKED
================================================================

Tier 3+ work cannot dispatch without DAG review.

Plan: $plan_path (Tier $tier)

Required action: review the plan's task DAG with the user, then
create one of:
  .claude/state/dag-approved-${slug}-<timestamp>.txt

with >=40 chars explaining the DAG was reviewed and approved.

Why this gate exists: plans dispatching at Tier 3+ without DAG
review ship work whose dependencies, parallelism, and
decomposition have not been validated. The Builder/Planner role
boundary requires the human (or designated authority) to confirm
the DAG before dispatch.

Operationalizes: 04-gates.md gate 6.1 (DAG review human checkpoint)
plus 02-roles.md Orchestrator role.
================================================================
MSG

  cat <<JSON
{"decision": "block", "reason": "DAG-waiver gate: Tier $tier plan '$plan_path' has no DAG-approval waiver. Create .claude/state/dag-approved-${slug}-<timestamp>.txt with >=40 chars of justification."}
JSON

  exit 2
}

# ============================================================
# Main inspection logic
# ============================================================
inspect_dispatch() {
  local input="$1"

  # Tool-name guard — only fire on Task tool calls.
  local tool_name
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  if [[ "$tool_name" != "Task" ]]; then
    return 0
  fi

  # Discover active plans
  local active_plans
  active_plans=$(discover_active_plans)
  if [[ -z "$active_plans" ]]; then
    # No active plan → gate doesn't apply
    return 0
  fi

  # For each active plan: if Tier >= 3, require waiver or marker.
  local plan_path tier slug marker waiver
  while IFS= read -r plan_path; do
    [[ -z "$plan_path" ]] && continue

    tier=$(parse_tier "$plan_path")
    if [[ "$tier" -lt 3 ]]; then
      # Tier < 3, this plan doesn't gate; continue to next plan.
      continue
    fi

    slug=$(plan_slug "$plan_path")
    [[ -z "$slug" ]] && slug="unknown-plan"

    # Per-session marker check
    marker=$(session_marker_path "$slug")
    if [[ -f "$marker" ]]; then
      # Already gated this session for this plan; allow.
      continue
    fi

    # Look for substantive waiver
    waiver=$(find_substantive_waiver "$slug" || true)
    if [[ -n "$waiver" ]]; then
      # Write marker so subsequent invocations don't re-gate.
      write_session_marker "$slug" "$waiver" || true
      continue
    fi

    # No marker, no substantive waiver → BLOCK.
    emit_block "$plan_path" "$tier" "$slug"
  done <<< "$active_plans"

  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local total=0 passed=0 failed_names=""
  local scratch
  scratch=$(mktemp -d -t dagwvr-XXXXXX) || { echo "mktemp FAIL"; exit 1; }
  trap 'rm -rf "$scratch"' EXIT

  echo "dag-review-waiver-gate self-test"
  echo "================================="

  # Helper: run one scenario.
  # $1 name, $2 expected exit (0 or 2), $3 plan content (or 'none' for no plan),
  # $4 plan filename (slug.md), $5 stdin JSON (tool-input),
  # $6 waiver content (or 'none'), $7 pre-existing marker (or 'none'),
  # $8 session id override
  run_scenario() {
    local name="$1"
    local expect="$2"
    local plan_content="$3"
    local plan_filename="$4"
    local stdin_json="$5"
    local waiver_content="$6"
    local existing_marker="$7"
    local sid="$8"

    total=$((total+1))
    local case_dir="$scratch/case-$total"
    mkdir -p "$case_dir/docs/plans" "$case_dir/.claude/state"

    # Plan setup
    if [[ "$plan_content" != "none" ]]; then
      printf '%s' "$plan_content" > "$case_dir/docs/plans/$plan_filename"
    fi

    # Compute slug for waiver/marker placement (matches plan_slug logic).
    local slug
    slug=$(printf '%s' "${plan_filename%.md}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')

    # Waiver setup
    if [[ "$waiver_content" != "none" ]]; then
      printf '%s' "$waiver_content" > "$case_dir/.claude/state/dag-approved-${slug}-20260503000000.txt"
    fi

    # Pre-existing marker setup
    if [[ "$existing_marker" != "none" ]]; then
      local sid_norm
      sid_norm=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
      [[ -z "$sid_norm" ]] && sid_norm="default"
      printf '%s' "$existing_marker" > "$case_dir/.claude/state/dag-checked-${sid_norm}-${slug}.txt"
    fi

    local exit_code
    set +e
    (
      cd "$case_dir" || exit 99
      echo "$stdin_json" | env CLAUDE_SESSION_ID="$sid" \
        bash "$SELF_PATH" >/dev/null 2>"$case_dir/err.log"
    )
    exit_code=$?
    set -e

    if [[ "$exit_code" == "$expect" ]]; then
      passed=$((passed+1))
      printf '  ok   %-3d %s\n' "$total" "$name"
    else
      printf '  FAIL %-3d %s (expected exit=%s, got exit=%s)\n' \
        "$total" "$name" "$expect" "$exit_code"
      printf '       stderr: %s\n' "$(head -3 "$case_dir/err.log" 2>/dev/null | tr '\n' ' ')"
      failed_names="$failed_names\n  - $name"
    fi
  }

  # Plan templates
  local TIER1_PLAN="# Plan: Tier 1 demo
Status: ACTIVE
Tier: 1
Mode: code

## Goal
Trivial plan."

  local TIER3_PLAN="# Plan: Tier 3 demo
Status: ACTIVE
Tier: 3
Mode: design

## Goal
Substantial plan needing DAG review."

  # Stdin payloads (Task tool invocations)
  local TASK_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","prompt":"build something"}}'
  local NON_TASK_JSON='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo","old_string":"a","new_string":"b"}}'

  local SUBSTANTIVE_WAIVER="DAG reviewed with user 2026-05-03; tasks T1/T2/T3 confirmed parallel-safe; T4-T6 sequential. Approved."
  local SHORT_WAIVER="ok"

  # ---- Scenario 1: Pass — Tier 1 plan, no waiver, no marker ----
  run_scenario "S1. Tier 1 plan -> ALLOW" 0 \
    "$TIER1_PLAN" "tier1-demo.md" \
    "$TASK_JSON" "none" "none" "test-session-1"

  # ---- Scenario 2: Pass — no active plan ----
  run_scenario "S2. no active plan -> ALLOW" 0 \
    "none" "ignored.md" \
    "$TASK_JSON" "none" "none" "test-session-2"

  # ---- Scenario 3: Pass — Tier 3 plan with substantive waiver ----
  run_scenario "S3. Tier 3 + substantive waiver -> ALLOW" 0 \
    "$TIER3_PLAN" "tier3-demo.md" \
    "$TASK_JSON" "$SUBSTANTIVE_WAIVER" "none" "test-session-3"

  # ---- Scenario 4: Pass — Tier 3 plan with pre-existing session marker ----
  run_scenario "S4. Tier 3 + marker present (second invocation) -> ALLOW" 0 \
    "$TIER3_PLAN" "tier3-demo.md" \
    "$TASK_JSON" "none" "marker-from-first-invocation" "test-session-4"

  # ---- Scenario 5: Fail — Tier 3 plan, no waiver, no marker ----
  run_scenario "S5. Tier 3, no waiver, no marker -> BLOCK" 2 \
    "$TIER3_PLAN" "tier3-demo.md" \
    "$TASK_JSON" "none" "none" "test-session-5"

  # ---- Scenario 6: Fail — Tier 3 with too-short waiver ----
  run_scenario "S6. Tier 3 + short waiver (<40 chars) -> BLOCK" 2 \
    "$TIER3_PLAN" "tier3-demo.md" \
    "$TASK_JSON" "$SHORT_WAIVER" "none" "test-session-6"

  # ---- Bonus: non-Task tool always allowed (sanity) ----
  run_scenario "S7. non-Task tool (Edit) -> ALLOW (sanity)" 0 \
    "$TIER3_PLAN" "tier3-demo.md" \
    "$NON_TASK_JSON" "none" "none" "test-session-7"

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

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  run_self_test
fi

INPUT=$(load_input)
if [[ -z "$INPUT" ]]; then
  exit 0
fi

inspect_dispatch "$INPUT"
exit 0
