# Setup Guide

This guide walks a new user through installing Neural Lace and customizing it for their setup. Expected time: 10–15 minutes.

## Prerequisites

- Git 2.25+
- Bash (Git Bash on Windows is fine)
- [GitHub CLI](https://cli.github.com/) (`gh`) — for account-switching hooks
- [jq](https://jqlang.github.io/jq/) — for config parsing
- Claude Code installed ([docs](https://docs.claude.com/en/docs/claude-code))

## Install

```bash
cd ~
mkdir -p claude-projects && cd claude-projects
# Clone from the canonical upstream (check the current repo URL in your browser):
git clone <repo-url> neural-lace
cd neural-lace
./adapters/claude-code/install.sh
```

The installer:

- Copies rules, agents, hooks, templates, and the CLAUDE.md file into `~/.claude/`
- Sets `git config --global core.hooksPath` to the adapter's `git-hooks/` directory so the credential scanner runs on every push
- Creates `~/.claude/local/` and seeds it from the `.example.json` files in `adapters/claude-code/examples/`
- Creates `~/.claude/business-patterns.d/` for team-shared pattern files (see `docs/business-patterns-workflow.md`)
- Prunes `~/.claude/.backup-*` directories older than 30 days

It's safe to re-run: existing files are backed up before overwrite, and user customizations in `~/.claude/local/` are never touched.

## Customize — the two-layer config pattern

Neural Lace separates **harness data** (shared, generic, safe for any repo) from **local data** (your identity, accounts, project specifics). The harness ships only generic placeholders; your personalization lives in `~/.claude/local/`.

Files to edit after first install (all seeded from examples):

### `~/.claude/local/personal.config.json`

Your identity for git attribution and hook messages.

```json
{
  "version": 1,
  "preferred_name": "Alice Example",
  "noreply_email": "12345+alice@users.noreply.github.com",
  "timezone": "America/Los_Angeles"
}
```

### `~/.claude/local/accounts.config.json`

Your GitHub account mappings. Drives automatic account-switching when your directory changes.

```json
{
  "version": 1,
  "personal": {
    "user": "alice-example",
    "dir_triggers": ["~/code", "~/personal"]
  },
  "work": [
    {
      "user": "alice-at-acme",
      "dir_triggers": ["~/work/acme-corp"],
      "public_blocked": true
    }
  ]
}
```

- `dir_triggers` — when your current directory is under one of these paths, the hook switches `gh auth` to that account
- `public_blocked: true` — additional safeguard that refuses public-repo creation from this account (pair with your org's GitHub settings → Member privileges → "Public" disabled)

### `~/.claude/local/automation-mode.json`

How autonomously Claude operates. On first install, you'll see a prompt asking you to choose. You can change anytime via `/automation-mode`:

```json
{
  "version": 1,
  "mode": "review-before-deploy",
  "deploy_matchers": [
    "git push",
    "gh pr merge",
    "gh repo create",
    "supabase db push",
    "vercel deploy",
    "npm publish"
  ]
}
```

- `review-before-deploy` (default): Claude pauses before any Bash command matching a deploy matcher and waits for your approval
- `full-auto`: Claude runs through planned work without pausing on deploy matchers (other safeguards like the credential scanner and dangerous-command blocker still apply)

Per-project override: create `<project>/.claude/automation-mode.json` — takes precedence over the user-global file.

### `~/.claude/local/projects.config.json` (optional)

Per-project persona hints for testing/content agents. See `adapters/claude-code/examples/projects.config.example.json` for the shape.

## First-time checks

After install + customization, verify everything is wired up:

```bash
# Scanner works
bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test   # expect "self-test: OK"

# Local config loads
bash adapters/claude-code/scripts/read-local-config.sh --self-test    # expect "self-test: OK"

# Automation-mode gate works
bash adapters/claude-code/hooks/automation-mode-gate.sh --self-test   # expect "self-test: OK"

# Pre-commit scanner installed in this repo
ls -la .git/hooks/pre-commit   # should be executable, contain NEURAL-LACE-HYGIENE-HOOK
```

## Changing automation mode

```bash
/automation-mode review          # switch to review-before-deploy (global)
/automation-mode full-auto       # switch to full-auto (global)
/automation-mode status          # print current effective mode
/automation-mode review --project   # write the override to the current project's .claude/
```

## Updating

```bash
cd ~/claude-projects/neural-lace
git pull
./adapters/claude-code/install.sh   # refresh ~/.claude/ from the repo
```

On platforms with symlinks (macOS, Linux), `git pull` alone is sufficient. On Windows (file copies), re-run `install.sh` to propagate changes.

## What ships and what doesn't

The harness deliberately ships **templates and enforcement mechanisms** — not operational artifacts. In a project repo using Neural Lace, you produce plan files (`docs/plans/*.md`), decision records (`docs/decisions/*.md`), and review outputs (`docs/reviews/*.md`) as permanent team artifacts. Those files belong in your project repo.

In the **harness repo itself**, those same directories are gitignored because they would accumulate identifiers from every project the harness was used to build.

See `principles/harness-hygiene.md` for the full rule.

## Where to go next

- `README.md` — concept overview + architecture
- `docs/harness-guide.md` — file-by-file reference for every rule, agent, and hook
- `docs/harness-architecture.md` — enforcement map + hook chains
- `principles/harness-hygiene.md` — hygiene rules every harness change must follow
- `docs/business-patterns-workflow.md` — sharing team-private patterns without leaking them

## Reporting issues

- Bugs / feature requests: open a GitHub Issue on the upstream repo
- Security disclosures: file a private security advisory via GitHub's security tab
