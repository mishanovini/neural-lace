#!/bin/bash
# single-flight-lib.sh — universal single-flight + recursion guard, PLUS the
# HALT/drain flag (harness-execution-redesign-2026-08, Task 1 "Stage 0a";
# invariant 4 and invariant 11 of docs/designs/harness-execution-redesign-
# considerations-2026-08-02.md §2).
#
# ============================================================
# WHY THIS EXISTS (and why it is NOT a replacement for the two guards
# that already exist — Chesterton's Fence)
# ============================================================
#
# The 2026-08-02 self-DoS incident's trigger (per the considerations brief
# §1.1 "Trigger" row) was a resume-origin SessionStart invocation that did
# not reliably carry the existing wiring marker (NL_SESSIONSTART_ORIGIN=1),
# so hooks/lib/sessionstart-singleflight.sh's debounce — which only ever
# fires when a caller explicitly checks that marker — never engaged, and
# harness-doctor.sh + session-start-digest.sh ran their full heavy body on
# every concurrently-resuming session. Separately, hooks/lib/hook-reentry-
# guard.sh only suppresses when a SPAWNER remembers to export
# NL_HOOK_REENTRY=1 before launching a child — another wiring-dependent
# guard.
#
# Both of those are correct, tested, and STAY exactly as they are (they are
# not touched by this file) — invariant 9 (retire-before-extend) demotes
# them from "the sole defense" to "belt", never deletes them; a second,
# independent layer that happens to also catch the resume case is a feature,
# not redundant. What was missing is a guard that fires UNCONDITIONALLY —
# "in the lib, not the wiring" (invariant 4) — regardless of whether any
# caller remembered to set any marker at all. THIS file is that guard: every
# heavy entry point (harness-doctor.sh, session-start-digest.sh, coord-
# sync.sh, supervisor-tick.sh, health-tick.sh) sources it unconditionally
# and calls `sf_guard <name>` (or, for tick wrappers that already have their
# own overlap lock, at least `sf_halt_active`) at the very top of its real
# work — no env var required from the caller's own caller.
#
# ============================================================
# THE CONTRACT
# ============================================================
#
#   sf_guard <name> <ttl_seconds>
#     rc 0 — caller SHOULD RUN (acquired, reclaimed a stale stamp, or a
#            fail-open path was taken).
#     rc 1 — caller SHOULD SKIP. One of three reasons, always named in a
#            one-line stderr notice AND (best-effort) ledgered via
#            signal-ledger.sh's ledger_emit (gate="single-flight",
#            event="skip") so gate-friction telemetry (R3.5) starts
#            accumulating from this task onward:
#              1. HALT/drain flag is set (checked FIRST — an operator's
#                 one-gesture stop always wins).
#              2. Recursion: THIS process tree already has an active
#                 (unreleased) sf_guard hold on the SAME <name> — detected
#                 via an exported env var, so a nested subprocess
#                 invocation (bash spawning bash) is caught with ZERO
#                 filesystem I/O and with no wiring required anywhere in
#                 the call chain between the two invocations.
#              3. Single-flight: a DIFFERENT (unrelated, non-descendant)
#                 process claimed the same <name> within the last
#                 <ttl_seconds> — detected via a shared mkdir-based lock
#                 (same atomic-mkdir + TTL-aged-owner-stamp convention as
#                 sessionstart-singleflight.sh, generalized to any name,
#                 any caller, unconditionally).
#
#   sf_release <name>
#     Releases a hold THIS process's own sf_guard call on <name> is still
#     holding: clears the recursion-guard env var and removes the
#     cross-process mkdir lock. Idempotent — a second call, or a call for
#     a name this process never itself acquired, is a silent no-op — and
#     ownership-safe: it only ever acts when the recursion var IT set is
#     still 1, so it can never tear down a DIFFERENT process's active
#     single-flight hold. See "THE RUN-TO-EXIT ASSUMPTION" below for when
#     this is required, not optional.
#
# ============================================================
# THE RUN-TO-EXIT ASSUMPTION (read before adding a new sf_guard call site
# inside anything that loops)
# ============================================================
#
# sf_guard's recursion guard is an env var, exported into THIS process
# (and inherited by any child it spawns) the moment it acquires — and
# nothing clears it automatically. That is fine, BY DESIGN, for the common
# case: a script that calls `sf_guard NAME || exit 0` once near the top
# and then runs to completion and exits — process exit is what "releases"
# the guard, because the env var dies with the process. The mkdir-based
# cross-process lock is untouched by process exit and simply ages out via
# its own TTL, which is also fine for a one-shot caller.
#
# It is NOT fine for a caller that calls sf_guard for the SAME <name>
# MULTIPLE TIMES from inside ONE long-lived (resident) process — e.g. a
# `--daemon` mode looping `sf_guard tick-name; do_work; sleep N` forever in
# a single bash process. Pass 1 acquires and exports the recursion var;
# every later pass in that SAME process then finds the var already set and
# hits the recursion branch — correct for "a DIFFERENT invocation of this
# call chain is still in flight, skip", wrong here because it is the SAME
# resident loop seeing its own leftover state, so it skips FOREVER after
# pass 1. This is exactly HR-F1 (2026-08-03 harness review): nl-
# maintenance.sh's `--daemon` mode ticked once, then silently wedged on
# its own guard for the rest of its life, while the watchdog kept
# relaunching new daemons on top of the stuck one because nothing ever
# killed it.
#
# THE RULE: any sf_guard call site inside a resident loop (the SAME
# process re-entering the SAME sf_guard <name> more than once over its
# lifetime) MUST pair every acquire with an sf_release once that
# iteration's guarded work is done — guard -> work -> release, every
# pass. A call site that runs to process exit after a single guard does
# NOT need to call sf_release (the common case above). Get this wrong and
# the symptom is silent and easy to miss in review: the FIRST pass works,
# every later pass quietly no-ops, forever.
#
#   sf_halt_active            — rc 0 iff the HALT/drain flag is set.
#   sf_halt_set [reason]      — set the flag (the "one gesture" in
#                                invariant 11: touch/write one file).
#   sf_halt_clear             — clear the flag.
#   sf_halt_reason             — echo the stored reason (best-effort).
#
#   sf_repo_key <path>        — pure-bash (no subprocess spawn) path
#                                sanitizer, identical contract to
#                                sessionstart-singleflight.sh's
#                                ss_repo_key, for callers (e.g.
#                                session-start-digest.sh) whose heavy work
#                                is genuinely per-$PWD and must not dedupe
#                                a different repo's concurrent start
#                                against this one.
#
# Bypass: export SF_DISABLE=1 -> sf_guard always returns 0 (used by every
# other artifact's own --self-test so a held state file never wedges an
# unrelated suite; sf_halt_active also treats SF_DISABLE=1 as "not halted"
# for the same reason).
#
# FAIL-OPEN CONTRACT: identical to sessionstart-singleflight.sh — every
# internal error path (unwritable state dir, missing `find`, a lost mkdir
# race) returns 0 (run). A broken or unwritable lock must NEVER prevent
# real work; only the three EXPLICIT reasons above ever return 1. HALT is
# the sole deliberate exception to "never block real work" — it exists
# specifically so a human always has a one-gesture way to stop the whole
# maintenance layer, which is the entire point of invariant 11.
#
# State:
#   Locks: ${SF_STATE_DIR:-$HOME/.claude/state/single-flight}/<name>.lock/
#            (mkdir-based single-flight claim; per-caller SCOPABLE via
#            SF_STATE_DIR -- e.g. nl-maintenance.sh scopes its own ticks
#            under a private state dir so its lock namespace never
#            collides with an unrelated sf_guard caller's)
#   HALT:  ${SF_HALT_DIR:-$HOME/.claude/state/single-flight}/HALT
#            (presence = drain; content = "<epoch> <reason>")
#
#   HR-F11 (2026-08-03 harness review): HALT resolves via its OWN
#   canonical directory (SF_HALT_DIR), ALWAYS -- regardless of any
#   SF_STATE_DIR a caller scoped its LOCKS to. Before this split, HALT
#   shared SF_STATE_DIR's resolution, so a caller that scoped its lock dir
#   away from the default (nl-maintenance.sh's tick/watchdog guards,
#   SF_STATE_DIR="$(_nm_state_dir)/single-flight") also, silently, moved
#   WHERE the operator's one-gesture HALT had to be written to reach that
#   guard -- the runbook's documented "touch one file" gesture writes the
#   DEFAULT path and never drained those scoped callers directly; only
#   nl-maintenance.sh's own separate, unscoped `sf_halt_active` check
#   inside its tick body (a second, redundant read of the default HALT
#   path) happened to still catch it. SF_HALT_DIR and SF_STATE_DIR default
#   to the SAME directory, so any caller that never scopes either sees NO
#   behavior change; only a caller that scopes SF_STATE_DIR (locks moved)
#   without also scoping SF_HALT_DIR (HALT did not move) is affected, and
#   only for the better -- its sf_guard call now sees the canonical HALT
#   directly, not just via a second caller-side check.
#
# Self-test: bash single-flight-lib.sh --self-test

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_SINGLE_FLIGHT_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_SINGLE_FLIGHT_LIB_SOURCED=1

