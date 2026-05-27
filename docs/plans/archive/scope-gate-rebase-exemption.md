# Plan: scope-enforcement-gate rebase/merge full-skip
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: single-hook change to scope-enforcement-gate.sh (PreToolUse Bash); no new components
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal scope-gate change; the gate's 19-scenario --self-test plus a real git-rebase invocation are the acceptance artifacts (no product user surface)
Backlog items absorbed: none

## Goal
`scope-enforcement-gate.sh` false-blocks `git commit` during rebase- and merge-conflict
resolution, because such commits stage files git's replay/merge brings in (e.g. origin/master
applied to a PR branch) rather than author-chosen plan scope. The only prior escape was
`--no-verify` (forbidden). Add context-aware detection so the gate full-skips when a rebase
or merge is in progress, logging each exemption for audit. This unblocks the Circuit aging
PRs (P0 customer-launch work) without `--no-verify`.

## Scope
- IN: `adapters/claude-code/hooks/scope-enforcement-gate.sh` — add rebase/merge full-skip detection + self-test scenarios.
- IN: `docs/harness-architecture.md` — changelog note for the behavior change.
- OUT: the migration-only HARNESS-GAP-27 IN_MERGE code (retained as documented defense-in-depth; subsumed by the earlier full-skip when MERGE_HEAD is present).
- OUT: any downstream product code; any other hook.

## Tasks
- [ ] 1. Add rebase/merge full-skip block to the gate (detect `$GIT_DIR/rebase-apply`, `$GIT_DIR/rebase-merge`, `$GIT_DIR/MERGE_HEAD`, or `-m "Merge branch …"` message); log exemptions to `~/.claude/state/scope-gate-exemptions.log`. — Verification: mechanical
- [ ] 2. Update self-test: change s15 to merge-resolution-full-skip; add s17 (rebase-apply), s18 (rebase-merge precedence), s19 (Merge-branch message); 19/19 pass. — Verification: mechanical
- [ ] 3. Architecture-doc changelog note. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — rebase/merge full-skip detection + audit log + self-test scenarios 15/17/18/19.
- `docs/harness-architecture.md` — changelog entry (HARNESS-GAP-29).
- `docs/plans/scope-gate-rebase-exemption.md` — this plan (self-claiming).

## Testing Strategy
- `bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test` → 19/19 pass.
- Real `git rebase` conflict + invoke the gate → `rebase-in-progress detected`, exit 0, exemption logged.
- Real scope violation in a NORMAL (non-rebase/merge) commit still BLOCKS (self-test s3/s4/s5/s6/s8/s11; out-of-merge migration still blocks via s14).

## Walking Skeleton
The thinnest end-to-end slice is the self-test: one detection branch + one PASS scenario.
The full slice (all four detection signals + four scenarios + a real rebase invocation) is
implemented directly since the change is a single bash function and its self-test.

## Decisions Log
### Decision: merge-resolution commits now FULL-skip (supersedes HARNESS-GAP-27 narrow targeting)
- **Tier:** 1
- **Status:** proceeded with recommendation (Misha authorized the fix; behavior change flagged in report)
- **Chosen:** A rebase- or merge-in-progress commit full-skips the scope check.
- **Alternatives:** Keep HARNESS-GAP-27's migration-only merge exemption and add rebase-only full-skip — rejected because merging master into a PR branch stages many non-migration files (app code, configs, docs), so migration-only is insufficient for the actual P0 unblock.
- **Reasoning:** During a rebase/merge the staged set is dictated by git's replay/merge, not the author's per-file choice; scope-checking author-uncontrolled files is meaningless. Self-test s15 was updated from "narrow targeting blocks non-migration" to "merge-resolution full-skip".
- **To reverse:** one-commit revert restores narrow targeting.

## Definition of Done
- [ ] All tasks shipped
- [ ] 19/19 self-test pass
- [ ] Real-rebase invocation logs an exemption and exits 0
- [ ] Architecture doc updated
- [ ] Live `~/.claude/` mirror synced (byte-identical)
- [ ] Completion report appended; Status → COMPLETED

## Completion Report

### 1. Implementation Summary
All three tasks shipped in commit `fb2a806` (`feat(scope-gate): full-skip scope check during rebase/merge conflict resolution`):
- Task 1: rebase/merge full-skip detection block added after REPO_ROOT validation (`$GIT_DIR/rebase-apply`, `$GIT_DIR/rebase-merge`, `$GIT_DIR/MERGE_HEAD`, `-m "Merge branch …"` fallback) + audit log to `~/.claude/state/scope-gate-exemptions.log`.
- Task 2: self-test — s15 changed to merge-resolution-full-skip; s17/s18/s19 added; count 16→19; 19/19 pass.
- Task 3: `docs/harness-architecture.md` changelog entry (HARNESS-GAP-29).
- Tasks left unchecked per the verifier mandate (no manual checkbox flips); mechanical verification recorded in the evidence sibling. Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
Merge-resolution commits now FULL-skip, superseding HARNESS-GAP-27's migration-only merge exemption (see Decisions Log). One-commit revert restores narrow targeting. No other deviations.

### 3. Known Issues & Gotchas
The migration-only `IN_MERGE` code below the full-skip is now effectively subsumed whenever `MERGE_HEAD` is present (retained as documented defense-in-depth). The `-m "Merge branch …"` message fallback is a weaker signal than the filesystem-state checks and is a (low-risk, task-requested) cheap-evasion surface comparable to the already-available `--no-verify`.

### 4. Manual Steps Required
None for the PR. Cross-repo: this lands on Pocket-Technician/neural-lace master; the mishanovini mirror receives it when the mirror Action enables (see SCRATCHPAD).

### 5. Testing Performed
19/19 `--self-test`; real `git rebase` conflict → full-skip + audit-log line; live `~/.claude/` mirror byte-identical + 19/19. Evidence: sibling `*-evidence.md`.

### 6. Cost Estimates
n/a — harness-internal bash hook; no runtime cost.
