---
title: 3 harness-friction items from the worktree-spawn-primitive session
date: 2026-05-26
type: process
status: pending
auto_applied: false
originating_context: feat/worktree-spawn-primitive session (PR #11) — building the worktree-spawn primitive in an isolated worktree
decision_needed: Should any of these three gate/auto-deploy frictions be fixed? Each is a harness-improvement SUGGESTION surfaced for Misha's decision per friction-reflexion.md (not filed as committed work).
predicted_downstream:
  - adapters/claude-code/hooks/scope-enforcement-gate.sh
  - adapters/claude-code/hooks/task-completed-evidence-gate.sh
  - install.sh (auto-deploy core.hooksPath behavior)
---

## What was discovered

Building the worktree-spawn primitive in an isolated worktree (the dogfood)
surfaced three harness frictions, all stemming from cross-session interaction
while 3 sibling-session plans were ACTIVE:

1. **`scope-enforcement-gate.sh` cross-session false-fire on orphan harness
   commits.** The gate blocks iff EVERY active plan rejects a staged file
   (line ~1060). My orphan harness-infrastructure commit (no plan of its own)
   was blocked because the 3 sibling-session active plans don't claim my files
   — even though the gate's own design intends "no active plan = pass-through"
   (line ~1009). Worked around by opening+closing a lightweight bookkeeping
   plan (gate option 2), but that is ceremony the build-harness-infrastructure
   work-shape says should be optional.

2. **`task-completed-evidence-gate.sh` misfires on the lightweight session
   tracker.** Firing `TaskUpdate status=completed` on a `TaskCreate` session-
   tracker task (id "6") was blocked because the hook matched the bare numeric
   id against the 3 active plans' evidence logs, conflating session-tracker
   task IDs with plan-file task IDs.

3. **`install.sh` auto-deploy repoints global `core.hooksPath` into the
   committing worktree.** Every commit in my worktree ran the auto-deploy,
   which set `git config --global core.hooksPath` to
   `.../.claude/worktrees/worktree-spawn-primitive/adapters/claude-code/git-hooks`.
   When that ephemeral worktree is pruned (post-merge), the global hooksPath
   dangles and pre-push/credential hooks break for EVERY repo on the machine
   until the next install. I reset it to the stable main checkout's git-hooks
   at session end, but the auto-deploy will re-introduce it on the next
   worktree commit.

## Why it matters

Each is a cross-session/worktree interaction that adds friction or latent
breakage exactly in the parallel-session workflow the worktree primitive is
meant to make safe. (1) and (2) train sessions to fight or bypass gates; (3)
is a latent machine-wide breakage.

## Options

A. Fix all three (scope-gate: treat orphan harness commits under
   `adapters/claude-code/`+`docs/` as pass-through even when sibling plans are
   active; task-completed-gate: ignore ids that don't correspond to a plan
   task heading; install.sh: point hooksPath at the main checkout, never the
   committing worktree).
B. Fix only (3) (the latent machine-wide breakage) now; defer (1)/(2) as
   convenience gaps.
C. Defer all three — accept the documented workarounds (open-a-plan;
   don't-toggle-the-tracker; reset-hooksPath-manually).

## Recommendation

B as the floor — (3) is a real latent breakage that affects sibling sessions
machine-wide, and the fix (point hooksPath at the main checkout) is small and
reversible. (1) is the highest-leverage of the remaining two (it recurs for
every orphan harness session during the active 5-pattern swarm) but the fix
touches a load-bearing gate, so it warrants discussion before building. (2) is
lowest-severity (cosmetic tracker noise).

## Decision

(pending Misha's decision — surfaced per friction-reflexion.md; NOT auto-applied)

## Implementation log

(empty — no fix built this session; these are suggestions for discussion)
