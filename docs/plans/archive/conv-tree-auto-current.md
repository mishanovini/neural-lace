# Plan: Conv Tree auto-current (session-start emit + heartbeat)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal observability — no user-facing product surface, self-tests are the acceptance artifact
tier: 1
rung: 0
architecture: extends conversation-tree-emit.sh with two new modes (--on-session-start, --heartbeat) and adds a GUI /api/health liveness probe + freshness badge. Pure additive — no contract changes to existing events or sinks. Composes with the existing on-spawn/on-stop pair.
frozen: true

## Goal
Keep the Conversation Tree state file current automatically without depending on the cloud-side Dispatch orchestrator's tool calls (which never reach the local PreToolUse hook). The tree's "stale 4 days" failure mode (P1, surfaced 2026-05-22) was caused by the orchestrator running where ~/.claude/ does not load, so --on-spawn never fired in production. The fix emits from the CHILD's side at SessionStart and adds a scheduled heartbeat to mark live sessions and conclude stale ones.

## Scope
- IN: emit hook --on-session-start mode, --heartbeat mode, SessionStart wiring, scheduled task registration, /api/health endpoint, GUI freshness badge.
- OUT: refactoring the on-spawn/on-stop pair (still works for any future local orchestrator); GUI behavior changes (passive observer invariant intact); state schema changes (events are existing branch-opened/concluded shapes).

## Tasks

- [x] 1. Add --on-session-start mode to conversation-tree-emit.sh (child-side self-registration; idempotent on event_id). Verification: mechanical
- [x] 2. Add --heartbeat mode (transcript scan → live-marker refresh / stale conclude). Verification: mechanical
- [x] 3. Wire --on-session-start into SessionStart hooks (live + template). Verification: mechanical
- [x] 4. Add /api/health endpoint to server.js. Verification: mechanical
- [x] 5. Add freshness badge to GUI (HTML + CSS + 30s polling). Verification: mechanical
- [x] 6. Register-heartbeat.ps1: Windows scheduled task wrapper for --heartbeat (every 5 min). Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — new modes
- `adapters/claude-code/settings.json.template` — SessionStart wiring
- `neural-lace/conversation-tree-ui/server/server.js` — /api/health
- `neural-lace/conversation-tree-ui/web/app.js` — freshness polling
- `neural-lace/conversation-tree-ui/web/app.css` — badge styling
- `neural-lace/conversation-tree-ui/web/index.html` — badge element
- `neural-lace/conversation-tree-ui/scripts/register-heartbeat.ps1` — scheduled task wrapper

## In-flight scope updates
(none — all files declared upfront)

## Assumptions
- Claude Code's SessionStart hook fires reliably on Misha's local machine for every locally-running session (verified: my own session emitted on its SessionStart).
- Windows Task Scheduler runs scheduled tasks reliably when the user is logged in (verified: ConversationTreeUI-AutoStart already runs this way).
- The existing emit-hook ledger format (opened-<sid>.jsonl with node_id\ttitle\ttimestamp) is stable.
- Cloud-side Dispatch orchestrator does NOT load ~/.claude/ hooks (per Decision 011); we don't try to change that.

## Edge Cases
- SessionStart re-fires on resume/compact → idempotent event_id makes it a per-file no-op.
- Multiple local sessions running concurrently → each registers its own branch indexed by session_id; ledger files are per-session so no collision.
- Heartbeat fires while a session is mid-transcript-write → transcript mtime is fresh, marker is refreshed; no false-conclude.
- Heartbeat fires when laptop was asleep > 60min → all live markers are stale, all branches concluded. Acceptable: when sessions resume, --on-session-start re-registers them.
- GUI server restart → /api/health returns same data; mtime-based, no in-memory state.

## Acceptance Scenarios
n/a (acceptance-exempt: true) — self-tests + manual verification of end-to-end emit on session start are the acceptance artifact.

## Testing Strategy
- Existing self-test (`conversation-tree-emit.sh --self-test`) covers all 31 prior scenarios; must still pass.
- Manual: invoke `--on-session-start` with synthetic stdin → ledger + live-marker created.
- Manual: invoke `--heartbeat` → refreshes markers for active transcripts, writes heartbeat.last.
- Manual: hit `/api/health` → returns state_mtime + heartbeat_mtime.
- End-to-end: this very session's SessionStart should have emitted; tree should show this branch.

