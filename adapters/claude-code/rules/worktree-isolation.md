# Worktree Isolation — Inform Every Session at Start; Preserve Work Before Ending in a Worktree

**Classification:** Hybrid. The discipline (when to use a per-session worktree, and the exemption set for when NOT to) is a Pattern the operator and every session self-apply. Two Mechanisms back it: `session-start-worktree-advisor.sh` (SessionStart) auto-injects tailored guidance — the START side, which a hook **cannot force** (the cwd is chosen before SessionStart fires; a subprocess cannot relocate its parent) and therefore only informs; and `worktree-teardown-gate.sh` (Stop) blocks a session from ending inside a linked worktree with **uncommitted** work, steering toward preserve-first and **never** toward `--force` deletion. Both hooks exist, pass their self-tests, and are wired in the canonical `settings.json.template` — but live wiring is pending Wave B.6 install (the template has not yet been synced to the user's live `~/.claude/settings.json`).

**Ships with:** ADR 057 (`docs/decisions/057-worktree-isolation-enforcement.md`), which records the full A1–A7 / B1–B10 exemption + edge-case analysis (the operator asked to see every non-wanted case before the build).

## The behavior in one line

> A session that will make commits in a repo other live sessions also touch should work in its own git worktree, not the shared main checkout — so concurrent sessions don't collide on the working tree, the index, or `git stash`/`git clean`.

What forced this: a single main checkout shared by ~18 sessions, with collisions (stale dirty tree, blocked branch-switch, a sibling's `git clean` wiping another session's uncommitted plan files). The mess comes from many-sessions-on-one-folder, not from worktrees.

## Hard constraint — "incomplete ≠ abandoned"

The teardown gate must **never** pressure deleting a worktree that holds unmerged work. A worktree with uncommitted changes or unpushed commits holds WANTED work. The lazy resolution of a naive "you can't be complete while a worktree exists" gate is `git worktree remove --force` — which **destroys** that work. So the gate steers toward PRESERVE (commit / stash / push), never toward removal, and its block message explicitly says do NOT reach for `--force`.

## When we do NOT want worktree isolation (the exemption set)

- **A1 — Read-only sessions.** Diagnosis, Q&A, exploration, review; read-only sub-agents. No writes ⇒ no collision; a worktree is pure ceremony. (`teammate-spawn-validator.sh` already requires worktree isolation only for *write-capable* sub-agent spawns.)
- **A2 — On-main-checkout-by-necessity.** Post-merge sync (git-discipline Rule 2), `git worktree remove/prune`, branch deletion, local-master reconcile, plan-closure commits. You cannot remove a worktree from inside it.
- **A3 — Already isolated.** Already in a linked worktree, or a cloud/remote session (isolated VM; also doesn't load `~/.claude/` hooks).
- **A4 — Not a git repo.** No-op.
- **A5 — Intentionally-persistent worktrees.** Another **live** session's worktree (never disturb a peer's), `git worktree lock`-ed worktrees, a hand-off-and-resume worktree.
- **A6 — Tiny ancillary edits, pre-customer.** A one-line docs/SCRATCHPAD fix — worktree ceremony > the edit. Soft (advise OK, never block).
- **A7 — Emergency hotfix.** Worktree setup latency is real when prod is down. Operator judgment.

## Edge cases the mechanisms handle

- **B1 (load-bearing):** the teardown gate classifies work — clean+preserved → pass; **uncommitted → BLOCK toward preserve-first**; clean-but-unpushed → **ADVISE, non-blocking** (committed work survives `git worktree remove`; it dies only on `git branch -D`, which `branch-hygiene.md` governs). Never toward delete.
- **B2:** no reliable cross-session liveness signal exists, so the gate is **cwd-scoped** — it considers ONLY the worktree the current session is in, and structurally cannot touch a peer's worktree (satisfies A5). **Named v1 limitation:** a session that creates a worktree then cd's back to the main checkout before ending ("failure mode 2") is NOT caught; closing it would need a `git worktree add` marker-writer (deliberately out of v1 scope).
- **B3:** SessionStart can't know whether a session will write, so the advisor is informational, never a block.
- **B4:** the advisor is tailored to avoid alert fatigue — silent when already in a worktree; loud on the main checkout of a repo that has worktrees; gentle otherwise.
- **B5:** no hook-readable live-session count; the advisor keys on "main checkout of a repo that has linked worktrees" as the proxy for "multi-session repo."
- **B6:** the main checkout always carries bookkeeping churn ⇒ it is never gated by the teardown gate.
- **B8:** a fresh worktree needs gitignored env (`.env.local`) + an install (`npm install`) where applicable; the advisor names that cost so a session taking the advice doesn't get stuck (and it's *why* A1/A6 are real exemptions, not nags).
- **CRLF caveat:** on a repo without `.gitattributes` and with `core.autocrlf=true`, a freshly checked-out file can appear phantom-dirty; if that ever false-fires the gate, the fresh-waiver escape hatch covers it.

