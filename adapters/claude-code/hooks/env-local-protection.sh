#!/bin/bash
# env-local-protection.sh
#
# PreToolUse Bash hook that protects .env.local files from being clobbered
# by agent commands that redirect, truncate, copy, or move over them.
#
# Why this exists:
#   A Claude Desktop session running with cwd pointing at the user's
#   main project checkout (not an isolated worktree) issued
#   `cat > .env.local <<EOF ... EOF` writing a 5-line placeholder
#   stub, wiping the user's real production secrets. The existing
#   PreToolUse Edit|Write hook that denies edits to .env.local does
#   NOT fire on Bash, so the heredoc bypassed every protection.
#
# What this hook does (in order):
#   1. Parses the proposed Bash command from CLAUDE_TOOL_INPUT.
#   2. Detects shapes that would write to / truncate / replace .env.local:
#        - `> .env.local`          (truncating redirect)
#        - `>> .env.local`         (append — allowed; documented as such)
#        - `tee .env.local`        (without -a → truncating)
#        - `cp <any> .env.local`   (overwrite copy)
#        - `mv <any> .env.local`   (replace)
#        - `dd ... of=.env.local`  (rare but destructive)
#        - heredoc forms: `cat > .env.local <<EOF`, `cat > .env.local <<-EOF`
#   3. For each detected target, locates the existing file relative to
#      the agent's PWD (resolves relative + absolute paths).
#   4. If the existing file appears to hold REAL secrets (length > 300
#      bytes AND contains at least one heuristic real-key pattern), the
#      hook auto-backs it up to ~/.claude/backups/env-local/ and BLOCKS
#      the command with a stderr message explaining the recovery path.
#   5. If the existing file looks placeholder-shaped or is missing,
#      the hook ALWAYS backs up (cheap) and then ALLOWS.
#   6. If no .env.local target is detected, exits 0 silently.
#
# The auto-backup runs BEFORE the block so even an authorized overwrite
# (e.g., user-driven via a follow-up `OVERWRITE=1`-prefixed command) has
# a fresh recovery point next to it.
#
# Override path:
#   Set the env var ENV_LOCAL_OVERWRITE_OK=1 in the command itself, e.g.:
#       ENV_LOCAL_OVERWRITE_OK=1 cat > .env.local <<EOF ... EOF
#   This signals deliberate intent. The hook still backs up first.
#
# Self-test:
#   bash env-local-protection.sh --self-test
#
# Exit codes:
#   0 — command is allowed (silent or with backup notice)
#   1 — command is blocked (stderr explains why + cites backup path)

set -e

# ============================================================
# Self-test sentinel
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST=1
fi

BACKUP_ROOT="${HOME}/.claude/backups/env-local"

# ============================================================
# Helpers
# ============================================================

load_command() {
  # Returns the proposed Bash command string, or empty.
  local input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$input" ]]; then
    if [[ ! -t 0 ]]; then
      input=$(cat 2>/dev/null || echo "")
    fi
  fi
  # Try jq first (canonical .tool_input.command, fallback .command)
  local cmd
  cmd=$(echo "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || echo "")
  printf '%s' "$cmd"
}

slugify_path() {
  # Convert an absolute or relative path to a flat slug safe for filenames.
  local p="$1"
  echo "$p" | sed -E 's|^/+||; s|[/:\\ ]+|-|g; s|--+|-|g; s|^-||; s|-$||'
}

# Heuristic: does an existing .env.local file look like it holds real secrets?
# Criteria (any one trips it):
#   - file size > 300 bytes
#   - contains a recognizable real-key prefix (sk-, re_, tr_dev_, eyJ for JWT, SG.)
#   - has more than 8 VAR=value lines whose values are not obvious placeholders
file_has_real_secrets() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local size
  size=$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]')
  size="${size:-0}"
  if [[ "$size" -gt 300 ]]; then
    return 0
  fi
  # Pattern check — known real-key prefixes
  if grep -qE '(sk-[A-Za-z0-9_-]{15,}|re_[A-Za-z0-9_-]{15,}|tr_(dev|prod)_[A-Za-z0-9_-]{10,}|SG\.[A-Za-z0-9_-]{15,}|eyJ[A-Za-z0-9._-]{40,})' "$path" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Backup the file. Returns the backup path on stdout (empty if nothing to back up).
