# Observed Errors First — compact
> Enforcement: observed-errors-gate.sh (PreToolUse Bash blocker on `git commit`).
> Applies: any fix-class commit.

- Before a fix-class commit lands, the verbatim error you observed at runtime must be persisted to `.claude/state/observed-errors.md` in the same session.
- Entry must be fresh (mtime within 60 min of this session) and contain recognizable error syntax: HTTP 4xx/5xx + body, exception + stack frame, test diff verbatim, or console error + file:line.
- Doc-only commits, `chore:`/`style:`/`refactor:` commits, and merge commits skip the gate.
- Override: `OBSERVED_ERRORS_OVERRIDE=<reason>` env var, logged to `.claude/state/observed-errors-overrides.log`.
- Purpose: the friction of producing a fake error entry is comparable to producing a real one — the forcing function is pasting actual observed evidence, not writing about debugging.
