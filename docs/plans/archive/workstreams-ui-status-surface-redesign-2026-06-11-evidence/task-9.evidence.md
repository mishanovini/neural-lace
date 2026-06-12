# Task 9 Evidence — Emit discipline: context payloads on raised decisions/questions

Plan: `docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md` Task 9 (Verification: full)
Branch: `worker-ws-emit2` (salvage of orphaned WIP `7094ec3`)
Builder: plan-phase-builder (PARALLEL mode — task-verifier NOT invoked per dispatch protocol)
Date: 2026-06-12

## 1. Gap diagnosis (file:line — pre-WIP baseline `b13f7dd`)

Which emit surfaces created decision/question/operator-facing-action items WITHOUT an
accompanying `item-details-set`? Audited every harness emitter of
`decision-raised`/`question-raised`/`action-added` (9 files matched the grep):

| Surface | Pre-WIP behavior | Verdict |
|---|---|---|
| `workstreams-emit.sh --emit-item` (`b13f7dd` blob lines 1472–1513) | `.details` optional; extracted at :1482 and emitted RAW with zero validation; **no WARN when absent** — the primary orchestrator raise surface produced contextless items silently. This is the source of the live ~124-item near-all-empty-`details` state. | **GAP — closed this task** |
| `workstreams-emit.sh --emit-details` (`b13f7dd` :1515–1536) | event_id derived from (node\|item) ONLY (:1527; same at :1497 for the `--emit-item` sibling) → a SECOND emit with REVISED content produced the SAME event_id → `appendEvent` deduped → **enrichment silently never applied**. The enrichment loop the Task-8 "needs enrichment" gate depends on was structurally broken. | **GAP — closed this task** |
| `workstreams-emit.sh --on-spawn` `Work-item: new` (`b13f7dd` :540–549; comment :335 — sentinels "do NOT (yet) propagate") | kind event emitted with NO `item-details-set` path at all, even when the spawn prompt carried `Instructions:`/`Recommendation:`/`Links:` sentinels. | **GAP — closed this task** |
| `decision-context-gate.sh` :519–575 | fence path emits sibling `item-details-set` via `fenceToDetails` → `assembleItemDetails` (`decision-context-schema.js:599/584`) — rich by construction (the fence Zod schemas require background + per-kind fields). | NO GAP — untouched ("only if needed": not needed) |
| `workstreams-turn-emit.sh` :553–618 | assembles via `assembleItemDetails`; assembler-null ⇒ item DROPPED (:586–587) — never emits an incomplete card. | NO GAP — untouched |
| `workstreams-emit.sh --on-builder-dispatch` (ADR-054) | `details._category:"builder-dispatch"` — outside the operator-ask set by design (noise-control tier). | NO GAP (exempt by design) |
| `lib/workstreams-task-bridge.js` :189–197 | TaskCreate → `action-added` with NO details and NO `_category` (task-list mirror items). | Out of Task 9 declared scope — follow-up below |

## 2. Salvage audit — kept / fixed / added vs the orphaned WIP (`7094ec3`, never verified)

**Audited:** full `git diff b13f7dd..7094ec3` (407 insertions, one file) against the task spec
and against the sole-normative module's actual exports (verified present:
`assembleItemDetails` at `decision-context-schema.js:584`, `validateItemDetails` :570,
`DETAIL_CATEGORIES` :470, `ItemDetailsContentSchema` :507, exports :608–632).

**KEPT (verified correct):**
- Helpers `_resolve_schema_lib` / `_kind_to_category` / `_normalize_item_details` /
  `_assemble_spawn_details` / `_kind_of_item` (current hook ~:646–804). Schema resolution
  mirrors `decision-context-gate.sh` (`DECISION_CONTEXT_SCHEMA` env override); `_kind_of_item`
  honors `CONV_TREE_STATE_PATH` via the shared resolver (`lib/workstreams-state-resolver.sh:59-73`).
- `--emit-item` discipline (~:1807–1855): valid → NORMALIZED payload (`_category`+`surfaced_by`
  stamped by the module); invalid → RAW payload (information-preserving) + audit WARN;
  non-operator `_category` → SKIP passthrough; module unavailable → passthrough + log;
  absent → item still emits + born-context-incomplete WARN. Never blocks (Layer-A writer).
