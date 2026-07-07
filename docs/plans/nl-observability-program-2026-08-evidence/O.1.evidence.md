EVIDENCE BLOCK
==============
Task ID: O.1
Task description: Emit extension: lifecycle/spawn/task events + turn-trace spans via the D6 shared lib; every new event type registered in a consumer-map file — Done-when: self-test proves each event class lands; consumer-map covers 100% of event types (doctor predicate fragment).
Verified at: 2026-07-07T12:30:00Z
Verifier: task-verifier agent (adversarial re-derivation; all claims replayed, none trusted)

Oracle: specified — the task's own Done-when (self-test proves each event class lands; consumer-map covers 100% of event types per the doctor predicate check_obs_consumer_map), plus live-ledger runtime observation as the functionality floor.

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Self-test replay on master (Done-when clause 1)
   Command: bash adapters/claude-code/hooks/lib/signal-ledger.sh --self-test
   Output: "self-test summary: 17 passed, 0 failed". Scenario 8 emits ALL 10 Wave-O event classes via ledger_emit_typed (session-start session-stop session-compact session-resume throttle-detected spawn-dispatched spawn-concluded bg-task-started bg-task-finished turn-trace — lib lines 453-456) and asserts 10 schema-valid JSONL lines land. Scenario 9 proves turn-trace detail round-trips as nested JSON (contract C2, total_ms=53 survives).
   Result: PASS
2. Consumer-map coverage — doctor predicate replayed clause-by-clause (Done-when clause 2)
   Command: (a) tail -n 1000 ~/.claude/state/signal-ledger.jsonl | jq -r '.event' | sort -u | <has($e) check vs map>; (b) grep -rhoE 'ledger_emit(_typed)? "..." "..."' adapters/claude-code/hooks adapters/claude-code/scripts | <has($e) check>; (c) jq zero-consumer-entries query
   Output: all three clauses returned ZERO unmapped / zero-consumer entries against the REAL live ledger and REAL repo source.
   Result: PASS
3. Live doctor run (in-situ predicate wiring)
   Command: bash adapters/claude-code/hooks/harness-doctor.sh --quick (full log: %TEMP%/doctor-o1-verify.log)
   Output: 26 checks run; check_obs_consumer_map (wired at harness-doctor.sh:1961) emitted NO RED and NO WARN. The 4 REDs present are template-live-drift (O.4 surface), obs-writers-firing (O.6 predicate; false-positive from back-to-back doctor runs sharing a growth stamp — ledger PROVEN growing 2102->2162 lines during this verification), obs-heartbeats-fresh (O.2 surface), budget-worktrees-branches (estate hygiene). None is O.1's predicate or scope.
   Result: PASS (for O.1's predicate)
4. Adversarial coverage probe (falsification attempt)
   Command: whole-ledger event census (grep -o '"event":"..."' | sort | uniq -c)
   Output: historical event types pass(39)/tombstone(2)/info(2) exist in the ledger but NOT in the map — probed as a potential coverage hole. They sit at lines <=562 of 2113 (outside the predicate's by-design last-1000-line window) and clause (b) proves no current repo source emits them as literal ledger_emit args. Predicate green by its documented semantics; probe survived.
   Result: PASS
5. Consumer-map content
   File: adapters/claude-code/observability-consumer-map.json — 22 event types (8 pre-existing + 10 Wave-O C2 + 4 orchestrator-added legacy resumer/dispatcher vocabulary = the claimed "18+4"); every entry has >=1 named on-disk consumer; live-installed copy ~/.claude/observability-consumer-map.json is jq-canonical identical to repo copy.
   Result: PASS
6. Emit callsites per specs-o §O.1 (repo source)
   stop-verdict-dispatcher.sh:174 (turn-trace/session-stop via $event), workstreams-stop-writer.sh:187 (turn-trace), session-start-digest.sh:913 (session-start), pre-compact-continuity.sh:176 (session-compact), workstreams-emit.sh:649/901/2246 (spawn-dispatched/spawn-concluded/bg-task-started). Fragment deliverables all present: tests/fixtures/wave-o/O.1/{doctor-predicate,install-sync,manifest-amendments,template-wiring}.md
   Result: PASS
7. Live runtime emission (functionality floor — maintainer-observable outcome)
   ~/.claude/state/signal-ledger.jsonl contains, emitted TODAY during this verification session: session-start x5 (gate session-start-digest), bg-task-started 2026-07-07T11:49:06Z (gate workstreams-emit), turn-trace 2026-07-07T11:50:55Z with hooks[] timing array + total_ms=8611, session-stop same second (gate stop-verdict-dispatcher) — a turn-trace landed LIVE between two of my grep commands (count 0 -> 1), demonstrating real-time emission, not fixture residue.
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/lib/signal-ledger.sh::--self-test (17/17, scenario 8+9 = each Wave-O event class lands)
Runtime verification: file adapters/claude-code/observability-consumer-map.json::"turn-trace" (22 event types, all >=1 consumer)
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::check_obs_consumer_map (predicate wired at line 1961; live run of 26 checks shows no obs-consumer-map RED/WARN)
Runtime verification: file ~/.claude/state/signal-ledger.jsonl::"event":"turn-trace" (live line 2026-07-07T11:50:55Z, session f2d19bb9)

DEPENDENCY TRACE
================
Step 1: hook fires on a real session event (Stop / SessionStart / Task spawn)
  ↓ Verified at: live ledger lines today — session-start-digest session-start; workstreams-emit bg-task-started 11:49:06Z; stop-verdict-dispatcher turn-trace+session-stop 11:50:55Z
Step 2: emission goes through the D6 shared lib (ledger_emit / ledger_emit_typed)
  ↓ Verified at: callsite greps (stop-verdict-dispatcher.sh:174, workstreams-stop-writer.sh:187, session-start-digest.sh:913, pre-compact-continuity.sh:176, workstreams-emit.sh:649/901/2246) + self-test scenarios 1/2/8/9 (17/17)
Step 3: every emitted event type is registered with >=1 real consumer in the map
  ↓ Verified at: clause (a)/(b)/(c) replay — zero unmapped in last-1000 live lines, zero unmapped repo literals, zero empty-consumer entries
Step 4: doctor enforces the invariant continuously
  ↓ Verified at: harness-doctor.sh:1108 check_obs_consumer_map, invoked at :1961; live 26-check run emitted no obs-consumer-map RED/WARN

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/lib/signal-ledger.sh (1b738fb feat(wave-o): O.1 emit extension + turn-traces + consumer map; later 2b1cc30, 59e1dc2)
    - adapters/claude-code/observability-consumer-map.json (1b738fb; O.3 + orchestrator updates through 59e1dc2)
  Verified on master @ f25c33c (main checkout).

Verdict: PASS
Confidence: 9
Reason: PROVEN: self-test replayed 17/17 on master with scenario 8 landing all 10 Wave-O event classes; all three clauses of check_obs_consumer_map replayed clean against the real live ledger and repo source; live doctor run (26 checks) shows no obs-consumer-map RED; live ledger shows four Wave-O event classes emitted today including a turn-trace that landed in real time during verification. Adversarial probe (pass/tombstone/info historical vocabulary) failed to falsify — outside predicate scope by documented design and not emitted by any current repo source.

Estate observations (NOT O.1 gaps; for the orchestrator): live doctor currently 4 RED — template-live-drift (O.4), obs-writers-firing (O.6; consecutive-run growth-stamp artifact), obs-heartbeats-fresh (O.2 wiring), budget-worktrees-branches (10 worktrees > 6). The caller-cited /tmp/doctor-post-waveo.log does not exist at that path on this machine; superseded by direct replay above.
