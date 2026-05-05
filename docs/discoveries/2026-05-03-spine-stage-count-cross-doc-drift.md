---
title: Cross-doc drift — 11-stage vs 10-stage reliability spine references diverged
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: phase-1d-b-doctrine-restructure.md T6 cross-doc consistency check
decision_needed: n/a — auto-applied
predicted_downstream:
  - cross-doc consistency checks should be standard at multi-doc-plan completion
  - doctrine-integration v1 outputs (04-gates, 05-implementation, 03-work-sizing, 09-autonomy-ladder)
  - methodology-recommendation alignment in future doctrine work
---

# Cross-doc drift — 11-stage vs 10-stage reliability spine references diverged

## What was discovered

T6 of the doctrine-restructure plan (Phase 1d-B) ran a cross-doc consistency pass over the integrated v1 outputs. The pass surfaced that `04-gates.md` and `05-implementation-process.md` referred to the "11-stage reliability spine" while `03-work-sizing.md` and `09-autonomy-ladder.md` referred to "10-stage." The canonical methodology recommendation specifies 10-stage. The drift originated from a slip in the original plan's task description for the doctrine restructure — two of the four sub-builds inherited the wrong number from the slipped specification.

Without the explicit cross-doc consistency check at T6, the inconsistency would have shipped to the canonical doctrine and propagated into future doctrine references. The check was the only mechanism that surfaced it; the individual builders each produced internally-consistent documents that simply disagreed with each other on a load-bearing number.

## Why it matters

Cross-doc inconsistencies in canonical artifacts erode trust and confuse readers — especially when the inconsistency is a numbered-stage reference that downstream readers will treat as fact. A doctrine that says both "11-stage" and "10-stage" leaves the reader unsure which is authoritative; the resulting confusion cascades into every plan that cites the spine. Without explicit cross-doc consistency checks at multi-doc-plan completion, drift like this persists invisibly.

## Options considered

- **(a) Accept "11-stage" canonically and update 03/09 to match.** Rejected — the methodology recommendation specifies 10-stage; adopting 11-stage requires re-justifying the methodology, not just patching the docs.
- **(b) Standardize on "10-stage" via class-sweep.** Chosen — matches the methodology recommendation, restores doctrine-recommendation alignment, and surfaces every drifted location in one pass.
- **(c) Leave drift for future cleanup.** Rejected — doctrine inconsistency is exactly the kind of low-cost-to-fix-now / high-cost-to-fix-later problem that compounds.

## Recommendation

Option (b). The methodology recommendation is the source of truth; doctrine drift gets corrected toward it, not the other way around.

## Decision

Option (b). 10-stage is the canonical naming; 11-stage references replaced via 5-location class-sweep across `04-gates.md` and `05-implementation-process.md`.

## Implementation log

- 5 edits across `04-gates.md` and `05-implementation-process.md` in the integrated-v1 outputs replaced "11-stage" with "10-stage."
- Cross-doc consistency findings documented in `phase-1d-b-summary.md`.
- Pattern reinforced for future multi-doc plans: an explicit cross-doc consistency check is part of the plan's Definition of Done, not an optional QA pass.
