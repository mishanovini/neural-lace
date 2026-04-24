# Plan: Lifecycle Test (F.3 Dogfood)

Status: COMPLETED
Mode: code
Backlog items absorbed: none

## Goal

Throwaway plan used by Task F.3 of the robust-plan-file-lifecycle plan to dogfood the full lifecycle: creation warning fires on Write, the plan can be committed, the Status: ACTIVE -> Status: COMPLETED transition triggers `plan-lifecycle.sh` to `git mv` the file into `docs/plans/archive/`, and `find-plan-file.sh` resolves the archived slug transparently. This file is intentionally short and is removed at the end of the test by `git rm`.

## Scope

- IN: exercising the four-stage lifecycle on a single throwaway plan (creation warning, commit, status transition + auto-archival, archive-aware lookup) and the cleanup `git rm`.
- OUT: testing edge cases of the hook (multiple plans, evidence companions, recovery paths) — those are covered by `plan-lifecycle.sh --self-test` which Phase A already verified.

## Tasks

- [ ] 1. Observe the creation warning emitted by `plan-lifecycle.sh` when this file is written.
- [ ] 2. Commit this file to satisfy the warning.
- [ ] 3. Transition Status to COMPLETED and observe `git mv` staging.
- [ ] 4. Commit the status change + rename atomically.
- [ ] 5. Resolve the slug via `find-plan-file.sh lifecycle-test` and confirm archive resolution.
- [ ] 6. Clean up via `git rm docs/plans/archive/lifecycle-test.md`.

## Files to Modify/Create

- `docs/plans/lifecycle-test.md` — created at start, transitioned through stages, removed at end.
- `docs/plans/archive/lifecycle-test.md` — destination after the auto-archival fires.

## Assumptions

- The plan-lifecycle.sh hook is wired into `~/.claude/settings.json` as a PostToolUse hook for Write and Edit (verified in Phase A.2).
- The repo's working tree is clean before this test starts so `git status --porcelain` output is unambiguous.
- `find-plan-file.sh` is already present at `~/.claude/scripts/find-plan-file.sh` and `adapters/claude-code/scripts/find-plan-file.sh` (verified in Phase B.2).

## Edge Cases

- If the creation warning does NOT fire on this Write, F.3 must be marked FAIL and the bug surfaced — the plan-lifecycle hook is the very thing this whole plan ships, and a no-op here invalidates the deliverable.
- If `git mv` fails because the archive subdirectory does not exist, the hook should create it. Either behavior is observable in `git status` after the Edit.
- If `find-plan-file.sh` returns the wrong path (active when archived, or vice versa), F.3 must FAIL.

## Testing Strategy

Each task's verification is the observable side effect of the previous step: the warning text in tool output, `git status --porcelain` showing staged-or-unstaged files in expected locations, the actual file paths existing on disk, and the stdout/stderr of `find-plan-file.sh`. No separate unit tests are needed because this IS the integration test for Phase A + Phase B.

## Definition of Done

- [ ] All 6 tasks observed.
- [ ] Auto-archival hook fired during Status transition (the load-bearing observation).
- [ ] Archive lookup resolves correctly.
- [ ] File removed at end (no residual fixture in archive).
