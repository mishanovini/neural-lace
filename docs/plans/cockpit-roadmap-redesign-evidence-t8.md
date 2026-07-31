# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 8

Task: 8. UI polish absorbed (Verification: full, rung 3)
Builder: plan-phase-builder (sonnet), commit 57fa78a (build/roadmap-t8) → master 9f68fac
(union-resolved cockpit.selftest + plan conflicts). PARTIAL by design: 4/5 items done;
item 5 (My-To-Do pane retirement per A10) explicitly BLOCKED on task 4 landing (removing
the pane now would strand live operator to-dos with zero UI — functional regression).
Composed on master: cockpit 205/0, server 172/0 (168+S63b-e), derive-lib 57/0. DEPLOYED
(server restarted post-landing, health ok). Gates: pending.

## Builder-reported evidence (gates re-derive)
- cockpit.selftest 158/0 in-worktree (139+19 T8-*); server 169/0 (165+4 S63b-e). All new
  assertions RED pre-fix (git-stash bisection for data-flow; live-browser measurement for
  the two CSS bugs).
- Livesmoke (real server :7834, real registry/backlog/operator-todo, browser automation):
  resize via keyboard equivalents with exact px deltas, persists across real reload
  (localStorage); backlog rows collapsed by default (0px detail height) → expand with
  Schedule/Demote/Fold/Wontfix; real 501-char task descriptions render on the 18-task ask;
  zero Artifacts UI with 304 real artifacts server-side.
- TWO live-browser-caught bugs fixed mid-build (static selftests missed both): (1) resize
  baseline measured while tab hidden → jump on first use (re-measure per interaction);
  (2) .backlog-row-detail{display:flex} beat UA details:not([open]) collapse (the
  documented [hidden]-override footgun class) → :not([open]) override, both pinned.

## Rung-3 articulation (builder-authored, condensed)
**Spec meaning:** ship the 4 absorbed operator items + retire My-To-Do per A10/task4.
**Edge cases covered:** long descriptions (500-char server clamp + client expand); missing
description renders nothing; resize extremes (clamped, min-height floors); hidden-tab-at-
load measurement; the [hidden]-override footgun; this plan's own oversized task text
(4485/4846 chars measured) vs payload-schema's 2000-char cap.
**Edge cases NOT covered:** touch-gesture specifics beyond generic Pointer Events (no real
touch hardware).
**Assumptions:** the cockpit-v2 Task 6 schema carve-out sufficed, only the producer needed
wiring (confirmed via direct schema testing).

## Deferral record (item 5)
My-To-Do retirement NOT shipped: task 4 (Inbox "My items" section = the replacement
destination) had not landed at build time (now in flight). Orchestrator sequence: T4 lands
→ micro-task retires #todoSection/web/todo.js → checkbox flips. Plan In-flight entries
carry the reconciliation.

## Gate results
### task-verifier (opus): INCOMPLETE conf 9 (4/5) → retirement landed → FINAL RE-VERIFY PASS conf 9 — 13/13 live checks incl. real POST /api/todo toggle round-trip; dead-splitter falsification survived; count-exclusion proven by-construction (adversarial open-item probe); suites 251/173/23. Flipped on dual-gate authorization.
### comprehension-reviewer (opus): PASS conf 8 — articulation faithful (all covered edges grounded incl. 500/501 boundary, quota-degradation, textContent escaping; deferral ruled genuine hard dependency, not convenience). Flip authorized from comprehension side, subject to item-5 completion.
