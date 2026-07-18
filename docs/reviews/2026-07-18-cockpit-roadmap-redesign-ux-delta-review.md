# UX Delta Re-review: Cockpit roadmap redesign (post-fold, gate-critical)

**Plan:** `docs/plans/cockpit-roadmap-redesign.md` (post-fold revision, commit 7b4cd86)
**Reviewed:** 2026-07-18 · Delta against my FAIL review
(`docs/reviews/2026-07-18-cockpit-roadmap-redesign-ux-review.md`), cross-checked against the
architecture review (`docs/reviews/2026-07-18-cockpit-roadmap-redesign-architecture-review.md`)
and the operator's verbatim record (`docs/reviews/2026-07-17-cockpit-ux-design-input.md`,
supreme authority).
**Scope:** disposition of C1-C9 and I1-I6 only, plus adjudication audit and regression sweep.
Not a fresh full review.

**Verdict: PASS** — all 9 Criticals RESOLVED as binding, buildable spec text in the tasks they
belong to; all 6 Importants RESOLVED (none merely deferred); the 5 fold adjudications are
consistent with my findings and the operator's verbatim record; no new sev-3+ regression
introduced by the fold. The plan is safe to activate. Two non-blocking build-watch notes below
(neither rises to a residual concern band).

---

## Critical dispositions (C1-C9)

