#!/bin/bash
# bench-admission-hotpath.sh — measure adm_admit cost per dispatch,
# occupancy TTL cache OFF vs ON.
#
# WHY THIS EXISTS
# ===============
# T6 of docs/plans/accountable-estate-program-2026-07.md gates the admission
# enforcement flip on "hot path under 5 ms/dispatch". admission-lib.sh's own
# header carries measured baselines (19.0 ms snapshot-absent / 70.8 ms
# snapshot-present) that a reviewer must be able to REPRODUCE rather than
# take on faith — this repo's dominant defect class is a claim that
# measurement contradicts. This script is that reproduction.
#
# METHOD (identical shape to the one that produced the header's figures):
# source the lib, call adm_admit N times against a REAL janitor snapshot,
# divide wall-clock by N. The BEFORE case sets ADM_OCC_CACHE_TTL_SECS=0,
# which the lib documents as "disables caching entirely" — i.e. exactly the
# pre-cache code path, measured on the same machine in the same minute as
# the AFTER case, so the two numbers are comparable.
#
# SANDBOXING: HARNESS_SELFTEST=1 + ADM_STATE_DIR point every write at a temp
# dir, so the real would-block ledger (the T6 calibration data) is never
# polluted by a benchmark run. That flag is also what re-opens
# ADM_ESTATE_SNAPSHOT, closed in production by T6-prereq (b) — the
# legitimate test seam, not a reopened bypass.
#
# USAGE
#   bash adapters/claude-code/tests/bench-admission-hotpath.sh [N]
#   N defaults to 20.
#
# The per-dispatch figure is wall-clock and therefore load-sensitive: on a
# saturated box it reads high for BOTH cases. Read the RATIO and the
# absolute AFTER number together, and re-run on an idle machine before
# treating a near-budget result as a pass.
set -u

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${ADMISSION_LIB:-$_here/../hooks/lib/admission-lib.sh}"
N="${1:-20}"
SNAP="${BENCH_SNAPSHOT:-$HOME/.claude/state/estate/snapshot.json}"

[[ -r "$LIB" ]] || { echo "FATAL: admission-lib not readable at $LIB" >&2; exit 1; }
if [[ ! -r "$SNAP" ]]; then
  echo "FATAL: no real janitor snapshot at $SNAP" >&2
  echo "  The snapshot-PRESENT path is the one T6 budgets; benching without" >&2
  echo "  one measures the trivial early-return and proves nothing." >&2
  exit 1
fi

_size() { stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null || echo 0; }
_now_ms() {
  local t; t="$(date +%s%3N 2>/dev/null)"
  [[ "$t" =~ ^[0-9]+$ ]] || t=$(( $(date +%s) * 1000 ))
  printf '%s' "$t"
}

echo "admission-lib : $LIB"
echo "snapshot      : $SNAP ($(_size "$SNAP") bytes)"
echo "iterations    : $N"
echo

run_case() {
  local label="$1" ttl="$2" snap="${3:-$SNAP}"
  local sb; sb="$(mktemp -d 2>/dev/null || mktemp -d -t benchadm)"
  (
    export HARNESS_SELFTEST=1
    export ADM_STATE_DIR="$sb"
    export ADM_ESTATE_SNAPSHOT="$snap"
    export ADM_OCC_CACHE_TTL_SECS="$ttl"
    # shellcheck disable=SC1090
    source "$LIB" || { echo "FATAL: could not source $LIB" >&2; exit 1; }
    local t0 t1 i
    t0="$(_now_ms)"
    for (( i = 0; i < N; i++ )); do
      adm_admit selftest >/dev/null 2>&1
    done
    t1="$(_now_ms)"
    local total=$(( t1 - t0 ))
    printf '%-32s total=%6d ms   per-dispatch=%d.%d ms\n' \
      "$label" "$total" "$(( total / N ))" "$(( (total * 10 / N) % 10 ))"
  )
  rm -rf "$sb" 2>/dev/null || true
}

run_case "BEFORE (TTL cache OFF, ttl=0)"  0
run_case "AFTER  (TTL cache ON,  ttl=45)" 45

# FORK FLOOR — the load-bearing third number, and the reason a TTL cache alone
# cannot satisfy T6. Pointing the snapshot at a nonexistent path makes
# adm_live_sessions return -1 on its very first line, before any file read or
# string scan. Whatever remains is everything adm_admit does OTHER than read
# occupancy: ~45 command substitutions, each a real process on this platform.
# The TTL cache can only ever recover (BEFORE - FLOOR). If FLOOR alone exceeds
# 5 ms, no cache reaches the budget and the remaining work is fork collapse —
# exactly the retirement condition admission-lib.sh's own header names:
# "collapse the $(...)-per-helper style into direct assignment".
run_case "FLOOR  (snapshot ABSENT, no read)" 45 "/nonexistent/no-such-snapshot.json"

echo
echo "T6 budget: < 5 ms/dispatch before the enforcement flip."
echo "Read: (BEFORE - FLOOR) is the snapshot-read cost the cache removes."
echo "      FLOOR is the irreducible cost of adm_admit's own command"
echo "      substitutions — untouched by any occupancy cache."
