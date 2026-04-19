# Pattern: Builder-Verifier Pipeline

## When This Pattern Applies

When a task requires both implementation and independent verification. The key constraint: the entity that builds should never be the entity that verifies.

## Roles

### Builder
- Implements code changes
- Stages files for commit
- Writes evidence describing what was done
- CANNOT commit (commits happen only after verification)
- CANNOT mark tasks as complete

### Verifier
- Reviews the builder's diff against acceptance criteria
- Runs independent checks (typecheck, grep for expected patterns, API calls)
- Outputs a structured verdict: PASS, FAIL, or INCOMPLETE
- CANNOT modify application code
- CAN mark tasks as complete (only on PASS verdict)
- CAN write evidence blocks

### Decomposer (optional)
- Breaks features into atomic, independently verifiable tasks
- Does not write application code
- Output: ordered task list with acceptance criteria per task

## Workflow

1. Decomposer breaks the work into tasks (if needed)
2. Builder implements task N
3. Builder writes evidence (what was done, files modified, what to check)
4. Verifier receives evidence + checks repo state independently
5. If PASS: verifier marks task complete, moves to task N+1
6. If FAIL/INCOMPLETE: verifier explains gaps, builder addresses them, re-submit

## Why Separation Matters

Self-reported completion fails in practice. It's too easy to believe your own work is done. The verifier provides an independent check that catches:
- Tasks marked complete that aren't actually implemented
- Implementation that doesn't match acceptance criteria
- Side effects or regressions the builder didn't notice
- Missing edge case handling

## Common Failure Patterns

1. **Ghost props**: Component renders a field that the API doesn't return
2. **Conditional invisibility**: Feature inside a condition that's never true for test users
3. **Stale data**: Works for new records, breaks for records created before a migration
4. **Missing security policies**: New database table without access control
5. **Incomplete registration**: Job or route defined but not wired into the system
6. **API route without auth**: New endpoint not included in authentication middleware
