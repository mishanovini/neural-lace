# Agent Teams ↔ Neural Lace Harness — Conflict Analysis

**Date:** 2026-04-27
**Author:** Claude (parallel research aggregation)
**Status:** Phase 1-3 complete. Phase 4 (implementation plan) blocked on user approval of remediation strategy.

## Source research files (Phase 1 evidence)

All four research streams are on disk under `docs/reviews/agent-teams-research-2026-04-27/`:

- `hooks-inventory.md` (43 KB) — 35 hooks + 4 git-hook dispatchers, with concurrency assessment
- `agents-skills-inventory.md` (30 KB) — 17 agents, 6 skills, 2 commands, 3 templates
- `rules-architecture-inventory.md` (33 KB) — principles, rules, automation modes, state directories, Decision 011 context
- `anthropic-docs-research.md` (20 KB) — Agent Teams official docs, hook event matrix, GitHub issue verdicts

This document is the synthesis. Specific evidence lives in the research files; this doc cites them by section name.

---

## Executive summary

**Is this integration feasible?** Yes, but it is a substantial body of work — at least 8 new mechanisms and 2 amended rules are required before Agent Teams can be enabled safely. The prior analysis was directionally right but factually wrong on multiple specifics.

**Hard blockers that prevent enabling Agent Teams today** (the harness must address these before the env flag is flipped):

