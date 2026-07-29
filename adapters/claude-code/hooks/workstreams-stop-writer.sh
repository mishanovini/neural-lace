#!/usr/bin/env bash
# workstreams-stop-writer.sh — ONE consolidated Stop entry for the workstreams writer
# family (ADR 058 D5 target chain #4; specs-d §D.0.2). Collapses six prior Stop
# entries: workstreams-stop-gate, workstreams-emit --on-stop, workstreams-task-binding
# --on-stop (warn mode per D.6 — its Stop BLOCK retired per specs-d §D.0.5),
# workstreams-extract-pending, workstreams-emit-reconciler, workstreams-orchestrator-queue.
#
# WRITER SEMANTICS — THIS HOOK NEVER BLOCKS. Member stdout is swallowed (that is where
# a legacy {"decision":"block"} would live); member side effects (GUI data layer,
# queues, pending files) still happen. Any member that emits output is recorded as a
# signal-ledger WARN — the uniform demotion mechanism: complaints become ledger
# events, not session blocks.
set -u

INPUT="$(cat 2>/dev/null || true)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
[[ -f "$HOOKS_DIR/lib/signal-ledger.sh" ]] && source "$HOOKS_DIR/lib/signal-ledger.sh"
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/hook-reentry-guard.sh" 2>/dev/null; } || true

# ----------------------------------------------------------------------
# _wsw_now_ms — current epoch time in milliseconds (best-effort; falls
# back to whole-second*1000 on a `date` build without %3N). NL
# Observability Program Wave O, task O.1 (specs-o §O.1 deliverable 2 /
# contract C2 turn-trace) — mirrors stop-verdict-dispatcher.sh's own
# _svd_now_ms helper (duplicated rather than shared, since these two
# aggregators are deliberately independent per contract C2: "turn-trace
# ... emitted once per Stop by each chain aggregator for its own
# members").
# ----------------------------------------------------------------------
_wsw_now_ms() {
  local ms
  ms=$(date +%s%3N 2>/dev/null)
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "${#ms}" -ge 13 ]]; then
    printf '%s' "$ms"
  else
    printf '%s000' "$(date +%s 2>/dev/null || echo 0)"
  fi
}

MEMBERS=(
  "workstreams-stop-gate.sh"
  "workstreams-emit.sh --on-stop"
  "workstreams-task-binding.sh --on-stop"
  "workstreams-emit-reconciler.sh"
  "workstreams-orchestrator-queue.sh"
)

