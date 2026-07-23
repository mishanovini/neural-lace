#!/bin/bash
# supervisor-tick.sh — the operator's never-stall mechanism (continuous-
# operation program, docs/reviews/2026-07-19-continuous-operation-design-
# input.md round 2, Q6 disposition: "SOME periodic task survives — but it
# should be ONE task: the per-machine SUPERVISOR tick").
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# Operator mandate (2026-07-20, verbatim): "Aren't you supposed to have
# mechanisms in place to keep things from stopping and going stale? ... I
# told you to design this system so that it is continuously always making
# progress and never stops." The observed failure class (3x in two days,
# per the round-2 design doc's "Sessions are mortal" section): background
# agents + their completion notifications die with the Claude Code process;
# orphaned obligations (uncommitted worktree fixes, unflipped plan tasks,
# dead fix-waves) sit stale until the operator manually notices. Concrete
# incidents cited by the design doc: the NL Observability session died of
# context exhaustion mid-integration (work stranded in worktrees, found
# only because the operator asked); a reboot killed four builders and a
# review batch mid-flight; a "dead" session later REVIVED and raced the
# replacement orchestrator. A fourth, git-provable instance: the 2026-07-19
# harness-review batch (commit aeaf9d8) returned REFORMULATE on
# coord-sync.sh but the session died before persisting the finding — the
# fix wave landed on branch `build/harness-reform-f123` and NEVER MERGED,
# discovered only when a later session re-derived it from scratch
# (docs/reviews/2026-07-20-f1-f3-rederived-harness-review.md: "The prior
# fix wave ... never landed — branch empty vs origin/master"). This tick
# is the MINIMAL slice that makes that class of loss visible the moment it
# happens, independent of whether any session is open to notice it —
# closing the same gap health-tick.sh (ADR-061 D6) closed for
# doctor/scheduled-task/heartbeat health, but for STRANDED WORK OBLIGATIONS
# specifically (a surface health-tick's three steps do not cover).
#
# ============================================================
# WHAT ONE TICK DOES (observe-first; never destroys, never spawns claude)
# ============================================================
#
#   (a) Runs the ALREADY-DEPLOYED detector
#       `worktree-hygiene-sweep.sh --stranded --porcelain` (the 7-field
#       contract: ORPHANED-HOLDS-CONTENT<TAB>path<TAB>branch<TAB>dirty<TAB>
#       unintegrated<TAB>age_days<TAB>liveness — see that script's own
#       header). That detector ALREADY joins the worktree's dirty/
#       unintegrated state against session-heartbeat-lib.sh's liveness
#       classification internally (live/throttled/crashed/CONTINUING-grace/
#       claim) — this tick does NOT re-implement that join (a second,
#       drifting implementation of "is this owned" is exactly the
#       CANONICAL-COUNTERS-01 class of bug the sweep's own header warns
#       against). What THIS tick adds on top, read-only, via the SAME
#       shared heartbeat surface (`session-heartbeat.sh sweep --json`):
#       a machine-wide "how many live/throttled sessions exist right now"
#       count, folded into the alert text as context (distinguishes
#       "nobody is home at all" from "sessions are active but none owns
#       this specific worktree").
#   (b) For every ORPHANED-HOLDS-CONTENT row: NEVER auto-destroys or
#       auto-cherry-picks anything (this tick has no --prune-equivalent
#       path at all). Writes a durable alert into TWO existing surfaces —
#         1. `needs-you.sh add --section question` (one bullet per
#            orphan, in "Open questions" — viewable in NEEDS-YOU.md at the
#            MAIN checkout root any time, with or without a session open)
#         2. one aggregated JSON file into the EXISTING
#            ~/.claude/state/external-monitor-alerts/ directory, in the
#            EXACT schema external-monitor-alert-surfacer.sh already
#            consumes (schema_version 1 / started_at / ended_at /
#            total_routes / healthy_count / anomaly_count /
#            slow_threshold_ms / results[]) — reused byte-for-byte, same
#            convention health-tick.sh already established, so the
#            existing SessionStart surfacer renders this tick's findings
#            with zero changes to that file.
#       plus a per-orphan STATE LEDGER record (~/.claude/state/supervisor/
#       orphans/<key>.json — one file per orphaned worktree, keyed by a
#       cksum of path+branch) so a re-fire is IDEMPOTENT: an orphan already
#       alerted is not re-alerted every tick (only after
#       SUPERVISOR_TICK_REALERT_HOURS, default 24h, have passed with it
#       STILL orphaned) — this is what keeps NEEDS-YOU.md and the alert
#       dir from being spammed on every 5-minute fire.
#
#       RESPAWN GAP (named honestly, not built here): the round-2 design
#       doc's REAPER component (§3) additionally imagines "auto-triage" —
#       an Inbox item offering rehome-or-discard, or auto-cherry-pick when
#       patch-clean. This tick ships the ALERT half only (rehome-or-discard
#       IS exactly what the needs-you.sh question entry asks). It does NOT
#       attempt any auto-cherry-pick or any session/build RESPAWN: the only
#       respawn primitive this harness has (session-resumer.sh, ADR-061) is
#       for RESUMING A DEAD SESSION BY ID via `claude -p --resume`, is
#       explicitly UNARMED (the `~/.claude/local/resumer-armed.txt` marker
#       is absent by design — arming requires its own multi-day Phase-2
#       checklist: >=5 days shadow metrics, a live kill-drill, and an
#       explicit operator-created marker; see docs/reviews/2026-07-17-
#       circuit-continuous-building-design-sketch.md §4.4), and even once
#       armed it resumes a SESSION, not a bare orphaned WORKTREE (which may
#       have no still-resolvable owning session id at all once its
#       heartbeat file has aged out). No orphaned-worktree-specific respawn
#       primitive exists anywhere in this harness today. Filed as
#       SUPERVISOR-TICK-RESPAWN-GAP-01 via nl-issue.sh at build time (see
#       the build's own commit/report) rather than guessed at here.
#   (c) BOUNDED + NEVER-BLOCKING: every fork (the sweep, the heartbeat
#       sweep, each needs-you.sh add) runs under `timeout` against the
#       remaining wall-clock budget (SUPERVISOR_TICK_BUDGET_SECS, default
#       120s); a timed-out or missing detector WARNS (one alert result,
#       verdict SWEEP_TIMEOUT / DETECTOR_MISSING) and returns 0 — this
#       script NEVER exits nonzero on any path (observability, not
#       enforcement, mirrors health-tick.sh's own contract). Idempotent
#       per fire (re-running immediately produces the same ledger state,
#       no duplicate alerts — see (b)). Its own run log
#       (~/.claude/state/supervisor/tick.log) rotates at ~200KB
#       (tail-keep newest 500 lines — the same house pattern
#       agent-commit-gate.sh's probe log uses).
#
# ============================================================
# ENV OVERRIDES (HARNESS_SELFTEST house convention)
# ============================================================
#
#   SUPERVISOR_STATE_DIR         ledger + log dir (default
#                                 $HOME/.claude/state/supervisor;
#                                 HARNESS_SELFTEST=1 sandboxes under TMPDIR)
#   SUPERVISOR_ALERT_DIR          external-monitor-alerts dir override
#                                 (default $HOME/.claude/state/
#                                 external-monitor-alerts)
#   SUPERVISOR_TICK_REPOS         newline- or space-in-one-line-separated
#                                 repo path(s) to sweep. Default: resolve
#                                 via nl_repo_root() (hooks/lib/
#                                 nl-paths.sh); if that is unresolvable,
#                                 falls through to worktree-hygiene-
#                                 sweep.sh's own no-args discovery.
#   SUPERVISOR_TICK_SWEEP_BIN     path to worktree-hygiene-sweep.sh
#                                 (default: sibling script in this dir)
#   SUPERVISOR_TICK_BUDGET_SECS   wall-clock budget (default 120)
#   SUPERVISOR_TICK_REALERT_HOURS hours before a still-orphaned worktree is
#                                 re-alerted (default 24)
#   (heartbeat/claim sandboxing is inherited by the underlying scripts'
#   own HEARTBEAT_STATE_DIR / COG_CLAIMS_DIR / OBS_TRANSCRIPTS_ROOT /
#   NEEDS_YOU_STATE_DIR / NEEDS_YOU_MD_PATH contracts unchanged)
#
# Self-test: --self-test (fixture-driven; builds real git worktrees +
# heartbeat fixtures against the REAL, unmodified worktree-hygiene-sweep.sh
# — the pre-existing oracle for "is this orphaned" — rather than stubbing
# its output; never touches real machine state).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"

