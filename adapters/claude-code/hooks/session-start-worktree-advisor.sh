#!/bin/bash
# NEURAL-LACE-HOOK
# session-start-worktree-advisor.sh — SessionStart hook.
#
# Auto-injects tailored guidance encouraging per-session git-worktree
# isolation, so concurrent sessions stop colliding on the shared main
# checkout (the "N sessions on one folder" problem). This is the START
# side of worktree-isolation — which a hook CANNOT force (the session's
# cwd is already chosen by the time SessionStart fires; a subprocess
# cannot relocate its parent), so the advisor INFORMS rather than blocks.
# The Stop-side companion (worktree-teardown-gate.sh) handles the end side.
#
# Tailoring (per rules/worktree-isolation.md edge case B4 — avoid alert
# fatigue):
#   - Already in a linked worktree (git-dir != git-common-dir) → SILENT
#     (the session is already isolated; nagging it would be noise).
#   - In the MAIN CHECKOUT of a repo that HAS linked worktrees → LOUD
#     (worktrees existing is the readable proxy for "multi-session repo";
#     there is no hook-readable live-session count — edge case B5).
#   - In the main checkout with NO linked worktrees → GENTLE one-liner.
#   - Not a git repo → no-op.
#
# Every message names the exemption set (read-only / on-master-by-necessity
# / tiny edit) so a session for which a worktree is the WRONG tool can
# self-dismiss, and names the setup cost (gitignored env + install) so a
# session that takes the advice does not get stuck (edge case B8).
#
# Design notes:
# - Reads JSON on stdin per the SessionStart contract but ignores it.
# - Always exits 0 (informational; never blocks session start).
# - Silent when there is nothing worth saying.
# - Fast path: not a git repo → exit 0 immediately.
#
# Self-test: invoke with --self-test to exercise the scenario matrix.

set -u

# ============================================================
# Helpers
# ============================================================

_in_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# True when cwd is a LINKED worktree (not the main checkout). In the main
# checkout `--git-dir` and `--git-common-dir` are identical (both `.git`);
# in a linked worktree the per-worktree git dir differs from the shared
# common dir. Verified 2026-06-23 against the real neural-lace checkout.
_in_worktree() {
  local gd cd
  gd="$(git rev-parse --git-dir 2>/dev/null)" || return 1
  cd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$gd" ] && [ -n "$cd" ] && [ "$gd" != "$cd" ]
}

_repo_name() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "this repo"; return; }
  basename "$top" 2>/dev/null || echo "this repo"
}

# Count of LINKED worktrees (total worktrees minus the main checkout).
_linked_worktree_count() {
  local total
  total="$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ')"
  [ -z "$total" ] && { echo 0; return; }
  if [ "$total" -ge 1 ]; then echo $((total - 1)); else echo 0; fi
}

# ============================================================
# Main check
# ============================================================

_main_check() {
  _in_git_repo || return 0

  # Already isolated → say nothing (edge case B4 / exemption A3).
  if _in_worktree; then
    return 0
  fi

  local repo linked
  repo="$(_repo_name)"
  linked="$(_linked_worktree_count)"

  if [ "${linked:-0}" -gt 0 ]; then
    # LOUD — main checkout of a repo that has worktrees ⇒ multi-session.
    cat <<MSG
[worktree-advisor] You are in the MAIN CHECKOUT of '$repo' and $linked linked worktree(s) exist — other sessions likely share this folder, so commits here can collide on the working tree / index / stash.
If this session will COMMIT, prefer an isolated worktree:
    git worktree add ../$repo-<topic> -b <feat|fix>/<slug> origin/master
    # then copy any gitignored env (e.g. .env.local) and run the repo's install (e.g. npm install) if it needs one
SKIP this if your session is read-only (diagnosis / Q&A / review), an on-master-by-necessity op (post-merge sync, worktree or branch cleanup, master reconcile), or a tiny ancillary edit.
MSG
  else
    # GENTLE — main checkout, no worktrees yet (likely solo).
    cat <<MSG
[worktree-advisor] In the main checkout of '$repo'. If multiple sessions will run here and this one will commit, consider an isolated worktree (git worktree add ../$repo-<topic> -b <branch> origin/master). Skip for read-only / tiny / on-master-by-necessity work.
MSG
  fi
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  echo "[self-test] tmpdir=$tmp"

  _seed_repo() {
    # $1 = dir name; creates a git repo with one commit, cd-ready
    mkdir -p "$tmp/$1" && cd "$tmp/$1" || return 1
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    echo a > a && git add a && git commit --quiet -m init
  }

  # T1: not a git repo → silent, exit 0
  (
    mkdir -p "$tmp/plain" && cd "$tmp/plain"
    out="$(echo '{}' | _main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T1 not-a-git-repo silent: PASS"
    else echo "  T1 not-a-git-repo silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T2: inside a linked worktree → silent
  (
    _seed_repo wt-main >/dev/null 2>&1
    git worktree add --quiet "$tmp/wt-linked" -b wt-branch >/dev/null 2>&1
    cd "$tmp/wt-linked"
    out="$(_main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T2 in-worktree silent: PASS"
    else echo "  T2 in-worktree silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T3: main checkout WITH a linked worktree → LOUD
  (
    cd "$tmp/wt-main" 2>/dev/null || { echo "  T3 setup FAIL"; return 1; }
    # wt-main already has the wt-linked worktree from T2
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "MAIN CHECKOUT" && echo "$out" | grep -q "git worktree add"; then
      echo "  T3 main+worktrees loud: PASS"
    else echo "  T3 main+worktrees loud: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T4: main checkout with NO worktrees → GENTLE (lowercase 'main checkout', not the LOUD form)
  (
    _seed_repo solo >/dev/null 2>&1
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "In the main checkout" && ! echo "$out" | grep -q "MAIN CHECKOUT"; then
      echo "  T4 main+none gentle: PASS"
    else echo "  T4 main+none gentle: FAIL (got: $out)"; return 1; fi
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
  *)
    cat >/dev/null 2>&1 || true   # consume stdin (SessionStart payload), ignore
    _main_check
    exit 0
    ;;
esac
