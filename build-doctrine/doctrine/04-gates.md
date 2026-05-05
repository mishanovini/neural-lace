---
title: Build Doctrine — Gate Definitions
status: integrated v1
owner: misha
last_review: 2026-05-03
sources:
  - originally drafted independently before review of existing neural-lace artifacts (hooks, scanners, evals/), to surface uncoupled reasoning for later reconciliation
  - composes with 01-principles.md, 02-roles.md, 03-work-sizing.md
  - integrated-v1 incorporates Phase 1d-B comparative-review recommendations (gate types 2.6 + 2.7; gate matrix parameterized by architecture × rung; reliability-first framing; trust-the-process framing; C-mechanism cross-references for forthcoming Phase 1d-C work)
references:
  - ~/.claude/rules/vaporware-prevention.md (harness-layer enforcement map)
  - ~/.claude/docs/harness-architecture.md (gate inventory at NL Layer 0–3)
  - ~/.claude/agents/code-reviewer.md, claim-reviewer.md, end-user-advocate.md, systems-designer.md, ux-designer.md, plan-evidence-reviewer.md, harness-reviewer.md (NL adversarial-review agents)
  - outputs/unified-methodology-recommendation.md Section 3 (10-stage reliability spine)
  - outputs/unified-methodology-recommendation.md Section 6 (C-mechanism proposals C1-C22)
  - outputs/glossary.md (gate-category vocabulary)
  - 03-work-sizing.md (work-sizing tier definitions and 5-axis schema)
  - 09-autonomy-ladder.md (architecture taxonomy N-A-1, rung definitions)
revision_notes:
  - 2026-05-01: original draft.
  - 2026-05-03 v3 (integrated-v1):
      - gate types 2.6 (holdout scenario) and 2.7 (comprehension) added per N-A-2 and N-G-1
      - gate matrix parameterized by architecture × rung per N-A-1 (alongside tier-based applicability for code-level gates)
      - trust-the-process framing added to intro per N-R-G
      - C-mechanism IDs (C1-C22) cited where forthcoming Phase 1d-C work will mechanize gates
      - reliability-first framing in intro per Q1 inversion (gates compound along the 10-stage spine to produce first-try-functional applications)
      - per-tier adversarial-review-agent mapping added (Tier 1 = code-reviewer light + claim-reviewer; Tier 2 = + boundary-input + end-user-advocate plan-time; Tier 3 = per-sub-unit + cross-unit + systems-designer if Mode: design; Tier 4 = per-side + end-user-advocate runtime; Tier 5 = systems-designer ADR review)
      - **Harness implementation:** lines added to gate definitions citing C-mechanism IDs where the gate will be mechanized
---

# Build Doctrine — Gate Definitions

## Scope

Every gate the build system enforces is defined here. For each gate this document specifies:

- **Type** — mechanical (deterministic) / LLM-backed / human.
- **Trigger** — what fires the gate.
- **Inputs and outputs** — what the gate reads and writes.
- **Pass criterion** — what makes the gate green.
- **Failure handling** — what happens on red, including findings ledger entries.
- **Escape hatch** — whether the gate can be overridden, by whom, with what audit trail.
- **Tier applicability** — which work-sizing tiers require this gate.
- **Architecture × rung applicability** — for gates whose required-vs-recommended status depends on the architecture-and-rung axes (per N-A-1) rather than tier alone.
- **Harness implementation** — the C-mechanism ID (C1-C22 from `outputs/unified-methodology-recommendation.md` §6) and/or NL hook/agent that operationalizes the gate, and whether the implementation has landed or is forthcoming Phase 1d-C work.

Gates compose. The orchestrator's "is this unit done" check is a deterministic AND across all required gates for the unit's tier. No gate has approval authority on its own; the composition is what makes a unit complete.

Per anti-principle #11, every LLM-backed gate is paired with a mechanical backstop. The deterministic spine — schema validation, type checks, contract tests — is what makes the LLM components safe to lean on.

### Reliability-first framing

This doc defines what each gate IS. **`outputs/unified-methodology-recommendation.md` Section 3 names every gate at every stage of the 10-stage reliability spine** (Stage 0 pre-PRD context through Stage 10 session-end integrity — eleven labeled stages numbered 0 through 10, ten transitions between them; "10-stage" is the canonical naming throughout the doctrine). Gates compose along that spine; each catches a class of failure that the previous stages couldn't observe; the **compounding effect across stages is what produces first-try-functional applications**. Per the methodology recommendation's Q1 inversion (reliability spine as the central axis; rung as metadata over the gate stack), the substance is the gate stack, and rungs / autonomy levels are which gates are wired up at this project at this rung.

