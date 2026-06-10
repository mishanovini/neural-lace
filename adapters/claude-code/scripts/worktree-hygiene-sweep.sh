#!/usr/bin/env bash
# worktree-hygiene-sweep.sh — classify, report, and (with explicit approval) prune
# accumulated git worktrees. Originating incident: a downstream consumer repo
# accumulated 63 worktrees because parallel sessions never tore theirs down.
# This mechanism makes that accumulation visible-and-cleanable instead of silent.
#
# Usage:
#   worktree-hygiene-sweep.sh [repo ...]                 # REPORT ONLY (default)
#   worktree-hygiene-sweep.sh --prune [repo ...]         # prune SAFE-PRUNE entries
#                                                        #   (requires WORKTREE_SWEEP_APPROVE=1)
#   worktree-hygiene-sweep.sh --session-summary [repo ...]  # one line per repo when
#                                                        #   worktree count > 5
#   worktree-hygiene-sweep.sh --self-test                # scripted-scenario suite
#
# Repo selection: positional args are repo paths. With no args, all
# worktree-bearing repos under $HOME/claude-projects (depth <= 3) are discovered
# via `git worktree list` in each (repos with > 1 registered worktree).
#
# Classification (per registered worktree, primary ALWAYS skipped):
#   SAFE-PRUNE    = 0 unique patches (git cherry <base> <branch> has no '+' lines,
#                   base = origin/master | origin/main | master | main)
#                   AND 0 dirty files AND last commit older than N days
#                   (N default 7; env WORKTREE_SWEEP_AGE_DAYS).
#   HOLDS-CONTENT = anything else. NEVER touched by --prune.
#   Detached-HEAD, locked, missing-directory (prunable), and no-resolvable-base
#   worktrees are always HOLDS-CONTENT (never guess-prune).
#
# APPROVAL CHANNEL (Misha's standing order, 2026-06-09): nothing is deleted
# without his explicit approval. The env flag WORKTREE_SWEEP_APPROVE=1 IS that
# approval channel — --prune without it refuses (exit 3) and removes nothing.
# Removal uses `git worktree remove` (no --force) + `git branch -d` (NOT -D;
# -d refuses unmerged branches as a second, git-native guard). Every removal is
# logged to $WORKTREE_SWEEP_LOG (default ~/.claude/state/worktree-sweep.log).
#
# Stash census: per repo, `git stash list` count + ages are REPORTED ONLY.
# This script never drops stashes.
#
# Portability: Bash 3.2 (no associative arrays, no mapfile, no ${var,,}).
# Windows-safe: paths are parsed from `git worktree list --porcelain` by line
# prefix only — NEVER split on ':' (drive-colon paths like C:/Users/... are a
# known footgun).
#
# Exit codes: 0 ok; 2 usage error; 3 --prune without WORKTREE_SWEEP_APPROVE=1;
#             1 self-test failure.

set -u

AGE_DAYS="${WORKTREE_SWEEP_AGE_DAYS:-7}"
SWEEP_LOG="${WORKTREE_SWEEP_LOG:-$HOME/.claude/state/worktree-sweep.log}"
NOW_TS="$(date +%s)"

# ---------------------------------------------------------------- helpers ---

# Emit "path<TAB>branch<TAB>flags" per registered worktree (flags: detached,
# bare, locked, prunable, comma-joined; "-" if none; branch "-" if none).
# First emitted line is the primary worktree. Tab-delimited so drive-colon
# Windows paths are never split.
list_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() {
      if (path != "") {
        if (flags == "") flags = "-"
        if (branch == "") branch = "-"
        printf "%s\t%s\t%s\n", path, branch, flags
      }
      path = ""; branch = ""; flags = ""
    }
    /^worktree /  { flush(); path = substr($0, 10) }
    /^branch /    { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    /^detached$/  { flags = flags (flags == "" ? "" : ",") "detached" }
    /^bare$/      { flags = flags (flags == "" ? "" : ",") "bare" }
    /^locked/     { flags = flags (flags == "" ? "" : ",") "locked" }
    /^prunable/   { flags = flags (flags == "" ? "" : ",") "prunable" }
    END { flush() }
  '
}

# Resolve the comparison base for unique-patch detection. Echoes ref or nothing.
resolve_base() {
  local repo="$1" ref
  for ref in origin/master origin/main master main; do
    if git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done
  return 1
}

