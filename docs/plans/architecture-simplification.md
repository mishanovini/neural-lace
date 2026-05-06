# Plan: Architecture Simplification — Tranche 1.5 of the Build Doctrine Roadmap

Status: ACTIVE
Execution Mode: orchestrator
Mode: design
tier: 3
rung: 3
architecture: dialogue-only
frozen: true
prd-ref: docs/build-doctrine-roadmap.md
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; structural redesign of the harness's own enforcement substrate to align with the Build Doctrine. No product-user surface; verification is by the deterministic close-plan procedure (Tranche E) successfully closing this plan itself.

## Goal

Apply the existing Build Doctrine (`build-doctrine/doctrine/`) to the harness itself. Two months of reactive failsafe stacking has produced a verification stack that costs more than the work it gates (~13 sub-agent dispatches + ~65K tokens to close a 7-task plan). The doctrine already contains the architecture that would have prevented this; the harness has not been built TO the doctrine. This plan executes the catch-up.

Outcome: closing a typical harness-dev plan becomes a 4-second deterministic script with no agent dispatches. Builders pick from a work-shape library and fill in templated structures. Evidence is mechanical artifacts (test output, diff stats, commit SHAs), not prose. Verification proportionate to risk — `Verification: mechanical | full | contract` per task. The plan-closure-validator shipped 2026-05-05 retires.

After this plan ships, every subsequent harness change becomes a doctrine-applying exercise. Future failures get incentive or structural fixes — not new failsafes — per ADR 026.

## Scope

- IN: Seven sub-tranches A through G covering incentive redesign at the prompt layer (A), mechanical evidence substrate (B), work-shape library (C), risk-tiered verification (D), deterministic close-plan procedure (E), failsafe audit for retirement (F), calibration loop bootstrap (G). Each sub-tranche is a child plan dispatched from this parent plan. Selective gate-relaxation policy for work landing under this plan (specified below). Updates to `~/.claude/CLAUDE.md`, `~/.claude/rules/orchestrator-pattern.md`, `~/.claude/rules/planning.md`, key agent prompts, the plan template, the closure path mechanism, the enforcement map, and supporting infrastructure.
- OUT: Doctrine extensions (N1, N2, N3 from the integration review) — those land separately via the doctrine's knowledge-integration ritual; this plan does not block on them. Tranches 2-7 of the Build Doctrine roadmap (template schemas, template content, project pilot, knowledge-integration ritual authoring, orchestrator code, second-pass C-mechanisms) — those are sequenced AFTER this plan completes. Modifications to product-application code in any downstream project. New product features. Anything in the existing 50-row enforcement map other than retirement audit (Tranche F) — no new gates land during this plan.

## Tasks

The plan is organized into seven sub-tranches, each becoming its own child plan when started. The parent plan's tasks track sub-tranche initiation, completion, and integration. Sub-tranches run in parallel where possible per the orchestrator-pattern.

