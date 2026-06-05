#!/usr/bin/env bash
# coord-push.sh — push THIS machine's cross-machine coordination state to the
# private `workstreams-coordination` repo via a LOCAL CLONE + git-over-SSH.
#
# Task 2 of docs/plans/cross-machine-workstreams-coordination-2026-06-04.md.
#
# WHAT IT DOES
# Writes this machine's `tree-state/<hostname>.json` (the GUI snapshot, in the
# {hostname, pushed_at, snapshot:{nodes:[...]}} envelope from the coord repo's
# SCHEMA.md) into a local clone of the coordination repo, then commits + pushes
# tree-state/tasks/claims changes. Peers read it back via coord-pull.sh.
#
# WHY git-over-SSH (NOT the gh Contents API)
# The gh Contents API uses the *active* gh account; the operator's work account
# vs personal account causes account-blindness (a 403/404 = wrong account, not
# missing). git-over-SSH against the clone's existing personal-account SSH
# remote has NO gh-account dependency — this is the lesson from the
# gh-account-blindness bug. See the plan + ADR 051.
#
# SUBCOMMANDS
#   push          (default) — write tree-state, commit, push (pull-rebase on non-ff)
#   --self-test              — exercise the logic against a TEMP bare repo
#   --help
#
# CONFIG RESOLUTION (no hardcoded personal repo URL in this committed script)
#   COORD_REPO_URL env  >  ~/.claude/local/coord-repo-url.txt  >  existing
#   clone's origin URL  >  WARN + exit 0 (non-blocking).
#   COORD_CLONE_DIR env >  ~/claude-projects/workstreams-coordination (default).
#   COORD_BRANCH env    >  main (default).
#
# SAFETY
# - NEVER force-pushes (git-discipline.md Rule 1). Non-ff → pull --rebase (cap 2)
#   → push; persistent non-ff → WARN + exit 0 (assisted mode tolerates a retry
#   next cadence).
# - Atomic tree-state write (tmp + rename in the same dir).
# - Throttled: skips silently if the last successful push was < 600s ago
#   (override with --force or COORD_PUSH_THROTTLE_SECONDS).
# - exit 0 on no-op (nothing changed) and on any non-fatal degradation.

set -u

# ============================================================
# Constants / config
# ============================================================
COORD_CLONE_DIR="${COORD_CLONE_DIR:-$HOME/claude-projects/workstreams-coordination}"
COORD_BRANCH="${COORD_BRANCH:-main}"
COORD_PUSH_THROTTLE_SECONDS="${COORD_PUSH_THROTTLE_SECONDS:-600}"
WORKSTREAMS_STATE_DIR="${WORKSTREAMS_STATE_DIR:-$HOME/claude-projects/neural-lace/neural-lace/workstreams-ui/state}"
STATE_DIR="${STATE_DIR:-${HOME}/.claude/state/coord-sync}"
LAST_PUSH_FILE="${LAST_PUSH_FILE:-$STATE_DIR/last-push}"
LOCAL_CONFIG_URL_FILE="${HOME}/.claude/local/coord-repo-url.txt"
REBASE_RETRY_CAP=2

_log()  { printf '[coord-push] %s\n' "$*" >&2; }
_warn() { printf '[coord-push] WARN: %s\n' "$*" >&2; }

