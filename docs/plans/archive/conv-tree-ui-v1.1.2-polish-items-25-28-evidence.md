# Evidence Log — Conversation Tree UI v1.1.2 polish (items 25–28)

## Task 1 — Item 25: filled semantic button backgrounds + reclassify every action button

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Item 25: filled semantic button backgrounds (commit=green / caution=amber / util=blue / elevate=purple / destruct=muted-red / neutral=slate) with hover/active/disabled states; reclassify every pane/ctx/backlog action button by semantic — Verification: full
Verified at: 2026-05-18T19:07:46Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Git history — impl + plan commits
   Command: git log --oneline -- docs/plans/conv-tree-ui-v1.1.2-polish.md neural-lace/conversation-tree-ui/web/app.css
   Output: impl 71ad016 "feat(conv-tree-ui): v1.1.2 polish items 25-28"; plan d04ecd4
   Result: PASS

2. Acceptance criterion 1 — six .b-* classes, exact spec hex, hover/active/disabled
   Command: grep -n "b-commit|...|:disabled" web/app.css ; Read web/app.css:77-102
   Output: app.css:81-86 — .b-commit #22C55E / .b-caution #F59E0B (dark text #1a1505 per UX contrast assumption) / .b-util #3B82F6 / .b-elevate #A855F7 / .b-destruct #B91C1C / .b-neutral #475569 (all exact spec hex, white text except caution). :hover (lighter + 2px focus ring) 87-92, :active (darker) 93-98, grouped :disabled (opacity 0.5; cursor:not-allowed; box-shadow:none) 99-102.
   Result: PASS

3. Acceptance criterion 2 — no legacy ghost/primary ACTION buttons; semantic classes used
   Command: grep -on "el('button', *'[^']*'" web/app.js | dedupe
   Output: 32 semantic action buttons (b-caution x6, b-commit x6, b-destruct x2, b-elevate x1, b-neutral x7, b-util x10 [incl. 'b-util det-toggle']). Only non-semantic button classes: 'ghost x' (app.js:1043, ctx-head close X — documented allowed chrome), 'ghost dismiss' (app.js:1185, notification dismiss X — documented allowed chrome), 'li-jump' (app.js:596, v1.1.1 icon-jump nav affordance — not a pane/ctx/backlog action button), 'sb-undo'/'sb-x' (toast snackbar chrome — not action buttons). Zero el('button','ghost'|'primary',...) ACTION buttons remain.
   Result: PASS

4. Acceptance criterion 3 — index.html #blSave/#blCancel
   Command: grep -n "blSave|blCancel" web/index.html
   Output: index.html:105 <button id="blSave" class="b-commit">Add</button> ; :106 <button id="blCancel" class="b-neutral">cancel</button>
   Result: PASS

5. Acceptance criterion 4 — R39 PASS + full responsive suite 43/43
   Command: node web/responsive.selftest.js   (cwd: neural-lace/conversation-tree-ui)
   Output: "PASS  R39 item 25: six filled semantic button classes (exact palette) + hover/active/disabled, used in JS+HTML" ; final line "43 passed, 0 failed". R39 asserts the six exact-hex classes, :hover/:active/:disabled, semantic JS reclassification (mark done=b-commit, defer=b-caution, promote to branch=b-elevate), and #blSave=b-commit in HTML — correspondence-true, not a hardcoded string.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/web/app.css   (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.js     (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/index.html (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js (last commit: 71ad016, 2026-05-18)

DEPENDENCY TRACE
================
Step 1: maintainer sees a pane/ctx/backlog action button
  -> Verified at: web/app.css:78-102 (.b-commit/.b-caution/.b-util/.b-elevate/.b-destruct/.b-neutral filled + states)
Step 2: each action button carries its semantic class
  -> Verified at: web/app.js — 32 el('button','b-*',...) calls; only chrome X remain 'ghost'
