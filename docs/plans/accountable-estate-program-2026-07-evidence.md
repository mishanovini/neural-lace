# Evidence Log - Accountable Estate Program (build plan, cross-machine)

## Task T1 - Read-only estate inventory + daily brief

EVIDENCE BLOCK
==============
Task ID: T1
Task description: Read-only estate inventory + daily brief. New janitor scheduled task (deterministic bash) reducing existing truth (heartbeats, process table, git worktree list, signal-ledger tail, ask-registry) -> snapshot.json + rendered brief, incl. orphaned-worktree/branch found-list. Outcome metric: "what is running and who asked" answerable from one surface in <30 s. Verification: full.
Verified at: 2026-07-28T12:15:00Z
Verifier: task-verifier agent

Oracle: specified - the plan's own outcome metric ("what is running and who asked" answerable from one surface in <30 s), exercised live against this machine's REAL estate snapshot; classification delegates to the pre-existing shared oracle (session-heartbeat-lib.sh hb_classify, sourced at estate-janitor.sh:169, never re-implemented) and perf-tick-snapshot.sh's read-only pts_collect_processes (sourced :171).

Comprehension-gate: skipped - rung field missing (plan header has no rung:; treated as rung 0 per Decision 020a; builder articulation noted in worktree commit de66463, not load-bearing at rung 0)

