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
#
# A2 (cockpit-v2-push-materialized-store Task 3, binding architecture-review
# amendment): coord-push is WARN+exit-0 on every failure path BY DESIGN — that
# contract is NOT changed here. Two real gaps in the OLD no-op gate are:
#   (a) AHEAD-OF-ORIGIN RETRY — the old gate returned 'noop' the instant
#       `git diff --cached --quiet` found nothing NEW to stage, even when an
#       EARLIER local commit (e.g. from a prior run whose push/rebase failed)
#       still sits unpushed. One transient failure + a quiet estate (nobody
#       touches tree-state again) meant that commit — and everything after it
#       — never reached origin. Fixed: when there's nothing new to stage,
#       `_ahead_of_origin` checks whether HEAD still differs from this clone's
#       last-known `origin/<branch>` and, if so, attempts the push anyway.
#   (b) OUTCOME STATUS FILE — every invocation now writes
#       `~/.claude/state/coord-push-status.json` (override:
#       COORD_PUSH_STATUS_FILE), atomically, with
#       `{"outcome":"pushed"|"local-commit"|"noop","ts":<iso>,"detail":<str>}`.
#       This lets a caller (coord-sync.sh, Task 3's dedicated cadence) detect
#       a persistent 'local-commit' streak and alert on it (A2c) without
#       parsing stdout/stderr. Writing this file NEVER changes the exit code
#       — WARN+exit-0 stays load-bearing for every existing caller.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
{ source "$SELF_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true

# ============================================================
# Constants / config
# ============================================================
COORD_CLONE_DIR="${COORD_CLONE_DIR:-$HOME/claude-projects/workstreams-coordination}"
COORD_BRANCH="${COORD_BRANCH:-main}"
COORD_PUSH_THROTTLE_SECONDS="${COORD_PUSH_THROTTLE_SECONDS:-600}"
_WORKSTREAMS_STATE_DIR_DEFAULT=""
if command -v nl_workstreams_ui >/dev/null 2>&1; then
  _ui_dir="$(nl_workstreams_ui 2>/dev/null)"
  [[ -n "$_ui_dir" ]] && _WORKSTREAMS_STATE_DIR_DEFAULT="$_ui_dir/state"
fi
[[ -z "$_WORKSTREAMS_STATE_DIR_DEFAULT" ]] && _WORKSTREAMS_STATE_DIR_DEFAULT="$HOME/.claude/state/workstreams-ui-state"
WORKSTREAMS_STATE_DIR="${WORKSTREAMS_STATE_DIR:-$_WORKSTREAMS_STATE_DIR_DEFAULT}"
STATE_DIR="${STATE_DIR:-${HOME}/.claude/state/coord-sync}"
LAST_PUSH_FILE="${LAST_PUSH_FILE:-$STATE_DIR/last-push}"
LOCAL_CONFIG_URL_FILE="${HOME}/.claude/local/coord-repo-url.txt"
STATUS_FILE="${COORD_PUSH_STATUS_FILE:-${HOME}/.claude/state/coord-push-status.json}"
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
# A2a: is HEAD still ahead of (or diverged from) this clone's last-known
# origin/<branch>? Deliberately does NOT fetch first — the failure mode this
# closes is "a PRIOR run's push/rebase failed, leaving a local commit the
# remote-tracking ref never advanced past"; the clone's cached origin/<branch>
# ref already reflects that. (A genuinely stale cached ref just means the
# push attempt below round-trips and, if it turns out there's truly nothing
# new, no-ops at the git-protocol level — cheap and still WARN+exit-0-safe.)
# Echoes nothing; rc 0 = attempt the push, rc 1 = nothing to retry.
# ------------------------------------------------------------
_ahead_of_origin() {
  local dir="$1" branch="$2"
  local head_sha origin_sha
  head_sha=$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null) || return 1
  origin_sha=$(git -C "$dir" rev-parse -q --verify "origin/$branch" 2>/dev/null)
  if [ -z "$origin_sha" ]; then
    # No remote-tracking ref at all (fresh clone / never pushed yet) — a
    # local HEAD existing is itself "ahead" of an empty/unknown origin.
    [ -n "$head_sha" ]; return
  fi
  [ "$head_sha" != "$origin_sha" ]
}

