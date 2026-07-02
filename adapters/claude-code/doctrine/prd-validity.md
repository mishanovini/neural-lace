# PRD Validity — compact
> Enforcement: prd-validity-gate.sh (PreToolUse Write on docs/plans/), plan-reviewer.sh Check 10; prd-validity-reviewer agent. Full: doctrine/prd-validity-full.md
> Applies: every plan claiming to advance a product feature.

- Every plan header declares `prd-ref:`. A real slug resolves to the project's single canonical PRD at `docs/prd.md`; the gate BLOCKS plan creation when the PRD is missing or any required section is absent or under-substance. A missing `prd-ref:` field also blocks.
- The PRD has seven required sections, each ≥30 non-whitespace chars of project-specific content: Problem, Scenarios, Functional requirements, Non-functional requirements, Success metrics, Out-of-scope, Open questions.
- Harness-internal plans use the exact carve-out string `prd-ref: n/a — harness-development` (em-dash, exact phrasing) — the gate allows without a PRD. Never use the carve-out on plans that obviously address downstream product features; chronic misuse is itself a review signal.
- The gate checks shape only. prd-validity-reviewer reviews substance — concrete scenarios, numeric success metrics, explicit out-of-scope — and must PASS before a plan with a real slug moves to implementation. It runs upstream of systems-designer: a wrong-target PRD wastes every downstream review.
- Authoring discipline: write Problem first; each scenario names a real role + real situation + needed outcome; metrics are numeric ("DAU +20% within 60 days"), never adjectival; list at least three explicit out-of-scope items; list open questions honestly rather than assuming defaults. Rewrite shallow sections from scratch; don't patch qualifications onto them.
- The PRD is living: update `docs/prd.md` when a new scenario surfaces, a question resolves, or scope shifts — every plan referencing it sees the update automatically.
