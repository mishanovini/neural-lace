# Git — full doctrine

> Merged from the former rules: git, git-discipline, branch-hygiene, merge-completed-work, deploy-to-production. Compact: `doctrine/git.md`.

## Git standards

- Commit at natural milestones, not after every small change.
- Clear commit messages: `<type>: <description>` (types: feat, fix, refactor, test, docs, chore).
- **Push commits when work reaches a natural completion point** — feature branch ready for review, atomic commit landed and verified, plan task verified PASS. Default is to push, not to wait. Use safe methods only.
- **Safe push methods.** NEVER force-push (see below). Never use `--no-verify` to bypass pre-commit/pre-push hooks. Never use `--no-gpg-sign` if signing is enabled. Always honor branch-protection rules.
- PR descriptions: what changed, why, how to test; call out breaking changes.
- Never leave uncommitted work at session end — commit or stash.
- **A gh/git "repo not found" / 404 / 403 is wrong-account evidence until the other account is checked.** With two GitHub accounts active, a 404/403 most often means the active `gh auth` account cannot see a repo owned by the other account — NOT that the repo is missing. Run `gh auth switch -u <owner>`, retry, then switch back, before concluding "the repo doesn't exist."
- **`gh-account-autoswitch.sh` (PreToolUse, GH-AUTH-AUTOSWITCH-WORKORG-01) pre-empts the above reactively-discovered case proactively.** It resolves the target repo's owner (via the command's `--repo` flag, the git remote's URL, or the cwd repo's origin) before a `gh pr merge/create/view/checkout/...` or `git push <remote>` command runs, and pre-emptively runs `gh auth switch -u <owner>` if it differs from the currently-active account — so the 404/403 usually never happens at all. It never blocks (every path exits 0); it only prepares the environment ahead of the tool call. The reactive hint in `gh-account-blindness-hint.sh` (PostToolUse) remains the safety net for command shapes the proactive resolver doesn't recognize. Read-only gh/git commands (`gh pr list`, `gh repo list`, plain `git fetch`/`git pull`) are excluded from the write-scope regex and never trigger a switch.

## Rule 1 — Never force-push. No exceptions.

**Never run `git push --force`, `git push -f`, or `git push --force-with-lease`** — not to master, not to a feature branch, not even to a branch you "own." `--force-with-lease` is safer than `--force` against concurrent writers, but it is still a destructive overwrite of remote history and is still prohibited.

**Why absolute:** a force-push silently rewrites the remote branch's history. Downstream consumers (other worktrees, other clones, the main checkout, CI caches, preview deploys) have no way to detect the rewrite other than the next pull failing or silently merging divergent histories. The cost is high, asymmetric, and largely invisible to the agent; the benefit (a cleaner graph) is always achievable through safer paths. Absolute prohibition is the only enforcement that holds under context pressure.

**Safe alternatives (in order):**

a. **Don't rebase in the first place.** Use `git merge origin/master` into the feature branch instead of `git rebase origin/master`. The merge commit preserves both histories and pushes without force. A noisy graph is recoverable; an overwritten remote is not.
b. **Already rebased locally with a stale remote?** Open a NEW branch from current master, cherry-pick the work commits onto it, push that as a new branch, open a fresh PR, close the old PR. Cost: one extra branch and PR. Benefit: zero force-push.
c. **Branch never pushed?** Just push normally — the first push is not a force-push.
d. **History rewriting genuinely required** (e.g., secrets committed to a public branch)? Pause and surface to the operator as a hard-to-reverse decision. Do not act unilaterally.

**Still allowed:** `git commit --amend` BEFORE the first push of a commit (once pushed, never amend). `git reset --hard` against the local working tree when it doesn't require a push to take effect on the remote.

**Enforcement gap (honest):** no PreToolUse hook currently blocks `--force` flags on `git push`. Until such a gate ships, this rule relies on agent discipline and operator interrupt authority.

## Rule 2 — Sync the main checkout after every merge to master

When a session has merged work to `master` (via `gh pr merge`, direct push, or any other path), update the operator's main checkout so their next interactive session sees the merged work.

**The mechanic:**

1. Identify the main checkout: the directory whose `.git` is a directory (not a worktree pointer). `git rev-parse --git-common-dir` returns the parent repo's `.git`; its dirname is the main checkout. If the cwd IS the main checkout, this is a no-op `cd`.
2. `cd` into the main checkout (NOT the worktree).
3. `git fetch origin && git pull --ff-only origin master`.
4. If uncommitted changes would block the pull: `git stash push -u -m "auto-pre-pull-<ISO-timestamp>"`, pull, then `git stash pop`. If the pop produces conflicts in tracked files, surface the conflict markers in the final report — do NOT auto-resolve. The operator's uncommitted work is precious.
5. Do not push from the main checkout; pulling is enough.

