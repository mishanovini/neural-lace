# Plan: Workstreams Consolidation — single source of truth + harvest stranded work + redesign
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: HARNESS-GAP-39 (parallel-session UI collision)
acceptance-exempt: false
acceptance-exempt-reason: (removed 2026-06-09 — this plan ships a user-facing UI; exempting it switched off the end-user-advocate runtime gate and let a broken modal ship as "verified". User-facing plans may not be exempt per acceptance-scenarios.md; the rebuild must pass runtime acceptance.)
tier: 3
rung: 2
architecture: orchestration
frozen: false
prd-ref: n/a — harness-development

## Goal
Stop the scattering. Today the Workstreams state lives in 9 different `tree-state.json` files, the UI exists as two forked dirs (`conversation-tree-ui` husk + live `workstreams-ui`), and the layout/content fixes Misha reported are stranded across ~6 unmerged `pt/` branches. Consolidate to ONE state file, ONE UI, full-content items, captured in the workstreams-coordination GitHub repo — and harvest (don't lose) the stranded redesign work.

## User-facing Outcome
Misha opens the Workstreams UI and sees: every effort in motion across every project, tracked through to DEPLOYED (so anything that started-but-didn't-deploy is visible); each item self-contained with enough background to act on even after forgetting the context; a modal (not a panel-eating) detail view; and context-appropriate buttons (approve / decline / submit decision; respond with details or a clarifying question).

## Approved design (Misha 2026-06-08)
1. **Single source of truth = `workstreams-coordination/state/tree-state.json`** (git-backed, cross-machine, in the Coordination repo). EVERY emit hook (all projects), the gates, and the UI server read/write ONLY that file. Retire per-project `.claude/state/conversation-tree/` and the `conversation-tree-ui` fork.
2. **Full-content items (write for a cold reader):** every item carries BACKGROUND (memory-trigger — "what is this, what were we doing") + the decision/question + options + recommendation + links (branch/PR). Assume Misha reads it after fully forgetting context. No "INCOMPLETE METADATA" stubs.
3. **Capture ALL work in motion, tracked to deployed:** not just decisions-on-Misha. In-flight build sessions, open PRs, orchestrator tasks, migrations — each tracked merged→deployed, surfacing efforts that never deployed. "Awaiting me" becomes one filter.
4. **Modal detail overlay** (sits in front, dismissible) — NOT a right-panel that fills the screen.
5. **Context-appropriate action buttons:** approve / decline / submit a decision; respond with additional details or a clarifying question.

## DO-NOT-LOSE: stranded UI work to harvest (per Misha's "don't lose anything in progress")
Harvest these unmerged branches into the consolidated UI before retiring them:
- `pt/feat/conv-tree-ui-vertical-redesign-2026-05-23` [+6] — v2: narrow tree + tabbed side panel
- `pt/feat/conv-tree-accordion-panels-2026-05-27` [+10] — v3: accordion panels (detail redesign)
- `pt/fix/conv-tree-toast-stacking-2026-05-23` [+7]
- `pt/session/conv-tree-project-root-topology-...` [+4] — project-root topology + auto-extract
- `pt/feat/conv-tree-auto-emit-enforcement-2026-05-23` [+6] — Layer B reconciler
- `conv-tree-ui-v1.1.2-polish` [+1]; `fix/conv-tree-project-node-header-styling`
- `feat/deterministic-workstreams-turn-emit` [+9] — the per-turn emit (this session; merge it)

## Scope
- IN: state-path unification; emit/gate/UI code reconciliation to the single path; full-content item schema + emit; modal detail; all-work-in-motion model + deployed-tracking; context-buttons; harvest of the stranded branches; migrate the 9 files' open items (incl. the 40 orphaned) into the one file; commit the 21 uncommitted circuit audit docs + delete corrupted dupes.
- OUT: Circuit product features; the agent-upgrade review (separate session).

## Tasks
- [x] 1. Decide + implement the single state path (`workstreams-coordination/state/tree-state.json`); point emit + gates + UI server at it; one-time migrate all 9 files' open items in.
- [x] 2. Harvest the stranded `pt/` redesign branches (v2 vertical, v3 accordion, toast, topology) into the live `workstreams-ui`; retire `conversation-tree-ui` husk.
- [x] 3. Full-content item schema + emit (background + options + recommendation + links); fix turn-emit fragment-capture.
- [x] 4. Modal detail overlay; context-appropriate buttons (approve/decline/submit/respond).
- [x] 5. All-work-in-motion model: track build sessions + PRs + migrations through merged→deployed; surface un-deployed efforts.
- [x] 6. Merge `feat/deterministic-workstreams-turn-emit`; commit circuit audits + delete corrupted-filename dupes.

## Files to Modify/Create
- `neural-lace/workstreams-ui/**` (the live UI — harvest + modal + content + all-work model)
- `adapters/claude-code/hooks/conversation-tree-emit.sh`, `workstreams-turn-emit.sh`, `decision-context-gate.sh` (single-path)
- `workstreams-coordination/state/tree-state.json` (the new single source of truth)

## In-flight scope updates
(none yet)

## Assumptions
- The `pt/` remote branches are reachable (git fetch --all confirmed). Harvest = cherry-pick/merge their UI commits onto the live workstreams-ui.
- A git-backed state file in the coordination repo is acceptable as the live store the UI server reads (cross-machine via pull/push).

## Edge Cases
- Two machines writing the coordination-repo state file concurrently → need an append-only-event + merge strategy (the state.js facade already uses events; git-merge the JSONL/events, not the snapshot).
- Migrating 9 files' items without duplicating already-concluded nodes → dedupe by node_id.

## Acceptance Scenarios

### modal-detail — clicking an awaiting-me item opens a self-contained modal
**Slug:** `modal-detail`
**User flow:**
1. Open the Workstreams UI (127.0.0.1:7733).
2. Click the "Awaiting me" filter, then click any listed item.
3. Observe the detail view that opens.
4. Press Escape (or click outside it).
**Success criteria (prose):** the detail opens as a MODAL OVERLAY in front of the tree (not a panel that fills the right side), shows a Background section that re-triggers memory for a reader who has fully forgotten the context, the concrete ask, options with a recommendation, and context-appropriate action buttons; Escape/click-outside dismisses it cleanly.
**Artifacts to capture:** screenshot of the open modal; console log (no errors); network log.

### no-garbage-items — fragments and fixtures are gone
**Slug:** `no-garbage-items`
**User flow:**
1. Open the Workstreams UI with the "All" filter.
2. Scan the visible nodes and items.
**Success criteria (prose):** no "Turn NNNN" nodes, no mid-sentence fragment titles (leading quotes/backslashes/parens), and no self-test fixture items ("X or Y", ACCEPTANCE/INTEGRATION TEST) are visible anywhere.
**Artifacts to capture:** screenshot of the expanded tree; console log.

### onboarding-items-enriched — the 4 contractor-demo items are actionable
**Slug:** `onboarding-items-enriched`
**User flow:**
1. Open the "Onboarding — contractor demo" node.
2. Open each of the four items (form-fix, role-default, stale-checklist, wizard-copy) in the modal.
**Success criteria (prose):** each shows a real Background explaining what the item is and where it came from, a concrete ask, and (where context could be sourced) options/recommendation — no bare-slug, zero-context items remain.
**Artifacts to capture:** screenshot of one enriched item modal; console log.

### real-work-in-motion — the tracker reflects actual git/plan state
**Slug:** `real-work-in-motion`
**User flow:**
1. Open the Workstreams UI "In flight" and "Shipped·not-deployed"/"Deployed" filters.
2. Compare what is listed against actual open work (ACTIVE plans, open PRs, unmerged branches).
**Success criteria (prose):** genuinely in-flight efforts appear with truthful lifecycle states; efforts that shipped without deploying are surfaced; nothing is shown as open that is actually concluded, and nothing real is missing.
**Artifacts to capture:** screenshot of each filter view; network log of the /api/state read.

## Out-of-scope scenarios
- [populate in build]

## Testing Strategy
- Self-tests on the hooks; a live round-trip (emit a full-content decision → appears as a modal-openable card with background+options+buttons in the GUI); confirm cross-machine via a coordination-repo pull on the second machine.

## Walking Skeleton
Thinnest slice: point ONE emit + the UI server at the single coordination-repo state file; emit ONE full-content decision card; open it as a modal in the UI with background + options + an approve button. Prove the whole chain before harvesting branches.
