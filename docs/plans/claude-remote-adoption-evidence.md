# Evidence Log — claude-remote-adoption

This file documents evidence for each task in `docs/plans/claude-remote-adoption.md`. Phase A is research-driven (since live empirical testing of `claude --remote` was deferred); Phases B onward are implementation-driven.

---

## A.1 — Test `claude --remote` in isolation (research substitute)

**Date:** 2026-04-23
**Method:** Comprehensive doc-based research via `claude-code-guide` agent, two-round investigation. Live empirical testing deferred to backlog (P2 — user can validate findings via one-off `claude --remote` invocation when convenient).

**Findings:**

1. **Product name:** Claude Code on the Web. CLI flag: `claude --remote "prompt"`. Web UI: `claude.ai/code`.
2. **Repo source:** Cloud session clones from GitHub at the current branch. Fallback: bundles local repo (≤100MB, tracked files only) when not connected to GitHub. Force bundle: `CCR_FORCE_BUNDLE=1`.
3. **Project `.claude/` accessibility:** YES — cloud session reads + executes `.claude/settings.json` hooks, `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.mcp.json`, plugins declared in repo's `.claude/settings.json`, and `CLAUDE.md`.
4. **User `~/.claude/` accessibility:** NO — cloud session does NOT inherit user-level `~/.claude/`. Includes: user-level `CLAUDE.md`, plugins enabled only in user settings, MCP servers from `claude mcp add`, static API tokens, interactive auth like AWS SSO. Confirmed against [official table](https://code.claude.com/docs/en/claude-code-on-the-web).
5. **Monitoring:** `/tasks` CLI command, claude.ai/code web UI sidebar, Claude mobile app, live transcript at `https://claude.ai/code/{session-id}`. Real-time streaming + steering supported.
6. **Session completion:** PR if Claude created branch + opened it; transcript persists in web UI; `claude --teleport <session-id>` pulls session into local terminal to continue. No auto-push by default.
7. **Auth:** GitHub Proxy service (NOT direct token in sandbox). Either GitHub App (per-repo scoped) or `gh` CLI token synced via `/web-setup`. Push restricted to current branch. Sensitive credentials NEVER inside sandbox.
8. **Cost:** Cloud usage shares rate limits with all Claude usage. NO separate compute charge. Pro/Max/Team/Enterprise tiers; Pro=5 async/day, Max=15/day, Team/Enterprise=25/day (rough allocation).
9. **Concurrency:** Unlimited parallel cloud sessions (within quota). Each = isolated VM (4 vCPU, 16GB RAM, 30GB disk). Network access configurable (None/Trusted/Full/Custom). Fully isolated — no shared state collisions across parallel sessions.

**Verdict:** PASS (research-substitute; live verification deferred to P2 backlog item)

---

## A.2 — Test Desktop "+ New session" behavior (research substitute)

**Findings:**

1. **Worktree creation:** YES for Git repos. Default location `<project-root>/.claude/worktrees/`. Customizable in Settings → Claude Code → "Worktree location". Non-Git projects share same dir (no isolation).
2. **Commit propagation:** Manual cherry-pick + merge. NO auto-merge from worktree to main. Standard PR-based workflow recommended.
3. **Concurrent local-session uncommitted-state visibility:** NO — worktrees provide full isolation. "Changes in one session don't affect other sessions until you commit them." This addresses the concurrent-session plan-wipe failure mode (P1 backlog) for FUTURE sessions, but doesn't help sessions currently running on shared `~/.claude/`.
4. **Sub-agents:** Isolated to parent session. Cannot see sibling sessions; share git history but not uncommitted state.
5. **Shared vs isolated `~/.claude/`:** ALL `~/.claude/` content is SHARED across parallel local sessions on the same machine. Includes: `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/hooks/`, `~/.claude/rules/`, `~/.claude/agents/`, `~/.claude/skills/`, `~/.claude/local/`, `~/.claude.json`. **Implication: parallel local sessions still risk concurrent-session state-edit races on user-level harness files.**

**Verdict:** PASS

---

## A.3 — Verify config inheritance for cloud sessions

**Findings:** (Builds on A.1)

1. **Project `.claude/` directory:** YES — all subdirectories inherited (hooks, agents, rules, skills, settings.json, plans, templates if committed).
2. **`~/.claude/` contents:** Confirmed NOT inherited.
3. **Settings precedence in cloud:** Three-tier — managed (org admin) > project (`.claude/settings.json`) > user (`~/.claude/settings.json`). User tier effectively absent in cloud since `~/.claude/` doesn't travel.
4. **`CLAUDE_CONFIG_DIR`:** Not documented for cloud sessions. Likely not honored (no `~/.claude/` to point at).
5. **Plugins/marketplaces:** Cloud sessions start CLEAN. Only plugins declared in project's `.claude/settings.json` `enabledPlugins` are available. User plugins from `~/.claude/settings.json` do NOT carry over. Plugins fetched from marketplace at session start (requires network access).

**Verdict:** PASS

---

## A.4 — Identify missing-in-cloud harness components

**Findings (cross-referenced against neural-lace inventory):**

| Component | Count | Cloud availability | Gap impact |
|---|---|---|---|
| `~/.claude/hooks/*.sh` | ~26 hooks | NOT available (user-level) | All enforcement disabled in cloud unless committed to project `.claude/settings.json` |
| `~/.claude/rules/*.md` | ~17 rules | NOT available (user-level) | No global rule enforcement unless forked to project `.claude/rules/` |
| `~/.claude/agents/*.md` | ~16 agents | NOT available (user-level) | Verification agents (task-verifier, plan-evidence-reviewer, systems-designer, end-user-advocate) MISSING |
| `~/.claude/skills/*.md` | ~5 skills | NOT available (user-level) | Slash commands (`/harness-review`, `/why-slipped`, etc.) MISSING |
| `~/.claude/templates/*.md` | 3 templates | NOT available (user-level) | Plan/decision/completion templates MISSING |
| `~/.claude/scripts/*.sh` | 1 script (find-plan-file) | NOT available (user-level) | Utility scripts MISSING |
| `~/.claude/local/*.config.json` | per-machine | NOT available (by design) | Personal/machine-specific config MISSING — appropriate (cloud shouldn't have local secrets) |
| `~/.claude/CLAUDE.md` | 1 file | NOT available (user-level) | Global standards MISSING |
| `~/.claude/settings.json` | 1 file (with 13 PreToolUse hooks + Stop chain + permissions) | NOT available (user-level) | All session-enforcement MISSING |

**Conclusion:** Cloud sessions, by default, run with NEAR-ZERO neural-lace harness enforcement. To preserve enforcement in cloud, the harness must be present in the cloned project's `.claude/` directory.

**Verdict:** PASS

---

## Round 2 expanded research — Dispatch + other Anthropic remote/cloud capabilities

User flagged that round 1 missed Dispatch + other recently-shipped products. Round 2 added:

### Dispatch
- **What it is:** Cross-device delegation in Claude Cowork (released March 17, 2026). Phone ↔ desktop persistent thread.
- **NOT a parallel-orchestration solution.** Single-desktop model: phone sends tasks, desktop executes. If desktop closes, tasks queue but don't execute.
- **Doesn't solve concurrent-session collision problem** — still bound to one desktop session sharing `~/.claude/`.
- **Useful for:** monitoring + sending tasks from phone to always-on desktop. Not load-bearing for our scenario.

### Routines (scheduled/API/event-triggered cloud automation)
- **What it is:** Anthropic-managed cloud automation triggered by cron, HTTP API, or GitHub events. Launched April 14, 2026.
- **Architecture:** Each trigger fires a fresh isolated cloud session (same VM model as `--remote`).
- **Daily run limits:** Pro=5, Max=15, Team/Enterprise=25.
- **Harness inheritance:** Same as cloud sessions — project `.claude/` only.
- **Use cases:** scheduled migrations, auto-fix PRs on CI failure, nightly verification, deployment monitoring.
- **Concurrency:** Each routine run is independent + isolated.

### Claude Code Remote Control (desktop ↔ web/mobile)
- Exposes a running local CLI session to claude.ai/code or mobile app for remote monitoring.
- Different from `--remote` (cloud) and `--teleport` (cloud → local).
- Doesn't solve shared `~/.claude/` collision.

### Managed Agents (separate Anthropic platform)
- API-level multi-agent orchestration. Public beta April 8, 2026. $0.08/session-hour + token costs.
- NOT a Claude Code product. Different programming model — agents defined via API, not `.claude/` files.
- Would require complete rewrite of harness as agent logic. Not appropriate for Neural Lace.

### DevContainers (Docker-based local isolation)
- Official Claude Code support via `.devcontainer/` config.
- Each project's container = full isolation (no host `~/.claude/` collision).
- Trail of Bits maintains a reference secure devcontainer.
- Trade-off: requires Docker; container must be running locally.

**Citations** (full list in [round-1 + round-2 reports above]):
- https://code.claude.com/docs/en/claude-code-on-the-web
- https://code.claude.com/docs/en/scheduled-tasks (Routines)
- https://code.claude.com/docs/en/desktop (worktrees)
- https://platform.claude.com/docs/en/managed-agents/overview
- https://buttondown.com/verified/archive/anthropic-unveils-dispatch-how-cross-device/ (Dispatch)
- https://anthemcreation.com/en/artificial-intelligence/claude-cowork-ga-ai-collaboration-subscribers/

**Verdict for A.1-A.4:** All PASS via research substitute. Live empirical verification deferred.
