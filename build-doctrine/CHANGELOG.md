# Build Doctrine Changelog

## 2026-05-06 — v0.6 (Tranche 5a-integration: ritual wired in + audit-log analyzer + pilot-friction template)

- 5a doctrine doc (`build-doctrine/doctrine/07-knowledge-integration.md`, shipped earlier today) now wired into the harness mechanism stack:
  - Enforcement-map row in `adapters/claude-code/rules/vaporware-prevention.md` (synced to `~/.claude/rules/`).
  - New "Knowledge Integration Ritual" section in `docs/harness-architecture.md`.
  - One-line citations + sub-sections in `README.md`, `docs/best-practices.md`, `docs/harness-strategy.md`, `docs/claude-code-quality-strategy.md`, `adapters/claude-code/CLAUDE.md`.
  - `/harness-review` skill extended with **Check 13** — KIT-1..KIT-7 sweep against existing capture substrates (calibration / findings / discoveries / ADR ledger) plus the new audit-log analyzer (KIT-6); KIT-7 is a no-op pending Tranche 5c.
- Audit-log analyzer at `adapters/claude-code/scripts/analyze-propagation-audit-log.sh` (synced to `~/.claude/scripts/`):
  - Subcommands: `summary`, `cadence`, `unmatched`, `slow`.
  - Reads `build-doctrine/telemetry/propagation.jsonl` produced by Tranche 6a's engine.
  - Surfaces: rule-fire frequency, conjectural-rule promotion candidates (>= 3 matched events — itself a hypothesis), unmatched-event-type negative-space, slow-rule report, top-level summary.
  - Self-test: 7/7 PASS scenarios (missing log graceful, empty graceful, fired-only counts, unmatched event types, cadence promotion candidate, corrupt-line continues, slow-rule report).
- Pilot-friction template at `adapters/claude-code/templates/pilot-friction.md` (synced to `~/.claude/templates/`):
  - Standardizes Tranche-4 (canonical pilot) friction notes — per-floor, per-canon-artifact, per-propagation-rule, per-KIT-trigger sections.
  - Pilot sessions write `<pilot-repo>/docs/sessions/<date>-pilot-friction.md` from this template.
  - Structured input for Tranches 5b (cadence calibration), 6b (per-canon rules), 7 (residual C-mechanisms).
- **Pre-pilot infrastructure now complete.** The pilot consumes a fully-wired substrate: doctrine + templates + propagation engine + audit log + ritual + sweep + analyzer + friction template. Without this integration, the pilot would generate operator memory rather than counted observations.

## 2026-05-06 — v0.5 (Tranche 6a: propagation engine framework + audit log + 8 starter rules)

- Engine: `adapters/claude-code/hooks/propagation-trigger-router.sh` (~700 LOC bash) reading `propagation-rules.json`, evaluating triggers + conditions + actions, writing audit-log entries to `build-doctrine/telemetry/propagation.jsonl` (one JSONL line per rule evaluation, matched OR unmatched).
- Schema: `adapters/claude-code/schemas/propagation-rules.schema.json` — JSON Schema draft 2020-12 defining the rule format (id, trigger, condition, action, severity, owner, conjectural, pending_evidence).
- Rules: `build-doctrine/propagation/propagation-rules.json` ships 8 starter rules:
  - **4 proven** generalizing existing narrow hooks: plan-lifecycle archive, plan-edit evidence-first, decisions-index update, narrative-doc staleness.
  - **3 conjectural** covering existing canon: PT-3 ADR-adoption fan-out, PT-4 doctrine-change finding-routing, PT-6 findings-pattern detection. Each tagged `conjectural: true` + `pending_evidence: audit-log-tuning`.
  - **1 docs-coupling** rule fanning out doc-cross-reference changes.
- Audit log at `build-doctrine/telemetry/propagation.jsonl` (gitignored; per-event data). `.gitkeep` tracks the directory.
- README at `build-doctrine/propagation/README.md` documenting engine, audit-log format, conjectural-rule disposition path, performance budget hypothesis.
- Self-test: 14/14 PASS scenarios covering schema-validity, rules-validity, matching events fire rules, unmatched events record negative-space, metadata-match filters, path-pattern matching, malformed-config rejection, missing-config rejection, audit-log JSONL format, required-fields presence, failed-action recording, condition-not-met skip-action, production-rules load.
- **Performance budget** is v1 hypothesis: 1000ms per-rule / 5000ms per-event (doctrine target is 100ms / 500ms). Bash + jq on Windows Git Bash measures ~300ms per rule due to subprocess overhead; v2 optimization deferred.
- **Real-time hook wiring deferred** to a follow-up commit. Engine is standalone-runnable; the existing 4 narrow hooks (plan-lifecycle, plan-edit-validator, decisions-index-gate, docs-freshness-gate) remain in place; consolidation only happens after engine is proven.
- **Per the teaching example**: the audit log IS the measurement substrate for the canonical pilot. Without this engine, pilot evidence is operator memory rather than counted data. Tranche 6a ships ahead of the pilot to bootstrap the measurement loop.

