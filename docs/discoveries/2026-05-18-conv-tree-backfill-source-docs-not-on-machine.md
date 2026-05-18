---
title: Conv-tree rich-details backfill source docs absent on this machine
date: 2026-05-18
type: dependency-surprise
status: decided
auto_applied: true
originating_context: docs/plans/conv-tree-ui-v1.1-ux-interactivity.md (Phase C / item 9 backfill)
decision_needed: n/a — auto-applied (reversible: item-details-set is last-writer-wins/idempotent)
predicted_downstream:
  - neural-lace/conversation-tree-ui/state/backfill-details.js
  - docs/plans/conv-tree-ui-v1.1-ux-interactivity.md
---

## What was discovered

Item 9 said to backfill the ~17 live conv-tree action items with rich
payloads "sourced from the docs in `docs/reviews/` and `docs/plans/`
(TCPA decision-options doc for TCPA cards, Phase 6 plan for ratify,
etc.)". Those referenced docs — `docs/reviews/tcpa-decision-options-2026-05-17`,
`docs/plans/phase-6-preventive-controls.md`, the Phase 7 audit docs —
do NOT exist in any repo under `~/claude-projects` on this machine
(`find ~/claude-projects -name '*tcpa-decision-options*' -o -name
'phase-6-preventive-controls*'` → no matches; neural-lace `docs/reviews/`
has only the dispatch-worktree doc; no phase-6/7/tcpa plans). They are
external Dispatch-conversation artifacts not present here. The conv-tree
state itself carries only short item titles + node titles (no
annotations on these nodes, no backlog context_refs).

## Why it matters

Fabricating "description / options / pros-cons / recommendation" per
item without the source docs would be placeholder content dressed as
sourced — exactly the vaporware item 9 forbids ("not placeholder") and
`~/.claude/rules/vaporware-prevention.md` bans. Honest sourcing is
limited to what the state file verifiably contains.

## Options

A. Ship the backfill MECHANISM + state-grounded payloads (description =
   item text; context = owning branch; links = the docs/* path the item
   text itself embeds, else a branch pointer; blocking_input only when
   unambiguous) + a documented `--enrich <json>` path to layer real
   doc-sourced payloads later. Surface the gap loudly.
B. Block Phase C entirely until the source docs are provided.
C. Fabricate plausible payloads from the codenames. (Rejected — vaporware.)

## Recommendation

A. The mechanism is the reusable deliverable; grounded payloads + the
doc-pointer links give every item real, non-fabricated content and a
pointer to its source; `--enrich` makes the full enrichment a clean,
idempotent follow-up. Reversible (last-writer-wins), so auto-apply.

## Decision

A. Auto-applied: `backfill-details.js` ships with the honesty contract
in its header; 17 grounded payloads emitted (self-test 11/11; live
tree integrity nodes-before==after; idempotent re-run = 0). The deep
doc-sourced enrichment (TCPA 8-card pros/cons, Phase 6 ratification
specifics) is a follow-up gated on the source docs being accessible —
run `node state/backfill-details.js --apply --enrich <doc-sourced.json>`
when they are. Surfaced in the plan completion report + to Misha.

## Implementation log

- neural-lace/conversation-tree-ui/state/backfill-details.js — shipped (commit pending)
- docs/plans/conv-tree-ui-v1.1-ux-interactivity.md — Decisions Log + completion report note the gap
