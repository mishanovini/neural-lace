# Automation Modes — Choosing Where a Claude Code Session Runs

**Classification:** Pattern (self-applied decision discipline). The mode choice is the operator's judgment call; no hook blocks the "wrong" mode. But once a mode is chosen, its specific enforcement substrate is what it is — the Pattern here is picking the mode whose enforcement matches the task.

**Ships with:** Decision 011 (`docs/decisions/011-claude-remote-harness-approach.md`) — read it first. This rule operationalizes Decision 011 as a decision tree. Phase A research evidence (`docs/plans/archive/claude-remote-adoption-evidence.md`) is the factual substrate for every claim below. **Mode 5 (Agent Teams)** added per Decision 012 (`docs/decisions/012-agent-teams-integration.md`); see also `rules/agent-teams.md` for the full operational guide.

---

## The five modes

A Claude Code session runs in exactly one of five modes. Each has a different enforcement substrate (which hooks/rules/agents actually fire), a different isolation story (what concurrent sessions can or cannot collide on), and a different best-fit task class.

| # | Mode | Isolation | Harness enforcement | Best for |
|---|---|---|---|---|
| 1 | **Interactive local** | Single session per working tree | **Full** (`~/.claude/` loaded) | Tight-loop work, UX decisions, live steering |
| 2 | **Parallel local (worktrees)** | Git worktrees isolate files; `~/.claude/` shared | **Full for rules/hooks/agents; shared state collision risk** | Short parallel builds on disjoint files |
| 3 | **Cloud remote (`claude --remote`)** | Fresh VM per session; nothing shared | **Project `.claude/` only** (per Decision 011 Approach A) | Multi-hour autonomous builds, tasks that don't need interactive steering |
| 4 | **Scheduled (Routines via `/schedule`)** | Same as mode 3 — fresh VM per trigger | **Project `.claude/` only** | Nightly / cron / event-triggered recurring work |
| 5 | **Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)** | In-process default (per `force_in_process: true`); pane-based opt-in. Lead and teammates share `~/.claude/state/` but team-aware hooks scope counters by `team_name`. | **Full** for in-process teammates (lead's `~/.claude/` reused; teammates inherit project `.claude/` per Decision 011 Approach A). **Partial** for pane-based teammates on macOS+tmux (some parent-visibility events drop per Anthropic #24175). | Complex multi-agent workflows where direct teammate-to-teammate messaging is needed |

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

## Mode 5 — Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

Anthropic's experimental Agent Teams feature lets a "lead" Claude Code session spawn cooperating "teammate" sessions that can directly message each other (without round-tripping through the lead). Status: **feature-flagged in Neural Lace, disabled by default** per Decision 012. The five upstream Anthropic bugs (#50779, #24175, #24073, #24307, #45329) make silent enforcement degradation likely if enabled without the integration work this rule references.

### When to use

- Complex multi-agent workflows where teammate-to-teammate coordination is the load-bearing requirement (vs. orchestrator-pattern, where the main session is the only coordinator and teammates report back through it)
- Tasks where the structured `TaskCreated` / `TaskCompleted` event surface enables team-attributable enforcement that per-Edit hooks can't provide (per Anthropic #45329, `teammate_name`/`team_name` are observable in TaskCreated/Completed event input but NOT in PreToolUse Edit input)
- Scenarios where direct messaging between teammates avoids redundant orchestrator round-trips (e.g., a planner teammate handing structured tasks to a builder teammate without the lead reading the entire plan twice)

For most multi-task plans, **prefer the orchestrator pattern (Mode 1 dispatching to Mode 2 builders).** Agent Teams is opt-in for cases where teammate-to-teammate messaging actually matters; the orchestrator pattern is simpler and has fewer upstream bugs.

### Invocation

1. Ensure the harness is at `~/.claude/` (Mode 1 prerequisites).
2. Enable the feature flag: copy `adapters/claude-code/examples/agent-teams.config.example.json` to `~/.claude/local/agent-teams.config.json` and set `"enabled": true`. Defaults: `force_in_process: true` (until Anthropic #24175 is fixed), `worktree_mandatory_for_write: true`, `per_team_budget: true`.
3. Set the env var: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (in your shell or session settings).
4. Launch Claude Code (`claude` or IDE extension); the session can now spawn teammates via the `Agent` tool with `team_name` set.

Full enable instructions, including the clear-eyed list of upstream bugs the user opts into, live in `rules/agent-teams.md`. Read that rule before flipping the flag.

### Enforcement available

**In-process teammates (the default per `force_in_process: true`):**

- Full `~/.claude/` harness — lead's settings, hooks, agents, rules all reused by teammates
- New PreToolUse gate: `teammate-spawn-validator.sh` rejects unsafe spawn configurations (e.g., write-capable teammate without worktree isolation; `--dangerously-skip-permissions` with `force_in_process: true`)
- New TaskCreated event hook: `task-created-validator.sh` validates teammate task subjects + plan references + acceptance criteria
- New TaskCompleted event hook: `task-completed-evidence-gate.sh` enforces evidence-block existence + consumes the deferred-audit flag from the team-aware `tool-call-budget.sh`
- Extended `tool-call-budget.sh` (per-team counter + deferred-audit cadence + 90-call hard ceiling per teammate)
- Extended `plan-edit-validator.sh` (flock concurrent-write protection so two parallel verifiers serialize safely)
- Extended `product-acceptance-gate.sh` (multi-worktree artifact aggregation so a teammate's runtime PASS in its own worktree satisfies the lead's gate)

**Pane-based teammates (opt-in, set `force_in_process: false`):**

- Teammate's own `~/.claude/settings.json` loads independently (per Anthropic #24175 source-level analysis), so teammate-side hooks fire correctly
- BUT some parent-visibility events drop on macOS+tmux (`SubagentStart`, `Stop`, `TeammateIdle`, `TaskCompleted` may not reach the lead) — the lead's gates therefore see degraded coverage
- Recommended only when teammate-side full enforcement matters more than lead-side aggregate enforcement

### Decision 011 Approach A still applies

**Teammates inherit project `.claude/` the same way as the lead's session.** If the lead is in a project where `.claude/` is symlinked to `~/claude-projects/neural-lace/adapters/claude-code/` (solo-dev path) or contains a committed copy of the harness (team-shared / cloud-portable path), teammates see the same harness. There is no separate per-teammate harness inheritance story — it's one copy of the harness, shared across the lead and every in-process teammate. For pane-based teammates the same constraint applies because each pane reads the same project `.claude/`.

**This is the harness-portability story for Mode 5:** Decision 011 Approach A is unchanged; Agent Teams adds team-aware enforcement on top. If a project has run the rollout to populate `.claude/` (per Decision 011), it is also Agent-Teams-ready once the feature flag is flipped and the new hooks land.

### Concurrency model

In-process: bounded by Anthropic's caps on concurrent teammates per session (currently ~5 in-process; pane-based has higher caps but with the macOS+tmux degradation noted). The team-aware tool-call budget caps a single teammate at 90 tool calls without an intervening TaskCompleted; the per-team deferred-audit fires at 30 cumulative calls across all teammates.

Pane-based: bounded by terminal-multiplexer constraints (tmux/iTerm2). Windows Git Bash lacks tmux entirely, so pane-based mode is effectively macOS+Linux-only.

### Concrete examples

- A planner teammate authors `## Acceptance Scenarios` in plan-time mode while a builder teammate starts on Phase 1 — both report progress directly to each other without the lead arbitrating each handoff.
- A research teammate enumerates the codebase's existing patterns while a code-reviewer teammate evaluates the lead's proposed change against those patterns — both teammates feed signals to the lead simultaneously.
- A cluster of read-only teammates (research, explorer, claim-reviewer) querying different parts of a large codebase in parallel, each posting findings into a shared task subject the lead aggregates.

### Tradeoffs

- **Pro:** team-attributable enforcement (`teammate_name`/`team_name` observable in TaskCreated/Completed events) — closes the per-Edit attribution gap from Anthropic #45329
- **Pro:** direct teammate-to-teammate messaging avoids redundant orchestrator round-trips
- **Pro:** harness gates extend to multi-agent workflows that the orchestrator pattern handles less elegantly
- **Con:** **five known upstream Anthropic bugs.** The feature is experimental; flipping the flag is a deliberate opt-in to the specific behaviors documented in `rules/agent-teams.md`.
- **Con:** in-process teammates share the lead's permission mode — a lead in `--dangerously-skip-permissions` propagates the bypass to every teammate. The spawn validator blocks this when `force_in_process: true` is set.
- **Con:** pane-based mode has macOS+tmux event-drop degradation (Anthropic #24175). The harness defaults to in-process to side-step this.
- **Con:** worktree-mandatory writes add cherry-pick overhead to the team's work (mitigated by mandating worktrees only for write-capable teammates, not read-only ones).

### Known failure modes

- **Lead crashes mid-session, teammates orphaned.** Orphaned teammates may continue spawning Edit/Write hooks against their own state directories. Cleanup is per teammate-self-cleanup; flock timeouts mean stale locks self-clear after 30s.
- **Two teams concurrently on the same project.** `flock` on `<plan>.lock` covers concurrent verification. Two leads creating new plans is out of scope and falls back to existing single-session behavior.
- **`team_name` containing special characters.** `tool-call-budget.sh` strips non-alphanumeric chars and applies a 64-char length cap; `task-created-validator.sh` rejects disallowed-char team names at TaskCreated time.
- **Stale `~/.claude/state/audit-pending.<team>` flag.** If a TaskCompleted never fires (lead crashed, team disbanded), the flag persists. Mitigation: the existing 24h auto-cleanup of `~/.claude/state/*` extends to these flags.

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

4. **Do you need direct teammate-to-teammate messaging in a multi-agent workflow** (where the orchestrator pattern's lead-as-only-coordinator is the bottleneck)?
   -> **Mode 5 (Agent Teams)** — only after reading `rules/agent-teams.md` (the five upstream Anthropic bugs are deliberate opt-ins)

5. **Do you need 2-5 concurrent builds on disjoint files, each short enough that a cloud cold-start is proportionally expensive?**
   -> **Mode 2 (Parallel local worktrees)** — via orchestrator pattern with `isolation: "worktree"`, or Desktop "+ New session"

6. **Default:** Mode 1 (Interactive local).

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
| 5 | Mode 1 prerequisites + Claude Code v2.1.32+ + `~/.claude/local/agent-teams.config.json` with `enabled: true` + `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var set. The new hooks (`teammate-spawn-validator.sh`, `task-created-validator.sh`, `task-completed-evidence-gate.sh`) must be present in `~/.claude/hooks/` and wired in `~/.claude/settings.json`. Read `rules/agent-teams.md` before flipping the flag. |

The project-`.claude/` adoption for Mode 3 / Mode 4 is a one-time per-project setup. The two supported forms are:

- **Symlink:** project `.claude/` symlinks to `~/claude-projects/neural-lace/adapters/claude-code/`. Edits propagate automatically via the filesystem. Best for solo-dev; symlinks may not traverse to cloud cleanly depending on how the CLI packages the repo.
- **Committed copy:** project `.claude/` is a real directory with a copy of the harness, committed to the repo. Best for team-shared or cloud-portable scenarios. Sync via `cp -r ~/claude-projects/neural-lace/adapters/claude-code/* .claude/` from time to time.

See `docs/decisions/011-claude-remote-harness-approach.md` for the full rationale behind picking one over the other.

---

## Cross-reference to other harness rules

- `rules/orchestrator-pattern.md` — how to dispatch parallel builders (Mode 2 mechanics); also documents how the orchestrator pattern coexists with Mode 5 Agent Teams
- `rules/agent-teams.md` — full operational guide for Mode 5 (Agent Teams), including the five upstream Anthropic bugs the user opts into and the workarounds the harness ships
- `rules/planning.md` — plan lifecycle, `Execution Mode: orchestrator` header field, and `Execution Mode: agent-team` for Mode 5 plans
- `rules/harness-maintenance.md` — how harness changes propagate from `~/.claude/` to `neural-lace` to downstream project `.claude/`
- `docs/decisions/011-claude-remote-harness-approach.md` — the decision record Modes 3 + 4 + 5 (Approach A inheritance) operationalize
- `docs/decisions/012-agent-teams-integration.md` — the decision record introducing Mode 5
- `docs/plans/agent-teams-integration.md` — the plan that introduced Mode 5 and the new hooks
- `docs/plans/archive/claude-remote-adoption-evidence.md` — Phase A empirical research that backs the claims in this rule
- `docs/claude-code-quality-strategy.md` "Known Gaps and Residual Risks" section 3 and 4 — the concurrent-session and harness-portability problems this rule addresses

---

## Known gaps

- **Empirical validation of cloud harness inheritance** is research-substitute only as of 2026-04-23 — Phase A deferred live `claude --remote` testing to a P2 backlog item. First real cloud-session build in a downstream project with project `.claude/` populated will confirm (a) harness loads correctly, (b) verifier agents run, (c) hooks fire, (d) `plan-lifecycle.sh` archival works on Status flip. If any fails, this rule is updated with the correction.
- **Symlinked `.claude/` behavior under `claude --remote` repo packaging** is not empirically confirmed. The CLI's bundle mechanism may or may not follow symlinks. If symlinks don't travel, Approach A solo-dev path requires the committed-copy alternative.
- **Daily cloud quota is aggregate across Mode 3 and Mode 4.** Heavy scheduled use consumes budget for ad-hoc autonomous use. There's no mechanism to prioritize ad-hoc dispatch over Routines if both compete for the day's quota.
