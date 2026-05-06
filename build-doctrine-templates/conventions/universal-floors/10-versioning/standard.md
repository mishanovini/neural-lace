# Floor 10 — Versioning — Standard

## Default
Semantic Versioning for libraries and public APIs. CalVer (YYYY.MM.DD) acceptable for end-user apps without API contracts. Breaking changes require major bump + ADR + migration notes in CHANGELOG. Public/internal distinction explicit (named conventions per language).

## Alternatives
- **Strict SemVer with automated CHANGELOG** (Conventional Commits + `semantic-release`) — automatic version bumps from commit message types. Choose for libraries with frequent releases.
- **CalVer everywhere** (YYYY.MM.DD or YY.MM) — predictable, no breaking-change distinction; appropriate for end-user apps where users see release dates more than version numbers.
- **0.x perpetual** — indicate "no API stability guarantees" until 1.0. Honest for early projects; eventually you have to pick.
- **Single-version monorepo** vs. **per-package versions** — both valid; pick once and stick to it.

## When to deviate
- Internal services with no external consumers: skip versioning UI; use git SHA + deploy timestamp for ops.
- Hard real-time / safety-critical systems may require traceability beyond SemVer; combine SemVer + immutable build hashes + digital signatures.

## Cross-references
- Floor 8 (documentation) — version-bump triggers a CHANGELOG update + possibly an ADR.
- Floor 9 (dependency policy) — your project's versioning informs how downstream consumers pin you.
