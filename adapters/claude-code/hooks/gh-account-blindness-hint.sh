#!/usr/bin/env bash
# NEURAL-LACE-HOOK
# gh-account-blindness-hint.sh — react at the failure moment when a gh/git
# "repo not found" / 403 is actually a WRONG-ACTIVE-ACCOUNT problem, not a
# missing repo.
#
# WHY THIS EXISTS (root cause, 2026-06-05): a `gh` 404/403 caused by being
# authenticated as the WRONG account (e.g. active as account-A while the repo
# is owned by account-B) currently produces a false "the repo doesn't exist"
# conclusion. The dual-account convention is documented (a Pattern in
# rules/git.md + CLAUDE.md), but nothing REACTED to the 404. Per
# principles.md Decision Principle 6 ("mechanical where the signal is
# reliable") a gh 404/403 is a reliable signal — so this turns the Pattern
# into a Mechanism that fires the instant the failure happens.
#
# THREE LAYERS this file backs:
#   L1 (load-bearing, default mode): PostToolUse Bash hook. Scans the tool's
#       stdout/stderr for a not-found/403 signature, extracts the target
#       <owner>/<repo> from the gh/git command, looks <owner> up in
#       ~/.claude/local/accounts.config.json, and — IF that owner's account
#       is NOT the currently-active `gh auth` account — injects an advisory
#       naming the exact remediation: `gh auth switch -u <owner>; retry;
#       switch back`.
#   L2 (--session-start mode): emit the full account-map broadcast — all
#       authed accounts + the owner->account map + the "a 404 means switch
#       accounts, not missing repo" note. Wired as a SessionStart line right
#       after the existing active-account switcher.
#   L3 lives in rules/git.md (a one-line Pattern), not in this file.
#
# HYGIENE: this committed hook NEVER hardcodes account names or any personal
# identifier. The owner->account map is read from
# ~/.claude/local/accounts.config.json (gitignored, per-machine) at runtime.
#
# CONFIG SHAPE (read at runtime; canonical per examples/accounts.config.example.json):
#   {
#     "work":     [ { "gh_user": "<login>", "owners": ["<org-or-owner>", ...]? }, ... ],
#     "personal": [ { "gh_user": "<login>", "owners": [...]? }, ... ]
#   }
#   - gh_user is the gh CLI account login. owner==gh_user is the load-bearing
#     mapping: a repo owned by <X> needs the account whose gh_user is <X>.
#   - owners[] is OPTIONAL and forward-compatible: a list of additional GitHub
#     owners/orgs that account can access (e.g. an org the personal account is
#     a member of). When present, a repo under one of those owners maps to that
#     account too. Absent owners[] -> only owner==gh_user resolves.
#   - Legacy `user` is accepted as a fallback for `gh_user`. `work`/`personal`
#     may each be an object or an array of objects.
#
# Behavior (L1):
#   - Reads command + output from the PostToolUse JSON payload on stdin.
#   - No-op (silent, exit 0) unless: the command is gh/git AND the output
#     contains a not-found/403 signature AND a target owner can be extracted
#     AND that owner is a KNOWN account in accounts.config.json AND the active
#     account != that owner's account.
#   - On all of the above: emits a model-visible advisory naming the switch.
#   - ALWAYS exits 0 (advisory; the tool already failed — never blocks).
#   - Missing jq / missing accounts.config / can't determine active account /
#     unparseable owner -> graceful silent no-op.
#
# Hook event: PostToolUse, matcher "Bash" (L1); SessionStart (L2, --session-start).
# Self-test: invoke with --self-test (uses *_OVERRIDE env stubs; no real gh).
#
# REFACTOR (GH-AUTH-AUTOSWITCH-WORKORG-01, 2026-07-07): the owner/account
# resolution helpers (_account_for_owner, _active_account, _load_accounts,
# _accounts_path, _all_accounts) now live in hooks/lib/gh-account-lib.sh,
# shared with the new PreToolUse gh-account-autoswitch.sh hook, so the two
# mechanisms do not diverge. This file keeps its own event-specific logic
# (not-found-signature scan, owner/repo slug extraction, the advisory text,
# the SessionStart broadcast) and thin wrappers below delegate to the lib.

set -u

_GHLIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
. "${_GHLIB_DIR}/lib/gh-account-lib.sh" 2>/dev/null || true

