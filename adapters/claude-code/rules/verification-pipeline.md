# Verification Pipeline — Four-Agent Sequence Before Task Completion

**Classification:** Hybrid. The pipeline order (which agent fires when, in what sequence, with what blocking semantics) is a Pattern the orchestrator and task-verifier self-apply. The single Mechanism backing the pipeline is `task-verifier`'s requirement of `functionality-verifier` evidence (or harness-self self-test PASS) before flipping the checkbox on a `Verification: full` runtime task. The other three steps (end-user-advocate runtime, claim-reviewer, domain-expert-tester) compose by Pattern and have their own enforcement substrates documented in their per-agent prompts and per-rule files; this rule does NOT introduce a single PreToolUse hook that fires all four steps. Each step retains its existing trigger and lifecycle position.

**Ships with:** the `functionality-verifier` agent introduced in this rule's parent plan (`docs/plans/functionality-verification-pipeline.md`).

## Why this rule exists

The harness has accumulated a stack of mechanisms that gate on what was WRITTEN: `pre-commit-tdd-gate.sh` checks tests exist; `plan-edit-validator.sh` enforces evidence-first checkbox flips; `runtime-verification-reviewer.sh` cross-checks runtime-verification correspondence; `wire-check-gate.sh` validates the declared code chain; `plan-reviewer.sh` Check 13 enforces integration-verification sub-blocks at plan-time; `task-verifier` reads the evidence block and replays the runtime-verification command.

Every one of those mechanisms verifies the written artifact. None of them, by itself, verifies that the FEATURE WORKS when a user takes the path that should produce the outcome.

The repeated failure mode this gap produces: builders ship code that compiles cleanly, passes unit tests, satisfies wire-checks, and even produces a `Runtime verification: test src/foo.test.ts::happy-path` line that replays green — while clicking the button on the live page does nothing because the click handler is bound to an old handler reference, or because the form submits to the right endpoint but the listing page reads from a different source, or because the AI returns a response but the response doesn't contain what the task said it would.

The pipeline closes this gap by composing four agents in sequence. Each has a distinct role:

1. **`functionality-verifier`** USES the feature. Does the user-shaped exercise produce the user-shaped outcome? PASS/FAIL/INCOMPLETE per-task.
2. **`end-user-advocate`** (runtime mode) is the harness's adversarial product observer at session end. Replays the plan's full `## Acceptance Scenarios` set against the live app with adversarial probes.
3. **`claim-reviewer`** independently verifies the session's completion claims. Cross-checks every "X is done" / "we have Y" / "the system does Z" against the actual codebase and the actual evidence.
4. **`domain-expert-tester`** becomes the project's target persona and evaluates whether the work makes sense to that user. For UI work, this is the audience-aware UX check. For non-UI work, this is the "would the maintainer running this artifact know what to do" check.

This rule documents the pipeline. The agents themselves are documented in their per-agent files; the cross-references at the bottom of this rule point at each.

## The pipeline in one diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  Builder completes the task                                         │
│  (plan-phase-builder returns DONE; commit landed)                   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  1. functionality-verifier (NEW)  — fires per-task                  │
│     Be the user. Use the feature. Report whether it works.          │
│     • UI: navigate + click + observe                                │
│     • API: curl with realistic data + verify response               │
│     • AI: real model invocation + real response check               │
│     • Data: write via API + read via API + display check            │
│     • Harness: --self-test PASS + mirror byte-identical             │
│     BLOCKING on Verification: full runtime tasks.                   │
│     Mechanism: task-verifier requires this agent's evidence         │
│     before flipping the checkbox.                                   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  task-verifier flips the checkbox via the evidence-first protocol   │
│  (existing mechanism — plan-edit-validator.sh enforces freshness)   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
                  ┌─────────── plan completes ────────────┐
                  │  (orchestrator's deliverable is the    │
                  │   closed plan, not the commits)         │
                  └────────────────────┬────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. end-user-advocate (existing)  — fires at session end            │
