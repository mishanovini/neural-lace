#!/bin/bash
# teammate-spawn-validator.sh
#
# PreToolUse hook on Task|Agent matcher. Gates Agent Teams teammate
# spawns by reading ~/.claude/local/agent-teams.config.json (the
# feature-flag config introduced by Task 4 of the Agent Teams
# integration plan) and rejecting unsafe spawn configurations.
#
# Plan: docs/plans/agent-teams-integration.md (Task 5)
# Rule: adapters/claude-code/rules/agent-teams.md (Task 11 lands this)
#
# Four rejection conditions:
#   (a) enabled=false AND tool input has team_name set
#       → Agent Teams disabled; tell user how to enable.
#   (b) worktree_mandatory_for_write=true AND spawn lacks
#       isolation="worktree" AND spawned agent is write-capable.
#       → Filesystem-race risk; require worktree isolation.
#   (c) force_in_process=true AND lead session is in
#       --dangerously-skip-permissions mode.
#       → Permission bypass propagates to teammates; require explicit
#         opt-out of force_in_process.
#   (d) DAG-review waiver (folded from dag-review-waiver-gate.sh at NL
#       Overhaul Wave D.6 — that file retires to attic at D.5; its check
#       lives here now, ONE gate / ONE block message per §D.6 item 2).
#       tool_name == "Task" AND an ACTIVE plan at Tier >= 3 has no
#       DAG-approval waiver on file AND no per-session marker yet →
#       block until the DAG is reviewed with the user (see
#       `_dag_inspect_dispatch` below). Independent of the Agent Teams
#       config file — applies to any Task-tool dispatch, not just
#       team-config spawns, so it runs BEFORE the config_file_exists
#       early-return.
#
# Defaults to ALLOW when ambiguous. Better to let a teammate spawn
# than silently block legitimate work due to a hook bug.
#
# Self-test: bash teammate-spawn-validator.sh --self-test
# Expected: PASS, exit 0 (see file for current scenario count).
#
# Exit codes:
#   0 — spawn allowed (silent)
#   2 — spawn blocked (stderr explains why; exit 2 follows the
#       PreToolUse "block" convention used elsewhere in the harness
#       via JSON or stderr)

set -e

# ============================================================
# Self-test entry point (handled BEFORE input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

# ============================================================
# Read-only allowlist — agents whose spawn does not require worktree
# isolation under condition (b). These agents are documented (or
# expected) to perform research/review/verification only.
#
# Conservative: any agent NOT in this list is treated as write-capable.
# ============================================================
READ_ONLY_AGENTS=(
  "research"
  "explorer"
  "Explore"
  "task-verifier"
  "claim-reviewer"
  "plan-evidence-reviewer"
  "harness-reviewer"
  "systems-designer"
  "ux-designer"
  "code-reviewer"
  "security-reviewer"
  "enforcement-gap-analyzer"
  "Audience Content Reviewer"
  "UX End-User Tester"
  "Domain Expert Tester"
)

is_read_only_agent() {
  local agent="$1"
  [[ -z "$agent" ]] && return 1
  local a
  for a in "${READ_ONLY_AGENTS[@]}"; do
    if [[ "$agent" == "$a" ]]; then
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
# Config loading — graceful degradation when the file or any field
# is missing.
# ============================================================
load_config_field() {
  # $1 = field name, $2 = default value (printed verbatim if file absent
  # or field missing). Always prints exactly one value to stdout.
  local field="$1"
  local default="$2"
  local config_file="${AGENT_TEAMS_CONFIG_PATH:-$HOME/.claude/local/agent-teams.config.json}"
  if [[ ! -f "$config_file" ]]; then
    printf '%s' "$default"
    return 0
  fi
  local val
  val=$(jq -r ".${field} // empty" "$config_file" 2>/dev/null || echo "")
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

# Returns 0 if the config file exists, 1 otherwise.
config_file_exists() {
  local config_file="${AGENT_TEAMS_CONFIG_PATH:-$HOME/.claude/local/agent-teams.config.json}"
  [[ -f "$config_file" ]]
}

# ============================================================
# Reject helper — exit 2 with a structured stderr message.
# ============================================================
emit_block() {
  local title="$1"
  local body="$2"
  cat >&2 <<MSG

================================================================
BLOCKED: teammate-spawn-validator — $title
================================================================
$body
MSG
  exit 2
}

# ============================================================
# Permission-mode detection — best-effort. Returns 0 if the lead
# session is in bypassPermissions / --dangerously-skip-permissions
# mode, 1 otherwise. Defaults to "not bypassed" when no signal is
# available (allow side; per spec, log warning and allow).
# ============================================================
lead_is_dangerously_skipping_permissions() {
  # Direct env signal from Claude Code runtime
  case "${CLAUDE_PERMISSION_MODE:-}" in
    bypassPermissions|dangerouslySkipPermissions|skip)
      return 0
      ;;
  esac
  # Check user settings.json default mode (best effort, may not exist)
  local settings="$HOME/.claude/settings.json"
  if [[ -f "$settings" ]]; then
    local mode
    mode=$(jq -r '.defaultMode // empty' "$settings" 2>/dev/null || echo "")
    case "$mode" in
      bypassPermissions|dangerouslySkipPermissions)
        return 0
        ;;
    esac
  fi
  return 1
}

