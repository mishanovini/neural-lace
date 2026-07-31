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
# Echo the frontmatter `model:` VALUE (empty if none). Same fence-scoped,
# CRLF-safe walk as _frontmatter_pins_model — a body line starting `model:`
# must not count. Added 2026-07-29 for the exhausted-tier reroute, which needs
# to know WHICH tier is pinned, not merely that one is.
_mpg_frontmatter_model() {
  local f="$1" in_fm=0 line v
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in
        model:*)
          v="${line#model:}"
          v="${v#"${v%%[![:space:]]*}"}"       # ltrim
          v="${v%"${v##*[![:space:]]}"}"       # rtrim
          printf '%s' "$v"; return 0 ;;
      esac
    fi
  done < "$f"
  return 0
}

# Return 0 (true) iff <tier> is currently marked exhausted by
# model-availability.sh. On a 0 return, sets _MPG_FB (fallback tier, may be
# empty) and _MPG_REASON (stated reason, may be empty) for the caller's
# message. Shared by BOTH exhaustion-check call sites (frontmatter-pinned
# agent AND explicit `model:` on the spawn) so there is one parser for "is
# this tier exhausted," not two that can drift.
_mpg_tier_exhausted() {
  local tier="$1"
  _MPG_FB=""; _MPG_REASON=""
  [ -n "$tier" ] || return 1
  local ma; ma="$(dirname "$0")/../scripts/model-availability.sh"
  [ -f "$ma" ] || ma="$HOME/.claude/scripts/model-availability.sh"
  [ -f "$ma" ] || return 1
  bash "$ma" is-exhausted "$tier" 2>/dev/null || return 1
  _MPG_FB="$(bash "$ma" fallback-for "$tier" 2>/dev/null)"
  _MPG_REASON="$(bash "$ma" reason "$tier" 2>/dev/null)"
  return 0
}

# Print the reroute-required block to stderr. <tier> is the exhausted tier;
# <source> is a one-clause description of WHERE it came from (frontmatter pin
# vs explicit model:) that reads naturally as "<source>, but '<tier>' is
# currently marked UNAVAILABLE...". Relies on _MPG_FB/_MPG_REASON already set
# by _mpg_tier_exhausted.
_mpg_print_exhausted_block() {
  local tier="$1" source="$2"
  {
    echo "================================================================"
    echo "MODEL-PIN GATE — PINNED TIER IS EXHAUSTED, REROUTE REQUIRED"
    echo "================================================================"
    echo "${source}, but '${tier}' is currently"
    echo "marked UNAVAILABLE on this machine (reason: ${_MPG_REASON:-unspecified})."
    echo ""
    echo "Dispatching anyway does not fail safely — it dies at the API with a"
    echo "spend-limit error, and a verifier that dies on arrival is a"
    echo "verification that silently did not happen (2026-07-28: this is how"
    echo "commit f6562b2 reached master with no harness-reviewer)."
    echo ""
    if [ -n "$_MPG_FB" ]; then
      echo "FIX: re-dispatch this agent with an explicit model:"
      echo "     model: ${_MPG_FB}"
      echo "     (chain[1] for this agent in config/model-policy.json — the"
      echo "      fallback the policy already documents.)"
    else
      echo "FIX: re-dispatch with an explicit model that is available."
    fi
    echo ""
    echo "If '${tier}' is available again:"
    echo "     bash ~/.claude/scripts/model-availability.sh clear ${tier}"
    echo "================================================================"
  } >&2
}

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

  # Explicit model on the spawn → the goal, UNLESS that tier is itself
  # exhausted (2026-07-29 extension — probe T4 proved `model: fable` while
  # fable is exhausted passed rc=0 here and would die at the API: the same
  # f6562b2 silent-verifier-death class the frontmatter-pin reroute below
  # exists to prevent, just reached via the explicit-model path instead of
  # the frontmatter path. One exhaustion check now covers both surfaces).
  if [ -n "$model" ] && [ "$model" != "null" ]; then
    if _mpg_tier_exhausted "$model"; then
      _mpg_print_exhausted_block "$model" "This ${tool} spawn passes explicit model: ${model}"
      return 2
    fi
    return 0
  fi

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
    # ---- EXHAUSTED-TIER REROUTE (operator directive 2026-07-29) --------------
    # "Fable is supposed to always fail back to Opus. That's supposed to be built
    # in. If it's not, then fix it."
    #
    # config/model-policy.json declares ["fable","opus"] chains and its own note
    # concedes the fallback is "a documented preference" — nothing applied it. On
    # 2026-07-28 Fable was budget-exhausted and BOTH verifier dispatches died on
    # arrival with a spend-limit error. A dead verifier is a SKIPPED
    # verification, which is how f6562b2 reached master unreviewed.
    #
    # A PreToolUse hook cannot rewrite tool input and cannot retry an API error,
    # so it cannot perform the fallback itself. What it CAN do is refuse to let
    # the dispatch die silently: if the pinned tier is currently marked
    # exhausted, BLOCK here and name the exact override. Loud reroute beats
    # silent non-verification.
    local pinned_tier
    pinned_tier="$(_mpg_frontmatter_model "$def")"
    if [ -n "$pinned_tier" ] && _mpg_tier_exhausted "$pinned_tier"; then
      _mpg_print_exhausted_block "$pinned_tier" "agents/${atype}.md pins model: ${pinned_tier}"
      return 2
    fi
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
    echo "This gate: ~/.claude/hooks/model-pin-gate.sh (source: adapters/claude-code/hooks/model-pin-gate.sh)"
  } >&2
  return 2
}

