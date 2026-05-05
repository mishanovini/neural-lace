# Spec Freeze — Declared Files Cannot Be Edited Until the Plan's Spec Is Frozen

**Classification:** Hybrid. The "freeze the spec before editing files declared in scope" discipline is a Pattern the planner self-applies after a final spec review. The "edits to declared files are mechanically blocked unless the owning plan has `frozen: true`" rule is a Mechanism enforced by `spec-freeze-gate.sh` (PreToolUse `Edit` / `Write`). The freeze-thaw protocol — flip `frozen: false`, expand the plan's `## Files to Modify/Create` section, log the rationale in the Decisions Log, re-flip `frozen: true` — is Pattern-only; the hook only checks the binary state, not the protocol's audit-trail steps.

**Ships with:** Decision 016 (`docs/decisions/016-spec-freeze-gate-c2.md`) — read it first for the five sub-decisions (`frozen: true|false` is a plan-header field; freeze captures the plan's commit SHA implicitly; thawing requires explicit flip with rationale; recovery from drift via `## In-flight scope updates` for light cases or freeze-thaw for heavy cases; plan files themselves are exempt).

## Why this rule exists

Before C2 (the spec-freeze gate), a builder could begin editing files in mid-build, realize the design needed adjustment, edit the plan to add or restructure files, edit the file again, and continue — producing silent scope expansion that was invisible at session end. The plan effectively re-authored itself as work progressed. By the time a reviewer looked at the finished plan, the plan's `## Files to Modify/Create` section reflected the work that happened, not the work that was planned.

This is a load-bearing failure mode for the harness's discipline of "plan first, build to plan." If the plan can be silently rewritten during the build, the plan's pre-implementation review (`systems-designer`, `prd-validity-reviewer`, `ux-designer`, `end-user-advocate`) is reviewing a document that no longer matches what gets shipped. C2 closes the loop by making the spec a binary-frozen artifact: edits to declared files are blocked unless the plan has been explicitly marked `frozen: true`. Any subsequent change to scope is a deliberate plan amendment with an audit trail, not an in-flight drift.

C2 is a sibling to C10 (`scope-enforcement-gate.sh`, already shipped Phase 1d-C-1). C10 fires at `git commit` time and checks staged-files-vs-plan-bullets; C2 fires at `Edit` / `Write` time and checks file-being-edited-vs-plan-bullets-on-frozen-plans. The two complement each other: C10 catches scope expansion at commit (the latest moment); C2 catches scope expansion the moment it begins (the earliest moment). Both are needed because each fires at a different boundary, and both surface different failure modes (forgetting to update the plan vs. starting work before the plan is settled).

## What spec freeze means

`frozen: true` in a plan's header indicates: **the plan's `## Files to Modify/Create` section is the final declared scope as of the plan's current commit.** No further edits to declared files happen without an explicit thaw. The author has reviewed the scope and committed to its boundary; the spec is now governing the build.

`frozen: false` in a plan's header indicates: **the plan's spec is still being authored.** The scope set is mutable; the plan cannot govern edits yet because there is no committed contract. The gate blocks edits to declared files because no spec-as-contract exists.

Missing `frozen:` field is treated identically to `frozen: false` — the plan-reviewer's Check 10 (5-field plan-header schema) catches missing fields at plan-edit time, but the spec-freeze gate degrades to "no contract, block edits" when the field is absent.

The semantics are deliberately binary. A three-state field (`pending | frozen | thawed`) was considered and rejected (Decision 016, alternatives) — the binary flag with explicit thaw-via-flip captures the same audit trail without the complexity of a state machine.

### What freeze does NOT mean

- Freeze does not lock the plan file itself. Plan files MUST remain editable to update task checkboxes, append evidence blocks, add Decisions Log entries, append in-flight scope updates. The gate excludes `docs/plans/.*\.md` from the file-claim check (Decision 016e).
- Freeze does not prevent edits to files outside the plan's declared scope. The gate is scoped to files the plan claims; an unrelated refactor in a separate component proceeds normally.
- Freeze does not require a commit-by-commit hash. The freeze is implicit — the commit that flips `frozen: true` IS the freeze point. `git log -p docs/plans/<slug>.md` answers "what was the frozen scope?" without parallel state-tracking machinery (Decision 016b).

## When to freeze

The planner flips `frozen: true` after the final spec review. Concrete signals that the plan is ready to freeze:

1. **Goal, Scope, Tasks, and Files to Modify/Create are populated and stable.** No `[populate me]` placeholders. No "TBD" entries. No in-flight rewrites.
2. **Pre-implementation reviews have passed.** For Mode: design plans, `systems-designer` returned PASS. For plans with a real `prd-ref:` slug, `prd-validity-reviewer` returned PASS. For UI plans, `ux-designer` returned PASS. For all plans (per default), `end-user-advocate` plan-time mode returned PASS or the plan is acceptance-exempt with a substantive reason.
3. **The author has read the plan end-to-end at least once after the final review and is confident it reflects what should be built.** Freeze is a commitment; it should not happen by reflex.
4. **`Status: ACTIVE` is being set or has just been set.** Freeze and `Status: ACTIVE` typically land in the same plan-file edit commit. A frozen plan in `Status: DRAFT` is unusual and should be questioned.

The planner does NOT freeze the plan when:

- Reviews are still pending or have returned FAIL.
- The author is uncertain whether more files will need to enter scope.
- Pre-build investigation surfaced gaps that have not been incorporated into the plan yet.
- The plan is being authored in collaboration with a teammate or stakeholder who has not yet reviewed it.

If in doubt, leave `frozen: false` and continue authoring. The cost of an extra iteration before freeze is small; the cost of a thaw-soon-after-freeze is the audit-trail noise.

## When to thaw

Thawing — flipping `frozen: true` → `frozen: false` — is rare and requires a Decisions Log entry explaining why. Per Decision 016c, the freeze-thaw protocol is:

1. **Flip `frozen: true` → `frozen: false`** in a plan-file edit commit.
2. **Add a Decisions Log entry in the same commit** naming what is changing and why. The entry follows the standard `### Decision: <title>` format with Tier, Status, Chosen, Reasoning fields.
3. **Make the spec amendment** in subsequent commits — add or remove files in `## Files to Modify/Create`, restructure tasks, add a phase, etc.
4. **Re-flip `frozen: false` → `frozen: true`** in a final plan-file edit commit when the spec is again stable.

The Decisions Log entry is the audit artifact. A reviewer reading the plan can see every freeze-thaw cycle and the rationale for each. Repeated thawing without substantive amendment is itself a signal — the spec was incomplete at original freeze, or the author is working off-plan.

Legitimate reasons to thaw:

- A new file dependency surfaced mid-build that was not anticipated and is genuinely in-scope (e.g., a shared utility that the planned files all need; a configuration file that the new feature requires).
- A pre-implementation review surfaced a gap during build (rare — most reviews fire before freeze, but late reviews happen).
- A planned task was decomposed during build, revealing additional files that were absorbed by the original spec at a higher abstraction.
- An external dependency changed (a library API, an upstream service contract) and the spec must adapt.

Illegitimate reasons to thaw (these signal that the spec was not ready for freeze in the first place):

- "I want to refactor an unrelated file while I'm here." That work belongs in a separate plan.
- "The original task list was wrong; let me redo it." Major redo signals the plan should be ABANDONED and re-authored, not thawed.
- "I'm in a hurry and the gate is in my way." Speed pressure is the highest-risk moment for skipping discipline; the gate exists for exactly this case.
- "I'll thaw temporarily, edit one thing, and re-freeze without amending the spec." This bypasses the audit trail; the gate's discipline is about traceable amendment, not just blocked-vs-allowed.

The freeze-thaw protocol's friction is the point. If thawing feels heavy, that's correct — heavy friction discourages casual use. If a plan needs more than two freeze-thaw cycles in its life, that's a signal the original spec was under-developed and the plan should be re-authored.

## The freeze-thaw protocol vs `## In-flight scope updates`

Per Decision 016d, two recovery paths exist for scope drift discovered post-freeze:

- **Light case (one missing file).** Use the `## In-flight scope updates` plan section. Add a line: `- <YYYY-MM-DD>: <file path> — <one-line reason>`. The file becomes in-scope without re-thawing the spec; the gate honors entries in `## In-flight scope updates` alongside `## Files to Modify/Create` (this behavior is shared with `scope-enforcement-gate.sh`).
- **Heavier case (multiple files, restructured tasks, new phase).** Use the freeze-thaw protocol from Decision 016c.
- **Genuinely cross-plan work.** Open a new plan claiming the unrelated work. Do not amend the current plan to cover it; that produces plan-with-multiple-purposes which complicates lifecycle management.

The two mechanisms (in-flight updates vs freeze-thaw) are not interchangeable. In-flight updates are designed for small, incremental additions discovered during build — typically one file at a time, with one-line reasons. Freeze-thaw is designed for substantive scope amendment that warrants a full Decisions Log entry. If you find yourself adding three or four in-flight updates in quick succession, that's the signal to thaw instead — multiple in-flight updates without a thaw indicates the spec was substantially wrong, and the lighter mechanism is being used to avoid the Decisions Log entry the situation actually warrants.

The boundary is judgment-based: one or two in-flight updates with concise reasons is the light case; sustained drift across three or more updates is the heavy case. When in doubt, thaw. The Decisions Log entry forces the planner to articulate what changed and why; that articulation often surfaces deeper questions about whether the plan should be split or re-authored.

## The Mechanism: `spec-freeze-gate.sh`

`spec-freeze-gate.sh` is a PreToolUse `Edit` / `Write` hook. On every Edit or Write tool call, it:

1. Reads `tool_input.file_path` and normalizes to a repo-relative path.
2. Iterates every `Status: ACTIVE` plan in `docs/plans/*.md`. (Plan files in `docs/plans/archive/` are not scanned — archived plans are terminal historical records.)
3. For each plan, parses the `## Files to Modify/Create` section and the `## In-flight scope updates` section into a path list.
4. If `tool_input.file_path` matches any path in the lists AND that plan's header has `frozen: false` or missing, BLOCKS the operation with a message naming the blocking plan and offering the recovery options (flip `frozen: true`, use the in-flight section, or remove the file from the plan's declared list).
5. ALLOWS the operation if no plan claims the file, OR all claiming plans are frozen, OR the file path is itself a plan file (`docs/plans/.*\.md`) — the per-Decision-016e exemption.

