# Plan: ci/server-side-enforcement — mirror the local hook chain in CI so `--no-verify` cannot bypass the perimeter
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal CI wiring; no user-observable runtime — the verification artifact is the workflow runs reported by GitHub Actions on a draft PR.
Backlog items absorbed: none

## Goal

The expert review of 2026-05-23 named `--no-verify` as the biggest security
gap in the harness: "the hook chain is only as strong as its non-bypassability,
and `git commit --no-verify` / `git push --no-verify` can skip the perimeter
entirely." This plan adds a single workflow that runs the most-load-bearing
local hooks server-side, so the same checks run regardless of whether the
author bypassed them locally. Once branch-protection requires this check to
pass, a PR with a credential leak, hygiene violation, or skipped test cannot
merge no matter what the local commit path looked like.

## User-facing Outcome

For every PR (and every push to master), the new workflow
`server-side-enforcement.yml` runs five independent jobs:

1. `credential-scan` — invokes `pre-push-scan.sh` against the PR's base..head
   diff range. Fails if any credential pattern matches.
2. `harness-hygiene` — invokes `harness-hygiene-scan.sh` on the added/modified
   files in the diff. Fails on denylist or heuristic matches.
3. `no-test-skip` — runs `no-test-skip-gate.sh --self-test` plus a diff-grep
   for newly-introduced `.skip()` / `xtest()` / `xit()` in test files without
   an issue reference.
4. `plan-edit-validator` — runs `plan-edit-validator.sh --self-test` so a
   refactor that breaks the evidence-first-checkbox-flip contract surfaces
   immediately.
5. `pr-template-redundancy` — re-runs the existing PR-template validator so
   the server-side suite is self-contained (the same check is also wired by
   `pr-template-check.yml` for legacy compatibility).

A `summary` job aggregates the results so a single check-name on the PR
(`Server-side enforcement / All-checks summary`) is the candidate for
branch-protection's required-checks list.

## Scope

- IN: `.github/workflows/server-side-enforcement.yml` (new), this plan file.
- OUT: README update (deliberately deferred — Task 1's PR also touches
  README and a parallel README change here would create a merge conflict;
  the maintainer can fold a one-paragraph mention into the Task 1 README
  section after both PRs merge); branch-protection-rule wiring (manual
  repo-admin action; documented in the PR body so the maintainer can flip
  it after merge); the diagnostic-evidence check (lands in Task 3's PR via
  the PR-template extension which this workflow's `pr-template-redundancy`
  job already calls).

## Tasks

- [ ] 1. Land workflow + README addition + plan, open draft PR — Verification: mechanical

## Files to Modify/Create

- `.github/workflows/server-side-enforcement.yml` — five-job CI workflow
  mirroring the local hook chain.
- `adapters/claude-code/scripts/git-no-verify-friction.sh` — local
  `git` shell-function wrapper intercepting `commit --no-verify` /
  `-n`, requiring a literal confirmation string, logging every attempt
  (added 2026-05-23 per in-flight scope update).
- `adapters/claude-code/scripts/install-git-friction.sh` — installer
  that wires the wrapper into the user's bash/zsh rc files. Idempotent;
  ships `--check` and `--uninstall` modes plus a 6-case `--self-test`.
- `docs/no-verify-friction.md` — operator-facing documentation of the
  wrapper, the install/uninstall procedure, what gets logged, and the
  three-layer defense story.
- `docs/plans/ci-server-side-enforcement-2026-05-23.md` — this plan file.

## Assumptions

- The local hooks `pre-push-scan.sh`, `harness-hygiene-scan.sh`,
  `no-test-skip-gate.sh`, and `plan-edit-validator.sh` already exist and ship
  `--self-test` blocks (confirmed by grep against the current tree).
- `pre-push-scan.sh` reads stdin in git pre-push format
  `<local_ref> <local_sha> <remote_ref> <remote_sha>` — the workflow synthesizes
  exactly one such line per run using the PR's base/head SHAs.
- `harness-hygiene-scan.sh` accepts a list of file paths as positional args
  (confirmed by reading its header comment: "INVOCATION MODES … 3. Specific
  files").
- `no-test-skip-gate.sh` and `plan-edit-validator.sh` ship `--self-test` flags
  whose verdict matches the rule's stated contract (locally-verified before
  this PR).
