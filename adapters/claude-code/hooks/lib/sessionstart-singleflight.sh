#!/bin/bash
# sessionstart-singleflight.sh — debounced single-flight guard for heavy
# SessionStart scripts (auto-install; optionally digest / doctor).
#
# THE GAP THIS CLOSES
#   When N Claude Code sessions start within a short window, each independently
#   runs the heavy SessionStart scripts (git fetch + full ~/.claude sync, doctor,
#   digest). On Windows every subprocess is a full CreateProcess that Defender
#   scans, so simultaneous starts drove the live bash.exe count 34 -> 81 with
#   MsMpEng pinning a core. See docs/lessons/2026-07-13-agent-efficiency-
#   bottlenecks-process-spawn-and-hook-latency.md (rec 2 / SESSIONSTART-SINGLEFLIGHT-01).
#
# API (source this file, then):
#   ss_singleflight <name> <ttl_seconds>
#     rc 0 — caller SHOULD RUN the work (it created or reclaimed the run-stamp)
#     rc 1 — a FRESH run-stamp exists (a session ran within <ttl>s) → SKIP; the
#            shared ~/.claude that session produced already covers this one.
#   Bypass:  export SSF_DISABLE=1  → always rc 0 (callers' own self-tests use this).
#   State :  ${SSF_STATE_DIR:-$HOME/.claude/state/singleflight}/<name>.lock  (a dir)
#
# FAIL-OPEN CONTRACT: every internal error path returns 0 (run). A broken or
# unwritable lock must NEVER prevent a session from starting.
#
# WHY A DEBOUNCE (not a mutex held for the work's duration):
#   The stamp is created on acquire and simply AGES OUT after <ttl>s — there is
#   no explicit release and no EXIT trap. The goal is "run at most once per
#   <ttl>s across concurrent/rapid starts", which also covers the just-finished
#   case, with zero release-on-crash hazard: a crashed holder's stamp expires on
#   its own. Staleness is read from the stamp's stored epoch (second precision),
#   falling back to directory mtime (`find -mmin`, minute precision) when the
#   epoch is unreadable — both portable on MSYS Git Bash where flock/stat are
#   unreliable.
#
# Self-test: bash sessionstart-singleflight.sh --self-test   (7 scenarios)

_ssf_base_dir() { printf '%s' "${SSF_STATE_DIR:-$HOME/.claude/state/singleflight}"; }

# _ssf_stamp_age <lockdir> — echo age in seconds from the stored epoch, or -1
# if the epoch is missing/garbled (caller then uses the mtime fallback).
_ssf_stamp_age() {
  local lockdir="$1" ts now
  ts=$(awk 'NR==1{print $2}' "$lockdir/owner" 2>/dev/null)
  now=$(date +%s 2>/dev/null || echo 0)
  if [[ "$ts" =~ ^[0-9]+$ ]] && [[ "$ts" -gt 0 ]] && [[ "$now" =~ ^[0-9]+$ ]] && [[ "$now" -ge "$ts" ]]; then
    echo $(( now - ts )); return 0
  fi
  echo -1
}

# _ssf_is_stale <lockdir> <ttl_seconds> — rc 0 if the stamp is older than ttl.
_ssf_is_stale() {
  local lockdir="$1" ttl="$2" age ttl_min
  age=$(_ssf_stamp_age "$lockdir")
  if [[ "$age" -ge 0 ]] 2>/dev/null; then
    [[ "$age" -ge "$ttl" ]]; return
  fi
  # Unknown epoch → coarse mtime fallback (minute granularity). If `find` is
  # unavailable we cannot assess age at all: return 0 (stale → reclaim → RUN) so
  # the fail-open contract holds even on this conjunction — an indeterminate lock
  # must never make a session skip its setup. (A WORKING find that returns empty
  # is a genuinely-young lock → not stale → skip; that is the intended debounce,
  # not an error path.)
  command -v find >/dev/null 2>&1 || return 0
  ttl_min=$(( (ttl + 59) / 60 )); [[ "$ttl_min" -lt 1 ]] && ttl_min=1
  [[ -n "$(find "$lockdir" -maxdepth 0 -mmin +"$ttl_min" 2>/dev/null)" ]]
}

_ssf_write_owner() {
  printf '%s %s\n' "$$" "$(date +%s 2>/dev/null || echo 0)" > "$1/owner" 2>/dev/null || true
}

ss_singleflight() {
  local name="$1" ttl="${2:-120}" base lockdir
  [[ "${SSF_DISABLE:-0}" == "1" ]] && return 0   # explicit bypass (self-tests)
  [[ -z "$name" ]] && return 0                    # misuse → fail-open (run)
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=120
  base="$(_ssf_base_dir)"
  lockdir="$base/${name}.lock"
  mkdir -p "$base" 2>/dev/null || return 0        # can't make state dir → fail-open (run)
  # Atomic claim: mkdir succeeds for exactly one racer.
  if mkdir "$lockdir" 2>/dev/null; then
    _ssf_write_owner "$lockdir"; return 0
  fi
  # A stamp already exists — fresh or stale?
  if _ssf_is_stale "$lockdir" "$ttl"; then
    rm -rf "$lockdir" 2>/dev/null || true
    if mkdir "$lockdir" 2>/dev/null; then
      _ssf_write_owner "$lockdir"; return 0
    fi
    return 0    # lost the reclaim race → proceed anyway (fail-open toward running)
  fi
  return 1      # fresh stamp held by a recent session → skip
}

# ss_repo_key <path> — pure-bash (no subprocess spawn — the whole point of
# this lib is to CUT spawns, not add one) sanitization of a filesystem path
# into a short, collision-safe token for use as part of an ss_singleflight
# <name>. auto-install's sync is machine-GLOBAL (one lock name suffices —
# ~/.claude is the same shared mirror for every session). A caller whose
# heavy work is instead REPO-SCOPED (e.g. a SessionStart digest that reports
# on $PWD's git-freshness/worktree-state, which genuinely differs between
# concurrently-starting sessions in DIFFERENT repos/worktrees) MUST fold
# this into its lock name — otherwise a session-start-digest.sh in repo A
# would wrongly skip its OWN report because a repo-B session's digest
# claimed the SAME lock seconds earlier.
# T3 (SESSIONSTART-SINGLEFLIGHT-01 extension, agent-efficiency-fixes-2026-07).
ss_repo_key() {
  local p="${1:-$PWD}"
  p="${p//[:\\\/]/_}"
  printf '%s' "${p:0:80}"
}

# ============================================================
# Self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0; FAIL=0
  _tmp=$(mktemp -d 2>/dev/null || mktemp -d -t ssf) || { echo "cannot mktemp" >&2; exit 1; }
  trap 'rm -rf "$_tmp"' EXIT
  export SSF_STATE_DIR="$_tmp/sf"
  _ok() { if [[ "$1" == "$2" ]]; then echo "self-test: PASS — $3" >&2; PASS=$((PASS+1)); else echo "self-test: FAIL — $3 (got '$1' want '$2')" >&2; FAIL=$((FAIL+1)); fi; }

  # S1: clean acquire → rc 0, lockdir exists
  ss_singleflight s1 120; rc=$?; _ok "$rc" 0 "S1 clean acquire returns 0"
  [[ -d "$SSF_STATE_DIR/s1.lock" ]] && _ok present present "S1 lockdir created" || _ok absent present "S1 lockdir created"

  # S2: fresh stamp held → rc 1 (skip)
  ss_singleflight s2 120 >/dev/null   # first claim
  ss_singleflight s2 120; rc=$?; _ok "$rc" 1 "S2 fresh stamp → skip (rc 1)"

  # S3: stale stamp → reclaim (rc 0). Back-date the owner epoch.
  mkdir -p "$SSF_STATE_DIR/s3.lock"; printf '%s %s\n' 99999 1 > "$SSF_STATE_DIR/s3.lock/owner"
  ss_singleflight s3 120; rc=$?; _ok "$rc" 0 "S3 stale stamp → reclaim (rc 0)"

  # S4: re-acquire after removal → rc 0
  ss_singleflight s4 120 >/dev/null; rm -rf "$SSF_STATE_DIR/s4.lock"
  ss_singleflight s4 120; rc=$?; _ok "$rc" 0 "S4 re-acquire after removal (rc 0)"

  # S5: SSF_DISABLE bypass → rc 0 even with a fresh held stamp
  ss_singleflight s5 120 >/dev/null
  SSF_DISABLE=1 ss_singleflight s5 120; rc=$?; _ok "$rc" 0 "S5 SSF_DISABLE bypass (rc 0)"

  # S6: fail-open when state dir is uncreatable (base under a regular file)
  _f="$_tmp/afile"; : > "$_f"
  SSF_STATE_DIR="$_f/cannot" ss_singleflight s6 120; rc=$?; _ok "$rc" 0 "S6 uncreatable state dir → fail-open (rc 0)"

  # S7: mutual exclusion — with one fresh holder, N concurrent attempts all skip
  ss_singleflight s7 120 >/dev/null   # holder
  acq=0
  for i in 1 2 3 4 5; do
    ( ss_singleflight s7 120 ) && acq=$((acq+1))
  done
  _ok "$acq" 0 "S7 held stamp → all 5 concurrent attempts skip"
  rm -rf "$SSF_STATE_DIR/s7.lock"
  ss_singleflight s7 120; rc=$?; _ok "$rc" 0 "S7 after release, next attempt acquires (rc 0)"

  # S8: ss_repo_key — pure-bash path sanitization (T3 repo-scoping helper)
  r8="$(ss_repo_key '/c/Users/x/repo-a')"
  _ok "$r8" "_c_Users_x_repo-a" "S8a ss_repo_key sanitizes slashes/colons to underscores"
  r8b="$(ss_repo_key '/c/Users/x/repo-a')"
  r8c="$(ss_repo_key '/c/Users/x/repo-b')"
  if [[ "$r8b" != "$r8c" ]]; then
    echo "self-test: PASS — S8b different repo paths -> different keys" >&2; PASS=$((PASS+1))
  else
    echo "self-test: FAIL — S8b different repo paths produced the SAME key ('$r8b')" >&2; FAIL=$((FAIL+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASS passed, $FAIL failed" >&2
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi
