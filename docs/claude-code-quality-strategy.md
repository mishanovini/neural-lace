# Getting Quality Out of Claude Code — Strategy and Harness Design

**Last updated:** 2026-04-22
**Source material:** Transcript of a 2026-04-22 strategy discussion between the harness maintainer and a collaborating engineer; Neural Lace harness design docs.

This document codifies the strategy the maintainer has developed for extracting maximum quality from Claude Code, and maps each principle to its concrete manifestation in the Neural Lace harness. It exists so the strategy is legible to (a) the maintainer in future sessions, (b) collaborating engineers working with the harness, and (c) anyone who adopts Neural Lace externally and wants to understand the "why" behind its choices.

---

## Core Philosophy

Four beliefs underpin the entire strategy. Every mechanism in Neural Lace traces back to one of these.

### 1. Quality beats speed at every time scale

> *"If it takes 24 hours to build instead of two hours, but it finishes and it's like solid, I will take that."*

Claude Code's default posture is to favor performance over quality — what the maintainer calls its *"pressure to complete."* Rebuild cycles from shipping buggy code consume more tokens, more time, and more trust than longer upfront builds. The correct trade-off is always in favor of quality.

**Operational implication:** the `effort` setting should be set to `extra high` at minimum, `max` when quality still suffers. The setting *"actually provides more context window to every individual agent so that it doesn't feel the pressure of having to try and finish within before running out of context."* It directly relieves the quality-destroying pressure-to-complete bias.

### 2. Determinism requires mechanism, not prompt

> *"Context and prompts are not perfect… it's guidance but it's not deterministic. So the one deterministic thing that we can do to keep things on track is to create hooks."*

Prompts are probabilistic. Claude will sometimes acknowledge a directive and then quietly work around it — *"Cloud Code tends to sometimes be like hey I have direction to do things this way but when things come down to it I still tend to work around them."* Rules written in prose are guidance; rules written as hooks are physics.

**Operational implication:** any rule that matters must have a hook that enforces it. Prose rules are starting points, not endpoints. If you catch a bug class that a prose rule should have prevented, the next step is always "build the hook that makes this class impossible."

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
| **Bug persistence gate** | `hooks/bug-persistence-gate.sh` | Scans transcript for bug-trigger phrases ("we should also", "known issue"); blocks if no persistence happened |
| **Systems design gate** | `hooks/systems-design-gate.sh` | Blocks design-mode file edits without an active plan |

### From "Adversarial context separation" →

| Mechanism | File | What it does |
|---|---|---|
| **Task-verifier agent** | `agents/task-verifier.md` | Separate agent with sole authority to mark tasks complete; cannot modify code itself |
| **Plan-evidence-reviewer** | `agents/plan-evidence-reviewer.md` | Independent auditor of builder's evidence claims at tool-call-budget reset points |
| **Harness-reviewer** | `agents/harness-reviewer.md` | Adversarial review of any proposed harness change before commit |
| **Code-reviewer** | `agents/code-reviewer.md` | Independent review of code quality pre-commit |
| **Security-reviewer** | `agents/security-reviewer.md` | Adversarial security pass on diffs |
| **UX testers** | `agents/ux-end-user-tester.md`, `domain-expert-tester.md`, `audience-content-reviewer.md` | Persona-based adversarial user testing |
| **Orchestrator pattern** | `rules/orchestrator-pattern.md` | Main session dispatches to `plan-phase-builder` sub-agents in isolated worktrees; main session stays lean as pure orchestrator |

### From "Ask, don't tell" →

| Mechanism | File | What it does |
|---|---|---|
| **Decision records** | `rules/planning.md` + `hooks/decisions-index-gate.sh` | Every Tier 2+ decision requires a `docs/decisions/NNN-slug.md` file atomic with the implementing commit — captures the "why" from the AI's own reasoning |
| **Completion reports** | `templates/completion-report.md` | Forces reflection on what was built, what was deferred, what was learned |
| **Session retrospectives** | `rules/planning.md` | At session end, review for correction patterns; propose rules from recurring corrections |
| **Feedback → hook encoding discipline** | Documented but not mechanically gated | Every corrected behavior should become either a rule, a hook, or a feedback memory |

---

## The Planning Discipline

