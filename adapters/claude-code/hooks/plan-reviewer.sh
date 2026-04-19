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
