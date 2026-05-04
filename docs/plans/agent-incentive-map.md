# Plan: Agent Incentive Map — Document Predicted Stray-Patterns and Counter-Incentives

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; deliverable is documentation + agent prompt edits. No user-facing product surface to exercise.

## Context

Prior session work shipped Phase 1d-C-1 (three first-pass C-mechanisms: scope-enforcement-gate, plan-reviewer Check 9 quantitative-claims, dag-review-waiver-gate) at SHA `cc20cde` on branch `build-doctrine-integration`. After that landed, the user surfaced a meta-architectural question (Munger's "Show me the incentive and I'll show you the outcome" applied to AI agents): can we be PROACTIVE about agent incentive misalignments rather than purely reactive (the current `diagnosis.md` "After Every Failure: Encode the Fix" loop)?

The harness has 17 agents. Each has training-induced incentives plus prompt-induced incentives. Each strays from intended behavior in characteristic ways. Today, those stray-patterns are captured implicitly in the various rules and mechanisms — but not catalogued in one place. The next session has no consolidated reference for "here's how each agent will likely misbehave and what we've done about it."

This plan creates that artifact and applies four targeted prompt-level counter-incentives to the highest-leverage agents.

Working on branch `build-doctrine-integration` in `~/claude-projects/neural-lace/`. Scope-enforcement-gate and plan-reviewer Check 9 are now ACTIVE in this repo and will fire on this plan's commit.

## Goal

Three deliverables that shift the harness from reactive failure-correction to proactive incentive-design:

1. **`docs/agent-incentive-map.md`** — Primary artifact. Per-agent catalog: stated goal, latent training incentive, predicted stray-from patterns, current mitigations, residual gaps, detection signals. ~3000-5000 words covering all 17 NL agents.

2. **Four agent-prompt extensions** — Add explicit "your latent incentive is X; resist it" sections to the four highest-leverage agents (task-verifier, code-reviewer, plan-phase-builder, end-user-advocate). These prime the agent against its own training-induced bias.

3. **`docs/backlog.md` HARNESS-GAP-11** — Document the unaddressed structural weakness: reviewer accountability is one-way (when reviewer PASSes work that later fails, no signal flows back). This is the meaty mechanism that warrants its own future plan.

## Scope

**IN:**
- Create `docs/agent-incentive-map.md` (new).
- Edit 4 agent prompts in `adapters/claude-code/agents/` AND mirror to `~/.claude/agents/` (8 files modified across both locations).
- Add HARNESS-GAP-11 entry to `docs/backlog.md`.
- Update `docs/harness-architecture.md` preface to cite the new incentive-map doc (per docs-freshness-gate rule for structural additions).
- Single thematic commit on `build-doctrine-integration`, push to origin.

**OUT:**
- Editing the other 13 agent prompts (deferred until empirical data justifies; the four chosen are the highest-leverage based on observed stray patterns).
- Implementing the reviewer-calibration mechanism (HARNESS-GAP-11 captures it for future).
- Phase 1d-C-2 work (separate plan after this one lands).

## Tasks

Tasks dispatched per orchestrator-pattern. T1, T2, T3 touch different files and run in parallel. T4 is the sequential commit.

- [ ] **T1.** Create `docs/agent-incentive-map.md` covering all 17 NL agents in the structured format described in Goal section #1.
- [ ] **T2.** Extend the four agent prompts (task-verifier, code-reviewer, plan-phase-builder, end-user-advocate) with explicit counter-incentive sections per Goal section #2. Edit both `adapters/claude-code/agents/<name>.md` AND mirror to `~/.claude/agents/<name>.md` (8 files total).
- [ ] **T3.** Add HARNESS-GAP-11 entry to `docs/backlog.md` documenting the reviewer-accountability one-way gap.
- [ ] **T4.** Update `docs/harness-architecture.md` preface to cite the new incentive-map doc; commit all changes in a single thematic commit on `build-doctrine-integration`; push to `origin`.

## Files to Modify/Create

**New files:**
- `docs/plans/agent-incentive-map.md` (this plan; self-referential entry)
- `docs/agent-incentive-map.md`

**Modified files:**
- `adapters/claude-code/agents/task-verifier.md`
- `adapters/claude-code/agents/code-reviewer.md`
- `adapters/claude-code/agents/plan-phase-builder.md`
- `adapters/claude-code/agents/end-user-advocate.md`
- `~/.claude/agents/task-verifier.md` (mirror)
- `~/.claude/agents/code-reviewer.md` (mirror)
- `~/.claude/agents/plan-phase-builder.md` (mirror)
- `~/.claude/agents/end-user-advocate.md` (mirror)
- `docs/backlog.md`
- `docs/harness-architecture.md`

## Assumptions

- All 17 agent files exist at `adapters/claude-code/agents/<name>.md` and mirror at `~/.claude/agents/`.
- The existing pre-submission-audit-mechanical-enforcement.md plan is also ACTIVE; scope-enforcement-gate will require a waiver against it (this plan is genuinely independent work).
- The four chosen agents represent the highest-leverage stray-pattern interventions; the other 13 are catalogued in the incentive-map doc but their prompts not yet extended.

## Edge Cases

- Scope-enforcement-gate fires against pre-submission-audit-mechanical-enforcement.md plan since this work is out-of-scope of that plan. Mitigation: waiver written before commit attempt.
- New file at `docs/agent-incentive-map.md` triggers docs-freshness-gate. Mitigation: harness-architecture.md updated alongside.

## Acceptance Scenarios

n/a — `acceptance-exempt: true`. Documentation and prompt-edit work; verification is structural review of the deliverable.

## Definition of Done

- All 4 tasks task-verified PASS.
- All 11 file changes (including this plan) land in one commit on `build-doctrine-integration`.
- Commit pushed to `origin/build-doctrine-integration`.
- Status of THIS plan flipped to COMPLETED at session end.
