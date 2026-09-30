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
#   Added in review round 2 (record hcr-20260930-68fd4a0d):
#   - A `git config user.email <val>` run in a DIFFERENT, earlier Bash call
#     (m5): the later plain commit carries no override and short-circuits.
#   - An override whose value is only knowable at runtime (`$VAR` set in an
#     earlier call, `$(...)`, backticks) is UNKNOWN: logged as a ledger
#     `warn`, never blocked (MAJOR-1 — a literal "$E" is not an identity).
#   - A real `--author=` placed AFTER an unbalanced `$(`, a backtick, or a
#     here-doc operator on the same commit segment: the flag walk stops
#     there because it cannot know where the substitution ends.
#   - m6 (HYPOTHESIZED): the gh-API rung takes the PRIMARY email and ignores
#     its visibility, so a private primary could still be rejected by a
#     push-time email-privacy check. Dormant where the primary is public.
#
# ALSO ALLOWED (review round 2):
#   - The harness's OWN review-record commits: every resolved override is a
#     reviewer+<session>@<host> identity (review-runner.sh finalize's A1
#     stamp) AND every committed path is docs/reviews/records/<file>
#     (MAJOR-3 — see _gcia_records_only). Logged as a ledger `skip`.
#   - A commit into a repo that the same command `git init`s (a throwaway).
#
# SSH host-alias remotes (`git@github-<alias>:owner/repo`) are resolved via
# `ssh -G` in gh-account-lib.sh and enforced when the alias points at
# github.com (m3, round 2 — they previously failed open with no signal).
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
  # m2 (PR #67 review round 2, measured ~450-520ms vs ~150-185ms): a payload
  # whose description or cwd happens to contain a verb substring but which
  # has no "git" anywhere cannot be a git command — still a pure superset
  # filter (a git invocation always contains the substring "git").
  case "$_GCIA_RAW" in
    *git*) : ;;
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
# TEXT-AS-DATA NORMALIZATION (MAJOR-1, PR #67 review round 2, PROVEN false
# positives: every one below was rc=2 on a command carrying NO mismatching
# identity, with a WHAT line asserting an override that did not exist).
#
#   F1  git commit -m "$(cat <<'EOF' ... "git commit --author=X <y>" ... EOF)"
#       — a double-quoted phrase inside the here-doc body flipped quote
#       parity, so body text was tokenized as flags.
#   F4  git commit -F - <<'EOF' ... --author=Foo ... EOF
#       — the here-doc body stayed inside the segment and phase 2 walked it.
#   R1  an ANSI-C $'...' string holding git text (a replayed transcript) —
#       `\'` inside $'...' is an escaped quote, which a plain single-quote
#       scanner reads as a terminator, flipping parity for the rest of the
#       command.
#   P1  E=<matching email> && GIT_AUTHOR_EMAIL="$E" git commit — the literal
#       string "$E" was compared against the expected email.
#
# The fixes, applied to the WHOLE command before it is split:
#   1. $'...' strings are decoded and re-emitted as plain single-quoted
#      strings (an embedded ' becomes '"'"'), so every downstream scanner
#      sees balanced, ordinary quoting.
#   2. Here-doc BODIES are removed (the `<<DELIM` line and the terminator
#      line are kept). A body is data, never flags. Only removed when the
#      terminator line is actually present, so a stray `<<` in prose never
#      swallows the rest of a command.
# and, per segment:
#   3. Assignment-only segments (`E=x`, `export E=x`) are remembered and
#      substituted into later segments (gcp_subst_vars_var, the same helper
#      gcp_resolve_commit_target uses), so P1 compares the real value.
#   4. A value still containing `$` or a backtick after substitution is
#      UNKNOWN (set in an earlier Bash call, or computed at runtime) — it is
#      logged as a signal-ledger warn and never treated as a mismatch.
#   5. The phase-2 flag walk STOPS at a here-doc operator token and at a
#      token holding an unbalanced `$(` or a backtick: past that point the
#      tokenizer cannot know where the substitution ends, so any later
#      `--author=` could be message text. A token holding a BALANCED
#      `$(...)` (the usual `-m "$(cat <<'EOF' ... )"` once the body is
#      removed) is skipped as an opaque value and the walk continues, so a
#      real `--author=` AFTER the message is still seen. A newline-bearing
#      token is likewise skipped, not stopped at: after steps 1-2 a newline
#      inside a segment can only be inside a well-formed quoted value (the
#      splitter breaks unquoted newlines), so stopping there would only buy
#      a false negative on `-m "<multi-line>" --author=...`.
# ============================================================

_gcia_normalize_ansi_c() { # <cmd> -> _GCIA_NORM
  local s="$1"
  case "$s" in
    *"\$'"*) : ;;
    *) _GCIA_NORM="$s"; return 0 ;;
  esac
  local out="" i=0 n=${#s} ch nx dec in_sq=0 in_dq=0 q="'\"'\"'"
  while [ "$i" -lt "$n" ]; do
    ch="${s:i:1}"
    if [ "$in_sq" = "1" ]; then
      out+="$ch"; [ "$ch" = "'" ] && in_sq=0
      i=$((i+1)); continue
    fi
    if [ "$in_dq" = "1" ]; then
      out+="$ch"
      if [ "$ch" = '\' ]; then i=$((i+1)); out+="${s:i:1}"
      elif [ "$ch" = '"' ]; then in_dq=0; fi
      i=$((i+1)); continue
    fi
    case "$ch" in
      "'") in_sq=1; out+="$ch" ;;
      '"') in_dq=1; out+="$ch" ;;
      '\') out+="$ch"; i=$((i+1)); out+="${s:i:1}" ;;
      '$')
        if [ "${s:i+1:1}" = "'" ]; then
          i=$((i+2)); dec=""
          while [ "$i" -lt "$n" ]; do
            ch="${s:i:1}"
            if [ "$ch" = '\' ]; then
              nx="${s:i+1:1}"
              case "$nx" in
                n) dec+=$'\n' ;;
                t) dec+=$'\t' ;;
                "'") dec+="'" ;;
                '"') dec+='"' ;;
                '\') dec+='\' ;;
                *) dec+="\\$nx" ;;
              esac
              i=$((i+2)); continue
            fi
            [ "$ch" = "'" ] && break
            dec+="$ch"; i=$((i+1))
          done
          out+="'${dec//\'/$q}'"
        else
          out+="$ch"
        fi
        ;;
      *) out+="$ch" ;;
    esac
    i=$((i+1))
  done
  _GCIA_NORM="$out"
}

