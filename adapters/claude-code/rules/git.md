# Git Standards

- Commit at natural milestones, not after every small change
- Clear commit messages: `<type>: <description>` (types: feat, fix, refactor, test, docs, chore)
- **Push commits when work reaches a natural completion point** — feature branch ready for review, atomic commit landed and verified, plan task task-verified PASS. Default is to push, not to wait. Use safe methods only.
- **Safe push methods.** Never force-push to protected branches. Never use `--no-verify` to bypass pre-commit/pre-push hooks. Never use `--no-gpg-sign` if signing is enabled. Always honor branch-protection rules.
- **Customer-tier branching policy.** Pre-customer projects (no real users yet): pushing feature branches and merging to master (which deploys to production) is acceptable; the cost of a bad push is mostly self-inflicted and reversible via revert + redeploy. **Once a project has real users**: all work must go through a `dev` or `preview` branch with deployment-validation gates passing before merge to the customer-facing branch (typically `master` or `main`). The harness does not yet auto-detect customer-tier; per-project judgment for now, mechanical enforcement may follow.
- Never commit directly to `main` or `master` — use branches and PRs
- Never force-push to protected branches
- PR descriptions: what changed, why, how to test; call out breaking changes
- Never leave uncommitted work at session end — commit or stash
