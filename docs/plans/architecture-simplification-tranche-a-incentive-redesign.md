# Plan: Tranche A — Incentive Redesign at the Prompt Layer

Status: ACTIVE
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

(populated at closure)