1. **`tool-call-budget.sh` is per-`CLAUDE_SESSION_ID` and teammates have unique session_ids** (per [hooks-inventory.md → Notable concurrency risks #1] and [anthropic-docs-research.md → Open question 7]). 5 teammates × 30 calls = 150 cumulative tool calls before any audit is forced. The cumulative-build assumption of the budget gate is broken.

2. **Pane-based teammates (the macOS+tmux default) silently drop `SubagentStart`/`SubagentStop`/`TeammateIdle`/`TaskCompleted` at the parent process** (per #24175 source-level analysis, [anthropic-docs-research.md → Hook event semantics]). The harness's plan-integrity, acceptance-gate, and SubagentStop-based verification all assume parent visibility into teammate lifecycle. They get nothing on macOS+tmux.

3. **Inbox messages from teammates to the lead are deferred until `stop_reason=end_turn`** ([#50779 OPEN], broken on Opus 4.7). The orchestrator-pattern's "lead sees teammate status mid-tool-loop" expectation is broken on the current model.

4. **`teammate_name` and `team_name` are NOT in `PreToolUse`/`PostToolUse`/`Stop` from teammate sessions** (#45329). The harness has no documented way to attribute a teammate-issued tool call back to a specific named teammate. Workaround: join `session_id` against `~/.claude/teams/{team}/config.json`.

5. **Agent frontmatter `hooks:` is empirically NOT propagated to teammates** (#45329, plugin-equivalent rule). Any per-agent hook scoping the harness relies on does not work in teammate context.

**Soft blockers** (can ship behind feature flags or be deferred):

6. SessionStart account-switching hook is hardcoded `grep -q '<work-org-codename>'` against `$PWD`, not config-driven — drift from documented `dir_triggers` model. A teammate worktree under a different path silently switches to the personal account.

7. Templates `decision-log-entry.md` and `completion-report.md` exist only in `~/.claude/templates/`, not mirrored to `adapters/claude-code/templates/`. Teammates that inherit only project `.claude/` (per Decision 011 Approach A) won't see them.

8. `end-user-advocate` agent declares 28 `mcp__Claude_in_Chrome__*` and `mcp__Claude_Preview__*` tools on its `tools:` line. Teammates load MCP servers from project + user settings; tool *availability* depends on MCP provisioning in the teammate's environment.

**False alarms from the prior analysis** (refuted by research):

- "Existing agent definitions need audit because `skills:` and `mcpServers:` are stripped" — **REFUTED**. Zero agents in the current harness use either field (per [agents-skills-inventory.md → headline result]).
- "Pre-stop-verifier doesn't fire for teammate sessions" — **PARTIAL**. It DOES fire for in-process teammates (Stop converted to SubagentStop). It does NOT fire reliably for pane-based teammates due to #24175. Platform-dependent, not absolute.

**Newly discovered conflicts not in prior analysis:**

- Stop chain is **5 hooks**, not 4 (deferral-counter.sh added; rules/acceptance-scenarios.md is stale on this).
- **Several Gen-6 hooks are NOT WIRED** in settings.json (`goal-extraction-on-prompt.sh`, `goal-coverage-on-stop.sh`, `imperative-evidence-linker.sh`, `transcript-lie-detector.sh`, `vaporware-volume-gate.sh`, `automation-mode-gate.sh`). Pre-existing harness drift, separate from Agent Teams.
- `check-harness-sync.sh` does an unguarded auto-commit-and-sync to a shared repo — N teammates committing in parallel will race.
- `plan-edit-validator.sh`'s 120s mtime window does not prevent two parallel verifiers fabricating two evidence blocks within the window.
- `plan-lifecycle.sh` runs `git mv` on `.git/index` without lock coordination.
- `observed-errors.md` is repo-shared, so a teammate's recorded error satisfies another teammate's gate.
- Trust ledger mentioned in `principles/progressive-autonomy.md` is fully spec'd but **unimplemented** (no hook writes to it). Item #13 in the user's prompt is a non-issue today.

---

## Phase 1 — Inventory table

The full mechanism×event matrix is too large for inline rendering (35+ hooks × 7 events). The compact form below covers Mechanism | Event | Per-session/persistent | Conflict severity.

For full state-read/state-write/block-conditions detail, see `hooks-inventory.md` and `agents-skills-inventory.md`.

### Hooks (settings.json-wired only — 14 distinct hook callsites)

| Mechanism | Event / matcher | State scope | Conflict-with-Teams |
|---|---|---|---|
| Inline env-file blocker | PreToolUse Edit\|Write | none | none |
| Inline lock-file blocker | PreToolUse Edit\|Write | none | none |
| `plan-edit-validator.sh` | PreToolUse Edit\|Write | mtime window 120s, project plan files | **HARD** — parallel teammate verifiers race within window |
| `outcome-evidence-gate.sh` | PreToolUse Edit\|Write | per-project state | partial — fires per teammate session if hook propagates |
| `systems-design-gate.sh` | PreToolUse Edit\|Write | project plans | none — fires per session |
| `tool-call-budget.sh` | PreToolUse Edit\|Write\|Bash | `~/.claude/state/tool-call-count.<session>` | **HARD** — per-session counter, 5 teammates = 5 separate budgets |
| `no-test-skip-gate.sh` | PreToolUse Bash | none | none — fires per teammate |
| `observed-errors-gate.sh` | PreToolUse Bash | `.claude/state/observed-errors.md` (repo-shared) | partial — teammate's error satisfies another's gate |
| Inline dangerous-command pattern | PreToolUse Bash | none | none |
| Inline force-push / `--no-verify` block | PreToolUse Bash | none | none |
| Inline public-repo block | PreToolUse Bash | none | none — fires per teammate session |
| `check-harness-sync.sh` + `pre-commit-gate.sh` | PreToolUse Bash (`git commit`) | shared repo, runs `git commit` + `bash sync.sh` | **HARD** — concurrent teammate commits race |
| Inline GH account switcher | PreToolUse Bash (`git push`) | global gh auth state | partial — switches based on remote URL substring |
| `plan-deletion-protection.sh` | PreToolUse Bash | project plans | none |
| `post-tool-task-verifier-reminder.sh` | PostToolUse Edit\|Write | project plans | partial — reminder text in teammate session |
| `plan-lifecycle.sh` | PostToolUse Edit\|Write | git index, `git mv` | **HARD** — concurrent teammate plan edits race on `git mv` |
| Inline title-bar | UserPromptSubmit | terminal title only | none |
| Inline notification | Notification | none | none |
| `pre-stop-verifier.sh` | Stop | project plans, evidence | partial — per teammate session, but #24175 drops parent visibility for pane-based |
| `bug-persistence-gate.sh` | Stop | `.claude/state/bugs-attested-*.txt` | partial — per-session attestation |
| `narrate-and-wait-gate.sh` | Stop | session transcript | partial — fires per teammate Stop |
| `product-acceptance-gate.sh` | Stop | `.claude/state/acceptance/<slug>/...` | **HARD** — teammate writes to its own `.claude/state/`; lead's gate doesn't see it |
| `deferral-counter.sh` (Stop position 5) | Stop | per-session counter | partial |
| Compact-recovery prompt | SessionStart `compact` | SCRATCHPAD, backlog | partial — fires per pane-based teammate startup |
| Account switcher | SessionStart `*` | gh auth, supabase tokens | **HARD** — substring match on `$PWD`, fires for every pane-based teammate |
| Pipeline status check | SessionStart `*` | none | none |
| Harness sync drift check | SessionStart `*` | `~/.claude/` vs `claude-config` | partial — fires per teammate startup |
| `effort-policy-warn.sh` | SessionStart `*` | local config | partial — fires per teammate startup |

### Hooks NOT wired in settings.json (pre-existing harness drift, found by Agent A)

These exist in `adapters/claude-code/hooks/` but are not referenced by `settings.json`:

- `goal-extraction-on-prompt.sh`
- `goal-coverage-on-stop.sh`
- `imperative-evidence-linker.sh`
- `transcript-lie-detector.sh`
- `vaporware-volume-gate.sh`
- `automation-mode-gate.sh`
- `migration-claude-md-gate.sh`
- `review-finding-fix-gate.sh`
- `runtime-verification-executor.sh`, `runtime-verification-reviewer.sh`
- `pre-push-test-gate.sh`, `pre-push-pr-template.sh` (under `git-hooks/`)
- `harness-hygiene-scan.sh`, `pre-push-scan.sh` (these run via `core.hooksPath` git pre-push, not settings.json)
- `pre-commit-tdd-gate.sh` (runs inside `pre-commit-gate.sh`, not separately wired)

This is **not** an Agent Teams issue per se — it's pre-existing drift between documented enforcement and actual settings.json wiring. Surface to user separately as a P1 backlog item.

### Agents with hook-mandated lifecycle invocation

| Agent | Mandate | Hook backing |
|---|---|---|
| `task-verifier` | Only this agent flips plan checkboxes; mandatory before any `- [ ]` → `- [x]` | `plan-edit-validator.sh` (PreToolUse) — 120s evidence-mtime window |
| `plan-evidence-reviewer` | Mandatory at every 30-call budget firing | `tool-call-budget.sh --ack` |
| `enforcement-gap-analyzer` | Auto-invoked on every runtime acceptance FAIL | `product-acceptance-gate.sh` invokes (per docs; runtime-only) |

### Agents with pattern-mandated lifecycle invocation (not hook-backed)

`systems-designer`, `ux-designer`, `harness-reviewer`, `end-user-advocate` (plan-time mode), `code-reviewer`, `security-reviewer`, `claim-reviewer`.

---

## Phase 2 — Verdicts on prior claims

### Hard conflicts claimed

| Claim | Verdict | Evidence |
|---|---|---|
| `tool-call-budget.sh` is per-session, so 5×30 calls before gate fires | **CONFIRMED** | `hooks-inventory.md` documents the per-`CLAUDE_SESSION_ID` counter at `~/.claude/state/tool-call-count.<session>`. `anthropic-docs-research.md` open question #7 confirms each teammate gets a unique `session_id`. **Plus added concurrency risk:** the counter increment is unguarded `cat $f; echo $((+1)) > $f` per Agent A finding — even within a single session, parallel hook invocations race. |
| `pre-stop-verifier.sh` doesn't fire for teammate sessions | **PARTIAL** | Per docs ([anthropic-docs-research.md → Hook event semantics]): in-process teammates' `Stop` is automatically converted to `SubagentStop` and fires in lead's process. Pane-based teammates fire their own `Stop` in the pane child's process. Issue #24175 confirms `SubagentStart`/`SubagentStop` do NOT fire in parent for pane-based mode. So the prior claim is platform-dependent: fires for in-process, doesn't reliably reach parent for pane-based. |

### Partial conflicts claimed

| Claim | Verdict | Evidence |
|---|---|---|
| `plan-edit-validator.sh` only fires per-commit; teammate edits in worktrees may not trigger | **REFUTED ON TIMING** + **CONFIRMED ON RACE RISK** | The hook is PreToolUse Edit\|Write (settings.json:84-89), not per-commit. It DOES fire in teammate sessions (in-process: parent's hooks; pane-based: teammate's settings.json hooks). BUT Agent A flagged: the 120s mtime freshness window does not prevent two parallel verifiers fabricating two evidence blocks within the window — a real concurrent-write race. Net: claim was wrong about timing, right about effect. |
| `decisions-index-gate.sh` enforces atomicity per-commit, breaking when one teammate creates a decision and another implements it | **CONFIRMED** | The gate runs at PreToolUse Bash on `git commit`. It enforces same-commit staging of decision file + DECISIONS.md + plan-decisions-log entries. If teammate A commits the decision file and teammate B commits the implementation in a separate commit, the gate blocks B because the decision file isn't staged in B's commit. Teams must either commit jointly or the harness must teach the gate about cross-teammate decisions. |
| Automation-mode propagation: full-auto on lead = full-auto on all teammates | **CONFIRMED** but with addendum | Per docs: "Teammates start with the lead's permission settings." Plus #43736 OPEN: bypass mode set via shift+tab toggle does NOT propagate to teammates spawned via Agent tool with `run_in_background: true` — only `--dangerously-skip-permissions` CLI flag does. So the mode at spawn time CAN be a different mode than the lead's current mode if the lead toggled mid-session. **Plus separate issue:** `automation-mode-gate.sh` is NOT WIRED in settings.json (Agent A finding) — so it currently doesn't enforce anything regardless. |

### Composes-cleanly claims

| Claim | Verdict | Evidence |
|---|---|---|
| Pre-commit/pre-push credential scanners (global via `core.hooksPath`) | **CONFIRMED** | These run as git pre-commit/pre-push hooks, not Claude Code hooks. They fire on the actual `git push`/`git commit` regardless of which Claude Code session issued it. Teammate-agnostic by construction. |
| `harness-hygiene-scan.sh` | **PARTIAL** | Runs as pre-commit. Fires per commit, teammate-agnostic. **But** the scan loads `harness-denylist.txt` and Agent A flagged: parallel teammate commits = parallel hygiene scans loading the same file. Read-only loads, so probably safe, but the prior analysis didn't flag this. |
| `runtime-verification-executor.sh` | **PARTIAL** | Not wired in settings.json (Agent A finding). It's invoked indirectly by `pre-stop-verifier.sh`. Subject to all the parent-session-only firing semantics in #24175 — pane-based teammates' Stop fires in pane child, executor runs there, evidence is collected in the teammate's worktree if it has one. |
| Harness-review skill | **CONFIRMED** | Skills are user-invocable; no per-agent firing semantics. |
| Layer 0/1/2 architecture | **CONFIRMED** | Principles → Patterns → Adapter. Forward-compatibility doc explicitly accommodates new tool integrations under the adapter layer. |

### New mechanism needed claims

| Claim | Verdict | Evidence |
|---|---|---|
| Existing agent definitions need audit because `skills:` and `mcpServers:` are stripped | **REFUTED** | Per Agent B headline finding: zero agents/skills/commands use `skills:` or `mcpServers:` frontmatter. A literal `^skills:` and `^mcpServers:` grep across `adapters/claude-code/` returned no matches. The audit is unnecessary. **Real risk surface (newly identified):** `end-user-advocate.md` declares 28 MCP tool names inline on `tools:` line (the frontmatter survives, but tool *availability* depends on MCP provisioning in teammate environment); `plan-phase-builder.md` declares `tools: *`. These are different problems than the one the prior analysis named. |

---

## Phase 3 — New conflicts (the 18 items the user requested)

For each item, I report: what I checked, what I found (file:line evidence), severity, and recommended action.

### 1. State directories — session-scoped vs persistent vs cross-teammate visibility

**What I checked:** all `.claude/state/` and `~/.claude/state/` references across rules, principles, hooks, and architecture docs. See [`rules-architecture-inventory.md` Section 9] for the full table.

**Findings:**
- **All `<session-id>`-keyed state is per-session.** Teammates have unique `session_id`s (per #45329). Five teammates → five separate `~/.claude/state/tool-call-count.<sid>` files, five separate `.claude/state/user-goals/<sid>.json`, etc. Race risk is per-file (atomic-ish) but cumulative-counter assumptions are violated.
- **All `.claude/state/` lives inside the project working tree.** Pane-based teammate in a separate worktree → separate `.claude/state/` dir. Lead's Stop hooks read from cwd-relative `.claude/state/` and won't see teammate artifacts in another worktree.
- **Repo-shared persistent state** (`observed-errors.md`, `observed-errors-overrides.log`, `rejected-proposals.log`) is a different problem: any teammate's write satisfies any other teammate's read. False satisfaction risk for `observed-errors-gate.sh`.

**Severity:** HARD. Affects `tool-call-budget.sh`, `product-acceptance-gate.sh`, `bug-persistence-gate.sh`, `narrate-and-wait-gate.sh`, `goal-coverage-on-stop.sh` (if wired), `observed-errors-gate.sh`.

**Action:** new mechanism — a "team-scoped" state root keyed by `team_name` (read from `~/.claude/teams/<team>/config.json` at hook time) for cumulative gates. Per-session state stays per-session.

### 2. Account-aware switching

**What I checked:** SessionStart hook in `settings.json:273-279`. Compared to documented contract in `harness-architecture.md:81` and `examples/accounts.config.example.json`.

**Finding:** the deployed hook is hardcoded `grep -q '<work-org-codename>'` against `$PWD`. Not config-driven. A teammate's worktree under any path NOT containing the literal substring `<work-org-codename>` falls into the `else` branch (personal account). [`rules-architecture-inventory.md` Section 2 has the verbatim hook body.]

**Worktree teammate scenario:** if Anthropic's Agent Teams spawns a pane-based teammate in `<root>/.claude/worktrees/<branch>/` or any sibling path, the hook silently switches to the personal account. Push-time variant (`settings.json:178`) mirrors the bug for `git push`.

**Severity:** PARTIAL → HARD if teammates push to a work-org repo from a worktree without `<work-org-codename>` in the path.

**Action:** replace inline hook with config-driven `dir_triggers` lookup as documented in `harness-architecture.md`. Pre-existing harness drift, surfaced by this analysis but separate work item.

### 3. Public-repo block

**What I checked:** PreToolUse Bash hook at `settings.json:159` (inline regex on `gh repo create.*--public`).

**Finding:** the hook's regex matches the command string regardless of which session issued it. Teammate sessions fire their own PreToolUse Bash hook (per [`anthropic-docs-research.md` Hook event semantics]: in-process inherits parent settings; pane-based loads its own settings.json which contains the same hook). Either way, the block fires.

**Severity:** none.

**Action:** none.

### 4. `docs-freshness-gate.sh`

**What I checked:** the hook is NOT wired in `settings.json` (Agent A finding). The body exists at `adapters/claude-code/hooks/docs-freshness-gate.sh` but no settings.json callsite.

**Finding:** non-issue today. If wired in the future, would fire per pre-commit per teammate session.

**Severity:** none today; PARTIAL if wired later.

**Action:** flag as part of the "wired vs unwired" backlog item separately from Agent Teams.

### 5. Diagnostic-agent / fix-verifier loop

**What I checked:** how fix-verifier learns the original diagnosis when work crosses teammate boundaries.

**Finding:** there is no mechanism for cross-teammate state sharing other than `SendMessage`. Inbox messages are deferred until `stop_reason=end_turn` (#50779 OPEN, broken on Opus 4.7). The original diagnosis lives in the diagnosing agent's transcript; teammates don't see other teammates' transcripts.

**Severity:** PARTIAL. The current 5-step diagnostic loop assumes single-session continuity. Cross-teammate decomposition would lose the pre-fix-state context that fix-verifier compares against.

**Action:** if the diagnostic loop becomes a team task, the diagnosis must be persisted to `.claude/state/diagnoses/<id>.json` for the fix-verifier to read. New artifact convention.

### 6. UX validation agents — `.claude/audience.md` access

**What I checked:** `rules/testing.md` UX Validation section + the three UX agent definitions.

**Finding:** the agents read `.claude/audience.md` (project-relative). Teammates load project context per docs ("loads the same project context as a regular session: CLAUDE.md, MCP servers, and skills"). `.claude/audience.md` is read at agent-runtime via Read tool, not loaded as a settings file — so it works as long as the teammate's cwd is the project root.

**Caveat:** if teammate runs in a separate worktree, `.claude/audience.md` may not exist at that worktree's `.claude/` (depending on whether `.claude/` is symlinked or copied per Decision 011). Worktrees of the same project share the `.git/` but each has its own working files.

**Severity:** PARTIAL.

**Action:** UX agents should read `audience.md` via an absolute path resolution that walks upward from cwd, OR worktree-creation must include `.claude/audience.md` in the worktree.

### 7. Tool-call budget cross-team

**What I checked:** the per-`CLAUDE_SESSION_ID` counter at `~/.claude/state/tool-call-count.<session>`.

**Finding:** today's counter is per-session. With Agent Teams: per-teammate, since each has a unique session_id. With orchestrator-pattern + parallel local: per-Claude-Code-process, also separate. Two parallel teams running on the same machine would each have their own per-team counter.

**Tradeoff analysis:**

| Scope | Pros | Cons |
|---|---|---|
| Per-session (today) | Simple; isolates bursts to one session | Multiplies linearly with team size; no team-aggregate gate |
| Per-team | Caps cumulative team activity at 30 calls before audit | Requires `team_name` resolution at hook time; lead+teammate counters synchronized |
| Per-machine | Strongest cumulative cap | Cross-pollination across unrelated work; user complaints |
| Per-user | Aligns with daily quota mental model | Hardest to read at hook time without external state |

**Recommendation:** per-team counter (read `team_name` from `~/.claude/teams/<team>/config.json` keyed by `session_id` member lookup). Lead's session has `team_name` if it's leading a team. Teammates inherit team membership at spawn. If no team, fall back to per-session.

**Severity:** HARD. New mechanism required.

**Action:** extend `tool-call-budget.sh` with a `--team-aware` mode that reads `~/.claude/teams/*/config.json` to resolve current `session_id` to `team_name`. Counter file path becomes `~/.claude/state/tool-call-count.<team-or-session>`.

### 8. Scratchpad freshness warning

**What I checked:** the SessionStart `compact` matcher hook (settings.json:262-271).

**Finding:**
- In-process teammates: SessionStart does NOT fire in their context (#24175). Lead doesn't see staleness warning either if the lead's session doesn't restart.
- Pane-based teammates: each new pane-based teammate's CLI process fires SessionStart per #24175. Every teammate spawn shows the staleness warning. Noisy.

**Severity:** PARTIAL (UX only — informational warning, not gating).

**Action:** add a "skip if `agent_id` is set" guard to the compact-recovery hook so it only fires for the lead-equivalent context.

### 9. `Execution Mode` field in plan template

**What I checked:** plan template at `templates/plan-template.md:3` and rules/planning.md:51-59.

**Finding:** the field currently has only one documented value: `orchestrator`. Single-task plans don't declare it.

**For Agent Teams:** the natural addition is `Execution Mode: agent-team`. The orchestrator-pattern rule should then either:
(a) coexist (orchestrator dispatches to plan-phase-builder sub-agents; agent-team mode dispatches to teammates via TaskCreate), with separate sections in the rule, OR
(b) be replaced for agent-team plans (orchestrator becomes a fallback).

**Recommendation:** (a) — coexist. Agent Teams has limitations (no nested teams, lead is fixed for team lifetime, inbox-deferral bug) that make orchestrator-pattern still valuable for some workloads. Plan author chooses.

**Severity:** PARTIAL.

**Action:** new section in `rules/planning.md` and `rules/orchestrator-pattern.md` documenting when to use which mode. New optional value in plan-reviewer.sh's known-values list.

### 10. Evidence Log writes from teammates

**What I checked:** `task-verifier` agent's mandate ("only this agent flips checkboxes") + `plan-edit-validator.sh` 120s evidence-mtime gate.

**Finding:** `task-verifier` writes both an evidence block to `<plan>-evidence.md` and flips the `- [ ]` → `- [x]` in the plan file. If two teammates each invoke task-verifier in parallel:
- Each writes a separate evidence block (file is append-only per task-verifier's body).
- Both try to Edit the plan file. Plan-edit-validator sees evidence file mtime within 120s for both edits. Both pass the gate.
- Two checkbox flips race on the plan file's text (Edit tool's atomic-write behavior would mean second-write-wins or conflict).

**Path question:** if a teammate writes the evidence file, where does it land?
- In-process teammate: same cwd as lead → same plan + evidence file. Works (modulo the race above).
- Pane-based teammate in separate worktree: writes to its worktree's `<plan>-evidence.md`. Lead's view doesn't see it until merged.

**Severity:** HARD.

**Action:** new mechanism — `task-verifier` invocation must be serialized for the same plan. Options: (a) flock on `<plan>.lock` before evidence write; (b) only the lead invokes task-verifier (teammates BUILD; lead VERIFIES — mirrors orchestrator-pattern's build-in-parallel, verify-sequentially); (c) Anthropic-side fix that gives teammates ordered access to shared resources.

### 11. Hook output visibility (stderr surface)

**What I checked:** [`anthropic-docs-research.md` → Hook event semantics + Open questions] for hook stderr propagation.

**Finding:** hook stderr is surfaced to the firing session only. In-process: hook fires in lead's process, stderr goes to lead. Pane-based: hook fires in teammate's CLI process, stderr goes to that teammate's pane (and the user's terminal if attached). The user sees hook output for whichever pane they're attached to. No cross-process relay.

**Severity:** PARTIAL.

**Action:** important guidance for harness authors but no code change required. Document in `rules/automation-modes.md` (where the new agent-team mode would be added).

### 12. Concurrent harness-hygiene-scan

**What I checked:** `harness-hygiene-scan.sh` shared state.

**Finding:** Agent A's hooks-inventory documented:
- Loads `harness-denylist.txt` (read-only — safe to load in parallel)
- No flock; no shared lock file
- Writes nothing other than its own stderr

**Severity:** none. Read-only loads of a static file are safe in parallel.

**Action:** none.

### 13. Trust accumulation

**What I checked:** `principles/progressive-autonomy.md`, `patterns/risk-profiles/trust-ledger.schema.json`, search for any hook that writes the trust ledger.

**Finding (per [`rules-architecture-inventory.md` Section 1]):** **the trust ledger is fully spec'd but unimplemented.** No code in the harness writes a `trust-ledger.json`. The schema exists, the spec exists, but no enforcement exists today.

**Severity:** none today. PARTIAL if/when implementation lands AND Agent Teams ships.

**Action:** when trust-ledger implementation is pursued (separate work item), the design must consider per-team / per-teammate accounting. Specifically: the schema's `projects.<name>.tool_trust{}` field would need a `teammate.<name>.tool_trust{}` extension. Extend forward-compatibility doc to call this out.

### 14. The `--no-verify` block

**What I checked:** PreToolUse Bash inline hook at `settings.json:150`.

**Finding:** the hook regex matches the command string. Teammate-issued git commands fire teammate-side PreToolUse Bash. The block fires regardless of which session issued the command.

**Severity:** none.

**Action:** none.

### 15. Permissions inheritance edge case

**What I checked:** `automation-mode-gate.sh` + Decision 011 + `~/.claude/local/automation.config.json`.

**Finding:** `automation-mode-gate.sh` is NOT WIRED in `settings.json` (Agent A finding). It currently doesn't enforce anything. Pre-existing drift, not Agent Teams-specific.

**For the documented contract** (if wired): the hook reads `~/.claude/local/automation.config.json`. Per docs ([`anthropic-docs-research.md`] - in-process teammates inherit parent's loaded state; pane-based teammates load their own from `~/.claude/local/`). If the lead is in `review-before-deploy` mode but the teammate's pane-based CLI process loads a stale or different `automation.config.json` (e.g., it was edited mid-session), the modes diverge.

**Severity:** PARTIAL today (gate not wired); becomes HARD if wired with Agent Teams enabled.

**Action:** if `automation-mode-gate.sh` is ever wired, it must read team-membership from `~/.claude/teams/<team>/config.json` and propagate the team's mode to all teammates.

### 16. Hook recursion

**What I checked:** whether teammate-issued tools that invoke `claude -p` could create nested teammate sessions.

**Finding:** docs explicit: **"No nested teams: teammates cannot spawn their own teams or teammates."** Structurally limited at one level deep.

A teammate CAN invoke `claude -p` (interactive Claude in a subprocess) without it being a teammate spawn. That subprocess is a regular Claude Code session, not a teammate. Hooks fire per its own context.

**Severity:** none.

**Action:** none.

### 17. TaskCreated and TaskCompleted hooks

**What I checked:** [`anthropic-docs-research.md` → Hook event semantics].

**Finding:** these are real, supported, agent-team-aware hooks. They include `teammate_name`/`team_name`. Exit-2 rolls back; JSON `{"continue": false, "stopReason": "..."}` stops the teammate.

**Use case for harness:**

- **TaskCreated** could enforce: "every TaskCreate must reference a plan + acceptance criteria + scope." This is a BETTER mechanism than per-Edit plan-edit-validator for team-level enforcement, because it fires at the lead's `TaskCreate` call before any teammate starts work.

- **TaskCompleted** could enforce: "before a task is completed, evidence file must exist for the corresponding plan task." Replaces per-checkbox-edit gating with per-team-task-completion gating.

**Severity:** new opportunity, not a conflict.

**Action:** new hooks `task-created-validator.sh` and `task-completed-evidence-gate.sh`. Possibly REPLACES some per-Edit hooks in agent-team plans (with a feature flag for rollout).

### 18. Hook performance budget

**What I checked:** the cost of every Neural Lace hook firing per teammate per tool call.

**Estimation (qualitative):**
- PreToolUse hook chain on Edit: 5 hooks (env-blocker, lock-blocker, plan-edit-validator, outcome-evidence-gate, systems-design-gate). Each spawns bash + reads files. ~50-200ms each.
- PreToolUse hook chain on Bash: 8 hooks. Similar cost.
- PostToolUse Edit: 2 hooks.
- Stop: 5 hooks. ~500ms-2s aggregate (some run sub-tools like `find-plan-file.sh`, parse evidence, etc.).

**Per-teammate latency:**
- 5 teammates × 30 edits/teammate = 150 PreToolUse Edit firings × ~5 hooks × ~100ms = ~75 seconds of cumulative hook time across the team's edit phase. Spread across 5 parallel processes.
- The wall-clock impact per-teammate is unchanged (each teammate's hooks fire serially in its own process). But on macOS+tmux pane-based mode, every teammate is its own bash subprocess fork — overhead multiplies.
- On Windows (in-process forced), the parent process queues hook executions for all teammates. Lead's perceived responsiveness degrades.

**Recommendation:**
- Audit each hook for early-exit on irrelevant tool inputs (don't run plan-edit-validator on edits that don't touch a plan file). Some already do this; need to verify all.
- Mark hooks that should be lead-only via a new convention (read `agent_id` from stdin and skip if set). Examples: SessionStart compact-recovery prompt, harness-sync drift check.
- Mark hooks that should be team-aggregate (run only once per team-task lifecycle, not per teammate edit). Use TaskCreated/TaskCompleted as the trigger surface.

**Severity:** PARTIAL (UX latency, not correctness).

**Action:** add agent-id-aware early-exit to user-facing hooks in a separate task.

---

## Phase 4 — Implementation strategy outline

(Detailed plan will be written next, following user's requested template.)

**Required new mechanisms:**

1. `team-scoped-tool-call-budget.sh` — extend `tool-call-budget.sh` with team-aggregate counter.
2. `task-created-validator.sh` — TaskCreated hook enforcing plan-reference + acceptance-criteria.
3. `task-completed-evidence-gate.sh` — TaskCompleted hook enforcing evidence-block existence.
4. `teammate-spawn-validator.sh` — a PreToolUse hook on `Agent` (formerly `Task`) tool that rejects spawn when (a) write-capable role lacks `isolation: "worktree"`, (b) lead is in `--dangerously-skip-permissions` mode (warn or block).
5. Plan-file lock convention for parallel teammate task-verifier invocations (flock on `<plan>.lock` or serialize verification on lead).
6. Account-switching hook fix (config-driven, not hardcoded) — pre-existing drift, but Agent Teams makes it acute.
7. Templates parity: copy `decision-log-entry.md` and `completion-report.md` from `~/.claude/templates/` to `adapters/claude-code/templates/` (Decision 011 Approach A consequence).
8. New plan field `Execution Mode: agent-team` + section in rules/planning.md + rules/orchestrator-pattern.md documenting tradeoffs and dispatch contract.

**Required rule amendments:**

A. `rules/automation-modes.md` — add 5th mode (or sub-mode) "Agent Teams" with the harness-loading semantics.
B. `rules/orchestrator-pattern.md` — update "Pairing modes" + new section "Agent Teams vs orchestrator-pattern: when to use which."

**Documentation required:**

- Decision record `docs/decisions/012-agent-teams-integration.md` per the decisions-index-gate rule.
- Update `docs/harness-architecture.md` with new hooks + mode.
- Update `README.md` status table.

**Items deferred to backlog (not part of this integration):**

- Wire the unwired hooks (`goal-extraction-on-prompt.sh`, `automation-mode-gate.sh`, etc.) — pre-existing drift. P1 backlog item.
- Trust-ledger implementation — deferred until after team integration.
- Account-switching hook fix may ride along since Agent Teams forces the issue.

**Items where Anthropic-side fixes are required (cannot resolve harness-side):**

- #50779 Inbox messages deferred until `stop_reason=end_turn` (Opus 4.7 regression). **Workaround:** harness assumes lead receives messages only at end-of-turn; orchestrator-pattern deprecation warning when team mode is selected.
- #24073/#24307 Delegate Mode tool stripping bug. **Workaround:** Spawn-Before-Delegate Pattern documented as the only safe spawn order.
- #45329 `teammate_name` in PreToolUse/PostToolUse/Stop. **Workaround:** join `session_id` to `~/.claude/teams/<team>/config.json` members.
- #24175 Pane-based teammates drop SubagentStart/Stop/TeammateIdle/TaskCompleted at parent. **Workaround:** require `teammateMode: "in-process"` in settings.json or accept that some hook-driven gates only work for in-process teammates.

**Recommendation:** if any of those Anthropic-side issues remains open at integration time, gate Agent Teams support behind an explicit `enabled_unsafe: true` flag in `~/.claude/local/agent-teams.config.json` until upstream fixes ship.

---

## Open questions that need user decision before Phase 4 plan can be finalized

These are NOT items where docs are silent — these are items where the user must pick a direction.

1. **Per-team vs per-machine vs per-user tool-call budget scope.** Recommended per-team (item #7 above). Confirm.

2. **In-process teammates only, or accept pane-based for macOS+tmux?** In-process gives reliable hook firing but caps parallelism at one process. Pane-based scales but loses SubagentStart/Stop/TeammateIdle/TaskCompleted at the parent. Recommended: force in-process via `teammateMode: "in-process"` in adapters/claude-code/settings.json default until Anthropic fixes #24175.

3. **Worktree-mandatory for write-capable teammates?** Reduces filesystem races but adds setup complexity per spawn. Recommended yes, enforced by `teammate-spawn-validator.sh`.

4. **TaskCreated/TaskCompleted as new enforcement surface?** Adds capability but increases harness surface area. Recommended yes — better than per-Edit gating for team-aggregate concerns.

5. **Acceptance loop integration with team mode.** Should each teammate's work require its own scenario PASS at runtime, or does the lead's runtime advocate cover the whole team? Recommended: lead's runtime advocate covers the team-level outcome; per-teammate tasks are validated by lead-invoked task-verifier.

6. **Whether to ship Agent Teams support behind a feature flag.** Recommended yes (`agent_teams.enabled` in `~/.claude/local/agent-teams.config.json`) until #50779 and #24175 are resolved upstream.

These six questions are listed in the user's prompt's Phase 4 requirement (decisions log + acceptance criteria). The implementation plan cannot be scoped without resolving them.
