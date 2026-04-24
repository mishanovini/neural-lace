# Plan: End-User Advocate + Product-Acceptance Loop — Closing the Adversarial-Observation Gap

Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: "Adversarial pre-mortem pattern for plans"

## Goal

Close the structural gap in Gen 4 enforcement: every current mechanism except `pre-stop-verifier.sh` and `tool-call-budget.sh` gates on something the builder itself produces — a plan file, an evidence block, a test assertion, a self-report claim. The builder is the agent that fails at completeness, so self-certification (even via `task-verifier` running the same model) tends to converge on "the builder thinks it's done." The harness currently has no mechanism for **adversarial observation** of the running product from the user's perspective, which is why incomplete builds ship despite a growing stack of enforcement.

This plan introduces a single end-user advocate agent with two invocation modes:

- **Plan-time mode** — reviews every plan as a planner peer alongside `ux-designer` and `systems-designer`. Writes a detailed `## Acceptance Scenarios` section into the plan and flags places where the plan under-specifies user behavior. Gaps are closed before build begins; catching them at plan time costs minutes, not hours.
- **Runtime mode** — executes the scenarios against the running app (dev server or deployed URL) via browser automation (`mcp__Claude_in_Chrome` / Playwright MCP). Returns PASS/FAIL with screenshots + network logs + console logs as non-fakeable artifacts. Session cannot terminate with an ACTIVE plan lacking a PASS artifact.

A supporting `enforcement-gap-analyzer` agent runs on every acceptance failure, reads the session transcript + plan + hooks that fired, and produces a concrete harness improvement proposal (new rule, amended hook, or extended agent remit). Proposals pass through an extended `harness-reviewer` with an explicit generalization check before landing. Every user-visible gap becomes a harness improvement over time, not a one-off fix — the harness becomes self-improving from its own observed failures.

The user-observable outcome: plans that pass plan-time advocate review are materially more complete; builds that pass runtime advocate review actually work from the user's perspective; and multi-task plans can no longer complete with the product in a user-broken state because the session cannot terminate cleanly in that state.

## Scope

### IN

- New agent definition `adapters/claude-code/agents/end-user-advocate.md` with documented plan-time and runtime modes, scenario authoring protocol, and adversarial framing.
- New agent definition `adapters/claude-code/agents/enforcement-gap-analyzer.md` with required `Class of failure:` output field, existing-rule-review-first protocol, and handoff to `harness-reviewer`.
- Extension of `adapters/claude-code/agents/harness-reviewer.md` remit to include generalization-check on enforcement-gap proposals.
- New plan-template sections `## Acceptance Scenarios` and `## Out-of-scope scenarios` in `adapters/claude-code/templates/plan-template.md`.
- Extension of `adapters/claude-code/hooks/plan-reviewer.sh` to require `## Acceptance Scenarios` on plans with user-facing changes (classification heuristic based on `## Files to Modify/Create` patterns).
- **Harness-dev exemption mechanism.** New plan-header field `acceptance-exempt: true` (with required justification on a `acceptance-exempt-reason:` companion field) that opts a plan out of acceptance scenarios. Honored by `plan-reviewer.sh` (skips the requirement) and `product-acceptance-gate.sh` (treats exempt plans as no-artifact-needed). Documented in `acceptance-scenarios.md` with explicit guidance on when to use: harness-dev plans (no product user), pure-infrastructure plans (Dockerfile changes with no user-facing surface), and migration-only plans without UI implications. Not a general escape hatch — exemption requires a substantive reason, audited by `harness-reviewer` if invoked.
- New hook `adapters/claude-code/hooks/product-acceptance-gate.sh` — Stop hook chained after `pre-stop-verifier.sh`, blocking session termination when an ACTIVE plan has no PASS artifact for the current session (unless `acceptance-exempt: true` is declared).
- Artifact schema at `.claude/state/acceptance/<plan-slug>/<session-id>-<timestamp>.json` with screenshots + network logs + console logs as sibling files.
- Rule doc `adapters/claude-code/rules/acceptance-scenarios.md` explaining the full plan-time → runtime → gap-analysis loop.
- Update to `adapters/claude-code/rules/orchestrator-pattern.md` codifying the scenarios-shared-but-assertions-private discipline in builder dispatch prompts.
- Update to `adapters/claude-code/agents/plan-phase-builder.md` reflecting the same discipline.
- Walking-skeleton self-test at `docs/plans/acceptance-loop-smoke-test.md` that exercises the full loop end-to-end.
- Documentation updates: `docs/harness-architecture.md` (new agents + hook rows), `docs/best-practices.md` (new acceptance-loop principle), `adapters/claude-code/CLAUDE.md` (Generation 5 enforcement note).

### OUT

- Replacing `task-verifier` — task-level verification stays unchanged. Product-acceptance is additive, running in parallel per the user's stated preference.
- Replacing `ux-designer` or `systems-designer` — the end-user advocate is a third planner peer, not a replacement for either.
- Conversation-level verbal-vaporware enforcement (the "feature claim without file:line citation in chat" class). That gap requires a Claude Code PostMessage hook that doesn't exist yet; the backlog entry stays open.
- Per-session HMAC signing to close the `tool-call-budget.sh --ack` bypass — acknowledged in backlog, not in scope.
- Automatic browser-automation infrastructure provisioning (Playwright install, Chrome MCP setup). The agents USE existing MCP tools already available in the harness's tool list.
- Full retroactive migration of existing plans to include `## Acceptance Scenarios`. New plans get the section; retroactive application is future work.
- A rule-consolidation audit (triggered every N enforcement-gap proposals) — noted as future work, out of scope here.
- Artifact retention / cleanup automation. A TODO comment in the hook notes the 30-day cleanup convention; automation is deferred.

## Tasks

<!-- [parallel] tasks touch disjoint files; [serial] tasks share files or depend on prior commits -->

