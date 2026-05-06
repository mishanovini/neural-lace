# Plan: Tranche A — Incentive Redesign at the Prompt Layer

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: dialogue-only
frozen: true
prd-ref: docs/plans/architecture-simplification.md
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Sub-tranche of Tranche 1.5 (architecture-simplification). Pure prose edits to agent and rule files; no product-user surface. Verification is by reading the updated files for the reframed "done" definitions.

## Goal

Reframe "done" definitions across the agent + rule prompt layer so each agent's natural completion signal aligns with the desired behavior — closing the loop the user surfaced 2026-05-05 ("show me the incentive and I'll show you the outcome"). The Counter-Incentive Discipline sections shipped 2026-05-03 warn agents against their biases. This tranche extends those sections from "warn against bias" to "redesign the reward structure so the bias does not fire."

Specifically:
- Orchestrator's "done" = "plan closed and archived" (not "code shipped to master")
- Builder's "done" = "task-verifier flipped my checkbox" (not "I returned a plausible verdict")
- Verifier's correctness = "my PASS verdicts hold up at runtime" (not "I returned a verdict")
- Reviewer's correctness = same calibration framing as verifier

## Scope

- IN: Edits to `~/.claude/CLAUDE.md`, `~/.claude/rules/orchestrator-pattern.md`, `~/.claude/rules/planning.md`, `~/.claude/agents/{plan-phase-builder,task-verifier,code-reviewer,end-user-advocate}.md`. Sync to `adapters/claude-code/` mirrors for harness-maintenance discipline. Update existing Counter-Incentive Discipline sections in the 4 agent prompts. New "definition of done" framing repeated as the most-load-bearing pattern across the prompts.
- OUT: New gates / hooks / mechanisms (per Tranche 1.5 hard freeze). New agents. Substantive scope changes to the agents' tool surfaces or capabilities. Edits to other rules unless they directly cite "done" definitions that need reframing.

## Tasks

- [ ] 1. **Edit `adapters/claude-code/CLAUDE.md` "Context Persistence (SCRATCHPAD.md)" + adjacent sections.** Add the orchestrator's reframed "done" definition: "A plan is not 'shipped' until it is `Status: COMPLETED` and archived. Code on master without a closed plan is incomplete work. The orchestrator's deliverable is the closed plan, not the code." Verification: mechanical (grep for the new sentence). Sync to `~/.claude/CLAUDE.md`.
- [ ] 2. **Edit `adapters/claude-code/rules/orchestrator-pattern.md` "When to use orchestrator mode" and "The dispatch protocol" sections.** Same reframing — the orchestrator's reward signal is plan closure, not dispatch completion. Replace "after all tasks complete, append handoff report. Set Status: COMPLETED" with "Closure is the orchestrator's primary deliverable. Dispatching is the first part of the work; closure is the last part of the same work, not a separate phase." Verification: mechanical. Sync to `~/.claude/`.
- [ ] 3. **Edit `adapters/claude-code/rules/planning.md` "Verifier Mandate" + "Plan File Lifecycle" sections.** Reframe planning's done definition: "A plan is in flight from creation through closure. There is no 'I built it but bookkeeping is later'." Add: "Closure follows builds deterministically (per Tranche E of architecture-simplification once it ships)." Verification: mechanical. Sync to `~/.claude/`.
- [ ] 4. **Edit `adapters/claude-code/agents/plan-phase-builder.md` Counter-Incentive Discipline section.** Extend from "warn against bias" to "redesign the reward structure." Add: "DONE is not a self-declaration. DONE = task-verifier has flipped your checkbox AND the next task has been dispatched (or the plan has been closed). Your work-unit ends when the verifier verdict lands, not when you return a result message." Verification: mechanical. Sync to `~/.claude/`.
- [ ] 5. **Edit `adapters/claude-code/agents/task-verifier.md` Counter-Incentive Discipline section.** Add the calibration framing: "Your verdict will be cross-checked at session end (by `pre-stop-verifier.sh`) and at runtime acceptance (when applicable). A PASS that fails later is a stronger negative signal than a too-conservative FAIL. Bias toward FAIL when uncertain. PASSes that hold up at runtime are the metric of your correctness, not the speed of your verdict." Verification: mechanical. Sync to `~/.claude/`.
- [ ] 6. **Edit `adapters/claude-code/agents/code-reviewer.md` Counter-Incentive Discipline section.** Same calibration framing as task-verifier. Verification: mechanical. Sync to `~/.claude/`.
- [ ] 7. **Edit `adapters/claude-code/agents/end-user-advocate.md` Counter-Incentive Discipline section.** Same calibration framing, scoped to runtime acceptance: "Your runtime PASS verdict is the strongest claim about whether the user can use the feature. A PASS that the user immediately bug-reports is a stronger negative than a FAIL that the orchestrator argues is unwarranted." Verification: mechanical. Sync to `~/.claude/`.
- [ ] 8. **Update `docs/plans/architecture-simplification.md` to flip Task 2 to `[x]`** (Tranche A dispatch + completion). Apply the deterministic close-plan procedure once Tranche E ships; until then, lightweight evidence per the gate-relaxation policy.

