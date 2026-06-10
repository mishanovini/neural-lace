# Plan: Workstreams-UI residuals — event-sourced text repair + discriminating filters
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Close the two residuals from `docs/reviews/2026-06-09-workstreams-rebuild-residuals.md` and the discovery
"no event-sourced text-repair path" (2026-06-09): (1) the event schema has no way to correct the text of an
existing item or the title of an existing node — 10 items on the launch-sprint tracker node (its `cls-*` items) carry
frozen U+FFFD mojibake (em-dash mangle from the 07:23 ingest) that is user-visible as "COORD � <name>"; (2) the
GUI's Awaiting-me and In-flight filters are non-discriminating (209=209 — every open unchecked item satisfies
both), so the "what's waiting on Misha" pane carries no signal. This plan adds two additive event types
(`item-text-set`, `branch-retitled`), repairs the mojibake through the sole-normative writer (appendEvent —
never hand-editing the canonical JSON), and makes the two filters a signal-carrying partition.

## User-facing Outcome
After this ships, the operator opening the Workstreams GUI sees (a) the launch-sprint tracker items with
correct em-dash text (no � anywhere), and (b) an "Awaiting me" chip that counts only genuine Misha-asks
(decision / question / action_item_for_user) while "In flight" counts work-in-motion items NOT awaiting him —
two different numbers that partition the open set instead of duplicating it. Future text corruptions are
repairable through the event log (no attestation-breaking hand edits needed).

## Scope
- IN: `neural-lace/workstreams-ui/state/schema.js` (two additive event types per ADR-032 §1, no major bump);
  `neural-lace/workstreams-ui/state/reducer.js` (two reducer cases: replace item text / node title, reject
  unknown ids); `neural-lace/workstreams-ui/state/selftest.js` (new property covering validation, reducer
  application, unknown-id rejection, idempotency); `neural-lace/workstreams-ui/web/app.js` (Awaiting-me /
  In-flight predicate partition + consistent rollup badges); this plan file + its evidence directory;
  emission of correction events against the canonical state file (workstreams-coordination repo — committed
  there, not here).
- OUT: schema_version major bump (additions are additive within major 1); any change to store.js /
  attestation / compaction; hand-editing `tree-state.json` (forbidden — sole-normative writer only);
  reconstruction of mojibake strings whose original is not confidently inferable (left as-is, listed);
  the `?`-mangled arrows being corrected are limited to the one confident case in cls-s8 text; adapters/
  hooks (none touched); the GUI server (server.js unchanged).

## Tasks

- [ ] 1. Add `item-text-set` (node_id, item_id, text) and `branch-retitled` (node_id, title) to EVENT_TYPES
  + EVENT_REQUIRED_FIELDS in schema.js, and reducer cases in reducer.js (replace text/title; reject unknown
  node/item ids; retained-not-applied per NFR-2) — Verification: mechanical
- [ ] 2. Extend state/selftest.js with a new property: both events validate, apply (text/title replaced),
  reject unknown ids into snapshot.rejections, and are idempotent on event_id; ALL existing properties stay
  green — Verification: mechanical
- [ ] 3. Emit correction events via the state.js facade against the canonical state file for the 10 mojibake
  items on the launch-sprint tracker node (confident em-dash reconstructions only); jq-verify zero U+FFFD
  remains in the snapshot and verifySnapshotAttested still verifies — Verification: mechanical
- [ ] 4. Repartition the GUI filters in web/app.js: Awaiting-me = open, unanswered, genuine Misha-asks
  (details._category in {decision, question, action_item_for_user} or kind in {decision, question});
  In-flight = open work-in-motion items NOT awaiting him; rollup badges use the same predicates; verify the
  two counts differ on live data — Verification: mechanical
- [ ] 5. Advocate-style runtime check: load the GUI against the live state (DOM-level render via node, or
  puppeteer if available) and confirm corrected text renders without �, the two filter chips show different
  counts, and no console errors; capture evidence — Verification: mechanical

## Files to Modify/Create
- `neural-lace/workstreams-ui/state/schema.js` — add two additive event types + required fields
- `neural-lace/workstreams-ui/state/reducer.js` — add two reducer cases with unknown-id rejection
- `neural-lace/workstreams-ui/state/selftest.js` — new property test for the two events
- `neural-lace/workstreams-ui/web/app.js` — Awaiting-me / In-flight partition + consistent rollups
- `docs/plans/ws-ui-residuals-2026-06-10.md` — this plan
- `docs/plans/ws-ui-residuals-2026-06-10-evidence.md` — evidence blocks
- `docs/plans/ws-ui-residuals-2026-06-10-evidence/` — structured evidence artifacts (*.evidence.json)
- `docs/discoveries/2026-06-09-no-event-sourced-text-repair-path.md` — discovery status flip to implemented
  (only if the file exists on this branch; it is staged-only in the main checkout otherwise — skip then)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The canonical state file resolves via `~/.claude/workstreams-state-path.txt` to
  `~/claude-projects/workstreams-coordination/state/tree-state.json` (verified) and its
  audit log re-derives the cached snapshot byte-identically (verified by dry-run hash comparison:
  sha256 match on 2698 audit events vs cached 1322-node snapshot, attestation verified) — so appendEvent's
  post-compaction re-fold is lossless.
