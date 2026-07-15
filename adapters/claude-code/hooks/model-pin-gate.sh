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

# --- helpers: CRLF-safe, frontmatter-fence-scoped agent-def resolution -------
# All three read ONLY the first YAML frontmatter block (first ---…--- fence),
# strip trailing \r (Windows), and never use grep/sed/awk for fence detection
# (MSYS silently mangles \r — see doctrine). A body line starting `model:` or
# `name:` therefore does NOT count.

# Print the frontmatter `name:` value (empty if none).
_frontmatter_name() {
  local f="$1" in_fm=0 line
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in name:*) printf '%s' "${line#name:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; return 0 ;; esac
    fi
  done < "$f"
  return 0
}

# Return 0 iff the frontmatter carries a `model:` line.
_frontmatter_pins_model() {
  local f="$1" in_fm=0 line
  [ -f "$f" ] || return 1
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in model:*) return 0 ;; esac
    fi
  done < "$f"
  return 1
}

# Echo the agent-definition path for a subagent_type: filename slug FIRST, then
# by display `name:` frontmatter (M1 — subagent_type may be the DISPLAY name,
# e.g. "Domain Expert Tester", while the file is the slug). Empty if unresolved.
_resolve_agent_def() {
  local atype="$1" dir="$2" f name atype_lc
  [ -n "$atype" ] || return 0
  [ -d "$dir" ] || return 0
  if [ -f "$dir/$atype.md" ]; then printf '%s' "$dir/$atype.md"; return 0; fi
  atype_lc="$(printf '%s' "$atype" | tr '[:upper:]' '[:lower:]')"
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    name="$(_frontmatter_name "$f")"
    [ -n "$name" ] || continue
    if [ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" = "$atype_lc" ]; then
      printf '%s' "$f"; return 0
    fi
  done
  return 0
}

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

  # 'fork' ALWAYS inherits the parent model by design and cannot be pinned or
  # model-overridden (the Agent tool ignores `model` for fork). Blocking it
  # would be an un-remediable false-positive → exempt.
  local atype_lc; atype_lc="$(printf '%s' "$atype" | tr '[:upper:]' '[:lower:]')"
  [ "$atype_lc" = "fork" ] && return 0

  # No explicit model → the agent definition MUST pin one. Resolve by filename
  # slug first, then by display name: frontmatter (M1); accept only a model
  # pinned INSIDE the frontmatter fence (not a body line).
  local agents_dir def
  agents_dir="${MODEL_PIN_AGENTS_DIR:-$HOME/.claude/agents}"
  [ -d "$agents_dir" ] || agents_dir="$(dirname "$0")/../agents"
  def="$(_resolve_agent_def "$atype" "$agents_dir")"
  if [ -n "$def" ] && _frontmatter_pins_model "$def"; then
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
  # M1: display name differs from filename slug (real FP surface).
  printf -- '---\nname: Display Agent\nmodel: fable\n---\nbody\n' > "$fix/agents/display-agent.md"
  # M1 negative: a display name that RESOLVES but is UNPINNED must still BLOCK
  # (guards the name-resolution branch against a permissive regression).
  printf -- '---\nname: Unpinned Display\ntools: Read\n---\nbody\n' > "$fix/agents/unpinned-display.md"
  # Fence-scoping: a body line starting `model:` must NOT count as pinned.
  printf -- '---\nname: body-model-agent\ntools: Read\n---\nmodel: not-in-frontmatter\n' > "$fix/agents/body-model-agent.md"

  _rc() { # <expected-rc> <name> <json>
    local exp="$1" name="$2" json="$3" got
    CLAUDE_TOOL_INPUT="$json" MODEL_PIN_AGENTS_DIR="$fix/agents" bash "$SELF" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$exp" ]; then echo "  ok   $name (rc=$got)"; pass=$((pass+1))
    else echo "  FAIL $name (rc=$got, expected $exp)"; fail=$((fail+1)); fi
  }

  _rc 0 "explicit model → allow"            '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent","model":"sonnet"}}'
  _rc 0 "empty model + pinned agent → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent"}}'
  _rc 0 "display-name subagent_type resolves via name: → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"Display Agent"}}'
  _rc 2 "display-name resolves to UNPINNED agent → BLOCK" '{"tool_name":"Agent","tool_input":{"subagent_type":"Unpinned Display"}}'
  _rc 0 "fork subagent_type → exempt (inherits parent by design)" '{"tool_name":"Agent","tool_input":{"subagent_type":"fork"}}'
  _rc 2 "body model: line is NOT frontmatter → BLOCK" '{"tool_name":"Agent","tool_input":{"subagent_type":"body-model-agent"}}'
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
