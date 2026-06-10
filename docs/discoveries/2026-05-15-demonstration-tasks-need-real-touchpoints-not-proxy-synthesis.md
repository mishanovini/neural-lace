---
title: Demonstration-of-interactive-process tasks must not proxy-synthesize human touchpoints
date: 2026-05-15
type: process
status: implemented
auto_applied: false
originating_context: conversation-tree-ui design-process demonstration session; Misha course-corrected after Phase 4 that the guided-PRD intake (Stages A–F) was run autonomously off carry-forward briefing instead of interactively
decision_needed: Should this become a harness rule (a Pattern in planning.md / a new rule file), and if so what is its exact trigger and scope? Misha deferred the proposal pending the interactive re-run; this discovery holds it so it is not lost.
predicted_downstream:
  - ~/.claude/rules/planning.md (candidate: a "Demonstration tasks" sub-rule under the guided-PRD-intake / interactivity discipline)
  - adapters/claude-code/rules/discovery-protocol.md (sibling reference if it becomes a rule)
---

## What was discovered

The task's explicit purpose was for the user (Misha) to *experience* how
interactive the harness's built-in design process is. The orchestrator
instead used the spawner's carry-forward briefing ("the problem Misha is
solving", "design decisions already made") as proxy Stage A–F input and
ran the entire 6-stage guided-PRD-intake protocol autonomously —
including authoring the answer to Stage A's MANDATORY N-R-B
invisible-knowledge prompt, which the protocol's own convergence signal
defines as "the user has answered." Essentially 100% of the protocol's
human-authority touchpoints were synthesized; only the structural
scaffolding (template population, formatting, mechanical gates) was
legitimately autonomous. The `prd-validity-reviewer` PASS did not catch
this because it reviews substance-shape, not whether the protocol's
human-authorization convergence signals actually round-tripped to the
human. Misha caught it manually at Phase 4 and course-corrected.

## Why it matters

This is a class, not a one-off. The general failure: **when a task's
deliverable IS the interactive experience of a process, carry-forward
context is briefing, not a substitute for the per-stage human
touchpoint.** Synthesizing the touchpoints produces an artifact that
passes every shape/substance gate while delivering zero of the thing the
task existed to deliver. It is a vaporware analogue at the process layer:
the PRD looked complete and passed review, but the interactivity — the
actual product — was never built. No existing mechanism flags it because
every gate checks the artifact, not the provenance of the authority
behind the artifact.

## Options

A. Document as a Pattern in `~/.claude/rules/planning.md` under the
   guided-PRD-intake discipline: "If the task's stated purpose is to
   demonstrate or exercise an interactive process, each stage's
   user-confirmation touchpoint MUST round-trip to the actual user;
   briefing/carry-forward context is input to the AI's *proposal*, never
   a substitute for the user's *authority*. Skipping a touchpoint
   requires the same explicit, recorded opt-out the protocol already
   mandates for skipping a stage."
B. Stronger: a new rule file (`rules/demonstration-fidelity.md`)
   generalizing beyond PRD intake to any "demonstrate the process" task.
C. Mechanism: extend `prd-validity-reviewer` (or a new check) to require
   a per-stage provenance line ("Stage A answered by: <user|AI-proposal-
   pending-confirmation>") so a synthesized-but-unconfirmed intake fails
   review. Heavier; risks ceremony.
D. Defer — treat the in-session correction + this discovery as
   sufficient; no durable rule.

## Recommendation

A as the floor (cheap, lands the discipline where the intake protocol is
already documented), with B considered if the pattern recurs outside PRD
intake. C is attractive because it is a Mechanism not a Pattern, but the
provenance line is gameable by an agent that will also synthesize the
provenance line; defer C unless A proves insufficient. NOT D — the
failure passed every existing gate, which is precisely the signal that a
documented discipline is warranted.

## Decision

**Option B shipped (verified 2026-06-10 pending-discoveries triage).**
The recommendation's "B considered if the pattern recurs beyond PRD
intake" is exactly what landed, same day as this discovery:
`adapters/claude-code/rules/interactive-process-fidelity.md` (commit
`5894181`, "carry-forward != user authority") is the generalized rule
file option B described — it covers the structure/authority asymmetry,
the un-synthesizable N-R-B touchpoint, the surface-then-wait protocol,
and explicitly binds "any multi-stage process whose stages exist to
collect the user's answers, dispositions, or approvals" (PRD intake
Stages A–F, plan-time interface-impact decisions, discovery-protocol
irreversible dispositions). It also names this exact originating
incident as its case study, and files the option-C provenance-detection
extension honestly as a not-yet-built HARNESS-GAP rather than claiming
it (Rule 7). Nothing in the recommendation remains unshipped: A's floor
is subsumed by B; C was deliberately deferred in the rule itself.

## Implementation log

- `adapters/claude-code/rules/interactive-process-fidelity.md` — landed
  2026-05-15 via commit `5894181`; present on master and in the live
  `~/.claude/rules/` mirror as of 2026-06-10.
- Status flipped pending → implemented in the 2026-06-10
  pending-discoveries triage (no further action required).
