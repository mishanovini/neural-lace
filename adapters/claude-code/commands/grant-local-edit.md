---
description: Authorize the agent to edit a single file under ~/.claude/local/ for 30 minutes by writing a fresh marker that local-edit-gate.sh consumes.
argument-hint: <filename> [reason]
---

# grant-local-edit

Default-block gates around `~/.claude/local/` exist for a reason — those files
include credential-bearing config (`accounts.config.json`, `personal.config.json`)
that the agent must not silently drift. This command is the in-band escape hatch:
the user explicitly authorizes the agent to edit ONE specific file for 30 minutes.
After that, the authorization expires and `local-edit-gate.sh` blocks again.

Same shape as `bug-persistence-gate`'s waivers and `dag-review-waiver-gate`'s
session-approval markers. See ADR 029 and `rules/local-edit-authorization.md`.

Given the user's arguments `$ARGUMENTS`, follow this procedure exactly.

## Step 1 — Parse arguments

Split `$ARGUMENTS` on whitespace:

- `FILENAME` = first token (a basename within `~/.claude/local/`, e.g.
  `CLAUDE.md`, `accounts.config.json`, `credentials-reference.md`).
- `REASON` = the remaining tokens joined (optional one-line rationale).

If `FILENAME` is empty, print this usage and STOP:

```
Usage: /grant-local-edit <filename> [reason]
  <filename>  basename within ~/.claude/local/ (no path separators)
  [reason]    optional one-line rationale recorded in the marker
```

If `FILENAME` contains a `/` or `\`, reject it (basename only) and STOP.

## Step 2 — Derive the filename-slug

Lowercase, replace dots and spaces with dashes, strip all remaining
non-alphanumeric/non-dash characters, collapse repeated dashes, trim
leading/trailing dashes. This MUST match `local-edit-gate.sh`'s
`filename_slug()` exactly. Compute it with:

```bash
SLUG=$(printf '%s' "<FILENAME>" | tr '[:upper:]' '[:lower:]' | tr '. ' '--' | sed -E 's/[^a-z0-9-]//g' | sed -E 's/-+/-/g' | sed -E 's/^-|-$//g')
```

Example: `credentials-reference.md` → `credentials-reference-md`;
`accounts.config.json` → `accounts-config-json`.

## Step 3 — Write the marker

Write a fresh marker (mtime = now) via Bash. Writing under `~/.claude/state/`
is NOT gated, so this succeeds:

```bash
mkdir -p ~/.claude/state
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
MARKER=~/.claude/state/local-edit-${SLUG}-${TS}.txt
cat > "$MARKER" <<EOF
Filename: <FILENAME>
Slug: ${SLUG}
Granted: ${TS}
Reason: <REASON or "(none provided)">
EOF
echo "Authorized: ~/.claude/local/<FILENAME> is editable until $(date -u -d '+30 minutes' +%H:%M:%SZ 2>/dev/null || echo '30 minutes from now'). Marker: $MARKER"
```

The gate only checks that a file matching `local-edit-<slug>-*.txt` exists in
`~/.claude/state/` with mtime within 30 minutes — it does not validate the
body. The 4-line body above is for audit.

## Step 4 — Confirm

Echo to the user: which file is now editable, the marker path, and that the
authorization expires in 30 minutes. Then proceed with the edit the user asked
for (the gate will now allow it).

## When to invoke

Invoke when the user authorizes editing a specific file under `~/.claude/local/`
in their current message (e.g. "add a section to my local CLAUDE.md", "update
credentials-reference.md", "bump automation-mode.json to full-auto").

Do NOT invoke for files outside `~/.claude/local/` (the gate is silent on those),
without an explicit user authorization, or as a speculative "just in case" grant.
