#!/usr/bin/env bash
# worktree-prune.sh
#
# Conservative pruner for accumulated Dispatch / orchestrator git worktrees.
#
# Context: the Claude Code desktop app's Dispatch ("+ New session") flow
# creates a sibling git worktree per code task (e.g.
# ~/claude-projects/<project>/<adjective-name-hash> on branch
# claude/<same>). Nothing in the Anthropic runtime or this harness removes
# that worktree when the session ends, so they accumulate without bound
# (one machine on 2026-05-17 had ~50 in a single repo and ~30 in another,
# still growing). This script is the in-our-control half of the fix:
# periodically remove the ones that are provably safe to remove, and
# ONLY those.
#
# A worktree is removed ONLY when ALL of these hold:
#   - it is not the repo's main checkout
#   - it is not the worktree the script is being run from
#   - it is not `locked` (orchestrator Agent-tool isolation worktrees are
#     locked; they are handled by the orchestrator cherry-pick protocol,
#     never by this script) unless --include-locked is given
#   - the working tree has no REAL uncommitted changes (transient
#     session/build noise is ignored: .claude/state, scheduled_tasks.lock,
#     node_modules, .next, dist, *.tsbuildinfo, SCRATCHPAD.md)
#   - the branch's work is already in master: tip is an ancestor of
#     <master-ref>, OR `git diff --quiet <master-ref>...tip` (the branch
#     introduces no net change vs its fork point — covers squash-merges)
#   - the branch's last commit is at least --age-days old (default 3),
#     so a session that ran today/recently is never touched
#
# Everything else (dirty, unmerged-with-unique-commits, locked, recent)
# is LEFT IN PLACE and listed under "SKIPPED (needs human review)".
#
# Default mode is --dry-run (prints, removes nothing). Pass --apply to act.
#
# Usage:
#   worktree-prune.sh [--apply] [--age-days N] [--include-locked]
#                     [--repo <main-checkout-path>]... [--quiet]
#   worktree-prune.sh --self-test
#
# With no --repo, the script discovers the main checkout of the CWD's repo
# via `git rev-parse --git-common-dir` and prunes that repo. Pass --repo
# one or more times to target specific repos (used by the scheduled job).
#
# Exit codes:
#   0 — ran successfully (dry-run or apply); see stdout for the report
#   1 — a --repo argument was not a usable git repo
#   2 — usage error (bad flag / missing value)
#   3 — --self-test failure
#
# Windows note: `git worktree remove` deletes the tracked files and
# de-registers the worktree, but the now-empty leaf directory frequently
# fails its final rmdir with "Permission denied" because Explorer / the
# search indexer / a cloud file-sync client holds a transient handle.
# De-registration is
# the success criterion; the empty husk is harmless and is best-effort
# rmdir'd here and swept by `git worktree prune`.
set -u

# Absolute path to this script, captured BEFORE any cd (the self-test cds
# into a temp repo and re-invokes $0; a relative $0 would not resolve).
SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

AGE_DAYS=3
APPLY=0
INCLUDE_LOCKED=0
QUIET=0
REPOS=()

die_usage() { echo "worktree-prune.sh: $1" >&2; echo "see header for usage" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --include-locked) INCLUDE_LOCKED=1 ;;
    --quiet) QUIET=1 ;;
    --age-days) shift; [ $# -gt 0 ] || die_usage "--age-days needs a value"; AGE_DAYS="$1" ;;
    --repo) shift; [ $# -gt 0 ] || die_usage "--repo needs a path"; REPOS+=("$1") ;;
    --self-test) RUN_SELF_TEST=1 ;;
    -h|--help) sed -n '2,55p' "$0"; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
  shift
done

case "$AGE_DAYS" in (*[!0-9]*|'') die_usage "--age-days must be a non-negative integer" ;; esac

NOISE_RE='(^|/)\.claude/(state|worktrees)/|(^|/)\.claude/scheduled_tasks\.lock|(^|/)node_modules/|(^|/)\.next/|(^|/)dist/|\.tsbuildinfo$|(^|/)SCRATCHPAD\.md$'

# Resolve the master ref to compare branch work against.
master_ref() {
  local main="$1"
  if git -C "$main" rev-parse --verify -q origin/master >/dev/null 2>&1; then echo origin/master
  elif git -C "$main" rev-parse --verify -q master >/dev/null 2>&1; then echo master
  elif git -C "$main" rev-parse --verify -q origin/main >/dev/null 2>&1; then echo origin/main
  elif git -C "$main" rev-parse --verify -q main >/dev/null 2>&1; then echo main
  else echo HEAD; fi
}