## Walking Skeleton
Single-file walk-through: SessionStart fires → emit hook reads stdin (session_id, cwd, source) → derives project root + title → writes 2 branch-opened events (root + child) to BOTH sinks → ledger entry created → live-marker touched. Five minutes later, heartbeat scheduled task fires → finds the live-marker fresh (under 15min window) → re-touches it. Sixty minutes after this session ends, heartbeat finds stale marker → emits concluded for this session's branch → removes marker.

## Decisions Log
### Decision: child-side SessionStart emit vs. orchestrator-side fix
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** child-side SessionStart emit
- **Alternatives:** (a) change cloud-side Dispatch to call a webhook into local — requires Anthropic-side change, out of reach. (b) Periodic poll of cloud session list — no API exists. (c) Child-side emit — works with existing harness mechanics, idempotent, additive.
- **Reasoning:** The cloud orchestrator's PreToolUse hooks aren't accessible from the local harness. The child IS local. SessionStart fires reliably. Same event surface, same sinks — additive only.
- **Checkpoint:** N/A (Tier 1)

### Decision: scheduled task vs. server-side heartbeat
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Windows scheduled task running --heartbeat
- **Alternatives:** (a) GUI server runs heartbeat itself — breaks ADR-031 Option 2 passive-observer invariant. (b) Scheduled task — separate process, GUI invariant preserved, survives GUI restart.
- **Reasoning:** ADR-031 r7 explicitly forbids the GUI server from originating events. The heartbeat IS an originator. Keep them separate.

## Definition of Done
- [x] All tasks checked off (task-verifier flips on merge)
- [x] Self-test passes (31/31)
- [x] On-session-start manually verified (this session, log entry timestamped 2026-05-22T23:52:36Z)
- [x] Heartbeat task registered and LastTaskResult=0
- [x] /api/health returns valid JSON after server restart
- [x] Tree visibly updating live in the GUI

## Evidence Log

EVIDENCE BLOCK
Task ID: 1
Verdict: PASS
Task: Add --on-session-start mode to conversation-tree-emit.sh
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2 (merge), b4fdf3b (impl)
Runtime verification: bash ~/.claude/hooks/conversation-tree-emit.sh --self-test → 31/31 PASS
Files: adapters/claude-code/hooks/conversation-tree-emit.sh
Notes: Mode is idempotent on deterministic event_id; tested with synthetic SessionStart input — both sinks received events (log timestamp 2026-05-22T23:52:36Z).

EVIDENCE BLOCK
Task ID: 2
Verdict: PASS
Task: Add --heartbeat mode
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2
Runtime verification: bash ~/.claude/hooks/conversation-tree-emit.sh --heartbeat → exit 0, "refreshed 7 live marker(s)" (log timestamp 2026-05-22T23:56:55Z); subsequent heartbeats at 00:01:54, 00:06:56, 00:11 — confirming the 5-min cadence.
Files: adapters/claude-code/hooks/conversation-tree-emit.sh

EVIDENCE BLOCK
Task ID: 3
Verdict: PASS
Task: Wire --on-session-start into SessionStart hooks
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2
Runtime verification: grep -c "conversation-tree-emit.sh --on-session-start" both files → 1 and 1
Files: ~/.claude/settings.json (live), adapters/claude-code/settings.json.template (canonical)

EVIDENCE BLOCK
Task ID: 4
Verdict: PASS
Task: Add /api/health endpoint to server.js
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2
Runtime verification: curl http://127.0.0.1:7733/api/health returns valid JSON with ok=true, state_age_seconds, heartbeat_age_seconds, heartbeat_stale=false (confirmed end-to-end post-merge after server restart).
Files: neural-lace/conversation-tree-ui/server/server.js

EVIDENCE BLOCK
Task ID: 5
Verdict: PASS
Task: Add freshness badge to GUI
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2
Runtime verification: grep "freshness" web/index.html → 1; grep "pollHealth" web/app.js → 2; grep ".freshness" web/app.css → 2 matches.
Files: neural-lace/conversation-tree-ui/web/index.html, app.js, app.css

EVIDENCE BLOCK
Task ID: 6
Verdict: PASS
Task: Register-heartbeat.ps1 Windows scheduled task
Commit: 02f3ad9905e6b23fb5b9f2c7bf7b3fca9305a0e2
Runtime verification: powershell Get-ScheduledTask 'ConversationTreeUI-Heartbeat' → State=Ready, LastTaskResult=0, NextRunTime advancing every 5 min.
Files: neural-lace/conversation-tree-ui/scripts/register-heartbeat.ps1

