#!/bin/bash
# estate-merge.sh — THE single deterministic merge path (accountable-estate T5).
#
# design docs/designs/accountable-estate-2026-07-27.md §6c:
#   "merge-to-master becomes a critical section — estate-wide mkdir-atomic
#    merge lock (the coord-sync single-writer idiom, proven in-repo) + ONE
#    deterministic merge script (acquire -> rebase/FF per git doctrine -> push
#    both remotes per 064 -> release). No two sessions can merge concurrently;
#    clean merges by construction. The closer (above) calls it; nothing else
#    merges."
#
# T5's own dispatch text narrows "rebase/FF" to what this script actually
# does: "merge (ff-only preferred, else --no-ff with recorded rationale)".
# HONEST SCOPE NARROWING (state this, don't hide it — same discipline
# close-worktree.sh's and admission-lib.sh's own headers use):
#   - NO automated rebase. Rebasing the SOURCE branch would rewrite commits
#     this script does not own the history of, and turns a deterministic,
#     no-agent-discretion script into a conflict-resolution engine — exactly
#     the "medium variance (git edge cases)" risk the plan's own LOE line
#     flags. When a fast-forward is not possible, this script creates an
#     explicit `--no-ff` merge commit whose message records WHY (how many
#     commits the target is ahead of the source's branch point) instead.
#     Constitution §9 ("never rewrite history") is honored a fortiori: this
#     script never rewrites ANY branch's history, source or target.
#   - "registration update (T4 lib)" is satisfied by the CALLER, not
#     duplicated here. close-worktree.sh already closes the T4 registration
#     (hooks/lib/estate-registration-lib.sh's reg_close, via
#     spawn-worktree.sh --remove --disposition) as its own next step after a
#     successful merge. Adding a second write path into that lib from here
#     would be a new, untested mutation API on a store this script does not
#     own. An optional --slug flag is accepted purely as a LOG-CORRELATION
#     label (see merges.log below) — it never touches the registration store.
#   - "push both remotes per 064" applies ONLY when `--into` names a
#     canonical branch (master/main) AND a second remote with a distinct
#     fetch URL is discovered (same discovery idiom as
#     master-drift-autocorrect.sh's _discover_mirror_remote, duplicated not
#     sourced — siblings, not a hierarchy). For any other `--into` (e.g. this
#     program's own current integration target,
#     wip/harness-hardening-2026-07-29, which has no remote counterpart at
#     all today) this is pure configuration, never hardcoded, and a target
#     with no remote branch degrades to a LOCAL-ONLY merge (named, logged,
#     non-fatal) rather than inventing a new remote branch.
#
# WHY A LOCK, NOT AN AGENT (design's own words): "a long-lived deployment
# agent would itself be an unmanaged actor (heartbeat/resume/authority
# problems)." This is a lock + a deterministic script, called synchronously
# by whatever closer needs a merge — same shape as coord-sync.sh's own
# per-cycle mkdir lock (this file's lock helpers are a direct adaptation of
# coord-sync.sh:198-231, same stale-reclaim threshold reasoning: a merge
# cycle's own git operations are each bounded to double-digit seconds, so a
# lock older than 900s is provably a crashed holder, never a slow live one).
#
# NEVER: force-pushes, rewrites history (source or target), leaves a
# conflicted merge in progress, or auto-merges true divergence (constitution
# §9; also this script's own self-test greps for force-push flags, same
# discipline as master-drift-autocorrect.sh's T5 scenario).
#
# ============================================================
# USAGE
# ============================================================
#   estate-merge.sh merge <branch> --into <target> [options]
#   estate-merge.sh --check [--into <target>] [options]
#   estate-merge.sh --self-test
#   estate-merge.sh --help
#
# merge options:
#   --repo <path>          checkout where <target> is already checked out
#                           (default: cwd's toplevel). estate-merge.sh NEVER
#                           switches a live checkout's branch for you.
#   --into <target>         REQUIRED. Target branch name — CONFIGURATION, not
#                           hardcoded. Today's real integration target is
#                           wip/harness-hardening-2026-07-29 (master cannot
#                           take merges while a review-record deploy gate
#                           holds unreviewed files); this script works
#                           identically against master once that clears.
#   --remote <name>         canonical remote for freshness + push (default
#                           origin)
#   --reason <text>         rationale recorded in the --no-ff merge commit
#                           message when a fast-forward isn't possible
#   --no-push               skip the push step entirely (local-only
#                           integration branches; also used by --self-test)
#   --push-remotes <csv>    explicit override of which remotes to push
#                           (default: auto — --remote, plus an
#                           auto-discovered mirror ONLY when --into is
#                           master|main, per Decision-064)
#   --slug <slug>           optional log-correlation label (see header note
#                           above — never touches the T4 registration store)
#   --quiet                 suppress narration (BLOCKED/error text still
#                           prints)
#
# --check options (the divergence detector, deliverable 3):
#   --repo <path>
#   --into <target>         which local branch to check (default: master if
#                           it exists locally, else main, else current HEAD)
#   --remote <name>         default origin
#   --lookback <n>          cap on how many merge commits to scan for lock
#                           bypass (default 50) — bounded by BOTH this cap
#                           AND the tracking-since marker (see below)
#   --quiet
#
# TRACKING-SINCE MARKER (state/estate-merge/tracking-since-sha): the FIRST
# time --check (or merge) runs against a given STATE_DIR, it stamps the
# target branch's CURRENT tip as "everything before this is pre-existing
# history, not judged." Without this, --check's bypass scan would flag every
# merge commit that ever landed before this script existed — the same
# "pre-existing debt, named not hidden" discipline
# estate-registration-lib.sh's own header uses for pre-mechanism worktrees.
# The marker is written once and never advanced automatically; delete the
# state dir (or the marker file) to reset the tracked window deliberately.
#
# Exit codes:
#   0  merge: success (ff, no-ff, or already-integrated) | check: CLEAN
#   1  generic failure (a git command failed unexpectedly, not a preflight
#      refusal)
#   2  usage error OR a preflight block (dirty tree, wrong branch checked
#      out, target missing, target behind/diverged its upstream, lock busy,
#      merge conflict)
#   3  --self-test failure
#   4  --check found a RED finding (true divergence, or a merge that
#      bypassed this lock)
#
# Self-test: bash estate-merge.sh --self-test (sandboxed fixture repos; never
# touches a real remote, the real checkout, or ~/.claude/state/estate-merge
# unless HARNESS_SELFTEST pollution-guard Scenario proves otherwise).

