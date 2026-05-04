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

# ============================================================
# --self-test: exercise pass/fail paths for required-section validation
# ============================================================
#
# Creates four temporary plan files:
#   (a) fully populated  → expected pass
#   (b) missing "## Assumptions" header → expected fail
#   (c) Assumptions section contains only "[populate me]" → expected fail
#   (d) every required section populated substantively → expected pass
#
# Exits 0 on all scenarios matching expectations, non-zero otherwise.

if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT
  SCRIPT="${BASH_SOURCE[0]}"
  FAILED=0

  write_plan_base() {
    # $1 = output path, $2 = "include_assumptions" (0|1), $3 = assumptions_body
    local out="$1"
    local include_assumptions="$2"
    local assumptions_body="${3:-}"
    cat > "$out" <<'PLAN_HEAD'
# Plan: Self-test fixture
Status: ACTIVE
Mode: code
Backlog items absorbed: none

## Goal
Exercise the plan-reviewer required-section check with substantive
content that exceeds the twenty-character minimum for each section.

## Scope
- IN: the required-section validator in plan-reviewer.sh
- OUT: anything not related to required-section enforcement

## Tasks
- [ ] 1. Add a substantive content line so this passes length gate.

## Files to Modify/Create
- `hooks/plan-reviewer.sh` — extend validator with required-section checks

Walking Skeleton: n/a — self-test fixture, no runtime user-facing slice.
PLAN_HEAD

    if [[ "$include_assumptions" == "1" ]]; then
      cat >> "$out" <<PLAN_ASSUMPTIONS

## Assumptions
${assumptions_body}
PLAN_ASSUMPTIONS
    fi

    cat >> "$out" <<'PLAN_TAIL'

## Edge Cases
- Plan with zero edge cases — the check must still enforce a populated
  Edge Cases section rather than allowing it to be omitted.

## Testing Strategy
- Run `--self-test`; confirm every scenario exits with the expected
  pass/fail status (documented in-line at the call site).

## Definition of Done
- [ ] Self-test passes
PLAN_TAIL
  }

  # Scenario (a): fully populated — expect PASS
  write_plan_base "$TMPDIR_SELFTEST/a.md" 1 \
    "- Assumes the existing plan-reviewer bash script remains invocable
  from command line with a single file-path argument as documented."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/a.md" > /dev/null 2>&1; then
    echo "self-test (a) fully-populated: PASS (expected)" >&2
  else
    echo "self-test (a) fully-populated: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (b): missing Assumptions header — expect FAIL
  write_plan_base "$TMPDIR_SELFTEST/b.md" 0
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/b.md" > /dev/null 2>&1; then
    echo "self-test (b) missing-assumptions: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (b) missing-assumptions: FAIL (expected)" >&2
  fi

  # Scenario (c): Assumptions section contains only "[populate me]" — expect FAIL
  write_plan_base "$TMPDIR_SELFTEST/c.md" 1 "[populate me]"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/c.md" > /dev/null 2>&1; then
    echo "self-test (c) placeholder-only: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (c) placeholder-only: FAIL (expected)" >&2
  fi

  # Scenario (d): every section substantive — expect PASS (re-uses a.md shape)
  write_plan_base "$TMPDIR_SELFTEST/d.md" 1 \
    "- Assumes the shell supports bash 4+ associative arrays and awk is
  the GNU or BSD variant available on the developer's machine.
