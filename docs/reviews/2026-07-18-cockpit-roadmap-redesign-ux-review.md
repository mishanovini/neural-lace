# UX Review: Cockpit roadmap redesign — Requests / Roadmap / Inbox (plan-time)

**Plan:** `docs/plans/cockpit-roadmap-redesign.md` (Status: DRAFT)   **Reviewed:** 2026-07-18
**Audience:** solo technical founder glancing between meetings; many parallel autonomous
sessions; +1 teammate (Jaime) soon; desktop-primary (no-phone-observability directive).
Persona source: the operator-authored brief (`docs/reviews/2026-07-17-cockpit-ux-design-input.md`)
— no `.claude/audience.md` exists (checked).
**Verdict:** **FAIL** — Critical spec gaps must be folded into the plan before build. This is
the expected outcome for a plan whose three views are specced in ~15 lines: the plan's own
Architecture-review line gates the ACTIVE flip on this review, and every fix below is a
plan-text amendment, not a redesign. The plan's DIRECTION is right and faithful to the
five-round brief, with one substantive drift (Critical 6).

**Method:** Nielsen H1-H10; cognitive walkthrough (4 questions/step) over the operator's core
loop ("glance: what moved? what's stalled? what's next?"); four-UI-states audit per surface;
NN/g empty-state guidelines; WCAG 2.2 AA. Code claims verified in this worktree:
`neural-lace/workstreams-ui/web/app.js` (tab switching is DOM-only — zero hash/pushState;
`location.reload()` at app.js:1036 wipes client state), `asks.js:1076-1090` (load-once, full
re-render), existing pane-state conventions (`asks.js:169-205`; app.js:185 "NEVER the empty
state on failure") and a11y conventions + selftest anchors (`app.css:121,898`,
`todo.js:155-190`, `cockpit.selftest.js` R20-R22c, T13-21, T16-8).

**Drift-vs-brief check:** one substantive drift found — the plan ships Requests-to-Roadmap
("became ->") but not Roadmap-to-Requests, and the round-1 verbatim asks for the reverse
direction ("how it maps back onto the specific requests that I've made") — see Critical 6.
The apparent tension between "recently-completed stays visible in place" (round 4) and "a
fully complete subtree collapses to its headline immediately" (plan) is NOT drift — the
operator floated the collapse themselves — but it needs the recency cue in Important 1 to
serve both intents at once.

---

## Critical gaps (severity 3-4 — build-blocking)

1. **Stalled work invisible under collapsed parents — no status roll-up law.**
```
- Line(s): Plan Outcome section 2 (lines 26-31) + task 1 (lines 50-56) + task 3 (lines 61-64)
  Defect: Per-item status is derived, but no parent aggregation rule exists: a collapsed parent
    whose deep descendant is STALLED(waiting-on-you) renders "in-progress + progress bar" — the
    glance question "what's stalled?" reads confidently WRONG (H1 visibility; Gulf of
    Evaluation; the prior proposal's D5 defect reborn one level up, in the surface built to
    kill it).
  Severity: 4 (Critical) — frequency: every glance with any collapsed stalled descendant (the
    default tree view is collapsed; stalls are WHY the operator glances); impact: confident
    wrong signal on the core loop's highest-value question; persistence: until full manual
    expansion, i.e., never at glance speed.
  Confidence: PROVEN — tasks 1 and 3 define per-item states and child-count progress bars;
    no roll-up/propagation rule appears anywhere in the plan.
  Class: masked-descendant-state
  Sweep query: rg -n "stalled|roll-?up|propagat|ancestor|parent" docs/plans/cockpit-roadmap-redesign.md
    (confirms absence); build-time: rg -n "status" neural-lace/workstreams-ui/server/derive-lib.js
    — every site computing a parent status must apply the law.
  Required fix: Add a roll-up law to task 1: attention states propagate upward — every collapsed
    ancestor of a stalled item shows a counted, labeled badge ("1 stalled — waiting on you")
    beside its own status chip; badge click expands the path to the stalled item; precedence in
    the rolled badge: waiting-on-you > crashed > blocked-on > limit-parked.
  Required generalization: EVERY leaf-derived attention signal (stalled, waiting-on-you,
    quarantined, unknown-status per Critical 5) gets a defined collapsed-ancestor rendering —
    audit all of them against the roll-up law, not just stalled.
```

