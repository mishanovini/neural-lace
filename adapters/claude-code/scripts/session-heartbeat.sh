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
#   session-heartbeat.sh touch --event <start|prompt|tool-use|turn-end|compact|resume>
#                               [--marker <DONE|PAUSING|BLOCKED|CONTINUING|none>]
#                               [--session <sid>]
#                               [--if-older-than <seconds>]
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
#     --if-older-than <seconds> (2026-08-01 liveness-starvation fix, see
#     WHY THE DIRECT settings.json WIRING below) makes the touch a
#     CHEAP NO-OP when the session's heartbeat file was already written
#     less than <seconds> ago, so a frequently-fired call-site does not pay
#     hb_write's ~43s git/nl-paths/escape fan-out every time. Fails OPEN —
#     any uncertainty (no file, unreadable mtime, non-numeric argument,
#     or a FUTURE mtime / clock skew) means "not fresh", i.e. WRITE. A
#     liveness writer that skipped on doubt would silently stop refreshing,
#     which is the exact defect this flag exists to help close. Paired with
#     the claim-stake in cmd_touch, without which the guard reads an mtime
#     the write only advances ~43s later and is blind to an in-flight
#     sibling.
#
# ============================================================
# WHY THE DIRECT settings.json WIRING (2026-08-01 — the starvation fix)
# ============================================================
#
# PROVEN on this machine 2026-08-01: every heartbeat file in
# ~/.claude/state/heartbeats/ carried "last_event":"start" — the
# SessionStart touch was the ONLY one that ever landed, so the cockpit's
# age-only classifier (workstreams-ui/server/derive-lib.js
# classifyHeartbeatAge) could never see a session as currently active and
# no roadmap row could ever render RUNNING.
#
# The turn-end touch was NOT missing — it was STARVED. It sits at the END
# of workstreams-stop-writer.sh, AFTER that hook's 5-member fork loop, whose
# own emitted turn-trace timings measure 30s-547s per Stop.
#
# PROVEN (observable, re-derived independently by the harness-reviewer
# 2026-08-02): that touch does not run. The signal ledger holds 535
# `stop-verdict-dispatcher` turn-traces against 200
# `workstreams-stop-writer` ones, the last of the latter on
# 2026-07-31T17:18:29Z while the dispatcher kept emitting every turn; on
# 2026-08-01 session d3059d78 emitted 27 dispatcher turn-traces with ZERO
# heartbeat updates; all 14 heartbeat files read "last_event":"start".
#
# HYPOTHESIZED (mechanism): WHICH kill ends the hook. The original reading
# — "Claude Code's 60s hook timeout kills it before the touch" — does not
# survive its own evidence: 154 of those 200 stop-writer traces recorded
# total_ms > 60000 (max 571,816ms), and `ledger_emit` at
# workstreams-stop-writer.sh:260 is a direct append NINE LINES BEFORE the
# touch at :269, so those runs demonstrably ran past 60s AND reached :260,
# which a hard 60s kill forbids. An equally-consistent mechanism: the ~43s
# hb_write at the tail is itself what dies — corroborated by the leaked
# `a83f29bd-….json.iqLTc8` mktemp file in the real heartbeats dir, a kill
# landing between hb_write's printf and its mv. REFUTED IF: instrumenting
# the Stop chain shows :269 entered and hb_write returning normally.
# The fix below works under EITHER mechanism, because it removes the
# dependency on that hook finishing at all — which is why the mechanism was
# not chased further.
#
# The fix is therefore NOT another in-hook splice — it is giving this
# writer its OWN top-level settings.json entries (UserPromptSubmit and
# Stop; NOT PostToolUse — see the cost note in _sh_hb_fresher_than's header
# and the manifest entry), so that a heartbeat refresh can never again be
# starved by an unrelated hook's slow member chain. The pre-existing
# in-hook splices are left in place. Note what that does and does not
# collapse: the two direct entries pass `--if-older-than 15` and, thanks to
# the claim-stake in cmd_touch, genuinely collapse a duplicate between
# themselves. The pre-existing splices (workstreams-stop-writer.sh:220 and
# :269, session-start-digest.sh, pre-compact-continuity.sh) pass NO
# `--if-older-than` and therefore always write; that duplicate is tolerated,
# not prevented, because hb_write is an idempotent atomic overwrite.
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

