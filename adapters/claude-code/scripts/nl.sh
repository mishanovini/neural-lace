#!/bin/bash
# nl.sh — the `nl` CLI (NL Observability Program Wave O, task O.3 —
# specs-o §O.3, frozen contract C5).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# `hooks/lib/observability-derive.sh` (contract C4) is the derivation
# layer answering the six operator questions; this file is the thin
# human-facing CLI over it. It has NO logic of its own beyond argument
# dispatch and output formatting glue — every actual computation lives
# in the sourced C4 lib, so a bug fixed there is fixed for every
# consumer (this CLI, the future workstreams-ui cockpit shelling out to
# `nl <sub> --json`, and any doctor predicate that wants a derived
# answer) at once.
#
# ============================================================
# CONTRACT (specs-o §O.0.3 C5)
# ============================================================
#
#   nl status                 - Q1 (od_sessions) + one-line Q4 header
#                                (od_harness_health's doctor verdict)
#   nl needs-me                - Q2 (od_needs_me)
#   nl why <session> [--last-block]
#                               - Q6 (od_why)
#   nl costs [<session>]       - Q5 (od_costs)
#   nl shipped [--since <ts>]  - Q3 (od_shipped_since)
#   nl backlog                 - od_backlog_health
#   nl health                  - Q4 full passthrough (od_harness_health:
#                                doctor verdict + per-gate 7d
#                                block/waiver/downgrade counts, incl.
#                                waiver-dominant flags). `nl status`'s own
#                                header line stays a ONE-line doctor
#                                summary only (Q1 board is the point of
#                                that subcommand) — `nl health` is the
#                                full Q4 answer; `nl status --json` does
#                                NOT carry `.gates[]` (verifier-round fix:
#                                it used to compose {sessions, doctor} and
#                                silently discard od_harness_health's
#                                gates array — `nl health --json` is the
#                                one place that array is exposed, rather
#                                than duplicating it into every `status`
#                                payload).
#   each subcommand accepts --json for machine-readable output.
#
# Installed via the existing scripts/*.sh install glob — no install
# fragment needed (per §O.0.1-1's own note: "most tasks need NO install
# fragment").
#
# ============================================================
# USAGE
# ============================================================
#
#   bash scripts/nl.sh status
#   bash scripts/nl.sh needs-me --json
#   bash scripts/nl.sh why sess-abc123 --last-block
#   bash scripts/nl.sh costs sess-abc123
#   bash scripts/nl.sh shipped --since 2026-07-01T00:00:00Z
#   bash scripts/nl.sh backlog --json
#   bash scripts/nl.sh --self-test

set -u

_NL_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_NL_HOOKS_LIB="$_NL_SELF_DIR/../hooks/lib"

if [[ -f "$_NL_HOOKS_LIB/observability-derive.sh" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$_NL_HOOKS_LIB/observability-derive.sh"
else
  echo "nl: cannot find hooks/lib/observability-derive.sh (looked in $_NL_HOOKS_LIB)" >&2
  exit 1
fi
# shellcheck disable=SC1091
{ source "$_NL_HOOKS_LIB/hook-reentry-guard.sh" 2>/dev/null; } || true

_nl_have() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------
# _nl_spawn_breaker_tripped — NL-FINDING-040 item C: a cheap guard bounding
# the nl.sh-dominant amplification signature from the spawn-cascade
# incident (workstreams-ui's derive-cache.js polls `bash nl.sh <sub>
# --json` on a 30s timer per running cockpit server instance — see
# neural-lace/workstreams-ui/server/derive-cache.js; every additional
# concurrently-running cockpit instance, e.g. one per worktree checkout,
# multiplies the spawn rate). Trips (returns 0/true) when EITHER:
#   - NL_HOOK_REENTRY=1 (this invocation is itself inside an automation-
#     spawned/re-entrant chain — see lib/hook-reentry-guard.sh), OR
#   - the live sibling process count of nl.sh/observability-derive.sh
#     processes on this machine right now is >= NL_SPAWN_CEILING (default
#     10, env-overridable; 0 disables this specific signal).
# Never blocks on an undetermined process count (tolerates ps/tasklist
# both being unavailable — fails OPEN on the diagnostic, exactly like
# session-resumer.sh's own live_process_count).
# ----------------------------------------------------------------------
_nl_spawn_breaker_tripped() {
  if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
    printf 'NL_HOOK_REENTRY set (automation-spawned/re-entrant invocation)'
    return 0
  fi
  local ceiling="${NL_SPAWN_CEILING:-10}"
  [[ "$ceiling" =~ ^[0-9]+$ ]] || ceiling=10
  [[ "$ceiling" -eq 0 ]] && return 1
  local count=""
  if [[ -n "${NL_SPAWN_PROCESS_COUNT_OVERRIDE:-}" ]]; then
    count="$NL_SPAWN_PROCESS_COUNT_OVERRIDE"
  elif command -v ps >/dev/null 2>&1; then
    # ps -ef FIRST (full command lines), ps -W fallback. Exclude the grep
    # itself and this process's own pid so the probe agrees with
    # session-resumer.sh's live_process_count (FIX-3 consistency).
    count=$(ps -ef 2>/dev/null | grep -iE 'nl\.sh|observability-derive\.sh' 2>/dev/null | grep -vE 'grep' 2>/dev/null | awk -v self="$$" '$0 !~ ("(^| )" self "( |$)")' 2>/dev/null | grep -c '' 2>/dev/null)
    if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -eq 0 ]]; then
      count=$(ps -W 2>/dev/null | grep -ciE 'nl\.sh|observability-derive\.sh' 2>/dev/null)
    fi
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  if [[ "$count" -ge "$ceiling" ]]; then
    printf 'live nl.sh/observability-derive process count %s >= ceiling %s (NL_SPAWN_CEILING)' "$count" "$ceiling"
    return 0
  fi
  return 1
}

