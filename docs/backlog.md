# Neural Lace — Harness Backlog

Last updated: 2026-04-22

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

Strategy context and reasoning for many entries below lives in [`docs/claude-code-quality-strategy.md`](./claude-code-quality-strategy.md).

## Known gaps in current enforcement (from strategy doc, 2026-04-22)

These are residual risks in the Gen 4+ harness. Each is documented honestly rather than left hidden.

### P1 — Verbal vaporware in conversation is not mechanically blocked

Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. When the agent makes a feature claim in conversation without citing file:line, no mechanism catches it. Current mitigation: user reflex to ask for citations. Closing requires either a PostMessage hook in Claude Code itself or an adversarial post-response review agent that fires on every Nth response.

### P1 — Tool-call-budget `--ack` attestation is bypassable

The `tool-call-budget.sh` hook looks for sentinel lines in `~/.claude/state/reviews/`. A builder agent could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed. Closing requires either per-session HMAC signing or architectural support for observing Task tool invocations.

### P1 — Concurrent-session state collisions (plan-wipe incidents)

Multiple Claude Code sessions on the same machine share `~/.claude/` state and the git working tree. Uncommitted plan files have been lost to concurrent-session `git stash`/`clean` operations on multiple documented occasions (2026-04-19, 2026-04-20). A project-level plan addressing commit-on-creation is in flight, but cross-session state coordination (shared `~/.claude/` directory) is still unresolved.

### P1 — Harness portability to `claude --remote` cloud sessions

Cloud-hosted Claude Code sessions don't inherit the user's local `~/.claude/` configuration. Isolation wins (no collision) but enforcement loses (no hooks). Need to establish dotfiles-sync pattern or equivalent so cloud sessions inherit the same harness rules as local sessions.

## Improvements surfaced by 2026-04-22 strategy review

Prioritized order of leverage. Full reasoning in `docs/claude-code-quality-strategy.md` section "Additional Suggestions for Improvement."

### P0 — Adopt `claude --remote` + dotfiles sync as official background-work pattern

Directly resolves the concurrent-session plan-wipe incidents we've hit twice. Document the canonical pattern in a new `rules/automation-modes.md`: interactive work → local Claude Code; autonomous background work → `claude --remote` with dotfiles-synced harness; recurring work → `/schedule`. Requires verifying harness-portability mechanics in the cloud session first.

### P0 — Harness-tests-itself: synthetic session runner

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them (unauthorized checkbox flip, mocked integration test, uncited feature claim, budget exhaustion without audit). Runs on demand or weekly via `/schedule`. Produces a report showing which enforcement mechanisms have regressed. This catches silent enforcement regressions — currently invisible.

### P1 — Adversarial pre-mortem pattern for plans

Before any plan is marked ready to build, an adversarial agent answers "if the builder's only input is this plan, what will they get wrong?" Produces a list of expected failure modes. Plan is revised to close each. This is "verbose plans" with teeth — catches gaps humans approve as "looks plausible."

### P1 — Capture-codify cycle at PR level

Every fix PR requires a description field: "What rule/hook/agent would have caught this?" Empty = PR blocked. If a mechanism exists → link to it (confirms enforcement works); if none → propose one, or explicitly accept residual risk. Makes the capture-codify discipline structurally mandatory.

### P1 — Prompt template library for meta-questions

Codify canonical meta-questions as slash commands or skills: `/why-did-this-bug-slip`, `/find-my-bugs`, `/make-this-plan-verbose`, `/harness-this-lesson`. Currently these patterns live in individual memory; codifying makes them reusable and consistent.

### P1 — Delegability classification on plan tasks

Every plan task declares: fully-delegable / review-at-phase / interactive. Shapes dispatch automatically — fully-delegable auto-dispatches to background sessions, review-at-phase produces PRs at phase boundaries, interactive stays in foreground. Replaces per-task manual routing decisions.

### P1 — Explicit interactive vs autonomous session mode