# Real (non-noise) uncommitted change count for a worktree path.
real_dirt_count() {
  git -C "$1" status --porcelain 2>/dev/null \
    | sed 's/^...//' \
    | grep -vE "$NOISE_RE" \
    | sed '/^$/d' | wc -l | tr -d ' '
}

prune_repo() {
  local MAIN="$1"
  local TOPLEVEL
  TOPLEVEL=$(git -C "$MAIN" rev-parse --show-toplevel 2>/dev/null) || { echo "worktree-prune.sh: not a git repo: $MAIN" >&2; return 1; }
  local MASTER; MASTER=$(master_ref "$MAIN")
  local SELF; SELF=$(git rev-parse --show-toplevel 2>/dev/null || echo "__none__")
  local NOW; NOW=$(date +%s)
  local removed=0 brdel=0 skipped=0

  [ "$QUIET" = 1 ] || echo "### repo: $TOPLEVEL  (master ref: $MASTER, age>=${AGE_DAYS}d, apply=$APPLY)"

  # Parse `git worktree list --porcelain` into: path \t branch \t locked.
  # Captured into a var first so the loop runs in THIS shell (a pipe
  # `| while` runs in a subshell and the counters would be lost).
  local WTLIST
  WTLIST=$(git -C "$MAIN" worktree list --porcelain | awk '
    /^worktree /{wt=substr($0,10)}
    /^branch /{br=substr($0,8)}
    /^detached/{br="(detached)"}
    /^locked/{lk=1}
    /^$/{if(wt!=""){print wt"\t"br"\t"(lk?1:0); wt="";br="";lk=0}}
    END{if(wt!=""){print wt"\t"br"\t"(lk?1:0)}}
  ')
  while IFS=$'\t' read -r WT BR LK; do
    [ -z "$WT" ] && continue
    BR=${BR#refs/heads/}
    local reason=""
    # main checkout
    if [ "$WT" = "$TOPLEVEL" ]; then continue; fi
    # current worktree
    if [ "$WT" = "$SELF" ]; then reason="current session worktree"; fi
    # locked
    if [ -z "$reason" ] && [ "$LK" = 1 ] && [ "$INCLUDE_LOCKED" != 1 ]; then reason="locked (orchestrator worktree — out of scope)"; fi
    # age
    local LCEPOCH AGE
    LCEPOCH=$(git -C "$WT" log -1 --format=%ct 2>/dev/null || echo "")
    if [ -z "$reason" ]; then
      if [ -z "$LCEPOCH" ]; then reason="no commits / unreadable"; else
        AGE=$(( (NOW - LCEPOCH) / 86400 ))
        if [ "$AGE" -lt "$AGE_DAYS" ]; then reason="recent (age ${AGE}d < ${AGE_DAYS}d — possible live session)"; fi
      fi
    fi
    # dirty
    if [ -z "$reason" ]; then
      local DC; DC=$(real_dirt_count "$WT")
      [ "$DC" != "0" ] && reason="$DC uncommitted change(s) — salvageable, needs review"
    fi
    # merged?
    if [ -z "$reason" ]; then
      local TIP; TIP=$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "")
      if [ -n "$TIP" ] && git -C "$MAIN" merge-base --is-ancestor "$TIP" "$MASTER" 2>/dev/null; then :
      elif [ -n "$TIP" ] && git -C "$MAIN" diff --quiet "$MASTER...$TIP" 2>/dev/null; then :
      else reason="unmerged commits not in $MASTER — needs review"; fi
    fi

    if [ -n "$reason" ]; then
      skipped=$((skipped+1))
      [ "$QUIET" = 1 ] || echo "  SKIP  $BR  — $reason"
      continue
    fi

    if [ "$APPLY" = 1 ]; then
      git -C "$MAIN" worktree remove --force "$WT" >/dev/null 2>&1
      if git -C "$MAIN" worktree list --porcelain | grep -qxF "worktree $WT"; then
        [ "$QUIET" = 1 ] || echo "  FAIL  $BR  — still registered after remove"
      else
        removed=$((removed+1))
        rmdir "$WT" 2>/dev/null || true
        if git -C "$MAIN" branch -d "$BR" >/dev/null 2>&1; then brdel=$((brdel+1)); fi
        [ "$QUIET" = 1 ] || echo "  REMOVED  $BR"
      fi
    else
      removed=$((removed+1))
      [ "$QUIET" = 1 ] || echo "  WOULD-REMOVE  $BR  (merged & clean, age ok)"
    fi
  done <<< "$WTLIST"

  [ "$APPLY" = 1 ] && git -C "$MAIN" worktree prune 2>/dev/null || true
  # Best-effort husk sweep of empty sibling dirs next to the main checkout.
  if [ "$APPLY" = 1 ]; then
    local PARENT; PARENT=$(dirname "$TOPLEVEL")
    for d in "$PARENT"/*/; do
      [ -d "$d" ] || continue
      [ -z "$(ls -A "$d" 2>/dev/null)" ] && rmdir "$d" 2>/dev/null || true
    done
  fi
  echo "### summary[$TOPLEVEL]: $( [ "$APPLY" = 1 ] && echo removed || echo would-remove )=$removed branch-deleted=$brdel skipped=$skipped"
}

# ---------------------------------------------------------------------------
# Self-test: synthetic repo with a merged-old, a dirty, an unmerged, and a
# recent worktree; assert only the merged-old one is selected (dry-run).
# ---------------------------------------------------------------------------
if [ "${RUN_SELF_TEST:-0}" = 1 ]; then
  set -e
  T=$(mktemp -d)
  cleanup() { rm -rf "$T" 2>/dev/null || true; }
  trap cleanup EXIT
  R="$T/repo"
  git init -q -b master "$R"; cd "$R"
  git config user.email t@example.com; git config user.name t
  # base commit, backdated 30d (this is the OLD ancestor commit)
  echo base > f.txt; git add f.txt
  GIT_AUTHOR_DATE="2026-01-01T00:00:00" GIT_COMMITTER_DATE="2026-01-01T00:00:00" git -c commit.gpgsign=false commit -qm base
  BASE=$(git rev-parse HEAD)
  # advance master with a recent second commit
  echo c2 >> f.txt; git add f.txt; git -c commit.gpgsign=false commit -qm c2

  # wt_merged: branch tip == BASE (strict ancestor of master) + old -> WOULD-REMOVE
  git worktree add -q "$T/wt_merged" -b feat-merged "$BASE" >/dev/null

  # wt_dirty: branch at BASE (old, ancestor=merged) + real uncommitted file
  # -> passes age & merged checks, SKIPPED specifically for being dirty
  git worktree add -q "$T/wt_dirty" -b feat-dirty "$BASE" >/dev/null
  echo realwork > "$T/wt_dirty/important.txt"

  # wt_unmerged: unique commit not in master, old -> SKIP
  git worktree add -q "$T/wt_unmerged" -b feat-unmerged master >/dev/null
  ( cd "$T/wt_unmerged"; echo uniq>u.txt; git add u.txt
    GIT_AUTHOR_DATE="2026-02-01T00:00:00" GIT_COMMITTER_DATE="2026-02-01T00:00:00" git -c commit.gpgsign=false commit -qm uniq )

  # wt_recent: tip == master (merged) but last commit is recent -> SKIP recent
  git worktree add -q "$T/wt_recent" -b feat-recent master >/dev/null

  OUT=$(bash "$SCRIPT_ABS" --repo "$R" --age-days 3 2>&1)
  echo "$OUT" | grep -q "WOULD-REMOVE  feat-merged" || { echo "SELFTEST FAIL: merged-old not selected"; echo "$OUT"; exit 3; }
  echo "$OUT" | grep -qE "SKIP  feat-dirty  — .*uncommitted" || { echo "SELFTEST FAIL: dirty not skipped for dirt reason"; echo "$OUT"; exit 3; }
  echo "$OUT" | grep -qE "SKIP  feat-unmerged  — unmerged" || { echo "SELFTEST FAIL: unmerged not skipped"; echo "$OUT"; exit 3; }
  echo "$OUT" | grep -q "SKIP  feat-recent" || { echo "SELFTEST FAIL: recent not skipped"; echo "$OUT"; exit 3; }
  echo "$OUT" | grep -q "would-remove=1 " || { echo "SELFTEST FAIL: expected exactly 1 would-remove"; echo "$OUT"; exit 3; }
  # apply mode actually removes it
  OUT2=$(bash "$SCRIPT_ABS" --repo "$R" --age-days 3 --apply 2>&1)
  echo "$OUT2" | grep -q "REMOVED  feat-merged" || { echo "SELFTEST FAIL: apply did not remove"; echo "$OUT2"; exit 3; }
  git -C "$R" worktree list --porcelain | grep -q "wt_merged" && { echo "SELFTEST FAIL: still registered after apply"; exit 3; }
  echo "SELFTEST PASS (dry-run selects only merged-old; apply removes it; dirty/unmerged/recent skipped)"
  exit 0
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
  CD=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "worktree-prune.sh: not in a git repo and no --repo given" >&2; exit 1; }
  CD=$(cd "$CD" 2>/dev/null && pwd)
  REPOS+=("$(dirname "$CD")")
fi

rc=0
for r in "${REPOS[@]}"; do
  prune_repo "$r" || rc=1
done
exit $rc