# shellcheck disable=SC1091
[[ -f "$HOOKS_DIR/lib/nl-paths.sh" ]] && source "$HOOKS_DIR/lib/nl-paths.sh" 2>/dev/null || true

# ----------------------------------------------------------------------
# Path resolution (mirrors health-tick.sh's _ht_alert_dir convention)
# ----------------------------------------------------------------------
_st_state_dir() {
  if [[ -n "${SUPERVISOR_STATE_DIR:-}" ]]; then
    printf '%s' "$SUPERVISOR_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/supervisor-tick-selftest/%s/state' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/supervisor' "${HOME:-$PWD}"
}

_st_alert_dir() {
  if [[ -n "${SUPERVISOR_ALERT_DIR:-}" ]]; then
    printf '%s' "$SUPERVISOR_ALERT_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/supervisor-tick-selftest/%s/alerts' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/external-monitor-alerts' "${HOME:-$PWD}"
}

_st_now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown; }
_st_now_epoch() { date -u +%s 2>/dev/null || echo 0; }

_st_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/ }"
  s="${s//$cr/ }"
  s="${s//$tab/ }"
  printf '%s' "$s"
}

# _st_field <file> <key> — best-effort JSON scalar read (string or bare
# number), no jq dependency (mirrors concurrent-ownership-gate.sh's own
# sed -nE extraction convention). Never errors; empty on any miss.
_st_field() {
  local f="$1" k="$2" v
  [[ -f "$f" ]] || { printf ''; return 0; }
  v="$(sed -nE "s/.*\"${k}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$f" 2>/dev/null | head -1)"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi
  sed -nE "s/.*\"${k}\"[[:space:]]*:[[:space:]]*([0-9.]+).*/\1/p" "$f" 2>/dev/null | head -1
}

