# Plan: [Task Title]
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: [none | slug-1, slug-2]

<!--
Execution Mode values:
  orchestrator  Default for multi-task plans. The main session reads this plan,
                dispatches each task to a `plan-phase-builder` sub-agent via the
                Task tool, and collects results. The main session does NOT do the
                build work itself — it stays lean as an orchestrator. See
                ~/.claude/rules/orchestrator-pattern.md for the full protocol.
  direct        Single-task quick fixes (one file, < 15 min). The main session
                does the work directly. No sub-agent dispatch overhead.

If unsure, use orchestrator. The overhead of dispatching is small; the cost of
running a multi-phase plan in one context is large (context accumulates 200+
tool uses, quality degrades).

Backlog items absorbed — required. Declares which `docs/backlog.md` open items
this plan claims. The hook `backlog-plan-atomicity.sh` enforces that absorbed
items are deleted from the backlog's open sections in the same commit as the
plan file creation.

  Backlog items absorbed: none
      Use when the plan addresses a fresh user request not previously tracked
      in the backlog (single-task quick fixes, ad-hoc bug reports, new feature
      requests). The plan creates no obligation against the backlog.

  Backlog items absorbed: add-link-validation, dark-mode-contrast-audit
      Use when the plan claims two existing backlog items. Those exact entries
      must be deleted from the backlog's open sections in the same commit. On
      plan COMPLETION the items ship archived inside the completion report. On
      ABANDONMENT or DEFERRAL the items return to the backlog with a
      `(deferred from <plan-path>)` note.

See ~/.claude/rules/planning.md, "Backlog absorption at plan creation".

Mode values:
  code    Default. Code-level work — bug fixes, UI changes, refactors,
          test additions, isolated feature work. Iteration cost is low
          (seconds to minutes), failures are cheap, iterate-and-observe
          works. No systems-engineering sections required.

  design  System-design work where iteration cost is high and failures
          compound. Required for: CI/CD workflows, database migrations,
          infrastructure config (vercel.json, Dockerfile, etc.),
          deployment systems, multi-component features that cross
          service boundaries, anything where tools-I-haven't-used-before
          enter the pipeline. When Mode: design, the "Systems
          Engineering Analysis" section at the bottom of this template
          is REQUIRED and enforced by plan-reviewer.sh. The
          systems-designer agent MUST review the plan before
          implementation begins.

See ~/.claude/rules/design-mode-planning.md for the full protocol on
design-mode tasks.
-->

## Goal
[What we're building/changing and why]

## Scope
- IN: [what's included]
- OUT: [what's explicitly excluded]

## Tasks

<!--
Mark tasks that CAN run in parallel with siblings using `[parallel]` or
group them under a batch header. Default is serial. Examples:

  [parallel] tasks that touch disjoint files and have no data dependency
  [serial]   tasks that share a file, depend on a previous task's commit,
             or compete for the same migration number / port / resource

The orchestrator reads these markers to decide dispatch batching. When in
doubt, leave unmarked (serial). See ~/.claude/rules/orchestrator-pattern.md
for the full safety rules on parallelization.
-->

- [ ] 1. [First task — specific enough to verify completion]
- [ ] 2. [Second task]

## Files to Modify/Create
- `path/to/file` — [what changes and why]

## Testing Strategy
- [How each task will be verified]

## Walking Skeleton
<!--
Thinnest end-to-end slice that touches every architectural layer the
plan will ultimately affect (e.g., UI → API → worker → DB → back to UI).
Build this FIRST, before adding features. Prevents the integration-
vaporware pattern where pieces are built in isolation and the wires
between them never get connected.

Format: one paragraph naming the slice, followed by "First task:" with
the task number from your task list that implements it. The first task
MUST be the skeleton, not individual layers.

To opt out for legitimate cases (pure refactor, pure docs, no new
user-facing flow), replace this entire block with a single line:
    Walking Skeleton: n/a — <one-sentence justification>
-->

## Decisions Log
[Populated during implementation — see Mid-Build Decision Protocol]

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

<!--
================================================================
Systems Engineering Analysis — REQUIRED when Mode: design
================================================================

If this plan has Mode: design in the header, the 10 sections below
are mandatory. Each section must have substantive content specific
to this task (not placeholder text). The plan-reviewer.sh hook
enforces this at plan-creation time. The systems-designer agent
reviews the sections for substance before implementation begins.

If Mode: code, you may DELETE everything below this HTML comment
before saving the plan. The sections are only required for
system-design work.

Theme: make the invisible visible. Every section makes one
normally-implicit aspect of the system explicit and checkable.

See ~/.claude/rules/design-mode-planning.md for guidance on what
belongs in each section and why.
-->

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
[What does success look like from the user's perspective, in measurable
terms? Include the time-to-outcome expectation. Example:
"Within 30 min of X happening, Y is observably true at URL Z, OR the
user receives a clear notification explaining what's blocked." NOT
"the system is built."]

### 2. End-to-end trace with a concrete example
[Walk ONE real example through the system step by step, with actual
values, IDs, sizes. Name every state change at every boundary. This is
where invisible state changes become visible. If writing the trace
surfaces "I don't know how this happens" moments, those are gaps to
close BEFORE implementation.]

### 3. Interface contracts between components
[For every component boundary, document the contract: data format,
size limits, timing expectations, failure modes, who validates what.
Components don't break — interfaces break. Each contract should read
as "X promises Y that...".]

### 4. Environment & execution context
[What does the runtime environment provide? What's the working
directory? What env vars are set? What tools are pre-installed?
What's ephemeral vs. persistent? What happens across restarts?]

### 5. Authentication & authorization map
[Every external boundary has an auth story. For each: what credential
format, which key/token, what permissions it needs, what tier/quota
applies. Note rate limits explicitly.]

### 6. Observability plan (built before the feature)
[Every step emits what signal? Where do logs go? How would I
reconstruct what happened from logs alone if everything fails? Every
major state transition should emit a visible checkpoint.]

### 7. Failure-mode analysis per step
[Table: for each step, what can fail, what's the observable symptom,
what's the recovery/retry policy, when does it escalate to a human?
This should be the longest section — failure modes are the bulk of
real-world system behavior.]

### 8. Idempotency & restart semantics
[What happens if each step runs twice? If a step partially completes?
What's the restart procedure from every possible intermediate state?
Systems that can't restart cleanly become corrupted systems.]

### 9. Load / capacity model
[What's the throughput limit? What's the bottleneck resource (API
rate limit, runner concurrency, DB connections, memory)? What happens
at saturation — graceful degradation or catastrophic failure?]

### 10. Decision records & runbook
[Non-trivial choices with alternatives considered (for the decisions
log). Plus: for each known failure mode, a runbook entry of symptom
→ diagnostic steps → fix or escalation. Written before production,
not after first incident.]
