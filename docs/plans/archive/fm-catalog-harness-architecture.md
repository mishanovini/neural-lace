# Plan: Bake the Failure-Mode catalog architecture into the harness (cross-project)

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal convention + doc + standing-rule work; the "user" is the maintainer running future investigation sessions. No product runtime surface; verification is structural (files exist, schema consistent, references resolve, diagnosis.md self-test green).
tier: 2
rung: 2
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

Make the Failure-Mode (FM) catalog a *universal* harness convention applied to every project (the harness repo itself and every downstream project that consumes it) rather than a per-project ad-hoc artifact. The originating pain: a ~12-hour investigation that an FM catalog consulted *first* would have collapsed to ~1 hour. The harness already has `docs/failure-modes.md` (single file, six-field schema, 23 entries) deeply wired into ~40 files; this plan reconciles the requested architecture with that existing substrate rather than forking it — keeping one canonical schema, extending it additively for the investigation-first use case, codifying it as a cross-project standard, adding the investigation-first grep reflex, and proposing harness auto-search at session spawn.

## Scope

- IN: cross-project convention doc; ADR recording the convention + the two additive optional schema fields (Discriminator, Recovery); additive extension of `docs/failure-modes.md` schema preamble + 5 new harness-level FM entries (FM-024..FM-028) from today's surfaced gaps; per-project template skeleton; harness auto-search *proposal* (design only, no hook shipped); investigation-first FM-grep reflex added to `rules/diagnosis.md` (canonical + `~/.claude` mirror); CLAUDE.md + bootstrap-doctrine pointer; `harness-architecture.md` + `DECISIONS.md` index updates; bootstrap tasks filed for the other downstream projects in the operator's workspace.
- OUT: creating a competing `docs/failure-modes/` directory or a second schema (explicitly rejected — would fork the canonical catalog and break the `harness-lesson`/`why-slipped`/PR-gate consumers); shipping the auto-search SessionStart hook (separate execution); migrating the 23 existing FM entries (the new fields are optional/additive — no migration needed); editing other projects' repos directly (only filing bootstrap tasks/docs for them).

## Tasks

- [ ] 1. Author ADR 033 recording: (a) `docs/failure-modes.md` single-file six-field schema is the canonical cross-project FM convention; (b) two additive *optional* schema fields — `Discriminator`, `Recovery` — for the investigation-first use case; (c) rejection of the forked-directory alternative. Add the `docs/DECISIONS.md` index row. — Verification: mechanical
- [ ] 2. Write `docs/conventions/failure-mode-catalogs.md` — the cross-project standard: location (`docs/failure-modes.md` per project), the unified eight-field schema (six existing + two new optional), INDEX-via-Symptom grep-ability, adoption procedure, the investigation-first reflex, relationship to the existing harness consumers. — Verification: mechanical
- [ ] 3. Extend `docs/failure-modes.md`: add the two optional fields to the Schema section (backward-compatible note), and append FM-024..FM-028 — harness-level FMs from today's surfaced gaps (conv-tree-state-gate over-fire on parallel peer-review dispatch; session-wrap freshness unsatisfiable from worktrees; automation-mode-gate config-visibility from pre-config-commit worktrees; BLOCKED-marker → orchestrator-stop propagation; broad-investigation-without-catalog-first). — Verification: mechanical
- [ ] 4. Create `docs/templates/project-failure-modes/` skeleton: `README.md` (how to adopt), `failure-modes.md` (starter single-file with the schema preamble + one worked FM-000 example), `FM-template.md` (single-entry copy-paste template). — Verification: mechanical
- [ ] 5. Write `docs/proposals/fm-catalog-auto-search-harness-integration.md` — design for a SessionStart hook that greps the project's `docs/failure-modes.md` Symptom fields for keywords in the session title/prompt and injects matching FM IDs + Recovery as context. Which hook fires, where, what it reads, false-positive control, opt-out. Proposal only. — Verification: mechanical
- [ ] 6. Add the investigation-first FM-grep reflex to `adapters/claude-code/rules/diagnosis.md` (and sync the `~/.claude/rules/diagnosis.md` mirror byte-identical). Add a pointer in `adapters/claude-code/CLAUDE.md` and in `build-doctrine/doctrine/08-project-bootstrapping.md`. Update `docs/harness-architecture.md`. — Verification: mechanical
- [ ] 7. File bootstrap tasks for the other downstream projects in the operator's workspace (spawn_task chips name the specific repos — chips are not committed harness files; the committed convention doc carries only the generic bootstrap procedure). — Verification: mechanical

