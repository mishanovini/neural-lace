# Decision 015 — PRD-validity gate (C1): single `docs/prd.md` per project + 7 required sections + harness-development carve-out

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (Status: ACTIVE)
**Related backlog:** HARNESS-GAP-10 sub-gap E (C16 behavioral-contracts validator must require concrete invariants — partially addressed by this decision package)
**Related Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C1

## Context

Build Doctrine §6 C1 specifies a PRD-validity gate that fires on plan creation: every plan declares a `prd-ref:` field; the hook resolves the reference to a PRD file and verifies that file's required sections are present and substantive. The motivation: plan creation today does not require any prior product-document, so plans can be authored without a documented user-need, success criteria, or out-of-scope boundary. Build Doctrine §6 closes that loop by requiring a PRD before a plan that claims to address it can be created.

Two implementation details require explicit decisions before C1 can be built:

1. **PRD file path layout.** Build Doctrine §6 C1's default is per-slug PRDs at `docs/prd/<slug>.md`. SCRATCHPAD's lock (recorded by the user during phase-1d-C-2 planning) is single `docs/prd.md` per project. The two are incompatible — choose one.
2. **Harness-development carve-out.** Harness-development plans (this plan, plus all maintainer-internal harness work) are not building a product for end users; they build the harness itself. Forcing those plans to maintain a PRD is overhead with no audience to serve. Some bypass is required.

Without a decision on (1), the C1 hook cannot resolve the `prd-ref:` field. Without a decision on (2), C1 would block every harness-internal plan or force fake PRDs that read identically across plans.

## Decision

### Decision 015a — Single `docs/prd.md` per project (NOT per-slug)

Every project covered by C1 maintains exactly **one** PRD file, located at `docs/prd.md` (repo-relative). Plans whose `prd-ref:` field names a slug (e.g., `prd-ref: duplicate-campaign-feature`) all resolve to the same `docs/prd.md`; the slug is informational, not a path component. The C1 hook reads `docs/prd.md` and verifies its sections; the slug serves as an audit trail for which feature each plan claims to advance.

### Decision 015b — Seven required PRD sections

The PRD has seven required sections, each with ≥ 30 non-whitespace characters of substantive content (no placeholder-only):

1. **Problem** — what user pain or business gap this product addresses
2. **Scenarios** — concrete user stories or end-to-end flows the product must support
3. **Functional requirements** — what the product does (numbered FRs)
4. **Non-functional requirements** — performance, reliability, security, accessibility constraints (numbered NFRs)
5. **Success metrics** — measurable targets (numeric, not adjectival) that define "we shipped the right thing"
6. **Out-of-scope** — explicit list of adjacent things this product is NOT
7. **Open questions** — known unknowns the team is still resolving

Section ordering is suggested but not enforced; the hook locates sections by their `##`-level heading text.

### Decision 015c — Harness-development carve-out via `prd-ref: n/a — harness-development`

Plans whose `prd-ref:` field is the exact string `n/a — harness-development` (em-dash; exact phrasing) bypass the C1 hook entirely. The PRD file is not required; no section check fires. The carve-out string mirrors the existing `acceptance-exempt: true` + `acceptance-exempt-reason:` audit pattern: chronic use is auditable; the bypass is explicit.

The carve-out applies to plans whose work product is the harness itself (rules, hooks, agents, templates, decision records). It does NOT apply to plans whose work product is a downstream product the harness is being used to build.

## Alternatives considered

- **Per-slug `docs/prd/<slug>.md` (Build Doctrine §6 default).** Rejected per Decision 015a. Simpler-and-stronger: one PRD-per-project matches typical product-org practice; multiple PRDs per project introduce questions about which PRD a plan-without-slug references and increase the number of files to maintain. The single-file invariant lets the C1 hook stay simple.
- **Allow either per-slug OR single-file.** Rejected. Allowing both shapes means the C1 hook must check two conventions; downstream tooling that reads PRDs becomes branchy. One canonical layout is worth more than flexibility no project will use.
- **Skip C1 entirely for harness-dev.** Rejected per Decision 015c. The carve-out string makes the bypass explicit and auditable; a global skip of C1 for harness-dev would be silent and non-reviewable.
- **Write a real PRD for the harness itself.** Rejected per Decision 015c. The harness is a kit, not a product with an end-user audience; a PRD authored against itself does not produce useful constraints and would be largely tautological.
- **Use a different carve-out string.** Considered alternative phrasings (`harness-internal`, `n/a`, `none`). Rejected — the chosen phrasing matches the precedent of `acceptance-exempt-reason`'s narrative form, makes intent obvious to a reviewer scanning a plan header, and the em-dash discourages typo-paste of a fake bypass.

## Consequences

**Enables:**
- Plan creation can be gated on a documented user-need before the plan is even drafted.
- The PRD becomes the canonical artifact for "what are we building and why" — separate from the plan's "how are we building it."
- Audit of carve-out usage is mechanical: `grep "n/a — harness-development" docs/plans/*.md` lists every harness-dev plan; out-of-pattern bypasses are visible.

**Costs:**
- Every downstream project that adopts C1 must author and maintain a PRD before any plan-with-claim can be created. This is a one-time cost per project; ongoing maintenance is light (PRDs evolve with the product but slowly).
- The single-file invariant means a project with multiple distinct features lists them all in one `docs/prd.md`. For projects with > 5 distinct major features, this file grows large. Mitigation: use sub-headings within each `##` section; the section-presence check does not enforce length caps.

**Blocks:**
- Plans claiming a `prd-ref:` slug whose underlying section content has not been authored will be blocked at plan-creation time. Recovery: author or update `docs/prd.md` with the missing content first, then re-create the plan.

## Implementation status

Active — to be enforced by `adapters/claude-code/hooks/prd-validity-gate.sh` (Task 3 of the parent plan). The PRD template at `adapters/claude-code/templates/prd-template.md` ships with this decision (Task 1) so authors have a starting point.

## Failure modes catalogued

- `FM-NNN missing-PRD-on-plan-creation` — to be added to `docs/failure-modes.md` in Task 10 of the parent plan. Symptom: plan author runs `Write` on `docs/plans/<slug>.md` declaring `prd-ref: <slug>` but `docs/prd.md` does not exist or lacks required sections. Detection: PreToolUse Write hook resolves the reference, finds gap, blocks. Prevention: author the PRD first; use the carve-out only when genuinely working on the harness itself.

## Cross-references

- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — the implementing plan
- `adapters/claude-code/templates/prd-template.md` — canonical template (Task 1)
- `adapters/claude-code/hooks/prd-validity-gate.sh` — the hook (Task 3)
- `adapters/claude-code/agents/prd-validity-reviewer.md` — substance reviewer agent (Task 7)
- `adapters/claude-code/rules/prd-validity.md` — the rule documenting when PRDs are required (Task 2)
- Decision 016 — spec-freeze gate; the natural sibling that operates downstream of plan creation
- Decision 017 — 5-field plan-header schema; `prd-ref:` is one of the five required fields
