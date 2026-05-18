# Plan: Conversation Tree UI v1.1 — responsive layout + popup + tree fixes
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer (Misha) is the live user verifying this session directly via viewport-resize + screenshots; the conv-tree gate/emitter self-tests + the web-module state self-test are the acceptance artifact; there is no separate product end-user.
Backlog items absorbed: none

## Goal
Misha opened the Conv Tree UI live (master `ce216ad`, server on `127.0.0.1:7733`) at his actual typical window size — the vertical half of a 4k screen (~960×2160). The DEC-A LOCKED layout assumed a min 1440×900 three-pane side-by-side, so at his real viewport the actions+backlog panes are pushed off-screen, the context/popup pane permanently occupies real estate with a dead X button, the Fit button does not fit, and zoom-out leaves dead horizontal space. Ship a v1.1 that makes the GUI usable at his real viewport without regressing the ≥1440px experience.

## Scope
- IN: `neural-lace/conversation-tree-ui/web/app.css`, `web/app.js`, `web/index.html` — responsive breakpoint layout (CSS Grid template-areas + media queries), ctx/popup pane → dismissible overlay (wire X + click-outside + dock-wide/overlay-narrow), top-bar hide-concluded toggle (persisted, filters fully-concluded subtrees), Fit button → true fit-to-viewport, zoom −/+ → flex-fluid line-item reflow. DEC-A Decisions-Log entry extended with the additive responsive-breakpoint clause. A headless responsive regression check.
- OUT: state schema / reducer / `state/*.js` changes (frozen ADR-032 contract — hide-concluded persists via the existing localStorage UI-pref convention, NOT a new event type). The conv-tree gate hooks (`adapters/claude-code/hooks/conversation-tree-*.sh`) — untouched; re-run their self-tests only to prove no regression. NL-CTREE-006 (prompt()→inline forms, P2) — separate backlog item, not this batch.

## Tasks

- [ ] 1. Responsive breakpoint layout: CSS Grid template-areas + media queries (≥1440 three-pane unchanged; <1440 & ≥1440h vertical stack; <1024 & <1024h single-pane tabs); pane min-width → ~280px; page never scrolls — Verification: full
  **Prove it works:** 1. Open GUI at 1920×1080 → three-pane side-by-side (unchanged). 2. Resize to 960×2160 → tree top half, actions+backlog bottom half, no pane off-screen, no page scroll. 3. Resize to 1280×800 → vertical stack. 4. Resize to 700×900 → single-pane with Tree|Waiting|Backlog tabs. 5. Backfilled 45-node tree still renders in every shape.
  **Wire checks:** `web/index.html` (layout DOM + tab buttons) → `web/app.css` (`#layout` grid-template-areas + `@media` breakpoints) → `web/app.js` (tab switch handler for the small-viewport mode)
  **Integration points:** `node -e` headless check toggling viewport classes asserts grid-template-areas per breakpoint; manual viewport screenshots at the 4 shapes.
- [ ] 2. Context/popup pane → dismissible overlay: wire the X button, click-outside-to-close, dock right at wide viewports / overlay the tree at narrow — Verification: full
  **Prove it works:** 1. Click a tree node → ctx panel opens. 2. Click its ✕ → it closes (currently dead). 3. Click outside it → closes. 4. At ≥1440px it docks beside the tree without pushing panes; at <1440px it overlays.
  **Wire checks:** `web/app.js` (`openCtx`/`closeCtx` + outside-click listener + `sel`-clear) → `web/index.html` (`#ctxPanel`) → `web/app.css` (`.ctx-panel` overlay vs dock media rules)
  **Integration points:** preview_click the ✕ and an outside point; assert `#ctxPanel` hidden after each.
- [ ] 3. Top-bar hide-concluded toggle, persisted (localStorage UI-pref convention), default OFF=hide; filters concluded leaves AND branches whose entire subtree is concluded — Verification: full
  **Prove it works:** 1. Toggle present in header, default hides concluded. 2. With it off, a fully-concluded subtree is absent from the tree render. 3. Toggle on → concluded reappear. 4. Reload → preference persisted.
  **Wire checks:** `web/index.html` (`#showConcluded` control) → `web/app.js` (`visibleNodes`/`forest` subtree-concluded filter + localStorage `ctree-show-concluded`) → `web/app.css` (control style)
  **Integration points:** preview_eval reads localStorage + asserts concluded node count in DOM before/after toggle.
