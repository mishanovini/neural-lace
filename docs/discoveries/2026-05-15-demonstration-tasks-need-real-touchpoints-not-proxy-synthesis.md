---
title: Demonstration-of-interactive-process tasks must not proxy-synthesize human touchpoints
date: 2026-05-15
type: process
status: pending
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

Pending — Misha deferred the rule proposal until the interactive PRD
re-run (Stages A–F) completes, so the proposal is evaluated against a
clean example rather than mid-correction. This discovery holds the
learning so the discovery-surfacer re-raises it next session if it is
not decided inline.

## Implementation log

(empty until decided)
