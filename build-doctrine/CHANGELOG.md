# Build Doctrine Changelog

## 2026-05-06 — v0.2 (Tranche 2: template schemas)

- 7 canonical template schemas at `build-doctrine/template-schemas/`:
  `prd.schema.yaml`, `adr.schema.yaml`, `spec.schema.yaml`,
  `design-system.schema.yaml`, `engineering-catalog.schema.yaml`,
  `conventions.schema.yaml`, `observability.schema.yaml`. Each is JSON
  Schema draft 2020-12 in YAML form, $id-versioned at v1.
- Seven round-trip-validating example instances at
  `build-doctrine/template-schemas/examples/`. Each validates against its
  schema via `jsonschema.validate` (Python).
- README at `build-doctrine/template-schemas/README.md` documenting the
  schema set, validation invocation patterns (Python + Node), and the
  relationship to Tranche 3 (content seeding).
- Schemas validate SHAPE (structural presence + cardinality + minimum
  substance threshold). Substance review remains the per-artifact reviewer
  agent's job.
- Schema-validation gates at commit time deferred until Tranche 3 ships
  consumer templates.

## 2026-05-05

- Phase 0 migration: 8 integrated-v1 doctrine docs migrated from Build Doctrine repo
  (`~/claude-projects/Build Doctrine/outputs/integrated-v1/`) into
  `build-doctrine/doctrine/`. Migration is byte-identical; no edits.
- Initial `README.md` and `CHANGELOG.md` created.
- See `docs/decisions/025-build-doctrine-same-repo-placement.md` for the
  decision to keep `build-doctrine-templates/` in the same repo as NL
  rather than a separate repo.
