---
title: Component B merge blocked on parallel Phase-3/4/2b landing first
date: 2026-06-01
type: process
status: decided
auto_applied: false
originating_context: Component B (orchestrator reconciler) build session — branch feat/orchestrator-reconciler-component-b @ ac684f4, pushed to PT origin
decision_needed: When Phase 3+4+Task-2b (parallel build local_55828ae9) lands on master, trigger the Component B rebase+merge (re-anchor the one settings.json.template entry on the renamed workstreams-emit-reconciler.sh). Confirm parallel-first ordering.
predicted_downstream:
  - adapters/claude-code/settings.json.template
  - adapters/claude-code/hooks/workstreams-orchestrator-queue.sh
  - ~/.claude/settings.json (live)
  - neural-lace/workstreams-ui/scripts/register-reconciler.ps1 (scheduled-task registration)
---

## What was discovered

Component B (the orchestrator reconciler) is built, fully tested, committed, and
pushed to PT origin on `feat/orchestrator-reconciler-component-b` (@ ac684f4).
It CANNOT be cleanly merged to master from this session because a parallel
session (`local_55828ae9`, the Workstreams Phase 3+4 + Task 2b build) is
**actively working in the shared main checkout right now**:

- The main checkout is on branch `feat/workstreams-phase-3` @ 564c1b9 (NOT master).
- It has **uncommitted staged renames**: `conversation-tree-*.sh` → `workstreams-*.sh`
  for every conv-tree hook, INCLUDING `conv-tree-emit-reconciler.sh` →
  `workstreams-emit-reconciler.sh` — the exact hook my `settings.json.template`
  edit anchors my new `workstreams-orchestrator-queue.sh` entry next to.
- It has its own `settings.json.template` edit (Task 2b rewires the renamed hooks).

Both branches edited `settings.json.template`, and the parallel build renames a
hook my edit references → an inherent merge conflict that SOMEONE resolves at
merge time.

## Why it matters

Touching the main checkout (checkout master / merge) would wipe the parallel
session's uncommitted staged work — the classic cross-session P1 clobber the
harness warns against repeatedly. And whoever merges SECOND resolves the
settings.json conflict. If Component B merges first, the parallel session (which
does not know about my hook) resolves the conflict and may drop my wiring or
leave a stale `conv-tree-emit-reconciler.sh` reference. If the parallel build
merges first, I rebase Component B onto the renamed world and re-anchor my one
entry correctly — clean, and I own the integration of my own hook.

## Options

A. **Parallel-first (recommended).** Wait for Phase 3+4+2b to land on master,
   then rebase `feat/orchestrator-reconciler-component-b` onto master, re-anchor
   the single `settings.json.template` entry on `workstreams-emit-reconciler.sh`,
   merge. Cost: Component B not on master for a few hours. Benefit: clean merge,
   no clobber, correct dependency ordering (B builds on the renamed substrate).
B. Merge Component B to master first via a fresh master worktree. Cost: races the
   active parallel session; the parallel build resolves the settings conflict
   second without knowing my hook → fragile. Rejected.
C. Force the merge into the active main checkout. Cost: wipes uncommitted
   parallel work. Rejected outright (P1 clobber).

## Recommendation

A. The parallel Workstreams reframe is the substrate Component B sits on
(Component B reads the lifecycle events Phase 3 emits + the hooks Task 2b
renames). Parallel-first is both the safe ordering and the correct dependency
ordering.

## Decision

DECIDED: Option A (parallel-first). The ordering is the clear correct answer
(parallel build owns the rename + is the substrate Component B sits on), so this
is not a Misha-judgment call — it's a documented ordering with a mechanical
re-engage trigger (below) any session can execute once the parallel build lands.
Misha need only confirm the parallel Phase-3/4/2b work has merged before the
re-engage runs.

## Re-engage trigger (precise, for any future session)

When `feat/workstreams-phase-3` (Phase 3+4 + Task 2b rename) has merged to PT
master:

1. `git fetch origin && git -C <worktree> rebase origin/master` on
   `feat/orchestrator-reconciler-component-b` (or merge origin/master in).
2. Resolve the `settings.json.template` conflict: keep the single
   `workstreams-orchestrator-queue.sh` Stop-hook entry; re-anchor it AFTER the
   renamed `workstreams-emit-reconciler.sh` (was `conv-tree-emit-reconciler.sh`).
3. `git checkout master && git merge --no-ff feat/orchestrator-reconciler-component-b`; push origin.
4. **Live wiring** (post-merge, install-sync — collision-free once parallel work is landed):
   - `cp adapters/claude-code/hooks/workstreams-orchestrator-queue.sh ~/.claude/hooks/`
   - add the same Stop-hook entry to live `~/.claude/settings.json`
   - `node neural-lace/workstreams-ui/scripts/... ` — register the scheduled runner:
     `pwsh neural-lace/workstreams-ui/scripts/register-reconciler.ps1 -RunNow`
     (surface-only — config.autoSpawn stays false until Components A + C land).
5. Verify: `node neural-lace/workstreams-ui/state/reconciler-run.js --dry-run`
   prints the reconciliation report against live state.

## Implementation log

- Built + tested + pushed: feat/orchestrator-reconciler-component-b @ ac684f4 (PT origin).
- Plan: docs/plans/orchestrator-reconciler-component-b.md (Status: DEFERRED — see its Decisions Log "Session-1 completion state").
