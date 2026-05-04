# PRD Validity — Every Plan With a Product Claim Resolves to a Substantive PRD

**Classification:** Hybrid. The "every plan that claims to advance a product feature has a PRD behind it" discipline is a Pattern the planner self-applies when authoring a plan. The "plan creation is mechanically blocked unless `prd-ref:` resolves to a PRD whose seven required sections are present and substantive" rule is a Mechanism enforced by `prd-validity-gate.sh` (PreToolUse `Write` on `docs/plans/.*\.md`). The substance check (problem and scenarios actually concrete; success metrics actually measurable) is also Mechanism-adjacent — `prd-validity-gate.sh` enforces shape (presence + ≥30 non-whitespace chars per section), and the `prd-validity-reviewer` agent reviews substance and returns PASS/FAIL/REFORMULATE before implementation begins.

**Ships with:** Decision 015 (`docs/decisions/015-prd-validity-gate-c1.md`) — read it first for the three sub-decisions (single `docs/prd.md` per project; seven required sections; harness-development carve-out via `prd-ref: n/a — harness-development`).

## Why this rule exists

Before C1 (the PRD-validity gate), plans could be authored without any prior product-document. A planner could declare `## Goal: build duplicate-campaign feature` and proceed straight to tasks; no prior artifact named what user need that feature served, what success looked like, or what was explicitly out of scope. The result was a recurring failure mode: plans solved the wrong problem because the problem was never written down.

Build Doctrine §6 C1 closes that loop. Every plan that claims to advance a product feature must reference a PRD via the `prd-ref:` header field; the hook resolves the reference at plan-creation time and refuses to allow plan creation if the PRD is missing or its required sections are absent. The PRD is the single canonical artifact for "what we're building and why" — separate from any plan's "how we're building it." Plans translate PRD content into tasks; they do not reinvent product framing inline.

Two upstream gaps this rule does NOT close (and should not be expected to):

- **A PRD whose sections are present but generic.** `prd-validity-gate.sh` checks that each of the seven sections has ≥ 30 non-whitespace characters of non-placeholder content. A section that reads "Users want this feature" passes the mechanical check but is not substantive. The `prd-validity-reviewer` agent (Pattern-side) catches this; the hook does not.
- **A PRD that solves the wrong problem.** No mechanical rule can detect "you wrote a PRD for the wrong product." Adversarial review by the maintainer (and ultimately by the end users) is the discipline; the hook only ensures the artifact exists.

The rule is a structural defense against vaporware at the product framing layer — the layer that sits ABOVE every other Gen 4 / Gen 5 enforcement mechanism.

## What a PRD is

A PRD (Product Requirements Document) is the single canonical product-framing artifact for a project. One per project, located at `docs/prd.md` (repo-relative). Every plan that addresses a user-facing feature references the PRD via its `prd-ref:` header field; the slug names which feature within the PRD the plan claims to advance, but every slug resolves to the same `docs/prd.md` file (per Decision 015a).

The PRD is NOT:

- A spec sheet for one feature. It covers the whole product surface; individual features get a slug and reference the relevant section.
- A plan. Plans live in `docs/plans/*.md` and describe HOW work happens; PRDs describe WHAT and WHY.
- A roadmap. Roadmaps order features over time; PRDs define the features themselves.
- A user-research artifact. User research feeds the PRD; the PRD distills the research into requirements.
- A design document. Designs (visual, interaction, technical) come AFTER the PRD; the PRD constrains what designs are valid.

The PRD's audience is anyone who needs to know what the product does and why — future maintainers, reviewers, the planner authoring a new plan, the `end-user-advocate` agent authoring acceptance scenarios for a plan.

## When PRDs are required

The C1 hook fires on every `Write` operation against `docs/plans/.*\.md`. Three cases:

1. **`prd-ref: <real-slug>` (e.g., `prd-ref: duplicate-campaign-feature`)** — the hook resolves the reference to `docs/prd.md` and verifies the seven required sections. If the file is missing or any section is absent or under-substance, the hook BLOCKS plan creation with a message naming the failing section(s) plus a pointer to the PRD template.
2. **`prd-ref: n/a — harness-development`** — the harness-development carve-out (Decision 015c). The hook ALLOWS plan creation without checking for `docs/prd.md`. Used for plans whose work product is the harness itself (rules, hooks, agents, templates, decision records).
3. **`prd-ref:` field missing entirely** — the hook treats this as an authoring error and BLOCKS, prompting the author to either declare a real `prd-ref:` slug or use the carve-out string.

