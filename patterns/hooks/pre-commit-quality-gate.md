# Pattern: Pre-Commit Quality Gate

## When This Pattern Applies

Before any commit is finalized, the harness should run quality checks to prevent broken code from entering the repository.

## What to Check

1. **Test suite**: Run the project's test suite. Block commit if tests fail.
2. **Build verification**: Run the project's build command. Block commit if build fails.
3. **API consumer audit**: If the commit touches API routes, verify that all consumers of changed routes are also staged. Block if consumers are unstaged (indicates incomplete change).
4. **Code review**: Spawn a review agent to check the diff for quality, security, and integration issues.

## Behavior

- All checks run sequentially (tests → build → audit → review)
- First failure blocks the commit
- Output includes the last few lines of failing command for quick diagnosis
- Skip gracefully if a check doesn't apply (e.g., no test suite, no API audit script)

## Risk Classification

This is not a permission gate — it's a quality gate. The commit action itself is low risk (reversible, local), but the gate ensures what's being committed meets quality standards.
