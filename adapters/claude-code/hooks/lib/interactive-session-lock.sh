#!/bin/bash
# interactive-session-lock.sh — sourced library (NL Overhaul task B.12)
#
# Classification: Mechanism (guard library consumed by unattended tree-mutators)
#
# THE CONTRACT (binding on every unattended script that mutates a working tree):
#
#   EVERY unattended script that mutates a git working tree — checkout,
#   cherry-pick, reset, merge, clean, or anything that triggers install.sh —
#   MUST call `isl_live_session <repo-root>` BEFORE its first mutation, and
#   when the lock reports LIVE (exit 0) it MUST refuse the run and log the
#   refusal via `isl_refuse_log <repo-root> <daemon-name>`. The future
#   Component-C cross-machine sync daemon INHERITS this contract verbatim —
#   any daemon-class mutator added later starts by sourcing this lib.
#
#   Operator-attended runs may bypass with ISL_BYPASS=1; the bypass is still
#   logged (call `isl_refuse_log <repo-root> <daemon-name> bypassed` before
#   proceeding) so the audit trail shows every time the guard was skipped.
#
#   This lock is the STOPGAP (option A of the originating discovery,
#   docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md).
#   The DURABLE fix remains option C — unattended sync operates on a dedicated
#   clone/bare mirror and never touches a working tree a human develops in —
#   scheduled as a Wave E/F follow-on of the NL overhaul program.
#
# WHY: an unattended sync daemon performing checkout/cherry-pick/reset on the
# SAME checkout an interactive session is developing in silently sweeps
# uncommitted work into foreign commits, moves HEAD between the session's tool
# calls, and corrupts the live harness mirror via install.sh runs from
# transient branches (the GAP-51 failure class). The lock makes "is a human
# session live on this tree right now?" a single cheap check.
#
# API (all functions are safe to call from `set -u` callers):
#
#   isl_live_session <repo-root>
#     exit 0 ("locked" — an interactive session is live) when EITHER
#       (a) the explicit lock file <repo-root>/.claude/state/interactive-session.lock
#           exists with mtime younger than ISL_WINDOW_MIN (default 15) minutes, OR
#       (b) any transcript *.jsonl under <projects-root>/<project-slug-of-repo-root>/
#           has mtime younger than ISL_WINDOW_MIN minutes.
#     exit 1 ("unlocked") otherwise.
#
#   isl_refuse_log <repo-root> <daemon-name> [verdict]
#     Appends one line to the refusal log (default
#     ~/.claude/logs/interactive-session-lock.log). verdict defaults to
#     "refused"; pass "bypassed" when proceeding under ISL_BYPASS=1.
#     Always returns 0 (logging is best-effort; never blocks the caller).
#
#   isl_project_slug_candidates <abs-path>
#     Emits (one per line) the candidate Claude Code project-dir slugs for the
#     path: the absolute path with every '/', ':', '\', ' ' (space) and '.'
#     replaced by '-' (consecutive dashes NOT collapsed — Claude Code's
#     ~/.claude/projects/<slug>/ convention), plus a Windows-native variant
#     when the input is an MSYS-style /x/... path, plus a cygpath -w variant
#     when cygpath is available.
#
# TUNABLES (env, read at call time):
#   ISL_WINDOW_MIN     liveness window in minutes (default 15)
#   ISL_PROJECTS_ROOT  Claude Code projects tree (default ~/.claude/projects)
#   ISL_LOG_FILE       refusal-log path (default ~/.claude/logs/interactive-session-lock.log)
#   ISL_BYPASS         =1 → caller proceeds despite the lock (operator-attended;
#                      still logged). Honored by CALLERS, not by isl_live_session.
#   HARNESS_SELFTEST   =1 → sandbox mode: when ISL_LOG_FILE is unset the log
#                      defaults into $TMPDIR instead of ~/.claude/logs so a
#                      self-test can never touch the real log.
#
# Self-test: `bash interactive-session-lock.sh --self-test` (only when executed
# directly; sourcing never runs it). All scenarios sandboxed in mktemp -d under
# HARNESS_SELFTEST=1.

