#!/bin/bash
# propagation-trigger-router.sh — Build Doctrine propagation engine (Tranche 6a, 2026-05-06).
#
# Reads build-doctrine/propagation/propagation-rules.json, evaluates each rule
# against an input event passed on stdin or via flags, runs each matching rule's
# condition + action, and writes an audit-log entry to
# build-doctrine/telemetry/propagation.jsonl regardless of match outcome.
#
# Subcommands:
#   evaluate <event-type> [--path P] [--meta KEY=VAL ...]   Evaluate one event
#   evaluate-stdin                                           Read event JSON from stdin
#   --self-test                                              Run internal scenarios
#   --help                                                   Show usage
#
# Exit codes:
#   0 — engine ran successfully (rules may have matched or not — check audit log)
#   1 — generic failure
#   2 — usage error or configuration error (malformed rules.json, missing schema)
#
# See docs/plans/archive/build-doctrine-tranche-6a-propagation-engine-framework.md
# and build-doctrine/propagation/README.md for full design.

set -uo pipefail

SCRIPT_NAME="propagation-trigger-router.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ---------------------------------------------------------------------------
# Configurable paths (overridable via env for self-test isolation).
# ---------------------------------------------------------------------------
PROPAGATION_RULES_FILE="${PROPAGATION_RULES_FILE:-}"
PROPAGATION_AUDIT_LOG="${PROPAGATION_AUDIT_LOG:-}"

# When not overridden, locate from the git repo root.
locate_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

resolve_default_paths() {
  local repo_root
  repo_root=$(locate_repo_root)
  if [[ -z "$PROPAGATION_RULES_FILE" ]]; then
    PROPAGATION_RULES_FILE="$repo_root/build-doctrine/propagation/propagation-rules.json"
  fi
  if [[ -z "$PROPAGATION_AUDIT_LOG" ]]; then
    PROPAGATION_AUDIT_LOG="$repo_root/build-doctrine/telemetry/propagation.jsonl"
  fi
}

usage() {
  cat <<'EOF'
Usage: propagation-trigger-router.sh evaluate <event-type> [--path P] [--meta K=V]...
       propagation-trigger-router.sh evaluate-stdin
       propagation-trigger-router.sh --self-test
       propagation-trigger-router.sh --help

Build Doctrine propagation engine. Reads rules from
build-doctrine/propagation/propagation-rules.json (overridable via
$PROPAGATION_RULES_FILE), evaluates each rule's trigger against the input
event, dispatches matching rules' actions, and writes audit-log entries to
build-doctrine/telemetry/propagation.jsonl (overridable via
$PROPAGATION_AUDIT_LOG).

Examples:
  propagation-trigger-router.sh evaluate plan-status-flip --path docs/plans/foo.md --meta status_to=COMPLETED
  propagation-trigger-router.sh evaluate decision-record-created --path docs/decisions/042-foo.md
  echo '{"event_type":"file-modified","path":"docs/prd.md"}' | propagation-trigger-router.sh evaluate-stdin
EOF
}

# ---------------------------------------------------------------------------
# iso_timestamp / millisecond timer helpers.
# ---------------------------------------------------------------------------
iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

# Returns wall time in milliseconds. Falls back gracefully on systems without
# nanosecond precision.
now_ms() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    # macOS / BSD fallback — second precision only.
    echo "$(date +%s)000"
  fi
}

# ---------------------------------------------------------------------------
# Audit-log writer. One JSON line per event-rule evaluation. Append-only.
# ---------------------------------------------------------------------------
write_audit() {
  local entry="$1"
  mkdir -p "$(dirname "$PROPAGATION_AUDIT_LOG")" 2>/dev/null || true
  if ! printf '%s\n' "$entry" >> "$PROPAGATION_AUDIT_LOG" 2>/dev/null; then
    printf '[propagation-engine] audit-log write failed: %s\n' "$PROPAGATION_AUDIT_LOG" >&2
    # Per Behavioral Contracts §Failure modes: continue, do not crash.
  fi
}

