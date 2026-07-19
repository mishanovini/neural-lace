#!/usr/bin/env bash
# coord-sync.sh — cockpit-v2-push-materialized-store Task 3 (A1, BINDING):
# the SINGLE per-machine coordination cadence. Registered as the dedicated
# Windows Scheduled Task `NL-CoordSync` (600s / 10min, ignore-new-instance)
# via install-coord-sync-task.ps1 — see that file for the installer.
#
# WHAT IT DOES, IN ORDER (binding order per the architecture review, A1):
#   1. exporter        — `node server/export-state.js`, EXPORT_DIR pointed at
#      this clone's `plan-export/` subdirectory (a per-hostname export file,
#      schema-distinct from coord-push.sh's own `tree-state/` envelope).
#   2. coord-push.sh push — commits + publishes whatever the exporter (and/or
#      the live GUI tree-state) wrote, per A2's fixes (ahead-of-origin retry
#      + an outcome status file this script consumes below).
#   3. coord-pull.sh pull — refreshes this machine's read-side view of every
#      peer's export + tree-state, so the cockpit's peer-view reader (plan
#      Task 4) always has a fresh LOCAL clone to read from — no network on
#      its request path.
#
# THIS SCRIPT BEING THE EXPORTER'S ONLY INVOKER IS THE SINGLE-WRITER-PER-
# MACHINE ENFORCEMENT (F4) — nothing else in the harness calls
# server/export-state.js in production; only this cadence does.
#
# WHY A DEDICATED SCRIPT (not a mode on coord-push.sh/coord-pull.sh, and not
# hosted on health-tick.sh): health-tick.sh's cadence is HOURLY (A1, PROVEN
# health-tick.sh:12-13) — the plan's staleness contract needs <=600s.
# coord-push.sh/coord-pull.sh stay single-purpose (push-only / pull-only) so
# each keeps its own narrow self-test oracle; this script is purely the glue
# + the concerns Task 3 adds (no-overlap lock, persistent-failure alerting,
# staleness-contract logging) that don't belong in either sibling.
#
# NO-OVERLAP POLICY (A1: "ignore-new-instance + a cheap exporter lock"):
#   - The scheduled task itself is registered with -MultipleInstances
#     IgnoreNew (install-coord-sync-task.ps1) — the OS-level backstop.
#   - THIS script ALSO takes its own mkdir-based lock
#     (<STATE_DIR>/coord-sync.lock — same atomic-mkdir convention as
#     hooks/lib/sessionstart-singleflight.sh) for the duration of one cycle,
#     so a manual invocation racing the scheduled one — or a scheduled fire
#     landing while a slow prior cycle is still running past its 600s slot
#     (bash spawns have measured 94-119s here) — also no-ops instead of
#     double-running the exporter/push/pull. A lock older than
#     COORD_SYNC_LOCK_STALE_SECONDS (default 900s) is presumed abandoned (a
#     crashed prior run) and reclaimed — never held forever.
#
# A2c (BINDING): if coord-push's outcome status file
# (COORD_PUSH_STATUS_FILE, default ~/.claude/state/coord-push-status.json,
# written by coord-push.sh's A2b fix) shows 'local-commit' for MORE THAN
# COORD_SYNC_LOCAL_COMMIT_ALERT_THRESHOLD (default 3) CONSECUTIVE cycles,
# this script writes ONE alert file into
# ~/.claude/state/external-monitor-alerts/ — the SAME directory and JSON
# schema health-tick.sh already writes into, so the existing
# external-monitor-alert-surfacer.sh SessionStart hook surfaces it with zero
# new wiring. Deduped: once written, no further alert fires for the SAME
# stuck episode (a marker file suppresses repeats); the streak resets (and
# the marker clears) the moment an outcome OTHER than local-commit is
# observed, so a LATER stuck episode can alert again.
#
# STALENESS-CONTRACT INSTRUMENTATION: every cycle appends one line to
# <STATE_DIR>/cycles.log (rotated to the last COORD_SYNC_LOG_MAX_LINES
# lines, default 500) recording ts/outcome/rcs/duration — the source plan
# Task 4's "my coord view last refreshed Xm ago" reads from.
#
# CONFIG RESOLUTION (identical to coord-push.sh/coord-pull.sh):
#   COORD_REPO_URL env  >  ~/.claude/local/coord-repo-url.txt  >  existing
#   clone's origin URL  >  WARN + exit 0 (non-blocking; no coord repo
#   configured on this machine — a named-state degradation, not a crash).
#   COORD_CLONE_DIR env >  ~/claude-projects/workstreams-coordination.
#   COORD_BRANCH env    >  main.
#
# TEST-ONLY OVERRIDES (mirror health-tick.sh's *_CMD convention — never used
# outside --self-test): COORD_SYNC_EXPORTER_CMD / COORD_SYNC_PUSH_CMD /
# COORD_SYNC_PULL_CMD — full replacement command lines for the three
# cadence steps, run via `bash -c`.
#
# ============================================================
# EVENT-TRIGGERED PUBLISH + PERIODIC FLOOR (cockpit-roadmap-redesign Task 7,
# BINDING A5 — round-5 operator intent: publish within ~1min of a real
# status change instead of <=10min, without breaking idle-vs-dead honesty)
# ============================================================
#
# The scheduled task now fires every ~60s (install-coord-sync-task.ps1); each
# fire is a cheap MARKER CHECK that runs the full cycle only when needed:
#
#   dirty marker present  -> FULL cycle (trigger=event). The marker is
#     touched at the WRITER-LIB seam (progress-log-lib.sh pl_emit fresh
#     appends + ask-registry.sh _ar_append_record — A5 iii: NOT hooks, so
#     the GUI's delegated CLI writes and every future writer are covered).
#   clean, floor due      -> FULL cycle anyway (trigger=floor). THE FLOOR
#     RUNS THE FULL CYCLE (exporter+push+pull) AT <=COORD_SYNC_FLOOR_SECONDS
#     (default 600s) REGARDLESS OF THE MARKER — two PROVEN reasons (A5 i):
#     (1) the A3ii keepalive stamp is only written when the exporter RUNS
#     (export-state.js runExport, KEEPALIVE_MS=60min) — a naive "if clean:
#     exit 0" freezes `exported_at` and every healthy IDLE machine renders
#     peer-unreachable within ~80min (peer-view.js classifyPeerState);
#     (2) git-blind mutations (cherry-pick/pull/reset) fire no event and
#     touch no marker — the floor is their ONLY coverage.
#   clean, floor not due  -> marker-check-only no-op, logged to
#     STATE_DIR/debounce.log (its OWN small rotating log — NEVER cycles.log,
#     which stays one-line-per-FULL-cycle so it remains readable AND so
#     peer-view.js's cycles.log fallback for "my coord view last refreshed"
#     never mistakes a no-op check for a real refresh — A5 iv).
#
# CLEAR-BEFORE-EXPORT (A5 ii): the marker is removed BEFORE the exporter
# reads state, so an event landing mid-export re-dirties the marker and the
# NEXT fire republishes it; clear-after would lose that update (classic
# dirty-flag lost-update).
#
# DEBOUNCE / BURST COALESCING: N events between two fires collapse into ONE
# marker -> ONE cycle; fires are >=60s apart, so publish rate is bounded at
# ~1/min by construction, hash-gated as before (the exporter's own
# content-hash gate + coord-push's noop path are unchanged).
#
# LOCK THRESHOLD AT THE NEW CADENCE (A5 iv, VERIFIED): the 900s stale-lock
# reclaim remains correct at a 60s fire interval because (a) a LIVE cycle is
# hard-bounded by the scheduled task's ExecutionTimeLimit (5min = 300s;
# install-coord-sync-task.ps1) plus IgnoreNew, so a lock older than 900s
# (3x that bound) is provably a crashed holder, never a slow live one; and
# (b) a crashed lock delays publishing by at most 900s — no worse than the
# pre-Task-7 600s cadence's own worst case + one slot. Self-test Scenario 9
# pins the 900 > ExecutionTimeLimit cross-file invariant mechanically.
#
# FAILURE RENDERINGS (named-absence pattern, task-1 generalization):
#   - missing/garbled last-full-cycle stamp -> treated as FLOOR DUE (fail
#     toward publishing, never toward silence).
#   - un-creatable/unwritable marker path on the writer side -> the write
#     still succeeds (never-block law); this machine degrades to pure
#     600s-floor cadence — exactly the pre-Task-7 behavior, never worse.
#   - no coord repo configured -> the marker is cleared and the floor stamp
#     written anyway (nothing to publish TO; a later-configured repo gets
#     full state from the next floor cycle), logged skipped-no-coord-repo —
#     an unconfigured machine stays at one log line per floor period, not
#     one per 60s fire.
#
# Subcommands: (default) run one debounced fire | --force (run a full cycle
# regardless of marker/floor — manual verification path) | --self-test |
# --help
#
# Self-test: bash coord-sync.sh --self-test (sandboxed fixture coord repo;
# never touches the real coord clone, state dir, or alert dir).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
{ source "$SELF_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true

# ============================================================
# Constants / config
# ============================================================
COORD_CLONE_DIR="${COORD_CLONE_DIR:-$HOME/claude-projects/workstreams-coordination}"
COORD_BRANCH="${COORD_BRANCH:-main}"
LOCAL_CONFIG_URL_FILE="${HOME}/.claude/local/coord-repo-url.txt"
STATE_DIR="${STATE_DIR:-${HOME}/.claude/state/coord-sync}"
LOCK_DIR="$STATE_DIR/coord-sync.lock"
LOCK_STALE_SECONDS="${COORD_SYNC_LOCK_STALE_SECONDS:-900}"
STREAK_FILE="$STATE_DIR/local-commit-streak"
ALERT_ACTIVE_FILE="$STATE_DIR/local-commit-alert-active"
CYCLE_LOG="$STATE_DIR/cycles.log"
CYCLE_LOG_MAX_LINES="${COORD_SYNC_LOG_MAX_LINES:-500}"
LOCAL_COMMIT_ALERT_THRESHOLD="${COORD_SYNC_LOCAL_COMMIT_ALERT_THRESHOLD:-3}"
STATUS_FILE="${COORD_PUSH_STATUS_FILE:-${HOME}/.claude/state/coord-push-status.json}"
ALERT_DIR="${EXTERNAL_MONITOR_ALERTS_DIR:-${HOME}/.claude/state/external-monitor-alerts}"
# Task 7 (A5): event-triggered publish + full-cycle floor. The marker default
# ($STATE_DIR/dirty) meets progress-log-lib.sh's pl_coord_dirty_marker_path
# default (~/.claude/state/coord-sync/dirty) with zero configuration; the
# SAME env var (COORD_DIRTY_MARKER_FILE) overrides both ends at once.
DIRTY_MARKER_FILE="${COORD_DIRTY_MARKER_FILE:-$STATE_DIR/dirty}"
FLOOR_SECONDS="${COORD_SYNC_FLOOR_SECONDS:-600}"
LAST_FULL_FILE="$STATE_DIR/last-full-cycle"
DEBOUNCE_LOG="$STATE_DIR/debounce.log"
DEBOUNCE_LOG_MAX_LINES="${COORD_SYNC_DEBOUNCE_LOG_MAX_LINES:-300}"

COORD_PUSH_SH="$SELF_DIR/coord-push.sh"
COORD_PULL_SH="$SELF_DIR/coord-pull.sh"
_EXPORTER_JS_DEFAULT=""
if command -v nl_workstreams_ui >/dev/null 2>&1; then
  _ui_dir="$(nl_workstreams_ui 2>/dev/null)"
  [[ -n "$_ui_dir" ]] && _EXPORTER_JS_DEFAULT="$_ui_dir/server/export-state.js"
fi
EXPORTER_JS="${COORD_SYNC_EXPORTER_JS:-$_EXPORTER_JS_DEFAULT}"

_log()  { printf '[coord-sync] %s\n' "$*" >&2; }
_warn() { printf '[coord-sync] WARN: %s\n' "$*" >&2; }

_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_now_ms() {
  local t; t=$(date +%s%3N 2>/dev/null)
  if [[ "$t" =~ ^[0-9]+$ ]]; then printf '%s' "$t"; else printf '%s' "$(( $(date +%s) * 1000 ))"; fi
}
_hostname() {
  local h; h=$(hostname 2>/dev/null || echo "")
  [ -n "$h" ] || h="${COMPUTERNAME:-${HOSTNAME:-unknown-host}}"
  printf '%s' "$h"
}

# ============================================================
# Lock (mkdir-atomic — same convention as hooks/lib/sessionstart-
# singleflight.sh's atomic claim, but held for the cycle's duration and
# explicitly RELEASED on exit — this is a mutex, not a TTL debounce).
# ============================================================
_lock_age_secs() {
  local dir="$1" ts now
  ts=$(awk 'NR==1{print $2}' "$dir/owner" 2>/dev/null)
  now=$(date -u +%s 2>/dev/null || echo 0)
  if [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt 0 ] && [ "$now" -ge "$ts" ]; then
    echo $(( now - ts )); return 0
  fi
  echo 999999   # unknown/garbled owner file -> treat as very stale (safe to reclaim)
}

_acquire_lock() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$LOCK_DIR/owner" 2>/dev/null || true
    return 0
  fi
  local age; age=$(_lock_age_secs "$LOCK_DIR")
  if [ "$age" -ge "$LOCK_STALE_SECONDS" ]; then
    _warn "reclaiming a stale lock (age ${age}s >= ${LOCK_STALE_SECONDS}s) — presumed a crashed prior cycle"
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s %s\n' "$$" "$(date -u +%s)" > "$LOCK_DIR/owner" 2>/dev/null || true
      return 0
    fi
  fi
  return 1
}

