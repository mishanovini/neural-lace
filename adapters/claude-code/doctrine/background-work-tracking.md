# Background-work tracking — compact
> Enforcement: `stalled-work-surfacer.sh` (SessionStart — surfaces stalled Workflow runs AND stalled agent heartbeats via `agent-heartbeat.sh watch`)
> Applies: any background task you launch (Workflow run, spawned session, dispatch)

A launched background task is a tracked obligation from launch until its result
is consumed. Background completion notifications fire only on success — a
STALL produces no signal. Do not assert a task is "running" or "will resume me"
without verifying it.

**Verify before claiming.** For a Workflow, read its `journal.jsonl`: compare
the `started` event count to the `result` event count. `started > result` plus a
stale mtime means STALLED, not running. State PROVEN/HYPOTHESIZED honestly
(doctrine/claims.md): "verified running (journal active 30s ago)" vs "launched;
status unverified."

Before ending a turn whose next step depends on the task, check it. Completed →
consume the result. Stalled → recover in the foreground (synthesize from the
completed sub-parts rather than re-launching another stall-prone background
run). Still running → say so WITH the evidence (last-activity timestamp), never
as an assumption.

Prefer the foreground for work whose completion you must guarantee. Background
fan-out is for genuine parallelism you will actively poll, not a way to set work
going and forget it.

On recovery, mark the run acknowledged so it stops re-surfacing (`touch
<run-dir>/.stall-acked`).

Session-boundary catch, not real-time: a stall is caught at the NEXT session
start, not mid-session — the per-turn verify-before-claim discipline above is
what closes the mid-session gap.

**Agent heartbeat (interim Pattern).** Output-absence can't tell a hung agent
from a busy one, so agents PUSH liveness. When you dispatch a long background
agent, tell it in the prompt to emit at each milestone:
`bash ~/.claude/scripts/agent-heartbeat.sh emit --agent <id> --step <n> --note <what> [--long]`
(`--long` triples that step's staleness grace). `agent-heartbeat.sh watch`
(wired above) flags any agent whose last beat aged past threshold (default 20m).
Honest scope: this is a PATTERN (relies on the agent emitting; the true runtime
auto-heartbeat is not in-repo) and it catches the "worked, then wedged" class —
exactly the 5h hang in the 2026-07-14 lesson. Ack a handled stall:
`touch ~/.claude/state/heartbeats/agents/<id>.ack`.
