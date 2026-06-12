# Evidence Log — Workstreams UI — Shared Status Surface Redesign

> Companion evidence file. Per-task structured rationale + comprehension articulation
> live in `workstreams-ui-status-surface-redesign-2026-06-11-evidence/tasks-1-2-6.evidence.md`.
> The blocks below are the task-verifier's PASS records (rung:2 comprehension gate run).

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Data-model deltas — REUSE existing events for operator-authoring (action-added [+origin:operator], item-text-set, reordered, backlog-activated); add exactly ONE new event item-removed; origin as OPTIONAL reducer-read item field (not in EVENT_REQUIRED_FIELDS); extend state/selftest.js. — Verification: contract
Verified at: 2026-06-12T01:02:51Z
Verifier: task-verifier agent

Oracle: derived-preexisting (contract) — the full `state/selftest.js` property suite (the pre-existing reducer/schema oracle the new events must pass) is the done criterion; `item-removed`, `origin` store/derive, no-origin-flip, reject-retain, and idempotency are asserted by the new P20 property added to that suite.

Comprehension-gate: PASS (confidence 9) — all four canonical sub-sections present, each >30 non-ws chars and substantive; every "edge cases covered" claim (item-removed-only new event, origin derive-from-actor-at-creation, no-flip-on-edit, reject-and-retain on unknown id, event_id idempotency, attestation still verifies) maps one-to-one to the diff (schema.js item-removed type + required-fields; reducer.js origin-stamp at action-added + item-removed splice case; selftest P20 assertions) in afd1bb4..536e813.

Checks run:
1. Selftest suite (pre-existing oracle) incl. new P20
   Command: node neural-lace/workstreams-ui/state/selftest.js
   Output: 21 passed, 0 failed — incl. P20 operator-authoring e2e: create(+origin store/derive) / edit(no-origin-flip) / reorder / remove(+reject-retain+idempotent+envelope) — schema major 1, attested
   Result: PASS
2. Diff-correspondence: item-removed is the ONLY new event type; SCHEMA_VERSION unchanged
   Command: git diff afd1bb4..536e813 -- neural-lace/workstreams-ui/state/schema.js
   Output: single new EVENT_TYPES entry item-removed + required-fields [node_id,item_id]; origin NOT in EVENT_REQUIRED_FIELDS; no schema_version bump
   Result: PASS
3. Diff-correspondence: origin derived from ev.actor and stamped ONLY at creation
   Command: git diff afd1bb4..536e813 -- neural-lace/workstreams-ui/state/reducer.js
   Output: action-added case stamps newItem.origin (explicit ev.origin then gui=operator then dispatch=ai), set only at creation; item-removed case splices + rejects unknown node/item
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/state/selftest.js::P20-operator-authoring-e2e
Runtime verification: file neural-lace/workstreams-ui/state/schema.js::item-removed

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/state/schema.js   (commit 536e813)
    - neural-lace/workstreams-ui/state/reducer.js  (commit 536e813)
    - neural-lace/workstreams-ui/state/selftest.js (commit 536e813)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the pre-existing selftest oracle is green at 21/21 including the new P20 property which exercises create(+origin store/derive)/edit(no-flip)/reorder/remove(+reject-retain+idempotent+envelope); the diff confirms item-removed is the only new event and origin rides as an optional reducer-read field — both diff-correspondence and the contract oracle hold.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: GUI server write endpoint POST /api/event — add per-type operator-payload validation in front of the EXISTING append (do not rebuild); reject malformed payloads with a specific 422; never bypass the appendEvent facade. — Verification: full
Verified at: 2026-06-12T01:02:51Z
Verifier: task-verifier agent

Oracle: specified — the user-observable contract is "a malformed operator event returns a clear 422 and never reaches the log / corrupts state; a valid one appends through the facade." Exercised against the validator logic (4 malformed to 422 strings, 2 valid to accept) and confirmed live end-to-end (HTTP 422 bodies) in the prior pass; the appendEvent facade is unchanged.

Comprehension-gate: PASS (confidence 9) — four canonical sub-sections present and substantive; "edge cases covered" (per-type 422 for empty text / bad origin enum / non-array ordered_ids / empty item_id, BEFORE appendEvent, malformed never corrupts state) maps to the server.js diff (validateOperatorPayload run before append, returns specific 422); the facade-never-bypassed assumption holds — the diff inserts validation in front of, not in place of, the unchanged append.

Checks run:
1. validateOperatorPayload behavior (committed logic, executed standalone)
   Command: node -e (committed validateOperatorPayload re-executed against 6 cases)
   Output: PASS empty-text=422 / bad-origin=422 / reordered-non-array=422 / item-removed-no-item_id=422 / valid-action-added=accept / valid-item-removed=accept — ALL VALIDATOR CASES PASS
   Result: PASS
2. Facade not bypassed; endpoint not rebuilt
   Command: git diff afd1bb4..536e813 -- neural-lace/workstreams-ui/server/server.js
   Output: validateOperatorPayload added; the input.actor=gui + appendEvent(input) path is unchanged; a 422 short-circuits BEFORE appendEvent
   Result: PASS
