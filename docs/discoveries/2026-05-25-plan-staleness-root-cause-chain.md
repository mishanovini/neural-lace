---
title: Plan staleness root-cause chain → mass acceptance-gate waivers
date: 2026-05-25
type: process
status: decided
auto_applied: false
originating_context: plan-lifecycle-redesign design session (2026-05-25); Misha authorized a Mode:design plan after observing recurring acceptance-gate waivers and stale ACTIVE plans
decision_needed: n/a — decided; design captured in docs/plans/plan-lifecycle-redesign.md + docs/decisions/036-plan-lifecycle-mechanical-closure.md
predicted_downstream:
  - docs/plans/plan-lifecycle-redesign.md
  - docs/decisions/036-plan-lifecycle-mechanical-closure.md
  - adapters/claude-code/hooks/plan-reviewer.sh
  - adapters/claude-code/hooks/plan-auto-closure.sh (new — roadmap)
  - adapters/claude-code/scripts/acceptance-scenario-designer.sh (new — roadmap)
  - adapters/claude-code/scripts/close-plan.sh
  - adapters/claude-code/CLAUDE.md
---

## What was discovered

Two recurring symptoms in this harness share a single structural root cause:

1. **Mass acceptance-gate waivers.** `product-acceptance-gate.sh` (Stop hook,
   position 4) blocks session end whenever any `Status: ACTIVE` non-exempt plan
   lacks a PASS artifact for the current `plan_commit_sha`. In practice, ACTIVE
   plans accumulate, each one demands a PASS artifact that was never produced,
   and sessions routinely write per-session waivers
   (`.claude/state/acceptance-waiver-<slug>-*.txt`) just to end. The waiver
   becomes the default escape rather than the rare exception. This is the exact
   "loud is not rare" failure the harness warns about elsewhere: an escape hatch
   that fires every session is no longer an escape hatch — it is the path.

2. **Stale ACTIVE plans.** Plans sit at `Status: ACTIVE` indefinitely. Three
   distinct sub-causes, each previously undiagnosed:
   - **(a) Work shipped, Status never flipped.** The orchestrator's natural
     completion signal ("the last builder returned DONE; commits landed") is
     not plan closure. `Status: COMPLETED` + archival is a separate manual step
     (`close-plan.sh` invoked by hand, or a manual Edit). It is routinely
     forgotten. The plan stays ACTIVE forever even though the work is done.
   - **(b) Plan filed, no work ever started.** A plan is created with
     `Status: ACTIVE` (the template default), then abandoned at birth. Nothing
     records who owns it or when it was due, so nothing ever forces a decision.
   - **(c) Plan filed, work started, then stalled mid-stream.** A blocker
     surfaced and was never surfaced upward; the plan is neither progressing nor
     resolved.

## Why it matters — the causal chain

The two symptoms are the same disease:

```
ROOT: the plan's "closure machine" is defined (if at all) at CLOSURE time,
      not at CREATION time, and closure itself is MANUAL.
   │
   ├─► Acceptance scenarios are a rule-required heading whose SUBSTANCE is
   │   optional and skipped (writing them is friction). plan-reviewer.sh checks
   │   the heading exists; it does not check the scenarios are populated with
   │   concrete steps + expected outputs. So the PASS artifact the gate demands
   │   is frequently UNPRODUCIBLE — there is nothing concrete to run.
   │      └─► product-acceptance-gate.sh blocks → waiver written → repeat.
   │
   ├─► The PASS artifact contract (what commands run, expected outputs, on-disk
   │   location, "done when") is never written down at creation. Closure has no
   │   pre-agreed target, so "are we done?" is re-litigated ad hoc at the end —
   │   which is exactly when context is thinnest and the answer is "just waive."
   │
   ├─► Closure is manual (close-plan.sh by hand / manual Status Edit). The
   │   orchestrator's reward signal fires at "builder returned DONE," which is
   │   UPSTREAM of closure. So plans ship and stay ACTIVE. (sub-cause a)
   │
   └─► No structural commitment (owner, target date) is captured at creation, so
       a filed-but-unworked plan (sub-cause b) or a stalled plan (sub-cause c)
       has nobody and no deadline attached — nothing ever forces the renew /
       abandon / convert decision.
```

Every stale state is the **symptom of a missing structural commitment made at
plan creation**. The waiver flood is the downstream consequence of that missing
commitment colliding with a Stop gate that correctly demands evidence the plan
was never structured to produce.

## Options (considered)

A. **Palliative — surfacers + faster manual closing.** Add a SessionStart
   surfacer listing stale plans; nudge the human to close them. REJECTED by
   Misha: treats the symptom, adds nagging, does not prevent the accumulation.
B. **Auto-defer stale plans.** A hook that flips stale ACTIVE plans to DEFERRED
   automatically. REJECTED by Misha: auto-defer is symptom-masking — it hides
   the broken commitment instead of forcing a decision, and silently buries work.
C. **Loosen the acceptance gate** (make it advisory, or exempt more plans).
   REJECTED implicitly: weakens the harness's core anti-vaporware guarantee to
   paper over a creation-time gap. Wrong layer.
D. **Mechanical structural redesign — make the closure machine an artifact of
   plan CREATION, and make closure automatic.** Mandatory populated acceptance
   scenarios at creation; mandatory PASS-artifact contract at creation; auto-
   closure when the last task verifies AND the contract artifact exists; owner +
   target-date commitments at creation with a commitment-breach decision moment
   (not auto-defer). SELECTED.

## Recommendation

D — the full mechanical redesign. Each stale state is prevented by a structural
commitment captured at creation and enforced by code, not discipline. Detailed in
`docs/decisions/036-plan-lifecycle-mechanical-closure.md` and built per the
roadmap in `docs/plans/plan-lifecycle-redesign.md`.

## Decision

D selected (2026-05-25, Misha-authorized design session). This is NOT auto-applied
— it is a design that produces a Mode:design plan + ADR + implementation roadmap
requiring Misha's review and authorization before any implementation session runs.
The decision recorded here is the diagnosis-and-direction decision; the
irreversible parts (shipping the hooks) are gated on Misha's explicit go.

## Implementation log

- docs/plans/plan-lifecycle-redesign.md — Mode:design plan authored (2026-05-25)
- docs/decisions/036-plan-lifecycle-mechanical-closure.md — ADR authored (2026-05-25)
- adapters/claude-code/CLAUDE.md — "What Done Means" section updated to reflect
  mechanical auto-closure (2026-05-25)
- Implementation hooks/scripts: NOT YET BUILT — roadmap R1–R7 in the plan, gated
  on Misha's authorization.
