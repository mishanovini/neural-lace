#!/usr/bin/env bash
# gh-commit-author-identity-gate.sh — PreToolUse (matcher "Bash"): BLOCK a
# commit-creating git invocation (`commit`, `commit-tree`, `merge`,
# `cherry-pick`, `revert`, `pull`, `rebase`, `am`) whose command overrides
# author/committer EMAIL to something other than the identity expected for
# the repo it targets, on a repo with a resolvable github.com remote.
#
# ============================================================
# WHY THIS EXISTS (GH-COMMIT-IDENTITY-01, operator directive 2026-09-27,
# golden scenario)
# ============================================================
#
# 2026-09-21, on a downstream project's PR: fixer subagents committed with author
# `<session-context-email>@example.test` — the session's "user email" context
# value that Claude Code hands every agent "for authorship." The repo's own
# git config was already correct (a real, project-specific address in
# `.git/config`; a `users.noreply.github.com` address globally), so the
# agent(s) must have passed the author explicitly. Vercel maps commit emails
# to Vercel users and blocked the deploy ("Deployment was blocked"); cost
# ~1 hour. The session's context email has since changed to yet ANOTHER
# address, so this is a structural, recurring risk, not a one-off.
#
# Operator directive, verbatim (2026-09-27): "set things to always use the
# email that's logged into GH instead of the email used to log into Claude."
#
# THIS GATE is the enforcement half. hooks/lib/gh-commit-identity-lib.sh is
# the resolution half (see that file's header for the full resolution
# chain and why it never falls back to a synthesized noreply guess).
#
# ============================================================
# WHAT IT BLOCKS
# ============================================================
# A `git commit`, `commit-tree`, `merge`, `cherry-pick`, `revert`, `pull`,
# `rebase`, or `am` invocation (M1, PR #67 review, PROVEN: a real downstream
# project transcript ran `git -c user.name=… -c user.email=… merge -q --no-ff
# origin/master -m "Merge origin/master"`, and that project's own merge
# procedure makes merge the MOST FREQUENT commit-creating path, not an
# edge case — commit-tree is separately in scope even though
# hooks/lib/git-command-parse.sh's own gcp_resolve_commit_target
# deliberately excludes it for ITS callers; this gate tokenizes and walks
# each git segment itself rather than reusing that function's IS_COMMIT
# verdict) that overrides identity via ANY of:
#   - `--author=<name> <email>` (or separated `--author <value>`) whose
#     <email> does not match the expected email — `commit` ONLY; none of
#     the other verbs above accept `--author`
#   - `-c user.email=<val>` (separated or glued `-c<key>=<val>`) mismatch,
#     on ANY of the verbs above (`-c` is a global git flag)
#   - `GIT_AUTHOR_EMAIL=` / `GIT_COMMITTER_EMAIL=`, whether set as a
#     command-scoped prefix on the commit-creating segment itself
#     (`FOO=bar git commit`), via an earlier `export FOO=bar` segment in
#     the SAME command, or via an `env FOO=bar git commit` prefix — but
#     NOT an env var exported in a DIFFERENT, earlier Bash tool call (a
#     named, accepted residual: this hook only ever sees one command at a
#     time)
#   - a plain `git config user.email <val>` (or `--local`/`--worktree`
#     scoped) SET earlier in the SAME command, persisting into a LATER
#     commit-creating segment with no override of its own (m1, PR #67
#     review: "the likely path when an agent answers git's 'please tell
#     me who you are' prompt") — an explicit override on the commit
#     segment itself still wins, matching git's own last-wins semantics
#
# `-c user.name=<val>` / `GIT_AUTHOR_NAME=` / `GIT_COMMITTER_NAME=` are
# checked too, but NEVER block on their own (see WHAT IT ALLOWS below).
#
# The target repo is resolved the same way git itself would (`-C`,
# `--work-tree`, `--git-dir`, accumulated `cd`/`pushd`, in that priority),
# so `git -C <other-repo> commit --author=...` is judged against
# <other-repo>'s expected identity, not the invoking cwd's.
#
# ============================================================
# WHAT IT ALLOWS
# ============================================================
#   - Any commit-creating command with no identity override at all (the
#     overwhelming case), and any command NOT in the verb list above
#     (`git status`, `git log --author=…`, etc — never touched).
#   - An override that MATCHES the expected identity (case-insensitive on
#     email — not an override in effect, just spelling it out explicitly).
#   - A NAME-only mismatch (`-c user.name=`, `GIT_AUTHOR_NAME=`,
#     `GIT_COMMITTER_NAME=`) with no accompanying EMAIL mismatch (m2, PR
#     #67 review: Vercel and GitHub attribute commits by EMAIL, not
#     display name — blocking on name alone adds false-positive surface
#     with no attribution benefit). Still visible: logged as a
#     signal-ledger `warn`, never silently dropped.
#   - `GIT_COMMIT_IDENTITY_GATE_ACK=1` present anywhere in the same
#     resolution chain that fed a candidate override (command-scoped prefix,
#     or an earlier `export`) — the ONE sanctioned escape, for the genuine
#     case of committing on someone else's behalf (e.g. preserving original
#     authorship on a manually-applied patch). Per constitution §7, this is
#     for the user's explicit, in-conversation say-so — never set
#     preemptively by an agent to talk itself past this gate. Every ack use
#     is logged (ledger event "waiver"), so a pattern of acks is visible to
#     later review, not silently invisible.
#   - A target directory with NO resolvable github.com remote owner at all
#     (M4, PR #67 review, PROVEN false positive: a throwaway `git init`
#     scratch/fixture repo with its own local identity was compared
#     against whatever this MACHINE's global `~/.gitconfig` happened to
#     hold — there is no repo-level GitHub identity to enforce there).
#     Fails OPEN completely: no check, no auto-set.
#   - When a github.com remote owner IS resolvable but NO expected email
#     can be resolved for it (the owner is not mapped in this machine's
#     `~/.claude/local/accounts.config.json`, AND the repo carries no git
#     config identity of its own) -> fails OPEN. There is no ground truth
#     to check an override against, and never fabricates one to check
#     against (see the lib's noreply-never-used guarantee). NOTE (M3, PR
#     #67 review): the gh-API rung requires that config file to carry a
#     REAL owner->account mapping — on a machine where it still holds only
#     the shipped placeholder entries, every resolution falls to the
#     git-config fallback rung, and this is surfaced as a signal-ledger
#     `warn` (not silent) rather than assumed to be the gh-API path.
#
# ============================================================
# OPTIONAL SIDE EFFECT (operator's call, documented rationale)
# ============================================================
# When a commit-creating segment carries NO override at all, and the
# target repo has NO `user.email` configured at ANY level (neither local nor
# global), and an expected email WAS resolved via the gh API (not the
# fallback — the fallback rung requires config to already exist, so by
# construction it cannot fire here) -> this gate sets `user.email` on that
# repo, ONCE, and logs a signal-ledger `warn` plus a best-effort stderr note.
# Rationale: an unconfigured worktree committing under whatever ambient
# identity git falls back to (which can be wrong, or can error outright) is
# the exact same class of problem this gate exists to prevent, just via a
# different path (an ABSENT identity instead of an OVERRIDDEN one) — fixing
# it once, quietly, at the point where the correct value is already in hand,
# is cheaper than blocking every future commit from that worktree. m6 (PR
# #67 review): the stderr note is a best-effort courtesy, not a guarantee —
# PreToolUse stderr on a non-blocking (exit 0) path is not guaranteed
# visible to the agent transcript. The signal ledger, not the stderr note,
# is the reliable record.
#
# ============================================================
# NEVER BLOCKS ON:
# ============================================================
#   - a command matching NONE of the commit-creating verb substrings
#     ("commit", "merge", "cherry-pick", "revert", "pull", "rebase", " am")
#     anywhere in the RAW payload text, checked BEFORE sourcing any
#     library (m4, PR #67 review: this hook fires on every Bash call, so
#     the non-matching fast path must stay cheap). " am" (space-prefixed)
#     is deliberately loose — "am" alone is too short/common a substring
#     to check precisely with a case pattern, so this errs toward a
#     FALSE POSITIVE (occasionally sourcing libraries for an unrelated
#     command containing the word "am", e.g. a commit message reading "I
#     am done") rather than a FALSE NEGATIVE (ever skipping a real `git
#     am`) — resolves toward DETECTION, not silence, the same posture
#     git-command-parse.sh's own prefilter documents. A command matching
#     one of these substrings is NOT guaranteed to actually BE one of
#     these verbs (that precise determination is the tokenizer/parser
#     below); this is a cheap superset filter, not the real check.
#   - a target directory with no resolvable github.com remote owner (M4)
#   - internal limitation (no jq available for payload parsing when
#     CLAUDE_TOOL_INPUT/stdin carries no usable command text; no git binary)
#
# ============================================================
# NAMED RESIDUALS (m1, PR #67 review — NOT closed, deliberately, cost vs.
# realistic likelihood; each is a real bypass, named rather than hidden)
# ============================================================
#   - `bash -c '…git commit --author=…'` — an arbitrarily-quoted nested
#     shell command is not recursively re-parsed. Same class of gap
#     git-command-parse.sh's own obfuscated-verb prefilter already
#     documents for its callers.
#   - `git --config-env=user.email=SOME_ENV_VAR_NAME commit` — the
#     EFFECTIVE value lives in whatever `$SOME_ENV_VAR_NAME` resolves to
#     at runtime, which is only visible to this hook when that SPECIFIC
#     var name happens to also be one of the 4 tracked GIT_* vars set
#     earlier in the same command (it usually is not).
#   - `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.email
#     GIT_CONFIG_VALUE_0=<val> git commit` — git's alternate indexed
#     config-injection mechanism; not parsed.
#
# Self-test: bash gh-commit-author-identity-gate.sh --self-test

