# Plan: Fix acceptance gate's refused-exemption branch skipping the waiver valve
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal gate fix; self-test is the acceptance artifact
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Per discovery `docs/discoveries/2026-06-09-acceptance-gate-refused-exemption-skips-waiver-valve.md`:
in `product-acceptance-gate.sh`'s main loop, when `check_exemption` returns EXEMPT_OK but
`plan_declares_ui_surface()` refuses the exemption, the branch appends to BLOCKERS and
`continue`s — skipping the per-session waiver check entirely. A plan in that state cannot be
waived at all; the operator's documented release valve (git-discipline.md Rule 3) is dead for
exactly the plans most likely to need a bridging waiver. Fix per the discovery's recommendation
(option A): on refused exemption, fall through to the waiver check; a fresh substantive waiver
allows stop with a stderr refusal notice; only add the refusal to BLOCKERS when no valid waiver
exists. Keep the refusal message text.

## User-facing Outcome
The maintainer's documented per-session waiver release valve works again on plans whose
acceptance exemption was refused for declaring UI surfaces: an honest mid-rebuild pause with a
fresh substantive waiver allows session stop (with the refusal noted on stderr), while plans
with no valid waiver still block with the unchanged refusal message. Work-shape:
build-harness-infrastructure (`adapters/claude-code/work-shapes/build-harness-infrastructure.md`).

## Scope
- IN: the EXEMPT_OK/refused-exemption branch and waiver-check branch of the main loop in
  `adapters/claude-code/hooks/product-acceptance-gate.sh`; two new `--self-test` scenarios
  (U2, U3) plus scenario-count/header updates; discovery-file status flip to implemented.
- OUT: any change to `check_exemption`, `plan_declares_ui_surface`, `check_waiver`, or the
  artifact-check logic; any change to other hooks; falling through to the ARTIFACT check on
  refused exemption (the refusal blocker text remains the block message when no waiver exists).

## Tasks

- [x] 1. In the main loop, record the UI-surface exemption refusal instead of immediately blocking; fall through to the per-session waiver check (valid waiver → allow with stderr note "exemption refused (UI surface) but valid waiver present"; no/empty/stale waiver → add the unchanged refusal text to BLOCKERS). Extend `--self-test` with U2 (exempt+UI plan + fresh valid waiver → exit 0) and U3 (exempt+UI plan + stale waiver → exit 2); keep all existing scenarios green; update the scenario-count line to 14. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/product-acceptance-gate.sh` — refused-exemption fall-through + U2/U3 self-test scenarios + count/header update
- `docs/discoveries/2026-06-09-acceptance-gate-refused-exemption-skips-waiver-valve.md` — status flip to implemented with Decision + Implementation log
- `docs/plans/fix-acceptance-gate-waiver-valve-2026-06-10-evidence/1.evidence.json` — structured mechanical evidence for Task 1
- `docs/plans/fix-acceptance-gate-waiver-valve-2026-06-10.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- `check_waiver`'s 1-hour freshness window and substantive-content check are correct as-is; the
  fix only changes WHEN the waiver check is reached, not what it accepts.
- The refusal message text is load-bearing (operators and the rule doc quote it); it must remain
  byte-identical in the no-waiver block path.

## Edge Cases
- Refused exemption + EMPTY waiver file: no valid waiver exists, so BOTH the refusal blocker and
  the empty-waiver blocker are emitted (exit 2).
- Refused exemption + STALE waiver (older than 1 hour): `check_waiver` returns NO_WAIVER; the
  refusal blocker is emitted (exit 2) — covered by self-test U3.
- Valid (non-UI) exemption: behavior unchanged — allow with the exemption stderr note, never
  reaching the waiver check (scenario g stays green).
- `refused_exemption_msg` is reset at the top of each loop iteration so one plan's refusal cannot
  leak into the next plan's waiver evaluation.

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal work; the `--self-test` suite (14 scenarios) is the
  acceptance artifact.

## Out-of-scope scenarios
- n/a

## Testing Strategy
- `bash adapters/claude-code/hooks/product-acceptance-gate.sh --self-test` — all 14 scenarios
  (a-h, U, U2, U3, X, W1, W2) must pass, including the two new waiver-valve scenarios.
- One-off synthetic-repo run (exempt+UI plan + fresh waiver) confirming the exact stderr note
  "exemption refused (UI surface) but valid waiver present ... allowing stop" and exit 0.

## Walking Skeleton
- n/a — single-edit fix to an existing mechanism; the self-test IS the end-to-end slice.

## Decisions Log
- Followed discovery recommendation option A (fall through to waiver check), narrowed per the
  dispatch spec: the refused plan does NOT fall through to the artifact check — when no valid
  waiver exists the blocker is the unchanged refusal text, not the artifact-missing text.
  (Tier 1 — isolated, trivially reversible.)

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-task plan, no class-sweep needed
- S2 (Existing-Code-Claim Verification): swept — line refs verified against the live hook at
  fix time (EXEMPT_OK branch + waiver case statement)
- S3 (Cross-Section Consistency): n/a — single-task plan
- S4 (Numeric-Parameter Sweep): swept — scenario count 14 consistent (header, summary line, plan)
- S5 (Scope-vs-Analysis Check): swept — no Scope OUT contradiction; artifact-check fall-through
  explicitly OUT and not prescribed anywhere

## Definition of Done
- [ ] All tasks checked off
- [ ] Self-test 14/14 green
- [ ] Completion report appended to this plan file

## Completion Report

_Generated by close-plan.sh on 2026-06-10T12:13:36Z._

### 1. Implementation Summary

Plan: `docs/plans/fix-acceptance-gate-waiver-valve-2026-06-10.md` (slug: `fix-acceptance-gate-waiver-valve-2026-06-10`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/product-acceptance-gate.sh`
- `docs/discoveries/2026-06-09-acceptance-gate-refused-exemption-skips-waiver-valve.md`
- `docs/plans/fix-acceptance-gate-waiver-valve-2026-06-10-evidence/1.evidence.json`
- `docs/plans/fix-acceptance-gate-waiver-valve-2026-06-10.md`

Commits referencing these files:

```
04f524d fix(harness): remove trust/keep-going instigators behind the 2026-06-09 false-DONE incident
082be8b fix(harness): scope product-acceptance plan discovery to the current repo
0919122 chore(plans): evidence + checkbox for waiver-valve fix (Task 1, Verification: mechanical, 14/14 self-test)
2b47af7 feat(hook): product-acceptance-gate multi-worktree aggregation (plan task 10)
6b79adb fix(acceptance-gate): plan discovery cwd-only, not across worktrees
ba42033 fix(stop-hooks): break infinite-block-loop on unresolvable failures
db458bc fix(hooks): acceptance gate refused-exemption falls through to waiver valve
f790d4f feat(harness): Phase D — production runtime acceptance gate
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
