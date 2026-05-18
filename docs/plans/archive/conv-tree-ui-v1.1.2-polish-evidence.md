# Evidence Log — Conversation Tree UI v1.1.2 polish (drop item 20, add item 25)

Plan: docs/plans/conv-tree-ui-v1.1.2-polish.md
Work commit: b418f5c (code) / e5b4628 (plan), branch claude/jolly-davinci-d99487
Verification level: `full` per task; plan is `tier: 2 rung: 1` (no comprehension gate), `acceptance-exempt: true` (harness-internal; six self-test suites ARE the acceptance artifact).

---

## Task 20R — Revert item 20: restore "promote to branch" label + "promoted to branch" toast; keep btn-up + promoted event

EVIDENCE BLOCK
==============
Task ID: 20R
Task description: Revert item 20: restore 'promote to branch' button label + 'promoted to branch' toast in app.js; keep the btn-up semantic class + the type:'promoted' event unchanged — Verification: full
Verified at: 2026-05-18T19:27:01Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Diff inspection — label + toast revert
   Command: git show b418f5c -- neural-lace/conversation-tree-ui/web/app.js
   Output: line 1082 button now reads 'promote to branch' (was 'expand to branch'); line 1085 post(... , 'promoted to branch') (toast was 'expanded to branch').
   Result: PASS

2. btn-up class + promoted event UNCHANGED
   Command: grep -n btn-up / type:'promoted' web/app.js
   Output: line 1082 el('button', 'btn-up', 'promote to branch'); line 1085 type: 'promoted'. The btn-up purple class (item 22) and the frozen type:'promoted' event (ADR-032) are intact in the diff (only the two string literals changed).
   Result: PASS

3. Zero "expand to branch" / "expanded to branch" in app.js
   Command: grep -n "expand to branch|expanded to branch" neural-lace/conversation-tree-ui/web/app.js
   Output: no matches (exit 1)
   Result: PASS

4. Negative-regex regression sweep across web/
   Command: grep -rn "expand to branch|expanded to branch" neural-lace/conversation-tree-ui/web/
   Output: single hit at responsive.selftest.js:203 — R40's negative assertion (the expected "negative regex aside", not a live label).
   Result: PASS

5. R40 inverted + suite green
   Command: node web/responsive.selftest.js
   Output: 44 passed, 0 failed (R40 now asserts promote-to-branch label present, expand absent, el('button','btn-up','promote to branch'), type:'promoted')
   Result: PASS

Git evidence:
  - neural-lace/conversation-tree-ui/web/app.js (b418f5c, 2026-05-18) — lines 1078-1085 label/toast revert
  - neural-lace/conversation-tree-ui/web/responsive.selftest.js (b418f5c) — R40 inverted

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R40
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::btn-up.*promote to branch

Verdict: PASS
Confidence: 9
Reason: label + toast reverted to "promote to branch"/"promoted to branch"; btn-up + type:'promoted' provably unchanged; zero "expand" in app.js; R40 inverted and suite green.

---

## Task 25 — Top-level project nodes render as H1/H2-style headers (depth-0 only)

EVIDENCE BLOCK
==============
Task ID: 25
Task description: Top-level project nodes render as H1/H2-style headers: larger font (~1.18x), bolder weight, larger padding, subtle ~5% white tint + thin top separator, larger/distinct disclosure twist — applied ONLY to root-level nodes, not nested ones — Verification: full
Verified at: 2026-05-18T19:27:01Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. renderTreeNode depth param + depth-0 class wiring
   Command: git show b418f5c -- web/app.js ; grep -n "renderTreeNode|orderedRoots" web/app.js
   Output: signature now renderTreeNode(n, kids, container, depth) with depth = depth || 0; row class el('div','tnode-row' + (depth === 0 ? ' tnode-root' : '')); forest-root call line 631 orderedRoots.forEach((r) => renderTreeNode(r, f.kids, treeCanvas)) — 3 args so depth defaults to 0 -> gets tnode-root; recursive call line 591 renderTreeNode(k, kids, kc, depth + 1).
   Result: PASS

2. Depth-0 distinct twist glyph
   Command: git show b418f5c -- web/app.js (twist line)
   Output: tw glyph ternary uses larger glyphs at depth 0 (open/collapsed/leaf) and the original glyphs at depth >= 1.
   Result: PASS

3. .tnode-row.tnode-root CSS header rule
   Command: git show b418f5c -- web/app.css
   Output: .tnode-row.tnode-root { font-size:1.18rem; padding:0.62rem 0.7rem; border-left-width:5px; background-image:linear-gradient(rgba(255,255,255,0.05),rgba(255,255,255,0.05)); margin-top:0.7rem; border-top:1px solid var(--border2); }; .tnode-root .tnode-title{font-weight:800; letter-spacing:0.01em;}; .tnode-root .twist{font-size:1.05rem; width:1.3rem; color:var(--accent);}; first-child exemption removes the leading separator.
   Result: PASS

