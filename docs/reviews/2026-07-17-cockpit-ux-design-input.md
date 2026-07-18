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
