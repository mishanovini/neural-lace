# Lesson — Background Agents Need a Push Heartbeat + Watchdog, Not Orchestrator Polling

**Date:** 2026-07-14
**Source case:** During a long orchestration session, a background plan-closure agent
committed its work and then **hung**. The orchestrator (main loop) was watching the agent's
`tasks/<id>.output` file for liveness and read it as **0 bytes** — which it misinterpreted as
"still working / no output yet" rather than "dead." The session idled for **~5 hours** before the
operator intervened ("you've just wasted five hours"). A launched-but-unconsumed background task is
a tracked obligation; the harness had no reliable way to notice it had stopped making progress.
**Nature:** Failure post-mortem → concrete harness-mechanism proposal (the `/harness-lesson` step).
**Harness gap exposed:** background Agent/Workflow tasks emit **no periodic liveness signal**, and
the orchestrator's only liveness proxy (output-file size / "has it returned yet") **cannot
distinguish a hung agent from a working-but-quiet one.** Absence of output ≠ absence of life, and —
critically — ≠ presence of life either.

---

## 0. TL;DR

Detecting a hung background agent by **polling its output** is unsound: a healthy agent mid-`Read`
and a wedged agent look identical (both produce no new output). The fix is to invert the signal —
**push, not pull**: each background agent writes a `{step, note, timestamp}` heartbeat to a
per-agent status file at every milestone, and a lightweight **watchdog** flags any agent whose
heartbeat has gone stale past a threshold. **Heartbeat-absence is the clean hang signal** — a truly
hung agent *cannot* heartbeat, so the stopping of the heartbeat is unambiguous where the stopping of
*output* is not. This is the textbook supervisor / failure-detector pattern (Erlang OTP, systemd
`WatchdogSec=`, k8s liveness probes, Chandra–Toueg ⋄P).

---

## 1. The failure, precisely

- **Expected:** the orchestrator dispatches a background builder, the builder finishes (or dies),
  and the orchestrator consumes the result promptly.
- **Actual:** the builder committed its work, then hung (no return, no crash). The orchestrator
  checked the `output` file, saw 0 bytes, inferred "in progress," and waited. And waited.
- **Trigger:** reliance on `output`-file emptiness as a liveness proxy. The builder had genuinely
  produced on-disk work (a commit) but never emitted its final result and never signalled progress
  in between, so nothing distinguished "thinking hard" from "wedged."
- **Detection delay:** ~5 hours, and only because the operator noticed the wall-clock, not because
  any mechanism fired.

## 2. Classification

**Self-report / liveness blind spot.** The harness trusted the *absence* of a negative signal
("output file isn't empty-and-stale in a way I recognize") as a positive one ("agent is alive"). The
same family as marking work done because no failure was observed — here, assuming life because no
death was observed.

## 3. Why the obvious fix (orchestrator polls harder) is wrong

The tempting fix is "have the orchestrator poll each agent's output more aggressively and time it
out." This is a **pull** design and it is fundamentally weak:

- **It can't tell wedged from busy.** A subagent doing a 4-minute `npm ci` or a long single
  `Read`/model call produces no incremental output. Poll-and-timeout either fires false positives on
  legitimately-quiet steps (killing good work) or is set so lax it misses real hangs (the 5-hour
  case). There is no threshold that separates the two from *output alone*.
- **It burns the orchestrator's context/cache.** Every poll is a tool call in the main loop; over
  hours that is real token + cache-eviction cost for near-zero information.
- **It scales badly.** N background agents → N polls per tick from one orchestrator.

The information the orchestrator actually needs — "is this agent still advancing?" — is knowledge
only the *agent* has. So the agent must **volunteer** it.

## 4. Proposed mechanism (deployable)

**A native heartbeat primitive for background Agent/Workflow tasks.**

1. **Agent side (push).** Every background agent gets an injected instruction + a tiny helper to
   emit a heartbeat at each milestone: append `{"step": "<n/label>", "note": "<what just finished>",
   "ts": <epoch>}` to a per-agent status file, e.g.
   `tasks/<agent-id>.heartbeat.jsonl` (separate from `.output` so it is cheap to stat/tail and never
   collides with the final result). Milestones = "started", after each major tool phase, before/after
   any long-running step (`npm ci`, a model-heavy analysis, a build). The bar is low: even one line
   per few tool calls converts silence into signal.
2. **Watchdog side (detect).** A cheap tick (self-wakeup or the existing background-task poller)
   that, per live agent, reads only the LAST heartbeat line and checks `now - ts`. If it exceeds a
   **step-aware** threshold (generous by default; longer for a step self-labelled "long"), surface
   the agent as **STALLED** to the orchestrator with its last known step — the orchestrator then
   pings it (SendMessage) or kills+salvages. Absence of *any* heartbeat past a startup grace window
   = "died before doing anything" (the transient-launch-failure case, which also occurred this
   session: an agent returned 0 tool-uses + a system-prompt fragment).
3. **Placement.** This belongs in the harness (the Agent/Workflow runtime), not in each dispatch
   prompt — a prompt-level instruction is a Pattern (relies on the agent remembering); the runtime
   primitive is a Mechanism. Until the runtime supports it, the interim Pattern is: dispatch prompts
   instruct agents to write the heartbeat file, and the orchestrator's watchdog tick scans it.

## 5. Honest residual risk

- **An agent that hangs *inside* a single indivisible step** (one giant model call that never
  returns) still won't heartbeat mid-step — but that is exactly what the staleness threshold catches:
  the last heartbeat ages out and the watchdog fires. The heartbeat doesn't need sub-step
  granularity; it needs to *stop* when the agent stops, which it does.
- **False positives** if the threshold is tighter than a legitimately-long step. Mitigation: make
  the threshold step-aware (the agent's own "this next step is long" note extends its own grace) and
  default generous — a late detection is far cheaper than killing good work.
- **Cooperation dependency:** a misbehaving agent could emit fake heartbeats. Acceptable — the threat
  model is *accidental* hangs, not adversarial agents; and a commit/on-disk-evidence check (the
  orchestrator already trusts artifacts over claims) remains the final arbiter.

## 6. Companion work

- Filed to the machine-wide ledger via `nl-issue.sh` (2026-07-14) as the quick capture; **this file
  is the durable write-up.**
- Supersedes an earlier, weaker note that proposed the orchestrator-polling design — that approach is
  rejected here for the reasons in §3.
- Related lesson: [`2026-07-13-false-nothing-needed-from-you.md`](2026-07-13-false-nothing-needed-from-you.md)
  (both are "the harness trusted an absence as a positive signal").
