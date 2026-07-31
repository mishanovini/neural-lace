# UX + IA Audit: Cockpit (live app at 127.0.0.1:7733)

**Persona:** single operator-maintainer reviewing work done by AI agents across machines — non-developer posture when reading the UI, expert on the work itself. Standing complaint (verbatim): "I keep having to nudge you for little UI improvements that any decent UX designer should have caught on their own."
**Audit mode:** live-data + served-code hybrid. No browser MCP was available; I curled the live app's real API payloads (`/api/roadmap`, `/api/requests`, `/api/inbox`, `/api/pane/*`, `/api/reconciler`, `/api/docs`) AND the actually-served JS/CSS/HTML from 127.0.0.1:7733, then traced every rendering path in the served source. Click-paths are code-derived (HYPOTHESIZED where marked); every content claim is grounded in a live payload fetched 2026-07-30 (PROVEN).
**Critical grounding note:** the worktree copy of `neural-lace/workstreams-ui` this agent was pointed at is STALE — the live server serves Round-15 code (plan banding, Docs-panel crash fix, Machines renderer, inbox `(!)` error count, inbox links block) that the worktree copy lacks. Everything below was verified against the SERVED assets (the live truth), not the worktree copy. Implementers: fix against master/live, and beware that several "obvious" findings (empty Machines pane, Docs crash) are already fixed live — they are NOT re-filed here.
**Already in flight (Round 16 — NOT filed below):** inter-plan spacing; rendered markdown in the plan-doc popup; removing buttons under plan links; no title editing; drag-and-drop reordering; green (not blue) running states. The `/api/pane/status` and `/api/pane/costs` rc=1 backend bugs are being fixed separately — only their *presentation* is audited here.
**Date:** 2026-07-30

---

## Executive summary

