---
title: Build Doctrine — Role Definitions
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted independently before review of existing neural-lace artifacts (agents/, patterns/), to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md (same drafting methodology, same draft phase)
  - integrated with Neural Lace harness cross-references (Phase 1d-B)
references:
  - ~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md
  - ~/.claude/rules/orchestrator-pattern.md
  - ~/.claude/rules/vaporware-prevention.md
revision_notes:
  - 2026-05-01: spec author expanded to include guided PRD elicitation upstream; engineering catalog curator owns Integration Map; adversarial reviewer mandatory at every tier; findings ledger writes added to builder, reviewer, gates; propagation handling added to orchestrator
  - 2026-05-03 v3: Neural Lace agent cross-references added; telemetry as findings-ledger input documented (R-9); 90/100/90 ratio cited (N-R-F); best-model-per-role clarification added (N-R-D).
---

# Build Doctrine — Role Definitions

## Scope

Every role in the build system has a defined identity. For each role this document specifies:

- **Type** — human, LLM, or deterministic. This determines what kind of decisions the role can be trusted with.
- **Inputs** — what flows into the role.
- **Outputs** — what the role produces.
- **Decision authority** — what the role decides.
- **Decision boundaries** — what the role cannot decide. This is the load-bearing field; it prevents scope creep across roles.
- **Escalation conditions** — when the role hands off, bounces back, or stops.
- **Output gate** — what makes the role's output legitimate downstream.
- **Harness implementation** — the Neural Lace agent, hook, or rule (where applicable) that operationalizes this role at session granularity. Project-shape roles (Spec Author, Design / Catalog Curators, Planner, Knowledge Integrator) have no direct NL agent because NL operates per-session; they compose with NL when work-units dispatch into Claude Code sessions.

Roles are functional, not personnel. A single human can play multiple roles across a project; a single LLM session can play one role at a time but never two simultaneously. Mixing roles in one execution is a recurring failure mode and an explicit anti-pattern.

The role definitions compose with the principles (`01-principles.md`) and reference the work-sizing rubric (`03-work-sizing.md`) for tier-specific behavior.

**Empirical observation on the human/AI split** (Huryn, cited in Nate B. Jones, "Open loop audit"): for AI-augmented work, expect roughly 90% human judgment, 100% human takes (acceptance/rejection of every artifact), and 90% AI execution. The role boundaries below preserve human authority on judgment and takes while delegating execution.

**Best-model-per-role.** Roles are separable from model selection; per-role model optimization is encouraged. A planner role may benefit from a different model family than a builder role; an adversarial reviewer's "fresh context, different model family" prompt is a special case of the same general principle. The doctrine does not prescribe model choice but treats it as a project-level configuration the curator chooses based on observed reliability evidence per role. See Nate B. Jones, "You're using the wrong kind of agent."

---

## 1. Spec Author

**Type:** Human-led, LLM-assisted (human owns final spec). The role is a chain: **PRD elicitation → PRD freeze → spec decomposition → spec freeze**. One PRD generates many specs.

**Inputs:** project goals from stakeholder (often vague at intake), current design system reference, current engineering catalog (including Integration Map), prior PRDs and specs, ADRs, doctrine, prior drift logs and findings ledger entries touching the same domain.

**Outputs:**

1. A frozen PRD artifact conforming to the PRD template (problem, user stories, functional + non-functional requirements, success metrics, explicit out-of-scope, open questions resolved).
2. One or more frozen specs derived from the PRD, each conforming to the spec schema (goals, contracts, fixtures, acceptance gates, failure modes, irreversibility flags, dependencies, **PRD reference**).

