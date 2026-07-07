# Evidence — O.8 Estate-coordination protocol

EVIDENCE BLOCK
==============
Task ID: O.8
Task description: Estate-coordination protocol (from NL-FINDING-031 + the 2026-07-04 manual run): /coordinate-estate skill + doctrine compact encoding the manual run — inventory (list_sessions), classify (active / stalled>2h / wedged-undeliverable / superseded), re-home orphans via nl-issue, stand-down superseded satellites, freeze-window protocol, spawn-time supersession check — file-based channels ONLY.
Verified at: 2026-07-07T12:20:00Z
Verifier: task-verifier agent (adversarial re-derivation; main checkout master @ f25c33c)

Oracle: specified — the plan's Done-when (skill + doctrine compact w/ JIT trigger exist; sandboxed drill classifies seeded stale session + re-homes orphan to nl-issue ledger; coordination-section format documented), exercised directly by replaying the drill and firing the JIT trigger.

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Deliverable files on master
   Command: ls adapters/claude-code/skills/coordinate-estate.md adapters/claude-code/doctrine/estate-coordination{,-full}.md; git log --oneline -- <each>
   Output: all three exist (11434 / 2005 / 3020 bytes); authored in 808b112 "build(wave-o): O.8 estate-coordination skill + doctrine + drill fixture"; 808b112 IS ancestor of origin/master (git merge-base --is-ancestor)
   Result: PASS
2. Manifest JIT trigger (repo AND live ~/.claude/manifest.json, byte-identical entry)
   Command: grep -A12 '"id": "estate-coordination"' ~/.claude/manifest.json
   Output: kind=pattern, doctrine_file=doctrine/estate-coordination.md, jit_triggers.paths=["SCRATCHPAD.md"], keywords=["freeze","coordinate sessions","stand down"] — matches claim exactly
   Result: PASS
3. JIT trigger FIRES (functional, sandboxed, live manifest + live doctrine)
   Command: jq -n --arg fp 'C:\Users\misha\dev\Pocket Technician\neural-lace\SCRATCHPAD.md' '{"tool_name":"Edit","session_id":"o8-verify-test3","tool_input":{"file_path":$fp}}' | HARNESS_SELFTEST=1 HARNESS_SELFTEST_DIR=<mktemp> DOCTRINE_JIT_MANIFEST=~/.claude/manifest.json bash adapters/claude-code/hooks/doctrine-jit.sh
   Output: '[doctrine-jit] estate-coordination — injected once for this session (trigger: SCRATCHPAD.md)' + compact content. Verified with BOTH backslash and forward-slash path styles. Verified no earlier manifest entry shadows SCRATCHPAD.md (estate-coordination at entries[31] is the first path match; first-match-wins semantics).
   Result: PASS
4. Drill REPLAYED (sandboxed)
   Command: bash adapters/claude-code/tests/fixtures/wave-o/O.8/run-drill.sh
   Output: "drill summary: 10 passed, 0 failed" — Step A heartbeat-shape classification (dead pid 999999, 3923min-stale ts, CONTINUING marker on dead session), Step B transcript terminal-state = unanswered permission_request -> wedged-undeliverable, Step C nl-issue re-homing: exit 0, exactly one line in sandboxed NL_ISSUES_PATH ledger naming session id local_dead00000-stale-fixture-0000000000ab, untriaged, REAL ~/.claude/state/nl-issues.jsonl untouched (drill asserts this itself)
   Result: PASS (matches expected 10/10)
5. Coordination-section format documented in the doctrine
   Output: doctrine/estate-coordination-full.md documents `## COORDINATION ORDER` / `COORD UPDATE` SCRATCHPAD.md sections, append-only/polled properties, freeze-window status lines (`FREEZE STATUS: PENDING` -> `ACTIVE` -> `CUTOVER-DONE @ <sha>` + independent sha verification), classification taxonomy, re-homing one-liner format, spawn-time supersession check. Compact mirrors and links it. Skill (frontmatter + steps) encodes inventory/classify/re-home/stand-down/freeze/supersession and the file-based-channels-ONLY rule with send_message rationale — matches task text point-for-point.
   Result: PASS
6. Live-mirror install state
   Output: doctrine/estate-coordination{,-full}.md + manifest entry ARE live (~/.claude, mtime Jul 7 04:26). skills/coordinate-estate.md is NOT yet live: install.sh's sync loops (lines 450/916) omit skills/; only session-start-auto-install.sh (SYNC_SUBDIRS includes skills, wired live settings.json SessionStart, installs missing files from origin/master) delivers it — self-heals on next session start since 808b112 is on origin/master. Friction filed: nl-issue ledger entry 2026-07-07 (install.sh omits skills/templates from manual sync).
   Result: PASS with noted lag (Done-when requires existence + drill + docs, all met; canonical source per doctrine is master; JIT-critical surfaces — manifest + doctrine — are live and demonstrated firing)

Runtime verification: test adapters/claude-code/tests/fixtures/wave-o/O.8/run-drill.sh::drill-summary-10-passed-0-failed
Runtime verification: file adapters/claude-code/skills/coordinate-estate.md::name: coordinate-estate
Runtime verification: file adapters/claude-code/doctrine/estate-coordination-full.md::FREEZE STATUS
Runtime verification: file adapters/claude-code/manifest.json::"id": "estate-coordination"
Runtime verification: functionality-verifier O.8::SKIP (rationale: harness-internal pattern/skill unit — drill script IS the functionality exercise and was replayed directly by the verifier, 10/10; JIT injection additionally fired live)

DEPENDENCY TRACE
================
Step 1: Maintainer edits SCRATCHPAD.md (coordination surface)
  ↓ Verified at: doctrine-jit.sh live simulation — estate-coordination injected (trigger: SCRATCHPAD.md), live manifest entries[31]
Step 2: Injected compact routes to full doctrine + skill
  ↓ Verified at: doctrine/estate-coordination.md lines 2-3, 10 (links skills/coordinate-estate.md + -full.md; both exist on master @ 808b112)
Step 3: Skill protocol classifies stale/wedged sessions and re-homes orphans
  ↓ Verified at: run-drill.sh replay — classification wedged-undeliverable + nl-issue re-homing, 10/10, sandboxed (real ledger untouched)

Git evidence:
  adapters/claude-code/skills/coordinate-estate.md          (808b112, 2026-07-06)
  adapters/claude-code/doctrine/estate-coordination.md      (808b112, 2026-07-06)
  adapters/claude-code/doctrine/estate-coordination-full.md (808b112, 2026-07-06)
  adapters/claude-code/tests/fixtures/wave-o/O.8/           (808b112; drill + fixtures + manifest-amendments.md)
  Manifest entry integrated: 527cad3 (wave-o batch-1 splice); on origin/master (f25c33c)

Verdict: PASS
Confidence: 8
Reason: PROVEN: all four Done-when elements exercised directly against the specified oracle — drill replayed 10/10 sandboxed (classification + nl-issue re-homing, real ledger untouched); JIT trigger fired end-to-end against the LIVE manifest with realistic Edit payloads in both Windows path styles; skill/doctrine on master (808b112 ∈ origin/master) with coordination-section + freeze-window format documented. Adversarial probes survived: first-match shadowing check (none), backslash-path normalization (fires), sandbox-isolation assertion (real ledger untouched). Noted non-blocking gap: skills/coordinate-estate.md not yet in live mirror (install.sh omits skills/; session-start-auto-install delivers on next tick — mechanism verified wired + missing-file-installing; friction filed to nl-issue ledger).
