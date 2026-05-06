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
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

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
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

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
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

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

  # ============================================================
  # Check 10 scenarios (m, n, o, p, q) — 5-field plan-header schema
  # ============================================================
  #
  # Each fixture keeps Check 6b/7/8A/9 satisfied so the only variable
  # is the plan-header schema. Mode: code is used (simpler — no SEA
  # sections required) except where Status is non-ACTIVE to test the
  # Status gate.
  #
  # write_schema_plan: parameterized writer that emits a Mode: code,
  # Status: ACTIVE plan with the 5 header fields configurable per
  # scenario. Unset fields are omitted from the output.

  write_schema_plan() {
    # $1 = output path
    # $2 = status (default ACTIVE)
    # $3 = tier value (or empty to omit field)
    # $4 = rung value (or empty to omit)
    # $5 = architecture value (or empty to omit)
    # $6 = frozen value (or empty to omit)
    # $7 = prd-ref value (or empty to omit)
    local out="$1"
    local status="${2:-ACTIVE}"
    local tier_val="${3:-}"
    local rung_val="${4:-}"
    local arch_val="${5:-}"
    local frozen_val="${6:-}"
    local prd_val="${7:-}"

    {
      echo "# Plan: Self-test Check 10 schema fixture"
      echo "Status: $status"
      echo "Mode: code"
      echo "Backlog items absorbed: none"
      [[ -n "$tier_val" ]] && echo "tier: $tier_val"
      [[ -n "$rung_val" ]] && echo "rung: $rung_val"
      [[ -n "$arch_val" ]] && echo "architecture: $arch_val"
      [[ -n "$frozen_val" ]] && echo "frozen: $frozen_val"
      [[ -n "$prd_val" ]] && echo "prd-ref: $prd_val"
      cat <<'SCHEMA_BODY'

## Goal
Exercise the 5-field plan-header schema check by varying header fields
while keeping every other check satisfied. The fixture is intentionally
minimal in scope to keep test output focused.

## Scope
- IN: Check 10 5-field plan-header schema enforcement
- OUT: anything else; the fixture is single-purpose

## Tasks
- [ ] 1. Synthetic task placeholder; Test: covered by self-test runner
  invocation observing the exit code.

## Files to Modify/Create
- `hooks/plan-reviewer.sh` — schema check under exercise

## Assumptions
- Assumes the plan-reviewer schema check fires only on Status: ACTIVE
  plans, so DEFERRED fixtures bypass Check 10 entirely.

## Edge Cases
- The fixture must satisfy Check 6b's required sections so the only
  failing path is Check 10 itself.

## Testing Strategy
- Run plan-reviewer.sh against this fixture; observe the exit code
  matches the scenario expectation.

Walking Skeleton: n/a — self-test fixture, no runtime user-facing slice.

## Definition of Done
- [ ] Self-test reports the expected verdict per scenario.
SCHEMA_BODY
    } > "$out"
  }

  # Scenario (m): ACTIVE plan with all 5 fields valid — expect PASS
  write_schema_plan "$TMPDIR_SELFTEST/m.md" "ACTIVE" "2" "1" "coding-harness" "false" "n/a — harness-development"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/m.md" > /dev/null 2>&1; then
    echo "self-test (m) check10-pass-all-fields-active: PASS (expected)" >&2
  else
    echo "self-test (m) check10-pass-all-fields-active: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (n): ACTIVE plan missing tier — expect FAIL
  write_schema_plan "$TMPDIR_SELFTEST/n.md" "ACTIVE" "" "1" "coding-harness" "false" "n/a — harness-development"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/n.md" > /dev/null 2>&1; then
    echo "self-test (n) check10-fail-missing-tier: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (n) check10-fail-missing-tier: FAIL (expected)" >&2
  fi

  # Scenario (o): ACTIVE plan with rung: 7 (out of range) — expect FAIL
  write_schema_plan "$TMPDIR_SELFTEST/o.md" "ACTIVE" "2" "7" "coding-harness" "false" "n/a — harness-development"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/o.md" > /dev/null 2>&1; then
    echo "self-test (o) check10-fail-invalid-rung: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (o) check10-fail-invalid-rung: FAIL (expected)" >&2
  fi

  # Scenario (p): ACTIVE plan with architecture: invalid-value — expect FAIL
  write_schema_plan "$TMPDIR_SELFTEST/p.md" "ACTIVE" "2" "1" "invalid-value" "false" "n/a — harness-development"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/p.md" > /dev/null 2>&1; then
    echo "self-test (p) check10-fail-invalid-architecture: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (p) check10-fail-invalid-architecture: FAIL (expected)" >&2
  fi

  # Scenario (q): DEFERRED plan missing tier — expect PASS
  # (Status gate early-exits Check 10 for non-ACTIVE plans)
  write_schema_plan "$TMPDIR_SELFTEST/q.md" "DEFERRED" "" "1" "coding-harness" "false" "n/a — harness-development"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/q.md" > /dev/null 2>&1; then
    echo "self-test (q) check10-pass-deferred-skips-check10: PASS (expected)" >&2
  else
    echo "self-test (q) check10-pass-deferred-skips-check10: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # ============================================================
  # Check 11 scenarios (r, s, t, u, v) — C16 Behavioral Contracts
  # at rung >= 3
  # ============================================================
  #
  # Fixtures vary rung value and Behavioral Contracts section content
  # while keeping every other check satisfied. write_bc_plan generates
  # a Mode: code, Status: ACTIVE plan with the 5 header fields valid
  # (so Check 10 passes), parameterizing rung and the optional
  # Behavioral Contracts section.

  write_bc_plan() {
    # $1 = output path
    # $2 = rung value (0-5)
    # $3 = bc_mode ("none" | "all_substantive" | "missing_subentry" | "placeholder_subentry")
    local out="$1"
    local rung_val="$2"
    local bc_mode="$3"

    cat > "$out" <<BC_HEAD
# Plan: Self-test Check 11 behavioral-contracts fixture
Status: ACTIVE
Mode: code
Backlog items absorbed: none
tier: 2
rung: $rung_val
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal
Exercise Check 11 (C16 Behavioral Contracts) by varying the
Behavioral Contracts section content and the rung value while
keeping every other check satisfied.

## Scope
- IN: Check 11 sub-section presence + substance enforcement
- OUT: anything else; fixture is single-purpose

## Tasks
- [ ] 1. Synthetic task placeholder; Test: covered by self-test runner
  invocation observing the exit code.

## Files to Modify/Create
- \`hooks/plan-reviewer.sh\` — Check 11 implementation under exercise

## Assumptions
- Assumes Check 10 passes for this fixture so Check 11 outcome is
  the only variable across r/s/t/u/v scenarios.

## Edge Cases
- The fixture must satisfy Check 6b's required sections so the only
  failing path is Check 11 itself.

## Testing Strategy
- Run plan-reviewer.sh against this fixture in each variant; observe
  the exit code matches the scenario expectation.

Walking Skeleton: n/a — self-test fixture, no runtime user-facing slice.

## Definition of Done
- [ ] Self-test reports the expected verdict per scenario.
BC_HEAD

    case "$bc_mode" in
      "all_substantive")
        cat >> "$out" <<'BC_ALL'

## Behavioral Contracts

### Idempotency
The implementation must produce identical observable state when invoked
twice with the same inputs. Re-runs after partial failures resume from
the next unprocessed step rather than restarting from scratch.

### Performance budget
Per-invocation latency budget is 200ms p50 and 1s p99. The end-to-end
flow must complete within a 30s wall-clock window even when downstream
services exercise their own retry policies.

### Retry semantics
Transient failures (network timeouts, 5xx responses) trigger exponential
backoff with three retries and a 30s cap. Permanent failures (4xx
client errors) skip retry and surface the error to the caller.

### Failure modes
Documented failure phenotypes include (a) downstream service unavailable
producing a breaker-and-skip path, (b) partial-write inconsistency
where the database has the row but the index does not yet, surfaced via
a reconciliation pass on next sync.
BC_ALL
        ;;
      "missing_subentry")
        # Only Idempotency + Performance budget present; Retry semantics
        # and Failure modes missing.
        cat >> "$out" <<'BC_MISSING'

## Behavioral Contracts

### Idempotency
The implementation must produce identical observable state when invoked
twice with the same inputs. Re-runs resume from the next unprocessed
step rather than restarting from scratch entirely.

### Performance budget
Per-invocation latency budget is 200ms p50 and 1s p99. The end-to-end
flow must complete within a 30s wall-clock window even when downstream
services exercise their own retry policies.
BC_MISSING
        ;;
      "placeholder_subentry")
        cat >> "$out" <<'BC_PLACEHOLDER'

## Behavioral Contracts

### Idempotency
[populate me]

### Performance budget
Per-invocation latency budget is 200ms p50 and 1s p99. The end-to-end
flow must complete within a 30s wall-clock window even when downstream
services exercise their own retry policies.

### Retry semantics
Transient failures (network timeouts, 5xx responses) trigger exponential
backoff with three retries and a 30s cap. Permanent failures (4xx
client errors) skip retry and surface the error to the caller.

### Failure modes
Documented failure phenotypes include (a) downstream service unavailable
producing a breaker-and-skip path, (b) partial-write inconsistency
where the database has the row but the index does not yet, surfaced via
a reconciliation pass on next sync.
BC_PLACEHOLDER
        ;;
      "none")
        # Behavioral Contracts section omitted entirely
        ;;
    esac
  }

  # Scenario (r): rung 0, no Behavioral Contracts section — expect PASS
  # (Check 11 doesn't fire below rung 3)
  write_bc_plan "$TMPDIR_SELFTEST/r.md" "0" "none"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/r.md" > /dev/null 2>&1; then
    echo "self-test (r) check11-pass-rung0-no-section-needed: PASS (expected)" >&2
  else
    echo "self-test (r) check11-pass-rung0-no-section-needed: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (s): rung 3 with all 4 sub-entries substantive — expect PASS
  write_bc_plan "$TMPDIR_SELFTEST/s.md" "3" "all_substantive"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/s.md" > /dev/null 2>&1; then
    echo "self-test (s) check11-pass-rung3-substantive: PASS (expected)" >&2
  else
    echo "self-test (s) check11-pass-rung3-substantive: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (t): rung 3 with no Behavioral Contracts section — expect FAIL
  write_bc_plan "$TMPDIR_SELFTEST/t.md" "3" "none"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/t.md" > /dev/null 2>&1; then
    echo "self-test (t) check11-fail-rung3-section-missing: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (t) check11-fail-rung3-section-missing: FAIL (expected)" >&2
  fi

  # Scenario (u): rung 3 with only 2 of 4 sub-entries — expect FAIL
  write_bc_plan "$TMPDIR_SELFTEST/u.md" "3" "missing_subentry"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/u.md" > /dev/null 2>&1; then
    echo "self-test (u) check11-fail-rung3-subentry-missing: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (u) check11-fail-rung3-subentry-missing: FAIL (expected)" >&2
  fi

  # Scenario (v): rung 3 with all 4 sub-entries but Idempotency body
  # is "[populate me]" — expect FAIL
  write_bc_plan "$TMPDIR_SELFTEST/v.md" "3" "placeholder_subentry"
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/v.md" > /dev/null 2>&1; then
    echo "self-test (v) check11-fail-rung3-subentry-placeholder: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (v) check11-fail-rung3-subentry-placeholder: FAIL (expected)" >&2
  fi

  # ============================================================
  # Phase 1d-E-1 Task 1 scenarios (w, x, y, z) — Check 1
  # section-awareness + Check 5 context-awareness narrowing
  # ============================================================
  #
  # (w) Plan with `## Definition of Done` containing a checkbox using the
  #     word "all" — expect PASS (Check 1 must skip non-Tasks sections).
  # (x) Plan with `## Tasks` containing a documentation-context use of
  #     `table` (e.g., "add row to harness-architecture.md inventory
  #     table") — expect PASS (Check 5 Tier B keyword without DB /
  #     runtime context must NOT flag).
  # (y) Plan with `## Tasks` containing a real undecomposed sweep
  #     ("Wire RequiredLabel into all forms") — expect FAIL
  #     (regression check — genuine sweeps are still caught).
  # (z) Plan with `## Tasks` containing a real database-context runtime
  #     task ("Add new column to org_settings table via migration")
  #     without a Test:/Runtime verification: spec — expect FAIL
  #     (regression check — legitimate runtime tasks are still caught).

  # write_check15_plan: minimal Mode: code, Status: ACTIVE plan with
  # all required sections satisfied; the Tasks block and the Definition
  # of Done block are parameterized per scenario.
  write_check15_plan() {
    # $1 = output path
    # $2 = tasks_block (full multi-line content under `## Tasks`)
    # $3 = dod_block (full multi-line content under `## Definition of Done`)
    local out="$1"
    local tasks_block="$2"
    local dod_block="$3"

    cat > "$out" <<'CHECK15_HEAD'
# Plan: Self-test Phase 1d-E-1 Task 1 fixture
Status: ACTIVE
Mode: code
Backlog items absorbed: none
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal
Exercise the Check 1 section-awareness + Check 5 context-awareness
narrowing introduced for HARNESS-GAP-09. The fixture parameterizes
the Tasks and Definition of Done sections so the false-positive and
true-positive cases are each covered.

## Scope
- IN: Check 1 + Check 5 narrowing under Phase 1d-E-1 Task 1
- OUT: anything else; the fixture is single-purpose

CHECK15_HEAD

    {
      echo "## Tasks"
      echo ""
      echo "$tasks_block"
      echo ""
    } >> "$out"

    cat >> "$out" <<'CHECK15_MID'
## Files to Modify/Create
- `hooks/plan-reviewer.sh` — Check 1 + Check 5 narrowing under exercise

## Assumptions
- Assumes Check 6b passes for this fixture so the Check 1 + Check 5
  outcomes are the only variables across w/x/y/z scenarios.

## Edge Cases
- The fixture must satisfy Check 6b's required sections so the only
  failing path is Check 1 or Check 5 itself.

## Testing Strategy
- Run plan-reviewer.sh against this fixture in each variant; observe
  the exit code matches the scenario expectation.

Walking Skeleton: n/a — self-test fixture, no runtime user-facing slice.

CHECK15_MID

    {
      echo "## Definition of Done"
      echo ""
      echo "$dod_block"
    } >> "$out"
  }

  # Scenario (w): DoD checkbox uses "All" — must NOT trigger Check 1.
  # The DoD bullet "All tests pass" is the canonical example of plural
  # language outside a task list.
  write_check15_plan "$TMPDIR_SELFTEST/w.md" \
    "- [ ] 1. Refactor a single helper module to use the new pattern." \
    "- [ ] All tests pass after refactor."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/w.md" > /dev/null 2>&1; then
    echo "self-test (w) check1-section-aware-dod-with-all-keyword: PASS (expected)" >&2
  else
    echo "self-test (w) check1-section-aware-dod-with-all-keyword: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (x): Tasks line contains the Tier B keyword `table` in a
  # documentation context with NO database / runtime context tokens
  # nearby. Must NOT trigger Check 5.
  write_check15_plan "$TMPDIR_SELFTEST/x.md" \
    "- [ ] 1. Add a row to harness-architecture.md inventory table documenting the new hook." \
    "- [ ] Inventory row added."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/x.md" > /dev/null 2>&1; then
    echo "self-test (x) check5-context-aware-doc-table-no-db-context: PASS (expected)" >&2
  else
    echo "self-test (x) check5-context-aware-doc-table-no-db-context: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (y): Tasks line is a genuine undecomposed sweep ("all
  # forms") under `## Tasks` — Check 1 MUST still flag this. Regression
  # check confirming we didn't break true-positive detection.
  write_check15_plan "$TMPDIR_SELFTEST/y.md" \
    "- [ ] 1. Wire RequiredLabel into all forms across the codebase." \
    "- [ ] Forms updated."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/y.md" > /dev/null 2>&1; then
    echo "self-test (y) check1-real-sweep-still-caught: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (y) check1-real-sweep-still-caught: FAIL (expected)" >&2
  fi

  # Scenario (z): Tasks line contains a Tier A keyword (`migration`)
  # AND Tier B keywords (`column`, `table`) WITH database-context
  # tokens (`migration`, `schema`-ish via "table" wording) — Check 5
  # MUST still flag this because there's no Test:/Runtime verification:
  # spec. Regression check confirming legitimate runtime tasks are
  # still caught.
  write_check15_plan "$TMPDIR_SELFTEST/z.md" \
    "- [ ] 1. Add new column to org_settings table via migration." \
    "- [ ] Schema change applied."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/z.md" > /dev/null 2>&1; then
    echo "self-test (z) check5-real-database-task-still-caught: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (z) check5-real-database-task-still-caught: FAIL (expected)" >&2
  fi

  # ============================================================
  # Check 12 scenarios (vd1, vd2, vd3) — risk-tiered verification
  # field (Tranche D of architecture-simplification, 2026-05-05)
  # ============================================================
  #
  # (vd1) Plan with valid `Verification: mechanical` declaration on a
  #       task line — expect PASS (legal level).
  # (vd2) Plan with unmarked tasks (no Verification: field) — expect
  #       PASS (default `full` applies; backward-compatible behavior).
  # (vd3) Plan with invalid `Verification: bogus` declaration on a task
  #       line — expect FAIL (only mechanical/full/contract are legal).
  #
  # Fixtures reuse the `write_check15_plan` writer because it already
  # produces a plan that passes every other check. We vary only the
  # task-block content to isolate Check 12's outcome.

  # Scenario (vd1): legal `mechanical` level
  write_check15_plan "$TMPDIR_SELFTEST/vd1.md" \
    "- [ ] 1. Author the new helper module per the goal — Verification: mechanical" \
    "- [ ] Helper authored."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/vd1.md" > /dev/null 2>&1; then
    echo "self-test (vd1) check12-valid-mechanical-level: PASS (expected)" >&2
  else
    echo "self-test (vd1) check12-valid-mechanical-level: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (vd2): no Verification field (default-full backward compat)
  write_check15_plan "$TMPDIR_SELFTEST/vd2.md" \
    "- [ ] 1. Refactor a single helper module to use the new pattern." \
    "- [ ] Helper refactored."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/vd2.md" > /dev/null 2>&1; then
    echo "self-test (vd2) check12-default-full-no-field: PASS (expected)" >&2
  else
    echo "self-test (vd2) check12-default-full-no-field: FAIL (expected PASS)" >&2
    FAILED=1
  fi

  # Scenario (vd3): illegal level value
  write_check15_plan "$TMPDIR_SELFTEST/vd3.md" \
    "- [ ] 1. Author the new helper module per the goal — Verification: bogus" \
    "- [ ] Helper authored."
  if bash "$SCRIPT" "$TMPDIR_SELFTEST/vd3.md" > /dev/null 2>&1; then
    echo "self-test (vd3) check12-illegal-level-rejected: PASS (expected FAIL)" >&2
    FAILED=1
  else
    echo "self-test (vd3) check12-illegal-level-rejected: FAIL (expected)" >&2
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
#
# Section-aware (Phase 1d-E-1 Task 1): only flag sweep language when the
# matching line is under a `## ` heading whose title contains "Task" (case
# -insensitive — matches "## Tasks", "## Implementation Tasks", etc.).
# Headings like `## Definition of Done`, `## Acceptance Scenarios`,
# `## Out-of-scope scenarios`, `## Pre-Submission Audit`, etc. are NOT
# task-list sections; sweep-style language there is documentation, not
# undecomposed work, and false-positive findings on those headings have
# blocked legitimate plans (HARNESS-GAP-09).

# Walk the file with awk, emitting "<lineno>:<task-line>" only for sweep
# matches that fall under a Tasks-class heading. The state machine resets
# in_tasks_section to 0 on every `## ` heading and to 1 only when the
# heading title contains "Task" (case-insensitive). Sub-headings (`### `,
# `#### `) inherit the parent `## ` section's classification — they don't
# change the mode.
SWEEP_LINES=$(awk '
  BEGIN { in_tasks_section = 0 }
  /^## / {
    # Top-level section heading. Reset state, then check the title.
    title = $0
    sub(/^## +/, "", title)
    if (tolower(title) ~ /task/) {
      in_tasks_section = 1
    } else {
      in_tasks_section = 0
    }
    next
  }
  in_tasks_section && /^- \[[ xX]\][[:space:]]+.*(all[[:space:]]+[[:alnum:]_]+|every[[:space:]]+[[:alnum:]_]+|throughout|across[[:space:]]+the[[:space:]]+codebase|in[[:space:]]+every)/ {
    print NR ":" $0
  }
' "$PLAN_FILE" 2>/dev/null || true)

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
#
# Context-aware (Phase 1d-E-1 Task 1): the keyword list is split into two
# tiers. Tier A keywords are unambiguously runtime — finding any of them
# in an unchecked task always demands a test spec. Tier B keywords are
# context-dependent: words like `column`, `table`, `notification`,
# `trigger`, `component`, `UI` show up in documentation contexts (e.g.,
# "add a row to the inventory table", "wire RequiredLabel into the
# template column") just as often as they show up in runtime contexts.
# A Tier B keyword counts as runtime ONLY if a database / runtime
# context token is on the SAME line OR the NEXT line. Otherwise the
# task is treated as documentation work and is not flagged.
#
# This narrowing closes HARNESS-GAP-09 false-positives where harness-
# development plans referencing "the column in harness-architecture.md
# inventory table" tripped the runtime-keyword regex.

RUNTIME_KEYWORDS_TIER_A='(\b(page|route|button|form|webhook|cron|scheduled|endpoint|API|migration|RLS[[:space:]]+policy|auth[[:space:]]+flow)\b)'
RUNTIME_KEYWORDS_TIER_B='(\b(column|table|notification|trigger|component|UI)\b)'
DB_RUNTIME_CONTEXT='(\b(INSERT|SELECT|UPDATE|DELETE|migration|enum|schema|RLS|database|Supabase|SQL|click|render|screen|viewport)\b)'

UNSPEC_RUNTIME=""
UNSPEC_COUNT=0

# Pass 1: Tier A — always treated as runtime.
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
done < <(grep -nE "^- \[ \].*${RUNTIME_KEYWORDS_TIER_A}" "$PLAN_FILE" 2>/dev/null)

# Pass 2: Tier B — only count if a DB / runtime context token is on the
# same line as the Tier B keyword OR on the next line. The match is
# treated as runtime only when both conditions hold: the unchecked task
# line contains a Tier B keyword AND adjacency-context check passes.
while IFS= read -r task_match; do
  [[ -z "$task_match" ]] && continue
  ln=$(echo "$task_match" | cut -d: -f1)
  task_text=$(echo "$task_match" | cut -d: -f2-)

  # Skip if the line was already counted via Tier A (avoid double-flag
  # when both Tier A and Tier B keywords appear).
  if echo "$task_text" | grep -qE "${RUNTIME_KEYWORDS_TIER_A}"; then
    continue
  fi

  # Adjacency check: does the same line OR the next line contain a
  # database / runtime context token?
  same_line="$task_text"
  next_line=$(sed -n "$((ln+1))p" "$PLAN_FILE")
  if ! echo "$same_line"$'\n'"$next_line" | grep -qiE "${DB_RUNTIME_CONTEXT}"; then
    # Tier B keyword without DB / runtime context — treat as documentation,
    # not runtime. Skip.
    continue
  fi

  # Look at the next 10 lines for test spec language
  context=$(sed -n "$ln,$((ln+10))p" "$PLAN_FILE")
  if ! echo "$context" | grep -qiE 'Test(\s*file)?:|Runtime verification:|tests/[a-z]+/[a-z]'; then
    UNSPEC_RUNTIME+="    line $ln: $(echo "$task_text" | head -c 80)"$'\n'
    UNSPEC_COUNT=$((UNSPEC_COUNT + 1))
  fi
done < <(grep -nE "^- \[ \].*${RUNTIME_KEYWORDS_TIER_B}" "$PLAN_FILE" 2>/dev/null)

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
# Check 10 (Phase 1d-C-2): 5-field plan-header schema
# ============================================================
#
# Per Decision 017 (plan-header-schema-locked) + Build Doctrine §9 Q4-A,
# every plan with `Status: ACTIVE` must declare all five header fields:
#
#   tier:         must be 1, 2, 3, 4, or 5
#   rung:         must be 0, 1, 2, 3, 4, or 5
#   architecture: must be one of {coding-harness, dark-factory,
#                 auto-research, orchestration, hybrid}
#   frozen:       must be true or false
#   prd-ref:      must be non-empty (semantic validation belongs to C1
#                 prd-validity-gate.sh, not this schema check)
#
# Mode-agnostic — fires on Mode: code AND Mode: design AND Mode: design-skip.
# Status-gated: only ACTIVE plans need fresh schema. The hook early-exits
# on COMPLETED/ABANDONED/DEFERRED at the top of the script (line 484), so
# we only see ACTIVE (or empty) plans here.
#
# Each missing or invalid field produces ONE finding. The findings list
# all problems for the planner so the fix is one round-trip rather than
# five.

# Re-extract Status using awk (more portable than grep -P, which fails on
# some locales — notably Windows Git Bash). The original $STATUS extraction
# at line ~483 may be empty on these systems; using awk here keeps Check 10
# robust against that failure mode without modifying pre-existing code.
STATUS_AWK=$(awk -F: '/^Status:/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }' "$PLAN_FILE" 2>/dev/null)

# Extract the 5 schema fields unconditionally so Check 11 (which keys on
# RUNG_VALUE) sees a defined value even when Check 10 early-exits on
# non-ACTIVE Status. Required for `set -u` compatibility — referencing an
# unset variable below would otherwise abort the script.
TIER_VALUE=$(awk -F: '/^tier:/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }' "$PLAN_FILE" 2>/dev/null)
RUNG_VALUE=$(awk -F: '/^rung:/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }' "$PLAN_FILE" 2>/dev/null)
ARCH_VALUE=$(awk -F: '/^architecture:/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }' "$PLAN_FILE" 2>/dev/null)
FROZEN_VALUE=$(awk -F: '/^frozen:/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }' "$PLAN_FILE" 2>/dev/null)
# prd-ref may contain colons in its value (e.g., "n/a — harness-development"),
# so we capture everything after the first colon.
PRD_REF_VALUE=$(awk '/^prd-ref:/ { sub(/^prd-ref:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$PLAN_FILE" 2>/dev/null)

if [[ "$STATUS_AWK" == "ACTIVE" ]] || [[ -z "$STATUS_AWK" ]]; then
  # tier ∈ {1,2,3,4,5}
  if [[ -z "$TIER_VALUE" ]]; then
    add_finding "Check 10 (plan-header schema): required field 'tier:' is missing. Add 'tier: <1-5>' to the plan header. See Decision 017 in docs/decisions/."
  elif ! [[ "$TIER_VALUE" =~ ^(1|2|3|4|5)$ ]]; then
    add_finding "Check 10 (plan-header schema): field 'tier:' has invalid value '$TIER_VALUE'. Must be one of: 1, 2, 3, 4, 5. See Decision 017."
  fi

  # rung ∈ {0,1,2,3,4,5}
  if [[ -z "$RUNG_VALUE" ]]; then
    add_finding "Check 10 (plan-header schema): required field 'rung:' is missing. Add 'rung: <0-5>' to the plan header. See Decision 017."
  elif ! [[ "$RUNG_VALUE" =~ ^(0|1|2|3|4|5)$ ]]; then
    add_finding "Check 10 (plan-header schema): field 'rung:' has invalid value '$RUNG_VALUE'. Must be one of: 0, 1, 2, 3, 4, 5. See Decision 017."
  fi

  # architecture ∈ {coding-harness, dark-factory, auto-research, orchestration, hybrid}
  if [[ -z "$ARCH_VALUE" ]]; then
    add_finding "Check 10 (plan-header schema): required field 'architecture:' is missing. Add 'architecture: <coding-harness|dark-factory|auto-research|orchestration|hybrid>' to the plan header. See Decision 017."
  elif ! [[ "$ARCH_VALUE" =~ ^(coding-harness|dark-factory|auto-research|orchestration|hybrid)$ ]]; then
    add_finding "Check 10 (plan-header schema): field 'architecture:' has invalid value '$ARCH_VALUE'. Must be one of: coding-harness, dark-factory, auto-research, orchestration, hybrid. See Decision 017."
  fi

  # frozen ∈ {true, false}
  if [[ -z "$FROZEN_VALUE" ]]; then
    add_finding "Check 10 (plan-header schema): required field 'frozen:' is missing. Add 'frozen: <true|false>' to the plan header. See Decision 016 (spec-freeze) and Decision 017 (schema)."
  elif ! [[ "$FROZEN_VALUE" =~ ^(true|false)$ ]]; then
    add_finding "Check 10 (plan-header schema): field 'frozen:' has invalid value '$FROZEN_VALUE'. Must be 'true' or 'false'. See Decision 016."
  fi

  # prd-ref non-empty (semantic validation by prd-validity-gate.sh / C1)
  if [[ -z "$PRD_REF_VALUE" ]]; then
    add_finding "Check 10 (plan-header schema): required field 'prd-ref:' is missing or empty. For harness-development plans use 'prd-ref: n/a — harness-development'; otherwise reference a PRD slug resolving to docs/prd.md. See Decision 015 (PRD format) and Decision 017 (schema)."
  fi
fi

# ============================================================
# Check 11 (Phase 1d-C-2 / C16): Behavioral Contracts at rung >= 3
# ============================================================
#
# Per Build Doctrine §6 C16, plans operating at Rung 3+ (where the
# integration touches multi-component coordination) MUST declare a
# `## Behavioral Contracts` section with four named sub-entries:
#
#   ### Idempotency
#   ### Performance budget
#   ### Retry semantics
#   ### Failure modes
#
# Each sub-entry must have >= 30 non-whitespace chars after stripping
# HTML comments and standard placeholder tokens (mirrors Check 6b's
# substance check, but with a slightly higher threshold for the more
# specific behavioral commitments).
#
# Mode-agnostic. Status-gated to ACTIVE (or empty, treated as nascent
# plan-in-creation): terminal-Status plans don't need behavioral-contract
# review. The pre-existing line-484 early-exit covers this on Linux
# but may fall through on Windows Git Bash where grep -P fails — so we
# defensively gate on STATUS_AWK here too.
# Rung-gated: rung 0/1/2 → no behavioral contracts required.

if { [[ "$STATUS_AWK" == "ACTIVE" ]] || [[ -z "$STATUS_AWK" ]]; } && [[ "$RUNG_VALUE" =~ ^(3|4|5)$ ]]; then
  # Required parent section
  BC_LN=$(grep -nE '^## Behavioral Contracts\s*$' "$PLAN_FILE" 2>/dev/null | head -1 | cut -d: -f1)

  if [[ -z "$BC_LN" ]]; then
    add_finding "Check 11 (C16 behavioral contracts): plan declares 'rung: $RUNG_VALUE' but lacks '## Behavioral Contracts' section. Required at rung 3+. The section must contain four sub-headings: '### Idempotency', '### Performance budget', '### Retry semantics', '### Failure modes', each with >= 30 non-whitespace chars of substance. See Build Doctrine §6 C16."
  else
    # Required sub-headings (case-insensitive variants tolerated for
    # human-author flexibility: "Performance budget" / "Performance Budget").
    BC_REQUIRED_SUBS=(
      "Idempotency"
      "Performance budget"
      "Retry semantics"
      "Failure modes"
    )

    # check_bc_subsection: extract body of '### <name>' under the parent
    # section and assert >= 30 non-ws chars after HTML-comment + placeholder
    # stripping. Mirrors check_required_section's body-extraction shape.
    check_bc_subsection() {
      local sub="$1"
      local sub_pattern
      sub_pattern="$(printf '%s' "$sub" | sed 's/[][\/.^$*]/\\&/g')"
      # Locate the sub-heading within the Behavioral Contracts section only.
      # We find the line number of the sub-heading; if absent, finding.
      # The match is case-insensitive on the heading text to allow
      # "Performance Budget" or "Performance budget" variants.
      local sub_ln
      sub_ln=$(awk -v start="$BC_LN" -v pat="^### ${sub_pattern}\\s*\$" '
        BEGIN { IGNORECASE = 1 }
        NR == start { in_bc = 1; next }
        in_bc && /^## / { exit }
        in_bc && $0 ~ pat { print NR; exit }
      ' "$PLAN_FILE" 2>/dev/null)

      if [[ -z "$sub_ln" ]]; then
        add_finding "Check 11 (C16 behavioral contracts): required sub-heading '### $sub' is missing from '## Behavioral Contracts' section. All four sub-headings (Idempotency, Performance budget, Retry semantics, Failure modes) are required at rung 3+."
        return
      fi

      # Extract the sub-section body up to the next '### ' or '## '
      local body
      body=$(awk -v start="$sub_ln" '
        NR == start { next }
        NR > start {
          if ($0 ~ /^### / || $0 ~ /^## /) exit
          print
        }
      ' "$PLAN_FILE" 2>/dev/null | awk '
        /<!--/ { in_comment = 1 }
        !in_comment { print }
        /-->/ { in_comment = 0 }
      ')

      # Normalize for placeholder-token check
      local normalized
      normalized=$(printf '%s' "$body" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

      # Count non-whitespace chars
      local non_ws_count
      non_ws_count=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
      non_ws_count=${non_ws_count:-0}

      if [[ $non_ws_count -lt 30 ]]; then
        add_finding "Check 11 (C16 behavioral contracts): sub-section '### $sub' is empty or too short (only $non_ws_count non-whitespace chars; needs >= 30). Document the concrete invariant the implementation must uphold. See Build Doctrine §6 C16."
        return
      fi

      # Placeholder-only check: strip placeholder tokens and re-test
      local stripped="$normalized"
      for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
        stripped=$(printf '%s' "$stripped" | sed -E "s|${pat}||g")
      done
      stripped=$(printf '%s' "$stripped" | sed -E 's|[[:space:]]*[-*][[:space:]]*||g; s|[][(){}:;,.!?"`'"'"']||g')
      stripped=$(printf '%s' "$stripped" | tr -d '[:space:]')

      if [[ -z "$stripped" ]]; then
        add_finding "Check 11 (C16 behavioral contracts): sub-section '### $sub' contains only placeholder text (e.g., '[populate me]', 'TODO', or template prompt). Replace with the concrete behavioral invariant. See Build Doctrine §6 C16."
        return
      fi
    }

    # Run the check for each required sub-heading. Report first offender
    # and break (mirrors the pattern of check_required_section invocation
    # at line 744).
    for sub in "${BC_REQUIRED_SUBS[@]}"; do
      PREV_COUNT=$FINDING_COUNT
      check_bc_subsection "$sub"
      if [[ $FINDING_COUNT -gt $PREV_COUNT ]]; then
        break
      fi
    done
  fi
fi

# ============================================================
# Check 12 (Tranche D of architecture-simplification, 2026-05-05):
# Risk-tiered Verification field validation
# ============================================================
#
# Each `## Tasks` checkbox line MAY end with `Verification: <level>`
# where <level> ∈ {mechanical, full, contract}. The default for unmarked
# tasks is `full` (backward-compatible — every existing plan in
# docs/plans/ predates this rule and tasks there are implicitly `full`).
#
# This check fires on every plan regardless of Mode/rung/Status. It scans
# task-checkbox lines for the `Verification:` token and rejects any token
# value that isn't one of the three legal levels.
#
# Mode-agnostic. Status-agnostic for new-plan creation: even DEFERRED
# plans benefit from a quick syntax check on their task list.
#
# See ~/.claude/rules/risk-tiered-verification.md for level semantics.

# Scan task-checkbox lines under any heading whose title contains "Task"
# (case-insensitive — matches "## Tasks", "## Implementation Tasks", etc.).
# Reuses the section-aware awk pattern from Check 1.
VERIFICATION_LINES=$(awk '
  BEGIN { in_tasks_section = 0 }
  /^## / {
    title = $0
    sub(/^## +/, "", title)
    if (tolower(title) ~ /task/) {
      in_tasks_section = 1
    } else {
      in_tasks_section = 0
    }
    next
  }
  in_tasks_section && /^- \[[ xX]\]/ && /Verification:/ {
    print NR ":" $0
  }
' "$PLAN_FILE" 2>/dev/null || true)

if [[ -n "$VERIFICATION_LINES" ]]; then
  while IFS= read -r vline; do
    [[ -z "$vline" ]] && continue
    vln=$(echo "$vline" | cut -d: -f1)
    vtext=$(echo "$vline" | cut -d: -f2-)
    # Extract the token immediately after `Verification:`. Strip any
    # surrounding whitespace and trailing punctuation/markers.
    vlevel=$(echo "$vtext" | sed -nE 's/.*Verification:[[:space:]]+([A-Za-z][A-Za-z_-]*).*/\1/p' | head -1)
    if [[ -z "$vlevel" ]]; then
      add_finding "Check 12 (risk-tiered verification): line $vln has 'Verification:' but no readable level token. Use one of: mechanical, full, contract. See ~/.claude/rules/risk-tiered-verification.md."
      continue
    fi
    if ! [[ "$vlevel" =~ ^(mechanical|full|contract)$ ]]; then
      add_finding "Check 12 (risk-tiered verification): line $vln declares 'Verification: $vlevel' but the only legal levels are: mechanical, full, contract (case-sensitive, lowercase). See ~/.claude/rules/risk-tiered-verification.md."
    fi
  done <<< "$VERIFICATION_LINES"
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