**Why:** without the sync, the main checkout drifts behind master after every agent-driven merge. The next interactive session starts stale, sees outdated SCRATCHPAD/plan files, and may re-derive shipped work; the operator's editor silently shows pre-merge content.

**Concrete example:**

```bash
MAIN_CHECKOUT="$(dirname "$(git rev-parse --git-common-dir)")"
if [ "$MAIN_CHECKOUT" != "$(pwd)" ]; then
  cd "$MAIN_CHECKOUT" || exit 1
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push -u -m "auto-pre-pull-$(date -u +%Y%m%dT%H%M%SZ)"
    STASHED=1
  fi
  git fetch origin && git pull --ff-only origin master
  if [ "${STASHED:-0}" = "1" ]; then
    git stash pop || echo "WARNING: stash pop produced conflicts; resolve manually in $MAIN_CHECKOUT"
  fi
fi
```

**Skip conditions:** already running in the main checkout (pull in place, no `cd`); the merge was a no-op (`git diff HEAD origin/master --quiet` after fetch); `--ff-only` would require a merge commit — unexpected, surface it, do NOT fall back to a non-ff merge silently.

## Rule 3 — Stop hooks: write waivers, don't loop

When a Stop hook fires about an ACTIVE plan unrelated to the session's actual scope, author a per-session waiver proactively rather than letting the retry-guard absorb the failure.

**Why proactive waivers beat retry-guard absorption:** the retry-guard caps retries at 3 with identical failure signature, then downgrades to a warn and logs the unresolved gap. Riding that path costs three failed Stop attempts of transcript noise and pollutes the unresolved-gap log with blocks that were never going to resolve. A waiver up-front (one file write, one line of justification) resolves the block cleanly on the first Stop.

**When a waiver is appropriate:** the blocking plan is genuinely orthogonal to this session's work — a prior session's product plan a harness session doesn't exercise; an acceptance plan whose app isn't running in a docs-only session; a stale `Status: ACTIVE` on shipped work (also fix the Status if it's an obvious closure miss). When the plan IS relevant and the block is a real signal, do NOT waive — fix the underlying issue.

**How to author:** write `.claude/state/acceptance-waiver-<plan-slug>-<UTC-timestamp>.txt` with at least one substantive line of justification specific to this session. Generic "not relevant" waivers erode the signal. Waivers have a 1-hour TTL; for longer sessions write a fresh one per Stop attempt.

**Never:** collapse to literal "Standing by." idle responses (they count as retries without moving state); `git commit --no-verify` to dodge a Stop block (wrong gate class entirely); edit the gate's source mid-session to make the block go away (if the gate is wrong, that's its own tracked fix — surface it).

## Rule 4 — Verify the staged set before every commit

**`git add <path>` does NOT limit commit scope** — `git commit` (without pathspec limiting) commits EVERY staged change in the index, including deletions or modifications carried over from a prior branch state you never intended to ship. Originating failure: a docs-only commit authored after `git stash push <single-path>` + branch switch shipped 3 files instead of 1, including deletions of two production runtime files — `git stash push <path>` stashes only the named path; all other working-tree state (including deletions) survives `git checkout` and the next commit silently picks it up.

**The discipline:**

1. **Always check before committing:** `git status --short` + `git diff --cached --stat` immediately before `git commit`, even for "trivial" doc-only commits. Anything staged that you did not author this session → STOP and diagnose before the commit lands.
2. **Use the pathspec-limited commit form for doc-only commits:** `git commit -m "..." -- <path> [<path>...]` — it limits the commit to the named paths regardless of what else is staged. Canonical for cross-branch doc-only commits.
3. **Prefer not switching branches with a dirty tree at all.** If you must, `git stash push -u` (everything, including untracked) rather than single-path stashes, or use a worktree.

## Branch hygiene

### WIP-branch naming convention

| Prefix | When | Example |
|---|---|---|
| `wip/<machine>-<topic>-<date>` | Genuinely in-progress, shape unclear; multi-machine context implied | `wip/laptop-investigate-checkout-divergence-2026-05-29` |
| `feat/<slug>` | Feature with a clear shape; ships via PR | `feat/pre-push-divergence` |
| `fix/<slug>` | Bug fix | `fix/sync-script-unbound-trap` |
| `salvage/<short-id>` | Extracting work from a dead session | `salvage/dead-session-review` |
| `backup/<context>` | Snapshot before a risky operation | `backup/pre-rebase-2026-05-27` |
| `rebase/<context>` | Active rebase work-area; short-lived | `rebase/cleanup-merge-conflicts` |
| `reconverge/<context>` | Cross-fork reconciliation | `reconverge/prs-40-44-2026-05-28` |
| `sync/<context>` | Cross-fork sync working branches | (auto-generated) |