**Decision authority:** scope (what's in, out, deferred); contracts at module boundaries; fixtures; acceptance gates; failure modes to cover; irreversibility flags; dependencies on other units; success metrics for the PRD.

**Decision boundaries:** does not decide implementation details (those belong to the builder); does not decide whether the spec passes its own gates downstream (that's the orchestrator's deterministic check); does not decide decomposition into work units (that's the planner's, against this spec).

**PRD elicitation process:** does **not** assume the user submits a complete PRD. The role guides the user through a structured intake — problem statement, scenarios, constraints, success metrics, scope boundaries, open questions — using the conversational pattern defined in `05-implementation-process.md`. The user confirms; the AI proposes; the loop converges to a frozen PRD. Submitting a PRD blind is supported but not required.

**Escalation conditions:** scope ambiguity that requires stakeholder input; contract changes that span surfaces owned by others; irreversibility flag triggered at a level requiring authorization the spec author doesn't hold; PRD elicitation surfaces open questions the user cannot resolve unaided.

**Output gate:** PRD must pass schema validation and human freeze before any spec derives from it. Each spec must pass schema validation, reference its PRD, and be frozen. An unfrozen or schema-incomplete artifact cannot be dispatched.

**Harness implementation:** no direct NL agent — the Spec Author is a doctrine-layer project-shape role and PRD intake spans a project's first hours, well outside any single Claude Code session. Future-state mechanization is proposed in `outputs/unified-methodology-recommendation.md` §6 as **C1 PRD-validity gate** (presence + schema check at first plan creation, paired with a new `prd-validity-reviewer` agent for substance) and **C2 spec-freeze gate** (`frozen: true` plan-header field + PreToolUse rejection of edits to plan-declared files when the freeze is missing).

---

## 2. Design System Curator

**Type:** Human-led, LLM-assisted (especially for inventory tasks).

**Inputs:** existing design tokens, current component inventory, accessibility baseline, prior interaction patterns, anti-patterns log, requests for new components from spec authors, propagation triggers from related artifact changes.

**Outputs:** the maintained, versioned design system reference for each project — tokens, component inventory with provenance, interaction patterns, accessibility baseline, anti-patterns.

**Decision authority:** which components enter canon; naming and convention; variant vs. new component; anti-patterns worth documenting; deprecations; accessibility baseline updates.

**Decision boundaries:** does not decide per-spec design choices that fit existing canon (those are spec-level); does not approve specs (that's the spec author's freeze).

**Escalation conditions:** a spec requires a component not in canon — must be added with explicit provenance before build proceeds; conflict between components proposed by different specs; propagation trigger reveals an inconsistency between design system and an instantiation in a spec.

**Output gate:** every new entry in canon carries provenance (rationale, date, originating spec or ADR). Propagation triggers fire when entries are added, modified, or deprecated.

**Harness implementation:** no direct NL agent — the Design System Curator owns a project-canon artifact (`docs/design-system.md`) that is maintained at project granularity. NL `rules/ux-design.md` and `rules/ux-standards.md` are session-granularity references; per Phase 1a R-6, UX standards are an 11th universal floor for UI projects. Future-state mechanization is proposed in `outputs/unified-methodology-recommendation.md` §6 as **C6 Design system consistency gate** — a pre-commit hook scanning changed UI files for tokens/components not declared in `docs/design-system.md`.

---

## 3. Engineering Catalog Curator

**Type:** Human-led, LLM-assisted (especially for inventory generation from code and Integration Map maintenance).

**Inputs:** current codebase state, module signatures, public contracts, ADR history, runtime integration data (who actually calls whom), deprecation candidates, propagation triggers.

**Outputs:** the maintained engineering catalog including:

- Module inventory and public contracts
- Reuse map
- **Integration Map** (a sub-section of the catalog): for each module, who consumes it, who it consumes, what events it publishes / subscribes to, the actual usage patterns of cross-repo edges (which fields, which events), and the failure mode if a producer changes contract without coordinated update
- Deprecations
- ADR index

**Decision authority:** what counts as reusable vs. project-specific; deprecation; contract boundary placement; what triggers an ADR; which cross-repo surfaces need explicit governance; the structure and granularity of Integration Map entries.

**Decision boundaries:** does not implement new modules (builder's job); does not decide whether a new module is justified for a given spec (spec author + planner do, against this catalog).

**Escalation conditions:** near-miss reuse cases (an existing module almost fits — extend, fork, or accept partial reuse?); contract drift between catalog and code; Integration Map drift between documented and actual integration behavior.

**Output gate:** catalog and Integration Map reflect current code and runtime state. Detected drift triggers re-curation or opens a finding; a stale catalog or Integration Map is treated as a build blocker for the affected surfaces.

**Harness implementation:** no direct NL agent — the Engineering Catalog Curator owns `docs/engineering-catalog.md` at project granularity. NL has no equivalent (per Phase 1a R-6 / T2 §3). Future-state mechanization is proposed in `outputs/unified-methodology-recommendation.md` §6 as **C5 Engineering catalog / Integration Map consistency gate** — pre-commit hook comparing declared module list against actual `src/` inventory and surfacing drift findings.

---

## 4. Planner

**Type:** LLM (bounded scope), human review before any dispatch.

**Inputs:** frozen spec, doctrine, design system reference, engineering catalog (including Integration Map), work-sizing rubric, available worker capacity, dependency graph.

**Outputs:** a DAG of work units. Each unit conforms to the spec schema, fits within a defined work-sizing tier, has explicit dependencies, references its acceptance gates, and references the Integration Map nodes it touches (for Tier 3+ units).

**Decision authority:** how to decompose a goal into units; dependencies between units; which gates each unit needs; tier classification per unit.

**Decision boundaries:** does not decide scope (spec author already did); does not decide whether to dispatch (orchestrator does, after human review); does not interpret underspecified specs — bounces them back instead.

**Escalation conditions:** decomposition reveals scope ambiguity — return to spec author; a unit cannot be sized below Tier 4 — escalates for human-led architecture work; cross-repo contract change required — escalates to engineering catalog curator and human checkpoint.

**Output gate:** human reviews the DAG before any worker dispatches. This is non-negotiable per principle 4 ("decomposition is the engineering").

**Harness implementation:** no direct NL agent — the Planner role is project-spanning, not session-bounded. The closest session-granularity analog is the orchestrator role on-session (the main Claude Code session reading a plan and dispatching `plan-phase-builder` sub-agents per `~/.claude/rules/orchestrator-pattern.md`), but that is a Builder-coordination shape, not the cross-spec DAG production the Planner role describes. Future-state mechanization is proposed in `outputs/unified-methodology-recommendation.md` §6 as **C7 DAG-review waiver gate** (PreToolUse on first `Task` dispatch in a session for a Tier 3+ plan rejects without an explicit `dag-approved-by-human-<plan-slug>-<timestamp>.txt` waiver).

---

## 5. Builder

**Type:** LLM.

**Inputs:** a single dispatched work unit (spec, contracts, fixtures, acceptance gates), design system and engineering catalog (including Integration Map) as canon, harness configuration in effect for the host tool.

**Outputs:** code, tests, updates to relevant documentation, **findings ledger entries** (any issue noticed during build that the unit doesn't itself resolve), drift log entries (when the spec proved underspecified), structured run log entries.

**Decision authority:** implementation choices that fit within the spec's contracts and constraints; which existing modules to reuse (consulting the catalog); which existing components to use (consulting the design system).

**Decision boundaries:** does not change scope; does not change contracts; does not declare itself done (gates + adversarial reviewer do); does not silently interpret an underspecified spec — records a drift log entry and bounces the unit back; **does not silently fix or ignore issues outside the unit's scope** — writes them to the findings ledger so they're not lost.

**Escalation conditions:** spec underspecified beyond what the builder can resolve from canon; reuse-first analysis reveals a near-miss requiring catalog curator input; mechanical gate failure that suggests spec error rather than implementation error.

**Output gate:** must pass all mechanical gates **and** adversarial review before the unit is marked complete by the orchestrator. Adversarial review is mandatory at every tier per principle #5.

**Harness implementation:** invokes Neural Lace's `plan-phase-builder` sub-agent for dispatched tasks (concise verdict under 500 tokens; serial and parallel dispatch modes; `isolation: "worktree"` for parallel safety). The dispatch protocol — including the scenarios-shared / assertions-private discipline — is documented in `~/.claude/rules/orchestrator-pattern.md`. Per-task verification (Stage 6 of the reliability spine) is the densest gate stack: `pre-commit-tdd-gate.sh` 5-layer test discipline, `plan-edit-validator.sh` evidence-first checkbox protocol, `runtime-verification-executor.sh` replayable evidence, `task-verifier` PASS/FAIL/INCOMPLETE verdicts, `no-test-skip-gate.sh`, `observed-errors-gate.sh`, `outcome-evidence-gate.sh`. Builder scope-boundary discipline maps to proposed **C10 scope-enforcement gate** (`outputs/unified-methodology-recommendation.md` §6) — PreToolUse on `git commit` comparing the staged diff to the plan's `## Files to Modify/Create` list.

---

## 6. Adversarial Reviewer

**Type:** LLM (fresh context, no shared history with the builder, ideally a different model family).

**Activation:** mandatory at every tier per principle #5. Depth scales with tier (Tier 1: lightweight edge-case pass; Tier 4–5: deep boundary and option-space review). Skipping is not an option.

**Inputs:** spec, builder output, fixtures, mechanical gate results, doctrine, Integration Map nodes the unit touches.

**Outputs:** structured findings written to the findings ledger — what's missing, what would break, what edge cases aren't handled. Findings are categorized (severity, location, scope, suggested action) and actionable. Not approval; not "looks good."

**Decision authority:** none. The reviewer produces findings; it does not gate anything directly.

**Decision boundaries:** does not approve the unit; does not modify the unit; does not choose between findings to suppress.

**Escalation conditions:** severe findings → marks the unit as needs-rebuild and routes to a fresh builder; scope-related findings → routes to spec author; pattern of findings across units → routes to the knowledge integrator for doctrine consideration.

**Output gate:** findings must be structured (severity, location, scope, suggested action) and persisted in the findings ledger. Narrative-only review is rejected.

**Harness implementation:** composes Neural Lace's specialist reviewer agents — `code-reviewer`, `claim-reviewer`, `end-user-advocate` (plan-time + runtime modes), `systems-designer` (Mode: design plans), `ux-designer` (UI plans), `security-reviewer`, `harness-reviewer`, `plan-evidence-reviewer`. Per-tier depth scales the agent set: Tier 1 light-touch gets one or two reviewers; Tier 4-5 boundary review gets the full specialist stack. The class-aware feedback contract (per `~/.claude/rules/diagnosis.md` "Fix the Class, Not the Instance") means each finding emits a six-field block with `Class:` + `Sweep query:` + `Required generalization:` so the same defect class is closed across the artifact in one pass. Future-state mechanization for Tier 5 ADR review is proposed as **C4 ADR-adoption gate** (`outputs/unified-methodology-recommendation.md` §6).

---

## 7. Mechanical Gates

**Type:** Deterministic.

**Inputs:** builder output (code, tests, logs), gate definitions from doctrine, project-specific gate configuration.

**Outputs:** per-gate pass/fail with diagnostic detail on failure; failures persisted as findings ledger entries with severity proportional to the gate.

**Decision authority:** pass/fail per gate, deterministically, against fixed thresholds.

**Decision boundaries:** does not relax thresholds at runtime; does not interpret ambiguity; does not synthesize across gates (that's the orchestrator's role with the gate matrix).

**Escalation conditions:** persistent failure across retry budget — escalates to human queue. Gate definition itself producing surprising results — flags for knowledge integrator review (the gate may be wrong, not the work).

**Output gate:** this role *is* the gate. Green from all required gates is one of the inputs to the orchestrator's "is it done" deterministic check.

**Harness implementation:** operationalized by Neural Lace's hook layer. Selected high-leverage hooks: `pre-commit-tdd-gate.sh` (4-layer test discipline + mock ban + trivial-assertion ban), `plan-edit-validator.sh` (evidence-first checkbox flips, flock-protected for parallel safety), `runtime-verification-executor.sh` (parses + executes replayable verification commands), `harness-hygiene-scan.sh` (denylist + sensitive-data scanning), `decisions-index-gate.sh` (decision record + DECISIONS.md atomicity), `pre-push-scan.sh` (credential pattern scanner), `no-test-skip-gate.sh`, `observed-errors-gate.sh`, plus 30+ others. The complete enforcement map (rule-by-rule, with the hook or agent that enforces each) lives at `~/.claude/rules/vaporware-prevention.md`; the inventory lives at `~/.claude/docs/harness-architecture.md`.

---

## 8. Orchestrator

**Type:** Deterministic state machine. Explicitly **not** an LLM agent — see anti-principle #11.

**Inputs:** DAG of work units (post-human-review), worker pool capacity, gate definitions, escalation rules, retry budgets, **propagation rule set** from `06-propagation.md`.

**Outputs:** dispatch decisions, state transitions, escalation queue entries, propagation events fired on triggers, append-only run log.

**Decision authority:** when to dispatch a unit; when to retry; when to escalate; when to advance unit state; when to halt the run; **which propagation events to fire on which triggers** — all per pre-defined rules.

**Decision boundaries:** does not reason about whether a unit is done (that's the gates + reviewer composition); does not reason about scope, contracts, or correctness; does not modify the DAG mid-run except by deterministic rules; does not infer new propagation rules at runtime.

**Escalation conditions:** retry budget exhausted; max time / token budget hit; irreversibility flag triggered — routes to human checkpoint; gate failure outside the retry-recoverable set; propagation event fails to find a clean update path — opens a finding for the appropriate curator.

**Output gate:** every state transition and every fired propagation event is logged. The run log is the durable record of what the system did.

**Harness implementation:** at the **session level**, the main Claude Code session per `~/.claude/rules/orchestrator-pattern.md` (Pattern-class) — the main session reads the plan, dispatches each task to a fresh `plan-phase-builder` sub-agent, collects the verdict, and moves on. This is a session-bounded approximation of the doctrine's project-spanning Orchestrator. At the **project lifecycle level**, a future deterministic state machine (full **C7** form per `outputs/unified-methodology-recommendation.md` §6) consuming a frozen DAG and dispatching Claude Code sessions per node — deferred to Phase 4+ pending pilot evidence (Q10 in the recommendation's open questions).

---

## 9. Knowledge Integrator

**Type:** Human-led, LLM-assisted (LLM proposes; human approves).

**Inputs:** the personal-knowledge tool captures (podcasts, articles, conversations), newsletter content, drift logs from build runs, post-mortems, findings ledger entries (especially patterns and persistent unresolved findings), harness `learning/` proposals when they touch build doctrine.

**Outputs:** doctrine changelog entries — versioned, dated, sourced — that update specific doctrine artifacts; proposed updates to gate definitions, work-sizing tiers, and propagation rules when patterns warrant.

**Decision authority:** which captured insights graduate to doctrine vs. stay as the personal-knowledge tool reference; which doctrine artifact each insight belongs in; whether a proposal is ready for adoption; conflict resolution between contradictory inputs; whether a recurring finding ledger pattern indicates doctrine change.

**Decision boundaries:** does not change doctrine without human approval; does not silently retire principles; does not graduate an insight without explicit source attribution.

**Escalation conditions:** contradictory inputs requiring stakeholder resolution; insights touching multiple artifacts that require coordinated update (triggers propagation rule set); recurring drift log or findings ledger signals that suggest a missing principle or role.

**Output gate:** every doctrine change has source, rationale, and date. No anonymous changes; no untraceable evolution.

**Harness implementation:** composes Neural Lace's `/harness-review` skill (weekly self-audit running against NL's own state and writing dated reviews to `docs/reviews/`) plus a forthcoming `process-improvement-observer` agent (Phase 1d-E) that surfaces patterns from the findings ledger, drift log, and per-session telemetry as candidate doctrine changes. **Per Q11 amendment** (`outputs/unified-methodology-recommendation.md` §9) the harness-meta data — knowledge integrator inputs, findings ledger, drift logs, process-improvement observations — lives in **Neural Lace**, not in the personal-knowledge tool. the personal-knowledge tool stays out of harness-meta scope; it can still feed personal/business CONTEXT into projects (via MCP, captures, etc.) but the harness's self-improvement loop runs entirely inside NL.

---

## 10. Human Checkpoint

**Type:** Human.

**Inputs:** dispatch requests at irreversibility boundaries — schema migrations, public API changes, credential changes, production deploys, cross-repo contract breaks, anything else flagged in the spec's irreversibility field; high-severity unresolved findings ledger entries that require user disposition.

**Outputs:** approve / reject with rationale logged to the run log; finding disposition (act / defer / accept-with-rationale) logged to the findings ledger.

**Decision authority:** whether the irreversible action proceeds; how to dispose of findings that require user judgment.

**Decision boundaries:** does not redesign the unit at the checkpoint (decline + back-off, not edit-and-continue); does not relax thresholds for irreversible actions in pursuit of velocity.

**Escalation conditions:** decline triggers re-spec or back-off; ambiguity at the checkpoint that suggests the spec is the wrong unit of work — bounces to spec author.

**Output gate:** this *is* the checkpoint. Nothing past it without explicit approval logged. **The user cannot silently fail to decide on findings — undecided findings remain in the ledger as visible-and-pending until disposed.**

**Harness implementation:** operationalized by Neural Lace's Stop-hook chain plus inline PreToolUse blockers for irreversible actions. Stop-chain components: `narrate-and-wait-gate.sh` (no permission-seeking trail-off when keep-going was authorized), `bug-persistence-gate.sh` (bugs surfaced in transcript persisted to backlog/reviews), `product-acceptance-gate.sh` (Stop hook position 4 — every ACTIVE non-exempt plan must have PASS runtime artifact). Inline blockers for irreversibility include force-push, public-repo creation, sensitive-file access, dangerous-command patterns; the permission-model substrate (T2 Confirm / T3 Block tiers, six risk dimensions D1-D6, hard limits that never relax) is documented in `~/.claude/principles/permission-model.md` and `~/.claude/principles/progressive-autonomy.md`.

---

## Role-to-role relationships (high-level)

- **Spec author → Planner → Orchestrator** is the dispatch axis. Each step has a frozen handoff artifact (PRD → spec → DAG).
- **Builder ↔ Mechanical Gates ↔ Adversarial Reviewer** is the verification axis. The builder cannot mark itself done. Adversarial review is mandatory at every tier.
- **Design system + Engineering catalog curators** sit alongside spec author as the canon-maintenance axis. They are read by every builder, written by no builder. The Integration Map specifically is owned by the engineering catalog curator and consulted by Tier 3+ work.
- **Knowledge integrator** sits across all axes, observing drift logs, findings ledger, and outcomes, proposing doctrine updates.
- **Human checkpoint** is invoked by the orchestrator at irreversibility boundaries, at any point a deterministic rule routes to human queue, and for findings disposition.
- **Orchestrator** is the only role allowed to dispatch builders and the only role that fires propagation events. No role bypasses it.

## Findings ledger (cross-cutting artifact)

Not a role per se, but a durable artifact every role writes to:

- **Builders** write findings discovered during build that the unit doesn't itself resolve (out-of-scope drift, contract ambiguity, unhandled edge case the spec missed).
- **Adversarial reviewers** write structured findings as their primary output.
- **Mechanical gates** write findings when they fail.
- **Propagation triggers** write findings when an automated update path can't be cleanly resolved.
- **Knowledge integrator** reads the ledger to detect patterns warranting doctrine change.
- **Human checkpoint** disposes of user-actionable findings (act / defer / accept-with-rationale).

The ledger is append-only. Entries are never deleted, only transitioned in status. Per anti-principle #14, nothing the system noticed gets quietly dropped.

### R-9 — Neural Lace telemetry feeds the findings ledger

Neural Lace's per-session telemetry (planned per `~/.claude/docs/harness-strategy.md` 2026-08 target; see HARNESS-GAP-10 sub-gap D) is one of the findings ledger's input streams. The telemetry records hooks fired, blocks confirmed, escape hatches invoked, and class-aware feedback emitted by the seven adversarial reviewer agents. The findings ledger consumes this stream alongside reviewer findings, drift-log entries, and propagation events. The Knowledge Integrator runs pattern detection across all sources — telemetry-derived signals (e.g., "the same hook blocked the same builder six times this week") sit alongside reviewer-derived signals (e.g., "this defect class appeared in three plans over the last sprint") as candidate inputs to doctrine change.

### Findings-ledger schema (Q5 confirmed)

Per the user's Q5 decision (`outputs/unified-methodology-recommendation.md` §9), the findings-ledger schema is six fields:

- **`id`** — unique identifier within the project's ledger.
- **`severity`** — one of info / warn / error / severe.
- **`scope`** — one of unit / spec / canon / cross-repo.
- **`source`** — which gate, agent, or role produced the finding.
- **`status`** — open / in-progress / dispositioned-act / dispositioned-defer / dispositioned-accept / closed.
- **`disposition_history`** — append-only log of state transitions with timestamp, actor, and rationale.

This schema is operationalized by the proposed **C9 findings-ledger schema gate** (`outputs/unified-methodology-recommendation.md` §6) — a Phase 1d-C mechanism extending `bug-persistence-gate.sh`'s pattern to all finding categories with a pre-commit schema validation hook on `docs/findings.md` and a Stop-hook persistence sweep.

## Anti-patterns

- **One LLM playing multiple roles in one execution.** Specifically: builder also doing adversarial review, planner also dispatching, knowledge integrator also approving without human. Each one collapses the independence the system relies on.
- **Approval implicit in narration.** A builder writing "all tests pass" is not a gate result. A reviewer writing "looks good to me" is not a finding. Outputs must be structured.
- **Routing decisions inside the LLM stack.** The orchestrator's job is to decide what runs next based on rules, not based on a meta-LLM's opinion of what should run next.
- **Findings in chat, not in the ledger.** A reviewer mentioning an issue in conversation rather than writing it to the ledger is a #14 violation. Findings have one home: the ledger.
- **PRD by submission.** Treating the PRD as something the user delivers complete is a process failure, not a user failure. The spec author role guides the user through PRD creation; "write me a PRD" is not how this system operates.

---

## Open during fresh-draft phase

- **Source citations.** Each role definition will eventually cite analogues in your existing harness work, in expert content (Nate B. Jones on plumbing-vs-models, others), and in named past failures. Citations absent from this draft to keep it independent.
- **Mechanical implementation.** Some roles (mechanical gates, orchestrator, parts of human checkpoint enforcement) are partly implemented in your existing harness. The integration pass identifies which roles are already operationalized and which need new infrastructure.
- **Tier-specific behavior.** The work-sizing rubric (`03-work-sizing.md`) defines which roles activate at which tier and at what depth.

## Next step

Hold this as the independent draft alongside the principles draft. The next two artifacts in sequence are the gate definitions and the propagation doc, both of which will reference these roles.
