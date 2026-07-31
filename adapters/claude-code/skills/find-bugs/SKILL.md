---
name: find-bugs
description: Self-audit recent work for bugs before the user finds them. Invoke after completing a significant change to proactively enumerate likely failure modes (empty states, error states, edge cases, integration points, untested paths) and run available verification commands. Returns an honest list of "here's what I think I broke or missed, with evidence for each."
---

# find-bugs

Adversarial self-review skill. Used to convert "I just shipped something, it probably works" into a concrete list of things that could be wrong.

## When to use

Invoke `/find-bugs` immediately after:

- Completing a plan task (before invoking task-verifier)
- Finishing a significant edit across multiple files
- Before committing a change that touches integration surfaces (API, DB, auth, webhooks)
- Before declaring a feature done in conversation
- When the user asks "are you sure?" or "is there anything you missed?"

The default posture of this skill is paranoid. Assume something is broken until each plausible failure mode has been checked.

## How to invoke

The user runs `/find-bugs` with or without an argument:

- With argument: `/find-bugs "the new notification banner change"` — focus the audit on the described area.
- Without argument: audit everything edited recently (last ~30 min of tool-use history).

## Procedure

### Step 1. Inventory recent changes

Identify what was edited. Use these sources:

- Recent `Edit`/`Write` tool calls visible in context
- `git status` and `git diff HEAD` for staged and unstaged changes
- `git log --since="30 minutes ago" --oneline` for very recent commits
- SCRATCHPAD.md's "Latest Milestone" section for session-level context

List each file changed with a one-line summary of the change.

### Step 2. Enumerate likely failure modes per change

For each changed file, walk this checklist:

**UI components (`.tsx`, `.jsx`):**
- Does the component have a loading state? An empty state? An error state?
- If it renders data from props or hooks, what does it do when the data is `null`, `undefined`, or `[]`?
- Does every interactive element have a click handler wired?
- Are conditional renders (`{isAdmin && ...}`) blocking this element for the test user?
- Does the component render correctly in dark mode? Light mode?
- Are ARIA labels present on icon-only buttons?

**API routes (`route.ts`, `route.js`):**
- What does this route return for an unauthenticated request?
- What does it return for a user who lacks permission?
- What does it return when the DB query returns zero rows?
- Does it handle malformed request bodies without throwing?
- Is the route in the auth middleware's matcher list?
- Does any new column it queries actually exist in the schema?

**Database migrations (`supabase/migrations/*.sql`):**
- Does existing data satisfy any new NOT NULL constraints?
- Did a new table get RLS policies in the same migration?
- Was the seed function updated for org-scoped tables?

**Integration points (webhooks, cron, external APIs):**
- Is the handler registered in the aggregator (`trigger/index.ts`, route manifest, etc.)?
- What happens when the external service returns a non-200?
- What happens on timeout?
- Is there idempotency for retry storms?

**Hooks (`~/.claude/hooks/*.sh`):**
- Does `--self-test` pass?
- What happens on the negative path (the condition the hook is supposed to detect)?
- Does the hook handle missing input files gracefully?

**Plan and rule files:**
- Are all cross-references valid (no dead links)?
- Does the file read coherently end-to-end after the edit?
- Are any required sections missing per `planning.md`?

### Step 3. Run available verification

For each plausible failure mode, run the cheapest available check:

- `npx tsc --noEmit` for TypeScript changes
- `npm test` or the project's test runner
- `npm run lint` if fast
- `curl` against local dev server for API changes (if running)
- `rg <identifier>` to confirm the identifier is used/referenced where expected
- `git diff --stat` to confirm the change set matches what was intended

Capture output. Do NOT swallow errors — a failing check is part of the report.

### Step 4. Categorize findings

Group each finding as:

- **Confirmed bug** — a check failed, evidence attached, this is broken
- **Plausible bug** — pattern suggests a problem, couldn't verify in this session
- **Gap** — a check that should exist but was skipped (test wasn't written, state wasn't verified)
- **Risk** — edge case not covered, not necessarily wrong but worth noting

### Step 5. Report

Return your findings in this shape:

```
## Changes audited
<N files, listed>

## Confirmed bugs
- <file:line> — <what's wrong> (evidence: <command output / grep result>)

## Plausible bugs
- <file:line> — <what might be wrong> (reason: <pattern>, verification attempted: <what you tried>)

## Gaps
- <what check should have run but didn't> (reason: <e.g., no test infrastructure>)

## Risks
- <edge case not covered> (severity: <high/medium/low>)

## Verdict
<"Clean" if no confirmed or plausible bugs; otherwise "Issues found — see above">
```

## Discipline

- **Never return "no issues found" without having run verification commands.** The whole point of this skill is to do work, not vibe-check.
- **Confirmed bugs require evidence.** Attach the failing command output or the line that demonstrates the problem.
- **Plausible bugs must include what was tried.** "I suspect this might break but didn't check" is acceptable only if the check isn't available in this environment.
- **Small findings matter.** A missing empty state is a real bug. A missing dark mode variant is a real bug. Do not filter findings for "importance" — the user decides what to fix.

## When the context doesn't support an audit

If there are no recent changes to audit (fresh session, no edits made, no uncommitted diff), respond with:

"No recent changes to audit. `/find-bugs` runs against work done in the current session or uncommitted in the working tree. Make a change first, then invoke again."

Do not fabricate changes to audit.

## Boundary: this skill finds, it does not fix

Findings are a report. Do NOT apply fixes in the same invocation. The user decides which findings to act on, and fixes are their own edits — tracked as such, not buried inside an audit step.
