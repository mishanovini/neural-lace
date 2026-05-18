# Evidence Log — Conversation Tree UI v1.1 UX interactivity (items 7–13)

## Task 1 — Phase A item 7 (+12,13): list anim, undo snackbar, 10s timer, ✕-cancels-undo

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Phase A — item 7 (+12,13): list enter/leave slide+fade (~200ms), new-item flash, undo snackbar; toast auto-dismiss 5s→10s; toast manual ✕ that also cancels the pending Undo
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: web/app.js snackbar(msg,opts) + _pendingUndo + 10000/2600 timer + sb-undo/sb-x
   Command: grep -n "snackbar\|_pendingUndo\|10000\|2600\|sb-undo\|sb-x\|item-unchecked" web/app.js
   Output: line 63 function snackbar(msg,opts); line 83 dur = opts.duration || (_pendingUndo ? 10000 : 2600); line 72/78 sb-undo/sb-x buttons; line 74 ✕→closeToast then if(fn)fn() (undo runs); line 583 undo posts item-unchecked; line 748/945 activate/archive undo wired
   Result: PASS
2. Wire-check: index.html #toast + app.css snackbar/.flash/keyframes/reduced-motion
   Command: grep -n in web/index.html, web/app.css
   Output: index.html:30 #toast role=status; app.css:318 .li.flash keyframes; app.css:92 snackbar flex; app.css:352 @media prefers-reduced-motion (edge case honoured)
   Result: PASS
3. Functionality (responsive selftest covers item-7/12/13 invariants)
   Command: node web/responsive.selftest.js
   Output: R23 snackbar undo+✕ 10s vs 2.6s PASS; R24 ✕→closeToast cancels pending undo PASS; R25 actWithUndo leave-anim→silent post→undo snackbar PASS; R26 enter/leave/flash keyframes + reduced-motion PASS; 33 passed, 0 failed
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R23
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R24
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R25
Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P15

DEPENDENCY TRACE
================
Step 1: user clicks "mark done" on an action
  ↓ Verified at: web/app.js:101-108 actWithUndo optimistic post + leave-anim + snackbar(okMsg+' — Undo?')
Step 2: snackbar shows with Undo + ✕, 10s timer
  ↓ Verified at: web/app.js:63-83 (10000ms when _pendingUndo set); responsive R23
Step 3: Undo posts inverse item-unchecked → item re-surfaces
  ↓ Verified at: web/app.js:583 post item-unchecked; reducer.js case 'item-unchecked' it.checked=false; state/selftest.js P15 round-trip green
Step 4: ✕ closes immediately AND cancels pending undo (item 13)
  ↓ Verified at: web/app.js:78-79 closeToast clears _pendingUndo+timer; responsive R24

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/web/app.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.css  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/index.html  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: snackbar/undo/10s/✕-cancels-undo wire-chain present in committed code, exercised live (captured trace) AND covered by green responsive R23-R26 + selftest P15 round-trip.

## Task 2 — Phase A item 8: per-pane "+N new" badge

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Phase A — item 8 (cheap): per-pane "+N new" badge in the pane-head when SSE delivers new actions/backlog while that pane isn't the focused tab/scrolled; clears when the user views the pane
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: index.html badge spans → app.js diff + primed-first-frame → app.css .new-badge
   Command: grep -n actionsNewBadge/new-badge/primed in web/index.html, web/app.js, web/app.css
   Output: index.html:63 #actionsNewBadge .new-badge; index.html:80 #backlogNewBadge; app.js:38 primed=false suppress first frame; app.js:194 ab=$('actionsNewBadge') bb=$('backlogNewBadge'); app.js:1001 primed=true; app.css:322 .new-badge + :hidden display:none
   Result: PASS
2. Functionality (responsive selftest item-8 invariant)
   Command: node web/responsive.selftest.js
   Output: R27 per-pane "+N new" badge: spans + diff + clear-on-look (item 8) PASS; 33 passed, 0 failed
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R27
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::primed = false

