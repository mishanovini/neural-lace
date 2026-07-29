#!/bin/bash
# perf-tick-snapshot.sh — P2: tick perf snapshot + orphan reap
# (perf-telemetry-2026-07 plan, task P2). Sourced by BOTH
# scripts/supervisor-tick.sh (primary, PERF-ESTATE-PROGRAM-01's named
# home) and scripts/health-tick.sh (fallback — supervisor-tick is
# operator-armed and may be inert on a given machine; health-tick's
# hourly cadence is already armed everywhere), so both ticks get the same
# snapshot line without duplicating the process-enumeration/reap logic.
#
# UNLIKE hooks/lib/perf-ledger.sh (P1), this file does NOT run on the
# per-Bash-call hot path — it fires once per TICK (minutes to hourly).
# Forking (wmic, date, git) is acceptable and used freely here; the
# zero-fork discipline is a P1-only constraint.
#
# ============================================================
# PROCESS ENUMERATION: wmic, not MSYS `ps` (investigated first)
# ============================================================
#
# PROVEN (measured at build time): MSYS `ps -W` reports ParentProcessId=0
# for essentially every process NOT descended from the current MSYS
# session tree — i.e. it cannot see the real parent of a bash.exe/
# claude.exe launched by a DIFFERENT session, which is exactly the case
# this reaper needs to judge. `session-heartbeat-lib.sh` already documents
# this same platform caveat for pid-liveness checks ("checking a native-
# Windows pid this way from an MSYS shell is UNRELIABLE"). `wmic process
# get Name,ProcessId,ParentProcessId,CreationDate` instead queries the
# real Windows kernel process table via WMI and returns the TRUE
# ParentProcessId for every process system-wide, regardless of which
# shell/session spawned it or spawned the shell that spawned it — verified
# by cross-referencing against `wmic ... get CommandLine` for the same
# PIDs. `/format:csv` fixes column order to (alphabetized by wmic, not by
# the order given in `get`): Node,CreationDate,Name,ParentProcessId,
# ProcessId — verified empirically at build time.
#
# ============================================================
# SAFETY CONTRACT — reap is REAL but DEFAULT-SAFE (observe-first)
# ============================================================
#
# Killing the wrong process on this machine IS the exact failure class
# this plan exists to prevent (the 2026-07-23 storm's own "manual kill
# discipline: only provably-orphaned/redundant" — a human being careful).
# So the kill mechanism (taskkill //PID <pid> //F, verified working at
# build time against a disposable process) is REAL and self-tested against
# a REAL disposable process, but is gated OFF by default:
#   PERF_TICK_REAP_ARMED=1   required to actually kill anything.
#   Unarmed (default): every orphan candidate is logged to the tick line
#   with action "would_reap" — visible, auditable, zero risk — mirroring
#   the harness's existing precedent for destructive automation
#   (session-resumer.sh ships fully built but explicitly UNARMED pending a
#   multi-day shadow period; this plan's own Notes section names the
#   43-worktree PURGE decision as "awaiting-operator, NOT agent-
#   actionable"). Arming is an explicit operator env-var choice, not a
#   silent default — decided at build time, documented in the manifest
#   entry's honesty_rationale, and NOT flippable by an agent session
#   without the operator setting the env var themselves.
#
# A candidate is a reap target ONLY when ALL of:
#   1. name is bash.exe or claude.exe
#   2. its ParentProcessId does not appear as a ProcessId anywhere in the
#      SAME snapshot (parent genuinely dead, not a race — one wmic call,
#      one point-in-time view)
#   3. age (now - CreationDate) >= PERF_TICK_ORPHAN_AGE_MIN minutes
#      (default 15 — hooks normally finish in seconds; this is generous
#      headroom against a merely-slow-but-alive hook)
#   4. its PID is NOT the reaper's own $$
#   5. its PID does NOT appear as "pid" in ANY session-heartbeat file
#      (${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}/*.json) —
#      the guard against reaping a live builder's own tracked process,
#      per session-heartbeat-lib.sh's contract.
#
# ============================================================
# LEDGER
# ============================================================
#
# Path: ${PERF_TICK_LEDGER_DIR:-$HOME/.claude/state/perf}/ticks.jsonl (one
# line per tick, no daily rotation per the plan — but SIZE-capped the same
# way supervisor-tick.sh's own tick.log is: >200KB triggers a tail-keep of
# the newest 1000 lines before appending, so it never grows unbounded).
#   {"ts":"...","bash_count":N,"claude_count":N,"worktree_count":N,
#    "defender_cpu_ms":N|null,"degraded":bool,
#    "reaped":[{"pid":N,"cmd_head":"...","age_min":N,"action":
#    "reaped"|"reap_failed"|"would_reap"}]}
# "reaped" is `[]` when no orphan candidates were found this tick (a valid,
# expected, common empty-reap result — not an error).
#
# ============================================================
# ENV OVERRIDES (HARNESS_SELFTEST house convention + CMD-override
# convention, mirrors health-tick.sh's HEALTH_TICK_*_CMD pattern)
# ============================================================
#   PERF_TICK_LEDGER_DIR         ledger dir override
#   PERF_TICK_PROCESS_LIST_CMD   full command line replacing the wmic
#                                 process snapshot (self-test injects
#                                 fixture CSV via this)
#   PERF_TICK_DEFENDER_CMD       full command line replacing the wmic
#                                 MsMpEng CPU-time query
#   PERF_TICK_KILL_CMD_TMPL      kill command template; %PID% is
#                                 substituted (default: taskkill //PID
#                                 %PID% //F). Self-test override lets a
#                                 dry-run-mode scenario prove NO kill
#                                 command ran, without touching real
#                                 processes.
#   PERF_TICK_ORPHAN_AGE_MIN     minutes before a parent-dead process is
#                                 reap-eligible (default 15)
#   PERF_TICK_REAP_ARMED         "1" to actually kill; unarmed otherwise
#                                 (default) — see SAFETY CONTRACT above
#   PERF_TICK_SELF_PID_OVERRIDE  self-test override for "$$" (self-
#                                 exclusion guard)
#   (HEARTBEAT_STATE_DIR inherited from session-heartbeat's own contract)
#
# Self-test: this file's own --self-test AND the extended scenarios in
# supervisor-tick.sh / health-tick.sh's own --self-test suites.

