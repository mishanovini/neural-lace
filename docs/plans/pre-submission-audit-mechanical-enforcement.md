# Plan: Pre-Submission Audit — Mechanical Enforcement

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-AUDIT-EXT-01, HARNESS-AUDIT-EXT-02
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via hook --self-test invocations and a manual round-trip of an example Mode: design plan through the extended reviewer chain.
tier: 1
rung: 0
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Close the Pattern-only gap left by commit `9c4e4c8` (which landed the Pre-Submission Class-Sweep Audit rule + 11 FM catalog entries + plan-template addition) by mechanizing the **single audit gate that has cleanly-binding teeth without depending on an unenforced upstream format**: `plan-reviewer.sh` refuses `Mode: design` plans whose `## Pre-Submission Audit` section is missing or placeholder. Outcome: a future Mode: design plan cannot reach `systems-designer`'s substance review without the planner having (or claimed to have via the canonical carve-out) at minimum acknowledged the five sweeps. The 8-round → 1-2-round improvement target requires this floor; it does NOT require 8E/8F today.

**Reformulated twice (2026-05-03)**:

- **Round 1 (REFORMULATE):** original plan included Checks 8B/8C/8D and a systems-designer agent precondition. Reviewer rejected: 8B taught a one-line annotation bypass (worse than no gate); 8C/8D were WARN-on-prose-regex (presumed noise); the agent precondition was ceremony, not friction. Documented in Decisions Log D-1.
- **Round 2 (REFORMULATE):** revised plan added Check 8F (FM-015 mechanization) and Check 8E (Scope OUT cross-check). Reviewer rejected both as `prose-regex-pretending-to-be-mechanism` AND `hook-depends-on-unenforced-upstream-format`: Check 8F's grep cannot map prose digit-tokens to manifest parameter names without either tightening the audit S4 format to `name=value` pairs (with an upstream Check 8F.0 enforcing the format) or accepting WARN-level. Check 8E has the symmetric flaw — its awk extraction assumes a backtick-path format that Scope OUT bullets are not required to use. Both 8E and 8F are deferred (Decisions Log D-3).

**Final scope:** Check 8A only. The other classes stay Pattern-only until either (a) format-enforcement upstream gates land, or (b) an LLM-driven check tooling proves out. The plan ships ONE mechanical gate that genuinely binds, rather than three gates with hidden bypasses.

## Scope

- IN:
  - `adapters/claude-code/hooks/plan-reviewer.sh` — ONE new mechanical check gated on `Mode: design`:
    - **Check 8A** — Pre-Submission Audit section presence + substance (mirrors Check 6b pattern; FAIL on: missing `## Pre-Submission Audit` section, OR section body containing fewer than 5 lines starting with `S1`/`S2`/`S3`/`S4`/`S5`, OR section body whose substantive content is dominated by `[populate me]` / `TODO` / bare `n/a` / bare `skipped` placeholder tokens). Accept exactly one carve-out: the canonical full-sentence exemption `n/a — single-task plan, no class-sweep needed`. FM-007 prevention layer.
  - Self-test extension in `plan-reviewer.sh --self-test` covering the new check (one PASS + three FAIL scenarios = 4 new scenarios: substantive audit; missing section; placeholder-only audit; canonical carve-out accepted).
  - Sync from neural-lace adapter directory to `~/.claude/` (manual copy per Windows install convention).
  - `docs/failure-modes.md` — update FM-007 Detection/Prevention fields to cite Check 8A with commit SHA. Other FM entries unchanged (still Pattern-only or deferred).
  - Cross-reference update in `rules/design-mode-planning.md` Enforcement summary: flip Status of `plan-reviewer.sh extension` from "planned, not yet implemented" to "landed (partial: 8A; 8B/8C/8D/8E/8F and agent precondition deferred — see plan `pre-submission-audit-mechanical-enforcement.md` Decisions Log D-1 and D-3)".
