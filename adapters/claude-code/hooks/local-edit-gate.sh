#!/bin/bash
# local-edit-gate.sh — gate Edit/Write/MultiEdit on ~/.claude/local/**
#
# PreToolUse hook. Blocks the tool when the target file is under
# ~/.claude/local/ unless a fresh per-file authorization marker exists at:
#   ~/.claude/state/local-edit-<filename-slug>-<ISO8601>.txt
# with mtime within 30 minutes.
#
# Marker is written by the /grant-local-edit skill. The user invokes
# /grant-local-edit <filename> to authorize a single-file edit; the marker
# expires automatically after 30 min.
#
# Replaces the broad deny rules at settings.json `permissions.deny` for
# `~/.claude/local/**` patterns.
#
# Plan:    docs/plans/context-aware-permission-gates.md (Task 5)
# ADR:     docs/decisions/029-local-edit-authorization-mechanism.md
# Rule:    ~/.claude/rules/local-edit-authorization.md
# Skill:   ~/.claude/skills/grant-local-edit.md
#
# Behavior:
#   - Tool not in {Edit, Write, MultiEdit}     -> allow (silent, exit 0)
#   - file_path missing from input              -> block (fail closed)
#   - file_path NOT under ~/.claude/local/      -> allow (silent, exit 0)
#   - Fresh matching marker present             -> allow (stderr confirmation)
#   - No marker / stale / wrong slug            -> block (exit 2 + JSON decision)
#
# Self-test: bash local-edit-gate.sh --self-test
# Expected: 8/8 PASS, exit 0.
#
# Exit codes:
#   0 — tool may proceed
#   2 — tool is blocked; stderr explains why; stdout has JSON block decision

set -u

FRESHNESS_SECONDS=1800   # 30 min

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

# Read stdin JSON or CLAUDE_TOOL_INPUT env var.
load_input() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  printf '%s' "$input"
}

# Extract field from JSON via jq with bash fallback.
extract_field() {
  local input="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".$field // \"\"" 2>/dev/null
  else
    # Fallback: best-effort grep for "field": "value"
    printf '%s' "$input" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -1
  fi
}

# Derive a filename-slug: lowercase, dots/spaces → dashes, non-alphanumeric stripped.
filename_slug() {
  local name="$1"
  printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr '. ' '--' | sed -E 's/[^a-z0-9-]//g' | sed -E 's/-+/-/g' | sed -E 's/^-|-$//g'
}

