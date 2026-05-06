# Floor 2 — Error handling — Standard

## Default
Typed errors with a small class hierarchy. Public response shape `{ error: { code, message, details? } }`. Retry only transient errors with exponential backoff + jitter, max 3 attempts, idempotent ops only. Log every error with stack frame + request_id + sanitized payload.

## Alternatives
- **Result types** (`Result<T, E>` / `Either`) — explicit at every call site. Idiomatic in Rust + FP-leaning teams; noisy elsewhere.
- **Sentinel-value errors** (Go-style `if err != nil`) — explicit return + check. Idiomatic in Go, awkward elsewhere.
- **Exception-only with no class hierarchy** — every error is `Exception`. Simple, loses dispatch on error class. Discouraged.

## When to deviate
- Regulated environments with mandated error-code taxonomies (PCI, HL7) override the public response shape.
- Performance-critical hot paths may skip stack capture; log error class + minimal context, accept lost stack info.

## Cross-references
- Floor 1 (logging) — error logs use the same structured format.
- Floor 5 (auth) — auth errors are a specific class with no internal-state leakage.