_release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null || true; }

# ============================================================
# Bootstrap-only clone check (NEVER a sync — coord-pull.sh below is the
# sanctioned sync step). Returns 1 when the coord repo is genuinely
# unconfigured/unreachable; callers must then SKIP the exporter step
# entirely — writing EXPORT_DIR into a non-git COORD_CLONE_DIR would break
# coord-push.sh's own later clone-if-missing check, which refuses to `git
# clone` into a non-empty directory.
# ============================================================
_ensure_clone_bootstrap() {
  if [ -d "$COORD_CLONE_DIR/.git" ]; then return 0; fi
  local url=""
  if [ -n "${COORD_REPO_URL:-}" ]; then
    url="$COORD_REPO_URL"
  elif [ -f "$LOCAL_CONFIG_URL_FILE" ]; then
    url=$(head -n1 "$LOCAL_CONFIG_URL_FILE" 2>/dev/null | tr -d '[:space:]')
  fi
  if [ -z "$url" ]; then
    _warn "no coord repo URL configured and no existing clone at $COORD_CLONE_DIR — skipping this cycle (named-state degradation; see plan Assumptions)"
    return 1
  fi
  mkdir -p "$(dirname "$COORD_CLONE_DIR")" 2>/dev/null || true
  if git clone --branch "$COORD_BRANCH" "$url" "$COORD_CLONE_DIR" >/dev/null 2>&1; then return 0; fi
  if git clone "$url" "$COORD_CLONE_DIR" >/dev/null 2>&1; then return 0; fi
  _warn "could not clone coord repo from $url -> $COORD_CLONE_DIR — skipping this cycle"
  return 1
}