- Each U+FFFD in the 10 item texts replaced a single em-dash (—) per the known 07:23 ingest corruption
  mechanism; context confirms this for all 10 (e.g. "COORD � <name>" → "COORD — <name>").
- Old-code writers re-deriving the snapshot before they pick up the new reducer will skip the unknown
  item-text-set events (forward-tolerance) and the corrections temporarily revert; they self-heal on the
  next append by a new-code writer because the correction events live permanently in the audit log.
- Live data has zero explicit `it.state` values and zero responded/deferred/backlogged open items
  (verified by analysis), so the new partition's counts are driven by kind/_category alone today.

## Edge Cases
- `item-text-set` on an unknown node or item id → rejected into snapshot.rejections, event retained (NFR-2).
- `branch-retitled` on an unknown node id → same rejection path.
- Re-emitting the same correction event (same event_id) → idempotent no-op at the envelope layer.
- An item whose details payload also carried mojibake → none found in current data (details fields were
  re-enriched post-corruption and are clean); corrections target the `text` field only.
- Items with `it.responded` set are excluded from Awaiting-me (answered, awaiting agent confirmation) —
  zero such open items today, so this changes no current count.
- `branch-retitled` replaces the node title but does NOT touch the `opened_at`/alias fields the reducer
  adds at deriveSnapshot time.
- A text correction string that itself fails confident reconstruction is left corrupted and reported.

## Acceptance Scenarios
- Scenario 1 (text repaired): Open the Workstreams GUI against the live canonical state. Navigate to the
  launch-sprint tracker items (e.g. via the All filter). Success: the three COORD items read
  "COORD — <name>" with em-dashes; no � (U+FFFD) appears anywhere in rendered text.
- Scenario 2 (filters discriminate): With the live state loaded, read the chip counts on "Awaiting me" and
  "In flight". Success: the two counts differ, Awaiting-me counts only decision/question/action_item_for_user
  items that are open and unanswered, and Awaiting-me + In-flight partitions (no overlap; their union plus
  blocked/parked/complete accounts for all open items).
- Scenario 3 (no console errors): Loading the GUI page produces no console errors.

## Out-of-scope scenarios
- Live SSE update flow (server push on state change) — unchanged by this plan; covered by prior builds.
- Phone/responsive layout — unchanged; covered by responsive.selftest.js separately.

## Testing Strategy
- Task 1+2: `node neural-lace/workstreams-ui/state/selftest.js` — all properties green including the new one.
- Task 3: jq scan of the canonical snapshot for U+FFFD (must be zero in the corrected items) + node
  verifySnapshotAttested on the on-disk file (must be verified:true).
- Task 4: node-level computation of the two filter predicates against the live snapshot (counts differ,
  partition sanity N+M vs open set).
- Task 5: DOM-level render (jsdom-free: drive the real app.js against the live snapshot via a minimal DOM,
  or puppeteer-core + system Chrome if available) — corrected text renders, chips differ, no console errors.

## Walking Skeleton
The thinnest slice: schema + reducer case for `item-text-set` alone, one selftest assertion, one correction
event emitted for cls-coord-cody, jq-verified. The rest (branch-retitled, remaining 9 items, filter
partition) layers on the proven slice.

## Decisions Log
- Decision: correction scope limited to confident em-dash reconstructions (semantic truth > completeness per
  workstreams-state rule). Tier 1; chosen during planning; alternatives: best-guess all replacements
  (rejected — risks writing false history through the sole-normative writer).
- Decision: Awaiting-me partition keys off details._category first, kind second; plain `action` items
  without a category are work-in-motion (In-flight). Tier 1; matches the dispatch prompt's specification.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): swept; behavior changes (2 event types, reducer semantics, filter partition,
  rollup-badge consistency) all cited in Tasks 1-5 and Files-to-Modify entries.
- S2 (Existing-Code-Claim Verification): swept; schema.js EVENT_TYPES/EVENT_REQUIRED_FIELDS, reducer
  rejection pattern, app.js isWaiting/itemState/applyFilter/projectRollup all read in-session at HEAD 7e765d5.
- S3 (Cross-Section Consistency): swept; "additive, no major bump" consistent across Goal/Scope/Tasks;
  partition semantics identical in Tasks, Edge Cases, Acceptance Scenarios.
- S4 (Numeric-Parameter Sweep): swept for [10 mojibake items, 1322 nodes, 2698 audit events]; consistent.
- S5 (Scope-vs-Analysis Check): swept; all Add/Modify verbs target IN-scope files; canonical-state commit
  explicitly routed to the workstreams-coordination repo (OUT of this repo's scope, named in Scope IN).

## Definition of Done
- [ ] All tasks checked off
- [ ] Selftest green (all properties)
- [ ] Zero U+FFFD in corrected items; attestation verifies
- [ ] Filter counts differ on live data
- [ ] Completion report appended to this plan file