The hook's gate is mechanical: shape only. The agent's review (`prd-validity-reviewer`) is substantive: it evaluates whether the PRD's content is actually about the right product, whether scenarios are concrete enough to design against, whether success metrics are measurable rather than adjectival. Both must pass before a plan with a real `prd-ref:` slug can move to implementation.

## The seven required sections

Per Decision 015b, every PRD has these seven sections. Each must have ≥ 30 non-whitespace characters of substantive, project-specific content. Section ordering is suggested but not enforced; the hook locates each section by its `##`-level heading text.

1. **Problem** — what user pain or business gap this product addresses. Concrete enough that a reviewer who has never used the product can summarize the pain in one sentence after reading the section.
2. **Scenarios** — concrete user stories or end-to-end flows the product must support. Each scenario names a real user role, a real situation they're in, and the outcome they need. Generic "users can manage their data" scenarios fail substance review.
3. **Functional requirements** — what the product does, expressed as numbered FRs. Each FR is an observable behavior, not an internal implementation detail.
4. **Non-functional requirements** — performance, reliability, security, accessibility, latency, throughput, and similar constraints, expressed as numbered NFRs. Each NFR has a measurable threshold (e.g., "p95 page load < 1.5s") rather than an adjective ("fast page load").
5. **Success metrics** — measurable targets that define "we shipped the right thing." Numeric targets, not adjectival claims. "Daily active users grow by 20% within 60 days of launch" is substantive; "users love the new feature" is not.
6. **Out-of-scope** — explicit list of adjacent things this product is NOT. Drawing the boundary forecloses scope creep at planning time and gives reviewers a concrete answer to "is this in scope?"
7. **Open questions** — known unknowns the team is still resolving. Listing open questions is itself a discipline: it prevents authors from glossing over uncertainty by assuming a default answer that turns out to be wrong.

The seven-section list is not a suggestion. The hook's section presence check is exact. If a section is renamed, missing, or split across multiple `##`-level headings, the gate FAILs. Use the canonical template at `adapters/claude-code/templates/prd-template.md` to start from a known-good shape.

## The harness-development carve-out

Plans whose work product IS the harness itself (rules, hooks, agents, templates, decision records, install scripts) are not building a product for end users; they are extending the maintainer's tooling. Forcing those plans to maintain a PRD produces tautological documents — the harness PRD-against-itself does not generate useful constraints, and authors would be tempted to copy-paste boilerplate to satisfy the gate.

The carve-out is the exact string `n/a — harness-development` (em-dash; exact phrasing) declared in the plan's `prd-ref:` field. The hook allows plan creation without checking for `docs/prd.md`. The `prd-validity-reviewer` agent does NOT fire on carve-out plans — there is no PRD substance to review.

The carve-out is auditable: `grep -l "prd-ref: n/a — harness-development" docs/plans/*.md` lists every harness-development plan. Chronic carve-out use on plans that obviously address downstream-product features (e.g., a plan with a `## Files to Modify/Create` section listing `src/components/*.tsx`) is itself a signal — the maintainer has misclassified the plan or is bypassing the discipline. `harness-reviewer` may surface this during routine reviews.

The carve-out applies only when the work product is the harness itself. It does NOT apply to:

- Plans for downstream products that happen to use the harness.
- Plans for harness-adjacent tooling that addresses an end-user need (e.g., a CLI for downstream-project authors).
- Plans whose primary deliverable is a new product feature, even if some harness-internal changes are bundled in.

When in doubt, write the PRD. The cost of an unnecessary PRD is small; the cost of a vaporware-shipping carve-out is large.

## The Mechanism + Pattern split

C1 is intentionally split into two enforcement layers:

- **Mechanism (`prd-validity-gate.sh` PreToolUse Write hook).** Runs on every plan-file creation. Reads the plan's header, locates `prd-ref:`, resolves it, checks the seven sections exist with ≥ 30 non-whitespace characters each, and either ALLOWS or BLOCKS plan creation. The hook is fast (< 200ms typical) and runs on every plan write. Its check is deliberately mechanical: presence + length + non-placeholder content. It does NOT evaluate semantic substance.

- **Pattern (`prd-validity-reviewer` agent).** Invoked by the planner manually OR via the gate's recommend-invoke message after a mechanical PASS. Reads the plan and the PRD together. Adversarially reviews PRD substance: are problem and scenarios concrete? Are success metrics measurable (numeric, not adjectival)? Are out-of-scope items explicit? Does the PRD answer "what would success look like at T+30 days?" Returns PASS / FAIL / REFORMULATE with class-aware findings (`Class:` + `Sweep query:` + `Required generalization:` per the existing seven adversarial-review agents pattern).