- `--emit-details` (~:1863–1915): category from `._category` else item-kind lookup; same
  validation; CONTENT-HASHED event id restores last-writer-wins (the ST42 fix).
- `--on-spawn` Work-item:new assembly (~:555–578): sentinels → `_assemble_spawn_details` →
  sibling `item-details-set` in the same batch; assembler-null ⇒ born honestly detail-less.
- ST37–ST42 self-tests (~:1467–1560) — they lock exactly the contract.
- The inline same-contract JS floor inside the node snippets is NOT a parallel shell schema:
  it replicates the precedent `workstreams-turn-emit.sh` already ships (:322–349) for
  stripped envs (worktree without zod — this worktree IS one); module normative when loadable.

**FIXED (one defect found):** `_builder_creation_events` comment (~:2027) claimed its
`ev_det` uses the "SAME derivation as --emit-details" — stale after the WIP made
`--emit-details` content-hashed. Behavior is correct (fixed id dedupes Pre/Post/reconciler
re-fires AND cannot clobber a later content-hashed enrichment); comment now says that
honestly. Commit `91fdc6c`.

**ADDED (the WIP's missing half):** the contract documentation the code comments referenced
did not exist. `rules/workstreams-state.md` gains "Context-complete item emission"
(per-kind payload table mapped onto `ItemDetailsContentSchema`, the cold-read bar, the
per-surface table, why-never-block + the GUI-gate composition, the honest fallback-floor
note, Enforcement row, cross-refs); `rules/decision-context.md` gains the emit-side-consumers
cross-ref in its Sole-normative-validator section. Commit `c41aacd`.

## 3. Self-test output (post-fix, both schema paths)

`bash adapters/claude-code/hooks/workstreams-emit.sh --self-test`
— worktree has NO zod ⇒ exercises the inline same-contract floor:

```
self-test: 66 passed, 0 failed
self-test: OK
```

`DECISION_CONTEXT_SCHEMA=<main-checkout>/neural-lace/workstreams-ui/state/decision-context-schema.js \
 bash adapters/claude-code/hooks/workstreams-emit.sh --self-test`
— real sole-normative module loadable ⇒ exercises the module path:

```
PASS: ST37 valid payload -> item-details-set emitted
PASS: ST37b normalized details._category stamped
PASS: ST37c normalized details.surfaced_by stamped
PASS: ST38 invalid payload still lands raw (info-preserving)
PASS: ST38b invalid payload -> schema-FAIL WARN logged
PASS: ST39 payload-less raise still emits the item
PASS: ST39b payload-less raise -> NO item-details-set
PASS: ST39c payload-less raise -> born-context-incomplete WARN logged
PASS: ST40 Work-item:new + sentinels -> item-details-set in spawn batch
PASS: ST40b decision born context-complete (background=Instructions:, recommendation carried)
PASS: ST41 no sentinels -> NO item-details-set (born honestly detail-less)
PASS: ST41b the item itself is still created
PASS: ST42 enrichment revision applies (last-writer-wins restored)
PASS: ST42b two distinct item-details-set events (content-hashed ids)
self-test: 66 passed, 0 failed
self-test: OK
```

(All 66 pass on both runs; ST1–ST36 + BD1–BD10 regressions unchanged-green.)

`node neural-lace/workstreams-ui/state/selftest.js`:

```
21 passed, 0 failed
```

## 4. Live demo transcript (TEMP state file — never the operator's tree)

`CONV_TREE_STATE_PATH=/tmp/tmp.2qsicGVa2F/demo-tree-state.json`, real module via
`DECISION_CONTEXT_SCHEMA`; decision raised WITH a full per-kind payload, then a
question raised with NO payload:

```
--- (1) decision WITH per-kind payload ---            rc=0
--- (2) question with NO payload ---                  rc=0
--- (3) landed events + validation via the sole-normative module ---
event counts: {"branch-opened":1,"decision-raised":1,"item-details-set":1,"question-raised":1}
decision details: _category=decision surfaced_by=workstreams-emit options=2 validateItemDetails.success=true
question details present: NO (born honestly detail-less)
--- (4) audit log ---
emit-item kind=decision item_id=i-demo-dec details validated against the sole-normative context schema (category=decision)
WARN: emit-item kind=question node_id=demo-root item_id=i-demo-q raised WITHOUT a context payload — the item is born
context-incomplete (...). Supply .details per rules/workstreams-state.md "Context-complete item emission".
```

Both prove-it properties hold: payload-bearing raise lands as `decision-raised` +
`item-details-set` whose details validate against the sole-normative schema; payload-less
raise still lands (exit 0, non-blocking) and is honestly detail-less.

## 5. Follow-ups (out of declared Task 9 scope)

- `lib/workstreams-task-bridge.js:189-197` TaskCreate→`action-added` items carry no
  `details`/`_category`; decide whether they should carry a noise-control `_category`
  (like builder-dispatch) so the Task-8 gate treatment is explicit rather than incidental.
- This worktree's `workstreams-ui` has no `node_modules` (zod missing), so default runs
  exercise the inline floor; the main checkout exercises the module. Acceptable per the
  documented graceful-degradation contract, but `npm install` guidance for fresh worktrees
  could be added to the workstreams-ui README.

## Comprehension Articulation

### Task 9 — Spec meaning
Task 9 is the SOURCE half of the plan's context-completeness hard requirement: extend the
harness emit path so that when the orchestrator raises a decision/question/operator-facing
action, the emission can — and prefers to — carry the per-kind context payload (background,
options-with-meaning, recommendation, reply-with…) as an `item-details-set` validated through
the sole-normative `decision-context-schema.js`, so future items are born context-complete
for the GUI's Task-8 render gate; and document that contract durably so every future
orchestrator session knows what a context-complete emission carries. Emission must never
block (Layer-A writer): an absent/invalid payload lands honestly detail-less/raw + WARN.

### Task 9 — Edge cases covered (file:line)
- Invalid payload (fails cold-read bar) → RAW landing, information-preserving, + WARN:
  `workstreams-emit.sh:1824-1826` (ST38/ST38b).
- Payload absent → item still emits, born-context-incomplete WARN: `:1833-1835` (ST39a-c).
- Non-operator `_category` (builder-dispatch tier) → SKIP passthrough: `:727-731` + `:1827-1828`.
- Module/node unavailable (stripped worktree) → same-contract inline floor / passthrough,
  never a crash: `:689`, `:702-728`, `:746` (NOLIB), mirroring `workstreams-turn-emit.sh:322-349`.
- Enrichment revision after a prior details event → content-hashed event id applies
  last-writer-wins; identical re-emit dedupes: `:1845`, `:1908` (ST42/ST42b).
- Work-item:new spawn without sentinels → no assembler output ⇒ NO `item-details-set`,
  item still created: `:756-760` guard + ST41/ST41b.
- Builder-dispatch creation batch keeps FIXED (node|item) `ev_det` so reconciler re-fires
  can never clobber later enrichment: `:2027-2036` (the salvage fix).

### Task 9 — Edge cases NOT covered
- Backfilling the existing ~124 detail-less live items — explicitly OUT per the plan's
  Scope (fix-forward only; source docs unavailable, fabrication barred per UX-3).
- `workstreams-task-bridge.js` TaskCreate mirrors carry no `_category` — out of the
  declared Task 9 file scope; logged as a follow-up above.
- Cloud/Dispatch sessions that load no `~/.claude/` hooks remain outside any emit
  discipline (the rule's accepted blind spot); the contract section documents, not solves it.

### Task 9 — Assumptions
- The reducer treats `item-details-set.details` as forward-tolerant last-writer-wins with
  no interior validation (stated at `decision-context-schema.js:462-468`), so emitting a
  RAW invalid payload cannot corrupt state — the GUI's gate, not the reducer, polices it.
- `appendEvent` dedupes strictly per event_id per file (store contract), making
  content-hashed ids the correct lever for revision-applies / re-fire-dedupes semantics.
- The Task-8 render gate (parallel builder) consumes `validateItemDetails`/
  `assembleItemDetails` from the same module, so "valid here" === "actionable there".