### Trust the process

Gates are not bureaucracy. Each gate exists because a specific class of failure shipped without it. The discipline is to trust the process — when a gate blocks, the answer is to read what it caught, not route around it. Per Nate B. Jones, gates "are how AI-augmented teams keep small failures from compounding into shipped vaporware." Cross-reference NL's `~/.claude/rules/vaporware-prevention.md` for the harness-layer enforcement map: it lists every hook + agent that fires per principle, and what each catches that the previous gate couldn't observe. The map is honest about residual gaps; the trust-the-process framing applies even there — when a residual gap surfaces, the answer is to encode the next mechanism (C-proposals are exactly this — currently-paper disciplines that should be mechanized — see `outputs/unified-methodology-recommendation.md` §6 for the C1–C22 sequence).

---

## Gate categories

1. **Static mechanical gates** — type checks, lint, format, schema validation, frontmatter completeness, scope enforcement.
2. **Test gates** — unit tests, integration tests, contract tests, property tests, mutation tests, **holdout scenarios (2.6)**, **comprehension (2.7)**.
3. **Document gates** — PRD validity, spec validity, ADR adoption, design system / catalog / Integration Map consistency.
4. **Adversarial review gate** — LLM-backed; structured prompt and output shape per tier.
5. **Propagation gates** — verify triggered updates landed (cross-references `06-propagation.md`).
6. **Human checkpoint gates** — DAG review, irreversibility approval, findings disposition.

---

## 1. Static mechanical gates

### 1.1 Type check

**Type:** Mechanical. **Trigger:** every dispatched unit, every commit. **Inputs:** code under change. **Pass:** zero type errors at the project's configured strictness. **Failure:** writes a finding (severity = blocking) to the ledger; unit returns to builder. **Escape hatch:** none at unit level; project-level strictness changes require an ADR. **Tier applicability:** all tiers.

**Harness implementation:** NL `pre-commit-tdd-gate.sh` (TypeScript strict mode + `rules/typescript.md`); already landed.

### 1.2 Lint

**Type:** Mechanical. **Trigger:** every dispatched unit. **Inputs:** code under change, project lint config. **Pass:** zero lint errors at error severity; warnings logged but not blocking. **Failure:** writes findings to the ledger; errors block, warnings advise. **Escape hatch:** disable rule per-line requires inline comment with rationale; persistent disables across many sites trigger a finding for the engineering catalog curator. **Tier applicability:** all tiers.

**Harness implementation:** NL `pre-commit-tdd-gate.sh` lint integration; already landed.

### 1.3 Format

**Type:** Mechanical. **Trigger:** every commit. **Inputs:** code. **Pass:** matches project formatter output. **Failure:** auto-fix where safe; otherwise blocks. **Escape hatch:** none. **Tier applicability:** all tiers.

**Harness implementation:** NL `pre-commit-tdd-gate.sh` format check; already landed.

### 1.4 Schema validation (specs, PRDs, ADRs, doctrine)

**Type:** Mechanical. **Trigger:** any artifact freeze, any commit touching `build-doctrine/` or `docs/decisions/`. **Inputs:** the artifact, its template's schema. **Pass:** all required fields present and well-formed; frontmatter valid; cross-references resolvable. **Failure:** writes a blocking finding; artifact cannot be marked frozen. **Escape hatch:** none. **Tier applicability:** all tiers (every unit has at minimum a spec).

**Harness implementation:** NL `plan-reviewer.sh` Check 6b (7 required sections + non-trivial content) covers plan validity today; PRD validity (C1) and spec freeze (C2) are forthcoming Phase 1d-C work that completes the schema-validation surface. C11 generalizes frontmatter completeness across project artifacts.

### 1.5 Scope enforcement (diff allowlist)

**Type:** Mechanical. **Trigger:** builder marking a unit ready for review. **Inputs:** unit's declared file scope (from spec), actual diff. **Pass:** all changed files lie within declared scope. **Failure:** out-of-scope changes flagged in the ledger as scope-creep findings. The unit is not auto-rejected — the orchestrator routes to the spec author to either expand scope (with re-freeze) or reject and have the builder revert out-of-scope changes. **Escape hatch:** spec author re-freeze with documented rationale; explicit "scope expansion" finding written to `docs/findings.md` AND staged in same commit. **Tier applicability:** all tiers; especially load-bearing at Tier 1 (where scope creep is the named failure mode).

**Harness implementation:** C10 diff-allowlist scope-enforcement gate (forthcoming Phase 1d-C); today: paper-only via the Builder role's "writes findings for out-of-scope" discipline. NL's `plan-edit-validator.sh` enforces evidence-first checkbox flips but doesn't currently enforce diff-allowlist.

