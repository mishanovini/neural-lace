# Expected-delta rubric — systems-designer (NEEDS-MISHA tier: results-only, no apply)

Planted (journey/service-design gaps in a Mode: code product plan): (a) WRONG
PLACEMENT — the transfer action lives only under Settings > Admin tools, nowhere
near where the job actually arises (the contact detail page / rep queue); the
plan even assumes "admins know to look in Settings"; (b) a select-from-ALL-org-
contacts dropdown (unusable at scale, no search); (c) MISSING JOURNEY STEPS — no
confirmation of what moved, no undo, no notification to the receiving rep
(their queue silently changes), no audit trail; (d) the toast says "Transferred"
with no detail; (e) no failure path (what does the admin see if the POST fails?).
The plan has NO 10-section Systems Engineering Analysis because it is Mode: code.

## What the UPGRADED agent should do differently
- Phase 0 self-scoping: ENGAGE this product plan with the service-design lens
  (the current agent's remit is design-mode infra plans only).
- Produce a task/wire-flow trace of "admin moves a contact": detect the placement
  gap (JTBD job-map: the job arises at the contact/rep surface, not Settings),
  the missing confirmation/undo/notify steps, and the dead-end failure path.
- Emit Critical/Major/Minor severities per finding with a `## Reasoning trace`,
  and a verdict from {PASS, PASS-WITH-CONCERNS, FAIL} — expected FAIL or
  PASS-WITH-CONCERNS driven by placement + missing journey steps.
- PROVEN (plan-text) vs HYPOTHESIZED (plan-silence) labels on findings.

## What the CURRENT agent will plausibly do
- Declines or no-ops ("not a Mode: design plan / no 10-section analysis to
  grade"), or grades the missing 10 sections as the failure — either way it
  never reaches the journey gaps. THIS IS THE KEY DISCRIMINATOR: engagement vs
  non-engagement.

## Regression signals (upgrade is WORSE if...)
- Scope creep into pixels (button styling, colors — that is ux-designer's lane;
  the boundary must hold).
- It demands the full 10-section Systems Engineering Analysis for this small
  Mode: code plan (proportionality lost).
- The six-field class-aware feedback block is dropped.

## Decision note for Misha (why this is results-only)
The discriminator doubles as the policy question: SHOULD this agent fire on
product plans at all, and should downstream readers of `design-mode-planning.md`
now expect a third verdict value (PASS-WITH-CONCERNS)? The fixture results show
what that expansion buys (journey gaps caught pre-build) and what it costs
(another blocking reviewer on every product plan).