_gcia_strip_heredoc_bodies() { # <cmd> -> _GCIA_NORM
  local s="$1"
  case "$s" in
    *'<<'*) : ;;
    *) _GCIA_NORM="$s"; return 0 ;;
  esac
  local -a L=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do L+=("$line"); done <<< "$s"
  local n=${#L[@]} i=0 j found t dash delim out=""
  local re="<<(-?)[[:space:]]*[\\\"']?([A-Za-z_][A-Za-z0-9_]*)"
  while [ "$i" -lt "$n" ]; do
    line="${L[$i]}"
    out+="$line"
    [ "$i" -lt $((n-1)) ] && out+=$'\n'
    if [[ "$line" =~ $re ]] && [[ "$line" != *'<<<'* ]]; then
      dash="${BASH_REMATCH[1]}"; delim="${BASH_REMATCH[2]}"
      found=-1
      for ((j=i+1; j<n; j++)); do
        t="${L[$j]}"
        [ -n "$dash" ] && t="${t#"${t%%[!$'\t']*}"}"
        if [ "$t" = "$delim" ]; then found=$j; break; fi
      done
      if [ "$found" -gt 0 ]; then
        i=$found
        continue
      fi
    fi
    i=$((i+1))
  done
  _GCIA_NORM="$out"
}

# 0 iff the value cannot be known before the shell runs it.
_gcia_unresolved() {
  case "$1" in
    *'$'*|*'`'*) return 0 ;;
  esac
  return 1
}

# Tokenize like gcp_tokenize_segment, but honoring backslash escapes (inside
# double quotes and unquoted) the way a shell does — an escaped `\"` inside a
# -m message must not end the string and expose the rest as flags.
_gcia_tokenize() { # <segment> -> _GCIA_TOK[]
  local s="$1" i ch n cur="" in_dq=0 in_sq=0 have=0
  _GCIA_TOK=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [ "$in_sq" = "1" ]; then
      if [ "$ch" = "'" ]; then in_sq=0; else cur+="$ch"; fi
      continue
    fi
    if [ "$in_dq" = "1" ]; then
      if [ "$ch" = '"' ]; then in_dq=0
      elif [ "$ch" = '\' ] && [ $((i+1)) -lt "$n" ]; then
        case "${s:i+1:1}" in
          '"'|'\'|'$'|'`') i=$((i+1)); cur+="${s:i:1}" ;;
          *) cur+="$ch" ;;
        esac
      else cur+="$ch"; fi
      continue
    fi
    case "$ch" in
      "'") in_sq=1; have=1 ;;
      '"') in_dq=1; have=1 ;;
      '\')
        if [ $((i+1)) -lt "$n" ]; then i=$((i+1)); cur+="${s:i:1}"; have=1; else cur+="$ch"; have=1; fi
        ;;
      ' '|$'\t')
        if [ -n "$cur" ] || [ "$have" = "1" ]; then
          _GCIA_TOK+=("$cur"); cur=""; have=0
        fi
        ;;
      *) cur+="$ch"; have=1 ;;
    esac
  done
  if [ -n "$cur" ] || [ "$have" = "1" ]; then
    _GCIA_TOK+=("$cur")
  fi
}

# Phase-2 walk control for one token: 0 = stop the walk, 1 = skip this token
# as an opaque value, 2 = interpret normally.
_gcia_token_class() {
  local tok="$1" o c
  case "$tok" in
    '<<'*) return 0 ;;
  esac
  case "$tok" in
    *'`'*) return 0 ;;
  esac
  case "$tok" in
    *'$('*)
      o="${tok//[^(]/}"; c="${tok//[^)]/}"
      [ "${#o}" = "${#c}" ] && return 1
      return 0
      ;;
  esac
  case "$tok" in
    *$'\n'*) return 1 ;;
  esac
  return 2
}

# Redirection-shaped tokens (`2>`, `>/dev/null`, `<in`) are not pathspecs.
_gcia_is_redirection() {
  case "$1" in
    [0-9]*'>'*|'>'*|'<'*|'&'*|[0-9]'<'*) return 0 ;;
  esac
  return 1
}

# Normalize a directory string for equality checks (slashes, trailing /).
_gcia_norm_path() {
  local p="${1//\\//}"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

# 0 iff <a> and <b> name the same repo: identical normalized text, or the
# same `git rev-parse --show-toplevel` (only forked when the text differs).
_gcia_same_repo() {
  local a b ta tb
  a="$(_gcia_norm_path "$1")"; b="$(_gcia_norm_path "$2")"
  if gh_ci_eq "$a" "$b" 2>/dev/null || [ "$a" = "$b" ]; then return 0; fi
  ta="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  tb="$(git -C "$2" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$ta" ] && [ "$ta" = "$tb" ]
}

# ============================================================
# Tracked env vars (the 4 identity vars + the ack). PERSISTENT state comes
# from `export NAME=...` segments and assignment-only segments, visible to
# every later segment in the same command. A command-scoped prefix
# (`NAME=... git commit`, or `env NAME=... git commit`) applies ONLY to its
# own segment — the round-1 version let `GIT_AUTHOR_EMAIL=x git add f &&
# git commit` leak the add's prefix into the commit, which no shell does.
# ============================================================

_gcia_reset_env_state() {
  _GCIA_P_ACK=0; _GCIA_P_AE=""; _GCIA_P_CE=""; _GCIA_P_AN=""; _GCIA_P_CN=""
  GCP_VAR_NAMES=(); GCP_VAR_VALUES=()
}

_gcia_note_persistent() { # <name> <value>
  case "$1" in
    GIT_AUTHOR_EMAIL) _GCIA_P_AE="$2" ;;
    GIT_COMMITTER_EMAIL) _GCIA_P_CE="$2" ;;
    GIT_AUTHOR_NAME) _GCIA_P_AN="$2" ;;
    GIT_COMMITTER_NAME) _GCIA_P_CN="$2" ;;
    GIT_COMMIT_IDENTITY_GATE_ACK) [ "$2" = "1" ] && _GCIA_P_ACK=1 ;;
  esac
  GCP_VAR_NAMES+=("$1"); GCP_VAR_VALUES+=("$2")
}

# Effective env for a commit segment = persistent state overlaid with that
# segment's own command-scoped assignments (_GCIA_SEG_AN[] / _GCIA_SEG_AV[]).
_gcia_effective_env() {
  _GCIA_ACK="$_GCIA_P_ACK"
  _GCIA_ENV_AUTHOR_EMAIL="$_GCIA_P_AE"; _GCIA_ENV_COMMITTER_EMAIL="$_GCIA_P_CE"
  _GCIA_ENV_AUTHOR_NAME="$_GCIA_P_AN"; _GCIA_ENV_COMMITTER_NAME="$_GCIA_P_CN"
  local j
  for ((j=0; j<${#_GCIA_SEG_AN[@]}; j++)); do
    case "${_GCIA_SEG_AN[$j]}" in
      GIT_AUTHOR_EMAIL) _GCIA_ENV_AUTHOR_EMAIL="${_GCIA_SEG_AV[$j]}" ;;
      GIT_COMMITTER_EMAIL) _GCIA_ENV_COMMITTER_EMAIL="${_GCIA_SEG_AV[$j]}" ;;
      GIT_AUTHOR_NAME) _GCIA_ENV_AUTHOR_NAME="${_GCIA_SEG_AV[$j]}" ;;
      GIT_COMMITTER_NAME) _GCIA_ENV_COMMITTER_NAME="${_GCIA_SEG_AV[$j]}" ;;
      GIT_COMMIT_IDENTITY_GATE_ACK) [ "${_GCIA_SEG_AV[$j]}" = "1" ] && _GCIA_ACK=1 ;;
    esac
  done
}