# --- slug derivation --------------------------------------------------------
# Claude Code names each project's transcript dir after the absolute checkout
# path with [/:\ .] -> '-' (no dash-collapsing). A repo path can be seen in
# multiple spellings (POSIX, MSYS /x/..., Windows-native X:\...), so emit every
# plausible candidate; the caller probes each for an existing dir.
isl_project_slug_candidates() {
  local p="${1:-}"
  [ -n "$p" ] || return 0

  # Candidate 1: the path exactly as given.
  printf '%s\n' "$p" | tr '/:\\ .' '-----'

  # Candidate 2: MSYS-style /x/rest -> X:\rest (Git Bash exposes Windows
  # drives this way, but Claude Code derives the slug from the native form).
  case "$p" in
    /[A-Za-z]/*)
      local drive rest native
      drive=$(printf '%s' "${p:1:1}" | tr 'a-z' 'A-Z')
      rest="${p:3}"
      native="${drive}:\\${rest//\//\\}"
      printf '%s\n' "$native" | tr '/:\\ .' '-----'
      ;;
  esac

  # Candidate 3: cygpath's Windows-native rendering, when available.
  if command -v cygpath >/dev/null 2>&1; then
    local w
    w=$(cygpath -w "$p" 2>/dev/null || true)
    [ -n "$w" ] && printf '%s\n' "$w" | tr '/:\\ .' '-----'
  fi
  return 0
}

# --- liveness check ---------------------------------------------------------
isl_live_session() {
  local repo_root="${1:-}"
  [ -n "$repo_root" ] || return 1
  local window="${ISL_WINDOW_MIN:-15}"

  # (a) explicit lock file, fresh.
  local lock="$repo_root/.claude/state/interactive-session.lock"
  if [ -f "$lock" ] && [ -n "$(find "$lock" -mmin "-$window" 2>/dev/null)" ]; then
    return 0
  fi

  # (b) any fresh transcript under the repo's Claude projects slug dir.
  local projects_root="${ISL_PROJECTS_ROOT:-$HOME/.claude/projects}"
  local slug dir
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    dir="$projects_root/$slug"
    [ -d "$dir" ] || continue
    if [ -n "$(find "$dir" -name '*.jsonl' -type f -mmin "-$window" 2>/dev/null | head -n 1)" ]; then
      return 0
    fi
  done < <(isl_project_slug_candidates "$repo_root")

  return 1
}

# --- refusal logging --------------------------------------------------------
isl_refuse_log() {
  local repo_root="${1:-unknown-repo}"
  local daemon="${2:-unknown-daemon}"
  local verdict="${3:-refused}"
  local log_file
  if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    # Sandbox: never touch the real log from a self-test run.
    log_file="${ISL_LOG_FILE:-${TMPDIR:-/tmp}/interactive-session-lock.selftest.log}"
  else
    log_file="${ISL_LOG_FILE:-$HOME/.claude/logs/interactive-session-lock.log}"
  fi
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  printf '%s %s daemon=%s repo=%s window=%smin bypass=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" \
    "$verdict" "$daemon" "$repo_root" "${ISL_WINDOW_MIN:-15}" "${ISL_BYPASS:-0}" \
    >> "$log_file" 2>/dev/null || true
  return 0
}

# ============================ SELF-TEST ======================================
_isl_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)" || { echo "self-test: mktemp failed"; return 1; }

  export HARNESS_SELFTEST=1
  export ISL_PROJECTS_ROOT="$tmp/projects"
  export ISL_LOG_FILE="$tmp/interactive-session-lock.log"
  export ISL_WINDOW_MIN=15

  local repo="$tmp/repo"
  mkdir -p "$repo"
  # Round-trip: create the transcript dir under the same slug the lib derives.
  local slug tdir
  slug="$(isl_project_slug_candidates "$repo" | head -n 1)"
  tdir="$ISL_PROJECTS_ROOT/$slug"
  mkdir -p "$tdir"

  _isl_age() { # $1=file $2=minutes-ago
    local secs=$(( $2 * 60 ))
    touch -d "@$(( $(date +%s) - secs ))" "$1" 2>/dev/null \
      || touch -t "$(date -d "@$(( $(date +%s) - secs ))" +%Y%m%d%H%M.%S 2>/dev/null)" "$1" 2>/dev/null || true
  }

  # T1 fresh transcript -> locked
  : > "$tdir/session-aaaa.jsonl"
  if isl_live_session "$repo"; then
    echo "T1 fresh-transcript-locked: PASS"; pass=$((pass+1))
  else
    echo "T1 fresh-transcript-locked: FAIL"; fail=$((fail+1))
  fi

  # T2 stale transcript only -> unlocked
  _isl_age "$tdir/session-aaaa.jsonl" 30
  if ! isl_live_session "$repo"; then
    echo "T2 stale-transcript-unlocked: PASS"; pass=$((pass+1))
  else
    echo "T2 stale-transcript-unlocked: FAIL"; fail=$((fail+1))
  fi

  # T3 fresh explicit lock file -> locked (even with only a stale transcript)
  mkdir -p "$repo/.claude/state"
  : > "$repo/.claude/state/interactive-session.lock"
  if isl_live_session "$repo"; then
    echo "T3 explicit-lock-locked: PASS"; pass=$((pass+1))
  else
    echo "T3 explicit-lock-locked: FAIL"; fail=$((fail+1))
  fi

  # T4 stale lock file + stale transcript -> unlocked
  _isl_age "$repo/.claude/state/interactive-session.lock" 30
  if ! isl_live_session "$repo"; then
    echo "T4 stale-lock-unlocked: PASS"; pass=$((pass+1))
  else
    echo "T4 stale-lock-unlocked: FAIL"; fail=$((fail+1))
  fi

  # T5 refusal line lands in the sandboxed log
  isl_refuse_log "$repo" "selftest-daemon"
  if [ -f "$ISL_LOG_FILE" ] \
     && grep -q 'daemon=selftest-daemon' "$ISL_LOG_FILE" \
     && grep -q '^[^ ]* refused ' "$ISL_LOG_FILE"; then
    echo "T5 refusal-logged-sandboxed: PASS"; pass=$((pass+1))
  else
    echo "T5 refusal-logged-sandboxed: FAIL"; fail=$((fail+1))
  fi

  # T6 slug formula: Windows-native path translates deterministically
  local got expect
  got="$(isl_project_slug_candidates 'C:\Users\example user\dev.repo' | head -n 1)"
  expect='C--Users-example-user-dev-repo'
  if [ "$got" = "$expect" ]; then
    echo "T6 slug-formula: PASS"; pass=$((pass+1))
  else
    echo "T6 slug-formula: FAIL (got '$got', want '$expect')"; fail=$((fail+1))
  fi

  rm -rf "$tmp"
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# Run the self-test ONLY when executed directly (never when sourced).
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  _isl_self_test
  exit $?
fi
