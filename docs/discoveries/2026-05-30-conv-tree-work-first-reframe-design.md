---
title: Workstreams — work-first reframe of the Conv Tree (Misha-greenlit, scope expanded; awaiting Q1 + Q2)
date: 2026-05-30
type: architectural-learning
status: decided
auto_applied: false
originating_context: Misha's 2026-05-30 reframe ask — flip the Conv Tree's primary structure from "conversation flow + Misha-pending leaves" to "work items with conversations as provenance," diagnosed against the recurring leak where sessions do real work that never surfaces as a pending item and never closes back to Misha. v1 design proposal authored 2026-05-30; Misha reviewed and confirmed direction + revised scope; v2 design proposal authored same day.
decision_needed: |
  Direction greenlit by Misha. Two micro-decisions still open before Phase 1+2 build starts:
  Q1 — Confirm "Workstream" as the tier name OR rename to "Initiative" (my mild preference: Initiative, eliminates product/tier naming clash). 10-second decision; affects every file rename.
  Q2 — Default render expansion: focus-only on current project (my counter-proposal — ~400-row first render otherwise) OR full-expand-all (Misha's literal ask). 30-second decision; affects Phase 2 UI.
  Phase-5 architecture (Q5a–Q5c, cost ceilings) and Phase-6 architecture (Q6a–Q6c) are deferred to the Phase 4 PAUSE checkpoint per the v2 sequence; not blockers for Phase 1+2 start.
predicted_downstream:
  - neural-lace/conversation-tree-ui/ → neural-lace/workstreams-ui/ (directory rename via `git mv`)
  - neural-lace/workstreams-ui/state/schema.js (Phase 1: three additive events: item-committed / item-shipped / item-blocked; one optional field: tier; polymorphic parent_id)
  - neural-lace/workstreams-ui/web/app.js (Phase 2: four-tier renderer + filter-driven side panel + detail card)
  - adapters/claude-code/hooks/conversation-tree-*.sh → adapters/claude-code/hooks/workstreams-*.sh (Phase 2 rename; symlink compat for 30 days)
  - adapters/claude-code/rules/conversation-tree-state.md → adapters/claude-code/rules/workstreams-state.md
  - adapters/claude-code/hooks/workstreams-orphan-blocker.sh (NEW Phase 4 — SessionStart hard-block gate)
  - scripts/agent-view-reconciler.js (NEW Phase 3 — polls `claude agents --json` every 60s, emits state-transition events)
  - scripts/lifecycle-backfill.js (NEW Phase 3 — assigns lifecycle states to existing 62 items by inference)
  - neural-lace/workstreams-ui/server.js (Phase 5 — gains reconciler role, fs.watch on event queue, Agent SDK spawn loop)
  - ~/.claude/state/workstreams-queue/ (NEW Phase 5 — event queue dir for Stop hooks → reconciler)
  - mishanovini/workstreams-state (NEW Phase 6 — dedicated private repo under Misha's personal GitHub account, local checkout at C:\Users\misha\dev\Personal\workstreams-state\; gh CLI auto-switches account in that dir; separates personal productivity infrastructure from PT business assets)
  - .github/workflows/workstreams-state-sync.yml (Phase 6.3 — Action that parses cloud-Routine commits for state events)
  - docs/plans/conv-tree-pending-items-reframe.md (currently ACTIVE — to be folded into Phase 1+2 with Status: SUPERSEDED + Decisions Log pointer)
  - docs/decisions/NNN-workstreams-reframe.md (Tier-2 ADR authoring tracked alongside Phase 1+2)
  - docs/decisions/031-conversation-tree-ui-architecture.md (revision r9 noting the rename + work-first reframe; substance preserved, work entity becomes first-class alongside conversations)
  - agent/memory/project_conv_tree_purpose.md → agent/memory/project_workstreams_purpose.md (content revised for work-first framing)
---

## What was discovered

The current Conv Tree's `isWaiting()` predicate is a deliberate narrow filter that hides everything that doesn't need Misha's immediate attention. This is by design (per `project_conv_tree_purpose.md`). But it creates a structural blind spot: **a Dispatch session that does real work and produces nothing user-facing leaves no trace in the tree**. Combined with the fact that the orchestrator-side `agent/memory/project_open_commitments_tracker.md` is hand-curated (42 items, manually reconciled against `git log` and `gh pr list`), the result is a long-running leak — work in flight is invisible to both Misha and the tracker unless I happened to write it down.

The proposed reframe (now confirmed) makes **work** the primary entity and **conversations + sessions** provenance. Six lifecycle states (proposed → committed → in-flight → blocked → shipped → closed) with `orphaned` as a derived state (no progress event for N hours). The storage substrate (ADR-032 event-sourced log) already supports this — only three additive event types + one optional field + a polymorphic `parent_id` reinterpretation are needed; `schema_version` stays at 1.

**Scope expanded after Misha's v1 review (2026-05-30):**

- Rename Conv Tree → Workstreams (entire subsystem)
- Four-tier hierarchy: Project → Workstream → WorkItem → Sub-task (each level meaningful; default render focus-expanded per my counter-proposal)
- Substance threshold: inclusive — any work surviving a single tool call (typo fixes are auto-transition items, never surfaced as "Awaiting me")
- Enforcement: hard SessionStart block (not click-through) with established waiver pattern (≥1 substantive line, <1h TTL) as the gate-respect-compatible escape hatch
- Two new phases added:
  - **Phase 5 — autonomous cascading orchestrator**: every Stop hook emits to an event queue; the existing GUI server gains a reconciler role (fs.watch on queue), uses Agent SDK to spawn next work; cascade-brake via per-workstream concurrency cap + rate limit + daily cost ceiling
  - **Phase 6 — cross-machine sync**: dedicated private repo `mishanovini/workstreams-state` (under Misha's personal GitHub account; local checkout at `C:\Users\misha\dev\Personal\workstreams-state\`; gh CLI auto-switches account in that dir per `CLAUDE.md` convention); append-only event log makes merges trivial; claim-and-lease prevents double-spawn across Misha's two machines; cloud-Routine bridge via GitHub Action

## Why it matters

The leak compounds. Today's open-commitments-tracker has 42 line items; many of them are things I committed to and never closed (per `feedback_follow_through.md`). Each new session adds the risk of another orphan. Without structural closure, the tracker has to grow forever or items silently age out. The work-first reframe gives the system a way to *see* its own incomplete work, instead of relying on me to remember to write it down.

Phase 5 multiplies the value: Misha's "keep moving on its own, only pause when something needs me" goal is exactly Rule 1 (drive to completion) operationalized as architecture — the system itself drives, surfaces to Misha only what Rule 3 says needs Misha. Phase 6 multiplies again by removing the single-machine bottleneck.

Cost of inaction: continued reliance on manual reconciliation; continued accumulation of started-and-dropped work; continued user-facing surprise when Misha asks "what happened with X" and I have to dig.

## Options

(These are the v1 options for the audit trail. v2 supersedes them with Misha's chosen path.)

A. **Full reframe (4 phases, ~11h).** Work as primary; lifecycle state machine; orphan detection. Closes the leak structurally.
B. **Parallel work-in-flight registry alongside the existing tree.** Avoids audience-expansion risk on the Conv Tree but introduces two-surface drift.
C. **Status quo + better discipline.** Doesn't fix the leak; relies on the same failing manual discipline.
D. **Phased reframe (Phases 0+1 first, re-evaluate).** v1 recommendation.
E. **Full six-phase build per v2 directives** (Misha's chosen path post-v1-review): adopt Workstreams rename + four-tier hierarchy + hard-block enforcement + inclusive substance threshold + autonomous reconciler + cross-machine sync. Six phases, ~33-42h, three checkpoints (Phase 4 PAUSE, Phase 5 PAUSE, Phase 6 DONE).

## Recommendation

v1 recommendation was Option D (Phase 0+1 only). v2 / final recommendation is **Option E** — Misha explicitly chose to expand scope, and the expanded scope's pieces are coherent. v2 design doc lays out the full 6-phase architecture with deep-dives on Phase 5 (cascading orchestrator) and Phase 6 (cross-machine sync).

## Decision

**DECIDED by Misha 2026-05-30.** Direction greenlit; six-phase build authorized; bundle Phase 1+2 as minimum coherent ship; notify-and-continue at Phase 2→3 and 3→4; PAUSE at Phase 4 (hard-block teeth biting), PAUSE at Phase 5 (autonomous spawning). Two micro-decisions (Q1 — tier name; Q2 — expansion default) still open and would benefit from Misha's answer before Phase 1+2 starts; both are 30-second decisions that lock cheaply now and would be expensive to relitigate after Phase 2 ships.

Status: `decided` rather than `implemented` because no build work has begun yet. Auto-applied: false (Misha's explicit greenlight, not unilateral application).

## Implementation log

**2026-05-30 — v1 design exploration authored.** Path: repo-root `conv-tree-redesign-work-first-2026-05-30.md` (gitignored). 5185 words. Recommended Option D (Phase 0+1 only).

**2026-05-30 — v1 reviewed by Misha; direction greenlit + scope expanded.** Six directives:
1. Rename Conv Tree → Workstreams
2. Tiered hierarchy not flat (Project → Workstream → WorkItem → Sub-task)
3. Phase 1+2 bundled
4. Phase 2→3 notify-and-continue (no pause)
5. Enforcement = hard SessionStart block (not click-through)
6. Substance threshold = inclusive (any work surviving a tool call)
Plus three new-scope items:
7. Agent View integration into Phase 3
8. Phase 5 — autonomous cascading orchestrator
9. Phase 6 — cross-machine sync via dedicated private repo

**2026-05-30 — v2 design proposal authored.** Path: repo-root `workstreams-design-v2-2026-05-30.md` (gitignored, matches the `*-design-*-YYYY-MM-DD.md` gitignore pattern). 5283 words. Includes:
- Entity model with four-tier hierarchy + polymorphic parent_id rationale
- UI sketch with focused-project expansion (counter-proposal to full-expansion-everywhere)
- Hard-block enforcement design + waiver pattern compatible with gate-respect.md
- Inclusive substance threshold + auto-transition mechanics
- All 6 phases with definitions of done and protocols (notify-and-continue vs PAUSE)
- Phase 5 deep-dive: reconciler-on-existing-GUI-server architecture, Agent SDK spawn approach (Option 1b from ADR-031 adopted for autonomous loop), cascade brakes (concurrency cap + rate limit + daily $ ceiling)
- Phase 6 deep-dive: `mishanovini/workstreams-state` repo (personal account; local at `C:\Users\misha\dev\Personal\workstreams-state\`), append-only event log merge semantics, claim-and-lease primitive, GitHub Action approach for cloud-Routine bridge
- 8 open questions (Q1+Q2 are pre-Phase-1 blockers; Q5a–Q5c, Q6a–Q6c are Phase-4-PAUSE decisions)
- Recommended sequence: Phase 1+2 next, after Misha answers Q1+Q2

**2026-05-30 — Q1 + Q2 answered by Misha; plan authored.** Q1: tier name stays `Workstream` (product/tier clash accepted). Q2: default render = non-complete states only (in-flight + blocked + proposed/committed shown; shipped/closed hidden by default, available as toggles). Plan landed at `docs/plans/workstreams-phase-1-2.md` — Status: ACTIVE, frozen: true, tier: 2, rung: 2, architecture: coding-harness, 7 tasks (3 mechanical + 3 full-verification renderer tasks + 1 supersede), plan-reviewer green (zero findings). A separate build session is spawning to execute.

**Next concrete actions (now in build session's hands):**
- Mark the existing `docs/plans/conv-tree-pending-items-reframe.md` SUPERSEDED with a Decisions Log entry pointing at the new plan
- Author ADR `docs/decisions/NNN-workstreams-reframe.md` (Tier-2 record of the rename + work-first reframe; references ADR-031 and ADR-032 noting the additive nature)
- Revise ADR-031 to r9 with a one-paragraph addendum noting the rename + work-entity-first interpretation; substance preserved
- Begin Phase 1+2 build per the standard orchestrator pattern