backup_env_local() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  mkdir -p "$BACKUP_ROOT" 2>/dev/null || return 1
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  local abs
  abs=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")
  local slug
  slug=$(slugify_path "$abs")
  local dest="${BACKUP_ROOT}/${slug}-${ts}.bak"
  cp -p "$path" "$dest" 2>/dev/null || return 1
  printf '%s' "$dest"
}

# Extract the LAST `.env.local`-shaped target from a command. The heuristic
# scans for these shapes (left-to-right) and returns the resolved path:
#   >  .env.local                     → .env.local
#   >  /abs/path/.env.local           → /abs/path/.env.local
#   tee .env.local                    → .env.local (must NOT have -a)
#   cp <src> .env.local               → .env.local
#   mv <src> .env.local               → .env.local
#   dd ... of=.env.local              → .env.local
# Append shapes (>>, tee -a) are returned as "APPEND:<path>" — these are
# considered safe-by-default but still trigger a backup.
extract_target() {
  local cmd="$1"
  local out=""

  # Truncating redirects: > path or >| path (NOT >>)
  # Capture last `>` occurrence not preceded by another > or |
  # We allow optional whitespace between > and path.
  local trunc
  trunc=$(echo "$cmd" | grep -oE '[^>|][[:space:]]*>[[:space:]]*[^[:space:]>|&;]*\.env\.local[^[:space:]]*' | tail -1 || true)
  if [[ -n "$trunc" ]]; then
    out=$(echo "$trunc" | grep -oE '[^[:space:]>|&;]*\.env\.local[^[:space:]]*' | tail -1)
    [[ -n "$out" ]] && { printf 'TRUNC:%s' "$out"; return 0; }
  fi

  # Heredoc-with-redirect: `cat > .env.local <<EOF` or `cat >> .env.local <<EOF`
  # Already covered by trunc above for > case; explicit pattern for clarity.
  local heredoc
  heredoc=$(echo "$cmd" | grep -oE '(cat|tee|printf)[[:space:]]+>[[:space:]]*[^[:space:]&;|]*\.env\.local' | tail -1 || true)
  if [[ -n "$heredoc" ]]; then
    out=$(echo "$heredoc" | grep -oE '[^[:space:]>]*\.env\.local')
    [[ -n "$out" ]] && { printf 'TRUNC:%s' "$out"; return 0; }
  fi

  # tee target (no -a flag = truncating)
  local tee_match
  tee_match=$(echo "$cmd" | grep -oE 'tee[[:space:]]+[^[:space:]&;|]*\.env\.local' | tail -1 || true)
  if [[ -n "$tee_match" ]]; then
    # Confirm -a not present in this tee invocation
    if ! echo "$cmd" | grep -qE 'tee[[:space:]]+(-[^[:space:]]*a[^[:space:]]*[[:space:]]+)?[^[:space:]&;|]*\.env\.local' || \
       ! echo "$cmd" | grep -qE 'tee[[:space:]]+-[^[:space:]]*a'; then
      out=$(echo "$tee_match" | grep -oE '[^[:space:]]*\.env\.local')
      [[ -n "$out" ]] && { printf 'TRUNC:%s' "$out"; return 0; }
    fi
  fi

  # cp/mv with .env.local as destination (LAST argument)
  local cp_mv
  cp_mv=$(echo "$cmd" | grep -oE '(cp|mv|install)[[:space:]]+[^&;|]*\.env\.local[^[:space:]&;|]*' | tail -1 || true)
  if [[ -n "$cp_mv" ]]; then
    # Verify .env.local is the LAST token (destination), not just somewhere
    local last_token
    last_token=$(echo "$cp_mv" | awk '{print $NF}')
    if echo "$last_token" | grep -qE '\.env\.local$'; then
      printf 'TRUNC:%s' "$last_token"
      return 0
    fi
  fi

  # dd of=.env.local
  local dd_match
  dd_match=$(echo "$cmd" | grep -oE 'of=[^[:space:]&;|]*\.env\.local[^[:space:]]*' | tail -1 || true)
  if [[ -n "$dd_match" ]]; then
    out=$(echo "$dd_match" | sed 's|^of=||')
    [[ -n "$out" ]] && { printf 'TRUNC:%s' "$out"; return 0; }
  fi

  # Append shapes (informational only — still backed up but allowed silently)
  local append
  append=$(echo "$cmd" | grep -oE '>>[[:space:]]*[^[:space:]>|&;]*\.env\.local[^[:space:]]*' | tail -1 || true)
  if [[ -n "$append" ]]; then
    out=$(echo "$append" | grep -oE '[^[:space:]>]*\.env\.local[^[:space:]]*' | tail -1)
    [[ -n "$out" ]] && { printf 'APPEND:%s' "$out"; return 0; }
  fi

  return 0
}

