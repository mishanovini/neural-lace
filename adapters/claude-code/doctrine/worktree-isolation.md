# Worktree Isolation — compact
> Enforcement: session-start-worktree-advisor.sh (SessionStart, informs), worktree-teardown-gate.sh (Stop, blocks).
> Applies: any session making commits in a repo other live sessions also touch.

- Work in your own git worktree, not the shared main checkout — concurrent sessions collide on the working tree, the index, and `git stash`/`git clean`.
- Incomplete ≠ abandoned: a worktree with uncommitted or unpushed work holds WANTED work. preserve first — commit, stash, or push — never `--force` deletion (`git worktree remove --force` destroys unmerged work).
- Teardown at Stop: uncommitted work in your own worktree → blocked toward preserve-first; clean-but-unpushed → advisory only (committed work survives `git worktree remove`; it dies only on `git branch -D`).
- Exemptions (worktree not wanted): read-only sessions; on-main-checkout-by-necessity (post-merge sync, worktree removal); already isolated (linked worktree or cloud VM); not a git repo; another session's or locked worktree — never disturb; tiny ancillary edits; emergency hotfix.
- Fresh-worktree cost: copy gitignored env (`.env.local`) + run installs where applicable — budget for it before taking the advice.
- Escape hatch: fresh substantive `.claude/state/worktree-teardown-waiver-*.txt` (<1h).
- Known limit: creating a worktree then ending the session from the main checkout is not caught — self-apply the preserve-first check.
