# Worktree/Branch Salvage Classification — Full Detail (2026-07-19)

Read-only sweep. All ahead/equiv/real counts computed via `git rev-list --count master..<ref>`
and `git cherry master <ref>` run directly against the repo at
`C:/Users/misha/dev/Pocket Technician/neural-lace` on 2026-07-19 ~12:16 PDT.
equiv = cherry `-` (patch-equivalent, already on master under a different SHA).
real = cherry `+` (genuinely NOT on master — true unintegrated content).

Raw data files (all in this scratchpad dir):
- worktree_list.txt — `git worktree list --porcelain` raw dump (83 worktrees incl. main)
- branches.txt — `git for-each-ref refs/heads` (210 local branches, upstream, last commit date)
- branch_analysis.tsv — per-branch ahead/equiv/real
- worktree_status.tsv — per-worktree dirty status + mtime
- joined.tsv — worktree path x branch x ahead/equiv/real x dirty x mtime (the master join)
- stale_branches_no_worktree.tsv — the ~91 no-upstream branches with no worktree
- orphan_detail.txt — commit subjects + diffstat for every branch/worktree carrying real content

## WORKTREES (82 non-main, from git worktree list --porcelain)

### EMPTY (ahead=0, clean tree) — 7 — safe to purge
| Worktree path | Branch | ahead |
|---|---|---|
| AppData/.../sweet-hamilton-c9a5b6/.../scratchpad/baseline-70f7133 | DETACHED @70f7133 | 0 |
| .claude/worktrees/agent-a436ce808ba48954f | build/gh-account-autoswitch | 0 |
| .claude/worktrees/agent-a7dbccd5d7525510f | build/backlog-build-escalation | 0 |
| .claude/worktrees/agent-acb45c9d1e98035d0 | build/cold-reader-lint | 0 |
| .claude/worktrees/backlog-loop-01 | build/backlog-loop-01 | 0 |
| .claude/worktrees/build-wave-o-o3 | build/wave-o-o3 | 0 |
| .claude/worktrees/build-wave-o-o6 | build/wave-o-o6 | 0 |

### INTEGRATED (ahead>0, all commits cherry-equivalent on master, clean tree) — 36 — safe to purge
agent-a0d09130ef7cab993, agent-a0d1c3859853b5d0f, agent-a10a3498d83c676bf, agent-a1746d56c7adc1130,
agent-a196eb301b8499f54, agent-a1b98c323fce694b8 (build/askp1-t8), agent-a3a48bafcbf7282ef (build/askp1-t14),
agent-a4c625558c427fb05 (build/askp1-t13), agent-a4fa9fcbf4a12dce0 (build/askp1-t4), agent-a515ac5b3f57b54fc,
agent-a51b5bb6069798b61 (build/cockpit-health-doctor), agent-a54f105863f16e7bd (build/askp1-t7),
agent-a56c2bf4aa5c49122, agent-a604946612410a415 (build/askp1-t3), agent-a6742c22d76bfb224,
agent-a67cc3af91e88e7fc, agent-a75b4ed5bbc2705ca (build/askp1-t10), agent-a7967d2e8799a07e8,
agent-a7cf30a69c23e597c (build/askp1-t5), agent-a7ed50f23b8dde9e9 (build/askp1-t6),
agent-a7fc0ab0ce99b63eb (amend/ask-p1-r2), agent-a8308194dd3fbbd9f (build/askp1-t11),
agent-a87a7cb5a461f2b11, agent-a920e64413ed14ed5 (amend/ask-p1), agent-a9c98ebee3eb4f80f (build/cockpit-health-ui),
agent-aa0b7e8db956f2a1c (build/askp1-t1), agent-ab99a0dd48022da4b, agent-ac57b5161c88bb13f (build/askp1-t2),
agent-ad08d3252b95071cf, agent-ad5e3ba46bd6a3b3f, agent-adb99ca9ecb607fcf, agent-aeb2a3faf71c9fe6f (build/askp1-t9),
agent-af06865a2d7af1112, agent-af19589d4233ff605 (EXCLUDED — recent review agent, see below),
agent-af89de92d44275474, agent-afbe486df9899cc03, angry-hypatia-45f5b0 (DETACHED @d9f95c87)

### ORPHAN-WORK (real unintegrated commits, clean tree) — 28
See main report table. Path→branch→commit subjects in orphan_detail.txt.

### DIRTY (uncommitted changes) — 5
agent-adb7aab5b7756bd4c, agent-adf0ab260b6e3056b, ec-review-wt (DETACHED, 1006 deletions not committed),
jovial-ishizaka-9a2574 (claude/distracted-haslett-05e4f8), modest-satoshi-150d97 (claude/goofy-faraday-5177b0)

### EXCLUDED from purge per task instruction (in use) — 6
agent-aa73f80c1e76035e8 (build/roadmap-t3, locked), agent-ae54bfb2272bba2c8 (build/roadmap-t1),
agent-ae89fc2e0cc6ea6b4 (build/roadmap-t2, locked), agent-aebd93f4eb7f331e4 (build/roadmap-t7, locked),
agent-af19589d4233ff605 (recent review agent), sweet-hamilton-c9a5b6 (build/cockpit-health-int)
— all 6 confirmed dirty and/or actively mtime'd (4 of them mtime'd within the last 6h: roadmap-t1/t2/t3/t7).
agent-a53db5b527041f6cc named in the task's exclusion list does NOT currently exist as a worktree or branch — moot, nothing to exclude.

## STALE LOCAL BRANCHES, NO WORKTREE, NO UPSTREAM (91 total)

### EMPTY (ahead=0) — 82 — safe to delete
10 named: build/askp1-t2b, build/cockpit-sessionstart-r2, build/wave-o-hb-perf2, build/wave-o-o5,
claude/compassionate-bouman-5dcabe, claude/nl-observability-handoff-b0d989, claude/relaxed-almeida-f07dc9,
claude/sweet-hamilton-c9a5b6, fix/f5-waiver-parity-gap-hooks, tmp/o4-flip
+ 72 `worktree-agent-*` / `worktree-wf_*` leftover-default-name branches (full list in
stale_branches_no_worktree.tsv rows 20-91) — every one verified ahead=0 individually.

### ORPHAN-WORK (branch-only, no worktree) — 9
See main report table.

## Full per-item raw data
See joined.tsv (worktrees) and stale_branches_no_worktree.tsv (branches) for the complete
ahead/equiv/real/dirty/mtime numbers behind every classification above.
