# Decision 011 — Claude --remote Harness Portability Approach

**Date:** 2026-04-23
**Status:** Implemented
**Stakeholders:** Neural Lace harness maintainer
**Tier:** 2 (multi-mechanism choice that shapes how all future cloud-session work happens)
**Plan:** [`docs/plans/archive/claude-remote-adoption.md`](../plans/archive/claude-remote-adoption.md)

## Context

Anthropic shipped multiple session-mode capabilities in 2025-2026:
- **`claude --remote` (Claude Code on the Web)** — fresh isolated cloud VMs, repo cloned from GitHub, project `.claude/` inherited but user `~/.claude/` is NOT
- **Routines** — scheduled / API-triggered / GitHub-event-triggered cloud automation; same harness inheritance as `--remote`; daily run quotas
- **Desktop "+ New session" worktrees** — git worktree-based isolation between parallel local sessions, but ALL `~/.claude/` is shared
- **Dispatch** — mobile↔desktop async task delegation in Claude Cowork (single-desktop model, NOT a parallel-orchestration mechanism)
- **Managed Agents** — separate Anthropic platform with API-defined agents ($0.08/session-hour); requires complete rewrite of harness as agent logic
- **DevContainers** — official Claude Code support for Docker-isolated local sessions

**The user's scenario:** solo harness maintainer + multiple downstream projects, needs multi-hour autonomous builds without concurrent-session shared-state collisions, with full Neural Lace harness enforcement (~26 hooks, 17 rules, 16 agents, 5 skills) intact.

**The core gap:** the Neural Lace harness lives globally in `~/.claude/`. Cloud sessions and parallel local sessions need a strategy to either inherit it or do without.

## Decision

**Hybrid approach with three complementary mechanisms, each scoped to a task class:**

### Primary mechanism: **Approach A — Commit harness into project `.claude/`**

For autonomous builds via `claude --remote` (cloud sessions): commit a copy or symlink of the Neural Lace harness into each downstream project's `.claude/` directory. The cloud session clones the project repo and inherits the harness automatically.

**Implementation specifics:**
- Neural Lace remains the canonical source of truth for harness components (`adapters/claude-code/` already serves this role)
- Each downstream project `.claude/` directory either symlinks to `~/claude-projects/neural-lace/adapters/claude-code/` (for solo-dev local convenience) or contains a committed copy (for team-shared / cloud-portable scenarios)
- Update flow: edit harness in `~/.claude/` for live testing → mirror to `adapters/claude-code/` (existing convention) → push to neural-lace → downstream projects pull/sync

**Why primary:** this is the only mechanism that gives cloud sessions full harness enforcement. Without it, `claude --remote` runs with near-zero Neural Lace enforcement (no TDD gate, no plan-edit-validator, no vaporware-prevention hooks, no verifier agents).

### Augmentation: **Routines for scheduled / recurring autonomous work**

Use `/schedule "prompt"` to create Anthropic Routines for:
- Nightly verification runs
- Auto-fix PRs responding to CI failures
- Backlog grooming on a weekly cadence
- Long-running migrations triggered on demand via API

Routines inherit the project `.claude/` the same way `claude --remote` does. Daily quota: 5/Pro, 15/Max, 25/Team-Enterprise.

### Optional layer: **DevContainers for interactive multi-session local dev**

When concurrent local sessions are needed AND interactive steering is required (i.e., not autonomous enough for cloud), wrap each session in its own DevContainer. Each container provides full filesystem isolation, eliminating the shared `~/.claude/` collision risk. This is a per-project opt-in, not a global default. Adds Docker as a dependency.

### Dispatch — out of scope for the core problem

Dispatch is mobile→desktop async task delegation. It does NOT provide parallel-session isolation and does NOT inherit harness any differently than the desktop session it talks to. Useful as personal convenience (send a quick task to your always-on desktop from your phone), but not a load-bearing component of this decision.

## Alternatives Considered

### Alternative B — Cloud-session startup script downloads harness

Cloud session runs a setup script that clones neural-lace and installs the harness into `/tmp/.claude/` (or equivalent staging area).

**Rejected because:**
- **Fragility:** setup script needs network access, auth credential to clone neural-lace (PAT or service account), and reliable network at session-start time. Any failure leaves the cloud session with NO harness, no fallback.
- **Startup latency:** every cloud session pays the script-execution cost (~30-90s depending on network + install).
- **Versioning nightmare:** which harness version should the script clone? main? a pinned tag? How do you roll back a bad harness change after it's been deployed to N parallel sessions?
- **Enforcement gaps during startup:** SessionStart hooks fire before setup completes, so the early window has no harness.
- **Race conditions:** if two parallel sessions on the same project start simultaneously, they may race on staging the same files.

