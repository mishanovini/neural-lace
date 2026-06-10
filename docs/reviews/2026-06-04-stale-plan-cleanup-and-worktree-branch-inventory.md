# Stale ACTIVE-plan cleanup + worktree/branch inventory — 2026-06-04

Owner: Misha
Author: nl-cleanup session (dispatched by orchestrator-prime)

## Why this exists

Dispatch (a sandbox-blind orchestrator that does NOT load the harness) left 23 plans at
`Status: ACTIVE` in `docs/plans/` with no commits in >24h. Because Dispatch never runs
`task-verifier`, it ships work and commits it but never flips checkboxes or `Status:` —
so checkbox/Status state was ~0% reliable as a completion signal. **Git was the source of
truth** for every verdict below.

This pass triaged all 23 (excluding `orchestrator-prime`, kept ACTIVE as the live
orchestrator) and inventoried the repo's worktrees + unmerged branches.

## Plan triage results

**17 → COMPLETED** (deliverables verifiably present on master HEAD; never flipped only
because Dispatch skipped task-verifier):

| plan | key evidence |
|---|---|
| ci-eats-own-cooking-2026-05-23 | `.github/workflows/evals.yml` + `hooks-selftest.yml` on HEAD, in continuous use |
| conv-tree-auto-emit-enforcement-2026-05-23 | reconciler hook + Layer-D rule, PR #33 (932e3be) |
| conv-tree-project-root-topology | migrate-topology + backfill + emit path-fallback, PR #20 (4e64e6e) |
| conv-tree-ui-v1.1.2-polish (items 25–28) | item-backlogged event + reducer, PR #12 (0094c0b) — **renamed** to resolve filename collision (see below) |
| conv-tree-ui-v2-vertical-redesign-2026-05-23 | backlog-context-set event + v2 layout, PR #32 (b93fdaf) |
| d8-d9-d10-principles-wiring-2026-05-28 | CLAUDE.md wiring + install sync + gate R3, PR #41 (7dc019f) |
| decision-queue | ADR 043 + schema + decision-queue.sh + bridge, e004396 (Task 6 activation deferred-by-design) |
| docs-recovery-2026-05-29 | 2 recovered docs present + 1 stale review dropped, PR #42 |
| harness-drift-detection | check-cross-repo-drift.sh + cross-repo-drift-warn.sh + sync.sh verify, 5b60c97/3b19478/b0461ec |
| harness-gate-fixes-2026-06-03 | T1 eef40b9, T2 4031d6a, T3 6b79adb, T4 skills-sync — all 4 fixes on HEAD |
| harness-principles-doc-and-gate | rules/principles.md + principles-compliance-gate.sh wired, PR #23 (6924d2b) |
| incentive-audit-fixes-2026-05-28 | stale-active-plan-surfacer + measure-claim-rate + harness-evaluator-daily, PR #40 (Fix #2 HMAC Misha-deferred) |
| misha-decision-batch-handoff-2026-05-20 | in-repo discovery e4a2f1d + off-repo handoff doc both present |
| pr-template-inline-gate-2026-05-24 | pr-template-inline-gate.sh wired + FM-030 + arch row, eda6f2b/#35 |
| repo-cleanup-dispatch-worktree-gitlinks-2026-05-22 | gitlinks-in-index = 0 + .gitignore guard + parser fix bf89a75 |
| revert-mirror-action-workflow | mirror-to-sister.yml GONE + ADR-044 marked Reverted (the absence is the success) |
| rules-index-and-diagnostic-evidence-template-2026-05-23 | rules/INDEX.md + golden test + PR-template evidence section |

**4 → DEFERRED** (design phase shipped 8–9d ago; implementation roadmap entirely unbuilt
with no activity while live work moved to orchestrator-prime/cross-machine; reversible,
each carries a RE-ENGAGE TRIGGER in its header comment):

| plan | state | re-engage note |
|---|---|---|
| doctrine-scoping-rules-authoring | design shipped PR #7; R1–R5 unbuilt | reserved ADR 044 collided — re-reserve before R1 |
| file-lifecycle-redesign | design shipped PR #15 (ADR 037+038); R3/R5 absent, R1/R4 landed piecemeal | reconcile piecemeal landings on resume |
| principles-doctrine-authoring | design shipped PR #7; R1–R7 unbuilt | ADR 043 collided + principles.md name overlaps shipped consolidation doc — resolve §D1 first |
| session-resilience-redesign | design shipped PR #12 (ADR 040); R1–R7 all absent | resume when scheduled |

**0 → ABANDONED.**

**3 kept ACTIVE** (genuinely in-flight):

| plan | last commit | why kept |
|---|---|---|
| orchestrator-prime | 2d ago | the live always-on orchestrator — explicitly out of scope for closure |
| cross-machine-workstreams-coordination-2026-06-04 | 24 min ago | created today; another machine (BOOK-JDM547N8BO) actively on `feat/component-c-cross-machine-sync`; coord-push/pull/overlap + ADR-051 still unshipped |
| plan-lifecycle-redesign | 26h ago | real in-flight commit (in-flight scope update); serves as a live scope umbrella; freshest of the design plans |

### Filename-collision note (conv-tree-ui-v1.1.2-polish)
The ACTIVE `conv-tree-ui-v1.1.2-polish.md` was a DIFFERENT round ("items 25–28") than the
already-archived COMPLETED `docs/plans/archive/conv-tree-ui-v1.1.2-polish.md` ("item 20/25").
To avoid `plan-lifecycle.sh` `git mv`-ing into an occupied path, the active round was renamed
`→ conv-tree-ui-v1.1.2-polish-items-25-28.md` (+ its `-evidence.md` companion) before flipping
to COMPLETED. Both rounds now coexist in `docs/plans/archive/` with distinct names.

