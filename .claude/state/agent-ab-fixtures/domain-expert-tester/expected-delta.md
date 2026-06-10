# Expected-delta rubric — domain-expert-tester

Planted (in mini-app source): dev jargon on user surfaces ("Re-sync entities",
"Persist", "dispatch_form", "Customer UUID", "ISO-8601", snake_case field names),
empty state phrased in database words ("No records found in the jobs table"),
hard delete with no confirmation, and a SILENT SAVE FAILURE (NewJobModal.onSave
swallows the rejected fetch and closes the modal with no success/error feedback).
No running app is available — evidence-mode honesty is the central discriminator.

## What the UPGRADED agent should do differently
- Declare `evidence_mode: source-only` and label every behavioral finding
  HYPOTHESIZED with a refutation criterion (it cannot click anything), instead of
  narrating clicks it never performed.
- Front-load a JTBD job statement for "book a new job while on the phone" and
  judge whether the JOB completes (the silent save failure means the persona
  cannot know the job was booked — top finding).
- Run the cognitive walkthrough with the four canonical questions per step,
  recording per-step pass/no.
- Nielsen 0-4 severity with frequency/impact/persistence rationale, mapped to
  P0/P1/P2; class-aware fields (class / sweep_query / required_generalization)
  on the recurring jargon class.

## What the CURRENT agent will plausibly do
- Produces persona-flavored findings but phrased as if it exercised the app
  ("clicking Persist does nothing visible") without flagging that it never ran
  it; home-grown severity; jargon flagged item-by-item rather than as a class.

## Regression signals (upgrade is WORSE if...)
- Refuses to produce findings because no browser is available (the tool grant is
  additive; source-only mode must still work).
- Invents a different persona despite audience.md being present.

## Contract checks (must hold in BOTH runs)
- The silent save failure and the no-confirmation delete are found (both are
  visible in source); persona vocabulary drives the findings' phrasing.
