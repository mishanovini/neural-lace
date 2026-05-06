# Neural Lace — Architecture Overview

> The harness is a structured tech team operating within an enforcement substrate, not a single-agent prompt. This doc explains the team, how it ships work end-to-end, and the three independent layer systems that hold it together.

**Last verified:** 2026-05-06.

## You are here

You're reading the unified architectural narrative — the doc that ties the whole system together. If you wanted something different:

- For the 30-second skim of what this is and why it exists → [`README.md`](../README.md).
- For the install-and-run-once walkthrough → [`SETUP.md`](../SETUP.md).
- For the exhaustive per-mechanism inventory (every hook, every agent, every script with its full behavioral specification) → [`docs/harness-architecture.md`](harness-architecture.md).
- For the per-practice rationale ("why is decision-record atomicity worth a hook?") → [`docs/best-practices.md`](best-practices.md).
- For the per-agent failure-mode analysis (where each agent's training incentives stray) → [`docs/agent-incentive-map.md`](agent-incentive-map.md).
- For the doc-writing principles this doc follows → [`docs/doc-writing-patterns.md`](doc-writing-patterns.md).
- For Build Doctrine integration arc status → [`docs/build-doctrine-roadmap.md`](build-doctrine-roadmap.md).

**Glossary (terms used throughout):**
- **Build Doctrine** — a separate methodology repository at `~/claude-projects/Build Doctrine/` whose principles (failsafe-first, work-shapes, risk-tiered verification, knowledge-integration ritual) were integrated into Neural Lace beginning May 2026.
- **ADR** — Architecture Decision Record. Stored at `docs/decisions/NNN-<slug>.md`; indexed by `docs/DECISIONS.md`. Required for every Tier 2+ decision.
- **rung** — the diff complexity score declared in a plan's header. R0 = single-file trivial. R1 = mostly-isolated. R2+ = multi-file with behavioral contracts. The harness gates more substance review at higher rungs.
- **A1 / A3 / A5 / A7 / A8** — labels for the five Generation-6 narrative-integrity Stop hooks: A1 first-message goal extraction, A3 self-contradiction detection, A5 deferral surfacing, A7 strong-imperative coverage, A8 vaporware-volume gate. Each reads the session JSONL transcript (which the agent cannot edit) to close a gap between claims and evidence.
- **FM-NNN** — failure-mode catalog entry. Stored at `docs/failure-modes.md`. Six-field schema (ID, Severity, Scope, Source, Location, Status).

## What this doc is — and isn't

**Is:** the unified narrative. A 15-minute read for a developer who wants to understand how the harness fits together end-to-end.

**Isn't:** the catalog. This doc shows shape and flow; it does not list every hook's `--self-test` count or every agent's tool allowlist. When you need depth on a specific mechanism, follow the link to the catalog.

**Isn't:** an install guide. See `SETUP.md` for that.

## What the harness IS at the architecture level

A harness platform that wraps an AI coding tool (Claude Code today; Codex / Cursor / Gemini planned) with three things composed together:

1. **A structured team of specialized agents** — 20 at this writing (19 sub-agents + the orchestrator main session) — each playing a real-world tech-team role with bounded scope and constrained authority.
2. **A layered architecture** — universal principles, tool-family patterns, tool-specific adapters, per-project overrides — so improvements compose rather than fork.
3. **An enforcement substrate** — ~40 hooks, contextual rules, and deterministic scripts that mechanically gate the work the team does.

The team is the agents. The architecture is the layering. The substrate is the hooks. None of the three works alone; their composition is what makes the harness more than the sum of its prompts.

The design premise is that AI coding tools, on their own, fail at specific predictable boundaries — claiming completion of work that was only partially done, deferring inconvenient sub-tasks silently, drifting from spec under context pressure, missing edge cases that a human reviewer would have caught. Each of these failure modes is documented in `docs/failure-modes.md` as a six-field entry (FM-NNN). The harness's job is to make each documented failure mode mechanically harder to produce than the correct alternative. That mechanical-harder property is what differentiates the harness from a richer prompt: a prompt asks the agent to do better; a hook refuses to let the agent ship the failure.

The team-role analogy is the maintainer's mental model for organizing this. A real engineering team has roles, accountability boundaries, peer review, escalation paths, and audit infrastructure (CI, linters, branch protection). The harness gives the AI the same shape, with one critical difference: the AI plays multiple roles in different contexts (one session is the orchestrator; another session, dispatched from it, is the builder), but each role's prompt scopes what the role can do and each transition between roles is gated by a hook. A builder cannot flip its own checkbox because `task-verifier` is the only entity with that authority; `task-verifier` cannot flip a checkbox without fresh evidence because `plan-edit-validator.sh` enforces evidence-first authorization. The hooks make the role separation real.

---

## I. The team-role analogy

### A concrete walkthrough first

You ship a feature. Here's who does what.

You start a session, type the user request, and the **main session** (the orchestrator — the engineering manager) reads the request. It opens the active plan at `docs/plans/<slug>.md`, sees three tasks marked unchecked, and decides task 1 and task 2 are independent (touch disjoint files). It dispatches two `plan-phase-builder` sub-agents in parallel via the Task tool with `isolation: "worktree"` — one per task, each in its own git worktree. (These are the IC engineers.) Each builder cuts a worker branch off the orchestrator's feature branch, builds the change, commits to its own worktree. When done, each builder invokes `task-verifier` (the QA engineer) to verify the work. `task-verifier` doesn't trust the builder's word — it reads the actual diff, runs `npm test`, runs the runtime-verification commands the plan declares, and only writes the evidence block + flips the checkbox if the diff matches the claim.

The orchestrator collects both verdicts, cherry-picks the worktree commits onto the feature branch (sequentially, to avoid plan-file race conditions), and tears down the worktrees. Before any commit lands, `code-reviewer` and `security-reviewer` (senior engineers) read the diff and emit class-aware findings. Issues fixed; commit lands.

Now task 3 — a UI surface change. The orchestrator dispatches a builder; this time `ux-designer` (the UX specialist) reviews the plan's UI section at plan-time and returns a structured gap list. The plan absorbs the gaps; the builder builds; `task-verifier` verifies. After all three tasks land, the orchestrator runs `close-plan.sh` (the deterministic close-out script) which invokes `end-user-advocate` in runtime mode (the PM / user advocate). The advocate opens a real browser via the Chrome MCP, walks the user-flow scenarios from the plan against the live app, and writes a JSON PASS/FAIL artifact to `.claude/state/acceptance/<slug>/`. On PASS: `close-plan.sh` flips Status to COMPLETED, which triggers `plan-lifecycle.sh` (a hook) to `git mv` the plan into `docs/plans/archive/`. On FAIL: `enforcement-gap-analyzer` (the retro / process-improvement agent) reads the failure and the session transcript, and produces a harness-improvement proposal — turning the FAIL into a learning, not a stuck plan.

That's one feature. Eight agents fired, plus the orchestrator. The principle the example demonstrates: **every claim is verified by a different agent than the one that made it**, and the verification is mechanical (hook-backed) where possible.

### Full role mapping

| Real-world tech-team role | Agent or mechanism | What it does | When it fires |
|---|---|---|---|
| Engineering manager / tech lead | The main session (orchestrator) | Reads plan, dispatches builders, collects results, stays lean. Doesn't do the build work itself. | Continuous through the session |
| IC engineer | `plan-phase-builder` | Builds one task (or tightly-coupled cluster) end-to-end in an isolated worktree. Returns a concise verdict. | Dispatched per task by orchestrator |
| QA engineer | `task-verifier` | The only entity that can flip plan checkboxes. Verifies via real evidence (typecheck, runtime commands, file:line citations). | After every task build |
| Senior code reviewer | `code-reviewer` | Reads diffs for quality, correctness, conventions, user impact. Emits class-aware findings. | Pre-commit on substantive diffs |
| Security engineer | `security-reviewer` | Catches OWASP-class issues common in AI-generated code (auth, injection, multi-tenant leaks, rate limiting). | Pre-commit on diffs touching sensitive surfaces |
| Principal engineer / architect | `systems-designer` | Reviews `Mode: design` plans (CI/CD, migrations, infrastructure) before implementation. PASS required. | Plan-time for design-mode plans |
| UX designer | `ux-designer` | Reviews UI plans before build. Maps user journey, finds missing empty/error/loading states, dead-ends. | Plan-time for new UI surfaces |
| Product manager / user advocate | `end-user-advocate` | Plan-time: authors `## Acceptance Scenarios`. Runtime: drives a real browser through scenarios against the live app, writes PASS/FAIL artifact. The only adversarial verifier of the running product. | Plan-time AND runtime (Stop hook gate) |
| Content / docs reviewer | `audience-content-reviewer` | Reads all user-facing text against the project's audience. Catches wrong-audience language, jargon, placeholder content. | After substantial UI builds |
| Generic UX tester | `ux-end-user-tester` | Walks the app as a non-technical back-office worker; finds dead ends, jargon, broken flows. | After substantial UI builds |
| Domain expert tester | `domain-expert-tester` | Becomes the project's target persona (from `.claude/audience.md`) and tests workflows from that perspective. | After substantial UI builds |
| Test engineer | `test-writer` | Generates tests for failure modes (not coverage numbers), following project conventions. | On demand |
| Auditor / internal control | `plan-evidence-reviewer` | Independent second opinion on completion claims. Verdicts: CONSISTENT / INCONSISTENT / INSUFFICIENT / STALE. | Every 30 tool calls (forced audit) |
| Comprehension reviewer | `comprehension-reviewer` | At rung 2+: verifies the builder's articulation (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions) corresponds to the actual diff. | Auto-invoked by `task-verifier` at rung 2+ |
| PRD reviewer | `prd-validity-reviewer` | Adversarial substance review of `docs/prd.md` against the active plan. Reviews problem clarity, scenario coverage, success-metric measurability. | Plan-time when `prd-ref:` is declared |
| Process improvement / retro | `enforcement-gap-analyzer` | Reads runtime FAIL + transcript + which hooks fired; proposes a generalized harness improvement. Required to amend an existing rule before adding a new one. | After every runtime acceptance FAIL |
| Adversarial harness reviewer | `harness-reviewer` | Skeptical review of any harness change. Default verdict: REJECT. Classifies change as Mechanism vs Pattern vs Hybrid; applies class-appropriate criteria. | Before any harness rule/hook/agent change is committed |
| Adversarial claim reviewer | `claim-reviewer` | Cross-checks feature claims in draft responses against the codebase via `verify-feature` skill. Default verdict: FAIL. Self-invoked (residual gap). | Before answering product Q&A |
| Cheap codebase explorer | `explorer` | Fast Haiku-powered lookups for "where does X live" without filling main context. | On demand |
| Deep researcher | `research` | Structured architecture analysis with curated output for the caller. | On demand |

**The team comprises 20 agents** — 19 sub-agents (the entries above) plus the orchestrator (the main Claude Code session, listed at the top of the table). Several **load-bearing hooks** play team roles too — they're not LLMs, but they're the auditors and gate-keepers without which the LLMs' self-discipline would fail.

| Real-world role | Hook / mechanism | What it does |
|---|---|---|
| Build-time linter / gate-keeper | `pre-commit-tdd-gate.sh` (5 layers) | New runtime files require tests; modified runtime files require test references; integration tests cannot mock; trivial assertions rejected; silent skips banned. |
| Plan-edit auditor | `plan-edit-validator.sh` | Refuses checkbox flips without fresh matching evidence file. Wrapped in `flock` so parallel verifiers serialize safely. |
| Scope auditor | `scope-enforcement-gate.sh` | Refuses commits with files outside the active plan's declared `## Files to Modify/Create`. Three escape options surfaced (update plan, new plan, defer). |
| Plan-lifecycle archivist | `plan-lifecycle.sh` | When a plan's `Status:` flips to terminal (COMPLETED / DEFERRED / ABANDONED / SUPERSEDED), atomically `git mv`s the file (and its evidence sibling) into `docs/plans/archive/`. |
| End-of-day auditor | `pre-stop-verifier.sh` | Refuses session end if any active plan has unchecked tasks, missing evidence, or runtime-verification gaps. |
| Narrative auditor (Gen 6 — 4 hooks) | `deferral-counter.sh`, `transcript-lie-detector.sh`, `imperative-evidence-linker.sh`, `goal-coverage-on-stop.sh` | Read the session JSONL transcript (which the agent cannot edit) to catch deferred work, self-contradiction, skipped imperatives, and unfulfilled first-message goals. The "you can't close out the day with unfinished work" auditor. |
| Tool-call rate limiter | `tool-call-budget.sh` | Forces a `plan-evidence-reviewer` audit every 30 tool calls. Mitigates attention decay in long sessions. |
| Acceptance gate | `product-acceptance-gate.sh` | Refuses session end when an ACTIVE non-exempt plan lacks a runtime PASS artifact whose `plan_commit_sha` matches HEAD. |
| Pre-push security guard | `pre-push-scan.sh` | Global git pre-push hook scanning for credentials. Last-line defense across every repo on the machine, not just AI-assisted ones. |
| Hygiene auditor | `harness-hygiene-scan.sh` | Pre-commit denylist scan refusing commits that leak personal identifiers, real domains, real emails, hardcoded paths into harness code. |

A real engineering team has the LLM-equivalent roles AND the auditing infrastructure (CI, linters, branch protection, credential scanning, code-review tooling). Neural Lace's harness has both. The split between "agents" and "hooks" maps cleanly to the split between "engineers reviewing each other" and "the CI / CD / policy engine that doesn't trust either of them."

### Per-agent vignettes — why each agent IS that role

A few agent prompts merit specific commentary because the role-match is what makes the harness work.

**`task-verifier` is a QA engineer, not a build assistant.** A QA engineer's job is to refuse to certify something they cannot verify. `task-verifier` follows that exact discipline: it has Edit access to plan files but only via the evidence-first protocol enforced by `plan-edit-validator.sh`, and it bans plain-text manual verification claims. Its prompt explicitly names self-reports as the failure mode it exists to backstop. When the builder says "I shipped X," `task-verifier` reads the actual diff, runs the runtime-verification command, and only flips the checkbox if reality matches the claim. The constraint that ONLY `task-verifier` can flip plan checkboxes is the load-bearing one — it makes the QA / dev separation real, not advisory.

**`end-user-advocate` is a PM with a user-test lab.** Most other agents trust the artifacts the builder produced (the diff, the evidence block, the test output). `end-user-advocate` doesn't. In runtime mode it opens a real browser, types into real forms, and asserts against the live page. Its verdict is a JSON artifact with screenshots + network log + console log — durable evidence the next session can replay. The advocate is the only agent in the harness whose verdict depends on observing the running product, not on reading what the builder wrote.

**`code-reviewer` and `security-reviewer` are senior engineers, not linters.** Their prompts open with prime directives — `code-reviewer`: "protect the end user from anything that would frustrate, confuse, or disappoint them"; `security-reviewer`: "protect the end user from incidents they'd never forgive." The framing is intentional: a linter catches style violations; a senior engineer catches design errors that pass the lint. The class-aware feedback contract (six-field blocks: Line / Defect / Class / Sweep query / Required fix / Required generalization) is the discipline that turns a code review from a list of issues into a list of CLASSES of issues — fix the class, not the instance.

**`harness-reviewer` defaults to REJECT.** Most reviewers default to PASS unless a problem is found. `harness-reviewer`'s default is REJECT unless the proposed harness change can be defended on Mechanism vs Pattern vs Hybrid grounds. The asymmetric default exists because harness changes compound: a wrong hook ships with every install. The reviewer's burden of proof is on the proposer, not the reviewer.

**`enforcement-gap-analyzer` is the retrospective at the end of every failed product test.** Every runtime acceptance FAIL produces a generalized harness-improvement proposal — not "fix this one thing" but "propose the rule or hook that would have caught this class of failure." The agent is REQUIRED to review existing rules first; missed-catches by an existing rule trigger AMENDMENT, not addition. The harness becomes self-improving from its own observed failures.

**`comprehension-reviewer` is the design review for non-trivial work.** At rung 2 and above (multi-file diffs, behavioral-contract changes), the builder must articulate four things in writing: their interpretation of the spec, the edge cases the diff covers, the edge cases NOT covered, and the assumptions the diff relies on. `comprehension-reviewer` then verifies the articulation corresponds to the actual diff. The mechanism catches the failure mode where the diff compiles and tests pass but the builder silently misunderstood an edge case — the diff is correct; the builder's mental model isn't.

### Why the analogy is load-bearing

This isn't a marketing flourish; it's how the harness was designed. Each agent's prompt explicitly names a role and grounds the agent in that role's incentives. Each hook's design names which incentive it counters and which agent's failure mode it backstops.

The team analogy lets the maintainer reason about the harness the way a tech lead reasons about a team: who's accountable for what; where are the single points of failure; which roles are missing or under-equipped. The catalog at `docs/agent-incentive-map.md` makes this explicit by enumerating each agent's stated goals, latent training incentives, predicted stray-from patterns, current mitigations, and residual gaps. When a new agent is added, the incentive-map exercise is part of the addition; when an existing agent strays, the map is consulted to decide whether the fix is a prompt edit, a new hook, or a new agent entirely.

---

## II. End-to-end product-delivery flow

### One feature, from idea to merge

A user asks for a feature that needs a new API route, a UI page, and a database column. The flow below is the full path the harness routes that work through, from plan creation to master merge. Each step names which agents fire, which hooks gate the transition, and what artifact is produced. The numbered list is sequential; many steps invoke parallel sub-flows internally.

1. **Plan creation.** The orchestrator runs `start-plan.sh <slug>` which scaffolds `docs/plans/<slug>.md` with the plan template (7 required sections plus the new 5-field plan-header schema: `tier`, `rung`, `architecture`, `frozen`, `prd-ref`). The planner fills Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy. ON FAIL: `plan-reviewer.sh` blocks the commit naming the missing-or-thin section. ON PASS: plan committed, `Status: ACTIVE`.

2. **Plan-time peer review.** For UI work, `ux-designer` is invoked on the plan's UI section. For systems-design work (CI/CD, migrations, infra), `systems-designer` is invoked on the 10-section Systems Engineering Analysis. For every plan that isn't `acceptance-exempt: true`, `end-user-advocate` is invoked in plan-time mode and authors the `## Acceptance Scenarios` section. If the plan declares a `prd-ref:`, `prd-validity-reviewer` reviews the linked `docs/prd.md` for substance. ON FAIL: gaps closed in the plan or rejected scenarios moved to `## Out-of-scope scenarios`. ON PASS: plan ready for build.

3. **Spec freeze.** The planner sets `frozen: true` in the plan header. After this point, edits to files declared in `## Files to Modify/Create` require either thawing (with a Decisions Log entry) or scope expansion via `## In-flight scope updates`. `spec-freeze-gate.sh` enforces.

4. **Orchestrator dispatch.** The main session reads the plan and identifies independent task clusters. For each cluster, it dispatches a `plan-phase-builder` via the Task tool with `isolation: "worktree"`. Up to ~5 parallel builders. Builders cut worker branches off the orchestrator's feature branch, build, commit on the worker branch.

5. **Per-task verification.** Each builder invokes `task-verifier` BEFORE the orchestrator cherry-picks. `task-verifier` writes an evidence block at `<plan>-evidence.md` (or, for mechanical tasks, a structured `<plan-slug>-evidence/<task-id>.evidence.json`) and flips the checkbox via `plan-edit-validator.sh`'s evidence-first protocol. At rung 2+, `comprehension-reviewer` is auto-invoked first; FAIL or INCOMPLETE blocks the flip. ON FAIL: builder iterates. ON PASS: checkbox flipped.

6. **Orchestrator cherry-pick.** Builders return; the orchestrator processes results in plan-task-ID order. Each builder's commits are cherry-picked onto the feature branch. Conflict → BLOCKED (the parallelism assumption was wrong; surface to user). Worktree torn down.

7. **Pre-commit gates.** When the orchestrator commits the cherry-picked work to the feature branch, the pre-commit hook chain fires: `pre-commit-tdd-gate.sh` (5 layers), `plan-reviewer.sh` (if plan files staged), `harness-hygiene-scan.sh` (if harness files staged), `definition-on-first-use-gate.sh` (if doctrine docs staged), `findings-ledger-schema-gate.sh` (if `docs/findings.md` staged), `npm test`, `npm run build`, API audit. Any layer fires → BLOCK.

8. **Pre-commit code review.** `code-reviewer` and `security-reviewer` read the diff. Each emits class-aware findings. The orchestrator addresses every Critical and Important finding. Sweep-class findings get `Class-sweep:` documented in the commit message.

9. **Plan closure invocation.** With all tasks DONE and all gates green, the orchestrator runs `close-plan.sh <slug>`. The script deterministically: (a) verifies all tasks checked, (b) verifies all checked tasks have evidence blocks, (c) updates `docs/build-doctrine-roadmap.md` if the plan was a doctrine tranche, (d) drafts the closure commit, (e) invokes runtime acceptance.

10. **Runtime acceptance.** `end-user-advocate` is invoked in runtime mode against the dev server. It opens a real browser (Chrome MCP), walks each scenario from the plan, captures screenshots + network log + console log, and writes a JSON artifact to `.claude/state/acceptance/<slug>/<session-id>-<ts>.json` with `plan_commit_sha` and per-scenario verdict. ON FAIL: see step 11. ON PASS: continues to step 12.

11. **Failure → harness-improvement loop.** `enforcement-gap-analyzer` is auto-invoked with the FAIL artifact + plan + session transcript + list of hooks that fired. The analyzer reads existing rules first, drafts a `docs/harness-improvements/NNN-<slug>.md` proposal (amend an existing mechanism if one should have caught the FAIL; only add new if no existing mechanism applies). `harness-reviewer` reviews the proposal with a generalization check. The runtime FAIL becomes a harness improvement, not a stuck plan.

12. **Status flip → archival.** The orchestrator (or `close-plan.sh`) flips `Status:` from `ACTIVE` to `COMPLETED`. `plan-lifecycle.sh` (PostToolUse) immediately `git mv`s the plan and its evidence sibling into `docs/plans/archive/`. The Status change and the file rename land in the same commit. (Status is the last edit; completion reports / final notes go BEFORE the flip.)

13. **Stop-hook chain.** The session ends. The 8-position Stop chain runs: `pre-stop-verifier.sh` (plan integrity) → `bug-persistence-gate.sh` (bugs persisted) → `narrate-and-wait-gate.sh` (no permission-seeking trail-off) → `product-acceptance-gate.sh` (PASS artifact present) → `deferral-counter.sh` (deferrals surfaced) → `transcript-lie-detector.sh` (no completion-vs-deferral contradictions) → `imperative-evidence-linker.sh` (user imperatives have evidence) → `goal-coverage-on-stop.sh` (first-message goals covered). Any block → session cannot end.

14. **Handoff freshness (ADR-027 Layer 5).** Before composing the final summary, `session-wrap.sh` verifies handoff artifacts are fresh: SCRATCHPAD mtime within 30 minutes and mentions every plan touched; roadmap reflects every Status change; pending discoveries flipped to decided/implemented if their decision shipped; What's Next reflects actual pending state.

15. **Push and merge.** Per `~/.claude/rules/git.md`, the orchestrator pushes the feature branch. PR created via `gh pr create` (the PR template forces "What mechanism would have caught this?" answered with one of three forms: existing FM-NNN entry, new FM-NNN proposal, or accepted residual risk with rationale). PR-template-check workflow runs in CI. `vaporware-volume-gate.sh` (PreToolUse on `gh pr create`) blocks PRs with high docs/config volume but zero execution evidence unless explicitly tagged. On green CI: merge to master. Master deploys to production per the customer-tier branching policy in `~/.claude/rules/git.md`.

**The agent cannot skip a step.** Each transition is gated mechanically. The team's discipline is enforced by the substrate; agent self-discipline is the fallback, not the primary defense.

**Per-step agent invocations summarized:**

| Step | Agents that fire | Hooks that gate |
|---|---|---|
| 1 (plan creation) | (planner) | `plan-reviewer.sh`, `plan-edit-validator.sh`, `prd-validity-gate.sh` |
| 2 (peer review) | `ux-designer`, `systems-designer`, `end-user-advocate` (plan-time), `prd-validity-reviewer` | (advisory) |
| 3 (spec freeze) | (planner) | `spec-freeze-gate.sh` |
| 4 (dispatch) | `plan-phase-builder` (×N) | `teammate-spawn-validator.sh` (Agent Teams), worktree-isolation enforcement |
| 5 (per-task verification) | `task-verifier`, `comprehension-reviewer` (rung 2+) | `plan-edit-validator.sh`, `outcome-evidence-gate.sh` |
| 6 (cherry-pick) | (orchestrator) | (none — git operations) |
| 7 (pre-commit gates) | `pre-commit-tdd-gate.sh`, plus contextual gates | All pre-commit hooks |
| 8 (code review) | `code-reviewer`, `security-reviewer` | (advisory; findings drive iteration) |
| 9 (closure invocation) | (orchestrator running close-plan.sh) | (deterministic script) |
| 10 (runtime acceptance) | `end-user-advocate` (runtime) | `product-acceptance-gate.sh` |
| 11 (FAIL → improvement) | `enforcement-gap-analyzer`, `harness-reviewer` | (advisory) |
| 12 (status flip → archival) | (orchestrator) | `plan-lifecycle.sh` |
| 13 (Stop chain) | — | 8-position Stop chain (pre-stop-verifier through goal-coverage-on-stop) |
| 14 (handoff freshness) | (orchestrator running session-wrap.sh) | (deterministic script) |
| 15 (push and merge) | — | `pre-push-scan.sh`, `vaporware-volume-gate.sh`, branch-protection (CI) |

### What the negative paths surface

The most informative property of this flow is what happens on FAIL. The harness was designed around the principle that **every failure becomes a structural learning**, not a stuck session. Runtime FAILs invoke the gap-analyzer; reviewer findings carry `Class:` + `Sweep query:` so siblings are fixed in one pass; observed errors land in `.claude/state/observed-errors.md` before fix commits ship. The flow above isn't a happy-path script; it's a recoverable state machine where every dead-end has a documented next move.

A few specific FAIL-path patterns are worth calling out:

- **Pre-commit gate FAIL:** the commit doesn't land. The orchestrator must fix the issue and create a NEW commit (never `--amend`, because if a hook failed, the commit didn't happen). `git.md` documents this discipline.
- **`task-verifier` FAIL:** the checkbox stays unchecked. The builder iterates and re-invokes. `task-verifier` errs toward FAIL when evidence is ambiguous — the prompt explicitly instructs this.
- **`comprehension-reviewer` INCOMPLETE:** the agent couldn't grade the articulation (missing sub-section, schema violation). The builder fills the gap and re-invokes — distinct from FAIL where the agent graded and rejected.
- **Stop-hook chain block:** the session can't end. The agent must address whatever the hook blocked on (uncommitted plan file, missing acceptance artifact, deferral not in final message, contradiction not reconciled). Each hook's block message names the specific remediation.
- **PR-template-check FAIL on master merge:** branch protection refuses the merge. The PR description must answer "What mechanism would have caught this?" before the merge unblocks.
- **Acceptance FAIL:** as detailed in step 11 above, the gap-analyzer is auto-invoked. The plan does not stay stuck; it produces a harness-improvement artifact and the user decides whether to amend the plan, the harness, or both.

