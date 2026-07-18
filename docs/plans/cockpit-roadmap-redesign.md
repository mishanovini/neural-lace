# Plan: Cockpit roadmap redesign — one registry, three views

Status: DRAFT
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none
Architecture-review: PENDING (Check 17 gates the ACTIVE flip — dispatch architecture-reviewer
[model: fable] + ux-designer on this draft before activation)

## Goal

Rebuild the cockpit's surface around the operator's actual mental model, per the five-round
sit-down (`docs/reviews/2026-07-17-cockpit-ux-design-input.md` — ALL verbatim requirements live
there; this plan is its synthesis) + the Fable proposal
(`docs/reviews/2026-07-17-cockpit-ux-redesign-proposal.md`: live-verified defects — 718 identical
drift chips, the 18/18-done ask rendering ACTIVE, prompt-fragment titles).

## User-facing Outcome

ONE registry, THREE views:
1. **Requests** — the conversation/intent ledger: every ask with an auto-distilled ALWAYS-EDITABLE
   title, verbatim origin one click away, and an EVOLUTION TIMELINE (original → amendments from
   continued conversation → decisions made → "became → <plan>" on promote, which closes it here).
2. **Roadmap** — a priority-ordered hierarchical tree (intents → plans → tasks) with a STATUS ON
   EVERY ITEM (no waterline): not-started / in-progress (progress bar from child counts) /
   complete / STALLED(reason + what-unblocks). Expandable to the actually-tracked granularity.
   Discovered work shows an "added mid-build" marker. Completed items: in place 7 days; a fully
   complete subtree collapses to its headline immediately; after 7 days → per-parent "N completed ▸".
   Kanban toggle + project filter chips (same derived states; chips per operator nod).
   HARNESS CHORES EXCLUDED from this view entirely (operator B).
3. **Inbox** — everything waiting on the operator (decisions from conversations + unblock-actions
   from stalled builds — one fact, two views). **CONTEXT CONTRACT (operator mandate): every item
   carries source-provenance, the issue, trade-offs (for decisions), and what's-needed — a
   context-less item CANNOT render as answerable: it quarantines as "needs context" and auto-files
   a defect against the producing session.**

## Scope

