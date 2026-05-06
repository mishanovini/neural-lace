<!-- scaffold-created: 2026-05-06T10:21:29Z by start-plan.sh slug=build-doctrine-5a-integration-and-audit-analyzer -->
# Plan: Build Doctrine 5a Integration And Audit Analyzer
Status: ACTIVE
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
