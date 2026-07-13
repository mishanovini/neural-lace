# NL Overhaul Program — Completion Retro (F.4)

**Date:** 2026-07-13
**Plan:** [docs/plans/nl-overhaul-program-2026-07.md](../plans/nl-overhaul-program-2026-07.md)
**Baseline:** [docs/reviews/nl-overhaul-baseline-2026-07.md](nl-overhaul-baseline-2026-07.md) (B.10, captured 2026-07-02)
**Origin audit:** [docs/reviews/2026-07-01-neural-lace-effectiveness-audit.md](2026-07-01-neural-lace-effectiveness-audit.md)

This is the F.4 retro closing the Great Consolidation (Phases 0–5). It compares the six
B.10 baseline metrics against the post-program state and checks the ADR-058 D7 refutation
criteria.

## ⚠️ Measurement-provenance caveat (read first — honesty §1)

The B.10 baseline was captured on the **laptop** (main checkout `…/dev/…/neural-lace`).
This retro is measured on the **desktop** (main checkout `…/claude-projects/neural-lace`).
- **Metrics 4, 5, 6 are repo-level / live-mirror** — synced from the same `master`, so they
  are machine-independent and the before/after IS valid. These are the program's core
  structural aims.
- **Metrics 1, 2, 3 are machine-local state** (`.claude/state/` counts). The two machines
  are different populations, so their before/after is **NOT a valid comparison**. Current
  desktop values are reported for completeness and flagged. A fully-valid state-effectiveness
  comparison requires re-running metrics 1–3 on the laptop (follow-up, filed).

## The six metrics — before → after

| # | Metric | Baseline (laptop, 07-02) | Now (07-13) | Valid? | Verdict |
|---|---|---|---|---|---|
| 4 | Always-loaded rules-dir bytes | **883,882 B / 61 files** | **10,385 B / 1 file** | ✅ repo-level | **−98.8%** — context diet decisively achieved |
| 5 | Live Stop-chain entries | **22** (post-B.6; 20 pre) | **9** | ✅ live-mirror | **−59%** — gate consolidation; above the ≤6 target (doctor still flags budget-chains 9>6) |
| 6 | Blocking-gate count (manifest `blocking:true`) | doctor 6/6 green; chain 22 | **32 blocking entries; doctor operational** | ✅ repo-level | see note ▼ |
| 1 | Retry-guard downgrades (`unresolved-stop-hooks.log`) | **321** | **0** (no such log on desktop) | ❌ diff machine | non-comparable |
| 2 | Acceptance-waiver files | **12** | **595** (587 project + 8 home) | ❌ diff machine + pollution | non-comparable — see note ▼ |
| 3 | External-monitor alerts (total / acked) | **33 / 0** | **31 / 21** | ❌ diff machine | non-comparable; acking now active |

**Metric 6 note.** 32 manifest entries carry `blocking:true`. The ≤12 "budget" the baseline
references is the per-gate classification defined by the C.1 manifest schema; interpreting 32
against it requires that per-gate definition (not just a raw grep). Reported as-measured; the
Stop-chain reduction (metric 5) is the load-bearing gate-consolidation evidence and is
unambiguous.

**Metric 2 note (a real finding, not an effectiveness signal).** 587 `acceptance-waiver-*.txt`
files in the desktop's project `.claude/state/` is **self-test pollution** — a test path
generating waiver fixtures into real project state without a sandbox, the same class as the
`operator-todo.md` / `unlinked.jsonl` pollution filed this week. It says nothing about program
effectiveness. Filed as a follow-up.

## Refutation-criteria check (ADR 058 D7)

The program's central refutable claim: *a context diet (Wave C) + gate consolidation (Wave D)
reduce the always-loaded doctrine corpus and the Stop-chain length without losing enforcement
integrity.*

- **Not refuted.** Rules-dir fell 98.8% (883,882 → 10,385 B; 61 → 1 file) while doctrine moved
  to JIT-delivered `doctrine/` — the corpus shrank without deleting doctrine. Stop-chain fell
  22 → 9. The harness-doctor (Wave B walking skeleton) is operational and its reds are all
  accounted-for (stale local branches + the one budget-chains item this retro confirms: chain
  is 9, above the ≤6 aspiration — the one place the consolidation target was approached but not
  fully reached).
- **The residual (honest):** Stop-chain at 9 > the ≤6 budget. Gate consolidation delivered the
  bulk of its aim but left the chain 3 over budget — a documented, bounded shortfall, not a
  refutation of the approach.

## Program state at closure

- **46 → 52 checkboxes** with this retro + E.7: Waves A–F complete.
- **E.7 (session-resumer watchdog)** — ADR-061 Phase-1 build merged (`4fd706a` supervisor core,
  `08a3351` reentry-safe heartbeats + health tick, `b682227` scheduled-task registration),
  reviewer-passed, and **armed 2026-07-13** on explicit operator authorization (Phase-2 gate).
  The auto-continue-after-API-error capability the audit's RC-continuity finding called for is
  now live.
- **F.6 (durable sync fix)** — dedicated sync clone shipped; and the sibling
  **master-drift-autocorrection** mechanism (built + shipped 2026-07-13) closes the
  fork-mirror-drift class (PT-FORK-SYNC-NOT-RUNNING-01) end-to-end.

## Follow-ups filed (not blockers to closure)
1. Re-measure baseline metrics 1–3 on the **laptop** for a valid state-effectiveness before/after.
2. Self-test waiver-file pollution (587 `acceptance-waiver-*.txt` in project state) — same
   test-isolation class as the operator-todo/unlinked.jsonl pollution.
3. Stop-chain 9 → ≤6: 3 entries over the consolidation budget (doctor budget-chains).

## Verdict

The Great Consolidation **achieved its core structural aims** (context diet decisive; gate
consolidation substantial) and **is not refuted** by the D7 criteria. The program is complete;
the three follow-ups above are bounded, documented, and tracked — none blocks closure.
