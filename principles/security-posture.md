# Security Posture

## What this principle covers
How to handle credentials, prevent accidental exposure, validate software sources, and maintain defense in depth. These principles apply regardless of language, platform, or toolchain.

---

## Never Commit Credentials

This is absolute. No exceptions, no "just for testing," no "I will rotate it later."

- Never commit `.env` files, API keys, tokens, passwords, or credentials of any kind.
- Never put secrets in documentation, readme files, configuration guides, or inline comments.
- If you discover exposed credentials in a repository, flag them immediately. Assume they are already compromised.

Secrets belong in environment configuration, secret managers, or encrypted vaults. They do not belong in version control, even in private repositories. Git history is permanent.

---

## No Secrets in Documentation

Documentation is often the most widely shared artifact in a project. Treat every documentation file as potentially public:

- Use placeholder values (`YOUR_API_KEY_HERE`) instead of real credentials.
- Never include infrastructure identifiers (database connection strings, internal hostnames, account IDs) in docs unless the doc is explicitly marked as internal and access-controlled.
- When writing setup guides, reference environment variables by name, not by value.

---

## Defense in Depth

No single security measure is sufficient. Layer defenses so that when one fails, others catch the breach:

1. **Developer discipline:** Follow the rules above. This is the first line.
2. **Automated scanning:** Use pre-commit and pre-push hooks to scan for credential patterns. This catches what discipline misses.
3. **Review gates:** Code review should include a security check. Reviewers should verify that no secrets, overly broad permissions, or unsafe patterns were introduced.
4. **Runtime protection:** Row-level security, authentication middleware, and authorization checks in the application itself. Never rely solely on the client to enforce access control.

Each layer assumes the previous layer might have failed.

---

## Public Exposure Is a One-Way Door

Making a repository, document, or API endpoint public is effectively irreversible. Scrapers index content within minutes. Git history cannot be reliably scrubbed.

Before making anything public, require all of:

1. **Explicit, current consent** from the owner. Not implied, not from a previous conversation, not "they said it was fine last week."
2. **A complete security audit** of every file and the full version history.
3. **Zero credentials, infrastructure identifiers, business-specific data, or personal information** present anywhere in the content or its history.

When in doubt, keep it private. It is trivial to make something public later. It is nearly impossible to make something private again.

---

## Software Installation Safety

Every dependency you install is code you trust to run on the user's machine. Treat installation as a security decision:

- **Well-established tools** (millions of users, maintained by known organizations): explain the trust basis and proceed.
- **Less-validated tools** (small user base, unknown maintainer, recent creation): stop and review with the user before installing.
- **Prefer official distribution channels:** package registries (npm, PyPI, crates.io), platform package managers (apt, brew, winget), and official GitHub releases. Avoid downloading binaries from arbitrary URLs.
- **Justify every new dependency.** "It saves a few lines of code" is not sufficient justification for adding a dependency with its own dependency tree, maintenance burden, and attack surface.

---

## Credential Scanning at Multiple Stages

Do not rely on a single scan. Implement scanning at multiple points in the workflow:

- **Before commit:** Catch secrets before they enter version history.
- **Before push:** Last line of defense before secrets leave the local machine.
- **In CI:** Catch secrets that bypassed local hooks (new machine, misconfigured environment).
- **In review:** Human eyes on the diff, specifically looking for credential patterns.

The goal is redundancy. Any single stage can fail. The combination should not.