- Assumes the temporary directory is writable for the duration of
  this self-test run."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/d.md" > /dev/null 2>&1; then
    echo "self-test (d) every-section-substantive: PASS (expected)" >&2
  else
    echo "self-test (d) every-section-substantive: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # ============================================================
  # Check 8A scenarios (e, f, g, h) — Mode: design Pre-Submission
  # Audit section presence + substance gate
  # ============================================================
  #
  # All four use the same Mode: design fixture, varying only the
  # ## Pre-Submission Audit section's content. The fixture also
  # populates the 10 Systems Engineering Analysis sub-sections so
  # Check 7 (design-mode SEA section enforcement) passes — otherwise
  # we cannot test Check 8A in isolation.

  write_design_plan_base() {
    # $1 = output path, $2 = audit_mode ("5_sweeps" | "carveout" | "placeholder" | "missing")
    local out="$1"
    local audit_mode="$2"
    cat > "$out" <<'DESIGN_HEAD'
# Plan: Self-test design-mode fixture
Status: ACTIVE
Mode: design
Backlog items absorbed: none

## Goal
Exercise Check 8A by varying the Pre-Submission Audit section while
keeping every other check satisfied. The fixture deliberately
includes substantive content for Check 6b's required sections AND
the 10 Systems Engineering Analysis sub-sections so Check 7 passes
in isolation.

## Scope
- IN: the Pre-Submission Audit gate in plan-reviewer.sh
- OUT: anything else; the fixture is single-purpose

## Tasks
- [ ] 1. Synthetic task with a runtime test reference: tests/foo.spec.ts
  covers the user flow.

## Files to Modify/Create
- `hooks/plan-reviewer.sh` — extend with Check 8A self-test scenarios

## Assumptions
- Assumes Check 7 passes for this fixture so Check 8A's outcome
  is the only variable across scenarios e/f/g/h.

## Edge Cases
- The fixture must not regress Check 6b's required-section gates;
  if any required section is missing or placeholder, the test result
  is ambiguous between Check 6b and Check 8A.

## Testing Strategy
- Run plan-reviewer.sh against this fixture in each variant; observe
  the exit code matches expectation per scenario.

Walking Skeleton: n/a — self-test fixture, no runtime user-facing slice.

## Definition of Done
- [ ] Self-test reports the expected verdict per scenario.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
Within zero seconds of running plan-reviewer.sh against this fixture,
the script exits with the expected code per scenario.
A future planner reading this fixture sees the canonical shape of a
passing design-mode plan for Check 8A specifically.
The exit code is the only assertion the self-test makes.

### 2. End-to-end trace with a concrete example
At T=0 the self-test invokes `bash plan-reviewer.sh /tmp/<scenario>.md`.
plan-reviewer reads the file, sets MODE_VALUE=design from the header.
It runs Check 6b required sections, then Check 7 SEA sections,
then Check 8A audit section.
Exits 0 on PASS, 1 on any FAIL.

### 3. Interface contracts between components
plan-reviewer.sh receives a file path argument from the self-test runner.
It emits exit 0 on PASS, exit 1 on findings (stderr details).
self-test invokes via `bash $SCRIPT $path` and keys on the exit status.
Stderr findings are captured but not asserted in the self-test.

### 4. Environment & execution context
Bash 4+ shell with GNU or BSD awk and GNU or BSD grep available.
Temporary fixture file under a `mktemp -d` directory.
No persistent state — trap removes the tmpdir on exit.
Working directory is the user's CWD; PLAN_FILE is read absolute.

### 5. Authentication & authorization map
None — the fixture is offline.
No network or auth boundaries are crossed.
The hook reads only the local plan file and writes only stderr findings.

### 6. Observability plan (built before the feature)
Self-test prints one line per scenario to stderr.
Format: `self-test (X) name: PASS (expected)` or `FAIL (expected)`.
A final summary line indicates whether all expectations matched.
Failures localize to the named scenario via the prefix letter.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery |
|------|---------|---------|----------|
| Fixture write | Disk full | mktemp fails with ENOSPC | Bash exits with the mktemp error |
| Hook invocation | Bash syntax error in plan-reviewer.sh | Non-zero exit with parse error on stderr | Self-test reports unexpected verdict; author inspects |
| Verdict comparison | Off-by-one in expected exit code | Scenario flagged as failed | Author reads stderr and fixes the scenario expectation |

### 8. Idempotency & restart semantics
Each invocation is idempotent — creates a fresh tmpdir.
Runs all scenarios sequentially, cleans up via trap on exit.
No persistent state between runs.
Re-running mid-run is safe — the prior tmpdir is independent.

### 9. Load / capacity model
Four Check-8A scenarios per self-test pass.
Plus the existing 4 scenarios (a/b/c/d) = 8 total.
Total runtime ~1s on a typical machine; no bottleneck.
Memory footprint: a few KB of fixture text per scenario.

### 10. Decision records & runbook
Decision: use four scenarios (e/f/g/h) for Check 8A.
Alternative: one combined scenario interleaving all four cases.
Rejected because the four-scenario form makes failures localizable
to the specific gate (presence vs substance vs carve-out).
Runbook: if any scenario produces unexpected verdict, capture the
fixture file via TMPDIR_SELFTEST inspection during a debug run.

DESIGN_HEAD

    case "$audit_mode" in
      "5_sweeps")
        cat >> "$out" <<'AUDIT_5SWEEPS'
## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, 0 matches in self-test fixture
S2 (Existing-Code-Claim Verification): swept, 0 matches
S3 (Cross-Section Consistency): swept, 0 contradictions remaining
S4 (Numeric-Parameter Sweep): swept, 0 matches
S5 (Scope-vs-Analysis Check): swept, 0 contradictions
AUDIT_5SWEEPS
        ;;
      "carveout")
        cat >> "$out" <<'AUDIT_CARVEOUT'
## Pre-Submission Audit

n/a — single-task plan, no class-sweep needed
AUDIT_CARVEOUT
        ;;
      "placeholder")
        cat >> "$out" <<'AUDIT_PLACEHOLDER'
## Pre-Submission Audit

[populate me]
AUDIT_PLACEHOLDER
        ;;
      "missing")
        # No section emitted — gate must FAIL on absence
        ;;
    esac
  }

  # Scenario (e): Mode: design + 5 substantive sweep lines — expect PASS
  write_design_plan_base "$TMPDIR_SELFTEST/e.md" "5_sweeps"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/e.md" > /dev/null 2>&1; then
    echo "self-test (e) design-mode-with-5-sweeps: PASS (expected)" >&2
  else
    echo "self-test (e) design-mode-with-5-sweeps: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (f): Mode: design + canonical carve-out — expect PASS
  write_design_plan_base "$TMPDIR_SELFTEST/f.md" "carveout"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/f.md" > /dev/null 2>&1; then
    echo "self-test (f) design-mode-with-carveout: PASS (expected)" >&2
  else
    echo "self-test (f) design-mode-with-carveout: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (g): Mode: design + missing Pre-Submission Audit section — expect FAIL
  write_design_plan_base "$TMPDIR_SELFTEST/g.md" "missing"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/g.md" > /dev/null 2>&1; then
    echo "self-test (g) design-mode-missing-audit-section: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (g) design-mode-missing-audit-section: FAIL (expected)" >&2
  fi

  # Scenario (h): Mode: design + audit-section-placeholder-only — expect FAIL
  write_design_plan_base "$TMPDIR_SELFTEST/h.md" "placeholder"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/h.md" > /dev/null 2>&1; then
    echo "self-test (h) design-mode-audit-placeholder-only: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (h) design-mode-audit-placeholder-only: FAIL (expected)" >&2
  fi

  # ============================================================
  # Check 9 scenarios (i, j, k, l) — Mode-gated comparative-claim
  # arithmetic check (FM-013 / FM-014)
  # ============================================================
  #
  # (i) Mode: code plan with comparative phrases — expect PASS (Check 9 is
  #     design-mode-only, so Mode: code plans are exempt from Check 9.
  #     The fixture must still pass all OTHER checks).
  # (j) Mode: design plan with comparative phrases AND visible arithmetic
  #     in the same paragraph — expect PASS.
  # (k) Mode: design plan with comparative phrase but NO arithmetic in
  #     the same paragraph — expect FAIL.
  # (l) Mode: design plan with self-contradicting hedge ("comfortably
  #     under X (slight over)") — expect FAIL.

  # Fixture (i): Mode: code plan with comparative phrases. The fixture
  # must reuse the standard required-section shape; we extend the
  # base writer to inject a paragraph containing comparative phrases
  # without arithmetic, so the only thing distinguishing this from a
  # FAIL is the mode-gating.
  cat > "$TMPDIR_SELFTEST/i.md" <<'CHECK9_I'
# Plan: Self-test Check 9 mode-code fixture
Status: ACTIVE
Mode: code
Backlog items absorbed: none

## Goal
This plan describes a small refactor that should fit comfortably under
50 RPM at peak load, with no concerns about exceeding 100 calls per
minute since the integration only fires on user-driven events. The
typical usage stays well below 30 RPM observed in production.

## Scope
- IN: refactor a small helper for under 200 lines of churn
- OUT: anything outside the helper

