# Floor 3 — Secrets handling — Express

Default: **secrets in environment variables**, sourced from a secrets manager at deploy time, never committed to source. Pre-commit hook scans for accidentally-committed credentials.

- Storage: cloud secrets manager (AWS Secrets Manager / GCP Secret Manager / Vault).
- Injection: env vars at process start; `.env.local` for local dev (gitignored).
- Rotation: 90 days for high-sensitivity (DB passwords, signing keys); 1 year for low.
- Scanning: `harness-hygiene-scan.sh` and `pre-push-scan.sh` block known patterns.
- Accidental commit response: revoke immediately + remove from history + audit downstream.
