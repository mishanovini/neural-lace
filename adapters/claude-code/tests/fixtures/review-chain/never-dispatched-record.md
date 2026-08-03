# Fixture Review Record: harness-reviewer, never actually dispatched

**Reviewer:** harness-reviewer (model: fable, dispatched by gated-pipeline Task 1's self-test fixture setup)
**Reviewed:** adapters/claude-code/tests/fixtures/review-chain/never-dispatched-plan.md @ 6a9a8d052151ef8f1d9487a5b652584305c4c6d2
**Reviewed at:** 2026-08-03

## Verdict: PASS

Well-formed on its face (rules 1 and 2 pass) — the point of this fixture is
that NO row of type `harness-reviewer` exists anywhere in this directory's
`dispatch-ledger.jsonl`, so rule 3 fails with "never dispatched." This is
the record a forged/hallucinated review would look like.
