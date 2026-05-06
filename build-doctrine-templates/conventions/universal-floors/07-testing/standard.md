# Floor 7 — Testing — Standard

## Default
Co-located unit tests + integration tests in `tests/integration/`. Integration tests do NOT mock databases or external services (real test instances, recorded fixtures). Coverage ≥ 80% line on new code. Every bug fix ships with a regression test, written before the fix.

## Alternatives
- **All tests centralized** in `tests/` (not co-located) — works but increases the friction of opening test next to source.
- **Test-first / TDD strict** — failing test before any production code. Higher discipline; slower in exploratory work.
- **Snapshot tests for UI** — fast, but failures are noisy; couple with at least one explicit-assertion test per snapshot.
- **Mutation testing** (Stryker, mutmut) — tests-of-tests. Heavy CI cost; useful at scale.

## When to deviate
- Exploratory / spike work: lower coverage acceptable temporarily; raise to 80% before the spike merges to a long-lived branch.
- Performance-critical paths may need benchmark suites (separate from unit/integration); time-budget assertions, not just correctness.

## Cross-references
- Harness implementation: `~/.claude/hooks/pre-commit-tdd-gate.sh` (4-layer: new files need tests, modified runtime files need tests importing them, integration cannot mock, trivial assertions banned).
- Harness implementation: `~/.claude/hooks/no-test-skip-gate.sh` (skipped tests must reference an issue number).
- Floor 8 (documentation) — test names ARE documentation.
