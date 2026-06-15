# Plan: Parallel-Dev Discipline — Bake Trunk-Based CI/CD Into the Harness
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: build-harness-infrastructure work; the deliverables are a rule file, a PreToolUse hook, and settings.json wiring — no product user-facing runtime. Self-tests (the hook's --self-test) are the acceptance artifact, per the build-harness-infrastructure work-shape.
tier: 2
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Bake a parallel-dev CI/CD discipline into the neural-lace harness so EVERY Claude Code session follows it by default — Mechanism where the failure is silent and high-cost, Pattern + SessionStart surfacing where the discipline is judgment-shaped. The discipline prevents four real failures observed this week across multi-machine / multi-session work on a single codebase: (1) migration-number collision causing silent schema loss; (2) diverged remotes; (3) uncommitted accumulation; (4) two machines on the same task. The intellectual frame is trunk-based development applied to the agent-driven, multi-machine case.

## User-facing Outcome

The harness's "user" is the maintainer (and every Claude session). After this plan ships:
- A session that creates a migration with a bare sequential-integer prefix (`168_*.sql`) is BLOCKED at commit with a clear remediation (use a UTC timestamp) — the silent-schema-loss collision can no longer occur. (Mechanism — active now via `migration-naming-gate.sh`.)
- Every session has the seven trunk-based practices as its loaded standard (`parallel-dev-discipline.md`), surfaced contextually like every other harness rule.
- The exact `gh` commands to configure branch protection + a merge queue are documented in the rule for the operator to run once per repo.

## Scope

- IN:
  - `adapters/claude-code/rules/parallel-dev-discipline.md` — the 7-practice rule (+ one-item=one-branch=one-machine), Hybrid classification, cross-refs, enforcement table, scope, documented-not-executed `gh` commands.
  - `adapters/claude-code/hooks/migration-naming-gate.sh` — PreToolUse Bash gate blocking bare-integer-prefixed newly-added migrations; `--self-test`.
  - `adapters/claude-code/rules/INDEX.md` — new row (CI golden test requires it).
  - `adapters/claude-code/settings.json.template` + live `~/.claude/settings.json` — wire the gate into the PreToolUse Bash chain.
  - `docs/harness-architecture.md` — PreToolUse table row, hook-scripts table row, rules-table row, PreToolUse count bump.
  - Live `~/.claude/` sync of rule + hook (byte-identical) + settings wiring — active NOW.
- OUT:
  - Executing branch-protection / merge-queue `gh` commands (coordination-sensitive; documented only, operator runs them).
  - Touching any downstream-product migrations (the gate is harness-only; product migration back-catalogs are grandfathered and untouched).
  - Merging to neural-lace master (orchestrator reconciles in curation — master is messy with deferred RWR-27).
  - Extending `session-start-git-freshness.sh` (it already surfaces "BEHIND remote — pull before working"; verified by self-test, no change needed).

## Tasks

- [ ] 1. Write `parallel-dev-discipline.md` rule (7 practices + work-board item, each tied to its failure; documented `gh` commands). — Verification: mechanical
- [ ] 2. Write `migration-naming-gate.sh` + `--self-test` (integer BLOCKED, timestamp ALLOWED, non-migration IGNORED, existing-untouched ALLOWED, no-staged no-op, malformed fail-safe). — Verification: mechanical
- [ ] 3. Add INDEX.md row; verify rules-index-coverage golden test passes. — Verification: mechanical
- [ ] 4. Wire the gate in BOTH `settings.json.template` and live `~/.claude/settings.json`; validate JSON. — Verification: mechanical
- [ ] 5. Verify `session-start-git-freshness.sh` already surfaces "BEHIND remote — pull before working" (run its self-test); extend only if missing. — Verification: mechanical
- [ ] 6. Update `docs/harness-architecture.md` (rule + hook + PreToolUse rows + count). — Verification: mechanical
- [ ] 7. Sync canonical→live `~/.claude/` for rule + hook byte-identical (`diff -q`); confirm gate wiring identical in template + live; run live hook self-test. — Verification: mechanical
- [ ] 8. harness-reviewer on rule + hook (or self-applied if Task tool unavailable). — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/rules/parallel-dev-discipline.md` — CREATE: the rule.
- `adapters/claude-code/hooks/migration-naming-gate.sh` — CREATE: the gate + self-test.
- `adapters/claude-code/rules/INDEX.md` — MODIFY: add the rule's row.
- `adapters/claude-code/settings.json.template` — MODIFY: wire the gate in PreToolUse Bash chain.
- `docs/harness-architecture.md` — MODIFY: PreToolUse row + hook-scripts row + rules-table row + PreToolUse count.
- `~/.claude/rules/parallel-dev-discipline.md` — SYNC: byte-identical live mirror.
- `~/.claude/hooks/migration-naming-gate.sh` — SYNC: byte-identical live mirror.
- `~/.claude/settings.json` — MODIFY: identical gate wiring in live PreToolUse chain.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- `session-start-git-freshness.sh` already surfaces the "behind remote — pull" message (verified: its self-test T3 exercises exactly that). No extension needed.
- The migration runner (`supabase db push` and equivalents) applies migrations in lexical order and treats a duplicate prefix as already-applied, silently skipping the second — this is the documented behavior the gate prevents triggering.
- Live `~/.claude/settings.json` carries pre-existing machine-local `permissions` content not in the template, so full-file byte-identical settings.json is neither expected nor desirable; the *gate-wiring entry* is what must match (verified identical).
- The branch `feat/parallel-dev-discipline` was already checked out in a sibling worktree by a parallel agent attempt; this worktree uses `feat/parallel-dev-discipline-a11e` to avoid the collision (flagged for orchestrator reconciliation).

## Edge Cases
- Existing integer-named migrations in history: GRANDFATHERED — gate checks only `--diff-filter=A` (added files).
- Prisma layout: the number lives in the directory name, not the file — gate extracts the directory component.
- Same-second timestamp collision across two machines: vanishingly rare and visibly distinguished by the descriptive slug; acceptable residual (orders-of-magnitude safer than a guaranteed-collision shared counter).
- Non-commit Bash, malformed input, no-staged-files: gate is a no-op / fail-safe ALLOW (never blocks unrelated work).
- A migration named with a 14-digit value that is NOT a valid date (e.g. `99999999999999_x`): the gate accepts it as a timestamp-shaped prefix (it does not validate calendar validity — out of scope; the collision-prevention property holds regardless).

## Acceptance Scenarios
- n/a — acceptance-exempt (build-harness-infrastructure; self-tests are the acceptance artifact).

## Out-of-scope scenarios
- n/a — acceptance-exempt.

## Testing Strategy
- `migration-naming-gate.sh --self-test`: 23 assertions (11 prefix-predicate, 4 name-extraction, 8 git-integration) covering every required scenario + Supabase/generic/Prisma/mixed/non-commit/malformed. MUST pass.
- `session-start-git-freshness.sh --self-test`: 8/8 PASS confirms the "BEHIND remote — pull" surfacing is intact (Deliverable 3 verification).
- `evals/golden/rules-index-coverage.sh`: confirms INDEX↔rules bidirectional sync after the new row.
- `jq -e` on both settings.json files: confirms JSON validity after wiring.
- `diff -q` on rule + hook canonical-vs-live: confirms byte-identical sync.

## Walking Skeleton
The gate IS the thinnest end-to-end slice: a single PreToolUse Bash hook whose `--self-test` exercises the full block/allow decision against a real git index. There are no layers to thread — the hook's self-test passing is the harness's user-facing outcome (the maintainer's `--self-test` PASS). The rule + wiring make it loaded + active.

## Decisions Log
### Decision: distinct branch name to avoid sibling-worktree collision
- **Tier:** 1 (reversible)
- **Status:** proceeded
- **Chosen:** `feat/parallel-dev-discipline-a11e` in this worktree.
- **Reasoning:** `feat/parallel-dev-discipline` is already checked out in sibling worktree `agent-aa2d265dac62a51e5` (a parallel agent attempt). Git forbids two worktrees on one branch. Using a distinct suffix lets this worktree commit cleanly; the orchestrator reconciles the two attempts in curation. Flagged in the return.

### Decision: timestamp-only enforcement (not calendar-validated)
- **Tier:** 1
- **Status:** proceeded
- **Chosen:** the gate requires a 14-digit (or 8+sep+6) prefix shape; it does NOT validate that the digits form a real calendar date.
- **Alternatives:** full date-validation (rejected — adds complexity for no safety gain; the collision-prevention property is about uniqueness-without-coordination, which any timestamp-shaped prefix provides; `date -u +%Y%m%d%H%M%S` always produces a valid one).
- **Reasoning:** the failure being prevented is the SHARED COUNTER, not malformed dates. A 14-digit prefix from `date` is correct by construction.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code build-harness-infrastructure plan; not Mode: design.
- S2 (Existing-Code-Claim Verification): swept — freshness-hook BEHIND-surfacing claim verified by running its self-test (8/8); settings.json structure verified by reading both files; INDEX golden test verified by running it.
- S3 (Cross-Section Consistency): swept — gate behavior described identically in rule, hook header, harness-architecture rows, and this plan.
- S4 (Numeric-Parameter Sweep): n/a — no numeric design parameters.
- S5 (Scope-vs-Analysis Check): swept — every "Add/Modify" target is in `## Files to Modify/Create`; no Scope-OUT target prescribed (gh-execution, downstream-product migrations, master-merge all OUT and not touched).

## Definition of Done
- [ ] All tasks checked off (by task-verifier in curation)
- [ ] `migration-naming-gate.sh --self-test` passes (23/23)
- [ ] INDEX golden test passes
- [ ] Both settings.json files valid JSON with gate wired
- [ ] Rule + hook byte-identical canonical↔live
- [ ] Committed on feature branch, pushed
- [ ] harness-reviewer verdict recorded

## Completion Report

_Generated by close-plan.sh on 2026-06-15T10:58:25Z._

### 1. Implementation Summary

Plan: `docs/plans/parallel-dev-discipline-2026-06-14.md` (slug: `parallel-dev-discipline-2026-06-14`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/migration-naming-gate.sh`
- `adapters/claude-code/rules/INDEX.md`
- `adapters/claude-code/rules/parallel-dev-discipline.md`
- `adapters/claude-code/settings.json.template`
- `docs/harness-architecture.md`
- `~/.claude/hooks/migration-naming-gate.sh`
- `~/.claude/rules/parallel-dev-discipline.md`
- `~/.claude/settings.json`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19a7ab7 Component B reconciler v1 — orchestrator wake-trigger + reconcile loop (single-machine, surface-first) (#58)
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2590947 feat(hook): pre-push-divergence-check — block stale-fetch pushes to master (#47)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2dc69a5 feat(drift-detection): 3-component harness-internal cross-repo drift detection (#34)
3203d01 fix(hooks): scope-enforcement-gate evaluates the commit's TARGET repo + gates PowerShell (HARNESS-GAP-47)
331e048 feat(hooks): session-start cheatsheet + credential-asking guard (hygiene-2 PR 2/3) (#54)
3402cd6 feat(hooks): land customer-facing-review gate from 2026-06-02 salvage (ADR 053, renumbered from 046)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
38a6ea9 feat(rules): information-architecture rule — canonical content router (#51)
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
