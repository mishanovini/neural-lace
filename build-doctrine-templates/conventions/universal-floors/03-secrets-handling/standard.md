# Floor 3 — Secrets handling — Standard

## Default
Secrets in env vars sourced from a secrets manager at deploy time. Never committed. Pre-commit + pre-push scanning for known credential patterns. Local dev uses `.env.local` (gitignored). Rotation cadence: 90d high-sensitivity, 1y low. On accidental commit: revoke immediately, remove from history, audit downstream.

## Alternatives
- **Encrypted at rest in repo** (e.g., `git-crypt`, `sops`) — secrets travel with code, decrypted at deploy. Choose when ops team has firm key-management discipline.
- **Service-mesh injection** (Vault Agent, AWS Secrets Manager extension) — secrets fetched at runtime, never in env. Choose for high-sensitivity; adds startup latency.
- **Hard-coded encrypted blob with code-side decryption** — antipattern; discouraged.

## When to deviate
- HSM-backed secrets (FIPS 140-2 / 3 environments) — defaults insufficient; adopt the HSM provider's pattern.
- Air-gapped deploys (no internet) — secrets manager unavailable; offline encrypted storage with manual key custody.

## Cross-references
- Harness implementation: `~/.claude/hooks/harness-hygiene-scan.sh` + `~/.claude/hooks/pre-push-scan.sh` + 18 built-in patterns.
- Floor 5 (auth) — credentials FOR services covered there; secrets ABOUT services covered here.
