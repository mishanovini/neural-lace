# Plan: Worktree-spawn primitive + verified isolation rules
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: single-script harness primitive + convention-doc update; no new external dependency
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal tooling; the script's `--self-test` (9/9) plus the committed verification evidence are the acceptance artifact — there is no product user to advocate for.
Backlog items absorbed: none

## Goal
Close the gap `docs/conventions/worktree-per-session.md` named ("no
worktree-spawn primitive") by shipping a decision-aware primitive that decides
whether a session needs an isolated git worktree and, if so, creates a
predictably-named one. Motivation: a PROVEN cross-session collision — a working
tree has one HEAD; concurrent sessions sharing the main checkout race on it, so
a sibling's `git checkout` flips it and another session's commit lands on the
wrong branch (observed 2026-05-26: a session-wrap commit landed on
`pattern-3-file-lifecycle-plan`; reproduced deterministically). Build-harness-
infrastructure work-shape (every file under `adapters/claude-code/` or `docs/`).

## Scope
- IN: the `spawn-worktree.sh` primitive (decision matrix + create + cd + remove + self-test); convention-doc update with verified findings, decision matrix, and primitive usage; harness-architecture script-table row; a committed verification-evidence artifact.
- OUT: a SessionStart "working-tree occupancy" warning gate (surfaced as a remaining gap, not built); an ADR-number allocation primitive (separate gap); changing the native Claude Code `--worktree` flag behavior (out of our control — documented, not modified).

## Tasks
- [ ] 1. Research the auto-isolation mechanism + collision root cause; verify against filesystem + official docs. — Verification: mechanical
- [ ] 2. Build `adapters/claude-code/scripts/spawn-worktree.sh` with the decision matrix + `--self-test`. — Verification: mechanical
- [ ] 3. Update `docs/conventions/worktree-per-session.md` (verified rules, decision matrix, primitive, corrections) + `docs/harness-architecture.md` script table. — Verification: mechanical
- [ ] 4. Capture verification evidence (self-test, collision reproduction, 3 session-type decisions, apply/remove round-trip, dogfood short-circuit). — Verification: mechanical

## Files to Modify/Create
- `docs/plans/worktree-spawn-primitive.md` — this plan (gate-endorsed "open a new plan" for genuinely-separate orphan harness work; the 3 sibling-session active plans do not claim these files).
- `adapters/claude-code/scripts/spawn-worktree.sh` — the primitive (committed in 67a2146).
- `docs/conventions/worktree-per-session.md` — verified rules + decision matrix + primitive usage (committed in 67a2146).
- `docs/harness-architecture.md` — script-table row for the primitive (committed in 67a2146).
- `adapters/claude-code/scripts/spawn-worktree-selftest-evidence.md` — committed execution evidence (co-located with the script).

## In-flight scope updates
- (none)

## Assumptions
- Misha's commit identity (`mishanovini`) is correct when local git config is unset (verified from history).
- The official Claude Code worktree docs (`code.claude.com/docs/en/worktrees`) accurately describe `--worktree`/`worktree.baseRef`/`.worktreeinclude`/cleanup as of 2026-05; the filesystem evidence on this machine corroborates the per-session 1:1 mapping.
- Git Bash on this machine emits `git rev-parse --show-toplevel` in canonical `C:/...` form, which `git worktree list` also uses (the primitive standardizes on this form for reliable string compares).

## Edge Cases
- Caller already inside a worktree → short-circuit, never nest (handled + tested).
- Branch name already exists → attach instead of `-b` (handled).
- Re-run with same slug → idempotent reuse (tested).
- Windows empty-husk dir after `worktree remove` → best-effort rmdir; de-registration is the success criterion (mirrors `worktree-prune.sh`).
- A worktree starts WITHOUT gitignored files (SCRATCHPAD.md, .env) unless `.worktreeinclude` lists them (documented).

## Testing Strategy
- `spawn-worktree.sh --self-test`: 9 scenarios (read-only skip; commits+unknown isolate w/ reason text; commits+alone skip; apply creates `session/<slug>`; idempotent reuse; already-isolated short-circuit; `--branch` override; `--remove`; bad-`--type` rejected).
- Live verification against the real repo (decisions for 3 session types, apply+remove round-trip, dogfood short-circuit) captured in `adapters/claude-code/scripts/spawn-worktree-selftest-evidence.md`.
- Deterministic collision reproduction included in the evidence artifact.

## Walking Skeleton
The thinnest end-to-end slice: `spawn-worktree.sh <slug> --type commits --apply --print-cd` → creates `.claude/worktrees/<slug>` on `session/<slug>` from `origin/HEAD` and prints the cwd → caller `cd`s in → commits land on the isolated branch, never on a sibling's. Verified by the apply/remove round-trip in the evidence artifact.

## Decisions Log
### Decision: open a new plan to resolve the scope-enforcement cross-session false-fire
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** create this lightweight plan claiming the work's files (gate option 2).
- **Alternatives:** (a) `git commit --no-verify` — rejected, no current-chat bypass authorization per gate-respect.md; (b) defer the evidence artifact — rejected, A8 vaporware-volume-gate then blocks PR create; (c) piggyback the evidence on a sibling plan's glob — rejected as dishonest.
- **Reasoning:** the work is genuinely separate from the 3 active sibling-session plans; the gate explicitly endorses "open a new plan" for this case. Also aligns with CLAUDE.md ("the deliverable is the closed plan").
- **Surfaced to user:** yes — the scope-gate cross-session false-fire is flagged in the session summary as a friction item.

## Definition of Done
- [ ] Primitive built + self-test 9/9.
- [ ] Convention doc + architecture doc updated.
- [ ] Verification evidence committed.
- [ ] PR opened.
- [ ] Plan closed (Status: COMPLETED) after PR.

## Completion Report

All four tasks are complete; the work shipped in commits `67a2146` (script +
convention doc + architecture-doc row) and `b2e4eef` (this plan + verification
evidence), opened as **PR #11**
(https://github.com/Pocket-Technician/neural-lace/pull/11, base
`chore/adr-reconcile-5pattern`).

Task boxes are intentionally left unchecked: this is a **retroactive
bookkeeping plan** created solely to satisfy the scope-enforcement-gate's
"open a new plan" option for orphan harness-infrastructure work (the 3
sibling-session active plans did not claim these files — a documented
cross-session false-fire). The work was done *before* the plan existed, so
there are no per-task task-verifier evidence blocks; the acceptance artifact is
`adapters/claude-code/scripts/spawn-worktree-selftest-evidence.md` (self-test
9/9 + collision reproduction + 3 session-type decisions + apply/remove
round-trip + dogfood short-circuit) plus the PR.

**Backlog items absorbed:** none.

**Manual steps required:** after PR #2 (`chore/adr-reconcile-5pattern`) merges
to master, retarget/rebase PR #11 onto master. No migrations, env vars, or
infra changes.

**Known follow-ups (surfaced, not built):** (1) a SessionStart "working-tree
occupancy" heuristic that nudges a session to `spawn-worktree.sh` when the main
checkout is dirty/on a non-default branch with a recent sibling commit; (2) an
ADR-number/plan-slug allocation primitive (worktree isolation does NOT fix
number collisions); (3) the scope-enforcement-gate cross-session false-fire on
orphan harness commits when sibling plans are active (this session hit it; a
friction item for Misha).
