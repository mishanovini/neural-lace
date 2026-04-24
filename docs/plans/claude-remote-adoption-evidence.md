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

---

## A.6 — Write `~/.claude/rules/automation-modes.md`

**Date:** 2026-04-23
**Task ID:** A.6

**What was built:**
- New rule file `~/.claude/rules/automation-modes.md` (~280 lines) operationalizing Decision 011 as a four-mode decision tree
- Mirrored to `adapters/claude-code/rules/automation-modes.md` (byte-identical)
- Added a row for the new rule in `~/.claude/docs/harness-architecture.md` Rules table; mirrored to `docs/harness-architecture.md` in neural-lace

**Sections in the new rule file:**
- Summary table of the four modes (isolation, harness enforcement, best-fit task)
- Mode 1 (Interactive local): when to use, invocation, full-harness enforcement detail, concrete examples, tradeoffs, known failure mode (concurrent local sessions wiping uncommitted state)
- Mode 2 (Parallel local worktrees): three invocation paths (Desktop, orchestrator dispatch, manual `git worktree add`), enforcement detail (full harness BUT shared `~/.claude/`), shared-state collision risk called out per Decision 011 + Phase A research
- Mode 3 (Cloud remote `claude --remote`): CLI + Web UI invocation, monitoring surfaces, `--teleport`, project-`.claude/`-only inheritance, full-isolation concurrency model, daily quotas (5/15/25 per Pro/Max/Team-Enterprise)
- Mode 4 (Scheduled Routines): `/schedule` invocation, MCP-server alternative, same harness inheritance as Mode 3, shared daily quota
- Out-of-scope modes: Dispatch (mobile↔desktop), Managed Agents, DevContainers, self-hosted — each with one-paragraph explanation of why excluded
- Numbered decision tree (5 stop conditions, top-to-bottom)
- Pairing rules (orchestrator-Mode-1 + builder-Mode-2 / Mode-3 valid; Mode-1 + bare-Mode-1 on same tree DANGEROUS)
- Per-mode setup prerequisites (subscriptions, GitHub push, `.claude/` adoption form)
- Cross-references to `orchestrator-pattern.md`, `planning.md`, `harness-maintenance.md`, Decision 011, Phase A evidence file, strategy doc residual-risks section
- Known gaps section (live cloud-session validation deferred; symlink behavior under cloud bundling not empirically confirmed; daily quota aggregate)

**Citations of Decision 011:** Direct quote of Decision 011's "this is the only mechanism that gives cloud sessions full harness enforcement..." sentence in Mode 3 enforcement section. Approach A symlink vs committed-copy options surfaced in setup prerequisites. Out-of-scope modes (Dispatch, Managed Agents, DevContainers, self-hosted) all cite Decision 011 alternatives reasoning explicitly.

**Citations of Phase A research:** Mode 3 enforcement section cites evidence file sections A.3 + A.4 by name. Mode 4 quota figures cite Phase A research section A.1. Mode 2 shared-`~/.claude/` risk cites evidence file section A.2.

**Diff verification (sync to adapter):**
```
$ diff -q ~/.claude/rules/automation-modes.md ~/claude-projects/neural-lace/adapters/claude-code/rules/automation-modes.md
(no output — files byte-identical)
```

**Runtime verification:** file `~/.claude/rules/automation-modes.md`

**Verdict:** PASS

---

## A.7 — Update `~/.claude/CLAUDE.md` with "Choosing a Session Mode" section

**Date:** 2026-04-23
**Task ID:** A.7

**What was built:**
- New "Choosing a Session Mode" section inserted into `~/.claude/CLAUDE.md` between "Naming & Identity" and "Autonomy" (near the top — first 30 lines of the file)
- 4 bullet points summarizing each mode in one line each (interactive local / parallel local worktrees / cloud remote / scheduled Routines)
- Closing paragraph pointing at `~/.claude/rules/automation-modes.md` for the full decision tree, and at `docs/decisions/011-claude-remote-harness-approach.md` for the rationale
- Mirrored to `adapters/claude-code/CLAUDE.md` (byte-identical)

