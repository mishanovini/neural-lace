---
title: Build Doctrine — Implementation Process
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted independently before review of existing neural-lace artifacts, to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md, 02-roles.md, 03-work-sizing.md, 04-gates.md, 06-propagation.md, 08-project-bootstrapping.md
references:
  - outputs/unified-methodology-recommendation.md (reliability spine §3, NL mechanism map §6)
  - outputs/glossary.md
  - outputs/analysis/03-comparative-analysis.md
  - ~/.claude/rules/diagnosis.md (R-5 — 5-step diagnostic loop)
  - ~/.claude/rules/orchestrator-pattern.md (Phase 5 dispatch)
  - ~/.claude/rules/planning.md (Phase 2 PRD intake; verbose plans)
revision_notes:
  - 2026-05-01 v1: initial eight-phase forward flow with PRD intake
  - 2026-05-01 v2: Phase 2 clarified to run integrated with bootstrap for new projects per 08-project-bootstrapping.md; existing projects use standard PRD intake against existing canon
  - 2026-05-03 v3: NL 5-step diagnostic loop adopted in Phase 6 (R-5); plate test as Stage E success-metric prompt (N-R-A); invisible-knowledge prompt in Stage A (N-R-B); spec-driven development terminology mention (N-I-1); behavioral contracts at Rung 3+ (N-G-2 / C16); reliability spine cross-reference.
---

# Build Doctrine — Implementation Process

## Scope

This document defines the end-to-end forward flow from idea to ship. It ties together the principles, roles, work-sizing tiers, gates, and propagation rules into a single process the human and AI follow together.

The process exists for one reason: to make sure no step is skipped, no role is mixed, no decision is left in chat, and no work dispatches without the inputs that make it safe to dispatch.

This document specifies:

- The **forward flow** — the canonical sequence from intent to shipped work.
- How **first-project intake** (PRD + bootstrap integrated) differs from **subsequent PRD intake** (PRD against existing canon).
- The **guided PRD intake protocol** — the structured conversation that converts vague intent into a frozen PRD.
- The **tier-transition protocol** — what happens when a unit discovers mid-execution that it was misclassified.
- The **handoff conventions** — what each role hands to the next, in what shape.

The process is not strictly linear — propagation events, findings, and tier transitions can route work back to earlier stages. But the canonical forward flow is the spine; deviations log to the run log and route deterministically.

### A note on terminology: spec-driven development (N-I-1)

The discipline this document encodes — frozen-spec-before-build, gated decomposition, evidence-first verification — is what practitioners are increasingly calling **spec-driven development**. Nate B. Jones popularized the framing in his content review (Phase 1b N-I-1): the spec is the load-bearing artifact, code is its instantiation, and "the build" is the act of compiling spec into running software with mechanical gates ensuring fidelity. The Build Doctrine is one expression of spec-driven development; Neural Lace is the harness that enforces fidelity per session. We use "spec-driven development" as the practitioner-facing term and "Build Doctrine + Neural Lace" as the project-internal name. They are the same discipline at different levels of abstraction.

---

## Cross-reference: the 10-stage reliability spine

This doc's eight phases plus the PRD intake stages map onto the 10-stage reliability spine documented in `outputs/unified-methodology-recommendation.md` Section 3 (Stages 0 through 10 — eleven labeled stages, ten transitions between them; "10-stage" is the canonical naming). The two views describe the same execution sequence at different granularities — this doc names the activity at each phase; the reliability spine names which gates compound at each stage and what failure mode each catches.

| This doc | Reliability spine stage(s) |
|---|---|
| Phase 1 — Intent capture | Stage 0 (pre-PRD context) |
| Phase 2 — Guided PRD intake | Stage 1 (PRD intake) |
| Phase 3 — Spec decomposition | Stage 2 (spec freeze) + Stage 3 (decomposition / DAG production) |
| Phase 4 — Planning (DAG production) | Stage 3 + Stage 4 (DAG review checkpoint) |
| Phase 5 — Dispatch | Stage 5 (builder dispatch) |
| Phase 6 — Build, gate, review | Stage 6 (per-task verification) + Stage 7 (adversarial review) |
| Phase 7 — Propagation and canon update | Stage 8 (propagation) |
| Phase 8 — Ship | Stage 9 (acceptance scenarios) + Stage 10 (session-end integrity) |

