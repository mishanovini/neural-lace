---
title: scope-enforcement-gate resolves repo from session cwd, not cd target
date: 2026-06-09
type: process
status: pending
auto_applied: false
originating_context: workstreams consolidation closure — committing a summary file to the sibling workstreams-coordination repo from a neural-lace-rooted main session
decision_needed: Should the scope-enforcement-gate resolve the target repo from the git command (parse `-C <dir>` / cwd-after-cd) before applying the no-plan-repo skip, OR should hook-sync always pull from master to prevent regressions of the gate itself?
predicted_downstream:
  - adapters/claude-code/hooks/scope-enforcement-gate.sh
  - the hook-sync workflow (whatever propagates adapters/claude-code/hooks/* to ~/.claude/hooks/*)
---

## What was discovered

The `scope-enforcement-gate.sh` PreToolUse Bash hook detects the active repo
from the **session cwd**, not from the actual `cd <other-repo>` target embedded
inside the bash command it is gating.

Consequence: a main session whose cwd is `neural-lace` (which HAS `docs/plans/`
and an active plan) CANNOT commit to the sibling `workstreams-coordination` repo
via a `cd ~/claude-projects/workstreams-coordination && git commit ...` command.
The gate resolves the repo as neural-lace, checks the staged coordination file
against neural-lace's plan scope, finds it out-of-scope, and BLOCKS — even though
the gate's own no-plan-repo skip WOULD apply if it resolved the real target repo
(workstreams-coordination has no `docs/plans/`, so the skip should fire).

Workflow-agent builders are unaffected because they run with a different cwd
(rooted in the target repo or its worktree), so the cwd-based resolution happens
to match the commit target for them. The failure is specific to a session whose
cwd is one repo while it commits into a sibling repo via an inline `cd`.

(This builder session is itself rooted in a Pocket-Technician worktree, not the
neural-lace main session, which is why its `cd ~/claude-projects/workstreams-coordination`
commit in this same closure succeeded — confirming the failure is conditional on
the session cwd being a repo-with-an-active-plan, exactly as described.)

## Why it matters

Cross-repo commits from a main orchestrator session silently hit a gate that was
never meant to fire for them. The no-plan-repo skip exists precisely so that
commits to repos without `docs/plans/` (like workstreams-coordination) are
unconstrained — but the skip is keyed off the WRONG repo, so it never gets a
chance to apply. The operator either has to launch a builder in the target repo's
cwd or bypass with `--no-verify`, both of which are friction for what should be a
clean no-op-skip path.

## Second, related finding — live-mirror regression

A later builder's hook-sync regressed the live `~/.claude/hooks/scope-enforcement-gate.sh`
away from master's fixed version (the version that already carries the no-plan-repo
skip + the rebase/merge full-skip from HARNESS-GAP-29). It was re-synced from master
on 2026-06-09. Root shape: hook-sync does not verify byte-identity against master
after syncing, so a stale or mid-edit canonical copy can overwrite the live mirror
with an older behavior. This is the two-layer-config drift failure
(`adapters/claude-code/hooks/*` canonical vs `~/.claude/hooks/*` live) that
`harness-maintenance.md` warns about, manifesting on a security-relevant gate.

## Options

A. Make the gate resolve the target repo from the git command itself — parse a
   `-C <dir>` flag and/or detect a `cd <dir> && git ...` prefix, resolve THAT
   directory's repo root, and apply the no-plan-skip check against the target
   repo rather than the session cwd. Tradeoff: more parsing surface in the hook
   (must handle `cd`, `pushd`, `git -C`, chained `&&`/`;`); a parse miss could
   re-introduce the wrong-repo resolution. Closes the cross-repo-commit failure
   at the source.

B. Have hook-sync always pull from master (never from a possibly-dirty canonical
   working copy) AND verify byte-identity against master after sync. Tradeoff:
   addresses the regression (second finding) but NOT the primary cwd-resolution
   failure; these are two distinct bugs that happen to have surfaced together.

C. Both A and B — they address different root causes (A = gate logic; B = sync
   integrity). Tradeoff: more work, but they are independent and non-conflicting.

## Recommendation

C — they are orthogonal. A fixes the gate's cross-repo blind spot; B prevents the
live mirror from silently regressing to a pre-fix gate. Doing only A leaves the
regression vector open; doing only B leaves the cwd-resolution failure open.
Both are reversible (single-file hook edit + a sync-workflow guard), so this is a
reversible decision per discovery-protocol — but it is being left `pending` for
Misha because it touches a security-relevant gate's parsing surface and the
hook-sync workflow, where a parse regression or sync change has broad blast radius
across every commit in every repo.

## Decision

(pending — awaiting Misha)

## Implementation log

(empty — not yet decided)

## Additional live repros (appended 2026-06-09, orchestrator-prime session)
1. **`git -C <other-repo> commit` passes; `cd <other-repo> && git commit` blocks** — observed on the
   trust-instigators amend (blocked in `cd &&` form, succeeded via `git -C`). The gate evaluates in the
   session/process cwd, and its `^git commit` segment matching also misses `git -C` forms.
2. **Salvage builder (wf_195f11bc-e9c) repro**: Bash-tool commits in circuit worktrees blocked against
   the MAIN checkout's unrelated staged files. Builder routed around it via the **PowerShell tool — the
   gate's matcher is Bash-only, so PowerShell `git commit` is entirely ungated.** That is BOTH a third
   repro of the cwd bug AND a separate enforcement gap (PreToolUse matcher does not cover the
   PowerShell tool). Repo-level git hooks still ran; no --no-verify was used.

Implication for the fix: resolve the TARGET repo (parse `-C` / `cd` in the command, or run git in the
command's effective directory), AND extend the matcher to the PowerShell tool — otherwise the gate is
trivially evadable by tool choice.
