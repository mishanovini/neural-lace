#!/bin/bash
# session-resumer.sh — OS-level session-death watchdog (NL Overhaul Wave E,
# task E.7; operator directive 2026-07-02, API-throttle survival; plan
# Decisions Log entry "E.7 session-resumer watchdog added").
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# A session throttled by the API (429/529/rate-limit/overloaded) or one
# that simply goes idle mid-task cannot recover itself — the model is not
# running. The prior attempt at this (the "wake-queue") tried to deliver a
# nudge INTO a session-mediated channel and dropped 330/330 messages
# because a dead session cannot consume anything. This script acts at the
# OS level instead: it is invoked by a Windows Scheduled Task (outside the
# API entirely, so throttling cannot kill the watchdog itself), scans
# recent transcripts for a death signature, and resumes via the `claude`
# CLI directly (`claude -p --resume <session-id> "<nudge>"`).
#
# ============================================================
# REGISTRATION (ORCHESTRATOR STEP — NOT done by this builder; §E.W step 6)
# ============================================================
#
# This builder (E.7) does NOT run schtasks. Per specs-e §E.0.1 /
# §E.W.6, task registration + the live kill-and-resume drill are
# orchestrator-supervised steps. The EXACT command the orchestrator runs
# (10-minute cadence, git-bash invocation, per specs-e §E.7):
#
#   schtasks /Create /SC MINUTE /MO 10 \
#     /TN "NL-session-resumer" \
#     /TR "C:\Program Files\Git\bin\bash.exe -c 'cd <nl-repo-root> && bash adapters/claude-code/scripts/session-resumer.sh'"
#
# (<nl-repo-root> is the operator's neural-lace checkout — resolve via
# `bash adapters/claude-code/hooks/lib/nl-paths.sh` sourced, same as every
# other schtasks doc in this repo; see scripts/schedule-weekly-eval.md for
# the sibling convention this mirrors.)
#
# The doctor predicate this builder documents (implemented by E.10) is in
# the sibling `doctor-predicate.md` fragment beside this file's manifest
# fragment: adapters/claude-code/tests/fixtures/wave-e/E.7/doctor-predicate.md
#
# ============================================================
# DEATH SIGNATURE (per specs-e §E.7)
# ============================================================
#
# A transcript (JSONL, modified within the last 48h) is DEAD when EITHER:
#
#   (a) API-error tail: the last event in the transcript, stringified,
#       matches (case-insensitively) `429|529|rate.?limit|overloaded`.
#   (b) Stale-with-in-flight-work: the transcript's mtime is >30 minutes
#       old AND at least one of:
#         - the most recent TodoWrite tool_use call's todos[] contains an
#           entry with status "in_progress";
#         - the final assistant message's last non-empty line carries a
#           CONTINUING: marker (the D.3 marker vocabulary's machine-
#           readable "intended to continue" signal);
#         - an ACTIVE-plan file (docs/plans/*.md, no archive/deferred,
#           containing an unchecked `- [ ]` task) was referenced (its
#           basename appears in transcript text) within the transcript's
#           OWN last hour of activity (last event ts minus 1h).
#
# A NATURAL END (the final assistant message's last non-empty line
# carries DONE: or PAUSING:) is never resumed regardless of the above —
# classified skip, logged, left alone.
#
# ============================================================
# RESUME MECHANICS
# ============================================================
#
#   claude -p --resume <session-id> "<nudge>"
#
# where <nudge> is the fixed string (verbatim, asserted by --self-test):
#
#   "re-read SCRATCHPAD.md + NEEDS-YOU.md, verify branch state, continue the in-flight task"
#
# Backoff state per session: ~/.claude/state/resumer/<session-id>.json
# {attempts, next_eligible_epoch, last_event}. Schedule: 5 -> 15 -> 45 ->
# 120 minutes between successive attempts; after 5 attempts, escalate (one
# digest-feed line + ledger event) and STOP retrying that session (no
# further resume commands are constructed for it).
#
# Fresh-spawn fallback: only when `claude -p --resume` itself exits
# non-zero with an unresumable error (session corrupt/unknown to the CLI)
# — NOT merely because the resumed session dies again later (that is a
# normal backoff cycle, not an unresumable error). On that fallback path:
#   claude -p "<substrate nudge>"
# run with the session's own cwd as the working directory, substrate nudge
# referencing SCRATCHPAD.md + the ACTIVE plan + NEEDS-YOU.md.
#
# ============================================================
# LEDGER + DIGEST
# ============================================================
#
# Every action (classify-skip, resume-attempt, resume-fallback, backoff-
# wait, escalation) calls `ledger_emit resumer <event> <detail>` via
# hooks/lib/signal-ledger.sh, AND appends one JSON line to the digest feed
# file the E.1 digest reads directly (documented path, no dependency on
# E.1 existing yet):
#
#   ~/.claude/state/resumer/digest-feed.jsonl
#   {"ts", "session_id", "event", "detail"}
#
# E.1's session-start-digest.sh (§E.1) is specced to read this file for
# its "session-resumer" feed line (count of resumes in the last 24h +
# most recent one-liner). This path is ALSO recorded in this task's
# doctor-predicate.md fragment so E.10 can grep-verify the wiring exists.
#
# ============================================================
# ACTIVATION GUARDRAILS (E.7 activation preconditions, operator concern
# 2026-07-06 — nl-issue ledger entry "E.7 ACTIVATION PRECONDITIONS";
# BINDING before the scheduled task is armed for real resumes)
# ============================================================
#
# (1) STORM CAP — machine-wide max resume/fallback ACTIONS per rolling hour
#     (default 2, RESUMER_STORM_CAP override). A reboot can leave many dead
#     transcripts at once; without a cap every one of them fires a `claude`
#     process in the same watchdog pass. Classification still runs for every
#     candidate every pass (nothing is skipped-and-forgotten); once the cap
#     for the current rolling hour is reached, remaining resume-eligible
#     sessions are QUEUED oldest-transcript-first and logged to the digest
#     feed as event "storm-cap-queued" with detail "resume queued (storm
#     cap)" — they get picked up on a LATER pass once the window has room
#     (the queue is not persisted structure, it re-derives every pass from
#     whatever is still resume-eligible; "oldest first" = transcript mtime
#     ascending). Cap state: one timestamp-per-action append log at
#     `~/.claude/state/resumer/storm-cap.log` (one epoch-seconds line per
#     resume/fallback action taken); the count of lines within the last
#     3600s IS the rolling-hour count. RESUMER_STORM_CAP=0 disables the cap
#     (unlimited — escape hatch, still logged if used).
#
# (2) TOMBSTONES — a session that was deliberately ended (not crashed) is
#     marked never-resume via a marker FILE (not a marker line in a shared
#     log, so a single `rm` retracts it) at:
#       ~/.claude/state/session-resumer/never/<session-id>
#     New verb: `session-resumer.sh --never <session-id>` touches that file
#     (idempotent; mkdir -p the dir first). The scan skips ANY transcript
#     whose session id has a tombstone, logging "classify-skip" with detail
#     "tombstoned — never-resume marker present".
#
#     Archived-session marker (investigated): the CCD session store exposes
#     archival only via the `archive_session` MCP tool call, not as a
#     mechanically-discoverable on-disk file this bash script can read —
#     `~/.claude/projects/<slug>/<session-id>.jsonl` gains no archived-flag
#     sibling file and no in-JSONL marker on archival (verified by inspecting
#     a live projects dir: sessions have only their own `.jsonl`, plus for
#     some IDs a same-named directory holding `subagents/`+`workflows/`
#     subdirs — unrelated to archival status). So: ARCHIVING AND TOMBSTONING
#     ARE NOT THE SAME THING and this script does NOT infer one from the
#     other. `--never <id>` is the one explicit channel; if a session is
#     archived through the UI/tool and the operator also wants the watchdog
#     to leave it alone forever, they run `--never` on it too.
#
# (3) LIVENESS GUARD — skip any session whose repo has a FRESH interactive-
#     session-lock signal (the B.12 pattern in hooks/lib/interactive-
#     session-lock.sh, also consumed by scripts/sync-pt-to-personal.sh):
#     either the explicit `<repo>/.claude/state/interactive-session.lock`
#     file, or a fresh transcript under that repo's own Claude-projects slug
#     dir, both within ISL_WINDOW_MIN (default 15) minutes. This is the
#     "open-but-idle interactive window" false-positive guard: a human may
#     be mid-thought in a DIFFERENT session on the same repo when this one
#     went stale, and headlessly injecting a resume nudge into that repo
#     while a person is actively looking at it is exactly the class of harm
#     B.12 exists to prevent. Classified skip, logged "classify-skip" with
#     detail "liveness guard: interactive session live on <repo-root>".
#     Resolved repo root: the transcript's own `cwd` field (same field
#     perform_resume already reads for the fallback path).
#
# (4) SHADOW MODE — RESUMER_SHADOW=1 (env var, distinct from --self-test's
#     HARNESS_SELFTEST=1 dry-run plumbing) runs classification AND every
#     guardrail (storm cap / tombstone / liveness) exactly as in a live
#     pass, but the final resume/fallback command is NEVER executed —
#     instead ONE digest-feed line is appended per would-be action:
#       event="would-have-resumed", detail="would-have-resumed <session-id>
#       (<reason>)"
#     No backoff state is written in shadow mode (a shadow pass must be
#     re-runnable indefinitely without mutating the real backoff schedule
#     that governs live behavior later). This is the mode the scheduled
#     task registers with FIRST — see docs/runbooks/session-resumer.md for
#     the shadow -> armed rollout procedure and the kill switch.
#
# (5) KILL SWITCH — documented in docs/runbooks/session-resumer.md: what
#     the watchdog does, the shadow->armed rollout, the one-liner to
#     disable the scheduled task (`schtasks /Change /TN "NL-session-
#     resumer" /DISABLE`), the `--never` tombstone verb, and storm-cap
#     tuning (RESUMER_STORM_CAP).
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST)
# ============================================================
#
# HARNESS_SELFTEST=1 routes ALL state (backoff files, digest feed, storm-cap
# log, tombstone dir) through signal-ledger.sh's existing sandbox convention
# PLUS this script's own RESUMER_STATE_DIR override (mirrors local-edit-
# gate.sh / plan-edit-validator.sh's per-lib override pattern). The self-test
# NEVER invokes the real `claude` binary — resume/fallback command
# construction is captured into RESUMER_DRYRUN_LOG instead of exec'd, exactly
# like a "would run: <cmd>" trace.
#
# Usage:
#   session-resumer.sh                    # live scan + resume pass
#   session-resumer.sh --self-test         # exercise fixtures, never invokes claude
#   session-resumer.sh --never <session-id>  # tombstone: never resume this id
#   RESUMER_SHADOW=1 session-resumer.sh   # classify + guardrails, log would-have, never exec
#
# Bash 3.2 / Git-Bash on Windows portable (no mapfile, no declare -A).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/../hooks/lib/signal-ledger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "${ISL_LIB_PATH:-$SCRIPT_DIR/../hooks/lib/interactive-session-lock.sh}" 2>/dev/null || true

RESUME_NUDGE="re-read SCRATCHPAD.md + NEEDS-YOU.md, verify branch state, continue the in-flight task"

# Backoff schedule in minutes, indexed by attempt number (1-based: the
# Nth entry is the wait BEFORE the Nth retry attempt after a failure).
# 5 -> 15 -> 45 -> 120 -> 120 (attempt 5 also waits 120; the cap is on
# ATTEMPT COUNT reaching 5, not on the backoff minutes growing further).
BACKOFF_MINUTES=(5 15 45 120 120)
MAX_ATTEMPTS=5

# ----------------------------------------------------------------------
# _resumer_state_dir — resolve the per-session backoff state directory.
# HARNESS_SELFTEST=1 sandboxes via RESUMER_STATE_DIR (required to be set
# by the self-test harness; falls back to a TMPDIR sandbox otherwise so a
# stray HARNESS_SELFTEST=1 invocation never touches production state).
# ----------------------------------------------------------------------
_resumer_state_dir() {
  if [[ -n "${RESUMER_STATE_DIR:-}" ]]; then
    printf '%s' "$RESUMER_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/resumer-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state/resumer' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _resumer_digest_feed — resolve the digest-feed JSONL path (E.1 consumer
# contract). Sandboxed the same way as the backoff state dir.
# ----------------------------------------------------------------------
_resumer_digest_feed() {
  printf '%s/digest-feed.jsonl' "$(_resumer_state_dir)"
}

# ----------------------------------------------------------------------
# _resumer_projects_root — resolve ~/.claude/projects (or
# RESUMER_PROJECTS_ROOT override for --self-test / fixture scans).
# ----------------------------------------------------------------------
_resumer_projects_root() {
  if [[ -n "${RESUMER_PROJECTS_ROOT:-}" ]]; then
    printf '%s' "$RESUMER_PROJECTS_ROOT"
    return 0
  fi
  printf '%s/.claude/projects' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# _resumer_tombstone_dir — resolve the never-resume marker directory
# (activation guardrail 2: TOMBSTONES). Sandboxed the same way as the
# backoff state dir (RESUMER_STATE_DIR override wins; else derives from it
# so a --self-test run's tombstones never leak into production).
# ----------------------------------------------------------------------
_resumer_tombstone_dir() {
  printf '%s/never' "$(_resumer_state_dir)"
}

# ----------------------------------------------------------------------
# _resumer_tombstone_path <session_id>
# ----------------------------------------------------------------------
_resumer_tombstone_path() {
  printf '%s/%s' "$(_resumer_tombstone_dir)" "$1"
}

# ----------------------------------------------------------------------
# is_tombstoned <session_id> — 0 (true) if a never-resume marker exists.
# ----------------------------------------------------------------------
is_tombstoned() {
  [[ -f "$(_resumer_tombstone_path "$1")" ]]
}

# ----------------------------------------------------------------------
# tombstone_session <session_id> — the `--never <id>` verb: creates the
# marker (idempotent; mkdir -p first). Always returns 0 unless the dir
# genuinely cannot be created.
# ----------------------------------------------------------------------
tombstone_session() {
  local sid="$1" dir path
  [[ -z "$sid" ]] && { echo "session-resumer: --never requires a session-id" >&2; return 1; }
  dir="$(_resumer_tombstone_dir)"
  mkdir -p "$dir" 2>/dev/null || { echo "session-resumer: could not create tombstone dir $dir" >&2; return 1; }
  path="$(_resumer_tombstone_path "$sid")"
  : > "$path" 2>/dev/null || { echo "session-resumer: could not write tombstone $path" >&2; return 1; }
  emit_action "$sid" "tombstone" "never-resume marker created (--never)"
  echo "session-resumer: tombstoned $sid -> $path"
  return 0
}

# ----------------------------------------------------------------------
# _resumer_storm_cap_log — resolve the storm-cap action-timestamp log path
# (activation guardrail 1: STORM CAP). One epoch-seconds line per
# resume/fallback action taken; sandboxed the same way as the backoff dir.
# ----------------------------------------------------------------------
_resumer_storm_cap_log() {
  printf '%s/storm-cap.log' "$(_resumer_state_dir)"
}

# ----------------------------------------------------------------------
# storm_cap_count_last_hour — count of storm-cap-log lines with epoch
# timestamp within the last 3600s of now. Prunes older lines from the log
# on every call (keeps the file from growing unbounded) — best-effort,
# never fails the caller.
# ----------------------------------------------------------------------
storm_cap_count_last_hour() {
  local path now cutoff
  path="$(_resumer_storm_cap_log)"
  [[ -f "$path" ]] || { echo 0; return 0; }
  now=$(date -u +%s)
  cutoff=$((now - 3600))
  local kept
  kept="$(awk -v cutoff="$cutoff" '$1 ~ /^[0-9]+$/ && $1 >= cutoff' "$path" 2>/dev/null)"
  # Rewrite the log pruned to just the kept (recent) lines — best-effort.
  if [[ -n "$kept" ]]; then
    printf '%s\n' "$kept" > "${path}.tmp$$" 2>/dev/null && mv "${path}.tmp$$" "$path" 2>/dev/null || true
  else
    : > "$path" 2>/dev/null || true
  fi
  if [[ -z "$kept" ]]; then
    echo 0
  else
    printf '%s\n' "$kept" | grep -c '^[0-9]'
  fi
}

# ----------------------------------------------------------------------
# storm_cap_record_action — append one epoch-seconds line marking a
# resume/fallback action was just taken (called ONLY on the live/dryrun
# action path, never in shadow mode — shadow mode never consumes the cap).
# ----------------------------------------------------------------------
storm_cap_record_action() {
  local path
  path="$(_resumer_storm_cap_log)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  date -u +%s >> "$path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# storm_cap_limit — echoes the configured cap (RESUMER_STORM_CAP override,
# default 2). 0 means uncapped.
# ----------------------------------------------------------------------
storm_cap_limit() {
  printf '%s' "${RESUMER_STORM_CAP:-2}"
}

# ----------------------------------------------------------------------
# storm_cap_has_room — 0 (true) if another action can be taken within the
# current rolling hour, given the configured cap. A cap of 0 means
# unlimited (always has room).
# ----------------------------------------------------------------------
storm_cap_has_room() {
  local cap
  cap="$(storm_cap_limit)"
  [[ "$cap" -eq 0 ]] && return 0
  local count
  count="$(storm_cap_count_last_hour)"
  [[ "$count" -lt "$cap" ]]
}

# ----------------------------------------------------------------------
# liveness_guard_live <transcript> — 0 (true) if the transcript's own repo
# (its `cwd` field) has a FRESH interactive-session-lock signal (activation
# guardrail 3: LIVENESS GUARD, the B.12 pattern). Returns 1 (false, i.e.
# "no live interactive window, safe to consider resuming") whenever the
# ISL lib is unavailable, the transcript has no cwd, or the check itself
# fails — never blocks the scan due to a missing dependency.
# ----------------------------------------------------------------------
liveness_guard_live() {
  local transcript="$1"
  command -v isl_live_session >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local cwd
  cwd="$(jq -r '.cwd? // empty' "$transcript" 2>/dev/null | head -1)"
  [[ -z "$cwd" ]] && return 1
  isl_live_session "$cwd"
}

# ----------------------------------------------------------------------
# emit_digest_feed <session_id> <event> <detail> — best-effort JSONL
# append to the digest-feed file, mirrors signal-ledger.sh's own
# never-fails-the-caller contract.
# ----------------------------------------------------------------------
emit_digest_feed() {
  local sid="$1" event="$2" detail="$3"
  local path
  path="$(_resumer_digest_feed)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg sid "$sid" --arg ev "$event" --arg d "$detail" \
      '{ts:$ts, session_id:$sid, event:$ev, detail:$d}' >> "$path" 2>/dev/null || true
  else
    printf '{"ts":"%s","session_id":"%s","event":"%s","detail":"%s"}\n' \
      "$ts" "$sid" "$event" "${detail//\"/\\\"}" >> "$path" 2>/dev/null || true
  fi
  return 0
}

# ----------------------------------------------------------------------
# _resumer_normalize_event <event> — NL Observability Program Wave O, task
# O.1 (specs-o §O.1 deliverable 2): maps this script's own pre-existing
# event vocabulary (tombstone/escalation/backoff-wait/would-have-resumed/
# storm-cap-queued/resume-attempt/resume-unresumable/resume-fallback/
# classify-skip) onto the frozen contract-C2 ledger event types
# (session-resume/throttle-detected), so the SIGNAL LEDGER carries the
# normalized name while the ORIGINAL name is preserved verbatim in the
# detail text (never lost — "keep old names as detail text" per specs-o).
#
# Mapping rationale:
#   session-resume    — an actual (or would-be, under shadow mode) resume
#                        attempt against a dead session: resume-attempt,
#                        resume-fallback, resume-unresumable,
#                        would-have-resumed, tombstone (a resume-adjacent
#                        lifecycle action on the session).
#   throttle-detected  — this pass could not/did not act because of a
#                        rate/volume constraint: backoff-wait (per-session
#                        cooldown), storm-cap-queued (rolling-hour cap),
#                        escalation (repeated-failure ceiling reached).
#   (anything else, e.g. classify-skip — a natural-end/no-signal
#    classification, not a resume or a throttle event) passes through
#    UNCHANGED; the digest-feed side (emit_digest_feed, called separately
#    by emit_action below) always keeps the original name regardless.
# ----------------------------------------------------------------------
_resumer_normalize_event() {
  local event="$1"
  case "$event" in
    resume-attempt|resume-fallback|resume-unresumable|would-have-resumed|tombstone)
      printf 'session-resume'
      ;;
    backoff-wait|storm-cap-queued|escalation)
      printf 'throttle-detected'
      ;;
    *)
      printf '%s' "$event"
      ;;
  esac
}

# ----------------------------------------------------------------------
# emit_action <session_id> <event> <detail> — the one call site every
# action funnels through: ledger_emit (if available) + digest feed.
#
# Wave O task O.1: the LEDGER event name is normalized to contract C2
# (session-resume | throttle-detected | passthrough) via
# _resumer_normalize_event; the ORIGINAL event name is preserved verbatim
# at the front of the ledger detail text ("orig_event=<event> ..."), never
# dropped. The DIGEST FEED (emit_digest_feed below) is UNCHANGED — it
# keeps receiving the original event name exactly as before, so every
# pre-existing digest-feed self-test assertion (grep '"event":"escalation"'
# etc. against digest-feed.jsonl) continues to pass unmodified.
# ----------------------------------------------------------------------
emit_action() {
  local sid="$1" event="$2" detail="$3"
  if command -v ledger_emit >/dev/null 2>&1; then
    local normalized
    normalized="$(_resumer_normalize_event "$event")"
    ledger_emit "resumer" "$normalized" "session=${sid} orig_event=${event} ${detail}"
  fi
  emit_digest_feed "$sid" "$event" "$detail"
}

# ----------------------------------------------------------------------
# mtime_epoch <file> — portable mtime in epoch seconds (Linux/macOS/
# Git-Bash), matches the convention used by local-edit-gate.sh /
# plan-edit-validator.sh / observed-errors-gate.sh.
# ----------------------------------------------------------------------
mtime_epoch() {
  local f="$1"
  stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0
}

# ----------------------------------------------------------------------
# extract_final_assistant_text <transcript> — same jq extraction pattern
# as session-honesty-gate.sh / continuation-enforcer.sh's
# extract_final_text, reused verbatim for consistency.
# ----------------------------------------------------------------------
extract_final_assistant_text() {
  local transcript="$1"
  [[ -z "$transcript" ]] || [[ ! -f "$transcript" ]] && { echo ""; return 0; }
  command -v jq >/dev/null 2>&1 || { echo ""; return 0; }
  jq -rs '
    [ .[]
      | select((.type? == "assistant")
               or (.message?.role? == "assistant")
               or (.role? == "assistant")) ] as $a
    | if ($a | length) == 0 then ""
      else
        ($a[-1] | (.message?.content // .content // .text // "")) as $c
        | if ($c | type) == "array" then
            ([ $c[] | if type == "object" then (.text // "")
                      elif type == "string" then .
                      else "" end ] | join("\n"))
          elif ($c | type) == "string" then $c
          else ($c | tostring) end
      end
  ' "$transcript" 2>/dev/null
}

# ----------------------------------------------------------------------
# final_marker_keyword <final_text> — echoes DONE|PAUSING|BLOCKED|
# CONTINUING if the last non-empty line carries exactly one such marker,
# empty string otherwise. Same extraction rule as session-honesty-gate.sh.
# ----------------------------------------------------------------------
final_marker_keyword() {
  local final_text="$1"
  [[ -z "$final_text" ]] && { echo ""; return 0; }
  local last_line stripped
  last_line=$(printf '%s\n' "$final_text" | awk 'NF{l=$0} END{print l}')
  stripped=$(printf '%s' "$last_line" \
    | sed -E 's/^[[:space:]>*_`#-]+//' \
    | sed -E 's/[[:space:]*_`]+$//')
  if printf '%s' "$stripped" | grep -qE '^(DONE|PAUSING|BLOCKED|CONTINUING):[[:space:]]'; then
    printf '%s' "$stripped" | sed -E 's/^(DONE|PAUSING|BLOCKED|CONTINUING):.*$/\1/'
  else
    echo ""
  fi
}

# ----------------------------------------------------------------------
# last_event_matches_api_error <transcript> — 0 (true) if the last JSONL
# line, stringified, matches the death-signature regex.
# ----------------------------------------------------------------------
API_ERROR_REGEX='429|529|rate.?limit|overloaded'

last_event_matches_api_error() {
  local transcript="$1"
  [[ -f "$transcript" ]] || return 1
  local last_line
  last_line=$(tail -n 1 "$transcript" 2>/dev/null)
  [[ -z "$last_line" ]] && return 1
  printf '%s' "$last_line" | grep -qiE "$API_ERROR_REGEX"
}

# ----------------------------------------------------------------------
# has_in_progress_todo <transcript> — 0 (true) if the LAST TodoWrite
# tool_use call's todos[] contains a status:"in_progress" entry. Same
# jq extraction as continuation-enforcer.sh's DONE/TodoWrite consistency
# check.
# ----------------------------------------------------------------------
has_in_progress_todo() {
  local transcript="$1"
  command -v jq >/dev/null 2>&1 || return 1
  local todos
  todos=$(jq -c -s '
    [ .[]
      | (.message?.content // .content // [])
      | if type=="array" then .[] else empty end
      | select(type=="object" and (.type? == "tool_use") and (.name? == "TodoWrite"))
      | (.input?.todos // [])
    ] | if length==0 then null else .[-1] end
  ' "$transcript" 2>/dev/null || echo "null")
  [[ -z "$todos" ]] || [[ "$todos" == "null" ]] && return 1
  local n
  n=$(printf '%s' "$todos" | jq -r '[ .[]? | select(.status == "in_progress") ] | length' 2>/dev/null || echo 0)
  n=${n//[!0-9]/}
  [[ -z "$n" ]] && n=0
  [[ "$n" -gt 0 ]]
}

# ----------------------------------------------------------------------
# has_active_plan_activity <transcript> — 0 (true) if an ACTIVE plan's
# basename (docs/plans/*.md, excluding archive/deferred) is referenced
# anywhere in the transcript text AND the transcript has at least one
# event within its own final hour (a best-effort proxy for "was this
# plan touched recently in-session" — precise recency-of-the-mention is
# not mechanically derivable from JSONL without per-line timestamps on
# every event, which not all transcript producers emit; the transcript-
# level "stale >30min but had recent-hour activity" gate above already
# bounds this to sessions that were live in roughly the last hour of
# their own existence).
# ----------------------------------------------------------------------
has_active_plan_activity() {
  local transcript="$1" repo_root="$2"
  [[ -f "$transcript" ]] || return 1
  [[ -z "$repo_root" ]] && return 1
  local plans_dir="$repo_root/docs/plans"
  [[ -d "$plans_dir" ]] || return 1
  local f base
  for f in "$plans_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    if grep -qF "$base" "$transcript" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ----------------------------------------------------------------------
# classify_transcript <transcript> [<repo_root>] [<session_id>]
#
# Sets CLASSIFY_VERDICT (resume|skip), CLASSIFY_REASON (one-line detail).
#
# session_id is optional (defaults to the transcript's basename minus
# .jsonl, matching how scan_and_resume derives it) — passed explicitly so
# --self-test scenarios that use ad-hoc fixture paths still get correct
# tombstone/liveness-guard behavior keyed on the ACTUAL id under test.
# ----------------------------------------------------------------------
CLASSIFY_VERDICT=""
CLASSIFY_REASON=""

classify_transcript() {
  local transcript="$1" repo_root="${2:-}" sid="${3:-}"
  CLASSIFY_VERDICT="skip"
  CLASSIFY_REASON=""

  if [[ ! -f "$transcript" ]]; then
    CLASSIFY_REASON="transcript missing"
    return 0
  fi

  [[ -z "$sid" ]] && sid="$(basename "$transcript" .jsonl)"

  # Guardrail 2: TOMBSTONES — a deliberately-never-resume session is
  # skipped before any other signal is even computed.
  if is_tombstoned "$sid"; then
    CLASSIFY_VERDICT="skip"
    CLASSIFY_REASON="tombstoned — never-resume marker present"
    return 0
  fi

  # Guardrail 3: LIVENESS GUARD — an interactive session is live on this
  # transcript's own repo right now; never headlessly nudge into a tree a
  # human may be actively looking at.
  if liveness_guard_live "$transcript"; then
    local live_cwd
    live_cwd="$(command -v jq >/dev/null 2>&1 && jq -r '.cwd? // empty' "$transcript" 2>/dev/null | head -1)"
    CLASSIFY_VERDICT="skip"
    CLASSIFY_REASON="liveness guard: interactive session live on ${live_cwd:-<unknown repo>}"
    return 0
  fi

  local final_text keyword
  final_text="$(extract_final_assistant_text "$transcript")"
  keyword="$(final_marker_keyword "$final_text")"

  # Natural end always wins, regardless of any other signal.
  if [[ "$keyword" == "DONE" ]] || [[ "$keyword" == "PAUSING" ]]; then
    CLASSIFY_VERDICT="skip"
    CLASSIFY_REASON="natural end (${keyword}: marker) — classify-skip"
    return 0
  fi

  # (a) API-error tail.
  if last_event_matches_api_error "$transcript"; then
    CLASSIFY_VERDICT="resume"
    CLASSIFY_REASON="dead: last event matches API-error signature (429/529/rate-limit/overloaded)"
    return 0
  fi

  # (b) stale + in-flight work.
  local now mtime age_min
  now=$(date -u +%s)
  mtime=$(mtime_epoch "$transcript")
  age_min=$(( (now - mtime) / 60 ))

  if [[ "$age_min" -gt 30 ]]; then
    if [[ "$keyword" == "CONTINUING" ]]; then
      CLASSIFY_VERDICT="resume"
      CLASSIFY_REASON="dead: stale ${age_min}min + CONTINUING: final marker"
      return 0
    fi
    if has_in_progress_todo "$transcript"; then
      CLASSIFY_VERDICT="resume"
      CLASSIFY_REASON="dead: stale ${age_min}min + in_progress task in TodoWrite state"
      return 0
    fi
    if has_active_plan_activity "$transcript" "$repo_root"; then
      CLASSIFY_VERDICT="resume"
      CLASSIFY_REASON="dead: stale ${age_min}min + ACTIVE-plan activity in transcript"
      return 0
    fi
    CLASSIFY_REASON="stale ${age_min}min but no in-flight-work signal — classify-skip"
    return 0
  fi

  CLASSIFY_REASON="not stale (${age_min}min) and no API-error tail — classify-skip"
  return 0
}

# ----------------------------------------------------------------------
# backoff state read/write — ~/.claude/state/resumer/<session-id>.json
# {attempts, next_eligible_epoch, last_event}
# ----------------------------------------------------------------------
backoff_state_path() {
  printf '%s/%s.json' "$(_resumer_state_dir)" "$1"
}

read_backoff_attempts() {
  local sid="$1" path
  path="$(backoff_state_path "$sid")"
  [[ -f "$path" ]] || { echo 0; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.attempts // 0' "$path" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

read_backoff_next_eligible() {
  local sid="$1" path
  path="$(backoff_state_path "$sid")"
  [[ -f "$path" ]] || { echo 0; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.next_eligible_epoch // 0' "$path" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_backoff_state() {
  local sid="$1" attempts="$2" next_eligible="$3" last_event="$4" path
  path="$(backoff_state_path "$sid")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson a "$attempts" --argjson n "$next_eligible" --arg e "$last_event" \
      '{attempts:$a, next_eligible_epoch:$n, last_event:$e}' > "$path" 2>/dev/null || true
  else
    printf '{"attempts":%s,"next_eligible_epoch":%s,"last_event":"%s"}\n' \
      "$attempts" "$next_eligible" "${last_event//\"/\\\"}" > "$path" 2>/dev/null || true
  fi
}

# ----------------------------------------------------------------------
# backoff_minutes_for_attempt <attempt_number (1-based)> — echoes the
# BACKOFF_MINUTES entry, clamped to the last entry if attempt exceeds the
# array length.
# ----------------------------------------------------------------------
backoff_minutes_for_attempt() {
  local n="$1"
  local idx=$((n - 1))
  local last_idx=$(( ${#BACKOFF_MINUTES[@]} - 1 ))
  [[ "$idx" -lt 0 ]] && idx=0
  [[ "$idx" -gt "$last_idx" ]] && idx=$last_idx
  echo "${BACKOFF_MINUTES[$idx]}"
}

# ----------------------------------------------------------------------
# build_resume_command <session_id> — echoes the VERBATIM command string
# that would be executed. Kept as a pure string-builder (no side effects)
# so --self-test can assert it verbatim without any process invocation.
# ----------------------------------------------------------------------
build_resume_command() {
  local sid="$1"
  printf 'claude -p --resume %s "%s"' "$sid" "$RESUME_NUDGE"
}

# ----------------------------------------------------------------------
# build_fallback_command <cwd> <plan_hint> — echoes the VERBATIM
# fresh-spawn fallback command string for an unresumable session.
# ----------------------------------------------------------------------
build_fallback_command() {
  local cwd="$1"
  local nudge="re-read SCRATCHPAD.md, the ACTIVE plan, and NEEDS-YOU.md in ${cwd}; continue the in-flight task from that substrate"
  printf 'claude -p "%s"' "$nudge"
}

# ----------------------------------------------------------------------
# perform_resume <session_id> <transcript> <reason> <repo_root>
#
# The one live-action call site. Under HARNESS_SELFTEST=1 this NEVER
# invokes the real `claude` binary — it appends the constructed command
# to RESUMER_DRYRUN_LOG (required by the self-test harness) and returns a
# synthetic exit code from RESUMER_SELFTEST_RESUME_RC (default 0) so
# backoff-arithmetic and unresumable-fallback scenarios are both
# exercisable without a live CLI dependency.
# ----------------------------------------------------------------------
perform_resume() {
  local sid="$1" transcript="$2" reason="$3" repo_root="$4"

  local attempts next_eligible now
  attempts="$(read_backoff_attempts "$sid")"
  next_eligible="$(read_backoff_next_eligible "$sid")"
  now=$(date -u +%s)

  if [[ "$attempts" -ge "$MAX_ATTEMPTS" ]]; then
    emit_action "$sid" "escalation" "max attempts (${MAX_ATTEMPTS}) reached — no further resume attempted; ${reason}"
    return 0
  fi

  if [[ "$next_eligible" -gt "$now" ]]; then
    local wait_min=$(( (next_eligible - now) / 60 ))
    emit_action "$sid" "backoff-wait" "not yet eligible (${wait_min}min remaining); ${reason}"
    return 0
  fi

  local next_attempt=$((attempts + 1))
  local cmd
  cmd="$(build_resume_command "$sid")"

  # Guardrail 4: SHADOW MODE — classification + every guardrail above
  # already ran for real; log what WOULD happen and stop. No backoff state
  # is written (a shadow pass must be safely re-runnable indefinitely) and
  # no storm-cap slot is consumed (shadow mode never contends with live
  # resume traffic for the cap). Checked before the storm cap itself so a
  # shadow pass's digest line always reflects "this session would have
  # been resumed", independent of how much of the live cap happens to be
  # free at the moment the shadow pass runs.
  if [[ "${RESUMER_SHADOW:-0}" == "1" ]]; then
    emit_action "$sid" "would-have-resumed" "would-have-resumed ${sid} (${reason})"
    return 0
  fi

  # Guardrail 1: STORM CAP — if the rolling-hour cap is already spent,
  # queue this session (oldest-transcript-first ordering is achieved by
  # scan_and_resume iterating transcripts in mtime-ascending order before
  # calling here — see scan_and_resume) rather than firing another
  # `claude` process. Logged, re-evaluated next pass; no backoff state
  # written (this is not a failure, just a deferral).
  if ! storm_cap_has_room; then
    emit_action "$sid" "storm-cap-queued" "resume queued (storm cap); ${reason}"
    return 0
  fi
  # Committed to taking an action this pass — record it against the
  # rolling-hour cap BEFORE dispatching, whether via the self-test dryrun
  # path or the live path (both count identically toward the cap).
  storm_cap_record_action

  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s\n' "$cmd" >> "${RESUMER_DRYRUN_LOG:-/dev/null}" 2>/dev/null || true
    local rc="${RESUMER_SELFTEST_RESUME_RC:-0}"
    if [[ "$rc" -eq 0 ]]; then
      emit_action "$sid" "resume-attempt" "attempt ${next_attempt}/${MAX_ATTEMPTS}: ${reason}"
      local wait_min
      wait_min="$(backoff_minutes_for_attempt "$next_attempt")"
      write_backoff_state "$sid" "$next_attempt" $((now + wait_min * 60)) "resume-attempt"
    else
      emit_action "$sid" "resume-unresumable" "attempt ${next_attempt}/${MAX_ATTEMPTS}: --resume exited ${rc} (unresumable) — falling back to fresh-spawn; ${reason}"
      local cwd
      cwd="$(jq -r '.cwd? // empty' "$transcript" 2>/dev/null | head -1)"
      [[ -z "$cwd" ]] && cwd="$repo_root"
      local fallback_cmd
      fallback_cmd="$(build_fallback_command "$cwd")"
      printf '%s\n' "$fallback_cmd" >> "${RESUMER_DRYRUN_LOG:-/dev/null}" 2>/dev/null || true
      emit_action "$sid" "resume-fallback" "fresh-spawn fallback constructed for cwd=${cwd}"
      local wait_min
      wait_min="$(backoff_minutes_for_attempt "$next_attempt")"
      write_backoff_state "$sid" "$next_attempt" $((now + wait_min * 60)) "resume-fallback"
    fi
    return 0
  fi

  # ---- LIVE path: actually invoke the CLI. Never reached under
  # --self-test / HARNESS_SELFTEST=1 (see gate above). ----
  emit_action "$sid" "resume-attempt" "attempt ${next_attempt}/${MAX_ATTEMPTS}: ${reason}"
  local out rc
  out=$(claude -p --resume "$sid" "$RESUME_NUDGE" 2>&1)
  rc=$?
  local wait_min
  wait_min="$(backoff_minutes_for_attempt "$next_attempt")"
  if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiE 'no (such|conversation)|unresumable|not found|unknown session'; then
    emit_action "$sid" "resume-unresumable" "--resume exited ${rc} (unresumable): ${out:0:200}"
    local cwd
    cwd="$(jq -r '.cwd? // empty' "$transcript" 2>/dev/null | head -1)"
    [[ -z "$cwd" ]] && cwd="$repo_root"
    local fallback_nudge="re-read SCRATCHPAD.md, the ACTIVE plan, and NEEDS-YOU.md in ${cwd}; continue the in-flight task from that substrate"
    ( cd "$cwd" 2>/dev/null && claude -p "$fallback_nudge" >/dev/null 2>&1 & )
    emit_action "$sid" "resume-fallback" "fresh-spawn fallback launched for cwd=${cwd}"
  fi
  write_backoff_state "$sid" "$next_attempt" $((now + wait_min * 60)) "resume-attempt-rc-${rc}"
}

# ----------------------------------------------------------------------
# scan_and_resume — the live entry point: enumerate transcripts under
# ~/.claude/projects/*/, filter to last-48h mtime, classify, act.
#
# Candidates are processed OLDEST-TRANSCRIPT-MTIME-FIRST across the WHOLE
# scan (not just within one project dir) so that when the storm cap (E.7
# activation guardrail 1) is exhausted mid-pass, the sessions that get
# queued are consistently the newer-mtime ones — a stable, predictable
# "oldest first" ordering rather than an accident of directory iteration
# order.
# ----------------------------------------------------------------------
scan_and_resume() {
  local projects_root repo_root
  projects_root="$(_resumer_projects_root)"
  [[ -d "$projects_root" ]] || { echo "session-resumer: no projects root at ${projects_root} — nothing to scan"; return 0; }
  repo_root="$(nl_repo_root 2>/dev/null || echo "")"

  local now cutoff
  now=$(date -u +%s)
  cutoff=$((now - 48*3600))

  # Build a "mtime<TAB>path" list of in-window transcripts, then sort
  # numerically ascending on mtime (oldest first) before acting on any of
  # them — portable (no mapfile/declare -A; bash 3.2 / Git-Bash safe).
  local proj_dir f mtime sid list_file
  list_file="$(mktemp 2>/dev/null || printf '%s/resumer-scan.%s' "${TMPDIR:-/tmp}" "$$")"
  : > "$list_file"
  for proj_dir in "$projects_root"/*/; do
    [[ -d "$proj_dir" ]] || continue
    for f in "$proj_dir"*.jsonl; do
      [[ -f "$f" ]] || continue
      mtime=$(mtime_epoch "$f")
      [[ "$mtime" -lt "$cutoff" ]] && continue
      printf '%s\t%s\n' "$mtime" "$f" >> "$list_file"
    done
  done

  local line
  while IFS=$'\t' read -r mtime f; do
    [[ -z "$f" ]] && continue
    sid="$(basename "$f" .jsonl)"
    classify_transcript "$f" "$repo_root" "$sid"
    if [[ "$CLASSIFY_VERDICT" == "skip" ]]; then
      emit_action "$sid" "classify-skip" "$CLASSIFY_REASON"
    else
      perform_resume "$sid" "$f" "$CLASSIFY_REASON" "$repo_root"
    fi
  done < <(sort -n -k1,1 "$list_file" 2>/dev/null)

  rm -f "$list_file" 2>/dev/null || true
}

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'srst')
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export SIGNAL_LEDGER_PATH="$TMP/ledger.jsonl"
  export RESUMER_STATE_DIR="$TMP/resumer-state"
  export RESUMER_DRYRUN_LOG="$TMP/dryrun.log"
  # Sandbox the ISL (interactive-session-lock) lib's own state too — this
  # script now sources it for the LIVENESS GUARD (activation guardrail 3),
  # and its self-test scenarios below construct fixture liveness signals
  # that must never touch the real ~/.claude/projects or ~/.claude/logs.
  export ISL_PROJECTS_ROOT="$TMP/isl-projects"
  export ISL_LOG_FILE="$TMP/isl-refusal.log"
  mkdir -p "$RESUMER_STATE_DIR" "$ISL_PROJECTS_ROOT"
  unset CLAUDE_CODE_SESSION_ID
  unset RESUMER_SHADOW

  FIXDIR_SRC="$SCRIPT_DIR/../tests/fixtures/resumer"
  # Work on COPIES under TMP so the self-test never mutates the checked-in
  # fixture files' mtimes on disk (mtime is load-bearing for this script's
  # own staleness logic — leaving it pristine avoids any risk of a test
  # run silently poisoning a later run's "not stale" baseline).
  FIXDIR="$TMP/fixtures"
  mkdir -p "$FIXDIR"
  cp "$FIXDIR_SRC"/*.jsonl "$FIXDIR/"

  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  # backdate_mtime <file> <seconds-ago> — portable mtime backdating with a
  # HARD assertion the backdate actually took (a silently-failed backdate
  # would make the staleness scenarios pass or fail for the wrong reason).
  backdate_mtime() {
    local f="$1" secs_ago="$2" target
    target=$(( $(date -u +%s) - secs_ago ))
    touch -d "@${target}" "$f" 2>/dev/null \
      || touch -t "$(date -u -v-"${secs_ago}"S +%Y%m%d%H%M.%S 2>/dev/null)" "$f" 2>/dev/null \
      || true
    local got
    got=$(mtime_epoch "$f")
    local diff=$(( got - target ))
    [[ "$diff" -lt 0 ]] && diff=$(( -diff ))
    if [[ "$diff" -gt 5 ]]; then
      echo "  FAIL: backdate_mtime could not backdate $f (wanted ~${target}, got ${got}) — staleness scenarios depending on this file are UNRELIABLE on this platform" >&2
      FAILED=$((FAILED+1))
      return 1
    fi
    return 0
  }

  # ------------------------------------------------------------
  # Scenario 1: dead-429 fixture classifies as resume, and the resume
  # command is constructed VERBATIM (assert the exact string).
  # ------------------------------------------------------------
  echo "Scenario 1: dead-429 classifies resume; resume command asserted verbatim"
  : > "$RESUMER_DRYRUN_LOG"
  rm -f "$RESUMER_STATE_DIR"/*.json "$RESUMER_STATE_DIR"/storm-cap.log
  classify_transcript "$FIXDIR/dead-429.jsonl" ""
  if [[ "$CLASSIFY_VERDICT" == "resume" ]]; then
    ok "dead-429 classifies as resume"
  else
    no "expected resume, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi
  perform_resume "dead-429-sess" "$FIXDIR/dead-429.jsonl" "$CLASSIFY_REASON" ""
  expected_cmd='claude -p --resume dead-429-sess "re-read SCRATCHPAD.md + NEEDS-YOU.md, verify branch state, continue the in-flight task"'
  actual_cmd="$(head -1 "$RESUMER_DRYRUN_LOG")"
  if [[ "$actual_cmd" == "$expected_cmd" ]]; then
    ok "resume command constructed VERBATIM: $actual_cmd"
  else
    no "resume command mismatch. expected [$expected_cmd] got [$actual_cmd]"
  fi

  # ------------------------------------------------------------
  # Scenario 2: dead-stale-with-in-flight fixture -> resume.
  # ------------------------------------------------------------
  echo "Scenario 2: dead-stale-with-in-flight classifies resume"
  backdate_mtime "$FIXDIR/dead-stale-with-in-flight.jsonl" 3600
  classify_transcript "$FIXDIR/dead-stale-with-in-flight.jsonl" ""
  if [[ "$CLASSIFY_VERDICT" == "resume" ]]; then
    ok "dead-stale-with-in-flight classifies as resume ($CLASSIFY_REASON)"
  else
    no "expected resume, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi

  # ------------------------------------------------------------
  # Scenario 3: natural-DONE fixture -> skip, regardless of staleness.
  # ------------------------------------------------------------
  echo "Scenario 3: natural-DONE classifies skip"
  backdate_mtime "$FIXDIR/natural-DONE.jsonl" 3600
  classify_transcript "$FIXDIR/natural-DONE.jsonl" ""
  if [[ "$CLASSIFY_VERDICT" == "skip" ]] && printf '%s' "$CLASSIFY_REASON" | grep -qi "natural end"; then
    ok "natural-DONE classifies as skip ($CLASSIFY_REASON)"
  else
    no "expected natural-end skip, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi

  # ------------------------------------------------------------
  # Scenario 4: PAUSING fixture -> skip.
  # ------------------------------------------------------------
  echo "Scenario 4: PAUSING classifies skip"
  classify_transcript "$FIXDIR/PAUSING.jsonl" ""
  if [[ "$CLASSIFY_VERDICT" == "skip" ]] && printf '%s' "$CLASSIFY_REASON" | grep -qi "natural end"; then
    ok "PAUSING classifies as skip ($CLASSIFY_REASON)"
  else
    no "expected natural-end skip, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi

  # ------------------------------------------------------------
  # Scenario 5: backoff arithmetic — 2nd failure -> 15 min wait.
  # ------------------------------------------------------------
  echo "Scenario 5: backoff arithmetic (2nd failure -> 15min)"
  rm -f "$RESUMER_STATE_DIR"/backoff-sess.json "$RESUMER_STATE_DIR"/storm-cap.log
  : > "$RESUMER_DRYRUN_LOG"
  now=$(date -u +%s)
  # Seed state as if 1 attempt already happened, eligible now.
  write_backoff_state "backoff-sess" 1 "$now" "resume-attempt"
  perform_resume "backoff-sess" "$FIXDIR/dead-429.jsonl" "test" ""
  next_eligible="$(read_backoff_next_eligible "backoff-sess")"
  attempts_after="$(read_backoff_attempts "backoff-sess")"
  expected_wait_sec=$((15*60))
  actual_wait_sec=$((next_eligible - now))
  # allow +/-2s slack for wall-clock jitter across the two `date` calls
  diff=$(( actual_wait_sec - expected_wait_sec ))
  [[ "$diff" -lt 0 ]] && diff=$(( -diff ))
  if [[ "$attempts_after" == "2" ]] && [[ "$diff" -le 2 ]]; then
    ok "2nd failure schedules ~15min backoff (attempts=$attempts_after, wait=${actual_wait_sec}s)"
  else
    no "expected attempts=2 wait=~900s, got attempts=$attempts_after wait=${actual_wait_sec}s"
  fi

  # ------------------------------------------------------------
  # Scenario 6: max-attempts cap — 6th eligible attempt -> escalation,
  # no resume command constructed.
  # ------------------------------------------------------------
  echo "Scenario 6: max-attempts cap (6th eligible -> escalation, no command)"
  rm -f "$RESUMER_STATE_DIR"/capped-sess.json "$RESUMER_STATE_DIR"/storm-cap.log
  : > "$RESUMER_DRYRUN_LOG"
  write_backoff_state "capped-sess" 5 "$(date -u +%s)" "resume-attempt"
  before_lines=$(wc -l < "$RESUMER_DRYRUN_LOG" 2>/dev/null | tr -d ' ')
  perform_resume "capped-sess" "$FIXDIR/dead-429.jsonl" "test" ""
  after_lines=$(wc -l < "$RESUMER_DRYRUN_LOG" 2>/dev/null | tr -d ' ')
  [[ -z "$before_lines" ]] && before_lines=0
  [[ -z "$after_lines" ]] && after_lines=0
  escalation_logged=0
  if [[ -f "$TMP/resumer-state/digest-feed.jsonl" ]] && grep -q '"event":"escalation"' "$TMP/resumer-state/digest-feed.jsonl" 2>/dev/null; then
    escalation_logged=1
  fi
  if [[ "$after_lines" == "$before_lines" ]] && [[ "$escalation_logged" == "1" ]]; then
    ok "6th eligible attempt escalates with no new resume command constructed"
  else
    no "expected no new dryrun-log line + escalation digest event; before=$before_lines after=$after_lines escalation_logged=$escalation_logged"
  fi

  # ------------------------------------------------------------
  # Scenario 7: unresumable --resume error triggers fresh-spawn fallback.
  # ------------------------------------------------------------
  echo "Scenario 7: unresumable --resume error falls back to fresh-spawn"
  rm -f "$RESUMER_STATE_DIR"/unresumable-sess.json "$RESUMER_STATE_DIR"/storm-cap.log
  : > "$RESUMER_DRYRUN_LOG"
  RESUMER_SELFTEST_RESUME_RC=1 perform_resume "unresumable-sess" "$FIXDIR/dead-429.jsonl" "test" "$TMP"
  if grep -q '^claude -p "re-read SCRATCHPAD.md' "$RESUMER_DRYRUN_LOG"; then
    ok "unresumable error produces a fresh-spawn fallback command"
  else
    no "expected a fallback 'claude -p' command in dryrun log, got: $(cat "$RESUMER_DRYRUN_LOG")"
  fi

  # ------------------------------------------------------------
  # Scenario 8: not-stale, no API-error, no marker -> skip (quiet, not a
  # false positive on a normal in-progress recent session).
  # ------------------------------------------------------------
  echo "Scenario 8: fresh non-dead transcript classifies skip (no false positive)"
  FRESH="$TMP/fresh.jsonl"
  jq -cn '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"still working on it"}]}}' > "$FRESH"
  classify_transcript "$FRESH" ""
  if [[ "$CLASSIFY_VERDICT" == "skip" ]]; then
    ok "fresh, non-dead transcript is not falsely resumed ($CLASSIFY_REASON)"
  else
    no "expected skip on a fresh non-dead transcript, got $CLASSIFY_VERDICT"
  fi

  # ------------------------------------------------------------
  # Scenario 9: digest-feed file gets a line per emit_action call.
  # ------------------------------------------------------------
  echo "Scenario 9: emit_action writes a digest-feed line"
  rm -f "$TMP/resumer-state/digest-feed.jsonl"
  emit_action "digest-test-sess" "classify-skip" "unit test detail"
  if [[ -f "$TMP/resumer-state/digest-feed.jsonl" ]] && grep -q "digest-test-sess" "$TMP/resumer-state/digest-feed.jsonl"; then
    ok "digest-feed.jsonl received the emitted action"
  else
    no "expected digest-feed.jsonl to contain the emitted session id"
  fi

  # ------------------------------------------------------------
  # Scenario 10 (activation guardrail 1 — STORM CAP): 3 dead sessions,
  # cap=2 -> exactly 2 resumes fire and 1 is queued (storm-cap-queued).
  # ------------------------------------------------------------
  echo "Scenario 10: storm cap (3 dead, cap 2 -> 2 resumes + 1 queued)"
  rm -f "$RESUMER_STATE_DIR"/storm-*.json "$RESUMER_STATE_DIR"/storm-cap.log
  rm -f "$TMP/resumer-state/digest-feed.jsonl"
  : > "$RESUMER_DRYRUN_LOG"
  RESUMER_STORM_CAP=2
  export RESUMER_STORM_CAP
  perform_resume "storm-a" "$FIXDIR/dead-429.jsonl" "test" ""
  perform_resume "storm-b" "$FIXDIR/dead-429.jsonl" "test" ""
  perform_resume "storm-c" "$FIXDIR/dead-429.jsonl" "test" ""
  unset RESUMER_STORM_CAP
  resume_cmd_lines=$(wc -l < "$RESUMER_DRYRUN_LOG" 2>/dev/null | tr -d ' ')
  queued_count=0
  if [[ -f "$TMP/resumer-state/digest-feed.jsonl" ]]; then
    queued_count=$(grep -c '"event":"storm-cap-queued"' "$TMP/resumer-state/digest-feed.jsonl" 2>/dev/null | tr -d ' ')
  fi
  [[ -z "$resume_cmd_lines" ]] && resume_cmd_lines=0
  [[ -z "$queued_count" ]] && queued_count=0
  if [[ "$resume_cmd_lines" == "2" ]] && [[ "$queued_count" == "1" ]]; then
    ok "storm cap allows exactly 2 resumes and queues the 3rd (commands=$resume_cmd_lines queued=$queued_count)"
  else
    no "expected 2 resume commands + 1 queued, got commands=$resume_cmd_lines queued=$queued_count"
  fi

  # ------------------------------------------------------------
  # Scenario 11 (activation guardrail 2 — TOMBSTONES): --never marks a
  # session id; classify_transcript then skips it even though the
  # underlying transcript is the dead-429 fixture (would otherwise resume).
  # ------------------------------------------------------------
  echo "Scenario 11: tombstone (--never) skips even a dead-429 transcript"
  rm -rf "$RESUMER_STATE_DIR/never"
  tombstone_session "tombstoned-sess" >/dev/null
  if is_tombstoned "tombstoned-sess"; then
    ok "tombstone_session created a discoverable marker"
  else
    no "tombstone_session did not create a marker is_tombstoned can see"
  fi
  classify_transcript "$FIXDIR/dead-429.jsonl" "" "tombstoned-sess"
  if [[ "$CLASSIFY_VERDICT" == "skip" ]] && printf '%s' "$CLASSIFY_REASON" | grep -qi "tombstoned"; then
    ok "tombstoned session classifies skip even with a dead-429 signature ($CLASSIFY_REASON)"
  else
    no "expected tombstoned skip, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi
  # A non-tombstoned session id on the SAME transcript still resumes —
  # proves the skip is keyed on the id, not a global switch.
  classify_transcript "$FIXDIR/dead-429.jsonl" "" "not-tombstoned-sess"
  if [[ "$CLASSIFY_VERDICT" == "resume" ]]; then
    ok "a different (non-tombstoned) session id on the same transcript still resumes"
  else
    no "expected resume for a non-tombstoned id, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi

  # ------------------------------------------------------------
  # Scenario 12 (activation guardrail 3 — LIVENESS GUARD): a transcript
  # whose cwd has a FRESH interactive-session-lock signal classifies skip
  # even though its own content is the dead-429 death signature.
  # ------------------------------------------------------------
  echo "Scenario 12: liveness guard skips a dead-429 transcript whose repo has a live interactive session"
  LIVE_REPO="$TMP/live-repo"
  mkdir -p "$LIVE_REPO"
  LIVE_TRANSCRIPT="$TMP/liveness-fixture.jsonl"
  {
    printf '{"cwd":"%s","type":"user","message":{"role":"user","content":[{"type":"text","text":"go ahead"}]}}\n' "$LIVE_REPO"
    printf '{"cwd":"%s","type":"system","subtype":"api_error","isApiErrorMessage":true,"result":"error","message":"Error: 429 rate_limit_error"}\n' "$LIVE_REPO"
  } > "$LIVE_TRANSCRIPT"
  # Sanity check: WITHOUT any liveness signal, this fixture resumes (proves
  # the skip below is caused by the liveness guard, not some other factor).
  classify_transcript "$LIVE_TRANSCRIPT" "" "liveness-sanity-sess"
  if [[ "$CLASSIFY_VERDICT" == "resume" ]]; then
    ok "liveness fixture resumes when no interactive session is live (sanity baseline)"
  else
    no "expected resume as the sanity baseline, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi
  # Now make the repo's own transcript slug dir contain a fresh .jsonl —
  # the ISL "any fresh transcript under this repo's slug" liveness signal.
  isl_slug="$(isl_project_slug_candidates "$LIVE_REPO" 2>/dev/null | head -n 1)"
  isl_tdir="$ISL_PROJECTS_ROOT/$isl_slug"
  mkdir -p "$isl_tdir"
  : > "$isl_tdir/some-other-session.jsonl"
  classify_transcript "$LIVE_TRANSCRIPT" "" "liveness-guarded-sess"
  if [[ "$CLASSIFY_VERDICT" == "skip" ]] && printf '%s' "$CLASSIFY_REASON" | grep -qi "liveness guard"; then
    ok "liveness guard skips a dead-429 transcript whose repo has a live interactive session ($CLASSIFY_REASON)"
  else
    no "expected liveness-guard skip, got $CLASSIFY_VERDICT ($CLASSIFY_REASON)"
  fi

  # ------------------------------------------------------------
  # Scenario 13 (activation guardrail 4 — SHADOW MODE): RESUMER_SHADOW=1
  # logs "would-have-resumed" and does NOT construct/execute any command
  # or write backoff state.
  # ------------------------------------------------------------
  echo "Scenario 13: shadow mode logs would-have-resumed, never executes, never writes backoff state"
  rm -f "$RESUMER_STATE_DIR"/shadow-sess.json
  rm -f "$TMP/resumer-state/digest-feed.jsonl"
  : > "$RESUMER_DRYRUN_LOG"
  RESUMER_SHADOW=1 perform_resume "shadow-sess" "$FIXDIR/dead-429.jsonl" "test reason" ""
  shadow_cmd_lines=$(wc -l < "$RESUMER_DRYRUN_LOG" 2>/dev/null | tr -d ' ')
  [[ -z "$shadow_cmd_lines" ]] && shadow_cmd_lines=0
  shadow_logged=0
  if [[ -f "$TMP/resumer-state/digest-feed.jsonl" ]] && grep -q '"event":"would-have-resumed"' "$TMP/resumer-state/digest-feed.jsonl" \
     && grep -q 'would-have-resumed shadow-sess' "$TMP/resumer-state/digest-feed.jsonl"; then
    shadow_logged=1
  fi
  shadow_backoff_attempts="$(read_backoff_attempts "shadow-sess")"
  if [[ "$shadow_cmd_lines" == "0" ]] && [[ "$shadow_logged" == "1" ]] && [[ "$shadow_backoff_attempts" == "0" ]]; then
    ok "shadow mode logs would-have-resumed, executes nothing, writes no backoff state"
  else
    no "expected 0 dryrun-log lines + would-have-resumed logged + 0 backoff attempts; got cmd_lines=$shadow_cmd_lines logged=$shadow_logged attempts=$shadow_backoff_attempts"
  fi
  # Shadow mode also never consumes a storm-cap slot: run it repeatedly
  # past the default cap and confirm live resume capacity is untouched.
  rm -f "$RESUMER_STATE_DIR"/storm-cap.log
  RESUMER_STORM_CAP=1
  export RESUMER_STORM_CAP
  RESUMER_SHADOW=1 perform_resume "shadow-x" "$FIXDIR/dead-429.jsonl" "test" ""
  RESUMER_SHADOW=1 perform_resume "shadow-y" "$FIXDIR/dead-429.jsonl" "test" ""
  RESUMER_SHADOW=1 perform_resume "shadow-z" "$FIXDIR/dead-429.jsonl" "test" ""
  unset RESUMER_STORM_CAP
  shadow_room="$(storm_cap_has_room && echo yes || echo no)"
  if [[ "$shadow_room" == "yes" ]]; then
    ok "repeated shadow-mode passes never consume the storm-cap budget"
  else
    no "expected storm-cap room to remain untouched after shadow-mode passes, got: $shadow_room"
  fi

  # ------------------------------------------------------------
  # Scenario 14 (Wave O task O.1, specs-o §O.1 deliverable 2, contract C2):
  # the SIGNAL LEDGER (not the digest feed — that stays on the original
  # vocabulary, proven unaffected by every PASS above) carries the
  # NORMALIZED event name, with the ORIGINAL name preserved verbatim in the
  # detail text. Reuses ledger content already produced by earlier
  # scenarios in THIS SAME self-test run (Scenario 6 escalation, Scenario 7
  # resume-fallback/resume-unresumable, Scenario 13 would-have-resumed) —
  # SIGNAL_LEDGER_PATH has been the one fixture path ($TMP/ledger.jsonl)
  # for the whole run, so every prior emit_action call already landed here.
  # ------------------------------------------------------------
  echo "Scenario 14: ledger event names are normalized to contract C2; original names preserved in detail"
  if [[ -f "$SIGNAL_LEDGER_PATH" ]]; then
    if grep -q '"gate":"resumer".*"event":"throttle-detected".*orig_event=escalation' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "escalation normalizes to throttle-detected (orig_event preserved)"
    else
      no "expected a resumer/throttle-detected ledger line with orig_event=escalation"
    fi
    if grep -q '"gate":"resumer".*"event":"session-resume".*orig_event=resume-fallback' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "resume-fallback normalizes to session-resume (orig_event preserved)"
    else
      no "expected a resumer/session-resume ledger line with orig_event=resume-fallback"
    fi
    if grep -q '"gate":"resumer".*"event":"session-resume".*orig_event=would-have-resumed' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "would-have-resumed normalizes to session-resume (orig_event preserved)"
    else
      no "expected a resumer/session-resume ledger line with orig_event=would-have-resumed"
    fi
    if grep -q '"gate":"resumer".*"event":"throttle-detected".*orig_event=storm-cap-queued' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "storm-cap-queued normalizes to throttle-detected (orig_event preserved)"
    else
      no "expected a resumer/throttle-detected ledger line with orig_event=storm-cap-queued"
    fi
    if grep -q '"gate":"resumer".*"event":"classify-skip"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "classify-skip passes through unchanged (not a resume/throttle event)"
    else
      no "expected a resumer/classify-skip ledger line to pass through unchanged"
    fi
    if ! grep -q '"gate":"resumer".*"event":"escalation"' "$SIGNAL_LEDGER_PATH" 2>/dev/null \
       && ! grep -q '"gate":"resumer".*"event":"resume-fallback"' "$SIGNAL_LEDGER_PATH" 2>/dev/null \
       && ! grep -q '"gate":"resumer".*"event":"would-have-resumed"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then
      ok "raw pre-normalization event names never appear as the ledger's own event field"
    else
      no "a raw (non-normalized) event name leaked into the ledger's event field"
    fi
  else
    no "expected \$SIGNAL_LEDGER_PATH ($SIGNAL_LEDGER_PATH) to exist after this self-test's many emit_action calls"
  fi
  # Digest-feed side stays on the ORIGINAL vocabulary — re-assert directly
  # against the content Scenario 13 (immediately above) just wrote (earlier
  # scenarios' digest-feed content, e.g. Scenario 6's "escalation", is
  # legitimately overwritten/rm'd by Scenarios 10-13's own setup steps —
  # this reuses whatever is CURRENT at this point in the run rather than a
  # stale target).
  if [[ -f "$TMP/resumer-state/digest-feed.jsonl" ]] && grep -q '"event":"would-have-resumed"' "$TMP/resumer-state/digest-feed.jsonl" 2>/dev/null; then
    ok "digest-feed.jsonl keeps the ORIGINAL event name (would-have-resumed) unaffected by ledger normalization"
  else
    no "expected digest-feed.jsonl to still carry the original 'would-have-resumed' event name"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# main (live invocation, not under --self-test)
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--never" ]]; then
  tombstone_session "${2:-}"
  exit $?
fi

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" != "--self-test" ]] && [[ "${1:-}" != "--never" ]]; then
  scan_and_resume
fi
