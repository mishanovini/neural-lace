#!/bin/bash
# plan-reviewer.sh — Generation 4
#
# Adversarial review of plan files via bash/grep checks. Runs from a
# PreToolUse hook on Write/Edit of docs/plans/*.md files that create
# new plans or mark plans ACTIVE. Catches the specific failure modes
# the adversarial harness review identified:
#
#   - Undecomposed sweep tasks ("all forms", "every page", "throughout")
#   - Tasks without explicit test specs or Runtime verification entries
#   - "Verify manually" / "in browser by hand" language in acceptance
#   - Missing Scope section
#   - Missing Definition of Done
#
# Unlike the plan-reviewer agent prompt, this is a bash script that
# actually runs. It's grep-based — not as nuanced as a language model
# but its failure conditions are objective and it fires automatically.
#
# Exit codes:
#   0 — plan passes mechanical review
#   1 — plan has findings; stderr lists them (blocking)
#   2 — input error

set -u

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <plan-file>" >&2
  exit 2
fi

PLAN_FILE="$1"
if [[ ! -f "$PLAN_FILE" ]]; then
  echo "plan-reviewer: file not found: $PLAN_FILE" >&2
  exit 2
fi

# Only review active-status plans (or newly created plans where Status
# hasn't been set yet)
STATUS=$(grep -oP '(?<=^Status:\s)\w+' "$PLAN_FILE" 2>/dev/null | head -1 || echo "")
if [[ "$STATUS" == "COMPLETED" || "$STATUS" == "ABANDONED" || "$STATUS" == "DEFERRED" ]]; then
  # Finalized plans don't need adversarial review
  exit 0
fi

FINDINGS=""
FINDING_COUNT=0

add_finding() {
  FINDINGS+="  * $1"$'\n'
  FINDING_COUNT=$((FINDING_COUNT + 1))
}

# ============================================================
# Check 1: Undecomposed sweep tasks
# ============================================================
#
# Look for task lines that use plural language without per-file decomp.
# "All", "every", "throughout", "across" followed by a bare task description
# (no sub-items listed) is a sweep.

