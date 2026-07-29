#!/bin/bash
# admission-lib.sh — estate admission control, OBSERVE MODE ONLY (T3).
#
# ============================================================================
# WHAT THIS IS
# ============================================================================
# The resource authority for the Accountable Estate program
# (docs/plans/accountable-estate-program-2026-07.md, task T3). It answers one
# question at every dispatch point: "under current estate pressure, WOULD this
# dispatch have been blocked?" — and writes the answer to a would-block ledger.
#
# IN THIS SLICE IT NEVER BLOCKS ANYTHING. `adm_admit` returns 0 on every path,
# including HALT, drain, and BLACK pressure. The deliverable is the ledger, not
# the enforcement. That is not a shortcut; it is binding program rule 4
# (observe-first before every enforcement flip) and architecture-review F1:
#
#   "P0's proposed caps (4/min, burst 6, cap 5) are contradicted by measured
#    LEGITIMATE load: the protected downstream-product orchestrator sustains
#    15-21 dispatches/min; 5 of the last 10 days ran 1,200-1,400 dispatches/day
#    (storms are CHRONIC, not a one-off). As written, the governor throttles the
#    operator's most-valued work on night one and gets disabled in frustration."
#    -- docs/reviews/2026-07-27-accountable-estate-architecture-review.md F1
#
# The enforcement flip is T6, GATED on >=7 calendar days of this ledger plus
# operator sign-off on thresholds. Do not add a blocking path here without it.
#
# ============================================================================
# WHY A SOURCED LIB AND NOT A GATE (review F2 — CRITICAL, PROVEN)
# ============================================================================
# A PreToolUse gate does not cover all dispatchers. session-resumer.sh spawns
# `claude -p --resume` from a scheduled task with ZERO hooks; Decision-011
# cloud/scheduled sessions have no PreToolUse at all. A client-side gate as the
# guarantee recreates the decision-064 failure class (client gate != every
# writer). So: admission is ONE lib, sourced by every dispatch path. The gate
# is a convenience surface, never the guarantee.
#
# Callsites wired in this slice (all three named by the T3 task text):
#   1. hooks/workstreams-emit.sh  --on-builder-dispatch   (emit-feed
#      registration; PreToolUse Task|Agent|Workflow — the dispatch-gate surface)
#   2. scripts/session-resumer.sh  at the storm-cap commit point (the hookless
#      scheduled dispatcher — the F2 coverage gap this design exists for)
#   3. scripts/spawn-worktree.sh   (worktree builder dispatch)
#
# HONEST COVERAGE STATEMENT (the review's verdict-change condition is
# "NEEDS-RESHAPING if a coverage audit finds a substantial dispatch path
# emitting nothing into the ledger" — so this list is the audit, kept current):
#   COVERED : Task/Agent/Workflow tool dispatch; session-resumer resume and
#             fresh-spawn flavors; spawn-worktree builder dispatch.
#   NOT YET : Decision-011 cloud/scheduled sessions (no hooks, and they do not
#             source this lib — they run on a different machine image); a human
#             typing `claude` directly; MCP-side agent spawns. These emit
#             nothing into the ledger and MUST be treated as unmeasured load
#             when reading calibration data. Closing the cloud path is T14.
#
# ============================================================================
# CONTRACTS
# ============================================================================
# FAIL-OPEN, ABSOLUTELY. Every internal error path admits. A broken, unwritable,
# or garbled ledger must never prevent a dispatch. This is enforced by
# `adm_admit` returning 0 unconditionally in observe mode, and by every helper
# defaulting to the permissive answer when its input is missing.
#
# SPAWN-FREE HOT PATH (design 6b edge 6: "dispatch-time access must be
# spawn-free bash builtins or the fix becomes its own overhead"). The admit path
# uses builtins only: `read`, glob expansion, `[[`, printf, and $EPOCHSECONDS.
# It forks at most ONCE, and only on bash < 5.0, for a `date +%s` fallback.
# It NEVER calls hb_classify (measured expensive — see backlog
# ESTATE-T1-HB-CLASSIFY-PERF-01, 12m38s for a full janitor pass); slot occupancy
# is read from the janitor's already-computed snapshot instead. That is the
# governor design's rule: "the gate reads the cached pressure snapshot ... the
# gate never measures anything itself — one file read, ~0 ms".
#
# DERIVED, NEVER DECLARED (review F4 / THE ONE THING). Nothing here trusts a
# caller-supplied claim about capacity. Occupancy comes from the janitor
# snapshot's own hb_classify output; rate comes from stamp files this lib wrote;
# pressure comes from the tick's file. The caller supplies only labels for
# attribution (who dispatched, which repo) — never the numbers that decide.
#
# ============================================================================
# API
# ============================================================================
#   adm_admit <source> [key=value ...]
#     The one call every dispatcher makes. <source> is a short enum naming the
#     dispatch path: emit-feed | resumer | worktree | selftest | other.
#     Optional key=value pairs are attribution labels (see SCRUB below).
#     ALWAYS returns 0 in observe mode. Appends exactly one ledger line.
#     Echoes the verdict it WOULD have returned: admit | would-block:<reason>
#
#   adm_verdict                 -> last verdict string, no side effects
#   adm_pressure_color          -> green|yellow|red|black|unknown
#   adm_halt_active             -> rc 0 if the HALT kill switch is present
#   adm_drain_active            -> rc 0 if the drain flag is present
#   adm_ledger_path             -> absolute path of this machine's ledger file
#   adm_ledger_rotate           -> size-bounded rotation (called by the janitor)
#
# STATE (all overridable for tests; hostname-scoped per review F10 so there is
# exactly ONE writer per file and cross-machine merge is append-only):
#   ADM_STATE_DIR      default $HOME/.claude/state/governor
#     HALT             kill switch      (one `touch` stops the estate — T6)
#     DRAIN            drain flag       (deny-new at safe boundaries — T4/T6)
#     pressure.json    written by the Loop-2 pressure tick (NOT BUILT YET —
#                      absent means pressure=unknown, which admits; see below)
#     rate/            stamp file per dispatch (review F9: never a
#                      read-modify-write token bucket — those lose updates)
#     ledger/<host>.jsonl   the would-block ledger, O_APPEND, one writer
#   ADM_ESTATE_SNAPSHOT default $HOME/.claude/state/estate/snapshot.json
#                      T1's janitor output; source of slot occupancy.
#
# WHAT IS HONESTLY NOT BUILT HERE: the Loop-2 pressure tick that writes
# pressure.json is NOT part of T3. Until it exists, adm_pressure_color returns
# "unknown" and the pressure rung of the ladder never fires. The ledger records
# pressure_src=absent on those lines so calibration cannot mistake "we never saw
# pressure" for "pressure was fine". Do not read a 7-day window as
# pressure-calibrated until that file starts appearing.
#
# SCRUB-AT-WRITE (design 6b edge 4 — occurred 2x this week). This lib is
# machine-wide and its ledger is committed for cross-machine visibility, so it
# must never carry product names, absolute user paths, or command lines. Only
# enum'd/whitelisted label keys are written, values are truncated and stripped
# of path separators and anything outside [A-Za-z0-9._-]. Raw cmdlines, window
# titles, and prompt text are NEVER accepted. See _adm_scrub.
#
# CLOCK (design 6b edge 5): every line carries wall time AND a monotonic-ish
# counter with an explicit source label, because hostname-scoped files fix
# concurrent writes but not cross-machine ORDERING.
#
# CALIBRATION POLLUTION (design 6b edge 3): the baseline is being recorded
# DURING the chronic-storm period. Traffic from the protected downstream-product
# orchestrator must be tagged so "normal" is not learned from pathology. Set
# NL_PROTECTED_ORCHESTRATOR=1 in that orchestrator's environment; every line it
# produces carries protected=1. Untagged traffic is assumed unprotected.
#
# Self-test: bash admission-lib.sh --self-test
# ============================================================================

