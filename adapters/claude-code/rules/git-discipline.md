# Git Discipline — Force-Push Prohibition, Post-Merge Sync, Stop-Hook Waivers

**Classification:** Pattern (self-applied discipline). The force-push prohibition is partly Mechanism-backed — `~/.claude/git-hooks/pre-push` runs the credential scanner and existing harness gates reject `--no-verify` bypasses, but a `git push --force` to a non-protected branch is not currently blocked by any harness hook. The post-merge sync of the user's main checkout is Pattern only — no hook detects "merged but did not sync." The waiver-instead-of-loop discipline for Stop hooks is Pattern; the underlying mechanism is the retry-guard library at `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh` which downgrades blocks to warns after 3 retries, but the right move BEFORE that threshold is to author a substantive waiver, not let the retry-guard absorb the failure.

**Why this rule exists:** the user observed (2026-05-14) that every code session was asked to re-explain merge / sync / waiver mechanics in its prompt. Baking these into the harness means every future session inherits them automatically without per-task prompting.

## Rule 1 — Never force-push. No exceptions.

**Never run `git push --force`, `git push -f`, or `git push --force-with-lease`** — not to master, not to a feature branch, not even to a branch you "own." This is absolute. `--force-with-lease` is safer than `--force` against concurrent writers, but it is still a destructive overwrite of remote history and is still prohibited.

### Why this is absolute

A force-push silently rewrites the remote branch's history. Downstream consumers (other worktrees, other clones, the user's main checkout, CI caches, deployed previews tracking the branch) have NO way to detect the rewrite other than the next pull failing or — worse — silently merging the divergent histories together. The cost of a bad force-push is high, asymmetric, and largely invisible to the agent. The benefit (cleaner commit graph, "fixing" a rebase) is always achievable through safer paths.

LLM agents are also prone to "loud is not rare": the option exists, the option's name doesn't sound alarming relative to other commands the agent runs constantly, and the agent will reach for it the moment a normal push fails. Absolute prohibition is the only enforcement that holds under context pressure.

### Safe alternatives (in order)

When the feature branch has been rebased locally and the remote has the pre-rebase version (the canonical situation that tempts force-push):

a. **Don't rebase in the first place.** Instead of `git rebase origin/master`, use `git merge origin/master` into the feature branch. This creates a merge commit that preserves both histories and pushes without force. Merge commits are slightly noisier in `git log --graph` than a clean rebase, but the trade is correct: a noisy graph is recoverable; an overwritten remote is not.

b. **If you've already rebased locally and need to update the remote** — open a NEW branch from current master, cherry-pick the work commits onto it, push that as a new branch, open a fresh PR from the new branch, close the old PR. Cost: one extra branch and PR. Benefit: zero force-push.

c. **If the branch was never pushed** — just push normally. There's nothing on the remote to overwrite; the first push is not a force-push.

d. **If the situation genuinely demands history rewriting** (e.g., secrets accidentally committed to a public branch) — pause and surface to the user as a Tier 3 decision per `planning.md`. Do not act unilaterally.

### What the harness still allows

`git commit --amend` is allowed BEFORE the first push of a commit (the commit is still local). Once a commit has been pushed, do NOT amend — the next push would require force.

`git reset --hard` is allowed against your local working tree if it doesn't require a push to take effect on the remote (e.g., resetting an unpushed branch). It is NOT a path to force-push.

### Enforcement gap (honest)

There is currently no PreToolUse hook on `git push` that blocks `--force` / `--force-with-lease` / `-f` flags. This is a candidate for mechanization (proposed: `force-push-prohibition-gate.sh` PreToolUse Bash). Until the gate ships, this rule relies on agent discipline and on the user's interrupt authority when they see a force-push attempt.

## Rule 2 — Sync the user's main checkout after every merge to master

When a code session has merged work to `master` (via `gh pr merge`, direct push to master, or any other path that lands commits on master), the session must update the user's main checkout so their next interactive session sees the merged work.

### The mechanic

1. Identify the user's main checkout. Convention: for any repo the agent is working in, the main checkout is the directory containing `.git/` as a directory (not as a file pointing at a worktree). Concretely, `git rev-parse --git-common-dir` returns the parent repo's `.git` directory; `dirname` of that is the main checkout. If the agent's cwd is itself the main checkout (no worktree), this step is a no-op.

