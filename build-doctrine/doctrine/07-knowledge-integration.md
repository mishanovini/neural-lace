---
title: Build Doctrine — Knowledge Integration Ritual
status: integrated v1 (Tranche 5a — process + triggers + versioning shipped; cadence + canon-incorporation tagged as hypothesis pending Tranche 4 pilot evidence)
owner: misha
last_review: 2026-05-06
sources:
  - drafted as Tranche 5a of the Build Doctrine integration arc, parallel to Tranche 6a (propagation engine framework). The decomposition logic mirrors 6a's: ship the structurally-derivable parts now; defer evidence-driven refinement to Tranches 5b/5c.
  - composes with 01-principles.md (especially #8 and #9), 02-roles.md (Role 9 — Knowledge Integrator), 06-propagation.md (PT-4 doctrine-change trigger).
references:
  - build-doctrine/doctrine/02-roles.md (Role 9 — Knowledge Integrator)
  - build-doctrine/doctrine/06-propagation.md (PT-4 trigger; the propagation engine surfaces changes; this ritual processes them)
  - ~/.claude/rules/calibration-loop.md (Tranche G — observation capture)
  - ~/.claude/rules/findings-ledger.md (Tranche 1 — finding capture)
  - ~/.claude/rules/discovery-protocol.md (Tranche 1d-D — discovery capture)
  - ~/.claude/skills/harness-review.md (existing periodic-audit skill — extends in 5a as ritual driver)
  - docs/decisions/queued-tranche-1.5.md (G.1 — calibration storage; the 5a ritual extends the bootstrap pattern from G to doctrine-level)
revision_notes:
  - 2026-05-06 v1: Tranche 5a — process shape + trigger taxonomy + cadence-as-hypothesis + versioning policy. Cadence numbers (monthly default) and trigger thresholds (N=3 calibration, M=3 findings within 7 days) are explicitly conjectural per AP16 mitigation. To be revised in Tranche 5b based on pilot evidence.
---

# Build Doctrine — Knowledge Integration Ritual

## Scope

This document defines **how the doctrine itself evolves over time** — the process by which observations from running projects flow back into doctrine revisions, with audit trail and explicit decision authority.

**This is not a process for evolving project canon (engineering catalog, design system, conventions per project).** That's per-project work governed by 06-propagation.md's PT-1 through PT-7 triggers and the propagation engine. **This is a process for evolving the doctrine itself** — the universal layer above project canon.

The ritual operationalizes Role 9 (Knowledge Integrator) from `02-roles.md` and Principle 9 ("Documents are living; updates propagate on trigger") from `01-principles.md`.

### What ships in Tranche 5a (this document, v1)

- **Process shape** — propose → review → land flow for doctrine changes
- **Trigger taxonomy** — what surfaces "doctrine should be revised" signals from existing capture substrate
- **Cadence as documented hypothesis** — initial numbers explicitly tagged conjectural
- **Versioning policy** for `build-doctrine-templates/` — semver with pinning convention

### What waits for Tranche 5b (pilot evidence)

- Cadence calibration — was monthly the right default? Did triggers fire faster than expected?
- Threshold tuning — was N=3 calibration entries too eager / too rare?
- Canon-incorporation mechanism — re-run bootstrap vs. selective sync (needs real pilot canon to evaluate)

### What waits for Tranche 5c (telemetry)

- Auto-detection of doctrine-change triggers from accumulated telemetry
- Cross-project pattern detection (the canonical pilot project's findings vs. other projects' findings)

---

## Design philosophy

Three rules govern ritual design:

1. **The ritual operates on existing capture substrate.** Today: calibration entries (Tranche G), findings ledger (C9), discovery files (1d-D), ADR adoption events (PT-3), and `/harness-review` outputs. Tomorrow: propagation engine audit log (Tranche 6a), telemetry (HARNESS-GAP-11). The ritual does not create new capture — it consumes what exists and what's coming online.

2. **Hypothesis-marker discipline.** Every cadence number, threshold, or boundary in this document carries an explicit `(hypothesis, pending pilot evidence)` tag. This prevents conjectural specs from hardening into locked rules. Revising a hypothesis is structural; revising a "this was wrong from the start" lock is embarrassing and invites resistance to revision.

3. **Process audit-trail is mandatory.** Every doctrine change has source, rationale, and date — the same discipline that anti-anonymous-changes (Role 9) requires. The ritual does not bypass this; it routes changes through audit-trail-preserving channels (ADRs + commits + decision-records).

---

## Trigger taxonomy

Triggers map to existing capture substrate. Each trigger carries (a) what fires it, (b) the threshold for review escalation, (c) the doctrine area most-likely affected.

### KIT-1. Calibration-pattern trigger

**Source:** `.claude/state/calibration/<agent-name>.md` files (Tranche G).

**Threshold (hypothesis, pending pilot evidence):** ≥ 3 same-class observations within 14 days for the same agent → review trigger for the agent's prompt or the rule that governs its behavior.

**Doctrine area most-likely affected:** `02-roles.md` role-attribute updates; `~/.claude/agents/<name>.md` prompt extensions (which are downstream of doctrine but flow through the ritual when the pattern is doctrine-shaped).

**Example:** if `task-verifier` accumulates 3 `pass-by-default` observations in 14 days, the ritual surfaces a review-trigger to examine whether the agent's Counter-Incentive Discipline section needs strengthening.

### KIT-2. Findings-pattern trigger

**Source:** `docs/findings.md` (Tranche 1's C9 ledger) — six-field schema (id / severity / scope / source / location / status).

**Threshold (hypothesis, pending pilot evidence):** ≥ 3 similar findings within 7 days touching the same doctrine area → review trigger for that doctrine area.

**Doctrine area most-likely affected:** depends on the findings cluster. Drift findings → `06-propagation.md` rule-set; gate-failure findings → `04-gates.md` gate definitions; spec-incompleteness findings → `08-project-bootstrapping.md` floor coverage.

**Example:** 3 findings within a week all flagging "spec underspecified for X edge case" → ritual surfaces a review-trigger to examine whether `08-project-bootstrapping.md`'s universal floors need an additional category.

### KIT-3. Discovery-accumulation trigger

**Source:** `docs/discoveries/YYYY-MM-DD-*.md` files (Tranche 1d-D).

**Threshold (hypothesis, pending pilot evidence):** ≥ 5 process-class discoveries OR ≥ 3 architectural-learning-class discoveries → review trigger for the harness rule or doctrine principle the discoveries touch.

**Doctrine area most-likely affected:** `01-principles.md` principle additions or anti-principle additions (this is exactly how AP16 was added in Tranche 1.5); `~/.claude/rules/<name>.md` rule extensions.

**Example:** 3 architectural-learning discoveries in 30 days about the same harness-internal pattern → ritual surfaces a review-trigger to examine whether the pattern needs a principle.

### KIT-4. ADR-cross-reference staleness trigger

**Source:** `docs/decisions/NNN-*.md` adoption events (PT-3 propagation byproduct) where the new ADR's cross-references reveal stale text in earlier doctrine docs.

**Threshold:** any single ADR adoption that cites a doctrine doc text fragment that no longer matches current state → immediate review trigger (no accumulation needed; the ADR is the trigger artifact).

**Doctrine area most-likely affected:** the doctrine doc(s) the ADR cross-references.

**Example:** ADR 028 adopts a new principle that contradicts wording in `04-gates.md` → ritual surfaces a review-trigger to update `04-gates.md` (or to escalate the contradiction for resolution before ADR 028 lands).

### KIT-5. /harness-review skill trigger

**Source:** `/harness-review` skill outputs (existing) writing dated reviews to `docs/reviews/YYYY-MM-DD-<slug>.md`.

**Threshold:** any harness-review run that flags ≥ 3 narrative-doc-stale entries OR ≥ 1 missing-rule entry → review trigger.

**Doctrine area most-likely affected:** narrative docs (README, CLAUDE.md, harness-strategy, etc.); harness rules and agents.

**Example:** weekly `/harness-review` flags that 3 user-facing narrative docs are stale post-Build-Doctrine-integration → ritual surfaces a review-trigger to schedule a doc-sweep (this is exactly what HARNESS-GAP-17 captured).

### KIT-6. Propagation-engine audit-log trigger (Tranche 6a-dependent)

**Source:** `build-doctrine/telemetry/propagation.jsonl` (Tranche 6a's audit log, when shipped).

**Threshold (hypothesis, pending Tranche 6a + pilot evidence):** ≥ 5 PT-N events in 7 days for the same trigger type AND ≥ 30% of those resolved by `finding opened (curator-mediated)` rather than auto-update → review trigger for the propagation rule.

**Doctrine area most-likely affected:** `06-propagation.md` rule-set; `propagation-rules.json` config.

**Example:** if 8 PT-1 events fire in a week and 4 of them require curator finding-routing (auto-update couldn't apply), the rule may be over-broad or the dependent set incomplete — ritual surfaces a review-trigger.

### KIT-7. Drift-signal trigger (Tranche 5c-dependent)

**Source:** scheduled drift-detection telemetry (HARNESS-GAP-11, gated 2026-08).

**Threshold:** to-be-defined when telemetry ships.

**Doctrine area most-likely affected:** all doctrine docs; cross-project patterns.

**Status:** placeholder; refined in Tranche 5c.

---

## Cadence

### Monthly review (hypothesis, pending pilot evidence)

The Knowledge Integrator (Role 9) runs a scheduled review **once per calendar month**. The review:

1. Reads the ritual's trigger sources (calibration, findings, discoveries, ADR adoptions, harness-review outputs, propagation audit log when available).
2. Aggregates triggered review-events from the prior month.
3. For each, drafts a proposed doctrine change OR explicitly closes the trigger as no-action with rationale.
4. Surfaces drafts to the user (the human approver per Role 9's "human-led, LLM-assisted" type) for review.
5. Lands accepted changes via the propose → review → land flow below.
6. Writes a monthly ritual-log entry at `build-doctrine/telemetry/knowledge-integration-log.md` (append-only; created on first ritual run).

**Why monthly (hypothesis):** reasoning rate of doctrine evolution. Faster than monthly risks churn — doctrine changes propagate to projects, and frequent propagation creates project friction (PT-4 fan-out cost). Slower than monthly risks signal-rot — accumulated triggers lose context if not addressed within ~30 days.

**Why this is conjectural:** without pilot evidence about how often triggers actually fire, monthly is a guess. If the canonical-project pilot generates 3 doctrine-shape findings per week, monthly is too slow. If it generates 1 per quarter, monthly is too fast (most months would have nothing to review). Tranche 5b revises this once pilot evidence accumulates.

### On-demand review (always available)

Any of the following bypass the monthly cadence and trigger an immediate ritual run:

- **KIT-4 (ADR cross-reference staleness)** — the ADR is the trigger artifact; it should not wait for the next monthly run.
- **Any trigger flagged severity: critical** in its source artifact (e.g., a finding tagged severity: critical in the findings ledger).
- **User explicit invocation** — running `/harness-review` with a specific doctrine area in scope.

---

## Process: propose → review → land

The ritual routes doctrine changes through a structured flow with the same audit-trail discipline as ADR adoption.

### Stage 1 — Propose

The Knowledge Integrator (or any contributor) drafts a proposed doctrine change as a new entry under `build-doctrine/proposals/YYYY-MM-DD-<slug>.md` (directory created on first proposal).

The proposal carries:

```yaml
---
proposal_id: YYYY-MM-DD-<slug>
proposed_by: misha | claude | <other-contributor>
trigger_source: <KIT-1 through KIT-7, OR ad-hoc>
trigger_evidence: <link to specific calibration entries, finding IDs, discovery files, ADR, or harness-review section that surfaced this>
affected_doctrine_areas:
  - <doctrine doc paths>
proposed_change_class: addition | modification | retirement | clarification
status: draft
---

## What the change is

<concrete diff-style description of the doctrine change>

## Why (citing trigger evidence)

<explicit reasoning tying the change to the trigger evidence — not "I think this would be nice"; specifically "X observation surfaced N times in M days, current doctrine cannot account for it, proposed change addresses">

## Who is affected

<which projects, roles, gates the change touches>

## Reversibility

<explicit statement: REVERSIBLE / IRREVERSIBLE>
```

### Stage 2 — Review

The user (Role 9 human-approver) reviews the proposal. Possible verdicts:

- **APPROVE** — accept as proposed; advance to Stage 3.
- **APPROVE-WITH-AMENDMENTS** — accept with named changes; the integrator revises and re-submits.
- **DEFER** — accept the underlying observation but defer the change (proposal status flips to `deferred` with rationale).
- **REJECT** — reject with rationale (proposal status flips to `rejected`; not deleted — preserved for audit).

The user's verdict is logged in the proposal file's revision_notes.

### Stage 3 — Land

For APPROVED proposals:

1. **Doctrine commit:** the integrator (or LLM-assisted from the proposal) writes the actual doctrine-doc edit. Lands as a commit citing the proposal_id.
2. **ADR if material:** if the change is Tier 2+ per `~/.claude/rules/planning.md`'s decision-record mandate, an ADR lands in the same commit at `docs/decisions/NNN-<slug>.md` with `Source: knowledge-integration-ritual` in its frontmatter.
3. **Propagation:** the doctrine change is itself a PT-4 propagation event. When Tranche 6a's propagation engine ships, the engine fans out the change to dependent doctrine docs and downstream project canon. Until then, `/harness-review` is the closest mechanism (manually re-run on each downstream project).
4. **Versioning:** if the change touches `build-doctrine-templates/` content, the templates repo's VERSION file bumps per the versioning policy below.
5. **Proposal closure:** the proposal file's status flips to `landed` with the commit SHA.

---

## Versioning policy: `build-doctrine-templates/`

### Semantic versioning with pinning

`build-doctrine-templates/VERSION` carries a semver string `MAJOR.MINOR.PATCH`.

- **MAJOR** — template-shape change. Existing project canon needs revisions to remain valid against the new shape. Projects pin the prior version; opt-in re-bootstrap is the migration path.
- **MINOR** — additive content. New floors, new architectural defaults, new naming-convention defaults. Existing project canon remains valid; projects opt-in to the new content.
- **PATCH** — clarifications, typo fixes, non-content edits to existing template entries. Projects automatically pick up patches when they sync templates.

### Pinning convention

Each project's `.bootstrap/state.yaml` carries:

```yaml
templates_version: <pinned semver>
```

Projects pin a version at bootstrap. Sync to a new version is an explicit opt-in (project ships an ADR + a re-bootstrap if MAJOR; just an opt-in commit if MINOR/PATCH).

### Template change → ritual entry mapping

Every templates-repo change lands via a Tranche 5a proposal (Stage 1-3 above). The proposal cites which templates-floor changed, which projects pin the prior version, and what the migration path is (PATCH = automatic; MINOR = opt-in commit; MAJOR = re-bootstrap recommended).

### What's deferred to Tranche 5b

The actual mechanism by which projects sync to new templates versions — re-run bootstrap from scratch vs. selective floor-by-floor sync — is **deferred to Tranche 5b** because it depends on pilot evidence about which approach works in practice. The current docs say "re-bootstrap is the migration path" for MAJOR, but the precise procedure (how `.bootstrap/state.yaml` reconciles with new template defaults; what conflicts trigger user review; what stays untouched) is conjectural until a real project does it.

---

## How project canon incorporates updates (deferred to Tranche 5b)

Per the original Phase 5 scope, this section would specify:

- Re-run bootstrap from scratch vs. selective sync per floor
- Which template-version-bump kinds require which migration paths
- Conflict resolution when project canon diverges from new template defaults
- Audit-trail discipline for canon-update events

**Status:** explicitly deferred to Tranche 5b. The canonical-project pilot generates the empirical evidence that informs the right answer. Authoring this from imagination would be exactly the AP16 anti-pattern this entire ritual is designed to catch — speccing a process before observing the work it must support.

---

## Cross-references

- **Role 9 spec:** `build-doctrine/doctrine/02-roles.md` — Knowledge Integrator decision authority and harness implementation
- **Principle 9 spec:** `build-doctrine/doctrine/01-principles.md` — "Documents are living; updates propagate on trigger"
- **Anti-Principle 16:** same file — "Reactive enforcement compounding" — the AP this ritual mitigates against by hypothesis-marker discipline
- **Propagation engine spec:** `build-doctrine/doctrine/06-propagation.md` — PT-4 doctrine-change trigger; this ritual's KIT-6 trigger consumes the propagation engine's audit log
- **Calibration loop:** `~/.claude/rules/calibration-loop.md` — Tranche G; KIT-1 trigger source
- **Findings ledger:** `~/.claude/rules/findings-ledger.md` — C9 from Tranche 1; KIT-2 trigger source
- **Discovery protocol:** `~/.claude/rules/discovery-protocol.md` — Tranche 1d-D; KIT-3 trigger source
- **`/harness-review` skill:** `~/.claude/skills/harness-review.md` — KIT-5 trigger source
- **Tranche 5a plan:** `docs/plans/build-doctrine-tranche-5a-knowledge-integration-ritual.md` (when authored)
- **Q9 sequencing decision:** `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §9 Q9 — this Tranche 5a partially overrides Q9 by shipping the structurally-derivable parts; Q9's full-deferral applies to Tranches 5b + 5c.

---

## Failure modes

### Trigger fires but no proposal materializes

The Knowledge Integrator either missed the trigger or judged it inactionable. Default: trigger evidence remains in its source artifact (calibration entry, finding, discovery, etc.); next monthly review reconsiders. Persistent ignored triggers (3+ months without action) flag for the human approver: either the trigger threshold is wrong (lower it), the source artifact's signal-to-noise is wrong (re-tune), or the area genuinely doesn't need doctrine change (close the trigger as `no-action` with rationale).

### Proposal lands without trigger evidence

Doctrine change happens via direct commit, bypassing the propose → review → land flow. **This is a hygiene violation** — every doctrine change must have source, rationale, and date per Role 9. The fix: open a retroactive proposal entry citing the commit SHA, and in future, route through Stage 1 first.

### Proposal contradicts existing doctrine

The propose-stage carries `affected_doctrine_areas`; if reviewing reveals contradiction with another doctrine doc, the proposal must address the contradiction explicitly (modify both docs, or pick which wins, or escalate to user for arbitration). Silent contradiction is forbidden.

### Cadence misfires (too fast / too slow)

The 5b revision target. Until pilot evidence accumulates, the monthly cadence is a hypothesis; if it's clearly wrong (every monthly run has nothing to do, or every monthly run feels overwhelmed), surface the observation as a KIT-3 (process-class) discovery and schedule a 5b revision sooner than the original gating implies.

### Templates version-bump without project propagation

A new templates version lands but downstream projects don't sync. Status: known limitation until Tranche 6b (propagation engine PT-4 rules) ships. Manual mitigation: when bumping VERSION, the integrator manually creates findings in each pinned-prior-version project's `docs/findings.md` to surface the available update.

---

## Status of this document

**Tranche 5a — shipped 2026-05-06.** Process shape, trigger taxonomy, cadence-as-hypothesis, versioning policy.

**Pending Tranche 5b** (gated on canonical-project pilot empirical evidence): cadence calibration, threshold tuning, canon-incorporation mechanism, KIT-6 threshold refinement.

**Pending Tranche 5c** (gated on HARNESS-GAP-11 telemetry, 2026-08): KIT-7 drift-signal trigger; cross-project pattern detection.

This document is itself subject to the ritual it describes. Future revisions land via the propose → review → land flow with the trigger source explicitly cited.