# _st_key <path> <branch> — stable, portable dedup key (cksum, already used
# elsewhere in this codebase — close-plan.sh, plan-lifecycle.sh — for the
# same "turn a string into a safe filename stem" need).
_st_key() { printf '%s|%s' "$1" "$2" | cksum | awk '{print $1}'; }

_st_log_file() { printf '%s/tick.log' "$(_st_state_dir)"; }

# _st_log <line> — append one line to the rotating run log. Rotation: keep
# the file bounded (~200KB) — tail-keep the newest 500 lines (the SAME
# house pattern agent-commit-gate.sh's probe log uses).
_st_log() {
  local dir log
  dir="$(_st_state_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  log="$(_st_log_file)"
  if [[ -f "$log" ]] && [[ "$(wc -c < "$log" 2>/dev/null || echo 0)" -gt 200000 ]]; then
    tail -n 500 "$log" > "$log.tmp" 2>/dev/null && mv "$log.tmp" "$log" 2>/dev/null
  fi
  printf '%s [supervisor-tick] %s\n' "$(_st_now_iso)" "$1" >> "$log" 2>/dev/null || true
}

# _st_run <timeout_secs> <cmd...> — bounded fork (timeout-wrap every fork,
# scope item (c)). Falls back to unbounded exec when `timeout` is
# unavailable on the platform (never a hard dependency).
_st_run() {
  local secs="$1"; shift
  if [[ "$secs" -le 0 ]] 2>/dev/null; then secs=1; fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "${secs}s" "$@"
  else
    "$@"
  fi
}

# ----------------------------------------------------------------------
# _st_resolve_repos — sets global array ST_REPOS. Paths may contain
# spaces (e.g. this very machine's "Pocket Technician" segment) — read
# line-by-line into an array, never naive word-splitting.
# ----------------------------------------------------------------------
ST_REPOS=()
_st_resolve_repos() {
  ST_REPOS=()
  if [[ -n "${SUPERVISOR_TICK_REPOS:-}" ]]; then
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && ST_REPOS+=("$line")
    done <<< "$SUPERVISOR_TICK_REPOS"
    [[ "${#ST_REPOS[@]}" -gt 0 ]] && return 0
  fi
  if declare -F nl_repo_root >/dev/null 2>&1; then
    local r
    r="$(nl_repo_root)"
    if [[ -n "$r" ]]; then
      ST_REPOS=("$r")
      return 0
    fi
  fi
  ST_REPOS=()
  return 0
}

