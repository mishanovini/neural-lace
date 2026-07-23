# Cockpit UX redesign — operator design input (2026-07-17, verbatim intent)

Captured from the operator reviewing the LIVE cockpit (:7733). This document is the requirements
brief for the UX deep-dive; it SUPERSEDES the assumption that the current ask-tree presentation is
the right frame, and may reshape docs/plans/cockpit-ui-polish.md.

## Verbatim needs
> "The thing I'm really looking for from this is the ability to keep track of the status of
> everything that is on the roadmap: that is upcoming; that is in the works; that is partially
> done; and that is complete. I want to have a frame of reference for the status of all of that
> work and how it maps back onto the specific requests that I've made."

> "I know I said previously that each node in the tree diagram should be defined by my original
> request, but the first sentence of my prompt appears to not be a good reference for what my
> actual ask was."

> "The multitude of drift tags is not helpful." (screenshot: hundreds of identical unlabeled
> 'drift' chips — see the badge-storm nl-issue; the auditor half is a mechanism bug, the
> presentation half is a UX failure regardless)

## What this implies (analysis, to be pressure-tested in the sit-down)
1. **The operator's mental model is ROADMAP-first, not session-first.** Their four buckets —
   upcoming / in the works / partially done / complete — are WORK-ITEM lifecycle states, not
   session states. The current landing is session/ask-rooted; they are asking for an
   outcome/roadmap-rooted frame with asks/sessions as supporting evidence UNDER items.
2. **The ask-node naming is broken as designed.** Auto-capture summarizes the first ~140 chars of
   the first prompt; real asks are (a) often mid-conversation, (b) multi-part, (c) better stated
   as INTENT than as quoted prompt text. Candidate fixes to explore: LLM-distilled intent titles
   (editable), naming-at-promote (Circuit D2 promote doubles as the naming moment), merging
   multiple prompts into one work item (the "Merge into..." affordance already exists).
3. **These four buckets map cleanly onto Circuit's pipeline** (PROPOSED=upcoming; promoted+
   building=in the works; partially built=partial; merged/deployed=complete) — the redesign
   should anticipate that convergence rather than invent a parallel taxonomy.
4. Badges/telemetry must earn their place: grouped, counted, labeled, capped — or demoted off the
   primary surface entirely (anti-noise law applies to OUR OWN telemetry too).

## Round 2 — operator sit-down input (2026-07-17, verbatim intent)

**The origin story (load-bearing):**
> "It's common for me to make a request that turns into a very long conversation and goes off on
> all kinds of tangents. This causes me to then lose track of not just my original request, but
> additional requests that I've made, decisions that I've made, and items that are still waiting
> on me. So I do want to be able to use this as a way of tracking the requests that I've made and
> maybe how those requests also get modified by our continued conversation. I want that tracking
> to also include questions or decisions that are waiting on me."

**The structural question posed:** should (1) conversation/intent tracking and (2) design/plan/
build tracking be ONE surface or TWO? Their candidate lifecycle: "as we close out conversations
and turn those into plans or design efforts, we close out the conversation in that surface and
spawn the designing/planning/building stream in the other surface." Explicitly presented as an
idea to be pushed on, not a directive.

**Their build-surface mental model:** "a status tracking surface that lists all the plans in the
order they are intended to be built. Any plan should be openable into its sub-components. Easy to
see which sub-components have been built, which are in process, which not started."

**Answers to the round-1 questions:**
1. Work-item framing + distilled-editable titles + promote-as-naming: "Yes, I agree."
2. Board vs list: maybe offer BOTH; kanban only occasionally; PRIMARY = hierarchical list
   (intents → plans → sub-components) in intended BUILD ORDER, read as a WATERLINE: "everything
   above what's currently being worked on is marked as complete, and everything below is still
   next on the to-do list."
3. Statuses: **not started / in progress / complete / STALLED-PAUSED — and stalled "should be
   able to tell me WHY it has stopped and WHAT is needed to get it moving forward again."**
4. Telemetry quiet: agree — plus click-to-drill-into-detail on any item.

## Round 3 — operator answers (2026-07-17, verbatim intent)

- **"Complete" oracle:** "Complete means there's nothing else needed to have the item fully
  functional in production." (The strictest reading — merged AND deployed AND working; pure
  functionality-over-components. Per-item, not per-repo convention.)
- **Meeting-sourced items:** "should be proposed to me before being accepted into the status page.
  Ideally a mechanism for me to accept a proposal or modify a proposal and accept bits and pieces
  of it. The system could automatically take the items I approve and inject those into the
  roadmap." (Refines Circuit D2: the promote surface needs accept / modify / PARTIAL-accept, with
  approved fragments auto-injected.)
