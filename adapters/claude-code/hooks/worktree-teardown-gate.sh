#!/bin/bash
# NEURAL-LACE-HOOK
# worktree-teardown-gate.sh — Stop hook.
#
# Prevents a session from ENDING inside a linked git worktree that holds
# UNPRESERVED work. "Unpreserved" = uncommitted changes (staged, unstaged,
# or untracked) — work that a later `git worktree remove --force` or
# `git clean` would destroy. The gate steers toward PRESERVE-FIRST
# (commit / stash / push), NEVER toward `--force` deletion: a worktree
# holding unmerged work is WANTED work, not trash (the "incomplete ≠
# abandoned" principle). This is the END side of worktree-isolation; the
# SessionStart companion (session-start-worktree-advisor.sh) handles start.
#
# SCOPE (edge case B2 — there is no reliable cross-session liveness
# signal): the gate considers ONLY the worktree the CURRENT session is in
# (its cwd). It NEVER enumerates or touches peer worktrees, so it cannot
# tell session A to disturb session B's live worktree (exemption A5).
# Consequence — a NAMED v1 limitation: a session that creates a worktree
# and then cd's back to the main checkout before ending ("failure mode 2")
# is not caught; closing that needs a `git worktree add` marker-writer,
# deliberately out of v1 scope.
#
# Behavior:
#   - cwd is the MAIN CHECKOUT (git-dir == git-common-dir) → no-op (B6:
#     the main checkout always carries bookkeeping churn and is never a
#     "worktree to tear down").
#   - cwd is not a git repo → no-op (A4).
#   - cwd worktree is git-LOCKED (.git/worktrees/<n>/locked exists) → no-op
#     (A5: intentionally persistent).
#   - cwd is a linked worktree with uncommitted changes → BLOCK toward
#     preserve-first (retry-guard + fresh-waiver escape hatch).
#   - cwd is a linked worktree, clean, but with unpushed commits → ADVISE
#     (non-blocking, exit 0): committed work survives `git worktree remove`
#     and only dies on `git branch -D` (governed by branch-hygiene), so a
#     hard block here would be high-false-positive (Decision D2).
#   - cwd is a clean, fully-preserved worktree → no-op (A1 read-only
#     sessions pass here for free).
#
# Escape hatch: a fresh .claude/state/worktree-teardown-waiver-*.txt
# (>=1 substantive line, <1h old) allows the stop (mirrors
# bug-persistence-gate.sh's attestation pattern).
#
# Exit codes: 0 = may terminate; 2 = blocked (stderr explains).
#
# Self-test: invoke with --self-test.

set -u

