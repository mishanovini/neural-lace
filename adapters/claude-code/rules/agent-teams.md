# Agent Teams Integration

**Classification:** Hybrid (Pattern + Mechanism). The decision tree, Spawn-Before-Delegate procedure, and inbox-deferral guidance are Patterns the lead and teammate sessions self-apply. The enforcement substrate is Mechanism: the spawn validator (`hooks/teammate-spawn-validator.sh`), the team-aware tool-call budget (`hooks/tool-call-budget.sh`), the TaskCreated/TaskCompleted gates (`hooks/task-created-validator.sh`, `hooks/task-completed-evidence-gate.sh`), the flock-protected plan-edit validator (`hooks/plan-edit-validator.sh`), and the multi-worktree acceptance aggregator (`hooks/product-acceptance-gate.sh`) all fire mechanically once the feature flag is on. The flag itself (`enabled: true` in `~/.claude/local/agent-teams.config.json`) is the load-bearing toggle: with it off, none of the team-mode behaviors activate and the harness operates exactly as it did pre-integration.

**Ships with:** Decision 012 (`docs/decisions/012-agent-teams-integration.md`) — read it first for the six approved design decisions and their alternatives. The conflict analysis that drove this integration is at `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`.

---

## How to enable Agent Teams

Agent Teams is **disabled by default** because of unresolved upstream bugs (see "Upstream bugs you opt into" below). To turn it on, write the file at:

```
~/.claude/local/agent-teams.config.json
```

with the following content:

```json
{
  "version": 1,
  "enabled": true,
  "force_in_process": true,
  "worktree_mandatory_for_write": true,
  "per_team_budget": true
}
```

Then in your Claude Code launcher, set the environment variable Anthropic ships behind:

```
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

(Requires Claude Code v2.1.32 or later.)

### Field defaults

| Field | Default | What it controls |
|---|---|---|
| `version` | `1` | Schema version. Bump only when the schema changes shape. |
| `enabled` | `false` | Master switch. With `false`, the spawn validator rejects any `Agent` tool call carrying a `team_name` parameter and the harness behaves as a non-team installation. |
| `force_in_process` | `true` | When `true`, the spawn validator rejects pane-based teammate spawns. Pane-based teammates silently drop `SubagentStart`/`SubagentStop`/`TeammateIdle`/`TaskCompleted` at the parent process per #24175 — the parent never observes their lifecycle, so harness gates that depend on parent visibility don't fire for them. Override only for visual debugging or multi-monitor demos where you accept the lost enforcement. |
| `worktree_mandatory_for_write` | `true` | When `true`, the spawn validator rejects spawns of write-capable teammates (i.e. teammates that can call Edit/Write/MultiEdit/Bash) without `isolation: "worktree"`. Write-capable teammates without worktree isolation race on the filesystem; this is a structural defect, not a corner case. |
| `per_team_budget` | `true` | When `true`, `tool-call-budget.sh` derives `effective_session_id` from team membership (`~/.claude/teams/<team>/config.json`) and counts tool calls per team rather than per session. Solo sessions fall back to per-session counting automatically. |

### Schema and example

- Schema: `adapters/claude-code/schemas/agent-teams.config.schema.json` — JSON Schema for the file shape.
- Example: `adapters/claude-code/examples/agent-teams.config.example.json` — copy this to `~/.claude/local/agent-teams.config.json` and edit `enabled` to `true`.

### Upstream bugs you opt into

Enabling Agent Teams means accepting that the following five Anthropic-side defects are in your harness until Anthropic ships fixes. The harness mitigates each (workarounds below), but mitigation is not the same as repair. **Read this list before flipping the flag**:

- **anthropics/claude-code#50779 — Inbox messages to lead deferred until `stop_reason=end_turn`.** OPEN. Empirically broken on Opus 4.7. Teammate→lead messages do not reach the lead's context until the lead's tool loop ends. **Workaround:** don't design lead-side coordination that depends on the lead seeing teammate status mid-tool-loop. Batch coordination at TaskCreated/TaskCompleted boundaries. See "Inbox-deferral guidance" below.

- **anthropics/claude-code#24175 — Pane-based teammates drop `SubagentStart`/`SubagentStop`/`TeammateIdle`/`TaskCompleted` at the parent process.** Closed without fix. Source-level analysis confirms the parent process never observes these events for teammates running in tmux/iTerm2 panes. **Workaround:** the harness defaults `force_in_process: true` which rejects pane-based spawns at the validator. On Windows Git Bash there is no tmux so this is structurally enforced anyway. Override the default only when you accept the lost parent visibility.

- **anthropics/claude-code#43736 — `bypassPermissions` inheritance bug.** OPEN. Bypass mode toggled mid-session via shift+tab does NOT propagate to teammates spawned via the `Agent` tool with `run_in_background: true`. **Workaround:** when running with elevated permissions, set the `--dangerously-skip-permissions` CLI flag at launch instead of toggling mid-session. The CLI flag does propagate. The `force_in_process: true` default also makes this less acute since in-process teammates inherit the parent's settings at spawn time.

- **anthropics/claude-code#24073 / #24307 — Delegate Mode tool stripping.** Closed without fix. When the lead delegates a tool-use prompt to a teammate via `SendMessage`, the teammate's tools (including ToolSearch for deferred tools) are not fully initialized for the first turn. **Workaround:** the **Spawn-Before-Delegate Pattern** below — spawn teammates with minimal acknowledgment prompts, wait for idle, then send full task assignments via `SendMessage`. This forces a turn boundary that initializes the tool surface.

- **anthropics/claude-code#45329 — `teammate_name` and `team_name` not in `PreToolUse`/`PostToolUse`/`Stop` hook event input.** Closed as duplicate. Hooks firing in teammate context cannot see which named teammate issued the tool call from the event JSON alone. **Workaround:** the harness derives team membership at hook time by joining `session_id` against `~/.claude/teams/<team>/config.json` member lists. `tool-call-budget.sh` and `task-completed-evidence-gate.sh` both use this lookup pattern.

The five bugs above are the durable cost of the integration. The remaining bugs catalogued in the conflict analysis (account-switcher inflexibility, repo-shared `observed-errors.md`, etc.) are pre-existing harness drift, not Agent Teams problems, and are tracked separately in `docs/backlog.md`.

---

## When to use Agent Teams vs. orchestrator-pattern

The two patterns are NOT interchangeable. **Orchestrator-pattern**: main session dispatches sub-agent builders via the `Task` tool; one dispatch = one builder = one short return; battle-tested. **Agent Teams**: lead and teammates run as peers; teammates persist across `SendMessage` rounds; experimental with five known upstream bugs.

### Decision tree

1. **Does the work decompose into independent tasks the orchestrator can verify and route?** Yes → **orchestrator-pattern**.
2. **Do the agents need to exchange partial work or coordinate iteratively in real time, AND have you read and accepted the upstream bug list above?** Yes → **Agent Teams**.
3. **When in doubt → orchestrator-pattern.** It is the more battle-tested path; Agent Teams adds peer coordination at the cost of five unresolved upstream bugs.

The two modes coexist: an orchestrator-pattern lead can dispatch a builder that is itself an Agent Teams lead. Nested teams are NOT supported by Anthropic, so the inner lead must complete before the outer dispatch returns. See `rules/orchestrator-pattern.md` for the orchestrator alternative in detail.

---

## Spawn-Before-Delegate Pattern

**Origin:** community workaround for #24073 and #24307 — Delegate Mode tool stripping.

**The bug:** when a lead spawns a teammate via the `Agent` tool with a full task description in the prompt, the teammate's tools (especially deferred tools surfaced via ToolSearch) are not fully loaded for the first turn. The teammate may try to call a tool that "exists" but whose schema is not yet present in its context, producing `InputValidationError`.

**The workaround:** spawn the teammate with a minimal acknowledgment prompt, wait for it to go idle, THEN send the real task assignment via `SendMessage`. The intermediate turn boundary forces tool initialization.

### Procedure

1. **Spawn with an idle prompt.** Call the `Agent` tool with `subagent_type` and `team_name` set, plus a tiny prompt that asks the teammate to acknowledge readiness and stop:

   ```
   Agent(
     subagent_type="<your-builder-agent>",
     team_name="<your-team>",
     name="builder-1",
     prompt="Acknowledge with the single word 'ready' and stop. Do not call any tools."
   )
   ```

2. **Wait for idle.** The teammate will return after one turn. The lead's tool-loop continues. Note: per #50779 the teammate's `ready` reply will not appear in the lead's inbox until the lead's `stop_reason=end_turn`. This is fine — you do not need to read the reply for this pattern; you only need the teammate to have completed one turn.

3. **Send the real task via SendMessage.** Now the teammate's tool surface is fully initialized:

   ```
   SendMessage(
     to="builder-1",
     content="<full task description here, including plan reference, scope, acceptance criteria>"
   )
   ```

4. **The teammate processes the real task on its second turn**, with all tools (including ToolSearch-resolved deferred tools) available.

### Why the harness does not automate this

The pattern requires the lead to coordinate two distinct calls (`Agent` + `SendMessage`) per teammate. Automating it inside a hook is possible but adds indirection that obscures what the lead is doing. Current decision: document the pattern and let the lead apply it. A future skill may wrap the sequence if the upstream bug persists.

---

## In-process vs pane-based teammate mode

Agent Teams supports two teammate execution modes. The harness defaults to `in-process` and rejects `pane-based` unless the user explicitly overrides.

### The two modes

| Mode | What it is | Where the teammate runs | Hook firing |
|---|---|---|---|
| `in-process` (harness default) | The teammate's tool calls are interleaved into the lead's process. SubagentStart/Stop fire in the lead's process. | Same OS process as the lead. | All harness gates fire reliably from the lead's process. |
| `pane-based` (Anthropic default on macOS+tmux / Linux+tmux) | The teammate gets its own tmux pane (or iTerm2 pane). Its CLI is a child process, with its own settings.json load. | Separate child process, separate Claude Code CLI instance. | The teammate's PreToolUse / Stop hooks fire in the child process. SubagentStart/Stop do NOT fire reliably in the parent (#24175). |

### Why the harness defaults to `in-process`

Several harness gates depend on the parent process observing the teammate lifecycle (notably `pre-stop-verifier.sh` and SubagentStop-based verification). Pane-based teammates lose this visibility per #24175. In-process teammates get ALL gates firing reliably; pane-based teammates keep per-session enforcement (each pane has its own settings.json hooks) but lose parent-visibility events. The harness defaults to in-process to maximize reliability.

### When to override `force_in_process: false`

Override only for visual debugging (watching teammate output in a separate pane), multi-monitor demos, or research / exploration sessions where gate firing semantics don't matter. Do not override for production team work — the lost enforcement is silent (no error message says "this gate didn't fire because you went pane-based").

### Platform notes

- **Windows + Git Bash:** in-process forced (no tmux available). The `force_in_process: true` default is structurally redundant but asserts correct intent.
- **macOS + tmux / iTerm2, Linux + tmux:** pane-based is Anthropic's default. This is where #24175 bites hardest; the harness default rejects pane-based by design.
- **Cloud Linux (`claude --remote`):** in-process forced (single-VM session model). Pane-based is moot.

---

## Inbox-deferral guidance (#50779)

**The bug:** teammate-to-lead `SendMessage` calls are not surfaced in the lead's context until the lead's tool loop reaches `stop_reason=end_turn`. Empirically broken on Opus 4.7. The lead does not see teammate status mid-tool-loop.

**Implication for harness behavior:** any coordination pattern that depends on "lead checks teammate status, decides next move, takes action mid-loop" is broken. The lead's "decide next move" happens at turn boundaries, not within turns.

### Behavioral guidance for plan authors

- **Don't design lead-side polling loops that read teammate inbox messages.** They appear empty until the lead's turn ends, then arrive all at once.
- **Batch coordination at task boundaries.** Use `TaskCreated` / `TaskCompleted` events. These fire reliably and the harness already gates them via `task-created-validator.sh` and `task-completed-evidence-gate.sh`.
- **Use `TaskList` for status polling.** It reads team-shared state at any time and bypasses the inbox-deferral bug entirely.
- **Avoid mid-tool-loop "wait until teammate X reports done."** That is the exact pattern the bug breaks. If the lead must wait, end the turn and resume on next input or scheduled wake-up.

The orchestrator-pattern is structurally unaffected — it never relied on inbox messages (one dispatch = one return), which is part of why it remains the safer default.

---

## How the harness gates fire in team mode

Once `enabled: true`, the following hooks activate team-mode behavior. Each entry names the event matcher and what changes vs. solo mode.

| Hook | Event | Behavior in team mode |
|---|---|---|
| `hooks/teammate-spawn-validator.sh` | PreToolUse `Task\|Agent` | Rejects spawn when `enabled: false`, when `worktree_mandatory_for_write: true` AND the spawn lacks `isolation: "worktree"` AND the teammate has write-capable tools, or when the lead is in `--dangerously-skip-permissions` mode AND `force_in_process: true`. Allows spawn otherwise. |
| `hooks/task-created-validator.sh` | TaskCreated | Reads `task_subject` and `task_description`. Blocks task creation when the description doesn't reference an active plan file (regex `docs/plans/[a-z0-9-]+\.md`) or doesn't reference acceptance criteria / a `Done when:` clause. |
| `hooks/task-completed-evidence-gate.sh` | TaskCompleted | Two checks layered: (1) verifies an evidence block at `<plan>-evidence.md` references the same task ID; (2) consumes the deferred-audit flag at `~/.claude/state/audit-pending.<team>` if present — runs `plan-evidence-reviewer`, allows or blocks based on PASS/FAIL. |
| `hooks/tool-call-budget.sh` | PreToolUse `Edit\|Write\|Bash` | Resolves `effective_session_id` to `team_name` if the firing session is a team member (read from `~/.claude/teams/<team>/config.json`); else falls back to `CLAUDE_SESSION_ID`. At counter == 30 in team mode, sets the audit-pending flag instead of blocking. Hard ceiling at 90 per teammate sub-counter. |
| `hooks/plan-edit-validator.sh` | PreToolUse `Edit\|Write` | Wraps the evidence-mtime check in `flock` on `<plan>.lock` so two parallel verifiers serialize. 30s lock timeout protects against orphaned locks from crashed verifiers. |
| `hooks/product-acceptance-gate.sh` | Stop (position 4) | Enumerates current repo's worktrees via `git worktree list`. Aggregates `.claude/state/acceptance/<plan-slug>/` artifacts found in any worktree. A scenario PASS in any worktree's state dir satisfies the gate, provided `plan_commit_sha` matches. |

In solo mode (no team membership), every hook above falls back to pre-integration behavior. The integration is fully backward-compatible.

**Gates that fire identically regardless of team mode** (no team-awareness needed): `pre-commit-tdd-gate.sh`, `harness-hygiene-scan.sh`, `pre-push-scan.sh`, and inline PreToolUse Bash blockers (force-push, `--no-verify`, public-repo, dangerous-command pattern). These run at git operations or per-session against repo state.

**Gates partially degraded for pane-based teammates only** (the harness default rejects pane-based, but if the user overrides): `pre-stop-verifier.sh` fires in the teammate's pane not the lead's; `bug-persistence-gate.sh` attestation is per-pane; `narrate-and-wait-gate.sh` fires per teammate Stop. Keep `force_in_process: true` to avoid these tradeoffs.

---

## Cross-references

- `docs/decisions/012-agent-teams-integration.md` — the six approved design decisions and the alternatives rejected
- `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md` — original conflict analysis; integration plan resolves every HARD finding
- `rules/orchestrator-pattern.md` — more battle-tested multi-agent topology; default when in doubt
- `rules/automation-modes.md` — four-mode framework Agent Teams fits within (orthogonal to mode choice)
- `rules/acceptance-scenarios.md` — runtime acceptance gate; aggregates artifacts across worktrees in team mode
- `adapters/claude-code/schemas/agent-teams.config.schema.json` — JSON Schema for the config file
- `adapters/claude-code/examples/agent-teams.config.example.json` — copy-paste starting point
- Hooks (all six new or modified for this integration):
  - `adapters/claude-code/hooks/teammate-spawn-validator.sh` — new, PreToolUse Task|Agent
  - `adapters/claude-code/hooks/task-created-validator.sh` — new, TaskCreated
  - `adapters/claude-code/hooks/task-completed-evidence-gate.sh` — new, TaskCompleted
  - `adapters/claude-code/hooks/tool-call-budget.sh` — team-aware mode + deferred-audit cadence
  - `adapters/claude-code/hooks/plan-edit-validator.sh` — flock-based concurrent-write protection
  - `adapters/claude-code/hooks/product-acceptance-gate.sh` — multi-worktree artifact aggregation

## Scope

Applies only when `enabled: true` in `~/.claude/local/agent-teams.config.json` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set. With the flag off, the rule reduces to documentation. With the flag on, the workarounds above are the load-bearing safety story until Anthropic resolves the five named upstream bugs.
