# Plan: Build Doctrine Tranche 0b — Phase 0 Migration

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: dialogue-only
frozen: true
prd-ref: n/a — harness-development
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; pure content migration of doctrine docs from a sibling repo into NL plus directory scaffolding for the templates layer. No product-user surface; verification is by the `definition-on-first-use-gate.sh --self-test` passing against the migrated content.

## Goal

Close the Phase 0 foundation step that should have shipped weeks ago. The Build Doctrine plan explicitly specifies the doctrine should live at `neural-lace/build-doctrine/doctrine/01-principles.md` etc. inside NL. The 8 integrated-v1 doctrine docs (~38000 words) have been authored at `~/claude-projects/Build Doctrine/outputs/integrated-v1/` but never migrated into NL itself.

This tranche:
1. Creates `neural-lace/build-doctrine/` directory with `README.md` + `CHANGELOG.md` per plan spec
2. Migrates the 8 integrated-v1 doctrine docs into `neural-lace/build-doctrine/doctrine/`
3. Creates `neural-lace/build-doctrine-templates/` directory with `README.md` + `CHANGELOG.md` + `VERSION` + 7 empty subdirectories — same-repo placement (NOT a separate repo) per the roadmap's preamble decision
4. Lands `docs/decisions/025-build-doctrine-same-repo-placement.md` recording the same-repo decision
5. Verifies `definition-on-first-use-gate.sh` fires correctly on the migrated content (currently a no-op because it has nothing to scan)

After this tranche, every doctrine reference in NL has a real path to resolve to, and Tranches 2-7 of the Build Doctrine roadmap become unblocked.

## Scope

- IN: New `neural-lace/build-doctrine/` directory tree with README + CHANGELOG + 8 doctrine docs migrated from `Build Doctrine/outputs/integrated-v1/`. New `neural-lace/build-doctrine-templates/` directory tree with README + CHANGELOG + VERSION + 7 empty subdirectories (each with `.gitkeep`). New ADR `docs/decisions/025-build-doctrine-same-repo-placement.md` + matching index row in `docs/DECISIONS.md`. Verification that `definition-on-first-use-gate.sh --self-test` still passes (no regression) and that a fresh `git commit` touching one of the migrated doctrine docs would either pass cleanly or surface a clear acronym-undefined error.
- OUT: Authoring of new doctrine content (the 8 docs are migrated as-is from integrated-v1; any edits are limited to fixing path references that change because of the migration). Authoring of template schemas (Tranche 2). Authoring of template default content (Tranche 3). Updates to existing NL rule files that reference the doctrine — those references already use the future path `neural-lace/build-doctrine/...` and will start resolving correctly after this tranche lands.

## Tasks

