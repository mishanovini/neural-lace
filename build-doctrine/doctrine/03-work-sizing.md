---
title: Build Doctrine — Work Sizing Rubric
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - originally drafted independently before review of existing neural-lace artifacts (risk dimensions, patterns/, agents/), to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md and 02-roles.md
  - integrated-v1 incorporates Phase 1d-B comparative-review recommendations + cross-references to NL mid-build decision tiers and the 3-axis spec-header schema
references:
  - ~/.claude/rules/planning.md (mid-build decision tiers L383-388; Plan-Time Decisions With Interface Impact)
  - ~/.claude/principles/permission-model.md (T0-T3 permission tiers, six-dimension composite scoring)
  - outputs/unified-methodology-recommendation.md Section 3 (10-stage reliability spine)
  - outputs/unified-methodology-recommendation.md Section 6 (C-mechanism proposals C1-C22)
  - outputs/glossary.md (Tier vs Rung vs Architecture vs mid-build-Tier vs Permission-Tier disambiguation)
  - 04-gates.md (gate matrix parameterized by architecture × rung)
  - 09-autonomy-ladder.md (architecture taxonomy N-A-1; rung definitions)
  - 08-project-bootstrapping.md (project canon; rung initialization)
revision_notes:
  - 2026-05-01: adversarial review made mandatory at every tier (depth scales by tier); Integration Map references required at Tier 3+; findings ledger references added throughout; Tier 4 explicitly requires Integration Map updates as a sub-deliverable
  - 2026-05-03 v3 (integrated-v1):
      - NL mid-build decision tiers (T1/T2/T3 reversibility) cross-referenced as a separate axis (per Phase 1a R-2)
      - five orthogonal axes documented (per R-7) — work-sizing tier, autonomy rung, architecture, mid-build decision tier, permission tier
      - architecture taxonomy as third axis (per N-A-1) — added as final tier-selection trigger question
      - five-axis spec-header schema confirmed per Q4 (tier × rung × architecture; mid-build-tier and permission-tier inherit from project)
      - universal requirements cross-reference C-mechanism IDs (forthcoming Phase 1d-C work) and the NL adversarial-review agents that operationalize each tier
---

# Build Doctrine — Work Sizing Rubric

## Scope

Every unit of work fits a tier. The tier determines:

- What inputs the spec must contain to dispatch the unit.
- Which roles activate.
- Which gates run.
- Who reviews and how deeply.
- What counts as "done."

The rubric exists to prevent **over-delegation** — the failure mode where work that needs scaffolding is given to a solo LLM that produces plausible-looking output with structural holes. It also prevents **under-delegation**, where simple work is over-gated and the team grinds.

LOC is a proxy in this rubric, not the determinant. The determinants are: **what contracts are changing**, **how many modules are touched**, **what needs to remain consistent across the change**, and **whether the work introduces a pattern not yet in canon.**

This rubric composes with the harness's runtime risk model. The two systems answer different questions:

- **Tier** answers: "what shape must the spec, roles, and gates take to dispatch this work safely?"
- **Risk tier (NL `permission-model.md` T0-T3)** answers: "for any given runtime action, what permission level is required?"

A Tier 1 unit can still trigger high runtime risk (e.g., a small change near credentials). A Tier 5 design exercise may produce no runtime actions at all. They compose; they do not collapse into each other.

---

## Five orthogonal axes — what each measures and why they don't conflate

Every unit of dispatched work is described by **five orthogonal axes**. Each measures a distinct property; none subsume any other; the orchestrator enforces the gate set produced by the cross-product of all five. This section is load-bearing because conflating axes is the most common source of misclassified work and missed gates.

