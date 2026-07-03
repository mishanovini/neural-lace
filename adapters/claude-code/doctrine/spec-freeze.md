# Spec Freeze — compact
> Enforcement: spec-freeze-gate.sh (PreToolUse Edit/Write), scope-enforcement-gate.sh (commit-time sibling), plan-reviewer.sh Check 10. Full: doctrine/spec-freeze-full.md
> Applies: every ACTIVE plan — declared files cannot be edited until the plan's spec is frozen.

- `frozen: true` in the plan header means the `## Files to Modify/Create` section is the committed scope contract as of the plan's current commit. `frozen: false` (or a missing field) means the spec is still being authored — the gate BLOCKS Edit/Write on any file the plan declares.
- Freeze after the final spec review: all sections populated and stable, pre-implementation reviews passed (systems-designer / prd-validity-reviewer / ux-designer / end-user-advocate as applicable), typically in the same commit that sets `Status: ACTIVE`. If you're unsure whether more files will enter scope, stay unfrozen and keep authoring — an extra iteration is cheaper than thaw noise.
- Plan files themselves are exempt: checkbox flips, evidence appends, and Decisions Log entries are always allowed.
- Light drift (one missing file discovered mid-build): add a line to `## In-flight scope updates` (`- <YYYY-MM-DD>: <path> — <one-line reason>`); the gate honors those entries alongside Files to Modify/Create.
- Heavier amendment (multiple files, restructured tasks, a new phase) uses the thaw protocol: (1) flip `frozen: true` → `frozen: false`; (2) add a Decisions Log entry naming what changes and why, in the same commit; (3) amend the spec; (4) re-flip to `frozen: true` when stable. Three or more in-flight updates in quick succession = thaw instead — the lighter mechanism is dodging the Decisions Log entry the situation warrants.
- Never thaw for unrelated refactors ("while I'm here"), to dodge the gate under time pressure, or to thaw-edit-refreeze without amending the spec. Genuinely cross-plan work opens its own plan.
- Orchestrators freeze BEFORE dispatching builders — an unfrozen plan blocks every builder Edit on declared files.
