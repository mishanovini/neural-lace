# Plan: Agent-Driven Functionality Verification Pipeline
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; self-tests are the acceptance artifact
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

Build a formal agent-driven verification pipeline that runs BEFORE any task can be declared done. The pipeline composes four agents — functionality-verifier (NEW), end-user-advocate (existing, role clarified for pipeline), claim-reviewer (existing, role clarified for pipeline), domain-expert-tester (existing, role clarified for pipeline) — sequenced so the cheapest mechanical check fires first and the most expensive adversarial check fires last.

Closes the load-bearing harness gap: sessions repeatedly build components that compile and pass unit tests but don't work as functionality. Wire-checks, static traces, integration verification, and plan enrichment all gate on what was WRITTEN. The new functionality-verifier gates on USE — does a user-shaped exercise of the feature actually produce the user-shaped outcome.

## User-facing Outcome

A maintainer running the harness for a UI / API / webhook / migration task can no longer mark the task complete by citing only typecheck and component tests. Before `task-verifier` flips the checkbox, an agent must have demonstrated the user-observable path — clicking the button, calling the endpoint, sending a real message — and produced PASS evidence.

For harness work itself, the "user" is the maintainer; the agent's `--self-test` PASSING is the equivalent functionality demonstration. The pipeline composes uniformly across product code and harness code.

## Scope

- IN: New agent file `adapters/claude-code/agents/functionality-verifier.md`.
- IN: New rule `adapters/claude-code/rules/verification-pipeline.md` documenting pipeline order, when each agent runs, and how task-verifier gates on functionality-verifier evidence.
- IN: New orchestration script `adapters/claude-code/pipeline-templates/verify-functionality.sh` that sequences the pipeline for the maintainer who wants to run it explicitly. The script is the manual entrypoint; `task-verifier`'s extension is the auto-firing path.
- IN: Updates to `adapters/claude-code/agents/end-user-advocate.md`, `adapters/claude-code/agents/claim-reviewer.md`, `adapters/claude-code/agents/domain-expert-tester.md` clarifying each agent's role within the new pipeline (added section: `## Role in the Verification Pipeline`).
- IN: Update to `adapters/claude-code/agents/task-verifier.md` to require functionality-verifier evidence for `Verification: full` runtime tasks.
- IN: Update to `docs/harness-architecture.md` documenting the pipeline and the new agent.
- IN: Live-mirror sync (every changed file copied to `~/.claude/<same-path>`).
- OUT: Hook-enforced auto-invocation of every pipeline step. The orchestrator + task-verifier compose them by discipline (Pattern); only the functionality-verifier requirement is hardened at task-verifier dispatch time (Mechanism). Auto-firing of claim-reviewer / end-user-advocate runtime / domain-expert-tester from a single PreToolUse hook is out of scope — those gates already exist via their own mechanisms (Stop-hook product-acceptance-gate for end-user-advocate; self-invocation for claim-reviewer; manual invocation for domain-expert-tester).
- OUT: A new MCP-driven runtime harness. functionality-verifier uses the same browser-MCP fallback chain as end-user-advocate (`mcp__Claude_in_Chrome__*` → `mcp__Claude_Preview__*` → ENVIRONMENT_UNAVAILABLE artifact).
- OUT: Changes to existing hooks. `task-verifier.md` extension is prose-level guidance to the agent; the mechanical evidence-block check at `plan-edit-validator.sh` already enforces the format the new agent's evidence satisfies.

## Tasks

- [ ] 1. Create `adapters/claude-code/agents/functionality-verifier.md` — Verification: mechanical
- [ ] 2. Create `adapters/claude-code/rules/verification-pipeline.md` — Verification: mechanical
- [ ] 3. Update `adapters/claude-code/agents/task-verifier.md` to add functionality-verifier requirement for `Verification: full` runtime tasks — Verification: mechanical
- [ ] 4. Update `adapters/claude-code/agents/end-user-advocate.md`, `claim-reviewer.md`, `domain-expert-tester.md` with `## Role in the Verification Pipeline` sections — Verification: mechanical
- [ ] 5. Create `adapters/claude-code/pipeline-templates/verify-functionality.sh` orchestration script with `--self-test` — Verification: mechanical
- [ ] 6. Update `docs/harness-architecture.md` (Agents table + new section "Functionality Verification Pipeline") — Verification: mechanical
- [ ] 7. Sync to live mirror at `~/.claude/`; verify byte-identical via `diff -q` — Verification: mechanical
- [ ] 8. Run `harness-hygiene-scan --self-test` and the new pipeline script's `--self-test` — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/agents/functionality-verifier.md` — new agent file (defines the agent that USES the feature as a user)
- `adapters/claude-code/rules/verification-pipeline.md` — new rule documenting pipeline composition
- `adapters/claude-code/pipeline-templates/verify-functionality.sh` — new orchestration script
- `adapters/claude-code/agents/task-verifier.md` — add `## Functionality-verifier requirement (Verification: full)` section
- `adapters/claude-code/agents/end-user-advocate.md` — add `## Role in the Verification Pipeline` section
- `adapters/claude-code/agents/claim-reviewer.md` — add `## Role in the Verification Pipeline` section
- `adapters/claude-code/agents/domain-expert-tester.md` — add `## Role in the Verification Pipeline` section
- `docs/harness-architecture.md` — add `functionality-verifier.md` row to Quality Gates table; add new section "Functionality Verification Pipeline"
- `~/.claude/agents/functionality-verifier.md` — live-mirror copy
- `~/.claude/rules/verification-pipeline.md` — live-mirror copy
- `~/.claude/pipeline-templates/verify-functionality.sh` — live-mirror copy
- `~/.claude/agents/task-verifier.md` — live-mirror copy
- `~/.claude/agents/end-user-advocate.md` — live-mirror copy
- `~/.claude/agents/claim-reviewer.md` — live-mirror copy
- `~/.claude/agents/domain-expert-tester.md` — live-mirror copy

