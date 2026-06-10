---
title: Acceptance gate's refused-exemption branch skips the waiver valve
date: 2026-06-09
type: process
status: pending
auto_applied: false
originating_context: First live firing of the 2026-06-09 UI-surface exemption refusal (product-acceptance-gate.sh, master 84ce51f). The workstreams-consolidation plan's exemption was correctly refused, but the session's valid per-session waiver was never consulted — the refusal branch BLOCKs and `continue`s before the waiver check (step 2) runs.
decision_needed: Should the EXEMPT_OK-but-UI-surface refusal fall through to the waiver/artifact checks (treat invalid exemption as NOT_EXEMPT) instead of hard-blocking?
predicted_downstream:
  - adapters/claude-code/hooks/product-acceptance-gate.sh (reorder: refused exemption → fall through to waiver + artifact checks, not immediate BLOCK)
  - self-test scenario: exempt+UI plan WITH fresh valid waiver → exit 0; WITHOUT → exit 2
---

## What was discovered
The new `plan_declares_ui_surface` refusal (added 2026-06-09) blocks inside the `EXEMPT_OK` case
and `continue`s to the next plan, so steps 2 (per-session waiver) and 3 (artifact) never run for
that plan. A session honestly PAUSING mid-rebuild with a substantive waiver stays blocked anyway.
Observed live: this session wrote a valid waiver for `workstreams-consolidation-2026-06-08` and the
gate still blocked Stop.

## Why it matters
The waiver is the documented release valve for "work genuinely incomplete, session pausing honestly"
(git-discipline.md Rule 3). A refusal branch that bypasses it converts every paused UI-plan session
into a hard lock until the plan header is edited — friction that invites header-flipping instead of
honest pauses.

## Options
A. Treat refused exemption as NOT_EXEMPT and fall through to waiver/artifact checks (refusal message
   becomes a stderr notice + the artifact-missing BLOCK text when neither waiver nor artifact exists).
B. Keep hard-block; document "edit the plan header" as the only remediation.

## Recommendation
A — refusal should mean "you don't get the exemption," not "you don't get the waiver valve either."
Same enforcement outcome (no silent exemption), preserves the honest-pause path. One-screen edit +
one self-test scenario.

## Decision
(pending)

## Implementation log
(pending)