- OUT:
  - **Check 8B** (deferred-decision detection). Reviewer-rejected round 1 — annotation-skip teaches a one-line bypass cheaper than compliance. See D-1.
  - **Check 8C** (stays-identical WARN). Reviewer-rejected round 1 — WARN-on-prose-regex is logging, not enforcement. See D-1.
  - **Check 8D** (comparative-phrase WARN). Reviewer-rejected round 1 — cannot detect missing arithmetic via grep. See D-1.
  - **Check 8E** (Scope OUT cross-check). Reviewer-rejected round 2 — the awk extraction assumes a backtick-path format that Scope OUT bullets are not required to use, AND the verb-target match cannot distinguish "OUT-targeted prescription" from "OUT-mentioned-as-context." Needs format-enforcement upstream (require Scope OUT to use a stable backtick-path format) before this can land. See D-3.
  - **Check 8F** (numeric-parameter sweep manifest). Reviewer-rejected round 2 — `prose-regex-pretending-to-be-mechanism`. The grep cannot reliably map prose digit-tokens to manifest parameter names. Needs either (a) tightened audit S4 format to `name=value` pairs with an upstream Check 8F.0 enforcing the format, or (b) accept WARN-level (and accept that WARN-level is noise per D-1's principle). Both options require updates to `rules/design-mode-planning.md`'s audit format spec, which is out of scope here. See D-3.
  - **Agent precondition** in `systems-designer.md`. Reviewer-rejected round 1 — ceremony, not friction. See D-1.
  - The eight remaining unmechanized classes (FM-008/009/010/011/012/013/014/015/016/017 — note FM-015 and FM-016 also remain Pattern-only after Check 8E/8F deferral). Documented as Pattern-only in the rule's existing Enforcement summary.
  - A separate `plan-pre-flight-auditor` agent.
  - Changes to `~/.claude/rules/design-mode-planning.md`'s sweep query specifications. Those landed in 9c4e4c8 and remain stable.

## Tasks

- [x] 1. Extend `plan-reviewer.sh` with **Check 8A** (Pre-Submission Audit section presence + substance on Mode: design plans). Implementation: gate on `MODE_VALUE == "design"`. Required-section lookup using the existing `check_required_section`-style awk + body-extraction. FAIL conditions:
    - Section heading `## Pre-Submission Audit` is missing
    - Section body, after stripping HTML comments and bullet markers, is empty or under 30 non-whitespace chars
    - Section body, after stripping placeholder tokens (`[populate me]`, `TODO`, bare `n/a`, bare `skipped`), is empty
    - Section body does NOT contain at least one of: (a) the canonical full-sentence carve-out `n/a — single-task plan, no class-sweep needed`, OR (b) at least 5 lines that begin with `S1` / `S2` / `S3` / `S4` / `S5` (one per sweep, in any order, optionally bullet-prefixed)
- [x] 2. Extend `plan-reviewer.sh --self-test` with 4 new fixture scenarios:
    - **PASS:** Mode: design plan with 5 substantive sweep lines (each cites a sweep query + a count or finding); confirm exit 0
    - **PASS-carve-out:** Mode: design plan whose `## Pre-Submission Audit` section contains only the canonical full-sentence carve-out; confirm exit 0
    - **FAIL-missing:** Mode: design plan with NO `## Pre-Submission Audit` section; confirm exit 1 + finding cites missing section
    - **FAIL-placeholder:** Mode: design plan whose audit body is `[populate me]` only; confirm exit 1 + finding cites placeholder content
- [x] 3. Update `docs/failure-modes.md` FM-007 Detection / Prevention fields to cite Check 8A with the implementing commit SHA. Other FM entries unchanged.
- [x] 4. Update `rules/design-mode-planning.md` Enforcement summary listing: flip `plan-reviewer.sh extension` Status from "planned, not yet implemented" to a partial-landed status. Cite this plan's commit SHA. Document explicitly that 8A is the only mechanized check; 8B/8C/8D/8E/8F and agent precondition are deferred per D-1 and D-3.
- [ ] 5. Sync changed files from neural-lace adapter directory to `~/.claude/` per `harness-maintenance.md` Windows manual-sync rule. Verify with the diff loop. Commit, dual-remote push.

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-reviewer.sh` — extend with Check 8A and self-test scenarios. ~80 added lines. Single self-contained function `check_pre_submission_audit_8a()` callable conditionally on `MODE_VALUE == "design"`.
- `docs/failure-modes.md` — Detection/Prevention field update on FM-007 only (cite Check 8A with implementing commit SHA). ~5 lines edited.
- `adapters/claude-code/rules/design-mode-planning.md` — Enforcement summary table status update. ~10 added lines documenting that S1 is mechanized via Check 8A and S2-S5 remain Pattern-only with explicit links to D-1 and D-3 for the deferral reasoning.
- `~/.claude/hooks/plan-reviewer.sh`, `~/.claude/rules/design-mode-planning.md` — copies synced from the adapter directory after Task 4 completes. The `~/.claude/docs/failure-modes.md` file does not currently exist locally — sync also creates it as part of the harness-maintenance discipline (the diagnosis rule references it).

## In-flight scope updates

- 2026-05-05: `docs/plans/pre-submission-audit-mechanical-enforcement.md` — bookkeeping recovery: original Phase 1d-C-2 session built Check 8A in commit `10adac2` (May 3) but ended without running task-verifier; this session recovers the audit trail (Tasks 1-5 evidence + checkbox flips + Status: COMPLETED).
- 2026-05-05: `docs/plans/pre-submission-audit-mechanical-enforcement-evidence.md` — evidence file companion to the plan, never committed by the original session; landed during this recovery session via task-verifier dispatches.

## Assumptions

- The bash regex syntax and awk-based body extraction used by `plan-reviewer.sh`'s existing checks (notably `check_required_section`'s pattern at lines 357-416) are sufficient for Check 8A. Section-presence + substance-via-non-whitespace-char-count + placeholder-token stripping is the same shape Check 6b uses today.
- The `## Pre-Submission Audit` section's format established in commit 9c4e4c8 — five lines starting with `S1`, `S2`, `S3`, `S4`, `S5` followed by `(` and a description — is stable and is what the precondition checker keys on. If the format changes later, both the hook AND the agent prompt need updating; this plan does not propose changing the format.
- `systems-designer` agents are invoked with the plan file path as the first argument or via prompt-injected context — the agent can `Read` the plan file from disk to inspect the audit section. (Verified by reading the existing agent prompt: it expects file path inputs.)
- The four remaining unmechanized classes (FM-008, FM-009, FM-011, FM-015) are accepted as "Pattern-only" for now. Further mechanization (e.g., calling out to an LLM-driven sub-check, or building a numeric-parameter-aware mini-parser) is out of scope here and tracked separately.
- `rules/design-mode-planning.md`'s carve-out language ("n/a — single-task plan, no class-sweep needed") is the only acceptable bypass for the audit. Both the hook AND the agent must accept this exact phrasing as a substance-equivalent.

## Edge Cases

- A `Mode: design` plan with all five sweep lines populated but with bodies like "ran sweep, no findings" — accepted by Check 8A. The discipline 8A enforces is "documented all five sweeps OR explicitly carved out," not "found zero gaps." Whether the documented sweep was actually run is a separate question that would need different mechanization (out of scope here per D-3).
- A `Mode: code` plan that happens to have a `## Pre-Submission Audit` section (e.g., the planner copied the design-mode template) — Check 8A is gated on `MODE_VALUE == "design"` so it no-ops cleanly. The section's presence in a `Mode: code` plan is harmless and doesn't trigger the new gate.
- A plan with `acceptance-exempt: true` AND `Mode: design` — Check 8A still applies. The acceptance loop is independent of the design-mode review chain; `acceptance-exempt: true` only bypasses the runtime acceptance gate, not the systems-engineering pre-submission audit.
- A plan submitted to `systems-designer` that is `Mode: design` but the `## Pre-Submission Audit` section was added LATER than the rest of the plan — Check 8A still accepts, since presence + substance is checked at any point, not gated on authoring order.
- The canonical full-sentence carve-out (`n/a — single-task plan, no class-sweep needed`) must match exactly. A planner who writes `n/a` alone, or `n/a, single-task` (different punctuation), or paraphrases the sentence, FAILs Check 8A. This is intentional — the canonical phrase is the explicit acknowledgment that the planner has read the rule's "When the audit doesn't apply" sub-section and is choosing the carve-out deliberately.
- The `--self-test` flag's existing test fixtures must not regress. New scenarios are added; existing ones are unchanged.

## Acceptance Scenarios

(none — see `acceptance-exempt-reason` in the header. This plan has no UI surface to browser-automate. Verification is via `plan-reviewer.sh --self-test` exit codes and a manual replay of the eight-round originating plan through the extended reviewer chain to confirm the audit gate fires correctly.)

## Out-of-scope scenarios

- A plan-pre-flight-auditor agent that would do all 5 sweeps automatically. Considered in the proposal but rejected: two gates (hook + extended agent precondition) provide sufficient mechanical enforcement at lower complexity. An auditor agent would duplicate work without measurable additional coverage.
- Mechanization of FM-008 / FM-009 / FM-011 / FM-015. These need either LLM-driven checks or domain-specific parsers and are tracked separately.

## Testing Strategy

- **Check 8A unit tests** via `plan-reviewer.sh --self-test`: 4 new fixture scenarios (PASS-substantive, PASS-carve-out, FAIL-missing, FAIL-placeholder) plus the existing 4 scenarios = 8 total. Running `--self-test` produces "all scenarios matched expectations" or names the failing scenario.
- **Negative case (Mode: code)**: a clean Mode: code plan exercises Check 8A's gate and confirms it does NOT fire (since `MODE_VALUE == "design"` is the trigger). Already covered by the existing self-test fixture-a (Mode: code) which must continue to PASS.
- **Sync verification**: after copying changed files to `~/.claude/`, run the diff loop from `harness-maintenance.md` and confirm zero output across `hooks/plan-reviewer.sh`, `rules/design-mode-planning.md`, and the new `~/.claude/docs/failure-modes.md`.

## Walking Skeleton

n/a — single mechanical check. The plan IS the skeleton: implement Check 8A, exercise via `--self-test`, sync to `~/.claude/`, ship.

## Decisions Log

### D-1: Drop Checks 8B / 8C / 8D + the systems-designer agent precondition (2026-05-03)

- **Tier:** 2
- **Status:** proceeded with reviewer recommendation
- **Chosen:** Reduce scope from 5 hook checks + 1 agent precondition to 3 hook checks (8A + 8E + 8F). Drop 8B (deferred-decision detection), 8C (stays-identical WARN), 8D (comparative-phrase WARN), and the systems-designer agent precondition.
- **Alternatives considered:**
  - Land all 5 checks + agent precondition as originally drafted. Rejected by `harness-reviewer` (round 1, REFORMULATE verdict): 8B teaches a one-line bypass (`Surfaced to user: <date>` annotation) that is cheaper than honest compliance, making the gate WORSE than the current Pattern-only state. 8C and 8D are WARN-level on prose-regex, where the harness's existing experience (Check 4b WARN behavior) shows WARN-level findings get ignored. The agent precondition is ceremony-not-mechanism — typing five fake `S<N>: swept, 0 matches` lines is 4 seconds and indistinguishable from real work.
  - Redesign the agent precondition to have systems-designer independently run at least one sweep query and compare the documented match-count to actual. Considered, but: (a) non-trivial complexity for an agent prompt, (b) requires the agent to make a judgment call on "plausibility," (c) the right answer is probably a separate hook that mechanically verifies sweep counts before submission, which is its own design problem. Deferred to a follow-up plan if Mode: design plans still slip through Check 8A with empty-but-formatted audit sections.
- **Reasoning:** the harness has an explicit anti-pattern in `docs/harness-review-audit-questions.md`: a Mechanism whose bypass cost equals or undercuts compliance cost is harness bloat, not improvement. 8B's annotation-skip falls in that category. 8C/8D are noise. The agent precondition is ceremony. Landing them would dilute the catalog and create "gate that fires but doesn't bind" patterns that erode trust in the rest of the harness. Better to land the three checks that DO have teeth (8A, 8E, 8F) and accept that FM-008/009/010/011/012/013/014/017 stay Pattern-only until evidence shows a specific mechanization design works.
- **Checkpoint:** plan revision committed at <SHA TBD via Task 7 commit>.
- **To reverse:** restore the deleted Tasks 2/3/4/7 from this plan's git history (commit immediately before the reformulation), re-apply to plan-reviewer.sh and systems-designer.md. Cost ~30 minutes; the original plan revision is preserved in git history.

### D-2: FM-015 promoted to in-scope as Check 8F — REVERSED in D-3 (2026-05-03)

- **Tier:** 2
- **Status:** SUPERSEDED by D-3 below. Originally adopted from harness-reviewer round 1 recommendation; reversed in round 2 after the same reviewer flagged Check 8F's design as `prose-regex-pretending-to-be-mechanism`.
- This entry is preserved as part of the audit trail; the substantive choice is documented in D-3.

### D-3: Drop Check 8E and Check 8F (defer with format-enforcement prerequisite) (2026-05-03)

- **Tier:** 2
- **Status:** proceeded with reviewer round-2 recommendation
- **Chosen:** Reduce in-scope checks from {8A, 8E, 8F} to {8A only}. Defer 8E and 8F until the rule-level format requirements they depend on are themselves enforced upstream.
- **Alternatives considered:**
  - Tighten audit S4 format to `swept for params [name=value, name=value, ...]` AND tighten Scope OUT format to require backtick-delimited paths AND add upstream Check 8F.0 enforcing the audit format AND add upstream Check 8E.0 enforcing the Scope OUT format. Rejected: scope creep — the original plan's IN-scope explicitly excluded changes to `~/.claude/rules/design-mode-planning.md`'s sweep query specifications. Tightening the formats requires updating the rule, which then propagates to every Mode: design plan author. That's a large enough change to warrant its own plan with its own systems-designer review.
  - Demote 8E and 8F to WARN-level. Rejected by D-1's principle: WARN-on-prose-regex is noise, not enforcement; the harness has explicit precedent (Check 4b) showing WARN-level findings get ignored.
- **Reasoning:** the reviewer's `prose-regex-pretending-to-be-mechanism` finding applies to BOTH 8E and 8F. Both depend on plan-section formats (Scope OUT bullet format for 8E; audit S4 manifest format for 8F) that the rule recommends but does not enforce. A check whose correctness depends on an unenforced upstream format is fragile: planners can satisfy the format inconsistently, the hook silently fires false-positives or false-negatives, and trust in the gate erodes. The honest path is to ship Check 8A alone (which has no upstream format dependency — it gates on section presence and explicit substance markers) and defer 8E/8F until the format question is resolved properly.
- **Consequence:** Check 8A is the only mechanical layer landing in this plan. FM-007 cites it; FM-008/009/010/011/012/013/014/015/016/017 stay Pattern-only. The originally-promised "8-round → 1-2-round" outcome will require additional mechanization once the format-enforcement design lands; this plan establishes the floor, not the ceiling.
- **Checkpoint:** plan revision committed at <SHA TBD via Task 5 commit>.
- **To reverse / promote 8E / 8F later:** create a follow-up plan that (a) updates `rules/design-mode-planning.md` to require canonical `name=value` audit S4 format and backtick-path Scope OUT format, (b) adds Check 8F.0 / 8E.0 enforcing those formats, (c) re-implements the original Check 8E / 8F against the now-enforced formats. The work is straightforward once the format question is settled.

## Pre-Submission Audit

n/a — Mode: code plan, no class-sweep needed. (The audit discipline is required for `Mode: design` plans, where the 10-section systems-engineering analysis presents the surface area sweeps must cover. This plan's scope is one bash hook + one agent prompt edit + a docs sweep; no analysis sections exist for sweeps to apply to. Per the carve-out in `rules/design-mode-planning.md` "When the audit doesn't apply".)

## Definition of Done

- [ ] All 5 tasks above are checked by the `task-verifier` agent (per harness rule, only task-verifier flips checkboxes).
- [ ] `plan-reviewer.sh --self-test` exits 0; the 4 existing scenarios plus 4 new Check-8A scenarios (8 total) each report the expected verdict.
- [ ] FM-007 cites Check 8A's implementing commit SHA. FM-015 and FM-016 stay Pattern-only (deferred per D-3) with text reflecting the deferral.
- [ ] `~/.claude/` and `~/claude-projects/neural-lace/adapters/claude-code/` show zero diff for the changed files (plan-reviewer.sh, design-mode-planning.md), and `~/.claude/docs/failure-modes.md` exists as a copy of the neural-lace `docs/failure-modes.md`.
- [ ] Backlog items HARNESS-AUDIT-EXT-01 and HARNESS-AUDIT-EXT-02 are deleted from `docs/backlog.md` (already done atomically with the initial plan-file creation commit `428dbef`, per backlog-plan-atomicity hook).
- [ ] Completion report appended to this plan file per `~/.claude/templates/completion-report.md`.