# ---------------------------------------------------------------------------
# Paths and small helpers (no side effects at source time except defaults)
# ---------------------------------------------------------------------------

# SELF-TEST POLLUTION GUARD (found by this lib's own Scenario 16, 2026-07-28).
# This lib is spliced into workstreams-emit.sh, session-resumer.sh and
# spawn-worktree.sh. Each of those has its OWN --self-test, and those suites
# drive the spliced dispatch paths for real — so without this guard, running any
# HOST script's self-test silently appends dozens of junk lines to the
# OPERATOR'S REAL would-block ledger, poisoning the exact 7-day calibration
# window T3 exists to produce. That is not hypothetical: it happened on the
# first full run here, and Scenario 16 caught it.
#
# The repo already learned this lesson once per-caller (see the
# PERF_LEDGER_DIR export in pr-template-inline-gate.sh's self-test). Doing it
# per-caller relies on every future caller remembering. So the defense lives
# HERE: under HARNESS_SELFTEST=1 with no explicit ADM_STATE_DIR, the lib
# redirects to a throwaway per-process dir instead of real state. An explicit
# ADM_STATE_DIR always wins, so this lib's own self-test still controls its
# sandbox precisely.
adm_state_dir() {
  if [[ -n "${ADM_STATE_DIR:-}" ]]; then printf '%s' "$ADM_STATE_DIR"; return 0; fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s' "${TMPDIR:-/tmp}/adm-selftest-$$"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/governor"
}
adm_ledger_dir() { printf '%s' "$(adm_state_dir)/ledger"; }
adm_rate_dir()   { printf '%s' "$(adm_state_dir)/rate"; }

