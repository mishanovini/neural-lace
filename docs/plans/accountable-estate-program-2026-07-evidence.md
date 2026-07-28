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

## Task T2 - Ask SLAs (deadline/default-action/SLA verbs + brief SLA panel)

EVIDENCE BLOCK
==============
Task ID: T2
Task description: Ask SLAs: deadline/default-action/SLA verbs on ask-registry + the brief's <=5-asks panel. Outcome metric: zero operator-asks silently older than their deadline in a 14-day window. Verification: full.
Verified at: 2026-07-28T21:40:00Z
Verifier: task-verifier agent

Oracle: specified - the plan/design contract (design section 2's operator-ask fields: "what, why, deadline, default-action, SLA state... re-surfaced every brief until closed; breaching SLA escalates visually, never silently expires") exercised by the VERIFIER'S OWN fixture round-trip against a sandboxed registry (never builder-authored assertions alone) plus the real production surfaces read-only.

Comprehension-gate: skipped - rung field missing (plan header has no rung:; treated as rung 0 per Decision 020a, same disposition as T1)

Checks run:
1. Task-text match: plan lines 32-34 match the invocation description verbatim. Result: PASS
2. Commit on master. Command: git log --oneline master | head -1. Output: 2be51c1 feat(accountable-estate): T2 ask SLAs. Main checkout in sync with origin/master; all six claimed files in the squash diff. Result: PASS
3. VERIFIER FIXTURE ROUND-TRIP (sandboxed via documented env vars ASK_REGISTRY_STATE_DIR / PROGRESS_LOG_STATE_DIR / ASK_REGISTRY_MIRROR_PATH + HARNESS_SELFTEST=1; never the real registry):
   a. set-deadline normalizes "2026-07-27 00:00:00" to "2026-07-27T00:00:00Z". PASS
   b. sla --now 2026-07-28T00:00:00Z classifies all four states: fx-overdue=overdue, fx-duesoon=due-soon (36h inside the 48h window), fx-ok=ok, fx-nodl=no-deadline; sorted soonest-deadline-first, undated last. PASS
   c. default_action carried on the sla row ("auto-dismiss and proceed with option B"). PASS
   d. DEADLINE FOLD carve-out: clear-deadline AFTER set-deadline resolves to no-deadline despite the earlier non-empty set (record-type-ordered, not last-non-empty-wins). PASS
   e. set-deadline AGAIN after clear restores the deadline (latest deadline_set/deadline_cleared record wins). PASS
   f. Unparseable --deadline "not-a-date" rejected: honest stderr note, exit 0, registry line count unchanged (10 before, 10 after). PASS
   g. Sandbox integrity: real ~/.claude/state/ask-registry.jsonl (16079 bytes, mtime 1785268501) and repo mirror docs/asks/ask-registry.jsonl (54108 bytes, mtime 1785268503) byte-identical before/after all fixture work. PASS
4. Janitor fold replayed by verifier. Command: bash adapters/claude-code/scripts/estate-janitor.sh --self-test. Output: self-test summary: 16 passed, 0 failed / self-test: OK (real 11m58s wall on this loaded machine, user+sys ~54s; concurrent builder running). Scenario 7b asserts deadline_set folds, clear-wins-over-set, undated-empty, default_action last-non-empty-wins; Scenario 9 asserts tempdir sandboxing. Result: PASS
5. Brief SLA panel replayed by verifier. Command: bash adapters/claude-code/scripts/estate-brief.sh --self-test. Output: self-test summary: 25 passed, 0 failed / self-test: OK (real 1m08s). Scenario 7 asserts TEXT states ("overdue 3d" / "due in 2d" / "no deadline") plus overdue-first-then-dated-then-undated sort; Scenario 8 asserts the independent ESTATE_BRIEF_MAX_ASK_ROWS cap (default 5, env-overridable) vs ESTATE_BRIEF_MAX_ROWS=20 elsewhere. Result: PASS
6. REAL brief rendered once by verifier (8.3s). Output: "ASKED (6 active, top 5 by SLA)" with the builder's production demo ask ask-t2-sla-demo-CLEANUP-ME FIRST carrying literal text "overdue 2d", no-deadline asks after - the overdue-first SLA panel demonstrated against real production snapshot.json (generated 2026-07-28T19:48:21Z by T2-era janitor code; asks[] carry deadline/default_action keys, jq-confirmed). Result: PASS
7. REAL sla verb read-only against the production registry: header plus 5 active rows, all no-deadline; the demo ask correctly EXCLUDED (dismissed). Demo lifecycle proven in the real registry: created 19:20:37Z, deadline_set 19:27:36Z (past-dated 2026-07-26, a real overdue), deadline_cleared 19:53:51Z, status_change dismissed 19:54:55Z. The builder's "real production demo + cleanup proven" claim is TRUE on-disk. Result: PASS
8. Ask-registry full suite final line (builder's pending question resolved). File: tasks/b1o97sg10.output (this session's task dir, mtime Jul 28 13:42). Final line: "self-test summary: 55 passed, 0 failed". The only two "FAIL" string hits are scenario TITLES (Scenario N/R4: "a FAILING fake command/classifier degrades silently"). T2 scenarios W/W2/W3/X/Y/Y2/Z/Z2 all show PASS lines. No re-run needed (machine care honored; per-scenario results inspected). Result: PASS
9. RED evidence (new-from-absent behavior, stated-reason path): pre-T2 (parents d528852/fc718fe/f62c3d1), sla fell to ask-registry.sh's unknown-verb branch, snapshot asks[] had no deadline key, and the brief ask row was "ask_id | summary | project" with no SLA text (the removed line is visible in the 2be51c1 diff; T1 evidence check 7 shows the old panel shape). The T2 assertions cannot pass against the pre-T2 tree. Result: PASS
10. Manifest honesty: ask-registry honest_status names the four new verbs, the DEADLINE FOLD contract, and default_action as data-only this slice (observe-first); estate-janitor golden_scenario updated to 16 scenarios incl. the fold; estate-brief golden_scenario updated to 25 scenarios plus SLA panel semantics. Result: PASS
11. Program rule 3 (retirement disposition): session-start-digest.sh carries an explicit EVALUATED-NOT-RETIRED block - feed_needs_you / feed_backlog_accountability retained because ask-registry/NEEDS-YOU/backlog are three still-unmerged populations (consolidation is T10 territory per review F5/F6; retiring feed_needs_you pre-migration would clobber the operator's only NEEDS-YOU visibility channel - the exact F6 failure class). Honest-disposition accepted, same standard as T1 check 11. Result: PASS (judgment call, reasoning cited)
12. Docs impact: this plan predates the Docs impact: field (no task in the plan uses it) - grandfathered per verifier doctrine; the manifest honest_status updates in-commit are the doc surface for these scripts. Result: N/A (grandfathered)

Runtime verification: test adapters/claude-code/scripts/ask-registry.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/estate-janitor.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/estate-brief.sh::--self-test
Runtime verification: file C:/Users/misha/.claude/state/estate/snapshot.json::deadline
Runtime verification: functionality-verifier T2::SKIP (rationale: no Task tool in this verifier environment; the user-shaped exercise was executed inline by the verifier - fixture round-trip of all four verbs, real brief rendered showing a real overdue ask first with "overdue 2d" text, real sla read-out against the production registry; plan is acceptance-exempt: harness-internal, maintainer-is-user per constitution section 4)

DEPENDENCY TRACE
================
Step 1: operator/agent sets a deadline via ask-registry.sh set-deadline, which appends deadline_set (normalized canonical UTC)
  Verified at: verifier fixture run (scratchpad t2-verify-fixture; check 3a) + real registry record at 19:27:36Z
Step 2: readers fold deadline via the DEADLINE FOLD carve-out (clear wins over earlier set)
  Verified at: checks 3d/3e (verifier fixture), cmd_sla jq (ask-registry.sh:1346-1348), _ej_collect_asks jq (estate-janitor.sh, same carve-out), janitor self-test Scenario 7b
Step 3: estate-janitor.sh folds deadline/default_action into snapshot.json asks[]
  Verified at: self-test 16/0 replayed + real snapshot.json asks[] keys (ask_id,deadline,default_action,last_ts,project,repo,status,summary via jq)
Step 4: estate-brief.sh renders the <=5-asks SLA panel overdue-first with TEXT states from snapshot.json only
  Verified at: self-test 25/0 replayed (Scenarios 7/8) + REAL render first ASKED row "ask-t2-sla-demo-CLEANUP-ME | overdue 2d | ..."
Step 5: operator sees any overdue ask AT THE TOP of the daily brief, so "silently older than deadline" is structurally impossible while the brief is read
  Verified at: check 6 (real render); the sla verb additionally gives an on-demand read-out (check 7)

Git evidence:
  Files modified (all in squash 2be51c1 on master, 2026-07-28):
    - adapters/claude-code/scripts/ask-registry.sh (+425 lines: 4 verbs, DEADLINE FOLD contract, scenarios W-Z2 + V)
    - adapters/claude-code/scripts/estate-janitor.sh (+38: fold fields + Scenario 7b)
    - adapters/claude-code/scripts/estate-brief.sh (+110: SLA panel + Scenarios 7/8)
    - adapters/claude-code/hooks/session-start-digest.sh (+33: rule-3 disposition comment)
    - adapters/claude-code/manifest.json (3 honest_status/golden_scenario updates)
    - docs/plans/accountable-estate-program-2026-07.md (Files-to-Modify table honesty)

Outcome-metric ruling (verifier judgment): the metric "zero operator-asks silently older than their deadline in a 14-day window" is forward-looking and cannot be a present fact at close. The slice's demonstrable core - the mechanism that deletes "silently" - IS demonstrated: a real overdue ask surfaced FIRST on the real daily brief with explicit "overdue 2d" text, and the sla verb gives an on-demand read-out. Per Program rule 2 (metric + re-check date), the 14-day window is recorded as a monitored claim:
Outcome-metric re-check date: 2026-08-11 (14 days from close). Re-check: run ask-registry.sh sla and render the brief; any ask found overdue that never surfaced on a brief re-opens T2.

Verdict: PASS
Confidence: 9
Reason: PROVEN: the verifier round-tripped all four verbs itself on a sandboxed fixture registry (normalization, all four sla states, overdue-first sort, clear-wins-over-set carve-out, re-set after clear, unparseable rejection, sandbox integrity fingerprint-proven), replayed both self-tests green (janitor 16/0 incl. fold Scenario 7b; brief 25/0 incl. SLA text/sort/cap), resolved the ask-registry suite's pending final line (55 passed, 0 failed on file), rendered the REAL brief showing a REAL overdue ask first with "overdue 2d" text, and confirmed the production demo + cleanup trail on-disk in the real registry. Adversarial probes that did not break it: unparseable-deadline injection, clear-vs-set fold ordering probe in both directions, real-registry fingerprint diff, FAIL-string audit of the suite output.
