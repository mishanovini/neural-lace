# Getting Quality Out of Claude Code — Strategy and Harness Design

**Last updated:** 2026-05-05 (Build Doctrine integration arc + Gen 6 narrative-integrity hooks added)
**Source material:** Transcript of a 2026-04-22 strategy discussion between the harness maintainer and a collaborating engineer; Neural Lace harness design docs; Build Doctrine integration synthesis (May 2026).

This document codifies the strategy the maintainer has developed for extracting maximum quality from Claude Code, and maps each principle to its concrete manifestation in the Neural Lace harness. It exists so the strategy is legible to (a) the maintainer in future sessions, (b) collaborating engineers working with the harness, and (c) anyone who adopts Neural Lace externally and wants to understand the "why" behind its choices.

> **Generation arc as of May 2026.** Gen 4 (2026-04-15) shipped the core anti-vaporware mechanism layer. Gen 5 (2026-04-24) added adversarial observation of the running product (end-user-advocate acceptance loop), plan-lifecycle integrity, and a self-improvement meta-loop. Gen 6 (2026-04-26) closed the gap between agent claims and transcript evidence with six narrative-integrity Stop hooks (A1, A3, A5, A7, A8). The **Build Doctrine integration arc** (May 2026) shipped seven mechanism families addressing structural gaps the prior generations didn't cover: Discovery Protocol (proactive learning capture), comprehension gate (R2+ articulate-before-checkbox), PRD validity + spec freeze, findings ledger, definition-on-first-use, scope-enforcement-gate redesign (plans as living artifacts), DAG review waiver gate. **2026-05-06 extension:** Tranches 2 (template schemas), 3 (template content), 5a (knowledge-integration ritual at `build-doctrine/doctrine/07-knowledge-integration.md` — 7 KIT triggers), 6-orch (Python orchestrator scaffolding), 6a (propagation engine framework + 8 starter rules + JSONL audit log), and 5a-integration (audit-log analyzer + `/harness-review` Check 13 + pilot-friction template) all shipped — pre-pilot measurement substrate now complete. See `docs/harness-architecture.md` for the full mechanism inventory and `docs/decisions/013-024` for the integration arc's decision records.

---

## Core Philosophy

Four beliefs underpin the entire strategy. Every mechanism in Neural Lace traces back to one of these.

### 1. Quality beats speed at every time scale

> *"If it takes 24 hours to build instead of two hours, but it finishes and it's like solid, I will take that."*

Claude Code's default posture is to favor performance over quality — what the maintainer calls its *"pressure to complete."* Rebuild cycles from shipping buggy code consume more tokens, more time, and more trust than longer upfront builds. The correct trade-off is always in favor of quality.

**Operational implication:** the `effort` setting should be set to `extra high` at minimum, `max` when quality still suffers. The setting *"actually provides more context window to every individual agent so that it doesn't feel the pressure of having to try and finish within before running out of context."* It directly relieves the quality-destroying pressure-to-complete bias.

### 2. Determinism requires mechanism AND prompt — both layers, not either/or

> *"Context and prompts are not perfect… it's guidance but it's not deterministic. So the one deterministic thing that we can do to keep things on track is to create hooks."*

Prompts alone are probabilistic. Claude will sometimes acknowledge a directive and then quietly work around it — *"Cloud Code tends to sometimes be like hey I have direction to do things this way but when things come down to it I still tend to work around them."* But hooks alone aren't enough either — a hook only catches specific, mechanically-detectable violations. Many quality concerns (tone, judgment calls, cross-cutting patterns) can only be communicated through prose guidance.

The correct architecture is **both layers working together:**

- **Prose as guidance** — `CLAUDE.md`, rule files, agent prompts, plan templates. Tells the agent *what's expected* and *why*. Shapes 80% of behavior for 20% of cases.
- **Hooks as physics** — PreToolUse, PostToolUse, Stop hooks. *Enforce* the rules that must not be violated, even when prose guidance was present but ignored.

