---
title: Refine docs/{decisions,reviews,sessions} gitignore to allow NL-self artifacts
date: 2026-05-03
type: process
status: implemented
auto_applied: true
originating_context: D5 of the D1-D5 educational re-do session 2026-05-03; closes HARNESS-GAP-10 sub-gap H
decision_needed: n/a — auto-applied
predicted_downstream:
  - .gitignore
  - All future force-add ceremonies for legitimate NL-self decisions/reviews/sessions
  - HARNESS-GAP-10 sub-gap H (now closed)
---

# Refine docs/{decisions,reviews,sessions} gitignore to allow NL-self artifacts

## What was discovered

The original gitignore for `docs/decisions/`, `docs/reviews/`, `docs/sessions/` was a blunt directory-level exclude. It caught both legitimate NL-self artifacts (which follow numbered `NNN-*.md` or dated `YYYY-MM-DD-*.md` conventions) AND downstream-project artifacts (which don't follow these conventions). Result: every legitimate NL-self commit required `git add -f`. Downstream artifact protection was actually maintained, but at the cost of friction on every legitimate use.

The user surfaced (D5 of the 2026-05-03 D1-D5 dialogue): "Why are decisions and reviews even gitignored at all? Is there sensitive data in there?" Answer: no sensitive data; the gitignore was preventing accidentally committing downstream-project artifacts. But the implementation was a blunt instrument.

## Why it matters

`git add -f` ceremony is forgettable; legitimate NL-self artifacts get missed when force-add isn't used. Plus the ceremony itself signals that something is wrong with the rule design. Multiple sessions' worth of commits this week hit this friction.

## Options considered

- **A — Negation pattern in `.gitignore` allowing the convention.** Selected.
- **B — Move NL-self artifacts to a separate path** (e.g., `docs/nl-decisions/`). Rejected — rename churn for 12+ existing decision records.
- **C — Stop gitignoring entirely; rely on harness-hygiene-scan.** Rejected — implementation cost outweighs benefit.

## Recommendation

A. Use file-level exclude patterns (`docs/decisions/*` not `docs/decisions/`) so negation can re-include matching files. Per git's gitignore quirk, parent-directory exclusion blocks negation; file-level patterns avoid this.

## Decision

A applied. `.gitignore` now reads:

```
docs/decisions/*
!docs/decisions/[0-9][0-9][0-9]-*.md
docs/reviews/*
!docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
docs/sessions/*
!docs/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
```

## Implementation log

- `.gitignore` updated with file-level exclude + negation pattern.
- Verified: `git add docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` works without `-f`.
- Verified: `git status` shows previously-invisible NL-self review file (`2026-04-27-agent-teams-conflict-analysis.md`) as untracked-and-stageable.
- HARNESS-GAP-10 sub-gap H is closed structurally — no follow-up plan needed for this specific gap.
- Noted: any NL-self artifact that DOESN'T follow the numbered/dated convention is still gitignored. Force-add still works as the fallback for unusual cases.
