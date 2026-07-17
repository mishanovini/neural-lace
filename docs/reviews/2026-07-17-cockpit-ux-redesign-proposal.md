# UX + IA Redesign Proposal: the Workstreams cockpit as a Roadmap Board

**Persona:** solo technical founder running many parallel autonomous Claude sessions, glancing at
this cockpit between meetings; a second teammate (Jaime) joining soon. Verbatim frame (the brief,
`docs/reviews/2026-07-17-cockpit-ux-design-input.md`): *"keep track of the status of everything on
the roadmap: upcoming / in the works / partially done / complete — and how it maps back onto the
specific requests I've made."* No `.claude/audience.md` exists; the operator-authored brief is the
persona source and is stronger than an inferred one.

**Audit mode:** hybrid. Data layer LIVE (HTTP against the running server at `127.0.0.1:7733` —
`/api/asks`, `/api/ask/<id>`, `/api/todo`, `/api/backlog` fetched 2026-07-17; all counts below are
live-PROVEN). Render layer STATIC (no browser MCP available in this environment; every visual claim
is derived from a full read of `asks.js` / `todo.js` / `backlog.js` / `index.html` / `server.js` —
deterministic renderers, so confidence is high, but claims about pixels are code-derived
HYPOTHESIZED, labeled where it matters).

**Date:** 2026-07-17. Author: ux-ia-auditor (deep-redesign brief, operator requirements verbatim).

---

## Executive summary

The cockpit's information architecture is rooted in the wrong entity. The operator thinks in
**work items with a four-state lifecycle** (upcoming / in the works / partially done / complete);
the app is rooted in **asks grouped by project**, with lifecycle expressed only as a manual
active-vs-completed flip. Live evidence of the mismatch: the flagship ask
(`ask-20260710-workstreams-rebuild`) is **18/18 tasks done, narrative "merged to master" — and
renders in the ACTIVE group while the Completed group shows count 0**. The operator's "complete"
bucket is empty precisely when the work is complete (severity 4, Gulf of Evaluation). Meanwhile the
real "upcoming" set (55 open backlog rows) lives in a sidebar pane with a different root entity,
different vocabulary, and no join to asks — the four-bucket question is structurally unanswerable
from this surface. Compounding it: the same live card carries **718 identical unlabeled "drift"
chips** (all one divergence class, `unmatched_dispatch`), and 2 of the 3 live ask titles are the
exact prompt-fragment garbage the operator recanted ("is that really the cleanest way to manage
this process?").

**The proposal:** re-root the landing surface as a **Roadmap Board** — four lanes that ARE the
operator's buckets and ARE Circuit's pipeline states — with **work items** as cards, lane
assignment **derived** (never declared), titles **LLM-distilled at capture and human-confirmed at
promote**, asks demoted to one-click provenance under each card, and a hard **one-chip-per-class**
telemetry law on the primary surface. Nothing in the data layer is rebuilt: the ask registry
becomes the work-item registry by adding a title field and a derivation, and the entire existing
drill-down (plans, sessions, waiting, evidence) survives intact inside the card. Roughly half the
value (badge law, derived lanes, board layout) is renderer + server-derivation work on data that
already exists.

---

## The four IA systems — health at a glance

| System | Current state | Weakest point | Severity |
|---|---|---|---|
| Organization | Ask-rooted tree grouped by PROJECT; lifecycle = manual binary (active/completed); "upcoming" lives in a separate pane with a separate taxonomy | The root entity (ask) is not the operator's unit of thought (work item); the four buckets are not representable | **4** |
| Labeling | Auto-captured prompt-fragment titles; five overlapping status vocabularies; "drift"/"inflight"/"Asks" are system words | Titles: 2 of 3 live asks are meaningless fragments (operator-recanted by name) | **4** |
| Navigation | 2 tabs (Asks, Harness Health) + persistent sidebar (To-Do, Backlog) + docs modal; drill-down lazy per card | Structure is fine; the *grouping dimension* inside the landing tab is wrong (project, not lifecycle) | 2 |
| Search | None anywhere; backlog full list (72 rows) has no filter | Absent escape hatch — tolerable at 3 asks, fails at Circuit-ingest volume | 2→3 |

Navigation and the interaction patterns (undo windows, defect-forms, absolute-link law, lazy
drill-down) are genuinely good — this is a re-rooting and re-labeling problem, not a rebuild.

---

## Current-state IA — map & diagnosis

### The current model (as shipped, observed live)

```
Workstreams (tabs: Asks* | Harness Health)          * = landing
└── Asks tab
    ├── Ask tree (main column) — grouped by PROJECT, open by default
    │   ├── Circuit (1)
    │   │   └── [card] "is that really the cleanest way to manage this process?"
    │   │              no plan · no waiting · narrative: "a session was attached"
    │   ├── neural-lace (2)
    │   │   ├── [card] "Rebuild workstreams around ask-rooted asks…"
    │   │   │          18/18 done · "merged to master" · 718 × [drift][drift][drift]…
    │   │   └── [card] "So how should we update the harness and the standard practice…"
    │   │              no plan · narrative = the same truncated prompt text again
    │   ├── Completed (0) — hidden (renders only when count > 0)
    │   └── Peers — collapsed, "no data yet"
    └── Sidebar: My To-Do (1 resolved pointer) · Backlog (55 open / 3 in flight / 14 closed,
        tiers high/medium/low/unlabeled, compact top-5-per-tier)
```

This is a **hierarchical model rooted in the ask**, with project as the only grouping scheme and
lifecycle reduced to a manually-flipped binary. Every structural defect below follows from that
root choice.

### Diagnosis — the six structural defects (each: framework · gulf · persona impact)

**D1 — The primary job is unanswerable: no lifecycle frame exists.** (Severity 4.)
The operator's stated top job — "status of everything: upcoming / in the works / partially done /
complete" — has no home. "Upcoming" is split between the Backlog pane (55 open rows, different
entity, different vocabulary) and no-plan asks; "in the works" vs "partially done" is
indistinguishable (both render as an active card with a progress bar); "complete" is a manual flip
nobody performs. *Framework:* mental-model mismatch (Norman) — the app's conceptual model (asks by
project) diverges from the user's (work items by lifecycle); a simulated closed card sort against
the operator's four piles fails for every card because the piles don't exist as groups. *Gulf:*
Evaluation — the operator cannot read the state of the system they care about. *Impact:* the
between-meetings glance yields nothing; the operator falls back to asking sessions or reading
plans, which is the exact context-reestablishment tax this UI was built to kill.