# The `-auto` spellings are the ADR-061 D2 reentry variants already emitted
# in production by session-start-digest.sh / workstreams-stop-writer.sh /
# pre-compact-continuity.sh; `prompt` and `tool-use` are the 2026-08-01
# direct-wiring events (see WHY THE DIRECT settings.json WIRING above).
# Listing them here is not cosmetic: cmd_touch writes an UNRECOGNISED event
# anyway, but first prints a diagnostic to stderr — and hook stderr is
# operator-visible, so an event this repo itself wires must be on the list
# or every automation-spawned turn emits a spurious warning.
ALLOWED_EVENTS=(start start-auto prompt tool-use turn-end turn-end-auto compact compact-auto resume)
ALLOWED_MARKERS=(DONE PAUSING BLOCKED CONTINUING none)

_sh_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# ----------------------------------------------------------------------
# _sh_hb_fresher_than <sid> <seconds> — exit 0 (true) iff <sid>'s heartbeat
# file exists AND its mtime is younger than <seconds>. Backs the
# `touch --if-older-than` cheap guard.
#
# WHY MTIME AND NOT last_activity_ts: mtime is the moment the writer
# COMMITTED to writing (the claim-stake below touches the destination BEFORE
# hb_write's fan-out), which is <= the moment last_activity_ts is stamped.
# It is a WRITE-INTENT marker, which is exactly what this guard needs, and
# deliberately NOT a liveness signal -- if hb_write dies mid-flight the two
# diverge without bound. Nothing consumes heartbeat-file mtime for liveness
# (cmd_reap uses last_activity_ts + transcript mtime; hb_classify and
# roadmap-routes.js use last_activity_ts), so the divergence is contained.
# 2026-08-02 review B1: the claim-stake invalidated this block's previous
# "mtime IS the moment last_activity_ts was stamped" assertion. Reading it
# costs ONE `date -r` fork, where parsing the ISO string back out would cost
# a jq (or sed) fork PLUS a `date -d` fork. Cost, re-measured by the
# harness-reviewer on the committed blob (3 runs, sandboxed, on a LOADED
# machine — 2026-08-02, ~217 bash processes / 96% memory): bare bash spawn
# 509-1106ms, guarded no-op 4675-7147ms, a FULL hb_write 42267-44834ms.
# (The round-1 figures in this file's history — 250ms / ~2s / 19.9s — were
# taken on a quieter machine and were ~2x optimistic; these are the numbers
# to cite.) The guard therefore turns a ~43s call into a ~6s call — which is
# what makes a sub-turn call-site thinkable at all; it does not make one
# free (see the settings.json wiring note in the header for why PostToolUse
# is deliberately NOT wired even at the guarded cost).
#
# FAILS OPEN — every uncertain path returns 1 ("not fresh" => DO write): a
# missing file, an unreadable/zero mtime, a non-numeric <seconds>, a clock
# that cannot be read, or a mtime in the FUTURE. Skipping on doubt would let
# a liveness writer silently stop refreshing, which is precisely the defect
# being closed here.
#
# THE FUTURE-MTIME CASE IS NOT THEORETICAL (harness-reviewer 2026-08-02,
# Critical 1). The obvious spelling of the last line —
# `[[ $(( now - mtime )) -lt "$secs" ]]` — is TRUE for a NEGATIVE age, so a
# heartbeat stamped in the future is treated as permanently fresh and the
# writer stops refreshing until wall-clock catches up: the exact freeze this
# whole change exists to close, re-introduced by the guard meant to make it
# cheap. Proven with `touch -d '2026-08-03'`: the call took the ~5s skip
# path, not the ~42s write path, and last_event stayed "start". Reachable
# via an NTP correction, MSYS DST/timezone handling, a heartbeat copied
# between worktrees, or a restored backup — so the negative age is rejected
# explicitly BEFORE the freshness comparison, and Scenario K asserts it.
# ----------------------------------------------------------------------
_sh_hb_fresher_than() {
  local sid="$1" secs="$2" f mtime now age
  [[ "$secs" =~ ^[0-9]+$ ]] || return 1
  f="$(hb_path_for "$sid")"
  [[ -f "$f" ]] || return 1
  mtime="$(date -u -r "$f" +%s 2>/dev/null || stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
  [[ "$mtime" =~ ^[0-9]+$ ]] && [[ "$mtime" -gt 0 ]] || return 1
  # bash builtin epoch (>=4.2) — no fork; falls back to `date` only if the
  # builtin format is unsupported.
  now="$(printf '%(%s)T' -1 2>/dev/null)"
  [[ "$now" =~ ^[0-9]+$ ]] || now="$(date -u +%s 2>/dev/null || echo 0)"
  [[ "$now" -gt 0 ]] || return 1
  age=$(( now - mtime ))
  # Future mtime (negative age) => clock skew, NOT freshness. Fail open.
  [[ "$age" -ge 0 ]] || return 1
  [[ "$age" -lt "$secs" ]]
}

