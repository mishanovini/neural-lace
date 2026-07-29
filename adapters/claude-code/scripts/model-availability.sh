#!/bin/bash
# model-availability.sh — record and query which model TIERS are currently
# unusable, so the documented fallback chain becomes a real mechanism.
#
# ============================================================================
# THE GAP THIS CLOSES (PROVEN, 2026-07-28)
# ============================================================================
# config/model-policy.json defines every reviewer as an ordered chain
# ["fable","opus"], and its own note concedes the weakness:
#
#   "the fallback is a documented preference (the Agent frontmatter model: field
#    holds a single value)"
#
# So the chain is DOCUMENTED and nothing applies it. 21 of 25 agents pin
# `model: fable`. On 2026-07-28 the operator's Fable weekly budget was exhausted
# and BOTH verifier dispatches (task-verifier, harness-reviewer) died instantly:
#
#   "You've hit your monthly spend limit ... to keep using Fable 5 or switch
#    models to continue this chat."
#
# They only ran when the caller manually passed model: opus. The operator's
# reaction: "Fable is supposed to always fail back to Opus. That's supposed to be
# built in. If it's not, then fix it."
#
# The consequence is worse than a failed dispatch: a verification that dies on
# arrival is a verification that did not happen, and the session moves on. That
# is exactly how f6562b2 reached master unreviewed.
#
# ============================================================================
# HOW THE FALLBACK ACTUALLY HAPPENS
# ============================================================================
# `apply <tier>` REPINS every agent pinned to the exhausted tier to its chain
# fallback, so the dispatch genuinely RUNS on the fallback model. That is the
# fallback. `restore <tier>` puts the pins back.
#
# An earlier version of this file shipped ONLY the marker + a gate block, and
# described that as the fix. It was not: a block is a stop sign that still
# requires a human or agent to act, and the operator's requirement was that
# Fable ALWAYS fall back to Opus. Recording the correction here because the
# distinction is the whole point — "blocks the dispatch and tells you to use
# Opus" and "runs on Opus" are different products.
#
# The gate block (model-pin-gate.sh) is retained as a BACKSTOP for the window
# where a tier is known-exhausted but `apply` has not been run: without it a
# stale Fable pin dies silently at the API. Marker = knowledge, apply = action,
# gate = backstop.
#
# ============================================================================
# API
# ============================================================================
#   model-availability.sh mark-exhausted <tier> [--reason TEXT] [--hours N]
#       Record <tier> as unusable for N hours (default 24 — weekly limits reset
#       on a schedule this script cannot read, so the TTL is deliberately short
#       and re-marking is cheap).
#   model-availability.sh is-exhausted <tier>      -> rc 0 if currently marked
#   model-availability.sh clear <tier>             -> remove the marker
#   model-availability.sh status                   -> human-readable listing
#   model-availability.sh fallback-for <tier>      -> echo the next tier in the
#       chain from config/model-policy.json (the chain the harness already
#       documents), empty if none.
#
# STATE: ${MODEL_AVAIL_STATE_DIR:-$HOME/.claude/state/model-availability}/<tier>
# Machine-local by design: a budget is per-account-per-machine-session, not a
# property of the repo, so this must never be committed.
#
# Self-test: bash model-availability.sh --self-test
# ============================================================================

set -uo pipefail
_MA_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_ma_state_dir() {
  if [[ -n "${MODEL_AVAIL_STATE_DIR:-}" ]]; then printf '%s' "$MODEL_AVAIL_STATE_DIR"; return 0; fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}}/ma-selftest-$$"; return 0
  fi
  printf '%s' "$HOME/.claude/state/model-availability"
}

_ma_now() { if [[ -n "${EPOCHSECONDS:-}" ]]; then printf '%s' "$EPOCHSECONDS"; else date +%s 2>/dev/null || echo 0; fi; }

_ma_tier_ok() { case "$1" in fable|opus|sonnet|haiku|mythos) return 0 ;; *) return 1 ;; esac; }

