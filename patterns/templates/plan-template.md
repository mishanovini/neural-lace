# Plan: [Task Title]
Status: ACTIVE
Execution Mode: orchestrator

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

## Decisions Log
[Populated during implementation — see Mid-Build Decision Protocol]

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
