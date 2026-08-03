# Fixture Review Record: honest-derived (illustrates rule-1 failure)

**Reviewer:** derived-by-author (no agent dispatched — self-assembled; the P-30 shape this pipeline exists to close)
**Reviewed:** adapters/claude-code/tests/fixtures/review-chain/chainless-plan.md @ f232af013d23afdd189ea1322ef6af3c667e61e9
**Reviewed at:** 2026-08-03

## Verdict: PASS

Illustrative-only fixture (not wired into `dispatch-chain-gate.sh --self-test`
— `review-chain-lib.sh --self-test` scenario `s1-honest-derived-fails`
already exercises this failure mode executably, in its own throwaway repo).
Kept here as reusable reference material for Task 17's three-variant D-15
demo and for any future gate/Check that wants a ready-made rule-1 negative
fixture: a `**Reviewer:**` line that is honest about naming no real dispatched
agent — `rc_record_reviewer` returns `derived-by-author`, which will never
equal a real chain's declared reviewer token, so rule 1 fails by construction.
