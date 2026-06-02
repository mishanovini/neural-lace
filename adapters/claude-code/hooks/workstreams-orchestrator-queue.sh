#!/usr/bin/env bash
# workstreams-orchestrator-queue.sh — Component B wake-trigger writer (Stop hook).
#
# orchestration-architecture-2026-05-30.md §3 ("Where the queue lives"): a thin
# wake-trigger file dropped on every session Stop. It is NOT state — the
# reconciler reads the ADR-032 event log for truth. The queue exists only so a
# burst of Stops coalesces into "there is work to reconcile" and so the runner
# can be triggered with low latency. Losing the queue entirely costs nothing but
# latency — the scheduled reconciler pass re-reads full state regardless.
#
# This is deliberately a SEPARATE, tiny hook (NOT an edit to
# conversation-tree-emit.sh) so it composes additively into the Stop chain and
# never collides with the parallel Workstreams Phase-3 emit-hook work.
#
# Contract (gate-respect.md: WRITER hooks never block): exit 0 ALWAYS. Any error
# is logged and swallowed. The actual reconciliation is done by the node runner
# (reconciler-run.js), triggered by the scheduled task and/or by these wakes.
#
# Stdin: the Stop-hook JSON event ({"session_id": "...", ...}). All fields optional.

set -uo pipefail
trap 'exit 0' ERR   # a writer hook must never block a Stop

QUEUE_DIR="${ORCHESTRATOR_QUEUE_DIR:-$HOME/.claude/state/orchestrator/queue}"
LOG="${ORCHESTRATOR_QUEUE_LOG:-$HOME/.claude/state/orchestrator/queue.log}"

_log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" "$*" >>"$LOG" 2>/dev/null || true
}

# Drop one wake-trigger file. Best-effort; never fails the caller.
_drop_wake() {
  local queue_dir="$1" session_id="$2" event_type="$3"
  mkdir -p "$queue_dir" 2>/dev/null || return 0
  local ts rand fname
  ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo now)"
  # cheap unique suffix (no external dep): pid + nanoseconds-ish + RANDOM
  rand="${$}$(date +%N 2>/dev/null || echo 0)${RANDOM:-0}"
  fname="${queue_dir}/${ts}-${rand}.json"
  local machine_id; machine_id="$(hostname 2>/dev/null || echo local)"
  # Minimal thin trigger. jq if available for safe escaping; else printf.
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg et "$event_type" --arg sid "$session_id" --arg mid "$machine_id" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo now)" \
      '{event_type:$et, session_id:$sid, machine_id:$mid, ts:$ts}' >"$fname" 2>/dev/null \
      || printf '{"event_type":"%s","session_id":"%s","machine_id":"%s"}\n' "$event_type" "$session_id" "$machine_id" >"$fname" 2>/dev/null
  else
    printf '{"event_type":"%s","session_id":"%s","machine_id":"%s"}\n' "$event_type" "$session_id" "$machine_id" >"$fname" 2>/dev/null
  fi
  printf '%s' "$fname"
}

# ---- self-test --------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  trap - ERR
  pass=0; fail=0
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/wsq-st-$$")"
  qd="$tmp/queue"
  # ST1: a wake file lands and is valid JSON with the expected fields.
  f="$(_drop_wake "$qd" "sess-abc-123" "stop")"
  if [[ -n "$f" && -f "$f" ]]; then
    if command -v jq >/dev/null 2>&1; then
      et="$(jq -r '.event_type' "$f" 2>/dev/null)"
      sid="$(jq -r '.session_id' "$f" 2>/dev/null)"
      [[ "$et" == "stop" && "$sid" == "sess-abc-123" ]] && { echo "PASS ST1 wake file valid JSON w/ fields"; pass=$((pass+1)); } \
        || { echo "FAIL ST1 fields wrong (et=$et sid=$sid)"; fail=$((fail+1)); }
    else
      grep -q 'sess-abc-123' "$f" && { echo "PASS ST1 wake file (no jq)"; pass=$((pass+1)); } || { echo "FAIL ST1"; fail=$((fail+1)); }
    fi
  else
    echo "FAIL ST1 no wake file dropped"; fail=$((fail+1))
  fi
  # ST2: a second drop creates a DISTINCT file (burst coalescing relies on >1 file).
  sleep 0.01 2>/dev/null || true
  f2="$(_drop_wake "$qd" "sess-def-456" "stop")"
  cnt="$(find "$qd" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$cnt" -ge 2 && "$f2" != "$f" ]] && { echo "PASS ST2 distinct wake files ($cnt)"; pass=$((pass+1)); } \
    || { echo "FAIL ST2 expected ≥2 distinct files, got $cnt"; fail=$((fail+1)); }
  # ST3: missing queue dir is created on demand (no pre-existing dir).
  qd2="$tmp/fresh/queue"
  f3="$(_drop_wake "$qd2" "sess-x" "stop")"
  [[ -f "$f3" ]] && { echo "PASS ST3 queue dir auto-created"; pass=$((pass+1)); } || { echo "FAIL ST3"; fail=$((fail+1)); }
  rm -rf "$tmp" 2>/dev/null || true
  echo "── workstreams-orchestrator-queue.sh self-test: $pass passed, $fail failed ──"
  [[ "$fail" -eq 0 ]] && exit 0 || exit 1
fi

# ---- runtime (Stop hook) ----------------------------------------------------
INPUT="$(cat 2>/dev/null || echo '{}')"
SID=""
if command -v jq >/dev/null 2>&1; then
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo '')"
fi
WAKE="$(_drop_wake "$QUEUE_DIR" "$SID" "stop")"
_log "wake dropped: $WAKE (session=${SID:-?})"
exit 0
