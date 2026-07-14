# Cockpit v2 — push-materialized store (GUI reads the store, never the plan file)

Status: DRAFT
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## Why (operator directive, 2026-07-14)

> "The plan should always be considered the source of truth. But we need to make sure that plan
> file stays continuously updated as a living document. And the JSON store should simply be a
> consolidated overview of that data… as work gets done, the agent that checks off those
> checkboxes should always update the plan AND the JSON store (or a deterministic script does it
> automatically). This should be fully deterministic and always in PUSH form instead of pull so
> it's fully automated. The JSON store also has data and status from multiple plans. This
> architecture should allow the GUI to be very quick and responsive and always current because it
> only needs to reference the JSON store."

**What's built today (the gap):** the checkbox flip already PUSHES a `task_done` *event* into the
per-ask JSONL — but the GUI still **pulls** the task list + checkbox state from the plan markdown at
request time (`computePlanRows` → `countPlanTasks`, joined live with the events). So the store is
incomplete and the read path re-derives. This plan closes that: the store becomes a complete,
push-maintained projection; the GUI reads only the store.

**Architecture:** classic materialized read-model. Plan file = source of truth. A deterministic
projector, triggered by the SAME mechanism that edits the plan, writes the projection into a
consolidated multi-plan JSON store. GUI reads the store. The auditor drops to a safety-net backfill
(catch a missed push and re-project) — it is no longer on the read path. Because the projection is
pushed by the same deterministic action that mutates the plan, store and plan cannot drift.

## Tasks

- [ ] 1. [serial] **Store schema + projector.** New deterministic script
  `adapters/claude-code/scripts/plan-project.sh` — given a plan file, parse it and upsert that
  plan's projection into the consolidated store (`~/.claude/state/workstreams-store.json`, plus an
  in-repo mirror if the GUI needs it). Projection per plan: `{plan_slug, plan_doc, ask_id, status,
  tasks[{id, description, done, in_flight, evidence_link, updated_ts}], progress{done,in_flight,
  not_started,total}, last_projected_ts}`. `description` = the task's text from the plan (this is what
  makes the GUI's task list readable — operator item 3). `in_flight` is derived ONCE at projection
  time from the task_started/task_done events. Atomic write (tmp+rename). Idempotent. `--self-test`
  — Verification: mechanical
- [ ] 2. [serial] **Push triggers (the deterministic automation).** Call the projector from every
  mechanism that mutates a plan: the existing `plan-lifecycle.sh` PostToolUse splice on
  `docs/plans/*.md` (covers every checkbox flip + amendment), `start-plan.sh` (plan create), and
  `close-plan.sh` (plan close). Subshelled + `|| true` (constraint 5: never block the hook). This is
  the "push, not pull" core — a checkbox flip updates the plan AND the store in the same
  deterministic action — Verification: full
