# 064 — Never-diverge: single canonical master + write-discipline gate + FF-only convergence

**Date:** 2026-07-15
**Status:** DECIDED (decide-and-go per constitution §8; pending architecture-reviewer design pass before build — R3 of `docs/plans/harness-governance-batch-2026-07-15.md`)
**Tier:** 2 (reversible — every element is a config flip or gate removal; no history rewrite, no data surgery)
**Backlog anchor:** PT-FORK-SYNC-NOT-RUNNING-01 (marked RESOLVED 2026-07-13 by shipping `master-drift-autocorrect.sh`; the class RECURRED 2026-07-15 as a 14/10 divergence — that resolution was partial: it FF-syncs a strictly-behind side but by design refuses true divergence)

## Problem (cold-read context)

The neural-lace repo is dual-hosted: the personal-account remote `origin` (github.com) and
the work-org remote `pt` (SSH host alias `github-pt`). Both masters accept independent
writes today. Local commits are safe — the `post-commit` hook (`sync.sh`) dual-pushes every
local commit to both remotes with tree-hash verification. The uncovered writer is **GitHub
server-side PR merges**: a PR merged on one repo's web UI/`gh pr merge` lands on that master
only; no local hook can observe it. When both repos take server-side merges between
reconciles, the masters truly diverge (unpaired commits on both sides), and the only
automatic mechanism — `master-drift-autocorrect.sh` (SessionStart, FF-only) — correctly
refuses to touch true divergence. Result: recurring manual Tier-3 reconciles (2026-06-01
~10/10 split; 2026-07-15 14/10 split, reconciled as merge `937e8cb`).

Diagnosis (explorer agent, 2026-07-15, this plan's Evidence Log): divergence is a
**multi-master replication problem**. With two independently writable masters and async
mirroring, a divergence window always exists regardless of sync frequency. Structural
impossibility requires a single-writer topology; then every sync is a fast-forward, which
is always safe to automate. Also found: `sync-pt-to-personal.sh` (the intended bridge) is
wired to NOTHING (no hook, no schedule, no manifest entry) and carries a latent push-URL
discovery bug that `master-drift-autocorrect.sh` explicitly diverged from (its comment at
scripts/master-drift-autocorrect.sh:174-189 documents the silent no-op failure mode).

## Options considered

| Option | What happens | Cost / risk |
|---|---|---|
| A. Single canonical master (personal `origin`) + gate PR-merges to canonical only + keep FF-only autocorrect | PR merges allowed only on the personal repo; pt becomes a mirror kept in step by the existing dual-push + FF autocorrect; a PreToolUse gate blocks `gh pr merge` targeting the pt repo; true divergence becomes structurally impossible (single writer) | Gate false-positive risk on legitimate pt-repo PRs (none should exist post-cutover); external/server-side writes to pt (collaborator, other un-harnessed machine) still possible until operator adds branch protection (surfaced as optional hardening, operator-only) |
| B. Robust bidirectional sync (wire `sync-pt-to-personal.sh` on a schedule; auto-merge divergence) | A cron/scheduled task cherry-picks or merges across | Does NOT make divergence impossible (window persists); auto-merging diverged masters is exactly the Tier-3 action the operator reserved for humans; keeps two writable masters (the root cause) |
| C. Retire one remote entirely | One repo only | Loses the work-org/personal split the operator deliberately runs (business intent — not mine to remove) |

## Decision

**Option A.** Concretely:

1. **Canonical = personal `origin` master.** Rationale: the live deploy path
   (`session-start-auto-install.sh`) already reads `origin/master` ONLY — choosing origin
   as canonical means zero change to the deploy path and zero added deploy lag. (PT-canonical
   would put every harness deploy behind a mirror hop.)
2. **Write-discipline gate (the Mechanism):** a PreToolUse gate on `gh pr merge` /
   `gh api .../merge` that blocks merging PRs on the NON-canonical work-org repo
   (resolved from the `pt` remote's URL at runtime — never hardcoded), with a block
   message teaching the canonical flow
   (retarget the PR to the personal repo, or push the branch and open it there). Deployed
   estate-wide via the normal install path, it covers every harnessed machine — including
   the other machine that merged PT-side PRs (the actual source of this divergence).
   §10 evidence bar: golden scenario = PR #100 merged PT-side 2026-07-13 → 14-commit
   divergence 2026-07-15; fp_expectation = zero legitimate PT-repo `gh pr merge` calls
   post-cutover (any PT-side PR is itself the defect); retirement = pt repo archived or
   operator enables server-side branch protection making the gate redundant.
3. **Convergence stays FF-only** (`master-drift-autocorrect.sh` unchanged in semantics):
   with a single writer, mirror-behind is the only reachable drift state, and it self-heals
   at SessionStart. Divergence-refusal remains as the tripwire for out-of-model writes
   (fails loudly to NEEDS-YOU/status instead of silently merging).
4. **Retire `sync-pt-to-personal.sh` to `attic/`** (it is unwired, bug-carrying, and its
   remaining "manual recovery" role is superseded by the runbook
   `docs/runbooks/master-reconcile-and-estate-cleanup.md`); update the
   `cross-repo-drift-postpush-gate.sh` block message that references it to point at the
   runbook instead. (Chesterton check done: its only live reference is that block message.)
5. **Operator-optional hardening (surfaced, not blocking, NOT agent-executable):** enable
   GitHub branch protection on pt/master restricting direct pushes/merges (access-control
   change = operator-only by policy). Until then the gate covers all harnessed machines,
   which the evidence says is where every historical divergence originated.

## Why this is mine to decide (and what would reverse it)

Reversible: the gate is one manifest entry + one hook file (removable in one commit);
canonical choice is a config constant; the attic move is a `git mv`. No third parties, no
data surgery, no unrecoverable spend. Reversal trigger: operator states a business need for
PT-side PR merges (then the gate flips its canonical constant or gains an allowlist, and
the mirror direction reverses — the design is symmetric in which side is canonical).

## Consequences

- The two masters can no longer truly diverge from any harnessed machine; the manual
  reconcile runbook becomes a recovery tool for external-writer incidents only.
- PT-side PRs in flight at cutover must be merged canonical-side (one-time migration note
  in the gate's block message).
- `check_model_pins`/doctor unaffected. New doctor check candidate (builder scope): assert
  the post-commit dual-push hook is installed (`core.hooksPath` → `git-hooks/`) so the
  mirror-by-write path can't silently vanish.
