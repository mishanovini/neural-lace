# UX Review — Roadmap master-plan hierarchy IA (R11), 2026-07-28

ux-designer plan-time review, operator-requested (Round 11: "Do we need to bring in the UX
designer?"). Input: docs/reviews/2026-07-17-cockpit-ux-design-input.md Round 11 direction
(R11-A/B/C) + live /api/roadmap (49 plans, 5 projects) + real plan files.

**Verdict: FAIL as-proposed — direction approved (mechanical hierarchy, honest absence,
phase-retirement), SIX build-blocking Critical constraints + six Important. This file is the
BINDING build spec for the R11 renderer round; the full finding bodies live in the session
transcript (agent a2036873, 2026-07-28) — constraints reproduced here in full effect.**

## The six Critical constraints (build-blocking)
1. BATCH SOURCE: batch structure derives ONLY from (a) `###` sub-headings inside `## Tasks`
   or (b) checkbox-line ID TOKENS whose letters form CONTIGUOUS runs in file order — NEVER
   from title text (PROVEN trap: conversation-quality-phase2-2026-06-23.md's letters are
   title cross-references over plain 0-9 ids; title-derivation would invert its real P0→P5
   priority order). FILE ORDER is always the rendered order — batches are labels on
   contiguous runs, never a sort key.
2. BATCH LABELS: quote the file's own `###` heading VERBATIM ("Phase B — …" is correct and
   operator-endorsed at this level); letters-only plans render the mechanical span "Tasks
   A1–A7"; the "foundations→engine→…" gloss NEVER renders (practice, not data). General law:
   every derived level's label must quote a string that exists in the source artifact.
3. RETROFIT SAME-ROUND: renderer rebuild + `parent-plan:` retrofit of verified-real families
   ship together; acceptance oracle = "master nodes visibly group their REAL children on the
   live tree", never "renderer supports parent-plan". A level rendering for zero real
   artifacts is scaffolding, not shipped.
4. REFERENCE LIFECYCLE: (1) a master with ANY non-terminal child is PINNED on the tree
   regardless of its own aging/archive; (2) dangling parent → child renders standalone +
   badge "parent '<slug>' not found"; (3) resolution is same-project-scoped; (4) cycles
   break at the back-edge and flag both plans. General law: every reference-typed field
   carries explicit missing/terminal/duplicate behavior.
5. MASTER PROGRESS: TWO labeled counts ("plans 2/7 · own tasks 3/5"), never one blended bar
   (C2-family double-count is structural); task anchors (`parent-plan: slug#task`) are the
   double-count-free upgrade — an anchored task's status derives from its child plan and
   leaves the own-tasks count. General law: every fraction names its unit; bare fractions
   prohibited surface-wide.
6. DEFAULT EXPANSION — ACTIVE-PATH POLICY: L0 project groups open; EVERY L1 row always
   visible as exactly ONE line; auto-open only chains leading to in-progress / live-session
   / waiting-on-operator nodes; I2 completed-collapse unchanged; persisted openSet always
   wins. (~5 headers + 49 one-line rows + active chains ≈ one screen.)

## The six Important constraints
I1 master's two child kinds render as two LABELED subsections ("Plans — build order" then
"Direct tasks — task id"); anchors nest child plans under their task rows. I2 ordering rule
renders ONCE per expanded container as a muted caption ("build order — ↑/↓ to change" /
"file order — the plan's own sequence"), plus "#k of n" chips only on build-ordered rows.
I3 reorder scoped WITHIN the current sibling list; feedback names the container; parent
reassignment is file-edit-only this round. I4 filter matches render with their full ancestor
chain; kanban cards stay PLANS (masters are chips on child cards, never cards). I5 repo-wide
"phase" terminology sweep with per-hit disposition (user-facing → change; verbatim
plan-heading quotes → allowed; internal identifiers → rename/annotate) — incl. the R10-4
toast ("now #N of M in <container>'s build order"). I6 master/batch rows reuse the
details/summary renderNode path (C9 a11y by construction).

## Tree anatomy (the build target)
L0 project header: name · "N of M plans complete" bar · four-bucket count strip
(upcoming / in progress / partially done / complete; merged-unverified maps to partially
done per the operator's R3 complete oracle). L1 masters + standalone plans, one line each,
build order: `▸ #3 of 9 · <H1 title> · [master — 7 plans] · status+age · plans 2/7 · own
tasks 3/5 · project chip` (the [master] tag ONLY from resolved children). L2 under a master:
anchored tasks with nested child plans, else the two labeled subsections. L3 batch rows only
when the file carries them (verbatim heading label + fraction chip). L4 tasks (one line,
file order). L5/6 subtasks + live-session leaves; unattributed-sessions node stays at tree
bottom. Bars at L0-L2 container levels only; chips at leaves. Nice-to-have: bucket counts as
filter toggles.

## Decide-and-go defaults recorded by the reviewer
(a) moving a plan under/out of a master stays file-edit-only this round; (b) cross-repo
parent-plan links out of scope until configured — same-project resolution only.