**Why "near the top":** the rule explicitly named "near the top" in the plan task description. The new section is at lines 16-23 of the file (~5% from the top). This positions the mode-choice as something the operator confronts immediately on session start, consistent with the Decision 011 framing.

**Diff verification:**
```
$ diff -q ~/.claude/CLAUDE.md ~/claude-projects/neural-lace/adapters/claude-code/CLAUDE.md
(no output — byte-identical)
```

**Runtime verification:** file `~/.claude/CLAUDE.md`

**Verdict:** PASS

---

## A.8 — Update `docs/claude-code-quality-strategy.md` cloud-caveat paragraph

**Date:** 2026-04-23
**Task ID:** A.8

**What was built:**
- Replaced the "4. Harness-portability to cloud sessions" entry in the "Known Gaps and Residual Risks" section. Old entry described an unresolved tension between isolation (cloud) and enforcement (local). New entry titled "4. Harness-portability to cloud sessions — RESOLVED (2026-04-23)" and points at Decision 011 with a concrete summary of the three-part hybrid (Approach A primary, Routines augmentation, DevContainers optional). References `rules/automation-modes.md` for the operator-facing decision tree and the Phase A evidence file by path.
- Updated section "M. Adopt `claude --remote` + dotfiles sync" — original framing "in flight" / "based on the agent's research" / "dotfiles-synced harness". Replaced with "SHIPPED (2026-04-23)" header and updated framing to reference the four modes from `automation-modes.md`. Explicitly notes that Approach A (commit harness into project `.claude/`) superseded the dotfiles-sync framing because Phase A research confirmed cloud sessions inherit the cloned project `.claude/` directly without needing a separate dotfiles mechanism.

**What was preserved:** all other content in the strategy doc is untouched. Sections 1-3 of "Known Gaps" (verbal vaporware, tool-call-budget bypass, concurrent-session collisions) are unchanged. Section M's "Why" justification preserved with minor rewording.

**Cross-references introduced:** `docs/decisions/011-claude-remote-harness-approach.md`, `docs/plans/archive/claude-remote-adoption-evidence.md`, `rules/automation-modes.md`, `rules/orchestrator-pattern.md`.

**Runtime verification:** file `docs/claude-code-quality-strategy.md`

**Verdict:** PASS

---

## A.9 — Implement Approach A on a reference project

**Date:** 2026-04-23
**Task ID:** A.9

