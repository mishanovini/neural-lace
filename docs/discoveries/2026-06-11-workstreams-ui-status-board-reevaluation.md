---
title: Workstreams UI — re-evaluate from tree-first to status-board-first
date: 2026-06-11
type: user-experience
status: decided
auto_applied: false
originating_context: Operator asked for a full UX re-evaluation of the Workstreams GUI after correcting a mischaracterization of the right panel; the built UI had drifted from the intended concept.
decision_needed: One layout fork reshapes everything — board-PRIMARY with the tree as a toggle (recommended), or tree-and-board CO-EQUAL? Plus — commission a ux-ia-auditor pass to produce the concrete proposed IA + board design?
predicted_downstream:
  - neural-lace/workstreams-ui/web/{app.js,app.css,index.html}
  - neural-lace/workstreams-ui/state/{schema.js,reducer.js}  (human-authored items as first-class)
  - docs/discoveries/2026-05-27-conv-tree-v4-design.md  (the v4 redesign is partially superseded by this re-frame)
---

## What was discovered

The Workstreams GUI's core metaphor does not match its stated purpose.

- **Stated concept (operator):** a SINGLE shared surface where the operator AND the AI
  orchestrator keep one reconciled picture — what's in progress, what's next, what's
  *waiting on the operator*, and what's done — so both parties always agree on the state
  of the work and on what to do next.
- **What got built:** a **structure-first** UI whose primary object is a *tree of how the
  AI's work decomposed* (Project → branch → item), auto-emitted from Dispatch events. The
  right panel — intended by the operator as (1) an independently operator-authored to-do
  list + (2) a separate backlog — drifted into auto-derived "Waiting / Decisions /
  Questions" views.

Two concrete drift signals:
- A prior ux-designer review recommended "make branch-selection filter the right panel" —
  a recommendation built on the (now-corrected) wrong assumption that the right panel is a
  filtered view of the left. The operator never intended that coupling. **That
  recommendation is retracted.**
- The live state carries 112 auto-emitted items (88 action / 19 decision / 5 question),
  0 with curated `details`. A tree faithfully shows *everything the AI did* but does not
  tell either party *what to do next* — so the surface reads as a firehose, not a plan.

## Why it matters

A tree answers "how is this structured / where does it belong?" A status board answers
"what's happening and what's next?" The concept needs the *status* answer as the headline;
the build leads with the *structure* answer. Until the primary metaphor matches the
concept, the GUI cannot be the shared frame-of-reference it exists to be.

## Options

A. **Specific improvements to the current tree-first UI** (the ux-designer's non-retracted
   findings: design the empty-`details` state as the default; make the detail modal a
   superset of the list row; a11y on tree twists; visual verification). Cheapest; does NOT
   fix the metaphor mismatch.
B. **Full from-scratch rebuild** (backend + frontend). Most expensive; throws away a solid,
   hard-won event-sourced substrate that is NOT the problem.
C. **Keep the foundation, re-conceive the surface** (recommended). Keep the event-sourced
   data layer (append-only log, attestation, cross-machine coordination repo + reconciler).
   Flip the PRIMARY surface to a **status board** — lanes **Now / Next / Waiting-on-you /
   Done(recent) / Backlog** — where operator-authored to-dos and AI-emitted work-items
   coexist in ONE model, tagged by origin. "Waiting on you" is first-class and always
   visible. The tree demotes to a secondary lens (toggle: "show how this decomposes").
   Requires making hand-authored items first-class in the schema alongside emitted ones.

## Recommendation

**C.** Considerably different *presentation*, same *foundation*. The backend already does
the hard part; the tree-first frontend metaphor is what walked the build away from the
concept. Bigger than tweaks (A), smaller than a rebuild (B). Reuse the existing
rendering/event machinery where it fits.

Next step: hand the concept (shared single surface, status-first, both authors,
waiting-on-you first-class) to the `ux-ia-auditor` agent — purpose-built for app-wide IA +
workflow redesign — to produce a concrete proposed board layout + data-model deltas,
grounded against the real 112-item state. Pending the operator's layout-fork answer first.

## Decision

Operator direction (2026-06-11), revising the fork:

