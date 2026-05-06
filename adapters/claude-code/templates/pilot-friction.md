# Pilot Friction Notes — `<pilot-project-name>` — `<YYYY-MM-DD>`

<!--
This template is the canonical shape for friction notes captured during a
canonical-pilot session (Tranche 4 of the Build Doctrine integration arc).
The Tranche 4 session writes one of these per work-item-run-through-doctrine
in the pilot project's repo at:

  <pilot-repo>/docs/sessions/<YYYY-MM-DD>-pilot-friction.md

Friction notes are the empirical input that unlocks Tranches 5b (cadence
calibration), 6b (per-canon rules), and 7 (residual C-mechanisms). Without
structured friction notes, pilot evidence is operator memory rather than
counted observations.

Cross-references:
  - build-doctrine/doctrine/08-project-bootstrapping.md (Stage 0 + Universal Floors)
  - build-doctrine/doctrine/06-propagation.md (PT-1..PT-7 trigger taxonomy)
  - build-doctrine/doctrine/07-knowledge-integration.md (KIT-1..KIT-7 trigger taxonomy)
  - docs/plans/tranche-4-canonical-pilot-handoff.md (Tranche 4 handoff)
  - adapters/claude-code/scripts/analyze-propagation-audit-log.sh (audit-log analyzer)

When complete, the friction notes feed into:
  - This NL repo's docs/reviews/<date>-pilot-<run-N>-friction.md (cross-link from pilot's repo)
  - Tranche 5b's cadence calibration analysis (which trigger thresholds were right? wrong?)
  - Tranche 6b's per-canon rule design (which canon artifacts churned vs. stable?)
  - Tranche 7's residual C-mechanism prioritization (which 14 mechanisms did the pilot need most?)

Replace every `<placeholder>` with concrete content. Sections with no friction
to report should still be filled with "n/a — no friction observed" so the
absence is itself a captured signal.
-->

## Run metadata

- **Pilot project:** `<project-name>`
- **Pilot repo:** `<absolute-or-org/repo path>`
- **Work item this run exercised:** `<feature / bug / refactor name>`
- **Run number:** `<1, 2, 3 ...>` (pilots have multiple runs; this is the Nth)
- **Run date:** `<YYYY-MM-DD>`
- **Engagement mode declared:** `Express | Standard | Deep`
- **Architecture-axis (Karpathy test result):** `coding-harness | dark-factory | auto-research | orchestration | hybrid`
- **Total wall time for this run:** `<minutes / hours>`
- **Operator:** `<your name>` (informs calibration roll-up; persistent across runs)

## Universal floors exercised

For each floor the work item exercised (if any), capture friction. Skip floors not exercised this run.

### Floor 1 — Logging
- **Exercised:** `yes | no`
- **Did the template default match what the pilot actually needed?** `yes | no — describe deviation`
- **Friction observed:** `<concrete friction or "n/a">`
- **Floor change suggestion:** `<change to floor template OR "none">`

### Floor 2 — Error handling
(same shape)

### Floor 3 — Secrets handling
(same shape)

### Floor 4 — Input validation
(same shape)

### Floor 5 — Auth and authorization
(same shape)

### Floor 6 — Observability beyond logs
(same shape)

### Floor 7 — Testing
(same shape)

### Floor 8 — Documentation in code
(same shape)

### Floor 9 — Dependency policy
(same shape)

### Floor 10 — Versioning
(same shape)

### Floor 11 — UX standards (UI projects only)
(same shape)

## Per-canon-artifact friction

For each of the 7 canon artifacts the pilot generated or referenced.

### `docs/prd.md`
- **Did the schema (build-doctrine/template-schemas/prd.schema.yaml) capture what the pilot needed?** `yes | no — describe`
- **Did substance review (prd-validity-reviewer) catch real issues, or fire on noise?** `<observation>`
- **Friction:** `<concrete or "n/a">`

### `docs/conventions.md`
- **Did the templates (build-doctrine-templates/conventions/) provide good defaults for the pilot's stack?** `<observation>`
- **What conventions did the pilot OVERRIDE from the defaults? Why?** `<list>`
- **Friction:** `<concrete or "n/a">`

### `docs/design-system.md` (UI projects only)
(same shape)