## Files to Modify/Create

- `docs/decisions/033-failure-mode-catalog-cross-project-convention.md` — new ADR (Task 1)
- `docs/DECISIONS.md` — index row for ADR 033 (Task 1)
- `docs/conventions/failure-mode-catalogs.md` — new cross-project convention (Task 2)
- `docs/failure-modes.md` — schema preamble extension + FM-024..FM-028 (Task 3)
- `docs/templates/project-failure-modes/README.md` — adoption guide (Task 4)
- `docs/templates/project-failure-modes/failure-modes.md` — starter skeleton (Task 4)
- `docs/templates/project-failure-modes/FM-template.md` — single-entry template (Task 4)
- `docs/proposals/fm-catalog-auto-search-harness-integration.md` — auto-search design (Task 5)
- `adapters/claude-code/rules/diagnosis.md` — investigation-first FM-grep reflex (Task 6)
- `~/.claude/rules/diagnosis.md` — byte-identical mirror sync (Task 6)
- `adapters/claude-code/CLAUDE.md` — pointer to the convention (Task 6)
- `build-doctrine/doctrine/08-project-bootstrapping.md` — FM-catalog bootstrap step (Task 6)
- `docs/harness-architecture.md` — note the convention doc + proposal (Task 6)

## In-flight scope updates

(none yet)

## Assumptions

- The existing `docs/failure-modes.md` six-field schema is canonical and its ~40 consumers (skills, PR-gate, rules, ADRs) must keep working — adding optional fields is backward-compatible because every consumer reads by Symptom phenotype or by FM-NNN ID, not by a fixed field set.
- neural-lace is a pre-customer harness repo → merge to master autonomously per `git.md` pre-customer policy; no preview gating.
- The other downstream projects' repos are not in this worktree; bootstrap is delivered as filed tasks + a documented procedure, not direct edits (per the brief's deliverable 7).
- The two new fields are optional: a project adopting the catalog may omit Discriminator/Recovery on entries where they add nothing; the schema preamble states this.

## Edge Cases