The gate degrades to ALLOW (with stderr warning) on any plan-parse error to avoid hook-bug-induced lockout. A maintainer working in an unusual state should not be blocked by a malformed plan they did not author.

The hook's check is fast (typically < 1s for a project with ~10 ACTIVE plans). At higher plan counts, the iteration could become a bottleneck; if observed slowness emerges, the hook can cache the declared-files set in `.claude/state/spec-freeze-cache.json` regenerated on plan-file edit. Out of scope for first implementation.

The hook fires on every Edit and Write — high-volume tools. Its self-test exercises six scenarios (PASS-no-plan-claims, PASS-frozen-plan, FAIL-unfrozen-plan, PASS-multiple-plans-all-frozen, FAIL-multiple-plans-one-unfrozen, PASS-plan-file-itself) plus a regression check against a synthetic ACTIVE plan with all five header fields.

## Recovery from a blocked edit

When `spec-freeze-gate.sh` blocks an Edit, the maintainer reads the message and chooses:

1. **The spec is correct; the edit is in-scope.** Flip `frozen: false` → `frozen: true` in the plan header (commit). Re-attempt the Edit.
2. **The spec is incomplete; one file is missing.** Add a line to `## In-flight scope updates`: `- <YYYY-MM-DD>: <file path> — <reason>`. Commit. Re-attempt the Edit.
3. **The spec is incomplete; multiple files or substantial restructure needed.** Use the freeze-thaw protocol: flip to `frozen: false`, add a Decisions Log entry, amend `## Files to Modify/Create`, flip back to `frozen: true`, commit. Re-attempt.
4. **The file is genuinely out of this plan's scope.** Either remove the path from the plan's `## Files to Modify/Create` (if it was added in error) or open a new plan claiming the work and proceed there.
5. **The Edit was a mistake.** Don't make it. The gate caught a real scope expansion that should not happen.