**The reliability spine compounds gates across stages; this doc defines the activity at each stage.** When asking "what fires here?" consult the spine. When asking "what does the role do here?" consult this doc. Together they specify what happens, who does it, and what mechanically prevents the activity from drifting.

---

## The forward flow

The canonical sequence has eight phases. Each phase has defined inputs, defined outputs, the role that owns it, and the gate that lets the work pass to the next phase.

### Phase 1 — Intent capture

**Owner:** human (stakeholder, often Misha himself).

**Input:** vague idea, problem encountered, customer feedback, capability gap, market pressure, regulatory change. Anything that motivates new work.

**Output:** a brief intent statement — one to three sentences naming the problem and the rough shape of what might address it. Not a PRD. Not a spec. Just a starting point.

**Gate to next phase:** none. Intent is captured without ceremony; the intake process refines it.

**Harness implementation:** Phase 1 has no NL mechanism today and shouldn't — capturing intent ahead of structured intake is intentionally informal. Reliability spine Stage 0 covers the project-bootstrap context that surrounds Phase 1; see `08-project-bootstrapping.md`.

### Phase 2 — Guided PRD intake (and, for first-project, integrated bootstrap)

**Owner:** spec author role (human-led, AI-assisted).

**For first-project work in a new project:** Phase 2 runs as the integrated PRD-driven intake described in `08-project-bootstrapping.md`. The PRD is the spine; bootstrap canon (conventions, design system, engineering catalog, gate config, observability) is initialized as a side-effect of PRD content + AI inferences + selectively surfaced decisions. Engagement mode (Express / Standard / Deep / Custom) selected at Stage 0 governs depth. Both PRD and canon converge together at freeze.

**For subsequent PRDs in an established project:** Phase 2 runs as standard PRD intake against existing canon. The design system, engineering catalog, conventions, gate config, and observability are already in place; Phase 2 produces only the PRD against them. The PRD intake protocol below describes this case.

**Input:** intent statement, current canon (or empty if first-project), prior PRDs that may overlap, doctrine, prior drift logs and findings ledger entries touching the same domain.

**Output:**

- A frozen PRD artifact conforming to the PRD template.
- For first-project: also frozen bootstrap canon per `08`.

**Gate to next phase:** PRD validity gate (3.1 in `04-gates.md`). For first-project: also bootstrap freeze gates per `08`.

**Harness implementation:** today, the PRD-validity gate is paper-only — `plan-reviewer.sh` enforces plan-shape but not PRD-shape, and `task-verifier` covers post-build evidence but not pre-build PRD existence. **Forthcoming Phase 1d-C: C1 (`prd-validity-gate.sh`) — PreToolUse hook on first plan creation requiring an upstream frozen `docs/prd/<slug>.md` with required sections.** Substantive review delegated to a new `prd-validity-reviewer` agent. Until C1 lands, the discipline is pattern-only and runs the same risk as any paper rule under time pressure.

The PRD intake protocol is detailed below.

### Phase 3 — Spec decomposition

**Owner:** spec author role.

**Input:** frozen PRD.

**Output:** one or more frozen specs, each conforming to the spec schema, each referencing the PRD, each scoped to a single unit of work.

A PRD often produces multiple specs. The decomposition into specs is itself a sizing exercise — each spec should map to a single work-sizing tier and a single coherent unit of work. If a spec turns out to span multiple tiers or independently-shippable units, the spec author splits it before freezing.

**Gate to next phase:** spec validity gate (3.2). Per-spec freeze.

**Harness implementation:** today, spec validity is paper-only at the schema level; NL's `plan-reviewer.sh` Check 6b enforces the seven required plan sections (which approximates spec validity). **Forthcoming Phase 1d-C: C2 (`spec-freeze-gate.sh`) — PreToolUse `Edit|Write` hook on files in active plan's `## Files to Modify/Create` that rejects edits when freeze is missing or stale.** C2 mechanically converts spec drift from a Pattern (forgotten under time pressure) into a Mechanism. See `outputs/unified-methodology-recommendation.md` §6 for the full C2 specification.

#### Behavioral contracts at Rung 3+ (N-G-2 / C16)

At Rung 3 and above, every spec contract field must specify **behavioral semantics beyond type signatures**:

- **Idempotency invariant** — what running the operation twice produces (same result / accumulating effect / explicit re-entry guard).
- **Performance budget** — latency p50/p95/p99 expectations, throughput floor, resource ceiling. Numeric, not "should be fast."
- **Failure modes** — drawn from a project-defined enum (e.g., `transient | permanent | partial | unknown`), not free-text. Free-text failure modes don't compose with retry policies.
- **Retry semantics** — explicit retry count, backoff parameters (initial delay, multiplier, max delay), jitter strategy. Numeric, not "with backoff."

Type signatures alone are insufficient at Rung 3+ because the LLM-bounded planner, builder, and adversarial reviewer all need to compose with the contract beyond its shape. A contract that says `function pay(amount: number): Promise<Receipt>` doesn't tell the builder whether duplicate calls are safe, the reviewer whether retry-on-timeout is correct, or the orchestrator whether a 504 is transient or permanent.

**Harness implementation:** today, the discipline is pattern-only — adversarial-review agents (`code-reviewer`, `systems-designer`) catch missing behavioral contracts on adversarial passes but don't gate them mechanically. **Forthcoming Phase 1d-C: C16 (behavioral-contracts schema check, extends `plan-reviewer.sh`) — pre-commit hook on plan/spec edits with `rung: 3+` requiring a `## Behavioral Contracts` section with idempotency / performance budget / retry semantics / failure modes sub-entries.** The mechanism mirrors `plan-reviewer.sh` Check 6b's section-presence + non-trivial-content discipline. C16 depends on the rung field landing in the plan header (per Q4 in the methodology recommendation).

### Phase 4 — Planning (DAG production)

**Owner:** planner role (LLM-bounded).

**Input:** frozen specs, doctrine, design system, engineering catalog, work-sizing rubric.

**Output:** a DAG of work units. Each unit conforms to the spec schema, fits a tier, has explicit dependencies and gate references.

**Gate to next phase:** DAG review (6.1). Mandatory at Tier 3+; recommended at Tier 1–2 (project policy may auto-approve simple cases).

The DAG review is where the human decides scope is right, decomposition is sound, and dependencies are accurate. Per anti-principle #10, scope is not delegable to LLMs; this gate is where that principle becomes operational.

**Harness implementation:** today, DAG review is paper-only — there's no mechanism preventing a Tier 3+ plan from dispatching builders without human DAG approval. The `pre-stop-verifier.sh` Stop hook catches some downstream symptoms (unchecked tasks, missing evidence) but doesn't enforce the upstream DAG checkpoint. **Forthcoming Phase 1d-C: C7 (DAG-review waiver gate, short-term form) — PreToolUse hook on first `Task` invocation in a session for plan with `Tier: 3+` requiring a `dag-approved-by-human-<plan-slug>-<timestamp>.txt` waiver in `.claude/state/`.** Future-state full C7 (deterministic orchestrator CLI) deferred per Q10.

### Phase 5 — Dispatch

**Owner:** orchestrator (deterministic state machine).

**Input:** approved DAG.

**Output:** workers dispatched per the DAG's dependency order, capacity-bounded, with retry budgets and escalation rules in effect.

**Gate to next phase:** none — dispatch is the action; the next phase is the work itself.

**Harness implementation:** NL's orchestrator pattern (`~/.claude/rules/orchestrator-pattern.md`) is the closest current analog — the main session reads the plan, dispatches each task to a `plan-phase-builder` sub-agent via the `Task` tool, collects the result, and moves on. Today the orchestrator is Pattern-class only (the discipline is self-applied; no hook enforces it). The full deterministic-orchestrator vision (a project-level CLI consuming a frozen DAG and dispatching Claude Code sessions per node) is the future-state form of C7. The current Pattern-class orchestrator handles parallel dispatch with worktree isolation, build-in-parallel + verify-sequentially via cherry-pick, and the **scenarios-shared, assertions-private** discipline that prevents the builder from teaching to the test.

### Phase 6 — Build, gate, review

**Owner:** builder role per work unit; mechanical gates per unit; adversarial reviewer per unit.

**Input:** dispatched work unit (spec, contracts, fixtures, gate definitions, canon references).

