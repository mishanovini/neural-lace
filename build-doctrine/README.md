# Build Doctrine

The doctrine layer for the Neural Lace harness — eight integrated documents
that codify principles, roles, work-sizing, gates, implementation process,
propagation, project bootstrapping, and the autonomy ladder.

## Purpose

The doctrine is the **shape** layer of the Build Doctrine architecture:
it defines the universal principles and processes that apply to every
project the harness operates on. It is content-stable across projects —
when a new project bootstraps, it consumes the doctrine as-is, then
specializes via the per-project canon (see Tranche 4 of the roadmap).

Together with `build-doctrine-templates/` (sibling directory — the
**content** layer with default values for universal floors) and the
per-project canon artifacts produced at bootstrap, the doctrine forms
a three-layer rendering: doctrine (universal shape) + templates
(default content) + canon (per-project specialization).

## What's inside

The eight integrated-v1 doctrine docs in `doctrine/`:

- `01-principles.md` — foundational principles
- `02-roles.md` — role taxonomy
- `03-work-sizing.md` — sizing work for the harness
- `04-gates.md` — the gate stack
- `05-implementation-process.md` — the build process
- `06-propagation.md` — how changes propagate
- `08-project-bootstrapping.md` — bootstrap process for new projects
- `09-autonomy-ladder.md` — the rungs (R0-R5)

`07-knowledge-integration.md` is deferred to Tranche 5 — it depends on
findings from the canonical pilot (Tranche 4).

## Cross-references

- `docs/build-doctrine-roadmap.md` — the multi-tranche arc tracker.
- `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md` —
  the original Build Doctrine plan in a sibling repo (historical spec).
- `~/claude-projects/Build Doctrine/outputs/glossary.md` — the
  authoritative acronym source consulted by the
  `definition-on-first-use-gate.sh`.
- `docs/decisions/025-build-doctrine-same-repo-placement.md` — the
  same-repo placement decision (templates live as a sibling directory,
  not in a separate repo).

## How this directory grows

- Tranche 0b (this migration) lands the eight integrated-v1 docs as-is.
- Tranche 5 lands `07-knowledge-integration.md` after the canonical
  pilot in Tranche 4 produces the friction findings the section needs
  to be authored against.
- Subsequent revisions follow the cadence defined in
  `07-knowledge-integration.md` once that doc lands.

The `CHANGELOG.md` tracks every material change; the doctrine docs are
versioned as a set, not individually.
