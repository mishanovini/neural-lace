---
date: 2026-05-06
topic: Don't defer building infrastructure when the dependency is the measurement substrate itself
lesson: When Claude says "wait for evidence before building X," check whether X IS what produces the evidence — if so, deferring just delays measurement.
project: harness-development
participants: misha, claude
related-files:
  - docs/build-doctrine-roadmap.md (Tranche 6 decomposition row)
  - build-doctrine/doctrine/06-propagation.md (the engine spec)
---

# Don't defer when the dependency is measurement infrastructure

## Context

Working on the Build Doctrine integration roadmap. The user asked Claude to explain the propagation engine (a planned system that auto-fans out changes across canon artifacts — engineering catalog, design system, ADRs, etc., with a 7-trigger taxonomy). Then asked: "Why is it preferable to test this harness on a pilot project before building this propagation engine?"

Claude gave a confident multi-part answer leaning on doctrine principles (Anti-Principle 16: reactive enforcement compounding) to justify deferring the engine until the pilot generates empirical evidence about which propagation rules matter.

## Claude's initial position

Build the engine **after** the pilot. Reasoning given:
- The engine's value lives in its rules, and rules need evidence
- Pilot evidence is what calibrates the rule schema
- High-cost mechanisms misdirected are worse than low-cost ones
- AP16 says "let observed failures justify mechanism, not anticipated failures"
- Several artifacts the engine routes between don't exist yet (engineering catalog, design system, Integration Map)
- The four narrow hooks already cover high-traffic paths; the engine generalizes long-tail

Claude was confident in this answer. It cited multiple doctrine sources. It produced a clean structural argument.

## The user's pushback

Two questions, both sharp:

1. **"Will there be mechanisms in place to actually measure these traffic patterns?"** This question forces Claude to look at what measurement infrastructure exists vs. what doesn't. The honest answer turns out to be: **the propagation audit log IS the measurement mechanism, and it doesn't exist until the engine ships**. Without the engine, the pilot generates operator memory (impressions), not structured data (counted events).

2. **"Would it be more practical to have some starter rules that can be fine tuned when we discover that they're either too eager or too rare?"** This reframes the build/defer decision entirely. Instead of waterfall (wait → build → operate), the user proposes iterative (build with starter rules → operate → measure → tune). Bootstrap the system using the system.

The user followed up with another sharp observation: "Are there even mechanisms in place to actually capture and document findings and discoveries? If not, then Claude didn't think this through thoroughly, which is exactly the pattern this effort is attempting to overcome."

## The corrected position

Decompose the propagation engine into stages:

- **6a (engine framework + audit log + starter rules):** Ships now. The router code is generic (~200-400 lines bash). The starter rules generalize 4 already-firing narrow hooks (zero conjecture — these are proven). Plus 3 conjectural rules covering canon that exists today (ADRs, doctrine, findings ledger). Crucially, **the audit log ships with the framework**, which converts the pilot from impression-generating to data-generating.

- **6b (per-canon-category rules):** Waits for pilot artifacts. Rules covering engineering catalog signature changes, design-system component changes, cross-repo edges need the canon artifacts those rules fan out to — and those don't exist in any project yet.

- **6c (telemetry-driven refinement):** Waits for telemetry infrastructure (HARNESS-GAP-11, gated 2026-08). PT-5 drift detection specifically requires scheduled consistency-check infrastructure.

The corrected position is **strictly better than Claude's initial position**. It produces measurement capability sooner, generates evidence sooner, refines rules iteratively against real audit-log data instead of operator impressions, and still defers the parts that genuinely need pilot artifacts.

## The lesson for developers

Four takeaways for working with Claude Code:

- **When Claude says "wait for evidence," ask what the evidence-collection mechanism is.** If the answer is "we'll figure it out during the pilot," that's a red flag. Instrumentation is its own subsystem; if it doesn't exist yet, the pilot generates impressions, not data. Push Claude to identify the measurement substrate explicitly.

- **"Defer this until X happens" is a deferral pattern; ask whether X actually has to come first.** Claude has a bias toward sequential dependencies. Reality often supports decomposition: the framework here ships independently from the rules; the proven rules ship independently from the conjectural ones. Asking "can this be split?" reveals seams Claude didn't surface.

- **Starter rules + iterative tuning beats waterfall design.** This is generally true for any system whose value lives in its config rather than its code. If Claude is proposing "design the perfect schema first," consider whether starter values + an audit log + refinement is the more practical path.

- **Test whether Claude actually checked.** When Claude makes confident claims about what infrastructure exists ("there's no measurement substrate"), ask directly: "Did you check?" Claude often answers from probability rather than verification — and the failure mode is exactly what doctrine principle AP16 critiques (reactive enforcement compounding without the evidence loop). The pushback "Are there even mechanisms in place to capture findings?" forced Claude to actually look. The answer turned out to be more nuanced than Claude's confident "not really."

## Generalization

The broader pattern: **Claude often confidently defers infrastructure whose absence is the actual blocker**. The shape of the failure:

> Claude: "We should wait for X to happen before building Y."
> Reality: "X requires Y to happen. Building Y is what enables X."

The user's prompt that surfaces this: **"What mechanism is in place to make X happen?"** — forces Claude to inspect rather than assume. If the answer is "we'll add it later," that's the moment to question the deferral.

A related variant: when Claude proposes building a rich system in one phase, ask **"What's the minimum slice that produces value AND generates measurement?"** Often the answer is much smaller than Claude's first proposal.

This pattern shows up in: instrumentation, telemetry, auditing, observability, validation, schema design, content seeding, rule libraries, configuration systems. Anywhere "the value lives in the data the system collects" but "the system has to exist to collect the data," Claude has a documented bias toward designing the rich version first. Push back.

## What good prompts looked like in this conversation

Both of the user's pushback questions are reusable templates:

- **"Will there be mechanisms in place to actually measure these traffic patterns?"** — generic template: "Will there be mechanisms in place to actually [measure / verify / observe / record] these [outputs / patterns / events]?"

- **"Would it be more practical to have some starter rules that can be fine tuned when we discover that they're either too eager or too rare?"** — generic template: "Would it be more practical to ship a starter version of [X] that can be tuned when we discover [failure-mode-1] or [failure-mode-2]?"

Both questions force Claude to consider iterative-deployment over waterfall-design. Save and reuse.