set -u

SCRIPT_NAME="estate-merge.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# --- portable bounded subprocess (a hung remote must not wedge the lock) ---
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "$SCRIPT_NAME: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

QUIET=0
log()  { [ "${QUIET:-0}" = 1 ] || printf '%s\n' "$*" >&2; }
warn() { printf '%s: WARN: %s\n' "$SCRIPT_NAME" "$*" >&2; }
usage() {
  sed -n '2,90p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

_em_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""; }
_em_now_ms() {
  local t; t=$(date +%s%3N 2>/dev/null)
  if [[ "$t" =~ ^[0-9]+$ ]]; then printf '%s' "$t"; else printf '%s' "$(( $(date +%s) * 1000 ))"; fi
}
_em_hostname() {
  local h; h=$(hostname 2>/dev/null || echo "")
  [ -n "$h" ] || h="${COMPUTERNAME:-${HOSTNAME:-unknown-host}}"
  printf '%s' "$h"
}

# ============================================================
# State dir (same HARNESS_SELFTEST sandboxing convention as
# admission-lib.sh / estate-registration-lib.sh: explicit override always
# wins; HARNESS_SELFTEST=1 with no override diverts under $TMPDIR).
# ============================================================
_em_state_dir() {
  if [ -n "${ESTATE_MERGE_STATE_DIR:-}" ]; then printf '%s' "$ESTATE_MERGE_STATE_DIR"; return 0; fi
  if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    local base="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}}"
    printf '%s' "${base%/}/estate-merge-selftest-$$"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/estate-merge"
}
STATE_DIR="$(_em_state_dir)"
LOCK_DIR="$STATE_DIR/lock"
LOCK_STALE_SECONDS="${ESTATE_MERGE_LOCK_STALE_SECONDS:-900}"
MERGE_LOG="$STATE_DIR/merges.log"
MERGE_LOG_MAX_LINES="${ESTATE_MERGE_LOG_MAX_LINES:-500}"

# Tracking-since marker path is PER-TARGET (sanitized branch name), not a
# single shared file -- a real bug found while proving this against this
# machine's actual repo: checking 'master' first, then a DIFFERENT target
# like 'wip/harness-hardening-2026-07-29', would reuse master's marker as
# the OTHER target's range boundary, false-flagging every genuinely
# pre-existing merge on that unrelated branch as a lock bypass. Each target
# gets its own "everything before this SHA is pre-existing" baseline.
_em_tracking_marker_path() {
  local target="$1" clean
  clean="$(printf '%s' "$target" | tr -c 'A-Za-z0-9._-' '_')"
  printf '%s/tracking-since-sha.%s' "$STATE_DIR" "$clean"
}

# ============================================================
# Lock (mkdir-atomic — direct adaptation of coord-sync.sh:198-231's
# single-writer idiom: held for the operation's duration, explicitly
# released on exit, a stale holder reclaimed by age).
# ============================================================
_em_lock_age_secs() {
  local dir="$1" ts now
  ts=$(awk 'NR==1{print $2}' "$dir/owner" 2>/dev/null)
  now=$(date -u +%s 2>/dev/null || echo 0)
  if [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt 0 ] && [ "$now" -ge "$ts" ]; then
    echo $(( now - ts )); return 0
  fi
  echo 999999   # unknown/garbled owner file -> treat as very stale (safe to reclaim)
}

_em_acquire_lock() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$LOCK_DIR/owner" 2>/dev/null || true
    return 0
  fi
  local age; age=$(_em_lock_age_secs "$LOCK_DIR")
  if [ "$age" -ge "$LOCK_STALE_SECONDS" ]; then
    warn "reclaiming a stale merge lock (age ${age}s >= ${LOCK_STALE_SECONDS}s) — presumed a crashed prior run"
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s %s\n' "$$" "$(date -u +%s)" > "$LOCK_DIR/owner" 2>/dev/null || true
      return 0
    fi
  fi
  return 1
}

_em_release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null || true; }

# ============================================================
# merges.log — one line per invocation (coord-sync cycles.log idiom).
# ============================================================
_em_log_merge() {
  local outcome="$1" target="$2" source_branch="$3" sha="$4" reason="$5" pushed="$6" slug="$7"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  reason="${reason:--}"; [ -n "$reason" ] || reason="-"
  slug="${slug:--}"; [ -n "$slug" ] || slug="-"
  printf 'ts=%s host=%s target=%s source=%s outcome=%s sha=%s pushed=%s slug=%s reason=%s\n' \
    "$(_em_iso_now)" "$(_em_hostname)" "$target" "$source_branch" "$outcome" "${sha:--}" "$pushed" "$slug" "$reason" \
    >> "$MERGE_LOG" 2>/dev/null || true
  if [ -f "$MERGE_LOG" ]; then
    local lines; lines=$(wc -l < "$MERGE_LOG" 2>/dev/null | tr -d ' ')
    if [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -gt "$MERGE_LOG_MAX_LINES" ]; then
      local tmp="$MERGE_LOG.tmp.$$"
      tail -n "$MERGE_LOG_MAX_LINES" "$MERGE_LOG" > "$tmp" 2>/dev/null && mv -f "$tmp" "$MERGE_LOG" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
  fi
  return 0
}