_sf_state_dir() { printf '%s' "${SF_STATE_DIR:-$HOME/.claude/state/single-flight}"; }

# _sf_sanitize <name> — collapse any character that cannot appear in a bash
# variable name or a filesystem path segment to '_'. Used both for the lock
# directory name and for the recursion-guard env var name.
_sf_sanitize() {
  local s="$1"
  s="${s//[^A-Za-z0-9_]/_}"
  printf '%s' "$s"
}

# sf_repo_key <path> — see header. Mirrors sessionstart-singleflight.sh's
# ss_repo_key exactly (kept as a separate pure-bash copy here rather than a
# cross-lib source, so this file has zero dependency on any other lib and
# can be sourced standalone by any future entry point).
sf_repo_key() {
  local p="${1:-$PWD}"
  p="${p//[:\\\/]/_}"
  printf '%s' "${p:0:80}"
}

# ----------------------------------------------------------------------
# HALT / drain (invariant 11)
# ----------------------------------------------------------------------
# HR-F11 (2026-08-03 harness review): HALT's own directory, resolved
# INDEPENDENTLY of _sf_state_dir -- see the header "State" section for the
# full rationale. Same default as _sf_state_dir so unscoped callers see no
# change; a caller that scopes SF_STATE_DIR away from the default no
# longer silently relocates where the operator's HALT gesture must land.
_sf_halt_dir() { printf '%s' "${SF_HALT_DIR:-$HOME/.claude/state/single-flight}"; }

