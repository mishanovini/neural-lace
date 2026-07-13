# Git — compact
> Enforcement: pre-push-scan.sh, automation-mode-gate.sh, stop-hook-retry-guard.sh; else Pattern — self-applied. Sources: git, git-discipline, branch-hygiene, merge-completed-work, deploy-to-production. Full: doctrine/git-full.md
> Applies: every git operation in every session.

- Commit at milestones; messages `<type>: <desc>` (feat, fix, refactor, test, docs, chore). Push at completion points — default push, not wait.
- **NEVER force-push** (`--force`, `-f`, `--force-with-lease`) — any branch, no exceptions. Alternatives + the leaked-secret history-rewrite exception (→ pause the operator): full doctrine.
- Never `--no-verify` or `--no-gpg-sign`; honor branch protection. `--amend` only before first push.
- Post-merge sync: after any merge to master, `cd` to the main checkout and `git fetch && git pull --ff-only origin master` (stash/pop around uncommitted; surface stash-pop + non-ff conflicts, never auto-resolve).
- Staged-set verify before every commit: `git status --short` + `git diff --cached --stat` (`git add <path>` does NOT scope the commit). Doc-only commit after a branch switch: pathspec form `git commit -m "..." -- <path>`.
- Stop-hook blocks on plans orthogonal to the session: write a substantive waiver proactively; never loop "Standing by.", never bypass with `--no-verify`, never edit the gate mid-session.
- Branch naming: `wip/<machine>-<topic>-<date>`, `feat/`, `fix/`, `salvage/`, `backup/`, `rebase/`. Stashes: pop or branch-convert by session end (>24h = leak). Stale branch (untouched 7d): empty diff → delete; else push, rename to wip/, or PR.
- Every session that opens a PR must merge before reporting DONE, unless it needs product review, has failing CI, or has conflicts. Auto-merge green safe classes (docs, plans, config, tests-only, dep bumps, cleanup); never leave a green-mergeable PR >1h.
- Plan-rooted work: when a PR/squash-merge serves an active plan, add a `plan: <slug>` trailer to the squash-commit body — the primary SHA→plan attribution signal the merge-emission auditor reads (diff-touches-`docs/plans/<slug>.md` is the fallback).
- Deploy to production by default: verified work lands on master and deploys; report the production URL, never the preview. Skip only on explicit "preview only", red tests, or irreversible migrations (ask first). Stacked PRs: merge A, retarget B, merge B.
- **Deploy preflight is mandatory before any production deploy:** run `~/.claude/scripts/deploy-preflight.sh <intended-commit>...` — it FAILS CLOSED on fetch failure, dirty tree, HEAD != origin/master, or a missing commit (incident 2026-06-18).
- Customer tier: pre-customer → `full-auto` (direct master, auto-merge on green); real users → `review-before-deploy` (per-project `automation-mode.json`).
- gh/git 404/403 is wrong-account evidence first: `gh auth switch -u <owner>`, retry, then conclude. `gh-account-autoswitch.sh` (PreToolUse) pre-empts it before gh/git write commands run.
