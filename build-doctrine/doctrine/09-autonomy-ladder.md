---
title: Build Doctrine — Autonomy Ladder
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted to encode the progressive-autonomy trajectory Misha articulated as the strategic intent behind adopting this doctrine
  - composes with 01-principles.md, 02-roles.md, 03-work-sizing.md, 04-gates.md, 05-implementation-process.md, 06-propagation.md, 08-project-bootstrapping.md
  - architecture taxonomy informed by Nate B. Jones, "You're using the wrong kind of agent" (2026-03-25)
  - integrated-v1 incorporates the methodology inversion (Q1) — autonomy ladder reframed as metadata over the reliability spine
references:
  - ~/.claude/principles/progressive-autonomy.md (NL's L1-L5 per-action Trust Score; trust ceiling by infrastructure maturity; hard limits)
  - ~/.claude/principles/permission-model.md (T0-T3 permission tiers, six-dimension composite scoring)
  - ~/.claude/rules/planning.md (mid-build decision tiers; Plan-Time Decisions With Interface Impact)
  - outputs/unified-methodology-recommendation.md Section 3 (10-stage reliability spine)
  - outputs/unified-methodology-recommendation.md Section 4 (autonomy progression reframed)
  - outputs/glossary.md (Rung vs Level vs Tier vs Permission-tier disambiguation)
  - outputs/analysis/03-comparative-analysis.md (C-mechanism IDs C1-C22)
  - 03-work-sizing.md (Five orthogonal axes section)
  - 04-gates.md (gate matrix parameterized by architecture × rung)
revision_notes:
  - 2026-05-03 v3 (substantial reframing): autonomy ladder repositioned as metadata over the reliability spine per Q1 methodology inversion; Rung × Level orthogonality documented (Rung is project-level commitment in this doc; Level per `~/.claude/principles/progressive-autonomy.md` is per-action trust accumulation); five orthogonal axes cross-referenced; promotion criteria reframed as reliability metrics; demotion as automatic on reliability degradation.
---

# Build Doctrine — Autonomy Ladder

## The autonomy ladder is metadata over the gate stack

The doctrine's top priority is **first-try-functional applications**. Autonomy progression is the secondary outcome — conditional on accumulated reliability evidence at the previous level. The autonomy ladder is therefore not a free-standing axis: each rung names which gates from the reliability spine are wired up at this project, and promotion is a function of reliability evidence the previous rung accumulated. Without this inversion, autonomy adoption drifts gradually until something breaks; with it, autonomy progression is a gated decision that requires evidence.

Read the same content the other way: the substance is the gates that compound to make the first build of a feature ship correctly. The rung is **cadence-and-review-pattern metadata** describing which gates fire automatically vs. require human checkpoint at this project. The headline reframing per `outputs/unified-methodology-recommendation.md` §1 and §4: every gate operates at every rung; what changes between rungs is the human-review density and which gates are sufficient — not which gates exist. R0 means every gate operates with human review on every line. R5 means every gate operates without human-in-the-loop AND a holdout-scenario harness independently verifies behavior. The rungs themselves are descriptions of cadence.

This document specifies:

- **The rungs (R0–R5)** — six cadence patterns, each named by which gates from the reliability spine are wired up and at what review density.
- **Promotion criteria** — reliability metrics the project must demonstrate before moving from rung N to rung N+1.
- **Demotion conditions** — reliability-evidence regressions that automatically demote the project.
- **The five orthogonal axes** — how rung composes with work-sizing tier, architecture, mid-build decision tier, and permission tier.
- **Composition with the rest of the doctrine** — work-sizing tier, role definitions, propagation cadence, project bootstrapping.

The ladder is what converts the doctrine from "methodology for AI-assisted application development" into "methodology for the full trajectory from supervised work to autonomous systems." It is the structural addition that makes the strategy of **building layers of abstraction until human role is minimized** safe to execute — by ensuring every rung promotion is gated on accumulated reliability evidence rather than aspiration.

Cross-reference: the reliability-first inversion is specified in `outputs/unified-methodology-recommendation.md` §3 (the 10-stage reliability spine) and §4 (autonomy progression reframed). Read that document's §3 first if rungs feel like a free-standing axis on a first reading; the spine is what makes the rungs derivative.

---

## Composition with NL's per-action trust model

This doc owns one autonomy axis — the project-level **rung** (R0–R5) describing where humans sit relative to the work. Two adjacent axes operate at different abstractions in NL and compose orthogonally with rung. Conflating rung with either of them loses information.

### Rung × Level — project-level commitment vs. per-action trust accumulation

NL's `~/.claude/principles/progressive-autonomy.md` defines a different autonomy schema: **Levels L1–L5** operating on a continuous **Trust Score** (0.0–1.0) per-project-per-tool. Trust starts at 0.3 (Level 2: Supervised), accumulates +0.02 per safe session, +0.03 on extended autonomous operation, decays -0.10 on user override of T3 block, -0.30 on credential leak, and is capped by infrastructure maturity (no CI → max 0.4 / Level 2; CI + tests → max 0.6 / Level 3; CI + deploy validation + eval suite → max 1.0 / Level 5 possible). The system also enforces six **hard limits** that never relax regardless of Level (credential exposure, public exposure, account creation, irreversible data ops, financial transactions, security control changes — see `principles/progressive-autonomy.md`).

NL's `~/.claude/principles/permission-model.md` defines a third autonomy axis: **permission tiers T0–T3** (T0 Silent Allow / T1 Log & Allow / T2 Confirm / T3 Block) decided per-action via a composite score across six risk dimensions (D1 Reversibility / D2 Blast Radius / D3 Sensitivity / D4 Authority Escalation / D5 Novelty / D6 Velocity), each scored 0–4. The composite is `max(D1,D2,D3,D4) × (1 + D5×0.15) × (1 + D6×0.1)` and selects the tier. Trust Score adjusts the boundaries between tiers (more T0 / less T2 at higher trust) but the T3 / hard-limits boundary barely moves.

### Three orthogonal axes, three abstractions

The composition rule is straightforward, and all three coexist on every dispatched action:

1. **Doctrine Rung (this doc)** is per-project commitment about WHERE HUMANS SIT. Rung is recorded in `engineering-catalog.md`, restated in every PRD, and changes only via gated promotion/demotion events. Rung answers "how autonomously is this project executed?"
2. **NL Level (`progressive-autonomy.md`)** is per-project-per-tool runtime calibration via Trust Score. Level changes continuously as Trust accumulates / decays. Level answers "how much trust does the harness extend to each action right now?"
3. **NL Permission tier (`permission-model.md`)** is per-tool-action runtime decision via composite risk score. Permission tier is computed at every Edit / Write / Bash / Task. Permission tier answers "what does the harness do with THIS specific action?"

A Rung 4 project running an irreversible production deploy still hits T2 (Confirm) or T3 (Block) because the action's blast radius is high regardless of project rung. The doctrine commits the project's operating mode; the harness calibrates per-action behavior within that commitment. A project at Rung 1 (every PR human-reviewed) may have its harness extend Level 4 trust on safe-pattern operations within an individual session; the two abstractions don't contradict — Rung is the project-level cadence, Level is the per-action runtime trust.

This is the resolution Phase 1a R-7 documented and `outputs/unified-methodology-recommendation.md` §4 confirmed: keep both vocabularies, cross-reference them as orthogonal axes, do not force one to renumber. Conflating them would erase the difference between project-level commitment and per-action runtime calibration — both of which matter.

---

## The rungs — each defined by gate set + review cadence

Six rungs. Each rung describes (a) which gates from the 10-stage reliability spine are wired up at this project, (b) where humans sit relative to the work — i.e., review cadence and depth — and (c) the architecture options compatible with this rung. **The substance is the gates; the rung is the cadence-and-review pattern.**

### Rung 0 — Pair programming with AI

**This rung exists because:** the most upstream gates of the reliability spine (Stage 0 bootstrap, Stage 1 PRD intake, Stage 2 spec freeze, Stage 6 per-task verification) operate with human eyes on every line of generated code. The architecture is "AI as an IDE assistant"; the human is the author and reviewer in real time.

**Required gates (from reliability spine — see `outputs/unified-methodology-recommendation.md` §3 Stage 0–6):** type checks, lint, format, schema validation, frontmatter, scope enforcement, unit tests, PRD-validity (Stage 1), spec-validity (Stage 2), manual code review by author (Stage 6). Adversarial review optional.

**Where humans sit:** in the IDE, in real time, with every line. The human is the author; the AI is the assistant.

**What the gate stack protects against:** ordinary software defects. AI assistance is treated as a tool, not a participant in the work. Stage 6 (per-task verification) collapses into the human's real-time read.

**Architecture options:** coding-harness only.

### Rung 1 — AI generates, human reviews

**This rung exists because:** Stage 5 (builder dispatch) is now LLM-bounded — the AI authors the unit at unit-of-work scale — so Stage 6 (per-task verification) and Stage 7 (adversarial review) must fire on every PR with humans verifying. The gate stack includes the Rung 0 set plus the adversarial-review apparatus from Stage 7 + the integration / contract / runtime-verification apparatus from Stage 6.

**Required gates:** all Rung 0 gates plus mandatory adversarial review (Stage 7, tier-appropriate depth), integration tests where applicable (Stage 6), contract tests when boundaries are touched (Stage 6), mandatory human code review (Stage 6).

**Where humans sit:** reviewing every PR in detail. The question shifts from "should I write this differently?" (Rung 0) to "is this implementation correct and does it match the spec?" (Rung 1).

**What the gate stack protects against:** AI completion bias (claims work done that isn't), edge case omission, contract drift, scope creep within a unit. Adversarial review (Stage 7) is the structural backstop on AI self-assessment.

**Architecture options:** coding-harness; orchestration possible at the multi-step-workflow boundary (NL `rules/orchestrator-pattern.md`).

**Most projects start here.** New projects default to R1 unless explicitly justified otherwise (see `08-project-bootstrapping.md`).

### Rung 2 — AI generates and tests, human spot-checks

**This rung exists because:** Stage 6 (per-task verification) gains comprehension-gate verification (forthcoming C15) plus property-based tests on hot paths and mutation tests on critical paths (forthcoming C13). The AI generates not just code but the test apparatus that would have been written by an independent reviewer at Rung 1. Human review density drops because Stage 6's mechanical density rises.

**Required gates:** all Rung 1 gates plus property-based tests on hot paths, mutation testing on critical paths, **comprehension gate** (Stage 6 — security/blast radius pass; forthcoming as `comprehension-reviewer.md` agent C15), strengthened spec contracts (behavioral contracts beyond type signatures — anticipating Rung 3's C16).

**Where humans sit:** reviewing the diff selectively. Reviewing test additions in detail (because tests are now the agent's quality argument, not just code). Reviewing comprehension-gate findings always.

**What the gate stack protects against:** AI gaming its own tests. Without tests written by an independent reviewer (property-based generators, mutation tests that introduce defects), the agent's self-validation is suspect. The comprehension gate adds the "do we understand what this does in context" layer that adversarial review's "what's wrong?" doesn't cover.

**Architecture options:** coding-harness; orchestration; light orchestration for test generation.

### Rung 3 — AI generates and validates, human reviews specs

**This rung exists because:** Stage 2 (spec freeze) gains behavioral-contracts schema enforcement (C16); Stage 6 (per-task verification) gains bilateral contract tests (C3) and behavioral-contract validation (idempotency, performance budgets, retry semantics, failure modes); Stage 8 (propagation) auto-resolves more triggers without human disposition. The human role shifts from "reads code on routine units" to "reviews specs and validation outcomes." The gate stack carries the load that human PR review used to.

**Required gates:** all Rung 2 gates plus contract tests on **both sides** of every boundary (forthcoming C3), integration tests across all touched module boundaries, **behavioral contract validation** (idempotency, performance budgets, retry semantics, failure modes — forthcoming C16 enforces the schema in `## Behavioral Contracts` section of every Rung 3+ spec), mandatory ADR for any pattern not in canon.

**Where humans sit:** authoring the spec. Reviewing the validation outcomes (did the gates pass and why). Reading code only on findings or for spot audits.

**What the gate stack protects against:** underspecified specs producing precisely-specified garbage. The shift to spec-only review means the spec must be exhaustive enough to fully constrain the implementation. Behavioral contracts (C16) and bilateral contract tests (C3) are the deterministic backstop on this — when humans don't read code, the spec + contracts + tests are the only thing constraining what ships.

**Architecture options:** coding-harness with high autonomy; orchestration for multi-step workflows.

### Rung 4 — AI runs autonomous loops with metric optimization

**This rung exists because:** the auto-research architecture (per Nate B. Jones taxonomy, `08-project-bootstrapping.md` and N-A-1) requires a computable scoring function that becomes the primary quality gate. Stage 6 (per-task verification) extends to include scoring-function evaluation; Stage 9 (acceptance scenarios) gains **holdout scenarios** stored outside the codebase (forthcoming C14) so the optimizing agent can't game them. Human review density drops to "metric definition + outcome confirmation" only.

**Required gates:** all Rung 3 gates plus computable scoring function with externally-defined target, comprehensive test suite as guardrail (anti-regression), **holdout scenario validation** (forthcoming C14 — scenarios stored OUTSIDE the project repo, agent has no read access during development; required at Rung 4–5), runtime budget caps (compute, time, iterations).

**Where humans sit:** defining the metric. Defining the boundaries. Reviewing convergence outcomes. Confirming the metric is measuring what was intended.

**What the gate stack protects against:** optimization-by-deletion (agent makes the metric better by removing functionality). Scoring functions that don't measure what was intended. Holdout scenarios are critical here because regular tests in the codebase are visible to the optimizing agent and therefore gameable.

**Architecture options:** auto-research (per N-A-1) — REQUIRED for Rung 4. Coexists with coding-harness work at lower rungs in hybrid projects (each work unit declares its sub-architecture; gate matrix in `04-gates.md` applies per sub-architecture).

**Architecture-specific:** the auto-research pattern fundamentally requires a computable metric. Without one, the loop has nothing to optimize against. Projects attempting Rung 4 without this should be re-classified as Rung 2 or 3 work that doesn't need the autonomous loop.

### Rung 5 — Dark factory operation

**This rung exists because:** the dark-factory architecture (per N-A-1) requires that no human read the code; the validation system is the only quality gate. Stage 9 (acceptance scenarios) becomes the project's primary verification surface, backed by holdout scenarios + digital twin universe + evidentiary verification (tamper-evident audit trail of what the agent considered, generated, and rejected). The dark-factory architecture is **a project-level ADR** in itself (forthcoming C22 cross-references the ADR-level decision per project to operate at this rung).

**Required gates:** all Rung 4 gates plus mandatory holdout scenario validation (C14 — required, not recommended), digital twin universe (high-fidelity replicas of dependencies for safe testing at scale), evidentiary verification (tamper-evident audit trail), **dark-factory architecture review** (an ADR-level decision per project to operate at this rung — see `04-gates.md` ADR-adoption gate).

**Where humans sit:** authoring specs at extraordinary precision. Maintaining the holdout scenario set. Reviewing dark-factory output via metric outcomes only — never code, never PRs, never line-by-line.

**What the gate stack protects against:** everything below + the catastrophic failure mode of a dark factory shipping bad software at scale because nobody reads it. The holdout scenarios and evidentiary verification are the only defense against this; both are non-negotiable.

**Architecture options:** dark-factory only. Hybrid projects may dispatch dark-factory units alongside lower-rung sub-architectures, but the dark-factory unit itself must be at Rung 5.

**Architecture-specific:** the dark factory pattern fundamentally requires verifiable behavioral scenarios. Domains where quality is subjective (creative writing, design taste, novel UX) cannot operate at Rung 5. The doctrine refuses to dispatch dark-factory work without a validation system that can determine "good" without human taste.

---

## Gate set summary by rung × architecture

The gate matrix here is the rung-axis view of the matrix in `04-gates.md`'s integrated-v1 (which parameterizes by architecture × rung × tier). This view is parameterized by **rung × architecture** to make the architecture × rung feasibility constraints explicit. Auto-research is feasible only at Rung 4+; dark-factory only at Rung 5. Each architecture row describes which gates fire, not which rungs are accessible — accessibility is the cross-product.

| Gate | R0 (coding-harness) | R1 (coding-harness, orchestration) | R2 (coding-harness, orchestration) | R3 (coding-harness, orchestration) | R4 (+ auto-research) | R5 (dark-factory) |
|---|---|---|---|---|---|---|
| Type checks, lint, format | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Unit tests | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Schema validation, frontmatter, scope | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Manual code review | ✓ author | ✓ reviewer | spot | — | — | — |
| Adversarial review (Stage 7) | optional | ✓ | ✓ | ✓ | ✓ | ✓ |
| Integration tests | when applicable | when applicable | ✓ | ✓ | ✓ | ✓ |
| Contract tests | when boundary touched | when boundary touched | ✓ | ✓ both sides (C3) | ✓ both sides | ✓ both sides |
| Property tests on hot paths | — | — | ✓ (C13) | ✓ | ✓ | ✓ |
| Mutation tests on critical paths | — | — | ✓ (C13) | ✓ | ✓ | ✓ |
| Comprehension gate (C15) | — | — | ✓ | ✓ | ✓ | ✓ |
| Behavioral contracts schema (C16) | — | — | — | ✓ | ✓ | ✓ |
| ADR for novel patterns | — | — | — | ✓ | ✓ | ✓ |
| Computable scoring function | — | — | — | — | ✓ (auto-research only) | ✓ |
| Holdout scenarios (C14) | — | — | — | — | ✓ (auto-research) | ✓ (no escape) |
| Runtime budget caps | — | — | — | — | ✓ | ✓ |
| Digital twin universe | — | — | — | — | optional | ✓ |
| Evidentiary verification (C21) | — | — | — | — | optional | ✓ |
| Dark factory architecture ADR (C22) | — | — | — | — | — | ✓ |

Each rung's gate set is **cumulative** — Rung N includes everything from Rungs 0 through N-1, plus the additions specific to Rung N. There is no demotion of gates as autonomy increases. The whole point is that gates compound to compensate for reducing human oversight.

**Architecture × rung feasibility constraints (per N-A-1):**

| Architecture | Rung availability | Notes |
|---|---|---|
| Coding harness | R0–R3 | Default architecture for application development. Tier within work-sizing rubric (T1–T5) operates orthogonally. |
| Orchestration | R1–R4 | Multi-step workflows; handoff schemas need verification at R1+. |
| Auto research | R4 only | Requires computable scoring function. Cannot operate at lower rungs without becoming "supervised auto research" (misclassified). |
| Dark factory | R5 only | Requires holdout scenarios + verifiable behavioral domain. The destination, not a starting point. |
| Hybrid | Any rung | A project may run different units at different rungs and architectures. Spec declares per-unit architecture; orchestrator enforces gate set per-unit per-sub-architecture. |

The architecture/rung pairing is not arbitrary. **An architecture's required quality gate determines the lowest rung it can operate at.** Auto-research's scoring function is meaningless at supervised rungs (a human is making the calls). Dark-factory's holdout scenarios are over-engineered when humans are reading every PR. Coding-harness's "human judgment as quality gate" is incompatible with R4–R5 where humans don't make per-unit calls.

This matrix mirrors `04-gates.md` for consistency. Both are anchored in the same five orthogonal axes (see next section) and the same C-mechanism cross-references.

---

## Five orthogonal axes

Per `outputs/glossary.md` and `03-work-sizing.md` "Five orthogonal axes" section, every unit of dispatched work is described by **five orthogonal axes**. This doc owns the **Rung** axis; the other four are referenced.

| Axis | Domain | What it measures | Where defined |
|---|---|---|---|
| Work-sizing tier | T1–T5 | Complexity of contract surface and decomposition cost | `03-work-sizing.md` |
| **Autonomy rung** | R0–R5 | **Project-level commitment about where humans sit** | **This doc** |
| Architecture | coding-harness / orchestration / auto-research / dark-factory / hybrid | Agent topology the project employs | `08-project-bootstrapping.md` (per N-A-1) and this doc |
| Mid-build decision tier | T1–T3 | Reversibility of decisions made *during* a build | NL `~/.claude/rules/planning.md` |
| Permission tier | T0–T3 | Per-action runtime risk via 6-dimension composite scoring | NL `~/.claude/principles/permission-model.md` |

The axes do not collapse. A small-effort Tier 1 work-sizing unit at Rung 4 with `architecture: auto-research` may produce a Tier 3 mid-build decision (irreversible schema change discovered mid-build) which triggers NL's pause-and-wait protocol regardless of the unit's lower-axis values; the unit may also produce T2 (Confirm) and T3 (Block) actions per `permission-model.md` regardless of the project's Trust Score-derived Level. **All five enforce simultaneously.** Conflating any two erases information; see `03-work-sizing.md` "Common conflation patterns" for examples.

The per-axis allocation:

- **Work-sizing tier** is declared per-spec (`tier: 1-5`).
- **Rung** is declared in `engineering-catalog.md` profile section, optionally overridden per-spec (`rung: 0-5`). Owned by this doc.
- **Architecture** is declared in project canon, optionally overridden per work unit when a project runs hybrid (`architecture: coding-harness | orchestration | auto-research | dark-factory | hybrid`).
- **Mid-build decision tier** is NOT a spec-header field — it is evaluated per-decision at build time when a Tier 2 or Tier 3 reversibility threshold is crossed.
- **Permission tier** is NOT a spec-header field — it is evaluated per-tool-action at runtime by the harness's permission model.

The first three are declared up-front; the last two are evaluated dynamically as the build proceeds. Per Q4 of `outputs/unified-methodology-recommendation.md` §9, the **three-axis spec-header schema** is `tier: 1-5` + `rung: 0-5` + `architecture: <one of five>`.

---

## Promotion criteria — reliability evidence, not aspiration

Promotion to a higher rung is a conscious, evidence-based, gated decision. **It is not gradual drift, and it is not aspiration — it is mechanical evidence that the gates required at the next rung have been wired up AND have produced findings demonstrating sustained reliability at the current rung.**

Promotion authority remains human (knowledge integrator role + Misha sign-off per `02-roles.md`). The eligibility check is mechanical, against the project's accumulated reliability evidence. Per `outputs/unified-methodology-recommendation.md` §4, the proposed mechanism is **C13 — Promotion / demotion gate** (`autonomy-rung-gate.sh`, forthcoming Phase 1d-C work): SessionStart hook reads project's rung field + last-N findings-ledger entries + verifies promotion criteria against the gate config.

### Required evidence per promotion (reliability metrics)

To promote any project from Rung N to Rung N+1, the project must demonstrate:

1. **Sustained green at Rung N — measured as zero severity≥error findings AND zero runtime acceptance failures AND zero session-end integrity violations on plans completed at this project for the sustained-green window** (recommended minimum: 30 days of active work; tunable per `gate-config.yaml`). The findings-ledger schema (forthcoming C9 — `findings-ledger-schema-gate.sh`) is the mechanism that quantifies "sustained green" mechanically; without C9, this criterion is paper-only.
2. **Findings-ledger pattern review** — no recurring patterns of severity ≥ error in the last sustained-green window. Persistent unresolved findings are a promotion blocker until resolved. (Mechanical check via C9 findings-ledger.)
3. **Adversarial review consistency** — the seven adversarial-reviewer agents (`code-reviewer`, `security-reviewer`, `harness-reviewer`, `claim-reviewer`, `plan-evidence-reviewer`, `ux-designer`, `systems-designer`) have produced consistent finding patterns across recent units (severity distribution roughly stable), indicating reviewers are calibrated.
4. **Spec quality threshold** — drift log entries below the project's drift threshold for the sustained-green window. High drift means specs aren't catching what they should catch and the project is not ready for less spec review.
5. **Specific Rung N+1 capability validated in test environment** — the new gates required at Rung N+1 must be wired up, exercised against representative work, and producing useful findings, not stubbed or skipped.

Plus one rung-specific reliability check that names which forthcoming C-mechanism operationalizes the eligibility for that promotion:

| Promotion | Specific reliability check (and which C-mechanism mechanizes it) |
|---|---|
| R0 → R1 | Adversarial review pipeline operational; reviewer is independent of builder (different model family preferred). C1 (PRD-validity gate) operationalizes upstream PRD freeze; C20 (telemetry-feeds-ledger) records reliability evidence. |
| R1 → R2 | Property test generators tuned (C13 — mutation-test threshold); mutation tests producing useful findings (C13); comprehension gate operational and producing findings on representative units (C15 — comprehension-gate agent); C2 (spec-freeze gate) operationalizes spec-quality reliability. |
| R2 → R3 | Behavioral contracts written for all critical surfaces (C16 — `## Behavioral Contracts` schema check); bilateral contract tests passing on representative cases (C3); C7 (DAG-gate) operationalizes the human DAG-review checkpoint at Tier 3+; C16 mechanizes the gate. |
| R3 → R4 | Computable scoring function defined and validated against human judgment on a holdout set; runtime budget caps tested; C18 (holdout scenario gate) confirms holdout scenarios are present and passing on representative work; C20 (telemetry-feeds-ledger) confirms the auto-research loop's telemetry feeds the findings ledger. |
| R4 → R5 | Holdout scenario set independently maintained; evidentiary verification audit trail working (C21 — evidentiary verification); project ADR for dark-factory operation reviewed and accepted (C22 — dark-factory ADR review). |

C9 (findings-ledger schema) cross-references **every promotion** because findings-ledger is how reliability evidence is recorded. C20 (telemetry-feeds-ledger) cross-references every promotion because it ensures the telemetry → ledger pipeline actually fills the ledger from runtime evidence. Without C9 + C20, "sustained green" is a paper claim; with them, it's a measurable threshold.

C13 (mutation-test threshold) is the rung-specific check at R1→R2; C14 (property-test generators) is the rung-specific check at R1→R2; C15 (comprehension-gate agent) is the rung-specific check at R1→R2 and operates continuously at R2+; C16 (behavioral-contracts validator) is the rung-specific check at R2→R3 promotion and operates continuously at R3+; C18 (holdout scenario gate) is the rung-specific check at R3→R4 promotion; C19 (digital twin universe) is the rung-specific check at R4→R5; C21 (evidentiary verification) is the rung-specific check at R4→R5; C22 (dark-factory ADR review) is the rung-specific check at R4→R5.

These C-mechanisms are forthcoming Phase 1d-C work; today the discipline is pattern-only and the eligibility check is human judgment guided by the criteria above. Once C9 and C13 land, the eligibility check is mechanical.

### Promotion authority

Promotion is a doctrine-level event. The knowledge integrator role authorizes promotion, with explicit human (Misha or designated authority) sign-off. Promotion is logged with date, evidence cited (findings-ledger entries during the sustained-green window), and rationale — it's a doctrine artifact in the project's CHANGELOG.

A project's current rung is recorded in its `engineering-catalog.md` profile section and re-stated in every PRD it produces. Specs inherit the project's rung unless they explicitly downgrade (a Rung 4 project may dispatch a Rung 1 unit for a sensitive change).

---

## Demotion conditions — automatic on reliability degradation

Demotion is automatic and immediate when triggered. **Demotion is not punishment; it is the doctrine's recognition that the evidence supporting the current rung has been compromised.** Per `outputs/unified-methodology-recommendation.md` §4, C13 (`autonomy-rung-gate.sh`) mechanizes demotion: orchestrator (deterministic) auto-decrements the rung field on reliability-evidence regressions; human (Misha) auto-decrements on triggers requiring judgment.

Each demotion trigger is a reliability-evidence regression that some specific gate detected:

1. **Severe finding produced — auto-demotes one rung until the finding is resolved AND the resolution is itself gated at the lower rung.** Detection comes from the findings-ledger (forthcoming C9): any new finding of severity `severe` flips the project's rung field down. Resolution requires (a) the finding's status flipped to `closed` in the ledger AND (b) the resolution work itself dispatched at the demoted rung's gate set.
2. **Production incident attributable to the project at current rung.** Detection is human-reported (no mechanical trigger today; future-state telemetry → ledger pipeline per C20). Demotion holds until incident postmortem completes and identifies whether the rung's gates failed or were absent.
3. **Holdout scenario validation regression** — for Rung 4–5 projects, any drop in scoring function pass rate or holdout scenario pass rate that exceeds the project's defined regression threshold. Detection comes from the runtime acceptance gate (`product-acceptance-gate.sh`) plus the forthcoming C18 (holdout scenario gate).
4. **Sustained drift pattern** — drift log entries above the threshold for two consecutive review cycles indicates spec quality has degraded and Rung 3+ work is no longer adequately constrained. Detection comes from the drift log + findings-ledger (C9).
5. **Repeated tier-transition findings** — frequent mid-execution tier transitions indicate the planner or spec author is misclassifying work, which is itself a signal that judgment about what to dispatch is degrading. Detection comes from the orchestrator's tier-transition log (forthcoming C8 — tier-transition halting gate).
6. **External regulatory or compliance event** — new requirements that the current rung's audit trail cannot satisfy. Detection is human-reported.

Demotion authority: orchestrator (deterministic via C13) for triggers 1, 3, 4, 5. Human (Misha or designated) for triggers 2 and 6. Demotion is logged in the project's CHANGELOG with trigger and date.

**Re-promotion** after demotion follows the standard promotion criteria — sustained green at the demoted rung, findings-ledger clean, etc. Demotion is not a stigma; it is part of the autonomy ladder operating correctly.

---

## Composition with the rest of the doctrine

### With work-sizing tier (`03-work-sizing.md`)

Tier and rung are orthogonal axes — see the "Five orthogonal axes" section above and `03-work-sizing.md`'s "Five orthogonal axes" section for the canonical treatment. A Rung 1 project may dispatch Tier 1, 2, 3, or 4 units. A Rung 4 project may dispatch Tier 1 (auto-research on a small optimization) or Tier 4 (auto-research on a complex contract surface) — the rung determines how it's gated; the tier determines how it's structured. Per `03-work-sizing.md`, the spec-header schema declares both: `tier: 1-5` + `rung: 0-5` + `architecture: <one of five>`.

The combination of tier + rung + architecture determines the full gate set. All three must be specified in the spec; orchestrator enforces the gate set produced by the cross-product (see gate matrix in `04-gates.md`).

### With architecture (per N-A-1 in Phase 1b)

Architecture is the third orthogonal axis. A spec declares `architecture` (coding-harness / orchestration / auto-research / dark-factory / hybrid). The architecture × rung combination is constrained per the matrix above; not every combination is valid (e.g., auto-research at Rung 1 is misclassified work). The architecture-by-rung feasibility table is mirrored in `04-gates.md`'s gate matrix, which parameterizes by architecture × rung × tier.

### With role definitions (`02-roles.md`)

The roles in `02-roles.md` operate at every rung; what changes by rung is the **density of human role activity**:

- **Rung 0–1:** Builder (human or human+AI), every-PR human review, full role activation. Adversarial Reviewer role (5/6 NL agents) operates per-PR.
- **Rung 2–3:** Builder (AI), spec author (human, frequent), adversarial reviewer (LLM via the seven NL agents), human checkpoint (only at irreversibility boundaries — T2/T3 mid-build; T2/T3 permission tier). Comprehension-gate agent (forthcoming C15) operates as an additional reviewer at R2+.
- **Rung 4–5:** Spec author (human, deep), adversarial reviewer (LLM with holdout-scenario backstop via C18), human checkpoint (at architecture-level decisions only — ADR adoption per `04-gates.md`). Builder role activity is largely autonomous; orchestrator role activity (forthcoming C7 deterministic-orchestrator full form) coordinates the dispatch.

The roles do not change. The frequency and depth of human role activity decreases as rung increases. The doctrine remains structurally identical; the operating cadence shifts.

### With propagation (`06-propagation.md`)

Higher rungs propagate more aggressively because the cost of a stale artifact is higher when there's less human review to catch it. Specifically:

- **Rung 0–2:** Standard propagation per `06-propagation.md`. Findings opened; curators act on cadence.
- **Rung 3+:** Auto-update is the default for mechanical propagation; findings only opened when interpretation is required. Stale artifacts at Rung 3+ are treated as severity `error`, not `warn`. The forthcoming C12 (propagation-event hook generalization) is the mechanism that operationalizes this rung-aware auto-update behavior.
- **Rung 4–5:** Cross-repo edges in `pending propagation` block any irreversible action until consumers acknowledge (forthcoming C17 — cross-repo edge `pending propagation` blocker). The doctrine refuses to ship at high autonomy with unresolved propagation.

### With project bootstrapping (`08-project-bootstrapping.md`)

Stage 0 of bootstrap captures the project's **starting rung**. New projects default to Rung 1 (AI generates, human reviews) unless explicitly justified otherwise. Bootstrapping at Rung 4 or 5 requires the corresponding gate infrastructure (C18 holdout scenarios; C21 evidentiary verification; C22 dark-factory ADR) to exist before bootstrap can complete.

The autonomy ladder is referenced from Stage 0 explicitly: "What rung does this project start at, and what's the trajectory?" Stating the trajectory at bootstrap is what makes promotion later feel like a gated step rather than gradual drift.

### With NL principles

`~/.claude/principles/progressive-autonomy.md` (Trust Score / Levels L1–L5) and `~/.claude/principles/permission-model.md` (T0–T3 tiers / six dimensions) are referenced in the "Composition with NL's per-action trust model" section above. Both compose orthogonally with this doc's Rung axis. Every dispatched action carries: project Rung (this doc), per-tool Trust-Score-derived Level (`progressive-autonomy.md`), per-action Permission tier (`permission-model.md`), plus the work-sizing Tier and mid-build Tier where applicable.

---

## Operating principles for the ladder

### Reliability evidence drives promotion, not aspiration

A project at Rung 3 wants to be at Rung 4 — but cannot promote until C18 / C21 mechanisms are wired up AND have produced findings-ledger evidence of sustained green at Rung 3. **Wanting to be at a higher rung is not evidence; reliability metrics are.** The promotion eligibility check is mechanical against accumulated findings-ledger entries (C9 + C20); the eligibility decision is human (knowledge integrator + Misha). Aspiration without evidence is the named anti-pattern this doctrine exists to prevent.

### The right rung is the one your gates support

A project's correct rung is determined by which gates are operational and producing useful findings, not by which rung the team wishes they were at. Aspiring to Rung 4 without a computable scoring function means the project is at Rung 3 with extra ceremony. The doctrine names this honestly. With the inversion in place — rung is metadata over the gate stack — this principle is structural, not aspirational: the rung field cannot meaningfully exceed the gates wired up at the project, because the gates ARE what the rung describes.

### Promotion is a conscious, gated, evidence-based decision

The most common failure mode in autonomy adoption is gradual drift — a team starts reviewing every PR, gradually reviews fewer, eventually reviews none, and discovers the gap in production. The ladder makes this drift impossible: at each rung, the doctrine requires gates the previous rung didn't, and those gates must be operational and producing findings before promotion. There is no "casually skip a rung" path. With the inversion, drift is structurally impossible — rung is a function of which gates are wired up, not a free-standing choice.

### Demotion is part of the system working

Demotion is not failure. It is the doctrine recognizing that evidence supporting a rung has been compromised and adjusting until evidence is restored. Projects that never demote are either operating below their actual rung (possible) or hiding regressions (more likely). A demotion event is data, not stigma.

### Trust accumulates gate-by-gate, not all at once

Each rung's gate additions correspond to a specific failure mode the previous rung's gates don't catch. The rung structure is deliberate: comprehension gates (C15) at Rung 2 catch dark code; behavioral contracts (C16) at Rung 3 catch silent assumption failures; holdout scenarios (C18) at Rung 4–5 catch test gaming; evidentiary verification (C21) at Rung 5 catches agent introspection drift. **Skipping a rung means skipping a class of detection.** The compound effect across stages is what makes Rung 5 operation safe at all.

### Specifications get heavier as autonomy increases

At Rung 0, the spec is documentation. At Rung 5, the spec is the only thing constraining what ships. Every rung the project promotes through requires the spec to do more work. C16 (behavioral-contracts schema check) makes this requirement mechanical at R3+: the spec MUST include a `## Behavioral Contracts` section with idempotency / performance budget / retry semantics / failure modes. **This is the hidden cost of high autonomy** — it does not eliminate engineering effort, it relocates it from code review to specification authoring. Teams unprepared for this will produce precisely-specified garbage at high autonomy and conclude AI doesn't work.

### Architecture choice is a rung commitment

Selecting auto-research or dark-factory architectures is a commitment to operate at Rung 4 or 5. The architectures aren't separable from the rungs that support them. A project cannot run "supervised dark factory" — that's misclassified Rung 2 work. **Honesty about architecture is honesty about rung.**

---

## Anti-patterns

### Drift up the ladder without evidence

Gradually reducing human review without consciously promoting the project's rung. The most common failure mode and the one the ladder exists to prevent.

**With the inversion applied**, this anti-pattern is structurally impossible: rung is a function of which gates are wired up, so reducing human review without wiring up the next-rung gates produces an inconsistent state that mechanical detection (C13) flags. Without the inversion, drift happens by accretion — the gate set doesn't change but the human-review density quietly drops. Mitigation: rung is a declared property of the project, written in `engineering-catalog.md`, restated in every PRD; reducing human-review density without the corresponding gate additions IS the demotion trigger that C13 detects.

### Aspirational rung declaration

Declaring the project at Rung 4 because that's where you want to be, without the gates to support it. The doctrine catches this mechanically: schema validation on the project's rung field requires the gate infrastructure (forthcoming C13 schema check + C18 / C21 / C22 presence checks) to be operational, not just configured.

**With the inversion applied**, this anti-pattern is structurally impossible because the rung describes the gates, not the team's aspiration. A project with no holdout-scenario harness cannot be at Rung 4; the rung field can claim Rung 4 but the validator (C13) sees no C18-required holdout scenarios and demotes / blocks promotion until evidence appears. Without the inversion, the rung is a free-standing axis and the validator has nothing to check against.

### Skipping rungs to ship faster

"We don't need property tests yet, we'll add them at Rung 4." Each rung's gates exist because they catch specific failure modes the previous rungs don't. Skipping a rung means accumulating the failure modes that rung was designed to catch. The doctrine does not allow rung skipping; promotion is one-rung-at-a-time minimum. C13 enforces this mechanically: the rung field cannot increment by more than 1 per promotion event.

### Treating demotion as failure

Demotion events are signal, not punishment. A project that never demotes is either operating below capacity or hiding evidence. Knowledge integrator should review demotion patterns and surface them for ritual review — both unusually frequent demotion (signal that the project is over-aspiring) and unusually absent demotion (signal that something isn't being detected).

### Architecture without rung commitment

"We're using CrewAI for orchestration but everyone still reviews every PR." If humans are reviewing every PR, the orchestration architecture is over-engineered for the actual rung. Either commit to Rung 3+ to leverage the architecture, or use coding-harness pattern that fits the supervision level.

### Higher rung means less work for humans

Rung promotion does not reduce human work; it relocates it. From PR review to spec authoring. From per-unit decision to gate design. From "is this code right?" to "is this validation strategy right?" Teams expecting headcount reduction from rung promotion will find the math doesn't work; teams expecting time reallocation toward higher-leverage activities will find the math does work.

### Confusing Rung with Level or Permission tier

Conflating the project-level Rung commitment with NL's per-action Level (Trust Score) or per-action Permission tier (T0–T3 composite scoring). They measure different things at different abstractions; see "Composition with NL's per-action trust model" above. A Rung 4 project running an irreversible production deploy still hits T2/Confirm or T3/Block because the action's blast radius is high regardless of project rung. The Rung field doesn't override the per-action gate; the per-action gate doesn't downgrade the Rung field.

---

## Open during fresh-draft phase

- **Sustained-green window calibration.** 30 days is a working default; pilot use will calibrate. Different project velocities may warrant different windows. The forthcoming C9 (findings-ledger schema) makes the window mechanical; the threshold is configurable per `gate-config.yaml`.
- **Promotion criteria precision.** Some criteria above (drift threshold, regression threshold) are project-specific. The doctrine specifies that thresholds exist; projects set the values during bootstrap.
- **Cross-rung dispatch within a single project.** A Rung 3 project dispatching a Rung 1 unit for a sensitive change works; a Rung 1 project dispatching a Rung 4 unit does not (the project doesn't have the gate infrastructure). The doctrine should make the constraint mechanical: dispatchable rungs are bounded by the project's current declared rung. C13 enforcement at spec freeze (C2) is the natural location for this check.
- **Knowledge integration cadence per rung.** Higher rungs likely need more frequent knowledge integration ritual review because more is happening autonomously. Specifics deferred to `07-knowledge-integration.md` (drafted last per master plan).
- **Rung 4–5 specifics for non-coding work.** The ladder is currently described primarily through software examples. Auto-research and dark-factory patterns for analytical work, content generation, and operational workflows need explicit examples in templates phase.
- **Vocabulary precision for "Level" vs "Rung" in cross-doctrine references.** Per the glossary, Rung (this doc, R0–R5) and Level (NL `progressive-autonomy.md`, L1–L5) are kept distinct. Doctrine docs use "Rung" exclusively; references to NL's L1–L5 always say "Level" with the cross-reference to `principles/progressive-autonomy.md`. This avoids the failure mode where one author writes "the project is at Level 3" and a second reader interprets that as Rung 3.

## Next steps

The Phase 1d-C work (forthcoming) implements the C-mechanisms cross-referenced throughout this document, in roughly this order per `outputs/unified-methodology-recommendation.md` §6:

- **First-pass:** C1 (PRD-validity), C2 (spec-freeze), C9 (findings-ledger schema), C7-DAG-gate, C16 (behavioral contracts), C15 (comprehension-gate agent). These together close the highest-leverage reliability gaps and make the gate-stack-as-rung mapping mechanical.
- **Second-pass:** C13 (promotion / demotion gate, dependent on C9), C14 (property-test generators), C18 (holdout scenarios gate), C20 (telemetry-feeds-ledger). These mechanize the promotion eligibility check end-to-end.
- **Longer-term:** C19 (digital twin universe), C21 (evidentiary verification), C22 (dark-factory ADR review). These mechanize Rung 5 specific gates.

Until C9 + C13 land, the eligibility check is human judgment guided by the criteria above. After they land, the eligibility check is mechanical; the eligibility decision remains human (knowledge integrator + Misha). The reliability spine is the load-bearing axis; this ladder is the metadata describing how reliability evidence at each rung translates to autonomy progression.
