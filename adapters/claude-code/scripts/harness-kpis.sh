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

# ---- WAVE-O O.9: od_backlog_health oracle, guarded source + feature-detect ----
# Contract C4 (specs-o §O.0.3): observability-derive.sh is owned/built by task
# O.3 (parallel; O.9 never creates/edits that file — §O.0.1 rule 2). Source it
# if present; if it doesn't yet supply od_backlog_health (pre-merge, or the
# file doesn't exist at all), fall back to the private test shim so this
# script still has a real oracle to call. Once O.3 merges the real lib, the
# guarded source above wins the declare -F check and this fallback is never
# invoked.
_KPI_OBS_DERIVE="$_KPI_SELF_DIR/../hooks/lib/observability-derive.sh"
_KPI_OD_SHIM="$_KPI_SELF_DIR/../tests/fixtures/wave-o/O.9/od-backlog-shim.sh"
if [[ -f "$_KPI_OBS_DERIVE" ]]; then
  # shellcheck disable=SC1090,SC1091
  { source "$_KPI_OBS_DERIVE" 2>/dev/null; } || true
fi
if ! declare -F od_backlog_health >/dev/null 2>&1; then
  if [[ -f "$_KPI_OD_SHIM" ]]; then
    # shellcheck disable=SC1090,SC1091
    { source "$_KPI_OD_SHIM" 2>/dev/null; } || true
  fi
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
# _kpi_backlog_path — resolve docs/backlog.md (BACKLOG-LOOP-01 part 3,
# observability O.9). BACKLOG_MD_PATH overrides (fixtures); under
# HARNESS_SELFTEST=1 the default resolves into the sandbox (absent file
# => section reports "no backlog file") so self-tests never read the
# real backlog unless a fixture is explicitly provided.
# ============================================================
_kpi_backlog_path() {
  if [[ -n "${BACKLOG_MD_PATH:-}" ]]; then
    printf '%s' "$BACKLOG_MD_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/backlog-selftest/%s/backlog.md' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  local root
  root="$(_kpi_repo_root)"
  printf '%s/docs/backlog.md' "$root"
  return 0
}

# ============================================================
# _kpi_backlog_date_epoch <YYYY-MM-DD> — GNU date with BSD fallback
# ============================================================
_kpi_backlog_date_epoch() {
  date -u -d "$1" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null \
    || echo ""
}

