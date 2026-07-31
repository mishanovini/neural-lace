#!/usr/bin/env bash
# ask-cockpit-checkin.sh — ask-rooted-workstreams-p1 Task 17(d): the 2-week
# operator check-in that ASKS the cold-start question (design sketch §8
# metric 1's re-measurement mechanism: "operator can cold-start any active
# ask in <60s via the surface... repeated at a scheduled 2-week check-in
# that ASKS the operator (calendar task, not vibes)").
#
# Registered as a Windows Scheduled Task by the sibling installer
# (install-weekly-hygiene-task.ps1 -Checkin; 2-week cadence via
# `New-ScheduledTaskTrigger -Weekly -WeeksInterval 2`). This script does
# ONE thing: write an alert marker into the SAME
# ~/.claude/state/external-monitor-alerts/ directory
# hooks/external-monitor-alert-surfacer.sh (an ALREADY-WIRED SessionStart
# hook — see its own header) scans on every session start, so the cold-start
# question surfaces at the next interactive session with zero new
# SessionStart entries (constraint 3 — the 8/8 cap). Mirrors the exact same
# alert-marker shape harness-hygiene-weekly.sh's write_alert_marker already
# uses ({started_at, source, title, summary}), so no new consumer-side
# parsing is needed in the surfacer.
#
# This script is a pure WRITER: no reads, no ground-truth checks, no
# grading — it hands the operator a repeatable prompt to re-run the Task 18
# walkthrough on a cadence, per constitution's "the ONLY pause is
# irreversibility" — this is not that; it is a reminder, not a gate.
#
# Usage:
#   ask-cockpit-checkin.sh              # write today's check-in alert marker
#   ask-cockpit-checkin.sh --self-test  # sandboxed self-test (never touches
#                                       # the real ~/.claude estate)
#
# Exit codes: 0 always (best-effort writer semantics, constraint 5) except
# --self-test, which exits 1 on any assertion failure.
#
# Sandboxing (constraint 4). Resolution order for the alert directory:
#   1. ASK_COCKPIT_CHECKIN_ALERT_DIR env var, if set (explicit override).
#   2. HARNESS_SELFTEST=1 and no override -> a sandboxed dir under
#      HARNESS_SELFTEST_DIR (or a pid-scoped tempdir fallback).
#   3. Default: $HOME/.claude/state/external-monitor-alerts — the real,
#      production alert directory external-monitor-alert-surfacer.sh reads
#      (matches harness-hygiene-weekly.sh's own resolved path exactly, so
#      both writers' alerts surface through the identical mechanism).

set -u

# ----------------------------------------------------------------------
# _alert_dir — resolve the alert directory per the order above. Always
# prints a non-empty path; never fails.
# ----------------------------------------------------------------------
_alert_dir() {
  if [[ -n "${ASK_COCKPIT_CHECKIN_ALERT_DIR:-}" ]]; then
    printf '%s' "$ASK_COCKPIT_CHECKIN_ALERT_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/external-monitor-alerts' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/ask-cockpit-checkin-selftest/$$}"
    return 0
  fi
  printf '%s/.claude/state/external-monitor-alerts' "${HOME:-$PWD}"
}

# The cold-start question, verbatim per the Acceptance Scenarios'
# `cold-start-ask` slug + sketch §8 metric 1's falsifier ("operator still
# scroll-hunting transcripts"). Kept ASCII-only and single-line-safe (no
# embedded raw double-quotes/newlines) since it is interpolated directly
# into a hand-built JSON literal below — no jq dependency for a 3-field
# object.
COLD_START_QUESTION='2-week cockpit check-in (design sketch Sec8, metric 1): pick an ask you have NOT looked at in >=24h. Open http://127.0.0.1:7733/ and answer, in under 60 seconds without opening a transcript -- what did I ask / whats the plan / how far along is it / whats waiting on me. Falsifier: you catch yourself scroll-hunting a transcript instead of reading the card -- if so, file the specific gap.'

# ----------------------------------------------------------------------
# write_checkin_alert [alert-dir-override]
#
# Writes one alert marker JSON file (same {started_at, source, title,
# summary} shape harness-hygiene-weekly.sh's write_alert_marker uses) and
# prints its path on success. Best-effort: mkdir/write failures are
# swallowed (never blocks the caller — writer semantics, constraint 5).
# ----------------------------------------------------------------------
write_checkin_alert() {
  local alert_dir="${1:-$(_alert_dir)}"
  mkdir -p "$alert_dir" 2>/dev/null || return 0
  local ts ts_iso
  ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "unknown")
  ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  local alert_file="${alert_dir}/ask-cockpit-checkin-${ts}.json"
  # Escape any double quotes defensively (the literal above has none today,
  # but a future edit that adds one must not produce invalid JSON).
  local summary_escaped
  summary_escaped=$(printf '%s' "$COLD_START_QUESTION" | sed 's/"/\\"/g')
  cat > "$alert_file" 2>/dev/null <<JSON
{
  "started_at": "$ts_iso",
  "source": "ask-cockpit-checkin.sh",
  "title": "2-week cold-start check-in",
  "summary": "$summary_escaped"
}
JSON
  [[ -f "$alert_file" ]] && printf '%s\n' "$alert_file"
  return 0
}

