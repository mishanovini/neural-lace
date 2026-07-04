#!/bin/bash
# waiver-density.sh — waiver-density alarm (Wave E, task E.3).
#
# ============================================================
# WHY THIS EXISTS (NL Overhaul Program Wave E, task E.3 — specs-e §E.3)
# ============================================================
#
# The signal ledger (hooks/lib/signal-ledger.sh, Wave D task D.1) gives every
# gate/hook a uniform place to record a "waiver" event when its enforcement
# was bypassed with a reason. Nothing read that ledger for waiver DENSITY
# until this task: a gate that racks up repeated waivers on the same window
# is a gate that is either broken (false-firing, forcing waivers as the only
# way through) or genuinely obsolete (the check it enforces no longer
# matters) — either way it needs a human decision, not silent tolerance.
# This script is the read side: it counts waivers per gate over a trailing
# 7-day window and, at >=3, both surfaces a digest line (consumed by E.1's
# session-start-digest.sh) and files a backlog "fix or retire" item so the
# decision does not evaporate at session end.
#
# ADR 059 D7's auto-DEMOTION (a manifest.json blocking:true -> false flip
# once a gate crosses its own waiver threshold) is explicitly OUT OF SCOPE
# here — that lands at F.5. This task only detects + files; it never edits
# manifest.json.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   waiver-density.sh --digest-line
#     Print ZERO OR ONE line for E.1's digest to consume:
#       "waiver-density: <gate> <N> waivers/7d -> fix-or-retire item filed"
#     - Computed against the gate with the HIGHEST waiver count in the
#       trailing 7-day window (ties broken alphabetically by gate name for
#       determinism).
#     - Prints NOTHING when every gate's 7-day waiver count is below the
#       ALARM_THRESHOLD (default 3) — E.1's "quiet feeds emit nothing" rule.
#     - As a side effect (not on stdout): for EVERY gate at/above threshold
#       (not just the max), idempotently appends a
#       `WAIVER-DENSITY-<GATE>-<yyyymmdd>` backlog entry (today's date, so a
#       gate crossing threshold again next week gets a NEW dated entry, but
#       re-running this script repeatedly today never duplicates it).
#
#   waiver-density.sh --report
#     Print a markdown table of EVERY gate that has ANY waiver in the
#     trailing 7-day window, sorted by count descending (gate name
#     ascending on ties): gate | waivers/7d | over threshold?. Used by E.5's
#     harness-kpis.sh (script-level composition, not a shared library — E.5
#     shells out to this script and includes its stdout verbatim in the KPI
#     report). Does NOT file backlog entries (read-only report mode).
#
#   waiver-density.sh (no args)
#     Alias for --report (a sane default for direct/manual invocation).
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST) — mirrors lib/signal-ledger.sh's contract
# ============================================================
#
# Ledger path resolution:
#   1. SIGNAL_LEDGER_PATH env var, if set.
#   2. HARNESS_SELFTEST=1 and SIGNAL_LEDGER_PATH unset -> the SAME sandbox
#      convention signal-ledger.sh itself uses
#      (${TMPDIR:-/tmp}/signal-ledger-selftest/<pid>.jsonl) — this script
#      sources lib/signal-ledger.sh and calls its own _signal_ledger_path so
#      the two never disagree about where "the ledger" is.
#   3. Default: $HOME/.claude/state/signal-ledger.jsonl.
#
# Backlog path resolution (the file the alarm appends WAIVER-DENSITY-* to):
#   1. WAIVER_DENSITY_BACKLOG_PATH env var, if set (self-test / explicit
#      override — NEVER writes to the real docs/backlog.md under
#      HARNESS_SELFTEST unless a caller deliberately points it there).
#   2. Else the repo's docs/backlog.md resolved via hooks/lib/nl-paths.sh's
#      nl_repo_root() (never ambient cwd guessing).
#   3. Unresolvable -> no-op (best-effort writer semantics, same as
#      ledger_emit / nl-issue.sh's escalation append).
#
# ============================================================
# DIGEST FEED CONTRACT (consumed by E.1 session-start-digest.sh)
# ============================================================
#
# feed_waiver_density() in session-start-digest.sh already calls:
#   bash "$cwd/scripts/waiver-density.sh" --digest-line
# and takes the first line of stdout verbatim (E.1 prefixes its own
# icon/feed-name — this script's line ALREADY carries the "waiver-density:"
# label per the spec's exact digest-line text, so E.1's generic `head -n1`
# passthrough is sufficient; no additional icon is added here). Absence of
# this script entirely, or a nonzero/erroring invocation, is already
# tolerated by E.1 (`|| true`, empty-output check) — this script never
# needs its own separate "not installed yet" placeholder line.
#
# ============================================================

