# Ask-rooted Workstreams view — design sketch (for operator review)

Status: DRAFT — awaiting operator review. No code changes until approved.
Author: orchestrator session, 2026-07-10, from the operator's own requirements
(conversation of 2026-07-10; verbatim pain points condensed in §1).
Supersedes-in-direction: the six-question pane IA of the O.4 rebuild (the *data
layer* of wave O is retained in full — see §4). Prior art: the original
conversation-tree UI (git history `952c9d6` → `e7393bc`), the wave-O design
sketch (`docs/reviews/2026-07-04-observability-design-sketch.md`), decision 060.

## 1. The problem, in the operator's terms

- Fire-and-forget parallel sessions work, but **returning to a session costs a
  context-reestablishment tax**: verbose transcripts, unclear relevance, scroll
  archaeology to rediscover "what did I even ask for?"
- **Decisions arrive without the context needed to answer them.**
- No at-a-glance view of **how much of a build plan is done / in flight / not
  started** — especially painful in long sessions.
- Wanted surfaces: (1) per-ask view — my ask → the plan → progress → what's
  waiting on me, in context; (2) a to-do list of everything waiting on me PLUS
  a freely-editable personal to-do list; (3) a backlog view of
  decided-but-not-started items.
- Long-term: the same surface extended to the whole team — who is working on
  what, status, sessions per person — to delegate without toe-stepping.
  Forward-compatibility now; full build later (unless trivially cheap).
- The 2026-07-10 verdict on the six-question cockpit: "not helpful at all,
  super noisy... completely different from what I had originally asked for.
  I actually really liked the original design a lot better."

## 2. What went wrong last time (both times) — the laws this design keeps

The ORIGINAL tree UI had the right IA (ask-rooted) on a rotten data layer
(sessions cooperatively self-reporting their status — they forgot, lied, went
stale; NL-FINDING-024). The O.4 REBUILD fixed the data layer (derive from
ground truth) but silently replaced the IA with six harness-centric panes —
and its one value metric (operator trust) shipped with no mechanism, so the
value regression went unmeasured until the operator screenshotted it.

