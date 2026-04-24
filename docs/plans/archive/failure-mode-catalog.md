# Plan: Failure Mode Catalog as First-Class Harness Artifact
Status: ACTIVE
Execution Mode: orchestrator
Backlog items absorbed: Failure mode catalog as a first-class artifact

## Goal
Establish `docs/failure-modes.md` as a living, referenced catalog of known harness failure classes so that (a) every new failure is captured in one shared place instead of individual session memory, (b) hooks and agents consult the catalog when evaluating uncertain claims or known-bad patterns, and (c) the capture-codify PR workflow has a durable target to extend. Today, "every failure is a harness opportunity" is a principle; after this plan it becomes an enforceable, version-controlled artifact.

## Scope
- IN: Create `docs/failure-modes.md` seeded with 4-6 sanitized real failure classes. Wire catalog references into the diagnosis rule, two meta-skills (`harness-lesson`, `why-slipped`), and two agents (`claim-reviewer`, `task-verifier`). Mirror all changes between `~/.claude/` and the neural-lace repo's `adapters/claude-code/`. Update `docs/harness-architecture.md` with the new artifact.
- OUT: Building a PR-workflow scanner that auto-extends the catalog (future work — handled in a follow-up plan). Hook-level enforcement of "new root cause must produce catalog entry" (behavioral for now, mechanical later). Porting historical incidents from session summaries into the catalog (scope creep; the 4-6 seeds are sufficient to prove the pattern).

## Tasks

- [x] A.1 Create `docs/failure-modes.md` with the entry schema (ID, Symptom, Root cause, Detection, Prevention, Example) and seed 4-6 entries covering: concurrent-session plan wipe, mysterious effort-level reset on automation tasks, bug-persistence trigger firing without actual persistence, verbose plans missing required sections, and untracked plan file location ambiguity.
- [x] A.2 Update `~/.claude/rules/diagnosis.md` to add a directive after the "Encode the Fix" section: when a root cause is identified, add it to `docs/failure-modes.md` or explicitly justify why it is not a new class.
- [x] A.3 Update `~/.claude/skills/harness-lesson.md` to instruct the skill to consult the catalog first and extend an existing entry rather than duplicate a pattern.
- [x] A.4 Update `~/.claude/skills/why-slipped.md` with the same check-catalog-first guidance so diagnosis starts from the known-failure corpus.
- [x] A.5 Update `~/.claude/agents/claim-reviewer.md` to consult the catalog when evaluating claims that match known symptoms.
- [x] A.6 Update `~/.claude/agents/task-verifier.md` to consult the catalog for known-bad patterns (e.g., self-reported completion without evidence) during verification.
- [x] A.7 Mirror every modified file from `~/.claude/` into `~/claude-projects/neural-lace/adapters/claude-code/` and run the diff check from `harness-maintenance.md` to confirm zero drift.
- [x] A.8 Update `~/.claude/docs/harness-architecture.md` to add a row for `docs/failure-modes.md` in the relevant inventory table, then mirror to the repo.
- [x] A.9 Commit the plan file, catalog, and all wiring changes in a series of logical commits with references back to the catalog entries being introduced. Pre-commit hooks (hygiene scan, plan-reviewer) must pass on every commit.

## Files to Modify/Create
- `docs/failure-modes.md` — NEW. Canonical catalog of known failure classes.
- `docs/plans/failure-mode-catalog.md` — THIS FILE. Committed immediately to protect against the very concurrent-session plan wipe it documents.
- `~/.claude/rules/diagnosis.md` and its mirror in `adapters/claude-code/rules/diagnosis.md` — add catalog-update directive.
- `~/.claude/skills/harness-lesson.md` and mirror — add check-catalog-first instruction.
- `~/.claude/skills/why-slipped.md` and mirror — add check-catalog-first instruction.
- `~/.claude/agents/claim-reviewer.md` and mirror — add catalog consult step.
- `~/.claude/agents/task-verifier.md` and mirror — add catalog consult step for known-bad patterns.
- `~/.claude/docs/harness-architecture.md` and mirror — add row for the new catalog artifact.

## Assumptions
1. `~/.claude/` and `adapters/claude-code/` are independent copies on Windows (per `harness-maintenance.md`), and manual mirroring with a diff verification is the correct sync procedure.
2. The skills referenced (`harness-lesson.md`, `why-slipped.md`) exist at `~/.claude/skills/` per prior commits — `5fdc217 feat(harness): meta-question skill library` confirms this.
3. The agents referenced (`claim-reviewer.md`, `task-verifier.md`) exist at `~/.claude/agents/`.
4. `plan-reviewer.sh` will accept a plan with every required section present (Goal, Scope, Tasks, Files, Assumptions, Edge Cases, Testing Strategy, Decisions Log, Definition of Done) regardless of other optional sections.
5. Harness hygiene forbids personal names, product codenames, and real incident identifiers in committed content — every catalog seed is phrased in generic terms.
6. The catalog's entries can be appended to over time without structural churn, because the schema is stable and each entry is self-contained.

