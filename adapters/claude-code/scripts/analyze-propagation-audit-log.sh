#!/bin/bash
# analyze-propagation-audit-log.sh — read build-doctrine/telemetry/propagation.jsonl
# and emit operational summaries (Tranche 5a-integration, 2026-05-06).
#
# Consumed by:
#   - KIT-6 (propagation-engine audit-log trigger) per build-doctrine/doctrine/07-knowledge-integration.md
#   - /harness-review skill Check 13 (KIT-1..KIT-7 sweep)
#
# Subcommands:
#   summary [--audit-log PATH]      Top-level overview: total events, fired count,
#                                   unmatched count, condition-not-met count,
#                                   action-failed count, slow-rule count.
#   cadence [--audit-log PATH]      Rule-fire frequency by rule_id (descending),
#                                   plus conjectural-rule disposition candidates
#                                   (rules with >= 3 matched events tagged
#                                   "promotion candidate").
#   unmatched [--audit-log PATH]    Negative-space summary: which event_types
#                                   fire with no rule, count by event_type.
#   slow [--audit-log PATH]         Slow-rule report: rules whose duration_ms
#                                   exceeded the per-rule budget.
#   --self-test                     Run internal scenarios.
#   --help                          Show usage.
#
# Exit codes:
#   0 — completed successfully (output goes to stdout)
#   1 — generic failure
#   2 — usage error

set -uo pipefail

SCRIPT_NAME="analyze-propagation-audit-log.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Promotion-candidate threshold for conjectural rules. v1 hypothesis: 3 matched
# events. Tunable via env or future config; pilot evidence informs whether 3 is
# the right floor.
PROMOTION_CANDIDATE_THRESHOLD="${PROMOTION_CANDIDATE_THRESHOLD:-3}"

usage() {
  cat <<'EOF'
Usage: analyze-propagation-audit-log.sh summary [--audit-log PATH]
       analyze-propagation-audit-log.sh cadence [--audit-log PATH]
       analyze-propagation-audit-log.sh unmatched [--audit-log PATH]
       analyze-propagation-audit-log.sh slow [--audit-log PATH]
       analyze-propagation-audit-log.sh --self-test
       analyze-propagation-audit-log.sh --help

Reads the propagation engine's audit log (default
build-doctrine/telemetry/propagation.jsonl, overridable via --audit-log or
$PROPAGATION_AUDIT_LOG) and emits operational summaries consumed by KIT-6
trigger and the /harness-review skill's KIT-1..KIT-7 sweep.

Subcommands emit human-readable text summaries to stdout. Empty or missing
audit logs produce a "no events captured yet" message and exit 0 (not an
error).

Examples:
  analyze-propagation-audit-log.sh summary
  analyze-propagation-audit-log.sh cadence --audit-log /custom/path/audit.jsonl
  PROMOTION_CANDIDATE_THRESHOLD=5 analyze-propagation-audit-log.sh cadence
EOF
}

# ---------------------------------------------------------------------------
# Locate audit log: --audit-log flag > $PROPAGATION_AUDIT_LOG env > default.
# ---------------------------------------------------------------------------
locate_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

resolve_audit_log() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return
  fi
  if [[ -n "${PROPAGATION_AUDIT_LOG:-}" ]]; then
    printf '%s' "$PROPAGATION_AUDIT_LOG"
    return
  fi
  printf '%s/build-doctrine/telemetry/propagation.jsonl' "$(locate_repo_root)"
}

# ---------------------------------------------------------------------------
# Filter valid JSON lines from input. Invalid lines emit warnings to stderr
# (line number + first 80 chars) but don't fail the run.
# ---------------------------------------------------------------------------
read_valid_lines() {
  local audit_log="$1"
  if [[ ! -f "$audit_log" ]]; then
    return 0  # Empty by design — caller handles.
  fi
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ -z "$line" ]]; then continue; fi
    if printf '%s' "$line" | jq empty 2>/dev/null; then
      printf '%s\n' "$line"
    else
      printf '[analyze] skipping invalid JSONL at line %d: %.80s\n' "$line_num" "$line" >&2
    fi
  done < "$audit_log"
}