DEPENDENCY TRACE
================
Step 1: SSE state frame adds an action while focus elsewhere
  ↓ Verified at: web/app.js id-diff prev-vs-new; primed guard at :38/:1001 (no false badge first frame — edge case)
Step 2: pane-head shows "+1 new"
  ↓ Verified at: web/app.js:194 actionsNewBadge/backlogNewBadge text update; index.html:63/80 spans
Step 3: user views pane → badge clears
  ↓ Verified at: clear-on-look wiring; responsive R27 asserts spans+diff+clear-on-look
Step 4: no false badge on first load
  ↓ Verified at: primed first-frame suppression (app.js:38→:1001), captured live (+1 appeared on a posted action, cleared on look)

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/web/app.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/index.html  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.css  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: badge spans + SSE id-diff + primed-first-frame guard + clear-on-look present in committed code; covered by green responsive R27; live trace shows +1 appears on new action and clears on pane look (functionality, not just component).

## Task 3 — Phase B item 9: additive item-details-set + rich-details UI

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Phase B — item 9: additive item-details-set event (schema+reducer+selftest) + expandable rich-details UI on action/decision/question items
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: schema.js EVENT_TYPES+EVENT_REQUIRED_FIELDS → reducer.js case → app.js renderItemDetails → app.css .li-details
   Command: git show aafbdc7 -- state/schema.js state/reducer.js; grep li-details web/app.js web/app.css
   Output: schema.js +'item-details-set' to frozen EVENT_TYPES + 'item-details-set':['node_id','item_id','details'] (ADDITIVE — nothing existing changed/removed); reducer.js case 'item-details-set' it.details LWW; app.js:142 renderItemDetails el('div','li-details'); app.js:168 det-link clickable; app.js:541 expanded→appendChild(renderItemDetails); app.css:330 .li-details
   Result: PASS
2. Functionality (selftest covers apply/reject-unknown/idempotent)
   Command: node state/selftest.js
   Output: P15 ... details-set(LWW) ... unknown-item rejected — 15 passed, 0 failed (existing 14 still green = additive proof)
   Result: PASS
3. Regression: schema_version still 1; gates unaffected
   Command: grep SCHEMA_VERSION; bash conversation-tree-{state,stop}-gate.sh / -emit.sh --self-test
   Output: SCHEMA_VERSION=1; state-gate 18/18, stop-gate 8/8, emit 17/17
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P15
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R28
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R29
Runtime verification: file neural-lace/conversation-tree-ui/state/schema.js::const SCHEMA_VERSION = 1

DEPENDENCY TRACE
================
Step 1: item-details-set event applied to a named item
  ↓ Verified at: reducer.js case 'item-details-set' sets it.details (LWW); rejects unknown item; selftest P15
Step 2: GUI expand renders .li-details with description/context/instructions/options/recommendation/links
  ↓ Verified at: web/app.js:142-180 renderItemDetails; :541 expanded gate; responsive R29 renderItemDetails+.li-details
Step 3: items without details render exactly as before (no regression)
  ↓ Verified at: web/app.js:532 if(it.details && typeof===object) gate — absent → unchanged path; existing 14 selftest cases green
Step 4: schema_version still 1; conv-tree gates 18/8/17 unchanged
  ↓ Verified at: schema.js:11 SCHEMA_VERSION=1; gate self-tests all green (additive, no bump confirmed)

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/schema.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/state/reducer.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.js  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: additive event verified at git-diff level (no required field changed, schema_version 1, gates 18/8/17 unaffected — the load-bearing claim); selftest P15 green incl. apply/reject/idempotent; renderItemDetails chain present + live-verified expand renders all fields.

