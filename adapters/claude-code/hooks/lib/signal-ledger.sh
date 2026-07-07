# signal-ledger.sh — shared library: ONE append-only JSONL ledger for every
# gate/hook signal (block / warn / waiver / downgrade / skip).
#
# ============================================================
# WHY THIS EXISTS (NL Overhaul Program Wave D, task D.1 — ADR 058 D6)
# ============================================================
#
# The 2026-07-01 effectiveness audit found a 0%-consumed signal loop: every
# gate narrated its own outcome to its own stderr / its own log file, and
# nothing aggregated them. 107 recent retry-guard downgrades, 12 acceptance
# waivers, and every other "the gate let this through anyway" event were
# each recorded (if at all) in a different file with a different shape, so
# no digest, KPI script, or waiver-density alarm could read them uniformly.
#
# ADR 058 D6: "All gate events (block/warn/waiver/downgrade/skip) append to
# one JSONL ledger via a shared lib." This file is that shared lib. Every
# hook that wants to record a signal sources this file and calls
# `ledger_emit`. Nothing downstream (yet) reads the ledger except future
# Wave-E work (the digest, the waiver-density alarm, the KPI script) — this
# task only builds the write side + wires the one consumer named in its
# Done-when (the retry-guard's downgrade path).
#
# ============================================================
# THE CONTRACT
# ============================================================
#
#   ledger_emit <gate> <event> [detail]
#
#     gate    - the hook/gate name emitting the signal (free text, but by
#               convention the same string the gate identifies itself as
#               elsewhere, e.g. "pre-stop-verifier", "product-acceptance-gate").
#     event   - one of: block | warn | waiver | downgrade | skip
#               (not enforced as a hard allow-list — callers may introduce a
#               new event class without a lib change — but these five are
#               the ones ADR 058 D6 names and every caller today uses one of
#               them).
#     detail  - optional free-text detail (a one-line reason, a failure
#               signature, a file path — whatever the caller finds useful
#               downstream). May be empty. May contain quotes, backslashes,
#               newlines, or other JSON-hostile characters; ledger_emit
#               escapes it correctly regardless.
#
#   Appends ONE line of JSON to the ledger:
#     {"ts":"2026-07-03T12:00:00Z","session_id":"abc123","gate":"<gate>",
#      "event":"<event>","detail":"<escaped detail>"}
#
#   NEVER BLOCKS. Every code path in ledger_emit exits/returns 0 (or, more
#   precisely, never causes the calling hook to fail) — a ledger write is
#   observability, not enforcement. A missing state dir, an unwritable file,
#   a busted permission bit: all best-effort, all silently swallowed. This
#   mirrors every other writer-class mechanism in the harness (gate-respect:
#   writer hooks do not block anything).
#
# ============================================================
# SESSION ID
# ============================================================
#
# session_id resolution: $CLAUDE_CODE_SESSION_ID env var if set, else the
# literal string "unknown". (Distinct from stop-hook-retry-guard.sh's
# richer resolution chain — that lib needs a STABLE per-session key for
# counting; this lib only needs an audit-trail label, so the simpler
# contract from this task's own spec is followed verbatim: "session_id
# (from $CLAUDE_CODE_SESSION_ID or 'unknown')".)
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST)
# ============================================================
#
# HARNESS_SELFTEST=1 routes the ledger write to a sandboxed path instead of
# the real production ledger, so every hook's --self-test (this file's own,
# and every future caller's) can exercise ledger_emit without polluting
# ~/.claude/state/signal-ledger.jsonl. Resolution order for the ledger path:
#
#   1. SIGNAL_LEDGER_PATH env var, if set (explicit override — used by
#      self-tests and by any caller that wants a non-default location).
#   2. HARNESS_SELFTEST=1 and SIGNAL_LEDGER_PATH unset -> a sandboxed path
#      under ${TMPDIR:-/tmp}/signal-ledger-selftest/<pid>.jsonl. This is the
#      "sandboxing built in" clause from the task spec: a caller does not
#      need to remember to set SIGNAL_LEDGER_PATH itself when running under
#      HARNESS_SELFTEST=1 — the lib does it automatically.
#   3. Default: $HOME/.claude/state/signal-ledger.jsonl (the real,
#      production, cross-project ledger — matches the $HOME/.claude/state/
#      convention used by every other cross-project state file in the
#      harness, e.g. decision-context-gate.sh's FALLBACK_DIR).
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/lib/signal-ledger.sh"   # from a hooks/*.sh file
#   ledger_emit "my-gate" "warn" "some one-line reason"
#
# Reading back (for digest/KPI consumers, or for manual inspection):
#
#   ledger_tail 20                 # last 20 lines of the resolved ledger
#   ledger_tail 20 "$SOME_PATH"    # last 20 lines of an explicit ledger file

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_SIGNAL_LEDGER_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_SIGNAL_LEDGER_SOURCED=1

