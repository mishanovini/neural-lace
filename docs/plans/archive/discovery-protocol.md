# Plan: Phase 1d-D — Discovery Protocol (Capture, Surface, Decide-and-Apply, Track)

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-10 sub-gap H (refining docs/reviews gitignore — partial; the discovery protocol provides the durable-capture path that sub-gap H sought).
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; deliverable is a new rule, two new hook artifacts (one new + one extended), an initial population of discovery files, and minimal wiring. No user-facing product surface.

## Context

Sessions repeatedly surface mid-process realizations that aren't bug-shaped (already captured by `bug-persistence-gate`) but are still consequential: architectural learnings, scope expansions, dependency surprises, performance discoveries, failure-mode discoveries, process discoveries, user-experience discoveries. Today these get reasoned about in commit messages or scattered across artifact types — and most then evaporate. The current session has produced at least six: NL-impl-plan-location learning, settings.json-vs-template divergence, spine-stage-count cross-doc drift, gitignore-blinds-bug-persistence-gate, agent-incentive-map as proactive layer, plan-lifecycle archival waiver dance.

Per user directive (2026-05-03): the harness needs (a) durable capture of these discoveries, (b) surfacing to the decision-maker, (c) decide-and-apply autonomous flow for reversible decisions, (d) audit-trail tracking with conclusion-summary visibility for retrospective review.

This plan ships the protocol's first version. Phase 1d-D-2 (deferred) will add automatic builder-return capture and full propagation routing per the seven discovery types; Phase 1d-D-1 (this plan) ships the durable substrate plus surfacing.

Working on branch `build-doctrine-integration` in `~/claude-projects/neural-lace/`. Two prior commits on this branch (`cc20cde`, `18d3911`, `b7ceb2d`).

## Goal

Five deliverables forming the minimum-viable Discovery Protocol:

1. **`~/.claude/rules/discovery-protocol.md`** — the rule documenting format, types, capture pathways, surfacing, decision protocol, propagation. Mirror to `adapters/claude-code/rules/discovery-protocol.md`.
2. **Extended `bug-persistence-gate.sh`** — accepts `docs/discoveries/YYYY-MM-DD-<slug>.md` as legitimate persistence (alongside the existing `docs/backlog.md` and `docs/reviews/`). Mirror to `~/.claude/hooks/`.
3. **`discovery-surfacer.sh`** — new SessionStart hook scanning `docs/discoveries/` for `Status: pending` and surfacing them in system-reminder. Mirror to `~/.claude/hooks/`. Wire into `settings.json.template` and `~/.claude/settings.json`.
4. **`docs/discoveries/`** directory with **6 initial-population discovery files** capturing the discoveries this session has produced. All start at `Status: decided` since each was already resolved during the work.
5. **Documentation updates** — `~/.claude/rules/vaporware-prevention.md` enforcement map gets two new rows (capture + surfacer); `docs/harness-architecture.md` preface cites the new rule + hooks.

## Scope

**IN:**
- All 5 deliverables above.
- Single thematic commit on `build-doctrine-integration`, push to `origin`.
- Self-tests for `discovery-surfacer.sh` and the extended `bug-persistence-gate.sh`.

**OUT:**
- Phase 1d-D-2 (PostToolUse hook on Task to auto-capture builder-returned discoveries; full taxonomy-routed propagation per discovery type; /harness-review extension to surface stuck discoveries).
- Phase 1d-G (calibration mimicry — depends on Phase 1d-C-3's findings ledger).
- Phase 1d-C-2 work (PRD-validity + spec-freeze + interface declarations — separate plan after this).
- Discovery-file creation for discoveries that emerged AFTER the user's directive landed (those become test cases for the protocol once it's live).

## Discovery file format

Frontmatter:
```yaml
---
title: <imperative description, ≤60 chars>
date: 2026-05-03
type: architectural-learning | scope-expansion | dependency-surprise | performance | failure-mode | process | user-experience
status: pending | decided | implemented | rejected | superseded
auto_applied: true | false
originating_context: <plan path or session description where surfaced>
decision_needed: <specific question; populated for pending; "n/a — auto-applied" for decided autonomous>
predicted_downstream:
  - <artifact path or type that this affects>
---
```

Body sections:
- **What was discovered** — concrete description with file:line citations
- **Why it matters** — what fails if not addressed
- **Options** — paths forward with tradeoffs (for `Status: pending`)
- **Recommendation** — proposed direction
- **Decision** — populated after resolution
- **Implementation log** — populated after downstream effects land

## Tasks

Tasks dispatched per orchestrator-pattern. T1, T2, T3, T4 touch different files and run in parallel. T5 sequential (shared docs). T6 sequential (commit + push).

### Batch 1 (parallel, 4 builders)