### 1.6 Frontmatter completeness

**Type:** Mechanical. **Trigger:** any markdown artifact commit. **Inputs:** frontmatter block. **Pass:** all required keys present (`status`, `owner`, `last_review`, `sources`, `references`). **Failure:** blocks commit; writes finding. **Escape hatch:** none. **Tier applicability:** all tiers.

**Harness implementation:** NL `harness-hygiene-scan.sh` enforces frontmatter on harness-repo files; project-level coverage forthcoming via C11 frontmatter completeness gate generalized.

---

## 2. Test gates

### 2.1 Unit tests

**Type:** Mechanical. **Trigger:** every dispatched unit. **Inputs:** unit's tests, fixtures from the spec. **Pass:** all unit tests green; coverage of each declared failure mode (a test that fails when the failure is introduced — not line coverage). **Failure:** failing tests block; missing failure-mode coverage writes a finding (severity = blocking unless explicitly waived per spec). **Escape hatch:** failure-mode waiver requires re-freeze of the spec with rationale. **Tier applicability:** all tiers.

**Harness implementation:** NL `pre-commit-tdd-gate.sh` Layers 1-4 (new files need tests, integration cannot mock, trivial assertions banned, silent-skip banned) + `no-test-skip-gate.sh`; already landed.

### 2.2 Integration tests

**Type:** Mechanical. **Trigger:** Tier 2 units touching schema or external systems; Tier 3+ always. **Inputs:** integration test suite scoped to the unit. **Pass:** all green at the integration boundary. **Failure:** blocks; writes a finding with the failing path. **Escape hatch:** none at unit level. **Tier applicability:** Tier 2 (when applicable), Tier 3, Tier 4. Tier 5 produces no implementation; integration tests run in subsequent Tier 1–4 work.

**Harness implementation:** NL `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh` (Stop hook chain — parses + executes Runtime verification entries + verifies correspondence to modified files); already landed.

### 2.3 Contract tests

**Type:** Mechanical. **Trigger:** Tier 2 units when a boundary is touched; Tier 3+ for any cross-module boundary; Tier 4 mandatory on both sides of the boundary against shared fixtures. **Inputs:** the contract definition (from engineering catalog), test suite on each side. **Pass:** both sides green against the same fixtures. **Failure:** blocks; writes findings on the side that failed plus an Integration Map check finding. **Escape hatch:** explicit break declaration in spec with backward-compat or migration plan; otherwise none. **Tier applicability:** Tier 2 (when boundary touched), Tier 3, Tier 4.

**Harness implementation:** C3 bilateral contract-test gate (forthcoming Phase 1d-C). Today: paper-only — NL's TDD gate covers unit-test presence but doesn't enforce contract-test bilaterality. The Tier 4 named failure mode "fixed on one side, forgot the other" is exactly what C3 closes.

### 2.4 Property tests

**Type:** Mechanical. **Trigger:** opt-in per spec; required for hot paths declared in the engineering catalog. **Inputs:** generators, invariants. **Pass:** invariants hold under generated inputs at the project's configured shrinking budget. **Failure:** counter-example logged to findings; blocks unit. **Escape hatch:** narrowing the property's domain requires spec re-freeze. **Tier applicability:** Tier 2+ on hot paths; advisory on others.

**Harness implementation:** Not currently mechanized in NL; project-level test runners + `gate-config.yaml` declarations. No C-proposal as of Phase 1d-B; revisit when sufficient project pilots run property-tested hot paths.

### 2.5 Mutation tests

**Type:** Mechanical. **Trigger:** Tier 3+ on the integration hot paths (the seams between sub-units); Tier 4 on the contract surface. **Inputs:** mutation test runner, code under test, test suite. **Pass:** mutation score above project threshold. **Failure:** writes findings naming surviving mutants; blocks unit-level completion. **Escape hatch:** test additions to kill the mutant; only an explicit ADR can lower the threshold project-wide. **Tier applicability:** Tier 3 (seams), Tier 4 (contract surface), Tier 5 not applicable.

**Harness implementation:** Not currently mechanized in NL; project-level. No C-proposal as of Phase 1d-B.

### 2.6 Holdout scenario gate

Per N-A-2 (added in this integrated-v1 revision; see `outputs/glossary.md` "Holdout scenario gate" entry). Cross-reference Nate B. Jones, "Wrong agents" — StrongDM dark factory section.