- [x] 1. **Author selective gate-relaxation policy.** A sibling document (`docs/plans/architecture-simplification-gate-relaxation.md` or a section within this plan) specifying which gates exempt work landing under `docs/plans/architecture-simplification*` slugs and how the exemption is keyed (path-prefix matching on plan slugs). Specifies which gates STAY ON (load-bearing — pre-commit-tdd-gate, plan-edit-validator, pre-stop-verifier, scope-enforcement-gate, credential scanners) and which TEMPORARILY EXEMPT for this plan's work specifically (closure-validator, full-treatment task-verifier mandate where `Verification: mechanical` would apply). Logged so audit-trail is intact.
- [x] 2. **Dispatch sub-tranche A (incentive redesign).** Author `docs/plans/architecture-simplification-tranche-a-incentive-redesign.md`. Scope: update `~/.claude/CLAUDE.md`, `~/.claude/rules/orchestrator-pattern.md`, `~/.claude/rules/planning.md`, `~/.claude/agents/{plan-phase-builder,task-verifier,code-reviewer,end-user-advocate}.md` to reframe "done" definitions per the discovery's incentive-design framing. Extend Counter-Incentive Discipline sections from "warn against bias" to "redesign reward structure." ~3-5 days; can run in parallel with Task 3.
- [x] 3. **Dispatch sub-tranche B (mechanical evidence substrate).** Author `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md`. Scope: replace prose evidence blocks with structured-artifact evidence (test pass output captured verbatim, diff-stats summary, commit-SHA + files-modified linkage). Schema for evidence files. Bash-level evidence-write helpers. Backward compatibility with existing evidence blocks during transition. ~5-7 days; can run in parallel with Task 2.
- [x] 4. **Dispatch sub-tranche D (risk-tiered verification).** Author `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md`. Scope: plan-template extended with `Verification: mechanical | full | contract` field per task. Rewrite task-verifier mandate: only `Verification: full` invokes the agent; `Verification: mechanical` runs a bash check; `Verification: contract` runs schema or golden-file comparison. Update plan-edit-validator to honor per-task verification level. ~3-5 days; depends on Task 2 (incentive redesign clarifies the mandate) and partial Task 5 (work-shape library for the mechanical paths).
- [x] 5. **Dispatch sub-tranche E (deterministic close-plan procedure).** Author `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md`. Scope: rewrite `/close-plan` skill (shipped today, currently a coordinator wrapping the heavy stack) as a deterministic script that batches all closure work into mechanical steps. No agent dispatches in the closure path. Single tool invocation runs to completion or fails at a specific step. ~3-5 days; depends on Tasks 3+4. **This sub-tranche's acceptance test is closing this very plan — i.e., Tranche 1.5's own closure runs through Tranche E's procedure once it ships.**
- [x] 6. **Dispatch sub-tranche C (work-shape library).** Author `docs/plans/architecture-simplification-tranche-c-work-shape-library.md`. Scope: catalog the recurring task classes in harness-dev (build hook, build rule, migrate doc, add agent, author ADR, write self-test, etc.). For each, author a canonical shape with file structure, test shape, stderr format, self-test pattern, worked example, mechanical shape-compliance check. ~7-10 days; can run in parallel with Tasks 4+5+7 (not on the critical path for closure-cost reduction).
- [x] 7. **Dispatch sub-tranche G (calibration loop bootstrap).** Author `docs/plans/architecture-simplification-tranche-g-calibration-loop.md`. Scope: even before telemetry lands, manual calibration discipline — every builder failure produces a work-shape-library update, a regression test addition, a defensive prompt extension. Document this as a discipline; mechanize as telemetry comes online. ~5-10 days; can run in parallel with most other tranches.
- [ ] 8. **Dispatch sub-tranche F (failsafe audit for retirement).** Author `docs/plans/architecture-simplification-tranche-f-failsafe-audit.md`. Scope: walk every gate in the enforcement map (50 rows in `vaporware-prevention.md`). Mark each as KEEP (still load-bearing after redesign), SCOPE-DOWN (subsumed by new mechanism but partial), RETIRE (redundant with new substrate). Execute the retirements. ~2-3 days; depends on Tasks 2+3+4+5 having landed (must know what the new structure looks like before retiring old gates).
- [ ] 9. **Update Build Doctrine roadmap with Tranche 1.5 progress.** Quick status row updated to ✅ DONE on plan completion. Recent Updates entry summarizes the redesign outcome with commit SHAs.
- [x] 10. **Authoring/integration of doctrine extensions N1, N2, N3.** Author `build-doctrine/doctrine/01-principles.md` extension capturing the "reactive enforcement compounding" anti-principle (N1). Extend `04-gates.md` with the "mechanical vs LLM-judgment" decision rubric (N2). Extend `08-project-bootstrapping.md` (or new doctrine doc) with "the harness is a project too" meta-loop section (N3). These are small extensions that land alongside or after the Tranche A-G work.
- [ ] 11. **Final integration: re-run the discovery's "what's the closure cost?" benchmark.** Close this plan via Tranche E's deterministic close-plan procedure. Capture the actual cost (target: 4 seconds, no agent dispatches). Compare to the pre-redesign baseline (~13 dispatches, ~65K tokens). Document as part of this plan's Completion Report.

## Files to Modify/Create

This is a Mode: design plan; the full file inventory lives in each sub-tranche's child plan. The parent plan only directly modifies:

