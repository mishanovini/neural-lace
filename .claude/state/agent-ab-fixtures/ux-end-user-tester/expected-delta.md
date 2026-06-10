# Expected-delta rubric — ux-end-user-tester

Planted (SettingsPage.tsx): raw snake_case label (`default_reply_window_mins`),
dev verb on a user button ("Upsert config"), destructive "Purge" button with no
confirmation and no reversibility info, telecom jargon ("SIP trunk", "CPaaS
BYOC"), and a vague "Submit" button that doesn't name its action.

## What the UPGRADED agent should do differently
- Mandatory first-person think-aloud narration (`user_narration`) at each friction
  moment, in the persona's (Dana-style) literal, impatient voice — e.g. reading
  `default_reply_window_mins` aloud and not knowing what it means.
- Every finding tagged with the Nielsen heuristic(s) it violates (H1-H10) — the
  Purge button maps to error prevention / user control (H5/H3), the jargon to
  match-with-real-world (H2).
- Calibrated severity: Nielsen 0-4 with explicit frequency x impact x persistence
  decomposition, mapped to P0/P1/P2 (Purge-no-confirm should be P0/sev-4 class).
- `evidence_mode: source-only` declared; behavioral claims labeled HYPOTHESIZED
  with refutation criteria.
- Class-aware fields (class / sweep_query / required_generalization) on the
  jargon-label class (multiple instances on one page = a class, not instances).

## What the CURRENT agent will plausibly do
- Flags most of the same surface problems (its checklist does cover jargon and
  destructive actions) but as third-person checklist findings without narration,
  without H-numbers, with uncalibrated severity, and without the evidence-mode
  honesty flag.

## Regression signals (upgrade is WORSE if...)
- Narration theater replaces substance (long persona monologue, fewer concrete
  findings than the current run).
- The JSON summary rollup is dropped or P0/P1/P2 mapping is lost.

## Contract checks (must hold in BOTH runs)
- Purge-without-confirmation and the snake_case label are both flagged; findings
  reference the persona's vocabulary and patience.
