# Plan: Tranche D — Risk-Tiered Verification

Status: COMPLETED
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

_Generated by close-plan.sh on 2026-05-06T04:25:54Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md` (slug: `architecture-simplification-tranche-d-risk-tiered-verification`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/agents/task-verifier.md`
- `adapters/claude-code/hooks/plan-edit-validator.sh`
- `adapters/claude-code/hooks/plan-reviewer.sh`
- `adapters/claude-code/rules/risk-tiered-verification.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/templates/plan-template.md`
- `docs/harness-architecture.md`
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification-evidence.md`
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2f3be21 feat(harness): D1+D4+D5 follow-through — plan template, multi-push impl, hygiene-scan expansion gap
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
4d94940 docs(plan-mode): Execution Mode: agent-team value + cross-references (plan task 12)
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
5870575 feat(hook): A5 — deferral-counter Stop hook
5938a69 feat(tranche-e): deterministic close-plan procedure
5c8e3e4 feat(harness): no-test-skip gate + deploy-to-production rule
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