# Classify one worktree. Sets globals: R_DIRTY R_UNIQUE R_AGE R_CLASS R_NOTE
classify_worktree() {
  local repo="$1" wt_path="$2" branch="$3" flags="$4" base="$5"
  R_DIRTY="?"; R_UNIQUE="?"; R_AGE="?"; R_CLASS="HOLDS-CONTENT"; R_NOTE=""

  case ",$flags," in
    *,prunable,*)
      R_NOTE="stale-registration (dir missing)"; return 0 ;;
    *,locked,*)
      R_NOTE="locked"; return 0 ;;
    *,detached,*)
      R_NOTE="detached HEAD"; return 0 ;;
  esac

  if [ ! -d "$wt_path" ]; then
    R_NOTE="dir missing"; return 0
  fi

  # dirty count (tracked changes + untracked files)
  R_DIRTY="$(git -C "$wt_path" status --porcelain 2>/dev/null | grep -c . || true)"
  [ -n "$R_DIRTY" ] || R_DIRTY=0

  # last-commit age in days
  local ct
  ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null || true)"
  if [ -n "$ct" ]; then
    R_AGE=$(( (NOW_TS - ct) / 86400 ))
  fi

  if [ -z "$base" ]; then
    R_NOTE="no base ref (origin/master|main missing)"; return 0
  fi

  # unique patches vs base
  R_UNIQUE="$(git -C "$repo" cherry "$base" "refs/heads/$branch" 2>/dev/null | grep -c '^+' || true)"
  [ -n "$R_UNIQUE" ] || R_UNIQUE=0

  if [ "$R_UNIQUE" = "0" ] && [ "$R_DIRTY" = "0" ] && [ "$R_AGE" != "?" ] && [ "$R_AGE" -gt "$AGE_DAYS" ]; then
    R_CLASS="SAFE-PRUNE"
  fi
  return 0
}

# Print stash census for a repo (report-only — never drops stashes).
stash_census() {
  local repo="$1" count line ts age
  count="$(git -C "$repo" stash list 2>/dev/null | grep -c . || true)"
  [ -n "$count" ] || count=0
  echo "  Stashes: $count"
  if [ "$count" -gt 0 ]; then
    git -C "$repo" stash list --format='%gd%x09%ct%x09%gs' 2>/dev/null |
      while IFS="$(printf '\t')" read -r ref ts msg; do
        age=$(( (NOW_TS - ts) / 86400 ))
        echo "    $ref: ${age}d old — $msg"
      done
  fi
}

# Sweep one repo. $1=repo $2=mode(report|prune|summary)
# Writes classification rows to $ROWS_FILE as: class<TAB>path<TAB>branch
sweep_repo() {
  local repo="$1" mode="$2"
  local base wt_list primary_seen path branch flags
  local wt_count=0 safe_count=0

  base="$(resolve_base "$repo" || true)"

  wt_list="$(mktemp)"
  list_worktrees "$repo" > "$wt_list"
  : > "$ROWS_FILE"

  if [ "$mode" != "summary" ]; then
    echo ""
    echo "== repo: $repo (base: ${base:-NONE}, age threshold: ${AGE_DAYS}d) =="
    printf '  %-58s %-34s %5s %6s %6s  %s\n' "WORKTREE" "BRANCH" "DIRTY" "UNIQUE" "AGE_D" "CLASS"
  fi

  primary_seen=0
  while IFS="$(printf '\t')" read -r path branch flags; do
    [ -n "$path" ] || continue
    if [ "$primary_seen" = "0" ]; then
      primary_seen=1   # primary worktree: ALWAYS skipped, never classified/pruned
      continue
    fi
    wt_count=$(( wt_count + 1 ))
    classify_worktree "$repo" "$path" "$branch" "$flags" "$base"
    if [ "$R_CLASS" = "SAFE-PRUNE" ]; then
      safe_count=$(( safe_count + 1 ))
    fi
    printf '%s\t%s\t%s\n' "$R_CLASS" "$path" "$branch" >> "$ROWS_FILE"
    if [ "$mode" != "summary" ]; then
      local note_sfx=""
      [ -n "$R_NOTE" ] && note_sfx="  ($R_NOTE)"
      printf '  %-58s %-34s %5s %6s %6s  %s%s\n' "$path" "$branch" "$R_DIRTY" "$R_UNIQUE" "$R_AGE" "$R_CLASS" "$note_sfx"
    fi
  done < "$wt_list"
  rm -f "$wt_list"

  if [ "$mode" = "summary" ]; then
    if [ "$wt_count" -gt 5 ]; then
      echo "repo $repo: $wt_count worktrees, $safe_count safe-prune candidates — run worktree-hygiene-sweep.sh"
    fi
    return 0
  fi

  if [ "$wt_count" = "0" ]; then
    echo "  (no secondary worktrees)"
  else
    echo "  Total: $wt_count worktree(s), $safe_count SAFE-PRUNE candidate(s)"
  fi
  stash_census "$repo"

  if [ "$mode" = "prune" ]; then
    prune_safe "$repo"
  fi
  return 0
}

