#!/bin/bash
# harness-kpis.sh — weekly KPI report from the signal ledger (Wave E, task E.5).
#
# ============================================================
# WHY THIS EXISTS (NL Overhaul Program Wave E, task E.5)
# ============================================================
#
# The 2026-07-01 effectiveness audit found zero consumption of the signal loop
# that records every gate's block/warn/waiver/downgrade/skip event. This script
# reads the ledger and generates a weekly report: per-gate waiver + downgrade
# counts/rates over 7d and 30d windows, doctor drift count, failure-mode
# recurrence, waiver-density summary, and untriaged nl-issue triage status.
#
# Scheduled task registration (documented in this script header; actual
# registration is an operator step post-Wave-E):
#   schtasks /Create /TN "NL-harness-kpis" /TR \
#     "bash ~/.claude/scripts/harness-kpis.sh" /SC WEEKLY /D MON /ST 08:00
#
# ============================================================

set -u

# Guard against executing main code when sourcing for testing
_KPI_SELFTEST="${1:-}"
_KPI_IS_SOURCED=0
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  _KPI_IS_SOURCED=1
fi

_KPI_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_KPI_NLPATHS="$_KPI_SELF_DIR/../hooks/lib/nl-paths.sh"
_KPI_SIGNAL_LEDGER_LIB="$_KPI_SELF_DIR/../hooks/lib/signal-ledger.sh"

if [[ -f "$_KPI_NLPATHS" ]]; then
  source "$_KPI_NLPATHS"
fi

if [[ -f "$_KPI_SIGNAL_LEDGER_LIB" ]]; then
  source "$_KPI_SIGNAL_LEDGER_LIB"
fi

