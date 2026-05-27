# ADR Numbering Reconciliation — 5-Pattern Parallel Design Effort

**Date:** 2026-05-25
**Author:** reconciliation session (mechanical; no design decisions)
**Scope:** ADRs 036–042 produced by four design sessions that ran in parallel in one shared working tree on 2026-05-25.

## TL;DR

**No renumbering was required.** The on-disk ADR numbers are already collision-free,
contiguous after the last committed ADR (035), index-consistent in `docs/DECISIONS.md`,
and every cross-reference already resolves to the correct number. The transient
number collision the parallel sessions risked was **pre-resolved by the dispatch
(Pattern 5) session**, which renumbered its own ADRs 037/038 → 041/042 before writing
(recorded in `SCRATCHPAD.md`). This ledger records the verified state and the
identity mapping; it documents one deliberately-declined cosmetic reorder.

## Inventory

| # | File | Pattern | Title (short) | Git state | Status field |
|---|------|---------|---------------|-----------|--------------|
| 035 | `035-diagnostic-first-protocol.md` | (prior) | Diagnostic-First Protocol | committed (pre-effort) | Active |
| 036 | `036-plan-lifecycle-mechanical-closure.md` | 1 | Plan-lifecycle mechanical closure | **committed @ `03a7d2d`** | Proposed |
| 037 | `037-file-lifecycle-session-artifacts.md` | 3 | File-lifecycle policy for session artifacts | untracked | Proposed |
| 038 | `038-pending-items-marker-convention.md` | 3 | Pending-items marker + auto-extraction | untracked | Proposed |
| 039 | `039-conv-tree-reconciliation-over-interception.md` | 5 | Conv-tree reconciliation over interception | untracked | Proposed |
| 040 | `040-session-resilience-three-layer-model.md` | 4 | Session-resilience three-layer model | untracked | Proposed |
| 041 | `041-dispatch-mode-autodetect-signal.md` | 5 | Dispatch-mode auto-detect signal | untracked | Proposed |
| 042 | `042-ntfy-out-of-band-notification.md` | 5 | ntfy out-of-band notification | untracked | Proposed |

Seven new ADRs across four patterns (036 committed @ `03a7d2d`; 037–042 untracked).
Pattern 2 produced no new ADR (it was roadmap-sequencing work, committed @ `5eecd69`).

## Canonical numbering decision (identity mapping — no file moves)

| Old number | New (canonical) number | Action |
|------------|------------------------|--------|
| 036 | 036 | none (committed; stays) |
| 037 | 037 | none |
| 038 | 038 | none |
| 039 | 039 | none |
| 040 | 040 | none |
| 041 | 041 | none |
| 042 | 042 | none |

**Every old number equals its canonical number. Zero `git mv` / `mv` operations performed.**

### Why no renumber

The task's reconciliation goal — *no collisions, contiguous after the last committed
ADR, index consistent, cross-references resolve* — is **already fully satisfied on disk**:

1. **No duplicate numbers.** 035→042 are each used exactly once.
2. **Contiguous.** 036 (last committed) is followed by 037, 038, 039, 040, 041, 042 with no gaps.
3. **Index matches.** `docs/DECISIONS.md` rows 035–042 each link to the correctly-named file; `decisions-index-gate.sh --self-test` passes.
4. **Cross-references resolve.** Every `ADR-NNN` / `decisions/NNN-` reference across `docs/` (ADR bodies, the three discoveries, the four Mode:design plans, the upstream-issue proposal) points to the correct current number. Verified by `rg` sweep (see Verification below).

The dispatch (Pattern 5) session, writing last into the shared tree, observed the
other sessions' files and renumbered its own 037/038 → 041/042 to avoid the clash —
so the collision never reached disk.

### Declined cosmetic reorder (039 ↔ 040)

A strict *ascending-pattern-number* ordering (1, 3, 4, 5) would place Pattern 4
(session-resilience) before Pattern 5 (dispatch). The current sequence interleaves
them: 039 is Pattern 5, 040 is Pattern 4. A pattern-strict ordering would swap:

