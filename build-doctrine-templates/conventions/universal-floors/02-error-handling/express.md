# Floor 2 — Error handling — Express

Default: **typed errors with a class hierarchy**. Public response `{ error: { code, message, details? } }`. Retry transient errors only (network timeout, downstream 5xx). Log every error with stack + request_id.

- `UserError` (4xx response, not logged as error)
- `SystemError` (5xx response, logged)
- `BugError` (5xx response, alert)
- Retry: exponential backoff + jitter, max 3 attempts, idempotent ops only.
- Log: error type, stack frame, request_id, sanitized payload.
