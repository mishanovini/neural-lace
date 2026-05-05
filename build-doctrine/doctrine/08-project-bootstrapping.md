---
title: Build Doctrine — Project Bootstrapping
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted independently before review of existing neural-lace artifacts, to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md (especially #2, #5, #9), 02-roles.md, 03-work-sizing.md, 04-gates.md, 05-implementation-process.md, 06-propagation.md
  - integrated with Neural Lace harness cross-references (Phase 1d-B)
references:
  - ~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md
  - ~/.claude/rules/automation-modes.md
  - ~/.claude/rules/ux-design.md
  - ~/.claude/rules/ux-standards.md
  - ~/.claude/rules/testing.md
  - ~/.claude/agents/ux-designer.md
revision_notes:
  - 2026-05-01 v1: initial seven-stage sequential bootstrap with per-stage walkthroughs
  - 2026-05-01 v2: restructured to PRD-driven intake with surfaced bootstrap moments; engagement modes (Express / Standard / Deep / Custom) with per-decision depth selection; AI-prioritized Q&A rounds replace fixed stage walkthroughs; audit pass at end captures what was defaulted vs reviewed
  - 2026-05-03 v3: Karpathy test added to Stage 0 (N-A-1); UX standards as 11th universal floor for UI projects (R-6); architecture-taxonomy as Stage 0 spec input (N-A-1); 40-hour wall as bootstrap motivation (N-B-1); engagement-mode × automation-mode composition documented (R-8); Layer 3 mapping clarified (doctrine canon = mature form of NL Layer 3); Q8 pilot order recorded.
---

# Build Doctrine — Project Bootstrapping

## Scope

This document defines how a new project initializes its canon — design system, engineering catalog, conventions, gate configuration, observability — through an integrated process that runs alongside the first PRD intake. Bootstrapping is the primary operationalization of principle #5 ("System carries the structure"): the user describes the app they want to build, and the system uses that description to fill in as much canon as it can, surfacing decisions only when they actually require user input.

Bootstrapping happens once per project (and occasionally on major updates). It produces the **per-project canon** that every subsequent unit of work references.

**Project bootstrap is the highest-leverage moment for getting the doctrine right.** Per Nate B. Jones, the "40-hour wall" captures the empirical pattern: AI-augmented teams produce roughly 40 hours of un-rework-able output before structural drift forces a do-over. Bootstrap done well front-loads the structural work that pays back across every subsequent unit. Bootstrap done quickly — without addressing universal floors, canon shape, autonomy starting point, architecture taxonomy — produces the 40-hour wall as scar tissue. The reliability spine can only compound across stages 1-10 if Stage 0 (this document's scope) lays a substrate the later stages can anchor to.

This document specifies:

- The relationship between **build doctrine** (in `neural-lace/build-doctrine/`) and the **default templates repo** (semi-independent, `build-doctrine-templates/`).
- **Stage 0** — starting position, engagement mode selection, the Karpathy test, and architecture-taxonomy declaration.
- The **PRD-driven intake flow**, where PRD authoring and bootstrap canon initialization run as one integrated activity.
- The **canon shape** — seven categories of artifacts that emerge from the integrated intake.
- **Engagement modes** — Express, Standard, Deep, Custom — and how depth is tracked per decision.
- **Composition with NL automation modes** — engagement-mode (per-bootstrap-decision) is orthogonal to NL automation-mode (per-session execution surface).
- **Universal floors** — ten convention categories every project addresses; eleven for UI projects.
- **Layer 3 mapping** — how the doctrine's per-project canon is the mature form of Neural Lace's Layer 3.
- **Audit pass** — what the user sees after intake converges, and how to dispose of defaulted choices.
- **Update and re-bootstrapping protocol**, **adoption protocol** for existing projects, **anti-patterns**, **open questions**.

The integrated approach replaces the prior sequential bootstrap. The artifact separation stays the same (PRD ≠ conventions ≠ design system ≠ engineering catalog); the process is what converges.

---

## Architectural relationship: doctrine ↔ templates repo

The build doctrine and the default templates are deliberately separated:

- **Build doctrine** (`neural-lace/build-doctrine/`) defines **shape and rules** — what every templates instance must contain, what bootstrap looks like, what gates check. Stable; evolves through the knowledge integration ritual.
- **Default templates repo** (`build-doctrine-templates/`, separate repo) holds **default content** — actual proposed defaults for conventions, design system primitives, engineering catalog seeds, observability configs, naming conventions, lint configurations. Each template entry is structured for three-layer rendering: TL;DR, why, alternatives. Evolves more frequently as project experience refines defaults.

Each project at bootstrap time pins to a specific version of the templates repo. Updates can flow into existing projects via a defined pull mechanism. This separation means a default can improve without requiring a doctrine change, and a doctrine change doesn't force every default to be re-litigated.

---

## Stage 0 — Starting position, engagement mode, Karpathy test, architecture taxonomy

Bootstrap begins with four short questions that set the substrate for everything that follows. The first two (starting position, engagement mode) frame the intake flow. The next two (Karpathy test, architecture-taxonomy declaration) frame which gates the project's specs will be checked against.

### Starting position

| Position | Description |
|---|---|
| New project, vague idea | "I want to build something for X." Minimal stack/risk constraints stated up front. PRD-first intake. |
| New project, defined stack | "TypeScript service, deployed to AWS, customer-facing." Stack and risk constrained early. PRD-first but bootstrap inferences front-load. |
| Existing project, adopting doctrine | Codebase already exists. Extraction-first: AI reads existing state into canon, surfaces inconsistencies as findings. PRD intake runs after canon extraction. |

The starting position determines what AI emphasizes during intake — a vague idea needs more elicitation; a defined stack needs less; an existing project needs extraction. The PRD-driven flow (next section) accommodates all three.

### Engagement mode

| Mode | Description | Typical duration |
|---|---|---|
| **Express** | "Accept defaults; ask me only what cannot be defaulted." AI surfaces only the irreducible decisions; everything else applied silently from defaults + inferences. Audit at end. | 15–30 min |
| **Standard** | "Walk me through the decisions that matter; show defaults; let me confirm or deviate." AI surfaces decisions at category granularity; confirms each before applying. | 1–2 hours |
| **Deep** | "Show alternatives and trade-offs on every meaningful choice." AI surfaces the full three-layer template (TL;DR + why + alternatives) at every decision point. | half-day to full day |
| **Custom (mixed)** | Different modes per category. User picks at each surfaced moment. Most users default to this in practice — Express overall but Deep on the categories they care about (e.g., security, observability). | varies |

Mode is **per-decision, not per-bootstrap, and switchable mid-stream.** A user who chose Express overall can say "actually, go deep on logging" without restarting. The bootstrap state file tracks current mode and per-decision overrides.

**Harness implementation:** engagement-mode is a Pattern-class doctrine concept today; no NL hook gates it. A future `bootstrap-orchestrator` skill (Phase 1d-E or later) could operationalize the mode-per-decision dispatch and the audit-pass output. Until then, the AI authoring the conversation is the substrate.

### Karpathy test

Before any other Stage 0 work, answer: **"What are you optimizing against?"** Per Andrej Karpathy (cited via Nate B. Jones). The answer determines the architecture-taxonomy choice for this project.

- If the answer is **"a clear computable metric"** (e.g., a benchmark, a throughput target, an evaluation harness with numerical scoring), **auto-research architecture is feasible** because the system can run autonomous optimization loops against the metric.
- If the answer is **"verifiable behavioral scenarios with no human taste"** (e.g., contractual API behavior, deterministic transformations, well-specified state machines), **dark-factory becomes feasible** subject to Rung-5 readiness (holdout scenarios, evidentiary verification, digital twin universe).
- If the answer is **"human judgment about quality"** (UX taste, copy tone, design coherence, product-market fit), **coding-harness is the right architecture** and the project starts at coding-harness Rung 1 unless evidence justifies higher.

Stage 0 records the architecture choice as the third axis in the spec-header schema (per unified methodology Q4: `tier × rung × architecture` becomes a YAML-keyed header surface). Most application development falls in the third bucket; auto-research and dark-factory are real but specialized.

**Harness implementation:** Pattern-class today; no hook enforces the Karpathy diagnostic. The C-proposal map's C16 (behavioral-contracts schema check) indirectly catches the slip when an R3+ spec lacks the contract surface that dark-factory or auto-research would require, but the diagnostic itself is paper-only at Stage 0.

### Architecture taxonomy as Stage 0 input

The project's **architecture is a declared input alongside the autonomy rung.** Five options:

- `coding-harness` — AI assists or generates code with human review. Default for application development. Supports rungs R0–R3.
- `orchestration` — multi-step workflows with specialized agents passing structured outputs. Supports R1–R4.
- `auto-research` — autonomous optimization loops against computable metrics. Requires R4.
- `dark-factory` — specifications go in, working software comes out, no human reads code. Requires R5 plus holdout scenarios + evidentiary verification + digital twin universe.
- `hybrid` — different work units run at different architecture-rung combinations.

The architecture × rung × tier matrix in `04-gates.md` determines the gate set per dispatched unit. The project may revise architecture later (a coding-harness project could grow an auto-research subsystem for a hot-path optimization), but the bootstrap declaration **anchors initial gate-config and orchestrator behavior** — without it, the orchestrator has no basis to decide which gates fire on which unit.

**Harness implementation:** today, the architecture field lives in the bootstrap state file and is consumed by the doctrine's gate-matrix lookup. Mechanical enforcement of "the spec's declared architecture is consistent with the gates that ran" is forthcoming via C16 (behavioral-contracts schema check at R3+) and C13 (promotion / demotion gate) per `outputs/unified-methodology-recommendation.md` §6.

---

## PRD-driven intake flow

After Stage 0, intake runs as a single integrated activity. The PRD is the spine; bootstrap canon is initialized as a side-effect of PRD content + AI inferences + selectively surfaced decisions.

### How AI runs the flow

AI manages the conversation by prioritizing what to ask next. Each Q&A round consists of:

1. **AI assesses current state.** What's known about the app, the stack, the risk profile, the scale targets. What canon decisions are already constrained by what's known. What remains genuinely open.
2. **AI selects the next highest-priority surface.** This may be a PRD-content question ("what user roles does this support?") or a bootstrap-relevant question ("you mentioned PII storage — that pulls observability into the customer-facing-critical defaults; confirm or go deeper?"). AI prioritizes by impact: questions whose answers constrain the most downstream decisions go first.
3. **AI surfaces at the user's engagement mode for that decision.** Express: TL;DR only or silent default. Standard: TL;DR + why. Deep: full alternatives. User can always say "tell me more" or "show alternatives" to drop deeper, or "skip and default" to drop shallower.
4. **User responds.** Confirms, deviates with rationale, defers, or explicitly opts out of the question.
5. **AI updates state.** PRD draft, bootstrap canon, depth tracking, and pending question queue all update. Sometimes a user answer constrains many downstream decisions and prunes the queue significantly.

The AI's judgment is load-bearing here. It decides what to ask, when to ask, what to default silently, what to surface. The depth-tracked audit pass is the safety net — anything defaulted at depth 0 is shown to the user at the end for spot-checking.

### What AI listens for during PRD content

While walking through PRD intake (problem framing, scenarios, functional requirements, non-functional requirements, success metrics, out-of-scope), AI extracts bootstrap-relevant signals:

| PRD signal | Bootstrap implication |
|---|---|
| User mentions specific language / framework | Stack defaults narrow; lint, type, testing config inferable |
| User mentions deployment (web, mobile, edge, etc.) | Observability defaults; CI/CD shape; performance budgets |
| User mentions storing or processing PII / payments / health data | Risk profile escalates; auth, observability, secrets defaults tighten |
| User mentions multi-region or high-traffic | Scale defaults; tracing required; rate-limit design |
| User mentions third-party integrations | Cross-repo edges seeded into Integration Map |
| User mentions team composition | Documentation defaults; review process; commit/branch conventions |
| User mentions compliance requirements (HIPAA, SOC2, PCI, GDPR) | Specific gate additions; explicit security conventions |
| User describes UI elements | Design system seeding triggered; UX-standards floor (#11) activates |
| User describes workflows / state transitions | State management and architectural defaults |
| User mentions budget / timeline pressure | Engagement mode may default to Express for non-critical categories |

AI doesn't ask about these directly out of nowhere. It surfaces the implication when the user mentions the relevant content. "You mentioned this stores customer payment info — the default is the customer-facing-critical observability profile and PCI-aware auth conventions. Confirm or want to see alternatives?"

### Minimum required info before convergence

AI cannot freeze PRD + bootstrap canon until a minimum threshold of information is reached. The threshold is:

- **PRD minimum**: problem statement, primary scenario, top three functional requirements, identified non-functional category coverage (each of: performance, security, accessibility, observability, reliability has either a stated requirement or explicit "not applicable with rationale"), success metric stated, out-of-scope acknowledged.
- **Bootstrap minimum**: language/runtime confirmed; deployment target confirmed; risk profile confirmed; team shape confirmed (solo / small / distributed); architecture-taxonomy choice confirmed (per Stage 0 Karpathy test); each universal floor category (ten, or eleven for UI projects) has either a stated convention, explicit confirmation of the proposed default, or explicit deferral with rationale.

If the user attempts to converge early in Express mode without minimum thresholds met, AI surfaces what's still missing: "You haven't told me about deployment target or expected scale. I need at least one of: a one-line deployment description, or permission to default both to the lowest-risk profile. Which?"

The minimums prevent shallow bootstraps that crater later. They don't require deep deliberation — Express mode lets the user clear them in single-line answers.

### Surfaced bootstrap moments — order of priority

When AI selects what to surface during a Q&A round, this rough priority order applies:

1. **Stack-fundamental decisions** — language, runtime, primary framework. These constrain everything downstream.
2. **Risk profile** — because it parameterizes most defaults.
3. **Deployment target** — affects observability, performance budgets, CI/CD shape.
4. **Architecture-taxonomy choice** (per Karpathy test) — determines gate set per dispatched unit.
5. **Data sensitivity** — drives auth, secrets, observability tightening.
6. **Scale targets** — drives architectural defaults, async patterns.
7. **Team shape** — drives documentation, review, commit conventions.
8. **UI primitives** (if applicable) — drives design system seeding and UX-standards floor (#11).
9. **Module structure** — drives engineering catalog initialization.
10. **Naming preferences** — defaults are usually accepted; surfaced when stack constrains them.
11. **Per-category convention deviations** — surfaced when project-specific reasons exist; otherwise defaulted.
12. **Gate thresholds** — usually defaulted from risk profile; surfaced for deep mode or when user wants explicit control.

AI deviates from this order based on what the PRD content reveals. If a user describes a healthcare app in Stage 0, data sensitivity jumps to position 1 because it dominates downstream choices.

---

## Canon shape — seven categories

The artifacts that emerge from the integrated intake. AI fills these in as PRD content + inferences + user confirmations land. Each frozen artifact references its bootstrap version and the depth of engagement per choice.

| Category | Artifact | Primary contributors |
|---|---|---|
| Project profile | `README.md` header + `engineering-catalog.md` profile section | Stage 0, PRD intake |
| Conventions | `conventions.md` (covers ten — or eleven for UI projects — universal floors + naming + architectural defaults) | PRD content + defaults + surfaced decisions |
| Design system (UI projects) | `design-system.md` (tokens, primitive components, accessibility baseline, anti-patterns) | PRD UI descriptions + defaults + surfaced decisions |
| Engineering catalog | `engineering-catalog.md` (modules, public contracts, reuse map, **Integration Map**, deprecations, ADR index) | PRD module descriptions + integration mentions + defaults |
| Gate config | `gate-config.yaml` (thresholds per gate per tier, hot path declarations, perf budgets) | Risk profile + architecture-taxonomy + defaults |
| Observability | `observability.md` (run logs, state files, drift logs, findings ledger format and locations) | Defaults + scale inferences |
| Bootstrap state | `.bootstrap/state.yaml` (engagement mode, per-decision depth, automation-mode pairing, architecture-taxonomy declaration, audit log of intake conversation) | Continuous — AI maintains throughout intake |

These categories are not walked through in any fixed order. They emerge as PRD content + AI inferences + surfaced decisions land.

---

## Composition with NL automation modes

**Engagement modes (Express / Standard / Deep / Custom — defined in this document, per-bootstrap-decision) compose orthogonally with NL automation modes (Interactive local / Parallel local / Cloud remote / Scheduled / Agent Teams — defined in `~/.claude/rules/automation-modes.md`).** They measure different things and never substitute for each other.

- **Engagement mode shapes how heavily the user engages during bootstrap.** Express means "ask me only what you must"; Deep means "show me alternatives at every meaningful choice." It governs the human-in-the-loop density of the project-bootstrap conversation.
- **Automation mode shapes per-session execution surface.** Interactive local is the default IDE/CLI session; Cloud remote is `claude --remote` for multi-hour autonomous builds; Scheduled fires Routines on cron or events; Agent Teams (experimental) lets a lead spawn cooperating teammates with direct messaging. It governs where the per-action enforcement substrate runs and how isolated concurrent sessions are.

A project bootstrapped in **Express mode** may run sessions in **Cloud remote mode** — the user accepted defaults at bootstrap time and now wants long autonomous runs. A project bootstrapped in **Deep mode** may run sessions in **Interactive local mode** — the user deliberated heavily on canon and now wants tight-loop steering on each session. Any pairing is legitimate; the two are independent and both must be declared in the project's bootstrap state.

The `.bootstrap/state.yaml` file records both:

```
engagement_mode: express | standard | deep | custom
default_automation_mode: interactive_local | parallel_local | cloud_remote | scheduled | agent_teams
```

The default automation mode is the project's recommended starting point; individual sessions can override (a Deep-bootstrapped project may still run a one-off Cloud remote session for a specific autonomous task). The pairing is documentation, not enforcement — `~/.claude/rules/automation-modes.md` is the substrate that governs each session's actual execution mode.

**Harness implementation:** automation-mode is enforced at NL's session granularity (`~/.claude/rules/automation-modes.md` is loaded when each session starts). Engagement-mode is enforced at the doctrine's project granularity (paper-only today; potential `bootstrap-orchestrator` skill in Phase 1d-E). The two enforcement substrates compose without conflict because they fire at different cadences (project-bootstrap once vs. per-session always).

---

## Layer 3 mapping — doctrine canon as the mature form of NL's Layer 3

Neural Lace's `docs/harness-strategy.md` defines **Layer 3 as "Project — per-repo rules, audience, context — changes per project."** Today, NL's Layer 3 is light: project `.claude/rules/`, `.claude/audience.md`, and the project's top-level `CLAUDE.md`. The doctrine's per-project canon (project profile, conventions including the now-eleven universal floors, design system, engineering catalog with Integration Map, gate config, observability, bootstrap state) **is Layer 3 expanded into structured artifacts.**

The mapping is direct:

| NL Layer 3 (today) | Doctrine canon (mature form) |
|---|---|
| project `.claude/rules/` | `conventions.md` (eleven universal floors + naming + architectural defaults) |
| project `.claude/audience.md` | `README.md` profile + `engineering-catalog.md` profile section |
| project `CLAUDE.md` | `engineering-catalog.md` (modules, contracts, reuse map, Integration Map, deprecations, ADR index) |
| (none — design-system is implicit today) | `design-system.md` (tokens, primitives, accessibility baseline, anti-patterns) for UI projects |
| (none — gate config is implicit) | `gate-config.yaml` (thresholds per gate per tier, hot path declarations) |
| `.claude/state/` (per-session ephemeral) | `observability.md` (run logs, state files, drift logs, findings ledger format) |
| (none — bootstrap is implicit) | `.bootstrap/state.yaml` (engagement mode, per-decision depth, audit log) |

**A project that adopts this doctrine populates a richer Layer 3** than NL's reference description. A project that doesn't adopt the doctrine still has a Layer 3, just smaller — the existing NL artifacts cover a useful subset. **The doctrine's value-add is heaviest at Stage 0 because NL has no project-bootstrap concept;** every later stage (1-10 of the reliability spine in the unified methodology) has both doctrine and NL contributors, but Stage 0 is doctrine-owned end-to-end.

This mapping is also why the doctrine survives-as-is here: NL has nothing equivalent to PRD-driven intake, engagement-modes, the Karpathy test, the canon-shape framework, or the universal floors. Phase 1d-B's comparative analysis identified `08-bootstrap` as **the strongest survives-as-is candidate** because the abstraction layer is genuinely different.

**Harness implementation:** the canon artifacts are documents the project authors and commits to its repo. NL's Layer 3 mechanisms (project `.claude/rules/` loading, `audience.md` reading, `CLAUDE.md` ingestion at SessionStart) operate on the subset of canon that NL recognizes today. Future C-mechanisms — particularly C5 (Engineering catalog / Integration Map consistency gate) and C6 (Design system consistency gate) per `outputs/unified-methodology-recommendation.md` §6 — extend NL to mechanically validate the design-system and engineering-catalog artifacts against project state.

---

## Engagement modes in detail

### Express

**What AI does:** Asks only the minimum-required questions (see Minimum required info above). Applies all template defaults silently for everything else. Surfaces nothing at category-by-category granularity.

**What user sees:** Short Q&A focused on PRD problem-and-scenarios + four to six bootstrap-fundamental questions. Defaults visible only in the audit summary at the end.

**When this mode fits:** Throwaway prototypes, hackathon projects, internal tools where the user trusts defaults wholesale, projects where the developer is highly experienced and just wants the structure in place.

**Risk:** User accepts a default that turns out to be wrong for the project's actual needs. Mitigation: depth tracking + audit pass + propagation rules that can update canon retroactively as later PRDs reveal mismatches.

### Standard

**What AI does:** Walks through PRD intake stages while interleaving bootstrap decisions at category granularity. For each meaningful category (logging, auth, testing, etc.), AI surfaces TL;DR + brief why, asks for confirm / deviate / not applicable.

**What user sees:** Full PRD conversation plus roughly 10–25 bootstrap surfaced moments, each a 1–3 minute exchange.

**When this mode fits:** Most new projects from experienced developers who want explicit control over the major choices but aren't optimizing for every detail.

**Risk:** User confirms defaults without engaging deeply, treating it as ceremony. Mitigation: AI varies its prompts to encourage thinking ("here's the default; does it fit your case?") rather than pure approval flow.

### Deep

**What AI does:** Surfaces full three-layer template content (TL;DR + why + alternatives) at every meaningful decision. Engages in trade-off discussion. Can write ADRs as decisions land if the choice is architectural.

**What user sees:** Extended deliberation, often in multiple sessions. The bootstrap state file holds progress across sessions.

**When this mode fits:** First project on a new doctrine adoption. Projects with novel constraints. Architecture-heavy projects where the canon decisions ARE the work.

**Risk:** Analysis paralysis; bootstrap never converges. Mitigation: AI tracks time-in-decision and gently nudges convergence after extended debate ("we've been on this for 25 minutes; should we accept the current default and revisit if needed, or is this worth more time?").

### Custom (mixed)

**What AI does:** At each surfaced moment, AI presents the choice at the project's overall mode but offers a one-line "want to go deeper / shallower on this one?" option.

**What user sees:** The bootstrap they expected based on their default mode, with the freedom to drop in or out per decision.

**When this mode fits:** Most users in practice. Express overall, Deep on the few categories they care about (often security, observability, or whatever bit them in a prior project).

**This is the recommended starting mode for users who haven't bootstrapped a project under this doctrine before.** It surfaces the choice without forcing commitment to a mode they haven't tested.

---

## Depth tracking per decision

Every canon decision is annotated with the depth at which the user engaged:

- `depth: 0` — defaulted silently, never reviewed
- `depth: 1` — TL;DR seen, confirmed
- `depth: 2` — Why seen, confirmed
- `depth: 3` — Alternatives compared, deliberated

The bootstrap state file logs depth per choice. After bootstrap, the system can answer questions like:

- "What did I default at depth 0 in this project?"
- "Across my projects, which defaults do I almost always deepen on?" (signal for the knowledge integrator: those defaults may need refinement)
- "What was the rationale for choosing X over Y on this project?" (depth 3 entries carry rationale)

---

## The minimum cannot be defaulted

Some decisions cannot be defaulted away regardless of engagement mode. AI must surface them and get explicit user input. Stage 0 starting position covers most of these.

Mandatory surfaced decisions:

- Project name and one-line description
- Primary language / runtime
- Deployment target (one-liner is sufficient)
- Risk profile (with TL;DR of what each implies)
- Existing-project flag
- Architecture-taxonomy choice (per Stage 0 Karpathy test)

Conditionally mandatory (surfaced only if PRD content reveals applicability):

- Compliance regimes that change defaults (HIPAA, PCI, SOC2, GDPR)
- Multi-region or strict latency targets
- External integrations that need Integration Map seeding
- UI primitives (triggers UX-standards floor #11 + design-system seeding)

---

## Audit pass

After PRD freeze + canon convergence, AI presents the audit summary:

```
Bootstrap complete.

PRD: frozen at depth 3 (deep elicitation through 6 stages).
Conventions: 23 of 31 choices at depth 0 (silently defaulted from templates repo v2.4.1).
  - Logging: depth 1, accepted JSON structured default
  - Auth: depth 3, deviated from default to use Auth0 OIDC (rationale logged)
  - [21 more...]
Design system: not applicable (non-UI project).
Engineering catalog: 4 modules seeded at depth 0; Integration Map empty.
Gate config: 12 thresholds at depth 0; 3 reviewed at depth 1.
Observability: 6 settings at depth 0.
Architecture taxonomy: coding-harness (Karpathy: human judgment about quality).
Default automation mode: interactive_local.

You can:
  [1] Spot-check specific categories now
  [2] Schedule a review (calendar reminder + personal-knowledge-tool follow-up entity)
  [3] Proceed to first build; revisit when issues surface
  [4] Open the bootstrap state file for direct edit

Recommended: option 3 unless any depth-0 category felt important to you. The findings ledger and propagation triggers will surface mismatches later if defaults turn out wrong.
```

The audit is the safety net for Express mode and the documentation trail for Deep. It exists in both cases.

---

## Universal floors — the eleven convention categories

Every project's `conventions.md` must address each. AI surfaces them at the user's engagement mode during intake or applies defaults silently in Express. Schema validation gates the file on freeze; missing categories fail the gate.

The first ten apply to every project. The eleventh applies only to UI projects.

1. **Logging** — structured vs. unstructured, levels, never-log list, correlation IDs, retention, library.
2. **Error handling** — typed errors / class hierarchy, public response shape, retry semantics, what gets logged.
3. **Secrets handling** — storage, injection, rotation, scanning, accidental-commit response.
4. **Input validation** — where, library, error flow.
5. **Auth and authorization** — identity source, where authz checked, audit logging on auth events.
6. **Observability beyond logs** — metrics, traces, alerts.
7. **Testing** — directory structure, categories, mocking philosophy, fixtures, coverage targets.
8. **Documentation in code** — docstring/JSDoc requirements, README structure, ADR triggers.
9. **Dependency policy** — addition process, license policy, security scanning, update cadence.
10. **Versioning** — SemVer or alternative, breaking-change policy, public/internal API distinction.
11. **UX standards** (UI projects only) — color rules (red = error/critical only; purple = AI), contrast in light AND dark modes (filled-button rule, explicit `dark:` variants on every text/border class), every-card-clickable, every-number-needs-context, attention hierarchy, micro-interactions, accessibility baseline. Also the seven baseline UX principles: errors suggest a solution, suggestions link directly to action, empty states explain why and offer a first action, destructive actions require confirmation with reversibility info, success states confirm and reveal what's next, loading states describe what's loading, warnings by color.

The 11th floor explicitly applies only to UI projects; non-UI projects skip it with rationale recorded in `.bootstrap/state.yaml`. Bootstrap state's audit pass surfaces any project that flagged itself UI but defaulted floor 11 to depth 0 — the user spot-checks before convergence.

The actual default content lives in the templates repo (`build-doctrine-templates/conventions/universal-floors/`).

**Harness implementation per floor (where NL mechanizes):**

- **Floor #3 (Secrets handling)** — operationalized by NL's `harness-hygiene-scan.sh` pre-commit hook + `pre-push-scan.sh` (18 built-in patterns + personal + team) + inline PreToolUse blockers on `.env` / `credentials.json` / `secrets.yaml`. Doctrine declares the convention; NL enforces at edit time.
- **Floor #7 (Testing)** — operationalized by NL's `pre-commit-tdd-gate.sh` (4-layer scan: new files need tests, modified runtime files need tests importing them, integration cannot mock, trivial assertions banned, silent-skip patterns banned) + `no-test-skip-gate.sh` + `runtime-verification-executor.sh`. Doctrine declares the testing convention; NL enforces at commit time.
- **Floor #11 (UX standards)** — operationalized by NL's mandatory `ux-designer` agent review before building any new UI surface (per `~/.claude/rules/planning.md` and `~/.claude/agents/ux-designer.md`) plus the three UX testers (`ux-end-user-tester`, `domain-expert-tester`, `audience-content-reviewer`) per `~/.claude/rules/testing.md` after substantial UI builds. The seven baseline UX principles live in `~/.claude/rules/ux-design.md`; the deeper standards (color rules, contrast, attention hierarchy, micro-interactions, accessibility) live in `~/.claude/rules/ux-standards.md`. Doctrine declares the floor; NL enforces at plan-review and post-build review.
- **Floors #1, #2, #4, #5, #6, #8, #9, #10** — Pattern-class today; no NL hook gates them directly. The C-proposal map's C12 (propagation-event hook generalization) is the long-term mechanization path: a generalized router that detects floor-relevant edits and surfaces findings against unaddressed-floor convention deviations.

---

## Naming convention defaults

Per language. Project may override per-category with rationale. Defaults are surfaced in Standard and Deep modes; applied silently in Express.

### JavaScript / TypeScript

| Category | Default |
|---|---|
| Files (general) | `kebab-case.ts` |
| Component files | `PascalCase.tsx` |
| Test files | `*.test.ts` |
| Variables, functions | `camelCase` |
| Constants (compile-time) | `SCREAMING_SNAKE_CASE` |
| Types, interfaces, classes | `PascalCase` |
| Boolean variables | prefix with `is`, `has`, `can`, `should` |
| Enum values | `PascalCase` |
| React hooks | prefix with `use`, `camelCase` |

### Python

| Category | Default |
|---|---|
| Files | `snake_case.py` |
| Test files | `test_*.py` or `*_test.py` |
| Functions, variables, methods | `snake_case` |
| Classes | `PascalCase` |
| Constants | `SCREAMING_SNAKE_CASE` |
| Modules, packages | `lowercase_short` |
| Private members | prefix with `_` |

### Go

| Category | Default |
|---|---|
| Files | `lowercase` (single word) or `lowercase_snake` |
| Test files | `*_test.go` |
| Exported identifiers | `PascalCase` |
| Unexported identifiers | `camelCase` |
| Acronyms | preserve case (`HTTPServer`, not `HttpServer`) |

### Rust

| Category | Default |
|---|---|
| Files | `snake_case.rs` |
| Functions, variables | `snake_case` |
| Types, traits, enums | `PascalCase` |
| Constants, statics | `SCREAMING_SNAKE_CASE` |

### Branch naming

`feat/`, `fix/`, `hotfix/`, `chore/`, `docs/`, `refactor/`, `spike/` followed by `short-description`.

### Commit messages

Conventional Commits format. Prefix with type. Breaking changes: `BREAKING CHANGE:` in body or `!` after type.

### Directory structure (general defaults; language-idiomatic specifics override)

`src/`, `tests/` (or colocated), `docs/`, `docs/decisions/` (ADRs), `scripts/`, `fixtures/`, `migrations/`.

---

## Update and re-bootstrapping protocol

### Templates repo updates

When the templates repo publishes a new version, existing projects can:

- **Pin** — stay on current version. No action.
- **Pull diff and review** — AI runs a diff against the project's instantiated canon, surfaces what changed, walks through user disposition per category at the user's engagement mode.
- **Full re-bootstrap** — rare; for major doctrine alignments. Re-runs the integrated intake at the user's chosen mode, preserving project-specific choices where possible.

### Project conventions changes

When a project decides to change a convention (e.g., adopt a new logging library), the change is itself a Tier 4 work unit per `03-work-sizing.md` and `05-implementation-process.md`. The change updates `conventions.md` and triggers propagation (T8 — conventions change) which opens findings against existing code that no longer matches. A migration plan is part of the spec; migration may decompose into many Tier 1–3 sub-units.

### Doctrine changes propagating to bootstrap

When the build doctrine itself changes — e.g., a new universal floor category is added, or the eleven floors expand to twelve — existing projects' bootstraps are flagged for re-visit. The propagation rule (T4 doctrine change) opens findings on each project's bootstrap state.

---

## Adopting doctrine on existing projects

For projects with significant existing code, full bootstrap from scratch is impractical. The adoption protocol:

1. **Stage 0** runs as usual — but starting position is "Existing project, adopting doctrine."
2. **Extraction first.** AI reads the codebase and proposes initial canon by inferring current state — extracted module structure, observed naming patterns, current logging library, etc. The user reviews and corrects.
3. **PRD intake runs second**, against the extracted canon rather than empty canon. Subsequent PRDs run as usual.
4. **Drift findings expected.** Adopting doctrine on existing code reveals inconsistencies (different logging styles, undocumented contracts, missing gates). These become initial findings ledger entries with severity reflecting urgency.
5. **Migration plan optional but recommended.** Some inconsistencies are accepted as legacy; others queue for cleanup work units. The bootstrap doesn't block on full conformance.

The principle: doctrine adoption surfaces what's there and decides what to fix. It doesn't gatekeep.

### Pilot order (user-confirmed 2026-05-03)

The unified methodology recommendation §8 originally proposed an adoption order across four pilot projects. The user clarified on 2026-05-03 (per Q8 of the methodology recommendation) that **the canonical pilot project's secondary component is part of the canonical pilot project, not a separate pilot.** The amended pilot order is:

1. **The canonical pilot project (with its secondary component as one effort)**
2. **The personal-knowledge tool** (a sibling pilot project)
3. **Pilot project B** (a personal-finance project)
4. **Pilot project C** (an automation-pilot project)
5. **Pilot project D** (an internal-admin project)

This is the user-confirmed adoption order; **future projects start at coding-harness Rung 1 unless explicitly justified otherwise** (per `09-autonomy-ladder.md`'s default-rung discipline). Treating the secondary component as part of the canonical pilot consolidates the first pilot effort and frees the second slot for the personal-knowledge tool earlier than originally proposed. The cross-project pattern detection that informs subsequent pilots' canon defaults (per the knowledge integrator role) runs against NL's `docs/reviews/` per Q11 — the personal-knowledge tool is itself a pilot project, not the harness-meta owner.

---

## Expected duration

| Project type | Express | Standard | Deep |
|---|---|---|---|
| Greenfield small project | 15–30 min | 1–2 hours | 4–8 hours |
| Greenfield mid-size | 30–60 min | 2–4 hours | full day |
| Existing small project, adopting | 30–60 min | 2–3 hours | day-scale |
| Existing large/legacy, adopting | 1–2 hours minimum | 4–8 hours | multi-day, staged |

Custom (mixed) mode usually lands between Express and Standard depending on which categories the user deepens on.

---

## Anti-patterns

### Sequential walkthrough

The prior version of this document had a fixed seven-stage walkthrough. That structure forced users through bootstrap regardless of whether their app idea pre-constrained the answers. The integrated PRD-driven intake replaces this; sequential walkthrough is now an anti-pattern.

### AI asks about everything regardless of mode

Ignoring engagement mode and surfacing every category-level decision in Express. Defeats the whole point of mode selection.

### Templates as plain markdown

Templates that only have a default value, with no TL;DR / why / alternatives structure. Forces users into Express by default because there's nothing to deepen on. The three-layer template structure is what makes Standard and Deep meaningful.

### Bootstrap by checklist

Treating intake as a form to fill out. The point is the conversation: AI proposes from inferences, user catches what AI missed. Skipping the dialogue produces a shallow canon.

### Forcing convergence below minimums

Allowing freeze when minimum required info isn't met. AI must enforce the minimum thresholds; "I'll figure that out later" without rationale capture is the path to canon that doesn't actually constrain anything.

### Premature crystallization

Treating the first-PRD bootstrap as final. Canon is itself living per principle #9; it updates as later PRDs reveal what the first didn't anticipate.

### Conventions as documentation only

Writing `conventions.md` and never enforcing it. Conventions only have value when adversarial review prompts reference them, lint rules enforce them, and findings ledger captures violations.

### Re-bootstrap as default for every doctrine change

Overreacting to small doctrine updates with full re-bootstraps. Most doctrine changes flow as targeted findings, not full re-runs.

### Skipping the Karpathy test or architecture declaration

Bootstrapping without naming what the project is optimizing against, or without declaring an architecture-taxonomy choice. Both produce bootstrap state that the orchestrator cannot use to select the right gate set per dispatched unit, which collapses every later stage of the reliability spine because the gates aren't anchored.

### Conflating engagement mode with automation mode

Treating "Express engagement" as equivalent to "full-auto deployment" or "Deep engagement" as equivalent to "Interactive local." The two are orthogonal. Bootstrap engagement is about how heavily the user engaged in the canon-authoring conversation; automation mode is about where the per-action enforcement substrate runs. Conflating them produces brittle pairings (e.g., refusing to run cloud-remote sessions on an Express-bootstrapped project) that have no doctrinal basis.

---

## Open during fresh-draft phase

- **AI judgment calibration.** "When to surface vs. default silently" is the load-bearing AI judgment in this design. The doctrine sketches priorities; the actual judgment will refine through pilot use, with depth-deepening patterns feeding the knowledge integrator.
- **Templates repo organization.** Single repo with subdirectories per project type, monorepo with workspaces, or multiple repos. Deferred until templates repo is actually built.
- **Pull-diff-and-review tooling.** The mechanism for surfacing template repo changes against an instantiated project. Likely a structured diff with category-by-category disposition; specifics deferred.
- **Multi-language projects.** Naming defaults table assumes one primary language. Polyglot projects need a per-language section in their conventions doc.
- **Templates repo governance.** Who can update the defaults, what rituals govern changes. Likely runs through the same knowledge integration ritual as the doctrine itself, but with potentially looser cadence.
- **Stage 0 for migrations vs. green new.** Some adoptions are gradual; the protocol may need finer subdivision than greenfield/existing.
- **Bootstrap-orchestrator skill.** A potential Phase 1d-E artifact that operationalizes engagement-mode dispatch and the audit-pass output as a slash command, raising engagement-mode from Pattern to partial Mechanism.

## Next step

Phase 1c integration of `08` is complete with this document. The remaining bootstrap-adjacent work for the unified methodology lives in subsequent phases:

- Phase 1d-C — first-pass C-proposals (C1 PRD validity, C2 spec freeze, C5 / C6 catalog and design-system consistency gates) that mechanize parts of the bootstrap-output canon.
- Phase 1d-E — potential `bootstrap-orchestrator` skill and templates-repo scaffolding.
- First pilot — the canonical pilot project (with its secondary component as a single effort), per Q8 amendment.
