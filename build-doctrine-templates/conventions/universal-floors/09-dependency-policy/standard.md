# Floor 9 — Dependency policy — Standard

## Default
Lock files committed. New deps vetted for maintenance + adoption + license + transitive count. Automated security scanning weekly; high-severity CVEs block merge. Patch + minor updates monthly via dependency-bot PR; major updates require ADR.

## Alternatives
- **Strict allowlist** (every dep approved by a human) — high overhead; appropriate in regulated industries where supply-chain attestation is required.
- **Vendored dependencies** (sources committed in-repo) — full control + no external trust; high maintenance cost.
- **No lockfile** — never. This is an antipattern; lockfiles prevent supply-chain drift and "works on my machine."
- **Auto-merge dependency-bot PRs** without review — works for tiny low-risk projects; risky once dependencies have any production reach.

## When to deviate
- Compliance regimes (PCI, HITRUST) often mandate explicit dep-vetting workflows. Adopt the regime's process.
- Air-gapped / offline environments: vendor everything; no live updates.
- Heavy ML/AI dependencies (PyTorch, TensorFlow) often have larger transitive graphs and slower update cycles; treat them as long-lived rather than monthly.

## Cross-references
- Floor 3 (secrets) — supply-chain attacks often deliver credentials-stealing payloads; the two floors compose.
- Floor 7 (testing) — every dep update should run the test suite before merge.