# Hostname without a fork where possible. $HOSTNAME is set by bash itself.
_adm_host() {
  local h="${ADM_HOST_OVERRIDE:-${HOSTNAME:-}}"
  if [[ -z "$h" ]]; then h="$(uname -n 2>/dev/null)" || h="unknown"; fi
  # scrub: hostnames land in filenames and in the committed snapshot
  h="${h%%.*}"
  h="${h//[^A-Za-z0-9._-]/_}"
  printf '%s' "${h:-unknown}"
}

adm_ledger_path() { printf '%s/%s.jsonl' "$(adm_ledger_dir)" "$(_adm_host)"; }

# Wall clock, seconds since epoch. Builtin on bash >= 5.0; one fork below that.
_adm_now() {
  if [[ -n "${EPOCHSECONDS:-}" ]]; then printf '%s' "$EPOCHSECONDS"; return 0; fi
  local t; t="$(date +%s 2>/dev/null)" || t=0
  printf '%s' "$t"
}

# ISO-8601 UTC. Only called on the LEDGER-WRITE path, never on a hot decision
# path, so one fork here is acceptable; bash has no builtin UTC formatter
# before 4.2 and printf %(%s)T is not portable to the MSYS builds in this estate.
_adm_iso() {
  local t; t="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || t=""
  printf '%s' "$t"
}

# Monotonic-ish counter with an HONEST source label (edge 5). Linux/MSYS expose
# /proc/uptime; macOS does not, and there is no portable builtin, so we fall
# back to wall time and SAY SO in the line rather than pretending.
_adm_mono() {
  local up
  if [[ -r /proc/uptime ]] && read -r up _ < /proc/uptime 2>/dev/null; then
    printf '%s uptime' "${up%%.*}"
    return 0
  fi
  printf '%s wall' "$(_adm_now)"
}

# _adm_scrub <value> — whitelist-only sanitizer for label VALUES (edge 4).
# Strips path separators and anything outside a conservative charset, then
# truncates. A value that scrubs to empty is dropped by the caller.
_adm_scrub() {
  local v="$1"
  v="${v//[^A-Za-z0-9._-]/}"
  printf '%s' "${v:0:48}"
}

# Label KEYS are a closed enum. An unknown key is dropped, not written — this is
# what stops a future caller from quietly piping a prompt or cmdline in here.
_adm_key_allowed() {
  case "$1" in
    repo|agent|kind|reason_hint|plan|task|session) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Kill switch + drain flag
# ---------------------------------------------------------------------------
# Both are one-gesture operator controls: `touch`/`rm`. Precedent:
# resumer-armed.txt. In OBSERVE MODE both only produce a would-block record.

adm_halt_active()  { [[ -e "$(adm_state_dir)/HALT" ]]; }
adm_drain_active() { [[ -e "$(adm_state_dir)/DRAIN" ]]; }

