#!/usr/bin/env bash
# NEURAL-LACE-HOOK
# gh-account-autoswitch.sh — PROACTIVELY switch the active `gh` account
# BEFORE a gh/git command targeting the OTHER account's repo runs, so the
# WRONG-ACCOUNT 403/"Repository not found" never happens in the first place.
#
# WHY THIS EXISTS (GH-AUTH-AUTOSWITCH-WORKORG-01, operator-greenlit 2026-07-07)
#
# This machine has two GitHub accounts: alice-at-acme (work, owns
# acme-org/* = origin) and alice-example (personal, owns
# alice-example/* = the personal mirror). The active `gh` identity flips to
# whichever account last ran a `gh auth switch` / `gh auth login`. Before
# this hook, `gh pr merge`/`gh pr create` etc. against the OTHER account's
# repo 403s ("Repository not found"), and the agent historically STOPPED
# and waited on the operator for a one-line `gh auth switch` fix — wasting
# large amounts of operator time.
#
# THIS HOOK is the PROACTIVE half of the fix: it runs BEFORE the gh/git
# command executes and switches accounts pre-emptively when it can resolve
# the target owner and that owner differs from the active account.
#
# THE OTHER (PRE-EXISTING) HALF — gh-account-blindness-hint.sh — is
# REACTIVE: it fires AFTER a 404/403 already happened (PostToolUse) and
# only ADVISES the switch; it does not act. This hook and that one share
# owner/account resolution via hooks/lib/gh-account-lib.sh (see that file's
# header) — NOT duplicated logic, just two different reaction points on the
# same underlying mapping. If this hook's PRE-emptive switch works, the
# blindness-hint should rarely have anything left to react to; it stays as
# a safety net for any command shape this hook does not recognize (e.g. a
# raw `curl` against the GitHub API, or gh subcommands not in scope below).
#
# DESIGN CHOICE — leave-on-target, do NOT switch back (documented, not a
# gap): after switching for a wrong-account command, this hook does NOT
# add a PostToolUse companion to switch back to the prior account. Two
# reasons: (1) the SAME session commonly issues several commands against
# the SAME just-switched-to owner in a row (e.g. `gh pr create` then
# `gh pr view` then `gh pr merge` on the same personal-mirror repo) — a
# switch-back after each one would cause MORE total switches, not fewer;
# (2) the existing SessionStart directory-based switcher (inline command
# in settings.json.template, `nl_accounts_match_dir "$PWD"`) already
# re-asserts the cwd's correct default account at the START of every new
# session, so a leftover "wrong for this dir" active account from a prior
# session's autoswitch self-corrects the moment a new session begins. The
# risk this accepts: mid-session, a subsequent gh command that has NO
# resolvable target owner (a bare `gh pr list` with no --repo, run from a
# directory whose git remote doesn't disambiguate) could run against
# whichever account this hook last left active, rather than the cwd's
# "true" default. This hook mitigates that specific risk by re-deriving
# the cwd-default via the SAME dir-trigger config
# (nl_accounts_match_dir-equivalent, see _cwd_default_owner_account below)
# as a fallback path when no explicit target is resolvable — see
# _resolve_target_account.
#
# THIS HOOK NEVER BLOCKS: every exit path is `exit 0`. It prepares the
# environment (or no-ops); it never denies the tool call. Read-only gh/git
# subcommands are explicitly excluded — switching accounts for a read that
# would succeed on either account is unnecessary account-flip noise.
#
# THIS IS ONE HALF OF THE FIX, DOCUMENTED: this hook only fixes the
# WRONG-ACCOUNT 403. The operator's separate full-auto merge authorization
# (automation-mode.json / the deploy-matcher classifier) is a DIFFERENT
# concern — a `gh pr merge` may still be gated by that classifier for
# review-before-deploy mode. This hook does not touch that gate; it only
# ensures that WHEN the merge is allowed to proceed, it runs against the
# correct account.
#
# Hook event: PreToolUse, matcher "Bash".
# Self-test: invoke with --self-test (stubs `gh` via a fake PATH entry;
# never touches real gh auth state).

set -u

_GHAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
. "${_GHAS_DIR}/lib/gh-account-lib.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${_GHAS_DIR}/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================
# Input — read the PreToolUse JSON payload (tool_input.command, cwd) from
# stdin, or honor GHAS_CMD / GHAS_CWD overrides for self-test / flagless
# direct invocation.
# ============================================================

_ghas_read_payload() {
  if [ -z "${GHAS_CMD:-}" ]; then
    _GHAS_PAYLOAD="$(cat 2>/dev/null || true)"
  fi
}

_ghas_command() {
  if [ -n "${GHAS_CMD:-}" ]; then printf '%s' "$GHAS_CMD"; return 0; fi
  local payload="${_GHAS_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    printf '%s' "$payload" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true
  else
    printf '%s' "$payload"
  fi
}

_ghas_cwd() {
  if [ -n "${GHAS_CWD:-}" ]; then printf '%s' "$GHAS_CWD"; return 0; fi
  local payload="${_GHAS_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    local c
    c="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
    if [ -n "$c" ]; then printf '%s' "$c"; return 0; fi
  fi
  printf '%s' "$PWD"
}

# ============================================================
# Predicates — which commands are IN SCOPE (may need a switch) vs
# READ-ONLY (never switch; works on either account).
# ============================================================

# gh subcommands that write/target a specific repo's identity and are worth
# pre-switching for. Kept tight and named explicitly per the task spec.
_GHAS_WRITE_RE='gh[[:space:]]+pr[[:space:]]+(merge|create|ready|checkout|close|reopen|edit|review|view)|gh[[:space:]]+repo[[:space:]]+(create|edit|delete|fork|clone|view)|gh[[:space:]]+issue[[:space:]]+(create|close|reopen|edit)|gh[[:space:]]+release[[:space:]]+(create|delete|edit|upload)|gh[[:space:]]+api[[:space:]]'

# `gh pr view` is explicitly listed as in-scope by the task spec (it is the
# livesmoke scenario), even though it's a read — a 404 on the wrong account
# is just as much a false "doesn't exist" there as on a write. `gh repo view`
# likewise appears in the spec's write-subcommand list above for the same
# reason: viewing the WRONG account's private repo also 404s.

_ghas_is_gh_or_git() {
  printf '%s' "$1" | grep -qE '(^|[[:space:];&|(])(gh|git)([[:space:]]|$)'
}

# True if the command is a `git push <remote> ...` (remote name matters —
# that's how we resolve target owner for git, distinct from gh subcommands).
_ghas_is_git_push() {
  printf '%s' "$1" | grep -qE '(^|[[:space:];&|(])git[[:space:]]+push([[:space:]]|$)'
}

_ghas_is_write_scope() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -qE "$_GHAS_WRITE_RE" && return 0
  _ghas_is_git_push "$cmd" && return 0
  return 1
}

# ============================================================
# Target-owner resolution. Priority order per the task spec:
#   1. explicit --repo/-R owner/repo flag
#   2. the named git remote's URL owner (for `git push <remote> ...`)
#   3. the cwd repo's origin owner (fallback for gh subcommands with no
#      --repo flag; gh itself resolves against the cwd repo's remote)
# ============================================================

_ghas_extract_repo_flag_owner() {
  local cmd="$1" slug
  slug="$(printf '%s' "$cmd" | grep -oiE '(--repo|-R)[=[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | sed -E 's/^(--repo|-R)[=[:space:]]+//I')"
  [ -n "$slug" ] || return 1
  printf '%s' "${slug%%/*}"
}

# Given a remote NAME (e.g. "origin", "personal"), echo its owner login by
# reading the remote URL via `git -C <cwd> remote get-url <name>`.
_ghas_owner_from_remote_name() {
  local cwd="$1" remote="$2" url
  command -v git >/dev/null 2>&1 || return 1
  url="$(git -C "$cwd" remote get-url "$remote" 2>/dev/null)" || return 1
  _ghas_owner_from_url "$url"
}

# Parse an owner login out of a github.com URL (https or ssh form).
_ghas_owner_from_url() {
  local url="$1" slug
  slug="$(printf '%s' "$url" | grep -oiE 'github\.com[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 \
            | sed -E 's#^github\.com[:/]##')"
  [ -n "$slug" ] || return 1
  printf '%s' "${slug%%/*}"
}

