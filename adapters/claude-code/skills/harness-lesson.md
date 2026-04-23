---
name: harness-lesson
description: Encode a recent failure as a proposed harness change (hook, rule, or agent modification) that would prevent the class. Input is a description of what went wrong (or inferred from context). Output is a concrete file-level proposal — full file path plus actual content, not "you should add a hook" — with justification and honest residual-risk analysis.
---

# harness-lesson

Failure-to-mechanism skill. Takes a specific failure as input and produces a deployable harness change that catches the entire class of failure, not just the specific instance.

This is the "encode the fix" step from `~/.claude/rules/diagnosis.md`. Every failure that isn't encoded repeats.

## When to use

Invoke `/harness-lesson` after:

- `/why-slipped` analyzed a failure and you want to produce the actual fix file
- A user correction surfaced a pattern that should become a rule
- A postmortem identified a root cause that needs a mechanical guard
- A repeat failure (same class, different instance) shows a rule is missing or insufficient

The skill is the complement to `/why-slipped`: that skill diagnoses, this skill proposes the concrete mechanism.

## How to invoke

- With argument: `/harness-lesson "plan marked complete while tasks 3.4 and 3.5 were still unchecked"` — treat the argument as the failure description.
- Without argument: infer from the most recent failure in context.

If the context is ambiguous, ask the user to describe the failure in one sentence before proceeding.

## Procedure

### Step 1. Restate the failure precisely

Write a one-paragraph description that answers:

- What was the expected behavior?
- What actually happened?
- What was the trigger (what tool call, state, or edit set the failure in motion)?
- What was the detection delay (immediate? next session? user caught it?)

Cite specific file paths, commit SHAs, or conversation moments where possible.

### Step 2. Classify the failure

Pick the primary class. The canonical list:

- **Vaporware** — feature claimed done without runtime verification
- **Self-report** — agent marked its own work complete without independent check
- **Context drift** — prior instruction forgotten after compaction or long session
- **Sharing blind spot** — work done on one surface, never propagated to another
- **Scope drift** — built outside the plan without updating the plan
- **Incomplete sweep** — "all X" task completed after only some X were done
- **Missing precondition** — edit assumed state (migration, env, config) that wasn't present
- **Silent swallow** — error caught but not surfaced to the user or next session
- **Stale reference** — docs/rules point at files that no longer exist
- **Bypass** — enforcement layer existed but was skipped via a route the layer didn't cover

If the failure is multi-causal, list a primary and up to two secondary classes.

### Step 3. Choose the mechanism type

Map the failure class to the appropriate mechanism. The harness has these enforcement surfaces:

- **PreToolUse hook** (`~/.claude/hooks/*.sh` wired into `settings.json`) — blocks a tool call before execution. Best for: preventing actions that should never happen (committing without tests, editing plan files without evidence).
- **PostToolUse hook** — fires after a tool call; useful for logging and derivative checks. Weaker enforcement than Pre.
- **Pre-commit hook** (git-level) — gates commits. Best for: TDD gate, review-finding-fix-gate, harness-hygiene-scan.
- **SessionStart hook** — runs at session start; surfaces warnings and context. Best for: reminders, freshness checks, policy warnings.
- **Stop hook / pre-stop** — runs at session end; blocks stop if preconditions aren't met. Best for: plan-integrity sweep.
- **Agent** (`~/.claude/agents/*.md`) — an independent reviewer that the main session delegates to. Best for: adversarial review (task-verifier, claim-reviewer, plan-evidence-reviewer).
- **Rule file** (`~/.claude/rules/*.md`) — behavioral convention, self-applied. Best for: patterns that are hard to mechanically detect but easy to state.
- **Template change** (`~/.claude/templates/*.md`) — default structure for new files. Best for: enforcing required sections by default.
- **Skill** (`~/.claude/skills/*.md`) — user-invokable procedure. Best for: reducing friction on a task that's currently manual.

Prefer mechanical enforcement (hook/agent) over rule-only fixes when the class is mechanically detectable. Rules are the fallback when detection is impossible or when false-positive cost is high.