# ============================================================
# Status-file read (coord-push.sh's A2b output) -> pushed|local-commit|noop|unknown
# ============================================================
_read_push_outcome() {
  local f="$STATUS_FILE"
  [ -f "$f" ] || { printf 'unknown'; return 0; }
  local out=""
  if command -v jq >/dev/null 2>&1; then
    out=$(jq -r '.outcome // empty' "$f" 2>/dev/null)
  fi
  if [ -z "$out" ]; then
    out=$(grep -o '"outcome"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
  fi
  [ -n "$out" ] && printf '%s' "$out" || printf 'unknown'
}

# ============================================================
# A2c: consecutive local-commit streak -> ONE deduped alert per episode.
# ============================================================
_write_local_commit_alert() {
  local streak="$1"
  mkdir -p "$ALERT_DIR" 2>/dev/null || return 0
  local ts_name; ts_name=$(date -u '+%Y-%m-%dT%H-%M-%SZ' 2>/dev/null || echo "unknown-$$")
  local alert_file="$ALERT_DIR/${ts_name}-coord-sync-stuck.json"
  local now; now=$(_iso_now)
  local host; host=$(_hostname)
  local reason="coord-push has landed ${streak} consecutive local-commit outcomes on ${host} (never reaching origin) -- cross-machine publication has been silently deferred; see ${STATUS_FILE} and ${CYCLE_LOG}"
  reason="${reason//\\/\\\\}"; reason="${reason//\"/\\\"}"
  local tmp; tmp=$(mktemp "${alert_file}.XXXXXX" 2>/dev/null || printf '%s.tmp' "$alert_file")
  printf '{"schema_version":1,"monitor_url":"nl-coord-sync (cross-machine coordination transport, cockpit-v2 A2c)","started_at":"%s","ended_at":"%s","total_routes":1,"healthy_count":0,"anomaly_count":1,"slow_threshold_ms":0,"results":[{"label":"coord-push","method":"CADENCE","path":"%s","expected":"pushed|noop","status":"local-commit x%s","elapsed_ms":0,"verdict":"COORD_PUSH_STUCK_LOCAL_COMMIT","failure_reason":"%s"}]}\n' \
    "$now" "$now" "$COORD_CLONE_DIR" "$streak" "$reason" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$alert_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  if [ -f "$alert_file" ]; then
    _log "ALERT written: $alert_file (persistent local-commit streak=$streak; surfaced at next SessionStart)"
  fi
}

_track_local_commit_streak() {
  local outcome="$1" streak=0
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [ -f "$STREAK_FILE" ] && streak=$(cat "$STREAK_FILE" 2>/dev/null || echo 0)
  [[ "$streak" =~ ^[0-9]+$ ]] || streak=0

  if [ "$outcome" = "local-commit" ]; then
    streak=$((streak + 1))
    echo "$streak" > "$STREAK_FILE" 2>/dev/null || true
    if [ "$streak" -gt "$LOCAL_COMMIT_ALERT_THRESHOLD" ]; then
      if [ ! -f "$ALERT_ACTIVE_FILE" ]; then
        _write_local_commit_alert "$streak"
        : > "$ALERT_ACTIVE_FILE" 2>/dev/null || true
      fi
      # else: already alerted for this episode — stay silent (dedup).
    fi
  else
    # Streak broken (pushed / noop / unknown) — reset so a FUTURE stuck
    # episode can alert again (A2c: one alert per episode, not per run).
    rm -f "$STREAK_FILE" "$ALERT_ACTIVE_FILE" 2>/dev/null || true
  fi
}

# ============================================================
# Staleness-contract instrumentation (small rotating log; Task 4's source
# for "my coord view last refreshed Xm ago").
# ============================================================
_log_cycle() {
  local outcome="$1" export_rc="$2" push_rc="$3" pull_rc="$4" pull_result="$5" duration_ms="$6" trigger="${7:-legacy}"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf 'ts=%s host=%s outcome=%s export_rc=%s push_rc=%s pull_rc=%s pull_result=%s duration_ms=%s trigger=%s\n' \
    "$(_iso_now)" "$(_hostname)" "$outcome" "$export_rc" "$push_rc" "$pull_rc" "$pull_result" "$duration_ms" "$trigger" \
    >> "$CYCLE_LOG" 2>/dev/null || true
  if [ -f "$CYCLE_LOG" ]; then
    local lines; lines=$(wc -l < "$CYCLE_LOG" 2>/dev/null | tr -d ' ')
    if [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -gt "$CYCLE_LOG_MAX_LINES" ]; then
      local tmp="$CYCLE_LOG.tmp.$$"
      tail -n "$CYCLE_LOG_MAX_LINES" "$CYCLE_LOG" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CYCLE_LOG" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
  fi
  return 0
}

_classify_pull_output() {
  local out="$1"
  if printf '%s' "$out" | grep -q "pulled peers' state"; then printf 'synced'
  elif printf '%s' "$out" | grep -q "already current"; then printf 'noop'
  elif printf '%s' "$out" | grep -q "fetch failed"; then printf 'fetch-failed'
  elif printf '%s' "$out" | grep -q "stash pop conflict"; then printf 'diverged'
  else printf 'unknown'
  fi
}

# ============================================================
# Task 7 (A5): floor stamp + debounce-skip logging.
# ============================================================

# _floor_age_secs — seconds since the last FULL cycle. A missing or garbled
# stamp prints a huge value: NAMED failure rendering = "floor due" (fail
# toward publishing, never toward silence).
_floor_age_secs() {
  local ts now
  ts=$(head -n1 "$LAST_FULL_FILE" 2>/dev/null | tr -d '[:space:]')
  now=$(date -u +%s 2>/dev/null || echo 0)
  if [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt 0 ] && [ "$now" -ge "$ts" ]; then
    echo $(( now - ts )); return 0
  fi
  echo 999999
  return 0
}

_stamp_full_cycle() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  date -u +%s > "$LAST_FULL_FILE" 2>/dev/null || true
  return 0
}