| Axis | Domain | What it measures | Where defined |
|---|---|---|---|
| **Work-sizing tier** | T1–T5 | Complexity of the contract surface and decomposition cost — how much spec + decomposition + cross-unit review the work requires | This doc |
| **Autonomy rung** | R0–R5 | Project-level commitment about where humans sit relative to the work — every PR / selective PRs / specs only / metric-driven / dark factory | `09-autonomy-ladder.md` |
| **Architecture** | coding-harness / orchestration / auto-research / dark-factory / hybrid | Agent topology the project employs — which substrate produces output | `09-autonomy-ladder.md` (per N-A-1) and `08-project-bootstrapping.md` |
| **Mid-build decision tier** | T1–T3 | Reversibility of decisions made *during* a build — isolated revert / multi-file revert / irreversible | NL `~/.claude/rules/planning.md` L383-388 |
| **Permission tier** | T0–T3 | Per-action runtime risk via 6-dimension composite scoring — Silent Allow / Log & Allow / Confirm / Block | NL `~/.claude/principles/permission-model.md` |

The mid-build decision tiers (per NL `~/.claude/rules/planning.md` L383-388) read in essence:

- **Tier 1 (mid-build)** — isolated, trivially reversible; continue + document.
- **Tier 2 (mid-build)** — multi-file but revertible; commit checkpoint first.
- **Tier 3 (mid-build)** — irreversible (schema, public API, auth, production data); pause and wait.

Note that NL's mid-build T1–T3 measure **reversibility** of mid-build decisions, while this doc's work-sizing T1–T5 measure **effort and contract surface**. Same letter, different axes.

**A spec declares all five values** (or inherits from project canon where applicable). The orchestrator enforces all five gate sets per dispatched unit. The C-mechanism sequence (forthcoming Phase 1d-C work — see `outputs/unified-methodology-recommendation.md` §6) operationalizes the spec-header validation:

- **Work-sizing tier** is declared per-spec: `tier: 1-5`. Validated at spec freeze (C2 — forthcoming).
- **Autonomy rung** is inherited from `engineering-catalog.md` profile section, optionally overridden per-spec: `rung: 0-5`. Validated at spec freeze (C2) and at promotion/demotion events (C13 — forthcoming).
- **Architecture** is inherited from project canon, optionally overridden per work unit when a project runs hybrid: `architecture: coding-harness | orchestration | auto-research | dark-factory | hybrid`. Validated at spec freeze (C2).
- **Mid-build decision tier** is NOT a spec-header field — it is evaluated per-decision at build time when a Tier 2 or Tier 3 reversibility threshold is crossed (NL `rules/planning.md` mid-build protocol).
- **Permission tier** is NOT a spec-header field — it is evaluated per-tool-action at runtime by the harness's permission model.

The first three are declared up-front (project + spec metadata). The last two are evaluated dynamically as the build proceeds. Per Q4 of `outputs/unified-methodology-recommendation.md` §9, the **three-axis spec-header schema** is `tier: 1-5` + `rung: 0-5` + `architecture: <one of five>`.

**Why all five matter at once.** A small-effort Tier 1 work-sizing unit can still hit Tier 3 mid-build (the unit innocuously discovers a schema migration is required) and trigger NL's pause-and-wait protocol — the work-sizing-tier's spec didn't anticipate the migration, and the mid-build-tier's irreversibility flag is what halts the unit. Independent axes, all enforced. Conflating any two — e.g., assuming Tier 1 work-sizing means low Permission-tier runtime risk — produces silent gate gaps.

**Cross-reference to the reliability spine.** The five axes feed into the 10-stage reliability spine (see `outputs/unified-methodology-recommendation.md` §3). Stage 2 (Spec freeze) validates the three declared axes; Stage 6 (Per-task verification) is where mid-build-tier evaluations fire; Stage 5 + 6 are where permission-tier evaluations fire on every tool action.

---

## Universal requirements (every tier)

Independent of tier, every dispatched unit:

- Has a frozen spec referencing its upstream PRD. (Operationalized by C2 spec-freeze gate, forthcoming Phase 1d-C; today: pattern-only via plan-reviewer.sh Check 6b.)
- Receives **mandatory adversarial review** with fresh context, ideally a different model family from the builder. Depth scales by tier — Tier 1 receives a lightweight edge-case pass; Tier 4–5 receive deep boundary and option-space review — but the obligation is universal. No build skips review. (Per principle #5, anti-principle #10.) Operationalized by C5 / NL's `code-reviewer`, `claim-reviewer`, `end-user-advocate`, `systems-designer`, `ux-designer` agents per tier — see the per-tier role-activation section below for the exact agent invocation per tier.
- Writes findings to the structured findings ledger. Issues identified during build but outside the unit's scope are captured, not silently ignored. (Per principle #6, anti-principle #14.) Operationalized by C9 findings-ledger schema gate (forthcoming Phase 1d-C); today: NL's `bug-persistence-gate.sh` covers the bug subset, the rest is paper-only.
- Mechanical gates run. Failures appear in the findings ledger. (Operationalized by NL's `pre-commit-tdd-gate.sh` 5-layer scan + `runtime-verification-executor.sh` + `plan-edit-validator.sh` — see `04-gates.md` gate matrix for full mapping.)
- Drift log entries record any time the builder had to interpret an underspecified spec. (Operationalized by C9; today: paper-only.)
- Out-of-scope changes are flagged as findings, not silent fixes. (Operationalized by C10 diff-allowlist scope-enforcement gate, forthcoming Phase 1d-C; today: paper-only.)

What scales by tier is the **depth, breadth, and additional gates** layered on top of these universals.

---

## Tier 1 — Contained Implementation

**Qualifies when:** Pure functions, single-purpose utilities, isolated transformations, formatters, validators against fixed schemas. No cross-module dependencies beyond well-defined interfaces. No contract changes. No state schema changes.

**Indicative size:** ≤200 LOC. Single file or a tightly related cluster.

**Spec depth required:** Inputs and outputs typed explicitly. Behavioral examples (fixtures) covering nominal and edge cases. Failure modes enumerated. Acceptance gates pre-defined.

**Roles activated:** Builder. Mechanical gates. Adversarial reviewer (lightweight pass, mandatory).

**Adversarial review agents (NL):** `code-reviewer` lightweight pass; `claim-reviewer` self-invoked. (See `04-gates.md` adversarial review gate, Tier 1 row.)

**Gates beyond universal:** None. Type checks, lint, unit tests against the fixtures, coverage of stated failure modes.

**Review pattern:** Mechanical gates plus lightweight adversarial review focused on edge cases and "what does this assume that might not hold."

**Decomposition:** None required.

**Tier-specific failure mode:** Scope creep. "While I was here I also fixed…" is the most common Tier 1 failure. The mitigation is mechanical: the unit's diff is gated against its declared file scope; out-of-scope edits fail the unit. Out-of-scope issues the builder noticed are written to the findings ledger. (Operationalized by C10 diff-allowlist scope-enforcement gate — forthcoming.)

---

## Tier 2 — Schema-Bound CRUD

**Qualifies when:** Standard CRUD against a typed schema. Form handlers with validated inputs. Predictable database operations behind an established repository pattern. REST endpoints with explicit DTOs. Anything where the contract is fixed and the implementation is filling in a known shape.

**Indicative size:** ≤500 LOC. May span 2–3 files (route, handler, test).

**Spec depth required:** All Tier 1 requirements, plus: explicit DTOs, validation rules including null / empty / boundary cases, error response shapes, the contract definition for any boundary the unit touches (referenced from the engineering catalog).

**Roles activated:** Builder. Mechanical gates. Adversarial reviewer (full edge-case pass, mandatory).

**Adversarial review agents (NL):** All Tier 1 + boundary-input enumeration via `code-reviewer` deeper pass; `end-user-advocate` plan-time mode for UI work.

**Gates beyond universal:** Integration tests against the schema. Contract test if a boundary is touched. Error-path tests covering all enumerated failure modes.

**Review pattern:** Mechanical gates plus adversarial review with fresh context. Reviewer's prompt is specifically scoped to "what edge cases aren't handled, what's the worst valid input that breaks this, what does this assume about upstream that might not hold."

**Decomposition:** None required.

**Tier-specific failure mode:** Edge case omission and silent contract drift. The implementation passes happy-path tests and matches the contract's structure but fails on null inputs, oversized payloads, auth edge cases, or implicit contract semantics not captured in the type signature. The mitigation is the adversarial reviewer's explicit edge-case prompt and a fixture suite that includes the boundary inputs.

---

## Tier 3 — Cross-Module Coordination

**Qualifies when:** Features that span multiple modules within the same repo. Refactors touching several internal contracts. Integration of a new library across multiple call sites. Anything where consistency across the change matters more than any single touch.

**Indicative size:** 500–1500 LOC across 5–15 files. Multiple internal modules.

**Spec depth required:** All Tier 2 requirements, plus: explicit list of affected modules, current contracts at each touched boundary, target contracts if any are changing, **references to the Integration Map nodes the unit touches**, migration plan if behavior changes, ordering constraints between sub-units, success criteria for the integrated whole (not just per-unit). At Rung R3+, also: `## Behavioral Contracts` section per N-G-2 (idempotency, performance budget, retry semantics, failure modes). Operationalized by C16 behavioral-contracts schema check — forthcoming.

**Roles activated:** Spec author. Planner. Builders (multiple, one per decomposed sub-unit). Mechanical gates. Adversarial reviewer (per sub-unit, mandatory) plus a separate cross-unit adversarial review pass after integration. Orchestrator. Engineering catalog curator (for Integration Map updates).

**Adversarial review agents (NL):** All Tier 2 + per-sub-unit `code-reviewer` + cross-unit integration review; `systems-designer` if `Mode: design`.

**Gates beyond universal:** All Tier 2 gates per sub-unit, plus: cross-unit integration tests, mutation testing on the integration hot paths (the seams between sub-units), end-to-end test of the whole feature, drift log review across sub-units before unit-level completion, **Integration Map verified consistent with implementation post-integration** (operationalized by C5 catalog/Integration-Map consistency gate — forthcoming).

**Review pattern:** Planner produces the DAG. **Human reviews the DAG before any dispatch** — this is the load-bearing checkpoint at this tier. Operationalized by C7 DAG-review waiver gate (forthcoming Phase 1d-C; today: pattern-only via NL `rules/orchestrator-pattern.md`). Per-sub-unit adversarial review (mandatory). A separate cross-unit reviewer pass runs once all sub-units are green to verify the integrated whole, not just the parts. The cross-unit reviewer specifically validates that the Integration Map matches what was actually built.

**Decomposition:** Mandatory. Decomposed into Tier 1/2 sub-units. Treating Tier 3 as solo work is a primary source of holes.

**Tier-specific failure mode:** Integration mismatches between sub-units that pass their own tests but disagree at the seam. Half-done migrations that compile but leak old behavior in unmodified call sites. Integration Map drift between documented and actual integration. The mitigation is the cross-unit reviewer pass, the explicit migration plan in the spec, mutation testing focused on the seams, and Integration Map verification.

---

## Tier 4 — Contract Boundary Changes

**Qualifies when:** Changes to public APIs. Cross-repo shared surfaces (the `contact-fields.ts` class of change). Breaking schema changes. Auth boundary changes. Anything where two systems — owned by the same team or by different parties — must agree on a contract.

**Indicative size:** Determined by the contract surface, **not LOC**. Could be 50 LOC across two repos. Could be 2000 LOC. Tier is set by what the change touches, not how big it is.

**Spec depth required:** All Tier 3 requirements, plus: human-authored spec (this is non-delegable); explicit before / after contracts; both sides' acceptance criteria; backward-compatibility strategy or an explicit break declaration with migration path; contract tests defined and committed **before any implementation runs**; irreversibility flag set if the change cannot be rolled back without coordinated action across consumers; **Integration Map updates included as a required sub-deliverable** of the contract change.

**Roles activated:** Spec author (human-led). Engineering catalog curator (boundary likely needs catalog and Integration Map update). Planner (decomposes per-side work). Builders (separate dispatch per side of the boundary). Mechanical gates. Adversarial reviewer (deep boundary review, mandatory). Human checkpoint on irreversible breaks.

**Adversarial review agents (NL):** All Tier 3 + per-side review; `end-user-advocate` runtime mode (browser-against-live-app verification of bilateral behavior).

**Gates beyond universal:** All Tier 3 gates, plus: contract tests on **both sides** of the boundary running against the same shared fixtures (operationalized by C3 bilateral-contract-test gate — forthcoming), integration test across the boundary, type / schema checks at the boundary, adversarial review explicitly scoped to "what does each side assume about the other that the contract doesn't enforce," human checkpoint before any irreversible push (NL permission-tier T3 Block), Integration Map updated and verified before unit-level completion (C5 — forthcoming).

**Review pattern:** Human owns the spec from start to freeze. Mandatory deep adversarial review for each side's implementation runs separately. The cross-boundary contract test must pass before either side ships. If only one side can ship, the irreversibility flag determines whether that's allowed. The Integration Map update is reviewed alongside the contract change, not after.

**Decomposition:** Mandatory. Each side dispatches as separate units; the contract definition is its own dispatched artifact upstream of either side's implementation.

**Tier-specific failure mode:** "Fixed on one side, forgot the other." This is the highest-risk surface in any system that has shared contracts across modules or repos. Symptoms: one side ships a contract change; the consuming side breaks at runtime, or worse, accepts the new contract silently with subtle semantic drift. Stale Integration Map masking the actual integration behavior. The mitigation is the contract-tests-first discipline, both-sides-shared-fixtures, the human checkpoint at the irreversibility boundary (NL Permission-tier T3), and Integration Map updates as a required sub-deliverable.

---

## Tier 5 — Novel Architecture

**Qualifies when:** Introducing a pattern not in canon. Choosing a new framework, runtime, or major dependency. Designing systems where doctrine and catalog don't yet apply because the abstractions are still being worked out. Fundamental refactors that change how the system is reasoned about, not just how it's coded.

**Indicative size:** Indeterminate. This tier is **design work**, not implementation work. The deliverable is a decision and an architecture, not a code change. Implementation that follows happens in Tier 1–4 against the new design.

**Spec depth required:** Problem statement. Constraints (technical, operational, organizational). Options analysis with trade-offs. Prior art review. Reasons-for-rejection on options not chosen. ADR (Architecture Decision Record) format encouraged.

**Roles activated:** Human leads. AI participates as sounding board, prior-art summarizer, options expander, devil's advocate — **not** as decision-maker. Spec author once the design crystallizes. Engineering catalog curator to update canon (and Integration Map shape if the new pattern changes integration topology) after it's adopted. Adversarial review on the ADR itself before adoption (mandatory; reviews the option analysis, not the implementation).

**Adversarial review agents (NL):** `systems-designer` ADR review; option-space completeness pass. (Operationalized in part by C4 ADR-adoption gate — forthcoming.)

**Gates beyond universal:** ADR drafted before any implementation. Adversarial review of the ADR (focused on "what's missing from the option space, what assumptions are unstated"). Design review with relevant stakeholders. Once a decision is made and recorded, work decomposes into Tier 1–4 units against the new design. The decision itself is gated by stakeholder acceptance, not by mechanical checks. Canon updates (catalog, Integration Map structure, design system implications) ship alongside the ADR adoption.

**Review pattern:** Human stakeholder review. AI sounding-board produces structured pros / cons / risks across options. Mandatory adversarial review of the ADR before adoption. The decision is logged in an ADR with rationale and date.

**Decomposition:** The ADR itself is the unit. Subsequent implementation decomposes per Tier 1–4 against the decided design.

**Tier-specific failure mode:** Implementing under-considered architecture because the work was framed as "build this" instead of "decide this, then build that." Failing to update canon (engineering catalog, Integration Map, design system, doctrine) to reflect the new pattern, leading to the next implementer reinventing or contradicting it. The mitigation is treating Tier 5 as a distinct activity with its own deliverable (the ADR and updated canon), separate from the implementation that follows, and adversarial review of the ADR before adoption.

---

## Tier selection — trigger questions

Apply in order. The first "yes" sets the floor; the actual tier may be higher if multiple apply.

1. **Does this introduce or change an architectural pattern not yet in canon?** → Tier 5.
2. **Does this change a contract that anyone else depends on?** → at least Tier 4. Includes public APIs, cross-repo shared types, schema changes, auth boundaries.
3. **Does this span multiple modules in coordinated ways?** → at least Tier 3. "Coordinated" means consistency across modules matters; a touch-and-go across 10 files for a renamed import is not Tier 3.
4. **Does this require state schema changes?** → treat as Tier 4 (contract change to the data layer, even if internal).
5. **Otherwise:** Tier 1 if pure / contained, Tier 2 if schema-bound CRUD against fixed contracts.
6. **What architecture is this work?** (coding-harness / orchestration / auto-research / dark-factory / hybrid). Per N-A-1 (`09-autonomy-ladder.md`), architecture is **orthogonal to tier** and determines the gate matrix's rung-axis. The architecture answer does NOT change the tier — it adds the third axis the spec must declare alongside tier and rung. Reference the gate matrix in `04-gates.md`, which is parameterized by architecture × rung. For example: a Tier 2 work-sizing unit at Rung 4 with `architecture: auto-research` activates the metric-driven scoring gates at Stage 5; a Tier 2 unit at Rung 1 with `architecture: coding-harness` activates the standard adversarial-review pattern.

LOC is checked last, only as a sanity check. A "Tier 1" call producing 500 LOC is a signal that the work may actually be Tier 2 or 3 and was misclassified.

---

## Anti-patterns

### Tier shopping

Choosing the lowest tier that lets the work dispatch. The temptation is real because lower tiers have less ceremony. The mitigation is the trigger questions: any one of them firing escalates the tier regardless of how much someone wants the work to be smaller. Tier shopping is the doctrine analogue of "I'll just sneak this past code review."

### Tier collapse on small changes

Tier 4 work whose total diff is 50 LOC being dispatched as Tier 1 because the LOC is small. The contact-fields.ts class of change is exactly this. LOC does not determine tier; the contract surface does.

### Skipping decomposition at Tier 3+

Sending a Tier 3 unit to a single builder "to keep it simple." The decomposition step is the engineering at this tier; skipping it produces the integration mismatches the tier is designed to prevent.

### Solo Tier 5

Treating architecture decisions as build tasks. "Just have Claude design and implement the new event system." The deliverable at Tier 5 is a decision and an ADR, not a working system. Implementation belongs in subsequent Tier 1–4 work against the decided design.

### Mixing tiers within one execution

A Tier 4 contract change that "while we're at it" also implements the Tier 2 consumers of the new contract in the same dispatch. The contract change should ship as its own unit and freeze before consumers build against it. Bundling them collapses the boundary that makes Tier 4 governance work.

### Skipping adversarial review on "trivial" units

Treating a Tier 1 unit as too small to warrant review. Adversarial review is universal per principle #5; what scales is depth, not whether it runs. A skipped review at Tier 1 is the same anti-pattern as a skipped review at Tier 4 — it just compounds slower.

### Findings noted but not logged

A reviewer or builder noticing an issue and resolving it conversationally rather than writing it to the findings ledger. Per anti-principle #14, this drops information the system should have retained. The discipline: every noticed issue gets a ledger entry, even if also resolved in-flight.

### Conflating tier with rung, with architecture, with mid-build-tier, or with permission-tier

The five axes are orthogonal. Common conflation patterns: (a) "Tier 1 means low runtime risk, so skip the permission-tier check" — wrong; a Tier 1 utility that touches credentials still produces T3 Block actions. (b) "Rung R4 means we don't need the work-sizing tier at all" — wrong; rung determines who reviews, tier determines what the spec must contain; both must be declared. (c) "Mid-build Tier 3 = work-sizing Tier 3" — wrong; same letter, different axes (reversibility vs effort). (d) "Architecture = dark-factory means no human review at any tier" — wrong; architecture × rung produces the gate matrix; dark-factory at R5 is gateless of human review per-PR but holdout scenarios + evidentiary verification are the gates that fire instead.

---

## Composition with the harness risk model

Every runtime action — file write, command execution, deploy, credential operation — gets a risk score from the harness independent of the work-sizing tier. The composition rule:

- **The higher of the two governs at any given moment.** A Tier 1 unit performing a credential operation runs at the runtime risk tier required for that action, even if the unit's overall tier is Tier 1.
- **Tier governs spec and decomposition; risk tier governs permission at action time.** They do not substitute for each other; they layer.
- **Tier 4 and Tier 5 both imply elevated runtime expectations** — Tier 4 because of the irreversibility flag, Tier 5 because exploratory work near production systems is a known hazard. The harness should treat these tiers as a hint that runtime risk thresholds may need to be tightened for the duration.

The doctrine does not redefine the harness's risk dimensions. It references them. (See NL `~/.claude/principles/permission-model.md` for the six-dimension scoring formula and the four-tier T0–T3 response policy.)

### Composition with mid-build decision tiers

Mid-build decision tiers (NL `~/.claude/rules/planning.md` L383-388) are also orthogonal and also additive. A Tier 1 work-sizing unit can encounter a Tier 3 mid-build decision (e.g., the builder discovers schema changes are required to complete the work). The mid-build protocol activates regardless of work-sizing tier:

- **Tier 1 mid-build (isolated, trivially reversible):** continue + document in plan's Decisions Log.
- **Tier 2 mid-build (multi-file, revertible):** commit checkpoint first; log the SHA; continue.
- **Tier 3 mid-build (irreversible: schema, public API, auth, production data):** PAUSE; wait for explicit user approval; document tradeoffs.

When a work-sizing-Tier-1 unit hits a mid-build-Tier-3 decision, the unit halts and the decision is escalated. This is the doctrine's tier-transition discipline (`05-implementation-process` L264-276) operating in conjunction with NL's mid-build-tier protocol — the work-sizing tier-transition halt is for "this entire unit is misclassified," and the mid-build tier-transition halt is for "this specific decision within the unit is irreversible." Both can fire; both produce findings; both halt before damage.

---

## Open during fresh-draft phase

- **Indicative LOC bounds** are placeholders. They will likely change after pilot use; the goal is to refine them based on actual cases that misclassified, not to defend the initial numbers.
- **Composition with neural-lace risk tiers** is now described concretely (above) per the integrated-v1 cross-references; specific composition rules are codified per axis.
- **Tier transitions during execution** (e.g., a Tier 2 unit that discovers it should have been Tier 3) need a defined protocol — currently "halt unit, drift log entry, finding written to ledger, re-spec at correct tier." Will be operationalized by C8 tier-transition halting gate (forthcoming Phase 1d-C).
- **Adversarial review depth thresholds** per tier are described qualitatively. Concrete prompt structures and required output shapes per tier are specified in `04-gates.md` (gate type 4, adversarial review).

## Next step

The integrated-v1 doctrine docs land first; subsequent Phase 1d-C work mechanizes C-proposals (C1, C2, C3, C5, C7, C8, C9, C10, C13, C14, C15, C16) as NL hooks and agents. After mechanization, this rubric can be tightened by removing "forthcoming" caveats; today the universal requirements depend on adversarial-review and findings-ledger paper rules + NL's existing `pre-commit-tdd-gate.sh` / `plan-edit-validator.sh` / `plan-reviewer.sh` / `bug-persistence-gate.sh` / `runtime-verification-executor.sh` to do the heavy lifting.
