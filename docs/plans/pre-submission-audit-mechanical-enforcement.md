# Plan: Pre-Submission Audit — Mechanical Enforcement

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-AUDIT-EXT-01, HARNESS-AUDIT-EXT-02
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via hook --self-test invocations and a manual round-trip of an example Mode: design plan through the extended reviewer chain.

## Goal

Close the Pattern-only gap left by commit `9c4e4c8` (which landed the Pre-Submission Class-Sweep Audit rule + 11 FM catalog entries + plan-template addition) by mechanizing the audit at the **single load-bearing gate** that has real friction: `plan-reviewer.sh` refuses `Mode: design` plans whose `## Pre-Submission Audit` section is missing or placeholder, and refuses plans whose analysis sections prescribe work targeting Scope OUT items, and refuses plans whose capacity-section numeric parameters appear inconsistently across sibling references. Outcome: a future Mode: design plan cannot reach `systems-designer`'s substance review without the planner having (or claimed to have) performed at minimum sweeps S1, S4, and S5. The 8-round → 1-2-round improvement target becomes mechanically supported, not just culturally aspirational.

**Reformulated 2026-05-03 from harness-reviewer feedback** (verdict REFORMULATE on initial draft) — the original plan included three checks (8B, 8C, 8D) that were either prose-regex with high false-positive rate or that taught a one-line bypass that was cheaper than compliance. Those are now out of scope (logged in Decisions Log entry D-1). FM-015 was promoted from out-of-scope to in-scope as Check 8F per reviewer's "cheap-and-high-value" classification. The systems-designer agent precondition (originally Task 7) was dropped as ceremony-not-mechanism — an agent reading "S1: swept, 0 matches" cannot distinguish real from faked work.

## Scope

- IN:
  - `adapters/claude-code/hooks/plan-reviewer.sh` — three new mechanical checks gated on `Mode: design`:
    - **Check 8A** — Pre-Submission Audit section presence + substance (mirrors Check 6b pattern; FAIL on missing section, placeholder-only, or fewer than 5 substantive sweep lines for design-mode plans). Carve-out for the canonical exemption phrase `n/a — single-task plan, no class-sweep needed` (FM-007 prevention).
    - **Check 8E** — `Add X` / `Modify Y` / `Replace Z` / `prescribes` / `requires.*to` verbs in analysis sections (Sections 1-10) cross-checked against Scope OUT bullets. FAIL when a verb prescribes work targeting a file path or component listed in Scope OUT (FM-016 prevention).
    - **Check 8F** — numeric-parameter sweep manifest validation. Plan's audit S4 line must enumerate which numeric parameters were swept; check then greps Section 9 (Load/capacity) for digit-tokens (≥ 3 chars, with capacity-context tokens like RPM/ITPM/threads/calls/batch/cap/max/timeout) and FAILs when any such token does not appear in the sweep manifest (FM-015 prevention).
  - Self-test extension in `plan-reviewer.sh --self-test` covering the three new check paths (one PASS + one FAIL scenario per check = 6 new scenarios).
  - Sync from neural-lace adapter directory to `~/.claude/` (manual copy per Windows install convention).
  - `docs/failure-modes.md` — update FM-007, FM-015, FM-016 Detection/Prevention fields to cite the new mechanical layer with commit SHA. The remaining FM entries (FM-008, FM-009, FM-010, FM-011, FM-012, FM-013, FM-014, FM-017) stay Pattern-only.
  - Cross-reference update in `rules/design-mode-planning.md` Enforcement summary: flip Status of `plan-reviewer.sh extension` from "planned, not yet implemented" to "landed (partial: 8A + 8E + 8F; 8B/8C/8D and agent precondition deferred — see plan `pre-submission-audit-mechanical-enforcement.md` Decisions Log)".