**D2 — Complete work renders as active (PROVEN live).** (Severity 4 — a confident wrong signal.)
`/api/asks` today: the rebuild ask has `plan_progress {done:18, total:18}`, narrative "merged to
master", and sits in the active group; `completed.count` is 0. Cause (from `server.js:880-1061`):
ask status is DECLARED (`active|done|dismissed|merged`, flipped only by UI buttons or CLI), never
derived — while the system's own law 4 (design sketch §2) says in-progress is *derived, never
declared*. The lifecycle level was exempted from the law that governs the task level. *Framework:*
Nielsen #1 (visibility of system status) + the project's own derivation law. *Gulf:* Evaluation.
*Impact:* the "complete" bucket under-reports forever (nobody performs bookkeeping clicks —
especially not this operator, at this glance frequency); trust in the whole surface erodes because
its headline claim is visibly stale.

**D3 — The title system is broken as designed (PROVEN live, operator-recanted).** (Severity 4.)
Live titles: *"is that really the cleanest way to manage this process?"* (a mid-conversation
rhetorical fragment, now the sole representation of the Circuit workstream) and *"So how should we
update the harness and the standard practice to ensure that work that gets built actually gets
deployed and that..."* (first-140-chars truncation). *Framework:* information scent (Pirolli &
Card) — the card title is the highest-value cue on the surface and it carries near-zero scent;
Nielsen #2 — the label is the system's raw input, not the user's concept. *Impact:* the operator
cannot recognize their own roadmap; recognition-over-recall (#6) inverts into recall-over-
recognition ("which conversation was that fragment from?").

**D4 — The drift-chip wall: 718 identical unlabeled chips on one card (PROVEN live).** (Severity 4;
screenshot-documented operator complaint.)
All 718 badges are one class (`unmatched_dispatch`, one per task per source), and every one renders
the bare literal "drift" — the badge objects carry `divergence_class`/`message` but
`renderDriftBadges()` (`asks.js:213-238`) looks for `label||type||note` and falls through to the
hardcoded fallback. Two defects compounding: the auditor over-emits (mechanism bug, filed
separately), and the renderer has **no grouping, no cap, no dedup** — so a single upstream bug
converts the primary surface into noise. This violates the app's own anti-noise law (hard
constraint 1) in spirit: the law polices *strings* but not *volume*. *Framework:* Nielsen #8
(minimalism — every extra chip competes with the real signal), Hick's Law, signal-detection.
*Impact:* the one card that matters is unreadable; the operator's verbatim verdict: "the multitude
of drift tags is not helpful."

**D5 — Parked-ness ("partially done") is inexpressible.** (Severity 3.)
The operator distinguishes "in the works" (active now) from "partially done" (started, stalled).
The data to derive this EXISTS — session heartbeat classification (`live|stale|throttled|crashed|
missing`) is in the detail payload (observed live: the rebuild ask carries a `live` dispatcher and
a `missing` origin session), and `activity_ts` is on every card — but liveness is never lifted to
the card/landing level, so a stalled item and a running item render identically. *Framework:* Gulf
of Evaluation; "absence is a named state, never zero" (the harness's own contract, honored
everywhere except here). *Impact:* stalled work silently reads as healthy; the operator discovers
parks by absence, days later.

**D6 — The request-mapping click dead-ends (PROVEN live).** (Severity 3.)
"How it maps back onto the specific requests I've made" is served by the Verbatim reveal — which
renders *"Capture reference (transcript path + prompt offset)"* plus a **relative** path
(`docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md#1` observed live), which the
renderer, per its own absolute-links law, refuses to hyperlink: the operator gets un-clickable
text and a copy button instead of their words. The honest-limitation comment in `asks.js:581-589`
documents the gap (no read surface resolves the pointer to text). *Framework:* weak scent →
dead-end (the label "Verbatim" promises text and delivers a pointer); Nielsen #1. *Impact:* the
second half of the operator's stated frame is a dead click today.

Minor (ledger below): a 274-row artifact wall in the drill-down (same uncapped-list class as D4);
`narrative_excerpt` duplicating the summary when no events exist (renders the same text twice on a
card); five parallel status vocabularies (ask `active/done/dismissed/merged` · backlog
`open/inflight/terminal` · task `done/in_flight/not_started` · operator's four buckets · Circuit's
`PROPOSED/SCHEDULED/…/merged`); no search/filter.

---

## Proposed IA — the Roadmap Board (the optimal structure)

### 1. The organizing frame: a BOARD of work items, four lanes = the operator's buckets

**Decision: hybrid — board primary, existing drill-down retained per card, To-Do sidebar
retained.** Not a status-grouped list as the primary presentation, not the tree re-rooted, for
these reasons:

- **The operator's stated model IS a kanban.** Four lifecycle states of work items is the exact
  conceptual shape of every board tool this persona already lives in (Jakob's Law: Linear, GitHub
  Projects, Trello). Rendering their own four words as lane headers is the strongest information
  scent achievable — the labels are literally the user's vocabulary (Nielsen #2, verbatim).
- **Glance-frequency favors spatial encoding.** Between meetings, the answer to "status of
  everything" should be preattentive: lane occupancy IS the status distribution — column heights
  answer J1 in one fixation, before reading a single title. A status-grouped list carries the same
  IA but demands serial scanning; a tree with per-node status chips demands reading every node
  (weak scent at the top level, high scan cost — this is why re-rooting the existing tree loses).
- **Hick/Miller are satisfied by construction:** 4 lanes (< 7±2), each showing top-N cards +
  "N more" overflow, newest-activity-first within a lane.
- **The board is a presentation over a status-grouped list** — same payload, one grouping
  function; below ~900px the lanes stack vertically into exactly the grouped list. Choosing the
  board costs nothing over the list; it adds the spatial glance layer on wide screens (where this
  operator actually looks).
- **The tree is not discarded — it descends one level.** Everything the current ask card drill-down
  does (per-plan task rows with verifier evidence, waiting-on-you §3 blocks, session lineage,
  artifacts) is *correct* and survives verbatim as the card's expanded view. The redesign moves the
  root, not the branches.

### 2. The root entity: WORK ITEM, with asks demoted to provenance

Stop equating ask == roadmap node. A **work item** is the unit of the roadmap; an **ask** is
evidence attached to it:

```
WORK ITEM  (title: distilled intent, human-confirmable · lane: DERIVED · owner · project chip)
 ├── requests   1..n asks (verbatim, resolved text, when, which session/meeting) ← "Merge into…" already exists
 ├── plans      0..n plan slugs → the existing per-plan drill-down, unchanged
 ├── sessions   0..n, heartbeat-classified, lineage — unchanged
 └── evidence   SHAs / PRs / reviews — capped list + "all N →", unchanged otherwise
```

