# Plan: Cockpit roadmap redesign — one registry, three views

Status: ACTIVE
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none
Architecture-review: DONE 2026-07-18, TWO gate reviews, BOTH folded into the task text below —
architecture-reviewer (Fable) SOUND-WITH-AMENDMENTS, binding A1-A10
(`docs/reviews/2026-07-18-cockpit-roadmap-redesign-architecture-review.md`); ux-designer FAIL
pre-amendment, Criticals C1-C9 + Importants I1-I6
(`docs/reviews/2026-07-18-cockpit-roadmap-redesign-ux-review.md`). Every binding amendment is
folded in this revision. DELTA re-review 2026-07-18: ux-designer PASS-WITH-CONCERNS — all
C1-C9 + I1-I6 confirmed resolved, six sev-1/2 residuals folded as delta R1-R6
(`docs/reviews/2026-07-18-cockpit-roadmap-redesign-ux-delta.md`). The operator's verbatim record
(`docs/reviews/2026-07-17-cockpit-ux-design-input.md`) remains the supreme authority where any
texts conflict. Adjudications between the two reviews are logged in the Decisions Log.

## Goal

Rebuild the cockpit's surface around the operator's actual mental model, per the five-round
sit-down (`docs/reviews/2026-07-17-cockpit-ux-design-input.md` — ALL verbatim requirements live
there; this plan is its synthesis) + the Fable proposal
(`docs/reviews/2026-07-17-cockpit-ux-redesign-proposal.md`: live-verified defects — 718 identical
drift chips, the 18/18-done ask rendering ACTIVE, prompt-fragment titles).

## User-facing Outcome

ONE registry, THREE views, ONE navigation shell.

**Shell (C2):** three tabs — **Roadmap** (the landing tab: the glance surface), **Requests**,
**Inbox (N)** with a live headline count where N = derived ANSWERABLE items only (quarantined
items and operator-authored "My items" excluded — I4/A10). Hash-based item addressing
(`#roadmap/<id>`, `#request/<id>`, `#inbox/<id>`): every cross-view link switches tab + scrolls
+ expands + visibly highlights + moves programmatic focus to the target item; return = browser
Back (hashchange) AND an explicit return affordance on the landed item, both restoring the prior
tab with tree expansion + scroll intact. LAW: every cross-view arrow in this plan ships four
specs — target address, landed state, return path, miss behavior (a followed link to a
resolved/gone item renders "resolved <when> — <outcome>", never blank/404 — C3).

1. **Requests** — the conversation/intent ledger: every ask with an auto-distilled ALWAYS-EDITABLE
   title (operator edits always outrank the distiller — A3), verbatim origin one click away, an
   EVOLUTION TIMELINE (original → best-effort-classified amendments → decisions → "became →
   <plan>" on promote, which closes it here), a filter box, and age-grouped searchable closed
   requests (C8).
2. **Roadmap** — a build-order hierarchical tree (intents → plans → tasks) with a STATUS ON
   EVERY ITEM (no waterline), enum: not-started / in-progress (progress bar from child counts) /
   merged—deploy-unverified (no-signal oracle class, OUTSIDE Complete — A4) / complete /
   STALLED(derived reason + what-unblocks) / UNKNOWN(reason) (C5 — derivation failure is a named
   state, never a confident wrong bucket). ROLL-UP LAW (C1): attention states propagate to every
   collapsed ancestor as counted labeled badges — never masked by a parent's "in-progress".
   Every item's drill-down answers "from your request(s): …" (C6 — the round-1 verbatim
   direction). Expandable to the actually-tracked granularity; "added mid-build" markers;
   completed aging (in place 7d / immediate subtree collapse with "completed <when>" headline /
   "N completed ▸ — latest: <title>"). Kanban toggle + project filter chips. HARNESS CHORES
   EXCLUDED by provenance (operator B, A9).
3. **Inbox** — everything waiting on the operator (decisions + unblock-actions — one fact, two
   views), with a full item LIFECYCLE (arrive / act / leave — C3). **CONTEXT CONTRACT (operator
   mandate): every item carries source-provenance, the issue, trade-offs (for decisions), and
   what's-needed — a context-less item CANNOT render as answerable: it quarantines as "needs
   context" (framed as SYSTEM failure, excluded from the count — I4) and auto-files ONE defect
   against the producing session (A8).** Items render the operator-approved constitution §3
   compact anatomy (I5). The Inbox SUPERSEDES the My-To-Do pane (A10).

## Scope