set -u

_WD_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# hooks/lib lives at adapters/claude-code/hooks/lib relative to this
# script's own location (adapters/claude-code/scripts/ -> ../hooks/lib/).
_WD_HOOKS_LIB="$_WD_SELF_DIR/../hooks/lib"
if [[ -f "$_WD_HOOKS_LIB/signal-ledger.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_WD_HOOKS_LIB/signal-ledger.sh"
fi
if [[ -f "$_WD_HOOKS_LIB/nl-paths.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_WD_HOOKS_LIB/nl-paths.sh"
fi

ALARM_THRESHOLD="${WAIVER_DENSITY_THRESHOLD:-3}"
WINDOW_DAYS="${WAIVER_DENSITY_WINDOW_DAYS:-7}"

_have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------
# _wd_ledger_path — resolve the signal ledger path. Delegates to
# signal-ledger.sh's own resolver when sourced successfully (so this
# script and the ledger writers NEVER disagree about the file); falls back
# to re-deriving the same contract if the source failed to load for any
# reason (defensive; the lib is expected to always be present).
# ----------------------------------------------------------------------
_wd_ledger_path() {
  if _have _signal_ledger_path; then
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
}

# ----------------------------------------------------------------------
# _wd_backlog_path — resolve the backlog file the alarm appends to.
# ----------------------------------------------------------------------
_wd_backlog_path() {
  if [[ -n "${WAIVER_DENSITY_BACKLOG_PATH:-}" ]]; then
    printf '%s' "$WAIVER_DENSITY_BACKLOG_PATH"
    return 0
  fi
  if _have nl_repo_root; then
    local root
    root="$(nl_repo_root)"
    if [[ -n "$root" ]]; then
      printf '%s/docs/backlog.md' "$root"
      return 0
    fi
  fi
  printf ''
  return 0
}

# ----------------------------------------------------------------------
# _wd_json_field <json-line> <field> — extract a top-level string field's
# RAW value from a signal-ledger JSONL line (same flat, single-line,
# no-nested-object shape ledger_emit itself writes; safe without a jq dep).
# ----------------------------------------------------------------------
_wd_json_field() {
  local line="$1" field="$2"
  printf '%s' "$line" | sed -n "s/.*\"$field\":\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\".*/\\1/p"
}

# ----------------------------------------------------------------------
# _wd_now_epoch — current UTC seconds-since-epoch. Prints 0 on failure.
# ----------------------------------------------------------------------
_wd_now_epoch() {
  date -u +%s 2>/dev/null || echo 0
}

# ----------------------------------------------------------------------
# _wd_epoch <iso-ts> — best-effort seconds-since-epoch for a
# ledger_emit-style UTC ISO-8601 timestamp. Prints 0 on failure.
# ----------------------------------------------------------------------
_wd_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null || echo 0
}

# ----------------------------------------------------------------------
# _wd_counts <ledger-path> -> prints "<gate>\t<count>" lines, one per gate
# that has >=1 "waiver" event inside the trailing WINDOW_DAYS window, sorted
# by count descending then gate ascending (deterministic tie-break). Never
# errors; prints nothing for a missing/empty ledger.
# ----------------------------------------------------------------------
_wd_counts() {
  local ledger="$1"
  [[ -f "$ledger" ]] || return 0

  local now_epoch cutoff_epoch
  now_epoch="$(_wd_now_epoch)"
  cutoff_epoch=$(( now_epoch - WINDOW_DAYS * 86400 ))

  declare -A gate_counts=()
  local line ts_raw event gate epoch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    event="$(_wd_json_field "$line" "event")"
    [[ "$event" != "waiver" ]] && continue
    ts_raw="$(_wd_json_field "$line" "ts")"
    epoch="$(_wd_epoch "$ts_raw")"
    # Malformed/unresolvable timestamps are treated as IN-window (fail-open
    # for visibility: an alarm that silently drops unparseable events would
    # under-count, not over-count, the exact opposite of what a density
    # alarm should risk).
    if [[ "$epoch" -gt 0 ]] && [[ "$epoch" -lt "$cutoff_epoch" ]]; then
      continue
    fi
    gate="$(_wd_json_field "$line" "gate")"
    [[ -z "$gate" ]] && gate="unknown"
    gate_counts["$gate"]=$(( ${gate_counts["$gate"]:-0} + 1 ))
  done < "$ledger"

  local g
  for g in "${!gate_counts[@]}"; do
    printf '%s\t%s\n' "$g" "${gate_counts[$g]}"
  done | sort -t "$(printf '\t')" -k2,2nr -k1,1
}

# ----------------------------------------------------------------------
# _wd_backlog_append <gate> <count> — idempotently append the fix-or-retire
# backlog entry for one gate (grep for the exact dated ID before append).
# Best-effort; never errors if the backlog path is unresolvable.
# ----------------------------------------------------------------------
_wd_backlog_append() {
  local gate="$1" count="$2"
  local backlog
  backlog="$(_wd_backlog_path)"
  [[ -z "$backlog" ]] && return 0
  [[ -f "$backlog" ]] || return 0

  local today gate_upper id
  today="$(date -u '+%Y%m%d' 2>/dev/null || echo 'unknown')"
  gate_upper="$(printf '%s' "$gate" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-')"
  id="WAIVER-DENSITY-${gate_upper}-${today}"

  if grep -q "$id" "$backlog" 2>/dev/null; then
    return 0
  fi

  {
    printf '\n## %s — waiver-density alarm (auto-filed)\n\n' "$id"
    printf '**Severity:** P2 (repeated bypass of enforcement is a live risk, not a nag).\n'
    printf '**Trigger:** gate `%s` recorded %s waiver(s) in the trailing %sd window (threshold >=%s).\n' \
      "$gate" "$count" "$WINDOW_DAYS" "$ALARM_THRESHOLD"
    printf '**Action:** fix or retire `%s` — either the check is false-firing (fix it) or it no longer earns its keep (retire it). Ledger refs: `ledger_tail` for gate=%s, event=waiver, or grep the raw ledger.\n' "$gate" "$gate"
    printf '**Filed:** auto-filed by waiver-density.sh --digest-line; idempotent per gate per day (id above). ADR 059 D7 auto-demotion is NOT performed here (that is task F.5) — this entry is detect-and-file only.\n'
  } >> "$backlog"
  return 0
}

# ----------------------------------------------------------------------
# wd_digest_line — the --digest-line verb.
# ----------------------------------------------------------------------
wd_digest_line() {
  local ledger
  ledger="$(_wd_ledger_path)"
  local counts
  counts="$(_wd_counts "$ledger")"
  [[ -z "$counts" ]] && return 0

  # File backlog entries for EVERY gate at/above threshold (side effect),
  # then emit the digest line for the max (first row, already sorted
  # count-desc/gate-asc).
  local top_gate="" top_count=0
  local line gate count
  while IFS=$'\t' read -r gate count; do
    [[ -z "$gate" ]] && continue
    if [[ -z "$top_gate" ]]; then
      top_gate="$gate"
      top_count="$count"
    fi
    if [[ "$count" -ge "$ALARM_THRESHOLD" ]]; then
      _wd_backlog_append "$gate" "$count"
    fi
  done <<< "$counts"

  [[ -z "$top_gate" ]] && return 0
  [[ "$top_count" -lt "$ALARM_THRESHOLD" ]] && return 0

  printf 'waiver-density: %s %s waivers/7d -> fix-or-retire item filed\n' "$top_gate" "$top_count"
  return 0
}

# ----------------------------------------------------------------------
# wd_report — the --report verb (read-only, no backlog side effects).
# ----------------------------------------------------------------------
wd_report() {
  local ledger
  ledger="$(_wd_ledger_path)"
  local counts
  counts="$(_wd_counts "$ledger")"

  printf '# Waiver density (trailing %sd window, alarm threshold >=%s)\n\n' "$WINDOW_DAYS" "$ALARM_THRESHOLD"
  if [[ -z "$counts" ]]; then
    printf 'No waiver events recorded in the trailing %sd window.\n' "$WINDOW_DAYS"
    return 0
  fi

  printf '| gate | waivers/%sd | over threshold |\n' "$WINDOW_DAYS"
  printf '|------|%s|----------------|\n' "$(printf -- '-%.0s' $(seq 1 $((WINDOW_DAYS > 9 ? 6 : 5))))"
  local gate count over
  while IFS=$'\t' read -r gate count; do
    [[ -z "$gate" ]] && continue
    if [[ "$count" -ge "$ALARM_THRESHOLD" ]]; then
      over="YES"
    else
      over="no"
    fi
    printf '| %s | %s | %s |\n' "$gate" "$count" "$over"
  done <<< "$counts"
  return 0
}

# ============================================================
# CLI dispatch (only when executed directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      : # handled below, after function defs, via a dedicated block
      ;;
    --digest-line)
      wd_digest_line
      exit 0
      ;;
    --report|"")
      wd_report
      exit 0
      ;;
    *)
      echo "usage: waiver-density.sh --digest-line | --report | --self-test" >&2
      exit 1
      ;;
  esac
fi

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'wdst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  _wd_now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
  _wd_days_ago_iso() {
    local d="$1"
    date -u -d "${d} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
      || date -u -v-"${d}"d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
  }
  _wd_emit_fixture() {
    # _wd_emit_fixture <ledger> <gate> <days-ago>
    local ledger="$1" gate="$2" days_ago="$3"
    local ts; ts="$(_wd_days_ago_iso "$days_ago")"
    printf '{"ts":"%s","session_id":"selftest","gate":"%s","event":"waiver","detail":"fixture"}\n' "$ts" "$gate" >> "$ledger"
  }

  echo "self-test: waiver-density.sh"

  # ------------------------------------------------------------
  # Scenario 1: fixture ledger with 3 waivers on one gate (within 7d) ->
  # digest line + idempotent backlog entry in a SANDBOX backlog copy.
  # ------------------------------------------------------------
  echo "Scenario 1: 3 waivers/7d -> digest line + backlog entry (sandbox)"
  LEDGER1="$TMP/s1-ledger.jsonl"
  BACKLOG1="$TMP/s1-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG1"
  _wd_emit_fixture "$LEDGER1" "fixture-gate-a" 1
  _wd_emit_fixture "$LEDGER1" "fixture-gate-a" 2
  _wd_emit_fixture "$LEDGER1" "fixture-gate-a" 3
  OUT1="$( SIGNAL_LEDGER_PATH="$LEDGER1" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG1" bash "$SELF_ABS" --digest-line )"
  if printf '%s' "$OUT1" | grep -qE '^waiver-density: fixture-gate-a 3 waivers/7d -> fix-or-retire item filed$'; then
    pass "3-waiver fixture produces the exact digest line"
  else
    fail "expected exact digest line, got: $OUT1"
  fi
  TODAY_ID1="WAIVER-DENSITY-FIXTURE-GATE-A-$(date -u '+%Y%m%d')"
  if grep -q "$TODAY_ID1" "$BACKLOG1"; then
    pass "idempotent backlog entry $TODAY_ID1 appended to the SANDBOX backlog copy"
  else
    fail "expected $TODAY_ID1 in sandbox backlog, got: $(cat "$BACKLOG1")"
  fi

  # ------------------------------------------------------------
  # Scenario 2: 2 waivers on a gate (below threshold) -> silence, no
  # backlog append.
  # ------------------------------------------------------------
  echo "Scenario 2: 2 waivers/7d -> silence (below threshold)"
  LEDGER2="$TMP/s2-ledger.jsonl"
  BACKLOG2="$TMP/s2-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG2"
  _wd_emit_fixture "$LEDGER2" "fixture-gate-b" 1
  _wd_emit_fixture "$LEDGER2" "fixture-gate-b" 2
  OUT2="$( SIGNAL_LEDGER_PATH="$LEDGER2" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG2" bash "$SELF_ABS" --digest-line )"
  if [[ -z "$OUT2" ]]; then
    pass "2-waiver fixture produces NO digest line"
  else
    fail "expected empty output for 2 waivers, got: $OUT2"
  fi
  if ! grep -q "WAIVER-DENSITY-FIXTURE-GATE-B-" "$BACKLOG2"; then
    pass "no backlog append below threshold"
  else
    fail "unexpected backlog append below threshold: $(cat "$BACKLOG2")"
  fi

  # ------------------------------------------------------------
  # Scenario 3: re-run does not duplicate the backlog entry (idempotence).
  # ------------------------------------------------------------
  echo "Scenario 3: re-run --digest-line does not duplicate the backlog entry"
  ( SIGNAL_LEDGER_PATH="$LEDGER1" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG1" bash "$SELF_ABS" --digest-line >/dev/null )
  DUP_COUNT=$(grep -c "$TODAY_ID1" "$BACKLOG1" 2>/dev/null | tr -d ' ')
  if [[ "$DUP_COUNT" == "1" ]]; then
    pass "re-running --digest-line does not duplicate the backlog entry (count=$DUP_COUNT)"
  else
    fail "expected exactly 1 occurrence of $TODAY_ID1 after re-run, got $DUP_COUNT"
  fi

  # ------------------------------------------------------------
  # Scenario 4: waivers OUTSIDE the 7-day window are excluded from the count.
  # ------------------------------------------------------------
  echo "Scenario 4: waivers older than 7d are excluded from the window"
  LEDGER4="$TMP/s4-ledger.jsonl"
  BACKLOG4="$TMP/s4-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG4"
  _wd_emit_fixture "$LEDGER4" "fixture-gate-c" 10
  _wd_emit_fixture "$LEDGER4" "fixture-gate-c" 12
  _wd_emit_fixture "$LEDGER4" "fixture-gate-c" 20
  OUT4="$( SIGNAL_LEDGER_PATH="$LEDGER4" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG4" bash "$SELF_ABS" --digest-line )"
  if [[ -z "$OUT4" ]]; then
    pass "3 waivers all older than 7d -> no digest line (window excludes them)"
  else
    fail "expected empty output for out-of-window waivers, got: $OUT4"
  fi

  # ------------------------------------------------------------
  # Scenario 5: non-waiver events (block/warn/downgrade/skip) never count
  # toward the density alarm.
  # ------------------------------------------------------------
  echo "Scenario 5: non-waiver events are excluded from the count"
  LEDGER5="$TMP/s5-ledger.jsonl"
  BACKLOG5="$TMP/s5-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG5"
  local_ts="$(_wd_now_iso)"
  {
    printf '{"ts":"%s","session_id":"selftest","gate":"fixture-gate-d","event":"block","detail":"x"}\n' "$local_ts"
    printf '{"ts":"%s","session_id":"selftest","gate":"fixture-gate-d","event":"warn","detail":"x"}\n' "$local_ts"
    printf '{"ts":"%s","session_id":"selftest","gate":"fixture-gate-d","event":"downgrade","detail":"x"}\n' "$local_ts"
    printf '{"ts":"%s","session_id":"selftest","gate":"fixture-gate-d","event":"skip","detail":"x"}\n' "$local_ts"
  } > "$LEDGER5"
  OUT5="$( SIGNAL_LEDGER_PATH="$LEDGER5" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG5" bash "$SELF_ABS" --digest-line )"
  if [[ -z "$OUT5" ]]; then
    pass "block/warn/downgrade/skip events never trigger the waiver alarm"
  else
    fail "expected empty output (non-waiver events only), got: $OUT5"
  fi

  # ------------------------------------------------------------
  # Scenario 6: multiple gates over threshold -> EACH gets its own backlog
  # entry, digest line reports the MAX gate.
  # ------------------------------------------------------------
  echo "Scenario 6: multiple over-threshold gates each get a backlog entry; digest reports the max"
  LEDGER6="$TMP/s6-ledger.jsonl"
  BACKLOG6="$TMP/s6-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG6"
  for i in 1 2 3; do _wd_emit_fixture "$LEDGER6" "gate-small" "$i"; done
  for i in 1 2 3 4 5; do _wd_emit_fixture "$LEDGER6" "gate-big" "$i"; done
  OUT6="$( SIGNAL_LEDGER_PATH="$LEDGER6" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG6" bash "$SELF_ABS" --digest-line )"
  if printf '%s' "$OUT6" | grep -qE '^waiver-density: gate-big 5 waivers/7d -> fix-or-retire item filed$'; then
    pass "digest line reports the gate with the HIGHEST count (gate-big, 5)"
  else
    fail "expected digest line for gate-big/5, got: $OUT6"
  fi
  TODAY_BIG="WAIVER-DENSITY-GATE-BIG-$(date -u '+%Y%m%d')"
  TODAY_SMALL="WAIVER-DENSITY-GATE-SMALL-$(date -u '+%Y%m%d')"
  if grep -q "$TODAY_BIG" "$BACKLOG6" && grep -q "$TODAY_SMALL" "$BACKLOG6"; then
    pass "BOTH over-threshold gates got their own backlog entry (not just the max)"
  else
    fail "expected both $TODAY_BIG and $TODAY_SMALL in backlog, got: $(cat "$BACKLOG6")"
  fi

  # ------------------------------------------------------------
  # Scenario 7: --report mode renders a table for ALL gates with any waiver
  # in-window (including below-threshold ones) and performs NO backlog
  # side effect.
  # ------------------------------------------------------------
  echo "Scenario 7: --report renders all gates, no backlog side effect"
  LEDGER7="$TMP/s7-ledger.jsonl"
  BACKLOG7="$TMP/s7-backlog.md"
  printf '# fixture backlog\n' > "$BACKLOG7"
  for i in 1 2 3; do _wd_emit_fixture "$LEDGER7" "gate-over" "$i"; done
  _wd_emit_fixture "$LEDGER7" "gate-under" 1
  OUT7="$( SIGNAL_LEDGER_PATH="$LEDGER7" WAIVER_DENSITY_BACKLOG_PATH="$BACKLOG7" bash "$SELF_ABS" --report )"
  if printf '%s' "$OUT7" | grep -q "gate-over" && printf '%s' "$OUT7" | grep -q "gate-under"; then
    pass "--report lists both the over- and under-threshold gate"
  else
    fail "expected both gates in report, got: $OUT7"
  fi
  if printf '%s' "$OUT7" | grep -E '^\| gate-over \|' | grep -q "YES"; then
    pass "--report marks gate-over as over threshold"
  else
    fail "expected gate-over row marked YES, got: $OUT7"
  fi
  if printf '%s' "$OUT7" | grep -E '^\| gate-under \|' | grep -q "no"; then
    pass "--report marks gate-under as NOT over threshold"
  else
    fail "expected gate-under row marked no, got: $OUT7"
  fi
  if ! grep -q "WAIVER-DENSITY-GATE-OVER-" "$BACKLOG7"; then
    pass "--report performs no backlog side effect"
  else
    fail "--report unexpectedly appended a backlog entry: $(cat "$BACKLOG7")"
  fi

  # ------------------------------------------------------------
  # Scenario 8: empty/missing ledger -> --digest-line silent, --report says
  # so honestly, neither crashes.
  # ------------------------------------------------------------
  echo "Scenario 8: missing ledger is tolerated (no crash, honest report)"
  MISSING_LEDGER="$TMP/does-not-exist.jsonl"
  set +e
  OUT8A="$( SIGNAL_LEDGER_PATH="$MISSING_LEDGER" bash "$SELF_ABS" --digest-line )"
  RC8A=$?
  OUT8B="$( SIGNAL_LEDGER_PATH="$MISSING_LEDGER" bash "$SELF_ABS" --report )"
  RC8B=$?
  set -e
  if [[ "$RC8A" -eq 0 ]] && [[ -z "$OUT8A" ]]; then
    pass "missing ledger -> --digest-line exit 0, empty output"
  else
    fail "expected exit 0 + empty output for --digest-line on missing ledger, got rc=$RC8A out=$OUT8A"
  fi
  if [[ "$RC8B" -eq 0 ]] && printf '%s' "$OUT8B" | grep -q "No waiver events recorded"; then
    pass "missing ledger -> --report exit 0, honest 'no waivers' message"
  else
    fail "expected honest no-waivers report, got rc=$RC8B out=$OUT8B"
  fi

  # ------------------------------------------------------------
  # Scenario 9: the REAL (non-sandbox) docs/backlog.md was never touched by
  # any scenario above.
  # ------------------------------------------------------------
  echo "Scenario 9: the real repo docs/backlog.md was not touched by this self-test"
  REAL_BACKLOG_HITS=0
  if _have nl_repo_root; then
    REAL_ROOT="$(nl_repo_root)"
    if [[ -n "$REAL_ROOT" && -f "$REAL_ROOT/docs/backlog.md" ]]; then
      REAL_BACKLOG_HITS=$(grep -c "WAIVER-DENSITY-FIXTURE-GATE-A-\|WAIVER-DENSITY-GATE-BIG-\|WAIVER-DENSITY-GATE-SMALL-\|WAIVER-DENSITY-GATE-OVER-" "$REAL_ROOT/docs/backlog.md" 2>/dev/null | tr -d ' ')
    fi
  fi
  if [[ "${REAL_BACKLOG_HITS:-0}" == "0" ]]; then
    pass "the real repo docs/backlog.md was NOT modified by this self-test"
  else
    fail "the REAL docs/backlog.md was unexpectedly modified by the self-test"
  fi

  # ------------------------------------------------------------
  # Scenario 10: HARNESS_SELFTEST sandbox — ledger path resolves under the
  # SAME sandbox convention as lib/signal-ledger.sh (never the real
  # production ledger) when no explicit override is set.
  # ------------------------------------------------------------
  echo "Scenario 10: HARNESS_SELFTEST sandbox path resolution matches signal-ledger.sh"
  (
    unset SIGNAL_LEDGER_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_wd_ledger_path)"
    case "$resolved" in
      "${TMPDIR:-/tmp}"/signal-ledger-selftest/*) exit 0 ;;
      *) exit 1 ;;
    esac
  )
  if [[ $? -eq 0 ]]; then
    pass "HARNESS_SELFTEST sandbox path resolution (shared with signal-ledger.sh)"
  else
    fail "sandbox path resolution did not match the expected shape"
  fi
  (
    unset SIGNAL_LEDGER_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_wd_ledger_path)"
    [[ "$resolved" != "${HOME:-}/.claude/state/signal-ledger.jsonl" ]]
  )
  if [[ $? -eq 0 ]]; then
    pass "sandbox path never equals the production ledger path"
  else
    fail "sandbox path incorrectly resolved to the production ledger path"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