## The two mechanisms

### `session-start-worktree-advisor.sh` (SessionStart)
Auto-injects guidance into every session's context. Silent when already in a worktree (A3) or not a git repo (A4). Loud on the main checkout when linked worktrees exist (the multi-session proxy); gentle otherwise. Every message names the create command (with the right base + setup cost) and the exemption set so a session for which a worktree is the wrong tool self-dismisses. Always exits 0.

### `worktree-teardown-gate.sh` (Stop)
No-op unless cwd is a linked, non-locked worktree (B6/A4/A5). Then: clean+preserved → allow; clean-but-unpushed → advise (non-blocking); **uncommitted → block toward preserve-first** via the retry-guard (3-retry downgrade) with a fresh-waiver escape hatch: `.claude/state/worktree-teardown-waiver-*.txt` (≥1 substantive line, <1h).

## The honest ceiling

Neither mechanism *forces* a session to start in a worktree (that's UI/operator behavior; the advisor only informs), and neither sees cloud/remote sessions. What they buy: every session is *told* the right behavior at start, and no session can end having stranded uncommitted work in its own worktree — without ever pressuring deletion of unmerged work.

## Cross-references

- `~/.claude/rules/branch-hygiene.md` — WIP-branch naming + the stale-branch decision tree (the teardown gate's "push to preserve" lands on a branch this governs).
- `~/.claude/rules/git-discipline.md` — Rule 2 (post-merge main-checkout sync, an A2 case) + the never-force-push prohibition the gate's preserve-first message echoes.
- `~/.claude/rules/orchestrator-pattern.md` — `isolation: "worktree"` for parallel builders + the cherry-pick-then-teardown flow (sub-agent worktrees, governed by `teammate-spawn-validator.sh`, not this gate — B9).
- `~/.claude/rules/automation-modes.md` — Mode 2 (parallel local worktrees) vs the shared-checkout collision failure mode.
- `~/.claude/hooks/lib/stop-hook-retry-guard.sh` — the loop-break the teardown gate sources.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | When to use a worktree; the A1–A7 exemption set; the B1 preserve-first / B2 cwd-scope discipline | `adapters/claude-code/rules/worktree-isolation.md` |
| Advisor (SessionStart, Mechanism, wired in template; live wiring pending Wave B.6 install) | Auto-injects tailored worktree guidance at every session start (informational; never blocks) | `adapters/claude-code/hooks/session-start-worktree-advisor.sh` |
| Teardown gate (Stop, Mechanism, wired in template; live wiring pending Wave B.6 install) | Blocks ending in a worktree with uncommitted work; steers preserve-first, never `--force` | `adapters/claude-code/hooks/worktree-teardown-gate.sh` |
| User authority | The backstop for the start side (which no hook can force) and the named failure-mode-2 limitation | (Pattern) |

## Scope

Applies in any project whose Claude Code installation has the two hooks wired in `settings.json`. Both are wired in the canonical `settings.json.template`; live wiring pending Wave B.6 install (the sync from template to the user's `~/.claude/settings.json` has not yet run). Both degrade to no-ops where they can't apply (non-git, no transcript, main checkout, already isolated), so they are safe in every session mode. The advisor fires on every SessionStart; the teardown gate fires on every Stop but no-ops unless the session is ending inside a linked worktree.