_em_ensure_tracking_marker() {
  local main="$1" target="$2" marker
  marker="$(_em_tracking_marker_path "$target")"
  [ -f "$marker" ] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  local sha; sha=$(git -C "$main" rev-parse --verify --quiet "refs/heads/$target" 2>/dev/null)
  [ -n "$sha" ] || return 0
  local tmp="$marker.tmp.$$"
  printf '%s\n' "$sha" > "$tmp" 2>/dev/null && mv -f "$tmp" "$marker" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

# ============================================================
# Mirror-remote discovery (duplicated from master-drift-autocorrect.sh's
# _discover_mirror_remote — siblings, not a hierarchy, same reasoning
# estate-registration-lib.sh gives for not sourcing admission-lib.sh).
# Compares FETCH urls (a dual-pushurl canonical remote lies on push-url
# comparison — see that file's own header note); returns the first remote
# whose fetch URL differs from the given canonical remote's.
# ============================================================
_em_discover_mirror_remote() {
  local repo_dir="$1" canonical_remote="$2"
  local canonical_url name mirror_url
  canonical_url="$(git -C "$repo_dir" remote get-url "$canonical_remote" 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && return 0
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    [ "$name" = "$canonical_remote" ] && continue
    mirror_url="$(git -C "$repo_dir" remote get-url "$name" 2>/dev/null || echo "")"
    if [ -n "$mirror_url" ] && [ "$mirror_url" != "$canonical_url" ]; then
      printf '%s' "$name"
      return 0
    fi
  done < <(git -C "$repo_dir" remote 2>/dev/null)
  return 0
}

# ============================================================
# _em_ref_state <repo> <local-ref> <remote> <remote-ref>
# Echoes: no-upstream | converged | behind | ahead | diverged | unreachable
# Read-only — never fetches (callers fetch first, if they want freshness).
# ============================================================
_em_ref_state() {
  local repo="$1" local_ref="$2" remote="$3" remote_ref="$4"
  local local_sha remote_sha
  local_sha=$(git -C "$repo" rev-parse --verify --quiet "$local_ref" 2>/dev/null) || { printf 'unreachable'; return 0; }
  remote_sha=$(git -C "$repo" rev-parse --verify --quiet "$remote/$remote_ref" 2>/dev/null) || { printf 'no-upstream'; return 0; }
  if [ "$local_sha" = "$remote_sha" ]; then printf 'converged'; return 0; fi
  if git -C "$repo" merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
    printf 'behind'; return 0
  fi
  if git -C "$repo" merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
    printf 'ahead'; return 0
  fi
  printf 'diverged'
}

# ============================================================
# merge subcommand
# ============================================================
cmd_merge() {
  local source_branch="" target="" repo="" remote="origin" reason="" no_push=0
  local push_remotes_csv="" slug=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --into) shift; target="${1:-}" ;;
      --repo) shift; repo="${1:-}" ;;
      --remote) shift; remote="${1:-}" ;;
      --reason) shift; reason="${1:-}" ;;
      --no-push) no_push=1 ;;
      --push-remotes) shift; push_remotes_csv="${1:-}" ;;
      --slug) shift; slug="${1:-}" ;;
      --quiet) QUIET=1 ;;
      --*) echo "$SCRIPT_NAME: unknown flag: $1" >&2; return 2 ;;
      *)
        if [ -z "$source_branch" ]; then source_branch="$1"; else echo "$SCRIPT_NAME: unexpected arg: $1" >&2; return 2; fi
        ;;
    esac
    shift
  done

  [ -n "$source_branch" ] || { echo "$SCRIPT_NAME: merge requires a <branch>" >&2; return 2; }
  [ -n "$target" ] || { echo "$SCRIPT_NAME: --into <target> is required" >&2; return 2; }
  [ -n "$remote" ] || remote="origin"

  repo="${repo:-$(pwd)}"
  local main
  main="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "$SCRIPT_NAME: --repo is not a usable git repo: $repo" >&2; return 2; }

  if ! _em_acquire_lock; then
    echo "$SCRIPT_NAME: BLOCKED — another estate-merge is in progress (lock held at $LOCK_DIR) — refusing to run concurrently. Re-run once it finishes." >&2
    return 2
  fi
  trap _em_release_lock EXIT

  local t0; t0=$(_em_now_ms)

  # ---- PREFLIGHT ----
  if ! git -C "$main" rev-parse --verify --quiet "refs/heads/$target" >/dev/null 2>&1; then
    echo "$SCRIPT_NAME: BLOCKED — target branch '$target' does not exist in $main." >&2
    _em_log_merge "blocked-no-target" "$target" "$source_branch" "" "$reason" "no" "$slug"
    return 2
  fi

  local source_sha
  source_sha="$(git -C "$main" rev-parse --verify --quiet "refs/heads/$source_branch" 2>/dev/null)"
  if [ -z "$source_sha" ]; then
    echo "$SCRIPT_NAME: BLOCKED — source branch '$source_branch' does not exist." >&2
    _em_log_merge "blocked-no-source" "$target" "$source_branch" "" "$reason" "no" "$slug"
    return 2
  fi

  local current_branch
  current_branch="$(git -C "$main" symbolic-ref --short HEAD 2>/dev/null || echo "")"
  if [ "$current_branch" != "$target" ]; then
    echo "$SCRIPT_NAME: BLOCKED — $main is on '${current_branch:-<detached>}', not the target branch '$target'." >&2
    echo "  estate-merge.sh never switches a live checkout's branch for you — checkout '$target' in $main first." >&2
    _em_log_merge "blocked-wrong-branch" "$target" "$source_branch" "" "$reason" "no" "$slug"
    return 2
  fi

  local dirty_n
  dirty_n=$(git -C "$main" status --porcelain 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$dirty_n" != "0" ]; then
    echo "$SCRIPT_NAME: BLOCKED — $main has $dirty_n uncommitted change(s) on '$target'. Commit or stash before merging." >&2
    _em_log_merge "blocked-dirty" "$target" "$source_branch" "" "$reason" "no" "$slug"
    return 2
  fi

  _em_ensure_tracking_marker "$main" "$target"

  if git -C "$main" rev-parse --verify --quiet "${target}@{upstream}" >/dev/null 2>&1; then
    nl_run_bounded "${ESTATE_MERGE_FETCH_TIMEOUT:-15}" git -C "$main" fetch --quiet "$remote" "$target" >/dev/null 2>&1
    local target_state; target_state=$(_em_ref_state "$main" "refs/heads/$target" "$remote" "$target")
    case "$target_state" in
      diverged)
        echo "$SCRIPT_NAME: BLOCKED — '$target' has DIVERGED from $remote/$target (neither is an ancestor of the other)." >&2
        echo "  Auto-merge of true divergence is categorically refused. See docs/runbooks/master-reconcile-and-estate-cleanup.md." >&2
        _em_log_merge "blocked-target-diverged" "$target" "$source_branch" "" "$reason" "no" "$slug"
        return 2
        ;;
      behind)
        echo "$SCRIPT_NAME: BLOCKED — '$target' is BEHIND $remote/$target. Fast-forward it first — merging now would hide the upstream advance." >&2
        _em_log_merge "blocked-target-behind" "$target" "$source_branch" "" "$reason" "no" "$slug"
        return 2
        ;;
    esac
  fi

  # ---- Idempotency: already integrated? ----
  if git -C "$main" merge-base --is-ancestor "$source_sha" "refs/heads/$target" 2>/dev/null; then
    log "$SCRIPT_NAME: '$source_branch' is already an ancestor of '$target' — nothing to do"
    local already_sha; already_sha=$(git -C "$main" rev-parse "refs/heads/$target")
    _em_log_merge "already-integrated" "$target" "$source_branch" "$already_sha" "$reason" "no" "$slug"
    return 0
  fi

  # ---- MERGE (ff-only preferred, else an explicit --no-ff with rationale) ----
  local outcome="" merged_sha=""
  if git -C "$main" merge-base --is-ancestor "refs/heads/$target" "$source_sha" 2>/dev/null; then
    if git -C "$main" merge --ff-only -q "$source_branch" >/dev/null 2>&1; then
      outcome="merged-ff"
      merged_sha="$(git -C "$main" rev-parse "$target")"
      log "$SCRIPT_NAME: fast-forwarded '$target' to '$source_branch' ($merged_sha)"
    else
      echo "$SCRIPT_NAME: FAILED — expected a fast-forward but git refused; aborting with no mutation." >&2
      _em_log_merge "failed-ff" "$target" "$source_branch" "" "$reason" "no" "$slug"
      return 1
    fi
  else
    local ahead_n
    ahead_n=$(git -C "$main" rev-list --count "${source_sha}..refs/heads/$target" 2>/dev/null)
    [ -n "$ahead_n" ] || ahead_n="?"
    local msg="estate-merge: integrate $source_branch into $target"
    if [ -n "$reason" ]; then
      msg="$msg

