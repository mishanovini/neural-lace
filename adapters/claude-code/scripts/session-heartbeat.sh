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
#                               [--session <sid>]
#     Atomically writes/overwrites a session's heartbeat file (schema
#     per C1; see hooks/lib/session-heartbeat-lib.sh's header for the exact
#     JSON shape). NEVER BLOCKS — exit 0 always, on every code path
#     (mirrors ledger_emit / needs-you.sh add's writer-never-blocks
#     contract: a liveness tick is observability, not enforcement). Reads
#     pid ($$), cwd ($PWD), branch (`git branch --show-current` in
#     ${CLAUDE_PROJECT_DIR:-$PWD}), and model from env
#     ($CLAUDE_MODEL/$ANTHROPIC_MODEL) — see the lib's hb_write for the
#     exact resolution. --session <sid> (ADR-061 D2) targets an EXPLICIT
#     session id, overriding the $CLAUDE_CODE_SESSION_ID fallback — the
#     session-resumer's `--event resume` touch attributes to the RESUMED
#     session this way instead of the literal sid "unknown".
#
#   session-heartbeat.sh sweep [--json] [--stale-min <n>]
#     Report-only: lists every heartbeat file's session id + classification
#     (live|stale|throttled|crashed) per hb_classify, using the SAME lib functions
#     §O.3's `od_sessions` will call — the computation lives in
#     session-heartbeat-lib.sh once, shared here and there. Never blocks;
#     exit 0 always (a listing is not a verdict this script enforces).
#
#   session-heartbeat.sh reap [--json] [--reap-min <n>] [--dry-run]
#     Hygiene (O.3 hb-perf2 fork-batching fix, docs/backlog.md
#     HARNESS-PERF-O3-HB): removes heartbeat files for sessions that are
#     DEFINITIVELY dead — both signals (heartbeat last_activity_ts AND the
#     session's own transcript mtime) older than the reap threshold
#     (OBS_HEARTBEAT_REAP_MIN env var, default 1440min = 24h; a missing
#     transcript counts as "old" on that axis too, since a heartbeat with
#     no transcript at all has nothing to be recently active about). A
#     session that is merely stale/crashed-by-the-30min-default (recent,
#     just not currently live) is NOT touched — only genuinely
#     >24h-abandoned entries are removed. This shrinks N for every
#     downstream per-session scan (od_sessions/`nl status`, this script's
#     own `sweep`, harness-doctor.sh's heartbeats-fresh check) and is the
#     hygiene half of the O.3 hb-perf2 fix (the fork-batching half is in
#     hooks/lib/session-heartbeat-lib.sh and observability-derive.sh).
#     Emits one `ledger_emit "session-heartbeat" "reap" <detail>` line per
#     reaped session (session_id set to the REAPED session's own id, so
#     `nl why <that-sid>` — od_why's generic per-session ledger read — can
#     always answer "what happened to this session" even after its
#     heartbeat file is gone). --dry-run reports what WOULD be reaped
#     without deleting or emitting anything. Never blocks; exit 0 always.
#     NOTE: reaping bounds the Q1 board (od_sessions/`nl status`) to
#     recent+live sessions — a session dead >24h correctly drops off
#     "what's running right now" once reaped. This script does not wire
#     its own scheduled invocation (see CALL-SITES below); a cron/digest
#     tick calling this verb periodically is a follow-up, out of this
#     task's 3-file scope.
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
# signal-ledger.sh is best-effort ONLY (used by the `reap` verb to emit an
# observability line per reaped session) — its absence must never abort
# this script, since touch/sweep/reap's own file operations do not depend
# on it at all; `cmd_reap` guards every ledger_emit call with
# `command -v ledger_emit` for exactly this reason.
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/signal-ledger.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/signal-ledger.sh" 2>/dev/null || true
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
  local event="" marker="none" session=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event) event="${2:-}"; shift 2 ;;
      --marker) marker="${2:-none}"; shift 2 ;;
      --session) session="${2:-}"; shift 2 ;;
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

  # ADR-061 D2: explicit --session overrides the env-derived sid (see
  # hb_write's own --session contract in the lib).
  if [[ -n "$session" ]]; then
    hb_write --session "$session" "$event" "$marker" >/dev/null 2>&1 || true
  else
    hb_write "$event" "$marker" >/dev/null 2>&1 || true
  fi
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

