# Plan: Phase 1d-C-2 — PRD-validity gate (C1) + spec-freeze gate (C2) + plan-header schema + behavioral contracts (C16)

Status: COMPLETED
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: HARNESS-GAP-10 sub-gap E (C16 behavioral-contracts validator must require concrete invariants — partially addressed)
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via per-hook `--self-test` invocations, plus a manual round-trip exercising a synthetic Mode: design plan with the new 5-field header through the extended plan-reviewer chain, plus a synthetic PRD through C1, plus a frozen plan + declared-file edit through C2.
tier: 2
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Context

Phase 1d-C-2 is the second batch of Build Doctrine §6 first-pass mechanisms (1d-C-1 shipped C10/C22/C7-DAG; 1d-C-3 ships C9 findings-ledger). Per SCRATCHPAD: C1 PRD-validity gate, C2 spec-freeze gate, plan-header schema enforcement, plus the locked decision that all five plan-header fields (`tier`, `rung`, `architecture`, `frozen`, `prd-ref`) are required with no defaults and `docs/prd.md` is single-per-project. This plan builds those mechanisms and extends `plan-reviewer.sh` to enforce the schema, and bundles C16 (`## Behavioral Contracts` schema check at `rung: 3+`) because it shares plan-reviewer infrastructure with the schema check and Build Doctrine §6 lists it in first-pass.

Source-of-truth: `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 + §9 Q4-A + §9 Q5-A + §9 Q6-A; integrated-v1 `04-gates.md` §3.1/3.2; integrated-v1 `05-implementation-process.md` Phase 2.

## Goal

Four mechanisms ship in one coherent unit so the plan-header schema (the prerequisite shared substrate) lands once and the gates stack on top:

1. **C1 `prd-validity-gate.sh`** — PreToolUse `Write` on `docs/plans/.*\.md` blocks plan creation that declares a `prd-ref:` resolving to a missing-or-incomplete `docs/prd.md`. Required PRD sections: problem, scenarios, functional, non-functional, success metrics, out-of-scope, open-questions (Build Doctrine §6 C1).
2. **C2 `spec-freeze-gate.sh`** — PreToolUse `Edit|Write` on files declared in any ACTIVE plan's `## Files to Modify/Create` section blocks edits unless that plan's header has `frozen: true`. The bypass is to either (a) flip `frozen: true` (with the freeze captured at the plan's commit SHA), or (b) move the file out of the plan's declared-files list.
3. **Plan-header schema enforcement** — `plan-reviewer.sh` Check 10 requires all five header fields (`tier: 1-5`, `rung: 0-5`, `architecture: coding-harness | dark-factory | auto-research | orchestration | hybrid`, `frozen: true|false`, `prd-ref: <slug>|n/a — harness-development`) on every plan with `Status: ACTIVE`. Missing or invalid values FAIL.
4. **C16 `## Behavioral Contracts` check** — `plan-reviewer.sh` Check 11 requires a `## Behavioral Contracts` section with four sub-entries (idempotency / performance budget / retry semantics / failure modes) when `rung: 3+`. Each sub-entry must have ≥ 30 non-whitespace chars (mirrors Check 6b).