**Type:** Mechanical. **Trigger:** any unit whose plan declares `architecture: dark-factory` (any rung≥5) OR `architecture: auto-research` (any rung≥4); optional but recommended for high-autonomy `coding-harness` work (Rung 3+). **Inputs:** holdout scenarios stored OUTSIDE the project repo (filesystem-level isolation; agent has no read access to scenarios during development) — typically in a separate `tests/holdout/` directory mounted read-only at verification time, OR in an external repo the build pipeline pulls. **Pass:** holdout suite passes after the unit is built; representative coverage of the user-observable behavior space (per `outputs/glossary.md` definition). **Failure:** blocks; opens a finding with the failing scenario(s). **Escape hatch:** none for `dark-factory` architecture; project-level ADR may temporarily downgrade requirements for `auto-research` with rationale.

**Architecture × rung applicability:**

- `architecture: dark-factory`, any rung≥5 — **REQUIRED** (no escape hatch).
- `architecture: auto-research`, any rung≥4 — **REQUIRED** (ADR-level downgrade possible).
- `architecture: coding-harness`, rung≥3 — **RECOMMENDED**.
- `architecture: orchestration`, rung≥3 — **RECOMMENDED**.
- All other combinations — not required.

**Tier applicability:** all tiers within the qualifying architecture × rung combinations. Tier-orthogonal: the gate fires per architecture × rung, not per tier.

**Harness implementation:** C14 holdout-scenarios gate (forthcoming Phase 1d-C). Today: paper-only.

### 2.7 Comprehension gate

Per N-G-1 (added in this integrated-v1 revision). Cross-reference NL's forthcoming `comprehension-reviewer` agent (planned to land in `adapters/claude-code/agents/`).

**Type:** LLM-backed (forthcoming as C15 comprehension-gate agent in Phase 1d-C; today: pattern-only). **Trigger:** every unit at Rung 2+. **Inputs:** the diff under change, the surrounding-call-site context, the spec. **Pass:** the agent produces a structured comprehension summary identifying:

- **Blast radius** — which other modules' contracts depend on this; how the change ripples.
- **Cross-tenant exposure** — if the surface is multi-tenant, what isolation properties this change preserves/breaks.
- **Credential-handling implications** — if the path touches secrets, what changes about secret lifetime, scope, exposure surface.
- **Ephemeral-token semantics** — for surfaces that issue or accept ephemeral tokens, how this change affects token lifetimes, reuse, revocation.

The summary is human-readable and either: empty (the change has none of the above concerns — low-blast-radius change) or surfaces specific concerns. **Failure:** comprehension summary surfaces a concern AND no disposition is on file → blocks. **Escape hatch:** human disposition recorded in the findings ledger (act / defer / accept-with-rationale).

**Architecture × rung applicability:** all architectures, rung≥2.

**Tier applicability:** all tiers from rung≥2. Tier-orthogonal.

**Harness implementation:** C15 comprehension-gate agent (forthcoming Phase 1d-C). Today: paper-only — NL has no comprehension agent. Self-invoked by the builder before commit; enforced by `task-verifier` invoking it.

---

## 3. Document gates

### 3.1 PRD validity

**Type:** Mechanical (schema) + human (freeze). **Trigger:** PRD submitted for freeze. **Inputs:** PRD against template; open-questions field. **Pass:** all required fields complete; open-questions field empty or explicitly marked "deferred with rationale"; human freeze recorded. **Failure:** schema failure blocks; non-empty open questions return to spec author for elicitation. **Escape hatch:** "deferred with rationale" requires explicit user opt-in logged in the PRD. **Tier applicability:** every PRD-derived work; some Tier 1 utility work may not require a PRD if it's inside an existing PRD's scope.

**Harness implementation:** C1 PRD-validity gate (forthcoming Phase 1d-C). Today: paper-only — NL's plan-reviewer enforces plan schema, not PRD schema. C1 + a new `prd-validity-reviewer` agent (per Q6 of the methodology recommendation) close the gap.

### 3.2 Spec validity

**Type:** Mechanical (schema) + human (freeze). **Trigger:** spec submitted for freeze. **Inputs:** spec against template, PRD reference, Integration Map references (Tier 3+). **Pass:** schema valid; PRD reference resolves; Integration Map references resolve (Tier 3+); all required fields complete. **Failure:** blocks freeze; specifics in findings. **Escape hatch:** none. **Tier applicability:** all tiers.

**Harness implementation:** C1 (PRD reference resolvability) + C2 spec-freeze gate (forthcoming Phase 1d-C). Today: NL's `plan-reviewer.sh` Check 6b enforces 7-section presence + Check 8A enforces Pre-Submission Audit on Mode: design plans. The "frozen: true" allowlist for plan-declared file edits is C2's contribution.

### 3.3 ADR adoption

