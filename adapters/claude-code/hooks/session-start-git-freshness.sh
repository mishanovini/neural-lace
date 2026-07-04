#!/bin/bash
# NEURAL-LACE-HOOK
# session-start-git-freshness.sh — SessionStart hook for git freshness.
#
# Surfaces three kinds of state at session start so the next session does
# not unknowingly work from a stale or conflicted starting point:
#
#   1. (Item 1) Local master behind a remote master. Fetches all remotes
#      (with a short timeout so a flaky network does not block session
#      start) and reports if any remote master has commits the local
#      master has not seen.
#
#   2. (Item 9) Working tree has uncommitted changes that are NOT on a
#      named WIP branch. Convention (per branch-hygiene rule): WIP work
#      lives on `wip/*`, `feat/*`, `fix/*`, `feature/*`, `bugfix/*`,
#      `salvage/*`, `backup/*`, or `rebase/*` branches. Uncommitted
#      changes on master or another "stable" branch are surprising and
#      worth warning about — they may indicate work from a previous
#      session that did not commit cleanly.
#
#   3. (Item 9 / convenience) Current branch + ahead/behind summary, so
#      the operator sees at a glance where they are.
#
# Design notes:
# - Reads JSON on stdin per the SessionStart contract but ignores the
#   payload. The hook acts on the working directory.
# - Always exits 0 (informational; never blocks session start).
# - Silent if there is nothing to report.
# - Fast path: if not a git repo, exit 0 immediately.
# - Network fetch is timeout-bounded (default 10s) so the hook cannot
#   stall session start indefinitely on a slow/flaky link. The timeout
#   is honored as best-effort; on systems without `timeout` the fetch
#   runs unbounded.
#
# Self-test: invoke with --self-test to exercise the scenario matrix.

set -u

# ============================================================
# Constants
# ============================================================

FETCH_TIMEOUT_SECONDS="${FETCH_TIMEOUT_SECONDS:-10}"
# Branches where uncommitted work is expected and not worth flagging:
WIP_BRANCH_PATTERN='^(wip|feat|feature|fix|bugfix|salvage|backup|rebase|reconverge|sync|sync-pt-to-personal)/'

# ============================================================
# Helpers
# ============================================================

_in_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

_remote_names() {
  git remote 2>/dev/null
}

_current_branch() {
  git symbolic-ref --short -q HEAD 2>/dev/null || echo ""
}

_has_uncommitted() {
  # Unstaged or staged changes (tracked files only — untracked are noise).
  ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null
}

_is_wip_branch() {
  local b="$1"
  [ -z "$b" ] && return 1
  printf '%s' "$b" | grep -qE "$WIP_BRANCH_PATTERN"
}

# Run git fetch --all with a best-effort timeout. Suppresses normal output;
# errors are echoed to stderr (the SessionStart layer ignores stderr but the
# operator can see them on direct invocation).
_safe_fetch_all() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FETCH_TIMEOUT_SECONDS" git fetch --all --quiet 2>&1 | head -5 >&2 || return 0
  else
    git fetch --all --quiet 2>&1 | head -5 >&2 || return 0
  fi
}

# Echoes the count of commits on $1 that are not on $2 (i.e. how far $1 is
# AHEAD of $2). Empty string if either ref is missing.
_ahead_count() {
  local from="$1" to="$2"
  git rev-parse --verify --quiet "$from" >/dev/null || return 0
  git rev-parse --verify --quiet "$to" >/dev/null || return 0
  git rev-list --count "${to}..${from}" 2>/dev/null
}

# ============================================================
# Main check
# ============================================================