# Prune SAFE-PRUNE rows from $ROWS_FILE. Approval already checked in main.
prune_safe() {
  local repo="$1" class path branch ts
  while IFS="$(printf '\t')" read -r class path branch; do
    [ "$class" = "SAFE-PRUNE" ] || continue
    if git -C "$repo" worktree remove "$path" 2>/dev/null; then
      if [ "$branch" != "-" ]; then
        if ! git -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
          echo "  PRUNED worktree $path (branch $branch NOT deleted — branch -d refused; left in place)"
        else
          echo "  PRUNED worktree $path + branch $branch"
        fi
      else
        echo "  PRUNED worktree $path (no branch)"
      fi
      mkdir -p "$(dirname "$SWEEP_LOG")"
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "$ts repo=$repo removed worktree=$path branch=$branch" >> "$SWEEP_LOG"
    else
      echo "  SKIP $path — git worktree remove refused (state changed since classification?)"
    fi
  done < "$ROWS_FILE"
}

# Discover worktree-bearing repos under ~/claude-projects (depth <= 3),
# deduplicated by primary-worktree path.
discover_repos() {
  local seen gitdir repo primary count
  seen="$(mktemp)"
  find "$HOME/claude-projects" -maxdepth 3 -name .git \( -type d -o -type f \) 2>/dev/null |
    while read -r gitdir; do
      repo="$(dirname "$gitdir")"
      primary="$(list_worktrees "$repo" | head -1 | cut -f1)"
      [ -n "$primary" ] || continue
      if grep -Fxq "$primary" "$seen" 2>/dev/null; then continue; fi
      echo "$primary" >> "$seen"
      count="$(list_worktrees "$repo" | grep -c . || true)"
      if [ "$count" -gt 1 ]; then
        echo "$primary"
      fi
    done
  rm -f "$seen"
}

# -------------------------------------------------------------- self-test ---

