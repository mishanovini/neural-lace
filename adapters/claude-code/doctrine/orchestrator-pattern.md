# Orchestrator Pattern — compact
> Enforcement: Pattern — self-applied; task-verifier mandate + plan-edit-validator.sh back the verification layer. Full: doctrine/orchestrator-pattern-full.md
> Applies: any multi-task plan (≥2 tasks) — the main session orchestrates; builders build.

- Dispatch each task to a fresh plan-phase-builder sub-agent. The main session does NOT build directly — direct Edit/Write bloats its context.
- Parallel dispatch is the default for independent tasks (disjoint file sets). Serialize when tasks share files, data, or resources. Cap parallel builders at ≤5; batch larger sweeps.
- Parallel builders MUST run with `isolation: "worktree"`. Worktrees root at master HEAD, so every dispatch prompt's mandatory first-action is `git checkout -b worker-<task-id> <feature-branch>` to land the builder on the orchestrator's branch. Commit plan edits BEFORE dispatching.
- Shared-checkout git-state disciplines (mechanics + incidents in -full.md): WORKTREE-CHECK (builder confirms its OWN worktree via `git rev-parse --show-toplevel`); BRANCH-VERIFY + `ls-remote` around every shared commit/push; COMMIT-VERIFY-AFTER-DENIAL (a denied `add && commit && push` kills the commit — `git log -1` first).
- Build in parallel, verify sequentially: builders build + commit in their worktrees and return ≤500 tokens (verdict, summary, commit SHAs, blockers) WITHOUT invoking task-verifier; the orchestrator then processes results in task-ID order — cherry-pick onto the feature branch, invoke task-verifier, tear down the worktree. A cherry-pick conflict means the parallelism assumption was wrong: abort, mark BLOCKED, never force-resolve.
- A builder's return is a CLAIM. Before accepting a verdict, confirm the on-disk evidence: cited SHAs resolve, the evidence block / .evidence.json exists for the task ID, the checkbox is flipped. A verdict with no on-disk artifact is FAIL — never trust builder claims, never re-narrate them as fact.
- Dispatch prompts are self-contained: plan path, task IDs, branch + HEAD, env vars, acceptance scenarios verbatim — but NEVER the advocate's assertion list (scenarios-shared, assertions-private).
- On BLOCKED or FAIL: stop dispatching and report the blocker — never route around it to the next task.
- Cross-repo dispatch: `isolation: "worktree"` roots in the LAUNCHER's repo — instruct the builder to make its own worktree in the target repo.
- The orchestrator's deliverable is the CLOSED plan (checkboxes verified, completion report, Status flipped, archived) — "all builders returned DONE" is not completion.
- **Proactive audit loop** before declaring a product area done (incident 2026-06-18; the 6 dead-code patterns + full protocol are in -full.md): (a) static failed-functionality hunt; (b) runtime-exercise EVERY claimed flow and verify the outcome; (c) fix → re-audit → repeat to a clean pass. Bar: surface problems the operator did NOT point at, or the audit failed.
