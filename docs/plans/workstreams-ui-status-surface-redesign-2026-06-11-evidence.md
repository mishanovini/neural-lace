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

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Cockpit view: per-project status-count rows (fixed density) computed from the reduced state; waiting-count accent; click → project drill. — Verification: full
Verified at: 2026-06-12T02:44:22Z
Verifier: task-verifier agent

Oracle: specified — acceptance scenario `status-of-everything-at-a-glance`: one row per project with now/next/waiting/done counts, readable and non-overflowing even for the lopsided live data; counts must equal the reduced state. Exercised by an INDEPENDENT e2e oracle (regression.e2e.js ORACLE_SRC re-derives the four buckets from raw /api/state, separate from app.js's code) cross-checked against the rendered DOM.

Comprehension-gate: PASS (confidence 9) — Stage 1: all four canonical sub-sections present for Task 3; Stage 2: each substantive (well above 30 non-ws chars, no placeholders); Stage 3: every file:line claim spot-checked against the live code and diff 67bb3f3..f830be4 (statusCounts app.js:259 with disjoint/total C3 buckets shipped→done / isWaitingOnYou→waiting / committed→next / else→now; cockpitRows app.js:894 grouping the SAME allWorkItems() the filters read; zero-pill muted + waiting-accent-only-when->0 at app.js:1021-1026; shared `.ck-cols,.ck-row` grid at app.css:998) — all map; the "blocked sits in WAITING" assumption matches statusCounts exactly and is honestly flagged count-invisible (0 blocked in live data).

Checks run:
1. Live e2e re-run (fresh server on 7799 against a fresh COPY of today's live state — 124 items, one MORE than the builder's run, so the suite is not locked to a frozen fixture)
   Command: CONV_TREE_STATE_PATH=<copy> CTREE_PORT=7799 node server/server.js & then WS_URL=http://127.0.0.1:7799/ node scripts/regression.e2e.js
   Output: 17/17 PASS — T1 ckRows=6 4pills=true numeric=true treeItemsInCockpit=0; T2 all 6 project rows match the reduced state (independent oracle); T3 rowHeights 36..36px constant; T0 pageErrors=0
   Result: PASS
2. C3 phantom-state sweep — no invented closed/proposed in the status surface
   Command: grep -nE "'proposed'|'closed'" web/app.js + git diff 67bb3f3..f830be4
   Output: STATE_ICON now committed/in-flight/blocked/shipped only (diff REMOVED proposed/closed); COMPLETE_STATES={shipped:1}; the single remaining 'proposed' reference (app.js:1912) is PRE-EXISTING detail-modal code (Task 8 surface), not added by this diff
   Result: PASS
3. Data-path trace — counts derive from the reducer's snapshot, no parallel computation
   Output: SSE /api/events → S (app.js:2268-2270) → nodes() → allWorkItems() (app.js:328) → cockpitRows()+statusCounts() — same flattening the right-pane filters read; server serves readState().snapshot from the sole-normative state library
   Result: PASS
4. Runtime screenshot corroboration (committed artifacts)
   Output: cockpit-1280.jpg / cockpit-768.jpg — one fixed-height row per project, repo-grouped, four NUMBER pills on a shared grid; lopsided projects (Cross-project 8/52, neural-lace 25 next/10 waiting) each one row; amber accent only on waiting>0
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T2-cockpit-counts-match-reduced-state
Runtime verification: file neural-lace/workstreams-ui/web/app.js::cockpitRows

DEPENDENCY TRACE
================
Step 1: reducer folds the event log into the snapshot
  Verified at: state/reducer.js (untouched this diff); server.js safeRead()→readState().snapshot
Step 2: GUI receives the snapshot (SSE /api/events + /api/state)
  Verified at: web/app.js:2268-2270 (S = parsed snapshot); e2e T15 /api/health ok
Step 3: cockpit rows + counts derived from the same allWorkItems()+statusCounts() the filters read
  Verified at: web/app.js:894 cockpitRows / :259 statusCounts; e2e T2 oracle match
Step 4: operator sees one count-row per project; click drills
  Verified at: e2e T1/T3/T4; cockpit-1280.jpg

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js  (commit f830be4)
    - neural-lace/workstreams-ui/web/app.css (commit f830be4)
    - neural-lace/workstreams-ui/scripts/regression.e2e.js (commit f830be4)

Verdict: PASS
Confidence: 9
Reason: PROVEN: fresh e2e re-run this session (17/17 against a copy of TODAY'S live state, one item more than the builder's run) shows 6 cockpit rows whose four pills all match an independent /api/state-derived oracle, constant 36px row height with zero item chips in the cockpit; code trace confirms counts derive from the reducer snapshot via the same allWorkItems() path the filters use; C3 holds (proposed/closed removed from the status surface).

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Waiting-on-you global list: bounded filter (blocked-on-operator + unanswered decisions/questions); context-complete summary rows; detail-less items carry a visible "context incomplete" marker, never painted decision-ready. — Verification: full
Verified at: 2026-06-12T02:44:22Z
Verifier: task-verifier agent

Oracle: specified — the plan's Surface-2 contract: the ONLY globally-rendered item list, bounded by construction to unanswered Misha-asks + blocked work; rows show background + recommendation inline when details exist; an item whose details cannot support that must be visibly flagged. Exercised by the independent e2e oracle (needsYou re-derived from raw /api/state) plus the builder's live context-complete round-trip artifact.

Comprehension-gate: PASS (confidence 9) — Stage 1: four canonical sub-sections present for Task 4; Stage 2: substantive; Stage 3: file:line claims verified (waitingSummary app.js:498 returns null on absent/insufficient details; title-echo/≤20-char description rejected at :503-507; recommendation string-AND-fence duality at :510-514; waitingRow neutral dashed ctx-incomplete-badge at :519+app.css:1098 — deliberately NEUTRAL so amber stays exclusive to needs-you; blocked badge with blocked_on edge at :543-544; renderWaitingInto→applyFilter('awaiting-me')→isWaitingOnYou at :551/:378/:248). The "ALL blocked items included (safe direction)" assumption matches isWaitingOnYou exactly; the honest NOT-covered boundary (presence-based summary check, full per-kind validation is Task 8's gate) is correctly scoped — Task 4's obligation is never to lie about readiness, which the bare=0 assertion proves.

Checks run:
1. Live e2e re-run — boundedness + no-bare-rows
   Command: WS_URL=http://127.0.0.1:7799/ node scripts/regression.e2e.js (fresh server, fresh state copy)
   Output: T10 waitRows=20 (oracle=20) ctx=0 incomplete=20 bare=0 — rendered row set === independent isWaitingOnYou oracle set; all 20 detail-less live items carry the visible incomplete marker, zero painted decision-ready
   Result: PASS
2. Context-COMPLETE inline path (builder's live round-trip, corroborated by committed artifact)
   Output: waiting-context-complete-1280.jpg — a decision POSTed with details (background/options/recommendation) renders wait-bg + "→ option B —…" recommendation inline with NO incomplete badge; code path waitingSummary→wait-ctx confirmed at app.js:529-534
   Result: PASS
3. Single-predicate discipline — list, cockpit pill, and tree amber all share isWaitingOnYou
   Output: applyFilter case 'awaiting-me' (app.js:383), statusCounts waiting bucket (app.js:264), treeItemRow needs (app.js:1249) all call isWaitingOnYou (app.js:248) — the three surfaces cannot disagree
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T10-waiting-bounded-no-bare-rows
Runtime verification: file neural-lace/workstreams-ui/web/app.js::isWaitingOnYou

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js     (commit f830be4)
    - neural-lace/workstreams-ui/web/index.html (commit f830be4 — chip relabeled "Waiting on you")

Verdict: PASS
Confidence: 9
Reason: PROVEN: fresh e2e re-run shows the list bounded to exactly the independent oracle's 20-item needs-you set with bare=0 (every detail-less item visibly flagged "context incomplete — needs enrichment", none decision-ready); the context-complete inline path is proven by the live POST round-trip artifact; one shared isWaitingOnYou predicate drives list, cockpit pill, and tree amber so the surfaces agree by construction.

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Per-project tree: color=status / icon=kind / amber needs-you dot + open-count badges; focusable twists (aria-expanded); collapse-done default + "show done"; C4 breadcrumb return; C6 kind-color retirement. — Verification: full
Verified at: 2026-06-12T02:44:22Z
Verifier: task-verifier agent

Oracle: specified — acceptance scenario `drill-into-a-project-tree` (+ binding corrections C4/C6): nested tree with guide lines bounded to one project; amber marks ONLY needs-you/blocked; done muted; keyboard expand/collapse; persistent breadcrumb return. The C6 prove-it ("amber on any non-needs-you row = zero") is asserted bidirectionally by the e2e against the rendered DOM.

Comprehension-gate: PASS (confidence 9) — Stage 1: four canonical sub-sections present for Task 5; Stage 2: substantive; Stage 3: claims verified against code+diff (branchGroup real <button class="twisty"> with aria-expanded+aria-label at app.js:1198/1205-1209; branchExpanded default !allDone at :1183/:1202; expand-a-done-branch reveals items via allDone||visibleInTree at :1223 with "N done hidden" note at :1225-1228; per-project branch-state key at :1182; treeItemRow color=STATUS class + needs-you amber edge only via isWaitingOnYou at :1247-1254, kind GLYPH icon at :1259, muted done check at :1263; C4 breadcrumb at :1064 + rail app.css:1034 + ≤560px full swap app.css:1079 + drill persistence app.js:59; C6 retirement sweep real — app.css has exactly 2 hits for retired kind-color classes, BOTH comments; app.js zero; st-committed/in-flight re-keyed to grays at app.css:875-885). Honest NOT-covered items (remaining .chip-warn filter chips → Task 10; det-incomplete-badge amber is the pre-existing modal → Task 8 surface; 560px breakpoint judgment call satisfying the ≤390 requirement) are accurate and within scope boundaries; no assumption contradicted.

Checks run:
1. Live e2e re-run — drill + amber discipline + a11y + done-collapse + return path
   Command: WS_URL=http://127.0.0.1:7799/ node scripts/regression.e2e.js (fresh server, fresh state copy)
   Output: T4 drill bounded (neural-lace, 35 items, 10 branch rails, +29px indent, rail=true); T5 amberRows=10 mismatches=0 (amber set === oracle needs-set, both directions); T6 kindColorClasses=0, 35 neutral kind glyphs; T7 aria-expanded true→false via keyboard Enter; T8 all-done branches expandedByDefault=0, show-done reveals 8→23 and reverts; T9 breadcrumb returns to cockpit; T16 390px rail hidden + breadcrumb present
   Result: PASS
2. C6 static sweep (re-run independently, not trusted from the evidence file)
   Command: grep -nE '\.k-action|\.k-decision|\.k-question|li-kind\.|kind-action|kind-decision|kind-question|ti-badge\.k-' web/app.css web/app.js
   Output: app.css 2 hits — both retirement comments (lines 370, 825); app.js 0 hits; STATE_ICON has no proposed/closed; amber rules target only .needs-dot/.tree-item.needs-you/.ck-pill.accent/.rg-wait (+ pre-existing modal/filter-bar UI outside the row discipline)
   Result: PASS
3. C5 — no new window.prompt in this diff
   Command: git diff 67bb3f3..f830be4 -- web/app.js | grep '^+.*window.prompt'
   Output: zero added; the 8 call sites (app.js:1829-1937) are all pre-existing detail-modal code = Task 8 scope per the binding correction
   Result: PASS
4. Runtime screenshot corroboration
   Output: drill-1280.jpg — rail + "← All projects" breadcrumb + project header + branch groups with twisty/needs-dot/open-count badges + guide lines + glyph icons, amber edges only on needs-you rows; drill-390.jpg — full swap, breadcrumb present
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T5-amber-set-equals-needs-set
Runtime verification: file neural-lace/workstreams-ui/web/app.js::branchGroup

DEPENDENCY TRACE
================
Step 1: cockpit row click → setDrill(projectId)
  Verified at: web/app.js:1028 (cockpitRow click) → :947 setDrill; e2e T4
Step 2: renderDrill consumes the SAME cockpitRows() refs (reducer-derived)
  Verified at: web/app.js:1037-1042; no parallel data path
Step 3: renderProjectTree → branchGroup → treeItemRow render the bounded tree
  Verified at: web/app.js:1108/:1198/:1247; e2e T4/T5/T6
Step 4: keyboard expand/collapse + breadcrumb return
  Verified at: web/app.js:1205-1209 (button twisty aria-expanded) / :1064 (breadcrumb); e2e T7/T9/T16

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js  (commit f830be4)
    - neural-lace/workstreams-ui/web/app.css (commit f830be4)

Verdict: PASS
Confidence: 9
Reason: PROVEN: fresh e2e re-run (17/17) asserts the drilled tree is bounded, the rendered amber set equals the independent needs-you oracle set with zero mismatches in both directions, zero kind-color classes survive in the DOM, the twisty is a real keyboard-operable aria-expanded button, all-done branches collapse by default with a working show-done toggle, and the breadcrumb restores the cockpit at 1280 and 390px; my own static C6 sweep confirms the retirement (2 comment-only hits in app.css, 0 in app.js) and zero window.prompt lines were added.

EVIDENCE BLOCK
==============
Task ID: 7
Task description: Backlog surface: same edit pattern + promote-to-task. — Verification: full
Verified at: 2026-06-12T20:35:00Z
Verifier: task-verifier agent

Oracle: specified — the task's Prove-it (add a backlog item; promote it; it moves to the active list / Next and out of backlog) + binding corrections C1 (promote = the EXISTING `backlog-activated`, no new event type), C5 (zero window.prompt), I3 (write-error revert + inline retry).

Comprehension-gate: PASS (confidence 9) — Stage 1: all four canonical sub-sections present for Task 7 in tasks-7-8.evidence.md; Stage 2: substantive, specific, honest NOT-covered list (double-failure promote dupe, legacy-capture edit/remove vocabulary gap, archived-node parked items); Stage 3 diff-correspondence against b13f7dd..c9a34a1 verified by direct read: myTaskRefs backlogged-exclusion at app.js:359-362 + my-tasks filter at :400 exactly as claimed; buildPromoteEvents at :964-982 creates the lazy mirror (`backlog-added` only when absent), uses the EXISTING `backlog-activated`, repairs stale mirror title via `branch-retitled`; postSeq stable pre-generated event_ids at :927-936 (idempotent retry resume). No assumption contradicted. (Three-stage rubric executed directly by this verifier — comprehension-reviewer agent dispatch unavailable in this environment; rubric per ~/.claude/agents/comprehension-reviewer.md stages.)

Checks run:
1. Live e2e re-run (fresh server on 7799 against a COPY of today's live state; operator's 7733/real file untouched)
   Command: CONV_TREE_STATE_PATH=<tmp-copy> CTREE_PORT=7799 node server/server.js & then WS_URL=http://127.0.0.1:7799/ node scripts/regression.e2e.js
   Output: T17 PASS — add=true inMyTasksBeforePromote=false leftBacklog=true task=true/committed/operator activatedRoot=backlog-activated inMyTasksAfter=true; suite 21/21 on second run (first run 20/21 — T10, a Task-4 lock, failed ONLY its >=1 non-vacuity guard because today's live state has zero waiting items: rows=0 === oracle=0, bare=0; re-run with items present passed T10 non-vacuously waitRows=1 oracle=1)
   Result: PASS
2. C1 — no new event type
   Command: git diff b13f7dd..58b23c2 -- neural-lace/workstreams-ui/state/schema.js state/reducer.js state/selftest.js (empty diff) + grep schema.js for item-promoted/task-added/task-edited/task-removed
   Output: state layer diff EMPTY across Tasks 7/8/9; zero matches for any new event name; EVENT_TYPES unchanged
   Result: PASS
3. C5 — zero native prompts
   Command: grep -c "window.prompt" neural-lace/workstreams-ui/web/app.js
   Output: 0; e2e T20 window.prompt-in-source=0 nativeDialogsFired=0 (suite-wide counter)
   Result: PASS
4. C2 per-type 422 guards for the backlog events
   Command: read server/server.js:158-178
   Output: backlog-added (non-empty text), item-backlogged (item_id+node_id), branch-retitled (non-empty title) guards present
   Result: PASS
5. State selftest
   Command: node neural-lace/workstreams-ui/state/selftest.js
   Output: 21 passed, 0 failed
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T17-backlog-add-promote-roundtrip
Runtime verification: file neural-lace/workstreams-ui/web/app.js::buildPromoteEvents
Runtime verification: file neural-lace/workstreams-ui/server/server.js::backlog-added

DEPENDENCY TRACE
================
Step 1: operator types in the Backlog "+ add" input
  Verified at: web/app.js renderBacklogInto/addBacklogItem (:600-921); e2e T17 add=true
Step 2: POST /api/event (item-backlogged path) with per-type 422 guards
  Verified at: server/server.js:158-178; C2 guard read
Step 3: promote click → buildPromoteEvents → existing backlog-activated (+ lazy mirror)
  Verified at: web/app.js:964-982; e2e T17 activatedRoot=backlog-activated
Step 4: item leaves Backlog, appears committed/Next in My-tasks + cockpit counts
  Verified at: e2e T17 leftBacklog=true inMyTasksAfter=true task state=committed; screenshot backlog-promoted-1280.jpg

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js     (commits 58db4d9, 0de8da4)
    - neural-lace/workstreams-ui/server/server.js (commit 0de8da4)
    - neural-lace/workstreams-ui/scripts/regression.e2e.js (commit c4db22b)

Verdict: PASS
Confidence: 9
Reason: PROVEN: I re-ran the full e2e myself against a fresh state copy — T17 demonstrates the complete user bar (in-surface add → row in Backlog and NOT in My-tasks → promote → out of backlog, committed task in the active list on a backlog-activated root); the empty state-layer diff plus my schema grep prove C1 (promote reuses the existing event vocabulary, zero new event types); C5 grep returns zero and the suite's native-dialog counter is zero.

EVIDENCE BLOCK
==============
Task ID: 8
Task description: Context-card + gate: per-kind required-field templates; progressive-disclosure render; context-incomplete flag for items missing required fields. — Verification: full
Verified at: 2026-06-12T20:36:00Z
Verifier: task-verifier agent

Oracle: specified — acceptance scenario `open-a-context-complete-decision` (both paths) + binding corrections I1 (consume the sole-normative assembleItemDetails/validateItemDetails; no parallel validator), I2 (suppress ALL resolving buttons on incomplete), C5 (all 8 window.prompt sites retired).

Comprehension-gate: PASS (confidence 9) — Stage 1: all four canonical sub-sections present for Task 8 in tasks-7-8.evidence.md; Stage 2: substantive with honest NOT-covered items (Task-4 waiting-row prose heuristic vs context_state row/card parity deferred to Task 10/11; enrichment round-trip is Task 9's emit side; firstSentences clamp limitation); Stage 3 diff-correspondence verified by direct read: server.js defensive require at :40-48 (degraded mode → no annotation → client gate fails CLOSED), gateCategoryOf + annotateContextState at :79-99 deriving context_state via dcs.assembleItemDetails(cat,de)!==null at serve time on a per-request parse (never persisted), buildActionButtons I2 early-return at app.js:2381-2387 (gate note + single respond/enrichment channel, zero resolving/lifecycle buttons). The stated assumption that the browser cannot require the Zod module (hence serve-time annotation) is consistent with the architecture as read. No assumption contradicted. (Three-stage rubric executed directly by this verifier — comprehension-reviewer dispatch unavailable in this environment.)

Checks run:
1. Live e2e re-run (fresh server on 7799 against a state COPY)
   Command: WS_URL=http://127.0.0.1:7799/ node scripts/regression.e2e.js
   Output: T18 PASS — card=true bg=true opts=2 meaning=true choose=2 rec=true reply=true more=true approve=true inSurfaceForm=true respondedRecorded=true (context-complete decision posted via /api/event against the copy; reply recorded via in-surface form); T19 PASS — "context incomplete — needs enrichment" panel, gateNote=true, buttons=1 (respond-only), resolving=0; T20 PASS — window.prompt-in-source=0, nativeDialogsFired=0
   Result: PASS
2. I1 — no parallel validator in the client
   Command: grep -n "assembleItemDetails|validateItemDetails|ItemDetailsContentSchema|decision-context-schema" web/app.js + grep context_state
   Output: only a comment (app.js:2035-2037) references the module; the gate predicate reads the server annotation (`it.context_state !== 'complete'` at :2047); per-kind required-field logic exists ONLY in state/decision-context-schema.js, consumed server-side via the boot-safe defensive require (server.js:40-48)
   Result: PASS
3. I2 — action suppression
   Command: read app.js:2355-2390 (buildActionButtons)
   Output: contextGateBlocks(it) early-return renders ONLY the dm-gate-note + the respond/enrichment channel; behaviorally confirmed by T19 resolving=0
   Result: PASS
4. C5 — all 8 prompt sites retired
   Command: grep -c "window.prompt" web/app.js
   Output: 0 (token absent entirely); suite-wide native-dialog counter fired 0 times across all 21 tests
   Result: PASS

Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T18-context-complete-card
Runtime verification: playwright neural-lace/workstreams-ui/scripts/regression.e2e.js::T19-gate-suppresses-resolving-buttons
Runtime verification: file neural-lace/workstreams-ui/server/server.js::annotateContextState

DEPENDENCY TRACE
================
Step 1: item details land in state (item-details-set) / or are absent
  Verified at: state layer unchanged (empty diff); reducer forward-tolerant details
Step 2: server annotates context_state at serve time via the sole-normative assembler
  Verified at: server/server.js:79-99 (gateCategoryOf + annotateContextState; dcs.assembleItemDetails null = incomplete); degraded mode fails CLOSED (:40-48)
Step 3: client reads the annotation; gate decides actionability
  Verified at: web/app.js:2047 (contextGateBlocks reads context_state); :2381-2387 early-return
Step 4: complete card renders essentials + in-surface reply; incomplete renders needs-enrichment with zero resolving buttons
  Verified at: e2e T18/T19; screenshots context-complete-1280.jpg / context-incomplete-1280.jpg

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/app.js     (commits 58db4d9, 0de8da4)
    - neural-lace/workstreams-ui/web/app.css    (commit 0de8da4)
    - neural-lace/workstreams-ui/server/server.js (commits 0de8da4, c4db22b — boot-safe zod require)

Verdict: PASS
Confidence: 9
Reason: PROVEN: I re-ran the e2e myself — T18 demonstrates the context-complete decision card (background, options with meaning+risk, per-option Choose, recommendation, reply phrasing, "More context" expand, reply recorded via in-surface form) and T19 demonstrates the gate (needs-enrichment panel, exactly one respond-only button, zero resolving buttons); my own greps prove I1 (client carries no validator — completeness is derived server-side by the sole-normative assembleItemDetails, fail-closed when zod is missing) and C5 (zero window.prompt in source, zero native dialogs fired).

EVIDENCE BLOCK
==============
Task ID: 9
Task description: Emit discipline: extend the emit path so a raised decision/question carries the context payload (maps to decision-context.md fences); document the contract. — Verification: full
Verified at: 2026-06-12T20:38:00Z
Verifier: task-verifier agent

Oracle: specified (the in-flight 2026-06-12 file-scope contract: per-kind context payloads as sibling item-details-set validated through the sole-normative module — valid→normalized, invalid→raw+WARN, absent→detail-less+WARN, NEVER blocks) + derived (the hook's own pre-existing ST1-ST36/BD1-BD10 self-test suite must stay green alongside the new ST37-ST42 locks).

Comprehension-gate: PASS (confidence 9) — Stage 1: all four canonical sub-sections present in task-9.evidence.md; Stage 2: substantive, with an honest gap-diagnosis table and honest NOT-covered items (no backfill of the ~124 detail-less live items per plan Scope OUT; workstreams-task-bridge.js TaskCreate mirrors logged as follow-up; cloud-session blind spot documented-not-solved); Stage 3 diff-correspondence against c9a34a1..58b23c2 verified by direct read: INVALID→raw+WARN at workstreams-emit.sh:1824-1826, absent→born-context-incomplete WARN at :1834, content-hashed det_ev_id at :1845 (emit-item) and :1908 (emit-details — the ST42 last-writer-wins fix), spawn no-sentinel guard at :756-760, builder ev_det FIXED-derivation honesty comment at :2027-2036 (the salvage fix — re-fires dedupe AND cannot clobber later content-hashed enrichment). Assumptions verified: reducer treats details as forward-tolerant LWW; appendEvent dedupes per event_id; the GUI gate (Task 8, verified above) consumes the same module. decision-context-gate.sh untouched, matching the "only if needed: not needed" claim. (Three-stage rubric executed directly by this verifier — comprehension-reviewer dispatch unavailable in this environment.)

Checks run:
1. Full self-test, real-module path (this checkout resolves the repo schema module; zod present in workstreams-ui/node_modules)
   Command: bash adapters/claude-code/hooks/workstreams-emit.sh --self-test
   Output: 66 passed, 0 failed (ST37/37b/37c normalize+stamp; ST38/38b invalid→raw+WARN; ST39a-c absent→emit+WARN; ST40/40b/41/41b spawn sentinels; ST42/42b content-hashed revision; ST1-ST36 + BD1-BD10 regressions green)
   Result: PASS
2. Full self-test, inline-floor path (module deliberately unloadable)
   Command: DECISION_CONTEXT_SCHEMA=/nonexistent/schema.js bash adapters/claude-code/hooks/workstreams-emit.sh --self-test
   Output: 66 passed, 0 failed — the same-contract inline floor holds in stripped envs
   Result: PASS
3. Live demo re-derived by this verifier (TEMP state file via CONV_TREE_STATE_PATH; operator's tree untouched)
   Command: --emit-branch; --emit-item decision WITH full per-kind payload; --emit-item question with NO payload; then read state + validate via the sole-normative module
   Output: rc=0/rc=0; decision details landed normalized (_category=decision, surfaced_by=workstreams-emit, options=2) and validateItemDetails.success=true via state/decision-context-schema.js; question landed detail-less; audit log carries the exact born-context-incomplete WARN referencing rules/workstreams-state.md "Context-complete item emission"
   Result: PASS
4. Contract documentation present
   Command: grep "Context-complete item emission" adapters/claude-code/rules/workstreams-state.md; grep emit-side cross-ref in rules/decision-context.md
   Output: section at workstreams-state.md:64 + Enforcement-table row at :114; decision-context.md:212 names all consumers of the single module ("no parallel payload schema anywhere")
   Result: PASS
5. Scope compliance
   Command: git diff --stat c9a34a1..58b23c2
   Output: exactly the four declared files (workstreams-emit.sh, workstreams-state.md, decision-context.md, task-9.evidence.md); decision-context-gate.sh untouched; state layer untouched
   Result: PASS
6. Live-mirror sync status (flagged, non-blocking)
   Command: diff -q adapters/claude-code/{hooks/workstreams-emit.sh,rules/workstreams-state.md,rules/decision-context.md} ~/.claude/...
   Output: all three DIFFER — ~/.claude mirror predates Task 9 (Jun 10 mtime; zero Task 9 helpers). The emit discipline is NOT live in running sessions until the merge-time install/sync propagates it. Same class as merge-to-master: a plan-closure step, not a task-build gap. MUST be performed at plan closure.
   Result: SKIPPED (closure-step flag — propagation happens at merge per the two-layer-config convention; the canonical artifact is fully verified)

Runtime verification: test adapters/claude-code/hooks/workstreams-emit.sh::--self-test-66-of-66-both-schema-paths
Runtime verification: file adapters/claude-code/hooks/workstreams-emit.sh::_normalize_item_details
Runtime verification: file adapters/claude-code/rules/workstreams-state.md::Context-complete item emission

DEPENDENCY TRACE
================
Step 1: orchestrator raises an item with .details via --emit-item (or sentinels via --on-spawn)
  Verified at: workstreams-emit.sh:1807-1860 / :555-578; live demo rc=0
Step 2: payload normalized/validated through the sole-normative module (env-override + repo resolution mirrors decision-context-gate.sh)
  Verified at: _resolve_schema_lib :646-659, _normalize_item_details :687-755; ST37 family
Step 3: sibling item-details-set lands in the same batch (content-hashed id → enrichment LWW)
  Verified at: :1845/:1908; live demo event landed; ST42/ST42b
Step 4: the GUI's Task-8 gate consumes the same module's verdict → context-complete card renders
  Verified at: server.js annotateContextState (Task 8 PASS above); validateItemDetails.success=true on the demo payload — "valid here" === "actionable there"

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/hooks/workstreams-emit.sh  (commits 335e99a, dab16a7)
    - adapters/claude-code/rules/workstreams-state.md (commit 0b7cead)
    - adapters/claude-code/rules/decision-context.md  (commit 0b7cead)

Verdict: PASS
Confidence: 9
Reason: PROVEN: I re-ran the 66-scenario self-test on BOTH schema paths (real module and forced inline floor) and replayed the live demo against a temp state file — a payload-bearing decision lands as decision-raised + a sibling item-details-set whose normalized payload validates success=true through the sole-normative module, and a payload-less question still lands (exit 0, never blocked) born honestly detail-less with the contract-referencing WARN; the contract is documented in workstreams-state.md with the cross-ref in decision-context.md. Flag for plan closure: the ~/.claude live mirror predates this work — sync at merge or the live emit path stays pre-Task-9.