### C1 — Status roll-up law with precedence — RESOLVED
Task 1 "ROLL-UP LAW (C1)" (plan lines 105-110): attention states propagate to every collapsed
ancestor as counted, labeled badges ("1 stalled — waiting on you") beside the parent's own chip;
badge click expands the path; precedence pinned: waiting-on-you > crashed > blocked-on >
limit-parked > unknown; applies to EVERY leaf-derived attention signal (all stalled reasons +
unknown, per my Required generalization); computation sited (derive-lib, task 1) and rendering
sited (task 3, lines 144-145). Reinforced at Outcome §2 (lines 49-50), Edge Cases (lines
340-341), Acceptance scenario 6 (lines 366-368), and Testing Strategy ("roll-up badges +
precedence order", line 388; "roll-up computation" server-side, line 396). This is the full bar
my finding set: law + precedence + generalized signal coverage + test binding. The precedence
extension (unknown at tail) is adjudication (b) — see the adjudication audit; it strengthens,
not weakens, the law.

### C2 — Navigation shell, tabs, hash addressing, landed/Back/miss semantics — RESOLVED
Outcome "Shell (C2)" (lines 30-38): three tabs named, Roadmap = landing, live "Inbox (N)" with
N = answerable only (quarantined + My-items excluded); hash addressing `#roadmap/<id>` /
`#request/<id>` / `#inbox/<id>`; landed state = switch + scroll + expand + highlight +
programmatic focus; return = browser Back (hashchange) AND an explicit return affordance, both
restoring prior tab with expansion + scroll; the four-spec LAW for every cross-view arrow
(address / landed state / return / miss) closes my "no unaddressed arrows" generalization.
Build home is explicit — task 3 "Shell (C2), built here; tasks 4-5 register into it" (lines
136-141) — so it is task-bound, not aspiration. Acceptance scenario 6 exercises the full leg
including Back-restores-state. The miss rule ("resolved <when> — <outcome>", never blank/404)
is bound in the shell law (lines 37-38) and again in task 4 (c) and Edge Cases (line 346).

### C3 — Inbox arrive/act/leave lifecycle + stale-link rule — RESOLVED
Outcome §3 names the frame ("full item LIFECYCLE (arrive / act / leave — C3)", line 57) with
arrival specified via the context contract (context-less CANNOT render answerable — it
quarantines, lines 58-61). Task 4 "Item lifecycle (C3)" (lines 202-210) specs all three verbs
in binding text: (a) ANSWER — v1 named-channel + copyable reply stub (matching my Question 1
recommendation, logged as the PENDING decision with build-on-default — correct handling);
(b) RESOLVE — the item leaves when the canonical ledger entry clears/is-answered, or on
operator dismiss as a LABELED override (consistent with the derivation law, as my fix
required); (c) STALE-LINK — "resolved <when> — <outcome>", never blank/404. My Required
generalization (every view's item type defines all three verbs at plan level) is adopted as
the LAW line with Requests (auto-capture / edit-amend / close-on-promote) and Roadmap
(promote / build / complete-aging) named explicitly. The win-state decay problem ("Inbox (N)
overstates") is closed by RESOLVE plus the count spec in the shell.

### C4 — Four UI states per surface, incl. filtered-empty and win-vs-error — RESOLVED
Exactly the required shape — one binding block per view with copy in the plan: task 3 "Four UI
states (C4)" (lines 174-177): loading "deriving roadmap…"; error = pane-error + Retry, NEVER
the empty state (the app.js:185 law cited); FILTERED-empty names the filter + hidden count +
one-click clear with both copy variants I required; TRUE-empty explains auto-arrival (no setup
ask). Task 4 "Win state (C4)" (lines 234-237): win copy verbatim, rendered ONLY on successful
derivation; unreadable ledger renders pane-error + Retry, NEVER the win state — the
error-masquerading-as-empty distinction is now law, and Acceptance scenario 7 tests it
directly. Task 5 (lines 259-260): loading/error per convention + auto-capture empty copy.
Testing Strategy (lines 389-391) grows FOUR-STATE assertions per new view on the T13-21
pattern including filtered-vs-true empty and win-state-only-on-success — my Required
generalization, test-bound. Sub-surfaces (kanban, quarantine group, timeline panel) inherit
their host view's pane states: the kanban shares the roadmap view's data path, the quarantine
group renders only within a successfully-loaded Inbox, and a request timeline always contains
at least its pinned origin event — no residual four-state hole.

### C5 — unknown(reason), no default-guess branch — RESOLVED
Task 1 Enum (lines 82-88): unknown(reason) is the sixth value; any derivation-input failure
(plan-parse error, unreadable heartbeat, schema drift — my exact instances) renders a visibly
distinct labeled chip ("status unknown — plan parse failed") with the reason one click away;
"NO default-guess branch anywhere in derive-lib (selftest-pinned)" — the exact no-guess
binding I required, with the test pin ("unknown-on-input-failure (no default-guess branch)",
Testing Strategy line 395). My Required generalization is adopted verbatim: EVERY derivation
this plan ships (status, stalled-reason, progress fraction, complete-oracle, hostname-person
map) names its failure rendering (lines 86-88; the hostname case lands as "unassigned" — a
named state, never a guess — task 7 lines 286-289). Unknown propagates through the C1 roll-up
per adjudication (b). Edge case line 349 + Acceptance scenario 7 close the loop.

### C6 — Roadmap-to-Requests direction (the one verbatim drift) — RESOLVED
Task 3 "Roadmap→Request (C6)" (lines 150-153): every roadmap item's drill-down carries "from
your request(s): <title(s)>", linked via `#request/<id>` (so it inherits the C2 four-spec
law), resolved verbatim one click away via the existing Verbatim mechanism — my Required fix
verbatim. The generalization is adopted as LAW: every promote/became/derived-from relationship
renders in BOTH directions or the plan states why not. Restated at Outcome §2 (lines 51-52).
Acceptance scenario 9 makes the operator's round-1 sentence the test: "which request did this
come from?" answerable cold in under 60s. The drift from the verbatim record is closed.

### C7 — State-preserving refresh — RESOLVED
Task 3 "Refresh model (C7)" (lines 178-182): the three views poll on the existing 30s tick
with STATE-PRESERVING re-render, preserving the exact state set I enumerated (details-open
set, scroll, focus, uncommitted title edits, AND the C2 landing highlight — the pairing my
finding required); refresh failure renders "derived <age> — STALE" (app.js:176 pattern),
never silent staleness. Generalization adopted as LAW, and the Testing Strategy binds one
state-preserving-re-render assertion per view (lines 392-393: "expansion + scroll + focus +
uncommitted edits survive a poll tick"). Both defect branches of my finding (stale load-once
AND wipe-on-rerender) are foreclosed.

### C8 — Findability of closed requests — RESOLVED
Task 5 "Findability (C8)" (lines 253-257): filter box with the exact substring scope I
specified (title + distilled intent + verbatim origin); closed requests default-collapsed
under age groups ("this week / this month / older") that search reaches inside ("closed (N)"
expands) — the months-old lookup is now possible under the collapse default. The proposal's
rule is adopted into the plan as a RULE with the sibling surfaces named (roadmap tree at
scale, "N completed" roll-ups, quarantine group) — my Required generalization, with the
"~2 viewports at birth" threshold intact. Outcome §1 (line 44) carries it at the outcome
level too.

### C9 — A11y bindings + selftest growth — RESOLVED
Task 3 "A11y (C9)" (lines 183-188) binds every convention my fix named: nested
`<details>`/`<summary>` tree (native keyboard disclosure), todo.js edit-button + Escape +
focus-return for title editing (never click-on-text-only), text + color never color-only
(chips carry words, bars carry "4/9" — also bound at tree spec line 143; the insertion marker
is a labeled chip), interactive chips as real `<button>`s inheriting the 24px floor (WCAG
2.5.8), kanban toggle as an aria-pressed button. Tasks 4 and 5 bind "as task 3" (lines
243-244, 261) — terse but real bindings, and the Testing Strategy makes them enforceable:
A11Y assertions per new view on the R20-R22c pattern (details-based disclosure present,
focus-visible reachable, aria-live on edit feedback, text alternative for every color
signal — lines 391-392). That is the full bar: conventions bound in task text + selftest
growth per view.

## Important dispositions (I1-I6) — one line each

- **I1 recency — RESOLVED.** Task 3 (lines 154-158): transition age on every chip, "completed
  <rel-time>" on collapsed subtree headlines, non-color-only under-24h "new" treatment;
  generalized to all three views (Inbox age in the task-4 collapsed row, line 194; Requests
  "last amended" at line 258).
- **I2 marker lifetime — RESOLVED.** Task 3 (lines 159-164): insertion marker ages out on the
  SAME 7d tunable (one knob); persistent-vs-transient declared as LAW for every annotation
  chip.
- **I3 kanban unit + persistence — RESOLVED.** Task 3 (lines 165-170): cards = top-level
  items, columns = derived statuses (six-value reconciliation via adjudication (d)), toggle +
  chip selections persist (localStorage); LAW extended to task 7's person-grouped view
  (line 289).
- **I4 quarantine framing + count — RESOLVED.** Task 4 (lines 223-233): below answerable
  items under the system-failure header, defect-filed link, open-source-session hatch,
  dismiss, EXCLUDED from Inbox (N) (also pinned in the shell, line 32); framing law
  generalized to every system-failure surface.
- **I5 Inbox anatomy — RESOLVED.** Task 4 (lines 191-201): my proposed collapsed-row /
  §3-expanded / below-the-fold anatomy adopted essentially verbatim, with the sort rule and
  the one-format-learned-once LAW.
- **I6 timeline anatomy + amendment correction — RESOLVED.** Task 5 (lines 247-250: collapsed
  = current state / expanded = oldest-first chronology, origin pinned, dated, "became →"
  terminal) + task 2 (lines 129-132: detach on the undo-window pattern, generalized to every
  auto-captured record type).

The severity-1 polish (roll-up exemplar scent) is also absorbed: "N completed — latest:
<title>" (lines 54, 162).

## Adjudication audit (plan Decisions Log, lines 404-435)

None of the five adjudications undoes a UX finding or contradicts the verbatim record:

- **(a) roadmap_rank default = insertion order** — architecture-side (F7 offered either);
  stable reading order serves round-2 "the order they are intended to be built" better than
  recency churn; operator-editable rank preserves control. Consistent.
- **(b) unknown at the precedence tail** — extends my C1 ordering (which covered stalled
  reasons only) to satisfy C5's propagation requirement; operator-actionable stalls
  outranking an indeterminate state is the right call. Strengthens both findings.
- **(c) Inbox supersedes My-To-Do; "My items" section, excluded from (N)** — resolves A10 in
  the direction my I4 count-honesty finding pushes (the headline counts only what needs the
  operator); no operator verbatim governs the To-Do pane; one surface means the two counts
  can never disagree. Consistent.
- **(d) kanban columns reconciled with the six-value enum** — merged-unverified and unknown
  as their own labeled columns, never inside Complete; upholds C5 and the operator's
  round-3/4 complete definition over my I3 "four columns" wording, which predated the
  six-value enum. Correct precedence.
- **(e) Acceptance scenario 1 hardened to complete-PROVEN** — replaces an honest-fallback
  label with a mechanism-true signal (A4); aligns with the operator's "deployed in
  production, fully functional" definition. Consistent.

The one PENDING decision (inline vs pointer+stub answering) proceeds on the default both
reviews recommended, logged for operator override — correct decide-and-go handling per
constitution §8, not a gap.

## Regression sweep (fold-introduced sev-3+ defects)

None found. Checked specifically: (1) the new "merged — deploy unverified" status the fold
introduced (A4) is text-labeled, gets its own kanban column, never renders inside Complete,
carries the recency law, and is correctly OUTSIDE the C1 attention-state roll-up set (it is a
lifecycle state, not an attention signal — a collapsed parent showing in-progress over it is
not a wrong stall signal); (2) the My-items migration into the Inbox (adjudication c) retains
the existing todo.js machinery and is count-excluded — no new dead end or count distortion;
(3) hash routing vs the C7 refresh model — the landing highlight is explicitly in the
preserved-state set, so the interaction is specified, not accidental.

Two non-blocking build-watch notes (severity 1 at most, recorded for the builder, not
gating):
- Tasks 4/5 bind a11y by reference ("as task 3"). The bindings are real and test-enforced,
  but the Inbox's unique interactive anatomy (trade-offs table, copyable reply stub, dismiss)
  should get the same per-view a11y assertion depth the Testing Strategy already promises —
  watch that the selftest additions cover the Inbox-specific controls, not just the shared
  patterns.
- The kanban inherits the roadmap view's four states by sharing its data path; if the build
  ever gives the kanban an independent fetch, the C4 per-view binding applies to it in its
  own right.

## Verdict

**PASS.** All 9 Criticals RESOLVED with binding, buildable spec text sited in the owning
tasks and test-bound in the Testing Strategy; all 6 Importants RESOLVED; adjudications
consistent with the findings and the operator's verbatim record; no fold-introduced
regression. This delta review lifts my 2026-07-18 FAIL: the plan is cleared for activation
from the UX gate's side.