if [[ -n "${_PTS_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_PTS_LIB_LOADED=1

_PTS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/nl-paths.sh
source "$_PTS_SELF_DIR/nl-paths.sh" 2>/dev/null || true

# ---- ledger path (self-test sandboxed) ----------------------------------
pts_ledger_dir() {
  if [[ -n "${PERF_TICK_LEDGER_DIR:-}" ]]; then
    printf '%s' "$PERF_TICK_LEDGER_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/perf-tick-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/perf' "${HOME:-$PWD}"
}

pts_ledger_file() {
  printf '%s/ticks.jsonl' "$(pts_ledger_dir)"
}

_pts_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/ }"
  s="${s//$cr/ }"
  s="${s//$tab/ }"
  printf '%s' "$s"
}

# _pts_wmi_date_to_epoch <wmidatetime> — "20260723000320.118071-420" ->
# epoch seconds (one `date` fork — acceptable, not hot-path). Prints
# empty on any parse failure (caller treats empty as "unknown age").
#
# PORTABILITY (macos-portability-2026-07 M4): the GNU-only `date -d`
# spelling is tried first, then the BSD `date -j -f` equivalent — the
# same two-spelling shape this repo's `_hb_epoch` (session-heartbeat-lib)
# and `_od_epoch` (observability-derive) already use. Kept inline rather
# than sourcing hooks/lib/portable-time.sh because this lib is sourced by
# hooks on a metered path and, like its siblings, is deliberately
# self-contained so it works when shipped alone into a fixture tree.
# Local time on both branches, matching the previous behavior (the WMI
# string's trailing UTC-offset field was ignored before and still is).
_pts_wmi_date_to_epoch() {
  local w="$1"
  [[ "$w" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2}) ]] || { printf ''; return 0; }
  local y="${BASH_REMATCH[1]}" mo="${BASH_REMATCH[2]}" d="${BASH_REMATCH[3]}"
  local h="${BASH_REMATCH[4]}" mi="${BASH_REMATCH[5]}" s="${BASH_REMATCH[6]}"
  date -d "${y}-${mo}-${d} ${h}:${mi}:${s}" +%s 2>/dev/null && return 0
  date -j -f '%Y-%m-%d %H:%M:%S' "${y}-${mo}-${d} ${h}:${mi}:${s}" +%s 2>/dev/null && return 0
  printf ''
}

