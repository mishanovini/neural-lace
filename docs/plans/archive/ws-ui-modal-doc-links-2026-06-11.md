# Plan: Workstreams-UI — in-modal doc links open in-app via the Docs viewer
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Operator-directed (Misha, 2026-06-11, verbatim): "That link needs to actually work directly right here and
open within the Workstreams UI… a pointer to a document is sufficient [but] that link needs to actually
work." Today the item-detail modal renders document references (e.g. `REDESIGN-PRD-DRAFT-2026-06-10.md`,
`docs/reviews/x.md`) as inert styled chips — the 2026-06-02 port note in app.js says so explicitly
("informational rather than click-to-open"). The operator reading a redesign question must leave the GUI
and hunt the file down manually. This plan makes every document reference in the modal's details rendering
a clickable link that opens the document IN-APP via the existing Docs-viewer subsystem (/api/doc →
openDocModal), and makes the server able to resolve coordination-repo docs (which live at the repo ROOT
of `~/claude-projects/workstreams-coordination`, with no `docs/` subdir — so the existing auto-discovery
skips that repo entirely and /api/doc could not serve its files).

## User-facing Outcome
The operator opens a redesign question in the item-detail modal, sees `REDESIGN-PRD-DRAFT-2026-06-10.md`
rendered as a link, clicks it, and the full PRD displays in the in-app document viewer layered above the
modal — no new tab, no file://, no leaving the Workstreams UI. `docs/…` repo paths in any details field
behave identically (resolving against the item's own project or the harness repo). Esc closes the viewer
first and the detail modal second.

## Scope
- IN: `neural-lace/workstreams-ui/web/app.js` (linkifyDocs upgraded to clickable buttons matching `docs/…`
  paths AND bare `*.md` names; new openDocSmart candidate-probing resolver; openDocInApp bridge out of the
  docsBrowser IIFE; references/links gates widened; Esc-layering fix); `neural-lace/workstreams-ui/web/app.css`
  (clickable chip styling; doc-viewer z-index above the detail modal); `neural-lace/workstreams-ui/config/projects.js`
  (stable `workstreams-coordination` alias when the repo exists on this machine; listDocs root-`*.md`
  fallback for projects without `docs/`); `neural-lace/workstreams-ui/web/responsive.selftest.js` (R28
  regression lock).
- OUT: server.js routes (unchanged — /api/docs, /api/doc, /api/doc/open already exist and suffice);
  state lib (schema/reducer/store untouched); markdown renderer changes; any spawn/steer affordance
  (Option-2 invariant untouched); cross-link resolution for non-.md references (branch jumps stay toasts);
  the OS open-in-editor path (unchanged, still offered by the viewer).

## Tasks

- [x] 1. Server resolution (config/projects.js): coordination-repo alias + root-md listDocs fallback + traversal-guard checks — Verification: mechanical
  Add a stable `workstreams-coordination` alias to loadProjects() (runtime-computed via os.homedir(),
  present only when the repo exists; explicit config still wins) and a root-level `*.md` listDocs fallback
  (depth ≤ 2, discovery skip-rules) for projects without `docs/`; verify resolveDoc serves
  `REDESIGN-PRD-DRAFT-2026-06-10.md` and still rejects `../` traversal and absolute paths.
- [x] 2. Client in-modal doc links (web/app.js + app.css): clickable chips that open docs in-app — Verification: mechanical
  Rewrite linkifyDocs to emit clickable chips for `docs/…` paths AND bare/pathed `*.md` tokens
  (URL-embedded tokens stay plain text; textContent-only DOM, no innerHTML); add openDocSmart (probes
  /api/doc candidates: explicit project prefix > item project > neural-lace > workstreams-coordination,
  bare names coordination-first) opening via the openDocInApp bridge to the Docs-viewer openDocModal;
  widen the references/links doc-test gates; layer #docScrim/#docModal/#docsPanel above the detail
  modal; Esc closes the viewer first, the modal second.
- [x] 3. Regression lock + runtime proof (responsive.selftest.js R28 + headless flow) — Verification: mechanical
  Add R28 locking the new invariants (openDocSmart defined, bridge assigned, clickable chips, bare-.md
  matcher, coordination candidate, Esc layering, CSS z-indexes); both selftests green (responsive 28/28,
  state 20/20); headless-browser flow against a live server: open redesign Q1 modal → doc reference
  renders as link → click → coordination-repo PRD displays in-app → `docs/backlog.md` link opens the
  neural-lace doc → zero console errors.

## Files to Modify/Create
- `neural-lace/workstreams-ui/web/app.js` — clickable linkifyDocs + openDocSmart + openDocInApp bridge + Esc layering
- `neural-lace/workstreams-ui/web/app.css` — button.det-link-doc styling + doc-viewer z-index overrides
- `neural-lace/workstreams-ui/config/projects.js` — coordination alias + root-md listDocs fallback
- `neural-lace/workstreams-ui/web/responsive.selftest.js` — R28 invariant lock
- `docs/plans/ws-ui-modal-doc-links-2026-06-11.md` — this plan
- `docs/plans/ws-ui-modal-doc-links-2026-06-11-evidence/` — structured evidence artifacts (*.evidence.json)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The coordination repo lives at `~/claude-projects/workstreams-coordination` by documented convention
  (verified on this machine; the alias is conditional on existence, so machines without it see no key).
- The Docs-viewer subsystem (docsBrowser IIFE: openDocModal + /api/doc + mdRender) is present in the build
  (it is; when absent the bridge stays null and links degrade to an explanatory toast, no crash).
- resolveDoc's existing traversal guard (rejects absolute paths, `..` segments, escapes of the project
  root) applies unchanged to the new coordination root — no new path-security surface is introduced.
