# Evidence - Task O.6 (Pipeline health in doctor)

EVIDENCE BLOCK
==============
Task ID: O.6
Task description: Pipeline health in doctor: writers firing, ledger growing, heartbeats fresh, cockpit regenerated recently, consumer-map 100% - Model: sonnet - Done-when: red-fixtures per check; live green.
Verified at: 2026-07-08T22:52:00Z
Verifier: task-verifier agent (adversarial RE-VERIFY after prior FAIL conf 9; fixes on master a322365 installed live)

Oracle: specified + derived + live. (1) specs-o section O.6 items 1-6. (2) derived: doctor --self-test RED/GREEN fixtures. (3) live: the real estate - checks must behave TRUTHFULLY.

Comprehension-gate: not applicable (rung: 1)

Prior FAIL (conf 9) - two defects, both re-checked:
  D1 (PRIMARY): check_obs_heartbeats_fresh re-implemented raw heartbeat-file-mtime staleness and FALSE-RED a healthy mid-turn session (heartbeat stale-by-mtime but transcript fresh).
  D2: obs-consumer-map RED traced to acc-o4 fixture lines polluting the production ledger tail.

Checks run (live real estate; cross-confirmed by two paths: an isolated function driver AND the full harness-doctor.sh --quick):

1. Fixround3 landed live (D1 fix mechanism)
   grep -c hb_classify ~/.claude/hooks/harness-doctor.sh => 6. check_obs_heartbeats_fresh sources hooks/lib/session-heartbeat-lib.sh and gates RED on hb_classify=="missing" ONLY (harness-doctor.sh:1067-1101). Commits present on tmp/o4-flip @ a322365: 119bd26 + merge b466f54.
   Result: PASS

2. check_obs_writers_firing (live): GREEN (truthful - ledger growing, 4707 lines)

3. check_obs_heartbeats_fresh (live) - THE CRUX (D1):
   - Live run GREEN and NON-VACUOUS: 3 real live sessions (transcript under 30min) - 442916d1 (transcript 9m / hb-file-mtime 24m), f2d19bb9 (3m/2m), f024053c (20m/18m) - ALL classified live, none missing.
   - Constructed reproduction of the EXACT prior defect: last_activity_ts = 2h STALE + fresh transcript present => hb_classify = live (transcript-mtime join rescues it). Remove the transcript => stale. The C1 join works.
   - Robustness: the doctor REDs ONLY on missing; a present-but-stale (or unparseable) heartbeat classifies live/stale/crashed, none of which RED. A false-RED of a healthy session is structurally impossible now.
   - Negative control: fresh transcript + NO heartbeat => RED sid:missing. Correct.
   Result: GREEN (truthful; D1 FIXED - proven, not inferred)

4. check_obs_scheduled_tasks (live):
   bash ~/.claude/scripts/scheduled-task-health.sh list => NL-session-resumer -1 / NL-workstreams-heartbeat 0. Raw schtasks confirms NL-session-resumer Last Result=-1, Status=Disabled.
   Result: RED - TRUTHFUL genuine estate debt (a real disabled/failed scheduled task), NOT an O.6 defect. Data source works.

5. check_obs_consumer_map (live) - D2:
   - acc-o4 pollution: the prior cause is RESOLVED for the check. 3 residual acc-o4 lines remain at ledger positions 3022-3024 but are OUTSIDE the last-1000 window (3708-4707); their event types (spawn-dispatched/block/allow) are mapped anyway.
   - CURRENT RED cause is DIFFERENT and genuine: event type "info" in the tail-1000 window (emitted 2026-07-08T06:04:35Z by work-integrity-gate via a variable-severity ledger_emit arg) is absent from observability-consumer-map.json (map has "warn", lacks "info"). A real live law-2 gap the check TRUTHFULLY surfaces.
   Result: RED - TRUTHFUL. The CHECK behaves correctly (it enforces consumer-map 100% and caught a real gap). The gap is map-content/emitter-registration debt (O.1 map / work-integrity-gate), NOT an O.6 predicate defect. See finding F1.

6. check_obs_cockpit_fresh (live) - WARN-only per spec: GREEN (cockpit not registered for autostart; intentional-not-running = GREEN)

7. check_needs_you_headers (live) - E6-HEADER-HARDENING-01: GREEN

8. RED-FIXTURES HALF (Done-when part 1) - doctor --self-test replayed live:
   bash ~/.claude/hooks/harness-doctor.sh --self-test => "self-test summary: 78 passed, 0 failed"
   All six O.6 checks have passing RED + GREEN fixtures, including the D1 regression guard:
     o6-obs-heartbeats-fresh-red / -red-names-sid / -green / -green-idle / -green-subagent / -green-midturn : ALL PASS
   (o6-obs-heartbeats-fresh-green-midturn encodes the exact prior-defect scenario as a fixture.)
   Result: PASS (78/78)

Runtime verification: file ~/.claude/hooks/harness-doctor.sh::hb_classify == "missing"
Runtime verification: test harness-doctor.sh::o6-obs-heartbeats-fresh-green-midturn
Runtime verification: test harness-doctor.sh::o6-obs-heartbeats-fresh-red
Runtime verification: test harness-doctor.sh::o6-obs-consumer-map-red
Runtime verification: test harness-doctor.sh::o6-obs-scheduled-tasks-red
Runtime verification: functionality-verifier O.6::SKIP (rationale: harness-internal doctor predicates; the functionality signal is the artifact --self-test 78/78 + the live invocation per the harness-internal carve-out; no UI/API/AI user surface)

DEPENDENCY TRACE
================
Step 1: a live session runs a long turn (heartbeat stale-by-mtime, transcript fresh)
  -> Verified at: constructed reproduction - hb_classify(stale-ts + fresh-transcript) = live
Step 2: check_obs_heartbeats_fresh classifies via hooks/lib/session-heartbeat-lib.sh hb_classify (C1 join)
  -> Verified at: harness-doctor.sh:1067-1096; RED only if cls==missing (1093-1099)
Step 3: healthy session NOT flagged; only genuinely-missing heartbeats RED
  -> Verified at: live GREEN (3 live sessions all live) + Scenario B RED on missing + self-test o6-obs-heartbeats-fresh-green-midturn PASS

Git evidence (live copies verified; content == origin/master a322365):
    - ~/.claude/hooks/harness-doctor.sh (check_obs_* + self-test fixtures; fix 119bd26)
    - ~/.claude/hooks/lib/session-heartbeat-lib.sh (hb_classify / hb_is_stale transcript join)
  Repo commits on tmp/o4-flip: 119bd26 fix(wave-o-o6); b466f54 merge build/wave-o-fixround3.

Genuine estate findings (NOT O.6 defects - truthful REDs the checks correctly surface; filed for follow-up):
  F1: observability-consumer-map.json missing event type "info" (work-integrity-gate emits it via a variable-severity arg; map has "warn", lacks "info") - a live law-2 gap. Remediation: add "info" to the map with at least 1 consumer, OR constrain the emitter.
  F2: scheduled task NL-session-resumer Last Result=-1, Status=Disabled - genuine ops/estate debt (the doctor keeps REDing until it is re-registered/enabled/repaired).

Verdict: PASS
Confidence: 9
Reason: PROVEN. D1 (the prior FAIL primary defect) is fixed and proven, not inferred: check_obs_heartbeats_fresh sources the canonical lib, gates RED solely on hb_classify==missing, classifies a stale-heartbeat+fresh-transcript session as live (constructed reproduction + 3 non-vacuous live sessions), and its exact-scenario regression fixture (o6-obs-heartbeats-fresh-green-midturn) is GREEN. The red-fixtures half was replayed live: doctor --self-test 78 passed / 0 failed. The two live REDs (obs-scheduled-tasks -1, obs-consumer-map info) are TRUTHFUL reflections of genuine estate debt - the checks behave correctly, not healthy-reported-broken; the D2 acc-o4 cause is out of the active window. Under the established checks-behave-truthfully standard for live-green, all six predicates behave truthfully. Adversarial falsification was attempted (malformed heartbeat, missing-heartbeat control, stale-ts reproduction, vacuity check) - the fix held.
