# Observed Errors First (Stub — enforcement is in the hook)

**Rule:** when committing a fix, the verbatim error you observed at runtime must be persisted to `.claude/state/observed-errors.md` in the same session before the commit can land.

**Classification:** Mechanism. This file is intentionally short. The format spec, override conditions, and trigger logic are all enforced by `hooks/observed-errors-gate.sh`. If a constraint described below isn't backed by the hook, it's theater.

## Why this rule exists

Read-the-error-body discipline is exactly the kind of behavior that depends on the agent's self-classification ("am I in a debugging situation?") — which historically fails. The forcing function isn't the file's content; it's the act of pasting an actual error message (HTTP status + body, exception + stack frame, test diff verbatim, console error with file:line). A perfunctory entry is hard to write because the agent has to invent recognizable error syntax. The friction of producing fake evidence is comparable to producing real evidence — and that's the point.

## Enforcement map (hook-backed)

| Constraint | Hook / agent that enforces it | File |
|---|---|---|
| Fix-class commits require a fresh `.claude/state/observed-errors.md` entry | `observed-errors-gate.sh` PreToolUse Bash blocker on `git commit` | `~/.claude/hooks/observed-errors-gate.sh` |
| Entry must be from current session (mtime within 60 min) | same hook | same |
| Entry must contain recognizable error syntax (HTTP 4xx/5xx + body, exception + stack, test diff, or console error + file:line) | same hook | same |
| Doc-only commits, `chore:` / `style:` / `refactor:` commits, and merge commits skip the gate | same hook | same |
| Override via `OBSERVED_ERRORS_OVERRIDE=<reason>` env var; logged to `.claude/state/observed-errors-overrides.log` | same hook | same |

## Cross-references

- `rules/diagnosis.md` — broader exhaustive-diagnosis discipline; this rule operationalizes its first principle ("read the full stack") for the moment of "I'm about to commit a fix."
- `hooks/observed-errors-gate.sh` — the gate itself; format spec lives in the hook header comment.
- `docs/harness-review-audit-questions.md` — the five lenses this rule was designed against (observable trigger, narrow remedy, low cheap-evasion paths).
