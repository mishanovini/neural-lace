---
name: verbose-plan
description: Expand an underspecified plan file to match the mandatory verbose-plan standard. Invoke when a draft plan feels thin, when plan-reviewer.sh rejected it for missing sections, or when a plan was written hastily and needs Assumptions, Edge Cases, and Testing Strategy populated. Reads the target plan, identifies gaps against the required-sections list in planning.md, proposes additions for each gap, and writes the expanded plan via Edit.
---

# verbose-plan

Plan-expansion skill. Converts a thin plan draft into a complete plan that passes `plan-reviewer.sh` and provides the builder enough context to implement autonomously.

## When to use

Invoke `/verbose-plan` when:

- A plan file exists but feels underspecified (missing context, thin task list, no assumptions)
- `plan-reviewer.sh` rejected the plan for missing required sections
- You just drafted a plan quickly and want to ensure it meets the verbose-plan standard before starting work
- The user says "expand this plan" or "beef up the plan" or "this plan is too thin"

## How to invoke

- With argument: `/verbose-plan ~/.claude/plans/foo.md` — operate on the specified plan file.
- Without argument: operate on the most recently modified file in `~/.claude/plans/` or `docs/plans/` (prefer the active plan referenced by SCRATCHPAD.md's "Active Plan" field).

If there's no clear active plan, ask the user which plan to expand.

## Required sections (from planning.md)

Every plan MUST contain:

1. **Header metadata** — `Status:`, `Execution Mode:`, `Backlog items absorbed:`
2. **Goal** — what's being built and why
3. **Scope** — explicit IN and OUT lists
4. **Assumptions** — every premise the plan relies on, explicit not implied
5. **Edge Cases** — foreseen edge conditions and how they're handled
6. **Testing Strategy** — how each task will be verified
7. **Tasks** — numbered checklist with acceptance criteria per task
8. **Files to Modify/Create** — all files the plan will touch
9. **Decisions Log** — populated during implementation
10. **Definition of Done** — final checklist

A section is "missing" if it's absent, empty, or contains only placeholder text like "[populate me]", "TODO", or "…".

## Procedure

### Step 1. Read the target plan

Read the full plan file. Do not skim. Note the existing structure, tone, and scope.

### Step 2. Identify gaps

For each required section, classify its current state:

- **Present and substantive** — no action needed
- **Present but thin** — has the header but 1-2 lines of shallow content; flag for expansion
- **Placeholder only** — has content like "TBD" or "[populate me]"; flag for replacement
- **Missing entirely** — section header not present; flag for insertion

Also check task-level quality:

- Does each task have acceptance criteria (a "Done when:" field or equivalent)?
- Does each task list its files to modify?
- Are sweep tasks (e.g., "wire X into all Y") decomposed per-target per planning.md's sweep rule?

### Step 3. Propose additions

For each gap, draft specific content that fits the plan's scope. Do NOT write generic placeholder content — the whole point of verbose plans is substantive content.

**Assumptions:** List every premise. Examples of good assumptions:
- "Supabase's RLS policies on the `foo` table allow the service role to bypass, per migration 042"
- "The test user has role='admin' in the seed data"
- "The Trigger.dev job registry at `trigger/index.ts` is the single source of truth for active jobs"
- Bad assumptions: "we're using React" (obvious), "the code will work" (vacuous)

**Edge Cases:** Name specific edge conditions and the planned handling. Examples:
- "User has no existing `bar` record: the API route returns 200 with `{ items: [] }`, not 404"
- "Migration runs on an org created before the feature existed: backfill script inserts defaults"
- "User navigates away during multi-step form: `UnsavedChangesGuard` prompts before unmount"

**Testing Strategy:** Per-task verification plan. Examples:
- "Task 1: run `npm test src/lib/foo.test.ts` — passes"
- "Task 3: E2E test in `tests/e2e/bar.spec.ts` covering the new flow"
- "Task 5: manual API call `curl -s localhost:3000/api/baz | jq` — returns expected shape"

**Decomposed sweep tasks:** If a task says "wire X into all forms", grep for the forms and list each by path as a sub-item.

### Step 4. Write the expanded plan

Apply the changes via `Edit` (preferred) or `Write` (for plans that need major restructuring).

- Preserve existing content where it's substantive
- Insert new sections in the canonical order
- Match the formatting style of existing sections (same heading depth, same bullet style)
- Do not delete the existing Decisions Log, even if it's empty

### Step 5. Verify

After writing, re-read the plan to confirm:

- Every required section is present and has substantive content
- No placeholder text remains in any required section
- The plan reads coherently end-to-end
- Tasks have acceptance criteria
- File paths cited in tasks exist or are clearly new-to-create

If `plan-reviewer.sh` is available, run it against the expanded plan and confirm it passes.

### Step 6. Report

Return a summary in this shape:

```
## Plan expanded
File: <absolute path>

## Gaps filled
- Assumptions: <N items added>
- Edge Cases: <N items added>
- Testing Strategy: <N items added>
- <other sections as applicable>

## Substantive additions (not fluff)
<list the 3-5 most important additions, briefly>

## Remaining thin areas (honest)
<sections still shallow; propose whether to dig deeper or leave as-is>

## Plan-reviewer.sh result
<PASS / FAIL / not run — and why if not run>
```

## Discipline

- **Never pad for length.** A 500-line plan is not better than a 250-line plan if the extra 250 lines are filler. Expand where content is missing, not where the plan is already substantive.
- **Do not invent scope.** If the original plan didn't mention feature X, don't add "oh and also build X" in the Assumptions section. Expansion clarifies existing scope; it does not grow scope.
- **Preserve user intent.** If the plan's author wrote something specific, don't rewrite it to match a different style. Add content around the existing text.
- **Ask when ambiguous.** If expanding a gap requires a decision the user hasn't made (e.g., "what should happen when the API returns 429?"), ask the user rather than guessing.

## When the plan is already complete

If the plan has all required sections with substantive content, respond with:

"Plan at <path> already meets the verbose-plan standard. Required sections present: Goal, Scope, Assumptions, Edge Cases, Testing Strategy, Tasks, Files, Decisions Log, Definition of Done. No expansion needed."

Do not rewrite a complete plan for style preferences.

## Boundary

This skill edits plan files. It does NOT:

- Change the plan's status (ACTIVE / COMPLETED / etc.)
- Check off any task boxes (only task-verifier may do that)
- Create decision records or commit changes
- Start implementing the plan

Its sole job is to fill in missing plan content.
