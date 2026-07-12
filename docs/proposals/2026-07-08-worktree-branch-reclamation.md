# Proposal: post-merge reclamation for worktrees and branches — the missing GC half

Status: PROPOSED (filed from the 2026-07-08 <product> cleanup-audit session, `brave-babbage-5abb42`;
left uncommitted here because the neural-lace checkout had another session's work in flight)
nl-issue: filed 2026-07-08 pointing at this file.
Author-session evidence: `<author-session-temp>\scratchpad\` — the brave-babbage-5abb42 session's Temp dir (branch-pr-join.json, cleanup-log.txt, salvage/)

## What prompted this (measured, 2026-07-08, <product> repo)

A machine-wide sweep found the <product> repo carrying:

- **64 registered git worktrees**: 54 leftover agent/workflow isolation worktrees under
  `<repo>/.claude/worktrees/` (`agent-*`, `wf_*`), 4 CCD app-session worktrees under
  `~/claude-projects/<product>/`, 2 in a DEAD session's Temp scratchpad
  (`.../hopeful-proskuriakova-852f57/.../scratchpad/{master-wt,rule-wt}`), 1 at drive root
  (`C:/wt-alerts`), plus the main checkout and 3 live-session worktrees.
- **~155 local branches**: 83 with squash-MERGED PRs (#737–#838), 1 with a CLOSED PR,
  ~55 `worktree-agent-*`/`worktree-wf_*` base-snapshot branches (ahead:0), and a handful of
  genuinely-unique stragglers.
- **18 dead `<product>-*` clone/copy directories** under `~/claude-projects/work-org/`
  (pre-worktree-era workflows; several are node_modules-only shells, some ~GB scale).
- The **main checkout parked on a stale merged feature branch** (`fix/deploy-gate-determinism-20260708`,
  merged as #834) instead of master.

All but ~8 branches were **verifiably reclaimable** (PR merged; no commits after `mergedAt`;
content confirmed on `origin/master`, several at hunk level). Only 4 worktrees held uncommitted
work; 3 of the 4 were parallel/predecessor drafts of work that later shipped via other PRs.

## Root causes — why NOTHING cleaned these up automatically

1. **A reclaim-side mechanism has never existed.** The worktree-isolation design (ADR 057,
   `adapters/claude-code/rules/worktree-isolation.md`) is deliberately preserve-first: the Stop-side
   `worktree-teardown-gate.sh` blocked ending with UNCOMMITTED work and explicitly never steered
   toward deletion. It never reclaimed merged leftovers — and ADR 058 D5 then retired it to an
   exit-0 shim, folding the uncommitted-work check into `work-integrity-gate.sh` (still
   preserve-only). The harness has strong "don't lose work" mechanisms and **zero
   "reclaim finished work" mechanisms**.
2. **`isolation: "worktree"` auto-clean only removes UNCHANGED worktrees.** Every agent/workflow
   builder that commits anything leaves its worktree + a pinning branch behind forever (54 found).
   The orchestrator-pattern's cherry-pick-then-teardown step is a Pattern (self-applied), not a
   Mechanism — sessions skip it under token/time pressure, and nothing notices.
3. **Squash-merge blindness.** GitHub squash-merges mean branch tips are never ancestors of master,
   so `git branch --merged` finds nothing. The two reliable signals — upstream `[gone]` after
   `git fetch --prune`, and PR state MERGED via `gh` — are consumed by no tool on this machine.
4. **A branch checked out in ANY worktree cannot be deleted** (`git branch -D` refuses), so leftover
   worktrees transitively pin branches: worktree-pileup causes branch-pileup.
5. **CCD app-session worktrees persist until the session is archived**, and auto-archive-on-PR-close
   was deliberately disabled 2026-07-01 (it archived ACTIVE sessions that merged PRs mid-work);
   `archive_session` is unavailable in unsupervised mode. So session worktrees linger by design,
   with no downstream sweeper.
6. **Ad-hoc checkouts have no registry or TTL.** Scratchpad worktrees outlive their session's Temp
   dir purpose; nothing inventories `C:/wt-alerts`-style one-offs or the dead clone directories.
7. **Post-merge main-checkout sync (git-discipline Rule 2) is a Pattern, not a Mechanism** — the
   main checkout stays parked on merged branches indefinitely.

## Proposal (classification: Mechanism; per ADR 058 D7 gate rules)

**`repo-gc.sh`** — a per-repo reclaimer, run weekly (cron/triage digest) and on demand:

1. **Inventory**: `git fetch --prune`; for every local branch — upstream state, PR state
   (ONE batched `gh pr list --state all --json number,state,headRefName,mergedAt` call, joined
   locally — not per-branch calls), which worktree pins it, dirty status.
2. **Classify**:
   - `RECLAIM`: PR MERGED + worktree clean + **zero commits after mergedAt**
     (`git log --after=<mergedAt> origin/master..<branch>` empty) + not a live session's cwd.
   - `HOLD`: dirty worktree, unmerged unique commits, open PR, live-session cwd, `git worktree lock`ed.
   - `REPORT`: everything ambiguous (closed-unmerged PRs, no-PR branches with unique commits).
3. **Act** (RECLAIM only): `git worktree remove` (NEVER `--force`), `git branch -D`,
   `git worktree prune`; append one ledger line per action (branch, tip SHA, PR#, worktree path)
   so anything reclaimed is re-creatable from the SHA.
4. **Safety invariants**: never `--force`; never touch a live session's worktree (consult the CCD
   session inventory where available, else mtime + lock heuristics); dirty worktrees get a salvage
   diff written to a salvage dir and are ONLY reported, never removed.
5. **Surface**: one SessionStart digest line — "repo-gc: N branches / M worktrees reclaimable →
   run repo-gc.sh" — consistent with the D6 single-digest rule.
6. **Companion fix**: promote the orchestrator teardown step to a Mechanism — worktree-creating
   agent/workflow calls append to a manifest; the reaper treats manifest entries whose branch
   merged as RECLAIM candidates even when the generic classifier would be unsure.

- **Golden scenario** (required by D7): squash-merged branch + gone upstream + clean pinning
  worktree → reclaimed with ledger line; same setup with one uncommitted file → HOLD + salvage diff.
- **Expected false-positive rate**: ~0 for RECLAIM (three independent conditions must all pass);
  the failure mode to watch is false-HOLD (over-conservatism), which costs only disk.
- **Retirement condition**: if worktree-creating flows ever gain reliable self-teardown (manifest
  reaper at 100% for 60 days), the weekly GC demotes to monthly or retires.

## Measured payoff on 2026-07-08

The manual equivalent of this mechanism (executed in the authoring session): ~60 worktrees and
~140 branches verified and reclaimed, several GB of dead checkouts identified, 4 uncommitted-work
worktrees salvage-diffed — roughly 3 hours of agent time that a 2-minute weekly script would have
prevented from accumulating.
