# Plan: scope-enforcement-gate Windows drive-letter fix + HARNESS-GAP-27 supersession docs
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: single-hook change (scope-enforcement-gate.sh) + doc updates to backlog/ADR/rule rows; no new components
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal scope-gate refinement; the gate's `--self-test` (now 20 scenarios) is the acceptance artifact, no product user surface
Backlog items absorbed: none

## Goal
PR #26 (HARNESS-GAP-29, 2026-05-27) shipped the rebase/merge full-skip in `scope-enforcement-gate.sh` but the
`case` statements that normalize `git rev-parse --git-dir` only treated `/*` as absolute. On Windows Git Bash,
`git rev-parse --git-dir` returns a drive-letter path (`C:/Users/…/.git`), which fell through to the
relative-handling branch and got re-prefixed with the repo root — producing a nonexistent path. The MERGE_HEAD /
rebase-state filesystem checks then silently never fired on Windows, so the full-skip was lost on the only
machine class where Git Bash is the canonical shell. Fix: extract `_resolve_git_dir_abs` helper that recognizes
POSIX-absolute, Windows drive-letter (forward- and back-slash forms), relative, and empty inputs; replace both
inline `case` blocks with calls to it; add self-test scenario 20 exercising the helper directly so the fix is
covered deterministically on any platform. Concurrently, sweep all live documentation of HARNESS-GAP-27 to mark
it superseded by PR #26 with a one-line citation (the narrow migration-allowlist behavior is no longer the
current behavior).