**Type:** Adversarial review (LLM) + human (stakeholder approval). **Trigger:** Tier 5 work or any architectural pattern not in canon. **Inputs:** ADR draft. **Pass:** adversarial review pass complete and findings dispositioned; stakeholder approval recorded with date. **Failure:** unaddressed reviewer findings or missing approval blocks. **Escape hatch:** none for adoption; superseding an existing ADR uses the standard ADR status workflow. **Tier applicability:** Tier 5; required when any tier introduces a novel pattern.

**Harness implementation:** C4 ADR-adoption gate (forthcoming Phase 1d-C). Today: NL has `decisions-index-gate.sh` enforcing atomicity (record + DECISIONS.md index in same commit) but not the adoption-flow review/disposition cycle. C4 closes the adoption-flow gap by requiring a `## Adversarial review` section before status flip from `proposed` → `accepted`.

### 3.4 Engineering catalog consistency

**Type:** Mechanical. **Trigger:** any commit touching declared modules, public contracts, or Integration Map nodes; daily scheduled run. **Inputs:** code under change, current catalog state. **Pass:** code matches catalog; new public surfaces have catalog entries; Integration Map nodes match actual runtime integration. **Failure:** opens a finding routed to the engineering catalog curator. The unit is not auto-blocked unless the spec named these as required deliverables (Tier 4). **Escape hatch:** none — drift is treated as build blocker for affected surfaces (per role definition). **Tier applicability:** Tier 3+ (curator updates required); Tier 1–2 monitored, not blocking.

**Harness implementation:** C5 engineering catalog / Integration Map consistency gate (forthcoming Phase 1d-C, longer-term). Today: paper-only — NL has nothing equivalent.

### 3.5 Design system consistency

**Type:** Mechanical. **Trigger:** any commit adding/modifying UI components or tokens. **Inputs:** code, design system reference. **Pass:** every new component has a design system entry; token usage matches canonical tokens. **Failure:** opens a finding routed to the design system curator. **Escape hatch:** none — design canon is load-bearing per principle #2. **Tier applicability:** any tier producing UI.

**Harness implementation:** C6 design system consistency gate (forthcoming Phase 1d-C, longer-term). Today: NL `rules/ux-standards.md` covers some discipline (color rules, contrast, every-card-clickable) but no consistency check against a per-project design system.

---

## 4. Adversarial review gate

**Type:** LLM-backed, mandatory at every tier per principle #5.

**Activation:** every dispatched unit. Skipping is not an option. Depth scales by tier.

**Operating constraints:**

- Fresh context: no shared session history with the builder.
- Different model family preferred: cross-vendor or cross-model where infrastructure permits.
- One reviewer per dispatched unit. Two reviewers from the same lineage are not independent.

**Tier-specific prompt and output shape, with NL adversarial-review agent mapping:**

| Tier | Prompt focus | NL agents that operationalize | Required output structure |
|---|---|---|---|
| 1 | "What edge cases aren't handled? What does this assume that might not hold?" | `code-reviewer` lightweight pass; `claim-reviewer` self-invoked. | Findings ledger entries: severity (info/warn/error/severe), location, scope, suggested action. Minimum 0 findings if work is clean; minimum format compliance always. |
| 2 | All Tier 1 plus: "What's the worst valid input that breaks this? What contract semantics aren't captured in types? What error paths are untested?" | All Tier 1 + boundary-input enumeration via `code-reviewer` deeper pass; `end-user-advocate` plan-time mode for UI work. | Same shape, deeper coverage; explicit boundary-input enumeration in findings. |
| 3 | Per-sub-unit Tier 2 review, plus separate cross-unit pass: "Do the seams hold? Are there integration mismatches between sub-units? Does the Integration Map match what was built?" | All Tier 2 + per-sub-unit `code-reviewer` + cross-unit integration review; `systems-designer` if `Mode: design`. | Per-sub-unit findings plus a cross-unit integration findings section. |
| 4 | Per-side Tier 3 review, plus boundary review: "What does each side assume about the other that the contract doesn't enforce? Are the contract tests on both sides actually testing the same thing? What happens during the migration window?" | All Tier 3 + per-side review; `end-user-advocate` runtime mode (browser-against-live-app verification of bilateral behavior). | Per-side findings plus boundary-specific findings section. |
| 5 | ADR review: "What's missing from the option space? What assumptions are unstated? What will future implementers find painful that isn't called out? What does this make easy that wasn't before, and what does it make hard?" | `systems-designer` ADR review; option-space completeness pass. | Findings against the ADR itself, focused on option-space completeness and future-pain prediction. |

