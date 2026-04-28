# Decision 012: Agent Teams integration — six design decisions

**Date:** 2026-04-27
**Status:** Active
**Tier:** 2
**Stakeholders:** Misha (maintainer)
**Plan:** [`docs/plans/agent-teams-integration.md`](../plans/agent-teams-integration.md)
**Supporting analysis:** [`docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`](../reviews/2026-04-27-agent-teams-conflict-analysis.md)

## Context

Anthropic shipped an experimental Agent Teams feature
(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, requires Claude Code v2.1.32+).
A "lead" Claude Code session can spawn long-lived "teammate" sessions via a
new `Agent` tool (formerly `Task`) and a new pair of TaskCreated /
TaskCompleted hook events. Teammates run with their own session IDs, their
own working directories (optionally git worktrees), and their own tool
loops; they can be in-process (lead's process tree) or pane-based
(separate tmux/iTerm2 panes).

A Phase 1 conflict analysis (`docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`)
catalogued every Neural Lace harness mechanism (35 hooks, 17 agents, 6
skills, 17 rules) against every documented teammate event matcher. Five
hard blockers and three soft blockers were identified — enabling Agent
Teams without harness changes would silently degrade enforcement in
specific, named ways:

1. `tool-call-budget.sh` is keyed by `CLAUDE_SESSION_ID`. Five teammates
   each accumulate 30 calls before any audit fires — six times the
   calibrated cadence. Cumulative-build assumption broken.
2. Pane-based teammates (the macOS+tmux default) silently drop
   `SubagentStart`/`Stop`/`TeammateIdle`/`TaskCompleted` at the parent
   process per Anthropic issue #24175. Plan-integrity, acceptance-gate,
   and SubagentStop verification all assume parent visibility.
3. Inbox messages from teammates to lead are deferred until
   `stop_reason=end_turn` per Anthropic #50779 — broken on Opus 4.7 (the
   currently configured default model).
4. `teammate_name` and `team_name` are NOT in PreToolUse / PostToolUse /
   Stop from teammate sessions per Anthropic #45329. The harness has no
   per-teammate attribution surface for tool calls.
