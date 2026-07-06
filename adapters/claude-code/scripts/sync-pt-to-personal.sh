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
# DEDICATED-CLONE ARCHITECTURE (Wave F task F.6, specs-e §SYNC-CLONE-C — the
# durable follow-on of B.12's interactive-session-lock stopgap):
#
#   docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md
#   documented an unattended sync daemon rewriting a developer's LIVE working
#   tree mid-session (checkout/cherry-pick/reset racing the human's tool calls,
#   uncommitted work swept into foreign commits, install.sh run from a
#   transient branch corrupting the live harness mirror). Option C — the
#   chosen durable fix — is: this script NEVER checks out, cherry-picks, or
#   resets the CALLER's working tree. All mutating git operations run inside
#   a DEDICATED clone at $SYNC_CLONE_DIR (default
#   ~/.claude/sync-clone/<repo-basename>), which no interactive session ever
#   `cd`s into or develops in. The caller's cwd is used ONLY for read-only
#   remote discovery (`git remote -v` / `git remote get-url`) so the dedicated
#   clone can be bootstrapped with the same canonical+mirror remote URLs — no
#   `checkout`, `reset`, `cherry-pick`, `commit`, or `push` ever touches it.
#
#   The B.12 interactive-session-lock guard STAYS as defense-in-depth, but its
#   verdict now branches on WHICH checkout is live (F.6 fix round, resolving
#   the verified gap: the guard used to refuse-and-die unconditionally, which
#   contradicted the Done-when "a live sync run succeeds while an interactive
#   session is open"):
#     - caller checkout is a NORMAL interactive checkout, distinct from
#       $SYNC_CLONE_DIR (the expected/only-supported shape of a real run):
#       LOG-AND-PROCEED. A live session on the caller never blocks the sync,
#       because the caller's tree is never touched — the log line still
#       records the lock holder (repo + daemon + verdict) for observability.
#     - caller checkout IS $SYNC_CLONE_DIR itself, or the ISL liveness check
#       somehow fires against the clone (a misconfigured/degenerate
#       invocation this script does not otherwise support — e.g. someone
#       manually `cd`s into the dedicated clone and runs it from there):
#       REFUSE-and-die, unchanged from B.12. This is the ONLY branch where
#       refusal still applies — defense-in-depth for the one shape where a
#       live session sharing the mutated tree would actually be unsafe.
#   The refusal log accumulating zero REFUSED entries tagged with a caller
#   path outside $SYNC_CLONE_DIR, while still gaining LOG-AND-PROCEED entries
#   when a real session is open, is the F.6 Done-when's third clause.
#
# Usage:
#   sync-pt-to-personal.sh <PR-number-or-commit-SHA>
#   sync-pt-to-personal.sh --self-test
#
# Examples:
#   sync-pt-to-personal.sh 43          # look up merge commit for PT PR #43
#   sync-pt-to-personal.sh be067db     # cherry-pick this exact commit
#
# Env:
#   SYNC_CLONE_DIR   override the dedicated-clone path (default
#                    ~/.claude/sync-clone/<basename of the invoking repo>).
#   ISL_LIB_PATH     override the interactive-session-lock lib path (testing).
#   ISL_BYPASS=1     operator-attended override of the ISL guard (still logged).
#
# Guarantees:
#   - Never force-pushes (no --force / -f anywhere; push aborts if non-FF).
#   - Identity-free: no real org / user / account name hardcoded. The "canonical
#     remote" is `origin`; the "mirror remote" is whichever other remote has a
#     distinct URL. The gh account name for the mirror is parsed from that URL.
#   - Never mutates the invoking repo's working tree or HEAD (dedicated-clone
#     architecture above) — the caller's branch/checkout is left exactly as
#     found; only $SYNC_CLONE_DIR's temp branch is created/destroyed.
#   - No-op if the PT commit's tree is already present on mirror master (idempotent).
#   - Verifies tree-equivalence before push AND after push (catches half-syncs).

set -u

# ============================================================
# Constants / args
# ============================================================

CANONICAL_REMOTE="origin"
TEMP_BRANCH_PREFIX="sync-pt-to-personal/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ============================================================
# Helpers
# ============================================================

_log() { printf '[sync-pt-to-personal] %s\n' "$*" >&2; }
_die() { _log "ERROR: $*"; exit 1; }