## 2026-05-06 — v0.4 (Tranche 6 scaffolding: orchestrator project structure)

- Python orchestrator scaffolding at `build-doctrine-orchestrator/`: pyproject.toml,
  package layout (`src/build_doctrine_orchestrator/`), DAG state machine
  (nodes + edges + topological iteration + cycle detection), state types
  + transition rules (TaskState, DispatchState), Dispatcher protocol +
  NoopDispatcher reference impl, pytest test harness with ~32 tests across
  state and DAG.
- **Validation deferred** to first Python-equipped session (current session
  has no Python locally; scaffolding is correct-by-inspection only). Every
  Python file marked with `_TODO_PILOT_VALIDATE_` sentinel + README documents
  the required validation steps prominently.
- **Propagation engine (C12) deliberately deferred** until canonical-pilot
  empirical signal informs which PT-1..PT-7 trigger router slots actually
  fire most. The doctrine explicitly warns against authoring all 7 cold.
- Real builder-spawn integration deferred — `Dispatcher` protocol exists,
  the `plan-phase-builder` integration is post-pilot work.
- Cross-tranche integration (with state-summary.sh, close-plan.sh,
  start-plan.sh, session-wrap.sh) deferred — orchestrator is standalone
  scaffolding in v1.

## 2026-05-06 — v0.3 (Tranche 3: template content)

- Default content for the 11 universal floors at Express + Standard
  depths under `build-doctrine-templates/conventions/universal-floors/`.
  22 floor templates total (Floor 11 / UX standards is UI-projects-only).
- Naming-convention defaults for the 4 named languages: JavaScript/TypeScript,
  Python, Go, Rust at `build-doctrine-templates/conventions/naming/`.
- Branch + commit conventions at
  `build-doctrine-templates/conventions/branching-and-commits.md`
  (Conventional Commits format + branch-prefix taxonomy + PR workflow).
- API-style architectural default at
  `build-doctrine-templates/conventions/architectural-defaults/api-style.md`
  as the worked example. Other architectural defaults (state management,
  async patterns, database access, frontend framework) deferred until
  canonical-pilot friction informs which to author next.
- README at `build-doctrine-templates/conventions/README.md` documenting
  the layout + depth tiers + how downstream projects consume.
- Templates are prose; no schema-validation. Schema-validation gates at
  commit time deferred until project bootstraps produce friction.

## 2026-05-06 — v0.2 (Tranche 2: template schemas)

- 7 canonical template schemas at `build-doctrine/template-schemas/`:
  `prd.schema.yaml`, `adr.schema.yaml`, `spec.schema.yaml`,
  `design-system.schema.yaml`, `engineering-catalog.schema.yaml`,
  `conventions.schema.yaml`, `observability.schema.yaml`. Each is JSON
  Schema draft 2020-12 in YAML form, $id-versioned at v1.
- Seven round-trip-validating example instances at
  `build-doctrine/template-schemas/examples/`. Each validates against its
  schema via `jsonschema.validate` (Python).
- README at `build-doctrine/template-schemas/README.md` documenting the
  schema set, validation invocation patterns (Python + Node), and the
  relationship to Tranche 3 (content seeding).
- Schemas validate SHAPE (structural presence + cardinality + minimum
  substance threshold). Substance review remains the per-artifact reviewer
  agent's job.
- Schema-validation gates at commit time deferred until Tranche 3 ships
  consumer templates.

## 2026-05-05

- Phase 0 migration: 8 integrated-v1 doctrine docs migrated from Build Doctrine repo
  (`~/claude-projects/Build Doctrine/outputs/integrated-v1/`) into
  `build-doctrine/doctrine/`. Migration is byte-identical; no edits.
- Initial `README.md` and `CHANGELOG.md` created.
- See `docs/decisions/025-build-doctrine-same-repo-placement.md` for the
  decision to keep `build-doctrine-templates/` in the same repo as NL
  rather than a separate repo.
