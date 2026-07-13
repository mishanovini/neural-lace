#!/usr/bin/env bash
# master-drift-autocorrect.sh — FF-only auto-correction of remote-vs-remote
# master drift (docs/plans/master-drift-autocorrection-2026-07.md).
#
# WHY THIS EXISTS
# ===============
# The repo has two masters — origin/master (personal remote) and the mirror
# remote's master (work-org remote). Local pushes dual-push both, but GitHub
# SERVER-SIDE PR merges land on exactly one of them, so the two masters drift
# apart until someone notices (they push-race-diverged six times on
# 2026-07-12 alone). Detection already exists in
# hooks/session-start-git-freshness.sh; this script is the AUTO-CORRECTION of
# the benign case: when one master is STRICTLY BEHIND the other
# (`git merge-base --is-ancestor` proves fast-forwardability), the behind
# master is pushed forward with a plain (never forced) push. True divergence
# (neither SHA an ancestor of the other) is categorically refused and
# surfaced via the status file — a reviewed merge per
# docs/runbooks/master-drift-autocorrect.md is the only path out.
#
# DEDICATED-CLONE ARCHITECTURE (F.6 / specs-e §SYNC-CLONE-C — same as
# sync-pt-to-personal.sh): every mutating git operation (fetch, push) runs
# inside a DEDICATED clone at $SYNC_CLONE_DIR (default
# ~/.claude/sync-clone/<repo-basename>), never in the caller's checkout. The
# caller's cwd is used ONLY for read-only remote discovery
# (`git remote get-url`). The B.12 interactive-session-lock guard runs first
# with the F.6 verdict branching: a live session on a normal (non-clone)
# caller checkout is LOG-AND-PROCEED (this run never touches that tree);
# only the degenerate shape where the caller checkout IS the dedicated clone
# itself REFUSES (logged, exit 0 — see EXIT CODE CONTRACT).
#
# USAGE
#   master-drift-autocorrect.sh              # act on the repo containing cwd
#   master-drift-autocorrect.sh --self-test  # sandboxed fixture suite
#
# Dispatched BACKGROUNDED by hooks/session-start-git-freshness.sh on remote
# master SHA inequality (or a non-quiet status file); also directly invocable
# by hand for on-demand runs — same behavior, no arguments.
#
# EXIT CODE CONTRACT: exit 0 in EVERY path (a SessionStart hook chain must
# never be poisoned). Failures degrade to "no mutation + a log line"; the
# status file carries the machine-readable verdict of the last COMPLETED
# evaluation.
#
# STATUS FILE (~/.claude/state/master-drift/<repo-basename>.status): exactly
# one line, overwritten atomically (write temp + mv), one of:
#   CONVERGED <sha7>
#   CORRECTED <remote> <sha7>
#   DIVERGED <sha7-origin> <sha7-mirror>
#   PUSH-REJECTED <remote> <reason-word>
# Consumers (the git-freshness hook's digest rendering) must tolerate an
# absent file (= quiet). Early exits (kill switch, lock held, single remote,
# fetch/bootstrap failure, ISL refuse) write NOTHING — a stale CONVERGED is
# acceptable; every session start is the natural retry tick.
#
# ENV
#   MASTER_DRIFT_AUTOCORRECT   =0 → kill switch: exit 0 immediately, no
#                              mutation (present-moment check, honored here
#                              AND by the dispatching hook).
#   SYNC_CLONE_DIR             override the dedicated-clone path (default
#                              ~/.claude/sync-clone/<repo-basename>).
#   MASTER_DRIFT_STATE_DIR     override the status-file directory (default
#                              ~/.claude/state/master-drift; sandboxed into
#                              $TMPDIR under HARNESS_SELFTEST=1).
#   MASTER_DRIFT_LOG_FILE      override the phase log (default
#                              ~/.claude/logs/master-drift-autocorrect.log;
#                              sandboxed under HARNESS_SELFTEST=1).
#   FETCH_TIMEOUT_SECONDS      per-fetch/push timeout (default 10 — the
#                              git-freshness hook's discipline).
#   MASTER_DRIFT_CLONE_TIMEOUT bootstrap `git clone` timeout (default 300).
#   MASTER_DRIFT_LOCK_STALE_MIN break a held lock older than this (default 30).
#   ISL_LIB_PATH               override the interactive-session-lock lib path.
#   ISL_BYPASS=1               on the LOG-AND-PROCEED path (caller is a distinct
#                              interactive checkout) forces the "bypassed" log
#                              word. The degenerate caller==dedicated-clone
#                              refusal is UNBYPASSABLE by design — ISL_BYPASS
#                              does NOT override it (that shape is never safe).
#   MASTER_DRIFT_PUSH_TIMEOUT  seconds bounding the corrective push (default 60;
#                              the push traverses the global pre-push hook chain
#                              (scanner + divergence check), so it needs more
#                              headroom than the fetch bound).
#
# GUARANTEES
#   - FF-only: a push happens ONLY after `git merge-base --is-ancestor`
#     proves the target is strictly behind; the server rejecting non-FF is
#     the independent backstop against check-to-push races.
#   - Never force-pushes (no force flag anywhere; self-test T5 greps for it).
#   - No tokens: authenticates via the ambient credential store, never
#     prompts (GIT_TERMINAL_PROMPT=0), never acquires credentials.
#   - Never mutates the invoking repo's working tree, HEAD, or refs.
#   - Never auto-merges divergence: neither-ancestor → DIVERGED, touch
#     nothing.
#   - Only the `master` ref of the two discovered remotes is ever pushed.
#
# OBSERVABILITY: one line per phase (dispatch, isl, lock, bootstrap, fetch,
# ancestor, push, state) appended to the log; the status file is the
# machine-readable summary of the last completed run.