cmd_mark_exhausted() {
  local tier="${1:-}"; shift 2>/dev/null || true
  _ma_tier_ok "$tier" || { echo "model-availability: unknown tier '$tier'" >&2; return 2; }
  local reason="" hours=4   # 4h, not 24: the operator said "resets in a few hours"; a TTL is a GUESS standing in for an unobservable condition, so it must err short — an over-long TTL keeps agents off their primary (invariant b)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --hours) hours="${2:-24}"; shift 2 ;;
      *) shift ;;
    esac
  done
  local d; d="$(_ma_state_dir)"; mkdir -p "$d" 2>/dev/null || return 0
  local until_ts=$(( $(_ma_now) + hours * 3600 ))
  printf '%s\t%s\t%s\n' "$until_ts" "$hours" "${reason:-unspecified}" > "$d/$tier" 2>/dev/null || return 0
  echo "model-availability: '$tier' marked exhausted for ${hours}h (reason: ${reason:-unspecified})"
  local fb; fb="$(cmd_fallback_for "$tier")"
  [[ -n "$fb" ]] && echo "model-availability: dispatches pinned to '$tier' will be blocked with instructions to use '$fb'"
  return 0
}

cmd_is_exhausted() {
  local tier="${1:-}"
  local f; f="$(_ma_state_dir)/$tier"
  [[ -r "$f" ]] || return 1
  local until_ts rest
  IFS=$'\t' read -r until_ts rest < "$f" 2>/dev/null || return 1
  [[ "$until_ts" =~ ^[0-9]+$ ]] || return 1
  if (( $(_ma_now) >= until_ts )); then
    rm -f "$f" 2>/dev/null   # self-expiring: a stale marker must never persist
    return 1
  fi
  return 0
}

cmd_clear() {
  local tier="${1:-}"
  rm -f "$(_ma_state_dir)/$tier" 2>/dev/null
  echo "model-availability: cleared '$tier'"
}

cmd_reason() {
  local tier="${1:-}" f until_ts hours reason
  f="$(_ma_state_dir)/$tier"; [[ -r "$f" ]] || return 1
  IFS=$'\t' read -r until_ts hours reason < "$f" 2>/dev/null || return 1
  printf '%s' "${reason:-unspecified}"
}