# ---- process snapshot ----------------------------------------------------
# Sets: PTS_BASH_COUNT, PTS_CLAUDE_COUNT, PTS_DEGRADED (0/1),
#       PTS_PROC_ROWS (array of "pid|ppid|name|created")
PTS_BASH_COUNT=0
PTS_CLAUDE_COUNT=0
PTS_DEGRADED=0
PTS_PROC_ROWS=()
pts_collect_processes() {
  PTS_BASH_COUNT=0
  PTS_CLAUDE_COUNT=0
  PTS_DEGRADED=0
  PTS_PROC_ROWS=()
  # PROVEN at build time (two compounding platform quirks, both fixed
  # here): (1) `wmic ... /format:csv`, when captured, is UTF-16LE
  # (verified via `file` on the raw redirected output) — bash's `$(...)`
  # truncates at the first embedded NUL byte, so an un-decoded capture
  # silently collapses ~300 real rows down to a single garbled "row".
  # `iconv` is unavailable on this Git-Bash install; `tr -d '\000'` strips
  # the NUL bytes (safe — wmic's CSV content is pure ASCII range). (2)
  # EVEN AFTER NUL-stripping, captured output showed DOUBLED `\r` before
  # each `\n` (hex `0d 0d 0a`, verified via `xxd`) — MSYS text-mode I/O
  # re-translating an already-CRLF stream. A single trailing-`\r` strip in
  # the read loop below left ONE residual `\r` glued to the last CSV field
  # (ProcessId), which then failed the `^[0-9]+$` numeric check on EVERY
  # row except the file's last line (which lacks a trailing terminator) —
  # this is EXACTLY the bug that silently collapsed the array to a single
  # element while iteration counts looked correct. `tr -d '\r'` here
  # removes every CR at the source, and the loop below also strips any
  # that survive (belt-and-suspenders, matches the CommandLine lookup's
  # own `tr -d '\000\r'` below).
  local cmd="${PERF_TICK_PROCESS_LIST_CMD:-wmic process get Name,ProcessId,ParentProcessId,CreationDate /format:csv | tr -d '\\000\\r'}"
  local out
  out="$(bash -c "$cmd" 2>/dev/null)"
  if [[ -z "$out" ]]; then
    PTS_DEGRADED=1
    return 0
  fi
  local line pid ppid name created node
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    [[ -z "$line" ]] && continue
    [[ "$line" == Node,* ]] && continue
    IFS=',' read -r node created name ppid pid <<< "$line"
    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && continue
    PTS_PROC_ROWS+=("${pid}|${ppid}|${name}|${created}")
    case "$name" in
      bash.exe) PTS_BASH_COUNT=$((PTS_BASH_COUNT + 1)) ;;
      claude.exe) PTS_CLAUDE_COUNT=$((PTS_CLAUDE_COUNT + 1)) ;;
    esac
  done <<< "$out"
  [[ "${#PTS_PROC_ROWS[@]}" -eq 0 ]] && PTS_DEGRADED=1
  # Explicit — bash functions otherwise return the LAST command's exit
  # status, and `[[ ... ]] && x` is FALSE (rc=1) on the common/healthy
  # case above (a non-empty snapshot) despite nothing having failed. A
  # caller doing `pts_collect_processes && next_thing` would silently skip
  # next_thing on every normal run — caught live at build time.
  return 0
}

# ---- worktree count -------------------------------------------------------
# Sets PTS_WORKTREE_COUNT (raw `git worktree list` line count across the
# resolved repo — includes the main checkout row, matching "worktree
# count" read literally).
PTS_WORKTREE_COUNT=0
pts_collect_worktree_count() {
  PTS_WORKTREE_COUNT=0
  if [[ -n "${PERF_TICK_WORKTREE_COUNT_OVERRIDE:-}" ]]; then
    PTS_WORKTREE_COUNT="$PERF_TICK_WORKTREE_COUNT_OVERRIDE"
    return 0
  fi
  local repo=""
  if declare -F nl_repo_root >/dev/null 2>&1; then
    repo="$(nl_repo_root)"
  fi
  [[ -z "$repo" ]] && repo="$PWD"
  [[ -d "$repo" ]] || return 0
  local n
  n="$(git -C "$repo" worktree list 2>/dev/null | grep -c . || true)"
  [[ "$n" =~ ^[0-9]+$ ]] && PTS_WORKTREE_COUNT="$n"
  return 0
}

# ---- Defender CPU (best-effort; degrades honestly) ------------------------
# Sets PTS_DEFENDER_CPU_MS (cumulative CPU-ms since MsMpEng started — a
# monotonic total, NOT an instantaneous %; documented as such in the
# ledger's schema comment above) and PTS_DEFENDER_DEGRADED (0/1).
PTS_DEFENDER_CPU_MS=""
PTS_DEFENDER_DEGRADED=0
pts_collect_defender_cpu() {
  PTS_DEFENDER_CPU_MS=""
  PTS_DEFENDER_DEGRADED=0
  # Same UTF-16LE decode + doubled-CR fix as pts_collect_processes above.
  local cmd="${PERF_TICK_DEFENDER_CMD:-wmic process where \"name like '%MsMpEng%'\" get UserModeTime,KernelModeTime /format:csv | tr -d '\\000\\r'}"
  local out
  out="$(bash -c "$cmd" 2>/dev/null)"
  # Expected CSV (alphabetized): Node,KernelModeTime,Name,ProcessId,UserModeTime
  # (this query has no Name/ProcessId in `get`, so actual cols are just
  # Node,KernelModeTime,UserModeTime — verified empirically at build time).
  local dataline
  dataline="$(printf '%s\n' "$out" | grep -v '^Node,' | grep -v '^\s*$' | head -1)"
  if [[ -z "$dataline" ]]; then
    PTS_DEFENDER_DEGRADED=1
    return 0
  fi
  local node kmt umt
  dataline="${dataline//$'\r'/}"
  IFS=',' read -r node kmt umt <<< "$dataline"
  if [[ "$kmt" =~ ^[0-9]+$ && "$umt" =~ ^[0-9]+$ ]]; then
    # 100ns units -> ms
    PTS_DEFENDER_CPU_MS=$(( (kmt + umt) / 10000 ))
  else
    PTS_DEFENDER_DEGRADED=1
  fi
}

