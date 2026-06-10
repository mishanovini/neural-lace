# Plan: Worktree-Hygiene Sweeper — make worktree accumulation visible-and-cleanable
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism; self-test is the acceptance artifact
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
A downstream consumer repo accumulated 63 worktrees because parallel sessions
never tore theirs down. Build a sweeper script that classifies every registered worktree
as SAFE-PRUNE (no unique patches, clean, old) or HOLDS-CONTENT (never touched),
reports by default, and prunes only safe entries under an explicit
operator-approval env flag. Misha approved 2026-06-09.

## User-facing Outcome
The maintainer can run `worktree-hygiene-sweep.sh` against any repo (or all
worktree-bearing repos) and see a classification table of every worktree plus a
stash census; with `--prune` + `WORKTREE_SWEEP_APPROVE=1` the SAFE-PRUNE
entries are removed (worktree + `branch -d`) with a per-removal audit-log line
in `~/.claude/state/worktree-sweep.log`. A `--session-summary` mode emits one
compact line per repo (count > 5) ready for later SessionStart wiring.

## Scope
- IN: `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` (new script:
  report / prune / session-summary / self-test modes); this plan file; sync of
  the script to `~/.claude/scripts/` per the two-layer convention.
- OUT: editing `settings.json.template` (SessionStart wiring is deliberately
  deferred — the `--session-summary` mode exists so wiring later is trivial);
  any stash deletion (census is report-only); merging this branch to master
  (orchestrator's job); pruning anything in this session's real run (REPORT
  ONLY against neural-lace + the originating downstream repo).

## Tasks

- [x] 1. Author `worktree-hygiene-sweep.sh` — classification (SAFE-PRUNE vs HOLDS-CONTENT via `git cherry` unique-patch count + dirty count + age), report default, `--prune` gated on `WORKTREE_SWEEP_APPROVE=1` with `branch -d` second guard + audit log, stash census, `--session-summary`, Bash 3.2-portable, Windows drive-colon-safe — Verification: mechanical
- [x] 2. `--self-test` covering: safe-prune detected; dirty never safe; unique-patch never safe; prune without APPROVE refuses; prune with APPROVE removes only the safe one; primary worktree never touched — Verification: mechanical
- [x] 3. Real REPORT run against neural-lace + the originating downstream repo (no prune) + sync to `~/.claude/scripts/` with diff verify — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` — the sweeper (new)
- `docs/plans/worktree-hygiene-sweeper-2026-06-09.md` — this plan

## In-flight scope updates
- 2026-06-10: `docs/plans/worktree-hygiene-sweeper-2026-06-09-evidence/**` — closure evidence artifacts (3x mechanical .evidence.json + path-anonymized neural-lace report-only run; downstream-repo report run kept out of the harness repo per harness-hygiene, captured in session return)

## Assumptions
- `git worktree list --porcelain` output shape (worktree/branch/bare lines) is
  stable across the git versions on this machine (2.40+).
- `git cherry <base> <branch>` with base `origin/master` (fallback
  `origin/main`, then local `master`/`main`) is an adequate unique-patch
  oracle: 0 `+` lines means every patch on the branch is content-equivalent to
  one on the base.
- Worktrees whose directory is missing (stale registration) are surfaced as
  HOLDS-CONTENT/prunable-stale rather than silently skipped; `git worktree
  prune` semantics are NOT invoked automatically.

## Edge Cases
- Primary worktree: always skipped (never classified, never pruned) — detected
  as the first entry of `git worktree list --porcelain`.
- Detached-HEAD worktree: no branch to `branch -d`; classified HOLDS-CONTENT
  (cannot prove patch containment without a branch ref).
- Windows paths (`C:/...`): never split on `:`; porcelain parsing strips only
  the `worktree ` prefix.
- No origin remote / no master|main: classification degrades to HOLDS-CONTENT
  (no base to compare against — never guess-prune).
- Locked worktrees (`locked` porcelain attr): HOLDS-CONTENT, never pruned.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal; `--self-test` is the acceptance artifact)

## Out-of-scope scenarios
- n/a

## Testing Strategy
- `--self-test`: temp repo + scripted worktrees, six asserted scenarios (see
  Task 2). All-green is the completion bar.
- Real REPORT run against neural-lace + the originating downstream repo
  captured in the session return (no prune; `WORKTREE_SWEEP_APPROVE` unset).

## Walking Skeleton
The thinnest slice: parse `git worktree list --porcelain` for one repo, print
one classification row, exit 0. Everything else (prune, census, summary,
self-test) layers on that parse-and-classify core.

## Decisions Log
- Prune approval channel is the `WORKTREE_SWEEP_APPROVE=1` env flag per
  Misha's standing order (nothing deleted without explicit approval); the flag
  IS that approval, documented in the script header. Tier 1 — follows the
  directive verbatim.
- `branch -d` (not `-D`) as the second guard: git itself refuses unmerged
  branches even if classification were wrong. Tier 1.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-script plan; all behavior changes live in Task 1's description and the one Files entry
- S2 (Existing-Code-Claim Verification): n/a — new file; no existing-code claims beyond porcelain format (verified by running git worktree list --porcelain)
- S3 (Cross-Section Consistency): swept; classification rule stated identically in Goal/Tasks/Edge Cases
- S4 (Numeric-Parameter Sweep): swept for AGE_DAYS default 7 and summary threshold 5 — each appears once
- S5 (Scope-vs-Analysis Check): swept; no Add/Modify verbs target OUT-scoped files (settings.json.template explicitly OUT)

## Definition of Done
- [x] All tasks checked off
- [x] Self-test all green (15/15, 2026-06-10)
- [x] Script synced to ~/.claude/scripts/ (diff-verified, content-identical to committed blob d4132be)
- [x] Completion report appended to this plan file

## Completion Report

_Generated by close-plan.sh on 2026-06-10T13:18:14Z._

### 1. Implementation Summary

Plan: `docs/plans/worktree-hygiene-sweeper-2026-06-09.md` (slug: `worktree-hygiene-sweeper-2026-06-09`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh`
- `docs/plans/worktree-hygiene-sweeper-2026-06-09.md`

Commits referencing these files:

```
8687fe3 chore(plans): worktree-hygiene-sweeper closure evidence — 3x mechanical evidence + path-anonymized nl report-only run (14wt/0 safe-prune) + self-test 15/15
ebc5cf8 feat(scripts): worktree-hygiene-sweep — classify/report/approval-gated prune of accumulated worktrees
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

- close-plan.sh staged the rename with PRE-FLIP content and did not commit (the
  known rename-only-commit defect class, recurrence of the 83c2564 fix-up): the
  Status flip + completion report existed on disk but not in the staged blob,
  and task checkboxes were never flipped despite per-task PASS verdicts. Fixed
  in the closure commit by restaging true content + flipping checkboxes against
  the verified evidence.
- The downstream-repo report-only run is NOT committed here: its raw output
  embeds downstream-project identifiers the harness-hygiene denylist forbids.
  It ran clean (exit 0, report-only, nothing pruned) and is captured in the
  closing session's return. The committed nl report run is path-anonymized
  (`<projects-root>` substitution) for the same reason.

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

- `--self-test`: 15/15 PASS (safe-prune detected; dirty never safe; unique-patch
  never safe; prune without APPROVE refuses exit 3; approved prune removes only
  the safe entry via `worktree remove` + `branch -d` with audit-log line;
  primary never touched; `--session-summary` silent at <=5 worktrees).
- Real report-only runs 2026-06-10: neural-lace (14 worktrees classified, 0
  SAFE-PRUNE, 8-stash census, exit 0 — committed path-anonymized at
  `docs/plans/worktree-hygiene-sweeper-2026-06-09-evidence/report-run-nl-2026-06-10.txt`)
  and the originating downstream repo (post-cleanup state, exit 0, nothing
  pruned — output in session return only, per harness-hygiene).
- Mirror sync verified: `~/.claude/scripts/worktree-hygiene-sweep.sh` raw
  content hashes to the committed canonical blob (`d4132be`).
- Structured evidence: `docs/plans/worktree-hygiene-sweeper-2026-06-09-evidence/{1,2,3}.evidence.json`, all PASS.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
