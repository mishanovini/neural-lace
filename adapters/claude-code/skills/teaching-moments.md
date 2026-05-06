---
description: Capture or browse teaching moments — interactions where the user pushed back and Claude's revised position became substantively better. Used to teach developers good prompting patterns. Use when the user asks "capture this", "this was a good prompt", or wants to see existing examples. Companion to ~/.claude/rules/teaching-moments.md.
---

# /teaching-moments

Capture and browse teaching moments — moments in Claude conversations where the user's pushback produced a better answer than Claude's first response. The captured examples become a living curriculum for developers learning to work with Claude Code.

See `~/.claude/rules/teaching-moments.md` for when capture qualifies + the file-format spec.

## Subcommands

### `/teaching-moments capture` — manually capture a moment

Use when Claude missed one and the user wants to capture it after the fact, OR when the user wants to capture a moment Claude wouldn't have been the judge of (e.g., "I think you missed a teaching moment in the prior turn").

Procedure:

1. **Identify the conversation segment.** Read the user's last 5-10 messages and Claude's responses. Find the pushback that produced the shift.
2. **Confirm it qualifies.** Apply the four criteria from `~/.claude/rules/teaching-moments.md` — substantive pushback, meaningfully better revised position, generalizable lesson, enough context surviving.
3. **Author the file.** Write to `docs/teaching-examples/YYYY-MM-DD-<slug>.md` using the format in the rule.
4. **Surface to user.** Show the file path; ask if they want adjustments.

### `/teaching-moments list` — list all captured examples

Procedure:

1. `ls docs/teaching-examples/*.md`
2. For each: read frontmatter, emit `<date> | <topic> | <lesson>` table row.
3. If no `docs/teaching-examples/` directory exists, surface "no teaching examples captured in this project yet."

### `/teaching-moments show <slug>` — show a specific example

Read `docs/teaching-examples/<slug-or-date-prefix>.md` and display.

### `/teaching-moments propagate` — copy to user's cross-project pool

Use when the user wants a project-level teaching example to live in their broader curriculum (e.g., shared across teams, kept across projects).

Procedure:

1. List `docs/teaching-examples/*.md` in the current project.
2. Ask which to propagate (or `all`).
3. Copy each to `~/teaching-examples/<original-slug>.md`, prepending `[from <project-name>]` to the topic frontmatter to preserve provenance.
4. Confirm with file paths.

## When NOT to use this skill

- Don't auto-capture every minor correction. The bar in `~/.claude/rules/teaching-moments.md` is "0-1 captures per session is normal; 3+ means the bar is too low."
- Don't use to capture the user's domain knowledge ("the user told me about X library"). That's information transfer, not a teaching moment about prompting.
- Don't use to capture Claude's self-corrections ("I made an error and fixed it"). The teachable moment requires the user's pushback as the surfacing mechanism.

## Cross-references

- `~/.claude/rules/teaching-moments.md` — the capture rule (when to write, format spec)
- `docs/teaching-examples/` — the captured examples (project-level)
- `~/teaching-examples/` — user's cross-project pool (manually populated via `/teaching-moments propagate`)