- [ ] 3. [serial] **Backfill + auditor demotion + THE AUTO-HEALING FEEDBACK LOOP.** One-time backfill:
  project every existing plan into the store. Then repoint the auditor: it no longer feeds the read
  path — it becomes the SAFETY NET.

  **SILENT HEALING IS FORBIDDEN (operator directive 2026-07-14).** A divergence between store and plan
  means *the push mechanism is broken* — some write path mutated a plan without triggering the
  projector. Healing the data while saying nothing fixes the symptom forever and never the cause. So
  every detected divergence does FOUR things:
  1. **HEAL the data** — re-project from the plan file so the GUI is never wrong for long.
  2. **CLASSIFY THE CAUSE** — not "drift happened" but *which write path bypassed the projector*:
     `git-checkout|git-pull|git-merge|external-editor|script-write|hook-not-fired|matcher-miss|
     other-machine|unknown`. Determine it from evidence (plan-file mtime vs last_projected_ts, git
     reflog, whether the hook's marker fired). An unclassifiable drift is itself reported as
     `unknown` — never swallowed.
  3. **AUTO-FILE THE FIX** — emit a cause-classified defect into the harness's existing improvement
     loop via `nl-issue.sh` (machine-wide ledger → weekly triage → build-ready backlog row). This is
     the auto-healing loop: **the system's own detected divergence becomes a queued fix to Neural Lace
     itself**, automatically, with no human noticing required.
  4. **ESCALATE ON RECURRENCE** — the same cause-class seen N times (default 3) is not noise, it is a
     real hole in the push mechanism: promote it automatically from an nl-issue to a **build-ready
     backlog row** with the evidence attached.

  Dedup so one recurring cause files one escalating item, not a hundred rows. The auditor must also
  report `heals_this_cycle` in its diagnostics so a rising heal rate is visible as a mechanism
  regression — Verification: full
- [ ] 4. [serial] **GUI reads the store only.** Repoint `server.js`'s `computePlanRows` /
  `aggregatePlanProgress` at the store; DELETE the request-time `countPlanTasks(planFile)` read. The
  `/api/asks` + `/api/ask/<id>` payloads are served from the store (fast, always current, spans all
  plans). Prove it: no plan-markdown read remains on any request path — Verification: full
- [ ] 5. [serial] **UI polish (operator items 1-4, + item 5 TBD).** (a) panes RESIZABLE and each
  independently SCROLLABLE; (b) backlog rows compact/collapsed by default, expandable — a tidy list,
  not a wall; (c) task list shows each task's DESCRIPTION (now in the store, task 1) and DROPS the
  repeated long plan-path link per row — the single "View live plan doc" button covers it; (d) REMOVE
  the Artifacts list (noise). [item 5: operator's message was cut off — fold in when supplied] —
  Verification: full

## Files to Modify/Create
- `adapters/claude-code/scripts/plan-project.sh` (new — the projector)
- `adapters/claude-code/hooks/plan-lifecycle.sh` (push trigger on plan edit)
- `adapters/claude-code/scripts/start-plan.sh`, `adapters/claude-code/scripts/close-plan.sh` (push on create/close)
- `neural-lace/workstreams-ui/server/server.js` (read the store; delete the plan-file read)
- `neural-lace/workstreams-ui/server/auditor.js` (demote to backfill/drift-reporter)
- `neural-lace/workstreams-ui/web/{app.css,asks.js,backlog.js,index.html}` (UI polish)

## Acceptance
1. Flip a checkbox in a plan → the store updates within the same action (no GUI refresh needed to
   re-derive); the GUI shows the new state on next load without reading the plan file.
2. `grep` proves no request path reads a plan `.md`.
3. The GUI's task list shows readable per-task descriptions; no repeated per-task plan link; no
   Artifacts section; panes resize + scroll; backlog rows collapse/expand.
4. Kill a push (simulate a missed hook) → the auditor's backfill detects the divergence, heals it,
   and REPORTS the drift (it must not hide a broken push).

## Acceptance Scenarios

Authored by `end-user-advocate` (mode=plan-time, 2026-07-14). The user is a solo operator running
many parallel autonomous coding sessions who needs, at a glance: **what did I ask for, what's the
plan, how far along, what needs me.** Every scenario below is written from that chair. Success
criteria are prose on purpose — the exact assertion strings are the advocate's and are NOT published
here (builders teach to the test).

Default `target_url:` `http://127.0.0.1:7733` (server.js `CTREE_PORT`, default 7733).

### checkbox-flip-reflects-in-gui — the core push: a flip lands in the GUI without a plan-file read

**Slug:** `checkbox-flip-reflects-in-gui`

**User flow:**
1. Open the cockpit and note the progress figures for an active plan (done / in-flight / not-started / total).
2. In a session, let `task-verifier` flip one unchecked task's checkbox to `[x]` in that plan's markdown.
3. Reload the cockpit (or wait one poll interval) without restarting the server.
4. Read the same plan's row and its task list.

**Success criteria (prose):** The flipped task now reads as done in the GUI and the plan's progress
counters move by exactly one (done +1, and the task leaves not-started/in-flight) — with no server
restart, no manual auditor run, and no request-time read of the plan markdown. The freshness the GUI
displays for that plan must correspond to the flip, not to an older projection. The change must be
visible within the plan's stated freshness bound (which the plan must state — see Gap G5).

**Artifacts to capture:** Screenshot of the plan row + task list after the flip; network log of the
`/api/asks` and `/api/ask/<id>` requests during the reload; console log (expect no errors).

**Edge variations:**
- Flip a task in a plan whose `ask-id:` front matter is absent/`none` — the plan must still project.
- Un-flip (`[x]` → `[ ]`, a correction): the store must follow the plan back down, not latch at done.

### no-plan-markdown-read-on-request-path — the pull path is actually deleted, not merely bypassed

**Slug:** `no-plan-markdown-read-on-request-path`

**User flow:**
1. Start the cockpit server.
2. Exercise every read surface: the landing page, `/api/asks`, and `/api/ask/<id>` for an ask with a linked plan.
3. Inspect the running server's file reads for the request duration (or prove statically that no plan-markdown read remains reachable from a request handler).

**Success criteria (prose):** No request handler reads a `docs/plans/**.md` file. `countPlanTasks`
is gone from the read path — not merely unreferenced but deleted — and no equivalent request-time
plan parse has been reintroduced under another name. Evidence must be behavioral (the server serves
correct plan rows with the plan markdown made unreadable, see the edge variation), not only a grep.

**Artifacts to capture:** Grep/static output showing the deleted call site; network log of the read
surfaces; console log.

**Edge variations:**
- Temporarily rename `docs/plans/` out of the way and hit the read surfaces: rows must still render
  from the store. If anything degrades, a plan read is still on the path.

### in-flight-task-visible-during-dispatch — "what's running right now" survives the pull→push cut

**Slug:** `in-flight-task-visible-during-dispatch`

**User flow:**
1. Open the cockpit and note that a given plan's task N is not started.
2. Dispatch a builder for task N (the path that emits a `task_started` progress-log event — `workstreams-emit.sh --on-builder-dispatch`). Do NOT edit the plan markdown.
3. Reload the cockpit / wait one poll interval.
4. Read the plan's row and task N.

**Success criteria (prose):** Task N shows as in-flight, and the plan's in-flight counter reflects it,
while the builder is still running — i.e. before any checkbox flip edits the plan file. This is the
signal the operator most needs from a cockpit while parallel sessions run; a dashboard that shows
zero in-flight work while three builders are mid-flight is worse than no dashboard. Today's pull path
derives this correctly at request time; the push architecture must not regress it. (This scenario is
expected to FAIL against the plan as currently written — the projector's only triggers are plan-file
mutations, and a builder dispatch mutates no plan file. See Gap G1.)

**Artifacts to capture:** Screenshot of the plan row while the builder is mid-flight; the store's
JSON for that plan at the same instant; console log.

**Edge variations:**
- Builder is dispatched and then the session dies without ever flipping the checkbox: the task must
  not remain in-flight forever with no signal — the operator needs to see stalled work as stalled.
- `waiting_on_operator` (the "what needs me" signal) fires with no plan edit: same trigger-coverage
  question — confirm the GUI still surfaces it.

### external-plan-edit-heals-or-declares-itself-stale — the store must never lie confidently

**Slug:** `external-plan-edit-heals-or-declares-itself-stale`

**User flow:**
1. Note a plan's progress in the cockpit.
2. Change that plan's markdown by a route that fires NO PostToolUse hook — e.g. `git pull`, `git checkout`, an orchestrator cherry-pick onto master, or an edit from an external editor. Check off two more tasks this way.
3. Reload the cockpit immediately and read the plan's row.
4. Wait for the auditor's safety-net cycle and reload again.

**Success criteria (prose):** At step 3 the GUI must not present stale numbers as current, silently.
Either it already reflects the new state, or it visibly marks that plan's data as possibly-stale /
last-projected-at-T — the cockpit already has this convention (`app.js` renders `derived <age> —
STALE`), and the store path must keep it. By step 4 the auditor must have healed the divergence AND
surfaced that a push was missed. A confidently-wrong number with no staleness affordance is the
failure mode this scenario exists to catch: the operator's whole trust in the cockpit rests on not
being lied to.

**Artifacts to capture:** Screenshots at step 3 and step 4; the store JSON before/after the auditor
cycle; the auditor's drift report output.

**Edge variations:**
- Plan edited by a builder inside a git worktree (the hook fires there): confirm the projection lands
  in the store the GUI actually reads, not a worktree-local copy.
- Plan file edited on another machine and synced: the GUI must degrade honestly, not invent progress.

### store-missing-degrades-honestly — deleted store shows "unknown", never a plausible zero

**Slug:** `store-missing-degrades-honestly`

**User flow:**
1. With the cockpit running and showing several plans, delete the store JSON.
2. Reload the cockpit landing page.
3. Open an ask detail view for an ask with a linked plan.

**Success criteria (prose):** The GUI stays up (no 500, no blank page) and states plainly that plan
state is unavailable/unknown for the affected plans. It must NOT render `0/0 tasks` or `0% complete`
or an empty task list — a zero that is indistinguishable from a real, legitimately-empty plan is a
confident lie, and it is exactly the shape a materialized read-model fails in. "Unknown" and "zero"
must be visually distinct to the operator. The store must then be rebuildable (auditor backfill or
one command) and the GUI must recover without a server restart.

**Artifacts to capture:** Screenshot of the missing-store state; network log of `/api/asks` (expect a
2xx with an honest payload, not a 500); console log.

### store-corrupt-degrades-honestly — truncated/garbage store does not take the cockpit down or invent data

**Slug:** `store-corrupt-degrades-honestly`

**User flow:**
1. Truncate the store JSON mid-object (simulating a crash during write) and reload the cockpit.
2. Restore, then corrupt a SINGLE plan's projection (garbage `tasks` value, a `progress` that disagrees with `tasks`) and reload.
3. Restore, then hand-write a projection whose `progress` counters disagree with its own `tasks[]` array, and reload.

**Success criteria (prose):** A wholly-unparseable store degrades exactly as the missing-store case
(honest unknown, no 500). A single bad plan entry must not poison the other plans — the rest still
render, and the bad one shows as unknown/damaged. Where the store carries both `tasks[]` and derived
`progress{}` counters, the GUI must not display counters that contradict the task rows it is showing
next to them; the internal disagreement must be detected and surfaced, not rendered. The auditor must
flag all three as drift.

**Artifacts to capture:** Screenshots of each of the three states; console log; the auditor's drift report.

### concurrent-flips-lose-no-plan — many parallel sessions is the operator's normal mode, not an edge case

**Slug:** `concurrent-flips-lose-no-plan`

**User flow:**
1. Ensure the store holds projections for at least three plans, A, B and C.
2. Trigger the projector for plan A and plan B at the same instant (two concurrent plan-file edits, as two parallel sessions genuinely produce), each flipping a different task.
3. Reload the cockpit and read all three plans' rows.
4. Repeat under load: fire ~10 concurrent projector invocations across different plans.

**Success criteria (prose):** After concurrent pushes, the store still contains ALL plans, and both
A's and B's flips are present. No plan's projection is lost, truncated, or reverted by a racing
writer. `tmp+rename` makes each individual write atomic but does not make a read-modify-write of a
single consolidated file atomic — two concurrent projectors that each read the whole store, edit
their own slice, and rename over it will silently drop one of the two updates (last writer wins).
The operator runs many parallel sessions by design, so this is a routine path, not a stress test. If
the store survives 10 concurrent writers with zero lost updates, the design is sound; if it drops
even one, the GUI is silently missing a plan's progress until the next auditor cycle.

**Artifacts to capture:** The store JSON after the concurrent burst; a diff against the expected
projection set; console/auditor log showing whether the loss was even detected.

### plan-edit-does-not-slow-the-session — the projector is on the session hot path

**Slug:** `plan-edit-does-not-slow-the-session`

**User flow:**
1. Measure the current wall-clock cost of the `plan-lifecycle.sh` PostToolUse hook on a single plan-file edit (baseline, before this plan's changes).
2. With the projector spliced in, measure the same edit again, with a store holding a realistic plan count (this repo has 237 plan files today, incl. archive).
3. Repeat for the edit shapes agents actually make: a checkbox flip, an Evidence-Log append, a several-line amendment — plan files are edited many times per session.
4. Force projector failure modes (store unreadable, store locked by another writer, malformed plan) and re-run the edit.

**Success criteria (prose):** The added per-edit cost stays within the plan's stated hot-path budget
(which the plan must state — see Gap G5) and does not grow with the number of plans in the store: the
projector re-projects ONE plan, and must not fork per plan or per file. A prior unbounded fork-per-file
scan was a confirmed MAJOR latency defect on this exact surface (Windows Git-Bash, expensive spawns),
so the acceptance bar is a measured number, not "feels fine." Under every forced failure mode the hook
must still exit 0, never hang, and never propagate an error into the host session (constraint 5) — the
operator's session must be unharmed by a broken projector, and the projector must never mutate the plan
(constraint 6). The user-visible trade here is explicit: this plan makes the GUI fast by moving cost
onto every session's edit path, and that cost must be proven small.

**Artifacts to capture:** Timing table (baseline vs. spliced, per edit shape, with plan count);
process-spawn count per edit; the hook's exit code under each forced failure.

### backfill-does-not-melt-the-machine — 237 plans through the safety net

**Slug:** `backfill-does-not-melt-the-machine`

**User flow:**
1. Run the one-time backfill (Task 3) against the real repo's full plan set (237 files today).
2. Time it; count process spawns.
3. Let the auditor's periodic safety-net cycle run with the full store and time one cycle.
4. Run the backfill twice and diff the store.

**Success criteria (prose):** The backfill completes within a stated bound, and the periodic auditor
cycle's cost is bounded and does not scale as fork-per-plan-per-cycle. A safety net that re-parses
237 plan files every cycle with a process spawn each is the fork-per-file defect wearing a new hat.
Running the backfill twice must produce a byte-identical store (idempotence), and must not clobber
in-flight/evidence data that only the event stream knows.

**Artifacts to capture:** Backfill wall time + spawn count; one auditor cycle's wall time; diff of the
store across two backfill runs (expect empty).

### drift-is-reported-where-the-operator-looks — a missed push is a bug, and the operator must see it

**Slug:** `drift-is-reported-where-the-operator-looks`

**User flow:**
1. Simulate a missed push: change a plan's checkboxes while the projector is disabled, so the store now disagrees with the plan.
2. Reload the cockpit and observe what the operator sees BEFORE the auditor runs.
3. Let the auditor's safety-net cycle run.
4. Reload the cockpit again and look for the drift signal, as the operator, without reading any log file.

**Success criteria (prose):** The auditor detects the divergence, heals the store, and the fact that a
push was missed reaches a surface the operator actually looks at — the cockpit — not only stderr or a
log file no one opens. Silent self-healing is a trap: it converts a broken push (a real bug in the
push architecture this plan's whole premise rests on) into an invisible one, so the store looks
trustworthy precisely when it isn't. The existing per-task drift badges must survive the cut to the
store: after Task 4 deletes the plan-markdown read, task rows must still carry their drift badges
(they come from the auditor today, and the Task 1 store schema does not carry them — see Gap G6).

**Artifacts to capture:** Screenshot of the cockpit showing the drift signal; the auditor's report
output; the store before/after the heal.

### long-multiline-descriptions-stay-scannable — real plan tasks are 4-8 lines of markdown, not one-liners

**Slug:** `long-multiline-descriptions-stay-scannable`

**User flow:**
1. Project a plan whose tasks are real ones — e.g. this very plan, whose five tasks each span 4-8 wrapped lines and contain backticks, quotes, `[serial]` prefixes, embedded file paths, parentheses, and a trailing `— Verification: full` suffix.
2. Open the cockpit and read that plan's task list.
3. Also project a plan containing a task with a double quote, a backslash, a literal `"` inside backticks, and a non-ASCII character; reload.
4. View the task list at a narrow window width and with several plans expanded at once.

**Success criteria (prose):** Each task is identifiable at a glance — the operator can tell WHAT task
3 is without opening the plan — while the list stays a tidy, scannable list rather than a wall of
prose. These two goals are in tension and the plan does not resolve it (Gap G7): showing the full
multi-line description of every task directly contradicts Task 5(b)'s "a tidy list, not a wall." A
truncation/summary rule must exist and be visible in the result (e.g. the task's leading bolded title,
or a clamped single line with expand-on-click), and the tags the description carries (`[serial]`,
`— Verification: full`) must be handled deliberately, not dumped raw. Special characters must round-trip
through the store without corrupting it — a bash-authored projector that naively concatenates JSON will
produce an unparseable store the first time a task description contains a quote, which lands the
operator straight in the store-corrupt scenario above.

**Artifacts to capture:** Screenshot of the task list for a real multi-line-task plan; the store JSON
for that plan (must parse); screenshot at narrow width; console log.

### new-plan-appears-in-cockpit — start-plan.sh pushes, the operator sees the ask take shape

**Slug:** `new-plan-appears-in-cockpit`

**User flow:**
1. With the cockpit open, create a new plan via `start-plan.sh`.
2. Reload / wait one poll interval.
3. Find the new plan in the cockpit and read its task list and progress.

**Success criteria (prose):** The new plan appears without a server restart, with its tasks and
descriptions, at 0 done. A plan created but not yet linked to an ask must still be discoverable rather
than invisible — the operator's question "what's the plan" must be answerable for a plan the moment it
exists.

**Artifacts to capture:** Screenshot of the cockpit showing the new plan; store JSON entry; console log.

### closed-plan-leaves-the-active-view — the consolidated store must not become a graveyard

**Slug:** `closed-plan-leaves-the-active-view`

**User flow:**
1. Close a plan via `close-plan.sh` (Status → COMPLETED; `plan-lifecycle.sh` moves the file to `docs/plans/archive/`).
2. Reload the cockpit.
3. Look at the active view, and then look for the closed plan.

**Success criteria (prose):** The closed plan leaves the operator's at-a-glance active view (it must
not sit there at 100% forever, crowding the signal) and its projection is either removed from the store
or explicitly marked terminal/archived — the plan never says which, and with 237 plan files on disk the
difference between "the store holds active plans" and "the store holds everything ever" decides whether
the cockpit stays scannable. The archival file MOVE must not leave a stale projection pointing at a path
that no longer exists, and must not be re-created by the auditor's backfill on the next cycle.

**Artifacts to capture:** Screenshot of the active view after close; store JSON entry for the closed
plan; screenshot after one auditor cycle (confirm it does not resurrect).

### fifty-plus-plans-stay-fast — the whole point of the architecture, measured

**Slug:** `fifty-plus-plans-stay-fast`

**User flow:**
1. Load the store with 50+ plans (this repo already has 237 plan files — use real ones).
2. Cold-load the cockpit landing page and time to first meaningful render.
3. Time `/api/asks` and `/api/ask/<id>` server-side.
4. Scroll/expand several plans' task lists and interact.

**Success criteria (prose):** The landing page and both API endpoints stay within the plan's stated
latency budget (which the plan must state — see Gap G5) at 50+ plans, and the payload does not balloon:
shipping every task's full description for every plan to the browser on the landing page is a size
problem the plan has not costed. "Fast and responsive" is the operator directive's central promise and
is currently unfalsifiable in the Acceptance section — this scenario is the number that makes it real.
Interaction (expand, scroll, resize) must stay smooth at that plan count.

**Artifacts to capture:** Server-side timings for both endpoints at 50+ plans; landing-page payload
size in bytes; screenshot of the populated cockpit; console log.

### panes-resize-and-scroll-independently — operator item 1

**Slug:** `panes-resize-and-scroll-independently`

**User flow:**
1. Open the cockpit.
2. Drag the divider between panes to resize.
3. Scroll one pane to its bottom; observe the other pane.
4. Reload the page.

**Success criteria (prose):** Panes are resizable by drag and each scrolls independently — scrolling
one does not move the other, and neither scrolls the whole page. Resizing does not clip or hide content
in either pane. Whether pane sizes persist across reload is a deliberate choice the plan should state;
losing them every reload is a papercut the operator hits dozens of times a day.

**Artifacts to capture:** Screenshots before/after resize and at scroll-bottom; console log.

### backlog-rows-collapse-and-expand — operator item 2

**Slug:** `backlog-rows-collapse-and-expand`

**User flow:**
1. Open the cockpit's backlog pane with a realistic number of backlog rows.
2. Observe the default state.
3. Expand one row, read it, collapse it again.
4. Reload.

**Success criteria (prose):** Backlog rows are compact/collapsed by default — the pane reads as a tidy
list, not a wall of text — and any row expands to full detail on click and collapses again. The
collapsed row must still carry enough to decide whether to expand it. Expanding one row must not expand
or reflow the others.

**Artifacts to capture:** Screenshot of the default collapsed pane; screenshot with one row expanded;
console log.

### task-list-shows-descriptions-without-repeated-links — operator item 3

**Slug:** `task-list-shows-descriptions-without-repeated-links`

**User flow:**
1. Open an ask with a linked plan.
2. Read the task list.
3. Look for per-task plan-path links.
4. Click the single "View live plan doc" control.

**Success criteria (prose):** Each task row shows its description (so the operator can tell what the
task IS without leaving the cockpit); the long plan path is NOT repeated on every row; and the single
"View live plan doc" control opens the live plan through the existing doc resolver. Removing the
per-row link must not remove the operator's ability to reach the plan — the one button must actually
work, not just exist.

**Artifacts to capture:** Screenshot of the task list; screenshot after clicking "View live plan doc";
network log of the doc-open request.

### artifacts-section-removed — operator item 4

**Slug:** `artifacts-section-removed`

**User flow:**
1. Open an ask detail view that previously rendered an Artifacts list.
2. Look for the Artifacts section.
3. Confirm nothing else in the view broke where it used to sit.

**Success criteria (prose):** The Artifacts list is gone from the UI. Nothing the operator still needs
was only reachable through it (if anything was, it must have a new home) — and its removal leaves no
empty container, stray heading, or layout hole behind.

**Artifacts to capture:** Screenshot of the ask detail view; console log.

## Out-of-scope scenarios

- **Real-time push to the browser (SSE/WebSocket) so the cockpit updates with no reload** — the plan's
  promise is "always current"; the current GUI polls. Whether a poll interval satisfies "always
  current" is a scope call for the planner. Excluded here because the plan neither claims nor rules out
  a browser-push path; scenarios above accept "within one poll interval" IF the plan states that bound.
- **Multi-machine / synced store** — the store lives at `~/.claude/state/`, machine-local. Cross-machine
  currency is not in this plan's Scope.
- **Auth / access control on the cockpit** — server binds 127.0.0.1 only; out of scope.
- **Task 5's "item 5"** — the operator's message was cut off and the item is literally unknown, so no
  scenario can be authored for it. It must not be silently accepted as delivered (see Gap G8).
- **Migrating the historical event JSONLs into the store** — the plan projects from plan files, not from
  event history; replaying history is not claimed.

## Plan-Time Advocate Feedback

Reviewer: `end-user-advocate` (mode=plan-time) · 2026-07-14 · first review.

**Verdict: FAIL** — 5 Critical gaps. The plan's Acceptance section proves component greens (a grep, a
store write, an auditor heal) but does not prove the user-visible promise: *a fast, always-current
cockpit.* Two of the gaps are user-visible regressions, not just missing tests.

### Critical

- Line(s): Task 1 ("`in_flight` is derived ONCE at projection time from the task_started/task_done
  events") + Task 2 (trigger list: `plan-lifecycle.sh` PostToolUse on `docs/plans/*.md`, `start-plan.sh`,
  `close-plan.sh`).
  Defect: The projector's TRIGGERS are all plan-file mutations, but the projection's INPUTS include
  event streams that change with no plan-file mutation. `task_started` is emitted by
  `hooks/workstreams-emit.sh` on `--on-builder-dispatch` — a builder dispatch edits no plan file, so the
  projector never runs, so `in_flight` is never re-derived. Net effect: the operator dispatches three
  builders and the cockpit shows **zero in-flight work** until a checkbox flips — at which point the
  task goes straight from not-started to done. The in-flight state, the single most valuable signal for
  an operator running many parallel sessions, becomes permanently invisible. Today's pull path derives
  it correctly at request time; this plan regresses it. `waiting_on_operator` ("what needs me"),
  `merged`, and the ask-registry's `plan_linked` records are the same shape.
  Class: trigger-coverage-gap (a pushed projection whose trigger set is narrower than its input set —
  every input writer must be a trigger, or that field must not live in the pushed projection).
  Sweep query: `rg -n "pl_emit|progress-log\.sh emit|--type (task_started|task_done|waiting_on_operator|merged|plan_amended|plan_completed|ask_registered|session_attached)" adapters/claude-code/`
  Required fix: Either (a) splice the projector into EVERY emitter of a projection input — starting with
  `workstreams-emit.sh`'s `task_started` splice — or (b) keep event-derived fields (`in_flight`,
  `evidence_link`) out of the pushed projection and have the GUI join them from the events at read time,
  and drop the claim that the store is complete. State which, in the plan.
  Required generalization: For every field in the Task 1 schema, name its writer(s) and prove each writer
  is a projector trigger. Enumerate the emitters via the sweep query and add a table to the plan mapping
  field → writer → trigger. Any field whose writer is not a trigger is stale-by-construction.

- Line(s): `## Why` ("always current", "very quick and responsive"), Task 2, `## Acceptance` #1.
  Defect: "Always current" is asserted with no mechanism for the mutation paths that don't fire a
  PostToolUse hook — `git pull`, `git checkout`, an orchestrator cherry-pick onto master, an external
  editor, a merge. On those paths the store silently serves stale numbers with no bound on how long, and
  no staleness affordance. The plan states no freshness bound anywhere (how long may the store lie?) and
  no auditor cadence, so "always current" is a claim without a mechanism (constitution §1).
  Class: unfalsifiable-freshness-claim (a currency promise with no stated staleness bound and no
  degraded/unknown display state).
  Sweep query: `rg -n -i "always current|current|fresh|real-?time|instant|responsive|quick|fast" docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: State the max staleness bound (e.g. "≤ auditor period, and the auditor runs every N s"),
  state the auditor's cadence, and require the GUI to display per-plan `last_projected_ts` with a stale
  affordance — the cockpit ALREADY has this convention (`web/app.js` renders `derived <age> — STALE`);
  the store path must keep it rather than regress to confident silence.
  Required generalization: Every currency/speed word the sweep surfaces must be rewritten as a bound the
  advocate can falsify ("the GUI reflects a plan-file change within X s of it landing, or marks that plan
  stale"), or deleted.

- Line(s): Task 4 ("GUI reads the store only… DELETE the request-time `countPlanTasks`"), `## Acceptance`
  (no entry).
  Defect: The plan never says what the GUI shows when the store is missing, unreadable, truncated, or
  missing the plan being viewed. The obvious default — a projection that isn't there yields
  `progress{done:0,total:0}` — renders as `0/0`, `0%`, empty task list: **indistinguishable from a real
  plan with no work done.** That is a confident lie in the operator's primary trust surface, and it is
  the classic failure mode of a materialized read-model. Today's pull path returns `null` and renders an
  honest "no plan file found" row; deleting it without specifying the replacement loses that honesty.
  Class: missing-degradation-semantics (a read-model with no defined unknown/unavailable state, so
  absence renders as zero).
  Sweep query: `rg -n "progress\{|done:|total:|tasks\[\]|countPlanTasks|planTasks" neural-lace/workstreams-ui/server/server.js`
  Required fix: Define three distinct display states in the plan — `known` (projection present),
  `unknown` (no projection / unreadable store), `damaged` (projection present but self-inconsistent) —
  and require `unknown` and `damaged` to be visually distinct from a legitimate zero. Server must not 500
  on a corrupt store; one bad plan entry must not poison the others.
  Required generalization: Every field the GUI reads from the store needs a defined
  absent/malformed rendering. Audit the Task 1 schema field-by-field and state the fallback for each.

- Line(s): Task 1 ("Atomic write (tmp+rename). Idempotent.").
  Defect: `tmp+rename` makes each individual write atomic; it does NOT make a read-modify-write of a
  single consolidated multi-plan file atomic. Two parallel sessions each flipping a checkbox will each
  read the whole store, edit their own slice, and rename over the other — **last writer wins, one plan's
  update is silently lost.** The operator's stated normal mode is *many parallel autonomous sessions*,
  so this is a routine path, not a stress case. The lost update persists until the auditor's next cycle,
  and (per the gap above) the auditor's cadence is unstated.
  Class: lost-update-under-concurrency (concurrent read-modify-write of one shared file, mistaken for
  safe because the final write is atomic).
  Sweep query: `rg -n "tmp\+rename|mktemp|mv -f|rename|flock|lockfile|\.tmp" adapters/claude-code/scripts/ adapters/claude-code/hooks/lib/`
  Required fix: Specify the concurrency control in Task 1 — either a lock around read-modify-write
  (`flock`, with a bounded timeout so constraint 5 still holds: never hang the host hook), or per-plan
  shard files (`store/<plan-slug>.json`) that the GUI or a consolidator merges, making each writer's
  write genuinely independent. Per-plan shards also remove the whole-store rewrite from the hot path.
  Required generalization: Any state file written by the session hot path from multiple parallel sessions
  needs the same treatment; check the other writers the sweep surfaces (progress-log JSONL is per-ask and
  append-only, which is why it is safe — the consolidated store is not).

- Line(s): `## Acceptance` #1-#4 (whole section).
  Defect: Not one acceptance criterion carries a number, so none can be falsified. "Updates within the
  same action", "fast", "always current", "quick and responsive", "readable descriptions" — a build can
  satisfy every word of the Acceptance section while the cockpit is slower than before (the projector was
  added to every plan edit on the session hot path) and less current than before (in-flight is gone).
  #2 (a grep) is the only falsifiable one, and it proves an implementation detail, not a user outcome.
  There is no criterion for the two costs this architecture actually incurs: added latency on every
  session's plan edit, and the backfill/auditor cost across 237 plan files (a prior unbounded
  fork-per-file scan on this exact surface was a confirmed MAJOR latency defect).
  Class: component-green-acceptance (criteria assert that pieces exist/ran, not that the user's outcome
  holds, and carry no measurable bound).
  Sweep query: `rg -n -i "fast|quick|responsive|readable|tidy|current|updates|works|correct" docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: Give the Acceptance section numbers: (i) hot-path budget — added wall-clock per plan edit
  ≤ X ms p95 on Windows Git-Bash, with a fixed process-spawn count independent of plan count; (ii) GUI
  budget — landing page + `/api/asks` + `/api/ask/<id>` ≤ Y ms at 50+ plans; (iii) freshness bound — a
  plan-file change is reflected within Z s or the plan is marked stale; (iv) backfill bound across the
  real 237-file plan set.
  Required generalization: Every adjective the sweep surfaces becomes a number with a measurement method,
  or is struck. The `## Acceptance Scenarios` section above is the user-outcome half; these budgets are
  the numbers those scenarios assert against.