# ============================================================
# Error signatures that mean "not found / forbidden"
# ============================================================
# Kept tight to avoid false positives. A bare "404" is NOT enough on its own —
# we additionally require the command to be a gh/git repo-targeting command.
_NF_SIGNATURE_RE='Could not resolve to a Repository|Repository not found|GraphQL: Could not resolve|Not Found \(HTTP 404\)|HTTP 404|gh: Not Found|Must have admin rights|Resource not accessible by|HTTP 403|\(HTTP 403\)|Permission to .* denied'

# ============================================================
# Input
# ============================================================

# Read the tool command. GHBLIND_CMD wins (self-test); else parse stdin JSON.
_read_command() {
  if [ -n "${GHBLIND_CMD:-}" ]; then printf '%s' "$GHBLIND_CMD"; return 0; fi
  local payload="${_GHBLIND_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    printf '%s' "$payload" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true
  else
    printf '%s' "$payload"
  fi
}

# Read the tool output (stdout+stderr). GHBLIND_OUTPUT wins (self-test).
_read_output() {
  if [ -n "${GHBLIND_OUTPUT:-}" ]; then printf '%s' "$GHBLIND_OUTPUT"; return 0; fi
  local payload="${_GHBLIND_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    # tool_response may be an object {stdout,stderr,...} or a bare string.
    # tostring captures all of it for substring matching.
    printf '%s' "$payload" | jq -r '.tool_response | tostring' 2>/dev/null || true
  else
    printf '%s' "$payload"
  fi
}

# ============================================================
# Predicates / extraction
# ============================================================

_is_gh_or_git() {
  printf '%s' "$1" | grep -qE '(^|[[:space:];&|(])(gh|git)([[:space:]]|$)'
}

_has_notfound_signature() {
  printf '%s' "$1" | grep -qE "$_NF_SIGNATURE_RE"
}

# Extract the target owner/repo slug from a gh/git command. Echoes "owner/repo"
# (lowercased owner is NOT applied — GitHub logins are case-insensitive but we
# compare case-insensitively below). Empty on no match.
_extract_owner_repo() {
  local cmd="$1" slug=""
  # 1) --repo owner/repo  OR  -R owner/repo  (gh pr/issue/etc.)
  slug="$(printf '%s' "$cmd" | grep -oiE '(--repo|-R)[=[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | sed -E 's/^(--repo|-R)[=[:space:]]+//I')"
  if [ -n "$slug" ]; then printf '%s' "${slug%.git}"; return 0; fi
  # 2) gh api repos/owner/repo[/...]
  slug="$(printf '%s' "$cmd" | grep -oiE 'repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | sed -E 's#^repos/##')"
  if [ -n "$slug" ]; then printf '%s' "${slug%.git}"; return 0; fi
  # 3) github.com/owner/repo  OR  github.com:owner/repo
  slug="$(printf '%s' "$cmd" | grep -oiE 'github\.com[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | sed -E 's#^github\.com[:/]##')"
  if [ -n "$slug" ]; then printf '%s' "${slug%.git}"; return 0; fi
  # 4) gh repo <subcmd> owner/repo  (view|clone|edit|...)
  slug="$(printf '%s' "$cmd" | grep -oiE 'gh[[:space:]]+repo[[:space:]]+[a-z-]+[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | grep -oiE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')"
  if [ -n "$slug" ]; then printf '%s' "${slug%.git}"; return 0; fi
  # 5) bare owner/repo argument (last resort; command already known gh/git)
  slug="$(printf '%s' "$cmd" | grep -oiE '(^|[[:space:]])[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+([[:space:]]|$)' | head -1 \
            | tr -d '[:space:]')"
  if [ -n "$slug" ]; then printf '%s' "${slug%.git}"; return 0; fi
  printf ''
}

# Path to accounts.config.json. GHBLIND_ACCOUNTS wins (self-test).
# Delegates to hooks/lib/gh-account-lib.sh (shared with gh-account-autoswitch.sh).
_accounts_path() { gh_accounts_path; }

# Load + CR-strip + JSON-validate accounts config. Echoes content; rc!=0 on
# missing/empty/malformed/no-jq.
_load_accounts() { gh_load_accounts; }

# Given an owner, echo the gh_user account that should be active for it, or
# empty if owner is not known to the config. Mapping:
#   - owner == some entry's gh_user (or legacy `user`)  -> that gh_user
#   - owner listed in some entry's owners[]             -> that entry's gh_user
# Case-insensitive comparison (GitHub logins are case-insensitive).
_account_for_owner() { gh_account_for_owner "$1"; }

# List "<type> <gh_user>" lines for every account in the config (L2).
_all_accounts() { gh_all_accounts; }

# Currently-active gh account login. GHBLIND_ACTIVE wins (self-test).
_active_account() { gh_active_account; }

