# Expected-delta rubric — end-user-advocate (plan-time mode)

Planted: the Goal crams 5+ acceptance criteria into one story (transfer +
confirmation summary + capacity warning + 5-minute undo + contact notification) —
the upgrade's BDD scoping discipline (1-3 AC per story; 4+ signals too-large)
should fire. The Edge Cases section provides material for planted Edge variations
(at-capacity boundary, mid-send transfer, undo-after-reply).

## What the UPGRADED agent should do differently
- Surface the too-large-story signal (split recommendation or explicit AC-count
  flag) in the plan-time feedback block.
- Author scenarios declarative-first (Given-When-Then) with imperative steps
  second, each carrying an `Oracles in play:` line (named FEW HICCUPPS oracles)
  and PLANTED `Edge variations` derived from the plan's Edge Cases.
- Include a coverage self-audit note (SFDIPOT factors / tours considered).
- Error-recovery / empty-state oracles (Nielsen H5/H9) appear for the undo and
  capacity-warning paths.

## What the CURRENT agent will plausibly do
- Authors flat imperative scenarios (numbered clicks), no oracle naming, no
  AC-count discipline, edge variations at most copied verbatim from Edge Cases.

## Regression signals (upgrade is WORSE if...) — CRITICAL parser contract
- Authored scenarios missing the machine-parsed fields the runtime mode and
  product-acceptance-gate depend on: `### <slug> — <desc>` heading, `**Slug:**`,
  `**User flow:**` numbered list, `**Success criteria (prose):**`,
  `**Artifacts to capture:**`. GWT must be ADDITIVE to this shape, not a
  replacement. If the upgraded output drops these fields, the upgrade breaks the
  gate's scenario parsing — hard regression, do not apply.
- Scenario count exploding past the soft cap, or private assertions leaking into
  the scenario prose (assertions stay private).

## Contract checks (must hold in BOTH runs)
- A plan-time feedback block is present; the three planted edge cases are covered
  somewhere (in-scope scenarios or explicitly out-of-scope with rationale).