**Output per work unit:**
- Code, tests, documentation updates.
- Findings ledger entries for any issues noticed.
- Drift log entries if the spec proved underspecified.
- Mechanical gate results.
- Adversarial review findings (mandatory at every tier, depth scales).

**Gate to next phase:** all required gates green per the gate matrix for the unit's tier; findings dispositioned for blocking severity; integration tests pass for Tier 3+.

This phase is where most of the doctrine's rigor is operationalized. It's also where the highest variance lives — the volume and severity of findings, the rate of drift signals, the frequency of tier transitions all surface here.

**Harness implementation:** Phase 6 is the densest NL-coverage phase. The full anti-vaporware stack fires here:

- **`pre-commit-tdd-gate.sh`** (4-layer scan) — new runtime files need tests; modified runtime files need a test importing them; integration tier cannot mock; trivial assertions are banned.
- **`plan-edit-validator.sh`** — only `task-verifier` flips checkboxes; evidence-first protocol enforced via flock for parallel verifiers.
- **`runtime-verification-executor.sh`** + **`runtime-verification-reviewer.sh`** — parses and executes Runtime verification entries (test/playwright/curl/sql/file); verifies commands exercise modified files.
- **`task-verifier`** agent — outputs PASS / FAIL / INCOMPLETE with evidence block; only entity authorized to flip plan checkboxes.
- **`no-test-skip-gate.sh`** — blocks staged `test.skip` / `it.skip` unless skip references issue number.
- **`tool-call-budget.sh`** — every 30 Edit/Write/Bash calls forces `plan-evidence-reviewer` audit before proceeding.
- 7 adversarial-review agents (`code-reviewer`, `security-reviewer`, `harness-reviewer`, `claim-reviewer`, `plan-evidence-reviewer`, `ux-designer`, `systems-designer`) plus 3 audience-aware testing agents — fresh-context adversarial passes per tier-scaled prompts.

See `outputs/unified-methodology-recommendation.md` §3 Stage 6 for the full ~12 NL gates + 7 proposed C-mechanism stack at this phase.

#### Diagnostic loop for build-time issues (R-5)

When a build-time issue surfaces — a test fails, a curl returns 500, a build doesn't deploy, a feature looks wrong on screen — the builder follows NL's 5-step diagnostic loop wholesale (per `~/.claude/rules/diagnosis.md`):

1. **Map the full chain.** Trace from user action through frontend → API → backend → external services → response. Read every step that influences the symptom, not just the layer where the symptom appeared.
2. **Trace a concrete example end-to-end with actual values.** Walk a real value through each layer. Substitute the literal input the failing test uses; see what each layer actually produces.
3. **Check what's hiding behind the first error — exhaustive-by-default.** Assume multiple problems until proven otherwise. "If I fix this, what does the next step do?" Surface the second and third bugs before fixing any.
4. **List ALL bugs across the full chain, fix in one commit.** Don't patch one and ship; the partial fix masks the others and the next bug report blames a different surface. One commit, all root causes.
5. **Validate by running the code with a concrete value.** TypeScript compiling is NOT validation. Trace the full chain with a real value, OR run the code and observe the correct outcome.

The canonical NL rule lives at `~/.claude/rules/diagnosis.md`; this phase adopts it wholesale rather than restating it. The builder role is responsible for executing the loop; the adversarial reviewer is responsible for catching when it was skipped (e.g., a fix that addresses the named symptom but leaves sibling symptoms intact).

**Class-sweep discipline.** When feedback (from a reviewer, a test failure, a user correction, a lint error) flags a defect at one location, the fix MUST search the artifact for sibling instances of the same class and fix all of them in the same commit. Document the search in the fix commit (e.g., `Class-sweep: <grep pattern> — N matches, M fixed`). The named instance is one example of the class; the class is what gets fixed. Without class-sweep, review loops fail to converge in 5+ iterations as the reviewer surfaces sibling instances one at a time. See `~/.claude/rules/diagnosis.md` "Fix the Class, Not the Instance."

### Phase 7 — Propagation and canon update

**Owner:** orchestrator fires events; appropriate curators (design system, engineering catalog) act on them.

**Input:** the unit's outputs and the propagation rule set from `06-propagation.md`.

