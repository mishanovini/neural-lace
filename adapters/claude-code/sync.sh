#!/usr/bin/env bash
# sync.sh — push a branch to EVERY distinct remote URL (name-independent dual-publish).
#
# WHY THIS SHAPE: the previous version matched remotes by NAME (`personal`/`work`/`pt`).
# In a clone where the second repo's remote was named something else (e.g. `origin`), the
# script silently skipped it and pushed to only one repo — the root cause of the two
# Neural Lace repos drifting apart. This version is URL-based: it discovers every distinct
# push URL configured in the repo and pushes the branch to each. Remote names are
# irrelevant, so the same command works from any clone regardless of naming.
#
# Usage:
#   sync.sh [branch]      # default: current branch
#   sync.sh --self-test   # run the built-in self-test
#
# Guarantees:
#   - Never force-pushes (no --force / -f anywhere).
#   - Reports per-URL success/failure.
#   - Exits non-zero if ANY push fails — NO silent half-sync (the original drift bug).
#   - Identity-free: the URLs come from the user's local git config at runtime, so this
#     committed script contains no real org/user names (harness-hygiene).

set -u

# Print distinct push URLs, one per line, in first-seen order.
# `git remote -v` lines look like: "<name>\t<url> (push)".
_sync_collect_urls() {
  git remote -v 2>/dev/null | awk '$3=="(push)"{print $2}' | awk '!seen[$0]++'
}

_sync_run() {
  local branch="${1:-}"
  if [ -z "$branch" ]; then
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  fi
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "sync.sh: could not determine a branch (detached HEAD?). Pass one explicitly: sync.sh <branch>" >&2
    return 2
  fi

  local urls
  urls="$(_sync_collect_urls)"
  if [ -z "$urls" ]; then
    echo "sync.sh: no push remotes configured (git remote -v is empty)." >&2
    return 2
  fi

  echo ""
  echo "Syncing branch '$branch' to every distinct remote URL:"
  printf '%s\n' "$urls" | sed 's/^/  - /'
  echo ""

  local failed=0 url
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    echo "> push -> $url"
    if git push "$url" "$branch"; then
      echo "  ok"
    else
      echo "  FAILED" >&2
      failed=1
    fi
    echo ""
  done <<< "$urls"

  if [ "$failed" -ne 0 ]; then
    echo "sync.sh: one or more pushes FAILED — the repos may now be OUT OF SYNC. Resolve before relying on the mirror." >&2
    return 1
  fi
  echo "Sync complete — branch '$branch' pushed to all distinct remote URLs."
  return 0
}

# ============================================================
# Self-test
# ============================================================
_sync_self_test() {
  command -v git >/dev/null 2>&1 || { echo "self-test: FAIL — git not available" >&2; return 1; }

  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-self-test')"
  [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "self-test: FAIL — could not create tmp dir" >&2; return 1; }

  local start_dir; start_dir="$(pwd)"
  local failed=0 msg=""
  _f() { failed=1; msg="$1"; }

  (
    set -e
    git init -q --bare "$tmp/repoA.git"
    git init -q --bare "$tmp/repoB.git"
    git init -q "$tmp/work"
    cd "$tmp/work"
    git config user.email "test@example.com"
    git config user.name "Test User"
    git checkout -q -b master
    echo "hello" > f.txt
    git add f.txt
    git commit -q -m "initial"
    # Two remotes pointing at repoA (different NAMES, same URL) + one at repoB.
    git remote add origin "$tmp/repoA.git"
    git remote add work   "$tmp/repoA.git"
    git remote add personal "$tmp/repoB.git"
  ) || { _f "setup failed"; }

  if [ "$failed" = "0" ]; then
    cd "$tmp/work"

    # Test 1: dedup — three remotes, two distinct URLs -> 2 lines.
    local n; n="$(_sync_collect_urls | wc -l | tr -d ' ')"
    if [ "$n" != "2" ]; then _f "dedup: expected 2 distinct URLs, got $n"; fi

    # Test 2: happy path push to both distinct URLs succeeds.
    if [ "$failed" = "0" ]; then
      if ! _sync_run master >/dev/null 2>&1; then _f "happy-path: _sync_run returned non-zero"; fi
    fi

    # Test 3: both bare repos actually received master at the same SHA.
    if [ "$failed" = "0" ]; then
      local src shaA shaB
      src="$(git rev-parse master)"
      shaA="$(git ls-remote "$tmp/repoA.git" refs/heads/master | awk '{print $1}')"
      shaB="$(git ls-remote "$tmp/repoB.git" refs/heads/master | awk '{print $1}')"
      [ "$shaA" = "$src" ] || _f "repoA did not receive master ($shaA != $src)"
      [ "$failed" = "0" ] && { [ "$shaB" = "$src" ] || _f "repoB did not receive master ($shaB != $src)"; }
    fi

    # Test 4: fail-loud — a bogus remote URL makes _sync_run return non-zero.
    if [ "$failed" = "0" ]; then
      git remote add broken "$tmp/does-not-exist.git"
      if _sync_run master >/dev/null 2>&1; then _f "fail-loud: expected non-zero with a broken remote, got 0"; fi
      git remote remove broken
    fi
  fi

  cd "$start_dir" 2>/dev/null || true
  rm -rf "$tmp" 2>/dev/null || true

  if [ "$failed" = "1" ]; then
    echo "self-test: FAIL — $msg" >&2
    return 1
  fi
  echo "self-test: OK"
  return 0
}

# ============================================================
# Dispatch
# ============================================================
case "${1:-}" in
  --self-test|self-test)
    _sync_self_test
    exit $?
    ;;
  *)
    _sync_run "${1:-}"
    exit $?
    ;;
esac