**No new store.** The ask registry already has everything a work-item registry needs (append-only
records, `merged_into`, `plan_slugs[]`, status, provenance) — Circuit's design already treats it as
the intent store for meeting-extracted items. The change is: add a `title` field (distinct from the
captured `summary`), let multiple asks fold into one item (the existing merge), and derive the lane.
This resolves the three hard cases the brief names:
- **Multi-part prompts:** the distiller (below) may detect N intents; the item renders ONE card
  with a "contains N parts — split?" affordance rather than auto-splitting (error prevention:
  a wrong auto-split is costlier than a wide card; splitting stays an operator/one-click action).
- **Mid-conversation asks:** any session can emit `ask-registry.sh register` mid-stream when a new
  directive lands (mechanism-emitted, same law as the progress log — never model memory deciding
  "this feels like an ask" at session end). The opening-prompt auto-capture continues as the floor.
- **Circuit convergence:** meeting-extracted items ARE work items with `verbatim_ref` = doc anchor
  — the same entity, the same board, zero re-IA when Circuit P1 lands (§6 below).

### 3. Lane assignment: DERIVED, never declared (law 4, extended to the lifecycle level)

The single most load-bearing change. Manual `Done/Dismiss` becomes an *override*, not the
mechanism:

| Lane (operator's word) | Derivation (all inputs exist today) | Circuit state |
|---|---|---|
| **Up next** | item exists ∧ no task done ∧ no live/fresh session. Sub-group at top: **"needs your promote"** (PROPOSED — the D2 gate rendered as an affordance, not a chore) | PROPOSED · SCHEDULED |
| **In the works** | any in_flight task ∨ a `live` heartbeat attached ∨ activity within T (default 24h) | promoted + building |
| **Partially done** | progress > 0 ∧ no live session ∧ last activity older than T. Sub-state chips: **"parked — resting until \<ts\>"** (from watchdog deferral records, Circuit §4.4) vs **"stalled \<age\>"** (no known reason) | partially built |
| **Complete** | all tasks done ∧ merge SHA in evidence (∧ green deploy where a deploy signal exists) → auto-assigns, card carries a one-word "auto" chip until operator-confirmed. Manual Done forces it; disagreement between derived and declared renders ONE labeled chip ("shown done, not merged" — the only divergence class that earns card presence, see §5) | merged / deployed |

Today's live estate under this derivation, for concreteness: the rebuild ask → **Complete**
(18/18 + merged SHAs in its 274 artifacts); the two title-fragment asks → **Up next** (nothing
started); the 55-row backlog stays OFF the board except rows classed as roadmap items (§7).
The board would be honest on day one with zero manual grooming — that is the acceptance test.

### 4. The naming mechanism: distill at capture, confirm at promote, merge for consolidation

Three layers, so quality is absorbed by the system (Tesler) without re-introducing the capture
ceremony the operator already rejected (2026-07-10 Q1: "completely automatic"):

1. **Distill-at-capture (automatic, cheap model).** Registration gains one Haiku/Sonnet call:
   *"state the operator's intent as a ≤12-word imperative title + one-sentence scope."* Input: the
   full prompt (not 140 chars) + basic session context. Fallback when no model is reachable: the
   current truncation, explicitly chip-labeled **"auto title — unreviewed."** Editable inline on
   the card (single click on the title, same round-trip pattern `todo.js` already implements for
   to-do text). This alone converts "is that really the cleanest way…" into something like
   "Design the Circuit continuous-building pipeline" — recognition restored at zero ceremony.
2. **Name-at-promote (the quality gate, riding Circuit D2).** The promote affordance on an
   Up-next card shows the distilled title as an editable field; confirming the promote confirms the
   name. One click = roadmap approval + D4 authorization + naming moment. Nothing enters the
   *promoted* set with an unreviewed title; un-promoted auto-captures may keep auto titles (they're
   labeled as such). This is the Circuit sketch's "naming-at-promote" candidate, adopted — but as
   the *second* layer, so the board is never hostage to promote-backlog for readable titles.
3. **Merge/split for shape correction.** The existing "Merge into…" affordance is the multi-ask →
   one-item consolidator; the split affordance (new, small) is its inverse for multi-part prompts.
   Title provenance chip disappears on first human touch (edit, promote, or merge-target choice).

### 5. The telemetry ecology: the one-chip-per-class law

**The rule (proposed as a payload-schema-enforced law, same enforcement pattern as the anti-noise
and absolute-links laws):** operational telemetry may appear on the primary surface ONLY as
**grouped by class · counted · capped at one chip per class per card · labeled in plain words ·
one click from its detail**. And only divergence classes that change what the operator should
*believe about the card's own claim* qualify at all (e.g. "shown done, not merged"); bookkeeping
classes (`unmatched_dispatch` and kin) render NOWHERE on the board — they live in Harness Health's
diagnostics pane, counted.

Applied to today's live defects:
- 718 × "drift" → at most ONE chip: nothing, in fact, because `unmatched_dispatch` is a
  bookkeeping class — the card shows zero drift chips and Harness Health shows "progress-log
  bookkeeping divergences: 718 (1 class) →". If a belief-changing class fires, the card shows
  "log disagrees with records (n) →".
- 274 artifact rows → newest 5 + "all 274 →".
- Enforcement lives in the RENDERER and the payload schema, not only in the auditor: the auditor's
  over-emission is a real bug being fixed separately (the nl-issue), but the presentation layer
  must be invulnerable to upstream emission bugs by construction — a cap is defense in depth, the
  same reasoning as the schema's identifier scan. (Class: uncapped-list-render; the sweep below
  catches all siblings.)

