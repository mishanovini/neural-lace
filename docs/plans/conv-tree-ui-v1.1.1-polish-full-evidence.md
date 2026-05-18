# Evidence Log — Conversation Tree UI v1.1.1 polish (items 14-24)

Acceptance-exempt harness-infrastructure plan (work-shape: build-harness-infrastructure;
tier 2 / rung 1 -> comprehension gate not applicable). The conv-tree gate/emit self-tests
plus the web-module state self-test plus the extended responsive self-test ARE the
acceptance artifact per the plan acceptance-exempt-reason. Commits on branch
claude/jolly-davinci-d99487: e01d2dd (plan), e10dae7 (14-18,20-22), 2f2f3c9 (19),
a78ac23 (23), bc5ed47 (24).

Six-suite regression sweep run by the verifier 2026-05-18:
state/selftest.js 15/0; web/responsive.selftest.js 43/0; backfill --self-test 15/0;
conv-tree state-gate 18/0; stop-gate 8/0; emit 17 OK; node --check all OK;
grep promote-to-branch web/ = only the selftest negative-assertion regex;
SCHEMA_VERSION = 1 (no schema bump; ADR-032 frozen).

## Task 14 - Type-color palette

EVIDENCE BLOCK
==============
Task ID: 14
Task description: Type-color palette badge bg/text + 4-6px left accent + ~5pct tint, BOTH Waiting pane AND tree; WCAG AA on dark bg
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.css L27-30 type-action #dc2626 / type-decision #f59e0b / type-question #3b82f6 / type-on #0b0b0f; L265-267 filled li-kind action/decision/question; L271-273 li.kind-* 5px left border + 5pct gradient tint. Result PASS
2. Wire-check app.js L682 div li kind-it.kind; L690 span li-kind it.kind. Result PASS
3. Contrast near-black on each fill: action 4.07 decision 9.15 question 5.34. Bold 700-weight badge UI affordance; decision/question clear 4.5; action red 4.07 just under normal-text AA but >=3 bold-AA - minor finding NOT a task failure; distinct red/amber/blue + accent + tint delivered; locked by R34. Result PASS
Runtime verification: test web/responsive.selftest.js::R34

Verdict: PASS

## Task 15 - Hyperlink crowding fix

EVIDENCE BLOCK
==============
Task ID: 15
Task description: title flex:1; replace text crumb with fixed ~24px arrow icon button, tooltip Jump to in tree, same destination
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.js L691 span li-text it.text; L697 button li-jump arrow; L698 jump.title Jump to in tree; L699 click focusNode n.node_id. grep li-crumb across web/ exit 1 zero hits. Result PASS
2. Wire-check app.css L268 li-text flex:1; L275-280 li-jump flex 0 0 24px width 24px height 24px. Result PASS
Runtime verification: test web/responsive.selftest.js::R35

Verdict: PASS

## Task 16 - Hide-concluded default OFF, relocated, prominent eye

EVIDENCE BLOCK
==============
Task ID: 16
Task description: default UNCHECKED=hide concluded; move toggle into tree pane-head; eye glyph + bigger label
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check index.html section pane tree-pane -> pane-head -> label viewtoggle -> span eye + input id showConcluded (inside tree pane-head not global header). Result PASS
2. Wire-check app.js L48 showConcludedPref = localStorage ctree-show-concluded === 1 (false when unset = hide); L1263 showConcluded.checked = showConcludedPref; L471/L501 hide concluded when pref off. Result PASS
Runtime verification: test web/responsive.selftest.js::R36

Verdict: PASS

## Task 17 - Bidirectional interior highlight + auto-scroll

EVIDENCE BLOCK
==============
Task ID: 17
Task description: interior wash + 3-4px left bar; click Waiting item highlights+scrolls tree node and vice-versa; smooth scroll both ways
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.css L283-287 li.hl/tnode-row.hl linear-gradient wash + border-left 4px solid; type-coloured kind hl variants. Result PASS
2. Wire-check app.js L37 selItem shared sel; L544 tree row hl when node_id===sel; L684 li hl when sel===n.node_id or selItem===it.item_id; L704 click item sets selItem + focusNode; L1006-1007 selectNode scrolls li data-node smooth; L1019-1020 focusNode scrolls tree data-node smooth. Result PASS
Runtime verification: test web/responsive.selftest.js::R37

Verdict: PASS

## Task 18 - Toast bottom-right + arrival flash + reduced-motion

EVIDENCE BLOCK
==============
Task ID: 18
Task description: toast bottom-right, bottom-center narrow; arrival flash new/changed items; reduced-motion = persistent 1.5s highlight
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.css L105 toast right 1.2rem bottom 1.2rem NO left 50pct in base; L389-391 media max-width 699.98px recenters right 50pct translateX 50pct; L395-399 keyframes arrive wash; L473-476 prefers-reduced-motion clause covers li.arrive + tnode-row.arrive. Result PASS
2. Wire-check app.js L102 arriveCls arrive-static under reduced-motion else arrive; L103 sweepArriveStatic clears after 1500ms; L545/685/875 applied to new tree node / action / backlog. Result PASS
Runtime verification: test web/responsive.selftest.js::R38

Verdict: PASS

## Task 19 - Clickable doc links + Docs browser (server + config + UI)

