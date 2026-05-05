# Decision 016 — Spec-freeze gate (C2): `frozen: true|false` semantics, freeze-by-commit-SHA, freeze-thaw protocol

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (Status: ACTIVE)
**Related Build Doctrine source:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 C2

## Context

Build Doctrine §6 C2 specifies a spec-freeze gate that prevents builders from editing files declared in a plan's scope until the plan's spec has reached a stable, reviewed shape. The motivation: mid-build spec drift — the builder edits a file, realizes the design needs adjustment, edits the plan to match, edits the file again — produces silent scope expansion that is invisible at session end. Builders effectively re-author the plan as they go. The gate forces a discipline: declare scope explicitly before edits begin, freeze it, and any subsequent change to scope is a deliberate plan amendment rather than an in-flight drift.

C2 is a sibling to C1 (Decision 015) and C10 (`scope-enforcement-gate.sh`, already shipped Phase 1d-C-1). C10 fires at `git commit` time and checks staged-files-vs-plan-bullets; C2 fires at `Edit`/`Write` time and checks file-being-edited-vs-plan-bullets-on-frozen-plans. The two complement each other: C10 catches scope expansion at commit (the latest moment); C2 catches scope expansion the moment it begins (the earliest moment).

The gate's behavior depends on the answers to three questions:

1. **What does "frozen" mean operationally?** Plans evolve continuously; a hard "no edits" rule would be unworkable. The mechanism needs a binary signal that's clear to both author and hook.
2. **How does an author un-freeze a plan when the spec genuinely needs to grow?** Drift discipline is good; rigid impossibility is not.
3. **What is the recovery path when an author realizes mid-build that the spec needs amendment?**

## Decision

### Decision 016a — `frozen: true | false` is a plan-header field

Every plan declares `frozen: true` or `frozen: false` in its header. The default for a new plan is `false`. The spec-freeze gate fires on `Edit`/`Write` operations that target a file listed in any ACTIVE plan's `## Files to Modify/Create` section AND blocks the operation when that plan's `frozen` is `false` (or missing). When `frozen: true`, the gate allows the edit through.

The semantics:

- `frozen: false` — spec is still being authored. The plan cannot govern edits yet (the scope set is still mutable). The gate blocks edits to declared files because there is no committed contract.
- `frozen: true` — spec is settled. The author has reviewed the `## Files to Modify/Create` section and committed to its boundary. Edits proceed; if the plan needs to grow, the author re-opens the plan (Decision 016b).

### Decision 016b — Freeze captures the plan's commit SHA implicitly

When `frozen: true` is set in a plan-file-edit commit, that commit's SHA becomes the implicit freeze point. Future references to "the spec at the time of freeze" resolve to the plan-file content at that SHA. The `spec-freeze-gate.sh` hook does NOT explicitly read the SHA — it reads the current file's `frozen:` field. However, the audit trail (`git log docs/plans/<slug>.md`) shows when freeze happened.

This implicit semantics keeps the hook simple: no SHA-tracking machinery, no parallel state file. If an author wants to know "what was the frozen scope?", `git show <freeze-sha>:docs/plans/<slug>.md` answers it.

### Decision 016c — Thawing requires explicit `frozen: false` flip with rationale recorded in the Decisions Log

When an author needs to amend a frozen spec (add a file, remove a file, restructure tasks), the protocol is:

1. **Flip `frozen: true` → `frozen: false`** in a plan-file edit commit.
2. **Add a Decisions Log entry** in the same commit naming what is changing and why. The entry follows the standard `### Decision: <title>` format with Tier, Status, Chosen, Reasoning fields.
3. **Make the spec amendment** in subsequent commits — add files to `## Files to Modify/Create`, restructure tasks, etc.
4. **Re-flip `frozen: false` → `frozen: true`** in a final plan-file edit commit when the spec is again stable.

The Decisions Log entry from step 2 is the audit artifact: a reviewer reading the plan can see every freeze-thaw cycle and the rationale for each. Repeated thawing without substantive amendment is itself a signal — the spec was incomplete at original freeze, or the author is working off-plan.

### Decision 016d — Recovery from drift discovered post-freeze

When an author discovers, after an edit has been blocked, that the planned scope is genuinely insufficient:

- **Light case (one missing file).** Use the existing `## In-flight scope updates` section (introduced 2026-05-04 per the in-flight-scope-updates discovery). Add `- <YYYY-MM-DD>: <file path> — <one-line reason>` to that section. The file becomes in-scope without re-thawing the spec; the gate honors `## In-flight scope updates` alongside `## Files to Modify/Create` (this behavior is shared with C10 / `scope-enforcement-gate.sh`).
- **Heavier case (multiple files, restructured tasks, new phase).** Use the freeze-thaw protocol from Decision 016c. The thaw signals to reviewers and tooling that the original spec underestimated the work; the Decisions Log entry documents what was missed and how the amendment closes the gap.
- **Genuinely cross-plan work.** Open a new plan claiming the unrelated work. Do not amend the current plan to cover it; that produces plan-with-multiple-purposes which complicates lifecycle management.

