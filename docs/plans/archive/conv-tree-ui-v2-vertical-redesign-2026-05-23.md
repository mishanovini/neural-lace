# Plan: Conversation Tree UI — v2 vertical redesign (2026-05-23)
Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: backlog-context-set event + context_text persistence + v2 vertical layout in workstreams-ui. Shipped PR #32 (b93fdaf), carried via fork unification e99e4b6 / reconverge 3a2babc. Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: frontend-only
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Conversation Tree UI is harness-internal tooling; the maintainer (Misha) is the user and the self-test + manual viewport walk-through is the acceptance artifact.
Backlog items absorbed: none

## Goal
Reshape the Conversation Tree GUI per Misha's 2026-05-23 feedback: "Too
many panels keep trying to cram themselves in horizontally. I want to
be able to use this easily with a narrower window and I like having the
tree itself have access to the full vertical space in the window, which
means I would prefer to keep all additional panels to the side instead
of taking up space below. I think we could also use popup modals in
more circumstances and reduce the horizontal cramming. I don't think
the tree itself needs to take up so much horizontal space."

Plus the follow-up requirement (same day): "Just a title isn't very
useful. The context is critical, and it should open into a larger
textbox, not a single line."

## Scope

IN:
- `neural-lace/conversation-tree-ui/web/index.html` — DOM restructure (always-visible #paneTabs, drawer peek pill, dispatch composer modal, textarea for context capture)
- `neural-lace/conversation-tree-ui/web/app.css` — rewrite layout from Layout A/B/C scheme to single responsive template (tree narrow + side panel + class-based drawer state); modal contract for ctxPanel + docModal + dispatchModal; context-area styles
- `neural-lace/conversation-tree-ui/web/app.js` — modal-style openCtx/openDocModal; new applyPaneTab + applySideState handlers; Send-to-Dispatch composer modal; backlog context disclosure (read/edit textarea) + capture-time context_text persistence
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — rewrite to lock the v2 layout contract (48 assertions across R1-R78)
- `neural-lace/conversation-tree-ui/state/schema.js` — add additive `backlog-context-set` event (schema major still 1)
- `neural-lace/conversation-tree-ui/state/reducer.js` — handle `backlog-context-set`; persist `context_text` on `backlog-added`
- `neural-lace/conversation-tree-ui/docs/ux-audit-2026-05-23.md` — full audit (13 findings) backing the redesign
- `neural-lace/conversation-tree-ui/.claude/launch.json` — preview-tool config (CTREE_PORT=7799 to avoid colliding with user's running v1 server on 7733)

OUT:
- Any product-code changes (none touched)
- Tree node keyboard navigation, global keyboard shortcuts, virtualization, full a11y audit — captured as UX-VR-08 through UX-VR-12 in the audit doc as deferred follow-ups
- Cross-project consumer changes
- Schema major bump (additive only)

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/index.html` — rewrite DOM
- `neural-lace/conversation-tree-ui/web/app.css` — rewrite layout
- `neural-lace/conversation-tree-ui/web/app.js` — surgical edits per the new layout contract
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — rewrite assertions
- `neural-lace/conversation-tree-ui/state/schema.js` — add `backlog-context-set` event
- `neural-lace/conversation-tree-ui/state/reducer.js` — handle the new event + persist `context_text` on `backlog-added`
- `neural-lace/conversation-tree-ui/docs/ux-audit-2026-05-23.md` — new audit doc
- `neural-lace/conversation-tree-ui/.claude/launch.json` — new preview-tool config

## In-flight scope updates

## Tasks
- [x] 1. Author audit doc identifying layout / interaction / modal-candidate findings — Verification: mechanical
- [x] 2. Rewrite CSS layout (tree narrow column + persistent side panel + drawer at <1024px + modal contract for ctx/doc/dispatch) — Verification: mechanical
- [x] 3. Rewrite HTML DOM (new tab nav, peek pill, dispatch modal, context textarea in capture form) — Verification: mechanical
- [x] 4. Patch JS for modal-style ctx + doc, paneTabs handler, drawer state, dispatch composer, backlog context UI — Verification: mechanical
- [x] 5. Add additive `backlog-context-set` event + reducer case + persist `context_text` on `backlog-added` — Verification: mechanical
- [x] 6. Rewrite responsive.selftest.js to lock the v2 contract — Verification: mechanical
- [x] 7. Run state selftest + responsive selftest (both green) — Verification: mechanical
- [x] 8. Manual viewport walk at 1920 / 1280 / 900px via preview MCP — Verification: mechanical

## Assumptions
- The current GUI users (Misha + future harness maintainers) use modern browsers (Chrome/Firefox/Safari evergreen). No IE11 support required.
- The reducer's existing acceptance of an optional `context` field on `backlog-added` was a silent drop bug (the field was passed in capture but never persisted). Fixing it as part of UX-VR-13 is correct, not a behavior break.
- The conversation-tree-emit hook and the conv-tree-state gates do not read `context_text` and are not affected by the schema addition.
- A simultaneous user-side v1 server on port 7733 will keep working through this PR — the preview tool runs on 7799 to avoid collision.

## Edge Cases
- Persisted localStorage state (`ctree-pane-tab`, `ctree-side`) from a v1 GUI session is harmless on v2 (defaults handle missing/unrecognized values).
- Migration: existing backlog items with no `context_text` show "Add context →" affordance — no migration script needed.
- CSS transitions on the drawer slide may show an intermediate `right` value during the 160ms window; the final computed value is correct (verified with `transition: none` in the preview eval).
- Modal stacking: opening doc viewer while detail modal is open: both modals visible; the later-added one wins by DOM order. Acceptable for v1; can refine later.
- Schema additivity: a downstream consumer of the conv-tree state JSON that uses an older copy of the schema will see `backlog-context-set` as an unknown event type and skip it. This is the documented additivity contract.

## Testing Strategy
- Mechanical: `node web/responsive.selftest.js` locks 48 contract assertions (R1-R78). `node state/selftest.js` (17 assertions) confirms the schema+reducer extension preserves all prior invariants.
- Manual: walk preview MCP at 1920x1080, 1280x800, 1000x768, 900x800. Verify (a) tree narrow + side panel beside it at >=1024, (b) drawer + peek pill at <1024, (c) modals don't shift the persistent layout, (d) backlog capture form uses textarea, (e) per-item context disclosure renders read+edit modes.

## Walking Skeleton
Smallest end-to-end slice that exercises every architectural layer:
schema → reducer → server SSE → client app.js render → DOM → CSS → user
interaction. The schema event flows through the existing state-library
appendEvent path; the reducer mutates `snap.backlog[i].context_text`; the
server's existing SSE state broadcast picks up the change; the GUI's
existing `renderBacklog()` flow re-renders; the new disclosure UI shows
the updated context. Layered tests pass at each step.

## Decisions Log
### Decision: class-based body state, not data attributes
- Tier: 1
- Status: implemented
- Chosen: `body.classList.add('side-open')` instead of `body.dataset.side = 'open'`
- Reasoning: class-based selectors avoid the CSS cascade puzzle hit during initial implementation (CSS `body[data-side="open"]` rules failed to apply due to specificity ordering with adjacent unconditional rules). Class selectors have explicit specificity, simpler cascade behavior, and easier selftest pattern matching.

### Decision: drawer slides via `right` not `transform`
- Tier: 1
- Status: implemented
- Chosen: off-canvas via `right: calc(-1 * min(var(--side-panel-w), 92vw))` + open via `right: 0`
- Reasoning: `transform` failed to apply in real-time during testing (cascade interaction with media-query rules). `right` is a single-value property and cascades cleanly.

### Decision: backlog context as new additive event vs reusing context-attached
- Tier: 1
- Status: implemented
- Chosen: new `backlog-context-set` event (item_id, context_text)
- Reasoning: `context-attached` semantically attaches a REFERENCE (doc path, prior-decision URL), not free-form prose. The two are distinct kinds of context — refs are short tokens, the prose textarea is paragraphs of background. Reusing context-attached would conflate them. New event keeps the data model clean. Schema major stays 1 (additive).

## Definition of Done
- [x] Both selftests green
- [x] Manual preview walk confirms layout contract at 4+ viewport widths
- [x] Plan file authored + ACTIVE (this file)
- [x] Commit pushed to feat/conv-tree-ui-vertical-redesign-2026-05-23
- [x] PR opened against master (do NOT merge — Misha reviews)