### Important

- Line(s): Task 1 (projection schema) vs. `server.js:853-864` (`auditor.getBadgesForAsk` → per-row
  `drift_badges`) and `server.js:845` (`evidence_link` from the `task_done` event).
  Defect: The Task 1 schema carries `evidence_link` but NOT `drift_badges`, while Task 4 deletes the read
  path that currently assembles both. Two shipped, user-visible features (per-task drift badges; evidence
  links) are silently dropped or left undefined by the cut. Task 3 also says the auditor "REPORTS the
  drift" without naming the surface — a report to stderr or a log file is invisible to the operator, and
  silent self-healing turns a broken push into an invisible one.
  Class: read-model-schema-omission (fields the current read path assembles that the new store schema does
  not carry — the cut drops them silently).
  Sweep query: `rg -n "plan_slug:|tasks:|drift_badges|evidence_link|in_flight|plan_doc|getBadgesForAsk" neural-lace/workstreams-ui/server/server.js neural-lace/workstreams-ui/server/payload-schema.js`
  Required fix: Diff the current `computePlanRows` output shape against the Task 1 schema field-by-field
  and either carry every field into the store or state explicitly which are being dropped and why. Name
  the surface the drift report lands on (the cockpit, per the scenario above).
  Required generalization: Any field in the existing payload shape that the store does not carry is a
  regression until the plan says otherwise — enumerate them all, not just drift_badges.