- details text is operator/agent-authored (trusted), but the renderer never uses innerHTML for it, so a
  hostile string still has no injection path.
- The serving instance on :7733 runs the same code from the `workstreams-ui-server` worktree and picks up
  the change via its established take-master pattern + ui_build_ms auto-reload.

## Edge Cases
- A `*.md` token embedded in a URL (e.g. `https://github.com/x/y/blob/main/foo.md`) — preceded by `/`,
  so the mid-URL guard keeps it plain text (no false link).
- Trailing sentence punctuation after a `docs/…` reference — trimmed from the chip text so the probe path
  is clean.
- A referenced doc that exists in none of the candidate projects — every probe misses → error toast naming
  the reference; modal stays open; nothing navigates away.
- The docs drawer absent from a build (docsBtn missing) — openDocInApp stays null; clicking shows
  "Docs viewer unavailable in this build." instead of throwing.
- Esc with both the doc viewer and the detail modal open — the detail-modal handler returns early while
  the viewer is open (viewer closes first; second Esc closes the modal).
- A project key in the map whose root lacks `docs/` AND has no root-level `*.md` — listDocs returns an
  empty file list exactly as before (fallback walk finds nothing).
- `item.details` referencing a doc by `workstreams-coordination/<name>.md` explicit prefix — the prefix
  candidate resolves first (project = workstreams-coordination, path = remainder).

## Acceptance Scenarios
- Scenario 1 (bare coordination-repo doc name): Open the Workstreams GUI against the live state. Click the
  "Redesign Q1 — Backlog/idea-capture dimension" item (Awaiting-me filter). Success: the modal's Background
  row renders `REDESIGN-PRD-DRAFT-2026-06-10.md` as a clickable link; clicking it opens the document viewer
  IN-APP, titled "workstreams-coordination › REDESIGN-PRD-DRAFT-2026-06-10.md", with the full PRD content
  rendered; the detail modal remains open underneath.
- Scenario 2 (repo-relative docs/ path): In the same modal, click the `docs/backlog.md` link. Success: the
  viewer displays the neural-lace backlog in-app.
- Scenario 3 (dismissal layering): With the viewer open above the modal, press Esc. Success: the viewer
  closes, the detail modal is still open; a second Esc closes the detail modal.
- Scenario 4 (no console errors): The whole flow produces zero browser console errors or warnings.

## Out-of-scope scenarios
- Open-in-OS-editor button behavior — pre-existing viewer affordance, unchanged by this plan.
- Docs-drawer browsing UX (folder tree, filter) — unchanged except coordination docs now listed.
- Branch-reference jumps ("see branch: …") — still degrade to a toast (no tree-canvas navigation exists).

