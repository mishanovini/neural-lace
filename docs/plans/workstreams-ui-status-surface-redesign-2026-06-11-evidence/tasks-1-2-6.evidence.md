# Evidence — Tasks 1, 2, 6 (operator-authoring vertical + My-tasks surface)

Branch: `worker-ws-mytasks`
Commit: `536e813d69d037d9c7d6e7f7e0b6be18b5d10ce0`
Worktree: `C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/worktrees/agent-a3bf47087ec4c946f`
Verification level: Task 1 = contract; Tasks 2, 6 = full.

## Task 1 — data substrate (REUSE existing events; ONE new event)

Done-when (C1): reuse `action-added` (+ `origin:operator`), `item-text-set` (edit),
`reordered` (reorder), `backlog-activated` (promote); add exactly ONE new event
`item-removed`; `origin` is an OPTIONAL reducer-read item field (NOT in
EVENT_REQUIRED_FIELDS); resolve store-vs-derive.

**Store-vs-derive decision: DERIVED from `ev.actor`, persisted on the item.**
The snapshot carries no per-item actor, so a render-time derive would need a
per-item log walk the renderer does not have. The reducer reads the
authoritative `ev.actor` the server forces (`gui`⇒operator, `dispatch`⇒ai) — OR
an explicit `ev.origin` when provided — and stamps the derived value on
`it.origin` at the creating `action-added` only (a later operator edit never
re-derives, so an AI item's origin is never flipped). This is "derive from
actor" per the C1 instruction; the derived result is persisted exactly as
`tier`/`serves_item_id` are persisted reducer-read item fields. `origin` is NOT
in EVENT_REQUIRED_FIELDS — every existing `action-added` parses unchanged.

Files: `state/schema.js` (+`item-removed` type + required fields), `state/reducer.js`
(item-removed case + origin stamp on action-added), `state/selftest.js` (P20).

Mechanical check (contract — the pre-existing oracle is the full selftest suite):
```
$ node neural-lace/workstreams-ui/state/selftest.js
  PASS  P20 operator-authoring e2e: create(+origin store/derive) / edit(no-origin-flip)
        / reorder / remove(+reject-retain+idempotent+envelope) — schema major 1, attested
21 passed, 0 failed
```
P20 asserts: create via action-added (origin derived from actor=gui AND explicit
origin); AI create (actor=dispatch) ⇒ origin='ai'; edit via item-text-set does
NOT flip an AI item's origin; reorder via reordered; remove via item-removed
splices the item; unknown item/node id rejected-AND-retained (NFR-2); same
event_id re-append idempotent no-op; missing item locator rejected by envelope
validation; schema_version stays 1; snapshot attestation still verifies.

## Task 2 — POST /api/event per-type operator-payload validation (NOT rebuilt)

Done-when (C2): endpoint already exists (`server.js:163-191`, forces actor=gui,
appends via the facade, 400/422/409) — do NOT rebuild; add per-type payload
validation + confirm round-trip.

File: `server/server.js` — added `validateOperatorPayload()` run BEFORE
`appendEvent`; returns a specific 422 on a malformed operator event. The facade
(`appendEvent`) is never bypassed; the endpoint is unchanged.

Runtime (server on a temp state file, curl):
```
empty text on action-added      → HTTP 422 {"error":"action-added requires non-empty text"}
bad origin enum                 → HTTP 422 {"error":"action-added origin must be \"operator\" or \"ai\"..."}
reordered ordered_ids non-array → HTTP 422 {"error":"reordered requires ordered_ids to be an array"}
item-removed missing item_id    → HTTP 422 {"error":"item-removed requires a non-empty item_id"}
state after: bad1 absent=true bad2 absent=true   (malformed events never corrupted state)
```
Round-trip (add/edit/reorder/remove via POST /api/event, re-read /api/state):
each operation persisted across reload — see Task 6.

## Task 6 — My-tasks surface (operator-owned, editable)

Done-when: list all `origin:operator` items; in-surface "+ add" (C5 — never
window.prompt); inline-edit (item-text-set); remove (item-removed); reorder
(reordered) via KEYBOARD (I4); on POST failure inline edit REVERTS + shows inline
"not saved — retry" ON the row (I3); removed items filtered out of the surface.

Files: `web/index.html` (My-tasks chip), `web/app.js` (`renderMyTasksInto`,
`myTaskRow`, `reorderMyTask`, `myTaskRefs`, `ensureMyTasksNode`, filter plumbing),
`web/app.css` (surface styling; amber reserved for needs-you per C6 — controls
are neutral, only --err red is used for the retry affordance).

Runtime (real browser via Claude-in-Chrome against the live server):
- My-tasks chip renders, active, count reflects operator items; in-surface
  "+ add" input present (placeholder "Add a task and press Enter…"); NO
  window.prompt in the surface flow.
- Typed-add ("water the plants") via the input + Enter → row appears →
  PERSISTS to the state file (`origin: operator`).
- Inline edit: clicking row text swaps in an <input>; "call plumber" →
  "call plumber (edited)" → persisted.
- Keyboard/button reorder: the ▼ control (aria-label "move task down") flips
  order [task-B, water] → [water, task-B].
- Remove: the ✕ control removes the row; sibling remains; removed item filtered
  from the surface AND gone from the state file.
- Write-failure revert (I3): with fetch stubbed to reject, an inline edit
  REVERTS the displayed text to the original, marks the row `save-failed`, and
  shows the inline affordance "↻ not saved — retry" ON the row (not just a
  toast); the state file is unchanged (failed write never persisted).
- No console errors; screenshot captured showing the surface + retry affordance
  + the operator items appearing in the left project tree (first-class model).

## Acceptance scenario `add-and-edit-a-personal-task`
1. Open "My tasks" → chip active, in-surface add input present. ✓
2. Type a new task + Enter → appears immediately, persists to state file. ✓
3. Edit text inline + reload → text change persists; shows in cockpit counts +
   the "My tasks" project tree. ✓
Plus I3 (write-error revert + inline retry) exercised in the real browser. ✓
