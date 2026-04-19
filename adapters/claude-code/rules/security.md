# Security Rules

## Credentials & Secrets
- NEVER commit `.env` files, API keys, tokens, or credentials
- NEVER put secrets in markdown files, CLAUDE.md, or documentation
- If you find exposed credentials, flag them immediately
- No destructive operations (`rm -rf`, `DROP TABLE`, force-push) without explicit approval
- Update `.env.example` when adding new environment variables (keep it current, never with real values)
- No `curl`, `wget`, or network requests to unknown endpoints — only to documented APIs

## Public Repositories (Strict)
- **NEVER create a public GitHub repository.** Always use `--private` when running `gh repo create`.
- **NEVER change an existing repository's visibility to public.** Never run `gh repo edit --visibility public` or use the equivalent API.
- Making a repository public is a **one-way door**: GitHub retains the history, scrapers index it immediately, and scrubbing is effectively impossible.
- A public repo is only permitted if ALL of these are true:
  1. The user explicitly asks for a public repo **in their current message** (not a previous message, not a general permission, not "you can decide")
  2. A complete security audit has been performed on every file AND the full git history
  3. Zero credentials, infrastructure identifiers, business-specific data, or personal information are present
  4. The user has confirmed understanding that public = permanent

- If you catch yourself about to create a public repo, STOP and ask the user to confirm in the current message.
- If you're building a repo that the user might want to make public later, create it private and let them make that decision manually.

## Software Installation
- NEVER install/download dependencies without justifying safety
- Well-established tools (millions of users, known orgs): explain trust basis, proceed
- Anything less validated: stop and review with user BEFORE installing
- Prefer official distribution channels (winget, pip/PyPI, npm, GitHub releases)

## Pre-Push Scanner (Enforcement Layer)
Every `git push` runs through a pattern scanner at `~/claude-projects/neural-lace/adapters/claude-code/hooks/pre-push-scan.sh` that blocks pushes containing credentials or known-sensitive identifiers. This is the last-line enforcement when a rule is forgotten or bypassed. See `docs/harness-guide.md` for how the scanner loads personal and team patterns.
