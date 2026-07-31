#!/usr/bin/env bash
# limit-resume.sh — bounded, per-session, turn-scoped auto-resume watchdog.
#
# ============================================================
# WHY THIS EXISTS (operator, 2026-07-30: "I'm guessing you're still not
# retriggering yourself after the limits reset. How do we make that
# actually work?")
# ============================================================
#
# The machine-local, hand-made predecessor (~/.claude/state/limit-resume/
# resume.sh + LaunchAgent local.neurallace.limit-resume, never in this
# repo) had three defects, diagnosed and fixed here:
#   DEFECT 1 (PATH): launchd's environment lacks Homebrew, so `env node`
#     (the `claude` CLI's own shebang) failed on every tick. Fixed by
#     appending Homebrew/local bin dirs to PATH at the top of this
#     script (never prepending — a self-test stub earlier on PATH must
#     never be shadowed by a real `claude`), and PROVEN under a REAL
#     launchd-triggered tick (`launchctl kickstart -k`) against the REAL
#     `claude` binary this session — see the completion report for the
#     log lines.
#   DEFECT 2 (never auto-armed): fixed by splicing `arm` into
#     SessionStart AND UserPromptSubmit (turn-scoped — see below) and
#     `disarm` into Stop.
#   DEFECT 3 (hardcoded ids): fixed — the session id comes from
#     $CLAUDE_CODE_SESSION_ID at arm time; the resume prompt is generic.
#
# ============================================================
# REVIEW FIXES (harness-reviewer REJECT, 2026-07-30 — every point below
# is a direct response to a PROVEN finding, not a speculative hardening)
# ============================================================
#   F1/F6 (Critical+Major): the ORIGINAL cmd_tick had no liveness
#     discriminator and no initial floor — since the marker is armed
#     EXACTLY while a turn is in flight (by the turn-scoped design's own
#     construction), the reviewer PROVED a tick landing seconds after arm
#     spawns `claude -p --resume` against a live, healthy, mid-turn
#     session, then deletes the marker on the (also live) success,
#     destroying the very protection the turn needed. Fixed with TWO
#     independent gates, both must pass before any attempt:
#       (a) MIN_SILENCE_SECONDS floor (default 1800s = 30min, matching
#           both ADR-061 D4's own cooldown floor and hb-lib's
#           OBS_STALE_MIN default) — armed_at must be at least this old.
#           Deterministic; works even with zero heartbeat coverage.
#       (b) hooks/lib/session-heartbeat-lib.sh's hb_classify (the SAME
#           canonical oracle scripts/session-resumer.sh already uses,
#           ADR-061 D1/D3) — if a heartbeat file exists for the tracked
#           session and classifies as `live`, the attempt is skipped
#           regardless of the floor (a still-live long turn must never
#           be resumed no matter how old armed_at is). hb_is_stale is
#           ALREADY transcript-mtime-aware for exactly the "heartbeats
#           only refresh at Stop, so a mid-turn session's own heartbeat
#           looks stale" case (session-heartbeat-lib.sh's own C1 join,
#           not reinvented here). Best-effort: missing heartbeat data
#           degrades to floor-only, never to "assume dead" (mirrors
#           session-resumer.sh's own "a session this script cannot see
#           clearly is skipped, never resumed" discipline where it CAN
#           tell; where it genuinely cannot tell, the floor is the
#           safety net, chosen because heartbeat coverage for the
#           single main-checkout session this mechanism tracks already
#           exists via the SAME hook files this splices into).
#   F3 (Critical): state was a SINGLE machine-global marker, so two
#     concurrent interactive sessions in two different (non-worktree)
#     repos on the same machine would silently clobber each other's
#     tracked session. Fixed: every marker/attempts/next-eligible/giveup
#     file is now keyed by session id under $STATE_DIR/armed/<key>.*;
#     `disarm` removes only the file matching ITS OWN session id (arg or
#     $CLAUDE_CODE_SESSION_ID), never "the" marker. The mkdir-based
#     concurrent-spawn LOCK stays a single global lock (FM-037
#     prevention item 2's "independent hard spawn breaker" — at most one
#     live `claude` child from this mechanism at any time, machine-wide,
#     regardless of how many sessions are tracked) and `tick` attempts at
#     most ONE resume per invocation even if multiple sessions are armed.
#   F5 (Major): self-test scenarios asserting a NEGATIVE ("no marker was
#     written") passed vacuously if `git worktree add` itself failed
#     silently. Fixed: both worktree-creating scenarios now assert the
#     worktree directory exists before trusting the negative assertion.
#   F9 (Minor): `cd "$cwd" 2>/dev/null; NL_HOOK_REENTRY=1 ...` (a `;`, not
#     `&&`) let a missing recorded cwd silently proceed in the wrong
#     directory. Fixed: a missing cwd now disarms that session with a
#     `cwd-gone` reason instead of running blind.
#   F10 (Minor): `status`'s numeric fields lacked the same sanitization
#     `tick` already applies to the same files. Fixed: shared helper.
#
# ROUND 2 (harness-reviewer REJECT again, same day, on the F1-F10 fixes
# above — 2 more Critical findings, both PROVEN via real concurrency/
# classification probes):
#   Critical-1: `cmd_disarm` unconditionally `rmdir`'d the GLOBAL spawn
#     lock, even when a DIFFERENT session's tick was actively holding it
#     mid-spawn (disarm fires on every turn's Stop, for every tracked
#     session) — the reviewer measured TWO concurrent `claude` children
#     against the SAME session. Fixed: disarm no longer touches the
#     lock at all; it is released only by its owning tick's own EXIT
#     trap, or reclaimed by `_lr_reclaim_stale_lock` when its mtime is
#     older than TIMEOUT_SECONDS+120s (an owning tick can only be that
#     old if it crashed without running its trap). Self-tests S16/S17.
#   Critical-2: the liveness gate was a DENY-list ("proceed unless
#     live"), so it spawned on `throttled` (ADR-061 D4's own explicit
#     never-spawn class — an alive process being retried internally by
#     the CLI, i.e. exactly a limit-paused session) and on `stale`
#     (a healthy session merely idle >30min, alive pid) — the reviewer
#     proved both. Fixed: inverted to an ALLOWLIST — proceed ONLY when
#     hb_classify confirms `crashed` (dead pid; the one class that
#     unambiguously means the process is gone, which is exactly what a
#     usage-limit kill produces). `missing`/`live`/`throttled`/`stale`
#     all skip. When the heartbeat oracle itself is entirely unavailable
#     (lib failed to source), round 2 degraded to the floor alone --
#     round 3 (below) tightened this further to also fail closed.
#     Self-test S15.
#   Also fixed in the same pass: `_lr_eligible_to_attempt`'s floor check
#     used to silently SKIP (fail open) when `armed_at` failed to parse;
#     it now fails CLOSED (treats an unparseable timestamp as floor-not-
#     elapsed).
#
# ROUND 3 (harness-reviewer REJECT a third time, on the round-2 fixes —
# 1 Critical + 3 Major + 2 Minor):
#   Critical: this script had no reentry guard of its OWN -- `cmd_arm`/
#     `cmd_tick` only ever SET NL_HOOK_REENTRY=1 for the spawned child,
#     never CHECKED it for themselves. Two of the three hook chokepoints
#     were protected only because their HOST hook (session-start-
#     digest.sh, workstreams-stop-writer.sh) already reentry-guards
#     before ever reaching the splice; the new UserPromptSubmit entry
#     calls `arm` directly with no such host-level guard, so an
#     automation-resumed child could re-arm itself through it -- and
#     since `arm` also clears .giveup/.attempts, a successful resume
#     would silently reset its own hard-stop counter. Fixed: both
#     `cmd_arm` and `cmd_tick` now check NL_HOOK_REENTRY as their FIRST
#     statement. Self-tests S18/S19.
#   Major: the "heartbeat oracle entirely unavailable" fallback used to
#     degrade to `proceed` (floor-only) -- LESS conservative than the
#     sibling "oracle available, this session's data specifically
#     missing" branch, which correctly skips. Fixed: both unknowns now
#     fail equally closed (`skip-no-oracle`).
#   Major: the manifest's `golden_scenario` implied broad usage-limit
#     coverage; the allowlist actually covers only the confirmed-dead
#     (`crashed`) subset, never `throttled` (alive, limit-paused --
#     ADR-061 D4's own never-spawn class). Fixed: golden_scenario now
#     states this scope boundary explicitly.
#   Major: this ADR asserted one fixed harness-doctor.sh self-test tally
#     that didn't match an independent reviewer run. Fixed: both counts
#     are now reported, with the shared reasoning for why both are
#     pre-existing (a purely additive diff).
#   Minor: self-test S9 only proved the resumed child RECEIVES
#     NL_HOOK_REENTRY=1, never that `arm` HONORS it -- closed by S18/S19.
#   Minor: `_lr_reclaim_stale_lock`'s age-check-then-rmdir was not atomic
#     -- fixed via an atomic `mv`-based claim (see ROUND 4, which found
#     this fix was necessary but not sufficient).
#
# ROUND 4 (harness-reviewer REJECT a fourth time, on the round-2/3 fixes
# — 1 Critical + 2 Major; rounds 1-3 all independently RE-verified clean
# by this pass):
#   Critical: round 2 fixed `cmd_disarm` releasing a lock it did not own,
#     but did not generalize the fix to the other two lock-touching
#     paths. `_lr_reclaim_stale_lock` reclaimed on AGE ALONE, which a
#     real probe proved insufficient -- a GNU `timeout`-bounded child
#     that traps/ignores TERM can genuinely outlive TIMEOUT_SECONDS while
#     its owning tick is still alive and legitimately waiting on it, so
#     an age-only reclaim could steal the lock from a still-live owner;
#     and the EXIT trap was a bare `rmdir "$LOCK_DIR"`, removing whatever
#     sat at that path regardless of who created it, so the tick that
#     had its lock stolen would then delete the RECLAIMER's fresh lock on
#     its own exit -- reopening the concurrent-spawn window. The
#     reviewer measured 2 concurrent `claude` children this way. Fixed:
#     every acquirer writes its own pid into `$LOCK_DIR/owner`; release
#     (`_lr_release_own_lock`) checks that token before removing
#     anything; reclaim additionally requires `kill -0 <owner_pid>` to
#     confirm DEATH, not just age. Self-tests S20/S21.
#   Major: the fallback shim for a missing portable-timeout.sh silently
#     ran the `claude` child fully UNBOUNDED with no announcement --
#     every sibling caller of the same shim convention (harness-doctor.sh,
#     ensure-cockpit.sh, etc.) emits a loud WARN; this one didn't. Fixed:
#     matches the sibling convention now.
#   Major: several artifacts (this header, the ADR, manifest.json)
#     phrased the single-concurrent-spawn property as an unqualified
#     absolute resting on an unproven premise (nl_run_bounded's timeout
#     alone). Fixed: restated in terms of the ownership+liveness check
#     that actually makes it true.
#
# See docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md for
# the ADR-061/FM-037 reconciliation (updated post-review to name the
# controls reused, not just the scope difference).
#
# ============================================================
# TURN-SCOPED ARMING (why Stop firing per-TURN, not per-session, matters)
# ============================================================
#
# Claude Code's Stop hook fires at the end of EVERY assistant turn, not
# once at the true end of a session (workstreams-stop-writer.sh's own
# per-turn heartbeat/turn-trace bookkeeping already depends on that
# fact). arm is spliced into BOTH SessionStart (covering the sliver
# before the first prompt) AND UserPromptSubmit (re-arms at the start of
# every subsequent turn); disarm is spliced into Stop (fires at the end
# of every turn). Net effect: the marker is armed for as long as a turn
# is actively in flight — WITHOUT the F1/F6 gates above, that would make
# the trigger condition ~1:1 correlated with "resuming is wrong"; WITH
# them, a genuinely still-live turn is protected by the floor+liveness
# check regardless of the marker's mere presence.
#
# ============================================================
# SAFETY CONTRACT (every point load-bearing; see FM-037)
# ============================================================
#   1. At most ONE live-spawn per tick, machine-wide: a single mkdir lock
#      guards the entire tick, and tick stops after its first real
#      attempt even if multiple sessions are armed. This is proven ONLY
#      by ownership-scoped release + reclaim (round 4): the lock carries
#      an owner-pid token; release checks that token, and stale-lock
#      reclaim additionally requires the recorded owner's pid be
#      CONFIRMED DEAD (`kill -0`) WHEN one is recorded -- a lock with no
#      owner file at all (e.g. one created before this fix landed) falls
#      back to age-only reclaim, the same information the pre-fix code
#      had (round-5 review precision fix: the summary here previously
#      omitted this fallback, reading stronger than the guarded code a
#      few lines below actually implements) -- not merely aged past a
#      timeout in the common case. Age alone was proven insufficient (a
#      GNU `timeout`-bounded child that traps/ignores TERM can genuinely
#      outlive TIMEOUT_SECONDS while its owner is still legitimately
#      alive).
#   2. The resumed child is spawned with NL_HOOK_REENTRY=1 so its own
#      SessionStart/Stop/UserPromptSubmit hooks no-op instead of
#      re-triggering this watchdog (or any other spawning hook)
#      recursively.
#   3. Bounded retries with REAL backoff (900s/1800s/3600s, capped
#      7200s) and a hard stop (default 8 attempts) per tracked session —
#      a giveup sentinel makes the stuck state visible (doctor check)
#      rather than silent, and pins further ticks to a no-op for THAT
#      session (mutation-proof self-test).
#   4. The `claude -p --resume` invocation is time-bounded via
#      hooks/lib/portable-timeout.sh's nl_run_bounded.
#   5. `arm`/`disarm` are no-ops from any cwd that is NOT the main
#      checkout — a worktree-isolated builder sub-agent can never
#      arm/wipe a tracked marker.
#   6. A tracked session is never resumed while genuinely live (floor +
#      heartbeat liveness gate, see "REVIEW FIXES" above).
#   7. Disarming only ever removes the CALLING session's own tracked
#      state — never another session's.
#
# ============================================================
# SUBCOMMANDS
# ============================================================
#   arm [--session <id>] [--cwd <dir>]     Arm/refresh the marker for a session.
#   disarm [<reason>] [--session <id>]     Remove one session's tracked state.
#   tick                                    The watchdog action (launchd, every 900s).
#   status [<session-id>] [--json] [--all] Report state for one/all sessions.
#   --self-test                            Sandboxed scenarios.
#
# ============================================================
# ENV
# ============================================================
#   LIMIT_RESUME_STATE_DIR            default $HOME/.claude/state/limit-resume
#   LIMIT_RESUME_MAX_RETRIES          default 8
#   LIMIT_RESUME_BASE_BACKOFF_SECONDS default 900
#   LIMIT_RESUME_MAX_BACKOFF_SECONDS  default 7200
#   LIMIT_RESUME_TIMEOUT_SECONDS      default 1800 (bound on the claude child)
#   LIMIT_RESUME_MIN_SILENCE_SECONDS  default 1800 (F6 floor before ANY attempt)
#   LIMIT_RESUME_STALE_MIN            default 30 (hb_classify's stale-minutes arg)
#   LIMIT_RESUME_CLAUDE_BIN           default "claude" (resolved via PATH)

