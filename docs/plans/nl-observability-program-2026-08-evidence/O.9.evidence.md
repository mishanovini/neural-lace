# Task O.9 — Backlog accountability loop (RE-VERIFY of prior FAIL on clause 4)

EVIDENCE BLOCK
==============
Task ID: O.9
Task description: Backlog accountability loop (operator directive 2026-07-06): (1) age-tiered digest surfacing with one-word disposition proposals, idempotent per item-week; (2) plan-time absorption matching in plan-edit validation; (3) KPI backlog-health section + terminal-state batch proposal. RE-VERIFY: prior verdict FAIL conf 9 on clause 4 (operator SCHEDULE disposition was invisible to od_backlog_health, so the row read overdue and would re-nag).
Verified at: 2026-07-08T00:00:00Z
Verifier: task-verifier agent (RE-VERIFY)

Oracle: specified — Done-when clause 4 (operator answers one digest proposal word and the row reaches terminal state), exercised LIVE as a round-trip against the real docs/backlog.md via od_backlog_health. Correct terminal-for-the-loop state for a SCHEDULE answer whose build has NOT merged: row leaves overdue_ids + dispositioned_in_flight=true + terminal=false (dispositioned, tracked, not re-surfaced, not falsely done).

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. CRUX (clause 4) — LIVE oracle round-trip on the real backlog
   Command: source observability-derive.sh; BACKLOG_MD_PATH=<repo>/docs/backlog.md od_backlog_health --json  (exit 0, 102998 bytes)
   Output (jq): .summary.overdue_ids == [COMPLETION-AUDIT-DEPTH-DOWNSTREAM-01, PT-FORK-SYNC-NOT-RUNNING-01, HARNESS-GAP-45, HARNESS-GAP-51] — GH-AUTH-AUTOSWITCH-WORKORG-01 NOT present (index -> NOT_PRESENT).
     GH-AUTH row facts: terminal=false, dispositioned_in_flight=true, is_overdue=false, age_days=38, threshold_days=30, inflight_date=2026-07-07, terminal_date=null.
     .summary.dispositioned_in_flight_ids == [RESUMER-SCHEDULED-EXIT1-01, HARNESS-GAP-48, GH-AUTH-AUTOSWITCH-WORKORG-01] (GH-AUTH at index 2).
   Result: PASS — row left overdue_ids via the dispositioned-in-flight state; honest (terminal=false, build not merged); will not re-nag.
2. ADVERSARIAL PROBE — the suppression does real work (not vacuous)
   Observation: GH-AUTH age_days=38 exceeds medium threshold_days=30, so without the dispositioned-in-flight suppression is_overdue would be TRUE and the row WOULD be in overdue_ids (the exact re-nag bug the prior FAIL cited). The SCHEDULED 2026-07-07 marker (parsed as inflight_date) flips is_overdue -> false, WITHOUT marking the row terminal/closed.
   Result: PASS
3. Digest consumer cannot re-surface a dispositioned row
   Command: grep -n overdue_ids session-start-digest.sh (line 923 reads doc.summary.overdue_ids)
   Output: the backlog-accountability feed builds its candidate list from the oracle overdue_ids; a row absent from overdue_ids never reaches the feed. S16e self-test asserts a SCHEDULED-marked row yields empty feed output (S16e SCHEDULED-marked row is silent, dispositioned-in-flight, never re-nags).
   Result: PASS
4. observability-derive self-test (oracle-level regression)
   Command: bash observability-derive.sh --self-test
   Output: 69 passed, 0 failed (exit 0). Includes dispositioned-in-flight scenario SCHED-ROW-01: overdue_ids excludes the SCHEDULED row; terminal=false, dispositioned_in_flight=true (distinct third state, not done/closed).
   Result: PASS
5. Clause 2 — plan-time absorption matching
   Command: bash plan-edit-validator.sh --self-test
   Output: 15 passed, 0 failed. F13 backlog-surface-match-unabsorbed-warns PASS; F14 absorbed-header-naming-the-id-silences PASS; F15 e2e-prose-edit-allowed-with-absorption-warn PASS.
   Result: PASS
6. Clause 3 — KPI backlog-health section
   Command: bash harness-kpis.sh --self-test
   Output: 13 passed, 0 failed. report contains Backlog Health section; open/terminal counts; priority breakdown; aging histogram; flow counts.
   Result: PASS
7. Fix merged + installed live
   Output: fix in master history (048add3 merge O.9 backlog-build-escalation; d78e29c oracle-level dispositioned-in-flight coverage; f731832). Live lib and repo lib both contain the state (15 matching lines each). HEAD == origin/master == 470f7fa on branch tmp/o4-flip.
   Result: PASS
8. UNRELATED failure noted honestly (does NOT affect any O.9 clause)
   Command: bash session-start-digest.sh --self-test
   Output: 70 passed, 1 failed (exit 1). Single failure is S2 all-quiet: feed_unresolved_gaps (feed 12, session-start-digest.sh:593) reads the LIVE HOME/.claude/state/unresolved-gaps.jsonl (15 real entries on this machine) instead of a sandboxed path, so the quiet baseline emits an unresolved-gaps line. Pre-existing fixture-isolation leak in a feed ORTHOGONAL to the O.9 backlog-accountability feed; every O.9-specific scenario (S16 series incl. S16e) PASSES. Not verdict-affecting for O.9.
   Result: SKIPPED (out of scope for O.9; environmental leak in feed 12)

Runtime verification: test adapters/claude-code/hooks/lib/observability-derive.sh::--self-test  (69/69 PASS; dispositioned-in-flight SCHED-ROW-01 scenario)
Runtime verification: test adapters/claude-code/hooks/plan-edit-validator.sh::--self-test  (15/15 PASS; clause 2 F13/F14/F15)
Runtime verification: test adapters/claude-code/scripts/harness-kpis.sh::--self-test  (13/13 PASS; clause 3 Backlog Health section)
Runtime verification: file docs/backlog.md::SCHEDULED 2026-07-07  (GH-AUTH row carries the operator SCHEDULE marker that flips is_overdue -> false)

DEPENDENCY TRACE (clause 4 operator round-trip)
================
Step 1: Operator answers the digest proposal with SCHEDULE
  -> Verified at: docs/backlog.md GH-AUTH row carries **SCHEDULED 2026-07-07** (operator disposition, O.9 acceptance round-trip)
Step 2: Oracle re-derives the row state from the marker
  -> Verified at: od_backlog_health --json (live) -> GH-AUTH dispositioned_in_flight=true, terminal=false, is_overdue=false, inflight_date=2026-07-07
Step 3: Row leaves the overdue set without being marked done
  -> Verified at: .summary.overdue_ids excludes GH-AUTH; .summary.dispositioned_in_flight_ids includes it; terminal=false (honest, build not merged)
Step 4: Digest consumer cannot re-nag
  -> Verified at: session-start-digest.sh:923 reads doc.summary.overdue_ids; S16e self-test asserts a SCHEDULED row yields empty feed output

Git evidence:
  Files (fix): observability-derive.sh (dispositioned_in_flight state), session-start-digest.sh, plan-edit-validator.sh, harness-kpis.sh
    - landed on master: 048add3 (merge O.9 backlog-build-escalation), d78e29c (dispositioned-in-flight coverage), f731832
  HEAD == origin/master == 470f7faeb056fb3fd55fdba89b4f32ad960e113e (branch tmp/o4-flip)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the live od_backlog_health oracle against the real docs/backlog.md shows GH-AUTH-AUTOSWITCH-WORKORG-01 is NOT in .summary.overdue_ids and reads dispositioned_in_flight=true with terminal=false — the exact terminal-for-the-loop state clause 4 requires: the operator one-word SCHEDULE answer moved the row out of overdue re-surfacing WITHOUT falsely marking it done (build not merged; honest state reflects that). Adversarial probe confirmed the suppression is load-bearing (age 38 > threshold 30 would otherwise force is_overdue=true, the prior re-nag bug). The digest consumer keys off overdue_ids and S16e proves a SCHEDULED row is silent, so no re-nag path exists. Clauses 1-3 re-derived green (observability-derive 69/69, plan-edit-validator 15/15, harness-kpis 13/13). The single session-start-digest S2 failure is an unrelated feed-12 unresolved-gaps fixture-isolation leak, orthogonal to O.9 and not verdict-affecting.