### Phase 1 — Walking skeleton (one scenario, end-to-end) [serial]

- [x] A.1 Create stub plan `docs/plans/acceptance-loop-smoke-test.md` with ONE acceptance scenario ("the user can navigate to a given URL and see expected text on the page"). Walking-skeleton target is `python -m http.server 3000` serving the neural-lace repo root, so the scenario is "navigate to http://localhost:3000/README.md and observe the text 'Neural Lace'." Zero code dependency, zero project-app dependency.
- [x] A.2 Draft minimal `adapters/claude-code/agents/end-user-advocate.md` supporting both modes — just enough to execute the smoke scenario. Production hardening in Phase 3.
- [x] A.3 Create `.claude/state/acceptance/` directory convention. Hand-craft a PASS artifact for scenario 1.1 in the schema that Phase 4 will automate.
- [x] A.4 Minimal extension to `adapters/claude-code/hooks/pre-stop-verifier.sh` that detects the PASS artifact and allows session end. Not yet the full production gate — just enough to validate the control flow.
- [x] A.5 Execute the skeleton end-to-end: invoke the agent in plan-time mode on the stub plan → scenario written → invoke in runtime mode against the target page → PASS artifact written → session ends cleanly. Capture evidence in `docs/plans/acceptance-loop-smoke-test-evidence.md`.

### Phase 2 — Plan template + rule pattern [parallel]

- [x] B.1 Extend `adapters/claude-code/templates/plan-template.md` with `## Acceptance Scenarios` and `## Out-of-scope scenarios` sections, including guidance comments in the template that explain what each section should contain and how the end-user advocate will author them.
- [x] B.2 Write `adapters/claude-code/rules/acceptance-scenarios.md` documenting the full loop: plan-time authoring, scenarios-shared/assertions-private discipline, runtime execution, gap-analysis cycle, convergence criteria, and the skip-with-justification path for non-user-facing plans.
- [x] B.3 Update `adapters/claude-code/rules/planning.md` referencing the new rule and clarifying when end-user-advocate is required (every plan by default; skip with justification for docs-only plans).

### Phase 3 — Production end-user-advocate agent [serial, depends on Phase 1]

- [x] C.1 Production `adapters/claude-code/agents/end-user-advocate.md` — full plan-time protocol: read Goal / Scope / UI section / Edge Cases, produce scenario list with step-by-step flows, flag underspecified plan sections, return structured feedback to planner.
- [x] C.2 Production runtime protocol: load scenarios from plan file → execute each via `mcp__Claude_in_Chrome` (Playwright MCP fallback) → capture screenshots + network logs + console logs → write PASS/FAIL artifact. Adversarial framing explicit in the prompt ("you are trying to find reasons this is not actually delivered; assume bugs until you can't find them").
- [x] C.3 Scenario file format specification: structured Markdown within the `## Acceptance Scenarios` section — each scenario has a stable slug ID, numbered user-flow steps, success criteria in prose, optional edge variations. Format is human-authorable and machine-extractable.

### Phase 4 — Runtime acceptance gate [serial, depends on Phase 3]

- [ ] D.1 Production `adapters/claude-code/hooks/product-acceptance-gate.sh` — Stop hook invoked after `pre-stop-verifier.sh` in the hook chain. Blocks session end if ACTIVE plan has unsatisfied acceptance scenarios.
- [ ] D.2 Artifact schema: JSON at `.claude/state/acceptance/<plan-slug>/<session-id>-<timestamp>.json` with `{session_id, plan_commit_sha, scenarios: [{id, verdict, artifacts, assertions_met, failure_reason?}]}`. Sibling files for screenshot / network log / console log per scenario.
- [ ] D.3 Session-to-plan correlation: hook scans all `docs/plans/*.md` with `Status: ACTIVE`, iterates over them, checks each has a satisfying artifact matching current plan_commit_sha.
- [ ] D.4 `--self-test` subcommand exercising: (a) no active plan → PASS, (b) active plan with valid PASS artifact → PASS, (c) active plan with FAIL artifact → BLOCK, (d) active plan with no artifact → BLOCK, (e) active plan with stale artifact (wrong plan_commit_sha) → BLOCK, (f) active plan with valid waiver → PASS.
- [ ] D.5 Waiver mechanism: `.claude/state/acceptance-waiver-<plan-slug>-<timestamp>.txt` with one-line justification. Present → allow stop. Waivers are per-session and do not persist across sessions.
- [ ] D.6 Harness-dev exemption mechanism: `acceptance-exempt: true` plan-header field + `acceptance-exempt-reason: <one-sentence>` companion field. Both `plan-reviewer.sh` and `product-acceptance-gate.sh` honor the exemption (skip requirement, allow stop). Documented in `acceptance-scenarios.md` with explicit when-to-use guidance and the audit expectation (`harness-reviewer` may review exemption rationale). Self-test extends 4.4 with two new scenarios: (g) active plan with valid `acceptance-exempt: true` + reason → PASS, (h) active plan with `acceptance-exempt: true` but no reason → BLOCK with clear message.

### Phase 5 — Enforcement-gap analyzer [serial, depends on Phase 4]

- [ ] E.1 `adapters/claude-code/agents/enforcement-gap-analyzer.md` — reads session transcript + plan + failing scenario + hooks that fired. Required output fields: Title, Date, `Class of failure:`, `Existing rules/hooks that should have caught this:`, `Why current mechanisms missed this:`, `Proposed change (concrete diff or file creation)`, Testing strategy for the new rule.
- [ ] E.2 Prompt discipline: analyzer must review existing rules BEFORE proposing new ones. A missed-catch by an existing rule triggers amendment, not addition. The agent's prompt explicitly states: "if your proposed rule would only fire on this specific bug's exact conditions, reformulate."
- [ ] E.3 Extend `adapters/claude-code/agents/harness-reviewer.md` remit — every `enforcement-gap-analyzer` proposal flows through `harness-reviewer` with an explicit generalization check: too narrow? overlaps existing rule? `Class of failure` substantive? Verdicts: PASS / REFORMULATE / REJECT.