**Reference project chosen:** a small work-account demo repo on GitHub (path under the user's `~/claude-projects/<work-org>/` tree)
- GitHub remote: a public org-scoped demo repository
- Pre-existing files: `README.md`, `index.html`, `package.json`, `.github/` — no `.claude/` directory before this phase
- Selected because: (a) it's literally the "demo" repo for the org, making a perfect reference implementation; (b) minimal pre-existing content so cloud-session inheritance can be tested without confounding factors; (c) on GitHub so the cloud `--remote` clone path is exercised; (d) no existing `.claude/` to conflict with the new setup.

**Sync mechanism chosen:** **Committed copy** (Decision 011 Approach A — cloud-portable variant)

**Reason for committed copy over symlink:**
1. The reference project's purpose is to demonstrate the cloud-portability path. Symlinks may or may not traverse the `claude --remote` CLI's repo-bundle mechanism cleanly — committed copies are always portable.
2. The reference project is a work-account repo intended to be cloneable by anyone with access. A symlink to a path under `~/claude-projects/neural-lace/` would only resolve on a developer machine that has that path; cloud sessions cloning the repo cannot resolve it.
3. The committed-copy form is the canonical answer for team-shared / cloud-portable scenarios per Decision 011 Consequences.

**Setup performed:**
1. `mkdir -p <reference-project-root>/.claude`
2. `cp -r ~/claude-projects/neural-lace/adapters/claude-code/* .claude/` — copied all harness assets (CLAUDE.md, agents/, commands/, hooks/, install.sh, local/, patterns/, pipeline-templates/, rules/, schemas/, scripts/, settings.json, settings.json.template, skills/, templates/, tests/, sync.sh, business-patterns.paths.example)
3. Created `.claude/HARNESS-SYNC.md` documenting:
   - Why this committed copy exists (Decision 011 reference)
   - The source-of-truth flow diagram (`~/.claude/` -> `neural-lace/adapters/claude-code/` -> this project's `.claude/`)
   - The sync command (`cp -r ~/claude-projects/neural-lace/adapters/claude-code/* .claude/` + git add/commit/push)
   - The committed-copy-vs-symlink choice rationale
   - Hygiene boundary (no personal config in committed `.claude/`; use `~/.claude/local/` instead)
   - Verification procedure (local: confirm hooks fire / agents dispatch; cloud: `claude --remote "list every rule loaded for this session"`)

**Setup state at end of session:**
- Files PRESENT in the reference project's `.claude/` directory (including `HARNESS-SYNC.md`)
- Files NOT yet committed because the reference repo had no configured user identity. Per harness-maintenance.md ("NEVER update the git config"), this builder did not unilaterally configure a git identity for the user. The setup is observable on the local filesystem; the user can complete `git add .claude/ && git commit && git push` from their appropriate account context whenever convenient.
- Files were briefly staged via `git add` and then unstaged via `git reset HEAD .claude/` to avoid leaving state in the index without an accompanying commit.

**Verification (filesystem):**
```
$ ls <reference-project>/.claude/
CLAUDE.md  agents  business-patterns.paths.example  commands  examples
git-hooks  HARNESS-SYNC.md  hooks  install.sh  local  patterns
pipeline-prompts  pipeline-templates  rules  schemas  scripts
settings.json  settings.json.template  skills  sync.sh  templates  tests
```

**Limitation surfaced:** because the reference repo's git identity is not configured and this builder does not have authority to set it, the final `git commit` step is deferred to the user. This is a one-time per-machine setup the user does once. The reference setup is otherwise complete.

**Runtime verification:** file `<reference-project>/.claude/HARNESS-SYNC.md`

**Verdict:** PASS (setup complete; commit-to-remote deferred to user due to git-identity configuration boundary; documented as an explicit follow-up rather than a blocker)

**Follow-up backlog item required:** add P2 entry in `docs/backlog.md` — "User must commit + push `.claude/` setup in the chosen reference project to validate cloud `claude --remote` inheritance end-to-end. First real cloud-session build there is the integration test for Decision 011 Approach A per the decision record's Test Plan section."

---

## A.10 — Mirror all changes to `adapters/claude-code/`

**Date:** 2026-04-23
**Task ID:** A.10

**What was mirrored (per dispatch instructions: only the files this phase touched, NOT the pre-existing harness-mirror drift backlogged in plan #2):**

| File | Source | Destination | Diff verification |
|---|---|---|---|
| `rules/automation-modes.md` | `~/.claude/rules/automation-modes.md` | `adapters/claude-code/rules/automation-modes.md` | byte-identical |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | `adapters/claude-code/CLAUDE.md` | byte-identical |
| `docs/harness-architecture.md` | `~/.claude/docs/harness-architecture.md` | `docs/harness-architecture.md` (top-level neural-lace docs, not under adapters — that's the canonical location) | byte-identical |

**Diff loop output (per harness-maintenance.md):**
```
=== A.6 rules/automation-modes.md ===
(no output — byte-identical)
=== A.7 CLAUDE.md ===
(no output — byte-identical)
=== A.10 docs/harness-architecture.md ===
(no output — byte-identical)
=== ALL OK ===
```

**Pre-existing harness-mirror drift NOT addressed (intentionally, per dispatch scope):**
- `adapters/claude-code/rules/url-conventions.md` exists in adapter but the corresponding `~/.claude/rules/url-conventions.md` may be in a different state (this is the pre-existing P2 backlog item from plan #2 — out of scope here per dispatch instructions).
- Other potential drift in non-touched files is also out of scope per the explicit dispatch note: "your A.10 only needs to confirm sync of files YOU touched in A.6-A.9, not fix the pre-existing drift."

**Runtime verification:** file `adapters/claude-code/rules/automation-modes.md`

**Verdict:** PASS
