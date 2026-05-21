# Plan: cross-project decision-batch handoff doc + cross-branch stash discovery
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal docs-only compilation work; the staying-in-neural-lace artifact is a process-discovery file. The cross-project decision-batch handoff doc that motivated this session lives outside the harness repo at `~/claude-projects/MISHA-DECISIONS-2026-05-20.md` because the harness denylist correctly forbids downstream-project codenames in committed harness content.
prd-ref: n/a — harness-development

## Goal

Two artifacts came out of this session. They live in different places:

1. **`~/claude-projects/MISHA-DECISIONS-2026-05-20.md`** (OUTSIDE this repo) — a single compiled doc with every long-standing "needs-Misha-decision" item across his projects, so the maintainer can power through them in one sitting instead of context-switching. Lives at the parent of his project directories so it's accessible across all projects without violating harness-hygiene rules in any single project.
2. **`docs/discoveries/2026-05-21-stash-push-single-file-leaves-unstashed-deletions-stageable.md`** (this repo) — a captured failure-mode discovery from this session about a cross-branch git failure mode hit during a docs-only commit attempt.

This plan claims the in-repo artifacts and points at the off-repo one.

## Scope

- IN: writing this plan, the discovery file, committing both to a feature branch in this worktree, pushing the branch, opening a PR, merging to master.
- OUT: any code change. The off-repo handoff doc at `~/claude-projects/MISHA-DECISIONS-2026-05-20.md` is also out of this plan's commit scope (intentionally not committed anywhere; it's a personal cross-project artifact).

## Tasks

- [x] 1. Write the cross-project decision-batch handoff doc to `~/claude-projects/MISHA-DECISIONS-2026-05-20.md` (outside the harness repo). — Verification: mechanical
- [x] 2. Write the cross-branch stash discovery file to `docs/discoveries/`. — Verification: mechanical
- [ ] 3. Commit the plan + discovery file together on the current feature branch. — Verification: mechanical
- [ ] 4. Push the feature branch and open a PR to master. — Verification: mechanical
- [ ] 5. Merge the PR to master per pre-customer auto-merge policy. — Verification: mechanical

## Files to Modify/Create

- `docs/discoveries/2026-05-21-stash-push-single-file-leaves-unstashed-deletions-stageable.md` — new file; the process discovery.
- `docs/plans/misha-decision-batch-handoff-2026-05-20.md` — this plan file.

## Assumptions

- The current branch (`claude/condescending-burnell-dc70b5`) is the right feature branch to use for landing the discovery file; no need to spin a separate one.
- Pre-customer policy applies to neural-lace (the harness repo) — auto-merge after CI green is acceptable.
- The discovery file's `Status: pending` will not block other gates because it's a discovery file (the discovery-protocol substrate accepts pending entries).

## Edge Cases

- If the harness-hygiene scanner fires on any downstream-project codenames remaining in this plan or the discovery, surface and sanitize. Anonymize downstream-project names to "a downstream-project" / "the downstream repo" generically.
- If `prd-validity-gate.sh` blocks on the `prd-ref:` value, the `n/a — harness-development` carve-out (per `~/.claude/rules/prd-validity.md`) should resolve it.

## Testing Strategy

Each task is mechanical: file exists, commit landed, PR opened, PR merged. Self-test by `ls`, `git log --oneline`, `gh pr view`.

## Walking Skeleton

Smallest end-to-end slice: write the plan + discovery, commit both together (so the gate sees the plan claiming the discovery), push, open PR, merge.

## Decisions Log

- 2026-05-21: Authored the plan retroactively after the discovery file was already written, because `scope-enforcement-gate.sh` correctly blocked the commit (genuinely separate from the active conv-tree-ui-v1.1.2-polish plan).
- 2026-05-21: REDIRECTED the cross-project decision-batch handoff doc OUT of the harness repo to `~/claude-projects/MISHA-DECISIONS-2026-05-20.md` after the harness denylist correctly fired on downstream-project codenames in the original draft. The handoff doc's core purpose is a cross-project list and cannot be anonymized without defeating its utility; the right destination is a personal location outside any specific project's repo.

## Definition of Done

- [ ] Discovery file is on neural-lace master.
- [ ] This plan file's Status flips to COMPLETED and auto-archives.
- [ ] The discovery file remains `Status: pending` (its remediation lands via a separate future plan, not this one).