2. **No navigation shell, no cross-view addressing — the mandated "->Inbox link" is
   unbuildable as specced, and Back exits the app.**
```
- Line(s): Plan Outcome sections 1-3 (lines 22-37); task 1 line 54 ("waiting-on-you(->Inbox
    link)"); task 4. Code: web/app.js — tab switching is DOM-only (aria-selected flips at
    app.js:1020-1021); grep for hash/pushState/history returns only location.reload
    (app.js:1036).
  Defect: The plan never specifies the navigation shell (three tabs? which view lands first?),
    an Inbox count affordance, or ANY addressing mechanism for the cross-view links it mandates.
    Today's app has no URL routing, so "click the stalled reason -> land on THE Inbox item ->
    come BACK" has no mechanism; browser Back exits the whole app (H3 — no emergency exit;
    cognitive-walkthrough Q4 fails on the return leg of the designed unblock path).
  Severity: 3 (Critical) — frequency: every stalled->Inbox click (the primary designed path
    for unblocking work) plus every visit (landing/count); impact: dead end or whole-app exit
    at the moment of highest intent; persistence: structural.
  Confidence: PROVEN for code (no routing exists — cited lines); PROVEN for plan (no
    nav/landing/back/addressing wording in any task).
  Class: unaddressable-cross-view-link
  Sweep query: rg -n "link|land|back|becomes?|->" docs/plans/cockpit-roadmap-redesign.md —
    every cross-view arrow is an instance (stalled->Inbox, became->plan, Inbox->source-session,
    roadmap->request per Critical 6); each needs address + landed-state + return path.
  Required fix: Spec in the plan: three tabs — Roadmap (landing: the glance surface),
    Requests, Inbox with a live headline count "Inbox (N)" (excluding quarantined items,
    Important 4); hash-based item addressing (#inbox/<id>, #roadmap/<id>, #request/<id>) so a
    cross-view link switches tab + scrolls + expands + visibly highlights + moves programmatic
    focus to the item; return = browser Back (hashchange) AND an explicit "back to roadmap"
    affordance on the landed item, restoring the prior tab with tree expansion + scroll intact
    (pairs with Critical 7).
  Required generalization: every cross-view arrow in the plan gets four specs: target address,
    landed state (focused/expanded/highlighted), return path, and miss behavior (target
    resolved or gone — see Critical 3's stale-link rule). No unaddressed arrows.
```

3. **The Inbox has no answer path and no resolution lifecycle — a dead end at the moment of
   highest intent.**
```
- Line(s): Plan Outcome section 3 (lines 33-37) + task 4 (lines 65-68)
  Defect: The context contract specs what an item CONTAINS but not what the operator DOES with
    it: no answer affordance or answer-routing is defined, and no resolution rule (when/how an
    answered item leaves the Inbox). The operator reads the decision, decides... and the
    surface offers nothing (walkthrough Q2/Q3 fail at the action moment). Unspecified cleanup
    means answered items linger, "Inbox (N)" overstates, and the win state ("nothing waiting
    on you") never renders — the 18/18-renders-ACTIVE trust failure transplanted to the Inbox.
  Severity: 3 (Critical) — frequency: every Inbox item; impact: dead end + headline-count
    decay on the surface whose one job is "what needs me"; persistence: permanent until
    specced.
  Confidence: PROVEN — task 4 covers only quarantine + lint promotion; no answer/resolve/
    dismiss verb appears anywhere in the plan.
  Class: dead-end-at-action-moment
  Sweep query: rg -n "answer|resolve|dismiss|clear" docs/plans/cockpit-roadmap-redesign.md —
    zero lifecycle verbs for the Inbox. Contrast: Requests DOES define its exit
    (close-on-promote) and Roadmap defines its aging — the Inbox is the one view missing its
    exit.
  Required fix: Add to task 4: each item carries (a) an answer affordance — v1 minimum: a
    "how to answer" line naming the exact channel (reply in session <id> / the NEEDS-YOU.md
    entry) with a copyable reply stub; (b) a resolution rule — the item leaves when the
    canonical ledger entry clears/is-answered, or on operator dismiss (dismiss = labeled
    override, consistent with the derivation law); (c) stale-link behavior: a followed link to
    a resolved item renders "resolved <when> — <outcome>", never a blank or 404.
  Required generalization: every view's item type defines all three lifecycle verbs at plan
    level — how it arrives, what the operator does with it, how it leaves.
```