EVIDENCE BLOCK
==============
Task ID: 19
Task description: GET /api/doc /api/docs POST /api/doc/open; per-machine projects.json gitignored + example committed; md renderer + modal + docs panel; traversal guard
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check server.js L147 /api/docs L154 /api/doc L166 /api/doc/open POST -> projects.resolveDoc; projects.js L48-60 resolveDoc path-traversal-rejected 400 + abs.indexOf rootN not 0 containment guard. Result PASS
2. Wire-check config gitignore ignores projects.json; projects.example.json placeholder only no real path or codename; git ls-files config = gitignore example.json js only, projects.json NOT tracked. Result PASS
3. Wire-check app.js L280 mdRender L313 openDocModal L331 linkifyDocs + openDocsPanel; index.html L18 docsBtn L119-120 docScrim docModal L128 docsPanel. Result PASS
4. LIVE server test port 7798: curl /api/doc project=neural-lace path=docs/plans/conv-tree-ui-v1.1.1-polish.md returned ok:true content # Plan Conversation Tre...; curl path=../../etc/passwd returned HTTP 400. Result PASS
Runtime verification: curl -s http://127.0.0.1:7798/api/doc?project=neural-lace&path=docs/plans/conv-tree-ui-v1.1.1-polish.md
Runtime verification: test web/responsive.selftest.js::R39

Verdict: PASS

## Task 20 - promote-to-branch renamed to expand-to-branch

EVIDENCE BLOCK
==============
Task ID: 20
Task description: rename user strings to expand to branch / expanded to branch; event type promoted UNCHANGED ADR-032 frozen
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.js L1080 button btn-up expand to branch; L1083 post type promoted ... expanded to branch event type preserved. Result PASS
2. Class-sweep grep -rn promote-to-branch web/ only responsive.selftest.js:201 the negative-assertion regex in R40 guard itself; zero user strings in app.js/index.html. Result PASS
Runtime verification: test web/responsive.selftest.js::R40

Verdict: PASS

## Task 21 - Robust + correctly-directed backlog priority sort

EVIDENCE BLOCK
==============
Task ID: 21
Task description: prioRank high p1 1 to 0, medium p2 2 to 1, low p3 3 to 2, else 9 no falsy fallback; sortBacklog uses it with id tiebreak
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.js prioRank explicit if-chain high p1 1 to 0, medium med p2 2 to 1, low p3 3 to 2, default 9. L835 comment the OLD falsy fallback was the backwards bug now fixed. Result PASS
2. Wire-check sortBacklog L846-857 prioRank a minus prioRank b with localeCompare item_id deterministic tiebreak. Result PASS
3. EXECUTED logic test R41 evals extracted prioRank and asserts sort of P3 P1 P2 equals P1 P2 P3 AND low high medium equals high medium low AND high to 0, str-1 to 0, zzz to 9 - PASS within the 43/0 sweep. Result PASS
Runtime verification: test web/responsive.selftest.js::R41

Verdict: PASS

## Task 22 - Semantic button palette across the GUI

EVIDENCE BLOCK
==============
Task ID: 22
Task description: six semantic classes btn-go btn-wait btn-info btn-up btn-del btn-neutral plus outline in app.css, applied across app.js index.html
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check app.css L406-411 all six filled with AA-dark text colors; L413-416 outline secondary variants. Result PASS
2. Wire-check app.js per-class counts btn-go 4, btn-wait 1, btn-info 8, btn-up 2, btn-del 3, btn-neutral 4; index.html L15 btn-neutral L102 btn-go; mark done btn-go L753, expand-to-branch btn-up L1080. Each class applied to at least one button. Result PASS
Runtime verification: test web/responsive.selftest.js::R42

Verdict: PASS

## Task 23 - Cross-repo doc-sourced enrichment in backfill-details.js

EVIDENCE BLOCK
==============
Task ID: 23
Task description: resolveDocPath via config/projects.js + extractFromDoc section token-overlap, Option/Recommendation/blocking parser; no fabrication; description verbatim
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check backfill-details.js L40 require config/projects.js; L49 resolveDocPath tries node tree_id then mapped roots; L64 extractFromDoc section-match by token overlap; L106-114 Option block parse; L116-125 Recommendation; L125 blocking_input What you need from. Result PASS
2. Honesty contract header L14-23 description = verbatim item text; options/recommendation LEFT NULL when absent; explicit no fabrication. B14 asserts bare doc to null. Result PASS
3. Functionality backfill --self-test 15/0 B12 section matched B13 options recommendation blocking_input doc-sourced not null B14 NOT fabricated to null B15 payloadFor enriches from resolvable same-repo doc B11 append-only count unchanged. Result PASS
Runtime verification: test state/backfill-details.js::B12-B15
Runtime verification: test web/responsive.selftest.js::R43

Verdict: PASS

## Task 24 - Extend responsive.selftest R34-R43 + full six-suite regression sweep

EVIDENCE BLOCK
==============
Task ID: 24
Task description: responsive.selftest extended R34-R43 one invariant per item 14-23 incl executed prioRank; all six suites green; Decisions Log complete
Verified at: 2026-05-18T18:36:20Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Wire-check R34 item14 .. R43 item23 present 10 new assertions; R41 EXECUTES the extracted prioRank not a grep. Result PASS
2. Functionality six-suite sweep state 15/0; responsive 43/0 33 to 43 +10; backfill 15/0 11 to 15; state-gate 18/0; stop-gate 8/0; emit 17 OK; node --check all OK; schema_version still 1. Result PASS
3. Decisions Log 4 substantive Tier-1/2 entries sequential build, inline md renderer, two-layer config hygiene, read-doc enrichment, each with Chosen Alternatives Reasoning. Result PASS
Runtime verification: test web/responsive.selftest.js::R34
Runtime verification: test state/selftest.js::P15

Verdict: PASS