_sf_halt_flag_path() { printf '%s/HALT' "$(_sf_halt_dir)"; }

sf_halt_active() {
  [[ "${SF_DISABLE:-0}" == "1" ]] && return 1
  [[ -f "$(_sf_halt_flag_path)" ]]
}

sf_halt_set() {
  local reason="${1:-operator halt}" dir
  dir="$(_sf_halt_dir)"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s %s\n' "$(date +%s 2>/dev/null || echo 0)" "$reason" > "$(_sf_halt_flag_path)" 2>/dev/null || return 1
  return 0
}

sf_halt_clear() {
  rm -f "$(_sf_halt_flag_path)" 2>/dev/null
  return 0
}

sf_halt_reason() {
  local f; f="$(_sf_halt_flag_path)"
  [[ -f "$f" ]] || { printf ''; return 0; }
  awk '{ $1=""; sub(/^ /, ""); print; exit }' "$f" 2>/dev/null
}

# ----------------------------------------------------------------------
# Gate-friction ledger bootstrap (R3.5) — best-effort, never fails the
# caller. Reuses the EXISTING ADR 058 D6 ledger (signal-ledger.sh) rather
# than a new mechanism: "skip" is an already-mapped event type in
# observability-consumer-map.json, so no map change is needed for this to
# be consumed by digest/waiver-density immediately.
# ----------------------------------------------------------------------
_sf_ledger() {
  local event="$1" detail="$2"
  command -v ledger_emit >/dev/null 2>&1 || return 0
  ledger_emit "single-flight" "$event" "$detail" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# Cross-process single-flight primitives (mkdir + TTL-aged owner stamp —
# same portable mechanics as sessionstart-singleflight.sh's proven design;
# duplicated rather than sourced so this lib has zero cross-lib dependency).
# ----------------------------------------------------------------------
_sf_stamp_age() {
  local lockdir="$1" ts now
  ts=$(awk 'NR==1{print $2}' "$lockdir/owner" 2>/dev/null)
  now=$(date +%s 2>/dev/null || echo 0)
  if [[ "$ts" =~ ^[0-9]+$ ]] && [[ "$ts" -gt 0 ]] && [[ "$now" =~ ^[0-9]+$ ]] && [[ "$now" -ge "$ts" ]]; then
    echo $(( now - ts )); return 0
  fi
  echo -1
}

# _sf_owner_pid <lockdir> — echoes the pid recorded in <lockdir>/owner
# (field 1), or nothing if unreadable/non-numeric. Field 1 has been the
# owner pid since _sf_write_owner's very first commit (always
# "$$ $(date +%s)"), so no legacy-format migration is needed here.
_sf_owner_pid() {
  local lockdir="$1" pid
  pid=$(awk 'NR==1{print $1}' "$lockdir/owner" 2>/dev/null)
  [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 0 ]] && printf '%s' "$pid"
  return 0
}

