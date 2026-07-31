# portable-time.sh — the ONE portable date/time helper for this harness
# (macos-portability-2026-07 task M4).
#
# ============================================================
# WHY THIS LIB EXISTS
# ============================================================
#
# The harness was authored on Windows (Git-bash + GNU coreutils). GNU
# `date -d '<string>'` does not exist on BSD/macOS, which spells the same
# operation `date -j -f '<informat>' '<string>'` (absolute) or
# `date -v-<n><unit>` (relative). A bare `date -d` on stock macOS prints
# `date: illegal option -- d` and exits 1.
#
# That would be a loud, easily-fixed bug if the callsites surfaced it.
# They did not: the shape found across this repo was
#
#     touch -d '2 hours ago' "$f" 2>/dev/null \
#       || touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$f" \
#       || true
#
# where the BSD *fallback* is itself GNU-only, so on macOS BOTH halves
# fail, `|| true` swallows it, and the file is never aged. Seven gate
# self-tests then asserted the OPPOSITE of the scenario they named (a
# "stale waiver must be rejected" test silently ran with a FRESH waiver
# and reported PASS/FAIL for the wrong reason). MEASURED before this lib
# landed: 15 of 19 `date -d`-carrying self-test suites failed on stock
# macOS, vs 3 of 19 with the GNU toolchain on PATH.
#
# The lesson encoded here: a portability fallback that is never exercised
# on the platform it exists for is not a fallback, it is decoration.
#
# ============================================================
# DESIGN RULES (all three are load-bearing)
# ============================================================
#
# 1. PREFER ELIMINATION over dual-syntax. Most `date -d` callsites in this
#    repo converted a timestamp to epoch only to compare an age — and the
#    file's own MTIME is the same fact for one `stat` instead of a `date`
#    fork (see admission-lib.sh's adm_live_sessions for the precedent, and
#    concurrent-ownership-gate.sh, which M4 converted to `find -mmin` and
#    thereby REMOVED a fork from a PreToolUse path). Reach for this lib
#    only when a real timestamp parse is genuinely unavoidable.
#
# 2. ONE helper, not a dual-syntax branch per callsite. Branching inline
#    doubles the fork cost everywhere and guarantees the two halves drift.
#
# 3. A FAILED PARSE IS AN EXPLICIT UNKNOWN — never 0, never "now".
#    Every function here prints NOTHING and returns non-zero when it
#    cannot do the job. This is deliberate and is the whole point: a
#    silently-zero timestamp reads as "1970, infinitely stale" to a
#    `>` comparison and as "just now" to a `<` one, so a swallowed
#    failure does not degrade a staleness check, it INVERTS it in a
#    direction the caller cannot see. Callers must test the return code.
#
# ============================================================
# PLATFORM FACTS (each verified on this machine, 2026-07-29)
# ============================================================
#
#   GNU date -d "@<epoch>" +FMT   -> ok      | BSD: `illegal option -- d`
#   BSD date -r <epoch>    +FMT   -> ok      | GNU: `-r` means FILE, so
#                                              `date -r 1785330527` fails
#                                              with "No such file or
#                                              directory" -> safe to chain
#   Both spellings emit byte-identical output for the same instant, so
#   ordering GNU-first then BSD is a total function on either platform.
#   BSD touch -d '2 hours ago'    -> fails (BSD -d wants ISO-8601)
#   BSD touch -t YYYYMMDDhhmm.SS  -> ok  (and GNU touch accepts -t too,
#                                         so -t alone is fully portable)
#   BSD find -mmin / -newermt     -> BOTH supported (verified), so only
#                                    the cutoff STRING ever needed `date`.
#
# ============================================================
# API
# ============================================================
#
#   nl_now_epoch                 -> seconds since epoch (fork-free when
#                                   $EPOCHSECONDS exists, bash 5+)
#   nl_epoch_fmt <epoch> <fmt>   -> strftime-format an epoch
#   nl_epoch_to_touch_ts <epoch> -> "YYYYMMDDhhmm.SS" for `touch -t`
#   nl_ago_fmt <secs> <fmt>      -> strftime-format now-minus-<secs>
#                                   (replaces GNU-only `date -d '-N min'`)
#   nl_touch_age <file> <secs>   -> set <file> mtime to now-<secs>
#   nl_iso_to_epoch <iso-ts>     -> epoch for an ISO-8601 UTC timestamp
#
# All of them print nothing and return 1 on failure.
# ------------------------------------------------------------