## Task 4 — Phase B item 10: additive action-responded + inline Respond + Copy-to-Dispatch

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Phase B — item 10: additive action-responded event (schema+reducer+selftest) + inline Respond UI + "responded — awaiting confirmation" state + Copy-to-Dispatch
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: schema.js add action-responded → reducer.js sets it.responded (item stays !checked) → app.js Respond/submit/copy → app.css .li.responded
   Command: git show aafbdc7 -- state/schema.js state/reducer.js; grep action-responded/responded/Copy in web/app.js web/app.css
   Output: schema.js +'action-responded':['node_id','item_id','response_text'] (additive); reducer.js case 'action-responded' it.responded={text,ts} — does NOT touch it.checked (stays waiting, NOT concluded); app.js:622 Respond btn when respondable && !responded; app.js:544-549 responded-note "responded — awaiting confirmation" + "⧉ Copy to Dispatch →" → copyResponseForDispatch; app.css:344 .li.responded opacity .78 (de-emphasised, visible)
   Result: PASS
2. Functionality (selftest action-responded stays !checked/visible)
   Command: node state/selftest.js
   Output: P15 ... action-responded(stays !checked) ... 15 passed, 0 failed
   Result: PASS
3. Functionality (responsive R30/R31 invariants)
   Command: node web/responsive.selftest.js
   Output: R30 action-responded additive event (schema+required+reducer) PASS; R31 inline Respond UI + responded state + Copy-to-Dispatch PASS; 33 passed, 0 failed
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P15
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R30
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R31

DEPENDENCY TRACE
================
Step 1: user clicks Respond on a decision/question/needs-input item
  ↓ Verified at: web/app.js:620-623 respondable(it) && !it.responded → inline textarea+Submit
Step 2: Submit POSTs action-responded
  ↓ Verified at: reducer.js case 'action-responded' sets it.responded={text,ts}; does NOT set it.checked
Step 3: item shows "responded — awaiting confirmation" (visible, de-emphasised, NOT concluded)
  ↓ Verified at: web/app.js:544-547 responded-note badge; app.css:344 .li.responded opacity .78; selftest P15 asserts stays !checked
Step 4: "Copy to Dispatch →" formats [action <id>] title + response
  ↓ Verified at: web/app.js:548-549 ⧉ Copy to Dispatch → copyResponseForDispatch(it, text); responsive R31; live trace shows full flow + clipboard shape

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/schema.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/state/reducer.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.js  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: additive event (no schema bump); reducer confirmed to NOT set it.checked (item stays waiting/NOT concluded — the key behavioral contract); Respond+responded-note+Copy chain present; selftest P15 + responsive R30/R31 green; live trace shows full Respond→responded→Copy flow.

## Task 5 — Phase B: additive item-unchecked event (inverse of mark-done for Undo)

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Phase B — additive item-unchecked event (schema+reducer+selftest) — the inverse event item 7's Undo of mark-done/answered requires (append-only log has no built-in uncheck)
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: schema.js add item-unchecked → reducer.js case it.checked=false → app.js item-7 undo posts item-unchecked
   Command: git show aafbdc7 -- state/schema.js state/reducer.js; grep item-unchecked web/app.js
   Output: schema.js +'item-unchecked':['node_id','item_id'] (additive, no required field of any existing event changed); reducer.js case 'item-unchecked' it.checked=false (rejects unknown item); app.js:583 undo of done posts {type:'item-unchecked'...}
   Result: PASS
2. Functionality (selftest round-trip action-done→item-unchecked + reject)
   Command: node state/selftest.js
   Output: P15 ... item-unchecked(round-trip) ... unknown-item rejected — 15 passed, 0 failed (existing 14 green = additive proof)
   Result: PASS
3. Regression: schema_version still 1; gates 18/8/17 unaffected
   Command: grep SCHEMA_VERSION; gate self-tests
   Output: SCHEMA_VERSION=1; state-gate 18, stop-gate 8, emit 17 — all green
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P15
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R32
Runtime verification: file neural-lace/conversation-tree-ui/state/reducer.js::case 'item-unchecked'

DEPENDENCY TRACE
================
Step 1: item-unchecked on a checked item sets checked=false (re-surfaces it)
  ↓ Verified at: reducer.js case 'item-unchecked' it.checked=false; selftest P15 round-trip assertion
Step 2: rejects on unknown item
  ↓ Verified at: reducer.js if(!it){reject(...);return;}; selftest P15 unknown-item rejected