- **Naming:** "Let this system automatically create its own name. And then simply allow that name
  to always be modifiable by me at any time." (No mandatory confirm ceremony — auto-name always,
  operator-editable always; drops the "auto — unreviewed" gate idea in favor of edit-anytime.)
- **Project facet vs swimlane:** undecided, discuss further.

## Round 4 — operator final refinements (2026-07-17/18, verbatim intent)

- **INBOX CONTEXT MANDATE (load-bearing):** "every item waiting on me makes it very clear where
  that item comes from. It must provide me context, always. I have still been finding plenty of
  requests waiting on me that provide me no context at all and oftentimes do not even provide me
  an actual question. Every request from me absolutely needs to provide me the context I need to
  understand the issue, understand any trade-offs if I need to make a decision, and make it easy
  to determine what's needed in order to answer the question."
- **Tree reading (1):** NOT a strict waterline — "easy to look at the entire list in tree form and
  see which items have been completed, which are in progress, and which have not yet been
  started." Progress bars on in-progress items welcome if cheap ("we do not need to over-engineer
  additional granularity"). Expandable "down to the level of granularity that is actually tracked."
- **Discovered-work insertions (2):** accepted ("Good point").
- **Completed collapse (3):** recently-completed must stay VISIBLE IN PLACE; operator floats:
  collapse only when an entire node completes, and/or age out after a day~week into "ancient
  history"; asked for a recommendation.
- **(4):** "I do not want to maintain a water line. I just want statuses on every individual item."
- **(A) Complete reiterated:** "deployed in production, fully functional, nothing else to be done."
- **(B) Harness chores:** "do not really add any value to my view — leave them out."

## Round 5 — operator (2026-07-18, verbatim intent): event-driven sync + N-machine

> "Instead of updating the repo on a schedule, wouldn't it make more sense to do so whenever
> there's an actual status change? That would make it much easier to control mechanically."
> "Both Jaime and I may be using multiple computers running multiple sessions all in parallel.
> I need the ability to have this same sync between my own computers, in addition to between
> Jaime and myself."

Design response (agreed hybrid, folded into the redesign plan):
- EVENT-TRIGGERED publish: status-changing emissions (task_done/task_started/plan_amended/
  waiting_on_operator/merged) touch a cheap local dirty-marker (never-blocks: no git/network on
  the hook path); a debounced publisher (the existing NL-CoordSync task at a tighter check
  interval, idling when clean) publishes within ~a minute of a real change instead of ≤20min.
- PERIODIC FLOOR STAYS, for two proven reasons: (1) hooks are blind to git ops (cherry-pick/pull
  mutations fire no event — the coverage hole that killed the v2 store design); (2) the A3ii
  keepalive REQUIRES periodic publishes — a purely event-driven idle machine is indistinguishable
  from a crashed one, breaking peer-unreachable honesty.
- Burst coalescing: an orchestrated build fires dozens of events/min; publish is debounced, at
  most ~1/min, hash-gated as today.