## Tasks
- [ ] 1. Refactor the helper module per the goal above.

## Files to Modify/Create
- `src/helper.ts` — refactor target

## Assumptions
- Assumes the existing test suite covers the helper's contract so
  the refactor is verified by re-running the tests.

## Edge Cases
- The refactor must preserve behavior for all callers; if any caller
  relies on a side-effect, document it and keep the side-effect.

## Testing Strategy
- Run the existing test suite; manual smoke check is not required since
  the refactor is contract-preserving.

Walking Skeleton: n/a — pure refactor, no new end-to-end slice.

## Definition of Done
- [ ] Tests pass after refactor.
CHECK9_I

  if bash "$SCRIPT" "$TMPDIR_SELFTEST/i.md" > /dev/null 2>&1; then
    echo "self-test (i) check9-mode-code-exempt: PASS (expected)" >&2
  else
    echo "self-test (i) check9-mode-code-exempt: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Fixture (j): Mode: design plan with comparative phrases AND visible
  # arithmetic in the same paragraph. Reuse write_design_plan_base for
  # the structural shape (10 SEA sections + audit section), then append
  # a paragraph with both a comparative claim and the arithmetic that
  # validates it.
  write_design_plan_base "$TMPDIR_SELFTEST/j.md" "5_sweeps"
  cat >> "$TMPDIR_SELFTEST/j.md" <<'CHECK9_J'

## Capacity Notes

The proposed sync cadence stays under 50 RPM at peak. Computation:
60 calls (15 threads × 2 calls × 2 batches × 1 sync) ÷ 60s = 60 calls/min.
Wait, that exceeds 50 — the actual budget is 30 calls per sync because
the per-thread call count is 1 in steady state, giving 15 < 50 RPM.
CHECK9_J

  if bash "$SCRIPT" "$TMPDIR_SELFTEST/j.md" > /dev/null 2>&1; then
    echo "self-test (j) check9-design-mode-with-arithmetic: PASS (expected)" >&2
  else
    echo "self-test (j) check9-design-mode-with-arithmetic: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Fixture (k): Mode: design plan with comparative phrase but NO
  # arithmetic in the same paragraph. The base passes all other checks;
  # the appended paragraph asserts a quantitative claim without showing
  # the math.
  write_design_plan_base "$TMPDIR_SELFTEST/k.md" "5_sweeps"
  cat >> "$TMPDIR_SELFTEST/k.md" <<'CHECK9_K'

## Capacity Notes

The integration produces 60 calls per minute, well under 50 RPM at
peak load based on prior production observation that the rate has
never approached the documented ceiling for similar integrations.
CHECK9_K

  if bash "$SCRIPT" "$TMPDIR_SELFTEST/k.md" > /dev/null 2>&1; then
    echo "self-test (k) check9-design-mode-without-arithmetic: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (k) check9-design-mode-without-arithmetic: FAIL (expected)" >&2
  fi

  # Fixture (l): Mode: design plan with a self-contradicting hedge.
  # The phrase "comfortably under 50K ITPM (slight over)" is the
  # canonical FM-014 example.
  write_design_plan_base "$TMPDIR_SELFTEST/l.md" "5_sweeps"
  cat >> "$TMPDIR_SELFTEST/l.md" <<'CHECK9_L'

## Capacity Notes

The token budget sits comfortably under 50K ITPM (slight over)
in worst-case bursts. The integration is otherwise within tier.
CHECK9_L

  if bash "$SCRIPT" "$TMPDIR_SELFTEST/l.md" > /dev/null 2>&1; then
    echo "self-test (l) check9-self-contradicting-hedge: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (l) check9-self-contradicting-hedge: FAIL (expected)" >&2
  fi

  if [[ $FAILED -eq 0 ]]; then
    echo "plan-reviewer --self-test: all scenarios matched expectations" >&2
    exit 0
  else
    echo "plan-reviewer --self-test: one or more scenarios failed" >&2
    exit 1
  fi
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <plan-file>" >&2
  echo "       $0 --self-test" >&2
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
# Check 6b (Gen 5): Required sections must be present AND populated
# ============================================================
#
# Every plan — regardless of size or mode — must include the seven
# required sections listed in `~/.claude/rules/planning.md` → "Verbose
# Plans Are Mandatory". A section fails the check if:
#
#   (1) its `## <Heading>` marker is missing from the file, OR
#   (2) its body has fewer than 20 non-whitespace characters, OR
#   (3) its body (with whitespace collapsed) consists solely of one or
#       more placeholder tokens: "[populate me]", "[TODO]", "TODO",
#       "...", or a literal fragment of the template's own prompt text.
#
# The check reports the FIRST offending section so the author can fix
# and re-run. Scope and Definition-of-Done checks above remain in place;
# this check adds Assumptions, Edge Cases, Testing Strategy, plus
# re-validates Goal, Tasks, and Files to Modify/Create for substance.

