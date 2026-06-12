# Plan: Fix plan-lifecycle.sh cross-repo mis-archival (cwd-resolution class)
Status: ACTIVE
Execution Mode: single-session (single-task fix; orchestrator not required per orchestrator-pattern.md "NOT needed for single-task quick fixes")
Mode: code
Backlog items absorbed: HARNESS-GAP-49
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal hook bug-fix; the user is the maintainer and the hook's --self-test (10 scenarios incl. the new cross-repo scenario 10) is the acceptance artifact per the build-harness-infrastructure work-shape.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

`plan-lifecycle.sh` (PostToolUse auto-archival hook) resolves its git-mv target
from the SESSION cwd instead of the repo containing the edited plan file.
Observed 2026-06-11: a session rooted in neural-lace flipped `Status:` on a plan
inside a sibling product repo's worktree; the hook deleted the plan from that
worktree and created+staged it at `neural-lace/docs/plans/archive/` — the wrong
repo (the operator restored the misplaced file at the time). Same class as the scope-enforcement-gate's
HARNESS-GAP-47 "Target-repo resolution" fix (2026-06-10), now catalogued as
FM-032. This plan applies the equivalent fix to the path-subject hook: derive
the repo root from `tool_input.file_path` and run every git operation
`git -C <that-root>`.

## User-facing Outcome

The maintainer can flip a plan's Status from a session rooted in ANY repo and
the archival lands in the repo that owns the plan — never in the session repo.
Concretely demonstrable: the hook's `--self-test` scenario 10 (plan fixture in
a second temp repo while cwd stays in the first) passes, and the live cross-repo
reproduction archives into the plan's own repo with a true staged `git mv`
rename instead of the prior cross-repo plain-`mv` damage.

## Scope

- IN: `adapters/claude-code/hooks/plan-lifecycle.sh` (repo-root resolution from
  the edited file's path; `git -C` on all git operations; header "Target-repo
  resolution" section; self-test scenario 10), `docs/failure-modes.md` (new
  FM-032 class entry), `docs/discoveries/2026-06-09-scope-gate-uses-session-cwd-not-cd-target.md`
  (second-instance append + implementation log + identifier sanitization),
  `docs/backlog.md` (surface the main-checkout reconcile need observed during
  this fix), live-mirror sync of the hook to `~/.claude/hooks/` (byte-identical,
  outside git).
- OUT: `plan-status-archival-sweep.sh` changes (audited this session — its
  `archive_plan()` already roots per-file via `git -C "$plans_dir"`, and its
  `$PWD` scan is cwd-by-design for a SessionStart hook; no change needed);
  option B of the 2026-06-09 discovery (hook-sync integrity — remains open);
  any change to scope-enforcement-gate.sh (already fixed 2026-06-10); resolving
  the main checkout's foreign staged state (operator decision — surfaced in
  backlog, not auto-resolved).

## Tasks

- [ ] 1. Fix plan-lifecycle.sh target-repo resolution: derive the repo root from the edited file's path via `git -C "$(dirname <file>)" rev-parse --show-toplevel`; root the four archival git operations (show, ls-files, mv, add) with `git -C <root>`; add the header "Target-repo resolution" section; add cross-repo self-test scenario 10; catalogue the class as FM-032; extend the 2026-06-09 discovery with the second instance; sync the live mirror byte-identically — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-lifecycle.sh` — the fix + scenario 10 + header section
- `docs/failure-modes.md` — append FM-032 (hook resolves target repo from session cwd, not the operated-on subject)
- `docs/discoveries/2026-06-09-scope-gate-uses-session-cwd-not-cd-target.md` — second-instance append, implementation log, sanitization of project identifiers (was staged-uncommitted in the main checkout; lands here)
- `docs/backlog.md` — absorb HARNESS-GAP-49 (delete from open section per backlog-plan-atomicity; this plan ships its proposed fix) + new HARNESS-GAP-51 entry surfacing the main checkout's foreign-staged-state reconcile need + v57 header note
- `docs/plans/fix-plan-lifecycle-cwd-resolution-2026-06-12.md` — this plan

