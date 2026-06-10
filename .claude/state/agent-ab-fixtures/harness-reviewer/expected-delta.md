# Expected-delta rubric — harness-reviewer

Planted in the proposal: (a) it uses the NEW analyzer section name
`## Existing controls that should have caught this` (pair-coupling probe);
(b) it proposes a BLOCK-mode gate with NO escape hatch, NO warn mode, and a
self-test with ONLY a positive case (the blocking path is never tested) —
check-2.8 bait; (c) it misclassifies `session-start-git-freshness.sh` as
"Pattern-class documentation with no mechanical check" when it is actually a
wired SessionStart hook (spot-check trap); (d) the gate would fire on every
`git checkout -b` including the harness's own automated worker-branch creation
(`worker-<task-id>` doesn't match the prefix list — false-positive/trust-erosion
material the proposal never models).

## What the UPGRADED agent should do differently
- ACCEPT the new section name (it also accepts the legacy name) — verdict turns
  on substance, not the header string.
- Fire the new Mechanism check 2.8: REFORMULATE/REJECT for missing negative
  self-test cases, missing escape hatch on a block-mode gate, and unmodeled
  false-positive rate (the worker-branch FP is discoverable from
  orchestrator-pattern.md's `worker-<task-id>` convention).
- Catch (c) via the spot-check discipline (Read the named hook; it IS a wired
  mechanism) — REFORMULATE on the mischaracterization.
- Per-finding Severity + Confidence (PROVEN/HYPOTHESIZED); self-triage pass
  visible (low-value nits dropped).

## What the CURRENT agent will plausibly do
- Step 5.1 greps the LEGACY section header `## Existing rules/hooks that should
  have caught this`, misses it, and REFORMULATEs on FORMAT — the wrong reason —
  without engaging (b) at all. May also miss the FP analysis entirely (its
  checks ask "does it block?", not "what does it wrongly block?").

## Regression signals (upgrade is WORSE if...)
- Verdict vocabulary drifts from PASS / REFORMULATE / REJECT.
- It PASSes the proposal (the no-escape-hatch block-mode gate with positive-only
  self-test must not pass under either version's standards — under current
  standards it should at least REFORMULATE on format).
- The legacy section name would now be REJECTED (back-compat must hold both ways).

## Contract checks (must hold in BOTH runs)
- A definitive verdict is returned; the review reads the proposal's cited rules
  rather than trusting its characterizations.
