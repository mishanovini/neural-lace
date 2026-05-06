# Floor 4 — Input validation — Standard

## Default
Validate at the trust boundary using a schema-validation library, in the API/route handler before business logic. Reject invalid input with 400 + named-field error.

## Alternatives
- **JSON Schema directly** (no language wrapper) — portable across services. Choose when validation rules are shared across multi-language services.
- **Manual `if`-checks per field** — fine for tiny APIs (≤ 5 fields); becomes unmaintainable past that.
- **Database-level constraints only** — fails late (after request mostly processed). Insufficient as the only layer; use as defense-in-depth.

## When to deviate
- Streaming / message-queue endpoints: validate per-message, but allow batch-level partial-failure (one bad message does not reject the whole batch).
- Webhook ingestion from untrusted sources: layer signature-verification BEFORE schema validation; signature failure short-circuits.

## Cross-references
- Floor 5 (auth) — auth checks happen before validation when both are required.
- Floor 2 (error handling) — validation errors are `UserError` class.