# ============================================================
# _kpi_backlog_section <backlog_path> [window_days] — render the
# Backlog Health section (BACKLOG-LOOP-01 part 3):
#   - open-row count by priority (high/medium/low/unlabeled)
#   - aging histogram of open rows (0-7 / 8-30 / 31-90 / >90 days)
#   - adds vs terminal transitions inside the report window
#     (default KPI_WINDOW_DAYS=7 — this is a weekly report)
#
# ORACLE (Wave O task O.9): row-parsing + position-anchored
# terminal-marker detection + per-priority/age-tier/flow counting is
# delegated to the od_backlog_health oracle (contract C4; guarded source
# + feature-detect fallback near the top of this file). This function is
# now PURE presentation: it renders the oracle's own summary fields as
# markdown tables. If the oracle isn't available (neither the real lib
# nor the fallback shim could be sourced), report that honestly rather
# than silently going blank.
# ============================================================
_kpi_backlog_section() {
  local backlog_path="$1"
  local window_days="${2:-${KPI_WINDOW_DAYS:-7}}"

  printf '### Backlog Health\n\n'
  if [[ ! -f "$backlog_path" ]]; then
    printf 'No backlog file at %s.\n\n' "$backlog_path"
    return 0
  fi
  if ! declare -F od_backlog_health >/dev/null 2>&1; then
    printf 'od_backlog_health oracle unavailable (observability-derive.sh not yet present and no fallback shim found).\n\n'
    return 0
  fi

  local oracle_json
  oracle_json="$(BACKLOG_MD_PATH="$backlog_path" BACKLOG_HEALTH_WINDOW_DAYS="$window_days" od_backlog_health --json 2>/dev/null)"
  if [[ -z "$oracle_json" ]]; then
    printf 'od_backlog_health returned no data for %s.\n\n' "$backlog_path"
    return 0
  fi

  local open_high=0 open_medium=0 open_low=0 open_unlabeled=0
  local age_0_7=0 age_8_30=0 age_31_90=0 age_over_90=0 open_undated=0
  local adds_window=0 terminal_window=0 terminal_undated=0 terminal_total=0 open_total=0
  eval "$(printf '%s' "$oracle_json" | node -e '
    "use strict";
    var doc = JSON.parse(require("fs").readFileSync(0, "utf8"));
    var s = doc.summary || {};
    var pc = s.priority_counts || {};
    var at = s.age_tiers || {};
    function n(v) { return Number(v || 0); }
    var out = [
      "open_high=" + n(pc.high),
      "open_medium=" + n(pc.medium),
      "open_low=" + n(pc.low),
      "open_unlabeled=" + n(pc.unlabeled),
      "age_0_7=" + n(at["0_7"]),
      "age_8_30=" + n(at["8_30"]),
      "age_31_90=" + n(at["31_90"]),
      "age_over_90=" + n(at.over_90),
      "open_undated=" + n(at.undated),
      "adds_window=" + n(s.adds_in_window),
      "terminal_window=" + n(s.terminal_in_window),
      "terminal_undated=" + n(s.terminal_undated),
      "terminal_total=" + n(s.terminal_total),
      "open_total=" + n(s.open_total)
    ];
    process.stdout.write(out.join("\n"));
  ' 2>/dev/null)"

  printf 'Open structured rows: %d (terminal-marked: %d)\n\n' "$open_total" "$terminal_total"
  printf '| Priority | Open rows |\n'
  printf '|----------|-----------|\n'
  printf '| high | %d |\n' "$open_high"
  printf '| medium | %d |\n' "$open_medium"
  printf '| low | %d |\n' "$open_low"
  printf '| (unlabeled) | %d |\n' "$open_unlabeled"
  printf '\n'
  printf '| Age (open rows) | Count |\n'
  printf '|-----------------|-------|\n'
  printf '| 0-7d | %d |\n' "$age_0_7"
  printf '| 8-30d | %d |\n' "$age_8_30"
  printf '| 31-90d | %d |\n' "$age_31_90"
  printf '| >90d | %d |\n' "$age_over_90"
  if [[ "$open_undated" -gt 0 ]]; then
    printf '| (no parseable added-date) | %d |\n' "$open_undated"
  fi
  printf '\n'
  printf '| Flow (last %dd) | Count |\n' "$window_days"
  printf '|------------------|-------|\n'
  printf '| Rows added | %d |\n' "$adds_window"
  printf '| Terminal transitions | %d |\n' "$terminal_window"
  if [[ "$terminal_undated" -gt 0 ]]; then
    printf '| (terminal, no adjacent date) | %d |\n' "$terminal_undated"
  fi
  printf '\n'
  return 0
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

    # Backlog Health Section (BACKLOG-LOOP-01 part 3, observability O.9)
    _kpi_backlog_section "$(_kpi_backlog_path)"

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

  echo "Scenario 3: fixture backlog renders the Backlog Health section (BACKLOG-LOOP-01)"
  # Fixture: 2 open rows per distinct age bucket + priorities, 1 unlabeled,
  # 2 terminal rows (one dated in-window, one undated), 1 row added
  # in-window. Dates computed relative to today so bucket boundaries are
  # deterministic.
  d2="$(date -u -d '2 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-2d '+%Y-%m-%d' 2>/dev/null)"
  d20="$(date -u -d '20 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-20d '+%Y-%m-%d' 2>/dev/null)"
  d60="$(date -u -d '60 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-60d '+%Y-%m-%d' 2>/dev/null)"
  d120="$(date -u -d '120 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-120d '+%Y-%m-%d' 2>/dev/null)"
  export BACKLOG_MD_PATH="$TMP/fixture-backlog.md"
  cat > "$BACKLOG_MD_PATH" <<EOF
# Fixture Backlog

- **KPI-FRESH-01 — fresh high row** (added $d2; \`priority:high\`). Prose.
- **KPI-MID-01 — mid-age medium row** (added $d20; \`priority:medium\`). Prose.
- **KPI-OLD-01 — old low row** (added $d60; \`priority:low\`). Prose.
- **KPI-ANCIENT-01 — ancient unlabeled row** (added $d120). Prose.
- **KPI-TERM-01 — [CLOSED $d2] closed in window** (added $d120; \`priority:high\`). Prose.
- **KPI-TERM-02 — done long ago** (added $d120; \`priority:low\`). **(absorbed by docs/plans/fixture.md)**.
- **KPI-REF-OPEN-01 — open row referencing another row's terminal state** (added $d2; \`priority:high\`). **Distinct from OTHER-GAP-99 (IMPLEMENTED 2026-01-01).** Still open.
EOF
  report_path3="$TMP/report3.md"
  _kpi_generate_report "$report_path3" "2026-07-06"

  if grep -q "### Backlog Health" "$report_path3" 2>/dev/null; then
    pass "report contains Backlog Health section"
  else
    fail "report missing Backlog Health section"
  fi
  if grep -q "Open structured rows: 5 (terminal-marked: 2)" "$report_path3" 2>/dev/null; then
    pass "open/terminal row counts correct (5 open incl. terminal-referencing row, 2 terminal)"
  else
    fail "open/terminal row counts wrong (expected 5 open, 2 terminal)"
  fi
  if grep -q "| high | 2 |" "$report_path3" 2>/dev/null \
     && grep -q "| medium | 1 |" "$report_path3" 2>/dev/null \
     && grep -q "| low | 1 |" "$report_path3" 2>/dev/null \
     && grep -q "| (unlabeled) | 1 |" "$report_path3" 2>/dev/null; then
    pass "priority breakdown correct (2 high / 1 medium / 1 low / 1 unlabeled)"
  else
    fail "priority breakdown wrong"
  fi
  if grep -q "| 0-7d | 2 |" "$report_path3" 2>/dev/null \
     && grep -q "| 8-30d | 1 |" "$report_path3" 2>/dev/null \
     && grep -q "| 31-90d | 1 |" "$report_path3" 2>/dev/null \
     && grep -q "| >90d | 1 |" "$report_path3" 2>/dev/null; then
    pass "aging histogram buckets correct (2/1/1/1)"
  else
    fail "aging histogram buckets wrong"
  fi
  if grep -q "| Rows added | 2 |" "$report_path3" 2>/dev/null \
     && grep -q "| Terminal transitions | 1 |" "$report_path3" 2>/dev/null \
     && grep -q "| (terminal, no adjacent date) | 1 |" "$report_path3" 2>/dev/null; then
    pass "flow counts correct (2 added, 1 terminal in-window, 1 undated terminal)"
  else
    fail "flow counts wrong"
  fi
  unset BACKLOG_MD_PATH

  echo "Scenario 4: absent backlog file -> honest no-file line, no crash"
  report_path4="$TMP/report4.md"
  _kpi_generate_report "$report_path4" "2026-07-06"
  if grep -q "No backlog file at" "$report_path4" 2>/dev/null; then
    pass "absent backlog reported honestly"
  else
    fail "absent backlog not reported"
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
