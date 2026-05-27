# spawn-worktree.sh verification log — 2026-05-26
# Captured by the worktree-spawn-primitive session (commit-producing, isolated).

================================================================
1. SELF-TEST (9 scenarios)
================================================================
warning: in the working copy of 'f.txt', LF will be replaced by CRLF the next time Git touches it
SELFTEST PASS (read-only skips; commits+unknown isolate; commits+alone skip; apply creates session/<slug>; idempotent reuse; already-isolated short-circuit; --branch override; --remove; bad-type rejected)

================================================================
2. COLLISION REPRODUCTION (the root cause this primitive prevents)
   shared checkout -> B's commit lands on A's branch; worktrees fix it
================================================================
warning: in the working copy of 'f.txt', LF will be replaced by CRLF the next time Git touches it
[B] on B-branch
[A] checked out A-branch (flips shared HEAD)
warning: in the working copy of 'b.txt', LF will be replaced by CRLF the next time Git touches it
[B] committed -> landed on: A-branch 
    (B-branch has B's work? 0 — expected 0: the collision)

================================================================
3. LIVE DECISION — 3 session types against the real repo (dry-run)
================================================================
--- read-only ---
DECISION: no-isolation (type=read-only, concurrent=unknown)
  reason: read-only session mutates no HEAD/index; isolation is pure overhead
  use the main checkout as your cwd: C:/Users/misha/dev/Pocket Technician/neural-lace
--- commits ---
DECISION: isolate (type=commits, concurrent=unknown)
  reason: commits: a sibling checkout flips the shared HEAD -> commit lands on the wrong branch
  WOULD-CREATE: git -C "C:/Users/misha/dev/Pocket Technician/neural-lace" worktree add "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/fix-y" -b "session/fix-y" "origin/HEAD"
  (dry-run — re-run with --apply to create. then: cd "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/fix-y")
--- branch-switch ---
DECISION: isolate (type=branch-switch, concurrent=unknown)
  reason: branch-switching: the canonical shared-HEAD collision (proven 2026-05-26)
  WOULD-CREATE: git -C "C:/Users/misha/dev/Pocket Technician/neural-lace" worktree add "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/build-z" -b "session/build-z" "origin/HEAD"
  (dry-run — re-run with --apply to create. then: cd "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/build-z")

================================================================
4. APPLY + REMOVE round-trip against the real repo
================================================================
created cwd: C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/demo-verify
branch:      session/demo-verify
based on:    fff2de3  (origin/master=fff2de3)
spawn-worktree.sh: removed worktree C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/demo-verify
spawn-worktree.sh: deleted merged branch session/demo-verify
still registered? 0  (expected 0)

================================================================
5. DOGFOOD — this session's own worktree short-circuits (no nesting)
================================================================
DECISION: already-isolated — current working tree (C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/worktree-spawn-primitive) is a worktree, not the main checkout; not nesting
