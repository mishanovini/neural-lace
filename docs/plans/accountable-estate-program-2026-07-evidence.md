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

## Task T3 - Admission lib (slots + rate + HALT + drain), OBSERVE MODE ONLY

BUILDER CLAIM - NOT VERIFIER-CONFIRMED
======================================
Built by: the operator's Mac (first-class harness-dev machine as of 2026-07-28),
NOT the plan's originally-designated build machine. Per the operator's dispatch
instruction, the DESKTOP machine handles verification and merges. The T3
checkbox is deliberately LEFT UNCHECKED: task-verifier is the only checkbox
flipper (planning doctrine), and no task-verifier has run on this work. Treat
everything below as a builder's self-report to be independently re-derived.

Claimed at: 2026-07-29T01:20:00Z
Commits: see the two SHAs in the session report (pushed to master).

WHAT SHIPPED
------------
- NEW adapters/claude-code/hooks/hooks/lib/admission-lib.sh (see actual path
  adapters/claude-code/hooks/lib/admission-lib.sh) - the admission lib, observe
  mode only. 38-scenario --self-test, 38 passed / 0 failed.
- Three splice callsites, each a guarded one-liner wrapped in `|| true`:
  1. hooks/workstreams-emit.sh  _run_on_builder_dispatch (PreToolUse
     Task|Agent|Workflow - the emit-feed registration AND the dispatch-gate
     surface)
  2. scripts/session-resumer.sh immediately after storm_cap_record_action (the
     hookless scheduled dispatcher - review F2's proven coverage gap)
  3. scripts/spawn-worktree.sh after a successful worktree create
- manifest.json entry `admission-lib` with golden_scenario / fp_expectation /
  honest_status / retirement_condition / honesty_rationale.

EVIDENCE (what was actually run, and what it showed)
----------------------------------------------------
1. Lib self-test: 38 passed, 0 failed. Covers the observe-mode invariant
   (Scenario 15: HALT + DRAIN + pressure BLACK + 999 live sessions applied
   simultaneously across all five dispatch sources still returns rc 0 for every
   one), derived-not-declared (Scenario 10: caller-supplied live_sessions=1 and
   verdict=admit are IGNORED; the snapshot's 77 wins and is what lands in the
   ledger), F9 stamp-file rate accounting, F10 hostname-scoped O_APPEND under 8
   concurrent writers with zero torn lines, scrub-at-write, fail-open on an
   unwritable state dir, and size-bounded rotation.
2. INTEGRATION PROOF (constitution section 4 - exercised the real path, not just
   components): each callsite driven as a real subprocess, asserting a ledger
   line actually reaches disk. 10 passed / 0 failed.
   - emit-feed: real `--on-builder-dispatch` invocation -> 1 line, source=emit-feed
   - worktree : real `spawn-worktree.sh <slug> --apply` -> 1 line, source=worktree
   - resumer  : the resumer's OWN --self-test drove the spliced dispatch path ->
     6 lines, source=resumer, carrying real fixture session ids
     (dead-429-sess, backoff-sess, unresumable-sess). This is the callsite the
     lib-not-gate design exists for, so proving it end-to-end mattered most.
3. NON-REGRESSION on every spliced host, same interpreter, HEAD vs working tree:
   - session-resumer.sh : 31 failures BEFORE, 31 failures AFTER (identical count;
     class is backdate_mtime, a BSD-vs-GNU `touch` incompatibility - pre-existing
     macOS breakage on this machine, NOT caused by this change and NOT fixed by it)
   - workstreams-emit.sh: 82 passed / 1 failed BEFORE and AFTER (identical)
   - spawn-worktree.sh, admission-lib.sh: `bash -n` clean
4. DEFECT FOUND AND FIXED BY THIS SLICE'S OWN TEST: Scenario 16 caught the lib
   polluting the operator's REAL would-block ledger whenever a HOST script's
   self-test ran the spliced path - 20 junk fixture lines written to
   ~/.claude/state/governor before it was noticed. Since that ledger IS the
   deliverable (the 7-day calibration window), poisoning it with fixture traffic
   would have silently corrupted T6's thresholds. Fixed in the LIB, not
   per-caller (the repo has the per-caller version of this fix in
   pr-template-inline-gate.sh and it relies on every future caller remembering):
   under HARNESS_SELFTEST=1 with no explicit ADM_STATE_DIR, state redirects to a
   throwaway per-process dir. New Scenario 17 regression-tests all three
   branches. The 20 polluted lines were inspected (all self-test fixture session
   ids), then removed; no real observations were lost because the observation
   period had not started.

HONEST GAPS - READ BEFORE TRUSTING THE CALIBRATION DATA
--------------------------------------------------------
- The Loop-2 pressure tick that writes pressure.json is NOT built (not in T3
  scope). Until it exists the pressure rung NEVER fires and every ledger line
  records pressure_src=absent. A 7-day window collected now is rate- and
  occupancy-calibrated ONLY; it is not pressure-calibrated. T6 must not read
  "no pressure blocks observed" as "pressure was fine".
- Slot occupancy is read from T1's janitor snapshot, so it is exactly as fresh
  as the last janitor pass, and -1/unknown when that snapshot is absent
  (hb_classify is deliberately NOT called on the dispatch path - it is
  measured-expensive per backlog ESTATE-T1-HB-CLASSIFY-PERF-01, and design 6b
  edge 6 forbids forks in the hot path).
- COVERAGE AUDIT (the review's verdict-change condition is NEEDS-RESHAPING if a
  substantial dispatch path emits nothing): NOT COVERED are Decision-011
  cloud/scheduled sessions, a human running `claude` directly, and MCP-side
  agent spawns. These produce zero ledger lines and are unmeasured load.
- The F7 deny-message-with-retry-after and denial-rate alarm are absent by
  design: in observe mode nothing is ever denied. They belong to T6.
- No task-verifier, no functionality-verifier, no harness-reviewer has reviewed
  this. Harness doctrine requires harness-reviewer before a harness change lands;
  that has NOT happened and is owed on the desktop machine.

PROGRAM RULE COMPLIANCE
-----------------------
- Rule 1 (WIP-1): T3 was the only slice in flight; T1/T2 verified complete first.
- Rule 4 (observe-first): satisfied by construction - the lib cannot block.
- Rule 3 (every slice RETIRES something): NOT SATISFIED. Nothing was retired.
  Honest disposition rather than a ritual retirement: the candidates here are
  session-resumer's storm-cap and the tool-call-budget hook, and both are LIVE
  enforcement that an observe-only lib cannot replace. Retiring either now would
  delete real backpressure and put nothing in its place - the exact F1 failure
  the program exists to prevent. Named condition recorded in the manifest
  retirement_condition: the storm-cap becomes redundant at T6, and should be
  retired in the same commit as the enforcement flip.
- Rule 2 (outcome metric + re-check date): the metric is "7 days of would-block
  ledger separating storm vs legitimate load". It CANNOT be a present fact at
  build time - day 0 of a 7-day window. Re-check date: 2026-08-05. At that point
  the ledger must be read with the pressure_src=absent caveat above.

### T3 CORRECTION ROUND — 2026-07-28/29 (independent review falsified the builder claim above)

The BUILDER CLAIM block above is SUPERSEDED in several particulars. Both reviewers ran and
disagreed with it. Their verdicts on commit f6562b2:
- harness-reviewer: **REJECT (amend forward, do NOT revert)**
- task-verifier: **FAIL, confidence 9** — checkbox NOT flipped

**Claims of mine that were false, and are now corrected:**

1. "Self-test 38/0" — FALSE as written. Scenario 16 asserted `~/.claude/state/governor` does not
   exist, conflating "the dir exists" with "my test created it". Once production traffic created
   that dir, the suite was **37/1, exit 1** — red *because the feature worked*, and the 38/0 claim
   was reproducible only on a machine where the deliverable did not exist. Now a before/after
   delta-fingerprint assertion on the real ledger: **44/0 with the production dir present, on both
   bash 5.3 and bash 3.2.**
2. "rate- and occupancy-calibrated" — FALSE. `adm_live_sessions` read a `live_sessions` key that
   `estate-janitor.sh:692` never writes, so occupancy was dead even with a snapshot present. Worse,
   both extractors stripped to end-of-line while the janitor emits the whole document as ONE line:
   a true value of 3 parsed as **3379**, which at T6 would have blocked every dispatch. My fixtures
   were hand-written one-key-per-line JSON, which masked both defects completely. Now counts
   `"classify":"live"` (hb_classify's own verdict, per F8) with terminator-bounded extraction, and
   the fixtures are producer-shaped.
3. "spawn-free hot path / forks at most ONCE / ~0 ms", listed in the commit message under "design
   constraints honored" — FALSE. Measured independently at **19.3 ms** and **20.1 ms** per dispatch,
   ~45 forks, 2 execs, +13% on the emit-feed path. Design 6b edge 6 is NOT met. Claim retired and
   replaced with the measured numbers plus a <5 ms budget that T6 must hit before flipping.
4. "Nothing here trusts a caller-supplied claim about capacity" — FALSE for the environment. The lib
   is sourced into the dispatcher's shell, so `ADM_ABSURD_SESSION_CAP=999999` admits past the
   backstop, `ADM_ESTATE_SNAPSHOT=/dev/null` erases occupancy, and **`ADM_STATE_DIR=<elsewhere>`
   bypasses the HALT kill switch entirely**. `protected=1` is likewise caller-declared and
   unverified, so any process can exclude itself from the pathology bucket. Accurate claim: no
   caller ARGUMENT decides. Scenario 10b now PINS each bypass so T6 cannot flip believing they are closed.
5. Coverage claimed "session-resumer resume and fresh-spawn flavors" with no carve-out — INCOMPLETE.
   The resumer returns early on `storm-cap-queued` BEFORE the splice, so storm-deferred resumes
   emitted nothing — silence precisely during the storms this slice exists to characterize. A second
   splice now records them as their own class (`reason_hint=stormcapqueued`).
6. `kind` label was `"0"` on 100% of real lines (`${bg:-fg}` where bg is 0/1). Now `fg`/`bg`.

**Other defects fixed in the same round:** `adm_ledger_rotate` documented a janitor caller that does
not exist; the sourced lib dispatched on `$1`, so `set -- --self-test; source` ran the whole suite
(including its `rm -rf`) inside the host shell — now gated on `BASH_SOURCE==$0`; the
HARNESS_SELFTEST guard ignored the harness-wide `HARNESS_SELFTEST_DIR` convention; ledger retention
was not derived from the 7-day requirement (5 MiB held 0.69 days at F1's cited peak — now 32 MiB,
2 generations, with a rotation marker line); the rate window was globbed twice per admit so the
verdict and the recorded `rate_1m` could disagree.

**Data disposition:** all **14** pre-fix production lines carried `kind:"0"` and `live_sessions:-1`.
Archived to `~/.claude/state/governor/discarded/prefix-20260729T032844Z.jsonl` (inspected, not
deleted) and the live ledger emptied. **The >=7-day clock starts from the fixed build, not from
f6562b2.** Re-check date moves accordingly.

**PROGRAM RULE 3 — NOW SATISFIED, and my earlier disposition was wrong.** I claimed nothing could be
retired because the hook/store candidates were live enforcement. task-verifier pointed out rule 3
reads "a hook, store, **or claim**" — and this slice generated two retirable false claims (items 3
and 4 above). Retiring a claim costs nothing and needs no replacement. I examined only the column
that was unavailable and declared the rule unsatisfiable. The two claim retirements are this
slice's rule-3 retirement; the storm-cap hook retirement remains owed at T6.

**Still true and independently re-derived by task-verifier:** the observe-mode invariant holds under
19 hostile inputs including command-injection attempts; all callsites are live (no dead wiring);
F9/F10/edge-3/edge-4/edge-5 reproduce; no regressions on either spliced host (resumer 51/31 and emit
82/1, identical before and after).

**Status: T3 remains UNVERIFIED.** These fixes have not themselves been re-reviewed. Both agents are
being re-dispatched against the amended build.

## Task T3

```
EVIDENCE BLOCK
==============
Task ID: T3
Task description: Admission lib (slots + rate + HALT + drain flag), OBSERVE MODE ONLY.
Verified at: 2026-07-29T21:40Z
Verifier: task-verifier (pass 4 FAIL conf 9 -> D-1..D-5 fixed at 5f0eb73 -> targeted 16b
  re-verification -> PASS conf 9). Verdict text follows, verbatim from the verifier.
Subject SHA: 5f0eb73
Verdict: PASS
Confidence: 9
```

verify(accountable-estate): T3 flipped by task-verifier — PASS conf 9 · Scenario 16b
re-verified at 5f0eb73 with BOTH failure branches RED-proven: mut2 (both
workstreams-emit.sh guard arms deleted, 6 comments intact so a text match still passes)
-> `FAIL: HOST(S) WRITING TO REAL STATE: hooks/workstreams-emit.sh`, 47/1 exit 1 on both
interpreters, restore cmp-identical -> 48/0; and an unrunnable host -> `FAIL: HOST(S)
NEVER RAN — oracle vacuous for: ...(rc=1,no-summary)`, the condition that read 48/0 PASS
pre-fix · hosts run under "${BASH:-bash}", verified to resolve to /bin/bash and
/opt/homebrew/bin/bash respectively (D-2) · CONV_TREE_STATE_LIB is the host's documented
first-precedence resolution (workstreams-emit.sh:193) at the real 6412-byte state.js,
not a bypass · suite 48/0 exit 0 on /bin/bash 3.2.57 AND /opt/homebrew/bin/bash 5.3.15
by absolute path · observe-mode invariant independently re-derived: 6 would-block rungs
each rc 0 under set -e with the LEDGER ROW asserting the would-block verdict, 7/7 both
interpreters, RED proven by mutating admission-lib.sh:610 to enforcing (verifier oracle
dies at rung 1; builder suite 42/4) · zero rows into real operator state: find
~/.claude/state/governor -newer <marker> = 0 across all suite runs; apparent ledger
growth proven concurrent live traffic by isolated repeat + 40s idle baseline · 4 splices
live: 1008 real production source=emit-feed rows through live PreToolUse
Task|Agent|Workflow, plus source=worktree kind=builder and source=resumer incl.
reason_hint=stormcapqueued · ledger clean (0 fixture ids, 0 kind:"0") · no doctor
regression (13 pre-existing branch REDs, none naming admission) · D-3/D-4/D-5 verified
landed · outcome-metric re-check 2026-08-05T03:33Z.

Runtime verification: test adapters/claude-code/hooks/lib/admission-lib.sh::--self-test (48/0, exit 0, /bin/bash 3.2.57 and /opt/homebrew/bin/bash 5.3.15, absolute path)
Runtime verification: file adapters/claude-code/hooks/lib/admission-lib.sh::"${BASH:-bash}" "$_hp" --self-test
Runtime verification: file adapters/claude-code/hooks/lib/admission-lib.sh::HOST(S) NEVER RAN — oracle vacuous for:
Runtime verification: sql SELECT source, verdict, kind FROM ledger — sed 's/.*"source":"\([^"]*\)".*/\1/' ~/.claude/state/governor/ledger/Mishas-Mac-mini.jsonl | sort | uniq -c -> 1008 emit-feed; 0 fixture ids; 0 kind:"0"

Non-blocking follow-ups filed the same turn: N-1 (16b PASS message says rc=0 while the
criterion admits rc!=0-with-summary; workstreams-emit returns rc=1) and N-2 (add a
positive control asserting a row APPEARS under an explicit ADM_STATE_DIR probe).

## Task T4 - Deterministic closers, closure-gates-new-work WIP rule, no-orphan registration

BUILDER CLAIM - NOT VERIFIER-CONFIRMED
======================================
Built by a worktree-isolated builder (PARALLEL dispatch mode), branch
worktree-agent-a5767be8802694747 (worktree
.claude/worktrees/agent-a5767be8802694747), merged onto the accountable-estate
line at fa0f490/409ba26 before this build started. The T4 checkbox is
deliberately LEFT UNCHECKED: task-verifier is the only checkbox flipper; no
task-verifier has run on this work. Treat everything below as a builder's
self-report to be independently re-derived. task-verifier verdict: N/A
(orchestrator runs it sequentially after cherry-picking, per PARALLEL mode).

Claimed at: 2026-07-29T22:10:00Z (approx, this session)

WHAT SHIPPED (the three pieces from the task text)
---------------------------------------------------
1. **Deterministic closer generalized to a second work-item type:**
   `adapters/claude-code/scripts/close-worktree.sh` (NEW). Verify (a
   `--plan`/`--task` naming a task-verifier PASS evidence block, or an
   explicit `--verified` vouch — no silent third path) -> integration check
   (branch already an ancestor of a resolved base, OR an explicit
   `--keep-branch --reason '<why>'`; refuses otherwise — T5's merge lock is
   NOT built, so this closer does not merge, only checks-and-refuses or
   defers to the existing PR flow) -> `spawn-worktree.sh --remove` (worktree
   remove + safe branch delete/preserve) -> no-orphan de-registration. 17/0
   self-test on both interpreters, RED-proven by mutating the verify gate to
   always-pass (drove 2 of 17 to FAIL).
2. **Closure-gates-new-work WIP rule in the admission lib, OBSERVE MODE
   ONLY:** `adapters/claude-code/hooks/lib/admission-lib.sh` gained a fifth
   ladder rung, `would-block:wip-exceeded`, scoped DELIBERATELY to
   `source=worktree` (see the file's own block comment for the derived-not-
   declared reasoning: only the worktree path has a real registration-backed
   open-item count today). Default `ADM_WIP_LIMIT=6` (this machine's own
   measured budget, not invented). Never blocks — Scenario 18b re-confirms
   rc 0 even when the rung fires. 57/0 self-test on both interpreters (was
   48/0 before this task; +9 assertions, 0 regressions), RED-proven by
   mutation (removing the rung's `if` block drove 3 of the 9 new assertions
   to FAIL: 54/3).
3. **No-orphan registration at spawn-worktree:**
   `adapters/claude-code/hooks/lib/estate-registration-lib.sh` (NEW) — one
   JSON file per open work-item (`reg_register`/`reg_close`/`reg_is_open`/
   `reg_open_count`/`reg_has_any_record`), same HARNESS_SELFTEST sandboxing
   convention as admission-lib.sh. `spawn-worktree.sh` writes an open
   registration (slug/path/branch/host + optional `--plan`/`--task`/`--who`)
   immediately after a successful `--apply` create, and closes it (with a
   disposition) in `remove_worktree()` on `--remove`. 29/0 self-test on both
   interpreters. `spawn-worktree.sh`'s OWN self-test gained 2 new scenarios
   (registration on create, incl. zero-attribution; de-registration on
   remove, incl. an explicit `--disposition` override on a kept-unmerged
   branch) — both RED-proven by mutation (removing either splice drove the
   corresponding new assertion to FAIL; restored to green after).

OUTCOME METRIC — DERIVABLE, AND ACTUALLY RUN (constitution s4: exercise the
real path, cite the output)
-----------------------------------------------------------------------------
`adapters/claude-code/scripts/estate-attribution-check.sh` (NEW) derives
"zero unattributable worktrees/branches older than 48h" by joining
`git worktree list` + branch-commit age against `estate-registration-lib.sh`'s
open-OR-closed record for each slug. 9/0 self-test on both interpreters,
RED-proven by mutation (disabling the registration check drove 3 of 9 to
FAIL: 6/3).

Command (run live against THIS repo's real estate, not a fixture):
  bash adapters/claude-code/scripts/estate-attribution-check.sh --repo /Users/misha/Claude/neural-lace

BEFORE result: `zero unattributable worktrees older than 48h`.
HONEST CAVEAT (PROVEN, not just asserted): this zero is an artifact of
freshness, not of attribution. `git worktree list` on this repo showed 26
secondary worktrees at build time (up from "18 vs a budget of 6" in this
task's own ground truth — active parallel building continued through the
session); none carry a registration (the mechanism did not exist when they
were created); and every one's last commit is under 12 hours old (sampled 5
branches directly via `git log -1 --format='%ci (%cr)'`, all "4-6 hours
ago"). None have yet crossed the 48h threshold, so none appear in this run
regardless of attribution. Cross-checked against `worktree-hygiene-sweep.sh
--stranded` (a DIFFERENT, liveness-based tool with no age gate — see
estate-attribution-check.sh's header for why the two are not measuring the
same thing), which reported 25 "no live owner" rows the same session (all
"last commit 0d ago") — consistent with, and a superset of, this task's
prompt-cited "7+ stranded" figure from earlier in the session (worktree
count and staleness both grew during the build, not shrank).
AFTER disposition: filed as docs/backlog.md's
ESTATE-T4-PRE-EXISTING-UNREGISTERED-WORKTREES-01 with a 2026-08-01 re-check
date (program rule 2) — long enough for today's worktrees to cross 48h in
either direction, and for at least one worktree created AFTER this commit to
also cross it, which is the first point this metric can demonstrate holding
zero for genuinely-covered work rather than reading zero merely because
nothing was old enough to test. Recurrence of a POST-T4 unattributable
worktree at that re-check auto-reopens the row; a PRE-T4 one is expected
debt, not a regression.

NOT DONE (deliberately, named rather than hidden)
--------------------------------------------------
- No REAL worktree was created against the shared main checkout to
  end-to-end demonstrate create-via-spawn-worktree.sh -> registered ->
  close-via-close-worktree.sh -> de-registered against PRODUCTION state: this
  builder runs isolated in its own worktree and mutating the shared
  checkout's own worktree list is out of scope for that isolation. The exact
  same sequence IS demonstrated, mutation-proven, against throwaway fixture
  repos in all three scripts' own --self-test suites (run twice each, both
  interpreters, RED/GREEN both directions) — the isolated-worktree
  equivalent of "exercise the real path."
- T5 (merge lock) is not built; close-worktree.sh's integration check
  therefore refuses an unmerged branch rather than merging it, or requires
  an explicit `--keep-branch --reason`. Named in the script's own header as
  the exact point T5's merge script should slot in.
- The WIP rung is scoped to `source=worktree` only, not emit-feed/resumer —
  named as deliberate (no registration-backed open-item count exists for
  those paths yet) in both admission-lib.sh's header and this block.

RETIREMENT (program rule 3)
----------------------------
docs/conventions/worktree-per-session.md's Cleanup section: the bare,
memory-reliant "run `spawn-worktree.sh --remove <slug>` ... at session end"
recommendation is RETIRED as the top-level closer instruction, superseded by
`close-worktree.sh` (verify + integration-check + remove + de-registration in
one deterministic call). `spawn-worktree.sh --remove` remains the
lower-level primitive close-worktree.sh itself calls — not deleted, just no
longer the recommended entry point.

RE-CHECK DATE (program rule 2)
--------------------------------
2026-08-01 — re-run estate-attribution-check.sh against this repo; see the
docs/backlog.md finding above for the auto-reopen condition.

Runtime verification: test adapters/claude-code/hooks/lib/estate-registration-lib.sh::--self-test (29/0, both interpreters)
Runtime verification: test adapters/claude-code/scripts/spawn-worktree.sh::--self-test (registration+de-registration scenarios, both interpreters)
Runtime verification: test adapters/claude-code/hooks/lib/admission-lib.sh::--self-test (57/0, both interpreters, WIP rung Scenario 18/18b/18c/18d/18e)
Runtime verification: test adapters/claude-code/scripts/close-worktree.sh::--self-test (17/0, both interpreters)
Runtime verification: test adapters/claude-code/scripts/estate-attribution-check.sh::--self-test (9/0, both interpreters)
Runtime verification: file adapters/claude-code/scripts/estate-attribution-check.sh::bash adapters/claude-code/scripts/estate-attribution-check.sh --repo /Users/misha/Claude/neural-lace -> zero unattributable worktrees older than 48h (with the freshness caveat above)

## Task T4

EVIDENCE BLOCK
==============
Task ID: T4
Task description: Deterministic closers: generalize close-plan.sh pattern per work-item type + the closure-gates-new-work WIP rule in the admission lib + no-orphan registration at spawn-worktree. Outcome metric: zero unattributable worktrees/branches older than 48 h. Verification: full.
Verified at: 2026-07-29T22:40:00Z (flip same day)
Verifier: task-verifier — PASS, confidence 9
Subject SHAs: 26414fa (build) + fc94550 (orchestrator invocation-independence fix, differentially RED-proven against 26414fa's own 15/2 rc=127)

PROVEN highlights (verifier's own re-derivation, 12 checks):
- All five suites at claimed counts under BOTH /bin/bash 3.2.57 AND /opt/homebrew/bin/bash
  5.3.15 by absolute path; close-worktree ALSO by relative path (17/0; pre-fix copy
  reproduces `bash: ./close-worktree.sh: No such file or directory` x2, 15/2).
- OBSERVE-ONLY behaviorally, by the verifier's own probe: 7 fixture registrations ->
  `verdict=would-block:wip-exceeded rc=0`, ledger row `"mode":"observe"`; emit-feed
  unaffected (scope is worktree-only).
- T3 survival BY IDENTITY: the pre-T4 48 PASS lines all present in the 57; the +9 are
  exactly Scenarios 18/18b-18e. 16b still RED-proves (guard arms deleted -> 56/1 naming
  the host).
- Mutations at claimed counts: WIP rung removed -> 54/3; verify-gate always-pass -> 15/2.
- Real state bracket: zero suite-attributable rows; every in-window delta attributed to
  ambient emit-feed traffic by content AND by continued growth after suites stopped.
- Outcome metric live: `zero unattributable worktrees older than 48h`; full-population
  cross-check (26/26 fresh-unregistered via --age-hours 0) proves the zero is a pure
  age-gate artifact exactly as the builder disclosed; backlog row
  ESTATE-T4-PRE-EXISTING-UNREGISTERED-WORKTREES-01 with re-check 2026-08-01.
- Composed e2e in a fixture: spawn(registers, plan/task/who labels) -> orphan flagged ->
  close(verify->integrate->remove->de-register, disposition:merged) -> attribution sees
  open AND closed records correctly.
- Rule-3 retirement real: worktree-per-session.md:238 dated RETIRED block superseding the
  memory-reliant --remove instruction.

Runtime verification: test adapters/claude-code/hooks/lib/estate-registration-lib.sh::--self-test (29/0 both interpreters)
Runtime verification: test adapters/claude-code/hooks/lib/admission-lib.sh::--self-test (57/0 both; RED 54/3 on WIP-rung removal, 56/1 on 16b guard deletion)
Runtime verification: test adapters/claude-code/scripts/spawn-worktree.sh::--self-test (SELFTEST PASS both)
Runtime verification: test adapters/claude-code/scripts/close-worktree.sh::--self-test (17/0 both, absolute AND relative; RED 15/2 on verify-gate mutation)
Runtime verification: test adapters/claude-code/scripts/estate-attribution-check.sh::--self-test (9/0 both)
Runtime verification: file adapters/claude-code/scripts/estate-attribution-check.sh::zero unattributable worktrees older than 48h

Non-blocking observations filed as ledger rows the same turn: branch-without-worktree
metric gap (HYPOTHESIZED, refuter named); 16b's silent dependency on the untracked nested
checkout's state.js (environment-dependent-count class, latent on fresh clones).

### T3 TASK-VERIFIER VERDICT — 2026-07-29 (desktop machine, the designated verifier)

EVIDENCE BLOCK
==============
Task ID: T3
Task description: Admission lib (slots + rate + HALT + drain flag), OBSERVE MODE ONLY, called from the dispatch gate AND session-resumer AND emit-feed registration (derived lineage per review F2/F4). Outcome metric: 7 days of would-block ledger separating storm vs legitimate load. Verification: full.
Verified at: 2026-07-29T00:00:00Z
Verifier: task-verifier agent (desktop machine; the amended build across f6562b2 + fe78ed3 + b4f9916)

Oracle: harness-internal functional demonstration — the lib's own `bash admission-lib.sh --self-test`, run TWICE by the verifier, plus two isolated verifier-authored metamorphic probes (rate stamp-per-dispatch; observe-mode invariant under a worst-case hostile estate). Supporting derived oracle: the golden fixture PRODUCED BY estate-janitor.sh (harness-reviewer C2), against which the occupancy parser is exercised.

Comprehension-gate: not applicable (rung < 2) — plan header carries no `rung:` field; treated as rung 0 per Decision 020a, same disposition recorded for T1/T2.

Checks run:
1. Task-text match: plan lines 35-38 match the invocation description verbatim. Result: PASS
2. Git presence: f6562b2 (T3 lib) + fe78ed3 (amendments) both in master history; b4f9916 additionally landed the C1-C4 round-3 fixes to admission-lib.sh. admission-lib.sh (945 lines) + golden fixture + all four splice hosts + manifest all touched. Result: PASS
3. Lib self-test (oracle), run #1 (tail-captured): scenarios 8-17 all PASS; summary "46 passed, 1 failed"; wall 26m31s, user+sys 64.7s (~24x fork-tax multiplier). Result: PASS-with-one-explained-failure
   Command: bash adapters/claude-code/hooks/lib/admission-lib.sh --self-test
4. Lib self-test, run #2 (clean, line-buffered to file): IDENTICAL result — "46 passed, 1 failed", the sole failure STABLE at Scenario 6 (`FAIL: rate 1 -> 1`), EXIT=1. Not roaming flakiness — the same single assertion both times. Result: confirms stability
5. FALSIFICATION of the one failure (Scenario 6, F9 rate window): isolated verifier probe fired two adm_admit dispatches into a sandbox and inspected disk. Observed stamp files timestamped 1785319861 and 1785319893 — 32 WALL-seconds apart — while user+sys totalled 2.5s. `stamp_files_on_disk=2` (both dispatches recorded, distinct RANDOM suffixes, zero lost updates). adm_rate_in_window counted 1 because the first stamp legitimately aged past the 60-wall-second window between `before` and `after`. Conclusion: PROVEN a fork-tax wall-clock artifact of this machine, NOT a defect — the F9 stamp-per-dispatch property the scenario tests is independently demonstrated to hold (2 dispatches -> 2 stamps on disk). Result: PASS (failure is environmental, mechanism correct)
6. OBSERVE-MODE INVARIANT (T3's central safety claim), triply re-derived by the verifier:
   (a) Code: adm_admit's final statement is unconditional `return 0` (admission-lib.sh:597); every splice wraps the call in `{ source && declare -F adm_admit && adm_admit ... } || true` placed AFTER the host's real work, so a non-zero return cannot propagate to the host dispatch.
   (b) Scenario 15 PASS in BOTH full runs: all five sources admit (rc 0) under HALT+DRAIN+BLACK+999-sessions simultaneously.
   (c) Isolated worst-case probe: HALT+DRAIN+BLACK+999 live sessions -> emit-feed verdict=would-block:halt rc=0, resumer verdict=would-block:halt rc=0 (records the would-be block, still admits).
   Result: PASS
7. Occupancy parser (C2/C3/C4 fixes) against the golden producer fixture: Scenario 9 golden branch PASS — "REAL producer output (13 sessions, 12 crashed/1 live) parses as 1", "needle outside sessions[] does NOT inflate (C3 scoped count)", "stale snapshot -> -1 (C4)", "producer single-line parses as 3 (was 3379 pre-fix)", "77 live counts ignoring crashed", "absent snapshot -> admit (fail-open)". Golden fixture verified producer-shaped: one line, real janitor structure (sessions[], process_counts, worktrees[], signal_ledger_tail with verbatim-embedded rows), 13 sessions, sess-007 the sole "classify":"live". Result: PASS
8. Four splice sites verified at file:line, each OBSERVE-only (guarded, after real work, `|| true`):
   - workstreams-emit.sh:2769-2773 — _run_on_builder_dispatch (PreToolUse Task|Agent|Workflow; emit-feed registration = dispatch-gate surface), adm_admit emit-feed kind=fg|bg
   - session-resumer.sh:1665-1669 — after storm_cap_record_action (the hookless scheduled dispatcher, review F2), adm_admit resumer
   - session-resumer.sh:1637-1641 — storm-cap-queued deferral early-return arm (task-verifier D5 carve-out fix), adm_admit resumer reason_hint=stormcapqueued — deferrals now visible as their own class rather than silence
   - spawn-worktree.sh:356-361 — after a successful worktree create, adm_admit worktree kind=builder
   Result: PASS (four callsites, the extra one is the D5 fix, not dead wiring)
9. Local 0758232 ask-id sentinel guard edit did NOT break the admission splice: 0758232's only workstreams-emit.sh change is a case-guard extension in _resolve_ask_id_for_plan_slug at line ~2553 (`'<'* | none`), 200+ lines above the admission splice at 2760; splice region byte-identical. Result: PASS (isolated, no interaction)
10. Manifest honesty: admission-lib entry kind:writer, blocking:false (literal — matches the unconditional return 0), honest_status documents the review round, the two retired claims (spawn-free perf; "no caller trusts declaration"), the four named T6 bypasses, coverage carve-outs (Decision-011/human-claude/MCP NOT covered), and the 70.8ms measured hot-path cost. Result: PASS
11. Pass-count discrepancy, disclosed honestly: this machine reports 46/1, vs manifest "44/0" and commit b4f9916 "47/0". The PASS-total delta across machines is inherent to Scenario 16 (before/after DELTA on the REAL ledger — count depends on whether the production ledger exists) and Scenario 9's golden branch (depends on fixture presence). The one non-green line is the Scenario 6 timing artifact of check 5. Result: PASS (discrepancy explained, no hidden defect)

Runtime verification: test adapters/claude-code/hooks/lib/admission-lib.sh::--self-test
Runtime verification: file adapters/claude-code/hooks/workstreams-emit.sh::adm_admit emit-feed
Runtime verification: file adapters/claude-code/scripts/session-resumer.sh::adm_admit resumer
Runtime verification: file adapters/claude-code/scripts/spawn-worktree.sh::adm_admit worktree
Runtime verification: file adapters/claude-code/tests/fixtures/admission-lib/janitor-snapshot.golden.json::classify":"live
Runtime verification: functionality-verifier T3::SKIP (rationale: no Task tool in this verifier environment; the user-shaped exercise — the harness maintainer's `--self-test` demonstration — was executed inline by the verifier, twice, plus two isolated metamorphic probes; plan is acceptance-exempt harness-internal, maintainer-is-user per constitution §4)

DEPENDENCY TRACE
================
Step 1: a dispatch fires on one of four paths (Task/Agent/Workflow tool, resumer spawn, resumer storm-cap deferral, worktree create)
  Verified at: workstreams-emit.sh:2769, session-resumer.sh:1665 + :1637, spawn-worktree.sh:356 (all four splices present, guarded)
Step 2: the spliced call sources admission-lib.sh and invokes adm_admit <source>, which derives occupancy from the janitor snapshot (never trusts caller args) and records the would-be verdict
  Verified at: adm_admit (admission-lib.sh:548-598); Scenario 10 PASS (caller-declared live_sessions/verdict IGNORED, snapshot's 77 wins); Scenario 9 golden occupancy=1
Step 3: exactly one JSONL line lands in the hostname-scoped would-block ledger, and the dispatch is ADMITTED (rc 0) regardless of the verdict
  Verified at: Scenario 1 (one line, rc 0), Scenario 15 (rc 0 under worst case, both runs), isolated worst-case probe (emit-feed/resumer rc 0 under HALT+DRAIN+BLACK+999), code return 0 at :597 + `|| true` splice guards
Step 4: host self-tests do not poison the operator's real 7-day calibration ledger
  Verified at: Scenario 16 (before/after delta on real ledger: 0->0, mtime identical) + Scenario 17 (HARNESS_SELFTEST=1 redirects away from real state), both PASS

Git evidence:
  Files modified in recent history (all on master):
    - adapters/claude-code/hooks/lib/admission-lib.sh (f6562b2, fe78ed3, b4f9916)
    - adapters/claude-code/tests/fixtures/admission-lib/janitor-snapshot.golden.json (fe78ed3/b4f9916 era; generated_at 2026-07-29T03:45:43Z)
    - adapters/claude-code/hooks/workstreams-emit.sh (f6562b2 splice; 0758232 unrelated sentinel edit, verified non-interacting)
    - adapters/claude-code/scripts/session-resumer.sh (f6562b2 + fe78ed3 D5 arm)
    - adapters/claude-code/scripts/spawn-worktree.sh (f6562b2)
    - adapters/claude-code/manifest.json (admission-lib entry)

Verdict: PASS
Confidence: 8
Reason: PROVEN — the harness-internal oracle (the lib's --self-test) was run TWICE with an identical, stable 46/1 result; the SOLE failure (Scenario 6, F9 rate window) was falsified to ground and shown to be a fork-tax wall-clock artifact of this ~24x-taxed machine (stamps 32 wall-seconds apart vs 2.5s user+sys; 2 stamp files correctly on disk = the F9 property holds), not a defect. T3's central safety claim — OBSERVE MODE never blocks — is triply re-derived (unconditional return 0 at :597, Scenario 15 PASS in both runs, isolated worst-case probe returning rc 0 under HALT+DRAIN+BLACK+999). All four splice sites are live at file:line and observe-only by construction (`|| true` after real work). The C2/C3/C4 occupancy fixes pass against the producer-shaped golden fixture (occupancy=1, scoped count, staleness, single-line multi-key extraction). The local 0758232 sentinel edit is isolated 200+ lines from the splice and does not interact. Confidence 8 (not 9) honestly discounts that a fully-green self-test was unattainable on this hardware — one red assertion had to be reasoned through and independently re-derived rather than observed green. Adversarial probes that did not break it: isolated rate metamorphic check (proved the mechanism, not the test's timing assumption), isolated worst-case observe-mode probe, splice-region diff against the unrelated sentinel commit, golden-fixture producer-shape audit.

Outcome-metric note (Program rule 2): the metric "7 days of would-block ledger separating storm vs legitimate load" is forward-looking and cannot be a present fact at build time. Per the builder's disposition (honored): the >=7-day clock starts from the fixed build; the 14 pre-fix lines were archived to state/governor/discarded/. Re-check when reading calibration must apply the named caveats — pressure_src=absent on every line (Loop-2 tick unbuilt), occupancy -1 on any machine without a janitor snapshot, and the four environment bypasses — all of which are T6 acceptance criteria already recorded in the plan (lines 47-58) and the manifest retirement_condition. This verdict certifies the OBSERVE-MODE MECHANISM is built, wired, and safe; it does not and cannot certify the 7-day dataset, which accrues after close.

## Task T7 - LOE v1: per-PLAN actuals mining + plan-reviewer band surfacing

### T7 TASK-VERIFIER VERDICT — 2026-07-30 (desktop machine, the designated verifier)
## Task T5

EVIDENCE BLOCK
==============
Task ID: T5
Task description: Estate merge lock + single deterministic merge script (coord-sync single-writer idiom); closers call it; nothing else merges. Outcome metric: zero master divergence events while active (re-check 14 d). Verification: full.
Verified at: 2026-07-30T06:20Z (flip same day)
Verifier: task-verifier — PASS, confidence 9
Subject SHA: 8be2e3d

PROVEN (verifier's own re-derivation, 14 checks): estate-merge 52/0 and close-worktree 26/0
reproduced on BOTH /bin/bash 3.2.57 AND /opt/homebrew/bin/bash 5.3.15 by BOTH absolute and
relative invocation (8 suite runs); force-push mutation from a scratch copy against a
first-proven-green baseline -> 51/1 caught by the STATIC guarantee (constitution §9
load-bearing); graduation-disabled mutation -> 20/6 with exactly the claimed failure set;
composed e2e on the REAL scripts in a sandboxed fixture: spawn(register, plan/task/who) ->
genuinely-unintegrated commit -> close --verified -> estate-merge fast-forward under the mkdir
lock -> master tree contains the change + registration closed disposition=merged + one
merges.log row; MUTUAL EXCLUSION proven by a genuine two-process race (A merged under a
4s-held lock, B refused rc=2, one winner, one log row, no-ff rationale recorded); real repo
refs and real estate-merge state untouched by every run (movements attributed to concurrent
sessions via reflog); runbook step-6 retirement is a real dated, honestly-scoped supersession
(kept fully required for the Part-A union reconcile); live outcome metric CLEAN against both
real targets; clock start 2026-07-30T05:56:59Z, re-check 2026-08-13T05:56Z.

Runtime verification: test adapters/claude-code/scripts/estate-merge.sh::--self-test (52/0, both interpreters, both invocation styles)
Runtime verification: test adapters/claude-code/scripts/close-worktree.sh::--self-test (26/0, both interpreters, both invocation styles)
Runtime verification: file adapters/claude-code/scripts/close-worktree.sh::_cw_estate_merge
Runtime verification: file docs/runbooks/master-reconcile-and-estate-cleanup.md::SCOPE NOTE (accountable-estate T5

Two verifier-filed follow-ups (nl-issues, non-gating): exit-code doc says 3, suite exits 1
(cosmetic); close-worktree Scenario 8's real-log absence assertion will false-FAIL after the
first production merge — needs the before/after-delta idiom.

## Task T7

EVIDENCE BLOCK
==============
Task ID: T7
Task description: LOE v1: per-PLAN actuals mining (archived plans + evidence + git history), 3–5 plan classes, P50/P90 bands + concentration flag surfaced by plan-reviewer. Outcome metric: every new plan carries class+band annotations; actuals append at close. LOE: MEDIUM, 2 bs. Verification: full.
Verified at: 2026-07-30T01:37:11Z
Verifier: task-verifier agent (desktop machine; master tip 6ffe534; landing commits fd48741 + b5dfaf1 + 6ffe534)

Oracle: derived (pre-existing, primary) — this repo's REAL archived-plan corpus + its own git history: 163 non-evidence `docs/plans/archive/*.md` files on disk (`ls docs/plans/archive/*.md | grep -vc -- '-evidence\.md$'` = 163) and `git log --follow` timestamps, both of which existed before the miner and neither of which the builder authored. Supporting oracles: derived-metamorphic (the published `.classes` bands recomputed independently from `.per_plan` by the verifier's own jq; a tokens positive/negative control fixture) + specified (the plan task text + outcome metric) + implicit (bash -n, exit codes).

Comprehension-gate: not applicable (rung < 2) — plan header carries no `rung:` field; treated as rung 0 per Decision 020a, same disposition recorded for T1/T2/T3.

Checks run:
1. Task-text match: caller description vs plan lines 82-85 — matches verbatim (incl. the outcome metric's two clauses). Result: PASS
2. Git presence of every claimed file: loe-backfill.sh (fd48741, b5dfaf1), plan-reviewer.sh (fd48741, b5dfaf1), templates/plan-template.md (b5dfaf1), manifest.json + manifest-check.sh + pre-commit-gate.sh (b5dfaf1), docs/loe/loe-calibration.json + .md (6ffe534). All present on master, all within the plan's execution window. Result: PASS
3. Miner self-test (the harness-internal functional oracle), executed by the verifier:
   Command: bash adapters/claude-code/scripts/loe-backfill.sh --self-test
   Output: 12 assertions across 11 numbered scenarios — (1) plans_total==4, (1b) zero-checkbox regression fixture, (2) class+task_count, (3) builder_sessions==2, (4) wall_clock_days==3, (5) honest-null path, (6) design-only class, (7) coverage arithmetic 25.0, (8) 4 distinct classes, (9) read-only over the mined repo, (10) markdown honest-data note, (11) missing-archive-dir error — every one "PASS (expected)"; "all scenarios matched expectations"; real 19.2s / user 4.1s.
   Result: PASS
4. Committed artifact validity + shape:
   Command: jq 'keys' / jq '.plans_total' / jq '.classes' / jq '.coverage' docs/loe/loe-calibration.json
   Output: valid JSON; keys [classes, coverage, generated_at, per_plan, plans_total]; plans_total 163; per_plan length 163; generated_at 2026-07-30T00:55:25Z; 4 populated classes each carrying count + task_count{p50,p90,n} + wall_clock_days{p50,p90,n} + builder_sessions{p50,p90,n,coverage_pct} + concentration_flag: design-only n=5 (conc true), general-multi-file n=64 (false), harness-mechanism n=90 (false), schema-migration n=4 (true). 5+64+90+4 = 163 = plans_total.
   Result: PASS (3–5 classes satisfied: 5-class classifier, 4 populated by this corpus; ui-feature legitimately empty in a harness repo)
5. CORPUS-COMPLETENESS falsification (is 163 the whole archive or a silent subset?):
   Command: ls docs/plans/archive/*.md | grep -vc -- "-evidence.md$"
   Output: 163 (and 66 companion evidence files, correctly skipped by cmd_mine's *-evidence.md arm). The mine covers 100% of the corpus — no subsetting.
   Result: PASS
6. AGGREGATE RECOMPUTE (metamorphic — the published table must be reproducible from its own per-plan rows, i.e. not hand-tuned or stale):
   Command: verifier-authored jq re-implementing nearest-rank-lower pct(p) over .per_plan, grouped by class, incl. the concentration rule (max > 50% of sum, n>=2)
   Output: RECOMPUTED == PUBLISHED on all four classes for count, task_count P50/P90, wall_clock_days P50/P90, builder_sessions n, and concentration_flag (design-only 2/4 · 0.48/2.34 · true; general-multi-file 4/13 · 0.03/8.31 · false; harness-mechanism 4/13 · 0.04/6.90 · false; schema-migration 0/0 · 0.24/13.52 · true).
   Result: PASS
7. PER-ROW ground-truth cross-check against git (independent of the miner), plan `cockpit-v2-push-materialized-store`:
   Command: git log --follow --format=%aI -- docs/plans/archive/cockpit-v2-push-materialized-store.md (head/tail) ; grep -cE checked-checkbox ; grep -oE 'worktree +agent-[A-Za-z0-9]+' | sort -u
   Output: first 2026-07-14T07:27:13-07:00, last 2026-07-17T15:22:58-07:00 (= 3.3304 d), 8 checked boxes, 3 distinct agent markers — the artifact row says first/last identical, wall_clock_days 3.33, task_count 8, builder_sessions 3. Exact match on all four fields.
   Result: PASS
8. HONEST-DATA property: tokens_pct == 0 is a measurement, not a dead code path.
   (a) NEGATIVE (corpus): the anchored Tokens-key regex run over `cat docs/plans/archive/*.md` returns 0 hits — the pattern genuinely matches nothing in the real corpus.
   (b) POSITIVE CONTROL (verifier-built fixture repo carrying `Tokens: 120k` in evidence plus the decoy prose "a 1,000,000 token context window"): the miner returned tokens 120000 and tokens_pct 100 — the extractor WORKS, and the free-prose decoy was NOT promoted to an actual (the fd48741 Major F-C honest-data law holds under adversarial input; a leak would have produced 1000000).
   Result: PASS — 0% is truthful.
9. HONEST-DATA property: builder_sessions coverage 1.2% with nulls, never imputed.
   Command: cat docs/plans/archive/*.md | grep -oE 'worktree +agent-[A-Za-z0-9]+' | sort -u | wc -l
   Output: 4 distinct markers corpus-wide; the artifact attributes exactly 3 + 1 = 4 to the only two plans that carry them (2/163 = 1.2%; harness-mechanism 2/90 = 2.2%); every other class publishes p50/p90 null (NOT 0) with coverage_pct 0. The rendered .md repeats the null-means-unrecorded note.
   Result: PASS
10. SURFACING END-TO-END (the user-facing exercise; verifier-built fixture, NOT the builder's self-test): fixture plan `verifier-fixture-plan.md` in a git-less temp dir with `loe-class: harness-mechanism` + a byte-identical copy of the REAL docs/loe/loe-calibration.json (md5 a4b7c0dd4accdd71fac202a6bcf6018a on both sides) at `<fixture>/docs/loe/`.
    Command: bash adapters/claude-code/hooks/plan-reviewer.sh <fixture>/verifier-fixture-plan.md
    Output (stderr, rc=0): "[plan-reviewer] INFO Check 18 (LOE class+band, accountable-estate T7): class harness-mechanism: n=90 task_count P50/P90 4/13 — wall_clock_days P50/P90 0.04/6.90 — builder_sessions P50/P90 1/1 (coverage 2.2%) — concentration_flag false"
    REAL mined numbers (n=90), identical to the committed artifact. Result: PASS
11. BEHAVIOR-DIFFERENTIAL probes on Check 18 (wired != reached != behaving — the output must CHANGE across values, and the band must disappear when its input does). All 8 branches executed by the verifier against the same fixture:
    (a) loe-class: design-only -> INFO band "n=5 task_count 2/4 — wall_clock 0.48/2.34 — builder_sessions null/null (coverage 0%) — concentration_flag true" (DIFFERENT real numbers, matching the artifact's design-only row -> the line is read from the table per class, not hardcoded), rc=0
    (b) loe-class: ui-feature (valid class, zero mined plans) -> WARN "has zero mined plans in that class yet", rc=0
    (c) artifact ABSENT (RED for the band line) -> WARN "no calibration table found at docs/loe/loe-calibration.json yet"; the INFO band line does NOT render, rc=0
    (d) artifact CORRUPT -> WARN "present but NOT valid JSON — regenerate it" (distinct from (c): the fd48741 Major F-D corrupt-vs-empty split, verified live), rc=0
    (e) no loe-class + lifecycle-schema: v2 -> WARN "this plan lacks a 'loe-class:' header field" (the creation-time nudge), rc=0
    (f) no loe-class + NO lifecycle-schema (legacy vintage) -> SILENT (the v2 vintage gate that makes the nudge satisfiable; ~30 pre-T7 ACTIVE plans never flagged), rc=0
    (g) Status: COMPLETED -> SILENT, rc=0
    (h) baseline re-run after restoring the artifact -> INFO band renders again unchanged.
    Every branch exit 0 — Check 18 never blocks. Result: PASS
12. REGRESSION probe (does inserting Check 18 disturb checks 1-17 on real input?):
    Command: bash adapters/claude-code/hooks/plan-reviewer.sh docs/plans/accountable-estate-program-2026-07.md
    Output: RC=1 with 13 pre-existing findings from Checks 3/4/5/6b/10/13 rendering normally, and ZERO Check 18 lines (correct — this legacy plan has no lifecycle-schema, branch (f)). The surrounding machinery is intact. Result: PASS
13. Manifest + template wiring: `bash adapters/claude-code/scripts/manifest-check.sh` -> "[manifest-check] GREEN — 137 entries, 116 hooks covered, 0 warn" (the b5dfaf1 schema fix for ../scripts/ refs holds); templates/plan-template.md:88 carries `loe-class: <schema-migration | ui-feature | harness-mechanism | design-only | general-multi-file>` with an explanatory comment block — the creation-time writer half of "every new plan carries class annotations". Result: PASS
14. LIVE-INSTALL check (the maintainer is the user; does the mechanism actually reach them?): md5sum ~/.claude/hooks/plan-reviewer.sh == repo source (017cb7d37ee4840d1907798cb1de43f7) and ~/.claude/scripts/loe-backfill.sh == repo source (a3b0467a1d50eddcd0f9174c3a7b0d94); ~/.claude/templates/plan-template.md carries loe-class. The shipped surfaces are installed and live, not repo-only. Result: PASS
15. Review record: docs/reviews/records/2026-07-29-harness-change-review-302003c9.json exists, record_id hcr-20260729-302003c9, verdict PASS, plan_ref names T7, change_ref b5dfaf1. Its 5 covered_files blob SHAs were compared by the verifier against `git rev-parse HEAD:<path>` — ALL FIVE MATCH EXACTLY (loe-backfill.sh 3c46197, plan-reviewer.sh 117c1a7, pre-commit-gate.sh d22a497, manifest.json 80bd7c7, manifest-check.sh 72feeff), i.e. the record covers the bytes that actually shipped, not a stale draft. Result: PASS
16. Syntax floor: bash -n on plan-reviewer.sh and loe-backfill.sh — both clean. Result: PASS

Runtime verification: test adapters/claude-code/scripts/loe-backfill.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::check18-real-artifact-band-harness-mechanism-n90
Runtime verification: test adapters/claude-code/scripts/loe-backfill.sh::verifier-tokens-anchor-positive-control-120k
Runtime verification: test adapters/claude-code/scripts/manifest-check.sh::manifest-check-green-137-entries-0-warn
Runtime verification: file docs/loe/loe-calibration.json::"plans_total": 163
Runtime verification: file adapters/claude-code/hooks/plan-reviewer.sh::INFO Check 18 (LOE class+band
Runtime verification: file adapters/claude-code/templates/plan-template.md::loe-class:
Runtime verification: functionality-verifier T7::SKIP (rationale: no Task tool in this verifier environment; the user-shaped exercise — a maintainer authoring a v2 plan with a loe-class and seeing its mined band at review time — was executed inline by the verifier against the REAL committed artifact, plus 8 branch-differential probes and a tokens positive/negative control; plan is acceptance-exempt harness-internal, maintainer-is-user per constitution §4)

DEPENDENCY TRACE
================
Step 1: the maintainer creates a plan from the house template, which now carries a `loe-class:` field
  Verified at: adapters/claude-code/templates/plan-template.md:88 (+ comment block :89-95); live copy at ~/.claude/templates/plan-template.md confirmed carrying it
Step 2: plan-reviewer.sh runs on that plan (pre-commit-gate step 0b / PreToolUse on docs/plans/*.md) and reaches Check 18
  Verified at: plan-reviewer.sh:3262 (ACTIVE-or-unset status arm), :3263 (loe-class awk extraction); check 12 proves the surrounding 1-17 machinery still runs on a real plan
Step 3: Check 18 resolves the repo root and reads docs/loe/loe-calibration.json
  Verified at: plan-reviewer.sh:3277-3296; probes (c)/(d) prove the absent and corrupt inputs take distinct, non-blocking branches
Step 4: the mined P50/P90 bands + per-band n + concentration flag for THAT class render as an INFO line the maintainer reads
  Verified at: check 10 (harness-mechanism n=90 real numbers) and probe (a) (design-only n=5 — different real numbers, proving a per-class table read)
Step 5: the numbers themselves derive from the real archive + git history, honestly, with nulls where the signal is absent
  Verified at: checks 5-9 (163/163 corpus, recompute match, per-row git cross-check, tokens positive+negative control, builder_sessions marker count)

Git evidence:
  Files modified in recent history (all on master, tip 6ffe534):
    - adapters/claude-code/scripts/loe-backfill.sh (NEW; fd48741, b5dfaf1)
    - adapters/claude-code/hooks/plan-reviewer.sh (Check 18; fd48741, b5dfaf1)
    - adapters/claude-code/templates/plan-template.md (loe-class writer; b5dfaf1)
    - adapters/claude-code/manifest.json + scripts/manifest-check.sh + hooks/pre-commit-gate.sh (b5dfaf1)
    - docs/loe/loe-calibration.json + docs/loe/loe-calibration.md (6ffe534, 163 plans mined 2026-07-30T00:55:25Z)
    - docs/reviews/records/2026-07-29-harness-change-review-302003c9.json + records/index.json (9708ced)

Verdict: PASS
Confidence: 8
Reason: PROVEN — the mining half is correct against a pre-existing oracle the builder did not author: the artifact's 163 rows equal 100% of the on-disk archive corpus, its published class bands recompute exactly from its own per-plan rows, and one row (cockpit-v2-push-materialized-store) matches an independent `git log --follow` + checkbox-count + marker-count derivation on all four fields. The honest-data claims survived adversarial falsification rather than being taken on faith: a verifier-built positive control proved the token extractor WORKS (mined `Tokens: 120k` -> 120000) while REJECTING the decoy prose "1,000,000 token context window", so the corpus's tokens_pct 0 is a measurement (corpus grep for the anchored pattern = 0 hits), and builder_sessions 1.2% matches the 4 distinct `worktree agent-` markers that exist corpus-wide, published as nulls rather than imputed zeros. The surfacing half was exercised end-to-end against the REAL committed artifact (not the builder's synthetic self-test fixture): a maintainer-shaped v2 plan with `loe-class: harness-mechanism` renders "n=90 task_count P50/P90 4/13 — wall_clock_days 0.04/6.90 — builder_sessions 1/1 (coverage 2.2%) — concentration_flag false", and the output CHANGES to the design-only row's real numbers when the class changes, DISAPPEARS when the table is removed, and splits corrupt-from-empty when the table is broken — wired, reached, and behaving, across all 8 branches, every one exit 0 (never blocks). The whole mechanism is byte-identical in the live ~/.claude install, so it reaches the maintainer today. Confidence 8, not 9: (i) the ~100-scenario plan-reviewer suite still has not run end-to-end on this machine (characterized fork-tax class — one plan-reviewer invocation costs ~60-70 wall-seconds here; mitigated, not eliminated, by the verifier's own 8-branch Check 18 harness plus a real-plan regression probe showing checks 1-17 firing normally with zero Check 18 interference), and (ii) the outcome metric's second clause is an unbuilt seam, recorded below.

Residuals (weighed into the verdict, none of them refuting the delivered mechanism):
  - **Outcome-metric clause 2 ("actuals append at close") has NO mechanism and NO tracked owner.** The one-line splice is documented at an exact call site (loe-backfill.sh header :96-114 -> close-plan.sh cmd_close(), immediately before `emit_plan_completed_progress_log_event` at ~:1293) and is honestly named as unbuilt in the plan's own Files section (:149-155), the In-flight scope updates (:193-198), and the manifest's honesty_rationale — so nothing false is claimed anywhere. But T4's task text (the closer family that owns close-plan.sh) does not mention it, and no backlog row carries it: on this checkbox flip the obligation exists only in a code comment. THIS VERDICT CERTIFIES THE MINING + SURFACING MECHANISM ONLY; it does not certify that the calibration table refreshes at plan closure — today it does not, and it will silently go stale until someone re-runs the miner. Required follow-up (orchestrator, same turn as the commit): amend T4's task text to carry the splice, or file a backlog row for it.
  - Manifest `loe-backfill.jit_triggers.paths` (manifest.json:2841-2842) still lists `docs/plans/loe-calibration.json/.md` — stale after the fd48741 F-A move to `docs/loe/`. Harmless today (`doctrine_file` is null, so the trigger injects nothing), but it is a wrong path in a live manifest entry; the same stale spelling appears in that entry's `fp_expectation` and `honesty_rationale` prose while `golden_scenario` has the correct `docs/loe/`. One-line fix, not a mechanism defect.
  - Backlog row ESTATE-T7-LOE-BACKFILL-FULL-MINE-PENDING-01 (docs/backlog.md:1380) is now SATISFIED by 6ffe534 and should be closed; it still reads "not yet run to completion on this machine".
  - The review record's `covered_files` lists 5 of the 7 files b5dfaf1 touched — `templates/plan-template.md` (the creation-time writer, one of the 6 Majors) and `docs/backlog.md` carry no blob SHA, though the verdict_quote explicitly describes the template change as reviewed. Record-completeness nit; the 5 listed SHAs all match HEAD exactly.
  - P50/P90 use nearest-rank-LOWER, so at n=2 P90 collapses onto P50 (harness-mechanism builder_sessions publishes 1/1 while the underlying values are {1,3}). This is DOCUMENTED in the jq program's own header with exactly that n=2 example and mitigated by rendering n beside every band — a known, disclosed convention, not a hidden defect.
  - Check 18 resolves the table per-repo, so plans in downstream product repos (no docs/loe/) get the "run loe-backfill.sh" nudge rather than bands. Correct by design (calibration is per-corpus), noted so it is not later mistaken for a bug.

Outcome-metric note (Program rule 2): clause 1 ("every new plan carries class+band annotations") is forward-looking and cannot be a present fact at build time; what IS demonstrated present-tense is the full causal chain that produces it — the template writes the field, the v2-vintage-gated nudge catches plans that lack it, and a plan that has it renders real mined bands (checks 10/11/13/14). Clause 2 is the unbuilt seam above. Re-check date: at the next plan creation from the template (the nudge/band render is observable immediately) and at the next plan closure (which will demonstrate the staleness the missing splice implies).
Task description: LOE v1: per-PLAN actuals mining (archived plans + evidence + git history), 3-5 plan classes, P50/P90 bands + concentration flag surfaced by plan-reviewer. Outcome metric: every new plan carries class+band annotations; actuals append at close. Verification: full.
Verified at: 2026-07-30T07:55:00Z (flip same day)
Verifier: task-verifier — FAIL conf 9 (first Mac cross-check) -> two gating fixes at a8b114c -> targeted re-check -> PASS conf 9
Subject SHAs: fd48741 (desktop build) + b5dfaf1 (review remediation) + 6ffe534 (163-plan artifact) + a8b114c (Mac-gating fixes)

PROVEN with exact before/after pairs: loe-backfill scenario 4 FAIL("got null")/exit 1 both
interpreters at 8604509 -> "all scenarios matched expectations"/exit 0 both at a8b114c
(GNU `date -d` -> M4 dual-branch; the adversarial negative-offset probe on the BSD branch
held); the DECISIVE live mine on this Mac went wall_clock coverage 0% -> 100% with spot
values BYTE-IDENTICAL to the independently desktop-mined committed artifact (10.89==10.89,
13.93==13.93, 0.19==0.19 — two machines, two date implementations, same actuals); dd6
FAIL -> PASS both interpreters (`${4:-}` -> unset-only `${4-}`); mining honesty proven
against git-history ground truth (3/3 exact); surfacing re-demonstrated LIVE at a8b114c
(band INFO line + nudge WARN + vintage silence); review chain 9708ced genuine with both
spot-checked Majors landed.
Non-gating, classified: iv4 pre-existing at fd48741^ (filed PLAN-REVIEWER-IV4-MACOS-
PREEXISTING-01); append-at-close = operator-authorized WIP-1 deferral — OWNER: T9 (per
this flip, citing loe-backfill.sh's header splice spec); outcome metric is mechanism-true
via template+nudge, HYPOTHESIZED for the next template-created plan (refuter: that plan
lacking loe-class).

Runtime verification: test adapters/claude-code/scripts/loe-backfill.sh::--self-test (exit 0 both interpreters at a8b114c; exit 1 both at 8604509)
Runtime verification: test adapters/claude-code/hooks/plan-reviewer.sh::dd6 (PASS both at a8b114c; FAIL both at 8604509)
Runtime verification: file docs/loe/loe-calibration.json::plans_total
Runtime verification: file adapters/claude-code/templates/plan-template.md::loe-class

## Task T9 — Outcome-gated closure semantics (verifier record)

EVIDENCE BLOCK
==============
Task ID: T9
Task description: Outcome-gated closure semantics for harness plans (metric + re-check + auto-reopen), applied to THIS program first. LOE: MEDIUM, 2 bs. Verification: full.
Verified at: 2026-07-30T15:20:00Z
Verifier: task-verifier agent

Oracle: specified — the task's own three-part contract (metric + re-check + auto-reopen + "applied to THIS program first") + the harness-internal functionality signal (--self-test on both interpreters) + a real production plan closure as live demonstration (c7b8c22/43117a0).

Comprehension-gate: skipped — rung field missing (plan has no `rung:` header; treated as rung 0 per Decision 020a)

Operator invariants: none registered (exit 3)

Checks run:
1. close-plan.sh self-test, system bash
   Command: /bin/bash adapters/claude-code/scripts/close-plan.sh --self-test
   Output: self-test summary: 30 passed, 0 failed (of 27 scenarios); EXIT=0
   Result: PASS
2. close-plan.sh self-test, Homebrew bash
   Command: /opt/homebrew/bin/bash adapters/claude-code/scripts/close-plan.sh --self-test
   Output: 30 passed, 0 failed; EXIT=0. T9 regression scenarios present and green: S22 prose-mention-does-not-orphan-verdict, S23 outcome-gated-plan-missing-section-blocks, S24 outcome-gated-plan-closes-preserves-metric-plus-t7-splice-plus-event, S25 non-opted-in-plan-still-gets-default-outcome-section (observe-only), S26 scope-slash-tasks-heading-variant, S27 multiline-outcome-metric-survives-verbatim.
   Result: PASS
3. plan-recheck-sweep.sh self-test, both interpreters
   Command: /bin/bash (and /opt/homebrew/bin/bash) adapters/claude-code/scripts/plan-recheck-sweep.sh --self-test
   Output: 8 passed, 0 failed on BOTH (past-date reopens; future-date does not; recurrence-nonzero reopens; recurrence-zero does not; idempotent 2nd sweep; unparseable-date skip; --quick silent/one-line; S8 plan_reopened event asserted)
   Result: PASS
4. session-start-digest.sh self-test
   Command: /opt/homebrew/bin/bash adapters/claude-code/hooks/session-start-digest.sh --self-test → 91/91 OK. /bin/bash → 88 passed, 3 failed; failures are S1 monitor-alerts + S4 auto-ack ONLY (pre-existing on bash 3.2); T9's S21a/S21b feed_plan_recheck scenarios PASS on BOTH interpreters.
   Result: PASS (3 failures pre-existing, isolated, not T9 scenarios)
5. manifest-check
   Command: bash adapters/claude-code/scripts/manifest-check.sh
   Output: [manifest-check] GREEN — 148 entries, 122 hooks covered, 0 warn; entry id=plan-recheck-sweep at entries/145 with golden_scenario naming T9
   Result: PASS
6. Live sweep probe against the real repo (read path of the production wiring)
   Command: bash adapters/claude-code/scripts/plan-recheck-sweep.sh --quick --repo /Users/misha/Claude/neural-lace
   Output: empty, exit 0 — correct: the only archived Closure Outcome (context-watermark-opus5-window) has a future Re-check date 2026-09-28T00:00:00Z
   Result: PASS
7. Parser-fix RED arm (pre-fix source inspected, not trusted from the commit message)
   Command: git show 7f74f54^:adapters/claude-code/scripts/close-plan.sh | grep -n 'Task\[\[:space:\]\]'
   Output: old awk block boundary at old-line 423 was /Task[[:space:]]+(ID:[[:space:]]*)?[A-Za-z0-9.-]+/ — matches ANY "Task <word>" prose line (e.g. "Task description:"), resetting found_id/found_pass and orphaning real verdicts; old found_pass accepted only "Verdict: PASS". New code (close-plan.sh:604-613) anchors to literal ^Task ID: and accepts "PASS conf N" (close-plan.sh:591). S22 is the pinned regression.
   Result: PASS (bug real before, fixed after, regression scenario pinned)
8. "Applied to THIS program first"
   Files: docs/plans/accountable-estate-program-2026-07.md:9 `outcome-gated: true` + populated ## Closure Outcome (lines 211-228) with a non-placeholder Outcome metric and Re-check date: 2026-08-13T05:56:00Z
   Result: PASS
9. Live demonstration closure (real production run, not fixture)
   Files: docs/plans/archive/context-watermark-opus5-window.md — Status: COMPLETED, populated ## Closure Outcome (metric lines 155-158; bare machine-parseable Re-check date line 159 `2026-09-28T00:00:00Z`; Evidence pointers present); unarchived original absent from docs/plans/ (ls confirms). T7 append-at-close splice fired live: docs/loe/loe-calibration.json plans_total == 166 (was 163), regenerated in 43117a0 by the demo close itself. macos-portability-2026-07.md remains OPEN in docs/plans/ (deliberately not closed, M6 unfinished) — consistent.
   Result: PASS
10. Events + emitter registration
   File: adapters/claude-code/hooks/lib/progress-log-lib.sh:396-412 (plan_outcome_recorded, plan_reopened natural keys), :153 (_PL_KNOWN_EMITTERS includes plan-recheck-sweep). Asserted at runtime by close-plan S24 and sweep S8.
   Result: PASS
11. Docs impact: plan predates the `Docs impact:` convention (no task in this plan carries the field) — grandfathered per verifier protocol.

Runtime verification: test adapters/claude-code/scripts/close-plan.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/plan-recheck-sweep.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/session-start-digest.sh::--self-test
Runtime verification: file docs/plans/archive/context-watermark-opus5-window.md::Re-check date: 2026-09-28T00:00:00Z
Runtime verification: file docs/plans/accountable-estate-program-2026-07.md::outcome-gated: true
Runtime verification: functionality-verifier T9::SKIP (rationale: harness-internal mechanism with --self-test; the maintainer-facing functionality signal — self-tests on both interpreters plus a live --quick invocation and a real production close in git history — was exercised directly by this verifier; no Task tool available in this verification environment)

DEPENDENCY TRACE
================
Step 1: maintainer runs `close-plan.sh close <slug>` on an outcome-gated plan
  ↓ Verified at: close-plan.sh:1494 (verify_closure_outcome_declared gate, opt-in via `outcome-gated: true`) — S23 blocks placeholder/missing section
Step 2: close writes ## Closure Outcome unconditionally (observe-only for non-opted-in plans)
  ↓ Verified at: close-plan.sh:1590 (write_closure_outcome_section) — S24 preserves author metric verbatim, S25 default section, S27 multiline verbatim; live demo archive file lines 151-184
Step 3: T7 append-at-close splice fires
  ↓ Verified at: close-plan.sh:1690 (`bash "$SCRIPT_DIR/loe-backfill.sh" ... || true`, the seam loe-backfill.sh documents) — live proof: loe-calibration.json plans_total 163→166 in 43117a0
Step 4: plan_outcome_recorded event emitted
  ↓ Verified at: progress-log-lib.sh:396-403 — asserted by close-plan S24
Step 5: next session start → digest chokepoint invokes the sweep
  ↓ Verified at: session-start-digest.sh:1353 (call site) → :619 feed_plan_recheck → plan-recheck-sweep.sh --quick — S21a/b green on BOTH interpreters; live --quick run silent/exit 0
Step 6: passed re-check date or failing recurrence command → auto-reopen (git mv back, Status flip, Reopen Log, backlog row, needs-you entry, plan_reopened event; idempotent)
  ↓ Verified at: plan-recheck-sweep.sh self-test S1-S8 (8/8 both interpreters), progress-log-lib.sh:404-412

Git evidence:
  Files modified in recent history (all within the T9 window, 2026-07-30):
    - adapters/claude-code/scripts/close-plan.sh (7f74f54)
    - adapters/claude-code/scripts/plan-recheck-sweep.sh (NEW, 9135fb7)
    - adapters/claude-code/hooks/session-start-digest.sh (9135fb7)
    - adapters/claude-code/hooks/lib/progress-log-lib.sh (7f74f54)
    - adapters/claude-code/manifest.json (7f74f54)
    - docs/plans/archive/context-watermark-opus5-window.md (c7b8c22 close, 43117a0 truncation correction)
    - docs/loe/loe-calibration.json/.md (43117a0)
    - docs/backlog.md ESTATE-T9-EVIDENCE-POINTERS-NOISE-01 follow-up (5ea5d29)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all three halves of the task's contract were independently re-executed against real oracles — (1) metric+re-check WRITE half: close-plan.sh --self-test 30/0 on BOTH /bin/bash 3.2.57 and Homebrew bash with the six T9 scenarios green, plus a real production closure (context-watermark-opus5-window archived COMPLETED with populated Closure Outcome and the unarchived original gone); (2) AUTO-REOPEN half: plan-recheck-sweep.sh --self-test 8/8 both interpreters + live --quick probe silent/exit-0 against the real archive + SessionStart wiring green (S21a/b both interpreters); (3) "applied to THIS program first": outcome-gated: true + populated Closure Outcome with metric and re-check date in this plan itself. The parser-fix RED arm was verified against the actual pre-fix source (7f74f54^), not taken from the commit message. Known residue: ESTATE-T9-EVIDENCE-POINTERS-NOISE-01 (noisy Evidence pointers) filed in backlog by design, and the sweep's honest-gap disclosure (interactive-session chokepoint, not a true periodic tick) is documented in the script header — neither contradicts the task contract.
