# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 5

Task: 5. Requests ledger view (Verification: full, rung 3)
Builder: plan-phase-builder (sonnet), commit 06d31b2 (build/roadmap-t5) → master ac461e2;
fragments (server.js mount + index.html script tag) orchestrator-spliced next commit.
DEPLOYED LIVE: /api/requests 200 on :7733 (real asks). Composed suites at landing:
cockpit 170/0 (146+24 T5-*), requests-routes 25/0 (NEW), server 168/0, roadmap-routes 28/0.
Gates: pending.

## Builder-reported evidence (gates re-derive)
- Livesmoke (real browser, fixture registry, temp-applied fragments, reverted before
  commit): Open(2)/Closed(3) split with correct one-liners; full oldest-first timeline on
  promoted request (origin → became → amendment-candidate with working Detach); C6 BOTH
  directions proven in DOM (roadmap side shows "from your request(s)"); #request/missing →
  honest miss banner; filter matched distilled_intent surviving an operator rename (C8).
- Found+fixed real bug: block comment containing "T13-*/PV-*" prematurely closed via
  embedded */ — caught via node --check.

## Rung-3 articulation (builder-authored, condensed)
**Spec meaning:** four sub-bullets built literally: timeline anatomy (classifyRequestState,
oldest-first fold), "became →" #roadmap/<id> cross-arrow with close-on-promote as exit
verb, C8 findability (filter + age-grouped closed), I1 recency, C4 four-states, C9 a11y —
as a NEW parallel view (not an asks.js rewrite) per dispatch file list.
**Edge cases covered:** merged/dismissed/done/promoted precedence (requests-routes.js:
238-254); corrupt registry → empty-but-ok; missing ask-registry verbs → named error never
silent success (:389-402); noise/detached amendments excluded; distilled_intent survives
rename; last_amended_ts honestly empty; zero-item age groups never render empty shells.
**NOT covered:** multi-plan asks show only latest plan_linked as "became"; amendment
event_key correlates by ts (same-second collision risk, documented in header); no live
undo/reattach after Detach (no reverse verb specified upstream); legacy ask-tree remains
visible below the ledger, unconsolidated (task-8 remit note).
**Assumptions:** state-precedence ordering (merged > dismissed > done > promoted > open) is
the builder's documented call (plan names close-on-promote but no ordering vs pre-existing
statuses); detach-amendment verb shape is this task's pin (task 2 owns the file),
reconciled via fragment.

## Gate results
### task-verifier: pending
### comprehension-reviewer: pending
