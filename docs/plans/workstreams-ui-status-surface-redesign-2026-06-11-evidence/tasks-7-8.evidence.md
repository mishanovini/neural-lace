# Evidence — Tasks 7 + 8 (Workstreams UI status-surface redesign, 2026-06-11)

Builder: worker-ws-card2 (parallel dispatch; salvage of the orphaned WIP commit
`58db4d9`, whose builder died mid-session with zero verification run).
Commits (oldest first): `0de8da4` (salvage + fix + style), `c4db22b`
(e2e locks T17–T20 + boot-safe zod require), this evidence commit.
Diff base: `b13f7dd` (plan branch tip before the WIP).

## Salvage audit — what was kept / fixed / added relative to the WIP

**KEPT (audited against the plan's binding corrections, found correct):**
- Server-side context-completeness annotation (`server/server.js:87
  annotateContextState`, `:79 gateCategoryOf`): every operator-ask item
  (decision / question / action_item_for_user — same category logic as the
  client's `isMishaAsk`) gets `context_state: complete|incomplete` derived AT
  SERVE TIME by the SOLE-NORMATIVE `assembleItemDetails` (null = not
  self-contained = the gate). I1 holds: zero parallel validators in
  `web/app.js` — the client only reads the annotation. The annotation is
  never persisted (readState re-parses per call; appendEvent does its own
  independent read; client state arrives only via the annotated SSE path).
- Backlog data model on EXISTING events only (C1): rows are first-class node
  items parked via `item-backlogged` (`backlogged` flag; `itemState` maps it
  to committed; `isWaiting` excludes it); edit = `item-text-set`; remove =
  `item-removed`; promote = the EXISTING `backlog-activated` (NO
  `item-promoted` — the task line's wording was the documented stale trap).
  C1's own event list (item-text-set / item-removed operate on node items)
  forces exactly this membership model; the snap.backlog mirror is created
  lazily at promote time (`buildPromoteEvents` app.js:964) purely to satisfy
  backlog-activated's reducer precondition, with `branch-retitled` repairing
  a stale mirror title.
- C5: all 8 native `prompt()` sites replaced — Submit-a-decision (now
  per-option Choose buttons on the essentials card), Decline-why, Answer,
  Decline-ask-why, Respond-note, Block-reason, Ship-evidence,
  Deploy-evidence all via the in-card `openInlineForm` (app.js:2174).
- I2: `buildActionButtons` (app.js:2355) early-returns on a gated ask —
  ONLY the needs-enrichment note + the respond/enrichment channel render;
  every resolving AND lifecycle button suppressed.
- I5: the card's expand is a native `<details>` disclosure; `openInlineForm`
  lives inside the existing modal; zero new Esc/scrim handlers added.
- Header "+ capture" form re-routed through the same `addBacklogItem` path so
  every captured item is equally editable/removable/promotable.

**FIXED (defects in the WIP):**
1. Backlog leaked into My-tasks: `myTaskRefs` (app.js:359) and the
   `my-tasks` filter (app.js:400) now exclude `backlogged` items — the
   someday bucket renders ONLY on the Backlog surface and ENTERS the active
   list via promote ("Tasks = active; backlog = someday"); without this,
   promote-to-task was meaningless.
2. `ensureBacklogNode` failure dead-ended the add input (disabled forever,
   onFail never invoked). Failure callback threaded (app.js:912) — I3's
   re-enable + inline retry now fire on a failed node-create too.
3. A comment carried the literal `window.prompt` token, which would have
   failed the C5 zero-grep acceptance; reworded.
4. The WIP made `zod` (via decision-context-schema.js) load-bearing for
   server BOOT, violating server.js's "NO runtime deps" header with a
   startup crash on any machine without node_modules (reproduced in this
   worktree). The require is now defensive (`server/server.js:40`): missing
   module → loud stderr warning + degraded mode writing NO annotation, so
   the client gate fails CLOSED (asks render context-incomplete) rather
   than the passive GUI dying. Unchanged behavior where zod is installed
   (the operator's checkout has it via workstreams-ui/package.json).

**ADDED (missing from the WIP entirely):**
- All CSS (the WIP touched zero styles): backlog rows (`bl-row`,
  `bl-legacy`, `ctrl-promote`) + the whole Task-8 card (`dc-essentials`,
  `dc-bg/ask/opts/opt-*/rec-line/reply-line`, `dc-more` disclosure,
  `dc-incomplete-panel/-h/-b`, `dm-gate-note`, `dm-form*`) — per the C6
  discipline: neutral gray structure, NO new amber/green; the incomplete
  state mirrors the list's neutral-dashed `ctx-incomplete-badge`.
- Regression locks T17–T20 (`scripts/regression.e2e.js`) + a suite-wide
  native-dialog counter.
- This evidence file + screenshots.

## Task 7 — done-when mapping

Prove-it (plan): 1. add a backlog item; 2. promote it; 3. it moves to the
active list / Next and out of backlog.

- Step 1 → T17: in-surface add (`#filterBody .mytasks-add-input` + Enter)
  → row appears in Backlog with promote/remove controls; NOT in My-tasks
  (`inMyTasksBeforePromote=false`). Screenshot `backlog-add-1280.jpg`
  (editable "mine" row + 4 promote-only legacy captures + "Captured to
  backlog" toast; cockpit Backlog root counts it under NEXT).
- Steps 2–3 → T17: `.ctrl-promote` click → `leftBacklog=true`,
  `parkedStill=false`, task found with `state=committed` (the NEXT tier),
  `origin=operator`, on a root with `origin=backlog-activated` (FR-22
  handoff), `inMyTasksAfter=true`. Screenshot `backlog-promoted-1280.jpg`
  (My-tasks shows the promoted committed task; activated root visible in
  the cockpit with 1 next; "Promoted to task" toast).
- Wire check (`web/app.js` → `server/server.js`): add/edit/remove/promote
  all round-trip POST /api/event (C2 per-type 422 guards extended to
  `backlog-added` / `item-backlogged` / `branch-retitled`,
  server/server.js:158-178).
- Integration point: `backlog-activated` reduces correctly — asserted via
  the /api/state oracle in T17 (activated root exists, mirror.activated
  flips the entry out of the backlog view).
- I3: add-failure keeps text + re-enables + inline retry note; edit failure
  visibly REVERTS + `↻ not saved — retry` on the row (`attachBacklogEdit`);
  promote failure leaves the row + `↻ not promoted — retry` re-posting the
  SAME pre-generated-event_id array (idempotent resume via `postSeq`).

## Task 8 — done-when mapping

Prove-it (plan): 1. open a decision with full details → background /
options-with-meaning / recommendation / reply; 2. open one missing details
→ "context incomplete", not a bare choice.

- Step 1 → T18: posted a context-complete decision via /api/event (against
  the COPY, never the operator's file — explicitly permitted for the demo);
  modal shows `dc-essentials` with 2-sentence background, the ask, ONE line
  per option carrying meaning + `risk:` + cost + per-option Choose,
  `→ recommended:` line, `Reply with` phrasing, full renderer behind "More
  context". Reply recorded via the in-surface `dm-form` (action-responded
  verified in state; zero native dialogs). Screenshot
  `context-complete-1280.jpg`.
- Step 2 → T19: a detail-less decision renders the neutral
  "context incomplete — needs enrichment" panel; `dm-actions` carries the
  gate note + EXACTLY ONE button (respond/request-enrichment); zero
  resolving/lifecycle buttons. Screenshot `context-incomplete-1280.jpg`.
  This is the COMMON path: the live copy serves 24 asks, all annotated
  incomplete (`{"complete":0,"incomplete":24,"none":105}` from /api/state).
- Wire check (`web/app.js` → `state/schema.js` read): the client reads the
  reduced item (`details`, `context_state`) shapes; the per-kind required
  fields live ONLY in `state/decision-context-schema.js`
  (`ItemDetailsContentSchema` / `validateItemDetails` /
  `assembleItemDetails`) consumed server-side (I1 — re-styled, not
  re-templated; no second validator).
- Cold-read bar: the complete card answers what / why-now / what each
  option means+trades-off / what's recommended / how to reply with zero
  chat memory (see screenshot); anything the assembler can't verify as
  self-contained is gated, not presented as choosable (I2).

## Runtime evidence (commands + outputs)

1. `node state/selftest.js` → **21 passed, 0 failed** (state/ source
   untouched by these tasks).
2. `CONV_TREE_STATE_PATH=<copy> CTREE_PORT=7799 node server/server.js` —
   server on 7799 against a fresh copy of the live 124-item state
   (operator's 7733 instance and real file untouched).
3. `WS_URL=http://127.0.0.1:7799/ SHOT_DIR=<evidence-dir>
   node scripts/regression.e2e.js` → **21/21 PASS** (T0–T16 pre-existing
   locks all green, incl. T10 waiting-list `waitRows=20 oracle=20 bare=0`;
   T17 `add=true inMyTasksBeforePromote=false leftBacklog=true
   task=true/committed/operator activatedRoot=backlog-activated
   inMyTasksAfter=true`; T18 `card=true bg=true opts=2 meaning=true
   choose=2 rec=true reply=true more=true approve=true inSurfaceForm=true
   respondedRecorded=true`; T19 `panel=true gateNote=true buttons=1
   resolving=0`; T20 `window.prompt-in-source=0 nativeDialogsFired=0`).
4. `grep -c "window.prompt" web/app.js` → **0** (C5 acceptance).

Screenshots (this directory): `backlog-add-1280.jpg`,
`backlog-promoted-1280.jpg`, `context-complete-1280.jpg`,
`context-incomplete-1280.jpg`.

## Comprehension Articulation

### Task 7 — Spec meaning

The Backlog surface is the operator-owned "someday" bucket, distinct from
the active My-tasks list, with the same in-surface editing chrome (always-
present add input, inline text edit, remove, I3 revert+retry) plus one
extra affordance: promote-to-task, which moves an item out of the someday
bucket into the active/Next tier. Per binding correction C1 the build uses
ONLY existing events — promote is the existing `backlog-activated`, not a
new `item-promoted` — and per C5 no authoring step may use a native prompt.

### Task 7 — Edge cases covered

- Pre-promote separation: a parked item never shows in My-tasks
  (`web/app.js:359-362` myTaskRefs exclusion, `:400` filter exclusion).
- Promote of a row with no snap.backlog mirror: mirror created lazily with
  the CURRENT text so an inline edit never leaves a stale mirror
  (`web/app.js:972-975`); stale pre-existing mirror title repaired via
  `branch-retitled` (`web/app.js:978-982`).
- Retry after partial promote failure: stable pre-generated event_ids make
  re-posting the SAME array an idempotent resume (`postSeq`
  `web/app.js:927-936`; retry button `web/app.js:1006-1020`).
- Already-activated mirror (idempotent re-promote): `backlog-activated`
  skipped, the existing `activated_node` reused (`web/app.js:968-977`).
- Legacy snap.backlog captures (no node item): rendered promote-only with
  an honest "legacy capture" badge, deduped by item_id against node items
  (`legacyBacklogEntries` `web/app.js:907-911`, `legacyBacklogRow`
  `web/app.js:1133`).
- Add failure incl. failed Backlog-node creation: input re-enabled + inline
  retry, text preserved (`ensureBacklogNode` `web/app.js:912-921`,
  `renderBacklogInto` failure branch `web/app.js:600-607`).
- Empty backlog: designed empty state ("capture 'someday' work above").

### Task 7 — Edge cases NOT covered

- Double-failure promote sequence (action-added lands, item-removed fails,
  page re-renders losing the retry button, operator clicks promote afresh):
  a second task item would be created. Judged acceptable: requires two
  consecutive write failures around an SSE re-render; the duplicate is
  operator-visible in My-tasks and removable in one click.
- Legacy entries have no edit/remove (the event vocabulary has no
  backlog-text-edit/-remove for snap.backlog rows) — honest fix-forward
  limitation, surfaced by the "legacy capture" badge.
- Parked items on an ARCHIVED node disappear from the surface while their
  un-activated mirror would also be hidden by the item_id dedupe only if
  the node item is visible; rare and benign (archive is an explicit act).

### Task 7 — Assumptions

- The reducer's `backlog-activated` precondition (mirror must exist) and
  FR-22 root-creation semantics stay as shipped (`state/reducer.js:260-275`).
- `item-backlogged` → `itemState committed` → counts under NEXT is the
  intended cockpit treatment of "someday" work (it is how the verified
  Task 3 statusCounts already bucket it).
- The GUI is the single writer racing only the AI's appends; envelope-level
  event_id idempotency (§2) is the concurrency story for retries.

### Task 8 — Spec meaning

Every operator-ask (decision / question / action-for-operator) must pass a
context-completeness gate before being presented as actionable: complete →
a progressive-disclosure essentials card (1–2 sentence background, the ask,
one line per option with meaning+tradeoff, the recommendation, reply
affordances, full reasoning behind "More context"); incomplete → a "needs
enrichment" state with ALL resolving/lifecycle affordances suppressed (I2),
never a bare A/B/C. Per I1 the completeness check IS the existing
sole-normative Zod assembler — re-style the existing card, add no second
schema. Per C5 every reply records via an in-surface form.

### Task 8 — Edge cases covered

- Details with `_category` outside the gate set (autonomous_action,
  builder-dispatch logs): not asks, never gated, keep the existing render
  (`server/server.js:79-85` returns null; client `isMishaAsk` false).
- Ask with no `details` at all (the 24/24 live case): annotated incomplete
  via `assembleItemDetails(cat, {})` → null (`server/server.js:87-97`);
  partial detail stays reachable behind "Show what detail exists"
  (`web/app.js:2148-2170`).
- Kind=decision/question without `_category`: category inferred from kind
  on BOTH sides symmetrically (server `gateCategoryOf` / client
  `isMishaAsk`), so the row predicate and the card gate cannot disagree
  about who is gated.
- String vs object options, missing option keys, object recommendation:
  `optionTitle`/`optionKeyOf` fallbacks (`web/app.js:2060-2070`); reply
  affordances only on still-open decisions (`!it.checked`).
- zod unavailable at boot: server boots in degraded mode, no annotation →
  client gate fails CLOSED (`server/server.js:40-52`, `:88`).
- Annotation never persisted: serve-time mutation of a per-call parse;
  appendEvent reads independently (verified in `state/store.js:184` —
  readState re-parses per invocation).

### Task 8 — Edge cases NOT covered

- The Task-4 waiting-ROW summary marker still uses its own prose heuristic
  (`waitingSummary`, the verified Task-4 surface) rather than
  `context_state`; a details payload with `the_ask` but no `background`
  shows a summary on the row while the modal gates it. The gate (the
  actionability decision) is single-sourced; the row marker is cosmetic
  and re-keying it risks the verified T10 lock — left for Task 10/11
  polish if the operator wants row/card parity.
- No enrichment ROUND-TRIP: "Respond / request enrichment" records
  action-responded for the AI to act on; the emit-side authoring of
  context is Task 9 (a parallel builder owns it).
- `firstSentences` clamps on `.!?` only; a background written as one giant
  unpunctuated line renders in full inline (no truncation harm, just less
  clamping).

### Task 8 — Assumptions

- `assembleItemDetails(category, fields)` returning null IS the normative
  incompleteness predicate (per its module contract,
  `state/decision-context-schema.js:574-590`), and category-from-kind
  inference for legacy items without `_category` matches the module's
  authoritative `_category` override behavior.
- The browser cannot require the Zod module (CommonJS, no build step), so
  serve-time annotation is the I1-compliant delivery of the sole-normative
  verdict to the client; SSE is the client's only state source
  (`web/app.js:2849-2853`), so the annotation is always present when zod is.
- Suppressing lifecycle buttons on gated asks (beyond the named resolving
  buttons) is the correct I2 reading — "not presented as actionable" means
  no state-mutating affordance at all except the enrichment-request channel.