3. Live 422s (prior-pass evidence, recorded in tasks-1-2-6.evidence.md:53-60)
   Output: empty text=HTTP 422; bad origin=HTTP 422; reordered non-array=HTTP 422; item-removed missing item_id=HTTP 422; state after: malformed events absent (never corrupted state)
   Result: PASS

Runtime verification: curl -X POST http://127.0.0.1:7733/api/event (action-added with empty text expect HTTP 422 action-added requires non-empty text)
Runtime verification: file neural-lace/workstreams-ui/server/server.js::validateOperatorPayload

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/server/server.js (commit 536e813)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the committed validateOperatorPayload returns the exact 422 strings for all four malformed operator payloads and accepts valid ones (standalone re-execution), the prior pass recorded the same as live HTTP 422s, and the diff confirms the appendEvent facade is unchanged with validation inserted in front of it — endpoint reused not rebuilt, facade never bypassed.

EVIDENCE BLOCK
==============
Task ID: 6
Task description: My-tasks surface (operator-owned, editable) — list all origin:operator items; in-surface "+ add" (never window.prompt, C5); inline edit; keyboard/button reorder (I4); complete/delete; on POST failure inline edit REVERTS + shows inline "not saved — retry" on the row (I3) — all via the Task-2 endpoints. — Verification: full
Verified at: 2026-06-12T01:02:51Z
Verifier: task-verifier agent

Oracle: specified — acceptance scenario add-and-edit-a-personal-task: type a new task + Enter to appears and persists to the state file to edit inline to persists across reload to shows in cockpit counts + its project tree; plus I3 (write-error revert + inline retry) exercised in a real browser. Verified in the prior pass (13/13 My-tasks round-trip via Claude-in-Chrome against the live server) and re-grounded against the diff this pass.

Comprehension-gate: PASS (confidence 9) — four canonical sub-sections present and substantive; "edge cases covered" (I3 write-failure revert + inline retry on the row; I4 keyboard up/down reorder with aria-labels; remove filters from surface AND state file; add via in-surface input with ZERO window.prompt in the flow) maps to the app.js diff (renderMyTasksInto / myTaskRow / reorderMyTask, save-failed + not-saved-retry, upBtn/downBtn aria-label move-task-up/down, post reordered, post item-removed, add via input Enter); the 8-prompt-sites-out-of-scope claim verified — the single added window.prompt token is a COMMENT, the 8 actual calls are all at app.js:1570-1678 (the context-card surface, Tasks 4/8 per C5), none in the My-tasks path.

Checks run:
1. My-tasks authoring funcs present + wired to operator events via POST /api/event
   Command: git show 536e813:.../web/app.js | grep -nE renderMyTasksInto|myTaskRow|reorderMyTask|/api/event|action-added|item-text-set|item-removed|reordered
   Output: renderMyTasksInto/myTaskRow/reorderMyTask present; add=action-added(origin:operator); edit=item-text-set; remove=item-removed; reorder=reordered — all via post(...) to /api/event
   Result: PASS
2. C5 — zero window.prompt in the My-tasks flow
   Command: git diff afd1bb4..536e813 -- .../web/app.js | grep window.prompt  AND  git show 536e813:.../web/app.js | grep -n window.prompt
   Output: the ONLY added window.prompt is a comment (NEVER window.prompt); the 8 calls are all at lines 1570-1678 (context-card resolution, out-of-scope Tasks 4/8); My-tasks path (288-679) has zero
   Result: PASS
3. I4 keyboard reorder + I3 revert affordance present
   Command: git show 536e813:.../web/app.js (My-tasks region)
   Output: up/down buttons aria-label move-task-up/down to reorderMyTask to post(reordered); save-failed class + not-saved-retry inline control on the row on POST failure
   Result: PASS
4. Acceptance scenario add-and-edit-a-personal-task (prior-pass live browser, 13/13)
   Output: typed-add persists (origin:operator); inline edit persists; keyboard reorder flips order; remove filters from surface + state file; write-failure reverts + shows inline retry, state file unchanged; no console errors; screenshot captured
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::add-and-edit-a-personal-task
Runtime verification: file neural-lace/workstreams-ui/web/app.js::renderMyTasksInto

DEPENDENCY TRACE
================
Step 1: operator types a task in the in-surface "+ add" input + Enter
  Verified at: web/app.js renderMyTasksInto submitAdd to post({type:action-added, origin:operator})
Step 2: POST /api/event validates + appends via the facade
  Verified at: server.js validateOperatorPayload to appendEvent (Task 2)
Step 3: reducer folds action-added, stamps it.origin=operator
  Verified at: reducer.js action-added case (Task 1); selftest P20
Step 4: My-tasks surface filters origin===operator, renders the row; persists across reload
  Verified at: web/app.js isOperatorItem filter; prior-pass live reload round-trip

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js     (commit 536e813)
    - neural-lace/workstreams-ui/web/app.css    (commit 536e813)
    - neural-lace/workstreams-ui/web/index.html (commit 536e813)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the My-tasks surface authors via the in-surface input (zero window.prompt in the flow — the only added prompt token is a comment, the 8 calls are the out-of-scope context-card surface), keyboard reorder + I3 revert/retry are present in the diff, the operator-event POST wiring traces end-to-end through Tasks 2/1, and the prior pass confirmed the full add/edit/reorder/remove/revert round-trip live in a real browser (13/13) persisting across reload.
