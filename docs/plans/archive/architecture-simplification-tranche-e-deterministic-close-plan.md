# Plan: Tranche E — Deterministic Close-Plan Procedure

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
acceptance-exempt-reason: Sub-tranche of Tranche 1.5. Replaces the existing /close-plan skill (today a wrapper around the heavy stack) with a deterministic bash script that closes plans in seconds. Verification is by self-test scenarios + closing this very plan via the new procedure (acceptance test).

## Goal

Replace the current `/close-plan` skill (shipped today as part of GAP-16, currently a coordinator wrapping the heavy verification stack) with a **deterministic bash script that closes plans in ~4 seconds with zero agent dispatches**. This is the highest-leverage payoff of Tranche 1.5 — the architectural change that turns "closure costs more than the work" into "closure is a 4-second script."

The new procedure consumes the substrates Tranches B (mechanical evidence) and D (risk-tiered verification) shipped:
- For `Verification: mechanical` tasks: bash check + structured `.evidence.json` write
- For `Verification: contract` tasks: schema/golden-file comparison
- For `Verification: full` tasks: existing prose-evidence + task-verifier path (unchanged)
- Generates completion report from template + commit log
- Updates SCRATCHPAD
- Reconciles backlog
- Flips Status (which triggers existing plan-lifecycle.sh archival)
- Auto-pushes per existing customer-tier policy + user's full-auto preference

