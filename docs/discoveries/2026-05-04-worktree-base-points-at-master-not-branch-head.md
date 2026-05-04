---
title: Agent tool's worktree isolation creates worktrees at master, not branch HEAD
date: 2026-05-04
type: architectural-learning
status: pending
auto_applied: false
originating_context: Phase 1d-C-2 Builder B (Task 7 — prd-validity-reviewer agent) parallel-mode dispatch
decision_needed: How to make `isolation: "worktree"` reliably branch from current HEAD instead of master, OR whether to document the limitation and stop relying on parallel-mode for branch-state-dependent tasks
predicted_downstream:
  - rules/orchestrator-pattern.md (parallel-builder protocol)
  - hooks/teammate-spawn-validator.sh (Agent Teams worktree-mandatory rule)
  - any future plan that uses `isolation: "worktree"` for parallel-mode dispatches
---

## What was discovered

During Phase 1d-C-2, two parallel-mode dispatches were issued via the Agent tool with `isolation: "worktree"` set (Builder A for Task 1 and Builder B for Task 7). Both worktrees were created at master HEAD (`10adac2`) instead of the calling session's current branch HEAD (`aa15c99`).

**Concrete consequence for Builder B:** the plan file `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` had been committed at `aa15c99` but did NOT exist in the worktree (which was rooted at `10adac2`). When Builder B attempted `git commit`, `scope-enforcement-gate.sh` couldn't find any plan claiming the agent file, and BLOCKED. Builder returned BLOCKED. Recovery required copying the staged file out of the worktree, into the main repo, and committing on the branch directly.

**Builder A** worked around this implicitly by abandoning its worktree and committing in the main repo on the correct branch.

## Why it matters

The parallel-mode dispatch protocol documented in `rules/orchestrator-pattern.md` ("Build-in-parallel, verify-sequentially") relies on each builder having a usable worktree branched from the orchestrator's current HEAD. If worktrees branch from master instead, every parallel builder past the very first commit on a feature branch will hit this — they cannot see the plan file, cannot pass scope-enforcement-gate, cannot commit.

Practical effect today: parallel-mode dispatch is **broken for any feature branch that has commits ahead of master**. Sequential dispatch in the main repo is the only reliable path. This degrades the orchestrator pattern's parallelism story significantly.

This affects:
- Long-running feature branches (i.e., almost all real harness work — `build-doctrine-integration` itself has been running for many sessions)
- Agent Teams `worktree_mandatory_for_write: true` mode (per `rules/agent-teams.md`) — teammates would hit the same issue
- Any sweep task that relies on parallel-builder-per-file isolation

## Options

A. **Document the limitation in `rules/orchestrator-pattern.md`.** Add a "Known limitation: worktrees may branch from master, not feature-branch HEAD. Use sequential dispatch on long-running feature branches." Costs: zero implementation; gives every future orchestrator the heads-up. Loses parallelism on feature branches.

B. **Pre-flight check in builder dispatch prompts.** Have builders run `git fetch && git rebase origin/<branch>` (or `git merge origin/<branch>`) at the start of their work, before any commits. Catches the issue but rebases onto whatever the remote knows, not the local branch state — fragile if local has uncommitted ahead-of-remote work.

C. **Investigate Claude Code's worktree-creation primitive.** Determine whether `isolation: "worktree"` honors a base-commit hint, or whether this is a fixed master-only behavior. If configurable, fix the orchestrator's dispatch templates. If not, file with Anthropic.

D. **Replace `isolation: "worktree"` with sequential dispatch in the main repo.** Lose the parallelism guarantee but gain reliability. Update the orchestrator pattern's "Default to parallel dispatch" rule to "Sequential dispatch on long-running feature branches; parallel only on master or short-lived branches."

## Recommendation

C, then D as the fallback if C reveals the behavior is unfixable.

If C confirms the behavior is fixable (e.g., the Agent tool accepts a base-branch parameter we're not currently passing), fix the orchestrator's dispatch templates and reinstate parallelism. If C confirms it's a Claude Code limitation, fall back to D — sequential is the safe-and-correct mode for the kind of work NL itself does (always on a feature branch).

**Reasoning principle:** the orchestrator pattern is a quality-of-life improvement for context hygiene, not a correctness mechanism. Losing parallelism is acceptable; building wrong is not. Sequential dispatch already worked correctly for Phases 1d-C-2 and 1d-C-3 (most builders ran sequentially after Builder B's BLOCKED experience taught the orchestrator the lesson). Documenting + sequential-by-default is the conservative honest path.

## Decision

Pending. Surface to user at next SessionStart.

## Implementation log

(Empty until decided.)