_nl_usage() {
  cat <<'EOF'
usage: nl <subcommand> [args] [--json]

subcommands:
  status              Q1 session board + one-line Q4 harness-health header
  needs-me            Q2 items awaiting your decision
  why <session> [--last-block]
                      Q6 causal chain for a session (hooks fired -> state
                      read -> verdict -> what happened next)
  costs [<session>]   Q5 token usage + throttle time lost
  shipped [--since <iso-ts>]
                      Q3 what shipped since a timestamp (default: 24h ago)
  backlog             backlog health oracle (od_backlog_health)
  health              Q4 full harness-health passthrough (doctor verdict
                      + per-gate 7d block/waiver/downgrade counts,
                      od_harness_health in full — `nl status`'s header
                      line is a one-line summary only)

Each subcommand accepts --json for machine-readable output.
EOF
}

cmd_status() {
  local json_mode=0
  local a
  for a in "$@"; do [[ "$a" == "--json" ]] && json_mode=1; done

  if [[ "$json_mode" == "1" ]]; then
    local sessions_json health_json
    sessions_json="$(od_sessions --json)"
    health_json="$(od_harness_health --json)"
    if _nl_have jq; then
      jq -n --argjson s "$sessions_json" --argjson h "$health_json" \
        '{schema:1,oracle:"nl-status",sessions:$s.sessions,doctor:$h.doctor}'
    else
      printf '{"schema":1,"oracle":"nl-status","sessions":%s,"health":%s}\n' "$sessions_json" "$health_json"
    fi
    return 0
  fi

  od_harness_health | head -n1
  echo ""
  od_sessions
  return 0
}

cmd_needs_me() {
  od_needs_me "$@"
}

cmd_why() {
  local sid="" last_block=0 json_mode=0
  local -a rest=()
  for a in "$@"; do
    case "$a" in
      --last-block) last_block=1 ;;
      --json) json_mode=1 ;;
      *) rest+=("$a") ;;
    esac
  done
  sid="${rest[0]:-}"
  if [[ -z "$sid" ]]; then
    echo "usage: nl why <session-id> [--last-block] [--json]" >&2
    return 1
  fi
  local -a fargs=("$sid")
  [[ "$last_block" == "1" ]] && fargs+=(--last-block)
  [[ "$json_mode" == "1" ]] && fargs+=(--json)
  od_why "${fargs[@]}"
}

cmd_costs() {
  local sid="" json_mode=0
  local -a rest=()
  for a in "$@"; do
    case "$a" in
      --json) json_mode=1 ;;
      *) rest+=("$a") ;;
    esac
  done
  sid="${rest[0]:-}"
  local -a fargs=()
  [[ -n "$sid" ]] && fargs+=(--session "$sid")
  [[ "$json_mode" == "1" ]] && fargs+=(--json)
  od_costs "${fargs[@]}"
}

cmd_shipped() {
  local since="" json_mode=0
  local -a rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="$2"; shift 2 ;;
      --json) json_mode=1; shift ;;
      *) rest+=("$1"); shift ;;
    esac
  done
  if [[ -z "$since" ]]; then
    since="$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi
  local -a fargs=("$since")
  [[ "$json_mode" == "1" ]] && fargs+=(--json)
  od_shipped_since "${fargs[@]}"
}

cmd_backlog() {
  od_backlog_health "$@"
}

cmd_health() {
  od_harness_health "$@"
}