Checks run:
1. Task-text match: plan lines 26-31 match the invocation description verbatim. Result: PASS
2. Commits on master. Command: git log --oneline origin/master piped to grep db1449c/f13178c. Output: both present. Result: PASS
3. Janitor self-test replayed by verifier. Command: bash adapters/claude-code/scripts/estate-janitor.sh --self-test. Output: self-test summary: 13 passed, 0 failed / self-test: OK (real 4m08s wall on this fork-taxed machine; user+sys ~46s). Result: PASS
4. Brief self-test replayed by verifier. Command: bash adapters/claude-code/scripts/estate-brief.sh --self-test. Output: self-test summary: 17 passed, 0 failed / self-test: OK (real 10.9s). Result: PASS
5. Sandbox integrity (no real ~/.claude writes by self-tests). Command: stat -c mtime fingerprint of ~/.claude/state/estate/* before/after both self-tests. Output: identical (snapshot.json mtime 1785237911, sole file); janitor Scenario 9 additionally asserts tempdir sandboxing. Result: PASS
6. OUTCOME METRIC - real snapshot exists. Command: jq counts over ~/.claude/state/estate/snapshot.json. Output: generated_at 2026-07-28T11:25:09Z, 17 sessions, 94 worktrees, 92 orphaned worktrees, 142 orphaned branches, all five degraded flags false. Result: PASS
7. OUTCOME METRIC - one-surface read path timed by verifier. Command: time bash adapters/claude-code/scripts/estate-brief.sh. Output: real 0m2.279s, exit 0; rendered brief carries RUNNING (17 sessions with classify/branch/age), ASKED (5 active asks with id/summary/repo), ORPHANED WORKTREES (92, row-capped +72 more), ORPHANED BRANCHES (142); header prints "generated 2026-07-28T11:25:09Z (44m ago)" so staleness is honestly disclosed. Result: PASS. Verifier ruling on "<30 s from one surface": MET - the surface answers the question in 2.3 s from the latest snapshot and discloses snapshot age inline; the 12m36s generation cycle is a daily background cost, tracked as docs/backlog.md ESTATE-T1-HB-CLASSIFY-PERF-01 (row confirmed at backlog line 1253).
8. Read-only guarantee (runtime path). Only runtime write is the janitor's OWN snapshot.json via tmp+mv (estate-janitor.sh:674-684, ej_write_snapshot); all rm/mv/git-mutation hits are inside _ej_self_test fixtures (lines 707+, env-redirected to a mktemp sandbox); process collection delegates to read-only pts_collect_processes, never pts_reap_orphans (header :35; grep confirms no call). Brief writes only optional brief.txt under --write (self-test Scenario 5, sandboxed). Result: PASS
9. Installer ships WITHOUT registering. Register-ScheduledTask (install-estate-janitor-task.ps1:186) guarded by ShouldProcess; -WhatIf dry-run prints intent only; grep of install.sh / session-start-auto-install.sh / hooks finds zero auto-invocation; Get-ScheduledTask -TaskName NL-EstateJanitor on this machine: NOT REGISTERED. Result: PASS
10. Manifest entries. manifest.json ids estate-janitor (line 2707) + estate-brief (line 2737): selftest true, blocking false, kind writer, honest golden_scenario / fp_expectation / honesty_rationale. Result: PASS
11. Program rule 3 (retirement disposition). estate-janitor retirement_condition (manifest line 2733) logs the rule-3 check explicitly: candidates evaluated (od_sessions - different consumer, stays; worktree-hygiene-sweep / supervisor-tick - mutation-adjacent alert channels, retiring them pre-T3/T4 would drop the only stranded-worktree alert channel), none redundant this slice; retirement deferred with a named future condition (T5+ store consolidation). Honest-disposition reading accepted over ritual retirement (constitution section 1). Result: PASS (judgment call, reasoning cited)

Runtime verification: test adapters/claude-code/scripts/estate-janitor.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/estate-brief.sh::--self-test
Runtime verification: file C:/Users/misha/.claude/state/estate/snapshot.json::generated_at
Runtime verification: file adapters/claude-code/scripts/install-estate-janitor-task.ps1::ShouldProcess
Runtime verification: functionality-verifier T1::SKIP (rationale: no Task tool in this verifier environment; the user-shaped exercise was executed inline by the verifier - real brief rendered and timed at 2.279s against the real snapshot, both self-tests replayed; plan is acceptance-exempt: harness-internal, maintainer-is-user per constitution section 4)

DEPENDENCY TRACE
================
Step 1: janitor run reduces real estate truth -> snapshot.json
  Verified at: estate-janitor.sh:690-697 (ej_run) + real snapshot generated_at 2026-07-28T11:25:09Z (17/94/92/142, zero degraded)
Step 2: brief reads snapshot.json -> renders one text surface
  Verified at: verifier-timed run, real 2.279s, exit 0, scratchpad real-brief.txt capture
Step 3: operator answers "what is running and who asked" from that one surface
  Verified at: rendered RUNNING (17 sessions classified) + ASKED (5 active asks) sections in the same output
Step 4 (ship-only tail): installer exists but registers nothing
  Verified at: ShouldProcess guard at :186 + Get-ScheduledTask NOT REGISTERED + zero auto-invocation greps

Git evidence:
  Files modified in recent history (all on origin/master):
    - adapters/claude-code/scripts/estate-janitor.sh (db1449c 2026-07-28, f13178c 2026-07-28)
    - adapters/claude-code/scripts/estate-brief.sh (db1449c, f13178c)
    - adapters/claude-code/scripts/install-estate-janitor-task.ps1 (db1449c)
    - adapters/claude-code/manifest.json (db1449c)
    - docs/backlog.md ESTATE-T1-HB-CLASSIFY-PERF-01 (db1449c)

Verdict: PASS
Confidence: 9
Reason: PROVEN: verifier independently replayed both self-tests (13/13, 17/17), confirmed the real snapshot (2026-07-28T11:25:09Z, 17 sessions / 94 worktrees / 92 orphans, zero degraded), timed the real one-surface read path at 2.279s (metric met with staleness disclosed in-header), fingerprint-proved the self-tests wrote nothing to real ~/.claude state, code-verified zero estate mutations on the runtime path, and confirmed the installer ships unregistered (ShouldProcess-guarded, no auto-invocation, task absent from Task Scheduler). Adversarial probes that did not break it: mutation grep sweep, sandbox fingerprint diff, scheduled-task registry query, shared-oracle delegation check.