4. **The four UI states are unspecified on every new surface — including two distinct
   non-error empties the plan's own filters create.**
```
- Line(s): Tasks 3, 4, 5 (lines 61-70) — all three views spec only the ideal state. Code
    anchors: the binding convention already exists (asks.js:169-205 loading/error/empty with
    Retry; app.js:185 "NEVER the empty state on failure") but nothing binds the new views to
    it.
  Defect: No empty/loading/error state is specced for any view (H1; NN/g empty-state
    guidelines). Sharpest instances: (a) the Roadmap tree has TWO non-error empties —
    filtered-empty (harness-chore exclusion or a project chip can empty a REAL estate; must
    say "N items hidden (harness chores)" / "no items match <chip> [clear]") vs true first-use
    empty (must explain items arrive automatically from sessions — no setup ask); a bare
    "no items" reads as data loss to an operator whose trust was already burned by
    18/18-ACTIVE. (b) The Inbox empty is the WIN state and must be unmistakable from
    failed-to-derive — an unreadable ledger rendering as "nothing waiting on you" is a lying
    celebration (error-masquerading-as-empty, the worst of the four-state confusions).
  Severity: 3 (Critical) — frequency: filtered-empty is routine (chip clicks; chore exclusion
    is always-on); impact: perceived data loss / falsely suppressed asks; persistence: every
    occurrence.
  Confidence: PROVEN — grepping the plan for empty/loading/error state wording matches
    nothing; the convention exists in code, the binding does not exist in the plan.
  Class: unspecified-non-ideal-states
  Sweep query: build-time: rg -n "pane-empty|pane-error|pane-loading|aria-busy"
    neural-lace/workstreams-ui/web/*.js — each new view must show all three non-ideal states;
    plan-time: every surface named in Outcome sections 1-3 (tree, kanban, inbox list,
    quarantine group, requests ledger, evolution timeline panel) x 4 states.
  Required fix: Add one line per view to tasks 3/4/5 binding them to the existing pane-state
    convention with view-specific copy written in the plan: tree loading "deriving roadmap...";
    tree error = pane-error + Retry (never empty); filtered-empty names the filter + hidden
    count + one-click clear; true-empty explains auto-arrival; Inbox win state "Nothing
    waiting on you — all sessions running free. As of <time>." rendered ONLY on successful
    derivation; Requests empty explains auto-capture.
  Required generalization: every data-dependent surface in this plan ships all four states
    with copy in the plan, and cockpit.selftest.js grows T13-21-style four-state assertions
    per view (the plan's Testing Strategy currently lists structural checks only).
```