Session-start directive declaring interactive (human watching; more permissive) or autonomous (human not watching; stricter gates, auto-commit plans, harder enforcement). Same cadence shouldn't apply to both modes.

### P2 — Effort-level enforcement at project level

`.claude/minimum-effort.json` in project root declares minimum effort level. SessionStart hook warns if effort is below project minimum. Eliminates "forgot to set max" errors on quality-critical projects.

### P2 — Multi-model routing strategy

Codify model assignment per task type: Opus for planning/adversarial review/judgment; Sonnet for implementation; Haiku for mechanical operations. Partially done via individual agent frontmatter; could be more systematic via a central routing config.

### P2 — Scheduled retrospectives via `/schedule`

Weekly scheduled agent that reads the week's completed plans, decisions, and failure-mode entries; proposes harness improvements based on patterns; drafts `docs/retrospectives/YYYY-WW.md`. Turns ad-hoc "half my time on the harness" into systematic weekly attention.

### P2 — Session observability dashboard

Lightweight `claude-status` command aggregating active sessions (local + `--remote`), active plans, tool-call budget consumption, recent hook firings, uncommitted work at risk of wipe. Aggregates existing state files — no new infrastructure needed.

### P2 — Harness version contracts

Each project declares `harness-version: >=N` in its CLAUDE.md. Breaking harness changes bump the version. SessionStart warns if project version predates current harness. Prevents silent regressions as harness evolves beyond what older projects expected.

### P0 — Plan file deletion protection

Plan files should NEVER be deleted. The only legitimate operation on a plan file after creation is move-to-archive on terminal-status transition. Current state: nothing mechanically prevents deletion, and we have lost plan files multiple times (NEPQ, robust-plan-file-lifecycle) to `git stash -u` / `git clean -fd` operations from concurrent sessions.

Needed: a PreToolUse Bash hook that blocks destructive commands targeting plan files. Patterns to block:
- `rm` or `rm -rf` targeting `docs/plans/` or any path containing `/plans/`
- `git clean` in a working tree with uncommitted files under `docs/plans/`
- `git stash -u` / `git stash --include-untracked` when plan files are untracked (warn, optionally block)
- `git checkout .` / `git restore .` / `git reset --hard` that would discard uncommitted plan files

The hook should be conservative — if uncertain whether the command affects plan files, warn and require explicit confirmation rather than block outright. Block only when detection is high-confidence.

Companion work (in `robust-plan-file-lifecycle` plan): the commit-on-creation protection prevents plans from ever being uncommitted for long, which eliminates most wipe scenarios. Plan-deletion-protection is a defense-in-depth layer catching the residual cases.

Priority P0 because: this is a recurring, observed pain point. The mechanism needed is small (single hook). The blast radius of missing protection is high (days of planning work lost).

### P1 — Mysterious `effortLevel` wipe during session (2026-04-22/23)

Observed: `~/.claude/settings.json` started the session with `effortLevel: "max"`. Partway through, a subsequent `jq -r '.effortLevel'` returned `null` (key removed or value nulled). No task in the executing plan intentionally touched this field. Neither the main session nor any dispatched builder agent reported editing it.

Plausible causes:
- A PreToolUse or PostToolUse hook silently normalizing settings.json (e.g., a JSON rewriter that drops unknown keys)
- A concurrent session on the same machine overwriting settings.json with an older version (the concurrent-session state collision pattern we already have logged)
- An `install.sh` re-run during the session restoring from a template that had the key but was processed incorrectly
- A tool call with a full-file Write to settings.json that didn't preserve the effortLevel field

Remediation needed:
- Audit every hook that reads/writes `~/.claude/settings.json` for normalization that could drop top-level keys
- Consider adding a SessionStart hook that snapshots `settings.json` to `~/.claude/state/settings-snapshot.json` and, on next SessionStart, diffs against the current file to surface silent mutations
- Document the root cause once identified, then add a test/guard