cmd_fallback_for() {
  local tier="${1:-}"
  local policy="$_MA_SELF_DIR/../config/model-policy.json"
  [[ -r "$policy" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # first chain in categories[] that starts with <tier>; echo its next element
  jq -r --arg t "$tier" '
    [ (.categories // {}) | to_entries[] | .value ]
    | map(select(length > 1 and .[0] == $t))
    | if length > 0 then .[0][1] else "" end' "$policy" 2>/dev/null
}

cmd_status() {
  local d; d="$(_ma_state_dir)"
  local any=0 t
  for t in fable mythos opus sonnet haiku; do
    if cmd_is_exhausted "$t"; then
      any=1
      printf '  %-8s EXHAUSTED  (reason: %s; fallback: %s)\n' "$t" "$(cmd_reason "$t")" "$(cmd_fallback_for "$t")"
    fi
  done
  [[ "$any" -eq 0 ]] && echo "  all tiers available"
  return 0
}

# ---------------------------------------------------------------------------
# apply / restore — THE ACTUAL FALLBACK
# ---------------------------------------------------------------------------
# Operator directive 2026-07-29: "Fable is supposed to always fail back to Opus."
#
# WHY A PIN REWRITE IS THE ONLY REAL IMPLEMENTATION. The workflow recon of
# 2026-07-29 established three facts that rule out every other approach:
#   1. docs/decisions/063-model-pin-gate-blocks-not-injects.md — `updatedInput`
#      does NOT apply to Task/Agent spawns, and SubagentStart has no decision
#      control. A hook can DENY a dispatch; it can never re-point one.
#   2. docs/lessons/2026-07-24-fable-is-most-powerful-and-separately-budgeted.md
#      :82-89 — "Sub-agent model is fixed at dispatch — exhaustion kills, never
#      downgrades." The platform performs no fallback, ever.
#   3. config/model-policy.json's `chain` is read by NO running code, and
#      install.sh does not even sync config/ to ~/.claude. The chain has always
#      been documentation.
# The model is decided by ONE thing that actually executes: the `model:` line in
# agents/<slug>.md. So a real fallback rewrites that line. Anything else is a
# stop sign, not a fallback.
#
# apply   <tier> : rewrite every agent pinned to <tier> to its chain fallback,
#                  recording the original pin so restore is exact.
# restore <tier> : put the recorded pins back.
#
# NOTE: ~/.claude/agents is a symlink to the repo on this machine, so apply
# DIRTIES THE WORKING TREE. That is intended — it is a temporary operational
# flip, like a feature flag, and `restore` is its off switch. Do not commit the
# flipped pins.
_ma_agents_dir() {
  if [[ -n "${MODEL_AVAIL_AGENTS_DIR:-}" ]]; then printf '%s' "$MODEL_AVAIL_AGENTS_DIR"; return 0; fi
  local d="$_MA_SELF_DIR/../agents"
  [[ -d "$d" ]] && { printf '%s' "$d"; return 0; }
  printf '%s' "$HOME/.claude/agents"
}


# --- fence-scoped frontmatter field helpers (portable: tmp+mv, never sed -i) ---
_ma_field_of() {
  local f="$1" key="$2" in_fm=0 line v
  [[ -f "$f" ]] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "---" ]]; then
      if [[ "$in_fm" -eq 0 ]]; then in_fm=1; continue; else break; fi
    fi
    if [[ "$in_fm" -eq 1 ]]; then
      case "$line" in
        "$key":*) v="${line#"$key":}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; return 0 ;;
      esac
    fi
  done < "$f"
  return 0
}

_ma_set_field() {
  local f="$1" key="$2" val="$3" tmp="$1.ma.$$" in_fm=0 line done_=0
  [[ "$(_ma_field_of "$f" "$key")" == "$val" ]] && return 0
  : > "$tmp" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    local raw="$line"; line="${line%$'\r'}"
    if [[ "$line" == "---" ]]; then
      if [[ "$in_fm" -eq 0 ]]; then in_fm=1; printf '%s\n' "$raw" >> "$tmp"; continue; fi
      if [[ "$in_fm" -eq 1 && "$done_" -eq 0 ]]; then printf '%s: %s\n' "$key" "$val" >> "$tmp"; done_=1; fi
      in_fm=2; printf '%s\n' "$raw" >> "$tmp"; continue
    fi
    if [[ "$in_fm" -eq 1 && "$done_" -eq 0 ]]; then
      case "$line" in "$key":*) printf '%s: %s\n' "$key" "$val" >> "$tmp"; done_=1; continue ;; esac
    fi
    printf '%s\n' "$raw" >> "$tmp"
  done < "$f"
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

_ma_del_field() {
  local f="$1" key="$2" tmp="$1.ma.$$" in_fm=0 line
  [[ -n "$(_ma_field_of "$f" "$key")" ]] || return 0
  : > "$tmp" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    local raw="$line"; line="${line%$'\r'}"
    if [[ "$line" == "---" ]]; then
      if [[ "$in_fm" -eq 0 ]]; then in_fm=1; else in_fm=2; fi
      printf '%s\n' "$raw" >> "$tmp"; continue
    fi
    if [[ "$in_fm" -eq 1 ]]; then
      case "$line" in "$key":*) continue ;; esac
    fi
    printf '%s\n' "$raw" >> "$tmp"
  done < "$f"
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}


# pin accessors, expressed in terms of the generic field helpers so there is ONE
# parser for this data (harness-review Minor: a guard and the action it guards
# must not use divergent matchers).
_ma_pin_of()  { _ma_field_of "$1" "model"; }
_ma_set_pin() { _ma_set_field "$1" "model" "$2"; }

# _ma_primary_of <file> — the agent's DECLARED PRIMARY, read from the file
# itself. If a borrow is active the file carries `model-primary:` (written by
# the borrow); otherwise the current `model:` pin IS the primary.
#
# THIS IS THE WHOLE POINT OF THE REDESIGN. v1 stored the undo in a machine-local
# TSV and used that file's mere existence as a latch. harness-reviewer proved
# four non-adversarial sequences that ended in a PERMANENT Opus borrow or a
# silently-dead one: lose the state dir and the borrow is forever; let
# session-start-auto-install.sh master-wins-revert agents/*.md (it syncs the
# agents/ subdir on the SAME SessionStart event) and reconcile refuses to
# re-apply because the record still exists; an apply that matched zero agents
# still created the record and latched reconcile off; a crash between the pin
# write and the record append stranded unrecorded agents on the fallback.
# Storing the undo for a mutation in storage LESS DURABLE than the mutation is
# the defect class. So: no record. The file carries its own truth, the desired
# pin is recomputed from scratch every run, and an external revert is
# self-correcting because the next reconcile just re-derives.
_ma_primary_of() {
  local f="$1" v
  v="$(_ma_field_of "$f" "model-primary")"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  _ma_pin_of "$f"
}