5. Agent frontmatter `hooks:` is empirically NOT propagated to teammates
   (#45329, plugin-equivalent rule). Per-agent hook scoping is broken.

Plus pre-existing harness drift surfaced during the analysis — Stop chain
documentation 4-vs-5 staleness; templates `decision-log-entry.md` and
`completion-report.md` not mirrored to `adapters/claude-code/templates/`.
These are absorbed into this plan's scope as HARNESS-DRIFT-03 and
HARNESS-DRIFT-04.

The plan addresses each named blocker via a new mechanism or amendment.
Six design decisions shape the work — each is recorded below with
alternatives, reasoning, and reversal cost. The plan does NOT enable
Agent Teams; it makes enabling it safe. The user flips the env flag
in a subsequent session after the plan completes.

## Decision

Six coordinated decisions, all approved by the user 2026-04-27 in plan
review. Each is a Tier-2 architecture choice that shapes one or more of
the plan's 14 tasks.

### 1. Tool-call budget scope + audit cadence — per-team with deferred-audit on TaskCompleted, hard ceiling at 90

The tool-call-budget gate is rescoped from per-`CLAUDE_SESSION_ID` to
per-`team_name` in agent-team mode. The counter is keyed by the team
name resolved from the firing session's membership in
`~/.claude/teams/<team>/config.json`; solo sessions fall back to the
existing per-session keying.

In agent-team mode, the gate behavior at the 30-call threshold also
changes: instead of mid-stream blocking the tool call, the hook writes
a flag at `~/.claude/state/audit-pending.<team>` and allows the call
through. The new `task-completed-evidence-gate.sh` (see Decision 4
below) reads the flag at the next TaskCompleted boundary, runs
`plan-evidence-reviewer`, and either clears the flag (PASS verdict —
counter resets, TaskCompleted allowed) or blocks TaskCompleted (FAIL
verdict — findings must be addressed first).

A per-teammate sub-counter tracks runaway-task drift: if a single
teammate accumulates 90+ tool calls without an intervening TaskCompleted
clearing the flag, the gate falls back to mid-stream blocking. This
preserves the original "drift detection" property for tasks that grow
long without disrupting team-coordination flow on normal-length tasks.

Solo-mode behavior unchanged — block at 30, require ack — preserving
the original calibration for the single-builder case.

### 2. teammateMode default — force `in-process` via feature flag

The harness sets `force_in_process: true` as the default in
`~/.claude/local/agent-teams.config.json`, overriding Anthropic's
`auto` default until upstream issue #24175 is resolved. The spawn
validator (Task 5) rejects spawns that would land in pane-based mode
when this flag is true.

Pane-based mode silently drops parent-visible events on macOS+tmux,
which is precisely where the harness gates need to fire. In-process
mode loses some parallelism but keeps every event firing reliably at
the parent. Reliability is the load-bearing property.

### 3. Worktree-mandatory for write-capable teammates

Spawn validator (Task 5) rejects any `Agent` tool spawn that lacks
`isolation: "worktree"` AND grants the spawned agent write-capable
tools (Edit / Write / MultiEdit / Bash). Read-only teammates do not
need worktrees.

Without worktree isolation, multiple teammates editing the same working
tree race at the filesystem level. Two simultaneous `git commit`
invocations on the same working directory corrupt index state.
Worktree-mandatory turns this from a runtime race into a spawn-time
rejection — much cheaper to debug.

### 4. TaskCreated / TaskCompleted hooks as new enforcement surface

Two new hook events join the harness:

- `task-created-validator.sh` rejects TaskCreated when the
  `task_description` lacks a plan reference (`docs/plans/<slug>.md`)
  or an acceptance criterion / `Done when:` clause.
- `task-completed-evidence-gate.sh` rejects TaskCompleted when an
  evidence block doesn't exist at `<plan>-evidence.md` referencing the
  task ID, AND coordinates the deferred-audit flag from Decision 1.

These provide team-attributable enforcement that per-Edit hooks cannot
(per #45329). The TaskCreated/Completed event input includes
`teammate_name` and `team_name`, unlike the per-tool events.

### 5. Acceptance loop in team mode — lead-aggregate

The `end-user-advocate` agent's runtime mode runs only on the lead
session against the team's shared plan. Per-teammate scenarios are
NOT introduced. Lead-invoked `task-verifier` validates per-teammate
work as it lands.

Scenarios are per-plan; plans are per-team in agent-team mode. The
advocate's adversarial-observation discipline holds at the team-level
outcome. Per-teammate scenarios introduce coordination overhead that
adds no detection power for team-level outcomes. Reversible — a
future plan can add `per-teammate-scenarios: true` to the plan
template.

### 6. Feature flag for safe rollout

The integration ships disabled by default. `~/.claude/local/agent-teams.config.json`
controls the rollout:

```json
{
  "enabled": false,
  "force_in_process": true,
  "worktree_mandatory_for_write": true,
  "per_team_budget": true
}
```

The spawn validator (Task 5) refuses to allow `Agent` tool spawns with
a `team_name` parameter when `enabled: false`. The user opts in by
flipping the field after the plan completes, with full visibility into
the five upstream bugs they're accepting (documented in `rules/agent-teams.md`).

Same pattern as the existing public-repo block, force-push block, and
`--no-verify` block: dangerous-by-default behaviors that are fine if
the user knows what they're accepting. Re-evaluate the default once
Anthropic resolves #50779 and #24175.

## Alternatives Considered

### Decision 1 alternatives

- **Per-session (status quo extended):** Each teammate gets its own
  30-call budget. With five teammates that's 150 cumulative calls
  before any audit — six times the calibrated cadence. The whole
  point of the budget is that drift compounds across many small tool
  calls; multiplying it by N teammates breaks the gate. Rejected.
- **Per-team with mid-stream block at 30:** Maps directly to the
  original gate's intent but disrupts team coordination — one
  teammate hitting the threshold blocks every teammate's next tool
  call until the lead audits. The deferred-audit-on-TaskCompleted
  variant keeps the audit cadence right while preserving team flow.
- **Per-team with deferred audit only (no hard ceiling):** Elegant
  but lets a single runaway task accumulate hundreds of calls
  without check. The 90-call sub-counter restores the original
  drift-detection property.
- **Per-machine / per-user:** Cross-pollination across unrelated
  work. Predictability erodes.

### Decision 2 alternatives

- **Default `auto`:** Ships the silent-drop failure mode on
  macOS+tmux. Rejected.
- **Always pane-based:** Loses lead-process visibility into
  teammates entirely. Defeats the integration's purpose.

### Decision 3 alternatives

- **Optional (warning only):** Teammates without worktrees still race;
  a warning that's ignored at spawn time produces no improvement
  over the status quo.
- **Worktree always (read-only too):** Unnecessary complexity;
  read-only teammates have no filesystem-write race.

### Decision 4 alternatives

- **Per-Edit gating only (status quo extended):** Lacks team
  attribution per #45329; can't enforce team-aggregate concerns.
- **Defer to Phase 2:** Ships agent-teams without team-task-aware
  enforcement. Decision 1's deferred-audit cadence depends on
  TaskCompleted firing; without these hooks the cadence design fails.

### Decision 5 alternatives

- **Per-teammate scenarios:** Each teammate runs its own advocate
  against its own scenario subset. Multiplies infrastructure, adds
  coordination overhead, and produces no detection power gain at
  team-level outcomes.
- **Lead AND per-teammate:** Maximum coverage, multiplied
  infrastructure. Wrong tradeoff for current state.

### Decision 6 alternatives

- **Always enabled:** High upstream-bug density (#50779, #24175,
  #24073, #24307, #45329) makes silent breakage likely. Rejected.
- **Always disabled:** Integration provides no value. Rejected.

## Consequences

**Enables:**

- Safe rollout of Agent Teams once feature flag is flipped
- Team-aware tool-call budgeting that maps to the natural unit of
  cumulative work (per-team) without disrupting team flow
- Per-teammate attribution of enforcement-relevant events via the new
  TaskCreated/TaskCompleted hooks
- A clear contract: "we enable Agent Teams when these hooks all
  pass their self-tests" rather than the open-ended "audit before
  enabling" status quo

**Costs:**

- Three new hooks, two amended hooks, one new rule, one new plan
  template value, one new config schema, one feature flag config —
  ~1,200 lines of new harness code plus self-tests, per the plan's
  14 tasks
- Forced `in-process` mode caps team parallelism. Acceptable cost
  for reliability; reversible per machine when Anthropic ships #24175
- Worktree-mandatory adds spawn-time complexity for write-capable
  teammates. Aligned with `rules/orchestrator-pattern.md`'s existing
  parallel-builders discipline
- The deferred-audit flag introduces a new state file
  (`~/.claude/state/audit-pending.<team>`) that needs cleanup on
  abandoned tasks. The 24h auto-clean of `~/.claude/state/`
  (existing behavior in `tool-call-budget.sh`) covers this

**Blocks:**

- None. The plan is structured so each task ships independently
  with self-tests; the integration is reversible task-by-task via
  `git revert`. Until the feature flag is flipped (which is a
  user action after plan completion), the new mechanisms are
  no-ops in solo-session use.

**Reversal cost:**

- Flip `enabled: false` in `~/.claude/local/agent-teams.config.json`
  to disable the integration without removing code. Per-decision
  reversal cost is documented in each decision's plan-file entry
  (`docs/plans/agent-teams-integration.md` Decisions Log).

## Implementation reference

Plan: [`docs/plans/agent-teams-integration.md`](../plans/agent-teams-integration.md)
(14 tasks; ACTIVE 2026-04-27).

Supporting analysis: [`docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`](../reviews/2026-04-27-agent-teams-conflict-analysis.md)
(35-hook × 7-event matrix, 5 hard blockers, 3 soft blockers, false
alarms refuted).

Phase 1 research files: `docs/reviews/agent-teams-research-2026-04-27/`
(four 20-43KB inventories — hooks, agents/skills, rules/architecture,
Anthropic docs).