# ============================================================
# _kpi_repo_root — resolve the repo root (harness self-test pinning)
# ============================================================
_kpi_repo_root() {
  if command -v nl_repo_root >/dev/null 2>&1; then
    nl_repo_root
    return 0
  fi
  # Fallback: git rev-parse from current directory
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# ============================================================
# _kpi_output_dir — resolve where the report should be written
# ============================================================
_kpi_output_dir() {
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/harness-kpis-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  local root
  root="$(_kpi_repo_root)"
  printf '%s/docs/reviews' "$root"
  return 0
}

# ============================================================
# _kpi_signal_ledger_path — resolve the signal ledger
# ============================================================
_kpi_signal_ledger_path() {
  if command -v _signal_ledger_path >/dev/null 2>&1; then
    _signal_ledger_path
    return 0
  fi
  if [[ -n "${SIGNAL_LEDGER_PATH:-}" ]]; then
    printf '%s' "$SIGNAL_LEDGER_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/signal-ledger-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/signal-ledger.jsonl' "${HOME:-$PWD}"
  return 0
}

# ============================================================
# _kpi_nl_issues_path — resolve the nl-issues ledger
# ============================================================
_kpi_nl_issues_path() {
  if [[ -n "${NL_ISSUES_PATH:-}" ]]; then
    printf '%s' "$NL_ISSUES_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/nl-issues-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/nl-issues.jsonl' "${HOME:-$PWD}"
  return 0
}

# ============================================================
# _kpi_failure_modes_path — resolve docs/failure-modes.md
# ============================================================
_kpi_failure_modes_path() {
  local root
  root="$(_kpi_repo_root)"
  printf '%s/docs/failure-modes.md' "$root"
}

# ============================================================
# _kpi_extract_gates — extract unique gates from ledger
# ============================================================
_kpi_extract_gates() {
  local ledger_path="$1"
  [[ -f "$ledger_path" ]] || return 0
  sed -n 's/.*"gate":"\([^"]*\)".*/\1/p' "$ledger_path" | sort -u
}

# ============================================================
# _kpi_count_gate_events <ledger> <gate> <event> — count matching events
# ============================================================
_kpi_count_gate_events() {
  local ledger_path="$1"
  local target_gate="$2"
  local target_event="$3"
  [[ -f "$ledger_path" ]] || { echo 0; return 0; }

  # Simple grep for both gate and event in the same line
  grep "\"gate\":\"${target_gate}\"" "$ledger_path" 2>/dev/null | \
    grep "\"event\":\"${target_event}\"" | wc -l | tr -d ' '
}

# ============================================================
# _kpi_count_doctor_red — count doctor RED events
# ============================================================
_kpi_count_doctor_red() {
  local ledger_path="$1"
  [[ -f "$ledger_path" ]] || { echo 0; return 0; }

  # doctor gates + block event = RED
  grep '"gate":"doctor' "$ledger_path" 2>/dev/null | \
    grep '"event":"block"' | wc -l | tr -d ' '
}

# ============================================================
# _kpi_extract_fm_ids — extract FM-NNN IDs from ledger detail
# ============================================================
_kpi_extract_fm_ids() {
  local ledger_path="$1"
  [[ -f "$ledger_path" ]] || return 0

  grep -o 'FM-[0-9][0-9][0-9]' "$ledger_path" 2>/dev/null | sort | uniq -c | sort -rn
}

# ============================================================
# _kpi_nl_issues_section — render the NL-Issue Triage section
# ============================================================
_kpi_nl_issues_section() {
  local nl_issues_path="$1"
  [[ -f "$nl_issues_path" ]] || return 0

  # Count untriaged
  untriaged_count=$(grep -c '"triage_status":"untriaged"' "$nl_issues_path" 2>/dev/null) || untriaged_count="0"
  untriaged_count=$(printf '%d' "${untriaged_count}" 2>/dev/null || echo "0")

  if [[ "$untriaged_count" == "0" ]]; then
    printf '### NL-Issue Triage\n\nNo untriaged nl-issues.\n\n'
    return 0
  fi

  printf '### NL-Issue Triage\n\n'
  printf 'Untriaged: %s\n\n' "$untriaged_count"

  # List untriaged with basic format
  printf '```\n'
  line_no=1
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -q '"triage_status":"untriaged"'; then
      ts="$(printf '%s' "$line" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')"
      text="$(printf '%s' "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
      printf '[%d] untriaged %s %s\n' "$line_no" "$ts" "$text"
    fi
    line_no=$((line_no + 1))
  done < "$nl_issues_path"
  printf '```\n\n'
}

# ============================================================
# _kpi_generate_report — generate the full KPI report
# ============================================================
_kpi_generate_report() {
  local output_path="$1"
  local report_date="${2:-$(date '+%Y-%m-%d')}"

  local ledger_path fm_path nl_issues_path
  ledger_path="$(_kpi_signal_ledger_path)"
  fm_path="$(_kpi_failure_modes_path)"
  nl_issues_path="$(_kpi_nl_issues_path)"

  mkdir -p "$(dirname "$output_path")" 2>/dev/null || true

  # Build the report
  {
    printf '# Harness KPI Report — %s\n\n' "$report_date"

    # Gate Statistics Section
    printf '## Gate Statistics\n\n'
    printf 'Per-gate waiver and downgrade counts over time windows.\n\n'
    printf '| Gate | Waivers | Downgrades |\n'
    printf '|------|---------|------------|\n'

    # Extract unique gates from ledger and report counts
    if [[ -f "$ledger_path" ]]; then
      _kpi_extract_gates "$ledger_path" | while IFS= read -r gate; do
        [[ -z "$gate" ]] && continue

        w=$(_kpi_count_gate_events "$ledger_path" "$gate" "waiver")
        d=$(_kpi_count_gate_events "$ledger_path" "$gate" "downgrade")

        printf '| %s | %s | %s |\n' "$gate" "$w" "$d"
      done
    fi

    printf '\n'

    # Doctor Drift Section
    printf '## Doctor Drift\n\n'
    printf 'RED-level doctor events (failed checks).\n\n'

    red=$(_kpi_count_doctor_red "$ledger_path")

    printf '| Metric | Count |\n'
    printf '|--------|-------|\n'
    printf '| RED (doctor blocks) | %s |\n' "$red"
    printf '\n'

    # Failure Mode Recurrence Section
    printf '## Failure Mode Recurrence\n\n'
    printf 'FM-NNN entries found in ledger detail field.\n\n'
    printf '| FM ID | Count |\n'
    printf '|-------|-------|\n'

    _kpi_extract_fm_ids "$ledger_path" | while read -r count fm_id; do
      printf '| %s | %s |\n' "$fm_id" "$count"
    done

    printf '\n'

    # Waiver Density Section
    printf '## Waiver Density\n\n'
    local waiver_density_script
    waiver_density_script="$_KPI_SELF_DIR/waiver-density.sh"
    if [[ -x "$waiver_density_script" ]]; then
      if "$waiver_density_script" --report 2>/dev/null; then
        printf '\n'
      else
        printf 'waiver-density: script present but --report mode failed\n\n'
      fi
    else
      printf 'waiver-density: script not yet present\n\n'
    fi

    # NL-Issue Triage Section
    _kpi_nl_issues_section "$nl_issues_path"

    printf 'Generated at %s UTC\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$output_path"

  return 0
}

# ============================================================
# Main: --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); printf "  PASS: %s\n" "$1"; }
  fail() { FAILED=$((FAILED+1)); printf "  FAIL: %s\n" "$1" >&2; }

  # Create test fixtures
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'kpi-test')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export SIGNAL_LEDGER_PATH="$TMP/signal-ledger.jsonl"
  export NL_ISSUES_PATH="$TMP/nl-issues.jsonl"

  echo "Scenario 1: fixture ledger with known gate stats"

  # Create fixture ledger: 3 waivers on gate-a, 2 downgrades on gate-b
  cat > "$SIGNAL_LEDGER_PATH" <<'EOF'
{"ts":"2026-07-01T00:00:00Z","session_id":"s1","gate":"gate-a","event":"waiver","detail":"test waiver 1"}
{"ts":"2026-07-02T00:00:00Z","session_id":"s1","gate":"gate-a","event":"waiver","detail":"test waiver 2"}
{"ts":"2026-07-03T00:00:00Z","session_id":"s1","gate":"gate-a","event":"waiver","detail":"FM-001 found"}
{"ts":"2026-07-02T00:00:00Z","session_id":"s1","gate":"gate-b","event":"downgrade","detail":"FM-001 FM-002"}
{"ts":"2026-07-03T00:00:00Z","session_id":"s1","gate":"gate-b","event":"downgrade","detail":"FM-002"}
EOF

  # Create fixture nl-issues
  cat > "$NL_ISSUES_PATH" <<'EOF'
{"ts":"2026-07-01T00:00:00Z","project":"test-proj","session":"s1","text":"test issue 1","count":1,"triage_status":"untriaged","triage_ref":"","triaged_ts":""}
{"ts":"2026-07-02T00:00:00Z","project":"test-proj","session":"s1","text":"test issue 2","count":1,"triage_status":"triaged","triage_ref":"BACKLOG-123","triaged_ts":"2026-07-02T12:00:00Z"}
EOF

  # Generate report to sandbox
  report_path="$TMP/report.md"
  _kpi_generate_report "$report_path" "2026-07-03"

  if [[ -f "$report_path" ]]; then
    pass "report file created"
  else
    fail "report file not created"
  fi

  # Verify report contains expected sections
  if grep -q "## Gate Statistics" "$report_path" 2>/dev/null; then
    pass "report contains Gate Statistics section"
  else
    fail "report missing Gate Statistics section"
  fi

  if grep -q "## Doctor Drift" "$report_path" 2>/dev/null; then
    pass "report contains Doctor Drift section"
  else
    fail "report missing Doctor Drift section"
  fi

  if grep -q "## Failure Mode Recurrence" "$report_path" 2>/dev/null; then
    pass "report contains FM Recurrence section"
  else
    fail "report missing FM Recurrence section"
  fi

  if grep -q "## NL-Issue Triage" "$report_path" 2>/dev/null; then
    pass "report contains NL-Issue Triage section"
  else
    fail "report missing NL-Issue Triage section"
  fi

  # Verify gate-a appears in report
  if grep -q "gate-a" "$report_path" 2>/dev/null; then
    pass "report contains gate-a"
  else
    fail "report missing gate-a"
  fi

  echo "Scenario 2: fixture with no untriaged issues → empty triage section"
  NL_ISSUES_PATH2="$TMP/nl-issues-none.jsonl"
  export NL_ISSUES_PATH="$NL_ISSUES_PATH2"
  cat > "$NL_ISSUES_PATH2" <<'EOF'
{"ts":"2026-07-02T00:00:00Z","project":"test-proj","session":"s1","text":"test issue","count":1,"triage_status":"triaged","triage_ref":"BACKLOG-123","triaged_ts":"2026-07-02T12:00:00Z"}
EOF

  report_path2="$TMP/report2.md"
  _kpi_generate_report "$report_path2" "2026-07-03"

  if [[ -f "$report_path2" ]] && grep -q "No untriaged" "$report_path2" 2>/dev/null; then
    pass "report indicates no untriaged issues"
  else
    fail "report should indicate no untriaged issues"
  fi

  echo "Summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

# ============================================================
# Main: generate report and write to docs/reviews/
# ============================================================
# Only execute main if this is being run directly, not sourced
if [[ "$_KPI_IS_SOURCED" == "0" ]] && [[ "$_KPI_SELFTEST" != "--self-test" ]]; then
  OUTPUT_DIR="$(_kpi_output_dir)"
  REPORT_DATE="$(date '+%Y-%m-%d')"
  REPORT_PATH="$OUTPUT_DIR/harness-kpis-$REPORT_DATE.md"

  _kpi_generate_report "$REPORT_PATH" "$REPORT_DATE"

  if [[ $? -eq 0 ]]; then
    printf 'OK: KPI report written to %s\n' "$REPORT_PATH" >&2
    exit 0
  else
    printf 'FAIL: could not write KPI report\n' >&2
    exit 1
  fi
fi
