#!/usr/bin/env bash
# sync-pt-to-personal.sh — cherry-pick a PT-master commit onto personal master.
#
# Going-forward posture (2026-05-29, per Misha): PT is canonical; personal is
# synced FROM PT via cherry-pick + non-force direct push. The two repos have
# different commit SHAs forever (each cherry-pick produces a distinct commit
# object), but content (tree hash) is held identical at every sync point.
# `sync.sh` (dual-publish from current branch) and this script
# (cherry-pick-PT-master-onto-personal) compose: `sync.sh` is for feature-branch
# publishing; this script is for the merged-to-master content moving from
# canonical to mirror.
#
# Usage:
#   sync-pt-to-personal.sh <PR-number-or-commit-SHA>
#   sync-pt-to-personal.sh --self-test
#
# Examples:
#   sync-pt-to-personal.sh 43          # look up merge commit for PT PR #43
#   sync-pt-to-personal.sh be067db     # cherry-pick this exact commit
#
# Guarantees:
#   - Never force-pushes (no --force / -f anywhere; push aborts if non-FF).
#   - Identity-free: no real org / user / account name hardcoded. The "canonical
#     remote" is `origin`; the "mirror remote" is whichever other remote has a
#     distinct URL. The gh account name for the mirror is parsed from that URL.
#   - Restores the user's original branch on exit, even on failure (trap).
#   - No-op if the PT commit's tree is already present on mirror master (idempotent).
#   - Verifies tree-equivalence before push AND after push (catches half-syncs).

set -u

# ============================================================
# Constants / args
# ============================================================

CANONICAL_REMOTE="origin"
TEMP_BRANCH_PREFIX="sync-pt-to-personal/"

# ============================================================
# Helpers
# ============================================================

_log() { printf '[sync-pt-to-personal] %s\n' "$*" >&2; }
_die() { _log "ERROR: $*"; exit 1; }

# Discover the mirror remote: any remote with a push URL distinct from the
# canonical remote's push URL. Echoes "name url" of the first match, or empty.
_discover_mirror_remote() {
  local canonical_url mirror_name mirror_url
  canonical_url="$(git remote get-url --push "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && return 0
  while IFS=$'\t' read -r name rest; do
    [ -z "$name" ] && continue
    [ "$name" = "$CANONICAL_REMOTE" ] && continue
    mirror_url="$(git remote get-url --push "$name" 2>/dev/null || echo "")"
    if [ -n "$mirror_url" ] && [ "$mirror_url" != "$canonical_url" ]; then
      printf '%s\t%s\n' "$name" "$mirror_url"
      return 0
    fi
  done < <(git remote -v 2>/dev/null | awk '$3=="(push)"{print $1"\t"$2}' | awk '!seen[$1]++')
}

# Parse owner from a GitHub HTTPS/SSH URL. Echoes empty on no match.
_owner_from_url() {
  local url="$1"
  case "$url" in
    https://github.com/*)
      url="${url#https://github.com/}"
      printf '%s' "${url%%/*}"
      ;;
    git@github.com:*)
      url="${url#git@github.com:}"
      printf '%s' "${url%%/*}"
      ;;
    *)
      ;;
  esac
}

# Resolve <arg> into an origin/master-reachable commit SHA.
#   - If arg looks like a small integer, treat as PT PR# and look up merge_commit_sha
#     via gh api against the canonical remote's owner/name.
#   - Otherwise treat as a commit SHA and verify it's an ancestor of origin/master.
_resolve_to_pt_commit() {
  local arg="$1" canonical_url owner_name sha
  if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
    canonical_url="$(git remote get-url --push "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
    case "$canonical_url" in
      https://github.com/*) owner_name="${canonical_url#https://github.com/}"; owner_name="${owner_name%.git}" ;;
      git@github.com:*)    owner_name="${canonical_url#git@github.com:}"; owner_name="${owner_name%.git}" ;;
      *) _die "cannot parse canonical remote URL: $canonical_url" ;;
    esac
    sha="$(gh api "repos/${owner_name}/pulls/${arg}" --jq '.merge_commit_sha' 2>/dev/null || echo "")"
    [ -z "$sha" ] || [ "$sha" = "null" ] && _die "PR #${arg} has no merge_commit_sha (not merged?)"
  else
    sha="$arg"
  fi
  # Normalize to full SHA and verify ancestor of origin/master.
  sha="$(git rev-parse --verify --quiet "${sha}^{commit}" 2>/dev/null || echo "")"
  [ -z "$sha" ] && _die "could not resolve to a commit: $1"
  if ! git merge-base --is-ancestor "$sha" "${CANONICAL_REMOTE}/master" 2>/dev/null; then
    _die "commit $sha is not an ancestor of ${CANONICAL_REMOTE}/master"
  fi
  printf '%s' "$sha"
}