# ============================================================
# L1 — PostToolUse hint
# ============================================================

# Pure decision function. Echoes the hint text on stdout (no wrapper) when a
# hint should fire; echoes nothing when it should not. Used by both the live
# emitter and the self-test.
_compute_hint() {
  local cmd output owner slug required active
  cmd="$(_read_command)"
  output="$(_read_output)"

  [ -n "$cmd" ] || return 0
  _is_gh_or_git "$cmd" || return 0
  _has_notfound_signature "$output" || return 0

  slug="$(_extract_owner_repo "$cmd")"
  [ -n "$slug" ] || return 0
  owner="${slug%%/*}"
  [ -n "$owner" ] || return 0

  required="$(_account_for_owner "$owner")"
  [ -n "$required" ] || return 0   # owner not a known account -> can't advise

  active="$(_active_account)"
  [ -n "$active" ] || return 0     # can't determine active account -> no-op

  # Correct account already active -> the repo really is missing/forbidden.
  [ "$(printf '%s' "$active" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$required" | tr '[:upper:]' '[:lower:]')" ] && return 0

  cat <<EOF
[gh-account-blindness] The failure on '${slug}' is almost certainly a WRONG-ACCOUNT problem, not a missing repo.
  Active gh account: ${active}
  '${owner}' is served by account: ${required}
  This is account-blindness: a 404/403 here means "switch accounts", NOT "the repo doesn't exist".
  Remediation (run, then retry the failed command, then switch back):
    gh auth switch -u ${required}
    # <retry the gh/git command that just failed>
    gh auth switch -u ${active}
EOF
}

_run_l1() {
  # Capture stdin payload once (PostToolUse JSON) unless overridden.
  if [ -z "${GHBLIND_CMD:-}" ] || [ -z "${GHBLIND_OUTPUT:-}" ]; then
    _GHBLIND_PAYLOAD="$(cat 2>/dev/null || true)"
  fi
  local hint
  hint="$(_compute_hint)"
  if [ -n "$hint" ]; then
    if command -v jq >/dev/null 2>&1; then
      # Sanctioned PostToolUse channel for adding model-visible context.
      jq -n --arg ctx "$hint" \
        '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    else
      printf '%s\n' "$hint"
    fi
  fi
  exit 0
}

# ============================================================
# L2 — SessionStart account-map broadcast
# ============================================================

