---
title: git stash push of a single file leaves unstashed deletions stageable on branch-switch
date: 2026-05-21
type: process
status: implemented
auto_applied: true
originating_context: misha-decision-batch + FM-001 catalog session 2026-05-21; a downstream-project master commit f664400 unintentionally deleted src/instrumentation.ts + src/instrumentation-client.ts while landing a docs-only FM-001 catalog augmentation
decision_needed: How should the orchestrator avoid the class where switching branches with un-stashed deletions in the working tree silently re-stages those deletions onto the destination branch when `git add <single-file>` is run? Three remediation paths below.
predicted_downstream:
  - adapters/claude-code/rules/git-discipline.md (new sub-rule under Rule 2 or new Rule 4 for cross-branch doc-commit hygiene)
  - adapters/claude-code/rules/orchestrator-pattern.md (dispatch prompt addition for sessions that commit on master from a feature-branch worktree)
  - possibly adapters/claude-code/hooks/cross-branch-doc-commit-gate.sh (PreToolUse Bash on `git commit` when HEAD-branch != master and the staged set spans `docs/` + non-`docs/`)
---

## What was discovered

Session ran the following sequence on the a downstream-project repo to land a docs-only
FM-001 catalog augmentation to master:

1. Worktree was on feature branch `fix/webhook-hardening-2026-05-20` with one
   modified file: `docs/failure-modes/FM-001-nextjs-vercel-bundle-deadlock.md`.
2. `git stash push -m "fm-001-doc-update-temp" docs/failure-modes/FM-001-...md`
   — stashed ONLY that path; other working-tree state was left as-is.
3. `git checkout master` — switched branches.
4. `git stash pop` — restored the FM-001 doc augmentation.
5. `git add docs/failure-modes/FM-001-nextjs-vercel-bundle-deadlock.md` — explicit single-file add.
6. `git commit -m "..."` — created commit `f664400` on master.

Expected: commit contains only the FM-001 doc change. Actual: commit ALSO
contained deletions of `src/instrumentation.ts` (52 lines) and
`src/instrumentation-client.ts` (81 lines) — Sentry runtime-init files
that were modified, not deleted, by the parent commit `91d2ea5`. The
commit shipped 3 files changed, 67 insertions, 135 deletions when it
should have shipped 1 file changed, 67 insertions, 2 deletions.

## Why it matters

The deleted files are load-bearing for Sentry runtime init under Option α'
(`91d2ea5`). Pushing `f664400` to origin/master would break Sentry on the
next deploy and quietly invalidate Misha's recently-shipped FM-001
mitigation. The session's user-facing prose claimed "no code change.
Catalog only." while the actual diff deleted two production runtime files.

Class implications: any docs-only session that operates on master from a
feature-branch worktree carries this risk. The session author cannot rely
on `git add <single-file>` to limit the commit scope — if the working tree
has deletions relative to the destination branch (because the feature
branch had deleted them or because some prior op left the deletions
unstaged), `git commit` will pick those up unless `--only` is used or
`status --short` is checked carefully before committing.

The narrower failure mode: when the feature branch's HEAD has the SAME
files as master (no deletions in branch), but some other operation —
possibly the `git checkout master` step itself with `core.ignoreCase=true`
or `filemode=false` settings — produced a state where the worktree showed
those files as deleted relative to master's index. The session did not
diagnose the root cause of WHY the deletions appeared; only that the
commit picked them up.

The exact mechanism is not yet confirmed. Hypotheses:

- (H1) `git stash push -m "msg" <path>` syntax may have side effects under
  certain git versions (this is Windows git-bash, git for Windows). The
  alternate spelling `git stash push <path> -m "msg"` may behave differently.
- (H2) The feature branch's working tree had pre-existing un-staged deletions
  of `src/instrumentation.ts` and `src/instrumentation-client.ts` that the
  session did not surface via `git status` before stashing. The stash carried
  the named doc file only; the deletions stayed in the index/worktree and
  carried into master via checkout because they were ahead of master.
- (H3) `core.filemode=false` (set in this repo per `.git/config`) combined
  with the Windows symlink-handling could have produced a phantom-deletion
  signal on checkout.

