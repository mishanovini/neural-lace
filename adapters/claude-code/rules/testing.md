# Testing & Verification Standards

## Bug Persistence — Every Identified Bug Goes to Durable Storage Within the Same Session (MANDATORY)

**Any bug, gap, or functional deficiency you observe during a session MUST be persisted to durable storage before the session ends.** Discovery without persistence is equivalent to not finding it.

**What counts as "identifying a bug":**
- A test that fails or produces unexpected output
- A tool return or log that surfaces an error
- An observation that the code / data / UI doesn't behave as expected
- A gap noticed while investigating something else ("wait, also X is broken")
- A limitation flagged by a user in the conversation
- A vulnerability or inconsistency you notice while reading code for another purpose
- Anything where a future session would benefit from knowing what you now know

**Where it goes (pick one, immediately):**
- **`docs/backlog.md`** — if the bug is actionable and clearly scoped for future work. One bullet per bug, under the appropriate P0/P1/P2 section. Include enough detail that next-session you could start on it cold.
- **`docs/reviews/YYYY-MM-DD-<slug>.md`** — if the bug is one of a cluster found during a testing / investigation / audit pass. Entire set goes in one review doc with evidence.
- **An existing plan's Evidence Log or Decisions section** — if the bug was discovered *while working on* that plan and is directly related.

**The trigger phrases that mean "write it down NOW":**
"we should also...", "this is missing", "we don't have X yet", "ideally we'd...", "I'll document this later", "as a follow-up", "for next session", "this is out of scope for this PR", "let me flag this", "turns out X doesn't work".

Every one of those phrases is your brain trying to move on before persisting. **Stop. Write the backlog entry in the same response. Then continue.** This is the same principle as `planning.md`'s "Identifying a gap = writing a backlog entry" rule, but it applies to BUGS surfaced during execution, not just gaps noticed during planning.

**The bar:** if the bug isn't in `docs/backlog.md` or `docs/reviews/` by the end of the session, it's lost. "It's in the PR body" doesn't count — PR bodies are not searchable by future sessions. "I mentioned it in chat" doesn't count — the chat is ephemeral.

**End-of-session check:** before closing out, scan the session for any of the trigger phrases above. For each one, verify the corresponding bug is persisted. If not, persist it now.

**Why this is strict:** the 2026-04-20 session discovered ~25 distinct issues across state machine integration, harness gaps, and NEPQ prompt content. Without this rule, most of them were at risk of being lost when the session ended because they lived only in PR bodies + conversation chat. The consolidated gap list (`docs/reviews/2026-04-20-consolidated-gap-list.md`) had to be reconstructed retroactively. Going forward, every bug is persisted as it's found.

## Test Discipline
- Run existing tests before declaring work complete
- Write tests for new features and bug fixes (reproduce bug BEFORE fixing)
- Failing tests are blockers — fix or explain
- Never delete or skip tests to make a build pass
- Test edge cases: empty states, error states, boundary values

## No Skipped Tests — Make It Testable Or Surface The Blocker (MANDATORY)

**Never use `test.skip()`, `it.skip()`, `xtest()`, `.only()` that excludes others, or `expect.soft()` to dodge an assertion.** "Skip when the org has no reps" is not a valid test — it's a test that doesn't test. If you find yourself unable to exercise a code path in a test, the correct response is to make the code path reachable:

- **Seed the data inline.** Create a rep, a contact, a pricing entry, etc. inside the test's setup, use it, clean it up in a `finally` block. Use the real project APIs — this is more faithful than mocking anyway.
- **Use API endpoints to set up state.** `page.request.post('/api/reps', ...)` + `page.request.get('/api/auth/session')` to get org_id. This is the canonical pattern for workflow tests that need prerequisite data.
- **Add a fixture or helper** if the same setup recurs across tests (e.g., `tests/fixtures/seed-rep.ts`).
- **If the code path is genuinely unreachable** (e.g., depends on a third-party service that can't be touched from tests, or on a manual action), do NOT skip. Instead: document the blocker in the test body as a `test.fail({ message: '...' })` with a specific explanation, or surface it to the user explicitly in the session summary so we can come up with a solution together.

**The only legitimate skip** is a test that is temporarily broken due to a known upstream bug AND has an issue number to fix it. In that case the skip message MUST reference the issue (`test.skip('Blocked by #NNN — <short reason>')`). Anything else is vaporware testing.

**Enforcement:** pre-commit hook `no-test-skip-gate.sh` scans staged `*.spec.ts` / `*.test.ts` files for new `test.skip(`, `it.skip(`, `.skip(` on describe blocks, and blocks the commit unless the skip line references an issue number (`#NNN` or `github.com/.*/issues/NNN`).

**Why this is strict:** a skipped test is worse than no test. It creates the illusion of coverage while silently passing anything. The 2026-04-20 incident where calendar tests skipped 2 cases on empty-rep orgs made a real infinite-render-loop bug go undetected until the tests were fixed to seed data. Don't ship skips.

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