# _log_debounce_skip <floor_age> — marker-check-only fires log HERE, never
# to cycles.log (A5 iv: cycles.log stays one-line-per-FULL-cycle, and
# peer-view.js's cycles.log fallback never mistakes a no-op check for a
# refresh). Own small rotation.
_log_debounce_skip() {
  local floor_age="$1"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf 'ts=%s host=%s outcome=marker-check-only floor_age_s=%s floor_s=%s\n' \
    "$(_iso_now)" "$(_hostname)" "$floor_age" "$FLOOR_SECONDS" >> "$DEBOUNCE_LOG" 2>/dev/null || true
  if [ -f "$DEBOUNCE_LOG" ]; then
    local lines; lines=$(wc -l < "$DEBOUNCE_LOG" 2>/dev/null | tr -d ' ')
    if [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -gt "$DEBOUNCE_LOG_MAX_LINES" ]; then
      local tmp="$DEBOUNCE_LOG.tmp.$$"
      tail -n "$DEBOUNCE_LOG_MAX_LINES" "$DEBOUNCE_LOG" > "$tmp" 2>/dev/null && mv -f "$tmp" "$DEBOUNCE_LOG" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
  fi
  return 0
}

# ============================================================
# One cycle: exporter -> coord-push -> coord-pull (A1 binding order).
# ============================================================
_run_cycle() {
  local trigger="${1:-legacy}"
  local t0 t1
  t0=$(_now_ms)

  if ! _ensure_clone_bootstrap; then
    # Named degradation: nothing to publish TO. Clear the marker + write the
    # floor stamp anyway so an unconfigured machine logs ONE skip per floor
    # period (not one per 60s fire); a later-configured repo gets full state
    # from the next floor cycle — no event is ever lost, only deferred.
    rm -f "$DIRTY_MARKER_FILE" 2>/dev/null || true
    _stamp_full_cycle
    _log_cycle "skipped-no-coord-repo" "-" "-" "-" "-" "$(( $(_now_ms) - t0 ))" "$trigger"
    return 0
  fi

  # A5 ii (BINDING): clear the marker BEFORE the exporter reads state — an
  # event landing mid-export re-dirties it and the NEXT fire republishes;
  # clear-after would lose that update (classic dirty-flag lost-update).
  rm -f "$DIRTY_MARKER_FILE" 2>/dev/null || true

  # ---- step 1: exporter ----
  local export_dir="$COORD_CLONE_DIR/plan-export"
  local export_rc=0 export_out=""
  if [ -n "${COORD_SYNC_EXPORTER_CMD:-}" ]; then
    export_out=$(bash -c "$COORD_SYNC_EXPORTER_CMD" 2>&1); export_rc=$?
  elif [ -n "$EXPORTER_JS" ] && [ -f "$EXPORTER_JS" ]; then
    export_out=$(EXPORT_DIR="$export_dir" node "$EXPORTER_JS" 2>&1); export_rc=$?
  else
    _warn "exporter script not found (resolved: '${EXPORTER_JS:-<empty>}') — skipping export step this cycle"
    export_rc=127
  fi
  _log "exporter: rc=$export_rc"

  # ---- step 2: coord-push ----
  local push_rc=0
  if [ -n "${COORD_SYNC_PUSH_CMD:-}" ]; then
    bash -c "$COORD_SYNC_PUSH_CMD" >/dev/null 2>&1; push_rc=$?
  else
    bash "$COORD_PUSH_SH" push >/dev/null 2>&1; push_rc=$?
  fi
  _log "coord-push: rc=$push_rc"

  # ---- step 3: coord-pull ----
  local pull_rc=0 pull_out="" pull_result="unknown"
  if [ -n "${COORD_SYNC_PULL_CMD:-}" ]; then
    pull_out=$(bash -c "$COORD_SYNC_PULL_CMD" 2>&1); pull_rc=$?
  else
    pull_out=$(bash "$COORD_PULL_SH" pull 2>&1); pull_rc=$?
  fi
  pull_result=$(_classify_pull_output "$pull_out")
  _log "coord-pull: rc=$pull_rc ($pull_result)"

  local outcome; outcome=$(_read_push_outcome)
  _track_local_commit_streak "$outcome"

  # Floor stamp: a FULL cycle ran (whatever its step rcs — the floor tracks
  # cycle EXECUTION; step failures surface via outcome/rcs + the A2c alert).
  _stamp_full_cycle

  t1=$(_now_ms)
  _log_cycle "$outcome" "$export_rc" "$push_rc" "$pull_rc" "$pull_result" "$(( t1 - t0 ))" "$trigger"
  return 0
}

