# Decision 017 — Plan-header schema locked: 5 required fields, no defaults, gated on `Status: ACTIVE`

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (Status: ACTIVE)
**Related Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 + §9 Q4-A

## Context

Plans grew header fields organically over the harness's evolution: `Status:`, `Execution Mode:`, `Mode:`, `Backlog items absorbed:`, `acceptance-exempt:`, `acceptance-exempt-reason:`. Build Doctrine §6 introduces five additional fields that classify the plan along orthogonal axes:

1. `tier` — work sizing per Build Doctrine `03-work-sizing.md` (1=Contained, 2=Schema-Bound, 3=Cross-Module, 4=Contract, 5=Novel)
2. `rung` — autonomy / sophistication tier (0=read-only-context, 1=knowledge-integrator, 2=early-stage, 3=formalized, 4=autonomous, 5=meta)
3. `architecture` — which architectural family the work targets (`coding-harness`, `dark-factory`, `auto-research`, `orchestration`, `hybrid`)
4. `frozen` — spec-freeze flag (Decision 016)
5. `prd-ref` — PRD reference (Decision 015)

Each field gates downstream behavior:

- `tier` gates which review pipeline a change goes through (Tier 4+ requires architecture review per `04-gates.md`)
- `rung` gates `## Behavioral Contracts` requirement at `rung: 3+` (C16, this plan's Task 6)
- `architecture` gates which architectural-family-specific tooling activates
- `frozen` gates `spec-freeze-gate.sh` (Decision 016)
- `prd-ref` gates `prd-validity-gate.sh` (Decision 015)

Without a definitive schema, downstream gates cannot rely on the fields being present, valid, or unambiguously interpretable. The schema must be locked: which fields, what values they accept, what defaults (if any) apply, and on which plans the schema is enforced.

## Decision

### Decision 017a — Five fields required on every `Status: ACTIVE` plan

Every plan whose `Status:` is `ACTIVE` must declare all five fields in its header. Plans with `Status: COMPLETED`, `DEFERRED`, `ABANDONED`, or `SUPERSEDED` are exempt from the schema check (the `plan-reviewer.sh` Check 10 only fires on `Status: ACTIVE`); historical plans authored before this decision shipped do not need backfill if they are already in a terminal state.

The field set is fixed: `tier`, `rung`, `architecture`, `frozen`, `prd-ref`. Adding a sixth field is a new decision (a follow-up amendment to this record); reducing to four is a relaxation that requires its own decision.

### Decision 017b — No defaults; missing fields FAIL

Any of the five fields, if missing on an `ACTIVE` plan, FAILs `plan-reviewer.sh` Check 10. There are no implicit defaults. The author must declare every field explicitly. Rationale: defaults would silently propagate the wrong shape. If a plan is truly `tier: 1, rung: 0, architecture: coding-harness, frozen: false, prd-ref: n/a — harness-development`, authoring those values is one minute of work; defaulting them invites every plan to inherit values that may not match the actual work.

The harness-development carve-out for `prd-ref` (per Decision 015c) is the only "default-shaped" affordance: `prd-ref: n/a — harness-development` is a valid value, and harness-internal plans use it routinely. But the field MUST still be present; the carve-out is a value, not an absence.

### Decision 017c — Valid value enums

| Field | Valid values | Source |
|---|---|---|
| `tier` | `1`, `2`, `3`, `4`, `5` (integers) | Build Doctrine `03-work-sizing.md` |
| `rung` | `0`, `1`, `2`, `3`, `4`, `5` (integers) | Build Doctrine §6 + autonomy tier definitions |
| `architecture` | `coding-harness`, `dark-factory`, `auto-research`, `orchestration`, `hybrid` | Build Doctrine §9 Q4-A |
| `frozen` | `true`, `false` (lowercase, no quotes) | Decision 016 |
| `prd-ref` | non-empty string (any value); semantic validation belongs to C1, not the schema check | Decision 015 |

Out-of-range values FAIL Check 10 with a message naming the offending field, the offending value, and the valid set.

### Decision 017d — Schema check is mode-agnostic

`plan-reviewer.sh` Check 10 fires regardless of the plan's `Mode:` (`code` / `design` / `design-skip`). All three modes need consistent classification along the five axes. Some modes may render some fields trivially-true (a `Mode: design-skip` plan is almost always `tier: 1, rung: 0`), but the field must still be present.

This contrasts with the existing Mode-gated Checks 7-9 (which only fire on `Mode: design`); Check 10 (5-field schema) and Check 11 (C16 behavioral contracts at `rung: 3+`) fire across modes.

### Decision 017e — Backfill required for existing ACTIVE plans

Plans currently `Status: ACTIVE` at the time this decision lands MUST be backfilled with the five fields. Default values for harness-development plans: `tier: 1, rung: 0, architecture: coding-harness, frozen: false, prd-ref: n/a — harness-development`. The backfill is Task 8 of the parent plan and lands in the same plan-execution that ships the schema check.

## Alternatives considered

- **Defaults for unspecified fields.** Rejected per Decision 017b. Defaults silently mask incorrect classification; explicit fields force the author to think.
- **Schema as a separate file (`docs/plan-schema.json`).** Considered. Rejected for now — the five-field shape is small enough to live in the rule and the reviewer hook; a separate schema file adds tooling overhead. If the schema grows beyond ~10 fields, revisit.
- **Schema check fires only on `Mode: design`.** Rejected per Decision 017d. The five fields classify orthogonally to Mode; gating on Mode would leave most plans unclassified.
- **Allow `architecture: null` for plans that don't fit any family.** Rejected. The `hybrid` value already covers cross-family cases. A `null` value would hide the classification decision rather than surface it.
- **Make `prd-ref` validate against `docs/prd.md` at schema-check time (merge with C1).** Rejected — separation of concerns is cleaner. C1 (`prd-validity-gate.sh`) does semantic validation of the reference; Check 10 does shape validation of the field. The two gates compose: a plan with `prd-ref: my-feature` passes Check 10 (field present, non-empty) but may FAIL C1 (PRD missing or incomplete).

## Consequences

**Enables:**
- Downstream gates can rely on every active plan being classified along the five axes.
- Audit queries are easy: `grep -h "^tier:" docs/plans/*.md | sort | uniq -c` shows tier distribution.
- New gates can be designed against the field set without re-validating its presence.

**Costs:**
- Every new plan adds five lines to its header. Friction is small (~30 seconds per plan); the audit benefit is durable.
- Backfilling existing active plans is a one-time effort (Task 8). Plans archived before this decision do not need backfill.

**Blocks:**
- Plans with missing or invalid header fields will not pass `plan-reviewer.sh`. Recovery: add the missing fields, fix invalid values, re-run the reviewer. The block-message names the failing field, so recovery is mechanical.

## Implementation status

Active — to be enforced by `adapters/claude-code/hooks/plan-reviewer.sh` Check 10 (Task 5 of the parent plan).

## Failure modes catalogued

- `FM-NNN missing-plan-header-field` — to be added to `docs/failure-modes.md` in Task 10 of the parent plan. Symptom: plan-reviewer.sh Check 10 reports a missing or out-of-range field on an ACTIVE plan. Detection: regex extraction + enum validation. Prevention: use the plan template (which includes all five fields with placeholder guidance); when promoting a plan from `Status: DRAFT` to `Status: ACTIVE`, confirm header field set.

## Cross-references

- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — the implementing plan
- `adapters/claude-code/hooks/plan-reviewer.sh` — Check 10 lives here (Task 5)
- `adapters/claude-code/templates/plan-template.md` — extended with the five fields + inline guidance (Task 1)
- Decision 015 — PRD-validity (`prd-ref` field semantics)
- Decision 016 — spec-freeze (`frozen` field semantics)
- Decision 018 — spec-section divergence (records why `## Provides`/`## Consumes`/`## Dependencies` are NOT part of this schema)