# ---------------------------------------------------------------------------
# Pressure (read the cached snapshot; never measure)
# ---------------------------------------------------------------------------
# Loop 2 (the pressure tick) is NOT built in T3. Absent file => "unknown", which
# admits and is recorded as pressure_src=absent. We parse with the `read`
# builtin over a tiny flat JSON rather than jq: jq is a fork per dispatch, and
# edge 6 forbids that on the hot path.

adm_pressure_color() {
  local f="${ADM_PRESSURE_FILE:-$(adm_state_dir)/pressure.json}"
  [[ -r "$f" ]] || { printf 'unknown'; return 0; }
  local line color=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      *'"color"'*)
        color="${line#*\"color\"}"; color="${color#*:}"
        color="${color//[^A-Za-z]/}"
        break ;;
    esac
  done < "$f"
  case "$color" in
    green|yellow|red|black) printf '%s' "$color" ;;
    *) printf 'unknown' ;;
  esac
}

# ---------------------------------------------------------------------------
# Slot occupancy — DERIVED from the janitor snapshot (F4/F8)
# ---------------------------------------------------------------------------
# F8: background builders never emit `done` (workstreams-emit contract), so slot
# liveness must derive from heartbeats via hb_classify — with TTL only as a
# final fallback. We do NOT run hb_classify here (see the perf note in the
# header); we read the count the janitor already computed with it. If the
# snapshot is missing or stale we return -1 = unknown, which admits.

adm_live_sessions() {
  local f="${ADM_ESTATE_SNAPSHOT:-$HOME/.claude/state/estate/snapshot.json}"
  [[ -r "$f" ]] || { printf '%s' -1; return 0; }
  local line n=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      *'"live_sessions"'*)
        n="${line#*\"live_sessions\"}"; n="${n#*:}"
        n="${n//[^0-9]/}"
        break ;;
    esac
  done < "$f"
  [[ -n "$n" ]] || n=-1
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# Rate — stamp file per dispatch (review F9)
# ---------------------------------------------------------------------------
# F9: "Token bucket as read-modify-write file loses updates -> stamp-file-per-
# dispatch, count files younger than window." Each dispatch drops one empty
# file named <epoch>.<pid>.<n>; the count is a glob + arithmetic, no forks, and
# concurrent writers cannot lose each other's updates.

_adm_rate_record() {
  local d; d="$(adm_rate_dir)"
  [[ -d "$d" ]] || mkdir -p "$d" 2>/dev/null || return 0
  local now; now="$(_adm_now)"
  : > "$d/$now.$$.${RANDOM:-0}" 2>/dev/null || true
  return 0
}