# _main <force> — one debounced fire (Task 7 decision logic; see header).
_main() {
  local force="${1:-0}"
  if ! _acquire_lock; then
    _log "another coord-sync cycle is already running (lock held) — no-op (overlap prevention)"
    return 0
  fi
  trap _release_lock EXIT

  local dirty=0 floor_age trigger=""
  [ -f "$DIRTY_MARKER_FILE" ] && dirty=1
  floor_age=$(_floor_age_secs)

  if [ "$force" = "1" ]; then
    trigger="forced"
  elif [ "$dirty" = "1" ] && [ "$floor_age" -ge "$FLOOR_SECONDS" ]; then
    trigger="event+floor"
  elif [ "$dirty" = "1" ]; then
    trigger="event"
  elif [ "$floor_age" -ge "$FLOOR_SECONDS" ]; then
    trigger="floor"
  else
    # Marker-check-only fire: clean AND inside the floor window — no-op.
    _log_debounce_skip "$floor_age"
    return 0
  fi

  _run_cycle "$trigger"
  return 0
}

# ============================================================
# Self-test (sandboxed fixture coord repo — never touches the real coord
# clone, state dir, status file, or alert dir).
# ============================================================
_self_test() {
  local pass=0 fail=0
  _ck() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "  PASS: $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }

  local tmproot; tmproot=$(mktemp -d 2>/dev/null || echo "/tmp/coord-sync-st.$$")
  mkdir -p "$tmproot"
  local bare="$tmproot/origin.git"
  local fakehost="COORD-SYNC-TEST-HOST"

  git init --bare -b main "$bare" >/dev/null 2>&1
  local seed="$tmproot/seed"
  git clone "$bare" "$seed" >/dev/null 2>&1
  git -C "$seed" -c user.email=t@t -c user.name=t commit --allow-empty -m init >/dev/null 2>&1
  git -C "$seed" push -u origin HEAD:main >/dev/null 2>&1
  rm -rf "$seed"

  # ================= Scenario 1: full cycle end-to-end =================
  local clone1="$tmproot/clone1"
  local s1_state="$tmproot/s1-state" s1_alerts="$tmproot/s1-alerts" s1_status="$tmproot/s1-status.json"
  local s1_ar="$tmproot/s1-ar" s1_pl="$tmproot/s1-pl" s1_dp="$tmproot/s1-dp" s1_hb="$tmproot/s1-hb"
  mkdir -p "$s1_ar" "$s1_pl" "$s1_dp" "$s1_hb"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone1" COORD_BRANCH="main"
    export STATE_DIR="$s1_state" COORD_PUSH_STATUS_FILE="$s1_status"
    export EXTERNAL_MONITOR_ALERTS_DIR="$s1_alerts"
    export COORD_PUSH_THROTTLE_SECONDS=0
    export EXPORT_HOSTNAME="$fakehost"
    export ASK_REGISTRY_STATE_DIR="$s1_ar" PROGRESS_LOG_STATE_DIR="$s1_pl" \
           DISPATCH_PROVENANCE_STATE_DIR="$s1_dp" HEARTBEAT_STATE_DIR="$s1_hb"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  [ -f "$clone1/plan-export/${fakehost}.json" ]
  _ck "full cycle: exporter wrote plan-export/<host>.json into the coord clone" $?

  local clone1_head bare1_head
  clone1_head=$(git -C "$clone1" rev-parse HEAD 2>/dev/null)
  bare1_head=$(git --git-dir="$bare" rev-parse main 2>/dev/null)
  [ -n "$clone1_head" ] && [ "$clone1_head" = "$bare1_head" ]
  _ck "full cycle: exported state reached origin (coord-push published it)" $?

  [ -f "$s1_state/cycles.log" ] && grep -q "outcome=pushed" "$s1_state/cycles.log"
  _ck "full cycle: staleness-contract cycle log records outcome=pushed" $?

  # ================= Scenario 2: lock prevents overlap =================
  local s2_state="$tmproot/s2-state"
  mkdir -p "$s2_state/coord-sync.lock"
  printf '%s %s\n' 999999 "$(date -u +%s)" > "$s2_state/coord-sync.lock/owner"
  local s2_marker="$tmproot/s2-marker"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s2-clone" COORD_BRANCH="main"
    export STATE_DIR="$s2_state"
    export COORD_SYNC_EXPORTER_CMD="touch '$s2_marker.exporter'"
    export COORD_SYNC_PUSH_CMD="touch '$s2_marker.push'"
    export COORD_SYNC_PULL_CMD="touch '$s2_marker.pull'"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  local rc2=$?
  [ "$rc2" -eq 0 ] && [ ! -f "$s2_marker.exporter" ] && [ ! -f "$s2_marker.push" ] && [ ! -f "$s2_marker.pull" ]
  _ck "held lock -> overlapping invocation no-ops (none of the 3 steps ran), exits 0" $?

  rm -rf "$s2_state/coord-sync.lock"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s2-clone" COORD_BRANCH="main"
    export STATE_DIR="$s2_state"
    export COORD_SYNC_EXPORTER_CMD="touch '$s2_marker.exporter'"
    export COORD_SYNC_PUSH_CMD="touch '$s2_marker.push'"
    export COORD_SYNC_PULL_CMD="touch '$s2_marker.pull'"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  [ -f "$s2_marker.exporter" ] && [ -f "$s2_marker.push" ] && [ -f "$s2_marker.pull" ]
  _ck "after lock release, next invocation runs all 3 steps normally" $?
  [ ! -d "$s2_state/coord-sync.lock" ]
  _ck "lock is released after a normal cycle completes (trap EXIT)" $?

  # ======== Scenario 3: persistent local-commit -> exactly ONE alert ========
  # (simulates a dead remote via a stubbed coord-push step, per the plan's
  # own suggested test design — real conflict/rebase failure paths are
  # coord-push.sh's own self-test's job, not this one's.)
  local s3_state="$tmproot/s3-state" s3_alerts="$tmproot/s3-alerts" s3_status="$tmproot/s3-status.json"
  mkdir -p "$s3_state" "$s3_alerts"
  local s3_clone="$tmproot/s3-clone"
  local stub_local_commit
  stub_local_commit="printf '{\"outcome\":\"local-commit\",\"ts\":\"%s\",\"detail\":\"simulated dead remote\"}\n' \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" > '$s3_status'"
  local i
  for i in 1 2 3 4 5; do
    (
      export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$s3_clone" COORD_BRANCH="main"
      export STATE_DIR="$s3_state" COORD_PUSH_STATUS_FILE="$s3_status"
      export COORD_SYNC_FLOOR_SECONDS=0   # Task 7: every run floor-due — this scenario tests ALERTING, not debounce
      export EXTERNAL_MONITOR_ALERTS_DIR="$s3_alerts"
      export COORD_SYNC_EXPORTER_CMD="true"
      export COORD_SYNC_PUSH_CMD="$stub_local_commit"
      export COORD_SYNC_PULL_CMD="true"
      bash "$SELF_PATH" >/dev/null 2>&1
    )
  done
  local n_alerts_1; n_alerts_1=$(ls "$s3_alerts"/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$n_alerts_1" = "1" ]
  _ck "persistent local-commit (5 consecutive cycles, threshold 3): exactly ONE alert file written" $?

  local one_alert; one_alert=$(ls "$s3_alerts"/*coord-sync-stuck.json 2>/dev/null | head -n1)
  if [ -n "$one_alert" ] && grep -q 'COORD_PUSH_STUCK_LOCAL_COMMIT' "$one_alert" 2>/dev/null; then
    _ck "alert file carries the COORD_PUSH_STUCK_LOCAL_COMMIT verdict (surfacer-compatible schema)" 0
  else
    _ck "alert file carries the COORD_PUSH_STUCK_LOCAL_COMMIT verdict (surfacer-compatible schema)" 1
  fi

  # THE ORACLE: the real, unmodified surfacer must surface this alert.
  local surfacer="$SELF_DIR/../hooks/external-monitor-alert-surfacer.sh"
  if [ -f "$surfacer" ]; then
    local surf_out
    surf_out=$(bash "$surfacer" "$s3_alerts" </dev/null 2>/dev/null)
    if printf '%s' "$surf_out" | grep -q "1 unacked alert" && printf '%s' "$surf_out" | grep -q "COORD_PUSH_STUCK_LOCAL_COMMIT"; then
      _ck "REAL external-monitor-alert-surfacer.sh surfaces the coord-sync alert (pre-existing oracle)" 0
    else
      _ck "REAL external-monitor-alert-surfacer.sh surfaces the coord-sync alert (pre-existing oracle)" 1
    fi
  else
    _ck "surfacer oracle available at $surfacer" 1
  fi

  # Break the streak (one healthy 'pushed' cycle), then resume local-commit:
  # a NEW episode must alert again — dedup is per-episode, not permanent.
  local stub_pushed
  stub_pushed="printf '{\"outcome\":\"pushed\",\"ts\":\"%s\",\"detail\":\"remote recovered\"}\n' \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" > '$s3_status'"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$s3_clone" COORD_BRANCH="main"
    export STATE_DIR="$s3_state" COORD_PUSH_STATUS_FILE="$s3_status"
    export COORD_SYNC_FLOOR_SECONDS=0   # Task 7: every run floor-due — this scenario tests ALERTING, not debounce
    export EXTERNAL_MONITOR_ALERTS_DIR="$s3_alerts"
    export COORD_SYNC_EXPORTER_CMD="true" COORD_SYNC_PUSH_CMD="$stub_pushed" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  for i in 1 2 3 4; do
    (
      export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$s3_clone" COORD_BRANCH="main"
      export STATE_DIR="$s3_state" COORD_PUSH_STATUS_FILE="$s3_status"
      export COORD_SYNC_FLOOR_SECONDS=0   # Task 7: every run floor-due — this scenario tests ALERTING, not debounce
      export EXTERNAL_MONITOR_ALERTS_DIR="$s3_alerts"
      export COORD_SYNC_EXPORTER_CMD="true" COORD_SYNC_PUSH_CMD="$stub_local_commit" COORD_SYNC_PULL_CMD="true"
      bash "$SELF_PATH" >/dev/null 2>&1
    )
  done
  local n_alerts_2; n_alerts_2=$(ls "$s3_alerts"/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$n_alerts_2" = "2" ]
  _ck "streak reset by a healthy cycle + a NEW stuck episode -> a SECOND alert (dedup is per-episode, not permanent)" $?

  # ================= Scenario 4: no coord repo -> graceful no-op =================
  local s4_state="$tmproot/s4-state"
  (
    unset COORD_REPO_URL
    export COORD_CLONE_DIR="$tmproot/s4-nope" COORD_BRANCH="main"
    export STATE_DIR="$s4_state"
    HOME="$tmproot/s4-nohome" bash "$SELF_PATH" >/dev/null 2>&1
  )
  local rc4=$?
  [ "$rc4" -eq 0 ]
  _ck "no coord repo configured + no existing clone -> exits 0 (non-blocking)" $?

  # ======== Scenario 5 (Task 7, REAL FLAGLESS SHAPE): debounce skip + event
  # path end-to-end against the REAL exporter/push/pull and fixture origin —
  # no *_CMD stubs anywhere in this scenario. ========
  local s5_cycles="$s1_state/cycles.log"
  local s5_lines_before s5_lines_after
  s5_lines_before=$(wc -l < "$s5_cycles" 2>/dev/null | tr -d ' ')
  # 5a: clean + floor fresh (scenario 1 just ran a full cycle) -> marker-check-only no-op.
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone1" COORD_BRANCH="main"
    export STATE_DIR="$s1_state" COORD_PUSH_STATUS_FILE="$s1_status"
    export EXTERNAL_MONITOR_ALERTS_DIR="$s1_alerts"
    export COORD_PUSH_THROTTLE_SECONDS=0
    export EXPORT_HOSTNAME="$fakehost"
    export ASK_REGISTRY_STATE_DIR="$s1_ar" PROGRESS_LOG_STATE_DIR="$s1_pl" \
           DISPATCH_PROVENANCE_STATE_DIR="$s1_dp" HEARTBEAT_STATE_DIR="$s1_hb"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  s5_lines_after=$(wc -l < "$s5_cycles" 2>/dev/null | tr -d ' ')
  [ "$s5_lines_before" = "$s5_lines_after" ] && [ -f "$s1_state/debounce.log" ] \
    && grep -q "outcome=marker-check-only" "$s1_state/debounce.log"
  _ck "clean fire inside the floor window -> marker-check-only no-op: NO cycles.log line, skip logged DISTINCTLY to debounce.log (A5 iv)" $?

  # 5b: touch the dirty marker (a status-change event) -> the SAME real
  # cycle runs again, logged trigger=event; marker consumed.
  printf 'selftest-event\n' > "$s1_state/dirty"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$clone1" COORD_BRANCH="main"
    export STATE_DIR="$s1_state" COORD_PUSH_STATUS_FILE="$s1_status"
    export EXTERNAL_MONITOR_ALERTS_DIR="$s1_alerts"
    export COORD_PUSH_THROTTLE_SECONDS=0
    export EXPORT_HOSTNAME="$fakehost"
    export ASK_REGISTRY_STATE_DIR="$s1_ar" PROGRESS_LOG_STATE_DIR="$s1_pl" \
           DISPATCH_PROVENANCE_STATE_DIR="$s1_dp" HEARTBEAT_STATE_DIR="$s1_hb"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  tail -n1 "$s5_cycles" 2>/dev/null | grep -q "trigger=event" && [ ! -f "$s1_state/dirty" ]
  _ck "dirty marker -> the REAL full cycle runs (trigger=event in cycles.log), marker consumed (event->publish path E2E, no stubs)" $?

  # ======== Scenario 6 (Task 7, THE A5 FLOOR PIN): an IDLE machine (clean
  # marker) still runs the FULL cycle incl. the exporter once the floor
  # elapses — the keepalive stamp only updates when the exporter runs;
  # "if clean: exit 0" would render every healthy idle machine
  # peer-unreachable within ~80min. ========
  local s6_state="$tmproot/s6-state" s6_count="$tmproot/s6-exporter-count"
  mkdir -p "$s6_state"
  : > "$s6_count"
  # Floor already elapsed (stamp 700s old, floor 600s), NO marker.
  echo "$(( $(date -u +%s) - 700 ))" > "$s6_state/last-full-cycle"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s6-clone" COORD_BRANCH="main"
    export STATE_DIR="$s6_state" COORD_SYNC_FLOOR_SECONDS=600
    export COORD_SYNC_EXPORTER_CMD="echo run >> '$s6_count'"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  local s6_runs; s6_runs=$(wc -l < "$s6_count" 2>/dev/null | tr -d ' ')
  [ "$s6_runs" = "1" ] && grep -q "trigger=floor" "$s6_state/cycles.log" 2>/dev/null
  _ck "IDLE machine, floor elapsed -> FULL cycle runs INCLUDING the exporter (trigger=floor) — the A5 keepalive-honesty floor" $?
  # Floor NOT elapsed -> no exporter run (the skip is the debounce, the run above is the floor).
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s6-clone" COORD_BRANCH="main"
    export STATE_DIR="$s6_state" COORD_SYNC_FLOOR_SECONDS=600
    export COORD_SYNC_EXPORTER_CMD="echo run >> '$s6_count'"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  s6_runs=$(wc -l < "$s6_count" 2>/dev/null | tr -d ' ')
  [ "$s6_runs" = "1" ]
  _ck "same machine, floor fresh + still clean -> exporter NOT run again (debounce), floor cadence preserved at <=600s" $?
  # Missing/garbled stamp -> NAMED failure rendering: floor due (fail toward publishing).
  rm -f "$s6_state/last-full-cycle"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s6-clone" COORD_BRANCH="main"
    export STATE_DIR="$s6_state" COORD_SYNC_FLOOR_SECONDS=600
    export COORD_SYNC_EXPORTER_CMD="echo run >> '$s6_count'"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  s6_runs=$(wc -l < "$s6_count" 2>/dev/null | tr -d ' ')
  [ "$s6_runs" = "2" ]
  _ck "MISSING floor stamp -> treated as floor-due (named failure rendering: fail toward publishing, never toward silence)" $?

  # ======== Scenario 7 (Task 7, A5 ii): marker cleared BEFORE the exporter
  # reads state; an event landing MID-EXPORT re-dirties and the next fire
  # republishes (lost-update prevention). ========
  local s7_state="$tmproot/s7-state" s7_count="$tmproot/s7-exporter-count"
  mkdir -p "$s7_state"
  : > "$s7_count"
  local s7_marker="$s7_state/dirty"
  # Exporter stub: records "cleared-ok" iff the marker is ALREADY GONE when
  # the exporter runs, then simulates a mid-export event by re-touching it.
  local s7_exporter="[ ! -f '$s7_marker' ] && touch '$tmproot/s7-cleared-ok'; echo mid-export-event > '$s7_marker'; echo run >> '$s7_count'"
  printf 'pre-existing-event\n' > "$s7_marker"
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s7-clone" COORD_BRANCH="main"
    export STATE_DIR="$s7_state" COORD_SYNC_FLOOR_SECONDS=999999
    export COORD_SYNC_EXPORTER_CMD="$s7_exporter"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  [ -f "$tmproot/s7-cleared-ok" ] && [ -f "$s7_marker" ]
  _ck "marker is cleared BEFORE the exporter reads state (A5 ii), and a mid-export event re-dirties it (not lost)" $?
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s7-clone" COORD_BRANCH="main"
    export STATE_DIR="$s7_state" COORD_SYNC_FLOOR_SECONDS=999999
    export COORD_SYNC_EXPORTER_CMD="$s7_exporter"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  local s7_runs; s7_runs=$(wc -l < "$s7_count" 2>/dev/null | tr -d ' ')
  [ "$s7_runs" = "2" ]
  _ck "the re-dirtied marker triggers the NEXT fire's republish (clear-after would have lost this update)" $?

  # ======== Scenario 8 (Task 7): burst coalescing — N events between fires
  # collapse into ONE cycle; debounce log rotates on its own cap. ========
  local s8_state="$tmproot/s8-state" s8_count="$tmproot/s8-exporter-count"
  mkdir -p "$s8_state"
  : > "$s8_count"
  date -u +%s > "$s8_state/last-full-cycle"   # floor fresh — only events can trigger
  local i8
  for i8 in 1 2 3 4 5; do printf 'burst-event-%s\n' "$i8" > "$s8_state/dirty"; done
  (
    export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s8-clone" COORD_BRANCH="main"
    export STATE_DIR="$s8_state" COORD_SYNC_FLOOR_SECONDS=999999
    export COORD_SYNC_EXPORTER_CMD="echo run >> '$s8_count'"
    export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
    bash "$SELF_PATH" >/dev/null 2>&1
  )
  local s8_runs; s8_runs=$(wc -l < "$s8_count" 2>/dev/null | tr -d ' ')
  [ "$s8_runs" = "1" ] && [ ! -f "$s8_state/dirty" ]
  _ck "5 events between fires coalesce into exactly ONE cycle (burst coalescing; publish rate bounded by the fire interval)" $?
  for i8 in 1 2 3 4 5 6 7 8; do
    (
      export COORD_REPO_URL="$bare" COORD_CLONE_DIR="$tmproot/s8-clone" COORD_BRANCH="main"
      export STATE_DIR="$s8_state" COORD_SYNC_FLOOR_SECONDS=999999
      export COORD_SYNC_DEBOUNCE_LOG_MAX_LINES=5
      export COORD_SYNC_EXPORTER_CMD="echo run >> '$s8_count'"
      export COORD_SYNC_PUSH_CMD="true" COORD_SYNC_PULL_CMD="true"
      bash "$SELF_PATH" >/dev/null 2>&1
    )
  done
  s8_runs=$(wc -l < "$s8_count" 2>/dev/null | tr -d ' ')
  local s8_dlines; s8_dlines=$(wc -l < "$s8_state/debounce.log" 2>/dev/null | tr -d ' ')
  [ "$s8_runs" = "1" ] && [ "$s8_dlines" -le 5 ]
  _ck "8 clean fires -> zero extra cycles; debounce.log rotated to its own cap (skips never crowd cycles.log)" $?

  # ======== Scenario 9 (Task 7, A5 iv): lock-stale threshold VERIFIED at
  # the new cadence — 900s default must exceed the scheduled task's
  # ExecutionTimeLimit (the hard bound on a LIVE cycle's duration), so a
  # >=900s-old lock is provably crashed, never a slow live holder. ========
  local s9_ps1="$SELF_DIR/install-coord-sync-task.ps1"
  local s9_limit_min
  s9_limit_min=$(grep -oE 'ExecutionTimeLimit \(New-TimeSpan -Minutes [0-9]+' "$s9_ps1" 2>/dev/null | grep -oE '[0-9]+$' | head -n1)
  [ -n "$s9_limit_min" ] && [ "$LOCK_STALE_SECONDS" -gt $(( s9_limit_min * 60 )) ]
  _ck "LOCK_STALE_SECONDS default (${LOCK_STALE_SECONDS}s) > installer ExecutionTimeLimit (${s9_limit_min:-?}min) — stale reclaim can never seize a live cycle's lock" $?

  rm -rf "$tmproot" 2>/dev/null || true
  echo "[self-test] coord-sync: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# ============================================================
# Entry
# ============================================================
SELF_PATH="${BASH_SOURCE[0]}"

case "${1:-}" in
  --self-test) _self_test; exit $? ;;
  --help|-h)
    sed -n '2,140p' "$SELF_PATH" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  --force)       _main 1; exit $? ;;
  "")            _main 0; exit $? ;;
  *)             _warn "unknown subcommand: $1"; exit 0 ;;
esac
