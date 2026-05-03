# Plan: Pre-Submission Audit — Mechanical Enforcement

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-AUDIT-EXT-01, HARNESS-AUDIT-EXT-02
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via hook --self-test invocations and a manual round-trip of an example Mode: design plan through the extended reviewer chain.

## Goal

Close the Pattern-only gap left by commit `9c4e4c8` (which landed the Pre-Submission Class-Sweep Audit rule + 11 FM catalog entries + plan-template addition) by mechanizing the discipline at TWO gates: (1) plan-reviewer.sh refuses Mode: design plans whose `## Pre-Submission Audit` section is missing or placeholder, and detects four common defect classes that the audit was supposed to surface, and (2) the systems-designer agent refuses to review until the audit has been documented. Outcome: a future Mode: design plan cannot reach systems-designer's substance review without the planner having (or at minimum claimed to have) performed the five sweeps. The 8-round → 1-2-round improvement target stated in commit 9c4e4c8's rationale becomes achievable in practice, not just in theory.

## Scope

- IN:
  - `adapters/claude-code/hooks/plan-reviewer.sh` — five new mechanical checks (Check 8 A-E) gated on `Mode: design`
  - `adapters/claude-code/agents/systems-designer.md` — Pre-Submission Audit precondition check before the 10-section review begins
  - Self-test extension in `plan-reviewer.sh --self-test` covering the five new check paths (pass/fail fixtures)
  - Sync from neural-lace adapter directory to `~/.claude/` (manual copy per Windows install convention)
  - `docs/backlog.md` — delete the two absorbed entries (HARNESS-AUDIT-EXT-01 + 02) in the same commit as plan creation, per backlog-plan-atomicity rule
  - `docs/failure-modes.md` — update FM-007 / FM-010 / FM-012 / FM-013 / FM-014 / FM-016 / FM-017 Detection / Prevention fields to cite the new mechanical layer (was previously "planned, not yet implemented")
  - Cross-reference update in `rules/design-mode-planning.md` Enforcement summary table: flip Status of "plan-reviewer.sh extension" and "systems-designer agent precondition" from "planned, not yet implemented" to "landed (commit SHA)"
- OUT:
  - The remaining 4 unmechanized classes (FM-008 stale-existing-code-claim, FM-009 cross-section-contradiction, FM-011 numeric-precision-spec-incomplete, FM-015 numeric-parameter-not-fully-swept). These are content-specific and require either an LLM-driven check or a domain-specific parser; neither fits in a bash hook. Documented as out-of-scope and tracked in the rule's "What this audit doesn't catch" sub-section (added in this plan, see Task 6).
  - A separate `plan-pre-flight-auditor` agent. The two-gate enforcement above (hook + extended systems-designer) is sufficient; an additional agent would duplicate work.
  - Any change to `~/.claude/rules/design-mode-planning.md`'s sweep query specifications. Those landed in 9c4e4c8 and are not changing.

## Tasks

