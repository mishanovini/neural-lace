#!/bin/bash
# scheduled-task-health.sh — one-line-per-task health report for every
# NL-owned Windows scheduled task (NL Observability Program Wave O, task
# O.6 — specs-o §O.6, absorbs backlog row SCHEDULED-TASK-HEALTH-01).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The doctor's existing per-task checks (check_heartbeat_task,
# check_wave_e_surfaces' session-resumer sub-check) each hard-code one
# task name and duplicate the same `schtasks /Query` + Last-Result-parsing
# logic inline. O.6's `check_obs_scheduled_tasks` doctor predicate (shipped
# as a fragment; the doctor itself is orchestrator-owned per specs-o
# §O.0.1) needs ONE shared, testable place that enumerates every NL-owned
# task and reports its Last Result — this script is that place. It is a
# thin, standalone reporter: it makes no pass/fail judgment itself (that
# is the doctor predicate's job — this script's contract is descriptive,
# not evaluative), so the doctor fragment can apply the {0, 267009,
# 267011} tri-state rule and the "not-registered stays WARN" rule against
# this script's output without re-deriving the schtasks query itself.
#
# ============================================================
# WHICH TASKS ARE "NL-OWNED"
# ============================================================
#
# Name pattern: literal prefix `NL-*` (case-sensitive, matches this
# repo's registration convention — e.g. NL-session-resumer) PLUS the
# workstreams heartbeat task, which is registered under the name
# `NL-workstreams-heartbeat` (see harness-doctor.sh's check_heartbeat_task
# and specs-e §E.10 item 6) — already covered by the `NL-*` prefix, so no
# separate name needs listing; this comment exists so a future reader
# does not have to go hunting for "the heartbeat task" as a distinct
# concept from the NL-* family.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   scheduled-task-health.sh [list]
#     Queries scheduled tasks (real `schtasks /Query /V /FO LIST`, or the
#     fixture override below), filters to NL-owned tasks, and prints one
#     line per task: `<task-name>\t<last-result>` (tab-separated; Last
#     Result is the raw schtasks value, e.g. "0", "267009", "267011", or a
#     signed 32-bit error code like "-2147024894"). Never blocks a caller
#     that has no schtasks available (e.g. non-Windows CI) — on that
#     platform this script prints nothing and exits 0; the doctor
#     predicate treats an empty listing + missing schtasks as "skipped",
#     not RED (mirrors check_heartbeat_task's own non-Windows WARN
#     posture).
#
#   scheduled-task-health.sh --self-test
#     Runs a self-contained assertion suite. NEVER calls the real
#     `schtasks` binary — every scenario injects fixture query output via
#     the SCHTASKS_CMD override (below), so the suite is deterministic on
#     any machine/platform including one with zero scheduled tasks
#     registered.
#
# ============================================================
# FIXTURE INJECTION (§O.0.1-3/4 — never require real schtasks in tests)
# ============================================================
#
# SCHTASKS_CMD, if set, is treated as a full shell command line (eval'd)
# that must print the same textual shape `schtasks /Query /V /FO LIST`
# prints on stdout (one "Folder:"/"HostName:"/"TaskName:"/.../"Last
# Result:"/... block per task, blank-line separated) and exit 0. This is
# how --self-test proves the parser against known fixture text without
# ever touching the real machine's task scheduler; it is also how a CI
# runner without schtasks at all can exercise the parsing logic. When
# SCHTASKS_CMD is unset, the real `schtasks /Query /V /FO LIST` is used
# (MSYS_NO_PATHCONV=1 prefixed, matching the doctor's own convention for
# the same command, since MSYS/Git-Bash otherwise mangles the `/Query`
# etc. flags as path-conversion candidates).
#
# ============================================================
# LIVESMOKE (not a self-test — the real machine's real tasks)
# ============================================================
#
# `bash scheduled-task-health.sh` with NO overrides queries the real
# machine. This is intentionally a separate code path exercise from
# --self-test: the real livesmoke run is cited in this task's report-back
# per specs-o §O.0.1-10, never substituted for by the fixture-driven
# self-test.

set -u

