# Convention: One Worktree Per Parallel Session

**Status:** Active convention (2026-05-25; verified rules + decision matrix + spawn primitive added 2026-05-26)
**Owner:** Misha
**Applies to:** any time two or more Claude Code sessions work on the same repo concurrently — especially the implementation sessions for the 5-pattern redesign arc.

> **2026-05-26 update.** The collision root cause is now PROVEN (reflog evidence
> + a deterministic reproduction), the needs-isolation line is captured in a
> **decision matrix**, and the gap this doc named ("no worktree-spawn
> primitive") is **closed** — see `adapters/claude-code/scripts/spawn-worktree.sh`.
> Sections below were reconciled against the official Claude Code worktree docs
> + verified filesystem state; corrections carry **[corrected 2026-05-26]**.

## The problem this prevents

On 2026-05-25 four design sessions (Patterns 1/3/4/5 of the plan-lifecycle
redesign arc) ran **in parallel in the single main checkout**
(`C:/Users/misha/dev/Pocket Technician/neural-lace`). Because they shared one
working tree they collided on two shared resources:

1. **`SCRATCHPAD.md` write race** — each session rewrote the shared SCRATCHPAD, clobbering the others' state.
2. **ADR-number collision** — each session independently picked "the next ADR number." Patterns 1/3 took 036/037/038, Pattern 4 took 040, and Pattern 5 had to manually renumber its own 037/038 → 041/042 after observing the others' files. The collision was avoided only because the last-writing session *noticed* and renumbered by hand (see `docs/reviews/2026-05-25-adr-renumber-reconciliation.md`). Nothing structural prevented it.

The implementation sessions ahead (R1→R7 across the four redesign plans) must not
repeat this. **Each parallel session works in its own git worktree.**

## Why isolation is needed (PROVEN root cause)

A git working tree — including the main checkout — has **exactly one `HEAD`**.
`git checkout` and `git commit` both mutate that single shared `HEAD`. When two
or more sessions share one working tree, they race on it:

> Session A runs `git checkout branch-A`, flipping the shared `HEAD`. Session B,
> which earlier checked out `branch-B` and *believes* it is still there, then
> runs `git commit` — and the commit lands on **branch-A**, not branch-B.

This is a textbook time-of-check/time-of-use race on a resource the sessions
cannot see each other touching.

**PROVEN, two ways:**

1. **Reflog evidence (the real incident).** The main-checkout `HEAD` reflog for
   2026-05-26 shows `HEAD` ping-ponging across five branches in a ~19-minute
   window, with this pair four seconds apart:
   ```
   17:02:45  checkout: moving from chore/adr-reconcile-5pattern to pattern-3-file-lifecycle-plan
   17:02:49  commit:   fix(session-wrap): create SCRATCHPAD on missing …   ← landed on pattern-3-file-lifecycle-plan
   ```
   The session-wrap-fix session's commit landed on a **sibling session's**
   branch because a sibling had flipped the shared `HEAD` 4s earlier. (The
   "commit-3-plans session reported the branch flipping under it" report is the
   same race observed from the other side.)
2. **Deterministic reproduction** (in `spawn-worktree.sh --self-test` and the
   research notes): a synthetic two-session repo reproduces B's commit landing
   on A's branch in the shared checkout, and shows it **cannot** happen when each
   session has its own worktree (each worktree has its own `HEAD` under
   `.git/worktrees/<name>/HEAD`).

The SCRATCHPAD write-race and ADR-number collision above are the *file-level*
symptoms; the shared-`HEAD` wrong-branch commit is the *git-level* one. Worktree
isolation fixes all three because each worktree has its own `HEAD`, its own
index, and its own working files.

## How worktrees are created today (verified state)

Verified against the official docs (`code.claude.com/docs/en/worktrees`) **and**
this machine's filesystem. Four paths, all producing an isolated working tree
backed by the same `.git`:

1. **Desktop "+ New session" / Dispatch `start_code_task` (auto, per task).**
   The desktop app creates a sibling worktree **per code task**, automatically,
   at `.claude/worktrees/<adjective-surname-hash>` on branch
   `claude/<same-name>`. **[corrected 2026-05-26]** Verified isolation is
   **per code task = per session, 1:1**: each `~/.claude/projects/…--claude-worktrees-<name>`
   session-history dir on this machine holds **exactly one** session file, while
   the **main-checkout** project dir holds **15** session files — i.e. 15
   sessions shared the one main working tree over time, and that is the substrate
   the collision above happened on. The five auto-worktrees observed:
   `bold-albattani-0939ef`, `busy-elgamal-ce5389`, `nervous-lehmann-35212e`,
   `quizzical-almeida-cff6d1`, `xenodochial-clarke-71d1fe` (one of which,
   `busy-elgamal`, was later `git switch`-ed by its session onto a named branch
   `conv-tree-bootstrap-mechanism` — the worktree dir name and its branch need
   not match). Whether a Dispatch task auto-isolates is governed by its working
   directory / the desktop isolation setting: tasks that target the main
   checkout's cwd (or run isolation-disabled) do **not** get a fresh worktree —
   that is how 15 sessions accumulated in the one checkout.

2. **CLI `claude --worktree <name>` (`-w`).** Creates `.claude/worktrees/<name>/`
   on a new branch **`worktree-<name>`** (note: different prefix from the desktop
   `claude/<name>` path) and starts Claude in it. Omit the name for a generated
   one (e.g. `bright-running-fox`). `claude --worktree "#1234"` bases off a PR.

3. **Mid-session: the `EnterWorktree` tool** (ask Claude to "work in a
   worktree"), or **`spawn-worktree.sh --apply`** (this harness's decision-aware
   primitive — see "The spawn-worktree.sh primitive" below). Both let an
   already-running session move into a fresh worktree without relaunching.

4. **Orchestrator sub-agent builders (`isolation: "worktree"`).** When one
   session fans out parallel builders via the `Agent` tool, set
   `isolation: "worktree"` on each dispatch. Claude Code creates an isolated
   (locked) worktree per builder; the orchestrator cherry-picks results back per
   the build-in-parallel/verify-sequentially protocol. See
   `~/.claude/rules/orchestrator-pattern.md`. Subagent worktrees are removed
   automatically when the subagent finishes **with no changes**.

5. **Manual `git worktree add`.** For full control:
   `git worktree add .claude/worktrees/<name> -b <branch> <base>` then `cd` in.

**Base branch [corrected 2026-05-26].** Native worktrees branch from
`origin/HEAD` (the remote default branch — "a clean tree matching the remote"),
**not** "master HEAD" / the current feature branch. Settable to local `HEAD` via
`worktree.baseRef: "head"` in settings (e.g. when a subagent must build on
unpushed feature-branch state). `spawn-worktree.sh` follows the same default
(`--base origin/HEAD`, fallback local HEAD), overridable with `--base`.

**Gitignored files [new 2026-05-26].** A worktree is a fresh checkout, so
gitignored files (`.env`, `.env.local`, **and `SCRATCHPAD.md`**) are **absent**
unless listed in a `.worktreeinclude` file at the repo root (`.gitignore`
syntax). This is why a worktree session can see "no SCRATCHPAD" — list it in
`.worktreeinclude` if a fresh worktree should inherit the main checkout's
SCRATCHPAD, or treat the main checkout as the canonical SCRATCHPAD home (this
repo's convention: one SCRATCHPAD per repo, in the parent).

## The rule for the implementation phase

- **One session → one worktree.** Never run more than one session against the **main checkout** simultaneously. The main checkout is for the orchestrator/interactive driver only; concurrent build work happens in worktrees.
- **Prefer the dispatch/auto path (#1)** for the redesign R-sessions — it isolates SCRATCHPAD, plan-file edits, and ADR-number selection automatically.
- **Pre-commit the shared inputs.** Before dispatching parallel sessions, commit anything they'll read (plan files, the current ADR index) so each worktree — rooted at `origin/HEAD` **[corrected 2026-05-26: `origin/HEAD`, not "master HEAD" / the feature branch]** — sees a consistent base. A worktree based on `origin/HEAD` does **not** carry the dispatching session's unpushed feature-branch commits unless `worktree.baseRef: "head"` is set (or you pass `--base <ref>` to `spawn-worktree.sh`).
- **One owner per resource.** Two sessions must not both edit `SCRATCHPAD.md`, the same plan file, or claim the same next-ADR-number. Worktree isolation handles the file-level race; ADR-number selection is still a manual hazard (see Gaps below).

## Decision matrix — when isolation is actually needed

Not every session needs a worktree. The shared resource that collides is the
single `HEAD` + index per working tree (see "Why isolation is needed" above), so
the need is a function of **what the session does to git state** × **whether
another session might share the repo**. Isolation cost is low but non-zero (a
worktree is a full checkout — seconds to create, must be cleaned up, and starts
without gitignored files like `SCRATCHPAD.md`/`.env`), so read-only work should
skip it.

| Session type | Alone on repo | Concurrent (or unknown) |
|---|---|---|
| **read-only** (search / read / investigate; no Edit/Write/commit) | no isolation | **no isolation** — reads never touch `HEAD`/index; worst case is a stale read (re-read after a known sibling write) |
| **writes-files-only** (edits files; no commit, no branch-switch) | optional | **isolate** — a sibling checkout swaps files under your uncommitted edits (silent corruption) |
| **commits** (commits on the current branch; no branch-switch) | safe\* | **isolate** — proven: a sibling checkout flips the shared `HEAD` → your commit lands on the wrong branch |
| **branch-switching** (the feature-branch + PR session) | safe\* | **required** — the exact proven 2026-05-26 failure |
| **destructive** (`reset --hard` / `rebase` / `clean` / branch deletes) | **isolate** | **required** — destructive ops on a shared tree can wipe a sibling's uncommitted work |

\* "Alone on the repo" is genuinely safe — but it is **unprovable** at runtime
(sessions cannot see each other), and the cost of a wrong "I'm alone" assumption
is the proven wrong-branch commit. So the operational rule collapses to:

> **Isolate iff the session will mutate git state (commit / branch-switch /
> destructive), OR write files when concurrency is possible. Pure read-only
> sessions never isolate.**

`spawn-worktree.sh` encodes exactly this matrix; its default `--type` is
`commits` and default `--concurrent` is `unknown` (both conservative), so a
caller who says nothing gets isolation.

## The spawn-worktree.sh primitive

`adapters/claude-code/scripts/spawn-worktree.sh` (live mirror
`~/.claude/scripts/spawn-worktree.sh`) is the **in-our-control spawn half** (the
cleanup half is `worktree-prune.sh`). It (1) **decides** whether a session needs
isolation from the matrix above and (2) if so, **creates** a predictably-named
worktree on a clean base and prints the cwd to `cd` into. It complements — does
not replace — the native paths (`claude --worktree`, `EnterWorktree`, desktop
auto-isolation): its added value is the decision layer, an explicit
slug-aligned branch name, an explicit base ref, idempotent re-runs, and an
"already-isolated" short-circuit so a session already in a worktree is never
re-nested.

**Decide-only (default is dry-run — creates nothing):**
```bash
spawn-worktree.sh <slug> --type read-only        # → "no-isolation", prints main checkout
spawn-worktree.sh <slug> --type commits          # → "isolate", prints the WOULD-CREATE command
spawn-worktree.sh <slug> --type branch-switch    # → "isolate"
```

**Create + cd into it (the canonical commit-producing-session opener):**
```bash
cd "$(spawn-worktree.sh fix-webhook --type commits --apply --print-cd --quiet)"
# now on branch session/fix-webhook, in .claude/worktrees/fix-webhook, based on origin/HEAD
```

Within a single Claude Code session the Bash tool's cwd persists across calls,
so a `cd` into the printed path makes subsequent `git`/Bash commands run in the
isolated worktree. (Read/Write/Edit use absolute paths and are unaffected.)

Key flags: `--type` (read-only|writes|commits|branch-switch|destructive,
default `commits`), `--concurrent` (yes|no|unknown, default `unknown`), `--base`
(default `origin/HEAD`), `--branch` (default `<slug>` if it contains `/`, else
`session/<slug>`), `--apply`, `--print-cd`, `--remove <slug>` (clean-only unless
`--force`; safe-deletes the branch with `git branch -d`), `--self-test`. See the
script header for the full contract.

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

**[corrected 2026-05-26 — the native cleanup is more nuanced than "never
auto-removed".]** Per the official docs, on session exit Claude Code's behavior
depends on worktree state:

- **Clean** (no uncommitted changes, no untracked files, no new commits): the
  worktree **and its branch are removed automatically** (a *named* session
  prompts instead, so you can keep it).
- **Dirty / has commits**: you are **prompted** to keep or remove.
- **Non-interactive `-p` runs**: **never** auto-cleaned (no exit prompt) — remove
  with `git worktree remove`.
- **Subagent worktrees** orphaned by a crash are swept at startup once older than
  `cleanupPeriodDays`, **only if clean**. `--worktree`-created worktrees are
  never touched by that sweep.

So the accumulation this repo saw (~50 in one repo) comes from the worktrees that
**made commits** (the common case for a real task) plus non-interactive runs —
exactly the ones the native cleanup leaves behind. Two complementary cleanup
paths in this harness:

- **Per-session, explicit:** `spawn-worktree.sh --remove <slug>` tears down one
  worktree (clean-only unless `--force`) and safe-deletes its branch
  (`git branch -d` — merged-only, never loses work). Run it at session end.
- **Periodic, repo-wide:** `~/.claude/scripts/worktree-prune.sh` conservatively
  removes only worktrees whose branch tip is already an ancestor of master (or
  introduces no net diff vs its fork point — covers squash merges), that are
  unlocked, and that have no real uncommitted changes, and whose last commit is
  at least `--age-days` (default 3) old. Locked orchestrator-isolation worktrees
  are left for the cherry-pick protocol.

## Harness gaps — status

1. **Worktree-spawn primitive — CLOSED (2026-05-26).** `spawn-worktree.sh` is
   the spawn half (decision matrix + create + cd), paired with
   `worktree-prune.sh` (cleanup half). **Still open within this gap:** there is
   no *mechanical gate* that warns when a second session targets an
   already-occupied main checkout — sessions genuinely cannot see each other, so
   a reliable cross-session "occupancy" warning remains hard. The mitigation
   stays the documented discipline (this doc) + the primitive a session runs at
   its own start. **Recommendation: a SessionStart heuristic that detects "main
   checkout is dirty / on a non-default branch with a recent sibling commit" and
   nudges the session to `spawn-worktree.sh` is the next lightweight step if
   collisions keep recurring; not built.** A hard occupancy lock is out of scope
   (it would require an inter-session coordination channel the runtime does not
   expose).

2. **No ADR-number (or plan-slug) allocation primitive.** Parallel sessions each pick "the next ADR number" independently → collision risk. Today the only safeguard is a session manually checking `ls docs/decisions/` before writing. **Recommendation: a small allocation gate (e.g., a `reserve-adr-number.sh` that atomically claims the next free number, or a SessionStart reminder to check the index) would remove the manual hazard.** Surfaced for the maintainer to decide; not built. (Note: worktree isolation does NOT fix this — each worktree picks the next number against the same `origin/HEAD` base, so two isolated sessions still collide. This needs an allocation primitive, not isolation.)

3. **`docs-publish-on-stop.sh` (ADR 037 D3) not built.** Design-time doc propagation from a worktree still requires a manual commit/PR. Tracked by the file-lifecycle redesign plan.

## Cross-references

- `code.claude.com/docs/en/worktrees` — the official Claude Code worktree reference (`--worktree` flag, `worktree.baseRef`, `.worktreeinclude`, subagent isolation, cleanup semantics) that the 2026-05-26 corrections were reconciled against.
- `adapters/claude-code/scripts/spawn-worktree.sh` — the spawn half: decision matrix + create + cd + `--remove` (this doc's primitive).
- `~/.claude/scripts/worktree-prune.sh` — the cleanup half (periodic, conservative).
- `~/.claude/rules/automation-modes.md` — Mode 2 (Parallel local worktrees) and its tradeoffs; the five-mode decision tree.
- `~/.claude/rules/orchestrator-pattern.md` — `isolation: "worktree"` sub-agent dispatch + cherry-pick protocol. **[corrected 2026-05-26: that rule's "worktree base is master HEAD" note should read `origin/HEAD` per the official docs; the practical effect is the same when `origin/master` == `origin/HEAD`.]**
- `~/.claude/rules/git-discipline.md` — Rule 2 (post-merge sync of the main checkout) = the propagation mechanism above.
- `~/.claude/rules/agent-teams.md` — `worktree_mandatory_for_write` for write-capable teammates.
- `docs/decisions/037-file-lifecycle-session-artifacts.md` — the design-only publish-on-stop mechanism (D3) and SCRATCHPAD create-on-missing fix (D2).
- `docs/reviews/2026-05-25-adr-renumber-reconciliation.md` — the collision this convention prevents.