**Output:**
- Auto-updates to mechanical fields in dependent artifacts.
- Findings opened for changes that require curator interpretation.
- Cross-repo edges marked `pending propagation` where consumers must acknowledge.
- Audit log entries per propagation event.

**Gate to next phase:** propagation completion verification (5.2). Every fired event has either landed or has an open finding.

**Harness implementation:** see `06-propagation.md` for the per-trigger NL hook map. NL today implements narrow slices of the framework (`plan-lifecycle.sh`, `plan-edit-validator.sh`, `decisions-index-gate.sh`, `docs-freshness-gate.sh`); the doctrine's 7-trigger framework generalizes them. **Forthcoming Phase 1d-C: C12 (`propagation-trigger-router.sh`) — single PostToolUse hook reading `propagation-rules.json` listing triggers; auto-update where mechanical, opens findings where not.** C12 is the doctrine's biggest single mechanism opportunity per the methodology recommendation.

### Phase 8 — Ship

**Owner:** human at irreversibility checkpoint (when applicable); orchestrator otherwise.

**Input:** completed unit, all gates green, propagation resolved or pending-with-acknowledgment.

**Output:** merge / deploy / publish per project conventions.

**Gate to next phase:** none — this is the terminal phase per unit. Cross-repo edges in `pending propagation` continue tracking until consumers acknowledge.

After ship, the unit's outputs feed back into the loop:

- The findings ledger continues accumulating; patterns feed the knowledge integration ritual.
- Drift logs feed the same.
- Propagation audit feeds the same.
- The PRD's success metrics may be observed post-ship and inform future work or doctrine.

**Harness implementation:** ship-time gates are NL-dense. The 8-position Stop-hook chain enforces session-end integrity (per the reliability spine Stage 9 + Stage 10):

- **`pre-stop-verifier.sh`** (position 1) — plan-integrity (unchecked tasks, missing/malformed evidence, runtime-verification correspondence).
- **`bug-persistence-gate.sh`** (position 2) — bugs surfaced in transcript persisted to backlog/reviews.
- **`narrate-and-wait-gate.sh`** (position 3) — no permission-seeking trail-off when keep-going was authorized.
- **`product-acceptance-gate.sh`** (position 4) — every ACTIVE non-exempt plan must have PASS runtime artifact matching `plan_commit_sha`. The Gen 5 mechanism that closes the "feature exists in code but doesn't work for the user" failure mode.
- **Gen 6 narrative-integrity hooks** (positions 5-8) — `deferral-counter.sh`, `transcript-lie-detector.sh`, `imperative-evidence-linker.sh`, `goal-coverage-on-stop.sh`. Together they prevent the agent's narrative from drifting from the agent's actual work.

Plus: T2/T3 inline blockers fire at irreversibility (force-push, public-repo, sensitive-file, dangerous-command pattern) per NL's permission model. See `outputs/unified-methodology-recommendation.md` §3 Stages 9-10 for the full Gen 5 + Gen 6 substrate.

---

## Guided PRD intake protocol (subsequent PRDs)

This protocol applies when canon already exists. For first-project intake (which integrates bootstrap), see `08-project-bootstrapping.md`.

The principle: the system does not assume the user submits a complete PRD. The intake is the means by which a complete PRD is produced.

### Stages

Intake has six stages. The AI proposes, the user confirms or revises, the loop iterates. The AI carries the structure; the user carries the authority.

#### Stage A — Problem framing

**AI prompts for and proposes drafts of:**
- Problem statement: "What problem does this solve, in one sentence?"
- Affected users / roles
- Current state vs. desired state
- Why now: what makes this the right time

**Invisible-knowledge prompt (N-R-B).** In addition to the above, the AI MUST ask the following surfacing prompt:

> "What about how things work today is invisible to most people, and what's persistently friction-y? The bigger the project, the more institutional knowledge and friction shape what 'good' looks like — surface them now."

This prompt comes from Phase 1b N-R-B. The prompt's purpose: catch the institutional knowledge, undocumented constraints, and persistent-friction patterns that shape "good enough" but never get articulated because they're invisible to the people inside the system. Most PRDs ship with these gaps unfilled, and the resulting build hits surprise constraints late. Surfacing them at Stage A is upstream-cheap; surfacing them at Stage 6 is cleanup-expensive.

**Convergence signal:** the user can read the AI's draft problem statement and say "yes, that's the problem" without revision, AND has answered the invisible-knowledge prompt.

