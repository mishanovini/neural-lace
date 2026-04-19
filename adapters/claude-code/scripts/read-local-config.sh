#!/bin/bash
# NEURAL-LACE-LOCAL-CONFIG v1 — helper for reading ~/.claude/local/*.config.json
#
# Purpose: centralize jq-based extraction of values from local, uncommitted
# config files under ~/.claude/local/. Other hooks (SessionStart account
# switcher, automation-mode gate, public-repo blocker) source this helper
# rather than each reimplementing jq fallbacks, cache logic, and dir-match
# logic.
#
# USAGE
#
# Sourced form (preferred for hooks):
#   source "$REPO/adapters/claude-code/scripts/read-local-config.sh"
#   name=$(nl_config_get personal preferred_name "User")
#   if match=$(nl_accounts_match_dir "$PWD"); then
#     echo "matched: $match"
#   fi
#
# Direct-invoke form (useful for debugging / one-off shell):
#   bash read-local-config.sh path personal
#   bash read-local-config.sh exists personal
#   bash read-local-config.sh get personal .preferred_name User
#   bash read-local-config.sh match-dir "$HOME/claude-projects/something"
#   bash read-local-config.sh public-blocked some-gh-user
#   bash read-local-config.sh automation-mode
#   bash read-local-config.sh automation-matchers
#   bash read-local-config.sh --self-test
#
# DESIGN NOTES
#
# - Every function has a safe fallback. Missing jq, missing config file, and
#   malformed JSON all degrade to the fallback rather than erroring.
# - Functions use `return`, never `exit`, so they are safe to call from an
#   already-sourced caller.
# - JSON is parsed lazily and cached in a bash associative array keyed by
#   config name within a single shell invocation.

# Only run init logic once per shell
if [ -n "${_NL_LOCAL_CONFIG_LOADED:-}" ]; then
  :
