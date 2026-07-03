# Comprehension Gate — compact
> Enforcement: comprehension-reviewer agent, auto-invoked by task-verifier at rung ≥ 2. Full: doctrine/comprehension-gate-full.md
> Applies: plans declaring `rung: 2` or higher — builders articulate their mental model before the checkbox flips.

- On any plan with `rung: 2`+ in the header, write a `## Comprehension Articulation` block inside the task's Evidence Log entry BEFORE invoking task-verifier. Below rung 2 the gate is a no-op.
- Four required sub-sections, in this order, each ≥30 non-whitespace chars, no placeholder text:
  - `### Spec meaning` — what the spec asks for, in your own words (a paraphrase demonstrating understanding, not a copy-paste of the Goal).
  - `### Edge cases covered` — which edge cases the diff handles, with file:line citations pointing at the code that handles each.
  - `### Edge cases NOT covered` — honest gaps the diff does not address; if you believe none exist, explicitly justify why (a bare "None." fails).
  - `### Assumptions` — premises about callers, environment, or data shape that the diff's correctness depends on but the spec does not guarantee.
- task-verifier invokes comprehension-reviewer before flipping the checkbox. Three sequential stages: schema (all four headings present — else INCOMPLETE), substance (threshold met, no vacuous placeholders — else FAIL), diff correspondence (every cited edge case maps to actual diff content; no assumption actively contradicted by the diff — else FAIL).
- FAIL or INCOMPLETE blocks the flip: task-verifier returns FAIL without checking the box. Fix the articulation (or the diff) and re-invoke.
- Write specific, diff-anchored articulations — generic text that could apply to any task fails correspondence; fabricated file:line citations are caught against the actual diff.
- If you refactor mid-build, keep the articulation in sync with the final staged diff — it is graded against what's staged, not what you intended.