# ------------------------------------------------------------
# Resolve the coordination repo URL (config-first; never hardcoded).
# Echoes the URL on stdout; empty string if unresolved.
# ------------------------------------------------------------
_resolve_repo_url() {
  if [ -n "${COORD_REPO_URL:-}" ]; then printf '%s' "$COORD_REPO_URL"; return 0; fi
  if [ -f "$LOCAL_CONFIG_URL_FILE" ]; then
    local u; u=$(head -n1 "$LOCAL_CONFIG_URL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
  fi
  # Fall back to the existing clone's origin (so the script works on a machine
  # that already cloned the repo without needing the config file).
  if [ -d "$1/.git" ]; then
    local u2; u2=$(git -C "$1" remote get-url origin 2>/dev/null || echo "")
    if [ -n "$u2" ]; then printf '%s' "$u2"; return 0; fi
  fi
  printf ''
}

_hostname() {
  local h; h=$(hostname 2>/dev/null || echo "")
  [ -n "$h" ] || h="${COMPUTERNAME:-${HOSTNAME:-unknown-host}}"
  printf '%s' "$h"
}

_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_epoch_now() { date -u +%s; }

# ------------------------------------------------------------
# Ensure a clone exists at $1, cloning from $2 (URL) on branch $3 if missing.
# Returns 0 if a usable clone is present afterward, 1 otherwise.
# ------------------------------------------------------------
_ensure_clone() {
  local dir="$1" url="$2" branch="$3"
  if [ -d "$dir/.git" ]; then return 0; fi
  if [ -z "$url" ]; then return 1; fi
  _log "clone missing — cloning $url -> $dir"
  mkdir -p "$(dirname "$dir")" 2>/dev/null || true
  if git clone --branch "$branch" "$url" "$dir" >/dev/null 2>&1; then return 0; fi
  # Branch may not exist yet on a fresh repo; try a plain clone.
  if git clone "$url" "$dir" >/dev/null 2>&1; then return 0; fi
  return 1
}

# ------------------------------------------------------------
# Write tree-state/<host>.json atomically from the live GUI snapshot.
# Returns 0 on success (or graceful skip), echoes nothing.
# ------------------------------------------------------------
_write_tree_state() {
  local clone_dir="$1" host="$2"
  local src="$WORKSTREAMS_STATE_DIR/tree-state.json"
  local out_dir="$clone_dir/tree-state"
  local out="$out_dir/${host}.json"
  mkdir -p "$out_dir" 2>/dev/null || true

  if [ ! -f "$src" ]; then
    _warn "no live tree-state at $src — skipping tree-state write (push tasks/claims only)"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "jq not found — cannot build tree-state envelope; skipping tree-state write"
    return 0
  fi
  local ts; ts=$(_iso_now)
  local tmp="$out_dir/.${host}.json.tmp.$$"
  if ! jq --arg host "$host" --arg ts "$ts" \
        '{hostname:$host, pushed_at:$ts, snapshot:(.snapshot // {nodes:[]})}' \
        "$src" > "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    _warn "failed to build tree-state envelope from $src — skipping tree-state write"
    return 0
  fi
  # No-op guard: if the snapshot is byte-identical to what's already published
  # (ignoring the always-changing pushed_at), don't rewrite — so an unchanged
  # tree produces a true no-op push (exit 0, no commit). pushed_at alone must
  # not churn a commit every cadence.
  if [ -f "$out" ]; then
    local new_snap old_snap
    new_snap=$(jq -cS '.snapshot' "$tmp" 2>/dev/null || echo "x")
    old_snap=$(jq -cS '.snapshot' "$out" 2>/dev/null || echo "y")
    if [ "$new_snap" = "$old_snap" ]; then
      rm -f "$tmp" 2>/dev/null || true
      return 0
    fi
  fi
  mv -f "$tmp" "$out"
  return 0
}

# ------------------------------------------------------------
# Commit staged changes (if any) and push with pull-rebase-on-non-ff.
# Echoes "noop" | "pushed" | "local-commit" on stdout.
# ------------------------------------------------------------
_commit_and_push() {
  local dir="$1" branch="$2" host="$3"
  git -C "$dir" add -A 2>/dev/null || true
  if git -C "$dir" diff --cached --quiet 2>/dev/null; then
    printf 'noop'; return 0
  fi
  local msg="coord: $host tree-state/claims sync $(_iso_now)"
  if ! git -C "$dir" commit -m "$msg" >/dev/null 2>&1; then
    # Retry with a fallback identity (machine-generated sync commit) so the
    # script works even where no git user.name/user.email is configured.
    if ! git -C "$dir" \
          -c user.email="${GIT_AUTHOR_EMAIL:-coord-sync@localhost}" \
          -c user.name="${GIT_AUTHOR_NAME:-coord-sync}" \
          commit -m "$msg" >/dev/null 2>&1; then
      _warn "commit failed"; printf 'noop'; return 0
    fi
  fi

  # Try push; on non-ff, pull --rebase (cap) then retry. NEVER force.
  local attempt=0
  while [ "$attempt" -le "$REBASE_RETRY_CAP" ]; do
    if git -C "$dir" push origin "HEAD:$branch" >/dev/null 2>&1; then
      printf 'pushed'; return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$REBASE_RETRY_CAP" ]; then break; fi
    _log "push non-ff (attempt $attempt) — pull --rebase then retry"
    if ! git -C "$dir" \
          -c user.email="${GIT_AUTHOR_EMAIL:-coord-sync@localhost}" \
          -c user.name="${GIT_AUTHOR_NAME:-coord-sync}" \
          pull --rebase origin "$branch" >/dev/null 2>&1; then
      git -C "$dir" rebase --abort >/dev/null 2>&1 || true
      _warn "rebase failed — leaving commit local; will retry next cadence"
      printf 'local-commit'; return 0
    fi
  done
  _warn "push still non-ff after $REBASE_RETRY_CAP rebase(s) — commit is local; retry next cadence"
  printf 'local-commit'; return 0
}

# ============================================================
# Main push
# ============================================================
_run_push() {
  local force="${1:-}"
  mkdir -p "$STATE_DIR" 2>/dev/null || true

  # Throttle (unless forced).
  if [ "$force" != "--force" ] && [ -f "$LAST_PUSH_FILE" ]; then
    local last now delta
    last=$(cat "$LAST_PUSH_FILE" 2>/dev/null || echo 0)
    now=$(_epoch_now)
    delta=$((now - last))
    if [ "$delta" -lt "$COORD_PUSH_THROTTLE_SECONDS" ]; then
      _log "throttled (${delta}s < ${COORD_PUSH_THROTTLE_SECONDS}s since last push) — skipping"
      return 0
    fi
  fi

  local url; url=$(_resolve_repo_url "$COORD_CLONE_DIR")
  if [ -z "$url" ] && [ ! -d "$COORD_CLONE_DIR/.git" ]; then
    _warn "no coord repo URL (set COORD_REPO_URL or $LOCAL_CONFIG_URL_FILE) and no existing clone — nothing to push"
    return 0
  fi
  if ! _ensure_clone "$COORD_CLONE_DIR" "$url" "$COORD_BRANCH"; then
    _warn "could not ensure clone at $COORD_CLONE_DIR — skipping"
    return 0
  fi

  local host; host=$(_hostname)
  _write_tree_state "$COORD_CLONE_DIR" "$host"

  local result; result=$(_commit_and_push "$COORD_CLONE_DIR" "$COORD_BRANCH" "$host")
  case "$result" in
    pushed)       _log "pushed coordination state ($host)"; _epoch_now > "$LAST_PUSH_FILE" ;;
    local-commit) _log "committed locally (push deferred)"; _epoch_now > "$LAST_PUSH_FILE" ;;
    noop)         _log "no changes to push" ;;
  esac
  return 0
}

