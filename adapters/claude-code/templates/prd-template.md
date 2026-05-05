# PRD: [Product / Feature Name]

<!--
This is the canonical Product Requirements Document template for projects
using the Neural Lace harness. The PRD is the single source-of-truth for
"what are we building and why" — separate from any plan's "how are we
building it."

ONE PRD per project. Path: docs/prd.md (repo-relative). All plans whose
`prd-ref:` field references a slug resolve to THIS file; the slug is
informational (it identifies which feature within the PRD a plan claims
to advance), not a path component.

The PRD-validity gate (`prd-validity-gate.sh`) verifies seven required
sections at plan-creation time:

  1. Problem
  2. Scenarios
  3. Functional requirements
  4. Non-functional requirements
  5. Success metrics
  6. Out-of-scope
  7. Open questions

Each section must contain ≥ 30 non-whitespace characters of substantive,
project-specific content. Placeholder-only sections fail the gate.
Section ordering is suggested but not enforced; the hook locates each
section by its `##`-level heading text.

Harness-development plans bypass C1 entirely via the carve-out
`prd-ref: n/a — harness-development` in the plan header. No PRD is
required for plans whose work product is the harness itself (rules,
hooks, agents, templates, decision records); that carve-out is
documented in Decision 015. This PRD template is for product work — a
project the harness is being USED to build, not the harness itself.

For substance review of a draft PRD beyond shape-only validation, invoke
the `prd-validity-reviewer` agent with the plan path and the PRD path.
The agent reviews against adversarial criteria: are problem and
scenarios concrete? Are success metrics measurable (numeric, not
adjectival)? Are out-of-scope items explicit? Does the PRD answer
"what would success look like at T+30 days?"
-->

## Problem

<!--
What user pain or business gap does this product address? Be specific:
who is the user, what are they doing today, where does it break, what
does the breaking cost them? Avoid solution-language; describe the
problem state, not the proposed remedy.

Examples of substance:
  - "Field technicians today copy invoice details from email into a
     spreadsheet, then re-key into the billing portal. The double-entry
     produces ~3% error rate; corrections take 2-3 hours per error."
  - "Sales reps lose 10-15 deals per quarter to follow-up timing — they
     remember to call, but not at the right cadence; the deal is cold
     by the time they reach out."

Avoid: "Users want a better experience." (Not specific; not falsifiable.)
-->

[Describe the user pain or business gap this product addresses. ≥ 30 chars of substantive content.]

## Scenarios

<!--
Concrete user stories or end-to-end flows the product must support.
One scenario per substantive flow. Each scenario has a one-line title
and a short narrative walking the user through the flow with realistic
specifics (names, sizes, durations).

Format suggestion:

  ### Scenario 1 — <user-perspective title>

  <Persona> opens <surface>, sees <state>, takes <action>, expects
  <outcome>. The flow takes < <time bound>; if it fails, the user sees
  <error or recovery path>.

Each scenario should be a flow a real user would describe, not a
feature list. "User clicks Save" is not a scenario; "User updates an
invoice's billing address mid-submission and the submission preserves
the new address even after the timeout retry" is.
-->

[List the concrete user stories or flows this product supports. ≥ 30 chars of substantive content.]

## Functional requirements

<!--
What the product DOES, expressed as numbered requirements. Each FR is
falsifiable: a reader can determine whether the product satisfies the
requirement by observing behavior.

Format:

  - **FR-1.** <Requirement statement>. <Acceptance criteria.>
  - **FR-2.** <Requirement statement>. <Acceptance criteria.>

Avoid:
  - "The system should be fast." (Not falsifiable; belongs in NFRs.)
  - "Users can do everything they need." (Not specific.)
  - Implementation language: "The system uses GraphQL." (HOW, not WHAT.)

Prefer:
  - "FR-3. The system supports importing CSV files up to 10,000 rows.
     Acceptance: a 10,000-row CSV import completes within 60 seconds
     and produces zero data loss vs. the source file."
-->

[Numbered functional requirements describing what the product does. ≥ 30 chars of substantive content.]

## Non-functional requirements

