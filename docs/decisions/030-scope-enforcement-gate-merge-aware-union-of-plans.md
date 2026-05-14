# Decision 030 — Scope-enforcement-gate union-of-plans approach for merge commits (DEFERRED)

- **Date:** 2026-05-14
- **Status:** Deferred (the lightweight migration-allowlist approach shipped first; this ADR captures the more-general design for future implementation)
- **Stakeholders:** harness maintainer; every Claude Code session that resolves a merge of master into a feature branch

## Context

`scope-enforcement-gate.sh` (the C10 mechanism) blocks `git commit` when staged files fall outside the active plan's declared `## Files to Modify/Create` or `## In-flight scope updates` sections. It iterates ACTIVE plans currently visible at `docs/plans/*.md` — archived plans (under `docs/plans/archive/`) are not scanned.

This works well for normal builder commits. It fails in one specific shape: **merging master back into a feature branch**. When master has shipped concurrent work (its own plans, now archived), the merge brings in files from those archived plans. The gate sees those files as unclaimed by any currently-active plan and blocks the merge commit.

Today's workarounds:

1. **Lightweight (shipped 2026-05-14, HARNESS-GAP-27 option a).** Extend `_is_system_managed_path()` to honor a merge-context allowlist when `$GIT_DIR/MERGE_HEAD` exists. Currently allows `supabase/migrations/*.sql`, `prisma/migrations/**`, `db/migrations/**`. This handles the canonical case (commit-numbered migrations master generated since divergence) but does not handle the general case (a deploy-mode commit modifying harness-config, a copy of a doc that landed on master, etc.).
2. **Merge-resolution plan.** Author a session-scope plan whose `## Files to Modify/Create` wildcard-claims everything master might have touched (`docs/**`, `src/**`, project-specific subtrees). Fragile — the plan author has to anticipate every directory master might have touched, and the gate-fires-once-fixes-once cycle adds friction (PR #197 hit the gate twice on a single merge for this reason).

Neither approach is principled. The fundamental problem: **the gate's "ACTIVE plans" set is the wrong set during a merge resolution.** During a merge, the relevant scope set is the UNION of all plans active on EITHER side of the merge since the divergence point. A file in master's pulled-in commits was claimed by SOME plan at the time the commit landed — that plan may have since archived, but the commit's scope was correct then and remains correct now in audit terms.

The lightweight migration-allowlist exists because migrations are the most predictable in-merge case (commit-numbered, project-managed paths). But the same logic applies to every file class master controls procedurally during normal development — they're all unclaimed-by-current-HEAD-plans but they were claimed at the time master shipped them.

## Decision

**DEFER until pilot evidence demonstrates the migration-allowlist is structurally insufficient.** When deferral ends, the implementation will be:

### The mechanism

When `$GIT_DIR/MERGE_HEAD` exists, the gate's scope-set computation switches modes:

1. Compute `MERGE_BASE = git merge-base HEAD MERGE_HEAD`.
2. Enumerate every plan slug that was at one point active on EITHER branch in the window `MERGE_BASE..HEAD` and `MERGE_BASE..MERGE_HEAD`. Specifically:
   - For each commit in the window, parse the commit's tree at `docs/plans/*.md` (top-level only).
   - For each plan file present at that commit, parse its first ~50 lines for `Status: ACTIVE`.
   - Record the plan slug if ACTIVE at any point.
3. For each plan slug discovered in step 2, read the plan's current state from either:
   - `docs/plans/<slug>.md` (if still active), OR
   - `docs/plans/archive/<slug>.md` (if archived since), OR
   - The historical version at the commit where it was last ACTIVE.
4. Build the scope set as the UNION of every such plan's `## Files to Modify/Create` and `## In-flight scope updates` entries.
5. Scope-check staged files against this UNION set. The existing logic (glob match, directory-prefix match, exact match) is unchanged; only the source set changes.

Outside merge context, the gate's behavior is unchanged.

### Scope of plan-discovery

The window is `MERGE_BASE..HEAD` ∪ `MERGE_BASE..MERGE_HEAD`, capped at a reasonable depth (e.g., 500 commits per side) to bound walk time. If the merge crosses more than 500 commits per side, the union is computed over the cap; the gate's stderr emits a warning that the union may be incomplete and suggests using the lightweight migration-allowlist + a normal merge-resolution-plan for files the union didn't claim.

### Out of scope for this decision

- Whether to also exempt deletion-only files from a merge (a file deleted on one side and renamed on the other). The intersection of merge-conflict semantics and scope-enforcement is its own design problem; this ADR is scope-extension only.
- Whether to extend the same UNION-of-plans logic to cherry-picks (`$GIT_DIR/CHERRY_PICK_HEAD` exists). Probably yes for consistency, but deferred to the same implementation pass.

## Alternatives Considered

### Option A — Lightweight migration-allowlist only (the shipped approach)

Extend `_is_system_managed_path()` to allow `supabase/migrations/*.sql`, `prisma/migrations/**`, `db/migrations/**` when `MERGE_HEAD` exists. Already shipped 2026-05-14.

- **Pro:** small, surgical, easy to self-test, easy to revert. ~30 lines of bash including self-test scenarios.
- **Pro:** handles the highest-frequency case (PR #197's failure mode was migrations).
- **Con:** does NOT handle non-migration files master controls procedurally. Future PRs will hit the gate on harness-config files, on subtree copies, on lock files, etc. — each requires the same "extend the allowlist" pattern, growing the allowlist asymptotically.
- **Con:** the allowlist is global to all projects using the harness, which makes adding project-specific allowlist entries awkward.

The lightweight option is correct as a v1 — it handles the highest-value case at a tiny implementation cost — but it is not a complete answer.

### Option B — Union-of-plans (this decision, deferred)

The mechanism above. Handles every file the merge legitimately brings in, regardless of class, by computing the right scope set instead of allowlisting individual classes.

- **Pro:** structurally principled. The gate's contract becomes "files must have been claimed by SOME plan that was active during the merge window," which is the actual correctness criterion for merge commits.
- **Pro:** no per-project allowlist maintenance. The gate adapts automatically as projects evolve their plan structure.
- **Pro:** auditable. The gate's stderr can name which historical plan claimed a given pulled-in file.
- **Con:** larger implementation (~4-6 hours including self-test scenarios for merge-aware diff walking, edge-case handling for shallow clones / squash-merge histories).
- **Con:** requires walking git history at every merge commit, which is O(commits-in-window). For typical feature branches this is bounded; for long-lived branches it could be slow. The 500-commit cap mitigates but doesn't eliminate.
- **Con:** depends on commit history integrity — squashed merges, rebased histories, and force-pushed branches may lose the active-plan trail. The lightweight option doesn't have this dependency.

### Option C — Stderr-only documentation (HARNESS-GAP-27 option c)

Add a sentence to the gate's stderr remediation message naming the "merge-resolution plan" pattern as the canonical solution + a worked example, so the friction is well-documented even if not removed.

- **Pro:** trivial (~15 minutes).
- **Pro:** preserves the gate's discipline fully (no exemptions added).
- **Con:** keeps the friction. The user observed PR #197 hitting the gate twice across two merges; documentation doesn't reduce the per-occurrence cost.

Option C alone is insufficient; it was rejected as the headline approach. It MAY be a complement to option A (the shipped lightweight fix), in which case the stderr would name BOTH the migration-allowlist behavior AND the merge-resolution-plan pattern for non-migration files.

### Option D — Skip scope-check entirely when `MERGE_HEAD` exists

Just turn the gate off for all merge commits. The argument: "the user explicitly chose to merge; the contract is implicit."

- **Pro:** zero implementation.
- **Con:** **fails the gate's purpose**. The gate exists because builders accidentally stage scope-expanding files during normal commits; the same accident can happen during merge resolution (e.g., committing local working-directory garbage that wasn't part of the actual merge). Skipping the check entirely breaks the contract.
- **Con:** trains the agent to use merge commits as scope-expansion vectors, which is exactly the failure mode the gate exists to prevent.

Rejected. The right answer is to compute the right scope set during a merge, not to abandon scope-checking during merges.

## Consequences

- **Enables (when implemented):** clean merges of master into feature branches without manual scope-juggling. The gate's contract during a merge becomes correctness-preserving instead of friction-only.
- **Costs (when implemented):** ~4-6 hours of implementation + self-test. Bounded git-walk time per merge commit (typically <500ms for normal feature branches).
- **Costs (deferral):** the lightweight migration-allowlist (option A) is the working substitute; non-migration files still hit the gate during merges and require either a merge-resolution-plan workaround or per-occurrence backlog filings as new file classes surface.
- **Reversal cost:** if union-of-plans turns out to be too slow or too unreliable in practice, the lightweight allowlist is still the correct fallback. The migration-allowlist is independent of the union-of-plans logic; removing union-of-plans does not require removing the allowlist.

## When to un-defer

The union-of-plans approach should be implemented when ANY of these conditions hold:

1. **Three or more distinct file classes** beyond migrations require merge-context allowlist entries within a 30-day window. This signals the per-class allowlist is failing to scale.
2. **A merge-resolution-plan workaround takes longer than 10 minutes to author** for a single merge (PR #197 took ~15-20 minutes across two iterations even with the lightweight migration-allowlist in mind).
3. **A pilot project explicitly requests it** as a structural blocker for adoption.

Pilot evidence will determine which trigger fires first. The deferral is reversible at any time; the lightweight allowlist remains correct as the v1.

## Cross-references

- `~/.claude/hooks/scope-enforcement-gate.sh` — the gate. The lightweight migration-allowlist landed alongside this ADR.
- `~/.claude/rules/gate-respect.md` — the rule this ADR's deferral honors. Rather than per-occurrence bypass, the structural fix-the-gate path is the union-of-plans logic codified here.
- `docs/backlog.md` HARNESS-GAP-27 — the original backlog entry that surfaced this design space. The entry itemizes options (a/b/c); this ADR is the realization of option (b).
- PR #197 — the originating incident.
