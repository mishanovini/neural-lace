<!-- scaffold-created: 2026-05-06T09:28:27Z by start-plan.sh slug=build-doctrine-tranche-6a-propagation-engine-framework -->
# Plan: Build Doctrine Tranche 6a Propagation Engine Framework
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan — propagation engine is harness machinery, no end-user product surface; validation is via self-test scenarios + audit-log structural checks.
tier: 3
rung: 3
architecture: orchestration
frozen: true
prd-ref: n/a — harness-development

## Goal

Author the propagation engine framework + audit log + 7 starter rules + 1 docs-coupling rule, **before** the canonical pilot runs. Per the teaching example at `docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md`: the propagation audit log IS the measurement mechanism. Without it, the pilot generates operator memory rather than counted data. Tranche 6a ships the measurement substrate so that Tranche 4 (canonical pilot) produces structured evidence that 6b (per-canon rules) and 6c (drift detection) can refine against.

User-observable outcome: a developer working on a Build-Doctrine-aligned project sees the propagation engine fan out changes across canon artifacts (when an ADR transitions, when a doctrine doc is edited, when ≥3 similar findings accumulate) and audit every trigger evaluation to `build-doctrine/telemetry/propagation.jsonl` — providing a counted, structured record of what propagation events actually fire most.

## Scope
- IN: `adapters/claude-code/hooks/propagation-trigger-router.sh` (the engine; ~300-500 LOC bash), `adapters/claude-code/schemas/propagation-rules.schema.json` (rule format), `build-doctrine/propagation/propagation-rules.json` (the rule set: 4 proven + 3 conjectural + 1 docs-coupling = 8 rules), `build-doctrine/telemetry/.gitkeep` (telemetry directory placeholder; the `propagation.jsonl` log is gitignored), `build-doctrine/propagation/README.md` documenting engine + rules + audit-log format. Self-test scenarios in the router covering each rule. CHANGELOG entry recording v0.5.
- OUT: Per-canon-category rules (PT-1 contract, PT-2 design-system, PT-7 cross-repo) — Tranche 6b. PT-5 drift detection — Tranche 6c. Real-time hook wiring (PostToolUse) — deferred to a follow-up commit once self-tests are green; this plan ships the engine standalone-runnable, integration follows. Refactoring the 4 generalized hooks to remove their narrow logic — they remain in place; engine duplicates+supersedes; consolidation is a future cleanup.

## Tasks

