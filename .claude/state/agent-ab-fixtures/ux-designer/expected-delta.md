# Expected-delta rubric — ux-designer

Planted (plan UI section): ideal-state-only spec (no empty/loading/error states
mentioned), 16x16px icon-only details button (below WCAG 2.2 target-size minimum,
and unlabeled), color-only signal (response-time cell "turns red" with no second
signal), data loads on mount with no loading-state spec, and total silence on
accessibility and on what a brand-new org (zero reps / zero activity) sees.

## What the UPGRADED agent should do differently
- Top-line Verdict emitted (expected: FAIL or PASS-WITH-FINDINGS with the target
  size + missing states as the drivers).
- Four-UI-states audit per surface: names the missing empty / loading / error
  states for the table AND the side panel, with NN/g empty-state grounding.
- WCAG 2.2 criteria cited by number where load-bearing (2.5.8 target size 24x24
  minimum for the 16x16 button; focus/label criteria for the icon-only button).
- Nielsen H-numbers on findings; color-only red cell flagged with "color is never
  the only signal" + a paired-signal fix.
- Plan-silence inferences labeled HYPOTHESIZED (e.g., "the plan does not say
  whether sorting persists — HYPOTHESIZED gap") vs PROVEN-from-plan-text gaps.

## What the CURRENT agent will plausibly do
- Catches the empty-state gap and probably the icon-only button (its checklist
  covers these) but as prose "Critical/Important" gaps without a top-line
  verdict, without WCAG criterion numbers, and without PROVEN/HYPOTHESIZED
  separation.

## Regression signals (upgrade is WORSE if...)
- The "Summary for the plan file" block (planning.md integration point) is
  dropped.
- The six-field class-aware feedback block disappears from findings.
- Severity inflation: everything Critical (the upgrade's calibration should
  produce a spread, not a wall).

## Contract checks (must hold in BOTH runs)
- Missing empty state and the 16px icon-only button are flagged; review remains
  plan-level (no demand for a running app).
