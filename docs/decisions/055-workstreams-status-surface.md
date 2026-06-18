# 055 — Workstreams UI re-conceived as a shared status surface

**Date:** 2026-06-12
**Status:** Implemented
**Stakeholders:** Misha (operator), AI orchestrator
**Plan:** `docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md` (11/11 tasks verified; 4/4 runtime acceptance scenarios PASS)
**Originating discovery:** `docs/discoveries/2026-06-11-workstreams-ui-status-board-reevaluation.md`

## Context

The Workstreams GUI (né Conversation Tree UI, ADR-031/032/045) had drifted from its stated
purpose. The concept: ONE shared surface where the operator AND the AI orchestrator hold a
reconciled picture of everything in work at every lifecycle stage — thinking → queued →
moving → blocked/waiting → done. What was built: a structure-first tree of how the AI's work
decomposed, with the right panel drifting into auto-derived "waiting" views. Two operator
corrections were load-bearing:

1. **It is a status surface for the whole pipeline, not a decision queue.** "Waiting on the
   operator" is one state among several, not the purpose.
2. **Context-completeness is a hard requirement.** Every item presented to the operator must
   carry enough embedded context to decide with zero memory of past chat. The recurring
   failure — decision options with no explanation of what the options even mean — made the
   tool "useless without it." This is primarily an EMIT-discipline problem, secondarily a
   render problem.

A density critique sharpened the design: any view that renders item chips globally cannot
survive real, lopsided data (one project with dozens of items, "done" cumulatively huge).

## Decision

**Keep the event-sourced foundation; re-conceive the presentation** (Option C of the
discovery). Concretely:

1. **Density principle:** never render all items everywhere at once. COUNTS globally
   (cockpit = one row per project with now/next/waiting/done pills, O(projects)); ITEMS only
   in one bounded slice (the waiting list, or one drilled project's tree).
2. **Five surfaces:** project cockpit (counts, click→drill) · bounded global waiting-on-you
   list · per-project drill tree (breadcrumb return) · editable My-tasks · editable Backlog
   with promote-to-task.
3. **Color = STATUS, icon = KIND.** Neutral gray = structure/idle; amber = needs-you/blocked
   ONLY (the single pop); muted green check = done. Kind (action/decision/question) is icon-
   only. Two ramps + the done semantic; no rainbow.
4. **Operator authoring reuses the existing event vocabulary** (plan correction C1): operator
   items are first-class via `action-added` (+ derived `origin: operator|ai`, persisted at
   creation, never re-derived), `item-text-set`, `reordered`, `backlog-activated` for
   promote. Exactly ONE new event was added: `item-removed [node_id, item_id]`. Additive
   within ADR-032 schema major 1; `origin` is an optional reducer-read field, NOT in
   `EVENT_REQUIRED_FIELDS`.
5. **Lifecycle states are the ones the reducer actually produces** (correction C3): the
   phantom `closed`/`proposed` states were dropped; `shipped` carries the done semantic.
6. **Context-completeness ships as a gate + a contract.**
   - *Gate (render side):* completeness is derived server-side by the sole-normative
     `assembleItemDetails`/`validateItemDetails` (`decision-context-schema.js`) — no parallel
     validator. Context-incomplete decisions/questions render "needs enrichment" with ALL
     resolving buttons suppressed; a contextless choice structurally cannot reach the
     operator as actionable. The validator-unavailable path fails CLOSED.
   - *Contract (emit side):* `workstreams-emit.sh` operator-facing raises carry per-kind
     context payloads as sibling `item-details-set` events validated through the same
     module (valid→normalized; invalid→raw+WARN; absent→honestly detail-less+WARN; NEVER
     blocks the orchestrator's tool call — the Layer-A failure-isolation invariant).
     Documented in `rules/workstreams-state.md` "Context-complete item emission".
7. **All operator authoring is in-surface** (correction C5): the 8 `window.prompt` call
   sites were retired; replies/edits record via inline forms with write-failure revert +
   inline retry (I3) and keyboard operability (I4). One coordinated overlay-dismiss stack
   (I5). Cross-process append correctness rests on `renameSync` atomicity + `event_id`
   idempotency — explicitly NOT a mutex claim (I6).
8. **Backfilling `details` for pre-existing items is out of scope** (fix-forward only): the
   legacy ~120 detail-less items render honestly as context-incomplete.

## Alternatives considered

- **A — Targeted tweaks to the tree-first UI.** Rejected: cheapest, but does not fix the
  metaphor mismatch; the surface would keep answering "how is this structured?" instead of
  "what's happening and what's next?"
- **B — Full rebuild (backend + frontend).** Rejected: throws away a sound, hard-won
  event-sourced substrate (append-only log, attestation, cross-machine sync) that was never
  the problem.
- **Board-primary with tree demoted to a toggle.** Rejected by the operator: the tree's
  parallelization-awareness (where all the action is across projects) is first-class; the
  resolution is counts-globally/items-bounded, which lets cockpit AND tree both be
  first-class without either overflowing.
- **A project×status matrix with item chips in cells.** Rejected on the density critique:
  lopsided real data produces unequal row heights and overflowing cells; a count/heatmap
  matrix remains a viable future alternative under the same no-chips-in-cells principle.
- **New `task-added`/`task-edited`/`item-promoted` events for operator authoring.** Rejected
  at plan-time review (C1): the existing vocabulary already expresses create/edit/reorder/
  promote; a parallel event family would split the model in two.

## Consequences

- Both parties now read/write one model: operator items appear in cockpit counts, the
  relevant project tree, and the AI's view of the state file; AI items appear in the
  operator's editable surfaces. The frame is genuinely shared.
- The context-completeness gate changes the AI's incentive: a decision raised without a
  per-kind payload is born visibly "needs enrichment" and cannot solicit an answer — the
  emit contract is now the only path to an actionable ask.
- Costs accepted: legacy items stay detail-less (fix-forward); background/cloud emit paths
  that don't load `~/.claude/` hooks remain outside the contract (the documented ADR-031
  ceiling); residual UX edges tracked as `WS-UI-FOLLOWUPS-01` in `docs/backlog.md`
  (tree-toggle focus restore, degraded-mode banner, duplicate My-tasks root reconcile,
  cockpit row-proliferation policy).
- The operator's production server picks up the new surfaces on its next relaunch (the
  running process predates the build).

## Refutation criterion

The re-conception is working if, over the following weeks, the operator can answer "what is
the status of everything?" from the cockpit without scrolling a flat list, and no
contextless decision reaches him as actionable. REFUTED by: recurring operator questions
that the surface should have answered (status invisible) or any actionable bare-options ask
observed in the GUI (gate bypassed).