- GitHub Actions Ubuntu runners ship modern bash, git, and jq. The same
  assumption Task 1 already exercised.

## Edge Cases

- **First commit on a new branch.** `git rev-parse HEAD~1` may fail. The
  workflow handles this via `|| git rev-parse --verify HEAD` fallback so the
  workflow doesn't crash on initial-commit pushes.
- **Force-push or rebase.** The PR base..head diff range may include unrelated
  commits if the branch was rebased. This is correct behavior — the scanner
  should examine every commit between base and head.
- **Deleted files.** `git diff --diff-filter=AM` excludes deletions. Deleting
  a credential file is not a leak.
- **Large diff.** The PR-template-check workflow has a 1-minute timeout; this
  workflow uses 5 for credential-scan and harness-hygiene since they walk
  every commit-diff in the range.
- **Branch-protection not yet configured.** Documenting it in the PR body
  alerts the maintainer; merging this PR does not by itself enforce branch
  protection (that's a repo-admin action).

## Testing Strategy

- Local: invoke each hook's `--self-test` to confirm green (already done by
  Task 1's background sweep).
- Manual: invoke the credential-scan job's stdin synthesis locally to confirm
  the scanner accepts the format we're producing — verified during plan
  authoring with `bash adapters/claude-code/hooks/pre-push-scan.sh --help`
  semantics check.
- CI: opening this draft PR is the test — the workflow runs against itself
  and reports pass/fail.

## In-flight scope updates

- 2026-05-23: Misha follow-up to the original Task 2 brief added a
  local-shell `--no-verify` friction wrapper as the complement to the
  server-side gate. Three new files land on this branch:
  `adapters/claude-code/scripts/git-no-verify-friction.sh` (the wrapper —
  intercepts `git commit --no-verify` / `-n`, requires literal
  `I-AM-BYPASSING-SAFETY-DELIBERATELY` confirmation, logs every
  attempt to `~/.claude/logs/no-verify-attempts.log`, 10-case
  `--self-test`); `adapters/claude-code/scripts/install-git-friction.sh`
  (one-time installer that wires the wrapper into the user's bash/zsh
  rc files; idempotent; 6-case `--self-test`); `docs/no-verify-friction.md`
  (operator docs + three-layer defense diagram). Path-of-least-resistance
  principle: the server-side gate is the actual floor; the local
  friction makes the floor a rare-fire safety net rather than the
  only line of defense.

## Decisions Log

### Decision: one workflow with five jobs vs five separate workflows
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** one workflow with five jobs + a `summary` job that aggregates
  the verdicts.
- **Alternatives:** five separate workflows; pros = one badge per check.
  Cons = branch-protection becomes verbose ("require five separate
  checks"); a failure in any one shows up the same way as one summary check
  but with more setup.
- **Reasoning:** the `summary` job is the candidate for branch-protection's
  required-checks list — a single check that is GREEN only when all five
  underlying checks are green. This keeps branch-protection clean and lets
  the operator add new sub-checks without re-configuring branch protection.
- **Checkpoint:** n/a (single commit)
- **To reverse:** delete `server-side-enforcement.yml`.

### Decision: re-run the PR-template validator inside this workflow even though `pr-template-check.yml` already does it
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** re-run, scoped to PR events only (`if: github.event_name == 'pull_request'`).
- **Alternatives:** rely solely on the existing dedicated workflow.
- **Reasoning:** this workflow is intentionally the "single PR-required check
  surface" for branch-protection. If the maintainer eventually wires
  branch-protection to require *only* this workflow, removing the dedicated
  pr-template-check.yml later becomes a one-line action without breaking the
  PR-template enforcement.
- **Checkpoint:** n/a
- **To reverse:** delete the `pr-template-redundancy` job; pr-template-check.yml
  continues to run independently.

## Definition of Done

- [ ] Workflow lands on the branch and is referenced from the PR body.
- [ ] Draft PR is open against master, NOT merged.
- [ ] The PR body documents the branch-protection action required for the
      maintainer to actually enforce the new checks at merge time.
- [ ] The PR body documents the deferred README addition (one paragraph)
      that the maintainer can fold into Task 1's CI section after both
      land.
