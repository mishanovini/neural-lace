# Review: Verification-Overhead Discovery vs Build Doctrine — Integration Analysis

**Date:** 2026-05-05
**Reviewer:** orchestrator (this session)
**Source documents:**
- `docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md` (the discovery)
- `build-doctrine/doctrine/01-principles.md` through `09-autonomy-ladder.md` (the doctrine, 8 docs, ~38000 words)
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` (T4 deliverable, 793 lines)

**Purpose:** per user directive 2026-05-05 — first capture the architectural insight (done in the discovery), then compare against the Build Doctrine and recommend integration.

## Headline finding

**The Build Doctrine already contains nearly all of what the discovery surfaced.** The discovery's "10 missing structural pieces" map almost 1:1 onto existing doctrine principles, anti-principles, gate categories, roles, and reliability-spine stages. The user's framing was correct: "a lot of what you just brought to light is exactly what this build doctrine is supposed to be doing."

**The actual gap is not in the doctrine. The actual gap is that the harness has not been built according to its own doctrine.** Two months of reactive failsafe accumulation produced exactly the failure mode the doctrine's Anti-Principle 12 explicitly forbids ("We do not stack LLM gates without deterministic backstops"). The harness is non-conforming with the doctrine it ships.

This changes the integration recommendation substantially. The discovery isn't a contribution TO the doctrine — it's a forcing function for the harness to APPLY the doctrine to itself.

## Mapping table — discovery items vs doctrine

Every discovery item below maps to existing doctrine content unless explicitly marked GENUINELY NEW. Mapping density was unexpected and is the central finding of this review.

| # | Discovery item | Doctrine source | Status |
|---|---|---|---|
| 1 | Specs are prose, not contracts | **Principle 3** ("Specs are frozen artifacts, not chat threads"). Required spec fields enumerated: goals, non-goals, contracts at module boundaries, fixtures, acceptance gates, failure modes, irreversibility flags, dependencies, upstream PRD reference. **Anti-Principle 14** ("No artifact is the only copy of a decision"). Gate 1.4 (Schema validation for specs/PRDs/ADRs/doctrine). | **Already in doctrine; not yet applied to harness plans.** Plan template ships only 5 of these fields enforced. |
| 2 | Evidence is prose, not artifacts | **Principle 7** ("Visibility lives in artifacts, not narration"). Direct quote: "System state is readable without asking the system what happened. This includes: append-only run logs, machine-written human-readable state files, drift logs, and a structured findings ledger." | **Direct match in doctrine; harness implements partially.** Today's evidence blocks are prose; doctrine requires artifacts. Findings ledger is shipped (today's GAP-16 work absorbed C9). Run logs / drift logs / state files are not. |
| 3 | No standard shapes for common work | **Principle 2** ("Design system, engineering catalog, and conventions are canon"). Engineering catalog explicitly lists: "modules, contracts, reuse map, cross-repo shared surfaces, Integration Map, deprecations, ADR index." **Principle 5** ("System carries the structure"). | **Already in doctrine as the engineering catalog concept; not implemented in the harness.** The harness has no engineering-catalog equivalent for harness-dev work classes (build hook, build rule, build agent, etc.). Tranche 2-3 of the roadmap is intended to seed templates; nothing exists today. |
| 4 | Builders have too much scope per task | **Principle 4** ("Decomposition is the engineering"). **Doctrine 03-work-sizing.md** provides the T1-T5 tier rubric with tier-specific gates. **Anti-Principle 10** ("We do not let LLMs decide scope"). | **Already in doctrine via work-sizing rubric; not applied to harness self-development.** The harness's plan files declare tier/rung in the 5-field schema but the work-sizing tier system from 03-work-sizing isn't enforced for harness-dev plans. Today's plans regularly bundle 7+ decisions per task. |
| 5 | Contracts at boundaries are weak | **Principle 2** (engineering catalog with contracts). **Gate 2.3** (Contract tests, bilateral at Tier 4). **Gate 1.4** (Schema validation). | **Already in doctrine; partial harness implementation.** The 5-field plan-header schema is the only enforced contract on harness plan files. Hook input/output contracts, agent return-shape contracts, evidence-block contracts — none exist. |
| 6 | Tests are not the primary verification substrate | **Principle 6** ("Every build receives adversarial review" — but explicitly tier-scaled, not universal heavy review). **04-gates.md** organizes 28+ gates into 6 categories with mechanical-vs-LLM-judgment classification. The doctrine's reliability spine has 10 stages; per-task verification (Stage 6) is "the densest mechanism stack" with mechanical first. | **Already in doctrine architecture; harness has it inverted.** The doctrine's gate model puts mechanical FIRST (categories 1-3), LLM judgment LAST (category 4). The harness has task-verifier as the primary verifier with tests as a small contributor — the inversion of the doctrine's prescription. |
| 7 | No proportionate verification model | **04-gates.md** "Tier-based applicability" matrix. Gate 4 (Adversarial review) is explicitly tier-scaled ("Tier 1 receives a lightweight edge-case pass; Tier 4–5 receive deep boundary and option-space review"). Holdout scenarios (2.6) and comprehension gate (2.7) parameterized by architecture × rung. | **Already in doctrine; not applied to harness verification.** The harness's task-verifier mandate is uniform across all tasks regardless of risk. The proportionate model the discovery proposed (`Verification: mechanical | full | contract`) is the doctrine's tier-applicability matrix in different vocabulary. |
| 8 | Builder failures aren't fed back into the system | **Principle 8** ("Doctrine evolves through ritual"). **Principle 9** ("Documents are living; updates propagate on trigger"). **Role 9** (Knowledge Integrator). **06-propagation.md** PT-1..PT-7 trigger framework. | **Already in doctrine as the calibration loop; harness has the role and triggers paper-only.** The Knowledge Integrator role exists in 02-roles.md as a first-class role; no harness implementation. Propagation triggers exist in doctrine; harness has 3 single-purpose hooks (plan-lifecycle, decisions-index-gate, docs-freshness-gate) covering ~3 of the 7 trigger classes. |
| 9 | Process steps aren't deterministic | **Principle 5** ("System carries the structure"). **05-implementation-process.md** specifies an 8-phase forward flow with explicit handoffs; each phase has deterministic entry/exit criteria. | **Already in doctrine as the 8-phase forward flow; harness orchestrator-pattern.md is a partial implementation.** The doctrine's 8-phase flow is comprehensive and deterministic. The harness's orchestrator-pattern documents some of the phases but not as deterministic procedures — most steps remain LLM-discretion. |
| 10 | Pareto split: LLM judgment vs mechanical | **Anti-Principle 12** ("We do not stack LLM gates without deterministic backstops"). **02-roles.md** separates "Mechanical Gates" (Role 7) from "Adversarial Reviewer" (Role 6) as DISTINCT first-class roles. | **Direct match in doctrine; harness violates Anti-Principle 12 systematically.** Two months of failsafe stacking has produced exactly the architecture the doctrine forbids. The harness's enforcement map lists 50+ rows; many are LLM-agent-based (claim-reviewer, end-user-advocate, comprehension-reviewer, prd-validity-reviewer, plan-evidence-reviewer, etc.) without paired deterministic backstops at the same enforcement point. |

**Summary of mapping:** 10 of 10 discovery items map to existing doctrine content. Zero genuinely new architectural contributions from the discovery. The discovery is a **reminder of what the doctrine already says**, sharpened by two months of empirical evidence about what happens when the doctrine isn't applied.

## Things in the discovery that are NOT in the doctrine (genuinely new)

After full mapping, three contributions from the discovery are NOT already in the doctrine and should be considered for integration. None are big.

### N1. The "verification heaviness as a self-reinforcing failure mode" framing

The doctrine articulates failure modes individually (Principle 3 prevents prose-spec drift, Anti-Principle 12 prevents LLM-gate stacking, etc.) but doesn't have a section on **how reactive enforcement compounds when the doctrine is not applied at the start.** This compounding pattern — each failsafe added because the prior failsafe leaked, each gate adding overhead, each gate also incentivizing avoidance — is empirically real and worth naming.

**Doctrine integration:** add a new section to `01-principles.md` (or extend the Anti-Principles list) with something like: "We do not allow reactive enforcement stacking. When a failure repeats despite an existing gate, the response is to fix the underlying structure, not to add another gate. Adding a gate without removing or restructuring at least one upstream cause is technical debt."

### N2. The Pareto-split rubric for allocating work to mechanical vs LLM-judgment

The doctrine separates Mechanical Gates (Role 7) from Adversarial Reviewer (Role 6) as roles, and 04-gates.md classifies gates as Mechanical or LLM-judgment. But there is no explicit **decision rubric** for "should this NEW gate be mechanical or LLM?" The discovery's framing — "LLM judgment is good at: reading prose requirements, generating drafts, surfacing edge cases, classifying ambiguous inputs; LLM judgment is bad at: counting, applying rules consistently, remembering state across sessions, refusing shortcuts under pressure" — is a useful design rubric.

**Doctrine integration:** add to `04-gates.md` a "When to use a mechanical gate vs an adversarial review" sub-section, listing the heuristics for picking the right enforcement layer per failure class.

### N3. The "harness self-application" gap as a meta-doctrine concern

The doctrine specifies how doctrine + harness govern PROJECTS. It does not specify how doctrine governs the HARNESS itself. The discovery surfaced that the harness has not applied its own doctrine to its own development. This is a meta-loop the doctrine is silent on.

**Doctrine integration:** add a section to `08-project-bootstrapping.md` (or a new doctrine doc) titled "The harness is a project too" — specifying that harness self-development MUST follow the same doctrine the harness enforces on downstream projects. This is the integration that closes the meta-loop and prevents the failure mode that produced the discovery in the first place.

## What this means for the harness — the actual integration recommendation

**The integration recommendation is NOT primarily about extending the doctrine. The doctrine is mostly correct as written. The integration is about applying the doctrine to the harness itself.**

Concretely:

### 1. The architecture-simplification redesign (proposed in the discovery) IS the harness-self-application work

The discovery's recommended Tranches A-G map onto applying specific doctrine elements to harness-dev:

| Discovery Tranche | What it is | Doctrine alignment |
|---|---|---|
| A — Incentive redesign at the prompt layer | Reframe "done" definitions, extend Counter-Incentive Discipline | Aligns with Roles (02-roles) — each role's prompt should match its doctrine-defined responsibility |
| B — Mechanical evidence substrate | Replace prose evidence with artifacts | **Implements Principle 7** ("Visibility lives in artifacts, not narration") for the harness |
| C — Work-shape library | Catalog harness-dev task classes with canonical shapes | **Implements Principle 2** (engineering catalog) for the harness's own work |
| D — Risk-tiered verification | Per-task `Verification: mechanical \| full \| contract` declaration | **Implements 04-gates.md tier-applicability matrix** for harness-dev tasks |
| E — Deterministic close-plan procedure | Single mechanical script replacing the 13-dispatch dance | **Implements 05-implementation-process.md Phase 8** ("Ship") for harness-dev plans |
| F — Audit existing failsafes for retirement | Walk the 50-row enforcement map; mark KEEP / SCOPE-DOWN / RETIRE | **Implements Anti-Principle 12 verification** — every gate must have a deterministic backstop or be removed |
| G — Calibration loop bootstrap | Manual calibration before telemetry lands | **Implements Role 9** (Knowledge Integrator) for the harness's own learning loop |

So the discovery's 7-tranche redesign IS the doctrine being applied to the harness. The discovery doesn't propose new architecture — it proposes finally implementing the existing doctrinal architecture for harness self-development.

### 2. The Build Doctrine roadmap should be reframed

The current roadmap (`docs/build-doctrine-roadmap.md`) tracks 8 tranches focused on doctrine content + templates + pilot + orchestrator code. **None of those tranches is "apply the doctrine to harness self-development."** That's the missing tranche.

**Recommendation:** add a new tranche to the roadmap, slotted between Tranche 1 (C-mechanisms shipped) and Tranche 2 (template schemas), positioned as a prerequisite for the rest:

> **Tranche 1.5 — Harness self-application of doctrine** (~28-45 days, multi-sub-tranche)
> Apply the existing Build Doctrine to the harness itself. The harness has shipped the 8 first-pass C-mechanisms (Tranche 1) but has not been built TO the doctrine — verification overhead is now blocking, in violation of Anti-Principle 12 ("we do not stack LLM gates without deterministic backstops"). Tranche 1.5 implements the doctrine's existing prescriptions for harness self-development specifically. Sub-tranches A-G per the discovery doc's recommendations. **Blocks:** Tranches 2-7 cannot reliably proceed while harness verification is at current overhead — the friction of every plan close compounds across the substantial remaining work.

This reframes the next ~45 days of work as a doctrine-application exercise rather than a separate "redesign." It also establishes the precedent: when the doctrine + harness diverge, the harness is the side that catches up.

### 3. Three small doctrine extensions (per N1, N2, N3 above)

The doctrine's own knowledge-integration ritual (Phase 5 of the roadmap, deferred until after first project pilot) is the right channel for these three additions. Document the additions now in a discovery file or candidate-extension queue; integrate at the next ritual cadence.

These are minor compared to the harness-self-application work. They don't unblock anything. They're catch-ups for the doctrine's own completeness.

## What this means for current state

**Stop the GAP-16 + Tranche 0b closure dance.** Both plans stay `Status: ACTIVE`. The deterministic close-plan procedure (Tranche E of the redesign / sub-tranche of the proposed Tranche 1.5) becomes the path that closes them — and proving the new procedure works on these two specific plans becomes its acceptance test.

**Do not ship more failsafes.** The next harness change should be a structural one — Tranche A or B of the redesign, whichever the user picks to start. Hard freeze on reactive enforcement until at least Tranches A-E land.

**Update the roadmap doc** to reflect the new Tranche 1.5 (harness self-application) as the immediate next pickup, with the discovery + this review as supporting docs.

**Land an ADR (026)** capturing the decision: "When the harness diverges from its doctrine, the harness is the side that catches up. Reactive enforcement is paused in favor of structural application. Tranche 1.5 of the Build Doctrine roadmap operationalizes this."

## The deeper insight

The harness has been doing what it was incentivized to do: respond to failures, ship gates, accumulate enforcement, satisfy the user's stated need ("close this gap"). The doctrine has been sitting in a sibling repo articulating the architecture that would have prevented those failures, but the doctrine wasn't applied to the work that built the gates.

This is the same incentive failure the user surfaced earlier in the day, applied one level up. Just as builders need to be incentivized toward "plan closed" rather than "code shipped," **the harness-development process itself needs to be incentivized toward "doctrine applied" rather than "next failsafe shipped."**

The Build Doctrine roadmap currently does not bind the harness's own development to the doctrine. Tranche 1.5 is the binding mechanism. After it lands, every subsequent harness change is doctrine-applying, not doctrine-deferring.

## Open questions for user decision

1. **Approve Tranche 1.5 as the immediate next pickup?** This is the meaningful architectural commitment. Says yes to ~45 days of focused work; says no to more failsafes during that window.
2. **Approve the 3 small doctrine extensions (N1, N2, N3)?** Lower-stakes; can land alongside or after Tranche 1.5.
3. **Approve ADR 026 ("harness catches up to doctrine")?** Establishes the precedent for future divergences.
4. **What to do with the in-flight GAP-16 + Tranche 0b plans?** Two paths: (a) close them with lightweight evidence now and start Tranche 1.5 fresh, OR (b) leave them ACTIVE as the acceptance test for Tranche E (deterministic close-plan procedure). Recommendation: (b) — proves the new procedure on real plans.
5. **What to do with today's `plan-closure-validator` (just shipped)?** Recommendation: tag-for-retirement; keep firing until Tranche E ships its deterministic replacement; then audit per Tranche F.

## Cross-references

- **Discovery:** `docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md` — the architectural insight this review compares
- **Doctrine docs (NL-migrated):**
  - `build-doctrine/doctrine/01-principles.md` — Principles + Anti-Principles (most overlap concentration)
  - `build-doctrine/doctrine/02-roles.md` — 10 roles including Mechanical Gates and Knowledge Integrator
  - `build-doctrine/doctrine/03-work-sizing.md` — T1-T5 tier rubric
  - `build-doctrine/doctrine/04-gates.md` — 6 gate categories, mechanical-vs-LLM classification
  - `build-doctrine/doctrine/05-implementation-process.md` — 8-phase forward flow
  - `build-doctrine/doctrine/06-propagation.md` — PT-1..PT-7 trigger framework
  - `build-doctrine/doctrine/09-autonomy-ladder.md` — rung-as-metadata reframing
- **Doctrine source-of-record:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` — T4 reliability-spine (10 stages), per-doctrine-doc evaluation, C-mechanism proposals
- **Roadmap:** `docs/build-doctrine-roadmap.md` — current Build Doctrine integration tracker; needs Tranche 1.5 added
- **Failsafe inventory:** `~/.claude/rules/vaporware-prevention.md` — 50-row enforcement map (Tranche F audit target)
- **Originating conversation context:** 2026-05-05 session (this session) covering GAP-16 + Tranche 0b parallel build → closure overhead → "show me the incentive" recall → 10 missing structural pieces → comparison-with-doctrine review

## Conclusion

The discovery surfaced an architectural critique. The Build Doctrine already contains the answer. The recommendation is therefore not "extend the doctrine" — it's "apply the doctrine to harness self-development, beginning immediately, as Tranche 1.5 of the roadmap."

This is a more useful finding than expected. The path forward is shorter and more concrete than a new architectural design exercise. The harness already has its blueprint; the work is execution.

---

## Update — 2026-05-05 closure phase

User authorized all five recommendations in the "Open questions" section. GAP-16 and Tranche 0b plans closed with lightweight evidence in this same session and auto-archived. ADR 026, Tranche 1.5 parent plan, and roadmap update are the next artifacts. Hard freeze on new failsafes is in effect from this point forward until Tranches A-E of architecture-simplification land.
