#!/bin/bash
# health-tick.sh — session-independent, PASSIVE hourly health tick
# (ADR-061 D6: "who notices when nothing is running").
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# O.6 scheduled-task health and the doctor's --quick verdict are BUILT and
# wired, but both only run when a session is open (SessionStart) or when
# the operator invokes them by hand. A RED that appears while no session
# is open goes unnoticed until the next session happens to start. This
# tick closes that gap: an OS scheduled task (NL-health-tick, hourly —
# registration lives in install.sh, Phase-1 ops step) runs the three
# existing health surfaces and, on any RED/anomaly, writes ONE alert file
# that the EXISTING external-monitor-alert-surfacer.sh SessionStart hook
# surfaces at the next session start. Live consumer chain (ADR-060 law 2):
# alert file -> external-monitor-alert-surfacer.sh (wired SessionStart
# hook) + session-start-digest.sh feed 3; doctor-cache refresh ->
# session-start-digest.sh feed_doctor (feed 8).
#
# ============================================================
# SAFETY CONTRACT (ADR-061 D6 + §5 invariants)
# ============================================================
#
# - PASSIVE: this script NEVER spawns `claude` (no resume, no nudge, no
#   prompt — nothing). It only runs the three existing report/hygiene
#   surfaces below and writes files.
# - MUST NOT set NL_HOOK_REENTRY: harness-doctor.sh honors the reentry
#   guard and would self-suppress its checks (run_quick_checks no-ops),
#   silently defeating the tick's purpose (ADR-061 reviewer finding,
#   Minor). This is a claude-free tick that legitimately needs the
#   doctor/reap to actually run. The self-test proves the child env.
# - BOUNDED: internal wall-clock budget (HEALTH_TICK_BUDGET_SECS, default
#   300s = 5min). When the budget is exhausted mid-run, remaining steps
#   are SKIPPED gracefully (logged as skipped, never counted as
#   anomalies) and whatever was observed so far is still reported.
# - NEVER BLOCKS: exit 0 on every path (writer semantics — a health tick
#   is observability, not enforcement). Every step failure is tolerated
#   and recorded, never propagated as a nonzero exit.
#
# ============================================================
# WHAT ONE TICK DOES
# ============================================================
#
#   (a) doctor cache refresh — `session-start-digest.sh
#       --refresh-doctor-cache`, the ONE sanctioned path that runs
#       `harness-doctor.sh --quick` for real and writes
#       ~/.claude/state/digest/doctor-cache.json (consumed by the
#       digest's feed_doctor). A FAILED/unavailable verdict is an anomaly.
#   (b) scheduled-task health capture — `scheduled-task-health.sh`
#       (one "<NL-task>\t<last-result>" line per NL-owned task). Any Last
#       Result outside the doctor predicate's tri-state healthy set
#       {0, 267009, 267011} is an anomaly. Empty output (non-Windows /
#       no tasks) is NOT an anomaly.
#   (c) heartbeat reap — `session-heartbeat.sh reap` (fixes unbounded
#       heartbeat-file growth, ADR-061 §2). A nonzero exit / timeout is
#       an anomaly (the verb's own contract is exit-0-always, so any
#       failure here is real).
#   (d) worktree auto-prune — `worktree-hygiene-sweep.sh --prune` with
#       WORKTREE_SWEEP_APPROVE=1. Closes the "creation is automatic,
#       cleanup is only a Pattern" gap: every isolation:worktree dispatch
#       CREATES a worktree mechanically, but nothing ever removed one.
#       PASSIVE observability — never counted toward this tick's anomaly
#       alert (see the step's own comment for the full safety argument).
#   (e) perf snapshot + orphan reap — the perf-telemetry-2026-07 P2
#       writer, via the shared lib/perf-tick-snapshot.sh. Also PASSIVE:
#       never counted toward the anomaly alert.
#   (f) if any anomaly: write ONE alert JSON into
#       ~/.claude/state/external-monitor-alerts/ in EXACTLY the schema
#       external-monitor-alert-surfacer.sh consumes (schema_version 1,
#       monitor_url/started_at/ended_at/total_routes/healthy_count/
#       anomaly_count/slow_threshold_ms + results[] entries with the
#       label,method,path,expected,status,elapsed_ms,verdict,
#       failure_reason key ORDER its no-jq sed fallback requires).
#       All-green -> no alert file (silent tick).
#
# ============================================================
# ENV OVERRIDES (HARNESS_SELFTEST house convention)
# ============================================================
#
#   HEALTH_TICK_ALERT_DIR       alert output dir (default
#                               $HOME/.claude/state/external-monitor-alerts;
#                               HARNESS_SELFTEST=1 sandboxes under TMPDIR)
#   HEALTH_TICK_BUDGET_SECS     wall-clock budget (default 300)
#   HEALTH_TICK_DOCTOR_CMD      full command line replacing step (a)
#   HEALTH_TICK_TASK_HEALTH_CMD full command line replacing step (b)
#   HEALTH_TICK_REAP_CMD        full command line replacing step (c)
#   HEALTH_TICK_WORKTREE_PRUNE_CMD
#                               full command line replacing step (d).
#                               The self-test MUST set this (scoped to a
#                               fixture repo): the default form takes no
#                               repo argument, so the sweep would
#                               discover and prune the operator's REAL
#                               worktrees under $HOME/claude-projects.
#   HEALTH_TICK_PERF_SNAPSHOT_CMD
#                               full command line replacing step (e)
#   (steps (b)/(c) also inherit SCHTASKS_CMD / HEARTBEAT_STATE_DIR /
#   OBS_* sandboxing from the underlying scripts' own contracts)
#
# Self-test: --self-test (fixture-driven; never runs the real doctor,
# never touches the real alert dir / task scheduler / heartbeat state).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"

# harness-execution-redesign-2026-08 Task 1 (Stage 0a, invariant 11): the
# HALT/drain flag, sourced UNCONDITIONALLY — see
# hooks/lib/single-flight-lib.sh header.
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/single-flight-lib.sh" 2>/dev/null; } || true

# --- portable bounded subprocess (plan macos-portability-2026-07, M3) -----
# nl_run_bounded returns 124 on expiry exactly as GNU `timeout` does, so
# _ht_run_step's existing rc handling (and the "timeout 124" reasoning in
# the comment further down) is unchanged. It does NOT assign to SECONDS,
# which this script uses for its own wall-clock budget.
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "health-tick: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