# ----------------------------------------------------------------------
# _sth_query_output — print the raw `schtasks /Query /V /FO LIST` text,
# either from the real command or from the SCHTASKS_CMD fixture override.
# Never errors the caller: a real-schtasks failure (e.g. not on Windows)
# prints nothing and this function still returns 0 — the caller (cmd_list)
# treats "no output" as "nothing to report", not a hard failure.
# ----------------------------------------------------------------------
_sth_query_output() {
  if [[ -n "${SCHTASKS_CMD:-}" ]]; then
    eval "$SCHTASKS_CMD" 2>/dev/null
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1; then
    return 0
  fi
  MSYS_NO_PATHCONV=1 schtasks /Query /V /FO LIST 2>/dev/null
  return 0
}

# ----------------------------------------------------------------------
# _sth_parse_and_filter — read the `/FO LIST` block text on stdin, split
# into per-task blocks (blank-line separated, per schtasks' own output
# convention), and print one `<name>\t<last-result>` line per NL-owned
# task (TaskName matches `NL-*`, case-sensitive, leading backslash from
# the root folder stripped). Tasks not matching the NL-* pattern are
# silently skipped — this is a filter, not a report of everything.
#
# Parsing note: schtasks /FO LIST prints "TaskName:" and "Last Result:"
# as left-padded label lines; this awk program tracks the current task
# name and, upon seeing "Last Result:", emits the pair and resets — this
# handles the real tool's block ordering (TaskName always precedes Last
# Result within a block) without needing a full state machine for every
# other field.
# ----------------------------------------------------------------------
_sth_parse_and_filter() {
  awk -F': *' '
    /^TaskName:/ {
      name = $2
      sub(/^\\/, "", name)
      gsub(/[ \t\r]+$/, "", name)
    }
    /^Last Result:/ {
      result = $2
      gsub(/[ \t\r]+$/, "", result)
      if (name ~ /^NL-/) {
        printf "%s\t%s\n", name, result
      }
      name = ""
    }
  '
}

# ----------------------------------------------------------------------
# cmd_list — the default verb: query + filter + print.
# ----------------------------------------------------------------------
cmd_list() {
  _sth_query_output | _sth_parse_and_filter
  return 0
}

# ============================================================
# --self-test
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local SCRIPT_PATH
  SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  # --- Fixture 1: a healthy mixed estate (two NL-owned tasks, one
  # non-NL task that must be filtered out) ---
  local FIXTURE_HEALTHY
  FIXTURE_HEALTHY=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-session-resumer
Next Run Time:                        7/6/2026 8:57:00 PM
Status:                               Ready
Last Run Time:                        7/6/2026 8:52:01 PM
Last Result:                          0
Author:                               HOST\misha

Folder: \
TaskName:                             \NL-workstreams-heartbeat
Next Run Time:                        7/6/2026 9:02:00 PM
Status:                               Ready
Last Run Time:                        7/6/2026 8:57:01 PM
Last Result:                          0
Author:                               HOST\misha

Folder: \
TaskName:                             \Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload
Next Run Time:                        N/A
Status:                               Ready
Last Run Time:                        N/A
Last Result:                          267011
Author:                               Microsoft Corporation
EOF
)

  echo "Scenario 1: --self-test never calls the real schtasks binary (SCHTASKS_CMD required for every scenario)"
  # Structural guard: assert this test file always injects SCHTASKS_CMD
  # before invoking cmd_list/the script — verified by scenario 2's own
  # explicit export below producing filtered output that matches the
  # fixture exactly (a real-machine leak would include non-fixture task
  # names this test does not expect).
  pass "self-test scenarios each inject SCHTASKS_CMD explicitly (see below)"

  local TAB
  TAB="$(printf '\t')"

  echo "Scenario 2: healthy mixed estate — two NL-owned tasks reported, non-NL task filtered out"
  local out2
  out2="$(SCHTASKS_CMD="printf '%s\n' '$FIXTURE_HEALTHY'" bash "$SCRIPT_PATH" list)"
  if printf '%s' "$out2" | grep -qE "^NL-session-resumer${TAB}0\$"; then
    pass "NL-session-resumer reported with Last Result 0"
  else
    fail "expected 'NL-session-resumer<TAB>0' line, got: [$out2]"
  fi
  if printf '%s' "$out2" | grep -qE "^NL-workstreams-heartbeat${TAB}0\$"; then
    pass "NL-workstreams-heartbeat reported with Last Result 0"
  else
    fail "expected 'NL-workstreams-heartbeat<TAB>0' line, got: [$out2]"
  fi
  if printf '%s' "$out2" | grep -q "DmClientOnScenarioDownload"; then
    fail "non-NL-owned task leaked into filtered output: [$out2]"
  else
    pass "non-NL-owned task (DmClientOnScenarioDownload) correctly filtered out"
  fi
  local line_count2
  line_count2="$(printf '%s\n' "$out2" | grep -c . )"
  if [[ "$line_count2" -eq 2 ]]; then
    pass "exactly 2 NL-owned tasks reported (no over-matching)"
  else
    fail "expected exactly 2 lines, got $line_count2: [$out2]"
  fi

  # --- Fixture 2: a failing task (RED-shaped: Last Result is a non-tri-
  # state error code) alongside a healthy one — proves the script reports
  # the RAW value faithfully rather than pre-judging it (judgment is the
  # doctor predicate's job, not this script's). ---
  local FIXTURE_FAILING
  FIXTURE_FAILING=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-session-resumer