### 6. Mapping to requests: one click, resolved text, never on the glance surface

Each card's collapsed face shows ONLY: title · lane-relevant chip(s) · progress bar · owner ·
project · age. One click ("from your request(s)", replacing "Verbatim") opens the provenance
panel: per source-ask, the **resolved verbatim text** (requires the small server read-surface that
turns transcript-path+offset into text — the gap `asks.js` documents; for meeting-sourced items,
the doc anchor + "from the 07-17 standup" label per Circuit §2.6), timestamp, session/meeting link
(absolute — the currently-emitted relative `verbatim_ref` is a defect to fix at emission). Merged
items list all constituent requests. The glance view never carries prompt text; the mapping is
never more than one click.

### 7. What the board does NOT show — and the rest of the navigation

- **Harness chores stay off the roadmap.** Backlog rows are two populations wearing one list:
  operator-roadmap intent vs harness-internal engineering chores (live sample: SESSIONSTART-
  SINGLEFLIGHT-01, HOOK-SHIM-RETIRE-01…). Classing is by provenance (emitter: operator /
  notes-extractor / directive ⇒ roadmap; nl-issue / findings ⇒ chore). Roadmap-classed rows join
  the board's Up-next lane (via their registry link, which Circuit's pipeline already creates);
  chores remain in the sidebar Backlog pane, relabeled **"Engineering backlog"** to end the
  collision with the operator's "upcoming" concept. This is the terminology fix with the widest
  blast radius: today "Backlog" is where a cold reader would hunt for "upcoming," and finds
  harness plumbing (false scent).
- **Tabs:** **Roadmap** (landing — the board) · **Harness Health** (unchanged, plus ALL demoted
  telemetry per §5) · **Team** (when un-hidden; until then, per-person facets on the board).
- **Sidebar:** **My To-Do** unchanged (it serves "what needs me" well — one list, count, pointer
  items with escape hatch; observed working live) · **Engineering backlog** (collapsed by default
  now that roadmap items have left it).
- **Multi-user readiness:** every card carries an owner chip (git email → `config/people.js`);
  a thin **"working now"** strip above the lanes — one row per person with a live heartbeat
  (person · item title · plan/task · machine), derived from the heartbeat + peer-store data that
  now exists; peer-sourced cards keep their provenance labels per the existing peer-view law
  (never indistinguishable from local truth). The board gains a person facet, not a fork, when
  Jaime arrives.
- **Search/filter:** one filter box above the board (title/project/person substring) — the escape
  hatch that becomes necessary when Circuit's meeting ingest multiplies card count. Cheap now,
  painful to retrofit under volume.

### 8. The screen, in ASCII