Laws carried into this design (law 1 AMENDED per operator direction
2026-07-10 — "the original data layer approach was not the problem; the
problem was in the implementation: sessions forgot, emitted wrong, went
stale"):

1. **Log-first, derive-to-audit.** The primary read surface is an
   append-only per-ask PROGRESS LOG — cheap, instant, chronological,
   readable as a narrative ("what's done, what's in flight, what remains").
   The failure class of the original implementation is closed MECHANICALLY,
   not by hoping sessions remember: **every log event is emitted by a
   mechanism, never by model memory** — the task-verifier checkbox flip
   emits "task done"; the orchestrator's dispatch emits "task started"; a
   NEEDS-YOU append emits "decision waiting on operator"; a master merge
   emits the SHA; a plan amendment emits "plan updated." The wave-O
   derivation layer is DEMOTED from sole-truth to AUDITOR: background
   reconciliation (relaxed cadence — no more real-time derivation on the
   landing path) compares log vs ground truth and badges drift on exactly
   the divergent item. This is wave-O law 1's own escape clause ("event-
   sourced views are acceptable only with a ground-truth reconciler that
   flags divergence") — chosen this time instead of the purist extreme.
   Writes from the UI go to the SAME durable files sessions already read
   (NEEDS-YOU.md, backlog.md, the to-do file) — never a parallel store.
2. **Operator-altitude only on the landing page** (new — the anti-noise law).
   Every item rendered on the landing surface must be something the operator
   can act on or learn from *as the owner of asks*. Harness telemetry (gate
   gaps, stop-verdict breadcrumbs, drift internals) NEVER renders there — it
   lives in a diagnostics tab. Mechanically checkable: the landing-page
   payload schema has no field that carries gate/hook identifiers.
3. **Cold-reader bar at the source** (existing constitution §3, now enforced
   at render time too). A waiting-on-you item renders ONLY if it carries its
   context block (what-is-this / what-changes / why-yours). Items missing it
   render as a visible defect ("context missing — session violated §3"), not
   as a bare ID.
4. **In-progress is derived, never declared.** "Currently being worked on" =
   live heartbeat attached to the plan's branch/worktree + orchestrator
   dispatch records. A builder saying "I'm on task 3" is not evidence.

## 3. Information architecture

Landing page = **the ask tree** (one card per ask, newest activity first):

```
ASK (short summary — verbatim original one click away; when; which session)
 ├─ PROGRESS LOG          chronological, mechanism-emitted narrative:
 │                        "task 3 verified done (SHA) · builder dispatched
 │                        on task 5 · decision D waiting on you · plan
 │                        amended: +task 12" — the primary read; drift
 │                        badges appear inline where the auditor disagrees
 ├─ PLAN  docs/plans/<slug>.md          [██████░░░░] 6 done · 2 in flight · 4 not started
 │   ├─ done:       task list, each with verifier-flip evidence link
 │   ├─ in flight:  from "task started" events, audited vs heartbeats
 │   └─ not started
 ├─ WAITING ON YOU (n)   each item: §3 context block + one-word reply options
 ├─ ARTIFACTS            PRs, master SHAs, review docs, completion reports
 └─ SESSIONS             live/stalled/done sessions attached to this ask
```

Plan evolution: when conversation changes the scope, the TRACKED PLAN is
updated (normal planning doctrine) and the amendment lands in the progress
log — the ask node stays stable as the root.

Tabs (not landing): **My To-Do** — ONE list, two item sources: (a)
operator-created free items, freely editable; (b) Claude-created POINTER
items, auto-added by the same mechanism that appends a decision/question to
NEEDS-YOU.md (never by model memory) — each pointer carries its §3 context
and links back to the waiting item; in P1 clicking navigates to full
context (answer in-session), in P2 answering happens in place; the box
auto-checks when the underlying item resolves (derived, not manual).
· **Backlog** (docs/backlog.md rendered; BOTH Claude and operator can add —
operator via a small append form in the UI; disposition words as buttons —
SCHEDULE / DEMOTE / FOLD / WONTFIX write the disposition the loop already
understands) · **Harness Health** (the six wave-O panes, demoted verbatim —
operator condition: they stay only if they work and stay quiet) · **Team**
(empty shell in P1; see §6).

Progress semantics (per plan): `done` = checkbox flipped by task-verifier
(mechanical); `in flight` = §2 law 4 derivation; `not started` = remainder.
Counts + bar at ask level; drill-down opens the plan with per-task rows.

## 4. The one new primitive: the ask registry

Nothing today records the operator's ask verbatim — plans are Claude's
interpretation. New: `~/.claude/state/ask-registry.jsonl` (machine-local,
per-user) + an in-repo mirror for team flow later.

Capture: **fully automatic** (operator decision 2026-07-10) — every
session's opening operator request is registered as an ask by the
SessionStart machinery, zero ceremony. Display form is a SHORT SUMMARY
(operator: "does not need to be verbatim — a summary is fine as long as I
can remember what I asked for"); the verbatim original stays one click away
in the detail view. Merge / rename / dismiss are optional UI actions, never
required. Plan creation links plan-slug ↔ ask-id (the planning doctrine
gains one line: record the ask-id in the plan header). Sessions attach via
origin + explicit resume references; multi-session asks share one node.

Schema (per entry): `{ask_id, user, machine, repo, summary, verbatim_ref,
ts, origin_session, status: active|done|dismissed, plan_slugs[],
merged_into?}`.

## 5. Reuse map (nothing rebuilt that already exists)

| Need | Source |
|---|---|
| Tree/card UI, details popup, inline response patterns | git history `952c9d6`, `d0df33a`, `aafbdc7`, `e7393bc` (old conv-tree UI) |
| Derivation plumbing, caching, health/lobotomy contract | wave-O server + derive-cache (as of master `02ff2f3`) |
| Done-ness oracle | plan checkboxes (task-verifier-only flips) |
| Liveness | session heartbeats (O.2) + reaper |
| Waiting-on-you source | NEEDS-YOU.md (§2 canonical ledger) + AskUserQuestion pendings |
| Backlog + dispositions | docs/backlog.md + O.9 loop |
| Six-question panes | demoted intact to the Harness Health tab |
| Old event-sourced writers/gates | stay in attic/ — NOT resurrected |

## 6. Multi-user forward compatibility (design now, build later)

- Every node/payload carries `{user, machine, repo}` provenance from day one.
- The UI's reader takes a LIST of derivation sources; P1 ships with one
  (localhost). A future aggregator merges N users' derived JSON — the seam is
  the existing pane/tree API, not a new protocol.
- Git-flowing state (plans, backlog, NEEDS-YOU, ask-registry mirror) is
  already multi-user via the shared repo. Machine-local state (heartbeats,
  sessions) is the only layer needing a sync channel later.
- Explicitly deferred: identity/auth, cross-machine transport, realtime.

## 7. Phases + the usefulness bar

- **P1 (the priority):** the mechanism-emitted PROGRESS LOG (emission hooks
  on verifier-flip / dispatch / NEEDS-YOU append / merge / plan amendment) +
  ask registry (automatic, summary-form) + ask-tree landing page reading the
  log + plan progress counts + waiting-on-you (cold-reader-enforced) + My
  To-Do (operator items + auto-added Claude pointer items) + Backlog tab
  (both can add) + Harness Health demotion + background auditor with drift
  badges. Read-only except To-Do edits + backlog adds/dispositions.
  **Acceptance = operator walkthrough:** cold-start any ask and answer "what
  did I ask, what's the plan, how far along, what needs me" in under 60
  seconds without opening a transcript.
- **P2:** inline answering from the surface (decision replies written to
  NEEDS-YOU.md / the session-readable ledger — the old UI's inline-response
  pattern, resurrected).
- **P3:** team aggregation (§6).

## 8. Pre-registered success metrics — each WITH a mechanism (audit lesson)

1. **Context-reestablishment**: operator can cold-start any active ask in
   <60s via the surface. Mechanism: the P1 acceptance walkthrough, repeated at
   a scheduled 2-week check-in that ASKS the operator (calendar task, not
   vibes). Falsifier: operator still scroll-hunting transcripts.
2. **Zero telemetry on the landing page**: landing payload contains no
   gate/hook-identifier fields. Mechanism: schema check in the server
   self-test + doctor.
3. **Waiting-on-you completeness+dedup**: every NEEDS-YOU open item renders
   exactly once. Mechanism: reconciler-style count comparison
   (ledger-parsed vs rendered), on the existing drift-badge pattern.
4. Invariant-class health (not snapshots): the P1 surface inherits the
   lobotomy/health/restart contract that now exists (master `02ff2f3`).

## 9. Operator decisions — RESOLVED 2026-07-10

Q1 ask capture: **completely automatic** (no promotion ceremony).
Q2 six panes: **demote** to Harness Health tab — conditional on them
   actually working and not being noisy.
Q3 tree depth: **shallow first** (cards + plan drill-down; deepen later).
Q4 answering from the surface: **phase 2**; phase 1 = trustworthy read +
   editable to-do.
Q4b to-do storage (decide-and-go, one-revert reversible): in-repo
   `docs/operator-todo.md` — Claude-pointer items require Claude write
   access anyway, and the team goal makes it shared eventually.
Architecture amendment (operator): log-first with mechanism-emitted events;
   derivation demoted to auditor (§2 law 1 as amended).

Next: plan doc per planning doctrine (ux-designer + systems-designer
plan-time reviews), then build under the orchestrator pattern. Done-whens
written invariant-class where the property must survive respawns/growth
(audit lesson); every task carries the §7 usefulness bar, not component
evidence.