The composability across FAIL paths is intentional. A typical recovery flow chains several: a `task-verifier` FAIL surfaces a missed edge case → the builder fixes it → the next pass through `code-reviewer` catches a sibling instance via class-aware feedback → the `Class-sweep:` is documented in the commit message → on green, `close-plan.sh` runs runtime acceptance → if THAT FAILs, the gap-analyzer captures the structural lesson. Every step has audit trail; nothing slips through silently.

---

## III. Three layered architectures, cross-walked

The harness has three independent layer systems. Each answers a different question. Don't conflate them — they compose orthogonally, and seeing them together is what makes the harness's structure tractable.

### System 1 — Layer 0/1/2/3 (where does code live?)

**Source of truth:** `docs/harness-strategy.md` lines 58-95.

**Question answered:** if I want this harness to also drive Codex, Cursor, or Gemini, what changes?

| Layer | Name | Contains | Tool-knowledge |
|---|---|---|---|
| Layer 0 | PRINCIPLES | Universal values: risk model, autonomy ladder, security posture, evaluation discipline, UX philosophy | None — never references a specific tool |
| Layer 1 | PATTERNS | Tool-family-agnostic: rule system, hook system, agent system, template system, pipeline system, evaluation system | Says "a pre-commit hook should run tests"; doesn't say "bash: pre-commit-gate.sh" |
| Layer 2 | ADAPTERS | Tool-specific implementations: `adapters/claude-code/` (settings.json, agents/*.md); future `adapters/codex/` (AGENTS.md, codex.json); `adapters/cursor/` (.cursorrules) | The only layer that knows about `settings.json` or `.cursorrules` |
| Layer 3 | PROJECT | Per-repo overrides: `.claude/rules/`, `.claude/audience.md`, project `CLAUDE.md` | Project-specific schema knowledge, audience definition, business logic |

**Concrete example.** Take "destructive operations require user confirmation." At Layer 0 (`principles/permission-model.md`), this is stated abstractly: actions are scored on six dimensions (reversibility, blast radius, sensitivity, etc.) and tier-3 actions require confirmation. At Layer 1 (`patterns/hooks/`), the pattern says "a PreToolUse hook on Bash matchers can intercept commands before they execute." At Layer 2 (`adapters/claude-code/hooks/`), this becomes concrete bash scripts wired in `settings.json.template` — `pre-commit-gate.sh`, force-push blockers, `--no-verify` blockers. At Layer 3 (per-project), a project might add its own `.claude/rules/` for project-specific destructive operations (e.g., a Terraform-using project might add a Terraform-apply gate). The principle is one; the patterns are reusable; the adapter is tool-specific; the project layer is bespoke.

**What this lets you do:** when the next AI coding tool arrives, only Layer 2 has to be rewritten. Layer 0's principles, Layer 1's patterns, and Layer 3's project context survive. The investment in stating principles abstractly (rather than as bash scripts) pays off when a new tool needs the same principles expressed in its native config format.

**Cross-references:** `docs/harness-strategy.md` "Architecture: The Layer Model" section; `principles/forward-compatibility.md` for the abstraction rules; `principles/permission-model.md` and `principles/progressive-autonomy.md` as canonical Layer 0 documents.

### System 2 — Generation 1-6 (when was each enforcement class added, and why?)

**Source of truth:** `docs/harness-architecture.md` "Generation Evolution" sections.

**Question answered:** what existed when, and why was each layer needed?

| Generation | Date | Theme | Representative mechanisms |
|---|---|---|---|
| Gen 1-3 | early 2026 | Foundational: rules-as-prose, agents-as-helpers, hooks-for-credentials | Pre-commit credential scan, pre-push scan, basic agent files |
| **Gen 4** | 2026-04-15 | **Anti-vaporware mechanisms.** Move enforcement from self-applied prose to mechanically-executed hooks. | `pre-commit-tdd-gate.sh` (5 layers), `plan-edit-validator.sh` (evidence-first), `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh`, `plan-reviewer.sh`, `tool-call-budget.sh`, `claim-reviewer` agent, `verify-feature` skill |
| **Gen 5** | 2026-04-24 | **Adversarial observation of the running product + plan-lifecycle integrity + self-improvement meta-loop.** | `end-user-advocate` agent (plan-time + runtime), `product-acceptance-gate.sh` Stop hook position 4, `plan-lifecycle.sh` archival, `plan-deletion-protection.sh`, `docs/failure-modes.md` six-field catalog, class-aware reviewer feedback, `enforcement-gap-analyzer`, capture-codify PR template + branch protection |
| **Gen 6** | 2026-04-26 | **Narrative-integrity Stop hooks.** Read the session JSONL transcript (which the agent cannot edit) to close the gap between agent claims and transcript evidence. | A1 first-message goal extraction (checksummed), A3 self-contradiction detection, A5 deferral surfacing, A7 strong-imperative coverage, A8 vaporware-volume gate on PR creation |
| **Build Doctrine integration** | May 2026 | **Doctrine substrate brought into the harness.** Seven mechanism families addressing gaps in the Gen 4-6 substrate. | Discovery Protocol (`bug-persistence-gate.sh` extension + `discovery-surfacer.sh`), Comprehension Gate (`comprehension-reviewer` agent + `task-verifier` extension), PRD Validity + Spec Freeze (5-field plan-header schema), Findings Ledger (`docs/findings.md` + schema gate), Definition-on-First-Use, Scope-Enforcement Gate redesign, DAG Review Waiver Gate |
| **Tranche 1.5** | 2026-05-05 | **Architecture-simplification: apply doctrine to harness self-development.** | Deterministic `close-plan.sh`, mechanical evidence schema + `write-evidence.sh`, work-shapes library (6 shapes), risk-tiered verification (`mechanical` / `full` / `contract`), failsafe audit (closure-validator retired), calibration loop |

**The pattern across generations:** earlier generations relied on agent self-discipline (rules-as-prose). Later generations move enforcement from prose to mechanical gates because self-discipline failed in practice — the originating incidents are documented in commit messages, ADRs, and `docs/failure-modes.md`. Each generation's additions backfill a class of failure observed in the previous generation.

**Specific failure incidents that motivated each generation:**

- **Gen 4** (anti-vaporware): the originating incident was a multi-task plan where the agent flipped checkboxes on tasks that hadn't actually been built — the diff existed but didn't satisfy the user-observable outcome. The Gen 4 mechanisms make checkbox flips contingent on real evidence rather than self-report.
- **Gen 5** (acceptance loop): the originating insight was that every Gen 4 mechanism gated on something the BUILDER produced. There was no adversarial observation of the running product. `end-user-advocate` is the harness's only agent whose verdict comes from observing the live app, not from reading what the builder claimed.
- **Gen 6** (narrative integrity): the originating incident on 2026-04-26 was an agent shipping a PR with 800 lines of docs + 174 lines of CI YAML and ZERO execution evidence while the plan's DoD was unchecked. Gen 6 hooks read the session JSONL transcript (which the agent cannot edit) and refuse session end when the transcript reveals deferred work, self-contradiction, skipped imperatives, or unfulfilled first-message goals.
- **Build Doctrine integration**: an arc of work bringing Build Doctrine's substrate (PRD validity, spec freeze, comprehension gate, findings ledger) into the harness. Each mechanism family addressed a specific gap in the Gen 4-6 substrate that became visible when the harness was applied to non-trivial multi-month work.
- **Tranche 1.5** (architecture simplification): applied Build Doctrine to harness self-development. Replaced the failsafe-validator pattern with deterministic close-plan procedure; introduced mechanical evidence schema for structural tasks; introduced risk-tiered verification so trivial tasks aren't subject to the full prose-evidence rubric.

**What this lets you do:** when something fails, knowing which generation it was added in tells you whether to expect prose-level discipline or hook-level enforcement, and which document (rule vs hook + ADR) captures the rationale. The newer the generation, the more likely the failure is mechanically prevented; the older the generation, the more likely the failure mode survives as residual risk that the team-role analogy and prose discipline must hold.

**Cross-references:** `docs/harness-architecture.md` "Generation 4 Enforcement", "Generation 5 Enforcement", "Generation 6 Enforcement"; ADRs 011-024 for Build Doctrine integration; ADR 026 + ADR 027 for Tranche 1.5.

### System 3 — ADR-027 Layer 1-5 (how is handoff state verified at session boundary?)

**Source of truth:** `docs/decisions/027-autonomous-decision-making-process.md`.

**Question answered:** when one session ends and another begins, how do we verify the handoff hasn't gone stale?

| Layer | Name | Substrate | Failure mode it prevents |
|---|---|---|---|
| Layer 1 | Pre-emptive identification at plan kickoff | `docs/decisions/queued-<plan-slug>.md` | Decisions arising mid-execution that block progress against an asynchronously-available decider |
| Layer 2 | Mid-execution autonomous decisions (reversible only) | New `docs/decisions/NNN-<slug>.md` written during autonomous work | Pause-and-wait friction when the decision is reversible; or velocity-without-traceability when it isn't documented |
| Layer 3 | Mandatory ADR documentation | Every Tier 2+ Layer 2 decision lands in `docs/decisions/` | "I decided X in chat" disappearing when context compacts |
| Layer 4 | Final-summary surfacing | "Decisions made autonomously" section in every session-ending response | User missing the decision trail because it's buried in commits |
| Layer 5 | Handoff freshness as precondition | `session-wrap.sh` runs before final-summary composition | SCRATCHPAD says one thing; the artifacts the next session reads say another |

**The pattern:** Layer 4's surface-level summary is impeccable while Layer 5's underlying artifacts are stale. The user prompts "have you updated all the documentation so the next session knows the state?" because the agent passed its own surface test (composed the summary) while failing the underlying property (handoff is current). Layer 5 makes the artifacts the gate, not the prose.

**What this lets you do:** asynchronous review of substantial autonomous work. The user doesn't have to be in the session; the substrate guarantees the next session inherits an accurate handoff.

**Cross-references:** `docs/decisions/027-autonomous-decision-making-process.md` for the full rationale and the Layer 5 motivation (the empirical 2026-05-05 architecture-simplification session that surfaced the gap).

### Cross-walk — three systems, three questions

| System | Question answered | Layers | Changes rarely or often | Where documented |
|---|---|---|---|---|
| L0/L1/L2/L3 | If we add a new AI tool, what changes? | 4 | Rarely (when adding a new adapter — once per tool family) | `docs/harness-strategy.md` |
| Generation 1-6 | What existed when, and why was each layer needed? | 6 (and growing) | Often (each generation is months apart; one expected per quarter at current cadence) | `docs/harness-architecture.md` |
| ADR-027 Layer 1-5 | How is handoff state verified at session boundary? | 5 | Rarely (the model is locked once Layer 5 closed it; revisions are additive) | `docs/decisions/027-autonomous-decision-making-process.md` |

**How the three compose orthogonally.** A concrete example: imagine a new `Mode: design` plan authored today against an existing project's Codex adapter (when one ships). The plan's authoring follows ADR-027 Layer 1 (decisions queued at plan kickoff); its mechanical enforcement uses Generation 5's `systems-design-gate.sh` and Generation 6's narrative-integrity Stop hooks; its Codex-specific config lives in `adapters/codex/` (Layer 2). Three independent systems contribute to the same plan, none of them stepping on the others.

**Why three and not one.** A unified system would have to answer all three questions in one taxonomy. That doesn't work because the three questions have different audiences and different change cadences:
- L0/L1/L2/L3 is for the **maintainer thinking about portability** ("if a new AI tool ships, what do we have to rewrite?"). It changes when adapter strategy changes.
- Generation 1-6 is for the **maintainer thinking about evolution** ("when did this gap surface; what's the rationale for this hook?"). It changes every few months as new failure classes surface.
- ADR-027 Layer 1-5 is for the **operator running multi-session arcs** ("how does the next session inherit accurate state?"). It changes rarely because handoff-freshness is a foundational property.

A reader landing on the harness can pick the layer system that matches their question and ignore the others. Conflating them produces "the harness has 3+6+5 = 14 layers" confusion; seeing them as three orthogonal systems each answering one question makes each tractable.

**Where it gets visible in practice.** Plan files declare `architecture: <slug>` (L1 patterns layer — affects which patterns apply); declare `tier:`, `rung:`, `frozen:`, `prd-ref:` (substrate behaviors gated by Gen 6 / Build Doctrine mechanisms); and inherit Layer 5 handoff-freshness checks at session end. The plan-template's 5-field plan-header schema is the union of all three systems' inputs at plan-author time.

---

## IV. Where everything lives

Filesystem map, organized by layer. Annotations cite the team-role analogy from Section I and the layer system from Section III.

### Source of truth (the repo)

```
neural-lace/
│
├── principles/                  Layer 0 — Universal principles, tool-agnostic.
│   ├── core-values.md           Honesty, autonomy, completeness.
│   ├── permission-model.md      6 risk dimensions, 4 tiers, scoring.
│   ├── progressive-autonomy.md  Trust ladder (L1-L5), hard limits.
│   ├── forward-compatibility.md Abstraction rules; what survives tool changes.
│   ├── harness-hygiene.md       No identifiers / credentials / paths in harness code.
│   ├── security-posture.md      Defense in depth.
│   ├── evaluation-discipline.md How to test the harness itself.
│   ├── ux-philosophy.md         User-facing principles.
│   └── diagnosis-protocol.md    Exhaustive diagnosis before fixing.
│
├── patterns/                    Layer 1 — Tool-family-agnostic patterns.
│   ├── rules/                   Rule-system pattern (loaded contextually).
│   ├── hooks/                   Hook-system pattern (lifecycle event handlers).
│   ├── agents/                  Agent-system pattern (specialized sub-agents).
│   ├── templates/               Template-system pattern (plan/decision/report shapes).
│   ├── pipelines/               Pipeline-system pattern (multi-stage build flows).
│   └── risk-profiles/           Risk-scoring data (actions.jsonl).
│
├── adapters/
│   └── claude-code/             Layer 2 — Claude Code adapter.
│       ├── agents/              19 specialized agents (the team).
│       ├── hooks/               ~40 enforcement hooks (the substrate).
│       ├── rules/               Behavioral rules loaded contextually by file pattern.
│       ├── scripts/             close-plan.sh, start-plan.sh, state-summary.sh,
│       │                        session-wrap.sh, write-evidence.sh, find-plan-file.sh,
│       │                        record-test-pass.sh, audit-merged-prs.sh,
│       │                        audit-consistency.ts, validate-links.ts,
│       │                        install-pr-template.sh, install-repo-hooks.sh,
│       │                        read-local-config.sh, harness-hygiene-sanitize.sh
│       ├── work-shapes/         Engineering catalog: build-hook / build-rule /
│       │                        build-agent / author-ADR / write-self-test /
│       │                        doc-migration. Per Build Doctrine Principle 2.
│       ├── skills/              Slash commands (/harness-review, /find-bugs, ...).
│       ├── templates/           plan-template, completion-report, decision-log-entry,
│       │                        findings-template, comprehension-template.
│       ├── patterns/            Hygiene-scan denylist, security-scan patterns.
│       ├── build-doctrine-templates/
│       │                        Universal-floor doctrine templates (Tranche 3 content).
│       ├── examples/            Per-machine config examples.
│       ├── schemas/             JSON Schema (draft 2020-12) for evidence + others.
│       ├── data/                Imperative-patterns library (A7 hook input).
│       └── settings.json.template
│                                Hook wiring (committed; live copy is gitignored).
│
├── docs/                        Strategy, narratives, decisions.
│   ├── architecture-overview.md (THIS FILE) — Tier-3 unified narrative.
│   ├── harness-architecture.md  Tier-4 catalog of every mechanism.
│   ├── harness-strategy.md      Vision, layer model, security maturity.
│   ├── harness-guide.md         File-by-file reference, setup walkthrough.
│   ├── best-practices.md        25+ practices, rationale, enforcement.
│   ├── doc-writing-patterns.md  10 principles for user-facing docs.
│   ├── agent-incentive-map.md   Per-agent failure-mode analysis.
│   ├── build-doctrine-roadmap.md
│   │                            Tranche-by-tranche status.
│   ├── failure-modes.md         Six-field catalog of known failure CLASSES.
│   ├── findings.md              Class-aware ledger of findings (Decision 019).
│   ├── decisions/               ADRs (NNN-<slug>.md) + DECISIONS.md index.
│   ├── plans/                   Active plans + archive/ for terminal-status.
│   ├── discoveries/             Mid-process learnings (YYYY-MM-DD-<slug>.md).
│   ├── reviews/                 UX/audit findings (date-prefixed).
│   ├── sessions/                Session summaries (YYYY-MM-DD-<slug>.md).
│   └── harness-improvements/    enforcement-gap-analyzer proposals.
│
├── evals/                       Harness self-tests.
├── README.md                    Tier-1 front door.
├── SETUP.md                     Tier-2 first-time installer.
└── LICENSE                      MIT.
```

### Deployment artifact (the install target)

Separate from the source-of-truth tree above. `install.sh` symlinks (Linux/macOS) or copies (Windows) adapter files into `~/.claude/`:

```
~/.claude/                       Per-machine deployment of the Claude Code adapter.
├── agents/                      Spawned on demand by the Task tool.
├── rules/                       Loaded contextually by file pattern matcher.
├── hooks/                       Called by settings.json lifecycle hooks.
├── scripts/                     Callable from sessions or shell.
├── templates/                   Referenced during planning.
├── work-shapes/                 Referenced during build.
├── settings.json                Live config (gitignored; per-machine).
├── settings.json.template       Source-of-truth template for re-install.
├── CLAUDE.md                    Global behavioral instructions.
├── sensitive-patterns.local     Personal credential patterns.
├── business-patterns.d/         Team credential patterns (symlinked from private repos).
├── local/                       Personal config (gitignored).
│   ├── accounts.config.json     Multi-account routing.
│   ├── effort-policy.json       Per-account minimum effort level.
│   └── agent-teams.config.json  Agent Teams feature-flag (experimental).
└── state/                       Runtime state (gitignored).
    ├── tool-call-count.<session> Tool-call-budget counters.
    ├── observed-errors.md        Verbatim error capture.
    ├── acceptance/               Runtime acceptance JSON artifacts.
    ├── reviews/                  plan-evidence-reviewer outputs.
    └── user-goals/               First-message goal extraction (Gen 6 / A1).
```

### Find by topic

The tree above shows where things live by directory. The table below shows where to look up by topic — useful when you know what you want but not where it lives.

| Topic | Where to look |
|---|---|
| Anti-vaporware enforcement (rules + hooks + map) | `adapters/claude-code/rules/vaporware-prevention.md` |
| Failure-mode catalog (FM-NNN entries) | `docs/failure-modes.md` |
| Per-agent failure-mode analysis (incentive map) | `docs/agent-incentive-map.md` |
| Plan-closure procedure (deterministic) | `adapters/claude-code/scripts/close-plan.sh` |
| Plan-creation scaffolding | `adapters/claude-code/scripts/start-plan.sh` |
| Mechanical evidence schema + helper | `adapters/claude-code/schemas/evidence.schema.json` + `scripts/write-evidence.sh` |
| Handoff-freshness verification (Layer 5) | `adapters/claude-code/scripts/session-wrap.sh` + `docs/decisions/027-*` |
| State-summary derivation (SCRATCHPAD freshness) | `adapters/claude-code/scripts/state-summary.sh` |
| spawn_task report-back convention | `adapters/claude-code/rules/spawn-task-report-back.md` |
| Discovery protocol (mid-process learnings) | `adapters/claude-code/rules/discovery-protocol.md` + `hooks/discovery-surfacer.sh` |
| Comprehension gate (rung-2+ articulation) | `adapters/claude-code/rules/comprehension-gate.md` + `agents/comprehension-reviewer.md` |
| Acceptance-loop (plan-time + runtime) | `adapters/claude-code/rules/acceptance-scenarios.md` + `agents/end-user-advocate.md` |
| Risk model (6 dimensions, 4 tiers) | `principles/permission-model.md` |
| Progressive autonomy (trust ladder) | `principles/progressive-autonomy.md` |
| Two-layer config (no identity in shareable code) | `principles/harness-hygiene.md` + `hooks/harness-hygiene-scan.sh` |
| Multi-account auto-switching | `adapters/claude-code/scripts/read-local-config.sh` + `examples/accounts.config.example.json` |
| Build Doctrine integration arc status | `docs/build-doctrine-roadmap.md` |
| Decision records (ADRs) index | `docs/DECISIONS.md` (entries at `docs/decisions/NNN-*.md`) |
| Findings ledger (six-field entries) | `docs/findings.md` (validated by `findings-ledger-schema-gate.sh`) |
| Doc-writing principles (this doc tree) | `docs/doc-writing-patterns.md` |

The two trees are connected only by `install.sh`. The repo is the source of truth; `~/.claude/` is the cache. `settings-divergence-detector.sh` (SessionStart hook) surfaces drift between the two.

---

## Cross-references

Every other doc this one points at, with a one-line description.

- [`README.md`](../README.md) — Tier-1 front door; the 30-second skim.
- [`SETUP.md`](../SETUP.md) — Tier-2 install walkthrough.
- [`docs/harness-architecture.md`](harness-architecture.md) — Tier-4 catalog of every hook, agent, script, template.
- [`docs/harness-strategy.md`](harness-strategy.md) — Vision, layer model, security maturity targets.
- [`docs/harness-guide.md`](harness-guide.md) — File-by-file reference for adopters.
- [`docs/best-practices.md`](best-practices.md) — 25+ practices, rationale, where each is enforced.
- [`docs/doc-writing-patterns.md`](doc-writing-patterns.md) — 10 principles for user-facing docs (this doc follows them).
- [`docs/agent-incentive-map.md`](agent-incentive-map.md) — Per-agent failure-mode analysis.
- [`docs/build-doctrine-roadmap.md`](build-doctrine-roadmap.md) — Tranche-by-tranche status.
- [`docs/failure-modes.md`](failure-modes.md) — Catalog of known failure classes.
- [`docs/decisions/027-autonomous-decision-making-process.md`](decisions/027-autonomous-decision-making-process.md) — ADR-027, Layer 1-5 of handoff verification.
- [`principles/permission-model.md`](../principles/permission-model.md) — Risk dimensions, scoring, tiers.
- [`principles/progressive-autonomy.md`](../principles/progressive-autonomy.md) — Trust model, autonomy ladder.
- [`principles/harness-hygiene.md`](../principles/harness-hygiene.md) — No identifiers in harness code; two-layer config.
- [`adapters/claude-code/rules/orchestrator-pattern.md`](../adapters/claude-code/rules/orchestrator-pattern.md) — Multi-task plan dispatch protocol.
- [`adapters/claude-code/rules/acceptance-scenarios.md`](../adapters/claude-code/rules/acceptance-scenarios.md) — Plan-time → runtime → gap-analysis loop.

## Where to go next

Pick the destination matching what you came here to do.

- **Skim-reader** (you wanted 30 seconds, not 15 minutes) → [`README.md`](../README.md).
- **First-time installer** → [`SETUP.md`](../SETUP.md).
- **Mechanism inventory** (you need behavioral spec for a specific hook or agent) → [`docs/harness-architecture.md`](harness-architecture.md).
- **Per-agent failure analysis** (you're debugging an agent's stray-from pattern) → [`docs/agent-incentive-map.md`](agent-incentive-map.md).
- **Per-practice rationale** (you want to know why a specific practice is worth a hook) → [`docs/best-practices.md`](best-practices.md).
- **Doc-writing principles** (you're about to write or revise a doc in this repo) → [`docs/doc-writing-patterns.md`](doc-writing-patterns.md).
- **Build Doctrine status** (you're following the integration arc) → [`docs/build-doctrine-roadmap.md`](build-doctrine-roadmap.md).
- **Decision history** (you want to know why a specific architectural choice was made) → [`docs/DECISIONS.md`](DECISIONS.md) and the per-decision ADRs in [`docs/decisions/`](decisions/).

## Enforcement

This is a Pattern-class doc — not hook-enforced. The discipline of keeping it current lives in [`docs/doc-writing-patterns.md`](doc-writing-patterns.md) principle #4 ("Update-on-ship"). When the team-role mapping, end-to-end flow, or any of the three layer systems materially changes, this doc must be updated in the same change.

Specifically, this doc must be updated when:

- A new agent is added or an existing agent's role changes (Section I role table).
- A new lifecycle hook position is added in the Stop chain or end-to-end flow shifts (Section II numbered steps).
- A new layer system emerges (Section III adds a row to the cross-walk table) — rare, but ADR-027 itself is recent enough that the possibility is open.
- The filesystem layout changes materially (Section IV).
- The `Last verified:` date is more than 90 days old (per principle #5; signal to re-cold-test or update).

If you find this doc wrong, the right fix is: amend the doc, update `Last verified`, and commit in the same change as whatever made it wrong. Don't leave drift; the cost of re-deriving the architecture from `harness-architecture.md`'s catalog is much higher than the cost of keeping this narrative current.