set -u

export GIT_TERMINAL_PROMPT=0

CANONICAL_REMOTE="origin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
SCRIPT_ABS_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# ============================================================
# Path / state resolution helpers
# ============================================================

_resolve_state_dir() {
  if [ -n "${MASTER_DRIFT_STATE_DIR:-}" ]; then
    printf '%s' "$MASTER_DRIFT_STATE_DIR"
  elif [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    # Sandbox: a self-test must never touch the real state dir.
    printf '%s' "${TMPDIR:-/tmp}/master-drift-state.selftest"
  else
    printf '%s' "${HOME}/.claude/state/master-drift"
  fi
}

_resolve_log_file() {
  if [ -n "${MASTER_DRIFT_LOG_FILE:-}" ]; then
    printf '%s' "$MASTER_DRIFT_LOG_FILE"
  elif [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    printf '%s' "${TMPDIR:-/tmp}/master-drift-autocorrect.selftest.log"
  else
    printf '%s' "${HOME}/.claude/logs/master-drift-autocorrect.log"
  fi
}

MD_LOG_FILE="$(_resolve_log_file)"
REPO_BASENAME="unknown"

_log() { printf '[master-drift] %s\n' "$*" >&2; }

# One line per phase: timestamp, repo, phase, detail — the reconstruct-
# everything trail (plan SEA §6).
_phase() {
  local phase="$1" detail="${2:-}"
  mkdir -p "$(dirname "$MD_LOG_FILE")" 2>/dev/null || true
  printf '%s repo=%s phase=%s %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" \
    "$REPO_BASENAME" "$phase" "$detail" >> "$MD_LOG_FILE" 2>/dev/null || true
  _log "$phase: $detail"
}

# Atomic single-line status write (temp + mv; overwritten whole, never
# appended — interface contract §3 of the plan).
_write_status() {
  local content="$1" state_dir status_tmp
  state_dir="$(_resolve_state_dir)"
  mkdir -p "$state_dir" 2>/dev/null || true
  status_tmp="${state_dir}/.${REPO_BASENAME}.status.tmp.$$"
  if printf '%s\n' "$content" > "$status_tmp" 2>/dev/null \
     && mv -f "$status_tmp" "${state_dir}/${REPO_BASENAME}.status" 2>/dev/null; then
    _phase "state" "wrote: $content"
  else
    rm -f "$status_tmp" 2>/dev/null || true
    _phase "state" "WARN status write failed (disk?): $content"
  fi
}

# Best-effort bounded run of a network git command.
_bounded() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

# ============================================================
# F.6 helpers (same shapes as sync-pt-to-personal.sh — reused pattern)
# ============================================================

# Discover the mirror remote FROM A GIVEN REPO DIR: any remote with a FETCH
# URL distinct from the canonical remote's FETCH url. Echoes "name<TAB>url"
# of the first match, or empty. Read-only — never mutates.
#
# FETCH urls (not push urls, deliberately diverging from sync-pt-to-
# personal.sh's pattern): this repo's real checkouts configure origin as a
# DUAL-PUSH remote (remote.origin.pushurl listed twice: work-org URL +
# personal URL) whose FIRST push url equals the mirror remote's — push-URL
# comparison therefore sees "same URL" and discovers no mirror at all,
# silently no-opping the whole mechanism. What this corrector actually
# compares and corrects are the two remotes' FETCH identities
# (origin/master vs <mirror>/master remote-tracking refs), so fetch URLs
# are the honest discovery key. The dedicated clone is then wired with one
# single-URL remote per repo (no pushurl inheritance — see
# _ensure_sync_clone), so a push inside the clone targets exactly one repo.
_discover_mirror_remote() {
  local repo_dir="$1"
  local canonical_url name mirror_url
  canonical_url="$(git -C "$repo_dir" remote get-url "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && return 0
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    [ "$name" = "$CANONICAL_REMOTE" ] && continue
    mirror_url="$(git -C "$repo_dir" remote get-url "$name" 2>/dev/null || echo "")"
    if [ -n "$mirror_url" ] && [ "$mirror_url" != "$canonical_url" ]; then
      printf '%s\t%s\n' "$name" "$mirror_url"
      return 0
    fi
  done < <(git -C "$repo_dir" remote 2>/dev/null)
}

# Normalize a path for cross-spelling comparison (Windows-native vs MSYS
# spellings of the same dir — F.6 _normalize_path approach).
_normalize_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p" 2>/dev/null && return 0
  fi
  readlink -f "$p" 2>/dev/null && return 0
  printf '%s' "$p"
}

# Resolve the dedicated sync-clone directory: SYNC_CLONE_DIR env override,
# else ~/.claude/sync-clone/<basename of the given repo dir>.
_resolve_sync_clone_dir() {
  local repo_dir="$1"
  if [ -n "${SYNC_CLONE_DIR:-}" ]; then
    printf '%s' "$SYNC_CLONE_DIR"
    return 0
  fi
  local base
  base="$(basename "$repo_dir" 2>/dev/null || echo "repo")"
  printf '%s/.claude/sync-clone/%s' "${HOME}" "$base"
}

# Ensure a dedicated clone exists at $1 wired with canonical url $2 and
# mirror name $3 / url $4. Bootstraps via `git clone` from canonical when
# absent; repairs remotes when present. Returns 0 on a usable clone.
_ensure_sync_clone() {
  local clone_dir="$1" canonical_url="$2" mirror_name="$3" mirror_url="$4"

  if [ ! -d "$clone_dir/.git" ]; then
    [ -z "$canonical_url" ] && return 1
    _phase "bootstrap" "dedicated sync clone missing — cloning $canonical_url -> $clone_dir"
    mkdir -p "$(dirname "$clone_dir")" 2>/dev/null || true
    local clone_out clone_rc
    clone_out="$(_bounded "${MASTER_DRIFT_CLONE_TIMEOUT:-300}" git clone --quiet "$canonical_url" "$clone_dir" 2>&1)"
    clone_rc=$?
    if [ "$clone_rc" -ne 0 ]; then
      _phase "bootstrap" "bootstrap-failed rc=$clone_rc: $(printf '%s' "$clone_out" | head -1)"
      return 1
    fi
    git -C "$clone_dir" remote rename origin "$CANONICAL_REMOTE" >/dev/null 2>&1 || true
  fi

  if git -C "$clone_dir" remote get-url "$CANONICAL_REMOTE" >/dev/null 2>&1; then
    git -C "$clone_dir" remote set-url "$CANONICAL_REMOTE" "$canonical_url" >/dev/null 2>&1 || true
  else
    git -C "$clone_dir" remote add "$CANONICAL_REMOTE" "$canonical_url" >/dev/null 2>&1 || true
  fi

  if git -C "$clone_dir" remote get-url "$mirror_name" >/dev/null 2>&1; then
    git -C "$clone_dir" remote set-url "$mirror_name" "$mirror_url" >/dev/null 2>&1 || true
  else
    git -C "$clone_dir" remote add "$mirror_name" "$mirror_url" >/dev/null 2>&1 || true
  fi

  # Single-push invariant: each clone remote targets exactly ONE repo — a
  # push inside the clone must never dual-push (the caller's checkout may
  # configure multi-pushurl remotes; the clone must not inherit or keep any).
  git -C "$clone_dir" config --unset-all "remote.${CANONICAL_REMOTE}.pushurl" 2>/dev/null || true
  git -C "$clone_dir" config --unset-all "remote.${mirror_name}.pushurl" 2>/dev/null || true

  [ -d "$clone_dir/.git" ]
}

# Classify a failed push's output into the status file's one-word reason.
_push_reject_reason() {
  local rc="$1" out="$2"
  if [ "$rc" -eq 124 ]; then
    printf 'timeout'
  elif printf '%s' "$out" | grep -qiE '403|authentication|authoriz|denied|permission|could not read Username'; then
    printf 'auth'
  elif printf '%s' "$out" | grep -qiE 'non-fast-forward|fetch first|stale info|advanced since your last fetch|DIVERGENCE CHECK'; then
    printf 'non-ff'
  else
    printf 'rejected'
  fi
}

# ============================================================
# Main flow
# ============================================================

_main_correct() {
  local caller_repo_dir git_toplevel clone_dir
  local mirror_line mirror_name mirror_url canonical_url
  local origin_sha mirror_sha

  # 0. Resolve the CALLER's repo dir (read-only throughout).
  caller_repo_dir="$(pwd)"
  git_toplevel="$(git -C "$caller_repo_dir" rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [ -z "$git_toplevel" ]; then
    _phase "abort" "not-a-git-repo cwd=$caller_repo_dir"
    return 0
  fi
  caller_repo_dir="$git_toplevel"

  # 0a. Repo IDENTITY must be the MAIN checkout, never an ephemeral linked
  #     worktree (else clone/status/lock key on the worktree basename, orphan
  #     clones pile up, and DIVERGED status surfaces to no future session).
  #     In a linked worktree `--git-common-dir` points at the MAIN repo's .git;
  #     its parent is the main root. If the caller is a linked worktree, skip —
  #     the main checkout's own session-start covers correction.
  local common_dir main_root
  common_dir="$(git -C "$caller_repo_dir" rev-parse --git-common-dir 2>/dev/null || echo "")"
  case "$common_dir" in
    /*|[A-Za-z]:[\\/]*) : ;;                              # already absolute
    "" ) common_dir="$caller_repo_dir/.git" ;;           # fallback
    * ) common_dir="$caller_repo_dir/$common_dir" ;;      # relative to toplevel
  esac
  main_root="$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd || echo "$caller_repo_dir")"
  if [ "$(_normalize_path "$main_root")" != "$(_normalize_path "$caller_repo_dir")" ]; then
    REPO_BASENAME="$(basename "$main_root")"
    _phase "abort" "linked-worktree (main checkout is $main_root) — main session covers drift; skipping"
    return 0
  fi
  REPO_BASENAME="$(basename "$caller_repo_dir")"
  _phase "dispatch" "run starting (cwd repo: $caller_repo_dir)"

  # 1. Kill switch — present-moment env check (loud-is-not-rare lesson).
  if [ "${MASTER_DRIFT_AUTOCORRECT:-1}" = "0" ]; then
    _phase "abort" "kill-switch MASTER_DRIFT_AUTOCORRECT=0 — no mutation"
    return 0
  fi

  # 2. Resolve the dedicated clone path ahead of the ISL guard (the guard
  #    branches on caller-vs-clone identity).
  clone_dir="$(_resolve_sync_clone_dir "$caller_repo_dir")"

  # 3. Interactive-session-lock guard (B.12, F.6 verdict branching). This is
  #    an UNATTENDED mutator: with the guard lib missing we refuse to run
  #    unguarded (plan SEA §7: lib missing → exit 0, log isl-lib-missing).
  local isl_lib
  isl_lib="${ISL_LIB_PATH:-$SCRIPT_DIR/../hooks/lib/interactive-session-lock.sh}"
  if [ ! -f "$isl_lib" ]; then
    _phase "isl" "isl-lib-missing at $isl_lib — refusing to run unguarded (reinstall: bash adapters/claude-code/install.sh)"
    return 0
  fi
  # shellcheck source=/dev/null
  . "$isl_lib"
  if isl_live_session "$caller_repo_dir"; then
    local caller_real clone_real
    caller_real="$(_normalize_path "$caller_repo_dir")"
    clone_real="$(_normalize_path "$clone_dir")"
    if [ "$caller_real" = "$clone_real" ]; then
      # Degenerate shape: the caller checkout IS the dedicated clone — the
      # one shape where a live session shares the tree this script mutates.
      # REFUSE (logged); exit 0 per the hook-chain contract.
      isl_refuse_log "$caller_repo_dir" "master-drift-autocorrect"
      _phase "isl" "REFUSED: live session on $caller_repo_dir which IS the dedicated sync clone ($clone_dir)"
      return 0
    elif [ "${ISL_BYPASS:-0}" = "1" ]; then
      isl_refuse_log "$caller_repo_dir" "master-drift-autocorrect" "bypassed"
      _phase "isl" "live session on caller — ISL_BYPASS=1; proceeding (logged)"
    else
      # Normal shape: caller is a distinct interactive checkout. The
      # dedicated-clone architecture means this run never touches it —
      # LOG-AND-PROCEED (F.6).
      isl_refuse_log "$caller_repo_dir" "master-drift-autocorrect" "log-and-proceed"
      _phase "isl" "live session on caller — log-and-proceed (dedicated clone only mutates $clone_dir)"
    fi
  fi

  # 4. Discover both remotes from the caller (read-only).
  mirror_line="$(_discover_mirror_remote "$caller_repo_dir")"
  if [ -z "$mirror_line" ]; then
    _phase "abort" "single-remote (no mirror remote with a distinct URL) — nothing to correct"
    return 0
  fi
  mirror_name="${mirror_line%%$'\t'*}"
  mirror_url="${mirror_line#*$'\t'}"
  # FETCH url (see _discover_mirror_remote header note: push urls lie on
  # dual-push checkouts; the clone gets one single-URL remote per repo).
  canonical_url="$(git -C "$caller_repo_dir" remote get-url "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
  if [ -z "$canonical_url" ]; then
    _phase "abort" "no-canonical-url (remote '$CANONICAL_REMOTE' unresolved)"
    return 0
  fi

  # 5. Single-instance lock (mkdir-based) — acquired in the STATE dir BEFORE
  #    bootstrap so two concurrent first-runs cannot race `git clone` (a mutex
  #    must not live inside the resource whose creation it serializes). Loser
  #    exits 0 silently; a stale (> MASTER_DRIFT_LOCK_STALE_MIN min) lock from a
  #    crashed run is broken by age.
  local md_state_dir lock_dir
  md_state_dir="$(_resolve_state_dir)"
  mkdir -p "$md_state_dir" 2>/dev/null || true
  lock_dir="${md_state_dir}/${REPO_BASENAME}.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    local stale_min="${MASTER_DRIFT_LOCK_STALE_MIN:-30}"
    if [ -d "$lock_dir" ] && [ -n "$(find "$lock_dir" -maxdepth 0 -mmin "+$stale_min" 2>/dev/null)" ]; then
      _phase "lock" "breaking stale lock (age > ${stale_min}min): $lock_dir"
      rm -rf "$lock_dir" 2>/dev/null || true
      if ! mkdir "$lock_dir" 2>/dev/null; then
        _phase "lock" "lock-held (re-acquire after stale-break lost) — exiting silently"
        return 0
      fi
    else
      _phase "lock" "lock-held ($lock_dir) — another instance is running; exiting silently"
      return 0
    fi
  fi
  _MD_LOCK_DIR="$lock_dir"
  trap '[ -n "${_MD_LOCK_DIR:-}" ] && rmdir "$_MD_LOCK_DIR" 2>/dev/null || true' EXIT
  _phase "lock" "acquired $lock_dir"

  # 6. Bootstrap/repair the dedicated clone (now serialized under the lock).
  #    All mutation below runs with `git -C "$clone_dir"` — the caller's tree
  #    is never touched again.
  if ! _ensure_sync_clone "$clone_dir" "$canonical_url" "$mirror_name" "$mirror_url"; then
    _phase "abort" "bootstrap-failed for $clone_dir — next session start retries"
    return 0
  fi

  # 7. Fetch both remotes IN THE CLONE (timeout-bounded). On failure: exit 0
  #    without writing a scary status — stale CONVERGED is acceptable;
  #    detection re-runs next session.
  local fetch_secs="${FETCH_TIMEOUT_SECONDS:-10}"
  if ! _bounded "$fetch_secs" git -C "$clone_dir" fetch --quiet "$CANONICAL_REMOTE" 2>/dev/null; then
    _phase "fetch" "fetch-failed remote=$CANONICAL_REMOTE — status untouched"
    return 0
  fi
  if ! _bounded "$fetch_secs" git -C "$clone_dir" fetch --quiet "$mirror_name" 2>/dev/null; then
    _phase "fetch" "fetch-failed remote=$mirror_name — status untouched"
    return 0
  fi
  _phase "fetch" "fetched $CANONICAL_REMOTE + $mirror_name in clone"

  # 8. Resolve both remote master SHAs.
  origin_sha="$(git -C "$clone_dir" rev-parse --verify --quiet "${CANONICAL_REMOTE}/master" 2>/dev/null || echo "")"
  mirror_sha="$(git -C "$clone_dir" rev-parse --verify --quiet "${mirror_name}/master" 2>/dev/null || echo "")"
  if [ -z "$origin_sha" ] || [ -z "$mirror_sha" ]; then
    _phase "abort" "missing-master-ref (origin=${origin_sha:-none} ${mirror_name}=${mirror_sha:-none})"
    return 0
  fi

  # 9. FF-only compare/act (plan D2: merge-base --is-ancestor is the explicit
  #    gate; the server's non-FF rejection on a plain push is the backstop).
  if [ "$origin_sha" = "$mirror_sha" ]; then
    _phase "ancestor" "converged at $origin_sha"
    _write_status "CONVERGED $(printf '%.7s' "$origin_sha")"
    return 0
  fi

  local push_target="" push_sha=""
  if git -C "$clone_dir" merge-base --is-ancestor "$mirror_sha" "$origin_sha" 2>/dev/null; then
    # Mirror strictly behind origin → fast-forward the mirror.
    push_target="$mirror_name"; push_sha="$origin_sha"
    _phase "ancestor" "$mirror_name/master ($mirror_sha) strictly behind ${CANONICAL_REMOTE}/master ($origin_sha) — FF push eligible"
  elif git -C "$clone_dir" merge-base --is-ancestor "$origin_sha" "$mirror_sha" 2>/dev/null; then
    # Origin strictly behind mirror → symmetric.
    push_target="$CANONICAL_REMOTE"; push_sha="$mirror_sha"
    _phase "ancestor" "${CANONICAL_REMOTE}/master ($origin_sha) strictly behind $mirror_name/master ($mirror_sha) — FF push eligible"
  else
    # TRUE DIVERGENCE: touch nothing. Auto-merge is categorically refused;
    # surfacing is the next session start's digest line.
    _phase "ancestor" "DIVERGED (neither ancestor) origin=$origin_sha $mirror_name=$mirror_sha — auto-sync refused"
    _write_status "DIVERGED $(printf '%.7s' "$origin_sha") $(printf '%.7s' "$mirror_sha")"
    return 0
  fi

  # 10. Plain push (never forced; only master; by SHA so the clone's local
  #     branches are irrelevant).
  local push_out push_rc
  push_out="$(_bounded "${MASTER_DRIFT_PUSH_TIMEOUT:-60}" git -C "$clone_dir" push "$push_target" "${push_sha}:master" 2>&1)"
  push_rc=$?
  if [ "$push_rc" -ne 0 ]; then
    local reason
    reason="$(_push_reject_reason "$push_rc" "$push_out")"
    _phase "push" "push-rejected remote=$push_target rc=$push_rc reason=$reason: $(printf '%s' "$push_out" | tail -1)"
    _write_status "PUSH-REJECTED $push_target $reason"
    return 0
  fi
  _phase "push" "pushed ${push_sha}:master to $push_target (plain, fast-forward)"

  # 11. Post-push verification: re-fetch the target, confirm EQUAL SHAs.
  _bounded "$fetch_secs" git -C "$clone_dir" fetch --quiet "$push_target" 2>/dev/null || true
  local post_sha
  post_sha="$(git -C "$clone_dir" rev-parse --verify --quiet "${push_target}/master" 2>/dev/null || echo "")"
  if [ "$post_sha" = "$push_sha" ]; then
    _phase "verify" "post-push EQUAL: ${push_target}/master = $push_sha"
    _write_status "CORRECTED $push_target $(printf '%.7s' "$push_sha")"
  else
    _phase "verify" "post-push mismatch: ${push_target}/master = ${post_sha:-none}, expected $push_sha"
    _write_status "PUSH-REJECTED $push_target verify-mismatch"
  fi
  return 0
}

# ============================================================
# Self-test — sandboxed fixture suite (HARNESS_SELFTEST convention).
# Scenario matrix per the plan's Testing Strategy (T1-T10).
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  echo "[self-test] tmpdir=$tmp"

  # Sandbox EVERY write: state dir, log, ISL log/projects-root, sync clone,
  # and the global gitconfig (so machine-global hooksPath/user identity never
  # leak into fixtures — findings 025/028/030/034 discipline).
  export HARNESS_SELFTEST=1
  export TMPDIR="$tmp"
  export MASTER_DRIFT_STATE_DIR="$tmp/state"
  export MASTER_DRIFT_LOG_FILE="$tmp/master-drift.log"
  export ISL_LOG_FILE="$tmp/isl-refusal.log"
  export ISL_PROJECTS_ROOT="$tmp/isl-projects"
  export SYNC_CLONE_DIR="$tmp/sync-clone-under-test"
  export GIT_CONFIG_GLOBAL="$tmp/selftest-gitconfig"
  export GIT_AUTHOR_NAME="NL Selftest" GIT_AUTHOR_EMAIL="nl-selftest@example.test"
  export GIT_COMMITTER_NAME="NL Selftest" GIT_COMMITTER_EMAIL="nl-selftest@example.test"
  unset MASTER_DRIFT_AUTOCORRECT ISL_BYPASS 2>/dev/null || true
  mkdir -p "$ISL_PROJECTS_ROOT" "$tmp/state"
  : > "$GIT_CONFIG_GLOBAL"

  # Fixture triple: two bare "remotes" (origin, mirror — alice-at-acme /
  # acme-org placeholder era: no real identifiers) + one work clone playing
  # the interactive checkout.
  local ORIGIN_BARE="$tmp/bare-origin" MIRROR_BARE="$tmp/bare-mirror" WORK="$tmp/work"
  git init --bare --quiet "$ORIGIN_BARE"
  git init --bare --quiet "$MIRROR_BARE"
  git init --quiet "$WORK"
  git -C "$WORK" config core.hooksPath ""
  git -C "$WORK" remote add origin "$ORIGIN_BARE"
  git -C "$WORK" remote add acme-mirror "$MIRROR_BARE"
  ( cd "$WORK" && echo base > base.txt && git add base.txt && git commit --quiet -m "base" \
      && git push --quiet origin HEAD:master && git push --quiet acme-mirror HEAD:master )

  local STATUS_FILE="$tmp/state/work.status"

  # Helper: run the real script (flagless invocation shape) from a given cwd.
  _run() { ( cd "$1" && bash "$SCRIPT_ABS_PATH" ) >"$tmp/run.out" 2>&1; }

  # Helper: advance ONE bare remote by one commit (fresh throwaway clone —
  # no force pushes anywhere in this file, fixture setup included).
  _advance() { # $1 = bare path
    local adv="$tmp/advancer.$RANDOM"
    git clone --quiet "$1" "$adv" 2>/dev/null
    git -C "$adv" config core.hooksPath ""
    ( cd "$adv" && echo "adv $RANDOM $(date +%s%N 2>/dev/null || date +%s)" > "adv-$RANDOM.txt" \
        && git add . && git commit --quiet -m "advance" && git push --quiet origin HEAD:master )
    rm -rf "$adv"
  }

  _sha() { git -C "$1" rev-parse master 2>/dev/null; }

  # T1: converged → CONVERGED status, no push, bares unchanged.
  (
    rm -f "$STATUS_FILE"; rm -rf "$SYNC_CLONE_DIR"
    local o_before m_before
    o_before="$(_sha "$ORIGIN_BARE")"; m_before="$(_sha "$MIRROR_BARE")"
    _run "$WORK"; rc=$?
    if [ "$rc" -eq 0 ] \
       && grep -q "^CONVERGED $(printf '%.7s' "$o_before")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$ORIGIN_BARE")" = "$o_before" ] && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ]; then
      echo "  T1 converged -> CONVERGED, no push: PASS"
    else
      echo "  T1 converged -> CONVERGED, no push: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T2: mirror strictly behind → pushed, SHAs equal after, CORRECTED; caller
  # checkout untouched (HEAD identical before/after).
  (
    rm -f "$STATUS_FILE"
    _advance "$ORIGIN_BARE"
    local o_sha work_head_before
    o_sha="$(_sha "$ORIGIN_BARE")"
    work_head_before="$(git -C "$WORK" rev-parse HEAD)"
    _run "$WORK"; rc=$?
    if [ "$rc" -eq 0 ] \
       && grep -q "^CORRECTED acme-mirror $(printf '%.7s' "$o_sha")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$MIRROR_BARE")" = "$o_sha" ] \
       && [ "$(git -C "$WORK" rev-parse HEAD)" = "$work_head_before" ]; then
      echo "  T2 mirror-behind -> FF push + CORRECTED (caller untouched): PASS"
    else
      echo "  T2 mirror-behind -> FF push + CORRECTED: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null) mirror=$(_sha "$MIRROR_BARE") want=$o_sha)"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T3: origin strictly behind → symmetric push to origin, CORRECTED origin.
  (
    rm -f "$STATUS_FILE"
    _advance "$MIRROR_BARE"
    local m_sha
    m_sha="$(_sha "$MIRROR_BARE")"
    _run "$WORK"; rc=$?
    if [ "$rc" -eq 0 ] \
       && grep -q "^CORRECTED origin $(printf '%.7s' "$m_sha")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$ORIGIN_BARE")" = "$m_sha" ]; then
      echo "  T3 origin-behind -> symmetric FF push + CORRECTED: PASS"
    else
      echo "  T3 origin-behind -> symmetric FF push + CORRECTED: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T4: TRUE divergence → DIVERGED, both bares unchanged (rev-parse before
  # == after), no partial help.
  (
    rm -f "$STATUS_FILE"
    _advance "$ORIGIN_BARE"
    _advance "$MIRROR_BARE"
    local o_before m_before
    o_before="$(_sha "$ORIGIN_BARE")"; m_before="$(_sha "$MIRROR_BARE")"
    _run "$WORK"; rc=$?
    if [ "$rc" -eq 0 ] \
       && grep -q "^DIVERGED $(printf '%.7s' "$o_before") $(printf '%.7s' "$m_before")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$ORIGIN_BARE")" = "$o_before" ] && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ]; then
      echo "  T4 diverged -> DIVERGED, both remotes untouched: PASS"
    else
      echo "  T4 diverged -> DIVERGED, both remotes untouched: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Reconverge the fixture for the remaining scenarios: resolve T4's
  # divergence the reviewed way (merge in a throwaway clone, dual push) —
  # NO force pushes, matching the tool's own no-force guarantee.
  (
    local fix="$tmp/reconverge"
    git clone --quiet "$ORIGIN_BARE" "$fix" 2>/dev/null
    git -C "$fix" config core.hooksPath ""
    git -C "$fix" remote add acme-mirror "$MIRROR_BARE"
    git -C "$fix" fetch --quiet acme-mirror
    ( cd "$fix" && git merge --quiet --no-ff -m "reconverge fixture" acme-mirror/master >/dev/null 2>&1 \
        && git push --quiet origin HEAD:master && git push --quiet acme-mirror HEAD:master )
    rm -rf "$fix"
  ) || { echo "  (fixture reconverge FAILED)"; fail=$((fail+1)); }

  # T5: push rejected (target's pre-receive hook declines) → PUSH-REJECTED,
  # no force fallback; PLUS the static no-force guarantee: the script
  # contains no forced push (grep, same guarantee style as
  # sync-pt-to-personal.sh — pattern split so this line can't match itself).
  (
    rm -f "$STATUS_FILE"
    _advance "$ORIGIN_BARE"   # mirror now strictly behind → push eligible
    mkdir -p "$MIRROR_BARE/hooks"
    printf '#!/bin/sh\necho "fixture: declining push" >&2\nexit 1\n' > "$MIRROR_BARE/hooks/pre-receive"
    chmod +x "$MIRROR_BARE/hooks/pre-receive"
    local m_before; m_before="$(_sha "$MIRROR_BARE")"
    _run "$WORK"; rc=$?
    rm -f "$MIRROR_BARE/hooks/pre-receive"
    local force_pat
    force_pat='git[^#]*pu''sh[^#]*(--for''ce|[[:space:]]-f([[:space:]]|$))'
    if [ "$rc" -eq 0 ] \
       && grep -q "^PUSH-REJECTED acme-mirror " "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ] \
       && ! grep -qE "$force_pat" "$SCRIPT_ABS_PATH"; then
      echo "  T5 push-rejected -> PUSH-REJECTED, no force fallback (+ no-force grep): PASS"
    else
      echo "  T5 push-rejected -> PUSH-REJECTED: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null) force-grep=$(grep -cE "$force_pat" "$SCRIPT_ABS_PATH" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T6: lock held → second instance exits 0 silently, no push, status
  # untouched. (Fixture still has mirror strictly behind from T5's advance.)
  (
    rm -f "$STATUS_FILE"
    # Lock now lives in the STATE dir keyed on the caller's basename (MINOR-5:
    # acquired before bootstrap so it cannot live inside the clone it guards).
    mkdir -p "$tmp/state/work.lock"
    local m_before; m_before="$(_sha "$MIRROR_BARE")"
    _run "$WORK"; rc=$?
    rmdir "$tmp/state/work.lock" 2>/dev/null || true
    if [ "$rc" -eq 0 ] && [ ! -f "$STATUS_FILE" ] \
       && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ] \
       && grep -q "lock-held" "$tmp/master-drift.log"; then
      echo "  T6 lock-held -> silent exit 0, no mutation: PASS"
    else
      echo "  T6 lock-held -> silent exit 0, no mutation: FAIL (rc=$rc status-exists=$([ -f "$STATUS_FILE" ] && echo yes || echo no))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T7: degenerate invocation from INSIDE the dedicated clone with a live
  # session on it → ISL REFUSE (logged), no mutation, exit 0.
  (
    rm -f "$STATUS_FILE" "$ISL_LOG_FILE"
    # Simulate a live session on the clone via a fresh transcript under its
    # ISL slug + the explicit lock file (same mechanism the real lock checks).
    local slug tdir
    slug="$(bash -c ". '$SCRIPT_DIR/../hooks/lib/interactive-session-lock.sh'; isl_project_slug_candidates '$SYNC_CLONE_DIR' | head -n 1")"
    tdir="$ISL_PROJECTS_ROOT/$slug"
    mkdir -p "$tdir" "$SYNC_CLONE_DIR/.claude/state"
    : > "$tdir/session-live.jsonl"
    : > "$SYNC_CLONE_DIR/.claude/state/interactive-session.lock"
    local m_before o_before
    o_before="$(_sha "$ORIGIN_BARE")"; m_before="$(_sha "$MIRROR_BARE")"
    _run "$SYNC_CLONE_DIR"; rc=$?
    rm -f "$SYNC_CLONE_DIR/.claude/state/interactive-session.lock" "$tdir/session-live.jsonl"
    if [ "$rc" -eq 0 ] && [ ! -f "$STATUS_FILE" ] \
       && grep -q '^[^ ]* refused .*daemon=master-drift-autocorrect' "$ISL_LOG_FILE" 2>/dev/null \
       && [ "$(_sha "$ORIGIN_BARE")" = "$o_before" ] && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ]; then
      echo "  T7 invocation-from-clone -> ISL REFUSE, no mutation: PASS"
    else
      echo "  T7 invocation-from-clone -> ISL REFUSE, no mutation: FAIL (rc=$rc)"
      sed 's/^/    /' "$tmp/run.out"; cat "$ISL_LOG_FILE" 2>/dev/null | sed 's/^/    isl: /'; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T8: kill switch honored → exit 0, no push, no status write (mirror is
  # still strictly behind — a mutation would be visible).
  (
    rm -f "$STATUS_FILE"
    local m_before; m_before="$(_sha "$MIRROR_BARE")"
    ( cd "$WORK" && MASTER_DRIFT_AUTOCORRECT=0 bash "$SCRIPT_ABS_PATH" ) >"$tmp/run.out" 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && [ ! -f "$STATUS_FILE" ] \
       && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ] \
       && grep -q "kill-switch" "$tmp/master-drift.log"; then
      echo "  T8 kill-switch -> no mutation, no status: PASS"
    else
      echo "  T8 kill-switch -> no mutation, no status: FAIL (rc=$rc)"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T9: single-remote repo → silent no-op (exit 0, no status write).
  (
    local single="$tmp/single"
    git init --quiet "$single"
    git -C "$single" config core.hooksPath ""
    git -C "$single" remote add origin "$ORIGIN_BARE"
    ( cd "$single" && git fetch --quiet origin 2>/dev/null || true )
    rm -f "$tmp/state/single.status"
    _run "$single"; rc=$?
    if [ "$rc" -eq 0 ] && [ ! -f "$tmp/state/single.status" ] \
       && grep -q "single-remote" "$tmp/master-drift.log"; then
      echo "  T9 single-remote -> silent no-op: PASS"
    else
      echo "  T9 single-remote -> silent no-op: FAIL (rc=$rc)"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T10: no clone yet → bootstrap from the caller's remote URLs, then
  # proceed to a full evaluation (mirror behind → CORRECTED).
  (
    rm -f "$STATUS_FILE"; rm -rf "$SYNC_CLONE_DIR"
    local o_sha; o_sha="$(_sha "$ORIGIN_BARE")"   # mirror still behind from T5's advance
    _run "$WORK"; rc=$?
    if [ "$rc" -eq 0 ] && [ -d "$SYNC_CLONE_DIR/.git" ] \
       && grep -q "^CORRECTED acme-mirror $(printf '%.7s' "$o_sha")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$MIRROR_BARE")" = "$o_sha" ]; then
      echo "  T10 fresh-machine bootstrap -> clone + CORRECTED: PASS"
    else
      echo "  T10 fresh-machine bootstrap -> clone + CORRECTED: FAIL (rc=$rc clone=$([ -d "$SYNC_CLONE_DIR/.git" ] && echo yes || echo no) status=$(cat "$STATUS_FILE" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T11: the REAL checkouts' remote topology — origin has TWO pushurls
  # (mirror URL first, own URL second: the dual-push shape) while its FETCH
  # url stays its own repo. Push-URL-based discovery sees origin's first
  # pushurl == the mirror's URL and finds NO mirror (silent no-op — the
  # regression this scenario pins); fetch-URL discovery must find the
  # mirror, and the correction must land on exactly ONE repo (the clone's
  # single-push invariant), leaving the caller's dual-push config untouched.
  (
    rm -f "$STATUS_FILE"; rm -rf "$SYNC_CLONE_DIR"
    git -C "$WORK" config --add remote.origin.pushurl "$MIRROR_BARE"
    git -C "$WORK" config --add remote.origin.pushurl "$ORIGIN_BARE"
    _advance "$ORIGIN_BARE"   # mirror strictly behind again
    local o_sha; o_sha="$(_sha "$ORIGIN_BARE")"
    _run "$WORK"; rc=$?
    git -C "$WORK" config --unset-all remote.origin.pushurl 2>/dev/null || true
    if [ "$rc" -eq 0 ] \
       && grep -q "^CORRECTED acme-mirror $(printf '%.7s' "$o_sha")$" "$STATUS_FILE" 2>/dev/null \
       && [ "$(_sha "$MIRROR_BARE")" = "$o_sha" ] \
       && [ -z "$(git -C "$SYNC_CLONE_DIR" config --get-all remote.origin.pushurl 2>/dev/null)" ] \
       && [ -z "$(git -C "$SYNC_CLONE_DIR" config --get-all remote.acme-mirror.pushurl 2>/dev/null)" ]; then
      echo "  T11 dual-pushurl topology -> mirror discovered via fetch URLs + single-push clone: PASS"
    else
      echo "  T11 dual-pushurl topology -> mirror discovered via fetch URLs: FAIL (rc=$rc status=$(cat "$STATUS_FILE" 2>/dev/null))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T12 (MAJOR-3): invoked from a LINKED WORKTREE of the caller repo → identity
  # resolves to the MAIN checkout via --git-common-dir, so the run SKIPS (the
  # main session covers correction) instead of keying clone/status/lock on the
  # ephemeral worktree basename. Assert: exit 0, "linked-worktree" logged, no
  # status file, no mutation — even with real drift present.
  (
    rm -f "$STATUS_FILE"; rm -rf "$SYNC_CLONE_DIR"
    _advance "$ORIGIN_BARE"   # real drift present, to prove the SKIP stops it
    local o_before m_before wt
    o_before="$(_sha "$ORIGIN_BARE")"; m_before="$(_sha "$MIRROR_BARE")"
    wt="$tmp/linked-wt"
    git -C "$WORK" worktree add -q "$wt" -b md-selftest-linked >/dev/null 2>&1
    _run "$wt"; rc=$?
    git -C "$WORK" worktree remove --force "$wt" 2>/dev/null || true
    git -C "$WORK" branch -D md-selftest-linked 2>/dev/null || true
    if [ "$rc" -eq 0 ] && [ ! -f "$STATUS_FILE" ] \
       && grep -q "linked-worktree" "$tmp/master-drift.log" \
       && [ "$(_sha "$ORIGIN_BARE")" = "$o_before" ] && [ "$(_sha "$MIRROR_BARE")" = "$m_before" ]; then
      echo "  T12 linked-worktree caller -> SKIP (main session covers), no mutation: PASS"
    else
      echo "  T12 linked-worktree caller -> SKIP: FAIL (rc=$rc status-exists=$([ -f "$STATUS_FILE" ] && echo yes || echo no))"
      sed 's/^/    /' "$tmp/run.out"; return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --self-test)
    _self_test
    exit $?
    ;;
  -h|--help)
    cat <<'USAGE' >&2
master-drift-autocorrect.sh — FF-only auto-correction of remote-master drift.

USAGE:
  master-drift-autocorrect.sh              # act on the repo containing cwd
  master-drift-autocorrect.sh --self-test

Compares origin/master against the mirror remote's master (both discovered
read-only from the invoking repo), inside a DEDICATED sync clone
($SYNC_CLONE_DIR, default ~/.claude/sync-clone/<repo-basename>). A master
strictly behind its sibling (git merge-base --is-ancestor) is fast-forwarded
with a plain push — never forced, no tokens, no working-tree mutation. True
divergence is NEVER auto-merged: it is recorded in the status file
(~/.claude/state/master-drift/<repo-basename>.status) and surfaced as one
digest line by hooks/session-start-git-freshness.sh; see
docs/runbooks/master-drift-autocorrect.md for the reviewed-merge procedure,
the MASTER_DRIFT_AUTOCORRECT=0 kill switch, and PUSH-REJECTED triage.
Exit code is 0 in every path (SessionStart hook-chain safe).
USAGE
    exit 0
    ;;
  "")
    _main_correct
    exit 0
    ;;
  *)
    echo "[master-drift] unknown argument: $1 (takes no arguments; see --help)" >&2
    exit 0
    ;;
esac