The "decoupled harness updates" benefit B promises is real, but it's outweighed by these reliability issues. Approach A's repo-bloat downside is mild (~50KB per project) compared to B's complexity.

### Alternative C — Restricted task class for cloud sessions

Accept that cloud sessions have minimal harness; only use them for "well-scoped mechanical work" that doesn't need plan-edit-validator, TDD gate, etc. Complex autonomous work stays local.

**Rejected because:**
- **Caps the value of cloud sessions** — the whole point of `claude --remote` is to run multi-hour autonomous builds without tying up the local machine. Restricting to mechanical tasks means cloud is a glorified shell-script runner.
- **Forces dual-mode mental model** — "use local for hard stuff, cloud for easy stuff" is exactly the kind of friction the user wants to eliminate.
- **Doesn't solve the original problem** — the user's stated need is multi-hour autonomous builds with full enforcement. Approach C says "you can't have that in cloud" which is a non-answer.

C is a defensible posture for orgs that don't want to commit harness to project repos for hygiene reasons. For this user (solo harness maintainer, hygiene already enforced via harness-hygiene-scan.sh in neural-lace itself), Approach A is the better trade.

### Alternative D — Migrate to Claude Managed Agents (API-level)

Rewrite the harness as agent logic in Anthropic's Managed Agents platform. Use API-driven multi-agent orchestration.

**Rejected because:**
- **Complete architectural rewrite** — months of work to migrate 26 hooks + 17 rules + 16 agents + 5 skills + ~10 templates from declarative `.claude/` files to imperative API code.
- **Loses the Neural Lace declarative model** — the harness's value is that it's expressed as files that Claude Code consumes natively. Managed Agents is a different programming model.
- **Pricing pivot** — $0.08/session-hour at parallelism scale (3 hourly builds × 8 hours × 30 days = $58/month just for compute, before token costs).
- **Wrong tool for the job** — Managed Agents is designed for production server-side agents (Notion, Rakuten, Sentry use it). Neural Lace is a development harness.

Not appropriate for this scenario. Acknowledged as a strategic option only if the user pivots to a fundamentally different model (e.g., shipping Neural Lace as a SaaS product rather than a local harness).

### Alternative E — Self-hosted Claude Code

There is no official Anthropic self-hosted Claude Code offering as of April 2026. The CLI requires authentication to claude.ai. Not viable.

## Consequences

**Enables:**
- Multi-hour autonomous builds via `claude --remote` with full harness enforcement (Approach A)
- Scheduled recurring work without local-machine dependency (Routines)
- Interactive multi-session local dev with isolation (DevContainers, opt-in)
- Cross-device monitoring of running sessions (Dispatch, optional)

**Costs:**
- **Repo bloat:** committing harness adds ~50KB per project's `.claude/`. Across 10 downstream projects = ~500KB. Acceptable.
- **Sync friction:** harness updates must propagate from neural-lace → each project. Mitigated by symlinks for solo-dev convenience or scheduled sync scripts for committed-copy scenarios.
- **Hygiene boundary:** committed harness must contain zero personal/business identifiers. Already enforced by `harness-hygiene-scan.sh` in neural-lace itself; downstream projects inherit the cleaned-up artifacts.

**Blocks:**
- This decision means downstream projects MUST adopt the harness in their `.claude/` directory to use cloud sessions effectively. Projects that don't want the harness in their repo are restricted to local sessions only.

**Reversible?** Partially. Switching from A to B (startup script) is a project-by-project adoption, not a one-shot architectural pivot. Switching from A to D (Managed Agents) would require the rewrite acknowledged above; not practically reversible.

**Test plan:**
- Phase B-D of plan #4 implement the rule, CLAUDE.md update, and strategy doc update reflecting this decision.
- First real cloud-session build in a downstream project IS the integration test. Observe whether: (a) committed harness loads correctly in cloud, (b) verifier agents run successfully, (c) hooks fire as expected, (d) plan-lifecycle.sh archival works on Status flip.

**Future work / monitoring:**
- If startup latency for committed-harness cloud sessions proves painful, revisit B (startup script with caching) as an optimization.
- If repo bloat becomes intolerable across many downstream projects, consider a "harness-as-installable-package" model (e.g., `npm install neural-lace-harness` or equivalent) that keeps repos clean while propagating harness updates centrally.
- If Anthropic ships a feature that lets cloud sessions inherit user-level `~/.claude/` directly, this decision becomes obsolete and we revert to user-level harness.
