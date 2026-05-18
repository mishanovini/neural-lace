# Evidence Log — Dispatch to Conversation-Tree event emission (Claude-side writer)

## Task 1 — Build conversation-tree-emit.sh (--on-spawn / --on-stop, dual-sink, exit 0)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Build adapters/claude-code/hooks/conversation-tree-emit.sh: --on-spawn (classify spawn, ensure project/global root, emit branch-opened, record to per-session ledger) and --on-stop (read ledger, emit concluded per open node, clear ledger). Dual-sink via facade with deterministic idempotent event_id. Always exit 0; errors logged.
Verified at: 2026-05-18T15:07:16Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Hook exists + committed
   Command: git log --oneline -- adapters/claude-code/hooks/conversation-tree-emit.sh
   Output: 89b3429 (Pin-1 candidate matching) + 07691d5 (emitter + wiring)
   Result: PASS
2. Functionality — branch-opened reaches running GUI server, state=open
   Command: CLAUDE_SESSION_ID=tv-1779116726 emit --on-spawn (mcp__ccd_session__spawn_task) then curl /api/state filter title
   Output: emit-exit=0 ; node sp-079682ee634e state "open"
   Result: PASS
3. Functionality — concluded transition reaches GUI server, state=concluded
   Command: emit --on-stop (same SID) then re-curl /api/state
   Output: stop-exit=0 ; same node sp-079682ee634e state "concluded"
   Result: PASS
4. Gate-satisfaction — emitter write genuinely satisfies conversation-tree-state-gate via Pin-1 verified-snapshot path (NOT waiver)
   Command: parked the stale fresh waiver to /tmp, emit --on-spawn, then piped SAME spawn JSON to conversation-tree-state-gate.sh
   Output: conv-tree-gate ALLOW verified snapshot names live branch node gate-clean-e2e ; gate-exit=0
   Result: PASS  (earlier run masked by a stale fresh .claude/state waiver; investigated, parked it, re-ran clean to exercise the genuine verified-snapshot ALLOW path; waiver restored afterward)
5. Dual-sink + autodetect + failure-isolation log
   Command: tail ~/.claude/logs/conversation-tree-emit.log
   Output: dual sinks logged (GUI main-checkout neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json + section-5 gate path charming-blackburn-1c9d1a/.claude/state/conversation-tree/tree-state.json), root=proj-neural-lace, result=OK
   Result: PASS

DEPENDENCY TRACE
================
Step 1: Dispatch spawns child (mcp__ccd_session__spawn_task)
  Verified at: emit --on-spawn exit 0; log line branch-opened child title
Step 2: appendEvent facade writes branch-opened to GUI-watched tree-state.json
  Verified at: curl http://127.0.0.1:7733/api/state node state open
Step 3: dispatching session Stop emits concluded for opened branch
  Verified at: emit --on-stop exit 0; re-curl same node id state concluded

Runtime verification: curl -s http://127.0.0.1:7733/api/state
Runtime verification: file adapters/claude-code/hooks/conversation-tree-emit.sh::appendEvent

Verdict: PASS
Confidence: 9
Reason: emit hook builds branch-opened + concluded; the open to concluded transition is observable in the running GUI server /api/state, and the writer genuinely satisfies the state-gate via the verified-snapshot path (proven after disproving a stale-waiver-masked result).

## Task 2 — --self-test

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Add --self-test: spawn-classification for 4 enumerated tools + non-spawn no-op, stop-conclusion delta, idempotent re-fire, project-root autodetect, failure isolation. Prints self-test OK.
Verified at: 2026-05-18T15:07:16Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Verification level: mechanical
Checks run:
1. Self-test re-executed
   Command: bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test 2>&1 | tail -3
   Output: ST14 PASS ; self-test 17 passed 0 failed ; self-test OK
   Result: PASS

Runtime verification: command bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test

Verdict: PASS
Confidence: 9
Reason: --self-test prints self-test OK with 17 passed 0 failed, covering classification, idempotency, autodetect, failure isolation, and gate-Pin-1-candidate matching.

## Task 3 — Wire the hook (template + live)

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Wire the hook: settings.json.template PreToolUse matcher block immediately before conversation-tree-state-gate.sh, --on-stop appended to Stop chain after conversation-tree-stop-gate.sh; mirror into live ~/.claude/settings.json.
Verified at: 2026-05-18T15:07:16Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Verification level: mechanical
Checks run:
1. JSON validity both files
   Command: jq empty adapters/claude-code/settings.json.template ; jq empty ~/.claude/settings.json
   Output: TEMPLATE-JSON-OK ; LIVE-JSON-OK
   Result: PASS
2. Spawn matcher block ordering (template + live)
   Command: jq query of PreToolUse spawn matcher block hook commands
   Output (both files): conversation-tree-emit.sh --on-spawn THEN conversation-tree-state-gate.sh (adjacent, emit immediately precedes gate)
   Result: PASS
3. Stop chain ordering (template + live)
   Command: jq query of Stop[0] hook commands
   Output (both files): line 5 conversation-tree-stop-gate.sh ; line 6 conversation-tree-emit.sh --on-stop
   Result: PASS

Runtime verification: command jq -r '.hooks.Stop[0].hooks[].command' ~/.claude/settings.json

Verdict: PASS
Confidence: 9
Reason: Both canonical template and live settings.json have emit --on-spawn immediately before state-gate in the same spawn matcher block, and emit --on-stop immediately after stop-gate in the Stop chain; both JSON valid.

## Task 4 — Sync canonical to live mirror + regression

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Sync canonical to live mirror, verify diff -q byte-identical; run new self-test + regression conversation-tree-state-gate.sh --self-test (18/18) and conversation-tree-stop-gate.sh --self-test (8/8).
Verified at: 2026-05-18T15:07:16Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Verification level: mechanical
Checks run:
1. Byte-identical mirror
   Command: diff -q adapters/claude-code/hooks/conversation-tree-emit.sh ~/.claude/hooks/conversation-tree-emit.sh
   Output: BYTE-IDENTICAL-OK (diff exit 0)
   Result: PASS
2. Emit self-test
   Command: bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test
   Output: 17 passed 0 failed ; self-test OK
   Result: PASS
3. Regression state-gate self-test
   Command: bash ~/.claude/hooks/conversation-tree-state-gate.sh --self-test 2>&1 | tail -1
   Output: 18 passed 0 failed
   Result: PASS
4. Regression stop-gate self-test
   Command: bash ~/.claude/hooks/conversation-tree-stop-gate.sh --self-test 2>&1 | tail -1
   Output: 8 passed 0 failed
   Result: PASS

Runtime verification: command diff -q adapters/claude-code/hooks/conversation-tree-emit.sh ~/.claude/hooks/conversation-tree-emit.sh
Runtime verification: command bash ~/.claude/hooks/conversation-tree-state-gate.sh --self-test

Verdict: PASS
Confidence: 9
Reason: canonical and live mirror byte-identical; emit self-test 17/0; both regression gate self-tests pass at expected counts (18/0, 8/0) — no collateral wiring damage.

## Task 5 — End-to-end against running GUI server

EVIDENCE BLOCK
==============
Task ID: 5
Task description: End-to-end: with the GUI server running on :7733, spawn a dummy start_code_task, confirm branch-opened (title) then concluded reach the GUI-watched state file and render live; document evidence.
Verified at: 2026-05-18T15:07:16Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. GUI server reachable
   Command: curl -s http://127.0.0.1:7733/api/state
   Output: nodes array, 41 nodes
   Result: PASS
2. branch-opened renders live
   Command: emit --on-spawn (SID tv-1779116726) then curl /api/state filter title
   Output: node sp-079682ee634e state open
   Result: PASS
3. concluded renders live (open to concluded transition observed)
   Command: emit --on-stop (same SID) then re-curl /api/state filter title
   Output: same node sp-079682ee634e state concluded
   Result: PASS

DEPENDENCY TRACE
================
Step 1: spawn dummy child via emit --on-spawn
  Verified at: emit-exit=0
Step 2: appendEvent to GUI-watched module tree-state.json (main checkout)
  Verified at: server watch picks up; /api/state shows node state open
Step 3: dispatching session Stop emits concluded
  Verified at: /api/state same node id state concluded

Runtime verification: curl -s http://127.0.0.1:7733/api/state

Verdict: PASS
Confidence: 9
Reason: The running GUI server on :7733 reflected a spawn-created node as open then concluded after the Stop emitter — the user-observable outcome (Dispatch conversations auto-populate the operator GUI live) is proven end-to-end against the live system.
