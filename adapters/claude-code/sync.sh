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
# POST-PUSH VERIFICATION (drift detection part (a), 2026-05-28):
# When pushing master, after all per-URL pushes succeed, query each remote's master SHA
# via `gh api repos/<owner>/<name>/branches/master` and confirm all match. If any differ
# (push half-completed silently, ref-update raced, branch protection rejected, etc.),
# log the divergence and exit non-zero. This is the harness-internal alternative to the
# cross-repo mirror Action (PRs #30/#31/#32 — reverted by PR #33; ADR-044 Reverted) which
# proved over-engineered for the actual use case (every push happens through Claude Code
# with the harness loaded, so a local post-push check covers the steady-state need
# without the cross-account PAT operational burden).
#
# Usage:
#   sync.sh [branch]      # default: current branch
#   sync.sh --self-test   # run the built-in self-test
#
# Guarantees:
#   - Never force-pushes (no --force / -f anywhere).
#   - Reports per-URL success/failure.
#   - Exits non-zero if ANY push fails — NO silent half-sync (the original drift bug).
#   - On master pushes: ALSO exits non-zero if remote SHAs disagree after push (the
#     post-push drift signal — even if all individual pushes returned 0).
#   - Identity-free: the URLs come from the user's local git config at runtime, so this
#     committed script contains no real org/user names (harness-hygiene).

set -u

# Print distinct push URLs, one per line, in first-seen order.
# `git remote -v` lines look like: "<name>\t<url> (push)".
_sync_collect_urls() {
  git remote -v 2>/dev/null | awk '$3=="(push)"{print $2}' | awk '!seen[$0]++'
}

# Extract owner/name from a GitHub HTTPS or SSH URL.
# Returns empty if the URL isn't a recognizable GitHub URL.
_sync_owner_name_from_url() {
  local url="$1"
  case "$url" in
    https://github.com/*)
      url="${url#https://github.com/}"
      url="${url%.git}"
      printf '%s' "$url"
      ;;
    git@github.com:*)
      url="${url#git@github.com:}"
      url="${url%.git}"
      printf '%s' "$url"
      ;;
    *)
      ;;
  esac
}

