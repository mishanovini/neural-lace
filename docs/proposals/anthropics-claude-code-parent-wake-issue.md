# Draft GitHub issue — anthropics/claude-code: parent session wake on child turn-end

**Purpose of this file:** copy-pasteable issue text for `anthropics/claude-code`. This is
the *curative* fix for RC1 (no parent-wake), which cannot be closed harness-side (see
`docs/discoveries/2026-05-25-dispatch-coordination-debug.md` and ADR-042/039). Misha
files it; the harness ships the bounded palliatives in the meantime.

**Before filing:** check the referenced issues are still the right ones to cross-link and
search for a newer duplicate; fold this into an existing thread if one now covers it.

---

## Title

Inter-session coordination: wake / notify a parent session on child (sub-session) turn-end or idle

## Labels (suggested)

`enhancement`, `agent-sdk`, `sessions`, `dispatch`

## Body

### Summary

When one Claude Code session orchestrates child sessions (Dispatch "spawn task" /
`start_code_task`, or the Agent SDK spawning sub-sessions), there is no mechanism for a
**child's turn-end or idle-waiting state to wake or notify the parent**. The parent is
event-driven and sleeps; the child finishes its turn and goes idle awaiting the next
directive; nothing advances. The relay hangs until a human intervenes or an unrelated
event restarts the parent. This makes autonomous multi-session orchestration unreliable
for any workflow longer than a single parent turn.

### Environment

- Claude Code 2.1.146 (`AI_AGENT=claude-code_2-1-146_agent`, `CLAUDE_AGENT_SDK_VERSION=0.3.146`)
- Entry point: `claude-desktop` (Dispatch / desktop-hosted orchestration)
- Platform: Windows 11 (also reproduces conceptually on any host — this is an architecture gap, not OS-specific)

### What happens

1. Parent (orchestrator) session spawns a child session with a brief.
2. Child executes, reaches a point where it needs the next directive (or finishes its
   work), and **goes idle / ends its turn**.
3. The parent is not running a tool loop at that moment (it's "asleep" between events).
4. **No event is delivered to the parent.** The child's completion/idle is invisible to
   the parent until the parent is independently restarted (new user message, manual poll,
   session reopen). The coordination silently stalls.

### What we expected

One of:
- A **`SubagentStop` / child-turn-end event delivered to the parent** that re-enters the
  parent's loop (analogous to how local hooks fire, but cross-session), **or**
- **Inter-session message delivery that is not deferred to the parent's `stop_reason=end_turn`**
  (the current deferral behavior, see #50779, means a parent never sees a child's message
  until the parent's own loop already ended — which is exactly when it can't act on it), **or**
- An official **inter-session messaging / callback primitive** in the Agent SDK so an
  orchestrator can `await` a child's completion or register a wake callback.

### Why workarounds are insufficient

- **Report-back-via-file + poll-on-next-start:** a child can write a result file and the
  parent can read it at *its next SessionStart*, but nothing *triggers* a parent
  SessionStart on child completion. The parent must be woken by something external.
- **Parent-side polling (`ScheduleWakeup` / scheduled tasks):** bounds the hang (the
  parent wakes on a timer and checks), but it is a busy-wait — it burns turns/cache on a
  cadence and adds latency equal to the poll interval. It is a palliative for "hangs
  forever," not a fix for "should resume promptly on child completion."
- **Out-of-band push (ntfy/etc.) to the human:** routes around the gap by waking the
  *human*, not the parent session. Useful, but it makes a human the scheduler.

### Related issues

- #40070 — (parent/child session coordination; the closest existing thread — please dedupe against this)
- #50779 — inbox messages to lead deferred until `stop_reason=end_turn` (the deferral that defeats in-band coordination)
- #1770, #24798, #37213, #44380 — open threads on inter-session messaging / sub-session lifecycle visibility

### Concrete ask (smallest useful fix first)

A delivered **`SubagentStop`-equivalent cross-session event**, or **non-deferred
inter-session message delivery**, that re-enters a parent orchestrator's loop when a child
session ends its turn or goes idle. Even a best-effort, at-least-once notification (parent
de-dupes) would let orchestrators stop relying on human-as-scheduler or timer polling.

### Impact

This is the load-bearing gap for autonomous multi-session orchestration. Without it, every
multi-session workflow either stalls silently or requires a human / timer to keep it
moving — which negates the value of spawning child sessions for unattended work.