# ------------------------------------------------------------
# A2b: write the outcome status file atomically. Never affects the caller's
# exit code — this is a WRITER, not a gate. detail is free text (escaped).
# ------------------------------------------------------------
_write_status_file() {
  local outcome="$1" detail="${2:-}"
  local dir; dir="$(dirname "$STATUS_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  local ts; ts=$(_iso_now)
  local esc="$detail"
  esc="${esc//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  esc="${esc//$'\n'/ }"
  local tmp="$STATUS_FILE.tmp.$$"
  if printf '{"outcome":"%s","ts":"%s","detail":"%s"}\n' "$outcome" "$ts" "$esc" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$STATUS_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
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
    # No NEW staged changes — but A2a: don't treat that as the whole story.
    # An earlier local commit may still be sitting unpushed (a prior
    # transient push/rebase failure); retry it rather than deferring
    # publication indefinitely on a quiet estate.
    if _ahead_of_origin "$dir" "$branch"; then
      _log "no new staged changes, but HEAD differs from the last-known origin/$branch — retrying push of the existing unpushed commit(s) (A2a)"
    else
      printf 'noop'; return 0
    fi
  else
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
      _write_status_file noop "throttled (${delta}s < ${COORD_PUSH_THROTTLE_SECONDS}s since last push)"
      return 0
    fi
  fi

  local url; url=$(_resolve_repo_url "$COORD_CLONE_DIR")
  if [ -z "$url" ] && [ ! -d "$COORD_CLONE_DIR/.git" ]; then
    _warn "no coord repo URL (set COORD_REPO_URL or $LOCAL_CONFIG_URL_FILE) and no existing clone — nothing to push"
    _write_status_file noop "no coord repo URL configured and no existing clone"
    return 0
  fi
  if ! _ensure_clone "$COORD_CLONE_DIR" "$url" "$COORD_BRANCH"; then
    _warn "could not ensure clone at $COORD_CLONE_DIR — skipping"
    _write_status_file noop "could not ensure clone at $COORD_CLONE_DIR"
    return 0
  fi

  local host; host=$(_hostname)
  _write_tree_state "$COORD_CLONE_DIR" "$host"

  local result; result=$(_commit_and_push "$COORD_CLONE_DIR" "$COORD_BRANCH" "$host")
  case "$result" in
    pushed)       _log "pushed coordination state ($host)"; _epoch_now > "$LAST_PUSH_FILE"
                  _write_status_file pushed "pushed to origin/$COORD_BRANCH ($host)" ;;
    local-commit) _log "committed locally (push deferred)"; _epoch_now > "$LAST_PUSH_FILE"
                  _write_status_file local-commit "commit landed locally; push deferred (non-ff or push failure after ${REBASE_RETRY_CAP} rebase retries)" ;;
    noop)         _log "no changes to push"
                  _write_status_file noop "nothing to publish" ;;
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

  # --- Scenario 7 (A2a): ahead-of-origin retry — an existing LOCAL commit
  # that never reached origin (simulating a prior transient push failure)
  # gets pushed on the NEXT invocation even though there are NO new staged
  # changes (the OLD gate returned 'noop' here forever — the bug this fixes).
  git -C "$clone" -c user.email=t@t -c user.name=t commit --allow-empty \
    -m "simulated-prior-unpushed-commit" >/dev/null 2>&1
  local pre7_local pre7_origin
  pre7_local=$(git -C "$clone" rev-parse HEAD 2>/dev/null)
  pre7_origin=$(git -C "$clone" rev-parse origin/main 2>/dev/null)
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    export COORD_PUSH_STATUS_FILE="$tmproot/status7.json"
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  local post7_origin; post7_origin=$(git --git-dir="$bare" rev-parse main 2>/dev/null)
  [ "$pre7_local" != "$pre7_origin" ] && [ "$post7_origin" = "$pre7_local" ]
  _ck "A2a ahead-of-origin retry: unpushed local commit reaches origin with no new staged changes" $?
  if command -v jq >/dev/null 2>&1; then
    jq -e '.outcome=="pushed"' "$tmproot/status7.json" >/dev/null 2>&1
    _ck "A2a retry: status file records outcome=pushed" $?
  else
    _ck "A2a retry: status file records outcome=pushed (jq unavailable, skipped)" 0
  fi

  # --- Scenario 8 (A2b): status file records outcome=noop when a follow-up
  # invocation genuinely has nothing new to publish (HEAD == origin, no
  # staged changes) — confirms the A2a fix does not turn every push into a
  # forced attempt.
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    export COORD_PUSH_STATUS_FILE="$tmproot/status8.json"
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  if command -v jq >/dev/null 2>&1; then
    jq -e '.outcome=="noop" and (.ts|length)>0' "$tmproot/status8.json" >/dev/null 2>&1
    _ck "status file records outcome=noop with a timestamp when nothing to publish" $?
  else
    _ck "status file records outcome=noop (jq unavailable, skipped)" 0
  fi

  # --- Scenario 9 (A2b): a genuine UNRESOLVABLE rebase conflict (add/add on
  # the same path, both sides diverged from the same base) -> outcome
  # local-commit, the status file reflects it, and origin is NEVER
  # force-pushed over (the peer's commit stays intact).
  local peer9="$tmproot/peer9"
  git clone "$bare" "$peer9" >/dev/null 2>&1
  printf '{"marker":"peer-version"}' > "$peer9/claims.json"
  git -C "$peer9" -c user.email=r@r -c user.name=r add -A >/dev/null 2>&1
  git -C "$peer9" -c user.email=r@r -c user.name=r commit -m "peer-claims-add" >/dev/null 2>&1
  git -C "$peer9" push origin HEAD:main >/dev/null 2>&1
  # Local clone independently adds the SAME path with different content,
  # committed WITHOUT fetching first — the two histories diverge on an
  # add/add conflict at the identical path.
  printf '{"marker":"local-version"}' > "$clone/claims.json"
  git -C "$clone" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$clone" -c user.email=t@t -c user.name=t commit -m "local-claims-add" >/dev/null 2>&1
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone" COORD_BRANCH="main"
    export WORKSTREAMS_STATE_DIR="$work/wstate" COORD_PUSH_THROTTLE_SECONDS=0
    export COORD_PUSH_STATUS_FILE="$tmproot/status9.json"
    STATE_DIR="$tmproot/state" LAST_PUSH_FILE="$tmproot/state/last-push" \
      bash "$SELF_PATH" push --force >/dev/null 2>&1
  )
  if command -v jq >/dev/null 2>&1; then
    jq -e '.outcome=="local-commit"' "$tmproot/status9.json" >/dev/null 2>&1
    _ck "genuine rebase conflict -> outcome local-commit, status file reflects it" $?
  else
    _ck "genuine rebase conflict -> outcome local-commit (jq unavailable, skipped)" 0
  fi
  local origin9 peer9_sha
  origin9=$(git --git-dir="$bare" rev-parse main 2>/dev/null)
  peer9_sha=$(git -C "$peer9" rev-parse HEAD 2>/dev/null)
  [ -n "$origin9" ] && [ "$origin9" = "$peer9_sha" ]
  _ck "genuine conflict: origin unchanged (peer's commit intact, NEVER force-pushed over)" $?

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
