# Security — full doctrine

> Merged from the former rules: security, secret-hygiene. Compact: `doctrine/security.md`.

## Credentials & secrets

- NEVER commit `.env` files, API keys, tokens, or credentials.
- NEVER put secrets in markdown files, CLAUDE.md, or documentation.
- If you find exposed credentials, flag them immediately.
- No destructive operations (`rm -rf`, `DROP TABLE`, force-push) without explicit approval.
- Update `.env.example` when adding new environment variables (keep it current, never with real values).
- No `curl`, `wget`, or network requests to unknown endpoints — only to documented APIs.

## Public repositories (strict)

- **NEVER create a public GitHub repository.** Always use `--private` when running `gh repo create`.
- **NEVER change an existing repository's visibility to public.** Never run `gh repo edit --visibility public` or the equivalent API.
- Making a repository public is a **one-way door**: GitHub retains the history, scrapers index it immediately, and scrubbing is effectively impossible.
- A public repo is only permitted if ALL of these are true:
  1. The user explicitly asks for a public repo **in their current message** (not a previous message, not a general permission, not "you can decide").
  2. A complete security audit has been performed on every file AND the full git history.
  3. Zero credentials, infrastructure identifiers, business-specific data, or personal information are present.
  4. The user has confirmed understanding that public = permanent.
- If you catch yourself about to create a public repo, STOP and ask the user to confirm in the current message. If a repo might go public later, create it private and let the user make that call manually.

## Software installation

- NEVER install/download dependencies without justifying safety.
- Well-established tools (millions of users, known orgs): explain the trust basis, proceed.
- Anything less validated: stop and review with the user BEFORE installing.
- Prefer official distribution channels (winget, pip/PyPI, npm, GitHub releases).

## Three-layer defense against credential leaks

AI dev-tools (IDE assistants, MCP clients, agentic coding tools) commonly write machine-local config files into repo subdirectories. A casual `git add .` stages them; a `git commit -am` ships them — and these files routinely contain bearer tokens to downstream services. The three layers are sized so each independently catches the failure mode; bypassing one (e.g., `--no-verify`) does not bypass the others:

- **Layer 1** prevents `git add` from staging the file (override requires `git add -f`).
- **Layer 2** catches anything that DID get staged and committed, before it reaches a remote.
- **Layer 3** catches anything that reached a remote (e.g., if `--no-verify` was used).

## Layer 1 — global gitignore patterns

The file at `~/.config/git/ignore` is Git's XDG-fallback global gitignore (active when `core.excludesfile` is unset). Five categories of patterns to block:

1. **Harness-local** — `**/.claude/settings.local.json`, `**/.claude/local/` (per-machine config).
2. **AI dev-tool MCP configs** — `**/*.mcp.json`, `**/mcp-settings.json`, plus tool-specific filenames (Cursor's `mcp.json`, Claude Desktop's `claude_desktop_config.json`, Cline/Roo settings, Windsurf rules).
3. **AI dev-tool runtime / cache dirs** — `.codeium/`, `.continue/`, `.aider.conf.yml`, `.cline/`, `.roo/`, `.augment/`.
4. **IDE-emitted secret-bearing files** — `**/.idea/workspace.xml`, `**/.idea/dataSources.local.xml`, `**/.zed/settings.json`.
5. **Environment files outside the standard `.env*` set** — `*.env.private`, `.envrc.local`, `*.secrets`, `secrets.local.*`.

Verify a pattern matches a path with `git check-ignore -v <path>` (returns the matching line, or non-zero if none). To add a pattern, edit `~/.config/git/ignore` directly (per-machine; propagate manually) and re-verify. To force-track a sanitized variant of an ignored file, prefer renaming with an `.example` suffix over `git add -f` — the suffix is self-documenting; if `-f` is genuinely required, do it once during setup and document why in the README.

## Layer 2 — pre-push scanner

**Architecture:** `git config --global core.hooksPath` points at `<neural-lace>/adapters/claude-code/git-hooks/`. The `pre-push` file there is a dispatcher invoking the scanner at `<neural-lace>/adapters/claude-code/hooks/pre-push-scan.sh` for every push from every repo on the machine. The scanner checks the diff being pushed against built-in credential regexes plus `~/.claude/sensitive-patterns.local` (personal — never committed) plus `~/.claude/business-patterns.d/*.txt` / `~/.claude/business-patterns.paths` (team-shared). Pattern format per line: `Description|REGEX`. Add new patterns to whichever source matches the audience.

**Override-aware verification:** a per-repo `core.hooksPath` suppresses the global one. Two common cases:

- **Default-redundant override** — something set `core.hooksPath .git/hooks` (the Git default), suppressing the global path with no benefit. Fix: `git config --local --unset core.hooksPath`.
- **Husky-managed** — repos using Husky install with `core.hooksPath = .husky/_`; this is load-bearing, do NOT unset. Fix: add a committed, executable `.husky/pre-push` that delegates:

```bash
#!/usr/bin/env bash
SCANNER="$HOME/claude-projects/neural-lace/adapters/claude-code/hooks/pre-push-scan.sh"
[ -f "$SCANNER" ] && bash "$SCANNER" "$@" || echo "WARNING: scanner not found" >&2
```

**Audit command** for override status across all repos in a directory:

```bash
cd <repos-parent-dir> && for d in */; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  override=$(cd "$d" && git config --local --get core.hooksPath 2>/dev/null)
  [ -n "$override" ] && echo "$d: OVERRIDES with $override" || echo "$d: uses global (OK)"
done
```

Any repo reporting OVERRIDES needs case-by-case wiring per the two cases above. To test a new pattern blocks correctly, invoke the scanner directly with synthetic stdin in git pre-push format against a commit range containing the test pattern.

## Layer 3 — remote-side secret scanning

Most Git hosts (GitHub, GitLab) offer server-side secret scanning on every push, alerting on matches against hundreds of known credential providers. Enable it organization-wide. It catches: credentials that bypassed Layer 2 via `--no-verify`; credentials in repos lacking local hook wiring; public-fork scenarios. For some providers, scanning is partner-integrated — a known-pattern token in a public commit is auto-revoked by the provider.

**Audit and response:** check the host's secret-scanning alerts page per repo. Alerts left unaddressed are themselves a leak — they confirm a credential was pushed and survive in history even after a revert. The correct response to any alert: (a) revoke the credential at the provider, (b) rotate downstream usage, (c) close the alert.

## Fresh machine setup

1. Install the harness per the install convention.
2. `git config --global core.hooksPath <neural-lace>/adapters/claude-code/git-hooks/`.
3. Copy or recreate `~/.config/git/ignore` with the Layer 1 pattern set.
4. Verify with `git check-ignore -v <leak-vector-path>` (should match).
5. Audit per-repo `core.hooksPath` overrides with the Layer 2 audit command.
