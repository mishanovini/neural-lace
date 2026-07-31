# portable-timeout.sh — shared library: ONE bounded-subprocess primitive that
# works on stock macOS, where GNU `timeout` does not exist.
#
# ============================================================
# WHY THIS EXISTS (plan docs/plans/macos-portability-2026-07.md, task M3)
# ============================================================
#
# `timeout` is GNU coreutils. It is NOT part of the BSD userland Apple ships,
# so on a stock Mac (no `brew install coreutils`, or coreutils installed but
# gnubin not on PATH) every bare `timeout N cmd` in this harness fails with
# rc=127 "command not found". Two distinct defects followed from that:
#
#   1. MIS-REPORT. rc=127 is indistinguishable from a real failure of the
#      wrapped command, so the caller blames the wrong thing. Measured on a
#      stock Mac before this lib landed:
#        - runtime-verification-executor.sh reported "curl exit 127" for
#          evidence whose curl was never run;
#        - harness-doctor.sh's self-test sweep RED-flagged EVERY hook with
#          "--self-test exited 127" — a fully red doctor, none of it true.
#
#   2. SILENTLY-DROPPED BOUND. The files that already guarded with
#      `command -v timeout || <run it anyway>` did not mis-report, but they
#      quietly ran UNBOUNDED on macOS. A SessionStart `git fetch` against a
#      dead remote, or one hung hook in the doctor's ~50-hook sweep, then
#      hangs with no bound at all. The plan's Edge Cases name this
#      explicitly: "A `timeout` fallback must not silently run unbounded."
#
# This lib fixes both: it prefers real GNU `timeout` when present (so nothing
# changes on Windows/Git-bash or on a coreutils Mac), and otherwise bounds the
# command itself with a background + poll + tree-kill loop.
#
# ============================================================
# THE CONTRACT
# ============================================================
#
#   nl_run_bounded <seconds> <cmd> [args...]
#
#     Runs <cmd> with a wall-clock bound of <seconds>.
#     Returns the command's own exit status if it finished in time.
#     Returns 124 if the bound expired — the SAME code GNU `timeout` uses,
#     so existing `rc == 124` checks (health-tick.sh, supervisor-tick.sh)
#     keep working unchanged on both paths.
#     Returns 2 if called with no command.
#
#     stdout/stderr pass through untouched, so `out="$(nl_run_bounded 10 foo)"`
#     captures exactly what `out="$(timeout 10s foo)"` captured.
#
#   nl_run_bounded_mode
#
#     Echoes "timeout" or "poll" — which implementation nl_run_bounded will
#     use here. Callers use it for honest logging; self-tests use it to force
#     coverage of both paths.
#
# ============================================================
# FIDELITY: where the fallback differs from GNU timeout (stated, not hidden)
# ============================================================
#
#   - Granularity. Expiry is detected on a 1-second clock (bash's `SECONDS`,
#     which costs no fork), so a bound of N fires somewhere in [N, N+1). GNU
#     timeout is exact. Every bound in this harness is >= 10s except in tests,
#     so a sub-second overshoot is immaterial; correctness of the BOUND is
#     what matters, not its precision.
#   - Escalation. On expiry the fallback sends SIGTERM to the whole process
#     tree, waits a short grace period, then SIGKILL to any survivor. Bare GNU
#     `timeout` (no `-k`) sends only SIGTERM. The fallback is therefore
#     STRICTER, which is deliberate: this repo has already paid for a
#     timeout-without-kill leak (manifest: "auditor.js runCli timeout-without-
#     kill leaked 781 bash.exe / 3 reboots, fixed 2026-07-14"). The GNU path
#     is left byte-identical to today's behavior on purpose — adding `-k`
#     there would change Windows behavior, which this plan puts out of scope.
#   - Tree kill. Descendants are discovered from a single `ps -A -o pid=,ppid=`
#     snapshot taken BEFORE any signal (after the root dies its children are
#     reparented and the linkage is gone). If `ps` yields nothing usable, only
#     the direct child is signalled — degraded, but never worse than not
#     killing at all. There is a theoretical pid-reuse window between snapshot
#     and kill; GNU timeout has the same class of exposure and it has never
#     been observed here.
#   - `SECONDS` is READ, never assigned — health-tick.sh uses `SECONDS` for
#     its own wall-clock budget and clobbering it would silently corrupt that.
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/lib/portable-timeout.sh"       # from hooks/*.sh
#   source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh"    # from scripts/*.sh
#
# Callers source it defensively (`2>/dev/null || true`) and define a loud shim
# if it is missing, so a partial install degrades to today's behavior with a
# visible warning rather than hard-failing the hook.
#
# Portability floor: bash 3.2.57 (Apple's /bin/bash) + BSD userland. No
# associative arrays, no mapfile, no ${x^^}, no &>>, no `date -d`.