set -u

_GCIA_ARGV1="${1:-}"

# ============================================================
# m4 (PR #67 review, 2026-09-28): cheapest possible prefilter, BEFORE
# sourcing anything. This hook fires on EVERY Bash tool call. Reading the
# raw payload and checking for any commit-creating-verb substring before
# loading 5 library files (jq parse + sourcing cost) means the
# overwhelmingly common non-matching call pays almost nothing. Measured
# before this fix: a non-commit call like `ls -la` cost ~0.5-1.1s with this
# hook wired, vs ~0.5-0.76s for the comparable gh-account-autoswitch.sh.
# A raw substring check on the WHOLE payload is a safe superset of
# checking just the parsed .tool_input.command field: if none of these
# substrings is anywhere in the raw text, none can be inside a substring
# of that text either. MUST list every verb M1 added (merge/cherry-pick/
# revert/pull/rebase/am) — checking only "commit" here would silently
# skip those verbs entirely (the exact bug this comment now documents so
# it is not reintroduced by only adding a verb inside the parser below
# without also widening this prefilter). Only the plain (no-arg)
# invocation path reads stdin here — --self-test/--help never touch it,
# exactly as before this change.
# ============================================================
if [ -z "$_GCIA_ARGV1" ]; then
  if [ -n "${GCIA_CMD:-}" ]; then
    _GCIA_RAW="$GCIA_CMD"
  elif [ -n "${CLAUDE_TOOL_INPUT:-}" ]; then
    _GCIA_RAW="$CLAUDE_TOOL_INPUT"
  else
    _GCIA_RAW="$(cat 2>/dev/null || true)"
  fi
  case "$_GCIA_RAW" in
    *commit*|*merge*|*cherry-pick*|*revert*|*pull*|*rebase*|*' am'*) : ;;
    *) exit 0 ;;
  esac
fi

_GCIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
. "${_GCIA_DIR}/lib/git-command-parse.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${_GCIA_DIR}/lib/gh-account-lib.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${_GCIA_DIR}/lib/gh-commit-identity-lib.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${_GCIA_DIR}/lib/gate-contract-lib.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${_GCIA_DIR}/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================
# Payload reading — mirrors gh-account-autoswitch.sh's shape (the real
# PreToolUse stdin JSON: .tool_input.command / .cwd), plus CLAUDE_TOOL_INPUT
# env-var and GCIA_CMD/GCIA_CWD self-test overrides. The raw payload was
# already read by the m4 prefilter above (for the plain invocation path);
# this just hands it to the JSON-field extractors below instead of
# re-reading stdin a second time (which would hang — stdin is consumed
# exactly once).
# ============================================================

_gcia_read_payload() {
  _GCIA_PAYLOAD="${_GCIA_RAW:-}"
}

_gcia_command() {
  if [ -n "${GCIA_CMD:-}" ]; then printf '%s' "$GCIA_CMD"; return 0; fi
  if command -v jq >/dev/null 2>&1 && [ -n "${CLAUDE_TOOL_INPUT:-}" ]; then
    local v; v="$(printf '%s' "$CLAUDE_TOOL_INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  local payload="${_GCIA_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    printf '%s' "$payload" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true
  else
    printf '%s' "$payload"
  fi
}

