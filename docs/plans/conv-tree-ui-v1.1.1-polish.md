# Plan: Conversation Tree UI v1.1.1 — polish (items 14–18)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer (Misha) is the live user verifying via the running GUI; conv-tree gate/emitter self-tests + the web-module state self-test + responsive.selftest.js are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal
Items 1–13 shipped & merged (PR #4 items 1–6, PR #9 items 7–13, master `5c224e8`). Misha kept live-using the GUI and surfaced 5 polish items (14–18) on EXISTING behavior — no new features, no schema change. Ship as a fast-follow v1.1.1 PR. Misha's stated preference: working visible behavior now, polish soon.

## Scope
- IN: `web/app.css`, `web/app.js`, `web/index.html` — type-coded palette (14), title flex + icon-button crumb (15), prominent + sane-defaulted hide-concluded toggle (16), bidirectional item↔tree highlight w/ tint + scroll-into-view (17), bottom-right toast + arrival-flash on affected location (18). `web/responsive.selftest.js` extended.
- OUT: state schema / reducer / `state/*.js` (zero schema change — pure client polish). The conv-tree gate hooks — untouched; re-run self-tests for no-regression only. v1.2 Dispatch-side reader (NL-FINDING-011, separate session).

## Tasks

- [ ] 1. Item 14: type-coded palette — action=red, decision=amber, question=blue — on the `[type]` label + a 4–6px left-border stripe on the item card (+ optional ≤6% bg wash), in the Waiting pane; WCAG AA on dark — Verification: full
  **Prove it works:** 1. An action item shows a red `[action]` label + red left stripe; decision = amber; question = blue. 2. Label text passes AA contrast on the dark bg. 3. Consistent (same vars) wherever the type label/stripe appears.
  **Wire checks:** `web/app.css` (`--ty-action/-decision/-question` + `-rgb` vars; `.li-kind.action/.decision/.question`; `.li.kind-*` left stripe) → `web/app.js` (`renderActions` adds `kind-<kind>` class to the li)
  **Integration points:** preview_eval reads computed color of `.li-kind.action` etc. + asserts the left-border color per kind.
- [ ] 2. Item 15: title owns row width (`flex:1`); right-side text crumb → fixed ~24px icon-button "→" with tooltip "Jump to in tree"; same click→focusNode — Verification: full
  **Prove it works:** 1. `.li-text` is flex:1 and not crushed. 2. The jump affordance is a ~24px square icon-button (not a width-greedy text link), tooltip "Jump to in tree", click still navigates to the tree node.
  **Wire checks:** `web/app.js` (`renderActions` crumb → icon-button `.li-jump`) → `web/app.css` (`.li-jump` fixed 24px; `.li-text` flex:1)
  **Integration points:** preview_eval asserts `.li-jump` ~24px, title flex-grows, click focuses the node.
- [ ] 3. Item 16: hide-concluded default UNCHECKED (hide concluded on first load) + make the toggle prominent (eye icon, larger label, grouped near + project in a "View" group) — Verification: full
  **Prove it works:** 1. Fresh load (no localStorage key) → concluded hidden by default. 2. The toggle is visibly prominent (eye glyph + larger label, in a delineated View group near + project), discoverable. 3. Behavior (hide concluded leaves AND fully-concluded subtrees) unchanged from item 3.
  **Wire checks:** `web/index.html` (toggle moved into a `.view-filters` group near `#addProjBtn`, eye glyph, larger) → `web/app.css` (`.view-filters`/`.toggle-prom`) → `web/app.js` (default already false; unchanged filter logic)
  **Integration points:** preview_eval: localStorage cleared → reload → 0 concluded rows; toggle element bigger/grouped.
- [ ] 4. Item 17: bidirectional item↔tree highlight — full interior type-color tint (~15–20%) + 3–4px solid left accent; both directions (item→node AND node→item/backlog); smooth scroll-into-view of the other side — Verification: full
  **Prove it works:** 1. Click a Waiting item → its tree node gets a full interior tint (type color ~18%) + left bar AND scrolls into view. 2. Click a tree node → the corresponding Waiting item(s) get the same tint + scroll into view. 3. Tint color matches the item's type (action/decision/question palette).
  **Wire checks:** `web/app.js` (shared `selNodeId`; `renderActions` tints items whose node===selNodeId; `renderTreeNode` tints the selected node by its dominant item kind; both call `scrollIntoView`) → `web/app.css` (`.li.sel-link`, `.tnode-row.sel-tint` per-kind tints)
  **Integration points:** preview_eval clicks an item → asserts tree node tinted + the reverse (click node → item tinted) + scroll.
- [ ] 5. Item 18: toast → bottom-right (bottom-center on narrow) + arrival-flash (600ms type-color tint, reduced-motion = single-frame persist ~1.5s) on the affected item/backlog/tree-node on toast OR SSE arrival OR state change; + DEC log + extend responsive.selftest.js + full regression — Verification: full
  **Prove it works:** 1. A toast appears bottom-right (bottom-center < ~700px). 2. mark-done / new SSE item / conclude → a 600ms type-tinted flash on the affected location. 3. prefers-reduced-motion → single-frame highlight persisting ~1.5s (no fade). 4. responsive.selftest.js extended + all green; gates 18/8/17, state selftest 15/15 unchanged.
  **Wire checks:** `web/app.css` (`.toast` bottom-right + narrow media; `@keyframes arrival-flash`; reduced-motion variant) → `web/app.js` (flash the affected node/li on post-success + SSE diff) → `web/responsive.selftest.js` (new R34+ assertions)
  **Integration points:** preview_eval asserts toast right-anchored at wide; flash class applied on a state change; regression suite green.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.css` — type-color vars + `.li-kind`/`.li.kind-*`; `.li-jump`/`.li-text` flex; `.view-filters`/prominent toggle; `.sel-link`/`.sel-tint` per-kind tints; `.toast` bottom-right + narrow; `@keyframes arrival-flash` + reduced-motion.
- `neural-lace/conversation-tree-ui/web/app.js` — kind class on li; icon-button jump; shared selNodeId bidirectional tint + scrollIntoView; arrival-flash on post/SSE/state-change.
- `neural-lace/conversation-tree-ui/web/index.html` — View-filters group + prominent hide-concluded toggle markup.
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — extend with the 14–18 invariants.
- `docs/plans/conv-tree-ui-v1.1.1-polish.md` — this plan.

## In-flight scope updates

## Assumptions
- The existing semantic palette (`--err` red, `--warn` amber, `--info` blue) already passes AA on the `#111827` dark bg (it is the established harness UX standard); item 14's palette aliases/tunes these. Verified per-kind via computed-style.
- Zero schema change — items 14–18 are pure client polish; no `state/*.js` touched; gates key off schema major (unchanged) → 18/8/17 green by construction (re-run to confirm).
- hide-concluded already defaults to hide (localStorage absent → false) from item 3; item 16 is prominence + confirming the default, not a logic change.
- This plan does NOT mutate the live state file (no backfill / events) — the v1.1-responsive byte-integrity-style bar applies: existing tree renders unchanged after the CSS/JS polish.

## Edge Cases
- A node with mixed item kinds (action+decision+question): the selected-node tint uses a deterministic dominant kind (action > decision > question precedence — most-urgent wins) so the tint is stable.
- Reduced-motion: arrival-flash must NOT animate-fade; single-frame highlight persisting ~1.5s then removed (still clearly visible). The existing `@media (prefers-reduced-motion: reduce)` block extends to the new keyframes.
- Narrow viewport (single-pane tabs, <1024&<1024): toast bottom-center (not right) so it doesn't clip; bidirectional scroll-into-view still works within the active tab.
- Clicking a tree node whose items are all concluded+hidden: no Waiting item to tint — no error, just the node highlight.
- AA contrast: if a raw type hex fails on dark, use the tinted-bg + lighter-text variant; assert computed contrast intent via the established `--err/--warn/--info` (already AA).
- Page-never-scrolls (BF-3) + responsive breakpoints (items 1–6) + items 7–13 behavior all remain intact under the restyle.

## Testing Strategy
- Live preview (:7744) on the refreshed real state at 960×2160 + 1920×1080: per-item preview_eval assertions (computed colors, element sizes, tint classes, scroll, toast anchor).
- `web/responsive.selftest.js` extended (R34+) — locks the 14–18 CSS/HTML/JS invariants; existing R1–R33 stay green.
- Regression: conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17 (untouched), `state/selftest.js` 15/15 (untouched), `backfill-details.js --self-test` 11/11.

## Walking Skeleton
Thinnest slice proving the shared mechanism the rest builds on: define the `--ty-action/-decision/-question(+-rgb)` CSS vars and apply them to `.li-kind.action/.decision/.question` (item 14 label color). Confirm at 960×2160 the three labels render their distinct colors and items 1–13 are visually intact. Items 15–18 then layer onto that proven palette.

## Decisions Log

### Decision: type palette aliases the established semantic colors (AA-safe)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `--ty-action` = red (`--err` family #f87171), `--ty-decision` = amber (`--warn` #fbbf24), `--ty-question` = blue (`--info` #60a5fa) + `*-rgb` tuple vars for low-opacity washes/tints. These are the harness's established AA-on-dark semantic colors.
- **Alternatives:** raw spec hexes (#DC2626/#F59E0B/#3B82F6) verbatim (rejected — #DC2626 on #111827 is borderline for small label text; the established lighter family is AA-safe and already used consistently elsewhere). The spec explicitly allowed "lighten or use a tinted background" if raw hex fails AA.
- **Reasoning:** consistency with the existing palette + guaranteed AA; one var set drives 14/17/18 so the type-coding is identical everywhere (the spec's "consistent everywhere" requirement).
- **To reverse:** retune the three vars in `:root`.

### Decision: selected-node tint uses dominant-kind precedence action>decision>question
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** a node with mixed item kinds tints by its most-urgent open item kind (action > decision > question).
- **Alternatives:** tint by the clicked item's kind only (rejected — node→item reverse direction has no single clicked item; need a deterministic node color); multi-stripe (rejected — muddies the design per item 14's own "don't muddy" guidance).
- **Reasoning:** deterministic, stable across both highlight directions, surfaces the most-urgent signal.
- **To reverse:** change the precedence array in the dominant-kind helper.

## Definition of Done
- [ ] All 5 tasks task-verified PASS
- [ ] Items 14–18 demonstrated live at 960×2160 + 1920×1080
- [ ] WCAG AA intent held (type colors = established AA-on-dark semantic palette)
- [ ] Items 1–13 behavior + responsive layout intact under the restyle
- [ ] `web/responsive.selftest.js` extended + all green; gates 18/8/17; state selftest 15/15; backfill 11/11
- [ ] Live state file unchanged (no events emitted by this plan)
- [ ] One PR merged to neural-lace master; main checkout synced; :7733 restarted
- [ ] Completion report appended; SCRATCHPAD regenerated