# Guard against double-sourcing (several hooks source sibling libs that
# may in turn source this one).
if [ -z "${_NL_PORTABLE_TIME_LOADED:-}" ]; then
_NL_PORTABLE_TIME_LOADED=1

# nl_now_epoch — current time in seconds. $EPOCHSECONDS is a bash 5.0+
# builtin (no fork); bash 3.2.57, which is macOS's /bin/bash and this
# harness's floor, does not have it, so fall back to one `date +%s`
# (that spelling is POSIX and identical on both platforms).
nl_now_epoch() {
  if [ -n "${EPOCHSECONDS:-}" ]; then printf '%s' "$EPOCHSECONDS"; return 0; fi
  local t
  t="$(date +%s 2>/dev/null)" || return 1
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}

# nl_epoch_fmt <epoch> <strftime-fmt> — render an epoch in an arbitrary
# strftime format. GNU spelling first, BSD second; each fails cleanly on
# the other platform (see PLATFORM FACTS above), so the pair is a total
# function on either. <strftime-fmt> is given WITHOUT the leading '+'.
nl_epoch_fmt() {
  local e="$1" fmt="$2"
  [ -n "$e" ] || return 1
  [ -n "$fmt" ] || return 1
  date -d "@$e" "+$fmt" 2>/dev/null && return 0
  date -r "$e"  "+$fmt" 2>/dev/null && return 0
  return 1
}

# nl_epoch_to_touch_ts <epoch> — render an epoch as `touch -t`'s
# [[CC]YY]MMDDhhmm[.SS] format.
nl_epoch_to_touch_ts() {
  nl_epoch_fmt "$1" '%Y%m%d%H%M.%S'
}

# nl_ago_fmt <seconds_ago> <strftime-fmt> — render "now minus N seconds"
# in an arbitrary strftime format. This is the portable replacement for
# GNU-only `date -d '-N minutes' +FMT`, which several self-test fixtures
# used to build relative timestamps.
nl_ago_fmt() {
  local secs="$1" fmt="$2" now
  case "$secs" in ''|*[!0-9]*) return 1 ;; esac
  now="$(nl_now_epoch)" || return 1
  nl_epoch_fmt $(( now - secs )) "$fmt"
}

# nl_touch_age <file> <seconds_ago> — make <file> look <seconds_ago>
# seconds old. Returns non-zero if the file could not be aged.
#
# DO NOT append `|| true` at the callsite. Swallowing this failure is the
# exact defect this lib was written to kill: an un-aged fixture makes a
# staleness self-test assert the opposite of its own name while still
# printing a verdict.
nl_touch_age() {
  local f="$1" secs="$2" now target ts
  [ -n "$f" ] || return 1
  [ -e "$f" ] || return 1
  case "$secs" in ''|*[!0-9]*) return 1 ;; esac
  now="$(nl_now_epoch)" || return 1
  target=$(( now - secs ))
  ts="$(nl_epoch_to_touch_ts "$target")" || return 1
  [ -n "$ts" ] || return 1
  # `touch -t` is accepted by both GNU and BSD touch, so one spelling
  # covers both platforms — no second branch needed here.
  touch -t "$ts" "$f" 2>/dev/null || return 1
  return 0
}

# nl_iso_to_epoch <iso-ts> — seconds since epoch for an ISO-8601 UTC
# timestamp ("2026-07-29T06:08:47Z"). Prints nothing and returns 1 when
# the string cannot be parsed.
#
# NOTE the contrast with this repo's older `_hb_epoch` / `_od_epoch` /
# `_ny_epoch` (session-heartbeat-lib.sh, observability-derive.sh,
# needs-you.sh): those echo 0 on failure. That is safe THERE only because
# each of their callers documents 0 as "unparseable -> treat as stale"
# and handles it. This function refuses to make that choice on the
# caller's behalf (design rule 3).
nl_iso_to_epoch() {
  local ts="$1"
  [ -n "$ts" ] || return 1
  date -u -d "$ts" '+%s' 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null && return 0
  # Tolerate a trailing fractional part or a space separator, which some
  # producers in this repo emit ("2026-07-29 06:08:47").
  date -u -j -f '%Y-%m-%d %H:%M:%S' "$ts" '+%s' 2>/dev/null && return 0
  return 1
}

fi  # _NL_PORTABLE_TIME_LOADED