run_self_test() {
  local pass=0 fail=0
  local fix; fix="$(mktemp -d 2>/dev/null)" || { echo "mktemp FAIL"; exit 1; }
  mkdir -p "$fix/agents"
  # SANDBOX EVERY STATE DIR THIS HOOK'S TRANSITIVE CALLEES READ.
  # The exhausted-tier reroute splice shells out to model-availability.sh, which
  # reads ~/.claude/state/model-availability. Without this export the suite
  # inherits the OPERATOR'S LIVE MARKERS and goes RED (10/13 observed) purely
  # because a tier happens to be marked exhausted — a test whose outcome depends
  # on live machine state, which is the same self-invalidating class this repo
  # has now hit four times in two days. A hook that shells out to another harness
  # script inherits that script's entire state surface and must pin it.
  export MODEL_AVAIL_STATE_DIR="$fix/model-availability"
  mkdir -p "$MODEL_AVAIL_STATE_DIR"
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

  # <expected-rc> <name> <json> <stderr-must-contain> — like _rc, but also
  # asserts the block message actually names the substring given (guards
  # against an rc-only assertion staying green while the reroute message
  # regresses to generic text — the same false-green shape this fix closes).
  _rc_msg() {
    local exp="$1" name="$2" json="$3" needle="$4" out got
    out="$(CLAUDE_TOOL_INPUT="$json" MODEL_PIN_AGENTS_DIR="$fix/agents" bash "$SELF" 2>&1 1>/dev/null)"
    got=$?
    if [ "$got" -eq "$exp" ] && printf '%s' "$out" | grep -q -- "$needle"; then
      echo "  ok   $name (rc=$got, message names '$needle')"; pass=$((pass+1))
    else
      echo "  FAIL $name (rc=$got expected $exp; message contains '$needle'? $(printf '%s' "$out" | grep -q -- "$needle" && echo yes || echo no))"
      fail=$((fail+1))
    fi
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

  # --- Exhausted-tier reroute (2026-07-29) — was previously UNTESTED: the
  # suite stayed 13/13 with this whole block deleted (false-green class).
  # Reuses the MODEL_AVAIL_STATE_DIR sandbox exported above; run LAST so
  # marking fable exhausted here can't affect the fixed-model scenarios above.
  local ma_path; ma_path="$(dirname "$SELF")/../scripts/model-availability.sh"

  bash "$ma_path" mark-exhausted fable --reason "self-test probe" --hours 1 >/dev/null 2>&1
  _rc_msg 2 "pinned agent + tier exhausted → BLOCK naming fallback" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent"}}' "model: opus"
  bash "$ma_path" clear fable >/dev/null 2>&1
  _rc 0 "pinned agent + tier cleared → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent"}}'

  # Same exhaustion check, extended to the EXPLICIT model: dispatch path
  # (probe T4: `model: fable` while fable is exhausted used to pass rc=0 and
  # die at the API — the f6562b2 silent-verifier-death class).
  bash "$ma_path" mark-exhausted fable --reason "self-test probe" --hours 1 >/dev/null 2>&1
  _rc_msg 2 "explicit model:fable + fable exhausted → BLOCK naming fallback" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent","model":"fable"}}' "model: opus"
  bash "$ma_path" clear fable >/dev/null 2>&1
  _rc 0 "explicit model:fable + fable cleared → allow" '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent","model":"fable"}}'

  rm -rf "$fix" 2>/dev/null
  echo ""
  echo "model-pin-gate self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

SELF="$0"
if [ "${1:-}" = "--self-test" ]; then run_self_test; exit $?; fi
run_gate
exit $?
