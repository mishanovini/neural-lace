# Plan: Triage 5 stale neural-lace ACTIVE plans (2026-06-17)
Status: SUPERSEDED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal plan bookkeeping — Status flips, completion reports, and a one-line architecture-doc changelog entry; no product surface; the closed plans' own self-tests / shipped-commit verification are the acceptance artifact.
tier: 1
rung: 0
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Disposition (2026-07-02)
Items 1–2 executed by the nl-overhaul estate pass (exact-ask-rule closed; wim-deploy-age-guard-fix.md confirmed already archived at docs/plans/archive/, not top-level ACTIVE — nothing further to do). Items 3–4 superseded by nl-overhaul F.3 + DEC-2026-07-02-002.

## Goal
Triage the stale ACTIVE plans in `docs/plans/`: verify each plan's deliverables against `origin/master`, and for each either close it (COMPLETED + archive) when fully shipped, keep it ACTIVE with a dated Decisions Log note when it is live decision-blocked work, or report a recommendation when its disposition is the operator's call. Plan bookkeeping only — no source code, no feature work.

## User-facing Outcome
The maintainer's `docs/plans/` no longer carries plans that shipped-but-were-never-closed; each remaining ACTIVE plan is genuinely in-flight with its current state documented; the architecture-doc reflects the Exact-Ask Rule that shipped on 2026-06-14.

## Scope
- IN: Status flips (via Edit, so `plan-lifecycle.sh` archives correctly) + completion reports on the two plans confirmed fully shipped; a Decisions Log note on `orchestrator-prime.md`; the missed Exact-Ask architecture-doc changelog entry in `docs/harness-architecture.md` (closing Task 2 of the now-completed exact-ask plan); this plan file.
- OUT: any source/feature code; any change to the two already-DEFERRED plans (`agent-upgrades-batch2-ab-staging`, `plan-lifecycle-redesign`) — their disposition is the operator's call and they are correctly DEFERRED; merging this PR.

## Tasks
- [ ] 1. Close `exact-ask-rule-2026-06-14` (COMPLETED + archive) after verifying both tasks shipped via bd08119; close Task 2's missed architecture-doc changelog entry. — Verification: mechanical
- [ ] 2. Close `wim-deploy-age-guard-fix` (COMPLETED + archive) after verifying the fix + T15 shipped via PR #61 (self-test 50/50). — Verification: mechanical
- [ ] 3. Keep `orchestrator-prime` ACTIVE; append a 2026-06-17 Decisions Log entry (pending operator greenlight). — Verification: mechanical
- [ ] 4. Assess `agent-upgrades-batch2-ab-staging` + `plan-lifecycle-redesign` (both already DEFERRED) and report recommendations. — Verification: mechanical

## Files to Modify/Create
- `docs/plans/exact-ask-rule-2026-06-14.md` — completion report + Status: COMPLETED (auto-archives).
- `docs/plans/wim-deploy-age-guard-fix.md` — completion report + Status: COMPLETED (auto-archives).
- `docs/plans/orchestrator-prime.md` — Decisions Log entry (stays ACTIVE).
- `docs/harness-architecture.md` — Exact-Ask Rule changelog entry (closes Task 2 of the exact-ask plan).
- `docs/plans/triage-stale-plans-2026-06-17.md` — this plan file.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- `origin/master` is the source of truth for which deliverables shipped.
- `plan-lifecycle.sh` archives a COMPLETED plan on the Edit-tool Status flip (confirmed at runtime this session — both closed plans auto-archived to `docs/plans/archive/`).
- The two already-DEFERRED plans are not stale ACTIVE plans (the dispatch premise rested on a stale git-status snapshot); leaving them DEFERRED is correct.

## Edge Cases
- A named plan's deliverables are NOT all on master → leave ACTIVE / report (orchestrator-prime).
- A named plan is already DEFERRED + archived → no action; report the deviation + recommendation.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal plan bookkeeping; verification is the shipped-commit / self-test confirmation per closed plan).

## Out-of-scope scenarios
n/a — acceptance-exempt.

## Testing Strategy
- Each closure verified against master: grep the shipped deliverable + run the plan's own self-test where one exists (wim: `work-in-motion-sweep.selftest.js` 50/50 with T15).
- Live `~/.claude` mirror of the architecture-doc edit verified byte-identical.

## Walking Skeleton
The Status flips + completion reports + the one architecture-doc entry ARE the end-to-end slice; `plan-lifecycle.sh` archival on the COMPLETED flip is the proof it wired through.

## Decisions Log
- The dispatch named 5 "stale ACTIVE plans," but only 3 were ACTIVE on master (`exact-ask-rule` was a staged-only file in the main checkout; `agent-upgrades-batch2` and `plan-lifecycle-redesign` were already DEFERRED + in `docs/plans/deferred/`). Surfaced as a deviation; acted on the true state per Rule 0 (honesty) rather than the snapshot premise.
- `docs/harness-architecture.md` is claimed by THIS triage plan (Option 2 — open a new plan, per `gate-respect.md`) rather than retro-fitted into orchestrator-prime's scope, because the architecture-doc edit is triage work (closing the exact-ask plan's Task 2), not orchestrator-prime work.

## Pre-Submission Audit
- S1–S5: n/a — Mode: code harness-bookkeeping plan, no class-sweep needed.

## Definition of Done
- [ ] Two fully-shipped plans COMPLETED + archived with completion reports.
- [ ] orchestrator-prime kept ACTIVE with the dated Decisions Log entry.
- [ ] Both already-DEFERRED plans assessed; recommendations reported.
- [ ] Architecture-doc Exact-Ask entry landed + live mirror byte-identical.