resolve_path() {
  # Given a target token (may be relative), resolve to an absolute path
  # rooted at PWD if not already absolute.
  local p="$1"
  case "$p" in
    /*)         printf '%s' "$p" ;;
    [A-Za-z]:*) printf '%s' "$p" ;; # Windows absolute (C:\... or C:/...)
    *)          printf '%s/%s' "$PWD" "$p" ;;
  esac
}

# ============================================================
# Main flow
# ============================================================

main_flow() {
  local cmd
  cmd=$(load_command)

  # Nothing to do if no command parsed
  [[ -z "$cmd" ]] && return 0

  # Override sentinel — honor user-authorized overwrites
  if echo "$cmd" | grep -qE '\bENV_LOCAL_OVERWRITE_OK=1\b'; then
    # Still backup if a target is detectable
    local result
    result=$(extract_target "$cmd")
    if [[ -n "$result" ]]; then
      local target="${result#*:}"
      local abs
      abs=$(resolve_path "$target")
      if [[ -f "$abs" ]]; then
        local b
        b=$(backup_env_local "$abs" || true)
        [[ -n "$b" ]] && echo "[env-local-protection] backed up to $b before authorized overwrite" >&2
      fi
    fi
    return 0
  fi

  local result
  result=$(extract_target "$cmd")

  # No .env.local target → silent pass
  [[ -z "$result" ]] && return 0

  local mode="${result%%:*}"
  local target="${result#*:}"
  local abs
  abs=$(resolve_path "$target")

  # APPEND mode: always backup, never block
  if [[ "$mode" == "APPEND" ]]; then
    if [[ -f "$abs" ]]; then
      local b
      b=$(backup_env_local "$abs" || true)
      [[ -n "$b" ]] && echo "[env-local-protection] backed up to $b before append to $abs" >&2
    fi
    return 0
  fi

  # TRUNC mode: backup first, then decide
  local backup_path=""
  if [[ -f "$abs" ]]; then
    backup_path=$(backup_env_local "$abs" || true)
  fi

  # If no existing file OR file doesn't look like real secrets → allow
  if [[ ! -f "$abs" ]] || ! file_has_real_secrets "$abs"; then
    [[ -n "$backup_path" ]] && echo "[env-local-protection] backed up to $backup_path before overwrite of $abs (file did not appear to hold real secrets)" >&2
    return 0
  fi

  # Existing file has real secrets — BLOCK
  cat >&2 <<EOF
BLOCKED: refusing to overwrite $abs

This .env.local file appears to contain real secrets (size > 300 bytes
and/or matches real-key heuristics: sk-/re_/tr_/SG./JWT prefixes).

The command was about to truncate or replace it:
    $cmd

A backup was saved at:
    ${backup_path:-(backup failed — check ~/.claude/backups/env-local/)}

If this overwrite is intentional (e.g., rotating credentials, satisfying
a build-time placeholder check in a sandboxed dir), re-issue the command
with the override sentinel:

    ENV_LOCAL_OVERWRITE_OK=1 <your command>

If you reached this gate by accident — your cwd may be the main checkout
when you intended to be in a worktree. Run \`pwd\` and \`git worktree list\`
to confirm. The user's primary project checkout MUST NOT be overwritten
with placeholder values; only worktrees with their own isolated
.env.local should receive build-time stubs.
EOF
  return 1
}

# ============================================================
# Self-test
# ============================================================

run_self_tests() {
  local PASS=0 FAIL=0
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  # Helper: invoke hook with mock CLAUDE_TOOL_INPUT
  run_case() {
    local label="$1" expect_exit="$2" cmd_json="$3" prep="$4"
    eval "$prep" 2>/dev/null || true
    local exit_code=0
    CLAUDE_TOOL_INPUT="$cmd_json" bash "$0" >/tmp/env_local_self_test_out 2>/tmp/env_local_self_test_err </dev/null || exit_code=$?
    if [[ "$exit_code" == "$expect_exit" ]]; then
      echo "  PASS: $label"
      PASS=$((PASS+1))
    else
      echo "  FAIL: $label (expected exit $expect_exit, got $exit_code)"
      echo "    stderr: $(cat /tmp/env_local_self_test_err 2>/dev/null | head -3)"
      FAIL=$((FAIL+1))
    fi
  }

  # 1. Empty input → pass silently
  run_case "empty command passes" 0 '{}' 'true'

  # 2. Unrelated command → pass silently
  run_case "unrelated bash command passes" 0 '{"tool_input":{"command":"ls -la"}}' 'true'

  # 3. Command with .env.local in append mode + file with real-looking secrets → allow + backup
  cat > "$tmpdir/real_env" <<'EOF'
NEXT_PUBLIC_SUPABASE_URL=https://abcdefghij.supabase.co
RESEND_API_KEY=re_aBcDeFgHiJkLmNoPqRsTuV
TRIGGER_SECRET_KEY=tr_dev_actually_real_secret_here_with_chars
FAKE_API_KEY=sk-fake-FORTESTONLYxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
  # Use a unique filename to avoid colliding with real env detection
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  run_case "truncate-write blocked when file has real secrets" 1 \
    "{\"tool_input\":{\"command\":\"cat > $tmpdir/.env.local <<EOF\\nNEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co\\nNEXT_PUBLIC_SUPABASE_ANON_KEY=test_anon_key_placeholder_for_build\\nEOF\"}}" \
    'true'

  # 4. Same shape but with override sentinel → allow + backup
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  run_case "override sentinel allows overwrite" 0 \
    "{\"tool_input\":{\"command\":\"ENV_LOCAL_OVERWRITE_OK=1 cat > $tmpdir/.env.local <<EOF\\nplaceholder\\nEOF\"}}" \
    'true'

  # 5. Truncate-write when file is small/placeholder → allow
  echo "FOO=bar" > "$tmpdir/.env.local"
  run_case "truncate-write allowed when file lacks real secrets" 0 \
    "{\"tool_input\":{\"command\":\"echo 'X=Y' > $tmpdir/.env.local\"}}" \
    'true'

  # 6. Truncate-write when file does not exist → allow
  rm -f "$tmpdir/.env.local"
  run_case "truncate-write allowed when file missing" 0 \
    "{\"tool_input\":{\"command\":\"cat > $tmpdir/.env.local <<EOF\\nfoo\\nEOF\"}}" \
    'true'

  # 7. cp <src> .env.local when destination has real secrets → blocked
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  echo "stub" > "$tmpdir/source.txt"
  run_case "cp to .env.local blocked when destination has secrets" 1 \
    "{\"tool_input\":{\"command\":\"cp $tmpdir/source.txt $tmpdir/.env.local\"}}" \
    'true'

  # 8. mv <src> .env.local when destination has real secrets → blocked
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  echo "stub" > "$tmpdir/source.txt"
  run_case "mv to .env.local blocked when destination has secrets" 1 \
    "{\"tool_input\":{\"command\":\"mv $tmpdir/source.txt $tmpdir/.env.local\"}}" \
    'true'

  # 9. Append (>>) to .env.local → always allow even with real secrets
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  run_case "append (>>) allowed even with real secrets" 0 \
    "{\"tool_input\":{\"command\":\"echo 'NEW=value' >> $tmpdir/.env.local\"}}" \
    'true'

  # 10. dd of=.env.local → blocked when file has secrets
  cp "$tmpdir/real_env" "$tmpdir/.env.local"
  run_case "dd of=.env.local blocked when file has secrets" 1 \
    "{\"tool_input\":{\"command\":\"dd if=/dev/zero of=$tmpdir/.env.local bs=1 count=10\"}}" \
    'true'

  echo ""
  echo "Self-test: $PASS passed, $FAIL failed"
  [[ "$FAIL" == 0 ]]
}

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  run_self_tests
  exit $?
fi

main_flow
exit $?