**Output of stage:** problem statement + affected users + change motivation + invisible-knowledge surfaces, captured in PRD draft.

#### Stage B — Scenarios and stories

**AI prompts for and proposes:**
- Two to five user stories or scenarios covering primary use cases
- One to two scenarios covering edge cases the user may not have considered
- Explicitly NOT-scenarios — what users will sometimes want that we are not solving

**Convergence signal:** the user reviews scenarios and confirms coverage matches their mental model. AI specifically asks for missing scenarios; if the user can't add any after thinking, the set is likely complete.

**Output of stage:** structured user stories, primary and edge.

#### Stage C — Functional requirements

**AI prompts for and proposes:**
- What the system must do, in concrete behavioral terms
- Inputs, outputs, transformations
- Decision logic where applicable

**AI specifically surfaces requirements the user did not state but the scenarios imply.** This is where intake catches gaps. Example: user says "users can search by name"; AI proposes "search must handle partial matches, accent variations, and an empty result state" and asks the user to confirm or rule out each.

**Convergence signal:** AI asks "is there any scenario from Stage B that no requirement here addresses?" If the answer is no, the set is complete.

**Output of stage:** functional requirements list.

#### Stage D — Non-functional requirements

**AI prompts for and proposes drafts on each of:**
- Performance (latency, throughput, scale targets)
- Security (auth, authorization, data sensitivity, attack surface)
- Accessibility (WCAG level, keyboard / screen reader support)
- Observability (logging, metrics, traces, alerts)
- Reliability (uptime, error budget, recovery)
- Compliance (regulatory or internal policy constraints)
- Internationalization / localization (if applicable)

This stage is where the most user-side gaps get caught. Most users come with functional requirements clear and non-functional requirements absent or implicit. The AI's job is to **propose specific defaults per category** (referencing the project's existing conventions) and ask for confirmation, deviation, or "not applicable with rationale."

**Convergence signal:** every category has a stated requirement, an explicit "not applicable" with rationale, or an open question deferred-with-rationale.

**Output of stage:** non-functional requirements section with explicit coverage of all categories.

#### Stage E — Success metrics and out-of-scope

**AI prompts for and proposes:**
- Success metrics: how will we know this worked? (Behavioral, business, or technical metrics; explicit measurement methodology.)
- Explicit out-of-scope: what is tempting to include but is intentionally excluded? Why?

The out-of-scope section is load-bearing. It is the artifact that prevents scope creep three phases later when a builder asks "should I also handle X?"

**Plate test (N-R-A).** Every proposed success metric MUST pass the plate test:

> "When this finishes, is your plate lighter or heavier? Outcome metrics over process metrics. If the answer is 'we built X', restate as 'X enabled Y outcome for the user.'"

The plate test comes from Phase 1b N-R-A (Nate B. Jones, "Open loop audit"). The test catches success metrics phrased as outputs ("we shipped 5 features") rather than outcomes ("users now spend N minutes less per task"). An output-phrased metric is satisfied by motion, not by outcome. The plate test reframes: if the output ships and the user's plate stays the same, the metric is wrong.

Apply the test to every metric:
- "We launched the new dashboard" — output. Reframe: "Operators reduced time-to-fault-localization from N minutes to M, measured by run logs."
- "We migrated to the new auth provider" — output. Reframe: "Active sessions interrupted decreased to zero during migration; user-perceived re-login rate stayed flat."
- "We refactored the payment module" — output. Reframe: "Failed-charge retry success rate increased to N%, OR change-failure-rate dropped to M%."

