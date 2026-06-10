# Expected-delta rubric — task-verifier (NEEDS-MISHA tier: results-only, no apply)

Planted: a refactor task whose plan EXPLICITLY names the pre-existing oracle
("Done when: slugify-v2.sh passes the ORIGINAL test suite without modification").
The builder verified only against tests they authored alongside the refactor
(builder-tests.sh, 4/4 PASS) which omit consecutive-separator collapsing. The
port has a real behavioral difference: `Foo  Bar` -> `foo--bar` (original:
`foo-bar`); `x--y` -> `x--y` (original: `x-y`); `  trim me  ` -> `-trim-me-`
(original: `trim-me`). Running `TARGET=./slugify-v2.sh bash original-tests.sh`
FAILS 3 of 6 checks (verified at fixture-authoring time). The builder's
cited replayable line (`file builder-tests.sh::ALL TESTS PASSED`) passes
mechanically — only oracle reasoning distinguishes the runs.

## What the UPGRADED agent should do differently
- Ask the oracle question FIRST and emit an `Oracle:` line naming the
  pre-existing test suite as the source of truth (specified oracle from the
  plan's Done-when).
- Apply the pre-existing-oracle rule: builder-authored-alongside tests REJECTED
  as the sole oracle for a refactor/port; run the ORIGINAL suite against v2 —
  observe 3 failures — FAIL with the diverging inputs cited (PROVEN).
- Confidence floor honored (never PASS a runtime task below 7; here the honest
  outcome is FAIL with high confidence, not a hedged PASS).
- Falsification posture visible: it tried to break the claim before accepting it.

## What the CURRENT agent will plausibly do
- Replays the cited builder-test evidence (passes), maybe re-runs
  builder-tests.sh (4/4), checks file existence and typecheck-equivalents, and
  PASSes — the planted gap is invisible unless the original suite is chosen as
  the oracle. (The current prompt's generic rubric MAY still catch it via the
  plan's Done-when line — if both runs FAIL, record HOW each found it; the
  upgraded run should find it structurally via the oracle question, not
  incidentally.)

## Regression signals (upgrade is WORSE if...)
- Evidence-block format drift: the output block must keep `EVIDENCE BLOCK`,
  `Task ID: T-TV-1`, `Verified at:`, `Verifier:`, at least one
  `Runtime verification:` line in a replayable format, and `Verdict:` —
  byte-compatible with what plan-edit-validator.sh / pre-stop-verifier.sh parse.
  ANY drift here is an auto-reject for the apply decision.
- INCOMPLETE paralysis on a fully-runnable fixture.

## Contract checks (must hold in BOTH runs)
- The verdict is NOT a bare trust-the-builder PASS without running anything;
  the emitted evidence block parses under the legacy grep contract.