- [ ] 1. Extend `plan-reviewer.sh` with Check 8A (Pre-Submission Audit section presence + substance on Mode: design plans). The check must accept the carve-out "n/a — single-task plan, no class-sweep needed" per the rule's trivial-plan exemption.
- [ ] 2. Extend `plan-reviewer.sh` with Check 8B (deferred-decision detection in Decisions Log: "either/or", "decide later", "OR:" without preceding `Surfaced to user:` annotation → FAIL). Encodes FM-010 prevention.
- [ ] 3. Extend `plan-reviewer.sh` with Check 8C (WARN on "stays identical" / "preserved" / "unchanged" in Tasks section without a colon-delimited enumeration of what's preserved). Encodes FM-012 prevention. WARN-level — does not block.
- [ ] 4. Extend `plan-reviewer.sh` with Check 8D (WARN on comparative phrases — "under X RPM", "well below Y", "comfortably under Z" — in Section 9 of design-mode plans without inline numerics in the same paragraph). Encodes FM-013 + FM-014 prevention. WARN-level.
- [ ] 5. Extend `plan-reviewer.sh` with Check 8E (FAIL on "Add X" / "Modify Y" / "Replace Z" verbs in analysis sections that target a file or component listed in Scope OUT). Encodes FM-016 prevention.
- [ ] 6. Extend `plan-reviewer.sh --self-test` with one pass-case + one fail-case per new check (10 total scenarios). Pass scenarios verify the check approves substantive plans; fail scenarios verify the check blocks (or warns on) the targeted defect.
- [ ] 7. Extend `systems-designer.md` agent prompt with a Pre-Submission Audit precondition: before scoring any of the 10 SEA sections, read the plan's `## Pre-Submission Audit` section. If S1-S5 lines are empty, contain only "[populate me]" / "TODO" / "skipped", return FAIL immediately with a per-sweep gap list. Mode: code plans skip this check.
- [ ] 8. Update `docs/failure-modes.md` Detection / Prevention fields for the seven affected entries (FM-007, FM-010, FM-012, FM-013, FM-014, FM-016, FM-017) to cite the new mechanical layer with commit SHA.
- [ ] 9. Update `rules/design-mode-planning.md` Enforcement summary table: flip the two "planned, not yet implemented" statuses to "landed". Add a new "What this audit doesn't catch" sub-section listing the four unmechanized classes (FM-008/009/011/015) so future planners know which sweeps are still pure-Pattern.
- [ ] 10. Sync changed files from neural-lace adapter directory to `~/.claude/` (per `harness-maintenance.md` Windows manual-sync rule). Verify with the diff loop. Commit, dual-remote push.

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-reviewer.sh` — extend with Checks 8A-E (Tasks 1-5) and self-test scenarios (Task 6). One bash file, ~250 added lines. Each check is a self-contained function so they're individually disable-able if any produces false-positive churn after live use.
- `adapters/claude-code/agents/systems-designer.md` — insert a "## Pre-Submission Audit precondition (read FIRST, before scoring sections)" block at the top of the agent's review procedure (Task 7). ~30 added lines.
- `adapters/claude-code/rules/design-mode-planning.md` — Enforcement summary table status flips + new "What this audit doesn't catch" sub-section (Task 9). ~25 added lines.
- `docs/failure-modes.md` — Detection/Prevention field updates on seven entries (Task 8). ~10 lines edited per entry.
- `docs/backlog.md` — delete HARNESS-AUDIT-EXT-01 + HARNESS-AUDIT-EXT-02 entries (lines 35-80; the parent "Mechanism extensions" header at line 35 stays only if other items remain; otherwise remove the whole block). Performed atomically with plan-file creation per `backlog-plan-atomicity.sh`.

## Assumptions

- The bash regex syntax used by `plan-reviewer.sh`'s existing checks (extended grep with `-nE`) is sufficient for the new checks. Specifically: word-boundary detection for "either/or" tokens, paragraph-context windowing for comparative-phrase + numeric pairing, and Scope OUT bullet extraction for the Scope-vs-analysis cross-check. None of the new checks need a real parser.
- The `## Pre-Submission Audit` section's format established in commit 9c4e4c8 — five lines starting with `S1`, `S2`, `S3`, `S4`, `S5` followed by `(` and a description — is stable and is what the precondition checker keys on. If the format changes later, both the hook AND the agent prompt need updating; this plan does not propose changing the format.
- `systems-designer` agents are invoked with the plan file path as the first argument or via prompt-injected context — the agent can `Read` the plan file from disk to inspect the audit section. (Verified by reading the existing agent prompt: it expects file path inputs.)
- The four remaining unmechanized classes (FM-008, FM-009, FM-011, FM-015) are accepted as "Pattern-only" for now. Further mechanization (e.g., calling out to an LLM-driven sub-check, or building a numeric-parameter-aware mini-parser) is out of scope here and tracked separately.
- `rules/design-mode-planning.md`'s carve-out language ("n/a — single-task plan, no class-sweep needed") is the only acceptable bypass for the audit. Both the hook AND the agent must accept this exact phrasing as a substance-equivalent.

## Edge Cases

- A `Mode: design` plan with all five sweep lines populated but with bodies like "ran sweep, no findings" — accepted by both gates. The discipline is "ran the sweep AND documented the result," not "found zero gaps."
- A plan that mixes `Mode: design` and a substantive `## Pre-Submission Audit` section but where Section 9's comparative-phrase Check 8D fires WARN-level — the plan still advances (WARN doesn't block), but the WARN appears in stderr where the planner sees it.
- A `Mode: code` plan that happens to have a `## Pre-Submission Audit` section (e.g., the planner copied the design-mode template) — the new checks are gated on `Mode: design` so they no-op cleanly. The section's presence in a `Mode: code` plan is harmless.
- A plan with `acceptance-exempt: true` AND `Mode: design` (this very plan would be one if it were design-mode) — the audit gates still apply. The acceptance loop is independent of the design-mode review chain. Documented carve-out only applies to acceptance scenarios, not to the systems-engineering review.
- A plan submitted to `systems-designer` that is `Mode: design` but the Pre-Submission Audit section was added LATER than the rest of the plan (legitimate — planner may run sweeps after the analysis sections are drafted) — the agent still accepts, since the precondition checks substance, not authoring order.
- A multi-task design-mode plan where the Decisions Log contains "either/or" inside a Decision entry that ALREADY carries a `Surfaced to user:` annotation — Check 8B must NOT fire. The annotation IS the legitimate-deferred-with-user-input signal.
- The `--self-test` flag's existing test fixtures must not regress. New scenarios are added; existing ones are unchanged.

