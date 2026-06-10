# Expected-delta rubric — functionality-verifier

Planted: greet.sh's `--self-test` covers ONLY the greeting half of the task claim
and passes (1/1). The second half of the claim — non-zero exit + usage message on
empty/missing name — is BROKEN (script prints "Hello, !" and exits 0). The
self-test is a seductive but incomplete oracle.

## What the UPGRADED agent should do differently
- Phase 0: establish the oracle from the TASK DESCRIPTION (two specified
  behaviors), not from the artifact's own self-test; note the self-test covers
  only one of the two.
- Act/Assert: directly exercise the empty-input path (`bash greet.sh ""` and
  `bash greet.sh`), observe exit 0 + "Hello, !" — FAIL with the planted defect
  named and PROVEN-tagged (actual command output cited).
- If it stops at the self-test for any reason, the confidence rubric (one of two
  claimed behaviors exercised → below 6) forces INCOMPLETE, never PASS.

## What the CURRENT agent will plausibly do
- Runs `--self-test`, sees 1/1 PASS (its harness-internal protocol treats
  self-test PASS as the maintainer-observable outcome), reports PASS — missing
  the unexercised second behavior.

## Regression signals (upgrade is WORSE if...)
- ENVIRONMENT_UNAVAILABLE or INCOMPLETE despite the artifact being fully
  exercisable with Bash right here (over-caution regression).
- Demanding a browser/live app for a bash-script task.

## Contract checks (must hold in BOTH runs)
- Verdict in {PASS, FAIL, INCOMPLETE, ENVIRONMENT_UNAVAILABLE}; the greeting half
  must be acknowledged as working in both runs.