Plus enabling work:
- `prd-validity-reviewer` agent — substance review of PRD content (PASS/FAIL with class-aware findings)
- `~/.claude/templates/prd-template.md` — canonical PRD shape with the 7 sections
- Plan template extension — 5 new header fields with placeholder values + inline guidance
- New rule docs: `~/.claude/rules/prd-validity.md`, `~/.claude/rules/spec-freeze.md`
- Updates to: `~/.claude/rules/planning.md`, `~/.claude/rules/vaporware-prevention.md` enforcement map, `~/.claude/rules/design-mode-planning.md`
- Decision records: 015 (PRD format + harness-dev exemption), 016 (spec-freeze semantics), 017 (plan-header schema locked), 018 (spec-section divergence — chose Build Doctrine §6 over SCRATCHPAD's unsourced `## Provides`/`## Consumes`/`## Dependencies`)
- Discovery file capturing the spec-section divergence so the user sees it at next session start

## Scope

**IN:**
- `adapters/claude-code/hooks/prd-validity-gate.sh` — new PreToolUse hook with `--self-test`
- `adapters/claude-code/hooks/spec-freeze-gate.sh` — new PreToolUse hook with `--self-test`
- `adapters/claude-code/hooks/plan-reviewer.sh` — extend with Check 10 (5-field schema) + Check 11 (C16 behavioral contracts)
- `adapters/claude-code/agents/prd-validity-reviewer.md` — new agent
- `adapters/claude-code/templates/prd-template.md` — new template
- `adapters/claude-code/templates/plan-template.md` — extend header with 5 new fields + guidance
- `adapters/claude-code/rules/prd-validity.md` — new rule
- `adapters/claude-code/rules/spec-freeze.md` — new rule
- `adapters/claude-code/rules/planning.md` — reference new fields + new rules
- `adapters/claude-code/rules/vaporware-prevention.md` — 4 new enforcement-map rows
- `adapters/claude-code/rules/design-mode-planning.md` — reference C16
- `adapters/claude-code/settings.json.template` — wire 2 new hooks (PreToolUse Write + Edit/Write)
- `~/.claude/` mirror sync per Windows install convention (per `2026-05-03-settings-template-vs-live-divergence` discovery)
- `docs/decisions/015-prd-validity-gate-c1.md`, `016-spec-freeze-gate-c2.md`, `017-plan-header-schema-locked.md`, `018-spec-section-divergence-from-scratchpad.md`
- `docs/decisions/index` updated with 4 new rows
- `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md`
- `docs/failure-modes.md` — extend with new failure classes for unfrozen-spec-edit + missing-PRD-on-plan-creation + missing-header-field + missing-behavioral-contracts-at-r3+ (4 new FM entries, sequential numbering)
- `docs/harness-architecture.md` — add new hooks + agent + templates to the inventory
- Migrate this plan from `~/.claude/plans/what-do-we-have-elegant-pudding.md` to `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` upon ExitPlanMode (the migration is itself a plan-task, since plan-mode restricts the initial path)
- Backfill the 5 required header fields on every existing ACTIVE plan in `docs/plans/` so they don't FAIL Check 10 the moment it lands. Default values for harness-development plans: `tier: 1`, `rung: 0`, `architecture: coding-harness`, `frozen: false`, `prd-ref: n/a — harness-development`.

**OUT:**
- C9 findings-ledger schema gate — Phase 1d-C-3 (separate plan; depends on C1/C2/schema being shipped first)
- C15 comprehension-gate agent — first-pass but later in the sequence (C1 → C2 → C10 → C9 → C7-DAG → C16 → C22 → C15 per Build Doctrine §6); depends on rung field landing first
- `## Provides` / `## Consumes` / `## Dependencies` sections — SCRATCHPAD-named but unsourced; Decision 018 documents the choice to defer until user specifies semantics. **NOT** implemented in this plan.
- Per-slug `docs/prd/<slug>.md` directory layout (Build Doctrine §6 C1 default) — SCRATCHPAD locks single `docs/prd.md` per project; Decision 015 records this divergence
- Downstream-project rollout — NL adopts the gates first; downstream projects opt in via separate per-project plans (per the user's confirmed pilot order, see `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §9 Q8)
- Telemetry collection (HARNESS-GAP-10 sub-gap D) — independent track on 2026-08 schedule
- Calibration-mimicry (Phase 1d-G) — DEFERRED, blocked on telemetry + C9
- Refactoring existing plan-reviewer Checks 1-9 — they stay as-is; new checks are additive

## Tasks

- [x] **1. Decisions and template upstream** — Land all four decision records (015/016/017/018), the discovery file, and the new PRD template + extended plan template. No hooks yet; this is the substrate that Tasks 2-7 build on. Single commit. **Files:** `docs/decisions/015-018.md`, `docs/decisions/index`, `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md`, `adapters/claude-code/templates/prd-template.md`, `adapters/claude-code/templates/plan-template.md`. **Acceptance:** all 4 decisions have substantive Context/Decision/Alternatives/Consequences sections; PRD template has the 7 named sections with placeholder guidance; plan template's header includes all 5 new fields with inline `<!-- -->` guidance.

- [x] **2. New rule docs** — `prd-validity.md` and `spec-freeze.md`. Cross-reference into `planning.md`, `vaporware-prevention.md`, and `design-mode-planning.md`. Single commit. **Files:** `adapters/claude-code/rules/prd-validity.md`, `adapters/claude-code/rules/spec-freeze.md`, plus 3 cross-reference edits. **Acceptance:** new rules each name their hook + agent partners, document the harness-dev carve-out (PRD) and the freeze-thaw protocol (spec), and follow the Classification: Hybrid pattern from existing rules.

- [x] **3. C1 — `prd-validity-gate.sh`** — PreToolUse `Write` matcher on `docs/plans/.*\.md`. Reads `prd-ref:` field from the new plan's header. If `prd-ref:` is `n/a — harness-development`, allow. Else resolve to `docs/prd.md`; verify file exists; verify all 7 required sections (problem / scenarios / functional / non-functional / success metrics / out-of-scope / open-questions) present with ≥ 30 non-ws chars each. Block on any failure with a clear message naming the failing section(s) + a pointer to the PRD template. `--self-test`: 6 scenarios (PASS-with-PRD, PASS-with-harness-dev-carveout, FAIL-no-prd-ref, FAIL-prd-file-missing, FAIL-prd-section-missing, FAIL-prd-section-placeholder). Single commit. **Files:** `adapters/claude-code/hooks/prd-validity-gate.sh`. **Acceptance:** all 6 self-test scenarios PASS; hook is idempotent against re-runs; harness-dev carve-out works.

- [x] **4. C2 — `spec-freeze-gate.sh`** — PreToolUse `Edit|Write` matcher. Reads tool_input file path. Iterates every `Status: ACTIVE` plan in `docs/plans/*.md`. For each, parses the `## Files to Modify/Create` section into a path list. If the tool_input file matches any path AND that plan's header has `frozen: false` or missing, BLOCK with a message: "File `<path>` is declared in plan `<plan-slug>` whose spec is not frozen. Either flip `frozen: true` in the plan header (after a final spec review), OR move the file out of the plan's `## Files to Modify/Create` list." Allow if no plan claims the file, OR all claiming plans are frozen, OR the file is in `docs/plans/` (the plan file itself — circular dependency avoidance). `--self-test`: 6 scenarios (PASS-no-plan-claims, PASS-frozen-plan, FAIL-unfrozen-plan, PASS-multiple-plans-all-frozen, FAIL-multiple-plans-one-unfrozen, PASS-plan-file-itself). Single commit. **Files:** `adapters/claude-code/hooks/spec-freeze-gate.sh`. **Acceptance:** all 6 scenarios PASS; gate degrades to allow if any parsing error (don't block on hook bugs); concurrent plan parsing tolerated.

- [x] **5. plan-reviewer.sh Check 10 — 5-field plan-header schema** — Extend `plan-reviewer.sh` with Check 10. Required fields: `tier:`, `rung:`, `architecture:`, `frozen:`, `prd-ref:`. Required values: `tier ∈ {1,2,3,4,5}`, `rung ∈ {0,1,2,3,4,5}`, `architecture ∈ {coding-harness, dark-factory, auto-research, orchestration, hybrid}`, `frozen ∈ {true, false}`, `prd-ref` is non-empty (any string; semantic validation belongs to C1, not the schema check). FAIL on missing field, invalid value, or empty. Gate on `Status: ACTIVE` only (DEFERRED/COMPLETED/ABANDONED/SUPERSEDED plans don't need fresh schema). Add 5 new self-test scenarios. **Files:** `adapters/claude-code/hooks/plan-reviewer.sh` (extension only; Checks 1-9 untouched). **Acceptance:** new self-tests pass; existing Checks 1-9 self-tests still pass (regression check).

- [x] **6. plan-reviewer.sh Check 11 — C16 `## Behavioral Contracts`** — Extend `plan-reviewer.sh` with Check 11. Gates on `rung ∈ {3, 4, 5}`. Requires `## Behavioral Contracts` section with four named sub-entries (`### Idempotency`, `### Performance budget`, `### Retry semantics`, `### Failure modes`), each with ≥ 30 non-ws chars and no placeholder-only content (mirrors Check 6b's substance check, including HTML-comment stripping and placeholder-token stripping). Add 5 new self-test scenarios (PASS-rung3-substantive, PASS-rung0-no-section-needed, FAIL-rung3-section-missing, FAIL-rung3-subentry-missing, FAIL-rung3-subentry-placeholder). **Files:** `adapters/claude-code/hooks/plan-reviewer.sh` (extension). **Acceptance:** all new self-tests pass; Checks 1-10 unchanged.

- [x] **7. `prd-validity-reviewer` agent** — New agent file at `adapters/claude-code/agents/prd-validity-reviewer.md`. Reads the plan file path + the resolved `docs/prd.md`. Adversarially reviews the PRD's substance: are problem and scenarios concrete? Are success metrics measurable (numeric targets, not adjectives)? Are out-of-scope items explicit? Does the PRD answer "what would success look like at T+30 days"? Returns PASS/FAIL/REFORMULATE with class-aware findings (per the 7 adversarial-review agents pattern). Invocable manually OR via the `prd-validity-gate.sh` recommend-invoke message on PASS-mechanical. **Files:** `adapters/claude-code/agents/prd-validity-reviewer.md`. **Acceptance:** agent definition follows the existing adversarial-reviewer template; class-aware Output Format Requirements section present; invocation guidance documented.

- [x] **8. Backfill 5 header fields on existing ACTIVE plans** — Three plans need backfill: `pre-submission-audit-mechanical-enforcement.md` (still ACTIVE per SCRATCHPAD; will be COMPLETED via separate session per user) AND any new plan files created during this work. Each gets: `tier: 1`, `rung: 0`, `architecture: coding-harness`, `frozen: false`, `prd-ref: n/a — harness-development`. Single commit. **Files:** every `docs/plans/*.md` with `Status: ACTIVE`. **Acceptance:** every active plan passes the new Check 10; no regression of existing checks.

- [x] **9. Wire hooks into `settings.json.template` AND `~/.claude/settings.json`** — Per the `2026-05-03-settings-template-vs-live-divergence` discovery, BOTH files must be updated in the same commit. Add `prd-validity-gate.sh` to PreToolUse Write chain (after `plan-deletion-protection.sh`, before `plan-edit-validator.sh`). Add `spec-freeze-gate.sh` to PreToolUse Edit/Write chain (after `plan-edit-validator.sh`, before `tool-call-budget.sh`). Update `harness-architecture.md` inventory. **Files:** `adapters/claude-code/settings.json.template`, `~/.claude/settings.json`, `docs/harness-architecture.md`. **Acceptance:** SessionStart's settings-divergence detector finds zero divergence; new hooks fire on a synthetic Edit attempt; `harness-architecture.md` lists both new hooks and the new agent.

- [x] **10. Failure modes catalog extension** — Add 4 new FM entries to `docs/failure-modes.md`: `FM-NNN unfrozen-spec-edit`, `FM-NNN missing-PRD-on-plan-creation`, `FM-NNN missing-plan-header-field`, `FM-NNN missing-behavioral-contracts-at-r3+`. Each with the 6-field schema (ID, Symptom, Root cause, Detection, Prevention, Example). Cross-reference each from the originating decision record (015/016/017). **Files:** `docs/failure-modes.md`. **Acceptance:** 4 new entries with substantive content; `harness-reviewer` finds them when reviewing this plan.

- [x] **11. Migrate plan to canonical location** — `git mv ~/.claude/plans/what-do-we-have-elegant-pudding.md docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`. Update SCRATCHPAD's "Active Plan" section to point at the new path. **Files:** the plan file itself; `SCRATCHPAD.md`. **Acceptance:** `scope-enforcement-gate.sh` finds the plan; `plan-lifecycle.sh` archives it correctly when Status flips to COMPLETED.

## Files to Modify/Create

- `adapters/claude-code/hooks/prd-validity-gate.sh` — NEW. PreToolUse Write on `docs/plans/.*\.md`. Validates `prd-ref` field + resolves to `docs/prd.md` + checks 7 required sections.
- `adapters/claude-code/hooks/spec-freeze-gate.sh` — NEW. PreToolUse Edit/Write. Iterates ACTIVE plans, checks if file is declared, blocks if any claiming plan has `frozen: false`.
- `adapters/claude-code/hooks/plan-reviewer.sh` — EXTEND. Add Check 10 (5-field schema) + Check 11 (C16 behavioral contracts) + 10 new self-test scenarios.
- `adapters/claude-code/agents/prd-validity-reviewer.md` — NEW. Adversarial reviewer for PRD substance.
- `adapters/claude-code/templates/prd-template.md` — NEW. Canonical 7-section PRD template.
- `adapters/claude-code/templates/plan-template.md` — EXTEND. Add 5 new header fields with inline guidance comments.
- `adapters/claude-code/rules/prd-validity.md` — NEW. Documents when PRDs are required, what they contain, harness-dev carve-out, agent-vs-mechanism enforcement split.
- `adapters/claude-code/rules/spec-freeze.md` — NEW. Documents the freeze-thaw protocol, who freezes when, allowlist semantics, recovery from spec drift.
- `adapters/claude-code/rules/planning.md` — EDIT. Add a paragraph referencing the 5 new header fields and pointing at the two new rule files.
- `adapters/claude-code/rules/vaporware-prevention.md` — EDIT. Add 4 enforcement-map rows (PRD-validity gate; spec-freeze gate; 5-field schema check; behavioral-contracts check).
- `adapters/claude-code/rules/design-mode-planning.md` — EDIT. Cross-reference Check 11 in the Enforcement summary table.
- `adapters/claude-code/settings.json.template` — EDIT. Wire 2 new hooks.
- `~/.claude/settings.json` — EDIT. Mirror the template wiring (per the template-vs-live divergence discovery).
- `docs/decisions/015-prd-validity-gate-c1.md` — NEW. Records: 7 required PRD sections; single `docs/prd.md` per project (divergence from Build Doctrine `docs/prd/<slug>.md`); harness-dev carve-out via `prd-ref: n/a — harness-development`.
- `docs/decisions/016-spec-freeze-gate-c2.md` — NEW. Records: `frozen: true|false` semantics; freeze-by-commit-SHA; thawing requires explicit `frozen: false` flip with rationale; recovery from drift.
- `docs/decisions/017-plan-header-schema-locked.md` — NEW. Records: 5 fields required with no defaults; valid value sets; gate on `Status: ACTIVE` only.
- `docs/decisions/018-spec-section-divergence-from-scratchpad.md` — NEW. Records: SCRATCHPAD's `## Provides`/`## Consumes`/`## Dependencies` not in any source-of-truth; Build Doctrine §6 + C16 chosen instead; deferral pending user specification.
- `docs/decisions/index` — EDIT. Add 4 new rows.
- `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md` — NEW. Discovery file (status: decided, auto-applied: true) so the user sees this divergence at next SessionStart.
- `docs/failure-modes.md` — EDIT. Add 4 FM entries.
- `docs/harness-architecture.md` — EDIT. Add 2 hooks + 1 agent + 1 template to inventory.
- `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` — NEW (post-migration of this file).
- `docs/plans/<every-active-plan>.md` — EDIT. Backfill 5 header fields.
- `SCRATCHPAD.md` — EDIT. Update "Active Plan" pointer post-migration.

## In-flight scope updates

- 2026-05-04: `docs/DECISIONS.md` — Task 1 builder discovered the canonical decisions index lives at `docs/DECISIONS.md` (uppercase), not `docs/decisions/index` as the original Files to Modify/Create bullet listed. Updated 4 new rows (decisions 015-018) in the existing index file.

## Assumptions

- The Build Doctrine source-of-truth at `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` §6 + §9 is authoritative for C1/C2/C16 mechanism specs. SCRATCHPAD's note about `## Provides`/`## Consumes`/`## Dependencies` is unsourced and is treated as a forward-note that did not survive the source-check. Decision 018 documents this.
- The 5-field schema is locked per SCRATCHPAD + Build Doctrine §9 Q4-A. No user-side decision is needed; this is implementation, not design.
- Single `docs/prd.md` per project is locked per SCRATCHPAD. The Build Doctrine §6 default of `docs/prd/<slug>.md` is overridden. Decision 015 documents this.
- Harness-development plans (this plan, plus all NL-internal plans) opt out of C1 via `prd-ref: n/a — harness-development`. No PRD is required for harness-internal work; the harness is its own product surface.
- `plan-reviewer.sh` Check 10 / 11 follow the section-presence + non-trivial-content pattern of Check 6b (lines 700-739): HTML-comment stripping, placeholder-token stripping, 20-30 char threshold for substance. Self-tests follow the inline-heredoc pattern of Checks 1-9.
- `spec-freeze-gate.sh` operates on the ACTIVE-plan set known to the cwd's repo. It does NOT recurse into worktrees or sibling repos; per `~/.claude/rules/agent-teams.md`'s multi-worktree pattern, an ACTIVE plan in another worktree of the same repo is invisible to the gate (acceptable: the user can flip `frozen: true` from any worktree, and the gate sees the most recent commit).
- `prd-validity-reviewer` is invoked manually by the planner OR by orchestrator dispatch; it does NOT replace `prd-validity-gate.sh`'s mechanical schema check. The agent reviews substance; the hook reviews shape. Build Doctrine §9 Q6-A confirms separate-from-systems-designer.
- The PRD template is a starting point; downstream projects adapt it. The 7 sections are required; sub-section structure is flexible.
- `plan-edit-validator.sh`'s evidence-first protocol applies to this plan's task checkboxes — only `task-verifier` flips them.

## Edge Cases

- **NL plans without `prd-ref`.** Every NL-internal plan gets `prd-ref: n/a — harness-development`. The carve-out string is exact (em-dash, exact phrasing) per the same convention as Check 8A's carve-out.
- **A plan claims a file in `docs/plans/`.** Plan files themselves can be edited even when `frozen: true` (e.g., adding evidence blocks or in-flight scope updates). The gate excludes `docs/plans/.*\.md` from the file-claim check to avoid circular blocking.
- **Two active plans claim the same file.** The gate fires if ANY claiming plan has `frozen: false`. To unblock, either freeze all claiming plans or remove the file from the unfrozen plan's declared list.
- **A plan is created and not yet committed (uncommitted plan file).** `prd-validity-gate.sh` runs at PreToolUse Write — it sees the staged content of the plan being written. If the `prd-ref` is set but the PRD file hasn't been created yet, the gate FAILs and the planner must create the PRD first.
- **`docs/prd.md` itself being edited.** Edits to `docs/prd.md` don't trigger C1 (which fires on plan creation, not PRD editing). The PRD's own sections can drift; that's a `prd-validity-reviewer` substance issue, not a mechanical-gate issue. (Out of scope: a PRD-edit-validity hook.)
- **A plan with `Status: ACTIVE` but missing a required header field.** Check 10 FAILs at the next plan-reviewer invocation. The planner is expected to backfill the field. Task 8 of this plan does this for existing plans pre-emptively.
- **`rung: 6` (out of valid range).** Check 10 FAILs with "rung must be 0-5; got: 6".
- **Architecture value `hybrid`.** Valid (per Build Doctrine §9 Q4-A). The check accepts the literal string "hybrid".
- **`frozen: true` set, then plan author wants to add a file.** Author MUST first flip `frozen: false`, add the file to `## Files to Modify/Create`, then re-flip `frozen: true`. The freeze-thaw is documented in the spec-freeze.md rule.
- **Concurrent plan-reviewer invocations.** Existing `plan-edit-validator.sh` flock pattern serializes plan-file edits. The new checks 10/11 inherit this serialization.
- **Hook fires on plan migration (Task 11's `git mv`).** `git mv` triggers PreToolUse Bash, not Write — so neither C1 nor the schema check fires on the migration itself. The migrated plan file's content satisfies all checks because Tasks 1-10 produce the correct shape.

## Acceptance Scenarios

(none — see `acceptance-exempt-reason` in the header. This plan has no UI surface; verification is via `--self-test` exit codes for hooks, plus manual round-trips of synthetic plans + PRDs through the new validators.)

## Out-of-scope scenarios

- Browser-automated end-to-end test of a downstream project adopting C1/C2 — per the rollout sequence (the first pilot project comes after this plan ships), downstream adoption gets its own plan with its own acceptance scenarios. This plan ships the substrate.
- Migration of all NL `docs/plans/*.md` to add example PRDs — harness-dev plans don't need PRDs (carve-out applies).
- Per-slug `docs/prd/<slug>.md` directory — Decision 015 forecloses; if a project later needs multiple PRDs, the carve-out is to bump the schema and revise C1, which is its own future plan.

## Testing Strategy

**Per-hook self-tests** (Tasks 3, 4, 5, 6):
- C1 hook: 6 scenarios via `--self-test` (PASS-with-PRD, PASS-with-harness-dev-carveout, FAIL-no-prd-ref, FAIL-prd-file-missing, FAIL-prd-section-missing, FAIL-prd-section-placeholder).
- C2 hook: 6 scenarios via `--self-test` (PASS-no-plan-claims, PASS-frozen-plan, FAIL-unfrozen-plan, PASS-multiple-plans-all-frozen, FAIL-multiple-plans-one-unfrozen, PASS-plan-file-itself).
- plan-reviewer Check 10: 5 scenarios (PASS-all-fields, FAIL-missing-tier, FAIL-invalid-rung, FAIL-invalid-architecture-enum, FAIL-empty-prd-ref).
- plan-reviewer Check 11: 5 scenarios (PASS-rung3-substantive, PASS-rung0-no-section-needed, FAIL-rung3-section-missing, FAIL-rung3-subentry-missing, FAIL-rung3-subentry-placeholder).
- Existing self-tests must still pass after extensions (regression).

**Manual round-trip verification** (after Task 9 wiring):
- Write a synthetic plan with `prd-ref: n/a — harness-development` → verify C1 allows.
- Write a synthetic plan with `prd-ref: my-feature` and no `docs/prd.md` → verify C1 blocks.
- Create `docs/prd.md` with all 7 sections substantive → re-attempt → verify C1 allows.
- Take an ACTIVE plan with `frozen: false` and try to edit a file in its `## Files to Modify/Create` → verify C2 blocks.
- Flip `frozen: true` in the plan → re-attempt the edit → verify C2 allows.
- Run `plan-reviewer.sh` against an ACTIVE plan with all 5 header fields → verify Check 10 allows.
- Add a synthetic plan with `rung: 3` and no `## Behavioral Contracts` → verify Check 11 blocks.

**Sync verification:** after Task 9, the SessionStart settings-divergence detector reports zero divergence between `adapters/claude-code/settings.json.template` and `~/.claude/settings.json`.

## Walking Skeleton

End-to-end the **shortest possible** path through the new mechanisms is:
1. Author writes a tiny PRD at `docs/prd.md` with the 7 required sections (each ≥ 30 chars).
2. Author creates a plan at `docs/plans/example.md` with `prd-ref: example-feature`, `tier: 2`, `rung: 1`, `architecture: coding-harness`, `frozen: false`.
3. PreToolUse Write fires `prd-validity-gate.sh` → resolves `prd-ref` to `docs/prd.md` → all 7 sections present and substantive → PASS → plan creation allowed.
4. `plan-reviewer.sh` Check 10 sees 5 fields present and valid → PASS.
5. Check 11 sees `rung: 1` → no `## Behavioral Contracts` required → PASS.
6. Author tries to edit `src/feature.ts` (declared in plan's `## Files to Modify/Create`).
7. PreToolUse Edit fires `spec-freeze-gate.sh` → finds plan, sees `frozen: false` → BLOCKS with "freeze the plan first."
8. Author flips `frozen: true` in the plan, commits.
9. Re-attempts the edit → C2 sees `frozen: true` → PASS → edit allowed.

If this walking skeleton works for a synthetic plan, the substrate is correct.

## Decisions Log

### Decision: Use Build Doctrine §6 as authoritative; defer SCRATCHPAD's `## Provides`/`## Consumes`/`## Dependencies` until specified

- **Tier:** 2 (reversible — adding the three sections later is a follow-up plan, not a revert)
- **Status:** auto-applied per the discovery-protocol decide-and-apply discipline
- **Chosen:** Implement C1 + C2 + C16 (`## Behavioral Contracts`) per Build Doctrine §6 source-of-truth. Skip the SCRATCHPAD-named `## Provides`/`## Consumes`/`## Dependencies` sections until the user specifies their semantics.
- **Alternatives considered:**
  - Implement Build Doctrine §6 verbatim (chosen). Sources are explicit; behavior is well-defined.
  - Implement SCRATCHPAD's three sections without specs. Rejected — I cannot validate sections whose content semantics are undefined; would produce a hook that fires but doesn't bind.
  - Surface to the user via `AskUserQuestion`. Considered. Per discovery-protocol's reversibility test, this decision is reversible (a follow-up plan adds the three sections if user clarifies). Auto-applying is consistent with the user's "continue autonomously" directive AND lets the C1+C2+C16 work proceed without blocking.
- **Reasoning:** The phrase "per the original C2 extension" in SCRATCHPAD is unsourced — no decision document, no Build Doctrine reference, no committed proposal defines what these sections contain. The previous session author either (a) made a chat-only decision the user approved that wasn't written down, (b) made an aspirational note, or (c) confused the section names with C16's `## Behavioral Contracts`. Building on undefined specs produces vaporware. Building on Build Doctrine §6 produces real mechanisms.
- **Reversal cost:** ~1-3 hours to add a follow-up plan with the three sections defined. Cheaper than building a hook against undefined semantics and rebuilding it.
- **Discovery file:** `docs/discoveries/2026-05-04-spec-section-divergence-from-scratchpad.md` — surfaces this divergence to the user at next SessionStart so they can confirm or amend.

### Decision: Single `docs/prd.md` per project (NOT `docs/prd/<slug>.md`)

- **Tier:** 3 (irreversible per project — once a project's PRD is at one path, downstream tooling assumes the layout)
- **Status:** SCRATCHPAD-locked; this plan implements the lock
- **Chosen:** Single `docs/prd.md` per project. Diverges from Build Doctrine §6 C1's default of `docs/prd/<slug>.md`.
- **Alternatives considered:** Per-slug PRDs would allow multiple feature PRDs per project. Rejected per SCRATCHPAD lock; one PRD per project is simpler and matches typical product-org practice.
- **Reasoning:** SCRATCHPAD's "Single `docs/prd.md` per project (C1-fmt)" is the user-side decision. Implementation honors it.
- **Decision record:** `docs/decisions/015-prd-validity-gate-c1.md`.

### Decision: Harness-development plans exempt from C1 via `prd-ref: n/a — harness-development`

- **Tier:** 1 (reversible by changing the carve-out string)
- **Status:** auto-applied
- **Chosen:** NL itself, plus any future harness-development project, declares `prd-ref: n/a — harness-development` to bypass C1. No `docs/prd.md` required.
- **Alternatives considered:** Write an NL PRD (rejected — NL is a harness for building products; its "users" are harness maintainers, not product users). Make harness-dev plans skip C1 entirely (rejected — the carve-out is preferred so the bypass is explicit and auditable).
- **Reasoning:** Mirrors the existing `acceptance-exempt: true` + `acceptance-exempt-reason` pattern. The carve-out is auditable; chronic use can be reviewed.
- **Decision record:** `docs/decisions/015-prd-validity-gate-c1.md`.

### Decision: 5 plan-header fields required, no defaults

- **Tier:** 2 (reversible by relaxing the schema)
- **Status:** SCRATCHPAD-locked + Build Doctrine §9 Q4-A
- **Chosen:** All 5 fields (`tier`, `rung`, `architecture`, `frozen`, `prd-ref`) required on `Status: ACTIVE` plans. No defaults; missing fields FAIL.
- **Alternatives considered:** Defaults for unspecified fields. Rejected — defaults silently propagate wrong shape.
- **Reasoning:** "All five fields required, no defaults" is the SCRATCHPAD lock. Implementation honors it.
- **Decision record:** `docs/decisions/017-plan-header-schema-locked.md`.

### Decision: C16 (behavioral contracts) bundled with C1+C2 as Phase 1d-C-2

- **Tier:** 2 (reversible by splitting C16 into 1d-C-2.5)
- **Status:** auto-applied
- **Chosen:** Bundle C16 with C1+C2 in this plan. Both extend `plan-reviewer.sh`; both depend on the rung field landing.
- **Alternatives considered:** Ship C16 as 1d-C-3 with C9. Rejected — C16 needs the rung field, and the rung field lands in this plan. Better to land both together so plan-reviewer extensions land once.
- **Reasoning:** Cohesion. The 5-field schema check and C16's rung-gated check share the rung-extraction code.
- **Decision record:** Documented inline in this plan's Decisions Log; not a standalone ADR (Tier 2, internal sequencing decision, not a structural change).

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, 12 behavior-change matches across §10 (Decision records), §1 (Outcome), and §6 (Observability); each cited in Tasks 1-11 and Files to Modify/Create.
S2 (Existing-Code-Claim Verification): swept, 8 references to existing files (plan-reviewer.sh lines 700-739, settings.json.template, end-user-advocate, plan-edit-validator.sh, scope-enforcement-gate.sh, plan-lifecycle.sh, harness-architecture.md, discoveries/2026-05-03-*); all verified against current repo state via Read/Grep.
S3 (Cross-Section Consistency): swept, all "5 fields required" claims agree across header, Goal, Tasks 5/8, Files to Modify/Create; "harness-dev carve-out" identical phrasing in Decisions Log + Edge Cases + Goal + Files; "single docs/prd.md" identical claim in Goal + Decisions Log + Files; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept for params [non_ws_count_threshold=20-30, self_test_scenarios={6,6,5,5}, FM_entries=4, decisions=4]; values consistent across Tasks 3/4/5/6 + Acceptance + Testing Strategy.
S5 (Scope-vs-Analysis Check): swept, all "Add" / "Modify" / "Replace" verbs in §1-§10; all checked against Scope OUT (C9, C15, per-slug PRDs, downstream-project rollout, telemetry, calibration-mimicry, plan-reviewer Checks 1-9 refactor); 0 contradictions found.

## Definition of Done

- [ ] All 11 tasks checked off via `task-verifier`
- [ ] All hook self-tests pass (4 hooks × 5-6 scenarios = ~22 self-test scenarios total + existing regression suite)
- [ ] Manual round-trip verification (per Testing Strategy) confirms C1, C2, Check 10, Check 11 fire correctly on synthetic inputs
- [ ] `~/.claude/` mirror sync produces zero divergence per the SessionStart detector
- [ ] All 4 decision records committed and referenced from `docs/decisions/index`
- [ ] Discovery file at `docs/discoveries/` set to `Status: decided`, `auto_applied: true`
- [ ] Plan file migrated from `~/.claude/plans/` to `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`
- [ ] SCRATCHPAD updated; "Active Plan" pointer fresh
- [ ] Completion report appended to plan file

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Within 30 minutes of a maintainer attempting to (a) create a plan without a valid PRD reference, (b) edit a file declared in an unfrozen plan, (c) commit a plan with missing header fields, or (d) leave a Rung-3+ plan without behavioral contracts, the harness blocks with a specific actionable message naming the gap and pointing at the rule + template that resolves it. Within 24 hours of this plan landing, every existing ACTIVE plan in `docs/plans/` passes the new Check 10 (backfilled in Task 8). Within 7 days, the maintainer has run synthetic round-trip exercises confirming all four mechanisms fire correctly on positive and negative cases.

The user-side outcome: spec drift mid-build (FM-A `unfrozen-spec-edit`) becomes mechanically impossible without an explicit `frozen: true` flip; PRD-less plan creation (FM-B `missing-PRD-on-plan-creation`) becomes mechanically impossible without the harness-dev carve-out; plan-header drift (FM-C `missing-plan-header-field`) becomes mechanically impossible at plan-reviewer time; behavioral-contract underspecification at Rung 3+ (FM-D `missing-behavioral-contracts-at-r3+`) becomes mechanically impossible.

### 2. End-to-end trace with a concrete example

T=0: maintainer wants to add a feature to a downstream project (a Next.js app, hypothetically). They write `docs/prd.md` with the 7 required sections, each ≥ 30 chars (problem: 8-line description; scenarios: 3 named scenarios; functional: 5 numbered FRs; non-functional: 3 NFRs; success metrics: 4 numeric targets; out-of-scope: 4 explicit OOS items; open-questions: 2 listed questions).

T=5min: maintainer creates `docs/plans/duplicate-campaign.md` with header: `Status: ACTIVE`, `Mode: code`, `Execution Mode: orchestrator`, `tier: 2`, `rung: 1`, `architecture: coding-harness`, `frozen: false`, `prd-ref: duplicate-campaign-feature`.

T=5min:01s: PreToolUse Write fires `prd-validity-gate.sh`. Hook reads plan from tool_input. Extracts `prd-ref: duplicate-campaign-feature`. Resolves to `docs/prd.md`. Reads PRD. Verifies 7 sections present. Each substance-check (≥ 30 non-ws chars). PASS. Plan creation allowed.

T=5min:02s: PreToolUse Write also fires `plan-reviewer.sh`. Check 6b (existing) runs section presence. Check 7 (existing) runs Mode: design 10-section gate (skipped — Mode: code). Check 8A (existing) skipped — Mode: code. Check 9 (existing) skipped — Mode: code. **Check 10 (NEW)** runs: `tier: 2` ✓, `rung: 1` ✓, `architecture: coding-harness` ✓, `frozen: false` ✓, `prd-ref: duplicate-campaign-feature` ✓. PASS. **Check 11 (NEW)** runs: `rung: 1` < 3, no behavioral contracts required, PASS. Plan-reviewer overall PASS.

T=10min: maintainer fills in `## Files to Modify/Create` with `src/components/CampaignList.tsx`, `src/api/campaigns/duplicate.ts`. Commits the plan. Existing `plan-edit-validator.sh` allows (no checkbox flips yet).

T=15min: maintainer attempts to edit `src/components/CampaignList.tsx` (Edit tool). PreToolUse Edit fires the chain. `plan-edit-validator.sh` (existing) — not editing a plan file, allow. `tool-call-budget.sh` (existing) — within budget, allow. **`spec-freeze-gate.sh` (NEW)** — extracts file path `src/components/CampaignList.tsx`. Iterates `docs/plans/*.md` with `Status: ACTIVE`. Finds `duplicate-campaign.md`. Parses its `## Files to Modify/Create` section. Sees `src/components/CampaignList.tsx` listed. Reads `frozen: false`. **BLOCKS** with: "File `src/components/CampaignList.tsx` is declared in plan `duplicate-campaign` whose spec is not frozen. Either flip `frozen: true` in the plan header (after a final spec review), OR move the file out of the plan's `## Files to Modify/Create` list."

T=16min: maintainer reads the message. Re-reads the plan and PRD. Decides spec is correct. Edits the plan: `frozen: false` → `frozen: true`. Commits.

T=17min: re-attempts the file edit. `spec-freeze-gate.sh` re-runs. Sees `frozen: true`. PASS. Edit allowed. Build proceeds.

The end-to-end trace involves five new gates firing across two hooks plus two extended plan-reviewer checks. Each has a clear visible outcome at each boundary. The blocked-then-unblocked transition at T=15min → T=17min is the load-bearing flow this plan creates.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| Plan author (Edit/Write tool) | `prd-validity-gate.sh` | Plan file content available via `tool_input.file_path` + `tool_input.new_content`. Hook reads via standard PreToolUse JSON stdin shape. Within 200ms (file read + 7 grep operations). |
| `prd-validity-gate.sh` | Plan author | Exit 0 = allow; Exit 1 = block + stderr message naming missing PRD section(s). Exit 2 reserved for input-parse errors. JSON output empty (rely on exit code per `scope-enforcement-gate.sh` precedent). |
| Plan author (Edit tool) | `spec-freeze-gate.sh` | `tool_input.file_path` is a forward-slash-normalized absolute or repo-relative path. Hook normalizes to repo-relative, then matches against each plan's `## Files to Modify/Create` entries. |
| `spec-freeze-gate.sh` | Plan author | Same exit semantics as C1. Stderr names the blocking plan(s) and the file path. Within 1s (parses up to ~50 plans × ~10ms each). Note: the hook degrades to ALLOW (with stderr warning) on any plan-parse error to avoid hook-bug-induced lockout. |
| Plan author (Edit/Write on plan) | `plan-reviewer.sh` Checks 10/11 | Existing trigger surface (PreToolUse Edit/Write on plan files). Hook reads plan content directly from the tool_input. Within existing 2s budget. |
| `plan-reviewer.sh` | Plan author | Existing FAIL-on-first-finding behavior (early-break). Check 10 + Check 11 follow the same `add_finding` + `break` pattern as existing checks. |
| `prd-validity-gate.sh` | `prd-validity-reviewer` agent (recommended invocation) | On PASS-mechanical, hook prints to stdout: "Mechanical check passed. For substance review of the PRD, run: `Task(subagent_type='prd-validity-reviewer', plan='<path>', prd='docs/prd.md')`". This is a recommendation, not enforcement. The agent is invoked manually or via orchestrator dispatch. |
| Plan author | `prd-validity-reviewer` agent | Plan path + PRD path as arguments. Agent reads both files. Returns PASS / FAIL / REFORMULATE with class-aware findings (`Class:` + `Sweep query:` + `Required generalization:` per the existing 7 adversarial-review agents pattern). |

The contract surface is small (4 inputs, 4 outputs across the new mechanisms). All hooks follow established harness conventions; no new contract shapes.

### 4. Environment & execution context

Each hook runs in:
- **Working directory:** the repo root where the tool fired (Claude Code sets this automatically). On Windows, paths are forward-slash-normalized to match the bash environment.
- **Shell:** Git Bash (Windows) or default bash (macOS/Linux). The hooks use POSIX shell + standard utilities (`awk`, `grep`, `sed`, `tr`, `wc`).
- **Pre-installed tools:** `git`, `awk`, `grep`, `sed`, `bash`, `jq`. The hooks do NOT depend on any project-specific tooling.
- **Env vars:** `CLAUDE_PROJECT_DIR` (set by Claude Code). The hooks DON'T read `~/.claude/local/*` config; they read plan and PRD files directly from the cwd.
- **Ephemeral:** state — per-invocation. No state files written by the new hooks (unlike `tool-call-budget.sh` which keeps a counter at `~/.claude/state/`).
- **Persistent:** the harness rules + templates + decision records ship in the repo and `~/.claude/` mirror; they survive sessions.
- **VM destruction:** on cloud sessions (`claude --remote`), `~/.claude/` is NOT inherited. The hooks live at `adapters/claude-code/hooks/` and are inherited via project `.claude/` per Decision 011 Approach A. Not in scope here, but worth noting: a downstream project that adopts this plan's mechanisms gets full enforcement on cloud sessions if they've populated `.claude/` per Decision 011.

### 5. Authentication & authorization map

No external auth boundaries. All four mechanisms operate on local files (`docs/plans/*.md`, `docs/prd.md`, `docs/failure-modes.md`). No GitHub API, no Anthropic API, no Supabase, no external service calls.

`prd-validity-reviewer` agent runs in the standard Claude Code agent invocation context — inherits the lead session's auth (CLAUDE_CODE_OAUTH_TOKEN). No new auth boundary.

### 6. Observability plan (built before the feature)

Each new hook prints structured stderr on every fire:
- `prd-validity-gate.sh`: `[prd-validity] plan=<path> prd-ref=<value> verdict=PASS|FAIL reason=<short>`
- `spec-freeze-gate.sh`: `[spec-freeze] file=<path> matched-plans=<count> verdict=PASS|FAIL`
- `plan-reviewer.sh` Check 10: appends to existing structured log via `add_finding`
- `plan-reviewer.sh` Check 11: same as 10

A maintainer reconstructing what happened from logs alone sees: which hook fired, which file it gated on, which plan(s) it inspected, the verdict, and the reason. Sufficient for debugging.

The `harness-review` skill (existing) eventually scans these stderr messages aggregated to detect chronic FAIL patterns (e.g., "spec-freeze-gate FAILed 12 times this week — consider reviewing why specs aren't being frozen consistently"). Not in scope here, but the structured log shape supports future aggregation.

### 7. Failure-mode analysis per step

| Step | Failure mode | Symptom | Recovery / retry | Escalation |
|---|---|---|---|---|
| Plan creation (C1) | PRD file missing | Block message names missing file | Author creates `docs/prd.md` with template | If author claims PRD exists at non-canonical path, reject — single canonical path enforced |
| Plan creation (C1) | PRD section missing | Block names section | Author adds section per template | If section is intentionally minimal, ≥ 30 chars threshold can be met with one substantive paragraph |
| Plan creation (C1) | `prd-ref` field syntax error | Block names invalid value | Author fixes syntax | If carve-out string is paraphrased, reject — exact match required |
| Plan creation (C1) | Hook itself crashes | Hook prints stderr error + exit 2 (input-parse error) | Bash retry | If hook self-test scenarios pass but real fire fails, log a discovery |
| File edit (C2) | File declared in unfrozen plan | Block names plan + suggests freeze-or-remove | Author flips `frozen: true` OR removes file from declared list | If file is in 5+ plans, manual review of plan boundaries |
| File edit (C2) | File path doesn't normalize | Hook degrades to ALLOW with warning stderr | Author retries — usually a one-off | If recurrent, log discovery; consider Windows path normalization tweaks |
| File edit (C2) | Plan file parse error | Hook degrades to ALLOW with warning | Author manually verifies plan integrity | If recurrent across plans, plan-reviewer regression — fix it |
| Plan-reviewer Check 10 | Header field syntax error | Plan-reviewer FAIL with field name | Author fixes header | If field is added but value is non-canonical, reject |
| Plan-reviewer Check 11 | Rung 3+ plan w/o contracts | FAIL names missing sub-entry | Author adds sub-entry | If author argues rung is wrong, downgrade to rung 2 |
| Manual round-trip (Tests) | Self-test fails | Hook output names failing scenario | Fix hook code | If scenario is impossible to satisfy, redesign the check |
| Settings sync (Task 9) | Template-vs-live divergence | SessionStart detector reports diff | Apply diff to whichever side is stale | If repeated, examine install.sh — the discovery from 2026-05-03 documents this trap |
| Plan migration (Task 11) | `git mv` fails | Bash error | Resolve git state, retry | If file is dirty, commit first |
| Backfill (Task 8) | An existing plan resists schema | Manual edit needed | Author adds 5 fields | If a plan was archived prematurely, recover from archive first |

### 8. Idempotency & restart semantics

- **C1 hook re-runs:** safe. Reads plan + PRD; no state mutation. Re-running produces same verdict.
- **C2 hook re-runs:** safe. Same shape — read-only.
- **Plan-reviewer Check 10/11 re-runs:** safe. Existing pattern.
- **Decision records (Task 1):** idempotent — committing the same content twice is a no-op (git detects no diff). If author re-runs Task 1 mid-build with edits, only the diff lands.
- **Backfill (Task 8):** idempotent. If a plan already has all 5 fields, no edit happens.
- **Plan migration (Task 11):** non-idempotent — `git mv` fails on second invocation if the destination already exists. This is intentional — the migration is a one-shot.
- **Hook wiring (Task 9):** idempotent — the SessionStart detector verifies post-condition; if hooks are already wired, no edits land.

**Restart semantics:** if the orchestrator dies mid-plan, recovery is `git status` + `git diff` to see what's staged + read the plan file to see which checkboxes are checked. Re-invoke the orchestrator on the next session; it picks up from the next unchecked task. No mid-build state is held outside the plan file + commits.

### 9. Load / capacity model

**Throughput limits:**
- C1 fires once per plan creation (rare — maybe 5-10/week per maintainer)
- C2 fires on every Edit/Write — could be 100s/day. Each invocation iterates ~10-50 ACTIVE plans × ~10ms each = ~100-500ms per fire.
- Check 10/11 fire on every plan-file Edit — same volume as existing plan-reviewer checks (~50/day for a busy harness-dev session)

**Bottleneck:** C2's iteration over all ACTIVE plans. At 50 plans × 10ms/parse = 500ms — within the 1s PreToolUse hook budget but on the higher side. Optimization: cache the list of declared files in a state file at `.claude/state/spec-freeze-cache.json` regenerated on plan-file Edit; C2 reads cache instead of re-parsing all plans. **Out of scope for first implementation; flag in backlog if observed slowness.** With current ~5-10 ACTIVE plans typical, no optimization needed.

**Saturation behavior:** if C2 takes > 5s, Claude Code may surface a "hook timeout" warning. Mitigation: hook degrades to ALLOW after an internal 2s timeout with stderr warning. The maintainer sees a warning but the build doesn't lock up.

### 10. Decision records & runbook

**Decisions (recorded as ADRs in Task 1):**
- Decision 015: PRD format (single file, 7 sections) + harness-dev carve-out
- Decision 016: spec-freeze semantics (frozen: true|false, freeze-by-commit-SHA, freeze-thaw protocol)
- Decision 017: 5-field plan-header schema locked, no defaults
- Decision 018: spec-section divergence from SCRATCHPAD; chose Build Doctrine §6 source-of-truth + C16

Plus inline decision-log entries above for the 5th decision (C16 bundled with C1+C2 vs separate).

**Runbook entries** (added to Decision 016's body):

| Symptom | Diagnostic | Fix |
|---|---|---|
| `spec-freeze-gate.sh` blocks every Edit | Run `bash adapters/claude-code/hooks/spec-freeze-gate.sh --self-test` | If self-test passes, check `git log --all` for uncommitted plan with broken `## Files to Modify/Create` syntax; otherwise file the regression as P1 |
| `prd-validity-gate.sh` blocks valid PRDs | Verify all 7 sections each have ≥ 30 non-ws chars | If sections are visibly substantive but blocked, run `--self-test` to confirm hook integrity |
| Plan-reviewer Check 10 reports "missing tier" on a plan that has tier | Confirm syntax: `tier: 2` not `tier:2` (space required) | Fix syntax; or suspect a regex bug |
| C2 fires too slowly | Check `git ls-files docs/plans/*.md \| wc -l` | If > 50 plans, archive completed/deferred ones via `plan-lifecycle.sh` |
| `~/.claude/settings.json` divergence flagged at SessionStart | Diff template vs live | Apply the template to live (or vice versa, depending on which is correct) |
| Hook crashes with exit 2 | Stderr names parse error | Read the offending file; fix syntax |

---

# Completion Report

## 1. Implementation Summary

All 11 tasks shipped across 10 commits (`aa15c99`..`0658758`). Each task verified PASS by `task-verifier`; evidence at [`phase-1d-c-2-prd-validity-and-spec-freeze-evidence.md`](phase-1d-c-2-prd-validity-and-spec-freeze-evidence.md).

| Task | Description | Commit | task-verifier verdict |
|------|-------------|--------|------------------------|
| 1 | Decisions 015-018 + discovery + PRD template + plan-template extension (9 files) | `dc97f33` | PASS (9/10) |
| 2 | Rule docs `prd-validity.md` + `spec-freeze.md` + 4 cross-refs (6 files) | `b4406c8` | PASS (9/10) |
| 3 | C1 `prd-validity-gate.sh` (PreToolUse Write; 6/6 self-tests) | `d929261` | PASS (10/10) |
| 4 | C2 `spec-freeze-gate.sh` (PreToolUse Edit/Write/MultiEdit; 6/6 self-tests) | `ffd7e2c` | PASS (9/10) |
| 5 | `plan-reviewer.sh` Check 10 — 5-field plan-header schema (5 new self-test scenarios) | `8ff6a0c` | PASS (10/10) |
| 6 | `plan-reviewer.sh` Check 11 — `## Behavioral Contracts` at rung ≥ 3 (5 new scenarios; 22/22 total) | `8ff6a0c` | PASS (10/10) |
| 7 | `prd-validity-reviewer` agent — adversarial PRD substance review | `9350d87` | PASS (9/10) |
| 8 | Backfilled 5 header fields on `pre-submission-audit-mechanical-enforcement.md` | `8123d39` | PASS (9/10) |
| 9 | Wired both hooks into `settings.json.template` + live `~/.claude/settings.json` | `099d4e2` | PASS (10/10) |
| 10 | Failure-mode catalog +4 entries (FM-018..FM-021) | `0658758` | PASS (10/10) |
| 11 | Plan migrated from `~/.claude/plans/...` to canonical `docs/plans/...` | `aa15c99` | PASS (10/10) |

**Backlog items shipped:** HARNESS-GAP-10 sub-gap E (C16 behavioral-contracts validator concrete-invariants requirement). Built and shipped via Check 11 + FM-021. Substance check (>= 30 non-ws chars + placeholder-token stripping) covers vacuous-filler rejection. Deeper semantic validation (e.g., "idempotency must reference a specific input -> output mapping") is paper-only at C16; flagged as a follow-up note in FM-021 if substance check proves insufficient in practice.

## 2. Design Decisions & Plan Deviations

**Decisions:**

- **Decision 018 — Build Doctrine §6 authoritative; SCRATCHPAD's `## Provides`/`## Consumes`/`## Dependencies` deferred** (Tier 2 reversible). The SCRATCHPAD note proved unsourced. Auto-applied per discovery-protocol decide-and-apply discipline. **Confirmed by user** in their 2026-05-04 SCRATCHPAD edit: "That was an unsourced proposal I made conversationally and propagated to SCRATCHPAD treating silence-as-confirmation. The source-spec'd content is C16's `## Behavioral Contracts`. Removed."
- **Decision 015 — Single `docs/prd.md` per project** (Tier 3, SCRATCHPAD-locked). Diverges from Build Doctrine §6 C1's `docs/prd/<slug>.md` default; SCRATCHPAD lock honored. Confirmed by user.
- **Decision 015 — Harness-dev carve-out via `prd-ref: n/a — harness-development`** (Tier 1). NL plans bypass C1 with this exact-string declaration. Confirmed by user.
- **Decision 017 — 5-field plan-header schema locked, no defaults** (Tier 2, SCRATCHPAD-locked + Build Doctrine §9 Q4-A).
- **C16 bundled with C1+C2** (Tier 2, inline). C16 needs the rung field; bundling avoids two plan-reviewer.sh extension passes.

**Plan deviations:**
- **Worktree-base bug.** Parallel-mode dispatch via `isolation: "worktree"` created worktrees at master (`10adac2`) instead of branching from current HEAD (`aa15c99`). Builder B (Task 7) was BLOCKED because the plan file wasn't visible inside its worktree. Recovered by copying the staged agent file to the main repo. Subsequent tasks ran sequentially in the main repo.
- **`docs/decisions/index` actually at `docs/DECISIONS.md`.** Builder A discovered during Task 1; noted as in-flight scope update.
- **Pre-existing generic codename in self-test fixtures (Tasks 5+6).** harness-hygiene-scan blocked initial commit; builder rephrased to generic terms.

## 3. Known Issues & Gotchas

- **Pre-existing template-vs-live divergence for OTHER hooks** (NOT introduced by Phase 1d-C-2): `outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, `automation-mode-gate`, `public-repo-blocker` variants. Reconcile in a follow-up. Not blocking.
- **plan-reviewer Check 1 / Check 7 noise on this plan file itself.** 6 pre-existing findings (5× Check 1 sweep-language + 1× Check 7 design-mode shallowness). Tracked as HARNESS-GAP-09. Pre-existing.
- **Locked worktrees** at `.claude/worktrees/agent-a71e77d16bccba12a` and `.claude/worktrees/agent-a2ed8e5e0db4208d2`. Claude Code worktree manager handles cleanup. Not blocking.

## 4. Manual Steps Required

- None for the harness itself. The gates are LIVE on next session start.
- Downstream-project rollout is its own series of plans; opt-in per project.

## 5. Testing Performed & Recommended

**Performed:**
- C1 `--self-test`: 6/6 PASS.
- C2 `--self-test`: 6/6 PASS.
- `plan-reviewer.sh --self-test`: 22/22 PASS (zero regression).
- Live-repo end-to-end exercise of C2 against a synthetic file claim — PASS.
- Both gates wired byte-identically in template AND live settings.json.

**Recommended:**
- Run plan-reviewer.sh against EVERY plan in `docs/plans/*.md` (active + archive) to confirm no surprise regressions.
- Exercise the gates on a real PRD authoring flow during the first downstream-project rollout.

## 6. Cost Estimates

Zero ongoing cost. Local-only bash hooks + one local-only agent prompt. No cloud services, third-party APIs, or infrastructure spend. Per-invocation latency: <= 200ms per the C2 capacity model in §9.
