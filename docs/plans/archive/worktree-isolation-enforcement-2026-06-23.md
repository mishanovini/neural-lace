# Plan: Worktree-Isolation Enforcement (advisor + teardown gate)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the two hooks' `--self-test` suites are the acceptance artifact. No product user / runtime surface.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Encourage per-session git-worktree isolation so concurrent sessions stop colliding on the shared main checkout (the 18-sessions-on-one-folder problem), WITHOUT firing on the many legitimate cases where a worktree is the wrong tool. Two mechanisms: a SessionStart **advisor** that auto-injects tailored guidance (the start side, which a hook cannot force, only inform), and a Stop **teardown gate** that prevents a session from ending inside a worktree with unpreserved (uncommitted) work — steering toward preserve-first, never toward `--force` deletion (honors "incomplete ≠ abandoned"). Uses the `build-harness-infrastructure` work-shape.

## User-facing Outcome
Every session is *told* the right worktree behavior at start (tailored: silent when already isolated, loud on the shared main checkout of a multi-worktree repo, gentle otherwise), and no session can call itself complete having left uncommitted work stranded in a worktree — while never being pressured to delete unmerged work. The "user" is the maintainer; the self-tests are the observable proof.

## Scope
- IN: two new hooks + self-tests; a Hybrid rule documenting the exemption set; settings wiring (template + live); rules INDEX row; harness-architecture entry; one ADR.
- OUT: forcing start-in-worktree (not hook-achievable — cwd is set before SessionStart); a PreToolUse `git worktree add` marker-writer (failure-mode-2 "created-then-cd-away orphan" is a named v1 limitation); cloud/remote sessions (don't load `~/.claude/` hooks).

## Tasks
- [ ] 1. `session-start-worktree-advisor.sh` (SessionStart, additionalContext) + `--self-test` — Verification: mechanical
- [ ] 2. `worktree-teardown-gate.sh` (Stop, retry-guard + fresh-waiver) + `--self-test` — Verification: mechanical
- [ ] 3. `rules/worktree-isolation.md` (Hybrid) + rules `INDEX.md` row — Verification: mechanical
- [ ] 4. `docs/harness-architecture.md` hook-inventory entries + `settings.json.template` wiring (SessionStart + Stop) + live `~/.claude/settings.json` sync (verify diff) — Verification: mechanical
- [ ] 5. ADR `docs/decisions/NNN-worktree-isolation-enforcement.md` + `docs/DECISIONS.md` index row — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/session-start-worktree-advisor.sh` — create (Task 1)
- `adapters/claude-code/hooks/worktree-teardown-gate.sh` — create (Task 2)
- `adapters/claude-code/rules/worktree-isolation.md` — create (Task 3)
- `adapters/claude-code/rules/INDEX.md` — modify: add the worktree-isolation row (Task 3)
- `adapters/claude-code/settings.json.template` — modify: wire both hooks (Task 4)
- `docs/harness-architecture.md` — modify: add both hooks to the inventory (Task 4)
- `docs/decisions/DECISIONS.md` — modify: add ADR index row (Task 5) [path resolved at build time: docs/DECISIONS.md]
- `docs/decisions/057-worktree-isolation-enforcement.md` — create: the ADR (Task 5) [number resolved at build time]

## In-flight scope updates
- 2026-06-23: `docs/DECISIONS.md` — the ADR index lives at `docs/DECISIONS.md` (the Files list's `docs/decisions/DECISIONS.md` was a path typo); ADR row for 057 added here.
- 2026-06-23: `docs/plans/worktree-isolation-enforcement-2026-06-23.md` — this plan file itself (committed alongside the build).

## Assumptions
- neural-lace hooks are pure bash with `--self-test`; no npm needed in the worktree (verified 2026-06-23).
- The retry-guard lib (`lib/stop-hook-retry-guard.sh`) is the canonical Stop-gate loop-break; the teardown gate sources it like `bug-persistence-gate.sh`.
- Worktree detection is reliable: main checkout has `git rev-parse --git-dir` == `--git-common-dir`; a linked worktree has them differ.
- The ADR number (057 placeholder) is resolved against `docs/DECISIONS.md` at build time.

## Edge Cases
- A1 read-only / A2 on-master-by-necessity / A3 already-isolated / A4 non-git / A5 locked-or-peer worktree / A6 tiny edit / A7 hotfix — full set in `worktree-isolation.md` and ADR 057.
- B1 (load-bearing): teardown gate steers to preserve-first (commit/stash/push), NEVER `--force` — honors "incomplete ≠ abandoned".
- B2: no liveness signal ⇒ the gate scopes to the CURRENT session's own cwd worktree only; never touches peer worktrees. Failure-mode-2 (created-then-cd-away orphan) is a named v1 limitation.
- B6: main checkout always has churn ⇒ never gated.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal). The two `--self-test` suites are the acceptance artifact.

## Out-of-scope scenarios
- n/a

## Testing Strategy
- Each hook ships a `--self-test` matrix (the build-harness-infrastructure oracle). Task 1: not-git / in-worktree / main+worktrees(loud) / main+none(gentle). Task 2: main-checkout-noop / non-git / clean-worktree-pass / dirty-worktree-BLOCK / locked-exempt / unpushed-advise / waiver-pass. Both must report 0 failed before checkbox flip.
- Settings wiring verified by `jq` parse of template + live after edit.

## Walking Skeleton
Thinnest slice: the advisor hook detecting main-vs-worktree and emitting one tailored line, self-test green — proves the SessionStart injection + detection path end-to-end before the teardown gate's richer logic.

## Decisions Log
- D1: v1 teardown gate is cwd-scoped (the session's own worktree), not marker-based. Rationale: no reliable liveness signal; cwd-scoping is high-precision and structurally cannot touch a peer's worktree (A5/B2). Failure-mode-2 named as a limitation rather than covered by a riskier marker-writer. Reversible: a marker-writer can be added later.
- D2: BLOCK only on uncommitted-in-worktree (clear loss-on-removal); ADVISE (non-blocking) on unpushed-committed (survives worktree removal; dies only on branch -D, which branch-hygiene governs). Keeps false-positive rate low to avoid trust erosion.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code harness plan, not Mode: design.
- S2 (Existing-Code-Claim Verification): swept — model hooks (`session-start-git-freshness.sh`, `bug-persistence-gate.sh`, `lib/stop-hook-retry-guard.sh`) read in full this session; API confirmed.
- S3 (Cross-Section Consistency): swept — exemption set consistent between this plan, the rule, and the design doc.
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters beyond retry-guard's inherited threshold.
- S5 (Scope-vs-Analysis Check): swept — all declared files are under `adapters/claude-code/` or `docs/`; matches build-harness-infrastructure scope.

## Definition of Done
- [ ] Both hooks' `--self-test` report 0 failed
- [ ] Rule + INDEX row + harness-architecture entries landed
- [ ] Settings wired (template + live, jq-valid)
- [ ] ADR + index row landed
- [ ] Synced to `~/.claude/`, diff-verified byte-identical
- [ ] Committed, pushed, PR opened on the PT-org neural-lace remote (origin)
- [ ] Plan COMPLETED + archived

## Completion Report

_Generated by close-plan.sh on 2026-06-23T08:25:23Z._

### 1. Implementation Summary

Plan: `docs/plans/worktree-isolation-enforcement-2026-06-23.md` (slug: `worktree-isolation-enforcement-2026-06-23`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/session-start-worktree-advisor.sh`
- `adapters/claude-code/hooks/worktree-teardown-gate.sh`
- `adapters/claude-code/rules/INDEX.md`
- `adapters/claude-code/rules/worktree-isolation.md`
- `adapters/claude-code/settings.json.template`
- `docs/decisions/057-worktree-isolation-enforcement.md`
- `docs/decisions/DECISIONS.md`
- `docs/harness-architecture.md`

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
