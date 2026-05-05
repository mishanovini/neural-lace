# Build Doctrine Templates

The **content** layer of the three-layer Build Doctrine rendering. Default
content for the universal floors that every project consumes at bootstrap.

## Three-layer rendering convention

Every project that bootstraps against the doctrine consumes content in
three layers:

1. **Doctrine** (`build-doctrine/doctrine/`) — universal *shape*. The
   eight integrated-v1 docs define principles, roles, gates, etc. that
   apply to every project regardless of stack or domain.
2. **Templates** (this directory) — universal *content*. Default values
   for the universal floors (PRD shape, ADR shape, design-system seeds,
   engineering catalog conventions, observability defaults). Authored
   once; consumed by every project at bootstrap.
3. **Project canon** — per-project specialization. The bootstrap process
   takes the doctrine + templates and renders project-specific canon
   artifacts. Versioned in the project's own repo.

## What's inside (post-Tranche-0b)

Empty subdirectories scaffolded for the seven template categories:

- `prd/` — PRD template instances (Tranche 3 populates).
- `adr/` — ADR template instances.
- `spec/` — spec template instances.
- `design-system/` — design-system seeds (color tokens, type scale, etc.).
- `engineering-catalog/` — engineering-catalog defaults
  (naming conventions, branch conventions, etc.).
- `conventions/` — code conventions across languages.
- `observability/` — observability defaults (log shape, metric shape,
  trace boundaries).

`VERSION` tracks the templates' semantic version. `0.1.0` is the
pre-content seed; `1.0.0` will be cut when Tranche 3 ships the first
complete set of default content for all 11 universal floors.

## Cross-references

- `build-doctrine/doctrine/08-project-bootstrapping.md` — defines the
  universal floors this directory provides defaults for.
- `docs/build-doctrine-roadmap.md` — Tranche 3 (Phase 4b) is the seeding
  effort for this directory.
- `docs/decisions/025-build-doctrine-same-repo-placement.md` — decision
  record explaining why this directory lives in the same repo as the
  rest of the harness rather than a separate repo.
