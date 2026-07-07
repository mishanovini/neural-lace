#!/bin/bash
# session-heartbeat.sh — per-session liveness file writer + sweep report
# (NL Observability Program Wave O, task O.2 — specs-o §O.2, frozen contract
# C1 in §O.0.3).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The observability design sketch's law 1 (DERIVE-DON'T-MAINTAIN) requires
# "is a session alive, stalled, or crashed" to be computed from ground
# truth, never from a session self-reporting its own health. This script IS
# that ground truth: a small atomic per-session JSON file, touched at
# lifecycle boundaries (session start, end of turn, PreCompact, resume).
# Staleness is NEVER written into the file — it is always computed on READ
# (hooks/lib/session-heartbeat-lib.sh's hb_is_stale/hb_classify, the single
# shared implementation §O.3's `od_sessions` also calls, so the heartbeat
# script's own `sweep` verb and the future derivation lib can never drift
# apart on what "stale" means).
#
# ============================================================
# CONTRACT
# ============================================================
#
#   session-heartbeat.sh touch --event <start|turn-end|compact|resume>
#                               [--marker <DONE|PAUSING|BLOCKED|CONTINUING|none>]
#     Atomically writes/overwrites this session's heartbeat file (schema
#     per C1; see hooks/lib/session-heartbeat-lib.sh's header for the exact
#     JSON shape). NEVER BLOCKS — exit 0 always, on every code path
#     (mirrors ledger_emit / needs-you.sh add's writer-never-blocks
#     contract: a liveness tick is observability, not enforcement). Reads
#     pid ($$), cwd ($PWD), branch (`git branch --show-current` in
#     ${CLAUDE_PROJECT_DIR:-$PWD}), and model from env
#     ($CLAUDE_MODEL/$ANTHROPIC_MODEL) — see the lib's hb_write for the
#     exact resolution.
#
#   session-heartbeat.sh sweep [--json] [--stale-min <n>]
#     Report-only: lists every heartbeat file's session id + classification
#     (live|stale|crashed) per hb_classify, using the SAME lib functions
#     §O.3's `od_sessions` will call — the computation lives in
#     session-heartbeat-lib.sh once, shared here and there. Never blocks;
#     exit 0 always (a listing is not a verdict this script enforces).
#
#   session-heartbeat.sh --self-test
#     Runs a self-contained assertion suite, entirely sandboxed under
#     HEARTBEAT_STATE_DIR (see SANDBOXING below) — never touches the real
#     machine's heartbeat state.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — §O.0.1-3)
# ============================================================
#
# All state-directory resolution is delegated to
# hooks/lib/session-heartbeat-lib.sh's hb_state_dir (HEARTBEAT_STATE_DIR
# env override, else HARNESS_SELFTEST=1 sandboxed TMPDIR path, else the
# real $HOME/.claude/state/heartbeats). This script never resolves the
# path itself — one implementation, sourced.
#
# ============================================================
# CALL-SITES (fragment — see tests/fixtures/wave-o/O.2/callsite-wiring.md)
# ============================================================
#
# This script does NOT wire its own call-sites: session-start-digest.sh,
# workstreams-stop-writer.sh (chain member), and pre-compact-continuity.sh
# are OWNED by the O.1 builder this batch (specs-o §O.0.2 dispatch map).
# The exact one-line splices are shipped as a fragment for the orchestrator
# to apply — see tests/fixtures/wave-o/O.2/callsite-wiring.md.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/session-heartbeat-lib.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/session-heartbeat-lib.sh"
else
  echo "session-heartbeat.sh: cannot find hooks/lib/session-heartbeat-lib.sh next to scripts/ — aborting (never blocks caller: this is a standalone script, not a hook)" >&2
  exit 0
fi

ALLOWED_EVENTS=(start turn-end compact resume)
ALLOWED_MARKERS=(DONE PAUSING BLOCKED CONTINUING none)

