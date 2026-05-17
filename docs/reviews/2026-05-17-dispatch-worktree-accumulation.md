# Dispatch Worktree Accumulation — Lifecycle, Cleanup, Systemic Fix

Date: 2026-05-17
Author: Misha + Claude
Trigger: a large pile of accumulated Dispatch worktrees in one repo;
"are they not cleaning up when they're done?"

> Machine-specific instance data (exact branch names, per-worktree
> salvage recommendations) is intentionally kept OUT of this committed
> harness doc per harness-hygiene. It lives in the gitignored companion
> `.claude/state/worktree-surface-<date>.md` and was surfaced to the
> operator in the session chat.

## 1. The lifecycle (how worktrees are created, why they accumulate)

Two distinct worktree species, two distinct lifecycles:

### A. Dispatch session worktrees (the accumulation problem)

- **Created by:** the Claude Code desktop app's Dispatch / "+ New
  session" flow. Each spawned code task targeting a repo gets a sibling
  worktree at `~/claude-projects/<project>/<adjective-name-hash>` on
  branch `claude/<same>`.
- **Cleaned up by:** **nothing.** There is no session-end hook in the
  Anthropic runtime and none in this harness that removes the worktree
  when the Dispatch session ends. The branch is pushed, a PR may be
  opened/merged, and the local worktree is simply abandoned in place.
- **Result:** unbounded accumulation. One machine on 2026-05-17 had ~50
  in one repo, ~30 in another. New worktrees appeared *during* the
  cleanup session — the accumulation is live and ongoing.
- **Spawn logic location:** Anthropic desktop-app / Claude Code runtime.
  **NOT in this harness repo, NOT modifiable by us.** Confirmed: no
  worktree-cleanup hook exists in `adapters/claude-code/hooks/` (the only
  `worktree` matches there are unrelated — teammate-spawn validation,
  multi-worktree acceptance aggregation).

### B. Orchestrator Agent-tool worktrees (a separate, smaller issue)

- **Created by:** the `Agent` tool's `isolation: "worktree"` per the
  orchestrator-pattern. Live at `<repo>/.claude/worktrees/agent-*`,
  branches `worktree-agent-*` / `worker-*`, git-`locked`.
- **Cleaned up by:** the orchestrator's cherry-pick-then-`git worktree
  remove` protocol (`rules/orchestrator-pattern.md`). Auto-removed if the
  agent made no changes; persist (locked) if commits were made until the
  orchestrator removes them.
- **Orphaned when:** the orchestrator dies mid-run before cherry-pick
  (documented failure mode: orchestrator-pattern.md "Recovery from
  orphaned worktrees"). Several weeks-old orphans observed in one repo.

## 2. The gap

No mechanism — runtime or harness — removes a Dispatch worktree when its
session ends, and no reuse mechanism lets a new session pick up an idle
merged-out worktree. The desktop app owns spawn; the harness owns nothing
on the teardown side. The only lever in our control is **periodic
out-of-band pruning**.

## 3. Cleanup performed (safe set only)

All worktrees were classified, then only the provably-safe set was
removed: fully merged into master (tip is an ancestor of the master ref,
OR `git diff --quiet master...tip` — covers squash-merges), clean working
tree once session/build noise is filtered (`.claude/state`,
`scheduled_tasks.lock`, `node_modules`, `.next`, `dist`, `*.tsbuildinfo`,
`SCRATCHPAD.md`), ≥1–3 days idle, not locked, not the current/main
checkout. ~47 worktrees removed across three repos; zero salvageable
content lost (a merged+clean worktree's work is in master by definition).

Branches deleted with `git branch -d` (safe — refuses unmerged). Where
`-d` refused (squash-merged) the branch was **kept for history** — only
the worktree dir was removed.

Windows note: `git worktree remove` succeeds (files deleted, worktree
de-registered) but the empty leaf dir often fails its final rmdir with
"Permission denied" (Explorer / search-indexer / cloud-sync-client
handle). De-registration is the success criterion; husks are harmless and
`git worktree prune`d.

## 4. Worktrees with potentially-salvageable work

Left in place, surfaced individually to the operator (chat + the
gitignored companion file). Categories observed: real uncommitted code;
untracked design/audit docs; unmerged unique feature commits with no PR;
a multi-worktree abandoned design effort; old orphaned locked
orchestrator worktrees. None auto-deleted. See
`.claude/state/worktree-surface-<date>.md`.

## 5. Systemic fix — SHIPPED

`adapters/claude-code/scripts/worktree-prune.sh` (mirrored to
`~/.claude/scripts/`, byte-identical, `--self-test` PASS). Conservative
pruner: removes a worktree ONLY when fully merged + clean
(noise-filtered) + ≥`--age-days` idle (default 3) + not locked + not
current/main. Everything else → SKIP with reason. Default dry-run;
`--apply` acts. Handles the Windows husk-dir artifact. Documented in
`docs/harness-architecture.md` Scripts table.

## 6. Proposals ranked by feasibility

1. **Periodic cleanup script — DONE & SHIPPED.** Cheapest, fully in our
   control, no Anthropic dependency. The recurring win.
2. **Wire as a weekly scheduled task — READY, needs 1 approval click.**
   `mcp__scheduled-tasks` entry (cron `0 9 * * 1`): dry-run → apply →
   report removed + surface the needs-review list. Spec written this
   session; creation requires interactive approval (blocked in
   unsupervised mode). Alternative: an OS task-scheduler entry running
   `bash ~/.claude/scripts/worktree-prune.sh --apply --repo <main>...`
   weekly.
3. **Auto-cleanup on Dispatch session end — NOT FEASIBLE for us.**
   Requires an Anthropic-side session-end hook on the desktop app's
   Dispatch flow. Not exposed; out of our control. Tracked as an upstream
   ask, not an action item.
4. **Worktree reuse for sequential same-repo sessions — NOT FEASIBLE for
   us.** Requires a Dispatch spawn-side change. Out of our control.
5. **Better naming convention — NOT FEASIBLE for us.** The
   adjective-name-hash scheme is Anthropic-generated. (The pruner makes
   naming moot — it classifies by git state, not name.)

The feasible set is exactly {1, 2}. 1 is shipped; 2 is one approval away
with a documented manual fallback.

## 7. Follow-ups

Tracked as **HARNESS-GAP-35** in `docs/backlog.md` (sub-items A–D:
scheduled-task wiring; upstream auto-cleanup ask; orphaned-locked manual
review; per-worktree salvage decisions).
