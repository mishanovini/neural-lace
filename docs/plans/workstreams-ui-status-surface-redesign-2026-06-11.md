# Plan: Workstreams UI — Shared Status Surface Redesign
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Re-conceive the Workstreams GUI from a *structure-first* tool (a tree of how AI work
decomposed) into a **shared status surface** whose primary job is to let the operator AND
the AI orchestrator hold one reconciled picture of **everything in work, at every lifecycle
stage** — what we're still thinking about, what's queued, what's actively moving, what's
blocked/waiting on the operator, and what's complete.

Two corrections from the design conversation are load-bearing and drive this plan:
1. **It is a status surface for the whole pipeline, not a decision queue.** "Waiting on the
   operator" is ONE state among several (thinking → queued → moving → blocked → done →
   closed), not the purpose. The surface must answer "what is the status of everything?" at a
   glance for both parties.
2. **Every item presented to the operator must be context-complete** — enough embedded
   context to act/decide WITHOUT remembering past conversation. This is a hard requirement
   (the tool is useless without it) and is primarily an emit-discipline + gate problem, not
   only a render problem.

The event-sourced data substrate (the append-only log, the reducer, attestation, cross-machine
sync) is sound and is KEPT. This plan re-conceives the *presentation* and adds an
operator-authoring path + the context-completeness discipline; it does not rebuild the backend.

## User-facing Outcome

On one surface, the operator can:
- See the **status of everything** across all projects at a glance — counts per lifecycle
  stage per project (the cockpit), with no view that overflows regardless of item volume.
- Drill into any project and see its work as a **color-coded tree** (color = status, icon =
  kind, amber = needs-you) bounded to that project so it stays readable.
- See, in one bounded list, **everything currently waiting on them**, each item carrying full
  context.
- Maintain a **personal task list** (create/edit/reorder/complete/delete) independent of what
  the AI emits, and a separate **backlog** (the "eventually" bucket) with promote-to-task.
- Open any item and get a **context-complete card** (background · options-with-meaning ·
  recommendation · how-to-reply) — never a contextless choice.

And the AI orchestrator reads/writes the same model, so both parties always share the frame.

## Scope

- IN:
  - The five surfaces: project **cockpit** (status counts), global **waiting-on-you** list,
    per-project **tree** (color-coded), editable **my-tasks**, editable **backlog**.
  - **Lifecycle-state normalization** across items (proposed/committed/in-flight/blocked/
    done/closed) surfaced consistently in counts, tree color, and filters.
  - **Operator-authoring path**: GUI write endpoints + additive events so the operator can
    add/edit/reorder/complete/delete tasks and backlog items, and promote backlog→task.
  - **Context-completeness**: per-kind required-field templates on item `details`; the
    context-card render (progressive disclosure); the "context incomplete" flag/gate; the
    emit-side discipline so the AI authors context when it raises an item.
  - Color/IA discipline: color encodes status, icon encodes kind, amber = needs-you only.
  - Accessibility baseline carried over from the prior review: focusable disclosure twists
    (`aria-expanded`), aria-labels on icon-only controls, one coordinated overlay-dismiss.
  - Visual/responsive verification at ~1280 / 768 / 390 px against live data.
  - Rename leftover copy "Conversation Tree" → "Workstreams" in user-facing strings.