# Query a GitHub repo's master TREE HASH via gh CLI. Empty on error.
# On a 404 `gh api` outputs the error JSON body to stdout AND exits non-zero
# — `|| true` suppresses the exit code, so we must validate the shape
# explicitly (40-char hex) to distinguish a real tree hash from an error body.
#
# WHY TREE HASH AND NOT COMMIT SHA: per decision 064 (2026-07-16, superseding the
# 2026-05-29 "PT is canonical" posture — personal `origin` is now canonical;
# `pt` is the mirror, see docs/decisions/064-never-diverge-single-canonical-
# master.md), a manual reconcile (docs/runbooks/master-reconcile-and-estate-
# cleanup.md) can still produce a divergent-history-identical-content state —
# e.g. a cherry-pick-based reconcile after true divergence gives the two repos
# different commit SHAs on the affected commits (each cherry-pick produces a
# distinct commit object on the receiving side) while the CONTENT stays
# identical. What must stay identical is the CONTENT (the tree hash), not the
# commit SHA. Comparing `.commit.sha` here would false-positive after any such
# reconcile; comparing `.commit.commit.tree.sha` (the tree the master tip
# points at) is the correct content-equivalence check.
# Function name is preserved for callsite stability; the value it returns is
# now a tree hash, not a commit SHA.
_sync_remote_master_sha() {
  local owner_name="$1" tree
  [ -z "$owner_name" ] && return 0
  tree="$(gh api "repos/${owner_name}/branches/master" --jq '.commit.commit.tree.sha' 2>/dev/null || true)"
  if [[ "$tree" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s' "$tree"
  fi
}

# Post-push verification: for each distinct GitHub URL, query its master TREE
# HASH; all must be equal. Returns 0 if consistent, 1 if divergent, 2 if cannot
# verify (no gh CLI / no GitHub URLs / API call failed for one or more).
#
# Tree-hash (content) equivalence is the right check under the 2026-05-29
# divergent-history-identical-content posture: the two repos are expected to
# have different commit SHAs forever, but identical tree hashes (same content).
_sync_verify_master_convergence() {
  command -v gh >/dev/null 2>&1 || { echo "  [verify] skipped (gh CLI not available)" >&2; return 2; }

  local urls owner_name first_tree="" url tree mismatch=0 missing=0
  urls="$(_sync_collect_urls)"
  [ -z "$urls" ] && return 2

  echo ""
  echo "Post-push drift check (master tree hashes across remotes — content equivalence):"
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    owner_name="$(_sync_owner_name_from_url "$url")"
    if [ -z "$owner_name" ]; then
      echo "  - $url -> not a recognizable GitHub URL; skipping verify."
      continue
    fi
    tree="$(_sync_remote_master_sha "$owner_name")"
    if [ -z "$tree" ]; then
      echo "  - $owner_name -> tree hash unavailable (gh api failed; auth scope / network / no master ref)"
      missing=1
      continue
    fi
    echo "  - $owner_name tree = $tree"
    if [ -z "$first_tree" ]; then
      first_tree="$tree"
    elif [ "$tree" != "$first_tree" ]; then
      mismatch=1
    fi
  done <<< "$urls"

  if [ "$mismatch" -ne 0 ]; then
    echo "" >&2
    echo "DRIFT DETECTED: master tree hashes disagree across remotes (content divergence)." >&2
    echo "The push completed but the repos are NOT at identical CONTENT. Resolve before" >&2
    echo "the next push, or future syncs will compound the divergence. Common causes:" >&2
    echo "  - one remote rejected the push (branch protection / wrong scope / etc.)" >&2
    echo "  - a concurrent push to one remote raced this one" >&2
    echo "  - the branches were already divergent and this push only converged some" >&2
    echo "  - a cherry-pick conflict was resolved differently on one side" >&2
    return 1
  fi
  if [ "$missing" -ne 0 ]; then
    echo "  [verify] WARNING — could not query tree hash for one or more remotes; convergence not confirmed." >&2
    return 2
  fi
  echo "  [verify] all remote master tree hashes match (content converged)."
  return 0
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

  # Post-push verification: master only. Other branches don't need cross-repo
  # equality because they're not the steady-state convergence point.
  if [ "$branch" = "master" ]; then
    local verify_rc
    _sync_verify_master_convergence
    verify_rc=$?
    if [ "$verify_rc" -eq 1 ]; then
      return 1
    fi
    # rc=2 (cannot verify) is a warning, not a failure — we don't want to false-alarm
    # in environments without gh CLI auth, but it IS logged so the operator sees it.
  fi
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

    # Test 5: owner/name parser handles https + ssh + non-github URLs.
    if [ "$failed" = "0" ]; then
      local on
      on="$(_sync_owner_name_from_url "https://github.com/foo/bar.git")"
      [ "$on" = "foo/bar" ] || _f "owner-name (https): got '$on', want 'foo/bar'"
      on="$(_sync_owner_name_from_url "git@github.com:foo/bar.git")"
      [ "$on" = "foo/bar" ] || _f "owner-name (ssh): got '$on', want 'foo/bar'"
      on="$(_sync_owner_name_from_url "https://github.com/foo/bar")"
      [ "$on" = "foo/bar" ] || _f "owner-name (no .git): got '$on', want 'foo/bar'"
      on="$(_sync_owner_name_from_url "$tmp/repoA.git")"
      [ -z "$on" ] || _f "owner-name (filesystem URL): expected empty, got '$on'"
    fi

    # Test 6: verify-convergence returns 2 (cannot-verify) when no GitHub URLs present.
    # In the self-test we only have filesystem URLs, so the parser returns empty for
    # all of them, gh CLI never runs, and the function exits 2 (warning, not failure).
    if [ "$failed" = "0" ]; then
      _sync_verify_master_convergence >/dev/null 2>&1
      local rc=$?
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
        _f "verify-convergence (no-github-urls): expected 0 or 2, got $rc"
      fi
    fi

    # Test 7: tree-hash compare — two remotes with different commit SHAs but
    # identical tree hashes report convergence (rc=0). This is the post-2026-05-29
    # divergent-history-identical-content posture; comparing commit SHAs would
    # have false-positived as drift, comparing tree hashes correctly returns OK.
    # Uses a mock `gh` on PATH so no real network or auth is required.
    if [ "$failed" = "0" ]; then
      local mock_bin
      mock_bin="$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-mock-gh')"
      if [ -n "$mock_bin" ] && [ -d "$mock_bin" ]; then
        cat > "$mock_bin/gh" <<'MOCKGH'
#!/usr/bin/env bash
# Fake gh for sync.sh self-test. Only handles `gh api repos/<owner>/<name>/branches/master --jq <filter>`.
filter=""; repo=""; prev=""
for arg in "$@"; do
  case "$prev" in --jq) filter="$arg" ;; esac
  case "$arg" in repos/*/branches/master) repo="$arg" ;; esac
  prev="$arg"
done
# Two repos: different commit SHAs, IDENTICAL tree hashes.
case "$repo" in
  repos/test-owner-A/repo-x/branches/master)
    commit_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    tree_sha="11111111111111111111111111111111111111aa"
    ;;
  repos/test-owner-B/repo-y/branches/master)
    commit_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    tree_sha="11111111111111111111111111111111111111aa"
    ;;
  *) exit 1 ;;
esac
case "$filter" in
  ".commit.commit.tree.sha") echo "$tree_sha" ;;
  ".commit.sha") echo "$commit_sha" ;;
  *) exit 1 ;;
esac
MOCKGH
        chmod +x "$mock_bin/gh"

        # Stub out _sync_collect_urls so the function sees two distinct GitHub URLs
        # that the owner-name parser can recognize. The parser only accepts
        # github.com URLs, so we use real-looking https URLs.
        _sync_collect_urls_orig_body="$(declare -f _sync_collect_urls)"
        _sync_collect_urls() {
          printf 'https://github.com/test-owner-A/repo-x.git\n'
          printf 'https://github.com/test-owner-B/repo-y.git\n'
        }
        local out rc
        out="$(PATH="$mock_bin:$PATH" _sync_verify_master_convergence 2>&1)"; rc=$?
        # Restore the original collect-urls function.
        eval "$_sync_collect_urls_orig_body"

        if [ "$rc" -ne 0 ]; then
          _f "tree-hash-equiv (T7): expected rc=0 (content converged), got $rc; out: $out"
        elif ! printf '%s' "$out" | grep -q 'tree hashes match'; then
          _f "tree-hash-equiv (T7): expected 'tree hashes match' in output; out: $out"
        fi

        rm -rf "$mock_bin" 2>/dev/null || true
      fi
    fi
  fi

  cd "$start_dir" 2>/dev/null || true
  rm -rf "$tmp" 2>/dev/null || true

  if [ "$failed" = "1" ]; then
    echo "self-test: FAIL — $msg" >&2
    return 1
  fi
  echo "self-test: OK (7 scenarios)"
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
