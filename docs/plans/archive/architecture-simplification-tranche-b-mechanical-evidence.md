# Plan: Tranche B — Mechanical Evidence Substrate

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
acceptance-exempt-reason: Sub-tranche of Tranche 1.5 (architecture-simplification). Replaces prose evidence-block convention with a structured-artifact substrate. Verification is by the new schema validating against itself + helper scripts running their self-tests + the existing plan-edit-validator.sh accepting the new format alongside the old.

## Goal

Replace prose evidence blocks with structured-artifact evidence — directly addressing Principle 7 of the Build Doctrine ("Visibility lives in artifacts, not narration"). Today, evidence is paragraphs of prose that an LLM has to read and judge; the doctrine specifies it should be machine-written human-readable artifacts (test output, diff stats, commit-SHA + files-modified linkage, schema-validation results, file-existence checks).

The new substrate makes most verification mechanical:
- A bash check determines whether a task's evidence is sufficient
- Prose evidence becomes the escalation path for genuinely-novel work
- Closure cost drops because the closure-validator can check structured fields, not parse prose

This sub-tranche ships the substrate. Tranches D (risk-tiered verification) and E (deterministic close-plan) consume it.

## Scope

- IN: New JSON schema for evidence files (`adapters/claude-code/schemas/evidence.schema.json`). New helper script (`adapters/claude-code/scripts/write-evidence.sh`) that captures mechanical evidence into the canonical format from a single invocation. Documentation rule (`adapters/claude-code/rules/mechanical-evidence.md`) explaining the substrate. Update `plan-edit-validator.sh` to accept either old prose evidence (transition) OR new structured evidence. Update `task-verifier.md` agent prompt to write structured evidence when applicable. Sync to `~/.claude/`.
- OUT: Migration of existing prose evidence files to the new format (transition co-existence is enough; older plans stay prose-evidence). New verifier mandate (Tranche A's job). Risk-tiering of evidence (Tranche D's job). Closure procedure consuming the new evidence (Tranche E's job). Backward-incompat changes that would break existing closed plans.

## Tasks

- [ ] 1. **Author `adapters/claude-code/schemas/evidence.schema.json`** — JSON Schema specifying the canonical structured evidence shape. Required fields: `task_id`, `verdict` (PASS|FAIL|INCOMPLETE), `commit_sha`, `files_modified` (array), `mechanical_checks` (object — type-check pass, lint pass, test pass, schema-valid, etc., each as boolean OR detail-string), `timestamp` (ISO 8601). Optional fields: `runtime_evidence` (cmd + output capture for runtime-feature tasks), `prose_supplement` (escalation path for novel work). Self-validating (schema validates against its own meta-schema). Verification: mechanical (json-schema-validate on the schema itself).
- [ ] 2. **Author `adapters/claude-code/scripts/write-evidence.sh`** — bash helper that takes a task ID + a list of mechanical checks to run, runs them, captures outcomes, and writes the canonical structured evidence to a target file. Subcommands: `write-evidence.sh capture --task <id> --plan <path> [--check typecheck] [--check lint] [--check test:<name>] [--check files-in-commit] [--check schema-valid:<schema>]`. Exits 0 if all checks pass + writes evidence; exits 1 if any check fails + writes evidence with `verdict: FAIL`. Self-test with 8+ scenarios. Verification: mechanical (`--self-test` exits 0).
- [ ] 3. **Author `adapters/claude-code/rules/mechanical-evidence.md`** — documents the substrate. Specifies: when to use mechanical evidence (default for `Verification: mechanical` tasks once Tranche D ships), when to use prose evidence (escalation path for novel/judgment tasks), how the helper script integrates with `task-verifier`, how the schema is enforced. Verification: mechanical (file exists, contains canonical headings).
- [ ] 4. **Update `adapters/claude-code/hooks/plan-edit-validator.sh`** to recognize structured evidence files alongside prose evidence files. The validator currently checks for an evidence file's mtime + presence of the task ID. Extension: ALSO recognize structured `.evidence.json` companion files (in addition to prose `-evidence.md` files); freshness check applies to either; substance check verifies the JSON parses and contains the expected `task_id`. Backward compatible: prose-evidence plans continue to validate. Verification: mechanical (`--self-test` regression coverage extended).
- [ ] 5. **Update `adapters/claude-code/agents/task-verifier.md`** to use the helper script when appropriate. Add a section: "When the task's verification level is `mechanical` (per Tranche D) OR the work is purely structural (file edits, hook updates, prompt updates), prefer `write-evidence.sh capture` over writing prose evidence. The helper captures mechanical-check outcomes deterministically; the agent's role becomes invocation + outcome interpretation, not evidence authorship." Verification: mechanical (file contains the new section).
- [ ] 6. **Sync to `~/.claude/`** — copy schemas/, scripts/, rules/, hooks/, agents/ files to `~/.claude/` mirrors. Run all self-tests against both copies. Verify byte-identical via the diff loop.
- [ ] 7. **Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map** with one new row: "Mechanical evidence substrate" → schema + write-evidence.sh + plan-edit-validator extension. Cross-reference Principle 7 of the Build Doctrine.
- [ ] 8. **Update `docs/plans/architecture-simplification.md` to flip Task 3 to `[x]`** at completion.

## Files to Modify/Create

- `adapters/claude-code/schemas/evidence.schema.json` — NEW (~50-80 lines JSON Schema)
- `adapters/claude-code/scripts/write-evidence.sh` — NEW (~200-300 lines including self-test)
- `adapters/claude-code/rules/mechanical-evidence.md` — NEW (~80-120 lines)
- `adapters/claude-code/hooks/plan-edit-validator.sh` — MODIFY (extend evidence-recognition to include `.evidence.json`; ~30-50 added lines including self-test scenarios)
- `adapters/claude-code/agents/task-verifier.md` — MODIFY (add ~10-15 lines on helper-script preference)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row added)
- `~/.claude/schemas/evidence.schema.json`, `~/.claude/scripts/write-evidence.sh`, `~/.claude/rules/mechanical-evidence.md`, `~/.claude/hooks/plan-edit-validator.sh`, `~/.claude/agents/task-verifier.md` — sync mirrors
- `docs/plans/architecture-simplification.md` — MODIFY (Task 3 checkbox flip at completion)
- `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md` — this plan
- `docs/plans/architecture-simplification-tranche-b-mechanical-evidence-evidence.md` — companion evidence file (NEW)
- `docs/harness-architecture.md` — MODIFY (add row(s) for the new schema + script + rule per docs-freshness-gate)