5. **The derived-status enum has no honest-failure value.**
```
- Line(s): Task 1 (lines 50-56): not-started / in-progress / complete / stalled; Outcome
    section 2 (lines 26-28); Testing Strategy (lines 133-136).
  Defect: When derivation inputs fail (plan-parse error, unreadable heartbeat, schema drift),
    there is no "unknown" state — the item must land in one of four confident buckets, i.e.,
    a confident wrong chip on the trust-bearing surface. This is precisely the defect class
    (18/18-renders-ACTIVE) the plan exists to kill, and it violates the harness's own
    absence-is-a-named-state law. The plan already does this RIGHT once — "merged + labeled
    'no deploy signal' — never silently complete" (lines 101-103) — but only for that case.
  Severity: 3 (Critical) — frequency: low-moderate (failures, drift, new lifecycle values);
    impact: maximal — silent wrong status; persistence: silent until someone notices.
  Confidence: PROVEN — the enum is listed three times, never with a failure value.
  Class: missing-honest-failure-state
  Sweep query: rg -n "not-started|in-progress|complete|stalled" docs/plans/cockpit-roadmap-redesign.md
    — every enum listing gains the fifth value; build-time: every return path in derive-lib.js
    must have no default-guess branch.
  Required fix: Add a fifth derived value — unknown(reason) — rendered as a visibly distinct
    labeled chip ("status unknown — plan parse failed") with the reason one click away;
    unknown propagates to collapsed ancestors per Critical 1's roll-up law.
  Required generalization: every derivation in this plan (status, stalled-reason, progress
    fraction, complete-oracle, hostname-to-person map) names its failure rendering in the
    plan — the "no deploy signal" pattern applied uniformly.
```

6. **Roadmap-to-Request mapping is missing — the one drift from the operator's verbatim brief.**
```
- Line(s): Plan Outcome section 1 (lines 23-25: "became -> <plan>" on the REQUESTS side only)
    + Outcome section 2 / task 3 (no provenance affordance on roadmap items). Brief: round-1
    verbatim, input doc lines 8-11 ("...and how it maps back onto the specific requests that
    I've made").
  Defect: The plan specs the Requests-to-Roadmap direction but not the reverse: a roadmap item
    never shows which request(s) produced it — yet the reverse direction is the one the
    operator verbatim asked for. (H6 recognition; information scent; proposal J3.) Task 2's
    data layer supports it (the registry IS the work-item store), so this is a render
    omission, not a data gap.
  Severity: 3 (Critical) — frequency: routine glance follow-up ("which ask was this?");
    impact: half the operator's stated mission statement unanswerable from the primary view;
    persistence: structural.
  Confidence: PROVEN — Outcome section 2 and task 3 contain no request/provenance affordance.
  Class: one-way-provenance-link
  Sweep query: rg -n "became|verbatim|provenance|request" docs/plans/cockpit-roadmap-redesign.md
    — list every relationship; confirm each renders in both directions or has a reasoned
    absence.
  Required fix: Add to task 3: every roadmap item's drill-down carries "from your request(s):
    <title(s)>", linking (via Critical 2's addressing) to the ledger entry, with the resolved
    verbatim one click away (the existing Verbatim mechanism).
  Required generalization: every promote/became/derived-from relationship renders in BOTH
    directions, or the plan states why not.
```

7. **No refresh model: statuses go stale (load-once) or the tree wipes the operator's
   expansion state (naive re-render).**
```
- Line(s): Tasks 3-5 (silent). Code: asks.js:1076-1090 (load-once, full re-render; expansion
    state lives only in the DOM); app.js:1036 (location.reload on ui_build change);
    app.js:160 (30s poll exists for health panes only).
  Defect: No refresh model is specced for the three views. Inheriting the asks-pane pattern
    means the "live" statuses are page-load snapshots — an H1 failure on a surface whose
    entire pitch is current derived status. Naively adding poll + re-render instead wipes tree
    expansion, scroll, and in-flight title edits mid-read (state loss; H3). Either default is
    a defect; the plan must pick and spec the third option.
  Severity: 3 (Critical) — frequency: every glance (staleness) or every 30s tick (state
    loss); impact: stale trust-bearing data, or an unusable tree; persistence: structural.
  Confidence: PROVEN for code (load-once observed at cited lines); PROVEN omission in plan
    (no refresh/poll/SSE wording for the views).
  Class: state-loss-on-rerender (with unspecified-refresh-model)
  Sweep query: rg -n "innerHTML = " neural-lace/workstreams-ui/web/*.js — every full-clear
    re-render site is a state-loss site once polling lands.
  Required fix: Spec in task 3: the three views poll (the existing 30s tick is fine) with
    STATE-PRESERVING re-render — preserve the details-open set, scroll position, focus,
    uncommitted title edits, and the Critical 2 landing highlight; on refresh failure show the
    existing "derived <age> — STALE" treatment (app.js:176 pattern), never silent staleness.
  Required generalization: any auto-refreshing surface preserves expansion + scroll + focus +
    uncommitted edits; one selftest assertion per view.
```