Machine goes in `wip/` names so it's clear which machine the work originated on and whether it might be live; the date makes the stale-branch policy mechanically applicable. The other prefixes imply a sharp exit condition that closes within hours. Branches matching the prefix list are treated as expected-WIP by the session-start freshness surfacer; non-matching branches with uncommitted changes trigger a warning.

### Stash-lifetime discipline

A stash is a temporary holding pen for "switch branches, run something, come back" — NOT storage for tomorrow. **Stashes older than 24 hours are a leak signal**: needed work belongs on a real branch (`git stash branch <wip-name> stash@{N}`); unneeded work belongs deleted. At session end, pop or convert every stash. Audit `git stash list` at session start. When a long-lived stash is unavoidable, name it with date + reason: `git stash push -u -m "auto-pre-branch-switch-$(date -u +%Y%m%dT%H%M%SZ): <reason>"`.

### Stale-branch policy

A local branch is stale when ALL hold: ahead of master by ≥1 commit; not pushed in 7 days; no new commit in 7 days. Stale branches are surfaced at session start, never auto-deleted. Per branch, the decision tree:

1. **Content shipped elsewhere?** Confirm with `git diff <branch> master`; empty diff → `git branch -D <branch>`.
2. **Work no longer relevant** (wrong hypothesis, descoped)? Delete after a final check.
3. **Still in-flight?** Push it, OR rename to `wip/<machine>-...`, OR convert to a tracked PR.
4. **Backup/salvage from a specific moment?** Audit whether the need is still active; if not, delete.

## Merge completed work — standing rule

Every session that opens a PR MUST merge it before reporting DONE, unless: the PR touches product code requiring explicit operator review (feature changes, migrations, API changes); the PR has failing CI; or it has merge conflicts needing resolution.

Merge these classes automatically when CI passes — do NOT leave them sitting: documentation (docs/, README, CHANGELOG); audit findings and reports; plan files and status flips; config changes (workflows, lint configs); test-only changes; dependency bumps with green CI; cleanup (branch deletion, stale-file removal).

For product-code PRs: track the PR until merged — don't report DONE until it's on master. If CI passes and the change is safe (no user-facing behavior change), merge it. If it IS user-facing, flag it for the operator's review but still track until merged. Never leave a green PR sitting more than 1 hour without action. The pattern "open PR → move on → forget" is the single biggest source of drift; this rule exists to make it impossible.

## Deploy to production — default behavior

**Always deploy to production unless the user explicitly asks for a preview or staging target.** Previews are a staging ground for the agent's own tests, not a destination. After tests pass, work lands on master and deploys to production — leaving work on a feature branch with "here's the preview URL" is wasted latency.

**Mechanism:** the per-project `automation-mode.json` config. `mode: full-auto` auto-approves deploy-class commands; `mode: review-before-deploy` pauses for human authorization. Resolution: `<project>/.claude/automation-mode.json` → `~/.claude/local/automation-mode.config.json` → fallback (`review-before-deploy`). Pre-customer projects typically run `full-auto`; once real users exist, flip to `review-before-deploy`. Switch via `/automation-mode`.

**In practice, when a feature branch is green** (tests pass against live dev + DB, typecheck passes, commits clean): push the branch; open/update the PR; merge to master per project convention; confirm the production deploy succeeded (`gh pr checks` or dashboard); report the production URL, not the preview URL. Do NOT wait for the user to say "now merge it."

**Do NOT auto-deploy when:** the user says "preview only" or "don't merge yet"; the work is an explicit WIP draft awaiting review; tests are failing (never ship red); migrations have irreversible data effects warranting manual review — surface and ask.

**Stacked PRs:** if PR B targets PR A's branch, merge A first, retarget/rebase B to master, merge B. Both land; both deploy.

**Confirmation signal after merging:** the production URL (not preview); a clear summary of what merged and is now live; a note on any migrations applied.

**Customer-tier branching policy:** pre-customer projects (no real users): feature-branch merges to master and direct master commits are acceptable; the cost of a bad push is self-inflicted and reversible via revert + redeploy. Once a project has real users: all work goes through a `dev`/`preview` branch with deployment-validation gates before merging to the customer-facing branch; branch protection at the GitHub level enforces it. Auto-merge on verified-complete uses `--no-ff` merge commits to preserve the feature-branch audit trail; skip auto-merge only when the user said "preview only"/"don't merge"/"wait" in their most-recent message, or the branch contains genuinely unreviewed risky work (irreversible operations, schema migrations, auth changes).