## In-flight scope updates

(no in-flight changes yet)

## Assumptions

- The edited plan file's directory exists when the PostToolUse hook fires (the
  Edit/Write just completed), so `git -C "$(dirname <file>)"` resolves; when the
  file is outside any git work tree, the hook no-ops (strictly safer than the
  pre-fix behavior, which mis-archived into the cwd repo).
- origin/master's versions of the three modified committed files are identical
  to local HEAD's (verified via `git diff HEAD origin/master --stat` — empty),
  so changes authored against the main checkout apply cleanly in this worktree.
- `git -C` is available in every environment the hook runs in (Git Bash on
  Windows and POSIX) — the sibling sweep hook already relies on it.

## Edge Cases

- Plan file in a repo DIFFERENT from the session cwd → archival must land in the
  file's repo and stage there; session repo untouched (self-test scenario 10).
- Plan file not inside any git work tree → hook no-ops silently (no cross-repo
  plain-mv; covered by the `[ -z "$file_repo_root" ]` precondition).
- Plan tracked in its own repo but cwd in another repo → tracked-check now runs
  in the right repo, so archival is a true `git mv` rename (preserves history)
  instead of the plain-`mv` + `git add` decomposition.
- Evidence companion in the sibling repo → moves with the plan inside the same
  (correct) repo via the same `git -C` rooting.

## Acceptance Scenarios

- n/a — acceptance-exempt harness-internal plan; the hook's `--self-test`
  (10 scenarios) is the acceptance artifact per the work-shape.

## Out-of-scope scenarios

- Cross-repo behavior of OTHER path-subject hooks (none currently perform git
  mutations keyed to tool_input.file_path besides plan-lifecycle.sh; the FM-032
  Detection field gives the per-hook review check for future hooks).

## Testing Strategy

- Task 1 is `Verification: mechanical`: the hook's `--self-test` (10 scenarios,
  including new cross-repo scenario 10) must exit 0; a live end-to-end
  reproduction (two temp repos, stdin JSON invocation, cwd in the wrong repo)
  must archive into the plan's own repo and leave the session repo untouched;
  the live mirror must be byte-identical (`diff -q`). Evidence captured via
  `write-evidence.sh capture` with `exists:`, `command:` (self-test), and
  `files-in-commit` checks.

## Walking Skeleton

n/a — single-file hook fix on an existing mechanism; the thinnest slice IS the
fix + its self-test scenario (build-harness-infrastructure work-shape: Check 4b
advisory for harness-internal paths).

## Decisions Log

- Entry numbering: the new failure-mode entry is FM-032 (not FM-024 as a damaged
  working-tree copy of the catalog suggested) — the main checkout had a stale
  staged reversion of docs/failure-modes.md deleting FM-024..FM-031; the file
  was restored from HEAD before appending. Tier 1 (reversible, content-only).
- Built in a worktree from origin/master rather than the main checkout: the main
  checkout's index carries ~40 staged files from prior cross-machine sessions
  that the scope gate correctly flags; mutating that index (reset/stash juggling)
  risks destroying in-flight work (FM-001 class). Tier 1 (reversible; worktree
  removed after merge).

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): n/a — single-task Mode: code plan, no class-sweep needed
- S2 (Existing-Code-Claim Verification): n/a — single-task plan; code claims verified live this session (self-test + reproduction)
- S3 (Cross-Section Consistency): n/a — single-task plan, no class-sweep needed
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters introduced
- S5 (Scope-vs-Analysis Check): n/a — single-task plan, no class-sweep needed

## Definition of Done

- [ ] Task 1 checked off with mechanical evidence (self-test 10/10 + commit SHA)
- [ ] Live mirror `~/.claude/hooks/plan-lifecycle.sh` byte-identical to canonical
- [ ] Merged to master
- [ ] Completion report appended to this plan file
