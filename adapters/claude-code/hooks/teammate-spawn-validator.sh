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
# Three rejection conditions:
#   (a) enabled=false AND tool input has team_name set
#       → Agent Teams disabled; tell user how to enable.
#   (b) worktree_mandatory_for_write=true AND spawn lacks
#       isolation="worktree" AND spawned agent is write-capable.
#       → Filesystem-race risk; require worktree isolation.
#   (c) force_in_process=true AND lead session is in
#       --dangerously-skip-permissions mode.
#       → Permission bypass propagates to teammates; require explicit
#         opt-out of force_in_process.
#
# Defaults to ALLOW when ambiguous. Better to let a teammate spawn
# than silently block legitimate work due to a hook bug.
#
# Self-test: bash teammate-spawn-validator.sh --self-test
# Expected: 6/6 PASS, exit 0.
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

inspect_spawn "$INPUT"
exit 0
