<!-- scaffold-created: 2026-05-06T07:53:46Z by start-plan.sh slug=build-doctrine-tranche-2-template-schemas -->
# Plan: Build Doctrine Tranche 2 Template Schemas
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan — schemas are doctrine artifacts with no product user; validation is via mechanical schema-validate checks against round-trip example instances, not via runtime browser automation.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

Author the 7 canonical Build Doctrine template schemas (Tranche 2 / Phase 4a Layer B-shape per `docs/build-doctrine-roadmap.md`). Each schema is a JSON Schema (draft 2020-12) file that defines the structural shape every per-project instance of the corresponding canon artifact must conform to. After this tranche lands, the build-doctrine substrate has a stable shape-target for Tranche 3 (template content seeding) to validate against.

User-observable outcome: a downstream project bootstrapping per `08-project-bootstrapping.md` can validate its `prd.md`, `adr/*.md`, `spec/*.md`, `design-system.md`, `engineering-catalog.md`, `conventions.md`, and `observability.md` against the named schemas with a single `jq` or `ajv` invocation, surfacing missing required sections and shape errors before downstream work reads stale or malformed artifacts.

## Scope
- IN: 7 JSON Schema YAML files at `build-doctrine/template-schemas/`: prd.schema.yaml, adr.schema.yaml, spec.schema.yaml, design-system.schema.yaml, engineering-catalog.schema.yaml, conventions.schema.yaml, observability.schema.yaml. README.md at the same directory documenting the schema set + how to validate. One example instance per schema in `build-doctrine/template-schemas/examples/` that round-trip-validates against its schema. CHANGELOG.md entry under `build-doctrine/CHANGELOG.md` recording v0.2 schema-shipping.
- OUT: Schema-validation gates (deferred — schemas exist, gates ship later when consumed). Template CONTENT (Tranche 3). Schemas for non-doctrine artifacts (failure-modes, findings, evidence — those have their own canonical schemas). Template inheritance / extension mechanism (out of v1 scope; revisit if friction arises).

## Tasks

- [ ] 1. Author `build-doctrine/template-schemas/prd.schema.yaml` — 7 required sections (Problem / Scenarios / Functional / Non-functional / Success metrics / Out-of-scope / Open questions) per `adapters/claude-code/templates/prd-template.md`. Verification: contract
- [ ] 2. Author `build-doctrine/template-schemas/adr.schema.yaml` — Title / Date / Status / Stakeholders / Context / Decision / Alternatives / Consequences per `~/.claude/rules/planning.md` decision-record format. Verification: contract
- [ ] 3. Author `build-doctrine/template-schemas/spec.schema.yaml` — Goal / Scope / Tasks / Files / Assumptions / Edge Cases / Acceptance Scenarios / Testing Strategy per `adapters/claude-code/templates/plan-template.md`. Verification: contract
- [ ] 4. Author `build-doctrine/template-schemas/design-system.schema.yaml` — Tokens (color/spacing/typography/motion) / Components / States / Patterns per Build Doctrine 04-gates §design-system. Verification: contract
- [ ] 5. Author `build-doctrine/template-schemas/engineering-catalog.schema.yaml` — Work-shapes inventory (per `~/.claude/rules/work-shapes.md` shape format) per Build Doctrine Principle 2. Verification: contract
- [ ] 6. Author `build-doctrine/template-schemas/conventions.schema.yaml` — Per-language naming / branch-and-commit / project-layout per Build Doctrine 04-gates §conventions. Verification: contract
- [ ] 7. Author `build-doctrine/template-schemas/observability.schema.yaml` — Logs / metrics / traces / dashboards / alerts per Build Doctrine 04-gates §observability + 06-propagation. Verification: contract
- [ ] 8. Author one round-trip-validating example per schema at `build-doctrine/template-schemas/examples/<name>.example.{md,yaml}`. Verification: mechanical
- [ ] 9. Author `build-doctrine/template-schemas/README.md` documenting the schema set, the validation invocation pattern, and the relationship to Tranche 3 content seeding. Verification: mechanical
- [ ] 10. Update `build-doctrine/CHANGELOG.md` with v0.2 entry recording the schema-shipping. Verification: mechanical

