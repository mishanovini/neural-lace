# ADR 045 — Conversation Tree → Workstreams (work-first reframe)

- **Date:** 2026-06-01
- **Status:** Accepted — Phase 1+2 shipped (this ADR records the rename + the work-first interpretation; Phases 3-6 land in subsequent plans per the v2 design)
- **Stakeholders:** Misha (sole operator + user of the work tracker)
- **Supersedes / relates to:** does NOT supersede ADR-031 (conversation-tree UI architecture, Option-2 passive tracker) or ADR-032 (state schema) — both remain the load-bearing contracts; this ADR is a **revision/addendum** to their framing (the substrate is unchanged, the product name + the entity interpretation change). Relates to the design proposal `workstreams-design-v2-2026-05-30.md` (gitignored at repo root) and the build plan `docs/plans/workstreams-phase-1-2.md`. Absorbs/supersedes the `conv-tree-pending-items-reframe` plan.

## Context

The "Conversation Tree" (ADR-031/032) was built as a passive tracker of Dispatch conversations — branches (sessions) with decisions/questions/actions hanging off them. In practice the load-bearing thing Misha needs tracked is not the *conversation* but the *work*: open WorkItems across his projects, what is awaiting him, what is in flight, what stalled. Sessions are provenance for that work, not the primary entity. The old renderer foregrounded sessions (a stacked Waiting/Backlog/Decisions/Questions accordion keyed off conversation branches); the leak it left open is that in-flight work which is not strictly `blocked-on-user` fell out of view, so commitments silently aged out (the open-commitments-tracker leak class A6/A8-A14/…).

Misha's 2026-05-30 directive: rename the subsystem to **Workstreams** and rebuild it work-first — an explicit Project → Workstream → WorkItem → Sub-task hierarchy, sessions demoted to provenance, default view widened from "blocked-on-user" to all non-complete work, and (later phases) a hard-block orphan gate + autonomous cascading orchestrator + cross-machine sync.

## Decision

1. **Rename** the subsystem from "Conversation Tree" to **Workstreams** (product, plural) with a **Workstream** tier (singular, the second tier). The directory `neural-lace/conversation-tree-ui/` → `neural-lace/workstreams-ui/`; the hooks' internal state-lib path references follow; the rule file + memory file + docs follow. (Hook *filenames* `conversation-tree-*.sh` rename to `workstreams-*.sh` in a deferred Task-2b follow-up to avoid a high-blast-radius `settings.json` rewrite at the end of a build session; the directory + path references renamed in Phase 1+2.)
2. **Work-first entity interpretation over the SAME ADR-032 schema** — additive only. Three new event types (`item-committed`, `item-shipped`, `item-blocked`) set a WorkItem's derived lifecycle `state`; two optional fields (`tier`, `serves_item_id`) ride on `branch-opened`. `parent_id` is semantically broadened to range over Project/Workstream/WorkItem ids (it was already a string). `schema_version` stays at 1 (forward-tolerant, per ADR-032 §1). The ADR-032 §8 attestation contract and `verifySnapshotAttested` are untouched.
3. **Renderer reframe** — four-tier hierarchy with focus-project default expansion; sessions (`sess-*`/`sub-*`) hidden from the tree and surfaced only as detail-card provenance; a filter-driven single side panel (Awaiting me / In flight / Blocked / Recently shipped / Orphaned / Backlog / All) replacing the stacked accordion; a detail card on selection; an adjustable divider. Default view = non-complete states only (`{proposed, committed, in-flight, blocked}`), `{shipped, closed}` hidden until toggled. Orphans (Phase 2) = open/un-concluded sessions; item-level no-progress detection needs the event log and lands with the Phase-3 reconciler.

## Alternatives Considered

- **Keep "Conversation Tree", just widen the default filter.** Rejected: the conversation-first framing is the root of the leak; renaming + re-rooting on work is the preemptive fix (Rule 6) rather than treating the symptom.
- **Rename the tier to "Initiative" to avoid the product/tier "Workstreams"/"Workstream" recursion.** Rejected: Misha confirmed "Workstream" (2026-05-30 Q1) — "open Workstreams → see your Workstreams" parses cleanly (mirrors Trello "Boards → boards").
- **Discrete Project/Workstream/WorkItem/Sub-task classes** instead of one polymorphic WorkItem + derived tier. Rejected: discrete classes force premature tier commitment at creation and block mid-flight re-parenting (design §2).
- **Full-expand every project by default** (Misha's literal v1 ask). Counter-proposed focus-project expansion (only the most-recently-touched project expanded; ~400 rows at full expansion is unscannable) — Misha accepted the counter-proposal.

## Consequences

- **Enables:** a work-first dashboard where every commitment Misha makes is tracked and the default view shows what needs attention or is moving; the Phase-4 hard-block orphan gate, Phase-5 autonomous reconciler, and Phase-6 cross-machine sync build on this substrate.
- **Costs:** the old renderer's peripheral features (docs browser, dispatch composer, defer/priority popovers, reorder, zoom) were not carried into the v2 reframe — they are flagged for re-addition as polish. The hook *filename* rename (Task 2b) is deferred. Item-level orphan detection awaits the Phase-3 event-log reconciler.
- **Backward-compat:** additive schema means existing state files (62 items) replay unchanged; existing `branch-opened` events without `tier`/`serves_item_id` parse identically. The directory rename moved the gitignored live `tree-state.json` with it (no data loss). During the Task-2b window the hook filenames remain `conversation-tree-*.sh`.

## Refutation Criterion

The work-first reframe's premise — "foregrounding work (not conversations) closes the silent-aging leak" — would be REFUTED if, after Phase 4's hard-block orphan gate ships, commitments still age out silently (i.e., orphans accumulate un-dispositioned despite the gate). That is the Phase-4 acceptance check, not a Phase-1+2 one; Phase 1+2 only claim the renderer surfaces non-complete work by default, which is verified (the default filter is "Awaiting me", showing all 55 open items).