## Acceptance Scenarios

(none — see `acceptance-exempt-reason` in the header. This plan has no UI surface to browser-automate. Verification is via `plan-reviewer.sh --self-test` exit codes and a manual replay of the eight-round originating plan through the extended reviewer chain to confirm the audit gate fires correctly.)

## Out-of-scope scenarios

- A plan-pre-flight-auditor agent that would do all 5 sweeps automatically. Considered in the proposal but rejected: two gates (hook + extended agent precondition) provide sufficient mechanical enforcement at lower complexity. An auditor agent would duplicate work without measurable additional coverage.
- Mechanization of FM-008 / FM-009 / FM-011 / FM-015. These need either LLM-driven checks or domain-specific parsers and are tracked separately.

## Testing Strategy

- **Per-check unit tests** via `plan-reviewer.sh --self-test`: each new check (8A-E) gets one synthetic plan that should PASS and one that should FAIL/WARN. The existing self-test framework is extended with these new scenarios; running it produces "all scenarios matched expectations" or names the failing scenario.
- **Integration replay**: take the originating 8-round design-mode plan (its commit-tagged content from neural-lace's recent history), re-run `plan-reviewer.sh` against round-1 / round-2 / round-3 versions, confirm the new checks would have surfaced the documented round-N gaps before that round's `systems-designer` invocation.
- **Negative case**: a clean Mode: code plan exercises Check 8A's gate and confirms it does NOT fire (since `Mode: design` is the trigger).
- **Agent precondition replay**: feed `systems-designer` a synthetic Mode: design plan with an empty `## Pre-Submission Audit` section; confirm the agent returns the canonical FAIL message naming the specific empty sweep lines, NOT a substance review.
- **Sync verification**: after copying changed files to `~/.claude/`, run the diff loop from `harness-maintenance.md` and confirm zero output.

## Walking Skeleton

The thinnest end-to-end slice that exercises the full enforcement chain on one synthetic plan:
1. Build Check 8A (audit-section-presence) only — minimum viable gate
2. Add Mode: design plan fixture with an empty audit section to `--self-test`
3. Run `plan-reviewer.sh --self-test`; confirm the new fail scenario produces exit 1 with a clear message
4. Then iterate: add 8B-E one at a time, then the agent precondition, each with its own self-test scenario.

This validates the hook-extension pattern works before investing in all five checks.

## Decisions Log

(populated during implementation per `~/.claude/templates/decision-log-entry.md`)

## Pre-Submission Audit

n/a — Mode: code plan, no class-sweep needed. (The audit discipline is required for `Mode: design` plans, where the 10-section systems-engineering analysis presents the surface area sweeps must cover. This plan's scope is one bash hook + one agent prompt edit + a docs sweep; no analysis sections exist for sweeps to apply to. Per the carve-out in `rules/design-mode-planning.md` "When the audit doesn't apply".)

## Definition of Done

- [ ] All 10 tasks above are checked by the `task-verifier` agent (per harness rule, only task-verifier flips checkboxes).
- [ ] `plan-reviewer.sh --self-test` exits 0 with all scenarios matching expectations (existing + 10 new).
- [ ] The seven affected `failure-modes.md` entries cite the implementing commit SHA in their Detection / Prevention fields.
- [ ] `~/.claude/` and `~/claude-projects/neural-lace/adapters/claude-code/` show zero diff for the changed files.
- [ ] Backlog items HARNESS-AUDIT-EXT-01 and HARNESS-AUDIT-EXT-02 are deleted from `docs/backlog.md` (atomically with plan-file creation, per backlog-plan-atomicity hook).
- [ ] Completion report appended to this plan file per `~/.claude/templates/completion-report.md`.