8. **A months-old request is unfindable — no search, no closed-group spec on an
   append-forever ledger.**
```
- Line(s): Plan Outcome section 1 (lines 23-25) + task 5 (lines 69-70). Prior art: the
    proposal's missing-search-escape-hatch finding (severity 2-to-3 at volume) — never
    absorbed into the plan.
  Defect: Close-on-promote makes old requests CLOSED; the ledger is append-forever and
    auto-capture registers every session — yet the plan has no search, no filter, and no spec
    for how closed requests render. If closed default-hides (the natural build, mirroring the
    Completed group), the months-old lookup is IMPOSSIBLE, not just slow; if they stay
    visible, the ledger drowns in them. (H6 recognition-over-recall inverts; no escape hatch.)
  Severity: 3 (Critical) — frequency: occasional, but the job is operator-core ("keep track
    of the requests that I've made" — round 2); impact: job impossible under the likely
    default; persistence: worsens monotonically with the volume this very plan onboards.
  Confidence: PROVEN — grepping the plan for search/filter/find yields only Roadmap project
    chips (task 3).
  Class: missing-search-escape-hatch (second unabsorbed instance of the proposal's class)
  Sweep query: any surface that can exceed ~2 viewports is a sibling: requests ledger,
    roadmap tree at scale, "N completed" roll-ups, quarantine group.
  Required fix: Add to task 5: a filter box (substring over title + distilled intent +
    verbatim origin) + closed requests default-collapsed under age groups ("this week / this
    month / older") that search reaches inside ("closed (N)" expands).
  Required generalization: adopt the proposal's rule into the plan: any surface that can
    exceed ~2 viewports ships a filter escape hatch at birth, not at retrofit.
```

9. **The new surfaces are not bound to the codebase's WCAG conventions, and the selftest
   grows no a11y coverage for them.**
```
- Line(s): Tasks 3-5 + Testing Strategy (lines 133-136: "structural: statuses, quarantine,
    badge cap, aging states" — no a11y assertions). Code anchors that already do it right:
    app.css:121 (focus-visible), app.css:898 (24px min targets), app.css:147 +
    cockpit.selftest.js:127 (details/summary = native keyboard disclosure), todo.js:155-190
    (keyboard title-edit pattern: edit button + Escape cancel + focus management),
    selftest R20-R22c / T16-8 (a11y checks — all anchored to OLD surface ids).
  Defect: The plan builds the largest interactive surface yet (expand/collapse tree at every
    level, always-editable titles, filter chips, kanban toggle) with zero a11y wording. The
    concrete risks: a custom div-toggle tree (expand/collapse keyboard-unreachable — WCAG
    2.1.1 Keyboard), click-on-text-only title editing (no keyboard path), color-only status
    chips / progress bars / insertion markers (WCAG 1.4.1 Use of Color), sub-24px chip
    targets (WCAG 2.5.8 Target Size Minimum).
  Severity: 3 (Critical) — frequency: every keyboard/AT interaction with the PRIMARY surface;
    impact: primary surface unusable without a mouse; persistence: structural.
  Confidence: PROVEN that the plan contains no a11y wording and the Testing Strategy lists
    none for the new views; HYPOTHESIZED that a builder would drop the conventions — REFUTED
    if they inherit them anyway; the one plan-line that makes refutation unnecessary is free.
  Class: unbound-a11y-conventions-on-new-surface
  Sweep query: rg -n "aria-|details|summary|focus|keyboard" docs/plans/cockpit-roadmap-redesign.md
    (zero hits today); build-time: selftest gains per-view anchors mirroring R20-R22c.
  Required fix: Add to tasks 3-5: tree nodes use nested <details>/<summary> (the codebase's
    own native-keyboard pattern); title editing reuses the todo.js edit-button + Escape +
    focus-return pattern — never click-on-text-only; every status signal is text + color,
    never color-only (chips carry words; progress bars carry "4/9"; the insertion marker is a
    labeled chip "added mid-build"); interactive chips are real <button>s (inherits the 24px
    floor); the kanban toggle is an aria-pressed button.
  Required generalization: the Testing Strategy adds a11y assertions per new surface
    (details-based disclosure present, focus-visible reachable, aria-live on edit feedback,
    text alternative for every color signal) — the R20-R22c pattern extended to every view
    this plan creates.
```

