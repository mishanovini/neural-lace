# Naming conventions — Rust

Defaults follow Rust API Guidelines + `rustfmt`.

| Category | Default | Notes |
|---|---|---|
| Files | `snake_case.rs` | Module files. |
| Test files | `<name>.rs` (in `tests/` dir) | Integration tests. Unit tests are `mod tests` inside the source file. |
| Functions, variables | `snake_case` | Per Rust convention. |
| Types, traits, enums | `PascalCase` | `User`, `Iterator`, `Result`. |
| Enum variants | `PascalCase` | `Some`, `None`, `Ok`, `Err`. |
| Constants, statics | `SCREAMING_SNAKE_CASE` | `const MAX_BUFFER: usize = 4096;`. |
| Modules | `snake_case` | `mod user_service`. |
| Lifetimes | `'a`, `'b`, ... or descriptive | `'static`, `'input`. Short by default. |
| Macros | `snake_case!` | Trailing `!` is part of invocation, not the name. |

## Acronyms
Treat as words in non-`SCREAMING` contexts: `HttpClient` (not `HTTPClient`); `parse_url` (not `parse_URL`).

## Crate names
`kebab-case` in `Cargo.toml` (the index name); `snake_case` when imported (Rust converts automatically).

## Idioms beyond naming
- Prefer `Result<T, E>` over panics in library code.
- `clippy::pedantic` is too noisy by default; start with `clippy::all` and opt in to specific pedantic lints.

## Override
Project may override per-row with rationale; Rust's idioms are tight, deviating costs `rustfmt` friction.
