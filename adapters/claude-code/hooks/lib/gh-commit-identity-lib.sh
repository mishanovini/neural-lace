#!/usr/bin/env bash
# gh-commit-identity-lib.sh — shared library: resolve the EXPECTED git commit
# identity (email, and effective name) for a repo, so a gate can distinguish
# a legitimate commit identity from an accidental one.
#
# ============================================================
# WHY THIS EXISTS (GH-COMMIT-IDENTITY-01, operator directive 2026-09-27)
# ============================================================
#
# Golden scenario: a Claude Code session's "user email" context value (handed
# to every dispatched agent "for authorship") is NOT the identity a commit
# should carry — the commit should carry the identity of the GH ACCOUNT
# LOGGED IN for the repo being committed to. On 2026-09-21 a fixer subagent
# committed with a mismatched author email; the repo's own git config was
# already correct, so the agent must have passed the author explicitly.
# Vercel maps commit emails to Vercel users and BLOCKED the deploy over it
# (~1hr cost). The session's context email has since changed to yet another
# address — the risk is structural, not a one-off.
#
# This library answers ONE question: "for a commit landing in <repo>, what
# email (and, separately, name) SHOULD it carry?" The consuming gate
# (hooks/gh-commit-author-identity-gate.sh) uses the answer to judge whether
# an explicit override (--author=, -c user.email=/-c user.name=, or the
# GIT_AUTHOR_*/GIT_COMMITTER_* env vars) in a git commit / commit-tree
# command is legitimate or an accident worth blocking.
#
# ============================================================
# RESOLUTION CHAIN (email) — never synthesizes a noreply guess
# ============================================================
#   1. Resolve the target repo's remote owner (gh_owner_from_cwd_remote,
#      hooks/lib/gh-account-lib.sh).
#   2. Map owner -> the gh CLI account that should be active for it
#      (gh_account_for_owner, same lib — the SAME owner/account mapping the
#      gh-account-autoswitch.sh / gh-account-blindness-hint.sh mechanisms
#      already use; this file does not duplicate that mapping).
#   3. That account's PRIMARY VERIFIED EMAIL, via `gh api user/emails`
#      targeted at that SPECIFIC account's stored token (`gh auth token -u
#      <gh_user>`, NOT the currently-ACTIVE account — so this never has the
#      side effect of switching accounts just to answer a read-only
#      question). Cached under gia_state_dir()/<gh_user>.txt for
#      GIA_CACHE_TTL_MIN minutes (default 1440 = 24h) so a hot commit path
#      does not shell out to `gh api` every time.
#   4. If step 3 is unavailable for ANY reason (no gh binary, account not
#      resolvable, or — the documented, LIVE case on this machine as of
#      2026-09-27 — the account's token lacks the `user` scope and `gh api
#      user/emails` 404s) -> fall back to the repo's OWN EFFECTIVE
#      `git config user.email` (local overrides global, exactly like git
#      itself resolves it).
#   5. If NEITHER resolves -> empty. NEVER a `users.noreply.github.com`
#      guess (operator directive, verbatim: "NEVER fall back to a
#      users.noreply.github.com guess — Vercel would block it" — a
#      SYNTHESIZED guess is exactly as likely to be wrong as the session
#      email this mechanism exists to replace). An empty result means the
#      consuming gate has no ground truth to check against and must fail
#      OPEN (allow), not fabricate one.
#
# Name resolution is deliberately simpler: there is no GH-account "expected
# display name" oracle analogous to the email (gh api user/emails has no
# name equivalent worth trusting), so the "expected name" for the purposes
# of catching a `-c user.name=` / GIT_AUTHOR_NAME / GIT_COMMITTER_NAME
# override is the repo's OWN current effective `git config user.name` —
# i.e. a name override is flagged only when it changes what the repo is
# ALREADY configured to use, not against some independently-resolved value.
#
# ============================================================
# CACHING
# ============================================================
# gia_state_dir(): $GIA_STATE_DIR if set (self-test sandboxing), else
# $HOME/.claude/state/gh-emails — matches the $HOME/.claude/state/ convention
# every other cross-project cache in this harness uses.
#
# One flat file per gh_user, holding exactly the resolved email (no JSON,
# no jq dependency for the read path). Freshness is the file's OWN mtime,
# checked the same way this repo already checks a waiver's freshness
# elsewhere (`find <file> -mmin -<TTL>`) — no `touch -d`/GNU-date
# dependency, portable to the same bash 3.2/macOS + Windows Git Bash matrix
# the rest of hooks/lib/ targets.
#
# ============================================================
# SELF-TEST SANDBOXING
# ============================================================
#   GIA_STATE_DIR      - cache directory override
#   GIA_CACHE_TTL_MIN   - cache TTL in minutes (default 1440)
#   GIA_GH_CMD          - path to a `gh` stub (never touches the real `gh`)
# Reuses gh-account-lib.sh's GHBLIND_ACCOUNTS / GHBLIND_ACTIVE for the
# owner->account mapping half — no new config-sandboxing surface.
#
# Self-test: bash gh-commit-identity-lib.sh --self-test

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [ -n "${_GH_COMMIT_IDENTITY_LIB_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_GH_COMMIT_IDENTITY_LIB_SOURCED=1

_GIA_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
. "${_GIA_SELF_DIR}/gh-account-lib.sh" 2>/dev/null || true

gia_state_dir() {
  printf '%s' "${GIA_STATE_DIR:-$HOME/.claude/state/gh-emails}"
}

gia_cache_ttl_min() {
  printf '%s' "${GIA_CACHE_TTL_MIN:-1440}"
}

gia_gh_bin() { printf '%s' "${GIA_GH_CMD:-gh}"; }

# Sanitize a gh_user login into a safe filename component.
_gia_sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

gia_cache_path() {
  printf '%s/%s.txt' "$(gia_state_dir)" "$(_gia_sanitize "$1")"
}

# Echo the cached email for <gh_user> iff the cache file exists AND is
# fresher than gia_cache_ttl_min() minutes. Empty + rc=1 otherwise (miss,
# stale, or absent — all treated identically by the caller: re-resolve).
gia_cached_email() {
  local gh_user="$1" path
  path="$(gia_cache_path "$gh_user")"
  [ -f "$path" ] || return 1
  find "$path" -mmin "-$(gia_cache_ttl_min)" 2>/dev/null | grep -q . || return 1
  local content
  content="$(tr -d '\r\n' < "$path" 2>/dev/null)"
  [ -n "$content" ] || return 1
  printf '%s' "$content"
}

# Write <email> to the cache for <gh_user>. Best-effort — never fails the
# caller (a cache write failure just means the next call re-resolves).
gia_cache_email() {
  local gh_user="$1" email="$2" dir path
  dir="$(gia_state_dir)"
  path="$(gia_cache_path "$gh_user")"
  ( mkdir -p "$dir" 2>/dev/null && printf '%s' "$email" > "$path.tmp.$$" 2>/dev/null \
      && mv "$path.tmp.$$" "$path" 2>/dev/null ) || true
  return 0
}

# <gh_user>'s primary verified email, via THAT account's own stored gh CLI
# token (never the currently-active account — this must never have the side
# effect of switching accounts just to answer a read-only question). Empty +
# rc=1 on ANY failure (no gh binary, account not stored, token has no `user`
# scope so `gh api user/emails` 404s — the live MishaPT case as of
# 2026-09-27).
gia_gh_primary_email() {
  local gh_user="$1" gh_bin tok
  gh_bin="$(gia_gh_bin)"
  command -v "$gh_bin" >/dev/null 2>&1 || return 1
  tok="$("$gh_bin" auth token -u "$gh_user" 2>/dev/null)" || return 1
  [ -n "$tok" ] || return 1
  local out
  out="$(GH_TOKEN="$tok" "$gh_bin" api user/emails --jq '([.[]|select(.primary==true)]|.[0].email) // empty' 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Resolve the expected EMAIL for a commit landing in <cwd/target_dir>. Sets
# (never echoes, to stay call-without-subshell like git-command-parse.sh's
# hot-path helpers):
#   GIA_EMAIL         - the resolved email, or "" if unresolvable
#   GIA_EMAIL_SOURCE  - "gh-api-cache:<gh_user>" | "gh-api:<gh_user>" |
#                       "git-config" | "unresolved"
# Returns 0 iff GIA_EMAIL is non-empty.
gia_resolve_expected_email() {
  local cwd="$1" owner gh_user cached resolved cfg
  GIA_EMAIL=""; GIA_EMAIL_SOURCE="unresolved"

  owner="$(gh_owner_from_cwd_remote "$cwd" 2>/dev/null)"
  if [ -n "$owner" ]; then
    gh_user="$(gh_account_for_owner "$owner" 2>/dev/null)"
    if [ -n "$gh_user" ]; then
      cached="$(gia_cached_email "$gh_user")"
      if [ -n "$cached" ]; then
        GIA_EMAIL="$cached"; GIA_EMAIL_SOURCE="gh-api-cache:${gh_user}"
        return 0
      fi
      resolved="$(gia_gh_primary_email "$gh_user")"
      if [ -n "$resolved" ]; then
        gia_cache_email "$gh_user" "$resolved"
        GIA_EMAIL="$resolved"; GIA_EMAIL_SOURCE="gh-api:${gh_user}"
        return 0
      fi
    fi
  fi

  # Fallback: the repo's OWN effective git config (local overrides global —
  # `git config --get` already resolves that merge). NEVER a noreply guess
  # past this point — if this is empty too, GIA_EMAIL stays "".
  cfg="$(git -C "$cwd" config --get user.email 2>/dev/null)"
  if [ -n "$cfg" ]; then
    GIA_EMAIL="$cfg"; GIA_EMAIL_SOURCE="git-config"
    return 0
  fi

  return 1
}

# Resolve the expected NAME for a commit landing in <cwd/target_dir> — see
# the header comment: this is the repo's OWN current effective
# `git config user.name`, not an independently-resolved oracle.
gia_resolve_expected_name() {
  local cwd="$1"
  GIA_NAME="$(git -C "$cwd" config --get user.name 2>/dev/null)"
  [ -n "$GIA_NAME" ]
}

# ============================================================
# --self-test
# ============================================================
_gia_self_test() {
  local pass=0 fail=0 tmp cfg stub calls gr

  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t gialib)"
  cfg="$tmp/accounts.config.json"
  cat > "$cfg" <<'JSON'
{
  "work":     [ { "gh_user": "acct-work",     "owners": ["work-org"] } ],
  "personal": [ { "gh_user": "acct-personal", "owners": ["personal-org"] } ]
}
JSON

  # Recording + scriptable `gh` stub. STUB_EMAIL_<user> (sanitized) controls
  # what `gh api user/emails` returns for that user's token; empty/unset
  # means "fails" (simulates the missing `user` scope 404). STUB_TOKEN_<user>
  # controls `gh auth token -u <user>`; unset means "no such stored account".
  stub="$tmp/gh-stub.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
CALLS_FILE="${GIA_STUB_CALLS:-/dev/null}"
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "token" ] && [ "${3:-}" = "-u" ]; then
  echo "auth-token $4" >> "$CALLS_FILE"
  var="STUB_TOKEN_$(printf '%s' "$4" | tr -c 'A-Za-z0-9_' '_')"
  val="${!var:-}"
  [ -n "$val" ] || exit 1
  printf '%s' "$val"
  exit 0
fi
if [ "${1:-}" = "api" ] && [ "${2:-}" = "user/emails" ]; then
  echo "api-user-emails token=${GH_TOKEN:-<none>}" >> "$CALLS_FILE"
  var="STUB_EMAIL_FOR_TOKEN_$(printf '%s' "${GH_TOKEN:-}" | tr -c 'A-Za-z0-9_' '_')"
  val="${!var:-}"
  [ -n "$val" ] || exit 1
  printf '%s' "$val"
  exit 0
fi
exit 1
STUB
  chmod +x "$stub" 2>/dev/null || true

  export HARNESS_SELFTEST=1
  export GIA_STATE_DIR="$tmp/state"
  mkdir -p "$GIA_STATE_DIR"

  gr="$tmp/repo"
  mkdir -p "$gr"
  ( cd "$gr" && git init -q 2>/dev/null \
      && git remote add origin "https://github.com/work-org/some-repo.git" 2>/dev/null )

  _case() { # <name> <expect_rc0|1> <expect_email> <expect_source_prefix>
    local name="$1" want_rc="$2" want_email="$3" want_src_prefix="$4"
    local rc
    gia_resolve_expected_email "$gr"
    rc=$?
    if [ "$rc" = "$want_rc" ] && [ "$GIA_EMAIL" = "$want_email" ] && case "$GIA_EMAIL_SOURCE" in "$want_src_prefix"*) true;; *) false;; esac; then
      echo "  $name: PASS (email=$GIA_EMAIL source=$GIA_EMAIL_SOURCE)"; pass=$((pass+1))
    else
      echo "  $name: FAIL (rc=$rc email=$GIA_EMAIL source=$GIA_EMAIL_SOURCE; wanted rc=$want_rc email=$want_email source-prefix=$want_src_prefix)"; fail=$((fail+1))
    fi
  }

  # S1: owner known, gh-api resolves -> gh-api:<user>, and cached.
  calls="$tmp/calls1.txt"; : > "$calls"
  export GHBLIND_ACCOUNTS="$cfg" GIA_GH_CMD="$stub" GIA_STUB_CALLS="$calls"
  export STUB_TOKEN_acct_work="tok-work-1"
  export STUB_EMAIL_FOR_TOKEN_tok_work_1="acct-work@example.test"
  _case "S1 gh-api resolves on first call" 0 "acct-work@example.test" "gh-api:"

  # S2: same repo again -> cache hit, and the stub's user/emails endpoint is
  # NOT called a second time (only the S1 call should be on record).
  gia_resolve_expected_email "$gr" >/dev/null
  local n_email_calls; n_email_calls="$(grep -c '^api-user-emails' "$calls" 2>/dev/null || echo 0)"
  if [ "$GIA_EMAIL_SOURCE" = "gh-api-cache:acct-work" ] && [ "$n_email_calls" = "1" ]; then
    echo "  S2 cache hit avoids repeat gh api call: PASS"; pass=$((pass+1))
  else
    echo "  S2 cache hit avoids repeat gh api call: FAIL (source=$GIA_EMAIL_SOURCE email-calls=$n_email_calls)"; fail=$((fail+1))
  fi

  # S3: cache TTL of 0 minutes -> even a just-written cache counts as stale
  # -> re-resolves (proves the freshness check is load-bearing, not a no-op).
  GIA_CACHE_TTL_MIN=0 gia_resolve_expected_email "$gr" >/dev/null
  n_email_calls="$(grep -c '^api-user-emails' "$calls" 2>/dev/null || echo 0)"
  if [ "$n_email_calls" = "2" ]; then
    echo "  S3 TTL=0 forces re-resolution past the cache: PASS"; pass=$((pass+1))
  else
    echo "  S3 TTL=0 forces re-resolution past the cache: FAIL (email-calls=$n_email_calls, wanted 2)"; fail=$((fail+1))
  fi
  unset STUB_TOKEN_acct_work STUB_EMAIL_FOR_TOKEN_tok_work_1

  # S4: scope-missing fallback — token resolves (account IS stored) but
  # user/emails fails (simulates the live 404-for-missing-user-scope case) ->
  # falls back to the repo's OWN git config, never a noreply guess.
  git -C "$gr" config user.email "fallback@example.test"
  export STUB_TOKEN_acct_work="tok-work-2"
  # deliberately NOT setting STUB_EMAIL_FOR_TOKEN_tok_work_2 -> api call fails
  rm -f "$GIA_STATE_DIR"/*.txt
  _case "S4 scope-missing-fallback (gh-api fails -> repo git config)" 0 "fallback@example.test" "git-config"
  unset STUB_TOKEN_acct_work

  # S5: noreply-never-used — owner unknown to accounts.config AND repo has
  # no git config at all (isolated HOME, no global config either) ->
  # unresolved (empty), rc=1. Grep the actual gate output would happen in the
  # gate's own self-test; here we assert the LIBRARY never manufactures one.
  local gr2="$tmp/repo2"; mkdir -p "$gr2"
  ( cd "$gr2" && HOME="$tmp/emptyhome" git init -q 2>/dev/null \
      && git remote add origin "https://github.com/unknown-org/x.git" 2>/dev/null )
  mkdir -p "$tmp/emptyhome"
  rm -f "$GIA_STATE_DIR"/*.txt
  HOME="$tmp/emptyhome" gia_resolve_expected_email "$gr2" >/dev/null
  local rc5=$?
  if [ "$rc5" = "1" ] && [ -z "$GIA_EMAIL" ] && [ "$GIA_EMAIL_SOURCE" = "unresolved" ]; then
    echo "  S5 noreply-never-used: fully unresolvable -> empty, not a guess: PASS"; pass=$((pass+1))
  else
    echo "  S5 noreply-never-used: FAIL (rc=$rc5 email='$GIA_EMAIL' source=$GIA_EMAIL_SOURCE)"; fail=$((fail+1))
  fi
  if ! grep -qi 'noreply' <<< "$GIA_EMAIL"; then
    echo "  S5b resolved value never contains 'noreply': PASS"; pass=$((pass+1))
  else
    echo "  S5b resolved value never contains 'noreply': FAIL (got: $GIA_EMAIL)"; fail=$((fail+1))
  fi
  # Static invariant: the resolution chain in THIS file never constructs a
  # users.noreply.github.com string. Strips full-line comments first (the
  # header/inline comments legitimately NAME "noreply" in prose explaining
  # why the code never constructs one) so this checks actual CODE, not the
  # comment describing the guarantee.
  if ! sed -n '/^gia_resolve_expected_email/,/^}/p' "$0" | grep -v '^[[:space:]]*#' | grep -q 'noreply'; then
    echo "  S5c resolver source never constructs a noreply address: PASS"; pass=$((pass+1))
  else
    echo "  S5c resolver source never constructs a noreply address: FAIL"; fail=$((fail+1))
  fi

  # S6: no `gh` binary at all -> straight to git config fallback.
  git -C "$gr" config user.email "onlyconfig@example.test"
  rm -f "$GIA_STATE_DIR"/*.txt
  GIA_GH_CMD="/no/such/gh-binary-xyz" gia_resolve_expected_email "$gr" >/dev/null
  if [ "$GIA_EMAIL" = "onlyconfig@example.test" ] && [ "$GIA_EMAIL_SOURCE" = "git-config" ]; then
    echo "  S6 no gh binary -> git config fallback: PASS"; pass=$((pass+1))
  else
    echo "  S6 no gh binary -> git config fallback: FAIL (email=$GIA_EMAIL source=$GIA_EMAIL_SOURCE)"; fail=$((fail+1))
  fi

  # S7: name resolution reads the repo's own user.name.
  git -C "$gr" config user.name "Test Name"
  gia_resolve_expected_name "$gr" >/dev/null
  if [ "$GIA_NAME" = "Test Name" ]; then
    echo "  S7 gia_resolve_expected_name reads repo user.name: PASS"; pass=$((pass+1))
  else
    echo "  S7 gia_resolve_expected_name reads repo user.name: FAIL (got: $GIA_NAME)"; fail=$((fail+1))
  fi

  unset GHBLIND_ACCOUNTS GIA_GH_CMD GIA_STUB_CALLS HARNESS_SELFTEST GIA_STATE_DIR
  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[gh-commit-identity-lib self-test] $pass passed, $fail failed"
  return "$fail"
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then
  _gia_self_test
  exit $?
fi