Prose is the instruction; hooks are the backstop. Neither substitutes for the other. Prose without hooks is aspirational; hooks without prose are inscrutable (the agent doesn't know *why* it got blocked).

**Operational implication:** any rule that matters needs both a prose description (so the agent understands the intent and follows it most of the time) AND a hook (so violations are mechanically blocked when the agent drifts). If you catch a bug class that was already documented in prose, the next step is to add the hook that makes violations impossible, not to rewrite the prose. If you add a hook, also add the prose that explains what it's checking for — otherwise future agents hit the hook without context for how to comply.

### 3. Adversarial context separation is load-bearing

> *"If you can build an agent to be adversarial — so it doesn't share the same context, it doesn't share the same goals — that adversarial agent is usually like a tester or validator. Its goal is to check the work that was just done. That forces the builder to be like I cannot get around this until I do these things properly."*

Shared context = shared blind spots. The builder agent has every incentive to declare "done" and move on; handing verification back to the same agent defeats the purpose. Separation of builder and verifier, with different goals and different context windows, is the single architectural principle that most reduces vaporware.

**Operational implication:** for any task that matters, there must be an independent validator — different agent, different context, explicitly adversarial goal — whose approval is the gate to moving on.

### 4. Ask, don't tell

> *"Instead of telling it what to do, ask it what to do. You usually get great responses from it."*

Claude is strikingly honest about its own failures if prompted to surface them. The canonical meta-questions the maintainer re-uses after any significant work:

- *"Why did Claude Code allow these bugs to exist? What in the system allowed these bugs to exist?"*
- *"How could we have done this better? How can we take those lessons learned and build those back into the harness?"*

The system can explain its own weaknesses better than a human can guess them. Exploit that honesty.

**Operational implication:** every failure becomes a prompt — not "fix this" but "explain what allowed this, and how the harness should have prevented it." The answer gets codified into a new hook, agent, or rule.

---

## The Operating Model

### Systems engineering, not software engineering

> *"No longer are you going to be writing code yourself. Instead of doing software engineering, we now are going to be doing systems engineering. Directing the virtual software engineers to do their job well because they're not always doing it perfectly."*

the maintainer reports not reading code himself — *"I literally have not looked at code myself at all. Like zero."* Claude builds, the harness verifies, the human interrogates Claude about what went wrong. This requires confidence that the verification layer is strong enough to trust. The harness is what lets you stop reading code.

This shifts the human's work from "catching errors by hand" to "making sure the system catches errors automatically."

### SRE-style oscillation: build vs. harness work

The mental model is Google's Site Reliability Engineering:

- **When implementation is working cleanly** → spend ~99% of time on implementation (via delegation to Claude)
- **When implementation is getting buggy** → step back, improve the system (harness) itself, then return

*"You need to be able to move in both directions based on how effective the implementation is being."*

the maintainer reports currently spending *"half my time focused on the harness as opposed to actual implementation"* — the SRE signal that the system needs investment before more builds happen on top of it.

### Patience as a prerequisite

> *"Patience is going to be a new prerequisite for working with Claude."*

Both sides of this matter:
- Patience with the builder (long builds, iterative planning, verbose plans)
- Patience with the harness (not every bug justifies a new hook; pick the ones that represent classes)

### Delegation without blind trust

The harness provides the trust substrate. Without mechanical enforcement, delegation becomes dangerous. With it, the maintainer can run sessions in the background while doing other work — *"I have it running in the background building out this conversation flow that I was just telling you about."*

---

## The Mechanical Enforcement Stack

This is how Neural Lace turns the four core beliefs into executable code. Every row is a mechanism backed by a specific file. No aspirational enforcement.

### From "Quality beats speed" →

| Mechanism | File | What it does |
|---|---|---|
| **Max effort setting** | User-level config | Gives each agent more context budget so it doesn't rush |
| **Tool-call budget** | `hooks/tool-call-budget.sh` | Blocks after 30 Edit/Write/Bash calls without a `plan-evidence-reviewer` audit — forces periodic audit to catch drift |
| **Verbose planning requirement** | `rules/planning.md` + `agents/systems-designer.md` | Plans must enumerate assumptions, files, edge cases; short plans are rejected as incomplete |
| **Long-build acceptance** | Philosophy, documented in `best-practices.md` | 24-hour build with correctness beats 2-hour build with bugs |

### From "Determinism requires mechanism" →

| Mechanism | File | What it does |
|---|---|---|
| **Evidence-first checkbox flips** | `hooks/plan-edit-validator.sh` | Plan checkboxes cannot be self-flipped; require fresh evidence block within 120 seconds |
| **Runtime verification executor** | `hooks/runtime-verification-executor.sh` | Parses and executes `Runtime verification:` lines (test/playwright/curl/sql/file) |
| **Runtime verification correspondence** | `hooks/runtime-verification-reviewer.sh` | Verifies verification commands actually target the modified files, not unrelated artifacts |
| **Pre-commit TDD gate** | `hooks/pre-commit-tdd-gate.sh` | 5-layer enforcement: new files need tests; modified files need full-path imports; integration tests can't mock; trivial assertions banned; silent-skip patterns rejected |
| **Pre-stop verifier** | `hooks/pre-stop-verifier.sh` | Blocks session end if plan has unverified tasks |
| **Credential scanner** | `git-hooks/pre-commit` + `hooks/pre-push-scan.sh` | Two-layer mechanical block on credential leaks — the pattern the maintainer brought from a prior defense-industry role with rigorous QA practices |
| **Bug persistence gate** | `hooks/bug-persistence-gate.sh` | Scans transcript for bug-trigger phrases ("we should also", "known issue"); blocks if no persistence happened. *Build Doctrine extension:* now also accepts `docs/discoveries/YYYY-MM-DD-*.md` and `docs/findings.md` as legitimate durable-storage targets |
| **Systems design gate** | `hooks/systems-design-gate.sh` | Blocks design-mode file edits without an active plan |
| **Product acceptance gate** *(Gen 5)* | `hooks/product-acceptance-gate.sh` | Stop hook position 4: blocks session end when an ACTIVE non-exempt plan lacks a runtime PASS artifact whose `plan_commit_sha` matches HEAD |
| **Narrative-integrity Stop hooks A1/A3/A5/A7** *(Gen 6)* | `hooks/{goal-coverage-on-stop,transcript-lie-detector,deferral-counter,imperative-evidence-linker}.sh` | Read `$TRANSCRIPT_PATH` JSONL (which the agent cannot edit) and force gaps between agent claims and transcript evidence into the user-visible final message |
| **Vaporware-volume gate A8** *(Gen 6)* | `hooks/vaporware-volume-gate.sh` | PreToolUse on `gh pr create`: blocks PRs with > 200 lines of describing files AND ZERO behavior-executing artifact files |
| **Scope-enforcement gate** *(Build Doctrine, redesigned)* | `hooks/scope-enforcement-gate.sh` | Blocks builder commits that touch files outside the active plan's `## Files to Modify/Create` OR `## In-flight scope updates` sections; three structural options replace the old waiver model |
| **PRD validity gate** *(Build Doctrine)* | `hooks/prd-validity-gate.sh` | Plan creation blocked when `prd-ref:` resolves to a missing-or-incomplete `docs/prd.md` |
| **Spec freeze gate** *(Build Doctrine)* | `hooks/spec-freeze-gate.sh` | Edit/Write on declared files blocked unless plan declares `frozen: true` |
| **Findings-ledger schema gate** *(Build Doctrine)* | `hooks/findings-ledger-schema-gate.sh` | Validates every `docs/findings.md` entry against the locked six-field schema on every commit |
| **Definition-on-first-use gate** *(Build Doctrine)* | `hooks/definition-on-first-use-gate.sh` | Blocks commits that introduce uppercase 2-6-char acronyms in doctrine docs without a glossary entry or in-diff parenthetical definition |
| **Discovery surfacer** *(Build Doctrine)* | `hooks/discovery-surfacer.sh` | SessionStart hook: scans `docs/discoveries/` for `Status: pending` and emits a system-reminder block for each |
| **Plan-status archival sweep** *(Build Doctrine)* | `hooks/plan-status-archival-sweep.sh` | SessionStart safety-net for terminal-Status flips that bypass `plan-lifecycle.sh` (e.g., Bash `sed`-based edits don't fire PostToolUse Edit/Write) |
| **Settings divergence detector** *(Build Doctrine)* | `hooks/settings-divergence-detector.sh` | SessionStart surfacing of hook-entry-count divergence between live `~/.claude/settings.json` and committed `settings.json.template` |
| **DAG review waiver gate** *(Build Doctrine)* | `hooks/dag-review-waiver-gate.sh` | Tier 3+ active plans require a substantive (>= 40 char) waiver before the first Task invocation in a session |

### From "Adversarial context separation" →

| Mechanism | File | What it does |
|---|---|---|
| **Task-verifier agent** | `agents/task-verifier.md` | Separate agent with sole authority to mark tasks complete; cannot modify code itself |
| **Plan-evidence-reviewer** | `agents/plan-evidence-reviewer.md` | Independent auditor of builder's evidence claims at tool-call-budget reset points |
| **Harness-reviewer** | `agents/harness-reviewer.md` | Adversarial review of any proposed harness change before commit |
| **Code-reviewer** | `agents/code-reviewer.md` | Independent review of code quality pre-commit |
| **Security-reviewer** | `agents/security-reviewer.md` | Adversarial security pass on diffs |
| **End-user-advocate** *(Gen 5)* | `agents/end-user-advocate.md` | Plan-time + runtime adversarial observation of the running product; the only agent whose verdict does NOT trust what the builder produced |
| **Comprehension-reviewer** *(Build Doctrine)* | `agents/comprehension-reviewer.md` | At plan rung >= 2, applies three-stage rubric (schema / substance / diff correspondence) to the builder's articulated mental model; FAIL or INCOMPLETE blocks the checkbox flip |
| **PRD-validity-reviewer** *(Build Doctrine)* | `agents/prd-validity-reviewer.md` | Substance review of the upstream PRD a plan claims to implement; pairs with `prd-validity-gate.sh` PreToolUse Write blocker |
| **UX testers** | `agents/ux-end-user-tester.md`, `domain-expert-tester.md`, `audience-content-reviewer.md` | Persona-based adversarial user testing |
| **Orchestrator pattern** | `rules/orchestrator-pattern.md` | Main session dispatches to `plan-phase-builder` sub-agents in isolated worktrees; main session stays lean as pure orchestrator |
| **Counter-Incentive Discipline** *(2026-05-03)* | Sections in `agents/{task-verifier,code-reviewer,plan-phase-builder,end-user-advocate}.md` | Explicit prompts priming each agent against its own training-induced bias toward call-it-done shortcuts (builders) or trust-the-builder-by-default (reviewers) |

### From "Ask, don't tell" →

| Mechanism | File | What it does |
|---|---|---|
| **Decision records** | `rules/planning.md` + `hooks/decisions-index-gate.sh` | Every Tier 2+ decision requires a `docs/decisions/NNN-slug.md` file atomic with the implementing commit — captures the "why" from the AI's own reasoning |
| **Completion reports** | `templates/completion-report.md` | Forces reflection on what was built, what was deferred, what was learned |
| **Session retrospectives** | `rules/planning.md` | At session end, review for correction patterns; propose rules from recurring corrections |
| **Feedback → hook encoding discipline** | Documented but not mechanically gated | Every corrected behavior should become either a rule, a hook, or a feedback memory |

---

## The Two Biggest Quality Levers

Two levers matter more than any others for implementation quality. They are complementary — using one without the other produces significantly worse results than using both.

### Lever 1: Maximum effort setting

The VS Code Claude Code extension exposes an `effort` setting that controls per-agent context budget. Default is medium/high. **Always set to `Extra High` at minimum, `Max` when quality is still insufficient.**

Why it matters: *"It actually provides more context window to every individual agent so that it doesn't feel the pressure of having to try and finish within before running out of context."* Higher effort directly relieves the pressure-to-complete bias that causes Claude to rush through details and ship buggy code. This setting is described in the source transcript as *"the key unlock"* of the current moment.

Practical impact: effort level is a setting the user must remember to configure per VS Code session. If the default is left in place, every other quality mechanism in the harness fights an uphill battle against an agent operating under artificial context pressure.

### Lever 2: Verbose plans

The maintainer identifies planning verbosity as *"the single biggest lever on implementation quality"* that doesn't require new harness work. The discipline:

### 1. Verbose plans produce good code; terse plans produce bugs

> *"If you give it a task, often times it'll come back with a plan and you look at the plan you're like okay the plan looks great and I'm able to put the pieces together in my head. But if I have to make those assumptions in my head Claude Code basically just whips right through them and it doesn't have good quality."*

If the reader has to fill in gaps, the builder will fill them in too — and worse. Every assumption must be explicit in the plan text.

### 2. Iterate on the plan before any code

The pattern: Claude drafts plan → the maintainer reads it → *"you missed some things here. We need to dig in deeper here. This needs to be more spelled out and detailed."* → Claude revises → repeat until plan is concrete enough that implementation is mechanical.

Even when the maintainer has no specific additions, he requests **more verbosity** generically: *"I need a lot of verbosity in the plan itself."* The plan triples in length; implementation quality tracks the expansion.

### 3. Adversarial plan review

Neural Lace's `systems-designer`, `ux-designer`, and `harness-reviewer` agents review plans before implementation. This catches gaps a single-perspective plan author misses.

### 4. Revisit plan, not code, when builds go wrong

> *"What I've found most effective without addressing the harness itself, but just guiding Claude properly, is to spend a lot more time on the planning."*

When implementation is buggy, the fix is usually upstream. Don't patch the build; revise the plan and rebuild.

---

## The Feedback Loop

The discipline that turns failures into harness improvements:

1. **Find a bug** (in code, in flow, in conversation).
2. **Ask Claude why the system allowed it.** *"Why did Claude Code allow these bugs to exist? What in the system allowed these bugs to exist? Why didn't it catch these to begin with?"*
3. **Ask Claude how to prevent the class.** *"How could we have done this better? How can we take those lessons learned and build those back into the harness?"*
4. **Encode the prevention.** Turn the lesson into a new hook, agent prompt, rule file, or template field.
5. **Repeat indefinitely.** The harness grows teeth over time.

> *"Let's go build these back into the harness so that we don't have these problems again."*

This is already reflected in the "After Every Failure: Encode the Fix" section of `rules/diagnosis.md`. It is the single most important ongoing practice for improving quality over time.

### Post-task bug hunts

After Claude says something is done, the maintainer explicitly follows up with *"now that it should finish I need you to go back and find every bug that came up."* Claude produces honest lists — *"Here are the mistakes that I made very explicitly. I did exactly the thing you told me not to do. Here's exactly where I did it."*

Codify this pattern as a standing practice: the final turn of any significant build should include an explicit self-audit prompt.

---

## Concrete Patterns in Daily Use

### Session effort settings

- Default to `extra high` at minimum
- Use `max` when quality is still insufficient
- Low effort is never correct for significant work

### Prompt shapes that work

- **"Ask, don't tell"** — *"What could we have done better?"* > *"Fix this bug."*
- **"Find my bugs"** — *"Go back and find every bug that came up."*
- **"Explain what allowed this"** — for any surprise, surface the root cause before the fix
- **"More verbosity"** — blanket request when plans feel thin

### Anti-patterns to avoid

- **Token thrift.** Rebuild loops cost more than verbose plans. *"I'm honestly not concerned about [tokens] because if it goes and builds and then I go and find bugs and have to go back and rebuild things repeatedly, then we're wasting a lot of tokens on the back and forth."*
- **Trusting shared-context validation.** Builder checking builder's work = blind spots preserved.
- **Filling plan gaps in your head.** If you're making assumptions Claude didn't state, Claude will skip them too.
- **Letting Claude fabricate logic.** For simulators, test harnesses, anything that exposes internal logic — *"Do not generate your own logic for the simulator. I want to use the real world logic."* Claude will gladly invent plausible-looking fake logic if not constrained.
- **Staying in build mode when quality drops.** Step back to systems-engineering mode and fix the harness.
- **Process for its own sake.** Verification friction has a ceiling; bulk that prevents bugs is worth carrying, bulk that's theatrical isn't.

### Tools/surfaces actively leveraged

- Neural Lace harness (`~/.claude/` + neural-lace repo)
- Claude Code VS Code extension (effort dropdown, mode toggles)
- Plan files + evidence files + decisions records (all in-repo, durable artifacts)
- Sub-agents with `isolation: "worktree"` for parallelism
- Documentation-as-you-build (the harness auto-generates docs so humans read docs, not code)
- `claude --remote` for background autonomous work (per ongoing exploration — see "Multi-session management" below)

---

## Automating Best Practices — Removing the Need for User Discipline

The strategy above assumes the user remembers to do things. That's fragile. The long-term goal is to **make every best practice automatic** — enforced by default rather than memorized. This section maps each best practice to its current automation status and the specific mechanism that would complete the automation.

The tension this resolves: users shouldn't need to know Claude Code's internals to get quality output. The harness should make the path of least resistance the path of highest quality.

### Best Practice → Automation Mechanism

| Best Practice | Currently Requires | Proposed Automation |
|---|---|---|
| **Effort setting at Extra High / Max** | User must configure in VS Code dropdown every session | (1) SessionStart hook reads `~/.claude/local/effort-policy.json` and warns if effort is below configured minimum. (2) Per-project `.claude/minimum-effort.json` declares project-level minimum. (3) Stretch: hook could query Claude Code's current effort setting via an introspection API if one exists. |
| **Verbose plans** | User must request "more detail" iteratively | (1) Plan-reviewer agent automatically rejects plans below a complexity threshold (line count, section count, enumerated assumptions). (2) Adversarial pre-mortem agent (backlog P1) automatically runs on every draft plan and returns a list of gaps to fill. (3) Plan template with required sections (Assumptions, Edge Cases, Files Modified, Testing Strategy) that must be populated. |
| **Immediate commit of new plans** | User must remember to commit | `plan-lifecycle.sh` PostToolUse hook (planned in a project-level plan, `robust-plan-file-lifecycle`) detects a new plan file and surfaces a loud reminder; pre-stop-verifier warns on uncommitted plans at session end. |
| **Auto-archival on status transition** | User must manually move plans to archive | Same `plan-lifecycle.sh` hook: when `Status:` changes to COMPLETED/DEFERRED/ABANDONED/SUPERSEDED, auto-executes `git mv` to `docs/plans/archive/`. |
| **Meta-questions after significant work** | User must remember to ask | (1) Prompt template library as slash commands (`/why-did-this-bug-slip`, `/find-my-bugs`, `/harness-this-lesson`) — codifies the discipline into one-keystroke invocations. (2) Post-completion hook that automatically prompts the agent to self-audit on significant plan completions. |
| **Adversarial validation** | User must dispatch validator agents | (1) `task-verifier` mandate (already hook-enforced) — only this agent can flip plan checkboxes, forcing the builder to invoke it. (2) Pre-commit hook dispatches `code-reviewer` / `security-reviewer` automatically based on file types changed. (3) Plan-reviewer runs on every new plan automatically. |
| **Encode failures as new hooks/rules** | User must consciously run the capture-codify cycle | (1) PR template field (backlog P1): every fix PR requires "what rule/hook/agent would have caught this?" — empty = PR blocked. (2) Scheduled weekly retrospective agent (backlog P2) reviews failures and drafts proposed hook changes. |
| **Bug persistence to backlog** | User must add bugs to backlog.md | `bug-persistence-gate.sh` Stop hook (already shipped) scans transcript for trigger phrases and blocks session end if no persistence happened. |
| **Credential scanning** | User must avoid committing secrets | `pre-commit` + `pre-push` hooks (already shipped) block any commit matching denylisted credential patterns. |
| **Test coverage for runtime files** | User must write tests | `pre-commit-tdd-gate.sh` (already shipped, 5 layers) rejects commits that add runtime code without tests, use mocks in integration tests, or rely on trivial assertions. |
| **Plan checkboxes backed by evidence** | User must run task-verifier | `plan-edit-validator.sh` (already shipped) blocks checkbox flips without fresh evidence file within 120s. |
| **Runtime verification for completed tasks** | User must run verification commands | `runtime-verification-executor.sh` + `pre-stop-verifier.sh` (already shipped) parse verification entries and execute them at session end. |
| **Background autonomous work without collisions** | User must manage worktrees or remote sessions | Adopt `claude --remote` + dotfiles sync as the canonical pattern (backlog P0). Document in `rules/automation-modes.md` so it's the default answer when a user asks "how do I run this overnight." |
| **Context hygiene on long plans** | User must use orchestrator pattern voluntarily | `tool-call-budget.sh` (already shipped) blocks every 30 Edit/Write/Bash calls without a `plan-evidence-reviewer` audit — indirectly pressures toward dispatch-based work. |

### The Automation Maturity Model

Every best practice sits on a maturity ladder. The goal is moving each practice up the ladder over time:

**Level 0 — Verbal/aspirational.** Best practice exists in someone's head or in a rule file nobody reads.

**Level 1 — Documented prose.** Best practice is in `CLAUDE.md` or `rules/*.md`. Agent reads it and usually complies, sometimes forgets.

**Level 2 — Reminder hook.** A hook surfaces a warning when the practice is being violated. Non-blocking. Relies on agent noticing and responding.

**Level 3 — Blocking hook.** A hook refuses to proceed when the practice is violated. Agent cannot continue until it complies. This is where the practice becomes automatic.

**Level 4 — Default by construction.** The practice is structurally impossible to violate — the system is designed such that the non-compliant path doesn't exist. Example: the task-verifier mandate makes self-flipping checkboxes impossible because the hook blocks all plan edits that aren't preceded by an evidence file.

**Current positions (partial):**

| Practice | Level | Path to next level |
|---|---|---|
| Effort setting | Level 0 | SessionStart warning hook → Level 2 |
| Verbose plans | Level 1 | Plan-reviewer rejection threshold → Level 3 |
| Commit plans immediately | Level 1 | `plan-lifecycle.sh` reminder hook → Level 2 (planned) |
| Auto-archival | Level 1 | `plan-lifecycle.sh` auto-execution → Level 4 (planned) |
| Meta-questions | Level 0 | Slash command library → Level 2 |
| Adversarial validation | Level 3 (via task-verifier) | Already mature for plan work; extend to code review → Level 3 |
| Bug persistence | Level 3 | Already shipped |
| Credential scanning | Level 3 | Already shipped |
| TDD for runtime files | Level 3 | Already shipped |
| Evidence-first checkbox flips | Level 4 | Already shipped (blocking hook + mandate) |
| Runtime verification | Level 3 | Already shipped |

### Principle: Every Best Practice Has a Level Target

When documenting a best practice, declare which maturity level it should reach. Practices critical to quality (e.g., max effort, verbose plans) target Level 3 or 4. Practices that are nice-to-have but not load-bearing can stay at Level 2. Explicitly declaring the target prevents drift where a critical practice stays at Level 1 forever because "we documented it."

When a practice causes repeated failures despite being documented, that's the signal to move it up the ladder — either by adding a reminder hook (Level 2), a blocking hook (Level 3), or restructuring the system to make violation impossible (Level 4).

---

## Known Gaps and Residual Risks

The harness is honest about what it can't enforce. Knowing the gaps is part of the strategy.

### 1. Verbal vaporware in conversation — narrowed but not closed (Gen 6 partial)

Claude Code has no PostMessage hook. The `claim-reviewer` agent is self-invoked and can be skipped. **Gen 6 narrowed this gap substantially:** A1 (`goal-coverage-on-stop.sh`) checks the user's verbatim first message against tool-call evidence; A3 (`transcript-lie-detector.sh`) catches completion-class claims contradicted by deferral-class claims in the same session; A5 (`deferral-counter.sh`) forces deferred work into the user-visible final message; A7 (`imperative-evidence-linker.sh`) catches silently-skipped user imperatives. These hooks read `$TRANSCRIPT_PATH` JSONL — which the agent cannot edit — so the integrity is tamper-proof.

**Residual gap:** mid-session uncited feature claims (e.g., "X is wired up" with no file:line) still aren't caught at the moment of the claim — the Gen 6 hooks fire at session end, not on every assistant message. Closing this fully requires a PostMessage hook event that Claude Code does not currently emit.

**Mitigation:** Gen 6 hooks at session end + `claim-reviewer` agent self-invoked + user reflex to ask for file:line citations on any feature claim. Reviewer-accountability tracker (HARNESS-GAP-11) is the structural follow-up gated on telemetry.

### 2. Tool-call-budget `--ack` bypass

The hook looks for sentinel lines in a review file under `~/.claude/state/reviews/`. A builder could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed.

**Mitigation:** accepted residual risk for Gen 4. Closing requires either HMAC signing or Claude Code architectural support for observing Task-tool invocations.

### 3. Concurrent-session state collisions

Multiple Claude Code sessions on the same machine share `~/.claude/` state (memory, SCRATCHPAD, tool-call budgets). They also share the git working tree, leading to uncommitted-file wipes — this failure mode has been observed repeatedly in practice, with uncommitted plan files lost when concurrent sessions run `git stash` or `git clean` operations.

**Mitigation:** `claude --remote` for autonomous work (isolated cloud sandboxes); the `plan-lifecycle.sh` PostToolUse uncommitted-plan warning emits whenever an edit lands on an uncommitted plan; `pre-stop-verifier.sh` flags uncommitted plans at session end. **Open follow-up:** the multi-active-plan stranding discovery (`docs/discoveries/2026-05-05-multi-active-plan-stranding.md`) is pending decision — should a SessionStart hook surface ALL `Status: ACTIVE` plans (not just the most-recently-edited) with a warning when count > 1?

### 4. Plan-closure discipline — open gap (HARNESS-GAP-16)

The harness has multiple Pattern-level rules requiring closure bookkeeping (verifier mandate, "update status documents when work completes", planning.md's plan-completion checklist) but no Mechanism that REFUSES the irreversible Status: COMPLETED transition until closure is mechanically complete. Sessions can flip Status without checking all bases (all task checkboxes flipped, evidence blocks present with PASS, completion report populated, backlog reconciled, SCRATCHPAD updated), and once flipped + auto-archived, the audit trail is in a final state regardless of whether bookkeeping was done. Surfaced from the 2026-05-05 stranding incident where `pre-submission-audit-mechanical-enforcement.md` sat ACTIVE since 2026-05-03 with all 5 task checkboxes empty despite all 5 tasks' code work shipped on master.

**Proposed mechanism (HARNESS-GAP-16, ~4-5 hr).** Layer 1: extend `plan-lifecycle.sh` with closure-validation gate that runs mechanical checks BEFORE the auto-archive on Status: ACTIVE → COMPLETED transition (all checkboxes `[x]`, evidence blocks with PASS verdict per task ID, completion report populated, backlog absorbed-items reconciled, SCRATCHPAD mtime fresh and mentions plan slug). Layer 2: `/close-plan <slug>` skill that walks the orchestrator through closure mechanically and makes the right path easier than the wrong path. Layer 3 (already landed): `feedback_complete_plan_bookkeeping_in_session.md` memory — behavioral reinforcement only.

**Mitigation today:** Pattern-level rules + the auto-memory feedback entry. The mechanism is scheduled next-after HARNESS-GAP-13 ships.

### 4. Harness-portability to cloud sessions — RESOLVED (2026-04-23)

Cloud-hosted Claude Code sessions don't inherit the user's local `~/.claude/` config — Phase A research (`docs/plans/archive/claude-remote-adoption-evidence.md`) confirmed that `claude --remote` cloud VMs read ONLY the project's `.claude/` directory after cloning the repo, never the user-level `~/.claude/`.

**Resolution:** Decision 011 (`docs/decisions/011-claude-remote-harness-approach.md`) adopts a hybrid approach with three complementary mechanisms:

1. **Primary — Approach A (commit harness into project `.claude/`):** each downstream project's `.claude/` either symlinks to `~/claude-projects/neural-lace/adapters/claude-code/` (solo-dev local convenience) or contains a committed copy (team-shared / cloud-portable). Cloud sessions inherit the harness automatically via the repo clone. This is the only mechanism that gives cloud sessions full harness enforcement.
2. **Augmentation — Routines via `/schedule`:** scheduled / event-triggered cloud automation that inherits the same project `.claude/` as `--remote` does. Daily quota: 5/Pro, 15/Max, 25/Team-Enterprise.
3. **Optional layer — DevContainers:** for interactive multi-session local dev where the shared-`~/.claude/` collision risk in worktree-based parallelism (`rules/orchestrator-pattern.md`) is unacceptable. Per-project opt-in; adds Docker as a dependency.

The mode-by-mode operator-facing decision tree lives in `rules/automation-modes.md`. Phase A research deferred live empirical validation of cloud harness inheritance to a P2 backlog item — first real cloud-session build in a downstream project with Approach A adopted will confirm the inheritance behavior end-to-end. Approach A's known caveat: solo-dev symlinks may or may not traverse the CLI's repo-bundle mechanism cleanly; if symlinks don't travel, the committed-copy alternative is the fallback.

Alternatives B (cloud-session startup script that clones neural-lace) and C (restricted task class for cloud sessions) were both considered and rejected — see Decision 011 for the per-alternative rejection reasoning.

---

## Additional Suggestions for Improvement

Beyond what's already documented or in flight, these are opportunities to extend the strategy further. Presented in rough order of leverage.

### A. Harness-tests-itself: synthetic session runner

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them. Examples:

- A session that tries to flip a plan checkbox without evidence → should be blocked by `plan-edit-validator.sh`
- A session that writes an integration test with mocks → should be blocked by `pre-commit-tdd-gate.sh`
- A session that claims a feature exists without citing file:line → should be flagged by `claim-reviewer`
- A session that exhausts its tool-call budget without audit → should be blocked by `tool-call-budget.sh`

Runs on demand (or weekly via `/schedule`). Produces a report showing which enforcement mechanisms are still effective and which have regressed.

**Why:** Currently, harness correctness is verified manually when something breaks. A synthetic-session runner would catch silent regressions in enforcement, similar to how a project's planned customer-journey-test-harness tests conversations. It's the same pattern applied to the harness itself.

### B. Failure mode catalog as a first-class artifact

Maintain `~/.claude/docs/failure-modes.md` as a living document. Each entry:

- **Symptom:** what you observe going wrong
- **Root cause:** why the system allowed it
- **Detection:** which hook/agent/rule catches it, or "undetected" if residual
- **Prevention:** the mechanism (existing or proposed)
- **Example:** a real incident where this fired (or slipped)

Makes the "every bug → harness opportunity" discipline systematic rather than oral tradition. Also serves as onboarding material for new engineers joining the harness.

**Why:** The feedback loop currently depends on the maintainer remembering every past failure. A catalog externalizes that memory, making it shareable and more durable than a single person's recall.

### C. Adversarial pre-mortem pattern for plans

Before any plan is marked ready to build, an adversarial agent asks: *"If the builder's only input is this plan, what will they get wrong?"* The agent produces a list of expected failure modes. The plan is revised to close each one.

This is "verbose plans" with teeth — instead of relying on the human to notice gaps, an agent whose job is to find gaps runs systematically.

**Why:** Humans approve plans that look plausible. An adversarial agent with a "find the holes" mandate catches things humans miss at plan-review time, which is 10x cheaper than catching them at implementation time.

### D. Delegability classification on plan tasks

Every plan task declares one of:

- **Fully delegable** — mechanical work with clear acceptance criteria (migrations, refactors, tests)
- **Review-at-phase** — autonomous build with human review at phase boundary
- **Interactive** — requires ongoing human judgment (taste decisions, UX, copy)

The classification shapes execution: fully-delegable tasks auto-dispatch to background sessions; review-at-phase tasks produce PRs at phase end; interactive tasks stay in the foreground session.

**Why:** The current model forces the user to decide per-task how much to watch. Declaring delegability at plan time lets the dispatch layer handle routing automatically.

### E. Prompt template library for reusable meta-questions

Codify the maintainer's canonical meta-questions as slash commands or skills:

- `/why-did-this-bug-slip` — runs the "what allowed this" interrogation
- `/find-my-bugs` — post-completion self-audit prompt
- `/make-this-plan-verbose` — requests expansion of thin plans
- `/harness-this-lesson` — takes a recent failure and proposes hook/rule/agent changes

**Why:** These patterns currently live in the maintainer's head. Codifying them makes them reusable for any engineer on the harness, and makes them consistent across sessions.

### F. Effort-level enforcement at project level

Projects that require high quality should declare a minimum effort level. The harness enforces it on session start — warns if effort is below project minimum, requires explicit acknowledgment to proceed.

Stored as `.claude/minimum-effort.json` in the project root. Sessions read it at SessionStart.

**Why:** Effort level is currently a per-session decision the user must remember. For projects where quality matters, making it a project-level policy eliminates a class of "forgot to set max" errors.

### G. Multi-model routing strategy

Different models have different strengths. Codify where each is used:

- **Opus** for planning, architecture decisions, adversarial review, consequence/outcome reasoning
- **Sonnet** for implementation, refactoring, mechanical code generation
- **Haiku** for small, fast operations — renaming, linting, formatting-only changes

The harness can route automatically based on task type: plans use Opus, sub-agent implementations use Sonnet, simple operations use Haiku. Already partially handled (the `research` agent specifies Sonnet; `harness-reviewer` specifies Opus), but could be more systematic.

**Why:** Matches model strengths to task requirements. Reduces cost on mechanical work; ensures judgment tasks get the strongest model.

### H. Capture-codify cycle formalized at PR level

Every fix PR has a required description field: *"What rule/hook/agent would have caught this?"*

- If a specific mechanism would have caught it → link to it (confirms enforcement is working)
- If no mechanism would have caught it → propose one, or explicitly accept residual risk

Empty field = PR is blocked.

**Why:** Makes the "every failure is a harness opportunity" discipline structurally mandatory rather than aspirational. The PR template becomes the forcing function.

### I. Session observability dashboard

A lightweight command (`claude-status` or similar) that shows:

- Active Claude Code sessions (local + remote via `--remote`)
- Active plans per session (with status + progress)
- Tool-call budget consumption per session
- Recent hook firings (last N, by category)
- Stashed/uncommitted work at risk of concurrent-session wipe

Doesn't require new infrastructure — just aggregates existing state files under `~/.claude/state/` and `docs/plans/`.

**Why:** Currently, understanding the state of your sessions requires poking through multiple directories and files. A single-command view surfaces risks (e.g., uncommitted plans) before they bite.

### J. Harness version contracts

As the harness evolves, projects that depend on specific hook behaviors may break silently when the harness is updated. Declaring compatibility explicitly prevents this:

- Each project's CLAUDE.md declares `harness-version: >=N`
- Harness updates that are breaking bump a version number
- SessionStart warns if project version predates current harness

**Why:** Neural Lace is evolving quickly. Projects using it for months accumulate dependencies on specific behavior. Without version contracts, a harness improvement can silently degrade an older project's quality.

### K. Scheduled retrospectives via `/schedule`

A weekly scheduled agent that:

1. Reads the week's completed plans + decision records + failure-mode catalog entries
2. Proposes harness improvements based on patterns observed
3. Drafts a retrospective document under `~/.claude/docs/retrospectives/YYYY-WW.md`
4. Sends a push notification on completion

Turns the maintainer's informal "half my time on harness work" into systematic weekly attention.

**Why:** The capture-codify cycle only works if someone actively reviews what happened. Making it scheduled ensures it happens; making it AI-assisted reduces the friction to a manageable review-and-approve.

### L. Explicit "interactive vs autonomous" session mode

A session-start directive that declares whether the session is:

- **Interactive** — human is watching; prompts for confirmation on Tier 2+ actions
- **Autonomous** — human is not watching; maximum harness enforcement, stricter gates, auto-commit plan files

Affects hook behavior: interactive mode can be more permissive because the human is the fallback; autonomous mode cannot rely on human oversight and must lean harder on mechanical enforcement.

**Why:** The same session cadence shouldn't apply to both modes. A user running `claude --remote` overnight wants different gates than a user watching edits in real time. Making the mode explicit lets the harness adapt.

### M. Adopt `claude --remote` + project-`.claude/` harness as the official background-work pattern — SHIPPED (2026-04-23)

Per Decision 011 (`docs/decisions/011-claude-remote-harness-approach.md`) and the `rules/automation-modes.md` rule shipped in plan #4, the canonical session-mode tree is:

- **Interactive work** → Mode 1 (local Claude Code, full `~/.claude/` enforcement)
- **Parallel local autonomous work** → Mode 2 (worktrees via Desktop "+ New session" or `isolation: "worktree"`)
- **Unattended autonomous background work** → Mode 3 (`claude --remote` with project `.claude/` populated per Decision 011 Approach A)
- **Recurring work** → Mode 4 (`/schedule` Routines, same harness inheritance as Mode 3)

The "dotfiles-synced harness" framing from the original suggestion was superseded by Approach A (commit harness into project `.claude/`) after Phase A research confirmed that cloud sessions inherit the cloned repo's `.claude/` directly without needing a separate dotfiles-sync mechanism.

**Why:** Solves the concurrent-session problem cleanly with official tooling. Eliminates the edge case that has cost us plan files in the past, and gives cloud sessions full harness enforcement via the repo-clone path.

---

## Summary: The Strategy in Five Sentences

1. **Quality over speed** means the two biggest levers are maxed effort setting AND verbose plans — both levers used together, not either alone — plus long-build acceptance and token indifference.
2. **Determinism via mechanism AND prompt** means every rule that matters has both a prose description (so the agent follows it most of the time) and a hook (so violations are mechanically blocked when the agent drifts).
3. **Adversarial separation** means builders don't validate their own work; different agents with different goals do.
4. **Ask, don't tell** means every failure becomes a prompt to understand the failure mode, not just a patch.
5. **Encode every lesson** means the harness grows teeth over time; today's bug is tomorrow's blocked-at-commit-time violation.

The harness is how these principles get enforced without human discipline. The discipline that remains — planning verbosity, meta-questions, SRE-style oscillation — is what the human contributes. The goal over time is to automate even this residual discipline, so that best practices are invoked by default rather than memorized.

The Build Doctrine integration arc (May 2026) extends this with proactive mechanisms — capture-and-decide for mid-process learnings (Discovery Protocol) and articulate-before-checkbox-flip for R2+ tasks (comprehension gate) — beyond the reactive failure-correction loop the prior generations focused on.

---

## References

**Source transcripts:** 2026-04-22 strategy discussion between the harness maintainer and a collaborating engineer; Build Doctrine integration arc decisions 013-024 (May 2026).

**Neural Lace structural docs:**
- `README.md` — architectural overview
- `SETUP.md` — installation + customization
- `docs/harness-strategy.md` — vision + roadmap
- `docs/best-practices.md` — 30+ encoded practices (including Build Doctrine extensions)
- `docs/harness-architecture.md` — Gen 4-6 + Build Doctrine enforcement map
- `principles/` — tool-agnostic philosophy (core-values, permission-model, progressive-autonomy, evaluation-discipline, security-posture, harness-hygiene, ux-philosophy, diagnosis-protocol, forward-compatibility)
- `patterns/` — tool-family-agnostic patterns (hooks, pipelines, agents)
- `docs/decisions/` — Tier 2+ decision records, including:
  - 011 (claude --remote harness approach) — cloud-mode inheritance via project `.claude/`
  - 012 (Agent Teams integration) — feature-flagged five-mode framework
  - 013 (default push policy) — auto-push safe methods
  - 014 (calibration mimicry design) — telemetry-gated reviewer-accountability
  - 015-018 (PRD validity, spec freeze, plan-header schema, scratchpad divergence)
  - 019 (findings ledger format)
  - 020 (comprehension gate semantics)
  - 021 (DRIFT-02 account-switch config-driven)
  - 022 (pipeline-agents.md deletion)
  - 023 (definition-on-first-use enforcement)
  - 024 (GAP-14 reconciliation)
- `adapters/claude-code/` — Claude Code-specific implementation

**Key Neural Lace artifacts:**
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement authority
- `adapters/claude-code/rules/orchestrator-pattern.md` — multi-task delegation
- `adapters/claude-code/rules/planning.md` — plan lifecycle
- `adapters/claude-code/agents/task-verifier.md` — evidence-first verification
- `adapters/claude-code/hooks/*.sh` — 23+ enforcement hooks
