# Floor 4 — Input validation — Express

Default: **validate at the trust boundary**, with a schema-validation library, in the API/route handler before any business logic. Reject invalid input with a 400 response naming the failing field.

- Library: language-idiomatic schema validator (`zod`/`io-ts` for TS, `pydantic` for Python, `validator.v10` for Go, `serde` + `validator` for Rust).
- Where: at the API/route layer; never in business logic.
- Errors: surface the failing field name + reason, not the full schema.
