#!/usr/bin/env bash
# coord-pull.sh — pull peers' cross-machine coordination state from the private
# `workstreams-coordination` repo into the local clone, via git-over-SSH.
#
# Task 2 of docs/plans/cross-machine-workstreams-coordination-2026-06-04.md.
#
# WHAT IT DOES
# Refreshes the local clone (fetch + fast-forward to origin/<branch>) so peers'
# `tree-state/<peer-host>.json`, the shared `tasks/*.json`, and `claims.json`
# are current. The reconciler (state/reconciler.js) and the Workstreams GUI
# server read those files directly from the clone dir — so a fresh clone IS the
# "merged view input". Prints a one-line summary of what's available.
#
# WHY git-over-SSH (NOT the gh Contents API): see coord-push.sh header — avoids
# gh-account-blindness. ADR 051.
#
# SUBCOMMANDS
#   pull          (default) — fetch + sync the clone to origin
#   --self-test              — exercise the logic against a TEMP bare repo
#   --help
#
# CONFIG RESOLUTION (identical to coord-push.sh)
#   COORD_REPO_URL env  >  ~/.claude/local/coord-repo-url.txt  >  existing
#   clone's origin URL  >  WARN + exit 0 (non-blocking).
#   COORD_CLONE_DIR env >  ~/claude-projects/workstreams-coordination (default).
#   COORD_BRANCH env    >  main (default).
#
# SAFETY
# - Clean working tree → `reset --hard origin/<branch>` (deterministic refresh;
#   the clone is primarily a read-mirror of peers' state).
# - Dirty working tree (uncommitted local task/claims edits awaiting coord-push)
#   → stash -u, reset --hard, stash pop — so peers' state arrives WITHOUT
#   destroying local edits (they replay on top, then coord-push commits them).
#   Pop conflict → the stash is preserved + a WARN is logged (never auto-resolve;
#   git-discipline.md). NEVER force-pushes; pull only reads from origin.
# - exit 0 on no-op, on an unreachable repo, and on any non-fatal degradation
#   (the GUI falls back to a local-only tree).

set -u

# ============================================================
# Constants / config
# ============================================================
COORD_CLONE_DIR="${COORD_CLONE_DIR:-$HOME/claude-projects/workstreams-coordination}"
COORD_BRANCH="${COORD_BRANCH:-main}"
LOCAL_CONFIG_URL_FILE="${HOME}/.claude/local/coord-repo-url.txt"

_log()  { printf '[coord-pull] %s\n' "$*" >&2; }
_warn() { printf '[coord-pull] WARN: %s\n' "$*" >&2; }

