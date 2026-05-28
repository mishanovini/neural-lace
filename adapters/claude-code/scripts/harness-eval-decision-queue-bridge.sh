#!/usr/bin/env bash
# harness-eval-decision-queue-bridge.sh — Bridge from the daily/weekly harness
# evaluator into the Decision Queue substrate (ADR-043).
#
# When the harness evaluator surfaces a recommendation that the human needs to
# decide on (e.g., "promote conjectural rule PT-3 to mechanism: yes/no/defer",
# "investigate drift item X: now/later/never"), it calls into this bridge
# instead of leaving the recommendation buried in a markdown packet.
#
# Activation: harness-evaluator.sh adds one of:
#
#   # at the end of its run (after the packet is written):
#   bash adapters/claude-code/scripts/harness-eval-decision-queue-bridge.sh \
#     --packet "$OUTPUT_PATH"
#
# Or invoke per-recommendation:
#
#   bash adapters/claude-code/scripts/harness-eval-decision-queue-bridge.sh \
#     emit-recommendation \
#     --question "..." --recommendation "..." \
#     --counter "..." --defer-cost "..." \
#     --evidence "url1" --evidence "url2" --evidence "url3" \
#     [--mode QUICK|PICK|DEEP] [--highlight subtle|strong|urgent[:reason]]
#
# This bridge ships in feat/decision-queue. The harness-evaluator.sh script
# lives on feat/drift-backlog-and-harness-evaluator (unmerged to master as of
# 2026-05-24). Activating the bridge requires a one-line addition to
# harness-evaluator.sh once that branch lands.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DQ_SCRIPT="$SCRIPT_DIR/decision-queue.sh"

[[ -x "$DQ_SCRIPT" ]] || { echo "bridge: $DQ_SCRIPT not executable" >&2; exit 1; }

# Default actor for highlight history.
export DQ_ACTOR="${DQ_ACTOR:-harness-evaluator}"

# ---- mode: emit-recommendation --------------------------------------------

emit_recommendation() {
  local question="" recommendation="" counter="" defer_cost=""
  local mode="QUICK" project="harness"
  local highlight_spec=""
  local -a evidence=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --question)        question="$2"; shift 2 ;;
      --recommendation)  recommendation="$2"; shift 2 ;;
      --counter|--counterargument) counter="$2"; shift 2 ;;
      --defer-cost|--consequence-of-deferring) defer_cost="$2"; shift 2 ;;
      --evidence)        evidence+=("$2"); shift 2 ;;
      --mode)            mode="$2"; shift 2 ;;
      --project)         project="$2"; shift 2 ;;
      --highlight)       highlight_spec="$2"; shift 2 ;;
      *) echo "bridge: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  [[ -n "$question" ]] || { echo "bridge: --question is required" >&2; exit 1; }
  [[ -n "$recommendation" ]] || { echo "bridge: --recommendation is required" >&2; exit 1; }

  # The harness evaluator's discipline (per its header): every recommendation
  # cites ≥3 evidence pointers. Enforce here so the bridge does not let weak
  # recommendations through to the queue.
  if [[ ${#evidence[@]} -lt 3 ]]; then
    echo "bridge: harness-evaluator recommendations must cite ≥3 evidence pointers; got ${#evidence[@]}" >&2
    exit 1
  fi

  # Build --source-link args (one per evidence pointer).
  local -a dq_args=(
    add
    --question "$question"
    --project "$project"
    --mode "$mode"
    --recommendation "$recommendation"
    --source-session "harness-evaluator"
  )
  [[ -n "$counter" ]] && dq_args+=(--counter "$counter")
  [[ -n "$defer_cost" ]] && dq_args+=(--defer-cost "$defer_cost")
  local ev
  for ev in "${evidence[@]}"; do dq_args+=(--source-link "$ev"); done

  local new_id
  new_id=$(bash "$DQ_SCRIPT" "${dq_args[@]}") || { echo "bridge: decision-queue add failed" >&2; exit 1; }

  # Optional highlight.
  if [[ -n "$highlight_spec" ]]; then
    local level="${highlight_spec%%:*}"
    local reason="${highlight_spec#*:}"
    [[ "$level" == "$highlight_spec" ]] && reason="surfaced by daily harness evaluator"
    case "$level" in subtle|strong|urgent)
      bash "$DQ_SCRIPT" highlight "$new_id" --reason "$reason" --level "$level" || true
      ;;
    *) echo "bridge: invalid highlight level '$level'" >&2 ;;
    esac
  fi

  echo "$new_id"
}

# ---- mode: --packet (parse a daily packet and emit one item per Top-N rec)