### Phase 6 — Builder discipline (scenarios shared, assertions private) [parallel]

- [ ] F.1 Update `adapters/claude-code/rules/orchestrator-pattern.md` — builder dispatch prompt template explicitly includes the plan's `## Acceptance Scenarios` as SHARED (motivation and what-must-work) but does NOT include the end-user advocate's internal assertion list. New sub-section "Scenarios-shared, assertions-private" codifies the Goodhart rationale.
- [ ] F.2 Update `adapters/claude-code/agents/plan-phase-builder.md` — explicit statement of the discipline in the builder's prompt: "the end-user advocate will execute these flows against the running app before this session can end. You will not see the exact assertions. Build such that the scenarios work for the actual user trying to accomplish them."

### Phase 7 — Self-test + docs [parallel]

- [ ] G.1 Synthetic self-test at `adapters/claude-code/tests/acceptance-loop-self-test.sh` — scripts a known-broken feature scenario, invokes the full pipeline (plan-time advocate catches thin Goal → builder stubs feature → runtime advocate catches broken state → gap-analyzer proposes rule → harness-reviewer verdicts). Asserts each stage fires correctly.
- [ ] G.2 Add the self-test to the weekly `/harness-review` skill.
- [ ] G.3 Update `docs/harness-architecture.md` with rows for `end-user-advocate`, `enforcement-gap-analyzer`, `product-acceptance-gate.sh`.
- [ ] G.4 Update `docs/best-practices.md` with the acceptance-loop principle (adversarial observation, scenarios-shared/assertions-private, gap-analyzer generalization). Include worked example.
- [ ] G.5 Update `adapters/claude-code/CLAUDE.md` Generation 4 mention to reference Generation 5 and this loop.

## Files to Modify/Create

### Create

- `adapters/claude-code/agents/end-user-advocate.md` — new agent with plan-time and runtime modes.
- `adapters/claude-code/agents/enforcement-gap-analyzer.md` — gap-to-rule proposer.
- `adapters/claude-code/hooks/product-acceptance-gate.sh` — Stop hook requiring acceptance artifacts.
- `adapters/claude-code/rules/acceptance-scenarios.md` — pattern doc for the full loop.
- `adapters/claude-code/tests/acceptance-loop-self-test.sh` — synthetic self-test.
- `docs/plans/acceptance-loop-smoke-test.md` + `docs/plans/acceptance-loop-smoke-test-evidence.md` — walking skeleton artifacts.
- `.claude/state/acceptance/` directory convention — documented in the rule doc; not committed.

### Modify

- `adapters/claude-code/agents/harness-reviewer.md` — extended remit for enforcement-gap proposal review.
- `adapters/claude-code/agents/plan-phase-builder.md` — scenarios-shared/assertions-private discipline.
- `adapters/claude-code/hooks/plan-reviewer.sh` — require `## Acceptance Scenarios` on user-facing plans.
- `adapters/claude-code/hooks/pre-stop-verifier.sh` — chain to `product-acceptance-gate.sh`.
- `adapters/claude-code/templates/plan-template.md` — new sections + guidance comments.
- `adapters/claude-code/rules/planning.md` — reference new acceptance-scenarios rule + plan-time advocate requirement.
- `adapters/claude-code/rules/orchestrator-pattern.md` — scenarios-shared discipline.
- `adapters/claude-code/CLAUDE.md` — Generation 5 enforcement mention.
- `docs/harness-architecture.md` — new agents, new hook.
- `docs/best-practices.md` — new acceptance-loop principle.
- `docs/backlog.md` — remove absorbed "Adversarial pre-mortem pattern for plans" entry; update Last updated date.

## Assumptions

- `mcp__Claude_in_Chrome` MCP tools are available in typical harness-equipped sessions (confirmed in the current tool list). Fallback to Playwright MCP (`preview_*` tools also in the tool list) when Chrome MCP is unavailable.
- Plan files are the canonical input to the end-user advocate. The advocate reads the plan's Goal / Scope / Edge Cases / UI section and writes scenarios into the same file. No separate scenario file format.
- The walking skeleton can run against `python -m http.server 3000` serving the neural-lace repo root, so the smoke test has no project-app dependency. Python is assumed available in the harness environment (it ships with most macOS, Linux, and Windows-with-Git-Bash setups).
- `pre-stop-verifier.sh` is the correct hook-chain entry point for a new Stop-hook gate. Confirmed by existing pattern: `bug-persistence-gate.sh` and `narrate-and-wait-gate.sh` also chain into Stop hook behavior.
- The `harness-reviewer` agent's existing prompt can be extended to include enforcement-gap-proposal review without breaking its current remit (it already reviews rule/agent/hook changes; enforcement-gap proposals are a natural subset).
- This meta-plan is bootstrap-excluded from end-user-advocate review at plan-time because the agent doesn't exist yet. It is ALSO acceptance-exempt by virtue of being a harness-dev plan (no product user; `acceptance-exempt: true` would apply if the mechanism existed at plan creation time — it's added by Task 4.6 of this plan itself, which is the bootstrap chicken-and-egg this plan resolves). Subsequent harness-dev plans (e.g., the Phase 7 self-test plan) will declare `acceptance-exempt: true` explicitly. Subsequent product plans (in downstream projects) will undergo full plan-time + runtime advocate review.
- "Plans with user-facing changes" is a classifiable property. Classification heuristic: a plan is user-facing if any file in `## Files to Modify/Create` matches `src/app/**/*.tsx`, `src/components/**/*.tsx`, `src/app/**/page.tsx`, or similar patterns. Backend-only plans can opt in voluntarily but are not required.
- Assumes the existing four ACTIVE plans (`failure-mode-catalog.md`, `capture-codify-pr-template.md`, `claude-remote-adoption.md`, `plan-deletion-protection.md`) will either be reconciled (marked DEFERRED / COMPLETED) or accepted as concurrent in-flight work before this plan's implementation begins. This plan does not supersede them.
- Browser automation runs against a local dev server (`http://localhost:3000`) by default. Deployed-URL runs are supported but treated as a separate invocation pattern (advocate prompt reads a `target_url` scenario field).