# ---------------------------------------------------------------------------
# summary — top-level event counts.
# ---------------------------------------------------------------------------
cmd_summary() {
  local audit_log="$1"
  local lines
  lines=$(read_valid_lines "$audit_log")

  if [[ -z "$lines" ]]; then
    if [[ ! -f "$audit_log" ]]; then
      printf 'no audit log at %s — propagation engine has not fired yet\n' "$audit_log"
    else
      printf 'audit log empty (no valid events at %s)\n' "$audit_log"
    fi
    return 0
  fi

  local total fired unmatched no_rules condition_failed action_failed budget_exceeded slow
  total=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
  fired=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "fired") | .rule_id' | wc -l | tr -d ' ')
  unmatched=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "unmatched") | .rule_id' | wc -l | tr -d ' ')
  no_rules=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "no-rules-matched") | "x"' | wc -l | tr -d ' ')
  condition_failed=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "condition-not-met") | "x"' | wc -l | tr -d ' ')
  action_failed=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "action-failed") | "x"' | wc -l | tr -d ' ')
  budget_exceeded=$(printf '%s\n' "$lines" | jq -r 'select(.verdict == "event-budget-exceeded") | "x"' | wc -l | tr -d ' ')
  slow=$(printf '%s\n' "$lines" | jq -r 'select(.slow_rule == true) | "x"' | wc -l | tr -d ' ')

  printf 'Propagation engine audit log — summary\n'
  printf '  audit log: %s\n' "$audit_log"
  printf '  total entries: %s\n' "$total"
  printf '  fired (rule matched + action fired): %s\n' "$fired"
  printf '  unmatched (rule trigger did not match): %s\n' "$unmatched"
  printf '  no-rules-matched (event had zero matching rules): %s\n' "$no_rules"
  printf '  condition-not-met: %s\n' "$condition_failed"
  printf '  action-failed: %s\n' "$action_failed"
  printf '  event-budget-exceeded: %s\n' "$budget_exceeded"
  printf '  slow-rule warnings: %s\n' "$slow"
}

# ---------------------------------------------------------------------------
# cadence — rule-fire frequency + conjectural-rule promotion candidates.
# ---------------------------------------------------------------------------
cmd_cadence() {
  local audit_log="$1"
  local lines
  lines=$(read_valid_lines "$audit_log")

  if [[ -z "$lines" ]]; then
    printf 'no audit log entries — cannot compute cadence\n'
    return 0
  fi

  printf 'Rule-fire frequency (rule_id : count, descending)\n'
  local freq
  freq=$(printf '%s\n' "$lines" \
    | jq -r 'select(.verdict == "fired") | .rule_id' \
    | sort | uniq -c | sort -rn)
  if [[ -z "$freq" ]]; then
    printf '  (no rules have fired yet)\n'
  else
    printf '%s\n' "$freq" | awk '{printf "  %-50s : %d\n", $2, $1}'
  fi

  printf '\nConjectural rules — promotion candidates (>= %s matched events)\n' "$PROMOTION_CANDIDATE_THRESHOLD"
  local cand
  cand=$(printf '%s\n' "$lines" \
    | jq -r 'select(.conjectural == true and .verdict == "fired") | .rule_id' \
    | sort | uniq -c | sort -rn \
    | awk -v t="$PROMOTION_CANDIDATE_THRESHOLD" '$1 >= t {print}')
  if [[ -z "$cand" ]]; then
    printf '  (no conjectural rules ready for promotion yet)\n'
  else
    printf '%s\n' "$cand" | awk '{printf "  %-50s : %d events — review for conjectural -> proven\n", $2, $1}'
  fi
}

# ---------------------------------------------------------------------------
# unmatched — negative-space summary: event_types with no rule.
# ---------------------------------------------------------------------------
cmd_unmatched() {
  local audit_log="$1"
  local lines
  lines=$(read_valid_lines "$audit_log")

  if [[ -z "$lines" ]]; then
    printf 'no audit log entries — cannot compute unmatched summary\n'
    return 0
  fi

  printf 'Unmatched event types (no-rules-matched events)\n'
  local types
  types=$(printf '%s\n' "$lines" \
    | jq -r 'select(.verdict == "no-rules-matched") | .event.event_type' \
    | sort | uniq -c | sort -rn)
  if [[ -z "$types" ]]; then
    printf '  (every event was matched by at least one rule)\n'
  else
    printf '%s\n' "$types" | awk '{printf "  %-30s : %d events — candidate for new rule\n", $2, $1}'
  fi
}

# ---------------------------------------------------------------------------
# slow — slow-rule report: rules whose duration_ms exceeded the per-rule budget.
# ---------------------------------------------------------------------------
cmd_slow() {
  local audit_log="$1"
  local lines
  lines=$(read_valid_lines "$audit_log")

  if [[ -z "$lines" ]]; then
    printf 'no audit log entries — cannot compute slow-rule report\n'
    return 0
  fi

  printf 'Slow rules (per-rule budget exceeded — slow_rule:true entries)\n'
  local slow
  slow=$(printf '%s\n' "$lines" \
    | jq -r 'select(.slow_rule == true) | "\(.rule_id) \(.duration_ms)"' \
    | sort | uniq -c | sort -rn)
  if [[ -z "$slow" ]]; then
    printf '  (no slow rules — all evaluations within budget)\n'
  else
    printf '%s\n' "$slow" | awk '{printf "  %-50s : %d events @ ~%sms\n", $2, $1, $3}'
  fi
}