# ----------------------------------------------------------------------
# Path resolution (mirrors signal-ledger.sh / session-heartbeat-lib.sh
# sandboxing: explicit override wins, then HARNESS_SELFTEST tmp, then real)
# ----------------------------------------------------------------------
_ht_alert_dir() {
  if [[ -n "${HEALTH_TICK_ALERT_DIR:-}" ]]; then
    printf '%s' "$HEALTH_TICK_ALERT_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/health-tick-selftest/%s/alerts' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/external-monitor-alerts' "${HOME:-$PWD}"
}

# _ht_resolve_sweep_root — the worktree-sweep target repo (stdout; empty =
# no sweep, the caller's honest-skip arm). Resolution: HEALTH_TICK_SWEEP_ROOT
# env override wins; else the FIRST entry of the estate-repos config, whose
# path is itself overridable via HEALTH_TICK_REPOS_CONFIG (test seam — same
# ${VAR:-default} shape as ESTATE_JANITOR_REPOS_CONFIG; 2026-08-01 review
# Major: a new external-config read without a path seam is untestable by
# construction); else empty. Parse grammar deliberately matches
# estate-janitor.sh's _ej_resolve_repos for this SHARED file — CR strip,
# inline-#-comment strip, whitespace trim, skip blanks — because two
# consumers with two acceptance grammars diverge at the first CRLF
# (2026-08-01 review Major; on Windows CRLF is the standing hazard).
# FIRST-entry-only is deliberate: health-tick sweeps ONE repo where
# estate-janitor iterates all — stated here AND in the config header,
# because config-line ORDER selects the target of a (when armed) deleting
# operation, and the operator edits the file, not this script.
_ht_resolve_sweep_root() {
  if [[ -n "${HEALTH_TICK_SWEEP_ROOT:-}" ]]; then
    printf '%s' "$HEALTH_TICK_SWEEP_ROOT"
    return 0
  fi
  local cfg="${HEALTH_TICK_REPOS_CONFIG:-$HOME/.claude/config/estate-repos.txt}"
  [[ -f "$cfg" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(printf '%s' "$line" | sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    printf '%s' "$line"
    return 0
  done < "$cfg"
  return 0
}

_ht_now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown; }

_ht_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/ }"
  s="${s//$cr/ }"
  s="${s//$tab/ }"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _ht_run_step <name> <command-line> — run one step under the remaining
# budget with its own timeout. Sets the caller-visible globals:
#   _HT_STEP_RC   exit code (124 on timeout; 125 skipped-over-budget)
#   _HT_STEP_OUT  combined stdout+stderr (truncated to 4000 chars)
#   _HT_STEP_MS   elapsed milliseconds
# Never propagates failure. Steps are full shell command lines (the
# SCHTASKS_CMD convention) run via `bash -c` so overrides compose.
# ----------------------------------------------------------------------
_HT_STEP_RC=0
_HT_STEP_OUT=""
_HT_STEP_MS=0
_ht_run_step() {
  local name="$1" cmdline="$2"
  local budget="${HEALTH_TICK_BUDGET_SECS:-300}"
  local remaining=$(( budget - SECONDS ))
  if [[ "$remaining" -le 0 ]]; then
    _HT_STEP_RC=125
    _HT_STEP_OUT="skipped: wall-clock budget (${budget}s) exhausted before step '${name}' started"
    _HT_STEP_MS=0
    echo "[health-tick] SKIP ${name}: budget exhausted (graceful partial completion)"
    return 0
  fi
  local t0 t1
  t0=$(date +%s%3N 2>/dev/null); [[ "$t0" =~ ^[0-9]+$ ]] || t0=$(( $(date +%s) * 1000 ))
  # Bounded on EVERY platform. The previous `command -v timeout || <run it
  # anyway>` guard ran unbounded on stock macOS, which silently voided this
  # function's entire reason for existing: the remaining-budget arithmetic
  # above is meaningless if the step it guards cannot actually be killed.
  _HT_STEP_OUT="$(nl_run_bounded "${remaining}s" bash -c "$cmdline" 2>&1)"
  _HT_STEP_RC=$?
  t1=$(date +%s%3N 2>/dev/null); [[ "$t1" =~ ^[0-9]+$ ]] || t1=$(( $(date +%s) * 1000 ))
  _HT_STEP_MS=$(( t1 - t0 ))
  [[ "$_HT_STEP_MS" -lt 0 ]] && _HT_STEP_MS=0
  _HT_STEP_OUT="${_HT_STEP_OUT:0:4000}"
  echo "[health-tick] ${name}: rc=${_HT_STEP_RC} elapsed=${_HT_STEP_MS}ms"
  return 0
}

# ----------------------------------------------------------------------
# run_tick — the real tick. Always returns 0.
# ----------------------------------------------------------------------
run_tick() {
  SECONDS=0
  # harness-execution-redesign-2026-08 Task 1 (Stage 0a, invariant 11):
  # HALT/drain — checked first; an operator's one-gesture stop always wins.
  if declare -F sf_halt_active >/dev/null 2>&1 && sf_halt_active; then
    echo "[health-tick] HALT flag set ($(sf_halt_reason 2>/dev/null)) — draining: exiting without running this tick"
    return 0
  fi
  local started_at ended_at
  started_at="$(_ht_now_iso)"

  # results[] entries (surfacer schema; key order matters for its no-jq
  # sed fallback: label,method,path,expected,status,elapsed_ms,verdict,
  # failure_reason). Healthy steps are recorded too (verdict HEALTHY) so
  # the surfacer's healthy/anomaly counts are honest.
  local -a results=()
  local anomalies=0 healthy=0
  _ht_record() {
    # $1 label $2 path $3 expected $4 status $5 elapsed_ms $6 verdict $7 reason
    results+=("$(printf '{"label":"%s","method":"TICK","path":"%s","expected":"%s","status":"%s","elapsed_ms":%d,"verdict":"%s","failure_reason":"%s"}' \
      "$(_ht_json_escape "$1")" "$(_ht_json_escape "$2")" "$(_ht_json_escape "$3")" \
      "$(_ht_json_escape "$4")" "$5" "$(_ht_json_escape "$6")" "$(_ht_json_escape "$7")")")
    if [[ "$6" == "HEALTHY" ]]; then healthy=$((healthy + 1)); else anomalies=$((anomalies + 1)); fi
  }

  # ---- (a) doctor cache refresh (the one sanctioned real-doctor path) ----
  local doctor_cmd="${HEALTH_TICK_DOCTOR_CMD:-bash \"$HOOKS_DIR/session-start-digest.sh\" --refresh-doctor-cache \"\$HOME\"}"
  _ht_run_step "doctor-cache-refresh" "$doctor_cmd"
  local doctor_verdict_line
  doctor_verdict_line="$(printf '%s\n' "$_HT_STEP_OUT" | grep -E '^\[doctor\]' | tail -n1)"
  if [[ "$_HT_STEP_RC" -eq 125 ]]; then
    : # skipped over budget — not an anomaly, not healthy; simply unobserved
  elif [[ "$_HT_STEP_RC" -eq 0 ]] && printf '%s' "$doctor_verdict_line" | grep -q 'GREEN'; then
    _ht_record "harness-doctor" "doctor-cache-refresh" "GREEN" "rc=0" "$_HT_STEP_MS" "HEALTHY" ""
  else
    [[ -z "$doctor_verdict_line" ]] && doctor_verdict_line="no [doctor] verdict line in output (rc=${_HT_STEP_RC})"
    _ht_record "harness-doctor" "doctor-cache-refresh" "GREEN" "rc=${_HT_STEP_RC}" "$_HT_STEP_MS" "DOCTOR_RED" "$doctor_verdict_line"
  fi

  # ---- (b) scheduled-task health capture --------------------------------
  local task_cmd="${HEALTH_TICK_TASK_HEALTH_CMD:-bash \"$SCRIPT_DIR/scheduled-task-health.sh\"}"
  _ht_run_step "scheduled-task-health" "$task_cmd"
  if [[ "$_HT_STEP_RC" -eq 125 ]]; then
    :
  elif [[ "$_HT_STEP_RC" -ne 0 ]]; then
    _ht_record "scheduled-tasks" "scheduled-task-health" "rc=0" "rc=${_HT_STEP_RC}" "$_HT_STEP_MS" "TASK_QUERY_FAILED" "${_HT_STEP_OUT:0:200}"
  else
    # tri-state healthy Last Result set {0, 267009, 267011} — the doctor
    # predicate's own rule (specs-o §O.6). Empty output = nothing to judge.
    local bad_lines
    bad_lines="$(printf '%s\n' "$_HT_STEP_OUT" | awk -F'\t' 'NF>=2 && $2!="0" && $2!="267009" && $2!="267011" {printf "%s=%s; ", $1, $2}')"
    if [[ -n "$bad_lines" ]]; then
      _ht_record "scheduled-tasks" "scheduled-task-health" "last-result in {0,267009,267011}" "bad" "$_HT_STEP_MS" "TASK_LAST_RESULT_BAD" "$bad_lines"
    else
      _ht_record "scheduled-tasks" "scheduled-task-health" "last-result in {0,267009,267011}" "ok" "$_HT_STEP_MS" "HEALTHY" ""
    fi
  fi

  # ---- (c) heartbeat reap (bounds heartbeat-file growth) -----------------
  local reap_cmd="${HEALTH_TICK_REAP_CMD:-bash \"$SCRIPT_DIR/session-heartbeat.sh\" reap}"
  _ht_run_step "heartbeat-reap" "$reap_cmd"
  if [[ "$_HT_STEP_RC" -eq 125 ]]; then
    :
  elif [[ "$_HT_STEP_RC" -eq 0 ]]; then
    _ht_record "heartbeat-reap" "session-heartbeat-reap" "rc=0" "rc=0" "$_HT_STEP_MS" "HEALTHY" ""
  else
    # reap's own contract is exit-0-always, so any nonzero here (incl.
    # timeout 124) is a real failure worth surfacing.
    _ht_record "heartbeat-reap" "session-heartbeat-reap" "rc=0" "rc=${_HT_STEP_RC}" "$_HT_STEP_MS" "REAP_ERROR" "${_HT_STEP_OUT:0:200}"
  fi

  # ---- (d) worktree auto-prune -----------------------------------------
  # THE GAP THIS CLOSES: worktree CREATION is a Mechanism — every
  # `isolation: "worktree"` dispatch makes one, automatically, with no
  # human in the loop. Worktree REMOVAL was only ever a Pattern: a human
  # remembering to run the sweep. worktree-hygiene-sweep.sh's SAFE-PRUNE
  # path has been fully built and fully self-tested for weeks, but
  # NOTHING on this machine ever set WORKTREE_SWEEP_APPROVE=1, so
  # `--prune` had never once fired in production. Built, tested, and
  # completely unreached is the harness's cardinal defect (constitution
  # §10: wire it or delete the claim). This step is the wiring.
  #
  # SAFETY — this step decides NOTHING. Every "may I delete this"
  # judgment is delegated to the sweep's own SAFE-PRUNE predicate:
  # 0 unique patches vs the resolved base AND 0 dirty files AND last
  # commit older than WORKTREE_SWEEP_AGE_DAYS (default 7). Removal is
  # `git worktree remove` WITHOUT --force and `git branch -d` NOT -D, so
  # git itself refuses unmerged work as a second, independent guard this
  # script does not control. HOLDS-CONTENT / LIVE-OWNED / ORPHANED
  # worktrees are never touched by --prune at all — a locked worktree
  # (the shape a live or crashed dispatched agent leaves) is excluded
  # from SAFE-PRUNE by construction. Every removal is appended to
  # $WORKTREE_SWEEP_LOG (~/.claude/state/worktree-sweep.log).
  #
  # ON SETTING THE APPROVAL FLAG HERE: the operator's standing order
  # (sweep header, 2026-06-09) is that nothing is deleted without
  # explicit approval, and WORKTREE_SWEEP_APPROVE=1 IS that approval
  # channel. Arming it on this tick is approval for the SAFE-PRUNE CLASS
  # specifically — a class whose definition is "provably carries nothing"
  # — and is NOT a blanket licence to remove worktrees. The flag stays
  # required (and unset) for every other caller, so an interactive
  # `--prune` still refuses with exit 3 exactly as before.
  #
  # PASSIVE: like (e) below, never recorded via _ht_record, so a prune
  # hiccup can never trigger this tick's own anomaly alert. Housekeeping
  # that cries wolf about itself is worse than housekeeping that quietly
  # skips a cycle; the sweep's own log is the durable record. ----------
  # ARMING (harness-review bab00ab, Critical 1 — PROVEN): an agent commit
  # must NOT hard-code the operator's deletion-approval flag into an
  # unattended task. Three written records set the opposite convention:
  # manifest.json's perf-tick-snapshot entry ("an agent session cannot arm
  # it merely by running code"; worktree purges "operator-only"), ADR-061
  # §5 invariant 2 ("this ADR ships nothing armed"), and NEEDS-YOU.md's
  # log of per-batch operator asks including one the permission classifier
  # DENIED. So this step ships OBSERVE-FIRST, exactly like the
  # PERF_TICK_REAP_ARMED precedent on this same tick: report mode by
  # default, and it prunes ONLY when the operator has created the arming
  # marker themselves. Code an agent writes can never flip this.
  local whs="$SCRIPT_DIR/worktree-hygiene-sweep.sh"
  local arm_marker="${WORKTREE_PRUNE_ARM_MARKER:-$HOME/.claude/state/worktree-prune-armed}"
  if [[ -f "$whs" ]]; then
    # HARNESS_SELFTEST tri-state (review Minor F7): the default below
    # touches REAL state, so it must honor the same sandboxing contract
    # _ht_alert_dir implements — an explicit override wins, otherwise a
    # self-test never reaches the real sweep at all.
    local wt_cmd
    # Sweep-root resolution lives in _ht_resolve_sweep_root (top of file):
    # env override -> FIRST config entry (janitor-grammar parse, seam via
    # HEALTH_TICK_REPOS_CONFIG) -> empty = the honest-skip arm below. Was
    # hardcoded to the RETIRED legacy repo path until 2026-08-01 (doctor
    # legacy-paths RED) -- a silent no-op since the repo moved.
    local sweep_root; sweep_root="$(_ht_resolve_sweep_root)"
    if [[ -n "${HEALTH_TICK_WORKTREE_PRUNE_CMD:-}" ]]; then
      wt_cmd="$HEALTH_TICK_WORKTREE_PRUNE_CMD"
    elif [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
      wt_cmd="echo 'sandboxed: worktree prune skipped under HARNESS_SELFTEST'"
    elif [[ -z "$sweep_root" || ! -d "$sweep_root" ]]; then
      wt_cmd=""
      echo "[health-tick] worktree prune skipped: no sweep root (set ~/.claude/config/estate-repos.txt or HEALTH_TICK_SWEEP_ROOT)"
    elif [[ -f "$arm_marker" ]]; then
      wt_cmd="WORKTREE_SWEEP_APPROVE=1 bash \"$whs\" --prune \"$sweep_root\""
    else
      # Observe-first default: classify and report, delete NOTHING.
      wt_cmd="bash \"$whs\" \"$sweep_root\""
    fi
    # Run the step ONLY when an arm composed a command — the honest-skip
    # arm prints its own line and runs nothing (routing an echo through
    # _ht_run_step would make the rc=0 handler report "0 worktree(s)
    # pruned", a sweep-ran claim for a sweep that never ran).
    if [[ -n "$wt_cmd" ]]; then
      _ht_run_step "worktree-prune" "$wt_cmd"
      if [[ "$_HT_STEP_RC" -eq 0 ]]; then
        local pruned_n
        pruned_n="$(printf '%s\n' "$_HT_STEP_OUT" | grep -c 'PRUNED worktree' || true)"
        [[ -n "$pruned_n" ]] || pruned_n=0
        echo "[health-tick] worktree prune: ${pruned_n} worktree(s) pruned (SAFE-PRUNE class only; see $HOME/.claude/state/worktree-sweep.log)"
      elif [[ "$_HT_STEP_RC" -ne 125 ]]; then
        echo "[health-tick] WARN: worktree prune step failed (rc=${_HT_STEP_RC}, non-fatal, no alert): ${_HT_STEP_OUT:0:200}" >&2
      fi
    fi
  else
    echo "[health-tick] WARN: worktree-hygiene-sweep.sh not found at ${whs} — worktree prune skipped this fire (graceful, no crash)" >&2
  fi

  # ---- (e) P2 perf snapshot + orphan reap (perf-telemetry-2026-07 plan,
  # fallback tick — supervisor-tick.sh is the plan's declared PRIMARY home
  # but is OPERATOR-ARMED and may be inert on a given machine; this hourly
  # tick is already armed everywhere, so P3 gets data regardless). Shares
  # the SAME lib as supervisor-tick.sh (never a second implementation of
  # "collect a snapshot / decide an orphan"). Passive observability, not a
  # health check: never recorded via _ht_record, so a perf-snapshot hiccup
  # never triggers this tick's own anomaly alert — P3 (future task) is the
  # thing that turns ledger data into a RED, not this writer step. -------
  local pts_lib="$HOOKS_DIR/lib/perf-tick-snapshot.sh"
  if [[ -f "$pts_lib" ]]; then
    local pts_cmd="${HEALTH_TICK_PERF_SNAPSHOT_CMD:-bash -c \"source '$pts_lib' && pts_run_tick\"}"
    _ht_run_step "perf-snapshot" "$pts_cmd"
    if [[ "$_HT_STEP_RC" -eq 0 ]]; then
      echo "[health-tick] perf snapshot written: ${_HT_STEP_OUT:-<empty>}"
    elif [[ "$_HT_STEP_RC" -ne 125 ]]; then
      echo "[health-tick] WARN: perf snapshot step failed (rc=${_HT_STEP_RC}, non-fatal, no alert): ${_HT_STEP_OUT:0:200}" >&2
    fi
  else
    echo "[health-tick] WARN: perf-tick-snapshot.sh lib not found at ${pts_lib} — perf snapshot skipped this fire (graceful, no crash)" >&2
  fi

  ended_at="$(_ht_now_iso)"
  local total=$(( healthy + anomalies ))

  # ---- (f) one alert file iff any anomaly --------------------------------
  if [[ "$anomalies" -gt 0 ]]; then
    local alert_dir alert_file ts_name
    alert_dir="$(_ht_alert_dir)"
    mkdir -p "$alert_dir" 2>/dev/null || true
    ts_name="$(date -u '+%Y-%m-%dT%H-%M-%SZ' 2>/dev/null || echo "unknown-$$")"
    alert_file="$alert_dir/${ts_name}-health-tick.json"
    local results_json="" r first=1
    for r in "${results[@]}"; do
      if [[ "$first" == "1" ]]; then first=0; else results_json+=","; fi
      results_json+="$r"
    done
    local budget="${HEALTH_TICK_BUDGET_SECS:-300}"
    local tmp_alert
    tmp_alert="$(mktemp "${alert_file}.XXXXXX" 2>/dev/null || printf '%s.tmp' "$alert_file")"
    printf '{"schema_version":1,"monitor_url":"nl-health-tick (local harness watchdog, ADR-061 D6)","started_at":"%s","ended_at":"%s","total_routes":%d,"healthy_count":%d,"anomaly_count":%d,"slow_threshold_ms":%d,"results":[%s]}\n' \
      "$started_at" "$ended_at" "$total" "$healthy" "$anomalies" "$(( budget * 1000 ))" "$results_json" \
      > "$tmp_alert" 2>/dev/null && mv "$tmp_alert" "$alert_file" 2>/dev/null || rm -f "$tmp_alert" 2>/dev/null
    if [[ -f "$alert_file" ]]; then
      echo "[health-tick] ${anomalies} anomaly(ies) -> alert written: $alert_file (surfaced at next SessionStart by external-monitor-alert-surfacer.sh)"
    else
      echo "[health-tick] ${anomalies} anomaly(ies) but alert write FAILED (dir: $alert_dir) — tick still exits 0 (writer never blocks)" >&2
    fi
  else
    echo "[health-tick] all green (${healthy}/${total} checks healthy) — no alert written"
  fi

  echo "[health-tick] done in ${SECONDS}s (budget ${HEALTH_TICK_BUDGET_SECS:-300}s)"
  return 0
}

# ============================================================
# --self-test (fixture-driven; sandboxed; never touches real state)
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t htst)
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi
  export HARNESS_SELFTEST=1

  # SUITE-WIDE SAFETY INTERLOCK for step (d). The DEFAULT prune command
  # takes no repo argument, so the sweep would fall through to
  # discover_repos() and prune the OPERATOR'S REAL worktrees under
  # $HOME/claude-projects — on every self-test run, including the ones
  # the doctor and install.sh invoke. Every scenario therefore inherits a
  # no-op here; ONLY the dedicated prune scenario below overrides it, and
  # only with a command scoped to its own throwaway fixture repo. Removing
  # this line makes the suite destructive against real state.
  export HEALTH_TICK_WORKTREE_PRUNE_CMD="true"

  local SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
  local SURFACER="$HOOKS_DIR/external-monitor-alert-surfacer.sh"

  # Healthy fixture stand-ins for the three steps (fast, deterministic).
  local GREEN_DOCTOR="printf '%s\n' '[doctor] GREEN — 7 checks passed'"
  local RED_DOCTOR="printf '%s\n' '[doctor] FAILED — 2 red, 1 warn, 7 checks run'; exit 1"
  local HEALTHY_TASKS="printf 'NL-workstreams-heartbeat\t0\nNL-session-resumer\t267011\n'"
  local BAD_TASKS="printf 'NL-workstreams-heartbeat\t-2147024894\nNL-session-resumer\t0\n'"
  local OK_REAP="printf '0 heartbeat(s) reaped (oracle: session-heartbeat reap, threshold 1440min)\n'"

  echo "Scenario 1: all-green -> NO alert file written, exit 0"
  local d1="$TMP/s1-alerts"
  mkdir -p "$d1"
  local rc1
  HEALTH_TICK_ALERT_DIR="$d1" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" >/dev/null 2>&1
  rc1=$?
  if [[ "$rc1" -eq 0 ]]; then pass "all-green tick exits 0"; else fail "all-green tick exited $rc1"; fi
  if [[ -z "$(ls -A "$d1" 2>/dev/null)" ]]; then
    pass "all-green tick writes no alert file"
  else
    fail "all-green tick wrote an alert file: $(ls "$d1")"
  fi

  echo "Scenario 2: doctor RED -> ONE alert file, in the surfacer's exact format"
  local d2="$TMP/s2-alerts"
  mkdir -p "$d2"
  HEALTH_TICK_ALERT_DIR="$d2" HEALTH_TICK_DOCTOR_CMD="$RED_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" >/dev/null 2>&1
  local n2
  n2="$(ls "$d2"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$n2" == "1" ]]; then
    pass "doctor RED -> exactly one alert file"
  else
    fail "expected exactly 1 alert file, got $n2"
  fi
  local f2
  f2="$(ls "$d2"/*.json 2>/dev/null | head -1)"
  if command -v jq >/dev/null 2>&1 && [[ -n "$f2" ]]; then
    if jq -e '.schema_version == 1 and .anomaly_count == 1 and .healthy_count == 2 and (.results | length) == 3' "$f2" >/dev/null 2>&1; then
      pass "alert JSON carries schema_version/anomaly_count/healthy_count/results per the surfacer contract"
    else
      fail "alert JSON shape mismatch: $(cat "$f2")"
    fi
    if jq -e '.results[] | select(.verdict=="DOCTOR_RED") | .failure_reason | contains("FAILED")' "$f2" >/dev/null 2>&1; then
      pass "DOCTOR_RED result carries the doctor verdict line as failure_reason"
    else
      fail "expected a DOCTOR_RED result with the verdict line: $(cat "$f2")"
    fi
  fi
  # THE ORACLE: the real, unmodified surfacer must surface this alert.
  if [[ -f "$SURFACER" ]]; then
    local surf2
    surf2="$(bash "$SURFACER" "$d2" </dev/null 2>/dev/null)"
    if printf '%s' "$surf2" | grep -q "1 unacked alert" \
       && printf '%s' "$surf2" | grep -q "DOCTOR_RED"; then
      pass "REAL external-monitor-alert-surfacer.sh surfaces the alert (verdict visible) — pre-existing oracle"
    else
      fail "real surfacer did not surface the alert; surfacer output: [$surf2]"
    fi
  else
    fail "surfacer not found at $SURFACER (cannot run the format oracle)"
  fi

  echo "Scenario 3: bad scheduled-task Last Result -> alert names the task"
  local d3="$TMP/s3-alerts"
  mkdir -p "$d3"
  HEALTH_TICK_ALERT_DIR="$d3" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$BAD_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" >/dev/null 2>&1
  local f3
  f3="$(ls "$d3"/*.json 2>/dev/null | head -1)"
  if [[ -n "$f3" ]] && grep -q 'TASK_LAST_RESULT_BAD' "$f3" 2>/dev/null \
     && grep -q 'NL-workstreams-heartbeat=-2147024894' "$f3" 2>/dev/null; then
    pass "bad Last Result -> TASK_LAST_RESULT_BAD anomaly naming task + raw code"
  else
    fail "expected TASK_LAST_RESULT_BAD with task name; got: $(cat "$f3" 2>/dev/null)"
  fi
  if [[ -n "$f3" ]] && grep -q 'NL-session-resumer=' "$f3" 2>/dev/null; then
    fail "healthy task (Last Result 0) incorrectly flagged"
  else
    pass "healthy task (Last Result 0) and tri-state codes not flagged"
  fi

  echo "Scenario 4: budget respected — a hung step is cut off, tick exits 0, remaining steps skipped gracefully"
  local d4="$TMP/s4-alerts"
  mkdir -p "$d4"
  local t4_start t4_end t4_out rc4
  t4_start=$(date +%s)
  t4_out="$(HEALTH_TICK_ALERT_DIR="$d4" HEALTH_TICK_BUDGET_SECS=2 \
    HEALTH_TICK_DOCTOR_CMD="sleep 30" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" 2>&1)"
  rc4=$?
  t4_end=$(date +%s)
  local t4_elapsed=$(( t4_end - t4_start ))
  if [[ "$rc4" -eq 0 ]]; then pass "budget-tripped tick still exits 0"; else fail "budget-tripped tick exited $rc4"; fi
  if [[ "$t4_elapsed" -lt 15 ]]; then
    pass "2s budget cut the 30s hang off (wall clock ${t4_elapsed}s < 15s)"
  else
    fail "budget not respected: tick took ${t4_elapsed}s against a 2s budget"
  fi
  if printf '%s' "$t4_out" | grep -q 'graceful partial completion\|budget exhausted'; then
    pass "over-budget remaining steps logged as skipped (graceful partial completion)"
  else
    fail "expected a budget-exhausted skip log line; got: [$t4_out]"
  fi

  echo "Scenario 5: NL_HOOK_REENTRY is NOT set in the tick's child environment (ADR-061 D6 critical wiring)"
  local d5="$TMP/s5-alerts" probe5="$TMP/s5-env-probe" probe5b="$TMP/s5-env-probe-b"
  mkdir -p "$d5"
  HEALTH_TICK_ALERT_DIR="$d5" \
    HEALTH_TICK_DOCTOR_CMD="printf '%s' \"\${NL_HOOK_REENTRY:-unset}\" > '$probe5'; printf '[doctor] GREEN\n'" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" \
    HEALTH_TICK_REAP_CMD="printf '%s' \"\${NL_HOOK_REENTRY:-unset}\" > '$probe5b'; $OK_REAP" \
    bash "$SELF" >/dev/null 2>&1
  if [[ "$(cat "$probe5" 2>/dev/null)" == "unset" ]]; then
    pass "doctor child step sees NL_HOOK_REENTRY unset (the doctor would NOT self-suppress)"
  else
    fail "doctor child step saw NL_HOOK_REENTRY='$(cat "$probe5" 2>/dev/null)' (expected unset)"
  fi
  if [[ "$(cat "$probe5b" 2>/dev/null)" == "unset" ]]; then
    pass "reap child step sees NL_HOOK_REENTRY unset too (no step gains the marker)"
  else
    fail "reap child step saw NL_HOOK_REENTRY='$(cat "$probe5b" 2>/dev/null)' (expected unset)"
  fi

  echo "Scenario 6: a failing step never propagates — reap crash -> REAP_ERROR anomaly, tick exit 0"
  local d6="$TMP/s6-alerts"
  mkdir -p "$d6"
  local rc6
  HEALTH_TICK_ALERT_DIR="$d6" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="echo boom >&2; exit 3" \
    bash "$SELF" >/dev/null 2>&1
  rc6=$?
  local f6
  f6="$(ls "$d6"/*.json 2>/dev/null | head -1)"
  if [[ "$rc6" -eq 0 ]] && [[ -n "$f6" ]] && grep -q 'REAP_ERROR' "$f6" 2>/dev/null; then
    pass "reap failure -> REAP_ERROR anomaly recorded, tick exit 0"
  else
    fail "expected exit 0 + REAP_ERROR alert (rc=$rc6, file: $(cat "$f6" 2>/dev/null))"
  fi

  echo "Scenario 7: P2 perf snapshot fallback (perf-telemetry-2026-07 plan) — this tick writes a real ticks.jsonl line via the shared lib, and a perf-snapshot failure never triggers this tick's own anomaly alert"
  local pts_lib="$HOOKS_DIR/lib/perf-tick-snapshot.sh"
  if [[ -f "$pts_lib" ]]; then
    local d7="$TMP/s7-alerts" perf7="$TMP/s7-perf"
    mkdir -p "$d7"
    # Export the PERF_TICK_* overrides so the DEFAULT
    # HEALTH_TICK_PERF_SNAPSHOT_CMD (which sources pts_lib and calls
    # pts_run_tick) inherits them naturally through the process tree —
    # avoids nested-quoting a nested `bash -c` command-line string.
    HEALTH_TICK_ALERT_DIR="$d7" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
      HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
      PERF_TICK_LEDGER_DIR="$perf7" \
      PERF_TICK_PROCESS_LIST_CMD="printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\nOFFICE_PC,20260101000000.000000-420,bash.exe,1,111\nOFFICE_PC,20260101000000.000000-420,claude.exe,1,222\n'" \
      PERF_TICK_DEFENDER_CMD="true" \
      PERF_TICK_WORKTREE_COUNT_OVERRIDE=4 \
      bash "$SELF" >/dev/null 2>&1
    local pts_file="$perf7/ticks.jsonl"
    if [[ -f "$pts_file" ]] && grep -qE '"bash_count":1,"claude_count":1,"worktree_count":4' "$pts_file"; then
      pass "health-tick's own run wrote a fixture-driven ticks.jsonl line via the shared perf-tick-snapshot.sh lib"
    else
      fail "expected a ticks.jsonl line with bash_count=1/claude_count=1/worktree_count=4 at $pts_file: $(cat "$pts_file" 2>/dev/null)"
    fi
    if [[ -z "$(ls -A "$d7" 2>/dev/null)" ]]; then
      pass "perf snapshot step is passive observability — never counted toward this tick's own anomaly alert"
    else
      fail "perf snapshot step unexpectedly triggered an anomaly alert: $(ls "$d7")"
    fi
  else
    fail "perf-tick-snapshot.sh lib not found at $pts_lib"
  fi

  echo "Scenario 8: worktree auto-prune (step d) — ONE tick removes a SAFE-PRUNE fixture worktree (0 unique patches, clean, >7d old) and its branch, while leaving a dirty worktree and an unintegrated-patch worktree untouched; the prune step never triggers this tick's own anomaly alert"
  local whs="$SCRIPT_DIR/worktree-hygiene-sweep.sh"
  if [[ -f "$whs" ]]; then
    local d8="$TMP/s8-alerts" r8="$TMP/s8-repo" past8
    mkdir -p "$d8"
    past8=$(( $(date +%s) - 30 * 86400 ))

    # Fixture repo: one commit dated 30d ago, so every branch cut from it
    # is older than the 7d WORKTREE_SWEEP_AGE_DAYS default.
    git init -q "$r8" 2>/dev/null
    git -C "$r8" config user.email test@example.com
    git -C "$r8" config user.name "Self Test"
    git -C "$r8" symbolic-ref HEAD refs/heads/master
    echo base > "$r8/f.txt"
    git -C "$r8" add f.txt
    GIT_AUTHOR_DATE="@$past8 +0000" GIT_COMMITTER_DATE="@$past8 +0000" \
      git -C "$r8" -c commit.gpgsign=false commit -qm "init (30d ago)"

    # wt-safe:   at master tip, clean, 30d old            -> SAFE-PRUNE
    # wt-dirty:  at master tip, 30d old, one untracked    -> HOLDS-CONTENT
    # wt-unique: clean + old but carries a unique patch   -> HOLDS-CONTENT
    git -C "$r8" worktree add -q "$TMP/s8-wt-safe" -b s8-safe >/dev/null 2>&1
    git -C "$r8" worktree add -q "$TMP/s8-wt-dirty" -b s8-dirty >/dev/null 2>&1
    echo scratch > "$TMP/s8-wt-dirty/untracked.txt"
    git -C "$r8" worktree add -q "$TMP/s8-wt-unique" -b s8-unique >/dev/null 2>&1
    echo unique > "$TMP/s8-wt-unique/u.txt"
    git -C "$TMP/s8-wt-unique" add u.txt
    GIT_AUTHOR_DATE="@$past8 +0000" GIT_COMMITTER_DATE="@$past8 +0000" \
      git -C "$TMP/s8-wt-unique" -c commit.gpgsign=false commit -qm "unique patch (30d ago)"

    # Precondition: prove the fixture exists BEFORE the tick, so a PASS
    # below can never be vacuous (a never-created dir is also "gone").
    if [[ -d "$TMP/s8-wt-safe" ]]; then
      pass "(pre) SAFE-PRUNE fixture worktree exists before the tick"
    else
      fail "(pre) fixture worktree was never created — scenario 8 cannot prove anything"
    fi

    local rc8
    HEALTH_TICK_ALERT_DIR="$d8" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
      HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
      HEALTH_TICK_WORKTREE_PRUNE_CMD="WORKTREE_SWEEP_APPROVE=1 WORKTREE_SWEEP_LOG='$TMP/s8-sweep.log' OBS_TRANSCRIPTS_ROOT='$TMP/s8-tx' bash '$whs' --prune '$r8'" \
      bash "$SELF" >/dev/null 2>&1
    rc8=$?

    if [[ "$rc8" -eq 0 ]]; then pass "tick with the prune step exits 0"; else fail "tick with the prune step exited $rc8"; fi

    # THE ASSERTION the operator asked for: one tick, worktree gone.
    if [[ ! -d "$TMP/s8-wt-safe" ]]; then
      pass "ONE tick pruned the SAFE-PRUNE worktree (step (d) actually fires — WORKTREE_SWEEP_APPROVE is really set)"
    else
      fail "SAFE-PRUNE worktree survived the tick — step (d) did not fire"
    fi
    if ! git -C "$r8" rev-parse --verify --quiet refs/heads/s8-safe >/dev/null 2>&1; then
      pass "its branch was deleted too (via git branch -d, not -D)"
    else
      fail "worktree removed but branch s8-safe survived"
    fi
    if [[ -d "$TMP/s8-wt-dirty" ]] && [[ -d "$TMP/s8-wt-unique" ]]; then
      pass "HOLDS-CONTENT worktrees untouched (dirty + unique-patch both remain)"
    else
      fail "prune removed a HOLDS-CONTENT worktree — SAFE-PRUNE predicate breached"
    fi
    if [[ -d "$r8/.git" ]] && [[ -f "$r8/f.txt" ]]; then
      pass "primary worktree never touched"
    else
      fail "primary worktree damaged by the prune step"
    fi
    if grep -q 'removed worktree=.*s8-wt-safe' "$TMP/s8-sweep.log" 2>/dev/null; then
      pass "removal appended to the sweep log (durable record of what the tick deleted)"
    else
      fail "no sweep-log line for the removal: $(cat "$TMP/s8-sweep.log" 2>/dev/null)"
    fi
    # Passive-observability contract, same as scenario 7's perf step.
    if [[ -z "$(ls -A "$d8" 2>/dev/null)" ]]; then
      pass "prune step is passive — an all-green tick that pruned still writes NO anomaly alert"
    else
      fail "prune step triggered an anomaly alert: $(ls "$d8")"
    fi

    echo "Scenario 8b: a FAILING prune step never propagates and never alerts"
    local d8b="$TMP/s8b-alerts" rc8b
    mkdir -p "$d8b"
    HEALTH_TICK_ALERT_DIR="$d8b" HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" \
      HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
      HEALTH_TICK_WORKTREE_PRUNE_CMD="echo boom >&2; exit 4" \
      bash "$SELF" >/dev/null 2>&1
    rc8b=$?
    if [[ "$rc8b" -eq 0 ]] && [[ -z "$(ls -A "$d8b" 2>/dev/null)" ]]; then
      pass "prune failure -> tick still exits 0 and writes no alert (housekeeping never cries wolf)"
    else
      fail "prune failure leaked: rc=$rc8b, alerts=$(ls "$d8b" 2>/dev/null)"
    fi
  else
    fail "worktree-hygiene-sweep.sh not found at $whs (cannot test step (d))"
  fi

  echo "Scenario 9: sweep-root resolution (2026-08-01 review) — env override wins; config first-entry parses janitor-grammar; missing config -> honest skip"
  local d9="$TMP/s9-cfg"; mkdir -p "$d9"
  # (a) env override wins even when a config exists
  printf '/cfg/repo-one\n' > "$d9/repos.txt"
  local r9a; r9a="$(HEALTH_TICK_SWEEP_ROOT="/env/wins" HEALTH_TICK_REPOS_CONFIG="$d9/repos.txt" _ht_resolve_sweep_root)"
  [[ "$r9a" == "/env/wins" ]] && pass "env override wins over an existing config" || fail "env override lost: got '$r9a'"
  # (b) FIRST entry under the janitor grammar: CRLF endings, full-line and
  # inline #-comments, surrounding whitespace — the exact shapes the
  # 2026-08-01 review proved the first draft mis-parsed into a misleading
  # "config not set" skip.
  printf '# header comment\r\n\r\n   /cfg/first-repo   # inline note\r\n/cfg/second-repo\r\n' > "$d9/crlf.txt"
  local r9b; r9b="$(HEALTH_TICK_SWEEP_ROOT= HEALTH_TICK_REPOS_CONFIG="$d9/crlf.txt" _ht_resolve_sweep_root)"
  [[ "$r9b" == "/cfg/first-repo" ]] && pass "CRLF+comment+whitespace config parses to the FIRST clean entry" || fail "janitor-grammar parse broken: got '$r9b'"
  # (c) missing config -> empty -> never a guessed path
  local r9c; r9c="$(HEALTH_TICK_SWEEP_ROOT= HEALTH_TICK_REPOS_CONFIG="$d9/absent.txt" _ht_resolve_sweep_root)"
  [[ -z "$r9c" ]] && pass "missing config resolves to empty (no guessed path)" || fail "missing config guessed a path: '$r9c'"
  # (c2) branch COMPOSITION, reachable past the suite-wide interlock: one
  # composed tick with the *_CMD prune override cleared and HARNESS_SELFTEST
  # off, every other step stubbed green and the alert dir sandboxed — the
  # skip arm's exact message must surface in the tick's own output. This is
  # the scenario the 2026-08-01 review demanded: without it, the suite's
  # totals are invariant under reverting the whole sweep-root delta.
  local out9
  out9="$(HEALTH_TICK_WORKTREE_PRUNE_CMD= HARNESS_SELFTEST=0 HEALTH_TICK_ALERT_DIR="$d9/alerts" \
      HEALTH_TICK_SWEEP_ROOT= HEALTH_TICK_REPOS_CONFIG="$d9/absent.txt" \
      HEALTH_TICK_DOCTOR_CMD="$GREEN_DOCTOR" HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" \
      HEALTH_TICK_REAP_CMD="$OK_REAP" HEALTH_TICK_PERF_SNAPSHOT_CMD="true" \
      bash "$SELF" 2>&1)"
  case "$out9" in *"worktree prune skipped: no sweep root"*) pass "composed tick takes the honest-skip arm with its exact message" ;; \
    *) fail "composed tick did not surface the skip-arm message" ;; esac

  echo "Scenario 10 (harness-execution-redesign-2026-08 Task 1, invariant 11): HALT/drain -- set the flag, confirm the next tick exits immediately with a drain notice and writes no alert; clear it, confirm normal resumption"
  local d10="$TMP/s10-alerts" sf10="$TMP/s10-sf"; mkdir -p "$d10" "$sf10"
  printf '%s %s\n' "$(date +%s 2>/dev/null || echo 0)" "s10-test-halt" > "$sf10/HALT"
  local out10a
  out10a="$(SF_STATE_DIR="$sf10" HEALTH_TICK_ALERT_DIR="$d10" HEALTH_TICK_DOCTOR_CMD="$RED_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" 2>&1)"
  case "$out10a" in *"HALT"*) pass "Scenario 10a: HALT flag set -> tick drains with a notice naming HALT" ;; \
    *) fail "Scenario 10a: expected a HALT notice, got: $out10a" ;; esac
  [[ -z "$(ls "$d10" 2>/dev/null)" ]] && pass "Scenario 10b: HALT drain wrote NO alert even though the stubbed doctor was RED (never ran the tick body)" \
    || fail "Scenario 10b: an alert was written despite HALT being set"
  rm -f "$sf10/HALT"
  local out10c
  out10c="$(SF_STATE_DIR="$sf10" HEALTH_TICK_ALERT_DIR="$d10" HEALTH_TICK_DOCTOR_CMD="$RED_DOCTOR" \
    HEALTH_TICK_TASK_HEALTH_CMD="$HEALTHY_TASKS" HEALTH_TICK_REAP_CMD="$OK_REAP" \
    bash "$SELF" 2>&1)"
  [[ -n "$(ls "$d10" 2>/dev/null)" ]] && pass "Scenario 10c: HALT cleared -> next tick runs normally (RED doctor now produces an alert)" \
    || fail "Scenario 10c: expected an alert after HALT was cleared, got none"

  rm -rf "$TMP" 2>/dev/null || true
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
    cat <<'USAGE'
health-tick.sh — passive hourly harness health tick (ADR-061 D6).

  health-tick.sh              Run one tick: doctor-cache refresh,
                              scheduled-task health capture, heartbeat
                              reap; write ONE alert JSON into the
                              external-monitor-alerts dir iff any
                              RED/anomaly (surfaced at next SessionStart
                              by external-monitor-alert-surfacer.sh).
                              NEVER spawns claude; NEVER sets
                              NL_HOOK_REENTRY; exit 0 always; bounded by
                              HEALTH_TICK_BUDGET_SECS (default 300s).
  health-tick.sh --self-test  Run the sandboxed fixture suite.

Registered as the NL-health-tick hourly scheduled task via install.sh
(register_health_tick_task — Phase-1 ops step, orchestrator-enabled).
USAGE
    exit 0
    ;;
  "")
    run_tick
    exit 0
    ;;
  *)
    echo "health-tick.sh: unknown argument '$1' (run with -h for usage; never blocks)" >&2
    exit 0
    ;;
esac
