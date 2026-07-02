# Background-Work Tracking — A Launched Background Task Is a Tracked Obligation Until Its Result Is Consumed

**Classification:** Hybrid. The Mechanism is `stalled-work-surfacer.sh` (SessionStart hook) — it scans recent background-Workflow journals for the stall signature and surfaces any that started-but-never-completed, so stalled work is **structurally impossible to forget across session boundaries**. The hook exists, passes its own self-test, and is wired in `settings.json.template`; live wiring is pending Wave B.6 install (the template has not yet been synced to the user's live `~/.claude/settings.json`). The Pattern is the per-turn discipline below: never claim a background task is "running" without verifying it, and verify before ending any turn that depends on one. The mechanism is the session-boundary safety net; the discipline is the mid-session check. Neither alone is sufficient; together they close the class.

**Originating failure (2026-06-13):** a background `Workflow` (run `wf_b0ebc82b-7e1`) ran 3 of its 4 agents, then the 4th (synthesis) started and silently died. The task disappeared. Nothing surfaced it — background workflows only notify on **completion**, so a *stall* is invisible — and the orchestrator repeatedly told the operator "it's running in the background, it'll auto-resume me." It was not running, and it did not resume. The operator caught it ("I don't see anything actually processing"), not the harness. Misha's directive: *"We CANNOT have a system that allows activity like that to simply stall and be forgotten."* This rule + its hook are the encode-the-fix response (`diagnosis.md` "After Every Failure: Encode the Fix"; `principles.md` Rule 6 preemptive-over-symptom, Rule 7 no-false-promises).

## The rule in one sentence

**Every background task you launch — a `Workflow` run, a dispatched session (`spawn_task` / `start_code_task`), any work that executes outside the current foreground turn — is a tracked obligation from launch until its result is consumed; you may not describe it as "running," "in flight," or "will resume me" without first verifying its current state, and you may not end a turn that depends on it without checking it.**

## What this prohibits (the exact failure that happened)

- ❌ "It's running in the background and will auto-resume me" — asserted without checking. Background completion notifications fire only on success; a stall produces **no** signal. Asserting liveness you have not verified is a false promise (Rule 7).
- ❌ Launching a `Workflow`/dispatch and moving on as if completion is guaranteed. It is not. Agents stall, die, and take the task with them.
- ❌ Re-narrating a prior turn's "it's running" as still-true. Liveness is not durable; it must be re-checked each time it is claimed.

## What to do instead

1. **On launch:** record what you launched (run id / task id) where a later turn will see it — SCRATCHPAD or a state file. A launched task you didn't write down is a task you will forget.
2. **Before claiming it's running / in flight / will-resume-me:** verify. For a `Workflow`, read its `journal.jsonl` — `started` count vs `result` count, and the file's mtime. `started > result` + a stale mtime = **stalled, not running**. For a dispatched task, check `TaskList` / the task's transcript. State PROVEN/HYPOTHESIZED honestly (`claims.md`): "verified running (journal active 30s ago)" vs "launched; status unverified."
3. **Before ending a turn whose next step depends on the task:** check it. If it completed → consume the result. If it stalled → recover in the foreground (the completed sub-results are usually salvageable from the journal; synthesize the remainder yourself rather than re-launching another stall-prone background run). If genuinely still running → say so *with* the evidence (last-activity timestamp), not as an assumption.
4. **Prefer the foreground for work whose completion you must guarantee.** Background fan-out is for genuine parallelism you will actively poll; it is not a way to "set work going and forget it." When a delegated background run stalls, the reliable recovery is foreground synthesis from its completed parts — proven on the originating failure.
5. **On recovery:** once a stalled run is recovered/consumed, `touch <run-dir>/.stall-acked` so the surfacer stops re-flagging it.

## The Mechanism — `stalled-work-surfacer.sh` (SessionStart)

At every session start it scans `~/.claude/projects/*/*/subagents/workflows/*/journal.jsonl` (within a 48h lookback) and surfaces any run whose **`started` event count exceeds its `result` event count AND whose journal has been idle longer than `STALLED_WORK_STALE_MIN` (default 10 min) AND has no `.stall-acked` marker.** A completed run (`started == result`) is never flagged; an actively-running run (fresh mtime) is never flagged. Output names the run, the stall counts, last-activity age, the resume command, and the recovery path. Silent when nothing is stalled. Exits 0 always (never blocks session start). `--self-test` exercises stalled / completed / still-running / acked / none, and it was verified against the real `wf_b0ebc82b-7e1` failure at authoring time.

Config: `STALLED_WORK_STALE_MIN` (default 10), `STALLED_WORK_LOOKBACK_MIN` (default 2880 / 48h), `STALLED_WORK_SCAN_ROOT` (default `~/.claude/projects`).

## Honest limits (named, not hidden — Rule 7)

- **Session-boundary, not real-time.** The surfacer catches a stall at the *next session start*, guaranteeing it is never *permanently* forgotten. It does NOT catch a stall *mid-session* — that is what the per-turn verify-before-claim discipline (above) is for. A real-time heartbeat (scheduled task scanning every N min, writing a surfaced marker) would close the mid-session gap and is the named next enhancement; it is not built yet.
- **Workflow journals only.** It detects stalled `Workflow` runs (the originating failure class). Dispatched-session (`spawn_task`) liveness is covered by the existing `spawned-task-result-surfacer.sh` (unread-result surfacing) + the `dispatch-session-monitor` scheduled task; a unified background-work ledger spanning all three is a candidate consolidation, not yet built.
- **Cloud sessions** that don't load `~/.claude/` hooks don't run the surfacer (the documented cloud blind spot shared by every hook).

## Cross-references

- `~/.claude/hooks/stalled-work-surfacer.sh` — the Mechanism.
- `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix" — the doctrine this rule executes.
- `~/.claude/rules/principles.md` Rule 6 (preemptive over symptom-treating) + Rule 7 (no false promises) — the principles the originating failure violated.
- `~/.claude/rules/claims.md` — PROVEN/HYPOTHESIZED labeling for "is it running" claims.
- `~/.claude/rules/automation-modes.md` "Recurring-check vocabulary" — heartbeat vs surfacer vs wake-up (the named real-time enhancement is a background-task heartbeat).
- `~/.claude/rules/spawn-task-report-back.md` + `~/.claude/hooks/spawned-task-result-surfacer.sh` — the sibling surfacer for dispatched-session results.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | A launched background task is a tracked obligation; verify-before-claiming; verify-before-ending-a-dependent-turn; prefer foreground for must-complete work | `adapters/claude-code/rules/background-work-tracking.md` |
| Hook (Mechanism, wired in template; live wiring pending Wave B.6 install) | Stalled background-Workflow runs surfaced at every session start; never permanently forgotten | `adapters/claude-code/hooks/stalled-work-surfacer.sh` |
| User authority | The operator catches a stall the discipline missed mid-session (the originating incident) — until the heartbeat enhancement lands | (Pattern) |

## Scope

Applies in any session whose Claude Code installation has `stalled-work-surfacer.sh` wired in the SessionStart chain. The hook is wired in the canonical `settings.json.template`; live wiring is pending Wave B.6 install. The discipline binds every agent in every mode that can launch background work (Workflows, dispatched sessions). The surfacer is defensively inert where it cannot apply (no projects dir, no workflow journals) and never blocks session start.
