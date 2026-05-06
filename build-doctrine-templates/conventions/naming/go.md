# Naming conventions — Go

Defaults follow the Go community style guide + `gofmt`.

| Category | Default | Notes |
|---|---|---|
| Files | `lowercase` (single word) or `lowercase_snake` | Match the package name; underscores when readability demands. |
| Test files | `<name>_test.go` | Required by `go test`. |
| Exported identifiers | `PascalCase` | Capitalized first letter = exported. |
| Unexported identifiers | `camelCase` | Lowercase first letter = package-private. |
| Acronyms | preserve case | `HTTPServer`, not `HttpServer`. `URL`, `JSON`, `ID`. |
| Receivers | short (1-3 chars), consistent across methods | `func (u *User)`, `func (db *DB)`. |
| Interfaces (single-method) | suffix with `-er` | `Reader`, `Writer`, `Closer`. |
| Constants | `PascalCase` for exported, `camelCase` for unexported | No `SCREAMING_SNAKE_CASE` (un-Go-like). |
| Errors | prefix with `Err` for sentinel values | `var ErrNotFound = ...`. |

## Package names
Lowercase, single word, descriptive. Avoid `util`, `common`, `helpers`, `lib` (too generic).

## Override
Project may override per-row with rationale; Go's idioms are tighter than most languages, deviating costs onboarding friction.