# ============================================================
# Customer-facing spawn-time WARN (D.4 relocation from
# customer-facing-review-gate.sh, a retired Stop hook — see that file's
# header for the full extraction note). NON-BLOCKING by design: this is a
# heads-up at spawn time, not a gate. The original gate's HARD REQUIREMENT
# (block session-wrap unless BOTH UX + customer-advocate agents were
# invoked) stays live in customer-facing-review-gate.sh's own Stop-hook
# enforcement until D.5's cutover retires it — this warn is additive, not a
# replacement, and it must never change that gate's blocking behavior.
#
# Classifier: STRONG match -> customer-facing. WEAK match AND no EXCLUSION
# match -> customer-facing. Patterns loaded from
# patterns/customer-facing-patterns.txt (same three classes, same match
# semantics as the original gate's inline STRONG_RE/WEAK_RE/EXCLUSION_RE).
# ============================================================

# _cfw_patterns_file — resolve the patterns data file path. Overridable for
# self-test via CFW_PATTERNS_FILE.
_cfw_patterns_file() {
  if [[ -n "${CFW_PATTERNS_FILE:-}" ]]; then
    printf '%s' "$CFW_PATTERNS_FILE"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s/../patterns/customer-facing-patterns.txt' "$here"
}

# _cfw_build_class_re <CLASS> — echo a single ERE alternation joining every
# fragment tagged <CLASS> in the patterns file, or empty if the file is
# missing/unreadable/has no entries for that class (fail-open: an absent
# patterns file means the warn simply never fires, never a hard error).
_cfw_build_class_re() {
  local class="$1" file
  file="$(_cfw_patterns_file)"
  [[ -f "$file" ]] || { printf ''; return 0; }
  awk -F'\t' -v c="$class" '
    /^[[:space:]]*#/ { next }
    NF < 2 { next }
    $1 == c { frags[n++] = $2 }
    END {
      out = ""
      for (i = 0; i < n; i++) {
        out = (out == "") ? frags[i] : out "|" frags[i]
      }
      print out
    }
  ' "$file" 2>/dev/null
}

# _cfw_is_customer_facing <blob> — 0 if the blob classifies customer-facing.
_cfw_is_customer_facing() {
  local blob="$1"
  local strong_re weak_re exclusion_re
  strong_re="$(_cfw_build_class_re STRONG)"
  weak_re="$(_cfw_build_class_re WEAK)"
  exclusion_re="$(_cfw_build_class_re EXCLUSION)"

  if [[ -n "$strong_re" ]] && printf '%s' "$blob" | LC_ALL=C grep -iEq "$strong_re" 2>/dev/null; then
    return 0
  fi
  if [[ -n "$weak_re" ]] && printf '%s' "$blob" | LC_ALL=C grep -iEq "$weak_re" 2>/dev/null; then
    if [[ -n "$exclusion_re" ]] && printf '%s' "$blob" | LC_ALL=C grep -iEq "$exclusion_re" 2>/dev/null; then
      return 1
    fi
    return 0
  fi
  return 1
}

