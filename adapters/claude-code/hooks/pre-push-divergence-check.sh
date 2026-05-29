#!/bin/bash
# NEURAL-LACE-HOOK
# pre-push-divergence-check.sh — block pushes when the remote target ref
# has advanced since the local fetch.
#
# Item 2 of the 9-item git-best-practices initiative. Catches the
# "you fetched yesterday, you're about to push, but origin/master has
# moved on" failure mode locally — with a clear suggestion of how to
# reconcile — instead of letting the remote reject and the operator
# debug the message.
#
# Wired in via the global pre-push dispatcher at
# adapters/claude-code/git-hooks/pre-push (stage 3, between the credential
# scanner and any local repo-specific hook).
#
# Input contract (per git pre-push hook spec):
#   $1 — remote name (e.g. "origin")
#   $2 — remote URL
#   stdin — one or more lines: "<local-ref> <local-sha> <remote-ref> <remote-sha>"
#
# What it checks:
#   For every ref-spec line where the destination is a "stable" branch
#   (master / main), the script:
#     1. Skips delete-pushes (local-sha all zeros).
#     2. Skips first-pushes (remote-sha all zeros).
#     3. Queries the actual current remote SHA via `git ls-remote`.
#     4. Compares it to <remote-sha> from the input (what your local
#        thinks the remote is).
#     5. If they DIFFER → the remote advanced since your last fetch.
#        BLOCK with the actual remote SHA + recommended commands.
#
# Why "stable branches only": feature branches are typically single-author
# and a remote-advance is unusual (and rebase + force-push is its own
# whole-class of failure that other gates handle). Master/main is the
# multi-author critical path where stale-fetch + push is the canonical
# trip-and-fall.
#
# Exit codes:
#   0 — allow (no relevant ref / divergence not detected)
#   1 — block (divergence detected; stderr explains)
#
# Bypass: `git push --no-verify` (skips this AND every other pre-push hook).
#
# Self-test: invoke with --self-test to exercise scenarios in a sandbox.

set -u

# ============================================================
# Constants
# ============================================================

# Branches subject to the check. (main is included for projects that
# default to main; the check is a no-op on repos without that branch.)
STABLE_BRANCHES_REGEX='^refs/heads/(master|main)$'
ZERO_SHA='0000000000000000000000000000000000000000'

# ============================================================
# Helpers
# ============================================================

_die() { echo "$@" >&2; exit 1; }

# Returns 0 if ref is master/main, non-zero otherwise.
_is_stable_branch() {
  printf '%s' "$1" | grep -qE "$STABLE_BRANCHES_REGEX"
}

# Echoes the actual current SHA of <remote-ref> on <remote>, or empty
# on error. Uses `git ls-remote`, which respects the remote's current
# state regardless of what local tracking refs say.
_remote_current_sha() {
  local remote="$1" ref="$2"
  git ls-remote "$remote" "$ref" 2>/dev/null | awk 'NR==1{print $1}'
}

# ============================================================
# Main check
# ============================================================