### Stray pre-archive copies removed
Dispatch had left 10 untracked `docs/plans/archive/*.md` pre-archive snapshots (divergent,
not in git). 9 that collided with plans completed here were removed (authoritative versions
are the tracked actives, archived properly via the Status flip). `cross-machine-context-handoff-2026-05-24.md`
remains untracked in archive/ — not in this triage set; left for separate handling.

---

## Worktree / branch inventory (SURFACE-FOR-DECISION — no deletions performed)

> Deletion is the hard-to-reverse step. This is surfaced for Misha's decision; nothing was
> pruned, removed, or force-changed.

### Tracked gitlinks (mode 160000)
**COUNT: 0** — the ~30-gitlink problem from `repo-cleanup-dispatch-worktree-gitlinks` is
already resolved (swept fff2de3, 2026-05-22) and `.gitignore` carries the recurrence guard
(`/[a-z]*-[6hex]/`, HARNESS-GAP-41). No action needed.

### Worktrees (16 registered)
- **2 live-locked (DO NOT TOUCH):** `.claude/worktrees/agent-a8eae9d74f4bf7812`,
  `.claude/worktrees/agent-aad8efc5a8438767b` — locked to running pid 21428.
- **9 Dispatch sibling-worktrees** (`<adjective>-<surname>-<6hex>`): charming-wescoff-358c9f,
  infallible-heisenberg-9c2e06, intelligent-chebyshev-d4e10c, jolly-davinci-d99487,
  kind-faraday-c5fe05, stoic-gates-feefd3, vibrant-fermi-acf761, vigorous-bartik-154b8b,
  xenodochial-mendeleev-8b3c88. Five share HEAD 6570d6a (orphaned/duplicate spawns). These
  are the class `.gitignore` line 145 guards against → candidates for `git worktree remove`.
- **3 named feature worktrees:** customer-facing-review-gate-2026-06-01 (behind master 88),
  decision-context-gate-2026-05-29 (remote gone → likely merged), youthful-banach-7e2b40
  (conv-tree-ui-v1.1.1-polish, likely merged). Two have `gone` remotes → worktree never removed.

### Unmerged remote branches (46 total: 13 origin + 33 pt)
Heavy origin↔pt fork-pair mirroring; ~12 are byte-identical twins. After collapsing dups +
excluding 2 live heartbeat branches + 1 backup + 3 recent in-flight features, **~25 distinct
stranded work-streams** warrant a decision. Classes:
- **Live — exclude from any cleanup:** `pt/harness/active-sessions/BOOK-JDM547N8BO` (2h),
  `pt/harness/active-sessions/Office_PC` (49min) — cross-machine heartbeat branches.
- **Recent in-flight (keep):** `pt/feat/orchestrator-prime` (2d), `pt/feat/pr-health-snapshot-gate-2026-06-01` (3d),
  `pt/feat/f7-doc-gate-warn-mode-2026-05-30` (4d).
- **Stranded real work (11-day cluster — decision needed):** conv-tree-UI redesign family
  (`pt/feat/conv-tree-accordion-panels`, `pt/feat/conv-tree-ui-vertical-redesign`,
  `pt/fix/conv-tree-toast-stacking`, `origin+pt/fix/conv-tree-project-node-header-styling`),
  `pt/feat/decision-queue`, `origin/feat/drift-backlog-and-harness-evaluator` (16 commits, 4001 ins),
  `origin/ci/eats-own-cooking`, `origin/ci/server-side-enforcement`, `pt/fix/pr-template-inline-gate` (17 commits),
  `pt/feat/harness-principles-doc-and-gate`, `pt/feat/incentive-audit-fixes`,
  `pt/session/conv-tree-project-root-topology`, `pt/docs/harness-gap-cloud-orchestrator-hook-detector`,
  `pt/fix/scope-enforcement-gate-trailing-slash-parser`, `pt/feat/worktree-spawn-primitive-v2`.
  Several correspond to plans just marked COMPLETED above — their content likely landed on
  master via a different SHA path (reconverge squash-merges) and the branches are now
  shippable-elsewhere; needs a `git diff origin/master...<branch>` content check per branch
  before deletion.
- **Backup snapshot:** `origin/backup/personal-master-pre-cutover-20260528-100528`.
- **Trivial / backlog-edit-only:** several `claude/*` branches (amazing-fermi, busy-hawking,
  condescending-bouman, clever-wu) — small/backlog edits, possibly already reconciled.

### Local stale branches
~50 local branches; ~14 `worker-*` track the now-gone `origin/feat/decision-context-gate-2026-05-29`
(leftover parallel-build workers, content presumably landed via the feature branch). Several
`claude/*` and `worktree-agent-*` have no upstream / gone remotes. Many match untracked
archived-plan files, indicating shipped-but-bookkeeping-lagged.

### Recommendation framing (for Misha — no action taken)
1. The 9 Dispatch sibling-worktrees (esp. the 5 sharing HEAD 6570d6a) + their backing
   `claude/*` branches are the cleanest deletion candidates once you confirm none hold unique work.
2. The ~11-day stranded pt-only feature branches: most correspond to now-COMPLETED plans —
   verify content reached master (`git diff origin/master...<branch>`) then delete; any with a
   non-empty unique diff = stranded-real-work to reconcile.
3. Exclude the 2 heartbeat branches and the 3 recent in-flight features from any sweep.