- [ ] 4. Fix Fit button → true fit-to-viewport (bbox of rendered tree → zoom scale that fits with padding → apply scale + scroll to top-left/center) — Verification: full
  **Prove it works:** 1. Zoom in until tree overflows. 2. Click ⊙ fit → whole tree fits inside the visible tree-pane area with small padding, scaled, scrolled into view. 3. Works with no node selected (currently no-ops without selection).
  **Wire checks:** `web/app.js` (`fitSel` handler: `treeCanvas.scrollWidth/Height` + `treeScroll.clientWidth/Height` → `zoom` → `renderTree` + scroll reset) → `web/index.html` (`#fitSel`)
  **Integration points:** preview_eval sets zoom=2, clicks fit, asserts canvas bbox ≤ viewport.
- [ ] 5. Fix zoom −/+ → line-item widths flex-fluid relative to available width; reflow on zoom change so zoom-out has no dead horizontal space — Verification: full
  **Prove it works:** 1. Zoom out → tree node rows reflow to fill available width (no fixed-min dead space on the right). 2. Zoom in symmetrically. 3. Backfilled tree readable at every zoom step.
  **Wire checks:** `web/app.css` (`.tnode-canvas`/`.tnode-row` fluid width vs fixed min) → `web/app.js` (`renderTree` zoom transform + width recompute)
  **Integration points:** preview_eval steps zoom 0.4→2, asserts row width tracks container width.
- [ ] 6. DEC-A additive revision in Decisions Log + headless responsive regression check + opportunistic inline fixes for any unambiguous bug found at the real viewport — Verification: full
  **Prove it works:** 1. Decisions Log has the DEC-A responsive-breakpoint clause (≥1440 explicitly unchanged). 2. Regression check passes for all 4 viewport shapes. 3. Gates 18/18 + 8/8, emit 17/17, state selftest 14/14 still PASS. 4. Backfilled state file byte-identical (sha256 unchanged).
  **Wire checks:** `docs/plans/conv-tree-ui-v1.1-responsive.md` (Decisions Log) → `neural-lace/conversation-tree-ui/web/app.css` (the breakpoint rules the regression asserts)
  **Integration points:** re-run all four self-test suites; sha256sum the state file vs baseline.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.css` — responsive Grid template-areas + media-query breakpoints; ctx-panel overlay/dock rules; fluid tree-row widths; hide-concluded control style.
- `neural-lace/conversation-tree-ui/web/app.js` — small-viewport tab switching; ctx overlay open/close + outside-click; hide-concluded filter + localStorage persist; true fit-to-viewport; zoom reflow.
- `neural-lace/conversation-tree-ui/web/index.html` — tab-bar DOM for small viewport; hide-concluded toggle control in header; minor structural hooks for grid areas.
- `docs/plans/conv-tree-ui-v1.1-responsive.md` — this plan; Decisions Log carries the additive DEC-A revision.

## In-flight scope updates

## Assumptions
- The backfilled 45-node tree-state.json (sha256 `8a403e54…`) copied into the worktree's gitignored `state/` dir faithfully represents what Misha sees live; rendering it correctly at each viewport is the render-correctness proof.
- The conv-tree gate/stop/emit hooks live under `adapters/claude-code/hooks/` and are not touched by web/ changes, so their self-tests stay green by construction (re-run to confirm, not to fix).
- localStorage is the established persistence substrate for every existing UI preference in this app (zoom, collapsed, activeTree, projects, drafts, fired-defers); hide-concluded follows that convention. The user requested "persist in the state file"; the frozen ADR-032 schema + conv-tree-state-gate make a new event type a contract-surface change disproportionate to a view toggle — deviation surfaced for the user per friction-reflexion.
- CSS Grid `grid-template-areas` + `@media` is sufficient to express all three layouts with zero JS layout math (JS only toggles a body-level mode class for the tabbed small view).

## Edge Cases
- Viewport exactly at a breakpoint boundary (1440, 1024): media queries use `min-width`/`min-height` with non-overlapping ranges so exactly one layout applies.
- Tall-and-narrow (960×2160) vs short-and-narrow (1280×800): both fall in the vertical-stack band (width<1440 & height≥… ) — actions+backlog go side-by-side if the stacked region is ≥700px wide, else stacked.
- A tree whose every root subtree is concluded with hide-concluded ON → tree pane must show the steady-empty state ("all concluded — toggle Show concluded"), never a blank canvas (preserve the existing four-never-conflated pane-state contract).
- Fit with an empty/first-run tree → no-op gracefully (no NaN scale).
- ctx overlay open while resizing across the dock/overlay breakpoint → stays consistent (CSS-driven, not JS-cached geometry).
- Page-never-scrolls invariant (BF-3) must hold in every layout including the tabbed one.

## Testing Strategy
- Item 1–5: live preview server on port 7744 (separate from Misha's 7733) reading the copied backfilled state; preview_resize to 1920×1080 / 960×2160 / 1280×800 / 700×900; screenshot + preview_eval assertions per item's Integration points.
- Item 6: headless `node` regression asserting computed `grid-template-areas` per emulated viewport; full self-test sweep (state-gate 18/18, stop-gate 8/8, emit 17/17, state/selftest.js 14/14); `sha256sum` state file vs baseline `8a403e54…`.
- Dispatch emitter end-to-end: spawn a dummy session, confirm GUI auto-populates (proves the read path still works post-CSS/JS change).

## Walking Skeleton
The thinnest end-to-end slice: add the `@media` block + `grid-template-areas` to `#layout` and a body mode class; load the backfilled state at 960×2160; confirm all three panes are visible and the page does not scroll. Everything else (overlay, toggle, fit, zoom reflow) layers onto that proven skeleton.

