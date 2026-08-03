#!/bin/bash
# dispatch-chain-gate.sh — G2 (plan -> build), THE SKELETON (gated-pipeline-
# master-2026-08 Task 1; docs/plans/gated-pipeline-master-2026-08.md Task 1;
# design docs/designs/gated-pipeline-master-2026-08-03.md §4, REQ-B8 skeleton
# leg — the FULL G2 (subagent_type-keyed PreToolUse trigger, grandfather list,
# the three-variant D-15 acceptance-bar demo) is Task 17, NOT this file yet).
#
# ============================================================
# WHAT THIS FILE IS RIGHT NOW (Task 1 scope — read this before extending it)
# ============================================================
# This task ships ONLY a `--check <plan-file>` pre-flight entry point and a
# `--self-test`, proving the chain lib -> gate wiring end-to-end on fixtures.
# There is deliberately NO PreToolUse wiring in `settings.json.template` yet,
# NO `subagent_type` trigger logic, and NO grandfather-slug-list handling —
# all three are Task 17's job (REQ-B8's full form + the D-15 three-variant
# demo: chain-less new plan BLOCKED, no-attribution dispatch still BLOCKED,
# a chain naming a never-dispatched reviewer fails validity). Building those
# here would be exactly the "component exists before its wiring is proven"
# failure this whole design exists to prevent — the walking-skeleton
# discipline says prove `--check` decides correctly on real fixtures FIRST.
#
# ============================================================
# THE CONTRACT
# ============================================================
#   dispatch-chain-gate.sh --check <plan-file>
#     Validates <plan-file>'s `## Review Chain` block via
#     hooks/lib/review-chain-lib.sh's rc_validate_chain (the ONE validity
#     oracle, REQ-B6 — this gate owns no parsing of its own).
#     RC_VERDICT == FAIL  -> prints a {WHAT/WHY/FIX/ESCAPE} block via
#                             lib/gate-contract-lib.sh's gc_block, exit 1.
#     RC_VERDICT == WARN  -> prints the WARN detail (never blocks), exit 0.
#     RC_VERDICT == PASS  -> prints a one-line confirmation, exit 0.
#   dispatch-chain-gate.sh --self-test
#     Exercises both fixtures under tests/fixtures/review-chain/: the
#     chain-less plan (must BLOCK, all four gc_block fields present) and the
#     valid-chain plan (must pass, exit 0).
#
# Exit codes: 0 = proceed (PASS or WARN), 1 = blocked (--check "would-block"
# reading, per gc_exit_code's check-mode contract — see lib/gate-contract-lib.sh),
# 2 = usage error, 3 = --self-test failure.

_dcg_dir="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
# shellcheck source=./lib/review-chain-lib.sh
source "$_dcg_dir/lib/review-chain-lib.sh"
# shellcheck source=./lib/gate-contract-lib.sh
source "$_dcg_dir/lib/gate-contract-lib.sh"

# _dcg_check <plan-file> — runs rc_validate_chain and prints the gate's
# decision (gc_block on FAIL, a summary line otherwise). Return code is a
# plain proceed/block boolean (0 proceed — PASS or WARN, 1 block — FAIL); the
# caller maps a block through gc_exit_code for the actual process exit code,
# matching every other retrofitted gate's check/enforce convention. NEVER
# call gc_exit_code on the proceed path — its "check" branch unconditionally
# reports 1 (see lib/gate-contract-lib.sh: "check always reports 1 for
# would-block"), which is only correct for the block path.
_dcg_check() {
  local plan="$1" mode
  mode="$(gc_mode --check)"

  if [[ ! -f "$plan" ]]; then
    echo "$(gc_header 'dispatch-chain-gate: plan file not found' "$mode")" >&2
    gc_block \
      "no such file: $plan" \
      "G2 validates a plan's Review Chain block; the named file does not exist so there is nothing to validate" \
      "pass the plan's real path (relative to the repo root or absolute)" \
      "none — this is a usage error, not a chain-validity decision" \
      >&2
    return 1
  fi

  rc_validate_chain "$plan"

  if [[ "$RC_VERDICT" == "FAIL" ]]; then
    local what why fix escape
    if [[ "$RC_REASON" == "no ## Review Chain section"* ]]; then
      what="$plan has no ## Review Chain block"
      why="G2 (plan -> build) requires mechanical proof the design/plan reviews ran before a builder dispatches against this plan (D-15's acceptance bar; design docs/designs/gated-pipeline-master-2026-08-03.md §4)"
      fix="dispatch the required reviewers (plan-fidelity-reviewer at minimum; design-author's reviewers too if design-ref is required), then add a ## Review Chain block naming each reviewer/verdict/record — schema in design §4"
      escape="none for a new plan — a legacy plan predating this gate is exempted only via the install-generated grandfather slug list (Task 17), never by this flag"
    else
      what="$plan's Review Chain fails validity: $RC_REASON"
      why="review-chain-lib.sh's rc_validate_chain found at least one entry that does not satisfy the three validity rules (record parse / three-way anchor match / dispatch-ledger cross-check) — design §4"
      fix="re-dispatch the named reviewer against the current bytes and commit its record (rule 1/3), or restore the chain's anchor to a blob a real record actually attests (rule 2) — see the full detail below"
      escape="none — a chain entry that fails validity cannot be waived by editing the plan file; escalate to the plan's owner"
    fi
    echo "$(gc_header 'dispatch-chain-gate: Review Chain validation failed' "$mode")" >&2
    gc_block "$what" "$why" "$fix" "$escape" >&2
    echo "-- detail --" >&2
    printf '%s\n' "${RC_DETAIL_LINES[@]}" >&2
    return 1
  fi

  if [[ "$RC_VERDICT" == "WARN" ]]; then
    echo "dispatch-chain-gate: $plan — Review Chain WARN (proceeding): $RC_REASON" >&2
    printf '%s\n' "${RC_DETAIL_LINES[@]}" >&2
  else
    echo "dispatch-chain-gate: $plan — Review Chain valid, all entries PASS" >&2
  fi
  return 0
}

_dcg_usage() {
  cat >&2 <<'EOF'
usage: dispatch-chain-gate.sh --check <plan-file>
       dispatch-chain-gate.sh --self-test

Task 1 skeleton only — no PreToolUse enforce mode yet (Task 17).
EOF
}

# ============================================================
# --self-test (direct-execution guard, same convention as review-chain-lib.sh
# / gate-contract-lib.sh).
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  FIXDIR="$_dcg_dir/../tests/fixtures/review-chain"
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

  if [[ ! -f "$FIXDIR/chainless-plan.md" || ! -f "$FIXDIR/valid-chain-plan.md" ]]; then
    echo "self-test: fixtures missing under $FIXDIR (expected chainless-plan.md + valid-chain-plan.md)" >&2
    exit 3
  fi

  OUT="$(bash "$0" --check "$FIXDIR/chainless-plan.md" 2>&1)"
  RC=$?
  _st "chainless-exit-nonzero" "1" "$RC"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    C=$(printf '%s\n' "$OUT" | grep -c -F "$marker")
    _st "chainless-has-$marker" "1" "$C"
  done

  # Run from the repo root so the fixture's own committed HEAD blobs and
  # ledger-fixture-relative paths resolve exactly as they will for a real
  # invocation (dispatch-chain-gate.sh --check is always run with cwd = repo
  # root by its caller — the hook/session convention, not a self-test-only
  # assumption).
  REPO_ROOT="$(cd -- "$_dcg_dir/../../.." 2>/dev/null && pwd)"
  RC_LEDGER_PATH="$FIXDIR/dispatch-ledger.jsonl"
  export RC_LEDGER_PATH
  OUT="$(cd "$REPO_ROOT" && RC_LEDGER_PATH="$REPO_ROOT/adapters/claude-code/tests/fixtures/review-chain/dispatch-ledger.jsonl" bash "$_dcg_dir/dispatch-chain-gate.sh" --check "adapters/claude-code/tests/fixtures/review-chain/valid-chain-plan.md" 2>&1)"
  RC=$?
  _st "valid-chain-exit-zero" "0" "$RC"

  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# CLI dispatch (direct-execution guard — sourcing this file for its functions
# is not a supported use, unlike the libs; this is a gate entry point).
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --check)
      [[ -n "${2:-}" ]] || { _dcg_usage; exit 2; }
      if _dcg_check "$2"; then
        exit 0
      else
        mode="$(gc_mode --check)"
        exit "$(gc_exit_code "$mode" 2)"
      fi
      ;;
    *)
      _dcg_usage
      exit 2
      ;;
  esac
fi