- [x] **T1.** Write `~/.claude/rules/discovery-protocol.md` (and adapter mirror at `adapters/claude-code/rules/discovery-protocol.md`). The rule documents: typology of 7 discovery types, file format with frontmatter spec, three capture pathways (orchestrator-initiated, builder-return-derived (Phase 1d-D-2 deferred), bug-persistence-gate-extended), surfacing mechanism (SessionStart hook), decision protocol with auto-apply-vs-pause boundary (reversible auto-applied per user directive 2026-05-03; irreversible pauses), propagation routing per discovery type, lifecycle (pending → decided → implemented → archived OR rejected), versioning. Length target: 1500-2500 words. Cross-references existing rules (planning.md decision tiers, vaporware-prevention.md, diagnosis.md).

- [x] **T2.** Extend `~/claude-projects/neural-lace/adapters/claude-code/hooks/bug-persistence-gate.sh` to accept `docs/discoveries/YYYY-MM-DD-*.md` as legitimate persistence. Three places to update:
  - The `check_persisted_for()` function adds a third detection clause looking for new untracked files matching `docs/discoveries/[0-9]{4}-[0-9]{2}-[0-9]{2}-*.md` (mirrors the existing `docs/reviews/` clause exactly).
  - The block message body adds a fourth bullet describing the discoveries-path option.
  - Self-test gets one new scenario: trigger phrase present + new discovery file matching the pattern → PASS (no block).
  - Mirror to `~/.claude/hooks/bug-persistence-gate.sh`. Run `--self-test` on both copies.

- [x] **T3.** Create `~/claude-projects/neural-lace/adapters/claude-code/hooks/discovery-surfacer.sh` (new SessionStart hook). Logic:
  - Locate the working-directory's `docs/discoveries/` directory; if absent, exit 0 silently.
  - Scan for files matching `[0-9]{4}-[0-9]{2}-[0-9]{2}-*.md` with `Status: pending` in their frontmatter (top 30 lines).
  - For each pending discovery, output a system-reminder block with: title, type, date, decision_needed, originating_context, recommendation (extracted from body or marked "see file").
  - If pending count is zero, exit 0 silently.
  - Provide `--self-test` with 4 scenarios: no directory, empty directory, all-decided, ≥1 pending.
  - Mirror to `~/.claude/hooks/discovery-surfacer.sh`.

- [x] **T4.** Create `docs/discoveries/` directory with 6 initial-population files capturing this session's discoveries. Each file has the format defined in this plan's "Discovery file format" section. All 6 start at `Status: decided` and `auto_applied: true` since each was resolved during the work that surfaced it. Files:
  1. `2026-05-03-nl-impl-plans-belong-in-docs-plans.md` (architectural-learning) — surfaced when scope-enforcement-gate blocked a commit because the governing plan was at `~/.claude/plans/` not `docs/plans/`. Decision: future NL-implementation plans live at NL's `docs/plans/`. Applied via the agent-incentive-map plan being placed there.
  2. `2026-05-03-settings-template-vs-live-divergence.md` (process) — surfaced when settings.json wiring was missed because settings.json is gitignored and settings.json.template is the committed source. Decision: always update both. Applied via the C10/C7-DAG-waiver wiring touching both.
  3. `2026-05-03-spine-stage-count-cross-doc-drift.md` (process) — surfaced when T6 of the doctrine-restructure plan ran cross-doc consistency check and found 04-gates and 05-implementation said "11-stage" while 03/09 said "10-stage". Decision: standardize on 10-stage canonical naming. Applied via 5-location class-sweep.
  4. `2026-05-03-gitignore-blinds-bug-persistence-gate.md` (process) — surfaced when bug-persistence-gate couldn't see a freshly-written review file because docs/reviews/ is broadly gitignored. Decision: capture to backlog when reviews are gitignored; long-term refine gitignore to allow NL-self-reviews. Applied via HARNESS-GAP-10 sub-gap H.
  5. `2026-05-03-agent-incentive-map-as-proactive-layer.md` (architectural-learning) — surfaced when user invoked Munger's incentive frame. Decision: build the proactive layer alongside reactive failure-correction. Applied via Phase 1d-incentive-map work.
  6. `2026-05-03-plan-lifecycle-archival-waiver-dance.md` (process) — surfaced when the plan-lifecycle hook auto-archived a plan and the subsequent archival commit needed its own scope-waiver. Decision: scope-enforcement-gate should treat plan-lifecycle.sh's archival rename as in-scope automatically when triggered by Status: COMPLETED on a recently-active plan. Captured here for follow-up; partial mitigation in current waiver workflow.

Each file: 200-400 words covering the format's required sections.

### Batch 2 (sequential, single builder) — Wiring + Documentation + Phase 1d-G Plan Capture

- [x] **T5.** Wire `discovery-surfacer.sh` into both `adapters/claude-code/settings.json.template` and `~/.claude/settings.json` as a SessionStart hook (the SessionStart hook chain pattern mirrors existing entries). Update `~/.claude/rules/vaporware-prevention.md` enforcement map with two new rows (discovery-protocol persistence, discovery-surfacer surfacing) AND mirror to adapter copy. Update `docs/harness-architecture.md` preface to cite the new rule + hooks. Update `docs/backlog.md` Last-updated header line to chain the new annotation.