## In-flight scope updates

(none yet)

## Assumptions

- JSON Schema is the right tool for evidence-file format specification (vs YAML schema, vs custom format). Standard, validatable via `ajv`/`jsonschema`/etc., self-documenting. Decision-locked here unless deep-objection surfaces during build.
- The plan-edit-validator's existing mtime + task-ID checks generalize cleanly to a new file extension. Verified by reading the hook's existing logic — it checks for evidence-file presence, not specifically for prose format.
- Backward compatibility is required: existing closed plans have prose evidence; the new substrate must NOT invalidate them. Verified by the validator's "either format passes" approach.
- The helper script (`write-evidence.sh`) does NOT replace `task-verifier` agent. It's a tool the agent uses (or any orchestrator uses) to capture structured evidence. The agent still decides the verdict; the script captures the mechanical-check inputs.

## Edge Cases

- **Mechanical checks return ambiguous results** (e.g., test partially passes, partially times out). The helper script records detail-strings; the verdict is FAIL unless ALL named checks PASS. Escalation: prose-supplement field for orchestrator narrative.
- **Plan has tasks of mixed types** (some mechanical, some novel). Each task's evidence file independent; structured for mechanical, prose for novel. Plan-edit-validator handles both per task.
- **Helper script invoked outside a plan context** (debug, exploration). Allowed; produces a standalone evidence file that's not associated with a plan. No validator concern.
- **Schema evolves over time.** Versioned via a `schema_version` field in evidence files; validator accepts current + N-1 versions for graceful migration.

## Acceptance Scenarios

(plan is acceptance-exempt — see header)

## Out-of-scope scenarios

(none)

## Testing Strategy

Three mechanical layers:
1. JSON Schema validates against its own meta-schema (sanity check)
2. `write-evidence.sh --self-test` runs ~8 scenarios covering: capture-with-all-checks-pass, capture-with-failing-check, capture-with-runtime-evidence, capture-without-files-modified, capture-with-prose-supplement, schema-rejection-on-invalid-shape, backward-compat with prose-only existing files, helper-script-error-handling (missing args, malformed task ID, etc.)
3. `plan-edit-validator.sh --self-test` regression coverage extended with: mechanical-evidence-recognized, prose-evidence-still-recognized, mixed-format-plan-validates

## Walking Skeleton

The schema + helper script ship first as a self-contained unit (Tasks 1+2). Plan-edit-validator extension (Task 4) and task-verifier prompt update (Task 5) consume them. Sync (Task 6) and enforcement-map (Task 7) close the loop.

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every new file/edit is cited at task entry points
S2 (Existing-Code-Claim Verification): swept — plan-edit-validator's existing logic verified by reading the hook this session
S3 (Cross-Section Consistency): swept — Goal, Scope, Tasks, Files-to-Modify all agree
S4 (Numeric-Parameter Sweep): swept — schema field count, scenario count consistent
S5 (Scope-vs-Analysis Check): swept — every "Author/Update" verb maps to a Files-to-Modify entry; OUT clause excludes the consumer tranches (D, E)

## Definition of Done

- [ ] All 8 tasks shipped + synced to `~/.claude/` mirrors
- [ ] Schema self-validates; helper-script self-test PASS; plan-edit-validator self-test PASS (extended scenarios)
- [ ] Backward compat verified: a synthetic plan with prose evidence still validates
- [ ] Parent plan Task 3 checkbox flipped
- [ ] Status: ACTIVE → COMPLETED transition (under gate-relaxation: closure-validator advisory)

## Evidence Log

(populated by lightweight-evidence pattern at closure)

## Completion Report

_Generated by close-plan.sh on 2026-05-06T04:25:38Z._

### 1. Implementation Summary

Plan: `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md` (slug: `architecture-simplification-tranche-b-mechanical-evidence`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/agents/task-verifier.md`
- `adapters/claude-code/hooks/plan-edit-validator.sh`
- `adapters/claude-code/rules/mechanical-evidence.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/schemas/evidence.schema.json`
- `adapters/claude-code/scripts/write-evidence.sh`
- `docs/harness-architecture.md`
- `docs/plans/architecture-simplification-tranche-b-mechanical-evidence-evidence.md`
- `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md`
- `docs/plans/architecture-simplification.md`
- `~/.claude/schemas/evidence.schema.json`

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
70b8de9 plan(1.5/A+B): author Tranches A and B child plans + flip Task 1 (gate-relaxation policy already shipped)
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