# ---- heartbeat pid guard --------------------------------------------------
# _pts_heartbeat_pids — echoes every "pid" value found across the
# heartbeat state dir's *.json files, one per line (best-effort, no jq
# hard dependency — sed field-extraction, same convention supervisor-
# tick.sh's own _st_field uses).
_pts_heartbeat_pids() {
  local dir="${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}"
  [[ -d "$dir" ]] || return 0
  local f
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    sed -nE 's/.*"pid"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$f" 2>/dev/null
  done
  return 0
}

# ---- orphan detection + reap ----------------------------------------------
# Populates PTS_REAP_RESULTS (array of "pid|cmd_head|age_min|action").
# Requires pts_collect_processes to have already run (uses PTS_PROC_ROWS).
PTS_REAP_RESULTS=()
pts_reap_orphans() {
  PTS_REAP_RESULTS=()
  [[ "${#PTS_PROC_ROWS[@]}" -eq 0 ]] && return 0

  local self_pid="${PERF_TICK_SELF_PID_OVERRIDE:-$$}"
  local age_threshold_min="${PERF_TICK_ORPHAN_AGE_MIN:-15}"
  local armed="${PERF_TICK_REAP_ARMED:-0}"
  local kill_tmpl="${PERF_TICK_KILL_CMD_TMPL:-taskkill //PID %PID% //F}"

  # Build the live-PID set from THIS SAME snapshot (one point-in-time
  # view — no race between "list processes" and "check parent exists").
  local -A live_pids=()
  local row pid ppid name created
  for row in "${PTS_PROC_ROWS[@]}"; do
    IFS='|' read -r pid ppid name created <<< "$row"
    live_pids["$pid"]=1
  done

  local hb_pids
  hb_pids="$(_pts_heartbeat_pids)"

  local now_epoch
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"

  for row in "${PTS_PROC_ROWS[@]}"; do
    IFS='|' read -r pid ppid name created <<< "$row"
    case "$name" in
      bash.exe|claude.exe) : ;;
      *) continue ;;
    esac
    [[ "$pid" == "$self_pid" ]] && continue
    [[ -n "${live_pids[$ppid]:-}" ]] && continue   # parent alive -> not orphaned

    local created_epoch age_min
    created_epoch="$(_pts_wmi_date_to_epoch "$created")"
    if [[ -z "$created_epoch" ]]; then
      age_min=0
    else
      age_min=$(( (now_epoch - created_epoch) / 60 ))
    fi
    (( age_min < age_threshold_min )) && continue   # too young — still working

    # Heartbeat guard: never reap a PID any session's heartbeat tracks.
    if printf '%s\n' "$hb_pids" | grep -qx "$pid"; then
      continue
    fi

    # cmd-head: a targeted, single-process lookup (kept out of the bulk
    # snapshot query above to avoid CSV-comma-escaping risk in
    # CommandLine values across ~300 processes every tick).
    local cmd_head=""
    if [[ -z "${PERF_TICK_SKIP_CMDLINE_LOOKUP:-}" ]]; then
      local cl_out
      cl_out="$(wmic process where "ProcessId=${pid}" get CommandLine /format:list 2>/dev/null | tr -d '\000\r')"
      cmd_head="$(printf '%s\n' "$cl_out" | sed -n 's/^CommandLine=//p' | head -c 120)"
    fi
    [[ -z "$cmd_head" ]] && cmd_head="(${name})"

    local action
    if [[ "$armed" == "1" ]]; then
      local kill_cmd="${kill_tmpl//%PID%/$pid}"
      if bash -c "$kill_cmd" >/dev/null 2>&1; then
        action="reaped"
      else
        action="reap_failed"
      fi
    else
      action="would_reap"
    fi

    PTS_REAP_RESULTS+=("${pid}|$(_pts_json_escape "$cmd_head")|${age_min}|${action}")
  done
  return 0
}

# ---- ledger write ----------------------------------------------------------
# pts_append_tick_line — writes one JSONL line from the globals populated
# by pts_collect_processes / pts_collect_worktree_count /
# pts_collect_defender_cpu / pts_reap_orphans. Size-capped (tail-keep
# newest 1000 lines past ~200KB, same house pattern as supervisor-tick's
# own tick.log rotation). Returns the ledger file path on stdout.
pts_append_tick_line() {
  local dir file
  dir="$(pts_ledger_dir)"
  mkdir -p "$dir" 2>/dev/null || true
  file="$(pts_ledger_file)"

  if [[ -f "$file" ]] && [[ "$(wc -c < "$file" 2>/dev/null || echo 0)" -gt 200000 ]]; then
    tail -n 1000 "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null
  fi

  local ts=""
  printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1 2>/dev/null || ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"

  local defender_field="null"
  [[ -n "${PTS_DEFENDER_CPU_MS:-}" ]] && defender_field="$PTS_DEFENDER_CPU_MS"
  local degraded_bool="false"
  { [[ "${PTS_DEGRADED:-0}" == "1" ]] || [[ "${PTS_DEFENDER_DEGRADED:-0}" == "1" ]]; } && degraded_bool="true"

  local reaped_json="" r first=1 rpid rcmd rage raction
  for r in "${PTS_REAP_RESULTS[@]:-}"; do
    [[ -z "$r" ]] && continue
    IFS='|' read -r rpid rcmd rage raction <<< "$r"
    if [[ "$first" == "1" ]]; then first=0; else reaped_json+=","; fi
    reaped_json+="$(printf '{"pid":%s,"cmd_head":"%s","age_min":%s,"action":"%s"}' "$rpid" "$rcmd" "$rage" "$raction")"
  done

  printf '{"ts":"%s","bash_count":%d,"claude_count":%d,"worktree_count":%d,"defender_cpu_ms":%s,"degraded":%s,"reaped":[%s]}\n' \
    "$(_pts_json_escape "$ts")" "${PTS_BASH_COUNT:-0}" "${PTS_CLAUDE_COUNT:-0}" "${PTS_WORKTREE_COUNT:-0}" \
    "$defender_field" "$degraded_bool" "$reaped_json" \
    >> "$file" 2>/dev/null || true

  printf '%s' "$file"
}

