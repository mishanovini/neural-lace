# 052 — DEFERRED plans go to `docs/plans/deferred/`, not `docs/plans/archive/`

- **Date:** 2026-06-04
- **Status:** Accepted / Implemented
- **Stakeholders:** Misha (operator), harness maintainers
- **Supersedes/relates:** extends the "Plan File Lifecycle" section of
  `rules/planning.md`; pairs with `plan-lifecycle.sh` + `plan-status-archival-sweep.sh`.

## Context

The plan lifecycle archived a plan on **any** terminal status flip — `COMPLETED`,
`DEFERRED`, `ABANDONED`, `SUPERSEDED` all `git mv`'d into `docs/plans/archive/`.
During the 2026-06-04 stale-plan cleanup, four design-complete-but-unimplemented
plans were flipped to `DEFERRED` and archived. Misha flagged the smell:

> "Deferred should go into the same category as backlog, meaning plans that are
> still intended to be built but are not currently active. Abandoned and
> superseded can be archived because those are intended to be done with."

The root issue: the lifecycle conflated two orthogonal axes —
**terminal-for-editing** (no more edits expected → the plan rests) and
**done-for-building** (no more *building* expected). `DEFERRED` is the first
but NOT the second: a deferred plan is paused, still-intended work. Archiving it
alongside `COMPLETED` plans loses the "still needs building" signal and buries
roadmap where the operator won't look.

## Decision

Split the lifecycle **destination** by status while keeping the
`is_terminal_status` gate unchanged (so Stop-hook semantics — a deferred plan
doesn't block session-end — are preserved):

- `COMPLETED` / `ABANDONED` / `SUPERSEDED` → `docs/plans/archive/` (done with).
- `DEFERRED` → `docs/plans/deferred/` (**intended but not currently active** —
  the plan-level backlog).

Mechanized in both lifecycle hooks (`plan-lifecycle.sh` PostToolUse,
`plan-status-archival-sweep.sh` SessionStart safety net), each with a self-test
locking DEFERRED→deferred/ (and asserting it does NOT land in archive/).
`find-plan-file.sh` searches active → deferred → archive. A
`docs/plans/deferred/README.md` documents the category and the
re-activate (flip back to ACTIVE → `git mv` back) / truly-drop (flip to
ABANDONED → archives) transitions.

## Alternatives considered

1. **Fold DEFERRED plans into `docs/backlog.md` as entries.** Rejected: plan
   files are large and structured; collapsing them into backlog bullets loses
   the plan content + design analysis. A directory IS the "plan backlog."
2. **Keep DEFERRED in top-level `docs/plans/` (no move).** Rejected: it would
   re-surface via the stale-active-plan-surfacer as if active, re-creating the
   noise the cleanup removed. A distinct resting place cleanly separates
   "active" from "intended-but-parked."
3. **A new non-terminal `PAUSED` status.** Rejected for now: `DEFERRED` already
   exists and carries the right meaning; adding a status is more churn and the
   Stop-hook/verifier vocabulary would all need extending. Revisit if the
   terminal-vs-parked distinction needs to be machine-visible beyond placement.

## Consequences

- **Enables:** deferred roadmap stays visible and re-activatable; archive/ holds
  only genuinely-done-with plans; the operator's "what's still intended" view is
  honest.
- **Costs:** a third plan directory to know about; `find-plan-file.sh` searches
  one more dir. A SessionStart surfacer for `deferred/` (so parked plans get
  nudged like the backlog) is a follow-up, filed as a harness gap.
- **Migration:** the four 2026-06-04 deferrals (doctrine-scoping-rules-authoring,
  file-lifecycle-redesign, principles-doctrine-authoring, session-resilience-redesign)
  move from archive/ → deferred/.