else
  _NL_LOCAL_CONFIG_LOADED=1

  # Associative array: config-name -> raw JSON content (or the literal "__MISSING__"
  # / "__MALFORMED__" for negative caching).
  declare -gA _NL_CONFIG_CACHE 2>/dev/null || true

  # Track whether we've warned about missing jq already this invocation.
  _NL_JQ_WARNED=0

  _nl_local_dir() {
    echo "$HOME/.claude/local"
  }

  _nl_have_jq() {
    if command -v jq >/dev/null 2>&1; then
      return 0
    fi
    if [ "$_NL_JQ_WARNED" = "0" ]; then
      echo "read-local-config.sh: warning — jq not installed; using fallback values" >&2
      _NL_JQ_WARNED=1
    fi
    return 1
  }

  # Load and cache the raw JSON text for a given config name.
  # Sets stdout to the JSON text on success. Returns non-zero on missing/malformed.
  _nl_load_config() {
    local name="$1"
    if [ -z "$name" ]; then
      return 1
    fi

    # Check cache
    if [ -n "${_NL_CONFIG_CACHE[$name]:-}" ]; then
      case "${_NL_CONFIG_CACHE[$name]}" in
        __MISSING__|__MALFORMED__)
          return 1
          ;;
        *)
          printf '%s' "${_NL_CONFIG_CACHE[$name]}"
          return 0
          ;;
      esac
    fi

    local path
    path="$(_nl_local_dir)/${name}.config.json"

    if [ ! -f "$path" ]; then
      _NL_CONFIG_CACHE[$name]="__MISSING__"
      return 1
    fi

    local content
    # Strip CR (Windows line endings) — config files may be user-edited on Windows,
    # and stray CRs break downstream string comparisons.
    content="$(tr -d '\r' < "$path" 2>/dev/null)"

    if [ -z "$content" ]; then
      _NL_CONFIG_CACHE[$name]="__MALFORMED__"
      echo "read-local-config.sh: warning — $path is empty" >&2
      return 1
    fi

    # Validate JSON if jq is available
    if _nl_have_jq; then
      if ! printf '%s' "$content" | jq -e . >/dev/null 2>&1; then
        _NL_CONFIG_CACHE[$name]="__MALFORMED__"
        echo "read-local-config.sh: warning — $path is not valid JSON" >&2
        return 1
      fi
    fi

    _NL_CONFIG_CACHE[$name]="$content"
    printf '%s' "$content"
    return 0
  }

  # Public: echo the absolute path to ~/.claude/local/<name>.config.json
  nl_config_path() {
    local name="$1"
    echo "$(_nl_local_dir)/${name}.config.json"
  }

  # Public: 0 if config file exists, 1 otherwise
  nl_config_exists() {
    local name="$1"
    [ -f "$(nl_config_path "$name")" ]
  }

  # Public: read a jq-path from a config, with optional fallback
  # Usage: nl_config_get <name> <jq-path> [fallback]
  # Example: nl_config_get personal .preferred_name "User"
  # Accepts jq paths with or without a leading dot — normalizes either way.
  nl_config_get() {
    local name="$1"
    local jq_path="$2"
    local fallback="${3:-}"

    if [ -z "$name" ] || [ -z "$jq_path" ]; then
      echo "$fallback"
      return 0
    fi

    # Normalize: ensure leading dot
    case "$jq_path" in
      .*) ;;
      *) jq_path=".$jq_path" ;;
    esac

    if ! _nl_have_jq; then
      echo "$fallback"
      return 0
    fi

    local content
    if ! content="$(_nl_load_config "$name")"; then
      echo "$fallback"
      return 0
    fi

    local result
    # tr -d '\r' defends against jq on Windows (Git Bash) emitting CRLF output.
    result="$(printf '%s' "$content" | jq -r "$jq_path // empty" 2>/dev/null | tr -d '\r')"

    if [ -z "$result" ] || [ "$result" = "null" ]; then
      echo "$fallback"
      return 0
    fi

    echo "$result"
    return 0
  }

  # Helper: expand leading ~ to $HOME in a path string
  _nl_expand_tilde() {
    local p="$1"
    case "$p" in
      "~") echo "$HOME" ;;
      # Escape the tilde in the prefix-strip pattern; unescaped, bash tries
      # to perform its own tilde expansion on the pattern itself, which fails.
      "~/"*) echo "$HOME/${p#\~/}" ;;
      *) echo "$p" ;;
    esac
  }

  # Helper: does $dir start with $prefix? (after tilde expansion of prefix)
  _nl_dir_starts_with() {
    local dir="$1"
    local prefix="$2"
    prefix="$(_nl_expand_tilde "$prefix")"
    # Strip trailing slashes from prefix
    prefix="${prefix%/}"
    case "$dir" in
      "$prefix"|"$prefix"/*) return 0 ;;
      *) return 1 ;;
    esac
  }

  # Public: match a directory path against accounts.config.json triggers.
  # Prints: "<type> <gh-user>" on match (e.g., "work alice-at-acme").
  # Prints nothing and returns 1 on no-match.
  # Checks work accounts first, then personal; first match wins.
  nl_accounts_match_dir() {
    local dir="$1"
    if [ -z "$dir" ]; then
      return 1
    fi

    if ! _nl_have_jq; then
      return 1
    fi

    local content
    if ! content="$(_nl_load_config accounts)"; then
      return 1
    fi

    # Iterate work accounts first
    local account_types=("work" "personal")
    local atype gh_user triggers trigger
    for atype in "${account_types[@]}"; do
      # Get the number of accounts of this type
      local count
      count="$(printf '%s' "$content" | jq -r ".${atype} | length // 0" 2>/dev/null | tr -d '\r')"
      if [ -z "$count" ] || [ "$count" = "null" ]; then
        continue
      fi

      local i
      for ((i = 0; i < count; i++)); do
        gh_user="$(printf '%s' "$content" | jq -r ".${atype}[$i].gh_user // empty" 2>/dev/null | tr -d '\r')"
        if [ -z "$gh_user" ]; then
          continue
        fi

        # Get dir_triggers as newline-separated list
        triggers="$(printf '%s' "$content" | jq -r ".${atype}[$i].dir_triggers[]? // empty" 2>/dev/null | tr -d '\r')"
        if [ -z "$triggers" ]; then
          continue
        fi

        while IFS= read -r trigger; do
          [ -z "$trigger" ] && continue
          if _nl_dir_starts_with "$dir" "$trigger"; then
            echo "$atype $gh_user"
            return 0
          fi
        done <<< "$triggers"
      done
    done

    return 1
  }

  # Public: check whether a given gh-user has public_blocked=true in accounts.config.json.
  # Returns 0 if blocked, 1 otherwise (including missing config / missing jq).
  nl_account_public_blocked() {
    local target_user="$1"
    if [ -z "$target_user" ]; then
      return 1
    fi

    if ! _nl_have_jq; then
      return 1
    fi

    local content
    if ! content="$(_nl_load_config accounts)"; then
      return 1
    fi

    local result
    result="$(printf '%s' "$content" | jq -r --arg u "$target_user" '
      [.work[]?, .personal[]?]
      | map(select(.gh_user == $u))
      | .[0].public_blocked // false
    ' 2>/dev/null | tr -d '\r')"

    if [ "$result" = "true" ]; then
      return 0
    fi
    return 1
  }

  # Public: print automation mode (default "review-before-deploy" if missing)
  nl_automation_mode() {
    local mode
    mode="$(nl_config_get automation-mode mode "review-before-deploy")"
    echo "$mode"
  }

  # Public: print one automation deploy matcher per line.
  # Safe default list if config file missing.
  nl_automation_matchers() {
    if ! _nl_have_jq || ! _nl_load_config automation-mode >/dev/null 2>&1; then
      # Safe defaults
      printf '%s\n' \
        'git push' \
        'vercel deploy' \
        'npx vercel' \
        'supabase db push' \
        'npx supabase db push' \
        'gh pr merge'
      return 0
    fi

    local content
    content="$(_nl_load_config automation-mode)" || {
      printf '%s\n' \
        'git push' \
        'vercel deploy' \
        'npx vercel' \
        'supabase db push' \
        'npx supabase db push' \
        'gh pr merge'
      return 0
    }

    local matchers
    matchers="$(printf '%s' "$content" | jq -r '.deploy_matchers[]? // empty' 2>/dev/null | tr -d '\r')"

    if [ -z "$matchers" ]; then
      printf '%s\n' \
        'git push' \
        'vercel deploy' \
        'npx vercel' \
        'supabase db push' \
        'npx supabase db push' \
        'gh pr merge'
      return 0
    fi

    echo "$matchers"
  }
fi

# ============================================================
# Self-test
# ============================================================
_nl_self_test() {
  local tmp_home
  tmp_home="$(mktemp -d 2>/dev/null || mktemp -d -t 'nl-self-test')"
  if [ -z "$tmp_home" ] || [ ! -d "$tmp_home" ]; then
    echo "self-test: FAIL — could not create tmp dir" >&2
    return 1
  fi

  # Snapshot real HOME; swap to tmp for isolation
  local real_home="$HOME"
  export HOME="$tmp_home"
  mkdir -p "$tmp_home/.claude/local"

  # Reset cache for the test shell
  unset _NL_CONFIG_CACHE
  declare -gA _NL_CONFIG_CACHE

  local failed=0
  local fail_msg=""

  _fail() {
    failed=1
    fail_msg="$1"
  }

  # --- Test 1: missing config returns fallback ---
  local got
  got="$(nl_config_get personal preferred_name "DefaultUser")"
  if [ "$got" != "DefaultUser" ]; then
    _fail "missing-config fallback: expected 'DefaultUser', got '$got'"
  fi

  if nl_config_exists personal; then
    _fail "missing-config exists: should return 1 for missing file"
  fi

  # --- Test 2: write a valid personal config, read it back ---
  cat > "$tmp_home/.claude/local/personal.config.json" <<'JSON'
{
  "preferred_name": "SampleName",
  "voice": {
    "tone": "direct"
  }
}
JSON

  # Reset cache so the new file is re-read
  unset _NL_CONFIG_CACHE
  declare -gA _NL_CONFIG_CACHE

  if ! nl_config_exists personal; then
    _fail "exists after write: should return 0"
  fi

  got="$(nl_config_get personal preferred_name "FallbackUser")"
  if [ "$got" != "SampleName" ]; then
    _fail "read preferred_name: expected 'SampleName', got '$got'"
  fi

  got="$(nl_config_get personal .voice.tone "unknown")"
  if [ "$got" != "direct" ]; then
    _fail "read nested voice.tone: expected 'direct', got '$got'"
  fi

  got="$(nl_config_get personal .nonexistent "fb")"
  if [ "$got" != "fb" ]; then
    _fail "missing-key fallback: expected 'fb', got '$got'"
  fi

  # --- Test 3: accounts config with dir matching ---
  cat > "$tmp_home/.claude/local/accounts.config.json" <<JSON
{
  "work": [
    {
      "gh_user": "test-work-user",
      "dir_triggers": ["$tmp_home/work-projects", "~/work-alt"],
      "public_blocked": true
    }
  ],
  "personal": [
    {
      "gh_user": "test-personal-user",
      "dir_triggers": ["$tmp_home/personal-projects"],
      "public_blocked": false
    }
  ]
}
JSON

  unset _NL_CONFIG_CACHE
  declare -gA _NL_CONFIG_CACHE

  # Work match (direct path)
  got="$(nl_accounts_match_dir "$tmp_home/work-projects/some-repo")"
  if [ "$got" != "work test-work-user" ]; then
    _fail "work dir match: expected 'work test-work-user', got '$got'"
  fi

  # Personal match
  got="$(nl_accounts_match_dir "$tmp_home/personal-projects/another")"
  if [ "$got" != "personal test-personal-user" ]; then
    _fail "personal dir match: expected 'personal test-personal-user', got '$got'"
  fi

  # No match
  if got="$(nl_accounts_match_dir "/tmp/nowhere")" && [ -n "$got" ]; then
    _fail "no-match dir: should return empty, got '$got'"
  fi

  # Tilde expansion test (HOME is tmp_home)
  mkdir -p "$tmp_home/work-alt"
  got="$(nl_accounts_match_dir "$tmp_home/work-alt/repo")"
  if [ "$got" != "work test-work-user" ]; then
    _fail "tilde expansion dir match: expected 'work test-work-user', got '$got'"
  fi

  # public_blocked checks
  if ! nl_account_public_blocked test-work-user; then
    _fail "public-blocked for work user: should return 0"
  fi

  if nl_account_public_blocked test-personal-user; then
    _fail "public-blocked for personal user: should return 1 (not blocked)"
  fi

  if nl_account_public_blocked nonexistent-user; then
    _fail "public-blocked for missing user: should return 1"
  fi

  # --- Test 4: automation mode ---
  # Missing file -> default
  got="$(nl_automation_mode)"
  if [ "$got" != "review-before-deploy" ]; then
    _fail "automation-mode default: expected 'review-before-deploy', got '$got'"
  fi

  # Write automation-mode config
  cat > "$tmp_home/.claude/local/automation-mode.config.json" <<'JSON'
{
  "mode": "auto-deploy",
  "deploy_matchers": [
    "git push",
    "vercel deploy"
  ]
}
JSON

  unset _NL_CONFIG_CACHE
  declare -gA _NL_CONFIG_CACHE

  got="$(nl_automation_mode)"
  if [ "$got" != "auto-deploy" ]; then
    _fail "automation-mode explicit: expected 'auto-deploy', got '$got'"
  fi

  got="$(nl_automation_matchers | tr '\n' '|')"
  if [ "$got" != "git push|vercel deploy|" ]; then
    _fail "automation-matchers: expected 'git push|vercel deploy|', got '$got'"
  fi

  # --- Test 5: malformed JSON gracefully falls back ---
  echo "not valid json {{{" > "$tmp_home/.claude/local/broken.config.json"
  unset _NL_CONFIG_CACHE
  declare -gA _NL_CONFIG_CACHE

  # Suppress the expected stderr warning for cleaner output
  got="$(nl_config_get broken .anything "fallback_val" 2>/dev/null)"
  if [ "$got" != "fallback_val" ]; then
    _fail "malformed-json fallback: expected 'fallback_val', got '$got'"
  fi

  # --- Test 6: nl_config_path does not require existence ---
  got="$(nl_config_path somename)"
  if [ "$got" != "$tmp_home/.claude/local/somename.config.json" ]; then
    _fail "nl_config_path: expected tmp path, got '$got'"
  fi

  # Restore HOME
  export HOME="$real_home"

  # Cleanup
  rm -rf "$tmp_home" 2>/dev/null

  if [ "$failed" = "1" ]; then
    echo "self-test: FAIL — $fail_msg" >&2
    return 1
  fi

  echo "self-test: OK"
  return 0
}

# ============================================================
# CLI dispatch (only when invoked directly, not sourced)
# ============================================================
# Detect whether we're being sourced or executed directly.
if [ "${BASH_SOURCE[0]:-}" = "$0" ] || [ -z "${BASH_SOURCE[0]:-}" ]; then
  case "${1:-}" in
    --self-test|self-test)
      _nl_self_test
      exit $?
      ;;
    path)
      nl_config_path "$2"
      ;;
    exists)
      nl_config_exists "$2" && echo "yes" || echo "no"
      ;;
    get)
      nl_config_get "$2" "$3" "${4:-}"
      ;;
    match-dir)
      nl_accounts_match_dir "${2:-$PWD}" || {
        echo "no-match" >&2
        exit 1
      }
      ;;
    public-blocked)
      if nl_account_public_blocked "$2"; then
        echo "blocked"
      else
        echo "not-blocked"
        exit 1
      fi
      ;;
    automation-mode)
      nl_automation_mode
      ;;
    automation-matchers)
      nl_automation_matchers
      ;;
    ""|help|--help|-h)
      cat <<EOF
read-local-config.sh — helper for ~/.claude/local/*.config.json

Commands:
  path <name>                       Print config file path
  exists <name>                     Print 'yes' or 'no'
  get <name> <jq-path> [fallback]   Print value or fallback
  match-dir [dir]                   Print '<type> <gh-user>' or exit 1
  public-blocked <gh-user>          Print 'blocked' or 'not-blocked' (exit 1)
  automation-mode                   Print mode (default: review-before-deploy)
  automation-matchers               Print matchers, one per line
  --self-test                       Run self-test suite
EOF
      ;;
    *)
      echo "read-local-config.sh: unknown command '$1'" >&2
      exit 2
      ;;
  esac
fi