- Line(s): Task 1 ("`description` = the task's text from the plan") + Task 5(b) ("a tidy list, not a
  wall") + Task 5(c) ("task list shows each task's DESCRIPTION").
  Defect: Real task lines in this repo are multi-line markdown (this plan's own five tasks span 4-8
  wrapped lines each and contain backticks, quotes, `[serial]` prefixes and `— Verification: full`
  suffixes). "The task's text from the plan" defines no grammar: continuation lines? tag stripping?
  truncation? Rendering full descriptions for every task directly contradicts 5(b)'s "tidy list, not a
  wall." Separately, a bash projector that concatenates such text into JSON without escaping quotes,
  backslashes and newlines will produce an unparseable store the first time a description contains a `"`
  — which lands the operator straight in the undefined store-corrupt state above.
  Class: undefined-field-grammar (a projected field defined by prose, not a parse+escape+render rule).
  Sweep query: `rg -n "^- \[[ xX]\] [0-9]" docs/plans/*.md | rg '["\\`]'`
  Required fix: Specify the description rule (e.g. leading bolded title, or first sentence, clamped to N
  chars with expand-on-click), state whether `[serial]` / `— Verification:` tags are stripped or shown as
  chips, and mandate real JSON encoding (a JSON tool, not string concatenation) with a round-trip test on
  a description containing `"`, `\`, a newline and a non-ASCII char.
  Required generalization: Every string field the projector writes needs the same escape + truncation
  discipline — `plan_doc`, `ask_id`, `status` and `evidence_link` all originate in plan text too.

- Line(s): Task 5 ("[item 5: operator's message was cut off — fold in when supplied]").
  Defect: An in-scope task contains a scope item that is literally unknown. Task 5 cannot be verified as
  complete while part of it is undefined, and there is a real risk it gets checked off with item 5 quietly
  unaddressed.
  Class: unknown-scope-inside-an-in-scope-task.
  Sweep query: `rg -n "TBD|cut off|when supplied|\[item|TODO|\?\?\?" docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: Split item 5 into its own task (or a follow-up plan) and scope Task 5 to items (a)-(d)
  explicitly, so the checkbox means something. Ask the operator for item 5 — it is one question.
  Required generalization: No task may carry an unspecified sub-item; sweep the plan for placeholders.

