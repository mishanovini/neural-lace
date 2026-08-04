# Design: [Title]

<!--
This template is authored FOR `design-author` (adapters/claude-code/agents/design-author.md,
REQ-B2) and is that agent's Phase 5 self-audit checklist made concrete. Every section marked
REQUIRED must be present and substantive before the design is handed to reviewers
(architecture-reviewer always; harness-reviewer for any harness-surface design).

Follow this file's own comment-annotated style if you extend it — a template that doesn't teach its
user how to fill it out gets filled out wrong (see plan-template.md, the sibling this file mirrors).
-->

**Status:** <drafting | r1 — awaiting review | rN — delta integration | FINAL>
<!--
drafting          Still being written; not yet handed to any reviewer.
r1                First complete draft, submitted for review.
rN — delta        A later round that integrates specific review findings (name which review(s)
                   in the Changelog line below, not here).
FINAL             Every review this design's surface requires has returned a passing verdict
                   (architecture-reviewer SOUND, harness-reviewer PASS where applicable) and no
                   further round is expected. A plan's `design-ref:` header should anchor to a
                   FINAL (or explicitly-confirmed r-N-pending-only-scoped-confirmation) revision.
-->

**Author:** <design-author (model: fable) | session label, if authored before this agent existed>
<!--
Name the model that actually authored this, not the aspiration. If `design-author` authored it,
say so plus the model it ran as. If this design predates the agent's existence (the bootstrap
case), name the session honestly — "Fable main session <id>, model claude-fable-5, authored
inline — design-author agent did not exist yet" — see gated-pipeline-master-2026-08-03.md's own
header for the live precedent. An unattributed or un-pinned author is P-31's exact defect; never
leave this blank and never let it default silently to whatever model happened to be running.
-->

**Changelog:** <r1 (SHA): initial authoring. r1 → r2 (SHA): integrated <review path>, findings
<id list> — one line per substantive change, per round.>
<!--
THIS is where every review-driven or operator-driven correction lands. Every finding you
integrate, every operator correction, every reversal — one line here, folded into the numbered
section it corrects. NEVER as a body `## Addendum`, `## Round N`, or `## Update:` heading — that
is the P-32 defect (the 2026-08-02 considerations brief: a correction landed as an appended
section, the plan was written from the body above it, and the correction never reached any task
text). REQ-B10's no-addendum lint enforces this mechanically on the committed file; this
Changelog line is where the "what changed and why" that an Addendum heading would have held
actually belongs. If this is r1, write "r1 — initial authoring, no prior rounds."
-->