if [ -n "${_NL_PORTABLE_TIMEOUT_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
_NL_PORTABLE_TIMEOUT_LOADED=1

# ----------------------------------------------------------------------
# _nl_rb_have_timeout — is real GNU timeout on PATH? Probed once and cached;
# `command -v` is a builtin so this is cheap either way, but the cache keeps
# a 50-iteration sweep from re-probing 50 times.
# NL_PORTABLE_TIMEOUT_FORCE_POLL=1 forces the fallback path (self-test hook —
# it is the only way to exercise the macOS codepath on a machine that HAS
# coreutils installed, which is every machine this was authored on).
# ----------------------------------------------------------------------
_NL_RB_MODE=""
_nl_rb_mode() {
  if [ -z "$_NL_RB_MODE" ]; then
    if [ "${NL_PORTABLE_TIMEOUT_FORCE_POLL:-0}" = "1" ]; then
      _NL_RB_MODE="poll"
    elif command -v timeout >/dev/null 2>&1; then
      _NL_RB_MODE="timeout"
    else
      _NL_RB_MODE="poll"
    fi
  fi
  printf '%s' "$_NL_RB_MODE"
}

nl_run_bounded_mode() { _nl_rb_mode; }

# ----------------------------------------------------------------------
# _nl_rb_tree_pids <root> — echo "<root> <descendant pids...>", discovered
# breadth-first from ONE ps snapshot. Pure bash + one fork.
# The heredoc (not a pipe) keeps the read-loop in THIS shell so the
# accumulator variables survive.
# ----------------------------------------------------------------------
_nl_rb_tree_pids() {
  local root="$1"
  local snap all frontier next depth pid ppid
  snap="$(ps -A -o pid=,ppid= 2>/dev/null)"
  all="$root"
  frontier="$root"
  depth=0
  while [ -n "$frontier" ] && [ "$depth" -lt 25 ]; do
    next=""
    while read -r pid ppid; do
      [ -z "$pid" ] && continue
      [ -z "$ppid" ] && continue
      case " $frontier " in
        *" $ppid "*) next="$next $pid"; all="$all $pid" ;;
      esac
    done <<_NL_RB_SNAP
$snap
_NL_RB_SNAP
    frontier="$next"
    depth=$(( depth + 1 ))
  done
  printf '%s' "$all"
}

# ----------------------------------------------------------------------
# _nl_rb_signal_tree <signal> <pid-list> — best-effort; never fails.
# ----------------------------------------------------------------------
_nl_rb_signal_tree() {
  local sig="$1"; shift
  local p
  for p in $*; do
    [ -n "$p" ] && kill "-$sig" "$p" 2>/dev/null
  done
  return 0
}

# ----------------------------------------------------------------------
# _nl_rb_nap — one poll interval. Fractional sleep keeps a fast command from
# paying a full second; both BSD and GNU sleep accept it, but if this system's
# sleep rejects it we degrade to 1s rather than spinning hot.
# ----------------------------------------------------------------------
_NL_RB_FRAC=""
_nl_rb_nap() {
  if [ -z "$_NL_RB_FRAC" ]; then
    if sleep 0.05 2>/dev/null; then _NL_RB_FRAC=1; else _NL_RB_FRAC=0; fi
  fi
  if [ "$_NL_RB_FRAC" = "1" ]; then sleep 0.05; else sleep 1; fi
}

