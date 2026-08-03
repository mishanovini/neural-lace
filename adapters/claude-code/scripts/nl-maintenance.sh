#!/usr/bin/env bash
# nl-maintenance.sh — Windows-native (and darwin-portable) central
# maintenance core (harness-execution-redesign-2026-08, Task 3 / Stage 1).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
# R3.1 (operator, 2026-08-02c) rules out WSL2/systemd for good: no bespoke
# resident daemon, no plane. The landing zone the considerations brief names
# as the fallback is "central management logic, distributed cheap
# execution, scheduled by the OS scheduler each machine already has" — THIS
# file is that central management logic. It hosts the six maintenance
# mechanisms named in the 2026-08-02 RCA (coord-sync, supervisor-tick,
# workstreams-heartbeat, session-resumer, health-tick, downstream-product-
# health-monitor) as INTERNAL JOBS on completion-anchored schedules (invariant
# 2: a job's next run is scheduled only after ITS OWN prior invocation
# returns, so cadence >= cycle time holds BY CONSTRUCTION — no more of the
# coord-sync 60s-declared/110s-measured overlap class), reading its job
# table from `config/schedule-manifest.json` (the aggregate artifact Task 1
# bootstrapped) rather than hardcoding it here.
#
# It does NOT rewrite any of the six scripts' own logic (invariant: "the
# core invokes them as jobs without forking their logic") — each job is
# still literally `bash <script> <args>`, unchanged, single-flighted /
# HALT-checked internally exactly as Task 1 left them. This file is the
# SCHEDULER, not a rewrite.
#
# ============================================================
# MODES
# ============================================================
#   --tick                 run ONE scheduling pass: run every due job, then
#                           (subject to its own separate TTL) refresh the
#                           dashboard/inventory snapshot. Single-flighted
#                           against a concurrent tick (invariant 4). This is
#                           what the OS-level watchdog task / an operator's
#                           manual invocation calls.
#   --daemon [--interval S] [--max-iterations N]
#                           loop --tick + sleep <S> (default 20s) forever
#                           (or until --max-iterations, self-test only),
#                           writing a heartbeat file every pass regardless
#                           of HALT state (invariant 5: freshness, not
#                           liveness — a HALTed daemon must still look
#                           ALIVE-but-draining, never silently indistinguish-
#                           able from dead).
#   --watchdog              the ONE remaining recurring OS task's actual
#                           command (invariant 11 + the daemon pre-mortem's
#                           "exactly one deterministic watchdog"): checks the
#                           daemon heartbeat's freshness; relaunches
#                           `--daemon` backgrounded (nohup+disown, mirroring
#                           ensure-cockpit.sh's exact dispatch contract) iff
#                           stale AND not already relaunching. Always exits 0.
#   --status [--json]      human/debug snapshot of job due-ness + snapshot
#                           freshness + HALT state. NOT the dashboard's own
#                           read path (the dashboard reads snapshot files
#                           directly for true O(1) — invariant 3).
#   --self-test             fixture-sandboxed suite.
#
# ============================================================
# STATE (NL_MAINT_STATE_DIR override; HARNESS_SELFTEST=1 auto-sandboxes)
# ============================================================
#   jobs/<id>.last_completed     epoch of the job's last COMPLETION (not
#                                 start — this is what makes scheduling
#                                 completion-anchored)
#   daemon.heartbeat.json        {"generated_at":"...","pid":N,"halted":bool}
#   daemon.pid                   the running --daemon's pid (best-effort)
#   snapshots/dashboard.json     inventory + cost-budget + gate-friction
#                                 (TTL-materialized, atomic tmp+rename)
#   logs/tick.jsonl               one line per job run/skip (size-capped)
#   bypass-ledger.jsonl           NL_FORCE/--no-cache ledger rows this core
#                                 itself triggers (invariant 7) -- doctor's
#                                 OWN bypass ledger (harness-doctor.sh) is
#                                 separate and documented there.
#
# Self-test: bash nl-maintenance.sh --self-test

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/nl-paths.sh
{ source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck source=lib/single-flight-lib.sh
{ source "$SCRIPT_DIR/../hooks/lib/single-flight-lib.sh" 2>/dev/null; } || true
# shellcheck source=lib/portable-timeout.sh
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() { local s="${1:-}"; shift 2>/dev/null || true; "$@"; }
fi

# ----------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------
_nm_state_dir() {
  if [[ -n "${NL_MAINT_STATE_DIR:-}" ]]; then
    printf '%s' "$NL_MAINT_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/nl-maintenance-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/nl-maintenance' "${HOME:-$PWD}"
}

_nm_jobs_dir()   { printf '%s/jobs' "$(_nm_state_dir)"; }
_nm_snap_dir()   { printf '%s/snapshots' "$(_nm_state_dir)"; }
_nm_logs_dir()   { printf '%s/logs' "$(_nm_state_dir)"; }
_nm_heartbeat_path() { printf '%s/daemon.heartbeat.json' "$(_nm_state_dir)"; }
_nm_pid_path()        { printf '%s/daemon.pid' "$(_nm_state_dir)"; }
_nm_dashboard_path()  { printf '%s/dashboard.json' "$(_nm_snap_dir)"; }
_nm_tick_log_path()   { printf '%s/tick.jsonl' "$(_nm_logs_dir)"; }

_nm_repo_root() {
  if [[ -n "${NL_REPO_ROOT:-}" ]]; then
    printf '%s' "$NL_REPO_ROOT"
    return 0
  fi
  if declare -F nl_repo_root >/dev/null 2>&1; then
    nl_repo_root
    return 0
  fi
  printf '%s' "$(cd "$SCRIPT_DIR/../../.." && pwd)"
}

_nm_manifest_path() {
  if [[ -n "${NL_MAINT_MANIFEST:-}" ]]; then
    printf '%s' "$NL_MAINT_MANIFEST"
    return 0
  fi
  printf '%s/adapters/claude-code/config/schedule-manifest.json' "$(_nm_repo_root)"
}

_nm_now() {
  if declare -F nl_now_epoch >/dev/null 2>&1; then
    nl_now_epoch
    return 0
  fi
  date +%s 2>/dev/null || echo 0
}

_nm_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/ }"; s="${s//$cr/ }"; s="${s//$tab/ }"
  printf '%s' "$s"
}

