# Plan — context-watermark: Opus 5 window entry (recurrence hotfix)

Status: ACTIVE
Mode: code
Owner: interactive session (2026-07-28, operator-directed)
Backlog items absorbed: none (files a new row instead — see Tasks)
acceptance-exempt: yes (harness-internal; the maintainer is the user, demonstrated by
`context-watermark.sh --self-test` per constitution §4)

## Why

`hooks/context-watermark.sh` resolves the denominator for its context-fullness warning
from a HARDCODED model→window allowlist (`_model_window`). `claude-opus-5` was absent, so
the hook fell through to its conservative 200,000 default and reported **"~74% of 200000"**
and then **"~90% of 200000"** during a live session whose real window is 1,000,000 — actual
usage 163.2k / 1.0M = **16%**. The operator caught it directly ("Context is not at 74%")
after the session had already begun premature checkpointing on the strength of the number.

This is the SECOND occurrence of the identical failure. The 2026-07-20 incident
(`docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md`) was the same
bug on `claude-opus-4-8`; that fix added the ASSUMED label and one model family. The label
made staleness HONEST but did nothing to make it RARE — the table necessarily goes stale on
every model launch, silently, with "an operator eventually notices" as the only detector.

Scope discipline: this plan ships ONLY the instance fix. The class fix needs a real design
pass and is filed as a backlog row, not smuggled in here.

## Scope / Tasks

- [ ] W1 — Add `claude-opus-5` / `claude-opus-5-*` to `_model_window`'s 1,000,000 branch,
      with a header note recording the recurrence and its live evidence. Verification: full
      (`--self-test` green, including a new regression scenario).
- [ ] W2 — Add regression scenario T17b asserting bare `claude-opus-5` AND the dated
      snapshot form both resolve to 1000000, never the assumed 200000. RED before W1.
      Verification: full.
- [ ] W3 — File `CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01` in `docs/backlog.md` naming
      the class, why one-family-per-incident is symptom treatment, and three candidate
      structural fixes (suppress the percentage for unknown models / read the window from
      the session's own usage payload / doctor check that REDs when the running model is
      absent from the table). Verification: mechanical (row exists).

## Files to Modify/Create
- `adapters/claude-code/hooks/context-watermark.sh` — W1 + W2
- `docs/backlog.md` — W3
- `docs/plans/context-watermark-opus5-window.md` — this plan

## Assumptions
- Opus 5's context window is 1,000,000 tokens. Evidence: the operator's own client readout,
  "Context window 163.2k / 1.0M (16%)", with Opus 5 the selected model — a LIVE observation
  of the real denominator, which is the strongest evidence class this table accepts (the
  same class used to confirm `claude-opus-4-8` in the 2026-07-20 fix).
- Prefix matching (`claude-opus-5-*`) is the right shape for dated snapshot IDs, consistent
  with every other family in the table; the existing T19 prefix-collision guard already
  covers the risk that a future numeric sibling gets wrongly swallowed.

## Edge Cases
- A future `claude-opus-50` must NOT match `claude-opus-5`'s entry. Covered by the existing
  T19 prefix-collision scenario, which this change does not weaken.
- The `CONTEXT_WATERMARK_WINDOW` env override must still win over the table. Covered by T15.
- An unknown model must still fall through to 200000 AND say ASSUMED — this plan does not
  change the fallback behavior, only the table's contents. Covered by T16.

## Testing Strategy
`bash adapters/claude-code/hooks/context-watermark.sh --self-test`. New scenario T17b is the
oracle: it fails against the pre-change tree (both lookups return empty → assumed 200000) and
passes after. Full suite must stay green — 21/0 including T15/T16/T17/T19 unchanged.

## In-flight scope updates
- 2026-07-28: docs/plans/context-watermark-opus5-window.md — this plan
