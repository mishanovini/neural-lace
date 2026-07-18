# UX Delta Re-review: Cockpit roadmap redesign — resolution check of C1-C9 / I1-I6

**Plan:** `docs/plans/cockpit-roadmap-redesign.md` @ origin/master 0cb4f9b (the FOLDED revision)
**Reviewed:** 2026-07-18   **Prior review:** `docs/reviews/2026-07-18-cockpit-roadmap-redesign-ux-review.md` (FAIL)
**Audience:** unchanged — solo technical founder glancing between meetings, desktop-primary
(no `.claude/audience.md`; persona per the operator brief, re-checked).
**Scope:** RESOLUTION verification only — settled design is not re-litigated.

**Verdict: PASS-WITH-CONCERNS** — all nine Criticals and all six Importants are resolved with
buildable, unambiguous plan text (evidence quoted per item below). Six residual concerns
(severity 1-2, none build-blocking): four are seams the fold itself introduced (adjudications
(c)/(d), the A7 roadmap_rank fold), two are residual instances of the C2 arrow law not yet
bound to two specific affordances. Each is fixable with 1-2 plan lines under decide-and-go.

---

## Part 1 — Critical resolutions (C1-C9)

### C1 — Roll-up law: RESOLVED
Plan task 1, lines 105-110: "ROLL-UP LAW (C1): attention states propagate upward — every
collapsed ancestor of an attention-state descendant shows a counted, labeled badge ('1 stalled
— waiting on you') beside its own status chip; badge click expands the path to the item. Badge
precedence: waiting-on-you > crashed > blocked-on > limit-parked > unknown. Applies to EVERY
leaf-derived attention signal (all stalled reasons + unknown)". All demanded elements present:
ALL attention states incl. unknown (adjudication (b)), precedence order, click-expands-path.
Reinforced at Outcome §2 (lines 49-50), Edge Cases lines 340-341 ("roll-up badge always renders
— the attention state is never masked"), Acceptance scenario 6, Testing Strategy ("roll-up
badges + precedence order" + server-side "roll-up computation"). One multiplicity ambiguity
remains — Concern 4 below.

### C2 — Four-spec law on every cross-view arrow: RESOLVED
Outcome Shell, lines 30-38: three tabs, Roadmap lands, "Inbox (N)" live count (answerable
only), hash addressing `#roadmap/<id>` / `#request/<id>` / `#inbox/<id>`, landed state
("switches tab + scrolls + expands + visibly highlights + moves programmatic focus"), return
("browser Back (hashchange) AND an explicit return affordance... restoring the prior tab with
tree expansion + scroll intact"), and the LAW verbatim: "every cross-view arrow in this plan
ships four specs — target address, landed state, return path, miss behavior". Each named arrow
is bound: stalled to Inbox (task 1 line 103, the `#inbox/<id>` link); became-arrow (task 5
lines 251-252, "shell rules apply: landed state, return, miss behavior"); roadmap to request
(task 3 lines 150-153, `#request/<id>`). Scenario 6 exercises the full leg including
Back-with-state. Two affordances are not yet bound to the law — Concern 3 below.

### C3 — Inbox item lifecycle + stale-link rule: RESOLVED
Task 4, lines 202-210: "(a) ANSWER — v1: a 'how to answer' line naming the exact channel...
+ a copyable reply stub; (b) RESOLVE — the item leaves when the canonical ledger entry
clears/is-answered, or on operator dismiss (dismiss = labeled override...); (c) STALE-LINK —
a followed link to a resolved item renders 'resolved <when> — <outcome>', never blank/404."
The generalization law lands too, with the other views' verbs named inline ("Requests:
auto-capture / edit-amend / close-on-promote; Roadmap: promote / build / complete-aging").
The prior review's open question (inline vs pointer+stub) is correctly logged as the PENDING
decision with pointer+stub as the build-proceeds default — matching both reviews' lean.

### C4 — Four states per surface, filtered-vs-true-empty, win-vs-error: RESOLVED
Task 3 lines 174-177 (tree: loading copy "deriving roadmap…"; error = pane-error + Retry,
"NEVER the empty state on failure — the app.js:185 law"; "FILTERED-empty names the filter +
hidden count + one-click clear"; "TRUE-empty explains items arrive automatically"). Task 4
lines 234-237 (win state "rendered ONLY on successful derivation; a failed/unreadable ledger
renders pane-error + Retry, NEVER the win state"). Task 5 lines 259-260 (empty explains
auto-capture). Testing Strategy lines 388-390: "FOUR-STATE assertions per new view (the
T13-21 pattern... win-state-only-on-success)". Both demanded distinctions are explicit.
One coexistence gap the A10 fold created — Concern 1 below.

### C5 — Honest-failure status value: RESOLVED
Task 1 lines 82-88: enum carries "unknown(reason)... renders unknown(reason) as a visibly
distinct labeled chip ('status unknown — plan parse failed'), reason one click away; NO
default-guess branch anywhere in derive-lib (selftest-pinned)" + the uniform generalization to
every derivation (incl. the hostname-to-person "unassigned" state in task 7). Edge case line
349, Acceptance scenario 7, and the server selftest "unknown-on-input-failure (no
default-guess branch)" all pin it.

### C6 — Roadmap-to-Requests on every item: RESOLVED
Task 3 lines 150-153: "every roadmap item's drill-down carries 'from your request(s):
<title(s)>', linking via `#request/<id>` to the ledger entry, resolved verbatim one click
away... LAW: every promote/became/derived-from relationship renders in BOTH directions, or
the plan states why not." Acceptance scenario 9 makes "which request did this come from?"
part of the operator cold-start walkthrough. The round-1 verbatim drift is closed.

### C7 — Refresh model preserving tree state: RESOLVED
Task 3 lines 178-182: "the three views poll on the existing 30s tick with STATE-PRESERVING
re-render — preserve the details-open set, scroll position, focus, uncommitted title edits,
and the landing highlight; on refresh failure show 'derived <age> — STALE' (app.js:176
pattern), never silent staleness." Testing Strategy adds "one state-preserving-re-render
assertion per view (expansion + scroll + focus + uncommitted edits survive a poll tick)".
Both failure modes named in the original finding (staleness AND wipe-on-rerender) are closed.

### C8 — Ledger findability: RESOLVED
Task 5 lines 253-257: "a filter box (substring over title + distilled intent + verbatim
origin); closed requests default-collapsed under age groups ('this week / this month /
older') that search reaches inside ('closed (N)' expands). RULE (adopted from the proposal):
any surface that can exceed ~2 viewports ships a filter escape hatch AT BIRTH". The
generalization names the sibling surfaces. One clarification on the tree's own escape hatch —
Concern 6 below.

### C9 — A11y bindings + selftest growth: RESOLVED
Task 3 lines 183-188: nested `<details>`/`<summary>` tree, todo.js edit-button + Escape +
focus-return pattern ("never click-on-text-only"), "every status signal is text + color,
never color-only", real `<button>` chips (inherits the 24px floor), aria-pressed kanban
toggle. Tasks 4/5 bind "as task 3". Testing Strategy lines 390-392: "A11Y assertions per new
view (the R20-R22c pattern extended: details-based disclosure present, focus-visible
reachable, aria-live on edit feedback, text alternative for every color signal)". One new
interactive surface the fold added is NOT yet covered — Concern 2 below.

## Part 2 — Important resolutions (I1-I6)

- **I1 recency: RESOLVED** — task 3 lines 154-158 (transition age on every chip, "completed
  <rel-time>" on collapsed subtree headlines, non-color-only "new" treatment <24h,
  generalization to all three views); task 5 line 258 ("last amended <age>"); the task 4
  collapsed row carries age.
- **I2 marker lifetime: RESOLVED** — task 3 lines 159-164: the insertion marker "ages out on
  the SAME 7d tunable — one knob" + the persistent-vs-transient declaration law.
- **I3 kanban unit + persistence: RESOLVED** — task 3 lines 165-170: cards = TOP-LEVEL
  roadmap items; columns = the derived statuses; toggle + project-chip selections persist
  (localStorage); the alternate-view law also binds task 7's person grouping (lines 288-289).
- **I4 quarantine framing + count: RESOLVED** — task 4 lines 223-233: below answerable items,
  "N arrived without context — defects filed against the producing sessions", the defect
  link, the open-source-session escape hatch, dismiss, "EXCLUDED from the Inbox (N) headline
  count", the framing law — plus concrete auto-defect mechanics (auditor-cycle-only,
  once-per-item, lint_warnings reuse) that exceed the asked-for spec.
- **I5 Inbox anatomy: RESOLVED** — task 4 lines 191-201: the proposed anatomy adopted
  verbatim (collapsed row, sort rule, §3 expanded format, below-the-fold, one-format law).
- **I6 timeline + amendment correction: RESOLVED** — task 5 lines 247-250 (collapsed =
  current state, expanded = oldest-first chronology, origin pinned first, became-arrow as
  terminal event) + task 2 lines 129-132 (detach via the undo-window pattern;
  auto-capture-without-undo generalization).
- The severity-1 roll-up exemplar is folded too ("N completed — latest: <title>", task 3
  lines 161-162 and Outcome §2 line 54).

## Part 3 — Adjudication sanity check (new-problem scan)

- **(a) roadmap_rank default = registry insertion order:** sound — a stable reading order
  serves "the order they are intended to be built" better than recency churn. But the fold
  introduces an operator-editable REORDER interaction with no interaction spec — Concern 2.
- **(b) unknown at the precedence tail:** sound — concrete operator-actionable stalls outrank
  an indeterminate state, and unknown still propagates (C5 satisfied). Residual badge
  multiplicity ambiguity — Concern 4.
- **(c) Inbox supersedes My-To-Do:** sound as architecture (one surface, "the two counts can
  never disagree"; todo.js machinery retained). But the C4 win-state copy was written for a
  derived-only Inbox, and the fold now places two excluded-from-count sections in the same
  view — Concern 1. This is the fold's one real new UX seam.
- **(d) kanban six-value column mapping:** sound — merged-unverified and unknown as their own
  labeled columns is the only mapping consistent with C5/A4 (never inside Complete). Minor
  noise question on permanently-empty exceptional columns — Concern 5.
- **(e) Acceptance scenario 1 hardened to complete-PROVEN:** sound, strictly stronger test;
  no UX impact.

## Part 4 — Residual concerns (all non-blocking)

1.
```
- Line(s): Task 4 "Win state (C4)" (lines 234-237) vs "Inbox vs My-To-Do (A10)" (lines
    238-242) and "Quarantine" (lines 223-233)
  Defect: The win state "Nothing waiting on you — all sessions running free" is specced for a
    derived-only Inbox, but adjudication (c) adds a "My items" section and quarantine sits
    in-view; whether the celebration renders above a non-empty personal to-do list or above
    "N arrived without context" is unspecified — a mixed message on the trust-bearing surface
    (H1/H8; the copy over-claims relative to the visible view contents).
  Severity: 2 (Important) — frequency: whenever answerable=0 while My items or quarantine is
    non-empty (routine); impact: momentary mixed signal, not a wrong action; persistence: yes.
  Confidence: PROVEN — the plan specs the win state and the two excluded sections separately
    and never their coexistence.
  Class: celebration-copy-out-of-scope-with-view-contents (fold-introduced by adjudication c)
  Sweep query: rg -n "win state|My items|quarantin" docs/plans/cockpit-roadmap-redesign.md —
    any state copy that summarizes "the view" must be re-scoped whenever a section is added.
  Required fix: One plan line in task 4: the win state is the ANSWERABLE section's empty
    state (rendered in that section's position, copy scoped, e.g. "No session asks waiting on
    you"); the whole-view celebration renders only when answerable AND quarantine are both
    empty.
  Required generalization: any section added to an existing view re-scopes that view's
    empty/win copy — section-level states belong to sections; view-level copy must be true of
    the whole view.
```

2.
```
- Line(s): Task 3 "Build order (A7)" (lines 146-149) + task 3 A11y block (lines 183-188)
  Defect: roadmap_rank is "operator-editable via UI delegation" with no interaction spec; the
    natural build (drag-to-reorder) with no single-pointer/keyboard alternative violates WCAG
    2.2 2.5.7 Dragging Movements (AA) and the tree's keyboard operability — the one new
    interactive surface the fold added that the C9 a11y block does not cover.
  Severity: 2 (Important) — frequency: occasional (reordering); impact: reorder unusable
    without a mouse if built drag-only; persistence: structural. Not Critical: a pre-build
    spec ambiguity, and the default read of "editable" may be non-drag anyway.
  Confidence: HYPOTHESIZED — the plan never says "drag"; REFUTED if the builder ships a
    non-drag reorder control (e.g., move up/down buttons) by default.
  Class: drag-only-interaction (new surface post-dating the original review)
  Sweep query: rg -n "reorder|drag|rank" docs/plans/cockpit-roadmap-redesign.md
    neural-lace/workstreams-ui/web — every reorder affordance needs a non-drag path.
  Required fix: One line in task 3: rank editing ships keyboard-operable single-pointer
    controls (move up/down as real buttons); drag, if added, is an enhancement over them.
  Required generalization: every operator-editable ordering anywhere (roadmap rank now; any
    future kanban drag) ships the non-drag path first (WCAG 2.5.7).
```

3.
```
- Line(s): Task 4 quarantine "open source session" (line 225) + collapsed-row "blocks:
    <item>" (line 193); the arrow law at Outcome lines 36-38
  Defect: Two affordances are not bound to the four-spec arrow law: (a) "open source session"
    has no named target or mechanism (a session is not one of the three hash-addressable
    views — what opens, and where?); (b) "blocks: <item>" names a roadmap item but is not
    stated to link via `#roadmap/<id>` — as plain text it fails its obvious follow-up (H6,
    information scent).
  Severity: 2 (Important) — frequency: per quarantined item / per blocking item; impact: a
    dead end or a hunt at a moment the law exists to cover; persistence: until specced.
  Confidence: PROVEN — both affordances appear without address/landed/return/miss wording;
    the law's sweep arguably covers (b), but a builder can read "blocks:" as a chip label,
    not a link.
  Class: unaddressed-arrow (residual instances of C2's class — not a reopening of C2)
  Sweep query: rg -n "open source|blocks:|escape hatch" docs/plans/cockpit-roadmap-redesign.md
  Required fix: One line each: "blocks: <item>" links via `#roadmap/<id>` (full shell rules);
    "open source session" names its concrete target (e.g., the session's transcript/
    workstream surface) or is demoted to a copyable session id with that stated.
  Required generalization: already stated in the plan's own law — apply it to these two.
```

4.
```
- Line(s): Task 1 ROLL-UP LAW (lines 105-110)
  Defect: "a counted, labeled badge" (singular) + a precedence order leaves badge multiplicity
    ambiguous: a collapsed ancestor holding a crashed AND a waiting-on-you descendant could
    render one top-precedence badge (masking the crashed one — C1's own defect recurring at
    badge level) or one badge per class; the plan does not say which.
  Severity: 2 (Important) — frequency: multi-class collapse is uncommon but real at scale;
    impact: a masked attention state on the surface built to never mask one; persistence: yes.
  Confidence: PROVEN ambiguity — both readings fit the text.
  Class: ambiguous-aggregation-rule
  Sweep query: rg -n "counted, labeled badge|precedence" docs/plans/cockpit-roadmap-redesign.md
  Required fix: One clarifying line, decide-and-go default: one badge PER attention class
    present, ordered by precedence (never masks); precedence governs ORDERING, not selection.
  Required generalization: every aggregate signal states its multi-class rule (one-per-class
    vs top-only) — the kanban columns and the Inbox count already do; the badge should too.
```

5.
```
- Line(s): Task 3 kanban (lines 165-170), adjudication (d)
  Defect: Six columns where merged-unverified and unknown are usually empty adds standing
    noise to an occasional-use view (H8) — the fold never says whether exceptional columns
    render when empty.
  Severity: 1 (Nice-to-have) — occasional-use view, cosmetic noise only.
  Confidence: PROVEN omission.
  Class: instance-only (single view; no analogous empty-column problem elsewhere)
  Sweep query: n/a — instance-only
  Required fix: Decide-and-go default: the merged-unverified and unknown columns render only
    when non-empty (an empty exceptional column carries no information; the states stay
    honest whenever present).
  Required generalization: n/a — instance-only
```

6.
```
- Line(s): Task 5 findability RULE (lines 255-257) vs task 3 (project chips only, lines
    54, 165-170)
  Defect: The at-birth rule names "roadmap tree at scale" a sibling surface, but task 3 ships
    only project chips and no substring filter — a builder can read the chips as satisfying
    the escape hatch, or read the rule as demanding a tree filter box; the plan does not
    arbitrate.
  Severity: 1 (Nice-to-have) — the chips ARE a working escape hatch for the near-term tree.
  Confidence: PROVEN ambiguity.
  Class: instance-only (the other named siblings — closed groups, quarantine — are covered)
  Sweep query: n/a — instance-only
  Required fix: One clarifying line in task 3: chips satisfy the escape hatch at birth; a
    substring tree filter is the named follow-on once the tree exceeds ~2 viewports.
  Required generalization: n/a — instance-only
```

## Questions for the user
None new. The one open item (inline vs pointer+stub Inbox answering) is already correctly
parked as the plan's PENDING decision with the both-reviews-endorsed default.

## Summary for the plan file
UX delta re-review 2026-07-18 @0cb4f9b: PASS-WITH-CONCERNS. All nine Criticals (C1-C9) and
all six Importants (I1-I6) from the 2026-07-18 FAIL review are resolved with buildable plan
text; the five cross-review adjudications are sound. Six non-blocking residuals to absorb
during build (1-2 plan lines each, decide-and-go): (1) scope the Inbox win state to the
answerable section now that "My items" + quarantine share the view; (2) roadmap_rank reorder
ships keyboard-operable move controls, never drag-only (WCAG 2.2 2.5.7); (3) bind "blocks:
<item>" to `#roadmap/<id>` and name the "open source session" target per the plan's own
arrow law; (4) roll-up badges render one-per-attention-class (precedence = ordering, not
selection); (5) empty merged-unverified/unknown kanban columns hide; (6) state that project
chips satisfy the tree's at-birth filter escape hatch. The ACTIVE flip is no longer gated on
UX review.