# reconcile — STATELESS and UNCONDITIONAL. For every agent: derive the primary
# from the file, ask whether that tier is available, and make the pin match.
# Idempotent, so it is safe on every session start and every dispatch.
#   primary available      -> pin = primary, and model-primary: is removed
#   primary unavailable    -> pin = fallback, and model-primary: records the primary
cmd_reconcile() {
  local quiet=0
  [[ "${1:-}" == "--quiet" ]] && quiet=1
  local ad; ad="$(_ma_agents_dir)"
  [[ -d "$ad" ]] || return 0
  local f primary cur desired fb borrowed=0 returned=0
  for f in "$ad"/*.md; do
    [[ -f "$f" ]] || continue
    primary="$(_ma_primary_of "$f")"
    [[ -n "$primary" ]] || continue
    cur="$(_ma_pin_of "$f")"
    if cmd_is_exhausted "$primary"; then
      fb="$(cmd_fallback_for "$primary")"
      [[ -n "$fb" ]] || continue
      desired="$fb"
    else
      desired="$primary"
    fi
    if [[ "$cur" != "$desired" ]]; then
      _ma_set_pin "$f" "$desired" || continue
      [[ "$desired" == "$primary" ]] && returned=$((returned+1)) || borrowed=$((borrowed+1))
    fi
    # keep the primary recorded IN THE FILE only while it differs from the pin
    if [[ "$desired" == "$primary" ]]; then
      _ma_del_field "$f" "model-primary"
    else
      _ma_set_field "$f" "model-primary" "$primary"
    fi
  done
  if [[ "$quiet" -eq 0 ]]; then
    [[ "$borrowed" -gt 0 ]] && echo "model-availability: borrowed a fallback for $borrowed agent(s) whose primary is unavailable"
    [[ "$returned" -gt 0 ]] && echo "model-availability: returned $returned agent(s) to their declared primary"
    [[ "$borrowed" -eq 0 && "$returned" -eq 0 ]] && echo "model-availability: pins already correct (no change)"
  fi
  return 0
}

# apply/restore are now thin wrappers over reconcile, kept because the doctrine
# and the gate's remedy text name them. They no longer maintain any state.
cmd_apply()   { cmd_reconcile "${2:---quiet}" >/dev/null 2>&1; cmd_reconcile; }
cmd_restore() { cmd_reconcile "${2:---quiet}" >/dev/null 2>&1; cmd_reconcile; }

_ma_self_test() {
  local P=0 F=0
  pass() { P=$((P+1)); echo "  PASS: $*"; }
  fail() { F=$((F+1)); echo "  FAIL: $*"; }
  local T; T="$(mktemp -d)"; export MODEL_AVAIL_STATE_DIR="$T/state"

  echo "Scenario 1: unmarked tier is not exhausted"
  cmd_is_exhausted fable && fail "fable reported exhausted with no marker" || pass "clean state -> not exhausted"

  echo "Scenario 2: mark then query"
  cmd_mark_exhausted fable --reason "weekly budget hit" --hours 24 >/dev/null
  cmd_is_exhausted fable && pass "marked tier reports exhausted" || fail "marker not honored"
  [[ "$(cmd_reason fable)" == "weekly budget hit" ]] && pass "reason round-trips" || fail "reason lost: '$(cmd_reason fable)'"

  echo "Scenario 3: fallback resolves from model-policy.json (not hardcoded here)"
  local fb; fb="$(cmd_fallback_for fable)"
  [[ "$fb" == "opus" ]] && pass "fable -> opus, read from config/model-policy.json" || fail "expected opus, got '$fb'"

  echo "Scenario 4: an EXPIRED marker self-clears and does not linger"
  printf '%s\t%s\t%s\n' "1" "24" "ancient" > "$MODEL_AVAIL_STATE_DIR/sonnet"
  cmd_is_exhausted sonnet && fail "expired marker still reported exhausted" || pass "expired marker treated as available"
  [[ -f "$MODEL_AVAIL_STATE_DIR/sonnet" ]] && fail "expired marker file was not removed" || pass "expired marker file removed"

  echo "Scenario 5: clear works"
  cmd_clear fable >/dev/null
  cmd_is_exhausted fable && fail "still exhausted after clear" || pass "clear removes the marker"

  echo "Scenario 6: unknown tier is rejected, not silently accepted"
  cmd_mark_exhausted bogus-tier >/dev/null 2>&1 && fail "unknown tier accepted" || pass "unknown tier rejected"

  echo "Scenario 7: sandbox integrity — DELTA on real state, not its absence"
  # Asserting the real dir does not EXIST is self-invalidating: legitimate
  # production use (mark-exhausted / apply) creates it, so the test would go red
  # precisely because the feature works. This is the third instance of that class
  # in this harness in two days; assert a before/after delta instead.
  local _real="$HOME/.claude/state/model-availability"
  local _b=0; [[ -d "$_real" ]] && _b="$(ls -1 "$_real" 2>/dev/null | wc -l | tr -d ' ')"
  cmd_mark_exhausted haiku --reason "sandbox delta probe, must not touch real state" >/dev/null 2>&1
  local _a=0; [[ -d "$_real" ]] && _a="$(ls -1 "$_real" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$_b" == "$_a" ]] && pass "real state dir untouched by this self-test (entries $_b -> $_a)" \
    || fail "SANDBOX ESCAPE: real state dir changed ($_b -> $_a)"

  echo "Scenario 8: apply/restore is the REAL fallback — pins actually change"
  local AD="$T/agents"; mkdir -p "$AD"; export MODEL_AVAIL_AGENTS_DIR="$AD"
  printf -- '---\nname: rev\nmodel: fable\ntools: Read\n---\nbody\n' > "$AD/rev.md"
  printf -- '---\nname: exp\nmodel: haiku\n---\nbody\n' > "$AD/exp.md"
  cmd_apply fable >/dev/null 2>&1
  [[ "$(_ma_pin_of "$AD/rev.md")" == "opus" ]] && pass "fable-pinned agent repinned to opus (this is the fallback)" \
    || fail "apply did not repin: got '$(_ma_pin_of "$AD/rev.md")'"
  [[ "$(_ma_pin_of "$AD/exp.md")" == "haiku" ]] && pass "non-fable agent untouched" || fail "apply touched an unrelated tier"
  grep -q '^tools: Read' "$AD/rev.md" && pass "rest of the frontmatter preserved" || fail "apply corrupted the frontmatter"
  cmd_restore fable >/dev/null 2>&1
  [[ "$(_ma_pin_of "$AD/rev.md")" == "fable" ]] && pass "restore returns the original pin exactly" \
    || fail "restore failed: got '$(_ma_pin_of "$AD/rev.md")'"
  unset MODEL_AVAIL_AGENTS_DIR

  rm -rf "$T"; unset MODEL_AVAIL_STATE_DIR
  echo
  echo "self-test summary: $P passed, $F failed"
  [[ "$F" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    mark-exhausted) shift; cmd_mark_exhausted "$@" ;;
    is-exhausted)   shift; cmd_is_exhausted "$@" ;;
    clear)          shift; cmd_clear "$@" ;;
    reason)         shift; cmd_reason "$@" ;;
    fallback-for)   shift; cmd_fallback_for "$@" ;;
    status)         shift; cmd_status "$@" ;;
    apply)          shift; cmd_apply "$@" ;;
    restore)        shift; cmd_restore "$@" ;;
    reconcile)      shift; cmd_reconcile "$@" ;;
    --self-test)    _ma_self_test ;;
    *) echo "usage: model-availability.sh {mark-exhausted|is-exhausted|clear|reason|fallback-for|status|apply|restore|reconcile|--self-test}" >&2; exit 2 ;;
  esac
  exit $?
fi
