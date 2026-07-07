# Evidence — Task O.2 (Session heartbeat)

EVIDENCE BLOCK
==============
Task ID: O.2
Task description: Session heartbeat: liveness file per session (pid, cwd, branch, last-activity, marker-state, model); staleness = crash signal — Done-when: kill-drill — killed session's heartbeat goes stale and `nl status` reports stalled within one refresh.
Verified at: 2026-07-07T11:40:00Z
Verifier: task-verifier agent (adversarial re-derivation; independent drill replay, not the builder's run)

Oracle: specified — the plan's Done-when kill-drill: a killed (dead-pid) session's heartbeat must be classified stale/crashed by `nl status` within one refresh, computed on read from ground truth (law 1 DERIVE-DON'T-MAINTAIN).

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Task-text match (caller vs plan line 52-55)
   Result: PASS — exact match.
2. Git evidence
   Command: git log --oneline -- adapters/claude-code/scripts/session-heartbeat.sh adapters/claude-code/hooks/lib/session-heartbeat-lib.sh
   Output: 976586e feat(observability): O.2 session heartbeat — liveness file + sweep (Wave O); both files exist on master @ f25c33c.
   Result: PASS
3. Lib self-test replay (repo master copy)
   Command: bash adapters/claude-code/hooks/lib/session-heartbeat-lib.sh --self-test
   Output: "self-test summary: 13 passed, 0 failed", exit 0.
   Result: PASS (matches claimed 13/13)
4. Script self-test replay (repo master copy)
   Command: bash adapters/claude-code/scripts/session-heartbeat.sh --self-test
   Output: "self-test summary: 10 passed, 0 failed", exit 0.
   Result: PASS (matches claimed 10/10)
5. Installed-vs-repo parity
   Command: diff ~/.claude/{scripts/session-heartbeat.sh,hooks/lib/session-heartbeat-lib.sh} against repo copies
   Output: both byte-identical.
   Result: PASS
6. Call-site wiring (installed live hooks)
   Command: grep -n "session-heartbeat" ~/.claude/hooks/{session-start-digest.sh,workstreams-stop-writer.sh,pre-compact-continuity.sh}
   Output: session-start-digest.sh:922 (touch --event start), workstreams-stop-writer.sh:196 (touch --event turn-end --marker), pre-compact-continuity.sh:260 (touch --event compact).
   Result: PASS
7. KILL-DRILL REPLAY (independent, self-cleaning) — the Done-when oracle
   Command: seeded ~/.claude/state/heartbeats/drill-verify-o2.json with just-exited subshell pid 3989757 + last_activity_ts 2026-07-07T11:07:28Z (45 min old); ran bash ~/.claude/scripts/nl.sh status --json
   Output: {"session_id":"drill-verify-o2","state":"crashed","branch":"drill","worktree_root":"/tmp/drill","marker_state":"none"} — classified in ONE refresh (single run, elapsed_ms=21043); drill file deleted after ("cleanup: drill file removed").
   Result: PASS — killed session surfaces as crashed (the dead-pid refinement of "stalled"; stale-with-alive-pid maps to "stale", verified in self-test Scenario 5).
8. Production behaving-check (wired ≠ reached ≠ behaving)
   Command: ls -t ~/.claude/state/heartbeats/ + jq newest
   Output: f2d19bb9-a7ce-476f-812b-0efba358a0ab.json — THIS live session's heartbeat, last_event=turn-end, fresh ts 2026-07-07T11:35:00Z, real pid/branch — written by the stop-writer call-site during real operation.
   Result: PASS
9. Docs impact field
   Result: SKIPPED — plan predates the Docs-impact convention (no task in this plan carries the field); grandfathered per verifier protocol.

Runtime verification: test adapters/claude-code/hooks/lib/session-heartbeat-lib.sh::--self-test (13/13)
Runtime verification: test adapters/claude-code/scripts/session-heartbeat.sh::--self-test (10/10)
Runtime verification: file ~/.claude/hooks/workstreams-stop-writer.sh::session-heartbeat.sh touch --event turn-end
Runtime verification: functionality-verifier O.2::PASS (executed directly by task-verifier: kill-drill against live nl status --json, check 7 above — the maintainer-shaped exercise producing the maintainer-shaped outcome)

DEPENDENCY TRACE
================
Step 1: Session activity (start / turn-end / compact)
  ↓ Verified at: ~/.claude/hooks/session-start-digest.sh:922, workstreams-stop-writer.sh:196, pre-compact-continuity.sh:260 (installed, live)
Step 2: hb_write emits C1-schema JSON atomically to ~/.claude/state/heartbeats/<session-id>.json
  ↓ Verified at: session-heartbeat-lib.sh hb_write (lines 142-201); production file f2d19bb9-....json observed with fresh turn-end ts (check 8)
Step 3: Staleness computed on read (never written): stale = age > OBS_STALE_MIN; crashed = stale + dead pid
  ↓ Verified at: hb_is_stale/hb_classify (lib lines 265-313); self-test Scenarios 3-6 replayed green
Step 4: `nl status --json` surfaces the classification within one refresh
  ↓ Verified at: kill-drill replay (check 7) — seeded crashed session reported "state":"crashed" in a single run

Git evidence:
  Files modified:
    - adapters/claude-code/scripts/session-heartbeat.sh (commit 976586e, 2026-07-06)
    - adapters/claude-code/hooks/lib/session-heartbeat-lib.sh (commit 976586e, 2026-07-06)
  Master HEAD at verification: f25c33c (main checkout, branch master)

Verdict: PASS
Confidence: 9
Reason: PROVEN: independent kill-drill replay against the live installed estate — seeded dead-pid (3989757) heartbeat with 45-min-old ts, `nl status --json` classified it "crashed" in one refresh (21043ms), file self-cleaned; both self-tests replayed green (13/13 lib, 10/10 script) on master; installed copies byte-identical to repo; all three call-sites live and producing real heartbeats (this session's own turn-end heartbeat observed). RED for from-absent behavior: without the O.2 heartbeat file+lib, nl status has no liveness input at all — the drill session appears ONLY because the seeded C1 file exists and is classified on read.
