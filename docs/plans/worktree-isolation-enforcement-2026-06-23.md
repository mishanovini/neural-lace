# Plan: Worktree-Isolation Enforcement (advisor + teardown gate)
Status: ACTIVE
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
