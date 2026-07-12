---
title: orchestrator-prime keepalive can't invoke Skill in scheduled context
date: 2026-06-11
type: process
status: pending
auto_applied: false
originating_context: orchestrator-prime-keepalive scheduled task (hourly + on-launch), autonomous run 2026-06-11
decision_needed: How should the keepalive cold-start orchestrator-prime when the Skill tool cannot see file-based ~/.claude/skills/*.md skills in a scheduled-task session registry?
predicted_downstream:
  - <home>/.claude/scheduled-tasks/orchestrator-prime-keepalive/SKILL.md
  - adapters/claude-code/skills/orchestrator-prime.md
  - adapters/claude-code/rules/dispatch-relay-protocol.md
---

## What was discovered

The `orchestrator-prime-keepalive` scheduled task is designed to ensure exactly one
orchestrator-prime session is running, cold-starting it via `Skill(skill="orchestrator-prime")`
when none is. In an autonomous scheduled run on 2026-06-11, that call returned:

```
<tool_use_error>Unknown skill: orchestrator-prime</tool_use_error>
```

The skill file is present on disk in BOTH locations:
- `~/.claude/skills/orchestrator-prime.md` (live mirror, 12269 bytes)
- `~/claude-projects/neural-lace/adapters/claude-code/skills/orchestrator-prime.md` (canonical)

The failure is a **registry** gap, not a missing-file gap. This scheduled-task session's
available-skills set excludes orchestrator-prime AND every other file-based personal skill
under `~/.claude/skills/` (`close-plan`, `harness-review`, `calibrate`, `find-bugs`,
`grant-local-edit`, `pt-implement`, `pt-test`, `verbose-plan`, `verify-feature`,
`why-slipped`, `harness-lesson`, `teaching-moments`). Only directory-based skills
(`<product>-doc-reviewer`, `find-skills`, `new-project-setup`) and plugin/marketplace skills
are registered in this context. So the keepalive's prescribed cold-start mechanism is
inoperable in the scheduled-task (and likely cloud/headless) session type the task is
designed to run in (hourly + on-launch).

## Why it matters

The keepalive's single job — auto-respawn orchestrator-prime after a reboot or after it
exits — silently no-ops whenever it must actually cold-start. orchestrator-prime then only
comes up when Misha launches it interactively (where the file-based skills ARE registered).
The reboot-resilience story in `skills/orchestrator-prime.md` ("a durable scheduled-task
re-spawns you on app launch") does not hold in practice through the Skill-tool path.

This run did NOT attempt a workaround cold-start, for two independent reasons:
1. **Duplicate risk:** the single most-recently-active session in `list_sessions` was
   `orchestrator-prime` itself (`local_086cd4b4`, last activity 2026-06-12T01:20:54Z) showing
   `isRunning: false`. For a ScheduleWakeup-paced orchestrator, that most plausibly means
   *sleeping between cycles*, not *dead* — and the keepalive's own rule is "never spawn a
   second if one is already alive." A duplicate orchestrator (double-merging PRs,
   double-chipping Misha) is strictly worse than a one-hour coverage gap the next fire closes.
2. **No working autonomous cold-start primitive:** `spawn_task` only surfaces a chip that
   Misha must click (not an unattended respawn), and firing one every hourly failure would
   spam Misha with duplicate "relaunch" chips (the exact noise failure orchestrator-prime's
   own dedup guard warns against).

## Options

A. **Register file-based `~/.claude/skills/*.md` skills in scheduled-task session registries**
   so `Skill("orchestrator-prime")` resolves there (fixes the class for every file-based skill,
   not just this one). Strongest fix; depends on whether the harness controls the scheduled-task
   skill registry.
B. **Give the keepalive a Skill-independent cold-start primitive** — e.g. follow the
   orchestrator-prime SKILL.md startup procedure inline, or launch via a documented
   non-Skill path. Risk: turns the ephemeral keepalive into the orchestrator, conflating the
   two; high-consequence autonomous actions (PR merges) from a constrained context.
C. **Reframe the keepalive to surface-not-respawn**: when cold-start is needed, write a durable
   discovery (as here) + optionally ONE deduped chip (guarded by a marker file so it fires at
   most once per outage), rather than attempting an autonomous respawn. Honest about the
   platform limitation; relies on Misha's click for the actual relaunch.
D. **Teach the keepalive to distinguish sleeping-vs-dead** (e.g. check for a pending
   ScheduleWakeup / scheduled task tied to the orchestrator-prime session, or a recent
   `last_cycle_at` in `~/.claude/orchestrator-prime/state.json`) so it only acts when truly
   dead — reducing both false respawns and missed respawns.

## Recommendation

A as the durable root-cause fix (register file-based skills in scheduled contexts), paired
with D so the keepalive's alive-check is robust to the sleeping-between-cycles case. C is the
honest interim behavior until A lands. B is discouraged — it routes around the broken launch
path with high-consequence autonomous actions from the wrong context.

## Decision

Pending Misha. This run took no respawn action (duplicate risk + broken mechanism) and
captured the gap here for surfacing.

## Implementation log

(empty — pending decision)
