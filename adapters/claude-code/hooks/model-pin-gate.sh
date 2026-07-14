#!/bin/bash
# model-pin-gate.sh — PreToolUse (Task|Agent): BLOCK a subagent spawn that would
# SILENTLY INHERIT the main-loop model.
#
# WHY: operator directive 2026-07-14 — every subagent must be EXPLICITLY assigned a
# model at initiation. An omitted model does NOT mean "let NL choose"; it means
# "inherit the caller's model." On a Fable main-loop that silently ran ~1.7M tokens of
# un-pinned subagents on the premium Fable tier and drained the budget. This gate makes
# the silent-inherit path impossible on the ONE spawn surface a PreToolUse hook can
# inspect (the Task/Agent tool). Honest residual (NOT gate-able — see
# doctrine/model-selection.md): Workflow-inline agent() model:, spawn_task, cron/remote.
#
# ALLOW when: the spawn passes an explicit `model`, OR the target agent definition
#   agents/<subagent_type>.md carries a `model:` frontmatter (pinned per model-policy.json).
# BLOCK (exit 2) when: no explicit model AND the agent type is unpinned/unknown.
# FAIL-OPEN (exit 0) ONLY on internal limitation (no jq / empty-or-malformed input) —
#   NEVER on a genuine missing-model, which is precisely the thing to block.
set -uo pipefail

run_gate() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  [ -z "$input" ] && input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && return 0                       # nothing to inspect → fail-open
  command -v jq >/dev/null 2>&1 || return 0         # no jq → fail-open (internal)

  local tool atype model
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  case "$tool" in Task|Agent) ;; *) return 0 ;; esac  # only these spawn surfaces

  atype="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // .tool_input.agentType // ""' 2>/dev/null || true)"
  model="$(printf '%s' "$input" | jq -r '.tool_input.model // ""' 2>/dev/null || true)"

  # Explicit model on the spawn → the goal; allow.
  if [ -n "$model" ] && [ "$model" != "null" ]; then return 0; fi

  # No explicit model → the agent definition MUST pin one.
  local agents_dir def
  agents_dir="${MODEL_PIN_AGENTS_DIR:-$HOME/.claude/agents}"
  [ -d "$agents_dir" ] || agents_dir="$(dirname "$0")/../agents"
  def="$agents_dir/$atype.md"
  if [ -n "$atype" ] && [ -f "$def" ] && grep -qE '^model:' "$def" 2>/dev/null; then
    return 0                                         # frontmatter pins it → allow
  fi

  # Silent-inherit path → BLOCK.
  {
    echo "================================================================"
    echo "MODEL-PIN GATE — SUBAGENT SPAWN BLOCKED"
    echo "================================================================"
    echo "This ${tool} spawn passes NO explicit model and its agent type is not pinned,"
    echo "so it would SILENTLY INHERIT the main-loop model. Operator directive 2026-07-14:"
    echo "silent model-inherit is forbidden (it ran ~1.7M tokens on premium Fable by accident)."
    echo ""
    echo "  subagent_type: ${atype:-<none>}"
    echo ""
    echo "Fix ONE of:"
    echo "  1. Pass an explicit model on the spawn (model: fable|opus|sonnet|haiku) per"
    echo "     config/model-policy.json — chain[0] for this agent's category."
    echo "  2. Pin the agent: add a 'model:' frontmatter line to agents/${atype:-<type>}.md."
    echo ""
    echo "Policy: adapters/claude-code/config/model-policy.json  ·  doctrine/model-selection.md"
  } >&2
  return 2
}

run_self_test() {
  local pass=0 fail=0
  local fix; fix="$(mktemp -d 2>/dev/null)" || { echo "mktemp FAIL"; exit 1; }
  mkdir -p "$fix/agents"
  printf -- '---\nname: pinned-agent\nmodel: fable\n---\nbody\n' > "$fix/agents/pinned-agent.md"
  printf -- '---\nname: unpinned-agent\ntools: Read\n---\nbody\n' > "$fix/agents/unpinned-agent.md"

  _rc() { # <expected-rc> <name> <json>
    local exp="$1" name="$2" json="$3" got
    CLAUDE_TOOL_INPUT="$json" MODEL_PIN_AGENTS_DIR="$fix/agents" bash "$SELF" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$exp" ]; then echo "  ok   $name (rc=$got)"; pass=$((pass+1))
    else echo "  FAIL $name (rc=$got, expected $exp)"; fail=$((fail+1)); fi
  }

  _rc 0 "explicit model → allow"            '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent","model":"sonnet"}}'
  _rc 0 "empty model + pinned agent → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent"}}'
  _rc 2 "empty model + unpinned agent → BLOCK" '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent"}}'
  _rc 2 "empty model + unknown type → BLOCK" '{"tool_name":"Agent","tool_input":{"subagent_type":"does-not-exist"}}'
  _rc 2 "empty model + no type → BLOCK"      '{"tool_name":"Task","tool_input":{"prompt":"x"}}'
  _rc 0 "non-spawn tool (Bash) → allow"      '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  _rc 0 "malformed json → fail-open allow"   'this is not json'
  _rc 0 "empty input → fail-open allow"      ''
  _rc 0 "explicit model null-string treated empty but pinned → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent","model":null}}'

  rm -rf "$fix" 2>/dev/null
  echo ""
  echo "model-pin-gate self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

SELF="$0"
if [ "${1:-}" = "--self-test" ]; then run_self_test; exit $?; fi
run_gate
exit $?
