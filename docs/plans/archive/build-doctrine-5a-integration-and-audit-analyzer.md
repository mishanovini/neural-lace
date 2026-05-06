<!-- scaffold-created: 2026-05-06T10:21:29Z by start-plan.sh slug=build-doctrine-5a-integration-and-audit-analyzer -->
# Plan: Build Doctrine 5a Integration And Audit Analyzer
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan — 5a wiring + audit-log analyzer are harness machinery, no end-user product surface; validation is via self-test + structural file-existence checks.
tier: 2
rung: 2
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal

Bridge Tranche 5a (knowledge-integration ritual, shipped earlier today as `build-doctrine/doctrine/07-knowledge-integration.md`) from shipped-content to shipped-mechanism. Three deliverables:

1. **Wire 5a into the harness mechanism stack** — enforcement-map row in `vaporware-prevention.md`, section in `harness-architecture.md`, citations from narrative docs (best-practices, harness-strategy, claude-code-quality-strategy, CLAUDE.md, README), extension to `harness-review.md` skill so its periodic cadence drives a KIT-1..KIT-7 sweep.
2. **Build the audit-log analyzer** — bash+jq script reading `build-doctrine/telemetry/propagation.jsonl` (Tranche 6a's audit log) and emitting cadence stats / fan-out frequency / unmatched-event-class summary / slow-rule report. Consumed by KIT-6 trigger and by `harness-review` skill.
3. **Author pilot-friction template** — `adapters/claude-code/templates/pilot-friction.md` standardizing the per-floor / per-mechanism friction shape that Tranche 4 (canonical pilot) sessions will fill in.

User-observable outcome: a developer running `/harness-review` after this lands sees a KIT-1..KIT-7 sweep step that reports calibration-pattern hits, findings-pattern hits, discovery accumulation, ADR-cross-reference staleness, and propagation-engine audit-log insights — converting the 5a ritual from "doctrine doc" into "operational sweep with mechanical findings." Pilot sessions can then capture friction in a structured template, producing inputs for Tranches 5b / 6b / 7 that match what those tranches expect to consume.

## Scope
- IN: 5a enforcement-map row added to `adapters/claude-code/rules/vaporware-prevention.md` (synced to ~/.claude/rules/). New "Knowledge Integration Ritual" section in `docs/harness-architecture.md`. Citations added to `README.md`, `docs/best-practices.md`, `docs/harness-strategy.md`, `docs/claude-code-quality-strategy.md`, `adapters/claude-code/CLAUDE.md` (one-line each pointing at `build-doctrine/doctrine/07-knowledge-integration.md`). Extension to `adapters/claude-code/skills/harness-review.md` (and live mirror) adding Check 13 — KIT-1..KIT-7 sweep. New script `adapters/claude-code/scripts/analyze-propagation-audit-log.sh` (synced) with `--self-test`. New template `adapters/claude-code/templates/pilot-friction.md`. CHANGELOG bumped to v0.6 entry.
- OUT: Cadence calibration (Tranche 5b — pilot-gated). Trigger threshold tuning (5b). Cross-project pattern detection (5c — telemetry-gated 2026-08). Per-canon-category propagation rules (6b — pilot-gated). Real-time hook-chain wiring of the propagation engine (separate follow-up commit; not blocking 5a's operational value). Refactoring the 4 narrow hooks the engine supersedes (post-evidence cleanup).

## Tasks

- [ ] 1. Add 5a enforcement-map row to `adapters/claude-code/rules/vaporware-prevention.md`. Sync to `~/.claude/rules/`. Verification: mechanical
- [ ] 2. Add new "Knowledge Integration Ritual (Tranche 5a, 2026-05-06)" section to `docs/harness-architecture.md` documenting the ritual + 7 KIT triggers + ritual cadence + composition with calibration / findings / discoveries / propagation-audit-log. Verification: mechanical
- [ ] 3. Add one-line citation to `README.md`, `docs/best-practices.md`, `docs/harness-strategy.md`, `docs/claude-code-quality-strategy.md`, `adapters/claude-code/CLAUDE.md` pointing at `build-doctrine/doctrine/07-knowledge-integration.md`. Verification: mechanical
- [ ] 4. Author `adapters/claude-code/scripts/analyze-propagation-audit-log.sh` reading `build-doctrine/telemetry/propagation.jsonl` and emitting: rule-fire frequency by rule_id, conjectural-rule disposition candidates, unmatched-event-class summary, slow-rule report. Subcommands: `summary`, `cadence`, `unmatched`, `--self-test`. Verification: mechanical
- [ ] 5. Sync analyzer to `~/.claude/scripts/` and run `--self-test` against synced copy. Verification: mechanical
- [ ] 6. Extend `adapters/claude-code/skills/harness-review.md` (and live mirror) with Check 13 — KIT-1..KIT-7 sweep using the new analyzer + existing capture substrates (calibration / findings / discoveries / ADR ledger). Verification: mechanical
- [ ] 7. Author `adapters/claude-code/templates/pilot-friction.md` documenting the per-floor / per-mechanism friction shape Tranche 4 pilot sessions fill in. Sync to `~/.claude/templates/`. Verification: mechanical
- [ ] 8. Update `build-doctrine/CHANGELOG.md` with v0.6 entry. Update `docs/build-doctrine-roadmap.md` "Recent updates" with a 2026-05-06 line capturing the integration ship. Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (Task 1)
- `~/.claude/rules/vaporware-prevention.md` — MODIFY (Task 1, live mirror)
- `docs/harness-architecture.md` — MODIFY (Task 2)
- `README.md` — MODIFY (Task 3)
- `docs/best-practices.md` — MODIFY (Task 3)
- `docs/harness-strategy.md` — MODIFY (Task 3)
- `docs/claude-code-quality-strategy.md` — MODIFY (Task 3)
- `adapters/claude-code/CLAUDE.md` — MODIFY (Task 3)
- `adapters/claude-code/scripts/analyze-propagation-audit-log.sh` — CREATE (Task 4)
- `~/.claude/scripts/analyze-propagation-audit-log.sh` — CREATE (Task 5, live mirror)
- `adapters/claude-code/skills/harness-review.md` — MODIFY (Task 6)
- `~/.claude/skills/harness-review.md` — MODIFY (Task 6, live mirror)
- `adapters/claude-code/templates/pilot-friction.md` — CREATE (Task 7)
- `~/.claude/templates/pilot-friction.md` — CREATE (Task 7, live mirror)
- `build-doctrine/CHANGELOG.md` — MODIFY (Task 8)
- `docs/build-doctrine-roadmap.md` — MODIFY (Task 8)
- `docs/plans/build-doctrine-5a-integration-and-audit-analyzer.md` — CREATE (this plan)
- `docs/decisions/queued-build-doctrine-5a-integration-and-audit-analyzer.md` — CREATE (companion queue)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- Bash 4+ + `jq` available (matches existing harness conventions).
- The propagation audit log may be empty when the analyzer runs (engine has never fired). Analyzer must handle empty-input gracefully.
- The 7 KIT triggers in 5a are stable enough for v1 sweep — KIT-6 maps to the analyzer's output; KIT-1..KIT-5 map to existing capture substrates; KIT-7 (drift) is gated on Tranche 5c and is a no-op in v1.
- Narrative-doc citations are one-line additions, not substantive rewrites — substantial doc updates for 5a are deferred until pilot-evidence revises 5a's hypothesis fields.

## Edge Cases
- Audit log file does not exist (engine has never fired). Analyzer reports "no events; engine has not fired yet" and exits 0.
- Audit log has corrupted JSONL line. Analyzer skips invalid lines + reports their line numbers in stderr; valid-line stats still emit.
- KIT-6 trigger has no fired-rule events to summarize. Analyzer reports the unmatched-class summary as the primary signal.
- Conjectural-rule promotion candidates use ≥3 matched events as the v1 threshold; this itself is a hypothesis. Marked in analyzer output.
- `harness-review` Check 13 handles missing audit log: emits "audit log absent — engine not yet wired into PostToolUse" and continues with KIT-1..KIT-5/KIT-7.

## Acceptance Scenarios

n/a — harness-development plan, no product user.

## Out-of-scope scenarios

None — harness-development plan, acceptance-exempt.

## Testing Strategy
- **Analyzer self-test:** `--self-test` covers ~6-8 scenarios — empty audit log, audit log with N matched events, audit log with unmatched events (negative-space summary), audit log with mixed matched/unmatched, audit log with corrupt line (continues), audit log with conjectural-rule candidate, audit log with slow-rule entries.
- **Live mirror parity:** `~/.claude/scripts/analyze-propagation-audit-log.sh --self-test` produces same PASS results as in-repo copy.
- **Citation existence check:** `grep -q "07-knowledge-integration" <doc>` returns 0 for all 5 narrative docs.
- **Skill extension structure:** `harness-review.md` has Check 13 heading + KIT-1..KIT-7 subsection structure.
- **Per-task verification:** all 8 tasks use `Verification: mechanical` (file-existence + content checks via `write-evidence.sh capture`).

## Walking Skeleton

Thinnest end-to-end slice: analyzer + Check 13 + KIT-6 sweep on synthetic audit log. First task to ship: **Task 4** (analyzer). Once it works against synthetic input, Task 6 (Check 13) wires it in, and Tasks 1-3 + 7-8 are the documentation/wiring layer.

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol)

## Definition of Done
- [ ] All 8 tasks checked off
- [ ] 5a referenced from ≥ 5 narrative docs
- [ ] Analyzer self-test passes 6-8 scenarios cleanly
- [ ] Live mirrors match in-repo copies (analyzer + skill + template)
- [ ] CHANGELOG bumped to v0.6
- [ ] Roadmap "Recent updates" has a 2026-05-06 entry
- [ ] Plan closed via close-plan.sh

## Completion Report

_Generated by close-plan.sh on 2026-05-06T10:38:57Z._

### 1. Implementation Summary

Plan: `docs/plans/build-doctrine-5a-integration-and-audit-analyzer.md` (slug: `build-doctrine-5a-integration-and-audit-analyzer`).

Files touched (per plan's `## Files to Modify/Create`):

- `README.md`
- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/scripts/analyze-propagation-audit-log.sh`
- `adapters/claude-code/skills/harness-review.md`
- `adapters/claude-code/templates/pilot-friction.md`
- `build-doctrine/CHANGELOG.md`
- `docs/best-practices.md`
- `docs/build-doctrine-roadmap.md`
- `docs/claude-code-quality-strategy.md`
- `docs/decisions/queued-build-doctrine-5a-integration-and-audit-analyzer.md`
- `docs/harness-architecture.md`
- `docs/harness-strategy.md`
- `docs/plans/build-doctrine-5a-integration-and-audit-analyzer.md`
- `~/.claude/rules/vaporware-prevention.md`
- `~/.claude/scripts/analyze-propagation-audit-log.sh`
- `~/.claude/skills/harness-review.md`
- `~/.claude/templates/pilot-friction.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0a1f012 close(tranche-2): 7 template schemas — DONE via close-plan.sh
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1aadf35 docs(strategy): clarify dual-layer enforcement + add automation framework
1e6310c feat(hook): A7 — imperative-evidence linker
207d76a close(tranche-3): 29 template files — DONE via close-plan.sh
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
25ed7f5 docs(handoff): refresh backlog + roadmap to reflect closed Tranche 1.5 + add HARNESS-GAP-19
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
460519e feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
46616ba feat(build-doctrine): Tranche 6a — propagation engine framework + 8 starter rules + audit log
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
