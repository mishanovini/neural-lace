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
#   CARVE-OUT (task-verifier D5, 2026-07-28): session-resumer.sh returns early
#             on `storm-cap-queued` (:1626-1629) BEFORE reaching the splice, so
#             a resume DEFERRED by the rolling-hour storm cap emitted nothing —
#             precisely during the storms this slice exists to characterize.
#             FIXED by a second splice at that early-return recording
#             source=resumer with reason_hint=storm-cap-queued, so deferrals are
#             visible as their own class rather than as silence.
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
# HOT-PATH COST — MEASURED, NOT CLAIMED (design 6b edge 6).
#
# RETIRED CLAIM (2026-07-28, this is the slice's program-rule-3 retirement):
# this header previously asserted "uses builtins only ... forks at most ONCE ...
# one file read, ~0 ms". Both reviewers refuted it by measurement:
#   harness-reviewer: 19.3 ms/dispatch, 30+ command substitutions reachable
#   task-verifier   : 20.1 ms/call, 2 external execs (date, wc), ~45 subshell
#                     forks; --on-builder-dispatch 208.0 -> 234.8 ms (+13%)
#
# SECOND CORRECTION (same day, after the occupancy fix landed): every number
# above was measured on a machine where occupancy was DEAD — no snapshot existed,
# so adm_live_sessions returned -1 immediately without reading anything. With a
# real 20 KB janitor snapshot present, occupancy actually works and the cost is:
#   snapshot ABSENT  : 19.0 ms/dispatch
#   snapshot PRESENT : 70.8 ms/dispatch   <-- the honest production figure
# The 52 ms delta is reading the 20 KB document into a shell variable and running
# two O(n) parameter expansions over it. So the real gap to the <5 ms T6 budget
# is ~14x, not ~4x. The obvious fix is a TTL cache (occupancy only changes when
# the janitor runs, so caching is correct, not a shortcut) — deliberately NOT
# added here: it is unreviewed complexity late in a long session, and T6 must
# re-measure regardless. Named as T6 work, with this measurement as its baseline.
# Edge 6 says "dispatch-time access must be spawn-free bash builtins or the fix
# becomes its own overhead." THIS LIB DOES NOT MEET THAT BAR TODAY. The honest
# statement is: ~20 ms and ~45 forks per dispatch, +13% on the emit-feed path.
# That is tolerable for an observe-only slice and NOT tolerable at T6, when this
# moves onto the enforcing path. Retirement condition for the deviation: T6 must
# either collapse the $(...)-per-helper style into direct assignment (the forks
# are all command substitution, not real work) or re-measure and re-justify.
# Budget to hold it to: < 5 ms/dispatch before the enforcement flip.
#
# What IS true: this never calls hb_classify (measured expensive — backlog
# ESTATE-T1-HB-CLASSIFY-PERF-01, 12m38s for a full janitor pass); occupancy is
# read from the janitor's already-computed snapshot instead.
#
# DERIVED, NEVER DECLARED — TRUE FOR ARGUMENTS, MOSTLY TRUE FOR THE ENVIRONMENT NOW.
#
# RETIRED CLAIM (2026-07-28, same retirement): this header previously said
# "Nothing here trusts a caller-supplied claim about capacity." task-verifier
# falsified it in one command each, because the lib is SOURCED INTO THE
# DISPATCHER'S OWN SHELL, making that shell's entire environment a declaration
# channel:
#   ADM_ABSURD_SESSION_CAP=999999  -> admit where derived state says would-block
#   ADM_ESTATE_SNAPSHOT=/dev/null  -> admit (occupancy erased)
#   ADM_STATE_DIR=<elsewhere>      -> BYPASSES THE HALT KILL SWITCH ENTIRELY
#   NL_PROTECTED_ORCHESTRATOR=1    -> caller-declared, unverified; any process
#                                     can exclude its own traffic from the
#                                     "pathology" bucket in the calibration
#                                     this slice exists to produce
# The accurate claim: no caller ARGUMENT decides — the key enum drops
# live_sessions=/verdict=/rate_1m= and the snapshot wins (self-test Scenario 10).
#
# T6-PREREQUISITES (b) UPDATE (2026-07-29): of the four bypasses above, THREE
# are now CLOSED — ADM_ABSURD_SESSION_CAP, ADM_ESTATE_SNAPSHOT, and
# ADM_STATE_DIR are honored ONLY under HARNESS_SELFTEST=1 (see adm_state_dir,
# _adm_snapshot_path, _adm_session_cap below). No production callsite ever set
# any of the three (grep across adapters/claude-code confirmed zero non-lib,
# non-self-test occurrences at closure time), so gating them behind the flag
# this lib's own self-test now exports globally closes the bypass for every
# real dispatcher with zero production behavior change. Self-test Scenario 10b
# proves both halves: closed in production, still available under
# HARNESS_SELFTEST=1.
# NL_PROTECTED_ORCHESTRATOR stays OPEN by design — it is a genuine production
# signal the real protected orchestrator sets in ITS OWN environment; gating
# it behind HARNESS_SELFTEST would defeat its actual purpose (edge 3
# calibration-pollution tagging). There is no mechanism to verify a caller's
# self-declared identity without new authentication infrastructure
# disproportionate to this micro-slice — accepted in writing, residual risk
# named, at docs/decisions/065-admission-lib-env-bypass-closure.md.
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
#   adm_ledger_rotate           -> size-bounded rotation (called on every
#                                  adm_admit; NO other caller — the previous
#                                  "(called by the janitor)" annotation was
#                                  hallucinated infrastructure, 2026-07-28)
#   _adm_mtime <file>           -> portable mtime (GNU stat -c / BSD stat -f)
#   _adm_mtime_size <file>      -> portable "mtime size" in one stat call
#   adm_occ_cache_path          -> occupancy TTL cache file path (T6-prereq a)
#   _adm_snapshot_path          -> resolved janitor-snapshot path (ADM_ESTATE_
#                                  SNAPSHOT closed outside HARNESS_SELFTEST=1)
#   _adm_session_cap            -> resolved absurd-session-cap threshold
#                                  (ADM_ABSURD_SESSION_CAP closed likewise)
#
# STATE (all overridable for tests; hostname-scoped per review F10 so there is
# exactly ONE writer per file and cross-machine merge is append-only):
#   ADM_STATE_DIR      default $HOME/.claude/state/governor
#     HALT             kill switch      (one `touch` stops the estate — T6)
#     DRAIN            drain flag       (deny-new at safe boundaries — T4/T6)
#     pressure.json    written by the Loop-2 pressure tick (T6-PREREQUISITES
#                      (d), 2026-07-29 — hooks/lib/perf-tick-snapshot.sh's
#                      pts_write_pressure_tick, wired into pts_run_tick and
#                      therefore into health-tick.sh's existing hourly
#                      cadence; absent still means pressure=unknown, which
#                      admits; see below)
#     rate/            stamp file per dispatch (review F9: never a
#                      read-modify-write token bucket — those lose updates)
#     ledger/<host>.jsonl   the would-block ledger, O_APPEND, one writer
#   ADM_ESTATE_SNAPSHOT default $HOME/.claude/state/estate/snapshot.json
#                      T1's janitor output; source of slot occupancy.
#
# LOOP-2 PRESSURE TICK — WHAT IS BUILT AND WHAT IS STILL PARTIAL
# (T6-PREREQUISITES (d), 2026-07-29, replacing the prior "NOT BUILT HERE"
# claim): perf-tick-snapshot.sh's pts_write_pressure_tick now writes
# pressure.json every tick, so adm_pressure_color reads a real "tick" source
# instead of permanently "unknown", and the ledger's pressure_src field
# reads "tick" once a tick has run (self-test Scenario 18) rather than
# permanently "absent" (Scenario 19 still proves the honest fallback when it
# has not). The color ladder implemented there is PARTIAL: only the
# bash-count leg of the design's "CPU>75%/90% OR bash>60/90 OR RAM<15%"
# ladder is built (no CPU%/RAM% sampler exists anywhere in this repo to
# reuse, and building one is out of scope for this prerequisite slice); it
# never emits "black" (needs cross-tick persistence tracking, also not
# built). Do not read a 7-day window as FULLY pressure-calibrated on the
# CPU/RAM axes until those are built — the bash-count axis is real today.
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
# ADM_STATE_DIR STILL wins over that guard, but ONLY under HARNESS_SELFTEST=1
# (T6-PREREQUISITES (b), 2026-07-29 -- CLOSED bypass, was open before: the
# 2026-07-28 review found ADM_STATE_DIR honored unconditionally, which any
# sourcing shell could set to redirect the lib away from the real HALT kill
# switch. No production callsite ever set this var (grep across
# adapters/claude-code found zero non-lib, non-self-test occurrences), so
# gating it behind the flag this lib's OWN self-test now sets globally --
# see _adm_self_test's `export HARNESS_SELFTEST=1` -- closes the bypass for
# every real dispatcher without touching test isolation at all).
adm_state_dir() {
  if [[ -n "${ADM_STATE_DIR:-}" && "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s' "$ADM_STATE_DIR"; return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    # Honor the harness-wide HARNESS_SELFTEST_DIR convention (doctrine-jit.sh,
    # context-watermark.sh, pre-compact-continuity.sh all pair the two). The
    # 2026-07-28 review flagged ignoring it as a convention divergence.
    local base="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}}"
    # Leave an OBSERVABLE MARKER when we divert. A silent diversion means a
    # leaked HARNESS_SELFTEST in a real session would send production dispatches
    # to a throwaway dir with no trace — undercounting the calibration, which
    # biases T6 thresholds LOW, the F1 failure direction.
    printf '%s' "${base%/}/adm-selftest-$$"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/governor"
}

# Portable mtime — GNU coreutils `stat -c` vs BSD `stat -f`. This estate spans
# Windows/MSYS (GNU) and macOS (BSD); assuming either one breaks the other.
_adm_mtime() {
  local f="$1" m=""
  m="$(stat -c %Y "$f" 2>/dev/null)" || m=""
  [[ -n "$m" ]] || m="$(stat -f %m "$f" 2>/dev/null)" || m=""
  printf '%s' "${m:-0}"
}

# Portable mtime+size in ONE stat call (T6-prereq (a) — the occupancy TTL
# cache below needs both fields to key its cache; a separate `wc -c` per
# dispatch would be a second fork for no reason). Prints "mtime size".
_adm_mtime_size() {
  local f="$1" out=""
  out="$(stat -c '%Y %s' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="$(stat -f '%m %z' "$f" 2>/dev/null)" || out=""
  printf '%s' "${out:-0 0}"
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

# _adm_json_scalar <file> <key> — extract one scalar value from flat JSON.
#
# BOUNDED AT THE VALUE TERMINATOR, not at end-of-line. The 2026-07-28
# harness-review found the original line-oriented version returned 3379 for a
# true value of 3: estate-janitor.sh:692 writes the ENTIRE snapshot as a single
# line, so stripping non-digits "to end of line" concatenated every later number
# in the document. The self-test fixtures were all one-key-per-line, which masked
# the defect completely — hence the standing rule in this file's tests: fixtures
# must be the real producer's byte-for-byte output, never hand-written.
#
# Builtin-only: `$(<file)` is a bash read with no fork.
_adm_json_scalar() {
  local f="$1" key="$2" data rest val
  [[ -r "$f" ]] || return 1
  data="$(<"$f")" 2>/dev/null || return 1
  case "$data" in *"\"$key\""*) ;; *) return 1 ;; esac
  rest="${data#*\"$key\"}"
  rest="${rest#*:}"
  rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim
  val="${rest%%,*}"                          # bound at ,
  val="${val%%\}*}"                          # bound at }
  val="${val%%]*}"                           # bound at ]
  val="${val%%$'\n'*}"                       # bound at newline
  val="${val//\"/}"                          # unquote
  val="${val%"${val##*[![:space:]]}"}"       # rtrim
  printf '%s' "$val"
}

adm_pressure_color() {
  local f="${ADM_PRESSURE_FILE:-$(adm_state_dir)/pressure.json}"
  [[ -r "$f" ]] || { printf 'unknown'; return 0; }
  # READER-SIDE AGE BOUND (review REJECT C2, 2026-07-30): without this, a
  # stopped tick freezes the last color into authority FOREVER — at T6 a
  # frozen red would block every dispatch, a frozen green would admit
  # through a real storm (the exact frozen-occupancy class the 2026-07-28
  # review fixed one axis over). Default 7200s = 2x the hourly carrier
  # cadence (health-tick). Stale -> 'unknown' (which admits, fail-open).
  local max_age="${ADM_PRESSURE_MAX_AGE_SECS:-7200}"
  if (( max_age > 0 )); then
    local p_m now_p
    p_m="$(stat -c %Y "$f" 2>/dev/null)" || p_m=""
    now_p="$(_adm_now)"
    if [[ ! "$p_m" =~ ^[0-9]+$ ]] || (( now_p < p_m )) || (( now_p - p_m > max_age )); then
      printf 'unknown'; return 0
    fi
  fi
  local color; color="$(_adm_json_scalar "$f" color)" || color=""
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

# Returns the count of LIVE sessions, or -1 for unknown (which admits).
#
# 2026-07-28 review: the original read a "live_sessions" key that
# estate-janitor.sh:692 NEVER WRITES — occupancy was permanently dead even with
# a present snapshot, while the manifest claimed the window was
# occupancy-calibrated. We now count the field the janitor actually emits:
# each session row carries "classify":"<live|stale|throttled|crashed|missing>"
# (estate-janitor.sh:436), produced by session-heartbeat-lib.sh's hb_classify —
# so this IS the shared oracle's verdict (F8: slot liveness derives from
# heartbeats), just read from the janitor's cached pass instead of recomputed.
#
# ---------------------------------------------------------------------------
# Occupancy TTL cache (T6-PREREQUISITES (a), 2026-07-29)
# ---------------------------------------------------------------------------
# WHY: the header's measured cost (19.0 ms/dispatch snapshot-absent, 70.8 ms
# snapshot-present) is ~52 ms of reading the janitor's document into a shell
# variable and running two O(n) parameter expansions over it, below. The
# janitor snapshot only changes every ~5 min (its own scheduled cadence), so
# re-parsing it on EVERY dispatch is wasted work almost always.
#
# STALENESS CONTRACT (read this before changing ADM_OCC_CACHE_TTL_SECS):
# the cache is keyed on (source path, mtime-seconds, byte-size) — NOT a blind
# wall-clock cache. Any real snapshot change (new mtime OR new size) is an
# IMMEDIATE cache miss regardless of TTL, so a fresh janitor pass is never
# masked by a stale read. The TTL (default 45s, override
# ADM_OCC_CACHE_TTL_SECS, 0 disables caching entirely) is a SECONDARY,
# defensive bound for the one case identity-keying alone cannot catch: a
# rewrite that lands in the same wall-clock SECOND (stat's mtime resolution)
# AND happens to produce a byte-identical size to the previous content. That
# is exactly what this lib's own self-test does back-to-back
# (`_mk_snapshot 77` called twice around Scenario 9/10) — harmless there
# because both calls report the same count, but the TTL is what bounds the
# worst case in general to "at most one stale read per identity collision",
# which stays fail-open (an admission, not a false block) same as every other
# path in this observe-only slice. 45 s sits far inside the ~5 min snapshot
# cadence (the sizing this task asked for). A cache HIT does not re-evaluate
# ADM_SNAPSHOT_MAX_AGE_SECS staleness — safe because default TTL is 1/120th
# of default age_max; an operator setting age_max below the TTL window is
# trading that margin away deliberately.
#
# FORMAT: single line, TAB-delimited: mtime, size, count, computed_at(epoch),
# source path. Builtin `read` only — no fork on the hit path beyond the one
# `stat` already needed to know current (mtime,size) identity.
adm_occ_cache_path() { printf '%s/occupancy.cache' "$(adm_state_dir)"; }

_adm_occ_cache_write() {
  local path="$1" mtime="$2" size="$3" count="$4"
  local d; d="$(adm_state_dir)"
  [[ -d "$d" ]] || mkdir -p "$d" 2>/dev/null || return 0
  local now; now="$(_adm_now)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$mtime" "$size" "$count" "$now" "$path" \
    > "$(adm_occ_cache_path)" 2>/dev/null || true
  return 0
}

# Counting is builtin-only: strip every occurrence and divide the length delta.
#
# ADM_ESTATE_SNAPSHOT closure (T6-PREREQUISITES (b), 2026-07-29): the
# 2026-07-28 review named `ADM_ESTATE_SNAPSHOT=/dev/null` as a T6 bypass --
# any sourcing shell could erase occupancy by pointing this var elsewhere. No
# production callsite ever sets it (same grep result as ADM_STATE_DIR above),
# so the override is now honored ONLY under HARNESS_SELFTEST=1 (which every
# self-test scenario in this file gets for free from _adm_self_test's global
# `export HARNESS_SELFTEST=1`). CLOSED for every real dispatcher.
# Side-effect-free path resolver, factored out so the self-test can assert
# the ADM_ESTATE_SNAPSHOT closure directly (T6-PREREQUISITES (b)) without
# needing to drive a full adm_admit cycle.
_adm_snapshot_path() {
  local f="$HOME/.claude/state/estate/snapshot.json"
  if [[ "${HARNESS_SELFTEST:-0}" == "1" && -n "${ADM_ESTATE_SNAPSHOT:-}" ]]; then
    f="$ADM_ESTATE_SNAPSHOT"
  fi
  printf '%s' "$f"
}

adm_live_sessions() {
  local f; f="$(_adm_snapshot_path)"
  [[ -r "$f" ]] || { printf '%s' -1; return 0; }

  local ms snap_m snap_sz
  ms="$(_adm_mtime_size "$f")"
  snap_m="${ms%% *}"; snap_sz="${ms#* }"

  # ---- TTL cache fast path — see the staleness contract above ----
  local ttl="${ADM_OCC_CACHE_TTL_SECS:-45}"
  if (( ttl > 0 )); then
    local cache_f; cache_f="$(adm_occ_cache_path)"
    if [[ -r "$cache_f" ]]; then
      local c_mtime="" c_size="" c_count="" c_at="" c_path=""
      IFS=$'\t' read -r c_mtime c_size c_count c_at c_path < "$cache_f" 2>/dev/null
      # READ-BOUNDARY VALIDATION (review REJECT C1, 2026-07-30): c_count and
      # c_at come from a FILE and feed a bash arithmetic sink + an unquoted
      # JSON numeric field — the reviewer EXECUTED code through the
      # unvalidated path (array-subscript command substitution) and wrote
      # invalid JSON into the ledger. Anything non-numeric = cache miss.
      if [[ "$c_path" == "$f" && "$c_mtime" == "$snap_m" && "$c_size" == "$snap_sz" ]] \
         && [[ "$c_count" =~ ^-?[0-9]+$ ]] && [[ "$c_at" =~ ^[0-9]+$ ]]; then
        local now; now="$(_adm_now)"
        if (( now >= c_at && now - c_at < ttl )); then
          printf '%s' "$c_count"
          return 0
        fi
      fi
    fi
  fi

  local data; data="$(<"$f")" 2>/dev/null || { printf '%s' -1; return 0; }
  case "$data" in *'"sessions"'*) ;; *) printf '%s' -1; return 0 ;; esac

  # STALENESS (2026-07-28 review C4): this function's contract said "missing or
  # stale -> -1" while implementing only the missing half. A dead or wedged
  # janitor would freeze occupancy at its last value forever — at T6 a
  # frozen-high value blocks every dispatch and a frozen-low admits everything,
  # with no signal either way. Especially live here: there is NO darwin
  # scheduler for the janitor (installer is Windows-only), so on macOS the
  # snapshot is only as fresh as the last manual run.
  # Age is read from the file's MTIME, not by parsing generated_at into epoch.
  # task-verifier's round-2 note: an ISO->epoch conversion costs one or two more
  # `date` execs per dispatch on a hot path whose cost claim was just retired at
  # ~21 ms — it would move D2 in the wrong direction. mtime is one `stat` and is
  # a faithful proxy here because estate-janitor.sh writes the snapshot via
  # tmp+mv (ej_write_snapshot), so mtime IS the write time.
  local age_max="${ADM_SNAPSHOT_MAX_AGE_SECS:-5400}"
  if [[ "$snap_m" != "0" ]]; then
    local now2; now2="$(_adm_now)"
    if (( now2 - snap_m > age_max )); then
      (( ttl > 0 )) && _adm_occ_cache_write "$f" "$snap_m" "$snap_sz" -1
      printf '%s' -1; return 0
    fi
  fi

  # SCOPE THE COUNT TO sessions[] (2026-07-28 review C3): counting the needle
  # document-wide was wrong because estate-janitor.sh:611-626 embeds
  # signal_ledger_tail rows VERBATIM ("already-valid JSONL", unescaped). Any raw
  # region that ever carries the byte sequence would inflate occupancy — latent
  # today (that tail has zero such rows), active at T6 where over-count means
  # false blocks. Cut to the sessions array first; if the delimiters do not
  # parse, fail to UNKNOWN (-1), never to a permissive number.
  local region="${data#*\"sessions\":[}"
  [[ "$region" != "$data" ]] || { printf '%s' -1; return 0; }
  local tail_marker='],"sessions_degraded"'
  case "$region" in
    *"$tail_marker"*) region="${region%%"$tail_marker"*}" ;;
    *) printf '%s' -1; return 0 ;;   # unparseable region -> unknown, not 0
  esac

  local needle='"classify":"live"'
  local stripped="${region//$needle/}"
  local delta=$(( ${#region} - ${#stripped} ))
  (( delta >= 0 )) || { printf '%s' -1; return 0; }
  local count=$(( delta / ${#needle} ))
  (( ttl > 0 )) && _adm_occ_cache_write "$f" "$snap_m" "$snap_sz" "$count"
  printf '%s' "$count"
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

# ADM_ABSURD_SESSION_CAP closure (T6-PREREQUISITES (b), 2026-07-29): named as
# a T6 bypass by the 2026-07-28 review (any sourcing shell could raise the
# absurd-level backstop past derived occupancy). No production callsite ever
# sets it -- the only place that has ever set this var is this file's own
# self-test (Scenario 10b). So the override is honored ONLY under
# HARNESS_SELFTEST=1; every real dispatcher gets the fixed default of 50.
# A real, operator-authorized tunable threshold (per T6's calibration data)
# is T6's own job at the enforcement flip, not this observe-only prereq --
# this closure only removes the UNAUTHENTICATED environment-channel version.
_adm_session_cap() {
  local cap=50
  if [[ "${HARNESS_SELFTEST:-0}" == "1" && -n "${ADM_ABSURD_SESSION_CAP:-}" ]]; then
    cap="$ADM_ABSURD_SESSION_CAP"
  fi
  printf '%s' "$cap"
}

_adm_decide() {
  if adm_halt_active; then printf 'would-block:halt'; return 0; fi
  if adm_drain_active; then printf 'would-block:drain'; return 0; fi

  local color; color="$(adm_pressure_color)"
  case "$color" in
    black) printf 'would-block:pressure-black'; return 0 ;;
    red)   printf 'would-block:pressure-red';   return 0 ;;
  esac

  local live; live="$(adm_live_sessions)"
  if [[ "$live" != "-1" ]] && (( live >= $(_adm_session_cap) )); then
    printf 'would-block:session-backstop'; return 0
  fi

  # Reuse the caller's single measurement when it supplied one (adm_admit does),
  # so the verdict and the recorded rate_1m can never disagree.
  local rate="${_ADM_RATE_PRECOMPUTED:-}"
  [[ -n "$rate" ]] || rate="$(adm_rate_in_window)"
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

# RETENTION ARITHMETIC (2026-07-28 review: retention was not derived from the
# 7-day requirement). Measured mean line = 252 B. The slice's stated need is a
# >=7-day window. F1's cited sustained peak is 21 dispatches/min:
#   21/min * 1440 min * 7 d * 252 B = 53.4 MB  -> so ONE generation must hold
#   >= ~27 MB for 2 generations to cover the window at peak.
# The old 5 MiB default held 0.69 days at that rate and kept only ONE prior
# generation, so a peak week self-destructed inside 1.4 days. Now: 32 MiB per
# generation, 2 generations retained (.1 and .2), and a rotation marker line so
# a reader can tell rotation happened rather than silently reading a truncated
# window.
adm_ledger_rotate() {
  local f; f="$(adm_ledger_path)"
  [[ -f "$f" ]] || return 0
  local max="${ADM_LEDGER_MAX_BYTES:-33554432}"
  local size=0
  size="$(wc -c < "$f" 2>/dev/null)" || size=0
  size="${size//[^0-9]/}"
  [[ -n "$size" ]] || size=0
  if (( size > max )); then
    mv -f "$f.1" "$f.2" 2>/dev/null   # keep 2 generations, not 1
    mv -f "$f" "$f.1" 2>/dev/null || return 0
    # Rotation marker: without this a reader cannot distinguish "the window
    # starts here" from "the window was truncated here".
    printf '{"wall":"%s","host":"%s","event":"ledger-rotated","note":"previous generation moved to .1; older to .2"}\n' \
      "$(_adm_iso)" "$(_adm_host)" >> "$f" 2>/dev/null || true
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

  # Compute the rate ONCE. It used to be globbed (and reaped) twice per admit —
  # once inside _adm_decide, once for the ledger field — so the value that drove
  # the verdict could differ from the value recorded beside it.
  local rate; rate="$(adm_rate_in_window)"
  local verdict; verdict="$(_ADM_RATE_PRECOMPUTED="$rate" _adm_decide)"
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

  local color live mono mono_src pressure_src
  color="$(adm_pressure_color)"
  live="$(adm_live_sessions)"
  # LEDGER NUMERIC CLAMP (review REJECT C1): live/rate land in unquoted JSON
  # numeric positions — a non-numeric value would corrupt the 7-day
  # calibration ledger this program exists to produce. Unknown -> -1.
  [[ "$live" =~ ^-?[0-9]+$ ]] || live=-1
  [[ "$rate" =~ ^-?[0-9]+$ ]] || rate=-1
  # $rate is already computed above and was the value the verdict used.
  read -r mono mono_src <<< "$(_adm_mono)"
  # pressure_src is tick | tick-stale | absent (review REJECT C2): existence
  # alone is NOT a staleness signal; a calibration reader must be able to
  # discount lines whose color outlived the reader-side age bound.
  local p_f="${ADM_PRESSURE_FILE:-$(adm_state_dir)/pressure.json}"
  if [[ -r "$p_f" ]]; then
    if [[ "$color" == "unknown" ]]; then
      pressure_src="tick-stale"
    else
      pressure_src="tick"
    fi
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
  # T6-PREREQUISITES (b), 2026-07-29: this self-test IS the sanctioned
  # HARNESS_SELFTEST context, so it declares itself globally -- this is what
  # lets adm_state_dir/adm_live_sessions/_adm_session_cap honor their
  # ADM_STATE_DIR/ADM_ESTATE_SNAPSHOT/ADM_ABSURD_SESSION_CAP overrides below
  # while closing those SAME overrides for every real (non-self-test) caller.
  export HARNESS_SELFTEST=1
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

  echo "Scenario 9: absurd-level backstops, against PRODUCER-SHAPED snapshots"
  # 2026-07-28: these fixtures used to be hand-written one-key-per-line JSON
  # ({"live_sessions": 3}), which masked TWO Critical defects at once — the key
  # did not exist in the producer at all, and the parser broke on the producer's
  # real single-line document. Fixtures below are now shaped like
  # estate-janitor.sh:692's actual printf: ONE line, many keys, sessions[] rows
  # carrying "classify" exactly as estate-janitor.sh:436 emits them.
  _mk_snapshot() { # $1 = number of live sessions; writes producer-shaped JSON
    local n="$1" rows="" i
    for (( i=0; i<n; i++ )); do
      [[ -n "$rows" ]] && rows="$rows,"
      rows="$rows{\"session_id\":\"s$i\",\"classify\":\"live\",\"cwd\":\"/x\",\"branch\":\"master\",\"pid\":$((1000+i))}"
    done
    # include a non-live row and trailing numeric keys — the end-of-line-strip
    # bug concatenated these into the occupancy value (3 -> 3379)
    [[ -n "$rows" ]] && rows="$rows,"
    rows="$rows{\"session_id\":\"sdead\",\"classify\":\"crashed\",\"cwd\":\"/x\",\"branch\":\"main\",\"pid\":37}"
    # generated_at must be CURRENT: the C4 staleness check correctly rejects an
    # old snapshot as unknown, so a hard-coded past date would make every
    # occupancy scenario read -1 (which is exactly what happened when C4 landed).
    printf '{"schema":1,"generated_at":"%s","machine":"m","sessions":[%s],"sessions_degraded":false,"process_counts":{"bash_count":37,"claude_count":9,"degraded":false},"worktrees":94,"orphaned_worktrees":92,"orphaned_branches":142}\n' \
      "$(_adm_iso)" "$rows" > "$ADM_ESTATE_SNAPSHOT"
  }
  # GOLDEN FIXTURE — PRODUCED BY the real estate-janitor.sh, not shaped like it.
  # 2026-07-28 re-review C2: the first amendment added the rule "no hand-rolled
  # JSON extractor may be tested against a fixture the author wrote" and then
  # violated it 350 lines later with _mk_snapshot, an author-written printf that
  # only MIMICKED the producer — diverging exactly in the raw-embedded regions
  # where the C3 unscoped-count defect lived, which is why the suite stayed green
  # over a broken extractor. This fixture is a real `estate-janitor.sh run`
  # output (13 sessions: 12 crashed, 1 live), scrubbed of machine-identifying
  # data and kept in the producer's ONE-LINE shape, which is the entire point.
  local golden="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/fixtures/admission-lib/janitor-snapshot.golden.json"
  if [[ -r "$golden" ]]; then
    cp "$golden" "$ADM_ESTATE_SNAPSHOT"
    local gocc; gocc="$(ADM_SNAPSHOT_MAX_AGE_SECS=99999999 adm_live_sessions)"
    [[ "$gocc" == "1" ]] && pass "REAL producer output (13 sessions, 12 crashed/1 live) parses as 1" \
      || fail "golden-fixture occupancy wrong: expected 1, got '$gocc' — the parser disagrees with the real producer"
    # C3 regression: the needle must NOT be counted outside sessions[]
    local poisoned="$T/poisoned.json"
    sed 's/"signal_ledger_tail":\[/"signal_ledger_tail":["classify":"live" ,/' "$golden" > "$poisoned" 2>/dev/null || cp "$golden" "$poisoned"
    local pocc; pocc="$(ADM_ESTATE_SNAPSHOT="$poisoned" ADM_SNAPSHOT_MAX_AGE_SECS=99999999 adm_live_sessions)"
    [[ "$pocc" == "1" ]] && pass "needle outside sessions[] does NOT inflate occupancy (C3 scoped count)" \
      || fail "C3 regression: raw-embedded needle inflated occupancy to '$pocc'"
    # C4 regression: a stale snapshot must read UNKNOWN, not a frozen value.
    # Age is read from MTIME (cheaper than parsing generated_at — see the
    # function), so the fixture must be BACKDATED, not merely copied: `cp` gives
    # it a current mtime. `touch -t CCYYMMDDhhmm` is POSIX and identical on GNU
    # and BSD, unlike `touch -d`, which is the GNU-ism that breaks on macOS.
    touch -t 202001010000 "$ADM_ESTATE_SNAPSHOT" 2>/dev/null
    local socc; socc="$(ADM_SNAPSHOT_MAX_AGE_SECS=5400 adm_live_sessions)"
    [[ "$socc" == "-1" ]] && pass "stale snapshot -> -1 unknown, not a frozen occupancy (C4)" \
      || fail "C4 regression: stale snapshot returned '$socc' instead of -1"
    cp "$golden" "$ADM_ESTATE_SNAPSHOT"   # restore freshness for later scenarios
    rm -f "$ADM_ESTATE_SNAPSHOT"
  else
    fail "golden fixture missing at $golden — occupancy is only tested against author-written JSON"
  fi

  _mk_snapshot 3
  local occ; occ="$(adm_live_sessions)"
  [[ "$occ" == "3" ]] && pass "occupancy parses producer-shaped single-line JSON as 3 (was 3379 pre-fix)" \
    || fail "occupancy misparse: expected 3, got '$occ' — the end-of-line-strip defect is back"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "3 live sessions admits (legitimate load is 15-21/min per F1)" || fail "got '$v'"
  _mk_snapshot 77
  occ="$(adm_live_sessions)"
  [[ "$occ" == "77" ]] && pass "occupancy counts 77 live rows, ignoring the crashed row" || fail "expected 77, got '$occ'"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "would-block:session-backstop" ]] && pass "77 sessions trips the ~50 absurd backstop" || fail "got '$v'"
  rm -f "$ADM_ESTATE_SNAPSHOT"
  v="$(adm_admit emit-feed)"
  [[ "$v" == "admit" ]] && pass "absent snapshot -> unknown occupancy -> admit (fail-open)" || fail "got '$v'"

  echo "Scenario 9b: pressure parses a MULTI-KEY single-line document (the same defect class)"
  printf '{"schema":1,"color":"red","cpu":0.9,"src":"tick","bash":61}\n' > "$ADM_PRESSURE_FILE"
  local pc; pc="$(adm_pressure_color)"
  [[ "$pc" == "red" ]] && pass "multi-key single-line pressure parses as red (was 'unknown' pre-fix)" \
    || fail "pressure misparse: expected red, got '$pc'"
  printf '{"color":"green","note":"all clear, black is not the colour here"}\n' > "$ADM_PRESSURE_FILE"
  pc="$(adm_pressure_color)"
  [[ "$pc" == "green" ]] && pass "value bounded at the terminator, not confused by later text" \
    || fail "expected green, got '$pc'"
  rm -f "$ADM_PRESSURE_FILE"

  echo "Scenario 10: derived-not-declared (F4) — no caller ARGUMENT decides"
  _mk_snapshot 77
  v="$(adm_admit emit-feed live_sessions=1 verdict=admit rate_1m=0)"
  [[ "$v" == "would-block:session-backstop" ]] && pass "caller-declared live_sessions/verdict ignored; snapshot wins" || fail "caller overrode derived state: '$v'"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"live_sessions":77'*) pass "ledger records the DERIVED 77, not the declared 1" ;;
    *) fail "derived occupancy not recorded: $last" ;;
  esac
  rm -f "$ADM_ESTATE_SNAPSHOT"

  echo "Scenario 10b: the four T6 bypasses -- three now CLOSED, one ACCEPTED in writing"
  # 2026-07-28 review named four environment bypasses. T6-PREREQUISITES (b)
  # (2026-07-29) closed three of them (no production callsite ever set any of
  # the three -- verified by grep across adapters/claude-code) by gating their
  # overrides behind HARNESS_SELFTEST=1, which this self-test now exports
  # globally. The fourth (NL_PROTECTED_ORCHESTRATOR) is a genuine production
  # signal set by the REAL protected orchestrator's own environment -- gating
  # it behind HARNESS_SELFTEST would break its actual purpose, so it stays
  # open by design; see docs/decisions/065-admission-lib-env-bypass-closure.md
  # for the written acceptance. Scenario 11 above already proves it still
  # works in production (no HARNESS_SELFTEST needed to tag protected=1).
  #
  # These checks call the PURE, side-effect-free resolvers directly
  # (_adm_session_cap / adm_state_dir / _adm_snapshot_path), never adm_admit
  # with HARNESS_SELFTEST=0 -- that would fall through to the REAL production
  # state dir and write a real ledger line, exactly the sandbox escape
  # Scenario 16 exists to catch.
  local cap_prod cap_test
  cap_prod="$(HARNESS_SELFTEST=0 ADM_ABSURD_SESSION_CAP=999999 _adm_session_cap)"
  [[ "$cap_prod" == "50" ]] && pass "CLOSED: ADM_ABSURD_SESSION_CAP ignored outside HARNESS_SELFTEST (production sees the fixed default of 50)" \
    || fail "ADM_ABSURD_SESSION_CAP still honored in production: got cap=$cap_prod, expected 50"
  cap_test="$(HARNESS_SELFTEST=1 ADM_ABSURD_SESSION_CAP=999999 _adm_session_cap)"
  [[ "$cap_test" == "999999" ]] && pass "still available under HARNESS_SELFTEST=1 (the escape hatch itself still works for tests)" \
    || fail "ADM_ABSURD_SESSION_CAP override broken even under HARNESS_SELFTEST=1: got '$cap_test'"

  local dir_prod dir_test
  dir_prod="$(HARNESS_SELFTEST=0 ADM_STATE_DIR="$T/elsewhere" adm_state_dir)"
  [[ "$dir_prod" == "$HOME/.claude/state/governor" ]] && pass "CLOSED: ADM_STATE_DIR ignored outside HARNESS_SELFTEST (production resolves to real state, HALT kill switch cannot be hidden)" \
    || fail "ADM_STATE_DIR still honored in production: got '$dir_prod'"
  dir_test="$(HARNESS_SELFTEST=1 ADM_STATE_DIR="$T/elsewhere" adm_state_dir)"
  [[ "$dir_test" == "$T/elsewhere" ]] && pass "still available under HARNESS_SELFTEST=1 (Scenario 17 covers this too; re-confirmed here alongside its siblings)" \
    || fail "ADM_STATE_DIR override broken even under HARNESS_SELFTEST=1: got '$dir_test'"

  local snap_prod snap_test
  snap_prod="$(HARNESS_SELFTEST=0 ADM_ESTATE_SNAPSHOT="$T/elsewhere.json" _adm_snapshot_path)"
  [[ "$snap_prod" == "$HOME/.claude/state/estate/snapshot.json" ]] && pass "CLOSED: ADM_ESTATE_SNAPSHOT ignored outside HARNESS_SELFTEST (production reads the real janitor snapshot path, occupancy cannot be erased via /dev/null)" \
    || fail "ADM_ESTATE_SNAPSHOT still honored in production: got '$snap_prod'"
  snap_test="$(HARNESS_SELFTEST=1 ADM_ESTATE_SNAPSHOT="$T/elsewhere.json" _adm_snapshot_path)"
  [[ "$snap_test" == "$T/elsewhere.json" ]] && pass "still available under HARNESS_SELFTEST=1 (this file's own fixture-swapping in Scenario 9 depends on it)" \
    || fail "ADM_ESTATE_SNAPSHOT override broken even under HARNESS_SELFTEST=1: got '$snap_test'"

  echo "  (NL_PROTECTED_ORCHESTRATOR: ACCEPTED open by design -- see Scenario 11 and docs/decisions/065-admission-lib-env-bypass-closure.md)"

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

  echo "Scenario 16: sandbox integrity — DELTA on the real ledger, not its absence"
  # 2026-07-28: this scenario used to assert $HOME/.claude/state/governor does
  # NOT EXIST. That conflated "the dir exists" with "my self-test created it" —
  # so the moment the production splices worked, the lib's own regression test
  # went permanently red (37/1) on every machine it had ever run on, and the
  # "38/0" claimed in the commit message became reproducible only where the
  # deliverable does not exist. Both reviewers flagged it Critical.
  # The correct assertion is a BEFORE/AFTER DELTA on the real artifact.
  local real_led="$HOME/.claude/state/governor/ledger/$(_adm_host).jsonl"
  local before_n=0 before_m=0
  if [[ -f "$real_led" ]]; then
    before_n="$(wc -l < "$real_led" 2>/dev/null | tr -d ' ')"
    before_m="$(_adm_mtime "$real_led")"
  fi
  # drive a full admit cycle with the sandbox active
  adm_admit selftest >/dev/null 2>&1
  local after_n=0 after_m=0
  if [[ -f "$real_led" ]]; then
    after_n="$(wc -l < "$real_led" 2>/dev/null | tr -d ' ')"
    after_m="$(_adm_mtime "$real_led")"
  fi
  if [[ "$before_n" == "$after_n" && "$before_m" == "$after_m" ]]; then
    pass "real ledger unchanged by this self-test (lines $before_n->$after_n, mtime identical)"
  else
    fail "SANDBOX ESCAPE: real ledger changed (lines $before_n->$after_n, mtime $before_m->$after_m)"
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

  echo "Scenario 18: pressure_src populated end-to-end from the Loop-2 tick (T6-PREREQUISITES (d))"
  # Wires perf-tick-snapshot.sh's pts_write_pressure_tick (the Loop-2 writer)
  # straight into this lib's own adm_pressure_color/adm_admit reader, proving
  # pressure_src stops being permanently "absent" once the tick has run --
  # the exact gap this header used to document as "NOT BUILT YET".
  local pts_lib; pts_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf-tick-snapshot.sh"
  if [[ -r "$pts_lib" ]]; then
    (
      # subshell: PTS_* globals and PERF_TICK_* overrides never leak into
      # the rest of this suite; ADM_PRESSURE_FILE is inherited (not
      # re-exported) so the write lands exactly where adm_pressure_color
      # will look.
      source "$pts_lib"
      export PERF_TICK_PRESSURE_FILE="$ADM_PRESSURE_FILE"
      export PERF_TICK_PROCESS_LIST_CMD="printf 'Node,CreationDate,Name,ParentProcessId,ProcessId\nOFFICE_PC,20260101000000.000000-420,node.exe,0,1\n'"
      export PERF_TICK_DEFENDER_CMD="true"
      pts_collect_processes
      pts_write_pressure_tick
    )
    if [[ -r "$ADM_PRESSURE_FILE" ]]; then
      pass "Loop-2 tick wrote a real pressure.json (was 'NOT BUILT YET' per this file's own header)"
    else
      fail "pts_write_pressure_tick did not create $ADM_PRESSURE_FILE"
    fi
    local pc_after; pc_after="$(adm_pressure_color)"
    [[ "$pc_after" == "green" ]] && pass "adm_pressure_color reads the tick's output (0 bash rows -> green, the design's own bash>60/90 ladder)" \
      || fail "expected green from the tick-written file, got '$pc_after'"
    v="$(adm_admit emit-feed)"
    last="$(tail -1 "$led")"
    case "$last" in
      *'"pressure_src":"tick"'*) pass "ledger records pressure_src=tick once the Loop-2 tick has run (was permanently 'absent' before this slice)" ;;
      *) fail "pressure_src still absent after a real tick ran: $last" ;;
    esac
    rm -f "$ADM_PRESSURE_FILE"
  else
    fail "perf-tick-snapshot.sh not found at $pts_lib -- cannot prove the Loop-2 wiring"
  fi

  echo "Scenario 19: pressure_src stays absent when no tick has ever run (unchanged honesty contract)"
  rm -f "$ADM_PRESSURE_FILE"
  v="$(adm_admit emit-feed)"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"pressure_src":"absent"'*) pass "pressure_src=absent when the tick file is genuinely missing (fail-open, never silently defaulted to a color)" ;;
    *) fail "pressure_src not absent with no pressure file: $last" ;;
  esac

  echo "Scenario 20: CORRUPT OCCUPANCY CACHE is a MISS, never an arithmetic sink (review REJECT C1 — the reviewer executed code through the unvalidated path)"
  # Poison the cache with the reviewer's own injection payload shape; the
  # snapshot identity fields are made to MATCH so only the numeric guard
  # stands between the payload and the (( )) sink.
  snap20="$T/snap20.json"
  # PRODUCER-SHAPED fixture (the 2026-07-28 review's own law): the region
  # parse requires the '],"sessions_degraded"' terminator estate-janitor
  # emits — without it the lib honestly refuses to count (-1). Two drafts
  # of this scenario failed their own recount assert by violating the
  # producer shape ("x" generated_at; missing terminator).
  printf '{"generated_at":%s,"sessions":[{"classify":"live"},{"classify":"live"}],"sessions_degraded":false}\n' "$(date -u +%s)" > "$snap20"
  s20_m="$(stat -c %Y "$snap20" 2>/dev/null)"; s20_sz="$(stat -c %s "$snap20" 2>/dev/null)"
  inj_marker="$T/injected-by-scenario-20"
  printf '%s\t%s\t%s\t%s\t%s\n' "$s20_m" "$s20_sz" 'x[$(touch '"$inj_marker"')]' "$(date -u +%s)" "$snap20" > "$(adm_occ_cache_path)"
  occ20_err="$T/occ20.stderr"
  occ20="$(ADM_ESTATE_SNAPSHOT="$snap20" adm_live_sessions 2>"$occ20_err")"
  if [[ ! -e "$inj_marker" ]]; then
    pass "injection payload in the cache did NOT execute (numeric gate holds)"
  else
    fail "COMMAND INJECTION: the cache payload created $inj_marker"
  fi
  [[ "$occ20" == "2" ]] && pass "corrupt cache degraded to a MISS and the real snapshot was re-parsed (count=2)" \
    || fail "expected recount 2 after corrupt-cache miss, got '$occ20'"
  [[ -s "$occ20_err" ]] && fail "corrupt cache leaked bash diagnostics to stderr: $(head -1 "$occ20_err")" \
    || pass "fail-open path stayed silent on stderr under a poisoned cache"

  echo "Scenario 21: STALE pressure file -> color unknown + pressure_src tick-stale (review REJECT C2 — existence is not a staleness signal)"
  printf '{"color":"red"}\n' > "$ADM_PRESSURE_FILE"
  pc21="$(ADM_PRESSURE_MAX_AGE_SECS=0 ADM_PRESSURE_FILE="$ADM_PRESSURE_FILE" adm_pressure_color)"
  # max_age=0 disables the bound (matches the ttl>0 idiom); use a 1-second
  # bound against a backdated file instead.
  touch -d '2000-01-01' "$ADM_PRESSURE_FILE" 2>/dev/null || touch -t 200001010000 "$ADM_PRESSURE_FILE" 2>/dev/null
  pc21="$(ADM_PRESSURE_MAX_AGE_SECS=1 ADM_PRESSURE_FILE="$ADM_PRESSURE_FILE" adm_pressure_color)"
  [[ "$pc21" == "unknown" ]] && pass "a color older than the reader-side age bound reads unknown (a frozen red can never become permanently authoritative)" \
    || fail "expected unknown from a stale pressure file, got '$pc21'"
  v="$(ADM_PRESSURE_MAX_AGE_SECS=1 adm_admit emit-feed)"
  last="$(tail -1 "$led")"
  case "$last" in
    *'"pressure_src":"tick-stale"'*) pass "ledger records pressure_src=tick-stale for an outlived color (calibration readers can discount it)" ;;
    *) fail "expected pressure_src=tick-stale for a stale file: $last" ;;
  esac
  rm -f "$ADM_PRESSURE_FILE"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

# GATED ON BEING EXECUTED, NOT SOURCED (2026-07-28 harness-review, Major).
# A sourced lib that dispatches on "$1" inherits the CALLER's positionals:
# `set -- --self-test; source admission-lib.sh` ran the entire self-test inside
# the host shell — including its `rm -rf "$T"` and its export of ADM_STATE_DIR.
# Not triggerable at any current callsite (all three splices sit where $1 is
# either unset or a session id), but this file is spliced into dispatch paths
# and the next splice author should not have to know that.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _adm_self_test ;;
  esac
fi