## In-flight scope updates
(no in-flight changes yet)

## Assumptions

- The existing `task-verifier` evidence-block format (Runtime verification lines + evidence file freshness window) is sufficient as the substrate for functionality-verifier output — no new schema needed; the agent's PASS evidence appears in the standard `<plan>-evidence.md` block as a `Runtime verification: functionality-verifier <slug>::<PASS|FAIL>` line plus an attached summary.
- The browser-MCP fallback chain documented in `end-user-advocate.md` (Claude_in_Chrome → Claude_Preview → ENVIRONMENT_UNAVAILABLE) is reusable verbatim by functionality-verifier. The two agents have different intent (advocate is adversarial product reviewer; functionality-verifier is the user-perspective use-the-feature check) but identical environmental needs.
- For harness work, the "functionality demonstration" is the hook/agent/rule's `--self-test` invocation passing. functionality-verifier accepts a `--self-test PASS` exit as equivalent evidence; no browser is required for harness-internal tasks. This is consistent with the `build-harness-infrastructure` work-shape's mechanical-check rubric.
- The orchestrator runs the pipeline in sequence (functionality-verifier → end-user-advocate → claim-reviewer → domain-expert-tester) per Pattern discipline. Only step 1 (functionality-verifier) blocks task completion mechanically; steps 2-4 are pipeline composition documented in the rule but not gated by a single PreToolUse hook (they already have their own enforcement mechanisms — Stop hook for end-user-advocate runtime, self-invocation for claim-reviewer, manual invocation for domain-expert-tester).

## Edge Cases

- **Task is harness-internal (file under `adapters/claude-code/` or `~/.claude/`).** functionality-verifier accepts a `--self-test PASS` outcome as the functional demonstration. No browser, no curl. The agent recognizes the harness scope by checking whether every modified file resolves to a path under `adapters/claude-code/` or `~/.claude/`.
- **Task is `Verification: mechanical` or `Verification: contract`.** task-verifier's existing Step 0 early-return applies; functionality-verifier is NOT invoked. The risk-tiered verification rule already excludes these tasks from the heavy verification path.
- **Browser MCP unavailable and the task has a UI surface.** functionality-verifier writes a `verdict: ENVIRONMENT_UNAVAILABLE` artifact identical in shape to end-user-advocate's runtime artifact. task-verifier treats this as INCOMPLETE, not PASS — same anti-vaporware discipline as end-user-advocate. The builder must either provide a browser or write a waiver.
- **functionality-verifier disagrees with end-user-advocate.** functionality-verifier fires per-task (narrow, "does this specific task's user path work"); end-user-advocate fires plan-time and at session end against all in-scope acceptance scenarios (broad, "is the whole plan's user outcome delivered"). Disagreement is signal: typically functionality-verifier PASSes a narrow task but end-user-advocate FAILs because a sibling task is missing. The pipeline composition surfaces this naturally — both agents run, both verdicts land in evidence.
- **Bare-text claim from builder ("I tested it manually").** Rejected exactly as today: functionality-verifier requires the same replayable formats (playwright spec, curl command, sql query, test file::name, or the harness-self self-test invocation). Plain-text manual claims do not satisfy the agent.

## Acceptance Scenarios
- n/a — acceptance-exempt per `acceptance-exempt: true` (harness-internal work; self-tests are the acceptance artifact)

## Out-of-scope scenarios
- n/a — acceptance-exempt

## Testing Strategy

