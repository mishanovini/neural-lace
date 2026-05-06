# Floor 9 — Dependency policy — Express

Default: **lock files committed**, **only well-maintained dependencies** (recent commits, real adoption, license compatibility), **automated security scanning** (Dependabot, Snyk, or equivalent), **patch + minor updates monthly**, major updates with explicit ADR.

- Lock file (`package-lock.json`, `Pipfile.lock`, `go.sum`, `Cargo.lock`) committed.
- New dependency: check last-commit date, weekly downloads, license, transitive dep count.
- Security scan: weekly automated; high-severity CVEs blocked from merging.
- Update cadence: patch + minor monthly via dependency-bot PR; major with ADR.
