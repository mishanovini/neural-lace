# Harness-improvement proposal 099: branch-name-format-gate (FIXTURE)

Title: Block commits on branches whose names don't match the WIP prefix list
Date: 2026-06-08
Class of failure: branch-naming-drift — sessions create branches outside the
documented `wip/ feat/ fix/ salvage/ backup/ rebase/ reconverge/ sync/` prefix set,
defeating the stale-branch surfacing policy that keys on those prefixes.

## Existing controls that should have caught this
`branch-hygiene.md` documents the prefix list but is Pattern-class only —
`session-start-git-freshness.sh` is also Pattern-class documentation with no
mechanical check, so nothing fires when a misnamed branch is created.

## Why current mechanisms missed this (root-cause statement)
The prefix list lives in a rule and in one SessionStart surfacer; neither binds at
branch-creation time. The latent cause is that branch creation has no PreToolUse
surface in the harness today.

## Proposed change (concrete diff or file creation)
New hook `branch-name-format-gate.sh` (PreToolUse Bash on `git checkout -b|git
branch|git switch -c`): BLOCK (exit 2, block-mode, no warn mode, no escape hatch —
naming discipline should be absolute) any new branch whose name does not match the
prefix allowlist. Self-test: one scenario — a `feat/foo` branch is allowed.

## Testing strategy
Run `--self-test` (the allowed-branch scenario) and create one `feat/` branch
manually to confirm the gate stays silent.
