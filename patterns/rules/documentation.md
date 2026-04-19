# Documentation Standards

## What This Pattern Covers

How code should be documented. These are universal principles — specific annotation syntax (JSDoc, docstrings, rustdoc) varies by language, but the principles apply everywhere.

## Principles

### Document the Why, Not the What

- **Exported functions and components** get doc comments explaining *what* they do and *why* they exist
- **Complex business logic** gets inline comments explaining *why* — the code shows *what*
- **Simple code** needs no comments — if the code is clear, a comment is noise

### APIs Are Contracts

- **API routes** document: request shape, response shape, auth requirements, error codes
- **Public interfaces** include usage examples when the correct usage isn't obvious
- **Breaking changes** are called out in PR descriptions and changelogs

### Types Are Documentation

- Use **descriptive names** for types and interfaces — `CustomerInvoice` not `Data1`
- Add doc comments on complex types explaining their purpose and constraints
- Use deprecation annotations (`@deprecated`, `#[deprecated]`) instead of lingering TODO comments

### Schema Comments Propagate

- Database schema comments propagate to generated types in many ORMs (Prisma `///`, TypeORM `@Column({ comment })`) — use them
- These comments become the documentation for downstream consumers automatically

### Keep Docs Current

- When changing architecture, **update project documentation in the same PR**
- Stale docs are worse than no docs — they mislead
- Update `.env.example` when adding new environment variables
