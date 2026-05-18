# Evidence Log -- Conversation Tree UI v1.1 responsive layout + popup + tree fixes

Companion evidence file for docs/plans/conv-tree-ui-v1.1-responsive.md.
All six tasks are a single bundled commit d0df33a16356283dab3237b2f484d4be4315cdc8.
Verified by task-verifier agent. Plan rung 1 -- comprehension-gate not applicable (rung < 2).

---

## Task 1 -- Responsive breakpoint layout (CSS Grid template-areas + media queries)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Responsive breakpoint layout: CSS Grid template-areas + media queries (>=1440 three-pane unchanged; <1440 vertical stack; <1024 & <1024h single-pane tabs); pane min-width 280px; page never scrolls
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Off-screen bug removed (body min-width:1440px deleted)
   Command: git show d0df33a -- web/app.css | grep -nE "min-width: 1440px"
   Output: line 83 deletion of "min-width: 1440px"; body now min-width:320px; @media (min-width:1440px) blocks present (140,223)
   Result: PASS
2. CSS Grid template-areas at all 3 breakpoints
   Command: git show d0df33a -- web/app.css | grep -nE "grid-template-areas"
   Output: default vstack "tree tree"/"actions backlog"; @media min-width:1440px -> "tree actions"/"tree backlog" 57/43 (DEC-A unchanged); @media max 1023.98/1023.98h -> "pane"; @media max 699.98 -> stacked
   Result: PASS
3. Tab-bar DOM + JS body[data-tab] handler
   Command: git show d0df33a -- web/index.html ; app.js diff
   Output: nav id=tabBar data-tab tree/actions/backlog; app.js tabBar click flips document.body.dataset.tab; .right-col{display:contents} layout-transparent
   Result: PASS
