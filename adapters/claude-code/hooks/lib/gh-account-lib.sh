#!/usr/bin/env bash
# gh-account-lib.sh — shared library: owner->account resolution for the two
# gh dual-account mechanisms in this repo (GH-AUTH-AUTOSWITCH-WORKORG-01).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Two hooks need the identical "given a GitHub owner login, which gh CLI
# account should be active" resolution:
#   1. gh-account-blindness-hint.sh (PostToolUse, L1) — REACTIVE: advises
#      `gh auth switch -u <owner>` after a 404/403 already happened.
#   2. gh-account-autoswitch.sh (PreToolUse) — PROACTIVE: runs the switch
#      BEFORE the command executes, so the 404/403 never happens at all.
#
# Extracting the shared owner/account/config logic here means #2 does not
# duplicate #1's already-reviewed parsing (owner extraction, accounts.config
# lookup, active-account detection) — it sources this file instead. Both
# hooks source this lib and keep their own event-specific logic (L1's
# not-found-signature scan + advisory text; PreToolUse's pre-execution
# switch + signal-ledger emit).
#
# CONFIG SHAPE (unchanged from the original gh-account-blindness-hint.sh
# header; canonical example: examples/accounts.config.example.json):
#   {
#     "work":     [ { "gh_user": "<login>", "owners": ["<org-or-owner>", ...]? }, ... ],
#     "personal": [ { "gh_user": "<login>", "owners": [...]? }, ... ]
#   }
#   - gh_user is the gh CLI account login. owner==gh_user is the load-bearing
#     mapping: a repo owned by <X> needs the account whose gh_user is <X>.
#   - owners[] is OPTIONAL: additional GitHub owners/orgs that account can
#     access (e.g. an org the personal account is a member of).
#   - Legacy `user` is accepted as a fallback for `gh_user`. `work`/`personal`
#     may each be an object or an array of objects.
#
# HYGIENE: never hardcode account names/logins in this file. Everything is
# read from ~/.claude/local/accounts.config.json (gitignored, per-machine)
# at runtime, exactly as the original hook did.
#
# ENV OVERRIDES (self-test sandboxing; same names as the original hook so
# existing gh-account-blindness-hint.sh self-tests keep working unmodified):
#   GHBLIND_ACCOUNTS  - path to accounts.config.json (else default location)
#   GHBLIND_ACTIVE    - active gh account login (else `gh auth status`)

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [ -n "${_GH_ACCOUNT_LIB_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_GH_ACCOUNT_LIB_SOURCED=1

# Path to accounts.config.json. GHBLIND_ACCOUNTS wins (self-test).
gh_accounts_path() {
  printf '%s' "${GHBLIND_ACCOUNTS:-$HOME/.claude/local/accounts.config.json}"
}

# Load + CR-strip + JSON-validate accounts config. Echoes content; rc!=0 on
# missing/empty/malformed/no-jq.
gh_load_accounts() {
  command -v jq >/dev/null 2>&1 || return 1
  local path content
  path="$(gh_accounts_path)"
  [ -f "$path" ] || return 1
  content="$(tr -d '\r' < "$path" 2>/dev/null)"
  [ -n "$content" ] || return 1
  printf '%s' "$content" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s' "$content"
}

# Given an owner, echo the gh_user account that should be active for it, or
# empty if owner is not known to the config. Mapping:
#   - owner == some entry's gh_user (or legacy `user`)  -> that gh_user
#   - owner listed in some entry's owners[]             -> that entry's gh_user
# Case-insensitive comparison (GitHub logins are case-insensitive).
gh_account_for_owner() {
  local owner="$1" content
  content="$(gh_load_accounts)" || { printf ''; return 0; }
  printf '%s' "$content" | jq -r --arg owner "$owner" '
    [ (.work // []), (.personal // []) ]
    | map(if type=="array" then . else [.] end) | add
    | map(select(type=="object"))
    | map({ acct: (.gh_user // .user // empty),
            owns: ([ (.gh_user // .user // empty) ] + (.owners // [])) })
    | map(select(.acct != null and .acct != ""))
    | map(select( any(.owns[]; ascii_downcase == ($owner|ascii_downcase)) ))
    | (.[0].acct // empty)
  ' 2>/dev/null | tr -d '\r'
}

# List "<type> <gh_user>" lines for every account in the config.
gh_all_accounts() {
  local content
  content="$(gh_load_accounts)" || return 1
  printf '%s' "$content" | jq -r '
    [ {t:"work", a:(.work // [])}, {t:"personal", a:(.personal // [])} ]
    | map(.t as $t | (if (.a|type)=="array" then .a else [.a] end) | map({t:$t, e:.}))
    | add // []
    | map(select(.e|type=="object"))
    | map("\(.t) \(.e.gh_user // .e.user // "?")")
    | .[]
  ' 2>/dev/null | tr -d '\r'
}

# Currently-active gh account login. GHBLIND_ACTIVE wins (self-test).
gh_active_account() {
  if [ -n "${GHBLIND_ACTIVE:-}" ]; then printf '%s' "$GHBLIND_ACTIVE"; return 0; fi
  command -v gh >/dev/null 2>&1 || { printf ''; return 0; }
  # `gh auth status` prints the account login one line ABOVE "Active account: true".
  gh auth status 2>&1 | awk '
    /Logged in to .* account/ { line=$0; sub(/.* account[[:space:]]+/,"",line); sub(/[[:space:]].*/,"",line); acct=line }
    /Active account: true/    { print acct; exit }
  ' | tr -d '\r'
}

# Case-insensitive string equality helper.
gh_ci_eq() {
  [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ]
}

# ============================================================
# --self-test (library-level: owner resolution only; the two callers each
# keep their own event-specific self-tests)
# ============================================================
_gh_account_lib_self_test() {
  local pass=0 fail=0 tmp got
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ghlib)"
  local cfg="$tmp/accounts.config.json"
  cat > "$cfg" <<'JSON'
{
  "work":     [ { "gh_user": "acct-work",     "owners": ["work-org"] } ],
  "personal": [ { "gh_user": "acct-personal" } ]
}
JSON

  got="$(GHBLIND_ACCOUNTS="$cfg" gh_account_for_owner "acct-personal")"
  if [ "$got" = "acct-personal" ]; then echo "  L1 direct owner match: PASS"; pass=$((pass+1)); else echo "  L1 direct owner match: FAIL (got: $got)"; fail=$((fail+1)); fi

  got="$(GHBLIND_ACCOUNTS="$cfg" gh_account_for_owner "work-org")"
  if [ "$got" = "acct-work" ]; then echo "  L2 owners[] match: PASS"; pass=$((pass+1)); else echo "  L2 owners[] match: FAIL (got: $got)"; fail=$((fail+1)); fi

  got="$(GHBLIND_ACCOUNTS="$cfg" gh_account_for_owner "unknown-org")"
  if [ -z "$got" ]; then echo "  L3 unknown owner -> empty: PASS"; pass=$((pass+1)); else echo "  L3 unknown owner -> empty: FAIL (got: $got)"; fail=$((fail+1)); fi

  if GHBLIND_ACTIVE="acct-work" gh_ci_eq "ACCT-work" "acct-Work"; then echo "  L4 gh_ci_eq case-insensitive: PASS"; pass=$((pass+1)); else echo "  L4 gh_ci_eq case-insensitive: FAIL"; fail=$((fail+1)); fi

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[gh-account-lib self-test] $pass passed, $fail failed"
  return "$fail"
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then
  _gh_account_lib_self_test
  exit $?
fi