│     Adversarial product observer. Replays the plan's                │
│     ## Acceptance Scenarios against the live app.                   │
│     BLOCKING via product-acceptance-gate.sh Stop hook position 4.   │
│     Skipped when plan declares acceptance-exempt: true.             │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  3. claim-reviewer (existing)  — fires before answering             │
│     product Q&A (self-invoked by builder).                          │
│     Verifies every "X is done" claim has file:line citation.        │
│     Pipeline use: fires on the orchestrator's session-end summary   │
│     when the summary contains feature claims. Default verdict FAIL. │
│     ADVISORY in pipeline position; mandatory before user Q&A.       │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  4. domain-expert-tester (existing)  — fires after substantial      │
│     UI builds OR for any plan whose target persona is non-developer │
│     Becomes the target persona, audits the running app.             │
│     ADVISORY — findings logged but do not auto-block.               │
│     Mandatory under testing.md rules for substantial UI builds.     │
└─────────────────────────────────────────────────────────────────────┘
```

## When each step fires

### Step 1 — functionality-verifier

**Fires:** per-task, BEFORE `task-verifier` flips the checkbox.

**Trigger condition:** the task declares (or defaults to) `Verification: full` AND the task class is user-observable (UI, API, AI, Data, or harness-internal with `--self-test`).

**Exempted task classes:** `Verification: mechanical` and `Verification: contract` (task-verifier early-returns at Step 0 — see `~/.claude/rules/risk-tiered-verification.md`). Pure-refactor and pure-docs tasks where no user-observable surface exists return SKIP.

**Blocking semantics:** mechanical. task-verifier requires the agent's evidence line (`Runtime verification: functionality-verifier <slug>::<PASS|FAIL>`) in the evidence block before authorizing the checkbox flip. INCOMPLETE / ENVIRONMENT_UNAVAILABLE / SKIP are all not-PASS; task-verifier returns INCOMPLETE accordingly and the builder must either produce PASS evidence or surface the blocker.

**Evidence target:** the task's standard evidence file (`<plan>-evidence.md` or the structured `.evidence.json` substrate). The functionality-verifier's output block (see `agents/functionality-verifier.md` Output format) is the evidence.

### Step 2 — end-user-advocate (runtime mode)

**Fires:** at session end via the `product-acceptance-gate.sh` Stop hook (position 4 of the Stop chain).

**Trigger condition:** an ACTIVE plan exists, the plan is NOT `acceptance-exempt: true`, and no PASS artifact for the current `plan_commit_sha` is present under `.claude/state/acceptance/<plan-slug>/`.

**Blocking semantics:** mechanical, via the Stop hook. The hook BLOCKS session end without a PASS artifact (or substantive waiver / explicit exemption).

**Evidence target:** `.claude/state/acceptance/<plan-slug>/<session-id>-<ISO-timestamp>.json` plus sibling screenshot/network/console files.

**Composition with Step 1:** Step 1 (functionality-verifier) fires per-task during build; Step 2 (end-user-advocate runtime) fires once at session end against the full acceptance-scenarios set. They are complementary — Step 1 catches per-task functional failure inline; Step 2 catches cross-task scenarios that no single task's verification would surface (e.g., a sibling task missing breaks the whole flow).

### Step 3 — claim-reviewer

**Fires:** self-invoked by the orchestrator before sending any response to the user that contains a feature claim — including the session-end completion summary.

**Trigger condition:** the response under construction contains any of: "X works", "X is wired up", "X is done", "we have Y", "X supports Y", "X handles Z", "the system X", "X is now fixed", or future-tense → present-tense transitions about features.

**Blocking semantics:** self-invocation only. Claude Code does not have a PostMessage hook, so this step is the residual gap in the Gen 4 enforcement (acknowledged in `~/.claude/rules/vaporware-prevention.md`). The user retains interrupt authority when they see a feature claim without a visible citation.

**Evidence target:** the agent's review block (PASS/FAIL with class-aware feedback per the six-field contract) is reviewed by the orchestrator; FAIL means rewrite the draft.

**Composition with Steps 1-2:** Step 3 reviews the WORDS the orchestrator is about to send. Steps 1-2 verified the FEATURE. Even if Steps 1-2 both PASS, the orchestrator's prose summary can still drift into uncited claims about features that aren't part of THIS plan but are referenced as context. Step 3 catches that drift.

### Step 4 — domain-expert-tester

**Fires:** after substantial UI builds (per `testing.md` mandate), OR when the orchestrator judges the work has user-observable behavior that warrants persona-level review.

**Trigger condition:** plan added/modified a route, top-level page, top-level component, or any user-facing flow with non-trivial scope. The `testing.md` rule names the specific UI triggers.

**Blocking semantics:** advisory. Findings are logged to `docs/reviews/YYYY-MM-DD-<slug>.md` per the testing.md "Persist results immediately" rule. P0 findings must be fixed before close; P1 should be fixed unless deferred with reason; P2 may be deferred.

**Evidence target:** the agent's structured JSON output (see `agents/domain-expert-tester.md` Output Format) saved to `docs/reviews/`.

**Composition with Steps 1-2:** Step 1 verified the feature works. Step 2 verified scenarios pass adversarially. Step 4 verifies the feature MAKES SENSE to the target persona — that the UX is intuitive, that error messages help, that a real user (not a developer) can complete the task. Functional ≠ usable.

## Composition rules

1. **Step 1 is the only step the orchestrator MUST run for every task.** It is the mechanical backstop. Steps 2-4 fire at their own triggers; the orchestrator does not need to manually sequence them.
2. **The order matters when multiple steps fire.** functionality-verifier fires first (cheap mechanical check inline with task verification). end-user-advocate fires next (expensive but bounded — only at session end, only against declared scenarios). claim-reviewer fires before the orchestrator's prose summary leaves. domain-expert-tester fires when the orchestrator decides usability review is warranted.
3. **Skipping a step is legitimate only when its trigger condition is not met.** SKIP functionality-verifier when the task is mechanical/contract. SKIP end-user-advocate runtime when the plan is acceptance-exempt with substantive reason. SKIP claim-reviewer when no feature claim is in the draft. SKIP domain-expert-tester when no substantial UI surface was added.
4. **An agent's INCOMPLETE or ENVIRONMENT_UNAVAILABLE verdict is treated as NOT PASS for blocking purposes.** Do not fall back to PASS when the verifying agent could not run.

## Composition with existing mechanisms

The pipeline does NOT replace any existing mechanism. It composes with them:

- **`pre-commit-tdd-gate.sh`** runs at commit time, gates on test existence and quality. Functionality-verifier runs at task-verification time, gates on feature behavior. They check different things at different times.
- **`plan-edit-validator.sh`** runs at checkbox-flip time, enforces evidence-first protocol. Functionality-verifier's PASS output is *what makes* the evidence block valid for `Verification: full` runtime tasks. The validator is the substrate; functionality-verifier is the agent that fills it.
- **`runtime-verification-reviewer.sh`** runs at session-end, cross-checks that the runtime-verification line corresponds to the feature. Functionality-verifier's output line is itself a runtime-verification entry (`Runtime verification: functionality-verifier <slug>::<verdict>`), and the reviewer can replay it the same way it replays `playwright`/`curl`/`test`/`sql`/`file` entries.
- **`product-acceptance-gate.sh`** runs at Stop, gates on acceptance-scenarios PASS artifact. This is exactly end-user-advocate runtime's enforcement layer; the pipeline's Step 2 IS this gate.
- **`task-verifier`'s comprehension-gate (R2+)** runs before this pipeline at R2+ plans, gates on builder's articulated mental model. The comprehension-gate verifies what the builder UNDERSTOOD. Functionality-verifier verifies what the builder DELIVERED. Both at task time, but they check different things.

## When a step disagrees

- **functionality-verifier PASS but end-user-advocate FAIL.** A narrow task path works; the broader acceptance scenario fails. Diagnose: typically a sibling task is missing or a cross-task wiring gap exists. Open the missing task (or the in-flight scope update) and dispatch.
- **functionality-verifier PASS but claim-reviewer FAIL.** The feature works but the orchestrator's prose claim is wrong (different feature claimed than was built; mistaken claim about an adjacent feature). Rewrite the draft.
- **functionality-verifier PASS but domain-expert-tester P0.** The feature works but the persona cannot use it (invisible button, jargon, missing entry point). Fix the UX gap; re-run functionality-verifier to confirm the fix didn't break the function.

Disagreements are signal, not noise. Each agent has a distinct role; surfacing disagreement is the whole point of running them in sequence.

## What this pipeline is NOT

- **Not a single hook.** The pipeline is composed of four agents each with their own firing triggers. A single PreToolUse hook trying to invoke all four would fire-storm on every Edit/Write and conflate distinct lifecycle positions.
- **Not a replacement for unit tests or integration tests.** Unit and integration tests verify components and wiring; the pipeline verifies functionality. Both are necessary.
- **Not a substitute for code review.** `code-reviewer` reviews diffs for quality, conventions, correctness in the code. The pipeline reviews behavior in the running system. The two are complements.
- **Not an excuse to ship without thinking.** The pipeline catches mechanical failures of "the feature doesn't work." It does not catch shipping the wrong feature, solving the wrong problem, or building something the user did not ask for. `prd-validity-reviewer` and `end-user-advocate` plan-time mode catch those at planning time.

## Cross-references

- **Agent (new):** `~/.claude/agents/functionality-verifier.md` — the per-task functional check; the agent introduced by this rule's parent plan.
- **Agent:** `~/.claude/agents/end-user-advocate.md` — adversarial product observer (plan-time + session-end runtime).
- **Agent:** `~/.claude/agents/claim-reviewer.md` — verbal-vaporware adversary for feature claims in prose.
- **Agent:** `~/.claude/agents/domain-expert-tester.md` — target-persona usability tester.
- **Agent:** `~/.claude/agents/task-verifier.md` — the entity that flips checkboxes; requires functionality-verifier evidence on `Verification: full` runtime tasks.
- **Rule:** `~/.claude/rules/risk-tiered-verification.md` — defines `Verification: <level>` field that scopes when functionality-verifier fires.
- **Rule:** `~/.claude/rules/acceptance-scenarios.md` — the plan-time + runtime end-user-advocate loop (Step 2 of the pipeline).
- **Rule:** `~/.claude/rules/testing.md` — the substantial-UI-build mandate that triggers Step 4 (domain-expert-tester).
- **Rule:** `~/.claude/rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- **Rule:** `~/.claude/rules/planning.md` — `## FUNCTIONALITY OVER COMPONENTS` (the most important rule in the harness); this pipeline is the operational mechanism for that principle.
- **Hook:** `~/.claude/hooks/product-acceptance-gate.sh` — Stop hook position 4; Step 2's mechanical enforcement.
- **Hook:** `~/.claude/hooks/plan-edit-validator.sh` — checkbox-flip evidence-first enforcement; consumes functionality-verifier output as Runtime verification line.
- **Script:** `~/.claude/pipeline-templates/verify-functionality.sh` — orchestration script that runs the pipeline manually for a given plan task.