# ---------------------------------------------------------------------------
# Self-test scenarios.
# ---------------------------------------------------------------------------
make_synthetic_log() {
  local path="$1"
  local kind="$2"
  mkdir -p "$(dirname "$path")"
  case "$kind" in
    empty)
      : > "$path"
      ;;
    fired-only)
      cat > "$path" <<'EOF'
{"schema_version":1,"timestamp":"2026-05-06T10:00:00Z","event_id":"e1","rule_id":"pt-proven-plan-lifecycle-archive","severity":"info","conjectural":false,"verdict":"fired","duration_ms":420,"event":{"event_type":"plan-status-flip","path":"docs/plans/foo.md","metadata":{"status_to":"COMPLETED"}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:01Z","event_id":"e2","rule_id":"pt-proven-plan-lifecycle-archive","severity":"info","conjectural":false,"verdict":"fired","duration_ms":380,"event":{"event_type":"plan-status-flip","path":"docs/plans/bar.md","metadata":{"status_to":"DEFERRED"}}}
EOF
      ;;
    unmatched-only)
      cat > "$path" <<'EOF'
{"schema_version":1,"timestamp":"2026-05-06T10:00:00Z","event_id":"e1","rule_id":null,"verdict":"no-rules-matched","event":{"event_type":"file-deleted","path":"src/foo.ts","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:01Z","event_id":"e2","rule_id":null,"verdict":"no-rules-matched","event":{"event_type":"file-deleted","path":"src/bar.ts","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:02Z","event_id":"e3","rule_id":null,"verdict":"no-rules-matched","event":{"event_type":"session-end","path":"","metadata":{}}}
EOF
      ;;
    mixed)
      cat > "$path" <<'EOF'
{"schema_version":1,"timestamp":"2026-05-06T10:00:00Z","event_id":"e1","rule_id":"pt-3-adr-adoption-fanout","severity":"warning","conjectural":true,"verdict":"fired","duration_ms":420,"event":{"event_type":"decision-record-modified","path":"docs/decisions/001-foo.md","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:01Z","event_id":"e2","rule_id":"pt-3-adr-adoption-fanout","severity":"warning","conjectural":true,"verdict":"fired","duration_ms":380,"event":{"event_type":"decision-record-modified","path":"docs/decisions/002-bar.md","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:02Z","event_id":"e3","rule_id":"pt-3-adr-adoption-fanout","severity":"warning","conjectural":true,"verdict":"fired","duration_ms":410,"event":{"event_type":"decision-record-modified","path":"docs/decisions/003-baz.md","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:03Z","event_id":"e4","rule_id":"some-rule","severity":"info","conjectural":false,"verdict":"unmatched","duration_ms":210,"event":{"event_type":"plan-edit","path":"docs/plans/foo.md","metadata":{}}}
{"schema_version":1,"timestamp":"2026-05-06T10:00:04Z","event_id":"e5","rule_id":null,"verdict":"no-rules-matched","event":{"event_type":"file-deleted","path":"src/x.ts","metadata":{}}}
EOF
      ;;
    with-corrupt)
      cat > "$path" <<'EOF'
{"schema_version":1,"timestamp":"2026-05-06T10:00:00Z","event_id":"e1","rule_id":"pt-proven-plan-lifecycle-archive","severity":"info","conjectural":false,"verdict":"fired","duration_ms":420,"event":{"event_type":"plan-status-flip","path":"docs/plans/foo.md","metadata":{}}}
THIS IS NOT VALID JSON
{"schema_version":1,"timestamp":"2026-05-06T10:00:01Z","event_id":"e2","rule_id":"pt-proven-plan-lifecycle-archive","severity":"info","conjectural":false,"verdict":"fired","duration_ms":380,"event":{"event_type":"plan-status-flip","path":"docs/plans/bar.md","metadata":{}}}
EOF
      ;;
    with-slow)
      cat > "$path" <<'EOF'
{"schema_version":1,"timestamp":"2026-05-06T10:00:00Z","event_id":"e1","rule_id":"slow-rule-1","severity":"info","conjectural":false,"verdict":"fired","duration_ms":1200,"event":{"event_type":"plan-status-flip","path":"docs/plans/foo.md","metadata":{}},"slow_rule":true}
{"schema_version":1,"timestamp":"2026-05-06T10:00:01Z","event_id":"e2","rule_id":"slow-rule-2","severity":"info","conjectural":false,"verdict":"fired","duration_ms":1500,"event":{"event_type":"plan-status-flip","path":"docs/plans/bar.md","metadata":{}},"slow_rule":true}
EOF
      ;;
    *)
      printf 'unknown synthetic kind: %s\n' "$kind" >&2
      return 1
      ;;
  esac
}

run_self_test() {
  local PASSED=0 FAILED=0
  local SELF_PATH
  SELF_PATH="$(realpath "${BASH_SOURCE[0]}")"
  local TMP
  TMP=$(mktemp -d -t analyze-self.XXXX)

  # ----- S1: missing audit log → graceful "no events" -----
  local s1_out
  s1_out=$(bash "$SELF_PATH" summary --audit-log "$TMP/nonexistent.jsonl" 2>&1)
  if printf '%s' "$s1_out" | grep -q "has not fired yet"; then
    printf 'self-test (S1) missing-audit-log-graceful: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S1) missing-audit-log-graceful: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S2: empty audit log → graceful empty message -----
  make_synthetic_log "$TMP/empty.jsonl" empty
  local s2_out
  s2_out=$(bash "$SELF_PATH" summary --audit-log "$TMP/empty.jsonl" 2>&1)
  if printf '%s' "$s2_out" | grep -q "audit log empty"; then
    printf 'self-test (S2) empty-audit-log-graceful: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S2) empty-audit-log-graceful: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S3: fired-only log → summary counts correct -----
  make_synthetic_log "$TMP/fired.jsonl" fired-only
  local s3_out
  s3_out=$(bash "$SELF_PATH" summary --audit-log "$TMP/fired.jsonl" 2>&1)
  if printf '%s' "$s3_out" | grep -q "total entries: 2" \
     && printf '%s' "$s3_out" | grep -q "fired (rule matched + action fired): 2"; then
    printf 'self-test (S3) fired-only-counts: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S3) fired-only-counts: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S4: unmatched events → unmatched cmd reports event types -----
  make_synthetic_log "$TMP/unmatched.jsonl" unmatched-only
  local s4_out
  s4_out=$(bash "$SELF_PATH" unmatched --audit-log "$TMP/unmatched.jsonl" 2>&1)
  if printf '%s' "$s4_out" | grep -q "file-deleted" \
     && printf '%s' "$s4_out" | grep -q "session-end"; then
    printf 'self-test (S4) unmatched-event-types: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S4) unmatched-event-types: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S5: mixed log + cadence cmd reports promotion candidate -----
  make_synthetic_log "$TMP/mixed.jsonl" mixed
  local s5_out
  s5_out=$(bash "$SELF_PATH" cadence --audit-log "$TMP/mixed.jsonl" 2>&1)
  if printf '%s' "$s5_out" | grep -q "pt-3-adr-adoption-fanout" \
     && printf '%s' "$s5_out" | grep -q "promotion"; then
    printf 'self-test (S5) cadence-promotion-candidate: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S5) cadence-promotion-candidate: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S6: corrupt line → continues + warns to stderr -----
  make_synthetic_log "$TMP/corrupt.jsonl" with-corrupt
  local s6_stdout s6_stderr
  s6_stdout=$(bash "$SELF_PATH" summary --audit-log "$TMP/corrupt.jsonl" 2>/dev/null)
  s6_stderr=$(bash "$SELF_PATH" summary --audit-log "$TMP/corrupt.jsonl" 2>&1 >/dev/null)
  if printf '%s' "$s6_stderr" | grep -q "skipping invalid JSONL" \
     && printf '%s' "$s6_stdout" | grep -q "total entries: 2"; then
    printf 'self-test (S6) corrupt-line-skipped-with-warning: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S6) corrupt-line-skipped-with-warning: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S7: slow-rule report -----
  make_synthetic_log "$TMP/slow.jsonl" with-slow
  local s7_out
  s7_out=$(bash "$SELF_PATH" slow --audit-log "$TMP/slow.jsonl" 2>&1)
  if printf '%s' "$s7_out" | grep -q "slow-rule-1" \
     && printf '%s' "$s7_out" | grep -q "slow-rule-2"; then
    printf 'self-test (S7) slow-rule-report: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7) slow-rule-report: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  rm -rf "$TMP"

  printf '\nself-test summary: %d passed, %d failed (of %d scenarios)\n' \
    "$PASSED" "$FAILED" "$((PASSED+FAILED))" >&2
  if [[ "$FAILED" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Top-level dispatch.
# ---------------------------------------------------------------------------
parse_audit_log_flag() {
  AUDIT_LOG_OVERRIDE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --audit-log) AUDIT_LOG_OVERRIDE="$2"; shift 2;;
      *) shift;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    summary|cadence|unmatched|slow)
      parse_audit_log_flag "$@"
      local audit_log
      audit_log=$(resolve_audit_log "$AUDIT_LOG_OVERRIDE")
      "cmd_$cmd" "$audit_log"
      ;;
    --self-test)
      run_self_test
      ;;
    --help|-h|"")
      usage
      ;;
    *)
      printf '%s: unknown subcommand "%s"\n\n' "$SCRIPT_NAME" "$cmd" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
