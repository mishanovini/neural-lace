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
### task-verifier: pending
### comprehension-reviewer: pending
