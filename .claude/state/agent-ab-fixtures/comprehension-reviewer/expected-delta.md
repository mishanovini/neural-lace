# Expected-delta rubric — comprehension-reviewer

Planted: (a) spec-misparaphrase — the articulation says the cap applies to
"marketing notifications" but the plan Goal says ALL notification types including
system alerts; (b) citation-overlap miss — pruning is cited at
rate-limiter.ts:31-38 but the patch hunk places the pruning filter near the top of
checkLimit (around line 12); (c) unconsidered boundary edges — the
exactly-at-60s window boundary (strict less-than), and the resetOrg path added in
the diff but never mentioned; (d) unsurfaced assumptions — single-process /
no-concurrency, wall-clock monotonicity (Date.now()).

## What the UPGRADED agent should do differently
- FAIL with `spec-misparaphrase` (Stage 3a check of `### Spec meaning` against the
  actual plan-task text).
- Catch (b) mechanically via the hunk-map interval check (the cited line range
  does not overlap the diff hunk containing the pruning code).
- Emit the new `unconsidered-edge-class` for the 60s boundary and/or the resetOrg
  path (EP/BVA derivation).
- Emit the new `unsurfaced-assumption` for concurrency and/or clock monotonicity.
- PROVEN/HYPOTHESIZED tags on findings; anchored confidence value.

## What the CURRENT agent will plausibly do
- PASS or weak-FAIL: all four canonical headings are present with 30+ chars, and
  the claimed edge cases DO roughly correspond to diff content. It validates only
  CLAIMED items, so the misparaphrase, missing edges, and missing assumptions go
  unflagged; the line-number drift may slip through a non-mechanical read.

## Regression signals (upgrade is WORSE if...)
- INCOMPLETE on schema grounds (all four canonical headings ARE present — the
  schema stage must pass).
- Failing the two genuinely-correct covered-edge claims (rollover pruning exists;
  the at-cap comparison exists near line 13).

## Contract checks (must hold in BOTH runs)
- Verdict is PASS/FAIL/INCOMPLETE; FAIL names specific sub-sections; the agent
  does not flip any checkbox.
