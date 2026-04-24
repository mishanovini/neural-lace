#!/bin/bash
# NEURAL-LACE-ACCEPTANCE-LOOP-SELF-TEST v1
#
# Phase G.1 of docs/plans/end-user-advocate-acceptance-loop.md.
#
# Purpose
# -------
# Synthetic structural + control-flow self-test of the end-user-advocate
# acceptance loop. Verifies that every shipped piece of the loop exists on
# disk, has the required structural elements (sections, fields, sentinel
# strings), and that the underlying hooks pass their own --self-tests.
#
# What this self-test does NOT do
# -------------------------------
# It does NOT invoke the end-user-advocate or enforcement-gap-analyzer
# agents live. Live agent invocation requires Task-tool dispatch from a
# session that has the agent definition loaded into its registry, which in
# turn requires next-session activation after the agent files land. A
# structural self-test that runs synchronously inside any bash shell is
# the right shape for a CI-style sanity check; live end-to-end exercise
# happens via the walking-skeleton plan + its evidence file.
#
# What this self-test does instead
# --------------------------------
# Stage-by-stage structural + control-flow assertions:
#
#   Stage 1 — plan-time advocate stage
#       Asserts: agents/end-user-advocate.md exists, declares plan-time
#       mode in its body, and templates/plan-template.md contains the
#       Acceptance Scenarios section the advocate authors into plans.
#
#   Stage 2 — builder discipline stage (scenarios-shared, assertions-private)
#       Asserts: agents/plan-phase-builder.md and rules/orchestrator-pattern.md
#       contain the Goodhart-resistant discipline language.
#
#   Stage 3 — runtime advocate stage
#       Asserts: agents/end-user-advocate.md declares runtime mode,
#       has the artifact-schema specification, and the
#       product-acceptance-gate.sh hook passes its own --self-test (8
#       scenarios covering the artifact-recognition state machine).
#
#   Stage 4 — gap-analyzer stage
#       Asserts: agents/enforcement-gap-analyzer.md exists, declares the
#       five required output sections (Class of failure / Existing rules /
#       Why current mechanisms missed this / Proposed change / Testing
#       strategy), and has the existing-rule-review-first protocol.
#
#   Stage 5 — harness-reviewer Step 5 stage
#       Asserts: agents/harness-reviewer.md contains the Step 5 extended
#       remit with the five generalization checks, and the PASS /
#       REFORMULATE / REJECT verdict vocabulary.
#
#   Stage 6 — mirror sync
#       Asserts that the harness repo's adapter files are byte-identical
#       to the installed mirror at ~/.claude/. Skipped silently if
#       ~/.claude/ is not present (e.g. running on a clean CI runner).
#
# INVOCATION
#   bash adapters/claude-code/tests/acceptance-loop-self-test.sh
#
# EXIT CODES
#   0 — every stage passed
#   1 — at least one stage failed (structural defect or hook self-test FAIL)
#   2 — usage / environment error (e.g. cannot resolve repo root)
#
# This script is intended to be run by:
#   1. The /harness-review skill weekly (Phase G.2)
#   2. Local dev who suspects a piece of the loop has drifted

set -u

# ============================================================
# Helpers
# ============================================================

# Resolve repo root from script location (works whether run from any cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -d "$REPO_ROOT/adapters/claude-code" ]]; then
  echo "acceptance-loop-self-test: cannot resolve repo root from $SCRIPT_DIR" >&2
  exit 2
fi

ADAPTER="$REPO_ROOT/adapters/claude-code"
INSTALLED="${HOME}/.claude"

PASSED=0
FAILED=0
FAIL_DETAILS=()

stage_ok() {
  local stage="$1"
  local detail="${2:-}"
  PASSED=$((PASSED + 1))
  if [[ -n "$detail" ]]; then
    echo "PASS [${stage}] ${detail}" >&2
  else
    echo "PASS [${stage}]" >&2
  fi
}

stage_fail() {
  local stage="$1"
  local detail="$2"
  FAILED=$((FAILED + 1))
  FAIL_DETAILS+=("[${stage}] ${detail}")
  echo "FAIL [${stage}] ${detail}" >&2
}

# Assert: file exists and contains all of the given regex patterns.
# Usage: assert_contains_all <stage> <file> <pattern1> [pattern2] ...
assert_contains_all() {
  local stage="$1"
  local file="$2"
  shift 2
  if [[ ! -f "$file" ]]; then
    stage_fail "$stage" "missing file: ${file#$REPO_ROOT/}"
    return 1
  fi
  local missing=()
  for pat in "$@"; do
    if ! grep -qE "$pat" "$file"; then
      missing+=("$pat")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    stage_fail "$stage" "${file#$REPO_ROOT/} missing patterns: ${missing[*]}"
    return 1
  fi
  stage_ok "$stage" "${file#$REPO_ROOT/} has all required patterns"
  return 0
}

# ============================================================
# Stage 1 — plan-time advocate
# ============================================================
# Asserts the plan-time mode is documented in the agent body AND the
# plan template has the Acceptance Scenarios + Out-of-scope scenarios
# sections that the advocate authors into plans.

assert_contains_all "stage-1-advocate-plan-time" \
  "$ADAPTER/agents/end-user-advocate.md" \
  '^name: end-user-advocate' \
  'plan-time' \
  '## Acceptance Scenarios'

assert_contains_all "stage-1-template-sections" \
  "$ADAPTER/templates/plan-template.md" \
  '^## Acceptance Scenarios' \
  '^## Out-of-scope scenarios'

