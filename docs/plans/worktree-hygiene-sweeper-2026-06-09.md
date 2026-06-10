# Plan: Worktree-Hygiene Sweeper — make worktree accumulation visible-and-cleanable
Status: ACTIVE
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

- [ ] 1. Author `worktree-hygiene-sweep.sh` — classification (SAFE-PRUNE vs HOLDS-CONTENT via `git cherry` unique-patch count + dirty count + age), report default, `--prune` gated on `WORKTREE_SWEEP_APPROVE=1` with `branch -d` second guard + audit log, stash census, `--session-summary`, Bash 3.2-portable, Windows drive-colon-safe — Verification: mechanical
- [ ] 2. `--self-test` covering: safe-prune detected; dirty never safe; unique-patch never safe; prune without APPROVE refuses; prune with APPROVE removes only the safe one; primary worktree never touched — Verification: mechanical
- [ ] 3. Real REPORT run against neural-lace + the originating downstream repo (no prune) + sync to `~/.claude/scripts/` with diff verify — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` — the sweeper (new)
- `docs/plans/worktree-hygiene-sweeper-2026-06-09.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

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
- [ ] All tasks checked off
- [ ] Self-test all green
- [ ] Script synced to ~/.claude/scripts/ (diff-verified)
- [ ] Completion report appended to this plan file