# --------------------------------------------------------------------
# Self-test. Runs on whichever interpreter invoked it, against whichever
# `date` is first on PATH — so running it under both bash 3.2/5.x and
# both toolchains is the portability oracle.
#
# The `BASH_SOURCE[0] = $0` guard is load-bearing, not boilerplate: every
# consumer of this lib sources it from INSIDE its own `--self-test`
# branch, where $1 is still "--self-test". Without the guard this block
# would run — and `exit 0` — in the CALLER's shell, ending the caller's
# suite after 6 passing assertions that belong to a different file.
# (Observed exactly that against wire-check-gate.sh while building M4.)
# --------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  _pt_pass=0; _pt_fail=0
  _pt_ok()   { _pt_pass=$((_pt_pass+1)); echo "  PASS: $1"; }
  _pt_bad()  { _pt_fail=$((_pt_fail+1)); echo "  FAIL: $1" >&2; }

  echo "portable-time self-test (bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}, date=$(command -v date))"

  # T1 nl_now_epoch returns a plausible epoch
  _t1="$(nl_now_epoch)"
  case "$_t1" in
    ''|*[!0-9]*) _pt_bad "T1 nl_now_epoch non-numeric ('$_t1')" ;;
    *) if [ "$_t1" -gt 1700000000 ]; then _pt_ok "T1 nl_now_epoch=$_t1"
       else _pt_bad "T1 nl_now_epoch implausible ($_t1)"; fi ;;
  esac

  # T2 epoch -> touch ts round-trips through `touch -t` to the SAME epoch
  _pt_tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ptime)"
  : > "$_pt_tmp/f"
  _t2_target=$(( _t1 - 7200 ))
  if _t2_ts="$(nl_epoch_to_touch_ts "$_t2_target")"; then
    _pt_ok "T2 nl_epoch_to_touch_ts -> $_t2_ts"
  else
    _pt_bad "T2 nl_epoch_to_touch_ts failed on both spellings"
  fi

  # T3 nl_touch_age actually moves mtime — the assertion the old
  # `|| true` callsites never made. Read mtime back portably.
  _pt_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
  if nl_touch_age "$_pt_tmp/f" 7200; then
    _t3_mt="$(_pt_mtime "$_pt_tmp/f")"
    _t3_age=$(( _t1 - _t3_mt ))
    # allow a couple of seconds of clock drift across the calls
    if [ "$_t3_age" -ge 7195 ] && [ "$_t3_age" -le 7205 ]; then
      _pt_ok "T3 nl_touch_age aged the file by ${_t3_age}s (wanted 7200)"
    else
      _pt_bad "T3 nl_touch_age produced age ${_t3_age}s, wanted ~7200"
    fi
  else
    _pt_bad "T3 nl_touch_age returned non-zero"
  fi

  # T4 nl_touch_age refuses a missing file rather than reporting success
  if nl_touch_age "$_pt_tmp/nope" 60 2>/dev/null; then
    _pt_bad "T4 nl_touch_age claimed success on a missing file"
  else
    _pt_ok "T4 nl_touch_age fails loudly on a missing file"
  fi

  # T5 nl_iso_to_epoch parses a REAL producer's timestamp shape and
  # round-trips: epoch -> ISO -> epoch must be identity.
  _t5_iso="$(date -u -r "$_t2_target" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
             || date -u -d "@$_t2_target" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  if [ -n "$_t5_iso" ] && _t5_back="$(nl_iso_to_epoch "$_t5_iso")" \
     && [ "$_t5_back" = "$_t2_target" ]; then
    _pt_ok "T5 nl_iso_to_epoch round-trip $_t5_iso -> $_t5_back"
  else
    _pt_bad "T5 nl_iso_to_epoch round-trip failed (iso='$_t5_iso' back='${_t5_back:-}' want=$_t2_target)"
  fi

  # T6 a garbage timestamp is an EXPLICIT unknown (rule 3) — must print
  # nothing and return non-zero, NOT echo 0.
  if _t6="$(nl_iso_to_epoch 'not-a-timestamp' 2>/dev/null)"; then
    _pt_bad "T6 nl_iso_to_epoch accepted garbage (printed '$_t6')"
  elif [ -n "$_t6" ]; then
    _pt_bad "T6 nl_iso_to_epoch printed '$_t6' on failure; must print nothing"
  else
    _pt_ok "T6 garbage timestamp -> explicit unknown (empty, rc!=0)"
  fi

  rm -rf "$_pt_tmp" 2>/dev/null
  echo "portable-time self-test summary: $_pt_pass passed, $_pt_fail failed"
  [ "$_pt_fail" -eq 0 ] || exit 1
  exit 0
fi
