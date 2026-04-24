# Automation Modes — Choosing Where a Claude Code Session Runs

**Classification:** Pattern (self-applied decision discipline). The mode choice is the operator's judgment call; no hook blocks the "wrong" mode. But once a mode is chosen, its specific enforcement substrate is what it is — the Pattern here is picking the mode whose enforcement matches the task.

**Ships with:** Decision 011 (`docs/decisions/011-claude-remote-harness-approach.md`) — read it first. This rule operationalizes Decision 011 as a decision tree. Phase A research evidence (`docs/plans/archive/claude-remote-adoption-evidence.md`) is the factual substrate for every claim below.

---

## The four modes

A Claude Code session runs in exactly one of four modes. Each has a different enforcement substrate (which hooks/rules/agents actually fire), a different isolation story (what concurrent sessions can or cannot collide on), and a different best-fit task class.

| # | Mode | Isolation | Harness enforcement | Best for |
|---|---|---|---|---|
| 1 | **Interactive local** | Single session per working tree | **Full** (`~/.claude/` loaded) | Tight-loop work, UX decisions, live steering |
| 2 | **Parallel local (worktrees)** | Git worktrees isolate files; `~/.claude/` shared | **Full for rules/hooks/agents; shared state collision risk** | Short parallel builds on disjoint files |
| 3 | **Cloud remote (`claude --remote`)** | Fresh VM per session; nothing shared | **Project `.claude/` only** (per Decision 011 Approach A) | Multi-hour autonomous builds, tasks that don't need interactive steering |
| 4 | **Scheduled (Routines via `/schedule`)** | Same as mode 3 — fresh VM per trigger | **Project `.claude/` only** | Nightly / cron / event-triggered recurring work |

The table is the summary. The per-mode sections below give the concrete invocation, tradeoffs, enforcement surface, and failure modes.

---

## Mode 1 — Interactive local

### When to use

- Work where you want to watch each tool call and steer mid-course (UI design, copy choices, taste calls)
- Bug investigation where the failure isn't reproducible from a written spec alone
- Planning sessions (drafting a `docs/plans/*.md` with back-and-forth)
- First-time flows where you don't yet know what "done" looks like

### Invocation

Launch Claude Code in your IDE (VS Code extension, JetBrains plugin) or via `claude` in the project directory. This is the default mode — if no other mode is chosen explicitly, you are in Mode 1.

### Enforcement available

Full Neural Lace harness. The session loads:

- `~/.claude/settings.json` with all PreToolUse, PostToolUse, and Stop hooks (26 hooks in the Gen 4+ inventory per `docs/harness-architecture.md`)
- `~/.claude/rules/*.md` loaded contextually (17 rules)
- `~/.claude/agents/*.md` dispatchable via Task tool (16 agents including task-verifier, plan-evidence-reviewer, systems-designer, end-user-advocate)
- `~/.claude/skills/*.md` as slash commands (5 skills)
- `~/.claude/templates/*.md` for plan/decision/completion-report structure
- `~/.claude/CLAUDE.md` as global behavioral instructions
- `~/.claude/local/*.config.json` personal config (per-machine, never committed)

This is the only mode where every layer of the harness fires automatically.

### Concrete examples

- Drafting a new plan interactively, iterating with `systems-designer` review
- Hunting a UI contrast bug where the fix requires screenshot-checking each attempt
- A session where you plan to run `/find-my-bugs` mid-way and respond to its findings
- Pairing with `end-user-advocate` in plan-time mode to author acceptance scenarios

### Tradeoffs

- **Pro:** strongest enforcement; user is present to resolve ambiguities
- **Pro:** fastest feedback loop (no VM cold-start, no worktree setup)
- **Con:** ties up your local machine — the session monopolizes your terminal/IDE window
- **Con:** only one of these should run at a time against a given working tree (see Mode 2 for the parallel answer)

### Known failure mode

Running two interactive local sessions simultaneously in the same project working tree (without worktrees). The sessions share `~/.claude/`, the git working tree, and every `state/` file. Sibling sessions' `git stash` / `git clean` have wiped uncommitted plan files in practice (Neural Lace backlog documents at least two P1 incidents). If you need concurrency, use Mode 2 (worktrees) or Mode 3 (cloud).

---

## Mode 2 — Parallel local (git worktrees)

### When to use

- You need to run two or three concurrent builds on disjoint file sets (e.g., the orchestrator pattern dispatching two `plan-phase-builder` sub-agents with `isolation: "worktree"`)
- Each build is short enough (~minutes, not hours) that a cloud VM cold-start is proportionally expensive
- You want to observe progress in real time across both windows

### Invocation

Three paths, all equivalent:

1. **Desktop app "+ New session" button.** Creates a git worktree automatically at `<project-root>/.claude/worktrees/<branch-name>/` (configurable in Settings -> Claude Code -> "Worktree location"). Launches a fresh Claude Code session pointing at the worktree.
2. **Orchestrator pattern with `isolation: "worktree"`.** The main session dispatches via `Task tool` with `isolation: "worktree"` set, and Claude Code creates an isolated worktree for each dispatched builder (see `rules/orchestrator-pattern.md`).
3. **Manual `git worktree add`.** `git worktree add .claude/worktrees/my-branch -b my-branch` followed by `cd` into the worktree and launching `claude`.

### Enforcement available

- **Full `~/.claude/` harness** (same as Mode 1) because you're still on the same machine
- **Git-level isolation:** uncommitted file edits in one worktree are invisible to the other. No more cross-session `git stash` / `git clean` wipes on shared working trees.
- **BUT `~/.claude/` ITSELF IS SHARED:** all parallel local sessions read the same `settings.json`, the same `state/` files (tool-call budget counters, audit-ack files), the same `local/` config, the same memory files. This is a genuine risk — it's called out explicitly in Phase A research (evidence file section A.2) and in Decision 011.

### Concrete examples

- Orchestrator dispatching three parallel builders, each building a different file in a sweep task ("refactor 13 dashboard pages — dispatch 5 at a time, each on its own page")
- A long-running build in one worktree while you triage an urgent bug fix in another
- Running `/harness-review` in one worktree while a test builder runs in another

### Tradeoffs

- **Pro:** full harness enforcement (rules, hooks, agents) — you don't lose anything the local `~/.claude/` provides
- **Pro:** git-tree isolation solves the plan-file-wipe failure mode
- **Con:** shared `~/.claude/state/` can race. Two concurrent `task-verifier` invocations can both try to flip plan checkboxes in the same file. Mitigation: the orchestrator pattern's "build in parallel, verify sequentially" discipline, plus `plan-edit-validator.sh`'s 120s freshness window.
- **Con:** doesn't solve shared memory/preferences drift (if session A prompts a memory update, session B sees it mid-run)
- **Con:** still caps at the machine's CPU/RAM budget; practical ceiling is ~5 parallel builders per `rules/orchestrator-pattern.md`

### Known failure mode

Dispatching more than 5 parallel builders causes disk-I/O contention (concurrent `npm test` runs), race conditions on shared state files, and an orchestrator that drowns in return summaries. The orchestrator-pattern rule's parallelism ceiling (~5) is empirical; don't exceed it.

---

## Mode 3 — Cloud remote (`claude --remote`)

### When to use

- Multi-hour autonomous builds you don't want to supervise
- Tasks with a clear specification that won't need live steering
- Work you want to kick off from a phone (dispatch-style) and pick up later
- Scenarios where multiple truly-isolated concurrent sessions are needed (cloud sessions are fully isolated — no shared anything)

### Invocation

Two paths:

1. **CLI:** `claude --remote "<prompt>"` from inside the project directory. The CLI packages the current branch state, dispatches to a cloud VM, and returns a session URL + ID.
2. **Web UI:** `claude.ai/code` -> choose the project -> type the prompt. Same cloud VM under the hood.

Monitoring: `/tasks` CLI command, `claude.ai/code` sidebar, Claude mobile app, or the live transcript at `https://claude.ai/code/{session-id}`. You can steer in real time or let it run.

Bringing a cloud session back local: `claude --teleport <session-id>` pulls the session into a local terminal so you can continue interactively from where the cloud left off.

### Enforcement available

**Project `.claude/` only, per Decision 011 Approach A.** The cloud VM clones the repo from GitHub (or falls back to a bundled upload for ≤100MB repos) and inherits ONLY the project-level `.claude/` directory. Specifically:

- **YES inherited:** project `.claude/settings.json` (hooks declared there), project `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.mcp.json`, plugins named in project `settings.json.enabledPlugins`, and top-level `CLAUDE.md`
- **NO inherited:** user-level `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/rules/*`, `~/.claude/agents/*`, `~/.claude/hooks/*`, `~/.claude/skills/*`, `~/.claude/templates/*`, `~/.claude/local/*`, plugins enabled only in user settings, MCP servers from `claude mcp add`

Phase A research evidence (section A.3, A.4) cross-referenced this against `docs/harness-architecture.md`: by default, a cloud session runs with **near-zero Neural Lace harness enforcement**. To preserve enforcement, the harness MUST live in the cloned project's `.claude/` directory.

**Decision 011 Approach A closes this gap:** downstream projects either symlink `.claude/` to `~/claude-projects/neural-lace/adapters/claude-code/` (for solo-dev local convenience — symlink resolves locally but doesn't travel to cloud, so the CLI's file-bundle pre-processes the symlinked content) or commit a copy of the harness into `.claude/` (for team-shared / cloud-portable scenarios). Cloud sessions inherit either automatically via the repo clone.

Per Decision 011: *"this is the only mechanism that gives cloud sessions full harness enforcement. Without it, `claude --remote` runs with near-zero Neural Lace enforcement (no TDD gate, no plan-edit-validator, no vaporware-prevention hooks, no verifier agents)."*

### Concurrency model

Cloud sessions are **fully isolated VMs** (4 vCPU, 16GB RAM, 30GB disk per Phase A research). No shared state between parallel cloud sessions on the same repo. Each session clones its own copy; uncommitted state never collides.

Quotas per Phase A research: Pro = ~5 async/day, Max = ~15/day, Team/Enterprise = ~25/day (rough allocation across all cloud usage including Routines).

### Concrete examples

- "Implement the full refactor of feature X across these 40 files; open a PR when done" — set it running in cloud, check `/tasks` in the morning
- Nightly completeness check of the acceptance scenarios in every ACTIVE plan
- Parallel dispatch of 10 independent features across 10 cloud sessions (each isolated; no collision)
- Kicking off a migration from a phone while you're away from the desk

### Tradeoffs

- **Pro:** fully isolated; no shared-state collisions with local sessions or with other cloud sessions
- **Pro:** doesn't tie up your local machine — you can close the laptop and the build continues
- **Pro:** scales to concurrent runs bounded only by the daily quota, not by local CPU
- **Con:** harness enforcement only exists if Decision 011 Approach A is adopted in the target project (else cloud session is unenforced)
- **Con:** cold-start latency (~30-90s for repo clone + environment setup) makes cloud cost-effective only for work that takes longer than that overhead
- **Con:** no live IDE steering — monitoring is via the web/mobile surface, not your editor
- **Con:** daily quota caps — not suitable for tight-loop iteration where you might launch 50 sessions/day

### Known failure modes

- Cloud session clones from the branch's GitHub state; **uncommitted local changes don't travel.** Always commit before dispatching, or the cloud will build against stale state.
- If the project `.claude/` is empty or missing, the cloud session runs without Neural Lace enforcement — the session will still complete, but no hook will block vaporware or enforce plans. Decision 011 Approach A is the mitigation.
- Sensitive credentials NEVER live inside a cloud VM. GitHub pushes happen via Anthropic's GitHub Proxy service, not via tokens in the sandbox. If your task needs a third-party API credential, it must be provided via Anthropic's secret-injection mechanism — not echoed into the prompt.

---

## Mode 4 — Scheduled / event-triggered (Routines via `/schedule`)

### When to use

- Recurring work on a cron schedule (nightly verification, weekly backlog grooming)
- Event-triggered automation (on CI failure, on PR open, on a webhook fire)
- Long-running migrations triggered on demand via HTTP API

### Invocation

Primary: the `/schedule` slash command. Pass the prompt you want to run plus a cron expression or trigger spec. Anthropic Routines (launched April 14, 2026 per Phase A research) fires a fresh isolated cloud VM for each trigger — architecturally identical to Mode 3 under the hood.

Alternatives: the `scheduled-tasks` MCP server exposes `create_scheduled_task` / `list_scheduled_tasks` for programmatic scheduling.