Rationale: $reason"
    fi
    msg="$msg

Fast-forward not possible: $target is $ahead_n commit(s) ahead of source's branch point.
Merged via estate-merge.sh (accountable-estate T5 — the estate's single deterministic merge path)."
    if git -C "$main" merge --no-ff -q -m "$msg" "$source_branch" >/dev/null 2>&1; then
      outcome="merged-noff"
      merged_sha="$(git -C "$main" rev-parse "$target")"
      log "$SCRIPT_NAME: merge commit created for '$source_branch' into '$target' ($merged_sha) — $ahead_n commit(s) had diverged"
    else
      git -C "$main" merge --abort >/dev/null 2>&1 || true
      echo "$SCRIPT_NAME: BLOCKED — merge of '$source_branch' into '$target' produced conflicts. Aborted; no mutation." >&2
      echo "  Resolve manually (existing PR/review flow) and re-run, or split the change." >&2
      _em_log_merge "blocked-conflict" "$target" "$source_branch" "" "$reason" "no" "$slug"
      return 2
    fi
  fi

  # ---- PUSH (per Decision-064: both remotes ONLY for a canonical target) ----
  local pushed_summary="skipped"
  if [ "$no_push" != "1" ]; then
    local remotes_to_push
    if [ -n "$push_remotes_csv" ]; then
      remotes_to_push="$(printf '%s' "$push_remotes_csv" | tr ',' ' ')"
    else
      remotes_to_push="$remote"
      case "$target" in
        master|main)
          local mirror; mirror="$(_em_discover_mirror_remote "$main" "$remote")"
          [ -n "$mirror" ] && remotes_to_push="$remotes_to_push $mirror"
          ;;
      esac
    fi
    local pushed_list="" failed_list="" skipped_list="" r
    for r in $remotes_to_push; do
      [ -z "$r" ] && continue
      if ! git -C "$main" remote get-url "$r" >/dev/null 2>&1; then
        skipped_list="$skipped_list $r:no-such-remote"; continue
      fi
      if ! nl_run_bounded "${ESTATE_MERGE_LSREMOTE_TIMEOUT:-10}" git -C "$main" ls-remote --exit-code "$r" "refs/heads/$target" >/dev/null 2>&1; then
        skipped_list="$skipped_list $r:no-remote-branch"; continue
      fi
      local push_out push_rc
      push_out=$(nl_run_bounded "${ESTATE_MERGE_PUSH_TIMEOUT:-30}" git -C "$main" push "$r" "$target:$target" 2>&1)
      push_rc=$?
      if [ "$push_rc" -eq 0 ]; then
        pushed_list="$pushed_list $r"
      else
        failed_list="$failed_list $r"
        warn "push to '$r' failed (rc=$push_rc) — the merge is LOCAL only for that remote: $(printf '%s' "$push_out" | tail -1)"
      fi
    done
    pushed_list="${pushed_list# }"; failed_list="${failed_list# }"; skipped_list="${skipped_list# }"
    pushed_summary="pushed=${pushed_list:-none};failed=${failed_list:-none};skipped=${skipped_list:-none}"
  fi

  local t1; t1=$(_em_now_ms)
  _em_log_merge "$outcome" "$target" "$source_branch" "$merged_sha" "$reason" "$pushed_summary" "$slug"
  log "$SCRIPT_NAME: DONE outcome=$outcome target=$target sha=$merged_sha push={$pushed_summary} ($(( t1 - t0 ))ms)"
  return 0
}

# ============================================================
# --check subcommand (the divergence detector, deliverable 3)
# ============================================================
cmd_check() {
  local repo="" target="" remote="origin" lookback=50

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) shift; repo="${1:-}" ;;
      --into) shift; target="${1:-}" ;;
      --remote) shift; remote="${1:-}" ;;
      --lookback) shift; lookback="${1:-50}" ;;
      --quiet) QUIET=1 ;;
      --*) echo "$SCRIPT_NAME: unknown flag: $1" >&2; return 2 ;;
      *) echo "$SCRIPT_NAME: --check takes no positional args (got '$1')" >&2; return 2 ;;
    esac
    shift
  done

  repo="${repo:-$(pwd)}"
  local main
  main="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "$SCRIPT_NAME --check: not a usable git repo: $repo" >&2; return 2; }
  [ -n "$remote" ] || remote="origin"
  [[ "$lookback" =~ ^[0-9]+$ ]] || lookback=50

  if [ -z "$target" ]; then
    if git -C "$main" rev-parse --verify --quiet refs/heads/master >/dev/null 2>&1; then target="master"
    elif git -C "$main" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then target="main"
    else target="$(git -C "$main" symbolic-ref --short HEAD 2>/dev/null || echo "")"; fi
  fi
  if [ -z "$target" ] || ! git -C "$main" rev-parse --verify --quiet "refs/heads/$target" >/dev/null 2>&1; then
    echo "$SCRIPT_NAME --check: no target branch resolvable (no local master/main, and no --into given)" >&2
    return 2
  fi

  _em_ensure_tracking_marker "$main" "$target"

  local red=0
  local findings=""

  # ---- Axis 1: target vs its upstream (freshness / true divergence) ----
  if git -C "$main" rev-parse --verify --quiet "${target}@{upstream}" >/dev/null 2>&1; then
    nl_run_bounded "${ESTATE_MERGE_FETCH_TIMEOUT:-15}" git -C "$main" fetch --quiet "$remote" "$target" >/dev/null 2>&1
    local state; state=$(_em_ref_state "$main" "refs/heads/$target" "$remote" "$target")
    case "$state" in
      diverged)
        red=1
        findings="${findings}RED: '$target' has DIVERGED from $remote/$target (neither is an ancestor of the other) -- run docs/runbooks/master-reconcile-and-estate-cleanup.md.
