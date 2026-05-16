---
title: bug-persistence Stop gate structurally false-fires on interactive-intake surface-and-wait turns
date: 2026-05-16
type: process
status: pending
auto_applied: false
originating_context: conversation-tree-ui interactive guided-PRD intake (Stages B/C/D); bug-persistence-gate.sh fired at the end of multiple "surface the stage's question, wait for Misha's relayed answer" turns
decision_needed: How should the bug-persistence Stop gate treat the interactive-intake "surface-and-wait" turn, where making NO durable-docs edit is the correct behavior (the AI surfaces options/questions, the human answers next turn, THEN the artifact is edited)? Options below; recommendation A. Reversible — pick at the next harness-review or inline.
predicted_downstream:
  - adapters/claude-code/hooks/bug-persistence-gate.sh (candidate: recognize an intake/surface-turn signal)
  - ~/.claude/rules/planning.md or a guided-intake rule (candidate: document the PRD Open Questions section as a valid durable target)
  - docs/backlog.md (HARNESS-GAP if mechanized)
---

## What was discovered

During the interactive guided-PRD intake, the cadence is: the AI surfaces
the stage's canonical question + proposed content + flagged ambiguities,
then **ends the turn and waits** for the human's relayed answer; only the
*next* turn edits the PRD. This is the protocol-correct behavior (AI
proposes, user authorizes, THEN the artifact changes — no synthesis).

`bug-persistence-gate.sh` pattern-matches trigger phrases ("flag",
"surface", "gap", "open sub-question", "needs input", "missing") in the
turn's output and BLOCKS the Stop unless `docs/backlog.md` /
`docs/reviews/` / `docs/discoveries/` / `docs/findings.md` was edited in
the same turn. The surface-and-wait turn legitimately edits none of those
(by design — the durable capture is the PRD's `## Open questions`
section, edited *next* turn after the human answers). Result: the gate
fires at the end of essentially every Stage's surface turn (observed at
Stage B-followup, Stage C, Stage D). The "gap" it detects is not an
un-persisted bug — it is the normal intake open-question flow, which IS
being persisted, just one turn later and in `docs/prd.md` (not one of the
four recognized targets).

## Why it matters

It is a recurring structural false-positive, not a one-off. Each
occurrence costs a Stop-hook block + a remediation turn (this very
discovery is one). Left unaddressed it (a) trains the operator to treat
bug-persistence blocks as noise — eroding the gate's signal for the real
case it exists to catch; (b) injects a remediation artifact per Stage
into an otherwise clean intake. The gate is correct in general; the
interaction with the interactive-intake surface-turn pattern is the
defect.

## Options

A. **Teach the gate the PRD is a durable target during intake.** Add
   `docs/prd.md` (and `docs/prd/*.md`) to the recognized
   durable-persistence targets, OR specifically when an active guided
   intake is in progress. Cheap; risk: widens what counts as
   "persisted" — but the PRD genuinely IS durable structured storage.
B. **Recognize a surface-and-wait turn.** A turn that ends by explicitly
   stating a "Concrete blocker (expected): awaiting relayed answer"
   marker is an intake-pause, not an un-persisted-bug turn; the gate
   skips when that marker is present and the prior turn's questions are
   tracked in the PRD's `## Open questions`. More targeted; more
   mechanism to build.
C. **Per-turn waiver.** Operator writes the bug-persistence escape-hatch
   each surface turn. Rejected-leaning: that is exactly the
   "escape-hatch becomes reflexive" erosion the harness fights
   elsewhere ("loud is not rare").
D. **Accept the friction.** Treat each surface turn's remediation as the
   cost of the gate's conservatism. Status quo; not recommended given
   the recurrence.

## Recommendation

**A** as the floor — the PRD is legitimately durable structured storage;
not recognizing it is the actual gap. Optionally **A + B** if the
broadened target proves too permissive in non-intake contexts. NOT C
(escape-hatch erosion). NOT D (recurring, signal-eroding).

## Decision

Pending — surfaced for the post-Stage-F harness reconciliation or an
inline harness-review decision. This discovery is itself the durable
capture that satisfies the gate for this turn (option C applied once,
deliberately, while the structural fix is decided — not as a habit).

## Implementation log

(empty until decided)