_gcia_cwd() {
  if [ -n "${GCIA_CWD:-}" ]; then printf '%s' "$GCIA_CWD"; return 0; fi
  if command -v jq >/dev/null 2>&1 && [ -n "${CLAUDE_TOOL_INPUT:-}" ]; then
    local v; v="$(printf '%s' "$CLAUDE_TOOL_INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  local payload="${_GCIA_PAYLOAD:-}"
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    local c; c="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
    [ -n "$c" ] && { printf '%s' "$c"; return 0; }
  fi
  printf '%s' "$PWD"
}

# ============================================================
# Tracked env vars (the 4 identity vars + the ack), noted as assignments are
# encountered walking the command left-to-right — mirrors real shell
# semantics: an assignment earlier in the command is visible to everything
# after it in the SAME command.
# ============================================================

_gcia_reset_env_state() {
  _GCIA_ACK=0
  _GCIA_ENV_AUTHOR_EMAIL=""; _GCIA_ENV_COMMITTER_EMAIL=""
  _GCIA_ENV_AUTHOR_NAME=""; _GCIA_ENV_COMMITTER_NAME=""
}

_gcia_note_env_assignment() { # <name> <value>
  case "$1" in
    GIT_AUTHOR_EMAIL) _GCIA_ENV_AUTHOR_EMAIL="$2" ;;
    GIT_COMMITTER_EMAIL) _GCIA_ENV_COMMITTER_EMAIL="$2" ;;
    GIT_AUTHOR_NAME) _GCIA_ENV_AUTHOR_NAME="$2" ;;
    GIT_COMMITTER_NAME) _GCIA_ENV_COMMITTER_NAME="$2" ;;
    GIT_COMMIT_IDENTITY_GATE_ACK) [ "$2" = "1" ] && _GCIA_ACK=1 ;;
  esac
}

# Recognize `export NAME=VALUE [NAME2=VALUE2 ...]` segments (which
# gcp_strip_env_assignments_var deliberately does NOT treat as assignments —
# "export" itself has no `=`) and note each NAME=VALUE the same way a
# command-scoped assignment would be noted. Quote-aware via the shared
# tokenizer (a value may be quoted: `export GIT_AUTHOR_EMAIL="a b"`).
# Returns 0 iff the segment WAS an export (caller should `continue`, not
# fall through to git-segment parsing).
_gcia_maybe_export() {
  local seg="$1" rest tok name val k n
  case "$seg" in
    export|export[[:space:]]*) : ;;
    *) return 1 ;;
  esac
  rest="${seg#export}"
  gcp_tokenize_segment "$rest"
  n=${#GCP_SEG_TOKENS[@]}
  for ((k=0; k<n; k++)); do
    tok="${GCP_SEG_TOKENS[$k]}"
    case "$tok" in
      [A-Za-z_]*=*)
        name="${tok%%=*}"
        case "$name" in *[!A-Za-z0-9_]*) continue ;; esac
        val="${tok#*=}"
        _gcia_note_env_assignment "$name" "$val"
        ;;
    esac
  done
  return 0
}

# m1 (PR #67 review): `env NAME=VALUE... cmd` is functionally identical to
# a command-scoped prefix (`NAME=VALUE cmd`) but gcp_strip_env_assignments_var
# does not recognize it — the literal word "env" has no `=`, so it never
# matched the leading-assignment scan. If the segment starts with a bare
# "env" token, strip it and let the SAME assignment-stripping logic the
# caller already runs handle the NAME=VALUE pairs that follow, exactly as
# it already does for a plain command-scoped prefix. Does not attempt to
# parse env's OWN flags (`env -i ...`) — a named, accepted narrowing.
_gcia_strip_env_prefix() { # <segment> -> stdout: segment with "env " stripped
  local seg="$1" rest
  case "$seg" in
    env|env[[:space:]]*)
      rest="${seg#env}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      printf '%s' "$rest"
      ;;
    *) printf '%s' "$seg" ;;
  esac
}

# m1 (PR #67 review): recognize a plain `git config user.email <value>` /
# `git config user.name <value>` SET — not --get/--unset/--list — optionally
# scoped `--local`/`--worktree`. This is "the likely path when an agent
# answers git's 'please tell me who you are' prompt": a config SET followed
# by a plain `git commit` in the same command carries no override on the
# commit segment itself, so without this the identity change is invisible
# to the gate. `--global`/`--system` scope is deliberately NOT recognized —
# a machine-wide config change is a different, larger-blast-radius action
# outside this per-repo gate's scope. Also deliberately narrow: does not
# handle `-C`/global `-c` flags glued onto the `git config` invocation
# itself (a named, accepted simplification — the plain form is the
# overwhelmingly common shape). Sets _GCIA_CFGSET_KEY/_GCIA_CFGSET_VAL and
# returns 0 on a match; returns 1 (no output vars touched) otherwise.
_gcia_maybe_config_set() { # <segment starting with "git">
  local seg="$1"
  gcp_tokenize_segment "$seg"
  local n=${#GCP_SEG_TOKENS[@]} i
  [ "$n" -ge 4 ] || return 1
  [ "${GCP_SEG_TOKENS[0]}" = "git" ] || return 1
  [ "${GCP_SEG_TOKENS[1]}" = "config" ] || return 1
  i=2
  while [ "$i" -lt "$n" ]; do
    case "${GCP_SEG_TOKENS[$i]}" in
      --local|--worktree) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  case "${GCP_SEG_TOKENS[$i]}" in
    user.email) _GCIA_CFGSET_KEY="user.email" ;;
    user.name) _GCIA_CFGSET_KEY="user.name" ;;
    *) return 1 ;;
  esac
  i=$((i+1))
  [ "$i" -lt "$n" ] || return 1
  _GCIA_CFGSET_VAL="${GCP_SEG_TOKENS[$i]}"
  return 0
}

# ============================================================
# Per-git-segment analysis. Extends gcp_analyze_git_segment (which stops the
# instant it sees the subcommand word, and treats commit-tree as NOT a
# commit) with: commit-tree recognition, `-c` VALUE capture (not skip), and
# continued scanning past the subcommand for `--author`.
# ============================================================

_gcia_note_cfg() { # <token like "user.email=x@y.test">
  local kv="$1" key val
  case "$kv" in
    *=*) key="${kv%%=*}"; val="${kv#*=}" ;;
    *) return 0 ;;
  esac
  case "$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')" in
    user.email) _GCIA_CFG_EMAIL="$val" ;;
    user.name) _GCIA_CFG_NAME="$val" ;;
  esac
}