### Decision 016e — Plan files themselves are exempt from C2

Plans need to be edited continuously during their active life — to update task checkboxes, append evidence blocks, add Decisions Log entries, append in-flight scope updates. Blocking edits to plan files would create a circular dependency (cannot un-freeze a plan because un-freezing requires editing the plan). The gate excludes `docs/plans/.*\.md` from the file-claim check.

## Alternatives considered

- **Three-state `frozen:` field (`pending | frozen | thawed`).** Rejected — adds complexity without clear benefit; a binary flag with explicit thaw-via-flip captures the same audit trail.
- **Implicit thaw on any plan-file edit.** Rejected — would let any edit silently un-freeze; the explicit flip is what makes the protocol auditable.
- **Freeze-by-explicit-SHA (require an SHA in the header).** Rejected — adds friction (author must know the SHA before flipping); the `git log` trail provides the same information without the field.
- **Per-file freeze granularity (`frozen-files: [list]` in addition to `frozen: bool`).** Rejected — overcomplicates the common case (whole-plan freeze) for a rare edge case (selective freeze). If a project needs per-file freeze, split the plan into separate plans.
- **Block ALL edits when `frozen: false` regardless of file-claim.** Rejected — would block edits to files no plan claims (e.g., refactoring an unrelated component while a plan is open). The file-claim check scopes the gate's blast radius.

## Consequences

**Enables:**
- Spec drift becomes a deliberate, audited action rather than a silent build-time pattern.
- Reviewers can identify "frozen scope" plans confidently — the binary field is parseable by humans and machines.
- The freeze-thaw cycle creates a natural rhythm: spec → freeze → build → un-freeze if needed → re-freeze → build → done.

**Costs:**
- Two additional plan-file edits per freeze-thaw cycle. For plans where mid-build amendment is common, this adds friction — though the friction is the point.
- The implicit SHA-as-freeze-point is convention-only; tooling that wants to display "frozen scope at freeze time" must read the git history. Mitigation: `git log -p docs/plans/<slug>.md` is straightforward; tooling can be added later if needed.

**Blocks:**
- Builders who try to edit a declared file before the plan is frozen will be blocked. Recovery: either freeze the plan (after a final spec review) or remove the file from declared scope. Both are explicit choices, not silent drift.

## Implementation status

Active — to be enforced by `adapters/claude-code/hooks/spec-freeze-gate.sh` (Task 4 of the parent plan).

## Runbook

| Symptom | Diagnostic | Fix |
|---|---|---|
| `spec-freeze-gate.sh` blocks every Edit | Run `bash adapters/claude-code/hooks/spec-freeze-gate.sh --self-test` | If self-test passes, an active plan likely has malformed `## Files to Modify/Create`; check syntax. If self-test fails, file as P1 regression. |
| Edit blocked but plan is `frozen: true` | Verify exact field: `frozen: true` (no quotes, lowercase, single space) | Fix syntax; if syntax is correct, the file path may not match any bullet — review path normalization (forward-slashes on Windows). |
| Plan needs amendment but author can't un-freeze | Check that a Decisions Log entry naming the amendment is included in the same commit as the `frozen: false` flip | Author the entry per Decision 016c; commit both edits together. |
| Multiple plans claim the same file, all but one frozen | Gate blocks because at least one claiming plan is `frozen: false` | Either freeze the unfrozen plan or remove the file from its declared list. The gate fires when ANY claiming plan is unfrozen. |

## Failure modes catalogued

- `FM-NNN unfrozen-spec-edit` — to be added to `docs/failure-modes.md` in Task 10 of the parent plan. Symptom: builder attempts `Edit`/`Write` on a file declared in an unfrozen plan's scope. Detection: PreToolUse hook resolves the file path against every active plan's declared scope. Prevention: freeze the plan first, OR move the file out of declared scope, OR record an in-flight scope update.

## Cross-references

- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — the implementing plan
- `adapters/claude-code/hooks/spec-freeze-gate.sh` — the hook (Task 4)
- `adapters/claude-code/rules/spec-freeze.md` — the rule documenting the freeze-thaw protocol (Task 2)
- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — C10, the sibling commit-time gate (already shipped)
- `docs/discoveries/2026-05-04-in-flight-scope-updates-section-added.md` — the discovery introducing the `## In-flight scope updates` section that the recovery path leverages
- Decision 015 — PRD-validity gate; the upstream sibling that gates plan creation
- Decision 017 — 5-field plan-header schema; `frozen:` is one of the five required fields