<!--
Constraints the product must satisfy that aren't about WHAT it does
but HOW it behaves: performance, reliability, security, accessibility,
internationalization, etc.

Format:

  - **NFR-1.** <Constraint name>: <numeric or measurable target>.
  - **NFR-2.** <Constraint name>: <numeric or measurable target>.

Examples:
  - "NFR-1. p95 page-load latency: < 1.5s on 4G mobile."
  - "NFR-2. Accessibility: WCAG 2.1 AA conformance for all customer-
     facing views."
  - "NFR-3. Data retention: customer records preserved for 7 years
     after account closure (regulatory)."

Avoid adjectival NFRs ("should be reasonably fast") — they are not
testable. Every NFR has a number or a citation to a standard.
-->

[Numbered non-functional requirements with numeric or measurable targets. ≥ 30 chars of substantive content.]

## Success metrics

<!--
Measurable targets that define "we shipped the right thing." Numeric
targets, not adjectives. Each metric has a target value and a
measurement method.

Format:

  - **SM-1.** <Metric name>: <target value> by <date>. Measured via
    <source / instrumentation>.
  - **SM-2.** <Metric name>: <target value> by <date>. Measured via
    <source / instrumentation>.

Examples:
  - "SM-1. Activation rate: ≥ 60% of new signups complete the first
     workflow within 7 days. Measured via product analytics events."
  - "SM-2. Support volume: < 1 ticket per 10 active users per month.
     Measured via support ticketing system tags."
  - "SM-3. Revenue: $X ARR by Q4. Measured via billing system."

Avoid: "Users love it." (Not measurable.) "Improved engagement." (No
target value.)

If you have ≤ 3 metrics, you probably haven't thought hard enough.
Real products have leading indicators, lagging indicators, and
counterbalancing metrics (e.g., engagement up but support volume down).
-->

[Numbered success metrics with numeric targets and measurement methods. ≥ 30 chars of substantive content.]

## Out-of-scope

<!--
Explicit list of adjacent things this product is NOT. Each entry has a
one-sentence rationale: WHY is this excluded?

Format:

  - **<Adjacent capability>** — <one-sentence rationale for exclusion>.

Examples:
  - "Mobile-native app — first release is web-only; mobile is Q3."
  - "Multi-tenant org hierarchy — single-org assumption simplifies
     auth model; revisit when first 10-user org appears."
  - "Real-time collaboration — async editing model is sufficient for
     the workflows in scope; real-time has 10x the implementation
     complexity for marginal user value."

Out-of-scope is not "things we won't build." It's "things a reasonable
reader might think this PRD includes but explicitly does not." If
your out-of-scope list is empty, you haven't thought about what an
adversarial reader would assume.
-->

[Numbered out-of-scope items with rationale for each exclusion. ≥ 30 chars of substantive content.]

## Open questions

<!--
Known unknowns the team is still resolving. These are NOT
"unimplemented features" — those go in Out-of-scope. Open questions
are decisions that need to be made before the product can be
finalized.

Format:

  - **OQ-1.** <Question> — currently leaning toward <answer>; deciding
    by <date> via <process>.
  - **OQ-2.** <Question> — alternatives are <A> vs. <B>; deciding by
    <date> via <process>.

Examples:
  - "OQ-1. Should the trial period be 14 days or 30 days? Leaning
     14; will A/B test in week 3 of beta."
  - "OQ-2. Should we offer a free tier? Alternatives are forever-free
     vs. 14-day-trial-then-paid. Deciding after first 50 paying
     customers."

If you have ≤ 1 open question, you either haven't started thinking or
you've already finished thinking. Real PRDs have 3-7 open questions.
-->

[Numbered open questions with current direction and decision process. ≥ 30 chars of substantive content.]

<!--
Footer note: this PRD is the source-of-truth for the product. As the
product evolves, this PRD evolves. Updates to the PRD itself do NOT
trigger C1 — C1 fires on plan creation, not PRD editing — but the
`prd-validity-reviewer` agent can be invoked at any time to review
substance drift. When a plan amends the product's direction, update
the relevant section here in the same effort, ideally in the same
commit as the plan-file edit.
-->
