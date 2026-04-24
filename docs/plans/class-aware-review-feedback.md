# Plan: Class-Aware Reviewer Feedback — Mod 1 + Mod 3 of the Narrow-Fix-Bias Mitigation

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: "Class-aware reviewer feedback (narrow-fix bias mitigation)" — Mods 1 and 3 only; Mod 2 (pre-commit class-sweep attestation hook) deferred to standalone backlog entry pending evidence Mods 1+3 are insufficient.

## Goal

Close the narrow-fix-bias pattern observed across 6 `systems-designer` iterations on the `capture-codify-pr-template` plan (2026-04-23): adversarial reviewers name specific defects; LLM builders fix the named defects; sibling instances of the same defect class slip; the next pass surfaces a sibling; loop. Each pass closes real gaps but each fix introduces narrower follow-ons, leading to non-converging review loops.

This plan ships two prose-layer interventions:

1. **Mod 1 (reviewer agent updates):** modify all adversarial-review agents (`systems-designer`, `harness-reviewer`, `code-reviewer`, `security-reviewer`, `ux-designer`, `claim-reviewer`, `plan-evidence-reviewer`) to require a `Class:` + `Sweep query:` + `Required generalization:` field per identified gap. This shifts ~5% of the reviewer's effort to defect classification and gives the builder the sweep query upfront.

2. **Mod 3 (rule update):** add a "Fix the Class, Not the Instance" sub-rule to `rules/diagnosis.md` under the existing "After Every Failure: Encode the Fix" section. Documents the discipline so it's discoverable when a builder reads `diagnosis.md` mid-session.

