# Local-edit Authorization (Stub — enforcement is in the hook)

**Rule:** Edit/Write/MultiEdit operations on files under `~/.claude/local/**` require a fresh per-file authorization marker authored by `/grant-local-edit <filename>` within the last 30 minutes. The default is to BLOCK — the marker is the in-band escape hatch.

**Classification:** Mechanism. This file is intentionally short. The marker format, freshness window, slug derivation, and trigger logic are all enforced by `hooks/local-edit-gate.sh`. If a constraint described below isn't backed by the hook, it's theater.

## Why this rule exists

`~/.claude/local/` holds machine-local config: account mappings, credentials, project routing, automation preferences, and machine-local CLAUDE.md notes. Some files (`accounts.config.json`, `personal.config.json`) are credential-bearing; agents drifting them silently is the failure mode the default-block protects against. Other files (`automation-mode.json`, `CLAUDE.md`) are routinely-edited preferences where agent assistance saves friction.

The gate is the same shape as `bug-persistence-gate` (waiver markers), `dag-review-waiver-gate` (per-session approval), `tool-call-budget` (audit-pending flag): default-block + session-scoped escape hatch authored by user intent. It replaces the prior six-line `permissions.deny` for `~/.claude/local/**` patterns with a more nuanced gate that allows authorized edits while preserving the protection.

## Enforcement map (hook-backed)

| Constraint | Hook / agent that enforces it | File |
|---|---|---|
| Edit/Write/MultiEdit on `~/.claude/local/**` requires fresh marker | `local-edit-gate.sh` PreToolUse | `~/.claude/hooks/local-edit-gate.sh` |
| Marker must be authored by `/grant-local-edit <filename>` | `grant-local-edit` skill writes marker; hook reads it | `~/.claude/skills/grant-local-edit.md` |
| Marker must match target's filename-slug | same hook (slug derivation: lowercase, dots/spaces → dashes, non-alphanumerics stripped) | same |
| Marker must be mtime within 30 minutes | same hook | same |
| Tool != Edit/Write/MultiEdit → silent allow | same hook | same |
| Target outside `~/.claude/local/` → silent allow | same hook | same |
| Malformed input (missing file_path) → fail closed | same hook | same |

## Cross-references

- `rules/diagnosis.md` — broader exhaustive-diagnosis discipline; this rule operationalizes the "default-block + authorized-escape" pattern for the local-edit case.
- `hooks/local-edit-gate.sh` — the gate; format spec lives in the hook header comment + self-tests.
- `skills/grant-local-edit.md` — the marker authoring surface.
- `docs/decisions/029-local-edit-authorization-mechanism.md` — design rationale and rejected alternatives.
- `rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- Sibling fresh-marker gates: `hooks/bug-persistence-gate.sh`, `hooks/dag-review-waiver-gate.sh`, `hooks/tool-call-budget.sh`.

## Scope

This rule applies in any project whose Claude Code installation has `local-edit-gate.sh` wired in `settings.json`. The gate fires from any session (project-rooted or harness-rooted) because `~/.claude/local/` is itself per-machine, not per-project. There is no opt-in or opt-out at the project level — the home-dir gate is the perimeter.