If the AI's proposed metric is output-phrased and the user can't restate it as outcome-phrased, the metric belongs in the out-of-scope section ("we want to ship X" is fine; it's just not a success metric).

**Convergence signal:** the user can articulate, without prompting, what success looks like and what is intentionally not being built, AND every success metric has passed the plate test.

**Output of stage:** success metrics (outcome-phrased) + out-of-scope list.

#### Stage F — Open questions resolution

**AI surfaces:**
- Anything from prior stages that wasn't fully resolved
- Constraints the AI suspects but couldn't get clear answers on
- Dependencies on other work or decisions

**For each open question, the user does one of:**
- Resolves it (answer captured, moved to the relevant section)
- Defers it with rationale ("we'll figure this out in stage X of build because Y")
- Halts intake — the question is too significant to defer; PRD cannot freeze until resolved

**Convergence signal:** open-questions field is empty or contains only deferred-with-rationale entries.

**Output of stage:** PRD ready for freeze.

### Operating principles

- **AI proposes, user authorizes.** The AI's drafts are starting points; the user always has authority to revise.
- **AI surfaces what users miss.** Most intake failures come from users believing they've thought of everything. The AI's value is structured prompting that catches gaps.
- **No silent skips.** Skipping a stage requires explicit user opt-out with rationale captured in the PRD.
- **Stages are not strictly sequential.** Later stages often surface revisions to earlier ones. Loops are normal; the intake converges, not progresses linearly.
- **Intake is not exhaustive elicitation theater.** The goal is a frozen PRD with no holes, not a 40-page document. Most intakes converge in 30–90 minutes for typical features.

### When intake declines

Some intakes won't converge. Signals:

- The user can't articulate the problem clearly even after Stage A drafting.
- Scenarios contradict each other and the user can't resolve.
- Open questions multiply faster than they resolve.

Default action when intake won't converge: **pause and recommend a Tier 5 design pass** before further intake. The work isn't ready for PRD; it's ready for architectural deliberation. The AI flags this explicitly rather than producing a flawed PRD.

---

## Tier-transition protocol

When a unit discovers mid-execution that it was misclassified — usually a Tier 2 unit hitting a contract change that makes it actually Tier 4 — the protocol is:

1. **Halt the unit immediately.** No further code changes after the discovery.
2. **Write a `tier-transition` finding** to the ledger with severity `error`, the discovered tier, and the specific evidence (which gate flagged or which builder observation).
3. **Drift log entry** recording what made the original classification wrong.
4. **Route to spec author** if the discovery is at the spec level (the original spec didn't capture the contract surface), or to **planner** if it's at the decomposition level (the spec was right, but planner sized it incorrectly).
5. **Close the original unit without merge.** Any partial code changes are reviewed for salvage, but the unit's state is closed.
6. **Re-spec at the correct tier.** The new unit dispatches with the higher-tier gates from the start.

This protocol is explicitly **not** "carry on at the higher tier." Promoting tier mid-execution loses the gates the higher tier required from the start — Tier 4 contract tests aren't valid if they're written after the implementation, for example. The integrity comes from running the right tier's gates from the beginning.

The tier-transition findings are also a high-signal input for the knowledge integrator — frequent transitions in a particular pattern suggest the work-sizing rubric or the intake process is missing a trigger question.

**Harness implementation:** tier-transition halting is paper-only today. **Forthcoming Phase 1d-C: C8 (tier-transition halting gate) — Hybrid Mechanism + Pattern that detects tier-escalation signals at build-time and forces the halt + re-spec discipline.** Until C8 lands, the discipline lives in builder role boundaries (per `02-roles.md`) and adversarial-review agent prompts.

---

## Handoff conventions

Each role-to-role handoff has a defined shape. Handoffs that don't conform fail at the receiving role's input gate.

### Stakeholder → Spec author (Phase 1 → 2)

**Shape:** intent statement (informal, 1–3 sentences). No required schema; this is the unstructured starting point.

### Spec author → Spec author (Phase 2 → 3, PRD to spec decomposition)

Self-handoff inside the role; the artifact transitions from PRD (frozen) to specs (drafted, then frozen). PRD reference is required in every spec.

For first-project work, also: bootstrap canon transitions from in-flight to frozen during Phase 2 per `08`.

### Spec author → Planner (Phase 3 → 4)

**Shape:** frozen spec set, all schema-valid, with PRD references. Spec set must be coherent — a planner receiving five specs from one PRD that contradict each other rejects the handoff and routes back to spec author.

### Planner → Human (Phase 4 → DAG review gate)

**Shape:** structured DAG with per-unit tier classification, dependencies, gate references, and rationale for any decomposition choices that aren't obvious from the spec.

### Human → Orchestrator (Phase 4 gate → 5)

**Shape:** approved DAG with timestamp and (optional) review notes for downstream context. C7 enforces this mechanically via the waiver file.

### Orchestrator → Builder (Phase 5 → 6)

**Shape:** dispatched work unit context — the spec, the contracts, the fixtures, the gate definitions for the unit's tier, the relevant slice of canon (catalog modules touched, design system components used, Integration Map nodes referenced). NL's `plan-phase-builder` agent is the current implementation; dispatch follows the **scenarios-shared, assertions-private** discipline (the builder sees plan's `## Acceptance Scenarios` verbatim but not the advocate's runtime assertions).

### Builder → Mechanical gates → Adversarial reviewer

**Shape:** unit output with diff, test results, drift log entries, findings ledger entries.

### Adversarial reviewer → Orchestrator

**Shape:** structured findings written to the ledger.

### Orchestrator → Curators (Phase 7 propagation)

**Shape:** propagation event with trigger ID, source, dependents identified, suggested action. C12 (forthcoming) is the generalized router.

### Orchestrator → Human (irreversibility checkpoint, Phase 8)

**Shape:** action specifics, spec rationale, gate state summary, propagation status.

### Anything → Findings ledger

**Shape:** structured entry with severity, location, scope, suggested action, owner, timestamp. This is the universal handoff for "I noticed something." C9 (forthcoming) operationalizes the schema.

---

## Role mixing — explicitly disallowed transitions

The following handoffs are anti-patterns; none are valid:

- Builder → ship (skipping gates and review).
- Builder → builder (one builder handing to another mid-unit; if work needs more capacity, decompose first).
- Adversarial reviewer → builder (reviewer doesn't direct fixes; orchestrator routes findings).
- Planner → builder (skipping orchestrator and human DAG review).
- Spec author → builder (skipping planner; even one-unit specs go through planner so the DAG and gates are explicit).
- Stakeholder → builder (any direct path from intent to build skips intake, decomposition, planning, and review).

The orchestrator enforces these as deterministic rules; LLM agents do not negotiate their way around them.

---

## Special cases

### Hotfix

Real production issues sometimes need faster paths. The hotfix protocol:

- Tier 1 or Tier 2 fix only — anything larger is not a hotfix, it's a rushed change.
- Spec is required, but PRD can be auto-generated from a templated incident PRD that the human freezes after-the-fact.
- All gates still run. Adversarial review is mandatory.
- Human checkpoint at irreversibility is mandatory.
- Hotfix path is logged as a `hotfix` event for knowledge integrator review — frequent hotfix paths suggest test coverage gaps or process issues.

The hotfix path is **faster**, not **gated less**. Speed comes from skipping deliberation, not from skipping verification.

### Exploratory spike

Sometimes the right work is to write throwaway code to learn something. The spike protocol:

- Treated as Tier 5 (design work) regardless of code volume.
- Output is an ADR or written learning, not merged code.
- Code from a spike is explicitly marked as not-for-merge.
- Findings about the explored space land in the engineering catalog or design system as appropriate, with provenance pointing to the spike.

Spikes that produce code that wants to merge are misclassified — re-spec as Tier 1–4 work against the spike's findings.

### Refactor

Refactors are normal work. The tier is determined by what the refactor touches:

- Internal-only refactor in one module: Tier 1 or 2.
- Cross-module refactor: Tier 3.
- Refactor that changes a public contract: Tier 4.
- Refactor that introduces a new pattern: Tier 5 (the new pattern is the work; the refactor is its first instantiation).

The same gates apply. Refactors don't get a discount because they're "just cleanup."

---

## Open during fresh-draft phase

- **Intake duration calibration.** The 30–90 minute target for typical PRD intake is a guess. Pilot will calibrate.
- **Intake skip rules.** Some work units may not warrant a full PRD (small Tier 1 utilities derived from existing PRDs). The protocol for "scoped under existing PRD-X" deferred to templates phase.
- **Multi-stakeholder intake.** Current protocol assumes one stakeholder. Multi-stakeholder PRDs (with conflicting requirements) need a defined resolution path; deferred.
- **Cross-PRD coordination.** When two in-flight PRDs touch the same surfaces, coordination protocol deferred — likely a propagation rule on PRD freeze.

## Next step

This document is integrated v1. Next: `06-propagation.md` integration (Phase 1d-B Task T3 paired output); Phase 1d-C lands the C-mechanism stack (C1, C2, C7, C8, C12, C16) referenced throughout.
