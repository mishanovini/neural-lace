#!/usr/bin/env bash
# spawn-worktree.sh
#
# Decision-aware worktree primitive for parallel Claude Code sessions.
#
# The problem it solves (PROVEN — see docs/conventions/worktree-per-session.md
# "Why isolation is needed"): a git working tree has exactly ONE HEAD. `git
# checkout` and `git commit` mutate that single shared HEAD. When two or more
# sessions share one working tree (e.g. the main checkout), they race on HEAD:
# session A's `git checkout branch-A` flips the shared HEAD, and if session B
# then commits, B's commit lands on branch-A — NOT B's intended branch. This
# was observed on 2026-05-26 (a session-wrap fix commit landed on a sibling's
# `pattern-3-file-lifecycle-plan` branch) and is reproduced deterministically in
# --self-test. A worktree gives each session its OWN HEAD, so the race vanishes.
#
# This script is the IN-OUR-CONTROL spawn half (the cleanup half is
# worktree-prune.sh). It does two things:
#   1. DECIDES whether a session needs an isolated worktree, from the session
#      type + concurrency context (the decision matrix below).
#   2. If needed, CREATES a predictably-named worktree on a clean base and
#      prints the absolute cwd the session should `cd` into.
#
# Native alternatives (documented, complementary — NOT replaced by this script):
#   - `claude --worktree <name>` (CLI launch flag) — creates .claude/worktrees/
#     <name> on branch worktree-<name> at launch time.
#   - the `EnterWorktree` tool — relocates an already-running session mid-turn.
#   - the desktop app auto-isolates every "+ New session" per code task.
# This script's added value over those: a scriptable DECISION layer (skip
# isolation for read-only work), explicit branch naming aligned to a session
# slug, an explicit base ref, idempotent re-runs, and an "already-isolated"
# short-circuit so a session that is already in a worktree is never re-nested.
#
# ── Decision matrix (session type x concurrency) ───────────────────────────
#   read-only        : never isolate (no HEAD/index mutation)
#   writes           : isolate when concurrency is possible (file race under
#                      uncommitted edits); optional when provably alone
#   commits          : isolate (sibling checkout flips HEAD -> wrong-branch commit)
#   branch-switch    : isolate (the canonical proven failure)
#   destructive      : isolate (reset/rebase/clean can wipe a sibling's work)
# "Alone on the repo" is safe in theory but UNPROVABLE (sessions can't see each
# other), so the operational rule collapses to: isolate iff the session will
# mutate git state, or write files when concurrency is possible. The default
# --type is `commits` (conservative: assume the session will write git state).
#
# ── Usage ──────────────────────────────────────────────────────────────────
#   spawn-worktree.sh <slug> [options]        # decide + (dry-run) plan
#   spawn-worktree.sh <slug> --apply          # decide + create if needed
#   spawn-worktree.sh <slug> --apply --print-cd   # print ONLY the cwd on stdout
#   spawn-worktree.sh --remove <slug> [--force]   # tear down one worktree
#   spawn-worktree.sh --self-test
#
# Options:
#   --type <read-only|writes|commits|branch-switch|destructive>
#                         session type for the decision (default: commits)
#   --concurrent <yes|no|unknown>
#                         is another session likely sharing this repo?
#                         (default: unknown, treated as yes)
#   --base <ref>          base ref for a new worktree
#                         (default: origin/HEAD, fallback local HEAD —
#                          matches the native --worktree "clean tree" default)
#   --branch <name>       branch name for the new worktree
#                         (default: <slug> if it contains '/', else session/<slug>)
#   --repo <path>         main checkout to operate on
#                         (default: discovered from cwd)
#   --apply               actually create (default is dry-run / decide-only)
#   --print-cd            print ONLY the absolute cwd to stdout (for `cd "$(...)"`)
#   --remove <slug>       remove the worktree for <slug> (clean-only unless --force)
#   --force               with --remove: remove even with uncommitted changes
#   --quiet               suppress the human-readable decision narration
#
# Exit codes:
#   0  ran ok (decision emitted; dry-run or apply or remove)
#   1  --repo / cwd is not a usable git repo
#   2  usage error (bad flag / missing value)
#   3  --self-test failure
#
# Windows note (same as worktree-prune.sh): `git worktree remove` may leave an
# empty leaf dir whose final rmdir fails with "Permission denied" because a
# file handle is held transiently. De-registration is the success criterion;
# the husk is harmless and best-effort rmdir'd.
set -u