# ============================================================
# CLI dispatch (only when executed directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  # NL-FINDING-040 item C: a real (non-self-test, non-help) subcommand
  # invocation checks the generic spawn breaker FIRST — before any od_*
  # derivation function runs (some of which, e.g. od_backlog_health, are
  # measured at 80-258s on the real estate; see derive-cache.js's own
  # per-subcommand timeout comments). Skipped entirely for --self-test/
  # -h/--help/bare so the self-test suite and interactive help are never
  # affected by ambient machine process counts.
  case "${1:-}" in
    --self-test|-h|--help|"") ;;
    *)
      _nl_breaker_reason="$(_nl_spawn_breaker_tripped)"
      if [[ -n "$_nl_breaker_reason" ]]; then
        echo "nl: spawn breaker tripped — skipping derivation (${_nl_breaker_reason})" >&2
        exit 0
      fi
      ;;
  esac

  case "${1:-}" in
    --self-test)
      : # handled below, after function defs
      ;;
    status)     shift; cmd_status "$@"; exit $? ;;
    needs-me)   shift; cmd_needs_me "$@"; exit $? ;;
    why)        shift; cmd_why "$@"; exit $? ;;
    costs)      shift; cmd_costs "$@"; exit $? ;;
    shipped)    shift; cmd_shipped "$@"; exit $? ;;
    backlog)    shift; cmd_backlog "$@"; exit $? ;;
    health)     shift; cmd_health "$@"; exit $? ;;
    -h|--help|"")
      _nl_usage
      exit 0
      ;;
    *)
      echo "nl: unknown subcommand '${1:-}'" >&2
      _nl_usage >&2
      exit 1
      ;;
  esac
fi

