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
  "workstreams-extract-pending.sh"
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
    mkdir -p "$_wsw_tt_tmp/hooks/lib"
    cp "${BASH_SOURCE[0]}" "$_wsw_tt_tmp/hooks/workstreams-stop-writer.sh"
    cp "$HOOKS_DIR/lib/signal-ledger.sh" "$_wsw_tt_tmp/hooks/lib/signal-ledger.sh" 2>/dev/null
    for _wsw_member_spec in \
      "workstreams-stop-gate.sh:silent" \
      "workstreams-emit.sh:silent" \
      "workstreams-task-binding.sh:silent" \
      "workstreams-extract-pending.sh:silent" \
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
    _wsw_tt_out=$(printf '{}' | HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$_wsw_tt_ledger" bash "$_wsw_tt_tmp/hooks/workstreams-stop-writer.sh" 2>&1)
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
  fi

  exit $fails
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
"$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event turn-end --marker "$marker_state" >/dev/null 2>&1 || true
# ---- END WAVE-O O.2 CALLSITE ----------------------------------------------

exit 0