- Line(s): Task 1 ("`~/.claude/state/workstreams-store.json`, plus an in-repo mirror if the GUI needs it").
  Defect: An unresolved either/or inside the deliverable. Which file does the GUI read? If both exist,
  there are two stores and they will drift — the exact failure this plan exists to eliminate. Also
  unstated: what happens when a projector running inside a git WORKTREE (the orchestrator's normal build
  mode) pushes — does it write the machine-global store the GUI reads, or a worktree-local copy?
  Class: ambiguous-single-source-of-truth (two candidate store locations, no decision).
  Sweep query: `rg -n "workstreams-store|state/|mirror|in-repo" docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: Pick ONE store path, state it, and state that worktree-spawned projectors write to that
  same machine-global path. If a mirror is genuinely needed, name it as a derived artifact with a stated
  direction of flow.
  Required generalization: n/a beyond this decision — but the same question applies to the shard layout if
  the concurrency fix adopts per-plan shards.

- Line(s): Task 3 (backfill) + Task 2 (`close-plan.sh` trigger); `## Files to Modify/Create`.
  Defect: The lifecycle of a projection is never defined: when a plan is archived (the PostToolUse hook
  MOVES the file to `docs/plans/archive/`), is its entry removed, marked terminal, or left pointing at a
  now-nonexistent path? With 237 plan files on disk, "the store holds everything ever" versus "the store
  holds active plans" decides whether the cockpit stays scannable. The backfill must also not resurrect
  entries it just removed.
  Class: missing-projection-lifecycle (create/update specified; delete/archive not).
  Sweep query: `rg -n "archive|deferred|COMPLETED|terminal|close-plan" adapters/claude-code/hooks/plan-lifecycle.sh`
  Required fix: State the archive/delete semantics in Task 2/3, and state what the GUI's default view
  shows (active only, presumably) versus what the store retains.
  Required generalization: Every store-mutating trigger (create / edit / close / archive / defer / delete)
  needs its projection effect named — enumerate all six.

