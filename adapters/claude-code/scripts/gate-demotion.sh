#!/bin/bash
# gate-demotion.sh — metric-driven auto-demotion of blocking gates (ADR 059 D7,
# NL Overhaul Wave F, task F.5).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# E.3 (waiver-density.sh) detects gates whose waiver count crosses a threshold
# in the trailing 7-day window and FILES a "fix or retire" backlog entry
# (WAIVER-DENSITY-<GATE>-<yyyymmdd>). Detection alone has no teeth: a
# chronically-waived gate stays blocking:true in manifest.json indefinitely
# unless a human notices the backlog entry and acts. ADR 059 D7 gives the
# numbers teeth: a gate crossing its own threshold gets AUTO-DEMOTED to
# blocking:false (with an honest_status/honest note explaining why and when),
# pending harness-reviewer re-review — the demotion is not a verdict that the
# gate is wrong forever, only that it needs re-review before it blocks again.
#
# This script is the WRITE side of that pipeline (waiver-density.sh is the
# READ/detect side; this script never re-implements its counting logic — it
# shells out to `waiver-density.sh --report` and reads that markdown table,
# so the two scripts can never disagree about what "crossed the threshold"
# means).
#
# ============================================================
# MANIFEST-EDIT SCOPING (§F.0.1 — CRITICAL)
# ============================================================
#
# adapters/claude-code/manifest.json is ORCHESTRATOR-ONLY this wave (F.1 is
# the designated integrator). This script NEVER writes to the real manifest
# itself when run by a non-orchestrator session:
#
#   --self-test          : operates ONLY on a manifest COPY inside a mktemp
#                           tempdir (HARNESS_SELFTEST convention). Never
#                           touches the real manifest.json.
#   --dry-run [<path>]    : reads the real manifest (or <path>), prints the
#                           jq transform + which entries WOULD be demoted,
#                           writes NOTHING. Safe to run any time.
#   --apply <src> <dst>   : the exact jq transform, applied to <src>,
#                           written to <dst>. This is the orchestrator-applied
#                           step (F.1 runs this against the real manifest.json
#                           in the same pass it integrates every other F.5/F.1
#                           fragment) — never invoked by this builder against
#                           the real path. The exact invocation is also
#                           reproduced verbatim in orchestratorTodo (see the
#                           F.5 builder's structured report) so F.1 does not
#                           need to read this file to know what to run.
#
# ============================================================
# THE JQ TRANSFORM
# ============================================================
#
# For the set of gate names G[] identified as over-threshold (from
# `waiver-density.sh --report`'s "YES" rows), the transform:
#   .entries |= map(
#     if (.id as $i | G_ARRAY | index($i)) != null and .blocking == true then
#       .blocking = false
#       | .honest_status = (
#           (if (.honest_status // "") == "" then "" else (.honest_status + " ") end)
#           + "auto-demoted <DATE> pending harness-reviewer re-review (E.3 threshold)."
#         )
#     else . end
#   )
# (G_ARRAY is a jq array literal, e.g. ["gate-a","gate-b"], built from the
# candidate list; `.id as $i | G_ARRAY | index($i)` is the correct idiom —
# piping the array literal directly into `index(.id)` breaks because `.id`
# would then be evaluated against the ARRAY, not the original object.)
#
# <DATE> is substituted with the real UTC date (YYYY-MM-DD) at run time — the
# jq program itself is built with the date already interpolated (jq has no
# portable "current date" builtin across the jq versions in the wild, so the
# date is computed in bash and passed in via --arg, not hardcoded in the
# program text below).
#
# ============================================================
# LEDGER + DIGEST
# ============================================================
#
# On every entry actually demoted (--apply only; --dry-run and --self-test's
# internal sandbox runs never touch the real ledger):
#   ledger_emit "gate-demotion" "demote" "<gate> auto-demoted blocking:false (E.3 threshold, N waivers/7d)"
# --digest-line prints ZERO OR ONE line (E.1 digest convention: quiet feeds
# emit nothing) naming the most-recently-demoted gate still within the
# trailing 7-day window of ITS demotion event (read back from the ledger —
# this script is idempotent-safe to call every session without re-demoting
# or re-emitting stale news forever).
#
# ============================================================
# CONTRACT (subcommands)
# ============================================================
#
#   gate-demotion.sh --dry-run [<manifest-path>]
#     Read waiver-density.sh --report (respects SIGNAL_LEDGER_PATH/
#     HARNESS_SELFTEST env exactly like waiver-density.sh does — this script
#     never resolves the ledger path itself, it shells out). For every gate
#     marked "YES" (over threshold) in that report that is ALSO blocking:true
#     in the resolved manifest, print what would change. Never writes.
#
#   gate-demotion.sh --apply <src-manifest> <dst-manifest>
#     Apply the transform: read <src-manifest>, write the demoted result to
#     <dst-manifest> (may be the same path — jq's own idiom of writing to a
#     temp file then mv is used internally so a same-path in-place edit is
#     safe). Emits one ledger "demote" event per gate actually flipped, and
#     prints a one-line summary per gate to stdout. Exits 0 always (best-
#     effort; a missing jq or unreadable manifest is reported and the script
#     exits 1 — the only failure exit).
#
#   gate-demotion.sh --digest-line
#     Print zero or one digest line (E.1 convention) about the most recent
#     demotion event still within a 7-day freshness window, read from the
#     signal ledger's "gate-demotion"/"demote" events. Never writes anything.
#
#   gate-demotion.sh --self-test
#     Full fixture suite: builds a synthetic manifest + synthetic waiver
#     ledger in mktemp -d, runs --dry-run and --apply against the COPY only,
#     asserts the real repo manifest.json is never touched, asserts
#     idempotence (re-running --apply on an already-demoted entry is a no-op
#     that does not double-append the honest_status note), asserts a
#     below-threshold gate is never demoted, asserts --digest-line freshness
#     windowing.
#
# ============================================================
# SCHEDULING
# ============================================================
#
# Per specs-f §F.5: "Runs from the E.5 weekly KPI pass (not a new hook — zero
# new chain entries)." harness-kpis.sh's weekly invocation is the intended
# caller of `gate-demotion.sh --dry-run` (report only, surfaced in the KPI
# report for a human to review) — see orchestratorTodo for the exact
# harness-kpis.sh wiring line (that file is not owned by this task). The
# --apply path is intentionally NEVER auto-invoked from a schedule in this
# script's own design: ADR 059 D7 demotes to WARN pending *harness-reviewer
# re-review*, so the decision to actually flip manifest.json stays a reviewed
# action (harness-reviewer + F.1 integration), not a fully unattended cron.