Until fixed: users should periodically check `jq -r '.effortLevel' ~/.claude/settings.json` is not `null`. The existing `effort-policy-warn.sh` hook catches this indirectly (will warn if env var is unset and settings is missing the key AND policy requires non-low).

### P1 — Harness-work plans have no tracked home

Per `harness-hygiene.md`, the harness repo adds `docs/plans/` to `.gitignore` (harness repos don't ship instance artifacts). But harness-dev work DOES produce plan files, and those plans have no naturally-tracked home:

- `neural-lace/docs/plans/` — gitignored; plans there survive locally but aren't protected from `git clean`
- `~/.claude/plans/` — outside any git repo; plans there survive git operations anywhere but aren't version-controlled or shareable

Encountered 2026-04-22: wrote `harness-quick-wins-2026-04-22.md` to `neural-lace/docs/plans/`, hit the `.gitignore` at commit time, moved to `~/.claude/plans/` which is outside any repo.

Options to resolve:
- **Separate harness-dev repo:** e.g., `neural-lace-dev` or similar, tracking only the working plans/decisions/sessions for harness evolution. Isolates instance artifacts from shareable harness code.
- **Carve-out within neural-lace:** a `docs/internal-plans/` (not gitignored) specifically for harness-dev plans. Weakens the hygiene guarantee (contributors may leak identifiers), requires reviewer vigilance.
- **Accept `~/.claude/plans/`:** formalize this as THE location for harness-dev plans. Add a README there explaining the convention. Plans are local-only by design; cross-machine collaboration requires explicit git init + separate repo setup by the contributor.

Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice. Options 1-2 are correct for a growing contributor base.

### P2 — Bug-persistence gate should recognize cross-repo persistence

The `bug-persistence-gate.sh` hook scopes its check to the current project's `docs/backlog.md` or `docs/reviews/`. When trigger phrases reference harness-level concerns and persistence legitimately happens in the neural-lace repo, the hook still fires against the project cwd.

Two possible fixes:
- **Harness-aware scoping:** check both the current project's `docs/` AND `~/claude-projects/neural-lace/docs/backlog.md` when trigger phrases reference harness concerns (would require classifying trigger phrases as project-level vs harness-level)
- **Cross-repo persistence attestation:** explicit sentinel file (e.g., `.claude/state/persisted-elsewhere-<hash>.txt`) carrying the commit SHA of the cross-repo persistence; similar to the existing `--ack` pattern

Workaround pattern (used 2026-04-22): write a dated review file in the current project's `docs/reviews/` that points at the authoritative persistence location. Works but requires the agent to remember to do it.

## Existing entries

## ✅ DELIVERED 2026-04-20 — Mechanical enforcement of bug-persistence rule

Shipped in commit `0090d4b`: `hooks/bug-persistence-gate.sh` Stop hook wired into `settings.json.template`. Scans session transcript for trigger phrases, checks `docs/backlog.md` + `docs/reviews/` for persistence, blocks session end if bugs mentioned without being recorded. Attestation escape hatch via `.claude/state/bugs-attested-*.txt`. Documented in `docs/harness-architecture.md`.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure

## P0 — Stop hook for "narrate-and-wait" pattern (new 2026-04-21)

Counterpart to bug-persistence-gate: catch the pattern where the agent
completes a unit of work, narrates a summary, and implicitly stops
waiting for user confirmation. Specifically blocks session termination
when the last N assistant turns contain trigger phrases like "next up
is", "ready to continue", "want me to proceed", "after merge", "then
I'll" — indicating the agent has queued up work it could be doing now
but is pausing to announce.

Scope ~3 hrs: Stop hook script, transcript regex, allowlist for genuine
end-of-session summaries (e.g., "done for tonight", explicit /clear
requests, explicit "stop" from user).

This was added after the maintainer repeatedly observed the agent
stopping mid-execution on 2026-04-21 and asking rhetorical "are you
still working?" questions.