Per queued-tranche-1.5.md E.1: **bash script wrapped by slash command**. E.2: **auto-push by default** (per user's `feedback_full_auto_deploy.md` memory). E.3: **block by default with `--force` escape** for emergency override.

## Scope

- IN: New bash script `adapters/claude-code/scripts/close-plan.sh` implementing the deterministic procedure. Rewrite `adapters/claude-code/skills/close-plan.md` (existing) to invoke the script. Self-test ~10 scenarios covering: all-mechanical-tasks-closure, all-full-tasks-closure (existing path), mixed-tier-closure, missing-completion-report-blocks, stale-SCRATCHPAD-blocks, unreconciled-backlog-blocks, --force-bypass, runtime-failure-blocks, missing-evidence-blocks, all-PASS-archives. Update enforcement map. Sync to `~/.claude/`. Closes this very plan as the acceptance test (Task 11 of the parent plan).
- OUT: Retirement of the existing closure-validator hook (Tranche F's job). Migration of legacy plans to the new procedure (transitional; legacy plans close via existing mechanisms). Auto-discovery of plan tier from content (manual `Verification:` declarations per Tranche D's pattern).

## Tasks

- [ ] 1. Author `adapters/claude-code/scripts/close-plan.sh` (~300-400 lines including self-test). Subcommand: `close-plan.sh close <plan-slug>`. Implementation: parse plan file's Tasks; for each, read `Verification:` level; run mechanical/contract checks OR confirm full-tier evidence already present; capture mechanical evidence via Tranche B's helper; generate completion report (Implementation Summary, Design Decisions, Known Issues sub-sections) from commit-log diff + plan files-to-modify; update SCRATCHPAD; verify backlog reconciliation; flip Status (which triggers existing plan-lifecycle.sh archival); auto-push if no `--no-push` flag. Verification: mechanical (`--self-test` PASS).
- [ ] 2. Add `--self-test` flag with 10 scenarios per the plan's testing strategy. Each scenario sets up a synthetic plan in a temp git repo, invokes the close-plan script, asserts expected outcome (block/allow + correct artifacts produced).
- [ ] 3. Rewrite `adapters/claude-code/skills/close-plan.md` to be a thin slash-command wrapper invoking the bash script. Keep the existing pattern of skill → script invocation. Verification: mechanical (skill file invokes the script; smoke-test runs).
- [ ] 4. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map: amend the existing `plan-closure-validator.sh` row to reference the new deterministic procedure as the primary closure path; mark the closure-validator as "tagged-for-retirement during Tranche F audit; deterministic procedure (this Tranche) is the replacement." Verification: mechanical.
- [ ] 5. Sync `adapters/claude-code/scripts/close-plan.sh` and `adapters/claude-code/skills/close-plan.md` to `~/.claude/`. Verify byte-identical.
- [ ] 6. Update `docs/harness-architecture.md` with the new deterministic close-plan procedure section.
- [ ] 7. **Acceptance test: close THIS plan (Tranche E) using the new procedure.** Successful closure proves the procedure works end-to-end. The closure-validator hook will fire as it does today (it's tagged for retirement, not yet retired); the new procedure must produce evidence that satisfies it. Capture timing (target: < 30 seconds for full closure) as evidence in the completion report.
- [ ] 8. Flip parent plan Task 5 to `[x]` at completion.

## Files to Modify/Create

- `adapters/claude-code/scripts/close-plan.sh` — NEW (~300-400 lines including self-test)
- `adapters/claude-code/skills/close-plan.md` — REWRITE (existing thin coordinator → thin wrapper around the bash script)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (amend existing row)
- `~/.claude/scripts/close-plan.sh`, `~/.claude/skills/close-plan.md` — sync mirrors
- `docs/harness-architecture.md` — MODIFY
- `docs/plans/architecture-simplification.md` — Task 5 flip
- `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md` — this plan
- `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan-evidence.md` — companion evidence

## In-flight scope updates

(none yet)

## Assumptions

- Per queued-tranche-1.5.md E.1-E.3, recommendations apply (bash wrapped by slash command, auto-push default, block-with-force-flag).
- Tranche B's mechanical-evidence substrate is shipped (verified — commit `35ee3df`); the new procedure consumes it.
- Tranche D's risk-tiered verification is shipped (verified — commit `f4b818f` cherry-picked above); plan tasks declare `Verification:` level which the procedure routes on.
- The existing `plan-lifecycle.sh` hook handles auto-archival on terminal-Status transitions. The new procedure produces a Status flip; archival fires automatically via the existing hook.
- The closure-validator (today's GAP-16 ship) still fires during the transition. The procedure produces evidence that satisfies the validator's checks. After Tranche F retires it, the procedure runs even faster.

## Edge Cases

- **Plan has tasks of mixed verification tiers.** Procedure handles each task per its declared tier; routing logic exists in plan-edit-validator (Tranche D) and the procedure references the same convention.
- **A mechanical check fails mid-procedure.** Block by default; clear stderr naming the failure; `--force` flag bypasses with audit log. Per E.3.
- **The plan's task-verifier evidence is already present from prior work.** Procedure recognizes existing structured evidence and doesn't re-run; idempotent.
- **The user wants to skip auto-push (review locally first).** `--no-push` flag commits only; user pushes manually.
- **Closing this very plan (Task 7 acceptance test) succeeds.** Validates the procedure end-to-end. Failure here means Tranche E hasn't shipped correctly.

## Acceptance Scenarios

(plan is acceptance-exempt — but Task 7 IS itself an acceptance test by closing this very plan)

## Out-of-scope scenarios

(none)

## Testing Strategy

`--self-test` flag exercises 10 scenarios per Task 2. Plus the live acceptance test (Task 7) of closing this very plan via the new procedure.

## Walking Skeleton

Tasks 1+2 ship the script + self-test as a self-contained unit. Task 3 wraps it as the slash command. Tasks 4-6 sync and integrate. Task 7 is the live acceptance test that proves it works.

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept
S2 (Existing-Code-Claim Verification): swept — Tranche B + D substrates verified shipped; plan-lifecycle.sh exists and handles archival
S3 (Cross-Section Consistency): swept
S4 (Numeric-Parameter Sweep): 10 self-test scenarios consistent
S5 (Scope-vs-Analysis Check): swept

## Definition of Done

- [ ] All 8 tasks shipped + synced
- [ ] `--self-test` PASS 10/10
- [ ] **Acceptance test: this very plan closes successfully via the new procedure (~target < 30 sec)**
- [ ] Parent plan Task 5 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition (via the new procedure itself!)

## Evidence Log

(populated at closure — partly by the new procedure itself)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T06:48:35Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md` (slug: `architecture-simplification-tranche-e-deterministic-close-plan`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/scripts/close-plan.sh`
- `adapters/claude-code/skills/close-plan.md`
- `docs/harness-architecture.md`
- `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan-evidence.md`
- `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/scripts/close-plan.sh`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03f2a8e chore(closure): close 8 plans via close-plan.sh — Tranche 1.5 substantively complete
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
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
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
5870575 feat(hook): A5 — deferral-counter Stop hook
5938a69 feat(tranche-e): deterministic close-plan procedure
5c8e3e4 feat(harness): no-test-skip gate + deploy-to-production rule
5fdc217 feat(harness): meta-question skill library (why-slipped, find-bugs, verbose-plan, harness-lesson)
60ce18c feat(hooks): pre-push-test-gate + record-test-pass helper
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
