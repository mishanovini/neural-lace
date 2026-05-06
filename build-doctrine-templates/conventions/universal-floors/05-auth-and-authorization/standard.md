# Floor 5 — Auth and authorization — Standard

## Default
Identity from a verified token (JWT or session cookie) issued by an external IdP or app's session layer. Authorization checked at route boundary with role/permission lookup. Audit-log every auth event.

## Alternatives
- **OAuth 2.0 / OIDC with external IdP** — most projects; pushes identity complexity to the provider.
- **Session-backed (server-stored)** — good for monoliths; logout invalidation is server-driven.
- **JWT-only (stateless)** — scales horizontally; logout is harder (token revocation requires a denylist).
- **mTLS** — service-to-service; not user-facing.

## When to deviate
- Regulated industries (healthcare, finance) require specific MFA + audit requirements; adopt the regulation's spec.
- Internal / behind-VPN services may relax MFA but never auth — least-privilege still applies.

## Cross-references
- Floor 3 (secrets) — auth keys / signing material covered there.
- Floor 6 (observability) — auth events feed the security-events dashboard.
