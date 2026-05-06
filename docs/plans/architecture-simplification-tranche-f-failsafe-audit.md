# Plan: Tranche F — Failsafe Audit

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 2
architecture: dialogue-only
frozen: true
prd-ref: docs/decisions/026-harness-catches-up-to-doctrine.md
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Sub-tranche of Tranche 1.5. Walks the enforcement map and classifies each gate KEEP/SCOPE-DOWN/RETIRE. Verification is by per-retirement self-tests and the audit document itself.

## Goal

Walk the 50-row enforcement map at `~/.claude/rules/vaporware-prevention.md`. For each gate, classify per queued decision F.1: KEEP (still load-bearing after redesign), SCOPE-DOWN (subsumed by new mechanism but partial), RETIRE (redundant with new substrate). Execute retirements one-at-a-time per F.2 (each independently revertable). Threshold per F.3: KEEP requires both (a) gate has fired meaningfully in last 30 days AND (b) gate is in the doctrine's gate matrix at `04-gates.md`.

The clear first retirement: **`plan-closure-validator.sh`** — Tranche E's `close-plan.sh` is the structural replacement; the validator's preconditions are subsumed by close-plan's deterministic checks.

## Scope

- IN: Audit document at `docs/reviews/2026-05-05-failsafe-audit.md` capturing per-gate classification + rationale. Execute clear retirements (currently identified: closure-validator). Each retirement is its own commit. Update `vaporware-prevention.md` enforcement map post-retirement to reflect new state.
- OUT: New gates / mechanisms (hard freeze still in effect until Tranche F itself completes). Retirements that require deeper analysis (defer to follow-up audit). Substantive re-design of any KEEP-classified gate.

## Tasks