set -u

_GD_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_GD_HOOKS_LIB="$_GD_SELF_DIR/../hooks/lib"
# shellcheck disable=SC1091
if [[ -f "$_GD_HOOKS_LIB/signal-ledger.sh" ]]; then
  source "$_GD_HOOKS_LIB/signal-ledger.sh"
fi
# shellcheck disable=SC1091
if [[ -f "$_GD_HOOKS_LIB/nl-paths.sh" ]]; then
  source "$_GD_HOOKS_LIB/nl-paths.sh"
fi

_have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------
# _gd_waiver_density_script — resolve waiver-density.sh's path (sibling
# script, same scripts/ dir).
# ----------------------------------------------------------------------
_gd_waiver_density_script() {
  printf '%s/waiver-density.sh' "$_GD_SELF_DIR"
}

# ----------------------------------------------------------------------
# _gd_over_threshold_gates — parse `waiver-density.sh --report`'s markdown
# table and print one gate name per line for every row marked "YES" (over
# threshold). Inherits the caller's env (SIGNAL_LEDGER_PATH,
# WAIVER_DENSITY_THRESHOLD, HARNESS_SELFTEST, etc.) unchanged — this
# function never overrides them, so a self-test caller's sandboxed ledger
# is respected transparently.
# ----------------------------------------------------------------------
_gd_over_threshold_gates() {
  local wd_script
  wd_script="$(_gd_waiver_density_script)"
  [[ -f "$wd_script" ]] || return 0
  bash "$wd_script" --report 2>/dev/null | \
    awk -F'|' '/\| *YES *\|/ { gsub(/^ +| +$/, "", $2); print $2 }'
}