# Absolute path to this script, captured BEFORE any cd (the self-test cds into
# a temp repo and re-invokes $0; a relative $0 would not resolve).
SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

SLUG=""
TYPE="commits"
CONCURRENT="unknown"
BASE=""
BRANCH=""
REPO=""
APPLY=0
PRINT_CD=0
QUIET=0
REMOVE_SLUG=""
FORCE=0
RUN_SELF_TEST=0

die_usage() { echo "spawn-worktree.sh: $1" >&2; echo "see header for usage" >&2; exit 2; }
log() { [ "$QUIET" = 1 ] || echo "$@" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --type) shift; [ $# -gt 0 ] || die_usage "--type needs a value"; TYPE="$1" ;;
    --concurrent) shift; [ $# -gt 0 ] || die_usage "--concurrent needs a value"; CONCURRENT="$1" ;;
    --base) shift; [ $# -gt 0 ] || die_usage "--base needs a value"; BASE="$1" ;;
    --branch) shift; [ $# -gt 0 ] || die_usage "--branch needs a value"; BRANCH="$1" ;;
    --repo) shift; [ $# -gt 0 ] || die_usage "--repo needs a path"; REPO="$1" ;;
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --print-cd) PRINT_CD=1 ;;
    --quiet) QUIET=1 ;;
    --remove) shift; [ $# -gt 0 ] || die_usage "--remove needs a slug"; REMOVE_SLUG="$1" ;;
    --force) FORCE=1 ;;
    --self-test) RUN_SELF_TEST=1 ;;
    -h|--help) sed -n '2,75p' "$0"; exit 0 ;;
    -*) die_usage "unknown argument: $1" ;;
    *) [ -z "$SLUG" ] && SLUG="$1" || die_usage "unexpected argument: $1" ;;
  esac
  shift
done

case "$TYPE" in
  read-only|writes|commits|branch-switch|destructive) : ;;
  *) die_usage "--type must be one of: read-only writes commits branch-switch destructive" ;;
esac
case "$CONCURRENT" in yes|no|unknown) : ;; *) die_usage "--concurrent must be yes|no|unknown" ;; esac

# slug sanitiser: kebab/ASCII; strip anything but [a-zA-Z0-9._/-]; collapse.
sanitise_slug() { printf '%s' "$1" | tr ' ' '-' | sed 's/[^a-zA-Z0-9._/-]//g; s#//*#/#g; s/^-*//; s/-*$//'; }

