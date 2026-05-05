# Decision 003: `review-before-deploy` as automation-mode default

**Date:** 2026-04-18
**Status:** Active
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

New automation-mode feature (Phase 6) lets users choose between `full-auto` (Claude executes multi-step plans without pausing) and `review-before-deploy` (Claude pauses before any command matching a configured deploy-class list: `git push`, `gh pr merge`, `supabase db push`, `vercel deploy`, `npm publish`, etc.). On a fresh install, one of the two must be the default until the user chooses.

## Decision

**Default is `review-before-deploy`.** Users opt IN to `full-auto` via:
- First-run SessionStart prompt (reply "2" or "full-auto")
- `/automation-mode full-auto` slash command
- Direct edit of `~/.claude/local/automation-mode.json`

Per-project overrides live at `<project>/.claude/automation-mode.json` and take precedence over the user-global default.

## Alternatives Considered

- **`full-auto` default** (matches current maintainer behavior) — rejected: this is a public-facing harness; the safe default should be the one that requires explicit opt-in to more autonomy, not more caution. A new user who installs and immediately runs `git push` should see a pause + explanation, not a surprise push.

## Consequences

- **Enables:** human-in-the-loop for irreversible operations by default; maintainer keeps existing workflow via one-line local config.
- **Costs:** the maintainer (and any user who prefers `full-auto`) must set the config once on a new machine; small first-run friction.
- **Blocks:** nothing material.

## Implementation reference

Phase 6 of `docs/plans/public-release-hardening.md`. Wire-up in `adapters/claude-code/hooks/automation-mode-gate.sh` + `adapters/claude-code/settings.json.template`.