2. `cd` into the main checkout (NOT the worktree).

3. `git fetch origin && git pull --ff-only origin master`.

4. If the main checkout has uncommitted changes that would block the pull:
   - `git stash push -u -m "auto-pre-pull-<ISO-timestamp>"` to preserve them.
   - `git pull --ff-only origin master`.
   - `git stash pop` to restore them.
   - If `git stash pop` produces merge conflicts in tracked files, surface the conflict markers in the final report — DO NOT auto-resolve content conflicts. The user's uncommitted work is precious.

5. Do not push from the main checkout. Pulling is enough; the merge already landed via the original push path.

### Why this is required

Without the sync, the user's main checkout drifts behind master after every agent-driven merge. The next interactive session starts from a stale state, sees outdated SCRATCHPAD / plan files / recent commits, and may re-derive work the agent already shipped. Worse, the user's editor (which they likely have open against the main checkout) silently shows pre-merge content.

### Concrete example (Windows Git Bash path style)

```bash
# Inside the worktree, after `gh pr merge --merge` (or direct push) lands work on master:
MAIN_CHECKOUT="$(dirname "$(git rev-parse --git-common-dir)")"
if [ "$MAIN_CHECKOUT" != "$(pwd)" ]; then
  cd "$MAIN_CHECKOUT" || exit 1
  if ! git diff --quiet || ! git diff --cached --quiet; then
    STASH_NAME="auto-pre-pull-$(date -u +%Y%m%dT%H%M%SZ)"
    git stash push -u -m "$STASH_NAME"
    STASHED=1
  fi
  git fetch origin && git pull --ff-only origin master
  if [ "${STASHED:-0}" = "1" ]; then
    if ! git stash pop; then
      echo "WARNING: stash pop produced conflicts; resolve manually in $MAIN_CHECKOUT"
      # Surface in final report; do NOT auto-resolve
    fi
  fi
fi
```

### Skip conditions

- The agent is already running in the main checkout (no worktree). Pull from the agent's cwd; no `cd` needed.
- The merge was a no-op (nothing actually landed). Detect via `git diff HEAD origin/master --quiet` after fetch.
- `git pull --ff-only` would require a merge commit (non-fast-forward). This is unexpected — surface it to the user; do NOT fall back to a non-ff merge silently.

### Enforcement gap (honest)

No hook currently runs this sync automatically. The discipline is Pattern-only. A future SessionStart hook could detect "main checkout is behind origin/master by N commits" and run the sync proactively. Until that ships, the agent runs the sync inline after every merge.

## Rule 3 — Stop hooks: write waivers, don't loop

When a Stop hook fires about an ACTIVE plan unrelated to the session's actual scope (most commonly `product-acceptance-gate.sh` for an exempt-by-context plan from a prior session that didn't get flipped), the right move is to author a per-session waiver proactively rather than let the retry-guard absorb the failure.

### Why proactive waivers beat retry-guard absorption

The retry-guard library (`adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh`) caps retries at 3 with identical failure signature + same git HEAD; after the threshold, the block downgrades to a warn and the unresolved gap is appended to `.claude/state/unresolved-stop-hooks.log`. This is a safety net against unresolvable loops — but it is NOT the intended path for known-irrelevant blocks. Letting the retry-guard absorb the failure has two costs:

- Three failed Stop attempts before the downgrade — each one consumes a model turn and pollutes the transcript with retry noise.
- The unresolved-gap log accumulates entries for blocks that were never going to resolve, drowning the signal of genuine residual gaps.

Authoring a waiver up-front (one file write, one line of justification) resolves the block cleanly on the first Stop and leaves no retry-guard footprint.

### When a waiver is appropriate

The plan that's blocking is genuinely orthogonal to the work in this session. Common examples:

- An ACTIVE plan from a prior session targeting product code that this harness-improvement session is not exercising.
- An acceptance-scenarios plan whose live app isn't running because this session is a harness/docs-only session.
- A plan whose `Status:` is stale (the work shipped; `Status: ACTIVE` was never flipped to `COMPLETED`) — in this case, after writing the waiver, also fix the plan's Status if it's an obvious closure miss.

