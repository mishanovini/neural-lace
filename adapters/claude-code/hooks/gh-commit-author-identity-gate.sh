#!/usr/bin/env bash
# gh-commit-author-identity-gate.sh — PreToolUse (matcher "Bash"): BLOCK a
# `git commit` / `git commit-tree` whose command overrides author/committer
# identity to something other than the identity expected for the repo it
# targets.
#
# ============================================================
# WHY THIS EXISTS (GH-COMMIT-IDENTITY-01, operator directive 2026-09-27,
# golden scenario)
# ============================================================
#
# 2026-09-21, Circuit PR #1871: fixer subagents committed with author
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
# A `git commit` or `git commit-tree` invocation (working-tree commits AND
# raw commit-object writes — commit-tree is explicitly in scope even though
# hooks/lib/git-command-parse.sh's own gcp_resolve_commit_target deliberately
# excludes it for ITS callers; this gate needs the broader match, so it
# tokenizes and walks each git segment itself rather than reusing that
# function's IS_COMMIT verdict) that overrides identity via ANY of:
#   - `--author=<name> <email>` (or separated `--author <value>`) whose
#     <email> does not match the expected email
#   - `-c user.email=<val>` (separated or glued `-c<key>=<val>`) mismatch
#   - `-c user.name=<val>` mismatch against the repo's OWN current
#     `git config user.name` (see the lib header: there is no independent
#     "expected name" oracle, so a name override is judged against what the
#     repo is already configured to use)
#   - `GIT_AUTHOR_EMAIL=` / `GIT_COMMITTER_EMAIL=` / `GIT_AUTHOR_NAME=` /
#     `GIT_COMMITTER_NAME=`, whether set as a command-scoped prefix on the
#     commit segment itself (`FOO=bar git commit`) or via an earlier
#     `export FOO=bar` segment in the SAME command (these persist for the
#     rest of that one shell process, exactly like a real shell) — but NOT
#     an env var exported in a DIFFERENT, earlier Bash tool call (a named,
#     accepted residual: this hook only ever sees one command at a time).
#
# The target repo is resolved the same way git itself would (`-C`,
# `--work-tree`, `--git-dir`, accumulated `cd`/`pushd`, in that priority),
# so `git -C <other-repo> commit --author=...` is judged against
# <other-repo>'s expected identity, not the invoking cwd's.
#
# ============================================================
# WHAT IT ALLOWS
# ============================================================
#   - Any commit with no identity override at all (the overwhelming case).
#   - An override that MATCHES the expected identity (case-insensitive on
#     email — not an override in effect, just spelling it out explicitly).
#   - `GIT_COMMIT_IDENTITY_GATE_ACK=1` present anywhere in the same
#     resolution chain that fed a candidate override (command-scoped prefix,
#     or an earlier `export`) — the ONE sanctioned escape, for the genuine
#     case of committing on someone else's behalf (e.g. preserving original
#     authorship on a manually-applied patch). Per constitution §7, this is
#     for the user's explicit, in-conversation say-so — never set
#     preemptively by an agent to talk itself past this gate. Every ack use
#     is logged (ledger event "waiver"), so a pattern of acks is visible to
#     later review, not silently invisible.
#   - When NO expected identity is resolvable at all (the repo's owner
#     account also lacks the gh API `user` scope AND the repo carries no
#     git config identity of its own) -> fails OPEN. There is no ground
#     truth to check an override against, and never never fabricates one to
#     check against (see the lib's noreply-never-used guarantee).
#
# ============================================================
# OPTIONAL SIDE EFFECT (operator's call, documented rationale)
# ============================================================
# When a commit/commit-tree segment carries NO override at all, and the
# target repo has NO `user.email` configured at ANY level (neither local nor
# global), and an expected email WAS resolved via the gh API (not the
# fallback — the fallback rung requires config to already exist, so by
# construction it cannot fire here) -> this gate sets `user.email` on that
# repo, ONCE, and prints a non-blocking note (never a silent side effect).
# Rationale: an unconfigured worktree committing under whatever ambient
# identity git falls back to (which can be wrong, or can error outright) is
# the exact same class of problem this gate exists to prevent, just via a
# different path (an ABSENT identity instead of an OVERRIDDEN one) — fixing
# it once, quietly, at the point where the correct value is already in hand,
# is cheaper than blocking every future commit from that worktree.
#
# ============================================================
# NEVER BLOCKS ON:
# ============================================================
#   - non-commit, non-commit-tree commands (fast substring prefilter)
#   - internal limitation (no jq available for payload parsing when
#     CLAUDE_TOOL_INPUT/stdin carries no usable command text; no git binary)
#
# Self-test: bash gh-commit-author-identity-gate.sh --self-test

set -u

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
# env-var and GCIA_CMD/GCIA_CWD self-test overrides.
# ============================================================