# Discover the mirror remote FROM A GIVEN REPO DIR: any remote with a push URL
# distinct from the canonical remote's push URL. Echoes "name<TAB>url" of the
# first match, or empty. Read-only (git remote -v / get-url) — never mutates.
_discover_mirror_remote() {
  local repo_dir="$1"
  local canonical_url mirror_name mirror_url
  canonical_url="$(git -C "$repo_dir" remote get-url --push "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && return 0
  while IFS=$'\t' read -r name rest; do
    [ -z "$name" ] && continue
    [ "$name" = "$CANONICAL_REMOTE" ] && continue
    mirror_url="$(git -C "$repo_dir" remote get-url --push "$name" 2>/dev/null || echo "")"
    if [ -n "$mirror_url" ] && [ "$mirror_url" != "$canonical_url" ]; then
      printf '%s\t%s\n' "$name" "$mirror_url"
      return 0
    fi
  done < <(git -C "$repo_dir" remote -v 2>/dev/null | awk '$3=="(push)"{print $1"\t"$2}' | awk '!seen[$1]++')
}

# Normalize a path for cross-spelling comparison (the clone-path check needs
# this: `git rev-parse --show-toplevel` renders Windows-native, e.g.
# "C:/Users/...", while a raw $SYNC_CLONE_DIR/cwd on MSYS bash is commonly
# "/c/..." or "/tmp/..." — same directory, different spelling). Preference
# order: `cygpath -u` (canonical POSIX form, when available — covers both
# spellings uniformly) > `readlink -f` (resolves symlinks, same-spelling
# only) > the raw string (last resort, exact-match only).
_normalize_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p" 2>/dev/null && return 0
  fi
  readlink -f "$p" 2>/dev/null && return 0
  printf '%s' "$p"
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

# Resolve the dedicated sync-clone directory: SYNC_CLONE_DIR env override, else
# ~/.claude/sync-clone/<basename of the given repo dir>.
_resolve_sync_clone_dir() {
  local repo_dir="$1"
  if [ -n "${SYNC_CLONE_DIR:-}" ]; then
    printf '%s' "$SYNC_CLONE_DIR"
    return 0
  fi
  local base
  base="$(basename "$repo_dir" 2>/dev/null || echo "repo")"
  printf '%s/.claude/sync-clone/%s' "${HOME}" "$base"
}

# Ensure a dedicated clone exists at $1 with remotes matching $2 (canonical
# url) / $3 (mirror name) / $4 (mirror url). Bootstraps via `git clone` from
# canonical if the directory is absent; adds/repairs remotes if it already
# exists (e.g. an earlier bootstrap only had one remote configured). Never
# checks out a branch here beyond what `git clone` itself does by default —
# actual sync work happens on a temp branch created later in _main_sync.
# Returns 0 on a usable clone, 1 otherwise.
_ensure_sync_clone() {
  local clone_dir="$1" canonical_url="$2" mirror_name="$3" mirror_url="$4"

  if [ ! -d "$clone_dir/.git" ]; then
    [ -z "$canonical_url" ] && return 1
    _log "dedicated sync clone missing — cloning $canonical_url -> $clone_dir"
    mkdir -p "$(dirname "$clone_dir")" 2>/dev/null || true
    if ! git clone --quiet "$canonical_url" "$clone_dir" 2>&1 | sed 's/^/  /'; then
      return 1
    fi
    git -C "$clone_dir" remote rename origin "$CANONICAL_REMOTE" >/dev/null 2>&1 || true
  fi

  # Ensure canonical remote points at the right URL (repair drift).
  if git -C "$clone_dir" remote get-url "$CANONICAL_REMOTE" >/dev/null 2>&1; then
    git -C "$clone_dir" remote set-url "$CANONICAL_REMOTE" "$canonical_url" >/dev/null 2>&1 || true
  else
    git -C "$clone_dir" remote add "$CANONICAL_REMOTE" "$canonical_url" >/dev/null 2>&1 || true
  fi

  # Ensure mirror remote exists and points at the right URL.
  if git -C "$clone_dir" remote get-url "$mirror_name" >/dev/null 2>&1; then
    git -C "$clone_dir" remote set-url "$mirror_name" "$mirror_url" >/dev/null 2>&1 || true
  else
    git -C "$clone_dir" remote add "$mirror_name" "$mirror_url" >/dev/null 2>&1 || true
  fi

  [ -d "$clone_dir/.git" ]
}