SWEEP_LINES=$(grep -nE '^- \[[ xX]\]\s+.*(all\s+\w+|every\s+\w+|throughout|across\s+the\s+codebase|in\s+every)' "$PLAN_FILE" 2>/dev/null || true)
if [[ -n "$SWEEP_LINES" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract the line number and task text
    ln=$(echo "$line" | cut -d: -f1)
    # Check if the next few lines have sub-items (indented checkboxes)
    has_sub_items=$(sed -n "$((ln+1)),$((ln+10))p" "$PLAN_FILE" | grep -cE '^\s+- \[[ xX]\]' || echo "0")
    has_sub_items=$(echo "$has_sub_items" | tr -d '[:space:]')
    if [[ "$has_sub_items" -eq 0 ]]; then
      add_finding "Check 1 (undecomposed sweep): line $ln has sweep language without per-file sub-items — \"$(echo "$line" | cut -d: -f2- | head -c 100)\""
    fi
  done <<< "$SWEEP_LINES"
fi

# ============================================================
# Check 2: Manual verification language
# ============================================================

MANUAL_LINES=$(grep -niE 'verify\s+manually|by\s+hand|in\s+browser\s+by\s+hand|manual\s+(test|verification|check)' "$PLAN_FILE" 2>/dev/null || true)
if [[ -n "$MANUAL_LINES" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ln=$(echo "$line" | cut -d: -f1)
    add_finding "Check 2 (manual verification): line $ln uses banned manual-verification language — \"$(echo "$line" | cut -d: -f2- | head -c 100)\""
  done <<< "$MANUAL_LINES"
fi

# ============================================================
# Check 3: Missing Scope section
# ============================================================

if ! grep -qE '^## Scope' "$PLAN_FILE" 2>/dev/null; then
  add_finding "Check 3: missing '## Scope' section"
else
  # Must have both IN and OUT
  if ! grep -qiE '(^\s*-\s*\*\*IN\*\*|^\s*\*\*IN\*\*)' "$PLAN_FILE" 2>/dev/null && ! grep -qiE '\bIN:' "$PLAN_FILE" 2>/dev/null; then
    add_finding "Check 3: Scope section missing 'IN' clause"
  fi
  if ! grep -qiE '(^\s*-\s*\*\*OUT\*\*|^\s*\*\*OUT\*\*)' "$PLAN_FILE" 2>/dev/null && ! grep -qiE '\bOUT:' "$PLAN_FILE" 2>/dev/null; then
    add_finding "Check 3: Scope section missing 'OUT' clause (explicit exclusions)"
  fi
fi

# ============================================================
# Check 4: Missing Definition of Done
# ============================================================

if ! grep -qiE '^## Definition of Done|^## Done When|^## Acceptance' "$PLAN_FILE" 2>/dev/null; then
  add_finding "Check 4: missing '## Definition of Done' section"
fi

# ============================================================
# Check 4b: Walking-skeleton section (integration-vaporware defense)
# ============================================================
#
# Research-backed rule (2026-04-21, see docs/reviews/2026-04-20-integration-vaporware-research.md
# in projects using the harness): plans must identify the thinnest
# end-to-end slice touching every architectural layer, and the first
# task must be to build that slice. Forces integration FIRST, features
# second — prevents the pattern where each piece is built in isolation
# and the wires between them never get connected.
#
# Plans can opt out with "Walking Skeleton: n/a" on a single line,
# followed by a one-sentence justification (e.g., "Pure refactor — no
# new end-to-end slice being added"). This keeps the forcing function
# while allowing pragmatic edge cases. Plans covering only test-harness
# or docs-only changes are auto-exempt.

IS_DOCS_ONLY=0
if grep -qiE '^# Plan: .*(docs?|documentation|readme|changelog)' "$PLAN_FILE" 2>/dev/null; then
  IS_DOCS_ONLY=1
fi
IS_TEST_HARNESS=0
if grep -qiE 'tests/.*harness|journey.harness|test.infrastructure' "$PLAN_FILE" 2>/dev/null; then
  IS_TEST_HARNESS=1
fi

if [[ $IS_DOCS_ONLY -eq 0 ]] && [[ $IS_TEST_HARNESS -eq 0 ]]; then
  if ! grep -qiE '^## Walking Skeleton|^Walking Skeleton:' "$PLAN_FILE" 2>/dev/null; then
    add_finding "Check 4b: missing '## Walking Skeleton' section. Plans that add new user-facing functionality must identify the thinnest end-to-end slice touching every architectural layer (UI → API → worker → DB → notification) as the first task. Build the skeleton first, then add flesh. Use 'Walking Skeleton: n/a' with a one-sentence justification if this plan is a pure refactor or other exempt case."
  fi
fi

# ============================================================
# Check 5: Runtime tasks without test specs
# ============================================================
#
# Any unchecked task that mentions runtime keywords (page, route, button,
# form, webhook, cron, migration, API) should have a test spec nearby.
# Heuristic: scan each runtime task, look at the following 10 lines for
# a "Test:" or "Runtime verification:" reference.

RUNTIME_KEYWORDS='(\b(page|route|button|form|component|UI|webhook|cron|scheduled|trigger|endpoint|API|migration|column|table|notification)\b)'

UNSPEC_RUNTIME=""
UNSPEC_COUNT=0
while IFS= read -r task_match; do
  [[ -z "$task_match" ]] && continue
  ln=$(echo "$task_match" | cut -d: -f1)
  task_text=$(echo "$task_match" | cut -d: -f2-)
  # Look at the next 10 lines for test spec language
  context=$(sed -n "$ln,$((ln+10))p" "$PLAN_FILE")
  if ! echo "$context" | grep -qiE 'Test(\s*file)?:|Runtime verification:|tests/[a-z]+/[a-z]'; then
    UNSPEC_RUNTIME+="    line $ln: $(echo "$task_text" | head -c 80)"$'\n'
    UNSPEC_COUNT=$((UNSPEC_COUNT + 1))
  fi
done < <(grep -nE "^- \[ \].*${RUNTIME_KEYWORDS}" "$PLAN_FILE" 2>/dev/null)

if [[ "$UNSPEC_COUNT" -gt 0 ]]; then
  add_finding "Check 5: $UNSPEC_COUNT unchecked runtime task(s) without Test:/Runtime verification: specs"
  FINDINGS+="$UNSPEC_RUNTIME"
fi

# ============================================================
# Check 6: "typecheck is verification" / "code looks correct" language
# ============================================================

GEN3_PATTERNS=$(grep -nE 'typecheck\s+(passes|clean|OK|succeeds)|code\s+looks?\s+correct|should\s+work|static\s+analysis' "$PLAN_FILE" 2>/dev/null | grep -v '^#' || true)
if [[ -n "$GEN3_PATTERNS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ln=$(echo "$line" | cut -d: -f1)
    add_finding "Check 6 (Gen 3 anti-pattern): line $ln uses 'typecheck passes' or similar as acceptance"
  done <<< "$GEN3_PATTERNS"
fi

# ============================================================
# Check 7 (Gen 5): Mode: design plans must have substantive
# Systems Engineering Analysis sections
# ============================================================
#
# When a plan declares Mode: design, it MUST include the 10 sections
# (Outcome, End-to-end trace, Interface contracts, Environment,
# Authentication, Observability, Failure modes, Idempotency, Load/capacity,
# Decision records & runbook). Each section must have > 2 lines of
# non-placeholder content.
#
# Rationale: design-mode work fails catastrophically when any of these
# 10 dimensions is unexamined. See ~/.claude/rules/design-mode-planning.md.

# Only apply to plans with Mode: design (not design-skip, not code)
MODE_VALUE=$(awk '/^Mode:/ { print $2; exit }' "$PLAN_FILE" 2>/dev/null | tr -d '[:space:]')

if [[ "$MODE_VALUE" == "design" ]]; then
  # Required section headings (look for "### N." or "## Systems Engineering")
  REQUIRED_SECTIONS=(
    "Outcome"
    "End-to-end trace"
    "Interface contracts"
    "Environment"
    "Authentication"
    "Observability"
    "Failure-mode analysis"
    "Idempotency"
    "Load"
    "Decision records"
  )

  # First, require the parent section exists
  if ! grep -qE '^## Systems Engineering Analysis' "$PLAN_FILE"; then
    add_finding "Check 7 (design-mode): plan declares Mode: design but lacks '## Systems Engineering Analysis' section. Copy the template from ~/.claude/templates/plan-template.md."
  else
    # Check each of the 10 sub-sections exists
    MISSING_SECTIONS=""
    for sec in "${REQUIRED_SECTIONS[@]}"; do
      if ! grep -qiE "^### [0-9]+\. .*$sec" "$PLAN_FILE"; then
        MISSING_SECTIONS+="    - $sec"$'\n'
      fi
    done

    if [[ -n "$MISSING_SECTIONS" ]]; then
      add_finding "Check 7 (design-mode): plan is missing required sections:"$'\n'"$MISSING_SECTIONS"
    fi

    # Check for placeholder text inside sections: lines that are just
    # bracket-text like "[What we're building]" or "[TBD]" or one-liner
    # sections with fewer than 3 substantive lines.
    PLACEHOLDER_COUNT=$(grep -cE '^\s*\[[^]]+\]\s*$' "$PLAN_FILE" 2>/dev/null | tr -cd '[:digit:]')
    PLACEHOLDER_COUNT=${PLACEHOLDER_COUNT:-0}
    if [[ $PLACEHOLDER_COUNT -gt 3 ]]; then
      add_finding "Check 7 (design-mode): plan has $PLACEHOLDER_COUNT placeholder lines (bracket-text like '[What we're building]'). Replace all placeholders with task-specific content before the plan is ACTIVE."
    fi

    # Section-substance check: for each of the 10 sections, count the
    # non-blank, non-comment lines between that heading and the next.
    # Fewer than 3 lines = placeholder.
    SHALLOW_SECTIONS=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
      # Extract the content between ### i. and the next ### or end of Systems Eng section
      CONTENT=$(awk -v n="$i" '
        /^## Systems Engineering Analysis/ { in_sys = 1; next }
        in_sys && /^## / && !/^## Systems Engineering/ { exit }
        in_sys && $0 ~ "^### "n"\\. " { in_sec = 1; next }
        in_sys && in_sec && /^### / { exit }
        in_sec { print }
      ' "$PLAN_FILE" 2>/dev/null)

      # Count substantive lines: non-blank, non-comment, non-pure-bracket
      SUBSTANTIVE=$(echo "$CONTENT" | grep -vE '^\s*$|^\s*<!--|^\s*-->|^\s*\[[^]]+\]\s*$' | wc -l | tr -cd '[:digit:]')
      SUBSTANTIVE=${SUBSTANTIVE:-0}

      if [[ $SUBSTANTIVE -lt 3 ]] && [[ -n "$CONTENT" ]]; then
        SHALLOW_SECTIONS+="    - Section $i has only $SUBSTANTIVE substantive line(s)"$'\n'
      fi
    done

    if [[ -n "$SHALLOW_SECTIONS" ]]; then
      add_finding "Check 7 (design-mode): sections are too shallow to pass systems review. Each section needs specific content (typically 5+ lines), not one-line placeholders:"$'\n'"$SHALLOW_SECTIONS    Then invoke the systems-designer agent for substantive review."
    fi
  fi
fi

# ============================================================
# Report
# ============================================================

if [[ "$FINDING_COUNT" -gt 0 ]]; then
  echo "" >&2
  echo "================================================================" >&2
  echo "PLAN REVIEW: $FINDING_COUNT finding(s) — plan requires rework" >&2
  echo "================================================================" >&2
  echo "" >&2
  echo "File: $PLAN_FILE" >&2
  echo "" >&2
  echo "$FINDINGS" >&2
  echo "To resolve: address each finding above. The plan-reviewer fires" >&2
  echo "before a plan can be marked ACTIVE so that Gen 3 anti-patterns" >&2
  echo "don't survive into execution." >&2
  echo "" >&2
  exit 1
fi

echo "plan-reviewer: no findings" >&2
exit 0