Both layers must pass before a plan with a real `prd-ref:` slug can move to implementation. The gate catches missing or empty PRDs at plan-creation time; the agent catches PRDs that are present but not actually substantive. A PRD that passes the gate but fails agent review is the common case and the load-bearing audit point — that is where most product-framing failures surface.

The split mirrors the existing `plan-reviewer.sh` (Mechanism: section presence) + `systems-designer` agent (Pattern: section substance) split. The two-layer pattern is consistent across the harness because it is the only known way to get cheap-and-fast shape checks PLUS expensive-but-deep substance review without conflating the two.

### When to invoke the agent

The planner invokes `prd-validity-reviewer` via the Task tool:

1. After authoring or significantly revising `docs/prd.md`.
2. Before authoring a plan with a real `prd-ref:` slug pointing at the PRD.
3. After receiving a `Plan-Time PRD Validity Feedback:` block from a previous review iteration and updating the PRD in response.
4. As part of routine harness reviews when the PRD has not been adversarially reviewed in some time.

The agent returns structured findings keyed to the seven sections. The planner addresses each finding by updating the PRD (or by deciding the gap moves to the PRD's `## Out-of-scope` section with rationale). Iteration continues until the agent returns PASS.

The agent is upstream of every other adversarial review in the harness. A weak PRD cascades: weak problem statement → weak plan goal → weak acceptance scenarios → vaporware shipping that solves nothing. By the time `end-user-advocate` runs runtime acceptance, the build has already happened against the wrong target. By the time `systems-designer` reviews a Mode: design plan, the system is being designed for the wrong outcome. Catching shallowness at the PRD layer costs minutes; catching it later costs days.

### Separation from `systems-designer`

Per Build Doctrine §9 Q6-A and Decision 015: the `prd-validity-reviewer` agent is intentionally separate from `systems-designer`, not redundant with it.

- `systems-designer` reviews a plan's 10 Systems Engineering Analysis sections — HOW the system will be built, traced, observed, and recovered.
- `prd-validity-reviewer` reviews a PRD's seven product sections — WHAT problem the system solves, WHO it solves it for, and HOW success is measured.

A PRD review must pass before a plan that references it can move to implementation. For Mode: design plans, BOTH agents must PASS. The PRD review is upstream; the systems review is downstream. Failing the PRD review means the system is being designed for the wrong outcome and `systems-designer` review of the same plan is wasted effort.

Harness-development plans (those declaring `prd-ref: n/a — harness-development`) bypass `prd-validity-reviewer` entirely. There is no product user to advocate for at the PRD layer for harness-internal work; the substance-review focus shifts to whether the harness change addresses a real maintainer-facing failure class (which `harness-reviewer` evaluates).

## Authoring discipline

The planner self-applies the following discipline when authoring or revising a PRD:

1. **Write the Problem section first.** Every other section is downstream of the problem statement. If you cannot describe the problem in one substantive paragraph that does not mention any specific feature, the rest of the PRD will be aspirational rather than grounded.
2. **Make scenarios real.** Each scenario names a real user role (not "the user"), a real situation they are in (not "wants to use the product"), and a real outcome they need. If a scenario reads identically across two products, it is not concrete enough.
3. **Make success metrics numeric.** "Engagement increases" is not a success metric. "Daily active users grow by 20% within 60 days of launch" is. If a metric cannot be measured today, name how it WILL be measured at launch and what threshold defines success.
4. **Be aggressively explicit about out-of-scope.** Listing what the product is NOT often clarifies what it IS. If you cannot identify three adjacent things the product explicitly does not do, the scope is not yet understood.
5. **List open questions even if they are uncomfortable.** Listing "we don't know how to handle X yet" is more valuable than asserting a default answer that will turn out to be wrong. Reviewers can see the open questions; downstream plans can include resolution tasks.
6. **Re-author rather than patch.** If a PRD review surfaces multiple substance gaps, rewrite the affected sections from scratch rather than appending qualifications to existing prose. Patched prose carries the original framing forward; rewrites force fresh analysis.
7. **Treat the PRD as living.** PRDs evolve as the product is understood. Update `docs/prd.md` when a new scenario surfaces, an open question resolves, or out-of-scope grows. Plans authored against an updated PRD see the new content automatically (single canonical file).

## Failure modes (and how the harness handles them)

- **Plan author declares `prd-ref: <slug>` but the PRD does not exist.** The hook BLOCKS plan creation with a message: "PRD file `docs/prd.md` not found. Either create the PRD using the template at `adapters/claude-code/templates/prd-template.md`, or declare `prd-ref: n/a — harness-development` if this is harness-internal work."
- **PRD exists but is missing one or more required sections.** The hook BLOCKS with a message naming each missing section. The author adds the section using the template's structure.
- **PRD section is present but contains only placeholder text or fewer than 30 non-whitespace chars.** The hook BLOCKS with a message naming the under-substance section. The author writes substantive content using the template's per-section guidance.
- **PRD passes mechanical gate but agent review identifies generic content.** The agent returns FAIL with class-aware findings keyed to specific sections. The planner addresses each finding before re-invoking the agent. Iteration continues until agent PASS.
- **Author tries to bypass the carve-out by writing `prd-ref: n/a` (without the full string).** The hook treats this as a missing or unrecognized value and BLOCKS, requiring the exact carve-out phrasing.
- **Author declares the carve-out on a plan that obviously addresses a downstream product feature.** No mechanical defense; chronic misuse surfaces in routine harness reviews via grep on the plan list.

## Cross-references

- **Decision record:** `docs/decisions/015-prd-validity-gate-c1.md` — the three sub-decisions (single PRD per project; seven required sections; harness-development carve-out via the exact-string convention).
- **Hook:** `adapters/claude-code/hooks/prd-validity-gate.sh` — the PreToolUse `Write` mechanism (lands in Phase 1d-C-2 Task 3).
- **Agent:** `adapters/claude-code/agents/prd-validity-reviewer.md` — the substance-review counterpart (already shipped Phase 1d-C-2 Task 7).
- **Template:** `adapters/claude-code/templates/prd-template.md` — the canonical PRD shape with the seven sections and per-section authoring guidance.
- **Plan template:** `adapters/claude-code/templates/plan-template.md` — the plan header includes the `prd-ref:` field with inline guidance pointing at this rule.
- **Sibling rule:** `adapters/claude-code/rules/spec-freeze.md` — Decision 016's spec-freeze gate (C2). The two rules together ensure: (a) plans claim a product context (C1 / this rule), and (b) plans freeze their scope before edits begin (C2 / spec-freeze).
- **Upstream rule:** `adapters/claude-code/rules/planning.md` — references the `prd-ref:` plan-header field and points at this rule.
- **Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C1 + §9 Q6-A — the original specification for the gate and the agent separation.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | When PRDs are required, what the seven sections require, the harness-development carve-out | `adapters/claude-code/rules/prd-validity.md` | landed |
| Template | Shape of a correct PRD with the seven sections and per-section guidance | `adapters/claude-code/templates/prd-template.md` | landed (Phase 1d-C-2 Task 1) |
| Hook (`prd-validity-gate.sh`) | Plan creation blocked unless `prd-ref:` resolves to a PRD with seven substantive sections | `adapters/claude-code/hooks/prd-validity-gate.sh` | landing in Phase 1d-C-2 Task 3 |
| Agent (`prd-validity-reviewer`) | PRD content is substantive, scenarios concrete, success metrics measurable | `adapters/claude-code/agents/prd-validity-reviewer.md` | landed (Phase 1d-C-2 Task 7) |
| Plan-reviewer Check 10 | The `prd-ref:` plan-header field is present and non-empty (semantic check is C1's job) | `adapters/claude-code/hooks/plan-reviewer.sh` | landing in Phase 1d-C-2 Task 5 |
| Decision record | The three sub-decisions backing this rule | `docs/decisions/015-prd-validity-gate-c1.md` | landed (Phase 1d-C-2 Task 1) |

The rule is documentation (Pattern-level). The mechanism stack (hook + plan-reviewer Check 10 + agent) is hook-and-agent-enforced. Together they close the loop: cannot author a plan without a valid PRD reference (hook); cannot author a plan with a malformed `prd-ref:` field (Check 10); cannot move to implementation with a present-but-shallow PRD (agent). The carve-out is the explicit, auditable bypass for harness-internal work.

## Scope

This rule applies in any project whose Claude Code installation has the `prd-validity-gate.sh` hook wired in `settings.json` AND has chosen to enforce PRD-validity. Adoption is per-project: a project opts in by populating `docs/prd.md` and authoring plans with `prd-ref:` slugs. A project that has not adopted the discipline writes `prd-ref: n/a — harness-development` (or some future generic-bypass equivalent) on every plan; the gate ALLOWS but the discipline does not produce its intended audit trail.

Neural Lace itself adopts the carve-out for all internal harness-development plans. Downstream projects opt in via separate per-project plans (per the rollout sequence — NL adopts the substrate first; downstream projects follow).