_sh_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# ----------------------------------------------------------------------
# cmd_touch — parse --event/--marker, validate, call hb_write. NEVER
# BLOCKS: an invalid --event or a write failure still exits 0 (this is a
# liveness tick, not a gate); it prints a diagnostic to stderr on the
# invalid-input path so a misconfigured caller is still discoverable, but
# never fails the calling hook chain.
# ----------------------------------------------------------------------
cmd_touch() {
  local event="" marker="none"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event) event="${2:-}"; shift 2 ;;
      --marker) marker="${2:-none}"; shift 2 ;;
      *) echo "session-heartbeat.sh touch: unknown flag '$1' (ignored, never blocks)" >&2; shift ;;
    esac
  done

  if [[ -z "$event" ]]; then
    echo "session-heartbeat.sh touch: --event is required (touch is a no-op this call, exit 0)" >&2
    return 0
  fi
  if ! _sh_in_list "$event" "${ALLOWED_EVENTS[@]}"; then
    echo "session-heartbeat.sh touch: unknown --event '$event' (expected one of: ${ALLOWED_EVENTS[*]}; writing anyway so a new event class doesn't require a script change, per the lib's contract note)" >&2
  fi
  if [[ -n "$marker" ]] && ! _sh_in_list "$marker" "${ALLOWED_MARKERS[@]}"; then
    echo "session-heartbeat.sh touch: unknown --marker '$marker' (expected one of: ${ALLOWED_MARKERS[*]}; writing anyway)" >&2
  fi

  hb_write "$event" "$marker" >/dev/null 2>&1 || true
  return 0
}

# ----------------------------------------------------------------------
# cmd_sweep — list every heartbeat file's session id + classification.
# Plain-text by default (one "<session_id>  <state>  <last_activity_ts>
# <branch>" line per file); --json emits an array of objects. Never
# blocks; exit 0 always. Empty state dir -> prints nothing (plain) or "[]"
# (--json), not an error.
# ----------------------------------------------------------------------
cmd_sweep() {
  local as_json=0 stale_min="${OBS_STALE_MIN:-30}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --stale-min) stale_min="${2:-30}"; shift 2 ;;
      *) echo "session-heartbeat.sh sweep: unknown flag '$1' (ignored)" >&2; shift ;;
    esac
  done

  local dir
  dir="$(hb_state_dir)"

  local -a files=()
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
  fi

  if [[ "$as_json" == "1" ]]; then
    if [[ "${#files[@]}" -eq 0 ]]; then
      echo "[]"
      return 0
    fi
    local out="[" first=1
    local f sid ts branch state
    for f in "${files[@]}"; do
      sid="$(_hb_field "$f" "session_id")"
      ts="$(_hb_field "$f" "last_activity_ts")"
      branch="$(_hb_field "$f" "branch")"
      state="$(hb_classify "$f" "$stale_min")"
      [[ "$first" == "1" ]] && first=0 || out+=","
      out+="$(printf '{"session_id":"%s","state":"%s","last_activity_ts":"%s","branch":"%s"}' \
        "$(_hb_json_escape "$sid")" "$state" "$(_hb_json_escape "$ts")" "$(_hb_json_escape "$branch")")"
    done
    out+="]"
    printf '%s\n' "$out"
    return 0
  fi

  if [[ "${#files[@]}" -eq 0 ]]; then
    return 0
  fi
  local f sid ts branch state
  for f in "${files[@]}"; do
    sid="$(_hb_field "$f" "session_id")"
    ts="$(_hb_field "$f" "last_activity_ts")"
    branch="$(_hb_field "$f" "branch")"
    state="$(hb_classify "$f" "$stale_min")"
    printf '%s  %s  %s  %s\n' "$sid" "$state" "$ts" "$branch"
  done
  return 0
}