### Step 4. Draft the concrete mechanism

Produce the actual file content. Not "you should add a hook that checks for X." The full file.

**For a new hook:**
- Absolute path
- Shebang (`#!/bin/bash`)
- Event it hooks (PreToolUse / PostToolUse / SessionStart / etc.)
- Tool filter (if PreToolUse/PostToolUse — which tools)
- The actual check logic
- Exit codes (0 = pass, non-zero = block) with clear error messages
- `--self-test` flag path
- Any settings.json wiring required to activate the hook

**For a rule addition:**
- Which rule file to modify (or whether to create a new one)
- Exact paragraph(s) to add
- Where in the file they belong (before/after which existing section)

**For an agent modification:**
- Agent file path
- Exact instruction block to add

**For a template change:**
- Template file path
- Exact section or field to add, with formatting matching the existing template

Always include enough context that the user can apply the change without further research.

### Step 5. Justify at the class level

In 3-5 sentences, explain:

- Why this mechanism catches the class, not just the instance
- What triggers are necessary for the mechanism to fire
- What the mechanism does when it fires (block / warn / dispatch an agent)
- Why this location in the enforcement stack (why a hook vs. a rule, why PreToolUse vs. PostToolUse, etc.)

### Step 6. Identify residual risk

Every mechanism has gaps. Name them explicitly:

- What variant of this failure does the mechanism NOT catch?
- What bypass routes exist (direct file write, different tool, out-of-band action)?
- What false positives might it introduce?
- Is there a cheaper-but-weaker version that would 80% the goal?
- Is there a stronger version that would need infrastructure the harness doesn't have?

Do not claim complete coverage. Honesty about gaps is required — it's what lets future lessons build on this one.

### Step 7. Note the companion work

Many harness changes need companion edits to be effective:

- A new hook needs a `settings.json` entry to be active
- A new agent needs a rule referencing it from the relevant protocol
- A new rule needs a cross-reference from CLAUDE.md's "Detailed Protocols" section
- A mirror to `~/claude-projects/neural-lace/adapters/claude-code/` per `harness-maintenance.md`
- An update to `~/.claude/docs/harness-architecture.md` inventory

List every companion change the user will need to make.

## Output format

```
## Failure
<Step 1: one paragraph>

## Classification
Primary: <class>
Secondary: <class(es) or "none">

## Mechanism type
<new hook | rule addition | agent mod | template change | skill>
Reason: <why this surface>

## Proposal

### File: <absolute path>
<content here — the actual file body or the exact paragraph to add>

### (Optional) File: <absolute path>
<companion file content>

## Why this catches the class
<3-5 sentences per Step 5>

## Residual risk
- <gap 1>
- <gap 2>
- <bypass route, if any>

## Companion work required
- <settings.json wiring, if hook>
- <cross-references in CLAUDE.md / rules, if applicable>
- <mirror to neural-lace + commit>
- <architecture doc update>
```

## Discipline

- **Concrete, not advisory.** "Add a hook that validates plan files" is not a proposal. The actual hook file content is a proposal.
- **Class-level, not instance-level.** If the proposal only catches the one specific bug you're reacting to, it's not a harness lesson — it's a bug fix. Generalize.
- **One mechanism per invocation.** Don't stack three proposals in one response. If the failure needs multiple layers, surface that in "Companion work required" and invoke the skill again for each layer.
- **Verifiable.** The proposal must include how to test the new mechanism (`--self-test` for hooks; a manual test case for rules).

## Boundary: this skill proposes, it does not implement

The skill's output is a proposal. Do NOT create or modify `~/.claude/` files in the same invocation. The user reviews, decides, and then applies (or a follow-up invocation with the user's go-ahead applies it). This boundary exists because harness changes ship globally — every future session is affected — and deserve explicit human approval.

## When there's no failure to analyze

If the recent context doesn't contain a specific failure, respond with:

"No specific failure is in scope. `/harness-lesson` produces a harness change in response to a concrete failure. Describe the failure: `/harness-lesson <what went wrong>`."

Do not invent a failure to have something to propose.