_main_check() {
  local remote="${1:-}" url="${2:-}"
  [ -z "$remote" ] && return 0  # no remote name → not our path

  local saw_block=0
  local local_ref local_sha remote_ref remote_sha actual_remote_sha

  while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
    [ -z "$remote_ref" ] && continue

    # Only enforce on stable branches.
    _is_stable_branch "$remote_ref" || continue

    # Skip delete-pushes.
    [ "$local_sha" = "$ZERO_SHA" ] && continue
    # Skip first-pushes (remote-side doesn't exist yet).
    [ "$remote_sha" = "$ZERO_SHA" ] && continue

    # What does the remote actually currently say?
    actual_remote_sha="$(_remote_current_sha "$remote" "$remote_ref")"
    if [ -z "$actual_remote_sha" ]; then
      # Cannot reach the remote (offline? network? auth?). Don't block
      # on infrastructure errors — let the actual push fail visibly.
      continue
    fi

    # Compare. If the actual remote SHA matches what your local thinks,
    # your fetch is current — push proceeds.
    if [ "$actual_remote_sha" = "$remote_sha" ]; then
      continue
    fi

    # Divergence detected.
    saw_block=1
    echo "" >&2
    echo "PRE-PUSH DIVERGENCE CHECK — PUSH BLOCKED" >&2
    echo "================================================================" >&2
    echo "" >&2
    echo "Target:           $remote $remote_ref" >&2
    echo "Local thinks remote: $remote_sha" >&2
    echo "Remote actually at:  $actual_remote_sha" >&2
    echo "" >&2
    echo "The remote branch advanced since your last fetch. Pushing now" >&2
    echo "would either be rejected (non-FF) or — worse — overwrite the new" >&2
    echo "commits if the remote allowed force-push." >&2
    echo "" >&2
    echo "Recommended reconcile:" >&2
    echo "  git fetch $remote" >&2
    short_branch="${remote_ref#refs/heads/}"
    echo "  git pull --rebase $remote $short_branch" >&2
    echo "  git push $remote $short_branch" >&2
    echo "" >&2
    echo "Bypass (only if you understand the consequence):" >&2
    echo "  git push --no-verify" >&2
    echo "" >&2
  done

  [ "$saw_block" = "1" ] && return 1
  return 0
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  echo "[self-test] tmpdir=$tmp"

  # ---- Setup: two bare repos sharing a base history ----
  (
    cd "$tmp" && mkdir bare-canonical && cd bare-canonical && git init --bare --quiet
  )
  (
    cd "$tmp" && mkdir work && cd work
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    git remote add origin "$tmp/bare-canonical"
    echo a > a && git add a && git commit --quiet -m init
    git push --quiet origin HEAD:master
  )

  # ---- T1: push to non-master branch → silent allow ----
  (
    cd "$tmp/work"
    out="$(echo 'refs/heads/feat/foo 0000000000000000000000000000000000000000 refs/heads/feat/foo 0000000000000000000000000000000000000000' \
      | _main_check origin "$tmp/bare-canonical" 2>&1)"
    rc=$?
    if [ "$rc" = "0" ] && [ -z "$out" ]; then echo "  T1 non-master-skip: PASS"
    else echo "  T1 non-master-skip: FAIL (rc=$rc out=$out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- T2: push master to currently-matching remote → allow ----
  (
    cd "$tmp/work"
    actual="$(git ls-remote origin refs/heads/master 2>/dev/null | awk '{print $1}')"
    local_sha="$(git rev-parse HEAD)"
    echo "refs/heads/master $local_sha refs/heads/master $actual" \
      | _main_check origin "$tmp/bare-canonical" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "0" ]; then echo "  T2 master-up-to-date allow: PASS"
    else echo "  T2 master-up-to-date allow: FAIL (rc=$rc)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- T3: push master while remote advanced → BLOCK ----
  (
    cd "$tmp"
    mkdir advancer && cd advancer
    git init --quiet
    git config user.email "t@example.com" && git config user.name "T"
    git remote add origin "$tmp/bare-canonical"
    git fetch --quiet origin
    git checkout --quiet -b master origin/master
    echo b > b && git add b && git commit --quiet -m b
    git push --quiet origin master
  )
  (
    cd "$tmp/work"
    git fetch --quiet origin 2>/dev/null
    # IMPORTANT: simulate the stale-fetch case — use the OLD remote SHA
    # (the one local thinks origin/master is) as <remote-sha>, but the
    # actual remote already advanced.
    stale_sha="$(git rev-parse HEAD)"  # local master, never updated post-init
    local_sha="$stale_sha"
    echo "refs/heads/master $local_sha refs/heads/master $stale_sha" \
      | _main_check origin "$tmp/bare-canonical" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "1" ]; then echo "  T3 stale-remote BLOCK: PASS"
    else echo "  T3 stale-remote BLOCK: FAIL (rc=$rc; expected 1)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- T4: master is a delete (zero local-sha) → skip ----
  (
    cd "$tmp/work"
    actual="$(git ls-remote origin refs/heads/master 2>/dev/null | awk '{print $1}')"
    echo "refs/heads/master $ZERO_SHA refs/heads/master $actual" \
      | _main_check origin "$tmp/bare-canonical" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "0" ]; then echo "  T4 delete-push skip: PASS"
    else echo "  T4 delete-push skip: FAIL (rc=$rc)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- T5: first-push (zero remote-sha) → skip ----
  (
    cd "$tmp/work"
    local_sha="$(git rev-parse HEAD)"
    echo "refs/heads/master $local_sha refs/heads/master $ZERO_SHA" \
      | _main_check origin "$tmp/bare-canonical" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "0" ]; then echo "  T5 first-push skip: PASS"
    else echo "  T5 first-push skip: FAIL (rc=$rc)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- T6: unreachable remote → don't block (let actual push fail) ----
  (
    cd "$tmp/work"
    actual_for_arg="0000000000000000000000000000000000000001"
    local_sha="$(git rev-parse HEAD)"
    echo "refs/heads/master $local_sha refs/heads/master $actual_for_arg" \
      | _main_check unreachable-name "/nonexistent/path" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "0" ]; then echo "  T6 unreachable-remote skip: PASS"
    else echo "  T6 unreachable-remote skip: FAIL (rc=$rc)"; return 1; fi
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
    _main_check "$@"
    exit $?
    ;;
esac
