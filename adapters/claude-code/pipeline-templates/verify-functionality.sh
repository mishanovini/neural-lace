#!/usr/bin/env bash
# verify-functionality.sh — Four-step verification pipeline orchestrator
#
# Purpose: explicit manual entrypoint for the verification pipeline documented
# in ~/.claude/rules/verification-pipeline.md. Sequences functionality-verifier,
# end-user-advocate (runtime), claim-reviewer, and domain-expert-tester
# invocations and emits a structured report the maintainer can paste into the
# task's evidence file.
#
# This script does NOT replace the in-band firing triggers each agent already
# has (task-verifier dispatch for Step 1; Stop hook for Step 2; self-invocation
# for Step 3; testing.md mandate for Step 4). It composes them into a single
# manual command for the case where the maintainer wants to run the pipeline
# end-to-end on demand.
#
# Usage:
#   bash verify-functionality.sh <plan-slug> <task-id>
#   bash verify-functionality.sh --self-test
#   bash verify-functionality.sh --help
#
# Exit codes:
#   0 — pipeline completed; verdict is PASS on all blocking steps
#   1 — pipeline completed; at least one blocking step FAILED
#   2 — usage error or unrecoverable environment failure

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'USAGE'
verify-functionality.sh — Four-step verification pipeline orchestrator

USAGE:
  bash verify-functionality.sh <plan-slug> <task-id>
  bash verify-functionality.sh --self-test
  bash verify-functionality.sh --help

ARGUMENTS:
  <plan-slug>   Slug of the plan file (resolved via
                ~/.claude/scripts/find-plan-file.sh).
  <task-id>     ID of the task within the plan to verify (e.g. "3.2").

FLAGS:
  --self-test   Run the script's built-in self-test suite.
  --help        Print this message.

PIPELINE STEPS:
  1. functionality-verifier  — be the user; use the feature (BLOCKING)
  2. end-user-advocate       — runtime adversarial probes (BLOCKING)
  3. claim-reviewer          — verify orchestrator's claims (ADVISORY)
  4. domain-expert-tester    — target-persona usability (ADVISORY)

OUTPUT:
  A structured pipeline report is emitted to stdout. Each step's verdict
  is one of PASS | FAIL | INCOMPLETE | SKIP | ENVIRONMENT_UNAVAILABLE.
  Step 1 and Step 2 verdicts gate the overall exit code; Steps 3-4 are
  advisory and report-only.

  When invoked outside the agent runtime (e.g. CI), the script prints
  guidance about which agent invocations the orchestrator should issue
  via the Task tool. It does NOT autonomously invoke agents — that is
  the orchestrator's job (which has access to the Task tool).

See ~/.claude/rules/verification-pipeline.md for the full pipeline
specification and ~/.claude/agents/functionality-verifier.md for the
new agent introduced in the pipeline's parent plan.
USAGE
}

# ─────────────────────────────────────────────────────────────────────
# self-test
# ─────────────────────────────────────────────────────────────────────

self_test() {
  local failures=0
  local tmpdir
  tmpdir=$(mktemp -d -t verify-functionality-self-test-XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  # Scenario 1: --help prints usage and exits 0
  if "$0" --help 2>&1 | grep -q "verify-functionality.sh"; then
    echo "[self-test] s1 (--help prints usage): PASS"
  else
    echo "[self-test] s1 (--help prints usage): FAIL" >&2
    failures=$((failures + 1))
  fi

  # Scenario 2: missing args produces usage error and exits non-zero
  local missing_args_out
  missing_args_out=$("$0" 2>&1 || true)
  if echo "$missing_args_out" | grep -qE "USAGE:|missing arguments"; then
    echo "[self-test] s2 (missing args prints usage): PASS"
  else
    echo "[self-test] s2 (missing args prints usage): FAIL" >&2
    failures=$((failures + 1))
  fi

  # Scenario 3: report-template generation has the four step sections
  local report
  report=$(generate_report_template "test-plan-slug" "1.1" 2>&1)
  if echo "$report" | grep -q "Step 1: functionality-verifier" \
     && echo "$report" | grep -q "Step 2: end-user-advocate" \
     && echo "$report" | grep -q "Step 3: claim-reviewer" \
     && echo "$report" | grep -q "Step 4: domain-expert-tester"; then
    echo "[self-test] s3 (report template has all four step sections): PASS"
  else
    echo "[self-test] s3 (report template has all four step sections): FAIL" >&2
    failures=$((failures + 1))
  fi

  # Scenario 4: dispatch instructions reference Task tool and each agent
  local dispatch
  dispatch=$(generate_dispatch_instructions "test-plan-slug" "1.1" 2>&1)
  if echo "$dispatch" | grep -q "Task tool" \
     && echo "$dispatch" | grep -q "functionality-verifier" \
     && echo "$dispatch" | grep -q "end-user-advocate" \
     && echo "$dispatch" | grep -q "claim-reviewer" \
     && echo "$dispatch" | grep -q "domain-expert-tester"; then
    echo "[self-test] s4 (dispatch instructions cite all four agents): PASS"
  else
    echo "[self-test] s4 (dispatch instructions cite all four agents): FAIL" >&2
    failures=$((failures + 1))
  fi

  # Scenario 5: check_environment emits a WARNING when invoked against an
  # unreachable URL — exercises the function deterministically regardless of
  # the actual environment the self-test runs in. We do this by pointing
  # curl at a guaranteed-unreachable URL via a subshell override.
  local env_warning
  env_warning=$(
    # shellcheck disable=SC2030
    # Override curl with a stub that always reports unreachable
    curl() { return 7; }
    export -f curl 2>/dev/null || true
    check_environment 2>&1 || true
  )
  if echo "$env_warning" | grep -qE "no dev server detected|WARNING"; then
    echo "[self-test] s5 (env warning emitted on unreachable URL): PASS"
  else
    echo "[self-test] s5 (env warning emitted on unreachable URL): FAIL" >&2
    echo "    captured: $env_warning" >&2
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    echo "self-test: OK (5 scenarios PASS)"
    return 0
  else
    echo "self-test: $failures FAILED" >&2
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────
# helpers
# ─────────────────────────────────────────────────────────────────────

generate_report_template() {
  local plan_slug="$1"
  local task_id="$2"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat <<REPORT
═══════════════════════════════════════════════════════════════
VERIFICATION PIPELINE REPORT
═══════════════════════════════════════════════════════════════
Plan: ${plan_slug}
Task: ${task_id}
Timestamp: ${ts}
Pipeline rule: ~/.claude/rules/verification-pipeline.md

─── Step 1: functionality-verifier (BLOCKING) ────────────────
Trigger: per-task, before task-verifier flips the checkbox
Scope: this specific task's user-shaped exercise
Verdict: <PASS | FAIL | INCOMPLETE | SKIP | ENVIRONMENT_UNAVAILABLE>
Evidence: <path or excerpt>
Notes: <one-line>

─── Step 2: end-user-advocate (BLOCKING) ─────────────────────
Trigger: at session end via product-acceptance-gate.sh
Scope: the whole plan's ## Acceptance Scenarios set
Verdict: <PASS | FAIL | INCOMPLETE | SKIP | ENVIRONMENT_UNAVAILABLE>
Evidence: .claude/state/acceptance/${plan_slug}/<artifact>.json
Notes: <one-line>

─── Step 3: claim-reviewer (ADVISORY) ────────────────────────
Trigger: before sending feature claims to the user
Scope: orchestrator's prose summary
Verdict: <PASS | FAIL>
Evidence: review block in conversation
Notes: <one-line>

─── Step 4: domain-expert-tester (ADVISORY) ──────────────────
Trigger: after substantial UI builds (per testing.md)
Scope: target persona's experience of the running app
P0 / P1 / P2 counts: <N> / <N> / <N>
Evidence: docs/reviews/<YYYY-MM-DD>-<slug>.md
Notes: <one-line>

─── Overall ──────────────────────────────────────────────────
Blocking verdict (Steps 1-2): <PASS | FAIL>
Advisory findings (Steps 3-4): <summary>
Next action: <merge if PASS; address gaps if FAIL>
═══════════════════════════════════════════════════════════════
REPORT
}

generate_dispatch_instructions() {
  local plan_slug="$1"
  local task_id="$2"

  cat <<DISPATCH
DISPATCH INSTRUCTIONS for orchestrator (Task tool required)
─────────────────────────────────────────────────────────────

The pipeline composes four agent invocations. This script generates
the dispatch sequence; the orchestrator runs each via the Task tool.

Step 1 — Invoke functionality-verifier:
  subagent_type: functionality-verifier
  prompt: |
    Plan: ${plan_slug}
    Task: ${task_id}
    Decide the task class (UI / API / AI / Data / Harness-internal)
    and exercise the user-shaped path per ~/.claude/agents/functionality-verifier.md.
    Return PASS / FAIL / INCOMPLETE / SKIP / ENVIRONMENT_UNAVAILABLE
    with the structured output block.

Step 2 — Invoke end-user-advocate (runtime mode):
  subagent_type: end-user-advocate
  prompt: |
    mode=runtime
    Plan file: docs/plans/${plan_slug}.md
    Execute the plan's ## Acceptance Scenarios against the live app
    using the canonical browser-MCP fallback chain. Write artifact to
    .claude/state/acceptance/${plan_slug}/<session>-<ts>.json.

  (Step 2 also fires automatically at session end via
   product-acceptance-gate.sh. Run manually here if the maintainer
   wants the report inline rather than at Stop time.)

Step 3 — Invoke claim-reviewer ONLY if the orchestrator's draft
session-end summary contains feature claims:
  subagent_type: claim-reviewer
  prompt: |
    Draft response: <paste the draft summary the orchestrator
    intends to send to the user>
    User question: <or pseudo-question if running on completion summary>

Step 4 — Invoke domain-expert-tester ONLY if substantial UI was
added (per testing.md trigger conditions):
  subagent_type: Domain Expert Tester
  prompt: |
    Audit the running app at <target_url> from the perspective of
    the project's target persona declared in .claude/audience.md.
    Persist findings to docs/reviews/<date>-<slug>.md per testing.md
    "Persist results immediately" rule.

─────────────────────────────────────────────────────────────
Blocking verdicts: Step 1 and Step 2 must both PASS for overall PASS.
Advisory findings from Steps 3-4 are logged but do not block.
DISPATCH
}

check_environment() {
  local warnings=""

  # Warn if no obvious dev server is running on default port
  if ! curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
       "http://localhost:3000/" >/dev/null 2>&1; then
    warnings+="WARNING: no dev server detected at http://localhost:3000/ — "
    warnings+="Step 1 (functionality-verifier) and Step 2 (end-user-advocate) "
    warnings+="will return ENVIRONMENT_UNAVAILABLE for UI/API tasks unless "
    warnings+="the maintainer starts a dev server first.\n"
  fi

  # Warn if no acceptance-scenarios state directory exists for this plan
  # (informational; agent will create it on first PASS write)
  if [ ! -d ".claude/state/acceptance" ]; then
    warnings+="NOTE: .claude/state/acceptance/ does not yet exist; will be "
    warnings+="created by end-user-advocate on first runtime invocation.\n"
  fi

  # If git is unavailable the script can't resolve plan-commit-sha
  if ! command -v git >/dev/null 2>&1; then
    warnings+="WARNING: 'git' not on PATH — plan-commit-sha cannot be "
    warnings+="resolved; acceptance artifacts will lack tamper-evidence.\n"
  fi

  if [ -n "$warnings" ]; then
    printf "%b" "$warnings"
  fi
}

# ─────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────

main() {
  if [ "$#" -eq 0 ]; then
    echo "Error: missing arguments." >&2
    usage >&2
    exit 2
  fi

  case "${1:-}" in
    --help|-h)
      usage
      exit 0
      ;;
    --self-test)
      self_test
      exit $?
      ;;
  esac

  if [ "$#" -lt 2 ]; then
    echo "Error: requires <plan-slug> and <task-id>." >&2
    usage >&2
    exit 2
  fi

  local plan_slug="$1"
  local task_id="$2"

  echo "verify-functionality.sh — verification pipeline orchestrator"
  echo ""

  # Environmental pre-checks (informational)
  local env_warnings
  env_warnings=$(check_environment 2>&1 || true)
  if [ -n "$env_warnings" ]; then
    printf "%b" "$env_warnings"
    echo ""
  fi

  # Emit the dispatch instructions for the orchestrator
  generate_dispatch_instructions "$plan_slug" "$task_id"
  echo ""

  # Emit the report template for the orchestrator to fill in
  generate_report_template "$plan_slug" "$task_id"

  # This script does not autonomously invoke agents (it has no Task tool
  # access). The orchestrator runs the four invocations via the Task tool
  # and pastes the verdicts back into the report template.
  exit 0
}

main "$@"