# Sets: _GCIA_IS_TARGET (1 iff subcommand is commit or commit-tree),
# _GCIA_TARGET_DIR, _GCIA_CFG_EMAIL, _GCIA_CFG_NAME, _GCIA_AUTHOR_VAL.
_gcia_analyze_segment() { # <segment starting with "git"> <base-dir>
  local seg="$1" base="$2"
  _GCIA_IS_TARGET=0; _GCIA_TARGET_DIR=""; _GCIA_CFG_EMAIL=""; _GCIA_CFG_NAME=""; _GCIA_AUTHOR_VAL=""
  gcp_tokenize_segment "$seg"
  local n=${#GCP_SEG_TOKENS[@]} i tok sub="" c_target="" work_tree="" git_dir=""
  [ "$n" -ge 2 ] || return 0
  [ "${GCP_SEG_TOKENS[0]}" = "git" ] || return 0

  i=1
  while [ "$i" -lt "$n" ]; do
    tok="${GCP_SEG_TOKENS[$i]}"
    case "$tok" in
      -C)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        c_target="$(gcp_compose_dir "$c_target" "$base" "${GCP_SEG_TOKENS[$i]}")"
        ;;
      -C?*) c_target="$(gcp_compose_dir "$c_target" "$base" "${tok:2}")" ;;
      --work-tree=?*) work_tree="$(gcp_compose_dir "" "$base" "${tok#--work-tree=}")" ;;
      --git-dir=?*) git_dir="$(gcp_compose_dir "" "$base" "${tok#--git-dir=}")" ;;
      --work-tree)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        work_tree="$(gcp_compose_dir "" "$base" "${GCP_SEG_TOKENS[$i]}")"
        ;;
      --git-dir)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        git_dir="$(gcp_compose_dir "" "$base" "${GCP_SEG_TOKENS[$i]}")"
        ;;
      -c)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        _gcia_note_cfg "${GCP_SEG_TOKENS[$i]}"
        ;;
      -c?*) _gcia_note_cfg "${tok#-c}" ;;
      --namespace) i=$((i+1)) ;;
      -*) : ;;
      *) sub="$tok"; break ;;
    esac
    i=$((i+1))
  done

  # M1 (PR #67 review, PROVEN): identity overrides on every OTHER
  # commit-creating subcommand passed the gate — a real downstream project
  # session transcript ran `git -c user.name=… -c user.email=… merge -q
  # --no-ff origin/master -m "Merge origin/master"`, and that project's own
  # merge procedure ("merge origin/master into the branch") makes merge commits
  # the most frequent commit-creating path of all, not an edge case. `-c`
  # is a GLOBAL git flag (already captured in phase 1 above regardless of
  # subcommand), so the fix is simply widening which subcommands count as
  # identity-bearing. `--author` stays commit-only below — none of these
  # other verbs accept that flag (cherry-pick preserves original
  # authorship automatically; git itself errors on `--author` elsewhere).
  case "$sub" in
    commit|commit-tree|merge|cherry-pick|revert|pull|rebase|am) _GCIA_IS_TARGET=1 ;;
    *) return 0 ;;
  esac

  if [ -n "$work_tree" ]; then _GCIA_TARGET_DIR="$work_tree"
  elif [ -n "$git_dir" ]; then _GCIA_TARGET_DIR="${git_dir%/.git}"
  elif [ -n "$c_target" ]; then _GCIA_TARGET_DIR="$c_target"
  else _GCIA_TARGET_DIR="$base"
  fi

  # Phase 2: subcommand-level flags — only --author matters here, and only
  # for `commit` itself (see the M1 note above: no other verb in scope
  # accepts --author).
  if [ "$sub" = "commit" ]; then
    i=$((i+1))
    while [ "$i" -lt "$n" ]; do
      tok="${GCP_SEG_TOKENS[$i]}"
      case "$tok" in
        --author=?*) _GCIA_AUTHOR_VAL="${tok#--author=}" ;;
        --author)
          i=$((i+1)); [ "$i" -lt "$n" ] && _GCIA_AUTHOR_VAL="${GCP_SEG_TOKENS[$i]}"
          ;;
      esac
      i=$((i+1))
    done
  fi
  return 0
}

# ============================================================
# Evaluate one commit/commit-tree segment: resolve expected identity for its
# target dir, perform the (optional) auto-set side effect, and check every
# override kind. Sets _GCIA_VIOLATION (0|1) and, on 1, the detail fields
# used by the block message.
# ============================================================

_gcia_evaluate() { # <target_dir> <cfg_email> <cfg_name> <author_val>
  local target_dir="$1" cfg_email="$2" cfg_name="$3" author_val="$4"
  _GCIA_VIOLATION=0
  _GCIA_AUTO_SET_NOTE=""

  # M4 (PR #67 review, PROVEN false positive): a repo with NO resolvable
  # github.com remote owner has no GitHub ground truth to check against.
  # Without this guard, a throwaway `git init` scratch/fixture repo with
  # its own local throwaway identity got compared against whatever this
  # MACHINE's global ~/.gitconfig happens to hold — not "the account
  # logged in for the repo" (there is no repo-level GH identity at all,
  # so there is nothing this gate can legitimately enforce). Fail open
  # completely: no check, no auto-set. A real transcript escaped this
  # only because the cwd could not be resolved when the hook ran — this
  # closes that gap structurally rather than by accident.
  if [ -z "$(gh_owner_from_cwd_remote "$target_dir" 2>/dev/null)" ]; then
    return 0
  fi

  gia_resolve_expected_email "$target_dir"
  local expected_email="$GIA_EMAIL" expected_source="$GIA_EMAIL_SOURCE"

  if [ "${_GCIA_ACK:-0}" = "1" ]; then
    ledger_emit "gh-commit-author-identity" "waiver" "GIT_COMMIT_IDENTITY_GATE_ACK=1 present; override allowed through for target_dir=${target_dir}"
    return 0
  fi

  if [ -z "$expected_email" ]; then
    # Nothing resolvable at all -> nothing to check, nothing to auto-set.
    return 0
  fi

  local bad_kind="" bad_val=""

  if [ -n "$author_val" ]; then
    local a_email=""
    case "$author_val" in
      *"<"*">"*) a_email="${author_val#*<}"; a_email="${a_email%%>*}" ;;
    esac
    if [ -z "$a_email" ] || ! gh_ci_eq "$a_email" "$expected_email"; then
      bad_kind="--author"; bad_val="$author_val"
    fi
  fi

  if [ -z "$bad_kind" ] && [ -n "$cfg_email" ] && ! gh_ci_eq "$cfg_email" "$expected_email"; then
    bad_kind="-c user.email"; bad_val="$cfg_email"
  fi

  if [ -z "$bad_kind" ] && [ -n "${_GCIA_ENV_AUTHOR_EMAIL:-}" ] && ! gh_ci_eq "$_GCIA_ENV_AUTHOR_EMAIL" "$expected_email"; then
    bad_kind="GIT_AUTHOR_EMAIL"; bad_val="$_GCIA_ENV_AUTHOR_EMAIL"
  fi

  if [ -z "$bad_kind" ] && [ -n "${_GCIA_ENV_COMMITTER_EMAIL:-}" ] && ! gh_ci_eq "$_GCIA_ENV_COMMITTER_EMAIL" "$expected_email"; then
    bad_kind="GIT_COMMITTER_EMAIL"; bad_val="$_GCIA_ENV_COMMITTER_EMAIL"
  fi

  # m2 (PR #67 review): a NAME-only mismatch is WARNED, never BLOCKED.
  # Vercel and GitHub attribute commits by EMAIL, not display name — the
  # directive this gate exists for ("use the email that's logged into
  # GH") is about email specifically, and blocking on a name mismatch adds
  # false-positive surface with no attribution benefit. Still visible
  # (signal ledger), never silent; only reached when no EMAIL-based
  # bad_kind was already set above (an email mismatch always wins).
  if [ -z "$bad_kind" ] && { [ -n "$cfg_name" ] || [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] || [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ]; }; then
    gia_resolve_expected_name "$target_dir"
    local expected_name="$GIA_NAME"
    if [ -n "$expected_name" ]; then
      local name_bad_kind="" name_bad_val=""
      if [ -n "$cfg_name" ] && [ "$cfg_name" != "$expected_name" ]; then
        name_bad_kind="-c user.name"; name_bad_val="$cfg_name"
      elif [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] && [ "${_GCIA_ENV_AUTHOR_NAME}" != "$expected_name" ]; then
        name_bad_kind="GIT_AUTHOR_NAME"; name_bad_val="$_GCIA_ENV_AUTHOR_NAME"
      elif [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ] && [ "${_GCIA_ENV_COMMITTER_NAME}" != "$expected_name" ]; then
        name_bad_kind="GIT_COMMITTER_NAME"; name_bad_val="$_GCIA_ENV_COMMITTER_NAME"
      fi
      if [ -n "$name_bad_kind" ] && declare -F ledger_emit >/dev/null 2>&1; then
        ledger_emit "gh-commit-author-identity" "warn" "name-only override ${name_bad_kind}=${name_bad_val} != expected ${expected_name} for ${target_dir} (not blocked — attribution is by email, not name)"
      fi
    fi
  fi

  if [ -n "$bad_kind" ]; then
    _GCIA_VIOLATION=1
    _GCIA_VIOLATION_DETAIL="${bad_kind}=${bad_val}"
    _GCIA_VIOLATION_EXPECTED="$expected_email"
    _GCIA_VIOLATION_SOURCE="$expected_source"
    _GCIA_VIOLATION_TARGET="$target_dir"
    return 0
  fi

  # No violation -> optional auto-set (obligation 3): only when the repo has
  # NO user.email at ANY level and the expected value came from the gh API
  # (never from the fallback rung, which by construction requires config to
  # already exist).
  if [ -z "$(git -C "$target_dir" config --get user.email 2>/dev/null)" ] \
     && case "$expected_source" in gh-api*) true ;; *) false ;; esac; then
    if git -C "$target_dir" config user.email "$expected_email" 2>/dev/null; then
      _GCIA_AUTO_SET_NOTE="auto-set user.email=${expected_email} for ${target_dir} (was unset; resolved via ${expected_source})"
      ledger_emit "gh-commit-author-identity" "warn" "$_GCIA_AUTO_SET_NOTE"
    fi
  fi
  return 0
}

_gcia_block() {
  local what why fix escape
  what="this commit sets identity via ${_GCIA_VIOLATION_DETAIL}, which does not match the identity expected for ${_GCIA_VIOLATION_TARGET} (${_GCIA_VIOLATION_EXPECTED}, resolved via ${_GCIA_VIOLATION_SOURCE})"
  why="Commits from Claude agents must carry the identity of the GitHub account logged in for the repo being committed to — never whatever email/name Claude Code's own session context hands the agent. A mismatch has already blocked a production deploy (Vercel maps commit emails to Vercel users; a downstream project's PR, 2026-09-21, ~1hr cost)."
  fix="drop the override so the commit resolves to ${_GCIA_VIOLATION_EXPECTED} (resolved via ${_GCIA_VIOLATION_SOURCE}) — if ${_GCIA_VIOLATION_TARGET}'s own \`git config user.email\` differs from this value, fix the config there instead of relying on an inline override"
  escape="GIT_COMMIT_IDENTITY_GATE_ACK=1 prefixed to the SAME command — only after the user in this conversation explicitly authorized committing under that other identity; never set it preemptively (constitution section 7)"
  {
    echo "================================================================"
    echo "GH-COMMIT-AUTHOR-IDENTITY GATE — COMMIT BLOCKED"
    echo "================================================================"
    if declare -F gc_block >/dev/null 2>&1; then
      gc_block "$what" "$why" "$fix" "$escape"
    else
      echo "WHAT: $what"
      echo "WHY: $why"
      echo "FIX: $fix"
      echo "ESCAPE: $escape"
    fi
    echo ""
    echo "This gate: ~/.claude/hooks/gh-commit-author-identity-gate.sh (source: adapters/claude-code/hooks/gh-commit-author-identity-gate.sh)"
  } >&2
  if declare -F ledger_emit >/dev/null 2>&1; then
    ledger_emit "gh-commit-author-identity" "block" "${_GCIA_VIOLATION_DETAIL} != expected ${_GCIA_VIOLATION_EXPECTED} (${_GCIA_VIOLATION_SOURCE}) for ${_GCIA_VIOLATION_TARGET}"
  fi
}

# ============================================================
# Main decision logic
# ============================================================

_gcia_run() {
  local cmd cwd
  cmd="$(_gcia_command)"
  [ -n "$cmd" ] || { exit 0; }
  # M1 (PR #67 review): this second prefilter (on the PARSED command,
  # after JSON extraction) must match the SAME verb-substring set as the
  # raw-payload prefilter near the top of this file — a narrower pattern
  # here would silently re-introduce the exact bug that prefilter's own
  # comment now warns against (only checking "commit" here skipped
  # merge/cherry-pick/revert/pull/rebase/am entirely, even though the raw
  # prefilter had already let them through).
  case "$cmd" in *commit*|*merge*|*cherry-pick*|*revert*|*pull*|*rebase*|*' am'*) : ;; *) exit 0 ;; esac
  case "$cmd" in *git*) : ;; *) exit 0 ;; esac
  command -v git >/dev/null 2>&1 || { exit 0; }

  cwd="$(_gcia_cwd)"
  [ -n "$cwd" ] || cwd="$PWD"

  _gcia_reset_env_state

  gcp_split_command "$cmd"
  local n=${#GCP_SEGMENTS[@]} i seg cd_target="" j
  local violation=0 auto_note=""
  # m1 (PR #67 review): a plain `git config user.email X` earlier in the
  # SAME command persists into a later commit-creating segment exactly
  # like a real shell would apply it — tracked here the same way cd_target
  # is tracked across segments.
  local cfg_track_email="" cfg_track_name=""

  for ((i=0; i<n; i++)); do
    seg="${GCP_SEGMENTS[$i]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [ -n "$seg" ] || continue

    # m1 (PR #67 review): `env NAME=VALUE... cmd` — strip the leading
    # "env" token so the assignment-stripping call below sees the exact
    # same NAME=VALUE shape it already handles for a bare command-scoped
    # prefix.
    seg="$(_gcia_strip_env_prefix "$seg")"
    [ -n "$seg" ] || continue

    GCP_ASSIGN_NAMES=(); GCP_ASSIGN_VALUES=()
    gcp_strip_env_assignments_var "$seg"
    for ((j=0; j<${#GCP_ASSIGN_NAMES[@]}; j++)); do
      _gcia_note_env_assignment "${GCP_ASSIGN_NAMES[$j]}" "${GCP_ASSIGN_VALUES[$j]}"
    done
    seg="$GCP_STRIPPED"
    [ -n "$seg" ] || continue

    local base="$cd_target"
    [ -n "$base" ] || base="$cwd"

    if gcp_is_cd_segment "$seg"; then
      gcp_parse_cd_target_var "$seg" "$base"
      cd_target="$GCP_CD_TARGET"
      continue
    fi

    if _gcia_maybe_export "$seg"; then continue; fi

    gcp_strip_command_prefix_var "$seg"
    case "$GCP_STRIPPED" in
      git|git[[:space:]]*) : ;;
      *) continue ;;
    esac

    if _gcia_maybe_config_set "$GCP_STRIPPED"; then
      case "$_GCIA_CFGSET_KEY" in
        user.email) cfg_track_email="$_GCIA_CFGSET_VAL" ;;
        user.name) cfg_track_name="$_GCIA_CFGSET_VAL" ;;
      esac
      continue
    fi

    _gcia_analyze_segment "$GCP_STRIPPED" "$base"
    [ "$_GCIA_IS_TARGET" = "1" ] || continue

    # m1: fold in a tracked earlier `git config user.email/name` SET only
    # when this segment carries no explicit override of its own — an
    # explicit -c/--author/env override on the commit segment itself
    # always takes precedence, matching git's own last-wins semantics.
    local eff_cfg_email="$_GCIA_CFG_EMAIL" eff_cfg_name="$_GCIA_CFG_NAME"
    [ -n "$eff_cfg_email" ] || eff_cfg_email="$cfg_track_email"
    [ -n "$eff_cfg_name" ] || eff_cfg_name="$cfg_track_name"

    _gcia_evaluate "$_GCIA_TARGET_DIR" "$eff_cfg_email" "$eff_cfg_name" "$_GCIA_AUTHOR_VAL"
    if [ "$_GCIA_VIOLATION" = "1" ]; then
      violation=1
      break
    fi
    if [ -n "${_GCIA_AUTO_SET_NOTE:-}" ]; then
      auto_note="$_GCIA_AUTO_SET_NOTE"
    fi
  done

  if [ "$violation" = "1" ]; then
    _gcia_block
    exit 2
  fi

  if [ -n "$auto_note" ]; then
    echo "[gh-commit-author-identity-gate] ${auto_note}" >&2
  fi
  exit 0
}

# ============================================================
# Self-test
# ============================================================

