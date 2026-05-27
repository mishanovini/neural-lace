# Conversation Tree — Orchestrator Auto-Emit (Four-Layer Enforcement)

**Classification:** Hybrid. Layer A (the per-tool emit hook) is Mechanism — it fires as a PreToolUse / SessionStart / Stop hook on every Dispatch tool surface and writes a branch event to the conv-tree state file. Layer B (pre-stop reconciliation) is Mechanism — it scans the agent-uneditable transcript at Stop time and compares it to the emit ledger, surfacing any spawn that escaped emission. Layer C (the heartbeat scheduled task) is Mechanism. Layer D (this rule + the agent's self-applied behavior) is Pattern — the agent treats every Dispatch spawn / conclude / cross-branch send as a tree-tracked event, even where Layers A-C cannot reach (genuine cloud Dispatch with no local-session footprint).

**Originating directive (2026-05-23):** Misha asked for the Conv Tree to "stay updated automatically without me reminding you." He observed that cloud Dispatch doesn't have local hooks and asked: "How can we add enforcement into the way you work so that you automatically keep the Conv Tree updated at all times?"

This rule documents the four-layer enforcement chain. Layers A-C are wired in `~/.claude/settings.json.template`; this rule pins the discipline that binds the orchestrator-class agents to honor the chain.

## The four layers (defense in depth)

Each layer catches a different failure mode. Failure of any single layer is caught by the others.

### Layer A — Tool wrapping (primary mechanism)

`conversation-tree-emit.sh` is wired at every Dispatch tool surface that has a local PreToolUse / SessionStart / Stop hook. Concretely:

| Event | Hook line | Effect on conv-tree state |
|---|---|---|
| `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` PreToolUse | `--on-spawn` | Emits `branch-opened` for the spawned child branch under the auto-detected project/global root, records to per-session correlation ledger. |
| SessionStart | `--on-session-start` | Emits `branch-opened` for the current session's own branch (child-side self-registration so cloud-spawned local sessions appear without needing the parent to emit). |
| Stop | `--on-stop` | Emits `concluded` for every branch this session opened (read from the ledger), then clears the ledger. |
| `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` PreToolUse | `conversation-tree-state-gate.sh` | Verifies the writer (above) actually populated the state file before allowing the spawn (ADR-031 r7 / ADR-034). |
| Stop | `conversation-tree-stop-gate.sh` | Verifies any spawn in the transcript has a matching state-file write (ADR-031 r7 stop-gate). |

Failure isolation: every runtime path of `conversation-tree-emit.sh` exits 0 — an emit failure NEVER blocks the orchestrator's tool call. Emit failures are logged to `~/.claude/logs/conversation-tree-emit.log` for postmortem inspection.

### Layer B — Pre-stop reconciliation (secondary mechanism)

`conv-tree-emit-reconciler.sh` runs as a Stop hook AFTER `--on-stop` has fired. It opens the session's transcript JSONL (`$TRANSCRIPT_PATH`, agent-uneditable), enumerates every Dispatch-class tool call (`mcp__ccd_session__spawn_task`, `mcp__ccd_session_mgmt__start_code_task`), and compares the count to the correlation-ledger entries Layer A wrote for the same session.

When a transcript spawn has no matching ledger entry, the reconciler emits a synthetic catch-up `branch-opened` for it. This catches the case where Layer A's PreToolUse hook silently failed (e.g., a transient state-file write race, a `jq` parse failure on edge-case `tool_input` shape).

The reconciler is non-blocking by design — it auto-fills, never refuses Stop. The Stop chain already has `conversation-tree-stop-gate.sh` for refuse-on-mismatch enforcement (ADR-031 r7 Pin); the reconciler complements it by auto-filling instead of refusing, so a small writer flake doesn't escalate to a Stop block.

### Layer C — Heartbeat (backstop)

`conversation-tree-emit.sh --heartbeat` runs every 5 minutes via Windows Task Scheduler (registered by `register-heartbeat.ps1`). It:

1. Scans `~/.claude/projects/*/*.jsonl` for transcripts modified in the last 15 minutes (configurable: `CONV_TREE_HEARTBEAT_FRESH_MIN`).
2. Touches the corresponding live-marker for each active session.
3. For live-markers older than the staleness threshold (default 60 min: `CONV_TREE_HEARTBEAT_STALE_MIN`), emits `concluded` for every branch that session opened, then removes the marker.
4. Writes a heartbeat timestamp to `~/.claude/state/conversation-tree/heartbeat.last` so the GUI's `/api/health` endpoint can show "last heartbeat N min ago" — and turn the badge red if the heartbeat itself stops.

This is the layer that catches cases where the orchestrator session crashed mid-stride (no Stop hook fired, no Layer A `--on-stop` ran). The heartbeat eventually concludes the orphaned branches based on transcript-staleness.

### Layer D — Rule + agent discipline (final backstop)

This rule binds every orchestrator-class agent (Dispatch orchestrator, lead session in Agent Teams mode, parallel orchestrator dispatching builders) to the following discipline:

1. **Every Dispatch spawn is a tree event.** When the orchestrator calls `mcp__ccd_session__spawn_task` or `mcp__ccd_session_mgmt__start_code_task`, that call IS the moment a new branch opens. Layers A-C are the mechanical guarantee; this rule says the agent treats the spawn as a commitment to the conv-tree narrative.
2. **Every cross-branch send is a `branch-note-add`.** When the orchestrator sends a message TO a child branch (when the equivalent of `mcp__ccd_session__send_message` is exposed), the agent emits `branch-note-add` (target = child node_id, note_text = the message body or a summary) as a side-effect of the send. This makes orchestrator → child communication visible in the tree.
3. **Every user-surface is potentially a `branch-note-add` or `decision-raised`.** When the orchestrator surfaces something TO the user (the equivalent of `mcp__ccd_session__send_user_message`), the agent emits the appropriate event based on the surface's class:
   - The user is being asked to decide → `decision-raised`
   - The user is being asked a question → `question-raised`
   - The user is being told something blocking → `branch-note-add` with a `blocker` tag (use the existing `text` field)
   - Pure status update → `branch-note-add` (no special tag)
4. **Every conclude is real.** The orchestrator does NOT emit `concluded` until the work the branch represents is genuinely finished. Premature conclusion shows up as a closed-branch operator-trust failure (they look at the tree, see it's done, then discover it isn't).
5. **The orchestrator's reward signal is "the tree matches reality."** A divergence between what the tree shows and what's actually happening is a failure — even if the underlying work is correct.

Layer D is the load-bearing layer for genuine cloud Dispatch (no local hook reach). In that environment Layers A-C don't fire, and the orchestrator's self-applied discipline is the only enforcement. The substrate exists so the orchestrator never has to manually write events — at the moment the agent calls a Dispatch tool, the side-effect emit happens via Layer A (when local). For cloud-only paths, the agent treats the rule as instructing it to make the equivalent calls via the GUI's `POST /api/event` endpoint (server.js exposes this for the symmetric file contract).

## Tool-surface matrix

| Tool | Layer A wrapping | Layer B reconciliation | Layer D agent action |
|---|---|---|---|
| `mcp__ccd_session__spawn_task` (Dispatch spawn from cloud or local) | YES (`--on-spawn` PreToolUse) | YES (reconciler verifies emit ledger) | Emit `branch-opened` per spawn |
| `mcp__ccd_session_mgmt__start_code_task` (Dispatch code spawn) | YES (`--on-spawn` PreToolUse) | YES | Emit `branch-opened` per spawn |
| `mcp__ccd_session__send_message` (if/when exposed) | NOT YET (tool not surfaced) | n/a | Emit `branch-note-add` per send (D-class) |
| `mcp__ccd_session__send_user_message` (if/when exposed) | NOT YET (tool not surfaced) | n/a | Emit appropriate event per message class (D-class) |
| Sub-agent `Task` / `Agent` invocations | EXPLICITLY EXCLUDED (ADR-034) | n/a | NOT emitted — AI-internal mechanics, not conversation branches |
| `Bash(claude …)` / `/schedule` / `claude --remote` | NOT YET (rare; cloud blind spot) | n/a | Acknowledged gap (cloud orchestrator dispatch is not locally observable) |
| SessionStart (local code session boot) | YES (`--on-session-start`) | n/a | Auto-emits own branch under project root |
| Stop (any session) | YES (`--on-stop`) | n/a | Auto-concludes branches this session opened |
| Heartbeat (every 5 min) | YES (`--heartbeat`) | n/a | Auto-concludes stale branches |

## How an agent self-applies Layer D

For every tool call that conceptually "opens / sends to / concludes" a branch in the conversation tree, the agent treats the call as a commitment to having a matching tree event. In practice:

1. **Before a `mcp__ccd_session__spawn_task` call:** the agent verifies the spawn is intentional (matches plan / user request); the auto-emit at Layer A handles the rest.
2. **After a `mcp__ccd_session__spawn_task` returns:** the agent records the returned `session_id` (if any) in its own working notes so it can later send to the child OR conclude on completion.
3. **When messaging a child branch:** if `mcp__ccd_session__send_message` (or equivalent) is exposed, call it. If only the GUI `POST /api/event` is available (cloud-Dispatch path), explicitly emit `branch-note-add` via that endpoint.
4. **When surfacing to the user:** classify the surface — decision / question / blocker / status — and ensure an event of the corresponding kind appears in the tree. The user reading the tree should see "this branch is asking me to decide X" before they read the actual surfacing message.
5. **When concluding work:** before sending a wrap-up message, confirm the branch's `concluded` event is in the tree. Either Layer A's Stop hook will fire, OR (cloud case) the agent emits explicitly.

## What this rule does NOT do

- **Does NOT block tool calls.** Every emit hook exits 0 on failure. Layer B auto-fills rather than refusing Stop. Layer D is self-applied, not gate-enforced.
- **Does NOT replace the existing `conversation-tree-state-gate.sh` and `conversation-tree-stop-gate.sh`** which enforce ADR-031 r7 Pin requirements (the agent CAN'T spawn without the state-file containing the spawned branch). Those gates are stricter than this rule's reconciliation — they refuse spawn / Stop when the contract isn't met. This rule's Layer B is COMPLEMENTARY: it auto-fills instead of refusing, so transient writer flakes don't escalate to user-visible gate blocks.
- **Does NOT reach genuine cloud Dispatch's tool calls.** Cloud Dispatch sessions don't load `~/.claude/` hooks. The discipline (Layer D) is the only enforcement there, and it requires the cloud orchestrator agent to be running in a session that has loaded this rule. For sessions that don't, the heartbeat (Layer C) still catches concludes-by-staleness when transcripts are teleported back.
- **Does NOT make backlog items, decision items, or in-branch action items auto-emit.** Those remain GUI-originated events (the human authors them). This rule covers session-lifecycle and cross-session-communication events only.

## Cross-references

- `~/.claude/hooks/conversation-tree-emit.sh` — Layer A primary; modes `--on-spawn`, `--on-stop`, `--on-session-start`, `--heartbeat`.
- `~/.claude/hooks/conv-tree-emit-reconciler.sh` — Layer B (added by this rule's accompanying enforcement PR).
- `~/.claude/hooks/conversation-tree-state-gate.sh` + `conversation-tree-stop-gate.sh` — refuse-on-mismatch gates per ADR-031 r7 / ADR-032 §8 / ADR-034.
- `neural-lace/conversation-tree-ui/scripts/register-heartbeat.ps1` — Layer C scheduled task registration.
- `docs/decisions/031-conversation-tree-ui-architecture.md` r7 — Mechanism + Pattern split for the conv-tree enforcement substrate.
- `docs/decisions/034-conversation-tree-scope-dispatch-only.md` — sub-agent Task/Agent explicitly out-of-scope.
- `neural-lace/conversation-tree-ui/state/schema.js` — `branch-opened`, `concluded`, `branch-note-add` event types.

## Enforcement summary

| Layer | What it does | File | Status |
|---|---|---|---|
| A | Per-tool side-effect emit | `~/.claude/hooks/conversation-tree-emit.sh` | shipped |
| A wiring | Hook wired at every applicable surface | `~/.claude/settings.json.template` | shipped |
| B | Pre-stop reconciliation of transcript ↔ ledger | `~/.claude/hooks/conv-tree-emit-reconciler.sh` | shipping with this PR |
| B wiring | Stop chain after `--on-stop` | `~/.claude/settings.json.template` | shipping with this PR |
| C | 5-min heartbeat scheduled task | `~/.claude/hooks/conversation-tree-emit.sh --heartbeat` | shipped |
| D | Agent discipline for cloud-Dispatch reach | this rule + agent self-application | shipping with this PR |
| User authority | Misha observes drift, points at it, asks for fix | (Pattern) | always |

## Scope

This rule applies in any session whose Claude Code installation has this rule file loaded AND has `conversation-tree-emit.sh` wired in `~/.claude/settings.json`. For sessions without the wiring (older harness installs), Layers A-C do not fire and the agent's Layer D discipline is the only enforcement — surface that gap to the user when noticed.
