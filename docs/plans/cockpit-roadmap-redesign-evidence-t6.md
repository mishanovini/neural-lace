# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 6

Task: 6. Badge law + badge-storm fix (Verification: full, rung 3)
Builder: plan-phase-builder (sonnet), commit cdff743 (build/roadmap-t6) → master f07a762.
Composed cockpit.selftest 146/0 on master. Gates: pending.

## Builder-reported evidence (gates re-derive)
- cockpit.selftest 146/0 (139 + T6-0..T6-5, T13-26, T16-7); server.selftest 165/0 untouched.
- RED first: pre-fix implementation swapped in via anchors → 139/7 for the right reasons.
- Fixture proofs: 718 identical unmatched_dispatch → ONE chip "unmatched_dispatch ×718"
  with 718-line drill-down; 4 mixed classes out-of-order → re-sorted per auditor.js:27-36
  precedence table; zero/undefined → null, no container (was always-empty span).
- Renderer executed for real: BADGE-LAW-RENDER-BEGIN/END extraction into vm-sandboxed
  fake DOM (no jsdom dep) — behavior, not source-regex.

## Rung-3 articulation (builder-authored, condensed)
**Spec meaning:** one-chip-per-class cap at the renderer (plan 279-282 + proposal §5/D4),
defense-in-depth vs the shipped auditor age-bound fix (0cb4f9b).
**Edge cases covered:** 718-identical; mixed out-of-order; zero/undefined; legacy badge
without divergence_class (groups under 'drift'); unranked/future class (sorts last, never
crashes).
**NOT covered:** proposal's "bookkeeping classes render ONLY in Harness Health" — needs
app.js (task 1/3 shell scope), not attempted; deferred (candidate task-9 or follow-up).
**Assumptions:** counted-labeled shows ×N even at N=1 (roll-up precedent); precedence =
auditor.js divergence-class table order (the authoritative source for THIS surface;
roadmap stalled-reason precedence is a different mechanism); plan-prose "suppress
bookkeeping" vs dispatch fixture "cap ×718" resolved as cap-not-suppress (suppression
needs out-of-scope files) — ADJUDICATION FOR GATES TO CHECK.

## Gate results
### task-verifier: pending (opus, in flight)
### comprehension-reviewer (opus): FAIL conf 5 — 1 gap: drill-down eagerly renders one hidden div per badge (718 in fixture), unsurfaced reliance on upstream auditor age-bound; 'invulnerable by construction' overclaims. CODE fix chosen (cap + '+K more'): T6 builder resumed. Adjudication (cap-not-suppress) ruled SOUND, not scope-laundering.

## Fix round (3c45d62, builder 4185d74)

Suppression per verifier mandate: BOOKKEEPING_DIVERGENCE_CLASSES (unmatched_dispatch,
orphaned_waiting_item, unknown_provenance — auditor.js table) filtered BEFORE grouping →
zero board chips; log_ahead_task_not_flipped stays belief-changing/on-board; unranked
default-visible (safe direction). Harness Health bookkeeping-divergence count via existing
/api/diagnostics/drift aggregate (BOOKKEEPING-DIAG block, app.js renderDiagnostics).
Drill-down capped DRILL_DOWN_LINE_CAP=50 + "+K more". RED-proven: pre-fix code → 170/9 on
exactly the new scenarios. Composed on master: cockpit 186/0, server 168/0.

### Revised articulation (fix round)
**Spec meaning:** proposal §5 literal — belief-changing classes get the one-chip cap;
bookkeeping classes render nowhere on the board, counted in Harness Health. Acceptance
Scenario 4 is the oracle (700 bookkeeping → 0 board chips).
**Edge cases covered:** pure-bookkeeping fixture (0 chips); mixed → only belief-changing
chip; multiple belief-changing classes (precedence sorts); drill-down cap ceiling vs
below-cap (no phantom "+more"); cross-file class-list duplication drift (T6H-4 guard).
**Edge cases NOT covered:** real click-through from the Harness Health count to a detail
view (proposal copy has "→"; a dead arrow would violate the no-fake-affordance convention
— flagged, not silently dropped).
**Assumptions:** the classification (1 belief-changing vs 3 bookkeeping) is a decide-and-go
reading of §5 + the auditor's own table, not an enumerated list in the proposal —
reversible. The drill-down body's own DOM footprint is capped at 51 elements regardless of
upstream count — that is the ONLY invulnerable-by-construction claim made; it does not
extend to the rest of the function or other surfaces.
