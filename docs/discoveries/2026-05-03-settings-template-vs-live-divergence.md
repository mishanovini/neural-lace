---
title: settings.json is gitignored; settings.json.template is committed source
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: phase-1d-c-1-low-risk-mechanisms.md T6 commit attempt
decision_needed: n/a — auto-applied
predicted_downstream:
  - future settings.json wiring tasks must update both files
  - install.sh's role in deriving live from template
  - hook-wiring task descriptions in plans
---

# settings.json is gitignored; settings.json.template is committed source

## What was discovered

The T4 builder of Phase 1d-C-1 wired the new hooks into `~/.claude/settings.json` (the gitignored copy). Inspecting the staged commit revealed `settings.json` was not tracked — the actually-committed source is `adapters/claude-code/settings.json.template`, which gets copied to live `settings.json` by `install.sh`. The hook wiring would have shipped to the local machine but not propagated to fresh installs of the harness.

The divergence is invisible without an explicit check: `git status` doesn't surface it because the live file is gitignored, and `git add settings.json` silently does nothing because of the ignore rule. A builder running locally sees the hook fire correctly and concludes the wiring is done.

## Why it matters

Hook wiring that lives only in the gitignored `~/.claude/settings.json` won't reach other installations of the harness. Anyone running `install.sh` against the repo gets the template-based settings without the new wiring. The harness's distribution model assumes the template is the authoritative source — a wiring task that touches only the live copy fails to ship.

## Options considered

- **(a) Commit `settings.json` directly.** Rejected — it contains machine-specific paths and personal preferences that drift across installs; that's why it's gitignored.
- **(b) Update template alongside live for every wiring task.** Chosen — keeps the template as the canonical source while preserving local customization in the gitignored copy.
- **(c) Auto-derive live from template via a sync hook.** Works in principle but adds tooling overhead and risks clobbering local customization. Deferred as a future enhancement.

## Recommendation

Option (b). The discipline cost is small (two-file edit per wiring task), and it preserves both the local-customization affordance and the canonical-template invariant.

## Decision

Option (b). Builders for hook-wiring tasks must update both `adapters/claude-code/settings.json.template` AND `~/.claude/settings.json`. Future tooling (option c) deferred.

## Implementation log

- `settings.json.template` wiring added in commit cc20cde alongside the live `settings.json` update.
- The pattern is now documented in plan task descriptions involving hook wiring (e.g., this plan's T5 explicitly names both files).
- Phase 1d-C-1's T6 commit caught the divergence retroactively; future plans encode the discipline upfront.
