---
name: grant-local-edit
description: Authorize the agent to edit a single file under ~/.claude/local/ for 30 minutes. Writes a session-scoped marker to ~/.claude/state/ that local-edit-gate.sh consumes at PreToolUse time. Required before any agent Edit/Write/MultiEdit on machine-local config (accounts.config.json, personal.config.json, projects.config.json, automation-mode.json, CLAUDE.md, etc.). Use when the user explicitly authorizes a local-config edit in the current message — e.g., "add this to ~/.claude/local/CLAUDE.md" or "update my account config to add the work GitHub user."
---

# grant-local-edit

Default-block gates around `~/.claude/local/` exist for a reason — those files
include credential-bearing config (`accounts.config.json`, `personal.config.json`)
that agents must not silently drift. This skill is the in-band escape hatch:
the user explicitly authorizes the agent to edit ONE specific file for 30
minutes. After that, the authorization expires; the gate blocks again.

This is the same shape as `bug-persistence-gate`'s waivers and
`dag-review-waiver-gate`'s session-approval markers — fresh-marker pattern
applied to the local-edit case. See ADR 029 and `rules/local-edit-authorization.md`.

## When to invoke

Invoke when the user authorizes editing a specific file under `~/.claude/local/`:

- "Add a section to `~/.claude/local/CLAUDE.md`" — invoke
  `/grant-local-edit CLAUDE.md` THEN do the edit.
- "Update my `accounts.config.json` to add a new directory mapping" — invoke
  `/grant-local-edit accounts.config.json` THEN do the edit.
- "Bump `automation-mode.json` to full-auto" — invoke
  `/grant-local-edit automation-mode.json` THEN do the edit.

Do NOT invoke:

- For files outside `~/.claude/local/` — the gate is silent on those, no
  authorization needed.
- Without an explicit user authorization in the current message — the user
  must have stated intent to modify the local file.
- For "just in case" preemptive grants — markers expire in 30 min, so
  speculative grants don't help.

## How to invoke

Two argument forms:

- **Filename only:** `/grant-local-edit <filename>` — basename within
  `~/.claude/local/`. Examples: `CLAUDE.md`, `accounts.config.json`,
  `automation-mode.json`. The skill auto-derives a kebab-case slug.
- **Filename + reason:** `/grant-local-edit <filename> <reason>` — same plus
  a one-line rationale that gets recorded in the marker for audit.

If invoked with no args, the skill prints usage and exits.

## What the skill does

1. Validates `<filename>` exists or is a path the user could reasonably want
   to create under `~/.claude/local/` (basename only — no path separators).
2. Derives a filename-slug: lowercase, dots → dashes, non-alphanumerics
   stripped. Example: `accounts.config.json` → `accounts-config-json`.
3. Generates an ISO 8601 timestamp.
4. Writes the marker file at:
   `~/.claude/state/local-edit-<filename-slug>-<ISO8601>.txt`
   The body contains:
   - Line 1: `Filename: <basename>`
   - Line 2: `Slug: <slug>`
   - Line 3: `Granted: <ISO timestamp>`
   - Line 4: `Reason: <reason or "(none provided)">`
5. Echoes confirmation to stdout: which file is now editable, until when.

The marker has no further authorization mechanism beyond mtime + slug-match;
the trust model is "operator controls `~/.claude/state/`," same as every
other fresh-marker gate in the harness.

## Marker lifecycle

- **Granted at invocation time** (mtime = now).
- **Consumed implicitly** by the next Edit/Write/MultiEdit on the matching
  file — gate sees the fresh marker, allows the edit, marker is NOT deleted
  (so subsequent edits within the 30-min window also work).
- **Expires after 30 minutes** (mtime check). Stale markers are inert.
- **Survives session boundaries** — the user can grant in one session, the
  agent can act in a session that fires within the 30-min window. Per
  user's stated workflow, this is acceptable; if cross-session grants prove
  problematic, the gate's freshness window is the knob to tighten.

## Cross-references

- `rules/local-edit-authorization.md` — the rule the skill operationalizes.
- `hooks/local-edit-gate.sh` — the consumer.
- `docs/decisions/029-local-edit-authorization-mechanism.md` — design rationale.

## Examples

**Example 1 — add to local CLAUDE.md**

User: "Add this directory-structure section to `~/.claude/local/CLAUDE.md`."

Agent:
1. Invokes `/grant-local-edit CLAUDE.md`.
2. Skill writes `~/.claude/state/local-edit-claude-md-2026-05-09T20-30-00Z.txt`.
3. Agent invokes Write tool on `~/.claude/local/CLAUDE.md` with the new content.
4. `local-edit-gate.sh` fires PreToolUse, sees the marker, allows.
5. Edit lands.

**Example 2 — update accounts.config.json**

User: "Add the work GitHub user to my accounts mapping for the new project at `~/claude-projects/<work-org>/new-tool/`."

Agent:
1. Invokes `/grant-local-edit accounts.config.json` (with reason: "user authorized adding new project mapping").
2. Skill writes the marker.
3. Agent reads `~/.claude/local/accounts.config.json`, edits, writes back.
4. Gate allows.
5. Edit lands.

**Example 3 — speculative grant (DON'T)**

User: "What's in my accounts.config.json?"

Agent: (just reads it — Read is not gated). Does NOT invoke `/grant-local-edit`
because no edit was authorized.
