---
shape_id: write-self-test
category: test
required_files:
  - "<script>.sh containing a --self-test invocation block"
mechanical_checks:
  - "grep -q -- '--self-test' <script>.sh"
  - "bash <script>.sh --self-test 2>&1 | grep -F 'self-test: OK'"
  - "echo $? : 0"
  - "grep -q -E 'self-test (PASS|FAIL|OK)' <script>.sh"
worked_example: adapters/claude-code/hooks/harness-hygiene-scan.sh
---

# Work Shape — Write Self-Test

## When to use

Whenever a bash mechanism (hook, gate, validator, sweep) is created or modified. The `write-self-test` shape composes inline with `build-hook` — every hook ships a `--self-test` block — but it also stands alone for any standalone bash mechanism not invoked as a Claude Code hook (helper scripts, sweep utilities, install scaffolding).

A self-test makes the mechanism regression-testable. Without one, adjacent code changes silently break behavior; the harness has no way to detect the breakage until it produces a downstream failure.

## Structure

A compliant `--self-test` block provides:

1. **A handler at script entry point** — when invoked with `--self-test` (typically the first arg), the script runs internal assertions and exits with `0` on PASS, non-zero on FAIL. No external side effects.
2. **Synthetic test scenarios** — tmp directories, in-line stdin, mocked file contents. Each scenario exercises one branch of the script's logic: at minimum the happy path, the block / fail path, and one edge case (empty input, missing file, etc.).
3. **Assertion helpers** — typically a small `_assert` function that takes a description, an expected value, and an actual value; prints `PASS` or `FAIL: <description>` per case.
4. **Final summary line** — `self-test: OK` (all assertions passed) or `self-test: FAIL — N failures`. Downstream consumers (`tool-call-budget.sh --ack`, CI workflows, mechanical-compliance checks) grep for this exact string.
5. **Cleanup** — tmp directories removed, temp files deleted. Self-test must not leak state.

## Common pitfalls

- **Self-test invokes the real environment.** If the test reads from `~/.claude/state/` or `docs/plans/`, it can corrupt session state. Always use synthetic tmp dirs created at test time.
- **Only happy-path tested.** A self-test that exercises only the success branch does not protect against regressions in the failure branch — and the failure branch is usually where the gate's value lives.
- **Final summary line drifts.** If the script prints `self-test passed` instead of `self-test: OK`, the grep-based mechanical check fails. Lock the exact string.
- **No cleanup on FAIL path.** When an assertion fails, tmp dirs leak. Use `trap` to ensure cleanup runs regardless of exit.
- **Missing exit-code propagation.** A self-test that prints FAIL but exits 0 silently passes CI. Track failure count and exit non-zero when count > 0.
- **Ten-scenario explosion without dedicated harness.** Once the scenario count exceeds ~5, the inline self-test becomes hard to maintain. Consider extracting to a sibling `tests/<name>.bats` file (Bats framework) and keeping the inline `--self-test` as a smoke test.

## Worked example walk-through

`adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test` exemplifies the shape:

- Self-test handler dispatched from arg parsing at top of script.
- Creates synthetic tmp dir; populates with synthetic files matching / not matching denylist patterns.
- Per-scenario assertions for: clean-content allows, denylist-match blocks, exempt-path bypasses, full-tree mode scans correctly.
- Each assertion prints PASS / FAIL with descriptive label.
- Final summary: `self-test: OK` or `self-test: FAIL — N failures`.
- Tmp dir cleaned via `trap` regardless of exit path.
- Documented in the script's invocation-mode header so users discover it.