set -u

# DEFECT 1 (the predecessor's proven, but never-since-exercised, fix):
# launchd's own minimal environment lacks Homebrew, so `command -v
# "$CLAUDE_BIN"` below could fail to resolve `claude` purely because of
# WHERE this process was invoked from. Appended (never prepended) so a
# self-test stub earlier on PATH is never shadowed by a real `claude`.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  # harness-reviewer REJECT round 4, PROVEN: every sibling caller of this
  # shim (harness-doctor.sh, ensure-cockpit.sh, ensure-coord-sync.sh,
  # session-start-auto-install.sh, f4-retro.sh, and others) emits a loud
  # WARN when portable-timeout.sh is missing; this one silently degraded
  # the `claude` child to fully UNBOUNDED with no announcement at all --
  # exactly the "silent degradation of a safety bound" that lib's own
  # header explicitly prohibits. Matches the sibling convention now.
  echo "limit-resume: WARN hooks/lib/portable-timeout.sh missing -- running UNBOUNDED (no timeout)" >&2
  nl_run_bounded() {
    _log "WARN: portable-timeout.sh unavailable -- running UNBOUNDED (wanted ${1}s bound)"
    local _secs="$1"; shift; "$@"
  }
fi
# ADR-061 D1/D3's canonical liveness oracle (hb_classify/hb_path_for) —
# best-effort; every use below degrades to the floor-only path when
# unavailable (F1/F6 fix; see header).
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/session-heartbeat-lib.sh" 2>/dev/null; } || true