"
        ;;
      behind)
        local n; n=$(git -C "$main" rev-list --count "refs/heads/$target..$remote/$target" 2>/dev/null)
        [ -n "$n" ] || n="?"
        findings="${findings}WARN: '$target' is BEHIND $remote/$target by $n commit(s) -- fast-forward it (staleness, not divergence).
"
        ;;
      converged)
        findings="${findings}OK: '$target' is CONVERGED with $remote/$target.
"
        ;;
      ahead)
        findings="${findings}OK: '$target' is AHEAD of $remote/$target (local commits not yet pushed).
"
        ;;
      *)
        findings="${findings}INFO: '$target' upstream state unresolvable ($state).
"
        ;;
    esac
  else
    findings="${findings}INFO: '$target' has no configured upstream -- freshness check skipped (local-only integration branch).
"
  fi

  # ---- Axis 2: any merge into '$target' that bypassed this lock? ----
  # Bounded by BOTH --lookback AND the tracking-since marker, so pre-existing
  # history (merges that landed before this mechanism existed) is never
  # false-flagged -- same "pre-existing debt, named not hidden" discipline as
  # estate-registration-lib.sh.
  local marker_sha="" marker; marker="$(_em_tracking_marker_path "$target")"
  [ -f "$marker" ] && marker_sha=$(head -n1 "$marker" 2>/dev/null | tr -d '[:space:]')
  local range="refs/heads/$target"
  if [ -n "$marker_sha" ] && git -C "$main" rev-parse --verify --quiet "$marker_sha" >/dev/null 2>&1; then
    range="refs/heads/$target ^$marker_sha"
  fi
  local merge_shas
  merge_shas=$(git -C "$main" log --merges --format=%H -n "$lookback" $range 2>/dev/null)
  local bypass_n=0 sha
  for sha in $merge_shas; do
    [ -z "$sha" ] && continue
    if [ -f "$MERGE_LOG" ] && grep -q "sha=$sha" "$MERGE_LOG" 2>/dev/null; then
      continue
    fi
    bypass_n=$((bypass_n + 1))
    local subject; subject=$(git -C "$main" log -1 --format=%s "$sha" 2>/dev/null)
    findings="${findings}RED: merge commit $sha ('$subject') in '$target' history is not recorded in $MERGE_LOG -- it bypassed the estate-merge lock.
"
  done
  [ "$bypass_n" -gt 0 ] && red=1

  printf '%s' "$findings"
  if [ "$red" = "1" ]; then
    echo "$SCRIPT_NAME --check: RED -- see findings above."
    return 4
  fi
  echo "$SCRIPT_NAME --check: CLEAN (target=$target, lookback=$lookback)."
  return 0
}

