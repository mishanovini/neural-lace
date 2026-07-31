# Spawn-Task Report-Back — compact
> Enforcement: spawned-task-result-surfacer.sh (SessionStart). Full: doctrine/spawn-task-report-back-full.md
> Applies: every `mcp__ccd_session__spawn_task` dispatch — the callback convention for a fire-and-forget MCP tool.

- `mcp__ccd_session__spawn_task` has no built-in callback. The convention: orchestrator embeds a literal sentinel line `Report-back: task-id=<task-id>` in the spawn prompt; the spawned session writes its result JSON before its own Stop hook fires; a SessionStart hook surfaces unread results on the orchestrator's next session start.
- Task-id format: `<YYYY-MM-DDTHH-MM-SS>-<short-slug>` — monotonic, kebab-case, collision-resistant.
- Result JSON lands at `.claude/state/spawned-task-results/<task-id>.json`. Schema: `task_id`, `started_at`, `ended_at`, `branch`, `pr_url` (or null), `exit_status` (ok|failed|partial), `summary` (1-3 sentences), `commits[]`, `artifacts[]`.
- Surfacer scans that directory for `*.json` files lacking a sibling `*.json.acked` marker and emits a system-reminder block per unread result (task-id, exit_status, branch, commits, summary, artifacts). Silent when nothing unread or the directory doesn't exist.
- Orchestrator acts on the surfaced result (cherry-pick, verify, replan) THEN writes `touch .claude/state/spawned-task-results/<task-id>.json.acked` — the ack marker stops re-surfacing. Forgetting the ack means the result re-surfaces every session; that repetition is itself the signal a loop wasn't closed.
- Spawned session crashes before writing → no result file → surfacer silent; fall back to checking git artifacts directly (branch/commits existence).
- Same convention composes with the Dispatch orchestrator's broader tree-tracking (workstreams-state.md) but is independent of it — this is the raw data callback, not the tree-visibility layer.