The four-tab IA (Roadmap / Requests / Inbox / Harness Health) is structurally sound after fifteen redesign rounds — the remaining damage is concentrated in three places. (1) **Every surface that shows a runnable command renders it as inline prose** except the one quarantine escape-hatch that got it right; the operator cannot tell where a command begins and ends, on the exact surface (Inbox asks) whose whole job is "act on this." (2) **The Requests ledger is a dead end being fed garbage**: the live ledger's top open "request" is a 401 error string that silently *overwrote the operator's actual words* as the title, dragging 93 identical "amendment captured" rows behind it — and the view offers no dismiss/close verb at all (the old ask-tree's lifecycle affordances are `display:none`). (3) **Labels lie in three load-bearing places**: the app calls itself "Workstreams" when the operator has ruled it "Cockpit"; the "Harness Health" tab label promises system trust but the tab actually contains the operator's what-happened/what-needs-me/costs glance panes; and every age older than an hour renders in raw hours ("registered 377h ago" is live on screen right now — nobody thinks in 377-hour units). The two red "Derivation failed rc=1" panels present a bash stack trace plus a jq usage hint as the primary content — the inverse of what this persona needs (plain-language impact first, technical detail folded, one-click copy-for-the-fixing-session). Top jobs average well; the fixes are mostly S-effort label/rendering discipline, with one M-effort structural move (relocate "What happened since your last look" to the landing tab).

---

## The four IA systems — health at a glance

| System | Current state | Weakest point | Severity |
|---|---|---|---|
| Organization | 4 task-based tabs (flat/fully-connected — right model for 4 sections), hash-addressable items, landing = Roadmap | Q3 "What happened" (diff-since-last-look) + Q5 costs live under "Harness Health" — operator glance questions filed under a maintainer label; Q1/Q2 duplicate Roadmap/Inbox content at lower fidelity with no cross-links | 3 |
| Labeling | Mostly persona-vocabulary ("waiting on you", "Shipped", "in build order") after R11's terminology sweep | App-name split (Workstreams vs Cockpit); "Harness Health" false scent; hour-only ages ("377h ago"); "partially done" vs "merged — deploy unverified" (one concept, two labels, same screen); session-id-first identity | 3 |
| Navigation | Strong: `#roadmap/<id>` / `#request/<id>` / `#inbox/<id>` cross-view law (land+highlight+focus+back+miss-banner) | The law is applied *except* on the Health tab: interrupt-strip chips and Q2 needs-me cards are inert text — the items they name are one `#inbox/<id>` away | 2 |
| Search | Per-view filters (roadmap: title/task-id; requests: title/intent/verbatim; docs: filename); no global search (acceptable at 4 tabs) | Docs browser = ONE flat list of 630 file rows (603 neural-lace + 27 coordination, live count) with a filename filter as the only structure | 2 |

---

## Current-state IA — map & diagnosis

```
Cockpit (h1 says "Workstreams")                      ← naming collision, operator already ruled
├─ #roadmap  Roadmap (LANDING)
│  ├─ toolbar: filter · project chips · harness-chores toggle · Kanban toggle · age label
│  ├─ project group "neural-lace — 26 plans, in build order (…)"   ← live: single project, so
│  │  ├─ band 1: in-progress-ish plans (8, rank order)                grouping-by-project is a no-op today
│  │  ├─ band 2: upcoming plans (10, rank order)
│  │  └─ Shipped (8) — collapsed roll-up
│  ├─ unbound-sessions node (4 live sessions, top of tree)
│  └─ sidebar: My items (…) · Backlog (…)  → "open in Inbox" / "open full backlog"
├─ #requests  Requests ledger
│  ├─ Open (3) — one is a 401-error junk capture with a 95-event timeline
│  └─ Closed (1) — grouped this week/this month/older; one titled literally "none"
│  └─ [hidden] old ask tree (asks.js, display:none — its lifecycle verbs went with it)
├─ #inbox  Inbox (N) — answerable → quarantine → My items
└─ #health  "Harness Health"
   ├─ toolbar: Refresh · reconciler badge
   ├─ interrupt strip (inert text chips)
   ├─ 2·What needs me │ 1·What's running │ 4·Harness health │ 5·Costs │ 3·What happened │ Backlog health
   ├─ Machines — cross-machine peer state (honest empty state, Round 15)
   └─ Diagnostics — auditor/reconciler internals
[global] 📁 Docs → flat 630-row list, filename filter → doc modal
```

**Diagnosis.** The navigation model (flat tab set + item-level hash addressing) fits the task profile: four sections, all one click apart, items deep-linkable — no restructure needed at the top level. The residual structural defects are *placement* and *duplication*, both inside the fourth tab:

1. **"Harness Health" is a label for one pane, not the tab** (false information scent, Pirolli/Card). The tab actually answers five different questions, three of which ("what happened since I last looked", "what's it costing", "what needs me") are operator glance questions, not harness trust questions. A cold operator asking *"what did the agents ship while I was away?"* would click Roadmap (its Shipped group shows completed *plans*, not the commit/decision diff) and never discover Q3 + Mark-seen under "Harness Health" — a tree-test **hunt→dead** on a top job. Norman: this widens the Gulf of Execution (the control exists; its location contradicts the intent that needs it).
2. **Q1/Q2 duplicate Roadmap-running and Inbox at lower fidelity.** The same needs-you item renders as structured anatomy in the Inbox and as a raw pre-wrap text blob in Q2 ("What needs me"); the same running sessions render as titled task rows on the Roadmap and as bare `session_id branch=…` rows in Q1. Duplication is defensible (the Health tab is the trust/reconciliation surface) — the missing piece is the cross-link: neither Q2 cards nor interrupt-strip chips navigate to `#inbox/<id>`, breaking the app's own every-cross-view-arrow law exactly once, on one tab.

---

## Proposed IA — the optimal structure

Keep the four-tab flat model (correct for this task count — Hick-cheap, everything one click). Three changes, smallest that fix the diagnosis:

```
Cockpit                                   ← one name everywhere: <title>, h1, aria-labels
├─ Roadmap (landing)
│  └─ + "Since your last look" strip (relocated Q3: commits · decisions · failures + Mark seen)
├─ Requests   (+ lifecycle verbs: Dismiss / Merge-into / Close — the ledger's missing exits)
├─ Inbox (N)  (unchanged structure; command-fenced rendering; open-session affordance)
└─ System     (renamed from "Harness Health" — truthful label for what remains:
               What's running · What needs me [→ cross-linked to Inbox] · Harness health ·
               Costs · Backlog health · Machines · Diagnostics · reconciler)
```

- **Relocate Q3 "What happened" to the Roadmap landing** (organization fix): diff-since-last-look is the operator's #1 return-visit question; the landing is where they return. The pane is already self-contained (own endpoint `?since=`, own Mark-seen anchor in localStorage). The Health tab keeps trust panes only. *Framework: information scent + card-sort pile ("what happened" sorts with "what's the state of the work", not with "is the harness broken"); narrows the execution gulf for job J3 below.*
- **Rename the fourth tab** to match its (post-relocation) contents — "System" or "Diagnostics". If Q1/Q2/Q5 stay, the current name is still wrong; if the operator prefers zero relocation, the rename alone fixes the scent. *Framework: Nielsen #2 match-real-world; label-contents contract.*
- **Give Requests its lifecycle verbs** (see finding 3) — a ledger with no exit verb besides "became a plan" cannot be groomed, and the live data shows it already needs grooming.

Everything else stays: the redesign rounds got the Roadmap anatomy, the Inbox contract, and the hash-routing law right.

---

## Per-workflow optimization (top jobs)

Click counts are code-derived from the served build (HYPOTHESIZED until clicked in a browser); content is live-payload PROVEN.

| Job (JTBD) | Current flow | Clicks now | First-click/findability | Proposed flow | Clicks after | Framework |
|---|---|---|---|---|---|---|
| J1 What needs me? | tab shows "Inbox (1)" → click → read | 1 | **direct** (count in label = strong scent) | unchanged | 1 | — |
| J2 What are agents doing now? | Roadmap: in-progress band first, running chips, unbound-sessions node | 0–1 | **direct** (post-R15 banding) | R16 running roll-up lands; keep | 0–1 | — |
| J3 What shipped since I last looked? | Harness Health → scroll to "3 · What happened" → Mark seen | 2 + scroll, wrong first click likely | **hunt→dead** (label contradicts intent) | "Since your last look" strip on Roadmap landing | 0 | scent; card-sort |
| J4 Answer an ask | Inbox → expand → read prose-embedded command → copy stub → manually hunt for the right terminal window | 3 + terminal hunt | direct until the last step, then **cliff** | + fenced command w/ copy; + copyable `claude --resume <session>` on answerable items (quarantine already has it) | 3, no hunt | Gulf of Execution; consistency (Nielsen #4) |
| J5 Why is this stalled? | stalled chip (real button) → drill-down reason + what-unblocks link | 1 | **direct** | unchanged | 1 | — |
| J6 Is the harness OK? | Health tab → doctor chip + gates | 1 | **direct**; but today's two rc=1 panels present raw bash/jq output | same, with the humane error surface (finding 2) | 1 | Nielsen #9 |
| J7 Clean up a junk request | Requests → … no affordance exists | **∞ (dead end)** | dead | Dismiss/Merge on the row | 2 | Nielsen #3 user control |
| J8 Find a doc | 📁 Docs → type filename fragment → scan flat 630-row list | 2 + scan | **hunt** | grouped-by-project/dir list + recently-opened first | 2 | Hick; Miller |
| J9 Check the other machine | Health → Machines (honest empty state names the pending Windows install) | 1 | direct (post-R15) | unchanged | 1 | — |

---

## Terminology & labeling fixes

| Concept | Current label(s) | Collision / mismatch / weak-scent | Proposed label | Framework |
|---|---|---|---|---|
| The app | "Workstreams" (`<title>`, `<h1>`, aria-label "workstreams views"); operator says "Cockpit" | two names, one app; the operator has already ruled | "Cockpit" everywhere user-visible | Nielsen #2/#4 |
| The fourth tab | "Harness Health" | contains what-happened/costs/needs-me — label promises a subset | "System" (or "Diagnostics") after Q3 relocation | scent |
| merged-but-unverified state | chip "merged — deploy unverified" AND header bucket "partially done" (same screen) | one concept, two labels | pick ONE ("merged — unverified" chip; header bucket "merged, unverified") | Nielsen #4 |
| Ages > 60 min | "377h ago", "59h ago", "227h ago" (live) | machine units, not human units | "16d ago", "2d 11h ago" — add d/wk branches to the ONE shared `formatAge` (app.js) | Nielsen #2 |
| A working session | "session a3fcb6ea" (Q1 rows, Q2 cards, interrupt chips, Inbox source chips) | id-first identity is engineering vocabulary; the Roadmap's own session leaves already lead with the task title | lead with plan/task title; id as secondary/tooltip | Nielsen #2/#6 |
| Error state | "Derivation failed (rc=1)" + `$ nl status --json` + raw stderr | rc/exit-code jargon leads; impact absent | "Can't read live session status right now" headline; detail folded | Nielsen #9 |

---

## Findings ledger (severity + effort/impact ranked)

### F1 — Runnable commands render as inline prose everywhere except the one place that got it right

```
- Location: web/inbox.js optionsTable()/expandedAnatomy() (context lines, option outcomes, my_pick, reply_with);
  web/app.js renderNeedsMe() (.nm-text raw block); inbox "My items" rows (todo text, noise_flag items);
  interrupt-strip chips (first-60-chars truncation can cut a command mid-token)
  Defect: The live Inbox item (NY-1785394095-d8ec, fetched 2026-07-30) renders
  "…run: powershell -File adapters/claude-code/scripts/install-coord-sync-task.ps1 -> the task registers…"
  as one proportional-font prose run inside a table cell. Where the command starts, where it ends, and that
  the "->" is narrative (not part of the command) is undiscoverable. No copy affordance. The SAME item's raw
  block renders identically in Q2. Meanwhile quarantineExtra() renders its `claude --resume` command as a
  readonly monospace input + "Copy resume command" button — the correct pattern, applied only to the rarest case.
  Framework: Nielsen #4 consistency (the app already owns the right pattern); Nielsen #5 error prevention
  (hand-retyping a mis-delimited command IS the error); Gulf of Execution.
  Persona impact: the operator's verbatim complaint — "it's not clear where the command begins and ends."
  Every actionable ask forces squint-parse + manual selection; a wrong selection runs a broken command on
  the Windows machine they were asked to fix.
  Severity: 3 — hits the highest-value surface (asks the operator must act on), every occurrence, persistent.
  Class: unfenced-inline-command
  Sweep query: rg -n "textContent = .*(outcome|o\.outcome|my_pick|reply_with|it\.text|item\.text|p\)|line)" web/*.js
    (then manually: every render site that prints server-authored prose which can carry a command)
  Effort: S–M   Impact: H
  Required fix: one shared renderCommandAwareText() helper: backtick spans and recognized command shapes
  (powershell …, claude …, nl …, git …, bash …, lines starting "$ ") render as a monospace fenced chip with
  a per-command copy button (reuse the quarantine input+copy pattern). Apply to inbox context/options/my-pick,
  Q2 nm-text, My-items rows.
  Required generalization: fence at the SOURCE too — needs-you.sh's §3 lint should require commands be
  backtick-fenced in option outcomes (the producer contract), so every future surface inherits delimitation
  instead of re-solving it per renderer. UI treats backticks as the fence marker.
```

### F2 — Derivation failure is presented as a bash dump with a jq usage hint (live on two panels right now)

```
- Location: web/app.js renderError() (served lines 187–212), rendering /api/pane/status and /api/pane/costs (both rc=1 live)
  Defect: The error surface leads with "Derivation failed (rc=1)", then "$ nl status --json", then a raw
  stderr <pre> whose live content ends in "jq: invalid JSON text passed to --argjson / Use jq --help for help
  with command-line options, or see the jq manpage, or online docs at https://jqlang.github.io/jq". The most
  prominent guidance on the panel is jq's own CLI help pointer — addressed to a shell user mid-pipeline, not
  an operator reading a dashboard. Nothing says WHAT question is now unanswerable ("live session states"),
  WHAT still works, or WHAT happens next (is a defect auto-filed? Retry re-runs a deterministic failure).
  Framework: Nielsen #9 (plain language, precise problem, constructive next step); Gulf of Evaluation
  (operator can't judge severity or scope from rc=1 + stderr).
  Persona impact: non-developer posture reads a wall of path/bash/jq text; can neither triage ("is my work
  state lost?") nor delegate cleanly (no one-click way to hand the detail to a fixing session).
  Severity: 3 — currently visible on 2 of 6 panes; every failure occurrence; high confusion cost.
  Class: raw-internals-as-primary-error-surface
  Sweep query: rg -n "pane-error|stderr_tail|renderError" web/*.js  (also inbox/roadmap/requests renderErrorState —
    those already lead with plain language; only app.js's pane renderError leads with internals)
  Effort: S   Impact: H
  Required fix: reshape renderError(): headline in question terms ("Can't read live session status right now");
  one line of scope honesty ("other panes are unaffected; last good data <age>"); actions: [Retry]
  [Copy technical details] ; the command + stderr fold into <details> "Technical detail (for the fixing
  session)". Keep role=alert.
  Required generalization: any surface that can show subprocess output to the operator (why-drawer error path
  uses the same renderError; /api/refresh failure toast) follows the same headline-first/fold-detail rule.
```

### F3 — The Requests ledger has no lifecycle verbs: a junk request cannot be dismissed

```
- Location: web/requests.js drilldown() — affordances are Edit-title, verbatim disclosure, timeline only.
  The old ask-tree's done/dismiss/merge verbs live in asks.js, which is display:none (requests.js:136).
  Defect: The ledger's ONLY exit is promotion ("became → plan"). Live proof of need: open request
  ask-auto-69752570c1d63e96 is a captured 401 auth error masquerading as an operator request. The operator's
  only recourse is editing its title. Dead end by construction.
  Framework: Nielsen #3 user control & freedom (no exits); JTBD J7 dead.
  Persona impact: the "conversation/intent ledger" — the surface meant to prove "the system heard me" —
  accumulates garbage the operator cannot clear, eroding trust in the whole ledger.
  Severity: 3 — permanent, worsens monotonically as junk accumulates; blocks a real grooming job.
  Class: missing-lifecycle-verb-on-ledger-view
  Sweep query: rg -n "closed_reason|dismiss|merge" web/requests.js server/requests-routes.js
    (server already models closed_reason: 'dismissed'/'merged' — the write path exists conceptually)
  Effort: M   Impact: H
  Required fix: row-level Dismiss (with the app's existing undo-window pattern from backlog.js) and
  Merge-into; wire to the ask lifecycle endpoint the hidden tree already used (/api/ask/<id>/lifecycle).
  Required generalization: every ledger view (Requests, Inbox, Backlog) must carry create/read AND
  resolve verbs on the same surface; Inbox and Backlog already comply — Requests is the one outlier.
```

### F4 — Junk-capture defense: the operator's words were overwritten by an error string; 93 identical timeline rows

```
- Location: server capture path (title auto-update) + web/requests.js timelineNode(); live item ask-auto-69752570c1d63e96
  Defect (three heads, one class):
  (a) origin event says the operator's actual request was "Please connect to gh and download the latest copy
      of Neural Lace." — a title_changed event then AUTO-RETITLED the request to the 401 error string. Machine
      output displaced operator intent on the intent ledger.
  (b) 93 of the 95 timeline events are the literal three words "amendment captured" — rendered as 93 identical
      <li> rows with zero content scent. Expanding the row produces a wall.
  (c) The one closed request renders title 'none' (the string), i.e. a fallback leak, beside "became →
      review-independence".
  Framework: Nielsen #2 (the ledger must speak the operator's words); signal-to-noise (Nielsen #8);
  data-quality defense at the render layer.
  Persona impact: the operator opens Requests and reads an API error where their sentence used to be —
  the exact "system garbled what I said" failure an intent ledger exists to prevent.
  Severity: 3 — trust-eroding on a trust surface; currently 1 of 3 open requests is junk (33% of the view).
  Class: machine-output-displacing-operator-words
  Sweep query: rg -n "title_changed|auto-updated|amendment captured" server/*.js web/requests.js
  Effort: S (render defenses) + M (capture-side)   Impact: H
  Required fix (render layer, immediate): never render a title that is 'none'/empty — fall back to distilled
  intent or became-slug; collapse runs of identical timeline events into "93 amendments captured (no text) ▸";
  cap the default timeline at ~10 events with "show all N".
  Required generalization (capture layer): title auto-update must never replace an operator-authored/origin
  title with text classified as an error signature (401/exception/traceback patterns) — route those to the
  quarantine lane the Inbox already has; amendments with no extractable text should not create events at all.
```

### F5 — "What happened since your last look" is filed under "Harness Health" (IA misplacement + false-scent tab label)

```
- Location: index.html tab "Harness Health" + template pane "3 · What happened"; web/app.js renderShipped()/Mark seen
  Defect: The diff-since-last-look pane (commits, decisions, failure count, Mark-seen anchor) — the operator's
  canonical return-visit question — is only reachable inside a tab whose label promises harness diagnostics.
  Tree-test: cold operator asking "what shipped while I was away" first-clicks Roadmap (its Shipped group shows
  completed PLANS, not the commit/decision diff) and never finds Q3. The tab label is simultaneously wrong in
  the other direction: what's-running/needs-me/costs are not "harness health".
  Framework: information scent (label-contents contract); simulated closed card sort — "what happened" sorts
  into the work pile, not the system pile; Gulf of Execution.
  Persona impact: the highest-frequency question (every return to the cockpit) requires either prior training
  or permanent non-discovery; Mark-seen (the anchor that makes the diff meaningful) goes unused.
  Severity: 3 — frequency is every-visit; impact is silent non-discovery (worst kind — no error to notice).
  Class: glance-question-filed-under-diagnostics-label
  Sweep query: n/a — audit the Health tab's pane list against the question "is this about system trust?"
    (fails: Q3 What-happened, Q5 Costs is borderline; passes: doctor, gates, reconciler, diagnostics, machines)
  Effort: M (relocate Q3 strip to Roadmap landing) + S (rename tab)   Impact: H
  Required fix: move Q3 (with Mark seen) to the Roadmap landing as a compact "Since your last look" strip
  (the pane is endpoint-self-contained: /api/pane/shipped?since=…). Rename the tab to "System".
  Required generalization: one-sentence label-contract check for every tab/pane heading: does the label
  predict ALL of its contents? ("Harness Health" fails; "Inbox — waiting on you" passes.)
```

### F6 — Answering an ask ends in a terminal hunt: no open-session affordance on answerable items

```
- Location: web/inbox.js replyBlock() — "How to answer: reply in session `a3fcb6ea`" + copyable stub, nothing else;
  contrast quarantineExtra() which ships a readonly `claude --resume <id>` input + copy button
  Defect: The primary answer flow (copy stub → deliver to the named session) dead-ends at "reply in session
  a3fcb6ea": the UI knows the session id but offers no way to open/resume it. The DEGRADED class (quarantine)
  got the resume affordance; the PRIMARY class didn't.
  Framework: Nielsen #4 consistency (same need, two treatments, inverted priority); Gulf of Execution
  (intent: "answer it"; required input: alt-tab archaeology across terminal windows/machines).
  Persona impact: every single ask answered = a manual hunt for the right window; on the wrong machine it is
  simply impossible without the resume command the app withholds.
  Severity: 3 — every answer flow, the app's most important write path.
  Class: escape-hatch-only-on-degraded-path
  Sweep query: rg -n "resume_cmd|reply_channel" web/inbox.js server/inbox-routes.js
  Effort: S   Impact: H
  Required fix: render the same copyable `claude --resume <session>` row inside replyBlock() whenever a
  session id is known (the server already computes resume_cmd for quarantine — reuse).
  Required generalization: anywhere a session id is displayed as the destination of an action (Q2 cards,
  Q1 rows' future affordances), pair it with the one-command way to reach it.
```

### F7 — The app has two names, and the wrong one is displayed

```
- Location: served index.html <title>Workstreams</title> (line 6), <h1>Workstreams</h1> (line 26),
  aria-label "workstreams views" (line 27)
  Defect: The operator calls it "Cockpit" and has chosen that as canonical; the UI header, the browser-tab
  title, and the AT label all say "Workstreams". (favicon is also a deliberate 204 — the browser tab carries
  neither a recognizable name-match nor an icon.)
  Framework: Nielsen #2/#4 — the system's name should match the user's name for it; the mismatch also leaks
  into every conversation about the tool ("the Workstreams UI" vs "the cockpit").
  Persona impact: small per-exposure, but it is the FIRST thing on every visit, and it is a decided question
  still rendering the losing answer.
  Severity: 3 by persistence + the operator having explicitly ruled; trivial to fix.
  Class: decided-rename-not-propagated
  Sweep query: rg -in "workstreams" web/index.html web/*.js --no-filename | rg -v "WorkstreamsShell|localStorage|selftest"
    (keep internal identifiers like window.WorkstreamsShell / storage keys — user-visible strings only)
  Effort: S   Impact: M
  Required fix: <title>Cockpit</title>, <h1>Cockpit</h1>, aria-label "cockpit views"; add a favicon.
  Required generalization: when the operator names a thing, sweep user-visible strings the same day;
  internal identifiers may lag, visible ones may not.
```

### F8 — Ages render in raw hours forever: "registered 377h ago" (live)

```
- Location: web/app.js formatAge() (served lines 161–172) — s→m→h, no day branch; exported as
  WorkstreamsShell.formatAge and preferred by roadmap.js/inbox.js/requests.js over their own (dead) day-capable fallbacks
  Defect: Live renders today: Requests "registered 377h ago" and "227h ago"; Shipped group "completed 59h ago".
  Humans convert 377h → "about two weeks" in their head every time; the UI was supposed to do it. The
  fallback formatAge in three view files HAS the day branch — it is dead code because the shell always exists.
  Framework: Nielsen #2 (real-world units); recognition over recall (mental arithmetic per row).
  Persona impact: every age older than a day, on every tab, misreads at a glance — precisely the "any decent
  UX designer" class of nudge the operator is tired of making.
  Severity: 2 — cosmetic per instance, but total-surface-wide and permanent.
  Class: shared-helper-worse-than-its-dead-fallbacks
  Sweep query: rg -n "function formatAge" web/*.js   (one shared fix in app.js heals every view; then delete
    or align the per-view fallbacks so the dead copies can't drift again)
  Effort: S   Impact: M
  Required fix: extend app.js formatAge: <60s, <60m, <24h, <14d → "Nd ago", else "Nw ago" (match the
  fallbacks' existing day logic).
  Required generalization: when a helper is intentionally duplicated per-file, a selftest should assert the
  copies agree — here the shared one silently lagged its own forks.
```

### F9 — The Health tab breaks the app's own cross-link law: interrupt chips and Q2 cards are inert

```
- Location: web/app.js renderInterruptStrip() (chips are <span>s) and renderNeedsMe() (cards render text;
  no #inbox/<id> affordance; item.links only when producer attached links)
  Defect: The interrupt strip exists to say "N item(s) need you now" — but its chips are dead text; the Q2
  card for the SAME item the Inbox renders (same NY- id) offers no "open in Inbox" arrow. The app's C2/C3
  law ("every cross-view link switches tab + lands + highlights") is implemented everywhere else.
  Framework: Nielsen #4 consistency with the app's own navigation law; Fitts (the most urgent items get the
  least clickable treatment on the page).
  Persona impact: the operator reads "needs you NOW", then must manually switch to Inbox and re-find the item.
  Severity: 2 — extra hop, not a dead end; but on the interrupt-priority class specifically.
  Class: cross-view-arrow-law-gap
  Sweep query: rg -n "interrupt-chip|needs-me-card|nm-head" web/app.js  then check each for shell.navigate
  Effort: S   Impact: M
  Required fix: chips and Q2 card headers become buttons → WorkstreamsShell.navigate('#inbox/' + id)
  (session-state chips → '#roadmap/<bound-task>' when a binding exists, else no-op with honest tooltip).
  Required generalization: any element that NAMES an addressable item (NY- id, plan slug, task id) must
  either link to it via the shell or carry an explicit reason it can't.
```

### F10 — Docs browser: one flat list of 630 rows, filename filter as the only structure

```
- Location: web/app.js renderDocsList() (served, post-Round-15 fix) — flat forEach over projects' files;
  live /api/docs: neural-lace 603 files + workstreams-coordination 27
  Defect: Opening 📁 Docs renders ~630 identical button rows ("neural-lace / docs/…") in one scroll column.
  No grouping by project or directory, no recency, no content search — findability rests entirely on the
  operator already knowing a filename fragment.
  Framework: Hick's Law (630 simultaneous choices); Miller (no chunking); information foraging (patch
  structure absent — the operator cannot decide "which folder is worth entering").
  Persona impact: doc lookup (plans, decisions, reviews) is a recurring job; today it's grep-by-memory.
  Severity: 2–3 — mitigated by the filter when the name is known; hunt otherwise.
  Class: flat-list-over-cognitive-limit
  Sweep query: n/a — single surface (the roadmap tree and backlog already chunk; this is the outlier)
  Effort: M   Impact: M
  Required fix: group rows under collapsible project → top-level-directory headers (docs/plans, docs/decisions,
  docs/reviews…), collapsed by default with counts; a "recently opened" section first (localStorage);
  filter matches full path (already true) and auto-expands matching groups.
  Required generalization: any list that can exceed ~2 screens gets chunk-headers + counts (the app's own
  Requests age-groups are the in-house precedent).
```

### F11 — One concept, two labels on one screen: "partially done" vs "merged — deploy unverified"

```
- Location: web/roadmap.js projectGroupHeaderText() bucket 'partially done' vs STATUS_LABEL/KANBAN 'merged — deploy unverified'
  Defect: The group header counts a plan as "partially done" while the same plan's own chip (and kanban
  column) says "merged — deploy unverified". A reader cannot be sure the two phrases are the same state.
  Framework: Nielsen #4; terminology one-concept-one-label rule.
  Severity: 2 — resolvable with a glance-and-infer, but it taxes exactly the state that most needs clarity.
  Class: terminology-collision
  Sweep query: rg -n "partially done|merged — deploy unverified|merged-unverified" web/*.js
  Effort: S   Impact: M
  Required fix: one phrase in both places ("merged, unverified" suggested — shorter for the header strip).
  Required generalization: derive header-bucket labels FROM the status-label map, never a second literal.
```

### F12 — Sessions are identified by hex id first, work second

```
- Location: web/app.js renderStatus() ("a3fcb6ea branch=wip/…"), renderNeedsMe() session chips,
  interrupt chips ("session a3fcb6ea (waiting-on-me)"), inbox source chips ("session a3fcb6ea")
  Defect: The operator thinks in work ("the estate T7 verifier"), not in session hexes. The Roadmap's own
  live-session leaves already lead with the task title — the Health tab and chips never adopted it.
  Framework: Nielsen #2 match-real-world; recognition over recall.
  Persona impact: mapping hex→work is a recall task the operator performs on every glance at Q1/Q2.
  Severity: 2 — persistent low-grade friction; HYPOTHESIZED that bindings exist for most sessions (the
  roadmap payload binds 4 live sessions to tasks today; unbound ones genuinely have only the id).
  Class: internal-id-as-primary-identity
  Sweep query: rg -n "session_id|'session '" web/*.js
  Effort: M (needs the session→task binding surfaced in od_sessions or joined client-side)   Impact: M
  Required fix: where a binding exists, render "<task/plan title> · a3fcb6ea"; keep bare id only for
  genuinely unbound sessions.
  Required generalization: ids are metadata, never headlines, on every operator-facing row.
```

### F13 — Adjacent overlapping counts: tab "Inbox (1)" vs sidebar "My items (2 open)"

```
- Location: index.html #inboxTabCount vs roadmap.js loadSideMyItems() countEl ('answerable + open todos + pointers')
  Defect: Two numbers about "what's waiting on me" visible simultaneously with different scopes (the sidebar
  folds to-dos in; the tab counts answerable only). Both are correct; the pair still invites "which is it, 1 or 2?"
  Framework: Gulf of Evaluation; Tesler (the scoping complexity is pushed to the reader).
  Severity: 2 — the sidebar's inner sections do disambiguate once opened.
  Class: same-concept-different-scoped-counts
  Sweep query: rg -n "open\)'|inboxTabCount" web/*.js
  Effort: S   Impact: L–M
  Required fix: sidebar summary shows the split, e.g. "My items (1 inbox + 1 to-do)" — scope named in the label.
  Required generalization: any two visible counts over overlapping sets must name their scopes in-label.
```

### F14 — Inbox collapsed row and expanded head repeat the identical sentence (and raw text repeats it a third time)

```
- Location: web/inbox.js renderRow() (summary .ib-ask-text = item.ask) + expandedAnatomy() head
  ("Decision needed: " + item.title) — for live items ask === title verbatim
  Defect: Expanding an item shows the same full sentence twice within ~40px; "Raw verbatim" holds it a third
  time. The summary also wraps to multiple lines for long asks (live item's title is 13 words), making the
  collapsed list not-a-list.
  Framework: Nielsen #8 minimalism; progressive disclosure (each level should add, not repeat).
  Severity: 2.
  Class: redundant-echo-across-disclosure-levels
  Sweep query: rg -n "ib-ask-text|ib-anatomy-head" web/inbox.js
  Effort: S   Impact: M
  Required fix: collapsed row = single-line ellipsis (title in title= tooltip); expanded head keeps the full
  sentence; suppress the head when it would exactly equal the just-clicked summary text (the roadmap's own
  provenance-dedup precedent, visibleFromRequests).
  Required generalization: apply the roadmap's dedup-on-echo rule to every details/summary pair in the app.
```

### F15 — Reply stub editor is a single-line `<input>` for composing an answer

```
- Location: web/inbox.js replyBlock() — input type=text
  Defect: Answers longer than a word ("done, and please also…") edit inside a one-line box with no wrapping.
  Framework: Nielsen #7 flexibility; match the control to the content.
  Severity: 2 (v1 explicitly scopes inline answering out; but the editable stub already invites composition).
  Class: control-too-small-for-invited-content
  Sweep query: rg -n "ib-reply-stub-input" web/inbox.js web/app.css
  Effort: S   Impact: L–M
  Required fix: auto-growing <textarea rows=2>; Enter still safe (no submit wired).
  Required generalization: n/a — instance-only today (the only free-compose field in the app).
```

---

## Quick wins (ship this week) vs. structural changes (scope a project)

**Quick wins (all S effort):**
1. F8 formatAge day/week units — one function, heals every tab.
2. F7 Cockpit rename (title/h1/aria) + favicon.
3. F2 error-surface reshape (headline → scope → actions → folded detail).
4. F6 resume-command row on answerable asks (reuse quarantine pattern).
5. F1 (UI half) fenced-command rendering in inbox + Q2.
6. F9 make interrupt chips / Q2 cards navigate to #inbox/<id>.
7. F11 one label for merged-unverified; F13 scoped sidebar count; F14 dedup echo; F4(render) 'none'-title guard + collapse identical timeline runs.

**Structural (M effort, plan-worthy):**
- F5 relocate "What happened" to the Roadmap landing + rename the fourth tab "System".
- F3 Requests lifecycle verbs (Dismiss/Merge with undo-window).
- F4 capture-side: never auto-retitle with error-classified text; suppress empty amendments.
- F1 (producer half): needs-you.sh lint requires backtick-fenced commands.
- F10 Docs browser grouping + recency.
- F12 session identity: title-first rows (needs binding data in od_sessions).

## Open questions for the operator

1. **Q3 relocation vs. tab rename only:** moving "Since your last look" to the Roadmap landing is my pick (it's your every-return question), but it adds one strip to the landing you've been trimming for noise. Rename-only ("System") is the zero-motion alternative. Which?
2. **Costs pane:** does "What's it costing" earn a landing/glance position for you, or is diagnostics-tab placement genuinely where you'd look for it? I left it on the fourth tab.
3. **Requests junk:** when the capture pipeline mis-files an error as a request (F4), do you want those auto-routed to the Inbox quarantine lane (visible, blamed on the producer) or silently suppressed with a counter? I propose the quarantine lane — consistent with the "flag, never withhold" convention.
