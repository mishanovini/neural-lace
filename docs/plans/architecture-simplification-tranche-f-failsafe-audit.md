# Plan: Tranche F — Failsafe Audit

Status: ACTIVE
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

(populated at closure)