H2 is most likely. If it's H2, the failure is reproducible:
- worktree has modified docs/foo + deleted src/bar.ts (un-staged)
- `git stash push <docs/foo>` stashes only the doc
- `git checkout master` carries the deletion of src/bar.ts into master worktree
- `git stash pop` restores docs/foo
- `git add docs/foo && git commit` ALSO picks up the deletion of src/bar.ts
  because `git add <path>` adds that path but `git commit` (without `--only`)
  commits every staged change PLUS every modified tracked file in the index
  (the deletion was already an index modification carried over from the
  feature branch's stale-index state).

If H2 is the mechanism, the universally-correct discipline is: ALWAYS check
`git status` before `git commit`, even for doc-only commits authored via
explicit `git add <path>`. The mistake was not running `git status` (or
`git diff --cached`) before the commit to confirm the staged set.

## Options

A. **Discipline-only fix.** Add to `git-discipline.md` Rule 2 (post-merge
   sync) or as a new Rule 4: "Before every commit on a branch you are not
   the sole author of, run `git status --short` AND `git diff --cached
   --stat` and confirm the staged set matches your intent. `git add <path>`
   does NOT limit the commit scope to that path." Low cost, relies on
   self-applied discipline.
B. **Hook-enforced fix.** New PreToolUse Bash gate on `git commit` that
   compares the staged-file-set against the message body's claims. When
   the commit message contains "no code change" / "docs only" / "catalog
   only" but the staged set includes non-`docs/` files, BLOCK with a
   structured remediation message. Higher friction; non-trivial regex
   parsing of natural-language commit messages.
C. **Hook-enforced fix (narrower).** New PreToolUse Bash gate on `git commit`
   that ALWAYS surfaces `git diff --cached --stat` to the agent before
   allowing the commit when the staged set spans multiple top-level
   directories (e.g., `docs/` AND `src/`). Forces the agent to acknowledge
   the multi-dir scope before the commit lands. Lower false-positive rate
   than B; doesn't try to parse commit messages.
D. **Convention-only fix.** Use `git commit -- <path>` (the `--` argument
   form) which DOES limit the commit scope to the specified paths,
   ignoring other staged changes. Document this as the canonical doc-only
   commit form. Misses the case where `git add` was already run.

## Recommendation

A + D combined. The discipline (run `git status` before every commit; use
`git commit -- <path>` for doc-only commits) is cheap and universal. The
hook in C is attractive but adds an enforcement layer that may produce
false positives on legitimate multi-dir commits (e.g., a feature commit
that touches `src/` + `docs/` together). The deeper class — agents not
diagnosing the working-tree state before acting — is already partially
addressed by `gate-respect.md` (diagnose before bypass) but is a different
class (this is diagnose BEFORE the destructive action, not diagnose after
a gate blocks). C as a follow-up if A+D recur.

## Decision

**A + D implemented (auto-applied, 2026-06-10 pending-discoveries
triage), exactly per this discovery's own recommendation.** The
remediation is a doc-only rule addition (rule wording within an
established mechanism class — reversible per discovery-protocol), so it
no longer warranted waiting: git-discipline.md gains **Rule 4 —
staged-set verification before every commit** (run `git status --short`
+ `git diff --cached --stat` before committing; `git add <path>` does
NOT limit commit scope) and documents the pathspec-limited
`git commit -m "..." -- <path>` form as the canonical doc-only-commit
shape (D). The hook options (B/C) stay un-built per the recommendation —
C is named in the rule as the candidate follow-up if the discipline
proves insufficient. Note close-plan.sh independently adopted the
pathspec-limited commit form for its closure commit (a70eec2),
corroborating D as the right convention.

## Implementation log

- `adapters/claude-code/rules/git-discipline.md` — new Rule 4
  (staged-set verification + pathspec-limited doc-only commits), title +
  enforcement table updated; cites this discovery as the originating
  failure.
- `adapters/claude-code/rules/INDEX.md` — git-discipline row updated.
- Landed via the 2026-06-10 pending-discoveries-triage branch.
