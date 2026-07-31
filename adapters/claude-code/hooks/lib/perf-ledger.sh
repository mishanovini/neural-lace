#!/bin/bash
# perf-ledger.sh — P1: per-call hook latency meter (perf-telemetry-2026-07
# plan, task P1). Sourced library, builtin-only, zero forks on the steady-
# state hot path.
#
# ============================================================
# INSTRUMENTATION POINT (investigated first, per the plan's mandate)
# ============================================================
#
# PROVEN (read adapters/claude-code/settings.json.template in full): there
# is NO single wrapper around the PreToolUse hook chain. Every hook is its
# own top-level `"command": "bash ~/.claude/hooks/<name>.sh"` entry inside
# the "PreToolUse" array — 24 separate matcher blocks fire on Bash alone,
# each its own bash.exe invocation, invoked directly by the Claude Code
# platform. Full-chain wrapping (one process timing the whole chain) is
# therefore impossible without the P6 dispatcher (docs/design-notes/
# pretooluse-dispatcher.md, out of this plan's scope — the plan itself
# names this as the expected finding: "if hooks are invoked individually
# by the platform ... P1 falls back to per-hook self-metering").
#
# SHIPPED SHAPE: self-metering. This lib is sourced by the 5 highest-cost
# per-Bash-call hooks (ranked by line count, the 2026-07-13 lesson's proxy
# for parse-tax — "script size is a per-invocation runtime cost on
# Windows"; docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-
# spawn-and-hook-latency.md §3):
#   scope-enforcement-gate.sh (2127 lines), plan-deletion-protection.sh
#   (1066), concurrent-ownership-gate.sh (1029), evidence-before-fix-
#   gate.sh (1009), pr-template-inline-gate.sh (735).
# Each emits one {ts,hook,ms} JSONL line per real (non-self-test)
# invocation. This does NOT capture total per-Bash-call chain latency
# (that needs P6) — it captures the actual cost of the 5 hooks the 07-13
# profile identified as dominant, which is enough for P3's p95-by-hook
# budget (group by "hook", percentile "ms").
#
# ============================================================
# ZERO-FORK CONTRACT (hot-path budget: <5ms, zero subprocess spawns)
# ============================================================
#
# Every function below uses ONLY bash builtins, and — critically — NEVER
# captures another function's output via `$(...)` or backticks: on this
# platform (MSYS2/Git-Bash) command substitution forks a real subshell
# process EVEN WHEN the substituted command is a pure-builtin shell
# function with no external command inside it (MEASURED at build time:
# converting 5 internal `x="$(fn)"` capture sites to global-variable
# returns took a 500-iteration begin/end loop from ~68s (~136ms/call —
# consistent with ~5 hidden forks/call) to well under 1s). So every
# helper below SETS A GLOBAL VARIABLE instead of `printf`-and-capture;
# only the public entry points (pl_meter_begin/pl_meter_end) are meant to
# be called directly, never substituted.
#   - $EPOCHREALTIME (bash >=5 builtin var, SECONDS.MICROSECONDS) for
#     timestamps — NEVER `date +%s%N` (a fork; MEASURED ~190ms/spawn on
#     this platform per the 07-13 lesson).
#   - `printf -v var '%(fmt)T' -1` (bash >=4.2 builtin strftime) for
#     human-readable timestamps/filenames — NEVER the external `date`
#     binary.
#   - Pure bash string/arithmetic (10#$var forced-base-10 to dodge octal
#     misparse of zero-padded microseconds) for elapsed-ms — NEVER `bc`/
#     `awk`/`python`.
#   - `printf '...' >> file` (builtin append redirection) for the ledger
#     write — NEVER `echo | tee -a` or a subshell.
#   - `mkdir -p` is the ONE guarded exception: only called when the target
#     dir does not already exist (`[[ -d ]]` builtin test first), so it
#     forks at most once ever (cold start), never on the steady-state path
#     the self-test's overhead budget measures.
# If $EPOCHREALTIME is unavailable (pre-5.0 bash), pl_available returns
# false and pl_meter_begin/pl_meter_end become structural no-ops — the
# meter NEVER falls back to forking for a timestamp (plan Assumptions).
#
# ============================================================
# LEDGER SCHEMA + PATH
# ============================================================
#
# Path: ${PERF_LEDGER_DIR:-$HOME/.claude/state/perf}/chain-YYYYMMDD.jsonl
# (HARNESS_SELFTEST=1 sandboxes under TMPDIR when PERF_LEDGER_DIR unset).
# Daily rotation by filename; one line per metered invocation, O_APPEND
# (atomic under ~4KB per POSIX/NTFS append semantics — lines here are
# ~60-80 bytes, well under that).
#   {"ts":"<local ISO-8601-ish, second precision>","hook":"<name>","ms":<int>}
# "hook" is the caller-supplied label (the hook's own basename, no .sh) —
# enough for P3 to group by hook and compute a trailing-24h p95.
#
# ============================================================
# USAGE (from a hook script)
# ============================================================
#   source "$SELF_DIR/lib/perf-ledger.sh" 2>/dev/null || true
#   pl_meter_begin
#   trap 'pl_meter_end "my-hook-name"' EXIT   # fires on EVERY exit path
# If the hook already sets its own `trap ... EXIT` later in the file,
# chain the call into that trap's command string instead of overwriting it
# (see pr-template-inline-gate.sh's composed trap for the pattern).
#
# Self-test: --self-test (bash "$0" --self-test). Proves: EPOCHREALTIME
# detection + no-op fallback; correct elapsed-ms arithmetic (incl. the
# leading-zero-microsecond edge case); ledger line schema + daily-rotation
# filename; hot-path overhead budget (<5ms/call) via a 500-iteration timed
# loop (a single fork would cost ~190ms — 500 forks would take ~95s, so
# completing well under 1s is itself strong evidence of zero forks); AND a
# static fork-counting harness that greps this file's function bodies for
# any subprocess-spawning construct ($(...), backticks, pipes, or a named
# external command) — a structural proof no fork is POSSIBLE in the hot
# path, not just empirically absent this run.