# ----------------------------------------------------------------------
# nl_run_bounded <seconds> <cmd...>
# ----------------------------------------------------------------------
nl_run_bounded() {
  local secs="${1:-}"
  shift 2>/dev/null || true
  [ "$#" -gt 0 ] || return 2

  # Normalize: integer seconds, minimum 1. A caller passing "20s" or garbage
  # must not turn into an unbounded run.
  secs="${secs%s}"
  case "$secs" in
    ''|*[!0-9]*) secs=10 ;;
  esac
  [ "$secs" -lt 1 ] && secs=1

  if [ "$(_nl_rb_mode)" = "timeout" ]; then
    timeout "${secs}s" "$@"
    return $?
  fi

  # ---- portable fallback: background + poll + tree-kill ----
  "$@" &
  local child=$!
  local t0=$SECONDS

  # Phase 1 — bounded tight spin. `kill` is a builtin, so each probe is one
  # cheap syscall and no fork. A command that finishes immediately is
  # detected in well under a millisecond, instead of paying a full sleep
  # interval it never needed. Measured on this Mac: an instantly-exiting
  # child is reaped after ~100-150 spins, so 400 is ~3x headroom; the whole
  # phase costs under 1ms even when it runs to completion.
  local spins=0
  while [ "$spins" -lt 400 ]; do
    kill -0 "$child" 2>/dev/null || break
    spins=$(( spins + 1 ))
  done

  # Phase 2 — sleep-polling for anything still alive.
  local naps=0
  while [ $(( SECONDS - t0 )) -lt "$secs" ]; do
    kill -0 "$child" 2>/dev/null || break
    _nl_rb_nap
    naps=$(( naps + 1 ))
    # After ~2s of fine-grained polling, back off to 1s so a 1500s bound
    # does not fork `sleep` 30,000 times.
    if [ "$naps" -ge 40 ]; then _NL_RB_FRAC=0; fi
  done

  if ! kill -0 "$child" 2>/dev/null; then
    # Finished inside the bound — propagate its real status.
    wait "$child" 2>/dev/null
    return $?
  fi

  # Expired. Snapshot the tree BEFORE signalling (once the root dies its
  # children are reparented and the ppid linkage is gone), TERM the tree,
  # grace, then KILL any survivor.
  #
  # The whole block runs under `2>/dev/null` to swallow bash's OWN
  # "line N: 12345 Terminated: 15 ..." job notice, which it emits
  # asynchronously at the next command boundary after the signal lands —
  # i.e. inside the grace loop, where a per-command redirect cannot catch
  # it. This suppresses only THIS shell's notice: the child forked before
  # the redirect and holds its own dup of the original fd 2, so a dying
  # child's stderr still reaches the caller unchanged.
  {
    local pids
    pids="$(_nl_rb_tree_pids "$child")"
    _nl_rb_signal_tree TERM "$pids"
    local g=0
    while [ "$g" -lt 20 ]; do
      kill -0 "$child" 2>/dev/null || break
      sleep 0.05 2>/dev/null || sleep 1
      g=$(( g + 1 ))
    done
    _nl_rb_signal_tree KILL "$pids"
    wait "$child" 2>/dev/null
  } 2>/dev/null
  return 124
}