- OUT:
  - **Check 8B** (deferred-decision detection in Decisions Log via "either/or" / "OR:" regex with `Surfaced to user:` annotation skip). Reviewer-rejected: the annotation-skip logic teaches a one-line bypass that is cheaper than compliance, making the gate WORSE than the current Pattern-only state. See Decisions Log D-1.
  - **Check 8C** (WARN on "stays identical" / "preserved" / "unchanged" without enumeration). Reviewer-rejected: WARN-level on loose prose-regex is logging, not enforcement; the Pattern-rule in `design-mode-planning.md` already covers this and a WARN-level mechanism doesn't add force. See Decisions Log D-1.
  - **Check 8D** (WARN on comparative phrases without inline numerics). Reviewer-rejected: cannot mechanically detect missing arithmetic via grep. The originating FM-013/FM-014 failures need either an LLM-driven check or a math-extraction parser. See Decisions Log D-1.
  - **Agent precondition** in `systems-designer.md` (originally Task 7). Reviewer-rejected: trust-on-substance precondition is ceremony, not friction — bypass cost = 4 seconds typing five fake sweep lines. Either redundant with Check 8A or requires a non-trivial redesign (agent independently runs at least one sweep query and compares documented count to actual). Redesign is out of scope here. See Decisions Log D-1.
  - The remaining unmechanized classes (FM-008 stale-existing-code-claim, FM-009 cross-section-contradiction, FM-011 numeric-precision-spec-incomplete, FM-012 stays-identical-without-enumeration, FM-013 capacity-claim-without-arithmetic, FM-014 capacity-claim-self-contradicts-math, FM-017 cold-start-violates-steady-state-envelope, FM-010 deferred-design-decision-with-interface-impact). These are content-specific and require either an LLM-driven check, a domain-specific parser, or a redesign of the agent precondition mechanism. Documented as Pattern-only in the rule's existing Enforcement summary.
  - A separate `plan-pre-flight-auditor` agent. The single-gate enforcement (Check 8A + 8E + 8F) is sufficient for the highest-leverage classes; an additional agent would duplicate work.
  - Any change to `~/.claude/rules/design-mode-planning.md`'s sweep query specifications. Those landed in 9c4e4c8 and are not changing.

## Tasks

