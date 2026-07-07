#!/bin/bash
# session-heartbeat-lib.sh — shared library: the SINGLE read-side
# implementation of the heartbeat file contract (NL Observability Program
# Wave O, task O.2 — specs-o §O.2, frozen contract C1).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# The observability design sketch's law 1 (DERIVE-DON'T-MAINTAIN) requires
# that "is this session alive/stalled/crashed" be computed from ground
# truth (a liveness file + process/transcript signals), never from
# cooperative self-reporting. `scripts/session-heartbeat.sh` is the WRITE
# side (touch/sweep verbs); THIS file is the READ side — the classification
# rules (hb_is_stale / hb_classify) live here ONCE so both the heartbeat
# script's own `sweep` verb and the future §O.3 derivation lib
# (`od_sessions`) call the identical logic. Two implementations of "is this
# stale" drifting apart is exactly the kind of duplicated-oracle bug
# CANONICAL-COUNTERS-01 exists to prevent.
#
# ============================================================
# THE CONTRACT (frozen, §O.0.3 C1 — do not change the schema)
# ============================================================
#
# Path: ${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}/<session-id>.json
# One file per session. Atomic write (tmp+mv) — this lib does not write
# (that's hb_write's job, called from the script), but every function here
# assumes a file it reads was written atomically and so is never observed
# half-written.
#
#   {"schema":1,"session_id":"...","pid":12345,"cwd":"C:/...",
#    "repo_root":"C:/...","worktree_root":"C:/... or same as repo_root",
#    "branch":"...","model":"...","last_activity_ts":"ISO-8601-UTC",
#    "last_event":"start|turn-end|compact|resume",
#    "marker_state":"DONE|PAUSING|BLOCKED|CONTINUING|none"}
#
# STALENESS IS NEVER WRITTEN — it is always computed on read (law 1):
#   stale = (now - last_activity_ts > OBS_STALE_MIN minutes)
#           AND no fresh transcript mtime for that session
#   crashed = stale AND pid not alive
#
# THE TRANSCRIPT-MTIME JOIN (nl-issues 2026-07-07 mid-turn false-stall
# fix): heartbeats only refresh at Stop (touch --event turn-end), so a
# long-running turn is normal and produces NO new heartbeat write for
# its entire duration — last_activity_ts alone therefore false-positives
# a LIVE mid-turn session as stale/stalled/crashed. hb_is_stale resolves
# this session's transcript (OBS_TRANSCRIPTS_ROOT-aware, same convention
# as observability-derive.sh's _od_find_transcript) and treats a
# transcript mtime within OBS_STALE_MIN of "now" as proof the session is
# still working, overriding the heartbeat-age-alone verdict. This is the
# ONE classification implementation both `session-heartbeat.sh sweep`
# and `od_sessions` call (see WHY THIS EXISTS above) — fixing it here
# fixes both consumers.
#
# HONEST PLATFORM CAVEAT (pid liveness on MSYS/Git-Bash): `_hb_pid_alive`
# uses `kill -0`/`ps -p`, which key off MSYS's own pid table — checking a
# native-Windows pid this way from an MSYS shell is UNRELIABLE (MSYS does
# not reliably see arbitrary Windows PIDs the way it sees its own
# subshells). This lib does NOT attempt a native-Windows liveness check
# (tasklist/wmic) to compensate — instead it leans on the transcript-
# mtime signal ABOVE the pid check in priority: a fresh transcript mtime
# is direct, platform-independent evidence of liveness, so on this
# platform "crashed" only fires when heartbeat AND transcript both agree
# nothing fresh happened, which is the honest, cheaply-available signal
# rather than a pid check this platform cannot make trustworthy.
#
# marker_state is populated by the writer from the last Stop-time scan of
# the final assistant message (same regex family as session-honesty-gate.sh:
# DONE:/PAUSING:/BLOCKED:/CONTINUING:, else "none").
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit override — §O.0.1-3)
# ============================================================
#
# Resolution order for the heartbeat state directory:
#   1. HEARTBEAT_STATE_DIR env var, if set (explicit override — used by
#      self-tests and any caller wanting a non-default location).
#   2. HARNESS_SELFTEST=1 and HEARTBEAT_STATE_DIR unset -> a sandboxed dir
#      under ${TMPDIR:-/tmp}/heartbeat-selftest/<pid>/.
#   3. Default: $HOME/.claude/state/heartbeats — the real, production,
#      cross-project state dir (matches signal-ledger.sh / needs-you.sh's
#      $HOME/.claude/state/ convention).
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/session-heartbeat-lib.sh"
#   f="$(hb_path_for "$session_id")"
#   hb_write "turn-end" "DONE"
#   hb_is_stale "$f" && echo stale
#   hb_classify "$f"   # -> live | stale | crashed | missing

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_SESSION_HEARTBEAT_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_SESSION_HEARTBEAT_LIB_SOURCED=1

