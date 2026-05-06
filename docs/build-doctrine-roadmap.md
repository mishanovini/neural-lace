# Build Doctrine + NL Integration — Roadmap

**Last updated:** 2026-05-05
**Owner:** Misha
**Status:** ACTIVE — primary tracker for end-to-end completion of the Build Doctrine integration into Neural Lace
**Source of truth:** this file. Other artifacts (per-phase plan files in `docs/plans/`, the Build Doctrine plan in `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md`, decision records 011-024) are referenced from here, not the other way around.

> **For Claude sessions:** read this file first when picking up Build Doctrine integration work. The "Current focus" section names the next pickup; the "How to update this doc" section at the bottom names the discipline for keeping it current.

---

## Quick status table

| Tranche | Description | Status | Plan file (when active) | Completed in |
|---|---|---|---|---|
| **0a** | Doctrine drafts (Phase 2a-2d, 1a, 1b, 1c, 1d-A, 1d-B) — produced 8 integrated-v1 docs + 4 analysis artifacts | ✅ DONE | n/a (Build Doctrine repo) | 2026-04-29 to 2026-05-03 |
| **0b** | Phase 0 — migrate doctrine docs into NL + create `build-doctrine-templates/` directory + activate definition-on-first-use scope | ✅ DONE | (archived) | 2026-05-05 |
| **1** | Phase 1d-C — 8 first-pass C-mechanisms (C1, C2, C7, C9, C10, C15, C16, C22) | ✅ DONE | (archived) | 2026-05-03 to 2026-05-04 |
| **1.5** | **Architecture simplification — apply doctrine to harness self-development.** 7 sub-tranches: A (incentive redesign), B (mechanical evidence), C (work-shape library), D (risk-tiered verification), E (deterministic close-plan), F (failsafe audit), G (calibration loop). | 🔄 6/7 SUB-TRANCHES SHIPPED — F PENDING (closure of A-E+G via close-plan.sh deferred to next session as live acceptance test) | [`docs/plans/architecture-simplification.md`](plans/architecture-simplification.md) — see ADR 026 + ADR 027 | A: `e352556`; B: `35ee3df`; C: `419c902`; D: `f4b818f`; E: `5938a69` (**2.8 sec closure benchmark**); G: `f83b56a`; F: pending |
| **2** | Phase 4a — Layer B-shape: 7 template schemas | ❌ NOT STARTED | (TBD: `docs/plans/build-doctrine-phase-4a-template-schemas.md`) | — |
| **3** | Phase 4b — Layer B-content: seed `build-doctrine-templates/` with default content for 11 universal floors × 3 depths | ❌ NOT STARTED | (TBD) | — |
| **4** | Phase 6 — canonical pilot project pilot | ❌ NOT STARTED | (TBD; plan lives in the pilot project's repo, references doctrine in NL) | — |
| **5** | Phase 5 — Author `07-knowledge-integration.md` (gated on Phase 6 per Q9) | ❌ NOT STARTED | (TBD) | — |
| **6** | Phase 7 — Minimal orchestrator (~300-500 LOC Python) + propagation engine (C12 generalized router) | ❌ NOT STARTED | (TBD) | — |
| **7** | The remaining 14 second-pass C-mechanisms (C3-C8, C11-C14, C17-C21) | ❌ NOT STARTED | (TBD; many subsumed by Tranche 6) | — |

**Headline status (2026-05-05):** the *enforcement substrate* (Tranche 1) is complete. The *foundation step* (Tranche 0b — migrating the doctrine docs into NL) is overdue and is the next pickup. The *content layer + pilot + orchestrator* (Tranches 2-6) is future work and represents the bulk of remaining effort.

---

## Current focus

**Next pickup: Tranche 0b — Phase 0 migration.** Foundation step that should have shipped weeks ago. Closing it activates `definition-on-first-use-gate.sh` (currently scoped to `neural-lace/build-doctrine/**/*.md` but with no in-scope files) and gives every doctrine reference in NL a real path to resolve to.

**Why this is next, not Tranche 2:** every later tranche references the doctrine. If the doctrine docs aren't accessible from inside NL, every reference is a broken link or a cross-repo lookup. Migration is also the cheapest tranche — ~1-2 hr — and unblocks everything else.

**Concurrent / blocked work:**
- HARNESS-GAP-08 (spawn-task-report-back convention) — currently in flight on `verify/pre-submission-audit-reconcile` branch. Tasks 1-4 shipped; Tasks 5-6 (sync to `~/.claude/`, commit) remaining. Should be closed before Tranche 0b starts so the branch isn't carrying two concurrent multi-task efforts.
- HARNESS-GAP-13 (hygiene-scan expansion Layers 1-4) — currently in flight on same branch. Layers 1-4 shipped; closure bookkeeping remaining (task-verifier on each, completion report, Status: COMPLETED).
- HARNESS-GAP-17 Part A (this session's narrative doc sweep) — work done, plan file authored, closure bookkeeping deferred to a future session.
- HARNESS-GAP-16 (closure-validation gate) — scheduled next-after-GAP-13. Specifically addresses the closure-bookkeeping discipline gap that produced the three open ACTIVE plans above.

**Recommended order:** close GAP-08 → close GAP-13 → close GAP-17 → ship GAP-16 → start Tranche 0b. The closure-validation gate (GAP-16) is the structural fix for "no single session owns end-to-end completion" — the user's core complaint that motivated this roadmap. Building it BEFORE the next major arc means the next arc benefits from the discipline.

---

## How to use this doc

### As a user (Misha)

- **At session start:** read the Quick status table + Current focus section. Know where we are.
- **At session end:** check that "Last updated" is today's date and Current focus reflects what just happened.
- **When picking up cold:** the Current focus section is the answer to "what should the next session work on?"

### As a Claude session

When this file is in scope at session start (e.g., user references it, or `Status: ACTIVE` plans reference it):

1. **Read this file first.** Quick status, current focus, blocked items.
2. **Read the named plan file (if any) for the active tranche.** Current focus's "Plan file" column points at it.
3. **Do the work** — but stay within the active tranche's plan unless the user explicitly redirects.
4. **At session end:**
   - If a tranche's status changed (NOT STARTED → IN PROGRESS → DONE), update the Quick status table.
   - If Current focus changed, update that section.
   - Update "Last updated" to today's date.
   - One-line entry under "Recent updates" at the bottom describing what shipped.

### How tranches relate to NL plan files

Each tranche corresponds to a focused work effort. The plan-creation + status-flip + roadmap-update flow is **deterministic — part of starting any work on a tranche, not a separate prerequisite**:

1. Create a plan file at `docs/plans/build-doctrine-phase-<n>-<slug>.md` per the standard plan template.
2. The plan file ships `Status: ACTIVE` from the moment of creation.
3. Roadmap Quick status flips from NOT STARTED → IN PROGRESS in the same commit as plan creation; populate the Plan file column.
4. When the tranche completes, the plan auto-archives; Quick status flips to DONE with the completion date in the same commit as the closure work.

There is no "wait for status flip" step — status follows work, not the other way around.

This gives the work two layers:
- **The roadmap** (this file) tracks the multi-tranche arc — survives across phases.
- **The plan files** track per-tranche execution — get archived as work completes.

The roadmap NEVER gets archived. Every Build Doctrine integration session updates it.

---

## Phase-by-phase detail

### Tranche 0a — Doctrine drafts ✅ DONE

What shipped: 8 integrated-v1 doctrine docs at `~/claude-projects/Build Doctrine/outputs/integrated-v1/` (~38000 words), plus 4 analysis artifacts (T1 NL inventory, T2 doctrine inventory, T3 comparative analysis, T4 unified methodology recommendation) totaling ~39343 words. 12 material decisions surfaced and approved.

Per the Build Doctrine plan: Phases 2a-2d (fresh drafts), 1a (NL review), 1b (Nate B. Jones content review), 1c (deep methodology review), 1d-A (decision approval), 1d-B (doctrine restructuring).

Where: `~/claude-projects/Build Doctrine/outputs/`. The integrated-v1 docs are the spec for everything downstream.

### Tranche 0b — Phase 0 migration ❌ NOT STARTED

**Scope:**
- Create `neural-lace/build-doctrine/` directory with `README.md` + `CHANGELOG.md` per plan spec
- Create `neural-lace/build-doctrine/doctrine/` and copy the 8 integrated-v1 docs from `Build Doctrine/outputs/integrated-v1/`
- Create `neural-lace/build-doctrine-templates/` directory with `README.md` + `CHANGELOG.md` + `VERSION` + empty subdirectories (`prd/`, `adr/`, etc.) — same-repo placement, NOT a separate repo (see decision in this roadmap's preamble)
- Verify `definition-on-first-use-gate.sh` fires correctly on the migrated content (gate is currently a no-op because it has nothing to scan)
- Add a one-line entry in NL's `docs/DECISIONS.md` index pointing at a new ADR explaining the same-repo decision (or amend an existing one if appropriate)

**Effort estimate:** ~1-2 hr. Pure-content migration + directory scaffolding.

**Blockers:** none (after the in-flight GAP-08, GAP-13, GAP-17 plans close).

**Done when:**
- `neural-lace/build-doctrine/doctrine/01-principles.md` etc. exist with the integrated-v1 content
- `definition-on-first-use-gate.sh --self-test` passes against the new in-scope files
- A Build Doctrine ADR (numbered, e.g., `025-build-doctrine-same-repo-placement.md`) records the decision to keep templates in NL rather than a separate repo
- The Build Doctrine plan's Phase 0 line in `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md` is flipped from "pending" to "complete"

### Tranche 1 — Phase 1d-C: 8 first-pass C-mechanisms ✅ DONE

What shipped:

| ID | Mechanism | NL artifact | Phase |
|---|---|---|---|
| C1 | PRD-validity gate | `prd-validity-gate.sh` + `prd-validity-reviewer.md` | 1d-C-2 |
| C2 | Spec-freeze gate | `spec-freeze-gate.sh` | 1d-C-2 |
| C7 | DAG-review waiver gate | `dag-review-waiver-gate.sh` | 1d-C-1 |
| C9 | Findings-ledger schema gate | `findings-ledger-schema-gate.sh` + `findings-ledger.md` rule + `docs/findings.md` substrate | 1d-C-3 |
| C10 | Diff-allowlist scope-enforcement gate | `scope-enforcement-gate.sh` | 1d-C-1 |
| C15 | Comprehension-gate agent | `comprehension-reviewer.md` agent + `comprehension-gate.md` rule | 1d-C-4 |
| C16 | Behavioral-contracts schema check | `plan-reviewer.sh` Check 11 | 1d-C-2 |
| C22 | Quantitative-claims arithmetic check | `plan-reviewer.sh` Check 9 | 1d-C-1 |

Plan estimate was "~3-4 weeks NL development." Actual: ~5 days (May 3-4, 2026), well ahead of estimate.

**The integration arc also shipped (beyond Phase 1d-C):**
- Phase 1d-D — Discovery Protocol (`rules/discovery-protocol.md` + `hooks/discovery-surfacer.sh` + `bug-persistence-gate.sh` extension)
- Phase 1d-E-1 through 1d-E-4 — HARNESS-GAP-10 sub-gaps A-H + drift fixes
- Phase 1d-F — Definition-on-first-use enforcement (sub-gap G of GAP-10)
- Phase 1d-G — Final cleanup (codename scrub, GAP-14 followups, observed-errors-first stub conversion)
- Decision records 013-024 (12 ADRs)

Plus this in-flight (May 5):
- HARNESS-GAP-08 (spawn-task-report-back convention)
- HARNESS-GAP-13 (hygiene-scan expansion Layers 1-4)
- HARNESS-GAP-17 Part A (this narrative doc sweep)

### Tranche 2 — Phase 4a: Layer B-shape (template schemas) ❌ NOT STARTED

**Scope:** author 7 schemas at `neural-lace/build-doctrine/template-schemas/` defining what every template instance must contain:
- `prd.schema.yaml`
- `adr.schema.yaml`
- `spec.schema.yaml`
- `design-system.schema.yaml`
- `engineering-catalog.schema.yaml`
- `conventions.schema.yaml`
- `observability.schema.yaml`

**Why this comes before Tranche 3:** schemas constrain what the content layer can produce. Authoring content first risks producing instances that don't conform.

**Effort estimate:** ~6-10 hr. Doctrine-stable work; can be done autonomously by Claude with the integrated-v1 docs as the spec.

**Blockers:** Tranche 0b must land first (so the schemas have a home).

**Done when:** all 7 schemas exist, each one validates against at least one example instance (a sanitized real-world artifact would be ideal; a synthetic minimal example is acceptable for now).

### Tranche 3 — Phase 4b: Layer B-content seeding ❌ NOT STARTED

**Scope:** seed `neural-lace/build-doctrine-templates/` with default content for the 10 universal floors (+ 11th UX-standards floor for UI projects), three depth levels per floor (Express / Standard / Deep), naming-convention defaults for JS/TS, Python, Go, Rust, plus branch/commit conventions, plus architectural defaults (layering, state mgmt, async, DB, API, frontend).

**Effort estimate:** ~15-25 hr; multi-session.

**Recommendation:** hybrid approach. Claude drafts content; you do a review pass on taste calls (which DEFAULT goes in `tldr` vs. `alternatives`?). Each floor can be a separate sub-session.

**Blockers:** Tranche 2 must land first.

**Done when:** all 11 floor categories have at least Express + Standard depth content; all naming-convention defaults are populated for the 4 named languages; at least one architectural-default category (recommend "API style") is populated as a worked example for the rest.

### Tranche 4 — Phase 6: canonical pilot project pilot ❌ NOT STARTED

**Scope:** run the pilot project through the doctrine end-to-end:
1. Bootstrap the pilot project against `08-project-bootstrapping.md`'s Karpathy test (compute → auto-research; verify behavioral → dark-factory at R5; human judgment → coding-harness with R1 default)
2. Generate the pilot project's 7 per-project canon artifacts (project README profile, conventions, design-system, engineering-catalog, gate-config, observability, .bootstrap/state)
3. Apply gate-stack to actual pilot-project work (reliability spine stages 1-10)
4. Capture friction; revise doctrine and templates based on findings

**Effort estimate:** depends on the pilot project's current state. The pilot itself is ~1 week of focused pilot-project work; doctrine revisions from findings are ~1-2 days.

**Why this project first:** per the plan's Q8 recommendation A — pilot order is the canonical pilot project first, then three sibling projects in sequence. The canonical pilot has the right shape (real product, real users in flight, harness mature enough to absorb doctrine layer).

**Blockers:** Tranches 0b + 2 must land. Tranche 3 should be at least partially populated (Express + Standard depths for floors the pilot project will exercise).

**Done when:** the pilot project has all 7 canon artifacts populated; the pilot project's primary current work item passes through the reliability spine end-to-end with friction notes captured at `docs/sessions/<date>-pilot-friction.md`; doctrine + templates revised at least once based on findings.

### Tranche 5 — Phase 5: Knowledge integration ritual ❌ NOT STARTED

**Scope:** author `neural-lace/build-doctrine/doctrine/07-knowledge-integration.md` covering:
- Cadence at which the doctrine itself updates (weekly? on-demand?)
- Triggers that surface "doctrine should be revised"
- Process for proposing → reviewing → landing doctrine changes
- Versioning policy for the templates repo (semantic versioning? date-based?)
- How project canon artifacts incorporate template updates (re-run bootstrap? selective sync?)

**Why deferred until after Tranche 4:** per the plan's Q9 recommendation A — empirical evidence from the pilot informs the ritual cadence specifications. Authoring before the pilot risks specifying rituals that don't match how the work actually unfolds.

**Effort estimate:** ~3-5 hr after the pilot has produced friction notes.

**Done when:** `07-knowledge-integration.md` exists in `neural-lace/build-doctrine/doctrine/`, references findings from the canonical-project pilot, and specifies cadence + trigger + process + versioning + project-canon-incorporation as named above.

### Tranche 6 — Phase 7: Orchestrator + propagation engine ❌ NOT STARTED

**Scope:** real Python code (the plan's "first place real code is written"):
1. **Minimal orchestrator** — DAG → dispatch state machine; ~300-500 LOC. Operationalizes what `rules/orchestrator-pattern.md` documents as Pattern.
2. **Propagation engine** — generalized PT-1..PT-7 trigger router (the C12 mechanism the doctrine flags as highest-leverage). Replaces the 3 single-purpose hooks (plan-lifecycle, decisions-index-gate, docs-freshness-gate) with a generalized framework.

**Effort estimate:** ~40-80 hr. Multi-session. Real test coverage required (this is product code, not harness scaffolding). CI required.

**Blockers:** Tranches 0b, 2, 3, 4 must land. Tranche 5 should be at least drafted.

**Done when:** orchestrator runs against at least one real pilot-project work item end-to-end; propagation engine catches at least one PT-1..PT-7 trigger event correctly; both have ≥80% test coverage; CI is green.

### Tranche 7 — The 14 second-pass C-mechanisms ❌ NOT STARTED

The remaining mechanisms beyond the first-pass 8. Per T4 §6, these are:
- C3 (engagement-mode declaration enforcement)
- C4 (universal-floor coverage check)
- C5 (per-floor naming-convention enforcement)
- C6 (Karpathy-test architecture-axis enforcement)
- C8 (Integration-Map consistency check)
- C11 (cross-document drift detection)
- C12 (generalized propagation router) — subsumed by Tranche 6 propagation engine
- C13 (promotion / demotion gate)
- C14 (holdout-scenario harness)
- C17 (rung-architecture pairing check)
- C18 (boundary-input adversarial pass automation)
- C19 (cross-unit pass automation)
- C20 (per-side review automation for Tier 4 work)
- C21 (ADR review for Tier 5 work)

**Effort estimate:** highly variable. Some are extensions of existing patterns (~2-3 hr each); some require new infrastructure (~10-20 hr each).

**Recommendation:** prioritize from observed pilot friction. If the canonical-project pilot reveals consistent failures at promotion/demotion (C13) or cross-document drift (C11), those become next-pickup. Don't attempt all 14 as a single tranche.

**Done when:** canonical-project pilot's gate stack is sufficient (no major reliability gaps observed). Some C-mechanisms may never need to ship; the criterion is observed friction, not the count.

---

## Cross-references

**Build Doctrine repo (separate from NL):**
- `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md` — the original master plan (authored before this roadmap; this roadmap is the active tracker, that file is the historical spec)
- `~/claude-projects/Build Doctrine/outputs/integrated-v1/01-principles.md` through `09-autonomy-ladder.md` — 8 integrated-v1 doctrine docs that Tranche 0b will migrate
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` — T4 deliverable, the spec for the C-mechanisms
- `~/claude-projects/Build Doctrine/outputs/analysis/` — T1 NL inventory, T2 doctrine inventory, T3 comparative analysis
- `~/claude-projects/Build Doctrine/outputs/glossary.md` — 322-line glossary the `definition-on-first-use-gate.sh` references
- `~/claude-projects/Build Doctrine/outputs/phase-1d-b-summary.md` — diff narrative for the Phase 1d-B restructuring

**NL artifacts (already shipped):**
- `adapters/claude-code/hooks/{prd-validity-gate,spec-freeze-gate,scope-enforcement-gate,findings-ledger-schema-gate,dag-review-waiver-gate,definition-on-first-use-gate,discovery-surfacer}.sh` — the C-mechanism hooks
- `adapters/claude-code/agents/{prd-validity-reviewer,comprehension-reviewer}.md` — the C-mechanism agents
- `adapters/claude-code/rules/{prd-validity,spec-freeze,findings-ledger,comprehension-gate,definition-on-first-use,discovery-protocol,findings-ledger}.md` — the rule files
- `adapters/claude-code/templates/comprehension-template.md` — articulation template
- `docs/decisions/011-024` — 14 decision records covering the integration arc
- `docs/findings.md` — findings ledger substrate
- `docs/harness-architecture.md` — full mechanism inventory (current via docs-freshness-gate)
- `docs/best-practices.md` — narrative best-practices catalog (current after this session's GAP-17 sweep)

**NL backlog entries (open work):**
- `docs/backlog.md` HARNESS-GAP-08, HARNESS-GAP-13, HARNESS-GAP-16, HARNESS-GAP-17 — in flight or scheduled
- `docs/backlog.md` HARNESS-GAP-11 — telemetry-gated; reviewer-accountability tracker
- `docs/backlog.md` Phase 1d-G calibration-mimicry — telemetry-gated

---

## Recent updates

- **2026-05-05** — **Tranche 1.5 substantively complete** (6 of 7 sub-tranches shipped). Tranches C, D, E, G shipped after A+B in parallel + sequential builds. Headline result: **closure cost dropped from 65K tokens + 13 dispatches to 2.8 seconds + 0 dispatches** via `close-plan.sh` (Tranche E). 14 pre-emptive decisions surfaced via ADR 027's new autonomous-decision queue. Doctrine extensions N1+N2+N3 added as AP16/P17/P18 in `01-principles.md` (commit `73f841d`). Tranche F (failsafe audit) deferred to next session — depends on A-E being battle-tested first. Live acceptance test of close-plan.sh deferred to next session: closing the architecture-simplification plans themselves via the new procedure validates end-to-end.
- **2026-05-05** — Tranches A (incentive redesign) and B (mechanical evidence substrate) of architecture-simplification SHIPPED in parallel. Both cherry-picked to master (commits `e352556` + `35ee3df`). Counter-Incentive Discipline sections extended across CLAUDE.md / orchestrator-pattern / planning / 4 agent prompts. New JSON Schema + helper script + rule + plan-edit-validator extension for mechanical evidence. Self-tests PASS on both. ADR 027 (autonomous decision-making process) shipped alongside, plus `docs/decisions/queued-tranche-1.5.md` pre-emptively surfacing all Tranches C/D/E/F/G decisions with options + recommendations. Tranches C, D, G dispatching next (parallel).
- **2026-05-05** — **Tranche 1.5 (architecture simplification) STARTED** as the immediate next pickup, replacing further failsafe work. ADR 026 ("harness catches up to doctrine") committed; parent plan `docs/plans/architecture-simplification.md` authored with seven sub-tranches A-G. Hard freeze on new failsafes in effect until at least Tranches A-E land. Discovery doc (`docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md`) and integration review (`docs/reviews/2026-05-05-discovery-vs-build-doctrine-integration.md`) supply the architectural rationale: 10/10 discovery insights map onto existing doctrine; the harness has not been built to it.
- **2026-05-05** — Tranche 0b (Phase 0 migration) + HARNESS-GAP-16 (closure-validation gate) CLOSED via lightweight evidence. Both auto-archived. The closure-validator hook shipped today fired on both Status flips and PASSED — first real-world test successful. These were the LAST harness-dev plans to close under the pre-architecture-simplification regime.
- **2026-05-05** — Tranche 0b (Phase 0 migration) + HARNESS-GAP-16 (closure-validation gate) CODE LANDED in parallel. Both shipped on master via parallel-builder dispatch + sequential cherry-pick. GAP-16: commit `120593c` (plan-closure-validator + /close-plan skill + 10 self-test scenarios PASS). Tranche 0b: commit `a4f55e6` (8 doctrine docs migrated to `build-doctrine/doctrine/`, `build-doctrine-templates/` scaffolded, ADR 025 landed). Hygiene-scan unblock for doctrine paths shipped first as commit `b5cdccb`. Both plans remain Status: ACTIVE pending task-verifier sweep + closure-report authoring (mechanical bookkeeping deferred — code is live).
- **2026-05-05** — Tranche 0b (Phase 0 migration) + HARNESS-GAP-16 (closure-validation gate) STARTED in parallel. Plan files: `docs/plans/build-doctrine-phase-0-migration.md` + `docs/plans/harness-gap-16-closure-validation.md`. Both dispatched as parallel builders in isolated git worktrees per orchestrator-pattern rule. Build-in-parallel, verify-sequentially.
- **2026-05-05** — Roadmap created (this file). Decision: keep `build-doctrine-templates` in same repo as NL (rejecting the original three-repo architecture). Decision: this file is the persistent source-of-truth for tracking; per-phase plan files come and go as work happens.
- **2026-05-05** — HARNESS-GAP-17 Part A (narrative doc sweep) completed. README, harness-strategy, best-practices, claude-code-quality-strategy, CLAUDE.md updated to reflect Gen 5/6 + Build Doctrine arc. Numbering conflict between two GAP-16 entries resolved (closure-validation kept as 16; docs-stale renumbered to 17).
- **2026-05-04** — Phase 1d-C-4 (comprehension gate) shipped. ALL 8 first-pass C-mechanisms now complete.
- **2026-05-04** — Phase 1d-G (final cleanup) shipped: codename scrub for master merge, GAP-14 followups, observed-errors-first stub conversion.
- **2026-05-04** — Phase 1d-F (definition-on-first-use enforcement) shipped.
- **2026-05-04** — Phase 1d-E-1 through 1d-E-4 shipped: HARNESS-GAP-10 sub-gaps A-H + drift fixes + automation-mode JSON schema + GAP-14 reconciliation.
- **2026-05-03** — Phase 1d-C-3 (findings ledger), 1d-C-2 (PRD validity + spec freeze + plan-header schema + behavioral contracts), 1d-C-1 (scope-enforcement + DAG waiver + quantitative arithmetic) shipped.
- **2026-05-03** — Phase 1d-D (Discovery Protocol) shipped.
- **2026-05-03** — Phase 1d-B doctrine restructuring complete (8 integrated-v1 docs at ~38K words).
- **2026-04-29 to 2026-05-01** — Phases 2a-2d, 1a, 1b, 1c, 1d-A complete in Build Doctrine repo.

---

## How to update this doc

When a tranche's status changes:

1. **NOT STARTED → IN PROGRESS** (when a plan file gets created and Status: ACTIVE):
   - Update the Quick status table: change status icon, populate "Plan file" column with the new plan's path
   - Update Current focus to point at the new tranche
   - Add a "Recent updates" entry naming the tranche start

2. **IN PROGRESS → DONE** (when the tranche's plan flips Status: COMPLETED):
   - Update the Quick status table: change to ✅ DONE, populate "Completed in" with the date range
   - Update Current focus to point at the next tranche
   - Add a "Recent updates" entry naming what shipped

3. **Always:**
   - Update "Last updated" date to today
   - Verify the Cross-references section still resolves (no broken paths)

When the user asks "where are we?":

- Read aloud: Current focus section + the most-recent "Recent updates" entry. That's the answer.

When this doc itself drifts (e.g., the recent updates section grows past ~30 entries):

- Move oldest entries to a `## Archive` section at the bottom. Don't delete history.
- Triggers a small revision; bump "Last updated" date.

---

## Why this doc exists (FAQ)

**Q: Why a roadmap doc instead of just plan files?**
A: Plan files have a lifecycle — they get archived on completion. This roadmap NEVER archives. It's the durable cross-session reference for "where are we in the multi-phase arc." Plan files track per-phase execution; this tracks the arc.

**Q: Why not just the Build Doctrine plan file in the Build Doctrine repo?**
A: That file lives in a different repo, isn't loaded into NL sessions by default, and was authored before the integration arc started. It's the historical spec; this is the active tracker.

**Q: Why same-repo (NL) for templates instead of separate repo?**
A: At current scale (one user, no projects pinning template versions), separation adds friction without paying for itself. If/when there are real projects pinning different template versions, splitting via `git subtree split` is straightforward. Premature separation is harder to undo than premature consolidation.

**Q: What if work happens that doesn't fit any tranche?**
A: Two paths: (a) if it's a HARNESS-GAP-N, it goes to `docs/backlog.md` as usual and may eventually become its own tranche if it's substantial; (b) if it's a Build Doctrine integration concern, propose a new tranche by editing this doc with `Status: PROPOSED` and waiting for user approval before promoting to NOT STARTED.

**Q: What if a tranche turns out to be larger than estimated?**
A: Split it. A tranche that's >40 hours is too large; sub-divide it (e.g., Tranche 3 might split into 3a/3b/3c by floor category). Update Quick status, write per-sub-tranche plan files.

**Q: How does this interact with HARNESS-GAP-16 (closure validation)?**
A: GAP-16 is the structural fix for "no single session owns end-to-end completion" — exactly the failure that produced this roadmap's gaps. Once GAP-16 ships (Layer 1: gate prevents Status: ACTIVE → COMPLETED transition without closure work; Layer 2: `/close-plan` skill walks through closure mechanically), per-tranche plan closure becomes mechanical rather than discipline-based. Worth shipping GAP-16 BEFORE Tranches 2-7 so the discipline lands first.
