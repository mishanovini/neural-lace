# Teaching Moments — Capture User Pushbacks That Shifted Claude's Position

**Classification:** Pattern (self-applied capture discipline). The trigger is Claude's own judgment that a user pushback was substantive and produced a better outcome. There's no Claude Code hook that can mechanically detect "the user changed my mind"; this rule is enforced by Claude's discipline.

## Why this rule exists

The user is teaching their developers to get high-quality results from Claude Code. A lot of that comes down to **good prompting and asking the right questions**. Many of Claude's failure modes — confident answers based on insufficient verification, deferring instead of decomposing, missing measurement-substrate considerations — are exactly the moments where a sharp user prompt produces a better outcome than Claude's first answer.

Those moments are durable training material for any developer learning to work with Claude. Capturing them as structured examples — what Claude initially proposed, what the user challenged, the corrected position, and the lesson — creates a living curriculum.

This rule defines **when and how Claude captures those moments**, plus the file format that makes them shareable.

## When to capture

Capture when ALL of these are true:

1. **The user pushed back substantively** on a position Claude took. Not a typo correction, not a clarifying question — a challenge to the substance of Claude's reasoning, design, or recommendation.
2. **Claude's revised position is meaningfully better** than the original. Not a minor adjustment — a shift in framing, sequencing, scope, or technique that the user could not have gotten if they'd accepted Claude's first answer.
3. **The lesson is generalizable.** It transfers to other developers working on other projects with Claude. Not "I made this specific edit wrong" but "Claude tends to do X; here's how to push past it."
4. **Enough context survives in the transcript** for a developer who wasn't there to follow what happened.

Examples that qualify:
- User pushes Claude to verify a claim Claude was about to make from confidence rather than evidence
- User decomposes a Claude-proposed all-or-nothing build into staged pieces
- User questions a deferral pattern and reveals it as bottleneck-shaped instead of dependency-shaped
- User identifies missing measurement infrastructure that Claude assumed would just exist
- User catches Claude reproducing the exact failure pattern the current work is trying to fix

Examples that do NOT qualify:
- Typo corrections, formatting fixes, scope adjustments to a single task
- "Use this library instead" without a generalizable lesson
- The user supplying domain knowledge Claude couldn't have known
- Claude self-correcting without user prompt

The bar is high. **A typical session produces 0 teaching moments. A high-signal session produces 1.** If you find yourself capturing 3+ in one session, the bar is being lowered too far.

## Where to write

Files live at `docs/teaching-examples/YYYY-MM-DD-<short-slug>.md` (project-level — each project that adopts this rule has its own directory). The slug is kebab-case, ASCII only, ≤ 60 chars, names the realization concisely.

Cross-project propagation: when teaching examples are explicitly shared across projects (e.g., copied to `~/teaching-examples/`), the user does that manually for now. A future skill could automate the propagation.

## File format

```markdown
---
date: YYYY-MM-DD
topic: <short topic, ≤ 60 chars>
lesson: <one-line lesson for developers, ≤ 120 chars>
project: <project name, or "harness-development">
participants: <user>, claude
related-files:
  - <optional: path to commit, plan, or doc the moment relates to>
---

# <Title — phrased as the lesson, e.g., "Don't defer when the dependency is measurement infrastructure">

## Context

One paragraph. What were we working on? What kind of decision was being made?

## Claude's initial position

What did Claude propose / argue? Include the structure of the reasoning, not verbatim quotes — make it readable for someone who wasn't in the conversation.

## The user's pushback

What did the user challenge or question? Use their actual phrasing if it's particularly clean; otherwise summarize. The pushback IS the teachable moment — capture it precisely.

## The corrected position

What did Claude end up agreeing with after the pushback? Why was it better?

## The lesson for developers

Why this matters when working with Claude Code. 2-4 bullets. Each transferable to other developers, other projects.

- ...
- ...

## Generalization

(Optional) The broader pattern this instance fits into. Other shapes the same failure mode takes. Other prompts that surface it.
```

## Discipline for writing

When capturing, prioritize **brevity** and **transferability**:

- **Brevity:** the developer reading this should get the lesson in under 5 minutes. If your capture is longer than ~400 lines, you're including too much transcript and not enough synthesis.
- **Transferability:** strip project-specific names where the lesson is general. "The user asked about Project X" becomes "the user asked about a system component"; the lesson stays.
- **Honest framing:** capture Claude's failure mode honestly. Don't soften "Claude was wrong" into "we were exploring different framings." If Claude was wrong, the developer needs to know that's a known failure mode they should expect.
- **The user's good prompt is the artifact.** What did they say or how did they frame it that surfaced Claude's blind spot? That's what the developer needs to learn to imitate.

## Cross-references

- `docs/teaching-examples/` — the captured examples (project-level)
- `~/.claude/skills/teaching-moments.md` — companion skill for browsing / manually capturing examples (when Claude misses one)
- `~/.claude/rules/diagnosis.md` — broader "After Every Failure" loop. Teaching moments are a subset of that loop applied to Claude's own failure modes specifically.

## Scope

This rule applies in any project where the user has chosen to capture teaching moments — implicitly opt-in by creating the `docs/teaching-examples/` directory. Projects without the directory see this rule as a no-op.

## Enforcement

Pattern-only. Hook-based detection of "user changed Claude's mind" is not feasible without a PostMessage hook that doesn't exist in Claude Code. The discipline lives in Claude's judgment + the user's ability to invoke `/capture-teaching-moment` manually when Claude misses one.
