# Git — compact
> Enforcement: pre-push-scan.sh, automation-mode-gate.sh, stop-hook-retry-guard.sh; else Pattern — self-applied. Sources: git, git-discipline, branch-hygiene, merge-completed-work, deploy-to-production. Full: doctrine/git-full.md
> Applies: every git operation in every session.

- Commit at natural milestones; `<type>: <description>` (feat/fix/refactor/test/docs/chore). Push at completion points — default is push.
- **NEVER force-push** (`--force`/`-f`/`--force-with-lease`, any branch, no exceptions). Alternatives + rewrite exception: git-full.md Rule 1.
- Never `--no-verify`/`--no-gpg-sign`; honor branch protection. `--amend` only pre-push.
- Post-merge: sync the main checkout (`cd` there; `git fetch origin && git pull --ff-only origin master`); stash/pop around a dirty tree, never auto-resolve pop conflicts. Detail: git-full.md Rule 2.
- Before every commit, run `git status --short` + `git diff --cached --stat` (`git add <path>` doesn't limit scope); doc-only cross-branch commits use `git commit -m "..." -- <path>`. Detail: git-full.md Rule 4.
- Stop-hook blocks on orthogonal plans: write a substantive waiver proactively; never loop "Standing by.", never `--no-verify`, never edit the gate. Detail: git-full.md Rule 3.
- Branch naming: `wip/<machine>-<topic>-<date>`, `feat/`, `fix/`, `salvage/`, `backup/`, `rebase/`. Pop/convert stashes by session end (>24h = leak). Stale (7d, ahead of master): empty diff → delete; else push/rename/PR. Detail: git-full.md "Branch hygiene".
- Merge every opened PR before DONE unless product review, red CI, or conflicts; auto-merge green safe classes (docs, plans, config, tests, deps, cleanup); never leave a green PR >1h.
- Plan-rooted work: add trailer `plan: <slug>` to the squash-commit — primary SHA→plan-slug signal for the merge-emission auditor. Detail: git-full.md "Plan-rooted commit attribution".
- Deploy to production by default; report the production URL, never preview. Skip only on "preview only", red tests, or irreversible migrations (ask). Stacked PRs: merge A, retarget B, merge B. Detail: git-full.md "Deploy to production".
- **Deploy preflight mandatory pre-deploy:** run `~/.claude/scripts/deploy-preflight.sh <commit>... [--repo <checkout>]` — fails closed on fetch failure, dirty tree, stale HEAD, or missing commit. Detail: git-full.md "Deploy preflight".
- Customer tier: pre-customer → `full-auto`; real users → `review-before-deploy`. Detail: git-full.md "Customer-tier branching policy".
- gh/git 404/403 = wrong-account evidence first: `gh auth switch -u <owner>`, retry, then conclude. `gh-account-autoswitch.sh` (PreToolUse) pre-empts this before gh/git write commands. Detail: git-full.md.
