# Evidence — scope-enforcement-gate rebase/merge full-skip

Execution evidence for `docs/plans/scope-gate-rebase-exemption.md`. All tasks
verified mechanically; this is the acceptance artifact (harness-internal,
acceptance-exempt).

## Self-test (19/19 PASS)

`bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test`:

```
self-test (1) all-files-in-scope: PASS
self-test (2) system-managed-archive-exempt: PASS
self-test (3) one-file-out-of-scope: PASS (correctly blocked)
self-test (4) multiple-files-out-of-scope: PASS (correctly blocked)
self-test (5) plan-missing-scope-section: PASS (correctly blocked)
self-test (6) plan-scope-placeholder-only: PASS (correctly blocked)
self-test (7) glob-pattern-match: PASS
self-test (8) glob-pattern-non-match: PASS (correctly blocked)
self-test (9) in-flight-scope-update-match: PASS
self-test (10) backward-compat-no-inflight-section: PASS
self-test (11) three-option-message: PASS (correctly blocked, three options present, no waiver references)
self-test (12) new-plan-staged-claims-scope: PASS
self-test (13) merge-context-supabase-migration-allowed: PASS
self-test (14) no-merge-context-supabase-migration-blocked: PASS (correctly blocked)
self-test (15) merge-resolution-full-skip: PASS (merge context full-skips scope-check)
self-test (16) merge-context-prisma-migration-allowed: PASS
self-test (17) rebase-apply-full-skip: PASS
self-test (18) rebase-merge-precedence: PASS
self-test (19) merge-branch-message-full-skip: PASS

self-test summary: 19 passed, 0 failed (of 19 scenarios)
```

Signal preserved: scenarios 3/4/5/6/8/11 still BLOCK real scope violations in normal
commit context; s14 still blocks an out-of-merge migration (the merge-context exemption
does NOT apply outside a merge/rebase).

## Real `git rebase` conflict invocation (full-skip + audit log)

A genuine `git rebase` over a conflicting out-of-scope file (`src/shared.ts`, not in the
plan's `## Files to Modify/Create`), then invoking the live gate on the
rebase-continuation commit:

```
[scope-enforcement-gate] rebase-in-progress detected — scope-check skipped (commit stages files from git's replay/merge, not author-chosen plan scope). Logged to ~/.claude/state/scope-gate-exemptions.log
exit=0
```

Sample exemption-log line written to `~/.claude/state/scope-gate-exemptions.log`:

```
2026-05-27T23:31:15Z	reason=rebase-in-progress	head=c6b5d85	branch=HEAD	repo=<repo-root>
```

(`branch=HEAD` is expected — HEAD is detached during a rebase. Non-rebase merge commits log
the real branch name.)

## Live-mirror sync

`diff -q adapters/claude-code/hooks/scope-enforcement-gate.sh ~/.claude/hooks/scope-enforcement-gate.sh`
→ byte-identical; live-mirror self-test 19/19 PASS.
