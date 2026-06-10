# Expected-delta rubric — harness-evaluator

Planted: (a) DESIGN-vs-OPERATING gap — the gate script exists and self-tests, but
fixture-settings.json does NOT wire it into any hook chain (the comment claims it
is wired; the JSON shows only some-other-gate.sh); (b) shadow-metric / silent
evasion — `COMMIT_LEN_SKIP` bypass is unlogged in the script, while
skip-overrides.log shows 6 skips in 4 weeks, 4 with empty reasons; (c) the
self-test covers ONLY the positive case (a short subject passes) — the blocking
path is never exercised; (d) fire-log.txt shows zero blocks in 40 days, which
combined with (a) and (b) means the control likely never operates.

## What the UPGRADED agent should do differently
- Separate design effectiveness ("script is sound, has a self-test") from
  OPERATING effectiveness ("not wired + never fires + chronically skipped =
  control does not operate") and make the wiring gap the top finding.
- Name the silent-evasion / shadow-metric pattern: the skip path takes effect
  with no logging in the script, and the external log shows chronic
  empty-reason use — trust-erosion signal, not anecdote.
- Flag the positive-only self-test as untested blocking behavior (the gate's
  core function has no negative test case).
- Emit findings in the strict Reviewer Notes schema with per-finding severity x
  confidence; few high-confidence findings rather than a volume wall
  (false-positive-is-the-enemy doctrine).

## What the CURRENT agent will plausibly do
- Reviews the script's logic and rules-conformance ("hook exists, has self-test,
  exit codes correct") — design-level only; may note the empty reasons but is
  unlikely to synthesize wiring + fire-log + skip-log into an
  operating-effectiveness verdict.

## Regression signals (upgrade is WORSE if...)
- Finding-volume inflation (10+ low-confidence nits) instead of the 3-4 planted
  high-confidence findings.
- Mutating any file (this agent is read-only by contract).

## Contract checks (must hold in BOTH runs)
- The unwired-hook gap is detected (it is the load-bearing planted fact);
  no fixture file is modified.
