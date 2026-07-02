# Local-edit Authorization — compact
> Enforcement: local-edit-gate.sh (PreToolUse Edit/Write/MultiEdit, blocks by default).
> Applies: any edit to `~/.claude/local/**`.

- Edit/Write/MultiEdit on `~/.claude/local/**` (accounts.config.json, personal.config.json, projects.config.json, automation-mode.json, local CLAUDE.md, etc.) requires a fresh per-file authorization marker.
- Authorize via `/grant-local-edit <filename>` — writes a marker `local-edit-gate.sh` consumes.
- Marker is valid for **30 minutes**; must match the target's filename-slug (lowercase, dots/spaces -> dashes, non-alphanumerics stripped).
- No marker or expired marker -> BLOCK. Wrong tool (not Edit/Write/MultiEdit) or target outside `~/.claude/local/` -> silent allow.
- Default-block protects credential-bearing files; in-band `/grant-local-edit` removes the "user authorized but agent can't act" friction.