# Check if path is under ~/.claude/local/. Accepts absolute and tilde paths.
# Returns 0 if under, 1 if not.
is_under_claude_local() {
  local path="$1"
  # Expand tilde
  local expanded="${path/#\~/$HOME}"
  # Resolve to absolute (without requiring existence — file may not exist yet for Write).
  case "$expanded" in
    /*) ;;
    *) expanded="$PWD/$expanded" ;;
  esac
  # Normalize Windows-Git-Bash paths: //c/foo and /c/foo are both ok
  local local_dir="${HOME}/.claude/local"
  case "$expanded" in
    "$local_dir"/*|"$local_dir") return 0 ;;
    *)
      # Also handle //c/Users/... vs /c/Users/... vs C:\Users\...
      # by normalizing to forward-slash + lowercase drive
      local normalized
      normalized=$(printf '%s' "$expanded" | sed -E 's|^//|/|' | sed -E 's|^([A-Z]):|/\L\1|' | tr '\\' '/')
      local normalized_local
      normalized_local=$(printf '%s' "$local_dir" | sed -E 's|^//|/|' | sed -E 's|^([A-Z]):|/\L\1|' | tr '\\' '/')
      case "$normalized" in
        "$normalized_local"/*|"$normalized_local") return 0 ;;
      esac
      return 1 ;;
  esac
}

# mtime in seconds since epoch (with portable fallback).
mtime_epoch() {
  local f="$1"
  [ -f "$f" ] || { echo 0; return; }
  stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0
}

# Find fresh marker for slug. Echo path if found, empty if not.
find_fresh_marker() {
  local slug="$1"
  local state_dir="${LOCAL_EDIT_STATE_DIR_OVERRIDE:-${HOME}/.claude/state}"
  [ -d "$state_dir" ] || return 1
  local now
  now=$(date +%s)
  local marker
  for marker in "$state_dir/local-edit-${slug}-"*.txt; do
    [ -f "$marker" ] || continue
    local mtime
    mtime=$(mtime_epoch "$marker")
    local age=$((now - mtime))
    if [ "$age" -ge 0 ] && [ "$age" -le "$FRESHNESS_SECONDS" ]; then
      echo "$marker"
      return 0
    fi
  done
  return 1
}

# Emit JSON block decision on stdout.
emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":"%s"}\n' "$reason"
}

# ============================================================
# Main gate logic
# ============================================================

run_gate() {
  local input
  input=$(load_input)

  # Tool name: from input.tool_name (Claude Code passes this)
  local tool_name
  tool_name=$(extract_field "$input" "tool_name")

  # If tool isn't Edit/Write/MultiEdit, silent allow.
  case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) return 0 ;;
  esac

  # Extract file_path from tool_input.file_path
  local file_path
  if command -v jq >/dev/null 2>&1; then
    file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
  else
    file_path=$(printf '%s' "$input" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/"file_path"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' | head -1)
  fi

  # No file_path → fail closed.
  if [ -z "$file_path" ]; then
    emit_block "local-edit-gate: tool input missing file_path; cannot determine target file"
    echo "[local-edit-gate] BLOCK: tool input missing file_path" >&2
    return 2
  fi

  # If target isn't under ~/.claude/local/, gate doesn't apply.
  if ! is_under_claude_local "$file_path"; then
    return 0
  fi

  # Derive slug from basename.
  local basename slug
  basename=$(basename "$file_path")
  slug=$(filename_slug "$basename")

  if [ -z "$slug" ]; then
    emit_block "local-edit-gate: could not derive filename-slug from basename '$basename'"
    echo "[local-edit-gate] BLOCK: empty slug from basename '$basename'" >&2
    return 2
  fi

  # Look for fresh marker.
  local marker
  if marker=$(find_fresh_marker "$slug") && [ -n "$marker" ]; then
    echo "[local-edit-gate] ALLOW: $basename — marker $(basename "$marker")" >&2
    return 0
  fi

  # No fresh marker → block.
  emit_block "Edit on ~/.claude/local/$basename requires authorization. The user must invoke '/grant-local-edit $basename' before this edit can land. Markers live in ~/.claude/state/local-edit-<slug>-<timestamp>.txt and expire after 30 min. See rules/local-edit-authorization.md."
  echo "[local-edit-gate] BLOCK: $basename has no fresh authorization marker" >&2
  echo "[local-edit-gate]        run /grant-local-edit $basename to authorize this edit" >&2
  return 2
}

# ============================================================
# Self-test
# ============================================================

cmd_self_test() {
  local TMPROOT
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t local-edit-gate)
  trap 'rm -rf "$TMPROOT"' EXIT

  local PASSED=0 FAILED=0

  # Use a synthetic state dir to avoid polluting the user's real ~/.claude/state/
  export LOCAL_EDIT_STATE_DIR_OVERRIDE="$TMPROOT/state"
  mkdir -p "$LOCAL_EDIT_STATE_DIR_OVERRIDE"

  # Helper: build JSON input
  build_input() {
    local tool="$1"
    local path="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path"
  }

  # Helper: run gate with input, capture exit code
  run_with() {
    local input="$1"
    CLAUDE_TOOL_INPUT="$input" run_gate >/dev/null 2>&1
    echo $?
  }

  # ---- S1: tool != Edit/Write/MultiEdit -> allow silently
  local rc
  rc=$(run_with "$(build_input "Read" "$HOME/.claude/local/CLAUDE.md")")
  if [ "$rc" = "0" ]; then
    echo "self-test (S1) non-edit-tool-allow: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S1) non-edit-tool-allow: FAIL (rc=$rc)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S2: target outside ~/.claude/local/ -> allow silently
  rc=$(run_with "$(build_input "Edit" "$HOME/some-project/foo.txt")")
  if [ "$rc" = "0" ]; then
    echo "self-test (S2) target-outside-local-allow: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S2) target-outside-local-allow: FAIL (rc=$rc)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S3: target inside, fresh matching marker -> allow
  rm -f "$LOCAL_EDIT_STATE_DIR_OVERRIDE"/local-edit-*.txt
  echo "Filename: CLAUDE.md" > "$LOCAL_EDIT_STATE_DIR_OVERRIDE/local-edit-claude-md-test.txt"
  rc=$(run_with "$(build_input "Write" "$HOME/.claude/local/CLAUDE.md")")
  if [ "$rc" = "0" ]; then
    echo "self-test (S3) fresh-matching-marker-allow: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S3) fresh-matching-marker-allow: FAIL (rc=$rc)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S4: target inside, no marker -> block
  rm -f "$LOCAL_EDIT_STATE_DIR_OVERRIDE"/local-edit-*.txt
  rc=$(run_with "$(build_input "Edit" "$HOME/.claude/local/CLAUDE.md")")
  if [ "$rc" = "2" ]; then
    echo "self-test (S4) no-marker-block: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S4) no-marker-block: FAIL (rc=$rc, expected 2)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S5: target inside, stale marker (>30 min) -> block
  rm -f "$LOCAL_EDIT_STATE_DIR_OVERRIDE"/local-edit-*.txt
  echo "stale" > "$LOCAL_EDIT_STATE_DIR_OVERRIDE/local-edit-claude-md-stale.txt"
  touch -d "31 minutes ago" "$LOCAL_EDIT_STATE_DIR_OVERRIDE/local-edit-claude-md-stale.txt" 2>/dev/null \
    || touch -t "200001010000" "$LOCAL_EDIT_STATE_DIR_OVERRIDE/local-edit-claude-md-stale.txt"
  rc=$(run_with "$(build_input "Edit" "$HOME/.claude/local/CLAUDE.md")")
  if [ "$rc" = "2" ]; then
    echo "self-test (S5) stale-marker-block: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S5) stale-marker-block: FAIL (rc=$rc, expected 2)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S6: target inside, marker for WRONG filename -> block
  rm -f "$LOCAL_EDIT_STATE_DIR_OVERRIDE"/local-edit-*.txt
  echo "marker for accounts" > "$LOCAL_EDIT_STATE_DIR_OVERRIDE/local-edit-accounts-config-json-foo.txt"
  rc=$(run_with "$(build_input "Edit" "$HOME/.claude/local/CLAUDE.md")")
  if [ "$rc" = "2" ]; then
    echo "self-test (S6) wrong-filename-marker-block: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S6) wrong-filename-marker-block: FAIL (rc=$rc, expected 2)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S7: MultiEdit fires the same gate
  rm -f "$LOCAL_EDIT_STATE_DIR_OVERRIDE"/local-edit-*.txt
  rc=$(run_with "$(build_input "MultiEdit" "$HOME/.claude/local/personal.config.json")")
  if [ "$rc" = "2" ]; then
    echo "self-test (S7) multiedit-fires-gate: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S7) multiedit-fires-gate: FAIL (rc=$rc, expected 2)"
    FAILED=$((FAILED + 1))
  fi

  # ---- S8: malformed input (missing file_path) -> block (fail closed)
  rc=$(run_with '{"tool_name":"Edit","tool_input":{}}')
  if [ "$rc" = "2" ]; then
    echo "self-test (S8) malformed-input-fail-closed: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "self-test (S8) malformed-input-fail-closed: FAIL (rc=$rc, expected 2)"
    FAILED=$((FAILED + 1))
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)"
  if [ "$FAILED" -gt 0 ]; then exit 1; fi
  exit 0
}

# ============================================================
# Entry
# ============================================================

if [ "${SELF_TEST:-0}" = "1" ]; then
  cmd_self_test
fi

run_gate
