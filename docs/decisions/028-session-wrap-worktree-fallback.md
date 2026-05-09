# Decision 028 — `session-wrap.sh` falls back to parent repo's SCRATCHPAD when run from a worktree

- **Date:** 2026-05-09
- **Status:** Active
- **Stakeholders:** harness maintainer; every Claude Code session that runs in a git worktree

## Context

`session-wrap.sh` is the Stop-hook freshness verifier introduced by ADR 027 Layer 5. Its first signal — `SCRATCHPAD.md mtime within 30 minutes` — uses `git rev-parse --show-toplevel` (via `find_repo_root`) to locate the SCRATCHPAD. From inside a git worktree, that returns the worktree's path, not the parent repo's. Worktrees do not carry their own SCRATCHPAD by convention (the orchestrator-pattern explicitly treats them as short-lived build isolation); the parent repo holds the authoritative SCRATCHPAD.

The result: every Stop event from a worktree session reports `SCRATCHPAD.md is 1666666 min stale` because `mtime_seconds_ago` returns the missing-file sentinel for the absent worktree-local SCRATCHPAD. The hook cries wolf, training operators to ignore the signal — which weakens it for the case it was designed to catch (genuinely stale parent SCRATCHPADs in non-worktree sessions).

Captured as discovery `docs/discoveries/2026-05-09-session-wrap-worktree-blind.md`.

## Decision

`session-wrap.sh`'s `find_repo_root` (or the equivalent SCRATCHPAD-locator) detects worktree context via `git rev-parse --git-common-dir` ≠ `git rev-parse --git-dir` and returns the parent repo's toplevel (`dirname` of `--git-common-dir`) when the two differ. When they're equal (primary repo), behavior is unchanged.

The fix preserves the rule that should hold: **one SCRATCHPAD per repo, in the parent**. The hook now honors that rule from worktrees too.

The worktree-local SCRATCHPAD created in this session as immediate workaround (at `stupefied-brattain-94152b/SCRATCHPAD.md`) is now redundant and is deleted as part of Task 2 cleanup of the parent plan.

## Alternatives Considered

- **Per-worktree SCRATCHPAD convention.** Document that every worktree carries a thin pointer SCRATCHPAD that just references the parent. Hook stays as-is. **Rejected** because (a) every new worktree would need ceremony (create + commit a pointer SCRATCHPAD) — easy to forget; (b) orchestrator-pattern.md explicitly says worktrees are short-lived build isolation, not long-running branches with their own state; (c) auto-creating the pointer file would require yet another hook (worktree-add or session-start), adding mechanism cost for a problem that's just hook-side blindness.
- **Hook silent-pass in worktrees.** Detect worktree context and skip the SCRATCHPAD freshness signal entirely (still run other 5 signals). **Rejected** because worktree sessions DO sometimes need to keep the parent's SCRATCHPAD fresh (when the work is substantive harness changes), and silent-pass means the operator gets zero feedback on freshness — exactly the opposite of what Layer 5 was for.

## Consequences

- **Enables:** consistent freshness signal across primary-repo and worktree sessions; operators don't need to learn a worktree-specific workflow.
- **Costs:** ~10 lines of bash plus an extra self-test scenario. Worktrees that genuinely want their own SCRATCHPAD (rare per orchestrator-pattern; not a current use case) lose that capability — they would now read the parent's instead. Mitigation: not currently used; if it ever becomes load-bearing, the option-B convention can be revisited.
- **Reversibility:** trivial. Single-commit revert restores prior behavior.
- **Side-effects:** changes the path the hook reads; downstream tooling that calls `find_repo_root` for non-SCRATCHPAD reasons should be checked. Audit during implementation: only `session-wrap.sh` itself uses `find_repo_root` (grep-confirmed at change time).
