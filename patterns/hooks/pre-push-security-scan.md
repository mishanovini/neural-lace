# Pattern: Pre-Push Security Scan

## When This Pattern Applies

Before any push to a remote repository, scan the diff for credentials, secrets, and sensitive data patterns.

## What to Scan

### Content Patterns (in added lines only)

1. **API tokens**: Platform-specific patterns (cloud providers, SaaS services, AI providers)
2. **Private keys**: PEM, RSA, DSA, EC, OpenSSH, PGP private key headers
3. **JWT tokens**: Base64-encoded JSON Web Tokens
4. **Connection strings**: Database URLs with embedded credentials
5. **Service role keys**: Platform-specific service/admin keys

### Filename Patterns (always blocked)

1. Environment files (`.env`, `.env.local`, `.env.production`, etc.)
2. Credential files (`credentials.json`, `secrets.yaml`, etc.)
3. SSH keys (`id_rsa`, `id_ed25519`, `.pem`)
4. Certificate files (`.p12`, `.pfx`)
5. Auth state files

### Pattern Sources (layered)

1. **Built-in patterns**: Hardcoded in the scanner
2. **Personal patterns**: User-specific patterns (never committed)
3. **Team patterns**: Shared via private repo symlinks

## Behavior

- Scan only added lines (`+` prefix in diff) to reduce false positives
- Show the first N characters of matched lines (not full lines — they may contain the secret)
- Block the push on any match
- Log the blocked attempt for telemetry
- The scanner operates at the git level, independent of the AI tool — it protects all pushes, not just AI-initiated ones

## Defense in Depth

This is one layer of credential protection. It should be paired with:
- File edit blocking (prevent writing to credential files)
- Pre-commit review (catch secrets before they're committed)
- Risk engine classification (flag high-sensitivity actions)