# ----------------------------------------------------------------------
# _st_write_alert <verdict> <path> <detail> — single-anomaly alert
# (DETECTOR_MISSING / SWEEP_TIMEOUT). Same schema as the aggregate writer
# below and as health-tick.sh's own alert JSON (reused byte-for-byte so
# external-monitor-alert-surfacer.sh needs zero changes).
# ----------------------------------------------------------------------
_st_write_alert_single() {
  local verdict="$1" path="$2" detail="$3"
  local result
  result="$(printf '{"label":"supervisor-tick","method":"TICK","path":"%s","expected":"stranded-scan-ok","status":"error","elapsed_ms":0,"verdict":"%s","failure_reason":"%s"}' \
    "$(_st_json_escape "$path")" "$(_st_json_escape "$verdict")" "$(_st_json_escape "$detail")")"
  _st_flush_alert 0 1 "$result"
}

# _st_flush_alert <healthy_count> <anomaly_count> <result-json-1> [result-json-2 ...]
_st_flush_alert() {
  local healthy="$1" anomalies="$2"; shift 2
  local alert_dir alert_file ts_name results_json="" r first=1
  alert_dir="$(_st_alert_dir)"
  mkdir -p "$alert_dir" 2>/dev/null || true
  ts_name="$(date -u '+%Y-%m-%dT%H-%M-%SZ' 2>/dev/null || echo "unknown-$$")"
  alert_file="$alert_dir/${ts_name}-supervisor-tick.json"
  for r in "$@"; do
    if [[ "$first" == "1" ]]; then first=0; else results_json+=","; fi
    results_json+="$r"
  done
  local tmp_alert
  tmp_alert="$(mktemp "${alert_file}.XXXXXX" 2>/dev/null || printf '%s.tmp' "$alert_file")"
  printf '{"schema_version":1,"monitor_url":"nl-supervisor-tick (local harness watchdog, continuous-operation round-2 Q6)","started_at":"%s","ended_at":"%s","total_routes":%d,"healthy_count":%d,"anomaly_count":%d,"slow_threshold_ms":%d,"results":[%s]}\n' \
    "$(_st_now_iso)" "$(_st_now_iso)" "$(( healthy + anomalies ))" "$healthy" "$anomalies" "$(( ${SUPERVISOR_TICK_BUDGET_SECS:-120} * 1000 ))" "$results_json" \
    > "$tmp_alert" 2>/dev/null && mv "$tmp_alert" "$alert_file" 2>/dev/null || rm -f "$tmp_alert" 2>/dev/null
  [[ -f "$alert_file" ]] && printf '%s' "$alert_file"
}