IN: derived status foundation (six-value enum + roll-up law + completion-oracle config);
work-item layer (titles with source precedence / evolution capture+classify+correct /
merge-split); the navigation shell + hash routing + refresh model; the three views with all four
UI states + a11y bindings + findability; badge law at the renderer; badge-storm auditor fix;
event-triggered coord publish (writer-lib dirty marker + full-cycle floor) + person grouping;
the four absorbed UI-polish items; needs-you cold-reader lint warn→block ON THE
INTERACTIVE/MODEL-INVOKED ADD PATH ONLY (mechanical callers store-and-quarantine — A1).
OUT: Circuit P1 (own plan; the propose/partial-accept surface ships there, landing on THIS
surface's Requests/Roadmap); the chat sign-off Stop-gate (harness plan, nl-issue filed); INLINE
Inbox answering (v1 = pointer + copyable reply stub; inline is the pending-decision follow-on).
ABSORBS: `docs/plans/cockpit-ui-polish.md` (flip it SUPERSEDED on this plan's activation).

## Tasks

- [x] 1. [serial] **Derived top-level status foundation.** Per-item status computed, never
  declared. Fixes the done-renders-ACTIVE defect.
  - **Enum (C5):** not-started / in-progress / merged—deploy-unverified / complete /
    stalled(reason) / **unknown(reason)**. When any derivation input fails (plan-parse error,
    unreadable heartbeat, schema drift), the item renders unknown(reason) as a visibly distinct
    labeled chip ("status unknown — plan parse failed"), reason one click away; NO default-guess
    branch anywhere in derive-lib (selftest-pinned). Generalization: EVERY derivation this plan
    ships (status, stalled-reason, progress fraction, complete-oracle, hostname→person map)
    names its failure rendering — the named-absence pattern applied uniformly.
  - **Complete oracle (A4, operator A):** per-project completion-oracle config with three named
    classes — `deploy-oracle` (deploy evidence strictly newer than merge; PORT the existing
    age-guarded oracle from work-in-motion-sweep.js:386-583, do not re-derive) /
    `merged-is-deployed` (harness: session-start-auto-install syncs live from origin/master +
    doctor green IS the functional deploy signal — merged is complete-PROVEN) / `no-signal`.
    Binding rule: `no-signal` renders as the DISTINCT "merged — deploy unverified" state
    OUTSIDE the Complete bucket, with a labeled per-item operator override to complete. Manual
    "done" is always an override, labeled.
  - **in-progress (A6):** live session activity via `listRawHeartbeats` + pure-JS age
    classification (the peer-view A3c precedent), using the heartbeat lib's own classes
    (throttled/stale are NOT crashed) + an activity window (the proposal's T≈24h disjunct,
    restored) so AV-pressure flap cannot oscillate in-progress ↔ "stalled: crashed". **NO
    child-process spawn on any GET path** (classifySessions stays detail-path-only; measured
    20ms pure-read landing derivation vs 87ms–119s spawns) — selftest-pinned.
  - **Stalled, with DERIVED reason + unblock:** waiting-on-you(→ `#inbox/<id>` link) /
    limit-parked(resume time) / blocked-on(predecessor) / crashed(salvage).
  - **ROLL-UP LAW (C1):** attention states propagate upward — every collapsed ancestor of an
    attention-state descendant shows a counted, labeled badge ("1 stalled — waiting on you")
    beside its own status chip; badge click expands the path to the item. Badge precedence:
    waiting-on-you > crashed > blocked-on > limit-parked > unknown. MULTIPLICITY (delta R4):
    an ancestor shows ONE badge PER attention class present in its subtree, each counted +
    labeled; precedence governs display ORDER only, never selection — a higher class never
    masks a lower one. Applies to EVERY leaf-derived attention signal (all stalled reasons +
    unknown) — audited against the law, not just stalled. Roll-up counts computed here in
    derive-lib; rendered in task 3. —
  Verification: full
- [x] 2. [serial] **Work-item layer.**
  - **Titles (A3, round 3):** auto-distilled (async LLM, off the hot path); ALWAYS
    operator-editable, no confirm ceremony. Title records carry `title_source: auto|operator`;
    fold rule: operator-sourced ALWAYS outranks auto REGARDLESS of timestamp (incl. distiller
    re-runs) — the plain last-non-empty-wins fold is insufficient for title. The UI's title
    edit delegates to ask-registry.sh (same one-writer-implementation discipline as the
    lifecycle endpoint).
  - **Amendment capture (A2)** — three buildable layers, replacing the unbuildable
    "scope-modifying splice" (no hook sees intent; UserPromptSubmit carries raw text only):
    (a) mechanical capture — a UserPromptSubmit splice appends EVERY operator prompt in an
    ask-attached session as a timeline CANDIDATE (transcript ref + offset, never full text —
    the registry stays small); (b) classification — the SAME async off-hot-path LLM lane as
    title distillation marks candidates amendment/noise; (c) correction — operator
    edit/delete/detach on the timeline, plus an explicit `ask-registry.sh amend` verb as the
    model-invoked supplement (labeled memory-dependent). HONEST LIMIT, stated in the plan and
    in UI copy where relevant: amendment detection is best-effort classification, not a
    guarantee.
  - **Amendment correction (I6):** every auto-captured amendment carries "detach" (marks
    not-an-amendment; feeds the classifier) using the cockpit's existing undo-window pattern.
    Generalization: every auto-captured record type (title, amendment, item, inbox entry) has
    an operator correction affordance — auto-capture without undo is a trust tax.
  - Merge/split of asks into items (existing affordance). —
  Verification: full
- [x] 3. [serial] **Roadmap tree view + the navigation shell.**
  - **Shell (C2), built here; tasks 4-5 register into it:** three tabs (Roadmap lands;
    Requests; Inbox (N) live count = answerable items only); hash routing (`#roadmap/<id>` /
    `#request/<id>` / `#inbox/<id>`) with the landed-state (switch + scroll + expand +
    highlight + programmatic focus), Back-via-hashchange + explicit return affordance
    restoring prior tab with expansion + scroll, and the miss rule (resolved/gone target →
    "resolved <when> — <outcome>").
  - **Tree per Outcome §2:** six-value status chips on every item; progress bars from child
    counts, ALWAYS with the "4/9" text (never bar-only); zero-tracked-children items omit the
    bar (no fake granularity); expansion to actually-tracked granularity; task-1 roll-up
    badges rendered on every collapsed ancestor.
  - **Build order (A7):** a `roadmap_rank` record on the registry, operator-editable via UI
    delegation to ask-registry.sh; DEFAULT = plan-creation (registry insertion) order. (The
    operator's "order intended to be built" previously had NO data source — this names the
    mechanism; see Decisions Log adjudication (a).) Reorder ships keyboard-operable move
    up/down controls (real buttons); drag, if offered, is an enhancement, never the only path
    (WCAG 2.2 2.5.7 — delta R2).
  - **Roadmap→Request (C6):** every roadmap item's drill-down carries "from your request(s):
    <title(s)>", linking via `#request/<id>` to the ledger entry, resolved verbatim one click
    away (the existing Verbatim mechanism). LAW: every promote/became/derived-from
    relationship renders in BOTH directions, or the plan states why not.
  - **Recency (I1):** every status chip carries its transition age ("in-progress, 2h" /
    "completed 3d ago" — app.js formatAge exists); a collapsed complete subtree's headline
    carries "completed <rel-time>"; transitions <24h old get one subtle, non-color-only "new"
    treatment. Generalization: every status-bearing chip in ALL THREE views (incl. Inbox item
    age, Requests "last amended") shows its age.
  - **Completed aging + markers (round 4 + I2):** completed in place 7d; a fully complete
    subtree collapses to its headline immediately (headline keeps "completed <when>"); after
    7d → per-parent roll-up "N completed ▸ — latest: <title>" (count + one exemplar for
    scent). The "added mid-build" insertion marker ages out on the SAME 7d tunable — one knob.
    LAW: every annotation chip declares persistent-vs-transient; transient ones share the
    single aging tunable.
  - **Kanban toggle (I3, decide-and-go default):** cards = TOP-LEVEL roadmap items; columns =
    the derived statuses with stalled visually distinct (merged-unverified and unknown render
    as their own labeled columns, never inside Complete — see Decisions Log adjudication (d);
    these two EXCEPTIONAL columns render only when non-empty — delta R5);
    same chips as the tree; toggle + project-chip selections persist (localStorage). LAW:
    every alternate view (kanban here; person-grouped peers in task 7) names its unit-of-card
    and its state persistence.
  - **Harness-chore exclusion (A9, operator B):** classifier = PROVENANCE (operator-requested
    vs machine-filed: nl-issue/findings/auto-sweep), NOT subject matter — else
    operator-requested harness work (this rebuild) vanishes and the roadmap opens near-empty.
  - **Four UI states (C4):** loading "deriving roadmap…"; error = pane-error + Retry (NEVER
    the empty state on failure — the app.js:185 law); FILTERED-empty names the filter + hidden
    count + one-click clear ("N items hidden (harness chores)" / "no items match <chip>
    [clear]"); TRUE-empty explains items arrive automatically from sessions (no setup ask).
  - **Refresh model (C7):** the three views poll on the existing 30s tick with
    STATE-PRESERVING re-render — preserve the details-open set, scroll position, focus,
    uncommitted title edits, and the landing highlight; on refresh failure show "derived
    <age> — STALE" (app.js:176 pattern), never silent staleness. LAW: any auto-refreshing
    surface preserves expansion + scroll + focus + uncommitted edits.
  - **A11y (C9):** tree nodes = nested `<details>`/`<summary>` (the codebase's native-keyboard
    disclosure pattern); title editing reuses the todo.js edit-button + Escape + focus-return
    pattern (never click-on-text-only); every status signal is text + color, never color-only
    (chips carry words; bars carry "4/9"; the insertion marker is a labeled chip); interactive
    chips are real `<button>`s (inherits the 24px floor); the kanban toggle is an aria-pressed
    button. —
  Verification: full
- [ ] 4. [serial] **Inbox view + context contract enforcement.**
  - **Item anatomy (I5 — the operator-approved §3 compact format, reused not reinvented):**
    COLLAPSED ROW: type glyph + text label (decision / unblock) + the ask as ONE imperative
    sentence + source chip (session/plan) + age + "blocks: <item>" when it stalls live work
    (links `#roadmap/<id>` — the shell's four-spec arrow law applies, delta R3);
    sort = blocking-live-work first, then age. EXPANDED: the constitution §3 anatomy rendered —
    1. Decision/Action needed (one sentence, visually primary); 2. Context ≤5 lines with links
    (provenance folded here: which conversation, when, verbatim one click); 3. Trade-offs
    table (Option / What happens / Cost-risk) — decisions only; 4. My pick + one-line reason;
    5. Reply-with — exact answers + what each triggers + the answer affordance. BELOW THE FOLD
    (collapsed details): raw verbatim, session lineage. LAW: any operator-facing ask anywhere
    (Inbox, needs-you sign-offs, stalled reasons) renders the same §3 anatomy — one format,
    learned once.
  - **Item lifecycle (C3):** (a) ANSWER — v1: a "how to answer" line naming the exact channel
    (reply in session <id> / the NEEDS-YOU.md entry) + a copyable reply stub (inline answering
    = the PENDING decision, see Decisions Log; build proceeds pointer+stub); (b) RESOLVE — the
    item leaves when the canonical ledger entry clears/is-answered, or on operator dismiss
    (dismiss = labeled override, consistent with the derivation law); (c) STALE-LINK — a
    followed link to a resolved item renders "resolved <when> — <outcome>", never blank/404.
    LAW: every view's item type defines all three lifecycle verbs at plan level (Requests:
    auto-capture / edit-amend / close-on-promote; Roadmap: promote / build / complete-aging —
    both specced above).
  - **Lint promotion (A1):** needs-you.sh cold-reader lint warn→BLOCK on the
    INTERACTIVE/MODEL-INVOKED add path ONLY — the session sees the error and retries with
    context (a teaching gate). MECHANICAL callers (stop-verdict-dispatcher.sh:45,
    session-resumer.sh park, session-honesty-gate.sh PAUSING) pass a `--mechanical` flag (or
    equivalent) and STORE-AND-QUARANTINE instead — the shipped ledger-never-rejects contract
    (needs-you.sh:556) is preserved; a waiting-item must never land NOWHERE. Constitution §10
    compliance: golden scenario = the 2026-07-18 bare-token sign-off incident (memory
    feedback_needs_from_you_full_context); expected FP rate <~5% of interactive adds (the
    session holds full context; retry-with-context is the designed recovery, costing seconds);
    retirement condition = demote to warn if a weekly triage window shows FP blocks exceeding
    true catches, or once every producer emits §3-complete items and the lint has not fired
    for a month.
  - **Quarantine (I4 + A8):** quarantined items render BELOW answerable ones under "N arrived
    without context — defects filed against the producing sessions"; each shows what the
    system DOES know, the auto-defect link ("defect filed →"), an "open source session" escape
    hatch, and dismiss; EXCLUDED from the Inbox (N) headline count. "Open source session"
    names its target (delta R3): the session's existing Harness Health drill-in when one
    exists, else a copyable `claude --resume <session-id>` command — never a dead affordance. Framing law: the system
    failed, not the operator — every system-failure surface (quarantine, unknown-status,
    coord-unreachable) names the failing component and shows the remediation already taken.
    Auto-defect mechanics: filed in the AUDITOR cycle only (never on render), keyed by ledger
    item id, ONCE per item lifetime, reusing the auditor's filed-once + recurrence-escalation
    state (auditor.js:185-193); legacy no-producer items file against the ledger id;
    recurrence escalates, never re-files. Classification reuses the `lint_warnings`
    needs-you.sh already stamps at add — never a second heuristic.
  - **Win state (C4):** "Nothing waiting on you — all sessions running free. As of <time>."
    SCOPED to the answerable section (delta R1): it renders when zero ANSWERABLE items exist,
    even while quarantined or "My items" entries remain visible below — those sections never
    defeat or fake the win; rendered ONLY on successful derivation; a failed/unreadable ledger renders pane-error +
    Retry, NEVER the win state (error-masquerading-as-empty is the worst four-state
    confusion). Loading/error per the existing pane-state convention.
  - **Inbox vs My-To-Do (A10):** the Inbox SUPERSEDES the My-To-Do pane as the canonical
    waiting-on-me surface; operator-authored freeform items render as a distinct "My items"
    section within the Inbox view (keeping the todo.js edit machinery), EXCLUDED from Inbox
    (N). One surface — the two counts can never disagree. (Task 8 removes the standalone
    pane.)
  - **A11y (C9):** as task 3 — details/summary disclosure, focus management, text-never-
    color-only, button chips. —
  Verification: full
- [x] 5. [serial] **Requests ledger view.**
  - **Timeline anatomy (I6):** collapsed = title + one-line CURRENT state ("became → <plan>"
    or "open, amended 2d ago"); expanded = oldest-first chronology, origin pinned first, every
    event dated, "became →" as the terminal event; amendment rows carry the task-2 detach
    affordance (undo-window pattern).
  - "became →" links use `#roadmap/<id>` addressing (shell rules apply: landed state, return,
    miss behavior); close-on-promote is the request's exit verb.
  - **Findability (C8):** a filter box (substring over title + distilled intent + verbatim
    origin); closed requests default-collapsed under age groups ("this week / this month /
    older") that search reaches inside ("closed (N)" expands). RULE (adopted from the
    proposal): any surface that can exceed ~2 viewports ships a filter escape hatch AT BIRTH —
    roadmap tree at scale, "N completed" roll-ups, and the quarantine group are siblings.
    ARBITRATION (delta R6): the roadmap tree's at-birth hatch = this SAME substring filter box
    (shipped in task 3) — project chips are facets, not search, and do not satisfy the rule
    alone.
  - **Recency (I1):** rows carry "last amended <age>".
  - **Four UI states (C4):** loading/error per pane convention; empty explains auto-capture
    ("requests appear here automatically as you talk to sessions").
  - **A11y (C9):** as task 3. —
  Verification: full
- [x] 6. [serial] **Badge law + badge-storm fix**: renderer caps telemetry to ONE counted, labeled
  chip per belief-changing class (bookkeeping classes → Harness Health only); auditor's
  unmatched_dispatch oracle age-bounded to the marker-retention horizon (nl-issue spec) —
  Verification: full
- [ ] 7. [serial] **Event-triggered publish + person grouping** (round 5, mechanics bound per A5).
  - **Dirty marker at the WRITER-LIB seam** (progress-log-lib.sh emit + ask-registry.sh
    append), NOT in hooks — hook-layer-only placement misses the GUI's own delegated CLI
    writes (lifecycle, title edits) and every future writer. Marker touch is never-blocking
    (no git/network on the write path).
  - **Debounced publisher:** NL-CoordSync publishes ≤~1/min when dirty, hash-gated burst
    coalescing as today.
  - **The floor runs the FULL cycle (exporter + push + pull) at ≤600s REGARDLESS of the
    marker.** Two proven reasons, pinned: the A3ii keepalive stamp is only written when the
    exporter runs (export-state.js:207-230) — a naive "if clean: exit 0" freezes `exported_at`
    and every healthy idle machine renders peer-unreachable within ~80min (peer-view.js:34-49);
    and git-blind mutations (cherry-pick/pull) produce no marker — the floor is their only
    coverage.
  - **Marker cleared BEFORE reading state for export** — an event landing mid-export
    re-dirties and the next cycle republishes; clear-after loses that update (classic
    dirty-flag lost-update).
  - **Cadence cost bound:** overlap bounded by the existing mkdir lock + IgnoreNew
    (coord-sync.sh:31-42); VERIFY the 900s lock-stale threshold at the new cadence; log
    marker-check-only fires distinctly so cycles.log stays readable.
  - **Person grouping:** hostname→person map (machine-local overrides) so peers group by
    PERSON (Misha's machines vs Jaime's); an unmapped hostname renders under "unassigned" —
    a named state, never a guess (task-1 generalization). Unit-of-card + state persistence
    named (I3 law). Coord-repo access for the second account documented. —
  Verification: full
- [ ] 8. [serial] **UI polish absorbed** (resizable/independently-scrollable panes without
  regressing the todo-clip fix; compact expandable backlog rows; task descriptions rendered +
  per-row plan links deduped; Artifacts section removed; the standalone My-To-Do pane REMOVED —
  its operator-authored items move into the Inbox "My items" section per A10/task 4) —
  Verification: full
- [ ] 9. [serial] **Acceptance**: end-user-advocate runtime pass over the shell + three views
  (scenarios below) + the operator's own cold-start walkthrough ON THE NEW SURFACE (replaces the
  retired ask-p1 walkthrough) — Verification: full

## Files to Modify/Create
- `neural-lace/workstreams-ui/web/` — shell + hash routing in app.js; all three views + their
  selftests
- `neural-lace/workstreams-ui/server/` — server.js + derive-lib.js (status derivation incl.
  unknown + roll-up counts, work-item layer), auditor.js (badge age-bound + quarantine
  auto-defect filing), payload-schema.js, server.selftest.js; completion-oracle port source:
  work-in-motion-sweep.js deploy oracle
- `neural-lace/workstreams-ui/config/` — completion-oracle config (per-project classes) + a
  `people.js`-style hostname→person map (machine-local overrides)
- `adapters/claude-code/scripts/needs-you.sh` — interactive-only lint block + `--mechanical`
- `adapters/claude-code/scripts/ask-registry.sh` — amend verb, `title_source`, timeline
  candidate verbs, `roadmap_rank`, dirty-marker at the writer-lib seam
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — dirty-marker at the writer-lib seam
  (NOT hook splices)
- `adapters/claude-code/scripts/coord-sync.sh` — debounce + full-cycle floor

## In-flight scope updates
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t4.md — task 4 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t8.md — task 8 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t5.md — task 5 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t3.md — task 3 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t2.md — task 2 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t6.md — task 6 evidence companion (gate input).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence-t7.md — task 7 evidence +
  articulation companion (gate input).
- 2026-07-19: docs/reviews/2026-07-19-worktree-salvage-classification.md — salvage sweep
  row-by-row record (doctor-restore track; 43+82 purge-safe, 28+9 orphan-work re-home queue,
  incl. ADR-061 supervisor core feeding the continuous-operation program).
- 2026-07-19: docs/reviews/2026-07-19-continuous-operation-design-input.md — operator
  sit-down record (24/7 continuous-operation design, round 1): steers this plan's task 7
  (publish cadence/supervision) + task 9 acceptance framing, and seeds the follow-on
  program plan. Sit-down-record precedent: cockpit-ux-design-input.md.
- 2026-07-19: docs/reviews/2026-07-19-doctor-red-spike-diagnosis.md — deploy-leg restoration
  prerequisite: doctor spike diagnosis; install/auto-install is this plan's deploy mechanism
  and coord-sync/coord-push must be record-covered before task 7 lands (nl-issue 126).
- 2026-07-19: docs/reviews/2026-07-19-doctor-quick-full-output.md — full doctor run output
  backing the diagnosis (raw evidence).
- 2026-07-19: docs/reviews/records/index.json — harness-change-review record registration for
  the 9 withheld blobs (unblocks the deploy leg; 5512926 precedent).
- 2026-07-19: docs/plans/cockpit-roadmap-redesign-evidence.md — task-verifier canonical
  evidence companion (created by the t1 verification gate).
- 2026-07-19: `neural-lace/workstreams-ui/server/derive-lib.js` — reconciles the
  original Files to Modify/Create table's BARE `derive-lib.js` token (no
  directory prefix — scope-enforcement-gate.sh matches the exact repo-root-
  relative staged path, so a bare filename never matches a nested repo path)
  to the real path. The same bareness affects `server/server.js` /
  `server/auditor.js` / `server/payload-schema.js` above (all missing the
  `neural-lace/workstreams-ui/` prefix the repo root actually requires) —
  flagged here for whichever task next stages those files to add its own
  matching in-flight entry; not fixed wholesale in this task to keep this
  edit scoped to the files Task 1 actually touches.
- 2026-07-19: `neural-lace/workstreams-ui/server/completion-oracle.js` — Task 1's
  per-project completion-oracle config (three named classes: deploy-oracle /
  merged-is-deployed / no-signal, per A4), named only in prose in the original
  Files to Modify/Create table ("a completion-oracle config (per-project
  classes; port source: `server/work-in-motion-sweep.js` deploy oracle)") with
  no concrete path — this reconciles the prose to the actual file.
- 2026-07-19: `neural-lace/workstreams-ui/config/completion-oracle.example.json` —
  the tracked, generic per-machine-override placeholder for the same config,
  mirroring `config/projects.example.json`'s existing two-layer convention.
- 2026-07-19: `neural-lace/workstreams-ui/config/.gitignore` — adds
  `completion-oracle.json` to the existing per-machine-override ignore list
  (same convention already covering `projects.json` / `wim-repos.json`).
- 2026-07-19: `neural-lace/workstreams-ui/web/*` — task 3 shell + Roadmap view (index.html, app.js, roadmap.js NEW, asks.js anchor, app.css, cockpit.selftest.js); scope-gate-parseable form of the prose Files-to-Modify entry
- 2026-07-19: `neural-lace/workstreams-ui/server/roadmap-routes.js` — task 3 NEW route module (tasks 1/2 own server.js/derive-lib/ask-registry.sh; mount line ships as a fragment)
- 2026-07-19: `neural-lace/workstreams-ui/server/roadmap-routes.selftest.js` — task 3 NEW sandboxed selftest (own file so task 1's server.selftest.js is never raced)
- 2026-07-19: `docs/plans/fragments/roadmap-t3-server-fragment.md` — task 3 coordination fragment (server.js mount + task-1/2 seams)
- 2026-07-19: `adapters/claude-code/hooks/workstreams-read.sh` — Task 2's A2 layer (a) capture splice extends the already-wired UserPromptSubmit ask-capture splice hosted in this hook (the task text mandates the splice; the files list omitted its host file). Same edit reformatted the files list above into gate-parseable bullets (scope-enforcement-gate structural error NO_PARSEABLE_ENTRIES was blocking every commit) — content-preserving; paths made repo-root-relative; no scope added beyond this entry.
- 2026-07-19: `docs/plans/fragments/` — cross-task patch fragments for concurrently-owned files (coordination convention this build round: a builder needing an edit in another in-flight task's file ships the proven diff here for the orchestrator to splice; first consumer: roadmap-t2-derive-lib-fragment.md).
- 2026-07-19: `adapters/claude-code/manifest.json` — honest_status refresh for the ask-registry entry (Task 2 added five verbs + the title_source contract; constitution §10 requires the inventory line stay true).
- 2026-07-19: `neural-lace/workstreams-ui/server/server.js` — reconciles the
  bare `server/server.js` token in the original Files to Modify/Create table
  (missing the `neural-lace/workstreams-ui/` prefix — flagged by task 1's own
  evidence as unresolved for "whichever task next stages" this file) to the
  real repo-root-relative path, for the roadmap-t3 server-integration task
  applying fragment §1 (the ONE mount line: require + first-line dispatch in
  the http.createServer handler). No other in-scope change to this entry;
  `server/auditor.js` / `server/payload-schema.js` remain unreconciled for
  whichever task next stages those two.
- 2026-07-19: `neural-lace/workstreams-ui/web/asks.js` — task 6 badge-law renderer fix (already covered by task 3's `web/*` glob entry above; named explicitly here so task 6's commit is unambiguously attributed and doesn't depend on a different task's entry)
- 2026-07-19: `neural-lace/workstreams-ui/web/cockpit.selftest.js` — task 6 badge-multiplicity fixture tests (T6-0..T6-5), same attribution note as the asks.js entry above
- 2026-07-19: `neural-lace/workstreams-ui/server/requests-routes.js` — task 5 NEW route module (Requests ledger payload/title/amend-detach; task 1 owns server.js, task 2 owns ask-registry.sh — mount line + verb seams ship as fragments)
- 2026-07-19: `neural-lace/workstreams-ui/server/requests-routes.selftest.js` — task 5 NEW sandboxed selftest (own file so task 1's server.selftest.js is never raced)
- 2026-07-19: `neural-lace/workstreams-ui/web/requests.js` — task 5 NEW client view module (self-mounting into the existing `#tabRequestsPanel`; registers 'requests' via `WorkstreamsShell.registerView`, replacing app.js's interim placeholder — no edit to app.js/roadmap.js/asks.js)
- 2026-07-19: `neural-lace/workstreams-ui/web/app.css` — task 5 CSS additions for the Requests ledger (`.rl-*` classes; same palette discipline as task 3's `.rm-*` section)
- 2026-07-19: `neural-lace/workstreams-ui/web/app.js` — task 6 FIX ROUND (task-verifier conf 7): bookkeeping-divergence-class summary added to the Harness Health diagnostics pane (`renderDiagnostics`, the `BOOKKEEPING-DIAG-BEGIN/END` anchored block only — same region already covered by task 3's `web/*` glob entry above), the redirect destination for classes `web/asks.js`'s badge law now suppresses from the ask card per proposal §5. Scoped to the diagnostics-pane region specifically to stay disjoint from task 8's concurrent pane-resize/backlog edits in the same file.
- 2026-07-19: `neural-lace/workstreams-ui/web/cockpit.selftest.js` — task 5 extends the suite with the T5-* block (24 new assertions; 139 -> 163 composed, 0 failing)
- 2026-07-19: `docs/plans/fragments/roadmap-t5-server-fragment.md` — task 5 coordination fragment (server.js mount + task-2 seams: reused set-title verb + NEW detach-amendment verb pinned)
- 2026-07-19: `docs/plans/fragments/roadmap-t5-shell-fragment.md` — task 5 coordination fragment (the ONE index.html `<script src="/requests.js">` line; task 5's dispatch excluded direct index.html edits)
- 2026-07-19: task 8 ("UI polish absorbed") touches `neural-lace/workstreams-ui/server/derive-lib.js` and `neural-lace/workstreams-ui/server/server.selftest.js`
  (`computePlanRows` — adds a clamped `description` field to each per-task
  payload object; S63b-e), beyond the task line's literal `web/*` scope. Necessary producer-
  side wiring: the archived cockpit-ui-polish.md's item 3 assumed the
  cockpit-v2 Task 6 schema carve-out (`description` in payload-schema.js's
  DETAIL_ALLOWED_KEYS/DENYLIST_EXEMPT_KEYS) was sufficient, but
  `computePlanRows` never actually emitted the field — a pure client-side
  "render `t.description`" would have had nothing to render. Discovered
  live during this task's build: this plan's OWN task 3/4 bullets parse to
  4485/4846-char descriptions (verified via `plan-parse.js` directly against
  this file), 2x+ over payload-schema's 2000-char `DENYLIST_EXEMPT_MAX_LEN`
  — wiring the raw field through unclamped would 500 `GET /api/ask/<id>` on
  this plan's own tracking ask the moment its task text grows past the cap
  (reproduced directly against `payload-schema.js`). `computePlanRows` now
  clamps to 500 chars server-side before the payload is built; the schema's
  job stays "reject if this producer ever regresses," never "do the
  truncation." derive-lib.js's `computePlanRows` is a different function
  than the title/status-derivation code tasks 1/2 own — no line-level
  overlap.
- 2026-07-19: task 8 does NOT retire the standalone My-To-Do pane
  (`#todoSection`/`web/todo.js`), despite the task line naming it. Task 4
  (Inbox view + the "My items" section, A10) — the pane's replacement
  destination — has not landed (not even started; only tasks 5/6 are
  in flight alongside this one per dispatch). Removing the pane now would
  strand the operator's existing to-do items (docs/operator-todo.md,
  verified live: real operator + pointer items render there today) with NO
  UI surface at all until task 4 ships — a functional regression, not a
  polish step. The other four items (resize/scroll, compact backlog rows,
  task descriptions, Artifacts removal) ship in full; pane retirement is
  deferred to whichever task lands task 4's "My items" section (task 4
  itself, per its own text: "Task 8 removes the standalone pane" — this
  reconciles that forward reference now that the actual landing order is
  known).
- 2026-07-19: `neural-lace/workstreams-ui/server/inbox-routes.js` — task 4 NEW route module (Inbox payload/dismiss; task 1 owns server.js — mount line ships as a fragment)
- 2026-07-19: `neural-lace/workstreams-ui/server/inbox-routes.selftest.js` — task 4 NEW sandboxed selftest (own file so task 1's server.selftest.js is never raced)
- 2026-07-19: `neural-lace/workstreams-ui/web/inbox.js` — task 4 NEW client view module. UNLIKE requests.js/roadmap.js, binds to task 3's EXISTING static markup (`#inboxSection`/`#inboxBody`/`#inboxTabCount`) rather than inserting a new wrapper subtree; registers 'inbox' via `WorkstreamsShell.registerView`.
- 2026-07-19: `neural-lace/workstreams-ui/web/app.js` — task 4 REMOVES (not merely overrides) app.js's interim Inbox renderer (`answerableOf`/`updateInboxCount`/`renderInboxInterim`/`loadInbox`/the interim `registerView('inbox', ...)` call + its boot-time poll) — that interim block independently drove `#inboxTabCount` on its own 30s timer, which would otherwise race inbox.js's own count update and violate A10 ("the two counts can never disagree"); unlike the Requests tab (no independent count widget), Inbox's count badge made this removal load-bearing, not optional cleanup. Also fixes one stale comment (Harness Health Q2 pane) that claimed needs-you.sh's add "never blocks on lint" — no longer true for the interactive path this task adds.
- 2026-07-19: `neural-lace/workstreams-ui/web/app.css` — task 4 CSS additions for the Inbox view (`.ib-*` classes; same palette discipline as tasks 3/5's `.rm-*`/`.rl-*` sections); reuses task 3's pre-existing `.inbox-section`/`.inbox-win` rather than duplicating them.
- 2026-07-19: `neural-lace/workstreams-ui/web/cockpit.selftest.js` — task 4 extends the suite with the T4-* block (~30 new assertions) and updates T3-3 (the Inbox-count assertion) to read `inbox.js` instead of `app.js`, since the derivation moved per this task.
- 2026-07-19: `neural-lace/workstreams-ui/server/server.selftest.js` — task 4 fixes ONE pre-existing fixture (S22b's "bad" needs-you.sh CLI call) that this task's own interactive lint-block change would otherwise silently break (the fixture deliberately creates a context-less decision entry to test DOWNSTREAM rendering, not the lint-block itself — an update to a test broken by this task's own change, not new scope).
- 2026-07-19: `adapters/claude-code/hooks/session-honesty-gate.sh` — task 4's A1 `--mechanical` flag added to the ONE PAUSING-marker `needs-you.sh add --section decision` call site (this gate fires with no live actor present to retry a lint block — must store-and-quarantine, never lose the PAUSING ask).
- 2026-07-19: `adapters/claude-code/scripts/session-resumer.sh` — task 4's A1 `--mechanical` flag added to its `needs-you.sh add --section inflight` park call site (named explicitly in the plan's A1 bullet by file; harmless today since `inflight` is never lint-checked, but correct per the plan's own file:line citation and future-proof if that scoping ever widens).
- 2026-07-19: `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — task 4's A1 `--mechanical` flag added to its `needs-you.sh add --section inflight` gap-recording call site (same rationale as session-resumer.sh above; also named explicitly in the plan's A1 bullet).
- 2026-07-19: `docs/plans/fragments/roadmap-t4-server-fragment.md` — task 4 coordination fragment (server.js mount line; also documents the pre-existing task-5 `requests.js` script-tag defect discovered adjacent to this work, corrected in the shell fragment below)
- 2026-07-19: `docs/plans/fragments/roadmap-t4-shell-fragment.md` — task 4 coordination fragment (the ONE index.html `<script src="/inbox.js">` line; PLUS the corrective diff moving task 5's misplaced `<script src="/requests.js">` line out of an HTML comment it accidentally landed inside — bundled since whoever applies this fragment is already editing that exact region)
- 2026-07-19: `docs/backlog.md` — task 4 files two follow-ups: `INBOX-MY-ITEMS-RELOCATION-01` (the "My items" section + standalone-pane retirement, confirmed task 8's per its own bullet) and `ROADMAP-WAITING-ON-YOU-SIGNAL-01` (roadmap-routes.js never populates `stalledSignals.waitingOnYouId`, so the Inbox's "blocks: `<item>`" chip has no live data source yet — HONEST LIMIT, never fabricated)

## Assumptions
- The ask registry IS the work-item registry plus fields (title, timeline, rank) — no new store
  (Fable proposal §7) — WITH the A3 caveat: the plain last-non-empty-wins fold is insufficient
  for `title`; the `title_source` operator-beats-auto precedence rule is part of this
  assumption's truth.
- Status derivation reads existing data (plan-parse, raw heartbeats, merge SHAs, acceptance
  artifacts). Deploy evidence is a three-class per-project oracle config (A4): `deploy-oracle`
  (ported from work-in-motion-sweep) / `merged-is-deployed` (harness auto-install + doctor) /
  `no-signal` (renders OUTSIDE Complete as "merged — deploy unverified") — never silently
  complete, never forever-incomplete.
- The distill step AND amendment classification run off the hot path (capture writes
  refs/verbatim; classification is async). Amendment detection is best-effort (A2) — the
  timeline is honest about this limit.
- Landing/roadmap derivation is pure-read JS — no child-process spawn on any GET path (A6;
  measured 20ms vs 87ms–119s).

## Edge Cases
- Status-change arriving via git ops (no hook): the full-cycle periodic floor covers it (A5).
- Operator title edit racing the async distiller: operator wins by `title_source` precedence,
  regardless of timestamps (A3).
- Multi-part prompts → split; mid-conversation asks → candidate capture + async classification,
  with detach + merge/split as the correction paths (A2/I6).
- Context-quarantined Inbox items must not silently vanish: they render AS quarantined with the
  producing session named; legacy no-producer items are keyed by ledger id (A8).
- An in-progress item with zero tracked children: progress bar omitted (no fake granularity).
- A collapsed ancestor of a stalled/unknown descendant: roll-up badge always renders — the
  attention state is never masked (C1).
- An idle-but-healthy machine over a quiet weekend: the floor keeps `exported_at` fresh — it
  never renders peer-unreachable (A5).
- AV-pressure heartbeat flap: throttled/stale ≠ crashed + the 24h activity window prevent
  in-progress ↔ crashed oscillation (A6).
- A cross-view link to a resolved/gone item: "resolved <when> — <outcome>", never blank (C3).
- A filter (chore exclusion, project chip) empties a REAL estate: filtered-empty with hidden
  count + one-click clear — never a bare "no items" that reads as data loss (C4).
- Any derivation input failure: unknown(reason), never a confident bucket (C5).

## Acceptance Scenarios
1. The archived 18/18 rebuild renders COMPLETE — complete-PROVEN via the harness
   `merged-is-deployed` oracle class (auto-install + doctor green), never ACTIVE, and NOT the
   no-signal fallback (A4).
2. A deploy-required item, merged but undeployed, renders "merged — deploy unverified" OUTSIDE
   the Complete bucket, with the labeled operator override available (A4).
3. A context-less INTERACTIVE needs-you add is REFUSED with the teaching message; the SAME text
   added via stop-verdict-dispatcher lands STORED + QUARANTINED (never lost); a legacy
   context-less item renders quarantined + exactly ONE defect filed across repeated auditor
   cycles (A1/A8).
4. Badge wall impossible: inject 700 bookkeeping badges → roadmap shows at most one counted chip
   per belief-changing class.
5. Flip a task on machine A → peer view on B updates within ~2 min (event path); a machine idle
   24h still shows fresh `exported_at` (full-cycle floor) and never renders peer-unreachable
   (A5).
6. Fully collapse the tree; stall one deep descendant (waiting-on-you) → every ancestor shows
   the counted labeled badge; clicking it expands the path; the `#inbox/<id>` link lands
   focused + highlighted; Back restores the roadmap with expansion + scroll intact (C1/C2).
7. Corrupt one plan file → its item renders unknown("plan parse failed") and rolls up — never a
   confident bucket; an unreadable NEEDS-YOU ledger renders pane-error + Retry — NEVER the
   "nothing waiting on you" win state (C5/C4).
8. Edit a title, then let the distiller re-run → the operator's title survives (A3).
9. Operator walkthrough on the new surface: the four bucket questions + "which request did this
   come from?" answerable cold in <60s (C6).

## Out-of-scope scenarios
Circuit's propose/partial-accept meeting-items surface (Circuit P1 ships it; this plan's
Requests view is where approved items land). The chat sign-off Stop-gate (separate harness
work). Inline Inbox answering (v1 ships pointer + copyable stub; see the PENDING decision).

## Closure Contract
All 9 tasks two-gate verified (rung 3); advocate pass green over the 9 scenarios; operator
walkthrough done on the new surface; deployed to :7733 (+ peer machines); cockpit-ui-polish
flipped SUPERSEDED; the standalone My-To-Do pane retired into the Inbox.

## Testing Strategy
Extend cockpit.selftest.js: structural (six-value statuses incl. unknown + merged-unverified,
quarantine placement + Inbox-count exclusion, badge cap, aging states, roll-up badges +
precedence order) + FOUR-STATE assertions per new view (the T13-21 pattern: loading / error /
filtered-vs-true empty / ideal, win-state-only-on-success) + A11Y assertions per new view (the
R20-R22c pattern extended: details-based disclosure present, focus-visible reachable, aria-live
on edit feedback, text alternative for every color signal) + one state-preserving-re-render
assertion per view (expansion + scroll + focus + uncommitted edits survive a poll tick).
Extend server.selftest.js: derivation oracles incl. the three-class complete-oracle fixtures,
unknown-on-input-failure (no default-guess branch), title-precedence fold (operator beats
newer auto), roll-up computation, and the no-spawn-on-GET pin. Peer-view suite: event-path
timing + idle-machine keepalive (the floor runs the exporter when clean). Advocate runtime as
the user-path oracle.

## Walking Skeleton
Task 1 first, alone: the derived status of ONE real archived plan rendering correctly end-to-end
(fixes the loudest live defect before any view work).

## Decisions Log
- (2026-07-18) Synthesis decisions from the sit-down, all operator-confirmed: one-registry-three-
  views; per-item statuses (no waterline); production-functional complete; in-place-7d/subtree/
  roll-up completed aging (operator asked for recommendation; this is it — one-number tunable);
  chips-not-swimlanes (nodded); auto-name-always-editable; harness chores excluded; event-hybrid
  publish with keepalive floor; person grouping. Inputs doc is authoritative for verbatim intent.
- (2026-07-18) DELTA REVIEW FOLD (decide-and-go, all six residuals from the PASS-WITH-CONCERNS
  delta review): R1 win-state scoped to answerable section (quarantine/"My items" never defeat
  it); R2 roadmap_rank reorder = keyboard-operable buttons, drag optional (WCAG 2.2 2.5.7);
  R3 "blocks:" links `#roadmap/<id>` + "open source session" targets Harness Health drill-in
  else copyable resume command; R4 roll-up = one badge PER class, precedence orders never
  selects; R5 kanban exceptional columns (merged-unverified, unknown) render only when
  non-empty; R6 tree's at-birth filter hatch = substring filter box, chips are facets only.
- (2026-07-18) ACTIVATED: Check 17 satisfied — architecture-review SOUND-WITH-AMENDMENTS +
  ux delta PASS-WITH-CONCERNS, all amendments folded. cockpit-ui-polish.md flipped SUPERSEDED
  (absorbed by tasks 6+8).
- (2026-07-18) **Review fold (this revision).** Both gate reviews folded into task text:
  architecture A1-A10 (all binding amendments) + UX C1-C9 Criticals, I1-I6 Importants, and the
  severity-1 roll-up-exemplar polish. Cross-review adjudications (decide-and-go, all reversible):
  (a) `roadmap_rank` DEFAULT = plan-creation (registry insertion) order, not the arch review's
  alternate "recency" — the review offered either; a stable reading order serves "the order they
  are intended to be built" (round 2), where recency churn would reorder the list under the
  operator daily.
  (b) Roll-up badge precedence extended with `unknown` at the tail (waiting-on-you > crashed >
  blocked-on > limit-parked > unknown) — C1 ordered the stalled reasons only; C5 requires
  unknown to propagate; concrete operator-actionable stalls outrank an indeterminate state.
  (c) A10 resolved as: the Inbox SUPERSEDES the My-To-Do pane; operator-authored items become a
  "My items" section within the Inbox (todo.js machinery retained), excluded from Inbox (N) —
  one waiting surface, counts can never disagree (subsumes the review's "canonical surface +
  pointer mirror" framing without keeping two competing panes).
  (d) Kanban "four columns" (I3) reconciled with the six-value enum (C5/A4): four core columns;
  merged-unverified and unknown are their own labeled columns, never inside Complete.
  (e) Acceptance scenario 1 hardened from "or honestly 'merged, no deploy signal'" to
  complete-PROVEN via merged-is-deployed, per A4 — the harness HAS a mechanism-true deploy
  signal.
- (2026-07-18) **PENDING — operator decision (build proceeds on the default).** Inbox v1
  answering: INLINE (type the answer in the cockpit, routed back to the session / the NEEDS-YOU
  ledger — real routing machinery, a bigger task 4) vs POINTER+STUB (the item names the exact
  channel + a copyable reply stub; answering happens in the named channel). BOTH reviews lean
  pointer+stub for v1 (UX review "Questions for the user" §1; arch review is silent = no
  objection). DEFAULT: pointer+stub — task 4 builds it unless the operator overrides; inline
  answering is then a candidate follow-on task, not a rework.