self_test() {
  local T pass=0 fail=0 out rc past repo
  T="$(mktemp -d)"
  past=$(( $(date +%s) - 30 * 86400 ))
  repo="$T/repo"

  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" symbolic-ref HEAD refs/heads/master
  echo base > "$repo/f.txt"
  git -C "$repo" add f.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$repo" -c commit.gpgsign=false commit -qm "init (30d ago)"

  # wt-safe: at master tip, clean, 30d old -> SAFE-PRUNE
  git -C "$repo" worktree add -q "$T/wt-safe" -b wt-safe >/dev/null 2>&1
  # wt-dirty: at master tip, 30d old, but has an untracked file -> HOLDS-CONTENT
  git -C "$repo" worktree add -q "$T/wt-dirty" -b wt-dirty >/dev/null 2>&1
  echo scratch > "$T/wt-dirty/untracked.txt"
  # wt-unique: clean + old, but carries a unique patch -> HOLDS-CONTENT
  git -C "$repo" worktree add -q "$T/wt-unique" -b wt-unique >/dev/null 2>&1
  echo unique > "$T/wt-unique/u.txt"
  git -C "$T/wt-unique" add u.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$T/wt-unique" -c commit.gpgsign=false commit -qm "unique patch (30d ago)"

  assert() { # $1 desc, $2 condition result (0 = pass)
    if [ "$2" = "0" ]; then
      pass=$(( pass + 1 )); echo "  PASS: $1"
    else
      fail=$(( fail + 1 )); echo "  FAIL: $1"
    fi
  }

  echo "[self-test] scenario 1-3 + 6: report classification"
  out="$("$0" "$repo" 2>&1)"; rc=$?
  assert "report exits 0" "$rc"
  echo "$out" | grep 'wt-safe' | grep -q 'SAFE-PRUNE'
  assert "safe-prune worktree detected (wt-safe -> SAFE-PRUNE)" "$?"
  echo "$out" | grep 'wt-dirty' | grep -q 'HOLDS-CONTENT'
  assert "dirty worktree NEVER classified safe (wt-dirty -> HOLDS-CONTENT)" "$?"
  echo "$out" | grep 'wt-unique' | grep -q 'HOLDS-CONTENT'
  assert "unique-patch worktree NEVER safe (wt-unique -> HOLDS-CONTENT)" "$?"
  # primary skip: exactly 3 classification rows (the 3 secondary worktrees)
  [ "$(echo "$out" | grep -c -E '(SAFE-PRUNE|HOLDS-CONTENT)$')" = "3" ]
  assert "primary worktree never listed as a classification row" "$?"

  echo "[self-test] scenario 4: --prune without WORKTREE_SWEEP_APPROVE=1 refuses"
  out="$(env -u WORKTREE_SWEEP_APPROVE "$0" --prune "$repo" 2>&1)"; rc=$?
  [ "$rc" = "3" ]
  assert "--prune without approval exits 3" "$?"
  [ -d "$T/wt-safe" ]
  assert "nothing removed without approval (wt-safe still present)" "$?"

  echo "[self-test] scenario 5: --prune with approval removes ONLY the safe one"
  out="$(WORKTREE_SWEEP_APPROVE=1 WORKTREE_SWEEP_LOG="$T/sweep.log" "$0" --prune "$repo" 2>&1)"; rc=$?
  assert "approved prune exits 0" "$rc"
  [ ! -d "$T/wt-safe" ]
  assert "SAFE-PRUNE worktree removed (wt-safe gone)" "$?"
  ! git -C "$repo" rev-parse --verify --quiet refs/heads/wt-safe >/dev/null 2>&1
  assert "SAFE-PRUNE branch deleted via branch -d (wt-safe ref gone)" "$?"
  [ -d "$T/wt-dirty" ] && [ -d "$T/wt-unique" ]
  assert "HOLDS-CONTENT worktrees untouched (wt-dirty + wt-unique remain)" "$?"
  git -C "$repo" rev-parse --verify --quiet refs/heads/wt-unique >/dev/null 2>&1
  assert "HOLDS-CONTENT branch untouched (wt-unique ref remains)" "$?"
  [ -d "$repo/.git" ] && [ -f "$repo/f.txt" ]
  assert "primary worktree never touched (repo + tracked file intact)" "$?"
  grep -q 'removed worktree=.*wt-safe' "$T/sweep.log" 2>/dev/null
  assert "removal logged to sweep log" "$?"

  echo "[self-test] bonus: --session-summary silent at <=5 worktrees"
  out="$("$0" --session-summary "$repo" 2>&1)"
  [ -z "$out" ]
  assert "--session-summary prints nothing for repo with <=5 worktrees" "$?"

  rm -rf "$T"
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  [ "$fail" = "0" ] && return 0 || return 1
}

# ------------------------------------------------------------------- main ---

MODE="report"
REPOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prune)           MODE="prune" ;;
    --session-summary) MODE="summary" ;;
    --self-test)       self_test; exit $? ;;
    --help|-h)         sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)                echo "unknown flag: $1" >&2; exit 2 ;;
    *)                 REPOS="$REPOS
$1" ;;
  esac
  shift
done

if [ "$MODE" = "prune" ] && [ "${WORKTREE_SWEEP_APPROVE:-0}" != "1" ]; then
  echo "REFUSING --prune: WORKTREE_SWEEP_APPROVE=1 is not set." >&2
  echo "Per standing order, nothing is deleted without explicit operator approval;" >&2
  echo "the WORKTREE_SWEEP_APPROVE=1 env flag is that approval channel." >&2
  exit 3
fi

if [ -z "$(echo "$REPOS" | tr -d '[:space:]')" ]; then
  REPOS="$(discover_repos)"
  if [ -z "$REPOS" ]; then
    echo "no worktree-bearing repos found under $HOME/claude-projects" >&2
    exit 0
  fi
fi

ROWS_FILE="$(mktemp)"
trap 'rm -f "$ROWS_FILE"' EXIT

echo "$REPOS" | grep -v '^$' | while read -r repo; do
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "skip: $repo is not a git repo" >&2
    continue
  fi
  sweep_repo "$repo" "$MODE"
done

exit 0