# `export NAME=VALUE [NAME2=VALUE2 ...]` — persistent. Returns 0 iff the
# segment WAS an export.
_gcia_maybe_export() {
  local seg="$1" rest tok name val k n
  case "$seg" in
    export|export[[:space:]]*) : ;;
    *) return 1 ;;
  esac
  rest="${seg#export}"
  _gcia_tokenize "$rest"
  n=${#_GCIA_TOK[@]}
  for ((k=0; k<n; k++)); do
    tok="${_GCIA_TOK[$k]}"
    case "$tok" in
      [A-Za-z_]*=*)
        name="${tok%%=*}"
        case "$name" in *[!A-Za-z0-9_]*) continue ;; esac
        val="${tok#*=}"
        _gcia_note_persistent "$name" "$val"
        ;;
    esac
  done
  return 0
}

# m1 (PR #67 review): `env NAME=VALUE... cmd` — strip the leading "env" so
# the assignment stripper sees the command-scoped NAME=VALUE shape. Does not
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

# ============================================================
# Per-git-segment analysis. Sets:
#   _GCIA_SUB          the subcommand word ("" when none)
#   _GCIA_IS_TARGET    1 iff the subcommand is commit-creating
#   _GCIA_TARGET_DIR   dir git will act in (-C / --work-tree / --git-dir / base)
#   _GCIA_CFG_EMAIL/_GCIA_CFG_NAME   global `-c user.email=/user.name=` values
#   _GCIA_AUTHOR_VAL   `commit --author` value
#   _GCIA_PATHSPECS[]  `commit -- <paths>` (redirection-shaped tokens dropped)
#   _GCIA_COMMIT_ALL   1 iff `commit -a/--all`
#   _GCIA_ARGS[]       tokens after the subcommand (for config/init/add)
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

_gcia_analyze_segment() { # <segment starting with "git"> <base-dir>
  local seg="$1" base="$2"
  _GCIA_SUB=""; _GCIA_IS_TARGET=0; _GCIA_TARGET_DIR=""; _GCIA_CFG_EMAIL=""; _GCIA_CFG_NAME=""
  _GCIA_AUTHOR_VAL=""; _GCIA_PATHSPECS=(); _GCIA_COMMIT_ALL=0; _GCIA_ARGS=()
  _gcia_tokenize "$seg"
  local n=${#_GCIA_TOK[@]} i tok c_target="" work_tree="" git_dir=""
  [ "$n" -ge 2 ] || return 0
  [ "${_GCIA_TOK[0]}" = "git" ] || return 0

  i=1
  while [ "$i" -lt "$n" ]; do
    tok="${_GCIA_TOK[$i]}"
    case "$tok" in
      -C)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        c_target="$(gcp_compose_dir "$c_target" "$base" "${_GCIA_TOK[$i]}")"
        ;;
      -C?*) c_target="$(gcp_compose_dir "$c_target" "$base" "${tok:2}")" ;;
      --work-tree=?*) work_tree="$(gcp_compose_dir "" "$base" "${tok#--work-tree=}")" ;;
      --git-dir=?*) git_dir="$(gcp_compose_dir "" "$base" "${tok#--git-dir=}")" ;;
      --work-tree)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        work_tree="$(gcp_compose_dir "" "$base" "${_GCIA_TOK[$i]}")"
        ;;
      --git-dir)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        git_dir="$(gcp_compose_dir "" "$base" "${_GCIA_TOK[$i]}")"
        ;;
      -c)
        i=$((i+1)); [ "$i" -lt "$n" ] || break
        _gcia_note_cfg "${_GCIA_TOK[$i]}"
        ;;
      -c?*) _gcia_note_cfg "${tok#-c}" ;;
      --namespace) i=$((i+1)) ;;
      -*) : ;;
      *) _GCIA_SUB="$tok"; break ;;
    esac
    i=$((i+1))
  done

  if [ -n "$work_tree" ]; then _GCIA_TARGET_DIR="$work_tree"
  elif [ -n "$git_dir" ]; then _GCIA_TARGET_DIR="${git_dir%/.git}"
  elif [ -n "$c_target" ]; then _GCIA_TARGET_DIR="$c_target"
  else _GCIA_TARGET_DIR="$base"
  fi
  [ -n "$_GCIA_SUB" ] || return 0

  # Remaining tokens, cut at the first walk-stop token (see note 5 above).
  local k cls
  for ((k=i+1; k<n; k++)); do
    tok="${_GCIA_TOK[$k]}"
    _gcia_token_class "$tok"; cls=$?
    [ "$cls" = "0" ] && break
    if [ "$cls" = "1" ]; then _GCIA_ARGS+=("__GCIA_OPAQUE__"); continue; fi
    _GCIA_ARGS+=("$tok")
  done

  # M1 (PR #67 review, PROVEN): every commit-creating verb, not only commit.
  case "$_GCIA_SUB" in
    commit|commit-tree|merge|cherry-pick|revert|pull|rebase|am) _GCIA_IS_TARGET=1 ;;
    *) return 0 ;;
  esac

  # Phase 2: `--author` (commit only — no other verb in scope accepts it),
  # plus the pathspec / -a facts the records-only exemption needs.
  [ "$_GCIA_SUB" = "commit" ] || return 0
  local m=${#_GCIA_ARGS[@]} after_dd=0
  for ((k=0; k<m; k++)); do
    tok="${_GCIA_ARGS[$k]}"
    [ "$tok" = "__GCIA_OPAQUE__" ] && continue
    if [ "$after_dd" = "1" ]; then
      _gcia_is_redirection "$tok" || _GCIA_PATHSPECS+=("$tok")
      continue
    fi
    case "$tok" in
      --) after_dd=1 ;;
      --author=?*) _GCIA_AUTHOR_VAL="${tok#--author=}" ;;
      --author) k=$((k+1)); [ "$k" -lt "$m" ] && _GCIA_AUTHOR_VAL="${_GCIA_ARGS[$k]}" ;;
      --all) _GCIA_COMMIT_ALL=1 ;;
      --message|--file|--reuse-message|--reedit-message|--fixup|--squash|--template|--cleanup|--date|--trailer)
        k=$((k+1)) ;;
      --*) : ;;
      -[!-]*)
        case "$tok" in -*a*) _GCIA_COMMIT_ALL=1 ;; esac
        # Short cluster ending in a value-taking flag with no glued value
        # (`-m`, `-am`, `-F`, `-C`, `-c`, `-t`) -> the next token is its value.
        case "$tok" in -*[mFCct]) k=$((k+1)) ;; esac
        ;;
    esac
  done
  return 0
}