- `docs/plans/architecture-simplification.md` — this plan file
- `docs/plans/architecture-simplification-evidence.md` — companion evidence file (created at first sub-tranche dispatch)
- `docs/plans/architecture-simplification-tranche-{a,b,c,d,e,f,g}-*.md` — 7 child plans (created on-demand at sub-tranche dispatch)
- `docs/plans/architecture-simplification-gate-relaxation.md` — selective gate-relaxation policy (Task 1)
- `docs/build-doctrine-roadmap.md` — Quick status row + Recent Updates entries (multiple touches across this plan's lifetime)
- `docs/decisions/026-harness-catches-up-to-doctrine.md` — already authored at this plan's creation; cross-referenced from sub-tranches
- `docs/DECISIONS.md` — index row added atomically with ADR 026 (per `decisions-index-gate.sh` atomicity)
- `docs/decisions/027-*.md` through `docs/decisions/0NN-*.md` — additional ADRs as sub-tranches surface decisions worth recording (each lands atomically with a DECISIONS.md row update)

## In-flight scope updates

- 2026-05-05: `docs/decisions/027-autonomous-decision-making-process.md` — NEW. Establishes the decision-making meta-process (pre-emptive queues + autonomous reversible proceed + ADR documentation + final-summary surfacing). Cross-cutting concern for this plan and beyond.
- 2026-05-05: `docs/decisions/queued-tranche-1.5.md` — NEW. Pre-emptively-surfaced decisions for Tranches C/D/E/F/G with options + tradeoffs + recommendations. User reviews asynchronously; orchestrator applies overrides as user answers, otherwise proceeds with recommendations on reversible decisions per ADR 027.
- 2026-05-05: `.gitignore` — MODIFY (one allow-pattern added: `!docs/decisions/queued-*.md`). Required for the queued-decisions file to be tracked alongside numbered ADRs.
- 2026-05-05: `build-doctrine/doctrine/01-principles.md` — MODIFY (Task 10 — three doctrine extensions N1, N2, N3 added as Anti-Principle 16 + Principle 17 + Principle 18). Originally listed in parent plan Task 10 but the file path wasn't in `## Files to Modify/Create`; surfaced and added here per scope-enforcement-gate.
- 2026-05-05: `docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md` — MODIFY (Status flip from `pending` to `decided` + Implementation log populated per ADR 027 Layer 3). Originating discovery for this entire arc; status update is part of the handoff.
- 2026-05-05: `SCRATCHPAD.md` — MODIFY (rewrite with current state of Tranche 1.5 + next-session pickup pointer; gitignored, not committed but updated for next-session continuity).
- 2026-05-05: `docs/backlog.md` — MODIFY (header v25 stamp summarizing Tranche 1.5 substantive completion).
- 2026-05-05: `docs/build-doctrine-roadmap.md` — MODIFY (Quick status row update + Recent updates entry per ADR 027 Layer 4 final-summary discipline).

## Assumptions

- The Build Doctrine at `build-doctrine/doctrine/` is the architectural source of truth (per ADR 026). Sub-tranches reference it directly; deviations require an in-flight scope update with rationale.
- The selective gate-relaxation policy (Task 1) ships first because it's a prerequisite for all subsequent sub-tranches — without it, the architecture-simplification work would itself be subject to the very overhead it's eliminating.
- Sub-tranches A and B are highest-leverage and ship first in parallel. D depends on A+B landing. E depends on B+D. F depends on A+B+D+E. C and G run in parallel with anything (off the critical path).
- ~14-22 days on the critical path (A+B → D → E → F) per the integration review's analysis. C and G add no critical-path time when parallelized.
- Each sub-tranche becomes a child plan on dispatch. Child plans use the standard plan template + the new patterns the redesign produces (eat-our-own-dogfood from sub-tranche A onwards).
- Closure of THIS plan is the acceptance test for Tranche E. If Tranche E's deterministic close-plan procedure cannot close this plan cleanly, Tranche E hasn't shipped.

## Edge Cases

- **Sub-tranche introduces a new failure mode mid-build.** The hard-freeze rule applies — no new failsafes. Resolution paths: (a) incentive redesign at the agent level, (b) structural fix in the work-shape library, (c) defer if the failure can be tolerated until Tranche F's audit. ADR 026 codifies "harness catches up to doctrine, not failsafe stacking."
- **A sub-tranche turns out to be larger than estimated.** Split it. A child plan that exceeds 40 hours is too large; sub-divide. The parent plan tracks completion of sub-tranches; sub-divisions are local to each child.
- **The closure-validator shipped 2026-05-05 fires on a sub-tranche's plan closure during the transition.** Expected. The closure-validator is tagged-for-retirement (Tranche F) but stays operational until then. Sub-tranches close through it via the same lightweight-evidence pattern this parent plan's parent used. After Tranche E lands, sub-tranches close through the new deterministic procedure.
- **Tranche F retires a gate that turns out to still be load-bearing.** Tranche F's audit must be reversible — every retirement is a single revert away. Surfaces during the next closure cycle if a retired gate's failure mode reappears.
- **A sub-tranche's child plan needs a doctrine clarification.** Surface as a discovery; either in-line clarify (if minor) or escalate to N1/N2/N3 doctrine-extension work.
- **User pivots priorities mid-tranche.** Status: ACTIVE → DEFERRED on this parent plan; sub-tranches inherit the deferral; resume conditions captured in the Decisions Log.

## Acceptance Scenarios

(plan is acceptance-exempt — see header)

## Out-of-scope scenarios

(none — acceptance-exempt)

## Testing Strategy

Each sub-tranche is responsible for its own testing strategy (in its child plan). The parent plan's testing strategy is integration-level: confirm that after Tranches A-E land, closing a synthetic harness-dev plan (or this plan itself) takes < 30 seconds and uses ≤ 1 agent dispatch. Compare against the pre-redesign baseline (13 dispatches, 65K tokens) and document the delta.

Final acceptance test: this plan's Status: ACTIVE → COMPLETED transition runs through the new deterministic close-plan procedure (Tranche E) without manual intervention. If it cannot, Tranche E has not shipped correctly.

## Walking Skeleton

The walking-skeleton form of this plan: Task 1 (gate-relaxation policy) lands first, immediately after this plan's creation, so subsequent sub-tranches benefit from the relaxation. Sub-tranche A (incentive redesign) and B (mechanical evidence) start in parallel as Task 2 and Task 3. From there, the critical path is A+B → D → E → F.

## Decisions Log

### Decision: Architecture-simplification as Tranche 1.5 of the Build Doctrine roadmap

- **Tier:** 3 (irreversible-in-spirit; commits the next ~14-45 days of harness-dev focus to structural redesign)
- **Status:** approved by user 2026-05-05
- **Chosen:** redesign as Tranche 1.5; hard freeze on new failsafes; sub-tranches A-G as the structure
- **Alternatives:** (a) continue stacking failsafes — rejected per ADR 026 trajectory analysis; (b) incentive-only redesign — rejected as necessary-not-sufficient; (c) structural-only redesign — rejected as fragile without incentive layer; (d) defer to a later phase of the roadmap — rejected per user's "everything is waiting on this" directive
- **Reasoning:** the discovery + integration review established that the doctrine already contains the answer; the harness has not been built to it. The redesign is the catch-up.
- **Checkpoint:** ADR 026 + this plan; both committed at the same time
- **To reverse:** flip Status to ABANDONED on this plan + revert ADR 026; the failsafe-stacking trajectory resumes by default. Cost of reversal scales with how much sub-tranche work has landed at the time.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every sub-tranche has its own task entry that names the child plan it produces
S2 (Existing-Code-Claim Verification): swept — verified Build Doctrine docs at `build-doctrine/doctrine/` are accessible; ADR 026 exists; closure-validator hook shipped 2026-05-05; ~50-row enforcement map exists at `vaporware-prevention.md`
S3 (Cross-Section Consistency): swept — Goal, Scope, Tasks, Files-to-Modify, Walking Skeleton all agree on the seven sub-tranche structure and the critical path
S4 (Numeric-Parameter Sweep): swept — ~14-22 days critical path, ~28-45 days total per integration review; 7 sub-tranches; ~50-row enforcement map; consistent across all references
S5 (Scope-vs-Analysis Check): swept — every "Dispatch / Author / Update" verb in Tasks is matched by a Files-to-Modify entry; OUT clause correctly excludes downstream-roadmap tranches and product-code work

## Definition of Done

- [ ] All 11 tasks task-verifier-flipped to `[x]` (or via Tranche E's deterministic procedure once it ships)
- [ ] All 7 sub-tranche child plans Status: COMPLETED + auto-archived
- [ ] Doctrine extensions N1, N2, N3 landed (Task 10)
- [ ] Final integration benchmark captured (Task 11): closure cost reduced from ~13 dispatches/65K tokens to ~1 dispatch/sub-1K tokens
- [ ] `docs/build-doctrine-roadmap.md` Quick status row for Tranche 1.5 = ✅ DONE
- [ ] Status: ACTIVE → COMPLETED transition closed via Tranche E's deterministic procedure (this is the acceptance test)
- [ ] Plan archived to `docs/plans/archive/`

## Evidence Log

(populated by sub-tranche closures and by Tranche E's procedure on final close)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:26:19Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification.md` (slug: `architecture-simplification`).

Files touched (per plan's `## Files to Modify/Create`):

- `docs/DECISIONS.md`
- `docs/build-doctrine-roadmap.md`
- `docs/decisions/026-harness-catches-up-to-doctrine.md`
- `docs/decisions/027-`
- `docs/plans/architecture-simplification-evidence.md`
- `docs/plans/architecture-simplification-gate-relaxation.md`
- `docs/plans/architecture-simplification-tranche-`
- `docs/plans/architecture-simplification.md`

Commits referencing these files:

```
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
4d18bf5 plan(parallel-tranches): start GAP-16 + Tranche 0b in parallel
549f70d feat(plan #4): Phase A complete — research-substitute investigation + Tier 2 decision record 011
566ffa6 feat(harness): D1-D5 educational re-do follow-through (Decision 014, GAP-12, gitignore fix)
6881712 fix(harness-hygiene): scrub codename leakage from committed decision/review files (Phase 1d-G Task 1)
6d30d7b docs: Decision 022 + audit-batch backlog cleanup (Phase 1d-E-2 Task 6)
70b8de9 plan(1.5/A+B): author Tranches A and B child plans + flip Task 1 (gate-relaxation policy already shipped)
70e5262 feat: capture-codify PR template + CI workflow + 7 decision records (#1)
73f841d feat(doctrine): N1 N2 N3 extensions to build-doctrine principles + parent plan Task 10 flip + scope update
7959436 feat(harness): Decision 020 + comprehension-template (Phase 1d-C-4 Task 1)
7f24907 feat(harness): definition-on-first-use enforcement — Decision 023 + rule + hook (Phase 1d-F Tasks 1+2)
8a5eca3 feat(autonomy): ADR 027 autonomous decision-making process + Tranche 1.5 decision queue
8ba7d46 feat(harness): land Decision 024 + close gap-14 backlog + archive plan
9239b02 feat(rules): default git push policy — auto-push (safe methods); customer-tier branching
951b073 plan(1.5): flip Tasks 4 (D), 6 (C), 7 (G) — all three sub-tranches shipped in parallel
9f9a8b1 feat(architecture): land ADR 026 + Tranche 1.5 plan + gate-relaxation policy
a4f55e6 feat(build-doctrine): Tranche 0b — migrate 8 doctrine docs into NL + scaffold templates dir
b68caf2 feat(1.5/E): Tranche E shipped — deterministic close-plan procedure (closure benchmark: 2.8 sec for synthetic 3-task plan vs 65K-token baseline)
c3494fc docs(roadmap): build-doctrine-roadmap — persistent tracker for end-to-end completion
d0c1757 docs(roadmap): mark GAP-16 + Tranche 0b code-landed; closure pending
dc97f33 feat(phase-1d-c-2): Task 1 — decisions 015-018 + discovery + PRD template + plan template extension
f993a83 feat(plan): agent-teams integration — Phase 5 starts
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