4. No regression to nested rendering
   Command: git show b418f5c -- web/app.js (full hunk review)
   Output: the diff touches only (a) the signature, (b) the row-class string concat, (c) the twist glyph ternary, (d) the recursive-call arg. No lines affecting drag (draggable/data-node), badges, .hl (item 17 sel wash), .concluded, or arrival-flash were modified. Depth >= 1 rows receive neither tnode-root nor the larger glyph — unchanged.
   Result: PASS

5. R44 present + full suite green
   Command: node web/responsive.selftest.js
   Output: 44 passed, 0 failed. R44 asserts all six .tnode-root CSS invariants AND the three renderTreeNode wiring tokens (4-arg signature, depth === 0 ? ' tnode-root', renderTreeNode(k, kids, kc, depth + 1)).
   Result: PASS

Git evidence:
  - neural-lace/conversation-tree-ui/web/app.js (b418f5c) — renderTreeNode depth param + tnode-root class + root twist
  - neural-lace/conversation-tree-ui/web/app.css (b418f5c) — .tnode-row.tnode-root header rule + first-child exemption
  - neural-lace/conversation-tree-ui/web/responsive.selftest.js (b418f5c) — R44 added

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R44
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::function renderTreeNode.n, kids, container, depth.
Runtime verification: file neural-lace/conversation-tree-ui/web/app.css::.tnode-row.tnode-root

Verdict: PASS
Confidence: 9
Reason: depth param threaded correctly (forest roots = depth 0 via 3-arg call site, +1 per recursion); .tnode-root CSS header styling matches the spec exactly; depth-0-only twist; no nested-render regression; R44 + full suite green.

---

## Task 26 — Invert R40 + add R44; full six-suite regression sweep green

EVIDENCE BLOCK
==============
Task ID: 26
Task description: Invert R40 + add R44 in web/responsive.selftest.js; full six-suite regression sweep green — Verification: full
Verified at: 2026-05-18T19:27:01Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. R40 inverted + R44 added
   Command: git show b418f5c -- web/responsive.selftest.js
   Output: R40 rewritten to assert promote-to-branch label + toast present, expand absent, el('button','btn-up','promote to branch'), type:'promoted'. New R44 block added covering .tnode-root CSS + renderTreeNode depth-0 wiring.
   Result: PASS

2. Six-suite regression sweep
   Command: node --check (3 JS) ; node state/selftest.js ; node web/responsive.selftest.js ; node state/backfill-details.js --self-test ; bash conversation-tree-{state-gate,stop-gate,emit}.sh --self-test
   Output:
     - node --check web/app.js / responsive.selftest.js / state/backfill-details.js -> all syntax OK
     - state/selftest.js -> 15 passed, 0 failed
     - web/responsive.selftest.js -> 44 passed, 0 failed (was 43; +1 = R44; R40 inverted PASS)
     - state/backfill-details.js --self-test -> 15 passed, 0 failed (B15 now uses docs/DECISIONS.md)
     - conversation-tree-state-gate.sh --self-test -> 18 passed, 0 failed
     - conversation-tree-stop-gate.sh --self-test -> 8 passed, 0 failed
     - conversation-tree-emit.sh --self-test -> 17 passed, 0 failed / OK
   Result: PASS

3. No schema change (ADR-032 frozen)
   Command: grep -n "const SCHEMA_VERSION" neural-lace/conversation-tree-ui/state/schema.js
   Output: 11:const SCHEMA_VERSION = 1;
   Result: PASS

4. B15 path-fragility fix (in-flight scope update, Task 26 "all six suites green")
   Command: git show b418f5c -- state/backfill-details.js
   Output: B15 selftest doc reference repointed from the archived conv-tree-ui-v1.1.1-polish.md to the permanent docs/DECISIONS.md (never archived/renamed); assertion regex changed to match DECISIONS.md. backfill suite back to 15/0 (was regressed 14/1).
   Result: PASS

Git evidence:
  - neural-lace/conversation-tree-ui/web/responsive.selftest.js (b418f5c) — R40 inverted, R44 added
  - neural-lace/conversation-tree-ui/state/backfill-details.js (b418f5c) — B15 path-fragility fix
  - neural-lace/conversation-tree-ui/state/schema.js — SCHEMA_VERSION still 1 (unchanged by this commit)

Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R40
Runtime verification: test neural-lace/conversation-tree-ui/web/responsive.selftest.js::R44
Runtime verification: test neural-lace/conversation-tree-ui/state/backfill-details.js::B15

Verdict: PASS
Confidence: 9
Reason: R40 inverted + R44 added; all six regression suites green (state 15, responsive 44, backfill 15, state-gate 18, stop-gate 8, emit 17); SCHEMA_VERSION still 1; B15 path-fragility fix restores backfill to 15/0.
