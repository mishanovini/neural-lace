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
# currently marked UNAVAILABLE...". <atype> (optional, third arg) is the
# subagent_type in scope at the call site — used ONLY to ask the resolver
# whether the FULL declared chain (not just this one hop) still has
# something available. Relies on _MPG_FB/_MPG_REASON already set by
# _mpg_tier_exhausted.
_mpg_print_exhausted_block() {
  local tier="$1" source="$2" atype="${3:-}"
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
      # fallback-for only matches when <tier> IS chain[0] of some category,
      # so an empty _MPG_FB does not necessarily mean the WHOLE chain is
      # exhausted — try the full resolver (walks every hop) before
      # concluding that. 2026-08-06 remediation: the prior text here
      # ("re-dispatch with an explicit model that is available") named NO
      # model at all when this branch fired, which is exactly the case
      # (whole chain exhausted, or a 1-element chain like build's [sonnet])
      # where the operator most needs a concrete next step.
      local ma resolve_out resolve_rc rmodel
      ma="$(dirname "$0")/../scripts/model-availability.sh"
      [ -f "$ma" ] || ma="$HOME/.claude/scripts/model-availability.sh"
      resolve_out=""; resolve_rc=1
      if [ -n "$atype" ] && [ -f "$ma" ]; then
        resolve_out="$(bash "$ma" resolve --agent "$atype" 2>&1)"; resolve_rc=$?
      fi
      if [ "$resolve_rc" -eq 0 ]; then
        rmodel="$(printf '%s\n' "$resolve_out" | grep '^RESOLVED_MODEL=' | head -1 | cut -d= -f2-)"
        echo "FIX: re-dispatch this agent with an explicit model:"
        echo "     model: ${rmodel}"
        echo "     (resolved from config/model-policy.json's full chain for '${atype}'.)"
      else
        echo "FIX: the entire declared chain for this agent is currently marked"
        echo "     exhausted — the chain walked and why:"
        if [ -n "$resolve_out" ]; then
          printf '%s\n' "$resolve_out" | sed 's/^/     /'
        else
          echo "     (chain unresolvable — no '${atype:-<agent>}' entry in config/model-policy.json)"
        fi
        echo ""
        echo "     Options, in order:"
        echo "     1. If a tier is available again, clear its marker (always available):"
        echo "        bash ~/.claude/scripts/model-availability.sh clear <tier>"
        echo "     2. Or re-dispatch once you know a specific model is available."
      fi
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
      _mpg_print_exhausted_block "$model" "This ${tool} spawn passes explicit model: ${model}" "$atype"
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
      _mpg_print_exhausted_block "$pinned_tier" "agents/${atype}.md pins model: ${pinned_tier}" "$atype"
      return 2
    fi
    return 0                                         # frontmatter pins it → allow
  fi

  # Silent-inherit path → BLOCK. Try to name the ONE model to pass (operator
  # directive 2026-08-05: "the fix should be one obvious line, not a
  # research task") by resolving this atype's declared chain via
  # model-availability.sh resolve — the SAME resolver the reroute block
  # above and dispatch-directives.sh now use, so there is one place that
  # walks a chain, not three. Falls back to the generic fable|opus|sonnet|
  # haiku text when atype is unresolvable (unknown/typo'd type, or a type
  # with no chain declared at all) — resolution failing is exactly the
  # "unknown/empty chain → loud failure, never a silent default" case, so
  # the generic text (not a guessed model) is the correct degraded form.
  local fix1_line="  1. Pass an explicit model on the spawn (model: fable|opus|sonnet|haiku) per"
  local fix1_line2="     config/model-policy.json — chain[0] for this agent's category."
  if [ -n "$atype" ]; then
    local ma resolve_out resolve_rc rmodel
    ma="$(dirname "$0")/../scripts/model-availability.sh"
    [ -f "$ma" ] || ma="$HOME/.claude/scripts/model-availability.sh"
    if [ -f "$ma" ]; then
      resolve_out="$(bash "$ma" resolve --agent "$atype" 2>/dev/null)"
      resolve_rc=$?
      if [ "$resolve_rc" -eq 0 ]; then
        rmodel="$(printf '%s\n' "$resolve_out" | grep '^RESOLVED_MODEL=' | head -1 | cut -d= -f2-)"
        if [ -n "$rmodel" ]; then
          fix1_line="  1. Pass an explicit model on the spawn: model: ${rmodel}"
          fix1_line2="     (resolved from config/model-policy.json's chain for '${atype}')."
        fi
      fi
    fi
  fi
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
    echo "$fix1_line"
    echo "$fix1_line2"
    echo "  2. Pin the agent: add a 'model:' frontmatter line to agents/${atype:-<type>}.md."
    echo ""
    echo "Policy: adapters/claude-code/config/model-policy.json  ·  doctrine/model-selection.md"
    echo "This gate: ~/.claude/hooks/model-pin-gate.sh (source: adapters/claude-code/hooks/model-pin-gate.sh)"
  } >&2
  return 2
}