# ============================================================
# --self-test — sandboxes ALL writes per §O.0.1-3. This is a thin-
# dispatcher self-test: it seeds a fixture estate (heartbeats + ledger +
# transcripts + needs-you ledger + backlog file) once and asserts each
# subcommand's output SHAPE, since the actual computation is already
# exhaustively tested by observability-derive.sh's own --self-test. The
# LAST scenario mirrors the REAL flagless invocation shape (no fixture-
# scoped flags on the command line beyond the subcommand itself, only
# env-var sandboxing) per §O.0.1-4.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'nlst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$TMP/heartbeats"
  export SIGNAL_LEDGER_PATH="$TMP/ledger.jsonl"
  export NEEDS_YOU_STATE_DIR="$TMP/needs-you"
  export OBS_BACKLOG_PATH="$TMP/backlog.md"
  export OBS_TRANSCRIPTS_DIR="$TMP/transcripts"
  export DOCTOR_CACHE_PATH="$TMP/doctor-cache.json"
  mkdir -p "$HEARTBEAT_STATE_DIR" "$NEEDS_YOU_STATE_DIR" "$OBS_TRANSCRIPTS_DIR"
  unset CLAUDE_CODE_SESSION_ID
  # FIX-5 (test hygiene): every scenario below shells `bash $SELF_ABS <sub>`,
  # each of which now runs the NL-FINDING-040 spawn breaker. If this suite
  # is itself run inside a reentrant env (NL_HOOK_REENTRY=1) or a machine
  # over the sibling-process ceiling, those sub-invocations would no-op and
  # every scenario would self-fail. Scrub both signals for the suite so the
  # real subcommand code paths are exercised deterministically regardless
  # of the ambient env this suite happens to run under.
  unset NL_HOOK_REENTRY NL_SPAWN_PROCESS_COUNT_OVERRIDE
  export NL_SPAWN_CEILING=0

  SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  # Seed a minimal fixture estate.
  cat > "$HEARTBEAT_STATE_DIR/sess-t1.json" <<EOF
{"schema":1,"session_id":"sess-t1","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
  cat > "$NEEDS_YOU_STATE_DIR/ledger.json" <<'EOF'
{"schema_version":1,"items":[{"id":"ny1","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z","section":"question","text":"fixture question","links":[],"session":"sess-t1","tier":null,"state":"open","resolved_at":null,"resolution_note":null}]}
EOF
  cat > "$DOCTOR_CACHE_PATH" <<EOF
{"ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","verdict_line":"[doctor] GREEN","exit_code":0}
EOF
  {
    printf '{"ts":"%s","session_id":"sess-t1","gate":"fixture-gate","event":"block","detail":"x"}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >> "$SIGNAL_LEDGER_PATH"
  cat > "$OBS_BACKLOG_PATH" <<EOF
# fixture backlog

- **FIX-01** priority:high added $(date -u '+%Y-%m-%d') — a fixture row
EOF
  printf '{"type":"assistant","message":{"usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$OBS_TRANSCRIPTS_DIR/sess-t1.jsonl"

  echo "Scenario 1: nl status (default + --json)"
  out1="$(bash "$SELF_ABS" status)"
  if printf '%s' "$out1" | grep -q "doctor:" && printf '%s' "$out1" | grep -q "sess-t1"; then
    pass "nl status shows the Q4 doctor header and the Q1 session board"
  else
    fail "nl status missing expected content: $out1"
  fi
  out1j="$(bash "$SELF_ABS" status --json)"
  if _nl_have jq && printf '%s' "$out1j" | jq -e . >/dev/null 2>&1; then
    pass "nl status --json is valid JSON"
  else
    fail "nl status --json is not valid JSON: $out1j"
  fi

  echo "Scenario 2: nl needs-me"
  out2="$(bash "$SELF_ABS" needs-me)"
  if printf '%s' "$out2" | grep -q "fixture question"; then
    pass "nl needs-me surfaces the fixture open item"
  else
    fail "nl needs-me missing fixture item: $out2"
  fi

  echo "Scenario 3: nl why <session> --last-block"
  out3="$(bash "$SELF_ABS" why sess-t1 --last-block)"
  if printf '%s' "$out3" | grep -q "fixture-gate"; then
    pass "nl why surfaces the fixture ledger event"
  else
    fail "nl why missing fixture-gate: $out3"
  fi

  echo "Scenario 4: nl costs <session>"
  out4="$(bash "$SELF_ABS" costs sess-t1)"
  if printf '%s' "$out4" | grep -q "oracle: od_costs"; then
    pass "nl costs delegates to od_costs (oracle named)"
  else
    fail "nl costs missing oracle tag: $out4"
  fi

  echo "Scenario 5: nl shipped --since <ts>"
  out5="$(bash "$SELF_ABS" shipped --since "1970-01-01T00:00:00Z")"
  if printf '%s' "$out5" | grep -q "oracle: od_shipped_since"; then
    pass "nl shipped delegates to od_shipped_since (oracle named)"
  else
    fail "nl shipped missing oracle tag: $out5"
  fi

  echo "Scenario 6: nl backlog"
  out6="$(bash "$SELF_ABS" backlog)"
  if printf '%s' "$out6" | grep -q "FIX-01" || printf '%s' "$out6" | grep -q "oracle: od_backlog_health"; then
    pass "nl backlog delegates to od_backlog_health"
  else
    fail "nl backlog missing expected content: $out6"
  fi

  echo "Scenario 6b: nl health (Q4 full passthrough, incl. gates the fixture ledger's block event produced)"
  out6b="$(bash "$SELF_ABS" health)"
  if printf '%s' "$out6b" | grep -q "oracle: od_harness_health" && printf '%s' "$out6b" | grep -q "fixture-gate"; then
    pass "nl health delegates to od_harness_health and surfaces per-gate activity"
  else
    fail "nl health missing expected content: $out6b"
  fi
  out6bj="$(bash "$SELF_ABS" health --json)"
  if _nl_have jq && printf '%s' "$out6bj" | jq -e '.gates | type == "array" and length > 0' >/dev/null 2>&1; then
    pass "nl health --json exposes a non-empty .gates[] array (the array 'nl status --json' deliberately omits)"
  else
    fail "nl health --json missing non-empty .gates[]: $out6bj"
  fi

  echo "Scenario 7: unknown subcommand exits 1 with usage on stderr"
  set +e
  out7="$(bash "$SELF_ABS" bogus-subcommand 2>&1)"
  rc7=$?
  set -e
  if [[ "$rc7" -eq 1 ]] && printf '%s' "$out7" | grep -q "unknown subcommand"; then
    pass "unknown subcommand exits 1 with a usage message"
  else
    fail "expected rc=1 + usage message, got rc=$rc7 out=$out7"
  fi

  echo "Scenario 8: bare invocation (no subcommand) prints usage, exit 0"
  set +e
  out8="$(bash "$SELF_ABS" 2>&1)"
  rc8=$?
  set -e
  if [[ "$rc8" -eq 0 ]] && printf '%s' "$out8" | grep -q "usage: nl"; then
    pass "bare 'nl' prints usage and exits 0"
  else
    fail "expected rc=0 + usage, got rc=$rc8 out=$out8"
  fi

  echo "Scenario 9: flagless-shape scenario — 'nl status' exactly as production/cockpit would invoke it (only env sandboxing, no fixture-scoped CLI flags)"
  set +e
  # FIX-5: explicitly scrub NL_HOOK_REENTRY for this sub-invocation (env -u)
  # in addition to the suite-wide scrub above — this scenario asserts the
  # REAL flagless production/cockpit invocation runs clean, so it must not
  # be silently skipped by the spawn breaker via an inherited reentrancy signal.
  out9="$(env -u NL_HOOK_REENTRY bash "$SELF_ABS" status)"
  rc9=$?
  set -e
  if [[ "$rc9" -eq 0 ]] && [[ -n "$out9" ]]; then
    pass "the real flagless 'nl status' invocation (env-sandboxed only) runs clean and produces output"
  else
    fail "flagless 'nl status' invocation failed: rc=$rc9"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