- Line(s): Whole file (82 lines, `rung: 3`).
  Defect: The plan has no `## Goal`, no `## Scope` (IN/OUT), and no `## Edge Cases` section. Without Scope
  I cannot tell what is deliberately excluded (so every gap above is arguably in scope), and the absence
  of an Edge Cases section is precisely why the failure modes in the Critical list are all unaddressed.
  Class: missing-plan-sections (template sections omitted, so the review surface the sections exist to
  create never happened).
  Sweep query: `rg -n "^## " docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: Add `## Goal` (the user-observable outcome, in a sentence with a number), `## Scope` with
  IN/OUT clauses, and `## Edge Cases` populated from the Critical gaps above.
  Required generalization: n/a — structural.

### Nice-to-have

- Line(s): Front matter, line 7 (`ask-id: <id | none — no linked ask>`).
  Defect: The literal template placeholder is still there. If the projector reads `ask_id` from front
  matter (Task 1's schema has an `ask_id` field), this very plan would project `ask_id: "<id | none — no
  linked ask>"` into the store — a nice demonstration that the projector must validate/normalize its
  inputs rather than trusting plan text.
  Class: instance-only (one unfilled placeholder) — though it doubles as evidence for the input-validation
  point in the undefined-field-grammar gap above.
  Sweep query: `rg -n "^(ask-id|prd-ref|rung|lifecycle-schema):" docs/plans/cockpit-v2-push-materialized-store.md`
  Required fix: Fill in `ask-id`, and have the projector treat an unparseable/placeholder `ask-id` as
  absent rather than projecting the literal string.
  Required generalization: n/a — instance-only.