## Enforcement summary

| Step | Agent | Trigger | Blocking? | Mechanism |
|---|---|---|---|---|
| 1 | `functionality-verifier` | task-verifier dispatch on `Verification: full` runtime task | **Yes** (mechanical) | task-verifier requires evidence line; plan-edit-validator enforces evidence-first protocol |
| 2 | `end-user-advocate` (runtime) | Stop hook, ACTIVE non-exempt plan, no fresh PASS artifact | **Yes** (mechanical) | `product-acceptance-gate.sh` Stop hook position 4 |
| 3 | `claim-reviewer` | builder draft contains feature claim | Self-invoked (residual gap) | Pattern only — Claude Code lacks PostMessage hook |
| 4 | `domain-expert-tester` | substantial UI build per `testing.md` | Advisory | Pattern — findings logged to `docs/reviews/`; P0 must fix |

Steps 1-2 are Mechanism-backed. Steps 3-4 are Pattern-only — they have well-established triggers and lifecycle positions in their per-agent rules, but the pipeline does NOT introduce a new hook to fire them automatically. The user retains interrupt authority on Step 3 (per the existing residual-gap acknowledgment in vaporware-prevention.md); Step 4 is covered by the testing.md mandate.

## Scope

This rule applies in any project whose Claude Code installation has the `functionality-verifier.md` agent file and the corresponding `task-verifier.md` extension. Projects without the extension see no behavioral change — task-verifier runs its existing rubric on every task. Adoption is implicit on harness install/sync; downstream projects do not need to opt in.

The pipeline composes uniformly across product code and harness code. For product code, the functional demonstration is a user-shaped exercise (browser click, curl call, AI invocation). For harness code, the functional demonstration is the artifact's `--self-test` invocation passing. Both are user-shaped exercises in their respective contexts — the harness's "user" is the maintainer, and `--self-test` is the maintainer-observable correctness check.
