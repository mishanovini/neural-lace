# Plan: Pre-Commit Gate — Validate Build Without Requiring a Live DB
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and the hook's `--self-test` PASS plus a DB-less build simulation are its acceptance artifacts. No product UI surface exists.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
`pre-commit-gate.sh` ran `npm run build` unconditionally. In a project whose
build invokes DB-touching steps (prisma migrate, build-time data fetching that
needs `DATABASE_URL`), that step fails inside a worktree with no DB connection —
so the gate false-fires on an environmental problem rather than a real code
defect. The same hook also ran `npm test`/`npm run build` even when no such
script exists, exiting 127 and blocking every commit in a non-npm repo (the
harness repo itself). This plan makes the gate validate real code correctness
without requiring a live DB, while preserving full-build signal for projects
that have a normal build.

## Scope
- IN: the build-script selection and skip-when-undefined behavior in
  `pre-commit-gate.sh`, plus a `--self-test` for the new selection logic.
- OUT: changing any other gate; changing CI; per-project package.json changes
  (a project adopts the carve-out by declaring its own `build:gate` script —
  that is downstream work, not part of this harness change).

## Tasks
- [ ] 1. Add `_has_npm_script` + `_select_build_script` helpers; prefer a project-declared `build:gate` over `build`; skip the test and build steps when the script is absent; add a `--self-test` covering the selection logic. Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/pre-commit-gate.sh` — build-script selection (prefer `build:gate`), skip-when-undefined for test/build, `--self-test` block.
- `docs/plans/fix-precommit-gate-db-build.md` — this plan file.

## Assumptions
- `jq` is available at gate runtime (it is a hard harness dependency — the
  PreToolUse commit matcher in `settings.json` already shells out to `jq`).
- A project that needs a DB-free gate build will declare its own `build:gate`
  npm script (a typecheck/compile-only subset); the harness cannot know an
  arbitrary project's build graph, so the DB-vs-no-DB knowledge lives in the
  project's package.json, where it belongs.

## Edge Cases
- No `package.json` (non-npm repo, harness repo): both test and build steps
  skip gracefully instead of exiting 127.
- `build:gate` declared without `build`: selection picks `build:gate`.
- `build` declared without `build:gate`: behavior unchanged — full build runs.
- Neither build script declared but a `test` script exists: build skips, test
  still runs.
- A real build failure under the selected script still BLOCKS (signal preserved).

## Testing Strategy
- `bash adapters/claude-code/hooks/pre-commit-gate.sh --self-test` exercises 8
  selection/skip scenarios and must report `ALL SELF-TESTS PASSED (8/8)`.
- A throwaway DB-less project (where `build` needs `DATABASE_URL` and
  `build:gate` does not) demonstrates the before/after: `npm run build` exits 1
  with no DB (old gate would block), the gate selects `build:gate` and it exits
  0 (new gate passes).
- Running the live gate in the (package.json-less) harness worktree confirms the
  test/build steps now skip instead of 127-blocking.

## Walking Skeleton
The thinnest slice is the `_select_build_script` function: given a `package.json`
it returns `build:gate` | `build` | "" — the single decision the whole fix turns
on. The `--self-test` exercises that function directly, so the verification path
runs end-to-end without invoking a real build.

## Decisions Log
### Decision: Opt-in `build:gate` target (option c) over env-detection (option a)
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** Prefer a project-declared `build:gate` npm script; fall back to
  `build`; skip when neither exists.
- **Alternatives:** (a) detect a DB-less env (no `DATABASE_URL`) and skip DB
  steps — rejected: the harness can't reliably know which build step needs the
  DB, and env-sniffing is non-deterministic. (b) mock the DB at gate time —
  rejected: requires per-project knowledge the harness doesn't have.
- **Reasoning:** Puts the build-graph knowledge in the project's package.json
  (where it belongs), is deterministic, mirrors the existing
  "runs only if the project defines npm run X" convention already used for the
  `audit:events` / `audit:connectivity` steps, and does not weaken signal for
  projects with a normal build.
- **Checkpoint:** N/A (single commit)
- **To reverse:** revert the commit; the gate returns to unconditional `npm run build`.

## Definition of Done
- [ ] Task 1 verified (self-test 8/8 + DB-less simulation + harness-worktree pass)
- [ ] Hook synced to the live `~/.claude/` mirror (byte-identical)
- [ ] PR merged to master, gate working correctly in DB-less environments
- [ ] SCRATCHPAD / plan status closed

## Completion Report

_Generated by close-plan.sh on 2026-05-27T09:34:00Z._

### 1. Implementation Summary

Plan: `docs/plans/fix-precommit-gate-db-build.md` (slug: `fix-precommit-gate-db-build`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/pre-commit-gate.sh`
- `docs/plans/fix-precommit-gate-db-build.md`

Commits referencing these files:

```
947fb1a feat(hook): pre-commit connectivity gate (opt-in via npm run audit:connectivity:files-only)
e2a6d55 feat(freshness): wire 5 pre-commit gates + update architecture + guide
e6b32ab feat(hook): pre-commit event-coupling gate (opt-in via npm run audit:events)
e95dc88 fix(hooks): validate build without a live DB in pre-commit-gate
fa50661 Initial release v1.0
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