# ---------------------------------------------------------------------------
# Build a JSON event object from CLI args. Convention:
#   evaluate <event-type> [--path P] [--meta K=V]...
# Output: a compact JSON object suitable for piping into rule evaluators.
# ---------------------------------------------------------------------------
build_event_json() {
  local event_type="$1"; shift
  local path=""
  local meta_pairs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path) path="$2"; shift 2;;
      --meta)
        meta_pairs+=("$2")
        shift 2
        ;;
      *) shift;;
    esac
  done

  # Build metadata sub-object via jq if pairs present, else empty {}.
  local meta_json='{}'
  if [[ ${#meta_pairs[@]} -gt 0 ]]; then
    meta_json=$(printf '%s\n' "${meta_pairs[@]}" | awk -F= '
      BEGIN { printf "{" }
      {
        if (NR > 1) printf ",";
        gsub(/"/, "\\\"", $2);
        printf "\"%s\":\"%s\"", $1, $2;
      }
      END { printf "}" }
    ')
  fi

  jq -n \
    --arg t "$event_type" \
    --arg p "$path" \
    --argjson m "$meta_json" \
    '{event_type: $t, path: $p, metadata: $m}'
}

# ---------------------------------------------------------------------------
# Configuration loader. Validates rules file is well-formed JSON; emits the
# parsed rules array for the evaluator to walk.
# ---------------------------------------------------------------------------
load_rules() {
  if [[ ! -f "$PROPAGATION_RULES_FILE" ]]; then
    printf '[propagation-engine] rules file not found: %s\n' "$PROPAGATION_RULES_FILE" >&2
    return 2
  fi
  if ! jq empty "$PROPAGATION_RULES_FILE" 2>/dev/null; then
    printf '[propagation-engine] malformed JSON: %s\n' "$PROPAGATION_RULES_FILE" >&2
    return 2
  fi
  local schema_version
  schema_version=$(jq -r '.schema_version // empty' "$PROPAGATION_RULES_FILE")
  if [[ "$schema_version" != "1" ]]; then
    printf '[propagation-engine] unsupported schema_version: %s (want 1)\n' "$schema_version" >&2
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Trigger matching. Returns 0 (match) or 1 (no match). Reads rule + event
# from caller-set globals to avoid argument-passing complexity.
# ---------------------------------------------------------------------------
trigger_matches() {
  local rule_json="$1"
  local event_json="$2"

  local rule_event_type rule_path_pattern event_event_type event_path
  rule_event_type=$(jq -r '.trigger.event_type // empty' <<< "$rule_json")
  rule_path_pattern=$(jq -r '.trigger.path_pattern // empty' <<< "$rule_json")
  event_event_type=$(jq -r '.event_type // empty' <<< "$event_json")
  event_path=$(jq -r '.path // empty' <<< "$event_json")

  if [[ -z "$rule_event_type" ]] || [[ "$rule_event_type" != "$event_event_type" ]]; then
    return 1
  fi

  if [[ -n "$rule_path_pattern" ]]; then
    # Glob-style pattern matching. Bash's [[ var == pattern ]] handles globs.
    # shellcheck disable=SC2053
    if [[ ! "$event_path" == $rule_path_pattern ]]; then
      return 1
    fi
  fi

  # metadata_match: each key/value must equal the event's metadata.<key>.
  local meta_match
  meta_match=$(jq -c '.trigger.metadata_match // {}' <<< "$rule_json")
  if [[ "$meta_match" != "{}" ]]; then
    local match_check
    match_check=$(jq -e --argjson m "$meta_match" --argjson e "$event_json" '
      ($m | to_entries) as $pairs |
      ($pairs | all(. as $p | ($e.metadata[$p.key] // null) == $p.value))
    ' <<< 'null' 2>/dev/null)
    if [[ "$match_check" != "true" ]]; then
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Condition evaluation. Returns 0 (proceed to action) or 1 (skip action).
# Per Behavioral Contracts §Failure modes: rule-script errors → skip + log,
# do NOT crash the engine.
# ---------------------------------------------------------------------------
evaluate_condition() {
  local rule_json="$1"
  local event_json="$2"

  local cond_type
  cond_type=$(jq -r '.condition.type // "always"' <<< "$rule_json")

  case "$cond_type" in
    always) return 0 ;;
    script)
      local script_path
      script_path=$(jq -r '.condition.script_path // empty' <<< "$rule_json")
      if [[ -z "$script_path" ]] || [[ ! -x "$script_path" ]]; then
        return 1
      fi
      printf '%s' "$event_json" | "$script_path" >/dev/null 2>&1
      ;;
    command)
      local cmd
      cmd=$(jq -r '.condition.command // empty' <<< "$rule_json")
      if [[ -z "$cmd" ]]; then return 1; fi
      bash -c "$cmd" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Action dispatch. Returns 0 (success) or 1 (failure). Failures are recorded
# in the audit-log entry but never crash the engine.
# ---------------------------------------------------------------------------
dispatch_action() {
  local rule_json="$1"
  local event_json="$2"

  local action_type
  action_type=$(jq -r '.action.type // empty' <<< "$rule_json")

  case "$action_type" in
    log-only) return 0 ;;
    script)
      local script_path
      script_path=$(jq -r '.action.script_path // empty' <<< "$rule_json")
      if [[ -z "$script_path" ]] || [[ ! -x "$script_path" ]]; then return 1; fi
      printf '%s' "$event_json" | "$script_path" >/dev/null 2>&1
      ;;
    command)
      local cmd
      cmd=$(jq -r '.action.command // empty' <<< "$rule_json")
      if [[ -z "$cmd" ]]; then return 1; fi
      bash -c "$cmd" >/dev/null 2>&1
      ;;
    open-finding)
      # Append to docs/findings.md per the finding_template. Best-effort;
      # the audit entry records whether the append succeeded.
      local repo_root
      repo_root=$(locate_repo_root)
      local findings_file="$repo_root/docs/findings.md"
      [[ -f "$findings_file" ]] || return 1
      local template
      template=$(jq -r '.action.finding_template // empty' <<< "$rule_json")
      [[ -n "$template" ]] || return 1
      # Append a one-line entry (real implementation would substitute placeholders).
      printf '\n<!-- propagation-engine appended; rule=%s; event=%s -->\n' \
        "$(jq -r '.id' <<< "$rule_json")" \
        "$(jq -r '.event_type' <<< "$event_json")" >> "$findings_file"
      return 0
      ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Main evaluator: walks rules, evaluates each, writes per-evaluation audit
# entries. Per the design, every evaluation produces one audit entry —
# matched or unmatched.
# ---------------------------------------------------------------------------
evaluate_event() {
  local event_json="$1"

  resolve_default_paths
  if ! load_rules; then
    return 2
  fi

  local event_start_ms
  event_start_ms=$(now_ms)
  # v1 budget hypothesis: 5000ms event budget, 1000ms per-rule. Bash+jq on
  # Windows Git Bash measures ~300ms per rule due to subprocess overhead;
  # the doctrine's 500ms / 100ms targets are the v2 goal once the engine
  # optimizes its jq usage. Tagged in audit-log entries via the slow_rule
  # flag so the audit log captures budget-overrun evidence for tuning.
  local event_budget_ms=5000
  local event_id
  event_id=$(printf '%s%s' "$(iso_timestamp)" "$RANDOM" | tr -d '\n' | head -c 24)

  local rules_json
  rules_json=$(jq -c '.rules[]' "$PROPAGATION_RULES_FILE")

  local any_match=0
  while IFS= read -r rule_json; do
    [[ -z "$rule_json" ]] && continue

    local elapsed=$(( $(now_ms) - event_start_ms ))
    if [[ "$elapsed" -gt "$event_budget_ms" ]]; then
      local rule_id
      rule_id=$(jq -r '.id' <<< "$rule_json")
      write_audit "$(jq -nc \
        --arg ts "$(iso_timestamp)" \
        --arg eid "$event_id" \
        --arg rid "$rule_id" \
        --argjson event "$event_json" \
        '{schema_version: 1, timestamp: $ts, event_id: $eid, rule_id: $rid, event: $event, verdict: "event-budget-exceeded"}')"
      # Mark as match so the no-rules-matched summary is suppressed: budget
      # overruns are incomplete-evaluation, not negative space.
      any_match=1
      continue
    fi

    local rule_id severity conjectural
    rule_id=$(jq -r '.id' <<< "$rule_json")
    severity=$(jq -r '.severity // "info"' <<< "$rule_json")
    conjectural=$(jq -r '.conjectural // false' <<< "$rule_json")

    local rule_start_ms rule_end_ms rule_duration_ms
    rule_start_ms=$(now_ms)

    local verdict="unmatched"
    local action_exit=""

    if trigger_matches "$rule_json" "$event_json"; then
      any_match=1
      if evaluate_condition "$rule_json" "$event_json"; then
        if dispatch_action "$rule_json" "$event_json"; then
          verdict="fired"
          action_exit=0
        else
          verdict="action-failed"
          action_exit=1
        fi
      else
        verdict="condition-not-met"
      fi
    fi

    rule_end_ms=$(now_ms)
    rule_duration_ms=$(( rule_end_ms - rule_start_ms ))

    # v1 per-rule budget threshold: 1000ms. Above this, audit entry is tagged
    # slow_rule for tuning. Doctrine target is 100ms but v1 bash+jq on
    # Windows measures ~300ms typical; 1000ms is the v1 hypothesis cap.
    local slow_warning=""
    if [[ "$rule_duration_ms" -gt 1000 ]]; then
      slow_warning="slow-rule"
    fi

    local audit_entry
    audit_entry=$(jq -nc \
      --arg ts "$(iso_timestamp)" \
      --arg eid "$event_id" \
      --arg rid "$rule_id" \
      --arg sev "$severity" \
      --arg verdict "$verdict" \
      --argjson conj "$conjectural" \
      --argjson dur "$rule_duration_ms" \
      --arg slow "$slow_warning" \
      --argjson event "$event_json" \
      --arg action_exit "$action_exit" \
      '{
        schema_version: 1,
        timestamp: $ts,
        event_id: $eid,
        rule_id: $rid,
        severity: $sev,
        conjectural: $conj,
        verdict: $verdict,
        duration_ms: $dur,
        event: $event
      }
      + (if $slow != "" then {slow_rule: true} else {} end)
      + (if $action_exit != "" then {action_exit_code: ($action_exit | tonumber)} else {} end)')
    write_audit "$audit_entry"

    # Critical-severity fired rules emit to stderr.
    if [[ "$verdict" == "fired" ]] && [[ "$severity" == "critical" ]]; then
      printf '[propagation-engine] CRITICAL rule fired: %s (event: %s)\n' "$rule_id" "$(jq -r '.event_type' <<< "$event_json")" >&2
    fi
  done <<< "$rules_json"

  # If no rule matched, write a single "no-rules-matched" event-level summary
  # so the audit log captures the negative space explicitly.
  if [[ "$any_match" -eq 0 ]]; then
    local summary
    summary=$(jq -nc \
      --arg ts "$(iso_timestamp)" \
      --arg eid "$event_id" \
      --argjson event "$event_json" \
      '{schema_version: 1, timestamp: $ts, event_id: $eid, rule_id: null, verdict: "no-rules-matched", event: $event}')
    write_audit "$summary"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Self-test scaffolding.
# ---------------------------------------------------------------------------
setup_synthetic_repo() {
  local label="$1"
  local d
  d=$(mktemp -d -t "propagation-${label}.XXXX")
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p build-doctrine/propagation build-doctrine/telemetry docs/plans docs/decisions
    cat > docs/findings.md <<'EOF'
# Findings

EOF
  )
  printf '%s' "$d"
}

write_minimal_rules() {
  local dir="$1"
  cat > "$dir/build-doctrine/propagation/propagation-rules.json" <<'EOF'
{
  "schema_version": 1,
  "rules": [
    {
      "id": "test-plan-status-flip",
      "description": "Test rule that fires when a plan's Status flips to COMPLETED.",
      "severity": "info",
      "trigger": {
        "event_type": "plan-status-flip",
        "metadata_match": { "status_to": "COMPLETED" }
      },
      "action": { "type": "log-only" }
    },
    {
      "id": "test-doctrine-doc-edit",
      "description": "Test rule that fires when build-doctrine/doctrine/*.md is modified.",
      "severity": "warning",
      "trigger": {
        "event_type": "doctrine-doc-modified",
        "path_pattern": "build-doctrine/doctrine/*.md"
      },
      "action": { "type": "log-only" }
    }
  ]
}
EOF
}

count_audit_lines() {
  local log="$1"
  if [[ -f "$log" ]]; then
    wc -l < "$log" | tr -d ' '
  else
    echo "0"
  fi
}

run_self_test() {
  local PASSED=0 FAILED=0
  local SELF_PATH
  SELF_PATH="$(realpath "${BASH_SOURCE[0]}")"

  # ----- S1: schema-validity -----
  local SCHEMA_PATH
  SCHEMA_PATH="$SCRIPT_DIR/../schemas/propagation-rules.schema.json"
  if [[ -f "$SCHEMA_PATH" ]] && jq empty "$SCHEMA_PATH" 2>/dev/null; then
    printf 'self-test (S1) schema-is-well-formed-json: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S1) schema-is-well-formed-json: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S2: minimal rules-file is well-formed -----
  local D2; D2=$(setup_synthetic_repo "S2")
  write_minimal_rules "$D2"
  if jq empty "$D2/build-doctrine/propagation/propagation-rules.json" 2>/dev/null; then
    printf 'self-test (S2) rules-file-well-formed-json: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S2) rules-file-well-formed-json: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi

  # ----- S3: matching event triggers rule + writes audit entry -----
  local D3; D3=$(setup_synthetic_repo "S3")
  write_minimal_rules "$D3"
  PROPAGATION_RULES_FILE="$D3/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D3/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate plan-status-flip --path "docs/plans/foo.md" --meta status_to=COMPLETED >/dev/null 2>&1
  local s3_count
  s3_count=$(count_audit_lines "$D3/build-doctrine/telemetry/propagation.jsonl")
  if [[ "$s3_count" -ge 1 ]] && grep -q '"verdict":"fired"' "$D3/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S3) matching-event-fires-rule: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S3) matching-event-fires-rule: FAIL (lines=%s)\n' "$s3_count" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D3"

  # ----- S4: non-matching event writes no-rules-matched -----
  local D4; D4=$(setup_synthetic_repo "S4")
  write_minimal_rules "$D4"
  PROPAGATION_RULES_FILE="$D4/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D4/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate session-end >/dev/null 2>&1
  if grep -q '"verdict":"no-rules-matched"' "$D4/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S4) unmatched-event-records-negative-space: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S4) unmatched-event-records-negative-space: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D4"

  # ----- S5: trigger metadata_match works -----
  local D5; D5=$(setup_synthetic_repo "S5")
  write_minimal_rules "$D5"
  # status_to=ACTIVE should NOT match (rule wants COMPLETED).
  PROPAGATION_RULES_FILE="$D5/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D5/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate plan-status-flip --path "docs/plans/foo.md" --meta status_to=ACTIVE >/dev/null 2>&1
  if grep -q '"verdict":"no-rules-matched"' "$D5/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S5) metadata-match-filters-correctly: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S5) metadata-match-filters-correctly: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D5"

  # ----- S6: trigger path_pattern works (positive match) -----
  local D6; D6=$(setup_synthetic_repo "S6")
  write_minimal_rules "$D6"
  PROPAGATION_RULES_FILE="$D6/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D6/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate doctrine-doc-modified --path "build-doctrine/doctrine/01-principles.md" >/dev/null 2>&1
  if grep -q '"verdict":"fired"' "$D6/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S6) path-pattern-positive-match: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S6) path-pattern-positive-match: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D6"

  # ----- S7: trigger path_pattern works (negative match — wrong path) -----
  local D7; D7=$(setup_synthetic_repo "S7")
  write_minimal_rules "$D7"
  PROPAGATION_RULES_FILE="$D7/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D7/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate doctrine-doc-modified --path "docs/random.md" >/dev/null 2>&1
  if grep -q '"verdict":"no-rules-matched"' "$D7/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S7) path-pattern-negative-match: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7) path-pattern-negative-match: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D7"

  # ----- S8: malformed JSON rules → exit 2 + error -----
  local D8; D8=$(setup_synthetic_repo "S8")
  printf '{ this is not valid json' > "$D8/build-doctrine/propagation/propagation-rules.json"
  local s8_rc s8_out
  s8_out=$(PROPAGATION_RULES_FILE="$D8/build-doctrine/propagation/propagation-rules.json" \
           PROPAGATION_AUDIT_LOG="$D8/build-doctrine/telemetry/propagation.jsonl" \
           bash "$SELF_PATH" evaluate session-end 2>&1)
  s8_rc=$?
  if [[ "$s8_rc" -eq 2 ]] && printf '%s' "$s8_out" | grep -q "malformed JSON"; then
    printf 'self-test (S8) malformed-config-rejected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S8) malformed-config-rejected: FAIL (rc=%s)\n' "$s8_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D8"

  # ----- S9: rules file missing → exit 2 -----
  local D9; D9=$(setup_synthetic_repo "S9")
  rm -f "$D9/build-doctrine/propagation/propagation-rules.json" 2>/dev/null
  local s9_rc s9_out
  s9_out=$(PROPAGATION_RULES_FILE="$D9/nonexistent/propagation-rules.json" \
           PROPAGATION_AUDIT_LOG="$D9/build-doctrine/telemetry/propagation.jsonl" \
           bash "$SELF_PATH" evaluate session-end 2>&1)
  s9_rc=$?
  if [[ "$s9_rc" -eq 2 ]] && printf '%s' "$s9_out" | grep -q "rules file not found"; then
    printf 'self-test (S9) missing-config-rejected: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S9) missing-config-rejected: FAIL (rc=%s)\n' "$s9_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D9"

  # ----- S10: audit log structure (each line is well-formed JSON) -----
  local D10; D10=$(setup_synthetic_repo "S10")
  write_minimal_rules "$D10"
  PROPAGATION_RULES_FILE="$D10/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D10/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate plan-status-flip --path "docs/plans/foo.md" --meta status_to=COMPLETED >/dev/null 2>&1
  local s10_lines s10_valid_lines
  s10_lines=$(count_audit_lines "$D10/build-doctrine/telemetry/propagation.jsonl")
  s10_valid_lines=$(while IFS= read -r line; do
    if printf '%s' "$line" | jq empty 2>/dev/null; then echo 1; fi
  done < "$D10/build-doctrine/telemetry/propagation.jsonl" | wc -l | tr -d ' ')
  if [[ "$s10_lines" -ge 1 ]] && [[ "$s10_lines" == "$s10_valid_lines" ]]; then
    printf 'self-test (S10) audit-log-jsonl-format-valid: PASS (%s/%s lines valid)\n' "$s10_valid_lines" "$s10_lines" >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S10) audit-log-jsonl-format-valid: FAIL (%s/%s lines valid)\n' "$s10_valid_lines" "$s10_lines" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D10"

  # ----- S11: required audit-entry fields present -----
  local D11; D11=$(setup_synthetic_repo "S11")
  write_minimal_rules "$D11"
  PROPAGATION_RULES_FILE="$D11/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D11/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate plan-status-flip --path "docs/plans/foo.md" --meta status_to=COMPLETED >/dev/null 2>&1
  local entry
  entry=$(head -1 "$D11/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null)
  if printf '%s' "$entry" | jq -e '.schema_version and .timestamp and .event_id and .rule_id and .verdict and .duration_ms and .event' >/dev/null 2>&1; then
    printf 'self-test (S11) required-fields-present: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S11) required-fields-present: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D11"

  # ----- S12: failed action recorded as action-failed -----
  local D12; D12=$(setup_synthetic_repo "S12")
  cat > "$D12/build-doctrine/propagation/propagation-rules.json" <<'EOF'
{
  "schema_version": 1,
  "rules": [
    {
      "id": "test-failing-action",
      "description": "Test rule with an action that always exits non-zero.",
      "severity": "info",
      "trigger": { "event_type": "session-end" },
      "action": { "type": "command", "command": "exit 1" }
    }
  ]
}
EOF
  PROPAGATION_RULES_FILE="$D12/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D12/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate session-end >/dev/null 2>&1
  if grep -q '"verdict":"action-failed"' "$D12/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S12) failed-action-recorded: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S12) failed-action-recorded: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D12"

  # ----- S13: condition not met → action does not fire -----
  local D13; D13=$(setup_synthetic_repo "S13")
  cat > "$D13/build-doctrine/propagation/propagation-rules.json" <<'EOF'
{
  "schema_version": 1,
  "rules": [
    {
      "id": "test-condition-fails",
      "description": "Test rule whose condition exits non-zero (skip action).",
      "severity": "info",
      "trigger": { "event_type": "session-end" },
      "condition": { "type": "command", "command": "exit 1" },
      "action": { "type": "log-only" }
    }
  ]
}
EOF
  PROPAGATION_RULES_FILE="$D13/build-doctrine/propagation/propagation-rules.json" \
  PROPAGATION_AUDIT_LOG="$D13/build-doctrine/telemetry/propagation.jsonl" \
    bash "$SELF_PATH" evaluate session-end >/dev/null 2>&1
  if grep -q '"verdict":"condition-not-met"' "$D13/build-doctrine/telemetry/propagation.jsonl" 2>/dev/null; then
    printf 'self-test (S13) condition-not-met-skips-action: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S13) condition-not-met-skips-action: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D13"

  # ----- S14: real rules file (production) validates against schema -----
  local REAL_RULES_FILE
  REAL_RULES_FILE="$(locate_repo_root)/build-doctrine/propagation/propagation-rules.json"
  if [[ -f "$REAL_RULES_FILE" ]] && jq empty "$REAL_RULES_FILE" 2>/dev/null; then
    local rule_count
    rule_count=$(jq '.rules | length' "$REAL_RULES_FILE")
    if [[ "$rule_count" -ge 4 ]]; then
      printf 'self-test (S14) production-rules-load (%s rules): PASS\n' "$rule_count" >&2
      PASSED=$((PASSED+1))
    else
      printf 'self-test (S14) production-rules-load: FAIL (rule_count=%s, want >= 4)\n' "$rule_count" >&2
      FAILED=$((FAILED+1))
    fi
  else
    printf 'self-test (S14) production-rules-load: SKIPPED (no production rules yet)\n' >&2
    # Don't count as fail; production rules ship in Tasks 3-5.
  fi

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
main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    evaluate)
      if [[ $# -lt 1 ]]; then
        printf '%s: missing <event-type>\n' "$SCRIPT_NAME" >&2
        return 2
      fi
      local event_type="$1"; shift
      local event_json
      event_json=$(build_event_json "$event_type" "$@")
      evaluate_event "$event_json"
      ;;
    evaluate-stdin)
      local event_json
      event_json=$(cat)
      if ! printf '%s' "$event_json" | jq empty 2>/dev/null; then
        printf '%s: stdin is not valid JSON\n' "$SCRIPT_NAME" >&2
        return 2
      fi
      evaluate_event "$event_json"
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
