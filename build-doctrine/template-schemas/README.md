# Build Doctrine — Template Schemas (v1)

Canonical structural shapes for the seven per-project canon artifacts a
Build-Doctrine-aligned project commits to. These are **shape** schemas
(JSON Schema draft 2020-12); substance review is the per-artifact reviewer
agent's job (e.g., `prd-validity-reviewer` for PRDs).

Authored by Tranche 2 of the Build Doctrine integration arc; see
[`docs/build-doctrine-roadmap.md`](../../docs/build-doctrine-roadmap.md)
and [`docs/decisions/025-build-doctrine-same-repo-placement.md`](../../docs/decisions/025-build-doctrine-same-repo-placement.md).

## The seven schemas

| Schema | Artifact | Source doctrine doc | Path convention |
|---|---|---|---|
| `prd.schema.yaml` | Product Requirements Document | `04-gates.md` §PRD-validity + `adapters/claude-code/templates/prd-template.md` | `docs/prd.md` |
| `adr.schema.yaml` | Architectural Decision Record | `04-gates.md` §ADR + `~/.claude/rules/planning.md` | `docs/decisions/NNN-<slug>.md` |
| `spec.schema.yaml` | Plan / Specification | `04-gates.md` §spec-validity + `adapters/claude-code/templates/plan-template.md` | `docs/plans/<slug>.md` |
| `design-system.schema.yaml` | Design System | `04-gates.md` §design-system + `~/.claude/rules/ux-design.md` + `~/.claude/rules/ux-standards.md` | `docs/design-system.md` |
| `engineering-catalog.schema.yaml` | Engineering Catalog | `01-principles.md` Principle 2 + `~/.claude/rules/work-shapes.md` | `docs/engineering-catalog.md` |
| `conventions.schema.yaml` | Conventions | `04-gates.md` §conventions + `~/.claude/rules/git.md` + per-language harness rules | `docs/conventions.md` |
| `observability.schema.yaml` | Observability | `04-gates.md` §observability + `06-propagation.md` + `~/.claude/rules/design-mode-planning.md` §6 | `docs/observability.md` |

## Validating an instance

The schemas are JSON Schema draft 2020-12 in YAML form. To validate an instance:

### Python (recommended — built-in support for YAML)

```bash
python -c "
import jsonschema, yaml, sys
schema = yaml.safe_load(open(sys.argv[1]))
instance = yaml.safe_load(open(sys.argv[2]))
jsonschema.validate(instance, schema)
print('PASS: instance conforms to schema')
" path/to/schema.yaml path/to/instance.yaml
```

Exit code 0 means the instance conforms. A non-zero exit prints the
specific validation error (which field failed, what was expected, what
was received).

### Node (ajv via yq for YAML→JSON)

```bash
yq -o=json path/to/schema.yaml > /tmp/schema.json
yq -o=json path/to/instance.yaml > /tmp/instance.json
ajv validate -s /tmp/schema.json -d /tmp/instance.json
```

### Validating all examples in this directory

```bash
for schema_file in build-doctrine/template-schemas/*.schema.yaml; do
  base=$(basename "$schema_file" .schema.yaml)
  example="build-doctrine/template-schemas/examples/${base}.example.yaml"
  [ -f "$example" ] || continue
  python -c "
import jsonschema, yaml, sys
schema = yaml.safe_load(open(sys.argv[1]))
instance = yaml.safe_load(open(sys.argv[2]))
jsonschema.validate(instance, schema)
print(f'PASS: {sys.argv[2]}')
" "$schema_file" "$example"
done
```

## What the schemas validate

**SHAPE** — the structural presence and types of fields, the cardinality of
arrays, the enumerated values of fixed-vocabulary fields, the minimum
substance threshold (typically ≥ 30 non-whitespace chars for prose
sections).

**NOT SUBSTANCE** — whether the prose is high-quality, whether assumptions
are sound, whether the alternatives section honestly considers real
alternatives. That's the reviewer agent's job:

- `prd-validity-reviewer` for PRDs
- (no agent yet) for ADRs, design-system, conventions, observability —
  reviewer agents land in Tranche 7 if pilot friction reveals the need

## Versioning

Each schema has a `$id` URL embedding a major version (e.g., `prd.v1.schema.yaml`).
Breaking changes (renaming a required field, removing a section) increment the
major version. Additive changes (adding optional fields, relaxing min-length)
stay within the same major version.

The seven schemas all currently start at v1. CHANGELOG.md entries in
`build-doctrine/CHANGELOG.md` track the per-schema version history.

## Relationship to Tranche 3 (template content)

Tranche 2 (this) ships the SHAPE.

Tranche 3 ships the CONTENT — default templates seeded into
`build-doctrine-templates/<artifact>/` per universal floor and depth tier.
Each Tranche 3 template instance must round-trip-validate against its
schema here.

When a project bootstraps per `08-project-bootstrapping.md`, it copies
the appropriate templates from `build-doctrine-templates/` into its own
`docs/`, then customizes. The schemas validate that the customized
artifacts still match the canonical shape.

## Future work (not in v1)

- **Schema-validation gate** at commit time, blocking commits to declared
  artifact paths if the artifact fails schema validation. Deferred until
  Tranche 3 ships consumer templates.
- **Cross-artifact consistency** (e.g., a spec's `prd_ref` must resolve
  to a section in the project's PRD). C8 in the doctrine; not yet
  implemented.
- **Per-project schema overrides** (e.g., a project that wants stricter
  rules than the v1 defaults). Out of v1 scope; revisit if friction
  surfaces.
