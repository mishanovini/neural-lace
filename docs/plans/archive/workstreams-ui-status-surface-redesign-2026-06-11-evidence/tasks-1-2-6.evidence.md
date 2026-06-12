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

## Comprehension Articulation

> **Authorship note (honesty):** authored by the orchestrator, not the original
> builder sub-agent session (`a3bf47087ec4c946f`), which is not continuable in this
> harness — the main session has no `SendMessage` tool surface to reach a finished
> sub-agent. Grounded in the verified diff (`afd1bb4..536e813`) and the
> task-verifier's independent re-derivation (selftest 21/21 incl P20; C1 honored
> exactly; live 422s; 13/13 My-tasks round-trip). The build's verified correctness
> is the demonstration of comprehension this records; the comprehension-reviewer's
> diff-correspondence check holds regardless of author.

### Task 1 — Spec meaning
Make operator-authored items first-class in the SAME event-sourced model as
AI-emitted items WITHOUT a parallel `task-*` event family. Per C1: reuse
`action-added` (tag operator origin), `item-text-set` (edit), `reordered` (reorder),
`backlog-activated` (promote); add exactly ONE new event `item-removed`. `origin` is
an OPTIONAL reducer-read item field (operator|ai), NOT in `EVENT_REQUIRED_FIELDS`, so
every pre-existing `action-added` parses unchanged. Additive within ADR-032 schema
major 1 — no `SCHEMA_VERSION` bump.

### Task 1 — Edge cases covered
(a) Unknown item/node id on `item-removed` is rejected-AND-retained (state unchanged,
not crash, not silent-drop) — `state/reducer.js` item-removed case, NFR-2. (b) Same
`event_id` re-append is an idempotent no-op (cross-process append safety, I6). (c) An
operator edit of an AI item never flips origin: origin is derived from `ev.actor` ONLY
at the creating `action-added` and persisted (`state/reducer.js:508-535`), never
re-derived on `item-text-set`. (d) Snapshot attestation still verifies post-change
(P10 green). All asserted by P20 in `state/selftest.js`.

### Task 1 — Edge cases NOT covered
Concurrent multi-writer ordering beyond last-writer-wins + `event_id` idempotency is
out of scope (the append transport is `renameSync` + idempotency, not a distributed
lock — explicit I6 decision). A malformed `origin` VALUE on the wire is not the
reducer's job to reject — that is Task 2's server-side `validateOperatorPayload`
(envelope-validity vs payload-validity kept separate on purpose).

### Task 1 — Assumptions
The server forces `actor` (`gui`⇒operator, `dispatch`⇒ai), so the reducer trusts
`ev.actor` as the authoritative origin source without a client-supplied claim. The
snapshot carries no per-item actor, so origin MUST be persisted on the item (a
render-time re-derive would need a per-item log walk the renderer lacks) — this is why
store-vs-derive resolved to derive-then-persist (mirrors how `tier`/`serves_item_id`
are already persisted reducer-read fields).

### Task 2 — Spec meaning
`POST /api/event` ALREADY exists (`server/server.js`, forces `actor=gui`, appends via
the `appendEvent` facade, returns 400/422/409). Per C2: do NOT rebuild it — add
per-type operator-payload validation in front of the existing append and confirm
round-trip. The facade is the sole-normative write path (ADR-032 §8) and must never be
bypassed.

### Task 2 — Edge cases covered
Each operator event type returns a specific 422 BEFORE `appendEvent` runs: empty
`text` on `action-added`, bad `origin` enum, non-array `ordered_ids` on `reordered`,
empty `item_id` on `item-removed` (live-confirmed). A rejected malformed event never
reaches the log, so it cannot corrupt state (post-reject state shows the bad events
absent).

### Task 2 — Edge cases NOT covered
Authn/authz on the endpoint is unchanged (localhost passive-observer GUI per ADR-031;
no new auth surface). Rate-limiting/flood protection out of scope. The validator covers
operator-authoring event types only — it does not re-validate AI-dispatch events (those
flow through the emit path, not this endpoint).

### Task 2 — Assumptions
`validateOperatorPayload` before `appendEvent` is sufficient to keep the log clean
because the facade is the only writer and this endpoint is the only operator write
surface. Existing 400 (bad JSON) / 409 (attestation conflict) semantics remain correct
and are not duplicated by the new 422 layer.

### Task 6 — Spec meaning
A dedicated operator-owned surface listing all `origin=operator` items with full
in-surface authoring: add (in-surface input, NEVER `window.prompt` per C5), inline edit
(`item-text-set`), remove (`item-removed`), keyboard/button reorder (`reordered`, I4).
On write failure the inline edit REVERTS and shows an inline "not saved — retry"
affordance ON the row (I3, not just a toast). Removed items filter out. First-class
items, so they also feed cockpit counts + the project tree, but THIS is the authoring
surface.

### Task 6 — Edge cases covered
(a) Write-failure revert (I3): with POST rejected, text reverts to the original, the
row is marked `save-failed`, an inline `↻ not saved — retry` control appears on the row,
and the state file is unchanged — exercised in a real browser with fetch stubbed to
reject. (b) Reorder is keyboard/button-operable (▲/▼ with aria-labels, I4), not
drag-only. (c) Remove filters the item from the surface AND from the state file; a
sibling remains. (d) Add uses an in-surface `<input>` — zero `window.prompt` in the
My-tasks flow (`web/app.js` renderMyTasksInto/myTaskRow/reorderMyTask).

### Task 6 — Edge cases NOT covered
The 8 remaining `window.prompt` sites are in the decision/question CONTEXT-CARD
resolution surface (`web/app.js:1570-1678`), which C5 assigns to Tasks 4/8 —
deliberately untouched here, tracked as a retire-target. Per-item project/priority/
status editing (design "eventual") is not in this v1 batch (text/reorder/remove/add is
the shipped authoring set). Drag-reorder (vs keyboard) is a future enhancement; keyboard
is the accessible baseline.

### Task 6 — Assumptions
Color discipline holds: controls are neutral, amber is reserved for needs-you/blocked
(C6), only `--err` red is used for the retry affordance — so My-tasks does not introduce
the rainbow the tree color=status migration removes. The operator-items-as-first-class
model means the same items rendering in cockpit/tree later (Tasks 3/5) read the same
`origin=operator` tag this surface writes.