### Enforcement available

**Same as Mode 3** — project `.claude/` only. Routines inherit the harness the same way `claude --remote` does. Decision 011 Approach A applies identically: if the project's `.claude/` contains the harness, each Routine run inherits it.

### Quota

Per Phase A research: Pro = 5 runs/day, Max = 15/day, Team/Enterprise = 25/day. Shared with the Mode 3 daily quota (both count against the same cloud-session allocation).

### Concrete examples

- Nightly `/schedule "run /find-my-bugs against the week's merged commits and open issues for each finding"` (at 02:00 daily)
- On-CI-failure auto-fix PR: `/schedule "fix the CI failure on this PR" --trigger github-event:check-failure`
- Weekly backlog grooming: `/schedule "review docs/backlog.md and dedupe / reprioritize" --cron "0 9 * * MON"`
- Long-running migration triggered via HTTP: `/schedule "apply migration 042 with data verification" --trigger http`

### Tradeoffs

- **Pro:** work happens without you remembering to run it
- **Pro:** cloud isolation (same as Mode 3)
- **Pro:** event triggers open automation paths that cron alone can't cover
- **Con:** same daily quota as `--remote`; heavy scheduling consumes the budget that might be wanted for ad-hoc autonomous work
- **Con:** same harness-portability constraint — if project `.claude/` is empty, Routines run without enforcement
- **Con:** debugging a failed Routine requires reading logs after the fact; no live steering

### Known failure mode

A Routine that assumes a feature exists (e.g., "deploy to staging") but the project is in a branch state where the feature doesn't yet exist. Routines run on a scheduled cadence that may outrun the state of the repo. Mitigation: the Routine prompt should itself query state before acting ("check if the deploy script exists; if not, comment on the tracking issue instead of erroring").

---

## Out-of-scope modes

For completeness, these capabilities exist but are NOT part of the four-mode decision tree (per Decision 011 explicit scope):

### Dispatch (Claude Cowork cross-device delegation)

Phone -> desktop task delegation. Single-desktop model: phone sends tasks, desktop executes. **Not a parallel-orchestration solution** — if the desktop closes, tasks queue but don't execute. Useful as personal convenience (send a quick task to your always-on desktop from your phone), NOT load-bearing for the "how do I run concurrent isolated sessions" question.

Decision 011 classifies Dispatch as out of scope for the core problem: it doesn't provide parallel-session isolation, and it doesn't inherit harness any differently than the desktop session it talks to.

### Managed Agents (platform.claude.com)

Separate Anthropic platform ($0.08/session-hour + token costs, public beta since April 8, 2026). API-level multi-agent orchestration where agents are defined via API, not via `.claude/` files.

Rejected in Decision 011 Alternative D: would require complete architectural rewrite of the harness as agent logic. Months of work to migrate 26 hooks + 17 rules + 16 agents + 5 skills + 10 templates from declarative `.claude/` files to imperative API code. Wrong tool for a local development harness.

### DevContainers (Docker-based local isolation)

Official Claude Code support via `.devcontainer/` config. Each project's container = full filesystem isolation — eliminates the shared-`~/.claude/` collision risk that Mode 2 has. Per-project opt-in.

Decision 011 keeps DevContainers as an **optional layer** for interactive multi-session local dev when concurrent local sessions are needed AND interactive steering is required (i.e., not autonomous enough for cloud). Adds Docker as a dependency. Not load-bearing for the common case; documented for teams that need stricter local isolation than Mode 2's worktrees provide.

### Self-hosted Claude Code

Does not exist as an Anthropic offering as of the Phase A research date (2026-04-23). The CLI requires authentication to claude.ai. Not viable.

---

## The decision tree

Flowchart form — read top-to-bottom, stop at the first match:

1. **Is this work that needs your live judgment on each step?** (UX calls, taste decisions, exploratory debugging)
   -> **Mode 1 (Interactive local)**

2. **Is this recurring work on a cron or an event trigger?**
   -> **Mode 4 (Scheduled / Routines)**

3. **Is this a multi-hour autonomous build you won't supervise?**
   -> **Mode 3 (Cloud remote)** — requires project `.claude/` to be populated per Decision 011 Approach A; else falls back to unenforced cloud which is strongly discouraged