When the plan IS relevant and the block is a real signal (the session's actual work failed acceptance), do NOT waive. Fix the underlying issue.

### How to author a waiver

For `product-acceptance-gate.sh` (the most common Stop-hook block):

```bash
mkdir -p .claude/state
cat > ".claude/state/acceptance-waiver-<plan-slug>-$(date -u +%Y%m%dT%H%M%SZ).txt" <<'EOF'
This session is harness-improvement work on the neural-lace repo and does not exercise
the <plan-slug> product code. The plan's runtime acceptance is gated on a live app that
is not running in this session. The plan remains ACTIVE and its acceptance gate will
run normally in the next session that exercises the product code.
EOF
```

Substantive ≥ 1 line of justification is required (per `acceptance-scenarios.md` and the gate's documented contract). Generic waivers like "not relevant" without context are themselves a failure mode — they erode the signal.

The waiver has a 1-hour TTL by gate convention (mirrors `bug-persistence-gate.sh`). For sessions longer than an hour where the same block keeps firing, write a fresh waiver per Stop attempt rather than reusing.

### What never to do

- **Never collapse to literal "Standing by." idle responses** when a Stop hook is blocking. The retry-guard interprets identical-signature failures as the same incident; literal idle replies don't move the state forward but DO count as retries. Either fix the underlying issue or write the waiver — not stall.

- **Never `git commit --no-verify` to bypass a Stop-hook block.** Stop hooks don't fire on commit; `--no-verify` skips PreCommit / pre-push hooks. Mixing the two is a sign the agent has lost track of which gate is blocking.

- **Never disable the gate by editing its source mid-session** to make the block go away. If the gate's logic is genuinely wrong, that's a harness-improvement task in its own right — open a discovery file per `discovery-protocol.md`, surface to the user, do not unilaterally rewrite the gate.

### Cross-references

- `~/.claude/rules/acceptance-scenarios.md` — defines the waiver mechanism for `product-acceptance-gate.sh`.
- `~/.claude/hooks/lib/stop-hook-retry-guard.sh` — the retry-guard library (3-retry threshold, identical-signature counting).
- `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized" — the `narrate-and-wait-gate.sh` discipline that overlaps with this rule's "never collapse to Standing by." prohibition.

## Cross-references

- `~/.claude/rules/git.md` — the broader Git Standards rule; references this file for force-push, post-merge sync, and merge-vs-rebase discipline.
- `~/.claude/rules/planning.md` — Tier 3 decision protocol for the rare case where history rewriting is genuinely warranted.
- `~/.claude/rules/orchestrator-pattern.md` — describes how parallel-builder worktrees relate to the user's main checkout; the post-merge sync is the inverse direction (worktree → main checkout) of the rule's "commit before dispatch" discipline.
- `~/.claude/rules/security.md` — the broader credential-and-destructive-ops perimeter that force-push falls under.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | Force-push prohibition, post-merge sync mechanic, waiver-before-retry-guard discipline | `adapters/claude-code/rules/git-discipline.md` | landed |
| Hook (existing) | Pre-push credential scanner (does not block `--force` flags directly) | `adapters/claude-code/hooks/pre-push-scan.sh` | landed |
| Hook (existing) | Stop-hook retry-guard caps loops at 3 retries; this rule says use waivers BEFORE the threshold | `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh` | landed |
| Hook (gap) | PreToolUse Bash blocker on `git push --force` / `-f` / `--force-with-lease` | (not yet implemented) | gap |
| Hook (gap) | PostMerge sync trigger for user's main checkout | (not yet implemented) | gap |

The rule is documentation-enforced (Pattern). The two gaps are candidates for future mechanization; until they ship, the discipline relies on agent self-application and on user interrupt authority.

## Scope

This rule applies in any project whose Claude Code installation has this rule file present at `~/.claude/rules/git-discipline.md`. The rule is loaded contextually by Claude Code's harness; no opt-in or hook wiring is required to make the rule active. The post-merge sync mechanic is universally applicable (any git-based project with a worktree topology). The force-push prohibition is universally applicable. The Stop-hook waiver discipline applies wherever the retry-guard library is wired (8 blocking Stop hooks as of 2026-05-09).
