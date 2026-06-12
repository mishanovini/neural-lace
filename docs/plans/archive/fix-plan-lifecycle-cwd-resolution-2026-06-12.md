# Plan: Fix plan-lifecycle.sh cross-repo mis-archival (cwd-resolution class)
Status: COMPLETED
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

## Completion Report

_Generated by close-plan.sh on 2026-06-12T16:40:11Z._

### 1. Implementation Summary

Plan: `docs/plans/fix-plan-lifecycle-cwd-resolution-2026-06-12.md` (slug: `fix-plan-lifecycle-cwd-resolution-2026-06-12`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/plan-lifecycle.sh`
- `docs/backlog.md`
- `docs/discoveries/2026-06-09-scope-gate-uses-session-cwd-not-cd-target.md`
- `docs/failure-modes.md`
- `docs/plans/fix-plan-lifecycle-cwd-resolution-2026-06-12.md`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
0658758 feat(phase-1d-c-2): Task 10 — failure-mode catalog +4 entries (unfrozen-spec-edit, missing-PRD, missing-plan-header-field, missing-behavioral-contracts-at-r3+)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
19af838 plan(amend): capture-codify — pass-5 generalization sweep + harness-improvement backlog
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1d485de plan(1d-F): definition-on-first-use enforcement (sub-gap G absorbed)
2068db5 docs(backlog): file harness gap 23 — gate reads stale commit message file
243c675 backlog: P1 — harness-work plans have no tracked home (2026-04-22)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
25ed7f5 docs(handoff): refresh backlog + roadmap to reflect closed Tranche 1.5 + add HARNESS-GAP-19
2987804 docs(backlog): mark bug-persistence-gate as delivered (shipped 0090d4b)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2c272c6 backlog: HARNESS-GAP-27 — scope-enforcement-gate merge-aware
2f3be21 feat(harness): D1+D4+D5 follow-through — plan template, multi-push impl, hygiene-scan expansion gap
30fc0c7 plan: claude-remote adoption + harness portability to cloud sessions
31067e7 docs(accounting): GAP-20 + GAP-21 backlog + honest force-usage accounting (committed in docs/reviews/)
3402cd6 feat(hooks): land customer-facing-review gate from 2026-06-02 salvage (ADR 053, renumbered from 046)
3a2babc reconverge: land personal fork onto PT master (decision-context + pr-health + F7 + principles)
3adb281 plan: end-user-advocate + product-acceptance loop (design mode)
428dbef plan: pre-submission-audit-mechanical-enforcement (absorbs HARNESS-AUDIT-EXT-01+02)
4d18bf5 plan(parallel-tranches): start GAP-16 + Tranche 0b in parallel
4f5db65 docs(backlog): HARNESS-GAP-08 — Status: REFERENCE for index/roadmap docs in docs/plans/
5122b5e fix(backlog): renumber UX/CX completion-criterion entry HARNESS-GAP-47 -> GAP-48 (number collision)
566ffa6 feat(harness): D1-D5 educational re-do follow-through (Decision 014, GAP-12, gitignore fix)
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
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
