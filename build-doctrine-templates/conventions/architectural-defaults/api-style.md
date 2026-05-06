# Architectural default — API style

This is the worked example for the architectural-defaults category. Other defaults (state management, async patterns, database access, frontend framework) follow the same shape but are deferred until pilot friction informs which to author next.

## Default

**REST + JSON** for client-server APIs; **gRPC + Protocol Buffers** for service-to-service when low-latency / strong typing matters; **GraphQL** for client-driven aggregation across many resources.

For most projects starting fresh, **REST + JSON is the right default**:
- Lowest tooling overhead, broadest client support
- Intermediaries (load balancers, caches, observability tools) understand HTTP semantics natively
- Errors map cleanly to HTTP status codes
- Versioning by URL path (`/v1/`, `/v2/`) is well-understood

## REST conventions

| Aspect | Default |
|---|---|
| URL style | `/api/v1/<plural-resource>/<id>/<sub-action>?` |
| Methods | GET (read), POST (create), PUT/PATCH (update), DELETE (delete) |
| Status codes | 200 (OK), 201 (Created), 204 (No Content), 400 (User error), 401 (Unauth), 403 (Forbidden), 404 (Not Found), 409 (Conflict), 422 (Validation error), 500 (Server error), 503 (Unavailable) |
| Error body | `{ "error": { "code": "<machine-readable>", "message": "<user-readable>", "details": {...}? } }` |
| Pagination | Cursor-based: `?limit=N&cursor=<opaque>`. Avoid offset-pagination at scale (slow on large tables, unstable across writes). |
| Filtering | Query params: `?status=active&created_after=2025-01-01`. Avoid free-text query languages until needed. |
| Versioning | URL-path: `/api/v1/...`. Header-based versioning is acceptable but harder to debug. |
| Idempotency | Required for POST/PUT operations that retry. Use `Idempotency-Key` header. |
| Authentication | Bearer token in `Authorization` header. Cookie-based for browser clients with CSRF protection. |

## When to deviate

| Choice | When |
|---|---|
| **gRPC** | Internal service-to-service with high request volume; cross-language type safety matters; team can absorb the proto-file workflow. |
| **GraphQL** | Multi-resource aggregation per request; many client teams with different data needs; schema evolution can be managed via deprecation, not versioning. |
| **JSON-RPC** | Specialized RPC need where REST verbs feel forced. Rare. |
| **WebSocket / SSE** | Server-push real-time data. Layer on top of REST for the rest of the API. |

## Cross-references

- Floor 4 (input validation) — request validation happens in the route handler, not in business logic.
- Floor 5 (auth) — auth happens before validation when both required.
- Floor 6 (observability) — every endpoint emits the four golden signals.
- Floor 2 (error handling) — error response shape is the public contract.

## Worked example

A `POST /api/v1/invoices` endpoint:

- Auth: `Authorization: Bearer <jwt>`. Reject 401 if invalid.
- Body: validated against `invoice.schema.yaml` (Floor 4); reject 422 with field-level error.
- Business logic: persist + emit `invoice.created` metric (Floor 6).
- Success: 201 + `{ "id": "...", "createdAt": "..." }`.
- Failure: 5xx + `{ "error": { "code": "internal_error", "message": "..." } }` + log with stack + request_id (Floor 1, Floor 2).
- Idempotency: `Idempotency-Key: <client-uuid>` header — repeat requests with same key return the same response, no double-creation.

## Future architectural defaults (deferred)

- **State management** (Redux / Zustand / Jotai for frontends; Redis / DB for backends) — pilot friction will inform.
- **Async patterns** (queues, schedulers, durable workflows) — varies enough by use-case that defaults are dangerous; spec per project.
- **Database access** (ORM vs query builder vs raw SQL) — language-specific; deferred.
- **Frontend framework** (React / Vue / Svelte / etc.) — taste-driven; deferred.
