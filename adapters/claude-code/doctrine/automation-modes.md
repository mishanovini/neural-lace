# Automation Modes — compact
> Enforcement: Pattern — self-applied mode choice, no hook blocks the "wrong" mode. Full: doctrine/automation-modes-full.md
> Applies: choosing where a Claude Code session runs, before starting work.

Five modes, pick the one whose enforcement matches the task:

1. **Interactive local** (default) — full `~/.claude/` harness, single session per working tree. Tight-loop work, UX calls, live steering.
2. **Parallel local (worktrees)** — full harness, git-tree isolation, `~/.claude/` state SHARED across sessions (risk: race on state files). 2-5 concurrent short builds via `isolation: "worktree"` or Desktop "+ New session."
3. **Cloud remote (`claude --remote`)** — fully isolated VM, but inherits **project `.claude/`** ONLY, not `~/.claude/`. Requires the harness committed/symlinked into the repo's own `.claude/` for enforcement to carry over (Decision 011 Approach A). Best for multi-hour autonomous builds you won't supervise.
4. **Scheduled (`/schedule` Routines)** — same isolation + same project-`.claude/`-only inheritance as cloud remote, on a cron/event trigger. Best for nightly verification, recurring jobs.
5. **Agent Teams** (experimental, feature-flagged, disabled by default) — lead spawns peer teammates messaging each other directly. Enable only when continuous teammate-to-teammate coordination is load-bearing; prefer `orchestrator-pattern` (Task-tool dispatch) otherwise — it's the more battle-tested topology.
- Decision tree: live judgment on each step → mode 1. Cron/event trigger → mode 4. Multi-hour unsupervised → mode 3 (verify project `.claude/` is populated first). Direct teammate messaging needed → mode 5 (read `doctrine/agent-teams.md` first — five known upstream bugs). 2-5 concurrent disjoint-file builds → mode 2. Default → mode 1.
- Never run two Mode-1 sessions on the same working tree without worktrees — they share `~/.claude/` state, the git tree, and every `state/` file; a sibling's `git stash`/`git clean` can wipe uncommitted work.
- Modes compose: a Mode-1 orchestrator commonly dispatches Mode-2 or Mode-3 builders.