1. **BOTH tree AND board are first-class — not board-primary-with-tree-toggle.** The tree's
   real value is **parallelization awareness**: the operator works across many projects /
   surfaces simultaneously and needs to keep track of all the different things happening in
   different places. The tree is *a* good way to show "where exactly all the action is" —
   but the operator is explicitly open to BETTER presentations of the parallel-across-
   projects view (e.g. a project×status matrix, a mission-control project-overview, swimlanes).
   So the design must serve both axes (status AND project/structure) as first-class, and
   should explore the strongest "parallel cockpit" presentation, not just keep the tree.

2. **HARD REQUIREMENT — context-complete items.** Every item presented to the operator MUST
   carry enough embedded context that he can decide WITHOUT remembering past discussion. The
   recurring failure: Claude presents decision *options with no context on what the options
   even mean*. This is a hard requirement — the Workstreams UI is useless without it. It is
   primarily an EMIT-DISCIPLINE problem (Claude must author full per-item context), not only a
   render problem: an item card for a decision/question must contain what-it-is + background/
   why-now + each option's MEANING and tradeoff + recommendation + reply-with. This maps onto
   the existing `decision-context.md` fence grammar (About / Background / Options-with-what-it-
   does-and-risk / Recommendation); the gap is that it isn't reliably emitted, flushed, or
   rendered. The fix is a gate: a contextless decision item is not a valid item.

Density critique (operator, 2026-06-11) — load-bearing correction: a project×status matrix
that renders item CHIPS in cells does NOT scale. Real data is lopsided (one project dozens of
items, another 3; "Done" cumulatively huge, "Waiting on you" tiny) → unequal row heights and
overflowing cells. The mockup only looked clean because under-populated. ROOT ERROR: trying to
render every item, everywhere, at once. Evolved principle: **never render all items at once —
COUNTS globally (fixed density, O(projects)); ITEMS only for one bounded slice.** Concretely:
global "waiting on you" list (naturally small); a project cockpit (one row/project with status
COUNTS now/next/waiting/done — fixed density, the parallel glance); drill into a project → its
work as the tree (bounded → readable; the tree was never the problem, making it global was). A
count/heatmap matrix (cells = numbers, click to drill) is the 2D-grid alternative, same
no-chips-in-cells principle. Context-complete cards thus only render in bounded views.

CONFIRMED by operator (2026-06-11): the evolved shape — global "waiting on you" list +
project cockpit (status counts) + drill into per-project tree — "makes sense." Build on it.

Design detail locked (operator asked, 2026-06-11):
1. **Tree (per-project, bounded).** Indentation + guide lines + real focusable disclosure
   twists; branch rows carry an open-count badge + an amber "needs-you" dot if anything
   inside is waiting on the operator; done/archived branches collapsed by default (a "show
   done" toggle). COLOR DISCIPLINE: color encodes STATUS, icon encodes KIND. Neutral gray =
   structure/idle; amber = needs-you / blocked (the ONLY thing that pops); green check = done
   then muted. Kind shown by icon (action / decision / question), never by color. Two ramps
   max (gray + amber) + green for the done semantic. Avoids the rainbow.
2. **"My tasks" — editable, operator-owned.** A dedicated surface showing the operator's
   ENTIRE hand-authored task list in one place; always-present "+ add" input; inline edit
   (text / project / status / priority / done / delete) + drag-reorder. First-class items
   (origin=operator) in the same event-sourced model → they also appear in cockpit counts +
   the relevant project tree, but THIS is the authoring surface. Claude reads it (knows the
   to-dos), operator owns it. Needs: user-authored item-add/edit events + GUI write endpoints.
3. **Backlog — editable, same pattern.** Separate "eventually" surface; add/edit/priority/
   delete + a "promote to task" action (backlog → Next). Tasks = active; backlog = someday.
4. **Context-completeness — what + how.** WHAT (per-kind required fields): decision = what's
   decided + why-now + each option's MEANING & tradeoff + recommendation + reply; question =
   the question + why-it-matters/what's-blocked + answer-shape + reply; action-for-operator =
   what + why + how-to-resolve. BAR = the cold-read test ("could the operator decide reading
   ONLY this card, zero memory of the chat?"); fail → "context incomplete", gated, not shown
   as actionable. HOW (clean+concise): progressive disclosure — essentials inline (1-2 sentence
   background, one line per option, the recommendation, reply buttons), full reasoning/links
   behind a "more" expand; structured labeled sections (scan not read); one line per option.

Still open (gates concrete build): the 5 ux-ia-auditor questions (lane labels; to-do default
lane; to-do scope global-vs-per-project; pipeline-flush in scope; tree-lens default).

## Implementation log

(empty — design re-evaluation only; no code changed)