_nm_atomic_write() {
  # _nm_atomic_write <target> <content> — tmp+rename (invariant: a reader
  # sees the old or the new file, never a partial one — Edge Case 3).
  local target="$1" content="$2" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="${target}.tmp.$$"
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

_nm_log() {
  # _nm_log <fields-json-fragment-without-braces> — appends one JSONL line
  # to logs/tick.jsonl, size-capped (>200KB -> tail-keep newest 1000 lines,
  # same house convention as perf-tick-snapshot.sh's ticks.jsonl).
  local frag="$1" dir file ts
  dir="$(_nm_logs_dir)"; mkdir -p "$dir" 2>/dev/null || return 0
  file="$(_nm_tick_log_path)"
  if [[ -f "$file" ]] && [[ "$(wc -c < "$file" 2>/dev/null || echo 0)" -gt 200000 ]]; then
    tail -n 1000 "$file" > "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file" 2>/dev/null
  fi
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '{"ts":"%s",%s}\n' "$(_nm_json_escape "$ts")" "$frag" >> "$file" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# jq availability — the job table + dashboard both read schedule-
# manifest.json's nested mechanisms[] array; this repo's own convention
# (session-heartbeat-lib.sh etc.) prefers a jq-free sed fallback for FLAT
# per-field extraction, but a nested array-of-objects filtered by a field
# match is exactly jq's job and re-deriving that in sed would be a real,
# fragile parser. jq is present on every machine this redesign targets
# (verified at build time); absence degrades HONESTLY (WARN + skip the
# job-table-driven tick, never a silent no-op that looks like success).
# ----------------------------------------------------------------------
_nm_have_jq() { command -v jq >/dev/null 2>&1; }

# _nm_jq <jq args...> — thin wrapper stripping \r from jq's output. PROVEN
# at build time: this machine's jq (a native Windows exe on PATH under Git
# Bash) writes CRLF line endings even for -r single-value output, so a
# captured "$(jq -r ...)" leaves a trailing \r glued onto the value after
# bash's command substitution strips only the trailing \n (the exact
# CRLF-corruption class perf-tick-snapshot.sh already documents for wmic
# output) -- every jq call in this file goes through this wrapper instead
# of raw `jq` so string-equality checks against extracted values (job ids,
# managed_by, script paths) never silently fail on an invisible \r.
_nm_jq() { jq "$@" 2>/dev/null | tr -d '\r'; }

# ----------------------------------------------------------------------
# Job table (schedule-manifest.json mechanisms[] where managed_by ==
# "nl-maintenance")
# ----------------------------------------------------------------------
_nm_job_ids() {
  local manifest; manifest="$(_nm_manifest_path)"
  [[ -f "$manifest" ]] || return 0
  _nm_jq -r '.mechanisms[] | select(.managed_by == "nl-maintenance") | .id' "$manifest"
}

_nm_job_field() {
  local id="$1" field="$2" manifest
  manifest="$(_nm_manifest_path)"
  [[ -f "$manifest" ]] || return 0
  _nm_jq -r --arg id "$id" --arg f "$field" '.mechanisms[] | select(.id == $id) | .[$f] // empty' "$manifest"
}

_nm_job_args() {
  local id="$1" manifest
  manifest="$(_nm_manifest_path)"
  [[ -f "$manifest" ]] || return 0
  _nm_jq -r --arg id "$id" '.mechanisms[] | select(.id == $id) | (.script_args // [])[]' "$manifest"
}

_nm_last_completed() {
  local id="$1" f
  f="$(_nm_jobs_dir)/${id}.last_completed"
  [[ -f "$f" ]] && cat "$f" 2>/dev/null || printf '0'
}

_nm_mark_completed() {
  local id="$1" now
  now="$(_nm_now)"
  mkdir -p "$(_nm_jobs_dir)" 2>/dev/null || return 0
  _nm_atomic_write "$(_nm_jobs_dir)/${id}.last_completed" "$now"
}

_nm_job_due() {
  local id="$1" cadence="$2" last now
  last="$(_nm_last_completed "$id")"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  [[ "$last" -eq 0 ]] && return 0        # never run -> due immediately
  [[ "$cadence" =~ ^[0-9]+$ ]] || cadence=300
  now="$(_nm_now)"
  [[ $(( now - last )) -ge "$cadence" ]]
}

# _nm_run_job <id> — resolves script+args, runs it (bounded, so one wedged
# job can never hang the whole tick forever), marks completion AFTER the
# subprocess returns regardless of exit code (completion-anchored retry:
# a failing job's next attempt is still floored at cadence seconds away,
# never a tight retry loop). tolerate-absent (script null/missing) still
# "completes" so its own cadence throttles repeat log noise instead of
# firing every tick.
_nm_run_job() {
  local id="$1" script args=() a rc dur t0 t1 repo full
  script="$(_nm_job_field "$id" script)"
  repo="$(_nm_repo_root)"
  while IFS= read -r a; do [[ -n "$a" ]] && args+=("$a"); done < <(_nm_job_args "$id")

  if [[ -z "$script" || "$script" == "null" ]]; then
    _nm_log "\"job\":\"$(_nm_json_escape "$id")\",\"action\":\"skip\",\"reason\":\"no script declared (external/tolerate-absent)\""
    _nm_mark_completed "$id"
    return 0
  fi

  full="$script"
  [[ "$script" != /* ]] && full="${repo}/${script}"
  if [[ ! -f "$full" ]]; then
    _nm_log "\"job\":\"$(_nm_json_escape "$id")\",\"action\":\"skip\",\"reason\":\"script not found at $(_nm_json_escape "$full")\""
    _nm_mark_completed "$id"
    return 0
  fi

  t0="$(_nm_now)"
  if [[ "${HARNESS_SELFTEST:-0}" == "1" && "${NL_MAINT_SELFTEST_RUN_REAL_JOBS:-0}" != "1" ]]; then
    # Self-test default: never actually run a real maintenance script (each
    # of the six has its own heavy self-test; this suite proves SCHEDULING,
    # not their internals). NL_MAINT_SELFTEST_RUN_REAL_JOBS=1 opts a
    # specific scenario into a real invocation (used for the tolerate-
    # absent / real-script-exists scenarios below).
    rc=0
    _nm_log "\"job\":\"$(_nm_json_escape "$id")\",\"action\":\"selftest-stub\",\"exit_code\":0,\"would_run\":\"$(_nm_json_escape "bash $full ${args[*]:-}")\""
  else
    nl_run_bounded 600 bash "$full" "${args[@]:-}" >/dev/null 2>&1
    rc=$?
    t1="$(_nm_now)"
    dur=$(( t1 - t0 ))
    _nm_log "\"job\":\"$(_nm_json_escape "$id")\",\"action\":\"run\",\"exit_code\":${rc},\"duration_s\":${dur}"
  fi
  _nm_mark_completed "$id"
  return 0
}

# ----------------------------------------------------------------------
# Dashboard/inventory snapshot (TTL, default 5 min — cheap, not the
# heavier doctor-verdict TTL). Computes: hooks-per-Bash, SessionStart
# spawn count (from settings.json.template, LIVE-settings when present),
# per-mechanism cost x fire-rate from schedule-manifest.json, and gate-
# friction from a workaround ledger IF one exists yet (Task 2's remaining
# scope owns building the ledger writer -- see In-flight scope updates in
# the plan; this reader degrades to an honest empty state, never fakes
# data, when the file is absent).
# ----------------------------------------------------------------------
_nm_dashboard_ttl_seconds() { printf '%s' "${NL_MAINT_DASHBOARD_TTL_SECONDS:-300}"; }

_nm_count_bash_hooks() {
  # Mirrors harness-doctor.sh's _count_bash_hooks exactly (same jq
  # expression, cited there) -- duplicated rather than sourced because
  # harness-doctor.sh has no guard against executing its own bottom
  # dispatch on `source`, so sourcing it here would be unsafe. Kept as a
  # named follow-up (extract to a shared lib) rather than silently
  # re-derived and left undocumented.
  local settings="$1"
  [[ -f "$settings" ]] || { printf ''; return 0; }
  _nm_jq -r '[(.hooks.PreToolUse // [])[] | select(.matcher // "" | contains("Bash")) | (.hooks // []) | length] | add // 0' "$settings"
}

_nm_count_sessionstart_spawns() {
  local settings="$1"
  [[ -f "$settings" ]] || { printf ''; return 0; }
  _nm_jq -r '[(.hooks.SessionStart // [])[] | (.hooks // []) | length] | add // 0' "$settings"
}

_nm_count_scheduled_tasks_enabled() {
  # Counts legacy_task_name entries from schedule-manifest.json that
  # schtasks reports as NOT Disabled. Non-Windows / schtasks-absent ->
  # empty (honest "not applicable here"), never a fabricated 0.
  local manifest="$1"
  command -v schtasks >/dev/null 2>&1 || { printf ''; return 0; }
  local names name state n=0
  names="$(_nm_jq -r '.mechanisms[] | select(.legacy_task_name != null) | .legacy_task_name' "$manifest")"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    state="$(MSYS_NO_PATHCONV=1 schtasks /Query /TN "$name" /FO LIST /V 2>/dev/null | tr -d '\r' | sed -nE 's/^Scheduled Task State:[[:space:]]*//p' | head -1)"
    [[ "$state" == "Enabled" ]] && n=$((n + 1))
  done <<< "$names"
  printf '%s' "$n"
}

_nm_refresh_dashboard_snapshot() {
  local force="${1:-0}" snap ttl now age gen
  snap="$(_nm_dashboard_path)"
  ttl="$(_nm_dashboard_ttl_seconds)"
  now="$(_nm_now)"
  if [[ "$force" != "1" && -f "$snap" ]]; then
    gen="$(sed -nE 's/.*"generated_at_epoch":([0-9]+).*/\1/p' "$snap" 2>/dev/null | head -1)"
    if [[ "$gen" =~ ^[0-9]+$ ]]; then
      age=$(( now - gen ))
      [[ "$age" -lt "$ttl" ]] && return 0
    fi
  fi

  local repo manifest live_home template_settings live_settings
  repo="$(_nm_repo_root)"
  manifest="$(_nm_manifest_path)"
  live_home="${HARNESS_DOCTOR_HOME:-${HOME:-$PWD}/.claude}"
  template_settings="${repo}/adapters/claude-code/settings.json.template"
  live_settings="${live_home}/settings.json"

  local hooks_template hooks_live sstart_template sstart_live tasks_enabled
  hooks_template="$(_nm_count_bash_hooks "$template_settings")"
  hooks_live="$(_nm_count_bash_hooks "$live_settings")"
  sstart_template="$(_nm_count_sessionstart_spawns "$template_settings")"
  sstart_live="$(_nm_count_sessionstart_spawns "$live_settings")"
  [[ -f "$manifest" ]] && tasks_enabled="$(_nm_count_scheduled_tasks_enabled "$manifest")" || tasks_enabled=""
  [[ -z "$hooks_template" ]] && hooks_template=null
  [[ -z "$hooks_live" ]] && hooks_live=null
  [[ -z "$sstart_template" ]] && sstart_template=null
  [[ -z "$sstart_live" ]] && sstart_live=null
  [[ -z "$tasks_enabled" ]] && tasks_enabled=null

  # Cost-budget rows: cost_per_day_ms = (86400 / declared_cadence_seconds)
  # * windows spawn_cost_ms -- a rough, DOCUMENTED-as-rough per-mechanism
  # daily hook-spawn cost estimate (invariant 1/10), not a full CPU-time
  # profile (spawns_per_cycle is still "not yet profiled" per the
  # manifest's own honest field).
  local cost_rows="[]"
  if [[ -f "$manifest" ]]; then
    cost_rows="$(_nm_jq -c '[.mechanisms[] | {
        id: .id,
        managed_by: (.managed_by // "unknown"),
        declared_cadence_seconds: .declared_cadence_seconds,
        spawn_cost_ms: (.platform_cost_lines.windows.spawn_cost_ms // null),
        fires_per_day: (if .declared_cadence_seconds and .declared_cadence_seconds > 0 then (86400 / .declared_cadence_seconds) else null end),
        est_spawn_ms_per_day: (if .declared_cadence_seconds and .declared_cadence_seconds > 0 and .platform_cost_lines.windows.spawn_cost_ms then ((86400 / .declared_cadence_seconds) * .platform_cost_lines.windows.spawn_cost_ms) else null end)
      }]' "$manifest")"
    [[ -z "$cost_rows" ]] && cost_rows="[]"
  fi

  # Gate friction: reads a workaround ledger IF one exists yet. Schema
  # (proposed here, honest about not being pre-agreed -- Task 2's
  # remaining scope owns the writer; see the plan's In-flight scope
  # updates for this exact note): one JSONL line per event,
  # {"ts":"...","gate":"<name>","event":"block"|"workaround"|"check"}.
  local friction_path friction_rows="[]"
  friction_path="${NL_MAINT_FRICTION_LEDGER:-${live_home}/state/gate-friction/ledger.jsonl}"
  if [[ -f "$friction_path" ]]; then
    friction_rows="$(_nm_jq -sc '
      group_by(.gate) | map({
        gate: .[0].gate,
        blocks: (map(select(.event=="block")) | length),
        workarounds: (map(select(.event=="workaround")) | length)
      })' "$friction_path")"
    [[ -z "$friction_rows" ]] && friction_rows="[]"
  fi
  local friction_available; [[ -f "$friction_path" ]] && friction_available=true || friction_available=false

  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local payload
  payload="$(_nm_jq -nc \
    --arg ts "$ts" \
    --argjson gen_epoch "$now" \
    --argjson hooks_template "$hooks_template" \
    --argjson hooks_live "$hooks_live" \
    --argjson sstart_template "$sstart_template" \
    --argjson sstart_live "$sstart_live" \
    --argjson tasks_enabled "$tasks_enabled" \
    --argjson cost_rows "$cost_rows" \
    --argjson friction_rows "$friction_rows" \
    --argjson friction_available "$friction_available" \
    '{
      schema: 1,
      generated_at: $ts,
      generated_at_epoch: $gen_epoch,
      inventory: {
        hooks_per_bash: { template: $hooks_template, live: $hooks_live, target: 6 },
        sessionstart_spawns: { template: $sstart_template, live: $sstart_live, target: 2 },
        legacy_scheduled_tasks_enabled: { count: $tasks_enabled, target_max: 2 }
      },
      cost_budget: $cost_rows,
      gate_friction: { available: $friction_available, rows: $friction_rows }
    }')"
  [[ -z "$payload" ]] && return 1
  _nm_atomic_write "$snap" "$payload"
}

# ----------------------------------------------------------------------
# Heartbeat + tick
# ----------------------------------------------------------------------
_nm_write_heartbeat() {
  local halted="$1" ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local payload
  payload="$(printf '{"schema":1,"generated_at":"%s","generated_at_epoch":%s,"pid":%s,"halted":%s}' \
    "$(_nm_json_escape "$ts")" "$(_nm_now)" "$$" "$halted")"
  _nm_atomic_write "$(_nm_heartbeat_path)" "$payload"
}

# _nm_write_activation_marker_once — write-once (never overwritten) epoch
# of this core's FIRST real tick on this machine. harness-doctor.sh's
# check_maintenance_both_substrates_alive (Task 3, invariant 9) reads this
# to RED "both substrates alive > 14 days" -- the anchor must never move
# once set, or the 14-day clock would silently reset on every restart.
_nm_write_activation_marker_once() {
  local f; f="$(_nm_state_dir)/activation-marker"
  [[ -f "$f" ]] && return 0
  _nm_atomic_write "$f" "$(_nm_now)"
}

_nm_tick_body() {
  if ! _nm_have_jq; then
    _nm_log "\"action\":\"tick-skip\",\"reason\":\"jq unavailable -- job-table-driven tick skipped (honest WARN, not a silent no-op)\""
    echo "[nl-maintenance] WARN: jq not found -- cannot read schedule-manifest.json's job table this tick" >&2
    _nm_write_heartbeat false
    return 0
  fi

  if declare -F sf_halt_active >/dev/null 2>&1 && sf_halt_active; then
    _nm_log "\"action\":\"tick-drain\",\"reason\":\"HALT flag set\""
    echo "[nl-maintenance] HALT flag set ($(sf_halt_reason 2>/dev/null)) — draining: no job runs this tick" >&2
    _nm_write_heartbeat true
    return 0
  fi

  local id cadence
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    cadence="$(_nm_job_field "$id" declared_cadence_seconds)"
    [[ -z "$cadence" || "$cadence" == "null" ]] && cadence=300
    if _nm_job_due "$id" "$cadence"; then
      _nm_run_job "$id"
    fi
  done < <(_nm_job_ids)

  _nm_refresh_dashboard_snapshot 0
  _nm_write_activation_marker_once
  _nm_write_heartbeat false
  return 0
}

run_tick() {
  # Single-flighted (invariant 4) -- a manual `--tick` racing the watchdog-
  # relaunched daemon's own tick, or two watchdog fires overlapping, both
  # collapse to one real tick instead of double-running jobs.
  if declare -F sf_guard >/dev/null 2>&1; then
    if ! SF_STATE_DIR="$(_nm_state_dir)/single-flight" sf_guard "nl-maintenance-tick" 120; then
      return 0
    fi
  fi
  _nm_tick_body
}

# ----------------------------------------------------------------------
# --daemon
# ----------------------------------------------------------------------
run_daemon() {
  local interval="${NM_DAEMON_INTERVAL:-20}" max_iterations="${NM_DAEMON_MAX_ITERATIONS:-0}"
  local args=("$@") i=0 a
  local n=${#args[@]}
  while [[ $i -lt $n ]]; do
    a="${args[$i]}"
    case "$a" in
      --interval) i=$((i+1)); interval="${args[$i]:-$interval}" ;;
      --max-iterations) i=$((i+1)); max_iterations="${args[$i]:-0}" ;;
    esac
    i=$((i+1))
  done

  mkdir -p "$(_nm_state_dir)" 2>/dev/null || true
  printf '%s' "$$" > "$(_nm_pid_path)" 2>/dev/null || true

  local count=0
  while true; do
    run_tick
    # HR-F1: release the per-tick single-flight guard now that this pass's
    # work is done. single-flight-lib.sh's recursion var is a run-to-exit
    # assumption (see its header, "THE RUN-TO-EXIT ASSUMPTION") and THIS
    # loop is a long-lived resident process re-entering the SAME guard
    # <name> every pass -- without an explicit release, pass 1 would set
    # the recursion var and every later pass in this SAME process would
    # see "recursion detected" and skip forever (the daemon ticks exactly
    # once, then wedges on its own guard). sf_release is a safe no-op when
    # this process never actually acquired the guard this pass (e.g. it
    # was skipped by HALT or by a genuinely concurrent holder) -- it only
    # ever releases a hold THIS process itself set.
    if declare -F sf_release >/dev/null 2>&1; then
      SF_STATE_DIR="$(_nm_state_dir)/single-flight" sf_release "nl-maintenance-tick"
    fi
    count=$((count + 1))
    if [[ "$max_iterations" -gt 0 && "$count" -ge "$max_iterations" ]]; then
      break
    fi
    sleep "$interval" 2>/dev/null || sleep 1
  done
}

# ----------------------------------------------------------------------
# --watchdog — the ONE remaining recurring OS task's real command.
# Mirrors ensure-cockpit.sh's contract exactly: HARNESS_SELFTEST=1 stubs
# BEFORE any real spawn, always returns 0, tolerate-absent everywhere.
# ----------------------------------------------------------------------
_nm_watchdog_stale_seconds() { printf '%s' "${NM_WATCHDOG_STALE_SECONDS:-300}"; }

# _nm_pid_cmdline <pid> — best-effort full command line for <pid>. Tries
# /proc/<pid>/cmdline first (present under MSYS2/Git-Bash on Windows and on
# Linux; NUL-separated argv, translated to spaces), falling back to
# `ps -fp <pid>` (covers macOS/BSD and any environment lacking /proc; `-f`
# is required here — a bare `ps -p` on this repo's MSYS2 ps prints only the
# executable path in COMMAND, e.g. "/usr/bin/bash", never the args, which
# would make identity verification impossible). Empty output/rc 1 means
# "could not determine" — callers MUST treat that as a non-match (fail
# closed: never kill on unknown identity).
_nm_pid_cmdline() {
  local pid="$1" out
  if [[ -r "/proc/$pid/cmdline" ]]; then
    out="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
    if [[ -n "$out" ]]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  out="$(ps -fp "$pid" 2>/dev/null | tail -n +2)"
  if [[ -n "$out" ]]; then
    printf '%s' "$out"
    return 0
  fi
  printf ''
  return 1
}

# _nm_pid_is_daemon <pid> — rc 0 iff <pid>'s command line names BOTH
# nl-maintenance and --daemon. This is the identity check the watchdog
# MUST pass before it ever kills the pid named in daemon.pid: Windows
# reuses PIDs, so an unverified kill against a stale/reused pid is
# unbounded harm (kills an unrelated, innocent process); an identity
# mismatch instead falls back to log-and-skip, which is bounded harm (at
# worst one extra resident bash process until it exits on its own, or
# until sf_release's per-pass fix (HR-F1) lets it keep ticking correctly).
_nm_pid_is_daemon() {
  local pid="$1" cmd
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  cmd="$(_nm_pid_cmdline "$pid")"
  [[ -z "$cmd" ]] && return 1
  [[ "$cmd" == *nl-maintenance* && "$cmd" == *--daemon* ]]
}

run_watchdog() {
  local hb hb_epoch now age stale
  hb="$(_nm_heartbeat_path)"
  now="$(_nm_now)"
  stale="$(_nm_watchdog_stale_seconds)"

  if [[ -f "$hb" ]]; then
    hb_epoch="$(sed -nE 's/.*"generated_at_epoch":([0-9]+).*/\1/p' "$hb" 2>/dev/null | head -1)"
  else
    hb_epoch=""
  fi

  if [[ "$hb_epoch" =~ ^[0-9]+$ ]]; then
    age=$(( now - hb_epoch ))
    if [[ "$age" -lt "$stale" ]]; then
      echo "[nl-maintenance-watchdog] daemon heartbeat fresh (${age}s old, threshold ${stale}s) — no action" >&2
      return 0
    fi
  else
    age="unknown"
  fi

  # Single-flight the relaunch decision itself (invariant 4) so two
  # overlapping watchdog fires never double-spawn the daemon.
  if declare -F sf_guard >/dev/null 2>&1; then
    if ! SF_STATE_DIR="$(_nm_state_dir)/single-flight" sf_guard "nl-maintenance-watchdog-relaunch" 60; then
      echo "[nl-maintenance-watchdog] relaunch already claimed by a concurrent watchdog fire — skipping" >&2
      return 0
    fi
  fi

  _nm_log "\"action\":\"watchdog-relaunch\",\"reason\":\"stale heartbeat\",\"heartbeat_age_s\":\"$(_nm_json_escape "$age")\""

  # HR-F1: before relaunching, try to kill the OLD daemon named in
  # daemon.pid -- but ONLY after verifying its command line actually names
  # nl-maintenance --daemon. daemon.pid was written but never read before
  # this fix, so old daemons (wedged on the recursion-guard bug above)
  # accumulated forever, each relaunch piling a new one on top. Identity
  # mismatch (missing pid file, dead pid, or a live pid whose command line
  # doesn't match -- e.g. Windows reused the pid for an unrelated process)
  # is ALWAYS log-and-skip, never kill: an unverified kill is unbounded
  # harm (an innocent process dies); leaving a genuine stale daemon alive
  # one extra relaunch cycle is bounded harm.
  local old_pid; old_pid="$(cat "$(_nm_pid_path)" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$old_pid" =~ ^[0-9]+$ ]]; then
    if _nm_pid_is_daemon "$old_pid"; then
      _nm_log "\"action\":\"watchdog-kill\",\"pid\":\"${old_pid}\",\"reason\":\"stale heartbeat, verified nl-maintenance --daemon cmdline\""
      if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
        echo "[nl-maintenance-watchdog self-test stub] would kill verified-stale daemon pid ${old_pid} — never signaled" >&2
      else
        echo "[nl-maintenance-watchdog] killing verified-stale daemon pid ${old_pid}" >&2
        kill "$old_pid" 2>/dev/null || true
      fi
    else
      _nm_log "\"action\":\"watchdog-kill-skip\",\"pid\":\"${old_pid}\",\"reason\":\"cmdline identity mismatch\""
      echo "[nl-maintenance-watchdog] daemon.pid names ${old_pid} but its command line does not confirm nl-maintenance --daemon — NOT killing (log-and-skip; PIDs are reused)" >&2
    fi
  fi

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    echo "[nl-maintenance-watchdog self-test stub] would relaunch: bash $(dirname "${BASH_SOURCE[0]}")/nl-maintenance.sh --daemon (heartbeat age: ${age}s) — never spawned" >&2
    return 0
  fi

  local self="${BASH_SOURCE[0]}"
  mkdir -p "$(_nm_logs_dir)" 2>/dev/null || true
  echo "[nl-maintenance-watchdog] heartbeat stale (${age}s, threshold ${stale}s) — relaunching daemon" >&2
  nohup bash "$self" --daemon >>"$(_nm_logs_dir)/daemon.stdout.log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
  return 0
}

