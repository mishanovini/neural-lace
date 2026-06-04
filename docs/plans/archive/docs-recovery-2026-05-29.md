# Plan: Recover unique-to-this-machine docs (audit + conv-tree-v4 design)

Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: both recovered docs present (docs/audit/2026-05-28-end-of-day-completeness.md, docs/discoveries/2026-05-27-conv-tree-v4-design.md, PR #42 a3c531a/01d3867); the third action (drop the stale review doc) confirmed executed (file absent). All 3 actions done. Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
frozen: true
tier: 1
rung: 0
architecture: harness-infrastructure
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: docs-only recovery; verification is the hygiene scan passing on each recovered file and the files surviving across machines via the canonical PT repo.
Backlog items absorbed: none
owner: misha
target-completion-date: 2026-05-29

## Goal

Recover two operator-personal documents stranded outside the canonical
repo (one in a stash, one on a worktree branch) so they survive across
machines under the 2026-05-29 divergent-history-identical-content sync
posture. Drop one redundant review doc that has been substantively
covered by subsequent shipped doctrine.

## Scope
- IN:
  - Commit `docs/audit/2026-05-28-end-of-day-completeness.md` (recovered from `stash@{0}^3`; redacted for harness-hygiene compliance — identifier-bearing tokens swapped for canonical placeholders).
  - Commit `docs/discoveries/2026-05-27-conv-tree-v4-design.md` (recovered from `conv-tree-v4-accordion-adoption` worktree; hygiene-clean as-is).
  - Drop `docs/reviews/2026-05-20-conv-tree-session-harness-gaps.md` after relevance check — all 5 gaps substantively covered by subsequent session-resilience work (ADRs 037/038/041, plans `file-lifecycle-redesign`, `conv-tree-pending-items-reframe`, `conv-tree-project-root-topology`).
  - Refresh local SCRATCHPAD (gitignored; not in this commit, but tracked as part of the work).
- OUT:
  - Editing the audit doc's semantic content (PR numbers, dates, tracker IDs preserved verbatim; only org/account/project-codename tokens redacted to placeholders).
  - Re-deriving or restating the conv-tree-v4 design (the discovery doc IS the canonical record).
  - Reopening any of the 22 currently-ACTIVE plans these docs touch by reference — those plans address the work this audit reports on; the audit is the cross-cutting summary.

## Tasks
- [ ] 1. Commit the 2 recovered docs with PR open, CI green, squash-merge to PT. — Verification: mechanical (hygiene scan passes, CI green, PR merges).

## Files to Modify/Create
- `docs/audit/2026-05-28-end-of-day-completeness.md` — NEW (recovered + redacted)
- `docs/discoveries/2026-05-27-conv-tree-v4-design.md` — NEW (recovered as-is)
- `docs/plans/docs-recovery-2026-05-29.md` — NEW (this plan)

## Assumptions
- The stash and worktree references (`stash@{0}^3`, `conv-tree-v4-accordion-adoption`) remain available until the docs land on PT master.
- The hygiene-scan placeholder convention used in the audit doc (`<canonical-org>`, `<personal-account>`, `<work-account>`, `<project-A>`, `<project-B>`) is acceptable for future readers — the inline hygiene-note prepended to the doc explains the convention.
- The 5 gaps in the dropped review are genuinely covered by the cited ADRs/plans (verified by grep against `docs/decisions/` and `docs/plans/` on current master).

## Edge Cases
- Stash discarded before docs land → recovery path lost; mitigated by committing in the same session that recovers.
- Conv-tree-v4 worktree pruned → branch ref preserved by `git branch -a`; mitigated by committing in the same session.
- Future redaction reveals additional denylist hits not caught by sed → mitigated by running the full hygiene scan locally before commit and again in CI.

## Testing Strategy
- Mechanical: `bash adapters/claude-code/hooks/harness-hygiene-scan.sh <each-file>` exit 0; CI `Harness-hygiene scan` job passes; PR template validator passes (uses (c) form — no mechanism applies to docs-recovery work).

## Walking Skeleton

n/a — two file adds + one file drop.

## Acceptance Scenarios

n/a — acceptance-exempt per header (docs-only; the operational outcome is the docs surviving across machines via PT canonical).

## In-flight scope updates

None.

## Decisions Log

### Decision: Redact-and-ship the audit doc rather than drop it
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Redact identifier-bearing tokens using canonical placeholders, prepend a hygiene-note explaining the convention, ship.
- **Alternatives:** (a) Drop the audit doc entirely (loses durable value the user explicitly named). (b) Save off-repo to `~/.claude/local/` (preserves value but loses cross-machine durability under the new sync posture — the whole point of this PR). (c) Add `docs/audit/` to the hygiene exemption list (expands the hygiene-rule's surface to admit instance identifiers; doctrine-level change not warranted by a one-doc recovery).
- **Reasoning:** The user named the audit doc as high durable value and named `docs/audit/` as the target path. Redaction preserves semantic value (PR numbers, dates, tracker IDs, decision rationale) while honoring `~/.claude/rules/harness-hygiene.md`. The inline hygiene-note makes the placeholder convention legible to future readers.
- **Checkpoint:** N/A (single commit).
- **To reverse:** `git revert <this-PR's-merge-SHA>` would restore master without the docs; the recovered originals can be re-derived from the stash + worktree refs which remain in the repo's reflog/refs.

### Decision: Drop the 2026-05-20 conv-tree review per relevance check
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Drop the 95-line review file.
- **Alternatives:** Ship it for the durable-record argument; ship a header-only stub linking to the shipped doctrine.
- **Reasoning:** All 5 gaps the review flagged are substantively covered by subsequent doctrine shipped to master (ADRs 037/038/041 + 3 named plans). Shipping the review adds redundant content and risks confusing future readers about which document is the durable record. Per user instruction.
- **Checkpoint:** N/A.
- **To reverse:** The branch `salvage/nervous-lehmann-review` retains the file; restore via `git show salvage/nervous-lehmann-review:docs/reviews/2026-05-20-conv-tree-session-harness-gaps.md > <path>`.

## Definition of Done
- [ ] All tasks checked off
- [ ] CI all-green on PT PR
- [ ] PR merged to PT master
- [ ] Personal master cherry-picked + tree-hash-equivalent
- [ ] Plan Status: COMPLETED, auto-archived
