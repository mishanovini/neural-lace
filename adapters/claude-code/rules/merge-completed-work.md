# Merge completed work — standing rule

**Classification:** Pattern (self-applied session discipline). No hook currently blocks "session ended with an open PR." A future PostToolUse hook on `gh pr create` is proposed at `docs/designs/auto-merge-on-green-hook.md` (neural-lace) to mechanize tracking; until that ships, this rule is enforced by agent discipline + the dispatch-session-monitor scheduled task's stale-PR sweep.

Every session that opens a PR MUST merge it before reporting DONE, unless:
- The PR touches product code that requires explicit user review (feature changes, migrations, API changes)
- The PR has failing CI checks
- The PR has merge conflicts that need resolution

For these PR classes, merge automatically when CI passes — do NOT leave them sitting:
- Documentation (docs/, README, CHANGELOG)
- Audit findings and reports
- Plan files and status flips
- Config changes (.github/workflows/, .eslintrc, etc.)
- Test-only changes
- Dependency bumps (Dependabot PRs with passing CI)
- Cleanup (branch deletion, stale-file removal)

For product-code PRs:
- Track the PR until merged — don't report DONE until it's on master
- If CI passes and the change is safe (no user-facing behavior change), merge it
- If the change IS user-facing, flag it for Misha's review but still track until merged
- Never leave a green PR sitting for more than 1 hour without action

The pattern of "open PR → move on → forget" is the single biggest source of drift in this system. This rule exists to make that pattern impossible.

## Cross-references

- `~/.claude/rules/deploy-to-production.md` — the default-to-deploy discipline this rule extends to the merge boundary (deploy follows merge; merge is the previously-missing step).
- `~/.claude/rules/git.md` "Auto-merge feature branches" — the per-session merge-on-verified discipline; this rule extends it to a standing cross-session rule covering the "PR opened, session ended, PR forgotten" failure mode.
- `~/.claude/rules/session-end-protocol.md` — DONE/PAUSING/BLOCKED markers; a DONE marker on a session that left a green PR unmerged is dishonest under this rule.
- `<scheduled-tasks-dir>/dispatch-session-monitor/SKILL.md` (per-machine scheduled-task location; typically under the user's cloud-sync Documents folder) — the scheduled task that sweeps stale PRs every 10 min and merges safe-class PRs automatically; the cross-session enforcement substrate for this rule.
- `docs/designs/auto-merge-on-green-hook.md` (neural-lace) — proposed future Mechanism (PostToolUse hook + tracking file + companion poller) that would make this rule structurally enforced rather than discipline-enforced.

## Scope

Applies to every Claude Code session in every project. The rule binds the session that OPENED the PR, not the session that built the work — those are typically the same session, but when they differ (e.g., builder opens PR, orchestrator merges), the orchestrator inherits the obligation. Cross-machine: the dispatch-session-monitor scheduled task runs on one machine and sweeps stale PRs across all repos the configured GitHub account can see, so PRs opened from any machine are eventually picked up by the monitor's sweep.