## Edge Cases

- **Plan-time advocate proposes scenarios the plan can't reasonably cover.** Handled by `## Out-of-scope scenarios` — advocate proposes, planner accepts/rejects each with rationale. Rejected items become documented exclusions, not silent omissions. This prevents "acceptance must pass" from becoming unbounded and blocking every plan.
- **Runtime scenarios obsoleted as code evolves.** Scenarios are versioned with the plan; if a scenario is obsolete, it must be explicitly removed from the plan via commit (not silently skipped). The runtime agent treats missing-scenario-implementation as FAIL, not SKIP.
- **Browser automation flakiness causes false FAILs.** Retry policy: 2 retries per scenario with fresh browser context. Persistent FAIL (3 attempts) counts as FAIL. Transient FAIL (1-2 retries then PASS) is logged but doesn't block.
- **Acceptance artifact from a stale session satisfies a new plan.** Artifact schema includes `plan_commit_sha`. Hook rejects artifacts whose `plan_commit_sha` is older than the current plan file's HEAD SHA.
- **Builder sees assertions via tool call inspection.** The orchestrator pattern explicitly excludes assertion content from dispatch prompts. The advocate's runtime mode runs in a separate sub-agent session; its internal state does not propagate to the builder.
- **Enforcement-gap analyzer proposes a rule that breaks existing functionality.** `harness-reviewer` + self-test suite + pre-commit hygiene scan catch this. Proposals are drafts requiring review before commit, not auto-applied.
- **Gap analyzer floods with 20 narrow proposals over 20 sessions.** `harness-reviewer`'s generalization check prevents most duplication. Every 10th proposal also triggers a rule-consolidation audit (future work; captured as a backlog item in the completion report).
- **Multiple plans ACTIVE simultaneously, each with its own acceptance artifact.** Hook's session-to-plan correlation iterates over ALL ACTIVE plans; EACH must have a satisfying artifact. Session end blocked if any lacks one. Covers current concurrent-plan state.
- **Plan has zero user-facing changes (pure docs).** Plan-reviewer classification skips the acceptance-scenarios requirement. The plan MAY include the section with a single "n/a — docs-only plan" entry for auditability.
- **Dev server not running during runtime invocation.** Runtime agent first checks `curl -s http://localhost:3000/api/health` (or equivalent). If unreachable, writes FAIL artifact with reason "dev server not running" rather than producing spurious scenario failures.
- **Scenario references a feature behind a feature flag the builder didn't enable.** Counts as FAIL. Plan-time advocate should have caught this; if missed, runtime FAIL triggers gap-analyzer which proposes "plan-reviewer checks scenarios for feature-flag mentions."
- **Builder games scenarios by pattern-matching flow descriptions.** Mitigation: scenarios describe FLOWS (what the user does + intends to accomplish), not exact strings. Runtime assertions (private) use semantic checks where possible (e.g., "the order-total equals the input sum" rather than "the page contains '$42.17'").
- **Waiver abuse — user writes waivers rather than fixing bugs.** Every waiver logged in the commit that exits the session. Weekly `/harness-review` surfaces waiver frequency; chronic waivers trigger a review of the underlying bug or the gate itself.

## Testing Strategy

- **Phase 1 (walking skeleton)** is itself the first live test of the full loop. Evidence in `docs/plans/acceptance-loop-smoke-test-evidence.md`.
- **Phase 4 hook** ships with `--self-test` subcommand exercising pass/block/stale-artifact/waiver paths (pattern matches existing `plan-reviewer.sh --self-test`).
- **Phase 5 agents** tested via scripted invocation on a known-failing scenario. Asserts `enforcement-gap-analyzer` produces a proposal with all required fields; asserts `harness-reviewer` REFORMULATEs an over-narrow proposal.
- **Phase 7.1 synthetic self-test** is the continuous test of the full pipeline. Runs weekly via `/harness-review`. Any regression (advocate stops catching stub broken feature) fails the weekly audit.
- **Integration test for the full loop**: scripted scenario-driver at `adapters/claude-code/tests/acceptance-loop-self-test.sh` invokes each agent in sequence and asserts expected artifacts. Run before every commit touching these files.
- **No test-skip escape hatches** per `no-test-skip-gate.sh`. If a scenario can't be tested, the test FAILs with a specific reason; the fix is to make it testable.

## Walking Skeleton

The thinnest slice that exercises every architectural layer is Phase 1: one scenario flows from plan-time authoring → plan file → runtime browser-automation execution → PASS artifact → Stop-hook recognition → clean session end. This validates that the plan file is the correct shared state, that the agent's two modes can share logic, that the hook chain allows gate insertion, and that the artifact schema is sufficient for re-reading by the hook. Everything else (production agents, gap analyzer, docs) layers on top of this skeleton.

First task: **Task 1.1** — create the stub plan with one acceptance scenario.

## Decisions Log

*Populated during implementation — see Mid-Build Decision Protocol.*

## Definition of Done

- [ ] All tasks checked off (via `task-verifier` agent per the mandate)
- [ ] All hook self-tests pass (including `product-acceptance-gate.sh --self-test`)
- [ ] Integration test `acceptance-loop-self-test.sh` exits 0
- [ ] Walking skeleton PASS artifact exists in `docs/plans/acceptance-loop-smoke-test-evidence.md`
- [ ] SCRATCHPAD.md updated with final state
- [ ] `docs/harness-architecture.md` reflects new agents + hook
- [ ] `docs/best-practices.md` references the acceptance-loop principle
- [ ] `docs/DECISIONS.md` has entries for every Tier 2+ decision from this plan
- [ ] Completion report appended to this plan file, including absorbed-backlog-item status
- [ ] `systems-designer` PASS verdict on this plan (required before implementation begins per design-mode protocol)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