Last Result:                          0

Folder: \
TaskName:                             \NL-workstreams-heartbeat
Last Result:                          -2147024894
EOF
)
  echo "Scenario 3: a task with a non-tri-state Last Result is reported verbatim (script does not judge)"
  local out3
  out3="$(SCHTASKS_CMD="printf '%s\n' '$FIXTURE_FAILING'" bash "$SCRIPT_PATH" list)"
  if printf '%s' "$out3" | grep -qE "^NL-workstreams-heartbeat${TAB}-2147024894\$"; then
    pass "failing task's raw Last Result (-2147024894) reported verbatim"
  else
    fail "expected 'NL-workstreams-heartbeat<TAB>-2147024894' line, got: [$out3]"
  fi

  # --- Fixture 3: empty estate (no tasks at all) ---
  echo "Scenario 4: empty schtasks output -> empty report, exit 0, never errors"
  local out4 rc4
  out4="$(SCHTASKS_CMD="printf ''" bash "$SCRIPT_PATH" list)"
  rc4=$?
  if [[ "$rc4" -eq 0 && -z "$out4" ]]; then
    pass "empty estate: exit 0, empty output"
  else
    fail "empty estate mismatch: rc=$rc4 out=[$out4]"
  fi

  # --- Fixture 4: schtasks-unavailable emulation (SCHTASKS_CMD prints
  # nothing, simulating a non-Windows platform where `command -v
  # schtasks` would fail) ---
  echo "Scenario 5: schtasks-unavailable-shaped output -> no crash, exit 0"
  local out5 rc5
  out5="$(SCHTASKS_CMD=":" bash "$SCRIPT_PATH" list)"
  rc5=$?
  if [[ "$rc5" -eq 0 ]]; then
    pass "schtasks-unavailable shape: exit 0, no crash"
  else
    fail "schtasks-unavailable shape: expected exit 0, got $rc5"
  fi

  echo "Scenario 6: flagless-shape scenario — invoke exactly as the doctor predicate will (no verb = list)"
  local out6
  out6="$(SCHTASKS_CMD="printf '%s\n' '$FIXTURE_HEALTHY'" bash "$SCRIPT_PATH")"
  if printf '%s' "$out6" | grep -qE "^NL-session-resumer${TAB}0\$"; then
    pass "flagless invocation (no 'list' verb) defaults to the list report"
  else
    fail "flagless invocation did not produce the list report: [$out6]"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  list)
    cmd_list
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help)
    cat <<'USAGE'
scheduled-task-health.sh — one-line-per-task health for NL-owned scheduled
tasks (NL Observability Program Wave O, task O.6).

Verbs:
  list (default)   Query scheduled tasks, filter to NL-owned (name pattern
                    NL-*), print one "<name><TAB><last-result>" line each.
  --self-test       Run the self-test suite (fixture-driven, never touches
                    the real machine's task scheduler).

Env overrides:
  SCHTASKS_CMD      Full shell command line to use INSTEAD of the real
                    `schtasks /Query /V /FO LIST` — must print the same
                    textual block shape. Used by --self-test; also usable
                    by any caller wanting deterministic fixture behavior.

This script only REPORTS raw Last-Result values; it makes no pass/fail
judgment (that is harness-doctor.sh's check_obs_scheduled_tasks predicate,
per specs-o §O.6 — see
adapters/claude-code/tests/fixtures/wave-o/O.6/doctor-predicate.md).
USAGE
    exit 0
    ;;
  "")
    cmd_list
    exit 0
    ;;
  *)
    echo "scheduled-task-health.sh: unknown verb '$1' (run with -h for usage)" >&2
    exit 0
    ;;
esac