- **functionality-verifier.md**: contract — agent file lands with the canonical sections (frontmatter, "When you are invoked," "Input contract," "Output format requirements," "What you are not"). `exists:` mechanical check confirms file present.
- **verification-pipeline.md**: contract — rule file lands with the canonical six-section structure (Classification, Why this rule exists, Pipeline order, When each agent fires, Cross-references, Enforcement, Scope). `exists:` check + grep for each required heading.
- **task-verifier.md** extension: contract — new section `## Functionality-verifier requirement (Verification: full)` exists and is referenced from the Step 3 (Run task-type-specific checks) flow. grep for the new heading.
- **Each updated agent** (end-user-advocate, claim-reviewer, domain-expert-tester): contract — `## Role in the Verification Pipeline` heading exists and contains a back-reference to `verification-pipeline.md`. grep for the heading and the back-reference.
- **verify-functionality.sh**: mechanical — script ships with `--self-test` that exercises three scenarios (PASS path for harness-self self-test; FAIL path for missing artifact; ENVIRONMENT_UNAVAILABLE path when MCP is unreachable). `bash verify-functionality.sh --self-test 2>&1 | grep -F 'self-test: OK'`.
- **harness-architecture.md** update: contract — table row for `functionality-verifier.md` present; section "Functionality Verification Pipeline" present.
- **Live mirror sync**: mechanical — `diff -q adapters/claude-code/<path> ~/.claude/<path>` returns no output for every changed file.

## Walking Skeleton

n/a — harness-internal work; the self-test is the end-to-end slice. Per `build-harness-infrastructure` work-shape, `## Walking Skeleton: n/a` is the canonical declaration for harness work whose layer-count is one (the agent / hook / rule itself) and whose slice IS the self-test.

## Decisions Log

### Decision: functionality-verifier is a new agent, not an extension of end-user-advocate
- **Tier:** 2
- **Status:** proceeded (auto-applied — reversible)
- **Chosen:** Build `functionality-verifier.md` as a separate agent that fires per-task during build, alongside the existing `end-user-advocate.md` which fires plan-time and at session end.
- **Alternatives:**
  - Extend `end-user-advocate.md` with a third mode (`mode=per-task`). Rejected: the existing two-mode dispatch is already nuanced; adding a third mode mixes plan-time peer-review semantics with per-task functional-check semantics. They are different roles.
  - Replace `end-user-advocate.md` entirely. Rejected: end-user-advocate is the harness's only adversarial *observer* of the running product across the whole plan; its scenarios-shared/assertions-private discipline (Goodhart prevention) is load-bearing. functionality-verifier is the per-task functional check; the two are complements, not alternatives.
- **Reasoning:** Separate agents make the roles legible. functionality-verifier per-task = "did THIS task's user path work?" end-user-advocate at session end = "does the WHOLE plan's user outcome hold up under adversarial probing?" Both are needed.
- **Checkpoint:** N/A — single commit lands the agent.
- **To reverse:** Delete the agent file + the rule + the task-verifier section + the script + the docs row, re-sync mirror. Single revert of the landing commit.

### Decision: Pipeline composition is Pattern-level except for the functionality-verifier requirement on `Verification: full` tasks
- **Tier:** 2
- **Status:** proceeded (auto-applied — reversible)
- **Chosen:** task-verifier mechanically requires functionality-verifier evidence (or harness-self self-test PASS) for `Verification: full` runtime tasks. The remaining pipeline steps (end-user-advocate runtime, claim-reviewer, domain-expert-tester) compose by Pattern in the new rule but are not auto-invoked by a single PreToolUse hook.
- **Alternatives:**
  - Hook-enforce every step. Rejected: each agent has its own well-tuned firing trigger (Stop-hook for advocate runtime; self-invocation before answering Q&A for claim-reviewer; manual after-build for domain-expert-tester). A single PreToolUse hook trying to fire all four would be brittle and would fire-storm on every Edit/Write.
  - Make the entire pipeline prose-only. Rejected: leaves the load-bearing gap (functionality check on task completion) without a mechanical backstop, which is the exact failure mode the work is meant to close.
- **Reasoning:** "Prose as guidance, hooks as physics" (per the harness's stated discipline). The functionality-verifier requirement at task-verifier dispatch is physics; the rest is guidance via the new rule. If pattern-level discipline proves insufficient, individual steps can be hardened in follow-ups.
- **Checkpoint:** N/A.
- **To reverse:** Revert the task-verifier extension.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, every behavior change in Sections is cited in Tasks + Files to Modify/Create
- S2 (Existing-Code-Claim Verification): swept, claims about end-user-advocate two modes / task-verifier Step 0 early-return / plan-edit-validator freshness window verified against files read this session
- S3 (Cross-Section Consistency): swept, "Pattern-level except task-verifier requirement" claim consistent across Goal / Scope / Tasks / Decisions Log
- S4 (Numeric-Parameter Sweep): swept, no numeric parameters in this plan
- S5 (Scope-vs-Analysis Check): swept, every "Add/Modify" verb maps to a file in Files to Modify/Create; no Scope OUT contradictions

## Definition of Done

- [ ] All tasks checked off (8 total)
- [ ] All self-tests pass (`harness-hygiene-scan --self-test`, `verify-functionality.sh --self-test`)
- [ ] Live mirror byte-identical to canonical for every changed file
- [ ] `docs/harness-architecture.md` row + section landed
- [ ] Commit message scoped `feat(harness): ...`
- [ ] Pushed to both remotes
- [ ] SCRATCHPAD.md updated
- [ ] Status: COMPLETED appended after completion report