## Files to Modify/Create
- `build-doctrine/template-schemas/prd.schema.yaml` — CREATE (Task 1)
- `build-doctrine/template-schemas/adr.schema.yaml` — CREATE (Task 2)
- `build-doctrine/template-schemas/spec.schema.yaml` — CREATE (Task 3)
- `build-doctrine/template-schemas/design-system.schema.yaml` — CREATE (Task 4)
- `build-doctrine/template-schemas/engineering-catalog.schema.yaml` — CREATE (Task 5)
- `build-doctrine/template-schemas/conventions.schema.yaml` — CREATE (Task 6)
- `build-doctrine/template-schemas/observability.schema.yaml` — CREATE (Task 7)
- `build-doctrine/template-schemas/examples/prd.example.md` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/adr.example.md` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/spec.example.md` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/design-system.example.yaml` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/engineering-catalog.example.yaml` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/conventions.example.yaml` — CREATE (Task 8)
- `build-doctrine/template-schemas/examples/observability.example.yaml` — CREATE (Task 8)
- `build-doctrine/template-schemas/README.md` — CREATE (Task 9)
- `build-doctrine/CHANGELOG.md` — MODIFY (Task 10)
- `docs/build-doctrine-roadmap.md` — MODIFY (Task 10) — flip Tranche 2 status to DONE
- `docs/plans/build-doctrine-tranche-2-template-schemas.md` — CREATE (this plan file itself; scaffolded by start-plan.sh)
- `docs/decisions/queued-build-doctrine-tranche-2-template-schemas.md` — CREATE (companion decisions queue scaffolded by start-plan.sh)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The integrated-v1 doctrine docs at `~/claude-projects/Build Doctrine/outputs/integrated-v1/` (already migrated to `build-doctrine/doctrine/` in Tranche 0b) are authoritative for the seven artifact shapes; schema authoring derives from them rather than re-deriving from first principles.
- The existing PRD template at `adapters/claude-code/templates/prd-template.md` is canonical for the PRD's seven sections; the schema mirrors its structure (the template is the human-authoring view; the schema is the machine-validation view of the same shape).
- JSON Schema draft 2020-12 is the canonical schema language (matches existing `evidence.schema.json` precedent in `adapters/claude-code/schemas/`).
- YAML serialization is preferred for the schema files themselves (machine-readable, also human-edit-friendly); JSON Schema validators (jq, ajv) accept YAML when piped through `yq` or equivalent.
- Round-trip-validation against example instances is the v1 verification bar; schema-validation gates that fire automatically at commit time are deferred (no consumers yet — gates ship when Tranche 3 templates need them).

## Edge Cases
- A schema declares a section as required but the corresponding template instance legitimately doesn't have that section (e.g., a project with no NFRs would fail PRD validation). Mitigation: make sections required at the structural level (heading must exist) but allow placeholder content with a documented sentinel ("n/a — explanation"). Schemas validate shape, not substance; substance is the reviewer agent's job.
- Schemas drift from the integrated-v1 docs over time as doctrine evolves. Mitigation: each schema's `description` field cites the source doctrine doc + section; CHANGELOG.md logs every schema bump; a future schema-doctrine-drift detector is HARNESS-GAP candidate.
- A downstream project bootstraps with v0.1 templates and the harness ships v0.2 schemas with new required sections. Mitigation: schemas declare `$id` with version; breaking changes increment the major version; downstream projects pin to a major version.
- Example instances drift from schemas (someone edits the example without revalidating). Mitigation: a `--self-test` style script in Task 9 walks every example and validates against its schema.
- The 7 schemas have overlapping concepts (e.g., "Status: ACTIVE" appears in both ADR and spec). Mitigation: extract shared definitions into a `_shared.schema.yaml` if friction surfaces; defer until a second instance of duplication is observed.

## Acceptance Scenarios

n/a — harness-development plan, no product user; see `acceptance-exempt-reason` in header.

## Out-of-scope scenarios

None — harness-development plan, acceptance-exempt.

## Testing Strategy
- **Schema-validity (each schema is itself well-formed JSON Schema):** `jq empty <schema-file>` exits 0 (or `python -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(sys.stdin.read())))" < schema | jq empty` for YAML).
- **Round-trip example validation (each example validates against its schema):** `python -c "import jsonschema, yaml, json, sys; jsonschema.validate(yaml.safe_load(open(sys.argv[1])), yaml.safe_load(open(sys.argv[2])))" <example> <schema>` exits 0 means example conforms.
- **Schema covers the integrated-v1 doctrine spec (manual review):** for each schema, walk the corresponding integrated-v1 doc section and confirm every named section has a corresponding required field in the schema. The README documents the mapping for reviewers.
- **Per-task verification:** Tasks 1-7 use `Verification: contract` (the round-trip example IS the truth-target); Tasks 8-10 use `Verification: mechanical` (file-exists + content checks via `write-evidence.sh capture`).

## Walking Skeleton

Walking Skeleton: n/a — pure schema authoring; no end-to-end runtime flow exists yet (consumers are Tranche 3 templates which haven't been authored). The "skeleton" equivalent is Task 1 (PRD schema) which is the simplest of the 7 and authoring it first establishes the file-shape pattern (YAML format, `$schema` declaration, required-field convention, descriptions citing doctrine) for the other 6.

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol)

## Definition of Done
- [ ] All 10 tasks checked off
- [ ] All 7 schemas validate against `jq empty` (well-formed JSON Schema)
- [ ] All 7 example instances round-trip-validate against their schemas (jsonschema.validate exits 0)
- [ ] README documents the validation invocation pattern
- [ ] build-doctrine/CHANGELOG.md updated with v0.2 entry
- [ ] docs/build-doctrine-roadmap.md Quick status table flipped: Tranche 2 → ✅ DONE
- [ ] Plan closed via `~/.claude/scripts/close-plan.sh close build-doctrine-tranche-2-template-schemas`
