# Security — compact
> Enforcement: pre-push-scan.sh (Layer 2), global gitignore (Layer 1), remote secret scanning (Layer 3); else Pattern — self-applied. Sources: security, secret-hygiene. Full: doctrine/security-full.md
> Applies: every session — credentials, destructive ops, repo visibility, installs.

- **NEVER commit** `.env` files, API keys, tokens, or credentials — not in source, not in markdown, not in CLAUDE.md. Flag exposed credentials immediately. Keep `.env.example` current, never with real values.
- no destructive operations (`rm -rf`, `DROP TABLE`, force-push) without explicit approval.
- Public repos: NEVER create one — always `--private` on `gh repo create`; never flip visibility to public. Public is a one-way door: permitted only with the user's request in their current message + full audit of every file AND git history + zero credentials/identifiers + user-confirmed permanence.
- Software installs: justify safety first. Well-established tools (millions of users, known orgs): state the trust basis, proceed. Anything less: stop and review with the user BEFORE installing. Official channels only (winget, pip/PyPI, npm, GitHub releases).
- No curl/wget to unknown endpoints — documented APIs only.
- Three-layer secret defense (independent layers — bypassing one does not bypass the others):
  1. Global gitignore (`~/.config/git/ignore`) blocks leak-vector files from `git add .` — MCP/AI-tool configs, IDE secret-bearing files, nonstandard `.env*` variants. Verify a pattern with `git check-ignore -v <path>`.
  2. pre-push-scan.sh via global `core.hooksPath` scans every push diff against built-in credential regexes + personal (`~/.claude/sensitive-patterns.local`) + team-shared patterns. Husky repos delegate via a committed `.husky/pre-push`. Per-repo `core.hooksPath` overrides suppress it — audit them; unset default-redundant ones.
  3. Remote-side secret scanning (e.g. GitHub Advanced Security) alerts on anything that reached the remote. Any alert: revoke the credential, rotate downstream usage, close the alert.