REQUIRED_HEADINGS=(
  "## Goal"
  "## Scope"
  "## Tasks"
  "## Files to Modify/Create"
  "## Assumptions"
  "## Edge Cases"
  "## Testing Strategy"
)

# Placeholder tokens that disqualify a section's body if it consists
# only of these (case-insensitive).
PLACEHOLDER_PATTERNS=(
  '\[populate me\]'
  '\[todo\]'
  '\btodo\b'
  '\.\.\.'
  '\[first explicit premise this plan depends on\]'
  '\[first edge case and how this plan handles it\]'
  '\[how each task will be verified\]'
  '\[what we.?re building/changing and why\]'
  '\[what we.?re building and why\]'
  '\[what.?s included\]'
  '\[what.?s explicitly excluded\]'
  '\[first task'
  '\[second task\]'
  '\[what changes and why\]'
)

check_required_section() {
  local heading="$1"
  # Locate the heading line number. Must be an exact heading match —
  # "## Goal" must not match "## Goal Achievement" etc.
  local heading_pattern
  heading_pattern="$(printf '%s' "$heading" | sed 's/[][\/.^$*]/\\&/g')"
  local ln
  ln=$(grep -nE "^${heading_pattern}\s*\$" "$PLAN_FILE" 2>/dev/null | head -1 | cut -d: -f1)

  if [[ -z "$ln" ]]; then
    add_finding "Check 6b: required section '$heading' is missing. Every plan must include: ${REQUIRED_HEADINGS[*]}. See ~/.claude/rules/planning.md, 'Verbose Plans Are Mandatory'."
    return
  fi

  # Extract the body: lines after the heading up to the next '## ' header
  # or end of file. Strip HTML comments so prompts inside <!-- --> don't
  # count toward substance.
  local body
  body=$(awk -v start="$ln" '
    NR == start { next }
    NR > start {
      if ($0 ~ /^## /) exit
      print
    }
  ' "$PLAN_FILE" 2>/dev/null | awk '
    /<!--/ { in_comment = 1 }
    !in_comment { print }
    /-->/ { in_comment = 0 }
  ')

  # Collapse to a single normalized string for checks
  local normalized
  normalized=$(printf '%s' "$body" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

  # Count non-whitespace characters
  local non_ws_count
  non_ws_count=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
  non_ws_count=${non_ws_count:-0}

  if [[ $non_ws_count -lt 20 ]]; then
    add_finding "Check 6b: required section '$heading' is empty or too short (only $non_ws_count non-whitespace chars; needs >= 20). Populate with substantive, plan-specific content. See ~/.claude/rules/planning.md, 'Verbose Plans Are Mandatory'."
    return
  fi

  # Placeholder-only check: strip placeholder tokens and list-bullets; if
  # nothing substantive remains, the section is placeholder-only.
  # Use '|' as sed delimiter so forward slashes inside patterns are safe.
  local stripped="$normalized"
  for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
    stripped=$(printf '%s' "$stripped" | sed -E "s|${pat}||g")
  done
  # Remove bullet markers and stray punctuation
  stripped=$(printf '%s' "$stripped" | sed -E 's|[[:space:]]*[-*][[:space:]]*||g; s|[][(){}:;,.!?"`'"'"']||g')
  stripped=$(printf '%s' "$stripped" | tr -d '[:space:]')

  if [[ -z "$stripped" ]]; then
    add_finding "Check 6b: required section '$heading' contains only placeholder text (e.g., '[populate me]', 'TODO', or template prompt). Replace with plan-specific content. See ~/.claude/rules/planning.md, 'Verbose Plans Are Mandatory'."
    return
  fi
}

# Run the check for each required heading, reporting the first
# offender and stopping so the author can fix and resubmit without
# being buried in duplicate findings.
for heading in "${REQUIRED_HEADINGS[@]}"; do
  PREV_COUNT=$FINDING_COUNT
  check_required_section "$heading"
  if [[ $FINDING_COUNT -gt $PREV_COUNT ]]; then
    break
  fi
done

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
# Check 8A (Gen 5+): Mode: design plans must have a substantive
# Pre-Submission Audit section
# ============================================================
#
# When a plan declares Mode: design, the planner must perform the
# 5-sweep Pre-Submission Class-Sweep Audit (S1-S5) before invoking
# systems-designer. The discipline is documented in
# ~/.claude/rules/design-mode-planning.md "Pre-Submission Class-Sweep
# Audit (mandatory before invoking systems-designer)" — landed in
# commit 9c4e4c8 as a Pattern; this check is the Mechanism layer.
#
# Why this exists: an originating 2026-04-28 design-mode review effort
# (an OAuth+IMAP auth-refactor plan) required eight rounds of
# systems-designer review to reach PASS. Each round caught real
# implementation gaps but the same root cause produced 9+ sibling
# instances over rounds 5-8: the planner did not perform a class-sweep
# before submitting to the reviewer. The Pattern rule documents the
# discipline; this check enforces that the discipline was at minimum
# acknowledged.
#
# What this check gates on: STRUCTURE only — section presence + at
# least 5 distinct sweep tokens (S1/S2/S3/S4/S5) OR the canonical
# full-sentence carve-out. It does NOT verify whether the documented
# sweeps were honestly performed (that would require LLM-grade reading
# or format-enforcement upstream — both deferred per
# docs/plans/pre-submission-audit-mechanical-enforcement.md
# Decisions Log D-3).
#
# Bypass surface (acknowledged residual risk): a planner who wants to
# satisfy the gate without doing the sweeps can write 5 fake
# "S<N>: swept, 0 matches" lines (~30s) vs honest sweeps (~30min).
# The 60× friction ratio plus the structural requirement of writing
# five distinct sweep declarations is meaningful (typing five sweep-
# shaped lines is a cognitive pause where typing one annotation is
# not — see why Check 8B was rejected for comparison). Closing this
# bypass requires either an LLM-driven check or per-sweep substance
# verification; both are out of scope here. See FM-007 in
# docs/failure-modes.md for the class this prevents.

if [[ "$MODE_VALUE" == "design" ]]; then
  AUDIT_LN=$(grep -nE '^## Pre-Submission Audit\s*$' "$PLAN_FILE" 2>/dev/null | head -1 | cut -d: -f1)

  if [[ -z "$AUDIT_LN" ]]; then
    add_finding "Check 8A (design-mode): plan declares Mode: design but lacks '## Pre-Submission Audit' section. The planner must perform the 5-sweep audit (S1 Entry-Point Surfacing, S2 Existing-Code-Claim Verification, S3 Cross-Section Consistency, S4 Numeric-Parameter Sweep, S5 Scope-vs-Analysis Check) before invoking the systems-designer agent. Add the section per the template at ~/.claude/templates/plan-template.md, OR if the plan is genuinely a single-task design-mode change with no analysis surface for sweeps to apply to, use the canonical carve-out: 'n/a — single-task plan, no class-sweep needed'. See ~/.claude/rules/design-mode-planning.md, 'Pre-Submission Class-Sweep Audit'."
  else
    # Extract the section body up to the next '## ' heading.
    # Strip HTML comments so prompts inside <!-- --> don't count
    # toward substance.
    AUDIT_BODY=$(awk -v start="$AUDIT_LN" '
      NR == start { next }
      NR > start {
        if ($0 ~ /^## /) exit
        print
      }
    ' "$PLAN_FILE" 2>/dev/null | awk '
      /<!--/ { in_comment = 1 }
      !in_comment { print }
      /-->/ { in_comment = 0 }
    ')

    # Path (a): canonical full-sentence carve-out present?
    # Use grep -F (fixed string) to match the em-dash literally.
    HAS_CARVEOUT=0
    if printf '%s' "$AUDIT_BODY" | grep -qF "n/a — single-task plan, no class-sweep needed" 2>/dev/null; then
      HAS_CARVEOUT=1
    fi

    # Path (b): all 5 distinct sweep tokens (S1, S2, S3, S4, S5) present?
    # Tolerate optional list-bullet ("- ", "* ", "+ ") and optional
    # bold ("**S1**" etc). We require DISTINCT tokens so writing "S1"
    # five times does not satisfy — must see one line each for S1..S5.
    SWEEP_TOKENS_FOUND=0
    for s in S1 S2 S3 S4 S5; do
      if printf '%s' "$AUDIT_BODY" | grep -qE "^\s*([-*+]\s+)?(\*\*)?${s}\b" 2>/dev/null; then
        SWEEP_TOKENS_FOUND=$((SWEEP_TOKENS_FOUND + 1))
      fi
    done

    if [[ $HAS_CARVEOUT -eq 0 ]] && [[ $SWEEP_TOKENS_FOUND -lt 5 ]]; then
      add_finding "Check 8A (design-mode): plan's '## Pre-Submission Audit' section has neither (a) the canonical full-sentence carve-out 'n/a — single-task plan, no class-sweep needed', nor (b) at least one line each starting with S1/S2/S3/S4/S5 (found $SWEEP_TOKENS_FOUND of 5 distinct sweep tokens). The planner must document each of the 5 sweeps (or use the canonical carve-out) before invoking systems-designer. Format per sweep: 'S1 (Entry-Point Surfacing): swept, N matches, M cited correctly, K added to Tasks/Files'. See ~/.claude/rules/design-mode-planning.md, 'The \`## Pre-Submission Audit\` section'."
    fi
  fi
fi

# ============================================================
# Check 9 (C22): Mode: design plans must show inline arithmetic
# for quantitative comparative claims (FM-013 / FM-014)
# ============================================================
#
# The "Quantitative Claims Must Be Validated, Not Asserted" rule in
# ~/.claude/rules/design-mode-planning.md requires that every comparative
# quantitative claim ("under 50 RPM", "fits within 30s timeout",
# "30% margin") in a design-mode plan be accompanied by inline arithmetic
# in the same paragraph that demonstrates the math has been checked.
#
# Comparative phrases without arithmetic are unverified assertions and
# cause real planning failures: the originating 2026-04-28 review caught
# Section 9 of an auth-refactor plan saying "60 calls within tier limits"
# against a 50 RPM cap — false by 20%.
#
# Detection: regex-match comparative phrases. For each match, scan a
# paragraph window (5 lines before + 5 lines after, bounded by blank
# lines) for inline arithmetic operators (multiplication, division,
# comparison, computed-value markers).
#
# Self-contradicting hedges ("comfortably under X (slight over)") are
# flagged as a separate failure class because the parenthetical
# contradiction is a stronger signal than absent arithmetic.
#
# Mode-gating: only fires on Mode: design. Mode: code and Mode: design-skip
# are exempt. The check is a no-op when the plan is not design-mode.

if [[ "$MODE_VALUE" == "design" ]]; then
  # Self-contradicting hedge patterns: a comparative phrase followed by a
  # parenthetical concession in the same line. These are detected first
  # because they're a stronger signal than missing arithmetic.
  HEDGE_LINES=$(grep -niE '\b(comfortably|well|fits|under|over|exceeds|below|above|at most|at least)\b[^()]{0,80}\((slight|slightly|barely|close call|just|almost)\b[^)]{0,80}(over|under|above|below|exceeds|short|past)' "$PLAN_FILE" 2>/dev/null || true)
  if [[ -n "$HEDGE_LINES" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ln=$(echo "$line" | cut -d: -f1)
      phrase=$(echo "$line" | cut -d: -f2- | head -c 140 | tr -d '\n')
      add_finding "Check 9 (design-mode self-contradicting hedge): line $ln has a comparative claim contradicting its own caveat — \"$phrase\". Reason: FM-014 — capacity claim contradicts its own math. Resolve to a single position (lower the cap, accept the rate-limit retry, upgrade the tier) and rewrite the claim without the parenthetical hedge."
    done <<< "$HEDGE_LINES"
  fi

  # Comparative-phrase detection. We collect all match line numbers and
  # then validate each match's surrounding paragraph for arithmetic.
  # The pattern groups cover the canonical forms documented in
  # ~/.claude/rules/design-mode-planning.md "Quantitative Claims Must Be
  # Validated, Not Asserted".
  COMPARATIVE_PATTERN='(\bunder [0-9]+\b|\bover [0-9]+\b|\bexceeds [0-9]+\b|\bfits within [0-9]+\b|\bbelow [0-9]+\b|\babove [0-9]+\b|\bat most [0-9]+\b|\bat least [0-9]+\b|\bwell (above|below) [0-9]+\b|\bcomfortably (under|within|below|above)\b|[0-9]+%[[:space:]]+(margin|headroom|over|under)\b|\b[0-9]+x\b[[:space:]]+(faster|slower|larger|smaller|more|less)\b)'

  COMPARATIVE_LINES=$(grep -nEi "$COMPARATIVE_PATTERN" "$PLAN_FILE" 2>/dev/null || true)

  if [[ -n "$COMPARATIVE_LINES" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ln=$(echo "$line" | cut -d: -f1)
      [[ -z "$ln" ]] && continue
      phrase=$(echo "$line" | cut -d: -f2- | head -c 120 | tr -d '\n')

      # Skip if this line is already flagged as a self-contradicting hedge
      # (the hedge check above is more specific and preferred).
      if echo "$HEDGE_LINES" | grep -qE "^$ln:" 2>/dev/null; then
        continue
      fi

      # Compute the paragraph window: walk backward from $ln until a blank
      # line or 5-line cap, then forward from $ln until a blank line or
      # 5-line cap. Intent: a "paragraph" is a contiguous block of
      # non-blank lines bounded by blank lines.
      start=$((ln - 5))
      [[ $start -lt 1 ]] && start=1
      end=$((ln + 5))

      # Walk back from ln-1 to start, stopping at the first blank line.
      i=$((ln - 1))
      while [[ $i -ge $start ]]; do
        if [[ -z "$(sed -n "${i}p" "$PLAN_FILE" | tr -d '[:space:]')" ]]; then
          start=$((i + 1))
          break
        fi
        i=$((i - 1))
      done

      # Walk forward from ln+1 to end, stopping at the first blank line.
      i=$((ln + 1))
      while [[ $i -le $end ]]; do
        if [[ -z "$(sed -n "${i}p" "$PLAN_FILE" | tr -d '[:space:]')" ]]; then
          end=$((i - 1))
          break
        fi
        i=$((i + 1))
      done

      paragraph=$(sed -n "${start},${end}p" "$PLAN_FILE" 2>/dev/null)

      # Inline arithmetic = at least one of:
      #   - multiplication / division: "N × M", "N * M", "N / M", "N ÷ M"
      #   - comparison: "N < M", "N > M", "N ≤ M", "N ≥ M", "N <= M", "N >= M"
      #   - computed value: "= N" or "→ N" or ":= N"
      # The patterns require digits on at least one side to keep noise low.
      ARITH_PATTERN='[0-9]+[[:space:]]*[×*/÷][[:space:]]*[0-9]+|[0-9]+[[:space:]]*[<>][=]?[[:space:]]*[0-9]+|[0-9]+[[:space:]]*[≤≥][[:space:]]*[0-9]+|[=→][[:space:]]*[0-9]+|[0-9]+[[:space:]]*=[[:space:]]*[0-9]+'

      if ! echo "$paragraph" | grep -qE "$ARITH_PATTERN" 2>/dev/null; then
        add_finding "Check 9 (design-mode comparative claim without inline arithmetic): line $ln has a comparative quantitative claim without arithmetic in the same paragraph — \"$phrase\". Required: show the math in the same paragraph (e.g., \"60 calls (15 threads × 2 calls × 2 batches × 1 sync) ÷ 60s = 60 calls/min < 50 RPM tier limit\"). Reason: FM-013 / FM-014 — capacity claims without arithmetic are unverified. See ~/.claude/rules/design-mode-planning.md, 'Quantitative Claims Must Be Validated, Not Asserted'."
      fi
    done <<< "$COMPARATIVE_LINES"
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