# ============================================================================
# --observe (PostToolUse Task|Agent) — OBSERVE, DON'T ASSUME.
#
# Operator directive 2026-08-05 (docs/backlog.md MODEL-LIMIT-INFERENCE-BAN-
# 2026-08-05): "I'm sick and tired of Claude making assumptions about what
# the limits are and making decisions based on those assumptions." There is
# no machine-readable limits source, so exhaustion state must come from a
# REAL failure string, never an inference from "an agent died" or "this
# feels slow."
#
# This runs AFTER a Task/Agent dispatch completes (PostToolUse, not the
# run_gate() PreToolUse path above). If the dispatch's tool_response carries
# the VERBATIM spend-limit error, this records which TIER ACTUALLY RAN
# (explicit model: on the spawn, else the resolved agent's own frontmatter
# pin — reusing _resolve_agent_def/_mpg_frontmatter_model already defined
# above, no second parser) as exhausted via model-availability.sh
# mark-exhausted. That is the SAME state file the PreToolUse reroute above,
# the silent-inherit fix1_line resolution above, and dispatch-directives.sh's
# resolve call all read — one write path, three read paths.
#
# Never blocks (always rc 0): the dispatch already finished: this hook only
# RECORDS what happened. If the tier can't be identified, or the response
# doesn't contain the verbatim error string, it records NOTHING — a miss is
# cheap (the next reroute-block or --observe hit still catches it), a false
# mark is not (it would silently steer every subsequent dispatch off a tier
# that was never actually exhausted).
#
# ----------------------------------------------------------------------------
# 2026-08-06 REMEDIATION (harness-change-review; both Critical, both PROVEN
# by replaying this session's own real transcripts against the v1 splice):
#
# C1 — UNANCHORED MATCH marked HEALTHY tiers exhausted. v1 grepped
# _MPG_EXHAUSTION_PATTERN unanchored against the ENTIRE tool_response, so the
# phrase appearing in a *prompt echo* (an Agent launch-ack is an OBJECT
# carrying the echoed `prompt`) or an agent's own foreground *report* text
# fired it exactly like a real death. Replaying the real toolUseResult of a
# SUCCESSFUL opus dispatch (whose launch-ack object's `.prompt` happened to
# quote this very bug's description) marked opus exhausted; replaying a
# builder dispatch marked sonnet — and categories.build.chain is [sonnet]
# only, a total builder lockout. Evidence (90-transcript corpus): all 13 TRUE
# deaths are STRING results BEGINNING "Error: Agent terminated early due to
# an API error:"; both FALSE positives were launch-ack OBJECTS carrying a
# `prompt` key. Fix below implements BOTH discriminators (either alone kills
# both FPs while keeping all 13 TPs):
#   1. ignore tool_response ENTIRELY (never even stringify it) when it is an
#      object carrying a `prompt` key — that shape is a launch-ack, never a
#      terminal death.
#   2. require the response to BEGIN WITH the literal death-signature prefix
#      "Error: Agent terminated early due to an API error" before the
#      exhaustion phrase is even searched for.
#
# C2 — SELF-REFERENTIAL TRIGGER INJECTION. v1's `--reason "observed:
# ${matched}"` stored the VERBATIM matched trigger text; model-availability.sh
# resolve echoes it in RESOLVED_REASON; dispatch-directives.sh printed that
# straight into the NEXT dispatch's prompt — so a TRUE positive on one tier
# could seed a FALSE positive on the next tier one dispatch later. Fix: never
# persist or re-emit the matched text — mark-exhausted below is given a FIXED
# token (tier + UTC timestamp only), and dispatch-directives.sh (separately
# fixed) now prints only the resolved tier + a closed-vocabulary cause code,
# never the raw stored reason string, so even an unrelated future reason
# value with unexpected content can never leak into a dispatch prompt.
# ----------------------------------------------------------------------------
_MPG_EXHAUSTION_PATTERN='hit your monthly spend limit'
_MPG_DEATH_PREFIX='Error: Agent terminated early due to an API error'

# Best-effort: does <text> name one of the known tiers? Real spend-limit
# error text names the model that died (e.g. "...spend limit for Fable
# 5..."), so a plain case-insensitive substring search is enough to recover
# it — this is intentionally the SAME closed tier vocabulary _ma_tier_ok
# already enforces, not a free-text guess. Echoes the first match, empty if
# none.
_mpg_parse_model_from_text() {
  local text_lc t
  text_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  for t in fable opus sonnet haiku mythos; do
    case "$text_lc" in *"$t"*) printf '%s' "$t"; return 0 ;; esac
  done
  return 0
}

run_observe() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  [ -z "$input" ] && input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local tool
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  case "$tool" in Task|Agent) ;; *) return 0 ;; esac

  local atype atype_lc
  atype="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // .tool_input.agentType // ""' 2>/dev/null || true)"
  # 'fork' always inherits the parent model and can never be pinned or
  # model-overridden -- mirrors run_gate's identical exemption (line ~223)
  # so a death on a fork spawn is never mis-attributed to whatever tier the
  # PARENT happened to be running on.
  atype_lc="$(printf '%s' "$atype" | tr '[:upper:]' '[:lower:]')"
  [ "$atype_lc" = "fork" ] && return 0

  # DISCRIMINATOR 2 (object-with-prompt-key, C1 fix): a launch-ack for an
  # in-flight or successfully-launched dispatch is an OBJECT carrying a
  # `prompt` key (the echoed dispatch prompt) -- never the terminal STRING a
  # real API-error death produces. Check the RAW type BEFORE ever
  # stringifying tool_response, so the echoed prompt's own text (which may
  # quote the exhaustion phrase verbatim, as this remediation's own dispatch
  # prompt does) is never substring-matched at all.
  local rtype
  rtype="$(printf '%s' "$input" | jq -r '(.tool_response // "") | type' 2>/dev/null || true)"
  if [ "$rtype" = "object" ]; then
    local has_prompt
    has_prompt="$(printf '%s' "$input" | jq -r '(.tool_response | has("prompt"))' 2>/dev/null || true)"
    [ "$has_prompt" = "true" ] && return 0
  fi

  local response
  response="$(printf '%s' "$input" | jq -r '(.tool_response // "") | if type=="string" then . else tostring end' 2>/dev/null || true)"
  [ -z "$response" ] && return 0

  # DISCRIMINATOR 1 (anchored prefix, C1 fix): a real death's tool_response
  # is a STRING that BEGINS WITH the literal error signature -- never a
  # foreground agent's own REPORT text or an echoed prompt that happens to
  # mention the phrase in prose. Both discriminators are required: each of
  # this session's two PROVEN false positives defeats only ONE of them.
  case "$response" in
    "${_MPG_DEATH_PREFIX}"*) : ;;
    *) return 0 ;;
  esac
  local after_prefix="${response#*"${_MPG_DEATH_PREFIX}"}"

  local matched
  matched="$(printf '%s' "$after_prefix" | grep -io -- "${_MPG_EXHAUSTION_PATTERN}[^\"]*" | head -1)"
  [ -z "$matched" ] && return 0    # no verbatim match -> record NOTHING (never infer)

  # AUTHORITATIVE identity over re-derivation: the tier that actually ran is
  # stated by the platform itself -- a `resolvedModel` field when the event
  # carries one, or the model NAME inside the error text (real errors say
  # "...for Fable 5..."/"...Opus...") -- never re-derived SOLELY from
  # frontmatter, which only proves what SHOULD have run, not what DID.
  # Frontmatter / the explicit `model:` on the spawn is consulted as a
  # FALLBACK only when no authoritative source names a tier. If an
  # authoritative source IS present and it DISAGREES with the fallback,
  # that is a genuine ambiguity this hook cannot resolve -- record NOTHING
  # rather than pick a side.
  local declared_model text_model authoritative_model
  declared_model="$(printf '%s' "$input" | jq -r '.resolvedModel // .tool_input.resolvedModel // ""' 2>/dev/null || true)"
  [ "$declared_model" = "null" ] && declared_model=""
  text_model="$(_mpg_parse_model_from_text "$response")"
  authoritative_model="${declared_model:-$text_model}"

  local spawn_model
  spawn_model="$(printf '%s' "$input" | jq -r '.tool_input.model // ""' 2>/dev/null || true)"
  [ "$spawn_model" = "null" ] && spawn_model=""
  if [ -z "$spawn_model" ]; then
    local agents_dir def
    agents_dir="${MODEL_PIN_AGENTS_DIR:-$HOME/.claude/agents}"
    [ -d "$agents_dir" ] || agents_dir="$(dirname "$0")/../agents"
    def="$(_resolve_agent_def "$atype" "$agents_dir")"
    [ -n "$def" ] && spawn_model="$(_mpg_frontmatter_model "$def")"
  fi

  local model
  if [ -n "$authoritative_model" ]; then
    if [ -n "$spawn_model" ] && [ "$spawn_model" != "$authoritative_model" ]; then
      return 0    # authoritative source disagrees with frontmatter/explicit -> never guess
    fi
    model="$authoritative_model"
  else
    model="$spawn_model"
  fi
  [ -z "$model" ] && return 0      # can't identify which tier ran -> never guess

  local ma
  ma="$(dirname "$0")/../scripts/model-availability.sh"
  [ -f "$ma" ] || ma="$HOME/.claude/scripts/model-availability.sh"
  [ -f "$ma" ] || return 0

  # Escalating TTL: a SECOND auto-observed death on a tier that is STILL
  # within a previous marker's window means dispatches keep landing on an
  # already-known-bad tier; re-marking at the same 4h base just resets the
  # clock forever without ever holding. Escalate to 12h so the fallback
  # sticks through a fuller cycle -- a FRESH first observation still gets
  # only the 4h base, so this does not lengthen the blast radius of a
  # one-off false mark.
  local hours=4
  bash "$ma" is-exhausted "$model" >/dev/null 2>&1 && hours=12

  # C2 fix: never persist or re-emit the matched trigger text. Store a FIXED
  # token + tier + UTC timestamp only -- this is the ONLY thing written to
  # the reason field a downstream dispatch prompt could ever echo.
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  bash "$ma" mark-exhausted "$model" --hours "$hours" \
    --reason "observed: API spend-limit error at ${ts}" >&2

  # Visible signal + audit (2026-08-06 remediation: the mark previously went
  # to stderr only, easy to miss). Emit the clear-with instruction on stdout
  # and append a one-line audit row, both sandboxable via env override so
  # --self-test never touches real machine state.
  echo "MODEL-AVAILABILITY: marked ${model} exhausted (auto-observed) — clear with: model-availability.sh clear ${model}"
  local audit_log
  audit_log="${MODEL_AVAIL_AUDIT_LOG:-$HOME/.claude/state/model-availability-audit.log}"
  mkdir -p "$(dirname "$audit_log")" 2>/dev/null
  printf '%s\ttier=%s\thours=%s\tauto-observed\ttool=%s\tsubagent_type=%s\n' \
    "$ts" "$model" "$hours" "$tool" "${atype:-<none>}" >> "$audit_log" 2>/dev/null
  return 0
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
  # A KNOWN agent name (present in the real config/model-policy.json's
  # agents{} map, chain=[fable,opus]) whose frontmatter is genuinely
  # unpinned — the case the new fix1_line resolution names a specific
  # model for, vs. the generic text for a truly unknown/typo'd type.
  printf -- '---\nname: task-verifier\ntools: Read\n---\nbody\n' > "$fix/agents/task-verifier.md"

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

  # --- Silent-inherit block now NAMES the resolved model for a KNOWN,
  # genuinely-unpinned agent type (operator directive 2026-08-05: "one
  # obvious line, not a research task"). Uses the REAL config/model-
  # policy.json (task-verifier's declared chain is [fable,opus]) against
  # the sandboxed, empty MODEL_AVAIL_STATE_DIR exported above -> fable is
  # fresh -> resolves to fable.
  #
  # Needle is the "(resolved from ...)" clause, NOT bare "model: fable" --
  # mutation-testing this assertion (2026-08-05) proved "model: fable" is a
  # SUBSTRING of the generic fallback text "model: fable|opus|sonnet|haiku",
  # so a bare-substring needle stayed green even with the resolver call
  # gutted entirely. The "(resolved from ...)" clause only ever appears on
  # the resolved path, so it is the actual discriminator.
  _rc_msg 2 "known-but-unpinned agent → BLOCK naming its resolved chain[0] model" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"task-verifier"}}' \
    "resolved from config/model-policy.json's chain for 'task-verifier'"
  # An UNKNOWN/typo'd agent type must still fall back to the generic
  # fable|opus|sonnet|haiku text — resolution failing (no chain declared)
  # must never be papered over with a guessed model.
  _rc_msg 2 "unknown agent type → BLOCK with generic policy text (no chain to resolve)" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"does-not-exist"}}' "fable|opus|sonnet|haiku"

  # --- --observe (PostToolUse): OBSERVE, DON'T ASSUME. Each scenario runs
  # against its OWN empty MODEL_AVAIL_STATE_DIR (never the suite-wide $fix
  # one, so a mark from one scenario can't leak into the next) and asserts
  # the exhaustion marker file itself, not just an rc (rc is always 0 for
  # --observe — it never blocks).
  _rc_observe() { # <name> <json> <expected-marked-tier-or-empty>
    local name="$1" json="$2" expect="$3" obsdir got_files
    obsdir="$(mktemp -d 2>/dev/null)" || { echo "  FAIL $name (mktemp)"; fail=$((fail+1)); return; }
    CLAUDE_TOOL_INPUT="$json" MODEL_PIN_AGENTS_DIR="$fix/agents" MODEL_AVAIL_STATE_DIR="$obsdir" \
      bash "$SELF" --observe >/dev/null 2>&1
    got_files="$(ls -1 "$obsdir" 2>/dev/null)"
    if [ -n "$expect" ]; then
      if [ -f "$obsdir/$expect" ]; then echo "  ok   $name (marked '$expect')"; pass=$((pass+1))
      else echo "  FAIL $name (expected '$expect' marked; dir has: ${got_files:-<empty>})"; fail=$((fail+1)); fi
    else
      if [ -z "$got_files" ]; then echo "  ok   $name (nothing marked)"; pass=$((pass+1))
      else echo "  FAIL $name (unexpectedly marked: $got_files)"; fail=$((fail+1)); fi
    fi
    rm -rf "$obsdir" 2>/dev/null
  }

  # 2026-08-06 remediation: the positive fixtures below now carry the REAL
  # anchored prefix "Error: Agent terminated early due to an API error:"
  # proven (90-transcript corpus) to begin all 13 real deaths -- a fixture
  # that used to pass with just the bare exhaustion phrase would now
  # (correctly) mark nothing, since that shape is exactly what a launch-ack
  # echo or an agent's own report can also contain (see the two FP negatives
  # below).
  _rc_observe "anchored death, frontmatter-pinned agent, no tier named in text → marks the pinned tier (frontmatter fallback)" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit. Please switch models."}' \
    "fable"
  # Real production wording carries an apostrophe AND names the tier in the
  # error text -- prove the pattern matches the VERBATIM string AND that the
  # authoritative text-parsed tier (fable) AGREEING with the frontmatter
  # fallback (fable) still marks correctly.
  REALISTIC_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: Agent terminated early due to an API error: You'"'"'ve hit your monthly spend limit for Fable 5 — switch models to continue this chat."}'
  _rc_observe "realistic verbatim spend-limit error (apostrophe + tier named, agrees with frontmatter) → marks the pinned tier" \
    "$REALISTIC_JSON" "fable"
  _rc_observe "anchored death, explicit model on the spawn, no tier named in text → marks the explicit tier" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"unpinned-agent","model":"opus"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}' \
    "opus"
  _rc_observe "AUTHORITATIVE text names a DIFFERENT tier than the frontmatter pin → disagreement → marks NOTHING (never guesses which is right)" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit for Opus 5 — switch models."}' \
    ""
  _rc_observe "resolvedModel field present (no frontmatter/explicit model in play) → marks the resolvedModel tier" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"unpinned-agent"},"resolvedModel":"opus","tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}' \
    "opus"
  _rc_observe "normal completion (no error string) → marks nothing" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"DONE, all tests pass"}' \
    ""
  _rc_observe "unrelated error text → marks nothing (never infer from a DIFFERENT error)" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: rate limited, try again later"}' \
    ""
  _rc_observe "non-Task/Agent tool → marks nothing" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}' \
    ""
  _rc_observe "unresolvable agent (unknown type, no explicit model), anchored death → marks nothing, never guesses" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"does-not-exist"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}' \
    ""
  _rc_observe "fork subagent_type → exempt, never marked even against a real death shape" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"fork"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}' \
    ""

  # --- C1 FP-replay proof: the two REAL corpus shapes that produced false
  # positives under the v1 (unanchored) matcher. Both must now mark NOTHING.
  _rc_observe "PROVEN FP #1 (launch-ack OBJECT whose .prompt echoes the phrase) → marks NOTHING" \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"pinned-agent"},"tool_response":{"prompt":"Investigate the C1 defect where a launch-ack containing the phrase '"'"'hit your monthly spend limit'"'"' falsely marked a healthy tier exhausted.","status":"launched"}}' \
    ""
  _rc_observe "PROVEN FP #2 (foreground STRING agent REPORT mentioning the phrase, no death prefix) → marks NOTHING" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Verdict: DONE\nSummary: fixed the false positive where a report mentioning \"hit your monthly spend limit\" in prose wrongly marked a tier exhausted."}' \
    ""

  # --- C2 proof: the reason PERSISTED never carries the matched trigger
  # text, only the fixed token -- so nothing downstream (dispatch-
  # directives.sh, a future resolve call) can ever re-emit attacker/self-
  # controllable content, regardless of what the underlying error said.
  _rc_observe_reason() { # <name> <json> <expect-tier>
    local name="$1" json="$2" expect="$3" obsdir got_reason
    obsdir="$(mktemp -d 2>/dev/null)" || { echo "  FAIL $name (mktemp)"; fail=$((fail+1)); return; }
    CLAUDE_TOOL_INPUT="$json" MODEL_PIN_AGENTS_DIR="$fix/agents" MODEL_AVAIL_STATE_DIR="$obsdir" \
      bash "$SELF" --observe >/dev/null 2>&1
    got_reason="$(MODEL_AVAIL_STATE_DIR="$obsdir" bash "$ma_path" reason "$expect" 2>/dev/null || true)"
    if printf '%s' "$got_reason" | grep -q "^observed: API spend-limit error at " \
       && ! printf '%s' "$got_reason" | grep -qi "hit your monthly spend limit"; then
      echo "  ok   $name (reason='$got_reason')"; pass=$((pass+1))
    else
      echo "  FAIL $name (reason='$got_reason' -- must be the fixed token, never the verbatim trigger)"; fail=$((fail+1))
    fi
    rm -rf "$obsdir" 2>/dev/null
  }
  _rc_observe_reason "stored reason is the FIXED token, never the verbatim matched trigger text" \
    '{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit for Fable 5, upgrade to keep going."}' \
    "fable"

  # --- Escalating TTL: a SECOND auto-observed death on a tier STILL within
  # the first marker's window escalates 4h -> 12h; a FRESH first
  # observation stays at 4h.
  ESC_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"pinned-agent"},"tool_response":"Error: Agent terminated early due to an API error: You have hit your monthly spend limit"}'
  ESCDIR="$(mktemp -d 2>/dev/null)"
  CLAUDE_TOOL_INPUT="$ESC_JSON" MODEL_PIN_AGENTS_DIR="$fix/agents" MODEL_AVAIL_STATE_DIR="$ESCDIR" bash "$SELF" --observe >/dev/null 2>&1
  FIRST_HOURS="$(cut -f2 "$ESCDIR/fable" 2>/dev/null)"
  if [ "$FIRST_HOURS" = "4" ]; then echo "  ok   fresh auto-mark uses the 4h base"; pass=$((pass+1))
  else echo "  FAIL fresh auto-mark hours: got '$FIRST_HOURS', expected 4"; fail=$((fail+1)); fi
  CLAUDE_TOOL_INPUT="$ESC_JSON" MODEL_PIN_AGENTS_DIR="$fix/agents" MODEL_AVAIL_STATE_DIR="$ESCDIR" bash "$SELF" --observe >/dev/null 2>&1
  SECOND_HOURS="$(cut -f2 "$ESCDIR/fable" 2>/dev/null)"
  if [ "$SECOND_HOURS" = "12" ]; then echo "  ok   second auto-mark within the first marker's window escalates to 12h"; pass=$((pass+1))
  else echo "  FAIL escalated auto-mark hours: got '$SECOND_HOURS', expected 12"; fail=$((fail+1)); fi
  rm -rf "$ESCDIR" 2>/dev/null

  # --- Visible signal + audit: the stdout line names the clear command, and
  # an audit row is appended (sandboxed via MODEL_AVAIL_AUDIT_LOG so this
  # never touches the real machine-wide audit log).
  AUDIT_LOG="$(mktemp -u 2>/dev/null)"
  AUDDIR="$(mktemp -d 2>/dev/null)"
  AUDIT_OUT="$(CLAUDE_TOOL_INPUT="$ESC_JSON" MODEL_PIN_AGENTS_DIR="$fix/agents" MODEL_AVAIL_STATE_DIR="$AUDDIR" MODEL_AVAIL_AUDIT_LOG="$AUDIT_LOG" bash "$SELF" --observe 2>/dev/null)"
  if printf '%s' "$AUDIT_OUT" | grep -q "^MODEL-AVAILABILITY: marked fable exhausted (auto-observed) — clear with: model-availability.sh clear fable$"; then
    echo "  ok   auto-mark emits the clear-with signal on stdout"; pass=$((pass+1))
  else
    echo "  FAIL stdout signal missing/wrong: '$AUDIT_OUT'"; fail=$((fail+1))
  fi
  if [ -f "$AUDIT_LOG" ] && grep -q "tier=fable" "$AUDIT_LOG" 2>/dev/null; then
    echo "  ok   audit row appended to the (sandboxed) audit log"; pass=$((pass+1))
  else
    echo "  FAIL audit row not found in '$AUDIT_LOG'"; fail=$((fail+1))
  fi
  rm -rf "$AUDDIR" "$AUDIT_LOG" 2>/dev/null

  rm -rf "$fix" 2>/dev/null
  echo ""
  echo "model-pin-gate self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

SELF="$0"
if [ "${1:-}" = "--self-test" ]; then run_self_test; exit $?; fi
if [ "${1:-}" = "--observe" ]; then run_observe; exit $?; fi
run_gate
exit $?
