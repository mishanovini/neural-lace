# Naming conventions — JavaScript / TypeScript

Defaults applied silently in Express; surfaced for confirmation in Standard.

| Category | Default | Notes |
|---|---|---|
| Files (general) | `kebab-case.ts` | Modules, utilities, helpers. |
| Component files | `PascalCase.tsx` | React + JSX components. |
| Test files | `<name>.test.ts` | Co-located with source. |
| Variables, functions | `camelCase` | Including methods. |
| Constants (compile-time) | `SCREAMING_SNAKE_CASE` | Module-level immutables. |
| Types, interfaces, classes | `PascalCase` | TypeScript type declarations. |
| Enum names | `PascalCase` | Enum type itself. |
| Enum values | `PascalCase` | Members of an enum. |
| Boolean variables | prefix with `is`, `has`, `can`, `should` | e.g., `isLoading`, `hasError`. |
| React hooks | prefix with `use`, `camelCase` | `useAuth`, `useFetch`. |
| Private members (class) | `_underscorePrefixed` | TypeScript `private` keyword preferred. |

## Acronyms
Preserve the conventional capitalization (`URL`, `URLPath`, `httpClient`, `XMLParser`). Avoid mixed forms like `urlPath` when the whole token would naturally be `URLPath`.

## React-specific
- Component file = component name (`Button.tsx` exports `Button`).
- Hooks file kebab-case: `use-auth.ts` exports `useAuth`. (Match your project's prevailing style; consistency over the specific choice.)

## Override
Project may override per-row with rationale recorded in this file. The pattern matters less than consistency across the codebase.