emit_from_packet() {
  local packet_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --packet) packet_path="$2"; shift 2 ;;
      *) echo "bridge: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done
  [[ -r "$packet_path" ]] || { echo "bridge: cannot read $packet_path" >&2; exit 1; }

  # v1 behavior: walk Section "4. Top 3 ..." subsections and emit one decision
  # per "**Recommendation:**" line. Each must already have ≥3 evidence pointers
  # per the evaluator's design constraint (we re-enforce in emit-recommendation).
  #
  # The parsing is intentionally conservative — it surfaces what's already
  # structured in the packet, not free-form prose. If the packet doesn't have a
  # recognizable Top-N block, the bridge does nothing and exits 0.

  local in_top=0 cur_section="" cur_question="" cur_rec="" cur_counter="" cur_defer=""
  local -a cur_ev=()
  local emitted=0

  flush() {
    if [[ -n "$cur_question" && -n "$cur_rec" && ${#cur_ev[@]} -ge 3 ]]; then
      local -a args=(
        emit-recommendation
        --question "$cur_question"
        --recommendation "$cur_rec"
      )
      [[ -n "$cur_counter" ]] && args+=(--counter "$cur_counter")
      [[ -n "$cur_defer" ]] && args+=(--defer-cost "$cur_defer")
      local e; for e in "${cur_ev[@]}"; do args+=(--evidence "$e"); done
      "$0" "${args[@]}" >/dev/null && emitted=$((emitted+1)) || true
    fi
    cur_question=""; cur_rec=""; cur_counter=""; cur_defer=""; cur_ev=()
  }

  while IFS= read -r line; do
    case "$line" in
      "## 4. Top 3"*|"## 4. Top "*)  in_top=1 ;;
      "## 5."*|"## 6."*|"## 7."*)    in_top=0; flush ;;
      "### 4."*)                     [[ $in_top -eq 1 ]] && { flush; cur_section="$line"; } ;;
    esac
    [[ $in_top -eq 0 ]] && continue

    case "$line" in
      "**Question:**"*)        cur_question="${line#**Question:** }" ;;
      "**Recommendation:**"*)  cur_rec="${line#**Recommendation:** }" ;;
      "**Counterargument:**"*) cur_counter="${line#**Counterargument:** }" ;;
      "**Defer cost:**"*)      cur_defer="${line#**Defer cost:** }" ;;
      "**Evidence:**"*)        ;;  # next bullet lines are evidence
      "- "*)
        # Treat bullet lines as evidence pointers when inside an item context.
        [[ -n "$cur_question" ]] && cur_ev+=("${line#- }")
        ;;
    esac
  done < "$packet_path"

  flush
  echo "bridge: emitted $emitted decision items from $packet_path"
}

# ---- self-test ------------------------------------------------------------

run_selftest() {
  local sandbox; sandbox=$(mktemp -d)
  export DQ_STATE_DIR="$sandbox/state"
  local pass=0 fail=0
  ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
  fail() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }

  echo "harness-eval-decision-queue-bridge self-test (sandbox: $sandbox)"

  # B1: emit-recommendation with all required fields
  local id
  id=$("$0" emit-recommendation \
    --question "Promote conjectural rule PT-3 to mechanism?" \
    --recommendation "Yes — 4 matched events in propagation audit log; passes the 3-event threshold." \
    --counter "Mechanizing too early can ossify a pattern that's still maturing." \
    --defer-cost "PT-3 stays as a documented Pattern; no mechanical enforcement yet." \
    --evidence "build-doctrine/telemetry/propagation.jsonl" \
    --evidence "docs/decisions/queued-tranche-1.5.md" \
    --evidence "build-doctrine/doctrine/07-knowledge-integration.md") || true
  if [[ "$id" =~ ^DQ- ]]; then ok "B1 emit-recommendation returns DQ- id ($id)"; else fail "B1 emit failed"; fi

  # B2: rejects with <3 evidence pointers
  set +e
  local id2
  id2=$("$0" emit-recommendation \
    --question "Weak rec" --recommendation "x" \
    --evidence "one" --evidence "two" 2>/dev/null)
  local rc=$?
  set -e
  [[ "$rc" != "0" && -z "$id2" ]] && ok "B2 rejects <3 evidence pointers" || fail "B2 accepted weak rec (rc=$rc)"

  # B3: --highlight subtle:reason works
  local id3
  id3=$("$0" emit-recommendation \
    --question "Highlighted rec" \
    --recommendation "x" \
    --evidence a --evidence b --evidence c \
    --highlight "subtle:aging past 14 days") || true
  local h_level
  h_level=$(bash "$DQ_SCRIPT" get "$id3" | jq -r '.highlight_level')
  [[ "$h_level" == "subtle" ]] && ok "B3 --highlight subtle sets level" || fail "B3 highlight level=$h_level"

  # B4: DQ_ACTOR defaults to harness-evaluator in highlight_history
  local actor
  actor=$(bash "$DQ_SCRIPT" get "$id3" | jq -r '.highlight_history[0].by')
  [[ "$actor" == "harness-evaluator" ]] && ok "B4 DQ_ACTOR default is harness-evaluator" \
    || fail "B4 actor=$actor"

  rm -rf "$sandbox"
  echo ""
  echo "RESULT: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# ---- main -----------------------------------------------------------------

if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage:
  harness-eval-decision-queue-bridge.sh emit-recommendation --question ... --recommendation ... --evidence ... --evidence ... --evidence ... [--counter ...] [--defer-cost ...] [--mode ...] [--highlight LEVEL[:REASON]]
  harness-eval-decision-queue-bridge.sh --packet <path>
  harness-eval-decision-queue-bridge.sh --self-test

Bridges harness-evaluator.sh recommendations into the Decision Queue substrate.
See: docs/decisions/043-decision-queue-substrate.md
EOF
  exit 0
fi

case "$1" in
  emit-recommendation) shift; emit_recommendation "$@" ;;
  --packet) emit_from_packet "$@" ;;
  --self-test|--selftest|selftest) run_selftest ;;
  *) echo "bridge: unknown command '$1'" >&2; exit 1 ;;
esac