_main_check() {
  local out_lines=()
  local current remote behind_count ahead_count

  _in_git_repo || return 0

  # 1. Fetch all remotes (best-effort, bounded).
  if [ -n "$(_remote_names)" ]; then
    _safe_fetch_all
  fi

  # 2. Local master vs remote masters — surface behind condition.
  if git rev-parse --verify --quiet master >/dev/null 2>&1; then
    while IFS= read -r remote; do
      [ -z "$remote" ] && continue
      git rev-parse --verify --quiet "${remote}/master" >/dev/null 2>&1 || continue
      behind_count="$(_ahead_count "${remote}/master" master)"
      ahead_count="$(_ahead_count master "${remote}/master")"
      if [ -n "$behind_count" ] && [ "$behind_count" -gt 0 ]; then
        if [ "$ahead_count" -gt 0 ]; then
          out_lines+=("[git-freshness] local master is BEHIND ${remote}/master by $behind_count commit(s) (and ahead by $ahead_count) — diverged. Reconcile before pushing.")
        else
          out_lines+=("[git-freshness] local master is BEHIND ${remote}/master by $behind_count commit(s). Run: git checkout master && git pull --ff-only ${remote} master")
        fi
      fi
    done < <(_remote_names)
  fi

  # 3. Current branch state.
  current="$(_current_branch)"
  if [ -n "$current" ]; then
    if _has_uncommitted; then
      if [ "$current" = "master" ] || [ "$current" = "main" ]; then
        out_lines+=("[git-freshness] uncommitted changes on $current branch — this is unusual. Either commit on master (pre-customer policy), or branch off and commit there. See: git status")
      elif ! _is_wip_branch "$current"; then
        out_lines+=("[git-freshness] uncommitted changes on '$current' (not a recognized WIP branch). Expected WIP-branch patterns: wip/* feat/* fix/* feature/* bugfix/* salvage/* backup/* rebase/* reconverge/* sync/*. See: git status")
      fi
      # If on a WIP-pattern branch, uncommitted is expected → no warning.
    fi

    # Also surface ahead-of-master on a feature branch so the operator sees
    # at-a-glance "yes you have N commits to push" / "no, branch is fresh."
    if [ "$current" != "master" ] && [ "$current" != "main" ]; then
      if git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
        local feat_ahead feat_behind
        feat_ahead="$(_ahead_count "$current" origin/master)"
        feat_behind="$(_ahead_count origin/master "$current")"
        if [ -n "${feat_ahead:-}" ] && [ "$feat_ahead" -gt 0 ]; then
          if [ -n "${feat_behind:-}" ] && [ "$feat_behind" -gt 0 ]; then
            out_lines+=("[git-freshness] current branch '$current' is ahead of origin/master by $feat_ahead, behind by $feat_behind — consider merging origin/master into '$current' or rebasing carefully (push-friendly).")
          fi
        fi
      fi
    fi
  fi

  # 4. Emit. Silent if nothing to report.
  if [ "${#out_lines[@]}" -gt 0 ]; then
    printf '%s\n' "${out_lines[@]}"
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

  # Reusable bare repo to act as origin
  ( cd "$tmp" && mkdir bare-canonical && cd bare-canonical && git init --bare --quiet )

  # T1: not a git repo → silent, exit 0
  (
    cd "$tmp"
    out="$(echo '{}' | _main_check)"
    if [ -z "$out" ]; then echo "  T1 not-a-git-repo silent: PASS"
    else echo "  T1 not-a-git-repo silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T2: git repo with no remotes → silent (no behind report; no current-branch warn unless dirty)
  (
    cd "$tmp" && mkdir noremote && cd noremote
    git init --quiet
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "t@example.com" && git config user.name "T"
    echo a > a && git add a && git commit --quiet -m init
    out="$(_main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T2 no-remotes silent: PASS"
    else echo "  T2 no-remotes silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T3: local master is BEHIND origin/master → expect behind-warning
  (
    cd "$tmp" && mkdir behind && cd behind
    git init --quiet
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "t@example.com" && git config user.name "T"
    git remote add origin "$tmp/bare-canonical"
    echo a > a && git add a && git commit --quiet -m init
    git push --quiet origin HEAD:master
    git branch master 2>/dev/null
    # Advance the remote master
    ( cd "$tmp" && mkdir advancer && cd advancer
      git init --quiet
      git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
      git config user.email "t@example.com" && git config user.name "T"
      git remote add origin "$tmp/bare-canonical"
      git fetch --quiet origin
      git checkout --quiet -b master origin/master
      echo b > b && git add b && git commit --quiet -m b
      git push --quiet origin master )
    # Local must be on master to compare master vs origin/master correctly.
    git fetch --quiet origin 2>/dev/null
    git checkout --quiet master 2>/dev/null || git checkout --quiet -b master
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "BEHIND origin/master"; then echo "  T3 behind-detection: PASS"
    else echo "  T3 behind-detection: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T4: local master matches origin/master → no behind warning
  (
    cd "$tmp/behind"
    git pull --ff-only --quiet origin master 2>/dev/null
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "BEHIND"; then echo "  T4 not-behind-when-current: FAIL (got: $out)"; return 1
    else echo "  T4 not-behind-when-current: PASS"; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T5: uncommitted changes on master → warn
  (
    cd "$tmp/behind"
    echo "uncommitted" > new-tracked.txt
    git add new-tracked.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "uncommitted changes on master"; then echo "  T5 dirty-on-master warn: PASS"
    else echo "  T5 dirty-on-master warn: FAIL (got: $out)"; return 1; fi
    # reset for next scenario
    git reset --hard --quiet HEAD
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T6: uncommitted on a wip/* branch → silent
  (
    cd "$tmp/behind"
    git checkout --quiet -b wip/test-uncommit
    echo "uncommitted on wip" > wip.txt
    git add wip.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "uncommitted changes"; then echo "  T6 dirty-on-wip-silent: FAIL (got: $out)"; return 1
    else echo "  T6 dirty-on-wip-silent: PASS"; fi
    git reset --hard --quiet HEAD && git checkout --quiet master && git branch -D wip/test-uncommit
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T7: uncommitted on an unrecognized branch (not master, not WIP-pattern) → warn
  (
    cd "$tmp/behind"
    git checkout --quiet -b random-junk
    echo "uncommitted" > junk.txt
    git add junk.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "not a recognized WIP branch"; then echo "  T7 dirty-on-unrecognized warn: PASS"
    else echo "  T7 dirty-on-unrecognized warn: FAIL (got: $out)"; return 1; fi
    git reset --hard --quiet HEAD && git checkout --quiet master && git branch -D random-junk
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T8: clean tree → silent
  (
    cd "$tmp/behind"
    out="$(_main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T8 clean-tree silent: PASS"
    else echo "  T8 clean-tree silent: FAIL (got: $out)"; return 1; fi
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
    # SessionStart hooks receive a JSON payload on stdin; we ignore it.
    cat >/dev/null 2>&1 || true
    _main_check
    exit 0
    ;;
esac