```
┌ Workstreams ────────────────────────────── [Roadmap] [Harness Health]  📁 Docs ┐
│ WORKING NOW  ▸ misha: "Cockpit health integration" · task 3 · desktop          │
│              ▸ (Jaime appears here from peer heartbeats)                       │
├──────────────┬───────────────┬────────────────┬───────────────┬───────────────┤
│ UP NEXT (6)  │ IN THE WORKS  │ PARTIALLY DONE │ COMPLETE (12) │  MY TO-DO (2) │
│              │ (3)           │ (2)            │               │  ☐ call bank  │
│ ┌──────────┐ │ ┌───────────┐ │ ┌────────────┐ │ ┌───────────┐ │  🔒 answer:   │
│ │NEEDS YOUR│ │ │Circuit    │ │ │Notes       │ │ │Workstreams│ │   sched.tasks │
│ │PROMOTE(2)│ │ │meeting    │ │ │connector   │ │ │rebuild    │ │  ───────────  │
│ │┌────────┐│ │ │pipeline   │ │ │████░░ 4/9  │ │ │██████ done│ │  ENGINEERING  │
│ ││Fix intg││ │ │██░░░ 3/11 │ │ │parked —    │ │ │auto ·     │ │  BACKLOG ▸    │
│ ││deploy  ││ │ │● live ·2m │ │ │resting     │ │ │merged     │ │  (55 open)    │
│ ││Promote▸││ │ │misha      │ │ │until 14:05 │ │ │e704e5a    │ │               │
│ │└────────┘│ │ └───────────┘ │ └────────────┘ │ └───────────┘ │               │
│ └──────────┘ │      …        │ ┌────────────┐ │  + 11 more ▸  │               │
│  + 4 more ▸  │               │ │Deploy gaps │ │               │               │
│              │               │ │█░░░ stalled│ │               │               │
│              │               │ │3d — no live│ │               │               │
│              │               │ │session     │ │               │               │
│              │               │ └────────────┘ │               │               │
└──────────────┴───────────────┴────────────────┴───────────────┴───────────────┘
 card click ⇒ expands in place to today's full drill-down:
 requests (resolved verbatim, 1-click) · plans+tasks+evidence · waiting-on-you · sessions · artifacts(5+N)
```

Narrow viewport: lanes stack vertically (Up next → … → Complete) = the status-grouped list;
sidebar drops below — the existing ~1200px stacking pattern, reused.

---

## Per-workflow optimization (top jobs)

| Job (JTBD) | Current flow | Clicks now | Findability | Proposed flow | Clicks after | Framework |
|---|---|---|---|---|---|---|
| J1 "Status of everything" (the glance) | open → read 3 mislabeled cards + mentally join sidebar backlog; four buckets not represented | n/a — **dead** (frame absent) | dead | open → lane occupancy read, zero clicks | **0** | mental-model match; preattentive spatial encoding; scent |
| J2 "What needs me?" | To-Do pane + per-card waiting chips | 0–1 | direct | unchanged; promote-needed items also surface as the Up-next sub-group | 0–1 | already right — kept |
| J3 "Map item → my request" | card → Verbatim → unresolvable relative pointer | 1 → **dead end** (live-proven) | dead | card → "from your request(s)" → resolved text + meeting/session link | 1 | scent honesty; Nielsen #1; absolute-links law applied to emission |
| J4 "Is anything stuck?" | open every card's drill-down, read session states | 2×N, hunt | hunt | Partially-done lane, "parked/resting until" vs "stalled Nd" chips | 0 | derived liveness lifted to card level; absence-is-named-state |
| J5 Promote a PROPOSED item (Circuit) | (future) backlog row hunt → SCHEDULE | — | — | Up-next "needs your promote" sub-group → Promote (confirm title) | 1 | right action at right moment; D2 gate = naming moment = D4 token |
| J6 "What's the team doing?" | Team tab unshipped; peers collapsed at page bottom | hunt | hunt | "Working now" strip, one row per live person | 0 | recognition; heartbeat-derived, provenance-labeled |

## Terminology & labeling fixes

| Concept | Current label(s) | Problem | Proposed | Framework |
|---|---|---|---|---|
| The roadmap unit | "ask" (also: backlog row, plan, PROPOSED item) | one concept, four labels/stores, no join | **work item** (card); "request" reserved for the operator's verbatim ask | one-concept-one-label; Nielsen #4 |
| The landing tab | "Asks" | system word; weak scent for "roadmap status" | **Roadmap** | Nielsen #2 |
| Upcoming work | "Backlog" (sidebar) | false scent — operator's "upcoming" resolves to harness chores | board lane **"Up next"**; sidebar → **"Engineering backlog"** | scent; card-sort pile match |
| Lifecycle states | active/done/dismissed/merged · open/inflight/terminal · done/in_flight/not_started ×5 vocabularies | consistency collision across panes | operator's four bucket words at presentation level; internal states map into them (table §3) | Nielsen #4; match-real-world |
| Divergence chip | "drift" ×718 | unlabeled, uncapped, meaningless | one plain-language chip per belief-changing class, counted; bookkeeping classes → Harness Health | anti-noise law §5 |
| Stalled state | (none) | inexpressible | "parked — resting until \<ts\>" / "stalled \<age\>" | absence-is-a-named-state |
| Title provenance | (none — auto titles look authored) | silent auto-text presented as truth | "auto title — unreviewed" chip until human-touched | honesty at the label level |

