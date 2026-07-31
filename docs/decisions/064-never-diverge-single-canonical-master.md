# 064 — Never-diverge: single canonical master + write-discipline gate + FF-only convergence

**Date:** 2026-07-15
**Status:** DECIDED, architecture-reviewed 2026-07-16: **SOUND-WITH-AMENDMENTS** — amendments A1–A6 folded in below (R3 of `docs/plans/harness-governance-batch-2026-07-15.md`). The review's ONE THING: the client gate alone does NOT deliver "structurally impossible" — server-side branch protection is the only layer covering every writer; it is hereby promoted to PRIMARY mechanism and the gate demoted to defense-in-depth.
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
2. **Write-discipline gate (DEFENSE-IN-DEPTH, not the guarantee — amended A1/A4):** a
   PreToolUse gate on `gh pr merge` / `gh api .../merge` that blocks merging PRs on the
   NON-canonical work-org repo, with a block message teaching the canonical flow
   (retarget the PR to the personal repo, or push the branch and open it there).
   **Target resolution (A4):** the gate resolves the merge TARGET the way gh does
   (explicit `--repo` flag, else the checkout's default repo), and blocks only when the
   resolved target equals the `pt` remote's repo (resolved from the remote URL at
   runtime — never hardcoded). On an ambiguous/unresolvable target it fails
   loud-and-asks, never silently allows. fp_expectation is defined against the resolved
   target, not the raw command string.
   **Honest coverage (A1):** this makes divergence impossible only *from a gate-synced
   harnessed machine performing the merge via the gh CLI*. **Residual writers the gate
   does NOT cover:** GitHub web-UI "Merge pull request"; a machine that hasn't yet synced
   the gate (deploy-lag window — auto-install syncs the hook only at a NEW session, so
   even the deploying machine's current session is unprotected until restart, the same
   class as the observed agents-registry snapshot lag); un-harnessed machines / external
   collaborators; CI/GitHub Actions; scheduled/cloud agents (Decision 011 — no
   PreToolUse); direct `git push pt master`. Only server-side branch protection closes
   these.
   **§10 evidence bar (A3):** merge path of PR #100 is UNKNOWN (server-side merges via
   web UI and gh CLI are indistinguishable in the API record) — so the 2026-07-15
   divergence golden scenario validates BRANCH PROTECTION, not this gate; the gate is
   labeled defense-in-depth accordingly and carries fp_expectation = zero legitimate
   pt-repo `gh pr merge` calls post-cutover; retirement = pt repo archived OR operator
   enables server-side branch protection (at which point the gate is a redundant
   teaching surface and may be retired or kept as UX).
3. **Convergence stays FF-only** (`master-drift-autocorrect.sh` unchanged in semantics):
   with a single writer, mirror-behind is the only reachable drift state, and it self-heals
   at SessionStart. Divergence-refusal remains as the tripwire for out-of-model writes
   (fails loudly to NEEDS-YOU/status instead of silently merging).
4. **Retire `sync-pt-to-personal.sh` to `attic/`** (it is unwired, bug-carrying, and its
   remaining "manual recovery" role is superseded by the runbook
   `docs/runbooks/master-reconcile-and-estate-cleanup.md`); update the
   `cross-repo-drift-postpush-gate.sh` block message that references it to point at the
   runbook instead. (Chesterton check done — reviewer independently re-verified: its only
   live reference is that block message; all other hits are comments/history. Its
   PT→personal cherry-pick direction encodes the OLD PT-canonical posture — directionally
   obsolete, a further retirement reason.) **Drift note (A6):** auto-install never deletes
   live files, so `~/.claude/scripts/sync-pt-to-personal.sh` lingers on every machine
   after the attic move — add it to install.sh's prune step, or accept as dead drift (its
   ISL guard + dedicated-clone + FF-only push make an accidental run near-harmless).
5. **PRIMARY STRUCTURAL MECHANISM (A2 — promoted from "optional"): GitHub branch
   protection / restricted-push on `pt/master`, enabled FIRST.** It is server-side,
   instant, machine-independent, and the ONLY layer that covers web-UI, CLI, CI, and
   collaborator writes uniformly — it does not wait for any harness deploy, closing the
   gate's rollout window. It is an access-control change and therefore OPERATOR-ONLY by
   policy (never agent-executed); it is surfaced as the batch's top NEEDS-YOU item. The
   PreToolUse gate (element 2) is defense-in-depth for the harnessed gh-CLI path and a
   teaching surface; it does not deliver the invariant on its own. Until branch
   protection is enabled, the invariant is NOT guaranteed — divergence remains possible
   via every residual writer listed in element 2, and the SessionStart detector + FF
   autocorrect + reconcile runbook remain the safety net.

## Why this is mine to decide (and what would reverse it)

Reversible: the gate is one manifest entry + one hook file (removable in one commit);
canonical choice is a config constant; the attic move is a `git mv`. No third parties, no
data surgery, no unrecoverable spend. Reversal trigger: operator states a business need for
PT-side PR merges (then the gate flips its canonical constant or gains an allowlist, and
the mirror direction reverses — the design is symmetric in which side is canonical).

## Consequences

- With branch protection enabled (primary), the two masters cannot truly diverge from ANY
  writer; with only the gate deployed (interim), divergence is prevented solely on the
  gate-synced harnessed gh-CLI path and the reconcile runbook remains the recovery tool.
- **Posture reversal acknowledged (A5):** this REVERSES the recorded 2026-05-29 "PT is
  canonical" posture (sync.sh:68-74 and sync-pt-to-personal.sh:5-11 headers say personal
  is synced FROM PT). Residual "PT-canonical" assumptions across the estate must be
  grepped and reconciled as part of the R3 build. Recent PRs #49-57 and #100 were merged
  WORK-side — the STANDING work-side PR-merge habit (not only in-flight PRs) must migrate
  to personal-side. `docs/RESUME-HERE.md` already routes cross-machine work through
  `origin/master`, so the documented flow is consistent; it is the observed merge
  behavior that migrates.
- PT-side PRs in flight at cutover must be merged canonical-side (one-time migration note
  in the gate's block message).
- `check_model_pins`/doctor unaffected. New doctor check candidate (builder scope): assert
  the post-commit dual-push hook is installed (`core.hooksPath` → `git-hooks/`) so the
  mirror-by-write path can't silently vanish.