- A consumer grepping the literal six-field list could mis-handle entries with the two new fields → mitigated by appending the new fields *after* Example and marking them optional in the preamble; no consumer parses positionally.
- `prd-validity-gate.sh` fires on plan Write → satisfied by `prd-ref: n/a — harness-development` carve-out.
- `scope-enforcement-gate.sh` iterates ACTIVE plans; an unrelated ACTIVE plan (`tranche-4-canonical-pilot-handoff.md`) exists — my commits stay within THIS plan's declared files so the gate passes; the other plan's scope is disjoint.
- `product-acceptance-gate.sh` Stop hook iterates all ACTIVE plans incl. the unrelated tranche-4 plan — if it blocks at session end on that orthogonal plan, a substantive per-`git-discipline.md` Rule 3 waiver is the correct response (not a fix to that plan, which is out of this session's scope).
- `definition-on-first-use-gate.sh` only fires under `neural-lace/build-doctrine/`; the 08-project-bootstrapping.md edit must define any new acronym inline or via glossary.

## Testing Strategy

All tasks are `Verification: mechanical` (build-harness-infrastructure shape — self-tests/structural checks are the harness's native verification idiom):
- Files exist with the expected sections (`test -f`, `grep -q` for required headings).
- `docs/failure-modes.md` FM-024..FM-028 each carry all six required fields (+ optional new fields) — grep per entry.
- `diagnosis.md` canonical vs `~/.claude` mirror byte-identical (`diff -q`).
- `DECISIONS.md` has the 033 row; `harness-architecture.md` references the new convention.
- No harness-hygiene denylist hits in staged diff (pre-commit gate).
- ADR 033 referenced from the convention doc and the implementing commit.

## Walking Skeleton

Thinnest end-to-end slice that proves the architecture: ADR 033 (the decision) → convention doc (the standard) → one new FM entry in `docs/failure-modes.md` using the extended schema (the worked instance) → diagnosis.md reflex line (the reflexive consumption point). If those four cohere and reference each other, the remaining template/proposal/bootstrap tasks are mechanical fan-out of the same pattern.

## Decisions Log

### Decision: Reconcile with existing `docs/failure-modes.md`, do not fork a new directory
- **Tier:** 2
- **Status:** proceeded with recommendation (reversible — additive optional schema fields, single-revert)
- **Surfaced to user:** 2026-05-19, plain-text in the session response before plan creation
- **Chosen:** canonical single-file six-field schema + two additive optional fields (Discriminator, Recovery); cross-project convention documents the existing pattern.
- **Alternatives:** (a) build the requested `docs/failure-modes/` directory + new schema as literally specified — rejected: forks the catalog, breaks `harness-lesson`/`why-slipped`/PR-gate consumers, file-vs-dir path collision; (b) full schema replacement + migrate 23 entries — rejected: large irreversible churn for no functional gain.
- **Reasoning:** the harness's own anti-fragmentation principle (one catalog per project, one mechanism per class) makes a parallel catalog self-defeating; additive fields deliver the investigation-first value without breaking any consumer; reversible via one `git revert`.
- **Checkpoint:** N/A (recorded pre-build)
- **To reverse:** revert the ADR + convention + schema-preamble commits; the 23 original entries are untouched.

## Definition of Done
- [ ] All 7 tasks task-verified PASS
- [ ] ADR 033 + DECISIONS row landed
- [ ] Convention doc, template skeleton, proposal doc created
- [ ] FM-024..FM-028 in `docs/failure-modes.md`; schema preamble extended
- [ ] diagnosis.md reflex added + mirror byte-identical
- [ ] harness-architecture.md + CLAUDE.md + bootstrap doctrine updated
- [ ] Bootstrap tasks filed for the 3 other projects
- [ ] Merged to neural-lace master; main checkout synced
- [ ] SCRATCHPAD updated; completion report appended; Status → COMPLETED

## Completion Report

_Generated by close-plan.sh on 2026-05-19T20:04:13Z._

### 1. Implementation Summary

Plan: `docs/plans/fm-catalog-harness-architecture.md` (slug: `fm-catalog-harness-architecture`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/rules/diagnosis.md`
- `build-doctrine/doctrine/08-project-bootstrapping.md`
- `docs/DECISIONS.md`
- `docs/conventions/failure-mode-catalogs.md`
- `docs/decisions/033-failure-mode-catalog-cross-project-convention.md`
- `docs/failure-modes.md`
- `docs/harness-architecture.md`
- `docs/proposals/fm-catalog-auto-search-harness-integration.md`
- `docs/templates/project-failure-modes/FM-template.md`
- `docs/templates/project-failure-modes/README.md`
- `docs/templates/project-failure-modes/failure-modes.md`
- `~/.claude/rules/diagnosis.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
0658758 feat(phase-1d-c-2): Task 10 — failure-mode catalog +4 entries (unfrozen-spec-edit, missing-PRD, missing-plan-header-field, missing-behavioral-contracts-at-r3+)
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0c1c4d8 docs(adr): ADR-032 — conversation-tree JSON state-schema field-layout contract (Task A1)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19bb3fc feat: B-DEC-D — resolve NL-FINDING-003 per DEC-D = option (d) snapshot-integrity attestation (REPLACES (b))
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2fa15d8 docs(adr): ADR-031 r2 — harden after systems-designer Phase-3 FAIL
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3e3568f feat(harness): build-harness-infrastructure work-shape — lighter process carve-out for harness work
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
460519e feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
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