Step 3: reversible round-trip action-done→item-unchecked
  ↓ Verified at: state/selftest.js P15 round-trip green
Step 4: item 7 Undo of "mark done" emits item-unchecked → item returns
  ↓ Verified at: web/app.js:583 post item-unchecked on undo; responsive R32 inverse-event wiring; live trace: Undo restored the item (16→15→16)

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/schema.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/state/reducer.js  (aafbdc7, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.js  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: additive inverse event (Walking Skeleton's riskiest-layer proof); reducer case + reject path + round-trip selftest P15 green; schema_version 1 + gates 18/8/17 unchanged confirm "additive, no bump, gates unaffected"; wired into item-7 undo (app.js:583) and live-verified restoring the item.

## Task 6 — Phase C: backfill-details.js (append-only, idempotent, honest-grounded payloads)

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Phase C — backfill: state/backfill-details.js emits item-details-set for every live open action, content sourced from docs/reviews/+docs/plans/; each payload = description / context / instructions-or-options / recommendation / single blocking input
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: backfill-details.js → appendEvent → reducer item-details-set → GUI .li-details
   Command: head -30 state/backfill-details.js; node state/backfill-details.js --self-test
   Output: script enumerates open actions → emits item-details-set per item; reducer case verified (Task 3); GUI .li-details verified (Task 3)
   Result: PASS
2. Functionality (self-test: integrity + idempotent + grounding)
   Command: node state/backfill-details.js --self-test
   Output: B6 blocking_input derived PASS; B9 idempotent re-run emits 0 PASS; B10 --enrich supersedes PASS; B11 append-only node count unchanged PASS; 11 passed, 0 failed
   Result: PASS
3. Honesty/scope disclosure (source docs absent — verified, not fabricated)
   Command: find ~/claude-projects -maxdepth 4 ( -name '*tcpa-decision-options*' -o -name 'phase-6-preventive-controls*' )
   Output: NO matches (docs genuinely absent). HONESTY CONTRACT in backfill-details.js header (lines 7-29): does NOT fabricate sourced content; grounds payloads ONLY in verifiable state; --enrich path documented. Deferral recorded in Decisions Log entry 4 + Completion Report §2/§3 + docs/discoveries/2026-05-18-conv-tree-backfill-source-docs-not-on-machine.md (file exists)
   Result: PASS (honest mechanism + grounded payloads + loud disclosure = correct completion given absent dependency; NOT vaporware-by-fabrication)

Runtime verification: test neural-lace/conversation-tree-ui/state/backfill-details.js::B11
Runtime verification: test neural-lace/conversation-tree-ui/state/backfill-details.js::B9
Runtime verification: file neural-lace/conversation-tree-ui/state/backfill-details.js::HONESTY CONTRACT

DEPENDENCY TRACE
================
Step 1: script enumerates live open actions and emits one item-details-set each (non-placeholder, grounded)
  ↓ Verified at: backfill-details.js logic; B6 blocking_input derived from item text; header HONESTY CONTRACT grounds desc/context/links in verifiable state
Step 2: after apply, GUI shows rich details; existing tree intact (append-only — node count unchanged)
  ↓ Verified at: self-test B11 append-only node count unchanged; reducer/GUI chain verified Task 3; live trace: 17 emitted, nodes-before==after, TCPA item shows doc-link
Step 3: idempotent (re-run does not duplicate/corrupt)
  ↓ Verified at: self-test B9 re-run emits 0 (no-op skip); backfill-details.js:90 sameDetails LWW skip; B10 --enrich supersedes safely
Step 4: honest deferral of deep enrichment (absent source docs)
  ↓ Verified at: docs disclosure present (Decisions Log 4, Completion Report §2/§3, discovery file); source-doc absence independently re-verified by find

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/backfill-details.js  (538416c, 2026-05-18)
    - docs/discoveries/2026-05-18-conv-tree-backfill-source-docs-not-on-machine.md  (538416c, 2026-05-18)

Verdict: PASS
Confidence: 8
Reason: backfill mechanism + idempotency + append-only integrity proven by self-test B9/B11 (re-run=0, node count unchanged); live trace confirms 17 emitted with tree intact. The deep doc-enrichment deferral is HONEST and LOUDLY disclosed (header HONESTY CONTRACT + Decisions Log 4 + Completion Report + discovery file) — source docs independently re-verified absent. The grounded-payloads + mechanism + disclosure IS the correct completion for Phase C given the absent dependency; fabricating sourced content would be the failure. Confidence 8 (not 9) reflects the documented partial: payloads are state-grounded, options/recommendation null pending --enrich — but this is the plan-sanctioned scope, not an undisclosed gap.

## Task 7 — DEC log + extend responsive.selftest.js + full regression sweep

EVIDENCE BLOCK
==============
Task ID: 7
Task description: DEC log (schema-additivity rationale) + extend web/responsive.selftest.js with the new-UI invariants + full regression sweep
Verified at: 2026-05-18T17:31:40Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check: Decisions Log records additivity + undo-inverse + backfill-sourcing decisions
   Command: read docs/plans/conv-tree-ui-v1.1-ux-interactivity.md Decisions Log
   Output: 4 entries present — (1) three new event types ADDITIVE ADR-032 major 1 no bump (Tier 2); (2) item-7 Undo inverse events + backlog-activate partial (Tier 1); (3) backfill content sourced idempotent LWW (Tier 1); (4) backfill source docs absent — ship mechanism + grounded payloads, enrichment deferred (Tier 1, loudly surfaced)
   Result: PASS
2. Functionality: extended responsive.selftest.js all-pass incl. new-UI invariants
   Command: node web/responsive.selftest.js
   Output: R23-R33 cover snackbar/✕/anim/details/respond/item-unchecked/SCHEMA_VERSION-still-1; R1-R22 (items 1-6) intact; 33 passed, 0 failed
   Result: PASS
3. Full regression sweep
   Command: node state/selftest.js; conv-tree state/stop/emit gates --self-test; findings-ledger --self-test; node --check web/app.js
   Output: state/selftest.js 15/15 (14 existing + P15 new); state-gate 18/18; stop-gate 8/8; emit 17/17; findings-ledger 6/6 (NL-FINDING-011 schema-valid); app.js syntax OK
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R33
Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P15
Runtime verification: file docs/plans/conv-tree-ui-v1.1-ux-interactivity.md::Decision: three new event types are ADDITIVE

DEPENDENCY TRACE
================
Step 1: Decisions Log records ADR-032-additivity + undo-inverse + backfill-sourcing
  ↓ Verified at: plan file Decisions Log — 4 substantive entries with Tier/Status/Chosen/Alternatives/Reasoning
Step 2: responsive.selftest.js extended with new-UI invariants, still all-pass
  ↓ Verified at: web/responsive.selftest.js R23-R33; re-executed node web/responsive.selftest.js → 33 passed 0 failed
Step 3: conv-tree gates 18/8/17 + state/selftest 15 all green (no regression)
  ↓ Verified at: re-executed all four gate self-tests + state selftest — all green; SCHEMA_VERSION=1
Step 4: items 1-6 responsive behavior intact under new DOM
  ↓ Verified at: R1-R22 green within the 33-pass run; live trace confirms grid-areas at 960x2160 + 1920x1080, no page scroll

Git evidence:
  Files modified in recent history:
    - docs/plans/conv-tree-ui-v1.1-ux-interactivity.md  (538416c, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js  (aafbdc7, 2026-05-18)

Verdict: PASS
Confidence: 9
Reason: all 4 Decisions Log entries present and substantive (incl. the loud honesty entry); responsive.selftest.js extended R23-R33 and full 33/33 green with items 1-6 (R1-R22) intact; full regression sweep re-executed independently — selftest 15/15, gates 18/8/17, findings 6/6 — confirming the load-bearing "additive, no bump, gates unaffected" claim end-to-end.
