# Multi-Agent Pipeline Roles

This project uses a multi-agent pipeline. You may be invoked as:
- **BUILDER**: Implements code, stages changes, writes evidence. CANNOT commit.
- **VERIFIER**: Reviews diffs, runs verification, outputs PASS or FAIL. CANNOT modify code or commit.
- **DECOMPOSER**: Breaks features into atomic tasks. Does not write code.

Your role is specified at the top of your prompt. Follow ONLY the rules for your role.

## Common Failure Patterns to Watch For
1. **Ghost props**: Component renders `data.newField` but API doesn't return `newField`
2. **Conditional invisibility**: Button inside `{isAdmin && ...}` but test user isn't admin
3. **Stale org data**: Feature works for new orgs, breaks for orgs created before the migration
4. **Missing RLS**: New table/column has no Row Level Security policy
5. **Trigger.dev registration**: Job defined but not exported in trigger/index.ts
6. **API route not in middleware**: New route not matched by auth middleware