_gcia_self_test() {
  local pass=0 fail=0 tmp cfg stub calls gr gr2

  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t gciag)"
  cfg="$tmp/accounts.config.json"
  cat > "$cfg" <<'JSON'
{
  "work":     [ { "gh_user": "acct-work",     "owners": ["work-org"] } ],
  "personal": [ { "gh_user": "acct-personal", "owners": ["personal-org"] } ]
}
JSON

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
  export SIGNAL_LEDGER_PATH="$tmp/ledger.jsonl"
  export GHBLIND_ACCOUNTS="$cfg"
  export GIA_GH_CMD="$stub"
  export GIA_STATE_DIR="$tmp/state"
  mkdir -p "$GIA_STATE_DIR"
  # Sandbox HOME for every _run below — the real machine's global
  # ~/.gitconfig (a real, personal email address) must NEVER leak into a
  # self-test assertion. Without this, "no override -> allow" and similar
  # cases silently pass or fail depending on whichever operator's machine
  # happens to run the suite, which is exactly the self-invalidating class
  # CLAUDE.md's Windows-local-failures note already warns about elsewhere.
  export HOME="$tmp/home"
  mkdir -p "$HOME"
  export STUB_TOKEN_acct_work="tok-work"
  export STUB_EMAIL_FOR_TOKEN_tok_work="acct-work@example.test"
  export STUB_TOKEN_acct_personal="tok-personal"
  export STUB_EMAIL_FOR_TOKEN_tok_personal="acct-personal@example.test"

  gr="$tmp/repo-work"
  mkdir -p "$gr"
  ( cd "$gr" && git init -q 2>/dev/null \
      && git remote add origin "https://github.com/work-org/some-repo.git" 2>/dev/null \
      && git config user.name "Repo Owner" )

  gr2="$tmp/repo-personal"
  mkdir -p "$gr2"
  ( cd "$gr2" && git init -q 2>/dev/null \
      && git remote add origin "https://github.com/personal-org/some-repo.git" 2>/dev/null )

  _run() { # <cmd> <cwd> -> sets RC, OUT
    calls="$tmp/calls-$RANDOM.txt"; : > "$calls"
    OUT="$(GCIA_CMD="$1" GCIA_CWD="$2" GIA_STUB_CALLS="$calls" bash "$SELF" 2>&1 1>/dev/null)"
    RC=$?
  }

  # -------- override blocked --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git commit -m "x" --author="Someone <wrong@example.test>"' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q '\[GATE:WHAT\]' && printf '%s' "$OUT" | grep -q 'acct-work@example.test' && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  override-blocked (--author mismatch): PASS"; pass=$((pass+1))
  else
    echo "  override-blocked (--author mismatch): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- matching override allowed --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git commit -m "x" --author="Someone <acct-work@example.test>"' "$gr"
  if [ "$RC" = "0" ]; then
    echo "  matching-override-allowed (--author matches expected): PASS"; pass=$((pass+1))
  else
    echo "  matching-override-allowed (--author matches expected): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- no override allowed (+ auto-set side effect) --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  git -C "$gr" config --unset user.email 2>/dev/null || true
  _run 'git commit -m "plain commit, no override"' "$gr"
  local set_email; set_email="$(git -C "$gr" config --get user.email 2>/dev/null)"
  if [ "$RC" = "0" ] && [ "$set_email" = "acct-work@example.test" ] && printf '%s' "$OUT" | grep -q 'auto-set'; then
    echo "  no-override-allowed (+ auto-set unset user.email): PASS"; pass=$((pass+1))
  else
    echo "  no-override-allowed (+ auto-set unset user.email): FAIL (rc=$RC set_email=$set_email out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- scope-missing fallback (gh api 404-equivalent) --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  git -C "$gr" config user.email "fallback@example.test"
  unset STUB_EMAIL_FOR_TOKEN_tok_work   # token resolves but user/emails fails
  _run 'git -c user.email=wrong@example.test commit -m "x"' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'fallback@example.test'; then
    echo "  scope-missing-fallback (gh-api fails -> repo git config): PASS"; pass=$((pass+1))
  else
    echo "  scope-missing-fallback (gh-api fails -> repo git config): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi
  export STUB_EMAIL_FOR_TOKEN_tok_work="acct-work@example.test"

  # -------- noreply-never-used (nothing resolvable at all -> allow, never guess) --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  local gr3="$tmp/repo-unknown"; mkdir -p "$gr3"
  ( cd "$gr3" && HOME="$tmp/emptyhome" git init -q 2>/dev/null \
      && git remote add origin "https://github.com/unknown-org/x.git" 2>/dev/null )
  mkdir -p "$tmp/emptyhome"
  OUT="$(HOME="$tmp/emptyhome" GCIA_CMD='git commit -m "x" --author="Someone <wrong@example.test>"' GCIA_CWD="$gr3" GIA_STUB_CALLS="$tmp/calls-noreply.txt" bash "$SELF" 2>&1 1>/dev/null)"
  RC=$?
  if [ "$RC" = "0" ] && ! printf '%s' "$OUT" | grep -qi 'noreply'; then
    echo "  noreply-never-used (unresolvable -> allow, no synthesized guess): PASS"; pass=$((pass+1))
  else
    echo "  noreply-never-used (unresolvable -> allow, no synthesized guess): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- commit-tree explicitly in scope --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  local a_blob a_tree
  a_tree="$(git -C "$gr" write-tree 2>/dev/null || echo "4b825dc642cb6eb9a060e54bf8d69288fbee4904")"
  _run "git -c user.email=wrong@example.test commit-tree ${a_tree} -m x" "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  commit-tree recognized as identity-bearing: PASS"; pass=$((pass+1))
  else
    echo "  commit-tree recognized as identity-bearing: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- -c user.name mismatch: m2 (PR #67 review) WARNS, never BLOCKS --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative "$SIGNAL_LEDGER_PATH"
  _run 'git -c user.name="Wrong Name" commit -m x' "$gr"
  if [ "$RC" = "0" ] && grep -q 'name-only override' "$SIGNAL_LEDGER_PATH" 2>/dev/null && grep -q 'Wrong Name' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "  -c user.name mismatch WARNS (not blocked) + logs ledger: PASS"; pass=$((pass+1))
  else
    echo "  -c user.name mismatch WARNS (not blocked) + logs ledger: FAIL (rc=$RC out=[$OUT] ledger=$(cat "$SIGNAL_LEDGER_PATH" 2>/dev/null))"; fail=$((fail+1))
  fi

  # -------- glued -c form --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -cuser.email=wrong@example.test commit -m x' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  glued -c<key>=<val> form parsed and blocked: PASS"; pass=$((pass+1))
  else
    echo "  glued -c<key>=<val> form parsed and blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- env var via command-scoped prefix --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_AUTHOR_EMAIL'; then
    echo "  GIT_AUTHOR_EMAIL command-scoped prefix blocked: PASS"; pass=$((pass+1))
  else
    echo "  GIT_AUTHOR_EMAIL command-scoped prefix blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- env var via earlier export segment --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'export GIT_COMMITTER_EMAIL=wrong@example.test && git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_COMMITTER_EMAIL'; then
    echo "  export in an earlier segment blocked: PASS"; pass=$((pass+1))
  else
    echo "  export in an earlier segment blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- ack escape allows through, and is logged as a waiver --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative "$SIGNAL_LEDGER_PATH"
  _run 'GIT_COMMIT_IDENTITY_GATE_ACK=1 GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x' "$gr"
  if [ "$RC" = "0" ] && grep -q '"gate":"gh-commit-author-identity"' "$SIGNAL_LEDGER_PATH" 2>/dev/null && grep -q '"event":"waiver"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "  GIT_COMMIT_IDENTITY_GATE_ACK=1 escape allows through + logs waiver: PASS"; pass=$((pass+1))
  else
    echo "  GIT_COMMIT_IDENTITY_GATE_ACK=1 escape allows through + logs waiver: FAIL (rc=$RC ledger=$(cat "$SIGNAL_LEDGER_PATH" 2>/dev/null))"; fail=$((fail+1))
  fi

  # -------- -C target dir resolution: wrong-account identity used against a
  # DIFFERENT repo than cwd, resolved via -C, must be judged against THAT
  # repo's expected identity --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run "git -C ${gr2} commit -m x --author=\"X <acct-work@example.test>\"" "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'acct-personal@example.test'; then
    echo "  -C target dir drives expected-identity lookup: PASS"; pass=$((pass+1))
  else
    echo "  -C target dir drives expected-identity lookup: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- non-commit command -> no-op, no gh calls --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  calls="$tmp/calls-status.txt"; : > "$calls"
  RC=0
  GCIA_CMD='git status' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1 || RC=$?
  if [ "$RC" = "0" ] && [ ! -s "$calls" ]; then
    echo "  non-commit command -> no-op, no gh calls: PASS"; pass=$((pass+1))
  else
    echo "  non-commit command -> no-op, no gh calls: FAIL (rc=$RC calls=$(cat "$calls" 2>/dev/null))"; fail=$((fail+1))
  fi

  # -------- unparseable --author value fails closed (ambiguous identity) --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git commit -m x --author=not-an-email-shape' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  unparseable --author value fails closed: PASS"; pass=$((pass+1))
  else
    echo "  unparseable --author value fails closed: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- cache reused across two commits in the sweep (no repeated gh api calls) --------
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  calls="$tmp/calls-cache.txt"; : > "$calls"
  GCIA_CMD='git commit -m x' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1
  GCIA_CMD='git commit -m x --author="A <acct-work@example.test>"' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1
  local n_calls; n_calls="$(grep -c '^api-user-emails' "$calls" 2>/dev/null || echo 0)"
  if [ "$n_calls" = "1" ]; then
    echo "  cache reused across invocations (1 gh-api call for 2 commits): PASS"; pass=$((pass+1))
  else
    echo "  cache reused across invocations (1 gh-api call for 2 commits): FAIL (calls=$n_calls)"; fail=$((fail+1))
  fi

  # ============================================================
  # M1 (PR #67 review, PROVEN): commit-creating verbs beyond commit/commit-tree
  # ============================================================

  # A verbatim-shaped real transcript: `-c user.name=/-c user.email=` on a
  # `merge` invocation, a downstream project's own most-frequent
  # commit-creating path.
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -c user.name="Someone" -c user.email=wrong@example.test merge -q --no-ff origin/master -m "Merge origin/master"' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  M1 merge -c user.email mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 merge -c user.email mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'GIT_COMMITTER_EMAIL=wrong@example.test git cherry-pick abc1234' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_COMMITTER_EMAIL'; then
    echo "  M1 cherry-pick env override blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 cherry-pick env override blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -c user.email=wrong@example.test revert --no-edit HEAD' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  M1 revert -c user.email mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 revert -c user.email mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -c user.email=wrong@example.test pull --no-rebase origin master' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  M1 pull -c user.email mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 pull -c user.email mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -c user.email=wrong@example.test rebase origin/master' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  M1 rebase -c user.email mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 rebase -c user.email mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git -c user.email=wrong@example.test am /tmp/patch.mbox' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  M1 am -c user.email mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  M1 am -c user.email mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # Non-regression: plain merge/pull/cherry-pick with NO override, and a
  # read-only `git log --author=` (not commit-creating), all still allowed.
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git merge origin/master' "$gr"
  if [ "$RC" = "0" ]; then
    echo "  M1 plain merge (no override) allowed: PASS"; pass=$((pass+1))
  else
    echo "  M1 plain merge (no override) allowed: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git log --author=someone@example.test' "$gr"
  if [ "$RC" = "0" ]; then
    echo "  M1 git log --author= (read-only, not commit-creating) allowed: PASS"; pass=$((pass+1))
  else
    echo "  M1 git log --author= (read-only, not commit-creating) allowed: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # ============================================================
  # M4 (PR #67 review, PROVEN false positive): no github.com remote -> fail open
  # ============================================================
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  # Sandbox a "global" git config holding SOME address, simulating a real
  # operator machine's ~/.gitconfig — the exact condition that let this
  # false positive escape a self-test suite that never populates one.
  git config --global user.email "global-fallback@example.test" 2>/dev/null
  git config --global user.name "Global Fallback" 2>/dev/null
  local scratch="$tmp/scratch-no-remote"; mkdir -p "$scratch"
  ( cd "$scratch" && git init -q 2>/dev/null && git config user.email "t@t.example" && git config user.name "t" )
  _run 'git -c user.email=totally-different@example.test -c user.name=other commit --allow-empty -m base' "$scratch"
  if [ "$RC" = "0" ]; then
    echo "  M4 no-github-remote scratch repo fails open (never blocked): PASS"; pass=$((pass+1))
  else
    echo "  M4 no-github-remote scratch repo fails open (never blocked): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # ============================================================
  # m1 (PR #67 review): two closable named bypasses
  # ============================================================

  # `env NAME=VALUE cmd` prefix (distinct from a bare command-scoped prefix).
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'env GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_AUTHOR_EMAIL'; then
    echo "  m1 'env NAME=VALUE git commit' prefix blocked: PASS"; pass=$((pass+1))
  else
    echo "  m1 'env NAME=VALUE git commit' prefix blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # `git config user.email X && git commit` — the "please tell me who you
  # are" shape: no override on the commit segment itself, but an earlier
  # config SET in the same command should still be caught.
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git config user.email wrong@example.test && git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'user.email' && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  m1 'git config user.email X && git commit' persistence blocked: PASS"; pass=$((pass+1))
  else
    echo "  m1 'git config user.email X && git commit' persistence blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # An explicit override on the commit segment ITSELF still wins over an
  # earlier tracked config-set (git's own last-wins semantics) — here the
  # tracked config is WRONG but the commit's own -c MATCHES, so it must
  # be ALLOWED, proving the commit segment's own override takes priority.
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  _run 'git config user.email wrong@example.test && git -c user.email=acct-work@example.test commit -m x' "$gr"
  if [ "$RC" = "0" ]; then
    echo "  m1 explicit commit-segment override wins over tracked config-set: PASS"; pass=$((pass+1))
  else
    echo "  m1 explicit commit-segment override wins over tracked config-set: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  unset HARNESS_SELFTEST SIGNAL_LEDGER_PATH GHBLIND_ACCOUNTS GIA_GH_CMD GIA_STATE_DIR \
    STUB_TOKEN_acct_work STUB_EMAIL_FOR_TOKEN_tok_work STUB_TOKEN_acct_personal STUB_EMAIL_FOR_TOKEN_tok_personal
  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[gh-commit-author-identity-gate self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"

case "${1:-}" in
  --self-test) _gcia_self_test; exit $? ;;
  -h|--help)
    cat <<'GCIA_USAGE' >&2
gh-commit-author-identity-gate.sh — PreToolUse gate: block a git commit /
commit-tree whose command overrides author/committer identity away from the
identity expected for the repo it targets (the gh CLI account logged in for
that repo — never the Claude Code session's own context email).

  gh-commit-author-identity-gate.sh             # PreToolUse: reads JSON on stdin
  gh-commit-author-identity-gate.sh --self-test  # run self-test suite

Escape: GIT_COMMIT_IDENTITY_GATE_ACK=1 prefixed to the same command, only
after the user's explicit in-conversation say-so.
GCIA_USAGE
    exit 2
    ;;
  "") _gcia_read_payload; _gcia_run ;;
  *)
    echo "gh-commit-author-identity-gate.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