# adm_rate_in_window [window_secs] — count stamps younger than the window and
# opportunistically reap older ones (bounded: the reap is the same glob pass).
adm_rate_in_window() {
  local win="${1:-${ADM_RATE_WINDOW_SECS:-60}}"
  local d; d="$(adm_rate_dir)"
  [[ -d "$d" ]] || { printf '%s' 0; return 0; }
  local now; now="$(_adm_now)"
  local cutoff=$(( now - win ))
  local n=0 f base ts
  for f in "$d"/*; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    ts="${base%%.*}"
    [[ "$ts" =~ ^[0-9]+$ ]] || { rm -f "$f" 2>/dev/null; continue; }
    if (( ts >= cutoff )); then
      n=$(( n + 1 ))
    else
      # older than the window and older than the reap grace -> drop it, so the
      # directory stays bounded without a separate sweeper.
      if (( ts < cutoff - ${ADM_RATE_REAP_GRACE_SECS:-300} )); then
        rm -f "$f" 2>/dev/null
      fi
    fi
  done
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# The ladder — what WOULD have happened
# ---------------------------------------------------------------------------
# Order matters: operator gestures (HALT, DRAIN) outrank measured pressure,
# which outranks the absurd-level count backstop.
#
# Thresholds are deliberately NOT the governor doc's original numbers. Design
# 6b supersedes them: "Pressure-based admission, NOT count caps ... Count
# threshold survives only as an absurd-level backstop (~50), effectively never
# hit." F1 proves the old 4/min-cap framing throttles legitimate work that
# measured 15-21 dispatches/min. So the rate rung sits at a deliberately absurd
# 120/min and exists only to catch a runaway retry loop (the UNRESOLVED__ spam
# class named in F7), not to shape normal load.

_adm_decide() {
  if adm_halt_active; then printf 'would-block:halt'; return 0; fi
  if adm_drain_active; then printf 'would-block:drain'; return 0; fi

  local color; color="$(adm_pressure_color)"
  case "$color" in
    black) printf 'would-block:pressure-black'; return 0 ;;
    red)   printf 'would-block:pressure-red';   return 0 ;;
  esac

  local live; live="$(adm_live_sessions)"
  if [[ "$live" != "-1" ]] && (( live >= ${ADM_ABSURD_SESSION_CAP:-50} )); then
    printf 'would-block:session-backstop'; return 0
  fi

  local rate; rate="$(adm_rate_in_window)"
  if (( rate >= ${ADM_ABSURD_RATE_PER_MIN:-120} )); then
    printf 'would-block:rate-backstop'; return 0
  fi

  printf 'admit'
}

# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------
# Append-only JSONL, hostname-scoped (F10): one writer per file, O_APPEND (`>>`
# is O_APPEND in bash), so concurrent dispatchers on the same machine interleave
# whole lines without a lock. Cross-machine merge is union-of-lines.

_ADM_LAST_VERDICT=""
adm_verdict() { printf '%s' "$_ADM_LAST_VERDICT"; }

adm_ledger_rotate() {
  local f; f="$(adm_ledger_path)"
  [[ -f "$f" ]] || return 0
  local max="${ADM_LEDGER_MAX_BYTES:-5242880}"
  local size=0
  size="$(wc -c < "$f" 2>/dev/null)" || size=0
  size="${size//[^0-9]/}"
  [[ -n "$size" ]] || size=0
  if (( size > max )); then
    mv -f "$f" "$f.1" 2>/dev/null || return 0
  fi
  return 0
}

# ---------------------------------------------------------------------------
# adm_admit — THE call
# ---------------------------------------------------------------------------
# Returns 0 ALWAYS in observe mode. Echoes the verdict.
#
# Note the ordering: we record the rate stamp BEFORE deciding, so this dispatch
# counts toward its own window the way an enforcing implementation would see it.
# Calibration data that excluded the current dispatch would systematically
# under-count at exactly the moments that matter.

adm_admit() {
  local source="${1:-other}"; shift 2>/dev/null || true
  source="$(_adm_scrub "$source")"
  [[ -n "$source" ]] || source="other"

  _adm_rate_record

  local verdict; verdict="$(_adm_decide)"
  _ADM_LAST_VERDICT="$verdict"

  # --- assemble the line (labels are enum-keyed and scrubbed) ---
  local labels="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    [[ "$k" != "$kv" ]] || continue
    _adm_key_allowed "$k" || continue
    v="$(_adm_scrub "$v")"
    [[ -n "$v" ]] || continue
    labels="$labels,\"$k\":\"$v\""
  done

  local color live rate mono mono_src pressure_src
  color="$(adm_pressure_color)"
  live="$(adm_live_sessions)"
  rate="$(adm_rate_in_window)"
  read -r mono mono_src <<< "$(_adm_mono)"
  if [[ -r "${ADM_PRESSURE_FILE:-$(adm_state_dir)/pressure.json}" ]]; then
    pressure_src="tick"
  else
    pressure_src="absent"
  fi

  local d; d="$(adm_ledger_dir)"
  [[ -d "$d" ]] || mkdir -p "$d" 2>/dev/null || { printf '%s' "$verdict"; return 0; }
  adm_ledger_rotate

  local protected=0
  [[ "${NL_PROTECTED_ORCHESTRATOR:-0}" == "1" ]] && protected=1

  printf '{"wall":"%s","mono":"%s","mono_src":"%s","host":"%s","source":"%s","verdict":"%s","pressure":"%s","pressure_src":"%s","live_sessions":%s,"rate_1m":%s,"protected":%s,"mode":"observe"%s}\n' \
    "$(_adm_iso)" "$mono" "$mono_src" "$(_adm_host)" "$source" "$verdict" \
    "$color" "$pressure_src" "$live" "$rate" "$protected" "$labels" \
    >> "$(adm_ledger_path)" 2>/dev/null || true

  printf '%s' "$verdict"
  return 0   # OBSERVE MODE: never block. T6 flips this, gated on 7 days of data.
}

# ===========================================================================
# Self-test
# ===========================================================================
_adm_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp"; return 1; }
  export ADM_STATE_DIR="$T/governor"
  export ADM_ESTATE_SNAPSHOT="$T/snapshot.json"
  export ADM_PRESSURE_FILE="$T/governor/pressure.json"
  export ADM_HOST_OVERRIDE="testhost"
  unset NL_PROTECTED_ORCHESTRATOR
  mkdir -p "$ADM_STATE_DIR"

  local led; led="$(adm_ledger_path)"

  echo "Scenario 1: clean estate -> admit, one ledger line, rc 0"
  local v rc
  v="$(adm_admit emit-feed repo=neurallace)"; rc=$?
  [[ "$v" == "admit" ]] && pass "verdict admit" || fail "expected admit, got '$v'"
  [[ "$rc" == "0" ]] && pass "rc 0" || fail "expected rc 0, got $rc"
  [[ -f "$led" ]] && pass "ledger created at hostname-scoped path" || fail "no ledger at $led"
  [[ "$(wc -l < "$led" | tr -d ' ')" == "1" ]] && pass "exactly one line" || fail "line count wrong"

  echo "Scenario 2: HALT is observed but DOES NOT block (the core observe-mode claim)"
  : > "$ADM_STATE_DIR/HALT"
  v="$(adm_admit resumer)"; rc=$?
  [[ "$v" == "would-block:halt" ]] && pass "verdict would-block:halt" || fail "got '$v'"
  [[ "$rc" == "0" ]] && pass "STILL rc 0 under HALT — observe mode never blocks" || fail "HALT blocked (rc=$rc) — observe-mode violation"
  rm -f "$ADM_STATE_DIR/HALT"

  echo "Scenario 3: DRAIN observed, also non-blocking"
  : > "$ADM_STATE_DIR/DRAIN"
  v="$(adm_admit resumer)"; rc=$?
  [[ "$v" == "would-block:drain" ]] && pass "verdict would-block:drain" || fail "got '$v'"
  [[ "$rc" == "0" ]] && pass "rc 0 under DRAIN" || fail "DRAIN blocked"
  rm -f "$ADM_STATE_DIR/DRAIN"

  echo "Scenario 4: pressure ladder read from the cached file (never measured here)"
  printf '{"color":"red"}\n' > "$ADM_PRESSURE_FILE"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "would-block:pressure-red" ]] && pass "red -> would-block:pressure-red" || fail "got '$v'"
  printf '{"color":"black"}\n' > "$ADM_PRESSURE_FILE"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "would-block:pressure-black" ]] && pass "black -> would-block:pressure-black" || fail "got '$v'"
  printf '{"color":"green"}\n' > "$ADM_PRESSURE_FILE"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "green -> admit" || fail "got '$v'"

  echo "Scenario 5: absent pressure file is recorded as absent, and ADMITS (honesty)"
  rm -f "$ADM_PRESSURE_FILE"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "absent pressure -> admit (fail-open)" || fail "got '$v'"
  if grep -q '"pressure_src":"absent"' "$led"; then
    pass "line records pressure_src=absent so calibration cannot mistake it for 'pressure was fine'"
  else fail "pressure_src=absent not recorded"; fi
  if grep -q '"pressure":"unknown"' "$led"; then
    pass "pressure recorded as unknown, not defaulted to green"
  else fail "unknown pressure not recorded"; fi

  echo "Scenario 6: rate uses stamp-files-per-dispatch, not read-modify-write (F9)"
  local before after
  before="$(adm_rate_in_window)"
  adm_admit emit-feed >/dev/null
  adm_admit emit-feed >/dev/null
  after="$(adm_rate_in_window)"
  (( after == before + 2 )) && pass "two dispatches -> +2 stamps (no lost updates)" || fail "rate $before -> $after"
  local stamps; stamps=0
  local sf; for sf in "$(adm_rate_dir)"/*; do [[ -e "$sf" ]] && stamps=$((stamps+1)); done
  (( stamps >= 2 )) && pass "stamp files exist on disk ($stamps)" || fail "no stamp files"

  echo "Scenario 7: concurrent writers do not lose each other's ledger lines (O_APPEND)"
  local base; base="$(wc -l < "$led" | tr -d ' ')"
  local i
  for i in 1 2 3 4 5 6 7 8; do ( adm_admit emit-feed kind=concurrent >/dev/null ) & done
  wait
  local now_lines; now_lines="$(wc -l < "$led" | tr -d ' ')"
  (( now_lines == base + 8 )) && pass "8 concurrent appends -> 8 whole lines" || fail "expected $((base+8)) lines, got $now_lines"
  if grep -c '^{' "$led" | grep -q "^$now_lines$"; then
    pass "every line is a complete JSON object (no interleaved fragments)"
  else fail "torn lines detected"; fi

  echo "Scenario 8: SCRUB — disallowed keys dropped, values sanitized (edge 4)"
  adm_admit emit-feed cmdline=/Users/secret/ProductName repo=neural-lace >/dev/null
  local last; last="$(tail -1 "$led")"
  case "$last" in
    *cmdline*) fail "disallowed key 'cmdline' leaked into the ledger" ;;
    *) pass "disallowed key 'cmdline' dropped" ;;
  esac
  case "$last" in
    *ProductName*) fail "unscrubbed value leaked" ;;
    *) pass "value from a disallowed key never written" ;;
  esac
  adm_admit emit-feed repo="../../etc/passwd" >/dev/null
  last="$(tail -1 "$led")"
  case "$last" in
    */*) fail "path separators survived the scrub: $last" ;;
    *) pass "path separators stripped from label values" ;;
  esac

  echo "Scenario 9: absurd-level backstops (design 6b: NOT count caps for normal load)"
  printf '{"live_sessions": 3}\n' > "$ADM_ESTATE_SNAPSHOT"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "3 live sessions admits (legitimate load is 15-21/min per F1)" || fail "got '$v'"
  printf '{"live_sessions": 77}\n' > "$ADM_ESTATE_SNAPSHOT"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "would-block:session-backstop" ]] && pass "77 sessions trips the ~50 absurd backstop" || fail "got '$v'"
  rm -f "$ADM_ESTATE_SNAPSHOT"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "absent snapshot -> unknown occupancy -> admit (fail-open)" || fail "got '$v'"

  echo "Scenario 10: derived-not-declared (F4) — a caller cannot assert its way in or out"
  printf '{"live_sessions": 77}\n' > "$ADM_ESTATE_SNAPSHOT"
  v="$(adm_admit emit-feed live_sessions=1 verdict=admit rate_1m=0)"
  [[ "$v" == "would-block:session-backstop" ]] && pass "caller-declared live_sessions/verdict ignored; snapshot wins" || fail "caller overrode derived state: '$v'"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"live_sessions":77'*) pass "ledger records the DERIVED 77, not the declared 1" ;;
    *) fail "derived occupancy not recorded: $last" ;;
  esac
  rm -f "$ADM_ESTATE_SNAPSHOT"

  echo "Scenario 11: calibration-pollution tag (edge 3)"
  v="$(NL_PROTECTED_ORCHESTRATOR=1 adm_admit emit-feed)"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"protected":1'*) pass "protected-orchestrator traffic tagged protected=1" ;;
    *) fail "protected tag missing: $last" ;;
  esac
  adm_admit emit-feed >/dev/null
  last="$(tail -1 "$led")"
  case "$last" in
    *'"protected":0'*) pass "untagged traffic recorded protected=0" ;;
    *) fail "default protected tag wrong" ;;
  esac

  echo "Scenario 12: clock fields present with an honest source label (edge 5)"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"wall":"20'*) pass "wall clock present (ISO-8601 UTC)" ;;
    *) fail "wall clock missing/misformatted: $last" ;;
  esac
  case "$last" in
    *'"mono_src":"uptime"'*) pass "monotonic source honestly labelled: uptime" ;;
    *'"mono_src":"wall"'*)   pass "monotonic source honestly labelled: wall (no /proc/uptime here)" ;;
    *) fail "mono_src label missing: $last" ;;
  esac

  echo "Scenario 13: FAIL-OPEN under a hostile/unwritable state dir"
  local SAVED="$ADM_STATE_DIR"
  export ADM_STATE_DIR="/nonexistent-adm-$$/governor"
  v="$(adm_admit emit-feed)"; rc=$?
  [[ "$rc" == "0" ]] && pass "unwritable state dir still returns 0 (fail-open)" || fail "fail-open violated, rc=$rc"
  [[ -n "$v" ]] && pass "verdict still produced: $v" || fail "no verdict under unwritable dir"
  export ADM_STATE_DIR="$SAVED"

  echo "Scenario 14: ledger rotation is size-bounded"
  export ADM_LEDGER_MAX_BYTES=200
  adm_admit emit-feed >/dev/null
  adm_admit emit-feed >/dev/null
  [[ -f "$led.1" ]] && pass "oversize ledger rotated to .1" || fail "no rotation at 200 bytes"
  unset ADM_LEDGER_MAX_BYTES

  echo "Scenario 15: OBSERVE-MODE INVARIANT — no input produces a non-zero rc"
  : > "$ADM_STATE_DIR/HALT"; : > "$ADM_STATE_DIR/DRAIN"
  printf '{"color":"black"}\n' > "$ADM_PRESSURE_FILE"
  printf '{"live_sessions": 999}\n' > "$ADM_ESTATE_SNAPSHOT"
  local worst_rc=0 s
  for s in emit-feed resumer worktree selftest other; do
    adm_admit "$s" >/dev/null; rc=$?
    (( rc != 0 )) && worst_rc=$rc
  done
  (( worst_rc == 0 )) && pass "every dispatch source admits under HALT+DRAIN+BLACK+999 sessions" \
    || fail "OBSERVE-MODE VIOLATION: rc=$worst_rc — this lib must never block in T3"
  rm -f "$ADM_STATE_DIR/HALT" "$ADM_STATE_DIR/DRAIN" "$ADM_ESTATE_SNAPSHOT"

  echo "Scenario 16: sandbox integrity — nothing written outside the temp dir"
  local real="$HOME/.claude/state/governor"
  if [[ -e "$real" ]]; then
    fail "real governor state dir exists at $real — self-test may have escaped its sandbox"
  else
    pass "no real ~/.claude/state/governor created by this self-test"
  fi

  echo "Scenario 17: HOST self-test pollution guard (the defect Scenario 16 caught)"
  # A host script (workstreams-emit / session-resumer / spawn-worktree) running
  # ITS own self-test must not append to the operator's real ledger via our
  # splice. With HARNESS_SELFTEST=1 and NO explicit ADM_STATE_DIR, the lib must
  # resolve away from $HOME/.claude/state/governor.
  local saved_dir="${ADM_STATE_DIR:-}"
  unset ADM_STATE_DIR
  local resolved; resolved="$(HARNESS_SELFTEST=1 adm_state_dir)"
  case "$resolved" in
    "$HOME/.claude/state/governor")
      fail "HARNESS_SELFTEST=1 still resolved to REAL state ($resolved) — host self-tests would poison the calibration ledger" ;;
    *) pass "HARNESS_SELFTEST=1 with no ADM_STATE_DIR redirects away from real state ($resolved)" ;;
  esac
  # and an explicit dir must still win over the guard
  local explicit; explicit="$(ADM_STATE_DIR="$T/explicit" HARNESS_SELFTEST=1 adm_state_dir)"
  [[ "$explicit" == "$T/explicit" ]] && pass "explicit ADM_STATE_DIR still wins over the guard" \
    || fail "explicit ADM_STATE_DIR ignored, got '$explicit'"
  # and with neither set, production still resolves to real state
  local prod; prod="$(HARNESS_SELFTEST=0 adm_state_dir)"
  [[ "$prod" == "$HOME/.claude/state/governor" ]] && pass "production path unchanged when not self-testing" \
    || fail "production path wrong: '$prod'"
  [[ -n "$saved_dir" ]] && export ADM_STATE_DIR="$saved_dir"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

case "${1:-}" in
  --self-test) _adm_self_test ;;
esac