# `git [-C d] config [--local|--worktree] user.email|user.name <value>` —
# a SET (not --get/--unset/--list; --global/--system are out of this
# per-repo gate's scope). Uses the _GCIA_SUB/_GCIA_ARGS/_GCIA_TARGET_DIR
# left by _gcia_analyze_segment. Sets _GCIA_CFGSET_KEY/_GCIA_CFGSET_VAL.
_gcia_maybe_config_set() {
  [ "$_GCIA_SUB" = "config" ] || return 1
  local n=${#_GCIA_ARGS[@]} i=0 key
  while [ "$i" -lt "$n" ]; do
    case "${_GCIA_ARGS[$i]}" in
      --local|--worktree) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  key="$(printf '%s' "${_GCIA_ARGS[$i]}" | tr '[:upper:]' '[:lower:]')"
  case "$key" in
    user.email|user.name) _GCIA_CFGSET_KEY="$key" ;;
    *) return 1 ;;
  esac
  i=$((i+1))
  [ "$i" -lt "$n" ] || return 1
  [ "${_GCIA_ARGS[$i]}" = "__GCIA_OPAQUE__" ] && return 1
  _GCIA_CFGSET_VAL="${_GCIA_ARGS[$i]}"
  return 0
}

# `git init [opts] [dir]` -> the directory it initializes (m1-minor, PR #67
# review round 2, PROVEN: `cd existing-subdir && git init && git -c
# user.email=t@t commit` in a pre-existing non-repo dir INSIDE a GitHub
# checkout was judged against the ENCLOSING repo's identity). A repo this
# same command creates is a throwaway, exactly like the no-remote case (M4).
_gcia_init_dir() {
  local n=${#_GCIA_ARGS[@]} i=0 tok dir=""
  while [ "$i" -lt "$n" ]; do
    tok="${_GCIA_ARGS[$i]}"
    case "$tok" in
      -b|--initial-branch|--template|--separate-git-dir|--object-format|--ref-format|--shared) i=$((i+1)) ;;
      -*|__GCIA_OPAQUE__) : ;;
      *) _gcia_is_redirection "$tok" || { dir="$tok"; break; } ;;
    esac
    i=$((i+1))
  done
  if [ -n "$dir" ]; then
    _GCIA_INIT_RESULT="$(gcp_compose_dir "" "$_GCIA_TARGET_DIR" "$dir")"
  else
    _GCIA_INIT_RESULT="$_GCIA_TARGET_DIR"
  fi
}

# `git add <paths>` -> recorded (with its dir) for the records-only
# exemption. `.`/-A/--all/-u/--update record a wildcard marker, which is
# never records-only.
_gcia_note_add() {
  local n=${#_GCIA_ARGS[@]} i tok
  for ((i=0; i<n; i++)); do
    tok="${_GCIA_ARGS[$i]}"
    case "$tok" in
      -A|--all|-u|--update|.|./|:/|__GCIA_OPAQUE__) _GCIA_ADD_PATHS+=("*"); _GCIA_ADD_DIRS+=("$_GCIA_TARGET_DIR") ;;
      --) : ;;
      -*) : ;;
      *) _gcia_is_redirection "$tok" || { _GCIA_ADD_PATHS+=("$tok"); _GCIA_ADD_DIRS+=("$_GCIA_TARGET_DIR"); } ;;
    esac
  done
}

