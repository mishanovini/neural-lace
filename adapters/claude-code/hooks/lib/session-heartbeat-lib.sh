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
# _hb_transcript_fresh_min <session-id> [transcript-path] [now-epoch] —
# prints the transcript's age in minutes (mtime vs now), or empty if no
# transcript is found for this session id. Never errors.
#
# OPTIONAL 2ND ARG (O.3 hb-perf fix — see file header "WHY THIS EXISTS"
# for the sibling-file duplication this closes): when the caller already
# knows the transcript path (od_sessions resolves it via its own O(1)
# _OD_TRANSCRIPT_INDEX, built once per `nl status` call instead of a
# full-tree `find` PER SESSION), it can pass that path directly and this
# function skips _hb_find_transcript's own full-tree find entirely.
# Distinguished by ARGUMENT COUNT, not by the value being non-empty: an
# explicitly-passed EMPTY string ("no transcript exists for this sid",
# per the caller's own index) is honored as-is and must NOT fall back to
# a local find (that find would re-scan the whole tree only to confirm
# the same absence the caller's index already established). Omit the
# arg entirely for unchanged standalone behavior (still correct, just
# resolves its own path via _hb_find_transcript) — this is what
# session-heartbeat.sh's `sweep` verb and harness-doctor.sh's
# heartbeats-fresh check both do today, and continue to do unmodified.
#
# OPTIONAL 3RD ARG <now-epoch> (O.3 hb-perf2 fork-batching fix): a caller
# looping over many sessions in one process (od_sessions) computes "now"
# via ONE `date -u +%s` call up front and can pass it here, skipping this
# function's own independent `date` subprocess for "now" — see hb_is_stale
# and hb_classify's own headers for the full fork-elimination rationale.
# Distinguished by argument count (requires the 2nd arg to also be
# supplied, even if empty, to reach position 3). Omit for unchanged
# standalone behavior (still correct, just forks its own `date -u +%s`).
# ----------------------------------------------------------------------
_hb_transcript_fresh_min() {
  local sid="$1" tf mtime now_epoch
  if [[ $# -ge 2 ]]; then
    tf="$2"
  else
    tf="$(_hb_find_transcript "$sid")"
  fi
  [[ -n "$tf" && -f "$tf" ]] || { printf ''; return 0; }
  mtime="$(date -u -r "$tf" +%s 2>/dev/null || stat -c %Y "$tf" 2>/dev/null || stat -f %m "$tf" 2>/dev/null || echo 0)"
  [[ "$mtime" -gt 0 ]] || { printf ''; return 0; }
  if [[ $# -ge 3 ]]; then
    now_epoch="$3"
  else
    now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  fi
  printf '%d' $(( (now_epoch - mtime) / 60 ))
}

# ----------------------------------------------------------------------
# hb_is_stale <file> [stale-min] [transcript-path] [session-id]
#             [last-activity-epoch] [now-epoch]
#   — exit 0 (true) if the heartbeat file's last_activity_ts is older
# than <stale-min> (default $OBS_STALE_MIN, else 30) minutes ago AND
# there is no fresher transcript activity for this session (C1's actual
# read-side contract: "stale = last_activity_ts old AND no fresh
# transcript mtime for that session"). A missing file is treated as
# stale (exit 0) — there is nothing fresher to report.
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
# OPTIONAL 3RD ARG <transcript-path> (O.3 hb-perf fix): threaded straight
# through to _hb_transcript_fresh_min — see that function's header for
# the argument-count-vs-value distinction (an explicit empty string is
# honored, not treated as "not passed"). Omit for unchanged behavior.
#
# OPTIONAL 4TH-6TH ARGS <session-id> <last-activity-epoch> <now-epoch>
# (O.3 hb-perf2 fork-batching fix — docs/backlog.md HARNESS-PERF-O3-HB):
# profiling proved the dominant residual `nl status` cost was per-session
# subprocess forks INSIDE this function and hb_classify — od_sessions
# already extracts marker/branch/worktree/cwd/last_activity_ts from every
# heartbeat file in ONE BATCHED jq call (see observability-derive.sh's
# _od_heartbeat_batch_build) and already knows the session id (its own
# loop variable), yet this function used to re-derive BOTH via its own
# `_hb_field` calls (2 more jq subprocess forks per session) and convert
# the timestamp to an epoch via its own `_hb_epoch` (`date`) call, on top
# of `date -u +%s` for "now" — all fully redundant with data/values the
# caller already has. When supplied:
#   - <session-id>: skips this function's own `_hb_field "$file"
#     "session_id"` call (used only to resolve the transcript when no
#     transcript-path was already given/known).
#   - <last-activity-epoch>: an ALREADY-CONVERTED epoch (seconds since
#     the Unix epoch — NOT the ISO-8601 string; od_sessions converts once
#     per session via jq's `fromdateiso8601` inside its own single
#     batched jq call, never via a bash `date` subprocess), skipping this
#     function's own `_hb_field` + `_hb_epoch` (`date -d`) calls
#     entirely. 0 means "unparseable/absent" (same convention `_hb_epoch`
#     itself uses on failure) and is honored as-is (falls through to the
#     same "no usable timestamp -> stale" verdict `_hb_epoch` returning 0
#     already produced before this fix).
#   - <now-epoch>: computed ONCE per od_sessions call (a single
#     `date -u +%s`, not one per session) and threaded through here (and
#     on to `_hb_transcript_fresh_min`'s own 3rd arg) instead of this
#     function calling `date -u +%s` again for every session.
# Distinguished by ARGUMENT COUNT (same convention as the transcript-path
# arg): to reach position 5 or 6 the caller must also supply position 4
# (and 5), even with an intentionally "empty"/0 value — od_sessions
# always has all three together, so this is never a hardship in
# practice. Omit all three for unchanged standalone behavior (still
# correct, just re-derives everything itself) — this is what
# session-heartbeat.sh's `sweep` verb and harness-doctor.sh's
# heartbeats-fresh check both do today (2-arg calls), and continue to do
# unmodified: neither passes a 4th+ arg, so neither is affected by this
# change in any way.
#
# Never errors.
# ----------------------------------------------------------------------
hb_is_stale() {
  local file="$1"
  local stale_min="${2:-$OBS_STALE_MIN}"
  local transcript_path_given=0 transcript_path=""
  local sid_given=0 sid_pre=""
  local epoch_given=0 epoch_pre=""
  local now_given=0 now_pre=""
  if [[ $# -ge 3 ]]; then
    transcript_path_given=1
    transcript_path="$3"
  fi
  if [[ $# -ge 4 ]]; then
    sid_given=1
    sid_pre="$4"
  fi
  if [[ $# -ge 5 ]]; then
    epoch_given=1
    epoch_pre="$5"
  fi
  if [[ $# -ge 6 ]]; then
    now_given=1
    now_pre="$6"
  fi
  [[ -f "$file" ]] || return 0

  local epoch now_epoch age_min
  if [[ "$epoch_given" == "1" ]]; then
    epoch="$epoch_pre"
  else
    local ts
    ts="$(_hb_field "$file" "last_activity_ts")"
    [[ -n "$ts" ]] || return 0
    epoch="$(_hb_epoch "$ts")"
  fi
  [[ -n "$epoch" ]] || epoch=0
  [[ "$epoch" -gt 0 ]] || return 0

  if [[ "$now_given" == "1" ]]; then
    now_epoch="$now_pre"
  else
    now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  fi
  age_min=$(( (now_epoch - epoch) / 60 ))
  [[ "$age_min" -gt "$stale_min" ]] || return 1

  # Heartbeat says old — before declaring stale, check for a fresher
  # transcript. A transcript mtime younger than stale_min means the
  # session is mid-turn (heartbeats only refresh at Stop) and NOT stale,
  # regardless of how old last_activity_ts has become.
  local sid transcript_age_min
  if [[ "$sid_given" == "1" ]]; then
    sid="$sid_pre"
  else
    sid="$(_hb_field "$file" "session_id")"
  fi
  if [[ -n "$sid" ]]; then
    if [[ "$transcript_path_given" == "1" ]]; then
      if [[ "$now_given" == "1" ]]; then
        transcript_age_min="$(_hb_transcript_fresh_min "$sid" "$transcript_path" "$now_epoch")"
      else
        transcript_age_min="$(_hb_transcript_fresh_min "$sid" "$transcript_path")"
      fi
    else
      transcript_age_min="$(_hb_transcript_fresh_min "$sid")"
    fi
    if [[ -n "$transcript_age_min" ]] && [[ "$transcript_age_min" -le "$stale_min" ]]; then
      return 1
    fi
  fi
  return 0
}

# ----------------------------------------------------------------------
# hb_classify <file> [stale-min] [transcript-path] [session-id]
#             [last-activity-epoch] [now-epoch] [pid]
#   — print one of: live | stale | crashed | missing. Never errors,
# always prints exactly one word.
#
#   missing  - file does not exist.
#   crashed  - stale (per hb_is_stale) AND the recorded pid is not alive.
#   stale    - stale but the pid IS still alive (e.g. a hung/throttled
#              process, or a pid reused by an unrelated process — the
#              distinction the sketch's "stalled" state maps onto).
#   live     - not stale.
#
# NOTE this function ALREADY only pays the `_hb_pid_alive` (`kill -0`)
# cost for the stale-candidate subset, never for every session: the pid
# check below is reached only when `hb_is_stale` returns true (rc 0), and
# hb_is_stale's own transcript-mtime join (C1) already resolves a
# heartbeat-stale-but-transcript-fresh session straight to "not stale"
# (rc 1) before this function ever looks at pid/kill at all. So the
# O.3-hb-perf2 fork-batching fix below (passing pre-resolved fields
# through) is what shrinks the PER-SESSION jq/date cost; the kill-only-
# for-stale-candidates property was already true and is unchanged here.
#
# OPTIONAL 3RD ARG <transcript-path> (O.3 hb-perf fix — eliminates the
# redundant per-session full-tree `find` this lib used to run
# independently of observability-derive.sh's own od_sessions index; see
# _hb_transcript_fresh_min's header for the full rationale): a caller
# that already resolved this session's transcript path (od_sessions, via
# its O(1) _OD_TRANSCRIPT_INDEX built once per `nl status` call) passes
# it here and hb_is_stale/_hb_transcript_fresh_min use it directly
# instead of re-deriving it via _hb_find_transcript. Distinguished by
# ARGUMENT COUNT: pass "" explicitly when the caller's index already
# proved no transcript exists for this sid (honored as-is, no fallback
# find). Omit the arg entirely for unchanged standalone behavior — every
# OTHER caller (session-heartbeat.sh's `sweep` verb, harness-doctor.sh's
# heartbeats-fresh check) calls this with 1-2 args and is unaffected;
# this does NOT change WHAT hb_classify decides, only HOW it finds the
# transcript when a caller already knows the path.
#
# OPTIONAL 4TH-7TH ARGS <session-id> <last-activity-epoch> <now-epoch>
# <pid> (O.3 hb-perf2 fork-batching fix — docs/backlog.md
# HARNESS-PERF-O3-HB): forwarded straight through to hb_is_stale (args
# 4-6 there; see that function's header for the full rationale — the
# short version: od_sessions already read all of these out of ONE
# batched jq call over every heartbeat file, so re-deriving them here via
# more `_hb_field`/`_hb_epoch`/`date` subprocess forks, per session, was
# pure redundant cost). The 7th arg <pid> additionally skips this
# function's own `_hb_field "$file" "pid"` call in the stale-candidate
# branch. Distinguished by ARGUMENT COUNT exactly as above: reaching
# position 7 requires positions 3-6 to also be supplied. Omit all four
# for unchanged standalone behavior — session-heartbeat.sh's `sweep` verb
# and harness-doctor.sh's heartbeats-fresh check both call this with 1-2
# args today and are completely unaffected.
# ----------------------------------------------------------------------
hb_classify() {
  local file="$1"
  local stale_min="${2:-$OBS_STALE_MIN}"

  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return 0
  fi

  local pid_given=0 pid_pre=""
  if [[ $# -ge 7 ]]; then
    pid_given=1
    pid_pre="$7"
  fi

  local stale_rc
  case "$#" in
    0|1|2)
      hb_is_stale "$file" "$stale_min"
      stale_rc=$?
      ;;
    3)
      hb_is_stale "$file" "$stale_min" "$3"
      stale_rc=$?
      ;;
    4)
      hb_is_stale "$file" "$stale_min" "$3" "$4"
      stale_rc=$?
      ;;
    5)
      hb_is_stale "$file" "$stale_min" "$3" "$4" "$5"
      stale_rc=$?
      ;;
    *)
      hb_is_stale "$file" "$stale_min" "$3" "$4" "$5" "$6"
      stale_rc=$?
      ;;
  esac

  if [[ "$stale_rc" -eq 0 ]]; then
    local pid
    if [[ "$pid_given" == "1" ]]; then
      pid="$pid_pre"
    else
      pid="$(_hb_field "$file" "pid")"
    fi
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

  echo "Scenario 6d: hb_classify — a caller-supplied transcript path (O.3 hb-perf fix) skips _hb_find_transcript entirely and matches the find-based verdict"
  (
    export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts-perf"
    mkdir -p "$OBS_TRANSCRIPTS_ROOT"
    # Same mid-turn shape as scenario 6b: heartbeat old + pid alive (this
    # test's own $$) + transcript fresh -> must classify live either way.
    cat > "$HEARTBEAT_STATE_DIR/sess-perf.json" <<EOF
{"schema":1,"session_id":"sess-perf","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-perf.jsonl"

    # Baseline: no path passed -> unchanged behavior, falls back to this
    # lib's own _hb_find_transcript (a full-tree find).
    cls_find="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-perf.json" 30)"

    # Instrument _hb_find_transcript (shadow it in this subshell only) to
    # prove it is NEVER invoked when a caller (e.g. od_sessions, which
    # already resolved the path via its own O(1) index) passes the
    # transcript path as hb_classify's optional 3rd arg.
    FIND_CALLS=0
    _hb_find_transcript() { FIND_CALLS=$((FIND_CALLS+1)); printf ''; }

    resolved_path="$OBS_TRANSCRIPTS_ROOT/sess-perf.jsonl"
    cls_passed="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-perf.json" 30 "$resolved_path")"

    [[ "$cls_find" == "live" ]] || exit 1
    [[ "$cls_passed" == "live" ]] || exit 2
    [[ "$cls_find" == "$cls_passed" ]] || exit 3
    [[ "$FIND_CALLS" == "0" ]] || exit 4
    exit 0
  )
  rc_perf=$?
  if [[ "$rc_perf" -eq 0 ]]; then
    pass "hb_classify: passed-in transcript path skips _hb_find_transcript entirely and matches the find-based verdict (live == live)"
  else
    fail "hb_classify passed-in-path scenario failed (rc=$rc_perf): verdict or find-call-count check did not hold"
  fi

  echo "Scenario 6e: hb_classify — an explicitly-EMPTY passed-in transcript path (index says 'no transcript exists') is honored as-is, no find fallback, and correctly still classifies crashed/stale (not incorrectly rescued to live)"
  (
    export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts-perf-empty"
    mkdir -p "$OBS_TRANSCRIPTS_ROOT"
    dead_pid=""
    ( : ) & dead_pid=$!
    wait "$dead_pid" 2>/dev/null
    cat > "$HEARTBEAT_STATE_DIR/sess-perf-crashed.json" <<EOF
{"schema":1,"session_id":"sess-perf-crashed","pid":$dead_pid,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    FIND_CALLS=0
    _hb_find_transcript() { FIND_CALLS=$((FIND_CALLS+1)); printf ''; }
    cls="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-perf-crashed.json" 30 "")"
    [[ "$cls" == "crashed" ]] || exit 1
    [[ "$FIND_CALLS" == "0" ]] || exit 2
    exit 0
  )
  rc_empty=$?
  if [[ "$rc_empty" -eq 0 ]]; then
    pass "hb_classify: explicit empty transcript-path arg is honored (no find fallback) and still classifies crashed correctly"
  else
    fail "hb_classify: explicit empty transcript-path arg scenario failed (rc=$rc_empty)"
  fi

  echo "Scenario 6f: hb_classify/hb_is_stale — pre-resolved session-id/last-activity-epoch/now-epoch/pid (O.3 hb-perf2 fork-batching fix, docs/backlog.md HARNESS-PERF-O3-HB) skip _hb_field and _hb_epoch ENTIRELY across a fresh-heartbeat case, a mid-turn-live (transcript-join) case, and a crashed case; kill still runs exactly once, only for the stale-candidate case"
  (
    export OBS_TRANSCRIPTS_ROOT="$TMP/transcripts-batch"
    mkdir -p "$OBS_TRANSCRIPTS_ROOT"
    NOW_EPOCH="$(date -u +%s 2>/dev/null || echo 0)"

    # File-based call counters, NOT plain shell variables: every
    # classification below is captured via command substitution
    # (`x="$(hb_classify ...)"`), which forks a subshell to run the
    # pipeline — a variable incremented by a shadowed function INSIDE
    # that subshell would never be visible out here once it exits. A
    # file write, by contrast, is a real side effect on disk and
    # survives the subshell boundary, so it is the only reliable way to
    # count subprocess-fork-avoidance from outside a captured call.
    FIELD_LOG="$TMP/field-calls.log"
    EPOCH_LOG="$TMP/epoch-calls.log"
    PIDALIVE_LOG="$TMP/pidalive-calls.log"
    _hb_calls() { local log="$1"; [[ -f "$log" ]] && wc -l < "$log" | tr -d ' [:space:]' || printf '0'; }

    # --- sub-case A: fresh heartbeat (age well under stale_min) — the
    # common/dominant real-world case. hb_is_stale must short-circuit at
    # the age check alone: NEITHER _hb_field NOR _hb_epoch NOR
    # _hb_pid_alive (kill) should ever run.
    cat > "$HEARTBEAT_STATE_DIR/sess-batch-fresh.json" <<EOF
{"schema":1,"session_id":"sess-batch-fresh","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
    : > "$FIELD_LOG"; : > "$EPOCH_LOG"; : > "$PIDALIVE_LOG"
    _hb_field() { printf 'x\n' >> "$FIELD_LOG"; printf ''; }
    _hb_epoch() { printf 'x\n' >> "$EPOCH_LOG"; printf '0'; }
    _hb_pid_alive() { printf 'x\n' >> "$PIDALIVE_LOG"; return 0; }

    cls_a="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-batch-fresh.json" 30 "" "sess-batch-fresh" "$NOW_EPOCH" "$NOW_EPOCH" "$$")"
    [[ "$cls_a" == "live" ]] || exit 1
    [[ "$(_hb_calls "$FIELD_LOG")" == "0" ]] || exit 2
    [[ "$(_hb_calls "$EPOCH_LOG")" == "0" ]] || exit 3
    [[ "$(_hb_calls "$PIDALIVE_LOG")" == "0" ]] || exit 4

    # --- sub-case B: heartbeat old (pre-resolved epoch = 2020, far past
    # stale_min), pid alive, transcript fresh — the C1 mid-turn-live
    # shape. Must classify live (transcript join rescues it); still never
    # calls _hb_field/_hb_epoch (all pre-resolved), and _hb_pid_alive
    # must ALSO stay at 0 here (hb_is_stale resolves not-stale via the
    # transcript join before hb_classify's pid branch is ever reached).
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-batch-midturn.jsonl"
    cat > "$HEARTBEAT_STATE_DIR/sess-batch-midturn.json" <<EOF
{"schema":1,"session_id":"sess-batch-midturn","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    : > "$FIELD_LOG"; : > "$EPOCH_LOG"; : > "$PIDALIVE_LOG"
    cls_b="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-batch-midturn.json" 30 "$OBS_TRANSCRIPTS_ROOT/sess-batch-midturn.jsonl" "sess-batch-midturn" 1577836800 "$NOW_EPOCH" "$$")"
    [[ "$cls_b" == "live" ]] || exit 5
    [[ "$(_hb_calls "$FIELD_LOG")" == "0" ]] || exit 6
    [[ "$(_hb_calls "$EPOCH_LOG")" == "0" ]] || exit 7
    [[ "$(_hb_calls "$PIDALIVE_LOG")" == "0" ]] || exit 8

    # --- sub-case C: heartbeat old (pre-resolved epoch), pid dead, no
    # transcript — must classify crashed. _hb_field/_hb_epoch still never
    # called (all fields pre-resolved, including pid), but _hb_pid_alive
    # IS called exactly once: pre-resolving the pid VALUE only skips the
    # _hb_field lookup, not the liveness check itself, which is the
    # entire point of the stale-candidate-only gating this scenario
    # verifies.
    dead_pid=""
    ( : ) & dead_pid=$!
    wait "$dead_pid" 2>/dev/null
    cat > "$HEARTBEAT_STATE_DIR/sess-batch-crashed.json" <<EOF
{"schema":1,"session_id":"sess-batch-crashed","pid":$dead_pid,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"2020-01-01T00:00:00Z","last_event":"turn-end","marker_state":"none"}
EOF
    : > "$FIELD_LOG"; : > "$EPOCH_LOG"; : > "$PIDALIVE_LOG"
    _hb_pid_alive() { printf 'x\n' >> "$PIDALIVE_LOG"; [[ "$1" == "$dead_pid" ]] && return 1 || return 0; }
    cls_c="$(hb_classify "$HEARTBEAT_STATE_DIR/sess-batch-crashed.json" 30 "" "sess-batch-crashed" 1577836800 "$NOW_EPOCH" "$dead_pid")"
    [[ "$cls_c" == "crashed" ]] || exit 9
    [[ "$(_hb_calls "$FIELD_LOG")" == "0" ]] || exit 10
    [[ "$(_hb_calls "$EPOCH_LOG")" == "0" ]] || exit 11
    [[ "$(_hb_calls "$PIDALIVE_LOG")" == "1" ]] || exit 12

    exit 0
  )
  rc_batch=$?
  if [[ "$rc_batch" -eq 0 ]]; then
    pass "hb_classify/hb_is_stale: pre-resolved session-id/epoch/now-epoch/pid skip _hb_field and _hb_epoch entirely across fresh/mid-turn-live/crashed cases; kill runs exactly once, only for the stale-candidate case"
  else
    fail "hb_classify pre-resolved-fields fork-batching scenario failed (rc=$rc_batch) — see sub-case exit codes 1-4=fresh, 5-8=mid-turn-live, 9-12=crashed"
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