# Extract the remote NAME argument from a `git push <remote> ...` command
# (defaults to "origin" if git push has no explicit remote arg, matching
# git's own default-remote behavior).
_ghas_git_push_remote_name() {
  local cmd="$1" after remote
  after="$(printf '%s' "$cmd" | sed -E 's/^.*git[[:space:]]+push[[:space:]]*//')"
  # First non-flag token is the remote name, if present.
  remote="$(printf '%s' "$after" | grep -oE '^[A-Za-z0-9_.-]+' | head -1)"
  if [ -z "$remote" ]; then remote="origin"; fi
  printf '%s' "$remote"
}

# cwd repo's "origin" owner (fallback for gh subcommands with no --repo).
_ghas_owner_from_cwd_origin() {
  local cwd="$1" url
  command -v git >/dev/null 2>&1 || return 1
  url="$(git -C "$cwd" remote get-url origin 2>/dev/null)" || return 1
  _ghas_owner_from_url "$url"
}

# Full resolution chain. Echoes owner or empty (no-op) on failure.
_ghas_resolve_target_owner() {
  local cmd="$1" cwd="$2" owner remote

  owner="$(_ghas_extract_repo_flag_owner "$cmd")" && [ -n "$owner" ] && { printf '%s' "$owner"; return 0; }

  if _ghas_is_git_push "$cmd"; then
    remote="$(_ghas_git_push_remote_name "$cmd")"
    owner="$(_ghas_owner_from_remote_name "$cwd" "$remote")" && [ -n "$owner" ] && { printf '%s' "$owner"; return 0; }
    return 1
  fi

  # gh subcommand with no explicit --repo: gh resolves against cwd's origin.
  owner="$(_ghas_owner_from_cwd_origin "$cwd")" && [ -n "$owner" ] && { printf '%s' "$owner"; return 0; }
  return 1
}

# ============================================================
# The switch itself — idempotent, never blocks.
# ============================================================

# Emit a ledger warn line (gate=gh-account-autoswitch). `warn` is an
# already-mapped event type in observability-consumer-map.json (consumers:
# digest:feed_ledger_summary, kpi:harness-kpis.sh) — no new event type
# needed for this to be observable.
_ghas_emit() {
  local detail="$1"
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "gh-account-autoswitch" "warn" "$detail"
  fi
}

# Perform the switch. GHAS_GH_CMD lets self-test point at a stub `gh`
# without touching PATH; production uses the real `gh` on PATH.
_ghas_gh_bin() { printf '%s' "${GHAS_GH_CMD:-gh}"; }

_ghas_do_switch() {
  local owner="$1" active="$2"
  local gh_bin
  gh_bin="$(_ghas_gh_bin)"
  command -v "$gh_bin" >/dev/null 2>&1 || return 1
  "$gh_bin" auth switch -u "$owner" >/dev/null 2>&1
  _ghas_emit "switched gh account ${active:-<unknown>} -> ${owner} (pre-emptive, before command executed)"
  return 0
}

# ============================================================
# Main decision logic (pure — testable without stdin/JSON wrapping).
# ============================================================

_ghas_run() {
  local cmd cwd owner active required

  cmd="$(_ghas_command)"
  [ -n "$cmd" ] || { exit 0; }
  _ghas_is_gh_or_git "$cmd" || { exit 0; }
  _ghas_is_write_scope "$cmd" || { exit 0; }

  cwd="$(_ghas_cwd)"
  owner="$(_ghas_resolve_target_owner "$cmd" "$cwd")"
  [ -n "$owner" ] || { exit 0; }   # unresolvable owner -> no-op, exit 0

  required="$(gh_account_for_owner "$owner")"
  [ -n "$required" ] || { exit 0; }   # owner not a known account -> can't act

  active="$(gh_active_account)"
  [ -n "$active" ] || { exit 0; }     # can't determine active account -> no-op

  if gh_ci_eq "$active" "$required"; then
    exit 0   # already correct account -> no-op (idempotent)
  fi

  _ghas_do_switch "$required" "$active"
  exit 0
}

# ============================================================
# Self-test
# ============================================================
#
# Sandboxes `gh` via GHAS_GH_CMD pointing at a recording stub script (never
# touches real gh auth state). Sandboxes accounts.config.json via
# GHBLIND_ACCOUNTS (shared env var name with gh-account-lib.sh). Sandboxes
# the ledger via HARNESS_SELFTEST=1 + explicit SIGNAL_LEDGER_PATH.

