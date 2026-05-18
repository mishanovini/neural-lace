# Plan: Conversation Tree UI v1.1 — UX interactivity (items 7–13)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer (Misha) is the live user verifying this session via the running GUI; the conv-tree gate/emitter self-tests + the web-module state self-test + the new reducer/selftest coverage are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal
Items 1–6 (responsive layout etc.) shipped & merged (PR #4, master `6dfbc7e`, plan closed `f32aa53`). Misha kept using the live GUI and surfaced 7 more UX gaps (items 7,8,9,10,12,13; item 11 is v1.2, filed NL-FINDING-011). The throughline: the GUI is now usable at his viewport but the interaction model is thin — state changes vanish with no feedback/undo, action items show only a title (no actionable detail), and there is no way to respond to a decision/question without context-switching to Dispatch. Ship a cohesive UX-interactivity batch as one PR.

## Scope
- IN: `web/app.css`, `web/app.js`, `web/index.html` (animations, undo snackbar, +N badge, rich-details UI, inline-response UI); `state/schema.js` + `state/reducer.js` + `state/selftest.js` (three ADDITIVE event types — `item-details-set`, `action-responded`, `item-unchecked` — within ADR-032 major 1, no bump); a backfill script `state/backfill-details.js` populating the live actions with rich payloads sourced from `docs/reviews/` + `docs/plans/`; `web/responsive.selftest.js` extended with the new UI invariants.
- OUT: ADR-032 MAJOR bump (all three new event types are additive — no required field of an existing event changes; `schema_version` stays 1; conv-tree gates key off the major and are untouched). The Dispatch-side auto-reader (item 11 → NL-FINDING-011, v1.2). The conv-tree gate hooks (`adapters/claude-code/hooks/conversation-tree-*.sh`) — untouched; re-run self-tests only for no-regression.

## Tasks

- [x] 1. Phase A — item 7 (+12,13): list enter/leave slide+fade (~200ms), new-item flash, undo snackbar; toast auto-dismiss 5s→10s; toast manual ✕ that also cancels the pending Undo — Verification: full
  **Prove it works:** 1. Click "mark done" on an action → item slide+fades out; a snackbar "Marked done. Undo?" appears bottom corner. 2. Click Undo within 10s → the item returns (state reverted). 3. Let it sit 10s → snackbar auto-dismisses, change stays. 4. Click the ✕ on the snackbar → it closes immediately AND the Undo is cancelled (item stays done). 5. New item arriving (toggle a filter to re-render) flashes briefly. 6. Same undo affordance on defer / archive / backlog-activate.
  **Wire checks:** `web/index.html` (`#toast` snackbar markup w/ action+✕) → `web/app.css` (`.li` enter/leave keyframes + `.flash` + `.snackbar`) → `web/app.js` (`snackbar(msg,undoFn)`, 10s timer, ✕ cancels undo; mark-done/defer/archive/activate wired to post-then-snackbar with inverse-event undo)
  **Integration points:** preview_eval clicks mark-done, asserts snackbar DOM + Undo reverts via the inverse event; asserts 10000ms timer; asserts ✕ clears timer + undo.
- [x] 2. Phase A — item 8 (cheap): per-pane "+N new" badge in the pane-head when SSE delivers new actions/backlog while that pane isn't the focused tab/scrolled; clears when the user views the pane — Verification: full
  **Prove it works:** 1. Simulate an SSE frame adding an item to actions while focus elsewhere → actions pane-head shows "+1 new". 2. Click/scroll the actions pane → badge clears. 3. No false badge on first load.
  **Wire checks:** `web/index.html` (pane-head badge spans) → `web/app.js` (diff prev-vs-new entry id sets on SSE `state` event, increment per pane, clear on pane focus/scroll) → `web/app.css` (`.new-badge`)
  **Integration points:** preview_eval injects a synthetic state with +1 action, asserts `#actionsNewBadge` text "+1 new", then focus → cleared.
- [x] 3. Phase B — item 9: additive `item-details-set` event (schema+reducer+selftest) + expandable rich-details UI on action/decision/question items — Verification: full
  **Prove it works:** 1. `state/selftest.js` covers `item-details-set` (applies details to the named item; rejects unknown item; idempotent re-set). 2. In the GUI, selecting/expanding an item with details renders a `.li-details` block: description, context, instructions (actions) / options+pros-cons+recommendation (decisions) / question+background (questions), links (clickable). 3. Items without details render exactly as before (no regression). 4. schema_version still 1; conv-tree gates 18/8, emit 17 unchanged.
  **Wire checks:** `state/schema.js` (`EVENT_TYPES`+`EVENT_REQUIRED_FIELDS` add `item-details-set`) → `state/reducer.js` (case sets `it.details`) → `web/app.js` (`renderActions`/ctx render the `.li-details` block) → `web/app.css` (`.li-details`)
  **Integration points:** `node state/selftest.js` (new cases green + existing 14 green); preview_eval expands a details-bearing item, asserts the rendered fields.
- [x] 4. Phase B — item 10: additive `action-responded` event (schema+reducer+selftest) + inline Respond UI + "responded — awaiting confirmation" state + Copy-to-Dispatch — Verification: full
  **Prove it works:** 1. selftest covers `action-responded` (sets `it.responded={text,ts}`; item stays !checked/visible). 2. Decision/question (and "needs input" action) items show a "Respond" button → inline textarea + Submit → POST `action-responded` → item shows "responded — awaiting confirmation" (visible, de-emphasised, NOT concluded). 3. A "Copy to Dispatch →" button appears formatting `[action <id>] <title>\nResponse: <text>` to clipboard. 4. Items without a response unchanged.
  **Wire checks:** `state/schema.js` (add `action-responded`) → `state/reducer.js` (case sets `it.responded`) → `web/app.js` (Respond affordance + submit POST + copyHandoff reuse) → `web/app.css` (`.li.responded`)
  **Integration points:** `node state/selftest.js`; preview_eval submits a response, asserts the responded state + Copy button + clipboard text shape.
- [x] 5. Phase B — additive `item-unchecked` event (schema+reducer+selftest) — the inverse event item 7's Undo of mark-done/answered requires (append-only log has no built-in uncheck) — Verification: full
  **Prove it works:** 1. selftest: `item-unchecked` on a checked item sets `checked=false` (re-surfaces it); rejects on unknown item; reversible round-trip action-done→item-unchecked. 2. Item 7's Undo of "mark done" emits `item-unchecked` and the item returns to the actions list.
  **Wire checks:** `state/schema.js` (add `item-unchecked`) → `state/reducer.js` (case `it.checked=false`) → `web/app.js` (item 7 undo of done/answered posts `item-unchecked`)
  **Integration points:** `node state/selftest.js` round-trip assertion.
- [x] 6. Phase C — backfill: `state/backfill-details.js` emits `item-details-set` for every live open action, content sourced from `docs/reviews/`+`docs/plans/`; each payload = description / context / instructions-or-options / recommendation / single blocking input — Verification: full
  **Prove it works:** 1. Script run against a COPY enumerates the live open actions and emits one `item-details-set` each with non-placeholder, doc-sourced content. 2. After apply, the GUI shows rich details on those items; the existing tree (52 nodes) still renders intact (append-only — node/tree count unchanged, only item.details added). 3. Idempotent (re-running does not duplicate/corrupt).
  **Wire checks:** `state/backfill-details.js` (enumerate live actions → per-item payload from cited docs) → `state/state.js` `appendEvent` → reducer `item-details-set` → GUI `.li-details`
  **Integration points:** run against worktree copy, assert details present + 52 nodes intact + idempotent; the LIVE run is a delivery step (like the server restart) after merge.
- [x] 7. DEC log (schema-additivity rationale) + extend `web/responsive.selftest.js` with the new-UI invariants + full regression sweep — Verification: full
  **Prove it works:** 1. Decisions Log records the ADR-032-additivity decision (3 new event types, no major bump, gates unaffected) + the undo-inverse-event design + the backfill-content-sourcing decision. 2. `web/responsive.selftest.js` extended (snackbar/✕/anim/details/respond invariants) still all-pass. 3. conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17, state/selftest.js (14 + new) all green.
  **Wire checks:** `docs/plans/conv-tree-ui-v1.1-ux-interactivity.md` (Decisions Log) → `web/responsive.selftest.js` (new assertions) → the regression suites
  **Integration points:** re-run all four self-test suites + the extended responsive test.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.css` — list enter/leave + flash keyframes; `.snackbar` w/ action+✕; `.new-badge`; `.li-details`; `.li.responded`.
- `neural-lace/conversation-tree-ui/web/app.js` — snackbar(msg,undoFn)+10s+✕-cancels-undo; per-pane +N-new diffing; rich-details render; inline Respond + Copy-to-Dispatch; undo posts inverse events.
- `neural-lace/conversation-tree-ui/web/index.html` — snackbar markup (action btn + ✕); pane-head new-badge spans.
- `neural-lace/conversation-tree-ui/state/schema.js` — add `item-details-set`, `action-responded`, `item-unchecked` to `EVENT_TYPES` + `EVENT_REQUIRED_FIELDS` (additive, ADR-032 major 1).
- `neural-lace/conversation-tree-ui/state/reducer.js` — three additive reducer cases.
- `neural-lace/conversation-tree-ui/state/selftest.js` — coverage for the three new events + existing 14 stay green.
- `neural-lace/conversation-tree-ui/state/backfill-details.js` — NEW: enumerate live open actions, emit `item-details-set` with doc-sourced rich payloads (idempotent).
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — extend with the new-UI invariants.
- `docs/plans/conv-tree-ui-v1.1-ux-interactivity.md` — this plan; Decisions Log.

## In-flight scope updates
- 2026-05-18: `docs/discoveries/2026-05-18-conv-tree-backfill-source-docs-not-on-machine.md` — discovery-protocol dependency-surprise record (backfill source docs absent on this machine; mechanism+grounded payloads shipped, enrichment deferred). New file (light case, spec-freeze in-flight, not a thaw).
- 2026-05-18: `docs/findings.md` — NL-FINDING-011 appended (item 11, v1.2 Dispatch-side reader, OUT of v1.1) — committed `d3480a1`.

## Assumptions
- ADR-032 §1 + `state/schema.js` header are authoritative: adding a new event type to `EVENT_TYPES` (and its `EVENT_REQUIRED_FIELDS` row) is ADDITIVE — no MAJOR bump — and adding an optional derived field (`details`/`responded`) to an item does not change any required field of an existing event. `schema_version` stays `1`; `conversation-tree-state-gate.sh`/`-stop-gate.sh`/`-emit.sh` key off the major and are unaffected (re-run their self-tests to confirm, not to fix).
- This plan INTENTIONALLY appends events to the live state file (the backfill + future responses) — the v1.1-responsive "state file byte-identical" invariant does NOT apply here; the integrity bar is instead "append-only: existing 52 nodes + tree structure unchanged, only item.details/responded added; reducer derives cleanly; idempotent backfill."
- localStorage remains the UI-pref substrate (consistent with items 1–6 + the prior friction-reflexion decision); no UI pref added here needs cross-device persistence.
- The append-only log has no built-in "uncheck"; item 7's Undo of mark-done/answered requires the new additive `item-unchecked` event (defer-undo reuses `defer-cleared`, archive-undo reuses `re-opened`).

## Edge Cases
- Undo of `backlog-activated` (creates a node): no un-activate event exists; Undo archives the just-created node (visible reversal) + annotates — documented partial; full reversal is out of scope (would need a non-additive change).
- Snackbar ✕ pressed before Undo: must cancel BOTH the auto-dismiss timer AND the pending undo (action stays in post-action state) — item 13 explicit.
- Rapid successive state changes: each gets its own snackbar; only the most recent Undo is offered (older snackbars auto-expire) — no undo-stack in v1.1.
- An item that is both details-bearing AND responded: render details + the responded de-emphasis together; respond does not hide details.
- Backfill run twice: `item-details-set` is last-writer-wins on `it.details` (idempotent — no duplicate items, no corruption); a node/tree count delta after backfill is a FAIL signal.
- SSE +N badge must not fire on the very first frame (no "prev" set yet) — prime silently like the conclude-notification `primed` guard.
- Reduced-motion: keyframes respect `@media (prefers-reduced-motion: reduce)` (no slide; instant) — accessibility, harness UX standard.
- Page-never-scrolls (BF-3) and the responsive breakpoints (items 1–6) must remain intact under the new DOM.

## Testing Strategy
- Phase A/B UI: live preview server (:7744) on a refreshed copy of the real state; preview_eval assertions per task's Integration points at Misha's 960×2160 + a wide viewport.
- Schema/reducer: `node state/selftest.js` — new event coverage added AND the existing 14 must stay green (additive proof). `node --check` all JS.
- Backfill: run against the worktree copy; assert details populated + node/tree integrity (52 nodes unchanged) + idempotency; LIVE backfill is a post-merge delivery step.
- Regression: conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17 (gates untouched, schema major unchanged); extended `web/responsive.selftest.js` all-pass.

## Walking Skeleton
Thinnest end-to-end slice proving the riskiest layer (the additive schema): add ONE event type (`item-unchecked`) to schema + reducer + one selftest case; confirm `node state/selftest.js` shows the new case green AND the existing 14 still green AND `schema_version` still 1 AND conv-tree gate self-tests unchanged. That proves "additive event type, no bump, gates unaffected" before the larger `item-details-set`/`action-responded` + UI layer builds on it.

## Decisions Log

### Decision: three new event types are ADDITIVE (ADR-032 major 1, no bump)
- **Tier:** 2
- **Status:** proceeded with recommendation (governed by ADR-032 §1 + state/schema.js header — explicit: "Adding a new event type to EVENT_TYPES is additive (no bump)")
- **Chosen:** `item-details-set`, `action-responded`, `item-unchecked` added to `EVENT_TYPES`+`EVENT_REQUIRED_FIELDS`; reducer gains three cases setting optional item fields (`details`,`responded`) / flipping `checked`. `schema_version` stays 1.
- **Alternatives:** (a) MAJOR bump (rejected — no required field of an existing event changes; bump would needlessly trip every reader's "schema too new" refuse + the conv-tree gates). (b) Overload existing events (rejected — e.g. re-emitting `action-added` with details would create duplicate-item rejects; semantics-muddying). (c) Store details/responses outside the state file (rejected — the state file is the single file-mediated contract; out-of-band storage breaks the passive-tracker model + Dispatch v1.2 reader).
- **Reasoning:** Additive within-major is exactly the ADR-032-sanctioned evolution path; keeps the frozen contract + all gates intact; the Walking Skeleton proves it before the big build.
- **To reverse:** remove the three enum rows + reducer cases + selftest cases; the optional item fields are simply never set.

### Decision: item 7 Undo uses inverse events; backlog-activate undo is partial
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Undo posts the inverse: mark-done/answered → new `item-unchecked`; defer → existing `defer-cleared`; archive → existing `re-opened`/restore; backlog-activate → archive the just-created node + annotate (visible reversal; the backlog stays activated — full un-activate would need a non-additive change).
- **Alternatives:** deferred server commit (hold the event until the 10s timer expires) — rejected: breaks the optimistic-confirm + symmetric-log contract items 1–6 established, and a closed browser would lose the change silently.
- **Reasoning:** append-only correctness; reuses existing inverse events where they exist; the one partial (backlog-activate) is documented and visibly reverses the user-facing effect.
- **To reverse:** drop the snackbar Undo wiring; state-transition posts as before.

### Decision: backfill content sourced from cited repo docs, idempotent last-writer-wins
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `backfill-details.js` enumerates live open actions and, per item, emits one `item-details-set` whose payload (description/context/instructions-or-options/recommendation/single-blocking-input/links) is sourced from the doc the item already references (`docs/reviews/tcpa-decision-options-2026-05-17`, `docs/plans/phase-6-preventive-controls.md`, Phase 7 audit docs, etc.). `item-details-set` is last-writer-wins on `it.details` → idempotent.
- **Alternatives:** hand-write generic placeholders (rejected — item 9 explicitly requires doc-sourced rich content, not placeholders; placeholder content would fail the substance bar).
- **Reasoning:** the items already name their source docs; sourcing from them yields accurate, non-placeholder payloads; idempotency makes re-running safe.
- **To reverse:** the events are additive; a later `item-details-set` with empty payload (or simply ignoring the field in the UI) neutralises them.

### Decision: backfill source docs absent on this machine — ship mechanism + grounded payloads, enrichment deferred
- **Tier:** 1
- **Status:** proceeded with recommendation — surfaced loudly (friction-reflexion + discovery 2026-05-18-conv-tree-backfill-source-docs-not-on-machine)
- **Chosen:** the docs item 9 names (`docs/reviews/tcpa-decision-options-2026-05-17`, `docs/plans/phase-6-preventive-controls.md`, Phase 7 audit docs) do NOT exist in any repo under `~/claude-projects` (verified). Rather than fabricate "sourced" content (vaporware), `backfill-details.js` grounds each payload ONLY in verifiable state (item text → description; owning branch → context; embedded `docs/*` path → links, else a branch pointer; derived blocking_input where unambiguous; options/recommendation LEFT NULL). A documented `--enrich <json>` path layers real doc-sourced payloads later (idempotent last-writer-wins).
- **Alternatives:** (a) block Phase C until docs provided (rejected — the mechanism + grounded payloads are independently valuable and item 9's mechanism is the deliverable); (b) fabricate from codenames (rejected — vaporware, explicitly banned + item 9 says "not placeholder").
- **Reasoning:** honest non-fabricated content + a pointer to each item's source doc; full enrichment is a clean reversible follow-up when the source docs are accessible.
- **To reverse:** re-run with a richer `--enrich` map; last-writer-wins supersedes.

## Definition of Done
- [x] All 7 tasks task-verified PASS
- [x] Items 7,8,9,10,12,13 demonstrated live at Misha's viewport (960×2160) + wide (1920×1080)
- [x] `state/selftest.js`: existing 14 green + new P15 green (15/15); `schema_version` still 1
- [x] conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17 — no regression (gates untouched)
- [x] Extended `web/responsive.selftest.js` 33/33; items 1–6 responsive behavior intact
- [x] Backfill: live state nodes-before==after + tree intact, 17 details populated, idempotent (re-run=0)
- [x] item 11 filed (NL-FINDING-011)
- [x] One PR merged to neural-lace master; main checkout synced; LIVE backfill run; :7733 restarted on new code
- [x] Completion report appended; SCRATCHPAD regenerated

## Completion Report

### 1. Implementation Summary
Items 7,8,9,10,12,13 shipped across two commits on `conv-tree-ui-v1.1-ux` (`aafbdc7` schema+UI, backfill commit, plan/discovery commit); item 11 filed as NL-FINDING-011. 7/7 plan tasks task-verified PASS.
- **Walking Skeleton first:** 3 ADDITIVE ADR-032 event types (`item-details-set`, `action-responded`, `item-unchecked`) — `schema_version` stays 1, conv-tree gates 18/8/17 unaffected (proven), `state/selftest.js` P15 added (15/15; existing 14 green).
- **Item 7/12/13:** list enter/leave slide+fade (~200ms) + new-arrival flash; undo snackbar on mark-done/answered/defer/archive/activate; 10s timer for undo-bearing (2.6s plain); always-present ✕ that cancels the pending undo (item 13). Reduced-motion honoured. Live-verified: mark-done→snackbar→Undo restores the item; ✕ cancels; defer/archive/activate undo paths wired (archive→re-opened, defer→defer-cleared, activate→archive-new-node documented partial).
- **Item 8:** per-pane "+N new" badge from an SSE id-diff (primed first frame); live-verified +1 appears on a new action and clears on pane look.
- **Item 9:** rich-details disclosure (collapsed default) — description/context/options(+pros-cons)/instructions/recommendation/blocking-input/links. Live-verified expand renders all fields.
- **Item 10:** inline Respond on decisions/questions/blocking-input → `action-responded` → "responded — awaiting confirmation" (visible, de-emphasised, NOT concluded) + "Copy to Dispatch →". Live-verified full flow.
- **Phase C backfill:** `backfill-details.js` (self-test 11/11) emitted 17 `item-details-set` for the live open actions; tree integrity nodes-before==after; idempotent (re-run=0); GUI renders the disclosure on all 17.

`Backlog items absorbed: none`.

### 2. Design Decisions & Plan Deviations
Three Decisions-Log entries: additive-schema (Tier 2), undo-inverse-events (Tier 1, backlog-activate undo is a documented partial), backfill-source-docs-absent (Tier 1). **Deviation surfaced (friction-reflexion + discovery 2026-05-18):** the docs item 9 said to source backfill content from (`tcpa-decision-options-2026-05-17`, `phase-6-preventive-controls.md`, Phase 7 audit docs) do NOT exist in any repo on this machine. I did NOT fabricate "sourced" payloads (vaporware). Shipped: the backfill mechanism + payloads grounded only in verifiable state (item text, owning branch, embedded doc-path links) + a documented `--enrich <json>` path. **The deep doc-sourced enrichment (TCPA 8-card pros/cons, Phase 6 ratification specifics) is a follow-up for when those source docs are accessible** — run `node state/backfill-details.js --apply --enrich <doc-sourced.json>`. This is your call to flag if you want me to chase the source docs from elsewhere.

### 3. Known Issues & Gotchas
- Backfill payloads are state-grounded, not yet doc-enriched (see §2 + the discovery file) — every item has real description/context + a pointer to its source doc; options/recommendation deliberately null (not fabricated).
- backlog-activate Undo is a documented partial: it archives the just-created node (visible reversal); no un-activate event exists (would need a non-additive change).
- Preview screenshot tool still times out on this SSE app (tooling limit; verification is eval-asserted, stronger for behavior). Promise-based evals also time out → verified via sequential synchronous evals.
- item-unchecked undo of an auto-concluded node also posts re-opened; if the SSE frame races, worst case is a transient concluded node the user re-opens manually (reducer stays consistent).

### 4. Manual Steps Required
None for the code. Optional follow-up: provide the source docs (or their location) to run the `--enrich` pass for the deep TCPA/Phase-6 payloads.

### 5. Testing Performed & Recommended
Live headless-browser walk-through (preview :7744 on the real backfilled state) of items 7/8/9/10/12/13 at 960×2160 + 1920×1080; `state/selftest.js` 15/15; `backfill-details.js --self-test` 11/11; `web/responsive.selftest.js` 33/33; conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17; tree-integrity nodes-before==after + idempotent backfill. Recommended: the `--enrich` pass once source docs are accessible; v1.2 Dispatch-side reader (NL-FINDING-011).

### 6. Cost Estimates
Zero ongoing cost — client CSS/JS/HTML + an additive within-major schema extension + a one-shot/idempotent Node backfill script in an existing localhost-only Node-stdlib tool. No new deps, no build step, no external services.