- [ ] 1. Author `adapters/claude-code/schemas/propagation-rules.schema.json` defining the rule format (id, trigger, condition, action, severity, owner, conjectural flag, description). Verification: contract
- [ ] 2. Author `adapters/claude-code/hooks/propagation-trigger-router.sh` framework: rules-loading, trigger-matching, condition-eval, action-dispatch, audit-log-writing, `--self-test` skeleton. Verification: mechanical
- [ ] 3. Author `build-doctrine/propagation/propagation-rules.json` containing the 4 proven rules generalizing `plan-lifecycle.sh`, `plan-edit-validator.sh`, `decisions-index-gate.sh`, `docs-freshness-gate.sh`. Verification: contract
- [ ] 4. Extend `propagation-rules.json` with 3 conjectural rules: PT-3 ADR-adoption-fanout, PT-4 doctrine-change-finding-routing, PT-6 findings-pattern-detection. Each tagged `conjectural: true` + `pending-evidence: audit-log-tuning` in metadata. Verification: contract
- [ ] 5. Extend `propagation-rules.json` with the docs-coupling rule (cross-reference change in one doc → fan-out check on cited docs). Verification: contract
- [ ] 6. Add self-test scenarios to `propagation-trigger-router.sh` covering each rule (1 PASS-path scenario per rule, 1 FAIL-path per rule, plus schema-validity, audit-log-format, budget-overflow, malformed-config). Verification: mechanical
- [ ] 7. Author `build-doctrine/propagation/README.md` documenting engine, rule format, audit-log format, how to add a rule, how to read telemetry, conjectural-rule disposition path. Verification: mechanical
- [ ] 8. Update `.gitignore` to exclude `build-doctrine/telemetry/propagation.jsonl`. Add `build-doctrine/telemetry/.gitkeep` to track the directory. Verification: mechanical
- [ ] 9. Sync `propagation-trigger-router.sh` to `~/.claude/hooks/` (live mirror). Run `--self-test` against synced copy. Verification: mechanical
- [ ] 10. Update `build-doctrine/CHANGELOG.md` with v0.5 entry. Update `docs/build-doctrine-roadmap.md` flipping Tranche 6a → ✅ DONE. Update `~/.claude/rules/vaporware-prevention.md` enforcement-map with propagation-engine row. Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/schemas/propagation-rules.schema.json` — CREATE (Task 1)
- `adapters/claude-code/hooks/propagation-trigger-router.sh` — CREATE (Tasks 2, 6)
- `build-doctrine/propagation/propagation-rules.json` — CREATE (Tasks 3, 4, 5)
- `build-doctrine/propagation/README.md` — CREATE (Task 7)
- `build-doctrine/telemetry/.gitkeep` — CREATE (Task 8)
- `.gitignore` — MODIFY (Task 8)
- `~/.claude/hooks/propagation-trigger-router.sh` — CREATE (live mirror; Task 9)
- `build-doctrine/CHANGELOG.md` — MODIFY (Task 10)
- `docs/build-doctrine-roadmap.md` — MODIFY (Task 10)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (Task 10)
- `docs/plans/build-doctrine-tranche-6a-propagation-engine-framework.md` — CREATE (this plan)
- `docs/decisions/queued-build-doctrine-tranche-6a-propagation-engine-framework.md` — CREATE (companion queue)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- Bash 4+ is available (matches existing harness hook conventions).
- `jq` is available for JSON parsing (matches existing harness hooks).
- The 4 generalized hooks remain in place during 6a — engine ships in parallel and supersedes only when self-tests prove the engine handles every case the narrow hook did. Consolidation is a follow-up commit guarded on operational evidence.
- Audit log format is JSONL (one event per line), schema versioned via `schema_version: 1` field. Future schema changes are additive within v1; v2 only if breaking.
- Conjectural rules' thresholds (e.g., "≥3 similar findings within 7 days" for PT-6) are tagged as hypotheses; tuning happens once audit log accumulates evidence.
- The engine writes to telemetry on every event (matched OR unmatched) so the audit log captures the full event stream — surfaces "negative space" (events with no matching rule) as candidate-rule data.

## Edge Cases
- A rule's condition evaluator script fails (non-zero exit, syntax error). Mitigation: engine logs failure to audit + skips action; does not crash. Next rule still evaluates.
- A rule's action script fails. Mitigation: engine logs action failure with stderr captured + non-zero exit recorded; continues with subsequent rules. Surfacing via audit-log read.
- Two rules match the same event with overlapping actions. Mitigation: engine evaluates rules in `id` order; each action runs independently. Operator-level deduplication is rule-author responsibility.
- `propagation-rules.json` is malformed. Mitigation: engine fails at load with explicit error naming file + line + reason. No partial loads.
- Audit log file does not exist at first event. Mitigation: engine creates `build-doctrine/telemetry/propagation.jsonl` with parent dir; first event writes the first line.
- Audit log write fails (disk full, permissions). Mitigation: engine logs to stderr + continues; does not crash.
- An event happens that no rule matches. Mitigation: engine writes a single `unmatched` audit entry. Negative space is itself measurement data.

## Acceptance Scenarios

n/a — harness-development plan, no product user.

## Out-of-scope scenarios

None — harness-development plan, acceptance-exempt.

## Behavioral Contracts

(Required for `rung: 3+` per `plan-reviewer.sh` Check 11.)

### Idempotency

Re-running the engine on the same input event must not produce duplicate side effects. The audit log is append-only and records every evaluation (matched and unmatched), so a re-run produces a new audit entry, but rule actions guard with existence-checks (e.g., "is the index entry already present? If so, no-op."). Replaying the same event N times produces N audit entries (intentional — captures invocation count) but the underlying state changes once.

### Performance budget

Engine total per-event evaluation budget: **< 500ms wall time** for the full rules sweep. Per-rule budget: **< 100ms**. Rules exceeding their per-rule budget log a `slow-rule` warning to the audit entry; rules exceeding the total event budget cause the engine to log `event-budget-exceeded` and stop processing remaining rules (ensuring the engine itself doesn't become a commit-time bottleneck). Budget verification happens during self-test against the 8 starter rules.

### Retry semantics

Within a single event invocation, failed rules are NOT retried — the audit log records the failure and the engine moves to the next rule. Manual retry happens by re-triggering the source event (e.g., re-editing the file, re-flipping the status). This matches the doctrine principle that propagation is reactive to events, not to its own failures — a failed rule is itself a finding-class signal that the rule's condition or action has drifted.

### Failure modes

Three failure classes with explicit handling:
1. **Rule-script-error** (condition or action exits non-zero): engine logs to audit with exit code + captured stderr; continues with next rule. Engine does NOT crash.
2. **Configuration-error** (malformed `propagation-rules.json`, schema-mismatch): engine fails at load time before processing any event; explicit error to stderr naming file + line + schema-violation. No partial loads.
3. **Audit-log-write-error** (disk full, permission denied): engine logs to stderr; continues processing. The audit log is the measurement substrate; losing one entry is acceptable, but the engine's primary function (rule evaluation) does not depend on audit-log success.

## Testing Strategy
- **Schema-validity:** `jq empty <schema-file>` exits 0 for `propagation-rules.schema.json`.
- **Rules-validity:** loading `propagation-rules.json` against the schema succeeds; every rule has required fields.
- **Engine self-test (Task 6):** `--self-test` covers 8 PASS-path scenarios (one per rule) + 8 FAIL-path scenarios (condition not met → action does NOT fire) + schema-validity + audit-log-format + budget-overflow + malformed-config. ~18-20 scenarios total.
- **Audit-log-format check:** synthetic event written + log inspected to verify JSONL structure (one event per line; each line well-formed JSON; required fields present: timestamp, rule_id, event_type, verdict, duration_ms).
- **Live mirror parity (Task 9):** `~/.claude/hooks/propagation-trigger-router.sh --self-test` produces the same PASS results as in-repo copy.
- **Per-task verification:** Tasks 1, 3, 4, 5 use `Verification: contract` (schema-validation); Tasks 2, 6, 7, 8, 9, 10 use `Verification: mechanical`.

## Walking Skeleton

The thinnest end-to-end slice: framework + ONE starter rule (plan-lifecycle generalized) + audit log writer + ONE self-test scenario, all running end-to-end. Once that passes, the other 7 rules and ~17 self-test scenarios are additive.

First task: **Task 2** (engine framework) — establishes the rules-loading + audit-log shape that all subsequent rules + self-tests build on. The engine's first executable behavior: "load rules, find no matches for a synthetic event, write an `unmatched` audit entry, exit 0." From there, each rule + scenario adds a slice.

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol)

## Definition of Done
- [ ] All 10 tasks checked off
- [ ] All 8 starter rules validate against the schema (4 proven + 3 conjectural + 1 docs-coupling)
- [ ] Self-test passes ~18-20 scenarios cleanly
- [ ] `propagation.jsonl` gitignored; `.gitkeep` tracks the directory
- [ ] Live mirror at `~/.claude/hooks/` matches in-repo copy
- [ ] CHANGELOG bumped to v0.5
- [ ] Roadmap Tranche 6a → ✅ DONE
- [ ] Vaporware-prevention enforcement map extended with the propagation-engine row
- [ ] Plan closed via close-plan.sh
