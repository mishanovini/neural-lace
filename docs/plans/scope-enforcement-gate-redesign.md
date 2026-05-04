# Plan: Scope-Enforcement-Gate Redesign — Read In-flight Scope Updates + Tier the Block-Message Options

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-hook redesign; verification is per-hook self-test plus observed behavior in subsequent commits.

## Context

Per the D1 reframe (2026-05-03/04 dialogue): the current `scope-enforcement-gate.sh` blocks out-of-scope commits with a single suggested fix — write a waiver. This rewards the wrong path: waiver is easy, plan-update is friction-heavy, so builders default to waivers. The waiver pattern undermines the discipline the gate was meant to enforce — plans stay static while actual scope expands silently.

The plan template was updated in commit `2f3be21` to add `## In-flight scope updates` section. The gate must now be updated to read this section AND restructure its block-message into three tiered options that reward the correct path first.

Recovery point: tag `pre-build-doctrine-integration` at master HEAD `10adac2`; integration branch tip at `2f3be21`.

## Goal

Update `scope-enforcement-gate.sh` so:

1. Plan-section parsing reads BOTH `## Files to Modify/Create` AND `## In-flight scope updates`. A file matching either is in-scope. Backward compatible: plans without the new section work as before.

2. Block-message restructured into three tiered options:
   - **Option 1 (RECOMMENDED) — Update the plan.** Show the exact line to add to `## In-flight scope updates`: `- <YYYY-MM-DD>: <file> — <one-line reason>`. Re-stage and re-commit.
   - **Option 2 — Defer to a different plan.** Unstage the file; add a backlog entry or new plan to claim it.
   - **Option 3 (last resort) — Waive.** Write a waiver file at `.claude/state/scope-waiver-<plan-slug>-<timestamp>.txt` with substantive justification.

3. Self-tests cover: existing scenarios still pass + new scenarios for in-flight-scope-updates section parsing + block-message structure verification.

4. Mirror to `~/.claude/hooks/scope-enforcement-gate.sh`.

## Scope

**IN:**
- Modify `adapters/claude-code/hooks/scope-enforcement-gate.sh` to read `## In-flight scope updates` section.
- Mirror to `~/.claude/hooks/scope-enforcement-gate.sh`.
- Update the block-message stderr template with the three tiered options.
- Add 3 new self-test scenarios: (a) file matches in-flight-scope-updates entry → allow; (b) file in original Files-to-Modify, in-flight-scope-updates section absent → still allow (backward compat); (c) file in neither section, no waiver → block with three-tiered message.
- Update `~/.claude/rules/vaporware-prevention.md` enforcement-map row for scope-enforcement-gate to mention the new behavior.
- Update `docs/harness-architecture.md` preface annotation.
- Single thematic commit on `build-doctrine-integration`; push (multi-push to both remotes).

**OUT:**
- Migrating existing waiver files (they remain valid as historical records).
- Adding a separate audit step for waiver-frequency tracking (would belong with HARNESS-GAP-11 calibration mimicry work).
- Creating the gate's third-option waiver path differently than today (still .claude/state/scope-waiver-* pattern).

## Tasks

- [x] **T1.** Update `adapters/claude-code/hooks/scope-enforcement-gate.sh`. Three concrete changes:
  (a) Plan-section parsing extended to also read `## In-flight scope updates` (mirror the existing `## Files to Modify/Create` parsing pattern; same bullet-extraction logic, glob-matching).
  (b) Block-message stderr template restructured with the three tiered options. Show concrete commands for each option (option 1: the exact line to add; option 2: `git restore --staged <file>` + backlog template; option 3: the waiver-file path).
  (c) Add 3 new self-test scenarios. Run `--self-test` and confirm 11/11 (8 existing + 3 new) pass.
- [x] **T2.** Mirror to `~/.claude/hooks/scope-enforcement-gate.sh` (byte-identical via `cp`).
- [x] **T3.** Update `~/.claude/rules/vaporware-prevention.md` enforcement-map row for scope-enforcement-gate to note the new tiered-options + in-flight-scope-updates behavior. Mirror to adapter copy.
- [x] **T4.** Update `docs/harness-architecture.md` preface annotation (chain new entry).
- [ ] **T5.** Commit + push (multi-push will hit both remotes).

## Files to Modify/Create

**Modified:**
- `adapters/claude-code/hooks/scope-enforcement-gate.sh`
- `~/.claude/hooks/scope-enforcement-gate.sh` (mirror)
- `adapters/claude-code/rules/vaporware-prevention.md`
- `~/.claude/rules/vaporware-prevention.md` (mirror)
- `docs/harness-architecture.md`
- `docs/plans/scope-enforcement-gate-redesign.md` (this plan; self-referential)

## In-flight scope updates

- 2026-05-04: `adapters/claude-code/hooks/scope-enforcement-gate.sh` — second-pass redesign per user D1-deep-dive (2026-05-04): waiver path removed entirely; replaced with "open a new plan" as option 2; added system-managed-path allowlist for `docs/plans/archive/*` (plan-lifecycle archival operations exempt). Reason: waivers were papering over cases that have better structural answers; user analysis confirmed all use cases fit options 1/2 or system-managed exempt.
- 2026-05-04: `~/.claude/hooks/scope-enforcement-gate.sh` (mirror of above)
- 2026-05-04: tests for new scenarios (system-managed-exempt; new-plan-staged; waiver-removal verification)
- 2026-05-04: `docs/plans/scope-enforcement-gate-redesign-evidence.md` — companion evidence file written by task-verifier per evidence-first protocol; not initially listed in `## Files to Modify/Create` because it's auto-generated by verification, not authored by the plan. Gate-flagged on commit attempt, captured here per the option-1 workflow (the gate's own self-test).

## Assumptions

- The existing scope-enforcement-gate.sh has been verified to work in production (it has fired multiple times this session); the redesign extends rather than rewrites.
- Backward compatibility: plans without `## In-flight scope updates` section continue to work — gate treats missing section as empty list, scope-check uses only `## Files to Modify/Create`.
- pre-submission-audit-mechanical-enforcement.md remains ACTIVE; this commit needs a waiver against it.

## Edge Cases

- **Plan has both sections but scope-update entry is malformed** (no file path, no date). Gate treats as no-op for that entry but doesn't block.
- **In-flight-scope-updates entry uses a glob that matches MORE than the staged file.** Same glob-handling as Files-to-Modify section.
- **Existing self-tests rely on specific block-message text.** Update self-tests to match new text; ensure no regression.

## Acceptance Scenarios

n/a — `acceptance-exempt: true`. Verification via `--self-test` all-pass + observed behavior in subsequent commits using the redesigned gate.

## Definition of Done

- All 5 tasks task-verified PASS.
- Hook self-test: 11/11 scenarios pass on both copies.
- Mirror byte-identical.
- Single commit pushed to both remotes via multi-push.
- Status of THIS plan flipped to COMPLETED at session end.