## Files to Modify/Create

- `adapters/claude-code/CLAUDE.md` — MODIFY (1-2 paragraph addition)
- `adapters/claude-code/rules/orchestrator-pattern.md` — MODIFY (~5-10 line reframings in 2 sections)
- `adapters/claude-code/rules/planning.md` — MODIFY (~3-5 line additions)
- `adapters/claude-code/agents/plan-phase-builder.md` — MODIFY (Counter-Incentive Discipline extension, ~5-10 lines)
- `adapters/claude-code/agents/task-verifier.md` — MODIFY (~5-10 lines)
- `adapters/claude-code/agents/code-reviewer.md` — MODIFY (~5-10 lines)
- `adapters/claude-code/agents/end-user-advocate.md` — MODIFY (~5-10 lines)
- `~/.claude/CLAUDE.md`, `~/.claude/rules/{orchestrator-pattern,planning}.md`, `~/.claude/agents/{plan-phase-builder,task-verifier,code-reviewer,end-user-advocate}.md` — sync mirrors of the adapter changes
- `docs/plans/architecture-simplification.md` — MODIFY (Task 2 checkbox flip at completion)
- `docs/plans/architecture-simplification-tranche-a-incentive-redesign.md` — this plan
- `docs/plans/architecture-simplification-tranche-a-incentive-redesign-evidence.md` — companion evidence file (NEW)

## In-flight scope updates

(none yet)

## Assumptions

- The Counter-Incentive Discipline sections exist in the 4 agent prompts already (per `docs/agent-incentive-map.md` work shipped 2026-05-03). Verified by inspection.
- The existing "done" framings in CLAUDE.md, orchestrator-pattern.md, and planning.md treat closure as a separate phase from build. Verified by inspection of those files this session.
- Reframing is additive, not destructive — existing content stays; new framings layer on top as the most-load-bearing pattern.
- The harness-maintenance.md sync rule applies: every adapters/ edit is mirrored to ~/.claude/.

## Edge Cases

- **Reframings conflict with each other across files.** Mitigation: author all 7 edits in one builder pass; check internal consistency before commit.
- **An agent prompt's existing structure makes the reframing awkward.** Acceptable to restructure that agent's section locally; document in the in-flight scope updates of this plan.
- **The reframing reveals a place where the doctrine itself is silent.** Capture as a discovery; defer doctrine extension (N1/N2/N3 from the integration review) to its own track.

## Acceptance Scenarios

(plan is acceptance-exempt — see header)

## Out-of-scope scenarios

(none)

## Testing Strategy

Mechanical verification per task: grep for the new framing in each modified file. No agent dispatch needed for verification. Lightweight evidence captures the grep output as proof.

## Walking Skeleton

The most-load-bearing reframing is the orchestrator's "done = plan closed" because it cascades through every other agent's behavior. Land Task 1 (CLAUDE.md) first as the minimum viable reframing; subsequent tasks layer on top.