- N-MACHINE: already the shipped architecture by construction — exports are per-hostname files;
  every non-self file renders as a peer, so Misha's own second computer is just another peer.
  MISSING layer (redesign scope): hostname→person mapping so peers group by PERSON ("Misha:
  desktop+laptop / Jaime: ..."), and Jaime's account gets push access to the private coord repo.
  Multiple sessions per machine are already aggregated (the exporter derives from machine-global
  state).

## Round 6 — 2026-07-20, live-surface walkthrough (operator, verbatim; screenshot: #roadmap tab)

> "This Workstreams UI is still not very helpful and is still not laid out the way that I've
> told you to. I feel like I've told you this already, but I'll tell you again. What I have in
> mind is I'm picturing a series of plans that are being worked on. We can call it phases one
> through four. If each phase has its own plan and each plan has a list of tasks within it, I
> want to be able to look at a tree that shows four connected tree nodes that are in series,
> each of which is essentially a branch that has the list of tasks as leaves within that
> branch. Each task in that list would display its status: not yet started, current progress,
> or completed. But generally speaking, I want to be able to take a look at everything that is
> currently being worked on and see it all on one single page, organized. Are you able to see
> how what we have right now is not meeting that requirement?"

Gap analysis against the live render (all but #6 are drift from laws ALREADY in the plan):
1. Task leaves render the FULL plan-task markdown (spec/verification text walls) — must be
   one-line: distilled task title + status chip + age; full text drill-down only.
2. "from your request(s):" renders inline and VERBATIM-DUPLICATES the item title (3x on
   screen for one item family) — provenance is a drill-down answer (C6), never inline default;
   suppress entirely when identical to the title.
3. Completed subtrees (18/18, 72-151h old) render fully expanded — the I2 collapse law
   (immediate one-line headline for fully-complete nodes) is not applied; the "N completed ▸ —
   latest:" roll-up prints the latest task's FULL TEXT instead of its title.
4. Edit-title / Move-up / Move-down are always-on full-size buttons (2 rows of chrome per
   item) — must be compact icon affordances on hover/focus (keyboard-reachable per R2).
5. Conversational fragments ("is that really the cleanest way…") render as not-started
   intents — the T2 distill+noise-classification lane is not running/not applied to the live
   registry.
6. NEW SPEC (this round): sibling plans under an intent render as CONNECTED NODES IN SERIES
   (phase 1 → 2 → 3 → 4, build order made visual), each expanding to its compact task-leaf
   list; the whole currently-active picture reads on ONE page.

## Round 7 — 2026-07-20, follow-on to the live walkthrough (operator, verbatim)

> "And there really should not be anything in paragraph form. Lists make it easy to scan
> quickly and capture the information that I need within seconds.
>
> I also see several background tasks running right now. It would make sense to me to see those
> as potentially sub-tasks within the tree. I'm not necessarily saying that all subtasks need to
> be listed within that tree, but that general concept should apply. Tasks within a plan do
> still have somewhat of a hierarchical structure, don't they? I want to see that structure in
> the Workstreams UI."

Two binding requirements (extend Round 6; same authority):
7A. NO PARAGRAPH FORM ANYWHERE in the roadmap surface. Every unit of information is a scannable
    list item: the tree, the item drill-downs, the Inbox anatomy, provenance. Prose blocks are
    banned — if a field carries multi-part content it renders as a bulleted/labeled list, never
    a sentence-paragraph. Design goal (operator): "capture the information I need within
    seconds." This is a global rendering law, audited surface-wide, not a per-view note.
7B. HIERARCHY IS VISIBLE. A plan's tasks have real sub-structure (task → subtasks → live work).
    The tree must SHOW that structure — intent → plan(phase) → task → subtask — as nested
    expandable nodes. Depth is opt-in (not every subtask forced into view; expandable), but the
    concept is mandatory: the tree is a genuine hierarchy, not a two-level list.
7B-i. LIVE BACKGROUND WORK AS SUB-TASKS. Currently-running background agents/sessions render as
    live sub-task leaves under the task they serve (data source: the T1 in-progress derivation —
    listRawHeartbeats + session→plan/task attribution), each with its own live status
    (running / stalled / done). "Everything currently being worked on, on one page" (Round 6)
    includes the live agents, positioned in the tree where the work actually sits.

## Round 8 — 2026-07-21, decisions after the round 6+7 fix deployed (operator, AskUserQuestion)

Context: rounds 6+7 rendering fixes deployed to :7733 (distilled leaves, immediate collapse,
compact chrome, no-paragraph, hierarchy, series-render). Live-DOM check found TWO data-shape
residuals: (a) junk conversational captures ("The computer rebooted.", "is that really the
cleanest way…") still render as top-level roadmap items; (b) the operator's ACTUAL current
work (redesign 8/9, supervisor-tick) does NOT appear — the Roadmap is rooted on captured ASKS,
and active plans have no linked ask. Two decisions:

8A. ROADMAP ROOTS ON ACTIVE PLANS AS PHASES (operator chose "Active plans as phases"). The
    Roadmap tree roots on PLAN files shown as connected phase-nodes in build order, each with
    its tasks as leaves (subtasks per 7B). Requests/asks move ENTIRELY to the Requests tab.
    This is the operator's round-1/6 vision made literal: "a series of plans being worked on,
    phases 1-4, each a branch with tasks as leaves." Show the full status spread the operator
    named (round 4): upcoming / in-progress / partially-done / complete — so roots = ACTIVE +
    recently-completed (aging window) + any DRAFT/queued plans, in build order, status chip on
    each. Completed plans collapse per the I2 aging law.
8B. JUNK HIDDEN FROM ROADMAP ENTIRELY (operator chose "Hide from Roadmap"). Consequence of 8A:
    an unlinked junk ask has NO plan, so a plan-rooted Roadmap never shows it — junk vanishes
    for free, living only in the Requests tab. The noise classifier (round-6 gap 5) becomes a
    Requests-tab-cleanliness nicety, NOT a Roadmap blocker. Retroactive classify sweep +
    classifier deploy stay queued but non-blocking.

LAW: the Roadmap is the PLAN/work tree (phases → tasks → subtasks + live agents); the Requests
tab is the ask/intent ledger. They are different trees rooted on different things. Provenance
links Roadmap→Requests where a plan has a linked ask (C6 bidirectional law preserved), but the
Roadmap's ROOTS are plans, never asks.

## Round 9 — 2026-07-23, operator walkthrough of the round-8 deploy (verbatim; screenshot: #roadmap, 16 phases)

> "This is an improvement, but there are still so many things missing. It sure as hell seems
> like you are just completely forgetting all the things I've asked you for. I see a partial
> tree structure with no context. I see the progress of phases but I don't see any information
> about what those phases are a part of, nor do I see what project it's a part of, nor do I see
> any of the other work that's going on. I do not see the to-do list pane that we've talked
> about repeatedly. I do see the backlog pane on a different page. Are you aware of all the
> things that I've asked for as part of this plan? Is there a reason why it's been such a
> fucking struggle to get you to implement the specific things that I've asked for so fucking
> many times?"

This is the operator's cold-start walkthrough (T9's human component): VERDICT FAIL — friction
list becomes the Round-9 fix round. Live-render audit against the verbatim record:

| # | Operator ask (round) | Live state 2026-07-23 | Diagnosis |
|---|---|---|---|
| R9-1 | Items named by intent, always editable (r3) | Plan phases render RAW SLUGS ("nl-finding-030-crlf-validator-skip") | Renderer ignores the plan file's own `# Plan:` H1 title — distillation lane covers asks, never plan titles. FIX: render H1 title, slug as tooltip/fallback. |
| R9-2 | "Phases of a project" — series under an intent (r2, r6 gap 6) | "PHASE 1 OF 16" numbers 16 UNRELATED plans as one giant series | 8A re-root flattened the grouping level: series-numbering across unrelated plans implies membership in nothing. FIX: group by project (header per group), number within group. |
| R9-3 | Which project each item belongs to (r9 explicit) | No per-item project label (only the filter chip) | FIX: subtle per-phase project chip. |
| R9-4 | Harness chores excluded (r4 operator B) | "0 hidden (harness chores)" while nl-finding-*/watchdog/enforcement plans render as phases | Chore classifier keys on ASK provenance; machine-filed PLANS (no linked ask) default to not-chore — classifier inert on the new plan-rooted tree. FIX: plan-level provenance classes (nl-issue/finding/sweep/watchdog slugs + header field going forward), hidden-count disclosure kept. |
| R9-5 | Provenance never noise (r6 gap 2) | "from your request(s): (no captured request — registered directly)" repeats on nearly every phase | Same noise class the dedup law targeted. FIX: suppress the line entirely when no real link exists. |
| R9-6 | To-do list pane visible ("talked about repeatedly") | Standalone pane RETIRED into Inbox "My items" (A10 adjudication — reviews', not operator's, decision); backlog on Requests tab only | Operator verbatim outranks the A10 adjudication (constitution: inputs doc is supreme). FIX: compact My-items + Backlog side panes on the Roadmap landing. |
| R9-7 | ALL current work incl. live background agents visible (r6 "everything on one page", 7B-i) | No live-agent leaves render; no other-work surface | Agent-leaf pipeline exists (roadmap-routes /agent/ leaves) but only task-BOUND sessions attribute; unbound sessions invisible. FIX: verify pipeline live + render an "unattributed live sessions (N)" node so running work is never invisible. |
| R9-8 | Everything = across the operator's projects | Only neural-lace plans root the tree | Plan scan covers this repo only (verify config); other repos' work invisible. FIX: scan configured repos' docs/plans/ (projects config); honest absence note where a repo has no plans. |

Shipped-and-confirmed by the same walkthrough (for the record): statuses on every item,
progress fractions, build-order series, completed collapse+aging, junk asks gone from the
Roadmap (8B), filter/kanban/chips chrome, Inbox count.

Root cause of the recurring fidelity gap (why rounds keep finding misses), named honestly:
(1) each hop of the pipeline (sit-down -> synthesis -> two gate reviews -> adjudications ->
9 builder dispatches) translated the verbatim record, and translation leaked — A10 retired the
operator's to-do pane on the reviews' authority, 8A dropped the grouping level while gaining
plan-roots; (2) T9 acceptance verified the PLAN's scenarios, not this verbatim record — the
oracle was the synthesis, so builders "passed" while operator asks were missing; (3) several
shipped mechanisms are INERT on live data (chore classifier classifying nothing, agent leaves
with no bound sessions, provenance line rendering its own absence) — component-done, not
functionally-done (constitution §4). Round-9 verification will use THIS table as the oracle.
