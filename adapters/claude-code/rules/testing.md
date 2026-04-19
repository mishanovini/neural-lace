# Testing & Verification Standards

## Test Discipline
- Run existing tests before declaring work complete
- Write tests for new features and bug fixes (reproduce bug BEFORE fixing)
- Failing tests are blockers — fix or explain
- Never delete or skip tests to make a build pass
- Test edge cases: empty states, error states, boundary values

## E2E Testing (System Boundary Rule)

**After any commit touching a system boundary, run E2E tests against live deployment.** A successful build is NOT validation.

System boundaries: database queries, external API calls, webhook handlers, environment variables, API route handlers.

Skip E2E for: type-only changes, docs, UI-only (unless consuming a changed API), pure refactors.

**Test design:** tool coverage (each endpoint individually) AND journey tests (multi-step flows where output feeds the next input).

**Process:** commit → push → deploy → E2E tests → report. Each project defines its E2E command in its CLAUDE.md.

## Pre-Commit Review (Mandatory)

Before every commit, spawn code-reviewer agent(s) checking:
1. **Auth & security** — proper guards, no cross-tenant access, no exposed secrets
2. **Error handling** — explicit on every async path, user-facing errors are actionable
3. **Integration** — changed files work with consumers (props, API contracts, DB schemas)
4. **Edge cases** — null/undefined, empty states, malformed input, race conditions

Fix issues and re-review before committing.

## UX Validation After Substantial Builds (Mandatory)

Run **all three** UX/content agents after new features, page redesigns, or workflow changes. All three are audience-aware — they read the project's target user from `.claude/audience.md` (or `CLAUDE.md`, or infer it).

1. **UX End-User Tester** (`~/.claude/agents/ux-end-user-tester.md`) — generic non-technical user walkthrough
2. **Domain Expert Tester** (`~/.claude/agents/domain-expert-tester.md`) — becomes the project's target persona (from `.claude/audience.md`) and tests workflows from that perspective
3. **Audience Content Reviewer** (`~/.claude/agents/audience-content-reviewer.md`) — reads all user-facing text and flags wrong-audience language, jargon, empty/placeholder content

**Define your project's audience** at `.claude/audience.md` with a description of the persona, their vocabulary, what they care about, and what confuses them. Without this file, the agents will infer from `CLAUDE.md` or the code.

All P0 (blocking) and P1 (confusing/frustrating) findings must be fixed. P2 (polish) can be deferred.

**Persist results immediately.** When a testing agent completes, write its findings to `docs/reviews/YYYY-MM-DD-<slug>.md` BEFORE doing anything else — before analysis, before fixes, before responding to the user. If the session crashes after agents complete but before results are saved, all findings are lost. Persist first, analyze second. After fixing findings, update the review file with fix status (mark as fixed with commit SHA, don't delete findings).

**Audit findings must list every affected file.** When an audit produces a finding like "8 forms missing RequiredLabel" or "5 server pages missing try/catch", the finding must list every file by path in the review document. Do not write generic findings like "many forms need X" — that's not actionable and leads to partial fixes.

**Fix tasks for sweep findings must track per-file.** When a finding lists 8 files, the corresponding fix task is 8 sub-items, not 1. Mark each sub-item complete only after that specific file is verified. Otherwise the task gets marked done after fixing 5 of 8 files and the remaining 3 silently slip. This has happened: an "S3 — wire RequiredLabel into 14 forms" task was marked done after 11 forms; the other 3 were only caught by a sweep agent days later. The fix is mechanical: split the task before starting, never let a sweep finding be a single checkbox.

**Review-finding ↔ fix-commit convention (Rule 4).** When a commit addresses one or more review findings, both sides of the link must be updated in the SAME commit:

- **Commit message** must reference each addressed finding by its ID, using the format `<TAG>-NNN` (e.g., `UX-E04`, `CONTENT-042`, `AUDIT-7`). The first token maps to the review category (UX, CONTENT, AUDIT, etc.); the number maps to the finding row in the review file.
- **Review file** (`docs/reviews/YYYY-MM-DD-*.md`) must be updated in the same commit to mark the addressed finding with `Fixed: <SHA>` on its row. Do not delete findings — the historical record is load-bearing.
- Enforced by `adapters/claude-code/hooks/review-finding-fix-gate.sh`: if the commit message references a finding ID that exists in any review file, but the corresponding review file isn't staged in the same commit, the commit is blocked.
- The enforcement is conservative — only finding IDs that actually exist in review files trigger the gate. Unrelated `<TAG>-NNN` patterns in commit messages (PR numbers, ticket references, etc.) don't false-positive.

## Link Validation (Mandatory Before Deploy)

Run `npm run test:links` after any commit that adds or modifies `href` values. This catches dead internal links (like `/insights` when the page is at `/ai-insights`).

For live validation against a running server: `npm run test:links:live`

## Consistency Audit (Mandatory Before Deploy)

Run `npm run audit:consistency` before every significant commit. This scans the codebase for pattern violations:
- Raw string formatting that should use shared helpers
- Unapproved color classes (orange, yellow) not in the project palette
- HTML entity arrows (`&larr;`) that should use icon libraries
- `<h1>` in content pages (should be `<h2>`)
- `text-xl` on page titles (should be `text-2xl`)
- Outline-only buttons (violates "filled button" rule for dark mode visibility)
- Missing `loading.tsx` for server-component pages with async fetches
- Manual fallback chains that should use dedicated helpers

The script is at `~/.claude/scripts/audit-consistency.ts` — copy it into your project's `scripts/` directory and add `"audit:consistency": "npx tsx scripts/audit-consistency.ts"` to package.json. Configure via optional `.audit-consistency.json` in project root.

P0 and P1 violations block the audit (exit code 1). P2 is informational.

## Interactive Playwright Tests (After UI Changes)

Run `npm run test:e2e:automation` after changes to the Automation page or any component it uses. These tests verify interactive behavior: clicking buttons opens modals, forms pre-populate, navigation links switch panels, follow-up editors render controls.

## Deployment Validation

**A PR is not done until it deploys successfully.**
1. Wait for ALL status checks (CI + deploy)
2. If deploy fails, fix it — it's your bug
3. Verify the deployed feature works
4. Never dismiss a failing check as "unrelated"

Sequence: commit → push → CI passes → deploy succeeds → feature verified → done.

## Purpose Validation

Before writing and before marking complete, ask: "Does this achieve its stated purpose under real conditions?"
1. State the purpose in one sentence (the outcome, not the mechanism)
2. Validate against real inputs (what does the caller actually provide at runtime?)