_gcia_read_payload() {
  if [ -z "${GCIA_CMD:-}" ] && [ -z "${CLAUDE_TOOL_INPUT:-}" ]; then
    _GCIA_PAYLOAD="$(cat 2>/dev/null || true)"
  fi
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

  case "$sub" in
    commit|commit-tree) _GCIA_IS_TARGET=1 ;;
    *) return 0 ;;
  esac

  if [ -n "$work_tree" ]; then _GCIA_TARGET_DIR="$work_tree"
  elif [ -n "$git_dir" ]; then _GCIA_TARGET_DIR="${git_dir%/.git}"
  elif [ -n "$c_target" ]; then _GCIA_TARGET_DIR="$c_target"
  else _GCIA_TARGET_DIR="$base"
  fi

  # Phase 2: subcommand-level flags — only --author matters here.
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

  if [ -z "$bad_kind" ] && { [ -n "$cfg_name" ] || [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] || [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ]; }; then
    gia_resolve_expected_name "$target_dir"
    local expected_name="$GIA_NAME"
    if [ -n "$expected_name" ]; then
      if [ -n "$cfg_name" ] && [ "$cfg_name" != "$expected_name" ]; then
        bad_kind="-c user.name"; bad_val="$cfg_name"
      elif [ -n "${_GCIA_ENV_AUTHOR_NAME:-}" ] && [ "${_GCIA_ENV_AUTHOR_NAME}" != "$expected_name" ]; then
        bad_kind="GIT_AUTHOR_NAME"; bad_val="$_GCIA_ENV_AUTHOR_NAME"
      elif [ -n "${_GCIA_ENV_COMMITTER_NAME:-}" ] && [ "${_GCIA_ENV_COMMITTER_NAME}" != "$expected_name" ]; then
        bad_kind="GIT_COMMITTER_NAME"; bad_val="$_GCIA_ENV_COMMITTER_NAME"
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
  why="Commits from Claude agents must carry the identity of the GitHub account logged in for the repo being committed to — never whatever email/name Claude Code's own session context hands the agent. A mismatch has already blocked a production deploy (Vercel maps commit emails to Vercel users; Circuit PR #1871, 2026-09-21, ~1hr cost)."
  fix="drop the override so the commit uses ${_GCIA_VIOLATION_EXPECTED} (git's own default identity resolution for ${_GCIA_VIOLATION_TARGET})"
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
  case "$cmd" in *commit*) : ;; *) exit 0 ;; esac
  case "$cmd" in *git*) : ;; *) exit 0 ;; esac
  command -v git >/dev/null 2>&1 || { exit 0; }

  cwd="$(_gcia_cwd)"
  [ -n "$cwd" ] || cwd="$PWD"

  _gcia_reset_env_state

  gcp_split_command "$cmd"
  local n=${#GCP_SEGMENTS[@]} i seg cd_target="" j
  local violation=0 auto_note=""

  for ((i=0; i<n; i++)); do
    seg="${GCP_SEGMENTS[$i]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
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

    _gcia_analyze_segment "$GCP_STRIPPED" "$base"
    [ "$_GCIA_IS_TARGET" = "1" ] || continue

    _gcia_evaluate "$_GCIA_TARGET_DIR" "$_GCIA_CFG_EMAIL" "$_GCIA_CFG_NAME" "$_GCIA_AUTHOR_VAL"
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
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'git commit -m "x" --author="Someone <wrong@example.test>"' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q '\[GATE:WHAT\]' && printf '%s' "$OUT" | grep -q 'acct-work@example.test' && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  override-blocked (--author mismatch): PASS"; pass=$((pass+1))
  else
    echo "  override-blocked (--author mismatch): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- matching override allowed --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'git commit -m "x" --author="Someone <acct-work@example.test>"' "$gr"
  if [ "$RC" = "0" ]; then
    echo "  matching-override-allowed (--author matches expected): PASS"; pass=$((pass+1))
  else
    echo "  matching-override-allowed (--author matches expected): FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- no override allowed (+ auto-set side effect) --------
  rm -f "$GIA_STATE_DIR"/*.txt
  git -C "$gr" config --unset user.email 2>/dev/null || true
  _run 'git commit -m "plain commit, no override"' "$gr"
  local set_email; set_email="$(git -C "$gr" config --get user.email 2>/dev/null)"
  if [ "$RC" = "0" ] && [ "$set_email" = "acct-work@example.test" ] && printf '%s' "$OUT" | grep -q 'auto-set'; then
    echo "  no-override-allowed (+ auto-set unset user.email): PASS"; pass=$((pass+1))
  else
    echo "  no-override-allowed (+ auto-set unset user.email): FAIL (rc=$RC set_email=$set_email out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- scope-missing fallback (gh api 404-equivalent) --------
  rm -f "$GIA_STATE_DIR"/*.txt
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
  rm -f "$GIA_STATE_DIR"/*.txt
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
  rm -f "$GIA_STATE_DIR"/*.txt
  local a_blob a_tree
  a_tree="$(git -C "$gr" write-tree 2>/dev/null || echo "4b825dc642cb6eb9a060e54bf8d69288fbee4904")"
  _run "git -c user.email=wrong@example.test commit-tree ${a_tree} -m x" "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'wrong@example.test'; then
    echo "  commit-tree recognized as identity-bearing: PASS"; pass=$((pass+1))
  else
    echo "  commit-tree recognized as identity-bearing: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- -c user.name mismatch (against repo's OWN configured name) --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'git -c user.name="Wrong Name" commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'Wrong Name' && printf '%s' "$OUT" | grep -q 'user.name'; then
    echo "  -c user.name mismatch blocked: PASS"; pass=$((pass+1))
  else
    echo "  -c user.name mismatch blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- glued -c form --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'git -cuser.email=wrong@example.test commit -m x' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  glued -c<key>=<val> form parsed and blocked: PASS"; pass=$((pass+1))
  else
    echo "  glued -c<key>=<val> form parsed and blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- env var via command-scoped prefix --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_AUTHOR_EMAIL'; then
    echo "  GIT_AUTHOR_EMAIL command-scoped prefix blocked: PASS"; pass=$((pass+1))
  else
    echo "  GIT_AUTHOR_EMAIL command-scoped prefix blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- env var via earlier export segment --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'export GIT_COMMITTER_EMAIL=wrong@example.test && git commit -m x' "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'GIT_COMMITTER_EMAIL'; then
    echo "  export in an earlier segment blocked: PASS"; pass=$((pass+1))
  else
    echo "  export in an earlier segment blocked: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- ack escape allows through, and is logged as a waiver --------
  rm -f "$GIA_STATE_DIR"/*.txt "$SIGNAL_LEDGER_PATH"
  _run 'GIT_COMMIT_IDENTITY_GATE_ACK=1 GIT_AUTHOR_EMAIL=wrong@example.test git commit -m x' "$gr"
  if [ "$RC" = "0" ] && grep -q '"gate":"gh-commit-author-identity"' "$SIGNAL_LEDGER_PATH" 2>/dev/null && grep -q '"event":"waiver"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
    echo "  GIT_COMMIT_IDENTITY_GATE_ACK=1 escape allows through + logs waiver: PASS"; pass=$((pass+1))
  else
    echo "  GIT_COMMIT_IDENTITY_GATE_ACK=1 escape allows through + logs waiver: FAIL (rc=$RC ledger=$(cat "$SIGNAL_LEDGER_PATH" 2>/dev/null))"; fail=$((fail+1))
  fi

  # -------- -C target dir resolution: wrong-account identity used against a
  # DIFFERENT repo than cwd, resolved via -C, must be judged against THAT
  # repo's expected identity --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run "git -C ${gr2} commit -m x --author=\"X <acct-work@example.test>\"" "$gr"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'acct-personal@example.test'; then
    echo "  -C target dir drives expected-identity lookup: PASS"; pass=$((pass+1))
  else
    echo "  -C target dir drives expected-identity lookup: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- non-commit command -> no-op, no gh calls --------
  rm -f "$GIA_STATE_DIR"/*.txt
  calls="$tmp/calls-status.txt"; : > "$calls"
  RC=0
  GCIA_CMD='git status' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1 || RC=$?
  if [ "$RC" = "0" ] && [ ! -s "$calls" ]; then
    echo "  non-commit command -> no-op, no gh calls: PASS"; pass=$((pass+1))
  else
    echo "  non-commit command -> no-op, no gh calls: FAIL (rc=$RC calls=$(cat "$calls" 2>/dev/null))"; fail=$((fail+1))
  fi

  # -------- unparseable --author value fails closed (ambiguous identity) --------
  rm -f "$GIA_STATE_DIR"/*.txt
  _run 'git commit -m x --author=not-an-email-shape' "$gr"
  if [ "$RC" = "2" ]; then
    echo "  unparseable --author value fails closed: PASS"; pass=$((pass+1))
  else
    echo "  unparseable --author value fails closed: FAIL (rc=$RC out=[$OUT])"; fail=$((fail+1))
  fi

  # -------- cache reused across two commits in the sweep (no repeated gh api calls) --------
  rm -f "$GIA_STATE_DIR"/*.txt
  calls="$tmp/calls-cache.txt"; : > "$calls"
  GCIA_CMD='git commit -m x' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1
  GCIA_CMD='git commit -m x --author="A <acct-work@example.test>"' GCIA_CWD="$gr" GIA_STUB_CALLS="$calls" bash "$SELF" >/dev/null 2>&1
  local n_calls; n_calls="$(grep -c '^api-user-emails' "$calls" 2>/dev/null || echo 0)"
  if [ "$n_calls" = "1" ]; then
    echo "  cache reused across invocations (1 gh-api call for 2 commits): PASS"; pass=$((pass+1))
  else
    echo "  cache reused across invocations (1 gh-api call for 2 commits): FAIL (calls=$n_calls)"; fail=$((fail+1))
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
