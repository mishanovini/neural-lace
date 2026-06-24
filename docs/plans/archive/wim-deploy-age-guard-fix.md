# Plan: Fix gone-this-pass false-DEPLOYED in work-in-motion-sweep (PR #61)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal tooling — a Node sweep script whose acceptance idiom is its `--self-test`; no browser-observable runtime surface for end-user-advocate to exercise.
tier: 2
rung: 1
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal
PR #61 (`fix/workstreams-ui-reflect-real-status`) shipped ADR-056 deploy
detection but a harness-reviewer REJECT identified a Critical false-DEPLOYED
bug: the gone-this-pass branch in `work-in-motion-sweep.js` emitted
`item-deployed` with NO age guard, so a PR that merges in the SAME sweep pass
was marked deployed against ANY pre-existing Ready prod deploy — including one
that completed days BEFORE the merge and cannot contain its code. This plan
closes the gap with a single shared "deploy strictly newer than ship"
predicate gating every path to `item-deployed`, plus a regression test (T15)
and a harness-hygiene anonymization.

## User-facing Outcome
The Workstreams "Work in Motion" view no longer mislabels a just-merged PR as
Deployed against a stale prod deploy; an item stays shipped-not-deployed until
a sweep observes a Ready prod deploy genuinely newer than its merge.

## Scope
- IN: age-guard the gone-this-pass deploy path via one shared predicate; T15
  regression test; anonymize the `proj-circuit` codename in the archived plan
  doc.
- OUT: any change to deploy-event schema, the reducer, the GUI, or other
  workstreams scripts.

## Tasks
- [x] 1. Extract a shared `deployIsNewerThanShip(readyMs, shipMs)` predicate and gate BOTH deploy-emission branches on it (gone-this-pass uses ship time == now). — Verification: mechanical
- [x] 2. Add T15 regression test (gone-this-pass + old deploy must NOT plan item-deployed); confirm 50/50, T14 + T12c still green. — Verification: mechanical
- [x] 3. Anonymize `proj-circuit` → "a Vercel-linked project" in the archived plan's Testing Strategy. — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js` — add shared predicate; both branches gate on it (the fix).
- `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js` — add T15 must-NOT-fire negative test.
- `docs/plans/archive/workstreams-ui-reflect-real-status.md` — anonymize product codename (harness-hygiene).
- `docs/plans/wim-deploy-age-guard-fix.md` — this plan file.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The existing prior-pass guard (`readyMs >= shipMs`) is correct and the only
  defect is the missing guard on the gone-this-pass branch (PROVEN by the
  reviewer and reproduced against the real `sweep()`).
- The selftest harness's `ok()` count reflects one assertion per call, so one
  new T15 assertion takes the suite 49 → 50.

## Edge Cases
- Legacy checked item with no `shipped_ts` and not gone-this-pass → unknown
  ship time → NOT auto-deployed (predicate returns false on null/NaN shipMs).
- Happy path (deploy newer than this-pass ship) still emits item-deployed —
  no false-negative introduced (T12c guards this).

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal Node tooling; `--self-test` is the
acceptance artifact).

## Out-of-scope scenarios
n/a

## Testing Strategy
- `node neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js`
  → 50/50 with T15 green; T15 RED-verified against the unfixed code.
- No regression: state selftest 21/21, reconciler selftest 33/33.

## Walking Skeleton
The shared predicate + the single gated emission path IS the end-to-end slice;
the self-test exercises it.

## Decisions Log
### Decision: one shared predicate as the only gate on item-deployed
- **Tier:** 2
- **Status:** proceeded with reviewer's required generalization
- **Chosen:** extract `deployIsNewerThanShip(readyMs, shipMs)`; compute one
  effective `shipMs` (reduced `shipped_ts` for prior-pass, `nowMs` for
  gone-this-pass) and gate the single `item-deployed` emission on it.
- **Alternatives:** add a second inline `readyMs >= nowMs` check only in the
  gone-this-pass arm (rejected — leaves two guard sites that can drift; the
  reviewer required ONE predicate on EVERY path).
- **Reasoning:** a single predicate on the single emission path means no code
  path can reach `item-deployed` ungated.
- **Checkpoint:** N/A (committed as one change)
- **To reverse:** revert the commit.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code bug-fix, not a Mode: design plan.
- S2 (Existing-Code-Claim Verification): swept — confirmed the prior-pass guard at the shared predicate call site and the single `item-deployed` emission site.
- S3 (Cross-Section Consistency): swept, 0 contradictions.
- S4 (Numeric-Parameter Sweep): swept — selftest count 49→50; no other params.
- S5 (Scope-vs-Analysis Check): swept — all three task verbs target files listed in Scope IN.

## Definition of Done
- [x] All tasks checked off
- [x] Self-test 50/50 with T15 green
- [x] SCRATCHPAD/plan reconciled
- [x] PR #61 updated (orchestrator re-confirms + merges)

## Completion Report (2026-06-17 — triage)

The fix shipped to `origin/master` via **PR #61** (merge commit **ac29415** — "fix(workstreams): reflect real deploy status + stop builder-dispatch noise polluting shipped-not-deployed (#61)"). All three tasks verified on master:

- **Task 1** — the shared `deployIsNewerThanShip(readyMs, shipMs)` predicate is present at `neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js:394` and gates EVERY path to `item-deployed` (the single emission site at :575 continues only when the predicate passes; the comment at :549 documents the one-predicate-gates-every-path design).
- **Task 2** — the T15 regression test ("gone-this-pass + deploy older than the just-now merge does NOT mark deployed") is present at `work-in-motion-sweep.selftest.js:368-391`. Self-test run at triage time: **50 passed, 0 failed** with T15 green — the plan's stated acceptance idiom (PROVEN at runtime).
- **Task 3** — `proj-circuit` codename anonymized in `docs/plans/archive/workstreams-ui-reflect-real-status.md` (grep count: 0 occurrences).

acceptance-exempt (harness-internal Node tooling; `--self-test` is the acceptance artifact). All deliverables confirmed shipped → COMPLETED.