**Pass criterion:** review completes; findings persisted to ledger in required structured format; severity distribution does not include unaddressed `severe` findings.

**Failure handling:** `severe` findings without disposition block the unit. `error` findings require user disposition (act / defer / accept-with-rationale). `warn` and `info` are logged for pattern detection by the knowledge integrator.

**Escape hatch:** none for the gate itself. User may disposition individual findings as `defer` or `accept-with-rationale`, which logs to the ledger as visible-and-pending (per anti-principle #14, undecided findings remain visible until decided).

**Harness implementation:** NL's seven adversarial-review agents (`code-reviewer`, `security-reviewer`, `harness-reviewer`, `claim-reviewer`, `plan-evidence-reviewer`, `ux-designer`, `systems-designer`) plus `end-user-advocate` (the only adversarial *observer* — runs the live product) are already landed. C5 / C15 are forthcoming Phase 1d-C work that adds (a) tier-scaled-prompt mechanization extending agent prompts with tier-parameterized structure, (b) the comprehension-gate agent for rung-2+ comprehension verification.

---

## 5. Propagation gates

Defined fully in `06-propagation.md`. Summarized here:

### 5.1 Propagation trigger fired

**Type:** Mechanical (rule evaluation) + LLM-assisted (suggested updates) + human (curator action where rules can't auto-apply).

**Trigger:** event matches a defined propagation trigger (contract change, component addition, ADR adoption, principle update, drift signal, etc.).

**Pass:** all dependent artifacts updated cleanly OR finding opened for the appropriate curator OR explicit no-op recorded.

**Failure:** rule fires but no clean update path and no finding opened — orchestrator-level error, halts run.

**Tier applicability:** all tiers (propagation is independent of tier; what differs is which triggers fire).

**Harness implementation:** C12 generalized propagation-event hook (forthcoming Phase 1d-C). Today: NL has three single-purpose triggers: `docs-freshness-gate.sh`, `decisions-index-gate.sh`, `migration-claude-md-gate.sh`. Doctrine specifies a 7-trigger framework. C12 is the highest-leverage single mechanism opportunity per `outputs/unified-methodology-recommendation.md` §6.

### 5.2 Propagation completion verification

**Type:** Mechanical. **Trigger:** unit-level completion check. **Pass:** every propagation event fired during the unit has either landed or has an open finding. **Failure:** unit cannot complete with un-resolved propagation; either propagation lands or finding is opened. **Escape hatch:** none.

**Harness implementation:** C12 (forthcoming). Today: paper-only.

---

## 6. Human checkpoint gates

### 6.1 DAG review

**Type:** Human. **Trigger:** planner produces a DAG; before any builder dispatches. **Inputs:** the DAG, the spec it derives from. **Pass:** human approval logged with timestamp. **Failure:** DAG returns to planner with structured feedback. **Escape hatch:** none. **Tier applicability:** mandatory at Tier 3+; recommended at Tier 1–2 (but may be batch-approved or auto-approved per project policy).

**Harness implementation:** C7 DAG-review waiver gate (forthcoming Phase 1d-C; short-term form). The waiver-gate variant requires a `dag-approved-by-human-<plan-slug>-<timestamp>.txt` file in `.claude/state/` for any plan with `tier: 3+` declared. Future-state: full deterministic orchestrator (longer-term per Q10 of the methodology recommendation). Today: NL `rules/orchestrator-pattern.md` is Pattern-class only.

### 6.2 Irreversibility approval

**Type:** Human. **Trigger:** any spec carrying an irreversibility flag, at the moment the unit attempts the irreversible action. **Inputs:** the action's specifics, the spec's rationale. **Pass:** explicit approval logged. **Failure:** unit halts; orchestrator routes to escalation queue. **Escape hatch:** none — this is the checkpoint. **Tier applicability:** Tier 4 mandatory; any tier when an irreversibility flag is set on its spec.

**Harness implementation:** NL permission-tier T3 Block + inline PreToolUse blockers on force-push, public-repo, sensitive-file, dangerous-command. Already landed at the action-time substrate; doctrine's spec-time irreversibility flag is the upstream commitment.

### 6.3 PRD freeze

**Type:** Human (spec author confirms freeze). **Trigger:** PRD elicitation converges. **Inputs:** PRD draft, open-questions field. **Pass:** explicit freeze action logged. **Failure:** non-empty open questions block freeze unless explicitly deferred. **Escape hatch:** "deferred with rationale" pattern. **Tier applicability:** every PRD.

**Harness implementation:** C1 (forthcoming).

### 6.4 Spec freeze

**Type:** Human (spec author confirms freeze). **Trigger:** spec drafted, schema validated. **Inputs:** spec, PRD reference, schema check result. **Pass:** explicit freeze logged. **Failure:** blocks dispatch. **Escape hatch:** none. **Tier applicability:** all tiers.

**Harness implementation:** C2 (forthcoming).

### 6.5 Findings disposition

**Type:** Human. **Trigger:** unit-level completion attempt with findings of severity `error` or above unaddressed. **Inputs:** findings ledger entries. **Pass:** every blocking-severity finding has a disposition (act / defer / accept-with-rationale). **Failure:** unit cannot complete. **Escape hatch:** none — undecided findings remain visible-and-pending per anti-principle #14. **Tier applicability:** all tiers.

**Harness implementation:** C9 findings-ledger schema gate (forthcoming Phase 1d-C). Today: NL's `bug-persistence-gate.sh` covers the bug subset; the rest is paper. Six-field schema per Q5 of the methodology recommendation: `id` / `severity` / `scope` / `source` / `location` / `status`.

---

## Gate matrix — parameterized by architecture × rung × tier

Per N-A-1, the gate matrix is **parameterized along three axes** (architecture × rung × tier). Tier-only applicability remains correct for code-level gates (type, lint, format, schema, unit/integration tests) because those don't vary by architecture or rung. But several gates are required-vs-recommended on architecture × rung combinations rather than tier alone — most notably gate type 2.6 (holdout scenarios) and 2.7 (comprehension).

### Tier-based applicability (code-level gates)

| Gate | Tier 1 | Tier 2 | Tier 3 | Tier 4 | Tier 5 |
|---|---|---|---|---|---|
| 1.1 Type check | ✓ | ✓ | ✓ | ✓ | n/a* |
| 1.2 Lint | ✓ | ✓ | ✓ | ✓ | n/a* |
| 1.3 Format | ✓ | ✓ | ✓ | ✓ | n/a* |
| 1.4 Schema validation | ✓ | ✓ | ✓ | ✓ | ✓ |
| 1.5 Scope enforcement | ✓ | ✓ | ✓ | ✓ | ✓ |
| 1.6 Frontmatter | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2.1 Unit tests | ✓ | ✓ | ✓ | ✓ | n/a* |
| 2.2 Integration tests | — | ✓ when applicable | ✓ | ✓ | n/a* |
| 2.3 Contract tests | — | ✓ when boundary touched | ✓ | ✓ both sides | n/a* |
| 2.4 Property tests | — | ✓ on hot paths | ✓ on hot paths | ✓ on hot paths | n/a* |
| 2.5 Mutation tests | — | — | ✓ on seams | ✓ on contract surface | n/a* |
| 3.1 PRD validity | ✓ | ✓ | ✓ | ✓ | ✓ |
| 3.2 Spec validity | ✓ | ✓ | ✓ | ✓ | ✓ (ADR substitutes for spec at this tier) |
| 3.3 ADR adoption | — | — | — | when novel pattern | ✓ |
| 3.4 Catalog consistency | monitor | monitor | ✓ | ✓ required | ✓ post-adoption |
| 3.5 Design system consistency | when UI | when UI | when UI | when UI | when UI |
| 4 Adversarial review | ✓ light | ✓ full | ✓ per-sub + cross | ✓ per-side + boundary | ✓ on ADR |
| 5 Propagation | ✓ | ✓ | ✓ | ✓ | ✓ |
| 6.1 DAG review | recommended | recommended | ✓ mandatory | ✓ mandatory | n/a |
| 6.2 Irreversibility approval | when flagged | when flagged | when flagged | ✓ mandatory | n/a |
| 6.3 / 6.4 PRD / Spec freeze | ✓ | ✓ | ✓ | ✓ | n/a (ADR freeze) |
| 6.5 Findings disposition | ✓ | ✓ | ✓ | ✓ | ✓ |

\* Tier 5 produces no implementation directly. Code-level gates apply to the subsequent Tier 1–4 implementation work that derives from the adopted ADR.

### Architecture × rung applicability (autonomy-axis gates)

For gates whose required-vs-recommended status depends on architecture × rung rather than tier:

| Gate | coding-harness R0–R2 | coding-harness R3+ | orchestration R1–R3 | orchestration R4+ | auto-research R4+ | dark-factory R5+ | hybrid |
|---|---|---|---|---|---|---|---|
| 2.6 Holdout scenarios | — | recommended | — | recommended | **REQUIRED** (ADR downgrade possible) | **REQUIRED** (no escape) | per declared sub-architectures |
| 2.7 Comprehension | rung≥2: ✓ | ✓ | rung≥2: ✓ | ✓ | ✓ | ✓ | per sub-architecture rung |
| Behavioral contracts (`## Behavioral Contracts` schema check, C16) | — | rung≥3: ✓ | — | rung≥3: ✓ | rung≥3: ✓ | rung≥3: ✓ | per sub-architecture rung |
| Adversarial review depth | per Tier table above | per Tier table above | per Tier table above | per Tier table above + metric-driven scoring auxiliary | metric-driven scoring is the gate | holdout + evidentiary verification ARE the gates | per sub-architecture |

Hybrid architectures: each work unit declares its sub-architecture, and the gate matrix's architecture × rung row applies per sub-architecture. The per-project canon (`gate-config.yaml`) specifies how hybrid units map to sub-architectures.

---

## Cross-cutting rules

### Findings ledger discipline

Every gate writes to the findings ledger on failure. The ledger is the single durable record of issues; gate diagnostics live alongside but do not replace ledger entries. Per anti-principle #14, no gate output is allowed to be lost between gate and ledger.

**Harness implementation:** C9 findings-ledger schema gate (forthcoming Phase 1d-C). Today: NL `bug-persistence-gate.sh` covers the bug subset. The rest is paper-only.

### Tier transition during execution

If a builder discovers mid-build that the unit is misclassified (e.g., a Tier 2 unit that turns out to require a Tier 4 contract change), the protocol is:

1. Halt the unit immediately. No further code changes.
2. Write a `tier-transition` finding to the ledger with severity `error` and the discovered tier.
3. Drift log entry recording what made the original classification wrong.
4. Route to spec author (or planner if it's a decomposition issue, not a spec issue) for re-classification and re-spec.
5. The original unit is closed without merge; the new unit dispatches against the corrected tier.

This protocol is explicitly **not** "carry on at the higher tier" — promoting tier mid-execution loses the gates the higher tier required from the start.

**Harness implementation:** C8 tier-transition halting gate (forthcoming Phase 1d-C). Today: paper-only — discipline only.

### Mid-build decision tier (separate from work-sizing tier transition)

Distinct from work-sizing tier transition is the **mid-build decision tier** axis (NL `~/.claude/rules/planning.md` L383-388):

- **Tier 1 (mid-build) — isolated, trivially reversible:** continue + document.
- **Tier 2 (mid-build) — multi-file but revertible:** commit checkpoint first.
- **Tier 3 (mid-build) — irreversible (schema, public API, auth, production data):** PAUSE and wait.

Both axes can fire on the same unit: the work-sizing tier-transition halt is for "this entire unit is misclassified," and the mid-build tier-transition halt is for "this specific decision within the unit is irreversible." See `03-work-sizing.md` "Five orthogonal axes" section for full disambiguation.

### Escape hatch audit

Every escape hatch invocation — formatter rule disable, failure-mode waiver, accept-with-rationale on a finding, "deferred with rationale" on a PRD open question — is logged with: who authorized, when, rationale, and a back-reference. The knowledge integrator periodically reviews escape hatch usage for patterns indicating doctrine or gate revision.

**Harness implementation:** Pattern-only at the doctrine level today; NL's harness-side equivalent is `enforcement-gap-analyzer` agent (auto-invoked on runtime FAIL) producing harness-improvement proposals. Project-level escape-hatch audit is forthcoming.

### Gate composition is AND, not OR

A unit is complete when every required gate is green. No gate has authority to mark a unit complete on its own; no gate can unilaterally fail-open. The composition is the verification.

---

## Open during fresh-draft phase

- **Project-specific thresholds.** Mutation score thresholds, hot path declarations, lint strictness — these live in per-project configuration referenced by gates, not in doctrine.
- **Performance budgets.** Some projects will need performance gates (latency, memory, bundle size). Drafted lightly here; can be added as project-specific gate type without doctrine change.
- **Security gates.** Credential scanning, dependency vulnerability scanning, SAST/DAST — covered by NL harness layers (`pre-push-scan.sh` for credential scanning + 18 built-in patterns; inline PreToolUse blockers on `.env`, `credentials.json`, etc.). Doctrine references NL; no separate gate definitions needed at the doctrine layer.
- **Gate runtime budgets.** Adversarial review especially can be expensive; tier-specific budgets and timeouts deferred.

## Next step

The integrated-v1 doctrine docs land first; subsequent Phase 1d-C work mechanizes the C-proposals. First-pass C-mechanization sequence per `outputs/unified-methodology-recommendation.md` §6: C1 → C2 → C10 → C9 → C7-DAG-gate → C16 → C22 → C15. After mechanization, the "forthcoming" caveats in this doc can be tightened to "landed" with implementation citations to the specific NL hooks and agents.
