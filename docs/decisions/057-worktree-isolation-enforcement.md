# 057 — Worktree-Isolation Enforcement (SessionStart advisor + Stop teardown gate)

**Date:** 2026-06-23
**Status:** Active
**Stakeholders:** Misha (operator), AI orchestrator
**Plan:** `docs/plans/worktree-isolation-enforcement-2026-06-23.md`
**Rule:** `adapters/claude-code/rules/worktree-isolation.md`
**Exemption analysis:** the full A1–A7 / B1–B10 exemption + edge-case set (the operator asked to see every non-wanted case before the build) is recorded in this ADR's Decision/Alternatives and in `rules/worktree-isolation.md`.
**Supersedes:** the Pattern-only worktree-teardown enforcement spec (2026-06-22, drafted in the operator's downstream working repo during the design conversation); this ADR builds the Mechanism.

## Context

A single shared main checkout was being used concurrently by ~18 sessions, producing the
collisions the harness's parallelism otherwise creates value to avoid: a stale dirty tree,
a blocked branch-switch, and a sibling session's `git stash`/`git clean` wiping another
session's uncommitted work. The operator asked: "going forward, every session in its own
worktree — how is that enforced?" The honest answer was that it was NOT enforced; only
`teammate-spawn-validator.sh` gated worktree isolation, and only for write-capable *sub-agent*
spawns — nothing governed top-level sessions.

Two facts shaped the design (both verified, not assumed):

1. **The START side cannot be hook-forced.** `SessionStart` fires after the session's cwd is
   already chosen; a hook is a child subprocess and cannot relocate its parent into a worktree.
   So the start side can only be *informed*, not forced — which is still valuable ("we can auto
   inject a prompt to tell every session the correct behavior" — operator).
2. **There is no hook-readable live-session count.** `.git/worktrees/` lists worktrees, not the
   processes attached to them; transcript files are cumulative history. So "is a peer session
   live in that worktree?" is unanswerable mechanically.

The operator's binding constraint: identify every case where the behavior is NOT wanted before
building, because a gate with a bad exemption set false-fires and trains everyone to ignore it.

## Decision

Ship two mechanisms (Hybrid rule + two hooks), with the exemption set baked in:

- **`session-start-worktree-advisor.sh` (SessionStart):** auto-injects tailored guidance.
  Silent when already in a linked worktree (`git-dir` != `git-common-dir`) or non-git; LOUD on
  the main checkout of a repo that HAS linked worktrees (the readable proxy for "multi-session
  repo"); GENTLE otherwise. Names the create command, the setup cost, and the exemption set so a
  session for which a worktree is the wrong tool self-dismisses. Never blocks.
- **`worktree-teardown-gate.sh` (Stop, after `product-acceptance-gate.sh`):** blocks a session
  from ending inside a linked worktree with UNCOMMITTED work, steering toward preserve-first
  (commit/stash/push) and **never** toward `--force` deletion. Clean-but-unpushed → non-blocking
  advise. Cwd-scoped: considers ONLY the session's own worktree, so it structurally cannot
  disturb a peer's (no liveness signal needed). Main checkout, non-git, and `git worktree
  lock`-ed worktrees are exempt. Fresh-waiver escape hatch + `lib/stop-hook-retry-guard.sh`,
  mirroring `bug-persistence-gate.sh`.

The load-bearing design choice (DEC-B1): the teardown gate honors "incomplete ≠ abandoned" —
it preserves work, it never pressures deletion of unmerged work.

## Alternatives Considered

- **Force start-in-worktree via a hook** — rejected: structurally impossible (SessionStart fires
  post-cwd; a subprocess can't relocate its parent). Naming this honestly rather than papering
  over it (Rule 7).
- **Marker-based teardown gate** (a PreToolUse `git worktree add` writer tracking every worktree
  the session created, so failure-mode-2 — created-then-cd-away orphan — is caught) — deferred:
  adds a third hook + a stale-marker false-positive surface. v1 is cwd-scoped (high-precision,
  zero peer-touch risk); failure-mode-2 is a NAMED v1 limitation, not a hidden gap.
- **Block on unpushed commits too** — rejected (DEC-D2): committed work survives `git worktree
  remove` (dies only on `git branch -D`, which branch-hygiene governs), so blocking normal
  mid-work unpushed state would be high-false-positive and erode the gate's trust. Unpushed →
  advise, not block.
- **Leave it Pattern-only** (the 2026-06-22 teardown spec) — rejected: the operator explicitly
  asked to build it; Pattern-only is what let the 18-on-one-folder mess accumulate.

## Consequences

- Every session is *told* the right worktree behavior at start; no session can end having
  stranded uncommitted work in its own worktree — without ever being pressured to delete
  unmerged work.
- Accepted ceilings (named, not hidden): start-in-worktree is not forced; cloud/remote sessions
  don't load `~/.claude/` hooks; failure-mode-2 (created-then-cd-away orphan) is uncaught in v1.
- Refutation criterion: if the advisor's LOUD message fires on sessions that are legitimately
  main-checkout-by-necessity often enough that the operator starts ignoring it, the exemption
  set / tailoring is wrong and must be narrowed. The message's self-dismiss exemption list is
  the mitigation; chronic noise would refute the tailoring.
- Self-tests are the acceptance artifact (build-harness-infrastructure work-shape): advisor 4/4,
  teardown gate 8/8.
