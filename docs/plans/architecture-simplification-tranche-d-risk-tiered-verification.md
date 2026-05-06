# Plan: Tranche D — Risk-Tiered Verification

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 2
architecture: dialogue-only
frozen: true
prd-ref: docs/plans/architecture-simplification.md
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Sub-tranche of Tranche 1.5. Adds per-task verification level declaration + plan-edit-validator routing logic. Verification is by self-test scenarios on the extended validator + a reference plan that exercises all three levels.

## Goal

Per-task verification proportionate to risk: most harness-dev tasks (mechanical work — file edits, hook updates, prompt updates) get a deterministic bash check. Schema/contract work gets golden-file or schema-validation comparison. Only genuinely-novel or runtime-feature work gets the full task-verifier agent dispatch.

Per queued-tranche-1.5.md D.1: **three tiers (mechanical / full / contract)**. D.2: **default `full` for backward compat**. D.3: **inline declaration at end of task description**.

## Scope

- IN: Plan-template extension with `Verification:` field convention. Update `plan-reviewer.sh` to recognize and validate the field. Update `plan-edit-validator.sh` to route per-task verification (mechanical → bash check, full → task-verifier agent expected, contract → schema/golden-file check). Update `task-verifier.md` agent to be invocation-conditional on `Verification: full`. Document in new rule `adapters/claude-code/rules/risk-tiered-verification.md`. Sync to `~/.claude/`.
- OUT: Migration of existing plan tasks to use the new field (transitional; default applies). The mechanical-evidence substrate (Tranche B already shipped). Auto-classification of existing tasks (manual classification from here forward).

## Tasks

- [ ] 1. Extend `adapters/claude-code/templates/plan-template.md` with `Verification:` inline-task convention. Add a comment block explaining the three levels. Verification: mechanical.
- [ ] 2. Author `adapters/claude-code/rules/risk-tiered-verification.md` (~80-120 lines). Documents: when to use each level, how `Verification:` is parsed, default behavior for unmarked tasks, escalation patterns. Cross-reference Build Doctrine `04-gates.md` tier matrix. Verification: mechanical.
- [ ] 3. Update `adapters/claude-code/hooks/plan-reviewer.sh` to recognize `Verification: <level>` per task. Add validation: legal levels are `mechanical`, `full`, `contract`. Unspecified = `full` (default). Self-test extended with 3 new scenarios. Verification: mechanical (`--self-test` PASS).
- [ ] 4. Update `adapters/claude-code/hooks/plan-edit-validator.sh` to honor per-task verification level when checking checkbox-flip evidence freshness. Mechanical-tier tasks: validator checks for structured `.evidence.json` (per Tranche B's substrate) OR a one-line evidence-block citing commit SHA. Full-tier: existing prose-evidence + task-verifier mandate. Contract-tier: validator checks for a referenced golden-file or schema match. Self-test extended with 3 new scenarios. Verification: mechanical.
- [ ] 5. Update `adapters/claude-code/agents/task-verifier.md` to skip when `Verification: mechanical` or `Verification: contract` is declared. Add: "If the task declares a verification level other than `full`, return immediately with PASS verdict citing the level. The mechanical or contract check is the verification; the agent dispatch is unnecessary." Verification: mechanical (file contains the new section).
- [ ] 6. Sync changes to `~/.claude/{rules,hooks,agents,templates}/`. Verify byte-identical via diff.
- [ ] 7. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with one new row: "Risk-tiered verification" → plan-template + plan-reviewer + plan-edit-validator + task-verifier extensions. Cross-reference Build Doctrine `04-gates.md`.
- [ ] 8. Update `docs/harness-architecture.md` with a section on risk-tiered verification.
- [ ] 9. Flip parent plan Task 4 to `[x]` at completion.

## Files to Modify/Create

- `adapters/claude-code/templates/plan-template.md` — MODIFY (add `Verification:` convention)
- `adapters/claude-code/rules/risk-tiered-verification.md` — NEW (~80-120 lines)
- `adapters/claude-code/hooks/plan-reviewer.sh` — MODIFY (~30-50 added lines including self-test)
- `adapters/claude-code/hooks/plan-edit-validator.sh` — MODIFY (~30-50 added lines)
- `adapters/claude-code/agents/task-verifier.md` — MODIFY (~10-15 added lines)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row)
- `~/.claude/{rules,hooks,agents,templates}/` mirrors
- `docs/harness-architecture.md` — MODIFY
- `docs/plans/architecture-simplification.md` — Task 4 flip
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md` — this plan
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification-evidence.md` — companion evidence

## In-flight scope updates

(none yet)

## Assumptions

- Per queued-tranche-1.5.md D.1-D.3, recommendations apply.
- The mechanical-evidence substrate from Tranche B is already shipped; this plan's `Verification: mechanical` tier consumes that substrate. Verified: Tranche B shipped in commit `35ee3df`.
- `plan-reviewer.sh` and `plan-edit-validator.sh` have well-defined extension points for new field parsing. Verified by reading both hooks earlier this session.

## Edge Cases

- **Task declares `Verification: <unknown>`.** plan-reviewer rejects with clear stderr naming the legal levels.
- **Task is unmarked (legacy plans).** Default `full` applies; existing task-verifier mandate runs as before.
- **Task is marked `mechanical` but ships novel work.** Task author is responsible for the classification; if reviewer suspects misclassification, escalates via in-flight scope update.
- **Three tiers turn out to be insufficient.** Decision C.1's "expand if data shows need" applies; new tier added in a future iteration.

## Acceptance Scenarios

(plan is acceptance-exempt)

## Out-of-scope scenarios

(none)

## Testing Strategy

Mechanical verification per task. Hook self-tests run with extended scenarios. A reference test plan exercises all three levels and demonstrates the validator routing.

## Walking Skeleton

Task 1 (template) ships first as the public surface. Tasks 2-5 implement the validation logic. Tasks 6-8 sync and document.

## Decisions Log

(populated during build if substantive choices arise)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept
S2 (Existing-Code-Claim Verification): swept — plan-reviewer.sh + plan-edit-validator.sh extension points verified by reading
S3 (Cross-Section Consistency): swept
S4 (Numeric-Parameter Sweep): 3 verification tiers consistent across Goal/Scope/Tasks
S5 (Scope-vs-Analysis Check): swept

## Definition of Done

- [ ] All 9 tasks shipped + synced
- [ ] Hook self-tests PASS (extended scenarios)
- [ ] Reference plan demonstrates all three verification levels routing correctly
- [ ] Parent plan Task 4 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition

## Evidence Log

(populated at closure)

## Completion Report

(populated at closure)