# ============================================================
# Stage 2 — builder discipline (scenarios shared, assertions private)
# ============================================================
# Asserts the Goodhart-resistant discipline lives in BOTH the orchestrator
# rule and the builder agent body, and that the cross-references match
# the convention codified in Phase F.

assert_contains_all "stage-2-orchestrator-discipline" \
  "$ADAPTER/rules/orchestrator-pattern.md" \
  '^## Scenarios-shared, assertions-private' \
  '## Acceptance Scenarios' \
  'Goodhart'

assert_contains_all "stage-2-builder-discipline" \
  "$ADAPTER/agents/plan-phase-builder.md" \
  'end-user-advocate will execute these flows' \
  'will not see the exact runtime assertions' \
  'user trying to accomplish them'

# ============================================================
# Stage 3 — runtime advocate + product-acceptance-gate
# ============================================================
# Asserts the runtime mode is documented in the agent body AND the
# product-acceptance-gate hook passes its own 8-scenario --self-test.

assert_contains_all "stage-3-advocate-runtime" \
  "$ADAPTER/agents/end-user-advocate.md" \
  'runtime' \
  'artifact' \
  'plan_commit_sha'

if [[ -x "$ADAPTER/hooks/product-acceptance-gate.sh" ]] || [[ -f "$ADAPTER/hooks/product-acceptance-gate.sh" ]]; then
  gate_out=$(bash "$ADAPTER/hooks/product-acceptance-gate.sh" --self-test 2>&1)
  gate_rc=$?
  if [[ $gate_rc -eq 0 ]] && grep -q '8 passed, 0 failed' <<<"$gate_out"; then
    stage_ok "stage-3-gate-self-test" "product-acceptance-gate.sh --self-test: 8/8 passed"
  else
    summary_line=$(grep -E 'self-test summary' <<<"$gate_out" | head -1)
    [[ -z "$summary_line" ]] && summary_line="(no summary line; rc=$gate_rc)"
    stage_fail "stage-3-gate-self-test" "product-acceptance-gate.sh --self-test failed: $summary_line"
  fi
else
  stage_fail "stage-3-gate-self-test" "missing hook: adapters/claude-code/hooks/product-acceptance-gate.sh"
fi

# ============================================================
# Stage 4 — enforcement-gap-analyzer
# ============================================================
# Asserts the analyzer exists, has the five required output sections,
# and codifies the existing-rule-review-first discipline.

assert_contains_all "stage-4-analyzer-sections" \
  "$ADAPTER/agents/enforcement-gap-analyzer.md" \
  '^name: enforcement-gap-analyzer' \
  'Class of failure' \
  'Existing rules' \
  'Why current mechanisms missed this' \
  'Proposed change' \
  'Testing strategy'

assert_contains_all "stage-4-analyzer-discipline" \
  "$ADAPTER/agents/enforcement-gap-analyzer.md" \
  'review existing rules' \
  'AMENDMENT' \
  'sibling'

# ============================================================
# Stage 5 — harness-reviewer Step 5 generalization checks
# ============================================================
# Asserts the reviewer's extended remit is present and that the
# Step 5 verdict vocabulary is documented.

assert_contains_all "stage-5-reviewer-step5" \
  "$ADAPTER/agents/harness-reviewer.md" \
  'Step 5' \
  'enforcement-gap' \
  'generalization' \
  'PASS / REFORMULATE / REJECT'

# ============================================================
# Stage 6 — mirror sync (informational; skipped if not installed)
# ============================================================
# Asserts the installed harness mirror at ~/.claude/ matches the repo
# for the load-bearing files in the acceptance loop. Skipped silently
# if ~/.claude/ does not exist (e.g. fresh CI environment).

if [[ -d "$INSTALLED" ]]; then
  mirror_targets=(
    "agents/end-user-advocate.md"
    "agents/enforcement-gap-analyzer.md"
    "agents/harness-reviewer.md"
    "agents/plan-phase-builder.md"
    "rules/orchestrator-pattern.md"
    "rules/acceptance-scenarios.md"
    "hooks/product-acceptance-gate.sh"
    "templates/plan-template.md"
  )
  mirror_drift=()
  for rel in "${mirror_targets[@]}"; do
    repo_file="$ADAPTER/$rel"
    inst_file="$INSTALLED/$rel"
    if [[ ! -f "$repo_file" ]]; then
      mirror_drift+=("missing-in-repo: $rel")
      continue
    fi
    if [[ ! -f "$inst_file" ]]; then
      mirror_drift+=("missing-in-install: $rel")
      continue
    fi
    if ! diff -q "$repo_file" "$inst_file" >/dev/null 2>&1; then
      mirror_drift+=("differs: $rel")
    fi
  done
  if [[ ${#mirror_drift[@]} -eq 0 ]]; then
    stage_ok "stage-6-mirror-sync" "all ${#mirror_targets[@]} acceptance-loop files match ~/.claude/ mirror"
  else
    stage_fail "stage-6-mirror-sync" "drift: ${mirror_drift[*]}"
  fi
else
  echo "SKIP [stage-6-mirror-sync] ~/.claude/ not present" >&2
fi

# ============================================================
# Summary
# ============================================================

echo "" >&2
echo "acceptance-loop-self-test summary: $PASSED passed, $FAILED failed" >&2
if [[ $FAILED -gt 0 ]]; then
  echo "" >&2
  echo "Failures:" >&2
  for d in "${FAIL_DETAILS[@]}"; do
    echo "  - $d" >&2
  done
  exit 1
fi
exit 0