## Important gaps (severity 2 — will cause confusion / rework)

1. **"What moved?" has no recency signal; immediate subtree collapse can hide the very
   completion the operator wants to notice.**
```
- Line(s): Plan Outcome section 2 (lines 29-31, completed aging) + task 3
  Defect: The glance loop's first question — what changed since I last looked? — has no
    signal: completed-2h-ago and completed-6d-ago chips render identically, and a subtree
    that completes COLLAPSES immediately with no "completed <when>" on its headline, so the
    day's biggest win reads as "one line disappeared" (H1). This finding also reconciles
    round 4's "recently-completed stays visible" with the collapse the operator themselves
    floated.
  Severity: 2 (Important) — frequency: every glance; impact: re-scan tax + missed
    completions; persistence: yes. Not Critical: the operator's verbatim questions are
    bucket-membership questions; "what moved" is the review brief's framing of the loop.
  Confidence: HYPOTHESIZED — the plan is silent on chip timestamps; REFUTED if chips are
    already intended to carry transition ages.
  Class: missing-recency-signal
  Sweep query: rg -n "ago|recent|age|timestamp" docs/plans/cockpit-roadmap-redesign.md —
    aging-OUT exists (7d), recency-IN does not.
  Required fix: Status chips carry transition age ("in-progress, 2h" / "completed 3d ago");
    a collapsed complete subtree's headline carries "completed <rel-time>"; transitions
    under 24h old get one subtle, non-color-only "new" treatment.
  Required generalization: every status-bearing chip in all three views (incl. Inbox item age
    and Requests "last amended") shows its age — app.js's formatAge already exists for this.
```

2. **The "added mid-build" insertion marker has no lifetime.**
```
- Line(s): Plan Outcome section 2 (line 29) + task 3
  Defect: No decay rule — the marker either persists forever (cumulative chip noise, H8) or
    vanishes at an undefined moment; its purpose (explain an unordered item's presence)
    expires once seen/aged.
  Severity: 2 — frequency: grows with discovered work (which this persona generates
    constantly); impact: chip noise on the glance surface; persistence: cumulative.
  Confidence: PROVEN omission.
  Class: unbounded-marker-lifetime
  Sweep query: rg -n "marker|chip|label" docs/plans/cockpit-roadmap-redesign.md — every
    transient annotation needs a lifetime rule.
  Required fix: The marker ages out on the same 7d tunable as completed aging (one knob, per
    the plan's own one-number-tunable decision).
  Required generalization: every annotation chip declares persistent-vs-transient; transient
    ones share the single aging tunable.
```

3. **The kanban toggle's card unit and persistence are undefined.**
```
- Line(s): Plan Outcome section 2 (line 31) + task 3
  Defect: What IS a kanban card — intents? plans? tasks? — and do the toggle + project-chip
    selections persist across visits? Ambiguity that yields build churn; a wrong unit makes
    the occasional-use kanban (operator round 2: "only occasionally") useless.
  Severity: 2 — frequency: occasional by the operator's own words; impact: rework risk more
    than user harm.
  Confidence: PROVEN omission.
  Class: underspecified-view-mapping
  Sweep query: rg -n "kanban|toggle|persist" docs/plans/cockpit-roadmap-redesign.md
  Required fix: One plan line (decide-and-go default, cheap to change): kanban cards =
    top-level roadmap items; four columns = the derived statuses with stalled visually
    distinct; same chips as the tree; toggle + chip selections persist (localStorage).
  Required generalization: every alternate view (kanban now; person-grouped peers in task 7)
    names its unit-of-card and its state persistence.
```

4. **Quarantine reads as the operator's chore, and its relationship to the Inbox count is
   undefined.**
```
- Line(s): Plan Outcome section 3 (lines 35-37), task 4, Edge Cases (lines 110-111)
  Defect: The mechanics are specced but the READING is not: nothing establishes "the system
    failed, not you" — a bare "needs context (session X)" chip reads as one more thing to
    chase. And whether quarantined items count toward "Inbox (N)" is unspecified — counting
    unanswerable items makes the headline overstate what actually needs the operator.
  Severity: 2 — frequency: per producer bug; impact: blame misdirection + count distortion on
    the trust-bearing count; persistence: until specced.
  Confidence: PROVEN — no copy/tone/count spec anywhere in the plan.
  Class: system-fault-reads-as-user-fault
  Sweep query: rg -n "quarantine|defect|producing session" docs/plans/cockpit-roadmap-redesign.md
  Required fix: Spec placement + copy: quarantined items sit BELOW answerable ones under
    "N arrived without context — defects filed against the producing sessions"; each shows
    what the system does know, the auto-defect link ("defect filed ->"), an "open source
    session" escape hatch, and dismiss; they are EXCLUDED from the Inbox (N) headline count.
  Required generalization: every system-failure surface (quarantine, unknown-status per
    Critical 5, coord-unreachable) names the failing component and shows the remediation
    already taken — the operator is never the implied actor for a system fault.
```

5. **Inbox item anatomy unspecified — and an operator-approved format already exists to
   reuse.**
```
- Line(s): Plan Outcome section 3 (lines 33-37) + task 4
  Defect: The context contract names the FIELDS (source, issue, trade-offs, what's-needed)
    but not order, hierarchy, or collapsed form — and the operator already approved an exact
    format for decisions put to them (constitution section 3 compact format, 2026-07-02).
    Not reusing it is an H4 consistency miss and a re-litigation risk.
  Severity: 2 — frequency: every item; impact: answer speed; the fields exist, the anatomy
    does not.
  Confidence: PROVEN omission.
  Class: unspecified-item-anatomy
  Sweep query: rg -n "contract|source|trade-off|needed" docs/plans/cockpit-roadmap-redesign.md
  Required fix — proposed anatomy, adopt into task 4:
    COLLAPSED ROW: type glyph + text label (decision / unblock) + the ask as ONE imperative
    sentence + source chip (session/plan) + age + "blocks: <item>" when it stalls live work.
    Sort: blocking-live-work first, then age.
    EXPANDED (the constitution section-3 compact format, rendered): 1. Decision/Action
    needed — one sentence, visually primary; 2. Context, five lines max, with links
    (provenance folded here: which conversation, when, verbatim one click); 3. Trade-offs
    table (Option / What happens / Cost-risk) — decisions only; 4. My pick + one-line
    reason; 5. Reply-with — the exact answers + what each triggers + the Critical 3 answer
    affordance.
    BELOW THE FOLD (collapsed details element): raw verbatim, session lineage.
  Required generalization: any operator-facing ask anywhere (Inbox, needs-you sign-offs,
    stalled reasons) renders the same section-3 anatomy — one format, learned once.
```

6. **Evolution timeline anatomy unspecified; auto-captured amendments have no correction
   path.**