# ============================================================
# Self-test (TEMP bare repo — never touches the live coord repo)
# ============================================================
_self_test() {
  local pass=0 fail=0
  local tmproot; tmproot=$(mktemp -d 2>/dev/null || echo "/tmp/coord-push-st.$$")
  mkdir -p "$tmproot"
  local bare="$tmproot/origin.git" clone="$tmproot/clone" work="$tmproot/work"
  local fakehost="TEST_HOST"

  _ck() { # name, condition(0=pass)
    if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "  PASS: $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi
  }

  # Bootstrap a bare origin with an initial commit on main.
  git init --bare -b main "$bare" >/dev/null 2>&1
  git clone "$bare" "$clone" >/dev/null 2>&1
  git -C "$clone" -c user.email=t@t -c user.name=t commit --allow-empty -m init >/dev/null 2>&1
  git -C "$clone" push -u origin HEAD:main >/dev/null 2>&1
  rm -rf "$clone"

  # Fake a live workstreams tree-state with a snapshot.
  mkdir -p "$work/wstate"
  cat > "$work/wstate/tree-state.json" <<'JSON'
{"schema_version":1,"snapshot":{"nodes":[{"node_id":"n1","title":"t","state":"open"}]}}
JSON

  # --- Scenario 1: missing-clone bootstrap + first push writes tree-state ---
  (
    export COORD_REPO_URL="$bare"
    export COORD_CLONE_DIR="$clone"
    export COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate"
    export COORD_PUSH_THROTTLE_SECONDS=0
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  [ -d "$clone/.git" ]; _ck "missing-clone bootstrap (clone created)" $?
  [ -f "$clone/tree-state/${fakehost}.json" ] 2>/dev/null
  # hostname is real, so check the actual host file exists instead:
  local hostfile; hostfile=$(ls "$clone/tree-state/"*.json 2>/dev/null | head -n1)
  [ -n "$hostfile" ]; _ck "tree-state file written" $?

  # --- Scenario 2: tree-state envelope shape (hostname/pushed_at/snapshot.nodes) ---
  if [ -n "$hostfile" ] && command -v jq >/dev/null 2>&1; then
    jq -e '.hostname and .pushed_at and (.snapshot.nodes|type=="array") and (.snapshot.nodes[0].node_id=="n1")' "$hostfile" >/dev/null 2>&1
    _ck "tree-state-write-shape (envelope + snapshot preserved)" $?
  else
    _ck "tree-state-write-shape (envelope + snapshot preserved)" 1
  fi

  # --- Scenario 3: pushed to origin (origin/main advanced) ---
  git -C "$clone" fetch origin >/dev/null 2>&1
  local local_sha remote_sha
  local_sha=$(git -C "$clone" rev-parse HEAD 2>/dev/null)
  remote_sha=$(git -C "$clone" rev-parse origin/main 2>/dev/null)
  [ -n "$local_sha" ] && [ "$local_sha" = "$remote_sha" ]; _ck "first push reached origin" $?

  # --- Scenario 4: no-op second push exits 0 (no new commit) ---
  local before_sha; before_sha=$(git -C "$clone" rev-parse HEAD)
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  local rc=$?
  local after_sha; after_sha=$(git -C "$clone" rev-parse HEAD)
  [ "$rc" -eq 0 ] && [ "$before_sha" = "$after_sha" ]; _ck "no-op push exits 0, no new commit" $?

  # --- Scenario 5: conflict-rebase path (peer pushes between writes) ---
  # Simulate a peer commit on origin, then change local tree-state and push:
  # the push must non-ff, rebase, and succeed (origin gets both commits).
  local peer="$tmproot/peer"
  git clone "$bare" "$peer" >/dev/null 2>&1
  echo '{"hostname":"PEER","pushed_at":"x","snapshot":{"nodes":[]}}' > "$peer/tree-state/PEER.json"
  git -C "$peer" -c user.email=p@p -c user.name=p add -A >/dev/null 2>&1
  git -C "$peer" -c user.email=p@p -c user.name=p commit -m "peer" >/dev/null 2>&1
  git -C "$peer" push origin HEAD:main >/dev/null 2>&1
  # Mutate the live snapshot so the local push has a new commit to make.
  cat > "$work/wstate/tree-state.json" <<'JSON'
{"schema_version":1,"snapshot":{"nodes":[{"node_id":"n2","title":"t2","state":"open"}]}}
JSON
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  git -C "$peer" fetch origin >/dev/null 2>&1
  # Origin should now contain BOTH the peer file and the local host file.
  git -C "$peer" cat-file -e "origin/main:tree-state/PEER.json" 2>/dev/null; local has_peer=$?
  local hostbase; hostbase=$(basename "$hostfile" 2>/dev/null)
  git -C "$peer" cat-file -e "origin/main:tree-state/$hostbase" 2>/dev/null; local has_host=$?
  [ "$has_peer" -eq 0 ] && [ "$has_host" -eq 0 ]; _ck "conflict-rebase path (both commits on origin)" $?

  # --- Scenario 6: unresolved URL + no clone → WARN + exit 0 (non-blocking) ---
  (
    unset COORD_REPO_URL
    export COORD_CLONE_DIR="$tmproot/nope" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    HOME="$tmproot/nohome" STATE_DIR="$tmproot/state2" LAST_PUSH_FILE="$tmproot/state2/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  _ck "unresolved URL + no clone exits 0 (non-blocking)" $?

  rm -rf "$tmproot" 2>/dev/null || true
  echo "[self-test] coord-push: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# ============================================================
# Entry
# ============================================================
SELF_PATH="${BASH_SOURCE[0]}"

case "${1:-push}" in
  --self-test) _self_test; exit $? ;;
  --help|-h)
    sed -n '2,40p' "$SELF_PATH" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  push)        _run_push "${2:-}"; exit $? ;;
  --force)     _run_push "--force"; exit $? ;;
  *)           _warn "unknown subcommand: $1"; exit 0 ;;
esac