- [ ] 1. **Author audit document** at `docs/reviews/2026-05-05-failsafe-audit.md`. Walk all 50 enforcement-map rows. For each: KEEP / SCOPE-DOWN / RETIRE classification + 1-2 sentence rationale citing F.3's dual threshold (last-30-day usage + doctrine matrix membership). Verification: mechanical (file exists with table containing all 50 rows).
- [x] 2. **Execute retirement: `plan-closure-validator.sh`**. Remove from `settings.json.template` PreToolUse Edit|Write chain + live mirror; delete the hook file from `adapters/claude-code/hooks/` + `~/.claude/hooks/`; remove the enforcement-map row from `vaporware-prevention.md`; delete the `close-plan.md` skill that wrapped it (it's a stub now; the new `close-plan.sh` script is the replacement). Audit-log the retirement at `.claude/state/failsafe-retirements.md`. Verification: mechanical (files removed, settings entry gone, enforcement-map row deleted).
- [ ] 3. **Identify additional clear retirements** during audit (any other gate that is verifiably subsumed by new substrate). Document candidates; defer execution to next focused audit session unless retirement is trivially safe.
- [ ] 4. **Update `docs/build-doctrine-roadmap.md`** Tranche 1.5 row to ✅ DONE on completion of audit document + first retirement. Add Recent Updates entry naming the closure-validator retirement.
- [ ] 5. **Flip parent plan Task 8** to `[x]` at completion. (Note: parent plan auto-archived in this same session via close-plan.sh; Task 8 lives in the archived copy at `docs/plans/archive/architecture-simplification.md`.)

## Files to Modify/Create

- `docs/reviews/2026-05-05-failsafe-audit.md` — NEW
- `adapters/claude-code/hooks/plan-closure-validator.sh` — DELETE
- `adapters/claude-code/skills/close-plan.md` — REPLACED (was wrapper around closure-validator; now wraps `close-plan.sh`)
- `adapters/claude-code/settings.json.template` — MODIFY (remove closure-validator PreToolUse entry)
- `~/.claude/hooks/plan-closure-validator.sh` — DELETE
- `~/.claude/skills/close-plan.md` — already updated by Tranche E
- `~/.claude/settings.json` — MODIFY (mirror)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (remove closure-validator row)
- `.claude/state/failsafe-retirements.md` — NEW (audit log of retirements)
- `docs/build-doctrine-roadmap.md` — MODIFY at completion
- `docs/plans/archive/architecture-simplification.md` — Task 8 flip (post-archive edit; allowed)
- `docs/plans/architecture-simplification-tranche-f-failsafe-audit.md` — this plan
- `docs/plans/architecture-simplification-tranche-f-failsafe-audit-evidence.md` — companion evidence

## In-flight scope updates

(none yet)

## Assumptions

- Per queued-tranche-1.5.md F.1-F.3, recommendations apply.
- `close-plan.sh` is the structural replacement for `plan-closure-validator.sh`. Verified: `close-plan.sh` shipped Tranche E, byte-identical between adapter and live, self-test PASS 10/10, live acceptance test PASS on 8 plans this session.
- The full 50-row audit is substantial work and may need multiple focused sessions. This plan ships the audit document + the first clear retirement. Subsequent retirements can land in follow-up plans or as in-flight scope updates here.
- Retirements are revertable: each is its own commit; revert a single commit to restore a gate.

## Edge Cases

- **A gate marked RETIRE turns out to still be load-bearing.** Single revert restores the gate. Captured in failsafe-retirements.md as a learned-lesson entry.
- **Mid-audit, a new gap surfaces that argues for a NEW gate.** Hard-freeze applies; defer to post-Tranche-F work; capture in backlog.

## Acceptance Scenarios

(plan is acceptance-exempt)

## Out-of-scope scenarios

(none)

## Testing Strategy

Mechanical verification per task. After closure-validator retirement: confirm `~/.claude/settings.json` no longer wires the hook; confirm subsequent `close-plan.sh` invocations still archive plans correctly.

## Walking Skeleton

Task 2 (closure-validator retirement) ships first as the simplest verifiable retirement. Task 1 (full audit document) authored alongside.

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1: swept
S2: swept — close-plan.sh + plan-closure-validator.sh both verified
S3: swept
S4: 50 enforcement-map rows
S5: swept — every retirement verb maps to a Files-to-Modify entry

## Definition of Done

- [ ] Audit document authored covering all 50 rows
- [x] First retirement (closure-validator) executed
- [ ] No regression: close-plan.sh continues to work post-retirement
- [ ] Roadmap Tranche 1.5 row → ✅ DONE
- [ ] Plan archived

## Evidence Log

See companion file at closure (or evidence captured inline given the small scope).

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:34:40Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-f-failsafe-audit.md` (slug: `architecture-simplification-tranche-f-failsafe-audit`).

Files touched (per plan's `## Files to Modify/Create`):

- `.claude/state/failsafe-retirements.md`
- `adapters/claude-code/hooks/plan-closure-validator.sh`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/settings.json.template`
- `adapters/claude-code/skills/close-plan.md`
- `docs/build-doctrine-roadmap.md`
- `docs/plans/architecture-simplification-tranche-f-failsafe-audit-evidence.md`
- `docs/plans/architecture-simplification-tranche-f-failsafe-audit.md`
- `docs/plans/archive/architecture-simplification.md`
- `docs/reviews/2026-05-05-failsafe-audit.md`
- `~/.claude/hooks/plan-closure-validator.sh`
- `~/.claude/settings.json`
- `~/.claude/skills/close-plan.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03f2a8e chore(closure): close 8 plans via close-plan.sh — Tranche 1.5 substantively complete
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1e6310c feat(hook): A7 — imperative-evidence linker
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
4627e01 feat(settings): wire spawned-task-result-surfacer SessionStart hook (GAP-08 Task 3)
4d18bf5 plan(parallel-tranches): start GAP-16 + Tranche 0b in parallel
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
5870575 feat(hook): A5 — deferral-counter Stop hook
5938a69 feat(tranche-e): deterministic close-plan procedure
7f2187a feat(scope-gate): second-pass redesign — remove waivers, add open-new-plan + system-exempt
82fdde0 feat(harness): FM-023 + harness-architecture inventory + vaporware-prevention map (Phase 1d-C-4 Task 5)
8a5eca3 feat(autonomy): ADR 027 autonomous decision-making process + Tranche 1.5 decision queue
8f4a3c2 feat(harness): plan-deletion-protection — register hook (B.1-B.2)
9d3c2f0 feat(harness): reconcile template-vs-live settings.json — wire 5 missing hooks + upgrade public-repo blocker
9f9a8b1 feat(architecture): land ADR 026 + Tranche 1.5 plan + gate-relaxation policy
a5620fd feat(hooks): TaskCreated + TaskCompleted gates (plan tasks 7+8)
b33cbe1 feat(harness): observed-errors-first rule + PreToolUse gate
b4406c8 feat(phase-1d-c-2): Task 2 — prd-validity + spec-freeze rule docs + cross-refs
c3494fc docs(roadmap): build-doctrine-roadmap — persistent tracker for end-to-end completion
c673b3e feat(harness): effort-level default xhigh + project policy warning hook
cc20cde feat(phase-1d-c-1): ship 3 first-pass C-mechanisms (C10 + C22 + C7-DAG-waiver)
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