# _sf_owner_alive <pid> — rc 0 iff a process with this pid is currently
# running (a plain signal-0 probe; MSYS2/git-bash maps this onto the
# Windows process table for native pids, same as any other bash `kill -0`
# use in this codebase, e.g. nl-maintenance.sh's watchdog identity check).
_sf_owner_alive() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# HR-F3 (2026-08-03 harness review): TTL alone lapses mid-run once the
# guarded work's real cycle exceeds the TTL (the review measured a 552s
# cold doctor-quick cycle; a fresh re-measurement during this fix, 2026-
# 08-03, SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1 bash harness-doctor.sh
# --quick timed via epoch delta, got 421s and 425s on two runs -- all
# comfortably >> the old 120s TTL), so from TTL seconds into any long run
# every concurrent invocation reclaimed the lock and ran concurrently,
# exactly the pathology the guard exists to prevent. Owner-pid liveness is
# checked FIRST and is authoritative when
# available: a lock whose recorded owner process is still alive is NEVER
# reclaimed, no matter how old its stamp is -- this is the actual
# guarantee sf_guard exists to provide (no two owners of the same <name>
# at once), not a time-boxed approximation of it. TTL remains the
# fallback for the two cases liveness can't answer: no pid was recorded
# (a pre-fix lock, or a lockdir written by something other than
# _sf_write_owner), or the owner process is confirmed dead -- the
# realistic reclaim case once a caller's process actually exited without
# releasing (crash, kill -9, power loss).
_sf_is_stale() {
  local lockdir="$1" ttl="$2" age ttl_min pid
  pid="$(_sf_owner_pid "$lockdir")"
  if [[ -n "$pid" ]] && _sf_owner_alive "$pid"; then
    return 1   # owner alive -> NOT stale, regardless of TTL age
  fi
  age=$(_sf_stamp_age "$lockdir")
  if [[ "$age" -ge 0 ]] 2>/dev/null; then
    [[ "$age" -ge "$ttl" ]]; return
  fi
  command -v find >/dev/null 2>&1 || return 0
  ttl_min=$(( (ttl + 59) / 60 )); [[ "$ttl_min" -lt 1 ]] && ttl_min=1
  [[ -n "$(find "$lockdir" -maxdepth 0 -mmin +"$ttl_min" 2>/dev/null)" ]]
}