_resolve_repo_url() {
  if [ -n "${COORD_REPO_URL:-}" ]; then printf '%s' "$COORD_REPO_URL"; return 0; fi
  if [ -f "$LOCAL_CONFIG_URL_FILE" ]; then
    local u; u=$(head -n1 "$LOCAL_CONFIG_URL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
  fi
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

_ensure_clone() {
  local dir="$1" url="$2" branch="$3"
  if [ -d "$dir/.git" ]; then return 0; fi
  if [ -z "$url" ]; then return 1; fi
  _log "clone missing — cloning $url -> $dir"
  mkdir -p "$(dirname "$dir")" 2>/dev/null || true
  if git clone --branch "$branch" "$url" "$dir" >/dev/null 2>&1; then return 0; fi
  if git clone "$url" "$dir" >/dev/null 2>&1; then return 0; fi
  return 1
}

# ------------------------------------------------------------
# Sync the clone to origin/<branch>, preserving local uncommitted edits.
# Echoes "synced" | "noop" | "diverged".
# ------------------------------------------------------------
_sync_to_origin() {
  local dir="$1" branch="$2"

  if ! git -C "$dir" fetch origin "$branch" >/dev/null 2>&1; then
    _warn "fetch failed (repo unreachable?) — keeping current clone"
    printf 'noop'; return 0
  fi

  local cur tgt
  cur=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")
  tgt=$(git -C "$dir" rev-parse "origin/$branch" 2>/dev/null || echo "")
  if [ -z "$tgt" ]; then _warn "no origin/$branch ref"; printf 'noop'; return 0; fi

  # Dirty working tree? Stash local edits, refresh, replay.
  local dirty=0
  git -C "$dir" diff --quiet 2>/dev/null && git -C "$dir" diff --cached --quiet 2>/dev/null || dirty=1
  # Untracked files also count as local edits worth preserving.
  if [ -n "$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then dirty=1; fi

  if [ "$dirty" -eq 1 ]; then
    local stash_msg="coord-pull-autostash-$(date -u +%Y%m%dT%H%M%SZ)"
    if git -C "$dir" stash push -u -m "$stash_msg" >/dev/null 2>&1; then
      git -C "$dir" reset --hard "origin/$branch" >/dev/null 2>&1
      if git -C "$dir" stash pop >/dev/null 2>&1; then
        printf 'synced'; return 0
      fi
      _warn "stash pop conflict — local edits preserved in 'git stash list' ($stash_msg); resolve manually"
      printf 'diverged'; return 0
    fi
    _warn "stash failed — leaving clone as-is to avoid losing local edits"
    printf 'diverged'; return 0
  fi

  if [ "$cur" = "$tgt" ]; then printf 'noop'; return 0; fi
  git -C "$dir" reset --hard "origin/$branch" >/dev/null 2>&1
  printf 'synced'; return 0
}

# ------------------------------------------------------------
# Print a one-line inventory of the merged-view inputs now available.
# ------------------------------------------------------------
_surface_inputs() {
  local dir="$1" self_host="$2"
  local peers tasks claims
  peers=$(ls "$dir/tree-state/"*.json 2>/dev/null | grep -v "/${self_host}.json$" | wc -l | tr -d ' ')
  tasks=$(ls "$dir/tasks/"*.json 2>/dev/null | wc -l | tr -d ' ')
  claims="absent"; [ -f "$dir/claims.json" ] && claims="present"
  _log "merged-view inputs: ${peers} peer tree-state(s), ${tasks} task(s), claims.json ${claims}"
}

# ============================================================
# Main pull
# ============================================================
_run_pull() {
  local url; url=$(_resolve_repo_url "$COORD_CLONE_DIR")
  if [ -z "$url" ] && [ ! -d "$COORD_CLONE_DIR/.git" ]; then
    _warn "no coord repo URL (set COORD_REPO_URL or $LOCAL_CONFIG_URL_FILE) and no existing clone — GUI uses local-only view"
    return 0
  fi
  if ! _ensure_clone "$COORD_CLONE_DIR" "$url" "$COORD_BRANCH"; then
    _warn "could not ensure clone at $COORD_CLONE_DIR — GUI uses local-only view"
    return 0
  fi

  local result; result=$(_sync_to_origin "$COORD_CLONE_DIR" "$COORD_BRANCH")
  case "$result" in
    synced)   _log "pulled peers' state (synced to origin/$COORD_BRANCH)" ;;
    noop)     _log "already current" ;;
    diverged) ;;  # already WARNed
  esac
  _surface_inputs "$COORD_CLONE_DIR" "$(_hostname)"
  return 0
}