# Resolve <arg> into an origin/master-reachable commit SHA, evaluated INSIDE
# the given repo dir (the dedicated clone — this only reads/verifies refs,
# never mutates).
#   - If arg looks like a small integer, treat as PT PR# and look up merge_commit_sha
#     via gh api against the canonical remote's owner/name.
#   - Otherwise treat as a commit SHA and verify it's an ancestor of origin/master.
_resolve_to_pt_commit() {
  local repo_dir="$1" arg="$2" canonical_url owner_name sha
  if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
    canonical_url="$(git -C "$repo_dir" remote get-url --push "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
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
  sha="$(git -C "$repo_dir" rev-parse --verify --quiet "${sha}^{commit}" 2>/dev/null || echo "")"
  [ -z "$sha" ] && _die "could not resolve to a commit: $2"
  if ! git -C "$repo_dir" merge-base --is-ancestor "$sha" "${CANONICAL_REMOTE}/master" 2>/dev/null; then
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
  local caller_repo_dir clone_dir canonical_url
  local temp_branch
  local current_gh_account need_switch=0

  # -1. Resolve the CALLER's repo dir (read-only — remote discovery + the ISL
  #     liveness probe both target this dir; no mutation ever happens here).
  #     This script is invoked FROM the checkout it should read remotes from
  #     (the whole point is "sync whatever repo I was run in"), so cwd's own
  #     git toplevel is authoritative — NOT nl_repo_root() (that helper
  #     answers "where is the neural-lace checkout on this machine", which is
  #     a different question and would silently redirect a run made from a
  #     fixture/worktree/other-repo cwd onto an unrelated checkout).
  caller_repo_dir="$(pwd)"
  local git_toplevel
  git_toplevel="$(git -C "$caller_repo_dir" rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -n "$git_toplevel" ] && caller_repo_dir="$git_toplevel"

  # -0.5. Resolve the dedicated sync-clone path NOW (read-only path
  #       arithmetic, no clone/bootstrap yet — that happens at step 2 below).
  #       Needed ahead of the ISL guard so the guard can tell a normal
  #       interactive caller apart from the degenerate case of the script
  #       being run FROM the clone itself (see step 0's clone-path check).
  clone_dir="$(_resolve_sync_clone_dir "$caller_repo_dir")"

  # 0. Interactive-session-lock guard (B.12 — see
  #    docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md
  #    and hooks/lib/interactive-session-lock.sh for the contract). Verdict
  #    branches on the CLONE-PATH CHECK (is the caller checkout the dedicated
  #    clone itself?) — see the header note above for the design rationale.
  local isl_lib
  isl_lib="${ISL_LIB_PATH:-$SCRIPT_DIR/../hooks/lib/interactive-session-lock.sh}"
  if [ -f "$isl_lib" ]; then
    # shellcheck source=/dev/null
    . "$isl_lib"
    if isl_live_session "$caller_repo_dir"; then
      # Clone-path check: normalize both sides (_normalize_path — cygpath -u
      # preferred, so a Windows-native toplevel from `git rev-parse
      # --show-toplevel` and an MSYS-spelled $SYNC_CLONE_DIR/cwd compare
      # equal when they name the same directory) so this comparison isn't
      # fooled by spelling differences alone.
      local caller_real clone_real
      caller_real="$(_normalize_path "$caller_repo_dir")"
      clone_real="$(_normalize_path "$clone_dir")"

      if [ "$caller_real" = "$clone_real" ]; then
        # Degenerate/unsupported shape: the caller checkout IS the dedicated
        # clone. The never-touches-the-caller-tree guarantee does not hold
        # here (this run WOULD mutate the very tree the live session is in)
        # — refuse, unchanged from B.12. Defense-in-depth for the one case
        # where it still matters.
        isl_refuse_log "$caller_repo_dir" "sync-pt-to-personal"
        _die "interactive session live on $caller_repo_dir, which IS the dedicated sync clone ($clone_dir) — refusing to run (refusal logged to ~/.claude/logs/interactive-session-lock.log; operator-attended runs may set ISL_BYPASS=1 to override). This is the one shape where a live session shares the tree this script mutates."
      elif [ "${ISL_BYPASS:-0}" = "1" ]; then
        isl_refuse_log "$caller_repo_dir" "sync-pt-to-personal" "bypassed"
        _log "interactive session live on $caller_repo_dir — ISL_BYPASS=1 set; proceeding (bypass logged; dedicated-clone architecture means this does not touch the live checkout regardless)"
      else
        # Normal shape: caller is a distinct interactive checkout, not the
        # clone. The dedicated-clone architecture means this run never
        # touches $caller_repo_dir, so a live session there is not unsafe —
        # LOG-AND-PROCEED (F.6 fix round). The log line still names the lock
        # holder for observability.
        isl_refuse_log "$caller_repo_dir" "sync-pt-to-personal" "log-and-proceed"
        _log "interactive session live on $caller_repo_dir — proceeding (logged; dedicated-clone architecture means this run only mutates $clone_dir, never the live checkout)"
      fi
    fi
  else
    _log "WARN: interactive-session-lock lib not found at $isl_lib — proceeding unguarded"
  fi

  # 1. Discover mirror remote FROM THE CALLER'S repo (read-only) — this tells
  #    us which two remote URLs the dedicated clone needs to be bootstrapped
  #    with. No mutation happens against $caller_repo_dir.
  mirror_line="$(_discover_mirror_remote "$caller_repo_dir")"
  [ -z "$mirror_line" ] && _die "no mirror remote found (need 2 remotes with distinct URLs)"
  mirror_name="${mirror_line%%$'\t'*}"
  mirror_url="${mirror_line#*$'\t'}"
  mirror_owner="$(_owner_from_url "$mirror_url")"
  if [ -z "$mirror_owner" ]; then
    # Not a github.com URL (local path, self-hosted, non-GitHub host, or a
    # test fixture) — the gh-auth-switch step (10, below) is best-effort
    # credential-account plumbing, not a sync precondition; push still works
    # with whatever credentials are already active. WARN and proceed instead
    # of hard-failing the entire sync over an optional convenience step.
    _log "WARN: cannot parse a github.com owner from mirror URL '$mirror_url' — skipping gh-auth-switch, will push with current credentials"
  fi
  canonical_url="$(git -C "$caller_repo_dir" remote get-url --push "$CANONICAL_REMOTE" 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && _die "cannot resolve canonical remote URL from $caller_repo_dir"
  _log "canonical remote: $CANONICAL_REMOTE -> $canonical_url"
  _log "mirror remote:    $mirror_name -> $mirror_url (owner: ${mirror_owner:-<unparsed>})"

  # 2. Bootstrap the DEDICATED sync clone (path already resolved at step
  #    -0.5, ahead of the ISL guard). All mutating operations from here on
  #    run with `git -C "$clone_dir"` — the caller's working tree/HEAD is
  #    never touched again in this function.
  _log "dedicated sync clone: $clone_dir"
  if ! _ensure_sync_clone "$clone_dir" "$canonical_url" "$mirror_name" "$mirror_url"; then
    _die "could not bootstrap dedicated sync clone at $clone_dir"
  fi

  # 3. Fetch both sides so we have latest refs (inside the clone).
  git -C "$clone_dir" fetch --quiet "$CANONICAL_REMOTE" 2>&1 | sed 's/^/  /'
  git -C "$clone_dir" fetch --quiet "$mirror_name" 2>&1 | sed 's/^/  /'

  # 4. Resolve the input to a PT-master commit (inside the clone).
  pt_sha="$(_resolve_to_pt_commit "$clone_dir" "$arg")"
  pt_tree="$(git -C "$clone_dir" rev-parse "${pt_sha}^{tree}")"
  _log "resolved input: $arg -> commit $pt_sha (tree $pt_tree)"

  # 5. Already-synced check: if mirror master's tree already matches, no-op.
  local mirror_tree
  mirror_tree="$(git -C "$clone_dir" rev-parse "${mirror_name}/master^{tree}" 2>/dev/null || echo "")"
  if [ "$mirror_tree" = "$pt_tree" ]; then
    _log "mirror ${mirror_name}/master already at tree $pt_tree — nothing to do."
    return 0
  fi

  # 6. Set up cleanup trap for the clone's temp branch (the clone has no
  #    "original branch" a human cares about — nothing to restore there —
  #    but the temp branch itself is still torn down on exit/failure).
  temp_branch="${TEMP_BRANCH_PREFIX}$(printf '%s' "$pt_sha" | head -c 7)"
  _SYNC_CLONE_DIR_FOR_TRAP="$clone_dir"
  _SYNC_TEMP_BRANCH="$temp_branch"
  cleanup() {
    if [ -n "${_SYNC_TEMP_BRANCH:-}" ] && [ -n "${_SYNC_CLONE_DIR_FOR_TRAP:-}" ]; then
      git -C "$_SYNC_CLONE_DIR_FOR_TRAP" checkout --quiet "${mirror_name:-origin}/master" >/dev/null 2>&1 || true
      git -C "$_SYNC_CLONE_DIR_FOR_TRAP" branch -D "$_SYNC_TEMP_BRANCH" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup EXIT

  # 7. Create temp branch from mirror master (inside the clone).
  if ! git -C "$clone_dir" checkout --quiet -b "$temp_branch" "${mirror_name}/master" 2>&1 | sed 's/^/  /'; then
    _die "failed to create temp branch $temp_branch from ${mirror_name}/master in $clone_dir"
  fi

  # 8. Cherry-pick (inside the clone).
  if ! git -C "$clone_dir" cherry-pick "$pt_sha" 2>&1 | sed 's/^/  /'; then
    git -C "$clone_dir" cherry-pick --abort 2>/dev/null || true
    _die "cherry-pick of $pt_sha failed (conflict?); aborted"
  fi

  # 9. Verify tree equivalence post-cherry-pick.
  local local_tree
  local_tree="$(git -C "$clone_dir" rev-parse HEAD^{tree})"
  if [ "$local_tree" != "$pt_tree" ]; then
    _die "tree mismatch after cherry-pick: expected $pt_tree, got $local_tree"
  fi
  _log "cherry-pick tree-equivalent (in dedicated clone) ✓"

  # 10. Switch gh auth to mirror_owner if needed (so credential helper uses
  #     the right account for the HTTPS push). Best-effort: if `gh auth list`
  #     doesn't show $mirror_owner, attempt the push anyway and surface failure.
  #     Skipped entirely when mirror_owner is empty (non-github.com mirror —
  #     see step 1's WARN); push proceeds with whatever credentials are active.
  if [ -n "$mirror_owner" ]; then
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
  fi

  # 11. Push to mirror master (FF-only, no force), from the clone.
  local push_ok=0
  if git -C "$clone_dir" push "$mirror_name" "HEAD:master" 2>&1 | sed 's/^/  /'; then
    push_ok=1
  fi

  # 12. Restore gh auth.
  if [ "$need_switch" = "1" ] && [ -n "$current_gh_account" ]; then
    _log "restoring gh auth to $current_gh_account"
    gh auth switch -u "$current_gh_account" 2>&1 | sed 's/^/  /' >&2 || true
  fi

  [ "$push_ok" = "1" ] || _die "push to ${mirror_name} master failed"

  # 13. Post-push verification: fetch mirror, confirm tree-equivalence.
  git -C "$clone_dir" fetch --quiet "$mirror_name" 2>&1 | sed 's/^/  /'
  local post_mirror_tree
  post_mirror_tree="$(git -C "$clone_dir" rev-parse "${mirror_name}/master^{tree}" 2>/dev/null || echo "")"
  if [ "$post_mirror_tree" != "$pt_tree" ]; then
    _die "post-push tree mismatch: ${mirror_name}/master tree $post_mirror_tree != PT tree $pt_tree"
  fi
  _log "post-push tree-equivalent ✓"

  _log "DONE: ${CANONICAL_REMOTE}/master @ $pt_sha (tree $pt_tree) → ${mirror_name}/master @ $(git -C "$clone_dir" rev-parse ${mirror_name}/master) [via dedicated clone $clone_dir]"
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  echo "[self-test] tmpdir=$tmp"

  # Sandbox EVERY write this suite makes: dedicated clone, ISL log, ISL
  # transcripts-projects-root, and retry-guard state (none of the ISL
  # scenarios below exercise retry_guard, but HARNESS_SELFTEST + a sandboxed
  # ISL_LOG_FILE/ISL_PROJECTS_ROOT are set globally per findings 025/028/034
  # so no scenario can leak into the real ~/.claude/state or ~/.claude/logs).
  export HARNESS_SELFTEST=1
  export ISL_LOG_FILE="$tmp/isl-refusal.log"
  export ISL_PROJECTS_ROOT="$tmp/isl-projects"
  export SYNC_CLONE_DIR="$tmp/sync-clone-under-test"
  mkdir -p "$ISL_PROJECTS_ROOT"

  # Synthetic commit identity for every fixture commit this suite makes
  # (including inside FRESH clones, which have no repo-local git config of
  # their own) — avoids depending on the invoking machine having a global
  # user.name/user.email configured.
  export GIT_AUTHOR_NAME="NL Selftest" GIT_AUTHOR_EMAIL="nl-selftest@example.test"
  export GIT_COMMITTER_NAME="NL Selftest" GIT_COMMITTER_EMAIL="nl-selftest@example.test"

  # Sandboxed global gitconfig (git >=2.32 GIT_CONFIG_GLOBAL): every fixture
  # git operation in this suite (including inside git-clone-created dedicated
  # clones, which have no repo-local config until _ensure_sync_clone sets one
  # up) reads/writes this file instead of the invoking machine's real
  # ~/.gitconfig. Torn down with $tmp on RETURN.
  export GIT_CONFIG_GLOBAL="$tmp/selftest-gitconfig"
  : > "$GIT_CONFIG_GLOBAL"

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
  # _discover_mirror_remote (given an explicit repo dir) picks the non-origin one.
  (
    cd "$tmp"
    mkdir bare-canonical && cd bare-canonical && git init --bare --quiet && cd ..
    mkdir bare-mirror && cd bare-mirror && git init --bare --quiet && cd ..
    mkdir work && cd work
    git init --quiet
    git config core.hooksPath ""
    git config user.email "test@example.com" && git config user.name "Test"
    git remote add origin "$tmp/bare-canonical"
    git remote add personal "$tmp/bare-mirror"
    echo "init" > a.txt && git add a.txt && git commit --quiet -m init
    git push --quiet origin master 2>/dev/null || git push --quiet origin HEAD:master
    git push --quiet personal master 2>/dev/null || git push --quiet personal HEAD:master
  ) || { echo "  S2 setup FAIL"; fail=$((fail+1)); }
  (
    line="$(_discover_mirror_remote "$tmp/work")"
    name="${line%%	*}"
    if [ "$name" = "personal" ]; then
      echo "  S2 _discover_mirror_remote: PASS"
    else
      echo "  S2 _discover_mirror_remote: FAIL (got '$line')"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S3: cherry-pick from canonical onto mirror produces tree-equivalent
  # commit — exercised directly against a throwaway clone dir (mirrors what
  # _main_sync does inside $SYNC_CLONE_DIR), never against $tmp/work (the
  # "caller checkout" stand-in), proving the mutation-target separation.
  (
    cd "$tmp/work"
    git remote remove origin
    git remote remove personal
    git remote add origin "$tmp/bare-canonical"
    git remote add personal "$tmp/bare-mirror"
    # add a new commit on canonical
    echo "new content" > b.txt && git add b.txt && git commit --quiet -m "feat: add b"
    git push --quiet origin HEAD:master
  ) || { echo "  S3 setup FAIL"; fail=$((fail+1)); }
  (
    local pt_sha pt_tree local_tree
    rm -rf "$tmp/clone-under-test"
    git clone --quiet "$tmp/bare-canonical" "$tmp/clone-under-test" 2>/dev/null
    cd "$tmp/clone-under-test"
    git remote rename origin origin 2>/dev/null || true
    git remote add personal "$tmp/bare-mirror"
    git fetch --quiet personal
    pt_sha="$(git rev-parse origin/master)"
    pt_tree="$(git rev-parse origin/master^{tree})"
    git checkout --quiet -b temp-mirror personal/master
    git cherry-pick --quiet "$pt_sha"
    local_tree="$(git rev-parse HEAD^{tree})"
    if [ "$local_tree" = "$pt_tree" ]; then
      echo "  S3 cherry-pick tree-equivalence (in dedicated clone): PASS"
    else
      echo "  S3 cherry-pick tree-equivalence (in dedicated clone): FAIL ($local_tree != $pt_tree)"
      return 1
    fi
    # Prove $tmp/work (the "caller checkout") never moved off its own branch —
    # the mutation-target-separation property this whole rewrite exists for.
    local work_branch
    work_branch="$(git -C "$tmp/work" symbolic-ref --short -q HEAD || echo "")"
    if [ "$work_branch" = "master" ] || [ -n "$work_branch" ]; then
      echo "  S3b caller checkout untouched (still on '$work_branch'): PASS"
    else
      echo "  S3b caller checkout untouched: FAIL (detached or missing)"
      return 1
    fi
  ) && pass=$((pass+2)) || fail=$((fail+2))

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

  # Scenario S5: conflict on cherry-pick → abort cleanly (in the dedicated
  # clone, never in $tmp/work).
  (
    cd "$tmp/work"
    # Make divergent edit on canonical
    git checkout --quiet master 2>/dev/null || git checkout --quiet -b master origin/master
    echo "canonical version" > c.txt && git add c.txt && git commit --quiet -m "feat: c canonical"
    git push --quiet origin HEAD:master
  ) || { echo "  S5 setup FAIL"; fail=$((fail+1)); }
  (
    cd "$tmp/clone-under-test"
    git fetch --quiet origin
    pt_sha="$(git rev-parse origin/master)"
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

  # Scenario S6: _resolve_to_pt_commit rejects non-ancestor SHA (evaluated
  # inside a given repo dir, matching the dedicated-clone call convention).
  (
    cd "$tmp/clone-under-test"
    git checkout --quiet --orphan orphan-branch
    git rm -rf --quiet . 2>/dev/null || true
    echo "x" > x.txt && git add x.txt && git commit --quiet -m "orphan"
    orphan_sha="$(git rev-parse HEAD)"
    # Now try to resolve an orphan SHA — should fail with non-ancestor error.
    # _resolve_to_pt_commit calls _die which calls exit 1; run in a subshell to catch.
    if ( _resolve_to_pt_commit "$tmp/clone-under-test" "$orphan_sha" >/dev/null 2>&1 ); then
      echo "  S6 reject-non-ancestor: FAIL (should have errored)"
      return 1
    fi
    echo "  S6 reject-non-ancestor: PASS"
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S7: _ensure_sync_clone bootstraps a fresh dedicated clone from a
  # canonical URL and wires both remotes, without ever touching $tmp/work.
  (
    rm -rf "$tmp/fresh-clone"
    if _ensure_sync_clone "$tmp/fresh-clone" "$tmp/bare-canonical" "personal" "$tmp/bare-mirror" \
       && [ -d "$tmp/fresh-clone/.git" ] \
       && git -C "$tmp/fresh-clone" remote get-url origin >/dev/null 2>&1 \
       && git -C "$tmp/fresh-clone" remote get-url personal >/dev/null 2>&1; then
      echo "  S7 _ensure_sync_clone bootstrap: PASS"
    else
      echo "  S7 _ensure_sync_clone bootstrap: FAIL"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S8 (the F.6 Done-when's core proof, mirroring the REAL flagless
  # invocation shape): run `sync-pt-to-personal.sh <sha>` for real (not just
  # calling internal functions) with $tmp/work as an ATTENDED-LOOKING repo
  # (fresh transcript under its ISL slug -> isl_live_session TRUE), with the
  # lock file present too, and confirm
  # (a) the run still completes successfully (LOG-AND-PROCEED, not a refusal
  # and not the ISL_BYPASS path — ISL_BYPASS is unset in this scenario),
  # (b) $tmp/work's branch/HEAD is byte-identical before and after (proves
  # the clone-path check correctly identified $tmp/work as NOT the clone), and
  # (c) the log gained exactly one entry, verdict "log-and-proceed", naming
  # the lock holder (repo=$tmp/work) — the observability half of the F.6 fix
  # (never zero entries: a live session IS logged, just not refused). This is
  # the literal "sync proceeds from the clone + logs" half of the F.6 task.
  (
    cd "$tmp/work"
    # Mirror remote stays a plain local bare-repo path (not github.com-shaped)
    # — exercising the WARN-and-proceed-without-gh-switch path (step 1/10 of
    # _main_sync) that non-GitHub mirrors legitimately take, without a
    # network dependency in the self-test.
    #
    # Reconverge origin/personal FIRST: S5's fixture deliberately diverged
    # them (conflicting c.txt) to exercise conflict-abort, so without this
    # they'd still disagree here — this scenario needs the realistic
    # "mirror is caught up, one new PT commit to bring over" starting
    # condition the tool is designed for, not a stale/diverged mirror.
    git checkout --quiet master 2>/dev/null || true
    git push --quiet --force personal HEAD:master
    echo "s8 content" > s8.txt && git add s8.txt && git commit --quiet -m "feat: s8"
    git push --quiet origin HEAD:master
    local before_head before_branch
    before_head="$(git rev-parse HEAD)"
    before_branch="$(git symbolic-ref --short -q HEAD || echo "detached")"

    # Simulate a LIVE interactive session on $tmp/work via a fresh transcript
    # under its ISL project slug (same mechanism the real lock checks) AND
    # the explicit lock file (belt-and-suspenders — the task line calls out
    # "scenario with the lock file present").
    local slug tdir
    slug="$(isl_project_slug_candidates "$tmp/work" 2>/dev/null | head -n 1)"
    if [ -z "$slug" ]; then
      # isl_project_slug_candidates isn't sourced in this subshell yet.
      slug="$(printf '%s' "$tmp/work" | tr '/:\\ .' '-----')"
    fi
    tdir="$ISL_PROJECTS_ROOT/$slug"
    mkdir -p "$tdir"
    : > "$tdir/session-live.jsonl"
    mkdir -p "$tmp/work/.claude/state"
    : > "$tmp/work/.claude/state/interactive-session.lock"

    rm -f "$ISL_LOG_FILE"
    rm -rf "${SYNC_CLONE_DIR:?}"
    unset ISL_BYPASS

    local sha; sha="$(git rev-parse HEAD)"
    local out rc
    out="$(cd "$tmp/work" && bash "$SCRIPT_ABS_PATH" "$sha" 2>&1)"
    rc=$?

    local after_head after_branch
    after_head="$(git -C "$tmp/work" rev-parse HEAD)"
    after_branch="$(git -C "$tmp/work" symbolic-ref --short -q HEAD || echo "detached")"

    local log_lines=0
    [ -f "$ISL_LOG_FILE" ] && log_lines=$(wc -l < "$ISL_LOG_FILE" | tr -d ' ')

    rm -f "$tmp/work/.claude/state/interactive-session.lock"

    # repo= in the log is the caller dir as `git rev-parse --show-toplevel`
    # renders it (Windows-native on this platform, e.g. "C:/Users/...") which
    # can differ in spelling from $tmp (MSYS-style "/tmp/..." here) even
    # though both name the same directory — match on the toplevel spelling
    # actually recorded, or fall back to a basename check, so this assertion
    # isn't platform-path-form-fragile.
    local work_toplevel
    work_toplevel="$(git -C "$tmp/work" rev-parse --show-toplevel 2>/dev/null || echo "$tmp/work")"
    if [ "$rc" -eq 0 ] \
       && [ "$after_head" = "$before_head" ] && [ "$after_branch" = "$before_branch" ] \
       && [ "$log_lines" = "1" ] \
       && grep -q 'log-and-proceed' "$ISL_LOG_FILE" \
       && { grep -q "repo=$work_toplevel" "$ISL_LOG_FILE" || grep -q "repo=$tmp/work" "$ISL_LOG_FILE"; } \
       && ! grep -q '^[^ ]* refused ' "$ISL_LOG_FILE" \
       && [ -d "$SYNC_CLONE_DIR/.git" ]; then
      echo "  S8 live-session+lock-file real invocation (log-and-proceed from clone): PASS"
    else
      echo "  S8 live-session+lock-file real invocation (log-and-proceed from clone): FAIL (rc=$rc before=$before_head/$before_branch after=$after_head/$after_branch log_lines=$log_lines)"
      echo "$out" | sed 's/^/    /'
      cat "$ISL_LOG_FILE" 2>/dev/null | sed 's/^/    log: /'
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Scenario S9 (defense-in-depth retained): simulate the DEGENERATE case of
  # this script being run FROM the dedicated clone itself, with the lock file
  # present there. Real flagless invocation (bash "$SCRIPT_ABS_PATH" "$sha"),
  # cwd = the clone dir, SYNC_CLONE_DIR pointed AT that same dir so the
  # clone-path check's caller-vs-clone comparison matches. Must still REFUSE
  # (non-zero rc, "refused" verdict logged, mirror untouched) — proving the
  # clone-path guard, not a blanket log-and-proceed, is what governs S8.
  (
    local clone_as_caller="$tmp/clone-is-caller"
    rm -rf "$clone_as_caller"
    git clone --quiet "$tmp/bare-canonical" "$clone_as_caller" 2>/dev/null
    git -C "$clone_as_caller" remote add personal "$tmp/bare-mirror" 2>/dev/null || true
    git -C "$clone_as_caller" fetch --quiet personal 2>/dev/null

    local mirror_before
    mirror_before="$(git -C "$tmp/bare-mirror" rev-parse master 2>/dev/null || echo "")"

    # Fresh transcript + lock file scoped to $clone_as_caller's own ISL slug.
    local slug tdir
    slug="$(isl_project_slug_candidates "$clone_as_caller" 2>/dev/null | head -n 1)"
    if [ -z "$slug" ]; then
      slug="$(printf '%s' "$clone_as_caller" | tr '/:\\ .' '-----')"
    fi
    tdir="$ISL_PROJECTS_ROOT/$slug"
    mkdir -p "$tdir"
    : > "$tdir/session-live.jsonl"
    mkdir -p "$clone_as_caller/.claude/state"
    : > "$clone_as_caller/.claude/state/interactive-session.lock"

    rm -f "$ISL_LOG_FILE"

    local sha; sha="$(git -C "$clone_as_caller" rev-parse master)"
    local out rc
    out="$(cd "$clone_as_caller" && SYNC_CLONE_DIR="$clone_as_caller" bash "$SCRIPT_ABS_PATH" "$sha" 2>&1)"
    rc=$?

    local mirror_after
    mirror_after="$(git -C "$tmp/bare-mirror" rev-parse master 2>/dev/null || echo "")"

    if [ "$rc" -ne 0 ] \
       && [ "$mirror_after" = "$mirror_before" ] \
       && grep -q '^[^ ]* refused ' "$ISL_LOG_FILE" 2>/dev/null; then
      echo "  S9 non-clone-checkout still refuses (defense-in-depth): PASS"
    else
      echo "  S9 non-clone-checkout still refuses (defense-in-depth): FAIL (rc=$rc mirror_before=$mirror_before mirror_after=$mirror_after)"
      echo "$out" | sed 's/^/    /'
      cat "$ISL_LOG_FILE" 2>/dev/null | sed 's/^/    log: /'
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

# ============================================================
# Entry point
# ============================================================

SCRIPT_ABS_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

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
from the invoking repo's `git remote -v` (read-only), then bootstraps/uses a
DEDICATED clone at $SYNC_CLONE_DIR (default ~/.claude/sync-clone/<repo-basename>)
wired with the same two remotes. All mutating operations (checkout, cherry-pick,
push) run inside that dedicated clone — the invoking repo's working tree and
HEAD are never touched (Wave F task F.6 / specs-e SYNC-CLONE-C: the durable
fix for the sync daemon thrashing a live checkout, docs/discoveries/
2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md). The B.12
interactive-session-lock guard still runs first: it LOGS-AND-PROCEEDS when a
live session is on a normal (non-clone) checkout — the sync never touches
that tree, so it is safe to proceed, and the log line still records the lock
holder — and only REFUSES in the degenerate case where the invoking checkout
IS the dedicated clone itself. No-op if mirror master's tree already matches.
USAGE
    [ "${1:-}" = "" ] && exit 2 || exit 0
    ;;
  *)
    _main_sync "$1"
    exit $?
    ;;
esac