# ============================================================
# --self-test
# ============================================================
_em_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  # No force-push anywhere in this file (static guarantee, same discipline as
  # master-drift-autocorrect.sh's own self-test T5 — pattern split so this
  # grep can't match itself).
  local force_pat
  force_pat='git[^#]*pu''sh[^#]*(--for''ce|[[:space:]]-f([[:space:]]|$))'
  if grep -qE "$force_pat" "${BASH_SOURCE[0]}"; then
    fail "static guarantee: this script contains a force-push pattern"
  else
    pass "static guarantee: no force-push pattern anywhere in this script"
  fi

  local T; T="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp"; return 1; }
  export HARNESS_SELFTEST=1

  # _mk_fixture <dir> -- a bare "origin" + a main checkout with a "target"
  # branch (2 commits) and a "source" branch forked from target's tip.
  # Returns via globals: FX_MAIN FX_BARE
  _mk_fixture() {
    local dir="$1"
    FX_BARE="$dir/origin.git"; FX_MAIN="$dir/main"
    git init -q --bare "$FX_BARE"
    git init -q -b target "$FX_MAIN"
    git -C "$FX_MAIN" config user.email t@example.com
    git -C "$FX_MAIN" config user.name t
    git -C "$FX_MAIN" config core.hooksPath ""
    git -C "$FX_MAIN" remote add origin "$FX_BARE"
    echo base > "$FX_MAIN/f.txt"; git -C "$FX_MAIN" add f.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm base
    echo t1 > "$FX_MAIN/t.txt"; git -C "$FX_MAIN" add t.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target commit 1"
    git -C "$FX_MAIN" branch source target
  }

  echo "Scenario 1: fast-forward merge (source strictly ahead of target)"
  {
    local d="$T/s1"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    local src_sha; src_sha=$(git -C "$FX_MAIN" rev-parse source)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "ff merge: exit 0" || fail "ff merge: expected 0, got $rc: $(cat "$d/out.log")"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$src_sha" ] && pass "ff merge: target fast-forwarded to source tip" \
      || fail "ff merge: target did not advance to source tip"
    grep -q "outcome=merged-ff" "$d/state/merges.log" 2>/dev/null && pass "ff merge: logged outcome=merged-ff" \
      || fail "ff merge: merges.log missing outcome=merged-ff: $(cat "$d/state/merges.log" 2>/dev/null)"
  }

  echo "Scenario 2: already-integrated source -> no-op, exit 0"
  {
    local d="$T/s2"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    # source == target here (never diverged) -> source is already an ancestor.
    git -C "$FX_MAIN" checkout -q target
    local before; before=$(git -C "$FX_MAIN" rev-parse target)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "already-integrated: exit 0" || fail "already-integrated: expected 0, got $rc"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$before" ] && pass "already-integrated: target unchanged" \
      || fail "already-integrated: target moved unexpectedly"
    grep -q "outcome=already-integrated" "$d/state/merges.log" 2>/dev/null && pass "already-integrated: logged" \
      || fail "already-integrated: not logged: $(cat "$d/state/merges.log" 2>/dev/null)"
  }

  echo "Scenario 3: divergent history -> explicit --no-ff merge commit with recorded rationale"
  {
    local d="$T/s3"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    echo t2 > "$FX_MAIN/t2.txt"; git -C "$FX_MAIN" add t2.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target commit 2 (diverges from source)"
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet --reason "closing worktree wt-x" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "no-ff merge: exit 0" || fail "no-ff merge: expected 0, got $rc: $(cat "$d/out.log")"
    git -C "$FX_MAIN" log -1 --format=%P target | grep -q ' ' && pass "no-ff merge: target now has 2 parents (a real merge commit)" \
      || fail "no-ff merge: target has only 1 parent"
    git -C "$FX_MAIN" log -1 --format=%B target | grep -q "Rationale: closing worktree wt-x" && pass "no-ff merge: rationale recorded in the commit message" \
      || fail "no-ff merge: rationale missing from commit message: $(git -C "$FX_MAIN" log -1 --format=%B target)"
    grep -q "outcome=merged-noff" "$d/state/merges.log" 2>/dev/null && pass "no-ff merge: logged outcome=merged-noff" \
      || fail "no-ff merge: not logged"
  }

  echo "Scenario 4: merge conflict -> aborted cleanly, no mutation, exit 2"
  {
    local d="$T/s4"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo "SOURCE-VERSION" > "$FX_MAIN/f.txt"; git -C "$FX_MAIN" add f.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source conflicting edit"
    git -C "$FX_MAIN" checkout -q target
    echo "TARGET-VERSION" > "$FX_MAIN/f.txt"; git -C "$FX_MAIN" add f.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target conflicting edit"
    local before; before=$(git -C "$FX_MAIN" rev-parse target)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "conflict: exit 2 (BLOCKED)" || fail "conflict: expected 2, got $rc: $(cat "$d/out.log")"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$before" ] && pass "conflict: target unchanged" \
      || fail "conflict: target moved despite the conflict"
    [ -z "$(git -C "$FX_MAIN" status --porcelain 2>/dev/null)" ] && pass "conflict: worktree clean after abort (no merge left in progress)" \
      || fail "conflict: worktree is dirty after the aborted merge: $(git -C "$FX_MAIN" status --porcelain)"
    grep -q "outcome=blocked-conflict" "$d/state/merges.log" 2>/dev/null && pass "conflict: logged outcome=blocked-conflict" \
      || fail "conflict: not logged"
  }

  echo "Scenario 5: dirty worktree on target -> BLOCKED, exit 2, no mutation"
  {
    local d="$T/s5"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    echo uncommitted > "$FX_MAIN/dirty.txt"
    local before; before=$(git -C "$FX_MAIN" rev-parse target)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "dirty tree: exit 2 (BLOCKED)" || fail "dirty tree: expected 2, got $rc"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$before" ] && pass "dirty tree: target unchanged" || fail "dirty tree: target moved"
    [ -f "$FX_MAIN/dirty.txt" ] && pass "dirty tree: uncommitted file untouched" || fail "dirty tree: uncommitted file vanished"
  }

  echo "Scenario 6: main not on the target branch -> BLOCKED, exit 2"
  {
    local d="$T/s6"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "wrong branch checked out: exit 2 (BLOCKED)" || fail "wrong branch: expected 2, got $rc"
  }

  echo "Scenario 7: nonexistent target branch -> BLOCKED, exit 2"
  {
    local d="$T/s7"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    bash "${BASH_SOURCE[0]}" merge source --into does-not-exist --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "nonexistent target: exit 2 (BLOCKED)" || fail "nonexistent target: expected 2, got $rc"
  }

  echo "Scenario 8: target BEHIND its upstream -> BLOCKED at merge time (the live class: local master behind origin/master)"
  {
    local d="$T/s8"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    git -C "$FX_MAIN" push -q origin target:target
    git -C "$FX_MAIN" branch --set-upstream-to=origin/target target
    # Advance the REMOTE independently (simulates "someone else pushed"),
    # leaving local target strictly behind origin/target.
    local adv="$d/advancer"
    git clone -q -b target "$FX_BARE" "$adv"
    git -C "$adv" config user.email t@example.com; git -C "$adv" config user.name t
    git -C "$adv" config core.hooksPath ""
    echo remote-advance > "$adv/r.txt"; git -C "$adv" add r.txt
    git -C "$adv" -c commit.gpgsign=false commit -qm "remote-only advance"
    git -C "$adv" push -q origin target:target
    local before; before=$(git -C "$FX_MAIN" rev-parse target)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "target behind upstream: exit 2 (BLOCKED)" || fail "target behind upstream: expected 2, got $rc: $(cat "$d/out.log")"
    grep -qi "BEHIND" "$d/out.log" && pass "target behind upstream: message names BEHIND" || fail "message missing BEHIND: $(cat "$d/out.log")"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$before" ] && pass "target behind upstream: local target unchanged" || fail "local target moved"
  }

  echo "Scenario 9: target DIVERGED from its upstream -> BLOCKED, points at the reconcile runbook"
  {
    local d="$T/s9"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    git -C "$FX_MAIN" push -q origin target:target
    git -C "$FX_MAIN" branch --set-upstream-to=origin/target target
    local adv="$d/advancer"
    git clone -q -b target "$FX_BARE" "$adv"
    git -C "$adv" config user.email t@example.com; git -C "$adv" config user.name t
    git -C "$adv" config core.hooksPath ""
    echo remote-only > "$adv/r.txt"; git -C "$adv" add r.txt
    git -C "$adv" -c commit.gpgsign=false commit -qm "remote-only commit"
    git -C "$adv" push -q origin target:target
    # local target ALSO advances independently -> true divergence
    echo local-only > "$FX_MAIN/l.txt"; git -C "$FX_MAIN" add l.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "local-only commit"
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "target diverged: exit 2 (BLOCKED)" || fail "target diverged: expected 2, got $rc"
    grep -qi "DIVERGED" "$d/out.log" && pass "target diverged: message names DIVERGED" || fail "message missing DIVERGED"
    grep -q "master-reconcile-and-estate-cleanup" "$d/out.log" && pass "target diverged: points at the reconcile runbook" \
      || fail "message missing runbook pointer: $(cat "$d/out.log")"
  }

  echo "Scenario 10: push -- successful merge is pushed to its remote (bare fixture)"
  {
    local d="$T/s10"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    git -C "$FX_MAIN" push -q origin target:target
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "push: merge exit 0" || fail "push: expected 0, got $rc: $(cat "$d/out.log")"
    local main_sha bare_sha
    main_sha=$(git -C "$FX_MAIN" rev-parse target)
    bare_sha=$(git --git-dir="$FX_BARE" rev-parse target)
    [ "$main_sha" = "$bare_sha" ] && pass "push: origin's target ref advanced to match the merge" \
      || fail "push: origin did not advance (main=$main_sha bare=$bare_sha)"
    grep -q "pushed=origin" "$d/state/merges.log" 2>/dev/null && pass "push: merges.log records pushed=origin" \
      || fail "push: not recorded: $(cat "$d/state/merges.log" 2>/dev/null)"
  }

  echo "Scenario 11: --no-push / no remote branch -> merge still succeeds locally, push reported skipped"
  {
    local d="$T/s11"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    # target was never pushed to origin at all -- no remote branch to push to.
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "no remote branch: merge still succeeds locally, exit 0" || fail "expected 0, got $rc: $(cat "$d/out.log")"
    grep -q "no-remote-branch" "$d/state/merges.log" 2>/dev/null && pass "no remote branch: recorded as skipped" \
      || fail "not recorded as skipped: $(cat "$d/state/merges.log" 2>/dev/null)"
  }

  echo "Scenario 12: lock prevents concurrent execution (held, fresh) -> refuses, no mutation"
  {
    local d="$T/s12"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    mkdir -p "$d/state/lock"
    printf '%s %s\n' 999999 "$(date -u +%s)" > "$d/state/lock/owner"
    local before; before=$(git -C "$FX_MAIN" rev-parse target)
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "2" ] && pass "held fresh lock: exit 2 (BLOCKED)" || fail "held fresh lock: expected 2, got $rc"
    [ "$(git -C "$FX_MAIN" rev-parse target)" = "$before" ] && pass "held fresh lock: target unchanged (no merge attempted)" \
      || fail "held fresh lock: target moved despite the lock"
  }

  echo "Scenario 13: a STALE lock is reclaimed and the merge proceeds"
  {
    local d="$T/s13"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    mkdir -p "$d/state/lock"
    printf '%s %s\n' 999999 "$(( $(date -u +%s) - 1000 ))" > "$d/state/lock/owner"
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "stale lock (age > 900s): reclaimed, merge proceeds (exit 0)" || fail "expected 0, got $rc: $(cat "$d/out.log")"
    [ ! -d "$d/state/lock" ] && pass "lock released after the reclaimed run completes" || fail "lock still held after completion"
  }

  echo "Scenario 14: --check CLEAN on a fresh target (tracking marker just created, nothing to flag)"
  {
    local d="$T/s14"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "--check clean: exit 0" || fail "--check clean: expected 0, got $rc: $(cat "$d/out.log")"
    grep -q "CLEAN" "$d/out.log" && pass "--check clean: reports CLEAN" || fail "--check clean: no CLEAN in output: $(cat "$d/out.log")"
  }

  echo "Scenario 15: --check catches the live class -- target strictly BEHIND its upstream (WARN, not RED)"
  {
    local d="$T/s15"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    git -C "$FX_MAIN" push -q origin target:target
    git -C "$FX_MAIN" branch --set-upstream-to=origin/target target
    local adv="$d/advancer"
    git clone -q -b target "$FX_BARE" "$adv"
    git -C "$adv" config user.email t@example.com; git -C "$adv" config user.name t
    git -C "$adv" config core.hooksPath ""
    echo remote-advance > "$adv/r.txt"; git -C "$adv" add r.txt
    git -C "$adv" -c commit.gpgsign=false commit -qm "remote-only advance"
    git -C "$adv" push -q origin target:target
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "--check behind: exit 0 (WARN, not a RED-level divergence)" || fail "--check behind: expected 0, got $rc: $(cat "$d/out.log")"
    grep -q "WARN.*BEHIND" "$d/out.log" && pass "--check behind: WARN finding present" || fail "--check behind: no WARN/BEHIND finding: $(cat "$d/out.log")"
  }

  echo "Scenario 16: --check catches TRUE divergence -- RED, exit 4"
  {
    local d="$T/s16"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    git -C "$FX_MAIN" push -q origin target:target
    git -C "$FX_MAIN" branch --set-upstream-to=origin/target target
    local adv="$d/advancer"
    git clone -q -b target "$FX_BARE" "$adv"
    git -C "$adv" config user.email t@example.com; git -C "$adv" config user.name t
    git -C "$adv" config core.hooksPath ""
    echo remote-only > "$adv/r.txt"; git -C "$adv" add r.txt
    git -C "$adv" -c commit.gpgsign=false commit -qm "remote-only commit"
    git -C "$adv" push -q origin target:target
    echo local-only > "$FX_MAIN/l.txt"; git -C "$FX_MAIN" add l.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "local-only commit"
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "4" ] && pass "--check diverged: exit 4 (RED)" || fail "--check diverged: expected 4, got $rc: $(cat "$d/out.log")"
    grep -q "RED.*DIVERGED" "$d/out.log" && pass "--check diverged: RED finding present" || fail "--check diverged: no RED/DIVERGED finding"
  }

  echo "Scenario 17: --check does NOT flag a merge performed via this script's own 'merge' subcommand"
  {
    local d="$T/s17"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >/dev/null 2>&1   # stamp the tracking marker BEFORE the merge
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    echo t2 > "$FX_MAIN/t2.txt"; git -C "$FX_MAIN" add t2.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target commit 2 (diverges from source)"
    bash "${BASH_SOURCE[0]}" merge source --into target --repo "$FX_MAIN" --no-push --quiet >/dev/null 2>&1
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "0" ] && pass "--check after a lock-honoring merge: exit 0 (no bypass)" || fail "expected 0, got $rc: $(cat "$d/out.log")"
    grep -qi "bypassed" "$d/out.log" && fail "--check false-flagged its own lock-honoring merge as a bypass" \
      || pass "--check does not false-flag a merge that went through this script"
  }

  echo "Scenario 18: --check DOES flag a merge that bypassed the lock (a plain 'git merge --no-ff' done by hand)"
  {
    local d="$T/s18"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    git -C "$FX_MAIN" checkout -q target
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >/dev/null 2>&1   # stamp the tracking marker first
    git -C "$FX_MAIN" checkout -q source
    echo s1 > "$FX_MAIN/s.txt"; git -C "$FX_MAIN" add s.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "source commit 1"
    git -C "$FX_MAIN" checkout -q target
    echo t2 > "$FX_MAIN/t2.txt"; git -C "$FX_MAIN" add t2.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target commit 2 (diverges from source)"
    git -C "$FX_MAIN" -c commit.gpgsign=false merge -q --no-ff -m "hand-merged, bypassing the lock" source >/dev/null 2>&1
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out.log" 2>&1
    local rc=$?
    [ "$rc" = "4" ] && pass "--check bypass: exit 4 (RED)" || fail "--check bypass: expected 4, got $rc: $(cat "$d/out.log")"
    grep -qi "bypassed the estate-merge lock" "$d/out.log" && pass "--check bypass: RED finding names the bypass" \
      || fail "--check bypass: no bypass finding: $(cat "$d/out.log")"
  }

  echo "Scenario 19: multi-target tracking-marker isolation -- checking one target first must NOT contaminate a DIFFERENT target's own baseline (real bug, found running --check against this machine's actual wip/harness-hardening-2026-07-29: checking 'master' first left a stale marker that false-flagged wip/harness-hardening's own genuinely pre-existing merges)"
  {
    local d="$T/s19"; mkdir -p "$d"
    _mk_fixture "$d"
    export ESTATE_MERGE_STATE_DIR="$d/state"
    # A SECOND branch with its OWN pre-existing merge commit, created BEFORE
    # any --check has ever run against EITHER branch (mirrors a real repo
    # with unrelated history on two different integration branches).
    git -C "$FX_MAIN" checkout -q -b other target
    echo other1 > "$FX_MAIN/other1.txt"; git -C "$FX_MAIN" add other1.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "other: commit 1"
    git -C "$FX_MAIN" checkout -q target
    echo other2 > "$FX_MAIN/other2.txt"; git -C "$FX_MAIN" add other2.txt
    git -C "$FX_MAIN" -c commit.gpgsign=false commit -qm "target: unrelated commit"
    git -C "$FX_MAIN" -c commit.gpgsign=false merge -q --no-ff -m "pre-existing merge on 'other', predates any --check" other >/dev/null 2>&1
    git -C "$FX_MAIN" checkout -q -b other2 target
    # Now check 'target' FIRST (stamps ITS OWN marker at the current tip,
    # which is AFTER the pre-existing merge above).
    bash "${BASH_SOURCE[0]}" --check --into target --repo "$FX_MAIN" >"$d/out1.log" 2>&1
    local rc1=$?
    [ "$rc1" = "0" ] && pass "multi-target: first target's own check is CLEAN (its marker covers its own pre-existing merge)" \
      || fail "multi-target: first target check unexpectedly RED: $(cat "$d/out1.log")"
    # 'other2' is a DIFFERENT branch name whose history ALSO contains that
    # same pre-existing merge commit (branched from target after it landed).
    # Checking it for the FIRST TIME must not be poisoned by 'target's marker.
    bash "${BASH_SOURCE[0]}" --check --into other2 --repo "$FX_MAIN" >"$d/out2.log" 2>&1
    local rc2=$?
    [ "$rc2" = "0" ] && pass "multi-target: a DIFFERENT target's first-ever check is ALSO clean (own marker, not contaminated by target's)" \
      || fail "multi-target: second target's first check wrongly RED (marker cross-contamination): $(cat "$d/out2.log")"
    grep -qi "bypassed" "$d/out2.log" && fail "multi-target: second target's pre-existing merge was false-flagged as a bypass" \
      || pass "multi-target: no false bypass finding on the second target's own pre-existing history"
    [ -f "$d/state/tracking-since-sha.target" ] && [ -f "$d/state/tracking-since-sha.other2" ] \
      && [ "$(cat "$d/state/tracking-since-sha.target")" != "$(cat "$d/state/tracking-since-sha.other2")" ] \
      && fail "multi-target: expected the SAME tip for both (other2 branched from target's current tip) -- markers diverged unexpectedly" \
      || pass "multi-target: separate per-target marker files exist (tracking-since-sha.<target>)"
  }

  echo "Scenario 20: HARNESS_SELFTEST sandbox-pollution guard (mirrors admission-lib/estate-registration-lib convention)"
  {
    unset ESTATE_MERGE_STATE_DIR
    local resolved; resolved="$(HARNESS_SELFTEST=1 bash -c "source '${BASH_SOURCE[0]}' 2>/dev/null; _em_state_dir" 2>/dev/null)"
    case "$resolved" in
      "$HOME/.claude/state/estate-merge") fail "HARNESS_SELFTEST=1 still resolved to REAL state ($resolved)" ;;
      *) pass "HARNESS_SELFTEST=1 with no override redirects away from real state ($resolved)" ;;
    esac
    local explicit; explicit="$(ESTATE_MERGE_STATE_DIR="$T/explicit" HARNESS_SELFTEST=1 bash -c "source '${BASH_SOURCE[0]}' 2>/dev/null; _em_state_dir" 2>/dev/null)"
    [ "$explicit" = "$T/explicit" ] && pass "explicit ESTATE_MERGE_STATE_DIR still wins over the guard" \
      || fail "explicit override ignored, got '$explicit'"
    local prod; prod="$(HARNESS_SELFTEST=0 bash -c "source '${BASH_SOURCE[0]}' 2>/dev/null; _em_state_dir" 2>/dev/null)"
    [ "$prod" = "$HOME/.claude/state/estate-merge" ] && pass "production path unchanged when not self-testing" \
      || fail "production path wrong: '$prod'"
  }

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [ "$FAIL" = "0" ] && { echo "self-test: OK"; return 0; }
  return 1
}

# ============================================================
# main — GATED ON BEING EXECUTED, NOT SOURCED (same discipline as
# admission-lib.sh / estate-registration-lib.sh: a sourced script that
# dispatches on "$1" would inherit the caller's positionals, or — as here —
# exit the caller's shell the moment it is sourced with zero args).
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    merge) shift; cmd_merge "$@"; exit $? ;;
    --check) shift; cmd_check "$@"; exit $? ;;
    --self-test) _em_self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    "") usage >&2; exit 2 ;;
    *) echo "$SCRIPT_NAME: unknown subcommand: $1" >&2; usage >&2; exit 2 ;;
  esac
fi