IN: derived status foundation; work-item layer (titles/evolution/merge-split); the three views;
badge law at the renderer; badge-storm auditor fix; event-triggered coord publish + person
grouping; the four absorbed UI-polish items; needs-you cold-reader lint warn→block.
OUT: Circuit P1 (own plan; the propose/partial-accept surface ships there, landing on THIS
surface's Requests/Roadmap); the chat sign-off Stop-gate (harness plan, nl-issue filed).
ABSORBS: `docs/plans/cockpit-ui-polish.md` (flip it SUPERSEDED on this plan's activation).

## Tasks

- [ ] 1. [serial] **Derived top-level status foundation.** Per-item status computed, never
  declared: complete = MERGED + DEPLOYED + FULLY FUNCTIONAL IN PRODUCTION (operator A — per-item
  oracle: merge SHA + deploy evidence + acceptance artifact where one exists; manual "done" is an
  override, labeled); in-progress = live session activity; stalled = started + no live session,
  with DERIVED reason+unblock: waiting-on-you(→Inbox link) / limit-parked(resume time) /
  blocked-on(predecessor) / crashed(salvage). Fixes the done-renders-ACTIVE defect —
  Verification: full
- [ ] 2. [serial] **Work-item layer.** Auto-distilled titles (LLM summarize intent; ALWAYS
  operator-editable, no confirm ceremony — round 3); request EVOLUTION timeline (amendment events
  on the ask record; capture splice for scope-modifying conversation turns); merge/split of asks
  into items — Verification: full
- [ ] 3. [serial] **Roadmap tree view** per Outcome §2 (statuses every item, progress bars,
  granularity expansion, insertion markers, completed aging: in-place 7d / subtree-headline /
  N-completed roll-up; kanban toggle; project chips; harness-chore exclusion filter) —
  Verification: full
- [ ] 4. [serial] **Inbox view + context contract enforcement**: the quarantine + auto-defect
  path; needs-you.sh cold-reader lint promoted warn→BLOCK on add (golden scenario: the
  2026-07-18 bare-token sign-off incident, memory feedback_needs_from_you_full_context) —
  Verification: full
- [ ] 5. [serial] **Requests ledger view** (timeline render, became→ links, close-on-promote) —
  Verification: full
- [ ] 6. [serial] **Badge law + badge-storm fix**: renderer caps telemetry to ONE counted, labeled
  chip per belief-changing class (bookkeeping classes → Harness Health only); auditor's
  unmatched_dispatch oracle age-bounded to the marker-retention horizon (nl-issue spec) —
  Verification: full
- [ ] 7. [serial] **Event-triggered publish + person grouping** (round 5): status-changing
  emissions touch a local dirty-marker (never-blocks); NL-CoordSync becomes the debounced
  publisher (≤~1/min when dirty, idle when clean) + keeps the periodic keepalive floor (git-blind
  coverage + peer-unreachable honesty); hostname→person map so peers group by PERSON (Misha's
  machines vs Jaime's); coord-repo access for the second account documented — Verification: full
- [ ] 8. [serial] **UI polish absorbed** (resizable/independently-scrollable panes without
  regressing the todo-clip fix; compact expandable backlog rows; task descriptions rendered +
  per-row plan links deduped; Artifacts section removed) — Verification: full
- [ ] 9. [serial] **Acceptance**: end-user-advocate runtime pass over the three views + the
  operator's own cold-start walkthrough ON THE NEW SURFACE (replaces the retired ask-p1
  walkthrough) — Verification: full

## Files to Modify/Create
`neural-lace/workstreams-ui/web/*` (all three views), `server/server.js` + `derive-lib.js`
(status derivation, work-item layer), `server/auditor.js` (badge age-bound),
`server/payload-schema.js`, `adapters/claude-code/scripts/needs-you.sh` (lint→block),
`adapters/claude-code/scripts/coord-sync.sh` + emission splices (dirty-marker), a
`config/people.js`-style hostname→person map (machine-local overrides).

## In-flight scope updates
(none yet)

## Assumptions
- The ask registry IS the work-item registry plus fields (title, timeline) — no new store (Fable
  proposal §7); status derivation reads existing data (plan-parse, heartbeats, merge SHAs,
  acceptance artifacts).
- Deploy evidence for the complete-oracle: per-project convention (deploy-preflight artifacts /
  acceptance artifacts); where none exists, merged+labeled "no deploy signal" — never silently
  complete.
- The distill step runs off the hot path (capture writes verbatim; distillation is async).

## Edge Cases
- Status-change arriving via git ops (no hook): periodic floor covers it (round 5).
- Multi-part prompts → split; mid-conversation asks → amendment vs new-item heuristic + operator
  merge/split as the correction path.
- Context-quarantined Inbox items must not silently vanish: they show AS quarantined with the
  producing session named.
- An in-progress item with zero tracked children: progress bar omitted (no fake granularity).

## Acceptance Scenarios
1. The archived 18/18 rebuild renders COMPLETE (or honestly "merged, no deploy signal") — never
   ACTIVE.
2. A context-less needs-you add is REFUSED (lint blocks); a legacy context-less item renders
   quarantined + auto-defect filed.
3. Badge wall impossible: inject 700 bookkeeping badges → roadmap shows at most one counted chip
   per belief-changing class.
4. Flip a task on machine A → peer view on B updates within ~2 min (event path), and an idle-but-
   alive machine still distinguishes from a dead one (keepalive floor).
5. Operator walkthrough on the new surface: the four questions answerable cold in <60s.

## Out-of-scope scenarios
Circuit's propose/partial-accept meeting-items surface (Circuit P1 ships it; this plan's Requests
view is where approved items land). The chat sign-off Stop-gate (separate harness work).

## Closure Contract
All 9 tasks two-gate verified (rung 3); advocate pass green; operator walkthrough done on the new
surface; deployed to :7733 (+ peer machines); cockpit-ui-polish flipped SUPERSEDED.

## Testing Strategy
Extend cockpit.selftest.js (structural: statuses, quarantine, badge cap, aging states) +
server.selftest.js (derivation oracles incl. the complete-oracle fixtures) + peer-view suite
(event-path timing) + advocate runtime as the user-path oracle.

## Walking Skeleton
Task 1 first, alone: the derived status of ONE real archived plan rendering correctly end-to-end
(fixes the loudest live defect before any view work).

## Decisions Log
- (2026-07-18) Synthesis decisions from the sit-down, all operator-confirmed: one-registry-three-
  views; per-item statuses (no waterline); production-functional complete; in-place-7d/subtree/
  roll-up completed aging (operator asked for recommendation; this is it — one-number tunable);
  chips-not-swimlanes (nodded); auto-name-always-editable; harness chores excluded; event-hybrid
  publish with keepalive floor; person grouping. Inputs doc is authoritative for verbatim intent.
