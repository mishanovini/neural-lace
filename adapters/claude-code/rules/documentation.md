# Rules for documentation (all files)

When writing or modifying code:

1. Add doc comments (JSDoc/TSDoc) to exported functions and components explaining *what* and *why*
2. Add inline comments on complex business logic explaining *why*, not *what*
3. API routes must document: request shape, response shape, auth requirements, error codes
4. Use descriptive type names and add doc comments on complex types
5. Use `@deprecated` annotations instead of lingering TODO comments
6. When changing architecture, update project documentation (AGENTS.md, README) in the same PR
7. Update `.env.example` when adding new environment variables
