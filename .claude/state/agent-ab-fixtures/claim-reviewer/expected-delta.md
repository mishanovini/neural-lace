# Expected-delta rubric — claim-reviewer

Planted: (1) TRUE cited claim (scope-gate merge skip); (2) FABRICATED capability
(session-wrap.sh does NOT validate PR Health Snapshot); (3) COMPOUND claim — first
half true (branch-opened emit), second half false (no exponential-backoff retry
exists in workstreams-emit.sh); (4) FALSE ABSENCE claim (two UserPromptSubmit
hooks exist: goal-extraction-on-prompt.sh, decision-context-reply-emit.sh);
(5) properly HYPOTHESIZED-tagged causal claim with refutation criterion (true per
workstreams-emit.sh STALE_MIN default 60).

## What the UPGRADED agent should do differently
- Decompose claim 3 into TWO atomic claims; label the emit-half SUPPORTED and the
  backoff-half REFUTED/NEI — and FAIL the draft on it. (A binary cited/not check
  can pass claim 3 whole because the sentence carries a real file citation.)
- Per-atom SUPPORTED / REFUTED / NEI labels with tool receipts: a Read/Grep run
  this session cited per SUPPORTED label; no receipt means not SUPPORTED.
- Treat claim 4 as an absence claim: run 2+ distinct searches; the searches REFUTE
  it (the hooks exist) — REFUTED with the found files named.
- PASS claim 5 explicitly via the claims.md bridge (HYPOTHESIZED + refutation
  criterion = honest phrasing, not a defect).
- Calibrated, downward-biased confidence with an anchoring rationale.

## What the CURRENT agent will plausibly do
- Catches claim 2 (it does verify citations) but passes claim 3 whole; weak or
  single-grep handling of claim 4; may flag claim 5 as hedging or as an
  unverified causal claim; emits an unanchored confidence number.

## Regression signals (upgrade is WORSE if...)
- It FAILs claim 5 (the HYPOTHESIZED-tagged claim) or demands it be removed.
- No atomic decomposition / verdict without per-claim labels.
- Loss of the six-field class-aware FAIL block on flagged defects.

## Contract checks (must hold in BOTH runs)
- Overall verdict present; the draft must FAIL (claims 2/3/4 are genuinely wrong);
  claim 1 must NOT be flagged.
