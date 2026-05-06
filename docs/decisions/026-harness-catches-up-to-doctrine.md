# ADR 026 — Harness Catches Up to Doctrine

**Date:** 2026-05-05
**Status:** Active
**Stakeholders:** Maintainer (decision authority); orchestrator + builder + reviewer agents (governed by this decision); future-session orchestrators (downstream consumers).

## Context

Two months of harness development (Generations 4 → 5 → 6 → Build Doctrine integration) have shipped via reactive failsafe stacking — each new gate added in response to a specific failure mode. The cumulative result is a verification stack that costs more than the work it gates. As of 2026-05-05, closing a 7-task harness-dev plan requires ~13 sub-agent dispatches and ~65K tokens.

In parallel, the Build Doctrine has been authored at `~/claude-projects/Build Doctrine/outputs/` (~38000 words across 8 integrated-v1 docs) and partially migrated into `build-doctrine/doctrine/` in NL (Tranche 0b, this session). The doctrine articulates a coherent architecture for AI-assisted build rigor: 9 principles, 6 anti-principles, 10 roles, 6 gate categories, T1-T5 work-sizing tier rubric, 8-phase forward flow, 7-trigger propagation framework, 10-stage reliability spine. Anti-Principle 12 explicitly forbids stacking LLM gates without deterministic backstops.

A discovery + integration review committed in this session (`docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md` + `docs/reviews/2026-05-05-discovery-vs-build-doctrine-integration.md`) established that:

1. The harness has not been built TO its own doctrine.
2. The 10 architectural insights surfaced by the verification-overhead critique map 1:1 onto existing doctrine principles, gates, and roles.
3. The discovery is therefore not a contribution TO the doctrine — it is a forcing function for the harness to APPLY the doctrine to itself.

The user authorized full architecture redesign as Tranche 1.5 of the Build Doctrine roadmap, with a hard freeze on new failsafe work.

## Decision

**When the harness diverges from its doctrine, the harness is the side that catches up.**

Specifically:

1. **The Build Doctrine is the architectural source of truth for harness self-development**, not just for downstream-project work. The doctrine's principles, anti-principles, roles, gates, work-sizing tiers, forward-flow phases, and propagation triggers govern how the harness itself is built and maintained.

2. **Reactive enforcement is paused.** No new gates, hooks, or LLM-judgment validators land while the harness is in catch-up mode (Tranche 1.5 of the architecture-simplification redesign). The hard freeze remains in effect until at least Tranches A-E of the redesign land.

3. **Existing failsafes are evaluated for retirement during Tranche F** (failsafe audit) once the structural foundation is in place. Each gate in the 50-row enforcement map is marked KEEP / SCOPE-DOWN / RETIRE based on whether the new structure makes it redundant.

4. **Future divergences trigger this same "harness catches up" response automatically.** When a new failure mode is observed AND the doctrine has not yet been fully applied to the area where the failure occurred, the response is to advance the harness's doctrine-application — not to add a new failsafe layer.

5. **Doctrine extensions (the rare case)** are governed by the doctrine's own knowledge-integration ritual (Principle 8). When the harness's empirical experience surfaces a genuinely new architectural insight not yet in the doctrine, the insight feeds upstream via the ritual cadence — it does not produce ad-hoc harness code.

This decision establishes the precedent. Operationally it is implemented by Tranche 1.5 of the Build Doctrine roadmap.

## Alternatives Considered

### Alternative A — Continue stacking failsafes

Keep adding gates as new failures surface. Each is correct in isolation. Cumulatively the verification overhead continues to grow.

**Rejected because:** the trajectory is unsustainable. Verification cost has already exceeded the cost of the work it gates. Continuing produces a harness that is mechanically correct but operationally unusable. Empirically validated by the 2026-05-05 conversation surfacing this exact pattern.

### Alternative B — Partial redesign (incentive only, no structural)

Apply incentive redesign to agent prompts (orchestrator's "done" = "plan closed", builder's "done" = "verifier flipped checkbox", etc.) without touching the structural foundation. Cheaper to ship; addresses behavior at the agent level.

**Rejected because:** the discovery established that incentive redesign is necessary but not sufficient. Builders with corrected incentives still face the same prose-spec / prose-evidence / no-work-shape-library / oversized-tasks substrate. The closure dance remains heavy because the structure underneath is still the bottleneck. Incentive design ALONE does not deliver the "closure becomes a 4-second script" outcome.

### Alternative C — Partial redesign (structural only, no incentive)

Build the work-shape library, mechanical evidence substrate, deterministic close-plan procedure, etc. — but leave agent prompts unchanged.

**Rejected because:** structure without incentive change leaves builders looking for shortcuts around the structure. The Counter-Incentive Discipline sections shipped 2026-05-03 are partial; without completing the incentive redesign, the structural redesign's gains erode over time.

### Alternative D — Full redesign as a multi-tranche plan

Address both incentive design AND structural foundation. Pause new failsafe work. Build the missing layers. Retire or scope-down failsafes that the new structure makes redundant.

**Selected.** This is the discovery's recommendation, the user's authorization, and the operational expression of "harness catches up to doctrine."

### Alternative E — Doctrine extension first, harness application after

Extend the Build Doctrine with new principles (e.g., the "reactive enforcement compounding" anti-principle, the explicit Pareto-split rubric, the "harness as project" meta-loop) BEFORE applying it to the harness.

**Partially adopted.** Three small doctrine extensions (N1, N2, N3 from the integration review) WILL be authored — but they are sequenced AFTER Tranche 1.5 begins, not before. Reason: the doctrine is sufficient as architectural source; the extensions are catch-up not blockers. Doing them first would delay the harness work for marginal doctrine-completeness gains.

## Consequences

### Positive

- **Verification overhead drops dramatically.** Once Tranches A-E land (~14-22 days on critical path), closing a plan goes from ~13 dispatches + 65K tokens to a 4-second deterministic script.
- **The harness becomes self-conforming with its own architecture.** Every future change is a doctrine-application exercise, not a doctrine-deferring patch. Compound interest of doctrine application replaces compound interest of failsafe stacking.
- **The Build Doctrine roadmap unblocks.** Tranches 2-7 (templates, pilot, knowledge-integration, orchestrator code) all become substantively easier once harness self-application is in place.
- **The user's stated priority — "first-try-functional applications" — gains structural support.** The reliability spine, work-shape library, and proportionate verification all directly serve this priority.
- **Failsafe retirement reduces technical debt.** Tranche F's audit removes mechanisms that the new structure makes redundant, reducing the total surface area the harness must maintain.

### Negative

- **~14-45 days of focused work before benefits materialize.** Not a quick win.
- **Hard freeze on new failsafes during the redesign.** If a new failure mode surfaces during Tranche 1.5, it cannot be patched with a new gate; it must wait for the redesign or be addressed via incentive change.
- **Some existing failsafes will lose protection coverage during the transition** (between when an old gate is scoped-down and when its new-structure replacement matures). Mitigation: Tranche F sequences retirements after each replacement is verified.
- **The closure-validator shipped 2026-05-05 (HARNESS-GAP-16) is tagged-for-retirement.** The work to ship it ~5 days ago becomes partially throwaway. Acceptable cost: the gate served its purpose for the two plans it gated this session, and its synthetic self-tests verified the gate-construction skill.

### Neutral

- **Existing PASSing gates continue to fire during the redesign.** The hard freeze prevents NEW gates; it doesn't disable existing ones. Selective relaxation per Tranche 1.5's gate-relaxation policy applies only to architecture-simplification work specifically.
- **Doctrine extensions (N1, N2, N3) are sequenced after Tranche 1.5 begins.** They are real but not blocking. The doctrine remains the source of truth even before extensions land; the extensions are clarifications, not foundational additions.

### Open

- Whether this decision applies to downstream-project harness use (where the harness is the substrate, not the artifact). Lean toward yes — same principle, same compounding-debt risk — but explicit guidance deferred to the first downstream-project pilot's friction notes (Tranche 4 of the roadmap).
- Whether the calibration loop (Tranche G) needs to land before or after the failsafe audit (Tranche F). Lean toward "G can run in parallel with F" since calibration learns from observed failures and Tranche F surfaces the mechanism inventory; running them together produces a more informed retirement decision.

## Implementation

Operationalized by:

1. **`docs/plans/architecture-simplification.md`** (Tranche 1.5 parent plan; to be authored as the next artifact this session).
2. **`docs/build-doctrine-roadmap.md`** updated with Tranche 1.5 row + Recent Updates entry.
3. **Selective gate-relaxation policy doc** (location TBD — likely a sub-section in the architecture-simplification plan or a sibling rule). Specifies which gates exempt architecture-simplification work and how the exemption is keyed (path-prefix on plan slugs).
4. **`docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md`** Status flipped from `pending` to `decided` with rationale citation to this ADR.

## Cross-references

- **Discovery:** `docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md` — the architectural insight that motivated this decision
- **Integration review:** `docs/reviews/2026-05-05-discovery-vs-build-doctrine-integration.md` — the comparison that established the doctrine already contains the answer
- **Build Doctrine roadmap:** `docs/build-doctrine-roadmap.md` — the multi-phase tracker; Tranche 1.5 is the operational arm of this decision
- **Doctrine source:** `build-doctrine/doctrine/01-principles.md` (Principle 5 "System carries the structure", Anti-Principle 12 "no stacking LLM gates without deterministic backstops"); `build-doctrine/doctrine/04-gates.md` (6 gate categories with mechanical-vs-LLM classification); `build-doctrine/doctrine/02-roles.md` (10 roles including Mechanical Gates and Knowledge Integrator)
- **Unified methodology:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` — the 10-stage reliability spine + per-doctrine-doc evaluation
- **Historical: prior decisions establishing the integration substrate:**
  - 011 (claude --remote harness approach) — cloud-mode inheritance
  - 012 (Agent Teams integration) — feature-flagged peer model
  - 013 (default push policy) — auto-push safe methods
  - 014 (calibration mimicry design) — telemetry-gated reviewer accountability
  - 015-018 (PRD validity, spec freeze, plan-header schema, scratchpad divergence)
  - 019 (findings ledger format)
  - 020 (comprehension gate semantics)
  - 023 (definition-on-first-use enforcement)
  - 024 (GAP-14 reconciliation)
  - 025 (Build Doctrine same-repo placement)