_sf_write_owner() {
  printf '%s %s\n' "$$" "$(date +%s 2>/dev/null || echo 0)" > "$1/owner" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# sf_guard <name> [ttl_seconds] — see header for the full contract.
# ----------------------------------------------------------------------
sf_guard() {
  local name="$1" ttl="${2:-120}"
  [[ -z "$name" ]] && return 0                    # misuse -> fail-open (run)
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=120
  [[ "${SF_DISABLE:-0}" == "1" ]] && return 0      # explicit bypass (self-tests)

  local key rvar
  key="$(_sf_sanitize "$name")"
  rvar="_SF_ACTIVE_${key}"

  # 1) HALT/drain — checked FIRST; the operator's one-gesture stop wins
  #    over an in-flight recursion hold or a reclaimable stale lock alike.
  if sf_halt_active; then
    echo "[sf-guard] ${name}: HALT flag set ($(_sf_halt_flag_path)) — draining, exiting without doing work" >&2
    _sf_ledger "skip" "${name}: HALT drain"
    return 1
  fi

  # 2) Recursion guard — zero I/O; catches THIS process tree re-entering
  #    the same named entry point (bash export -> child inherits).
  if [[ "${!rvar:-0}" == "1" ]]; then
    echo "[sf-guard] ${name}: recursion detected (already active in this process tree) — skipping" >&2
    _sf_ledger "skip" "${name}: recursion"
    return 1
  fi

  # 3) Cross-process single-flight debounce.
  local base lockdir
  base="$(_sf_state_dir)"
  if ! mkdir -p "$base" 2>/dev/null; then
    export "${rvar}=1"
    return 0                                       # can't make state dir -> fail-open (run)
  fi
  lockdir="${base}/${key}.lock"
  if mkdir "$lockdir" 2>/dev/null; then
    _sf_write_owner "$lockdir"
    export "${rvar}=1"
    return 0
  fi
  if _sf_is_stale "$lockdir" "$ttl"; then
    rm -rf "$lockdir" 2>/dev/null || true
    if mkdir "$lockdir" 2>/dev/null; then
      _sf_write_owner "$lockdir"
      export "${rvar}=1"
      return 0
    fi
    export "${rvar}=1"
    return 0                                       # lost the reclaim race -> proceed anyway
  fi
  echo "[sf-guard] ${name}: single-flight — another invocation ran within ${ttl}s — skipping" >&2
  _sf_ledger "skip" "${name}: single-flight (${ttl}s)"
  return 1
}

# ----------------------------------------------------------------------
# sf_release <name> — see header "THE RUN-TO-EXIT ASSUMPTION" for the full
# contract. Releases THIS process's own hold on <name>: clears the
# recursion var and removes the cross-process mkdir lock. Idempotent and
# ownership-safe by construction — it only acts when the recursion var it
# would clear is still 1, i.e. only when THIS process's own prior sf_guard
# call is the reason it's set. A name never acquired by this process (or
# already released) leaves the var at 0/unset, so this is a silent no-op;
# it can therefore never remove a lock a DIFFERENT process currently holds.
# ----------------------------------------------------------------------
sf_release() {
  local name="$1"
  [[ -z "$name" ]] && return 0
  local key rvar
  key="$(_sf_sanitize "$name")"
  rvar="_SF_ACTIVE_${key}"
  [[ "${!rvar:-0}" != "1" ]] && return 0   # never acquired by this process, or already released
  rm -rf "$(_sf_state_dir)/${key}.lock" 2>/dev/null || true
  unset "$rvar" 2>/dev/null || true
  return 0
}

# ============================================================
# Self-test
# ============================================================
# BASH_SOURCE[0] == $0 guard (mirrors hook-reentry-guard.sh): this file is
# almost always SOURCED by a caller, not executed directly. `source file`
# with no explicit arguments inherits the CALLING script's OWN positional
# parameters — so a caller invoked as `bash caller.sh --self-test` that
# does `source .../single-flight-lib.sh` (no args) would otherwise cause
# THIS block to see that inherited "--self-test" and run/exit here,
# silently truncating the caller's own execution before it ever reaches
# ITS OWN --self-test dispatch. (This is the exact documented gotcha
# harness-doctor.sh's self-test comments call out for
# sessionstart-singleflight.sh — that lib lacks this guard and instead
# requires every self-test call site to remember `source lib.sh ""`. This
# lib fixes the class at the source instead of documenting a workaround.)
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  PASS=0; FAIL=0
  _tmp=$(mktemp -d 2>/dev/null || mktemp -d -t sfl) || { echo "cannot mktemp" >&2; exit 1; }
  trap 'rm -rf "$_tmp"' EXIT
  export SF_STATE_DIR="$_tmp/sf"
  # HR-F11 (2026-08-03 harness review): HALT now resolves via its OWN
  # SF_HALT_DIR, independent of SF_STATE_DIR. Without this explicit
  # override every existing HALT scenario below (S9, S10, S12, S13) would
  # silently fall through to the REAL default ($HOME/.claude/state/single-
  # flight/HALT) instead of this self-test's sandbox -- exactly the
  # "self-tests override SF_HALT_DIR explicitly" requirement the finding's
  # fix names. Same tmp dir as SF_STATE_DIR by default, so those existing
  # scenarios' behavior is unchanged; the NEW split-specific scenarios
  # below (S20/S21) override both independently to prove the split is
  # real, not coincidental default-matching.
  export SF_HALT_DIR="$_tmp/sf"
  _ok() { if [[ "$1" == "$2" ]]; then echo "self-test: PASS — $3" >&2; PASS=$((PASS+1)); else echo "self-test: FAIL — $3 (got '$1' want '$2')" >&2; FAIL=$((FAIL+1)); fi; }
  _contains() { if [[ "$1" == *"$2"* ]]; then echo "self-test: PASS — $3" >&2; PASS=$((PASS+1)); else echo "self-test: FAIL — $3 (output did not contain '$2': $1)" >&2; FAIL=$((FAIL+1)); fi; }

  # S1: clean acquire -> rc 0, lockdir created, recursion var exported.
  # NOTE: called DIRECTLY (not via `$(...)` command substitution) because
  # `export` inside a command-substitution subshell never persists to the
  # caller — this is deliberately the SAME shape a real top-of-script
  # `sf_guard <name> || exit 0` call has, and is exactly what makes the
  # recursion check work in production (the child process that inherits
  # the export IS a real subprocess, not a substitution subshell).
  sf_guard s1 120 2>"$_tmp/s1.err"; rc=$?
  _ok "$rc" 0 "S1 clean acquire returns 0"
  [[ -d "$SF_STATE_DIR/s1.lock" ]] && _ok present present "S1 lockdir created" || _ok absent present "S1 lockdir created"
  _ok "${_SF_ACTIVE_s1:-unset}" 1 "S1 recursion-guard env var exported after acquire"

  # S2: recursion — SAME process, SAME name, called again (rvar already
  # exported by S1 above, simulating a nested subprocess that inherited it).
  sf_guard s1 120 2>"$_tmp/s2.err"; rc=$?
  out2="$(cat "$_tmp/s2.err" 2>/dev/null)"
  _ok "$rc" 1 "S2 recursion (same process tree, same name) -> skip (rc 1)"
  _contains "$out2" "recursion" "S2 message names 'recursion'"

  # S3: single-flight — a DIFFERENT (never-recursion-marked) name, pre-
  # claimed by a fresh lock as if from an unrelated process.
  mkdir -p "$SF_STATE_DIR/s3.lock"
  _sf_write_owner "$SF_STATE_DIR/s3.lock"
  out3="$(sf_guard s3 120 2>&1)"; rc=$?
  _ok "$rc" 1 "S3 fresh lock held by another process -> skip (rc 1)"
  _contains "$out3" "single-flight" "S3 message names 'single-flight'"

  # S4: stale lock -> reclaim (rc 0). Back-date the owner epoch.
  mkdir -p "$SF_STATE_DIR/s4.lock"; printf '%s %s\n' 99999 1 > "$SF_STATE_DIR/s4.lock/owner"
  sf_guard s4 120; rc=$?; _ok "$rc" 0 "S4 stale stamp -> reclaim (rc 0)"

  # S5: re-acquire after removal -> rc 0 (fresh name each time to avoid
  # cross-contamination with the recursion-guard env vars set above).
  sf_guard s5 120 >/dev/null; rm -rf "$SF_STATE_DIR/s5.lock"; unset _SF_ACTIVE_s5
  sf_guard s5 120; rc=$?; _ok "$rc" 0 "S5 re-acquire after removal (rc 0)"

  # S6: SF_DISABLE bypass -> rc 0 even with a fresh held stamp AND an
  # active recursion var.
  SF_DISABLE=1 sf_guard s1 120; rc=$?; _ok "$rc" 0 "S6 SF_DISABLE bypass ignores both recursion and single-flight state"

  # S7: fail-open when state dir is uncreatable (base under a regular file).
  _f="$_tmp/afile"; : > "$_f"
  SF_STATE_DIR="$_f/cannot" sf_guard s7 120; rc=$?; _ok "$rc" 0 "S7 uncreatable state dir -> fail-open (rc 0)"

  # S8: mutual exclusion — with one fresh holder (a brand-new name, never
  # recursion-marked), N concurrent SUBPROCESS attempts all skip (each
  # subshell inherits the CURRENT env, which has no _SF_ACTIVE_s8 set, so
  # this genuinely exercises the mkdir path, not the recursion path).
  ( unset _SF_ACTIVE_s8 2>/dev/null; sf_guard s8 120 ) >/dev/null
  acq=0
  for i in 1 2 3 4 5; do
    ( unset _SF_ACTIVE_s8 2>/dev/null; sf_guard s8 120 ) >/dev/null 2>&1 && acq=$((acq+1))
  done
  _ok "$acq" 0 "S8 held stamp -> all 5 concurrent (non-descendant) attempts skip"

  # S9: HALT — set, active check, guard drains, clear, guard resumes.
  _ok "$(sf_halt_active && echo yes || echo no)" no "S9a HALT inactive by default"
  sf_halt_set "test-drain" >/dev/null
  _ok "$(sf_halt_active && echo yes || echo no)" yes "S9b HALT active after sf_halt_set"
  out9="$(sf_guard s9 120 2>&1)"; rc=$?
  _ok "$rc" 1 "S9c sf_guard drains while HALT is active (rc 1)"
  _contains "$out9" "HALT" "S9d drain message names HALT"
  _contains "$(sf_halt_reason)" "test-drain" "S9e sf_halt_reason echoes the stored reason"
  sf_halt_clear
  _ok "$(sf_halt_active && echo yes || echo no)" no "S9f HALT inactive after sf_halt_clear"
  out9b="$(sf_guard s9 120 2>&1)"; rc=$?
  _ok "$rc" 0 "S9g sf_guard resumes normally once HALT is cleared"

  # S10: HALT wins over a fresh single-flight lock AND over an active
  # recursion var (checked FIRST, per the header contract).
  mkdir -p "$SF_STATE_DIR/s10.lock"; _sf_write_owner "$SF_STATE_DIR/s10.lock"
  sf_halt_set "s10-drain" >/dev/null
  out10="$(sf_guard s10 120 2>&1)"; rc=$?
  _ok "$rc" 1 "S10 HALT still drains even with a fresh single-flight lock present"
  _contains "$out10" "HALT" "S10 message names HALT, not single-flight (HALT checked first)"
  sf_halt_clear

  # S11: sf_repo_key — pure-bash path sanitization, distinct per path.
  r11a="$(sf_repo_key '/c/Users/x/repo-a')"
  _ok "$r11a" "_c_Users_x_repo-a" "S11a sf_repo_key sanitizes slashes/colons to underscores"
  r11b="$(sf_repo_key '/c/Users/x/repo-b')"
  if [[ "$r11a" != "$r11b" ]]; then
    echo "self-test: PASS — S11b different repo paths -> different keys" >&2; PASS=$((PASS+1))
  else
    echo "self-test: FAIL — S11b different repo paths produced the SAME key ('$r11a')" >&2; FAIL=$((FAIL+1))
  fi

  # S12: ledger integration (R3.5 bootstrap) — a fake ledger_emit records
  # the skip event with the gate name this lib promises ("single-flight").
  LEDGER_CALLS_FILE="$(mktemp 2>/dev/null || printf '%s/sfl-selftest-ledger-%s' "$_tmp" "$$")"
  ledger_emit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$LEDGER_CALLS_FILE"; }
  sf_halt_set "s12-drain" >/dev/null
  sf_guard s12 120 >/dev/null 2>&1
  sf_halt_clear
  if [[ -f "$LEDGER_CALLS_FILE" ]] && grep -q '^single-flight|skip|' "$LEDGER_CALLS_FILE" 2>/dev/null; then
    echo "self-test: PASS — S12 sf_guard's skip path calls ledger_emit(single-flight, skip, ...)" >&2; PASS=$((PASS+1))
  else
    echo "self-test: FAIL — S12 expected a ledger_emit(single-flight, skip, ...) call; got: $(cat "$LEDGER_CALLS_FILE" 2>/dev/null)" >&2; FAIL=$((FAIL+1))
  fi
  unset -f ledger_emit
  rm -f "$LEDGER_CALLS_FILE" 2>/dev/null

  # S13: sf_guard with no ledger_emit defined never fails the caller
  # (best-effort contract — mirrors hook-reentry-guard.sh's own S7).
  unset -f ledger_emit 2>/dev/null
  sf_halt_set "s13-drain" >/dev/null
  sf_guard s13 120 >/dev/null 2>&1; rc=$?
  sf_halt_clear
  _ok "$rc" 1 "S13 sf_guard still returns the correct rc with no ledger_emit defined"

  # S14: sf_release (HR-F1) — clears the recursion var + lock so a
  # resident loop can guard -> work -> release -> guard again WITHOUT ever
  # hitting "recursion detected" on pass 2+.
  sf_guard s14 120 >/dev/null 2>&1
  _ok "${_SF_ACTIVE_s14:-unset}" 1 "S14a sf_guard s14 acquired (pre-release state)"
  sf_release s14
  _ok "${_SF_ACTIVE_s14:-unset}" "unset" "S14b sf_release clears the recursion var"
  if [[ -d "$SF_STATE_DIR/s14.lock" ]]; then
    _ok present absent "S14c sf_release removes the lock dir"
  else
    _ok absent absent "S14c sf_release removes the lock dir"
  fi
  out14="$(sf_guard s14 120 2>&1)"; rc=$?
  _ok "$rc" 0 "S14d re-acquire after sf_release succeeds — THE fix for HR-F1's resident-loop wedge"
  if [[ "$out14" == *recursion* ]]; then
    _ok recursion-seen none "S14e no false recursion message on re-acquire after release"
  else
    _ok none none "S14e no false recursion message on re-acquire after release"
  fi

  # S15: sf_release idempotency — a second release, or a release for a
  # name this process never acquired, is a silent no-op, never an error.
  sf_release s14 2>"$_tmp/s15a.err"; rc=$?
  _ok "$rc" 0 "S15a double-release is a no-op (rc 0)"
  _ok "$(cat "$_tmp/s15a.err" 2>/dev/null)" "" "S15b double-release prints nothing to stderr"
  sf_release never-acquired-name-xyz 2>"$_tmp/s15c.err"; rc=$?
  _ok "$rc" 0 "S15c releasing a name this process never acquired is a no-op (rc 0)"

  # S16: sf_release ownership safety — it must NEVER tear down a lock this
  # process did not itself acquire (Windows PID reuse means an unverified
  # release would be as dangerous as an unverified kill). Simulate a lock
  # held by a DIFFERENT process: create the lockdir directly, WITHOUT ever
  # calling sf_guard s16 in this process (so _SF_ACTIVE_s16 stays unset).
  mkdir -p "$SF_STATE_DIR/s16.lock"
  _sf_write_owner "$SF_STATE_DIR/s16.lock"
  unset _SF_ACTIVE_s16 2>/dev/null
  sf_release s16
  if [[ -d "$SF_STATE_DIR/s16.lock" ]]; then
    _ok present present "S16 sf_release leaves a lock this process never acquired untouched (ownership safety)"
  else
    _ok absent present "S16 sf_release leaves a lock this process never acquired untouched (ownership safety)"
  fi
  rm -rf "$SF_STATE_DIR/s16.lock" 2>/dev/null

  # S17/S18/S19: HR-F3 owner-pid liveness (2026-08-03 harness review) —
  # _sf_is_stale must NEVER reclaim a lock whose recorded owner process is
  # still alive, no matter how stale the TTL says it is; it must still
  # reclaim once the owner is confirmed dead (the realistic case); and it
  # falls back to pure TTL aging when the owner file carries no valid pid.

  # S17: live owner (this test process's own $$), stamp far older than a
  # tiny ttl -> single-flight skip, NOT reclaimed, because the owner is
  # alive (liveness wins over TTL entirely).
  mkdir -p "$SF_STATE_DIR/s17.lock"
  printf '%s %s\n' "$$" 1 > "$SF_STATE_DIR/s17.lock/owner"
  out17="$(sf_guard s17 5 2>&1)"; rc=$?
  _ok "$rc" 1 "S17a live-owner lock (age >> ttl) is NOT reclaimed -- HR-F3"
  _contains "$out17" "single-flight" "S17b live-owner skip message names single-flight (not a fabricated recursion)"
  if [[ -d "$SF_STATE_DIR/s17.lock" ]]; then
    _ok present present "S17c live-owner lockdir survives (not rm -rf'd)"
  else
    _ok absent present "S17c live-owner lockdir survives (not rm -rf'd)"
  fi
  rm -rf "$SF_STATE_DIR/s17.lock"

  # S18: dead owner (a real pid this shell forked and already reaped) +
  # stamp older than ttl -> reclaimed (rc 0), same as the pre-fix
  # TTL-only behavior for the realistic case (owner process actually gone).
  ( : ) & _dead_pid=$!
  wait "$_dead_pid" 2>/dev/null
  mkdir -p "$SF_STATE_DIR/s18.lock"
  printf '%s %s\n' "$_dead_pid" 1 > "$SF_STATE_DIR/s18.lock/owner"
  sf_guard s18 5; rc=$?
  _ok "$rc" 0 "S18 dead-owner lock (age >> ttl) IS reclaimed -- HR-F3"

  # S19: no pid recorded (owner file carries a non-numeric field-1, e.g. a
  # lockdir not written by _sf_write_owner) -> falls back to pure TTL
  # aging, unaffected by liveness (there is no pid to check liveness OF).
  mkdir -p "$SF_STATE_DIR/s19.lock"
  printf '%s %s\n' - 1 > "$SF_STATE_DIR/s19.lock/owner"
  sf_guard s19 5; rc=$?
  _ok "$rc" 0 "S19 no-pid owner stamp falls back to TTL aging -> reclaimed when stale"

  # S20/S21: HR-F11 HALT canonical-path split (2026-08-03 harness review).

  # S20: HALT written to the canonical SF_HALT_DIR still drains sf_guard
  # even when the CALLER scoped SF_STATE_DIR (its locks) somewhere else
  # entirely -- the exact nl-maintenance.sh tick/watchdog shape
  # (SF_STATE_DIR="$(_nm_state_dir)/single-flight"). HALT itself is never
  # written into the scoped lock dir.
  _scoped="$_tmp/s20-scoped-locks"
  _canon="$_tmp/s20-canonical-halt"
  mkdir -p "$_scoped" "$_canon"
  SF_HALT_DIR="$_canon" sf_halt_set "s20-drain" >/dev/null
  out20="$(SF_STATE_DIR="$_scoped" SF_HALT_DIR="$_canon" sf_guard s20 120 2>&1)"; rc=$?
  _ok "$rc" 1 "S20a HALT in canonical SF_HALT_DIR drains sf_guard even though SF_STATE_DIR is scoped elsewhere -- HR-F11"
  _contains "$out20" "HALT" "S20b drain message names HALT"
  if [[ -f "$_scoped/HALT" ]]; then
    _ok present absent "S20c HALT is never written into the scoped SF_STATE_DIR (locks/HALT stay split)"
  else
    _ok absent absent "S20c HALT is never written into the scoped SF_STATE_DIR (locks/HALT stay split)"
  fi
  SF_HALT_DIR="$_canon" sf_halt_clear

  # S21: the split is REAL, not coincidental default-matching -- a HALT
  # file dropped only under a scoped SF_STATE_DIR (simulating the pre-fix
  # bug: HALT co-located with per-caller-scoped locks) must NOT drain a
  # guard call whose SF_HALT_DIR points elsewhere.
  printf '%s %s\n' "$(date +%s 2>/dev/null || echo 0)" "s21-scoped-only" > "$_scoped/HALT"
  out21="$(SF_STATE_DIR="$_scoped" SF_HALT_DIR="$_tmp/s21-unused-canonical" sf_guard s21 120 2>&1)"; rc=$?
  _ok "$rc" 0 "S21 a HALT file dropped only in a scoped SF_STATE_DIR (not SF_HALT_DIR) does not drain -- proves locks/HALT resolution paths are genuinely independent"
  rm -f "$_scoped/HALT"

  echo "" >&2
  echo "self-test summary: $PASS passed, $FAIL failed" >&2
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi
