---
title: Build Doctrine — Principles & Anti-Principles
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted independently before review of existing neural-lace artifacts, to surface uncoupled reasoning for later reconciliation
  - implicit inputs: conversation history with Claude on AI-augmented build rigor (May 2026)
  - integrated with Neural Lace harness cross-references (Phase 1d-B)
references:
  - ~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md
  - ~/.claude/rules/vaporware-prevention.md
  - ~/.claude/agents/task-verifier.md
revision_notes:
  - 2026-05-01 v1: principle #5 universalized (adversarial review at every tier); principle #6 expanded to include findings ledger; new principle #8 on living documents with triggered propagation; new anti-principle #14 on orphan findings
  - 2026-05-01 v2: new principle #5 'System carries the structure' inserted; subsequent principles renumbered; reflects the design choice that doctrine ceremony is mitigated by guided processes at every structured decision point
  - 2026-05-03 v3: Phase 1c deep review integrations applied — anti-principle #11 references task-verifier as harness implementation (R-3); 'agents cheat' quote added (N-R-C); METR study cited (N-X-3); Neural Lace introduced as harness substrate (R-1); reliability-first framing in opening.
---

# Build Doctrine — Principles & Anti-Principles

## Scope

These principles govern **how the human + AI collaboration is structured at the project level for designing and building applications**. The doctrine's top priority is **first-try-functional applications** — code that ships correctly the first build. Progressive autonomy is a secondary outcome that emerges as the natural consequence of the reliability spine maturing; it is never pursued aspirationally ahead of accumulated reliability evidence. See the unified methodology recommendation's Executive Summary (`outputs/unified-methodology-recommendation.md` §1) for the full reframing.

The principles sit a layer above the harness (which governs how the AI coding tool itself behaves at runtime). They apply to design work, engineering work, and the seams between them — independent of which AI tool is doing the work or which language the project is written in.

The split between **principles** (what we optimize for) and **anti-principles** (what we explicitly reject) is deliberate. Anti-principles name failure modes that recur unless explicitly forbidden. They carry equal weight.

Empirical evidence — see Model Evaluation & Threat Research (METR) on AI-augmented developer productivity — confirms that AI-assisted development without structural discipline produces precisely-specified garbage at scale; the doctrine exists to convert effort that would otherwise be lost to rework into reliability.

Target count: 9 principles + 6 anti-principles = 15 total. Fewer is better. Every entry must earn its place.

---

## How this layer composes with Neural Lace

The doctrine and Neural Lace are a strict two-layer system. **Doctrine sits ABOVE every session as the project-shape contract**: it defines what a project is (canon — design system, engineering catalog, conventions, gate-config, observability, bootstrap state), how PRDs are intaken and frozen, how work is decomposed into tiered units, where role boundaries fall, how knowledge propagates across artifacts, and what reliability evidence supports each rung of autonomy. **Neural Lace sits INSIDE every Claude Code session as the per-action enforcement substrate**: it mechanically blocks vaporware at edit-time, commit-time, dispatch-time, and session-end through ~39 hooks, ~17 agents, and ~25 rules. The doctrine commits to the principle; Neural Lace implements the enforcement.

The two layers compose at the orchestrator-dispatch boundary. The doctrine produces frozen specs and approved DAGs (project-granularity); the orchestrator hands each work-unit dispatch into a Claude Code session that is now under Neural Lace's enforcement substrate. Plans must pass `plan-reviewer.sh`; edits must pass `plan-edit-validator.sh`; commits must pass `pre-commit-tdd-gate.sh`; sessions must pass the 8-hook Stop chain ending with the product-acceptance-gate. The same vocabulary (Mechanism / Pattern / Hybrid) is used in both layers — the doctrine borrows Neural Lace's `harness-reviewer` rubric so classifications are legible across the boundary.

For the longer treatment of the two-layer architecture — including which concerns each layer owns, where they compose, and why two layers (not one or three) is the right shape — see `outputs/unified-methodology-recommendation.md` Section 2 ("The two-layer architecture"). The reliability spine in §3 of the same doc enumerates the 10 stages where doctrine-level and Neural-Lace-level gates compound.

---

## Principles

### 1. Doctrine before code

Conceptual scaffolding — principles, roles, gates, work-sizing rubrics, spec schemas — is settled before any orchestration or build code is written. Doctrine is cheap to iterate on; code written against unsettled doctrine is rewritten three times. The first concrete engineering investment is the orchestrator, and it should not exist until the doctrine it implements is stable.

### 2. Design system, engineering catalog, and conventions are canon

Three artifacts are load-bearing on every project: the design system reference (tokens, components, interaction patterns, accessibility baseline), the engineering catalog (modules, contracts, reuse map, cross-repo shared surfaces, Integration Map, deprecations, ADR index), and the conventions document (logging, error handling, secrets, validation, auth, observability, testing, documentation, dependency policy, versioning, naming, architectural defaults). All three are versioned, all three are referenced by every build agent, and all three are updated atomically with the work that changes them. New components, new modules, and new patterns require an entry in their respective canon before they are written. Reuse and existing convention are the default. Departure requires explicit justification.

### 3. Specs are frozen artifacts, not chat threads

Every unit of work is governed by a versioned spec with required fields: goals, non-goals, contracts at module boundaries, fixtures, acceptance gates, failure modes to cover, irreversibility flags, dependencies, and a reference to the upstream PRD it derives from. A spec that doesn't fill the required fields cannot be dispatched. The spec is the answer to "what does done mean for this unit of work" and that answer must exist as a file before any builder runs.

### 4. Decomposition is the engineering

Breaking a goal into well-scoped work units is the irreducible human + AI collaboration. It is not delegable to a single LLM call. The decomposition itself encodes scope decisions, contract boundaries, and risk allocations — the exact judgments that determine whether the resulting code has holes. When this step is skipped or rushed, the holes are baked in before any code is written.

### 5. System carries the structure

The doctrine encodes substantial structure — principles, roles, tiers, gates, propagation rules, conventions, templates. The system itself is responsible for carrying that structure on behalf of the user. At every structured decision point — project bootstrapping, conventions instantiation, design system seeding, engineering catalog initialization, gate configuration, PRD intake, spec authoring, finding disposition — the system proposes opinionated defaults and walks the user through confirmation, deviation, or deferral. The user retains authority on every decision; the user does not bear the cognitive load of starting from blank, remembering every required field, or navigating the doctrine manually. Without this principle, the doctrine becomes ceremony. With it, the doctrine becomes leverage.

### 6. Every build receives adversarial review

Adversarial review is universal. There is no tier of work too small to skip it. The depth scales with work-sizing tier — Tier 1 receives a lightweight edge-case pass; Tier 4–5 receive deep boundary and option-space review — but the obligation is constant. The reviewer always operates with fresh context, no shared history with the builder, and ideally a different model family. The reviewer's prompt is "what's missing, what would break, what edge cases aren't handled" — not "is this correct." No builder is trusted to mark its own work done.

### 7. Visibility lives in artifacts, not narration

System state is readable without asking the system what happened. This includes: append-only run logs, machine-written human-readable state files, drift logs (every time a worker had to interpret an underspecified spec), and a structured **findings ledger** (every issue identified by builder, reviewer, or gate, with severity, ownership, and resolution status). Dashboards, when they exist, are static HTML generated from these files. Chat is not the source of truth for what the build system did, what state it's in, or what issues remain open.

### 8. Doctrine evolves through ritual

Captured insights — from podcasts, articles, conversations, post-mortems, friction during pilot work, persistent findings ledger entries — graduate to doctrine through a versioned, dated, sourced changelog entry on a defined cadence. The graduation criteria are written down. Without ritual, doctrine either ossifies (nothing changes regardless of new evidence) or drifts arbitrarily (changes accumulate without traceable rationale). Both failure modes destroy doctrine's value as a stable reference.

### 9. Documents are living; updates propagate on trigger

Every doctrine artifact, design system entry, engineering catalog entry, conventions entry, Integration Map node, ADR, PRD, and spec is treated as a living document. Defined triggers — contract changes, component additions, architecture decisions, principle updates, conventions updates, drift signals — fire propagation events that check related artifacts and either auto-update them or open a structured finding routing to the appropriate curator. The propagation rules are explicit, mechanical where possible, and audit-logged. Stale documents are a system failure, not an editorial oversight.

---

## Anti-Principles

### 10. We do not let LLMs decide scope

Scope decisions — what is included in this work unit, what is deferred, what is explicitly out of bounds — are the load-bearing human contribution. Delegating scope to an LLM that produces a plausible-sounding decomposition is delegating the engineering judgment that prevents holes. LLMs propose; humans (or deterministic rules) decide.

### 11. We do not trust LLM completion claims

Self-review and self-writing share failure modes. The Claude that wrote a function and the Claude reviewing it are not independent observers. "Done" is what mechanical gates (types, lint, contract tests, mutation tests on hot paths) and adversarial review confirm — not what the builder asserts. A green self-report is a request to verify, not a verification.

**Harness implementation.** This anti-principle is operationalized in Neural Lace by an evidence-first protocol enforced across multiple hooks and agents:

- **`task-verifier` agent** (`~/.claude/agents/task-verifier.md`) — the only entity allowed to flip plan checkboxes. Reads files, runs typechecks, captures runtime evidence, and outputs PASS / FAIL / INCOMPLETE with an evidence block.
- **`plan-edit-validator.sh` hook** — rejects checkbox flips that are not preceded by a matching evidence block from `task-verifier`.
- **`pre-stop-verifier.sh` hook** — blocks session termination if any checked task lacks valid evidence, if evidence blocks are malformed, or if runtime-verification entries don't correspond to the modified files.
- **`runtime-verification-executor.sh` hook** — parses replayable bash commands from plan evidence blocks and executes them so verification is never narrative.
- **`pre-commit-tdd-gate.sh` hook** — 4-layer pre-commit scan including the integration-tier mock ban and the trivial-assertion ban, so tests cannot be vaporware either.

The full enforcement map (rule-by-rule, with the hook or agent that enforces each) lives at `~/.claude/rules/vaporware-prevention.md`. As Nate B. Jones puts it concretely: "return true passes a narrowly written test beautifully." Mechanical evidence-first verification is the structural backstop; self-reports are not.

### 12. We do not stack LLM gates without deterministic backstops

Two LLMs in a row can be confidently wrong about the same thing. An orchestration layer composed entirely of LLM agents reviewing other LLM agents has correlated failure modes that don't get cancelled out by stacking. Every LLM gate must be paired with mechanical enforcement — type checks, contract tests, schema validation — somewhere in the pipeline. The deterministic spine is what makes the LLM components safe to lean on.

### 13. We do not skip human checkpoints at irreversibility

Schema migrations. Public API changes. Credential changes. Production deploys. Cross-repo contract breaks. The build system stops and waits for explicit human authorization at these boundaries. Trust accumulation, automation mode, or pressure to ship do not relax this rule. The cost of a bad irreversible action is asymmetric to the cost of a confirmation prompt.

### 14. We do not let any artifact be the only copy of a decision

A decision made in chat, in a PR comment, or in a spec draft must graduate to the right durable artifact — engineering catalog, design system, conventions, ADR, doctrine changelog. Fragmented decisions become missing requirements later, and missing requirements are how holes appear. The discipline is: when a decision is made, ask "where does this live so the next agent finds it?" If the answer is "this conversation," the decision is not yet made.

### 15. We do not let findings die in flight

Every issue identified during build — by a builder, a reviewer, a mechanical gate, a propagation trigger, or a drift detection — is captured in the structured findings ledger with severity, scope, and ownership. Findings are surfaced to the user; the user can act, defer, or accept-with-rationale. What the user cannot do is silently fail to decide. Undecided findings remain visible until decided. Persistent undecided findings flag for knowledge integrator review (the doctrine or the spec may be the issue, not the work). The principle is simple: nothing the system noticed gets quietly dropped.

---

## Open during fresh-draft phase

- **Source citations.** Each principle and anti-principle should eventually cite its origin: a specific scar tissue, a named expert (Nate B. Jones on plumbing-vs-models, others), a documented failure. Citations are absent from this draft to keep the reasoning independent.
- **Mechanical enforcement.** Some principles imply enforcement that already exists in neural-lace (e.g., pre-commit scanners enforce parts of #13). The integration pass will identify which principles are already mechanically enforced and which need new enforcement.
- **Numbering and ordering.** Final order may change after reconciliation with neural-lace's existing principles.

## Next step

Hold this as the independent draft. The work-sizing rubric, gate definitions, implementation process, and propagation reference these principles. The project bootstrapping doc (`08-project-bootstrapping.md`) is the primary operationalization of principle #5.
