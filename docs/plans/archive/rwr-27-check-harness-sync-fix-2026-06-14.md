# Plan: RWR-27 — check-harness-sync.sh `git add -A` index pollution fix
Status: COMPLETED
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

## Completion Report

_Generated by close-plan.sh on 2026-06-14T10:44:56Z._

### 1. Implementation Summary

Plan: `docs/plans/rwr-27-check-harness-sync-fix-2026-06-14.md` (slug: `rwr-27-check-harness-sync-fix-2026-06-14`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/check-harness-sync.sh`
- `docs/harness-architecture.md`
- `docs/plans/rwr-27-check-harness-sync-fix-2026-06-14.md`
- `~/.claude/hooks/check-harness-sync.sh`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2590947 feat(hook): pre-push-divergence-check — block stale-fetch pushes to master (#47)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
3402cd6 feat(hooks): land customer-facing-review gate from 2026-06-02 salvage (ADR 053, renumbered from 046)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3a2babc reconverge: land personal fork onto PT master (decision-context + pr-health + F7 + principles)
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3b19478 feat(hooks): cross-repo-drift-postpush-gate — surface NL remote divergence at push time
3ce9b05 feat(doc-gate): F7 dev-doc gate (warn-mode default) for src/**/*.ts(x) commits (#46)
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