# Default staleness threshold in minutes (overridable per-call via the
# second arg to hb_is_stale/hb_classify, or globally via OBS_STALE_MIN).
: "${OBS_STALE_MIN:=30}"

# ----------------------------------------------------------------------
# hb_state_dir — resolve the heartbeat state directory per the order above.
# Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
hb_state_dir() {
  if [[ -n "${HEARTBEAT_STATE_DIR:-}" ]]; then
    printf '%s' "$HEARTBEAT_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/heartbeat-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/heartbeats' "${HOME:-$PWD}"
  return 0
}

# ----------------------------------------------------------------------
# hb_path_for <session-id> — print the resolved heartbeat file path for a
# given session id. Never fails. Empty <session-id> resolves under the
# literal "unknown" file (mirrors signal-ledger.sh's session_id fallback),
# so a malformed caller still writes/reads SOMEWHERE deterministic rather
# than silently no-op-ing.
# ----------------------------------------------------------------------
hb_path_for() {
  local sid="${1:-unknown}"
  printf '%s/%s.json' "$(hb_state_dir)" "$sid"
}

# ----------------------------------------------------------------------
# _hb_json_escape <string> — same technique as signal-ledger.sh's escaper
# (no jq dependency for the write path; jq IS used for reads when present).
# ----------------------------------------------------------------------
_hb_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# hb_write <event> [marker] — build the C1 JSON object for THIS process's
# session and atomically write it (tmp+mv) to hb_path_for(session_id).
# NEVER blocks the caller: every failure path is swallowed, exit 0 always
# (mirrors ledger_emit's writer-never-blocks contract). Session id comes
# from $CLAUDE_CODE_SESSION_ID (or "unknown", same fallback as
# signal-ledger.sh). Prints the resolved path to stdout on success.
#
#   event  - one of start|turn-end|compact|resume (not enforced as a hard
#            allow-list here — the writer script validates against the
#            allowed verb set before calling this; this lib stores
#            whatever string it is given so a future event class doesn't
#            require a lib change).
#   marker - DONE|PAUSING|BLOCKED|CONTINUING|none (defaults to "none" when
#            omitted or empty).
# ----------------------------------------------------------------------
hb_write() {
  local event="${1:-}"
  local marker="${2:-none}"
  [[ -n "$marker" ]] || marker="none"

  local sid="${CLAUDE_CODE_SESSION_ID:-unknown}"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  local pid="$$"
  local cwd="${PWD:-}"

  local repo_root="" worktree_root=""
  # nl-paths.sh, if reachable relative to this lib file, gives the honest
  # repo-root / main-checkout resolution; best-effort only — never fail
  # hb_write over a missing sibling file.
  local libdir
  libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  if [[ -n "$libdir" && -f "$libdir/nl-paths.sh" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$libdir/nl-paths.sh" 2>/dev/null || true
  fi
  if command -v nl_repo_root >/dev/null 2>&1; then
    worktree_root="$(nl_repo_root 2>/dev/null || true)"
  fi
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    repo_root="$(nl_main_checkout_root 2>/dev/null || true)"
  fi
  [[ -n "$worktree_root" ]] || worktree_root="$cwd"
  [[ -n "$repo_root" ]] || repo_root="$worktree_root"

  local branch=""
  branch="$(cd "${CLAUDE_PROJECT_DIR:-$cwd}" 2>/dev/null && git branch --show-current 2>/dev/null || true)"

  local model="${CLAUDE_MODEL:-${ANTHROPIC_MODEL:-unknown}}"

  local sid_esc cwd_esc repo_esc wt_esc branch_esc model_esc event_esc marker_esc
  sid_esc="$(_hb_json_escape "$sid")"
  cwd_esc="$(_hb_json_escape "$cwd")"
  repo_esc="$(_hb_json_escape "$repo_root")"
  wt_esc="$(_hb_json_escape "$worktree_root")"
  branch_esc="$(_hb_json_escape "$branch")"
  model_esc="$(_hb_json_escape "$model")"
  event_esc="$(_hb_json_escape "$event")"
  marker_esc="$(_hb_json_escape "$marker")"

  local json
  json="$(printf '{"schema":1,"session_id":"%s","pid":%s,"cwd":"%s","repo_root":"%s","worktree_root":"%s","branch":"%s","model":"%s","last_activity_ts":"%s","last_event":"%s","marker_state":"%s"}' \
    "$sid_esc" "$pid" "$cwd_esc" "$repo_esc" "$wt_esc" "$branch_esc" "$model_esc" "$ts" "$event_esc" "$marker_esc")"

  local path dir tmp
  path="$(hb_path_for "$sid")"
  dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || { return 0; }
  tmp="$(mktemp "${path}.XXXXXX" 2>/dev/null)" || { return 0; }
  printf '%s\n' "$json" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv "$tmp" "$path" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }

  printf '%s' "$path"
  return 0
}

# ----------------------------------------------------------------------
# _hb_field <file> <field> — extract one top-level string/number field
# from a heartbeat JSON file. Uses jq when present, falls back to a
# grep/sed extraction (still correct for this lib's own flat-JSON writer
# output, which never nests or contains embedded braces in values other
# than via the same escaping _hb_json_escape guarantees). Prints empty on
# any failure; never errors.
# ----------------------------------------------------------------------
_hb_field() {
  local file="$1" field="$2"
  [[ -f "$file" ]] || { printf ''; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' "$file" 2>/dev/null | tr -d '\r'
    return 0
  fi
  # Fallback: grep the "field":"value" or "field":value pair out of the
  # single-line JSON object. Handles both string and numeric fields.
  local line
  line="$(cat "$file" 2>/dev/null | tr -d '\r')"
  printf '%s' "$line" | sed -nE "s/.*\"${field}\":\"?([^\",}]*)\"?.*/\1/p" | head -1
}

# ----------------------------------------------------------------------
# _hb_epoch <iso-ts> — best-effort seconds-since-epoch for an ISO-8601 UTC
# timestamp (GNU + BSD date), same technique as needs-you.sh's _ny_epoch.
# Prints 0 on total failure (never errors the caller).
# ----------------------------------------------------------------------
_hb_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null && return 0
  echo 0
}

# ----------------------------------------------------------------------
# _hb_pid_alive <pid> — best-effort liveness check, cross-platform. `kill
# -0` works on POSIX; on Git-Bash/MSYS (Windows) PIDs are the MSYS
# subshell's own numbering and `kill -0` against a foreign real PID is
# UNRELIABLE — this lib cannot prove a native-Windows pid live or dead
# from an MSYS shell with any confidence (`kill -0`/`ps -p` both key off
# MSYS's own pid table, which does not include arbitrary Windows PIDs the
# way it does its own subshells). This is why `hb_is_stale`'s transcript-
# mtime signal (below) is preferred over the pid check wherever both are
# available: a fresh transcript mtime is direct, platform-independent
# evidence the session is still writing, whereas `_hb_pid_alive` on this
# platform can only be trusted to correctly detect a pid this same MSYS
# tree spawned (see the self-test's "just-exited subshell" scenario,
# which is exactly that trustworthy case). Treats an empty/zero/
# non-numeric pid as "not alive" (a heartbeat with no usable pid can
# never be proven live, so it degrades to stale-eligible rather than
# silently claiming liveness forever).
# ----------------------------------------------------------------------
_hb_pid_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ "$pid" -gt 0 ]] || return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  if command -v ps >/dev/null 2>&1; then
    ps -p "$pid" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# ----------------------------------------------------------------------