The user-observable outcome: the next adversarial-review loop in the harness (e.g., `systems-designer` on plan #6) emits class-aware feedback, and the responding builder does the class sweep on the first amendment rather than iterating 5+ times to surface sibling instances.

Mod 2 (pre-commit class-sweep attestation hook) is explicitly OUT of scope and remains in the backlog — see [backlog entry](../backlog.md). It's the mechanical backstop reserved for the case where Mods 1+3 prove insufficient.

## Scope

### IN

- Update `adapters/claude-code/agents/systems-designer.md` — add the required output format with `Class:`, `Sweep query:`, `Required generalization:` fields per gap. Mirror to `~/.claude/agents/systems-designer.md`.
- Update `adapters/claude-code/agents/harness-reviewer.md` — same. Mirror.
- Update `adapters/claude-code/agents/code-reviewer.md` — same. Mirror.
- Update `adapters/claude-code/agents/security-reviewer.md` — same. Mirror.
- Update `adapters/claude-code/agents/ux-designer.md` — same. Mirror.
- Update `adapters/claude-code/agents/claim-reviewer.md` — same. Mirror.
- Update `adapters/claude-code/agents/plan-evidence-reviewer.md` — same. Mirror.
- Update `adapters/claude-code/rules/diagnosis.md` — add "Fix the Class, Not the Instance" sub-rule. Mirror to `~/.claude/rules/diagnosis.md`.
- Update `adapters/claude-code/docs/harness-architecture.md` — note the class-aware feedback contract in the agents inventory.
- Verify each modification with the harness-maintenance diff loop (zero `MISSING` or `DIFFERS` output).

### OUT

- Mod 2 (pre-commit `class-sweep-attestation.sh` hook) — deferred to backlog as a standalone P1 entry. Reason: prose-layer interventions (Mods 1+3) are believed sufficient based on the strategy-doc principle "prose as guidance, hooks as physics" — start with prose, add hook only if pattern persists.
- Modifying the future `end-user-advocate` agent (created by plan #6) — that plan will adopt the class-aware format from the start because it ships AFTER this plan in the queue (per reorganization).
- Reviewer agents not in the standard adversarial-review set (e.g., `Plan`, `explorer`, `research`, `Explore`) — these are exploratory/planning agents, not adversarial reviewers. Out of scope.
- Retroactive review of plans already passed by reviewers under the old format. Plan #3 is already PASS-with-nit; no retroactive re-review.
- Changes to the orchestrator's response patterns — the orchestrator (main session) doesn't need new instructions; it just consumes the new richer reviewer output naturally.

## Tasks

- [ ] 1. Update `adapters/claude-code/agents/systems-designer.md` with the required output format. Add a new section "Output Format Requirements" specifying that for each identified gap, the agent must include: `Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`. Provide a worked example. Mirror to `~/.claude/agents/systems-designer.md`. Diff verification.
- [ ] 2. Update `adapters/claude-code/agents/harness-reviewer.md` with the same output format requirement. Mirror + diff.
- [ ] 3. Update `adapters/claude-code/agents/code-reviewer.md` with the same. Mirror + diff.
- [ ] 4. Update `adapters/claude-code/agents/security-reviewer.md` with the same. Mirror + diff.
- [ ] 5. Update `adapters/claude-code/agents/ux-designer.md` with the same. Mirror + diff.
- [ ] 6. Update `adapters/claude-code/agents/claim-reviewer.md` with the same. Mirror + diff.
- [ ] 7. Update `adapters/claude-code/agents/plan-evidence-reviewer.md` with the same. Mirror + diff.
- [ ] 8. Add "Fix the Class, Not the Instance" sub-rule to `adapters/claude-code/rules/diagnosis.md` under the existing "After Every Failure: Encode the Fix" section. The sub-rule says: "When a reviewer (or any feedback source) flags a defect at a specific location, the fix is not done until you have searched the entire artifact for sibling instances of the same defect class. Document the search in the fix commit (e.g., `Class-sweep: <grep pattern> — N matches, M fixed`). The named instance is one example of the class; the class is what gets fixed." Mirror to `~/.claude/rules/diagnosis.md`. Diff verification.
- [ ] 9. Update `adapters/claude-code/docs/harness-architecture.md` to note the new contract: in the agents inventory section, add a one-line entry under each modified agent referencing the class-aware feedback format. Mirror to `~/.claude/docs/harness-architecture.md`. Diff verification.
- [ ] 10. End-to-end smoke test: invoke the modified `systems-designer` agent on a deliberately-flawed test plan (a small throwaway with one obvious defect that has 3 sibling instances in the same file). Verify the agent's output now includes `Class:` + `Sweep query:` + `Required generalization:` fields, and the sweep query if executed actually surfaces the 3 siblings. Document evidence in `docs/plans/class-aware-review-feedback-evidence.md`.

## Files to Modify/Create

### Modify (in `~/.claude/` AND mirrored to `adapters/claude-code/`)

- `agents/systems-designer.md`
- `agents/harness-reviewer.md`
- `agents/code-reviewer.md`
- `agents/security-reviewer.md`
- `agents/ux-designer.md`
- `agents/claim-reviewer.md`
- `agents/plan-evidence-reviewer.md`
- `rules/diagnosis.md`
- `docs/harness-architecture.md`

### Create

- `docs/plans/class-aware-review-feedback-evidence.md` — Task 10 smoke-test evidence

### Modify (one-off)

- `docs/backlog.md` — Mod 1 + Mod 3 absorption (deletion of bundled entry; standalone Mod 2 entry already filed)

## Assumptions

- All seven adversarial-review agents have similar prompt structures (intro persona + review instructions + output format guidance). Adding an "Output Format Requirements" section to each is mechanically similar.
- Reviewers don't have hard-coded output schemas in code — their output format is purely prompt-driven. Verified by reading `~/.claude/agents/systems-designer.md` (no schema enforcement at the harness level; output is free-form).
- Existing reviewer outputs across the harness consume free-form text, not structured fields. No downstream parsers will break when the format changes.
- `harness-reviewer` agent will not be invoked on this plan's commits (it's not a design-mode plan; not editing CI/CD or migrations). The plan is Mode: code and self-applied for reviewer-prompt edits.
- The smoke test in Task 10 can use a temporary plan file that's deleted after verification — not committed to `docs/plans/`.
- "Adversarial reviewer" is the right scope. Excluded agents (`Plan`, `explorer`, `research`, `Explore`, `task-verifier`, `test-writer`, `statusline-setup`) are not adversarial reviewers and don't produce defect-list outputs.
- Mod 1 alone (without Mod 2) will measurably reduce the narrow-fix iteration pattern. Validation: the next adversarial-review loop after this plan ships should converge in fewer iterations than the 6-iteration plan #3 review.

## Edge Cases

- **A reviewer agent's existing prompt has its own output format guidance that conflicts with the new requirement.** Resolution: the new "Output Format Requirements" section takes precedence; existing guidance is updated to align or removed if redundant.
- **Some reviewers identify gaps that genuinely have no class** (e.g., a one-off typo). Resolution: the agent is allowed to declare `Class: instance-only` with a one-line justification. Documented in the new section.
- **`harness-reviewer` is itself one of the agents being modified.** Resolution: bootstrap exemption. The first version of this plan's `harness-reviewer.md` update is reviewed by a fresh `harness-reviewer` invocation on the next plan that uses it; this plan's update of `harness-reviewer.md` is self-applied without a meta-review (would be infinite recursion otherwise).
- **A reviewer's existing `Sweep query:` would be expensive to compute** (large codebase). Resolution: agents are instructed to provide the BEST query they can given available tools, not necessarily the most efficient. Builder runs the query themselves; if too slow, refines.
- **Diff loop for harness-maintenance produces non-zero output for an unrelated reason.** Resolution: investigate; if a previous session left drift, fix that drift in the same commit (per harness-maintenance rule).
- **Smoke test reveals the class-aware format isn't being followed reliably.** Resolution: tighten the agent prompt language ("MUST include" vs "should include"); add a required-format example. If still unreliable after one tightening pass, that's the signal to ship Mod 2 mechanically.

## Testing Strategy

- **Per-agent (Tasks 1-7):** after each agent file edit, grep the file for the required field names (`Class:`, `Sweep query:`, `Required generalization:`) — all three must be present. Diff-verify the `~/.claude/` mirror is byte-identical to the `adapters/claude-code/` source.
- **Rule update (Task 8):** grep `~/.claude/rules/diagnosis.md` for "Fix the Class, Not the Instance" — must return ≥ 1 match. Diff-verify mirror.
- **Architecture doc (Task 9):** grep `adapters/claude-code/docs/harness-architecture.md` for "class-aware feedback" — must return ≥ 1 match per modified agent.
- **Smoke test (Task 10):** create a throwaway test plan with 4 instances of an obvious defect class (e.g., 4 functions all missing the same auth check). Invoke `systems-designer` via Task tool. Read the agent's output. Assertions: (a) at least one `Class:` field present, (b) at least one `Sweep query:` field present, (c) the sweep query when executed via `grep` against the test plan returns ≥ 4 matches (proves the class is identified, not just the named instance). Document grep results + agent output snippet in evidence file.
- **No test-skip escape hatches** per `no-test-skip-gate.sh`. Smoke test must produce concrete output before Task 10 verifies.

## Decisions Log

*Populated during implementation.*

## Definition of Done

- [ ] All 10 tasks checked off via `task-verifier` (or evidence-first protocol if Task tool is unavailable in builder dispatch — see plan #5 Phase A's solution path)
- [ ] All 7 reviewer agent files updated and mirrored byte-identical
- [ ] `rules/diagnosis.md` updated with "Fix the Class, Not the Instance" sub-rule and mirrored
- [ ] `docs/harness-architecture.md` updated with class-aware feedback notes for each modified agent and mirrored
- [ ] Smoke test evidence file exists at `docs/plans/class-aware-review-feedback-evidence.md` showing the agent output now includes the new fields
- [ ] SCRATCHPAD.md updated with completion state
- [ ] Completion report appended to this plan file per `templates/completion-report.md`, including the Backlog items shipped subsection (Mods 1+3 status)
- [ ] No decision records required — this is Mode: code; all decisions are Tier 1 (reversible prompt edits)