_run_session_start() {
  local accounts active
  accounts="$(_all_accounts 2>/dev/null || true)"
  # No config / no accounts -> stay silent (the existing switcher already
  # reports the no-config case).
  [ -n "$accounts" ] || exit 0

  active="$(_active_account)"

  echo "[gh-account-map] Authed gh accounts on this machine (owner == account):"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local atype auser marker=""
    atype="${line%% *}"; auser="${line#* }"
    if [ -n "$active" ] && [ "$(printf '%s' "$auser" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$active" | tr '[:upper:]' '[:lower:]')" ]; then
      marker="  <- ACTIVE"
    fi
    echo "  • ${auser} (${atype}) — owns repos under '${auser}/'${marker}"
  done <<< "$accounts"
  echo "  NOTE: a gh/git 404 or 403 means SWITCH ACCOUNTS (gh auth switch -u <owner>),"
  echo "        not that the repo is missing. The PostToolUse hint fires this automatically."
  exit 0
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local pass=0 fail=0 tmp got
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ghblind)"
  local cfg="$tmp/accounts.config.json"
  cat > "$cfg" <<'JSON'
{
  "work":     [ { "gh_user": "acct-work",     "owners": ["work-org"] } ],
  "personal": [ { "gh_user": "acct-personal" } ]
}
JSON

  # C1 — 404 while WRONG account -> hint fires (owner=acct-personal, active=acct-work).
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="gh repo view acct-personal/some-repo" \
         GHBLIND_OUTPUT="GraphQL: Could not resolve to a Repository with the name 'acct-personal/some-repo'. (HTTP 404)" \
         _compute_hint)"
  if printf '%s' "$got" | grep -q 'gh auth switch -u acct-personal' \
     && printf '%s' "$got" | grep -q 'acct-work'; then
    echo "  C1 404 wrong-account -> hint fires: PASS"; pass=$((pass+1))
  else
    echo "  C1 404 wrong-account -> hint fires: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C2 — 404 while CORRECT account -> no hint (owner=acct-personal, active=acct-personal).
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-personal" \
         GHBLIND_CMD="gh api repos/acct-personal/some-repo" \
         GHBLIND_OUTPUT="gh: Not Found (HTTP 404)" \
         _compute_hint)"
  if [ -z "$got" ]; then
    echo "  C2 404 correct-account -> no hint: PASS"; pass=$((pass+1))
  else
    echo "  C2 404 correct-account -> no hint: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C3 — non-gh tool output -> no-op (npm test failure, no signature, not gh/git).
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="npm test" \
         GHBLIND_OUTPUT="1 test failed: expected true to be false" \
         _compute_hint)"
  if [ -z "$got" ]; then
    echo "  C3 non-gh output -> no-op: PASS"; pass=$((pass+1))
  else
    echo "  C3 non-gh output -> no-op: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C4 — missing accounts.config -> graceful no-op (even with a real 404 + wrong-looking).
  got="$(GHBLIND_ACCOUNTS="$tmp/does-not-exist.json" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="gh repo view acct-personal/some-repo" \
         GHBLIND_OUTPUT="Could not resolve to a Repository" \
         _compute_hint)"
  if [ -z "$got" ]; then
    echo "  C4 missing config -> graceful no-op: PASS"; pass=$((pass+1))
  else
    echo "  C4 missing config -> graceful no-op: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C5 — owner not a known account -> no hint (can't advise which account).
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="gh repo view some-other-org/their-repo" \
         GHBLIND_OUTPUT="HTTP 404" \
         _compute_hint)"
  if [ -z "$got" ]; then
    echo "  C5 unknown owner -> no hint: PASS"; pass=$((pass+1))
  else
    echo "  C5 unknown owner -> no hint: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C6 — org repo via owners[] while wrong account -> hint fires (owner=work-org -> acct-work).
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-personal" \
         GHBLIND_CMD="gh api repos/work-org/internal --jq .name" \
         GHBLIND_OUTPUT="gh: Not Found (HTTP 404)" \
         _compute_hint)"
  if printf '%s' "$got" | grep -q 'gh auth switch -u acct-work'; then
    echo "  C6 org via owners[] -> hint fires: PASS"; pass=$((pass+1))
  else
    echo "  C6 org via owners[] -> hint fires: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C7 — gh command SUCCEEDED (no signature) -> no-op.
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="gh repo view acct-personal/some-repo" \
         GHBLIND_OUTPUT="acct-personal/some-repo  A normal repo description  Updated 2d ago" \
         _compute_hint)"
  if [ -z "$got" ]; then
    echo "  C7 success output -> no-op: PASS"; pass=$((pass+1))
  else
    echo "  C7 success output -> no-op: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C8 — L2 account-map lists all accounts + the note.
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" bash "$0" --session-start)"
  if printf '%s' "$got" | grep -q 'acct-work (work)' \
     && printf '%s' "$got" | grep -q 'acct-personal (personal)' \
     && printf '%s' "$got" | grep -q '<- ACTIVE' \
     && printf '%s' "$got" | grep -qi 'SWITCH ACCOUNTS'; then
    echo "  C8 L2 account-map broadcast: PASS"; pass=$((pass+1))
  else
    echo "  C8 L2 account-map broadcast: FAIL (got: $got)"; fail=$((fail+1))
  fi

  # C9 — git clone over https while wrong account -> hint fires.
  got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="acct-work" \
         GHBLIND_CMD="git clone https://github.com/acct-personal/some-repo.git" \
         GHBLIND_OUTPUT="remote: Repository not found.\nfatal: repository not found" \
         _compute_hint)"
  if printf '%s' "$got" | grep -q 'gh auth switch -u acct-personal'; then
    echo "  C9 git-clone https wrong-account -> hint fires: PASS"; pass=$((pass+1))
  else
    echo "  C9 git-clone https wrong-account -> hint fires: FAIL (got: $got)"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --session-start) _run_session_start ;;
  --self-test)     _self_test; exit $? ;;
  -h|--help)
    cat <<'GHBLIND_USAGE' >&2
gh-account-blindness-hint.sh — react to wrong-active-account gh/git 404/403.

  gh-account-blindness-hint.sh                 # L1: PostToolUse (reads JSON on stdin)
  gh-account-blindness-hint.sh --session-start # L2: emit account-map broadcast
  gh-account-blindness-hint.sh --self-test     # run self-test suite

The L1 path injects an advisory naming `gh auth switch -u <owner>` when a
gh/git not-found/403 is caused by the wrong account being active. Owner ->
account mapping is read from ~/.claude/local/accounts.config.json at runtime;
no account names are hardcoded. Always exits 0 (advisory; never blocks).
GHBLIND_USAGE
    exit 2
    ;;
  "") _run_l1 ;;
  *)
    echo "gh-account-blindness-hint.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
