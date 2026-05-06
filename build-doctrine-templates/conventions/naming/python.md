# Naming conventions — Python

Defaults follow PEP 8 with one explicit choice on test-file pattern.

| Category | Default | Notes |
|---|---|---|
| Files | `snake_case.py` | All modules. |
| Test files | `test_<name>.py` | Pytest-discovered convention; `<name>_test.py` is acceptable but pick one and stick. |
| Functions, variables, methods | `snake_case` | Per PEP 8. |
| Classes | `PascalCase` | Per PEP 8. |
| Constants (module-level) | `SCREAMING_SNAKE_CASE` | Per PEP 8. |
| Modules, packages | `lowercase_short` | Single word preferred; underscores when needed for readability. |
| Private members | prefix with `_` | Single leading underscore = "internal use." |
| Name-mangled members | prefix with `__` | Class-private; rare. |
| Type aliases | `PascalCase` | `UserId = NewType('UserId', int)`. |

## Acronyms
Treat acronyms as words: `Url`, `HtmlParser`, `XmlElement`. (Differs from JS/TS convention.)

## Import order (per PEP 8)
1. Standard library
2. Third-party
3. Local application
Each group separated by a blank line; alphabetized within group.

## Override
Project may override per-row with rationale recorded in this file.
