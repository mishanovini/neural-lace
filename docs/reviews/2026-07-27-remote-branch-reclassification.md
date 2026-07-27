# Remote-branch purge re-classification — 2026-07-27

Re-verification of the 2026-07-24 session's "71 SAFE TO DELETE / 9 KEEP" call against
current master (origin/master == pt/master == 7aa2770). **The prior call did not survive
re-verification: 7 branches were safe, not 71.**

## Why the prior number was wrong

Three successive tests were run; only the third is trustworthy.

| Test | Verdict | Defect |
|---|---|---|
| `git cherry` patch-id | 22 safe | UNDER-reports: a squash merge's single commit never patch-id-matches the branch's individual commits. |
| synthetic commit (branch tip tree re-parented at merge-base) + `git cherry` | 35 safe | OVER-reports: for a branch whose tip is a MERGE commit it matched an unrelated equivalent patch. It declared `feat/orchestrator-prime` merged when that branch still exclusively holds `orchestrator-prime.md`, `dispatch-relay-protocol.md` and decision 047 — none on master. A false positive here = permanent loss of unintegrated work. |
| **`git merge-tree --write-tree` containment** | **12 safe** | Authoritative: a branch is contained iff merging it into master is CLEAN *and* yields master's exact tree — i.e. adds literally nothing. Correct for squash merges; no false positives. |

Known conservative bias of the accepted test: a branch that was squash-merged and whose
files master then modified further will re-merge dirty and classify UNIQUE-WORK. That
fails toward keeping, which is the correct direction for an irreversible delete.

## Executed (7 branches, 10 remote refs)

Note: `origin` carries TWO push URLs (github.com + github-pt), so a single
`git push origin --delete` removed the first three from BOTH remotes.

- `claude/distracted-haslett-05e4f8` (pt) — merge-adds-nothing
- `claude/jovial-ishizaka-9a2574` (pt) — merge-adds-nothing
- `feat/plan-lifecycle-mechanical-closure` (pt) — merge-adds-nothing
- `feat/prerequisite-unblocking-pattern` (origin) — merge-adds-nothing
- `feat/prerequisite-unblocking-pattern` (pt) — merge-adds-nothing
- `fix/conv-tree-project-node-header-styling` (origin) — merge-adds-nothing
- `fix/conv-tree-project-node-header-styling` (pt) — merge-adds-nothing
- `handoff/masters-reconciled-2026-07-11` (origin) — merge-adds-nothing
- `handoff/masters-reconciled-2026-07-11` (pt) — merge-adds-nothing
- `session/f1-pr-template-permissions` (pt) — merge-adds-nothing

## NOT deleted — KEEP list honored (operator standing order)

- `lesson/fable-model-facts` (pt) — **re-classified: now CONTAINED** (landed on master as #65 / 99ba24c; origin auto-deleted it on merge). Left in place anyway: explicit KEEP.
- `lesson/status-ground-truth` (pt) — **re-classified: now CONTAINED** (landed as #66 / 62d4e2f). Also currently checked out by a live worktree (`nl-lesson2`). Left in place: explicit KEEP + active session.
- `docs/ownership-gate-lesson-2026-07-11`, `docs/cross-machine-context-handoff-2026-05-24`, `ws-ui-server-stable` — still hold unique work; KEEP confirmed on the merits.
- 4 `harness/active-sessions/*` heartbeat branches (pt) — untouched.

## Operator decision, unchanged and now quantified: NY-1784489893-c961

108 remote branches (42 origin + 66 pt) hold content that is genuinely NOT on master.
They are old, likely-abandoned experiment branches — but "likely abandoned" is not
"integrated", and purging them is a judgment about intent, not a mechanical safety
question. Not agent-actionable. Full per-branch table: `docs/reviews/2026-07-27-remote-branch-classification.tsv`.