## Findings ledger (severity + effort/impact ranked)

```
- Location: /api/asks lifecycle derivation (server.js:880-1061) + Completed group (asks.js:1024-1040)
  Defect: ask lifecycle is DECLARED (manual done/dismiss), never derived — an 18/18-done, merged ask renders ACTIVE; Completed shows 0 (PROVEN live 2026-07-17)
  Framework: Gulf of Evaluation; Nielsen #1; the project's own law 4 ("derived, never declared") applied to tasks but not lifecycle
  Persona impact: the "complete" bucket lies by omission at every glance; trust in the surface decays
  Severity: 4 — every visit, headline claim wrong, persistent
  Class: declared-not-derived-state
  Sweep query: rg -n "set-status|status: reg.status" neural-lace/workstreams-ui/server/server.js (any state a UI button flips that ground truth could derive)
  Effort: M (derivation from existing plan_progress + artifacts SHAs + hb states; manual flip becomes override)
  Impact: H
  Required fix: lane assignment per §3; derived-vs-declared disagreement renders as one labeled chip
  Required generalization: every lifecycle-like state on any surface must name its oracle; declared states get an "operator override" label
- Location: renderDriftBadges (asks.js:213-238) + auditor emission (server/auditor.js)
  Defect: 718 identical chips, all rendering fallback literal "drift" (badges carry divergence_class, renderer wants label/type/note); no grouping/cap/dedup (PROVEN live)
  Framework: Nielsen #8; Hick; the anti-noise law's blind spot (polices strings, not volume)
  Persona impact: the flagship card is unreadable; operator verbatim: "not helpful"
  Severity: 4 — screenshot-documented, buries all real signal on the most important card
  Class: uncapped-list-render
  Sweep query: rg -n "forEach.*appendChild" neural-lace/workstreams-ui/web/*.js — flag any unbounded server-array loop into the DOM (drift_badges:718, artifacts:274 both live-confirmed; sessions, waiting_items, peer entries are siblings)
  Effort: S (renderer group-by-class + cap) + M (auditor dedup upstream, separate nl-issue)
  Impact: H
  Required fix: §5's one-chip-per-class law at the renderer; bookkeeping classes off the board entirely
  Required generalization: payload-schema/renderer cap contract for EVERY array render (top-N + "all N →")
- Location: ask registration capture (summary field; live examples ask-auto-c8c373d5e0a7df2d, ask-auto-916a4dd3c8886377)
  Defect: titles are first-~140-chars prompt fragments; 2 of 3 live titles meaningless (operator-recanted mechanism)
  Framework: information scent — the highest-leverage label on the surface carries none; Nielsen #2/#6
  Persona impact: operator cannot recognize their own roadmap items
  Severity: 4 — permanent, affects every future capture, poisons the board's usefulness
  Class: raw-input-as-label
  Sweep query: rg -n "summary" adapters/claude-code/scripts/ask-registry* — every summary writer
  Effort: M (distill call + fallback + editable title + provenance chip); promote-confirm rides Circuit P1 task 5
  Impact: H
  Required fix: §4 three-layer naming
  Required generalization: no auto-captured text renders unlabeled as if human-authored, anywhere
- Location: landing IA (asks.js renderLanding; index.html tab shell)
  Defect: grouping dimension is project; the operator's four-bucket lifecycle frame is unrepresentable; "upcoming" split across two taxonomies
  Framework: organization-scheme mismatch (Rosenfeld/Morville); failed closed card sort vs operator's stated piles
  Severity: 4 — the primary job (J1) is structurally unanswerable
  Class: wrong-root-entity
  Sweep query: n/a — instance-only (the one landing surface)
  Effort: M (board = regroup of existing payload + liveness field lift + CSS lanes)
  Impact: H
  Required fix: §1–§3 board; project becomes facet
  Required generalization: n/a
- Location: card-level liveness (payload for /api/asks omits session states that /api/ask/<id> carries)
  Defect: parked vs active indistinguishable at glance level
  Framework: Gulf of Evaluation; absence-is-a-named-state
  Severity: 3 — daily, overcome-able only by N drill-downs
  Class: detail-only-signal-needed-at-glance
  Sweep query: compare /api/asks card fields vs /api/ask detail fields; any glance-critical signal (liveness, waiting sources, resting-until) trapped in detail
  Effort: S (derive-lib already classifies; lift a summary field)
  Impact: H
  Required fix: lane derivation + parked/stalled chips (§3)
  Required generalization: any signal used by lane assignment must exist in the landing payload
- Location: verbatim_ref emission + renderVerbatimBody (asks.js:558-594)
  Defect: relative ref emitted (live: "docs/reviews/…#1"), unresolvable pointer shown instead of text
  Framework: dead-end scent; the app's own absolute-links law violated at emission
  Severity: 3 — the operator's request-mapping job dead-ends
  Class: pointer-shown-instead-of-content
  Sweep query: rg -n "verbatim_ref" adapters/ neural-lace/ — every emitter and consumer
  Effort: M (transcript-offset → text read surface, server-side; absolute-path emission fix S)
  Impact: M-H
  Required fix: §6 resolved-provenance panel
  Required generalization: refs rendered to the operator resolve to content or say why not
- Location: narrative_excerpt fallback (live: ask-auto-916a… narrative == summary)
  Defect: no-events fallback repeats the summary — same text twice on one card
  Framework: Nielsen #8; redundancy noise
  Severity: 2 · Class: fallback-duplicates-sibling-field · Sweep: rg -n "narrative_excerpt" server/ · Effort: S · Impact: L
  Required fix: fallback = "no progress recorded yet"; generalization: no fallback may duplicate an adjacent field
- Location: board/backlog volume (future, Circuit ingest)
  Defect: no search/filter anywhere; backlog full list already 72 rows
  Framework: missing Search system (Morville) — no escape hatch when scanning fails
  Severity: 2 today → 3 at ingest volume · Class: missing-search-escape-hatch · Sweep: n/a — app-wide absence · Effort: S · Impact: M
  Required fix: §7 filter box; generalization: any surface that can exceed ~2 viewports gets a filter
```

