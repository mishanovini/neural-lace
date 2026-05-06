# Plan: Tranche C — Work-Shape Library

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
acceptance-exempt-reason: Sub-tranche of Tranche 1.5. Authors a catalog of canonical task shapes; verification is by mechanical-compliance check that each shape has the required schema and a worked example.

## Goal

Catalog the recurring task classes in harness-dev work — the engineering catalog Build Doctrine Principle 2 calls for, applied to the harness itself. Each shape provides a canonical structure that builders fill in; mechanical checks verify shape compliance; LLM judgment escalates only when work doesn't fit any existing shape.

Per decision queue C.1: **Seed 6 shapes initially** — `build-hook`, `build-rule`, `build-agent`, `author-ADR`, `write-self-test`, `doc-migration`. Per C.2: **store at `adapters/claude-code/work-shapes/`**. Per C.3: **Markdown with YAML frontmatter**. Per C.4: **inline regex/grep checks for v1**.

## Scope

- IN: New `adapters/claude-code/work-shapes/` directory with 6 shape files plus a README. Each shape: YAML frontmatter declaring required-files glob, mechanical-check regex/grep patterns, when-to-use prose, worked example. Sync to `~/.claude/work-shapes/`. Cross-reference from `adapters/claude-code/rules/orchestrator-pattern.md` and the plan template. New rule `adapters/claude-code/rules/work-shapes.md` documenting the substrate.
- OUT: Mechanical compliance check enforcement at commit time (defer to Tranche D's risk-tier system). Additional shape categories beyond the 6. AST-based check format (defer per C.4 recommendation). Migration of existing harness work to the new shape pattern.

## Tasks

- [ ] 1. Create `adapters/claude-code/work-shapes/` directory with `README.md` (~30 lines: purpose, format, how-to-use, cross-reference to rule). Verification: mechanical (file exists, README contains canonical headings).
- [ ] 2. Author `adapters/claude-code/work-shapes/build-hook.md`. YAML frontmatter: `category: hook`, `required_files: [adapters/claude-code/hooks/<name>.sh, ~/.claude/hooks/<name>.sh, settings.json.template wiring]`, `mechanical_checks: [self-test exits 0, byte-identical sync, settings entry exists]`, `worked_example: harness-hygiene-scan.sh`. Body: when-to-use, structure, common pitfalls. Verification: mechanical.
- [ ] 3. Author `adapters/claude-code/work-shapes/build-rule.md`. Similar structure. Worked example: `harness-hygiene.md`. Verification: mechanical.
- [ ] 4. Author `adapters/claude-code/work-shapes/build-agent.md`. Worked example: `task-verifier.md`. Verification: mechanical.
- [ ] 5. Author `adapters/claude-code/work-shapes/author-ADR.md`. YAML: `category: decision`, `required_files: [docs/decisions/NNN-<slug>.md, docs/DECISIONS.md row]`, `mechanical_checks: [decisions-index-gate atomicity, NNN unique, frontmatter complete]`, `worked_example: 026-harness-catches-up-to-doctrine.md`. Verification: mechanical.
- [ ] 6. Author `adapters/claude-code/work-shapes/write-self-test.md`. Worked example: `harness-hygiene-scan.sh --self-test` block. Verification: mechanical.
- [ ] 7. Author `adapters/claude-code/work-shapes/doc-migration.md`. YAML: `category: migration`, `required_files: [<source-path>, <dest-path> in NL]`, `mechanical_checks: [diff -r byte-identical OR explicit-anonymization-only]`, `worked_example: build-doctrine Tranche 0b migration`. Verification: mechanical.
- [ ] 8. Author `adapters/claude-code/rules/work-shapes.md` (~80-120 lines). Documents: when to use a shape, how to add a new shape, mechanical-compliance check pattern, escalation path when work doesn't fit a shape, cross-references to Build Doctrine Principle 2 (engineering catalog). Verification: mechanical.
- [ ] 9. Sync to `~/.claude/work-shapes/` and `~/.claude/rules/work-shapes.md`. Verify byte-identical via diff.
- [ ] 10. Update `adapters/claude-code/rules/orchestrator-pattern.md` with a new section: "Use a work-shape when one applies. List the 6 v1 shapes; reference the library directory. Sync to `~/.claude/`. Verification: mechanical.
- [ ] 11. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with one new row: "Work-shape library" → `work-shapes/` + `rules/work-shapes.md` + cross-reference Build Doctrine Principle 2.
- [ ] 12. Update `docs/harness-architecture.md` with a new "Work-shapes" section listing the 6 v1 shapes.
- [ ] 13. Flip parent plan Task 6 to `[x]` at completion.

## Files to Modify/Create

- `adapters/claude-code/work-shapes/` directory + 7 files (1 README + 6 shapes)
- `adapters/claude-code/rules/work-shapes.md` — NEW
- `adapters/claude-code/rules/orchestrator-pattern.md` — MODIFY (~10 lines)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row)
- `~/.claude/work-shapes/` mirror
- `~/.claude/rules/work-shapes.md` mirror
- `~/.claude/rules/orchestrator-pattern.md` mirror update
- `docs/harness-architecture.md` — MODIFY (new section)
- `docs/plans/architecture-simplification.md` — MODIFY (Task 6 flip at completion)
- `docs/plans/architecture-simplification-tranche-c-work-shape-library.md` — this plan
- `docs/plans/architecture-simplification-tranche-c-work-shape-library-evidence.md` — companion evidence

