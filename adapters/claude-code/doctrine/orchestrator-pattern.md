# Orchestrator Pattern — compact
> Enforcement: Pattern — self-applied; task-verifier mandate + plan-edit-validator.sh back the verification layer. Full: doctrine/orchestrator-pattern-full.md
> Applies: any multi-task plan (≥2 tasks) — the main session orchestrates; builders build.

- Dispatch each task to a fresh plan-phase-builder sub-agent. The main session does NOT build directly — every direct Edit/Write is context it carries for the rest of the session.
- Parallel dispatch is the default for independent tasks (disjoint file sets). Serialize when tasks share files, data, or resources. Cap parallel builders at ≤5; batch larger sweeps.
- Parallel builders MUST run with `isolation: "worktree"`. Worktrees root at master HEAD, so every dispatch prompt's mandatory first-action is: `git checkout -b worker-<task-id> <feature-branch>` to land the builder on the orchestrator's branch. Commit plan edits BEFORE dispatching.
- Build in parallel, verify sequentially: builders build + commit in their worktrees and return {verdict, worktree_path, commit_shas, summary} WITHOUT invoking task-verifier; the orchestrator then processes results in task-ID order — cherry-pick the commits onto the feature branch, invoke task-verifier, tear down the worktree. A cherry-pick conflict means the parallelism assumption was wrong: abort, mark BLOCKED, never force-resolve.
- A builder's return is a CLAIM. Before accepting any verdict, confirm the evidence artifact on disk: cited SHAs resolve, the evidence block / .evidence.json exists for the task ID, the checkbox is flipped. A reported verdict with no on-disk artifact is FAIL — never trust builder claims, never re-narrate them as fact.
- Dispatch prompts are self-contained: plan path, task IDs, branch + HEAD, env vars, acceptance scenarios verbatim — but NEVER the advocate's assertion list (scenarios-shared, assertions-private).
- Builders return ≤500 tokens: verdict, summary, commits, blockers. Push back on sprawl.
- On BLOCKED or FAIL: stop dispatching and report the blocker — never route around it to the next task.
- Cross-repo dispatch: `isolation: "worktree"` roots in the LAUNCHER's repo; instruct the builder to detect this and create its own worktree in the target repo.
- The orchestrator's deliverable is the CLOSED plan (checkboxes verified, completion report, Status flipped, archived) — "all builders returned DONE" is not completion.