# ----------------------------------------------------------------------
# cmd_reap — remove heartbeat files for DEFINITIVELY dead sessions: both
# the heartbeat's own last_activity_ts AND the session's transcript mtime
# older than --reap-min (default $OBS_HEARTBEAT_REAP_MIN, else 1440min =
# 24h). See the file header's "reap" contract section for the full
# rationale (O.3 hb-perf2 fix, docs/backlog.md HARNESS-PERF-O3-HB) and
# the note on why a stale-but-recent (<24h) or live session is never
# touched — this is meaningfully more conservative than hb_classify's own
# 30min staleness window, by design. Never blocks; exit 0 always. A
# missing/empty state dir reaps nothing (not an error).
# ----------------------------------------------------------------------
cmd_reap() {
  local as_json=0 reap_min="${OBS_HEARTBEAT_REAP_MIN:-1440}" dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --reap-min) reap_min="${2:-1440}"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) echo "session-heartbeat.sh reap: unknown flag '$1' (ignored)" >&2; shift ;;
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

  local now_epoch
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"

  local -a reaped=()
  local f sid hb_ts hb_epoch hb_age_min tf t_mtime t_age_min detail

  for f in "${files[@]}"; do
    sid="$(_hb_field "$f" "session_id")"
    [[ -z "$sid" ]] && sid="$(basename "$f" .json)"

    hb_ts="$(_hb_field "$f" "last_activity_ts")"
    hb_epoch="$(_hb_epoch "$hb_ts")"
    if [[ "$hb_epoch" -gt 0 ]]; then
      hb_age_min=$(( (now_epoch - hb_epoch) / 60 ))
    else
      # Unparseable/absent timestamp: cannot prove recency, so treat as
      # "ancient" on this axis (matches hb_is_stale's own "no usable
      # timestamp -> stale" convention) — the transcript check below
      # still independently has to agree before this file is reaped.
      hb_age_min=999999999
    fi
    # Heartbeat itself must be reap-old — a session with a RECENT
    # heartbeat is never reaped regardless of anything else (this is the
    # "stale-but-recent session stays" guarantee).
    [[ "$hb_age_min" -gt "$reap_min" ]] || continue

    tf="$(_hb_find_transcript "$sid")"
    if [[ -n "$tf" && -f "$tf" ]]; then
      t_mtime="$(date -u -r "$tf" +%s 2>/dev/null || stat -c %Y "$tf" 2>/dev/null || stat -f %m "$tf" 2>/dev/null || echo 0)"
      if [[ "$t_mtime" -gt 0 ]]; then
        t_age_min=$(( (now_epoch - t_mtime) / 60 ))
      else
        t_age_min=999999999
      fi
    else
      # No transcript at all for this session id: nothing recent to
      # point to, so "old" on this axis too (a heartbeat with no
      # matching transcript has no basis to be kept alive by).
      t_age_min=999999999
    fi
    # BOTH signals must agree the session is dead — a fresh transcript
    # (e.g. a genuinely still-working mid-turn session whose heartbeat
    # merely hasn't refreshed) rescues the file from reaping, mirroring
    # hb_is_stale's own C1 transcript-mtime join philosophy one level up.
    [[ "$t_age_min" -gt "$reap_min" ]] || continue

    reaped+=("$sid")
    if [[ "$dry_run" != "1" ]]; then
      rm -f "$f" 2>/dev/null || true
      if command -v ledger_emit >/dev/null 2>&1; then
        detail="heartbeat+transcript both >${reap_min}min dead (hb_age=${hb_age_min}min, transcript_age=${t_age_min}min)"
        (
          export CLAUDE_CODE_SESSION_ID="$sid"
          ledger_emit "session-heartbeat" "reap" "$detail"
        ) >/dev/null 2>&1 || true
      fi
    fi
  done

  if [[ "$as_json" == "1" ]]; then
    local out="[" first=1 r
    for r in "${reaped[@]}"; do
      [[ "$first" == "1" ]] && first=0 || out+=","
      out+="\"$(_hb_json_escape "$r")\""
    done
    out+="]"
    printf '%s\n' "$out"
    return 0
  fi

  printf '%d heartbeat(s) reaped (oracle: session-heartbeat reap, threshold %dmin)\n' "${#reaped[@]}" "$reap_min"
  local r
  for r in "${reaped[@]}"; do
    printf '  %s\n' "$r"
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

  echo "Scenario B2: touch --event resume --session <sid> targets the explicit sid, not the ambient env sid (ADR-061 D2 — the resumer's resume-touch attribution fix)"
  (
    export CLAUDE_CODE_SESSION_ID="sess-ambient-watchdog"
    bash "$SCRIPT_DIR/session-heartbeat.sh" touch --event resume --session "sess-resume-target"
  )
  local fb2="$HEARTBEAT_STATE_DIR/sess-resume-target.json"
  if [[ -f "$fb2" ]]; then
    pass "touch --session wrote the heartbeat under the TARGET sid"
  else
    fail "expected $fb2 after touch --event resume --session sess-resume-target"
  fi
  local sid_b2 ev_b2
  sid_b2="$(_hb_field "$fb2" "session_id")"
  ev_b2="$(_hb_field "$fb2" "last_event")"
  if [[ "$sid_b2" == "sess-resume-target" && "$ev_b2" == "resume" ]]; then
    pass "touch --session round-trips session_id=target + last_event=resume"
  else
    fail "expected session_id=sess-resume-target/last_event=resume, got sid='$sid_b2' event='$ev_b2'"
  fi
  if [[ ! -f "$HEARTBEAT_STATE_DIR/sess-ambient-watchdog.json" ]]; then
    pass "touch --session did NOT write under the ambient env sid (no 'unknown'-class misattribution)"
  else
    fail "touch --session leaked a write under the ambient env sid"
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

  echo "Scenario H: reap — a >24h-dead session (no transcript, ancient heartbeat) is REMOVED; a stale-but-recent (<24h) session and a live session are NOT touched (O.3 hb-perf2 fix, docs/backlog.md HARNESS-PERF-O3-HB)"
  local reap_dir="$TMP/hb-reap"
  mkdir -p "$reap_dir"
  local reap_transcripts="$TMP/reap-transcripts"
  mkdir -p "$reap_transcripts"

  # Case 1: definitively dead — ancient heartbeat, no transcript at all
  # for this sid under the sandboxed transcripts root.
  cat > "$reap_dir/sess-reap-dead.json" <<'EOF'
{"schema":1,"session_id":"sess-reap-dead","pid":999999,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF

  # Case 2: stale-but-recent — heartbeat ~2 hours old (well past
  # hb_classify's 30min default staleness window, but comfortably under
  # the 1440min/24h reap threshold) — must survive reap untouched.
  local recent_ts
  recent_ts="$(date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  cat > "$reap_dir/sess-reap-recent.json" <<EOF
{"schema":1,"session_id":"sess-reap-recent","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"${recent_ts}","last_event":"turn-end","marker_state":"none"}
EOF

  # Case 3: live — fresh heartbeat.
  cat > "$reap_dir/sess-reap-live.json" <<EOF
{"schema":1,"session_id":"sess-reap-live","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF

  local reap_ledger="$TMP/reap-ledger.jsonl"
  local reap_out
  reap_out="$(HEARTBEAT_STATE_DIR="$reap_dir" OBS_TRANSCRIPTS_ROOT="$reap_transcripts" SIGNAL_LEDGER_PATH="$reap_ledger" cmd_reap)"

  if [[ ! -f "$reap_dir/sess-reap-dead.json" ]]; then
    pass "reap: a >24h-dead session (no transcript, ancient heartbeat) had its heartbeat file removed"
  else
    fail "reap: sess-reap-dead.json still exists after reap (expected removal)"
  fi
  if [[ -f "$reap_dir/sess-reap-recent.json" ]]; then
    pass "reap: a stale-but-recent (<24h) session's heartbeat file was NOT removed"
  else
    fail "reap: sess-reap-recent.json was incorrectly removed (should survive — under the 24h reap threshold)"
  fi
  if [[ -f "$reap_dir/sess-reap-live.json" ]]; then
    pass "reap: a live session's heartbeat file was NOT removed"
  else
    fail "reap: sess-reap-live.json was incorrectly removed"
  fi
  if printf '%s' "$reap_out" | grep -q "sess-reap-dead"; then
    pass "reap: plain output names the reaped session"
  else
    fail "reap: plain output did not name sess-reap-dead: $reap_out"
  fi
  if printf '%s' "$reap_out" | grep -q "1 heartbeat(s) reaped"; then
    pass "reap: plain output reports exactly 1 reaped (oracle-named count)"
  else
    fail "reap: expected '1 heartbeat(s) reaped' in output: $reap_out"
  fi

  if [[ -f "$reap_ledger" ]] && command -v jq >/dev/null 2>&1; then
    local reap_sid_in_ledger
    reap_sid_in_ledger="$(jq -r 'select(.gate=="session-heartbeat" and .event=="reap") | .session_id' "$reap_ledger" 2>/dev/null | tr -d '\r')"
    if [[ "$reap_sid_in_ledger" == "sess-reap-dead" ]]; then
      pass "reap: emits a ledger 'reap' event with session_id set to the REAPED session (so od_why <that-sid> can surface it — EVERY-SIGNAL-HAS-A-CONSUMER)"
    else
      fail "reap: expected ledger reap event session_id=sess-reap-dead, got '$reap_sid_in_ledger'"
    fi
  else
    echo "  (jq unavailable or ledger not written — skipping ledger-emission assertion)"
  fi

  echo "Scenario I: reap --dry-run reports without deleting; reap --json emits valid JSON; OBS_HEARTBEAT_REAP_MIN override is honored"
  local dry_dir="$TMP/hb-reap-dry"
  mkdir -p "$dry_dir"
  cat > "$dry_dir/sess-reap-dry.json" <<'EOF'
{"schema":1,"session_id":"sess-reap-dry","pid":999999,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  local dry_transcripts="$TMP/reap-dry-transcripts"
  mkdir -p "$dry_transcripts"
  local dry_out
  dry_out="$(HEARTBEAT_STATE_DIR="$dry_dir" OBS_TRANSCRIPTS_ROOT="$dry_transcripts" cmd_reap --dry-run)"
  if [[ -f "$dry_dir/sess-reap-dry.json" ]]; then
    pass "reap --dry-run: heartbeat file NOT deleted"
  else
    fail "reap --dry-run incorrectly deleted the heartbeat file"
  fi
  if printf '%s' "$dry_out" | grep -q "sess-reap-dry"; then
    pass "reap --dry-run: still REPORTS what would be reaped"
  else
    fail "reap --dry-run did not report the would-be-reaped session: $dry_out"
  fi

  local dry_json
  dry_json="$(HEARTBEAT_STATE_DIR="$dry_dir" OBS_TRANSCRIPTS_ROOT="$dry_transcripts" cmd_reap --dry-run --json)"
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$dry_json" | jq -e . >/dev/null 2>&1; then
      pass "reap --json output is valid JSON"
    else
      fail "reap --json output is NOT valid JSON: $dry_json"
    fi
    if printf '%s' "$dry_json" | jq -e 'index("sess-reap-dry") != null' >/dev/null 2>&1; then
      pass "reap --json lists the would-be-reaped session"
    else
      fail "reap --json did not list sess-reap-dry: $dry_json"
    fi
  fi

  # OBS_HEARTBEAT_REAP_MIN override: with a 1-minute threshold, even a
  # 2-hour-old (otherwise "stale-but-recent") heartbeat becomes eligible.
  local override_dir="$TMP/hb-reap-override"
  mkdir -p "$override_dir"
  cat > "$override_dir/sess-reap-override.json" <<EOF
{"schema":1,"session_id":"sess-reap-override","pid":999999,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"${recent_ts}","last_event":"turn-end","marker_state":"none"}
EOF
  local override_transcripts="$TMP/reap-override-transcripts"
  mkdir -p "$override_transcripts"
  HEARTBEAT_STATE_DIR="$override_dir" OBS_TRANSCRIPTS_ROOT="$override_transcripts" OBS_HEARTBEAT_REAP_MIN=1 cmd_reap >/dev/null
  if [[ ! -f "$override_dir/sess-reap-override.json" ]]; then
    pass "reap: OBS_HEARTBEAT_REAP_MIN override is honored (a 2h-old heartbeat reaps under a 1min threshold)"
  else
    fail "reap: OBS_HEARTBEAT_REAP_MIN=1 override did not take effect (file survived)"
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
  reap)
    shift
    cmd_reap "$@"
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
  touch --event <start|turn-end|compact|resume> [--marker <state>] [--session <sid>]
                          Atomically write/refresh a session's heartbeat
                          file (--session targets an explicit sid,
                          overriding $CLAUDE_CODE_SESSION_ID — ADR-061 D2).
                          Never blocks; exit 0 always.
  sweep [--json] [--stale-min <n>]
                          Report-only: list every heartbeat file's
                          classification (live|stale|throttled|crashed) per
                          hooks/lib/session-heartbeat-lib.sh's hb_classify.
  reap [--json] [--reap-min <n>] [--dry-run]
                          Hygiene: remove heartbeat files for sessions
                          definitively dead >24h (both heartbeat AND
                          transcript stale past --reap-min, default
                          OBS_HEARTBEAT_REAP_MIN or 1440min). Emits one
                          ledger "reap" event per removed session.
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