_ghas_self_test() {
  local pass=0 fail=0 tmp cfg stub gitrepo got calls

  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ghas)"
  cfg="$tmp/accounts.config.json"
  cat > "$cfg" <<'JSON'
{
  "work":     [ { "gh_user": "alice-at-acme",     "owners": ["acme-org"] } ],
  "personal": [ { "gh_user": "alice-example" } ]
}
JSON

  # Recording gh stub: `gh auth switch -u <user>` appends "switch <user>" to
  # a calls file; anything else no-ops with exit 0.
  stub="$tmp/gh-stub.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
CALLS_FILE="${GHAS_STUB_CALLS:-/dev/null}"
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "switch" ]; then
  echo "switch ${4:-$3}" >> "$CALLS_FILE"
  exit 0
fi
exit 0
STUB
  chmod +x "$stub" 2>/dev/null || true

  export HARNESS_SELFTEST=1
  export SIGNAL_LEDGER_PATH="$tmp/ledger.jsonl"

  # A throwaway git repo with origin=work-owned, personal=personal-owned,
  # for git-push remote-name resolution tests.
  gitrepo="$tmp/repo"
  mkdir -p "$gitrepo"
  ( cd "$gitrepo" && git init -q 2>/dev/null \
      && git remote add origin "https://github.com/acme-org/neural-lace.git" 2>/dev/null \
      && git remote add personal "https://github.com/alice-example/neural-lace.git" 2>/dev/null )

  _case() {
    local name="$1" active="$2" cmd="$3" cwd="$4" expect_switch_to="$5"
    calls="$tmp/calls-$RANDOM.txt"
    : > "$calls"
    got="$(GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="$active" GHAS_GH_CMD="$stub" GHAS_STUB_CALLS="$calls" \
           GHAS_CMD="$cmd" GHAS_CWD="$cwd" bash "$0")"
    local out; out="$(cat "$calls" 2>/dev/null)"
    if [ -n "$expect_switch_to" ]; then
      if printf '%s' "$out" | grep -q "switch $expect_switch_to"; then
        echo "  $name: PASS"; pass=$((pass+1))
      else
        echo "  $name: FAIL (calls: [$out])"; fail=$((fail+1))
      fi
    else
      if [ -z "$out" ]; then
        echo "  $name: PASS (no switch, as expected)"; pass=$((pass+1))
      else
        echo "  $name: FAIL (unexpected switch: [$out])"; fail=$((fail+1))
      fi
    fi
  }

  # S1 — personal-repo merge from work-active -> switches to alice-example.
  _case "S1 personal-repo merge from work-active -> switches" "alice-at-acme" \
    "gh pr merge --repo alice-example/neural-lace 42" "$gitrepo" "alice-example"

  # S2 — work-repo push from personal-active -> switches to alice-at-acme.
  _case "S2 work-repo push from personal-active -> switches" "alice-example" \
    "git push origin build/foo" "$gitrepo" "alice-at-acme"

  # S3 — already-correct account -> no-op.
  _case "S3 already-correct account -> no-op" "alice-example" \
    "gh pr merge --repo alice-example/neural-lace 42" "$gitrepo" ""

  # S4 — unresolvable owner -> no-op exit 0 (no --repo, no git repo cwd).
  _case "S4 unresolvable owner -> no-op" "alice-at-acme" \
    "gh pr list" "$tmp" ""

  # S5 — read-only op (gh pr list, resolvable owner but read-only scope) -> no switch.
  _case "S5 read-only op -> no switch" "alice-example" \
    "gh pr list --repo acme-org/neural-lace" "$gitrepo" ""

  # S6 — gh pr view (in-scope per spec: 404-prone read) on wrong-account repo -> switches.
  _case "S6 gh pr view wrong-account -> switches" "alice-at-acme" \
    "gh pr view --repo alice-example/neural-lace 7" "$gitrepo" "alice-example"

  # S7 — flagless shape: real PreToolUse stdin JSON (tool_input.command + cwd).
  calls="$tmp/calls-flagless.txt"; : > "$calls"
  local json_payload
  json_payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --repo alice-example/neural-lace 9"},"cwd":"%s"}' "$gitrepo")
  got="$(printf '%s' "$json_payload" | GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="alice-at-acme" GHAS_GH_CMD="$stub" GHAS_STUB_CALLS="$calls" bash "$0")"
  if grep -q "switch alice-example" "$calls" 2>/dev/null; then
    echo "  S7 flagless PreToolUse stdin JSON shape -> switches: PASS"; pass=$((pass+1))
  else
    echo "  S7 flagless PreToolUse stdin JSON shape -> switches: FAIL (calls: [$(cat "$calls" 2>/dev/null)])"; fail=$((fail+1))
  fi

  # S8 — non-gh/git command -> no-op, never touches gh.
  _case "S8 non-gh command -> no-op" "alice-at-acme" "npm test" "$gitrepo" ""

  # S9 — ledger emits a warn line on an actual switch.
  rm -f "$SIGNAL_LEDGER_PATH"
  calls="$tmp/calls-ledger.txt"; : > "$calls"
  GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="alice-at-acme" GHAS_GH_CMD="$stub" GHAS_STUB_CALLS="$calls" \
    GHAS_CMD="gh pr merge --repo alice-example/neural-lace 1" GHAS_CWD="$gitrepo" bash "$0" >/dev/null
  if [ -f "$SIGNAL_LEDGER_PATH" ] && grep -q '"gate":"gh-account-autoswitch"' "$SIGNAL_LEDGER_PATH" && grep -q '"event":"warn"' "$SIGNAL_LEDGER_PATH"; then
    echo "  S9 signal-ledger warn emitted on switch: PASS"; pass=$((pass+1))
  else
    echo "  S9 signal-ledger warn emitted on switch: FAIL"; fail=$((fail+1))
  fi

  # S10 — idempotent: two consecutive wrong-account commands only switch once
  # each time they're actually wrong (i.e. re-running against an
  # already-switched-to account is a no-op the second time).
  calls="$tmp/calls-idem.txt"; : > "$calls"
  GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="alice-at-acme" GHAS_GH_CMD="$stub" GHAS_STUB_CALLS="$calls" \
    GHAS_CMD="gh pr merge --repo alice-example/neural-lace 1" GHAS_CWD="$gitrepo" bash "$0" >/dev/null
  GHBLIND_ACCOUNTS="$cfg" GHBLIND_ACTIVE="alice-example" GHAS_GH_CMD="$stub" GHAS_STUB_CALLS="$calls" \
    GHAS_CMD="gh pr merge --repo alice-example/neural-lace 2" GHAS_CWD="$gitrepo" bash "$0" >/dev/null
  local n_switches; n_switches="$(grep -c '^switch ' "$calls" 2>/dev/null || echo 0)"
  if [ "$n_switches" = "1" ]; then
    echo "  S10 idempotent — second (already-correct) call performs no extra switch: PASS"; pass=$((pass+1))
  else
    echo "  S10 idempotent: FAIL (expected 1 switch total, got $n_switches; calls: [$(cat "$calls")])"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null
  unset HARNESS_SELFTEST SIGNAL_LEDGER_PATH
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --self-test) _ghas_self_test; exit $? ;;
  -h|--help)
    cat <<'GHAS_USAGE' >&2
gh-account-autoswitch.sh — proactively switch gh account before a gh/git
command targeting the OTHER account's repo runs.

  gh-account-autoswitch.sh             # PreToolUse: reads JSON on stdin
  gh-account-autoswitch.sh --self-test # run self-test suite

Resolves the target owner from (in order): --repo/-R flag, the named git
remote's URL (git push), the cwd repo's origin owner. If that owner maps to
a DIFFERENT gh account than the one currently active, runs
`gh auth switch -u <owner>` before the tool call proceeds. Never blocks
(always exits 0). Read-only gh/git commands are excluded. Owner->account
mapping shared with gh-account-blindness-hint.sh via
hooks/lib/gh-account-lib.sh; config at ~/.claude/local/accounts.config.json.
GHAS_USAGE
    exit 2
    ;;
  "") _ghas_read_payload; _ghas_run ;;
  *)
    echo "gh-account-autoswitch.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