- [ ] 1. Extend `plan-reviewer.sh` with **Check 8A** (Pre-Submission Audit section presence + substance on Mode: design plans). FAIL on missing `## Pre-Submission Audit` section, on a section with fewer than 5 lines starting with `S1`/`S2`/`S3`/`S4`/`S5`, or on a section whose body is dominated by `[populate me]` / `TODO` / `skipped` / `n/a` placeholder tokens (single-token bypass). Accept the canonical full-sentence carve-out `n/a — single-task plan, no class-sweep needed` (full string match).
- [ ] 2. Extend `plan-reviewer.sh` with **Check 8E** (Scope-OUT-vs-analysis cross-check). Sketched regex: extract Scope OUT bullets via `awk '/^- \*\*OUT:\*\*$|^- OUT:/,/^[^- ]/' | rg -oP '`[^`]+`'` → list of file paths and component names. For each, scan analysis sections (lines after `## Systems Engineering Analysis`) for verb tokens `(Add|Insert|Modify|Replace|Emit|Log|prescribes|requires.*to|connector must)\s+.*(<extracted-target>)`. FAIL when match found.
- [ ] 3. Extend `plan-reviewer.sh` with **Check 8F** (numeric-parameter sweep manifest validation). Read the plan's `S4 (Numeric-Parameter Sweep):` line; require it to either say `swept, 0 matches` or list parameters in the form `swept for params [<list>], all values consistent` per the rule's specified format. If the latter, extract the parameter list and grep Section 9 (Load/capacity) for digit-tokens ≥ 3 chars adjacent to capacity-context tokens (`RPM|ITPM|OTPM|threads|calls|batch|cap|max|timeout|retries`). FAIL when any such digit-token's accompanying parameter name does not appear in the sweep manifest.
- [ ] 4. Extend `plan-reviewer.sh --self-test` with three new fixture pairs (PASS + FAIL per check = 6 new scenarios) covering 8A / 8E / 8F.
- [ ] 5. Update `docs/failure-modes.md` Detection / Prevention fields for FM-007, FM-015, FM-016 to cite the new checks with commit SHA. Leave FM-008/009/010/011/012/013/014/017 unchanged (still Pattern-only — see Decisions Log D-1 for why).
- [ ] 6. Update `rules/design-mode-planning.md` Enforcement summary table: flip the `plan-reviewer.sh extension` Status from "planned, not yet implemented" to a partial-landed status pointing at this plan's commit. Note explicitly which sweeps are mechanized (S1, S5, S4) and which remain Pattern-only (S2, S3, plus the FM-010/012/013/014/017 prevention).
- [ ] 7. Sync changed files from neural-lace adapter directory to `~/.claude/` per `harness-maintenance.md` Windows manual-sync rule. Verify with the diff loop. Commit, dual-remote push.

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-reviewer.sh` — extend with Checks 8A, 8E, 8F (Tasks 1-3) and self-test scenarios (Task 4). One bash file, ~150 added lines. Each check is a self-contained function so they're individually disable-able if any produces false-positive churn after live use. Specifically:
  - **Check 8A** behavior changes: section-presence + substance gate. Single-token bypass (`n/a` alone, `TODO` alone, etc.) FAILs; only the canonical full-sentence carve-out is accepted.
  - **Check 8E** behavior changes: extracts Scope OUT bullets, scans analysis sections for prescription verbs targeting OUT items.
  - **Check 8F** behavior changes: parses the audit's S4 line for the swept-parameter manifest, cross-references Section 9 numeric tokens against the manifest.
- `docs/failure-modes.md` — Detection/Prevention field updates on three entries (Task 5): FM-007 (cite Check 8A), FM-015 (cite Check 8F), FM-016 (cite Check 8E). All three updates include the implementing commit SHA. ~10 lines edited per entry.
- `adapters/claude-code/rules/design-mode-planning.md` — Enforcement summary table status update (Task 6). ~10 added lines documenting which sweeps are now mechanized (S1, S4, S5) vs Pattern-only (S2, S3).
- `~/.claude/hooks/plan-reviewer.sh`, `~/.claude/docs/failure-modes.md`, `~/.claude/rules/design-mode-planning.md` — copies synced from the adapter directory after Task 6 completes (Task 7). The `~/.claude/docs/failure-modes.md` file does not currently exist — Task 7 creates it as part of the sync (it's referenced from `~/.claude/rules/diagnosis.md` so the harness expects it to exist locally).

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

### D-2: FM-015 promoted from out-of-scope to in-scope as Check 8F (2026-05-03)

- **Tier:** 2
- **Status:** proceeded with reviewer recommendation
- **Chosen:** Mechanize FM-015 (numeric-parameter-not-fully-swept) as Check 8F. The audit's S4 line already specifies the format (`swept for params [<list>], all values consistent`); the hook parses that manifest, then greps Section 9 for digit-tokens not in the manifest.
- **Alternatives considered:** Leave FM-015 as Pattern-only alongside FM-008/009/011. Rejected: the rule already specifies the sweep query (`rg -n '\b<value>\b'`) and the audit format requires the planner to enumerate swept parameters — the data needed to mechanize is already required. Triaging as out-of-scope was a wrong call corrected by the reviewer.
- **Reasoning:** the harness's three-axis discipline-mechanism-feedback model (per `docs/best-practices.md`) prefers mechanizing whenever the data is already structured. FM-015's data IS structured by the audit format; the cost of the check is small and the value is high (it's the one of the four "out-of-scope" classes that produced a real round-4 review failure in the originating effort).
- **Checkpoint:** plan revision committed at <SHA TBD via Task 7 commit>.
- **To reverse:** delete Check 8F from plan-reviewer.sh; remove the corresponding self-test scenarios. Cost ~15 minutes.

## Pre-Submission Audit

n/a — Mode: code plan, no class-sweep needed. (The audit discipline is required for `Mode: design` plans, where the 10-section systems-engineering analysis presents the surface area sweeps must cover. This plan's scope is one bash hook + one agent prompt edit + a docs sweep; no analysis sections exist for sweeps to apply to. Per the carve-out in `rules/design-mode-planning.md` "When the audit doesn't apply".)

## Definition of Done

- [ ] All 7 tasks above are checked by the `task-verifier` agent (per harness rule, only task-verifier flips checkboxes).
- [ ] `plan-reviewer.sh --self-test` exits 0 with all scenarios matching expectations (existing 4 + 6 new = 10 total).
- [ ] The three affected `failure-modes.md` entries (FM-007, FM-015, FM-016) cite the implementing commit SHA in their Detection / Prevention fields. The other eight FM entries stay Pattern-only with text reflecting that the originally-planned mechanism is deferred.
- [ ] `~/.claude/` and `~/claude-projects/neural-lace/adapters/claude-code/` show zero diff for the four changed files (plan-reviewer.sh, design-mode-planning.md, failure-modes.md, plus the new `~/.claude/docs/failure-modes.md` symlink-or-copy).
- [ ] Backlog items HARNESS-AUDIT-EXT-01 and HARNESS-AUDIT-EXT-02 are deleted from `docs/backlog.md` (already done atomically with the initial plan-file creation commit `428dbef`, per backlog-plan-atomicity hook).
- [ ] Completion report appended to this plan file per `~/.claude/templates/completion-report.md`.