# ============================================================
# --self-test — exercise the gate against synthetic worktrees.
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  [[ -f "$SELF_TEST_HOOK" ]] || { echo "self-test: cannot resolve own path" >&2; exit 2; }

  PASSED=0; FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t wt-teardown)
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] || { echo "self-test: cannot create tempdir" >&2; exit 2; }
  trap 'rm -rf "$TMPROOT"' EXIT

  # Build a repo with a bare origin so unpushed/clean states are real.
  _build_repo() {
    local name="$1"
    local repo="$TMPROOT/$name"
    mkdir -p "$repo"
    (
      cd "$repo" || exit 99
      git init -q -b master 2>/dev/null || { git init -q; git checkout -q -b master 2>/dev/null; }
      git config user.email "t@example.com"; git config user.name "T"; git config commit.gpgsign false
      git config core.autocrlf false; git config core.safecrlf false
      echo seed > seed.txt; git add seed.txt; git commit -q -m seed
      git init -q --bare "$TMPROOT/$name-origin.git" 2>/dev/null
      git remote add origin "$TMPROOT/$name-origin.git"
      git push -q -u origin master 2>/dev/null
    )
    echo "$repo"
  }

  # Run the hook from within a given dir; echoes the exit code. Capture
  # files are written OUTSIDE the worktree — writing them into the cwd
  # would itself create untracked files and make the worktree "dirty".
  _run_in() {
    local dir="$1"
    (
      cd "$dir" || exit 99
      printf '{"session_id":"selftest-%s"}' "$(basename "$dir")" | bash "$SELF_TEST_HOOK" >"$TMPROOT/last-stdout.txt" 2>"$TMPROOT/last-stderr.txt"
      echo $?
    )
  }

  _check() {  # $1 label, $2 actual-rc, $3 expected-rc
    if [[ "$2" == "$3" ]]; then echo "self-test ($1): PASS (rc=$2)" >&2; PASSED=$((PASSED+1))
    else echo "self-test ($1): FAIL (rc=$2, expected $3)" >&2; cat "$TMPROOT/last-stderr.txt" 2>/dev/null >&2; FAILED=$((FAILED+1)); fi
  }

  # S1: main checkout, dirty → no-op (exit 0). Main checkout is never gated.
  R=$(_build_repo s1); ( cd "$R"; echo change >> seed.txt )
  RC=$(_run_in "$R"); _check "S1 main-checkout-dirty-noop" "$RC" "0" "$R"

  # S2: not a git repo → no-op (exit 0).
  mkdir -p "$TMPROOT/plain"
  RC=$(_run_in "$TMPROOT/plain"); _check "S2 non-git-noop" "$RC" "0" "$TMPROOT/plain"

  # S3: clean linked worktree, nothing unpushed → no-op (exit 0).
  R=$(_build_repo s3)
  ( cd "$R"; git worktree add -q "$TMPROOT/s3-wt" -b s3-feat master >/dev/null 2>&1; \
    cd "$TMPROOT/s3-wt"; git push -q -u origin s3-feat 2>/dev/null )
  RC=$(_run_in "$TMPROOT/s3-wt"); _check "S3 clean-worktree-pass" "$RC" "0" "$TMPROOT/s3-wt"

  # S4: linked worktree with UNCOMMITTED changes → BLOCK (exit 2).
  R=$(_build_repo s4)
  ( cd "$R"; git worktree add -q "$TMPROOT/s4-wt" -b s4-feat master >/dev/null 2>&1; \
    cd "$TMPROOT/s4-wt"; echo dirty >> seed.txt )
  RC=$(_run_in "$TMPROOT/s4-wt"); _check "S4 dirty-worktree-BLOCK" "$RC" "2" "$TMPROOT/s4-wt"

  # S5: linked worktree that is LOCKED, even if dirty → no-op (exit 0).
  R=$(_build_repo s5)
  ( cd "$R"; git worktree add -q "$TMPROOT/s5-wt" -b s5-feat master >/dev/null 2>&1; \
    git worktree lock "$TMPROOT/s5-wt" 2>/dev/null; \
    cd "$TMPROOT/s5-wt"; echo dirty >> seed.txt )
  RC=$(_run_in "$TMPROOT/s5-wt"); _check "S5 locked-worktree-exempt" "$RC" "0" "$TMPROOT/s5-wt"

  # S6: clean linked worktree with UNPUSHED commit → ADVISE, non-blocking (exit 0).
  R=$(_build_repo s6)
  ( cd "$R"; git worktree add -q "$TMPROOT/s6-wt" -b s6-feat master >/dev/null 2>&1; \
    cd "$TMPROOT/s6-wt"; echo more > more.txt; git add more.txt; git commit -q -m "unpushed" )
  RC=$(_run_in "$TMPROOT/s6-wt"); _check "S6 unpushed-advise-nonblock" "$RC" "0" "$TMPROOT/s6-wt"
  if grep -q "unpushed" "$TMPROOT/last-stderr.txt" 2>/dev/null; then
    echo "self-test (S6b advisory-emitted): PASS" >&2; PASSED=$((PASSED+1))
  else echo "self-test (S6b advisory-emitted): FAIL (no advisory on stderr)" >&2; FAILED=$((FAILED+1)); fi

  # S7: dirty worktree BUT a fresh waiver present → allow (exit 0).
  R=$(_build_repo s7)
  ( cd "$R"; git worktree add -q "$TMPROOT/s7-wt" -b s7-feat master >/dev/null 2>&1; \
    cd "$TMPROOT/s7-wt"; echo dirty >> seed.txt; \
    mkdir -p .claude/state; echo "intentionally leaving WIP in this worktree; will resume" > ".claude/state/worktree-teardown-waiver-$(date -u +%Y%m%dT%H%M%SZ).txt" )
  RC=$(_run_in "$TMPROOT/s7-wt"); _check "S7 waiver-allows-stop" "$RC" "0" "$TMPROOT/s7-wt"

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed" >&2
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi

# ============================================================
# Runtime
# ============================================================

# Shared retry-guard library (loop-break). Mirrors bug-persistence-gate.sh.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