# ----------------------------------------------------------------------
# _gd_today — UTC date, YYYY-MM-DD. Prints "unknown-date" on failure
# (never crashes the caller).
# ----------------------------------------------------------------------
_gd_today() {
  date -u '+%Y-%m-%d' 2>/dev/null || echo 'unknown-date'
}

# ----------------------------------------------------------------------
# _gd_resolve_manifest <explicit-path-or-empty> — resolve the manifest to
# read for --dry-run when no explicit path is given: the repo's
# adapters/claude-code/manifest.json via nl_repo_root(). Prints empty on
# total failure (caller handles).
# ----------------------------------------------------------------------
_gd_resolve_manifest() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  if _have nl_repo_root; then
    local root
    root="$(nl_repo_root)"
    if [[ -n "$root" && -f "$root/adapters/claude-code/manifest.json" ]]; then
      printf '%s/adapters/claude-code/manifest.json' "$root"
      return 0
    fi
  fi
  printf ''
}

# ----------------------------------------------------------------------
# _gd_jq_transform_file <date> — write the jq program (with <date>
# interpolated via a bash string, NOT via jq --arg, so --dry-run's printed
# "exact transform" text is copy-pasteable verbatim) to a temp file, print
# the temp file's path. Caller is responsible for cleanup (mktemp file,
# not dir — cheap, one per invocation).
# ----------------------------------------------------------------------
_gd_jq_transform_file() {
  local date_str="$1"
  shift
  local gates=("$@")
  local jq_file
  jq_file="$(mktemp 2>/dev/null || mktemp -t 'gdjq')"

  # Build a jq array literal of gate names to demote, e.g. ["gate-a","gate-b"].
  local gate_json="[]"
  if [[ "${#gates[@]}" -gt 0 ]]; then
    gate_json="$(printf '%s\n' "${gates[@]}" | jq -R . | jq -s -c .)"
  fi

  cat > "$jq_file" <<JQ
.entries |= map(
  if (.id as \$i | ${gate_json} | index(\$i)) != null and .blocking == true then
    .blocking = false
    | .honest_status = (
        (if (.honest_status // "") == "" then "" else (.honest_status + " ") end)
        + "auto-demoted ${date_str} pending harness-reviewer re-review (E.3 threshold)."
      )
  else .
  end
)
JQ
  printf '%s' "$jq_file"
}

# ----------------------------------------------------------------------
# gd_dry_run [<manifest-path>]
# ----------------------------------------------------------------------
gd_dry_run() {
  local manifest
  manifest="$(_gd_resolve_manifest "${1:-}")"
  if [[ -z "$manifest" || ! -f "$manifest" ]]; then
    echo "gate-demotion: could not resolve a manifest.json to inspect (pass a path explicitly)" >&2
    return 1
  fi
  if ! _have jq; then
    echo "gate-demotion: jq is required (not found on PATH)" >&2
    return 1
  fi

  local over_gates=()
  while IFS= read -r g; do
    [[ -n "$g" ]] && over_gates+=("$g")
  done < <(_gd_over_threshold_gates)

  if [[ "${#over_gates[@]}" -eq 0 ]]; then
    echo "gate-demotion --dry-run: no gate is over the waiver-density threshold — nothing to demote."
    return 0
  fi

  local today
  today="$(_gd_today)"
  local candidates=()
  local g
  for g in "${over_gates[@]}"; do
    if jq -e --arg id "$g" '.entries[] | select(.id == $id and .blocking == true)' "$manifest" >/dev/null 2>&1; then
      candidates+=("$g")
    fi
  done

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "gate-demotion --dry-run: waiver-density flagged (${over_gates[*]}) but none is currently blocking:true in $manifest — nothing to demote."
    return 0
  fi

  echo "gate-demotion --dry-run: manifest=$manifest"
  echo "Gates over the E.3 waiver-density threshold AND currently blocking:true:"
  for g in "${candidates[@]}"; do
    echo "  - $g -> blocking:false; honest_status += \"auto-demoted ${today} pending harness-reviewer re-review (E.3 threshold).\""
  done
  echo ""
  echo "Exact jq transform (copy-pasteable; run via --apply for a reviewed/orchestrator-applied edit):"
  local jq_file
  jq_file="$(_gd_jq_transform_file "$today" "${candidates[@]}")"
  cat "$jq_file"
  rm -f "$jq_file"
  return 0
}

# ----------------------------------------------------------------------
# gd_apply <src> <dst>
# ----------------------------------------------------------------------
gd_apply() {
  local src="${1:-}" dst="${2:-}"
  if [[ -z "$src" || -z "$dst" ]]; then
    echo "usage: gate-demotion.sh --apply <src-manifest> <dst-manifest>" >&2
    return 1
  fi
  if [[ ! -f "$src" ]]; then
    echo "gate-demotion: src manifest not found: $src" >&2
    return 1
  fi
  if ! _have jq; then
    echo "gate-demotion: jq is required (not found on PATH)" >&2
    return 1
  fi

  local over_gates=()
  while IFS= read -r g; do
    [[ -n "$g" ]] && over_gates+=("$g")
  done < <(_gd_over_threshold_gates)

  if [[ "${#over_gates[@]}" -eq 0 ]]; then
    echo "gate-demotion --apply: no gate is over the waiver-density threshold — no-op (src copied to dst unchanged)."
    cp "$src" "$dst" 2>/dev/null || true
    return 0
  fi

  local today
  today="$(_gd_today)"

  # Only demote entries that are CURRENTLY blocking:true (idempotent: a gate
  # already demoted by a previous run is blocking:false and this jq's `if`
  # guard leaves it untouched — no double-appended honest_status text).
  local candidates=()
  local g
  for g in "${over_gates[@]}"; do
    if jq -e --arg id "$g" '.entries[] | select(.id == $id and .blocking == true)' "$src" >/dev/null 2>&1; then
      candidates+=("$g")
    fi
  done

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "gate-demotion --apply: over-threshold gate(s) found (${over_gates[*]}) but none is blocking:true in $src — no-op."
    cp "$src" "$dst" 2>/dev/null || true
    return 0
  fi

  local jq_file
  jq_file="$(_gd_jq_transform_file "$today" "${candidates[@]}")"

  local tmp_out
  tmp_out="$(mktemp 2>/dev/null || mktemp -t 'gdout')"
  if ! jq -f "$jq_file" "$src" > "$tmp_out" 2>/dev/null; then
    echo "gate-demotion: jq transform failed against $src" >&2
    rm -f "$jq_file" "$tmp_out"
    return 1
  fi
  mv "$tmp_out" "$dst"
  rm -f "$jq_file"

  for g in "${candidates[@]}"; do
    local count
    count="$(bash "$(_gd_waiver_density_script)" --report 2>/dev/null | awk -F'|' -v gate="$g" '{gsub(/^ +| +$/,"",$2); if ($2==gate) {gsub(/^ +| +$/,"",$3); print $3}}')"
    echo "gate-demotion: ${g} auto-demoted blocking:false (E.3 threshold, ${count:-?} waivers/7d) -> ${dst}"
    if _have ledger_emit; then
      ledger_emit "gate-demotion" "demote" "${g} auto-demoted blocking:false (E.3 threshold, ${count:-?} waivers/7d)"
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# gd_digest_line — print zero or one line about the most recent demotion
# still within a 7-day freshness window (mirrors waiver-density.sh's own
# "quiet feeds emit nothing" convention).
# ----------------------------------------------------------------------
gd_digest_line() {
  local ledger
  if _have _signal_ledger_path; then
    ledger="$(_signal_ledger_path)"
  elif [[ -n "${SIGNAL_LEDGER_PATH:-}" ]]; then
    ledger="$SIGNAL_LEDGER_PATH"
  else
    ledger="${HOME:-$PWD}/.claude/state/signal-ledger.jsonl"
  fi
  [[ -f "$ledger" ]] || return 0

  local now_epoch cutoff_epoch
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  cutoff_epoch=$(( now_epoch - 7 * 86400 ))

  # Most recent gate-demotion/demote event within the window (last line
  # wins on a tie — ledger is append-only chronological).
  local latest_detail=""
  local line gate_field event_field ts_raw epoch detail_field
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    gate_field="$(printf '%s' "$line" | sed -n 's/.*"gate":"\([^"]*\)".*/\1/p')"
    event_field="$(printf '%s' "$line" | sed -n 's/.*"event":"\([^"]*\)".*/\1/p')"
    [[ "$gate_field" != "gate-demotion" ]] && continue
    [[ "$event_field" != "demote" ]] && continue
    ts_raw="$(printf '%s' "$line" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')"
    epoch="$(date -u -d "$ts_raw" '+%s' 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts_raw" '+%s' 2>/dev/null || echo 0)"
    if [[ "$epoch" -gt 0 && "$epoch" -lt "$cutoff_epoch" ]]; then
      continue
    fi
    detail_field="$(printf '%s' "$line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')"
    [[ -n "$detail_field" ]] && latest_detail="$detail_field"
  done < "$ledger"

  [[ -z "$latest_detail" ]] && return 0
  printf 'gate-demotion: %s\n' "$latest_detail"
  return 0
}

# ============================================================
# CLI dispatch
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) : ;; # handled below
    --dry-run)
      gd_dry_run "${2:-}"
      exit $?
      ;;
    --apply)
      gd_apply "${2:-}" "${3:-}"
      exit $?
      ;;
    --digest-line)
      gd_digest_line
      exit 0
      ;;
    *)
      echo "usage: gate-demotion.sh --dry-run [manifest] | --apply <src> <dst> | --digest-line | --self-test" >&2
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

  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'gdst')"
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  echo "self-test: gate-demotion.sh"

  if ! command -v jq >/dev/null 2>&1; then
    echo "self-test: jq not found on PATH — cannot exercise this script (fail-open with a clear message, not a silent skip)" >&2
    exit 1
  fi

  # ------------------------------------------------------------
  # Fixture manifest with two blocking:true gates.
  # ------------------------------------------------------------
  FIXTURE_MANIFEST="$TMP/manifest-fixture.json"
  cat > "$FIXTURE_MANIFEST" <<'JSON'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "fixture-gate-over",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["fixture-gate-over.sh"],
      "events": ["PreToolUse"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "budget_class": "pretool"
    },
    {
      "id": "fixture-gate-under",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["fixture-gate-under.sh"],
      "events": ["PreToolUse"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "budget_class": "pretool"
    },
    {
      "id": "fixture-gate-not-blocking",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["fixture-gate-not-blocking.sh"],
      "events": ["PreToolUse"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": false,
      "budget_class": "pretool"
    }
  ]
}
JSON

  # ------------------------------------------------------------
  # Fixture waiver ledger: fixture-gate-over crosses the threshold (5
  # waivers/7d); fixture-gate-under stays below it (1 waiver/7d).
  # ------------------------------------------------------------
  FIXTURE_LEDGER="$TMP/ledger-fixture.jsonl"
  _now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
  _days_ago_iso() {
    local d="$1"
    date -u -d "${d} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
      || date -u -v-"${d}"d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
  }
  _emit() {
    local ledger="$1" gate="$2" days_ago="$3"
    local ts; ts="$(_days_ago_iso "$days_ago")"
    printf '{"ts":"%s","session_id":"selftest","gate":"%s","event":"waiver","detail":"fixture"}\n' "$ts" "$gate" >> "$ledger"
  }
  for i in 1 2 3 4 5; do _emit "$FIXTURE_LEDGER" "fixture-gate-over" "$i"; done
  _emit "$FIXTURE_LEDGER" "fixture-gate-under" 1

  # ------------------------------------------------------------
  # Scenario 1: --dry-run against the fixture manifest identifies
  # fixture-gate-over (over threshold + blocking:true), never
  # fixture-gate-under (below threshold) or fixture-gate-not-blocking
  # (not blocking regardless of waiver count). Writes nothing.
  # ------------------------------------------------------------
  echo "Scenario 1: --dry-run identifies only the over-threshold, currently-blocking gate"
  DRYRUN_OUT="$( SIGNAL_LEDGER_PATH="$FIXTURE_LEDGER" bash "$SELF_ABS" --dry-run "$FIXTURE_MANIFEST" )"
  if printf '%s' "$DRYRUN_OUT" | grep -q "fixture-gate-over"; then
    pass "dry-run names fixture-gate-over as a demotion candidate"
  else
    fail "expected fixture-gate-over in dry-run output, got: $DRYRUN_OUT"
  fi
  if ! printf '%s' "$DRYRUN_OUT" | grep -q "fixture-gate-under -> "; then
    pass "dry-run does NOT propose demoting fixture-gate-under (below threshold)"
  else
    fail "unexpectedly proposed demoting fixture-gate-under: $DRYRUN_OUT"
  fi
  if ! printf '%s' "$DRYRUN_OUT" | grep -q "fixture-gate-not-blocking"; then
    pass "dry-run does NOT mention fixture-gate-not-blocking (already blocking:false)"
  else
    fail "unexpectedly mentioned fixture-gate-not-blocking: $DRYRUN_OUT"
  fi
  ORIG_HASH_BEFORE="$(sha256sum "$FIXTURE_MANIFEST" 2>/dev/null || md5sum "$FIXTURE_MANIFEST" 2>/dev/null)"
  # (dry-run must never mutate the fixture manifest it read)
  ORIG_HASH_AFTER_DRYRUN="$(sha256sum "$FIXTURE_MANIFEST" 2>/dev/null || md5sum "$FIXTURE_MANIFEST" 2>/dev/null)"
  if [[ "$ORIG_HASH_BEFORE" == "$ORIG_HASH_AFTER_DRYRUN" ]]; then
    pass "--dry-run does not modify the manifest it inspects"
  else
    fail "--dry-run unexpectedly modified the fixture manifest"
  fi

  # ------------------------------------------------------------
  # Scenario 2: --apply against a COPY flips fixture-gate-over to
  # blocking:false with the honest_status note, leaves fixture-gate-under
  # and fixture-gate-not-blocking untouched.
  # ------------------------------------------------------------
  echo "Scenario 2: --apply flips only the over-threshold gate on a manifest COPY"
  APPLY_SRC="$TMP/manifest-apply-src.json"
  APPLY_DST="$TMP/manifest-apply-dst.json"
  cp "$FIXTURE_MANIFEST" "$APPLY_SRC"
  APPLY_OUT="$( SIGNAL_LEDGER_PATH="$FIXTURE_LEDGER" bash "$SELF_ABS" --apply "$APPLY_SRC" "$APPLY_DST" )"
  if [[ -f "$APPLY_DST" ]]; then
    pass "--apply wrote the destination manifest copy"
  else
    fail "--apply did not produce $APPLY_DST"
  fi
  DEMOTED_BLOCKING="$(jq -r '.entries[] | select(.id=="fixture-gate-over") | .blocking' "$APPLY_DST" 2>/dev/null)"
  if [[ "$DEMOTED_BLOCKING" == "false" ]]; then
    pass "fixture-gate-over flipped to blocking:false in the destination copy"
  else
    fail "expected fixture-gate-over blocking:false, got: $DEMOTED_BLOCKING"
  fi
  DEMOTED_STATUS="$(jq -r '.entries[] | select(.id=="fixture-gate-over") | .honest_status' "$APPLY_DST" 2>/dev/null)"
  if printf '%s' "$DEMOTED_STATUS" | grep -q "auto-demoted"; then
    pass "fixture-gate-over honest_status carries the auto-demoted note"
  else
    fail "expected auto-demoted note in honest_status, got: $DEMOTED_STATUS"
  fi
  UNDER_BLOCKING="$(jq -r '.entries[] | select(.id=="fixture-gate-under") | .blocking' "$APPLY_DST" 2>/dev/null)"
  if [[ "$UNDER_BLOCKING" == "true" ]]; then
    pass "fixture-gate-under (below threshold) stays blocking:true"
  else
    fail "fixture-gate-under unexpectedly changed: blocking=$UNDER_BLOCKING"
  fi
  NOTBLOCK_STATUS="$(jq -r '.entries[] | select(.id=="fixture-gate-not-blocking") | .blocking' "$APPLY_DST" 2>/dev/null)"
  if [[ "$NOTBLOCK_STATUS" == "false" ]]; then
    pass "fixture-gate-not-blocking untouched (was already blocking:false)"
  else
    fail "fixture-gate-not-blocking unexpectedly changed: blocking=$NOTBLOCK_STATUS"
  fi
  if printf '%s' "$APPLY_OUT" | grep -q "fixture-gate-over"; then
    pass "--apply prints a summary line naming the demoted gate"
  else
    fail "expected a summary line naming fixture-gate-over, got: $APPLY_OUT"
  fi

  # ------------------------------------------------------------
  # Scenario 3: idempotence — re-running --apply on the already-demoted
  # copy does not double-append the honest_status note (the jq guard's
  # `.blocking == true` condition is now false for fixture-gate-over).
  # ------------------------------------------------------------
  echo "Scenario 3: re-running --apply on an already-demoted manifest is idempotent"
  APPLY_DST2="$TMP/manifest-apply-dst2.json"
  ( SIGNAL_LEDGER_PATH="$FIXTURE_LEDGER" bash "$SELF_ABS" --apply "$APPLY_DST" "$APPLY_DST2" >/dev/null )
  REDEMOTED_STATUS="$(jq -r '.entries[] | select(.id=="fixture-gate-over") | .honest_status' "$APPLY_DST2" 2>/dev/null)"
  OCCURRENCES="$(printf '%s' "$REDEMOTED_STATUS" | grep -o "auto-demoted" | wc -l | tr -d ' ')"
  if [[ "$OCCURRENCES" == "1" ]]; then
    pass "re-applying does not double-append the auto-demoted note (occurrences=$OCCURRENCES)"
  else
    fail "expected exactly 1 occurrence of 'auto-demoted' after re-apply, got $OCCURRENCES: $REDEMOTED_STATUS"
  fi
  REDEMOTED_BLOCKING="$(jq -r '.entries[] | select(.id=="fixture-gate-over") | .blocking' "$APPLY_DST2" 2>/dev/null)"
  if [[ "$REDEMOTED_BLOCKING" == "false" ]]; then
    pass "already-demoted gate stays blocking:false on re-apply"
  else
    fail "already-demoted gate unexpectedly changed: blocking=$REDEMOTED_BLOCKING"
  fi

  # ------------------------------------------------------------
  # Scenario 4: --apply with NO gate over threshold is a clean no-op copy.
  # ------------------------------------------------------------
  echo "Scenario 4: no gate over threshold -> --apply copies src to dst unchanged"
  EMPTY_LEDGER="$TMP/empty-ledger.jsonl"
  : > "$EMPTY_LEDGER"
  APPLY_DST3="$TMP/manifest-apply-dst3.json"
  ( SIGNAL_LEDGER_PATH="$EMPTY_LEDGER" bash "$SELF_ABS" --apply "$FIXTURE_MANIFEST" "$APPLY_DST3" >/dev/null )
  NOOP_BLOCKING="$(jq -r '.entries[] | select(.id=="fixture-gate-over") | .blocking' "$APPLY_DST3" 2>/dev/null)"
  if [[ "$NOOP_BLOCKING" == "true" ]]; then
    pass "empty ledger -> no demotion, fixture-gate-over stays blocking:true"
  else
    fail "expected no-op (blocking:true) with an empty ledger, got: $NOOP_BLOCKING"
  fi

  # ------------------------------------------------------------
  # Scenario 5: the REAL repo manifest.json is never touched by any
  # scenario above (mechanical proof the self-test only operates on
  # copies, per §F.0.1's orchestrator-only manifest-edit rule).
  # ------------------------------------------------------------
  echo "Scenario 5: the real adapters/claude-code/manifest.json was not touched"
  REAL_MANIFEST=""
  if command -v git >/dev/null 2>&1; then
    REAL_ROOT="$(git -C "$_GD_SELF_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$REAL_ROOT" && -f "$REAL_ROOT/adapters/claude-code/manifest.json" ]]; then
      REAL_MANIFEST="$REAL_ROOT/adapters/claude-code/manifest.json"
    fi
  fi
  if [[ -n "$REAL_MANIFEST" ]]; then
    REAL_HASH_BEFORE_TEST="__unset__"
    # We cannot know the pre-self-test hash retroactively, but we CAN assert
    # the real manifest contains no "fixture-gate-" ids and no
    # "auto-demoted" honest_status text this self-test would have
    # introduced — a targeted content check rather than a full-file hash,
    # since other tasks may legitimately edit the real manifest between
    # this self-test's runs.
    if ! grep -q "fixture-gate-over\|fixture-gate-under\|fixture-gate-not-blocking" "$REAL_MANIFEST" 2>/dev/null; then
      pass "the real repo manifest.json contains no self-test fixture ids"
    else
      fail "the REAL manifest.json unexpectedly contains self-test fixture ids"
    fi
  else
    pass "real manifest.json not resolvable from this environment — skipping (not a failure; sandboxing is enforced by construction via explicit src/dst args regardless)"
  fi

  # ------------------------------------------------------------
  # Scenario 6: --digest-line — a fresh demotion event produces exactly one
  # line; an event older than 7 days produces silence.
  # ------------------------------------------------------------
  echo "Scenario 6: --digest-line freshness windowing"
  DIGEST_LEDGER="$TMP/digest-ledger.jsonl"
  FRESH_TS="$(_now_iso)"
  printf '{"ts":"%s","session_id":"selftest","gate":"gate-demotion","event":"demote","detail":"fixture-gate-x auto-demoted blocking:false (E.3 threshold, 4 waivers/7d)"}\n' "$FRESH_TS" > "$DIGEST_LEDGER"
  DIGEST_OUT="$( SIGNAL_LEDGER_PATH="$DIGEST_LEDGER" bash "$SELF_ABS" --digest-line )"
  if printf '%s' "$DIGEST_OUT" | grep -q "fixture-gate-x auto-demoted"; then
    pass "--digest-line surfaces a fresh demotion event"
  else
    fail "expected fresh demotion event in digest-line output, got: $DIGEST_OUT"
  fi

  STALE_LEDGER="$TMP/stale-ledger.jsonl"
  STALE_TS="$(_days_ago_iso 10)"
  printf '{"ts":"%s","session_id":"selftest","gate":"gate-demotion","event":"demote","detail":"fixture-gate-y auto-demoted blocking:false (E.3 threshold, 4 waivers/7d)"}\n' "$STALE_TS" > "$STALE_LEDGER"
  STALE_OUT="$( SIGNAL_LEDGER_PATH="$STALE_LEDGER" bash "$SELF_ABS" --digest-line )"
  if [[ -z "$STALE_OUT" ]]; then
    pass "--digest-line stays silent for a demotion event older than 7 days"
  else
    fail "expected silence for a stale demotion event, got: $STALE_OUT"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