**Within the session that a multi-task plan is built, before that session can end: (a) the plan contains a `## Acceptance Scenarios` section authored by the end-user advocate at plan-time and revised to close any gaps the advocate flagged; (b) a `.claude/state/acceptance/<plan-slug>/<session-id>-*.json` artifact exists with `verdict: PASS` covering every in-scope scenario (or the plan's Status is ABANDONED / DEFERRED, or an explicit waiver file exists); (c) every scenario in that artifact has a corresponding screenshot + network log + console log on disk as non-fakeable evidence.** The user-observable outcome from the harness maintainer's perspective: multi-task plans can no longer complete with the product in a user-broken state, because the session cannot terminate cleanly in that state.

Secondary outcome: over a rolling 30-day window, every runtime acceptance FAIL generates an `enforcement-gap-analyzer` proposal committed under `docs/harness-improvements/`. The harness's rule set observably grows from observed failures, measurable by counting entries added per month.

Failure mode for the outcome: the user experiences a session that cannot end ("hook is blocking me") when the work genuinely is done. Mitigation: `product-acceptance-gate.sh` emits a clear message naming the missing scenario(s) and pointing at the end-user advocate invocation command. Escape hatch: `.claude/state/acceptance-waiver-<plan-slug>-<timestamp>.txt` with a one-line justification (mirrors the existing `bug-persistence-gate.sh` waiver pattern).

### 2. End-to-end trace with a concrete example

Consider a future plan: "Add a Duplicate Campaign button to the campaigns list page." The trace:

**T=0, plan creation.** Maintainer drafts `docs/plans/campaign-duplicate.md` with Mode: code, Status: ACTIVE, Goal / Scope / Tasks populated, `## Acceptance Scenarios` present but contains only `[populate me]`. Commit attempt blocked by `plan-reviewer.sh` because the section is a placeholder (existing enforcement, extended in Phase 2.1 to cover the new section).

**T=1, invoke end-user-advocate in plan-time mode.** Task tool invocation with plan path + `mode=plan-time`. Agent reads the plan, identifies three scenarios from the Goal: (a) clicking Duplicate creates a copy with the same fields; (b) the copy's name has "(Copy)" suffix; (c) the original is unchanged. Agent ALSO flags a gap: plan doesn't specify what happens to the scheduled send time on the copy. Returns scenario list + one gap.

**T=2, planner resolves gap.** Maintainer adds Decision: "Copied campaign has scheduled send time cleared (unscheduled draft)." Updates Scope IN. Re-invokes advocate; advocate confirms no remaining gaps, writes 3 scenarios + 1 `## Out-of-scope scenarios` entry ("sending the copy immediately — separate flow").

**T=3, commit plan.** `plan-reviewer.sh` sees substantive `## Acceptance Scenarios` content → allow. `backlog-plan-atomicity.sh` enforces absorption → allow. Plan committed on feature branch.

**T=4, build.** Builder (plan-phase-builder sub-agent) sees the 3 scenarios in its dispatch prompt (Phase 6.1 discipline) but NOT the advocate's internal assertion list. Builds the feature, commits, task-verifier PASSes the task.

**T=5, Stop-hook triggers.** `pre-stop-verifier.sh` passes (evidence blocks present, task-verifier PASSes recorded). `product-acceptance-gate.sh` fires next in the chain: reads ACTIVE plan `campaign-duplicate.md`, finds 3 scenarios, looks for `.claude/state/acceptance/campaign-duplicate/*.json` artifact for current session. None found. Hook BLOCKS session end with stderr: "End-user advocate runtime review not performed. Run: `Task tool: end-user-advocate, mode=runtime, plan=docs/plans/campaign-duplicate.md`."

**T=6, runtime execution.** Maintainer (or orchestrator if autonomous) invokes advocate in runtime mode. Agent reads scenarios, spawns browser via `mcp__Claude_in_Chrome`, navigates to campaigns list, clicks Duplicate on a test campaign, checks: copy exists, name has "(Copy)" suffix, scheduled time cleared, original unchanged. Captures screenshots per step. Writes artifact: `.claude/state/acceptance/campaign-duplicate/s-8341-2026-04-25T14-22Z.json` with 3 scenarios all PASS, plan_commit_sha=<current HEAD>.

**T=7, Stop-hook re-run.** Gate finds the artifact, validates plan_commit_sha matches current plan HEAD, verdict is PASS → allow stop. Session closes.

**Divergent trace — runtime FAIL at T=6.** Advocate finds scheduled time is NOT cleared on the copy. Writes FAIL artifact. Hook remains blocking. `enforcement-gap-analyzer` auto-invoked with transcript + plan + FAIL artifact. Analyzer reads: task-verifier PASSED the build, but runtime FAILed the outcome. Produces proposal: "Class of failure: verifier confused 'code path exists' with 'code path produces correct state.' Proposed change: add to task-verifier prompt 'when task involves form state transitions, verifier must explicitly check state after action, not just that action fires.'" `harness-reviewer` verdicts PASS (substantive class, doesn't duplicate existing rule). Proposal committed as `docs/harness-improvements/2026-04-25-task-verifier-state-transition.md`. Maintainer re-opens plan, fixes code, re-runs advocate, eventually PASSes and session ends.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| Plan file `## Acceptance Scenarios` section | End-user-advocate runtime mode | Structured Markdown per scenario file format spec (Phase 3.3). Each scenario has: stable slug ID, numbered user-flow steps, prose success criteria, optional edge variations. Soft cap ≤ 20 scenarios per plan; hard cap 50 (advocate refuses to author more). UTF-8, no embedded HTML. Parseable by Markdown-aware tools. |
| End-user-advocate plan-time | Plan file | Appends / replaces `## Acceptance Scenarios` and `## Out-of-scope scenarios` sections atomically. Also returns a structured `## Plan-Time Advocate Feedback` block with gap list. Feedback may live in the plan temporarily (during resolution) or in a sibling `<plan-slug>-advocate-feedback.md`. |
| End-user-advocate runtime | `.claude/state/acceptance/<plan-slug>/` | JSON file per run, schema: `{session_id, plan_commit_sha, started_at, ended_at, scenarios: [{id, verdict: PASS|FAIL, artifacts: {screenshot, network_log, console_log}, assertions_met, failure_reason?}]}`. Sibling files stored in same directory. Total size ≤ 10MB per run (soft cap). |
| `product-acceptance-gate.sh` | Claude Code Stop hook chain | Exit 0 to allow stop; non-zero with stderr message to block. Invoked AFTER `pre-stop-verifier.sh`. Timeout: 30s. Read-only file access only. |
| `enforcement-gap-analyzer` | `harness-reviewer` → `docs/harness-improvements/NNN-*.md` | Structured Markdown with required fields: Title, Date, `Class of failure:`, `Existing-rule review:`, `Why current mechanisms missed this:`, Proposed change (diff or file creation), Testing strategy. ≤ 2000 tokens. Handed via Task tool. |
| `harness-reviewer` (extended) | Proposal commit (PASS) or reformulation loop | Verdicts: PASS / REFORMULATE / REJECT. PASS → proposal committed as draft PR under `docs/harness-improvements/`. REFORMULATE → returned to analyzer with specific gap. REJECT → logged in `.claude/state/rejected-proposals.log` to prevent retry. |
| Waiver file | `product-acceptance-gate.sh` | `.claude/state/acceptance-waiver-<slug>-<ts>.txt` with one non-empty line justifying the waiver. Presence allows stop for this session only. File is per-session ephemeral by convention (not committed). |

### 4. Environment & execution context

**Main session (orchestrator).** Working directory is project repo. Env: standard Claude Code harness (gh authenticated, Supabase configured per account-switching hook). All deferred tools available via ToolSearch, including `mcp__Claude_in_Chrome__*`.

**End-user-advocate plan-time invocation.** Sub-agent session spawned via Task tool. Fresh context. Reads: plan file, referenced rule files, existing project code for grounding. Writes: edits to plan file's Acceptance Scenarios sections. Does NOT need browser access — plan-time is paper review. No state persisted outside the plan file.

**End-user-advocate runtime invocation.** Sub-agent session spawned via Task tool with `run_in_background: false`. Reads: plan file, scenarios. Executes: browser automation against running dev server (`http://localhost:3000` typical) or deployed URL. Requires `mcp__Claude_in_Chrome__*` tools available in the sub-agent's tool set. Writes: artifact JSON + sibling screenshots/logs under `.claude/state/acceptance/<plan-slug>/`.

**`product-acceptance-gate.sh` execution.** Runs in standard Stop hook chain. Cwd is project repo. Env has standard hook vars (`CLAUDE_SESSION_ID`, `CLAUDE_HOOK_REASON`, etc.). Read-only disk access to `.claude/state/acceptance/`, read-only to `docs/plans/*.md` and git state. Max execution time: 30s (enforced by Claude Code hook timeout).

**Persistent vs ephemeral:** `.claude/state/acceptance/` is ephemeral per-session by convention (gitignored). Plan files and `docs/harness-improvements/` are persistent (git-tracked). Screenshots + logs retained 30 days by convention; automated cleanup is future work.

**Cross-machine portability:** state directory is local; if a session starts on machine A and continues on machine B, the artifact doesn't transfer. In practice, sessions complete on one machine. The `claude --remote` adoption plan (if completed first) would require adapting this — out of scope here.

### 5. Authentication & authorization map

- **End-user-advocate runtime → dev server.** Localhost, no auth required. Deployed-URL variant requires project session auth — scenarios must declare auth prerequisites (e.g., "assume logged-in user with Manager role"). Auth seeding uses project's test-user API (e.g., `POST /api/test/impersonate` in dev mode). Project-specific; documented in the scenario file format spec.
- **End-user-advocate → browser automation MCP.** `mcp__Claude_in_Chrome` uses the user's existing Chrome browser auth state. No new credentials. Rate limits: driven by browser throughput, no API layer.
- **`enforcement-gap-analyzer` → git commits (via `harness-reviewer`).** Proposals commit to a feature branch under the user's existing git identity. No new tokens.
- **`product-acceptance-gate.sh` → file system.** Reads `.claude/state/` and `docs/plans/`. No external auth.
- **Waiver file** has no auth — any session can create one. Accountability via the commit that exits the session including the waiver filename and justification in the commit message.

No new secrets, API keys, or tokens are introduced. All externally-authenticated operations piggyback on existing harness credentials.

### 6. Observability plan (built before the feature)

Every step emits a log line with an `[acceptance]` or `[acceptance-gate]` prefix to stdout, captured in session transcripts:

- **Plan-time invocation**: `[acceptance] plan-time mode on <plan-path>; found N scenarios, M gaps flagged`
- **Plan-time re-review**: `[acceptance] plan-time re-review on <plan-path>; N scenarios confirmed, 0 gaps remain`
- **Runtime invocation**: `[acceptance] runtime mode on <plan-path> at <timestamp>; scenarios: [s1, s2, s3]`
- **Per-scenario progress**: `[acceptance] scenario s1 start → step 1/5: navigate to /campaigns → PASS (1.2s)`
- **Scenario outcome**: `[acceptance] scenario s1 PASS (4.3s), 3/3 assertions met, artifacts at .claude/state/acceptance/<slug>/<file>.json`
- **Artifact write**: `[acceptance] wrote artifact at <path>, 3 PASS / 0 FAIL, total 11.2s`
- **Gate PASS**: `[acceptance-gate] plan <slug>: artifact <path> matches current plan_commit_sha <sha>, verdict PASS → allow stop`
- **Gate BLOCK**: `[acceptance-gate] blocking session end: plan <slug> has no PASS artifact; scenarios awaiting runtime review: [s1, s2]`
- **Gap-analyzer invocation**: `[gap-analyzer] analyzing FAIL on plan <slug>, scenario <id>; reading transcript (N tool calls) + N hooks fired`
- **Gap-analyzer output**: `[gap-analyzer] proposal written to .claude/state/gap-proposals/<timestamp>.md; Class of failure: <class>; handing to harness-reviewer`
- **harness-reviewer verdict**: `[harness-reviewer] proposal <id> PASS / REFORMULATE / REJECT; reason: <...>`

Structured logs (JSONL) also written to `.claude/state/acceptance/<slug>/run-log.jsonl` for programmatic analysis. A full run can be reconstructed from transcripts alone by grepping these prefixes.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / retry | Escalation |
|---|---|---|---|---|
| Plan-time advocate invocation | Agent times out while reading plan | No scenarios written; plan-reviewer still blocks | Re-invoke; if persists, manually script scenarios | Gap-analyzer proposes improvements to advocate prompt for long plans |
| Plan-time advocate invocation | Agent misreads Goal, writes wrong scenarios | Scenarios don't match user intent | Planner rejects via re-invocation with clarifying prompt | Post-hoc gap-analyzer reviews advocate accuracy |
| Plan-time gap resolution | Planner ignores advocate gap, commits anyway | plan-reviewer allows; runtime FAIL catches later | Normal flow — runtime IS the safety net | Gap-analyzer proposes stricter plan-reviewer rule to block commits with unresolved advocate gaps |
| plan-reviewer.sh new check | False positive on valid content | Plan commit blocked incorrectly | File hook bug report | Fix regex in plan-reviewer.sh |
| plan-reviewer.sh new check | False negative (allows placeholder) | Bad plan proceeds | Runtime advocate catches it | Strengthen content check |
| Runtime advocate — server not running | `curl /api/health` fails | FAIL artifact "dev server not running" | User starts server, re-runs | Gate error message educates user |
| Runtime advocate — browser MCP unavailable | Task tool invocation fails | Agent error, no artifact | Fall back to Playwright MCP | If both unavailable, block with install instructions |
| Runtime advocate — browser flake | Selector not found on first try | 1-2 retries logged, eventually PASS | Built-in 2-retry policy | Escalation after 3 attempts → FAIL with flake diagnosis |
| Runtime advocate — scenario genuinely fails | Assertion fails; FAIL artifact | FAIL with screenshot + reason | Builder fixes code, re-runs | Iteration cap after N FAILs on same scenario → escalate to user |
| Runtime advocate — screenshot capture fails | Missing artifact file | FAIL due to missing artifacts | Retry capture | Disk space check; Chrome MCP bug report |
| Artifact write | Disk full | Write error | Retry; fail clearly | User clears space; gate remains blocking |
| Artifact write | Permissions error | Write error | Check `.claude/state/` perms | Fix and retry |
| Gate — stale artifact | plan_commit_sha mismatch | Block despite artifact present | User re-runs advocate against current HEAD | Normal flow |
| Gate — no ACTIVE plan | No plans to check | Allow session end (PASS by default) | N/A | N/A |
| Gate — hook timeout | 30s exceeded | Fail open per Claude Code convention | Optimize file reads | Bug report if persistent |
| Gap-analyzer | Proposal lacks required field | harness-reviewer REFORMULATE | Analyzer re-invoked with gap callout | Normal flow |
| Gap-analyzer | Proposal duplicates existing rule | harness-reviewer REJECT | Discarded; logged to prevent retry | Normal flow |
| Gap-analyzer | Over-narrow proposal | harness-reviewer REFORMULATE with generalization gap | Analyzer re-prompted | After 3 REFORMULATEs on same failure, escalate to user |
| harness-reviewer | Drifts and approves narrow proposals | Rule bloat over time | Weekly `/harness-review` audit catches drift | Rework harness-reviewer prompt |
| Waiver | User creates waiver to bypass genuine failure | Product ships broken despite gate | Waiver requires one-line reason, logged in commit | Weekly review of waivers; chronic use → investigate |
| Waiver | Waiver left in state from previous session | Prevents gate from firing | Convention: waivers are per-session, timestamp-gated | Gate rejects waivers older than session start timestamp |

### 8. Idempotency & restart semantics

- **Plan-time advocate re-invocation** is idempotent: re-running on same plan reads current Acceptance Scenarios and either confirms ("no new gaps") or proposes revisions. Does not duplicate — extends or replaces atomically.
- **Runtime advocate re-invocation** writes a new artifact per run. Gate looks for ANY artifact matching current plan_commit_sha with verdict PASS; multiple runs fine. Stale artifacts (plan_commit_sha mismatch) ignored.
- **Partial runtime runs** (scenarios 1-2 PASS, crash before 3) write partial artifact with verdict FAIL and `partial: true` flag. Re-running starts from scenario 1 (no cross-scenario state). Safe because scenarios are independent by design.
- **`product-acceptance-gate.sh` restart** is trivially idempotent — pure read-only file check.
- **Enforcement-gap-analyzer re-run on same failure**: if proposal for this Class of failure already exists in `docs/harness-improvements/`, analyzer skips (detected by class matching). Otherwise produces one. Safe to re-run.
- **Artifact directory partial state**: if `.claude/state/acceptance/<slug>/` has only some scenarios' artifacts (run interrupted), gate sees incomplete set and blocks. User re-runs; new run produces complete set.
- **Session crash mid-runtime-run**: worst case, browser left in non-clean state. Next run starts fresh browser context (explicit in advocate init sequence). State ephemeral; no corruption possible.
- **Waiver persistence**: waivers are timestamped and convention-bound per-session. Gate rejects waivers older than session start. Prevents silent authorization of future sessions.

### 9. Load / capacity model

- **Scenarios per plan**: soft cap 20; typical 3-8; hard cap 50 (advocate refuses more).
- **Scenario runtime**: ~5-30s per scenario. 10 scenarios × 20s ≈ 200s per full acceptance run.
- **Disk usage**: ~500KB per scenario (screenshot + network log + console log). 10 scenarios ≈ 5MB per artifact. Weekly cleanup of > 30-day artifacts (future work) bounds directory to ~200MB under normal load.
- **Bottleneck**: `mcp__Claude_in_Chrome` throughput. Browser serializes actions (single instance). Can't parallelize scenarios within one run. Parallelize ACROSS runs by running multiple plans' acceptance runs in separate sessions.
- **At saturation**: single session runs N scenarios serially; if N > 50, advocate refuses. Multi-plan: gate iterates over all ACTIVE plans; blocks if any unsatisfied. No global saturation.
- **Hook overhead**: O(N) plan files + O(M) artifact files per Stop event. N=4 active plans × M=10 scenarios ≈ 40 file reads per Stop. < 100ms typical.
- **Gap-analyzer throughput**: invoked per runtime FAIL. Chronically-broken build = 10 failures = 10 proposals; harness-reviewer dedupes most as "existing class." Weekly audit catches any buildup.
- **No external API rate limits** — everything local against dev server or user's browser.

Graceful degradation: if `mcp__Claude_in_Chrome` unavailable → fall back to Playwright MCP. If both unavailable → advocate writes `ENVIRONMENT_UNAVAILABLE` verdict; gate treats as BLOCK with install message. User can waive with justification.

### 10. Decision records & runbook

**Decisions requiring records in `docs/decisions/NNN-*.md`:**

1. **Single-agent-two-modes vs two-agents** — chose single `end-user-advocate` with plan-time and runtime modes. Alternatives: separate `user-journey-reviewer` and `product-acceptance-runner`. Rejected because modes share ~70% of prompt context (persona, user-flow framing); forcing duplication causes drift. Tradeoff: agent prompt longer; mitigated by explicit mode dispatch at top.

2. **Assertions-private vs assertions-shared with builders** — chose private. Alternatives: fully transparent, fully opaque. Rejected transparent because LLM builders teach-to-the-test extremely easily. Rejected opaque because builders underspec. Tradeoff: slight orchestration complexity; worth the robustness.

3. **Parallel-across-the-board vs UI-only acceptance** — chose parallel (every plan). Alternative: UI plans only. Rejected because backend changes silently break UI three files away (silent-integration-bug class). Tradeoff: more acceptance runs per plan; acceptable per user's stated quality bias.

4. **Standalone hook vs extending `pre-stop-verifier.sh`** — chose standalone `product-acceptance-gate.sh` chained after. Alternative: inline extension. Rejected because pre-stop-verifier is already large; violates single-responsibility. Tradeoff: two hooks to maintain; worth clarity.

5. **Artifact format: JSON vs Markdown** — chose JSON for machine parsing, with screenshots/logs as siblings. Markdown-embedded base64 rejected because it bloats files and makes diffs useless.

6. **Waiver mechanism: file-based vs commit-message sentinel** — chose file. Commit messages don't exist at session-end-time (commits happen mid-session); file-based works in the right temporal window.

7. **Meta-plan bootstrap** — this plan is itself not reviewed by end-user advocate at plan-time because the agent doesn't exist. Documented in Assumptions. Future plans (including Phase 1 smoke test) WILL undergo advocate review.

**Runbook entries:**

- **Symptom**: session won't end — gate keeps blocking. **Diagnostic**: (1) run `product-acceptance-gate.sh --self-test`; (2) read gate stderr for scenario list; (3) check `.claude/state/acceptance/<slug>/` for recent artifacts. **Fix**: re-run end-user-advocate in runtime mode; if FAIL, address failing scenario; if all PASS, verify plan_commit_sha matches HEAD. **Escalation**: waiver if genuinely unachievable.

- **Symptom**: advocate proposes impossible-to-implement scenarios. **Diagnostic**: read `## Plan-Time Advocate Feedback`. **Fix**: add rejected scenarios to `## Out-of-scope scenarios` with rationale; re-invoke for confirmation. **Escalation**: advocate prompt-tightening via gap-analyzer if this recurs.

- **Symptom**: runtime FAILs on a scenario that passes manually. **Diagnostic**: read artifact's failure_reason + screenshot. **Common causes**: selector changed, auth state differs (clean browser), timing flake. **Fix**: use semantic assertions instead of brittle selectors; ensure auth seeding in scenario preamble.

- **Symptom**: gap-analyzer keeps proposing over-narrow rules. **Diagnostic**: recent harness-reviewer verdicts. **Fix**: tighten analyzer prompt's Class-of-failure requirement (require class to cover ≥ 2 distinct hypothetical instances). **Escalation**: if > 50% REFORMULATE rate, rework analyzer prompt.

- **Symptom**: plan has `## Acceptance Scenarios` but advocate still returns gaps. **Diagnostic**: advocate feedback — gap is often about scenario coverage (Goal implies a scenario you didn't write). **Fix**: add scenarios OR move to `## Out-of-scope scenarios`. Normal flow.

- **Symptom**: harness-reviewer approves a proposal that conflicts with existing rule. **Diagnostic**: read both rules side-by-side. **Fix**: merge into consolidated rule; add test distinguishing. **Escalation**: review harness-reviewer prompt's existing-rule-awareness.
