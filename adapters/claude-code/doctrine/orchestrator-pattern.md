# Orchestrator Pattern — compact
> Enforcement: Pattern — self-applied; task-verifier + plan-edit-validator.sh back verification. Full: doctrine/orchestrator-pattern-full.md
> Applies: any multi-task plan (≥2 tasks) — the main session orchestrates; builders build.

- Dispatch each task to a fresh plan-phase-builder sub-agent. The main session does NOT build directly — every Edit/Write is context it carries for the rest of the session.
- Parallel dispatch is default for independent (disjoint-file) tasks; serialize on shared files/data. Cap builders ≤5; batch sweeps.
- Parallel builders MUST use `isolation: "worktree"` (roots at master HEAD — first action: `git checkout -b worker-<task-id> <feature-branch>`). Commit plan edits BEFORE dispatching.
- Shared-checkout disciplines (incidents 07-06/07/09: -full.md): WORKTREE-CHECK before commit; BRANCH-VERIFY + `ls-remote` around a push; COMMIT-VERIFY-AFTER-DENIAL — denied compound kills the commit; verify `git log -1`.
- Build in parallel, verify sequentially: builders build+commit in worktrees, return verdict+worktree_path+commit_shas+summary WITHOUT invoking task-verifier; orchestrator cherry-picks each result (task-ID order), verifies, removes worktree. Conflict = abort + BLOCKED, never force.
- A builder's return is a CLAIM: confirm on disk first — SHA resolves, evidence artifact exists, checkbox flipped. No artifact = FAIL; never re-narrate unconfirmed.
- Dispatch prompts are self-contained: plan path, task IDs, branch+HEAD, env vars, scenarios verbatim — never the assertion list (scenarios-shared, assertions-private). Must open with `NL-ATTRIBUTION: plan=<slug> task=<id> role=<role>` (WARN-only). Residuals + directive-gen: -full.md.
- Builders return ≤500 tokens (verdict, summary, commits, blockers); push back on sprawl. BLOCKED/FAIL: stop dispatching, report it — never route around it.
- Cross-repo dispatch: `isolation: "worktree"` roots in the LAUNCHER's repo; builder must detect + worktree into the target repo.
- The orchestrator's deliverable is the CLOSED plan (checkboxes verified, completion report, Status flipped, archived) — "builders DONE" != completion.
- Verify obligations (OD-022): open ledger row blocks builder @3+; Stop refuses unnamed DONE. -full.md.
- **Proactive audit loop** (-full.md): before declaring an area done — (a) static hunt (computed-then-discarded, never-invoked, placeholder-as-real, UI-reads-dead-field, endpoint-noop, dead-flag-path); (b) exercise every claimed flow at runtime; (c) fix→re-audit to clean. Bar: surface unprompted problems.
- G2 gate: Task|Agent dispatch routes through dispatch-chain-gate.sh — chain-invalid BLOCKS, grandfathered/no-repo WARN. -full.md.
- **Solution-shape protocol** (OD-024, -full.md): before dispatching a fix for an operator-reported defect, state the CLASS + sweep six layers (schema, gate, parser, migration, doctrine, prompt) — each used or waived with a reason; instance-only needs a named exception.
