# SCRATCHPAD Template

The canonical shape for a project's `SCRATCHPAD.md` (working memory at project root; gitignored). Hard cap: 30 lines. SCRATCHPAD is a pointer, not a log — details live in plan files, backlog, and session summaries; SCRATCHPAD just tells a fresh session where to look and what's urgent.

See `~/.claude/CLAUDE.md` §"Context Persistence" for the operational discipline (when to read it, when to rewrite it).

## Format

```
# SCRATCHPAD — [Project Name]
## Current State (YYYY-MM-DD)
Branch: X | Deployed: Y | Migrations: through NNN

## Latest Milestone
[2-3 lines — what just shipped or was verified]

## Active Plan
[Path to plan file, or "None". Status: ACTIVE/COMPLETED/etc.]

## Backlog Pointer
[Path to backlog file, or key priorities if no backlog file exists]

## What's Next
[3-5 lines — immediate priorities for the next session]

## Blocking / Known Issues
[2-3 lines, or "None"]
```
