# Plan: RWR-27 — check-harness-sync.sh `git add -A` index pollution fix
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the hook has no user-observable runtime — its `--self-test` PASS is the acceptance artifact
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
`adapters/claude-code/hooks/check-harness-sync.sh` (a PreToolUse hook on `git commit`) ran `git add -A` when auto-syncing harness drift back to neural-lace. `git add -A` sweeps the ENTIRE working tree into the commit index — including batch residue and live `tree-state.json` — BEFORE the scope-enforcement-gate runs. The scope-gate then sees out-of-scope staged files and BLOCKS every neural-lace commit, even when the author staged only in-scope files (RWR-27). This blocked the Exact-Ask Rule commit and all neural-lace commits. Fix the root cause: a pre-commit verification hook must never mutate the index with `git add -A`.

## User-facing Outcome
The harness maintainer can commit in-scope files in neural-lace without the scope-enforcement-gate spuriously blocking because `check-harness-sync.sh` pre-staged unrelated working-tree residue. The hook's legitimate auto-sync-and-commit purpose is preserved; it now stages only the files it actually synced.

## Scope
- IN: `adapters/claude-code/hooks/check-harness-sync.sh` (canonical) + `~/.claude/hooks/check-harness-sync.sh` (live mirror); `docs/harness-architecture.md` changelog; this plan file.
- OUT: the scope-enforcement-gate itself (it behaves correctly — it was blocking on genuinely-staged-but-out-of-scope files); the auto-sync detection logic; the commit/push logic; neural-lace master reconciliation (orchestrator owns that).

## Tasks
- [ ] 1. Replace `git add -A` with targeted `git add -- "${SYNCED_PATHS[@]}"` staging only the synced files, in canonical + live mirror; add a `--self-test` locking the behavior; update the architecture-doc changelog. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/check-harness-sync.sh` — replace `git add -A` with targeted staging of the exact synced paths (`SYNCED_PATHS[]`); add `--self-test`.
- `~/.claude/hooks/check-harness-sync.sh` — live mirror; byte-identical copy of canonical for immediate unblock (two-layer sync).
- `docs/harness-architecture.md` — update the `check-harness-sync.sh` inventory line with the actual behavior + RWR-27 fix (docs-freshness-gate requires a doc update for a hook change).
- `docs/plans/rwr-27-check-harness-sync-fix-2026-06-14.md` — this plan.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The hook's auto-commit purpose (copy drift back + commit + push) is intentional and must be preserved — removing staging entirely (verify-only) would break it. Confirmed by reading lines 88-137 of the hook.
- The `CHANGED_FILES[]` array and the docs loop already enumerate exactly the files the hook copies, so the synced-paths set is derivable without new detection logic.
- `git add -- <paths>` with explicit pathspecs stages only those paths regardless of other working-tree dirtiness (standard git semantics).

## Edge Cases
- No drift detected → the hook exits at line 79 before any staging; no change in behavior.
- Synced set is empty after copy (race) → guarded by `if [ ${#SYNCED_PATHS[@]} -gt 0 ]` before `git add --`; no `git add` runs.
- Docs synced (live at `neural-lace/docs/`, not under the adapter) → tracked with the repo-relative `docs/<base>` path, not the adapter path.
- Committing inside neural-lace itself → line-22 skip-guard fires (exit 0) before any staging; the `git add -A` was never the neural-lace-internal path, but the latent index-pollution landmine is removed regardless (preemptive per Rule 6).

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal hook; self-test is the acceptance artifact).

## Out-of-scope scenarios
- n/a

## Testing Strategy
- `bash check-harness-sync.sh --self-test` must report 6/6 passed against BOTH canonical and live mirror.
- The negative-control self-test scenario proves `git add -A` WOULD have staged `batch-residue.tmp` + `tree-state.json` alongside the synced file; the fixed-staging scenario proves only the synced path is staged.
- `diff -q` confirms canonical and live mirror are byte-identical.

## Walking Skeleton
n/a — single-file hook edit; the self-test IS the end-to-end slice.

## Decisions Log
### Decision: stage only synced files (Option b) rather than remove staging (a) or make advisory (c)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Replace `git add -A` with `git add -- "${SYNCED_PATHS[@]}"`, staging exactly the files the hook copied.
- **Alternatives:** (a) remove staging entirely → breaks the hook's auto-commit (the copied files would be left uncommitted, defeating the auto-sync). (c) make advisory/warn-only → same breakage of the auto-commit purpose.
- **Reasoning:** Option (b) is the root-cause fix that preserves the hook's legitimate intent (Chesterton's Fence) and structurally cannot pollute the index (Rule 6 — preemptive). The hook already tracks the exact files it copies; staging precisely those is the minimal correct change.
- **Checkpoint:** N/A
- **To reverse:** revert the one staging block back to `git add -A`.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-task plan, no class-sweep needed
- S2 (Existing-Code-Claim Verification): swept — verified the hook's actual behavior (auto-sync + commit) by reading lines 1-141; line numbers cited match
- S3 (Cross-Section Consistency): n/a — single-task plan
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters
- S5 (Scope-vs-Analysis Check): swept — all "Modify" verbs target files in Scope IN

## Definition of Done
- [ ] `git add -A` removed from the live-sync logic; replaced with targeted `git add -- "${SYNCED_PATHS[@]}"`
- [ ] `--self-test` reports 6/6 passed on canonical and live mirror
- [ ] Canonical and live mirror byte-identical (`diff -q`)
- [ ] `docs/harness-architecture.md` changelog updated
- [ ] Committed on branch `fix/rwr-27-check-harness-sync` (NOT merged to messy neural-lace master)
