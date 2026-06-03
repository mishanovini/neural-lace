# Plan: Workstreams tree — real visual nesting (kill the flat-list)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: GUI fix to a local Node-stdlib tracker with no auth/route product surface; verification is a browser screenshot + puppeteer-core geometry regression, not an acceptance-scenario browser flow.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
The Workstreams GUI tree (`http://127.0.0.1:7733/`) renders as a FLAT LIST, not
a hierarchy. Browser-verified root cause (2026-06-02): the data has `tier=(none)`
on all 63 nodes and zero Workstream/Sub-task nodes, so every one of the 35
project items renders at `.tree-item.d1` — `distinctItemX: [50]`, one indent
level, 11px past the project title. The prior fix (PT `3a8138b`) added per-tier
indent CSS but the tiers it styles never exist in the data. Fix: derive a real
intermediate tier from `kind` (Decisions / Questions / Actions) and render true
guide-rail nesting so each tier sits at a measurably distinct x.

## User-facing Outcome
Opening the GUI shows a tree that visibly nests: each project's items are grouped
under Decisions / Questions / Actions headers, items clearly indented inside a
guide rail under their group — not a flat dump. Measurable: project-row x <
group-header x < item x, each step distinct.

## Scope
- IN: `web/app.js` tree renderer (renderProject/renderWorkstream/treeItemRow +
  new renderKindGroups), `web/app.css` tree-nesting styles, `scripts/regression.e2e.js`
  new geometry-based tier-nesting test (+ puppeteer-core fallback).
- OUT: right-pane filter list, detail card, server, state schema, data backfill.

## Tasks
- [ ] 1. app.js: group direct project items by kind into a Project → Kind-group → WorkItem tier; nest via .tree-kids guide-rail containers. — Verification: full
- [ ] 2. app.css: add .tree-group / .tree-kids nesting styles with distinct per-tier indent + guide rails; retire the dead .d1/.d2/.d3 indent rules. — Verification: full
- [ ] 3. regression.e2e.js: strengthen bug#1 + add tier-geometry test asserting projHead<group<item distinct x; add puppeteer-core fallback so it runs with system Chrome. — Verification: full

## Files to Modify/Create
- `neural-lace/workstreams-ui/web/app.js` — kind-grouping + guide-rail nesting renderer
- `neural-lace/workstreams-ui/web/app.css` — .tree-group / .tree-kids styles
- `neural-lace/workstreams-ui/scripts/regression.e2e.js` — tier-geometry regression + puppeteer-core fallback

## In-flight scope updates
(none)

## Assumptions
- The live server reads `state/tree-state.json`; data shape verified this session.
- `kind` is a stable per-item field (values: decision/question/action).
- System Chrome at the default path is usable via puppeteer-core for headless verification.

## Edge Cases
- A project with zero visible items → "Nothing in flight" (unchanged).
- Unknown future `kind` values → grouped last, alphabetical.
- Real Workstream nodes arriving later → render as their own tier (path preserved).

## Acceptance Scenarios
- n/a (acceptance-exempt; verified by screenshot + puppeteer-core geometry regression).

## Out-of-scope scenarios
- n/a

## Testing Strategy
- puppeteer-core headless screenshot (before/after) + geometry assertions:
  group-header x strictly > project-row x; item x strictly > group-header x by ≥12px.
- Full `regression.e2e.js` suite green (all 8 prior bugs + new tier test).
- node state selftests unaffected (no state/schema change).

## Walking Skeleton
Render one kind-group with one nested item; assert item x > group x in browser.

## Decisions Log
### Decision: derive the intermediate tier from `kind`, not fabricate Workstream nodes
- Tier: 1
- Chosen: group WorkItems by kind under each project as the visible middle tier.
- Alternatives: (a) only strengthen Project→Item indent — still 2 visible levels, still reads flat; (b) synthesize fake Workstream nodes — dishonest, pollutes data.
- Reasoning: `kind` is real data; grouping faithfully adds depth NOW and composes with real Workstream nodes when backfill assigns them.

## Pre-Submission Audit
- S1: n/a — Mode: code GUI fix.
- S2: existing-code claims (renderProject/collectWorkstreams/treeItemRow) verified against app.js this session.
- S3: n/a
- S4: indent steps (proj-body 1.4rem, tree-kids 0.9rem margin + 0.9rem pad) consistent across CSS + asserted in test.
- S5: n/a

## Definition of Done
- [ ] Tree visually nests (screenshot proves it; ≥3 distinct tier x-positions)
- [ ] regression.e2e.js green incl. new tier-geometry test
- [ ] Shipped to PT master AND personal master (tree-hash verified)
