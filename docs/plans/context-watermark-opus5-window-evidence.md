# Evidence — context-watermark-opus5-window

## Task W1
EVIDENCE BLOCK
==============
Task ID: W1
Verified at: 2026-07-29T16:05:00Z (flip executed same day)
Verifier: task-verifier — PASS conf 9
PROVEN: table entry at adapters/claude-code/hooks/context-watermark.sh:244 (case pattern
`claude-opus-5|claude-opus-5-*|` in the 1000000 branch) + header note :84, commit 297d078.
Suite 21/0 under /bin/bash 3.2.57 AND /opt/homebrew/bin/bash 5.3.15. Adversarial probe:
`claude-opus-50` falls through to the honest ASSUMED fallback (no prefix swallowing);
bare + dated forms both resolve 1000000. Oracle: the operator's live client readout
("163.2k / 1.0M (16%)" with Opus 5 selected) fixes the denominator.
Runtime verification: test adapters/claude-code/hooks/context-watermark.sh::--self-test (21/0 both interpreters)

## Task W2
EVIDENCE BLOCK
==============
Task ID: W2
Verified at: 2026-07-29T16:05:00Z (flip executed same day)
Verifier: task-verifier — PASS conf 9
PROVEN differentially: T17b (context-watermark.sh:765-777) asserts bare AND dated
`claude-opus-5` resolve 1000000. Mutation (W1 table entry deleted in a scratch copy):
`T17b ... FAIL (bare= dated=)`, 20/1, suite exit 1 — identical both interpreters; real
tree GREEN 21/0 exit 0. The scenario is coupled to its control, not a
survives-deletion no-op.
Runtime verification: test adapters/claude-code/hooks/context-watermark.sh::--self-test (mutant 20/1 exit 1; real 21/0 exit 0)

## Task W3
EVIDENCE BLOCK
==============
Task ID: W3
Verified at: 2026-07-29T16:05:00Z (flip executed same day)
Verifier: task-verifier — PASS conf 9
PROVEN mechanically: docs/backlog.md:1323-1357 — names the class (table stale-by-default
on every model launch), why per-incident additions are symptom treatment, and the three
candidate structural fixes (suppress-percentage-for-unknown / read window from the usage
payload / doctor check REDs when the running model is absent). Commit 297d078.
Runtime verification: file docs/backlog.md::CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01