- [x] **T7.** Write `docs/plans/phase-1d-g-calibration-mimicry.md` capturing the user's confirmed decisions on the calibration-mimicry mechanism (2026-05-03 confirmation). The plan ships at `Status: DEFERRED` since its dependencies (telemetry from HARNESS-GAP-10 sub-gap D; findings ledger from C9 in Phase 1d-C-3) have not yet shipped. The plan must encode these confirmed user decisions as design constraints:
  - **Decision G-1 (acceptable approximation):** RL-shaped via prompt conditioning is acceptable. No fine-tuning of any model. The mechanism produces calibration adjustment via injected prompts, not weight updates.
  - **Decision G-2 (scope of independent grading):** Start with high-stakes agents first — task-verifier, harness-reviewer, end-user-advocate runtime. Expand based on empirical drift evidence. Lower-stakes agents (explorer, research) deferred unless evidence justifies.
  - **Decision G-3 (visibility):** All three channels — internal-to-NL state, agents-see-it (calibration profiles in agent prompts), public visibility. Plus: a dashboard surface (mentioned by user as eventual expansion to provide harness-stats per project).
  - **Decision G-4 (dashboard, NEW from user 2026-05-03):** A dashboard surface for harness calibration + harness stats per project. This is a meaningful new artifact; design-decision-deferred. Captured here as forward-looking scope rather than an implementation directive in this plan.

  The plan's three sub-phases (1d-G-1 calibration-tracking, 1d-G-2 calibration-injector, 1d-G-3 scoreboard-+-dashboard) are documented as previously discussed. Length: 1500-2500 words.

### Batch 3 (sequential after Batch 2) — Commit + Push

- [x] **T6.** Stage all changes; write scope-waiver against the still-active pre-submission-audit-mechanical-enforcement.md plan; commit thematically; push to `origin/build-doctrine-integration`.

## Files to Modify/Create

**New files:**
- `~/.claude/rules/discovery-protocol.md`
- `adapters/claude-code/rules/discovery-protocol.md`
- `adapters/claude-code/hooks/discovery-surfacer.sh`
- `~/.claude/hooks/discovery-surfacer.sh`
- `docs/discoveries/2026-05-03-nl-impl-plans-belong-in-docs-plans.md`
- `docs/discoveries/2026-05-03-settings-template-vs-live-divergence.md`
- `docs/discoveries/2026-05-03-spine-stage-count-cross-doc-drift.md`
- `docs/discoveries/2026-05-03-gitignore-blinds-bug-persistence-gate.md`
- `docs/discoveries/2026-05-03-agent-incentive-map-as-proactive-layer.md`
- `docs/discoveries/2026-05-03-plan-lifecycle-archival-waiver-dance.md`
- `docs/plans/phase-1d-g-calibration-mimicry.md` (T7 deliverable; Status: DEFERRED)
- `docs/plans/discovery-protocol.md` (this plan; self-referential)

**Modified files:**
- `adapters/claude-code/hooks/bug-persistence-gate.sh`
- `~/.claude/hooks/bug-persistence-gate.sh`
- `adapters/claude-code/settings.json.template`
- `~/.claude/settings.json`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `~/.claude/rules/vaporware-prevention.md`
- `docs/harness-architecture.md`
- `docs/backlog.md` (Last-updated header chain)

## Assumptions

- The existing pre-submission-audit-mechanical-enforcement.md plan is still ACTIVE; scope-enforcement-gate will require a waiver against it.
- `docs/discoveries/` is NOT in the gitignore (will need to verify and add an exclusion if gitignore catches it the way `docs/reviews/` does — likely safe since `docs/discoveries/` is novel).
- The 6 initial discoveries are accurate accounts of what surfaced this session; T4's builder will write them with sufficient detail to be useful retrospective records.
- Phase 1d-D-2 work (auto-capture from builder returns; full propagation taxonomy) is durable-deferrable — the rule documents the full vision; this plan ships the substrate.

## Edge Cases

- **scope-enforcement-gate blocks because pre-submission-audit-mechanical-enforcement.md is still ACTIVE.** Mitigation: scope-waiver per existing pattern.
- **docs-freshness-gate fires because new files in `docs/discoveries/` constitute structural additions.** Mitigation: harness-architecture.md preface updated alongside.
- **harness-hygiene-scan blocks because a discovery references a project codename.** Mitigation: each discovery is reviewed for hygiene before committing; project names get sanitized to generic placeholders.
- **plan-reviewer.sh Check 9 fires because this plan has comparative phrases without arithmetic.** Mitigation: this plan is `Mode: code`, so Check 9 doesn't apply; the design-mode gating in Check 9 handles this correctly.

## Acceptance Scenarios

n/a — `acceptance-exempt: true`. Verification is structural (rule exists, hooks pass `--self-test`, files in expected paths, settings wired correctly).

## Definition of Done

- All 6 tasks task-verified PASS.
- All 18 file changes (12 new + 6 modified) land in one commit on `build-doctrine-integration`.
- Both new/extended hooks pass `--self-test`.
- Commit pushed to `origin`.
- Status of THIS plan flipped to COMPLETED at session end.