# ============================================================
# --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
  fail() { echo "  FAIL: $1" >&2; FAILED=$((FAILED + 1)); }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t ask-cockpit-checkin-st)
  trap 'rm -rf "$TMP"' EXIT

  echo "SELF-TEST: adapters/claude-code/scripts/ask-cockpit-checkin.sh"

  echo "Scenario 1: HARNESS_SELFTEST sandboxing resolves under HARNESS_SELFTEST_DIR, never a real ~/.claude-shaped path"
  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$TMP/sandbox"
  unset ASK_COCKPIT_CHECKIN_ALERT_DIR
  resolved="$(_alert_dir)"
  if [[ "$resolved" == "$TMP/sandbox/external-monitor-alerts" ]]; then
    pass "1: sandboxed dir resolves to HARNESS_SELFTEST_DIR/external-monitor-alerts"
  else
    fail "1: expected $TMP/sandbox/external-monitor-alerts, got $resolved"
  fi

  echo "Scenario 2: write_checkin_alert() creates a well-formed alert file under the sandbox"
  written="$(write_checkin_alert)"
  if [[ -n "$written" && -f "$written" ]]; then
    pass "2: alert file created ($written)"
  else
    fail "2: no alert file created"
  fi

  echo "Scenario 3: the written file is valid JSON with the four required fields"
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.started_at and .source and .title and .summary' "$written" >/dev/null 2>&1; then
      pass "3: valid JSON, all four fields present (jq)"
    else
      fail "3: jq validation failed on $written"
    fi
  else
    if grep -q '"started_at"' "$written" && grep -q '"source"' "$written" \
       && grep -q '"title"' "$written" && grep -q '"summary"' "$written"; then
      pass "3: all four fields present (grep fallback, jq unavailable)"
    else
      fail "3: missing a required field (grep fallback)"
    fi
  fi

  echo "Scenario 4: source field names this script (so a future alert-surfacer triage knows which mechanism fired)"
  if grep -q '"source": "ask-cockpit-checkin.sh"' "$written"; then
    pass "4: source field correct"
  else
    fail "4: source field missing/wrong in $written"
  fi

  echo "Scenario 5: title/summary carry the cold-start question, not a placeholder"
  if grep -q "2-week cold-start check-in" "$written" && grep -q "http://127.0.0.1:7733/" "$written"; then
    pass "5: cold-start question text present (title + the cockpit URL)"
  else
    fail "5: cold-start question text missing from $written"
  fi

  echo "Scenario 6: an explicit ASK_COCKPIT_CHECKIN_ALERT_DIR override takes precedence over HARNESS_SELFTEST"
  export ASK_COCKPIT_CHECKIN_ALERT_DIR="$TMP/explicit-override"
  resolved2="$(_alert_dir)"
  if [[ "$resolved2" == "$TMP/explicit-override" ]]; then
    pass "6: explicit override wins over HARNESS_SELFTEST sandboxing"
  else
    fail "6: expected $TMP/explicit-override, got $resolved2"
  fi
  unset ASK_COCKPIT_CHECKIN_ALERT_DIR

  echo "Scenario 7: two writes in the sandbox never collide with an unrelated real path (sandbox-only-writes assertion)"
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "7: self-test never created a .claude path under its own tempdir (no leak into a path a real resolver might also use)"
  else
    fail "7: unexpected .claude path created under $TMP"
  fi

  echo "Scenario 8: mkdir failure (unwritable parent) degrades silently — never crashes, never blocks (writer semantics)"
  if command -v chmod >/dev/null 2>&1 && [[ "$(uname -s 2>/dev/null)" != MINGW* && "$(uname -s 2>/dev/null)" != MSYS* ]]; then
    ro_parent="$TMP/readonly-parent"
    mkdir -p "$ro_parent"
    chmod 500 "$ro_parent" 2>/dev/null
    out8="$(write_checkin_alert "$ro_parent/nested/alerts" 2>&1)"
    rc8=$?
    chmod 700 "$ro_parent" 2>/dev/null
    if [[ "$rc8" == "0" ]]; then
      pass "8: unwritable target directory degrades silently (exit 0, no crash)"
    else
      fail "8: expected exit 0 even on a write failure, got rc=$rc8 out=$out8"
    fi
  else
    echo "  SKIP: 8 (chmod-based unwritable-dir fixture unreliable on this platform)"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Live path
# ============================================================
write_checkin_alert >/dev/null 2>&1 || true
exit 0