# ============================================================
# --self-test
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'shst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$TMP/hb"
  mkdir -p "$HEARTBEAT_STATE_DIR"

  echo "Scenario A: touch --event start writes a jq-valid heartbeat file"
  ( export CLAUDE_CODE_SESSION_ID="sess-a"; cmd_touch --event start )
  local fa="$HEARTBEAT_STATE_DIR/sess-a.json"
  if [[ -f "$fa" ]]; then
    pass "touch --event start created the heartbeat file"
  else
    fail "expected $fa to exist after touch --event start"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$fa" >/dev/null 2>&1; then
      pass "written file is valid JSON per jq"
    else
      fail "written file is not valid JSON"
    fi
  fi

  echo "Scenario B: touch --event turn-end --marker DONE round-trips marker_state"
  ( export CLAUDE_CODE_SESSION_ID="sess-b"; cmd_touch --event turn-end --marker DONE )
  local fb="$HEARTBEAT_STATE_DIR/sess-b.json"
  local marker_v
  marker_v="$(_hb_field "$fb" "marker_state")"
  if [[ "$marker_v" == "DONE" ]]; then
    pass "marker_state DONE round-trips through touch"
  else
    fail "expected marker_state DONE, got '$marker_v'"
  fi

  echo "Scenario C: sweep lists a fresh session as live and an old one as stale"
  cat > "$HEARTBEAT_STATE_DIR/sess-old.json" <<'EOF'
{"schema":1,"session_id":"sess-old","pid":999999,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  local sweep_out
  sweep_out="$(cmd_sweep)"
  if printf '%s' "$sweep_out" | grep -q "sess-old  stale\|sess-old  crashed"; then
    pass "sweep classifies the 2020-dated fixture as stale/crashed"
  else
    fail "sweep did not classify sess-old as stale/crashed: [$sweep_out]"
  fi
  if printf '%s' "$sweep_out" | grep -q "sess-a  live"; then
    pass "sweep classifies the just-touched sess-a as live"
  else
    fail "sweep did not classify sess-a as live: [$sweep_out]"
  fi

  echo "Scenario D: sweep --json emits valid JSON covering every fixture"
  local sweep_json
  sweep_json="$(cmd_sweep --json)"
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$sweep_json" | jq -e . >/dev/null 2>&1; then
      pass "sweep --json output is valid JSON"
    else
      fail "sweep --json output is not valid JSON: [$sweep_json]"
    fi
    local n
    n="$(printf '%s' "$sweep_json" | jq 'length' 2>/dev/null)"
    if [[ "$n" -ge 3 ]]; then
      pass "sweep --json lists at least the 3 fixture sessions (got $n)"
    else
      fail "expected >=3 entries in sweep --json, got $n"
    fi
  fi

  echo "Scenario E: touch never blocks on an invalid --event (exit 0, diagnostic to stderr)"
  local rc
  ( export CLAUDE_CODE_SESSION_ID="sess-e"; cmd_touch --event bogus-event 2>/dev/null )
  rc=$?
  if [[ "$rc" == "0" ]]; then
    pass "touch with an unknown --event still exits 0"
  else
    fail "touch with an unknown --event exited $rc (expected 0 — never blocks)"
  fi

  echo "Scenario F: flagless-shape scenario — invoke touch exactly as the real call-site does"
  # Mirrors the exact call-line shipped in
  # tests/fixtures/wave-o/O.2/callsite-wiring.md for session-start-digest.sh:
  #   session-heartbeat.sh touch --event start
  # with ONLY env-var sandboxing (no extra flags, no fixture-scoped path on
  # the command line) — this is the §O.0.1-4 flagless-invocation-shape must.
  rm -f "$HEARTBEAT_STATE_DIR"/sess-flagless*.json 2>/dev/null
  (
    export CLAUDE_CODE_SESSION_ID="sess-flagless-real-shape"
    bash "$SCRIPT_DIR/session-heartbeat.sh" touch --event start
  )
  local ff="$HEARTBEAT_STATE_DIR/sess-flagless-real-shape.json"
  if [[ -f "$ff" ]]; then
    pass "flagless-shape scenario: real call-line 'session-heartbeat.sh touch --event start' (env-sandboxed only) wrote the heartbeat file"
  else
    fail "flagless-shape scenario: expected $ff after invoking the real call-line"
  fi

  echo "Scenario G: sweep on an empty state dir prints nothing (plain) / [] (--json), never errors"
  local empty_dir="$TMP/hb-empty"
  mkdir -p "$empty_dir"
  local empty_out empty_json rc2
  empty_out="$(HEARTBEAT_STATE_DIR="$empty_dir" cmd_sweep)"
  rc2=$?
  empty_json="$(HEARTBEAT_STATE_DIR="$empty_dir" cmd_sweep --json)"
  if [[ "$rc2" == "0" && -z "$empty_out" && "$empty_json" == "[]" ]]; then
    pass "sweep on empty dir: exit 0, empty plain output, [] JSON output"
  else
    fail "sweep on empty dir mismatch: rc=$rc2 out=[$empty_out] json=[$empty_json]"
  fi

  rm -rf "$TMP" 2>/dev/null || true

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
  touch)
    shift
    cmd_touch "$@"
    exit 0
    ;;
  sweep)
    shift
    cmd_sweep "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help|"")
    cat <<'USAGE'
session-heartbeat.sh — per-session liveness file (NL Observability Program O.2)

Verbs:
  touch --event <start|turn-end|compact|resume> [--marker <state>]
                          Atomically write/refresh this session's heartbeat
                          file. Never blocks; exit 0 always.
  sweep [--json] [--stale-min <n>]
                          Report-only: list every heartbeat file's
                          classification (live|stale|crashed) per
                          hooks/lib/session-heartbeat-lib.sh's hb_classify.
  --self-test             Run the self-test suite (sandboxed).

See adapters/claude-code/scripts/session-heartbeat.sh header comment for
the full contract, and hooks/lib/session-heartbeat-lib.sh for the frozen
C1 file schema.
USAGE
    exit 0
    ;;
  *)
    echo "session-heartbeat.sh: unknown verb '$1' (run without args for usage; never blocks a caller since this is a standalone script)" >&2
    exit 0
    ;;
esac
