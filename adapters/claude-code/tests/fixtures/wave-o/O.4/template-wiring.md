# O.4 template-wiring fragment — trust-path retirement (specs-o §O.4 deliverable 4)

Builder: build/wave-o-o4. Orchestrator-applied — this builder NEVER edits
`settings.json.template` directly (§O.0.1-1).

## Context

Once the cockpit rebuild (this task) stops reading `tree-state.json` as
truth (it does — `workstreams-ui/server/server.js` now shells `nl <sub>
--json` for every pane; see `server/derive-cache.js`), the tree-consumer's
ONLY remaining protected surface — the two PreToolUse `workstreams-state-
gate.sh` entries — has no consumer left per law 2 (EVERY-SIGNAL-HAS-A-
CONSUMER-OR-IT-DOESN'T-SHIP). Per specs-o §O.4 deliverable 4 / decision D-O4,
these are retired at the template layer. This closes NL-FINDING-024 at the
root (the spawn writer -> gate PreToolUse race the finding describes can no
longer fire, because the gate it raced against is gone).

**Blocking-gate budget:** removing these two `workstreams-state-gate.sh`
PreToolUse entries takes the blocking-gates budget from 10/12 to 8/12 (§O.0.1-8).

## REMOVE — two PreToolUse entries (both currently wired; verified live at
`adapters/claude-code/settings.json.template` lines ~269-295 on the O.3
baseline this branch was cut from — re-verify exact line numbers at
integration time, the anchor is the JSON block shape below, not the line
number)

### Removal 1 — the `Task|Agent|Workflow` matcher's state-gate entry

```json
      {
        "matcher": "Task|Agent|Workflow",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/workstreams-state-gate.sh --builder-tracking"
          }
        ]
      },
```

This ENTIRE array element is removed. The SIBLING entry immediately above it
(`workstreams-emit.sh --on-builder-dispatch`, same matcher) is KEPT — it is
the ledger-emitter path, not the gate (O.1 owns that emitter; see
"KEPT" note below).

### Removal 2 — the `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task` matcher's state-gate entry

```json
      {
        "matcher": "mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/workstreams-state-gate.sh"
          }
        ]
      },
```

This ENTIRE array element is removed. The SIBLING entry immediately above it
(`workstreams-emit.sh --on-spawn`, same matcher) is KEPT (O.1's re-pointed
ledger emitter — `spawn-dispatched` event, contract C2).

## KEEP unchanged (do NOT touch as part of this fragment)

- `bash ~/.claude/hooks/workstreams-emit.sh --on-builder-dispatch` (Task|Agent|Workflow matcher)
- `bash ~/.claude/hooks/workstreams-emit.sh --on-spawn` (spawn_task|start_code_task matcher)
- The Stop-chain entry `bash ~/.claude/hooks/workstreams-stop-writer.sh` — see
  the companion note below; it is NOT removed, only ONE of its internal
  members is retired (a code change inside the hook file, not a
  settings.json.template edit — see manifest-amendments.md's
  "workstreams-stop-writer member retirement" section for the exact diff
  the orchestrator applies to `hooks/workstreams-stop-writer.sh`'s `MEMBERS`
  array).

## No other settings.json.template changes

Wave O budget rule (§O.0.1-8): SessionStart stays 8/8 (no new entries), Stop
stays within 4/6 (no new entries — this fragment REMOVES from the Stop
CHAIN's member list, a code-level change inside workstreams-stop-writer.sh,
not a settings.json.template Stop array entry — the Stop array itself is
untouched by this fragment).
