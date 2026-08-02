#!/bin/bash
# gate-contract-lib.sh — Gate Philosophy Law retrofit (R3.4,
# docs/designs/harness-execution-redesign-considerations-2026-08-02.md
# "Round 3 revamp" section; build plan
# docs/plans/harness-execution-redesign-2026-08.md Task 2).
#
# ONE shared emitter for the structured block-message fields {WHAT fired,
# WHY, exact FIX command/path, sanctioned ESCAPE with its cost} plus the
# mode-detection / header / exit-code helpers a gate's SINGLE enforce-path
# decision site and its new `--check` pre-flight entry point both call.
# Because both paths reach the same call with the same values, drift between
# "what the gate enforces" and "what --check reports" is structurally
# impossible — there is one decision, not two that can disagree.
#
# This lib does NOT own a gate's whole block message (header art, per-gate
# prose, the existing self-tested option list). It owns exactly the four
# fields, in a fixed, doctor-lintable format, so a caller wraps it inside
# its own pre-existing, already-self-tested framing — additive, not a
# rewrite of any gate's hard-won message text.
#
# Doctor-lintable convention: every retrofitted gate's block/would-block
# output contains four lines matching, in order of first appearance:
#   [GATE:WHAT] <one line>
#   [GATE:WHY] <one line>
#   [GATE:FIX] <one line — an exact command or path, not "see above">
#   [GATE:ESCAPE] <one line — a sanctioned escape + its cost, or "none — ...">
# A doctor gate-message lint that greps a gate's --check/--self-test output
# for all four markers is named in the plan's Task 2 but is NOT built by
# this task (scope: retrofit exactly scope-enforcement-gate.sh,
# pre-commit-gate.sh, concurrent-ownership-gate.sh) — see this task's build
# report for the explicit deferral.
#
# gc_mode <argv1> — echo "check" iff argv1 is literally --check, else
# "enforce". Call ONCE near a gate's entry point; thread the single result
# through the gate's one decision/block site. Re-deriving the mode at
# multiple call sites is exactly the drift class this lib exists to prevent.
gc_mode() {
  if [[ "${1:-}" == "--check" ]]; then
    echo "check"
  else
    echo "enforce"
  fi
}

# gc_block <what> <why> <fix> <escape> — prints the four structured
# fields to stdout in the fixed [GATE:*] format (caller redirects to stderr
# as part of its own message block, matching how every retrofitted gate
# already emits its human-readable message).
gc_block() {
  local what="$1" why="$2" fix="$3" escape="$4"
  echo "[GATE:WHAT] $what"
  echo "[GATE:WHY] $why"
  echo "[GATE:FIX] $fix"
  echo "[GATE:ESCAPE] $escape"
}

# gc_header <existing-title> <mode> — the enforce path's title text is
# returned byte-for-byte unchanged (every retrofitted gate's self-test
# greps for its existing title/option text; this must never perturb it).
# The check path gets a mode-distinguishing suffix so a --check transcript
# is never mistaken for a real enforcement block.
gc_header() {
  local title="$1" mode="$2"
  if [[ "$mode" == "check" ]]; then
    echo "${title} — WOULD BLOCK (--check pre-flight, not enforced)"
  else
    echo "$title"
  fi
}

# gc_exit_code <mode> <enforce-exit-code> — enforce keeps the gate's own
# pre-existing exit code EXACTLY (2 for scope-enforcement-gate.sh and
# concurrent-ownership-gate.sh, 1 for pre-commit-gate.sh) — zero change to
# any existing block-semantics oracle. check always reports 1 for
# would-block, uniformly across every retrofitted gate, regardless of what
# that gate's own enforce-mode code happens to be — one convention an agent
# can rely on without knowing each gate's native exit code.
gc_exit_code() {
  local mode="$1" enforce_code="$2"
  if [[ "$mode" == "check" ]]; then
    echo 1
  else
    echo "$enforce_code"
  fi
}

# ============================================================
# --self-test (direct-execution guard — same convention as
# lib/waiver-purpose-clause.sh and lib/signal-ledger.sh: only runs when this
# file is executed directly, never when sourced by a gate).
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  _st() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test ($1): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test ($1): FAIL (expected '$2', got '$3')" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  _st "mode-default-is-enforce" "enforce" "$(gc_mode "")"
  _st "mode-other-flag-is-enforce" "enforce" "$(gc_mode "--self-test")"
  _st "mode-check-flag-detected" "check" "$(gc_mode "--check")"

  FIELDS_OUT=$(gc_block "what-x" "why-x" "fix-x" "escape-x")
  _st "fields-what-marker" "1" "$(printf '%s\n' "$FIELDS_OUT" | grep -c '^\[GATE:WHAT\] what-x$')"
  _st "fields-why-marker" "1" "$(printf '%s\n' "$FIELDS_OUT" | grep -c '^\[GATE:WHY\] why-x$')"
  _st "fields-fix-marker" "1" "$(printf '%s\n' "$FIELDS_OUT" | grep -c '^\[GATE:FIX\] fix-x$')"
  _st "fields-escape-marker" "1" "$(printf '%s\n' "$FIELDS_OUT" | grep -c '^\[GATE:ESCAPE\] escape-x$')"
  _st "fields-line-count" "4" "$(printf '%s\n' "$FIELDS_OUT" | grep -c '^\[GATE:')"

  _st "header-enforce-byte-identical" "TITLE TEXT" "$(gc_header "TITLE TEXT" "enforce")"
  _st "header-check-suffixed" "TITLE TEXT — WOULD BLOCK (--check pre-flight, not enforced)" "$(gc_header "TITLE TEXT" "check")"

  _st "exit-enforce-passthrough-2" "2" "$(gc_exit_code "enforce" "2")"
  _st "exit-enforce-passthrough-1" "1" "$(gc_exit_code "enforce" "1")"
  _st "exit-check-always-1-from-2" "1" "$(gc_exit_code "check" "2")"
  _st "exit-check-always-1-from-1" "1" "$(gc_exit_code "check" "1")"

  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