# ---- state dir (HARNESS_SELFTEST-sandboxed like broadcast-active-session.sh) ----
if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
  STATE_DIR="${LIMIT_RESUME_STATE_DIR:-${TMPDIR:-/tmp}/limit-resume-selftest-$$}"
else
  STATE_DIR="${LIMIT_RESUME_STATE_DIR:-$HOME/.claude/state/limit-resume}"
fi
ARMED_DIR="$STATE_DIR/armed"
LOCK_DIR="$STATE_DIR/attempt.lock"
LOG="$STATE_DIR/log.txt"

MAX_RETRIES="${LIMIT_RESUME_MAX_RETRIES:-8}"
BASE_BACKOFF="${LIMIT_RESUME_BASE_BACKOFF_SECONDS:-900}"
MAX_BACKOFF="${LIMIT_RESUME_MAX_BACKOFF_SECONDS:-7200}"
TIMEOUT_SECONDS="${LIMIT_RESUME_TIMEOUT_SECONDS:-1800}"
MIN_SILENCE_SECONDS="${LIMIT_RESUME_MIN_SILENCE_SECONDS:-1800}"
STALE_MIN="${LIMIT_RESUME_STALE_MIN:-30}"
CLAUDE_BIN="${LIMIT_RESUME_CLAUDE_BIN:-claude}"

RESUME_NUDGE_TEXT="The usage limit that paused this session has reset. This is an automated OS-level resume (limit-resume watchdog) firing because the session went silent without a clean Stop (crash or limit-kill), not a human turn. Read SCRATCHPAD.md first and follow whatever section it documents for resuming after an interruption; verify the REAL current state of anything it claims is in flight (agents, background work, branches) rather than trusting the claim; resume or re-dispatch anything that actually died; continue the session's active work. You are an automation-resumed child (NL_HOOK_REENTRY=1) -- end this turn with CONTINUING:, PAUSING:, or BLOCKED:, never a bare DONE:, since a DONE claim from an unattended resume has not passed the full human-in-the-loop honesty chain."

_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_log() { mkdir -p "$STATE_DIR" 2>/dev/null || true; printf '%s %s\n' "$(_ts)" "$*" >> "$LOG" 2>/dev/null || true; }
_json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
_sanitize_num() { case "${1:-}" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }

# 0 (true) when cwd is the main checkout (not a linked worktree), OR cwd
# is not a git repo at all (self-test tmp dirs, or a non-repo cwd).
_lr_is_main_checkout() {
  local gd cgd
  gd="$(git rev-parse --git-dir 2>/dev/null)" || return 0
  cgd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 0
  gd="$(cd "$gd" 2>/dev/null && pwd)"
  cgd="$(cd "$cgd" 2>/dev/null && pwd)"
  [ "$gd" = "$cgd" ]
}

# Per-session file key (mirrors broadcast-active-session.sh's _claim_key).
_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
_marker_path() { printf '%s/%s.json' "$ARMED_DIR" "$(_key "$1")"; }
_attempts_path() { printf '%s/%s.attempts' "$ARMED_DIR" "$(_key "$1")"; }
_next_eligible_path() { printf '%s/%s.next-eligible' "$ARMED_DIR" "$(_key "$1")"; }
_giveup_path() { printf '%s/%s.giveup' "$ARMED_DIR" "$(_key "$1")"; }

_read_json_field() {
  # $1 = file, $2 = field name
  sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" "$1" 2>/dev/null | head -1
}

_rm_session_state() {
  local sid="$1"
  rm -f "$(_marker_path "$sid")" "$(_attempts_path "$sid")" "$(_next_eligible_path "$sid")" "$(_giveup_path "$sid")" 2>/dev/null
}

cmd_arm() {
  # harness-reviewer REJECT round 3, PROVEN: this script has no reentry
  # guard of its own -- it only SETS NL_HOOK_REENTRY=1 for the child it
  # spawns (cmd_tick), never CHECKS it for itself. The new UserPromptSubmit
  # hooks[] entry calls `arm` DIRECTLY (not through an already-guarded host
  # hook like session-start-digest.sh/workstreams-stop-writer.sh), so an
  # automation-resumed child -- which inherits NL_HOOK_REENTRY=1 in its own
  # environment -- would re-arm through that entry on its own first prompt,
  # and because arm also clears .giveup/.attempts, a successful resume
  # would silently reset its own hard-stop counter. Fail fast, matching
  # every other spawning hook's own top-of-function convention.
  if [ "${NL_HOOK_REENTRY:-0}" = "1" ]; then
    return 0
  fi
  local sid="" cwd="$PWD"
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) sid="${2:-}"; shift 2 ;;
      --cwd) cwd="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$sid" ]; then
    _log "arm: no session id available (CLAUDE_CODE_SESSION_ID unset, no --session) -- skipping"
    return 0
  fi
  if ! ( cd "$cwd" 2>/dev/null && _lr_is_main_checkout ); then
    return 0
  fi
  mkdir -p "$ARMED_DIR" 2>/dev/null || return 0
  local mpath tmp
  mpath="$(_marker_path "$sid")"
  tmp="$mpath.tmp.$$"
  if printf '{"session_id":"%s","cwd":"%s","armed_at":"%s"}\n' \
      "$(_json_esc "$sid")" "$(_json_esc "$cwd")" "$(_ts)" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$mpath" 2>/dev/null
  fi
  rm -f "$(_attempts_path "$sid")" "$(_next_eligible_path "$sid")" "$(_giveup_path "$sid")" 2>/dev/null
  _log "armed session=${sid} cwd=${cwd}"
}

cmd_disarm() {
  local reason="clean-end" sid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) sid="${2:-}"; shift 2 ;;
      *) reason="$1"; shift ;;
    esac
  done
  [ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  if ! _lr_is_main_checkout; then
    return 0
  fi
  if [ -z "$sid" ]; then
    return 0
  fi
  if [ -f "$(_marker_path "$sid")" ]; then
    _log "disarmed session=${sid} (${reason})"
  fi
  _rm_session_state "$sid"
  # harness-reviewer REJECT finding Critical-1 (round 2, PROVEN via a real
  # two-child concurrency probe): this used to unconditionally
  # `rmdir "$LOCK_DIR"` here, which released the GLOBAL spawn lock even
  # when a DIFFERENT session's tick was actively holding it mid-spawn —
  # since disarm fires on every turn's Stop for every tracked session,
  # this let a second `claude -p --resume` child stack on top of a still
  # -running first one. The lock is now released ONLY by its owning
  # tick's own EXIT trap, or reclaimed as stale by a later tick (see
  # _lr_reclaim_stale_lock) — never by an unrelated disarm call.
}

# Release the spawn lock -- but ONLY if it is still marked as owned by
# THIS process. harness-reviewer round-4 Critical finding, PROVEN by a
# real concurrency probe: the ORIGINAL EXIT trap was a bare
# `rmdir "$LOCK_DIR"`, which removes whatever sits at that path
# regardless of who created it -- so a tick that had its lock stolen by
# `_lr_reclaim_stale_lock` (see below) would then delete the RECLAIMER's
# fresh lock on its own exit, re-opening the concurrent-spawn window
# round 2 supposedly closed. Every acquirer now writes its own pid into
# `$LOCK_DIR/owner` immediately after `mkdir`; release checks that file
# still names US before removing anything.
_lr_release_own_lock() {
  local owner_pid
  owner_pid="$(cat "$LOCK_DIR/owner" 2>/dev/null)"
  if [ "$owner_pid" = "$$" ]; then
    rm -f "$LOCK_DIR/owner" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

# Reclaim an abandoned lock (owning tick crashed/was killed before its
# EXIT trap could fire). harness-reviewer round-4 Critical finding,
# PROVEN: age alone is NOT proof of death -- `nl_run_bounded`'s ACTIVE
# code path on a machine with GNU coreutils' `timeout` (no `-k` flag
# used here) sends only SIGTERM, so a child that traps/ignores TERM can
# genuinely outlive TIMEOUT_SECONDS while its owning tick is still alive
# and legitimately waiting on it (measured directly: `timeout 2s bash -c
# 'trap "" TERM; sleep 12'` returned rc=124 only after the full 12s, not
# at the 2s bound). An age-only reclaim would steal the lock from that
# still-live owner. Reclaim now requires BOTH the age threshold AND
# confirmed death of the recorded owner pid via `kill -0` (this repo's
# own portable liveness convention -- session-heartbeat-lib.sh's
# _hb_pid_alive uses the identical check). A lock with no owner file at
# all (e.g. one created before this fix landed) has no pid to check and
# falls back to the age-only heuristic, since that is strictly the same
# information the pre-fix code had.
_lr_reclaim_stale_lock() {
  [ -d "$LOCK_DIR" ] || return 0
  local mtime now age max_age owner_pid
  mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
  [ "$mtime" -gt 0 ] || return 0
  now=$(date +%s)
  age=$(( now - mtime ))
  max_age=$(( TIMEOUT_SECONDS + 120 ))
  [ "$age" -gt "$max_age" ] || return 0
  owner_pid="$(cat "$LOCK_DIR/owner" 2>/dev/null)"
  if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
    _log "tick: lock aged ${age}s but owner pid=${owner_pid} is still alive -- NOT reclaiming"
    return 0
  fi
  # `mv` on the same filesystem is atomic (exactly one racer's rename can
  # succeed), so even if two ticks concurrently reach this point after
  # both confirming death, only one of them treats the lock as reclaimed.
  local claim_tmp="${LOCK_DIR}.reclaim.$$"
  if mv "$LOCK_DIR" "$claim_tmp" 2>/dev/null; then
    _log "tick: reclaimed abandoned lock (age=${age}s > ${max_age}s, owner_pid=${owner_pid:-unknown} confirmed dead or unrecorded) -- the prior tick crashed without releasing it"
    rm -rf "$claim_tmp" 2>/dev/null || true
  fi
}

# Liveness gate (F1/F6, round-2-hardened per harness-reviewer Critical-2
# PROVEN finding: this used to be a DENY-list -- "proceed unless live" --
# which spawned on `throttled` (ADR-061 D4's own explicit never-spawn
# class: an alive process whose API traffic is erroring, i.e. exactly a
# limit-paused session already being retried by the CLI's own internal
# loop) and on `stale` (a perfectly healthy session whose operator has
# simply been idle >30min, alive pid). Now an ALLOWLIST: proceed ONLY
# when the canonical oracle confirms `crashed` (stale per hb_is_stale's
# transcript-mtime-aware check AND the recorded pid is confirmed dead) --
# the one class that unambiguously means "the process backing this
# session is gone," which is exactly what a usage-limit KILL produces
# and exactly what needs an external `claude -p --resume` to recreate. A
# live, throttled, stale-but-alive, or unclassifiable (missing heartbeat,
# OR the heartbeat oracle itself unavailable) session all SKIP -- mirrors
# session-resumer.sh's own "a session this script cannot see clearly is
# skipped, never resumed" discipline precisely, rather than a narrower
# version of it. Both "unknown" branches (no data for this session; no
# oracle at all) now fail equally closed -- round 3 fixed an asymmetry
# where the broader unknown used to fail open.
# Prints one of: proceed | skip-floor | skip-not-confirmed-dead | skip-no-oracle.
# $1 = sid, $2 = armed_at (ISO8601), $3 = now_epoch
_lr_eligible_to_attempt() {
  local sid="$1" armed_at="$2" now_epoch="$3"
  local armed_epoch age_sec
  armed_epoch=$(date -u -d "$armed_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$armed_at" +%s 2>/dev/null || echo 0)
  # Fail CLOSED on an unparseable/corrupt armed_at (round-2 fix): the
  # floor previously only applied when the timestamp parsed, silently
  # bypassing itself -- exactly backwards for a safety gate.
  if [ "$armed_epoch" -le 0 ]; then
    printf 'skip-floor'
    return 0
  fi
  age_sec=$(( now_epoch - armed_epoch ))
  if [ "$age_sec" -lt "$MIN_SILENCE_SECONDS" ]; then
    printf 'skip-floor'
    return 0
  fi
  if declare -F hb_classify >/dev/null 2>&1 && declare -F hb_path_for >/dev/null 2>&1; then
    local hbfile hbcls
    hbfile="$(hb_path_for "$sid")"
    hbcls="$(hb_classify "$hbfile" "$STALE_MIN" 2>/dev/null)"
    if [ "$hbcls" = "crashed" ]; then
      printf 'proceed'
      return 0
    fi
    printf 'skip-not-confirmed-dead'
    return 0
  fi
  # harness-reviewer REJECT round 3, PROVEN: the ORIGINAL version of this
  # branch degraded to "proceed" (floor-only) when the heartbeat oracle
  # itself was entirely unavailable (lib failed to source) -- asymmetric
  # with the "oracle IS available but THIS session's heartbeat is
  # missing" branch above, which correctly SKIPS. The broader unknown
  # ("no oracle at all") was failing OPEN while the narrower unknown
  # ("no data for this one session") failed closed -- backwards for a
  # safety gate. Fixed: fail closed here too. A genuinely broken/missing
  # session-heartbeat-lib.sh is a real install defect (harness-doctor's
  # own checks would surface it independently); this mechanism should
  # never treat "I cannot verify anything" as "assume dead."
  printf 'skip-no-oracle'
}

cmd_tick() {
  # Defense in depth alongside cmd_arm's own guard above: tick is only
  # ever invoked by the LaunchAgent, never by a spawned child directly,
  # but this costs nothing and matches the "every spawning entrypoint
  # self-guards" generalization the round-3 finding calls for.
  if [ "${NL_HOOK_REENTRY:-0}" = "1" ]; then
    return 0
  fi
  [ -d "$ARMED_DIR" ] || return 0
  _lr_reclaim_stale_lock
  mkdir "$LOCK_DIR" 2>/dev/null || return 0
  printf '%s\n' "$$" > "$LOCK_DIR/owner" 2>/dev/null || true
  trap '_lr_release_own_lock' EXIT

  local now spawned=0
  now=$(date +%s)

  local f
  for f in "$ARMED_DIR"/*.json; do
    [ -e "$f" ] || continue
    [ "$spawned" -eq 0 ] || break

    local sid cwd armed_at
    sid="$(_read_json_field "$f" session_id)"
    cwd="$(_read_json_field "$f" cwd)"
    armed_at="$(_read_json_field "$f" armed_at)"
    [ -n "$sid" ] || { _log "tick: marker $f unreadable -- removing"; rm -f "$f"; continue; }

    [ -f "$(_giveup_path "$sid")" ] && continue

    local next
    if [ -f "$(_next_eligible_path "$sid")" ]; then
      next=$(cat "$(_next_eligible_path "$sid")" 2>/dev/null || echo 0)
      next="$(_sanitize_num "$next")"
      [ "$now" -lt "$next" ] && continue
    fi

    local verdict
    verdict="$(_lr_eligible_to_attempt "$sid" "$armed_at" "$now")"
    [ "$verdict" = "proceed" ] || continue

    if [ ! -d "$cwd" ]; then
      _log "tick: recorded cwd '${cwd}' for session=${sid} no longer exists -- disarming (cwd-gone)"
      _rm_session_state "$sid"
      continue
    fi

    local claude_bin
    claude_bin="$(command -v "$CLAUDE_BIN" 2>/dev/null || true)"
    if [ -z "$claude_bin" ]; then
      _log "tick: '$CLAUDE_BIN' not found on PATH -- cannot attempt resume (session=${sid})"
      continue
    fi

    local attempts=0
    [ -f "$(_attempts_path "$sid")" ] && attempts="$(_sanitize_num "$(cat "$(_attempts_path "$sid")" 2>/dev/null)")"

    spawned=1
    local out rc
    out="$(cd "$cwd" 2>/dev/null && NL_HOOK_REENTRY=1 nl_run_bounded "$TIMEOUT_SECONDS" "$claude_bin" -p --resume "$sid" "$RESUME_NUDGE_TEXT" 2>>"$LOG")"
    rc=$?

    if [ "$rc" -eq 0 ]; then
      _log "attempt #$((attempts+1)) session=${sid} outcome=SUCCESS"
      _rm_session_state "$sid"
    else
      attempts=$((attempts+1))
      _log "attempt #${attempts} session=${sid} outcome=FAIL exit=${rc}"
      printf '%s\n' "$attempts" > "$(_attempts_path "$sid")" 2>/dev/null
      if [ "$attempts" -ge "$MAX_RETRIES" ]; then
        _log "GIVING UP after ${attempts} attempts for session=${sid} -- marker left armed; disarm manually or wait for a clean session end"
        printf 'gave up after %s attempts at %s\n' "$attempts" "$(_ts)" > "$(_giveup_path "$sid")" 2>/dev/null
      else
        local backoff=$(( BASE_BACKOFF * (1 << (attempts - 1)) ))
        [ "$backoff" -gt "$MAX_BACKOFF" ] && backoff="$MAX_BACKOFF"
        echo $(( now + backoff )) > "$(_next_eligible_path "$sid")" 2>/dev/null
      fi
    fi
  done
}

_print_one_status() {
  local sid="$1" as_json="$2"
  local mpath; mpath="$(_marker_path "$sid")"
  if [ ! -f "$mpath" ]; then
    if [ "$as_json" = "--json" ]; then printf '{"armed":false,"session_id":"%s"}\n' "$(_json_esc "$sid")"; else echo "disarmed session=${sid}"; fi
    return 0
  fi
  local cwd attempts next gaveup=0
  cwd="$(_read_json_field "$mpath" cwd)"
  attempts=0; [ -f "$(_attempts_path "$sid")" ] && attempts="$(_sanitize_num "$(cat "$(_attempts_path "$sid")" 2>/dev/null)")"
  [ -f "$(_giveup_path "$sid")" ] && gaveup=1
  next=0; [ -f "$(_next_eligible_path "$sid")" ] && next="$(_sanitize_num "$(cat "$(_next_eligible_path "$sid")" 2>/dev/null)")"
  if [ "$as_json" = "--json" ]; then
    printf '{"armed":true,"session_id":"%s","cwd":"%s","attempts":%s,"gave_up":%s,"next_eligible_epoch":%s}\n' \
      "$(_json_esc "$sid")" "$(_json_esc "$cwd")" "$attempts" "$gaveup" "$next"
  else
    if [ "$gaveup" -eq 1 ]; then
      echo "armed session=${sid} cwd=${cwd} attempts=${attempts} status=GAVE_UP"
    else
      echo "armed session=${sid} cwd=${cwd} attempts=${attempts} next_eligible_epoch=${next}"
    fi
  fi
}

cmd_status() {
  local sid="" as_json="" all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) as_json="--json"; shift ;;
      --all) all=1; shift ;;
      *) sid="$1"; shift ;;
    esac
  done
  if [ "$all" -eq 1 ]; then
    [ -d "$ARMED_DIR" ] || { [ "$as_json" = "--json" ] && echo "[]" || echo "(none armed)"; return 0; }
    local f any=0
    for f in "$ARMED_DIR"/*.json; do
      [ -e "$f" ] || continue
      any=1
      _print_one_status "$(_read_json_field "$f" session_id)" "$as_json"
    done
    [ "$any" -eq 1 ] || { [ "$as_json" = "--json" ] && echo "[]" || echo "(none armed)"; }
    return 0
  fi
  [ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -z "$sid" ]; then
    if [ "$as_json" = "--json" ]; then printf '{"armed":false}\n'; else echo "disarmed"; fi
    return 0
  fi
  _print_one_status "$sid" "$as_json"
}

# ============================================================
# --self-test
# ============================================================
_write_stub_claude() {
  local bindir="$1" calls="$2" failuntil="$3" envcheck="${4:-}"
  mkdir -p "$bindir"
  cat > "$bindir/claude" <<STUB
#!/bin/bash
n=0
[ -f "$calls" ] && n=\$(cat "$calls")
n=\$((n+1))
echo "\$n" > "$calls"
if [ -n "$envcheck" ]; then
  printf 'NL_HOOK_REENTRY=%s\n' "\${NL_HOOK_REENTRY:-unset}" > "$envcheck"
fi
if [ "\$n" -le "$failuntil" ]; then
  echo "stub: limit still active (call \$n)" >&2
  exit 1
else
  echo "stub: resumed OK (call \$n)"
  exit 0
fi
STUB
  chmod +x "$bindir/claude"
}

# Writes a heartbeat fixture. $1=dir $2=sid $3=last_activity_ts $4=pid
_write_hb_fixture() {
  local dir="$1" sid="$2" ts="$3" pid="$4"
  mkdir -p "$dir"
  printf '{"schema":1,"session_id":"%s","pid":%s,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"%s","last_event":"turn-end","marker_state":"none"}\n' \
    "$sid" "$pid" "$ts" > "$dir/$sid.json"
}

_self_test() {
  local pass=0 fail=0 tmp

  # S1 -- arm in the MAIN checkout writes a per-session marker.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s1 "$SCRIPT_DIR/limit-resume.sh" arm
    if grep -q '"session_id":"sess-s1"' "$tmp/state/armed/sess-s1.json" 2>/dev/null; then
      echo "  S1 arm writes per-session marker: PASS"
    else
      echo "  S1 arm writes per-session marker: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S2 -- arm from a LINKED WORKTREE is a no-op. Asserts the worktree
  # setup itself succeeded FIRST (F5 fix — a silently-failed `git
  # worktree add` must never make this pass vacuously).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    git worktree add -q "$tmp/wt" -b feat/s2-wt >/dev/null 2>&1
    [ -d "$tmp/wt" ] || { echo "  S2 arm from worktree no-ops: FAIL (worktree setup itself failed)"; exit 1; }
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    ( cd "$tmp/wt" && CLAUDE_CODE_SESSION_ID=sess-s2 "$SCRIPT_DIR/limit-resume.sh" arm )
    if [ ! -d "$tmp/state/armed" ] || [ ! -f "$tmp/state/armed/sess-s2.json" ]; then
      echo "  S2 arm from worktree no-ops: PASS"
    else
      echo "  S2 arm from worktree no-ops: FAIL (marker was written)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S3 -- tick with no armed dir at all is a silent no-op.
  (
    tmp=$(mktemp -d)
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$tmp/state/log.txt" ]; then
      echo "  S3 tick with no marker silent: PASS"
    else
      echo "  S3 tick with no marker silent: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S4 -- tick before the BACKOFF window elapses does NOT invoke claude
  # (floor disabled via env so this isolates the backoff mechanism only).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s4 "$SCRIPT_DIR/limit-resume.sh" arm
    echo $(( $(date +%s) + 3600 )) > "$tmp/state/armed/sess-s4.next-eligible"
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$calls" ]; then
      echo "  S4 backoff-not-due skips attempt: PASS"
    else
      echo "  S4 backoff-not-due skips attempt: FAIL (stub was called)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S5 -- fail-then-succeed chain (floor disabled to isolate backoff/success).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s5 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s5 "2020-01-01T00:00:00Z" 999999
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 1
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    a1=$(cat "$tmp/state/armed/sess-s5.attempts" 2>/dev/null || echo "")
    ne1=$(cat "$tmp/state/armed/sess-s5.next-eligible" 2>/dev/null || echo "")
    [ "$a1" = "1" ] || { echo "  S5 fail-then-succeed: FAIL (attempts='$a1', want 1)"; exit 1; }
    [ -n "$ne1" ] || { echo "  S5 fail-then-succeed: FAIL (no backoff recorded)"; exit 1; }
    echo 0 > "$tmp/state/armed/sess-s5.next-eligible"
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$tmp/state/armed/sess-s5.json" ] && [ "$(cat "$calls")" = "2" ]; then
      echo "  S5 fail-then-succeed disarms: PASS"
    else
      echo "  S5 fail-then-succeed disarms: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S6 -- MUTATION-PROOF hard-stop (floor disabled to isolate the cap).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    export LIMIT_RESUME_MAX_RETRIES=2
    CLAUDE_CODE_SESSION_ID=sess-s6 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s6 "2020-01-01T00:00:00Z" 999999
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    echo 0 > "$tmp/state/armed/sess-s6.next-eligible"
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    [ -f "$tmp/state/armed/sess-s6.giveup" ] || { echo "  S6 hard-stop mutation-proof: FAIL (no giveup after 2 failures)"; exit 1; }
    calls_after_giveup="$(cat "$calls")"
    echo 0 > "$tmp/state/armed/sess-s6.next-eligible"
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    calls_final="$(cat "$calls")"
    if [ "$calls_after_giveup" = "2" ] && [ "$calls_final" = "2" ]; then
      echo "  S6 hard-stop mutation-proof (call count pinned at 2): PASS"
    else
      echo "  S6 hard-stop mutation-proof: FAIL (calls $calls_after_giveup -> $calls_final)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S7 -- disarm removes only THIS session's state files.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s7 "$SCRIPT_DIR/limit-resume.sh" arm
    echo 3 > "$tmp/state/armed/sess-s7.attempts"
    "$SCRIPT_DIR/limit-resume.sh" disarm "test" --session sess-s7
    if [ ! -f "$tmp/state/armed/sess-s7.json" ] && [ ! -f "$tmp/state/armed/sess-s7.attempts" ]; then
      echo "  S7 disarm clears this session's state: PASS"
    else
      echo "  S7 disarm clears this session's state: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S8 -- cross-session safety: disarm from a LINKED WORKTREE cannot wipe
  # the main checkout's armed marker. Asserts worktree setup succeeded
  # first (F5 fix).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    git worktree add -q "$tmp/wt" -b feat/s8-wt >/dev/null 2>&1
    [ -d "$tmp/wt" ] || { echo "  S8 worktree disarm cannot wipe main-session marker: FAIL (worktree setup itself failed)"; exit 1; }
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s8-main "$SCRIPT_DIR/limit-resume.sh" arm
    ( cd "$tmp/wt" && CLAUDE_CODE_SESSION_ID=sess-s8-main "$SCRIPT_DIR/limit-resume.sh" disarm "worktree-stop" )
    if [ -f "$tmp/state/armed/sess-s8-main.json" ]; then
      echo "  S8 worktree disarm cannot wipe main-session marker: PASS"
    else
      echo "  S8 worktree disarm cannot wipe main-session marker: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S9 -- the resumed child gets NL_HOOK_REENTRY=1 (floor disabled).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s9 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s9 "2020-01-01T00:00:00Z" 999999
    calls="$tmp/calls"; bindir="$tmp/bin"; envcheck="$tmp/envcheck"
    _write_stub_claude "$bindir" "$calls" 0 "$envcheck"
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ -f "$envcheck" ] && grep -q '^NL_HOOK_REENTRY=1$' "$envcheck"; then
      echo "  S9 resumed child gets NL_HOOK_REENTRY=1: PASS"
    else
      echo "  S9 resumed child gets NL_HOOK_REENTRY=1: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S10 -- status reflects armed/gave-up state (JSON, doctor-consumable).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    out="$("$SCRIPT_DIR/limit-resume.sh" status sess-s10 --json)"
    [ "$out" = '{"armed":false,"session_id":"sess-s10"}' ] || { echo "  S10 status: FAIL (disarmed shape: $out)"; exit 1; }
    CLAUDE_CODE_SESSION_ID=sess-s10 "$SCRIPT_DIR/limit-resume.sh" arm
    echo "gave up" > "$tmp/state/armed/sess-s10.giveup"; echo 5 > "$tmp/state/armed/sess-s10.attempts"
    out2="$("$SCRIPT_DIR/limit-resume.sh" status sess-s10 --json)"
    if printf '%s' "$out2" | grep -q '"gave_up":1' && printf '%s' "$out2" | grep -q '"attempts":5'; then
      echo "  S10 status reflects gave-up state: PASS"
    else
      echo "  S10 status reflects gave-up state: FAIL ($out2)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S11 (F6 fix) -- a tick moments after arming (floor NOT disabled, i.e.
  # the real default) must NOT invoke claude, even with no backoff file
  # at all. This is the reviewer's own probe, reproduced as a standing
  # regression test.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s11 "$SCRIPT_DIR/limit-resume.sh" arm
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$calls" ]; then
      echo "  S11 initial-floor blocks an immediate post-arm tick: PASS"
    else
      echo "  S11 initial-floor blocks an immediate post-arm tick: FAIL (stub was called seconds after arming)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S12 (F1 fix) -- with the floor elapsed (backdated armed_at) but a
  # LIVE heartbeat fixture for the tracked session (fresh last_activity_ts,
  # this test process's own alive pid), tick must NOT invoke claude. This
  # directly reproduces the reviewer's liveprobe finding as a standing test.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export HEARTBEAT_STATE_DIR="$tmp/hb"
    CLAUDE_CODE_SESSION_ID=sess-s12 "$SCRIPT_DIR/limit-resume.sh" arm
    OLD_TS="$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-90 minutes' +%Y-%m-%dT%H:%M:%SZ)"
    python3 -c "
import json
p = '$tmp/state/armed/sess-s12.json'
d = json.load(open(p))
d['armed_at'] = '$OLD_TS'
json.dump(d, open(p, 'w'))
" 2>/dev/null || printf '{"session_id":"sess-s12","cwd":"%s","armed_at":"%s"}\n' "$tmp" "$OLD_TS" > "$tmp/state/armed/sess-s12.json"
    NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _write_hb_fixture "$tmp/hb" sess-s12 "$NOW_TS" "$$"
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$calls" ]; then
      echo "  S12 live heartbeat blocks resume past the floor: PASS"
    else
      echo "  S12 live heartbeat blocks resume past the floor: FAIL (stub was called against a LIVE session)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S13 (F1 fix, positive case) -- floor elapsed AND a STALE/CRASHED
  # heartbeat fixture (old last_activity_ts, dead pid) -> tick DOES
  # proceed and invoke the stub. Proves the gate is not simply
  # fail-closed-forever once a heartbeat file exists.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s13 "$SCRIPT_DIR/limit-resume.sh" arm
    OLD_TS="$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-90 minutes' +%Y-%m-%dT%H:%M:%SZ)"
    python3 -c "
import json
p = '$tmp/state/armed/sess-s13.json'
d = json.load(open(p))
d['armed_at'] = '$OLD_TS'
json.dump(d, open(p, 'w'))
" 2>/dev/null || printf '{"session_id":"sess-s13","cwd":"%s","armed_at":"%s"}\n' "$tmp" "$OLD_TS" > "$tmp/state/armed/sess-s13.json"
    _write_hb_fixture "$tmp/hb" sess-s13 "2020-01-01T00:00:00Z" 999999
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ -f "$calls" ]; then
      echo "  S13 stale/crashed heartbeat proceeds past the floor: PASS"
    else
      echo "  S13 stale/crashed heartbeat proceeds past the floor: FAIL (stub was never called)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S14 (F3 fix) -- two DIFFERENT sessions armed simultaneously (each a
  # main checkout of its OWN repo); disarming one leaves the other intact.
  (
    tmp=$(mktemp -d)
    mkdir -p "$tmp/repoA" "$tmp/repoB"
    ( cd "$tmp/repoA" && git init --quiet && git config user.email t@example.com && git config user.name T && git commit --allow-empty -q -m init )
    ( cd "$tmp/repoB" && git init --quiet && git config user.email t@example.com && git config user.name T && git commit --allow-empty -q -m init )
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    ( cd "$tmp/repoA" && CLAUDE_CODE_SESSION_ID=sess-s14-a "$SCRIPT_DIR/limit-resume.sh" arm )
    ( cd "$tmp/repoB" && CLAUDE_CODE_SESSION_ID=sess-s14-b "$SCRIPT_DIR/limit-resume.sh" arm )
    [ -f "$tmp/state/armed/sess-s14-a.json" ] && [ -f "$tmp/state/armed/sess-s14-b.json" ] || { echo "  S14 two-session isolation: FAIL (setup — both should be armed)"; exit 1; }
    ( cd "$tmp/repoA" && CLAUDE_CODE_SESSION_ID=sess-s14-a "$SCRIPT_DIR/limit-resume.sh" disarm "test" )
    if [ ! -f "$tmp/state/armed/sess-s14-a.json" ] && [ -f "$tmp/state/armed/sess-s14-b.json" ]; then
      echo "  S14 two concurrent sessions in different repos don't clobber: PASS"
    else
      echo "  S14 two concurrent sessions in different repos don't clobber: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S15 (harness-reviewer round-2 Critical-2, PROVEN) -- ALLOWLIST
  # regression: a `stale` heartbeat (old last_activity_ts, but pid
  # ALIVE — this test process's own $$) must SKIP, not proceed. Under
  # the old deny-list ("skip only if live") this spawned against a
  # perfectly healthy, merely-idle-for-30min session. `stale` means
  # "not confirmed dead"; only `crashed` (dead pid) may proceed.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s15 "$SCRIPT_DIR/limit-resume.sh" arm
    OLD_TS="$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-90 minutes' +%Y-%m-%dT%H:%M:%SZ)"
    python3 -c "
import json
p = '$tmp/state/armed/sess-s15.json'
d = json.load(open(p))
d['armed_at'] = '$OLD_TS'
json.dump(d, open(p, 'w'))
" 2>/dev/null || printf '{"session_id":"sess-s15","cwd":"%s","armed_at":"%s"}\n' "$tmp" "$OLD_TS" > "$tmp/state/armed/sess-s15.json"
    _write_hb_fixture "$tmp/hb" sess-s15 "2020-01-01T00:00:00Z" "$$"
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 99
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ ! -f "$calls" ]; then
      echo "  S15 allowlist: stale-but-alive session is never resumed: PASS"
    else
      echo "  S15 allowlist: stale-but-alive session is never resumed: FAIL (stub was called against a merely-idle, still-alive session)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S16 (harness-reviewer round-2 Critical-1, PROVEN) -- disarming ONE
  # session must NOT release the global spawn lock while it is (or could
  # be) held by an in-flight tick for a DIFFERENT session. Simulates the
  # held-lock state directly (mkdir) rather than racing a real spawn.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s16 "$SCRIPT_DIR/limit-resume.sh" arm
    mkdir -p "$tmp/state/attempt.lock"
    "$SCRIPT_DIR/limit-resume.sh" disarm "test" --session sess-s16
    if [ -d "$tmp/state/attempt.lock" ]; then
      echo "  S16 disarm never releases another tick's held lock: PASS"
    else
      echo "  S16 disarm never releases another tick's held lock: FAIL (lock was freed by an unrelated disarm)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S17 -- a genuinely ABANDONED lock (old mtime, far past
  # TIMEOUT_SECONDS+120s -- the owning tick could only have crashed
  # without running its own EXIT trap) IS reclaimed by the next tick, so
  # the mechanism cannot wedge itself shut forever.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s17 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s17 "2020-01-01T00:00:00Z" 999999
    mkdir -p "$tmp/state/attempt.lock"
    OLD_EPOCH=$(( $(date +%s) - 10000 ))
    python3 -c "
import os
os.utime('$tmp/state/attempt.lock', ($OLD_EPOCH, $OLD_EPOCH))
" 2>/dev/null || touch -t "197001010000" "$tmp/state/attempt.lock" 2>/dev/null || true
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 0
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ -f "$calls" ]; then
      echo "  S17 an abandoned (aged-out) lock is reclaimed, not permanent: PASS"
    else
      echo "  S17 an abandoned (aged-out) lock is reclaimed, not permanent: FAIL (tick stayed wedged)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S18 (harness-reviewer round-3 Critical, PROVEN) -- arm under
  # NL_HOOK_REENTRY=1 must write NO marker at all. This is the actual
  # behavior the safety contract claims ("the child's own
  # SessionStart/Stop/UserPromptSubmit hooks no-op") -- S9 only ever
  # proved the child RECEIVES the flag, never that arm HONORS it; this
  # is the missing other half of that property.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    NL_HOOK_REENTRY=1 CLAUDE_CODE_SESSION_ID=sess-s18 "$SCRIPT_DIR/limit-resume.sh" arm
    if [ ! -d "$tmp/state/armed" ] || [ ! -f "$tmp/state/armed/sess-s18.json" ]; then
      echo "  S18 arm under NL_HOOK_REENTRY=1 writes no marker: PASS"
    else
      echo "  S18 arm under NL_HOOK_REENTRY=1 writes no marker: FAIL (an automation-resumed child could re-arm itself)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S19 -- companion: an already-armed, already-given-up session's giveup
  # sentinel must survive a reentrant arm attempt (the exact amplification
  # risk the round-3 finding named -- a successful automation-resumed
  # child silently resetting its own hard-stop counter).
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    CLAUDE_CODE_SESSION_ID=sess-s19 "$SCRIPT_DIR/limit-resume.sh" arm
    echo "gave up" > "$tmp/state/armed/sess-s19.giveup"
    echo 8 > "$tmp/state/armed/sess-s19.attempts"
    NL_HOOK_REENTRY=1 CLAUDE_CODE_SESSION_ID=sess-s19 "$SCRIPT_DIR/limit-resume.sh" arm
    if [ -f "$tmp/state/armed/sess-s19.giveup" ] && [ "$(cat "$tmp/state/armed/sess-s19.attempts")" = "8" ]; then
      echo "  S19 a reentrant arm cannot reset an existing giveup/attempts: PASS"
    else
      echo "  S19 a reentrant arm cannot reset an existing giveup/attempts: FAIL"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S20 (harness-reviewer round-4 Critical, PROVEN) -- a lock whose
  # recorded owner pid is CONFIRMED ALIVE must never be reclaimed, no
  # matter how old its mtime is. Uses a REAL background process (this
  # test's own short-lived `sleep`) as the "still-alive owner" so the
  # `kill -0` check inside _lr_reclaim_stale_lock has a genuine live pid
  # to find, not a fabricated number that might coincidentally be dead.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s20 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s20 "2020-01-01T00:00:00Z" 999999
    sleep 60 & owner_pid=$!
    mkdir -p "$tmp/state/attempt.lock"
    printf '%s\n' "$owner_pid" > "$tmp/state/attempt.lock/owner"
    OLD_EPOCH=$(( $(date +%s) - 10000 ))
    python3 -c "
import os
os.utime('$tmp/state/attempt.lock', ($OLD_EPOCH, $OLD_EPOCH))
" 2>/dev/null || touch -t "197001010000" "$tmp/state/attempt.lock" 2>/dev/null || true
    calls="$tmp/calls"; bindir="$tmp/bin"
    _write_stub_claude "$bindir" "$calls" 0
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    result_ok=1
    [ ! -f "$calls" ] || result_ok=0
    [ -d "$tmp/state/attempt.lock" ] || result_ok=0
    [ "$(cat "$tmp/state/attempt.lock/owner" 2>/dev/null)" = "$owner_pid" ] || result_ok=0
    kill "$owner_pid" 2>/dev/null; wait "$owner_pid" 2>/dev/null
    if [ "$result_ok" = "1" ]; then
      echo "  S20 a lock with a CONFIRMED-ALIVE owner is never reclaimed, however old: PASS"
    else
      echo "  S20 a lock with a CONFIRMED-ALIVE owner is never reclaimed, however old: FAIL (stub_called=$([ -f "$calls" ] && echo yes || echo no), lock_survived=$([ -d "$tmp/state/attempt.lock" ] && echo yes || echo no))"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # S21 (harness-reviewer round-4 Critical, PROVEN) -- a tick's own EXIT
  # trap must NOT remove the lock if its recorded owner no longer matches
  # this process's own pid (i.e. the lock was reclaimed by someone else
  # mid-flight). The stub itself rewrites the owner file to a foreign pid
  # DURING the spawn, deterministically reproducing "ownership changed
  # while this tick was still running" without relying on real inter-
  # process timing.
  (
    tmp=$(mktemp -d)
    cd "$tmp" && git init --quiet && git config user.email t@example.com && git config user.name T
    git commit --allow-empty -q -m init
    export LIMIT_RESUME_STATE_DIR="$tmp/state"
    export LIMIT_RESUME_MIN_SILENCE_SECONDS=0
    CLAUDE_CODE_SESSION_ID=sess-s21 "$SCRIPT_DIR/limit-resume.sh" arm
    _write_hb_fixture "$tmp/hb" sess-s21 "2020-01-01T00:00:00Z" 999999
    bindir="$tmp/bin"; mkdir -p "$bindir"
    # Simulates "someone else reclaimed this lock while I was still
    # running": overwrite the owner file to a foreign pid before this
    # tick's own EXIT trap ever gets a chance to check it. The real path
    # is substituted at WRITE time via a quoted heredoc's own $tmp
    # expansion (no later sed dance needed).
    cat > "$bindir/claude" <<STUB
#!/bin/bash
printf '999999\n' > "$tmp/state/attempt.lock/owner" 2>/dev/null
echo "stub: resumed OK"
exit 0
STUB
    chmod +x "$bindir/claude"
    PATH="$bindir:$PATH" HEARTBEAT_STATE_DIR="$tmp/hb" "$SCRIPT_DIR/limit-resume.sh" tick
    if [ -d "$tmp/state/attempt.lock" ] && [ "$(cat "$tmp/state/attempt.lock/owner" 2>/dev/null)" = "999999" ]; then
      echo "  S21 EXIT trap never removes a lock whose owner no longer matches: PASS"
    else
      echo "  S21 EXIT trap never removes a lock whose owner no longer matches: FAIL (a foreign-owned lock was deleted)"; exit 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  arm)          shift; cmd_arm "$@" ;;
  disarm)       shift; cmd_disarm "$@" ;;
  tick)         cmd_tick ;;
  status)       shift; cmd_status "$@" ;;
  --self-test)  _self_test; exit $? ;;
  -h|--help|"")
    cat <<'USAGE_END' >&2
limit-resume.sh -- bounded, per-session, turn-scoped auto-resume watchdog.

Usage:
  limit-resume.sh arm [--session <id>] [--cwd <dir>]
  limit-resume.sh disarm [<reason>] [--session <id>]
  limit-resume.sh tick
  limit-resume.sh status [<session-id>] [--json] [--all]
  limit-resume.sh --self-test
USAGE_END
    exit 2
    ;;
  *)
    echo "limit-resume.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