# ============================================================
# Self-test (TEMP bare repo — never touches the live coord repo)
# ============================================================
_self_test() {
  local pass=0 fail=0
  local tmproot; tmproot=$(mktemp -d 2>/dev/null || echo "/tmp/coord-pull-st.$$")
  mkdir -p "$tmproot"
  local bare="$tmproot/origin.git" seed="$tmproot/seed" clone="$tmproot/clone"

  _ck() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "  PASS: $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }

  # Bootstrap origin with a peer tree-state already present.
  git init --bare -b main "$bare" >/dev/null 2>&1
  git clone "$bare" "$seed" >/dev/null 2>&1
  mkdir -p "$seed/tree-state" "$seed/tasks"
  echo '{"hostname":"PEER","pushed_at":"t0","snapshot":{"nodes":[{"node_id":"p1"}]}}' > "$seed/tree-state/PEER.json"
  echo '{"id":"task-x","status":"open"}' > "$seed/tasks/task-x.json"
  echo '{}' > "$seed/claims.json"
  git -C "$seed" -c user.email=s@s -c user.name=s add -A >/dev/null 2>&1
  git -C "$seed" -c user.email=s@s -c user.name=s commit -m seed >/dev/null 2>&1
  git -C "$seed" push -u origin HEAD:main >/dev/null 2>&1

  # --- Scenario 1: missing-clone bootstrap (pull clones if absent) ---
  ( export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    bash "$SELF_PATH" pull >/dev/null 2>&1 )
  [ -d "$clone/.git" ]; _ck "missing-clone bootstrap (clone created)" $?

  # --- Scenario 2: pull gets peer state (peer file present after pull) ---
  [ -f "$clone/tree-state/PEER.json" ]; _ck "pull surfaces peer tree-state" $?

  # --- Scenario 3: fast-forward (origin advances → clean clone follows) ---
  echo '{"hostname":"PEER","pushed_at":"t1","snapshot":{"nodes":[{"node_id":"p2"}]}}' > "$seed/tree-state/PEER.json"
  git -C "$seed" -c user.email=s@s -c user.name=s commit -am advance >/dev/null 2>&1
  git -C "$seed" push origin HEAD:main >/dev/null 2>&1
  ( export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    bash "$SELF_PATH" pull >/dev/null 2>&1 )
  local got_p2=1; command -v jq >/dev/null 2>&1 && \
    { jq -e '.snapshot.nodes[0].node_id=="p2"' "$clone/tree-state/PEER.json" >/dev/null 2>&1 && got_p2=0; } || \
    { grep -q '"p2"' "$clone/tree-state/PEER.json" 2>/dev/null && got_p2=0; }
  _ck "fast-forward path (clean clone follows origin)" $got_p2

  # --- Scenario 4: dirty-tree path (local edit preserved across pull) ---
  # Operator edits a local task awaiting coord-push; peer advances origin too.
  echo '{"id":"task-local","status":"open","notes":"WIP"}' > "$clone/tasks/task-local.json"
  echo '{"hostname":"PEER","pushed_at":"t2","snapshot":{"nodes":[{"node_id":"p3"}]}}' > "$seed/tree-state/PEER.json"
  git -C "$seed" -c user.email=s@s -c user.name=s commit -am advance2 >/dev/null 2>&1
  git -C "$seed" push origin HEAD:main >/dev/null 2>&1
  ( export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    bash "$SELF_PATH" pull >/dev/null 2>&1 )
  local local_kept=1 peer_advanced=1
  [ -f "$clone/tasks/task-local.json" ] && local_kept=0
  grep -q '"p3"' "$clone/tree-state/PEER.json" 2>/dev/null && peer_advanced=0
  [ "$local_kept" -eq 0 ] && [ "$peer_advanced" -eq 0 ]; _ck "dirty-tree: local edit preserved + peer state pulled" $?

  # --- Scenario 5: no-op when already current ---
  ( export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    bash "$SELF_PATH" pull >/dev/null 2>&1 ); _ck "no-op pull exits 0 when current" $?

  # --- Scenario 6: unresolved URL + no clone → exit 0 (non-blocking) ---
  ( unset COORD_REPO_URL
    export COORD_CLONE_DIR="$tmproot/nope" COORD_BRANCH="main"
    HOME="$tmproot/nohome" bash "$SELF_PATH" pull >/dev/null 2>&1 )
  _ck "unresolved URL + no clone exits 0 (non-blocking)" $?

  rm -rf "$tmproot" 2>/dev/null || true
  echo "[self-test] coord-pull: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# ============================================================
# Entry
# ============================================================
SELF_PATH="${BASH_SOURCE[0]}"

case "${1:-pull}" in
  --self-test) _self_test; exit $? ;;
  --help|-h)
    sed -n '2,40p' "$SELF_PATH" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  pull)        _run_pull; exit $? ;;
  *)           _warn "unknown subcommand: $1"; exit 0 ;;
esac
