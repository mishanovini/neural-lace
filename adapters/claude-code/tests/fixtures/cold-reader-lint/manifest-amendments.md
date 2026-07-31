# cold-reader-lint manifest-amendments fragment (operator directive
# 2026-07-07, constitution §3 amendment 53d3bee "the cold-reader bar")

Builder: build/cold-reader-lint. Per Wave-O serialization rules (specs-o
§O.0.1) this builder never edits `manifest.json` directly — the
orchestrator applies these amendments. Schema: `schemas/manifest.schema.json`.

Both entries below are documentation-only `honest_status` amendments — the
new behavior is WARN-only (never blocks, per the directive's D5 posture: no
new blocking gates), so NEITHER entry's `blocking`/`kind`/`wired_template`
flags change. No new manifest entry is created (mirrors task F.L's own
precedent: FUNCTIONAL-LINK, the WARN this cold-reader-lint check follows,
never got its own manifest id either — it is documented in
stop-verdict-dispatcher.sh's own header comment, the same place this
amendment documents cold-reader-lint).

## Entry 1 — `needs-you-ledger` (id, current manifest.json ~line 928-943): honest_status append

Current entry (verified live on this branch's f81c2d7 baseline):

```json
    {
      "id": "needs-you-ledger",
      "kind": "writer",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": true,
      "jit_triggers": {
        "paths": [],
        "keywords": []
      },
      "blocking": false,
      "budget_class": "none",
      "honest_status": "scripts/needs-you.sh — maintains NEEDS-YOU.md (E.6); called by decision-log flow + digest, not event-wired."
    },
```

Append to `honest_status` (all other fields unchanged):

```
 Cold-reader lint (constitution §3 amendment 53d3bee, operator directive
 2026-07-07): `add --section decision` scores every new entry's --text
 against three zero-session-context checks (background/context, a
 concrete artifact anchor, per-option outcome text — see
 _ny_lint_decision_text) and stores the result as a `lint_warnings` array
 on the item. WARN-only: a stderr notice is printed but `add` NEVER
 blocks (always exits 0 regardless of lint result) — the ledger's
 availability outranks its tidiness. Self-tested (T22-T25).
```

## Entry 2 — `stop-verdict-dispatcher` (id, current manifest.json ~line 1717-1736): honest_status append

Current entry (verified live on this branch's f81c2d7 baseline):

```json
    {
      "id": "stop-verdict-dispatcher",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [
        "stop-verdict-dispatcher.sh"
      ],
      "events": [
        "Stop"
      ],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": {
        "paths": [],
        "keywords": []
      },
      "blocking": true,
      "budget_class": "stop",
      "honest_status": "E.11 batched Stop verdict; invokes work-integrity/session-honesty/bug-persistence in --report mode, aggregates one verdict; replaces their 3 blocking Stop entries at §E.W (Stop 6->4). pin-f: delegates to the gates that validate purpose clauses.",
      "honesty_rationale": "Aggregator; delegates to bug-persistence/work-integrity/session-honesty's own waiver postures (already stated in its honest_status)."
    },
```

Append to `honest_status` (all other fields, including `blocking: true` for
the AGGREGATE gate verdict, unchanged — this new check is a WARN-only
side-channel exactly like the pre-existing FUNCTIONAL-LINK check documented
in the same field, never a contributor to the blocking verdict):

```
 Cold-reader-lint WARN (constitution §3 amendment 53d3bee, operator
 directive 2026-07-07), following FUNCTIONAL-LINK's own precedent
 immediately above it in this same file: scans the final assistant
 message for a §3-format "Decision needed" block and, if it is missing an
 artifact anchor or per-option outcome text, emits ONE ledger_emit warn +
 a stderr notice. WARN-only — never contributes to the block/gap verdict
 above, never participates in cycle-counting/DONE-refusal, never touches
 stdout. Self-tested (scenarios 18-21, mirroring FUNCTIONAL-LINK's own
 14-17).
```

## Fragments NOT included (per §O.0.1-1 "say 'none' explicitly")

- No new manifest `id` is created for either the needs-you.sh lint or the
  dispatcher WARN — both are sub-behaviors of an already-listed entry,
  same precedent as FUNCTIONAL-LINK (task F.L), which also never got its
  own id.
- `doctor-predicate.md`: none — this task adds no new doctor predicate.
- `install-sync.md`: none — no new top-level dir/file class; only edits
  inside already-synced files (`adapters/claude-code/scripts/needs-you.sh`,
  `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`,
  `adapters/claude-code/hooks/lib/observability-derive.sh`,
  `adapters/claude-code/doctrine/observability-full.md`) plus
  `neural-lace/workstreams-ui/web/{app.js,app.css,cockpit.selftest.js}`,
  which is a separate app directory outside the `adapters/claude-code/`
  sync glob (same rationale O.4's own manifest-amendments.md fragment gives
  for that directory).
- `attic-move-list.md` / `template-wiring.md`: none — no file is retired or
  moved, and settings.json.template is untouched (this task adds no new
  hook wiring; `needs-you.sh` and `stop-verdict-dispatcher.sh` are both
  already wired via their existing call sites/Stop entry).

## Interpretation note (per the dispatch's own instruction to record this)

The dispatch text says surfaces "reject entries that cannot fill those [the
three questions]" but also says the ledger is WARN-only / append-honest and
`add` must "never block the add (exit 0 always)". These two clauses are
reconciled as follows, applied consistently across all three surfaces built
in this task:

- **The LEDGER never rejects.** `needs-you.sh add` always stores the entry
  and always exits 0, lint or no lint (per the dispatch's own explicit
  "Never block the add" instruction in point 1).
- **A SURFACE "rejects" only in the sense of rendering a visibly DEGRADED
  card** — a `needs context: <gap list>` line/chip in place of (or
  alongside) the normal three-question anatomy render — never in the
  sense of dropping, hiding, or omitting the entry. `nl needs-me` prints
  every open item unconditionally; the lint-flagged ones additionally get
  the honest gap line. The cockpit Q2 pane renders every card
  unconditionally; the lint-flagged ones additionally get the `needs
  context` chip. Neither surface silently discards an entry it cannot
  fully render as three clean questions — "reject" here means "does not
  dress it up as complete," not "does not show it."
