#!/bin/bash
# hook-reentry-guard.sh — shared library: the KEYSTONE fix for the
# spawn-cascade incident (NL-FINDING-040; fix/spawn-cascade-guard branch).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
#
# A runaway bash/claude spawn cascade exhausted memory and crashed the
# operator's machine. Root-structural cause #1 (of three; see
# NL-FINDING-040 in docs/findings.md for the full diagnosis): NOTHING in
# the harness told a hook "you are running inside an automation-spawned
# session — do minimal work and DO NOT spawn anything else." A
# `claude`/`claude -p` process launched by automation (session-resumer.sh,
# a future scheduled task, a script that shells out to `claude`) inherits
# the FULL live hook suite: every SessionStart hook (session-start-digest.sh's
# ~16 feeds including a `harness-doctor.sh --quick` refresh,
# session-start-auto-install.sh, etc.) and every Stop hook
# (stop-verdict-dispatcher.sh + the workstreams-stop-writer member chain)
# fires again in the child, some of which themselves spawn further
# subprocesses (workstreams-emit.sh, session-heartbeat.sh, needs-you.sh).
# With no reentrancy signal anywhere, there was no mechanical way for a
# hook to recognize "I am an automation-spawned child" and refuse to keep
# going.
#
# This library is the ONE place that answers "should this invocation
# suppress its expensive/spawning behavior and no-op instead?" Every
# caller sources it and, at the top of its real work (after arg/stdin
# parsing, before any expensive scan or subprocess spawn), calls
# `hook_reentry_should_suppress` and exits 0 immediately if it returns
# true.
#
# ============================================================
# THE MECHANISM
# ============================================================
#
# Suppression fires on ONE explicit signal:
#
#   NL_HOOK_REENTRY is set to "1" in the environment. Any NL automation
#   that is about to spawn a `claude`/`claude -p` child (session-resumer.sh's
#   two call sites, any future scheduled-task launcher) MUST export
#   NL_HOOK_REENTRY=1 into that child's environment before spawning it.
#   Every hook this guard protects then no-ops in the child, because the
#   child's own hook suite fires again but the child is not a
#   human-interactive session that needs the full SessionStart/Stop
#   ceremony — it is a resume/nudge payload, and the ceremony's JOB
#   (surfacing state to a human, refreshing caches for a human's next
#   look) has no audience there.
#
# The signal is OFF (unset) by default, so a normal interactive session's
# hooks behave exactly as before this file existed — this is purely
# additive safety, never a behavior change for the common case.
#
# (An earlier draft also carried a generic NL_HOOK_DEPTH counter branch.
# It was deleted per the adversarial review (FIX-4, §10 anti-theater):
# nothing in production ever incremented NL_HOOK_DEPTH, so the depth branch
# was dead code advertising a defense that did not exist. Only the explicit
# NL_HOOK_REENTRY signal — the one that actually fires — remains, so these
# docs match runtime exactly.)
#
# ============================================================
# WHAT "SUPPRESS" MEANS FOR A CALLER
# ============================================================
#
# hook_reentry_should_suppress returns 0 (true, shell success) when the
# caller should skip its expensive/spawning body and exit 0 immediately
# (a silent, fast no-op — NOT a warning, NOT a block; the child session
# still needs to be able to proceed, just without redundant harness
# ceremony). It returns 1 (false) otherwise, in which case the caller
# proceeds exactly as it always has.
#
# The two genuinely load-bearing Stop gates (session-honesty-gate.sh,
# work-integrity-gate.sh, and by extension stop-verdict-dispatcher.sh
# which aggregates them) delegate ALL their verification via forked member
# subprocesses, so there is no way to "run the logic but never spawn" —
# stop-verdict-dispatcher.sh therefore suppresses its whole verification+
# fork chain under NL_HOOK_REENTRY=1, on the reasoning that an
# automation-spawned resume nudge is not where a fresh honesty ceremony
# needs to fire (the ORIGINAL session's own Stop already governed that
# work). See each hook's own inline comment for how it honors the split.
#
# ============================================================
# FAIL-SAFE CONTRACT
# ============================================================
#
# This library NEVER breaks a caller. If sourcing fails, if this file is
# absent entirely (older checkout, partial install), or if a caller
# forgets to check its return value, behavior is IDENTICAL to before this
# guard existed: hooks run their normal body. Every function here is a
# pure read of one environment variable — no file I/O, no subprocess
# calls, nothing that itself could fail expensively. A caller sources this
# file with the standard best-effort pattern:
#
#   HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck disable=SC1091
#   { source "$HOOKS_DIR/lib/hook-reentry-guard.sh" 2>/dev/null; } || true
#   if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
#     hook_reentry_note "my-hook-name"   # optional: ledger breadcrumb, best-effort
#     exit 0
#   fi
#
# ============================================================
# USAGE
# ============================================================
#
#   source "${BASH_SOURCE%/*}/lib/hook-reentry-guard.sh"
#   if hook_reentry_should_suppress; then exit 0; fi
#
#   # A launcher about to spawn a `claude` child that must not cascade:
#   NL_HOOK_REENTRY=1 claude -p --resume "$sid" "$nudge"

# ----------------------------------------------------------------------
# Source-guard
# ----------------------------------------------------------------------
if [[ -n "${_HOOK_REENTRY_GUARD_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_HOOK_REENTRY_GUARD_SOURCED=1

# ----------------------------------------------------------------------
# hook_reentry_should_suppress — 0 (true) iff the caller should no-op
# because this invocation is an automation-spawned/re-entrant child
# (NL_HOOK_REENTRY=1).
# ----------------------------------------------------------------------
hook_reentry_should_suppress() {
  [[ "${NL_HOOK_REENTRY:-0}" == "1" ]]
}

# ----------------------------------------------------------------------
# hook_reentry_reason — echoes a one-line human-readable reason the guard
# suppressed, for callers that want to log it. Empty string if not
# currently suppressed.
# ----------------------------------------------------------------------
hook_reentry_reason() {
  if [[ "${NL_HOOK_REENTRY:-0}" == "1" ]]; then
    printf 'NL_HOOK_REENTRY=1 (automation-spawned child)'
    return 0
  fi
  printf ''
}

# ----------------------------------------------------------------------
# hook_reentry_note <hook-name> — best-effort single-line breadcrumb to
# the signal ledger (if available) recording that a hook suppressed
# itself. NEVER fails the caller; a missing/failed ledger lib is silently
# tolerated. Purely observational — this is what lets a human later see
# "yes, the guard fired here" rather than a hook simply going quiet with
# no trace.
# ----------------------------------------------------------------------
hook_reentry_note() {
  local hook_name="${1:-unknown-hook}"
  command -v ledger_emit >/dev/null 2>&1 || return 0
  local reason
  reason="$(hook_reentry_reason)"
  ledger_emit "$hook_name" "reentry-suppressed" "$reason" 2>/dev/null || true
  return 0
}

# ----------------------------------------------------------------------
# hook_reentry_export_for_child — echoes the env-var assignment a caller
# should prefix onto any `claude`/`claude -p` spawn to mark the child as
# reentrant. Callers typically don't need this helper (they can just write
# `NL_HOOK_REENTRY=1 claude ...` directly), but it exists so a caller
# building a command STRING (e.g. session-resumer.sh's build_resume_command,
# which returns a verbatim string for --self-test assertions) has a single
# canonical spot to get the exact assignment text.
# ----------------------------------------------------------------------
hook_reentry_export_for_child() {
  printf 'NL_HOOK_REENTRY=1'
}

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  echo "Scenario 1: no env set -> not suppressed"
  unset NL_HOOK_REENTRY
  if hook_reentry_should_suppress; then
    no "expected NOT suppressed with no env set"
  else
    ok "not suppressed with no env set"
  fi

  echo "Scenario 2: NL_HOOK_REENTRY=1 -> suppressed"
  export NL_HOOK_REENTRY=1
  if hook_reentry_should_suppress; then
    ok "suppressed when NL_HOOK_REENTRY=1"
  else
    no "expected suppressed when NL_HOOK_REENTRY=1"
  fi
  unset NL_HOOK_REENTRY

  echo "Scenario 3: NL_HOOK_REENTRY=0 -> not suppressed (explicit off)"
  export NL_HOOK_REENTRY=0
  if hook_reentry_should_suppress; then
    no "expected NOT suppressed when NL_HOOK_REENTRY=0"
  else
    ok "not suppressed when NL_HOOK_REENTRY=0"
  fi
  unset NL_HOOK_REENTRY

  echo "Scenario 4: a stale NL_HOOK_DEPTH env var has NO effect (depth branch deleted per FIX-4)"
  export NL_HOOK_DEPTH=99
  export NL_HOOK_MAX_DEPTH=1
  if hook_reentry_should_suppress; then
    no "expected NOT suppressed — NL_HOOK_DEPTH must no longer be honored (dead branch was removed)"
  else
    ok "NL_HOOK_DEPTH is inert (depth mechanism deleted; only NL_HOOK_REENTRY fires)"
  fi
  unset NL_HOOK_DEPTH NL_HOOK_MAX_DEPTH

  echo "Scenario 5: hook_reentry_reason echoes empty string when not suppressed"
  unset NL_HOOK_REENTRY
  r="$(hook_reentry_reason)"
  if [[ -z "$r" ]]; then
    ok "reason is empty when not suppressed"
  else
    no "expected empty reason, got: $r"
  fi

  echo "Scenario 6: hook_reentry_reason names NL_HOOK_REENTRY when that's the trigger"
  export NL_HOOK_REENTRY=1
  r="$(hook_reentry_reason)"
  if [[ "$r" == *"NL_HOOK_REENTRY"* ]]; then
    ok "reason names NL_HOOK_REENTRY (got: $r)"
  else
    no "expected reason to mention NL_HOOK_REENTRY, got: $r"
  fi
  unset NL_HOOK_REENTRY

  echo "Scenario 7: hook_reentry_note is best-effort and never fails even without ledger_emit"
  unset -f ledger_emit 2>/dev/null
  export NL_HOOK_REENTRY=1
  if hook_reentry_note "test-hook"; then
    ok "hook_reentry_note returns 0 even with no ledger_emit defined"
  else
    no "hook_reentry_note should never fail the caller"
  fi
  unset NL_HOOK_REENTRY

  echo "Scenario 8: hook_reentry_note calls ledger_emit when available"
  LEDGER_CALLS_FILE="$(mktemp 2>/dev/null || printf '/tmp/hrg-selftest-%s' "$$")"
  ledger_emit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$LEDGER_CALLS_FILE"; }
  export NL_HOOK_REENTRY=1
  hook_reentry_note "my-test-hook"
  if [[ -f "$LEDGER_CALLS_FILE" ]] && grep -q '^my-test-hook|reentry-suppressed|' "$LEDGER_CALLS_FILE" 2>/dev/null; then
    ok "hook_reentry_note calls ledger_emit with (hook, reentry-suppressed, reason)"
  else
    no "expected a ledger_emit call recorded; got: $(cat "$LEDGER_CALLS_FILE" 2>/dev/null)"
  fi
  unset -f ledger_emit
  rm -f "$LEDGER_CALLS_FILE" 2>/dev/null
  unset NL_HOOK_REENTRY

  echo "Scenario 9: hook_reentry_export_for_child echoes the canonical assignment"
  r="$(hook_reentry_export_for_child)"
  if [[ "$r" == "NL_HOOK_REENTRY=1" ]]; then
    ok "hook_reentry_export_for_child echoes NL_HOOK_REENTRY=1"
  else
    no "expected 'NL_HOOK_REENTRY=1', got: $r"
  fi

  echo "Scenario 10: source-guard prevents double-definition side effects (re-sourcing is a no-op)"
  _before="$_HOOK_REENTRY_GUARD_SOURCED"
  # shellcheck disable=SC1090
  source "${BASH_SOURCE[0]}"
  if [[ "$_HOOK_REENTRY_GUARD_SOURCED" == "$_before" ]]; then
    ok "re-sourcing does not change the source-guard sentinel"
  else
    no "re-sourcing unexpectedly changed sentinel"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi
