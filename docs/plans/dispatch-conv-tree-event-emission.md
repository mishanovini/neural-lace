# Plan: Dispatch → Conversation-Tree event emission (Claude-side writer)

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: single-hook writer (PreToolUse spawn + Stop) over the frozen A2 state-library facade
frozen: false
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal writer hook; the --self-test block + the documented end-to-end spawn verification ARE the acceptance artifact. No product user surface; the operator running the harness is the user.
Backlog items absorbed: none

## Goal
Wire the Claude side of the Conversation-Tree UI file-mediated contract (ADR-031 r7 / ADR-032 / PRD FR-11/FR-12). Today only the GUI (human side) writes events; the Dispatch orchestrator and Code sessions spawned from it emit nothing, so the operator's Dispatch conversations never auto-populate the tree. This plan ships a single non-blocking writer hook that, as the orchestrator works, emits the ADR-032 lifecycle events (`branch-opened` on spawn, `concluded` on session/branch end) via the frozen state-library facade so the GUI auto-populates live.

## Scope
- IN: a new `conversation-tree-emit.sh` hook (canonical + live mirror); `--on-spawn` PreToolUse mode on the enumerated spawn surface (`mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task|Task|Agent`); `--on-stop` Stop mode; dual-sink idempotent writes via the `state.js` facade (the module STATE_FILE the shipped GUI server watches + the ADR-032 §5-resolved path the conv-tree gates read, when they differ); cwd→project auto-detection expressed as a per-project root node; per-session correlation ledger; failure isolation (always exit 0, errors logged under `~/.claude/logs/`); `--self-test`; settings wiring in `settings.json.template` (canonical) and `~/.claude/settings.json` (live).
- OUT: GUI changes (server.js / web/* — Phase C/D/E shipped). State-library changes (A2 frozen — facade is called, never modified). New event types beyond the ADR-032 §2 enum. Changes to the conv-tree gates' behavior. Precise child-DONE correlation across separate sessions (v1 concludes a spawn branch when the dispatching session ends; exact child-DONE via the `Report-back: task-id=` sentinel is a documented v2 follow-up, filed as a finding).

## Tasks

- [ ] 1. Build `adapters/claude-code/hooks/conversation-tree-emit.sh`: `--on-spawn` (classify spawn from stdin `tool_name`+`tool_input`, ensure project/global root node, emit `branch-opened` for the child branch, record to per-session ledger) and `--on-stop` (read this session's ledger, emit `concluded` per open node, clear ledger). Dual-sink via facade with deterministic idempotent `event_id`. Always `exit 0`; errors logged to `~/.claude/logs/conversation-tree-emit.log`. — Verification: full
  - **Prove it works:** 1. Pipe a synthetic `mcp__ccd_session_mgmt__start_code_task` JSON to the hook `--on-spawn` with `CONV_TREE_STATE_PATH` set to a temp file. 2. Read the temp file: assert a `branch-opened` event whose `title` equals the spawn title and a project/global root node exists. 3. Pipe a synthetic Stop JSON for the same session to `--on-stop`. 4. Read the temp file: assert a `concluded` event for the same `node_id`.
  - **Wire checks:** `adapters/claude-code/hooks/conversation-tree-emit.sh` → `appendEvent` in `neural-lace/conversation-tree-ui/state/state.js` → `branch-opened` written to `tree-state.json`
  - **Integration points:** the frozen `state.js` facade — verified by `node -e "require('<repo>/neural-lace/conversation-tree-ui/state/state.js').appendEvent" ` resolving; the conv-tree gates' `_resolve_state_path` logic (re-implemented identically) — verified by the §5-sink path matching the gate's resolver for the same cwd.
- [ ] 2. Add `--self-test`: spawn-classification for each of the 4 enumerated tools (+ a non-spawn no-op), stop-conclusion delta, idempotent re-fire (no double-write), project-root autodetect (cwd under `claude-projects/<p>/` → `proj-<p>` root; else `global`), and failure isolation (broken state-lib path → exit 0 + log line). Prints `self-test: OK`. — Verification: mechanical
- [ ] 3. Wire the hook: `adapters/claude-code/settings.json.template` (canonical) — new PreToolUse matcher block (same spawn matcher) immediately before `conversation-tree-state-gate.sh`, and `conversation-tree-emit.sh --on-stop` appended to the Stop chain after `conversation-tree-stop-gate.sh`; mirror the same two edits into live `~/.claude/settings.json`. — Verification: mechanical
- [ ] 4. Sync canonical → live mirror (`~/.claude/hooks/conversation-tree-emit.sh`), verify `diff -q` byte-identical; run the new self-test + regression `conversation-tree-state-gate.sh --self-test` (18/18) and `conversation-tree-stop-gate.sh --self-test` (8/8). — Verification: mechanical
- [ ] 5. End-to-end: with the GUI server running on :7733, spawn a dummy `start_code_task` "Hello world", confirm `branch-opened` (title "Hello world") then `concluded` reach the GUI-watched state file and render live; document evidence. — Verification: full
  - **Prove it works:** 1. Start `node neural-lace/conversation-tree-ui/server/server.js`. 2. From this Dispatch session, `start_code_task` a trivial child. 3. `curl -s http://127.0.0.1:7733/api/state` shows a node titled "Hello world". 4. After this session's Stop emitter runs, the node's state is `concluded`.
  - **Wire checks:** `adapters/claude-code/hooks/conversation-tree-emit.sh` → `neural-lace/conversation-tree-ui/state/state.js` → `neural-lace/conversation-tree-ui/server/server.js` → `/api/state`
  - **Integration points:** the shipped GUI server's `fs.watch` on the module `STATE_FILE` dir — verified by `curl http://127.0.0.1:7733/api/state` reflecting the write within the 40ms debounce.

## Files to Modify/Create
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — new writer hook (canonical).
- `~/.claude/hooks/conversation-tree-emit.sh` — live mirror (byte-identical; synced).
- `adapters/claude-code/settings.json.template` — canonical wiring (PreToolUse spawn block + Stop chain entry).
- `~/.claude/settings.json` — live wiring mirror (so it fires this session for end-to-end verification).
- `docs/plans/dispatch-conv-tree-event-emission.md` — this plan.
- `docs/findings.md` — v1-limitation finding (parent-session conclusion vs precise child-DONE) + the writer-path/GUI-path/§5-gate-path divergence note.

## In-flight scope updates

## Assumptions
- The `state.js` facade `appendEvent(ev, {statePath})` is stable and idempotent on `event_id` per file (confirmed by reading `state/state.js` + `state/store.js` + `selftest.js` P5/P6).
- The shipped GUI server (`server/server.js`) watches the module-relative `STATE_FILE` (`stateLib.STATE_FILE`) — confirmed by reading server.js; it has no statePath override. Therefore the GUI-visible sink is the module file, written via facade default opts.
- PreToolUse hooks receive `{tool_name, tool_input, session_id}` on stdin (or `$CLAUDE_TOOL_INPUT`); `$CLAUDE_SESSION_ID` is set — confirmed against `conversation-tree-state-gate.sh` and `tool-call-budget.sh`.
- Stop hooks receive `{transcript_path, session_id}` on stdin — confirmed against `conversation-tree-stop-gate.sh`.
- `node` and `jq` are on PATH (every other conv-tree hook assumes this; absence → fail-open exit 0).

## Edge Cases
- Hook fires twice for the same spawn → deterministic `event_id` makes the second a facade no-op (per-file dedupe).
- Spawn `tool_input` has no `title` → fall back to the first non-empty trimmed line of `prompt`/`description`/`content`, capped ~80 chars; empty → skip emission (exit 0, log).
- State-library module unresolvable / `node` missing / state file unwritable → catch, log to `~/.claude/logs/conversation-tree-emit.log`, exit 0. NEVER block the orchestrator's tool call (writer, not gate).
- cwd not under any `claude-projects/<project>/` → `global` root node.
- §5-resolved path == module STATE_FILE (cwd has no discoverable git root) → single sink, no duplicate.
- Stop fires with no ledger for the session (session opened no branches) → silent no-op exit 0.
- Reducer rejects an event (e.g. `concluded` with unchecked items — not applicable to auto-opened item-less branches) → facade throws; caught, logged, exit 0; never propagated.

## Testing Strategy
- Task 1/2: `--self-test` exercises every classification path, idempotency, autodetect, and failure isolation against temp `CONV_TREE_STATE_PATH` files — mechanical, deterministic, no network.
- Task 4: regression — the two existing conv-tree gate self-tests must still pass unchanged (proves no collateral wiring damage).
- Task 5: live end-to-end against the running GUI server — the FUNCTIONALITY test (a real spawn produces a real GUI-visible node), which is the bar per the functionality-over-components rule.

## Walking Skeleton
Thinnest end-to-end slice: `printf '<spawn-json>' | CONV_TREE_STATE_PATH=/tmp/t.json conversation-tree-emit.sh --on-spawn` produces a `branch-opened` in `/tmp/t.json` via the real facade. Every later capability (stop conclusion, dual-sink, autodetect, wiring) layers on that proven slice.

## Decisions Log

### Decision: GUI-visible sink is the module STATE_FILE; §5-path is a best-effort second sink
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** Primary sink = `state.js` `STATE_FILE` (module `state/tree-state.json`) because the shipped, out-of-scope GUI server watches exactly that path and has no override — it is the ONLY path that makes the operator's GUI auto-populate (binding verification step 3). Secondary best-effort sink = the ADR-032 §5-resolved path (re-implementing the gates' `_resolve_state_path` identically) so local-Dispatch conv-tree gates see the same truth and do not block subsequent spawns. Same deterministic `event_id` → idempotent per file.
- **Alternatives:** (a) §5 path only — architecturally pure but the shipped GUI never renders it (fails verification step 3); rejected. (b) Module path only — GUI works but local-Dispatch state-gate may block 2nd+ spawns on its own §5 read; rejected as it leaves a real friction. (c) Modify server.js to watch §5 — out of scope (GUI frozen).
- **Reasoning:** The task's binding outcome is "Dispatch conversations auto-populate the GUI." The GUI watches the module file. Dual-sink satisfies the GUI AND keeps the §5-gate contract honest, at ~5 lines and full failure isolation. Faithful to ADR-032 §5 (we DO write the §5 path) without touching the frozen GUI/lib.

### Decision: v1 concludes a spawn branch on the dispatching session's Stop, not on precise child-DONE
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** `branch-opened` on PreToolUse-spawn; `concluded` on the dispatching session's Stop for every branch it opened (per-session ledger). Reliable cross-session child-DONE correlation needs the `Report-back: task-id=` sentinel convention and is filed as a v2 finding.
- **Alternatives:** child session self-correlates via first-user-message hash — fragile (parent title ≠ child prompt, no shared key); rejected for v1. Modify the spawn-prompt convention to inject a correlation token — broader than a hook; deferred to v2.
- **Reasoning:** Satisfies all four explicit verification steps deterministically tonight without overreach; the v1 boundary is documented honestly as a finding.

## Definition of Done
- [ ] All tasks checked off (task-verifier)
- [ ] `conversation-tree-emit.sh --self-test` prints `self-test: OK`
- [ ] `conversation-tree-state-gate.sh --self-test` 18/18, `conversation-tree-stop-gate.sh --self-test` 8/8 (regression)
- [ ] canonical and live mirror byte-identical (`diff -q`)
- [ ] End-to-end: dummy spawn → `branch-opened` + `concluded` in the GUI-watched state file and rendered live at :7733
- [ ] SCRATCHPAD updated; v1-limitation finding filed in `docs/findings.md`
- [ ] One PR merged to neural-lace master; main checkout synced