## Effort/impact phasing — what's JS/CSS-only vs data-model work

**Phase A — renderer + derivation only (no schema/data-model change; ships this week):**
1. One-chip-per-class + list caps (D4, artifacts) — S, H. Pure `asks.js` + a small auditor dedup.
2. Lane derivation + board layout — M, H. A grouping function over the existing payload + CSS
   lanes + one server change (lift liveness summary into `/api/asks`); manual status → override.
3. Relabels: Roadmap / Up next / Engineering backlog / plain-word chips — S, H.
4. narrative fallback fix; filter box — S, M.
   *Acceptance (functionality-over-components): the live estate renders honestly — rebuild ask in
   Complete, two fragments in Up next, zero drift chips on the board, Harness Health carrying the
   718 count.*

**Phase B — small data-model additions:**
5. `title` field + distill-at-capture + provenance chip + inline edit — M, H.
6. Verbatim resolution read-surface + absolute-ref emission fix — M, M-H.
7. Split affordance; roadmap-vs-chore provenance classing — M, M.

**Phase C — rides Circuit (P1/P2), no re-IA:**
8. Promote-with-naming on Up-next cards (Circuit P1 task 5 is this affordance's natural home).
9. Meeting-provenance labels; PROPOSED sub-group feed from notes-extractor.
10. "Working now" strip + person facet + resting-until chips from deferral records (Team un-hide,
    Circuit P2/P3).

## Open questions for the operator (the sit-down — only calls that are genuinely yours)

1. **The parked boundary.** "Partially done" vs "in the works": is it *no live session + >24h
   quiet* (my default T), or do you want *any* item without a live session right now to read as
   parked, however recent its activity? This sets how twitchy the middle two lanes feel at your
   glance frequency — you know your rhythm; I don't.
2. **What "complete" means, per project.** For the harness, merged-to-master IS done. For
   Circuit (real users), is a card Complete at merged, or only at merged **and green-deployed**?
   One word each; it becomes the lane's oracle.
3. **What belongs on the roadmap board.** Operator-requested + meeting-sourced work only (harness
   self-improvement chores stay in the sidebar Engineering backlog) — my recommendation — or
   everything including harness internals? This decides what Jaime sees as "the roadmap" and how
   full the board runs.
4. **Naming ceremony floor.** Title-confirm mandatory at promote only (my recommendation:
   session-captured items keep editable auto-distilled titles, labeled "auto"), or must every card
   on the board carry a human-confirmed title? You rejected capture ceremony once — this is the
   same dial, one notch up, and only you know if "auto, unreviewed" chips on the board would annoy
   or reassure you.
5. **Project on the board: facet or swimlane?** My proposal filters by project (chips on cards,
   one-click facet). If you scan *by project first, lifecycle second*, horizontal project swimlane
   rows × lifecycle columns is the alternative — it costs vertical space and glance speed, which
   is why I didn't pick it. Pure scanning taste: yours.