- [ ] 1. Create `neural-lace/build-doctrine/` directory with `README.md` (~30-50 lines: purpose, what's inside, cross-reference to roadmap + Build Doctrine plan) and `CHANGELOG.md` (initial entry: `2026-05-05 — Phase 0 migration: 8 integrated-v1 doctrine docs migrated from Build Doctrine repo`).
- [ ] 2. Copy the 8 integrated-v1 doctrine docs from `~/claude-projects/Build Doctrine/outputs/integrated-v1/` to `neural-lace/build-doctrine/doctrine/`. Files: `01-principles.md`, `02-roles.md`, `03-work-sizing.md`, `04-gates.md`, `05-implementation-process.md`, `06-propagation.md`, `08-project-bootstrapping.md`, `09-autonomy-ladder.md`. (Note: `07-knowledge-integration.md` is deferred per Q9 — not in this migration; will land in Tranche 5.)
- [ ] 3. Create `neural-lace/build-doctrine-templates/` directory with `README.md` (~20-30 lines: purpose, three-layer rendering convention, cross-reference to doctrine `08-project-bootstrapping.md` for the universal floors), `CHANGELOG.md` (initial entry: `2026-05-05 — directory created; same-repo placement per roadmap decision`), `VERSION` (`0.1.0` — pre-content seed). Create 7 empty subdirectories each with a `.gitkeep`: `prd/`, `adr/`, `spec/`, `design-system/`, `engineering-catalog/`, `conventions/`, `observability/`.
- [ ] 4. Author `docs/decisions/025-build-doctrine-same-repo-placement.md` recording the decision to keep `build-doctrine-templates` in the same repo as NL (rejecting the original three-repo architecture from the Build Doctrine plan). Format: standard ADR with Status / Stakeholders / Context / Decision / Alternatives / Consequences. Reference: roadmap doc preamble where the decision is laid out.
- [ ] 5. Add a row to `docs/DECISIONS.md` index for ADR 025 (atomicity-driven per `decisions-index-gate.sh`).
- [ ] 6. Verify `definition-on-first-use-gate.sh --self-test` still passes after migration (run from `~/.claude/hooks/`). Verify a synthetic commit touching one of the migrated doctrine docs produces clean gate behavior (either passes because all acronyms are defined in the glossary, or surfaces a clear actionable error). Capture evidence.
- [ ] 7. Update `docs/build-doctrine-roadmap.md` Quick status table: Tranche 0b row from NOT STARTED → DONE, populate "Completed in" with `2026-05-05`. Add a Recent Updates entry naming the migration.
- [ ] 8. Update `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md` Phase 0 line in the Phase plan table from `pending` to `complete`. (This file is in a sibling repo; touching it requires a separate commit there. Document the cross-repo update in the evidence; user can sync the sibling repo after.)

## Files to Modify/Create

- `build-doctrine/README.md` — NEW (~30-50 lines)
- `build-doctrine/CHANGELOG.md` — NEW (~10 lines initial)
- `build-doctrine/doctrine/01-principles.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/02-roles.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/03-work-sizing.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/04-gates.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/05-implementation-process.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/06-propagation.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/08-project-bootstrapping.md` — NEW (migrated from integrated-v1)
- `build-doctrine/doctrine/09-autonomy-ladder.md` — NEW (migrated from integrated-v1)
- `build-doctrine-templates/README.md` — NEW (~20-30 lines)
- `build-doctrine-templates/CHANGELOG.md` — NEW (~10 lines initial)
- `build-doctrine-templates/VERSION` — NEW (single line: `0.1.0`)
- `build-doctrine-templates/prd/.gitkeep` — NEW (empty)
- `build-doctrine-templates/adr/.gitkeep` — NEW (empty)
- `build-doctrine-templates/spec/.gitkeep` — NEW (empty)
- `build-doctrine-templates/design-system/.gitkeep` — NEW (empty)
- `build-doctrine-templates/engineering-catalog/.gitkeep` — NEW (empty)
- `build-doctrine-templates/conventions/.gitkeep` — NEW (empty)
- `build-doctrine-templates/observability/.gitkeep` — NEW (empty)
- `docs/decisions/025-build-doctrine-same-repo-placement.md` — NEW (~80-120 lines ADR)
- `docs/DECISIONS.md` — MODIFY (one row added for ADR 025)
- `docs/build-doctrine-roadmap.md` — MODIFY (Quick status row + Recent updates; happens at plan completion)

## In-flight scope updates

- 2026-05-05 (orchestrator pre-builder-resume): `adapters/claude-code/hooks/harness-hygiene-scan.sh` — MODIFY. Add `build-doctrine/*` and `build-doctrine-templates/*` to `is_path_shape_exempt()`. Discovered when Builder B's first commit attempt was blocked by the heuristic-cluster detector firing ~190 hits on legitimate doctrine vocabulary (Tranche, Engineering, Catalog, Curator, Adversarial, Findings, Mechanical, Orchestrator, Architecture, etc.) that aren't in `NL_VOCAB_ALLOWLIST`. The structural fix matches the existing pattern: NL-internal harness directories like `adapters/`, `principles/`, `patterns/` are already exempt because their prose legitimately cites paths and uses domain vocabulary repeatedly; `build-doctrine/` and `build-doctrine-templates/` belong to the same class. Sync to live `~/.claude/hooks/harness-hygiene-scan.sh`. Self-test: PASS. Commit: `b5cdccb`.
- 2026-05-05 (Builder B during build): doctrine docs ARE NOT byte-identical to integrated-v1 source — codenames sanitized to generic placeholders per harness-hygiene rule ("no product codenames" — `~/.claude/rules/harness-hygiene.md`). Source docs in `~/claude-projects/Build Doctrine/outputs/integrated-v1/` are in a gitignored repo and may carry real codenames; the migrated copies in `neural-lace/build-doctrine/doctrine/` strip codenames so the harness layer can be public-shareable. The `## Testing Strategy` section's `diff -r` byte-identical check is therefore amended: 5 of 8 docs ARE byte-identical (`01-principles.md`, `03-work-sizing.md`, `04-gates.md`, `05-implementation-process.md`, `09-autonomy-ladder.md`); 3 of 8 contain codename-anonymization diffs only (`02-roles.md`, `06-propagation.md`, `08-project-bootstrapping.md`). Substance is preserved.
- 2026-05-05 (Builder B during build): `docs/discoveries/2026-05-05-doctrine-content-codenames-vs-hygiene-scanner.md` — NEW. Captures the codename-vs-hygiene encounter as a process discovery. Marks the structural exemption (now landed) as the resolved path; documents Builder B's anonymization approach for future doctrine migrations.

## Assumptions

- The 8 integrated-v1 doctrine docs at `~/claude-projects/Build Doctrine/outputs/integrated-v1/` are the canonical, current content. Verified in this session via the build-doctrine-roadmap inventory. No re-authoring needed.
- The `definition-on-first-use-gate.sh` already exists at `adapters/claude-code/hooks/definition-on-first-use-gate.sh` (verified in earlier session) and is wired in `settings.json.template` — Tranche 0b only needs to verify it works correctly post-migration.
- The glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md` (322 lines) is authoritative; the gate references it via the documented fallback path. After migration, the gate's path resolution still works because the gate already supports both the canonical glossary path AND a `${REPO}/build-doctrine/outputs/glossary.md` fallback (this fallback won't fire because we don't migrate the glossary in this tranche — that's a follow-up).
- `docs/DECISIONS.md` exists and follows the standard one-row-per-ADR convention. Verified by inspection.
- `docs/build-doctrine-roadmap.md` exists at the path used in this plan. Verified — committed in `c3494fc`.

## Edge Cases

- **Glossary not migrated.** The gate looks for the glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md` first (canonical), then falls back to `${REPO}/build-doctrine/outputs/glossary.md`. Migration of the glossary itself is OUT of this tranche — the canonical path still resolves on the user's machine. Future tranche (or follow-up) can migrate or symlink the glossary if desired.
- **Acronym-undefined errors after migration.** If the migrated docs contain an acronym not in the glossary, the gate will block the commit. Expected resolution paths: (a) add the acronym to the glossary, (b) define the acronym in-context within the doc itself. Task 6 captures this as part of verification.
- **ADR 025 numbering collision.** Confirmed via `ls docs/decisions/` that 024 is the highest existing number; 025 is free.
- **Cross-repo Build Doctrine plan update (Task 8).** The build-doctrine-plan.md file lives in a sibling repo (`~/claude-projects/Build Doctrine/`). Updating it from NL requires either: (a) a separate commit in the sibling repo, (b) handing off to the user, or (c) skipping the sibling-repo update and noting it as a follow-up. Task 8 chooses (a) — the builder should make the cross-repo edit and document it in the evidence. The user can sync the sibling repo after.

## Acceptance Scenarios

(plan is acceptance-exempt — see header `acceptance-exempt-reason`)

## Out-of-scope scenarios

(none — acceptance-exempt)

## Testing Strategy

Per Task 6: run `definition-on-first-use-gate.sh --self-test` and verify it still exits 0. Then synthesize a `git commit` (staged but not committed) touching one of the migrated doctrine docs and verify the gate either passes cleanly OR produces a clear actionable error naming the undefined acronym. Capture command + output as evidence.

Manual verification: confirm the migrated doctrine docs are byte-identical to the integrated-v1 source via `diff -r ~/claude-projects/Build\ Doctrine/outputs/integrated-v1/ neural-lace/build-doctrine/doctrine/`. Capture command output as evidence.

## Walking Skeleton

(n/a — pure migration plan)

## Decisions Log

### Decision: Same-repo placement for build-doctrine-templates

- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Keep `build-doctrine-templates` as a subdirectory of `neural-lace/` (same repo as the rest of the harness).
- **Alternatives:** (a) separate `build-doctrine-templates` repo per the original Build Doctrine plan's three-repo architecture (rejected — at current scale, one user with no projects pinning template versions, separation adds friction without paying for itself; if/when real projects pin different versions, splitting via `git subtree split` is straightforward); (b) keep templates inside `build-doctrine/` rather than a sibling directory (rejected — separates template *content* from doctrine *shape*, which is the original three-repo plan's correct content split; sibling-directory placement preserves the split without requiring a separate repo).
- **Reasoning:** Premature separation is harder to undo than premature consolidation. Roadmap doc preamble lays out the full rationale.
- **Checkpoint:** N/A
- **To reverse:** `git subtree split` to extract `build-doctrine-templates/` into its own repo if/when real version-pinning need emerges.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in Goal/Scope is cited at task entry points
S2 (Existing-Code-Claim Verification): swept — verified `definition-on-first-use-gate.sh` exists, settings.json wires it, glossary path resolves, integrated-v1 docs exist at the source path, ADR 024 is highest existing decision number
S3 (Cross-Section Consistency): swept — Goal, Scope, Tasks, Files-to-Modify all agree on the migration scope
S4 (Numeric-Parameter Sweep): swept — 8 doctrine docs (excluding 07-knowledge-integration), 7 template subdirectories, ADR 025, all consistent
S5 (Scope-vs-Analysis Check): swept — every "Migrate/Create" verb in Goal/Scope is matched by a Files-to-Modify entry; OUT clause correctly excludes new content authoring + template schemas + template default content (those are Tranches 2-3)

## Definition of Done

- [ ] All 8 tasks task-verifier-flipped to `[x]`
- [ ] Each task has an evidence block with `Verdict: PASS` in the companion `-evidence.md` file
- [ ] All 8 doctrine docs byte-identical to integrated-v1 source
- [ ] `definition-on-first-use-gate.sh --self-test` exits 0
- [ ] ADR 025 + DECISIONS.md row landed atomically
- [ ] `docs/build-doctrine-roadmap.md` Quick status row updated to DONE
- [ ] Status: ACTIVE → COMPLETED transition triggers auto-archive

## Evidence Log

(populated by task-verifier in the closure phase)

## Completion Report

(populated by orchestrator at closure)