**Supersedes:** <docs/plans/*, docs/designs/*, or a named in-repo law/convention this design
replaces — each with a one-line reason. "None — net-new, no prior art in this area" if genuinely
novel.>
<!--
A design that silently makes an old plan/design/convention obsolete without saying so leaves two
truths standing where only one should govern. If this design changes what a standing rule means
(the P-33/P-42 class — "refreshes on a timer" quietly read as load-bearing when it was an
implementation detail), name the exact citation being superseded, not just the file.
-->

**Inputs (all read in full):** <every handoff, prior design, prior review, and grounding sweep
this design is built on — real paths/anchors, not "context from the session".>
<!--
Phase 0 of design-author's protocol. An input you didn't actually read is not an input — cite a
git blob/commit or a HEAD ref for anything time-sensitive (a grounding sweep goes stale the
moment the code moves under it).
-->

---

## 0. What this design is, in three sentences
<!-- OPTIONAL but recommended: the elevator summary. A reader who stops here should know the
shape of the change even if they read nothing else. -->

## 1. Problem statement (evidence-anchored)
<!--
REQUIRED. Phase 1 output. Every claim PROVEN (cite the measurement/file:line/commit) or
HYPOTHESIZED (state what would refute it) — per `~/.claude/doctrine/claims.md`. A problem
statement built on unlabeled assertions is a design built on sand; the reviewer's first job is
to re-derive this section independently and compare (architecture-reviewer Phase 0) — make that
comparison land on agreement, not on "where did this number come from."
-->

## 2. Binding constraints
<!--
REQUIRED. What this design must NOT violate: hard stops, standing operator directives (cite by
`OD-`id once `config/operator-directives.json`, REQ-B1, exists; until then cite the originating
handoff's `D-`id or nl-issue id — concretely, not "the usual rules"), and prior incidents this
system already learned from (search docs/discoveries/, docs/decisions/, docs/reviews/ for "has
this already been burned by this shape before" — a design that re-introduces a documented past
failure is the reviewer's highest-value finding, and it is cheaper for you to find it first).
-->

## 3. Decisions (each with rationale + reversal cost)
<!--
REQUIRED — MANDATORY table, one row per non-trivial fork. Phase 2 of design-author's protocol.

A decision without a stated reversal cost has not actually been priced: per the harness's
two-tier reversibility model, an unpriced decision cannot be correctly sorted into
decide-and-go vs escalate-to-operator, which means deciding it unilaterally wasn't safe in the
first place. If a fork is genuinely the operator's call (business intent, irreversible spend,
subjective taste), say so in the Rationale column instead of deciding it for them.
-->

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-1 | [what was decided] | [why this, not the alternative] | [what it costs to undo] |

## 4. Architecture
<!--
REQUIRED for any design that introduces or changes a shape (component boundaries, an artifact
contract, a data flow, a source-of-truth). Draw module/section boundaries around what is LIKELY
TO CHANGE (Parnas information-hiding), not around today's flowchart of components — a boundary
drawn around an implementation detail invites a downstream plan to encode that detail as
load-bearing.

Any design that introduces or changes a data architecture, a source-of-truth boundary, a
read/write path, a cache/derived store, a cross-component data flow, or a consistency/staleness
contract MUST carry an `architecture-reviewer` verdict before any builder is dispatched
(doctrine/artifact-evidence-bar.md) — state the staleness contract explicitly if one applies:
how stale can a reader's view be, worst case?
-->

## Requirements
<!--
REQUIRED — this exact heading, unmodified. Machine-parsable: `plan-fidelity-reviewer` (REQ-B3)
checks the implementing plan against this table 1:1, and `plan-reviewer` Check 21 (REQ-B7)
parses this literal `## Requirements` heading to verify every MUST-REQ is claimed by at least
one plan task. A requirement that lives only in prose above this table is invisible to both —
if it matters, it gets a row.

Format: `REQ-id | MUST/SHOULD | requirement text, with its own verification stated INLINE (not
a separate column — a requirement whose sentence doesn't say how it's checked is unverifiable by
construction)`. Group into phases with sub-headers if the design has natural phases; keep the
`## Requirements` top-level heading exact regardless.
-->

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-1 | MUST | [requirement text]. Verify: [command/scenario that proves it]. |
| REQ-2 | SHOULD | [requirement text]. Verify: [command/scenario that proves it]. |

## Non-goals
<!--
REQUIRED. Phase 4. Everything a reader might reasonably expect this design to cover that it
deliberately does NOT — one line each, with where (if anywhere) it's tracked instead. An
unstated non-goal is how scope quietly creeps back in three plans later, because nobody wrote
down that it was ever excluded on purpose.
-->
- [capability a reader might expect] — [why excluded / where tracked instead, or "n/a — no
  future plan" if genuinely dropped]

## What this design gives up (named sacrifice)
<!--
REQUIRED — MANDATORY, and design-author's primary anti-rubber-stamp mechanism. Every
architecture trades something. Fill in, honestly:
  - the cheaper alternative you rejected, and why
  - the capability you deliberately did NOT build (distinct from Non-goals above: this is about
    cost/tradeoff, not scope — e.g. "every addition below this line, named, per D-07 anti-bloat:
    what does this design displace?")
  - the standing cost you are accepting (spawns × fire-rate, review latency, maintenance burden)
    and against what measured alternative

"A design that gives up nothing is unfinished" — an empty or hand-waved section here means
Section 3's Decisions table is decoration over a design that hasn't actually been decided yet.
If you cannot fill this honestly, return to Section 3 before finishing this one.
-->
- Rejected alternative: [what] — Why: [reason]
- Capability NOT built: [what] — Tracked as: [where, or "not tracked — deliberately dropped"]
- Standing cost accepted: [what, with a number if you have one] — Against: [the measured
  alternative this beats]

## Pre-mortem
<!--
REQUIRED — MANDATORY, design-author's second anti-rubber-stamp mechanism (Klein's prospective
hindsight — the same technique architecture-reviewer's Phase 4 applies to a design under
review, applied here to your OWN design before anyone else sees it).

Assume it is six months later and this design has failed badly. Write the incident report: what
broke, in what order, what the reader/operator saw, and why nobody noticed for weeks. Then state
what changes NOW, in this design, to make that story impossible. A design without a real
pre-mortem has not been adversarially tested against its own failure mode — "nothing will go
wrong" is not a pre-mortem, it's the absence of one.
-->

[the six-months-later incident report]

**What changes now to make that story impossible:**
[the concrete design change(s) this pre-mortem drove]

## Verification strategy
<!--
REQUIRED. How this design's own success is checked once built: self-tests, demonstrations, the
acceptance bar. Cycle-closing demonstrations belong here, not scattered across the Requirements
table's individual `Verify:` clauses — this section is the whole-design proof, not the per-REQ
one.
-->

## Directives honored
<!--
REQUIRED — this exact heading, unmodified (per the same parsing convention as `## Requirements`
above). `config/operator-directives.json` (REQ-B1) may not exist yet at authoring time. Once it
exists: cite every `OD-`id whose `surfaces` glob matches a path this design touches, one line
each — the same format the plan template's per-task `Directives:` field will use (REQ-B5). Until
it exists: name the binding operator directive by its handoff id (`D-NN`,
docs/handoffs/*-EXHAUSTIVE-issue-inventory.md Part 4) or its nl-issue id — concretely, so the
citation is auditable, never a bare "n/a" that just means nobody checked.

Forthcoming: once `config/operator-directives.json` exists, re-anchor this section's citations to
`OD-`ids and note the migration in the Changelog line for that round.
-->
- [directive id, `D-NN` or `OD-NNN`] — [one line: how this design honors it]

## Review Chain
<!--
STUB. `review-chain-lib.sh` (REQ-B6) is the sole validity oracle once it exists; until then this
section is documentation-only, but populate it in the SAME format so `design-ref:` and the
`design-reviews:` rows can be copied VERBATIM into the implementing plan's own `## Review Chain`
block (design r3 §4 of gated-pipeline-master-2026-08-03.md) — that is how this design's
`authored-by:` and its review verdicts become the plan's `design-ref:` anchor. Never leave this
section absent: an un-reviewed design cannot feed a chained plan (the authoring-path residual
this template exists to close).
-->
authored-by: design-author (model: fable)
<!--
Bootstrap-only exception: if this design predates the design-author agent's existence, name the
session honestly instead — "authored-by: <session label> (design-author agent does not exist
yet; provenance named honestly)" — see gated-pipeline-master-2026-08-03.md's own header for the
live precedent. Never claim design-author authorship you didn't have.
-->
design-reviews:
  - reviewer: architecture-reviewer  verdict: <PENDING>  record: <docs/reviews/... once landed>
  - reviewer: harness-reviewer       verdict: <PENDING>  record: <docs/reviews/... once landed —
    harness-surface designs only; omit the row entirely for designs with no harness surface>