# ----------------------------------------------------------------------
# cmd_touch — parse --event/--marker, validate, call hb_write. NEVER
# BLOCKS: an invalid --event or a write failure still exits 0 (this is a
# liveness tick, not a gate); it prints a diagnostic to stderr on the
# invalid-input path so a misconfigured caller is still discoverable, but
# never fails the calling hook chain.
# ----------------------------------------------------------------------
cmd_touch() {
  local event="" marker="none" session="" if_older=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event) event="${2:-}"; shift 2 ;;
      --marker) marker="${2:-none}"; shift 2 ;;
      --session) session="${2:-}"; shift 2 ;;
      --if-older-than) if_older="${2:-}"; shift 2 ;;
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

  # CHEAP FRESHNESS GUARD (--if-older-than): skip the whole write when this
  # session's heartbeat is already younger than the requested age. Placed
  # AFTER validation (so a misconfigured caller still gets its diagnostic)
  # and BEFORE hb_write (the only expensive thing this verb does). Fails
  # open — see _sh_hb_fresher_than's header.
  if [[ -n "$if_older" ]]; then
    if _sh_hb_fresher_than "${session:-${CLAUDE_CODE_SESSION_ID:-unknown}}" "$if_older"; then
      return 0
    fi
  fi

  # CLAIM-STAKE (harness-reviewer 2026-08-02, Critical 2). Bump the
  # DESTINATION's mtime the INSTANT we commit to writing, BEFORE hb_write's
  # ~43s nl-paths/git/escape/mktemp/mv fan-out. Without this the guard reads
  # an mtime that hb_write only advances on COMPLETION, so it is blind for
  # ~3x its own 15s window: a guarded call fired 2s after an in-flight
  # detached write was measured taking the FULL 45,760ms write path. Staking
  # the claim up front is what makes "the guard collapses the duplicate
  # write" a true statement rather than an aspiration, and it bounds the
  # process pile-up on a machine where each write costs ~43s.
  #
  # ONLY when the file ALREADY EXISTS. `touch` on an absent path would
  # create an EMPTY file, and every reader parses it as JSON (this script's
  # own sweep/hb_classify, observability-derive's od_sessions, the cockpit's
  # listRawHeartbeats) — a truncated-looking heartbeat is worse than a
  # duplicate write. The first write of a session has nothing to collapse
  # against anyway, and the guard already fails open on absence.
  #
  # If hb_write subsequently fails, the bumped mtime still records a TRUE
  # fact: this session ran the writer at that moment. It never invents
  # liveness for a session that did not run.
  local _dest
  _dest="$(hb_path_for "${session:-${CLAUDE_CODE_SESSION_ID:-unknown}}")"
  if [[ -f "$_dest" ]]; then
    touch "$_dest" 2>/dev/null || true
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

  # ---- ORPHANED mktemp LEFTOVERS (harness-reviewer 2026-08-02, minor 7) --
  # hb_write's atomic write is `mktemp "${path}.XXXXXX"` + `mv`. A kill
  # landing between its printf and its mv leaks a `<sid>.json.XXXXXX` file
  # that the `*.json` glob above can NEVER match — one has sat unreaped in
  # the real heartbeats dir since 2026-07-23, and the 2026-08-01 direct
  # wiring doubled the number of call-sites that can leak them. Reaped on
  # the SAME threshold, which is orders of magnitude beyond any in-flight
  # write (~43s at this machine's measured worst), so a live write's tmp
  # file is never at risk. Counted separately and reported on its own line:
  # `--json`'s documented shape is an array of SESSION IDS, and a tmp
  # leftover is not one — widening that array would break its consumers.
  local tmp_reaped=0 tf_mtime tf_age_min
  # -print0 + read -d '', matching this file's own convention at the sweep and
  # heartbeat loops above (2026-08-02 review B2: the previous unquoted for-over-find
  # word-split on whitespace, so on any state dir containing a space the reap
  # silently processed NOTHING and still reported "0 leftover(s) reaped" — a
  # false-negative report, and this repo itself lives under a spaced path).
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    tf_mtime="$(date -u -r "$f" +%s 2>/dev/null || stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
    if [[ "$tf_mtime" =~ ^[0-9]+$ ]] && [[ "$tf_mtime" -gt 0 ]]; then
      tf_age_min=$(( (now_epoch - tf_mtime) / 60 ))
    else
      # Unreadable mtime: cannot prove it is old, so LEAVE IT (the opposite
      # of the heartbeat path's convention, deliberately — deleting a file
      # we cannot age could destroy an in-flight write).
      continue
    fi
    [[ "$tf_age_min" -gt "$reap_min" ]] || continue
    tmp_reaped=$(( tmp_reaped + 1 ))
    [[ "$dry_run" == "1" ]] || rm -f "$f" 2>/dev/null || true
  done < <(find "$dir" -maxdepth 1 -type f -name '*.json.*' -print0 2>/dev/null)

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
  printf '%d orphaned mktemp leftover(s) reaped (*.json.XXXXXX, same %dmin threshold)\n' "$tmp_reaped" "$reap_min"
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

  echo "Scenario J: the direct-wiring refresh — a second touch with a NEW event advances last_activity_ts AND moves last_event off 'start' (the 2026-08-01 starvation defect: every real heartbeat file on this machine was frozen at last_event=start because the only touch that ever landed was SessionStart's)"
  local refresh_dir="$TMP/hb-refresh"
  mkdir -p "$refresh_dir"
  (
    export HEARTBEAT_STATE_DIR="$refresh_dir"
    export CLAUDE_CODE_SESSION_ID="sess-refresh"
    cmd_touch --event start
  )
  local frf="$refresh_dir/sess-refresh.json"
  local ts_before ev_before
  ts_before="$(_hb_field "$frf" "last_activity_ts")"
  ev_before="$(_hb_field "$frf" "last_event")"
  # Age the file by a full second so the second write's ISO timestamp
  # (1s resolution) is provably LATER, not merely equal.
  sleep 1
  (
    export HEARTBEAT_STATE_DIR="$refresh_dir"
    export CLAUDE_CODE_SESSION_ID="sess-refresh"
    cmd_touch --event prompt
  )
  local ts_after ev_after
  ts_after="$(_hb_field "$frf" "last_activity_ts")"
  ev_after="$(_hb_field "$frf" "last_event")"
  if [[ "$ev_before" == "start" && "$ev_after" == "prompt" ]]; then
    pass "refresh: last_event advanced start -> prompt (no longer frozen at 'start')"
  else
    fail "refresh: expected last_event start -> prompt, got '$ev_before' -> '$ev_after'"
  fi
  local epoch_before epoch_after
  epoch_before="$(_hb_epoch "$ts_before")"
  epoch_after="$(_hb_epoch "$ts_after")"
  if [[ "$epoch_after" -gt "$epoch_before" ]]; then
    pass "refresh: last_activity_ts ADVANCED ($ts_before -> $ts_after)"
  else
    fail "refresh: last_activity_ts did not advance ($ts_before -> $ts_after)"
  fi

  echo "Scenario K: --if-older-than cheap guard — a FRESH file is not rewritten; a STALE one is; a non-numeric threshold fails OPEN (writes)"
  local guard_dir="$TMP/hb-guard"
  mkdir -p "$guard_dir"
  (
    export HEARTBEAT_STATE_DIR="$guard_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard"
    cmd_touch --event start
  )
  local gf="$guard_dir/sess-guard.json"
  local g_ev_before g_ts_before
  g_ev_before="$(_hb_field "$gf" "last_event")"
  g_ts_before="$(_hb_field "$gf" "last_activity_ts")"
  sleep 1
  (
    export HEARTBEAT_STATE_DIR="$guard_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard"
    cmd_touch --event tool-use --if-older-than 600
  )
  local g_ev_fresh g_ts_fresh
  g_ev_fresh="$(_hb_field "$gf" "last_event")"
  g_ts_fresh="$(_hb_field "$gf" "last_activity_ts")"
  if [[ "$g_ev_fresh" == "$g_ev_before" && "$g_ts_fresh" == "$g_ts_before" ]]; then
    pass "guard: a file younger than --if-older-than 600 was NOT rewritten (event and ts both unchanged)"
  else
    fail "guard: fresh file WAS rewritten (event '$g_ev_before'->'$g_ev_fresh', ts '$g_ts_before'->'$g_ts_fresh')"
  fi
  # Same call with a 0-second threshold: nothing can be younger than 0s, so
  # the guard must fall through to a real write.
  (
    export HEARTBEAT_STATE_DIR="$guard_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard"
    cmd_touch --event tool-use --if-older-than 0
  )
  local g_ev_stale
  g_ev_stale="$(_hb_field "$gf" "last_event")"
  if [[ "$g_ev_stale" == "tool-use" ]]; then
    pass "guard: --if-older-than 0 falls through to a real write (last_event -> tool-use)"
  else
    fail "guard: --if-older-than 0 did not write (last_event still '$g_ev_stale')"
  fi
  # Fail-open: a non-numeric threshold must WRITE, never silently skip.
  local guard_open_dir="$TMP/hb-guard-open"
  mkdir -p "$guard_open_dir"
  (
    export HEARTBEAT_STATE_DIR="$guard_open_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard-open"
    cmd_touch --event start
  )
  sleep 1
  (
    export HEARTBEAT_STATE_DIR="$guard_open_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard-open"
    cmd_touch --event turn-end --if-older-than abc
  )
  local go_ev
  go_ev="$(_hb_field "$guard_open_dir/sess-guard-open.json" "last_event")"
  if [[ "$go_ev" == "turn-end" ]]; then
    pass "guard: a non-numeric --if-older-than FAILS OPEN (writes rather than skipping)"
  else
    fail "guard: non-numeric --if-older-than skipped the write (last_event '$go_ev', expected turn-end)"
  fi
  # CLOCK SKEW / FUTURE MTIME (harness-reviewer 2026-08-02, Critical 1): a
  # heartbeat stamped in the FUTURE has a NEGATIVE age. The naive
  # `age -lt secs` test is TRUE for it, so the writer would treat the file
  # as permanently fresh and stop refreshing until wall-clock caught up —
  # re-introducing the exact freeze this change closes, via the guard meant
  # to make it cheap. The write MUST land.
  local guard_skew_dir="$TMP/hb-guard-skew"
  mkdir -p "$guard_skew_dir"
  (
    export HEARTBEAT_STATE_DIR="$guard_skew_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard-skew"
    cmd_touch --event start
  )
  local skf="$guard_skew_dir/sess-guard-skew.json"
  local future_stamp
  future_stamp="$(date -u -d '+1 day' '+%Y%m%d%H%M' 2>/dev/null || date -u -v+1d '+%Y%m%d%H%M' 2>/dev/null)"
  if [[ -n "$future_stamp" ]] && touch -t "$future_stamp" "$skf" 2>/dev/null; then
    (
      export HEARTBEAT_STATE_DIR="$guard_skew_dir"
      export CLAUDE_CODE_SESSION_ID="sess-guard-skew"
      cmd_touch --event turn-end --if-older-than 15
    )
    local sk_ev
    sk_ev="$(_hb_field "$skf" "last_event")"
    if [[ "$sk_ev" == "turn-end" ]]; then
      pass "guard: a FUTURE mtime (clock skew) fails OPEN — the write lands instead of freezing the heartbeat until wall-clock catches up"
    else
      fail "guard: future-mtime file was treated as fresh and skipped (last_event '$sk_ev', expected turn-end) — negative-age regression"
    fi
  else
    echo "  (could not stamp a future mtime on this platform — skipping the clock-skew assertion)"
  fi

  # A guard against a session with NO heartbeat file yet must also write.
  local guard_new_dir="$TMP/hb-guard-new"
  mkdir -p "$guard_new_dir"
  (
    export HEARTBEAT_STATE_DIR="$guard_new_dir"
    export CLAUDE_CODE_SESSION_ID="sess-guard-new"
    cmd_touch --event prompt --if-older-than 600
  )
  if [[ -f "$guard_new_dir/sess-guard-new.json" ]]; then
    pass "guard: a session with no heartbeat file yet is written despite --if-older-than (fail-open on absence)"
  else
    fail "guard: --if-older-than suppressed the FIRST write for a session with no heartbeat file"
  fi

  echo "Scenario L: the writer NEVER returns nonzero — not on an unwritable state dir, and not on the guard path either (writer-never-blocks contract: a liveness tick must not be able to fail a tool call)"
  local unwritable="$TMP/unwritable-file"
  printf 'x\n' > "$unwritable"
  local rc_unwritable rc_unwritable_guard rc_unwritable_script
  # A regular FILE used as the state DIR: mkdir -p cannot create the
  # directory under it, so every write path fails — and must still exit 0.
  (
    export HEARTBEAT_STATE_DIR="$unwritable/hb"
    export CLAUDE_CODE_SESSION_ID="sess-unwritable"
    cmd_touch --event turn-end 2>/dev/null
  )
  rc_unwritable=$?
  if [[ "$rc_unwritable" == "0" ]]; then
    pass "writer: touch on an unwritable state dir still returns 0"
  else
    fail "writer: touch on an unwritable state dir returned $rc_unwritable (expected 0)"
  fi
  (
    export HEARTBEAT_STATE_DIR="$unwritable/hb"
    export CLAUDE_CODE_SESSION_ID="sess-unwritable"
    cmd_touch --event tool-use --if-older-than 60 2>/dev/null
  )
  rc_unwritable_guard=$?
  if [[ "$rc_unwritable_guard" == "0" ]]; then
    pass "writer: guarded touch on an unwritable state dir still returns 0"
  else
    fail "writer: guarded touch on an unwritable state dir returned $rc_unwritable_guard (expected 0)"
  fi
  # Same through the real entry point (a hook calls the SCRIPT, not the
  # function) — the exit-0 contract has to hold at process level too.
  (
    export HEARTBEAT_STATE_DIR="$unwritable/hb"
    export CLAUDE_CODE_SESSION_ID="sess-unwritable"
    bash "$SCRIPT_DIR/session-heartbeat.sh" touch --event tool-use --if-older-than 60 >/dev/null 2>&1
  )
  rc_unwritable_script=$?
  if [[ "$rc_unwritable_script" == "0" ]]; then
    pass "writer: the SCRIPT exits 0 on an unwritable state dir (process-level never-blocks contract)"
  else
    fail "writer: the script exited $rc_unwritable_script on an unwritable state dir (expected 0)"
  fi

  echo "Scenario M: the CLAIM-STAKE — a guarded call fired while a sibling write is still IN FLIGHT must skip. The guard reads the destination's mtime, which hb_write only advances on COMPLETION (~43s later), so without staking the claim up front the guard is blind for ~3x its own window and both calls take the full write path (harness-reviewer 2026-08-02, Critical 2)."
  local stake_dir="$TMP/hb-stake"
  mkdir -p "$stake_dir"
  (
    export HEARTBEAT_STATE_DIR="$stake_dir"
    export CLAUDE_CODE_SESSION_ID="sess-stake"
    cmd_touch --event start
  )
  local stake_file="$stake_dir/sess-stake.json"
  local stake_calls="$stake_dir/hb_write.calls"
  local old_stamp
  old_stamp="$(date -u -d '1 hour ago' '+%Y%m%d%H%M' 2>/dev/null || date -u -v-1H '+%Y%m%d%H%M' 2>/dev/null)"
  if [[ -n "$old_stamp" ]] && touch -t "$old_stamp" "$stake_file" 2>/dev/null; then
    (
      export HEARTBEAT_STATE_DIR="$stake_dir"
      export CLAUDE_CODE_SESSION_ID="sess-stake"
      : > "$stake_calls"
      # Stand in for the real ~43s writer: this isolates the ONE thing under
      # test — whether the DESTINATION's mtime is advanced BEFORE the write
      # body runs, rather than after it.
      hb_write() { printf 'call\n' >> "$stake_calls"; sleep 5; return 0; }
      cmd_touch --event turn-end &
      sleep 1
      # Sibling guarded call, 1s into a 5s "write". With the claim-stake it
      # sees a fresh mtime and skips; without it, it piles on a second write.
      cmd_touch --event tool-use --if-older-than 60
      wait
    )
    local stake_n
    stake_n="$(wc -l < "$stake_calls" 2>/dev/null | tr -d ' \r')"
    if [[ "$stake_n" == "1" ]]; then
      pass "claim-stake: a guarded call during an in-flight write SKIPPED (hb_write invoked exactly once, not twice)"
    else
      fail "claim-stake: expected exactly 1 hb_write invocation, got '$stake_n' — the guard is blind to the in-flight sibling"
    fi
  else
    echo "  (could not stamp a past mtime on this platform — skipping the claim-stake assertion)"
  fi
  # The claim-stake must NEVER create a file that does not exist: `touch` on
  # an absent path yields an EMPTY file, and every reader parses these as
  # JSON (sweep/hb_classify here, od_sessions, the cockpit's
  # listRawHeartbeats). Absent + guarded must still produce VALID JSON.
  local stake_new_dir="$TMP/hb-stake-new"
  mkdir -p "$stake_new_dir"
  (
    export HEARTBEAT_STATE_DIR="$stake_new_dir"
    export CLAUDE_CODE_SESSION_ID="sess-stake-new"
    cmd_touch --event prompt --if-older-than 60
  )
  local stake_new_file="$stake_new_dir/sess-stake-new.json"
  if [[ -s "$stake_new_file" ]] && { ! command -v jq >/dev/null 2>&1 || jq -e . "$stake_new_file" >/dev/null 2>&1; }; then
    pass "claim-stake: a first-ever write produces a NON-EMPTY, jq-valid heartbeat (the stake never creates a truncated file readers would choke on)"
  else
    fail "claim-stake: first-ever guarded write left an empty/invalid heartbeat at $stake_new_file"
  fi

  echo "Scenario N: reap also removes ORPHANED mktemp leftovers (<sid>.json.XXXXXX) — hb_write's tmp+mv leaks one whenever a kill lands between its printf and its mv, and the *.json glob can never match them (one has sat in the real state dir since 2026-07-23)"
  local orphan_dir="$TMP/hb-orphan"
  mkdir -p "$orphan_dir"
  local orphan_transcripts="$TMP/orphan-transcripts"
  mkdir -p "$orphan_transcripts"
  printf '{"schema":1}\n' > "$orphan_dir/abc-def.json.iqLTc8"
  printf '{"schema":1}\n' > "$orphan_dir/fresh-sid.json.ZZZZZZ"
  local ancient_stamp
  ancient_stamp="$(date -u -d '30 days ago' '+%Y%m%d%H%M' 2>/dev/null || date -u -v-30d '+%Y%m%d%H%M' 2>/dev/null)"
  if [[ -n "$ancient_stamp" ]] && touch -t "$ancient_stamp" "$orphan_dir/abc-def.json.iqLTc8" 2>/dev/null; then
    local orphan_out
    orphan_out="$(HEARTBEAT_STATE_DIR="$orphan_dir" OBS_TRANSCRIPTS_ROOT="$orphan_transcripts" cmd_reap)"
    if [[ ! -f "$orphan_dir/abc-def.json.iqLTc8" ]]; then
      pass "reap: a >24h-old mktemp leftover was removed"
    else
      fail "reap: the ancient mktemp leftover survived"
    fi
    if [[ -f "$orphan_dir/fresh-sid.json.ZZZZZZ" ]]; then
      pass "reap: a FRESH mktemp leftover (possible in-flight write) was NOT removed"
    else
      fail "reap: removed a fresh mktemp leftover — an in-flight write could be destroyed"
    fi
    if printf '%s' "$orphan_out" | grep -q "1 orphaned mktemp leftover(s) reaped"; then
      pass "reap: plain output reports the leftover count on its own line (oracle-named)"
    else
      fail "reap: leftover count not reported: $orphan_out"
    fi
    # --json's documented shape is an array of SESSION IDS; a tmp leftover is
    # not one and must not widen it.
    local orphan_json
    orphan_json="$(HEARTBEAT_STATE_DIR="$orphan_dir" OBS_TRANSCRIPTS_ROOT="$orphan_transcripts" cmd_reap --json)"
    if command -v jq >/dev/null 2>&1 && printf '%s' "$orphan_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
      pass "reap --json remains a valid array of session ids (leftover reaping did not change its shape)"
    else
      fail "reap --json shape broke: $orphan_json"
    fi
  else
    echo "  (could not stamp an ancient mtime on this platform — skipping the leftover-reap assertions)"
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
  touch --event <start|prompt|tool-use|turn-end|compact|resume>
        [--marker <state>] [--session <sid>] [--if-older-than <seconds>]
                          Atomically write/refresh a session's heartbeat
                          file (--session targets an explicit sid,
                          overriding $CLAUDE_CODE_SESSION_ID — ADR-061 D2;
                          --if-older-than makes the touch a cheap no-op
                          when the file is already younger than <seconds>,
                          failing OPEN so any doubt still writes).
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
