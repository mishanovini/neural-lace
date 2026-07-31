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
question. Not agent-actionable.

Full per-branch evidence — the 108 branches holding content NOT on master, and what
merging each into master would add:

| Remote | Branch | Merging it would add |
|---|---|---|
| origin | `audit/agent-incentive-structure-audit-2026-05-24` |  1 file changed, 106 insertions(+) |
| origin | `backup/personal-master-pre-cutover-20260528-100528` |  16 files changed, 6740 insertions(+) |
| origin | `chore/triage-stale-plans-2026-06-17` |  2 files changed, 842 insertions(+) |
| origin | `ci/eats-own-cooking-2026-05-23` |  9 files changed, 4280 insertions(+) |
| origin | `ci/server-side-enforcement-2026-05-23` |  9 files changed, 4322 insertions(+) |
| origin | `claude/agitated-thompson-84c93e` |  1 file changed, 4 insertions(+) |
| origin | `claude/amazing-fermi-233a5a` |  1 file changed, 11 insertions(+) |
| origin | `claude/beautiful-mcnulty-e8bc42` |  1 file changed, 3 insertions(+) |
| origin | `claude/busy-hawking-0daea8` |  8 files changed, 182 insertions(+), 10 deletions(-) |
| origin | `claude/clever-wu-d1a00c` |  4 files changed, 107 insertions(+), 15 deletions(-) |
| origin | `claude/condescending-bouman-f442a1` |  1 file changed, 15 insertions(+) |
| origin | `claude/serene-turing-0b131e` |  3 files changed, 671 insertions(+) |
| origin | `claude/sleepy-albattani-0d9012` |  10 files changed, 466 insertions(+), 11 deletions(-) |
| origin | `claude/vibrant-fermi-acf761` |  6 files changed, 4121 insertions(+) |
| origin | `conv-tree-ui-v1.1.2-polish` |  1 file changed, 85 insertions(+) |
| origin | `docs/agent-incentive-structure-audit-2026-05-24` |  7 files changed, 4227 insertions(+) |
| origin | `docs/cross-machine-context-handoff-2026-05-24` |  6 files changed, 4121 insertions(+) |
| origin | `docs/ownership-gate-lesson-2026-07-11` |  1 file changed, 4 insertions(+) |
| origin | `docs/rules-index-and-diagnostic-evidence-template-2026-05-23` |  12 files changed, 4509 insertions(+) |
| origin | `feat/agent-upgrades-batch2-2026-06-10` |  90 files changed, 7249 insertions(+) |
| origin | `feat/capture-codify-pr-template` |  9 files changed, 1508 insertions(+) |
| origin | `feat/customer-facing-review-gate-2026-06-01` |  8 files changed, 1509 insertions(+) |
| origin | `feat/decision-context-gate-2026-05-29` |  2 files changed, 31 insertions(+), 1 deletion(-) |
| origin | `feat/decision-queue` |  15 files changed, 5108 insertions(+) |
| origin | `feat/deterministic-workstreams-turn-emit` |  4 files changed, 2323 insertions(+) |
| origin | `feat/docs-refresh-tech-team-architecture` |  6 files changed, 984 insertions(+) |
| origin | `feat/drift-backlog-and-harness-evaluator` |  14 files changed, 5211 insertions(+) |
| origin | `feat/orchestrator-prime-finish` |  1 file changed, 12 insertions(+), 6 deletions(-) |
| origin | `feat/orchestrator-prime` |  9 files changed, 512 insertions(+) |
| origin | `feat/plan-lifecycle-closure-machine` |  8 files changed, 1074 insertions(+) |
| origin | `feat/pr-health-snapshot-gate-2026-06-01` |  7 files changed, 1392 insertions(+) |
| origin | `feat/worktree-isolation-enforcement-2026-06-23` |  7 files changed, 1331 insertions(+) |
| origin | `fix/pr-template-inline-gate-2026-05-24` |  19 files changed, 5571 insertions(+) |
| origin | `fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24` |  10 files changed, 4308 insertions(+) |
| origin | `fix/workstreams-ui-reflect-real-status` |  3 files changed, 521 insertions(+) |
| origin | `salvage/main-checkout-triage-2026-06-09` |  65 files changed, 58805 insertions(+), 47 deletions(-) |
| origin | `strategy/test-design-2026-05-23` |  6 files changed, 4121 insertions(+) |
| origin | `wip/preserve-nl-main-20260614` |  60 files changed, 69087 insertions(+), 45 deletions(-) |
| origin | `worker-gap-40-pr-template-inline-gate` |  14 files changed, 5211 insertions(+) |
| origin | `worker-workstreams-completed-filter-fix` |  2 files changed, 683 insertions(+) |
| origin | `worktree-agent-a341c8690244590d4` |  6 files changed, 4121 insertions(+) |
| origin | `ws-ui-server-stable` |  1 file changed, 55 insertions(+), 15 deletions(-) |
| pt | `build/cockpit-health-int` |  1 file changed, 7 insertions(+) |
| pt | `build/cockpit-sessionstart` |  2 files changed, 101 insertions(+) |
| pt | `ci/eats-own-cooking-2026-05-23` |  9 files changed, 4280 insertions(+) |
| pt | `ci/server-side-enforcement-2026-05-23` |  9 files changed, 4322 insertions(+) |
| pt | `claude/agitated-thompson-84c93e` |  1 file changed, 4 insertions(+) |
| pt | `claude/amazing-fermi-233a5a` |  1 file changed, 11 insertions(+) |
| pt | `claude/busy-hawking-0daea8` |  8 files changed, 182 insertions(+), 10 deletions(-) |
| pt | `claude/clever-wu-d1a00c` |  4 files changed, 107 insertions(+), 15 deletions(-) |
| pt | `claude/condescending-bouman-f442a1` |  1 file changed, 15 insertions(+) |
| pt | `claude/fable-continue` |  1 file changed, 3 insertions(+) |
| pt | `claude/modest-satoshi-150d97` |  1 file changed, 20 insertions(+) |
| pt | `claude/serene-turing-0b131e` |  3 files changed, 671 insertions(+) |
| pt | `claude/sleepy-albattani-0d9012` |  10 files changed, 466 insertions(+), 11 deletions(-) |
| pt | `claude/vibrant-fermi-acf761` |  6 files changed, 4121 insertions(+) |
| pt | `conv-tree-ui-v1.1.2-polish` |  1 file changed, 85 insertions(+) |
| pt | `conv-tree-v4-accordion-adoption` |  7 files changed, 3805 insertions(+) |
| pt | `docs/agent-incentive-structure-audit-2026-05-24` |  7 files changed, 4227 insertions(+) |
| pt | `docs/cross-machine-context-handoff-2026-05-24` |  6 files changed, 4121 insertions(+) |
| pt | `docs/harness-gap-cloud-orchestrator-hook-detector-2026-05-23` |  7 files changed, 4135 insertions(+) |
| pt | `docs/ownership-gate-lesson-2026-07-11` |  1 file changed, 4 insertions(+) |
| pt | `docs/reclamation-proposal-amendment` |  1 file changed, 124 insertions(+) |
| pt | `docs/rules-index-and-diagnostic-evidence-template-2026-05-23` |  12 files changed, 4509 insertions(+) |
| pt | `feat/agent-upgrades-batch2-2026-06-10` |  90 files changed, 7249 insertions(+) |
| pt | `feat/capture-codify-pr-template` |  9 files changed, 1508 insertions(+) |
| pt | `feat/conv-tree-accordion-panels-2026-05-27` |  15 files changed, 6702 insertions(+) |
| pt | `feat/conv-tree-auto-emit-enforcement-2026-05-23` |  10 files changed, 5347 insertions(+) |
| pt | `feat/conv-tree-ui-vertical-redesign-2026-05-23` |  10 files changed, 5152 insertions(+) |
| pt | `feat/customer-facing-review-gate-2026-06-01` |  8 files changed, 1509 insertions(+) |
| pt | `feat/decision-context-gate-2026-05-29` |  2 files changed, 31 insertions(+), 1 deletion(-) |
| pt | `feat/decision-queue` |  15 files changed, 5108 insertions(+) |
| pt | `feat/deterministic-workstreams-turn-emit` |  4 files changed, 2323 insertions(+) |
| pt | `feat/docs-refresh-tech-team-architecture` |  6 files changed, 984 insertions(+) |
| pt | `feat/drift-backlog-and-harness-evaluator` |  14 files changed, 5211 insertions(+) |
| pt | `feat/event-driven-heartbeat` |  8 files changed, 1432 insertions(+), 44 deletions(-) |
| pt | `feat/f7-doc-gate-warn-mode-2026-05-30` |  2 files changed, 804 insertions(+) |
| pt | `feat/harness-principles-doc-and-gate` |  8 files changed, 2097 insertions(+) |
| pt | `feat/incentive-audit-fixes-2026-05-28` |  5 files changed, 177 insertions(+) |
| pt | `feat/orchestrator-prime-finish` |  1 file changed, 12 insertions(+), 6 deletions(-) |
| pt | `feat/orchestrator-prime` |  9 files changed, 512 insertions(+) |
| pt | `feat/pr-health-snapshot-gate-2026-06-01` |  7 files changed, 1392 insertions(+) |
| pt | `feat/sweep-squash-merge-visibility` |  3 files changed, 577 insertions(+), 37 deletions(-) |
| pt | `feat/worktree-spawn-primitive-v2` |  2 files changed, 743 insertions(+) |
| pt | `findings-019-wig-scope-touch` |  5 files changed, 147 insertions(+) |
| pt | `fix/conv-tree-toast-stacking-2026-05-23` |  7 files changed, 4734 insertions(+) |
| pt | `fix/hooks-selftest-allowlist-decision-context-gate-2026-06-01` |  2 files changed, 33 insertions(+) |
| pt | `fix/pr-template-inline-gate-2026-05-24` |  19 files changed, 5571 insertions(+) |
| pt | `fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24` |  10 files changed, 4308 insertions(+) |
| pt | `fix/workstreams-ui-reflect-real-status` |  3 files changed, 493 insertions(+) |
| pt | `harness/active-sessions/BOOK-JDM547N8BO` |  1 file changed, 8 insertions(+) |
| pt | `harness/active-sessions/Misha-Laptop` |  1 file changed, 9 insertions(+) |
| pt | `harness/active-sessions/Mishas-Mac-mini.local` |  1 file changed, 9 insertions(+) |
| pt | `harness/active-sessions/Office_PC` |  1 file changed, 9 insertions(+) |
| pt | `salvage/main-checkout-triage-2026-06-09` |  65 files changed, 58805 insertions(+), 47 deletions(-) |
| pt | `salvage/pre-push-pii-patterns-20260702` |  3 files changed, 263 insertions(+), 1 deletion(-) |
| pt | `session/conv-tree-project-root-topology` |  6 files changed, 1880 insertions(+) |
| pt | `strategy/test-design-2026-05-23` |  6 files changed, 4121 insertions(+) |
| pt | `wip/evidence-bar-enforcement-gates` |  4 files changed, 41 insertions(+) |
| pt | `wip/preserve-nl-main-20260614` |  60 files changed, 69087 insertions(+), 45 deletions(-) |
| pt | `wip/supervisor-tick-snapshot-2026-07-22` |  1 file changed, 5 insertions(+) |
| pt | `worker-E.2` |  11 files changed, 1575 insertions(+), 2 deletions(-) |
| pt | `worker-e8-nlissue-fix` |  1 file changed, 32 insertions(+) |
| pt | `worker-gap-40-pr-template-inline-gate` |  14 files changed, 5211 insertions(+) |
| pt | `worker-workstreams-completed-filter-fix` |  2 files changed, 683 insertions(+) |
| pt | `worktree-agent-a341c8690244590d4` |  6 files changed, 4121 insertions(+) |
| pt | `worktree-agent-a58f66cfcd15bc33e` |  3 files changed, 102 insertions(+) |
| pt | `ws-ui-server-stable` |  1 file changed, 55 insertions(+), 15 deletions(-) |
