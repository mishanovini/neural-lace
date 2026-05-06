# Plan: Tranche G — Calibration Loop Bootstrap

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: dialogue-only
frozen: true
prd-ref: docs/plans/architecture-simplification.md
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Sub-tranche of Tranche 1.5. Bootstraps the calibration loop without telemetry — manual entry skill + structured format + roll-up via /harness-review. Verification is by self-test on the new skill.

## Goal

Implement Build Doctrine Principle 9 (Documents are living; updates propagate on trigger) for the harness's own learning loop. Every observed builder/reviewer failure produces a calibration entry; entries roll up periodically via the `/harness-review` skill. This is the manual bootstrap of the Knowledge Integrator role until telemetry lands (HARNESS-GAP-11, gated on 2026-08).

Per queued-tranche-1.5.md G.1: **calibration entries at `.claude/state/calibration/<agent-name>.md` (gitignored, operational)**. G.2: **lightweight skill `/calibrate <agent> <observation>` for structured manual entry, mechanize roll-up post-telemetry**.

## Scope

- IN: New skill `adapters/claude-code/skills/calibrate.md` capturing per-agent observations into structured entries. State directory `.claude/state/calibration/` (gitignored). Update `/harness-review` skill (or its underlying check script) with a roll-up section that reads calibration entries and surfaces patterns. New rule `adapters/claude-code/rules/calibration-loop.md` documenting the discipline. Sync to `~/.claude/`.
- OUT: Telemetry-driven calibration (HARNESS-GAP-11, gated). Auto-application of calibration findings to agent prompts (manual review-and-apply for now). Migration of historical observed failures to calibration entries.

## Tasks

- [ ] 1. Author `adapters/claude-code/skills/calibrate.md` (~80-120 lines). Skill invocation: `/calibrate <agent-name> <observation-class> <details>`. Captures structured entry to `.claude/state/calibration/<agent-name>.md` (creates if missing). Entry format: timestamp, observation-class (e.g., shortcut, hallucination, pass-by-default), details, suggested mitigation. Verification: mechanical (file exists, contains canonical sections).
- [ ] 2. Author `adapters/claude-code/rules/calibration-loop.md` (~80-120 lines). Documents: when to invoke `/calibrate`, observation classes, what becomes a prompt-update, what becomes a work-shape-library extension, what defers to telemetry. Cross-reference Build Doctrine Principle 9 + ADR 026 ("harness catches up to doctrine") + Counter-Incentive Discipline. Verification: mechanical.
- [ ] 3. Update `adapters/claude-code/skills/harness-review.md` (or the underlying check script if check-driven) with a "Calibration roll-up" check. Reads `.claude/state/calibration/*.md` files; surfaces top-3-most-frequent observation classes per agent. Verification: mechanical.
- [ ] 4. Sync to `~/.claude/skills/` and `~/.claude/rules/`. Verify byte-identical.
- [ ] 5. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with one new row: "Calibration loop bootstrap" → calibrate skill + harness-review extension + calibration-loop rule. Cross-reference Build Doctrine Principle 9 + Knowledge Integrator role.
- [ ] 6. Update `docs/harness-architecture.md` with a section on the calibration loop (manual bootstrap; telemetry-driven mechanization deferred).
- [ ] 7. Flip parent plan Task 7 to `[x]` at completion.

## Files to Modify/Create

- `adapters/claude-code/skills/calibrate.md` — NEW
- `adapters/claude-code/rules/calibration-loop.md` — NEW
- `adapters/claude-code/skills/harness-review.md` — MODIFY (add roll-up check)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row)
- `~/.claude/skills/calibrate.md`, `~/.claude/rules/calibration-loop.md`, `~/.claude/skills/harness-review.md` — sync mirrors
- `docs/harness-architecture.md` — MODIFY
- `docs/plans/architecture-simplification.md` — Task 7 flip
- `docs/plans/architecture-simplification-tranche-g-calibration-loop.md` — this plan
- `docs/plans/architecture-simplification-tranche-g-calibration-loop-evidence.md` — companion evidence

## In-flight scope updates

(none yet)

## Assumptions

- Per queued-tranche-1.5.md G.1-G.2, recommendations apply.
- `/harness-review` skill exists and has a check-extension pattern. Verified by inspection — skill file at `adapters/claude-code/skills/harness-review.md`.
- `.claude/state/` directory is the canonical operational-state location (used by other hooks: bug-persistence-gate, acceptance-gate, etc.); gitignored.
- Skill format pattern is well-defined; new skills follow the existing structure.

## Edge Cases

- **Multiple sessions invoke `/calibrate` simultaneously on the same agent.** Append-only file; each entry timestamped; race tolerable.
- **Calibration entries grow unbounded over time.** Roll-up check reads all; if entry count exceeds N (default 100) per agent, oldest entries get archived to a sub-directory. Defer the archival logic to a follow-up if the volume grows.
- **A user writes a calibration entry that looks like a real bug report.** The discipline says calibration is structured-with-class; a free-form bug report goes to backlog/findings, not calibration. Documented in the rule.

## Acceptance Scenarios

(plan is acceptance-exempt)

## Out-of-scope scenarios

(none)

## Testing Strategy

Mechanical verification per task. Skill self-test scenarios cover: invocation creates entry, repeated invocation appends, missing args fail cleanly, invalid agent-name fails cleanly.

## Walking Skeleton

Task 1 (skill) ships first as the entry point; Task 2 (rule) documents discipline; Task 3 (harness-review extension) consumes the entries; Tasks 4-6 sync and integrate.

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept
S2 (Existing-Code-Claim Verification): swept — `/harness-review` skill verified existing
S3 (Cross-Section Consistency): swept
S4 (Numeric-Parameter Sweep): 100-entry roll-up threshold consistent
S5 (Scope-vs-Analysis Check): swept

## Definition of Done

- [ ] All 7 tasks shipped + synced
- [ ] Skill self-test PASS
- [ ] Parent plan Task 7 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition

## Evidence Log

(populated at closure)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:26:01Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-g-calibration-loop.md` (slug: `architecture-simplification-tranche-g-calibration-loop`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/rules/calibration-loop.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/skills/calibrate.md`
- `adapters/claude-code/skills/harness-review.md`
- `docs/harness-architecture.md`
- `docs/plans/architecture-simplification-tranche-g-calibration-loop-evidence.md`
- `docs/plans/architecture-simplification-tranche-g-calibration-loop.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/skills/calibrate.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
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
6e4672c feat(skills): harness-review full-tree hygiene audit check (GAP-13 Task 3 / Layer 3)
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
