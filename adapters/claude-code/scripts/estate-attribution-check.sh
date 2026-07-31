#!/usr/bin/env bash
# estate-attribution-check.sh — T4's outcome-metric tool: derives "zero
# unattributable worktrees/branches older than 48h" (accountable-estate
# program, docs/plans/accountable-estate-program-2026-07.md T4).
#
# design docs/designs/accountable-estate-2026-07-27.md §6c: "branches/
# worktrees are REGISTERED at creation ... and de-registered by the closer.
# Anything existing without a ledger link is definitionally unattributable
# -> janitor flags it." This script IS that derivation: for every registered
# git worktree (primary always skipped), it joins two facts —
#   1. AGE: hours since the worktree's branch last committed (git log -1
#      --format=%ct on the branch ref; falls back to the worktree directory's
#      own mtime if the branch ref cannot be resolved, e.g. detached HEAD).
#   2. ATTRIBUTION: does hooks/lib/estate-registration-lib.sh have ANY record
#      (open OR closed — see reg_has_any_record) for this slug?
# A worktree with age >= the threshold (default 48h) AND no record at all is
# UNATTRIBUTABLE — the metric this program's T4 slice exists to make zero,
# going forward. Pre-existing worktrees created before this mechanism landed
# will still show up here; that is expected and is named as pre-existing
# debt in this program's evidence, not silently hidden by this tool.
#
# This is deliberately NOT a re-implementation of worktree-hygiene-sweep.sh's
# --stranded liveness heuristic (heartbeat/claim/agent-transcript joins). That
# tool answers "is anyone actively working on this worktree right now" —
# useful for --prune safety, but a DIFFERENT question from "do we have a
# record of who created it." A worktree can be live-owned (someone's actively
# in it) AND unattributable (never registered, e.g. created via the native
# `claude --worktree` flag or a bare `git worktree add`) at the same time;
# both facts matter, and conflating them would either hide real attribution
# gaps behind "someone's active" or falsely flag active work as abandoned.
# Run worktree-hygiene-sweep.sh --stranded for the liveness question; run
# this for the attribution question. Same underlying `git worktree list`
# walk, asked two different things.
#
# Usage:
#   estate-attribution-check.sh [--repo <path> ...] [--age-hours N] [--porcelain]
#   estate-attribution-check.sh --self-test
#   estate-attribution-check.sh --help
#
# Options:
#   --repo <path>     a repo to check (repeatable). Default: the current
#                     checkout's main worktree (discovered from cwd).
#   --age-hours N     age threshold in hours (default 48, matching the
#                     outcome metric's own wording).
#   --porcelain       TAB-delimited rows, no header/narration, for machine
#                     consumers (mirrors worktree-hygiene-sweep.sh --stranded
#                     --porcelain's contract).
#
# Exit codes: 0 always (informational tool; a repo that fails to resolve is
# reported to stderr and skipped, never a hard failure) except 2 for a usage
# error and 3 for --self-test failure.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
AGE_HOURS_THRESHOLD=48
PORCELAIN=0
REPOS=()

usage() { sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) shift; [ $# -gt 0 ] || { echo "estate-attribution-check.sh: --repo needs a path" >&2; exit 2; }; REPOS+=("$1") ;;
    --age-hours) shift; [ $# -gt 0 ] || { echo "estate-attribution-check.sh: --age-hours needs a value" >&2; exit 2; }; AGE_HOURS_THRESHOLD="$1" ;;
    --porcelain) PORCELAIN=1 ;;
    --self-test) RUN_SELF_TEST=1 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "estate-attribution-check.sh: unknown flag: $1" >&2; exit 2 ;;
    *) REPOS+=("$1") ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# list_worktrees <repo> — "path<TAB>branch" per registered worktree, primary
# first. Duplicated from worktree-hygiene-sweep.sh's own function (same
# porcelain-parsing idiom: never split on ':' — Windows drive-colon paths).
# ---------------------------------------------------------------------------
list_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() {
      if (path != "") {
        if (branch == "") branch = "-"
        printf "%s\t%s\n", path, branch
      }
      path = ""; branch = ""
    }
    /^worktree /  { flush(); path = substr($0, 10) }
    /^branch /    { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    END { flush() }
  '
}

# age_hours_of <repo> <path> <branch> — hours since last commit on <branch>,
# falling back to the worktree directory's own mtime if the branch ref does
# not resolve (detached HEAD or a branch name list_worktrees could not read).
age_hours_of() {
  local repo="$1" path="$2" branch="$3" now ct mtime
  now="$(date -u +%s 2>/dev/null || echo 0)"
  if [ "$branch" != "-" ] && ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null)" && [ -n "$ct" ]; then
    echo $(( (now - ct) / 3600 ))
    return 0
  fi
  if [ -d "$path" ]; then
    mtime="$(git -C "$repo" log -1 --format=%ct 2>/dev/null)"   # last resort: repo HEAD time, if even that fails use dir mtime
    if [ -z "$mtime" ]; then
      mtime="$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null || echo "$now")"
    fi
    echo $(( (now - mtime) / 3600 ))
    return 0
  fi
  echo 0
}