# _hb_transcripts_dir — same resolution convention as
# observability-derive.sh's _od_transcripts_dir (OBS_TRANSCRIPTS_ROOT
# override, else the real per-user transcripts root), duplicated locally
# (single-file portability: this lib is sourced BY observability-
# derive.sh, not the other way around, and must not assume a sibling is
# present — see file header). Frozen contract: specs-o §O.0.1-3 names
# OBS_TRANSCRIPTS_ROOT as the one sandboxing var for every transcript
# reader in this wave, so both libs honor the identical variable.
# ----------------------------------------------------------------------
_hb_transcripts_dir() {
  if [[ -n "${OBS_TRANSCRIPTS_ROOT:-}" ]]; then
    printf '%s' "$OBS_TRANSCRIPTS_ROOT"
    return 0
  fi
  printf '%s/.claude/projects' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _hb_find_transcript <session-id> — locate the transcript JSONL file for
# a session id anywhere under the transcripts dir (real layout nests by
# sanitized-cwd; self-test/fixture layout is flat) — same technique as
# observability-derive.sh's _od_find_transcript. Prints the first match
# or empty. Never errors.
# ----------------------------------------------------------------------
_hb_find_transcript() {
  local sid="$1" dir
  dir="$(_hb_transcripts_dir)"
  [[ -n "$sid" && -d "$dir" ]] || { printf ''; return 0; }
  find "$dir" -maxdepth 4 -type f -name "${sid}.jsonl" 2>/dev/null | head -n1
}

# ----------------------------------------------------------------------
# _hb_transcript_fresh_min <session-id> — prints the transcript's age in
# minutes (mtime vs now), or empty if no transcript is found for this
# session id. Never errors.
# ----------------------------------------------------------------------
_hb_transcript_fresh_min() {
  local sid="$1" tf mtime now_epoch
  tf="$(_hb_find_transcript "$sid")"
  [[ -n "$tf" && -f "$tf" ]] || { printf ''; return 0; }
  mtime="$(date -u -r "$tf" +%s 2>/dev/null || stat -c %Y "$tf" 2>/dev/null || stat -f %m "$tf" 2>/dev/null || echo 0)"
  [[ "$mtime" -gt 0 ]] || { printf ''; return 0; }
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  printf '%d' $(( (now_epoch - mtime) / 60 ))
}

# ----------------------------------------------------------------------
# hb_is_stale <file> [stale-min] — exit 0 (true) if the heartbeat file's
# last_activity_ts is older than <stale-min> (default $OBS_STALE_MIN,
# else 30) minutes ago AND there is no fresher transcript activity for
# this session (C1's actual read-side contract: "stale = last_activity_ts
# old AND no fresh transcript mtime for that session"). A missing file
# is treated as stale (exit 0) — there is nothing fresher to report.
#
# WHY THE TRANSCRIPT JOIN (nl-issues 2026-07-07 mid-turn false-stall):
# heartbeats only refresh at Stop (`touch --event turn-end`) — a long
# tool-heavy turn can run well past OBS_STALE_MIN with NO new heartbeat
# write even though the session is fully live, so last_activity_ts alone
# false-positives that session as stale/stalled/crashed mid-turn. The
# session's own transcript JSONL, however, is appended to continuously
# during a turn (every tool_use/hook_progress line), so a fresh
# transcript mtime is direct evidence of "still working" independent of
# the heartbeat cadence. A session is genuinely stale only when BOTH
# signals agree nothing fresh has happened.
#
# Never errors.
# ----------------------------------------------------------------------
hb_is_stale() {
  local file="$1"
  local stale_min="${2:-$OBS_STALE_MIN}"
  [[ -f "$file" ]] || return 0

  local ts epoch now_epoch age_min
  ts="$(_hb_field "$file" "last_activity_ts")"
  [[ -n "$ts" ]] || return 0
  epoch="$(_hb_epoch "$ts")"
  [[ "$epoch" -gt 0 ]] || return 0
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  age_min=$(( (now_epoch - epoch) / 60 ))
  [[ "$age_min" -gt "$stale_min" ]] || return 1

  # Heartbeat says old — before declaring stale, check for a fresher
  # transcript. A transcript mtime younger than stale_min means the
  # session is mid-turn (heartbeats only refresh at Stop) and NOT stale,
  # regardless of how old last_activity_ts has become.
  local sid transcript_age_min
  sid="$(_hb_field "$file" "session_id")"
  if [[ -n "$sid" ]]; then
    transcript_age_min="$(_hb_transcript_fresh_min "$sid")"
    if [[ -n "$transcript_age_min" ]] && [[ "$transcript_age_min" -le "$stale_min" ]]; then
      return 1
    fi
  fi
  return 0
}

# ----------------------------------------------------------------------
# hb_classify <file> [stale-min] — print one of: live | stale | crashed |
# missing. Never errors, always prints exactly one word.
#
#   missing  - file does not exist.
#   crashed  - stale (per hb_is_stale) AND the recorded pid is not alive.
#   stale    - stale but the pid IS still alive (e.g. a hung/throttled
#              process, or a pid reused by an unrelated process — the
#              distinction the sketch's "stalled" state maps onto).
#   live     - not stale.
# ----------------------------------------------------------------------
hb_classify() {
  local file="$1"
  local stale_min="${2:-$OBS_STALE_MIN}"

  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return 0
  fi

  if hb_is_stale "$file" "$stale_min"; then
    local pid
    pid="$(_hb_field "$file" "pid")"
    if _hb_pid_alive "$pid"; then
      printf 'stale'
    else
      printf 'crashed'
    fi
    return 0
  fi

  printf 'live'
  return 0
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'hblst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$TMP/hb"
  mkdir -p "$HEARTBEAT_STATE_DIR"
  unset CLAUDE_CODE_SESSION_ID

  echo "Scenario 1: hb_path_for resolves under the sandboxed state dir"
  p="$(hb_path_for "sess-abc")"
  if [[ "$p" == "$HEARTBEAT_STATE_DIR/sess-abc.json" ]]; then
    pass "hb_path_for composes state-dir + session-id + .json"
  else
    fail "expected $HEARTBEAT_STATE_DIR/sess-abc.json, got $p"
  fi

  echo "Scenario 2: hb_write produces jq-valid schema"
  CLAUDE_CODE_SESSION_ID="sess-write-1" hb_write "start" "none" >/dev/null
  wf="$HEARTBEAT_STATE_DIR/sess-write-1.json"
  if [[ -f "$wf" ]]; then
    pass "hb_write created the heartbeat file"
  else
    fail "hb_write did not create $wf"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$wf" >/dev/null 2>&1; then
      pass "written heartbeat file is valid JSON (jq)"
    else
      fail "written heartbeat file is NOT valid JSON"
    fi
    schema_v="$(jq -r '.schema' "$wf" 2>/dev/null | tr -d '\r')"
    sid_v="$(jq -r '.session_id' "$wf" 2>/dev/null | tr -d '\r')"
    event_v="$(jq -r '.last_event' "$wf" 2>/dev/null | tr -d '\r')"
    marker_v="$(jq -r '.marker_state' "$wf" 2>/dev/null | tr -d '\r')"
    if [[ "$schema_v" == "1" && "$sid_v" == "sess-write-1" && "$event_v" == "start" && "$marker_v" == "none" ]]; then
      pass "schema fields round-trip correctly (schema=1, session_id, last_event, marker_state)"
    else
      fail "field mismatch: schema=$schema_v sid=$sid_v event=$event_v marker=$marker_v"
    fi
  else
    grep -q '"schema":1' "$wf" && pass "schema field present (grep fallback, jq unavailable)" || fail "schema field missing (grep fallback)"
  fi

  echo "Scenario 3: staleness math — old fixture ts is stale, fresh ts is live"
  cat > "$HEARTBEAT_STATE_DIR/sess-old.json" <<'EOF'
{"schema":1,"session_id":"sess-old","pid":999999,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"DONE"}
EOF
  if hb_is_stale "$HEARTBEAT_STATE_DIR/sess-old.json" 30; then
    pass "hb_is_stale: an ancient timestamp (2020) is classified stale"
  else
    fail "hb_is_stale: ancient timestamp was NOT classified stale"
  fi

  fresh_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  cat > "$HEARTBEAT_STATE_DIR/sess-fresh.json" <<EOF
{"schema":1,"session_id":"sess-fresh","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$fresh_ts","last_event":"turn-end","marker_state":"DONE"}
EOF
  if hb_is_stale "$HEARTBEAT_STATE_DIR/sess-fresh.json" 30; then
    fail "hb_is_stale: a just-now timestamp was incorrectly classified stale"
  else
    pass "hb_is_stale: a just-now timestamp is classified NOT stale (live)"
  fi

  echo "Scenario 4: hb_classify — crashed = stale + dead pid"
  # A just-exited subshell's pid is guaranteed dead the instant it returns.
  dead_pid=""
  ( : ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null
  # Give the OS a moment to reap; on some platforms the pid may still show
  # briefly, but kill -0 on an already-reaped bash subshell pid reliably
  # fails on every platform this harness targets (Windows/Git-Bash, Linux).
  cat > "$HEARTBEAT_STATE_DIR/sess-crashed.json" <<EOF
{"schema":1,"session_id":"sess-crashed","pid":$dead_pid,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  cls="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-crashed.json" 30)"
  if [[ "$cls" == "crashed" ]]; then
    pass "hb_classify: stale + dead pid (just-exited subshell) -> crashed"
  else
    fail "hb_classify: expected 'crashed', got '$cls'"
  fi

  echo "Scenario 5: hb_classify — stale + alive pid -> stale (not crashed)"
  cat > "$HEARTBEAT_STATE_DIR/sess-stalled.json" <<EOF
{"schema":1,"session_id":"sess-stalled","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
  cls2="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-stalled.json" 30)"
  if [[ "$cls2" == "stale" ]]; then
    pass "hb_classify: stale + alive pid (this test's own \$\$) -> stale"
  else
    fail "hb_classify: expected 'stale', got '$cls2'"
  fi

  echo "Scenario 6: hb_classify — fresh file -> live; missing file -> missing"
  cls3="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-fresh.json" 30)"
  if [[ "$cls3" == "live" ]]; then
    pass "hb_classify: fresh timestamp -> live"
  else
    fail "hb_classify: expected 'live', got '$cls3'"
  fi
  cls4="$(hb_classify "$HEARTBEAT_STATE_DIR/does-not-exist.json" 30)"
  if [[ "$cls4" == "missing" ]]; then
    pass "hb_classify: nonexistent file -> missing"
  else
    fail "hb_classify: expected 'missing', got '$cls4'"
  fi

  echo "Scenario 6b: heartbeat-stale-but-transcript-fresh -> working (nl-issues 2026-07-07 mid-turn false-stall fix)"
  (
    export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts"
    mkdir -p "$OBS_TRANSCRIPTS_ROOT"
    # A heartbeat whose last_activity_ts is old (mimics a long tool-heavy
    # turn where no Stop-time touch has happened yet) but whose pid IS
    # this test's own $$ (alive) and whose transcript was just written —
    # the mid-turn-false-stall shape: heartbeat-old, transcript-fresh.
    cat > "$HEARTBEAT_STATE_DIR/sess-midturn.json" <<EOF
{"schema":1,"session_id":"sess-midturn","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-midturn.jsonl"
    if hb_is_stale "$HEARTBEAT_STATE_DIR/sess-midturn.json" 30; then
      exit 1
    fi
    cls="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-midturn.json" 30)"
    [[ "$cls" == "live" ]] || exit 1
    exit 0
  )
  if [[ $? -eq 0 ]]; then
    pass "hb_is_stale/hb_classify: old heartbeat + fresh transcript mtime -> NOT stale (live/working), not stalled/crashed"
  else
    fail "hb_is_stale/hb_classify: fresh transcript did not override a stale heartbeat timestamp"
  fi

  echo "Scenario 6c: dead-pid + stale-transcript (or no transcript) -> crashed, UNCHANGED by the transcript join"
  (
    export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts-empty"
    mkdir -p "$OBS_TRANSCRIPTS_ROOT"
    dead_pid=""
    ( : ) & dead_pid=$!
    wait "$dead_pid" 2>/dev/null
    cat > "$HEARTBEAT_STATE_DIR/sess-crashed2.json" <<EOF
{"schema":1,"session_id":"sess-crashed2","pid":$dead_pid,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    # No transcript file written for sess-crashed2 under this OBS_TRANSCRIPTS_ROOT
    # (or an equally stale one would also not save it) — the dead-pid +
    # no-fresh-transcript case must still classify crashed, exactly as
    # before this fix.
    cls="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-crashed2.json" 30)"
    [[ "$cls" == "crashed" ]] || exit 1
    exit 0
  )
  if [[ $? -eq 0 ]]; then
    pass "hb_classify: dead pid + no fresh transcript -> crashed (unchanged by the transcript-mtime join)"
  else
    fail "hb_classify: dead-pid+stale-transcript case regressed away from 'crashed'"
  fi

  echo "Scenario 7: hb_write never blocks even on an unwritable target"
  BLOCKER="$TMP/blocker-file"
  : > "$BLOCKER"
  (
    export HEARTBEAT_STATE_DIR="$BLOCKER/subdir"
    export CLAUDE_CODE_SESSION_ID="sess-unwritable"
    set +e
    hb_write "start" "none" >/dev/null
    rc=$?
    set -e
    exit $rc
  )
  if [[ $? -eq 0 ]]; then
    pass "hb_write returns 0 even when the target directory cannot be created"
  else
    fail "hb_write propagated a non-zero exit on an unwritable path"
  fi

  echo "Scenario 8: HARNESS_SELFTEST sandbox honored when HEARTBEAT_STATE_DIR unset"
  (
    unset HEARTBEAT_STATE_DIR
    export HARNESS_SELFTEST=1
    export TMPDIR="$TMP/sandboxed-tmp"
    mkdir -p "$TMPDIR"
    resolved="$(hb_state_dir)"
    case "$resolved" in
      "$TMPDIR"/heartbeat-selftest/*) exit 0 ;;
      *) exit 1 ;;
    esac
  )
  if [[ $? -eq 0 ]]; then
    pass "HARNESS_SELFTEST=1 with no explicit dir resolves under TMPDIR sandbox"
  else
    fail "HARNESS_SELFTEST sandbox path resolution did not match expected shape"
  fi
  (
    unset HEARTBEAT_STATE_DIR
    export HARNESS_SELFTEST=1
    resolved="$(hb_state_dir)"
    [[ "$resolved" != "$HOME/.claude/state/heartbeats" ]]
  )
  if [[ $? -eq 0 ]]; then
    pass "sandbox path never equals the production heartbeat state dir"
  else
    fail "sandbox path incorrectly resolved to the production state dir"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
