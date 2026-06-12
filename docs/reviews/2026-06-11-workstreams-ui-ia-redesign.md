# Workstreams UI — IA redesign proposal (ux-ia-auditor)

**Date:** 2026-06-11
**Agent:** ux-ia-auditor (app-wide IA redesign, static/code mode — live tree-state.json gitignored, designed against stated data facts + full source)
**North star:** one shared surface where the operator AND the AI orchestrator keep a single reconciled picture (in-progress / next / waiting-on-operator / done); a co-authored frame of reference for two collaborators.
**Pairs with discovery:** `docs/discoveries/2026-06-11-workstreams-ui-status-board-reevaluation.md`

## Headline recommendation
**BOARD-PRIMARY, tree as a "Group by" lens — NOT tree-and-board co-equal.** Co-equal (a 42%/58% draggable split) is what ships today and is the operator's diagnosed problem. Rationale: (1) two collaborators need ONE shared object, not two competing ones; (2) the dominant intent is *status*, so the default view's primary object must be status (information scent); (3) the tree's data is largely derived/hidden (a guessed "Workstream" regex tier, 0/112 details) — a poor *primary* but a fine *lens*. Falsifiable signal to revisit: if the operator finds himself toggling to Tree constantly after shipping.

## Two CRITICAL (severity-4) findings
1. **The detail modal is empty for ~all 112 items.** The rich `details` payload is set only by `item-details-set`, emitted when Dispatch writes a decision *fence*, flushed by a Stop hook that rarely fires on the long-running orchestrator. The one surface where the operator decides/acts is hollow. **Fix:** (a) GUI honest-empty state ("Context not yet sent by Dispatch · [open branch]") — quick; (b) the real fix is a Dispatch **non-Stop flush path** so fences reach the state file mid-loop — pipeline-side, the largest new engineering item.
2. **No operator-authored items exist.** `+ capture` only writes the backlog; every item is AI-emitted. The "shared" surface is one-writes-one-reads, not co-authored — the core concept is not actually built. **Fix:** a `[+ add to-do]` affordance emitting `action-added{actor:"gui"}`; the `actor` field already exists, so it's ~2 additive schema fields.

## The good news (undersold)
The event-sourced backend **already carries the entire status-board substrate**: six lifecycle states (proposed→committed→in-flight→blocked→shipped→closed), `priority-assigned` (P1–P5), `deferred`, `backlogged`, deploy tracking, and per-event `actor` (dispatch|gui). **This is a rendering + framing redesign, not a data rebuild.** ~70% of front-end logic (`itemState`, `isAwaitingMe`, `isMishaAsk`, `applyFilter`, the detail modal, the tree renderer) ports cleanly; 100% of backend untouched. The existing tree renderer moves *inside* the Group-by lens (zero throwaway).

## Proposed board layout
- **Pinned "⚠ Waiting on you" rail** — always visible at top, zero-click (the highest-value question deserves the strongest scent; today it's 1 chip among 9).
- **Lanes:** Now (in flight) · Next (committed/queued) · Recently done (7d). Items from BOTH authors coexist, tagged `👤 You` / `☁ Claude` (from `actor`).
- **Backlog lane** (operator-owned, "eventually") with `[+ add to-do]` living in it — the independent to-do path; NOT coupled to tree selection (the prior-review error explicitly avoided).
- **`Group by:` toggle** (None / Project / Repo / Tree), default **None** (flat lanes). The tree is one value of this facet.
- **Search box** (top-left, across all item text) — the missing escape hatch at 112-items-and-growing.
- Collapse the **9 filter chips → ~4 lanes + a `[filters ▾]` popover** for niche facets (deploy granularity, archived, stale sessions, kind).

## Data-model deltas (additive only)
1. **Operator-authored items first-class** — a well-known operator-owned root (or `freestanding:true` optional field) so `action-added{actor:"gui"}` items have a parent. The one load-bearing change; small (actor already exists).
2. **Operator can place a to-do directly into a lane** — reuse existing lifecycle events (`item-committed`→Next, etc.) + one optional "place in Waiting" flag.
3. Origin chips, priority surfacing = **zero schema work** (already present). Do NOT add a "lane" column — derive lanes from existing state (as `applyFilter` already does).

## Quick wins (ship this week) vs structural project
**Quick wins (S effort, independent):** search box; honest empty-details modal state; origin chips (👤/☁); collapse chips→lanes; surface P1–P5 priority; relabel "Workstream"→"Theme (auto-grouped)" + pin "Waiting on you".
**Structural project (multi-day):** board-primary re-layout; operator-authored items (+the ~2 schema fields); the Dispatch-side empty-details flush fix (the biggest lever on whether the shared frame is ever truly populated).

## Other findings
- "Workstream" tier is a regex guess (`WS_THEMES`) dressed as structure → demote to an opt-in "Theme (auto)" lens (sev 2).
- No search (sev 3). 9 flat facets > glance limit (sev 2).
- "In flight" vs "Awaiting me" were non-discriminating until a 2026-06-10 fix.

## Open questions for the operator (the 5 decisions)
1. **Lane vocabulary** — confirm the 5 labels (Waiting on you / Now / Next / Recently done / Backlog). Auditor recommends pinning "Waiting on you" as a *rail above* the lanes, not a peer lane.
2. **Operator to-do default lane** — land new to-dos in Now (lean), Next, or ask each time?
3. **To-do list scope** — one global operator lane (modeled) or per-project? (changes the schema parent)
4. **Empty-details pipeline fix** — in scope for this redesign, or a separate Dispatch-emit workstream? (GUI honest-empty state ships regardless)
5. **Tree-as-lens default** — `Group by: None` (flat, lean) or `Project`?

## Status
Proposal delivered; pending operator's 5 answers. No code changed. ux-ia-auditor agent id a804f3fb47c82355e (resumable for deeper iteration).
