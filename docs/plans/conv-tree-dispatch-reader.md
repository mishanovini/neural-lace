# Plan: Conv Tree Dispatch-Reader Hook
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: single-hook + cursor state + facade-read; mirrors conversation-tree-emit.sh
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal hook; the hook's --self-test + scripted end-to-end is the acceptance artifact, there is no product UI surface to advocate for
Backlog items absorbed: none

## Goal

Close the Conversation-Tree GUI loop. The emit hook (PR #3) writes branch
lifecycle events INTO the state file as Dispatch works. The v1.1 inline-response
UI (in-flight, parallel session) lets the operator type a response to an action
/ question / decision item in the GUI, which POSTs a GUI-actor event into the
same state file. **What is missing is the reverse direction**: a Dispatch-side
reader that picks up those operator-authored GUI events and surfaces them to the
orchestrator on its next turn — as if the operator had typed them in chat.
Without this reader, GUI responses sit in the state file forever and the loop
never closes.

Build `conversation-tree-read.sh` — a UserPromptSubmit hook that, before each
turn, reads new operator-authored GUI events via the A2 facade and injects them
as `additionalContext`.

## Scope
- IN: a new UserPromptSubmit hook `conversation-tree-read.sh`; a per-session
  read cursor; `--self-test` (≥8 scenarios); registration in live
  `~/.claude/settings.json` + repo `settings.json.template`; dual-mirror sync;
  architecture doc; regression run of the emit hook + conv-tree gate self-tests;
  one PR to master driven to merge; post-merge main-checkout sync.
- OUT: the GUI (server.js / web/app.js — the v1.1 session owns inline-response
  UI); the A2 state library (frozen — called, never modified); the emit hook;
  the conv-tree gates; adding any new event type to the ADR-032 §2 enum (the
  reader keys off the EXISTING frozen enum + speculative forward-compat names,
  it does not extend schema.js).

## Tasks

- [ ] 1. Build `conversation-tree-read.sh` (reader hook + ≥15-scenario `--self-test`) — Verification: mechanical
- [ ] 2. Scripted end-to-end: append a GUI `answered`+response event via the facade into a temp state file, fire the hook with synthetic UserPromptSubmit stdin, assert stdout `additionalContext` contains the response text — Verification: mechanical
- [ ] 3. Register the hook in live `~/.claude/settings.json` UserPromptSubmit chain + mirror into `adapters/claude-code/settings.json.template` — Verification: mechanical
- [ ] 4. Dual-mirror sync: live `~/.claude/hooks/conversation-tree-read.sh` byte-identical to `adapters/claude-code/hooks/conversation-tree-read.sh` — Verification: mechanical
- [ ] 5. Architecture doc `docs/conv-tree-dispatch-reader.md` + one-line row in `~/.claude/docs/harness-architecture.md` — Verification: mechanical
- [ ] 6. Regression: emit hook `--self-test` 17/17; `conversation-tree-state-gate.sh --self-test` + `conversation-tree-stop-gate.sh --self-test` still green — Verification: mechanical
- [ ] 7. One PR to neural-lace master, drive to merge, sync the `~/claude-projects/neural-lace` main checkout — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/conversation-tree-read.sh` — NEW. The reader hook (canonical).
- `~/.claude/hooks/conversation-tree-read.sh` — NEW. Live mirror (byte-identical).
- `adapters/claude-code/settings.json.template` — register reader in UserPromptSubmit chain.
- `~/.claude/settings.json` — live registration mirror (machine-local; not committed but must match).
- `docs/conv-tree-dispatch-reader.md` — NEW. Architecture doc for the reader half of the loop.
- `~/.claude/docs/harness-architecture.md` + `adapters/claude-code/docs/harness-architecture.md` — add the reader hook row.
- `docs/plans/conv-tree-dispatch-reader.md` — this plan.

## In-flight scope updates

## Assumptions
- The v1.1 inline-response UI POSTs via the existing `/api/event` endpoint,
  which forces `actor:"gui"` and appends ONE event through the frozen A2
  `appendEvent`. Confirmed by reading `server/server.js` lines 112-140.
- The operator-response events use the EXISTING ADR-032 §2 enum. From
  `web/app.js:355-356` the GUI emits `answered` (question/decision items) and
  `action-done` (action items); `annotated` (line 668) carries free text;
  `contested` (line 367) carries `.note`. The reader keys off these real types
  (plus speculative forward-compat names from the brief) — it does NOT depend
  on a `action-responded` type existing.
- Response text, when present, rides in an additive field (validateEvent only
  checks required fields, so extra fields pass). The reader scans a candidate
  field list (`.text` for annotated, `.note` for contested, then
  `.response/.text/.note/.answer/.comment/.body/.message`).
- The GUI server runs from the operator's MAIN checkout; the reader resolves
  the same main-checkout state file the emit hook's GUI sink targets (reuse the
  emit hook's `_main_repo_root` + GUI-path resolution for parity).
- `readState()` returns events in append-log order; the cursor tracks the
  last-seen `event_id` by array position (dispatch event_ids are not
  sortable; only GUI ULIDs are — array order is the only reliable ordering).

## Edge Cases
- Fresh cursor / first run → cold-start window-bounds the backlog (default 120
  min, cap 12) so turn 1 is not flooded; cursor then set to the latest event.
- Cursor event_id not found (compaction dropped it) → treated as cold-start.
- Malformed / torn / schema-too-new state file → facade throws → exit 0, no
  output, logged. Never crash, never block the prompt.
- Missing state file (GUI never ran) → exit 0 silently.
- No new events → exit 0, no output (clean no-op; idempotent re-fire).
- `actor:"dispatch"` events (the emit hook's own writes, the orchestrator's own
  `answered`) MUST NOT be surfaced — load-bearing exclusion (`actor==="gui"`).
- GUI housekeeping events (`reordered`, `draft-saved`, `re-parented`,
  `draft-cleared`) MUST NOT be surfaced — only the response-type allowlist.
- Large backlog → cap at MAX, emit most-recent MAX + truncation notice; cursor
  still advances to the latest event so nothing re-surfaces.
- Cursor advances past non-response events too (O(new) scan, no re-scan).
- node unavailable / any uncaught error → ERR trap → log → exit 0.

## Testing Strategy
- Task 1: `bash conversation-tree-read.sh --self-test` exercises ≥15 scenarios
  (fresh cursor, mid-stream cursor, malformed/missing state, no-new-events,
  mixed types, dispatch-actor exclusion, large-backlog truncation, cold-start
  window, text-field extraction for annotated/contested/answered+response,
  cursor-advances-past-non-response, snapshot title/item resolution, idempotent
  re-fire, failure isolation). PASS = `self-test: OK`, exit 0.
- Task 2: a scripted harness (inside the self-test as the e2e scenario) writes a
  real GUI `answered`+`response` event via `state.js appendEvent`, fires the
  hook in NON-self-test mode with synthetic stdin, asserts the emitted
  `additionalContext` JSON contains the response text and the resolved item
  title.
- Task 6: re-run emit hook + both conv-tree gate self-tests; all green.

## Walking Skeleton
The thinnest end-to-end slice: facade `appendEvent({type:"answered",actor:"gui",
node_id,item_id,response})` into a temp state file → `bash
conversation-tree-read.sh` with `CONV_TREE_STATE_PATH` + synthetic stdin →
stdout is `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
"additionalContext":"…response…"}}` → cursor file written. That single slice
exercises facade-read, actor filter, cursor create, text extraction, and the
UserPromptSubmit output contract — every architectural layer in one path. It is
self-test scenario E2E and is the acceptance artifact for an acceptance-exempt
harness hook.

## Decisions Log

### Decision: key off the real ADR-032 enum, not the brief's speculative names
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** filter `actor==="gui"` AND type ∈ {answered, action-done,
  annotated, contested, contest-resolved, deferred, defer-cleared,
  backlog-added} ∪ {action-responded, action-noted-via-gui, question-answered,
  decision-made (forward-compat, harmless if never emitted)}.
- **Alternatives:** trust the brief's `{action-responded,...}` names verbatim —
  rejected: those are NOT in the frozen §2 enum, `validateEvent` would reject
  them on write so they cannot appear unless v1.1 also extends schema.js; the
  GUI today emits the real enum types (`web/app.js:355-356`).
- **Reasoning:** the enum is the source of truth (the brief said "or whatever
  event types the v1.1 inline-response UI emits"). Including the speculative
  names too is forward-compatible and costless.
- **To reverse:** edit the RESPONSE_TYPES allowlist constant in one place.

### Decision: cursor tracks last-seen event_id by ARRAY POSITION
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** walk `events[]` in log order; new = events after the stored
  `last_event_id`'s index; advance cursor to the final event_id every run.
- **Alternatives:** sort by event_id — rejected: dispatch event_ids
  (`cte-bo-*`) are content hashes, not time-sortable; only GUI ULIDs sort.
- **Reasoning:** the append log order is the only reliable ordering and is
  stable per ADR-031 (append-only).
- **To reverse:** N/A — array order is the contract.

## Definition of Done
- [ ] All tasks checked off
- [ ] Reader `--self-test` ≥15 scenarios, `self-test: OK`
- [ ] End-to-end slice verified (GUI response event → next-turn additionalContext)
- [ ] Emit hook 17/17 + both conv-tree gate self-tests still green
- [ ] Dual mirror byte-identical
- [ ] SCRATCHPAD.md updated
- [ ] Completion report appended
- [ ] PR merged to master; main checkout synced

## Systems Engineering Analysis
n/a — `Mode: code` harness-infrastructure work-shape (`build-harness-infrastructure`):
every file is under `adapters/claude-code/` or `~/.claude/`, no user-observable
runtime, self-test is the verification idiom. The 10-section Systems
Engineering Analysis is for `Mode: design` plans; this is a single-hook
addition mirroring an already-shipped sibling (`conversation-tree-emit.sh`).
