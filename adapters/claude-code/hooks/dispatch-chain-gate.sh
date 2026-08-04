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

# ============================================================================
# --- T25 verify-obligation WIP-limit ---
# (gated-pipeline-master-2026-08 Task 25; operator directive 2026-08-03 /
# OD-022. design r3 is NOT amended for this — the frozen-flip clause was not
# triggered; see the plan's own In-flight scope-updates entry for Task 25.)
#
# APPENDED, SELF-CONTAINED ON PURPOSE: Task 17 is concurrently landing G2's
# live PreToolUse enforcement + subagent_type triggering in THIS SAME FILE
# (see the file-header comment above: "the FULL G2 ... is Task 17"). To
# minimize merge conflict with that in-flight work, this block is
# deliberately NOT interleaved into `_dcg_check` or the existing CLI `case`
# statement below — it intercepts its OWN flag before the file's
# pre-existing dispatch logic ever sees it, and calls a function that lives
# on the LEDGER LIB side (review-chain-lib.sh's rc_wip_limit_decision, added
# the same commit as this block — reuses the SAME dispatch-ledger reader
# rule 3 already consumes, per the M-3 "no second implementation" rule)
# rather than re-parsing the ledger here. When Task 17 wires the live
# subagent_type-keyed PreToolUse trigger, its own consult path can call
# `_dcg_check_wip_limit` (defined below) directly — no further edit to this
# block should be needed.
#
# CONTRACT: dispatch-chain-gate.sh --check-wip-limit <plan-file>
#   [--threshold N] [--waive <reason>]
#   Exit 0 (proceed) unless the plan's open verify-obligation count is >=
#   threshold (default 3) AND no verifier dispatch is in flight — see
#   rc_wip_limit_decision's own header (hooks/lib/review-chain-lib.sh) for
#   the full decision. `--waive <reason>` always proceeds (exit 0) but
#   LEDGERS the escape via gate-contract-lib.sh's gc_escape_used (the SAME
#   workaround-sensor ledger every other gate's named-reason waiver already
#   feeds — Task 5's dashboard friction pane reads it), never a silent skip.
#
# EXPECTED FALSE-POSITIVE RATE (constitution §10 calibration requirement):
# near-zero BY CONSTRUCTION for a legitimate parallel wave — obligations
# only count as blocking when NO verifier is in flight, so a session
# actively working the verify backlog (dispatching task-verifier while more
# builders land) never trips this. The remaining FP surface is a plan whose
# task-verifier dispatches never carry a role=verifier NL-ATTRIBUTION header
# (silently degrades the in-flight check to "never in flight", which makes
# the gate STRICTER, never looser — a false BLOCK is recoverable via
# --waive, so this direction of error is the one accepted). Calibrated
# against THIS session's own timeline (docs/plans/gated-pipeline-master-
# 2026-08-evidence.md Task 25): 11 builder-complete rows landed with 0
# verifier-complete rows over several hours before the operator's directive
# — a threshold of 3 would have fired once, long before 11 accumulated.
#
# RETIREMENT CONDITION: retire this block once Stage-2 auto-dispatch
# (design NON-GOALS / REQ-C6, Task 24's admission trigger) supersedes manual
# builder-dispatch WIP management entirely — at that point an orchestrator
# session never accumulates unverified merges to begin with, and this
# consult becomes a dead check on an unreachable state.
# ============================================================================

# _dcg_wip_ledger_escape <plan-slug> <reason> — records a --waive escape via
# the canonical gc_escape_used ledger (never a bespoke ledger file).
_dcg_wip_ledger_escape() {
  local slug="$1" reason="$2"
  gc_escape_used "dispatch-chain-gate-wip-limit" "waiver" "$slug" "$reason" 2>/dev/null || true
}

# _dcg_check_wip_limit <plan-file> [<threshold>] [<waive-reason>] — the WIP-
# limit decision, callable directly by a sourcing caller (e.g. a future
# Task 17 PreToolUse consult) or via the --check-wip-limit CLI entry point
# below. Prints a gc_block (FIX/ESCAPE fields included) on block, a summary
# line otherwise. Return code: 0 proceed, 1 block (same convention as
# _dcg_check).
_dcg_check_wip_limit() {
  local plan="$1" threshold="${2:-3}" waive="${3:-}"
  local slug; slug="$(basename "$plan" .md)"

  if [[ -n "$waive" ]]; then
    _dcg_wip_ledger_escape "$slug" "$waive"
    echo "dispatch-chain-gate --check-wip-limit: $plan -- WAIVED ($waive), ledgered to the workaround-sensor ledger, proceeding" >&2
    return 0
  fi

  rc_wip_limit_decision "$slug" "$threshold"
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "dispatch-chain-gate --check-wip-limit: $plan -- $RC_WIP_REASON" >&2
    return 0
  fi

  local tasks_csv=""
  [[ "${#RC_OPEN_OBLIGATIONS[@]}" -gt 0 ]] && tasks_csv="$(IFS=,; echo "${RC_OPEN_OBLIGATIONS[*]}")"
  gc_block \
    "plan '$slug' has ${RC_OPEN_OBLIGATIONS_COUNT} open verify obligation(s) (tasks: $tasks_csv) with no verifier dispatch in flight" \
    "OD-022 (operator directive 2026-08-03): the build->verified transition is mechanical and present-moment -- unverified builder-complete work must not accumulate past $threshold open task(s) on one plan without active verification" \
    "dispatch task-verifier against the open task(s) above before dispatching another builder on this plan, or verify the oldest open tasks first to drop below $threshold" \
    "re-run with --waive '<reason>' to proceed anyway (ledgered to the workaround-sensor ledger via gc_escape_used, named reason required)" \
    >&2
  return 1
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--check-wip-limit" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "usage: dispatch-chain-gate.sh --check-wip-limit <plan-file> [--threshold N] [--waive <reason>]" >&2
    exit 2
  fi
  _dcg_wl_plan="$2"; shift 2
  _dcg_wl_threshold=3
  _dcg_wl_waive=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold) _dcg_wl_threshold="${2:-3}"; shift 2 ;;
      --waive) _dcg_wl_waive="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if _dcg_check_wip_limit "$_dcg_wl_plan" "$_dcg_wl_threshold" "$_dcg_wl_waive"; then
    exit 0
  else
    exit 1
  fi
