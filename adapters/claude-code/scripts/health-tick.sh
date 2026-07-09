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
#   (d) if any anomaly: write ONE alert JSON into
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
#   (steps (b)/(c) also inherit SCHTASKS_CMD / HEARTBEAT_STATE_DIR /
#   OBS_* sandboxing from the underlying scripts' own contracts)
#
# Self-test: --self-test (fixture-driven; never runs the real doctor,
# never touches the real alert dir / task scheduler / heartbeat state).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"

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
  if command -v timeout >/dev/null 2>&1; then
    _HT_STEP_OUT="$(timeout "${remaining}s" bash -c "$cmdline" 2>&1)"
    _HT_STEP_RC=$?
  else
    _HT_STEP_OUT="$(bash -c "$cmdline" 2>&1)"
    _HT_STEP_RC=$?
  fi
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

  ended_at="$(_ht_now_iso)"
  local total=$(( healthy + anomalies ))

  # ---- (d) one alert file iff any anomaly --------------------------------
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