## Scope
- IN: `adapters/claude-code/hooks/scope-enforcement-gate.sh` — add `_resolve_git_dir_abs` helper, replace both inline `case` blocks, add self-test scenario 20, bump scenario count 19→20.
- IN: `adapters/claude-code/rules/vaporware-prevention.md` — rewrite the row's merge-context paragraph to lead with HARNESS-GAP-29 full-skip and mark HARNESS-GAP-27 superseded.
- IN: `adapters/claude-code/rules/gate-respect.md` — append a one-line supersession parenthetical to the HARNESS-GAP-27 worked example so it remains accurate as a teaching narrative.
- IN: `docs/backlog.md` — mark the HARNESS-GAP-27 entry [SUPERSEDED 2026-05-27 by PR #26 / HARNESS-GAP-29] with a one-line citation.
- IN: `docs/decisions/030-scope-enforcement-gate-merge-aware-union-of-plans.md` — flip Status to SUPERSEDED with a supersession-note paragraph.
- IN: live `~/.claude/` mirrors of the hook + the two touched rules (byte-identical sync per harness-maintenance.md two-layer config).
- OUT: `docs/harness-architecture.md` — line 7 already documents HARNESS-GAP-29 superseding HARNESS-GAP-27; no further edit needed.
- OUT: the archived plans (`docs/plans/archive/scope-gate-rebase-exemption.md`, `docs/plans/archive/session-state-refresh-2026-05-22.md`) — historical records; do not edit archived plans.
- OUT: any downstream product code; any other hook.

## Tasks
- [ ] 1. Extract `_resolve_git_dir_abs` helper recognizing POSIX-absolute, Windows drive-letter (forward- and back-slash), relative, and empty git-dir paths; replace both inline `case` blocks in the gate with calls to the helper. — Verification: mechanical
- [ ] 2. Add self-test scenario 20 calling `_resolve_git_dir_abs` directly with synthetic inputs (drive-letter forward/back, POSIX absolute, relative-vs-root, empty); bump scenario count 19→20 and update header comment. — Verification: mechanical
- [ ] 3. Documentation supersession sweep — backlog GAP-27 entry, ADR 030 Status + note, vaporware-prevention.md row, gate-respect.md worked-example parenthetical. — Verification: mechanical
- [ ] 4. Sync live `~/.claude/` mirrors of the hook + the two touched rules; verify byte-identical via `diff -q`. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — `_resolve_git_dir_abs` helper + two `case`-block replacements + self-test scenario 20.
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map row rewrite (GAP-29 leads; GAP-27 marked superseded).
- `adapters/claude-code/rules/gate-respect.md` — supersession parenthetical in the HARNESS-GAP-27 worked example.
- `docs/backlog.md` — HARNESS-GAP-27 entry marked SUPERSEDED with PR #26 citation.
- `docs/decisions/030-scope-enforcement-gate-merge-aware-union-of-plans.md` — Status: SUPERSEDED 2026-05-27 by PR #26 + supersession note.
- `docs/plans/windows-scope-gate-drive-letter-fix.md` — this plan (self-claiming).
- `docs/plans/windows-scope-gate-drive-letter-fix-evidence.md` — evidence sibling capturing the self-test result.

## Testing Strategy
- `bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test` → 20/20 pass (no regression on scenarios 1-19; new scenario 20 verifies the helper's contract on all four input shapes).
- Static review of the two replaced `case` blocks — both now call `_resolve_git_dir_abs` and the helper accepts drive-letter input as absolute.
- Cross-platform regression test (scenario 20) exercises the drive-letter case on any platform without needing a real Windows git.

## Walking Skeleton
The thinnest end-to-end slice is the helper + one self-test assertion exercising the Windows drive-letter case.
The full slice (4 input shapes × dedicated assertions, both `case`-block replacements, header-comment update,
all 5 doc updates) is implemented directly since the change is bounded, mechanical, and verifiable inline.

## Decisions Log
### Decision: extract a helper rather than duplicate the `case` fix in two places
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Single `_resolve_git_dir_abs` helper replacing both inline `case` blocks.
- **Alternatives:** Duplicate the `case` fix inline at both sites — rejected because future drift between the two copies is the failure shape that produced the original bug (one block recognizes drive-letter, the other doesn't).
- **Reasoning:** A helper produces a single source of truth for git-dir resolution and a deterministic unit-style self-test that doesn't need a real Windows git.
- **To reverse:** one-commit revert restores the inline `case` blocks (both call sites become independent again).

### Decision: scenario 20 calls the helper directly rather than mocking `git rev-parse` output
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Scenario 20 invokes `_resolve_git_dir_abs` with synthetic inputs.
- **Alternatives:** Mock `git rev-parse --git-dir` to return a drive-letter path — rejected because mocking `git` deep enough to make `[[ -e $GIT_DIR_PATH/MERGE_HEAD ]]` fire correctly cross-platform would itself be a fragile harness.
- **Reasoning:** Calling the helper directly is the cheapest correct regression test — it covers the bug's actual locus (path classification) on every platform without needing platform-specific git behavior.
- **To reverse:** delete scenario 20.

## Definition of Done
- [ ] All tasks shipped
- [ ] 20/20 self-test pass
- [ ] No regression on scenarios 1-19
- [ ] All five documentation surfaces updated (backlog, ADR 030, vaporware-prevention row, gate-respect parenthetical — `docs/harness-architecture.md` line 7 already current)
- [ ] Live `~/.claude/` mirrors synced (byte-identical via `diff -q`)
- [ ] Completion report appended; Status → COMPLETED

## Completion Report

### 1. Implementation Summary
All four tasks shipped in a single feature-branch commit on `fix/windows-scope-gate-drive-letter`:
- Task 1: `_resolve_git_dir_abs` helper added to `adapters/claude-code/hooks/scope-enforcement-gate.sh` (between `_is_system_managed_path` and the `--self-test` block). Both inline `case` blocks that normalized `git rev-parse --git-dir` (the rebase/merge full-skip block AND the legacy IN_MERGE block) replaced with calls to the helper. The four-branch `case` recognizes POSIX-absolute (`/*`), Windows drive-letter forward-slash (`[A-Za-z]:/*`) and backslash (`[A-Za-z]:\\*`), empty, and otherwise-relative.
- Task 2: self-test scenario 20 added directly above the summary echo. Five sub-assertions exercise the helper with synthetic inputs (drive-letter forward/back, POSIX absolute, relative-vs-root, empty). Scenario count bumped 19→20 in both the header comment and the summary line. 20/20 PASS confirmed locally.
- Task 3: documentation supersession sweep — `docs/backlog.md` HARNESS-GAP-27 entry marked `[SUPERSEDED 2026-05-27 by PR #26 / HARNESS-GAP-29]` with closing-sentence citation; `docs/decisions/030-…md` title flipped `(DEFERRED)` → `(SUPERSEDED)` + Status line + blockquote supersession-note paragraph; `adapters/claude-code/rules/vaporware-prevention.md` enforcement-map row rewritten to lead with HARNESS-GAP-29 full-skip and explicitly mark HARNESS-GAP-27 superseded; `adapters/claude-code/rules/gate-respect.md` worked-example parenthetical appended. `docs/harness-architecture.md` line 7 already current (added by PR #26); archived plans intentionally not edited.
- Task 4: live `~/.claude/` mirrors synced for the hook + the two touched rules; `diff -q` confirms byte-identical against the repo canonical.
- Tasks left unchecked per the verifier mandate (no manual checkbox flips); mechanical verification recorded in the sibling `windows-scope-gate-drive-letter-fix-evidence.md`. Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
Two decisions captured in the Decisions Log (extract-helper-vs-duplicate-fix; scenario-20-calls-helper-directly-vs-mock-git). No deviations from the original scope.

### 3. Known Issues & Gotchas
- The `[A-Za-z]:\\*` pattern in the helper's `case` covers the backslash form `git rev-parse --git-dir` rarely emits (Git Bash typically returns forward slashes even on Windows). It's defensive coverage; the load-bearing case is the forward-slash form which scenario 20 sub-assertion 1 exercises.
- The migration-only `IN_MERGE` allowlist below the rebase/merge full-skip remains in place as documented defense-in-depth, subsumed whenever the full-skip fires (MERGE_HEAD present). Removing it is out of scope for this PR.

### 4. Manual Steps Required
None for the PR. Cross-repo: this lands on `Pocket-Technician/neural-lace` master; the personal mirror remote receives it via the existing mirror Action.

### 5. Testing Performed
`bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test` → 20/20 PASS, no regression on scenarios 1-19. The new scenario 20 verifies the helper deterministically on any platform without needing a real Windows git. Three `diff -q` invocations confirm byte-identical live-mirror sync. Evidence: sibling `windows-scope-gate-drive-letter-fix-evidence.md`.

### 6. Cost Estimates
n/a — harness-internal bash hook + documentation; no runtime cost.
