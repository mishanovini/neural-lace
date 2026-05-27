# Convention: One Worktree Per Parallel Session

**Status:** Active convention (2026-05-25)
**Owner:** Misha
**Applies to:** any time two or more Claude Code sessions work on the same repo concurrently — especially the implementation sessions for the 5-pattern redesign arc.

## The problem this prevents

On 2026-05-25 four design sessions (Patterns 1/3/4/5 of the plan-lifecycle
redesign arc) ran **in parallel in the single main checkout**
(`C:/Users/misha/dev/Pocket Technician/neural-lace`). Because they shared one
working tree they collided on two shared resources:

1. **`SCRATCHPAD.md` write race** — each session rewrote the shared SCRATCHPAD, clobbering the others' state.
2. **ADR-number collision** — each session independently picked "the next ADR number." Patterns 1/3 took 036/037/038, Pattern 4 took 040, and Pattern 5 had to manually renumber its own 037/038 → 041/042 after observing the others' files. The collision was avoided only because the last-writing session *noticed* and renumbered by hand (see `docs/reviews/2026-05-25-adr-renumber-reconciliation.md`). Nothing structural prevented it.

The implementation sessions ahead (R1→R7 across the four redesign plans) must not
repeat this. **Each parallel session works in its own git worktree.**

## How worktrees are created today (verified state)

Three paths, all producing an isolated working tree backed by the same `.git`:

1. **Dispatch / Cowork `start_code_task` / Desktop "+ New session" (auto).**
   The Claude Code desktop app creates a sibling worktree **per code task**,
   automatically, at `.claude/worktrees/<adjective-surname-hash>` on branch
   `claude/<same-name>`. Verified on this machine: `git worktree list` shows
   five such worktrees (`bold-albattani-0939ef`, `busy-elgamal-ce5389`,
   `nervous-lehmann-35212e`, `quizzical-almeida-cff6d1`, `xenodochial-clarke-71d1fe`),
   each mirrored by a session-history dir under
   `~/.claude/projects/…--claude-worktrees-<name>`. These are **auto-created per
   session, not explicitly requested.** This is the preferred path for
   implementation sessions: dispatch each R-session as its own code task and it
   lands in its own worktree with zero shared-tree contention.

2. **Orchestrator dispatching sub-agent builders (`isolation: "worktree"`).**
   When one session fans out parallel builders via the `Agent` tool, set
   `isolation: "worktree"` on each dispatch. Claude Code creates an isolated
   (locked) worktree per builder; the orchestrator cherry-picks results back
   per the build-in-parallel/verify-sequentially protocol. See
   `~/.claude/rules/orchestrator-pattern.md`.

3. **Manual (`git worktree add`).** For explicit control:
   `git worktree add .claude/worktrees/<name> -b <branch>` then `cd` in and
   launch. Use when you want a specific branch name (e.g. `feat/r1-owner-fields`).

## The rule for the implementation phase

- **One session → one worktree.** Never run more than one session against the **main checkout** simultaneously. The main checkout is for the orchestrator/interactive driver only; concurrent build work happens in worktrees.
- **Prefer the dispatch/auto path (#1)** for the redesign R-sessions — it isolates SCRATCHPAD, plan-file edits, and ADR-number selection automatically.
- **Pre-commit the shared inputs.** Before dispatching parallel sessions, commit anything they'll read (plan files, the current ADR index) so each worktree — rooted at master HEAD — sees a consistent base. (Agent `isolation:"worktree"` roots at master HEAD, not the feature branch; see the orchestrator-pattern's "worktree base is master HEAD" note.)
- **One owner per resource.** Two sessions must not both edit `SCRATCHPAD.md`, the same plan file, or claim the same next-ADR-number. Worktree isolation handles the file-level race; ADR-number selection is still a manual hazard (see Gaps below).

## How doc-writes propagate back to the main checkout

Pick by phase:

- **Implementation sessions → PR-based merge (the built, standard path).**
  Each session commits in its worktree, pushes its branch, opens a PR, and the
  work reaches master via squash/`--no-ff` merge. After merge, **sync the main
  checkout**: `git fetch origin && git pull --ff-only origin master` (stash any
  uncommitted main-checkout work first). This is `~/.claude/rules/git-discipline.md`
  Rule 2 — the authoritative, already-working mechanism. Code changes need review
  anyway, so PR-merge is the right propagation channel for implementation work.

- **Design-time pure-docs → also PR-based merge today.** The lighter
  "copy-if-absent on stop" propagation (`docs-publish-on-stop.sh`, ADR 037 D3)
  that would auto-publish worktree-written durable docs into the main checkout
  **is design-only and NOT BUILT.** Until the file-lifecycle redesign ships it,
  design docs propagate the same way as code: commit in the worktree, push, PR.
  Do not rely on publish-on-stop — it does not exist yet.

## Cleanup

Worktrees are **not** auto-removed at session end and accumulate without bound
(one machine reached ~50 in a single repo). Run the existing pruner periodically:
`~/.claude/scripts/worktree-prune.sh` — it conservatively removes only worktrees
whose branch tip is already an ancestor of master, that are unlocked, and that
have no real uncommitted changes. Locked orchestrator-isolation worktrees are
left for the cherry-pick protocol.

## Harness gaps surfaced (not fixed here)

These are recommendations, surfaced per the diagnosis rule's "encode the fix"
discipline — **not built in this doc**:

1. **No worktree-spawn primitive / no isolation enforcement for interactive sessions.** The platform auto-isolates *dispatched* code tasks, but nothing stops two *interactive* sessions from sharing the main checkout (exactly what happened on 2026-05-25). There is no harness script that spawns a worktree, and no gate that warns when a second session targets an already-occupied working tree. A cross-session "working-tree occupancy" warning is hard to implement reliably (sessions don't see each other), but a documented launch discipline (this doc) plus a possible SessionStart heuristic is the lightweight mitigation. **Recommendation: keep this as a convention for now; revisit a mechanical guard if collisions recur.**

2. **No ADR-number (or plan-slug) allocation primitive.** Parallel sessions each pick "the next ADR number" independently → collision risk. Today the only safeguard is a session manually checking `ls docs/decisions/` before writing. **Recommendation: a small allocation gate (e.g., a `reserve-adr-number.sh` that atomically claims the next free number, or a SessionStart reminder to check the index) would remove the manual hazard.** Surfaced for the maintainer to decide; not built.

3. **`docs-publish-on-stop.sh` (ADR 037 D3) not built.** Design-time doc propagation from a worktree still requires a manual commit/PR. Tracked by the file-lifecycle redesign plan.

## Cross-references

- `~/.claude/rules/automation-modes.md` — Mode 2 (Parallel local worktrees) and its tradeoffs; the five-mode decision tree.
- `~/.claude/rules/orchestrator-pattern.md` — `isolation: "worktree"` sub-agent dispatch + the "worktree base is master HEAD" gotcha + cherry-pick protocol.
- `~/.claude/rules/git-discipline.md` — Rule 2 (post-merge sync of the main checkout) = the propagation mechanism above.
- `~/.claude/rules/agent-teams.md` — `worktree_mandatory_for_write` for write-capable teammates.
- `~/.claude/scripts/worktree-prune.sh` — the cleanup half.
- `docs/decisions/037-file-lifecycle-session-artifacts.md` — the design-only publish-on-stop mechanism (D3) and SCRATCHPAD create-on-missing fix (D2).
- `docs/reviews/2026-05-25-adr-renumber-reconciliation.md` — the collision this convention prevents.