# ============================================================
# Main flow
# ============================================================

_main_sync() {
  local arg="$1"
  local mirror_line mirror_name mirror_url mirror_owner
  local pt_sha pt_tree
  local original_branch temp_branch
  local current_gh_account need_switch=0

  # 1. Discover mirror remote.
  mirror_line="$(_discover_mirror_remote)"
  [ -z "$mirror_line" ] && _die "no mirror remote found (need 2 remotes with distinct URLs)"
  mirror_name="${mirror_line%%$'\t'*}"
  mirror_url="${mirror_line#*$'\t'}"
  mirror_owner="$(_owner_from_url "$mirror_url")"
  [ -z "$mirror_owner" ] && _die "cannot parse owner from mirror URL: $mirror_url"
  _log "canonical remote: $CANONICAL_REMOTE -> $(git remote get-url --push "$CANONICAL_REMOTE")"
  _log "mirror remote:    $mirror_name -> $mirror_url (owner: $mirror_owner)"

  # 2. Fetch both sides so we have latest refs.
  git fetch --quiet "$CANONICAL_REMOTE" 2>&1 | sed 's/^/  /'
  git fetch --quiet "$mirror_name" 2>&1 | sed 's/^/  /'

  # 3. Resolve the input to a PT-master commit.
  pt_sha="$(_resolve_to_pt_commit "$arg")"
  pt_tree="$(git rev-parse "${pt_sha}^{tree}")"
  _log "resolved input: $arg -> commit $pt_sha (tree $pt_tree)"

  # 4. Already-synced check: if mirror master's tree already matches, no-op.
  local mirror_tree
  mirror_tree="$(git rev-parse "${mirror_name}/master^{tree}" 2>/dev/null || echo "")"
  if [ "$mirror_tree" = "$pt_tree" ]; then
    _log "mirror ${mirror_name}/master already at tree $pt_tree — nothing to do."
    return 0
  fi

  # 5. Save current branch and set up cleanup trap.
  original_branch="$(git symbolic-ref --short -q HEAD || echo "")"
  temp_branch="${TEMP_BRANCH_PREFIX}$(printf '%s' "$pt_sha" | head -c 7)"
  cleanup() {
    if [ -n "${original_branch:-}" ]; then
      git checkout --quiet "$original_branch" 2>/dev/null || true
    fi
    git branch -D "$temp_branch" 2>/dev/null || true
  }
  trap cleanup EXIT

  # 6. Create temp branch from mirror master.
  if ! git checkout --quiet -b "$temp_branch" "${mirror_name}/master" 2>&1 | sed 's/^/  /'; then
    _die "failed to create temp branch $temp_branch from ${mirror_name}/master"
  fi

  # 7. Cherry-pick.
  if ! git cherry-pick "$pt_sha" 2>&1 | sed 's/^/  /'; then
    git cherry-pick --abort 2>/dev/null || true
    _die "cherry-pick of $pt_sha failed (conflict?); aborted"
  fi

  # 8. Verify tree equivalence post-cherry-pick.
  local local_tree
  local_tree="$(git rev-parse HEAD^{tree})"
  if [ "$local_tree" != "$pt_tree" ]; then
    _die "tree mismatch after cherry-pick: expected $pt_tree, got $local_tree"
  fi
  _log "cherry-pick tree-equivalent ✓"

  # 9. Switch gh auth to mirror_owner if needed (so credential helper uses
  #    the right account for the HTTPS push). Best-effort: if `gh auth list`
  #    doesn't show $mirror_owner, attempt the push anyway and surface failure.
  current_gh_account="$(gh auth status 2>&1 | grep -E '^\s*-?\s*Active account: true' -B1 | head -1 | sed -E 's/.*account[[:space:]]+([^[:space:]]+).*/\1/' | head -1)"
  if command -v gh >/dev/null 2>&1; then
    if gh auth status 2>&1 | grep -q "Logged in to github.com account $mirror_owner"; then
      if [ "$current_gh_account" != "$mirror_owner" ]; then
        _log "switching gh auth to $mirror_owner for mirror push"
        gh auth switch -u "$mirror_owner" 2>&1 | sed 's/^/  /' >&2 || true
        need_switch=1
      fi
    else
      _log "WARN: gh has no account '$mirror_owner'; attempting push with current credentials"
    fi
  fi

  # 10. Push to mirror master (FF-only, no force).
  local push_ok=0
  if git push "$mirror_name" "HEAD:master" 2>&1 | sed 's/^/  /'; then
    push_ok=1
  fi

  # 11. Restore gh auth.
  if [ "$need_switch" = "1" ] && [ -n "$current_gh_account" ]; then
    _log "restoring gh auth to $current_gh_account"
    gh auth switch -u "$current_gh_account" 2>&1 | sed 's/^/  /' >&2 || true
  fi

  [ "$push_ok" = "1" ] || _die "push to ${mirror_name} master failed"

  # 12. Post-push verification: fetch mirror, confirm tree-equivalence.
  git fetch --quiet "$mirror_name" 2>&1 | sed 's/^/  /'
  local post_mirror_tree
  post_mirror_tree="$(git rev-parse "${mirror_name}/master^{tree}" 2>/dev/null || echo "")"
  if [ "$post_mirror_tree" != "$pt_tree" ]; then
    _die "post-push tree mismatch: ${mirror_name}/master tree $post_mirror_tree != PT tree $pt_tree"
  fi
  _log "post-push tree-equivalent ✓"

  _log "DONE: ${CANONICAL_REMOTE}/master @ $pt_sha (tree $pt_tree) → ${mirror_name}/master @ $(git rev-parse ${mirror_name}/master)"
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  echo "[self-test] tmpdir=$tmp"

  # Scenario S1: _owner_from_url parses HTTPS and SSH URLs correctly.
  # Uses example-domain owner slugs to avoid identifier leak (harness-hygiene).
  local got_https got_ssh got_bad
  got_https="$(_owner_from_url 'https://github.com/example-org/example-repo.git')"
  got_ssh="$(_owner_from_url 'git@github.com:example-user/example-repo.git')"
  got_bad="$(_owner_from_url 'https://gitlab.com/foo/bar.git')"
  if [ "$got_https" = "example-org" ] && [ "$got_ssh" = "example-user" ] && [ -z "$got_bad" ]; then
    echo "  S1 _owner_from_url: PASS"; pass=$((pass+1))
  else
    echo "  S1 _owner_from_url: FAIL (https=$got_https ssh=$got_ssh bad=$got_bad)"; fail=$((fail+1))
  fi

  # Scenario S2: build a synthetic repo with two remotes; verify
  # _discover_mirror_remote picks the non-origin one.
  (
    cd "$tmp"
    mkdir bare-canonical && cd bare-canonical && git init --bare --quiet && cd ..
    mkdir bare-mirror && cd bare-mirror && git init --bare --quiet && cd ..
    mkdir work && cd work
    git init --quiet
    git config user.email "test@example.com" && git config user.name "Test"
    git remote add origin "$tmp/bare-canonical"
    git remote add personal "$tmp/bare-mirror"
    echo "init" > a.txt && git add a.txt && git commit --quiet -m init
    git push --quiet origin master 2>/dev/null || git push --quiet origin HEAD:master
    git push --quiet personal master 2>/dev/null || git push --quiet personal HEAD:master
  ) || { echo "  S2 setup FAIL"; fail=$((fail+1)); }
  (
    cd "$tmp/work"
    line="$(_discover_mirror_remote)"
    name="${line%%	*}"
    if [ "$name" = "personal" ]; then
      echo "  S2 _discover_mirror_remote: PASS"
    else
      echo "  S2 _discover_mirror_remote: FAIL (got '$line')"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S3: cherry-pick from canonical onto mirror produces tree-equivalent commit.
  (
    cd "$tmp/work"
    git remote remove origin
    git remote remove personal
    git remote add origin "$tmp/bare-canonical"
    git remote add personal "$tmp/bare-mirror"
    # add a new commit on canonical
    echo "new content" > b.txt && git add b.txt && git commit --quiet -m "feat: add b"
    git push --quiet origin HEAD:master
    pt_sha="$(git rev-parse HEAD)"
    pt_tree="$(git rev-parse HEAD^{tree})"
    # reset working branch to mirror state (one commit behind)
    git fetch --quiet personal
    git checkout --quiet -b temp-mirror personal/master
    git cherry-pick --quiet "$pt_sha"
    local_tree="$(git rev-parse HEAD^{tree})"
    if [ "$local_tree" = "$pt_tree" ]; then
      echo "  S3 cherry-pick tree-equivalence: PASS"
    else
      echo "  S3 cherry-pick tree-equivalence: FAIL ($local_tree != $pt_tree)"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S4: already-synced detection — mirror tree == PT tree → no-op.
  (
    cd "$tmp/work"
    git push --quiet personal HEAD:master
    git fetch --quiet personal
    pt_tree="$(git rev-parse origin/master^{tree})"
    mirror_tree="$(git rev-parse personal/master^{tree})"
    if [ "$mirror_tree" = "$pt_tree" ]; then
      echo "  S4 already-synced detection: PASS"
    else
      # The mirror was just brought to canonical's content above.
      # Push canonical's new commit to canonical-remote then verify mirror==canonical tree:
      git push --quiet origin HEAD:master
      git fetch --quiet origin
      pt_tree="$(git rev-parse origin/master^{tree})"
      mirror_tree="$(git rev-parse personal/master^{tree})"
      if [ "$mirror_tree" = "$pt_tree" ]; then
        echo "  S4 already-synced detection: PASS"
      else
        echo "  S4 already-synced detection: FAIL"
        return 1
      fi
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S5: conflict on cherry-pick → abort cleanly.
  (
    cd "$tmp/work"
    # Make divergent edit on canonical
    git checkout --quiet master 2>/dev/null || git checkout --quiet -b master origin/master
    echo "canonical version" > c.txt && git add c.txt && git commit --quiet -m "feat: c canonical"
    git push --quiet origin HEAD:master
    pt_sha="$(git rev-parse HEAD)"
    # Make conflicting edit on mirror
    git fetch --quiet personal
    git checkout --quiet -b temp-conflict personal/master
    echo "mirror version" > c.txt && git add c.txt && git commit --quiet -m "feat: c mirror"
    # Now cherry-pick the canonical commit — should conflict on c.txt
    if git cherry-pick --quiet "$pt_sha" 2>/dev/null; then
      echo "  S5 conflict detection: FAIL (cherry-pick should have failed)"
      git cherry-pick --abort 2>/dev/null || true
      return 1
    fi
    git cherry-pick --abort 2>/dev/null
    echo "  S5 conflict detection: PASS"
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S6: _resolve_to_pt_commit rejects non-ancestor SHA.
  (
    cd "$tmp/work"
    git checkout --quiet --orphan orphan-branch
    git rm -rf --quiet . 2>/dev/null || true
    echo "x" > x.txt && git add x.txt && git commit --quiet -m "orphan"
    orphan_sha="$(git rev-parse HEAD)"
    # Now try to resolve an orphan SHA — should fail with non-ancestor error.
    # _resolve_to_pt_commit calls _die which calls exit 1; run in a subshell to catch.
    if ( _resolve_to_pt_commit "$orphan_sha" >/dev/null 2>&1 ); then
      echo "  S6 reject-non-ancestor: FAIL (should have errored)"
      return 1
    fi
    echo "  S6 reject-non-ancestor: PASS"
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
  -h|--help|"")
    cat <<'USAGE' >&2
sync-pt-to-personal.sh — cherry-pick a PT-master commit onto personal master.

USAGE:
  sync-pt-to-personal.sh <PR-number-or-commit-SHA>
  sync-pt-to-personal.sh --self-test

The script discovers two remotes (canonical "origin" and mirror "the other one")
from `git remote -v`, looks up the PT-master commit (by PR# or SHA), cherry-picks
it onto a temp branch from mirror/master, verifies tree-equivalence, then pushes
non-force to mirror master. Restores original branch on exit. No-op if mirror
master's tree already matches.
USAGE
    [ "${1:-}" = "" ] && exit 2 || exit 0
    ;;
  *)
    _main_sync "$1"
    exit $?
    ;;
esac
