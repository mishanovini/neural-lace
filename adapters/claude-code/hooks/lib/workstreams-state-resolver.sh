#!/bin/bash
# workstreams-state-resolver.sh — SHARED canonical-state-path resolver (sourced).
#
# Why this exists (Workstreams consolidation, Phase A, 2026-06-08):
#   The Workstreams subsystem state was scattered across ~9 files because the
#   writer hooks (workstreams-emit.sh, workstreams-turn-emit.sh,
#   decision-context-gate.sh) and the GUI server each hardcoded a DIFFERENT
#   tree-state.json path — a GUI-sink path (main-checkout module file) and a
#   §5-gate path (per-project .claude/state/conversation-tree/) that diverged.
#   The fix: ONE canonical state file, whose location is recorded in a single
#   discoverable config, resolved IDENTICALLY by every writer + the GUI.
#
# Canonical config (read order, first non-empty wins):
#   1. $CONV_TREE_STATE_PATH env var — explicit single-sink override. ABSOLUTE
#      precedence so --self-tests (which point every emit at a temp file) and
#      any deliberate one-off redirection keep working unchanged.
#   2. ~/.claude/workstreams-state-path.txt — the home-dir config. Always
#      readable from any worktree/cwd (home dir, not repo-relative). Its single
#      line is the absolute path to the canonical tree-state.json.
#   3. The per-project fallback path passed as $1 — the pre-consolidation
#      behavior, kept so a machine WITHOUT the config file still works exactly
#      as before (graceful degradation, no hard dependency on the new config).
#
# Usage (sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/workstreams-state-resolver.sh"
#   sink=$(resolve_workstreams_state_path "$legacy_per_project_path")
#
# Contract: prints the resolved absolute path to stdout, exit 0. Never blocks,
# never errors fatally — a resolver used by writer hooks must never break a
# tool call (gate-respect.md: writer hooks do not block anything).

# The home-dir config file. Overridable via WORKSTREAMS_STATE_CONFIG for tests.
: "${WORKSTREAMS_STATE_CONFIG:=$HOME/.claude/workstreams-state-path.txt}"

# Read the canonical path from the home config file. Trims surrounding
# whitespace and the trailing newline; ignores blank/comment lines. Prints the
# path on stdout (empty if the file is absent/empty/comment-only).
_read_workstreams_state_config() {
  local cfg="${WORKSTREAMS_STATE_CONFIG:-}"
  [[ -n "$cfg" && -f "$cfg" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # strip CR (Windows line endings), then surrounding whitespace
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    printf '%s' "$line"
    return 0
  done < "$cfg"
  return 0
}

# resolve_workstreams_state_path <legacy_fallback_path>
#   1. $CONV_TREE_STATE_PATH (explicit override) — highest precedence.
#   2. canonical home-config path.
#   3. <legacy_fallback_path> ($1) — pre-consolidation per-project behavior.
resolve_workstreams_state_path() {
  local fallback="${1:-}"
  if [[ -n "${CONV_TREE_STATE_PATH:-}" ]]; then
    printf '%s' "$CONV_TREE_STATE_PATH"
    return 0
  fi
  local cfg_path
  cfg_path=$(_read_workstreams_state_config)
  if [[ -n "$cfg_path" ]]; then
    printf '%s' "$cfg_path"
    return 0
  fi
  printf '%s' "$fallback"
  return 0
}

# --self-test for the resolver itself. Exit 0 on OK, 1 on FAIL.
# Guard: only run when this file is EXECUTED directly, never when SOURCED by a
# hook (otherwise a hook invoked with `--self-test` would trip this block via
# its own positional $1). BASH_SOURCE[0] == $0 iff executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--self-test" ]]; then
  _rt_fail=0
  _rt_ck() { # name expected actual
    if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else echo "FAIL: $1 (want '$2' got '$3')"; _rt_fail=$((_rt_fail+1)); fi
  }
  _rt_tmp=$(mktemp -d)
  trap 'rm -rf "$_rt_tmp"' EXIT

  # R1: env override wins over everything
  echo "/canon/from/config.json" > "$_rt_tmp/cfg.txt"
  WORKSTREAMS_STATE_CONFIG="$_rt_tmp/cfg.txt" CONV_TREE_STATE_PATH="/env/override.json" \
    _rt_ck "R1 env override wins" "/env/override.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/cfg.txt" CONV_TREE_STATE_PATH="/env/override.json" resolve_workstreams_state_path "/fallback.json")"

  # R2: config file used when no env override
  _rt_ck "R2 config file used" "/canon/from/config.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/cfg.txt" CONV_TREE_STATE_PATH="" resolve_workstreams_state_path "/fallback.json")"

  # R3: fallback used when config file absent
  _rt_ck "R3 fallback when config absent" "/fallback.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/does-not-exist.txt" CONV_TREE_STATE_PATH="" resolve_workstreams_state_path "/fallback.json")"

  # R4: trailing whitespace / CRLF trimmed from config line
  printf '  /canon/with/space.json  \r\n' > "$_rt_tmp/cfg2.txt"
  _rt_ck "R4 trims whitespace+CR" "/canon/with/space.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/cfg2.txt" CONV_TREE_STATE_PATH="" resolve_workstreams_state_path "/fallback.json")"

  # R5: comment + blank lines skipped, first real line wins
  printf '# a comment\n\n/canon/after/comment.json\n/second/ignored.json\n' > "$_rt_tmp/cfg3.txt"
  _rt_ck "R5 skips comments/blanks" "/canon/after/comment.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/cfg3.txt" CONV_TREE_STATE_PATH="" resolve_workstreams_state_path "/fallback.json")"

  # R6: empty config file → fallback
  : > "$_rt_tmp/empty.txt"
  _rt_ck "R6 empty config -> fallback" "/fallback.json" "$(WORKSTREAMS_STATE_CONFIG="$_rt_tmp/empty.txt" CONV_TREE_STATE_PATH="" resolve_workstreams_state_path "/fallback.json")"

  if [[ "$_rt_fail" -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: $_rt_fail failed"; exit 1; fi
fi
