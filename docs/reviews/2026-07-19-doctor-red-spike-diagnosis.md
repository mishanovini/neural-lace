# Doctor red-spike diagnosis — 2026-07-19 (Fable research agent, read-only)

Repo doctor: FAILED — 164 red / 31 warn / 33 checks (~9.5 min). Live doctor (cache
2026-07-19T18:38Z): 164/1/32 — same headline by coincidence, different mix (live is stale:
still REDs orphaned worktrees, lacks ab1a7ed WARN demotion, misses evidence-bar rows).
Full run output: docs/reviews/2026-07-19-doctor-quick-full-output.md (197 lines).

## Clusters
| Cluster | Count | Root cause | Class |
|---|---|---|---|
| budget-worktrees-branches | 127 RED | 83 worktrees (budget ≤6) + ~90 orphan branches, Jul 6-12 dispatches; sweeper report-only | stale-state |
| new-gate-evidence-bar | 31 RED | live manifest.json stale (45 added_after in repo vs 4 live); Jul 16/17 backfill never deployed | drift ← deploy blockage |
| orphaned-worktree-work | 30 WARN | 30 worktrees hold UNINTEGRATED commits (20×1, 5×2, 1 dirty×3) — salvage before purge | salvage risk |
| manifest-freshness | 1 RED | auto-install never syncs manifest.json; install.sh hard-blocks | mechanism gap |
| obs-scheduled-tasks | 1 RED | NL-session-resumer Disabled = DELIBERATE (ADR 061) — check contradicts standing ADR | doctor false-fire |
| obs-cockpit-fresh | 1 RED | GENUINE: /api/diagnostics/drift ledger_open=1 vs rendered=0, id NY-1783427528-ea50 invisible on landing | defect |
| obs-ask-capture | 1 RED | 9/11 trailing-24h sessions no ask captured — splice not firing OR reboot-era FP | HYPOTHESIZED |
| budget-chains | 1 RED | live Stop chain 9 vs template 5 (≤6) — live-only accretion | drift |
| budget-active-plans | 1 RED | 4 ACTIVE plans vs 3 budget | workflow |

## Deploy leg: STALLED (PROVEN)
auto-install fires (2 runs today, 309 files synced) but WITHHOLDS 9 files — "REVIEW-GATE SKIP:
no PASS harness-change-review record covers blob_sha": hooks/harness-doctor.sh,
hooks/lib/merge-scan-lib.sh, hooks/plan-lifecycle.sh, hooks/plan-reviewer.sh,
hooks/session-start-digest.sh, scripts/coord-push.sh, scripts/coord-sync.sh,
scripts/manifest-check.sh, scripts/worktree-hygiene-sweep.sh. Their commits (973eb5b,
ab1a7ed, 1ee6487, 23cd526, 26106f4, 14568b2, 1b708c0 — Jul 16-17) landed on master WITHOUT
records in docs/reviews/records/index.json (12 entries; last = 5512926 gate23 trio).
install.sh hard-blocks the same files. The cure for the biggest red cluster (fixed sweeper +
doctor) is merged but undeployable.

## Cascade: observability blind ~2.5 days (PROVEN)
health-tick doctor-cache-refresh rc=124 every tick since Jul 17 (202 timeouts; last success
2026-07-16T23:34Z at 260s; 300s budget) — 83-worktree iteration pushed doctor past budget.
Each timeout starves scheduled-task-health + heartbeat-reap.

## History
Jul 10: 3 red/26 checks → Jul 12: 10 → Jul 15: 48/28 → Jul 16: 133/32 → Jul 19: 164/32.
Jumps track NEW checks landing; the 133→164 delta = aging stale rows crossing the 7d budget
(HYPOTHESIZED decomposition — per-cluster history not retained). No new failure kind this week.

## Fix plan (executing 2026-07-19)
1. harness-reviewer round on the 9 withheld blobs → register PASS records (5512926 precedent)
   → run install.sh. Unblocks deploy leg; −32 reds; deploys fixed sweeper/doctor.
2. Salvage-first worktree/branch sweep: classify 30 unintegrated-commit worktrees
   (already-on-master via patch-id / real orphan work / junk), salvage real work, purge pile.
   −127 reds; doctor runtime back under health-tick budget (revives cache refresh,
   heartbeat-reap, scheduled-task-health).
3. nl-issues filed: ADR-061-contradicting doctor check; cockpit NY-drift landing miss;
   health-tick doctor budget breach; (existing) ask-capture genuineness needs one live probe.