the maintainer identifies planning as *"the single biggest lever on implementation quality"* that doesn't require new harness work. The discipline:

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

## Known Gaps and Residual Risks

The harness is honest about what it can't enforce. Knowing the gaps is part of the strategy.

### 1. Verbal vaporware in conversation

Claude Code has no PostMessage hook. The `claim-reviewer` agent is self-invoked and can be skipped. The user retains interrupt authority when they see an uncited claim, but mechanical enforcement doesn't exist.

**Mitigation:** train the reflex to ask for file:line citations on any claim of feature existence.

### 2. Tool-call-budget `--ack` bypass

The hook looks for sentinel lines in a review file under `~/.claude/state/reviews/`. A builder could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed.

**Mitigation:** accepted residual risk for Gen 4. Closing requires either HMAC signing or Claude Code architectural support for observing Task-tool invocations.

### 3. Concurrent-session state collisions

Multiple Claude Code sessions on the same machine share `~/.claude/` state (memory, SCRATCHPAD, tool-call budgets). They also share the git working tree, leading to uncommitted-file wipes — this failure mode has been observed repeatedly in practice, with uncommitted plan files lost when concurrent sessions run `git stash` or `git clean` operations.

**Mitigation:** `claude --remote` for autonomous work (isolated cloud sandboxes); the `robust-plan-file-lifecycle` plan for commit-on-creation protection.

### 4. Harness-portability to cloud sessions

Cloud-hosted Claude Code sessions don't inherit the user's local `~/.claude/` config unless it's synced via dotfiles or checked into the project. This is an unresolved tension between isolation (cloud wins) and enforcement (local harness wins).

**Mitigation in progress:** investigate Claude Code Web's harness provisioning and Codespaces-style dotfile sync.

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

### M. Adopt `claude --remote` + dotfiles sync as the official background-work pattern

Based on the `claude-code-guide` agent's research, `claude --remote` is Anthropic's purpose-built solution for concurrent autonomous sessions. Establish this as the canonical pattern:

- **Interactive work** → local Claude Code, watching IDE
- **Autonomous background work** → `claude --remote` with dotfiles-synced harness
- **Recurring work** → `/schedule`

Document this in `rules/automation-modes.md` with concrete examples. Resolves the concurrent-session plan-wipe incidents without requiring worktree infrastructure.

**Why:** Solves the concurrent-session problem cleanly with official tooling. Eliminates the edge case that has cost us two plan files already.

---

## Summary: The Strategy in Five Sentences

1. **Quality over speed** means max effort, verbose plans, long builds, and token indifference.
2. **Determinism via mechanism** means every rule that matters becomes a hook; prose rules are aspirational.
3. **Adversarial separation** means builders don't validate their own work; different agents with different goals do.
4. **Ask, don't tell** means every failure becomes a prompt to understand the failure mode, not just a patch.
5. **Encode every lesson** means the harness grows teeth over time; today's bug is tomorrow's blocked-at-commit-time violation.

The harness is how these principles get enforced without human discipline. The discipline that remains — planning verbosity, meta-questions, SRE-style oscillation — is what the human contributes.

---

## References

**Source transcript:** 2026-04-22 strategy discussion between the harness maintainer and a collaborating engineer.

**Neural Lace structural docs:**
- `README.md` — architectural overview
- `SETUP.md` — installation + customization
- `docs/harness-strategy.md` — vision + roadmap
- `docs/best-practices.md` — 25+ encoded practices
- `docs/harness-architecture.md` — Gen 4 enforcement map
- `principles/` — tool-agnostic philosophy (core-values, permission-model, progressive-autonomy, evaluation-discipline, security-posture, harness-hygiene, ux-philosophy, diagnosis-protocol, forward-compatibility)
- `patterns/` — tool-family-agnostic patterns (hooks, pipelines, agents)
- `adapters/claude-code/` — Claude Code-specific implementation

**Key Neural Lace artifacts:**
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement authority
- `adapters/claude-code/rules/orchestrator-pattern.md` — multi-task delegation
- `adapters/claude-code/rules/planning.md` — plan lifecycle
- `adapters/claude-code/agents/task-verifier.md` — evidence-first verification
- `adapters/claude-code/hooks/*.sh` — 23+ enforcement hooks