- OUT:
  - Rebuilding the event-sourced backend / reducer / attestation / cross-machine sync.
  - Backfilling `details` for existing items (fix-forward only; the source docs are not on
    the machine and fabrication is barred — see the discovery's UX-3 disposition).
  - Re-deriving the ADR-032 schema major (all new events are additive within major 1).
  - Any change to the orchestrator/Dispatch coordination model beyond emitting richer item
    `details`.

## Design (consolidated — the converged decisions)

### The spine: lifecycle states
Every item has a normalized state: `proposed` (thinking) → `committed` (queued/next) →
`in-flight` (moving/now) → `blocked` (incl. blocked-on-operator = "waiting on you") → `done`
→ `closed`. Counts, tree color, cockpit columns, and filters are all derived from this single
state field. This is what makes the surface answer "status of everything," not just "what's
waiting."

### Surface 1 — Project cockpit (the global, density-resilient overview)
One compact row per project, each showing **status COUNTS** (now / next / waiting / done) as
fixed-size pills — O(projects), never O(items), so lopsided volumes never overflow. The
waiting count is accented when > 0 (the bottleneck signal). Click a row → drill into that
project's tree.

### Surface 2 — Waiting on you (the bounded global item list)
The only place items render globally; naturally small (only items in `blocked-on-operator`,
plus unanswered decisions/questions). Each row is a context-complete summary.

### Surface 3 — Per-project tree (the drill-down)
Bounded to one project so it stays readable. Indentation + guide lines + real focusable
disclosure twists. **Color = status** (neutral gray = structure/idle; amber = needs-you /
blocked, the only thing that pops; muted green check = done), **icon = kind** (action /
decision / question). Branch rows carry an open-count badge + an amber dot if anything inside
needs the operator. Done/archived collapsed by default ("show done" toggle). Two color ramps
(gray + amber) + green-for-done semantic; no rainbow.

### Surface 4 — My tasks (operator-owned, editable)
The operator's entire hand-authored list in one place. Always-present "+ add" input; inline
edit (text / project / state / priority / done / delete); drag-reorder. Items are first-class
in the same model (origin = operator) so they also appear in cockpit counts and the relevant
project tree — but this is the authoring surface; the AI reads it, the operator owns it.

### Surface 5 — Backlog (operator-owned, editable)
Same editing pattern for the "eventually" bucket; add / edit / priority / delete + a
**promote-to-task** action (backlog → committed/next).

### Context-completeness (the hard requirement)
- **What context per kind** (required fields on `details`): decision = what's decided ·
  why-now · each option's MEANING & tradeoff · recommendation · reply-with; question = the
  question · why-it-matters / what's-blocked · answer-shape · reply-with; action-for-operator
  = what · why · how-to-resolve. The bar is the **cold-read test**: could the operator decide
  reading only this card with zero memory of the chat?
- **Gate**: an item of kind decision/question/action-for-operator missing required fields is
  flagged `context-incomplete` and is NOT presented as actionable (it shows as "needs
  enrichment"), so a contextless choice can never reach the operator.
- **How presented (clean+concise)**: progressive disclosure — essentials inline (1–2 sentence
  background, one line per option, the recommendation, reply buttons); full reasoning/links
  behind a "more context" expand; labeled sections so the operator scans, not reads.
- **Emit discipline**: the AI authors the context payload when it raises an item (maps onto
  the existing `decision-context.md` fence grammar). This is the upstream half of the fix —
  no render can show context that was never written.

## Tasks

- [x] 1. Data-model deltas: add `origin` (operator|ai) + normalized `state` handling + the
  per-kind `details` context shape to the schema/reducer (additive within major 1); add a
  `task-added` / `task-edited` / `task-removed` / `item-promoted` event family for the
  operator-authoring path; extend `state/selftest.js`. — Verification: contract
- [x] 2. GUI server write endpoints: `POST /api/event` (validated, appends via the
  sole-normative state library) for add/edit/remove/promote/mark-done/defer; reject malformed
  payloads; never bypass the facade. — Verification: full
- [x] 3. Cockpit view: per-project status-count rows (fixed density) computed from the reduced
  state; waiting-count accent; click → project drill. — Verification: full
  **Prove it works:** 1. open the GUI; 2. see one row per project with now/next/waiting/done
  counts; 3. counts match the reduced state; 4. a project with dozens of items shows a number,
  not overflowing chips.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/state/reducer.js` → `neural-lace/workstreams-ui/server/server.js`
  **Integration points:** reads the live `tree-state.json` via the reducer; `curl localhost:<port>/` returns the cockpit DOM.
- [x] 4. Waiting-on-you global list: bounded filter (blocked-on-operator + unanswered
  decisions/questions); context-complete summary rows. — Verification: full
  **Prove it works:** 1. open the GUI; 2. the waiting list shows only items needing the
  operator; 3. each row shows background + recommendation inline.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/state/reducer.js`
  **Integration points:** derives from item `state`/`kind`; n/a external.
- [x] 5. Per-project tree: color=status / icon=kind / amber needs-you dot + open-count badges;
  focusable twists (`aria-expanded`); collapse-done default + "show done". — Verification: full
  **Prove it works:** 1. click a project in the cockpit; 2. its tree renders nested with guide
  lines; 3. amber marks only needs-you/blocked; 4. keyboard can expand/collapse a branch.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/web/app.css`
  **Integration points:** reads node/item tree from the reducer; n/a external.
- [x] 6. My-tasks surface: list all operator items; "+ add" input; inline edit; drag-reorder;
  complete/delete — all via the Task-2 endpoints. — Verification: full
  **Prove it works:** 1. type a new task + enter; 2. it appears and persists to the state file;
  3. edit its text inline; 4. it shows in the cockpit counts + its project tree.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/server/server.js` → `neural-lace/workstreams-ui/state/reducer.js`
  **Integration points:** `POST /api/event` round-trips; reload shows the new task.
- [ ] 7. Backlog surface: same edit pattern + promote-to-task. — Verification: full
  **Prove it works:** 1. add a backlog item; 2. promote it; 3. it moves to the active list /
  Next and out of backlog.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/server/server.js`
  **Integration points:** `item-promoted` event reduces correctly.
- [ ] 8. Context-card + gate: per-kind required-field templates; progressive-disclosure render;
  `context-incomplete` flag for items missing required fields. — Verification: full
  **Prove it works:** 1. open a decision with full details → see background/options-with-meaning/
  recommendation/reply; 2. open one missing details → see "context incomplete", not a bare choice.
  **Wire checks:** `neural-lace/workstreams-ui/web/app.js` → `neural-lace/workstreams-ui/state/schema.js`
  **Integration points:** reads `details` shape; n/a external.
- [ ] 9. Emit discipline: extend the emit path so a raised decision/question carries the
  context payload (maps to `decision-context.md` fences); document the contract. — Verification: full
- [ ] 10. A11y + polish + rename: coordinated overlay-dismiss stack; aria-labels on icon-only
  controls; sweep "Conversation Tree" → "Workstreams" user-facing copy; visual verification at
  1280/768/390 px against live data. — Verification: full
- [ ] 11. Integration verification: end-to-end run of all five surfaces against the live
  112-item state; regression + responsive self-tests green. — Verification: full

## Files to Modify/Create
- `neural-lace/workstreams-ui/web/app.js` — the five surfaces' render + interactions.
- `neural-lace/workstreams-ui/web/app.css` — color/status discipline, tree styling, layout.
- `neural-lace/workstreams-ui/web/index.html` — view shell + rename leftover copy.
- `neural-lace/workstreams-ui/state/schema.js` — additive event types + `details` context shape + `origin`.
- `neural-lace/workstreams-ui/state/reducer.js` — reduce new events; normalize `state`.
- `neural-lace/workstreams-ui/state/selftest.js` — cover new events + reducer paths.
- `neural-lace/workstreams-ui/server/server.js` — `POST /api/event` write endpoints.
- `neural-lace/workstreams-ui/scripts/regression.e2e.js` — surface/round-trip/responsive assertions.
- `docs/decisions/NNN-workstreams-status-surface.md` — ADR for the re-conception (Tier 3).

## In-flight scope updates

### 2026-06-11 — plan-time review corrections (ux-designer + data-model research; the acceptance lens did not run — agent-name error)
The review found the plan OVER-SCOPED — several proposed events already exist, so the build SHRINKS by reusing them — plus phantom states and two cleanups. The walking-skeleton (`worker-ws-skeleton`, commit `6005b95`) proved the end-to-end chain works but used new `task-*` events; it is SUPERSEDED by the reuse approach below (rework on clean `feat`, do not cherry-pick as-is). Corrections, binding on the tasks above:

- **C1 (Task 1 re-scope):** Do NOT add `task-added`/`task-edited`/`item-promoted`. REUSE existing events: `action-added` (+ `origin:operator`) for operator-create, `item-text-set` for edit, `reordered` for drag-reorder, `backlog-activated` for promote. Add exactly ONE new event: `item-removed [node_id,item_id]` (splice from `node.items`; reject-not-apply unknown id; idempotent on event_id). `origin` is an OPTIONAL reducer-read item field (mirror `tier`/`serves_item_id` at `reducer.js:93-94`), NOT in `EVENT_REQUIRED_FIELDS`; resolve store-vs-derive-from-`actor` (`schema.js:210`, forced `gui` at `server.js:175`).
- **C2 (Task 2 re-scope):** `POST /api/event` already exists (`server.js:163-191` — forces `actor=gui`, auto-attests, 400/422/409). Do NOT rebuild. Task 2 = add per-type payload validation for the operator events + confirm round-trip from the My-tasks surface.
- **C3 (lifecycle states):** `closed` and `proposed` are produced by NO reducer (rendered but unreachable; default untouched item = `in-flight`); the model uses `shipped` for "done". DECISION: drop `closed`/`proposed` from the v1 spine; use the states the reducer actually produces; reconcile `done`↔`shipped` (use the existing `shipped`). Update the ADR + the "## Design → spine" wording.
- **C4 (drill return path):** Tasks 3+5 — add a persistent "← all projects" breadcrumb + current-project header; master-detail at wide width, full-swap-with-back at ≤390px. Add a "return to cockpit; overview restored" exit step to the `drill-into-a-project-tree` scenario.
- **C5 (no `window.prompt`):** Tasks 4/6/8 — ALL operator authoring uses in-surface forms / inline-editable elements, never `window.prompt()`; retire the 8 existing prompt() call sites. Add a "reply records via in-surface form, never a native prompt" assertion to `open-a-context-complete-decision`.
- **C6 (color migration):** Tasks 5+10 — retire the existing color=KIND CSS (`.k-*`, `.li-kind.*`, `kind-*` border colors); re-key color to STATUS, express kind by ICON only (`kindGlyph`/`KIND_LABEL` exist). Tokens: gray=idle/structure, amber=needs-you/blocked ONLY, muted-green-check=done; nothing else uses amber or saturated green. Prove-it: grep rendered DOM — amber on any non-needs-you row returns zero.
- **I1 (context card = re-style, not re-template):** Task 8 — the per-kind `details` shape + incompleteness gate already exist (`ItemDetailsContentSchema` / `assembleItemDetails` in `decision-context-schema.js` — returns null when not self-contained = the gate). Task 8 = consume `validateItemDetails`/`assembleItemDetails` + re-style the existing detail card with progressive disclosure + the context-incomplete visual; do NOT re-template.
- **I2 (gate suppresses actions):** Task 8 — when context-incomplete, render ONLY a "needs enrichment" state; SUPPRESS the resolving buttons (Approve/Decline/Answer/Submit), don't just badge.
- **I3 (write-error revert):** Tasks 6/7 — on `POST /api/event` failure, the inline edit visibly REVERTS + shows an inline "not saved — retry" affordance on that row (not only a toast). Add to `add-and-edit-a-personal-task`.
- **I4 (keyboard reorder):** Task 6 — reorder via keyboard (move-up/down controls or arrow on focused row), not drag-only.
- **I5 (overlay stack):** Task 10 — single overlay-stack manager (Esc closes topmost; scrim-click closes own layer; one scrim; focus-trap + restore); retire the two ad-hoc Esc handlers.
- **I6 (cross-process append):** ADR — correctness rests on `renameSync` atomicity + `event_id` idempotency (verify the bash emit hooks `flock`); do NOT claim a mutex.

Verdict: not build-ready as originally written; with these corrections the design is sound and SMALLER.

### 2026-06-12 — Task 9 file scope (emit path lives in the harness hooks, not the GUI)
- `adapters/claude-code/hooks/workstreams-emit.sh` — Task 9: decision/question emits carry the per-kind context payload (maps to the `decision-context.md` fence grammar / `item-details-set`).
- `adapters/claude-code/hooks/decision-context-gate.sh` — Task 9 (only if needed): fence→`item-details-set` mapping completeness; no behavior change outside the context-payload path.
- `adapters/claude-code/rules/workstreams-state.md` — Task 9: document the emit context contract (what a context-complete decision/question emission carries).
- `adapters/claude-code/rules/decision-context.md` — Task 9 (only if needed): cross-reference the GUI gate consuming the same sole-normative schema.

## Assumptions
- The event-sourced state library + reducer + attestation remain the sole-normative write path
  (the GUI server appends through it, never bypasses it).
- New event types are additive within ADR-032 schema major 1 (no major bump).
- The GUI server is the single writer process per machine; cross-machine sync continues via the
  existing coordination repo (out of scope here).
- The operator-authoring endpoints are local-only (the GUI binds localhost); no auth surface.

## Edge Cases
- A project with dozens of items (lopsided) — cockpit shows counts only, never overflows.
- An item with empty `details` (the current 112/112 case) — renders as `context-incomplete`,
  not a contextless choice; the surface stays useful via text+kind+state.
- Concurrent edits (operator typing while the AI emits) — append-only events + idempotent
  event_id reconcile; last-writer-wins on a single field per the existing schema.
- Promote-to-task on an already-active item — no-op (idempotent).
- Empty states (no projects / no waiting items / empty backlog) — each surface has a designed
  empty state, not an error.

## Acceptance Scenarios

### status-of-everything-at-a-glance — operator sees the whole pipeline
**Slug:** `status-of-everything-at-a-glance`
**User flow:**
1. Open the Workstreams GUI.
2. Look at the project cockpit.
**Success criteria (prose):** the operator sees one row per project with counts for each
lifecycle stage (now / next / waiting / done); the view is readable and non-overflowing even
for a project with many items; nothing requires scrolling a giant flat list to learn status.
**Artifacts to capture:** screenshot of the cockpit; no console errors.

### add-and-edit-a-personal-task — operator owns an editable list
**Slug:** `add-and-edit-a-personal-task`
**User flow:**
1. Open "My tasks".
2. Type a new task and press enter.
3. Edit its text inline and reload the page.
**Success criteria (prose):** the new task appears immediately, persists across reload (it was
written to the state file), is editable inline, and shows up in the cockpit counts and its
project tree.
**Artifacts to capture:** screenshot before/after; network log of the POST /api/event;
confirm the state file changed.

### open-a-context-complete-decision — no contextless choices
**Slug:** `open-a-context-complete-decision`
**User flow:**
1. Open a decision item that has full `details`.
2. Open a decision item with empty `details`.
**Success criteria (prose):** the first shows background, each option's meaning and tradeoff, a
recommendation, and reply affordances inline (with "more context" available); the second shows
"context incomplete — needs enrichment" rather than a bare A/B/C with no meaning.
**Artifacts to capture:** screenshot of both states; no console errors.

### drill-into-a-project-tree — bounded, color-coded, readable
**Slug:** `drill-into-a-project-tree`
**User flow:**
1. Click a project row in the cockpit.
2. Expand a branch with the keyboard.
**Success criteria (prose):** the project's tree renders nested with guide lines; amber marks
only items needing the operator (and branches containing them carry an amber dot); done work is
muted; a branch can be expanded/collapsed via keyboard.
**Artifacts to capture:** screenshot of the tree; confirm focusable twists.

## Out-of-scope scenarios
- Cross-machine merge conflict resolution in the GUI (handled by the coordination substrate;
  rationale: out of this plan's surface scope).
- Backfilling `details` for the existing 112 items (rationale: source docs unavailable;
  fix-forward only per the discovery's UX-3 disposition).

## Testing Strategy
- Reducer/schema: `state/selftest.js` covers each new event type + state normalization (Task 1).
- Endpoints: round-trip test — POST an add/edit/promote event, re-read state, assert the change
  (Task 2/6/7).
- Surfaces: `regression.e2e.js` (puppeteer) asserts each surface renders against live data, the
  cockpit shows counts not chips, the context-incomplete path renders, and responsive at
  1280/768/390 (Task 3–11).
- Visual: manual screenshot verification at the three widths against the live 112-item state
  (the self-tests check markers, not render — both are required).

## Walking Skeleton
The thinnest end-to-end slice that proves the architecture: Task 1 (one additive `task-added`
event in schema+reducer+selftest) + Task 2 (`POST /api/event` that appends it via the facade) +
the my-tasks "+ add" input wired to that endpoint (subset of Task 6). When typing a task in the
GUI writes an event that the reducer folds into state and the cockpit count increments on
reload, the full operator-authoring + status-derivation chain is proven; every other surface is
an additional read/render over the same proven substrate.

## Decisions Log
- The event-sourced backend is kept; only presentation + the operator-authoring path + context
  discipline change. Tier 3 (data-model + new write surface) → ADR required (Files list).
- Color encodes status, icon encodes kind, amber = needs-you only (locked in the discovery doc
  design detail, 2026-06-11).
- Context-completeness is gated, not advisory: a contextless decision/question/action-for-
  operator item is flagged incomplete and not presented as actionable.

## Evidence Log

Task-verifier PASS records (rung:2 comprehension gate run) live in the companion
evidence file `workstreams-ui-status-surface-redesign-2026-06-11-evidence.md`; the
per-task structured rationale + comprehension articulation live in
`workstreams-ui-status-surface-redesign-2026-06-11-evidence/tasks-1-2-6.evidence.md`.

- **Task 1** — Verdict PASS (Confidence 9). Oracle: derived-preexisting (contract) — the
  `state/selftest.js` suite is green at 21/21 incl. the new P20 property
  (create+origin-store/derive / edit-no-origin-flip / reorder / remove+reject-retain+idempotent+envelope).
  Comprehension-gate: PASS. Diff afd1bb4..536e813 confirms `item-removed` is the only new
  event and `origin` rides as an optional reducer-read item field.
- **Task 2** — Verdict PASS (Confidence 9). Oracle: specified — `POST /api/event` returns the
  exact per-type 422 for empty text / bad origin enum / non-array ordered_ids / empty item_id
  (validator re-executed standalone; live HTTP 422s recorded prior pass), and the `appendEvent`
  facade is unchanged (endpoint reused, not rebuilt). Comprehension-gate: PASS.
- **Task 6** — Verdict PASS (Confidence 9). Oracle: specified — acceptance scenario
  `add-and-edit-a-personal-task` round-trips live (13/13 in a real browser); add/edit/reorder/remove
  all via the in-surface input (zero `window.prompt` in the My-tasks flow — the only added
  prompt token is a comment; the 8 calls are the out-of-scope context-card surface), I3
  revert+inline-retry and I4 keyboard reorder present in the diff. Comprehension-gate: PASS.
- **Task 3** — Verdict PASS (Confidence 9). Oracle: specified — acceptance scenario
  `status-of-everything-at-a-glance`. Verifier re-ran the e2e fresh (17/17, server on 7799
  against a copy of TODAY'S live state — 124 items): 6 cockpit rows, four number pills each,
  all matching the independent `/api/state`-derived oracle (T2), constant 36px rows with zero
  item chips (T1/T3); counts derive from the same `allWorkItems()`+`statusCounts()` the filters
  read (no parallel data path); C3 holds (`proposed`/`closed` removed from the status surface).
  Comprehension-gate: PASS. Per-task rationale in `…-evidence/tasks-3-4-5.evidence.md`.
- **Task 4** — Verdict PASS (Confidence 9). Oracle: specified — the Surface-2 contract.
  Fresh e2e: T10 `waitRows=20 (oracle=20) bare=0` — the rendered list equals the independent
  `isWaitingOnYou` set; all 20 detail-less live items carry the visible neutral "context
  incomplete — needs enrichment" marker, none painted decision-ready; the context-COMPLETE
  inline path (background + recommendation) proven by the live POST round-trip artifact
  (`waiting-context-complete-1280.jpg`). One shared predicate drives list, cockpit pill, and
  tree amber. Comprehension-gate: PASS.
- **Task 5** — Verdict PASS (Confidence 9). Oracle: specified — acceptance scenario
  `drill-into-a-project-tree` + C4/C6. Fresh e2e: drill bounded with guide lines (T4); amber
  set === oracle needs-set, zero mismatches both directions (T5); zero kind-color classes in
  the DOM, kind by glyph icon (T6); keyboard-operable `aria-expanded` button twisty (T7);
  all-done branches collapsed by default + working "show done" (T8); breadcrumb returns at
  1280 and 390px (T9/T16). Verifier-independent C6 sweep: 2 comment-only hits in app.css,
  0 in app.js; C5: zero `window.prompt` added in the diff. Comprehension-gate: PASS.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): each behavior change is cited in a Task + a Files entry.
- S2 (Existing-Code-Claim Verification): file paths verified against the live `workstreams-ui/`
  tree this session (state/{schema,reducer,selftest}.js, server/server.js, web/{app.js,app.css,index.html}).
- S3 (Cross-Section Consistency): "kept backend" stated consistently in Goal/Scope/Decisions.
- S4 (Numeric-Parameter Sweep): widths 1280/768/390 consistent across Scope/Testing/Tasks.
- S5 (Scope-vs-Analysis Check): every "add/modify" verb targets an in-scope `workstreams-ui/`
  or `docs/` path; no out-of-scope file prescribed.

## Definition of Done
- [ ] All tasks checked off (task-verifier).
- [ ] All five surfaces render against the live state; cockpit never overflows.
- [ ] Operator can add/edit/reorder/complete tasks + backlog; promote works; persists across reload.
- [ ] No decision/question/action-for-operator item is shown without required context (gate works).
- [ ] Self-tests + regression green; visual verification at three widths captured.
- [ ] ADR landed; rename sweep done; a11y baseline met.
- [ ] SCRATCHPAD updated; completion report appended; acceptance scenarios PASS at runtime.