# Resolve the main checkout of a repo path (NOT a worktree leaf).
# Echoes the main-checkout toplevel, or empty on failure.
main_checkout_of() {
  local start="$1" cd_common
  cd_common=$(git -C "$start" rev-parse --git-common-dir 2>/dev/null) || { echo ""; return 1; }
  # --git-common-dir is the shared .git (main checkout's .git). Its dirname is
  # the main checkout toplevel. Make absolute (it may be relative to start).
  case "$cd_common" in
    /*|[A-Za-z]:*) : ;;                       # already absolute (posix or win)
    *) cd_common="$start/$cd_common" ;;
  esac
  # Emit git's CANONICAL path form (what `git worktree list` and
  # `--show-toplevel` use) so string compares against git output match. On
  # Git-for-Windows that is C:/... form; on POSIX it is the normal absolute path.
  local maindir; maindir=$(dirname "$cd_common")
  git -C "$maindir" rev-parse --show-toplevel 2>/dev/null || ( cd "$maindir" 2>/dev/null && pwd )
}

# Resolve a usable base ref for a new worktree on the given main checkout.
resolve_base() {
  local main="$1"
  if [ -n "$BASE" ]; then echo "$BASE"; return; fi
  # Prefer the remote default branch (clean tree matching remote), like the
  # native --worktree default. Fall back through common names to local HEAD.
  if git -C "$main" rev-parse --verify -q origin/HEAD >/dev/null 2>&1; then echo origin/HEAD
  elif git -C "$main" rev-parse --verify -q origin/master >/dev/null 2>&1; then echo origin/master
  elif git -C "$main" rev-parse --verify -q origin/main >/dev/null 2>&1; then echo origin/main
  else echo HEAD; fi
}

# Is isolation needed for (type, concurrent)? Sets globals NEED and REASON in
# the CURRENT shell (NOT via $() — a subshell would lose the REASON assignment).
NEED=""
REASON=""
decide() {
  local t="$1" c="$2"
  case "$t" in
    read-only)
      NEED=no; REASON="read-only session mutates no HEAD/index; isolation is pure overhead" ;;
    writes)
      if [ "$c" = no ]; then
        NEED=no; REASON="writes-files-only and provably alone; isolation optional"
      else
        NEED=yes; REASON="writes files; a sibling checkout can swap files under uncommitted edits"
      fi ;;
    commits)
      if [ "$c" = no ]; then
        NEED=no; REASON="commits but provably alone; safe in the main checkout (but alone-ness is rarely provable)"
      else
        NEED=yes; REASON="commits: a sibling checkout flips the shared HEAD -> commit lands on the wrong branch"
      fi ;;
    branch-switch)
      NEED=yes; REASON="branch-switching: the canonical shared-HEAD collision (proven 2026-05-26)" ;;
    destructive)
      NEED=yes; REASON="destructive git ops (reset/rebase/clean) can wipe a sibling's uncommitted work" ;;
  esac
}

# ── --remove path ──────────────────────────────────────────────────────────
remove_worktree() {
  local main="$1" slug="$2"
  local wt="$main/.claude/worktrees/$slug"
  if ! git -C "$main" worktree list --porcelain | grep -qxF "worktree $wt"; then
    log "spawn-worktree.sh: no registered worktree at $wt"
    return 0
  fi
  local dc
  dc=$(git -C "$wt" status --porcelain 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$dc" != 0 ] && [ "$FORCE" != 1 ]; then
    log "spawn-worktree.sh: $wt has $dc uncommitted change(s); re-run with --force to remove anyway"
    return 1
  fi
  # Capture the branch the worktree was on BEFORE removing it, so we can
  # safe-delete it afterwards.
  local br; br=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo "")
  git -C "$main" worktree remove --force "$wt" >/dev/null 2>&1
  rmdir "$wt" 2>/dev/null || true
  if git -C "$main" worktree list --porcelain | grep -qxF "worktree $wt"; then
    log "spawn-worktree.sh: FAILED to de-register $wt"; return 1
  fi
  log "spawn-worktree.sh: removed worktree $wt"
  # Safe-delete the branch: `-d` (never `-D`) only succeeds if the branch is
  # merged, so unique unmerged work is never lost. A leftover unmerged branch
  # is left in place and reported.
  if [ -n "$br" ]; then
    if git -C "$main" branch -d "$br" >/dev/null 2>&1; then
      log "spawn-worktree.sh: deleted merged branch $br"
    else
      log "spawn-worktree.sh: kept branch $br (has unmerged commits — delete manually with 'git branch -D $br' if intended)"
    fi
  fi
  return 0
}

# ── Self-test ───────────────────────────────────────────────────────────────
if [ "$RUN_SELF_TEST" = 1 ]; then
  set -e
  T=$(mktemp -d); trap 'rm -rf "$T" 2>/dev/null || true' EXIT
  R="$T/repo"; git init -q -b master "$R"; cd "$R"
  R=$(git rev-parse --show-toplevel)   # canonical git form the script emits
  git config user.email t@example.com; git config user.name t
  echo base > f.txt; git add f.txt; git -c commit.gpgsign=false commit -qm base
  fail() { echo "SELFTEST FAIL: $1"; echo "---"; echo "$2"; exit 3; }

  # 1. read-only -> NO isolation, exits 0, prints the main checkout as cwd
  OUT=$(bash "$SCRIPT_ABS" investigate-x --type read-only --repo "$R" --print-cd 2>/dev/null)
  [ "$OUT" = "$R" ] || fail "read-only should print main checkout as cwd" "$OUT"

  # 2. commits + concurrent unknown -> isolation NEEDED, dry-run plans, creates nothing
  OUT=$(bash "$SCRIPT_ABS" fix-thing --type commits --repo "$R" 2>&1)
  echo "$OUT" | grep -q "DECISION: isolate" || fail "commits should decide isolate" "$OUT"
  echo "$OUT" | grep -q "reason: .*wrong branch" || fail "reason text must render (not be empty)" "$OUT"
  echo "$OUT" | grep -q "WOULD-CREATE" || fail "dry-run should say WOULD-CREATE" "$OUT"
  git -C "$R" worktree list --porcelain | grep -q "fix-thing" && fail "dry-run must not create a worktree" "$OUT"

  # 3. commits + concurrent no -> NO isolation
  OUT=$(bash "$SCRIPT_ABS" solo --type commits --concurrent no --repo "$R" 2>&1)
  echo "$OUT" | grep -q "DECISION: no-isolation" || fail "commits+alone should be no-isolation" "$OUT"

  # 4. branch-switch + --apply -> CREATES worktree on session/<slug> from base
  OUT=$(bash "$SCRIPT_ABS" build-feature --type branch-switch --repo "$R" --apply --print-cd 2>/dev/null)
  [ -d "$R/.claude/worktrees/build-feature" ] || fail "apply should create the worktree dir" "$OUT"
  git -C "$R" worktree list --porcelain | grep -q "build-feature" || fail "apply should register the worktree" "$OUT"
  WB=$(git -C "$R/.claude/worktrees/build-feature" symbolic-ref --short HEAD)
  [ "$WB" = "session/build-feature" ] || fail "default branch should be session/<slug>, got $WB" "$WB"
  [ "$OUT" = "$R/.claude/worktrees/build-feature" ] || fail "--print-cd should print the worktree path" "$OUT"

  # 5. idempotent: re-apply same slug reuses (no error), prints same cwd
  OUT=$(bash "$SCRIPT_ABS" build-feature --type branch-switch --repo "$R" --apply --print-cd 2>/dev/null)
  [ "$OUT" = "$R/.claude/worktrees/build-feature" ] || fail "re-apply should reuse + print same cwd" "$OUT"

  # 6. already-isolated short-circuit: invoke from INSIDE a worktree
  OUT=$(cd "$R/.claude/worktrees/build-feature" && bash "$SCRIPT_ABS" other --type commits --print-cd 2>/dev/null)
  [ "$OUT" = "$R/.claude/worktrees/build-feature" ] || fail "inside a worktree should short-circuit to cwd" "$OUT"

  # 7. --branch override
  OUT=$(bash "$SCRIPT_ABS" custom --type commits --branch feat/my-custom --repo "$R" --apply --print-cd 2>/dev/null)
  CB=$(git -C "$R/.claude/worktrees/custom" symbolic-ref --short HEAD)
  [ "$CB" = "feat/my-custom" ] || fail "--branch override should set branch, got $CB" "$CB"

  # 8. --remove tears it down
  bash "$SCRIPT_ABS" --remove custom --repo "$R" --quiet 2>/dev/null
  git -C "$R" worktree list --porcelain | grep -q "worktrees/custom" && fail "--remove should de-register" "" || true

  # 9. bad --type is a usage error (exit 2)
  if bash "$SCRIPT_ABS" x --type bogus --repo "$R" >/dev/null 2>&1; then fail "bad --type should exit non-zero" ""; fi

  echo "SELFTEST PASS (read-only skips; commits+unknown isolate; commits+alone skip; apply creates session/<slug>; idempotent reuse; already-isolated short-circuit; --branch override; --remove; bad-type rejected)"
  exit 0
fi

# ── Main path ────────────────────────────────────────────────────────────────
START="${REPO:-$(pwd)}"
MAIN=$(main_checkout_of "$START")
[ -n "$MAIN" ] || { echo "spawn-worktree.sh: not a git repo: $START" >&2; exit 1; }

# --remove subcommand
if [ -n "$REMOVE_SLUG" ]; then
  remove_worktree "$MAIN" "$(sanitise_slug "$REMOVE_SLUG")"
  exit $?
fi

[ -n "$SLUG" ] || die_usage "a session <slug> is required (or use --remove <slug> / --self-test)"
SLUG=$(sanitise_slug "$SLUG")
[ -n "$SLUG" ] || die_usage "slug sanitised to empty; provide a kebab-case slug"

# Already inside a worktree (not the main checkout)? Short-circuit: never nest.
CUR_TOP=$(git -C "$START" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$CUR_TOP" ] && [ "$CUR_TOP" != "$MAIN" ]; then
  log "DECISION: already-isolated — current working tree ($CUR_TOP) is a worktree, not the main checkout; not nesting"
  [ "$PRINT_CD" = 1 ] && echo "$CUR_TOP"
  exit 0
fi

decide "$TYPE" "$CONCURRENT"
WT="$MAIN/.claude/worktrees/$SLUG"
[ -n "$BRANCH" ] || case "$SLUG" in */*) BRANCH="$SLUG" ;; *) BRANCH="session/$SLUG" ;; esac
BASE_REF=$(resolve_base "$MAIN")