# ======================================================================
# --self-test
# ======================================================================
# Guarded on BASH_SOURCE == $0 so that sourcing this lib from a script that
# was itself invoked as `bash foo.sh --self-test` does NOT run this suite
# (the sourced file inherits the caller's positional parameters).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then
  PASSED=0
  FAILED=0
  _p() { printf 'self-test (%s): PASS\n' "$1" >&2; PASSED=$((PASSED+1)); }
  _f() { printf 'self-test (%s): FAIL — %s\n' "$1" "$2" >&2; FAILED=$((FAILED+1)); }

  # Every scenario runs TWICE: once on whatever this machine has (usually
  # real GNU timeout) and once with the poll fallback FORCED. The forced pass
  # is the one that proves the macOS codepath, and it is the only reason this
  # suite is trustworthy on a machine with coreutils installed.
  for _MODE in native forced-poll; do
    if [ "$_MODE" = "forced-poll" ]; then
      NL_PORTABLE_TIMEOUT_FORCE_POLL=1
      export NL_PORTABLE_TIMEOUT_FORCE_POLL
    else
      NL_PORTABLE_TIMEOUT_FORCE_POLL=0
      export NL_PORTABLE_TIMEOUT_FORCE_POLL
    fi
    _NL_RB_MODE=""   # re-probe under the new forcing
    _M="$_MODE/$(_nl_rb_mode)"

    # T1 — a command that finishes in time returns ITS status, not 124.
    if nl_run_bounded 10 true; then _p "T1a fast-command-rc0 [$_M]"; else _f "T1a fast-command-rc0 [$_M]" "rc=$?"; fi
    nl_run_bounded 10 sh -c 'exit 3'; _rc=$?
    if [ "$_rc" = "3" ]; then _p "T1b exit-status-propagates [$_M]"; else _f "T1b exit-status-propagates [$_M]" "expected 3, got $_rc"; fi

    # T2 — stdout is captured through command substitution, unchanged.
    _out="$(nl_run_bounded 10 printf 'hello-%s' world)"
    if [ "$_out" = "hello-world" ]; then _p "T2 stdout-captured [$_M]"; else _f "T2 stdout-captured [$_M]" "got '$_out'"; fi

    # T3 — THE LOAD-BEARING ONE: a command that overruns is actually killed,
    # returns 124, and returns in about the bound (not the command's length).
    _t0=$SECONDS
    nl_run_bounded 2 sleep 30; _rc=$?
    _el=$(( SECONDS - _t0 ))
    if [ "$_rc" = "124" ]; then _p "T3a overrun-returns-124 [$_M]"; else _f "T3a overrun-returns-124 [$_M]" "got rc=$_rc"; fi
    if [ "$_el" -ge 1 ] && [ "$_el" -le 6 ]; then _p "T3b overrun-returns-in-~2s (${_el}s) [$_M]"; else _f "T3b overrun-returns-in-~2s [$_M]" "elapsed ${_el}s, expected ~2s"; fi

    # T4 — the killed tree leaves nothing running. A GRANDCHILD sleep is
    # started (child = sh, grandchild = sleep); after the bound expires BOTH
    # must be gone from the process table. This is the "reap what you
    # initiate" law, and the reason the fallback tree-kills rather than
    # killing one pid: killing only the direct child would orphan the
    # grandchild AND leave it holding the caller's command-substitution pipe
    # open, converting the bound into a permanent hang.
    #
    # The marker is a unique sleep DURATION (not a name) so it cannot collide
    # with an unrelated `sleep` on this machine, and the ps scan uses a
    # bracketed pattern so `grep` does not match ITS OWN command line — an
    # un-bracketed pattern counts the grep itself and this assertion can then
    # never reach 0 no matter how correct the implementation is.
    _MARK_SECS=$(( 4000 + ( $$ % 900 ) ))
    nl_run_bounded 2 sh -c "sleep $_MARK_SECS & sleep $_MARK_SECS" >/dev/null 2>&1
    sleep 1
    _left="$(ps -A -o pid=,command= 2>/dev/null | grep -c "[s]leep ${_MARK_SECS}" || true)"
    _left="$(printf '%s' "$_left" | tr -d ' ')"
    case "$_left" in ''|*[!0-9]*) _left=0 ;; esac
    if [ "$_left" -eq 0 ]; then _p "T4 tree-killed-no-orphans [$_M]"; else _f "T4 tree-killed-no-orphans [$_M]" "$_left 'sleep ${_MARK_SECS}' process(es) survived the bound"; fi

    # T5 — a bound expressed as "20s" (the shape several callsites already
    # used) is normalized, not silently turned into an unbounded run.
    _t0=$SECONDS
    nl_run_bounded "2s" sleep 30; _rc=$?
    _el=$(( SECONDS - _t0 ))
    if [ "$_rc" = "124" ] && [ "$_el" -le 6 ]; then _p "T5 Ns-suffix-normalized [$_M]"; else _f "T5 Ns-suffix-normalized [$_M]" "rc=$_rc elapsed=${_el}s"; fi

    # T6 — a malformed bound must normalize to a REAL bound and still RUN the
    # command. It must never (a) become unbounded, or (b) abort without
    # running anything. "0" is the interesting case: clamped to the 1s floor,
    # so it must still kill an overrunning command rather than divide-by-zero
    # its way into running forever.
    nl_run_bounded "" sh -c 'exit 7'; _rc=$?
    if [ "$_rc" = "7" ]; then _p "T6a garbage-bound-still-runs-the-command [$_M]"; else _f "T6a garbage-bound-still-runs-the-command [$_M]" "expected 7, got $_rc"; fi
    _t0=$SECONDS
    nl_run_bounded "0" sleep 30; _rc=$?
    _el=$(( SECONDS - _t0 ))
    if [ "$_rc" = "124" ] && [ "$_el" -le 5 ]; then _p "T6b zero-bound-clamped-to-floor-still-bounds (${_el}s) [$_M]"; else _f "T6b zero-bound-clamped-to-floor [$_M]" "rc=$_rc elapsed=${_el}s — a 0/negative bound must clamp, never run unbounded"; fi
  done

  # T7 — no-command is a caller error (rc 2), never a silent success.
  nl_run_bounded 5; _rc=$?
  if [ "$_rc" = "2" ]; then _p "T7 no-command-rc2"; else _f "T7 no-command-rc2" "got $_rc"; fi

  # T8 — mode reporting is honest.
  NL_PORTABLE_TIMEOUT_FORCE_POLL=1; export NL_PORTABLE_TIMEOUT_FORCE_POLL; _NL_RB_MODE=""
  if [ "$(nl_run_bounded_mode)" = "poll" ]; then _p "T8a mode-reports-poll-when-forced"; else _f "T8a mode-reports-poll-when-forced" "got $(nl_run_bounded_mode)"; fi
  NL_PORTABLE_TIMEOUT_FORCE_POLL=0; export NL_PORTABLE_TIMEOUT_FORCE_POLL; _NL_RB_MODE=""
  if command -v timeout >/dev/null 2>&1; then
    if [ "$(nl_run_bounded_mode)" = "timeout" ]; then _p "T8b mode-reports-timeout-when-present"; else _f "T8b mode-reports-timeout-when-present" "got $(nl_run_bounded_mode)"; fi
  else
    if [ "$(nl_run_bounded_mode)" = "poll" ]; then _p "T8b mode-reports-poll-when-timeout-absent"; else _f "T8b mode-reports-poll-when-timeout-absent" "got $(nl_run_bounded_mode)"; fi
  fi

  printf '\nself-test summary: %s passed, %s failed\n' "$PASSED" "$FAILED" >&2
  [ "$FAILED" -eq 0 ] || exit 1
  exit 0
fi