fi

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test-wip-limit" ]]; then
  # Run ALONGSIDE the existing --self-test (not merged into it) — see the
  # block header above for why (T17 conflict minimization). A full
  # verification pass for this file runs BOTH:
  #   bash dispatch-chain-gate.sh --self-test
  #   bash dispatch-chain-gate.sh --self-test-wip-limit
  WL_PASSED=0
  WL_FAILED=0
  _wlst() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test-wip-limit ($1): PASS" >&2
      WL_PASSED=$((WL_PASSED + 1))
    else
      echo "self-test-wip-limit ($1): FAIL (expected '$2', got '$3')" >&2
      WL_FAILED=$((WL_FAILED + 1))
    fi
  }

  WLT="$(mktemp -d)" || { echo "self-test-wip-limit: mktemp failed" >&2; exit 3; }
  trap 'rm -rf "$WLT" 2>/dev/null || true' EXIT
  WL_LEDGER="$WLT/ledger.jsonl"
  WL_PLAN="$WLT/docs-plans/wip-fixture.md"
  mkdir -p "$(dirname "$WL_PLAN")"
  echo "# WIP fixture plan" > "$WL_PLAN"
  export RC_LEDGER_PATH="$WL_LEDGER"
  export DISPATCH_PROVENANCE_STATE_DIR="$WLT/dispatch-provenance"
  mkdir -p "$DISPATCH_PROVENANCE_STATE_DIR"

  _wl_row() { # <subagent_type> <ts> <task_id>
    printf '{"subagent_type":"%s","model":"claude-fable-5","ts":%s,"session_id":"selftest","artifact_ref":"docs/plans/wip-fixture.md","task_id":"%s"}\n' \
      "$1" "$2" "$3" >> "$WL_LEDGER"
  }

  # ---- GOLDEN SCENARIO (§10 evidence bar item 1): 3 builder-complete rows,
  # no verifier rows -> BLOCKS a 4th builder dispatch, naming the open
  # obligations. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "5"
  _wl_row "plan-phase-builder" 1001 "6"
  _wl_row "plan-phase-builder" 1002 "7"
  WL_OUT="$(bash "$0" --check-wip-limit "$WL_PLAN" 2>&1)"
  WL_RC=$?
  _wlst "golden-3-open-no-verifier-blocks-exit1" "1" "$WL_RC"
  WL_NAMES_ALL=1
  for t in 5 6 7; do printf '%s' "$WL_OUT" | grep -q "$t" || WL_NAMES_ALL=0; done
  _wlst "golden-block-names-all-open-tasks" "1" "$WL_NAMES_ALL"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    WL_MC=$(printf '%s' "$WL_OUT" | grep -c -F "$marker")
    _wlst "golden-block-has-$marker" "1" "$WL_MC"
  done

  # ---- GOLDEN SCENARIO continued: add verifier rows for each open task ->
  # dispatch passes (exit 0). ----
  _wl_row "task-verifier" 2000 "5"
  _wl_row "task-verifier" 2001 "6"
  _wl_row "task-verifier" 2002 "7"
  WL_OUT2="$(bash "$0" --check-wip-limit "$WL_PLAN" 2>&1)"
  WL_RC2=$?
  _wlst "golden-after-verify-rows-passes-exit0" "0" "$WL_RC2"

  # ---- Below-threshold (2 open, default threshold 3) -> proceeds. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "1"
  _wl_row "plan-phase-builder" 1001 "2"
  bash "$0" --check-wip-limit "$WL_PLAN" >/dev/null 2>&1
  _wlst "below-threshold-proceeds-exit0" "0" "$?"

  # ---- --waive always proceeds and ledgers the escape. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "1"
  _wl_row "plan-phase-builder" 1001 "2"
  _wl_row "plan-phase-builder" 1002 "3"
  export HARNESS_SELFTEST=1
  export WORKAROUND_SENSOR_LEDGER_PATH="$WLT/workaround-ledger.jsonl"
  bash "$0" --check-wip-limit "$WL_PLAN" --waive "operator-approved parallel wave" >/dev/null 2>&1
  _wlst "waive-proceeds-exit0" "0" "$?"
  WL_WAIVED=0
  grep -q '"bypass_kind":"waiver"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null && WL_WAIVED=1
  _wlst "waive-ledgered-to-workaround-sensor" "1" "$WL_WAIVED"
  unset WORKAROUND_SENSOR_LEDGER_PATH HARNESS_SELFTEST

  echo "self-test-wip-limit summary: $WL_PASSED passed, $WL_FAILED failed (of $((WL_PASSED + WL_FAILED)) scenarios)" >&2
  if [[ "$WL_FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
# --- end T25 verify-obligation WIP-limit block ---
# ============================================================================

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
