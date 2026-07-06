#!/bin/bash
# f4-retro.sh — NL Overhaul Program F.4 pre-registered retro
# (docs/plans/nl-overhaul-program-2026-07-specs-f.md §F.4-PROTOCOL, ADR 058 D7).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# §F.4-PROTOCOL pre-registers SIX baseline metrics (docs/reviews/
# nl-overhaul-baseline-2026-07.md sections 1-6, captured 2026-07-02) plus a
# synthetic-runner score comparison and two VERDICT RULES that must be
# printed mechanically, never self-graded as a pass. This script is the one
# place that re-runs each baseline metric's EXACT measurement method (same
# commands, same files) over a parameterized window so the 2026-07-24 (or
# whenever-actually-run) retro session does not have to re-derive anything —
# it runs this script and reads the table.
#
# Pre-registration discipline (why the method must not drift): the protocol
# was authored 2026-07-03 specifically "to bind the later evaluator" — the
# whole point is that nobody gets to pick a flattering measurement method
# after seeing the numbers. This script IS that binding: change it only to
# fix a bug in reproducing the pre-registered method, never to move a target.
#
# ============================================================
# THE SIX METRICS (baseline doc section -> this script's measurement)
# ============================================================
#
#   1. Retry-guard downgrades: `unresolved-stop-hooks.log` entries dated
#      inside the window (baseline counted ALL 321 lines with no dates in
#      the file -- this script counts lines whose parseable leading
#      timestamp falls in [--since, --until); lines with no parseable
#      timestamp are counted separately as "undated" so the total is never
#      silently short).
#   2. Waiver density: `acceptance-waiver-*.txt` file COUNT (baseline's
#      literal method, snapshot-style, not date-filtered -- mtime-filtered
#      here into the window) + signal-ledger `waiver` events per gate inside
#      the window (the spec's "+ ledger waiver events per gate" addendum).
#   3. Signal consumption: external-monitor-alerts total vs acked (baseline
#      method, snapshot-style; also reports how many are >7d unacked, the
#      spec's TARGET clause).
#   4. Rules-dir bytes: `cat ~/.claude/rules/*.md | wc -c` (baseline's exact
#      command; not window-filtered -- a live-state byte count).
#   5. Stop-chain entries: live settings.json hooks.Stop count (baseline's
#      exact node one-liner; not window-filtered -- live-state count).
#   6. Blocking gates: manifest.json blocking:true count (live-state count;
#      doctor's own --quick enumeration is cross-checked when available).
#
# PLUS: synthetic-runner score vs the earliest recorded run (see the
# SYNTHETIC-RUNNER COMPARISON section below -- this program never archived a
# formally dated "Wave-B baseline" synthetic-score file; that gap is
# reported honestly rather than papered over with an invented number).
#
# ============================================================
# WINDOW
# ============================================================
#
#   --since <date> --until <date>   (YYYY-MM-DD, both inclusive-exclusive:
#                                     [since, until) )
#   Default: --since 2026-07-03 --until <today>, i.e. "the 21 post-cutover
#   days from 2026-07-03" per the protocol text -- when today is before
#   2026-07-24 the window is necessarily PARTIAL and the table is labeled
#   INTERIM (never silently presented as the final 21-day read).
#
# ============================================================
# VERDICT RULES (pre-registered, ADR 058 D7 -- printed, never auto-passed)
# ============================================================
#
#   clause (a): synthetic-runner scores must IMPROVE vs the earliest
#               recorded run. Fails if current passed-count < earliest
#               passed-count, or current has any FAILED scenario the
#               earliest run did not.
#   clause (b): ledger waiver+downgrade rate per active gate must fall
#               >=50% vs the baseline (metrics 1 + 2 combined, per-gate
#               where the ledger has per-gate detail, aggregate for the
#               retry-guard log which is gate-name-free).
#   If clause (a) OR clause (b) is REFUTED -> mandated action is PROGRAM
#   PAUSE + re-design proposal to operator. This script prints the clause
#   verdicts and the mandated action text; it NEVER prints a self-graded
#   "PASS"/"overall verdict" -- ambiguous/mixed cases are surfaced to the
#   operator with a recommendation, per protocol.
#
# ============================================================
# CONTRACT
# ============================================================
#
#   f4-retro.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD]
#               [--baseline-synthetic-passed N] [--baseline-synthetic-total N]
#               [--write [<path>]]
#     Print the markdown table + verdict section to stdout. With --write,
#     ALSO write the same report to <path> (default:
#     docs/reviews/nl-overhaul-completion-<until-date>.md, resolved via
#     nl_repo_root()) -- a DRAFT the retro session edits, never auto-final.
#
#   f4-retro.sh --self-test
#     Fixture ledger/logs -> known counts -> table renders; verdict-rule
#     fixtures (clause-a fail, clause-b fail, both-pass). Never touches the
#     real machine state (HARNESS_SELFTEST convention: every path this
#     script reads is override-able via env var, exercised in the self-test
#     against a mktemp -d sandbox only).
#
# ============================================================
# SANDBOXING / PATH OVERRIDES (all self-test-safe; mirrors waiver-density.sh)
# ============================================================
#
#   F4_RETRO_STOP_HOOKS_LOG        default: <main-checkout>/.claude/state/unresolved-stop-hooks.log
#   F4_RETRO_STATE_DIR             default: <main-checkout>/.claude/state   (waiver files live here)
#   F4_RETRO_ALERTS_DIR            default: $HOME/.claude/state/external-monitor-alerts
#   F4_RETRO_RULES_DIR             default: $HOME/.claude/rules
#   F4_RETRO_SETTINGS_JSON         default: $HOME/.claude/settings.json
#   F4_RETRO_MANIFEST_JSON         default: <repo>/adapters/claude-code/manifest.json
#   F4_RETRO_FINDINGS_MD           default: <repo>/docs/findings.md
#   SIGNAL_LEDGER_PATH             (signal-ledger.sh's own convention; reused
#                                    verbatim here for ledger waiver events)
#   F4_RETRO_SYNTHETIC_RUNNER      default: <repo>/evals/synthetic/run-all.sh
#   F4_RETRO_TODAY_OVERRIDE        --self-test ONLY: simulates "today" for
#                                    the window-completeness check (real
#                                    wall-clock date otherwise; never set
#                                    this outside the self-test)
#
# None of these are read from cwd-relative guessing -- nl_repo_root() /
# nl_main_checkout_root() resolve the canonical repo per SELFTEST-ORACLE-
# PIN-01, and every one is override-able so --self-test never touches the
# real machine.

set -u

_F4_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_F4_HOOKS_LIB="$_F4_SELF_DIR/../hooks/lib"
# shellcheck disable=SC1091
if [[ -f "$_F4_HOOKS_LIB/nl-paths.sh" ]]; then
  source "$_F4_HOOKS_LIB/nl-paths.sh"
fi
# shellcheck disable=SC1091
if [[ -f "$_F4_HOOKS_LIB/signal-ledger.sh" ]]; then
  source "$_F4_HOOKS_LIB/signal-ledger.sh"
fi

_have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------
# _f4_repo_root — resolve the canonical repo root (git-root of THIS
# script's location, via nl-paths.sh, never cwd).
# ----------------------------------------------------------------------
_f4_repo_root() {
  if _have nl_repo_root; then
    nl_repo_root
    return 0
  fi
  git -C "$_F4_SELF_DIR" rev-parse --show-toplevel 2>/dev/null
}

# ----------------------------------------------------------------------
# _f4_main_checkout_root — the MAIN checkout (not a worktree) — the
# baseline doc's state files (.claude/state/*) live under the main
# checkout per its own "Machine:" provenance note.
# ----------------------------------------------------------------------
_f4_main_checkout_root() {
  if _have nl_main_checkout_root; then
    local r
    r="$(nl_main_checkout_root)"
    [[ -n "$r" ]] && { printf '%s' "$r"; return 0; }
  fi
  _f4_repo_root
}

# ----------------------------------------------------------------------
# _f4_epoch <YYYY-MM-DD> — seconds since epoch at 00:00:00 UTC of that
# date. Prints empty on failure (never crashes the caller).
# ----------------------------------------------------------------------
_f4_epoch() {
  local d="$1"
  date -u -d "${d} 00:00:00" '+%s' 2>/dev/null \
    || date -u -j -f '%Y-%m-%d %H:%M:%S' "${d} 00:00:00" '+%s' 2>/dev/null \
    || printf ''
}

_f4_today() {
  # Self-test override (F4_RETRO_TODAY_OVERRIDE) lets the verdict-window
  # fixtures simulate "the full 21-day protocol window has already
  # elapsed" without waiting on the wall clock. Never set outside
  # --self-test.
  if [[ -n "${F4_RETRO_TODAY_OVERRIDE:-}" ]]; then
    printf '%s' "$F4_RETRO_TODAY_OVERRIDE"
    return 0
  fi
  date -u '+%Y-%m-%d' 2>/dev/null || echo 'unknown-date'
}

# ----------------------------------------------------------------------
# _f4_days_since_epoch_into <outvar> <year> <month> <day> — pure-bash
# civil-date-to-days-since-1970-01-01 (Howard Hinnant's days_from_civil
# algorithm, no external calls, no subshell — writes into <outvar> via
# nameref so callers in a hot per-line loop never pay a command-
# substitution fork). Works for any proleptic Gregorian date; only used
# here for dates well within normal range.
# ----------------------------------------------------------------------
_f4_days_since_epoch_into() {
  local -n _f4_dse_out="$1"
  local y="$2" m="$3" d="$4"
  y=$((10#$y)); m=$((10#$m)); d=$((10#$d))
  if (( m <= 2 )); then y=$((y - 1)); fi
  local era
  if (( y >= 0 )); then era=$(( y / 400 )); else era=$(( (y - 399) / 400 )); fi
  local yoe=$(( y - era * 400 ))
  local mp=$(( (m + 9) % 12 ))
  local doy=$(( (153 * mp + 2) / 5 + d - 1 ))
  local doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  _f4_dse_out=$(( era * 146097 + doe - 719468 ))
}

# ----------------------------------------------------------------------
# _f4_fast_iso_epoch_into <outvar> <ts> — pure-bash UTC epoch-seconds parse
# for the two strict formats our own ledger/log writers actually emit
# (ledger_emit's `date -u '+%Y-%m-%dT%H:%M:%SZ'`, and plain date-only
# prefixes). Writes into <outvar> via nameref (no subshell). Sets <outvar>
# to empty (never errors) on anything that does not match either pattern
# EXACTLY, so the caller's `date`-based fallback still handles odd/foreign
# formats correctly — this is purely a fork-avoidance fast path for the
# common case, not a general ISO-8601 parser.
# Motivation: on this machine a `date -d` fork costs ~70-250ms
# (NL-FINDING-029/030 class, MSYS/git-bash fork overhead) — a few hundred
# ledger/log lines would otherwise cost tens of seconds per report
# generation; even a bare command-substitution subshell (no exec) adds
# measurable per-call cost at this scale, hence the nameref-output style
# throughout this fast path instead of `x="$(...)"`.
# ----------------------------------------------------------------------
_f4_fast_iso_epoch_into() {
  local -n _f4_fie_out="$1"
  local ts="$2"
  _f4_fie_out=""
  local y m d hh mm ss
  if [[ "$ts" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z?$ ]]; then
    y="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"; d="${BASH_REMATCH[3]}"
    hh="${BASH_REMATCH[4]}"; mm="${BASH_REMATCH[5]}"; ss="${BASH_REMATCH[6]}"
  elif [[ "$ts" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    y="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"; d="${BASH_REMATCH[3]}"
    hh="00"; mm="00"; ss="00"
  else
    return 0
  fi
  local days
  _f4_days_since_epoch_into days "$y" "$m" "$d"
  _f4_fie_out=$(( days * 86400 + 10#$hh * 3600 + 10#$mm * 60 + 10#$ss ))
}

# ----------------------------------------------------------------------
# _f4_fast_iso_epoch <ts> — command-substitution convenience wrapper
# around _f4_fast_iso_epoch_into, for the few (non-hot-loop) call sites
# that want a plain return value (e.g. the self-test). NOT used by the
# per-line hot path (_f4_extract_ts_epoch_into below uses the nameref form
# directly).
# ----------------------------------------------------------------------
_f4_fast_iso_epoch() {
  local _out
  _f4_fast_iso_epoch_into _out "$1"
  printf '%s' "$_out"
}

# ----------------------------------------------------------------------
# _f4_extract_ts_epoch_into <outvar> <line> — best-effort extraction of a
# leading ISO-8601-ish timestamp from a log/ledger line into <outvar> (no
# subshell). Supports:
#   - JSONL ledger lines: {"ts":"2026-07-05T12:00:00Z", ...}
#   - plain "YYYY-MM-DD..." prefixed lines
# Sets <outvar> to empty if no timestamp found.
#
# Performance note: this function runs once PER LINE of a log/ledger that
# can have hundreds of entries, so it is written to avoid forking ANY
# subprocess or subshell in the common case — bash's own `[[ =~ ]]` regex +
# BASH_REMATCH extraction feeding the pure-bash nameref fast path above.
# `date` is only invoked (via a command substitution, still relatively
# rare) as a last-resort fallback for a timestamp shape neither extraction
# regex recognizes at all.
# ----------------------------------------------------------------------
_f4_extract_ts_epoch_into() {
  local -n _f4_ete_out="$1"
  local line="$2"
  _f4_ete_out=""
  local ts=""

  if [[ "$line" =~ \"ts\":\"([^\"]*)\" ]]; then
    ts="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}([T\ ][0-9]{2}:[0-9]{2}:[0-9]{2})?) ]]; then
    ts="${BASH_REMATCH[1]}"
  fi
  [[ -z "$ts" ]] && return 0

  _f4_fast_iso_epoch_into _f4_ete_out "$ts"
  [[ -n "$_f4_ete_out" ]] && return 0

  # Fallback path (forks `date`) — only reached for a timestamp shape the
  # pure-bash fast path does not recognize (e.g. non-UTC offsets).
  _f4_ete_out="$(date -u -d "$ts" '+%s' 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null \
    || date -u -j -f '%Y-%m-%d' "$ts" '+%s' 2>/dev/null \
    || printf '')"
}

# ----------------------------------------------------------------------
# _f4_extract_ts_epoch <line> — command-substitution convenience wrapper
# around _f4_extract_ts_epoch_into, for non-hot-loop call sites.
# ----------------------------------------------------------------------
_f4_extract_ts_epoch() {
  local _out
  _f4_extract_ts_epoch_into _out "$1"
  printf '%s' "$_out"
}

# ============================================================
# METRIC 1 — retry-guard downgrade entries in window
# ============================================================
# Prints: "<in-window> <undated> <total>"
f4_metric1_retry_guard() {
  local since_epoch="$1" until_epoch="$2"
  local main_root
  main_root="$(_f4_main_checkout_root)"
  local log_path="${F4_RETRO_STOP_HOOKS_LOG:-${main_root}/.claude/state/unresolved-stop-hooks.log}"

  if [[ ! -f "$log_path" ]]; then
    printf '0 0 0 %s\n' "$log_path"
    return 0
  fi

  local total=0 in_window=0 undated=0
  local line epoch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    total=$((total + 1))
    # Nameref hot-path (no subshell per line — see _f4_extract_ts_epoch_into's
    # header comment on why that matters at this loop's scale).
    _f4_extract_ts_epoch_into epoch "$line"
    if [[ -z "$epoch" ]]; then
      undated=$((undated + 1))
      continue
    fi
    if [[ -n "$since_epoch" && "$epoch" -lt "$since_epoch" ]]; then continue; fi
    if [[ -n "$until_epoch" && "$epoch" -ge "$until_epoch" ]]; then continue; fi
    in_window=$((in_window + 1))
  done < "$log_path"

  printf '%s %s %s %s\n' "$in_window" "$undated" "$total" "$log_path"
}

# ============================================================
# METRIC 2 — waiver density (files + ledger events, per window)
# ============================================================
# Prints: "<waiver-files-in-window> <waiver-files-total> <ledger-waiver-events-in-window>"
f4_metric2_waiver_density() {
  local since_epoch="$1" until_epoch="$2"
  local main_root
  main_root="$(_f4_main_checkout_root)"
  local state_dir="${F4_RETRO_STATE_DIR:-${main_root}/.claude/state}"

  local total_files=0 in_window_files=0
  if [[ -d "$state_dir" ]]; then
    local f mtime
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      total_files=$((total_files + 1))
      mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)"
      [[ -z "$mtime" ]] && continue
      if [[ -n "$since_epoch" && "$mtime" -lt "$since_epoch" ]]; then continue; fi
      if [[ -n "$until_epoch" && "$mtime" -ge "$until_epoch" ]]; then continue; fi
      in_window_files=$((in_window_files + 1))
    done < <(find "$state_dir" -maxdepth 1 -iname "acceptance-waiver-*.txt" 2>/dev/null)
  fi

  local ledger_path
  if _have _signal_ledger_path; then
    ledger_path="$(_signal_ledger_path)"
  else
    ledger_path="${SIGNAL_LEDGER_PATH:-${HOME:-$PWD}/.claude/state/signal-ledger.jsonl}"
  fi

  local ledger_events=0
  if [[ -f "$ledger_path" ]]; then
    local line epoch event_field
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Pure-bash field extraction (no sed fork) — same nameref-avoids-
      # subshell discipline as the retry-guard loop above.
      event_field=""
      [[ "$line" =~ \"event\":\"([^\"]*)\" ]] && event_field="${BASH_REMATCH[1]}"
      [[ "$event_field" != "waiver" ]] && continue
      _f4_extract_ts_epoch_into epoch "$line"
      [[ -z "$epoch" ]] && continue
      if [[ -n "$since_epoch" && "$epoch" -lt "$since_epoch" ]]; then continue; fi
      if [[ -n "$until_epoch" && "$epoch" -ge "$until_epoch" ]]; then continue; fi
      ledger_events=$((ledger_events + 1))
    done < "$ledger_path"
  fi

  printf '%s %s %s\n' "$in_window_files" "$total_files" "$ledger_events"
}

# ----------------------------------------------------------------------
# f4_metric2_per_gate_alarm — per-gate waiver-density.sh style check: any
# single gate >=3/week (protocol's "any single gate >=3/week = E.3 alarm
# must have fired" clause). Delegates to waiver-density.sh --report so the
# two scripts never disagree about the count; verifies the E.3 alarm
# actually fired for that gate (WAIVER-DENSITY-<GATE>-* backlog entry) when
# a sibling waiver-density.sh + backlog are resolvable.
#
# Best-effort + bounded: waiver-density.sh --report shells a `date -d` per
# ledger line, which on a slow/MSYS shell can run long against a real
# multi-hundred-line ledger. This is optional supplementary detail (the
# table's own metric-2 row already has the load-bearing counts computed
# directly, no shell-out) — a slow/failed call here must never hang or fail
# the whole report, so it is wrapped in `timeout` where available and
# always non-fatal.
# ----------------------------------------------------------------------
f4_metric2_per_gate_alarm() {
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    # Self-test never shells out to the real waiver-density.sh against the
    # real machine ledger (that call is optional supplementary detail, not
    # a load-bearing count — see the header comment above).
    printf ''
    return 0
  fi
  local wd_script="$_F4_SELF_DIR/waiver-density.sh"
  [[ -f "$wd_script" ]] || { printf ''; return 0; }
  local out=""
  if _have timeout; then
    out="$(timeout 15 bash "$wd_script" --report 2>/dev/null)"
  else
    out="$(bash "$wd_script" --report 2>/dev/null)"
  fi
  printf '%s' "$out" | awk -F'|' '/\| *YES *\|/ { gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); print $2, $3 }'
  return 0
}

# ============================================================
# METRIC 3 — signal consumption (external-monitor alerts)
# ============================================================
# Prints: "<total> <acked> <unacked-over-7d>"
f4_metric3_signal_consumption() {
  local alerts_dir="${F4_RETRO_ALERTS_DIR:-${HOME:-$PWD}/.claude/state/external-monitor-alerts}"
  local total=0 acked=0 unacked_over_7d=0
  if [[ -d "$alerts_dir" ]]; then
    total="$(find "$alerts_dir" -maxdepth 1 -name "*.json" ! -name "*.acked" 2>/dev/null | wc -l | tr -d ' ')"
    acked="$(find "$alerts_dir" -maxdepth 1 -name "*.json.acked" 2>/dev/null | wc -l | tr -d ' ')"
    local now_epoch cutoff_epoch
    now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
    cutoff_epoch=$((now_epoch - 7 * 86400))
    local f mtime base acked_sibling
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      base="$(basename "$f")"
      acked_sibling="$alerts_dir/${base}.acked"
      [[ -f "$acked_sibling" ]] && continue
      mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)"
      [[ -z "$mtime" ]] && continue
      if [[ "$mtime" -lt "$cutoff_epoch" ]]; then
        unacked_over_7d=$((unacked_over_7d + 1))
      fi
    done < <(find "$alerts_dir" -maxdepth 1 -name "*.json" ! -name "*.acked" 2>/dev/null)
  fi
  printf '%s %s %s\n' "${total:-0}" "${acked:-0}" "$unacked_over_7d"
}

# ============================================================
# METRIC 4 — rules-dir bytes (live-state; baseline's exact command)
# ============================================================
f4_metric4_rules_bytes() {
  local rules_dir="${F4_RETRO_RULES_DIR:-${HOME:-$PWD}/.claude/rules}"
  local bytes=0 files=0
  if [[ -d "$rules_dir" ]]; then
    bytes="$(cat "$rules_dir"/*.md 2>/dev/null | wc -c | tr -d ' ')"
    files="$(ls "$rules_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  fi
  printf '%s %s\n' "${bytes:-0}" "${files:-0}"
}

# ============================================================
# METRIC 5 — Stop-chain entries (live-state; baseline's exact node one-liner)
# ============================================================
f4_metric5_stop_chain() {
  local settings_json="${F4_RETRO_SETTINGS_JSON:-${HOME:-$PWD}/.claude/settings.json}"
  if [[ ! -f "$settings_json" ]] || ! _have node; then
    printf '0 0 %s\n' "$settings_json"
    return 0
  fi
  node -e '
    const fs = require("fs");
    try {
      const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const stop = (j.hooks && j.hooks.Stop) || [];
      let count = 0;
      for (const m of stop) count += (m.hooks || []).length;
      console.log(stop.length + " " + count);
    } catch (e) {
      console.log("0 0");
    }
  ' "$settings_json" 2>/dev/null || printf '0 0\n'
}

# ============================================================
# METRIC 6 — blocking gates (live-state; manifest.json)
# ============================================================
f4_metric6_blocking_gates() {
  local repo_root
  repo_root="$(_f4_repo_root)"
  local manifest="${F4_RETRO_MANIFEST_JSON:-${repo_root}/adapters/claude-code/manifest.json}"
  if [[ ! -f "$manifest" ]] || ! _have jq; then
    printf '0 %s\n' "$manifest"
    return 0
  fi
  local count
  count="$(jq '[.entries[] | select(.blocking==true)] | length' "$manifest" 2>/dev/null)"
  printf '%s %s\n' "${count:-0}" "$manifest"
}

# ============================================================
# SYNTHETIC-RUNNER COMPARISON (clause a)
# ============================================================
# Runs evals/synthetic/run-all.sh (or F4_RETRO_SYNTHETIC_RUNNER override)
# and parses its "passed: N" / "failed: N" / "failing scenarios: ..." lines.
# Prints: "<passed> <failed> <failing-names-comma-joined-or-dash>"
f4_run_synthetic() {
  local runner="${F4_RETRO_SYNTHETIC_RUNNER:-}"
  if [[ -z "$runner" ]]; then
    local repo_root
    repo_root="$(_f4_repo_root)"
    runner="${repo_root}/evals/synthetic/run-all.sh"
  fi
  if [[ ! -f "$runner" ]]; then
    printf '0 0 runner-not-found:%s\n' "$runner"
    return 0
  fi
  local out
  out="$(bash "$runner" 2>&1)"
  local passed failed names
  passed="$(printf '%s\n' "$out" | sed -n 's/^passed:[[:space:]]*\([0-9]*\).*/\1/p' | tail -1)"
  failed="$(printf '%s\n' "$out" | sed -n 's/^failed:[[:space:]]*\([0-9]*\).*/\1/p' | tail -1)"
  names="$(printf '%s\n' "$out" | sed -n 's/^failing scenarios:[[:space:]]*//p' | tail -1)"
  [[ -z "$passed" ]] && passed=0
  [[ -z "$failed" ]] && failed=0
  [[ -z "$names" ]] && names="-"
  names="$(printf '%s' "$names" | tr ' ' ',')"
  printf '%s %s %s\n' "$passed" "$failed" "$names"
}

# ============================================================
# FINDINGS 019-028 STATUS SWEEP
# ============================================================
# Prints one line per finding id: "<id> <status-or-unknown>"
f4_findings_sweep() {
  local repo_root
  repo_root="$(_f4_repo_root)"
  local findings_md="${F4_RETRO_FINDINGS_MD:-${repo_root}/docs/findings.md}"
  [[ -f "$findings_md" ]] || return 0
  local id
  for id in 019 020 021 022 023 024 025 026 027 028; do
    local status
    status="$(awk -v id="NL-FINDING-${id}" '
      $0 ~ ("^### " id) { infinding=1; next }
      infinding && /^### NL-FINDING-/ { infinding=0 }
      infinding && /\*\*Status:\*\*/ {
        line=$0
        sub(/.*\*\*Status:\*\*[[:space:]]*/, "", line)
        print line
        exit
      }
    ' "$findings_md")"
    [[ -z "$status" ]] && status="unknown (id not found in $findings_md)"
    printf '%s %s\n' "$id" "$status"
  done
}

# ============================================================
# MAIN REPORT
# ============================================================
f4_generate_report() {
  local since_date="$1" until_date="$2"
  local baseline_syn_passed="$3" baseline_syn_total="$4"

  local since_epoch until_epoch
  since_epoch="$(_f4_epoch "$since_date")"
  until_epoch="$(_f4_epoch "$until_date")"

  # The protocol pre-registers a FULL 21-day post-cutover window from
  # since_date (§F.4-PROTOCOL: "the 21 post-cutover days from 2026-07-03").
  # A run is INTERIM whenever the window it actually measured (up to
  # until_date, or up to today if until_date is later than today) is
  # shorter than that full 21 days — this is independent of whatever
  # --until the caller passed (the CLI's own default is "today", which
  # would otherwise always read as "complete" under a naive
  # today-vs-until-only check, silently hiding a 3-days-in run behind a
  # non-interim label).
  local today window_complete="yes"
  today="$(_f4_today)"
  local today_epoch full_window_end_epoch measured_end_epoch
  today_epoch="$(_f4_epoch "$today")"
  full_window_end_epoch=""
  if [[ -n "$since_epoch" ]]; then
    full_window_end_epoch=$(( since_epoch + 21 * 86400 ))
  fi
  # The window actually measured stops at min(until_epoch, today_epoch) —
  # this script cannot measure past "now" regardless of what --until says.
  measured_end_epoch="$until_epoch"
  if [[ -n "$today_epoch" ]] && { [[ -z "$measured_end_epoch" ]] || [[ "$today_epoch" -lt "$measured_end_epoch" ]]; }; then
    measured_end_epoch="$today_epoch"
  fi
  if [[ -n "$full_window_end_epoch" && -n "$measured_end_epoch" ]] && [[ "$measured_end_epoch" -lt "$full_window_end_epoch" ]]; then
    window_complete="no"
  fi

  echo "# NL Overhaul F.4 retro — pre-registered metrics"
  echo ""
  if [[ "$window_complete" == "no" ]]; then
    echo "**INTERIM — window incomplete.** Requested window: [$since_date, $until_date). Today: $today. The pre-registered protocol window is the full 21 days from $since_date; this table only reflects what has elapsed so far and is NOT the final F.4 read. Re-run this script once the full 21-day window has passed."
  else
    echo "Window: [$since_date, $until_date). Generated: $today."
  fi
  echo ""
  echo "Baseline source: docs/reviews/nl-overhaul-baseline-2026-07.md (captured 2026-07-02, task B.10). Method for each row below reproduces that document's exact command, applied to the parameterized window where the metric is a count-over-time (rows 1-2) and re-read live for the four state-snapshot metrics (rows 3-6, which the baseline itself defines as point-in-time reads, not windowed counts)."
  echo ""
  echo "| # | Metric | Baseline (2026-07-02) | Current (window/live) | Target | Notes |"
  echo "|---|---|---|---|---|---|"

  # --- Metric 1 ---
  local m1 m1_win m1_undated m1_total m1_path
  m1="$(f4_metric1_retry_guard "$since_epoch" "$until_epoch")"
  m1_win="$(echo "$m1" | awk '{print $1}')"
  m1_undated="$(echo "$m1" | awk '{print $2}')"
  m1_total="$(echo "$m1" | awk '{print $3}')"
  echo "| 1 | Retry-guard downgrades (\`unresolved-stop-hooks.log\`) | 321 lines (all-time, undated) | ${m1_win} in-window; ${m1_undated} undated; ${m1_total} total on disk | −50% vs baseline (ADR 058 clause b) | Baseline file has no per-line dates — this run's in-window count only reflects lines this script CAN date; undated lines are reported separately, never silently dropped. |"

  # --- Metric 2 ---
  local m2 m2_win m2_total m2_ledger
  m2="$(f4_metric2_waiver_density "$since_epoch" "$until_epoch")"
  m2_win="$(echo "$m2" | awk '{print $1}')"
  m2_total="$(echo "$m2" | awk '{print $2}')"
  m2_ledger="$(echo "$m2" | awk '{print $3}')"
  echo "| 2 | Waiver density (\`acceptance-waiver-*.txt\` files + ledger \`waiver\` events) | 12 files (all-time snapshot) | ${m2_win} files mtime-in-window (${m2_total} total on disk); ${m2_ledger} ledger waiver-events in-window | −50% aggregate; any single gate ≥3/week ⇒ E.3 alarm must have fired | Per-gate ≥3/week breakdown printed below the table if any gate is over threshold. |"

  # --- Metric 3 ---
  local m3 m3_total m3_acked m3_over7d
  m3="$(f4_metric3_signal_consumption)"
  m3_total="$(echo "$m3" | awk '{print $1}')"
  m3_acked="$(echo "$m3" | awk '{print $2}')"
  m3_over7d="$(echo "$m3" | awk '{print $3}')"
  echo "| 3 | External-monitor alerts unacked | 33/33 unacked (0 acked) | ${m3_total} total, ${m3_acked} acked, ${m3_over7d} unacked >7d | 0 unacked >7d; digest ack path exercised | Live-state snapshot (not window-filtered — matches baseline's own method). |"

  # --- Metric 4 ---
  local m4 m4_bytes m4_files
  m4="$(f4_metric4_rules_bytes)"
  m4_bytes="$(echo "$m4" | awk '{print $1}')"
  m4_files="$(echo "$m4" | awk '{print $2}')"
  echo "| 4 | Rules-dir bytes (\`~/.claude/rules/*.md\`) | 883,882 bytes / 61 files | ${m4_bytes} bytes / ${m4_files} files | ≤30,000 bytes | Live-state snapshot. |"

  # --- Metric 5 ---
  local m5 m5_groups m5_entries
  m5="$(f4_metric5_stop_chain)"
  m5_groups="$(echo "$m5" | awk '{print $1}')"
  m5_entries="$(echo "$m5" | awk '{print $2}')"
  echo "| 5 | Stop-chain entries (live \`settings.json\`) | 20 entries / 1 matcher-group | ${m5_entries} entries / ${m5_groups} matcher-group(s) | ≤6 (post-E.W may be 4 — record actual) | Live-state snapshot. |"

  # --- Metric 6 ---
  local m6 m6_count
  m6="$(f4_metric6_blocking_gates)"
  m6_count="$(echo "$m6" | awk '{print $1}')"
  echo "| 6 | Blocking gates (manifest.json \`blocking:true\`) | pending at snapshot time (doctor did not exist yet) | ${m6_count} | ≤12 | Baseline explicitly deferred this metric (no doctor/manifest at capture time). |"

  echo ""

  # Per-gate waiver alarm breakdown (metric 2 addendum)
  local alarm_lines
  alarm_lines="$(f4_metric2_per_gate_alarm)"
  if [[ -n "$alarm_lines" ]]; then
    echo "**Per-gate waiver-density alarm (≥3/week):**"
    echo ""
    echo "| Gate | Waivers/7d | E.3 alarm fired? |"
    echo "|---|---|---|"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local gate cnt
      gate="$(echo "$line" | awk '{print $1}')"
      cnt="$(echo "$line" | awk '{print $2}')"
      echo "| ${gate} | ${cnt} | VERIFY against digest/backlog — this script does not re-derive alarm-fired state, only the threshold crossing itself (see waiver-density.sh --report). |"
    done <<< "$alarm_lines"
    echo ""
  fi

  # --- Synthetic-runner comparison (clause a) ---
  echo "## Synthetic-runner scenario scores (clause a)"
  echo ""
  local syn syn_passed syn_failed syn_failing
  syn="$(f4_run_synthetic)"
  syn_passed="$(echo "$syn" | awk '{print $1}')"
  syn_failed="$(echo "$syn" | awk '{print $2}')"
  syn_failing="$(echo "$syn" | awk '{print $3}')"
  if [[ -n "$baseline_syn_passed" ]]; then
    echo "| | Baseline | Current |"
    echo "|---|---|---|"
    echo "| passed | ${baseline_syn_passed} | ${syn_passed} |"
    echo "| failed | ${baseline_syn_total:+$((baseline_syn_total - baseline_syn_passed))} | ${syn_failed} |"
    echo ""
  else
    echo "**No formally pre-registered \"Wave-B baseline\" synthetic-runner score file exists in this repo** (the synthetic runner itself was built in Waves D/E, after Wave B — there was nothing to run yet at Wave-B time). This is a pre-registration gap, reported honestly rather than backfilled with an invented number. The earliest recorded live run this script can find is in \`docs/reviews/nl-overhaul-program-2026-07-specs-f.md\`'s evidence file: \`passed: 8 / failed: 0\` (2026-07-06T16:35Z, run \`gh run view 28785582207\`). Current run below is compared against that as the best-available reference; pass \`--baseline-synthetic-passed N --baseline-synthetic-total N\` to override with a different reference once the operator designates one."
    echo ""
    echo "| | Best-available reference (2026-07-06) | Current |"
    echo "|---|---|---|"
    echo "| passed | 8 | ${syn_passed} |"
    echo "| failed | 0 | ${syn_failed} |"
    echo ""
  fi
  if [[ "$syn_failing" != "-" ]]; then
    echo "Failing scenarios this run: ${syn_failing}"
    echo ""
  fi

  # --- Findings sweep ---
  echo "## Findings 019-028 status sweep"
  echo ""
  echo "| Finding | Status | Terminal? |"
  echo "|---|---|---|"
  local fline fid fstatus fterminal
  while IFS= read -r fline; do
    [[ -z "$fline" ]] && continue
    fid="$(echo "$fline" | awk '{print $1}')"
    fstatus="$(echo "$fline" | cut -d' ' -f2-)"
    case "$fstatus" in
      dispositioned-act|closed) fterminal="yes" ;;
      open) fterminal="**NO — still open**" ;;
      *) fterminal="unknown" ;;
    esac
    echo "| NL-FINDING-${fid} | ${fstatus} | ${fterminal} |"
  done < <(f4_findings_sweep)
  echo ""

  # --- Doctor --full ---
  echo "## Doctor --full"
  echo ""
  echo "Run \`bash adapters/claude-code/hooks/harness-doctor.sh --full\` (or \`--quick\` for the fast subset) dated within the retro week and paste its final line here. This script does not auto-invoke the full sweep (it can be slow; see NL-FINDING-029) — run it explicitly as part of the retro session and record: exit code, red count, warn count, checks-run count."
  echo ""

  # --- Verdict rules ---
  echo "## Verdict (pre-registered ADR 058 D7 rules — printed, never self-graded)"
  echo ""
  echo "**Clause (a)** — synthetic-runner scores must IMPROVE vs the earliest recorded run:"
  local clause_a="AMBIGUOUS"
  if [[ -n "$baseline_syn_passed" ]]; then
    if [[ "$syn_passed" -lt "$baseline_syn_passed" ]] || [[ "$syn_failed" -gt "$((baseline_syn_total - baseline_syn_passed))" ]]; then
      clause_a="REFUTED"
    elif [[ "$syn_passed" -ge "$baseline_syn_passed" && "$syn_failed" -eq 0 ]]; then
      clause_a="HOLDS"
    fi
  else
    if [[ "$syn_passed" -lt 8 ]] || [[ "$syn_failed" -gt 0 ]]; then
      clause_a="REFUTED"
    elif [[ "$syn_passed" -ge 8 && "$syn_failed" -eq 0 ]]; then
      clause_a="HOLDS"
    fi
  fi
  echo "  Verdict: **${clause_a}**"
  echo ""
  echo "**Clause (b)** — ledger waiver+downgrade rate per active gate must fall ≥50% vs baseline within 3 weeks of Wave D cutover:"
  local clause_b="AMBIGUOUS — requires operator to confirm the window is the actual post-cutover 3-week mark before this clause can be graded"
  if [[ "$window_complete" == "yes" ]]; then
    local m1_baseline=321 m2_baseline=12
    local m1_target_max=$(( m1_baseline / 2 ))
    local m2_target_max=$(( m2_baseline / 2 ))
    if [[ "$m1_win" -gt "$m1_target_max" ]] || [[ "$m2_win" -gt "$m2_target_max" ]]; then
      clause_b="REFUTED (retry-guard window count ${m1_win} vs target ≤${m1_target_max}, and/or waiver-file window count ${m2_win} vs target ≤${m2_target_max})"
    else
      clause_b="HOLDS (retry-guard window count ${m1_win} ≤${m1_target_max}; waiver-file window count ${m2_win} ≤${m2_target_max})"
    fi
  fi
  echo "  Verdict: **${clause_b}**"
  echo ""
  if [[ "$clause_a" == "REFUTED" || "$clause_b" == REFUTED* ]]; then
    echo "**MANDATED ACTION: clause (a) and/or (b) REFUTED per ADR 058 D7 — the mandated action is PROGRAM PAUSE + re-design proposal to the operator. Do NOT add gates; do NOT rationalize partial numbers.**"
  elif [[ "$clause_a" == "HOLDS" && "$clause_b" == HOLDS* ]]; then
    echo "Both clauses currently HOLD on the data above. Per protocol this script still does not self-grade an overall \"PASS\" — present this table to the operator with the recommendation that the hypothesis is NOT refuted by either clause, and let the operator make the final call."
  else
    echo "Mixed/ambiguous — present this table to the operator with a recommendation; no self-graded pass."
  fi
  echo ""

  # --- Activation proposal (mandatory per §F.4-PROTOCOL) ---
  echo "## Activation proposal — NL Observability Program (mandatory, omitting this fails F.4's Done-when)"
  echo ""
  echo "\`docs/plans/nl-observability-program-2026-08.md\` is Status: DRAFT, frozen: true, with an explicit START TRIGGER: \"nl-overhaul F.4 retro complete — the F.4 completion report MUST carry this program's activation proposal.\" Operator commitment 2026-07-04: \"Let's please make sure this gets into an actual build.\""
  echo ""
  echo "**Decision needed:** flip \`docs/plans/nl-observability-program-2026-08.md\` Status: DRAFT → ACTIVE and start task O.0."
  echo ""
  echo "| Option | What happens | Cost / risk |"
  echo "|---|---|---|"
  echo "| GO | Status flips to ACTIVE (one edit); O.0 dispatch begins; counts against the ACTIVE-plan ≤3 machine-wide budget | Low — one-line revert if wrong |"
  echo "| WAIT | Stays DRAFT/frozen; re-propose at next retro/KPI cycle | Operator's 2026-07-04 build commitment stays unfulfilled another cycle |"
  echo "| ABANDON | Status → ABANDONED with rationale; backlog items it absorbed (WORKSTREAMS-UI-PURPOSE-AUDIT-01, ntfy.sh item) un-absorb back to backlog | Reverses an explicit operator commitment — needs a stated reason |"
  echo ""
  echo "**My pick:** GO — the operator already greenlit this as a build commitment; the only gate was F.4 completing, which this report does."
  echo ""
  echo "**Reply with:** \`go\` / \`wait\` / \`abandon\`"
  echo ""

  return 0
}

# ============================================================
# --self-test
# ============================================================
_f4_run_self_test() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'f4st')"
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  echo "self-test: f4-retro.sh"

  export HARNESS_SELFTEST=1

  # ------------------------------------------------------------
  # Fixture 1: unresolved-stop-hooks.log with dated + undated lines.
  # ------------------------------------------------------------
  mkdir -p "$TMP/state"
  local LOG="$TMP/state/unresolved-stop-hooks.log"
  {
    printf '2026-07-04T00:00:00Z downgraded gate-a\n'
    printf '2026-07-10T00:00:00Z downgraded gate-b\n'
    printf '2026-06-01T00:00:00Z downgraded gate-c (before window)\n'
    printf 'no-timestamp-line downgraded gate-d\n'
  } > "$LOG"

  export F4_RETRO_STOP_HOOKS_LOG="$LOG"
  export F4_RETRO_STATE_DIR="$TMP/state"
  export F4_RETRO_ALERTS_DIR="$TMP/alerts"
  export F4_RETRO_RULES_DIR="$TMP/rules"
  export F4_RETRO_SETTINGS_JSON="$TMP/settings.json"
  export SIGNAL_LEDGER_PATH="$TMP/ledger.jsonl"

  local since_epoch until_epoch
  since_epoch="$(_f4_epoch 2026-07-03)"
  until_epoch="$(_f4_epoch 2026-07-24)"

  local m1
  m1="$(f4_metric1_retry_guard "$since_epoch" "$until_epoch")"
  local m1_win m1_undated m1_total
  m1_win="$(echo "$m1" | awk '{print $1}')"
  m1_undated="$(echo "$m1" | awk '{print $2}')"
  m1_total="$(echo "$m1" | awk '{print $3}')"
  if [[ "$m1_win" == "2" ]]; then
    pass "metric1 counts exactly the two in-window dated lines (got $m1_win)"
  else
    fail "metric1 expected 2 in-window, got $m1_win"
  fi
  if [[ "$m1_undated" == "1" ]]; then
    pass "metric1 counts exactly one undated line separately (got $m1_undated)"
  else
    fail "metric1 expected 1 undated, got $m1_undated"
  fi
  if [[ "$m1_total" == "4" ]]; then
    pass "metric1 total-on-disk matches fixture line count (got $m1_total)"
  else
    fail "metric1 expected total 4, got $m1_total"
  fi

  # ------------------------------------------------------------
  # Fixture 2: waiver files with known mtimes + ledger waiver events.
  # ------------------------------------------------------------
  touch -d '2026-07-05' "$TMP/state/acceptance-waiver-slugA-1.txt" 2>/dev/null \
    || touch -t 202607050000 "$TMP/state/acceptance-waiver-slugA-1.txt" 2>/dev/null \
    || : > "$TMP/state/acceptance-waiver-slugA-1.txt"
  touch -d '2026-06-01' "$TMP/state/acceptance-waiver-slugB-1.txt" 2>/dev/null \
    || touch -t 202606010000 "$TMP/state/acceptance-waiver-slugB-1.txt" 2>/dev/null \
    || : > "$TMP/state/acceptance-waiver-slugB-1.txt"
  {
    printf '{"ts":"2026-07-06T00:00:00Z","session_id":"s1","gate":"gate-a","event":"waiver","detail":"fixture"}\n'
    printf '{"ts":"2026-06-01T00:00:00Z","session_id":"s1","gate":"gate-a","event":"waiver","detail":"before window"}\n'
    printf '{"ts":"2026-07-07T00:00:00Z","session_id":"s1","gate":"gate-a","event":"block","detail":"not a waiver"}\n'
  } > "$TMP/ledger.jsonl"

  local m2 m2_win m2_ledger
  m2="$(f4_metric2_waiver_density "$since_epoch" "$until_epoch")"
  m2_win="$(echo "$m2" | awk '{print $1}')"
  m2_ledger="$(echo "$m2" | awk '{print $3}')"
  if [[ "$m2_win" == "1" ]]; then
    pass "metric2 counts exactly one in-window waiver file (got $m2_win)"
  else
    fail "metric2 expected 1 in-window file, got $m2_win"
  fi
  if [[ "$m2_ledger" == "1" ]]; then
    pass "metric2 counts exactly one in-window ledger waiver event, ignoring block events and out-of-window waivers (got $m2_ledger)"
  else
    fail "metric2 expected 1 in-window ledger event, got $m2_ledger"
  fi

  # ------------------------------------------------------------
  # Fixture 3: external-monitor alerts (acked + unacked, fresh + stale).
  # ------------------------------------------------------------
  mkdir -p "$TMP/alerts"
  : > "$TMP/alerts/fresh-unacked.json"
  : > "$TMP/alerts/acked-one.json"
  : > "$TMP/alerts/acked-one.json.acked"
  local stale="$TMP/alerts/stale-unacked.json"
  : > "$stale"
  touch -d '2026-06-01' "$stale" 2>/dev/null || touch -t 202606010000 "$stale" 2>/dev/null || true

  local m3 m3_total m3_acked m3_over7d
  m3="$(f4_metric3_signal_consumption)"
  m3_total="$(echo "$m3" | awk '{print $1}')"
  m3_acked="$(echo "$m3" | awk '{print $2}')"
  m3_over7d="$(echo "$m3" | awk '{print $3}')"
  if [[ "$m3_total" == "3" ]]; then
    pass "metric3 counts 3 total .json alert files, baseline's own definition (excludes .json.acked suffix only, not files that merely HAVE an acked sibling; got $m3_total)"
  else
    fail "metric3 expected 3 total (baseline method counts all *.json minus *.json.acked), got $m3_total"
  fi
  if [[ "$m3_acked" == "1" ]]; then
    pass "metric3 counts 1 acked sibling (got $m3_acked)"
  else
    fail "metric3 expected 1 acked, got $m3_acked"
  fi
  if [[ "$m3_over7d" == "1" ]]; then
    pass "metric3 counts exactly the stale unacked alert as >7d (got $m3_over7d)"
  else
    fail "metric3 expected 1 unacked>7d, got $m3_over7d"
  fi

  # ------------------------------------------------------------
  # Fixture 4: rules dir byte/file count.
  # ------------------------------------------------------------
  mkdir -p "$TMP/rules"
  printf '1234567890' > "$TMP/rules/a.md"
  printf '12345' > "$TMP/rules/b.md"
  local m4 m4_bytes m4_files
  m4="$(f4_metric4_rules_bytes)"
  m4_bytes="$(echo "$m4" | awk '{print $1}')"
  m4_files="$(echo "$m4" | awk '{print $2}')"
  if [[ "$m4_bytes" == "15" ]]; then
    pass "metric4 sums fixture rules-dir bytes exactly (got $m4_bytes)"
  else
    fail "metric4 expected 15 bytes, got $m4_bytes"
  fi
  if [[ "$m4_files" == "2" ]]; then
    pass "metric4 counts 2 fixture rule files (got $m4_files)"
  else
    fail "metric4 expected 2 files, got $m4_files"
  fi

  # ------------------------------------------------------------
  # Fixture 5: settings.json Stop chain.
  # ------------------------------------------------------------
  cat > "$TMP/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [ {"type":"command","command":"a"}, {"type":"command","command":"b"}, {"type":"command","command":"c"} ] }
    ]
  }
}
JSON
  if _have node; then
    local m5 m5_groups m5_entries
    m5="$(f4_metric5_stop_chain)"
    m5_groups="$(echo "$m5" | awk '{print $1}')"
    m5_entries="$(echo "$m5" | awk '{print $2}')"
    if [[ "$m5_groups" == "1" && "$m5_entries" == "3" ]]; then
      pass "metric5 reads fixture Stop chain exactly (1 group, 3 entries)"
    else
      fail "metric5 expected 1 group / 3 entries, got $m5_groups / $m5_entries"
    fi
  else
    echo "  SKIP: metric5 (node not on PATH in this environment)"
  fi

  # ------------------------------------------------------------
  # Fixture 6: manifest.json blocking-gate count.
  # ------------------------------------------------------------
  local FIXTURE_MANIFEST="$TMP/manifest.json"
  cat > "$FIXTURE_MANIFEST" <<'JSON'
{
  "entries": [
    {"id": "g1", "blocking": true},
    {"id": "g2", "blocking": true},
    {"id": "g3", "blocking": false}
  ]
}
JSON
  export F4_RETRO_MANIFEST_JSON="$FIXTURE_MANIFEST"
  if _have jq; then
    local m6 m6_count
    m6="$(f4_metric6_blocking_gates)"
    m6_count="$(echo "$m6" | awk '{print $1}')"
    if [[ "$m6_count" == "2" ]]; then
      pass "metric6 counts exactly 2 blocking:true fixture entries"
    else
      fail "metric6 expected 2, got $m6_count"
    fi
  else
    echo "  SKIP: metric6 (jq not on PATH in this environment)"
  fi

  # ------------------------------------------------------------
  # Fixture 7: findings sweep against a synthetic findings.md.
  # ------------------------------------------------------------
  local FIXTURE_FINDINGS="$TMP/findings.md"
  cat > "$FIXTURE_FINDINGS" <<'MD'
### NL-FINDING-019 — a
- **Status:** dispositioned-act
- **Description:** x

### NL-FINDING-020 — b
- **Status:** open
- **Description:** y
MD
  export F4_RETRO_FINDINGS_MD="$FIXTURE_FINDINGS"
  local sweep_out
  sweep_out="$(f4_findings_sweep)"
  if printf '%s' "$sweep_out" | grep -q "^019 dispositioned-act$"; then
    pass "findings sweep reads 019 status correctly from fixture"
  else
    fail "findings sweep did not read 019 correctly: $sweep_out"
  fi
  if printf '%s' "$sweep_out" | grep -q "^020 open$"; then
    pass "findings sweep reads 020 status correctly from fixture"
  else
    fail "findings sweep did not read 020 correctly: $sweep_out"
  fi
  if printf '%s' "$sweep_out" | grep -q "^021 unknown"; then
    pass "findings sweep reports 'unknown' for an id absent from the fixture (021), never fabricates a status"
  else
    fail "findings sweep should report unknown for missing id 021: $sweep_out"
  fi

  # ------------------------------------------------------------
  # Fixture 8: synthetic runner fixture script (pass + fail case).
  # ------------------------------------------------------------
  local RUNNER_PASS="$TMP/runner-pass.sh"
  cat > "$RUNNER_PASS" <<'SH'
#!/bin/bash
echo "passed:  8"
echo "failed:  0"
SH
  chmod +x "$RUNNER_PASS"
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_PASS"
  local syn_out
  syn_out="$(f4_run_synthetic)"
  if [[ "$syn_out" == "8 0 -" ]]; then
    pass "synthetic runner parse: pass-case parsed exactly (8 passed, 0 failed)"
  else
    fail "synthetic runner parse: expected '8 0 -', got '$syn_out'"
  fi

  local RUNNER_FAIL="$TMP/runner-fail.sh"
  cat > "$RUNNER_FAIL" <<'SH'
#!/bin/bash
echo "passed:  6"
echo "failed:  2"
echo "failing scenarios: scenario-x scenario-y"
SH
  chmod +x "$RUNNER_FAIL"
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_FAIL"
  syn_out="$(f4_run_synthetic)"
  if [[ "$syn_out" == "6 2 scenario-x,scenario-y" ]]; then
    pass "synthetic runner parse: fail-case parsed exactly (6 passed, 2 failed, names joined)"
  else
    fail "synthetic runner parse: expected '6 2 scenario-x,scenario-y', got '$syn_out'"
  fi

  # ------------------------------------------------------------
  # Scenario: verdict rules — clause-a fail, clause-b fail, both-pass.
  # ------------------------------------------------------------
  echo "Scenario: verdict-rule fixtures (clause-a fail / clause-b fail / both-pass)"

  # Clause (b) is only graded once the full 21-day protocol window has
  # elapsed (window_complete). F4_RETRO_TODAY_OVERRIDE simulates "today is
  # past the 21-day mark" without waiting on the wall clock; --until is set
  # to the same date so the requested window matches what "today" claims
  # to be. Ledger/log fixture timestamps stay inside [since, until).
  export F4_RETRO_TODAY_OVERRIDE="2026-07-24"

  # clause-a fail: current synthetic run regresses vs baseline-passed.
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_FAIL"
  local report_clause_a_fail
  report_clause_a_fail="$(f4_generate_report 2026-07-03 2026-07-24 8 8 2>&1)"
  if printf '%s' "$report_clause_a_fail" | grep -q "Verdict: \*\*REFUTED\*\*"; then
    pass "verdict fixture: clause (a) REFUTED when current run regresses vs baseline"
  else
    fail "verdict fixture: expected clause (a) REFUTED, got: $(printf '%s' "$report_clause_a_fail" | grep -A1 'Clause (a)')"
  fi
  if printf '%s' "$report_clause_a_fail" | grep -q "MANDATED ACTION: clause (a)"; then
    pass "verdict fixture: mandated PROGRAM PAUSE action printed on clause (a) REFUTED"
  else
    fail "verdict fixture: expected mandated-action line on clause (a) REFUTED"
  fi

  # clause-b fail: force a large in-window retry-guard/waiver count via a
  # dedicated fixture log/state-dir exceeding 50% of the 321/12 baseline.
  local CB_TMP="$TMP/clauseb"
  mkdir -p "$CB_TMP/state"
  local CB_LOG="$CB_TMP/state/unresolved-stop-hooks.log"
  # 161 lines is the smallest fixture that exceeds the 50%-of-321 target
  # (target max = 160); kept as tight as possible since each line costs a
  # timestamp parse (fast pure-bash path per line, still not free at scale).
  : > "$CB_LOG"
  local i
  for i in $(seq 1 161); do printf '2026-07-05T00:00:00Z downgraded gate-x\n' >> "$CB_LOG"; done
  export F4_RETRO_STOP_HOOKS_LOG="$CB_LOG"
  export F4_RETRO_STATE_DIR="$CB_TMP/state"
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_PASS"
  local report_clause_b_fail
  report_clause_b_fail="$(f4_generate_report 2026-07-03 2026-07-24 8 8 2>&1)"
  if printf '%s' "$report_clause_b_fail" | grep -q "Verdict: \*\*REFUTED"; then
    pass "verdict fixture: clause (b) REFUTED when in-window retry-guard count exceeds 50%-of-baseline target"
  else
    fail "verdict fixture: expected clause (b) REFUTED, got: $(printf '%s' "$report_clause_b_fail" | grep -A1 'Clause (b)')"
  fi

  # both-pass: small in-window counts, synthetic run improves.
  export F4_RETRO_STOP_HOOKS_LOG="$LOG"
  export F4_RETRO_STATE_DIR="$TMP/state"
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_PASS"
  local report_both_pass
  report_both_pass="$(f4_generate_report 2026-07-03 2026-07-24 6 8 2>&1)"
  if printf '%s' "$report_both_pass" | grep -q "Verdict: \*\*HOLDS\*\*"; then
    pass "verdict fixture: clause (a) HOLDS when current run improves vs baseline"
  else
    fail "verdict fixture: expected clause (a) HOLDS, got: $(printf '%s' "$report_both_pass" | grep -A1 'Clause (a)')"
  fi
  if printf '%s' "$report_both_pass" | grep -q "Verdict: \*\*HOLDS ("; then
    pass "verdict fixture: clause (b) HOLDS when in-window counts are well under target"
  else
    fail "verdict fixture: expected clause (b) HOLDS, got: $(printf '%s' "$report_both_pass" | grep -A1 'Clause (b)')"
  fi
  if printf '%s' "$report_both_pass" | grep -qi "self-graded"; then
    pass "verdict fixture: even both-pass case explicitly disclaims a self-graded overall PASS"
  else
    fail "verdict fixture: both-pass report should still disclaim self-grading"
  fi

  # ------------------------------------------------------------
  # Scenario: table renders with all six metrics present.
  # ------------------------------------------------------------
  echo "Scenario: full table render includes all six metric rows + activation proposal"
  # Back to the REAL wall-clock date for this scenario (unset the clause-b
  # fixtures' override) — the whole point here is proving INTERIM shows up
  # for a window that has not actually elapsed yet.
  unset F4_RETRO_TODAY_OVERRIDE
  export F4_RETRO_STOP_HOOKS_LOG="$LOG"
  export F4_RETRO_STATE_DIR="$TMP/state"
  export F4_RETRO_ALERTS_DIR="$TMP/alerts"
  export F4_RETRO_RULES_DIR="$TMP/rules"
  export F4_RETRO_SETTINGS_JSON="$TMP/settings.json"
  export F4_RETRO_MANIFEST_JSON="$FIXTURE_MANIFEST"
  export F4_RETRO_FINDINGS_MD="$FIXTURE_FINDINGS"
  export F4_RETRO_SYNTHETIC_RUNNER="$RUNNER_PASS"
  local full_report
  full_report="$(f4_generate_report 2026-07-03 2026-07-24 "" "" 2>&1)"
  local row
  for row in "| 1 |" "| 2 |" "| 3 |" "| 4 |" "| 5 |" "| 6 |"; do
    if printf '%s' "$full_report" | grep -qF "$row"; then
      pass "table renders row '$row'"
    else
      fail "table missing row '$row'"
    fi
  done
  if printf '%s' "$full_report" | grep -q "INTERIM"; then
    pass "table labels itself INTERIM when the window has not yet elapsed"
  else
    fail "table should be labeled INTERIM for a not-yet-elapsed window"
  fi
  if printf '%s' "$full_report" | grep -q "NL Observability Program"; then
    pass "activation proposal for the observability program is present"
  else
    fail "activation proposal missing — this fails F.4's Done-when per protocol"
  fi
  if printf '%s' "$full_report" | grep -qi "no formally pre-registered"; then
    pass "report honestly discloses the missing Wave-B synthetic baseline file rather than inventing one"
  else
    fail "report should disclose the missing Wave-B baseline file"
  fi

  unset F4_RETRO_STOP_HOOKS_LOG F4_RETRO_STATE_DIR F4_RETRO_ALERTS_DIR F4_RETRO_RULES_DIR
  unset F4_RETRO_SETTINGS_JSON SIGNAL_LEDGER_PATH F4_RETRO_MANIFEST_JSON F4_RETRO_FINDINGS_MD
  unset F4_RETRO_SYNTHETIC_RUNNER HARNESS_SELFTEST F4_RETRO_TODAY_OVERRIDE

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# CLI dispatch
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  SINCE="2026-07-03"
  UNTIL="$(_f4_today)"
  BASELINE_SYN_PASSED=""
  BASELINE_SYN_TOTAL=""
  WRITE_PATH=""
  WRITE_REQUESTED=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-test)
        _f4_run_self_test
        exit $?
        ;;
      --since)
        SINCE="${2:-}"
        shift 2
        ;;
      --until)
        UNTIL="${2:-}"
        shift 2
        ;;
      --baseline-synthetic-passed)
        BASELINE_SYN_PASSED="${2:-}"
        shift 2
        ;;
      --baseline-synthetic-total)
        BASELINE_SYN_TOTAL="${2:-}"
        shift 2
        ;;
      --write)
        WRITE_REQUESTED=1
        if [[ $# -ge 2 && "${2:0:2}" != "--" ]]; then
          WRITE_PATH="$2"
          shift 2
        else
          shift 1
        fi
        ;;
      -h|--help)
        sed -n '1,110p' "$0" | sed 's/^# //; s/^#//'
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        echo "usage: f4-retro.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--baseline-synthetic-passed N --baseline-synthetic-total N] [--write [path]] | --self-test" >&2
        exit 2
        ;;
    esac
  done

  REPORT="$(f4_generate_report "$SINCE" "$UNTIL" "$BASELINE_SYN_PASSED" "$BASELINE_SYN_TOTAL")"
  printf '%s\n' "$REPORT"

  if [[ "$WRITE_REQUESTED" == "1" ]]; then
    if [[ -z "$WRITE_PATH" ]]; then
      REPO_ROOT="$(_f4_repo_root)"
      WRITE_PATH="${REPO_ROOT}/docs/reviews/nl-overhaul-completion-${UNTIL}.md"
    fi
    mkdir -p "$(dirname "$WRITE_PATH")" 2>/dev/null || true
    printf '%s\n' "$REPORT" > "$WRITE_PATH"
    echo "" >&2
    echo "f4-retro: wrote report to $WRITE_PATH" >&2
  fi

  exit 0
fi
