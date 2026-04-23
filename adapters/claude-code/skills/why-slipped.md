---
name: why-slipped
description: Analyze a recent bug or failure and explain what hook, rule, or agent should have caught it. Use after finding a bug to extract harness-improvement opportunities. Takes the bug or failure description as input (or infers it from recent conversation context) and returns a diagnosis plus a specific proposed harness fix (hook name + file + logic, or rule addition + file + content).
---

# why-slipped

Post-mortem analysis skill that converts a specific recent failure into a concrete harness improvement proposal.

## When to use

Invoke `/why-slipped` immediately after:

- A bug the user had to point out ("why didn't you notice X?")
- A test failure caught only after deploy
- A vaporware incident (claim of "done" that turned out not to work)
- A regression caused by an edit the agent made confidently
- Any "how did we not catch this?" moment

The skill exists because failures are the highest-signal data for improving the harness. Every failure that isn't encoded as a rule or hook will repeat.

## How to invoke

The user runs `/why-slipped` with or without an argument:

- With argument: `/why-slipped "plan marked complete with 3 unbuilt tasks"` — treat the argument as the failure description.
- Without argument: infer the failure from the most recent conversation context (the last thing the user corrected or complained about).

If the failure is ambiguous or the context has drifted, ask the user one clarifying question before proceeding. Do not guess the failure from stale context.

## Procedure

Execute these steps in order. Do NOT skip steps — each one is load-bearing for the final proposal.

### Step 1. Identify the specific failure

Write down, in one paragraph, exactly what went wrong:

- What did the agent claim or do?
- What was the actual state?
- What was the delta — what was the user expecting that didn't happen?

Cite file paths, commit SHAs, or session artifacts where possible. "The plan had task 3.4 marked complete but the API route at `src/app/api/foo/route.ts` returns a 404" is a specific failure. "Claude made a mistake" is not.

### Step 2. Trace the enforcement map

Read `~/.claude/rules/vaporware-prevention.md` — specifically the "Enforcement map" table. For each row in that table, ask:

- Does this hook/rule apply to the failure class?
- If yes, did it fire? If it fired, what did it say?
- If it didn't fire, why not? (Wrong trigger, disabled, missing file, false-negative logic?)
- If there's no row that covers this failure class, note that — a gap in the map is itself the finding.

Also check:

- `~/.claude/rules/planning.md` for plan-lifecycle rules
- `~/.claude/rules/testing.md` for verification rules
- `~/.claude/rules/diagnosis.md` for correction-feedback rules
- `~/.claude/hooks/` directory for all active hooks (not just the ones listed in the map)

### Step 3. Classify the failure type

Pick ONE primary classification:

- **Vaporware** — feature claimed done without runtime verification
- **Context drift** — old instruction forgotten / inverted after compaction or long session
- **Self-report** — agent marked its own work complete without independent check
- **Sharing blind spot** — work done but never propagated to other surfaces (neural-lace, docs, backlog)
- **Scope creep** — built something outside the plan without updating the plan
- **Incomplete sweep** — task described as "all X" but only some X were done
- **Missing precondition check** — edit assumed state that didn't exist (migration, env var, RLS)
- **Other** — describe precisely

Secondary classifications are welcome if the failure is genuinely multi-causal.

### Step 4. Propose a specific fix

The proposal MUST be concrete. Not "we should add a hook." A full path plus actual content.

Acceptable fix shapes:

- **New hook:** `~/.claude/hooks/<name>.sh` — include a sketch of the hook body (what event, what trigger, what check, what exit code). If the fix is a PreToolUse/PostToolUse/SessionStart hook, specify which.
- **Rule addition:** `~/.claude/rules/<existing-file>.md` — include the exact paragraph to add, with context on where in the file it goes.
- **Agent modification:** `~/.claude/agents/<name>.md` — include the specific instruction to add or modify.
- **Template change:** `~/.claude/templates/<name>.md` — include the section to add.
- **Skill addition:** `~/.claude/skills/<name>.md` — include the frontmatter and body sketch.

If the fix requires changes in multiple files (e.g., a rule plus a hook that enforces it), list all files.

### Step 5. Justify the mechanism

In 2-3 sentences, explain why the proposed fix catches the failure class — not just the specific instance. "This hook fires on every plan file save and checks for unchecked tasks under a COMPLETED status, catching not just this plan but any plan completed without finishing its work" is a class-level justification. "This would have caught the specific bug on 2026-04-19" is not.

### Step 6. Identify residual risk

Every mechanical fix has edge cases it doesn't cover. Name them explicitly:

- What variant of this failure would the proposed fix NOT catch?
- What new failure mode does the fix introduce (false positives, bypass routes)?
- Is there a higher-leverage fix that the proposed change is a partial approximation of?

Honesty about residual risk is required. A proposal that claims to close a class completely is usually wrong.

## Output format

Return your analysis in this shape:

```
## Failure
<one-paragraph description from Step 1>

## Enforcement trace
<what in the map should have caught it, and why didn't it>

## Classification
<primary type>, optionally <secondary types>

## Proposed fix
File: <absolute path>
Shape: <new | modify>
Content:
---
<actual file content or the exact paragraph to add>
---

## Why this catches the class
<2-3 sentences>

## Residual risk
<what this does NOT catch, honestly>
```

## Boundary: this skill proposes, it does not implement

The skill's output is a proposal. Do NOT apply the fix in the same invocation — the user should review and approve before the harness changes. Creating or editing `~/.claude/` files is a separate step that requires explicit user direction.

## When the context doesn't support a diagnosis

If the recent conversation doesn't contain a specific failure (e.g., user invoked the skill out of curiosity), respond with:

"No specific failure is in scope for this session. `/why-slipped` analyzes a concrete recent bug or correction. If you have a specific failure in mind, invoke again with `/why-slipped <description>`."

Do not fabricate a failure to have something to analyze.
