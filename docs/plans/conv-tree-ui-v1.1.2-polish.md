# Plan: Conversation Tree UI v1.1.2 — polish (items 25–28)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer (Misha) is the live user verifying via the running GUI; conv-tree gate/emitter self-tests + the web-module state self-test + responsive.selftest.js are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal
Items 1–18 shipped & merged (PRs #4/#9/#10, master `301a5b7`). Misha kept live-using the GUI and surfaced 4 polish items (25–28) on EXISTING behavior. Item 28 alone is schema-additive (one new event type + two optional `deferred` fields — SCHEMA_VERSION stays 1, no major bump per ADR-032 §1). Ship as a fast-follow v1.1.2 PR.

## Scope
- IN: `web/app.css`, `web/app.js`, `web/index.html` (filled semantic buttons, no-scroll Details, Respond-only decision/question, Defer popover). `state/schema.js` + `state/reducer.js` (additive `item-backlogged` event + optional local-time `deferred` fields). `state/selftest.js` + `web/responsive.selftest.js` extended.
- OUT: schema MAJOR bump (item 28 is strictly additive — SCHEMA_VERSION stays 1; conv-tree gates key off the major and are untouched, re-run for no-regression only). Dispatch-side reader. Any non-25–28 behavior.

## Tasks

- [x] 1. Item 25: filled semantic button backgrounds (commit=green / caution=amber / util=blue / elevate=purple / destruct=muted-red / neutral=slate) with hover/active/disabled states; reclassify every pane/ctx/backlog action button by semantic — Verification: full
  **Prove it works:** 1. "mark done"/"Activate"/"Add"/"Submit response" render solid green w/ white text. 2. "defer" solid amber w/ dark text. 3. "details"/"copy"/"+ context"/"stage"/"+ cross-link" solid blue. 4. "promote to branch" solid purple. 5. "archive"/draft "mark used / clear" solid muted-red. 6. "annotate"/"dispute"/"cancel"/"Show concluded" solid slate. Hover lighter, active darker, disabled muted.
  **Wire checks:** `web/app.css` (`.b-commit`/`.b-caution`/`.b-util`/`.b-elevate`/`.b-destruct`/`.b-neutral` + `:hover`/`:active`/`:disabled`) → `web/app.js` (`renderActions`/`openCtx`/`renderBacklog` button classes) → `web/index.html` (`#blSave`/`#blCancel` classes)
  **Integration points:** preview_eval reads computed background-color of a `.b-commit`/`.b-caution`/`.b-util` button and asserts the filled hex per semantic.
- [x] 2. Item 26: clicking "details" no longer resets pane scroll — toggle the rich-details box inline (no full `renderActions()` rebuild) and `scrollIntoView({block:'nearest'})` so the clicked item stays visible — Verification: full
  **Prove it works:** 1. Scroll the Waiting pane so an item is mid/bottom. 2. Click its "details" — the item stays where it is (no jump to top); details expand inline below it. 3. Collapse removes the box, still no scroll reset. 4. SSE frame still renders expanded state (expandedItems preserved).
  **Wire checks:** `web/app.js` (`det-toggle` handler does in-place append/remove of `.li-details` + caret flip + `li.scrollIntoView({ block: 'nearest' })`, NOT `renderActions()`)
  **Integration points:** preview_eval scrolls actionsBody, clicks a det-toggle, asserts actionsBody.scrollTop is unchanged (±2px) and `.li-details` present.
- [x] 3. Item 27: decision/question items expose ONLY "Respond" as the completion path — no "mark answered"/"mark done" quiet-resolve; action items keep "mark done" — Verification: full
  **Prove it works:** 1. A `decision` item shows Respond (+ defer) but NO "mark answered" button. 2. A `question` item likewise. 3. An `action` item still shows "mark done". 4. No other quiet-resolve button on decision/question (dispute is gated to already-checked items only — unchanged).
  **Wire checks:** `web/app.js` (`renderActions` only constructs the done button when `it.kind === 'action'`; Respond path unchanged via `respondable()`)
  **Integration points:** preview_eval asserts a decision li has a "Respond" button and zero buttons whose text matches /mark (done|answered)/; an action li still has "mark done".
- [x] 4. Item 28: Defer popover — presets ("Later today" 8 PM, "Tomorrow morning" 9 AM, "Next week" Mon 9 AM, "Pick a specific time…" → `<input type="datetime-local">`, "Until further notice — move to Backlog"); all times local; `deferred` event records additive `scheduled_for_local` + `tz_offset_min`; "to Backlog" reuses backlog-promotion via additive `item-backlogged` event — Verification: full
  **Prove it works:** 1. "defer" opens a popover (not a `prompt()`). 2. Each preset computes the correct LOCAL datetime (verify "Next week" on a Monday → following Monday 09:00). 3. "Pick a specific time…" uses a native `datetime-local`; chosen value round-trips (stored → deferred badge re-displays the same local time via `fmtTime`). 4. "Until further notice — move to Backlog" removes the item from Waiting and creates a Backlog entry (same tree) with the existing "Activate" return path. 5. state selftest proves `item-backlogged` is additive + local-time fields persist + SCHEMA_VERSION still 1.
  **Wire checks:** `web/app.js` (`renderActions` defer handler → `.defer-pop` popover; presets compute local Date; `isWaiting` excludes `it.backlogged`) → `state/schema.js` (`item-backlogged` in `EVENT_TYPES` + `EVENT_REQUIRED_FIELDS`) → `state/reducer.js` (`case 'item-backlogged'` sets `it.backlogged`; `deferred` case persists `scheduled_for_local`/`tz_offset_min`)
  **Integration points:** `node state/selftest.js` P16 asserts item-backlogged round-trip + additive defer fields + SCHEMA_VERSION===1; preview_eval opens the popover and asserts a `datetime-local` input + the 5 preset buttons.
- [ ] 5. Extend `state/selftest.js` (P16) + `web/responsive.selftest.js` (R39–R43) + full regression (state 16/16, responsive 43/43, backfill 11/11, conv-tree gates 18/8 unchanged) + DEC log + completion report — Verification: full
  **Prove it works:** 1. `node state/selftest.js` → 16 passed 0 failed (P16 added). 2. `node web/responsive.selftest.js` → 43 passed 0 failed (R39–R43 added). 3. `node state/backfill-details.js --self-test` → 11/11. 4. conv-tree-state-gate `--self-test` 18/0, conv-tree-stop-gate 8/0 (unchanged — schema major unchanged). 5. Decisions Log + completion report appended.
  **Wire checks:** `state/selftest.js` (new `P16`) → `web/responsive.selftest.js` (new `R39`–`R43`) — both grep the additive schema/reducer + new CSS/JS invariants
  **Integration points:** all five self-test commands run and reported in the evidence block.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.css` — six `.b-*` filled semantic button classes + hover/active/disabled; `.defer-pop` popover styling.
- `neural-lace/conversation-tree-ui/web/app.js` — reclassify all action buttons; inline Details toggle (no rebuild) + scrollIntoView nearest; gate done-button to action kind; Defer popover (presets + datetime-local + to-Backlog); `isWaiting` excludes backlogged.
- `neural-lace/conversation-tree-ui/web/index.html` — `#blSave`/`#blCancel` semantic button classes.
- `neural-lace/conversation-tree-ui/state/schema.js` — additive `item-backlogged` event type + required fields (no major bump).
- `neural-lace/conversation-tree-ui/state/reducer.js` — `item-backlogged` reducer case; `deferred` case persists optional local-time fields.
- `neural-lace/conversation-tree-ui/state/selftest.js` — P16 additive-event + local-time-field regression property.
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — R39–R43 invariants for items 25–28.
- `docs/plans/conv-tree-ui-v1.1.2-polish.md` — this plan.

## In-flight scope updates

## Assumptions
- The spec's button palette (commit #22C55E, caution #F59E0B, util #3B82F6, elevate #A855F7, destruct #B91C1C, neutral #475569) is used verbatim; white text on all except caution (dark text on amber for contrast) per harness UX contrast standard. Verified per-class via computed-style.
- A new event type is additive per ADR-032 §1 ("Adding a new event type to EVENT_TYPES is additive — no bump"); precedent: v1.1-ux added `item-details-set`/`action-responded`/`item-unchecked` with SCHEMA_VERSION unchanged at 1. `item-backlogged` follows the same pattern.
- `scheduled_for` stays the canonical cross-machine ISO value (reducer/`checkDefers` unchanged); `scheduled_for_local` + `tz_offset_min` are OPTIONAL additive item fields for unambiguous re-display — not added to `EVENT_REQUIRED_FIELDS` (no contract change).
- The "Activate" button already in the Backlog pane is the documented return path for an item moved "until further notice — move to Backlog"; no new return-path UI needed (spec explicitly says reuse it).
- Conv-tree gates key off the schema MAJOR (unchanged at 1) → 18/8 green by construction; re-run only to confirm no regression.
- Display is already local (`fmtTime` uses `toLocaleString`); the only local-time gap was the ISO-`prompt()` INPUT, which item 28 replaces.

## Edge Cases
- "Later today" (8 PM) when it is already past 8 PM local → roll to tomorrow 8 PM (a past `scheduled_for` would fire `checkDefers` immediately, surprising the user).
- "Next week" when today IS Monday → the FOLLOWING Monday (+7 days), never today.
- `datetime-local` returns `YYYY-MM-DDTHH:MM` parsed as LOCAL time by `new Date(value)`; `.toISOString()` yields the canonical UTC `scheduled_for`; `scheduled_for_local` stores the raw local string; offset = `new Date(value).getTimezoneOffset()` (JS convention, minutes behind UTC).
- A `backlogged` item must drop out of "Waiting on you": `isWaiting` returns false when `it.backlogged` even though it is unchecked — but it still blocks node auto-conclude (it is genuinely not done; parking ≠ completing) which is correct.
- Item 28 "to Backlog" posts TWO events (`item-backlogged` then `backlog-added`); if the first succeeds and the second fails, the item is parked but not in backlog — surface the error toast (post() already does) and leave the item parked (recoverable: it is still in the node, reachable via the tree; not data loss).
- Decision/question with NO `details` and not yet responded still shows Respond (`respondable()` is true for kind decision/question regardless of details) — confirms item 27 never strands a decision with no completion path.
- Inline Details toggle must keep `expandedItems` in sync so a subsequent SSE-driven full `renderActions()` still renders the box expanded (no visual regression on live updates).
- Popover: only one open at a time (mirror the existing respond-box single-open guard); close on outside-click / Escape / choosing a preset.

## Acceptance Scenarios
n/a — `acceptance-exempt: true` (harness-internal tooling; self-tests + maintainer live-use are the acceptance artifact).

## Testing Strategy
- Each item carries a `**Prove it works:**` user-flow + a static `**Wire checks:**` chain (file:token) the wire-check gate verifies.
- Deterministic regression: `state/selftest.js` (P16 new), `web/responsive.selftest.js` (R39–R43 new), `state/backfill-details.js --self-test`, both conv-tree gate `--self-test`s.
- Live verification: the running `:7733` server after restart — Misha is the live user; the maintainer-observable self-tests are the acceptance artifact (acceptance-exempt).

## Walking Skeleton
Thinnest end-to-end slice proving the additive schema path before the rest: add `item-backlogged` to `schema.js` EVENT_TYPES/REQUIRED + the `reducer.js` case → extend `state/selftest.js` P16 → `node state/selftest.js` green (16/16, SCHEMA_VERSION still 1). That proves the only non-pure-client change (the additive event) is correct before the CSS/JS polish is layered on.

## Decisions Log

### Decision: item-backlogged is an ADDITIVE event; defer local-time fields are OPTIONAL additive (ADR-032 major 1, no bump)
- **Tier:** 2
- **Status:** proceeded with recommendation (governed by ADR-032 §1 + state/schema.js header — "Adding a new event type to EVENT_TYPES is additive (no bump)"; same precedent as the v1.1-ux trio `item-details-set`/`action-responded`/`item-unchecked` which shipped via a plan Decisions Log entry with no standalone ADR — pre-stop audit accepted + merged)
- **Chosen:** `item-backlogged` added to `EVENT_TYPES` + `EVENT_REQUIRED_FIELDS` (`['node_id','item_id']`); reducer gains `case 'item-backlogged'` setting `it.backlogged=true` (+ `item-unchecked` clears it for round-trip). `deferred` additionally accepts OPTIONAL `scheduled_for_local` + `tz_offset_min` persisted on the item; `scheduled_for` stays the canonical cross-machine ISO value. `schema_version` stays 1.
- **Alternatives:** (a) MAJOR bump (rejected — no required field of an existing event changes; a bump would needlessly trip every reader's "schema too new" refuse + the conv-tree gates). (b) Overload `archived`/`action-done` to park the item (rejected — `archived` is node-level and would hide siblings; `action-done` is a silent-resolve which item 27 explicitly forbids and is semantically wrong — a parked item is NOT done). (c) Make the defer local-time fields REQUIRED on `deferred` (rejected — that IS a contract change to an existing event; optional/derived keeps every Phase-0/v1.1 deferred event valid unchanged).
- **Reasoning:** additive-within-major is the ADR-032-sanctioned evolution path; keeps the frozen contract + all gates intact; the Walking Skeleton (P16) proves it before the client polish. Application of existing ADR-032 §1 policy, not a new architecture decision → `architecture: existing`, no new standalone ADR (mirrors the accepted v1.1-ux precedent).
- **To reverse:** remove the one enum row + the reducer case + P16/R43; the optional `deferred` fields are simply never set; the Backlog "Activate" return path is unaffected.

### Decision: "until further notice — move to Backlog" posts two existing-shape events; no dedicated undo
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** the "to Backlog" defer choice posts `item-backlogged` (parks it out of Waiting) then `backlog-added` (tree=`treeOf(n)`, priority medium, text=item text) + a `context-attached` crumb. The existing Backlog "Activate" button is the documented return path (spec explicitly says reuse it). No bespoke undo for this choice (plain confirmation toast); the other defer presets keep the existing `deferred`→`defer-cleared` undo via `actWithUndo`.
- **Alternatives:** (a) a single combined event (rejected — would need a non-additive reducer that both parks AND creates a backlog row; two existing-shape events compose without a contract change). (b) a dedicated un-backlog undo (rejected — the spec names "Activate" as the return path; a partial undo orphaning the backlog row is messier than the spec's path).
- **Reasoning:** reuses two already-shaped events; the return path is the spec-named Activate button; recoverable by construction (item stays in the node, reachable via the tree, tracked in Backlog).
- **To reverse:** the events are additive; clearing `backlogged` (item-unchecked) re-surfaces the item.

## Definition of Done
- [x] All 5 tasks task-verified PASS
- [x] state selftest 16/16, responsive 43/43, backfill 11/11, conv-tree gates 18/8 — all green
- [x] SCHEMA_VERSION still 1 (additive proof in P16)
- [x] SCRATCHPAD.md updated
- [x] Completion report appended; PR merged to master; main checkout synced; :7733 restarted

## Completion Report

### 1. Implementation Summary
| Plan task | Built | Verifier |
|---|---|---|
| 1. Item 25 filled semantic buttons | 6 `.b-*` CSS classes (exact spec hex) + hover/active/disabled; 32 action buttons reclassified across `renderActions`/`openCtx`/`renderBacklog`; `#blSave`/`#blCancel`; chrome ✕ left subdued | task-verifier PASS (commit 71ad016) |
| 2. Item 26 no-scroll Details | `det-toggle` handler toggles `.li-details` in place (no `renderActions()` rebuild) + `scrollIntoView({block:'nearest'})`; `expandedItems` kept in sync for the SSE full-render path | task-verifier PASS |
| 3. Item 27 Respond-only decision/question | done button gated to `it.kind==='action'`; zero "mark answered" in app.js; Respond path intact via `respondable()` (never strands a bare decision/question) | task-verifier PASS |
| 4. Item 28 Defer popover | `openDeferPop` with 5 presets (Later today 8 PM / Tomorrow 9 AM / Next week Mon 9 AM — `((1-getDay()+7)%7)||7` math verified / Pick specific → native `datetime-local` / Until further notice → Backlog); additive `item-backlogged` event + optional `scheduled_for_local`+`tz_offset_min`; `isWaiting` excludes backlogged; SCHEMA_VERSION still 1 | task-verifier PASS |
| 5. Selftests + regression + DEC log + report | P16 (state 16/16), R39–R43 (responsive 43/43), backfill 11/11, conv-tree gates 18/8; Decisions Log + this report | task-verifier PASS |

`Backlog items absorbed: none` — subsection omitted.

### 2. Design Decisions & Plan Deviations
Two Decisions Log entries above (Tier-2 additive-schema governed by ADR-032 §1 — no standalone ADR, mirroring the accepted v1.1-ux precedent; Tier-1 two-event "to Backlog"). No deviation from the approved plan; no in-flight scope updates.

### 3. Known Issues & Gotchas
- "to Backlog" posts two events; if `backlog-added` fails after `item-backlogged` succeeds the item is parked but not in Backlog — the error toast surfaces and the item remains reachable via the tree (recoverable, not data loss; documented Edge Case).
- The conversation-tree-state-gate fires on `Task|Agent` spawns in ANY session including harness-dev sessions that have no conversation-tree (resolved here via the gate's sanctioned substantive-waiver path, not `--no-verify`). Surfaced to Misha as a friction observation for discussion — not filed/acted on unilaterally per friction-reflexion.

### 4. Manual Steps Required
None — pure client + additive schema; no env vars, migrations, or services. Server restart of `:7733` is performed by this session post-merge so Misha sees it live.

### 5. Testing Performed & Recommended
Deterministic: `state/selftest.js` 16/16 (P16 new), `web/responsive.selftest.js` 43/43 (R39–R43 new), `state/backfill-details.js --self-test` 11/11, conv-tree-state-gate 18/0, conv-tree-stop-gate 8/0. Recommended: Misha's live use of the restarted `:7733` GUI (the plan's gate-honored acceptance path for this acceptance-exempt harness-internal tooling).

### 6. Cost Estimates
None — local-only vanilla JS/CSS module; no new dependency, service, or recurring cost.