- `040-session-resilience` → 039
- `039-conv-tree-reconciliation` → 040

**This swap was deliberately NOT performed**, because:

- It is pure cosmetic reordering of arbitrary identifiers; the sequence is already contiguous and collision-free, so it yields **zero correctness benefit**.
- It would require ~30 bidirectional cross-reference edits across design prose — including in-sentence sub-decision references like `ADR 040-a/b/c/d/e` (session-resilience) and the dispatch plan/discovery/proposal references to `039`/`041`/`042`. Swapping two live numbers is error-prone, and a single wrong-direction edit would corrupt a design record.
- ADR numbers are conventionally append/collision-resolved order, not topic-grouped; topic grouping is what the index and titles provide. The dispatch session already committed its intent to 039/041/042 in three referencing documents.

This is reversible: if strict pattern-grouping is wanted, the swap can be done later
as a dedicated change. It is surfaced here rather than performed silently.

## Verification

- `rg` sweep for `ADR[- ]0(3[6-9]|4[0-2])` and `decisions/0NN-` across `docs/` + `src/`: every reference resolves to the correct current number. No dead links, no number pointing at the wrong content.
- `docs/DECISIONS.md`: rows 035–042 present, contiguous, no duplicates, links valid.
- `decisions-index-gate.sh --self-test`: **OK**.
- `plan-reviewer.sh` on the four Mode:design plans:
  - `plan-lifecycle-redesign.md` (committed): **no findings**.
  - `session-resilience-redesign.md`: **no findings**.
  - `dispatch-coordination-redesign.md`: pre-existing structural findings (missing `## Walking Skeleton`; two `Verification: review` typos that should be `full`/`mechanical`; Task B2 missing integration sub-blocks). **NOT ADR-cross-reference issues** — unrelated to numbering.
  - `file-lifecycle-redesign.md`: pre-existing structural findings (Tasks R4/R5 missing integration sub-blocks). **NOT ADR-cross-reference issues** — unrelated to numbering.

The plan-reviewer findings are authoring issues owned by the originating design
sessions; they are out of scope for a mechanical ADR-numbering reconciliation
(no design changes were made to resolve them).

## Commit scope (Part 1 PR)

**Included** (clean, finding-free design-record artifacts):
- ADRs 037, 038, 039, 040, 041, 042
- `docs/DECISIONS.md` (index rows for 037–042 — authored by the parallel sessions, previously uncommitted)
- Discoveries: `2026-05-25-dispatch-coordination-debug.md`, `2026-05-25-file-lifecycle-root-cause-chain.md`, `2026-05-25-session-resilience-terminal-death-catalog.md`
- Proposal: `anthropics-claude-code-parent-wake-issue.md`
- This ledger

**Excluded** (with reasons):
- The three Mode:design plans (`dispatch-coordination-redesign.md`, `file-lifecycle-redesign.md`, `session-resilience-redesign.md`) — they are the originating sessions' execution-scaffolding deliverables, are `Status: ACTIVE`/`DRAFT` gated on Misha's review, and two of three carry pre-existing `plan-reviewer.sh` findings that staging would surface (and that are not this session's to fix). They remain in the working tree for their owning sessions to land after review + finding fixes. ADR prose references to these plans are not "dead links" — the files exist on disk and resolve once landed.
- `neural-lace/conversation-tree-ui/scripts/add-pending-items.js` and `backfill-from-sessions.js` — conv-tree-ui application scratch scripts (ADR 038 names `add-pending-items.js` as a throwaway to be retired once the extraction hook ships). Unrelated to ADR reconciliation; left untracked.

## Harness observations

- The collision was avoided only because the last-writing session manually checked the others' numbers and renumbered itself. Four sessions sharing one working tree with no number-allocation primitive is the structural cause — see the Part 2 worktree-per-session guidance produced alongside this ledger.