if [ "$NEED" = no ]; then
  log "DECISION: no-isolation (type=$TYPE, concurrent=$CONCURRENT)"
  log "  reason: $REASON"
  log "  use the main checkout as your cwd: $MAIN"
  [ "$PRINT_CD" = 1 ] && echo "$MAIN"
  exit 0
fi

log "DECISION: isolate (type=$TYPE, concurrent=$CONCURRENT)"
log "  reason: $REASON"

# Idempotent reuse: if the worktree path is already registered, just use it.
if git -C "$MAIN" worktree list --porcelain | grep -qxF "worktree $WT"; then
  log "  worktree already exists at $WT — reusing"
  [ "$PRINT_CD" = 1 ] && echo "$WT"
  exit 0
fi

if [ "$APPLY" != 1 ]; then
  log "  WOULD-CREATE: git -C \"$MAIN\" worktree add \"$WT\" -b \"$BRANCH\" \"$BASE_REF\""
  log "  (dry-run — re-run with --apply to create. then: cd \"$WT\")"
  [ "$PRINT_CD" = 1 ] && echo "$WT"
  exit 0
fi

# Apply: create the worktree. If the branch name already exists, attach to it
# instead of -b (which would fail).
if git -C "$MAIN" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
  git -C "$MAIN" worktree add "$WT" "$BRANCH" >/dev/null 2>&1
else
  git -C "$MAIN" worktree add "$WT" -b "$BRANCH" "$BASE_REF" >/dev/null 2>&1
fi
if ! git -C "$MAIN" worktree list --porcelain | grep -qxF "worktree $WT"; then
  echo "spawn-worktree.sh: failed to create worktree at $WT (base=$BASE_REF, branch=$BRANCH)" >&2
  exit 1
fi
log "  CREATED: $WT  (branch $BRANCH from $BASE_REF)"
log "  cd into it: cd \"$WT\""
log "  at session end, tear down: spawn-worktree.sh --remove $SLUG   (or rely on worktree-prune.sh)"
[ "$PRINT_CD" = 1 ] && echo "$WT"
exit 0