Step 3: backlog Add/cancel chrome carries the same semantic
  -> Verified at: web/index.html:105-106 (#blSave=b-commit, #blCancel=b-neutral)
Step 4: maintainer-observable acceptance artifact confirms the wiring end-to-end
  -> Verified at: node web/responsive.selftest.js -> R39 PASS, "43 passed, 0 failed"

Acceptance-exempt note: plan declares acceptance-exempt: true (harness-internal Dispatch tracker GUI; maintainer is the live user; self-test suite is the gate-honored acceptance artifact — identical verification path to the merged predecessor docs/plans/archive/conv-tree-ui-v1.1.1-polish.md). The runtime browser-advocate path does not apply per the acceptance-exempt reason.

Runtime verification: test web/responsive.selftest.js::R39
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::.b-commit
Runtime verification: file neural-lace/conversation-tree-ui/web/index.html::id="blSave" class="b-commit"

Verdict: PASS
Confidence: 9
Reason: All four acceptance criteria verified against actual repo state — six exact-hex semantic classes with hover/active/disabled in app.css, all 32 action buttons reclassified (only documented chrome X remain ghost), #blSave/#blCancel correct in index.html, and R39 + the full 43/43 responsive self-test (the gate-honored acceptance artifact for this acceptance-exempt harness-internal plan) pass cleanly.

## Task 2 — Item 26: clicking "details" no longer resets pane scroll (in-place toggle + scrollIntoView nearest)

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Item 26: clicking "details" no longer resets pane scroll — toggle the rich-details box inline (no full `renderActions()` rebuild) and `scrollIntoView({block:'nearest'})` so the clicked item stays visible — Verification: full
Verified at: 2026-05-18T19:14:30Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Git history — impl + plan commits
   Command: git log --oneline -3 -- neural-lace/conversation-tree-ui/web/app.js ; git show --stat 71ad016
   Output: impl 71ad016 "feat(conv-tree-ui): v1.1.2 polish items 25-28" (recent, 2026-05-18); plan d04ecd4. Commit body item 26: "Details toggles in place — no full renderActions() rebuild, so the pane no longer scroll-resets to top; scrollIntoView({block:'nearest'}) keeps the clicked item visible."
   Result: PASS

2. Acceptance criterion 1 — det-toggle handler: in-place add/remove of .li-details + caret flip + scrollIntoView({block:'nearest'}); NO renderActions() in handler
   Command: Read web/app.js:600-645 ; grep -n "renderActions" web/app.js
   Output: app.js:617-635 disc.addEventListener('click', ...). Collapse branch (619-624): expandedItems.delete(it.item_id); var box = li.querySelector('.li-details'); if (box) box.remove(); disc.textContent = '▸ details'; nowExpanded=false. Expand branch (625-631): expandedItems.add(it.item_id); var d = renderItemDetails(it.details); li.insertBefore(d, disc.nextSibling); disc.textContent = '▾ details'; nowExpanded=true. Line 634: if (nowExpanded) li.scrollIntoView({ block: 'nearest' }). renderActions occurrences in file: line 564 (function def), 612 (comment explicitly forbidding its use here), 1253 (actionsSort change listener — unrelated), 1337 (SSE/init caller — unrelated). ZERO renderActions() calls inside the 617-635 handler.
   Result: PASS

3. Acceptance criterion 2 — expandedItems updated in handler; render-time SSE-path appendChild preserved
   Command: Read web/app.js:608-638
   Output: expandedItems.delete at app.js:620 (collapse), expandedItems.add at app.js:626 (expand) — set kept in sync in both branches. Render-time: app.js:610 var expanded = expandedItems.has(it.item_id); app.js:637 if (expanded) li.appendChild(renderItemDetails(it.details)); — the SSE-driven full-render path that re-shows the expanded box is intact.
   Result: PASS

4. Acceptance criterion 3 — node web/responsive.selftest.js: R40 PASS + suite 43/43
   Command: node web/responsive.selftest.js   (cwd: neural-lace/conversation-tree-ui)
   Output: "PASS  R40 item 26: Details toggles IN PLACE (no full renderActions rebuild) + scrollIntoView nearest (no scroll reset)" ; final line "43 passed, 0 failed". R40 asserts the in-place toggle, absence of a renderActions() rebuild in the det-toggle handler, and the scrollIntoView({block:'nearest'}) call — correspondence-true to the item-26 invariant, not a hardcoded string.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/web/app.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js (last commit: 71ad016, 2026-05-18)

DEPENDENCY TRACE
================
Step 1: maintainer scrolls a pane so an item is mid/bottom, clicks its "details"
  -> Verified at: web/app.js:611 el('button','b-util det-toggle',...) ; :617 disc.addEventListener('click', ...)
Step 2: the details box is added/removed in place — no clear(actionsBody) + full rebuild
  -> Verified at: web/app.js:625-631 (expand: insertBefore) / :619-624 (collapse: box.remove); zero renderActions() in handler (grep: only 564/612/1253/1337, all outside 617-635)
Step 3: the clicked item stays visible — minimum scroll, never a reset to top
  -> Verified at: web/app.js:634 if (nowExpanded) li.scrollIntoView({ block: 'nearest' })
Step 4: a later SSE-driven full renderActions() still shows the box expanded
  -> Verified at: web/app.js:620/626 expandedItems kept in sync ; :610 expanded=expandedItems.has(...) ; :637 if (expanded) li.appendChild(renderItemDetails(...))
Step 5: maintainer-observable acceptance artifact confirms the wiring end-to-end
  -> Verified at: node web/responsive.selftest.js -> R40 PASS, "43 passed, 0 failed"

Acceptance-exempt note: plan declares acceptance-exempt: true (harness-internal Dispatch tracker GUI; maintainer is the live user; the deterministic responsive.selftest.js suite is the gate-honored acceptance artifact — identical verification path to the merged predecessor docs/plans/archive/conv-tree-ui-v1.1.1-polish.md). The runtime browser-advocate path does not apply per the acceptance-exempt reason.

Runtime verification: test web/responsive.selftest.js::R40
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::li.scrollIntoView({ block: 'nearest' })
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::b-util det-toggle

Verdict: PASS
Confidence: 9
Reason: All three acceptance criteria verified against actual repo state — the det-toggle click handler (app.js:617-635) does in-place add/remove of .li-details with caret flip and li.scrollIntoView({block:'nearest'}) and never calls renderActions() (grep confirms its only occurrences are the def, the forbidding comment, and two unrelated callers); expandedItems is updated in both branches and the SSE render-path appendChild at :637 is preserved; and R40 plus the full 43/43 responsive self-test (the gate-honored acceptance artifact for this acceptance-exempt harness-internal plan) pass cleanly.

## Task 3 — Item 27: decision/question resolve ONLY via Respond (no quiet mark-answered); action keeps mark-done

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Item 27: decision/question items expose ONLY "Respond" as the completion path — no "mark answered"/"mark done" quiet-resolve; action items keep "mark done" — Verification: full
Verified at: 2026-05-18T19:21:10Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Git history — impl + plan commits
   Command: git log --oneline -3 -- neural-lace/conversation-tree-ui/web/app.js
   Output: impl 71ad016 "feat(conv-tree-ui): v1.1.2 polish items 25-28" (recent, 2026-05-18); plan d04ecd4. app.js modified in 71ad016.
   Result: PASS

2. Acceptance criterion 1a — done button created ONLY when it.kind === 'action'
   Command: Read web/app.js:670-744 ; grep -nE "mark (done|answered)" web/app.js
   Output: app.js:676 `if (it.kind === 'action') {` opens the block; :677 `var done = el('button', 'b-commit', 'mark done');` is inside it; the block closes at :692 `acts.appendChild(done); }`. The done button is constructed nowhere else. grep -nE "mark (done|answered)" → only line 674 (comment) and 677 (the gated construction).
   Result: PASS

3. Acceptance criterion 1b — zero occurrences of the string "mark answered" in app.js
   Command: grep -c "mark answered" web/app.js
   Output: 0
   Result: PASS

4. Acceptance criterion 1c — Respond path intact + respondable() true for decision/question regardless of details
   Command: Read web/app.js:231-234 ; Read web/app.js:717-742
   Output: respondable(it) (app.js:231-234) returns `it.kind === 'decision' || it.kind === 'question' || (it.details && it.details.blocking_input)` — decision/question return true unconditionally; the details clause is an additional OR (a bare decision/question with no details still returns true). Respond path (app.js:719-742): `if (respondable(it) && !it.responded) { var rsp = el('button', 'b-commit', 'Respond'); ... acts.appendChild(rsp); }` — unchanged and intact.
   Result: PASS

5. Acceptance criterion 2 — no other quiet-resolve button on a waiting decision/question
   Command: Read web/app.js:670-743 (full non-checked-display else branch)
   Output: state-changing buttons in the branch: `mark done` gated to `it.kind === 'action'` (:676); `dispute` gated to `if (it.checked)` (:695) — a waiting (unchecked) decision/question has it.checked falsy so it never renders, and it is a contest/safety-net path not a quiet-resolve; `clear defer`/`defer` gated to `it.deferred` (:708/:712) — parking/un-parking, not resolution; `Respond` gated to `respondable(it) && !it.responded` (:719) — the intended completion path. On a non-contested waiting decision/question the only state-changing buttons are Respond and defer/clear-defer. No quiet-resolve button exists; decision/question is never stranded (respondable() always true for them).
   Result: PASS

6. Acceptance criterion 3 — node web/responsive.selftest.js: R41 PASS + suite 43/43
   Command: node web/responsive.selftest.js   (cwd: neural-lace/conversation-tree-ui)
   Output: "PASS  R41 item 27: decision/question resolve ONLY via Respond — done button gated to kind=\"action\", no \"mark answered\"" ; final line "43 passed, 0 failed". R41 (responsive.selftest.js:198-201) asserts against actual app.js source: regex `if \(it\.kind === 'action'\) \{ ... var done = el\('button', 'b-commit', 'mark done'\)`, AND `!/mark answered/.test(js)`, AND `/function respondable\s*\(/.test(js)` — correspondence-true to the item-27 invariant, not a hardcoded string or tautology.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/web/app.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js (last commit: 71ad016, 2026-05-18)

DEPENDENCY TRACE
================
Step 1: maintainer sees a waiting decision/question item in the Waiting pane
  -> Verified at: web/app.js:670-743 (non-checked-display else branch of renderActions)
Step 2: that item exposes Respond as the ONLY completion path — no quiet mark-answered/mark-done
  -> Verified at: web/app.js:676-692 (done button gated to it.kind === 'action'); grep -c "mark answered" = 0; web/app.js:719-742 (Respond gated to respondable() && !responded)
Step 3: a decision/question with no details is never stranded
  -> Verified at: web/app.js:231-234 respondable() returns true for kind decision/question unconditionally
Step 4: an action item still shows "mark done"; dispute is not a quiet-resolve path
  -> Verified at: web/app.js:677 (mark done inside the it.kind==='action' block); :695 dispute gated to it.checked (never on a waiting unchecked decision/question)
Step 5: maintainer-observable acceptance artifact confirms the wiring end-to-end
  -> Verified at: node web/responsive.selftest.js -> R41 PASS, "43 passed, 0 failed"

Acceptance-exempt note: plan declares acceptance-exempt: true (harness-internal Dispatch tracker GUI; maintainer is the live user; the deterministic responsive.selftest.js suite is the gate-honored acceptance artifact — identical verification path to the merged predecessor docs/plans/archive/conv-tree-ui-v1.1.1-polish.md). The runtime browser-advocate path does not apply per the acceptance-exempt reason.

Runtime verification: test web/responsive.selftest.js::R41
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::if (it.kind === 'action') {
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::function respondable (it)

Verdict: PASS
Confidence: 9
Reason: All three acceptance criteria verified against actual repo state — the 'mark done' button is constructed only inside `if (it.kind === 'action')` (app.js:676-692), the string "mark answered" has zero occurrences in app.js (grep -c = 0), the Respond path (app.js:719-742) is intact and respondable() (app.js:231-234) returns true for decision/question regardless of details so they are never stranded; the only state-changing buttons on a non-contested waiting decision/question are Respond and defer/clear-defer (dispute is gated to it.checked); and R41 plus the full 43/43 responsive self-test (the gate-honored acceptance artifact for this acceptance-exempt harness-internal plan) pass cleanly.

## Task 4 — Item 28: Defer popover (presets + datetime-local + to-Backlog via additive item-backlogged)

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Item 28: Defer popover — presets ("Later today" 8 PM, "Tomorrow morning" 9 AM, "Next week" Mon 9 AM, "Pick a specific time…" → `<input type="datetime-local">`, "Until further notice — move to Backlog"); all times local; `deferred` event records additive `scheduled_for_local` + `tz_offset_min`; "to Backlog" reuses backlog-promotion via additive `item-backlogged` event — Verification: full
Verified at: 2026-05-18T19:42:00Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Git history — impl + plan commits
   Command: git log --oneline -3 ; git show --stat 71ad016
   Output: impl 71ad016 "feat(conv-tree-ui): v1.1.2 polish items 25-28" (recent, 2026-05-18); plan d04ecd4 (immediately preceding). 71ad016 touches state/schema.js (+12), state/reducer.js (+19), web/app.js (+234/-56), state/selftest.js (+56), web/responsive.selftest.js (+44) — all four task-relevant files present.
   Result: PASS

2. Acceptance criterion 1 — state/schema.js: item-backlogged in EVENT_TYPES + EVENT_REQUIRED_FIELDS; SCHEMA_VERSION still 1
   Command: Read state/schema.js
   Output: schema.js:57 `'item-backlogged',` in the frozen EVENT_TYPES list (v1.1.2 additive block, commented per ADR-032 §1 additive rule); schema.js:96 `'item-backlogged': ['node_id', 'item_id'],` in EVENT_REQUIRED_FIELDS; schema.js:11 `const SCHEMA_VERSION = 1;` unchanged. Optional `scheduled_for_local`/`tz_offset_min` correctly NOT added to `deferred`'s required fields (lines 92-95 comment confirms intentional — no contract change).
   Result: PASS

3. Acceptance criterion 2 — state/reducer.js: item-backlogged case; deferred persists local fields only when present + keeps canonical scheduled_for; item-unchecked clears backlogged
   Command: Read state/reducer.js
   Output: reducer.js:333-339 `case 'item-backlogged'` resolves node+item, rejects if item not found, sets `it.backlogged = true`. reducer.js:134-147 `case 'deferred'`: sets canonical `it.scheduled_for` (line 139, unchanged behavior); then `if (ev.scheduled_for_local != null) it.scheduled_for_local = String(...)` (144) and `if (ev.tz_offset_min != null) it.tz_offset_min = Number(...)` (145) — guarded by `!= null`, persisted ONLY when present. reducer.js:320-327 `case 'item-unchecked'` sets `it.checked = false` AND `it.backlogged = false` (line 325 — un-park round-trip).
   Result: PASS

4. Acceptance criterion 3a — web/app.js: openDeferPop with 5 presets + native datetime-local; no prompt('Defer until; isWaiting excludes backlogged; to-Backlog posts item-backlogged then backlog-added w/ treeOf(n)
   Command: Read web/app.js:700-853 ; grep "prompt\('Defer until|isWaiting|item-backlogged"
   Output: openDeferPop (app.js:775-853): "Later today (8 PM)" (790-795, rolls to tomorrow if past), "Tomorrow morning (9 AM)" (796-799), "Next week (Mon 9 AM)" (800-805), "Pick a specific time…" reveals `dti.type = 'datetime-local'` + Set (806-822), "Until further notice — move to Backlog" (824-839). commit(d) posts `deferred` with scheduled_for=d.toISOString(), scheduled_for_local=toLocalInput(d) ("YYYY-MM-DDTHH:MM" local), tz_offset_min=d.getTimezoneOffset() (777-786). isWaiting (app.js:316): `((!it.checked) || it.deferred || it.contested) && !it.backlogged` — excludes backlogged. to-Backlog handler (826-839): posts `item-backlogged` first, then on success posts `backlog-added` with `tree_id: treeOf(n)`, then context-attached crumb. grep for `prompt('Defer until` → ZERO matches (old ISO prompt removed; app.js:705-707 comment confirms "no ISO prompt()").
   Result: PASS

5. Acceptance criterion 3b — "Next week" math `((1 - d.getDay() + 7) % 7) || 7` correctness (Mon/Wed/Sun reasoned explicitly)
   Command: Read web/app.js:800-805 ; manual derivation across all 7 weekdays
   Output: getDay() 0=Sun..6=Sat. Sun(0): (1-0+7)%7=1 → Mon next day ✓. Mon(1): (1-1+7)%7=0 → falsy → ||7 → +7 = FOLLOWING Monday, never today ✓ (satisfies plan Edge Case + Prove-it-works step 2). Tue(2):6, Wed(3):5, Thu(4):4, Fri(5):3, Sat(6):2 — every weekday lands on the next Monday; Wed→+5=Mon, Sun→+1=Mon all correct. .setHours(9,0,0,0) then sets local 09:00. Math is correct in every case.
   Result: PASS

6. Acceptance criterion 4 — node state/selftest.js (16/16, P16 PASS) AND node web/responsive.selftest.js (43/43, R42+R43 PASS)
   Command: node state/selftest.js ; node web/responsive.selftest.js   (cwd: neural-lace/conversation-tree-ui)
   Output: state/selftest.js → "PASS  P16 v1.1.2 item 28 additive: item-backlogged(park, !checked) + deferred local-time fields + plain-defer unchanged + unpark round-trip + unknown rejected + schema_version still 1" ; final line "16 passed, 0 failed". responsive.selftest.js → "PASS  R42 item 28: friendly Defer popover — presets + native datetime-local + to-Backlog (no ISO prompt())" and "PASS  R43 item 28: item-backlogged ADDITIVE (schema enum+required+reducer) + deferred local-time fields + isWaiting excludes backlogged + SCHEMA_VERSION still 1" ; final line "43 passed, 0 failed". P16 exercises the actual schema/reducer modules end-to-end (additive round-trip, local-field persistence, plain-defer regression, unpark round-trip, SCHEMA_VERSION===1) — functionality evidence, not component-only.
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/schema.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/state/reducer.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/app.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/state/selftest.js (last commit: 71ad016, 2026-05-18)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js (last commit: 71ad016, 2026-05-18)

DEPENDENCY TRACE
================
Step 1: maintainer clicks "defer" on a waiting item
  -> Verified at: web/app.js:713-715 (dfr button → openDeferPop(li,n,it)); old prompt() removed (grep "prompt('Defer until" = 0)
Step 2: a popover opens with 5 presets + a native datetime-local input
  -> Verified at: web/app.js:775-853 openDeferPop — later/tmrw/week/pick (datetime-local at :808) / toBl
Step 3: each preset computes the correct LOCAL datetime (Next-week math correct on Mon→+7, Wed→+5, Sun→+1)
  -> Verified at: web/app.js:800-805 ((1-d.getDay()+7)%7)||7 + .setHours(9,0,0,0); derivation table above
Step 4: chosen value persists — canonical ISO + additive local fields, re-displays via fmtTime
  -> Verified at: web/app.js:777-786 commit() posts deferred{scheduled_for, scheduled_for_local, tz_offset_min} ; state/reducer.js:134-147 persists all three (local fields guarded by !=null)
Step 5: "Until further notice — move to Backlog" parks the item out of Waiting + tracks it in Backlog
  -> Verified at: web/app.js:826-839 posts item-backlogged then backlog-added(treeOf(n)) ; state/reducer.js:333-339 sets it.backlogged ; web/app.js:316 isWaiting excludes backlogged
Step 6: item-backlogged is strictly additive — SCHEMA_VERSION stays 1
  -> Verified at: state/schema.js:57 (EVENT_TYPES) + :96 (EVENT_REQUIRED_FIELDS) + :11 (SCHEMA_VERSION=1 unchanged)
Step 7: maintainer-observable acceptance artifact confirms the whole chain end-to-end
  -> Verified at: node state/selftest.js → P16 PASS, "16 passed, 0 failed" ; node web/responsive.selftest.js → R42+R43 PASS, "43 passed, 0 failed"

Acceptance-exempt note: plan declares acceptance-exempt: true (harness-internal Dispatch tracker GUI; the maintainer is the live user; the deterministic state/selftest.js + web/responsive.selftest.js suites are the gate-honored acceptance artifact — identical verification path to the merged predecessor docs/plans/archive/conv-tree-ui-v1.1.1-polish.md). The runtime browser-advocate path does not apply per the acceptance-exempt reason; for harness-internal tooling the self-test PASS is the user-facing functional outcome (the harness's user is the maintainer). P16/R43 exercise the real schema+reducer modules through the additive round-trip, so this is functionality evidence, not component-only.

Runtime verification: test state/selftest.js::P16
Runtime verification: test web/responsive.selftest.js::R42
Runtime verification: test web/responsive.selftest.js::R43
Runtime verification: file neural-lace/conversation-tree-ui/state/schema.js::'item-backlogged'
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::dti.type = 'datetime-local'

Verdict: PASS
Confidence: 9
Reason: All four acceptance criteria verified against actual repo state — item-backlogged is in EVENT_TYPES (schema.js:57) and EVENT_REQUIRED_FIELDS (schema.js:96) with SCHEMA_VERSION unchanged at 1 (schema.js:11); the reducer's item-backlogged case sets backlogged (reducer.js:333-339), the deferred case persists local fields only when present while keeping canonical scheduled_for (reducer.js:134-147), and item-unchecked clears backlogged (reducer.js:325); openDeferPop ships all 5 presets plus a native datetime-local with the old ISO prompt() removed, isWaiting excludes backlogged, and to-Backlog posts item-backlogged then backlog-added with treeOf(n) (web/app.js:316/775-853); the "Next week" math `((1-d.getDay()+7)%7)||7` is correct in every weekday case including the Monday→following-Monday(+7) edge; and P16 (state 16/16) + R42 + R43 (responsive 43/43) — the gate-honored acceptance artifact for this acceptance-exempt harness-internal plan — pass cleanly.

## Task 5 — Selftests + full regression + Decisions Log + Completion Report

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Extend `state/selftest.js` (P16) + `web/responsive.selftest.js` (R39–R43) + full regression (state 16/16, responsive 43/43, backfill 11/11, conv-tree gates 18/8 unchanged) + DEC log + completion report — Verification: full
Verified at: 2026-05-18T19:34:00Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. state self-test suite
   Command: cd neural-lace/conversation-tree-ui && node state/selftest.js
   Output: "16 passed, 0 failed"; P16 line PASS — "v1.1.2 item 28 additive: item-backlogged(park, !checked) + deferred local-time fields + plain-defer unchanged + unpark round-trip + unknown rejected + schema_version still 1"
   Result: PASS

2. responsive self-test suite
   Command: cd neural-lace/conversation-tree-ui && node web/responsive.selftest.js
   Output: "43 passed, 0 failed"; R39 PASS (six filled semantic button classes), R40 PASS (Details toggles in place), R41 PASS (Respond-only resolve), R42 PASS (friendly Defer popover), R43 PASS (item-backlogged additive + SCHEMA_VERSION still 1)
   Result: PASS

3. backfill self-test (regression)
   Command: cd neural-lace/conversation-tree-ui && node state/backfill-details.js --self-test
   Output: "11 passed, 0 failed"
   Result: PASS

4. conv-tree gate self-tests (schema major unchanged → gates unaffected)
   Command: bash adapters/claude-code/hooks/conversation-tree-state-gate.sh --self-test ; bash adapters/claude-code/hooks/conversation-tree-stop-gate.sh --self-test
   Output: state-gate "18 passed, 0 failed"; stop-gate "8 passed, 0 failed"
   Result: PASS

5. Decisions Log + Completion Report presence + substance
   Command: read docs/plans/conv-tree-ui-v1.1.2-polish.md lines 85-138
   Output: ## Decisions Log has two substantive entries — Tier-2 "item-backlogged is an ADDITIVE event ..." (Chosen/Alternatives/Reasoning/To-reverse all populated) and Tier-1 "two existing-shape events; no dedicated undo"; NOT "[Populated during implementation]". ## Completion Report present with all 6 numbered subsections (1. Implementation Summary table, 2. Design Decisions & Plan Deviations, 3. Known Issues & Gotchas, 4. Manual Steps Required, 5. Testing Performed & Recommended, 6. Cost Estimates).
   Result: PASS

6. P16 correspondence (self-test exercises the claimed behavior, not a stub)
   Command: grep -n 'P16|item-backlogged|scheduled_for_local|SCHEMA_VERSION' state/selftest.js
   Output: P16 (selftest.js:597-647) appends item-backlogged then asserts item parked + NOT checked, asserts deferred-with-local-fields persists scheduled_for_local/tz_offset_min while plain-defer leaves them undefined, asserts unknown item_id rejected (retained not applied), asserts schema_version still 1
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/state/selftest.js  (impl commit: 71ad016)
    - neural-lace/conversation-tree-ui/web/responsive.selftest.js  (impl commit: 71ad016)
    - docs/plans/conv-tree-ui-v1.1.2-polish.md  (Decisions Log + Completion Report: 822eab4)
    - docs/plans/conv-tree-ui-v1.1.2-polish-evidence.md  (evidence: 822eab4)

Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P16
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R43
Runtime verification: test neural-lace/conversation-tree-ui/state/backfill-details.js::--self-test
Runtime verification: file docs/plans/conv-tree-ui-v1.1.2-polish.md::## Completion Report

Verdict: PASS
Confidence: 9
Reason: All five acceptance criteria pass with the exact required counts run against actual repo state — state 16/16 (P16 PASS), responsive 43/43 (R39–R43 all PASS), backfill 11/11, conv-tree-state-gate 18/0, conv-tree-stop-gate 8/0 (schema major unchanged, gates unaffected); the Decisions Log carries two substantive Tier-2/Tier-1 entries (not the placeholder) and the Completion Report is present with all 6 numbered subsections. P16 corresponds to the task: it exercises item-backlogged round-trip, deferred local-time field persistence, plain-defer-unchanged, unpark, unknown-rejection, and SCHEMA_VERSION==1 — not a stub. This is the gate-honored acceptance artifact for the acceptance-exempt harness-internal plan.