# ----------------------------------------------------------------------
# --status
# ----------------------------------------------------------------------
run_status() {
  local halted="no"
  if declare -F sf_halt_active >/dev/null 2>&1 && sf_halt_active; then halted="yes"; fi
  echo "nl-maintenance status"
  echo "  state dir: $(_nm_state_dir)"
  echo "  HALT: ${halted}"
  local hb; hb="$(_nm_heartbeat_path)"
  if [[ -f "$hb" ]]; then
    echo "  daemon heartbeat: $(cat "$hb" 2>/dev/null)"
  else
    echo "  daemon heartbeat: (none yet)"
  fi
  if _nm_have_jq; then
    local id cadence last now due
    now="$(_nm_now)"
    echo "  jobs:"
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      cadence="$(_nm_job_field "$id" declared_cadence_seconds)"
      last="$(_nm_last_completed "$id")"
      if _nm_job_due "$id" "$cadence"; then due="DUE"; else due="not due"; fi
      echo "    - ${id}: cadence=${cadence}s last_completed_epoch=${last} (${due})"
    done < <(_nm_job_ids)
  fi
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/nl-maint-st-$$")"
  mkdir -p "$tmp"
  local self_abs bash_bin
  self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  bash_bin="${BASH:-$(command -v bash)}"

  _ok() { if [[ "$1" == "$2" ]]; then echo "PASS: $3"; pass=$((pass+1)); else echo "FAIL: $3 (got '$1' want '$2')" >&2; fail=$((fail+1)); fi; }
  _contains() { if [[ "$1" == *"$2"* ]]; then echo "PASS: $3"; pass=$((pass+1)); else echo "FAIL: $3 (did not contain '$2'; got: $1)" >&2; fail=$((fail+1)); fi; }
  _file_exists() { if [[ -f "$1" ]]; then echo "PASS: $2"; pass=$((pass+1)); else echo "FAIL: $2 (file missing: $1)" >&2; fail=$((fail+1)); fi; }

  if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: nl-maintenance.sh self-test requires jq (not found on PATH) — cannot exercise the job-table-driven scenarios" >&2
    rm -rf "$tmp" 2>/dev/null || true
    exit 0
  fi

  # Fixture repo + manifest -----------------------------------------------
  local repo="$tmp/repo"
  mkdir -p "$repo/adapters/claude-code/scripts" "$repo/adapters/claude-code/config" "$repo/adapters/claude-code/hooks/lib"
  cat > "$repo/adapters/claude-code/scripts/fixture-job-a.sh" <<'EOF'
#!/usr/bin/env bash
echo "job-a ran" >> "${NM_FIXTURE_MARKER:-/dev/null}"
exit 0
EOF
  chmod +x "$repo/adapters/claude-code/scripts/fixture-job-a.sh"

  cat > "$repo/adapters/claude-code/scripts/fixture-job-fails.sh" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$repo/adapters/claude-code/scripts/fixture-job-fails.sh"

  cat > "$repo/adapters/claude-code/config/schedule-manifest.json" <<EOF
{
  "schema_version": 2,
  "mechanisms": [
    {"id":"job-a","script":"adapters/claude-code/scripts/fixture-job-a.sh","script_args":["x","y"],"managed_by":"nl-maintenance","declared_cadence_seconds":5,"legacy_task_name":null,"platform_cost_lines":{"windows":{"spawn_cost_ms":152}}},
    {"id":"job-fails","script":"adapters/claude-code/scripts/fixture-job-fails.sh","script_args":[],"managed_by":"nl-maintenance","declared_cadence_seconds":5,"legacy_task_name":null,"platform_cost_lines":{}},
    {"id":"job-external","script":null,"script_args":[],"managed_by":"external","declared_cadence_seconds":1800,"legacy_task_name":null,"platform_cost_lines":{}},
    {"id":"job-missing-script","script":"adapters/claude-code/scripts/does-not-exist.sh","script_args":[],"managed_by":"nl-maintenance","declared_cadence_seconds":5,"legacy_task_name":null,"platform_cost_lines":{}}
  ]
}
EOF

  export NL_REPO_ROOT="$repo"
  export NL_MAINT_MANIFEST="$repo/adapters/claude-code/config/schedule-manifest.json"
  export SF_DISABLE=1

  echo "Scenario 1: job table only includes managed_by=nl-maintenance entries"
  local ids; ids="$(NL_MAINT_STATE_DIR="$tmp/s1" bash -c "source '$self_abs'; _nm_job_ids" | tr '\n' ',')"
  _contains "$ids" "job-a," "S1 job-a present in managed job table"
  _contains "$ids" "job-fails," "S1 job-fails present in managed job table"
  _contains "$ids" "job-missing-script," "S1 job-missing-script present in managed job table"
  if [[ "$ids" != *"job-external"* ]]; then
    echo "PASS: S1 job-external (managed_by=external) excluded from the job table"; pass=$((pass+1))
  else
    echo "FAIL: S1 job-external should be excluded" >&2; fail=$((fail+1))
  fi

  echo "Scenario 2: a due, real-script job runs for real (NL_MAINT_SELFTEST_RUN_REAL_JOBS=1) and marks completion"
  local s2_state="$tmp/s2" s2_marker="$tmp/s2-marker.txt"
  rm -f "$s2_marker"
  NL_MAINT_STATE_DIR="$s2_state" NM_FIXTURE_MARKER="$s2_marker" NL_MAINT_SELFTEST_RUN_REAL_JOBS=1 HARNESS_SELFTEST=1 \
    bash -c "source '$self_abs'; _nm_run_job job-a"
  _file_exists "$s2_marker" "S2 fixture job-a actually executed (marker file written)"
  local s2_last; s2_last="$(cat "$s2_state/jobs/job-a.last_completed" 2>/dev/null)"
  if [[ "$s2_last" =~ ^[0-9]+$ && "$s2_last" -gt 0 ]]; then
    echo "PASS: S2 last_completed marker written with a real epoch"; pass=$((pass+1))
  else
    echo "FAIL: S2 expected a numeric last_completed, got '$s2_last'" >&2; fail=$((fail+1))
  fi

  echo "Scenario 3: a FAILING job still marks completion (completion-anchored retry -- failure does not retry-storm)"
  local s3_state="$tmp/s3"
  NL_MAINT_STATE_DIR="$s3_state" NL_MAINT_SELFTEST_RUN_REAL_JOBS=1 HARNESS_SELFTEST=1 \
    bash -c "source '$self_abs'; _nm_run_job job-fails"
  local s3_last; s3_last="$(cat "$s3_state/jobs/job-fails.last_completed" 2>/dev/null)"
  if [[ "$s3_last" =~ ^[0-9]+$ && "$s3_last" -gt 0 ]]; then
    echo "PASS: S3 a failing job still marks completion (re-arms from completion, not a tight retry)"; pass=$((pass+1))
  else
    echo "FAIL: S3 expected completion to be marked even on failure, got '$s3_last'" >&2; fail=$((fail+1))
  fi
  _contains "$(cat "$s3_state/logs/tick.jsonl" 2>/dev/null)" '"exit_code":7' "S3 tick log records the real nonzero exit code"

  echo "Scenario 4: a tolerate-absent job (missing script file) still marks completion and never errors"
  local s4_state="$tmp/s4"
  NL_MAINT_STATE_DIR="$s4_state" bash -c "source '$self_abs'; _nm_run_job job-missing-script"; s4_rc=$?
  _ok "$s4_rc" 0 "S4 missing-script job returns 0 (tolerate-absent)"
  local s4_last; s4_last="$(cat "$s4_state/jobs/job-missing-script.last_completed" 2>/dev/null)"
  [[ "$s4_last" =~ ^[0-9]+$ ]] && { echo "PASS: S4 completion marked despite missing script"; pass=$((pass+1)); } \
    || { echo "FAIL: S4 expected completion marked" >&2; fail=$((fail+1)); }

  echo "Scenario 5: completion-anchored due-ness — never-run job is due; a job completed 1s ago at cadence=5s is NOT due; backdating past cadence makes it due again"
  local s5_state="$tmp/s5"
  mkdir -p "$s5_state/jobs"
  local due5a; due5a="$(NL_MAINT_STATE_DIR="$s5_state" bash -c "source '$self_abs'; _nm_job_due job-a 5 && echo yes || echo no")"
  _ok "$due5a" "yes" "S5a never-run job is due immediately"
  printf '%s' "$(( $(date +%s) ))" > "$s5_state/jobs/job-a.last_completed"
  local due5b; due5b="$(NL_MAINT_STATE_DIR="$s5_state" bash -c "source '$self_abs'; _nm_job_due job-a 5 && echo yes || echo no")"
  _ok "$due5b" "no" "S5b just-completed job (cadence 5s) is NOT due"
  printf '%s' "$(( $(date +%s) - 10 ))" > "$s5_state/jobs/job-a.last_completed"
  local due5c; due5c="$(NL_MAINT_STATE_DIR="$s5_state" bash -c "source '$self_abs'; _nm_job_due job-a 5 && echo yes || echo no")"
  _ok "$due5c" "yes" "S5c completed 10s ago (cadence 5s) -> due again (completion-anchored floor)"

  echo "Scenario 6: HALT — a tick with HALT set runs NO jobs, but still writes a fresh (halted:true) heartbeat"
  local s6_state="$tmp/s6"
  mkdir -p "$s6_state/single-flight"
  printf '%s test-drain\n' "$(date +%s)" > "$s6_state/single-flight/HALT"
  SF_STATE_DIR="$s6_state/single-flight" SF_DISABLE=0 NL_MAINT_STATE_DIR="$s6_state" \
    bash -c "source '$self_abs'; SF_STATE_DIR='$s6_state/single-flight' _nm_tick_body" >/dev/null 2>&1
  if [[ -f "$s6_state/jobs/job-a.last_completed" ]]; then
    echo "FAIL: S6 job-a should NOT have run while HALTed" >&2; fail=$((fail+1))
  else
    echo "PASS: S6 no job ran while HALTed"; pass=$((pass+1))
  fi
  _contains "$(cat "$s6_state/daemon.heartbeat.json" 2>/dev/null)" '"halted":true' "S6 heartbeat still written, marked halted:true (freshness != liveness, invariant 5)"

  echo "Scenario 7: run_tick is single-flighted — a held lock skips the WHOLE tick (no jobs run, no crash)"
  local s7_state="$tmp/s7"
  # sf_guard's sanitizer collapses '-' to '_' for the lock dir name (single-
  # flight-lib.sh's _sf_sanitize) -- the fixture must pre-create the SAME
  # sanitized name ("nl_maintenance_tick.lock"), not the literal id.
  mkdir -p "$s7_state/single-flight/nl_maintenance_tick.lock"
  printf '%s %s\n' "$$" "$(date +%s)" > "$s7_state/single-flight/nl_maintenance_tick.lock/owner"
  NL_MAINT_STATE_DIR="$s7_state" SF_DISABLE=0 bash -c "source '$self_abs'; run_tick" >/dev/null 2>&1
  if [[ -f "$s7_state/jobs/job-a.last_completed" ]]; then
    echo "FAIL: S7 job should not have run — the tick itself should have been single-flight-skipped" >&2; fail=$((fail+1))
  else
    echo "PASS: S7 held tick lock skips the entire tick"; pass=$((pass+1))
  fi

  echo "Scenario 8: dashboard snapshot — TTL gate (fresh snapshot NOT recomputed unless forced), atomic write, honest empty gate-friction when the ledger file is absent"
  local s8_state="$tmp/s8"
  local s8_settings_dir="$tmp/s8-live"
  mkdir -p "$s8_settings_dir"
  cat > "$s8_settings_dir/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]},{"matcher":"Bash|PowerShell","hooks":[{"type":"command","command":"c"}]}],"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"d"},{"type":"command","command":"e"}]}]}}
