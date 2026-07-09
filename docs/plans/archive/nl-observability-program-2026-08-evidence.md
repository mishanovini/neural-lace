# Evidence Log — NL Observability Program — derived-truth cockpit + six-questions estate visibility

## Task O.5 — Push (ntfy.sh) — terminal disposition: DESCOPED by operator

EVIDENCE BLOCK
==============
Task ID: O.5
Task description: Push (ntfy.sh): exactly three rules — NEEDS-YOU created, session stalled/throttled >N min, doctor RED; registration + drill — Model: sonnet. TERMINAL DISPOSITION: descoped by operator 2026-07-07; original Done-when (phone drill) superseded, not satisfiable by directive.
Verified at: 2026-07-07T09:15:00Z
Verifier: task-verifier agent

Oracle: specified — the operator's explicit descope directive 2026-07-07 ("no interest in ntfy... don't need observability from my phone"); the verification bar for a user-descoped task is the completeness and mechanical truth of the terminal-disposition record, not the superseded Done-when.

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Plan O.5 block carries the DESCOPED disposition naming directive + date
   Command: git show c767ddd -- docs/plans/nl-observability-program-2026-08.md
   Output: +9 lines: 'DESCOPED by operator 2026-07-07 ("no interest in ntfy... don't need observability from my phone" ...) ... task closes as descoped-by-operator' — landed on master via PR #89 squash c767dddda41053b304e13c92ef00852eb7d58761 (origin/master). Same block applied verbatim to the main-checkout working copy in this verification (local master at d141119 is behind origin; ff blocked by another session's uncommitted docs/backlog.md — identical-content lines merge clean at next pull).
   Result: PASS
2. Build evidence real: origin branch + SHA
   Command: git ls-remote origin refs/heads/build/wave-o-o5
   Output: d8741b0b2c3bafa26feeb93bce5b75ef7908fc1e refs/heads/build/wave-o-o5 (tip commit: "build(wave-o-o5): ntfy.sh push — send/scan verbs + guarded needs-you call")
   Result: PASS
3. Self-test covers topic-absent no-op and unknown-class rejection — EXECUTED, not just read
   Command: git show d8741b0:adapters/claude-code/scripts/ntfy-push.sh > "$SCRATCH/ntfy-push.sh" && bash "$SCRATCH/ntfy-push.sh" --self-test
   Output: RESULT: 18 passed, 0 failed (exit 0). T1/T1b: topic-absent send exits 0, no network attempt recorded (mocked curl recorder log empty); T2/T2b: unknown --class rejected exit 1, no network attempt; T6: unknown class rejected even with topic present; T13/T13b: topic-absent scan does not burn pending item ids. Matches the disposition's "18/18 incl. the negative" claim exactly. NOTE: first replay showed 17/18 — T12 (flagless self-reinvocation via $_NTFY_SELF_DIR/ntfy-push.sh) failed exit 127 because the verifier extracted the file under a non-canonical name; re-extraction as ntfy-push.sh → 18/18. Replay artifact, not a script defect. Script path on the branch is adapters/claude-code/scripts/ntfy-push.sh (repo-canonical), not scripts/ntfy-push.sh as the invocation claimed — noted, not verdict-affecting.
   Result: PASS
4. Dormancy mechanically true on this machine
   Command: ls -la "$HOME/.claude/local/ntfy-topic"
   Output: No such file or directory (exit 2). Additionally: script absent from origin/master tree (git ls-tree origin/master adapters/claude-code/scripts/ntfy-push.sh → empty) and absent from installed ~/.claude/scripts/ — the push surface cannot fire at all; by the self-tested topic-absent contract it would be a silent no-op even if installed.
   Result: PASS
5. specs-o §O.5 DESCOPED banner on master
   Command: git show c767ddd -- docs/plans/nl-observability-program-2026-08-specs-o.md
   Output: +5 lines under '## §O.5 Push (ntfy.sh) — exactly three rules': '> **DESCOPED by operator 2026-07-07** ... spec text below retained for the record.' — on origin/master via c767ddd; local checkout receives it at next pull.
   Result: PASS

Runtime verification: file docs/plans/nl-observability-program-2026-08.md::DESCOPED by operator 2026-07-07
Runtime verification: test adapters/claude-code/scripts/ntfy-push.sh@d8741b0::--self-test (18/18 PASS; replay: git show d8741b0:adapters/claude-code/scripts/ntfy-push.sh > /tmp/ntfy-push.sh && bash /tmp/ntfy-push.sh --self-test)

DEPENDENCY TRACE (descope record chain)
================
Step 1: Operator directive 2026-07-07 — no phone observability
  ↓ Recorded at: plan O.5 DESCOPED block (c767ddd, PR #89) + specs-o §O.5 banner
Step 2: Built artifact disposed dormant-by-design
  ↓ Verified at: build/wave-o-o5 @ d8741b0, adapters/claude-code/scripts/ntfy-push.sh --self-test 18/18 (T1/T1b topic-absent no-op; T2/T2b+T6 unknown-class negative)
Step 3: Dormancy precondition on this machine
  ↓ Verified at: ~/.claude/local/ntfy-topic ENOENT; script not on master, not installed
Step 4: Consumer-map law 2 disposition
  ↓ Recorded at: plan DESCOPED block — push:* consumers removed at batch-2 integration; three classes keep digest/cockpit/cli consumers

Git evidence:
  origin/master: c767dddda41053b304e13c92ef00852eb7d58761 "ops(wave-o): O.5 operator descope ..." (#89, 2026-07-06 21:57 -0700) — plan +9, specs-o +5
  build branch: refs/heads/build/wave-o-o5 @ d8741b0b2c3bafa26feeb93bce5b75ef7908fc1e

Verdict: PASS
Confidence: 9
Reason: PROVEN: closure basis is descoped-by-operator, not built-to-Done-when. The terminal-disposition record is complete (directive quoted + dated in plan and specs on master via c767ddd), and every mechanical claim in it was independently replayed: branch SHA matches ls-remote; the cited 18/18 self-test was re-executed from the exact ref and passed 18/18 including both negatives; the dormancy precondition (~/.claude/local/ntfy-topic absent) holds on this machine. Original Done-when (phone drill) is superseded by the same directive and does not gate closure.

## Task O.3 — Derivation lib + CLI (`nl status|needs-me|why|costs`) — RE-VERIFIED PASS

EVIDENCE BLOCK
==============
Task ID: O.3
Task description: Derivation lib + CLI (`nl status|needs-me|why|costs`): computes Q1-Q5 from ground truth only; `nl why` replays ledger+transcript for a session's last block. Done-when: each of Q1-Q5 answered <10s on live estate; `nl why` reconstructs a seeded gate-block chain end-to-end (024-class fixture).
Verified at: 2026-07-08T21:25:00-07:00
Verifier: task-verifier agent (re-verification against LIVE installed estate == origin/master 470f7fa)

Oracle: specified — plan Goal + Done-when (Q1-Q5 <10s; nl why reconstructs the 024 chain); derived-metamorphic for nl why (chain must name writer+gate+retry+verdict).

Comprehension-gate: not applicable (rung 1 < 2)

Full detail (load context, timing table, cache-persistence, self-test): docs/plans/nl-observability-program-2026-08-evidence/O.3.evidence.md

Timing on live estate (breaker=0 every run; all reproducible measurements <10s):
  Q1 status   3828/4230/4404/4103 ms
  Q2 needs-me 455/554/479/381 ms
  Q3 shipped  773/834/783/652 ms
  Q4 why      1922 ms (real session 442916d1, --last-block --json)
  Q5 costs    6.5-9.6s reproducible (controlled cold-app rebuild 9581ms; steady 6.5-7.0s);
              single non-reproducible cold-OS-first-touch 11255ms documented as caveat
Cache persistence: obs-costs-cache.json entries STABLE run-over-run (17,17,17,17 / 10,10,10) — no 10->2 oscillation; prior cache defect FIXED.
024 reconstruction: observability-derive.sh --self-test 69/69 (scenarios 8/8a/8b/8c/8d PASS) + live 442916d1 verdict names stop-verdict-dispatcher + 3 gaps.

Runtime verification: test adapters/claude-code/hooks/lib/observability-derive.sh::--self-test
Runtime verification: file docs/plans/nl-observability-program-2026-08-evidence/O.3.evidence.md::TIMING DRILL

Verdict: PASS
Confidence: 8
Reason: PROVEN — all five questions answered <10s on the live installed estate in steady-state AND controlled-cold; nl why reconstructs the 024-class chain (self-test 69/69) and a real live block chain; costs cache persists run-over-run (no oscillation). One non-reproducible cold-OS-first-touch (11255ms) documented as a HYPOTHESIZED caveat with refuter for O.7 retro; it does not gate closure since the reproducible worst case (9581ms) is <10s.

## Task O.9 — Backlog accountability loop (RE-VERIFY; prior FAIL conf 9 on clause 4 now resolved)

EVIDENCE BLOCK
==============
Task ID: O.9
Task description: Backlog accountability loop (operator directive 2026-07-06) — age-tiered digest surfacing + plan-time absorption matching + KPI backlog-health section. RE-VERIFY of the clause-4 FAIL: the operator SCHEDULE disposition on GH-AUTH-AUTOSWITCH-WORKORG-01 must move the row to a terminal-for-the-loop state (out of overdue re-surfacing) without falsely marking it done.
Verified at: 2026-07-08T00:00:00Z
Verifier: task-verifier agent (RE-VERIFY)

Oracle: specified — Done-when clause 4, exercised LIVE against the real docs/backlog.md via od_backlog_health --json. Correct state for a SCHEDULE answer whose build has not merged: overdue_ids excludes the row + dispositioned_in_flight=true + terminal=false.

Comprehension-gate: not applicable (rung: 1)

Crux observation (live oracle): source ~/.claude/hooks/lib/observability-derive.sh; BACKLOG_MD_PATH=<repo>/docs/backlog.md od_backlog_health --json (exit 0). .summary.overdue_ids == [COMPLETION-AUDIT-DEPTH-DOWNSTREAM-01, PT-FORK-SYNC-NOT-RUNNING-01, HARNESS-GAP-45, HARNESS-GAP-51] — GH-AUTH-AUTOSWITCH-WORKORG-01 NOT present. GH-AUTH row: terminal=false, dispositioned_in_flight=true, is_overdue=false, age_days=38, threshold_days=30, inflight_date=2026-07-07. dispositioned_in_flight_ids includes GH-AUTH. Adversarial probe: age 38 > threshold 30 would force is_overdue=true but for the SCHEDULED marker — the suppression is load-bearing, not vacuous. Clauses 1-3 re-derived green (observability-derive 69/69 incl. dispositioned-in-flight SCHED-ROW-01; plan-edit-validator 15/15; harness-kpis 13/13). The lone session-start-digest S2 failure is an unrelated feed-12 unresolved-gaps fixture-isolation leak, orthogonal to O.9.

Full per-task evidence: docs/plans/nl-observability-program-2026-08-evidence/O.9.evidence.md

Runtime verification: test adapters/claude-code/hooks/lib/observability-derive.sh::--self-test  (69/69 PASS; dispositioned-in-flight SCHED-ROW-01 scenario: overdue_ids excludes the SCHEDULED row, terminal=false, dispositioned_in_flight=true)
Runtime verification: test adapters/claude-code/hooks/plan-edit-validator.sh::--self-test  (15/15 PASS; clause 2 absorption warn F13/F14/F15)
Runtime verification: test adapters/claude-code/scripts/harness-kpis.sh::--self-test  (13/13 PASS; clause 3 Backlog Health section)
Runtime verification: file docs/backlog.md::SCHEDULED 2026-07-07  (GH-AUTH-AUTOSWITCH-WORKORG-01 row carries the operator SCHEDULE disposition marker)

Verdict: PASS
Confidence: 9
Reason: PROVEN: live od_backlog_health shows GH-AUTH out of overdue_ids and dispositioned_in_flight=true / terminal=false — clause 4 satisfied via the real operator round-trip (SCHEDULE -> row leaves overdue re-surfacing) without falsely marking done. Clauses 1-3 green. The S2 digest self-test failure is an unrelated feed-12 fixture-isolation leak.
