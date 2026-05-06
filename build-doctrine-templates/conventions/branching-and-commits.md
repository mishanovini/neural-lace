# Branching and commit conventions

## Branch naming

Pattern: `<type>/<short-description>` where `<type>` is one of:

| Type | When to use |
|---|---|
| `feat/` | New feature work |
| `fix/` | Bug fix |
| `hotfix/` | Urgent production fix |
| `chore/` | Tooling, dependencies, non-code maintenance |
| `docs/` | Documentation-only changes |
| `refactor/` | Code restructure with no behavior change |
| `spike/` | Throwaway exploration; expected to be discarded or rewritten |
| `release/` | Release preparation branches (when using release branches) |

Description: kebab-case, descriptive, ≤ 60 chars. Prefer the user-facing outcome over the internal mechanism: `feat/duplicate-invoice-warning` over `feat/add-check-in-submit`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>?): <short description>

<optional body>

<optional footer(s)>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `build`, `ci`, `style`, `revert`. Project-specific extensions allowed (e.g., `plan`, `close` for harness-dev work).

Scope: optional area (`auth`, `ui`, `api`, etc.). Skip if the change is repo-wide or trivial.

Description: imperative mood, lowercase, no period (`add unit tests for X`, not `Added unit tests for X.`).

Body: explain WHY (not WHAT — the diff says what). Wrap at 72 cols.

Footers:
- `BREAKING CHANGE: <description>` — surfaces in CHANGELOG and forces major version bump.
- `Refs: #123, #456` — link issues.
- `Co-Authored-By: Name <email>` — pair-programming attribution.

## Examples

```
feat(auth): add MFA enrollment flow

Required by NFR-7 in the PRD. Uses TOTP per RFC 6238; recovery codes
generated at enrollment time, displayed once, never re-shown.

Refs: #142
```

```
fix: prevent duplicate invoice submission on slow networks

Submit button now disables on first click; re-enables only on response
or 30s timeout. Closes the resubmission bug surfaced in onboarding.

Fixes: #211
```

```
chore!: drop Node 18 support

BREAKING CHANGE: minimum Node version is now 20. The build system uses
features (top-level await in CJS) not present in Node 18.
```

## Pull request workflow

- Branch from default branch (usually `main` or `master`).
- Open PR when ready for review (avoid "draft" indefinitely; small PRs > big PRs).
- PR title follows the same Conventional Commits format as commits.
- Squash-merge by default (clean history); merge-commit if preserving the branch's audit trail matters more than linearity.

## Protected branches

`main` (or `master`) and any active `release/*` branches must be protected:
- Require status checks (CI must pass).
- Require ≥ 1 review (≥ 2 for high-sensitivity repos).
- No force-push.
- No direct commits (PR-only).