check_repo() {
  local repo="$1"
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "estate-attribution-check.sh: skip: $repo is not a git repo" >&2
    return 0
  fi

  local hooks_dir="$SCRIPT_DIR/../hooks"
  # shellcheck disable=SC1091
  source "$hooks_dir/lib/estate-registration-lib.sh" 2>/dev/null || true

  local wt_list; wt_list="$(mktemp)"
  list_worktrees "$repo" > "$wt_list"

  local primary_seen=0 path branch
  while IFS="$(printf '\t')" read -r path branch; do
    [ -n "$path" ] || continue
    if [ "$primary_seen" = "0" ]; then primary_seen=1; continue; fi   # primary never counted

    local slug; slug="$(basename "$path")"
    local age_h; age_h="$(age_hours_of "$repo" "$path" "$branch")"
    local attributed=0
    if declare -F reg_has_any_record >/dev/null 2>&1 && reg_has_any_record "$slug"; then
      attributed=1
    fi

    if [ "$attributed" = "0" ] && [ "$age_h" -ge "$AGE_HOURS_THRESHOLD" ] 2>/dev/null; then
      if [ "$PORCELAIN" = "1" ]; then
        printf 'UNATTRIBUTABLE\t%s\t%s\t%s\t%s\n' "$repo" "$path" "$branch" "$age_h"
      else
        printf '  UNATTRIBUTABLE  %-58s  branch %-30s  age %sh (no registration record: open or closed)\n' "$path" "$branch" "$age_h"
      fi
      UNATTR_COUNT=$(( UNATTR_COUNT + 1 ))
    fi
  done < "$wt_list"
  rm -f "$wt_list"
  return 0
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
self_test() {
  local pass=0 fail=0
  assert() { if [ "$2" = "0" ]; then pass=$((pass+1)); echo "  PASS: $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }

  local T; T="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp"; return 1; }
  export HARNESS_SELFTEST=1
  export REG_STATE_DIR="$T/estate"

  local repo="$T/repo"
  git init -q -b master "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  echo base > "$repo/f.txt"; git -C "$repo" add f.txt
  git -C "$repo" -c commit.gpgsign=false commit -qm base

  local past; past=$(( $(date -u +%s) - 3 * 86400 ))   # 3 days ago (>= 48h)

  # wt-old-unregistered: 3 days old, NO registration -> UNATTRIBUTABLE
  git -C "$repo" worktree add -q "$T/wt-old-unreg" -b wt-old-unreg >/dev/null 2>&1
  echo x > "$T/wt-old-unreg/x.txt"; git -C "$T/wt-old-unreg" add x.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$T/wt-old-unreg" -c commit.gpgsign=false commit -qm "old, unregistered"

  # wt-fresh-unregistered: brand new (now), NO registration -> NOT flagged (too young)
  git -C "$repo" worktree add -q "$T/wt-fresh-unreg" -b wt-fresh-unreg >/dev/null 2>&1
  echo x > "$T/wt-fresh-unreg/x.txt"; git -C "$T/wt-fresh-unreg" add x.txt
  git -C "$T/wt-fresh-unreg" -c commit.gpgsign=false commit -qm "fresh, unregistered"

  # wt-old-registered: 3 days old, HAS an open registration -> NOT flagged (attributed)
  git -C "$repo" worktree add -q "$T/wt-old-reg" -b wt-old-reg >/dev/null 2>&1
  echo x > "$T/wt-old-reg/x.txt"; git -C "$T/wt-old-reg" add x.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$T/wt-old-reg" -c commit.gpgsign=false commit -qm "old, registered"
  ( source "$SCRIPT_DIR/../hooks/lib/estate-registration-lib.sh" && reg_register wt-old-reg "$T/wt-old-reg" wt-old-reg plan=demo )

  # wt-old-closed: 3 days old, only a CLOSED registration on record -> NOT flagged (historical attribution still counts)
  git -C "$repo" worktree add -q "$T/wt-old-closed" -b wt-old-closed >/dev/null 2>&1
  echo x > "$T/wt-old-closed/x.txt"; git -C "$T/wt-old-closed" add x.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$T/wt-old-closed" -c commit.gpgsign=false commit -qm "old, closed record"
  ( source "$SCRIPT_DIR/../hooks/lib/estate-registration-lib.sh" && reg_register wt-old-closed "$T/wt-old-closed" wt-old-closed && reg_close wt-old-closed disposed )

  echo "Scenario 1: human report flags exactly the old+unregistered worktree"
  local out; out="$("${BASH:-bash}" "$SCRIPT_DIR/estate-attribution-check.sh" --repo "$repo" 2>&1)"
  echo "$out" | grep -q "wt-old-unreg" ; assert "old unregistered worktree flagged UNATTRIBUTABLE" "$?"
  echo "$out" | grep -q "wt-fresh-unreg" && fail=$((fail+1)) && echo "  FAIL: fresh unregistered worktree should NOT be flagged (too young)" \
    || { pass=$((pass+1)); echo "  PASS: fresh unregistered worktree NOT flagged (under the 48h threshold)"; }
  echo "$out" | grep -q "wt-old-reg\b" && fail=$((fail+1)) && echo "  FAIL: openly-registered old worktree should NOT be flagged" \
    || { pass=$((pass+1)); echo "  PASS: openly-registered old worktree NOT flagged (attributed)"; }
  echo "$out" | grep -q "wt-old-closed" && fail=$((fail+1)) && echo "  FAIL: worktree with a CLOSED record should NOT be flagged" \
    || { pass=$((pass+1)); echo "  PASS: worktree with only a CLOSED record NOT flagged (historical attribution counts)"; }

  echo "Scenario 2: --porcelain emits exactly one UNATTRIBUTABLE row, tab-delimited"
  out="$("${BASH:-bash}" "$SCRIPT_DIR/estate-attribution-check.sh" --repo "$repo" --porcelain 2>&1)"
  local n; n="$(printf '%s\n' "$out" | grep -c '^UNATTRIBUTABLE' || true)"
  [ "$n" = "1" ]; assert "exactly 1 porcelain UNATTRIBUTABLE row" "$?"
  printf '%s\n' "$out" | grep -q "^UNATTRIBUTABLE"$'\t'"$repo"$'\t'; assert "porcelain row carries the repo path in column 2" "$?"

  echo "Scenario 3: --age-hours override changes the threshold"
  out="$("${BASH:-bash}" "$SCRIPT_DIR/estate-attribution-check.sh" --repo "$repo" --age-hours 1000 2>&1)"
  echo "$out" | grep -q "wt-old-unreg" && fail=$((fail+1)) && echo "  FAIL: a 1000h threshold should exclude a 72h-old worktree" \
    || { pass=$((pass+1)); echo "  PASS: raising --age-hours above the fixture's actual age excludes it"; }

  echo "Scenario 4: primary worktree is never a row, even unregistered and ancient"
  # column 2 is ALWAYS the repo path (every row for this repo carries it), so
  # the discriminating check is column 3 (the worktree's OWN path) equalling
  # the repo path — that combination is unique to the primary.
  out="$("${BASH:-bash}" "$SCRIPT_DIR/estate-attribution-check.sh" --repo "$repo" --porcelain --age-hours 0 2>&1)"
  printf '%s\n' "$out" | grep -qF "UNATTRIBUTABLE"$'\t'"$repo"$'\t'"$repo"$'\t' \
    && fail=$((fail+1)) && echo "  FAIL: primary checkout itself appeared as a row (path == repo)" \
    || { pass=$((pass+1)); echo "  PASS: primary checkout never appears as its own row"; }

  echo "Scenario 5: a non-git repo path is skipped, not a hard failure (exit 0)"
  "${BASH:-bash}" "$SCRIPT_DIR/estate-attribution-check.sh" --repo "$T/not-a-repo" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "0" ]; assert "non-repo path skipped, exit 0" "$?"

  rm -rf "$T"
  echo
  echo "self-test summary: $pass passed, $fail failed"
  [ "$fail" = "0" ] && { echo "self-test: OK"; return 0; }
  return 1
}

if [ "${RUN_SELF_TEST:-0}" = "1" ]; then
  self_test; exit $?
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
  DEFAULT_REPO="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)"
  REPOS=("$DEFAULT_REPO")
fi

UNATTR_COUNT=0
for r in "${REPOS[@]}"; do
  [ "$PORCELAIN" = "1" ] || echo "== repo: $r (age threshold: ${AGE_HOURS_THRESHOLD}h) =="
  check_repo "$r"
done

if [ "$PORCELAIN" != "1" ]; then
  if [ "$UNATTR_COUNT" -eq 0 ]; then
    echo "  zero unattributable worktrees older than ${AGE_HOURS_THRESHOLD}h"
  else
    echo "  $UNATTR_COUNT unattributable worktree(s) older than ${AGE_HOURS_THRESHOLD}h"
  fi
fi
exit 0