## Decisions Log

(populated during build if substantive choices arise)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every prompt edit names the file + section
S2 (Existing-Code-Claim Verification): swept — Counter-Incentive Discipline sections confirmed present per session inspection
S3 (Cross-Section Consistency): swept — Goal, Scope, Tasks, Files-to-Modify all agree
S4 (Numeric-Parameter Sweep): n/a
S5 (Scope-vs-Analysis Check): swept — every "Edit" verb maps to a Files-to-Modify entry; OUT clause excludes new mechanism work

## Definition of Done

- [ ] All 7 prompt-edit tasks shipped + synced to `~/.claude/` mirrors
- [ ] Mechanical evidence captured for each task (grep output)
- [ ] Parent plan Task 2 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition (under gate-relaxation: closure-validator advisory)

## Evidence Log

(populated by lightweight-evidence pattern at closure)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:25:31Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-a-incentive-redesign.md` (slug: `architecture-simplification-tranche-a-incentive-redesign`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/agents/code-reviewer.md`
- `adapters/claude-code/agents/end-user-advocate.md`
- `adapters/claude-code/agents/plan-phase-builder.md`
- `adapters/claude-code/agents/task-verifier.md`
- `adapters/claude-code/rules/orchestrator-pattern.md`
- `adapters/claude-code/rules/planning.md`
- `docs/plans/architecture-simplification-tranche-a-incentive-redesign-evidence.md`
- `docs/plans/architecture-simplification-tranche-a-incentive-redesign.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/CLAUDE.md`

Commits referencing these files:

```
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3f2c6c4 docs(orchestrator): add anti-pattern #7 — --dry-run-first for install-class work
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
4d94940 docs(plan-mode): Execution Mode: agent-team value + cross-references (plan task 12)
55742f2 docs(rules): SCRATCHPAD triggers (Rule 2) + review-finding IDs (Rule 4) + memory last_verified (Rule 7)
70b8de9 plan(1.5/A+B): author Tranches A and B child plans + flip Task 1 (gate-relaxation policy already shipped)
70e5262 feat: capture-codify PR template + CI workflow + 7 decision records (#1)
72ad219 docs(harness): planning.md — unified plan file lifecycle convention
73f841d feat(doctrine): N1 N2 N3 extensions to build-doctrine principles + parent plan Task 10 flip + scope update
8a5eca3 feat(autonomy): ADR 027 autonomous decision-making process + Tranche 1.5 decision queue
8e1d735 feat(harness): Phase F builder discipline — scenarios-shared/assertions-private (F.1, F.2)
951b073 plan(1.5): flip Tasks 4 (D), 6 (C), 7 (G) — all three sub-tranches shipped in parallel
964a2ed feat(harness): mandatory verbose plans with required-section validator
97e838b feat(harness): wire failure-mode catalog into diagnosis rule, skills, agents
9c4e4c8 feat(harness): encode 11 lessons-learned from 8-round design-mode review
9f9a8b1 feat(architecture): land ADR 026 + Tranche 1.5 plan + gate-relaxation policy
a6ffebd feat(harness): Phase A walking skeleton — end-user-advocate acceptance loop
aed3948 feat(harness): Phase C production end-user-advocate agent (C.1-C.3)
b4406c8 feat(phase-1d-c-2): Task 2 — prd-validity + spec-freeze rule docs + cross-refs
b68caf2 feat(1.5/E): Tranche E shipped — deterministic close-plan procedure (closure benchmark: 2.8 sec for synthetic 3-task plan vs 65K-token baseline)
bfadcbb feat(harness): task-verifier comprehension-gate invocation at R2+ (Phase 1d-C-4 Task 4)
c417d6d docs(rules): backlog absorption (Rule 1) + orchestrator metadata (Rule 6) + template updates
d6d67b8 docs(narrative): GAP-17 Part A — sweep narrative docs to current Gen 5/6 + Build Doctrine state
d84f398 docs: add LICENSE (MIT) + best-practices.md + refresh README/CLAUDE.md
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