# check_customer_facing_warn <input> — non-blocking. Emits a stderr warn +
# signal-ledger "warn" event when a Task/Agent spawn's blob matches the
# customer-facing classifier. ALWAYS returns 0 — never blocks, never affects
# the calling hook's exit code, independent of Agent Teams config/enabled
# state (unlike inspect_spawn's three rejection rules, this concern applies
# to every spawn regardless of team_name/isolation).
check_customer_facing_warn() {
  local input="$1"

  local tool_name
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  case "$tool_name" in
    Task|Agent) ;;
    *) return 0 ;;
  esac

  local prompt title tldr description cwd blob
  prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null || echo "")
  title=$(printf '%s' "$input" | jq -r '.tool_input.title // ""' 2>/dev/null || echo "")
  tldr=$(printf '%s' "$input" | jq -r '.tool_input.tldr // ""' 2>/dev/null || echo "")
  description=$(printf '%s' "$input" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
  cwd=$(printf '%s' "$input" | jq -r '.tool_input.cwd // ""' 2>/dev/null || echo "")
  blob="${prompt} ${title} ${tldr} ${description} ${cwd}"

  # Nothing to classify.
  [[ -z "${blob// /}" ]] && return 0

  if _cfw_is_customer_facing "$blob"; then
    echo "" >&2
    echo "[teammate-spawn-validator] NOTE (non-blocking): this spawn looks customer-facing" >&2
    echo "  (contractor UI / dashboard / navigation / support docs pattern matched)." >&2
    echo "  Per rules/customer-facing-review.md, customer-facing work should be reviewed" >&2
    echo "  by BOTH a UX agent and the customer-advocate agent (end-user-advocate) before" >&2
    echo "  the session wraps. This is a heads-up only — customer-facing-review-gate.sh" >&2
    echo "  still enforces the hard requirement at session Stop." >&2
    echo "" >&2

    # Ledger event — best-effort, sourced lazily so a missing lib never
    # breaks this (or any) spawn. HARNESS_SELFTEST sandboxes the write.
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
    if [[ -f "$lib_dir/signal-ledger.sh" ]]; then
      # shellcheck disable=SC1091
      source "$lib_dir/signal-ledger.sh"
      if declare -F ledger_emit >/dev/null 2>&1; then
        ledger_emit "teammate-spawn-validator" "warn" "customer-facing spawn detected (non-blocking; see customer-facing-review-gate.sh for the hard requirement)"
      fi
    fi
  fi
  return 0
}

# ============================================================
# DAG-review waiver check (folded from dag-review-waiver-gate.sh at NL
# Overhaul Wave D.6, §D.6 item 2). Every helper below is namespaced
# `_dag_*` to stay surgically scoped within this file — dag-review-
# waiver-gate.sh itself stays in place (attic at D.5) with a header
# note pointing here; this is the live behavior going forward.
#
# Behavior (unchanged from the standalone gate):
#   - Tool != Task               -> allow (silent, exit 0)
#   - No active plan             -> allow (gate doesn't apply)
#   - Tier < 3 or no Tier field  -> allow
#   - Per-session marker present -> allow (already gated this session)
#   - Substantive waiver present -> allow + write per-session marker
#   - Otherwise                  -> BLOCK (via emit_block, same as the
#     other three rejection conditions in this file — ONE block-message
#     shape for the whole gate).
# ============================================================