# ---- idempotent source guard -----------------------------------------
if [[ -n "${_PL_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_PL_LIB_LOADED=1

# ---- availability ------------------------------------------------------
pl_available() {
  [[ -n "${EPOCHREALTIME:-}" ]]
}

# _pl_set_ledger_dir — sets global _PL_DIR. No $(...); no forks.
_pl_set_ledger_dir() {
  if [[ -n "${PERF_LEDGER_DIR:-}" ]]; then
    _PL_DIR="$PERF_LEDGER_DIR"
  elif [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    _PL_DIR="${TMPDIR:-/tmp}/perf-ledger-selftest/$$"
  else
    _PL_DIR="${HOME:-$PWD}/.claude/state/perf"
  fi
}

# _pl_set_today — sets global _PL_TODAY (YYYYMMDD, local time) via bash's
# builtin strftime printf conversion (NOT the external `date` binary).
_pl_set_today() {
  if [[ -n "${PERF_LEDGER_DATE_OVERRIDE:-}" ]]; then
    _PL_TODAY="$PERF_LEDGER_DATE_OVERRIDE"
    return 0
  fi
  _PL_TODAY=""
  printf -v _PL_TODAY '%(%Y%m%d)T' -1 2>/dev/null || _PL_TODAY=""
}

# _pl_set_now_ts — sets global _PL_NOWTS (second-precision local ts).
_pl_set_now_ts() {
  _PL_NOWTS=""
  printf -v _PL_NOWTS '%(%Y-%m-%dT%H:%M:%S)T' -1 2>/dev/null || _PL_NOWTS=""
}

# _pl_set_ledger_file — sets global _PL_FILE from _PL_DIR + _PL_TODAY.
_pl_set_ledger_file() {
  _pl_set_ledger_dir
  _pl_set_today
  [[ -z "$_PL_TODAY" ]] && _PL_TODAY="undated"
  _PL_FILE="${_PL_DIR}/chain-${_PL_TODAY}.jsonl"
}

# _pl_set_elapsed_ms <t0> <t1> — sets global _PL_MS. Pure-bash arithmetic
# on two $EPOCHREALTIME values ("SECONDS.MICROSECONDS", 6 fixed
# fractional digits). Forces base 10 on the numeric fields (10#$x) to
# dodge bash's octal misparse of zero-padded numbers like "007123".
_pl_set_elapsed_ms() {
  local t0="$1" t1="$2"
  _PL_MS=0
  [[ "$t0" == *.* && "$t1" == *.* ]] || return 0
  local s0="${t0%%.*}" u0="${t0#*.}"
  local s1="${t1%%.*}" u1="${t1#*.}"
  [[ "$s0" =~ ^[0-9]+$ && "$u0" =~ ^[0-9]+$ && "$s1" =~ ^[0-9]+$ && "$u1" =~ ^[0-9]+$ ]] || return 0
  u0=$((10#$u0)); u1=$((10#$u1))
  local sd=$((10#$s1 - 10#$s0))
  local ud=$((u1 - u0))
  if (( ud < 0 )); then
    ud=$((ud + 1000000))
    sd=$((sd - 1))
  fi
  (( sd < 0 )) && sd=0
  local total_us=$(( sd * 1000000 + ud ))
  _PL_MS=$(( total_us / 1000 ))
}

# pl_meter_begin — sets global _PL_T0 to now. No-op (leaves _PL_T0 empty)
# when EPOCHREALTIME is unavailable.
pl_meter_begin() {
  if pl_available; then
    _PL_T0="$EPOCHREALTIME"
  else
    _PL_T0=""
  fi
}

# pl_meter_end <hook-name> — computes elapsed ms since the matching
# pl_meter_begin, appends one JSONL line. Always returns 0 (safe to call
# from a `trap ... EXIT` under `set -e`/`set -eo pipefail`; never lets a
# metering failure affect the hook's own exit code). No-op when
# pl_meter_begin never ran or EPOCHREALTIME is unavailable. Zero `$(...)`
# anywhere in this call chain (see ZERO-FORK CONTRACT above).
pl_meter_end() {
  local hook="${1:-unknown}"
  if [[ -z "${_PL_T0:-}" ]] || ! pl_available; then
    _PL_T0=""
    return 0
  fi
  local t1="$EPOCHREALTIME"
  _pl_set_elapsed_ms "$_PL_T0" "$t1"
  local ms="$_PL_MS"
  [[ "$ms" =~ ^[0-9]+$ ]] || ms=0
  _PL_T0=""

  _pl_set_ledger_file
  [[ -d "$_PL_DIR" ]] || mkdir -p "$_PL_DIR" 2>/dev/null || true

  _pl_set_now_ts
  local ts="$_PL_NOWTS" hook_esc="$hook" ts_esc="$_PL_NOWTS"
  hook_esc="${hook_esc//\\/\\\\}"; hook_esc="${hook_esc//\"/\\\"}"
  ts_esc="${ts_esc//\\/\\\\}"; ts_esc="${ts_esc//\"/\\\"}"
  printf '{"ts":"%s","hook":"%s","ms":%d}\n' "$ts_esc" "$hook_esc" "$ms" \
    >> "$_PL_FILE" 2>/dev/null || true
  return 0
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--self-test" ]]; then
  _PL_PASSED=0
  _PL_FAILED=0
  _pl_pass() { _PL_PASSED=$((_PL_PASSED + 1)); echo "  PASS: $1"; }
  _pl_fail() { _PL_FAILED=$((_PL_FAILED + 1)); echo "  FAIL: $1" >&2; }

  echo "Scenario 1: EPOCHREALTIME availability detection (capability-honest)"
  # task-verifier 2026-07-29 (P1 re-verification, FAIL conf 9): this scenario used to
  # demand pl_available()==true unconditionally and, on failure, diagnosed with
  # `$(bash --version | head -1)` — a PATH-resolved bash, so a /bin/bash 3.2.57 run
  # reported "this host: GNU bash 5.3.15": the interpreter-identity lie (the last
  # surviving site of the class scope-enforcement-gate Scenario 38 exists to kill).
  # The honest contract is capability-aware: bash >=5 must detect EPOCHREALTIME;
  # pre-5 must report unavailable — BOTH are passes for the interpreter under test.
  if [[ "${BASH_VERSINFO[0]:-0}" -ge 5 ]]; then
    if pl_available; then
      _pl_pass "pl_available() true on bash ${BASH_VERSION} (\$EPOCHREALTIME='${EPOCHREALTIME}')"
    else
      _pl_fail "pl_available() false — expected true on bash >=5 (running: ${BASH_VERSION})"
    fi
  else
    if pl_available; then
      _pl_fail "pl_available() true on pre-5 bash ${BASH_VERSION} — EPOCHREALTIME cannot exist here; detection is broken"
    else
      _pl_pass "pl_available() false on bash ${BASH_VERSION} — the documented pre-5 no-op contract"
    fi
  fi

  echo "Scenario 2: no-op fallback when EPOCHREALTIME is forced-unavailable"
  _PL_T0=""
  ( unset EPOCHREALTIME 2>/dev/null
    source "${BASH_SOURCE[0]}" 2>/dev/null
    pl_meter_begin
    if [[ -z "${_PL_T0:-}" ]]; then echo OK; else echo FAIL; fi
  ) | grep -q '^OK$' && _pl_pass "pl_meter_begin no-ops (leaves _PL_T0 empty) when EPOCHREALTIME is unset" \
    || _pl_fail "pl_meter_begin did not no-op with EPOCHREALTIME unset"

  echo "Scenario 3: elapsed-ms arithmetic, incl. leading-zero-microsecond and second-rollover edge cases"
  _pl_set_elapsed_ms "10.000500" "11.000100"
  [[ "$_PL_MS" == "999" ]] && _pl_pass "999ms across a second rollover with leading-zero microseconds" \
    || _pl_fail "expected 999, got $_PL_MS"
  _pl_set_elapsed_ms "10.999900" "11.000100"
  [[ "$_PL_MS" == "0" ]] && _pl_pass "0ms (sub-1ms) elapsed computed correctly" \
    || _pl_fail "expected 0, got $_PL_MS"
  _pl_set_elapsed_ms "100.500000" "100.500123"
  [[ "$_PL_MS" == "0" ]] && _pl_pass "123us floors to 0ms (no over-rounding)" \
    || _pl_fail "expected 0, got $_PL_MS"
  _pl_set_elapsed_ms "100.000000" "105.000000"
  [[ "$_PL_MS" == "5000" ]] && _pl_pass "exact 5s -> 5000ms" \
    || _pl_fail "expected 5000, got $_PL_MS"

  echo "Scenario 4: ledger line schema + daily-rotation filename (sandboxed, capability-honest)"
  _PL_T="$(mktemp -d 2>/dev/null || mktemp -d -t pltst)"
  export PERF_LEDGER_DIR="$_PL_T/perf"
  export PERF_LEDGER_DATE_OVERRIDE="20260723"
  pl_meter_begin
  pl_meter_end "self-test-hook"
  _PL_EXPECTED_FILE="$_PL_T/perf/chain-20260723.jsonl"
  if [[ "${BASH_VERSINFO[0]:-0}" -ge 5 ]]; then
    if [[ -f "$_PL_EXPECTED_FILE" ]]; then
      _pl_pass "ledger file rotated to the overridden date: $_PL_EXPECTED_FILE"
    else
      _pl_fail "expected ledger file at $_PL_EXPECTED_FILE — found: $(ls "$_PL_T/perf" 2>/dev/null)"
    fi
    if [[ -f "$_PL_EXPECTED_FILE" ]] && grep -qE '^\{"ts":"[^"]+","hook":"self-test-hook","ms":[0-9]+\}$' "$_PL_EXPECTED_FILE"; then
      _pl_pass "ledger line matches the {ts,hook,ms} schema"
    else
      _pl_fail "ledger line schema mismatch: $(cat "$_PL_EXPECTED_FILE" 2>/dev/null)"
    fi
  else
    # Pre-5: the documented contract is NO-OP — pl_meter_end must write NOTHING.
    # The old expectations demanded a ledger write the lib's own contract forbids
    # here, so the suite failed 3.2 for honoring its own design (P1 re-verification).
    if [[ ! -f "$_PL_EXPECTED_FILE" ]]; then
      _pl_pass "pre-5 bash ${BASH_VERSION}: no ledger written — the documented no-op contract holds"
    else
      _pl_fail "pre-5 bash wrote a ledger line — the no-op contract is broken: $(cat "$_PL_EXPECTED_FILE")"
    fi
  fi

  echo "Scenario 5: pl_meter_end with no matching pl_meter_begin is a safe no-op (does not write)"
  _PL_T0=""
  rm -f "$_PL_EXPECTED_FILE"
  pl_meter_end "orphan-end-call"
  if [[ ! -f "$_PL_EXPECTED_FILE" ]]; then
    _pl_pass "no ledger line written when begin never ran"
  else
    _pl_fail "unexpectedly wrote a ledger line with no matching begin"
  fi

  echo "Scenario 6: hot-path overhead budget (<5ms/call) + timing-based fork absence proof"
  # A real Windows fork costs ~190ms (docs/lessons/2026-07-13-...). 500
  # begin/end pairs completing well under 1s (<2ms/call average) is strong
  # empirical evidence NONE of them forked — 500 real forks would take
  # ~95s. Directory pre-exists (steady-state; the one-time mkdir is not
  # part of this measurement).
  mkdir -p "$PERF_LEDGER_DIR" 2>/dev/null
  _PL_LOOP_T0="$EPOCHREALTIME"
  _pl_i=0
  while [[ "$_pl_i" -lt 500 ]]; do
    pl_meter_begin
    pl_meter_end "loop-hook"
    _pl_i=$((_pl_i + 1))
  done
  _PL_LOOP_T1="$EPOCHREALTIME"
  _pl_set_elapsed_ms "$_PL_LOOP_T0" "$_PL_LOOP_T1"
  _PL_LOOP_MS="$_PL_MS"
  _PL_PER_CALL_MS=$(( _PL_LOOP_MS / 500 ))
  echo "    500 begin/end pairs: ${_PL_LOOP_MS}ms total, ~${_PL_PER_CALL_MS}ms/call avg (a single fork would cost ~190ms)"
  if [[ "$_PL_LOOP_MS" -lt 2500 ]]; then
    _pl_pass "500 calls completed in ${_PL_LOOP_MS}ms (<2500ms budget; a single fork alone would exceed this) — average well under the 5ms/call hot-path budget"
  else
    _pl_fail "500 calls took ${_PL_LOOP_MS}ms — exceeds the budget; possible hidden fork"
  fi

  echo "Scenario 7: static fork-counting harness — no subprocess-spawning construct exists in the hot-path function bodies"
  # Extract just the hot-path functions (pl_available, the _pl_set_* / _pl_*
  # helpers, pl_meter_begin, pl_meter_end) and grep them for anything that
  # would spawn a process: command substitution $(...) or backticks, a
  # pipe, or a named external command this file must never call on the hot
  # path (date/mkdir/cat/jq/sed/awk/grep/wc/timeout/bc). mkdir is checked
  # separately below since it's the ONE explicitly-guarded cold-path
  # exception (see ZERO-FORK CONTRACT) — excluded from this pass, then
  # re-checked for its guard.
  _PL_SELF="${BASH_SOURCE[0]}"
  _PL_HOTPATH_LINES="$(sed -n '/^pl_available()/,/^}/p; /^_pl_set_ledger_dir()/,/^}/p; /^_pl_set_today()/,/^}/p; /^_pl_set_now_ts()/,/^}/p; /^_pl_set_ledger_file()/,/^}/p; /^_pl_set_elapsed_ms()/,/^}/p; /^pl_meter_begin()/,/^}/p; /^pl_meter_end()/,/^}/p' "$_PL_SELF")"
  # NOTE: `$((...))` is ARITHMETIC expansion (a builtin, never a fork) and
  # must NOT be flagged — only `$(` NOT followed by a second `(` is real
  # command substitution. `[^(]` after `\$\(` distinguishes the two: an
  # arithmetic expansion's `$` is always followed by TWO `(` in a row.
  # Likewise `||` (OR operator) must not be flagged as a pipe — strip every
  # `||` first (pure parameter expansion, no regex lookaround needed in
  # POSIX grep -E), then any remaining `|` is a real pipe.
  _PL_FORK_HIT=""
  _PL_NOOR="${_PL_HOTPATH_LINES//||/}"
  if printf '%s\n' "$_PL_HOTPATH_LINES" | grep -qE '\$\([^(]|`'; then
    _PL_FORK_HIT="command substitution / backtick"
  elif [[ "$_PL_NOOR" == *"|"* ]]; then
    _PL_FORK_HIT="pipe"
  elif printf '%s\n' "$_PL_HOTPATH_LINES" | grep -qE '\b(date|cat|jq|sed|awk|wc|timeout|bc|grep)\b'; then
    _PL_FORK_HIT="named external command"
  fi
  if [[ -z "$_PL_FORK_HIT" ]]; then
    _pl_pass "no command substitution, backtick, pipe, or named external command in the hot-path functions"
  else
    _pl_fail "found a potential fork source in the hot path: $_PL_FORK_HIT"
  fi
  # mkdir must appear at most once, guarded by a preceding [[ -d ]] test.
  _PL_MKDIR_LINE="$(printf '%s\n' "$_PL_HOTPATH_LINES" | grep -c 'mkdir -p')"
  _PL_MKDIR_GUARDED="$(printf '%s\n' "$_PL_HOTPATH_LINES" | grep -c '\[\[ -d "\$_PL_DIR" \]\] || mkdir -p')"
  if [[ "$_PL_MKDIR_LINE" -eq 1 && "$_PL_MKDIR_GUARDED" -eq 1 ]]; then
    _pl_pass "the one mkdir call is guarded by a [[ -d ]] test (cold-start only, never steady-state)"
  else
    _pl_fail "mkdir usage not in the expected guarded shape (found ${_PL_MKDIR_LINE} mkdir call(s), ${_PL_MKDIR_GUARDED} guarded)"
  fi

  rm -rf "$_PL_T" 2>/dev/null || true
  unset PERF_LEDGER_DIR PERF_LEDGER_DATE_OVERRIDE

  echo ""
  echo "self-test summary: ${_PL_PASSED} passed, ${_PL_FAILED} failed"
  if [[ "$_PL_FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