if [[ "${1:-}" == "--self-test" ]]; then
  fails=0
  for spec in "${MEMBERS[@]}"; do
    f="${spec%% *}"
    if [[ ! -f "$HOOKS_DIR/$f" ]]; then
      echo "self-test FAIL: missing member $f" >&2
      fails=1
    fi
  done
  # Syntax-check only — never live-run the REAL members in self-test (writers
  # mutate the GUI data layer / queues). E.2's temp-HOME sweep covers execution.
  if ! bash -n "${BASH_SOURCE[0]}"; then
    echo "self-test FAIL: writer fails bash -n" >&2
    fails=1
  fi
  [[ $fails -eq 0 ]] && echo "self-test PASS: ${#MEMBERS[@]} members present; writer syntax OK"

  # ------------------------------------------------------------------
  # Wave O task O.1 (specs-o §O.1 deliverable 2 / contract C2): prove the
  # turn-trace mechanism itself lands a valid event, WITHOUT live-running
  # the real GUI-mutating members above. Builds a throwaway copy of this
  # writer in a fixture hooks/ dir alongside SIX stub member scripts (same
  # basenames as MEMBERS, each a trivial script that either exits silent
  # or prints something to exercise the warn path) and a stub
  # lib/signal-ledger.sh sourcing the REAL one with SIGNAL_LEDGER_PATH
  # sandboxed — so the turn-trace assertion below is genuinely proving the
  # mechanism (real ledger_emit, real timing loop), not a re-description of it.
  # ------------------------------------------------------------------
  _wsw_tt_tmp=$(mktemp -d 2>/dev/null || mktemp -d -t wswst)
  if [[ -n "$_wsw_tt_tmp" && -d "$_wsw_tt_tmp" ]]; then
    trap 'rm -rf "${_wsw_tt_tmp:-}"' EXIT
    mkdir -p "$_wsw_tt_tmp/hooks/lib" "$_wsw_tt_tmp/scripts"
    cp "${BASH_SOURCE[0]}" "$_wsw_tt_tmp/hooks/workstreams-stop-writer.sh"
    cp "$HOOKS_DIR/lib/signal-ledger.sh" "$_wsw_tt_tmp/hooks/lib/signal-ledger.sh" 2>/dev/null
    # ADR-061 D2: give the fixture tree the REAL heartbeat writer + its lib
    # (+ the reentry guard) so the fixture run below can also prove the
    # non-reentry heartbeat event name is unchanged ("turn-end", O.2
    # callsite) — sandboxed via HEARTBEAT_STATE_DIR.
    cp "$HOOKS_DIR/lib/hook-reentry-guard.sh" "$_wsw_tt_tmp/hooks/lib/hook-reentry-guard.sh" 2>/dev/null
    cp "$HOOKS_DIR/lib/session-heartbeat-lib.sh" "$_wsw_tt_tmp/hooks/lib/session-heartbeat-lib.sh" 2>/dev/null
    cp "$HOOKS_DIR/../scripts/session-heartbeat.sh" "$_wsw_tt_tmp/scripts/session-heartbeat.sh" 2>/dev/null
    for _wsw_member_spec in \
      "workstreams-stop-gate.sh:silent" \
      "workstreams-emit.sh:silent" \
      "workstreams-task-binding.sh:silent" \
      "workstreams-emit-reconciler.sh:warn" \
      "workstreams-orchestrator-queue.sh:silent"; do
      _wsw_mf="${_wsw_member_spec%%:*}"
      _wsw_mmode="${_wsw_member_spec##*:}"
      if [[ "$_wsw_mmode" == "warn" ]]; then
        printf '#!/bin/bash\ncat >/dev/null 2>&1\necho "stub warn from %s"\nexit 0\n' "$_wsw_mf" > "$_wsw_tt_tmp/hooks/$_wsw_mf"
      else
        printf '#!/bin/bash\ncat >/dev/null 2>&1\nexit 0\n' > "$_wsw_tt_tmp/hooks/$_wsw_mf"
      fi
      chmod +x "$_wsw_tt_tmp/hooks/$_wsw_mf"
    done

    _wsw_tt_ledger="$_wsw_tt_tmp/ledger.jsonl"
    _wsw_tt_hb_dir="$_wsw_tt_tmp/hb-nonreentry"
    mkdir -p "$_wsw_tt_hb_dir"
    _wsw_tt_out=$(printf '{}' | HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$_wsw_tt_ledger" HEARTBEAT_STATE_DIR="$_wsw_tt_hb_dir" CLAUDE_CODE_SESSION_ID="sess-wsw-nonreentry" bash "$_wsw_tt_tmp/hooks/workstreams-stop-writer.sh" 2>&1)
    _wsw_tt_rc=$?

    if [[ "$_wsw_tt_rc" -eq 0 ]]; then
      echo "self-test PASS: fixture writer run exits 0 (writer never blocks)"
    else
      echo "self-test FAIL: fixture writer run exited $_wsw_tt_rc (expected 0)" >&2
      fails=1
    fi
    if [[ -f "$_wsw_tt_ledger" ]] && grep -q '"gate":"workstreams-stop-writer".*"event":"turn-trace"' "$_wsw_tt_ledger" 2>/dev/null; then
      echo "self-test PASS: turn-trace event landed (contract C2)"
    else
      echo "self-test FAIL: expected a workstreams-stop-writer/turn-trace ledger event in $_wsw_tt_ledger" >&2
      echo "  --- writer output ---" >&2
      echo "$_wsw_tt_out" >&2
      fails=1
    fi
    if command -v jq >/dev/null 2>&1 && [[ -f "$_wsw_tt_ledger" ]]; then
      _wsw_tt_trace_line=$(grep '"event":"turn-trace"' "$_wsw_tt_ledger" 2>/dev/null | tail -1)
      _wsw_tt_detail=$(printf '%s' "$_wsw_tt_trace_line" | jq -r '.detail' 2>/dev/null)
      _wsw_tt_nhooks=$(printf '%s' "$_wsw_tt_detail" | jq -r '.hooks | length' 2>/dev/null)
      if [[ "$_wsw_tt_nhooks" == "${#MEMBERS[@]}" ]]; then
        echo "self-test PASS: turn-trace records one entry per member (${_wsw_tt_nhooks}/${#MEMBERS[@]})"
      else
        echo "self-test FAIL: expected ${#MEMBERS[@]} hook entries in turn-trace, got ${_wsw_tt_nhooks}" >&2
        fails=1
      fi
      _wsw_tt_total_ms=$(printf '%s' "$_wsw_tt_detail" | jq -r '.total_ms' 2>/dev/null)
      if [[ "$_wsw_tt_total_ms" =~ ^[0-9]+$ ]]; then
        echo "self-test PASS: turn-trace total_ms is numeric ($_wsw_tt_total_ms)"
      else
        echo "self-test FAIL: turn-trace total_ms not numeric (got: $_wsw_tt_total_ms)" >&2
        fails=1
      fi
      _wsw_tt_reconciler_v=$(printf '%s' "$_wsw_tt_detail" | jq -r '.hooks[] | select(.n=="workstreams-emit-reconciler") | .v' 2>/dev/null)
      if [[ "$_wsw_tt_reconciler_v" == "warn" ]]; then
        echo "self-test PASS: member that produced output is recorded with verdict=warn"
      else
        echo "self-test FAIL: expected workstreams-emit-reconciler verdict=warn in trace, got '$_wsw_tt_reconciler_v'" >&2
        fails=1
      fi
    fi
    if [[ -f "$_wsw_tt_ledger" ]] && grep -q '"gate":"workstreams-emit-reconciler".*"event":"warn"' "$_wsw_tt_ledger" 2>/dev/null; then
      echo "self-test PASS: pre-existing per-member warn ledger event unaffected by the trace addition"
    else
      echo "self-test FAIL: expected the pre-existing workstreams-emit-reconciler/warn ledger event to still land" >&2
      fails=1
    fi

    # ---- ADR-061 D2 scenarios ------------------------------------------
    # Non-reentry (the fixture run above, no NL_HOOK_REENTRY in its env):
    # the O.2 callsite heartbeat event name is byte-identical to before —
    # "turn-end", never the -auto variant.
    if grep -q '"last_event":"turn-end","marker_state"' "$_wsw_tt_hb_dir/sess-wsw-nonreentry.json" 2>/dev/null \
       && ! grep -q 'turn-end-auto' "$_wsw_tt_hb_dir/sess-wsw-nonreentry.json" 2>/dev/null; then
      echo "self-test PASS: non-reentry heartbeat event name unchanged (turn-end, not turn-end-auto)"
    else
      echo "self-test FAIL: expected last_event turn-end (not -auto) in $_wsw_tt_hb_dir/sess-wsw-nonreentry.json; got: $(cat "$_wsw_tt_hb_dir/sess-wsw-nonreentry.json" 2>/dev/null)" >&2
      fails=1
    fi

    # Reentry: run the REAL writer (safe — the guard exits before the
    # member fork loop) under NL_HOOK_REENTRY=1 with a sandboxed heartbeat
    # dir + ledger. Assert: exit 0; heartbeat written with turn-end-auto;
    # the member fork loop stayed suppressed (no turn-trace ledger event —
    # the known side effect every non-reentry run emits, asserted above).
    _wsw_re_hb_dir="$_wsw_tt_tmp/hb-reentry"
    _wsw_re_ledger="$_wsw_tt_tmp/ledger-reentry.jsonl"
    mkdir -p "$_wsw_re_hb_dir"
    printf '{}' | NL_HOOK_REENTRY=1 HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$_wsw_re_ledger" HEARTBEAT_STATE_DIR="$_wsw_re_hb_dir" CLAUDE_CODE_SESSION_ID="sess-wsw-reentry" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1
    _wsw_re_rc=$?
    if [[ "$_wsw_re_rc" -eq 0 ]] && grep -q '"last_event":"turn-end-auto","marker_state"' "$_wsw_re_hb_dir/sess-wsw-reentry.json" 2>/dev/null; then
      echo "self-test PASS: reentry (NL_HOOK_REENTRY=1) writes heartbeat with turn-end-auto event, exit 0"
    else
      echo "self-test FAIL: expected turn-end-auto heartbeat under reentry (rc=$_wsw_re_rc, file: $(cat "$_wsw_re_hb_dir/sess-wsw-reentry.json" 2>/dev/null))" >&2
      fails=1
    fi
    if ! grep -q '"event":"turn-trace"' "$_wsw_re_ledger" 2>/dev/null; then
      echo "self-test PASS: reentry run still suppresses the member fork loop (no turn-trace event)"
    else
      echo "self-test FAIL: reentry run emitted a turn-trace event — member fork loop was NOT suppressed" >&2
      fails=1
    fi
    # ---- END ADR-061 D2 scenarios ---------------------------------------
  fi

  exit $fails
fi

# NL-FINDING-040 keystone guard: this writer forks 5 member subprocesses
# on EVERY live Stop (workstreams-stop-gate, workstreams-emit --on-stop,
# workstreams-task-binding --on-stop, workstreams-emit-reconciler,
# workstreams-orchestrator-queue — see MEMBERS above). Under
# NL_HOOK_REENTRY=1 (automation-spawned/re-entrant child), skip the entire
# fork loop and exit 0 — this hook is pure WRITER semantics (never blocks;
# see header), so suppressing it changes nothing about session
# correctness, only whether an automation-spawned child re-triggers 5 more
# forks per Stop.
if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
  # ---- ADR-061 D2 HOIST: reentry-safe liveness heartbeat -----------------
  # An automation-spawned child (NL_HOOK_REENTRY=1 — the guard's ONLY
  # trigger) must still be VISIBLE to the heartbeat liveness layer: an
  # invisible child that looks dead gets re-resumed — the FM-037 "branching
  # growth" root (ADR-061 §2). The touch is bounded, spawns no `claude`,
  # and never blocks (session-heartbeat.sh touch exits 0 on every path).
  # Event name carries the -auto suffix — a new last_event VALUE only; C1
  # schema unchanged. The member fork loop below stays suppressed exactly
  # as before.
  marker_state="${SESSION_HEARTBEAT_MARKER_STATE:-none}"
  bash "$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event turn-end-auto --marker "$marker_state" >/dev/null 2>&1 || true
  # ---- END ADR-061 D2 HOIST -----------------------------------------------
  hook_reentry_note "workstreams-stop-writer" 2>/dev/null || true
  exit 0
fi

# ---- WAVE-O O.1: member timing -> ONE turn-trace event (contract C2) ----
_WSW_TRACE_HOOKS=()
_wsw_start_ms=$(_wsw_now_ms)

for spec in "${MEMBERS[@]}"; do
  f="${spec%% *}"
  args="${spec#"$f"}"
  _wsw_t0=$(_wsw_now_ms)
  # shellcheck disable=SC2086
  out=$(printf '%s' "$INPUT" | bash "$HOOKS_DIR/$f" $args 2>&1 || true)
  _wsw_t1=$(_wsw_now_ms)
  _wsw_verdict="allow"
  if [[ -n "$out" ]] && command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "${f%.sh}" "warn" "stop-writer: ${out:0:200}"
    _wsw_verdict="warn"
  fi
  if command -v jq >/dev/null 2>&1; then
    _WSW_TRACE_HOOKS+=("$(jq -cn --arg n "${f%.sh}" --argjson ms "$((_wsw_t1 - _wsw_t0))" --arg v "$_wsw_verdict" '{n:$n, ms:$ms, v:$v}' 2>/dev/null)")
  else
    _WSW_TRACE_HOOKS+=("{\"n\":\"${f%.sh}\",\"ms\":$((_wsw_t1 - _wsw_t0)),\"v\":\"$_wsw_verdict\"}")
  fi
done

if command -v ledger_emit >/dev/null 2>&1; then
  _wsw_end_ms=$(_wsw_now_ms)
  _wsw_total_ms=$((_wsw_end_ms - _wsw_start_ms))
  [[ "$_wsw_total_ms" -lt 0 ]] && _wsw_total_ms=0
  _wsw_hooks_json="[]"
  if [[ "${#_WSW_TRACE_HOOKS[@]}" -gt 0 ]]; then
    _wsw_IFS_save="$IFS"
    IFS=,
    _wsw_hooks_json="[${_WSW_TRACE_HOOKS[*]}]"
    IFS="$_wsw_IFS_save"
  fi
  ledger_emit "workstreams-stop-writer" "turn-trace" "$(printf '{"hooks":%s,"total_ms":%s}' "$_wsw_hooks_json" "$_wsw_total_ms")"
fi

# ---- WAVE-O O.2 CALLSITE: turn-end liveness heartbeat -------------------
# Best-effort, never-blocks. marker_state defaults to "none" (orchestrator
# decision, specs-o §O.2 callsite-wiring.md: do NOT wire a marker scan this
# batch — no Stop-chain member currently exports a scanned MARKER_KEYWORD
# for this hook to reuse).
marker_state="${SESSION_HEARTBEAT_MARKER_STATE:-none}"
bash "$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event turn-end --marker "$marker_state" >/dev/null 2>&1 || true
# ---- END WAVE-O O.2 CALLSITE ----------------------------------------------

exit 0
