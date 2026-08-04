# Orchestrator Pattern — compact
> Enforcement: Pattern — self-applied; task-verifier + plan-edit-validator.sh back verification. Full: doctrine/orchestrator-pattern-full.md
> Applies: any multi-task plan (≥2 tasks) — the main session orchestrates; builders build.

- Dispatch each task to a fresh plan-phase-builder sub-agent. The main session does NOT build directly — every direct Edit/Write is context it carries for the rest of the session.
- Parallel dispatch is default for independent (disjoint-file) tasks; serialize when tasks share files/data/resources. Cap parallel builders ≤5; batch sweeps.
- Parallel builders MUST use `isolation: "worktree"`. Worktrees root at master HEAD — first dispatch action: `git checkout -b worker-<task-id> <feature-branch>` to land on the orchestrator's branch. Commit plan edits BEFORE dispatching.
- Shared-checkout disciplines (incidents 07-06/07/09; detail: -full.md): WORKTREE-CHECK — confirm own worktree before any commit; BRANCH-VERIFY + `ls-remote` around a commit; COMMIT-VERIFY-AFTER-DENIAL — a denied compound command kills the commit too; verify via `git log -1`.
- Build in parallel, verify sequentially: builders build+commit in worktrees, return verdict+worktree_path+commit_shas+summary WITHOUT invoking task-verifier; orchestrator cherry-picks each result (task-ID order) onto the feature branch, invokes task-verifier, tears down the worktree. Conflict = wrong parallelism: abort, mark BLOCKED, never force.
- A builder's return is a CLAIM: confirm on disk first — SHAs resolve, evidence block/.evidence.json exists, checkbox flipped. No artifact = FAIL; never trust or re-narrate an unconfirmed claim.
- Dispatch prompts are self-contained: plan path, task IDs, branch+HEAD, env vars, scenarios verbatim — NEVER the assertion list (scenarios-shared, assertions-private). MUST open with `NL-ATTRIBUTION: plan=<slug> task=<id> role=<builder|verifier|reviewer|advocate>` (workstreams-emit.sh); WARN-only. Quoted-header residual + GENERATE-not-hand-type (`dispatch-directives.sh`): -full.md.
- Builders return ≤500 tokens (verdict, summary, commits, blockers); push back on sprawl. On BLOCKED/FAIL: stop dispatching, report the blocker — never route around it.
- Cross-repo dispatch: `isolation: "worktree"` roots in the LAUNCHER's repo; the builder must detect this and worktree into the target repo itself.
- The orchestrator's deliverable is the CLOSED plan (checkboxes verified, completion report, Status flipped, archived) — "builders DONE" != completion.
- Verify obligations (OD-022): open ledger row blocks builder @3+; Stop refuses unnamed DONE. -full.md.
- **Proactive audit loop** (detail: -full.md): before declaring a product area done — (a) static hunt: computed-then-discarded, never-invoked, placeholder-as-real, UI-reads-dead-field, endpoint-noop, dead-flag-path; (b) exercise EVERY claimed flow at runtime; (c) fix → re-run both → repeat to clean pass. Bar: surface unprompted problems.