INPUT=""
if [[ ! -t 0 ]]; then INPUT=$(cat 2>/dev/null || echo ""); fi

# --- fast no-op paths ---------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0   # A4: not a git repo

_gd="$(git rev-parse --git-dir 2>/dev/null)"
_cd="$(git rev-parse --git-common-dir 2>/dev/null)"
# B6: main checkout (git-dir == git-common-dir) is never a worktree to tear down.
[[ -n "$_gd" && -n "$_cd" && "$_gd" != "$_cd" ]] || exit 0

# A5: a locked worktree is intentionally persistent. The per-worktree lock
# marker lives at <worktree-git-dir>/locked.
_gd_abs="$(git rev-parse --absolute-git-dir 2>/dev/null || echo "$_gd")"
[[ -f "$_gd_abs/locked" ]] && exit 0

# --- classify the work in THIS worktree --------------------------------
DIRTY=0
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then DIRTY=1; fi
if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then DIRTY=1; fi

BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "")"

# Unpushed commits: prefer the branch upstream; fall back to origin/master.
UNPUSHED=0
if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
  cnt="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
  [[ "${cnt:-0}" -gt 0 ]] && UNPUSHED="$cnt"
elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
  cnt="$(git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)"
  [[ "${cnt:-0}" -gt 0 ]] && UNPUSHED="$cnt"
fi

# --- fresh-waiver escape hatch -----------------------------------------
if [[ -d .claude/state ]]; then
  if find .claude/state -type f -name 'worktree-teardown-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# --- clean + fully preserved → no-op (A1) ------------------------------
if [[ "$DIRTY" -eq 0 && "${UNPUSHED:-0}" -eq 0 ]]; then
  exit 0
fi

# --- clean but unpushed → ADVISE, non-blocking (D2) --------------------
if [[ "$DIRTY" -eq 0 ]]; then
  cat >&2 <<MSG
[worktree-teardown] This worktree has ${UNPUSHED} unpushed commit(s) on '${BRANCH:-HEAD}'.
They survive 'git worktree remove' but are lost if the branch is later deleted.
To preserve durably before cleanup:  git push -u origin ${BRANCH:-<branch>}
(Advisory only — not blocking session end.)
MSG
  exit 0
fi

# --- dirty worktree → BLOCK toward preserve-first (B1) -----------------
WT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cat >&2 <<MSG
================================================================
WORKTREE-TEARDOWN GATE — BLOCKED
================================================================

This session is ending INSIDE a linked worktree that has UNCOMMITTED
changes. Uncommitted work in a worktree is destroyed by a later
'git worktree remove --force' or 'git clean' — exactly the silent loss
the "incomplete ≠ abandoned" principle forbids.

  worktree: $WT_PATH
  branch:   ${BRANCH:-<detached>}

PRESERVE the work before ending (do NOT reach for 'git worktree remove
--force' — that deletes it). Any ONE of:

  1. Commit it, then push the branch:
       git add -A && git commit -m "<msg>" && git push -u origin ${BRANCH:-<branch>}
  2. Stash it (survives worktree removal):
       git stash push -u -m "wip-$(date -u +%Y%m%dT%H%M%SZ)"
  3. If this WIP is intentionally left to resume later, waive:
       mkdir -p .claude/state
       echo "<why this WIP is intentionally persistent>" > \\
         .claude/state/worktree-teardown-waiver-$(date -u +%Y%m%dT%H%M%SZ).txt

See ~/.claude/rules/worktree-isolation.md (teardown gate / B1).
================================================================
MSG

RG_SESSION_ID=$(retry_guard_session_id "$INPUT")
RG_FAILURE_SIG="worktree-teardown:${WT_PATH}"
RG_ERROR_ONELINE="Worktree-teardown gate: session ending in worktree '${WT_PATH}' with uncommitted changes; preserve (commit/stash/push) before stop."

retry_guard_block_or_exit \
  "worktree-teardown-gate" \
  "$RG_SESSION_ID" \
  "$RG_FAILURE_SIG" \
  "$RG_ERROR_ONELINE" \
  '{"decision": "block", "reason": "Worktree-teardown gate: ending inside a worktree with uncommitted changes. Preserve the work (commit/stash/push) or write a fresh .claude/state/worktree-teardown-waiver-*.txt. See stderr."}' \
  2