## In-flight scope updates

(none yet)

## Assumptions

- Per queued-tranche-1.5.md decisions C.1-C.4, recommendations apply: 6 shapes, `work-shapes/` location, MD+YAML frontmatter, regex-based checks. User has not overridden as of this plan's creation.
- Worked examples cite existing harness files; those files are stable and well-formed.
- Shape compliance checks run as bash commands (regex/grep patterns) for v1; AST-based escalation deferred.

## Edge Cases

- **A real piece of work doesn't fit any of the 6 shapes.** Expected for novel work. Documentation in the rule says: escalate via the existing plan-template's `## Walking Skeleton` discipline; propose a new shape if the pattern recurs.
- **Two shapes overlap (e.g., a task is both `build-hook` and `write-self-test`).** Hooks include self-tests; the build-hook shape composes the write-self-test shape inline. Documented in the build-hook worked example.
- **Mechanical check has a false positive.** Override via task description with rationale (e.g., "Verification: full — see <reason>").

## Acceptance Scenarios

(plan is acceptance-exempt)

## Out-of-scope scenarios

(none)

## Testing Strategy

Mechanical verification per task: shape file exists, frontmatter parses as YAML, has required keys (category, required_files, mechanical_checks, worked_example). Bash one-liner for each.

## Walking Skeleton

Tasks 1+2 ship the directory + first shape; Tasks 3-7 layer in remaining shapes; Task 8 documents the rule; Tasks 9-12 sync and integrate.

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept
S2 (Existing-Code-Claim Verification): swept — worked-example files exist (harness-hygiene-scan.sh, harness-hygiene.md, task-verifier.md, 026-harness-catches-up-to-doctrine.md)
S3 (Cross-Section Consistency): swept
S4 (Numeric-Parameter Sweep): 6 shapes consistent across Goal/Scope/Tasks
S5 (Scope-vs-Analysis Check): swept

## Definition of Done

- [ ] All 12 tasks shipped + synced
- [ ] Mechanical verification PASS per task
- [ ] Parent plan Task 6 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition

## Evidence Log

(populated at closure)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:25:47Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-c-work-shape-library.md` (slug: `architecture-simplification-tranche-c-work-shape-library`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/rules/orchestrator-pattern.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/rules/work-shapes.md`
- `adapters/claude-code/work-shapes/`
- `docs/harness-architecture.md`
- `docs/plans/architecture-simplification-tranche-c-work-shape-library-evidence.md`
- `docs/plans/architecture-simplification-tranche-c-work-shape-library.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/rules/orchestrator-pattern.md`
- `~/.claude/rules/work-shapes.md`
- `~/.claude/work-shapes/`

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
3f2c6c4 docs(orchestrator): add anti-pattern #7 — --dry-run-first for install-class work
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
4d94940 docs(plan-mode): Execution Mode: agent-team value + cross-references (plan task 12)
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
5870575 feat(hook): A5 — deferral-counter Stop hook
5938a69 feat(tranche-e): deterministic close-plan procedure
5c8e3e4 feat(harness): no-test-skip gate + deploy-to-production rule
5fdc217 feat(harness): meta-question skill library (why-slipped, find-bugs, verbose-plan, harness-lesson)
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
