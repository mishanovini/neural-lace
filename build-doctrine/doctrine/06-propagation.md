---
title: Build Doctrine — Propagation (Living-Document Triggers)
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - drafted independently before review of existing neural-lace artifacts (hooks, learning/, telemetry/), to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md (especially #8), 02-roles.md, 03-work-sizing.md, 04-gates.md
references:
  - outputs/unified-methodology-recommendation.md (§3 Stage 8 propagation; §6 C12 + C5 + C6 + C17 mechanism specs)
  - outputs/glossary.md
  - outputs/analysis/03-comparative-analysis.md (D-cluster + A40-A50 propagation entries)
  - ~/.claude/hooks/plan-lifecycle.sh
  - ~/.claude/hooks/plan-edit-validator.sh
  - ~/.claude/hooks/decisions-index-gate.sh
  - ~/.claude/hooks/docs-freshness-gate.sh
  - ~/.claude/skills/harness-review.md
revision_notes:
  - 2026-05-01 v1: initial 7-trigger taxonomy with mechanical-enforcement boundaries
  - 2026-05-03 v3: NL propagation hooks cross-referenced (plan-lifecycle, plan-edit-validator, decisions-index-gate, docs-freshness-gate); /harness-review skill cited as T4-trigger mechanism; C12 propagation-event hook generalization cited as forthcoming Phase 1d-C; trigger naming PT-1..PT-7 to disambiguate from "Tier" usage.
---

# Build Doctrine — Propagation (Living-Document Triggers)

## Scope

Per principle #8, every doctrine artifact, design system entry, engineering catalog entry, Integration Map node, ADR, PRD, and spec is treated as a living document. This document defines:

- The **trigger taxonomy** — what events fire propagation.
- The **propagation rules** — for each trigger, which artifacts to check and what action.
- **Mechanical enforcement boundaries** — what runs as a pre-commit hook, what runs post-merge, what runs scheduled, what stays manual ritual.
- **Audit logging** — how propagation activity is recorded and reviewed.
- **Failure modes** — what happens when propagation can't cleanly resolve.

The principle behind propagation: **stale documents are a system failure, not an editorial oversight.** The system itself is responsible for keeping the canon in sync; humans intervene only where mechanical rules can't resolve cleanly.

### Naming: PT-1 through PT-7 (disambiguated from "Tier")

This doc uses **PT-1 through PT-7** as the propagation trigger labels, renamed from the original T1-T7 to disambiguate from two other "T-prefixed" taxonomies in the doctrine + harness:

- **Work-sizing tiers** (`03-work-sizing.md`) use **Tier 1 through Tier 5** (T1-T5) to measure effort.
- **Mid-build decision tiers** (`~/.claude/rules/planning.md`) use **Tier 1 through Tier 3** (T1-T3) to measure reversibility.
- **Permission tiers** (`neural-lace/principles/permission-model.md`) use **T0-T3** to map composite risk score to action.

Three "T1" definitions in the same methodology was a naming collision waiting to happen. **Propagation triggers are now PT-1 through PT-7.** The methodology recommendation's glossary records this disambiguation; cross-references in other doctrine docs use the PT-N form going forward.

---

## Design philosophy

Three rules govern propagation design:

1. **Mechanical where possible, finding where not.** Every trigger has a default mechanical action where the rule can be applied deterministically. Where it cannot, the trigger opens a structured finding routed to the appropriate curator. Findings are never silently dropped (per anti-principle #14).

2. **Surface the change, not the chase.** A propagation event surfaces what changed and what depends on it. It does not require the change-author to chase down every consumer manually — that's exactly the failure mode propagation prevents.

3. **Audit everything.** Every propagation event logged: trigger, source, fired-at timestamp, dependent artifacts checked, action taken, outcome. This audit is what allows the knowledge integrator to detect doctrine gaps and propagation-rule gaps.

---

## Trigger taxonomy

Triggers fall into seven categories.

### PT-1. Contract change

A change to a public contract — module signature, schema, API endpoint, event payload, cross-repo shared type.

**Detected by:** diff in declared contract surfaces (engineering catalog tracks which surfaces are public); type-system signature change on exported symbols; schema migration.

**Harness implementation:** today, ad-hoc per-project — there is no NL hook generalizing PT-1 detection across project canon. NL's existing per-feature hooks (e.g., `migration-claude-md-gate.sh` opt-in for migration → CLAUDE.md update) implement narrow slices but not the framework. **Forthcoming Phase 1d-C: C12 (`propagation-trigger-router.sh`) — single PostToolUse hook reading `propagation-rules.json` listing triggers; auto-update where mechanical, opens findings where not.** C12 is the doctrine's biggest single mechanism opportunity per `outputs/unified-methodology-recommendation.md` §6.

### PT-2. Component addition or change

New component added to or existing component modified in the design system.

**Detected by:** diff in design system reference; new component used in code without prior design system entry (caught by design system consistency gate).

**Harness implementation:** today, pattern-only — design-system consistency lives in `~/.claude/rules/ux-standards.md` + `ux-design.md` + adversarial-review by `ux-designer` agent, but no hook detects "new component used without design-system entry." **Forthcoming Phase 1d-C: C12 (generalized router) plus C6 (design system consistency gate) — pre-commit hook scanning changed UI files for tokens/components against `docs/design-system.md`.** C6 depends on a per-project `docs/design-system.md` schema (longer-term project canon work; see `08-project-bootstrapping.md`).

### PT-3. ADR adoption

A new ADR moves from `proposed` to `accepted`, or an existing ADR moves to `deprecated` / `superseded`.

**Detected by:** status field change in any `docs/decisions/ADR-*.md` file.

**Harness implementation:** **NL's `decisions-index-gate.sh`** enforces atomicity at the file-system level — commits adding a decision record must update `docs/DECISIONS.md` index in the same commit; commits referencing a decision in the index must update the underlying record. This operationalizes PT-3 for the index-update slice; per the comparative analysis (D10 / A41), the gate covers the "index stays in sync" property but does NOT yet cover the broader "ADR status change → fan out to dependent catalog/Integration-Map/design-system entries" property. **Forthcoming Phase 1d-C: C12 (generalized router) plus C4 (ADR-adoption gate) — PreToolUse on `docs/decisions/NNN-*.md` requiring a `## Adversarial review` section before status flip from `proposed` → `accepted`.** Until C12 + C4 land, the broader fan-out is curator-mediated via findings.

### PT-4. Doctrine change

A principle, role definition, work-sizing tier, gate definition, or propagation rule itself changes.

**Detected by:** diff in `build-doctrine/doctrine/` files.

**Harness implementation:** **NL's `/harness-review` skill** is the closest current mechanism for PT-4 — a weekly self-audit that reviews harness changes for hygiene, drift, and missing-rule signals. Today the skill runs against NL's own canon and writes to `docs/reviews/`. The doctrine-change → downstream-project-recheck path is manual: when a doctrine doc changes at severity ≥ "structure," `/harness-review` should re-run on every downstream project to verify their canon is consistent with the new doctrine. This is one of the trigger types `07-knowledge-integration.md` (deferred per Q9) will formalize. **Forthcoming Phase 1d-C: C12 (generalized router) — auto-fan-out on PT-4 events to dependent doctrine docs and downstream project canon.** Until C12 lands, the discipline is pattern-only; the operator runs `/harness-review` manually after substantive doctrine edits.

### PT-5. Drift signal

A builder logged a drift entry (spec proved underspecified) or a runtime check (catalog consistency, Integration Map consistency) found mismatch between documented and actual state.

**Detected by:** drift log entries; scheduled consistency checks.

**Harness implementation:** today, pattern-only — drift logs are structured pattern entries the knowledge integrator reviews on ritual cadence; no hook surfaces drift in the per-session loop. The longer-term form requires telemetry-driven detection (HARNESS-GAP-10 sub-gap D blocks this until NL telemetry ships in 2026-08). Forthcoming: telemetry-feed for drift signals + scheduled consistency-check job firing C12 router on drift detection.

### PT-6. Findings pattern

The findings ledger contains a recurring pattern across multiple units suggesting doctrine, role, or gate revision.

**Detected by:** scheduled pattern analysis on the findings ledger.

**Harness implementation:** today, pattern-only — the findings ledger is itself paper-only (per `outputs/glossary.md`, "Currently the most-referenced UNIMPLEMENTED artifact in the doctrine; T3's C9 mechanism proposal operationalizes it"). **Forthcoming Phase 1d-C: C9 (`findings-ledger-schema-gate.sh`) — defines `docs/findings.md` schema; pre-commit hook validates entries; Stop hook scans for findings created in current session and verifies persistence.** Plus a knowledge-integrator agent in Phase 1d-E that runs scheduled pattern analysis once C9's ledger is populated.

### PT-7. Cross-repo edge change

A change to a contract surface that the Integration Map identifies as cross-repo. Distinguished from PT-1 because it requires propagation across repository boundaries with their own commit cycles.

**Detected by:** PT-1 detection plus Integration Map indicates one or more consumers in other repos.

**Harness implementation:** today, ad-hoc — there is no NL hook tracking cross-repo edges. **Forthcoming Phase 1d-C: C17 (cross-repo edge `pending propagation` blocker) — pre-push or pre-irreversibility hook reading propagation log for unresolved cross-repo edges; blocks ship until each consumer dispositions.** C17 depends on C12 (the propagation log) and on the Integration Map's cross-repo edge format. Until C17 lands, cross-repo propagation discipline is pattern-only.

---

## Propagation rules

For each trigger, the rule specifies: dependent artifacts to check, default action per artifact type, escalation path when default action cannot apply.

### PT-1. Contract change

| Dependent artifact | Default action |
|---|---|
| Contract tests on this side | Auto-run; failures block the unit |
| Contract tests on consuming side | Auto-run; failures open finding routed to consumer-side spec author |
| Engineering catalog entry for the contract | Auto-update if mechanical (signature change) — finding routed to catalog curator if interpretation needed |
| Integration Map nodes referencing this contract | Auto-update mechanical fields (signature) — finding for usage-pattern fields |
| Design system (if UI is downstream) | Finding routed to design system curator if any visible behavior changes |
| ADRs that reference this contract | Status check — if affected, finding for the catalog curator to evaluate ADR validity |
| Any PRDs referencing this contract via spec lineage | Finding routed to PRD owner |

### PT-2. Component addition or change

| Dependent artifact | Default action |
|---|---|
| Design system inventory | Auto-update with provenance metadata |
| Existing usages (for change/deprecation) | Finding per usage routed to design system curator with migration path |
| Engineering catalog (modules using the component) | No-op for additions; for deprecation, finding routed to catalog curator |
| Specs referencing the old component | Finding routed to spec author of each |
| Anti-patterns log | Finding for design system curator to evaluate whether new entry warranted |

### PT-3. ADR adoption

| Dependent artifact | Default action |
|---|---|
| Engineering catalog | Finding routed to catalog curator to update affected entries |
| Integration Map (if topology changes) | Finding routed to catalog curator |
| Design system (if pattern affects UI) | Finding routed to design system curator |
| Doctrine (if pattern conflicts with existing doctrine) | Finding routed to knowledge integrator |
| Older ADRs being superseded | Auto-update status to `superseded by ADR-NNN` |
| Existing code using older pattern | Finding routed to engineering catalog curator with migration scope estimate |
| `docs/DECISIONS.md` index | Atomic update in same commit (NL `decisions-index-gate.sh`) |

### PT-4. Doctrine change

| Dependent artifact | Default action |
|---|---|
| Other doctrine docs that cross-reference the changed section | Auto-check reference integrity; finding for knowledge integrator if reference now invalid |
| Per-project templates that reference this doctrine | Finding for templates that may need version bump |
| Existing PRDs / specs / ADRs in flight | Finding for owner of each in-flight artifact |
| CHANGELOG | Auto-append entry with source, rationale, date |
| Knowledge integration ritual queue | Finding logged for next ritual cycle |
| Downstream project canon (every adopting project) | At severity ≥ "structure", `/harness-review` re-run per project (manual today; auto-trigger forthcoming via C12) |

### PT-5. Drift signal

| Dependent artifact | Default action |
|---|---|
| The artifact whose drift was detected | Finding with the specific drift instance |
| Spec author of the unit (if drift came from underspecified spec) | Finding routed for spec revision consideration |
| Knowledge integrator queue | Finding logged for pattern detection in periodic review |
| Doctrine (if drift suggests systemic gap) | Held for knowledge integrator triage; not an immediate action |

### PT-6. Findings pattern

| Dependent artifact | Default action |
|---|---|
| Knowledge integrator queue | Finding routed with the pattern characterization, sample entries, and frequency |
| Doctrine (potential principle, role, gate, or propagation-rule revision) | Held for ritual; not immediate |
| Project-specific configuration (if pattern is project-local) | Finding routed to project's catalog curator |

### PT-7. Cross-repo edge change

All PT-1 actions, plus:

| Dependent artifact | Default action |
|---|---|
| Consumer repos identified in Integration Map | Finding opened in each consumer repo's findings ledger; cross-repo edge marked as `pending propagation` until each consumer dispositions |
| Integration Map cross-repo edge | Status updated to `pending propagation` until all consumers acknowledge |
| Backward-compatibility test fixtures | Auto-run; failures block irreversibility approval |

Cross-repo propagation is the only category where the rule explicitly does **not** auto-resolve, even when all signatures match — consumers must acknowledge so cross-repo silent breakage is impossible.

### Composition with NL's `/harness-review` skill

When a doctrine change of severity ≥ "structure" fires (PT-4), `/harness-review` should re-run on every downstream project to verify their canon is consistent with the new doctrine. The skill (defined at `~/.claude/skills/harness-review.md` per NL adapter conventions) is today the closest mechanism to a doctrine-fan-out propagation hook:

- The skill scans the project's harness state for drift, missing rules, hygiene violations, and stale references.
- It reads `docs/failure-modes.md` to check whether new doctrine guidance addresses observed failure classes.
- It writes a dated review to `docs/reviews/YYYY-MM-DD-<slug>.md`.

For doctrine changes that affect multiple downstream projects, the operator runs `/harness-review` on each one and compares the diffs in the review files. **Manual today; could be automated post-Phase 1d-E** once a project-list registry exists in NL state. The forthcoming `07-knowledge-integration.md` will formalize this trigger type.

---

## Mechanical enforcement boundaries

Where each rule is enforced determines latency and reliability.

### Pre-commit hooks

Run on the developer's machine before a commit lands. Fail-closed: commit blocked until passing.

- Schema validation (1.4)
- Frontmatter completeness (1.6)
- Format (1.3)
- Lint at error severity (1.2)
- Type check (1.1) when fast
- Doctrine cross-reference integrity (PT-4 reference checks)
- Scope enforcement (1.5) where the diff allowlist can be evaluated locally

### Pre-push hooks / pre-merge gates

Run before code reaches the shared branch. Fail-closed.

- Full unit test suite (2.1)
- Full type check if pre-commit was a fast subset
- Contract tests for any touched boundary (2.3) — both sides if mono-repo
- Mutation tests on declared hot paths (2.5)
- Engineering catalog consistency (3.4) at error severity
- Design system consistency (3.5)
- Adversarial review pass (4) — the gate, not necessarily fully synchronous

### Post-merge actions

Fired by CI/CD on successful merge to a designated branch. Fail-open initially (don't block merge), but open findings.

- Cross-repo propagation events (PT-7) — opens findings in consumer repos
- Integration Map runtime verification — opens finding if drift detected
- Findings ledger pattern analysis incremental update
- CHANGELOG auto-entry for doctrine changes (PT-4)

### Scheduled jobs

Run on a defined cadence (daily / weekly).

- Findings ledger pattern analysis (PT-6) — full pass
- Engineering catalog runtime drift detection (PT-5)
- Integration Map runtime verification (PT-5) — full pass
- Cross-reference integrity audit across all artifacts
- Escape hatch usage pattern review

### Manual ritual

Run by humans on a defined cadence per `07-knowledge-integration.md`.

- Knowledge integration ritual (doctrine evolution)
- Findings ledger triage review
- Drift log review for systemic patterns
- Escape hatch audit

### Cross-reference: NL hooks implementing narrow slices today

The doctrine's framework is broader than what NL ships today. The four NL hooks below implement narrow, high-traffic slices of the propagation framework — they cover specific propagation paths without generalizing to a 7-trigger taxonomy:

- **`plan-lifecycle.sh`** (PostToolUse on plan-file edits) — handles plan-file lifecycle propagation: plan creation → in-progress → terminal-status → archive directory. When a plan's `Status:` flips to a terminal value, the file moves to `docs/plans/archive/` in the same edit cycle. This implements one slice of PT-3-adjacent state propagation (decision-record adoption ↔ plan-completion archival).
- **`plan-edit-validator.sh`** (PreToolUse on plan-file edits) — enforces evidence-first protocol with flock for parallel verifiers. Implements the per-plan-file slice of PT-1 + PT-3 propagation: only `task-verifier` flips checkboxes; evidence blocks and checkboxes update atomically.
- **`decisions-index-gate.sh`** (pre-commit on decision records and DECISIONS.md) — enforces atomicity: commits adding a decision record must update `docs/DECISIONS.md` index in the same commit. Implements the index-update slice of PT-3.
- **`docs-freshness-gate.sh`** (pre-commit on structural changes) — flags when structural changes ship without docs staged. Implements a narrow slice of PT-4 (doctrine-change-class) for in-repo docs.

The doctrine's framework is broader (PT-1 through PT-7 across all canon categories — engineering catalog, Integration Map, design system, ADRs, doctrine, drift logs, findings ledger, cross-repo edges); these hooks cover specific high-traffic propagation paths. **The forthcoming C12 (`propagation-trigger-router.sh`) is the generalized form** — single PostToolUse hook reading `propagation-rules.json` that subsumes the four narrow hooks above into one configurable router.

---

## Audit logging

Every propagation event writes an entry with:

- **Trigger ID** — which trigger fired (PT-1 through PT-7).
- **Source artifact** — file path or entity ID that originated the trigger.
- **Fired at** — timestamp.
- **Dependents identified** — list of artifacts checked.
- **Actions taken** — per-dependent: auto-update applied / finding opened (with finding ID) / no-op recorded with rationale.
- **Outcome status** — `complete` / `pending` (cross-repo waiting on consumers) / `failed` (no clean path, halted).

The propagation log is append-only, machine-written, human-readable. Lives at `build-doctrine/telemetry/propagation.jsonl` per project (or shared with neural-lace `telemetry/` if the integration pass shows that's cleaner).

The knowledge integrator reviews the propagation log on the ritual cadence to identify:

- Triggers that frequently can't auto-resolve (suggests rule refinement).
- Dependents that are repeatedly out of sync (suggests artifact restructuring).
- Cross-repo edges with persistently slow propagation (suggests Integration Map or coordination process gap).

**Harness implementation:** today, no propagation log exists; the four narrow NL hooks listed above each emit their own per-hook signals (commit blocks, stderr messages, system-message warnings) but no unified ledger aggregates them. **Forthcoming Phase 1d-C: C12 (generalized router) writes to `build-doctrine/telemetry/propagation.jsonl`** following the schema above. C9 (findings-ledger schema gate) is the prerequisite for the per-finding linkage.

---

## Failure modes

### Trigger fires but no dependents found

Two interpretations: the trigger is over-broad (logging without action), or the catalog is incomplete (dependents exist but aren't tracked). Default action: log the no-op event and route to the engineering catalog curator for review. Persistent no-op events flag for knowledge integrator (rule may need refinement or removal).

### Trigger fires but rule has no action defined

Halts the run. This is a doctrine bug, not a runtime issue. Logs an explicit `propagation rule gap` finding routed to the knowledge integrator with severity `severe`. The build doesn't proceed until the gap is filled, even if temporarily by a manual finding.

### Auto-update would conflict with concurrent change

Default action: open a finding routed to the appropriate curator with both versions visible. Do not auto-resolve; the merge is a human decision.

### Cross-repo consumer doesn't acknowledge

Cross-repo edge stays in `pending propagation` indefinitely. The Integration Map shows the unresolved state. The originating change cannot pass irreversibility approval until either all consumers acknowledge or the originating spec explicitly declares an intentional break with a migration plan.

### Audit log write fails

Halts the run immediately. Audit integrity is non-negotiable; a propagation event that fired but wasn't logged is worse than one that didn't fire at all (the system has acted but lost the record).

---

## Anti-patterns

### Propagation as suggestion

Treating propagation as advisory ("you might want to check the catalog") rather than mandatory action with audit trail. The whole point is that the system enforces sync, not that it asks nicely.

### Auto-update without provenance

Auto-applying a change to a dependent without recording why (which trigger, which source). The mechanical action is fine; the missing audit entry is the failure.

### Propagation by chat

Surfacing a propagation need in conversation ("hey, this contract changed, you should update the catalog") rather than as a structured trigger event with a logged outcome. Same anti-pattern as anti-principle #14: information that should be in the ledger / audit log lives in chat instead.

### Findings without ownership

A propagation event opening a finding without a specified curator. Every finding has an owner; un-owned findings rot.

### Rule sprawl

Adding propagation rules ad hoc without the knowledge integration ritual. Rules accumulate, contradict, and become unmaintainable. New rules graduate through the same ritual as doctrine changes.

---

## Open during fresh-draft phase

- **Cross-project propagation.** When two projects under different repos both consume the same shared library or contract, propagation across project boundaries needs explicit support. The Integration Map handles this within a project; cross-project requires either a shared catalog tier or a federation pattern. Drafted lightly; specifics in templates phase.
- **Propagation budget.** A naive implementation could fan out to expensive operations. Budget caps and prioritization rules deferred until pilot reveals actual cost.
- **the personal-knowledge tool as audit consumer.** Per Q11 (methodology recommendation): the personal-knowledge tool is OUT of scope for harness-meta. AI harness metadata, including propagation log analysis, lives in Neural Lace. The propagation log is itself a high-value `/harness-review` ingest source — patterns across projects, recurring rule gaps, etc. are surfaced there rather than in the personal-knowledge tool.
- **Integration with neural-lace `learning/`.** The harness's self-improvement engine (today expressed via `enforcement-gap-analyzer` + `harness-reviewer` agents on every Gen 5 runtime FAIL) likely already has trigger / event semantics. C12's `propagation-rules.json` schema design must reconcile with these existing self-improvement signals; this is a Phase 1d-C design question.

## Next step

This document is integrated v1. Next: Phase 1d-C lands C12 (`propagation-trigger-router.sh`), C5 (engineering catalog / Integration Map consistency gate), C6 (design system consistency gate), C9 (findings-ledger schema gate), and C17 (cross-repo edge `pending propagation` blocker) — the mechanism stack that operationalizes the framework specified here.
