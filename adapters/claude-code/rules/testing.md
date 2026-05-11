# Testing & Verification Standards

## FUNCTIONALITY OVER COMPONENTS — The most important rule in this harness (MANDATORY)

**Every test verifies functionality, not components.** The harness-wide principle is codified in `~/.claude/rules/planning.md`; this section operationalizes it for the testing surface specifically.

The three test layers in this harness are NOT interchangeable, and the third is required for completion of any user-facing task:

- **Unit tests verify components.** Function returns expected value for given input. Necessary baseline; **not sufficient** evidence of completion. A passing unit test against a stub or mock proves only that the stub is correct, not that any user-observable behavior exists.
- **Integration tests verify wiring.** Component A calls component B and the data shape contract holds. Necessary; **not sufficient**. Two correctly-wired components can still fail to produce a user-observable outcome if a third component in the chain was never built.
- **Functionality tests verify the user experience.** A user-flow scenario executes end-to-end against the running system and produces the user-observable outcome the task describes. **Required for completion of any user-facing task.** Examples: a Playwright spec that drives the UI through the task's user flow; a `curl` against the live endpoint that returns the expected user-observable response; a database query that confirms the side effect a user action would produce.

**"All tests pass" does not mean "the feature works."** Tests passing is evidence about the tests, not evidence about the feature. The feature works when a user can exercise it end-to-end and observe the expected outcome. If unit and integration tests pass but no functionality test exercises the user flow, the feature is not verified — it is vaporware behind a green test bar.

### Mocking discipline by test layer

- **Mocked LLM responses, mocked external APIs, mocked database connections, and mocked time** are acceptable for component (unit) tests. The unit's job is to verify behavior given an input; the mock is the input.
- **Mocked LLM responses, mocked external APIs, mocked databases, and mocked time are NOT acceptable for functionality tests of AI features.** The whole point of a functionality test for an AI feature is to verify the user-observable behavior the LLM actually produces — mocking the LLM defeats the test. If the LLM cost is the friction, use the smallest viable real model and the smallest realistic prompt; do not substitute the mock and claim the feature works.
- **Mocking the system under test is forbidden at every layer.** `pre-commit-tdd-gate.sh` Layer 3 already catches integration tests that mock the SUT; the rule extends here for clarity. A test that mocks the thing it claims to verify is not a test; it is theater.

### Concrete examples — same failure shape across three contexts

- **Schema task.** Unit test: "`createStateCard` function returns the expected shape." Integration test: "the API route calls `createStateCard` and persists." Functionality test: "a customer message arriving via the live webhook produces a state card with populated fields that the AI sees on the next response." First two are insufficient evidence of completion; third is required.
- **UI button fix.** Unit test: "the `launchCampaign` API returns 200 given valid payload." Integration test: "the API endpoint correctly inserts into `messages` table." Functionality test: "clicking the Launch button in the UI as a logged-in user produces messages sent to the listed contacts." First two pass while users still cannot launch a campaign; third is what proves the fix.
- **Conflict detection.** Unit test: "the `detectConflict` helper returns true for overlapping rules." Integration test: "the rule-save endpoint calls `detectConflict` before insert." Functionality test: "creating a conflicting rule in the UI shows the user a visible warning before saving." First two satisfy structural review while leaving the user un-warned; third is the feature.

### How this rule composes with the runtime-verification mandate

The task-verifier agent's `Runtime verification:` format requirement (`test <file>`, `playwright <spec>`, `curl`, `sql`, `file <path>`) is the lower-level mechanical check that lands functionality evidence on disk. The functionality-over-components principle is the higher-level decision rule: WHEN choosing between formats, prefer the one that exercises the user-observable outcome. A `test <file>::<unit-name>` line is mechanically valid format but is component-level evidence; a `playwright <spec>::<test-name>` or `curl <command>` line is the same format slot filled with functionality evidence.

Component-only evidence (only `test <file>` lines, only `file <path>` greps, only "typecheck clean" / "lint clean" / "compiles successfully") trips the warning emitted by `task-completed-evidence-gate.sh` and FAILs `task-verifier`'s primary verification axis. See `~/.claude/agents/task-verifier.md` "FUNCTIONALITY OVER COMPONENTS — your primary verification axis" for the verifier's rubric.

## Keep Going When Keep-Going Is Authorized (MANDATORY)

**When the user has given a keep-going / autonomous directive, don't narrate-and-wait between work units.** The directive is standing; it does not expire at a phase boundary, a commit, or an "end of task." If the plan, backlog, or standing instruction authorizes more work, pick the next concrete item and keep working.

**What narrate-and-wait looks like (don't do these when keep-going is active):**
- "Want me to continue with phase 2?" — the answer is yes; just do it.
- "Should I proceed with the next task?" — the authorization exists; proceed.
- "Ready to continue when you give the go-ahead." — the go-ahead was already given.
- "Next I'll need to [X]. Shall I proceed?" — stop asking, do X.
- "Let me know if you'd like me to [Y]." — Y is on the plan; do Y.

**Legitimate stopping points (always OK):**
- All authorized work is complete. Report completion with specifics (plan file, backlog items, commit SHAs) — NOT with a question.
- You hit a genuine blocker: missing credentials, ambiguous product decision, hard dependency on something the user must provide. Describe the blocker concretely.
- The user revoked the directive in their most recent message ("that's enough for today," "let's stop here," "pause").

**Enforcement:** Stop hook `narrate-and-wait-gate.sh` scans the session for keep-going signals from the user and checks whether the final assistant message trails off with a permission-seeking phrase. If so, the hook blocks session end. Escape hatch: write `.claude/state/autonomous-done-YYYY-MM-DD-HHMM.txt` with a one-line justification when authorized work is genuinely done.

**Why this is strict:** in the 2026-04-21 session the user corrected narrate-and-wait behavior at least six times ("are you still working?", "why do you keep stopping?", "please continue"). The behavioral rule alone hasn't held. The hook closes the loop — if the agent is about to stop after a permission-seeking tail, something is wrong and should be reconsidered.

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