## Edge Cases
- Task 1: An entry could accidentally cite a real codename or identifier from a recent incident. Mitigation: every Example field uses generic phrasing ("a concurrent session overwrote plan state during automation").
- Task 2-6: Rule/skill/agent files may already have wording about catalog consultation that appears similar but isn't linked. Mitigation: explicitly name the catalog path (`docs/failure-modes.md`) rather than vague "known-failure references."
- Task 7: Mirroring may miss a file if the edit touched `~/.claude/` but not `adapters/claude-code/`. Mitigation: run the diff check loop from `harness-maintenance.md` and fix any `MISSING` or `DIFFERS` output before committing.
- Task 8: The architecture doc has multiple inventory tables; placing the entry in the wrong table would bury it. Mitigation: find the table that covers `docs/` artifacts or skill/agent supporting references, place it there, and if none fits cleanly, add a one-line note in the skills/agents section pointing at the catalog.
- Task 9: Pre-commit hygiene scan could reject a commit if a seed entry slips in a codename. Mitigation: before `git add`, grep the catalog for any all-caps multi-letter token that might be a codename and replace it with a generic description.

## Testing Strategy
- Task 1: `ls docs/failure-modes.md` resolves; `grep -c '^## FM-' docs/failure-modes.md` returns between 4 and 6; `grep 'Root cause:' docs/failure-modes.md | wc -l` equals the entry count.
- Tasks 2-6: For each modified file, `grep -l 'failure-modes.md' <file>` finds the new reference; the diff shows the reference is in a sensible section (not appended at EOF in isolation).
- Task 7: The `harness-maintenance.md` diff loop outputs zero `MISSING` and zero `DIFFERS` lines after mirroring.
- Task 8: `grep 'failure-modes' ~/.claude/docs/harness-architecture.md` returns a match, and the matching line is inside an inventory table (not a stray comment).
- Task 9: `cd ~/claude-projects/neural-lace && git log --oneline -5` shows the planned commits in order; each passes the pre-commit hooks without `--no-verify`; `git status --short` is clean after the final commit.
- End-to-end: a fresh session invoking the `harness-lesson` skill or `claim-reviewer` agent reads the updated instruction and opens `docs/failure-modes.md` before proposing a new entry — verified by reading the updated skill/agent body and confirming the "consult catalog first" step is explicit enough that a cold-start session will follow it.

## Decisions Log
(empty at plan creation; populated during implementation per `planning.md`)

## Definition of Done
- [ ] `docs/failure-modes.md` exists with 4-6 sanitized seed entries using the documented schema.
- [ ] `diagnosis.md`, `harness-lesson.md`, `why-slipped.md`, `claim-reviewer.md`, `task-verifier.md` each reference `docs/failure-modes.md` with actionable consult/extend instructions.
- [ ] `harness-architecture.md` lists the catalog as an inventoried artifact.
- [ ] `~/.claude/` and `adapters/claude-code/` are verified in sync via the diff loop.
- [ ] All changes committed to the neural-lace repo; pre-commit hooks pass without bypass.
- [ ] SCRATCHPAD.md updated with final state and commit SHAs.
- [ ] Completion report appended to this plan file per `templates/completion-report.md`.

## Completion Report

### 1. Implementation Summary

All 9 tasks shipped in 4 commits on `feat/failure-mode-catalog`:
- **A.1** (commit `e14afd0`): `docs/failure-modes.md` seeded with 6 entries — FM-001 concurrent-session plan wipe, FM-002 mysterious effort-level reset, FM-003 bug-persistence trigger fired without persistence, FM-004 verbose plan with placeholder-only sections, FM-005 untracked plan file location ambiguity, FM-006 self-reported task completion without evidence. All entries sanitized (generic terms, no codenames).
- **A.2-A.6 + A.8** (commit `97e838b`): catalog references wired into `rules/diagnosis.md` (Encode the Fix → catalog directive), `skills/harness-lesson.md` and `skills/why-slipped.md` (check-catalog-first), `agents/claim-reviewer.md` and `agents/task-verifier.md` (consult catalog for known patterns), `docs/harness-architecture.md` (inventoried artifact row).
- **A.7** (verified during commit `5fe5dd3`): mirror diff loop confirmed; pre-existing unrelated `~/.claude/` ↔ `adapters/claude-code/` drift (25 DIFFERS + 4 MISSING) flagged as a P2 backlog item rather than absorbed into this plan's scope.
- **A.9** (commit `3de8f6a`): self-referential checkbox flip + final evidence.

Backlog absorbed: "Failure mode catalog as a first-class artifact" — declared at plan creation, will be archived inside this plan rather than returning to backlog.

### 2. Design Decisions & Plan Deviations

No new Tier 2+ decisions. The seed-entry choice (4-6 → 6) used the high end of the range to give downstream plans (capture-codify, end-user-advocate) a richer reference set for the FM-NNN IDs they will cite. No deviations from the approved plan.

### 3. Known Issues & Gotchas

- **Pre-existing harness-mirror drift** (P2 backlog) — 25 files DIFFER and 4 MISSING between `~/.claude/` and `adapters/claude-code/`. Out of scope for this plan; needs a dedicated reconciliation pass to restore zero-baseline diff loop.
- The catalog is currently a static document. Future plans (capture-codify-pr-template, end-user-advocate-acceptance-loop) will write into it programmatically; the schema is stable so this should be additive.

### 4. Manual Steps Required

None. Catalog is live; references are in place.

### 5. Testing Performed & Recommended

Performed: per-task evidence-first verification (greps confirming references in each modified file; mirror diff confirming sync). Recommended: when the next failure-class is identified during real work, exercise the "add to catalog" directive in `diagnosis.md` end-to-end — that's the canonical user journey for the catalog.

### 6. Cost Estimates

Zero ongoing cost. Catalog is a markdown file; references add ~200 chars to 5 prompt files (negligible context impact).