## Decisions Log

### Decision: DEC-A revised — additive responsive-breakpoint clause
- **Tier:** 2
- **Status:** proceeded with recommendation (user-directed; confirmed approach in the request)
- **Chosen:** DEC-A's original "min viewport 1440×900, three-pane side-by-side" is RETAINED UNCHANGED for width ≥ 1440px. Added clause: width < 1440px AND height ≥ 1440px → vertical stack (tree top, actions+backlog bottom); width < 1024px AND height < 1024px → single-pane with top tabs. Pane min-width relaxed 1440→~280px. CSS Grid `grid-template-areas` + `@media`, zero JS layout math.
- **Alternatives:** (a) JS-driven layout (rejected — user explicitly requested CSS-only; more failure surface). (b) Lower the single global min-width to 280 with flex reflow only (rejected — does not give the deliberate vertical-stack Misha wants at 960×2160). (c) Replace DEC-A wholesale (rejected — would regress the ≥1440 experience that already works; the user specified additive).
- **Reasoning:** The ≥1440 case is provably unchanged (same grid-areas as today's flex), so this EXTENDS DEC-A rather than contradicting it. Misha confirmed the breakpoint approach in the request.
- **To reverse:** revert the `@media` blocks in app.css; the ≥1440 default rule is the original layout.

### Decision: hide-concluded persists via localStorage, not the state file
- **Tier:** 1
- **Status:** proceeded with recommendation — surfaced to user per friction-reflexion
- **Chosen:** Persist the hide-concluded preference in `localStorage` (`ctree-show-concluded`), consistent with every other UI preference in this app.
- **Alternatives:** state-file persistence via a new `ui-setting-changed` event type (rejected for this batch — touches the frozen ADR-032 contract surface + conv-tree-state-gate + reducer + 3 self-test suites; disproportionate risk + latency for a view toggle when the user wants the fixes ASAP).
- **Reasoning:** Reversible; matches established convention; zero schema/gate blast radius. The user asked for state-file persistence — deviation + rationale surfaced in the completion report for the user's call.
- **To reverse:** add the event type + reducer case + schema enum entry + selftest later (a clean separate plan if the user wants cross-device persistence).

## Definition of Done
- [ ] All 6 tasks task-verified PASS
- [ ] Verified at 1920×1080, 960×2160, 1280×800, 700×900 with screenshots
- [ ] Backfilled state file sha256 unchanged (`8a403e54…`)
- [ ] conv-tree state-gate 18/18, stop-gate 8/8, emit 17/17, state/selftest.js 14/14 — no regression
- [ ] Dispatch emitter end-to-end re-confirmed (dummy spawn auto-populates GUI)
- [ ] One PR merged to neural-lace master; main checkout synced; Misha's 7733 server restarted on new code
- [ ] SCRATCHPAD.md updated; completion report appended
