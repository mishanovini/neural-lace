# Architecture review — cockpit-roadmap-redesign (Check 17 gate)

Reviewer: architecture-reviewer (Fable) · Date: 2026-07-18 · Subject:
`docs/plans/cockpit-roadmap-redesign.md` (DRAFT) against the verbatim record
(`docs/reviews/2026-07-17-cockpit-ux-design-input.md`), the expert proposal
(`docs/reviews/2026-07-17-cockpit-ux-redesign-proposal.md`), and the live code.
All numbers measured 2026-07-18 on this machine unless cited otherwise.

VERDICT: SOUND-WITH-AMENDMENTS
THE ONE THING: Task 4's needs-you lint warn->BLOCK, as written, silently drops
waiting-on-operator items on the MECHANICAL add paths (stop-verdict-dispatcher,
session-resumer park, session-honesty-gate PAUSING) and reverses the shipped
"the ledger never rejects" contract (needs-you.sh:556 "added anyway — the
ledger's availability outranks its lint"). A lost waiting-item is the exact
origin-story failure this cockpit exists to kill — respecify before ACTIVE:
block only the interactive/model-invoked surface; mechanical callers store-and-
quarantine (the task's OWN quarantine already handles them).

---

## PHASE 0 — independent derivation (written before reading the plan in detail)

**Real problem** (three distinct problems, not one): (P1) the four-bucket
roadmap frame is absent — lifecycle is declared, never derived, so an 18/18-done
merged ask renders ACTIVE (a confident lie, live-proven in the proposal);
(P2) labels are garbage — prompt-fragment titles, 718 identical "drift" chips;
(P3) waiting-on-operator items reach the operator without context (§3
violations). Plus a smaller transport problem: publish latency <=20min when the
operator wants ~1min on real change.

**Forces:** writer hooks never block; hooks are git-blind (cherry-pick is the
default orchestrator flow); bash spawn ~87ms typical, 94-119s measured worst
case under AV pressure (derive-lib.js:337-341); N machines / ~59 worktrees —
no machine-global read-modify-write; absence must never render as zero;
unmerged must never render as done; anti-noise + absolute-links laws; no
fork/oracle on any GET path (peer-view.js request-path discipline).

**The invariant (one sentence):** every status the cockpit shows must be
derivable at read time from mechanism-emitted, single-writer ground truth, with
absence/staleness/unknown as named states — never a confident lie.

**My candidate design:** keep the pull-at-read derivation (the only shape with
no drift class at all); re-root the PRESENTATION as a work-item lifecycle
tree; titles/amendments as new append-only registry fields with source-tagged
fold precedence; complete = per-project tiered oracle with explicit unknown;
publish = writer-lib dirty-marker + debounced full cycle + preserved periodic
floor. **Sacrifices:** no guaranteed amendment detection (async classification
+ operator correction, honestly labeled); per-project oracle config burden;
title quality depends on an LLM call.

**Divergence from the plan:** the plan matches this derivation on the load-
bearing shape — one registry, no new store, derived status, hybrid publish.
That skeleton is right and visibly absorbs every prior architecture-review scar
(v2 store, keepalive honesty, git-blind hooks). The divergences are task-level
specs, and in each the plan is wrong: the amendment "splice" claims a mechanism
no hook can implement (F2); the lint block reverses a shipped contract (F1);
title fold precedence, publish-floor mechanics, landing-path spawn ban, and
roadmap ordering are unspecified where silence will produce the wrong build
(F3, F5, F6, F7).

## LOAD-BEARING PREMISES (tested)

For this design to be right, ALL of the following must be true:
1. *The ask registry can be the work-item registry with added fields.* ->
   TRUE (append-only JSONL, reader fold, derive-lib.js:104-125) — BUT the fold
   is last-non-empty-wins in ts order, which makes this FALSE for `title`
   without a precedence rule (F3).
2. *Status derivation reads existing data only.* -> MOSTLY TRUE: plan-parse,
   raw heartbeats (25 files, 1.2ms measured), merge SHAs (events + merge-scan
   GUARANTEED lane) all exist. Deploy evidence: PARTIALLY TRUE — a real,
   age-guarded prod-deploy oracle already exists in this codebase
   (work-in-motion-sweep.js:386-583, conservative by construction) but feeds
   the retired tree-state model; and the harness project has a mechanism-true
   deploy signal the plan never names (session-start-auto-install syncs live
   from origin/master, so merged IS deployed for harness work) (F4).
3. *A capture splice can detect "scope-modifying conversation turns".* ->
   FALSE. UserPromptSubmit delivers raw prompt text (settings.json.template:
   483-500); no hook sees intent. As written this is a vaporware mechanism —
   constitution §1: no mechanism, say so (F2).
4. *Promoting the cold-reader lint to BLOCK is safe.* -> FALSE. `needs-you.sh
   add` is invoked mechanically by stop-verdict-dispatcher.sh:45 (unresolved
   gaps), session-resumer.sh:2079/2858 (LIVE park), session-honesty-gate.sh:
   454/927 (PAUSING marker); the shipped contract is ledger-never-rejects
   (needs-you.sh:556). A block on those paths means the item lands NOWHERE (F1).
5. *Event-triggered publish preserves idle-vs-dead honesty.* -> TRUE ONLY IF
   the periodic floor runs the FULL cycle including the exporter: the A3ii
   keepalive stamp is only written when the exporter runs (export-state.js:
   207-230, KEEPALIVE_MS=60min), and peer-view classifies peer-unreachable past
   ~80min (peer-view.js:34-49). A naive "if clean: exit 0" breaks it (F5).
6. *Derived complete never lies.* -> UNRESOLVED: the "merged, no deploy signal"
   fallback does not say which BUCKET it lands in (F4).
7. *The roadmap can render "in the order they are intended to be built".* ->
   FALSE today: no ordering field exists in the registry; no writer named (F7).
8. *Quarantine auto-defect cannot storm.* -> NOT ESTABLISHED: no dedup named;
   the auditor's filed-once-per-divergence-lifetime pattern exists
   (auditor.js:185-193) but the plan does not bind it (F8).

## FINDINGS (ranked; severity = blast-radius x likelihood x irreversibility)

**F1 [HIGH] [failure-mode-first + precedent search] [PROVEN needs-you.sh:556;
stop-verdict-dispatcher.sh:45; session-resumer.sh:2858; session-honesty-
gate.sh:927]** — Task 4's warn->BLOCK breaks mechanical add callers.
Failure scenario: a Stop-gate gap or a park notice fails the lint heuristic ->
add exits nonzero inside a best-effort hook -> the waiting-item never reaches
NEEDS-YOU.md or the Inbox. What the user sees: nothing — a decision that was
waiting on them simply does not exist anywhere. SILENT; the system does not
know. This is the worst class in the hierarchy (wrong-and-silent) applied to
the surface whose entire mandate is "never lose a thing waiting on me." It
also violates constitution §10: a new blocking gate needs a golden scenario
(named) + expected false-positive rate (absent) + retirement condition
(absent). Required change: block ONLY the interactive/model-invoked add (the
session sees the error and retries with context — a teaching gate); hook/
mechanical callers pass a flag that stores-and-quarantines instead (the
ledger never rejects; the task's own quarantine + auto-defect is the
enforcement for that path). Add the FP-rate estimate and retirement condition.

**F2 [HIGH] [mechanism-claim test] [PROVEN settings.json.template:483-500 —
UserPromptSubmit carries text, not intent]** — Task 2's "capture splice for
scope-modifying conversation turns" is not buildable as specced; no
deterministic hook can classify intent, and shipping the phrase as-is invites
a builder to fake it with keyword matching or model memory. Required change:
respecify as the three-layer mechanism that IS buildable: (a) mechanical
capture — a UserPromptSubmit splice appends EVERY operator prompt in an
ask-attached session as a timeline candidate (transcript ref + offset, never
full text — the registry stays small); (b) classification — the SAME async
off-hot-path LLM lane the plan already assumes for title distillation marks
candidates amendment/noise; (c) correction — operator edit/delete on the
timeline, plus an explicit `ask-registry.sh amend` verb as the model-invoked
supplement (labeled memory-dependent). State the residual gap honestly in the
plan: amendment detection is best-effort classification, not a guarantee.

**F3 [HIGH] [single-writer / derived-state] [PROVEN derive-lib.js:105-125 —
last-non-empty-wins fold in ts order; plan Assumption "distillation is
async"]** — Two writers of `title` with no precedence: capture t0 -> operator
edits title t1 -> async distiller lands t2>t1 -> the operator's title is
silently reverted. What the user sees: their own edit undone; trust in
editing dies (round 3's "always modifiable by me" betrayed). SILENT. Required
change: title records carry `title_source: auto|operator`; fold rule:
operator-sourced ALWAYS outranks auto regardless of timestamp; the UI's title
edit delegates to ask-registry.sh (same one-writer-implementation discipline
as the existing lifecycle endpoint, server.js:1004-1057). Same rule for any
future distiller re-runs.

**F4 [MED-HIGH] [failure-mode-first + reverse Chesterton] [PROVEN
work-in-motion-sweep.js:246-583 (existing deploy oracle); session-start-auto-
install (harness deploy mechanism)]** — Complete-oracle bucket ambiguity, in
both directions. The plan's fallback "merged + labeled 'no deploy signal' —
never silently complete" does not say which bucket the fallback renders in:
put it in Complete-with-a-label and a deploy-required Circuit item rides to
Complete without reaching production (the confident lie the operator's
round-3/4 definition explicitly forbids); keep it out and harness items sit
"incomplete" forever (everything-forever-in-progress, the other betrayal).
Both are avoidable because the evidence is better than the plan thinks:
(a) the harness project has a mechanism-true deploy signal — merged-to-master
auto-installs live via session-start-auto-install; doctor green is the
functional signal — so the 18/18 rebuild is complete-PROVEN, not "no deploy
signal"; (b) an age-guarded prod-deploy oracle already exists
(work-in-motion-sweep) and should be PORTED, not re-derived. Required change:
a small per-project completion-oracle config with three named classes —
`deploy-oracle` (Ready-style check, deploy strictly newer than merge) /
`merged-is-deployed` (harness: install mechanism + doctor) / `no-signal` —
and the binding rule: `no-signal` renders as a DISTINCT "merged — deploy
unverified" state OUTSIDE the Complete bucket, with a labeled per-item
operator override to complete. Acceptance scenario 1 should then expect
complete-PROVEN for the rebuild, not the fallback label.

**F5 [MED-HIGH] [failure-mode-first + hot-path] [PROVEN export-state.js:53,
207-230; peer-view.js:34-49; coord-sync.sh:31-42]** — Task 7's publish
mechanics need four bindings or the build will be wrong:
(i) The floor runs the FULL cycle (exporter+push+pull) at <=600s regardless
of the dirty marker. Two proven reasons: the A3ii keepalive stamp only
updates when the exporter runs — a naive "if clean: exit 0" freezes
`exported_at` and every healthy idle machine renders peer-unreachable within
~80min (the exact idle-vs-dead honesty the operator is probing); and
git-blind mutations (cherry-pick/pull) produce no dirty marker — the floor is
their only coverage.
(ii) Marker cleared BEFORE reading state for export, so an event landing
mid-export re-dirties and the next cycle republishes; clear-after loses that
update (classic dirty-flag lost-update).
(iii) Marker touched at the WRITER-LIB seam (progress-log-lib.sh emit +
ask-registry.sh append), not in hooks — hook-layer-only placement misses the
GUI's own delegated CLI writes (lifecycle, title edits) and every future
writer. The plan's Files-to-Modify says "emission splices (dirty-marker)":
wrong seam.
(iv) Cadence cost bound: a 60s scheduled fire spawns bash — measured 94-119s
worst case here, i.e. permanent overlap under AV pressure. The existing mkdir
lock + IgnoreNew bound this (coord-sync.sh:31-42), but verify the 900s
lock-stale threshold at the new cadence and log marker-check-only fires
distinctly so cycles.log stays readable.

**F6 [MEDIUM] [hot-path cost model] [PROVEN — measured 2026-07-18: full
landing derivation 20.0ms over 3 asks / 1,015 events (531KB largest log) / 25
heartbeats; raw heartbeat read 1.2ms; vs bash spawn ~87ms typical, 94-119s
worst; classifySessions = a spawn with a 180s timeout, derive-lib.js:297-343,
today detail-path only]** — Task 1's "in-progress = live session activity" on
every roadmap item invites a builder to put classifySessions on the landing
path: one spawn per request, 180s worst case — a >4,000x regression against
the measured pure-read path. Required change: bind in the task text + the
selftest: roadmap/landing derivation uses `listRawHeartbeats` + pure-JS age
classification (the peer-view A3c precedent) — NO child-process spawn on any
GET path. Also: use the heartbeat lib's own classes (throttled/stale are not
crashed) plus an activity window (the proposal's T~24h disjunct, which the
plan dropped) so a long build under AV pressure does not flap
in-progress -> "stalled: crashed" -> in-progress — a false "crashed" is a
confident lie in the one status the operator explicitly asked to trust
(round 2: stalled "should tell me WHY").

**F7 [MEDIUM] [premise test / synthesis drift] [PROVEN ask-registry.sh verb
list — no ordering verb; fold fields derive-lib.js:110]** — The operator's
round-2 requirement is "lists all the plans in the order they are intended to
be built"; the plan says "priority-ordered" with no field, no writer, no
affordance — no data source exists. Builders will invent an implicit order
(insertion or recency) and the stated need silently degrades. Required
change: name the mechanism (e.g. `roadmap_rank` records on the registry,
operator-editable via UI delegation; default recency) OR log an explicit
deferral (order = activity-recency until Circuit promote assigns rank).
Either is fine; silence is not.

**F8 [MEDIUM] [silent-healing / storm test] [PROVEN auditor.js:185-193 +
fileNlIssueDivergences — the filed-once + recurrence-escalation pattern
already exists]** — Task 4's quarantine auto-defect names no dedup, no filing
site, and no producer for legacy items (buildWaitingItems falls back to
session_id:''). Unbounded risk: one legacy context-less item files a defect
per render/cycle forever. Required change: file in the AUDITOR cycle only
(never on render), keyed by ledger item id, once per item lifetime, reusing
the auditor's nl-issue state pattern; empty-session legacy items file against
the ledger id; recurrence escalates rather than re-files. Classification
should reuse the `lint_warnings` needs-you.sh already stamps at add — never a
second heuristic.

**F9 [LOW-MED] [labeling/scope]** — "Harness chores excluded" (operator B) has
no pinned classifier. By provenance (operator-requested vs machine-filed:
nl-issue/findings/auto-sweep), NOT by subject matter — else operator-requested
harness work (the rebuild itself) vanishes and the roadmap opens near-empty.
Pin it in task 3.

**F10 [LOW] [decomposition]** — Inbox (view 3) vs the retained My-To-Do pane
(task 8): two "waiting on me" surfaces whose counts can disagree. State the
relationship (Inbox = the canonical waiting surface; To-Do = personal freeform
+ pointer mirror) in task 4/8 so the two never compete.

**Synthesis-drift audit vs the verbatim record:** otherwise faithful. Verified
specifically: no-waterline honored (round 4-4); auto-name-always-editable
honored — and the plan correctly DROPS the proposal's name-at-promote confirm
ceremony, which round 3 rejected (good synthesis); completed-aging is the
recommendation the operator asked for, logged; round-5 hybrid publish
faithfully carried (F5 is mechanics precision, not drift). The real drifts
are F7 (build order — a requirement dropped) and the F1/F4 ambiguities above.

## PRE-MORTEM (six months later, it failed)

Week 3: a stop-gate gap add fails the now-blocking lint inside a best-effort
hook; the item lands nowhere; the operator misses a blocking decision for nine
days and finds it in a transcript — the cockpit caused the failure it was
built to kill. Week 5: the operator renames a card; an async distiller from a
resumed session clobbers it overnight; they stop editing titles. Week 8: a
builder shipped "idle when clean"; over a quiet weekend every idle machine
goes peer-unreachable; the peers panel is declared broken and ignored. Week
10: AV pressure makes heartbeats flap; cards oscillate in-progress <->
"stalled: crashed"; the operator learns to ignore STALLED — the one status
they asked to trust. Throughout: the roadmap renders in registry-insertion
order; the operator quietly goes back to reading plan files to know what is
next. Every failure is silent; nothing in the system knows it is broken.
Each maps to F1/F3/F5/F6/F7 — all preventable now.

## Steelman

**The cheapest alternative (do-less: derived statuses + badge cap + titles on
the EXISTING surface; skip the three-view re-IA):** fixes the three loudest
live defects (done-renders-ACTIVE, 718 chips, garbage titles) for roughly a
third of the cost, on a surface already two-gate verified. This is a genuinely
strong option and the plan should not pretend otherwise. Why it still loses:
the four-bucket frame and the request-evolution ledger are the operator's
PRIMARY stated need across five rounds ("the thing I'm really looking for"),
and a lifecycle chip on a project-grouped tree still leaves the glance job
unanswerable (the grouping dimension is the defect, not the chip); the Inbox
context mandate has no home in the current IA at all. The plan's walking
skeleton (task 1 alone, then task 6) already IS the do-less core shipped
first — the sequencing captures the alternative's value.
**Doing nothing:** untenable — the surface's headline claim is a live
confident lie (18/18 merged renders ACTIVE) and the operator has recanted the
frame on the record, five rounds deep.
**The design itself:** no new store, no new writer, no new drift class;
derivation extended, presentation re-rooted; round 5 shows the v2-store scars
were learned, not just survived. The bones are correct.
**THE CROSSOVER:** the plan wins iff the amendments land. It loses — to the
do-less alternative — if F1..F5 ship as written, because each converts a
today-honest surface into a silently-lying one, and an honest small cockpit
beats a lying big one every time.

## What the current design gets right (and this must not lose)

1. Pull-at-read derivation — correct by construction, no store to corrupt, no
   bootstrap, sees git ops for free; the ONLY shape with no drift class (the
   v2 lesson, paid for once already). No builder may "optimize" statuses into
   a materialized store.
2. Ledger-never-rejects + writer-splices-never-block (F1 preserves this for
   mechanical paths).
3. The `in_flight` signal derived from task_started x unflipped checkbox x no
   task_done (derive-lib.js:239-268) — the v2 replacement destroyed this
   once; heartbeat-only "in progress" would destroy it again.
4. Absence/failure as named states everywhere — rc carried to panes,
   defect-form waiting items, peer provenance labels, estate-unchanged vs
   peer-unreachable. Every new view inherits this bar.
5. Payload-schema allowlist + anti-noise enforcement at the one seam — the
   new views extend the existing validators, never grow their own.
6. One writer implementation per store — UI writes delegate to
   ask-registry.sh; the auditor's filed-once dedup; the port-bind single-
   instance guard. The new fields (title, amendments, rank) ride the same
   discipline.

## WHAT WOULD CHANGE MY VERDICT

To NEEDS-RESHAPING: refusal to amend — lint blocking retained on mechanical
add paths; a materialized status store; hook-layer-only dirty markers; or
"no deploy signal" rendering inside the Complete bucket. To SOUND (no
amendments): evidence that mechanical callers cannot emit lint-failing text
(they can — gap/park text is arbitrary), that the distiller cannot race an
operator edit (it can — it is async by the plan's own assumption), or a
demonstrated deterministic amendment classifier (none exists on any hook
surface).

## Required amendments (binding for the ACTIVE flip)

A1 (F1): Task 4 — lint blocks interactive/model add only; mechanical callers
store-and-quarantine (a --mechanical flag or equivalent); add FP-rate +
retirement condition per constitution §10.
A2 (F2): Task 2 — respecify amendment capture as capture-all-prompts (refs) +
async LLM classification + operator correction + explicit amend verb; state
the best-effort gap in the plan.
A3 (F3): Task 2 — title_source on title records; operator-beats-auto fold
precedence; UI edits delegate to ask-registry.sh.
A4 (F4): Task 1 — per-project completion-oracle config (deploy-oracle /
merged-is-deployed / no-signal); no-signal renders OUTSIDE Complete as
"merged — deploy unverified" with labeled operator override; harness =
merged-is-deployed (auto-install + doctor); port the work-in-motion-sweep
deploy oracle.
A5 (F5): Task 7 — floor runs the full exporter cycle at <=600s regardless of
marker; clear-marker-before-export; marker at the writer-lib seam; cadence
overlap bounded by the existing lock (verify thresholds).
A6 (F6): Tasks 1/3 — no child-process spawn on any GET path; landing liveness
via listRawHeartbeats + JS age classes incl. throttled-vs-crashed + activity
window; selftest-pinned.
A7 (F7): Task 3 — name the roadmap-order mechanism or log the explicit
deferral.
A8 (F8): Task 4 — auto-defect files in the auditor cycle, once per
ledger-item lifetime, reusing the auditor's dedup state; legacy items keyed
by ledger id.
A9 (F9): Task 3 — chore classifier = provenance, pinned.
A10 (F10): Tasks 4/8 — Inbox vs My-To-Do relationship stated.