The block-message names the plan(s) claiming the file and explicitly offers options 1, 2, 3 with concrete next steps. The maintainer does not have to remember the protocol from this rule file at the moment of the block; the message is self-contained.

## Failure modes (and how the harness handles them)

- **Author tries to edit a declared file with `frozen: false`.** Gate BLOCKS. Author flips `frozen: true` (after review) or uses `## In-flight scope updates`.
- **Author flips `frozen: true` without final review.** No mechanical defense; chronic premature-freezing surfaces in routine harness reviews when reviewers see plans that thaw soon after freeze.
- **Author adds a file to `## Files to Modify/Create` while `frozen: true`.** This is the "stealth scope expansion" pattern. The plan-reviewer.sh Check 10 catches plan-header schema issues but does not detect scope diff against a prior freeze. The audit trail is in `git log -p docs/plans/<slug>.md`; reviewers can detect mid-freeze scope additions by reading the diff.
- **Two ACTIVE plans claim the same file.** The gate fires if ANY claiming plan has `frozen: false`. Author either freezes all claiming plans or removes the file from the unfrozen plan's declared list. Multi-claim is itself a signal — usually the plans should be merged or one should ABSORB the other.
- **Plan migrates to `docs/plans/archive/` mid-build (Status flip mistake).** Archived plans are NOT scanned by the gate. If the file is also claimed by an active plan, normal behavior. If only the archived plan claimed the file, the gate ALLOWS the edit (the work is not bound by an active spec). Recovery: restore the plan from archive, re-flip Status, re-attempt.
- **Hook crashes on a malformed plan.** Hook degrades to ALLOW with stderr warning naming the malformed plan. Author fixes the plan; gate resumes normal operation.
- **Author wants to test a hypothesis by editing a file outside any plan first, then deciding whether it belongs in the plan.** Pattern: write the test in a scratch location (a worktree or a separate branch); if it works, add the file to the plan via the freeze-thaw protocol or in-flight updates and copy the work in. The gate's discipline is "no edits to claimed files outside frozen plans," not "no exploration."