### `docs/engineering-catalog.md`
- **Did the work item match a canonical work-shape, or surface a new shape needing definition?** `<observation>`
- **If a new shape: did its mechanical-compliance checks make sense?** `<observation>`

### `docs/observability.md`
(same shape)

### `docs/decisions/NNN-*.md` (ADRs created during run)
- **List ADRs created:** `<NNN-slug, NNN-slug>`
- **Friction with ADR creation flow (decisions-index-gate, plan-reviewer Check 11, etc.):** `<observation>`

### `.bootstrap/state.yaml`
- **Did this run revise the bootstrap state? What changed?** `<observation>`

## Propagation engine fan-out

When work-item changes touched multiple canon artifacts, did the propagation engine catch the fan-out correctly?

- **Audit log path:** `<repo>/build-doctrine/telemetry/propagation.jsonl`
- **Total events fired this run:** `<from analyze-propagation-audit-log.sh summary>`
- **Rules that fired most:** `<from analyze-propagation-audit-log.sh cadence>`
- **Unmatched event types (negative space — candidates for new rules):** `<from unmatched cmd>`
- **Conjectural-rule disposition candidates (rules ready for promotion):** `<list>`
- **PT-1 (contract change) friction:** `<observation or "n/a — Tranche 6b not yet shipped">`
- **PT-2 (component change) friction:** `<observation or "n/a">`
- **PT-7 (cross-repo) friction:** `<observation or "n/a">`

## Knowledge-integration ritual triggers

(KIT-1..KIT-7 from `build-doctrine/doctrine/07-knowledge-integration.md`)

- **KIT-1 (calibration pattern):** did this run produce calibration entries that suggest a doctrine update? `<observation>`
- **KIT-2 (findings pattern):** did findings accumulate that suggest a doctrine update? `<observation>`
- **KIT-3 (discovery accumulation):** did discoveries surface that suggest a doctrine update? `<observation>`
- **KIT-4 (ADR cross-reference staleness):** did ADRs go stale relative to doctrine? `<observation>`
- **KIT-5 (`/harness-review` trigger):** what did `/harness-review` Check 13 surface? `<summary>`
- **KIT-6 (propagation-engine audit-log trigger):** what did the audit-log analyzer surface? `<summary>`
- **KIT-7 (drift signal):** `n/a — Tranche 5c not yet shipped`

## Substrate gaps observed

What did the pilot need that didn't exist in the substrate? List as backlog candidates.

- `<gap 1: needed X, got Y; recommend Z>`
- `<gap 2: ...>`

If no gaps, state explicitly: "no substantive substrate gaps observed this run."

## Doctrine revision proposals

Concrete proposals for revising the doctrine docs in this NL repo based on this run's friction. Each entry should be specific enough to action.

- **`<doc-name>` `<section>`:** `<proposed change + reason>`
- **`<doc-name>` `<section>`:** `<proposed change + reason>`

If no revisions proposed: "no doctrine revisions proposed this run."

## Hypotheses confirmed / refuted

5a tags certain numbers + thresholds as `(hypothesis, pending pilot evidence)`. This run's evidence on each:

- **Knowledge-integration cadence (5a hypothesis: monthly):** `<confirmed | refuted with evidence | insufficient evidence yet>`
- **PT-6 findings-pattern threshold (6a hypothesis: ≥3 within 7 days):** `<confirmed | refuted with evidence | insufficient evidence yet>`
- **Per-rule performance budget (6a hypothesis: 1000ms v1 / 100ms target):** `<observed range>`
- **Conjectural-rule promotion threshold (5a-integration hypothesis: ≥3 matched events):** `<observed counts>`

## Cross-link

- **NL-side review:** when this friction note is reflected in `<NL-repo>/docs/reviews/<date>-pilot-<run-N>-friction.md`, link here: `<path>`
- **Affected backlog items:** `<HARNESS-GAP-N, HARNESS-GAP-N>`
- **Resulting doctrine commits (if any):** `<commit SHA, commit SHA>`

## Recommended next-pilot-run focus

What this run learned that should shape the next run's exercise:

- `<focus 1>`
- `<focus 2>`

If this is the last planned run before declaring Tranche 4 closed, document why: `<reason>`.