EOF
  NL_MAINT_STATE_DIR="$s8_state" HARNESS_DOCTOR_HOME="$s8_settings_dir" NL_MAINT_FRICTION_LEDGER="$tmp/no-such-ledger.jsonl" \
    bash -c "source '$self_abs'; _nm_refresh_dashboard_snapshot 0"
  _file_exists "$s8_state/snapshots/dashboard.json" "S8 dashboard snapshot written"
  _contains "$(cat "$s8_state/snapshots/dashboard.json" 2>/dev/null)" '"hooks_per_bash"' "S8 snapshot carries hooks_per_bash inventory"
  _contains "$(cat "$s8_state/snapshots/dashboard.json" 2>/dev/null)" '"available":false' "S8 gate_friction honestly reports available:false when no ledger exists yet"
  local s8_before s8_after
  s8_before="$(cat "$s8_state/snapshots/dashboard.json" 2>/dev/null)"
  sleep 1
  NL_MAINT_STATE_DIR="$s8_state" HARNESS_DOCTOR_HOME="$s8_settings_dir" NL_MAINT_FRICTION_LEDGER="$tmp/no-such-ledger.jsonl" \
    bash -c "source '$self_abs'; _nm_refresh_dashboard_snapshot 0"
  s8_after="$(cat "$s8_state/snapshots/dashboard.json" 2>/dev/null)"
  _ok "$s8_after" "$s8_before" "S8 within-TTL re-call is a no-op (identical snapshot, not recomputed)"

  echo "Scenario 9: dashboard gate-friction reads a REAL ledger when present"
  local s9_state="$tmp/s9" s9_ledger="$tmp/s9-ledger.jsonl"
  printf '{"ts":"2026-01-01T00:00:00Z","gate":"scope-enforcement-gate","event":"block"}\n' > "$s9_ledger"
  printf '{"ts":"2026-01-01T00:00:01Z","gate":"scope-enforcement-gate","event":"workaround"}\n' >> "$s9_ledger"
  NL_MAINT_STATE_DIR="$s9_state" HARNESS_DOCTOR_HOME="$s8_settings_dir" NL_MAINT_FRICTION_LEDGER="$s9_ledger" \
    bash -c "source '$self_abs'; _nm_refresh_dashboard_snapshot 0"
  _contains "$(cat "$s9_state/snapshots/dashboard.json" 2>/dev/null)" '"available":true' "S9 gate_friction.available:true when the ledger exists"
  _contains "$(cat "$s9_state/snapshots/dashboard.json" 2>/dev/null)" 'scope-enforcement-gate' "S9 friction row names the real gate"

  echo "Scenario 10: --watchdog stub — fresh heartbeat means no relaunch; stale heartbeat means a logged (never-real-spawned under HARNESS_SELFTEST) relaunch"
  local s10_state="$tmp/s10"
  NL_MAINT_STATE_DIR="$s10_state" bash -c "source '$self_abs'; _nm_write_heartbeat false"
  local w10a; w10a="$(NL_MAINT_STATE_DIR="$s10_state" SF_DISABLE=1 bash -c "source '$self_abs'; run_watchdog" 2>&1)"
  _contains "$w10a" "fresh" "S10a fresh heartbeat -> no relaunch"
  mkdir -p "$s10_state"
  printf '{"schema":1,"generated_at":"2000-01-01T00:00:00Z","generated_at_epoch":1,"pid":1,"halted":false}' > "$s10_state/daemon.heartbeat.json"
  local w10b; w10b="$(NL_MAINT_STATE_DIR="$s10_state" SF_DISABLE=1 HARNESS_SELFTEST=1 bash -c "source '$self_abs'; run_watchdog" 2>&1)"
  _contains "$w10b" "self-test stub" "S10b stale heartbeat under HARNESS_SELFTEST logs the stub, never spawns real bash"
  _contains "$w10b" "would relaunch" "S10b stub names the relaunch it would have performed"

  echo "Scenario 11: --daemon under the REAL sf_guard (no SF_DISABLE) writes a fresh heartbeat on EVERY pass (HR-F1 -- was: the recursion guard was never released, so only the FIRST pass ever wrote a heartbeat and every later pass silently wedged, while the watchdog piled up relaunched daemons on top of the stuck one)"
  local s11_state="$tmp/s11"
  mkdir -p "$s11_state"
  local s11_hb="$s11_state/daemon.heartbeat.json"
  local s11_epochs="$tmp/s11-epochs.txt"
  : > "$s11_epochs"
  local s11_cmd=()
  if command -v timeout >/dev/null 2>&1; then
    s11_cmd=(timeout 20)
  fi
  # interval=1, not 0: _nm_now is second-resolution (`date +%s`), so a
  # zero-interval daemon can complete several passes inside the SAME
  # second, making "distinct heartbeat writes" unobservable by timestamp
  # alone -- a non-zero gap is what makes the distinct-epoch assertion
  # below reliable and non-flaky, while exercising the exact same
  # run_daemon loop the --interval 0 live/manual demo uses.
  s11_cmd+=(bash "$self_abs" --daemon --interval 1 --max-iterations 3)
  # SF_DISABLE=0 is REQUIRED here, not optional: the self-test's own setup
  # (above) does `export SF_DISABLE=1` for every OTHER scenario's
  # isolation, and that export is inherited by this backgrounded bash
  # subprocess same as any child process. Without this override S11 would
  # run the daemon with sf_guard fully bypassed -- the exact masking class
  # REQ-A1 exists to remove (the old S11 ran under SF_DISABLE=1 and could
  # not have caught HR-F1 even in principle). SF_STATE_DIR does not need a
  # separate override the way S6 needs one: S11 goes through run_daemon ->
  # run_tick, and run_tick prefixes its own sf_guard call with
  # SF_STATE_DIR="$(_nm_state_dir)/single-flight" internally (same
  # mechanism S7 already relies on) -- it is S6's direct, bypassing
  # `_nm_tick_body` call (which invokes sf_halt_active straight off the
  # raw $SF_STATE_DIR env var, with no such wrapper) that needs the
  # explicit SF_STATE_DIR prefix S6 uses.
  NL_MAINT_STATE_DIR="$s11_state" SF_DISABLE=0 "${s11_cmd[@]}" >"$tmp/s11.out" 2>"$tmp/s11.err" &
  local s11_bg=$!
  local s11_i=0
  while [[ $s11_i -lt 60 ]]; do
    if [[ -f "$s11_hb" ]]; then
      sed -nE 's/.*"generated_at_epoch":([0-9]+).*/\1/p' "$s11_hb" 2>/dev/null >> "$s11_epochs"
    fi
    kill -0 "$s11_bg" 2>/dev/null || break
    sleep 0.25 2>/dev/null || sleep 1
    s11_i=$((s11_i + 1))
  done
  wait "$s11_bg" 2>/dev/null
  if [[ -f "$s11_hb" ]]; then
    sed -nE 's/.*"generated_at_epoch":([0-9]+).*/\1/p' "$s11_hb" 2>/dev/null >> "$s11_epochs"
  fi
  local s11_distinct
  s11_distinct="$(sort -u "$s11_epochs" 2>/dev/null | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$s11_distinct" =~ ^[0-9]+$ ]] || s11_distinct=0
  if [[ -f "$s11_hb" ]]; then
    echo "PASS: S11a heartbeat file present after a bounded (max-iterations=3) daemon run under the REAL guard"; pass=$((pass+1))
  else
    echo "FAIL: S11a expected a heartbeat file after a bounded daemon run" >&2; fail=$((fail+1))
  fi
  if [[ "$s11_distinct" -ge 2 ]]; then
    echo "PASS: S11b >= 2 distinct heartbeat epochs observed across 3 passes (${s11_distinct} distinct) -- proves the daemon actually ticked more than once instead of writing one heartbeat and wedging"; pass=$((pass+1))
  else
    echo "FAIL: S11b expected >= 2 distinct heartbeat writes under the real guard (HR-F1 recursion-wedge regression) -- observed ${s11_distinct} distinct epoch(s): $(tr '\n' ' ' < "$s11_epochs" 2>/dev/null)" >&2; fail=$((fail+1))
  fi
  if grep -q "recursion detected" "$tmp/s11.err" 2>/dev/null; then
    echo "FAIL: S11c sf_guard recursion-skip fired inside run_daemon's own loop (HR-F1 regression -- sf_release is not running between passes): $(cat "$tmp/s11.err" 2>/dev/null)" >&2; fail=$((fail+1))
  else
    echo "PASS: S11c no sf_guard recursion-skip inside run_daemon's own loop across all 3 passes (sf_release runs between them)"; pass=$((pass+1))
  fi

  echo "Scenario 12: --status is human-readable and never errors even with an empty state dir"
  local s12_out s12_rc
  s12_out="$(NL_MAINT_STATE_DIR="$tmp/s12-empty" bash "$self_abs" --status 2>&1)"; s12_rc=$?
  _ok "$s12_rc" 0 "S12 --status exits 0 against a fresh/empty state dir"
  _contains "$s12_out" "nl-maintenance status" "S12 status output is labeled"

  echo "Scenario 13: bash 3.2 floor — no bash-4-only construct outside comments"
  local b4; b4=$(grep -nE '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A|^[[:space:]]*mapfile[[:space:]]|^[[:space:]]*readarray[[:space:]]' "$self_abs" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  if [[ -z "$b4" ]]; then
    echo "PASS: S13 no bash-4-only construct (bash 3.2 floor holds)"; pass=$((pass+1))
  else
    echo "FAIL: S13 bash-4-only construct(s) present: $b4" >&2; fail=$((fail+1))
  fi

  echo ""
  echo "self-test interpreter: ${BASH_VERSION:-unknown}"
  echo "self-test summary: ${pass} passed, ${fail} failed"
  rm -rf "$tmp" 2>/dev/null || true
  [[ "$fail" -eq 0 ]] && exit 0 || exit 1
}

# ============================================================
# Entry point
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) run_self_test ;;
    --tick) run_tick ;;
    --daemon) shift; run_daemon "$@" ;;
    --watchdog) run_watchdog ;;
    --status) run_status ;;
    *)
      echo "usage: nl-maintenance.sh --tick|--daemon [--interval S] [--max-iterations N]|--watchdog|--status|--self-test" >&2
      exit 2
      ;;
  esac
fi
