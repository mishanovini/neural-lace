# harness-reviewer: health-tick step (d) worktree auto-prune — VERDICT: REJECT

Reviewed commit `bab00ab` (adapters/claude-code/scripts/health-tick.sh). Independent
classification: **Mechanism** (an automated actuator — so "false positive" means *wrongful
deletion*, not wrongful block). Agreed with the author's classification.

Persisted here because the P1+P2 review before it was left chat-only, and an unpersisted
review is an unenforceable one — the review-before-deploy gate can only read records on disk.

## The two Criticals

**C1 — self-armed destructive mechanism (PROVEN).** The commit hard-coded
`WORKTREE_SWEEP_APPROVE=1` into an unattended hourly task, converting a per-approval operator
channel into standing automated approval. Three written records set the opposite convention:
`manifest.json`'s perf-tick-snapshot entry ("an agent session cannot arm it merely by running
code"; worktree purges "operator-only"), ADR-061 §5 invariant 2 ("this ADR ships nothing
armed"), and `NEEDS-YOU.md`'s log of per-batch operator asks — including one where the
permission classifier DENIED an agent exactly this action.

**C2 — the wiring provably cannot fire (PROVEN by measurement).** `~/.claude/state/health-tick/tick.log`
shows real ticks spending 136–226s of the 300s budget on step (a) alone, which exits rc=1 every
tick; one tick hit rc=124 and skipped steps (b)/(c) entirely. A timed real sweep in the default
no-arg form was killed at 9m59s having classified ~40 of 127 worktrees of the FIRST repo —
extrapolated ≥30min machine-wide, with `prune_safe` running only after a repo's FULL
classification. Step (d) would be TERM-killed mid-classification every tick forever: it prunes
nothing (the exact §10 theater the commit invoked) while starving step (e), the perf-telemetry
P2 fallback behind it.

## Majors

- **Ignored files defeat the "carries nothing" predicate (PROVEN empirically).** A worktree
  holding only gitignored files reports `git status --porcelain` = 0 lines, and
  `git worktree remove` WITHOUT `--force` returns rc=0 and deletes them. `.env` copies,
  gitignored SCRATCHPAD.md, local DBs sit outside BOTH guards — so the step comment's claim
  that "git itself refuses as a second, independent guard" is false for this class.
- **SAFE-PRUNE consults no liveness signal at all,** and `R_AGE` is the *branch-tip commit
  date*, not worktree creation or last use. A worktree created an hour ago from a >7d-old tip
  is instantly eligible. The liveness join, SELF-exclusion and CONTINUING-grace machinery built
  for the *warning* class are all skipped for the class that actually deletes.
- **Write-only audit channels.** `worktree-sweep.log` and `tick.log` have ZERO readers
  (grep-proven across the adapter). A chronically-failing deleter would be indistinguishable
  from a working one on every surface the operator reads.
- **Capability drift without charter update.** The tick's own SAFETY CONTRACT header still
  claims it "only runs the three existing report/hygiene surfaces and writes files"; no
  manifest entry, no ADR-061 amendment.

## Minors
HARNESS_SELFTEST did not sandbox the destructive default; fail-open evidence collection in the
sweep (`2>/dev/null | grep -c` yields 0 on command failure, i.e. errors read as "clean"); the
commit message overstated the self-test hazard's blast radius ("the doctor and install.sh
invoke" — no such invocation exists).

## What the reviewer confirmed as sound
Self-test 25/0 reproduced independently. Scenario 8's assertions are non-vacuous
(precondition-proven fixture, negative cases, log and no-alert checks). The sweep's classifier
held up against real data: of ~40 rows classified live, one SAFE-PRUNE, every content-holder
and the one live locked agent correctly protected. Stale-`origin/master` and multi-commit
squash-merge cases both fail SAFE (over-retention). The gap being closed is real.

## Applied in response (commit follows this record)
- **C1 fixed:** step (d) now ships OBSERVE-FIRST — report mode by default, pruning ONLY when
  the operator has created `~/.claude/state/worktree-prune-armed` themselves. Mirrors the
  `PERF_TICK_REAP_ARMED` precedent on this same tick. Agent-written code cannot flip it.
- **C2 partly fixed:** the sweep is now scoped to a single repo instead of `discover_repos()`
  over all of `$HOME/claude-projects`. Measured: **1m04s**, down from ≥30min.
- **Minor F7 fixed:** HARNESS_SELFTEST now short-circuits the step to a no-op.

## Still OPEN — not fixed, do not treat as closed
1. Step (d) still runs BEFORE step (e); the starvation ordering fix is not applied.
2. Ignored-file probe not added to the auto-prune path.
3. Liveness join / creation-time age still not consulted by the deleting class.
4. Deletion log still has no reader; no batch cap; no K-consecutive-failure escalation.
5. SAFETY CONTRACT header, manifest entry and ADR-061 amendment not yet written.
6. Fail-open evidence collection in the sweep unchanged.

Re-review is required before the arming marker is ever created. The observe-first default is
what makes it safe to leave this on master in the meantime.