# Discover active plans under docs/plans/*.md (top-level only).
_dag_discover_active_plans() {
  local plans_dir="${PLANS_DIR_OVERRIDE:-docs/plans}"
  [[ -d "$plans_dir" ]] || return 0
  local f
  for f in "$plans_dir"/*.md; do
    [[ -f "$f" ]] || continue
    if head -n 30 "$f" 2>/dev/null | grep -qiE '^[[:space:]]*\**[[:space:]]*Status[[:space:]]*:?\**[[:space:]]*ACTIVE'; then
      echo "$f"
    fi
  done
}

# Parse the Tier value from a plan's first 30 lines (defaults to 1).
_dag_parse_tier() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || { echo "1"; return; }
  local header
  header=$(head -n 30 "$plan_file" 2>/dev/null)
  [[ -z "$header" ]] && { echo "1"; return; }
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
_dag_plan_slug() {
  local plan_file="$1"
  local base
  base=$(basename "$plan_file" .md)
  printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Session marker path for a given plan slug.
_dag_session_marker_path() {
  local slug="$1"
  local state_dir="${STATE_DIR_OVERRIDE:-.claude/state}"
  local sid="${CLAUDE_SESSION_ID:-default}"
  sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
  [[ -z "$sid" ]] && sid="default"
  echo "${state_dir}/dag-checked-${sid}-${slug}.txt"
}

# Find a substantive (>=40 non-whitespace chars) waiver file for a slug.
_dag_find_substantive_waiver() {
  local slug="$1"
  local state_dir="${STATE_DIR_OVERRIDE:-.claude/state}"
  [[ -d "$state_dir" ]] || return 1
  local f content_chars
  for f in "$state_dir"/dag-approved-"$slug"-*.txt; do
    [[ -f "$f" ]] || continue
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
_dag_write_session_marker() {
  local slug="$1"
  local waiver_path="$2"
  local marker
  marker=$(_dag_session_marker_path "$slug")
  local marker_dir
  marker_dir=$(dirname "$marker")
  mkdir -p "$marker_dir" 2>/dev/null || return 1
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
  printf 'dag-approved at %s via waiver %s\n' "$ts" "$waiver_path" > "$marker" 2>/dev/null || return 1
  return 0
}

# Inspect a Task-tool dispatch for the DAG-waiver requirement. Calls the
# shared emit_block (exit 2) on failure; returns 0 (allow) otherwise.
_dag_inspect_dispatch() {
  local input="$1"

  local tool_name
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  if [[ "$tool_name" != "Task" ]]; then
    return 0
  fi

  local active_plans
  active_plans=$(_dag_discover_active_plans)
  if [[ -z "$active_plans" ]]; then
    return 0
  fi

  local plan_path tier slug marker waiver
  while IFS= read -r plan_path; do
    [[ -z "$plan_path" ]] && continue

    tier=$(_dag_parse_tier "$plan_path")
    if [[ "$tier" -lt 3 ]]; then
      continue
    fi

    slug=$(_dag_plan_slug "$plan_path")
    [[ -z "$slug" ]] && slug="unknown-plan"

    marker=$(_dag_session_marker_path "$slug")
    if [[ -f "$marker" ]]; then
      continue
    fi

    waiver=$(_dag_find_substantive_waiver "$slug" || true)
    if [[ -n "$waiver" ]]; then
      _dag_write_session_marker "$slug" "$waiver" || true
      continue
    fi

    emit_block "DAG review required before Tier $tier dispatch" "\
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
plus 02-roles.md Orchestrator role. (Folded from
dag-review-waiver-gate.sh at NL Overhaul Wave D.6 — same check,
now emitted through this file's shared block-message shape.)"
  done <<< "$active_plans"

  return 0
}

# ============================================================
# Inspect the tool input and apply the three rejection rules.
# ============================================================
inspect_spawn() {
  local input="$1"

  # Tool-name guard — skip if not Task/Agent.
  local tool_name
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  case "$tool_name" in
    Task|Agent) ;;
    *) return 0 ;;
  esac

  # ---------- Rejection (d): DAG-review waiver (folded, §D.6 item 2).
  # Runs BEFORE the Agent Teams config_file_exists early-return below —
  # this check is independent of Agent Teams configuration and applies
  # to any Task-tool dispatch (Tier 3+ active plan, no waiver on file).
  _dag_inspect_dispatch "$input"

  # Skip (allow) if config file is absent — Agent Teams not configured;
  # the feature flag is implicitly disabled, but a non-team Agent spawn
  # should still proceed normally.
  if ! config_file_exists; then
    return 0
  fi

  # Read config fields (defaults match Task 4 schema)
  local enabled force_in_process worktree_mandatory_for_write
  enabled=$(load_config_field "enabled" "false")
  force_in_process=$(load_config_field "force_in_process" "true")
  worktree_mandatory_for_write=$(load_config_field "worktree_mandatory_for_write" "true")

  # Parse tool_input fields
  local team_name isolation subagent_type
  team_name=$(printf '%s' "$input" | jq -r '.tool_input.team_name // ""' 2>/dev/null || echo "")
  isolation=$(printf '%s' "$input" | jq -r '.tool_input.isolation // ""' 2>/dev/null || echo "")
  subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || echo "")

  # ---------- Rejection (a): feature flag disabled while team_name set
  if [[ "$enabled" == "false" && -n "$team_name" ]]; then
    emit_block "Agent Teams is disabled" "\
Spawn requested with team_name=\"$team_name\" but Agent Teams is
disabled in the harness config.

Set \`enabled: true\` in:
  ~/.claude/local/agent-teams.config.json

Note: Agent Teams is an experimental Anthropic feature with known
upstream bugs. Read the enable instructions and bug list first:
  adapters/claude-code/rules/agent-teams.md (Task 11 lands this rule)

If you did NOT mean to spawn a teammate, drop the \`team_name\`
parameter from the Agent tool call."
  fi

  # ---------- Rejection (b): write-capable spawn missing worktree
  if [[ "$worktree_mandatory_for_write" == "true" && "$isolation" != "worktree" ]]; then
    if ! is_read_only_agent "$subagent_type"; then
      emit_block "Write-capable teammate spawn requires worktree isolation" "\
The spawned agent (subagent_type=\"${subagent_type:-<none>}\") is
treated as write-capable, and the harness config requires
\`isolation: \"worktree\"\` for write-capable spawns.

Add \`isolation: \"worktree\"\` to the Agent tool call. The harness
will create an isolated git worktree so concurrent file edits do
not race.

Read-only agents (research, explorer, task-verifier, code reviewers,
etc.) are exempt from this requirement — see the read-only allowlist
in this hook.

To relax this requirement project-wide, set
\`worktree_mandatory_for_write: false\` in:
  ~/.claude/local/agent-teams.config.json"
    fi
  fi

  # ---------- Rejection (c): force_in_process while permission bypass active
  if [[ "$force_in_process" == "true" ]]; then
    if lead_is_dangerously_skipping_permissions; then
      emit_block "Lead session has bypassPermissions while force_in_process is set" "\
The lead session is running with --dangerously-skip-permissions
(or bypassPermissions default mode), and the harness config forces
in-process teammates (\`force_in_process: true\`).

In-process teammates inherit the lead's permission mode, so an
unattended in-process teammate would also bypass all permission
prompts. This is unsafe by default.

Resolve in one of two ways:
  1. Disable force_in_process (allow pane-based teammates, which
     have their own permission state):
       set \`force_in_process: false\` in
       ~/.claude/local/agent-teams.config.json
  2. Do NOT bypass permissions in the lead session (re-launch
     without --dangerously-skip-permissions)."
    fi
  fi

  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local total=0 passed=0 failed_names=""

  # mktemp dir for per-scenario config files
  local scratch
  scratch=$(mktemp -d -t teammspn-XXXXXX) || { echo "mktemp FAIL"; exit 1; }
  trap 'rm -rf "$scratch"' EXIT

  # run_scenario <name> <expect-exit:0|2> <config-json|none> <tool-input-json> [env-overrides]
  run_scenario() {
    local name="$1"
    local expect="$2"
    local config_json="$3"
    local tool_input="$4"
    local env_overrides="${5:-}"
    total=$((total+1))

    local cfg_path="$scratch/cfg-$total.json"
    if [[ "$config_json" == "none" ]]; then
      rm -f "$cfg_path"
    else
      printf '%s' "$config_json" > "$cfg_path"
    fi

    # Run hook with overridden config path. Use 'env -i' style additions
    # via explicit assignment; preserve PATH/HOME.
    local exit_code
    set +e
    if [[ -n "$env_overrides" ]]; then
      # shellcheck disable=SC2086
      env AGENT_TEAMS_CONFIG_PATH="$cfg_path" \
        CLAUDE_TOOL_INPUT="$tool_input" \
        $env_overrides \
        bash "$SELF_PATH" >/dev/null 2>"$scratch/err-$total.log"
    else
      env AGENT_TEAMS_CONFIG_PATH="$cfg_path" \
        CLAUDE_TOOL_INPUT="$tool_input" \
        bash "$SELF_PATH" >/dev/null 2>"$scratch/err-$total.log"
    fi
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

  echo "teammate-spawn-validator self-test"
  echo "==================================="

  # S1 — non-Agent tool spawn (Edit) → allow (exit 0)
  run_scenario "S1. non-Agent tool (Edit) → ALLOW" \
    0 \
    '{"enabled":false}' \
    '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.md","content":"hi"}}'

  # S2 — config missing → allow (exit 0). Use real path to non-existent file.
  local nope="$scratch/does-not-exist.json"
  rm -f "$nope"
  total=$((total+1))
  set +e
  env AGENT_TEAMS_CONFIG_PATH="$nope" \
    CLAUDE_TOOL_INPUT='{"tool_name":"Agent","tool_input":{"team_name":"demo","subagent_type":"plan-phase-builder"}}' \
    bash "$SELF_PATH" >/dev/null 2>"$scratch/err-s2.log"
  local s2_exit=$?
  set -e
  if [[ "$s2_exit" == "0" ]]; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S2. config missing → ALLOW"
  else
    printf '  FAIL %-3d %s (expected exit=0, got exit=%s)\n' \
      "$total" "S2. config missing → ALLOW" "$s2_exit"
    failed_names="$failed_names\n  - S2"
  fi

  # S3 — enabled=false + team_name → reject (exit 2) with "Agent Teams is disabled"
  run_scenario "S3. enabled=false + team_name → BLOCK" \
    2 \
    '{"enabled":false,"force_in_process":true,"worktree_mandatory_for_write":true}' \
    '{"tool_name":"Agent","tool_input":{"team_name":"demo","subagent_type":"plan-phase-builder"}}'

  # S4 — write-capable without worktree → reject (exit 2)
  run_scenario "S4. write-capable spawn missing worktree → BLOCK" \
    2 \
    '{"enabled":true,"force_in_process":true,"worktree_mandatory_for_write":true}' \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"plan-phase-builder","team_name":"demo"}}'

  # S5 — read-only agent without worktree → allow (exit 0)
  run_scenario "S5. read-only agent without worktree → ALLOW" \
    0 \
    '{"enabled":true,"force_in_process":true,"worktree_mandatory_for_write":true}' \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"research","team_name":"demo"}}'

  # S6 — fully-specified spawn (enabled, worktree set, normal perms) → allow
  run_scenario "S6. fully-specified spawn (enabled+worktree+normal-perms) → ALLOW" \
    0 \
    '{"enabled":true,"force_in_process":true,"worktree_mandatory_for_write":true}' \
    '{"tool_name":"Agent","tool_input":{"team_name":"demo","subagent_type":"plan-phase-builder","isolation":"worktree"}}' \
    'CLAUDE_PERMISSION_MODE=default'

  # ---- D.4: customer-facing spawn-time WARN scenarios (non-blocking) ----
  # These exercise check_customer_facing_warn directly against a real
  # patterns file (the shipped patterns/customer-facing-patterns.txt), NOT
  # through run_scenario's Agent-Teams config harness — the warn is
  # independent of that config entirely.

  # S7 — customer-facing prompt → exit 0 (non-blocking) AND stderr carries
  # the NOTE. Uses a STRONG signal (docs/support) so it is unambiguous.
  # AGENT_TEAMS_CONFIG_PATH points at a non-existent file so inspect_spawn's
  # rejection rules no-op (config_file_exists → false → allow), isolating
  # the warn behavior under test from the machine's real (if any)
  # ~/.claude/local/agent-teams.config.json.
  total=$((total+1))
  set +e
  S7_ERR=$(env AGENT_TEAMS_CONFIG_PATH="$scratch/does-not-exist-s7.json" \
    CLAUDE_TOOL_INPUT='{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Build the contractor-facing navigation IA for the support page under src/app/(dashboard)/, docs/support included."}}' \
    bash "$SELF_PATH" 2>&1 >/dev/null)
  S7_EXIT=$?
  set -e
  if [[ "$S7_EXIT" == "0" ]] && printf '%s' "$S7_ERR" | grep -q "customer-facing"; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S7. customer-facing spawn → WARN (non-blocking, exit 0)"
  else
    printf '  FAIL %-3d %s (exit=%s)\n' "$total" "S7. customer-facing spawn → WARN (non-blocking, exit 0)" "$S7_EXIT"
    failed_names="$failed_names\n  - S7"
  fi

  # S8 — backend-only prompt (src/lib/ exclusion, no STRONG signal) → exit 0,
  # NO customer-facing NOTE on stderr. Same config-path isolation as S7.
  total=$((total+1))
  set +e
  S8_ERR=$(env AGENT_TEAMS_CONFIG_PATH="$scratch/does-not-exist-s8.json" \
    CLAUDE_TOOL_INPUT='{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Refactor the billing reconciliation logic in src/lib/billing.ts and src/trigger/sync.ts; add a supabase migration. Tests-only changes elsewhere."}}' \
    bash "$SELF_PATH" 2>&1 >/dev/null)
  S8_EXIT=$?
  set -e
  if [[ "$S8_EXIT" == "0" ]] && ! printf '%s' "$S8_ERR" | grep -q "customer-facing"; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S8. backend-only spawn → no customer-facing warn"
  else
    printf '  FAIL %-3d %s (exit=%s, err=%s)\n' "$total" "S8. backend-only spawn → no customer-facing warn" "$S8_EXIT" "$(printf '%s' "$S8_ERR" | head -3 | tr '\n' ' ')"
    failed_names="$failed_names\n  - S8"
  fi

  # S9 — customer-facing spawn that WOULD ALSO be blocked by a rejection
  # rule (write-capable, no worktree, Agent Teams enabled) → the warn fires
  # AND the block still fires (exit 2) — the warn must never mask or change
  # a blocking outcome (constraint: do not change any BLOCKING behavior).
  total=$((total+1))
  S9_CFG="$scratch/cfg-s9.json"
  printf '%s' '{"enabled":true,"force_in_process":true,"worktree_mandatory_for_write":true}' > "$S9_CFG"
  set +e
  S9_ERR=$(env AGENT_TEAMS_CONFIG_PATH="$S9_CFG" \
    CLAUDE_TOOL_INPUT='{"tool_name":"Agent","tool_input":{"team_name":"demo","subagent_type":"plan-phase-builder","prompt":"Build the contractor dashboard navigation under src/app/(dashboard)/"}}' \
    bash "$SELF_PATH" 2>&1 >/dev/null)
  S9_EXIT=$?
  set -e
  if [[ "$S9_EXIT" == "2" ]] && printf '%s' "$S9_ERR" | grep -q "customer-facing" \
     && printf '%s' "$S9_ERR" | grep -q "BLOCKED"; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S9. customer-facing + blockable spawn → warn fires AND block still fires"
  else
    printf '  FAIL %-3d %s (exit=%s)\n' "$total" "S9. customer-facing + blockable spawn → warn fires AND block still fires" "$S9_EXIT"
    failed_names="$failed_names\n  - S9"
  fi

  # S10 — non-Agent/Task tool (Edit) with a customer-facing-shaped path in
  # its input → the warn must NOT fire (tool-name guard); exit 0 as before.
  total=$((total+1))
  set +e
  S10_ERR=$(CLAUDE_TOOL_INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/app/(dashboard)/support/page.tsx","content":"hi"}}' \
    bash "$SELF_PATH" 2>&1 >/dev/null)
  S10_EXIT=$?
  set -e
  if [[ "$S10_EXIT" == "0" ]] && ! printf '%s' "$S10_ERR" | grep -q "customer-facing"; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S10. non-Agent/Task tool → warn does not fire"
  else
    printf '  FAIL %-3d %s (exit=%s)\n' "$total" "S10. non-Agent/Task tool → warn does not fire" "$S10_EXIT"
    failed_names="$failed_names\n  - S10"
  fi

  # ---- DAG-review waiver fold scenarios (§D.6 item 2) ----
  # Set up an isolated docs/plans + .claude/state pair per scenario via
  # PLANS_DIR_OVERRIDE / STATE_DIR_OVERRIDE (both env knobs the folded
  # _dag_* helpers honor, ported unchanged from dag-review-waiver-gate.sh).
  local dag_plans_dir="$scratch/dag-plans"
  local dag_state_dir="$scratch/dag-state"
  mkdir -p "$dag_plans_dir" "$dag_state_dir"

  # S7 — Tier 3 active plan, no waiver, no marker, tool_name=Task → BLOCK
  # (the folded dag-review-waiver-gate.sh check now firing through THIS
  # file's emit_block, independent of any Agent Teams config).
  rm -f "$dag_plans_dir"/*.md
  cat > "$dag_plans_dir/tier3-demo.md" <<'PLANEOF'
# Plan: Tier 3 demo
Status: ACTIVE
Tier: 3
Mode: design

## Goal
Substantial plan needing DAG review.
PLANEOF
  total=$((total+1))
  set +e
  actual_exit=$(
    env PLANS_DIR_OVERRIDE="$dag_plans_dir" \
      STATE_DIR_OVERRIDE="$dag_state_dir" \
      AGENT_TEAMS_CONFIG_PATH="$scratch/does-not-exist-s7.json" \
      CLAUDE_TOOL_INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","prompt":"build something"}}' \
      CLAUDE_SESSION_ID="dag-fold-s7" \
      bash "$SELF_PATH" >/dev/null 2>"$scratch/err-s7.log"
    echo $?
  )
  set -e
  if [[ "$actual_exit" == "2" ]] && grep -q "DAG review required" "$scratch/err-s7.log"; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S7. DAG-fold: Tier 3 plan, no waiver, tool=Task → BLOCK"
  else
    printf '  FAIL %-3d %s (expected exit=2 + DAG message, got exit=%s)\n' \
      "$total" "S7. DAG-fold: Tier 3 plan, no waiver, tool=Task → BLOCK" "$actual_exit"
    printf '       stderr: %s\n' "$(head -3 "$scratch/err-s7.log" | tr '\n' ' ')"
    failed_names="$failed_names\n  - S7"
  fi

  # S8 — same Tier 3 plan, WITH a substantive waiver on file → ALLOW
  rm -rf "$dag_state_dir"; mkdir -p "$dag_state_dir"
  printf 'DAG reviewed with user 2026-07-02; tasks confirmed parallel-safe; approved for dispatch.' \
    > "$dag_state_dir/dag-approved-tier3-demo-20260702000000.txt"
  total=$((total+1))
  set +e
  actual_exit=$(
    env PLANS_DIR_OVERRIDE="$dag_plans_dir" \
      STATE_DIR_OVERRIDE="$dag_state_dir" \
      AGENT_TEAMS_CONFIG_PATH="$scratch/does-not-exist-s8.json" \
      CLAUDE_TOOL_INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","prompt":"build something"}}' \
      CLAUDE_SESSION_ID="dag-fold-s8" \
      bash "$SELF_PATH" >/dev/null 2>"$scratch/err-s8.log"
    echo $?
  )
  set -e
  if [[ "$actual_exit" == "0" ]]; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S8. DAG-fold: Tier 3 plan + substantive waiver → ALLOW"
  else
    printf '  FAIL %-3d %s (expected exit=0, got exit=%s)\n' \
      "$total" "S8. DAG-fold: Tier 3 plan + substantive waiver → ALLOW" "$actual_exit"
    failed_names="$failed_names\n  - S8"
  fi

  # S9 — Tier 1 plan (below the Tier-3 gate threshold) → ALLOW, sanity
  # that the fold didn't change the tier cutoff.
  rm -f "$dag_plans_dir"/*.md
  rm -rf "$dag_state_dir"; mkdir -p "$dag_state_dir"
  cat > "$dag_plans_dir/tier1-demo.md" <<'PLANEOF'
# Plan: Tier 1 demo
Status: ACTIVE
Tier: 1

## Goal
Trivial plan.
PLANEOF
  total=$((total+1))
  set +e
  actual_exit=$(
    env PLANS_DIR_OVERRIDE="$dag_plans_dir" \
      STATE_DIR_OVERRIDE="$dag_state_dir" \
      AGENT_TEAMS_CONFIG_PATH="$scratch/does-not-exist-s9.json" \
      CLAUDE_TOOL_INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","prompt":"build something"}}' \
      CLAUDE_SESSION_ID="dag-fold-s9" \
      bash "$SELF_PATH" >/dev/null 2>"$scratch/err-s9.log"
    echo $?
  )
  set -e
  if [[ "$actual_exit" == "0" ]]; then
    passed=$((passed+1))
    printf '  ok   %-3d %s\n' "$total" "S9. DAG-fold: Tier 1 plan → ALLOW (below gate threshold)"
  else
    printf '  FAIL %-3d %s (expected exit=0, got exit=%s)\n' \
      "$total" "S9. DAG-fold: Tier 1 plan → ALLOW (below gate threshold)" "$actual_exit"
    failed_names="$failed_names\n  - S9"
  fi

  echo "==================================="
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

# Non-blocking customer-facing warn (D.4) — runs independently of
# inspect_spawn's Agent-Teams-config-gated rejection rules; always exits 0.
check_customer_facing_warn "$INPUT"

inspect_spawn "$INPUT"
exit 0