4. **Do you need 2-5 concurrent builds on disjoint files, each short enough that a cloud cold-start is proportionally expensive?**
   -> **Mode 2 (Parallel local worktrees)** — via orchestrator pattern with `isolation: "worktree"`, or Desktop "+ New session"

5. **Default:** Mode 1 (Interactive local).

---

## Pairing modes

Modes compose. Common combinations:

- **Mode 1 orchestrator dispatching Mode 2 builders:** the main interactive session becomes an orchestrator that dispatches parallel builders in worktrees. See `rules/orchestrator-pattern.md`.
- **Mode 1 orchestrator dispatching Mode 3 builders:** the orchestrator kicks off long autonomous tasks to cloud and stays in foreground for steering. Each cloud dispatch is an independent session with its own quota consumption.
- **Mode 4 triggering Mode 3 (same infrastructure):** a scheduled Routine IS a Mode 3 cloud session; this is one concept with two invocation paths.

Do NOT mix Mode 1 and Mode 2 on the same working tree without worktrees (i.e., launching a second bare Claude Code session while the first is still running). This is the cross-session plan-wipe failure mode documented in Decision 011 Consequences and the `docs/claude-code-quality-strategy.md` residual-risks section.

---

## Setup prerequisites per mode

| Mode | Prerequisites |
|---|---|
| 1 | Local install of Claude Code (`install.sh` from neural-lace, or direct Anthropic install) |
| 2 | Mode 1 prerequisites + the project is a git repo |
| 3 | Anthropic Pro/Max/Team/Enterprise subscription with `--remote` entitlement. Project pushed to GitHub (or small enough to bundle, ≤100MB). Project `.claude/` populated per Decision 011 Approach A for enforcement to carry over. |
| 4 | Mode 3 prerequisites + `/schedule` command availability (requires Pro+). `scheduled-tasks` MCP server optional for programmatic scheduling. |

The project-`.claude/` adoption for Mode 3 / Mode 4 is a one-time per-project setup. The two supported forms are:

- **Symlink:** project `.claude/` symlinks to `~/claude-projects/neural-lace/adapters/claude-code/`. Edits propagate automatically via the filesystem. Best for solo-dev; symlinks may not traverse to cloud cleanly depending on how the CLI packages the repo.
- **Committed copy:** project `.claude/` is a real directory with a copy of the harness, committed to the repo. Best for team-shared or cloud-portable scenarios. Sync via `cp -r ~/claude-projects/neural-lace/adapters/claude-code/* .claude/` from time to time.

See `docs/decisions/011-claude-remote-harness-approach.md` for the full rationale behind picking one over the other.

---

## Cross-reference to other harness rules

- `rules/orchestrator-pattern.md` — how to dispatch parallel builders (Mode 2 mechanics)
- `rules/planning.md` — plan lifecycle and the `Execution Mode: orchestrator` header field
- `rules/harness-maintenance.md` — how harness changes propagate from `~/.claude/` to `neural-lace` to downstream project `.claude/`
- `docs/decisions/011-claude-remote-harness-approach.md` — the decision record this rule operationalizes
- `docs/plans/archive/claude-remote-adoption-evidence.md` — Phase A empirical research that backs the claims in this rule
- `docs/claude-code-quality-strategy.md` "Known Gaps and Residual Risks" section 3 and 4 — the concurrent-session and harness-portability problems this rule addresses

---

## Known gaps

- **Empirical validation of cloud harness inheritance** is research-substitute only as of 2026-04-23 — Phase A deferred live `claude --remote` testing to a P2 backlog item. First real cloud-session build in a downstream project with project `.claude/` populated will confirm (a) harness loads correctly, (b) verifier agents run, (c) hooks fire, (d) `plan-lifecycle.sh` archival works on Status flip. If any fails, this rule is updated with the correction.
- **Symlinked `.claude/` behavior under `claude --remote` repo packaging** is not empirically confirmed. The CLI's bundle mechanism may or may not follow symlinks. If symlinks don't travel, Approach A solo-dev path requires the committed-copy alternative.
- **Daily cloud quota is aggregate across Mode 3 and Mode 4.** Heavy scheduled use consumes budget for ad-hoc autonomous use. There's no mechanism to prioritize ad-hoc dispatch over Routines if both compete for the day's quota.