## Cross-references

- **Decision record:** `docs/decisions/016-spec-freeze-gate-c2.md` — the five sub-decisions (binary `frozen` field; implicit SHA capture; explicit thaw-with-rationale; recovery via in-flight or freeze-thaw; plan-file exemption).
- **Hook:** `adapters/claude-code/hooks/spec-freeze-gate.sh` — the PreToolUse `Edit` / `Write` mechanism (lands in Phase 1d-C-2 Task 4).
- **Sibling hook:** `adapters/claude-code/hooks/scope-enforcement-gate.sh` — C10's commit-time scope-vs-plan check (already shipped Phase 1d-C-1). C2 catches the start of scope expansion; C10 catches the commit. Both are needed.
- **Plan template:** `adapters/claude-code/templates/plan-template.md` — the plan header includes the `frozen:` field with inline guidance pointing at this rule.
- **Plan-reviewer Check 10:** `adapters/claude-code/hooks/plan-reviewer.sh` — enforces the `frozen:` field is present and is `true` or `false` on `Status: ACTIVE` plans (lands in Phase 1d-C-2 Task 5).
- **Sibling rule:** `adapters/claude-code/rules/prd-validity.md` — Decision 015's PRD-validity gate (C1). C1 ensures the plan claims a product context; C2 ensures the plan freezes its scope before edits begin. Together they prevent two distinct vaporware-shipping patterns at the planning layer.
- **Upstream rule:** `adapters/claude-code/rules/planning.md` — references the `frozen:` plan-header field and points at this rule.
- **Upstream rule:** `adapters/claude-code/rules/orchestrator-pattern.md` — the orchestrator's dispatch protocol assumes the plan is frozen before builders are dispatched. An orchestrator that dispatches a builder against a `frozen: false` plan will see C2 BLOCK every Edit; the orchestrator must freeze first.
- **Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C2 — the original specification.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | When to freeze, when to thaw, the freeze-thaw protocol, the in-flight-vs-thaw distinction | `adapters/claude-code/rules/spec-freeze.md` | landed |
| Template | The `frozen:` field with default `false` and inline guidance | `adapters/claude-code/templates/plan-template.md` | landed (Phase 1d-C-2 Task 1) |
| Hook (`spec-freeze-gate.sh`) | Edits to declared files blocked unless owning plan has `frozen: true` | `adapters/claude-code/hooks/spec-freeze-gate.sh` | landing in Phase 1d-C-2 Task 4 |
| Plan-reviewer Check 10 | `frozen:` field present, value is `true` or `false` | `adapters/claude-code/hooks/plan-reviewer.sh` | landing in Phase 1d-C-2 Task 5 |
| Sibling hook (C10) | Commit-time scope-vs-plan check (catches scope expansion at commit boundary) | `adapters/claude-code/hooks/scope-enforcement-gate.sh` | landed (Phase 1d-C-1) |
| Decision record | The five sub-decisions backing this rule | `docs/decisions/016-spec-freeze-gate-c2.md` | landed (Phase 1d-C-2 Task 1) |

The rule is documentation (Pattern-level). The mechanism stack (gate + plan-reviewer Check 10 + sibling C10) is hook-enforced. Together they close the loop: cannot edit a declared file before the spec is frozen (C2 / this rule); cannot commit a scope-expanding change without updating the plan (C10); cannot author a plan with a malformed `frozen:` field (Check 10).

## Scope

This rule applies in any project whose Claude Code installation has the `spec-freeze-gate.sh` hook wired in `settings.json`. Adoption is per-project: a project opts in by populating its plan headers with the `frozen:` field. A project that has not adopted the discipline will see the gate take no action when files are not claimed by any plan with the field — the gate degrades to ALLOW gracefully.

Neural Lace itself adopts the discipline for all internal harness-development plans. Downstream projects opt in via separate per-project plans (per the rollout sequence — NL adopts the substrate first; downstream projects follow).