```
- Line(s): Plan Outcome section 1 (lines 23-25), task 2 (lines 57-60), task 5, Edge Cases
    (lines 108-109)
  Defect: (a) Timeline order and collapsed default are unspecced — the story reads
    oldest-first, the glance needs latest-state-first; pick and spec both layers. (b) The
    amendment heuristic ("capture splice for scope-modifying turns") WILL mis-fire, and the
    plan's correction affordances (merge/split) exist at ITEM level only — a wrong amendment
    on a request's timeline is uncorrectable (H3 user control; undo for auto-capture).
  Severity: 2 — frequency: per mis-capture / per ledger read; impact: wrong history on the
    intent ledger erodes exactly the "I lose track of my requests" trust it exists to
    restore.
  Confidence: PROVEN — merge/split specced at item level; nothing at amendment level.
  Class: no-undo-for-auto-capture (with unspecified-timeline-anatomy)
  Sweep query: rg -n "amendment|splice|merge/split|timeline" docs/plans/cockpit-roadmap-redesign.md
  Required fix: Timeline: collapsed = title + one-line current state ("became -> <plan>" or
    "open, amended 2d ago"); expanded = oldest-first chronology, origin pinned first, every
    event dated, "became ->" as the terminal event. Amendments: each carries "detach" (marks
    not-an-amendment; feeds the heuristic) using the cockpit's existing undo-window pattern.
  Required generalization: every auto-captured record type (title, amendment, item, inbox
    entry) has an operator correction affordance — auto-capture without undo is a trust tax.
```

## Nice-to-have improvements (severity 1 — polish)

1. **Count-only roll-ups carry no scent.**
```
- Line(s): Plan Outcome section 2 (line 30, "N completed")
  Defect: "12 completed" says nothing about WHAT completed; one exemplar restores scent at
    the cost of a few words.
  Severity: 1 — polish; the expand affordance exists.
  Confidence: PROVEN (label specced as count-only).
  Class: countable-rollup-without-scent
  Sweep query: rg -n "N completed|more|all N" docs/plans/cockpit-roadmap-redesign.md
    neural-lace/workstreams-ui/web — every count roll-up is a sibling.
  Required fix: Roll-up label = count + latest title: "12 completed — latest: badge law".
  Required generalization: count roll-ups carry one exemplar wherever a title fits.
```

## Questions for the user

1. **Inbox answering, v1 scope:** when you answer a decision from the Inbox, do you want to
   TYPE the answer in the cockpit itself (routed back to the session / the NEEDS-YOU ledger —
   real machinery, a bigger task 4), or is v1 "the Inbox shows me exactly WHERE and HOW to
   answer" (named channel + copyable reply stub) enough? This sets the scope of Critical
   gap 3's fix. My pick: pointer + stub for v1, inline answering as a later task — but the
   workflow preference is yours.

## Summary for the plan file

UX review 2026-07-18 (verdict FAIL pre-amendment; direction confirmed): the three-view frame,
derived statuses, completed-aging trio, context contract, and close-on-promote are right and
faithful to the five-round brief. Fold in before build: (1) a status ROLL-UP law — stalled /
waiting-on-you / unknown propagate to every collapsed ancestor as counted labeled badges,
never masked by a parent's "in-progress"; (2) a navigation spec — three tabs, Roadmap lands,
live "Inbox (N)" count (quarantined items excluded), hash-based item addressing for every
cross-view link (stalled->Inbox, became->, roadmap->request) with focus/highlight on landing
and Back restoring tree state; (3) Inbox item lifecycle — the constitution section-3 anatomy,
an answer affordance (v1: named channel + reply stub), a derived resolution rule, quarantine
framed as system failure with the defect-filed link and excluded from the count; (4) all four
UI states per surface with copy in the plan, incl. filtered-empty ("N hidden — harness
chores") distinct from true-empty, and the Inbox win-state distinct from failed-derivation;
(5) a fifth status value unknown(reason) — never a confident wrong bucket; (6) roadmap items
render "from your request(s)" (the round-1 verbatim direction); (7) polling with
state-preserving re-render + STALE labeling; (8) a Requests filter box + age-grouped,
searchable closed requests; (9) new surfaces bound to the existing a11y conventions (nested
details/summary tree, todo.js edit pattern, text-never-color-only signals, button chips) with
selftest a11y assertions per view. Important (non-blocking): recency ages on all status chips
+ "completed <when>" on collapsed subtree headlines; insertion-marker aging on the shared 7d
tunable; kanban card = top-level item + persisted toggle; amendment "detach" undo; timeline
collapsed = current-state / expanded = chronology.