## Testing Strategy
- Task 1: `node --check config/projects.js`; node one-liner asserting loadProjects() has the coordination
  key, resolveDoc serves the PRD, rejects `../` + absolute paths, and listDocs lists the root *.md set.
- Task 2: `node --check web/app.js`; live headless-browser exercise of the click-to-open flow (Scenarios 1-3).
- Task 3: `node web/responsive.selftest.js` (28/28 incl. R28) + `node state/selftest.js` (20/20 untouched) +
  headless run against a live server with console-log capture (Scenario 4).

## Walking Skeleton
The thinnest slice: the openDocInApp bridge + one clickable chip for the existing `docs/…` matcher, clicking
through to openDocModal. The bare-`*.md` matcher, candidate probing, coordination alias, layering fix, and
R28 lock layer on top of that proven slice.

## Decisions Log
- Decision: resolve doc references by PROBING /api/doc candidates client-side rather than encoding a
  project-resolution map. Tier 1; alternatives: a server-side "search all projects for this filename"
  endpoint (rejected — new API surface for what 2-4 cheap localhost GETs already answer); embedding
  project keys in details text (rejected — requires retro-editing every existing item).
- Decision: bare filenames probe `workstreams-coordination` FIRST (that is where bare-named docs live by
  convention); pathed refs probe the item's project first. Tier 1; observed from the live data shape.
- Decision: doc-viewer z-index raised via ID overrides (#docScrim 61 / #docModal 62) instead of restructuring
  the shared .modal-card class. Tier 1; smallest change that makes the viewer layer above the detail modal.

## Definition of Done
- [x] All tasks checked off (task-verified with structured evidence)
- [x] Both selftests pass (responsive 28/28, state 20/20)
- [x] Live headless verification of Scenarios 1-4 captured
- [x] Completion report appended to this plan file

## Completion Report

### 1. Implementation Summary
All three tasks built and verified in one session (structured evidence: `ws-ui-modal-doc-links-2026-06-11-evidence/{1,2,3}.evidence.json`, all PASS, commit cdd42cf):
- Task 1 — config/projects.js: `workstreams-coordination` alias (existence-conditional, runtime-computed) + root-`*.md` listDocs fallback. resolveDoc serves the coordination PRD; `../` and absolute paths still rejected; 21 root docs listed.
- Task 2 — web/app.js + app.css: linkifyDocs emits clickable button chips (docs/… paths + bare/pathed `*.md`; URL-embedded tokens stay plain; textContent-only DOM); openDocSmart candidate probing (explicit prefix > item project > neural-lace > coordination; bare names coordination-first); openDocInApp bridge; references/links gates widened; #docScrim 61 / #docModal+#docsPanel 62 layering; Esc closes viewer first.
- Task 3 — responsive.selftest.js R28 invariant lock; responsive 28/28, state 20/20; headless live flow verified (Scenarios 1-4 PASS, artifact in `.claude/state/acceptance/ws-ui-modal-doc-links-2026-06-11/`).

### 2. Design Decisions & Plan Deviations
Per Decisions Log: client-side candidate probing over a server search endpoint; coordination-first for bare names; ID-level z-index overrides. No deviations from plan.

### 3. Known Issues & Gotchas
- openDocSmart probes up to ~5 localhost GETs per click on a miss-heavy reference; negligible at this scale.
- Bare-`*.md` matcher can linkify a token that exists nowhere (probe fails → error toast names the reference; no navigation). Accepted: a dead link with a clear error beats an inert chip.
- The doc viewed in-app re-fetches once on open (probe + openDocModal both GET /api/doc); harmless on localhost.

### 4. Manual Steps Required
Update the serving worktree (`~/claude-projects/workstreams-ui-server`, take-master pattern) and restart the :7733 server; the ui_build_ms health field auto-reloads open tabs. (Performed by the shipping session.)

### 5. Testing Performed & Recommended
Performed: node --check on all edited JS; responsive selftest 28/28 (incl. new R28); state selftest 20/20 (untouched); server-side resolution + traversal-guard node checks; live headless-browser click-through of all four acceptance scenarios with console-log capture (zero errors). Recommended: none beyond the standing selftests.

### 6. Cost Estimates
None — localhost-only feature, no new dependencies, no services.