4. Deterministic regression selftest
   Command: node web/responsive.selftest.js
   Output: R1-R8,R14,R22 all PASS; 22 passed, 0 failed
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R1-R8,R14,R22 (22 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::grid-template-areas

DEPENDENCY TRACE
================
Step 1: User opens GUI at 960x2160
  v Verified at: app.css default #layout grid-template-areas "tree tree"/"actions backlog"
Step 2: All three panes on-screen, page does not scroll
  v Verified at: live preview eval documentElement.scrollWidth==960 (was 1440); body overflow:hidden
Step 3: >=1440px three-pane unchanged (DEC-A)
  v Verified at: @media min-width:1440px 57/43 grid; live eval 1920x1080 tree 57%
Step 4: <1024 & <1024h single pane + tabs
  v Verified at: live eval 700x900 "pane", tabBar display:flex, tabs isolate pane, no scroll

Verdict: PASS
Confidence: 9
Reason: User-observable responsive behavior demonstrated live at all 4 viewport shapes against the real backfilled state; deterministic selftest locks the invariants; DEC-A >=1440 provably unchanged.

---

## Task 2 -- Context/popup pane to dismissible overlay

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Context/popup pane to dismissible overlay: wire the X button, click-outside-to-close, dock right at wide viewports / overlay the tree at narrow
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. The X bug fixed (.ctx-panel[hidden] override)
   Command: git show d0df33a -- web/app.css | grep -nE "ctx-panel.hidden."
   Output: line 207 ".ctx-panel[hidden] { display: none !important; }" -- root cause was .ctx-panel display:flex beating UA [hidden] display:none
   Result: PASS
2. Single closeCtx() wired to X, scrim, Esc
   Command: app.js diff
   Output: closeCtx() sets ctxPanel.hidden + ctxScrim.hidden + sel=null + render(); x click closeCtx; ctxScrim click closeCtx; keydown Escape closeCtx
   Result: PASS
3. Dock vs overlay media rules
   Command: app.css diff
   Output: .ctx-panel position:fixed; @media max 1439.98 overlay+scrim; @media min 1440 ctxScrim display:none (docked)
   Result: PASS
4. Regression selftest
   Command: node web/responsive.selftest.js
   Output: R9,R10,R11,R15,R16,R17 PASS
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R9,R10,R11,R15,R16,R17 (22 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::closeCtx

DEPENDENCY TRACE
================
Step 1: Click tree node -> ctx panel opens
  v Verified at: openCtx() ctxPanel.hidden=false + ctxScrim.hidden=false; live eval open + scrim
Step 2: Click X -> closes (was dead)
  v Verified at: x click closeCtx; .ctx-panel[hidden] display:none important; live eval X -> display:none
Step 3: Click outside / Esc -> closes
  v Verified at: ctxScrim click + keydown Escape closeCtx; live eval scrim/Esc close
Step 4: >=1440 docks (no scrim); <1440 overlays
  v Verified at: @media min 1440 ctxScrim display:none; position:fixed never pushes grid

Verdict: PASS
Confidence: 9
Reason: The reported dead-X bug is root-caused (CSS specificity) and fixed; the single closeCtx path is wired to all three dismiss affordances and demonstrated live; dock/overlay split is CSS-driven.

---

## Task 3 -- Top-bar hide-concluded toggle, persisted (localStorage)

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Top-bar hide-concluded toggle, persisted (localStorage UI-pref convention), default OFF=hide; filters concluded leaves AND branches whose entire subtree is concluded
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. showConcluded control in header
   Command: git show d0df33a -- web/index.html
   Output: label with input type=checkbox id=showConcluded "show concluded" added to header
   Result: PASS
2. Subtree-concluded filter logic
   Command: app.js diff
   Output: concludedHiddenSet() memoized allConcluded() recursion + cycle guard; branch hidden only if it+all descendants concluded; visibleNodes() drops hidden; allHiddenByConcluded() drives tailored steady-empty (never blank canvas)
   Result: PASS
3. localStorage persistence, default OFF=hide
   Command: app.js diff
   Output: showConcludedPref = localStorage.getItem(ctree-show-concluded)===1 (default false=hide); applyShowConcluded writes 1/0; matches UI-pref convention; ADR-032 schema NOT touched
   Result: PASS
4. Regression selftest
   Command: node web/responsive.selftest.js
   Output: R13,R18,R19 PASS
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R13,R18,R19 (22 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::ctree-show-concluded

DEPENDENCY TRACE
================
Step 1: Toggle in header, default hides concluded
  v Verified at: index.html showConcluded; app.js default false; live eval default unchecked, 23 rows
Step 2: Fully-concluded subtree absent
  v Verified at: concludedHiddenSet()+visibleNodes(); live eval 23 hide / 45 show (22 concluded)
Step 3: Toggle on -> concluded reappear
  v Verified at: applyShowConcluded() render(); live eval show -> 45 rows
Step 4: Reload -> persisted
  v Verified at: localStorage getItem on init; live eval 1/0 persists across reload

Verdict: PASS
Confidence: 9
Reason: Toggle + subtree-concluded filtering + localStorage persistence demonstrated live across before/after/reload; localStorage-vs-state-file deviation surfaced and documented in Decisions Log per friction-reflexion (legitimate Tier 1, frozen ADR-032 untouched).

---

## Task 4 -- Fix Fit button to true fit-to-viewport

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Fix Fit button to true fit-to-viewport (bbox of rendered tree -> zoom scale that fits with padding -> apply scale + scroll to top-left/center)
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Fit measures natural bbox + scale + scroll origin
   Command: app.js diff
   Output: fitSel resets scale(1)/width:100%, reads treeCanvas.scrollWidth/Height + treeScroll.clientWidth/Height, z=min(vw/cw,vh/ch)*0.96 clamp 0.15..2, zoom=z, renderTree(), scrollLeft/Top=0
   Result: PASS
2. Works with no node selected (old impl no-op)
   Command: app.js diff
   Output: guard "if (!loaded || visibleNodes().length === 0) return" (was "if (!sel) return"); NaN guard restores+returns
   Result: PASS
3. Regression selftest
   Command: node web/responsive.selftest.js
   Output: R20 PASS
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R20 (22 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::treeCanvas.scrollWidth

DEPENDENCY TRACE
================
Step 1: User zooms in until overflow
  v Verified at: zoomIn handler zoom+0.1
Step 2: Click Fit with NO selection
  v Verified at: guard no longer requires sel; measures natural bbox
Step 3: Whole tree fits w/ padding, scrolled origin
  v Verified at: z=min(vw/cw,vh/ch)*0.96; renderTree(); scrollLeft/Top=0; live eval Fit no-selection canvas H <= viewport H, origin 0,0

Verdict: PASS
Confidence: 9
Reason: Fit now measures the real rendered bbox and computes a fitting scale (old impl only scrollIntoView a selected node, no-op without selection); demonstrated live fitting vertically with no node selected at scroll origin.

---

## Task 5 -- Fix zoom -/+ to flex-fluid line-item reflow

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Fix zoom -/+ to line-item widths flex-fluid relative to available width; reflow on zoom change so zoom-out has no dead horizontal space
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. .tree-canvas fluid width base
   Command: app.css diff
   Output: .tree-canvas { ... width: 100%; } zoom==1 default
   Result: PASS
2. JS recomputes width on zoom (no dead space)
   Command: app.js diff
   Output: renderTree() sets transform scale(zoom) AND treeCanvas.style.width = (100/zoom)+% so scaled canvas lays out at full visual width; symmetric zoom-in
   Result: PASS
3. Regression selftest
   Command: node web/responsive.selftest.js
   Output: R12,R21 PASS
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R12,R21 (22 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::treeCanvas.style.width

DEPENDENCY TRACE
================
Step 1: User zooms out
  v Verified at: zoomOut handler renderTree(); scale(0.6)+width:166.667%
Step 2: Rows reflow to fill width (no dead space)
  v Verified at: width:(100/zoom)% widens layout box; live eval zoom-out scale(0.6)+width:166.667% rows fill 100%
Step 3: Zoom in symmetric
  v Verified at: same formula; live eval zoom-in scale(1.2)+width:83.333% fill 100%

Verdict: PASS
Confidence: 9
Reason: Dead-horizontal-space bug at zoom-out is root-caused (scaled canvas at fixed 100% width left visual gap) and fixed via inverse-zoom width formula; demonstrated live filling 100% at zoom-out and zoom-in.

---

## Task 6 -- DEC-A additive revision + headless regression check + opportunistic fixes

EVIDENCE BLOCK
==============
Task ID: 6
Task description: DEC-A additive revision in Decisions Log + headless responsive regression check + opportunistic inline fixes for any unambiguous bug found at the real viewport
Verified at: 2026-05-18T16:33:57Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. DEC-A additive revision documented (>=1440 explicitly unchanged)
   Command: read docs/plans/conv-tree-ui-v1.1-responsive.md ## Decisions Log
   Output: "Decision: DEC-A revised -- additive responsive-breakpoint clause" Tier 2; >=1440px DEC-A original RETAINED UNCHANGED; alternatives rejected with reasons; to-reverse documented. "Decision: hide-concluded persists via localStorage" Tier 1, surfaced per friction-reflexion, alternatives+reasoning+reversal documented
   Result: PASS
2. Headless regression check passes (4 shapes locked)
   Command: node web/responsive.selftest.js
   Output: 22 passed, 0 failed; reads real app.css/index.html/app.js (not stubs)
   Result: PASS
3. Conv-tree gate/stop/emit + state selftest no regression
   Command: conversation-tree-state-gate.sh --self-test ; stop-gate --self-test ; emit --self-test ; node state/selftest.js
   Output: state-gate 18/0 ; stop-gate 8/0 ; emit 17/0 ; state/selftest.js 14/0
   Result: PASS
4. Backfilled state file byte-identical (read-only invariant)
   Command: sha256sum neural-lace/conversation-tree-ui/state/tree-state.json
   Output: 8a403e54ce16aa4bd76707003227df31c14008480b67b5a1b0c1ea4e0333f916 == baseline; gitignored, not in commit; diff --stat confirms no state/ change
   Result: PASS
5. app.js syntax valid
   Command: node --check neural-lace/conversation-tree-ui/web/app.js
   Output: exit 0
   Result: PASS

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::all (22 passed, 0 failed)
Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::all (14 passed, 0 failed)
Runtime verification: file neural-lace/conversation-tree-ui/state/tree-state.json::8a403e54ce16aa4bd76707003227df31c14008480b67b5a1b0c1ea4e0333f916
Runtime verification: file docs/plans/conv-tree-ui-v1.1-responsive.md::DEC-A revised

DEPENDENCY TRACE
================
Step 1: Decisions Log has DEC-A clause (>=1440 explicitly unchanged)
  v Verified at: plan ## Decisions Log lines 81-95 DEC-A (Tier 2) + localStorage (Tier 1) fully populated
Step 2: Regression check passes for all 4 shapes
  v Verified at: node web/responsive.selftest.js 22/22 against real files
Step 3: Gates 18/18+8/8, emit 17/17, state selftest 14/14 still PASS
  v Verified at: re-ran all four suites -- no regression (web/ only; hooks untouched)
Step 4: State file sha256 unchanged
  v Verified at: sha256sum == 8a403e54 baseline; not in commit (gitignored)

Verdict: PASS
Confidence: 9
Reason: Both Decisions Log entries are substantive and document the additive DEC-A revision (>=1440 unchanged) + the localStorage deviation with alternatives/reasoning/reversal; headless regression locks all 4 shapes; all four self-test suites green by my own re-execution; read-only state-file invariant confirmed by my own sha256.