# pts_run_tick — convenience one-call entry point: collect everything,
# reap, write the line. Prints the ledger file path (empty on total
# failure — never errors the caller).
pts_run_tick() {
  pts_collect_processes
  pts_collect_worktree_count
  pts_collect_defender_cpu
  pts_reap_orphans
  pts_append_tick_line
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--self-test" ]]; then
  _PTS_PASSED=0
  _PTS_FAILED=0
  _pts_pass() { _PTS_PASSED=$((_PTS_PASSED + 1)); echo "  PASS: $1"; }
  _pts_fail() { _PTS_FAILED=$((_PTS_FAILED + 1)); echo "  FAIL: $1" >&2; }

  _PTS_T="$(mktemp -d 2>/dev/null || mktemp -d -t ptstst)"
  export PERF_TICK_LEDGER_DIR="$_PTS_T/perf"
  export PERF_TICK_SKIP_CMDLINE_LOOKUP=1

  # Timestamps relative to "now" so the fixture is deterministic regardless
  # of when the self-test runs (avoids hardcoding a date that ages out).
  # Portable relative timestamps (macos-portability M4). GNU-only
  # `date -d '-30 minutes'` produced EMPTY strings on macOS, which then
  # flowed into the WMI-datetime fixtures below as unparseable garbage.
  _pts_old_ts="$(date -d '-30 minutes' +%Y%m%d%H%M%S 2>/dev/null \
                 || date -v-30M +%Y%m%d%H%M%S 2>/dev/null)"
  _pts_young_ts="$(date -d '-2 minutes' +%Y%m%d%H%M%S 2>/dev/null \
                 || date -v-2M +%Y%m%d%H%M%S 2>/dev/null)"
  if [[ -z "$_pts_old_ts" || -z "$_pts_young_ts" ]]; then
    echo "  FAIL: could not build relative fixture timestamps on this platform" >&2
    return 1
  fi

  echo "Scenario 0: CRLF-doubling regression — caught live at build time against REAL wmic output"
  # PROVEN bug (build-time, via `xxd`): captured `wmic ... /format:csv`
  # output, even after NUL-stripping, showed hex `0d 0d 0a` — a DOUBLED
  # \r before every \n (MSYS text-mode I/O re-translating an already-CRLF
  # stream). A single trailing-\r strip (`${line%$'\r'}`) left ONE
  # residual \r glued to the last CSV field (ProcessId), failing the
  # `^[0-9]+$` check on every row EXCEPT the file's last line — silently
  # collapsing a real ~300-row snapshot down to bash_count=0/claude_count=0
  # while looking like it succeeded (degraded=0, no error). This fixture
  # reproduces the EXACT byte pattern (printf '\r\r\n' — two CRs) so a
  # regression here fails loudly instead of silently under-counting.
  {
    printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\r\r\n'
    printf 'OFFICE_PC,20260101000000.000000-420,bash.exe,1,100\r\r\n'
    printf 'OFFICE_PC,20260101000000.000000-420,bash.exe,1,101\r\r\n'
    printf 'OFFICE_PC,20260101000000.000000-420,claude.exe,1,200\r\r\n'
  } > "$_PTS_T/fixture-crlf-doubled.csv"
  export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-crlf-doubled.csv'"
  pts_collect_processes
  if [[ "$PTS_BASH_COUNT" == "2" && "$PTS_CLAUDE_COUNT" == "1" ]]; then
    _pts_pass "doubled-CRLF fixture (real wmic byte pattern) still parses to bash_count=2 claude_count=1 (not 0/0)"
  else
    _pts_fail "CRLF-doubling regression: expected bash_count=2 claude_count=1, got bash=$PTS_BASH_COUNT claude=$PTS_CLAUDE_COUNT (total rows: ${#PTS_PROC_ROWS[@]})"
  fi
  if [[ "${#PTS_PROC_ROWS[@]}" == "3" ]]; then
    _pts_pass "all 3 data rows survived the doubled-CRLF fixture (not collapsed to 1)"
  else
    _pts_fail "expected 3 rows, got ${#PTS_PROC_ROWS[@]}"
  fi

  echo "Scenario 1: process snapshot counts (fixture CSV, no real wmic call)"
  {
    printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\n'
    printf 'OFFICE_PC,%s.000000-420,bash.exe,1,100\n' "$_pts_old_ts"
    printf 'OFFICE_PC,%s.000000-420,bash.exe,1,101\n' "$_pts_old_ts"
    printf 'OFFICE_PC,%s.000000-420,bash.exe,1,102\n' "$_pts_old_ts"
    printf 'OFFICE_PC,%s.000000-420,claude.exe,1,200\n' "$_pts_old_ts"
    printf 'OFFICE_PC,%s.000000-420,node.exe,1,300\n' "$_pts_old_ts"
  } > "$_PTS_T/fixture-basic.csv"
  export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-basic.csv'"
  pts_collect_processes
  [[ "$PTS_BASH_COUNT" == "3" ]] && _pts_pass "bash_count=3 from fixture" || _pts_fail "expected bash_count=3, got $PTS_BASH_COUNT"
  [[ "$PTS_CLAUDE_COUNT" == "1" ]] && _pts_pass "claude_count=1 from fixture" || _pts_fail "expected claude_count=1, got $PTS_CLAUDE_COUNT"
  [[ "$PTS_DEGRADED" == "0" ]] && _pts_pass "not degraded when the process-list command succeeds" || _pts_fail "unexpectedly degraded"

  echo "Scenario 2: process snapshot degrades honestly when the command fails/is empty"
  export PERF_TICK_PROCESS_LIST_CMD="true"   # succeeds, prints nothing
  pts_collect_processes
  [[ "$PTS_DEGRADED" == "1" ]] && _pts_pass "degraded:1 when the process list comes back empty" || _pts_fail "expected degraded=1"

  echo "Scenario 2b: return-code regression — pts_collect_processes must return 0 on the COMMON (non-empty, healthy) case, not the bash-default 'last command's status'"
  # Caught live at build time: bash functions return the exit status of
  # their LAST executed command unless it ends in an explicit `return`.
  # The last line here used to be `[[ ... -eq 0 ]] && PTS_DEGRADED=1`,
  # which is FALSE (rc=1) precisely when the snapshot is healthy and
  # non-empty — the common case — silently breaking any
  # `pts_collect_processes && next_thing` caller on every normal run.
  export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-basic.csv'"
  _pts_chain_ran=0
  pts_collect_processes && _pts_chain_ran=1
  [[ "$_pts_chain_ran" == "1" ]] && _pts_pass "pts_collect_processes returns 0 on a healthy non-empty snapshot (safe to && -chain)" \
    || _pts_fail "pts_collect_processes returned nonzero on a healthy snapshot — && -chained callers would silently skip"

  echo "Scenario 3: Defender CPU parses a fixture CSV; degrades honestly when absent"
  {
    printf 'Node,KernelModeTime,UserModeTime\n'
    printf 'OFFICE_PC,41020000000,210419062500\n'
  } > "$_PTS_T/fixture-defender.csv"
  export PERF_TICK_DEFENDER_CMD="cat '$_PTS_T/fixture-defender.csv'"
  pts_collect_defender_cpu
  # (41020000000 + 210419062500) / 10000 = 25143906 (integer division)
  if [[ "$PTS_DEFENDER_CPU_MS" == "25143906" && "$PTS_DEFENDER_DEGRADED" == "0" ]]; then
    _pts_pass "defender_cpu_ms computed from fixture KernelModeTime+UserModeTime (100ns units -> ms)"
  else
    _pts_fail "expected defender_cpu_ms=25143906 degraded=0, got ms=$PTS_DEFENDER_CPU_MS degraded=$PTS_DEFENDER_DEGRADED"
  fi
  export PERF_TICK_DEFENDER_CMD="true"
  pts_collect_defender_cpu
  [[ -z "$PTS_DEFENDER_CPU_MS" && "$PTS_DEFENDER_DEGRADED" == "1" ]] \
    && _pts_pass "defender_cpu_ms null + degraded:1 when MsMpEng is unreadable" \
    || _pts_fail "expected null+degraded on missing Defender data, got ms='$PTS_DEFENDER_CPU_MS' degraded=$PTS_DEFENDER_DEGRADED"

  echo "Scenario 4: worktree count override (real git worktree list path exercised separately by supervisor-tick/health-tick self-tests)"
  export PERF_TICK_WORKTREE_COUNT_OVERRIDE=7
  pts_collect_worktree_count
  [[ "$PTS_WORKTREE_COUNT" == "7" ]] && _pts_pass "worktree_count honors override" || _pts_fail "expected 7, got $PTS_WORKTREE_COUNT"
  unset PERF_TICK_WORKTREE_COUNT_OVERRIDE

  echo "Scenario 5: orphan reap guard logic — parent-dead+old -> candidate; parent-alive -> never; parent-dead+young -> never (still working)"
  {
    printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\n'
    printf 'OFFICE_PC,%s.000000-420,bash.exe,999999,900\n' "$_pts_old_ts"    # orphan: dead parent, old
    printf 'OFFICE_PC,%s.000000-420,bash.exe,999998,901\n' "$_pts_young_ts"  # too young -- skip
    printf 'OFFICE_PC,%s.000000-420,bash.exe,950,902\n' "$_pts_old_ts"      # parent alive -- skip
    printf 'OFFICE_PC,%s.000000-420,bash.exe,1,950\n' "$_pts_old_ts"        # the "alive parent" for 902
  } > "$_PTS_T/fixture-orphans.csv"
  export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-orphans.csv'"
  export PERF_TICK_SELF_PID_OVERRIDE=999999999
  pts_collect_processes
  pts_reap_orphans
  _pts_found_900=0; _pts_found_901=0; _pts_found_902=0
  for _pts_r in "${PTS_REAP_RESULTS[@]}"; do
    case "$_pts_r" in
      900\|*) _pts_found_900=1 ;;
      901\|*) _pts_found_901=1 ;;
      902\|*) _pts_found_902=1 ;;
    esac
  done
  [[ "$_pts_found_900" == "1" ]] && _pts_pass "old parent-dead pid 900 -> reap candidate" || _pts_fail "pid 900 should be a candidate (results: ${PTS_REAP_RESULTS[*]})"
  [[ "$_pts_found_901" == "0" ]] && _pts_pass "young parent-dead pid 901 -> NOT a candidate (still working)" || _pts_fail "pid 901 should NOT be a candidate"
  [[ "$_pts_found_902" == "0" ]] && _pts_pass "old parent-ALIVE pid 902 -> NOT a candidate" || _pts_fail "pid 902 should NOT be a candidate (parent 950 is alive)"

  echo "Scenario 6: heartbeat guard — a candidate whose pid matches a live heartbeat file is NEVER reaped"
  _PTS_HB_DIR="$_PTS_T/heartbeats"
  mkdir -p "$_PTS_HB_DIR"
  printf '{"schema":1,"session_id":"sess-x","pid":900,"cwd":"/x"}\n' > "$_PTS_HB_DIR/sess-x.json"
  export HEARTBEAT_STATE_DIR="$_PTS_HB_DIR"
  pts_reap_orphans
  _pts_found_900_guarded=0
  for _pts_r in "${PTS_REAP_RESULTS[@]}"; do
    case "$_pts_r" in
      900\|*) _pts_found_900_guarded=1 ;;
    esac
  done
  [[ "$_pts_found_900_guarded" == "0" ]] && _pts_pass "pid 900 excluded once a heartbeat file claims it (guard against reaping a live builder)" \
    || _pts_fail "pid 900 should have been excluded by the heartbeat guard"
  unset HEARTBEAT_STATE_DIR

  echo "Scenario 7: self-exclusion — the reaper never targets its own pid even if it looks orphan-shaped"
  export PERF_TICK_SELF_PID_OVERRIDE=900
  pts_reap_orphans
  _pts_found_900_self=0
  for _pts_r in "${PTS_REAP_RESULTS[@]}"; do
    case "$_pts_r" in
      900\|*) _pts_found_900_self=1 ;;
    esac
  done
  [[ "$_pts_found_900_self" == "0" ]] && _pts_pass "self pid (900) never targeted" || _pts_fail "self-exclusion failed"
  export PERF_TICK_SELF_PID_OVERRIDE=999999999

  echo "Scenario 8: DEFAULT (unarmed) mode never kills — logs would_reap only"
  unset PERF_TICK_REAP_ARMED
  _PTS_KILL_MARKER="$_PTS_T/kill-was-called"
  rm -f "$_PTS_KILL_MARKER"
  export PERF_TICK_KILL_CMD_TMPL="touch '$_PTS_KILL_MARKER'"
  pts_reap_orphans
  _pts_action_900=""
  for _pts_r in "${PTS_REAP_RESULTS[@]}"; do
    case "$_pts_r" in
      900\|*) _pts_action_900="$_pts_r" ;;
    esac
  done
  if [[ "$_pts_action_900" == *"would_reap"* ]]; then
    _pts_pass "unarmed mode logs action=would_reap for pid 900"
  else
    _pts_fail "expected would_reap action for pid 900, got: $_pts_action_900"
  fi
  if [[ ! -f "$_PTS_KILL_MARKER" ]]; then
    _pts_pass "unarmed mode never invoked the kill command (marker file absent)"
  else
    _pts_fail "unarmed mode invoked the kill command — SAFETY VIOLATION"
  fi

  echo "Scenario 9: ARMED mode kills a REAL disposable process (proves the mechanism, not just the guard)"
  # Spawn a real short-lived background process, then feed the reaper a
  # fixture snapshot where THAT process's REAL WINDOWS pid looks orphaned
  # (dead fake parent, backdated old enough). Confirm it is actually gone
  # after. NOTE: MSYS's own `$!` is a VIRTUAL pid in bash's private pid
  # table, NOT the real win32 pid taskkill/wmic operate on (MEASURED at
  # build time: `wmic process where "ProcessId=$!"` -> "No Instance(s)
  # Available" for a job MSYS itself confirms is alive via `kill -0`) —
  # exactly the platform gap session-heartbeat-lib.sh already documents
  # for pid-liveness checks. `ps -W` exposes the real win32 pid as its
  # WINPID column; resolve through that, matching how the PRODUCTION path
  # already works (pts_collect_processes sources pids from wmic directly,
  # so this mismatch does not exist there — it is a self-test-harness-only
  # concern for spawning a REAL disposable target).
  bash -c 'sleep 20' &
  _pts_msys_pid=$!
  _pts_real_pid="$(ps -W 2>/dev/null | awk -v p="$_pts_msys_pid" '$1==p{print $4}')"
  if [[ -n "$_pts_real_pid" ]] && kill -0 "$_pts_msys_pid" 2>/dev/null; then
    {
      printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\n'
      printf 'OFFICE_PC,%s.000000-420,bash.exe,999999,%s\n' "$_pts_old_ts" "$_pts_real_pid"
    } > "$_PTS_T/fixture-armed.csv"
    export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-armed.csv'"
    export PERF_TICK_REAP_ARMED=1
    export PERF_TICK_KILL_CMD_TMPL="taskkill //PID %PID% //F"
    export PERF_TICK_SELF_PID_OVERRIDE=999999999
    pts_collect_processes
    pts_reap_orphans
    sleep 1
    if wmic process where "ProcessId=${_pts_real_pid}" get ProcessId /format:csv 2>/dev/null | grep -q "$_pts_real_pid"; then
      _pts_fail "real disposable process (winpid $_pts_real_pid) is STILL ALIVE after armed reap — kill mechanism did not work"
    else
      _pts_pass "real disposable process (winpid $_pts_real_pid) was actually terminated by armed reap (taskkill //PID //F)"
    fi
    _pts_armed_action=""
    for _pts_r in "${PTS_REAP_RESULTS[@]}"; do
      case "$_pts_r" in
        "$_pts_real_pid"\|*) _pts_armed_action="$_pts_r" ;;
      esac
    done
    if [[ "$_pts_armed_action" == *"|reaped"* ]]; then
      _pts_pass "armed mode logs action=reaped for the real killed pid"
    else
      _pts_fail "expected action=reaped, got: $_pts_armed_action"
    fi
    unset PERF_TICK_REAP_ARMED
    wait "$_pts_msys_pid" 2>/dev/null
  else
    _pts_fail "could not resolve a real WINPID for the disposable test process before the armed-reap scenario (msys_pid=$_pts_msys_pid winpid=$_pts_real_pid)"
  fi

  echo "Scenario 10: empty-reap is a valid result (no candidates found -> reaped:[] in the ledger line, not an error)"
  {
    printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\n'
    printf 'OFFICE_PC,%s.000000-420,bash.exe,1,700\n' "$_pts_old_ts"
    printf 'OFFICE_PC,%s.000000-420,node.exe,0,1\n' "$_pts_old_ts"
  } > "$_PTS_T/fixture-empty.csv"
  export PERF_TICK_PROCESS_LIST_CMD="cat '$_PTS_T/fixture-empty.csv'"
  export PERF_TICK_WORKTREE_COUNT_OVERRIDE=1
  export PERF_TICK_DEFENDER_CMD="true"
  pts_collect_processes
  pts_collect_worktree_count
  pts_collect_defender_cpu
  pts_reap_orphans
  _pts_ledger_file="$(pts_append_tick_line)"
  if [[ -f "$_pts_ledger_file" ]] && grep -q '"reaped":\[\]' "$_pts_ledger_file"; then
    _pts_pass "ledger line schema: empty reap is [] (not an error, not omitted)"
  else
    _pts_fail "expected a ledger line with reaped:[]; file=$_pts_ledger_file content=$(cat "$_pts_ledger_file" 2>/dev/null)"
  fi
  if [[ -f "$_pts_ledger_file" ]] && grep -qE '"bash_count":1,"claude_count":0,"worktree_count":1,"defender_cpu_ms":null,"degraded":true' "$_pts_ledger_file"; then
    _pts_pass "ledger line carries bash_count/claude_count/worktree_count/defender_cpu_ms/degraded correctly"
  else
    _pts_fail "ledger line fields mismatch: $(cat "$_pts_ledger_file" 2>/dev/null)"
  fi

  rm -rf "$_PTS_T" 2>/dev/null || true
  unset PERF_TICK_LEDGER_DIR PERF_TICK_PROCESS_LIST_CMD PERF_TICK_DEFENDER_CMD PERF_TICK_SKIP_CMDLINE_LOOKUP
  unset PERF_TICK_SELF_PID_OVERRIDE PERF_TICK_KILL_CMD_TMPL PERF_TICK_WORKTREE_COUNT_OVERRIDE

  echo ""
  echo "self-test summary: ${_PTS_PASSED} passed, ${_PTS_FAILED} failed"
  if [[ "$_PTS_FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
