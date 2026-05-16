---
title: end-user-advocate agent not dispatchable in Dispatch environment
date: 2026-05-15
type: process
status: decided
auto_applied: true
originating_context: docs/plans/conversation-tree-ui.md Phase-4 expert-review gate (design-process demonstration session)
decision_needed: n/a — auto-applied (reversible: self-apply plan-time-advocate checklist + surface gap; no irreversible action)
predicted_downstream:
  - docs/backlog.md (HARNESS-GAP entry — mandated agent not registered)
  - adapters/claude-code/agents/end-user-advocate.md (exists as a file; not in the runtime agent registry)
---

## What was discovered

The harness mandates `end-user-advocate` plan-time review for every plan
(`~/.claude/rules/planning.md` "Mandatory: end-user-advocate review for
every plan"; `~/.claude/rules/acceptance-scenarios.md` Stage 1). The
agent file exists at `adapters/claude-code/agents/end-user-advocate.md`.
But dispatching `subagent_type: "end-user-advocate"` in THIS environment
returned: `Agent type 'end-user-advocate' not found. Available agents:
[... list without end-user-advocate ...]`. The runtime agent registry in
the Dispatch environment does not expose it, despite the rules treating
it as a required plan-time and Stop-hook-gated reviewer.

## Why it matters

The acceptance-loop (Gen 5) is built on `end-user-advocate` being
invokable in both plan-time and runtime modes; `product-acceptance-gate.sh`
(Stop position 4) gates session end on its runtime artifact. If the agent
is not dispatchable in the environment where Dispatch sessions actually
run, the entire acceptance loop is paper-only here — the single biggest
adversarial-observation mechanism the harness advertises silently does
not fire. This is a harness-integrity gap, not a one-off.

## Options

A. Self-apply the plan-time-advocate coverage checklist inline, surface
   the gap honestly in the design package, and log a HARNESS-GAP.
B. Block the design pass until the agent is available (fails the user's
   explicit "drive to completion" directive for an environment defect
   outside this task's scope).
C. Silently skip the advocate review (violates no-silent-skip + the
   acceptance-scenarios rule).

## Recommendation

A — reversible, honors "drive to completion", and no-silent-skip is
respected because the gap is surfaced + logged + the checklist is
self-applied with the substitute clearly marked as a substitute.

## Decision

A. Auto-applied (reversible: the substitute review is documented as a
   substitute; if the agent becomes available the real review can be run
   later without rework). The plan-time-advocate coverage check was
   self-applied; the systems-designer and ux-designer reviews
   independently cross-checked scenario coverage. A HARNESS-GAP entry is
   filed in docs/backlog.md.

## Implementation log

- docs/plans/conversation-tree-ui.md — `### UX Design Review` +
  advocate-coverage self-application note added (commit pending).
- docs/backlog.md — HARNESS-GAP entry added (commit pending).