# ----------------------------------------------------------------------
# run_tick — the real tick. Always returns 0.
# ----------------------------------------------------------------------
run_tick() {
  SECONDS=0
  local budget="${SUPERVISOR_TICK_BUDGET_SECS:-120}"
  local sweep_bin="${SUPERVISOR_TICK_SWEEP_BIN:-$SCRIPT_DIR/worktree-hygiene-sweep.sh}"
  local state_dir orphans_dir
  state_dir="$(_st_state_dir)"
  orphans_dir="$state_dir/orphans"
  mkdir -p "$orphans_dir" 2>/dev/null || true

  _st_log "tick start (budget=${budget}s, sweep_bin=${sweep_bin})"

  # ---- (a0) graceful degradation: detector missing --------------------
  if [[ ! -f "$sweep_bin" ]]; then
    _st_log "WARN: stranded-worktree detector not found at ${sweep_bin} — skipping orphan scan this fire (graceful, no crash)"
    _st_write_alert_single "DETECTOR_MISSING" "$sweep_bin" "worktree-hygiene-sweep.sh not found — orphan detection skipped this fire"
    echo "[supervisor-tick] WARN: detector missing at ${sweep_bin} (logged + alerted; never crashes)"
    return 0
  fi

  _st_resolve_repos

  # ---- (a) run the deployed detector -----------------------------------
  local sweep_out sweep_rc remaining
  remaining=$(( budget - SECONDS ))
  [[ "$remaining" -le 0 ]] && remaining=1
  sweep_out="$(_st_run "$remaining" bash "$sweep_bin" --stranded --porcelain "${ST_REPOS[@]}" 2>&1)"
  sweep_rc=$?

  if [[ "$sweep_rc" -eq 124 ]]; then
    _st_log "WARN: sweep timed out after ${remaining}s"
    _st_write_alert_single "SWEEP_TIMEOUT" "$sweep_bin" "worktree-hygiene-sweep.sh --stranded timed out after ${remaining}s"
    echo "[supervisor-tick] WARN: detector timed out (logged + alerted; never crashes)"
    return 0
  elif [[ "$sweep_rc" -ne 0 ]]; then
    _st_log "WARN: sweep exited rc=${sweep_rc}: ${sweep_out:0:300}"
  fi

  # ---- machine-wide liveness enrichment (read-only; reuses the SAME
  # heartbeat surface the sweep already joins internally — never a second
  # implementation of "is this owned") -----------------------------------
  local live_sessions=0
  local hb_script="$SCRIPT_DIR/session-heartbeat.sh"
  if [[ -f "$hb_script" ]]; then
    remaining=$(( budget - SECONDS )); [[ "$remaining" -le 0 ]] && remaining=1
    local hb_json
    hb_json="$(_st_run "$remaining" bash "$hb_script" sweep --json 2>/dev/null || echo '[]')"
    local n_live n_throttled
    n_live="$(printf '%s' "$hb_json" | grep -o '"state":"live"' | wc -l | tr -d ' ')"
    n_throttled="$(printf '%s' "$hb_json" | grep -o '"state":"throttled"' | wc -l | tr -d ' ')"
    live_sessions=$(( ${n_live:-0} + ${n_throttled:-0} ))
  fi

  # ---- (b) classify + alert (idempotent via the per-orphan ledger) ------
  local total_orphans=0 new_count=0
  local -a alert_results=()
  local seen_file
  seen_file="$(mktemp 2>/dev/null || printf '%s/seen.XXXXXX' "${TMPDIR:-/tmp}")"

  while IFS=$'\t' read -r tag path branch dirty uniq age liveness; do
    [[ "$tag" == "ORPHANED-HOLDS-CONTENT" ]] || continue
    [[ -n "$path" ]] || continue
    total_orphans=$(( total_orphans + 1 ))

    local key rec now_iso now_epoch
    key="$(_st_key "$path" "$branch")"
    rec="$orphans_dir/${key}.json"
    now_iso="$(_st_now_iso)"
    now_epoch="$(_st_now_epoch)"
    echo "$key" >> "$seen_file"

    local first_seen="$now_iso" last_alerted="$now_iso" alert_count=1 should_alert=1
    if [[ -f "$rec" ]]; then
      local old_first old_last_alerted old_count last_alerted_epoch realert_after
      old_first="$(_st_field "$rec" first_seen)"
      [[ -n "$old_first" ]] && first_seen="$old_first"
      old_last_alerted="$(_st_field "$rec" last_alerted)"
      old_count="$(_st_field "$rec" alert_count)"
      [[ -n "$old_count" ]] || old_count=0
      realert_after=$(( ${SUPERVISOR_TICK_REALERT_HOURS:-24} * 3600 ))
      last_alerted_epoch=0
      if [[ -n "$old_last_alerted" ]]; then
        last_alerted_epoch="$(date -u -d "$old_last_alerted" +%s 2>/dev/null || echo 0)"
      fi
      if [[ $(( now_epoch - last_alerted_epoch )) -ge "$realert_after" ]]; then
        should_alert=1
        alert_count=$(( old_count + 1 ))
      else
        should_alert=0
        alert_count="$old_count"
        last_alerted="$old_last_alerted"
        [[ -n "$last_alerted" ]] || last_alerted="$now_iso"
      fi
    fi

    # write/refresh the ledger record unconditionally (last_seen always
    # advances; last_alerted/alert_count only advance when should_alert=1)
    local tmp_rec
    tmp_rec="$(mktemp "${rec}.XXXXXX" 2>/dev/null || printf '%s.tmp' "$rec")"
    printf '{"path":"%s","branch":"%s","dirty":%s,"unintegrated":%s,"age_days":%s,"liveness":"%s","first_seen":"%s","last_seen":"%s","last_alerted":"%s","alert_count":%s}\n' \
      "$(_st_json_escape "$path")" "$(_st_json_escape "$branch")" "${dirty:-0}" "${uniq:-0}" "${age:-0}" "$(_st_json_escape "$liveness")" \
      "$first_seen" "$now_iso" "$last_alerted" "$alert_count" \
      > "$tmp_rec" 2>/dev/null && mv "$tmp_rec" "$rec" 2>/dev/null

    if [[ "$should_alert" == "1" ]]; then
      new_count=$(( new_count + 1 ))
      local text
      text="Orphaned worktree obligation: ${path} (branch ${branch}, dirty=${dirty:-0} file(s), unintegrated=${uniq:-0} commit(s), last commit ${age:-0}d ago, liveness=${liveness}). No live session currently owns it (this machine has ${live_sessions} live/throttled session(s) right now, none claiming this worktree). Rehome (finish + commit/cherry-pick to master) or discard (git worktree remove, after salvage) — see worktree-hygiene-sweep.sh --stranded for the exact salvage command. First detected ${first_seen}; alert #${alert_count}."
      remaining=$(( budget - SECONDS )); [[ "$remaining" -le 0 ]] && remaining=1
      _st_run "$remaining" bash "$SCRIPT_DIR/needs-you.sh" add --section question --text "$text" --session "supervisor-tick" >/dev/null 2>&1 || true
      alert_results+=("$(printf '{"label":"orphaned-worktree","method":"TICK","path":"%s","expected":"live-owner","status":"orphaned","elapsed_ms":0,"verdict":"ORPHANED_WORKTREE","failure_reason":"%s"}' \
        "$(_st_json_escape "$path")" "$(_st_json_escape "branch=${branch} dirty=${dirty:-0} unintegrated=${uniq:-0} age=${age:-0}d liveness=${liveness} alert#${alert_count}")")")
      _st_log "ALERT (alert #${alert_count}): ${path} branch=${branch} liveness=${liveness}"
    fi
  done <<< "$sweep_out"

  # ---- reconcile: prune ledger records for worktrees no longer orphaned
  # (resolved, integrated, live-owned-now, or removed) so a LATER
  # re-orphaning of the same path re-alerts fresh, and the ledger never
  # grows unbounded (TTL'd files, nothing scattered — Q5 point 3). ------
  local f fkey
  for f in "$orphans_dir"/*.json; do
    [[ -f "$f" ]] || continue
    fkey="$(basename "$f" .json)"
    if ! grep -Fxq "$fkey" "$seen_file" 2>/dev/null; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
  rm -f "$seen_file" 2>/dev/null || true

  if [[ "${#alert_results[@]}" -gt 0 ]]; then
    local healthy_here=$(( total_orphans - new_count ))
    [[ "$healthy_here" -lt 0 ]] && healthy_here=0
    local wrote
    wrote="$(_st_flush_alert "$healthy_here" "$new_count" "${alert_results[@]}")"
    _st_log "wrote alert: ${wrote:-<write-failed>}"
  fi

  _st_log "tick done in ${SECONDS}s: total_orphans=${total_orphans} alerted_this_fire=${new_count} live_sessions=${live_sessions}"
  echo "[supervisor-tick] ${total_orphans} orphan(s) found, ${new_count} alerted this fire, ${live_sessions} live session(s) machine-wide, done in ${SECONDS}s"
  return 0
}

# ============================================================
# --self-test (fixture-driven; sandboxed; runs the REAL, unmodified
# worktree-hygiene-sweep.sh — the pre-existing oracle for "is this
# orphaned" — rather than stubbing its output)
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local SWEEP="$SCRIPT_DIR/worktree-hygiene-sweep.sh"
  if [[ ! -f "$SWEEP" ]]; then
    echo "self-test: cannot find worktree-hygiene-sweep.sh at $SWEEP — aborting self-test" >&2
    return 1
  fi

  local T
  T="$(mktemp -d 2>/dev/null || mktemp -d -t sptst)"
  if [[ -z "$T" || ! -d "$T" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$T/hb"
  export COG_CLAIMS_DIR="$T/claims"
  export OBS_TRANSCRIPTS_ROOT="$T/tx"
  export NEEDS_YOU_STATE_DIR="$T/ny-state"
  export NEEDS_YOU_MD_PATH="$T/NEEDS-YOU.md"
  export SUPERVISOR_STATE_DIR="$T/sup-state"
  export SUPERVISOR_ALERT_DIR="$T/alerts"
  # Generous budget for the self-test specifically (NOT the production
  # default): the real worktree-hygiene-sweep.sh forks dozens of git
  # subprocesses per worktree, and on a heavily-loaded dev machine (many
  # concurrent Claude Code sessions/builders) each fork has been measured
  # up to several seconds — a tight budget here would produce a false
  # SWEEP_TIMEOUT that is a MACHINE-LOAD artifact, not a real regression.
  # Production ticks keep the tighter default (120s) via this same env var.
  export SUPERVISOR_TICK_BUDGET_SECS=600
  mkdir -p "$HEARTBEAT_STATE_DIR" "$COG_CLAIMS_DIR" "$OBS_TRANSCRIPTS_ROOT" "$SUPERVISOR_STATE_DIR" "$SUPERVISOR_ALERT_DIR"

  local SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

  # ---- fixture repo: primary + two secondary worktrees, both dirty -----
  local past srepo
  past=$(( $(date +%s) - 30 * 86400 ))
  srepo="$T/srepo"
  git init -q "$srepo"
  git -C "$srepo" config user.email test@example.com
  git -C "$srepo" config user.name "Self Test"
  git -C "$srepo" config core.hooksPath ""
  git -C "$srepo" symbolic-ref HEAD refs/heads/master
  echo base > "$srepo/f.txt"
  git -C "$srepo" add f.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$srepo" -c commit.gpgsign=false commit -qm "init (30d ago)"

  # wt-orphan: dirty secondary worktree with a DEAD-pid, ancient heartbeat
  # -> the real sweep classifies it ORPHANED-HOLDS-CONTENT.
  git -C "$srepo" worktree add -q "$T/wt-orphan" -b wt-orphan >/dev/null 2>&1
  echo scratch > "$T/wt-orphan/untracked.txt"
  local dead_pid
  ( : ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null
  cat > "$HEARTBEAT_STATE_DIR/sess-dead.json" <<EOF
{"schema":1,"session_id":"sess-dead","pid":${dead_pid},"cwd":"$T/wt-orphan","repo_root":"$T/wt-orphan","worktree_root":"$T/wt-orphan","branch":"wt-orphan","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF

  # wt-live: dirty secondary worktree with a LIVE-pid, fresh heartbeat ->
  # the real sweep classifies it LIVE-OWNED-HOLDS-CONTENT (never in
  # --stranded output at all) -> the FP guard scenario.
  git -C "$srepo" worktree add -q "$T/wt-live" -b wt-live >/dev/null 2>&1
  echo scratch > "$T/wt-live/untracked.txt"
  cat > "$HEARTBEAT_STATE_DIR/sess-live.json" <<EOF
{"schema":1,"session_id":"sess-live","pid":$$,"cwd":"$T/wt-live","repo_root":"$T/wt-live","worktree_root":"$T/wt-live","branch":"wt-live","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF

  export SUPERVISOR_TICK_REPOS="$srepo"

  echo "Scenario 1: fake stranded worktree + dead heartbeat -> alert fires (needs-you + alert file + ledger record)"
  local out1 rc1
  out1="$(bash "$SELF" 2>&1)"; rc1=$?
  [[ "$rc1" -eq 0 ]] && pass "tick exits 0" || fail "tick exited $rc1"
  echo "$out1" | grep -q '1 orphan(s) found, 1 alerted'
  pass_or_fail=$?
  if echo "$out1" | grep -q '1 orphan(s) found, 1 alerted'; then
    pass "exactly 1 orphan found + 1 alerted this fire"
  else
    fail "expected '1 orphan(s) found, 1 alerted'; got: $out1"
  fi
  if [[ -f "$NEEDS_YOU_MD_PATH" ]] && grep -q 'wt-orphan' "$NEEDS_YOU_MD_PATH" 2>/dev/null; then
    pass "NEEDS-YOU.md carries an entry naming the orphaned worktree"
  else
    fail "NEEDS-YOU.md missing or does not mention wt-orphan: $(cat "$NEEDS_YOU_MD_PATH" 2>/dev/null)"
  fi
  local n_alerts
  n_alerts="$(ls "$SUPERVISOR_ALERT_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n_alerts" == "1" ]] && pass "exactly one alert file written" || fail "expected exactly 1 alert file, got $n_alerts"
  local alert_f
  alert_f="$(ls "$SUPERVISOR_ALERT_DIR"/*.json 2>/dev/null | head -1)"
  if [[ -n "$alert_f" ]] && grep -q 'ORPHANED_WORKTREE' "$alert_f" 2>/dev/null && grep -q 'wt-orphan' "$alert_f" 2>/dev/null; then
    pass "alert JSON carries ORPHANED_WORKTREE verdict naming wt-orphan"
  else
    fail "alert JSON missing expected fields: $(cat "$alert_f" 2>/dev/null)"
  fi
  local n_ledger
  n_ledger="$(ls "$SUPERVISOR_STATE_DIR"/orphans/*.json 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n_ledger" == "1" ]] && pass "exactly one ledger record (wt-live never recorded)" || fail "expected exactly 1 ledger record, got $n_ledger"

  echo "Scenario 1b: re-fire immediately -> IDEMPOTENT (no duplicate needs-you entry, no new alert file)"
  local ny_count_before ny_count_after
  ny_count_before="$(grep -c 'wt-orphan' "$NEEDS_YOU_MD_PATH" 2>/dev/null || echo 0)"
  local out2
  out2="$(bash "$SELF" 2>&1)"
  ny_count_after="$(grep -c 'wt-orphan' "$NEEDS_YOU_MD_PATH" 2>/dev/null || echo 0)"
  if [[ "$ny_count_after" == "$ny_count_before" ]]; then
    pass "re-fire within the re-alert TTL adds NO new NEEDS-YOU mention of wt-orphan (idempotent)"
  else
    fail "re-fire duplicated the NEEDS-YOU entry: before=$ny_count_before after=$ny_count_after"
  fi
  n_alerts="$(ls "$SUPERVISOR_ALERT_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n_alerts" == "1" ]] && pass "re-fire wrote NO new alert file (still exactly 1)" || fail "re-fire wrote extra alert file(s): now $n_alerts"
  if echo "$out2" | grep -q '1 orphan(s) found, 0 alerted'; then
    pass "re-fire reports 1 orphan found, 0 newly alerted"
  else
    fail "expected '1 orphan(s) found, 0 alerted' on re-fire; got: $out2"
  fi

  echo "Scenario 2: live-heartbeat-owned worktree (wt-live) -> silent, never mentioned anywhere"
  if ! grep -q 'wt-live' "$NEEDS_YOU_MD_PATH" 2>/dev/null; then
    pass "wt-live (live-owned) never appears in NEEDS-YOU.md (FP guard holds)"
  else
    fail "wt-live incorrectly surfaced in NEEDS-YOU.md"
  fi
  if ! grep -rq 'wt-live' "$SUPERVISOR_ALERT_DIR" 2>/dev/null; then
    pass "wt-live never appears in any alert file"
  else
    fail "wt-live incorrectly appears in an alert file"
  fi
  if ! grep -rq 'wt-live' "$SUPERVISOR_STATE_DIR/orphans" 2>/dev/null; then
    pass "wt-live never gets a ledger record"
  else
    fail "wt-live incorrectly got a ledger record"
  fi

  echo "Scenario 3: detector missing -> graceful WARN, exit 0, never crashes"
  local out3 rc3
  out3="$(SUPERVISOR_TICK_SWEEP_BIN="$T/does-not-exist-sweep.sh" bash "$SELF" 2>&1)"; rc3=$?
  [[ "$rc3" -eq 0 ]] && pass "missing-detector tick still exits 0" || fail "missing-detector tick exited $rc3"
  if echo "$out3" | grep -q 'WARN.*detector missing'; then
    pass "missing-detector tick logs a WARN naming the gap"
  else
    fail "expected a WARN mentioning 'detector missing'; got: $out3"
  fi
  local n_alerts3
  n_alerts3="$(ls "$SUPERVISOR_ALERT_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  if [[ -n "$(grep -l 'DETECTOR_MISSING' "$SUPERVISOR_ALERT_DIR"/*.json 2>/dev/null)" ]]; then
    pass "a DETECTOR_MISSING alert was written (visible, not swallowed)"
  else
    fail "expected a DETECTOR_MISSING alert file among: $(ls "$SUPERVISOR_ALERT_DIR" 2>/dev/null)"
  fi

  echo "Scenario 4: re-alert after TTL expiry re-fires (honest non-staleness, not permanent silence)"
  local rec_f
  rec_f="$(ls "$SUPERVISOR_STATE_DIR"/orphans/*.json 2>/dev/null | head -1)"
  if [[ -n "$rec_f" ]]; then
    # backdate last_alerted well past the default 24h TTL
    sed -i -E 's/"last_alerted":"[^"]*"/"last_alerted":"2020-01-01T00:00:00Z"/' "$rec_f" 2>/dev/null
    local out4
    out4="$(bash "$SELF" 2>&1)"
    if echo "$out4" | grep -q '1 orphan(s) found, 1 alerted'; then
      pass "orphan past the re-alert TTL is alerted again (not silently forgotten)"
    else
      fail "expected re-alert after TTL expiry; got: $out4"
    fi
  else
    fail "no ledger record present to backdate for the TTL scenario"
  fi

  rm -rf "$T" 2>/dev/null || true
  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help)
    sed -n '2,140p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "")
    run_tick
    exit 0
    ;;
  *)
    echo "supervisor-tick.sh: unknown argument '$1' (run with -h for usage; never blocks)" >&2
    exit 0
    ;;
esac
