# Conventions templates

Default content for the convention categories every Build-Doctrine-aligned project addresses. Authored by Tranche 3; see [`docs/build-doctrine-roadmap.md`](../../docs/build-doctrine-roadmap.md).

## Layout

```
conventions/
├── universal-floors/
│   ├── 01-logging/{express,standard}.md
│   ├── 02-error-handling/{express,standard}.md
│   ├── 03-secrets-handling/{express,standard}.md
│   ├── 04-input-validation/{express,standard}.md
│   ├── 05-auth-and-authorization/{express,standard}.md
│   ├── 06-observability-beyond-logs/{express,standard}.md
│   ├── 07-testing/{express,standard}.md
│   ├── 08-documentation-in-code/{express,standard}.md
│   ├── 09-dependency-policy/{express,standard}.md
│   ├── 10-versioning/{express,standard}.md
│   └── 11-ux-standards/{express,standard}.md   ← UI projects only
├── naming/
│   ├── javascript-typescript.md
│   ├── python.md
│   ├── go.md
│   └── rust.md
├── branching-and-commits.md
├── architectural-defaults/
│   └── api-style.md   ← worked example; other defaults deferred
└── README.md   ← this file
```

## The 11 universal floors

Every project's `docs/conventions.md` (or equivalent) addresses each:

1. Logging
2. Error handling
3. Secrets handling
4. Input validation
5. Auth and authorization
6. Observability beyond logs
7. Testing
8. Documentation in code
9. Dependency policy
10. Versioning
11. UX standards (UI projects only)

The first 10 apply to every project; the 11th applies only to UI projects (skip with rationale recorded in `.bootstrap/state.yaml` for non-UI projects).

## Depth tiers

Each floor template is provided at two depths in v1:

- **Express** — silent default. One specific recommendation per floor; applied without surfacing during bootstrap when the user picks Express engagement mode. Short (≤ 30 lines).
- **Standard** — surfaced default + 2-3 named alternatives + when-to-deviate. Used in Standard engagement mode where decisions are surfaced for user confirmation. Longer (30-80 lines).

A third **Deep** depth is deferred — it would carry full alternatives matrices + decision-record-style rationale + linkouts. The two depths above cover the common cases; Deep is for projects with unusual needs and is best authored after a pilot reveals which floors actually need that depth.

## Naming conventions

Per language. Project may override per-row with rationale recorded in the project's `docs/conventions.md`. The four named languages (JS/TS, Python, Go, Rust) cover the bulk of current pilot projects; additional languages are added when a pilot lands.

## Branching and commits

A single document covering branch naming, Conventional Commits, PR workflow, and protected branches. Applies regardless of language.

## Architectural defaults

Only **API style** is authored as a worked example in v1. Other architectural defaults (state management, async patterns, database access, frontend framework) are deferred until pilot friction surfaces which are worth authoring. The roadmap (Tranche 4 → Tranche 7 path) is the place those land.

## How a project consumes these templates

At bootstrap (per `build-doctrine/doctrine/08-project-bootstrapping.md` Stage 0):

1. The project's chosen engagement mode (Express / Standard / Deep) determines which depth files are read.
2. The project's language(s) determine which `naming/<lang>.md` is read.
3. The project's UI/non-UI distinction determines whether Floor 11 is included.
4. The project's `.bootstrap/state.yaml` records which floors were applied vs. deferred + which conventions were overridden.
5. A consolidated `docs/conventions.md` is generated for the project, mixing the templates' content with project-specific overrides.

## Relationship to schemas

The schemas at `build-doctrine/template-schemas/` validate the SHAPE of per-project canon artifacts. These templates provide the CONTENT defaults. A project's `conventions.md` should:

- Conform to `conventions.schema.yaml` (shape).
- Use these templates as content seeds (substance).

Schema-validation gates that fire automatically at commit time are deferred until adoption produces friction.

## Versioning

This collection of templates is versioned alongside the doctrine docs at `build-doctrine/CHANGELOG.md`. v0.3 (this Tranche 3 ship) is the first content release; v0.2 was schemas; v0.1 was the doctrine migration.
