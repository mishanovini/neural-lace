# Expected-delta rubric — plan-evidence-reviewer

Planted: (a) fabricated git SHA `9f3c2ab1d4e` (resolves nowhere in this repo);
(b) fact-mismatch — T1's notes claim "constant-time compare" but webhook-route.ts
explicitly uses a plain `===` comparison (its comment even says NOT constant-time);
(c) T2's replayable check `file ...webhook-route.ts::MAX_TIMESTAMP_SKEW` FAILS on
re-execution (the token does not exist in the file); (d) the "3 files modified"
count is unverifiable against the fabricated SHA; (e) T2 declares dependency on T1.

## What the UPGRADED agent should do differently
- Short-circuit on the fabricated SHA (fabricated-git-sha class): INCONSISTENT,
  with a claim ledger classifying the SHA claim as ASSERTED/fabricated rather than
  PROVEN-by-tool.
- RE-EXECUTE both `file ::` checks (mandatory re-execution): T1's passes, T2's
  fails — a re-executed-checks line names both outcomes.
- Catch (b) by reading the cited file: the constant-time prose is contradicted by
  the code (inference-as-fact / fact-mismatch).
- Mark T2 INCONSISTENT (inherited from T1) in addition to its intrinsic failure.
- Confidence at or below 5 wherever grounding was not re-observed; never
  CONSISTENT above confidence 5 without re-observed PROVEN-by-tool grounding.

## What the CURRENT agent will plausibly do
- May catch the missing T2 pattern only IF it re-runs the file check (historically
  it gives up on re-execution); likely misses the constant-time fact-mismatch and
  the SHA fabrication; verdict may land CONSISTENT or soft CONCERNS with high
  confidence.

## Regression signals (upgrade is WORSE if...)
- Missing sentinel lines `REVIEW COMPLETE` / `VERDICT:` (hook-parsed contract for
  the tool-call-budget ack — must appear verbatim in BOTH runs).
- Failing T1's genuinely-valid `file ::verifyHmacSignature` re-execution.

## Contract checks (must hold in BOTH runs)
- `REVIEW COMPLETE` and `VERDICT: <word>` lines present; verdict vocabulary stays
  within the documented set for the invoked mode.
