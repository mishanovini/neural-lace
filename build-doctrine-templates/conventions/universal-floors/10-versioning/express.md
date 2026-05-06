# Floor 10 — Versioning — Express

Default: **Semantic Versioning** for libraries and public APIs (MAJOR.MINOR.PATCH); **calendar versioning** (YYYY.MM.DD) acceptable for end-user apps without API contracts. Breaking changes require a major bump + ADR + migration notes.

- SemVer: bump MAJOR for breaking changes; MINOR for additive; PATCH for bug fixes.
- Public vs internal API: explicitly tag internals (`_private`, `Internal`, `unstable`) so SemVer applies only to public surface.
- Breaking change: update CHANGELOG, write an ADR, document migration in the same release.
