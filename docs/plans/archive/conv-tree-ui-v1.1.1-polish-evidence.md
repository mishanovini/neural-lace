# Evidence Log -- Conversation Tree UI v1.1.1 polish (items 14-18)

All five tasks verified against commit e7393bc on branch
conv-tree-ui-v1.1.1-polish. KEY CLAIM confirmed mechanically:
git show e7393bc --stat touches exactly 4 files, all under
neural-lace/conversation-tree-ui/web/ -- NO state/*.js. Zero schema
change -> state/gate self-tests green by construction.

Shared regression evidence (re-run from neural-lace/conversation-tree-ui/):
- node web/responsive.selftest.js -> 38 passed, 0 failed (R1-R33 intact + R34-R38 new)
- node --check web/app.js -> syntax OK
- node state/selftest.js -> 15 passed, 0 failed (UNTOUCHED)
- node state/backfill-details.js --self-test -> 11 passed, 0 failed
- conversation-tree-state-gate.sh --self-test -> 18 passed
- conversation-tree-stop-gate.sh --self-test -> 8 passed
- conversation-tree-emit.sh --self-test -> 17 passed
- git show e7393bc --stat -> 4 files: web/app.css, web/app.js, web/index.html, web/responsive.selftest.js

---

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Item 14 type-coded palette action=red decision=amber question=blue on the type label + a 4-6px left-border stripe on the item card + optional <=6 percent bg wash in the Waiting pane WCAG AA on dark
Verified at: 2026-05-18T18:08:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Commit scope (zero schema change)
   Command: git show e7393bc --stat | tail -6
   Output: 4 files all under neural-lace/conversation-tree-ui/web/ -- NO state/*.js
   Result: PASS
2. Wire check -- CSS vars + per-kind label/stripe
   Command: git show e7393bc -- web/app.css
   Output: --ty-action #f87171, --ty-action-rgb 248 113 113, --ty-decision #fbbf24, --ty-question #60a5fa; .li-kind.action color var(--ty-action); .li.kind-action border-left 5px solid + rgb wash 0.05
   Result: PASS
3. Wire check -- JS emits kind class
   Command: git show e7393bc -- web/app.js
   Output: el div li kind- + it.kind in renderActions
   Result: PASS
4. AA-on-dark intent
   Output: palette aliases established --err/--warn/--info AA-on-dark semantic family (Decisions Log documents AA rationale; raw spec hexes rejected as borderline)
   Result: PASS
5. responsive.selftest.js R34
   Command: node web/responsive.selftest.js
   Output: 38 passed, 0 failed (R34 green)
   Result: PASS

DEPENDENCY TRACE
================
Step 1: user views an action item in the Waiting pane
  Verified at: web/app.js renderActions li kind- + it.kind
Step 2: card gets .li.kind-action + label gets .li-kind.action
  Verified at: web/app.css .li-kind.action / .li.kind-action rules
Step 3: red label + 5px red left stripe + 5 percent wash (amber/blue for decision/question)
  Verified at: runtime preview :7744 -- computed .li-kind.action rgb(248,113,113), .decision rgb(251,191,36), .question rgb(96,165,250), distinct, AA-on-dark

Runtime verification: test web/responsive.selftest.js::R34
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::--ty-action: #f87171
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::.li.kind-action

Verdict: PASS
Confidence: 9
Reason: type palette vars + per-kind label/stripe/wash present in CSS, JS emits the kind class, AA intent held via established semantic family, R34 green, user-observable distinct colors demonstrated live.

---

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Item 15 title owns row width flex 1 right-side text crumb to fixed 24px icon-button arrow with tooltip Jump to in tree same click focusNode
Verified at: 2026-05-18T18:08:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire check -- CSS .li-text flex + .li-jump fixed 24px
   Command: git show e7393bc -- web/app.css
   Output: .li-text flex 1 min-width 0; .li-jump flex 0 0 auto width 24px height 24px
   Result: PASS
2. Wire check -- JS icon-button replaces text crumb
   Command: git show e7393bc -- web/app.js
   Output: width-greedy li-crumb replaced by el button li-jump arrow, title Jump to in tree, aria-label set, e.stopPropagation + focusNode(n.node_id) preserved
   Result: PASS
3. responsive.selftest.js R35
   Command: node web/responsive.selftest.js
   Output: R35 green (flex 1 + 24px + button + tooltip text)
   Result: PASS

DEPENDENCY TRACE
================
Step 1: user views a Waiting item
  Verified at: web/app.css .li-text flex 1 min-width 0 -- title grows
Step 2: jump affordance is a fixed 24px icon-button not a width-greedy text link
  Verified at: web/app.css .li-jump width 24px height 24px; web/app.js el button li-jump arrow
Step 3: clicking the arrow button still navigates to the tree node
  Verified at: web/app.js cr.addEventListener click ... focusNode(n.node_id); runtime preview -- text crumb gone, .li-text flex-grows over 3x jump width, click focuses node

Runtime verification: test web/responsive.selftest.js::R35
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::.li-jump
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::li-jump

Verdict: PASS
Confidence: 9
Reason: title flex 1, fixed 24px icon-button with correct tooltip + aria-label, focusNode click preserved, R35 green, demonstrated live.

---

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Item 16 hide-concluded default UNCHECKED hide concluded on first load + make the toggle prominent eye icon larger label grouped near + project in a View group
Verified at: 2026-05-18T18:08:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire check -- index.html View-filters group
   Command: git show e7393bc -- web/index.html
   Output: span class view-filters label class toggle-prom span class eye eye-glyph input id showConcluded Show concluded near addProjBtn
   Result: PASS
2. Wire check -- CSS .view-filters / .toggle-prom
   Command: git show e7393bc -- web/app.css
   Output: .view-filters border 1px solid var(--border2) background var(--panel2); .toggle-prom font-weight 600; .toggle-prom .eye font-size 1rem
   Result: PASS
3. Default-hide preserved
   Command: grep -n ctree-show-concluded web/app.js
   Output: var showConcludedPref = localStorage.getItem ctree-show-concluded === 1 -- absent localStorage to false to hide-concluded by default; filter logic at lines 364/394 unchanged from item 3
   Result: PASS
4. responsive.selftest.js R36
   Command: node web/responsive.selftest.js
   Output: R36 green (view-filters/toggle-prom/eye + default-hide assertion)
   Result: PASS

DEPENDENCY TRACE
================
Step 1: fresh load no localStorage key
  Verified at: web/app.js L44 localStorage.getItem ctree-show-concluded === 1 to false
Step 2: concluded branches hidden by default (behavior unchanged from item 3)
  Verified at: web/app.js L364/L394 if showConcludedPref return null/false (unchanged filter logic)
Step 3: toggle visibly prominent -- eye glyph + larger label grouped in View block near + project
  Verified at: web/index.html view-filters/toggle-prom/eye markup; web/app.css view-filters delineated box; runtime preview -- group present with eye glyph, showConcluded unchecked by default

Runtime verification: test web/responsive.selftest.js::R36
Runtime verification: file neural-lace/conversation-tree-ui/web/index.html::class="view-filters"
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::ctree-show-concluded

Verdict: PASS
Confidence: 9
Reason: View-filters group with eye glyph + larger label present in HTML/CSS, default-hide (localStorage absent to false) preserved with unchanged filter logic, R36 green, demonstrated live.

---

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Item 17 bidirectional item-tree highlight full interior type-color tint 15-20 percent + 3-4px solid left accent both directions item-to-node AND node-to-item/backlog smooth scroll-into-view of the other side
Verified at: 2026-05-18T18:08:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire check -- JS shared selNodeLink + dominantKind + linkSelect + scrollIntoView
   Command: git show e7393bc -- web/app.js
   Output: var selNodeLink = null; function dominantKind node (action over decision over question precedence); function linkSelect nodeId src to render then scrollIntoView block center behavior smooth on the other side; tree row click to linkSelect n.node_id fromTree; item click to linkSelect n.node_id fromItem; li gets sel-link+kind- when n.node_id === selNodeLink; tree row gets sel-tint+tint-dk
   Result: PASS
2. Wire check -- CSS per-kind tints
   Command: git show e7393bc -- web/app.css
   Output: .li.sel-link.kind-action .tnode-row.sel-tint.tint-action background rgb var(--ty-action-rgb) 0.18 (decision/question parallel); neutral fallback for typeless nodes
   Result: PASS
3. Edge case -- node with no waiting item
   Output: CSS .tnode-row.sel-tint not tint- neutral fallback; JS dominantKind returns null to node highlight only no error (graceful)
   Result: PASS
4. responsive.selftest.js R37
   Command: node web/responsive.selftest.js
   Output: R37 green (selNodeLink + linkSelect + dominantKind + sel-link/sel-tint + 0.18 tint + scrollIntoView + fromTree)
   Result: PASS

DEPENDENCY TRACE
================
Step 1: user clicks a Waiting action item
  Verified at: web/app.js li.addEventListener click ... linkSelect n.node_id fromItem
Step 2: selNodeLink set render -- item gets sel-link+kind-action tree node gets sel-tint+tint-action
  Verified at: web/app.js renderTreeNode if n.node_id === selNodeLink row.classList.add sel-tint ... tint-+dk; renderActions n.node_id === selNodeLink sel-link
Step 3: tree node tinted rgba 248 113 113 0.18 scrolled into view; reverse direction symmetric (tree click to item tinted + scrolled)
  Verified at: web/app.css per-kind 0.18 tints; web/app.js scrollIntoView block center behavior smooth; runtime preview -- both directions proven rgba(248,113,113,0.18) both sides parent-node-no-item edge case = node highlight only no error

Runtime verification: test web/responsive.selftest.js::R37
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::function linkSelect
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::.tnode-row.sel-tint.tint-action

Verdict: PASS
Confidence: 9
Reason: bidirectional link-select with shared selNodeLink + dominant-kind precedence + per-kind 0.18 tint both sides + smooth scrollIntoView, typeless-node edge case handled gracefully, R37 green, both directions demonstrated live.

---

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Item 18 toast to bottom-right bottom-center on narrow + arrival-flash 600ms type-color tint reduced-motion = single-frame persist 1.5s on the affected item/backlog/tree-node on toast OR SSE arrival OR state change + DEC log + extend responsive.selftest.js + full regression
Verified at: 2026-05-18T18:08:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire check -- CSS toast bottom-right + narrow override + keyframes + reduced-motion
   Command: git show e7393bc -- web/app.css
   Output: .toast position fixed right 1rem bottom 1.2rem left auto transform none; media max-width 1023.98px and max-height 1023.98px .toast right auto left 50 percent translateX -50 percent; keyframes arrival-flash; media prefers-reduced-motion reduce .arrival-flash animation none important
   Result: PASS
2. Wire check -- JS arrivalFlash + reduced-motion timing + 3 trigger paths
   Command: git show e7393bc -- web/app.js
   Output: function arrivalFlash node kind with reducedMotion 1500 700 ms; triggered on new actions if newActionIds it.item_id arrivalFlash li it.kind, new backlog, new tree nodes seenNodeIds diff in renderTreeNode, AND on state change post then flashes treeCanvas.querySelector data-node since item slid out
   Result: PASS
3. responsive.selftest.js extended + all regression green
   Command: node web/responsive.selftest.js; node state/selftest.js; node state/backfill-details.js --self-test; gate self-tests
   Output: responsive 38/38 (R38 green), state selftest 15/15, backfill 11/11, state-gate 18/18, stop-gate 8/8, emit 17/17 -- all unchanged (no schema touched)
   Result: PASS
4. DEC log present
   Output: plan Decisions Log contains 2 Tier-1 decisions (type palette aliases semantic colors; dominant-kind precedence) -- tier-1 reversible no standalone ADR required
   Result: PASS

DEPENDENCY TRACE
================
Step 1: a toast appears (bottom-right at wide bottom-center on narrow under 1024 and under 1024)
  Verified at: web/app.css .toast right 1rem left auto + narrow media override; runtime preview -- toast computed right 16px rect 16px from right edge
Step 2: mark-done / new SSE item / conclude to 600ms type-tinted flash on the affected location
  Verified at: web/app.js arrivalFlash on newActionIds/newBacklogIds/seenNodeIds diff + post then flashes affected tree node; runtime preview -- affected node got arrival-flash class/_af timer type-tinted
Step 3: prefers-reduced-motion to single-frame highlight persisting 1.5s (no fade)
  Verified at: web/app.css media prefers-reduced-motion reduce .arrival-flash animation none; web/app.js reducedMotion 1500 700
Step 4: responsive.selftest.js extended + full regression green
  Verified at: node web/responsive.selftest.js to 38/38 (R34-R38 new R1-R33 intact); gates 18/8/17; state selftest 15/15; backfill 11/11

Runtime verification: test web/responsive.selftest.js::R38
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::@keyframes arrival-flash
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::function arrivalFlash
Runtime verification: test state/selftest.js::regression-15-passed

Verdict: PASS
Confidence: 9
Reason: toast bottom-right + narrow bottom-center override + arrival-flash keyframes + reduced-motion single-frame variant present; arrivalFlash wired on all 3 trigger paths (new item new node state-change); DEC log present; responsive.selftest.js extended R34-R38 with full regression green (38/38 15/15 11/11 18/8/17 zero schema touched); demonstrated live.
