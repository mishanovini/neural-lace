---
paths: **/*.ts,**/*.tsx
---

# TypeScript Standards

- `strict: true` in all tsconfig files
- `import type` for type-only imports
- No `any` without explicit justification comment
- Explicit return types on exported functions
- No `@ts-ignore` or `as any` — fix the type error
- No `console.log` in committed code — use proper error reporting or remove
- No `// eslint-disable` without justification comment
