---
title: 3 harness-friction items from the worktree-spawn-primitive session
date: 2026-05-26
type: process
status: implemented
auto_applied: true
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

**B (the recommended floor) implemented; (1) and (2) remain surfaced
discussion suggestions (auto-applied per discovery-protocol — B is a
small, reversible, mechanism-internal fix the discovery itself
recommended; 2026-06-10 pending-discoveries triage).** Re-verified
2026-06-10: all three frictions were still live. (3) was the latent
machine-wide breakage — `git-hooks/post-commit` runs the COMMITTING
worktree's install.sh, whose `ADAPTER_DIR` derives from its own
location, so every worktree commit repointed the GLOBAL `core.hooksPath`
at a prunable worktree path. Fixed: install.sh now resolves a
`STABLE_ADAPTER_DIR` (via `git rev-parse --git-common-dir` ≠ `--git-dir`
worktree detection → main-checkout adapter dir) and uses it for the
hooksPath pointer; file-sync to `~/.claude/` still deploys what was
committed (unchanged semantics). (1) scope-gate orphan-commit
false-fire and (2) task-completed-gate tracker-id conflation stay
deliberately UN-built and UN-filed: per friction-reflexion.md they are
suggestions needing Misha's discussion — (1) touches a load-bearing
gate's semantics; (2) is cosmetic. Both were re-surfaced to Misha in the
2026-06-10 triage return. Note (1) reproduced live during this very
triage (the triage session had to open a bookkeeping plan to commit).

## Implementation log

- `adapters/claude-code/install.sh` — `STABLE_ADAPTER_DIR` resolution
  (worktree-aware via git-common-dir) + both hooksPath call sites
  (dry-run Phase 4 echo + actual `git config --global` set) now use it;
  resolution verified live from a linked worktree (resolves to the main
  checkout's `adapters/claude-code`).
- Landed via the 2026-06-10 pending-discoveries-triage branch.