# ----------------------------------------------------------------------
# _signal_ledger_path — resolve the ledger file path per the order above.
# Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
_signal_ledger_path() {
  if [[ -n "${SIGNAL_LEDGER_PATH:-}" ]]; then
    printf '%s' "$SIGNAL_LEDGER_PATH"
    return 0
  fi

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/signal-ledger-selftest/%s.jsonl' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi

  printf '%s/.claude/state/signal-ledger.jsonl' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# _signal_ledger_json_escape <string>
#
# Escape a string for embedding inside a JSON double-quoted value, no jq
# dependency. Handles: backslash, double-quote, newline, carriage-return,
# tab, and other control characters (stripped to a space so the resulting
# line stays single-line-JSONL-valid). Printed to stdout WITHOUT the
# surrounding quotes — the caller adds those.
# ----------------------------------------------------------------------
_signal_ledger_json_escape() {
  local s="$1"
  # Order matters: backslash first (so we don't double-escape the
  # backslashes we introduce for the other substitutions).
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Convert real newlines/carriage-returns/tabs to their JSON escape
  # sequences (rather than stripping them) so multi-line detail strings
  # survive round-trip through a JSON parser, while the ledger file itself
  # stays one-object-per-line.
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  # Strip any other ASCII control characters (0x00-0x1F excluding the ones
  # already handled above) that would otherwise produce invalid JSON.
  # POSIX character class covers this without invoking a subprocess per
  # character; anything left over after the class strip is fine.
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# ledger_emit <gate> <event> [detail]
#
# Append one JSON line to the resolved ledger. NEVER fails the calling
# hook — every error path is swallowed. Returns 0 always.
# ----------------------------------------------------------------------
ledger_emit() {
  local gate="${1:-}"
  local event="${2:-}"
  local detail="${3:-}"

  # A signal with no gate name and no event is not useful; still never
  # error — just no-op quietly. (Defensive; real callers always supply
  # both positional args.)
  if [[ -z "$gate" && -z "$event" ]]; then
    return 0
  fi

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  local sid="${CLAUDE_CODE_SESSION_ID:-unknown}"

  local gate_esc event_esc detail_esc sid_esc
  gate_esc="$(_signal_ledger_json_escape "$gate")"
  event_esc="$(_signal_ledger_json_escape "$event")"
  detail_esc="$(_signal_ledger_json_escape "$detail")"
  sid_esc="$(_signal_ledger_json_escape "$sid")"

  local line
  line="$(printf '{"ts":"%s","session_id":"%s","gate":"%s","event":"%s","detail":"%s"}' \
    "$ts" "$sid_esc" "$gate_esc" "$event_esc" "$detail_esc")"

  local path
  path="$(_signal_ledger_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  printf '%s\n' "$line" >> "$path" 2>/dev/null || true

  return 0
}

# ----------------------------------------------------------------------
# ledger_emit_typed <gate> <event> [detail]
#
# NL Observability Program Wave O, task O.1 (specs-o §O.1 deliverable 1).
# ALIAS of ledger_emit — same signature, same 5-field JSONL line, same
# never-blocks contract. NO SCHEMA CHANGE: this frozen line shape
# ({ts,session_id,gate,event,detail}) is unchanged by Wave O. The alias
# exists purely so O.1's new lifecycle/spawn/task/turn-trace call sites can
# read as "typed" emissions (their event value is one of the KNOWN-TYPE
# registry below, not a gate-specific ad-hoc string) without implying any
# behavioral difference from a plain ledger_emit call — callers may use
# either name interchangeably; this file's own self-test exercises both.
# ----------------------------------------------------------------------
ledger_emit_typed() {
  ledger_emit "$@"
}

# ----------------------------------------------------------------------
# KNOWN EVENT TYPES (comment registry — not machine-enforced here; the
# machine-enforced invariant is observability-consumer-map.json + O.6's
# check_obs_consumer_map doctor predicate, per contract C3/law 2).
#
# Pre-Wave-O (ADR 058 D6 + Wave E callers):
#   block | warn | waiver | downgrade | skip | flush | demote | soft-counter
#
# Wave O additions (specs-o §O.0.3 contract C2 — session lifecycle,
# spawn/dispatch, background tasks, turn-traces):
#   session-start | session-stop | session-compact | session-resume |
#   throttle-detected | spawn-dispatched | spawn-concluded |
#   bg-task-started | bg-task-finished | turn-trace
#
# Every one of the 18 types above MUST have >=1 entry in
# observability-consumer-map.json (adapters/claude-code/
# observability-consumer-map.json) naming its real consumer(s) — see that
# file's own header and O.6's check_obs_consumer_map (doctor-enforced).
# A new event type introduced by a future caller is not schema-rejected
# here (ledger_emit never hard-allow-lists event values — see the
# original ADR 058 D6 contract note above), but it SHOULD be added to both
# this comment registry and the consumer map in the same commit, or it
# will show up as "unknown-in-map" (RED) at the next doctor run.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# ledger_tail [<n>] [<path>]
#
# Print the last <n> (default 20) lines of the resolved ledger (or an
# explicit <path> if given). Prints nothing (not an error) if the ledger
# does not exist yet. Never fails.
# ----------------------------------------------------------------------
ledger_tail() {
  local n="${1:-20}"
  local path="${2:-}"
  [[ -z "$path" ]] && path="$(_signal_ledger_path)"
  [[ -f "$path" ]] || return 0
  tail -n "$n" "$path" 2>/dev/null || true
  return 0
}

# ============================================================
# --self-test
# ============================================================
#
# Only runs when this file is EXECUTED directly (not sourced). Sandboxes
# every write via HARNESS_SELFTEST=1 + an explicit SIGNAL_LEDGER_PATH so the
# self-test never touches a real machine's ledger regardless of HOME.
#
# Invocation:
#   bash adapters/claude-code/hooks/lib/signal-ledger.sh --self-test
#
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'slst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  LEDGER="$TMP/ledger.jsonl"
  export SIGNAL_LEDGER_PATH="$LEDGER"
  unset CLAUDE_CODE_SESSION_ID

  # jq is optional; when present, use it to strictly validate each emitted
  # line is well-formed JSON. When absent, fall back to a structural grep
  # check (still exercises the escaping behavior, just less rigorously).
  _valid_json_line() {
    local line="$1"
    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$line" | jq -e . >/dev/null 2>&1
      return $?
    fi
    # Fallback: must start with { and end with } and contain the four keys.
    [[ "$line" == \{*\} ]] || return 1
    printf '%s' "$line" | grep -q '"ts"' || return 1
    printf '%s' "$line" | grep -q '"session_id"' || return 1
    printf '%s' "$line" | grep -q '"gate"' || return 1
    printf '%s' "$line" | grep -q '"event"' || return 1
    return 0
  }

  echo "Scenario 1: each of the five named event kinds appends a valid JSON line"
  rm -f "$LEDGER"
  for ev in block warn waiver downgrade skip; do
    ledger_emit "test-gate" "$ev" "detail for $ev"
  done
  n_lines=$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines" == "5" ]]; then
    pass "five events produced five lines (got $n_lines)"
  else
    fail "expected 5 lines, got $n_lines"
  fi
  all_valid=1
  while IFS= read -r line; do
    _valid_json_line "$line" || all_valid=0
  done < "$LEDGER"
  if [[ "$all_valid" == "1" ]]; then
    pass "every emitted line is valid JSON"
  else
    fail "one or more emitted lines are not valid JSON"
  fi
  if grep -q '"event":"block"' "$LEDGER" && \
     grep -q '"event":"warn"' "$LEDGER" && \
     grep -q '"event":"waiver"' "$LEDGER" && \
     grep -q '"event":"downgrade"' "$LEDGER" && \
     grep -q '"event":"skip"' "$LEDGER"; then
    pass "all five event kinds present verbatim in the ledger"
  else
    fail "one or more event kinds missing from the ledger"
  fi

  echo "Scenario 2: detail with quotes/backslashes/newlines escapes correctly"
  rm -f "$LEDGER"
  ledger_emit "quote-gate" "warn" 'she said "hi" and used a \backslash\ then
a second line'
  line2="$(cat "$LEDGER")"
  if _valid_json_line "$line2"; then
    pass "line with quotes/backslash/newline is still valid JSON"
  else
    fail "line with quotes/backslash/newline is NOT valid JSON: $line2"
  fi
  if command -v jq >/dev/null 2>&1; then
    # Some platforms' jq binary (notably Windows-native jq.exe under Git
    # Bash) writes text-mode output and turns embedded \n into \r\n on the
    # way out. Strip \r before comparing so this assertion checks the
    # actual round-trip content, not a platform-specific jq I/O quirk.
    roundtrip="$(printf '%s' "$line2" | jq -r '.detail' 2>/dev/null | tr -d '\r')"
    expected='she said "hi" and used a \backslash\ then
a second line'
    if [[ "$roundtrip" == "$expected" ]]; then
      pass "detail round-trips through jq to the original string"
    else
      fail "round-trip mismatch: got [$roundtrip]"
    fi
  else
    echo "  (jq unavailable — skipping strict round-trip assertion)"
  fi

  echo "Scenario 3: HARNESS_SELFTEST sandbox honored when SIGNAL_LEDGER_PATH unset"
  (
    unset SIGNAL_LEDGER_PATH
    export HARNESS_SELFTEST=1
    export TMPDIR="$TMP/sandboxed-tmp"
    mkdir -p "$TMPDIR"
    resolved="$(_signal_ledger_path)"
    case "$resolved" in
      "$TMPDIR"/signal-ledger-selftest/*) exit 0 ;;
      *) exit 1 ;;
    esac
  )
  if [[ $? -eq 0 ]]; then
    pass "HARNESS_SELFTEST=1 with no explicit path resolves under TMPDIR sandbox"
  else
    fail "HARNESS_SELFTEST sandbox path resolution did not match expected shape"
  fi
  # Also confirm it never resolves to the real prod path in that mode.
  (
    unset SIGNAL_LEDGER_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_signal_ledger_path)"
    [[ "$resolved" != "$HOME/.claude/state/signal-ledger.jsonl" ]]
  )
  if [[ $? -eq 0 ]]; then
    pass "sandbox path never equals the production ledger path"
  else
    fail "sandbox path incorrectly resolved to the production ledger path"
  fi

  echo "Scenario 4: ledger_tail returns the last n lines"
  rm -f "$LEDGER"
  for i in 1 2 3 4 5; do
    ledger_emit "tail-gate" "skip" "entry-$i"
  done
  tail2="$(ledger_tail 2 "$LEDGER")"
  n_tail_lines=$(printf '%s\n' "$tail2" | grep -c .)
  if [[ "$n_tail_lines" == "2" ]]; then
    pass "ledger_tail 2 returns exactly 2 lines (got $n_tail_lines)"
  else
    fail "expected 2 lines from ledger_tail 2, got $n_tail_lines"
  fi
  if printf '%s' "$tail2" | grep -q 'entry-5' && printf '%s' "$tail2" | grep -q 'entry-4'; then
    pass "ledger_tail returns the MOST RECENT entries (4 and 5)"
  else
    fail "ledger_tail did not return the expected most-recent entries"
  fi

  echo "Scenario 5: missing state dir is auto-created on first emit"
  DEEP="$TMP/does/not/yet/exist/ledger.jsonl"
  [[ -d "$(dirname "$DEEP")" ]] && fail "precondition violated: dir already exists" || true
  (
    export SIGNAL_LEDGER_PATH="$DEEP"
    ledger_emit "mkdir-gate" "block" "first ever write"
  )
  if [[ -f "$DEEP" ]]; then
    pass "missing parent directory chain was auto-created and the file written"
  else
    fail "expected $DEEP to exist after ledger_emit, it does not"
  fi

  echo "Scenario 6: ledger_tail on a non-existent ledger prints nothing and does not error"
  set +e
  out="$(ledger_tail 5 "$TMP/totally-missing-ledger.jsonl" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" == "0" ]] && [[ -z "$out" ]]; then
    pass "ledger_tail on missing file returns exit 0 with empty output"
  else
    fail "expected exit 0 + empty output, got rc=$rc out=[$out]"
  fi

  echo "Scenario 7: ledger_emit never fails the caller even when the path is unwritable"
  # Point at a path whose parent cannot be created (a file standing in for a
  # directory component) — mkdir -p will fail; ledger_emit must still return 0.
  BLOCKER="$TMP/blocker-file"
  : > "$BLOCKER"
  (
    export SIGNAL_LEDGER_PATH="$BLOCKER/subdir/ledger.jsonl"
    set +e
    ledger_emit "unwritable-gate" "warn" "should not crash"
    rc=$?
    set -e
    exit $rc
  )
  if [[ $? -eq 0 ]]; then
    pass "ledger_emit returns 0 even when the target path is unwritable"
  else
    fail "ledger_emit propagated a non-zero exit on an unwritable path"
  fi

  echo "Scenario 8 (Wave O task O.1): ledger_emit_typed is an alias — each new"
  echo "Wave-O event class lands exactly one schema-valid JSONL line"
  rm -f "$LEDGER"
  for ev in session-start session-stop session-compact session-resume \
            throttle-detected spawn-dispatched spawn-concluded \
            bg-task-started bg-task-finished turn-trace; do
    ledger_emit_typed "test-gate-o1" "$ev" "detail for $ev"
  done
  n_lines_o1=$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')
  if [[ "$n_lines_o1" == "10" ]]; then
    pass "ten Wave-O event classes produced ten lines via ledger_emit_typed (got $n_lines_o1)"
  else
    fail "expected 10 lines, got $n_lines_o1"
  fi
  all_valid_o1=1
  while IFS= read -r o1line; do
    _valid_json_line "$o1line" || all_valid_o1=0
  done < "$LEDGER"
  if [[ "$all_valid_o1" == "1" ]]; then
    pass "every ledger_emit_typed line is valid JSON"
  else
    fail "one or more ledger_emit_typed lines are not valid JSON"
  fi
  if grep -q '"event":"turn-trace"' "$LEDGER" && grep -q '"event":"session-start"' "$LEDGER" \
     && grep -q '"event":"spawn-dispatched"' "$LEDGER" && grep -q '"event":"bg-task-started"' "$LEDGER"; then
    pass "representative Wave-O event types present verbatim (turn-trace/session-start/spawn-dispatched/bg-task-started)"
  else
    fail "one or more Wave-O event types missing from the ledger"
  fi

  echo "Scenario 9 (Wave O task O.1): turn-trace detail is a compact JSON string"
  echo "that round-trips through jq (per contract C2)"
  rm -f "$LEDGER"
  TRACE_DETAIL='{"hooks":[{"n":"work-integrity-gate","ms":42,"v":"allow"},{"n":"session-honesty-gate","ms":11,"v":"allow"}],"total_ms":53}'
  ledger_emit_typed "stop-verdict-dispatcher" "turn-trace" "$TRACE_DETAIL"
  TRACE_LINE="$(cat "$LEDGER")"
  if command -v jq >/dev/null 2>&1; then
    inner_valid="$(printf '%s' "$TRACE_LINE" | jq -r '.detail' 2>/dev/null | jq -e . >/dev/null 2>&1 && echo yes || echo no)"
    if [[ "$inner_valid" == "yes" ]]; then
      pass "turn-trace detail round-trips as valid nested JSON through jq"
    else
      fail "turn-trace detail did not round-trip as valid nested JSON"
    fi
    total_ms_rt="$(printf '%s' "$TRACE_LINE" | jq -r '.detail' 2>/dev/null | jq -r '.total_ms' 2>/dev/null)"
    if [[ "$total_ms_rt" == "53" ]]; then
      pass "turn-trace detail.total_ms survives the round-trip (got $total_ms_rt)"
    else
      fail "turn-trace detail.total_ms mismatch (got $total_ms_rt, expected 53)"
    fi
  else
    echo "  (jq unavailable — skipping strict turn-trace round-trip assertion)"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