_gcia_is_init_dir() { # <target_dir>
  local k
  for ((k=0; k<${#_GCIA_INIT_DIRS[@]}; k++)); do
    if [ "$(_gcia_norm_path "${_GCIA_INIT_DIRS[$k]}")" = "$(_gcia_norm_path "$1")" ]; then
      return 0
    fi
  done
  return 1
}

# ============================================================
# MAJOR-3 (PR #67 review round 2, PROVEN): the harness's OWN review-record
# commits. scripts/review-runner.sh finalize commits a record as
# reviewer+<claimant session_id>@<host> (review-runner.sh:~375, the A1
# identity stamp) so harness-doctor's review-reviewer-independence check —
# record author must differ from the reviewed commit's author — stays GREEN.
# When that runner step fails, the documented manual fallback repeats the
# same stamped commit by hand; three replayed transcript commands in the
# harness repo are exactly that, and this gate blocked them — while its own
# FIX ("drop the override") would produce a record authored by the reviewed
# commit's identity, i.e. a doctor RED. So: a commit whose every RESOLVED
# identity override has the reviewer+<...>@<...> shape AND whose content is
# records-only (every path is docs/reviews/records/<file>) is EXEMPT, and is
# logged as a signal-ledger `skip`. Records-only is judged from the commit's
# own `-- <pathspec>` when present (git commits exactly those paths), else
# from what is staged now plus what an earlier `git add` in the same command
# will stage; `-a`/`--all`, a wildcard add, or any unresolved path is NOT
# records-only.
# ============================================================

_gcia_is_records_path() {
  local p="${1//\\//}"
  _gcia_unresolved "$p" && return 1
  p="${p#./}"
  case "$p" in
    docs/reviews/records/*) p="${p#docs/reviews/records/}" ;;
    */docs/reviews/records/*) p="${p##*/docs/reviews/records/}" ;;
    *) return 1 ;;
  esac
  [ -n "$p" ] || return 1
  case "$p" in */*|'*') return 1 ;; esac
  return 0
}

_gcia_records_only() { # <target_dir>
  local target="$1" k p count=0
  [ "${_GCIA_COMMIT_ALL:-0}" = "1" ] && return 1
  if [ "${#_GCIA_PATHSPECS[@]}" -gt 0 ]; then
    for ((k=0; k<${#_GCIA_PATHSPECS[@]}; k++)); do
      _gcia_is_records_path "${_GCIA_PATHSPECS[$k]}" || return 1
      count=$((count+1))
    done
    [ "$count" -gt 0 ]
    return
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _gcia_is_records_path "$p" || return 1
    count=$((count+1))
  done <<< "$(git -C "$target" -c core.quotePath=false diff --cached --name-only 2>/dev/null)"
  for ((k=0; k<${#_GCIA_ADD_PATHS[@]}; k++)); do
    _gcia_same_repo "${_GCIA_ADD_DIRS[$k]}" "$target" || continue
    _gcia_is_records_path "${_GCIA_ADD_PATHS[$k]}" || return 1
    count=$((count+1))
  done
  [ "$count" -gt 0 ]
}

_gcia_is_reviewer_identity() {
  case "$1" in
    reviewer+?*@?*) return 0 ;;
  esac
  return 1
}

# ============================================================
# Evaluate one commit-creating segment. Sets _GCIA_VIOLATION (0|1) and, on
# 1, the detail fields used by the block message.
# ============================================================

_gcia_evaluate() { # <target_dir> <cfg_email> <cfg_email_label> <cfg_name> <author_val>
  local target_dir="$1" cfg_email="$2" cfg_label="$3" cfg_name="$4" author_val="$5"
  _GCIA_VIOLATION=0
  _GCIA_AUTO_SET_NOTE=""

  # m1-minor (round 2): a repo this same command `git init`s is a throwaway.
  if _gcia_is_init_dir "$target_dir"; then
    return 0
  fi

  local has_email=0 has_name=0
  { [ -n "$author_val" ] || [ -n "$cfg_email" ] || [ -n "${_GCIA_ENV_AUTHOR_EMAIL:-}" ] || [ -n "${_GCIA_ENV_COMMITTER_EMAIL:-}" ]; } && has_email=1
  { [ -n "$cfg_name" ] || [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] || [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ]; } && has_name=1

  # m2 (PR #67 review round 2, measured 1.7-2.8s per plain commit): with NO
  # override at all, the only remaining job is the auto-set side effect,
  # which fires only when user.email is unset at every level. One
  # `git config --get` answers that — no owner lookup, no gh resolution.
  if [ "$has_email" = "0" ] && [ "$has_name" = "0" ]; then
    if [ -n "$(git -C "$target_dir" config --get user.email 2>/dev/null)" ]; then
      return 0
    fi
  fi

  # M4 (PR #67 review, PROVEN false positive): no resolvable github.com
  # remote owner -> no GitHub ground truth -> fail open entirely.
  if [ -z "$(gh_owner_from_cwd_remote "$target_dir" 2>/dev/null)" ]; then
    return 0
  fi

  if [ "${_GCIA_ACK:-0}" = "1" ] && { [ "$has_email" = "1" ] || [ "$has_name" = "1" ]; }; then
    ledger_emit "gh-commit-author-identity" "waiver" "GIT_COMMIT_IDENTITY_GATE_ACK=1 present; override allowed through for target_dir=${target_dir}"
    return 0
  fi

  local expected_email="" expected_source="unresolved" resolved_expected=0
  local bad_kind="" bad_val="" a_email="" unknown=""
  local -a resolved_vals=()

  if [ "$has_email" = "1" ]; then
    # Collect (kind, value) pairs; an unresolved value is UNKNOWN, not a
    # mismatch (MAJOR-1 P1 / note 4).
    local -a kinds=() vals=()
    if [ -n "$author_val" ]; then
      if _gcia_unresolved "$author_val"; then
        unknown="${unknown}--author=${author_val}; "
      else
        case "$author_val" in
          *"<"*">"*) a_email="${author_val#*<}"; a_email="${a_email%%>*}" ;;
        esac
        # an unparseable --author (no <email>) keeps an empty value, which
        # the comparison below treats as a mismatch: fail closed.
        kinds+=("--author"); vals+=("$a_email"); resolved_vals+=("$a_email")
      fi
    fi
    local k2 v2
    for k2 in cfg AE CE; do
      case "$k2" in
        cfg) v2="$cfg_email" ;;
        AE) v2="${_GCIA_ENV_AUTHOR_EMAIL:-}" ;;
        CE) v2="${_GCIA_ENV_COMMITTER_EMAIL:-}" ;;
      esac
      [ -n "$v2" ] || continue
      if _gcia_unresolved "$v2"; then
        case "$k2" in
          cfg) unknown="${unknown}${cfg_label}=${v2}; " ;;
          AE) unknown="${unknown}GIT_AUTHOR_EMAIL=${v2}; " ;;
          CE) unknown="${unknown}GIT_COMMITTER_EMAIL=${v2}; " ;;
        esac
        continue
      fi
      case "$k2" in
        cfg) kinds+=("$cfg_label") ;;
        AE) kinds+=("GIT_AUTHOR_EMAIL") ;;
        CE) kinds+=("GIT_COMMITTER_EMAIL") ;;
      esac
      vals+=("$v2"); resolved_vals+=("$v2")
    done

    if [ -n "$unknown" ] && declare -F ledger_emit >/dev/null 2>&1; then
      ledger_emit "gh-commit-author-identity" "warn" "identity override value(s) not resolvable before the shell runs (${unknown}) for ${target_dir} — not checked (unknown is not a mismatch)"
    fi

    if [ "${#kinds[@]}" -gt 0 ]; then
      gia_resolve_expected_email "$target_dir"
      expected_email="$GIA_EMAIL"; expected_source="$GIA_EMAIL_SOURCE"; resolved_expected=1
      if [ -z "$expected_email" ]; then
        # Nothing resolvable -> nothing to check, never a fabricated guess.
        return 0
      fi
      local q
      for ((q=0; q<${#kinds[@]}; q++)); do
        if [ -z "${vals[$q]}" ] || ! gh_ci_eq "${vals[$q]}" "$expected_email"; then
          bad_kind="${kinds[$q]}"
          if [ "${kinds[$q]}" = "--author" ]; then bad_val="$author_val"; else bad_val="${vals[$q]}"; fi
          break
        fi
      done
    fi
  fi

  # m2 (PR #67 review): a NAME-only mismatch is WARNED, never BLOCKED.
  if [ -z "$bad_kind" ] && [ "$has_name" = "1" ]; then
    gia_resolve_expected_name "$target_dir"
    local expected_name="$GIA_NAME"
    if [ -n "$expected_name" ]; then
      local name_bad_kind="" name_bad_val=""
      if [ -n "$cfg_name" ] && ! _gcia_unresolved "$cfg_name" && [ "$cfg_name" != "$expected_name" ]; then
        name_bad_kind="-c user.name"; name_bad_val="$cfg_name"
      elif [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] && ! _gcia_unresolved "$_GCIA_ENV_AUTHOR_NAME" && [ "${_GCIA_ENV_AUTHOR_NAME}" != "$expected_name" ]; then
        name_bad_kind="GIT_AUTHOR_NAME"; name_bad_val="$_GCIA_ENV_AUTHOR_NAME"
      elif [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ] && ! _gcia_unresolved "$_GCIA_ENV_COMMITTER_NAME" && [ "${_GCIA_ENV_COMMITTER_NAME}" != "$expected_name" ]; then
        name_bad_kind="GIT_COMMITTER_NAME"; name_bad_val="$_GCIA_ENV_COMMITTER_NAME"
      fi
      if [ -n "$name_bad_kind" ] && declare -F ledger_emit >/dev/null 2>&1; then
        ledger_emit "gh-commit-author-identity" "warn" "name-only override ${name_bad_kind}=${name_bad_val} != expected ${expected_name} for ${target_dir} (not blocked — attribution is by email, not name)"
      fi
    fi
  fi

  if [ -n "$bad_kind" ]; then
    # MAJOR-3: the harness's own review-record identity, records-only.
    local all_reviewer=1 rv
    for rv in ${resolved_vals[@]+"${resolved_vals[@]}"}; do
      _gcia_is_reviewer_identity "$rv" || { all_reviewer=0; break; }
    done
    [ "${#resolved_vals[@]}" -gt 0 ] || all_reviewer=0
    if [ "$all_reviewer" = "1" ] && _gcia_records_only "$target_dir"; then
      if declare -F ledger_emit >/dev/null 2>&1; then
        ledger_emit "gh-commit-author-identity" "skip" "review-record identity ${bad_kind}=${bad_val} on a records-only commit (docs/reviews/records/**) in ${target_dir} — exempt (review-runner A1 identity stamp)"
      fi
      return 0
    fi
    _GCIA_VIOLATION=1
    _GCIA_VIOLATION_KIND="$bad_kind"
    _GCIA_VIOLATION_DETAIL="${bad_kind}=${bad_val}"
    _GCIA_VIOLATION_VAL="$bad_val"
    _GCIA_VIOLATION_EXPECTED="$expected_email"
    _GCIA_VIOLATION_SOURCE="$expected_source"
    _GCIA_VIOLATION_TARGET="$target_dir"
    _GCIA_VIOLATION_REVIEWER="$all_reviewer"
    return 0
  fi

  # No violation -> optional auto-set (obligation 3): only when the repo has
  # NO user.email at ANY level and the expected value came from the gh API.
  if [ -z "$(git -C "$target_dir" config --get user.email 2>/dev/null)" ]; then
    if [ "$resolved_expected" = "0" ]; then
      gia_resolve_expected_email "$target_dir"
      expected_email="$GIA_EMAIL"; expected_source="$GIA_EMAIL_SOURCE"
    fi
    if [ -n "$expected_email" ] && case "$expected_source" in gh-api*) true ;; *) false ;; esac; then
      if git -C "$target_dir" config user.email "$expected_email" 2>/dev/null; then
        _GCIA_AUTO_SET_NOTE="auto-set user.email=${expected_email} for ${target_dir} (was unset; resolved via ${expected_source})"
        ledger_emit "gh-commit-author-identity" "warn" "$_GCIA_AUTO_SET_NOTE"
      fi
    fi
  fi
  return 0
}

_gcia_block() {
  local what why fix escape
  what="this commit sets identity via ${_GCIA_VIOLATION_DETAIL}, which does not match the identity expected for ${_GCIA_VIOLATION_TARGET} (${_GCIA_VIOLATION_EXPECTED}, resolved via ${_GCIA_VIOLATION_SOURCE})"
  if [ "$_GCIA_VIOLATION_KIND" = "git config user.email" ]; then
    what="${what} — the value comes from a \`git config user.email\` SET earlier in this same command, which persists into the commit"
  fi
  why="Commits from Claude agents must carry the identity of the GitHub account logged in for the repo being committed to — never whatever email/name Claude Code's own session context hands the agent. A mismatch has already blocked a production deploy (Vercel maps commit emails to Vercel users; a downstream project's PR, 2026-09-21, ~1hr cost)."
  case "$_GCIA_VIOLATION_KIND" in
    "git config user.email")
      fix="do not set user.email in this command — the commit resolves to ${_GCIA_VIOLATION_EXPECTED} (resolved via ${_GCIA_VIOLATION_SOURCE}) on its own; if ${_GCIA_VIOLATION_TARGET}'s configured user.email is wrong, set it to that value instead"
      ;;
    *)
      fix="drop the override so the commit resolves to ${_GCIA_VIOLATION_EXPECTED} (resolved via ${_GCIA_VIOLATION_SOURCE}) — if ${_GCIA_VIOLATION_TARGET}'s own \`git config user.email\` differs from this value, fix the config there instead of relying on an inline override"
      ;;
  esac
  if [ "${_GCIA_VIOLATION_REVIEWER:-0}" = "1" ]; then
    fix="${fix}. A reviewer+<session>@<host> identity is exempt ONLY on a records-only commit (every path under docs/reviews/records/, named via \`git commit ... -- <record.json> docs/reviews/records/index.json\`); for a review record, re-run \`bash scripts/review-runner.sh finalize\` or scope the commit to exactly the record files"
  fi
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
    echo "NOTE: this block prevented the ENTIRE command from running — including any"
    echo "fix/edit/git add prefix before the git commit. Nothing was executed. Re-run"
    echo "the non-commit part as its own call first, then commit separately. (NL-FINDING-016)"
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
  # M1 (PR #67 review): the SAME verb-substring set as the raw prefilter.
  case "$cmd" in *commit*|*merge*|*cherry-pick*|*revert*|*pull*|*rebase*|*' am'*) : ;; *) exit 0 ;; esac
  case "$cmd" in *git*) : ;; *) exit 0 ;; esac
  command -v git >/dev/null 2>&1 || { exit 0; }

  cwd="$(_gcia_cwd)"
  [ -n "$cwd" ] || cwd="$PWD"

  _gcia_reset_env_state
  _GCIA_INIT_DIRS=(); _GCIA_ADD_PATHS=(); _GCIA_ADD_DIRS=()

  # MAJOR-1 notes 1-2: normalize the WHOLE command before splitting.
  _gcia_normalize_ansi_c "$cmd"; cmd="$_GCIA_NORM"
  _gcia_strip_heredoc_bodies "$cmd"; cmd="$_GCIA_NORM"

  gcp_split_command "$cmd"
  local n=${#GCP_SEGMENTS[@]} i seg cd_target="" j
  local violation=0 auto_note=""
  # m1 / r2-1: a `git config user.email X` SET earlier in the same command
  # persists into a later commit-creating segment IN THE SAME REPO only.
  local cfg_track_email="" cfg_track_name="" cfg_track_dir=""

  for ((i=0; i<n; i++)); do
    seg="${GCP_SEGMENTS[$i]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [ -n "$seg" ] || continue

    seg="$(_gcia_strip_env_prefix "$seg")"
    [ -n "$seg" ] || continue

    # MAJOR-1 note 3: substitute assignments seen earlier in this command.
    if [ "${#GCP_VAR_NAMES[@]}" -gt 0 ]; then
      gcp_subst_vars_var "$seg"; seg="$GCP_SUBSTITUTED"
    fi

    GCP_ASSIGN_NAMES=(); GCP_ASSIGN_VALUES=()
    gcp_strip_env_assignments_var "$seg"
    if [ -z "$GCP_STRIPPED" ]; then
      # Assignment-only segment: shell variables for the rest of the command.
      for ((j=0; j<${#GCP_ASSIGN_NAMES[@]}; j++)); do
        _gcia_note_persistent "${GCP_ASSIGN_NAMES[$j]}" "${GCP_ASSIGN_VALUES[$j]}"
      done
      continue
    fi
    _GCIA_SEG_AN=(${GCP_ASSIGN_NAMES[@]+"${GCP_ASSIGN_NAMES[@]}"})
    _GCIA_SEG_AV=(${GCP_ASSIGN_VALUES[@]+"${GCP_ASSIGN_VALUES[@]}"})
    seg="$GCP_STRIPPED"

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

    _gcia_analyze_segment "$GCP_STRIPPED" "$base"

    if _gcia_maybe_config_set; then
      case "$_GCIA_CFGSET_KEY" in
        user.email) cfg_track_email="$_GCIA_CFGSET_VAL" ;;
        user.name) cfg_track_name="$_GCIA_CFGSET_VAL" ;;
      esac
      cfg_track_dir="$_GCIA_TARGET_DIR"
      continue
    fi
    case "$_GCIA_SUB" in
      init) _gcia_init_dir; _GCIA_INIT_DIRS+=("$_GCIA_INIT_RESULT"); continue ;;
      add) _gcia_note_add; continue ;;
    esac

    [ "$_GCIA_IS_TARGET" = "1" ] || continue

    _gcia_effective_env

    # A tracked earlier config SET folds in only when this segment carries
    # no explicit -c of its own (git's last-wins) AND targets the repo the
    # config was set in (r2-1, PR #67 review round 2, PROVEN: a set in repo
    # A followed by `cd B && git commit` blocked B's commit).
    local eff_cfg_email="$_GCIA_CFG_EMAIL" eff_cfg_name="$_GCIA_CFG_NAME" eff_label="-c user.email"
    if [ -z "$eff_cfg_email" ] && [ -n "$cfg_track_email" ] && _gcia_same_repo "$cfg_track_dir" "$_GCIA_TARGET_DIR"; then
      eff_cfg_email="$cfg_track_email"; eff_label="git config user.email"
    fi
    if [ -z "$eff_cfg_name" ] && [ -n "$cfg_track_name" ] && _gcia_same_repo "$cfg_track_dir" "$_GCIA_TARGET_DIR"; then
      eff_cfg_name="$cfg_track_name"
    fi

    _gcia_evaluate "$_GCIA_TARGET_DIR" "$eff_cfg_email" "$eff_label" "$eff_cfg_name" "$_GCIA_AUTHOR_VAL"
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

  # ============================================================
  # PR #67 review ROUND 2 — a pinned NEGATIVE (must allow) and POSITIVE
  # (must still block) case for every fixed shape.
  # ============================================================
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  git -C "$gr" config user.email "acct-work@example.test"
  local NL=$'\n' okmail='Me <acct-work@example.test>'

  _case() { # <label> <want-rc> <cmd> <cwd> [<grep-in-OUT>]
    _run "$3" "$4"
    if [ "$RC" = "$2" ] && { [ -z "${5:-}" ] || printf '%s' "$OUT" | grep -qF -- "$5"; }; then
      echo "  $1: PASS"; pass=$((pass+1))
    else
      echo "  $1: FAIL (rc=$RC want=$2 out=[$OUT])"; fail=$((fail+1))
    fi
  }

  # MAJOR-1 F1: heredoc-in-$(...) message quoting "git commit --author=..."
  local f1body="fix: quoting${NL}${NL}See \"git commit --author=Someone <x@y.test>\" in the docs.${NL}EOF${NL})\""
  _case "R2 MAJOR-1 F1 negative: quoted --author inside heredoc message is data (allow)" 0 \
    "git commit --author=\"${okmail}\" -m \"\$(cat <<'EOF'${NL}${f1body}" "$gr"
  _case "R2 MAJOR-1 F1 negative: same message, no override at all (allow)" 0 \
    "git commit -m \"\$(cat <<'EOF'${NL}${f1body}" "$gr"
  _case "R2 MAJOR-1 F1 positive: real --author AFTER the heredoc message still blocked" 2 \
    "git commit -m \"\$(cat <<'EOF'${NL}${f1body} --author=\"X <wrong@example.test>\"" "$gr" "wrong@example.test"

  # MAJOR-1 F4: `git commit -F - <<'EOF'` whose body mentions --author=
  _case "R2 MAJOR-1 F4 negative: heredoc body mentioning --author= is data (allow)" 0 \
    "git -c user.email=acct-work@example.test commit -F - <<'EOF'${NL}docs: explain --author=Foo <foo@example.test>${NL}EOF" "$gr"
  _case "R2 MAJOR-1 F4 positive: real -c override on a heredoc-message commit blocked" 2 \
    "git -c user.email=wrong@example.test commit -F - <<'EOF'${NL}body${NL}EOF" "$gr" "wrong@example.test"

  # MAJOR-1 R1: ANSI-C $'...' holding git text (with \' escapes)
  _case "R2 MAJOR-1 R1 negative: ANSI-C string holding git --author text is data (allow)" 0 \
    "HD=\$'git commit --author=\"C <wrong@example.test>\" -m \"\$(cat <<\\'EOF\\'\\nx\\nEOF\\n)\"'${NL}echo \"\$HD\" && git -c user.email=acct-work@example.test commit -m x" "$gr"
  _case "R2 MAJOR-1 R1 positive: ANSI-C message then a real --author mismatch blocked" 2 \
    "git commit -m \$'line1\\nit\\'s line2' --author=\"X <wrong@example.test>\"" "$gr" "wrong@example.test"

  # MAJOR-1 P1: same-command assignment expanded; unresolved -> unknown
  _case "R2 MAJOR-1 P1 negative: E=<matching> && GIT_AUTHOR_EMAIL=\"\$E\" (allow)" 0 \
    'E=acct-work@example.test && GIT_AUTHOR_EMAIL="$E" git commit -m x' "$gr"
  _case "R2 MAJOR-1 P1 positive: E=<wrong> && GIT_AUTHOR_EMAIL=\"\$E\" blocked with the REAL value" 2 \
    'E=wrong@example.test && GIT_AUTHOR_EMAIL="$E" git commit -m x' "$gr" "GIT_AUTHOR_EMAIL=wrong@example.test"
  rm -f "$SIGNAL_LEDGER_PATH"
  _run 'GIT_AUTHOR_EMAIL="$FROM_AN_EARLIER_CALL" git commit -m x' "$gr"
  if [ "$RC" = "0" ] && grep -q 'not resolvable before the shell runs' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "  R2 MAJOR-1 unresolved \$VAR is UNKNOWN (allow + ledger warn), not a mismatch: PASS"; pass=$((pass+1))
  else
    echo "  R2 MAJOR-1 unresolved \$VAR is UNKNOWN (allow + ledger warn): FAIL (rc=$RC ledger=$(cat "$SIGNAL_LEDGER_PATH" 2>/dev/null))"; fail=$((fail+1))
  fi
  _case "R2 MAJOR-1 escaped \\\" inside -m cannot expose --author text (allow)" 0 \
    'git commit -m "x \" --author=a <b@example.test> \" y" --author="M <acct-work@example.test>"' "$gr"
  _case "R2 command-scoped prefix on a NON-commit segment does not leak (allow)" 0 \
    'GIT_AUTHOR_EMAIL=wrong@example.test git add f.txt && git commit -m x' "$gr"

  # MAJOR-3: the harness's own review-record commits
  rm -f "$SIGNAL_LEDGER_PATH"
  _run 'GIT_AUTHOR_NAME="review-runner" GIT_AUTHOR_EMAIL="reviewer+sess-1@host-a" GIT_COMMITTER_NAME="review-runner" GIT_COMMITTER_EMAIL="reviewer+sess-1@host-a" git commit -q -m "review-record(rq-1): PASS on 1 file(s)" -- docs/reviews/records/2026-01-01-harness-change-review-abc.json docs/reviews/records/index.json 2>&1' "$gr"
  if [ "$RC" = "0" ] && grep -q '"event":"skip"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "  R2 MAJOR-3 negative: reviewer+ identity on a records-only pathspec commit exempt (+ ledger skip): PASS"; pass=$((pass+1))
  else
    echo "  R2 MAJOR-3 negative: reviewer+ records-only pathspec exempt: FAIL (rc=$RC out=[$OUT] ledger=$(cat "$SIGNAL_LEDGER_PATH" 2>/dev/null))"; fail=$((fail+1))
  fi
  _case "R2 MAJOR-3 negative: reviewer+ identity, records staged by a git add in the same command (allow)" 0 \
    'git add docs/reviews/records/r.json docs/reviews/records/index.json && GIT_AUTHOR_EMAIL=reviewer+s@h GIT_COMMITTER_EMAIL=reviewer+s@h git commit -m "review-record(x)"' "$gr"
  _case "R2 MAJOR-3 positive: reviewer+ identity on a NON-records path blocked (names the runner)" 2 \
    'GIT_AUTHOR_EMAIL=reviewer+s@h git commit -m x -- src/app.ts' "$gr" "review-runner.sh finalize"
  _case "R2 MAJOR-3 positive: reviewer+ identity with records + one other path blocked" 2 \
    'GIT_AUTHOR_EMAIL=reviewer+s@h git commit -m x -- docs/reviews/records/index.json README.md' "$gr" "reviewer+s@h"
  _case "R2 MAJOR-3 positive: reviewer+ identity with commit -a blocked" 2 \
    'GIT_AUTHOR_EMAIL=reviewer+s@h git commit -am x' "$gr" "reviewer+s@h"
  _case "R2 MAJOR-3 positive: a NON-reviewer identity on a records-only commit still blocked" 2 \
    'GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x -- docs/reviews/records/index.json' "$gr" "wrong@example.test"

  # m1-minor: pre-existing non-repo dir inside a GitHub checkout + git init
  mkdir -p "$gr/scratch-sub"
  _case "R2 m1 negative: cd existing-subdir && git init && -c commit fails open (throwaway repo)" 0 \
    'cd scratch-sub && git init -q && git -c user.email=t@t.example commit --allow-empty -m base' "$gr"
  _case "R2 m1 positive: same subdir WITHOUT git init is the enclosing repo -> blocked" 2 \
    'cd scratch-sub && git -c user.email=wrong@example.test commit -m x' "$gr" "wrong@example.test"

  # m5 / r2-1: a tracked `git config user.email` is scoped to ITS repo
  _case "R2 r2-1 negative: config set in repo A, then cd B && commit -> not applied to B (allow)" 0 \
    "git config user.email wrong@example.test && cd ${gr2} && git commit -m x" "$gr"
  _case "R2 r2-1 positive: git -C B config user.email, then cd B && commit -> blocked, labelled as a config SET" 2 \
    "git -C ${gr2} config user.email wrong@example.test && cd ${gr2} && git commit -m x" "$gr" "SET earlier in this same command"

  # m4: block message carries the NL-FINDING-016 whole-command note
  _case "R2 m4 block message states the ENTIRE command did not run" 2 \
    'git add a.txt && git commit -m x --author="S <wrong@example.test>"' "$gr" "prevented the ENTIRE command from running"

  # m2: short-circuit — no override + configured user.email = no gh calls
  rm -f "$GIA_STATE_DIR"/*.txt "$GIA_STATE_DIR"/*.negative
  calls="$tmp/calls-shortcircuit.txt"; : > "$calls"
  RC=0
  GCIA_CMD='git commit -m "plain"' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1 || RC=$?
  if [ "$RC" = "0" ] && [ ! -s "$calls" ]; then
    echo "  R2 m2 plain commit with configured user.email short-circuits (zero gh calls): PASS"; pass=$((pass+1))
  else
    echo "  R2 m2 plain commit short-circuit: FAIL (rc=$RC calls=$(cat "$calls" 2>/dev/null))"; fail=$((fail+1))
  fi

  # m3: SSH host-alias remote resolves to its github.com owner (was fail-open)
  if command -v ssh >/dev/null 2>&1; then
    printf 'Host gh-alias-test\n  HostName github.com\nHost not-gh-alias\n  HostName git.example.test\n' > "$tmp/ssh_config"
    local gra="$tmp/repo-alias" grn="$tmp/repo-alias-nongh"
    mkdir -p "$gra" "$grn"
    ( cd "$gra" && git init -q 2>/dev/null && git remote add origin "git@gh-alias-test:work-org/some-repo.git" 2>/dev/null && git config user.email "acct-work@example.test" )
    ( cd "$grn" && git init -q 2>/dev/null && git remote add origin "git@not-gh-alias:work-org/some-repo.git" 2>/dev/null && git config user.email "x@example.test" )
    export GHLIB_SSH_CONFIG="$tmp/ssh_config"
    _case "R2 m3 positive: ssh host-alias remote (github-<alias>) enforced -> blocked" 2 \
      'git -c user.email=wrong@example.test commit -m x' "$gra" "acct-work@example.test"
    _case "R2 m3 negative: ssh alias to a NON-github host fails open (allow)" 0 \
      'git -c user.email=wrong@example.test commit -m x' "$grn"
    unset GHLIB_SSH_CONFIG
  else
    echo "  R2 m3 ssh-alias cases SKIPPED: no ssh binary on this machine"
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
