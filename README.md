# Neural Lace

> A foundation for AI-assisted development: enforced best practices, risk-based permissions, progressive autonomy, and continuous self-evaluation.

Neural Lace is a harness platform that grows with its host. It wraps AI coding tools (Claude Code, Codex, Cursor, Gemini) with a mechanically-enforced layer of software-engineering + AI-collaboration best practices — so individual developers and teams inherit years of distilled discipline by default, not by self-enforcement.

> **Agent Teams (experimental, feature-flagged).** Compatibility with Anthropic's `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` ships disabled by default. To enable safely (with all harness gates working across teammate sessions), see [`adapters/claude-code/rules/agent-teams.md`](adapters/claude-code/rules/agent-teams.md). Decision record: [`docs/decisions/012-agent-teams-integration.md`](docs/decisions/012-agent-teams-integration.md).

## What It Does

- **Enforced best practices** (not aspirational): evidence-based task completion, anti-vaporware verification, decision-record atomicity, tool-call budget discipline, and more — each backed by a pre-commit hook or session gate that blocks the anti-pattern mechanically. See [`docs/best-practices.md`](docs/best-practices.md) for the full catalog.
- **Risk-based permissions**: Actions are classified by 6 risk dimensions (reversibility, blast radius, sensitivity, authority escalation, novelty, velocity) instead of brittle pattern matching. Unknown actions are handled gracefully.
- **Progressive autonomy**: Trust accumulates through safe operation. The system asks less and does more as reliability is demonstrated — but never stops protecting against catastrophic actions. Automation mode is configurable per-session, per-user, or per-project.
- **Two-layer configuration**: shareable harness code never contains identity, credentials, or machine-specific paths. Personal config lives in `~/.claude/local/` (gitignored). Hygiene scanner mechanically enforces this at pre-commit time.
- **Self-evaluation**: A weekly `/harness-review` skill audits the harness itself — dead doc links, stale references, drift between installed and source copies, hygiene violations.
- **Defense in depth**: Credentials scanned at commit time AND push time. Security anti-patterns common in AI-generated code flagged before they ship. Public-repo creation blocked per-account via `public_blocked` flag.
- **Forward-compatible**: Universal principles (Layer 0) and abstract patterns (Layer 1) survive tool changes. Only thin adapters (Layer 2) need to be rewritten per tool.

## Architecture

```
┌─────────────────────────────┐
│  Layer 0: PRINCIPLES        │  Universal values, risk model, autonomy ladder
│  (principles/)              │  Changes rarely. Tool-agnostic.
├─────────────────────────────┤
│  Layer 1: PATTERNS          │  Rules, hooks, agents, risk profiles, templates
│  (patterns/)                │  Changes occasionally. Tool-agnostic.
├─────────────────────────────┤
│  Layer 2: ADAPTERS          │  Claude Code, Codex, Cursor, Gemini
│  (adapters/)                │  Changes per tool version. Tool-specific.
├─────────────────────────────┤
│  Layer 3: PROJECT           │  Per-repo rules, audience, context
│  (in each project)          │  Changes per project.
└─────────────────────────────┘
```

## Directory Structure

```
neural-lace/
  principles/          Layer 0: Universal principles (risk model, autonomy, security)
  patterns/            Layer 1: Abstract patterns (rules, hooks, agents, risk profiles)
  adapters/            Layer 2: Tool-specific implementations
    claude-code/       Claude Code adapter (settings.json, hooks, agents, rules)
    codex/             Codex adapter (planned)
    cursor/            Cursor adapter (planned)
  telemetry/           Continuous monitoring schemas and collectors
  learning/            Self-improvement engine (proposals, accepted, rejected)
  evals/               Harness self-tests (golden scenarios, structural checks)
  docs/                Strategy, architecture, guides
```

## Quick Start (Claude Code)

```bash
cd ~/claude-projects
git clone https://github.com/<your-org-or-user>/neural-lace.git
cd neural-lace/adapters/claude-code
chmod +x install.sh
./install.sh
```

This deploys rules, agents, hooks, and templates to `~/.claude/` and sets up global git hooks for security scanning. See [`SETUP.md`](SETUP.md) for the detailed walkthrough (customizing `~/.claude/local/`, choosing an automation mode, first-run verification).

## Best Practices

This harness is as much about **encoded best practices** as it is about AI autonomy. A few highlights:

- **CLAUDE.md < 200 lines** — Anthropic recommends keeping it an index, not a book. `adapters/claude-code/CLAUDE.md` is the model.
- **Evidence-first task completion** — plan checkboxes can only be flipped by the `task-verifier` agent, never by self-report. A separate hook (`plan-edit-validator`) enforces this mechanically.
- **Decision records are atomic with the index** — every `docs/decisions/NNN-*.md` must be staged alongside `docs/DECISIONS.md` in the same commit. Hook-enforced.
- **Tool-call budget discipline** — after every 30 Edit/Write/Bash calls, the harness blocks further work until a `plan-evidence-reviewer` audit runs.
- **Orchestrator pattern for long plans** — main session dispatches build work to sub-agents; stays lean as an orchestrator. Documented in `rules/orchestrator-pattern.md`.
- **Anti-vaporware enforcement** — runtime features require a replayable runtime-verification command; "code exists" isn't done.
- **Two-layer config separation** — no identity in shareable code; everything personal lives in `~/.claude/local/`. Pre-commit scanner blocks accidental leaks.
- **Automation-mode default is safe** — `review-before-deploy` pauses before `git push`, `gh pr merge`, `supabase db push`, etc. Users opt IN to `full-auto`.

Full catalog of 25+ practices, their rationale, and where each is enforced: **[`docs/best-practices.md`](docs/best-practices.md)**.

## How It Works (Operational Wiring)

After installation, Neural Lace connects into your development workflow at multiple points:

```
neural-lace/adapters/claude-code/
    │
    ├── install.sh ──────► ~/.claude/
    │                       ├── agents/     (spawned on demand by Claude Code)
    │                       ├── rules/      (loaded contextually by file pattern)
    │                       ├── hooks/      (called by settings.json lifecycle hooks)
    │                       ├── templates/  (referenced during planning)
    │                       ├── docs/       (read on demand)
    │                       └── settings.json (permissions, hooks, plugins)
    │
    └── git-hooks/ ─────► git config --global core.hooksPath
                           ├── pre-commit   (credential + security scan on EVERY commit)
                           └── pre-push     (credential scan on EVERY push)
                                              └── loads patterns from:
                                                  ├── built-in (18+ patterns)
                                                  ├── ~/.claude/sensitive-patterns.local
                                                  └── ~/.claude/business-patterns.d/*.txt
```

**Key points:**
- `install.sh` symlinks (or copies on Windows) adapter files into `~/.claude/`
- `git core.hooksPath` makes the pre-commit and pre-push scanners global — they protect ALL repos on the machine, not just AI-assisted ones
- `settings.json` is machine-specific (copied from template, never overwritten on update)
- Rules load contextually — `api-routes.md` only loads when editing API route files

## Updating

```bash
cd ~/claude-projects/neural-lace
git pull
# Re-run installer to refresh symlinks/copies
./adapters/claude-code/install.sh
```

On platforms with symlinks (macOS, Linux), `git pull` is enough — symlinks point to the repo. On Windows (file copies), re-run `install.sh` after pulling to propagate changes.

## Security Scanning

### Pre-Commit (every commit, every repo)

Scans staged content and filenames for:

**Blockers (exit 1):**
- Credentials: API keys, tokens, private keys, JWTs (18+ pattern families)
- Sensitive files: `.env`, `credentials.json`, `secrets.yaml`, SSH keys
- Supabase service role key in client-side code

**Warnings (informational):**
- Hardcoded localhost URLs
- XSS vectors (`dangerouslySetInnerHTML`)
- Disabled type checking (`@ts-nocheck`)
- TLS validation bypass, permissive CORS
- SQL injection via template literals
- Exposed error internals to clients
- `debugger` statements, large files, lockfile desync

### Pre-Push (every push, every repo)

Scans the push diff for all credential patterns. This is the second line of defense — catches anything that made it past pre-commit.

### Pattern Sources (layered)

1. **Built-in**: 18+ credential families hardcoded in the scanner
2. **Personal**: `~/.claude/sensitive-patterns.local` (never committed)
3. **Team**: `~/.claude/business-patterns.d/*.txt` (symlinked from private repos)

See `docs/business-patterns-workflow.md` for team pattern sharing setup.

### Override

```bash
git commit --no-verify  # bypasses pre-commit (blocked by Claude Code's PreToolUse hook)
git push --no-verify    # bypasses pre-push (also blocked by PreToolUse hook in AI sessions)
```

In Claude Code sessions, `--no-verify` is itself blocked by a PreToolUse hook — so AI cannot bypass the scanners without explicit user authorization.

## Multi-Account Management

Neural Lace supports development across multiple GitHub accounts (e.g., personal + work org).

**Configuration:**
Copy `adapters/claude-code/examples/accounts.config.example.json` to `~/.claude/local/accounts.config.json` and fill in your accounts. The file is git-ignored and machine-local. Each account entry declares:

- `gh_user` — the GitHub username to switch to
- `dir_triggers` — directories under which this account is active
- `public_blocked` — set to `true` on work/sensitive accounts to prevent public-repo creation

See `~/.claude/local/accounts.config.example.json` after installation for the full schema.

**Per-session account switching:**
The Claude Code adapter's `SessionStart` hook reads `~/.claude/local/accounts.config.json` and auto-switches GitHub + Supabase credentials based on the working directory.

**Syncing to multiple remotes:**
See `sync.example.sh` for a reference script that pushes the current branch to all configured git remotes with matching account switching. Adapt to your accounts config and save as `sync.sh`.

## What's NOT in This Repo

Deliberately excluded:

- **Credentials and tokens** — stored in `~/.claude/sensitive-patterns.local`, `~/.supabase/tokens/`, or environment variables
- **Project-specific rules** — each project has its own `.claude/rules/` directory
- **Machine-specific settings** — `settings.json` is generated from template, per-machine
- **Project/org IDs** — configured in `settings.json` placeholders, not committed
- **Telemetry data** — stored locally at `~/.neural-lace/telemetry/`, never committed

## Key Concepts

### Risk Dimensions

Every action is scored on six dimensions (0-4 each):

| Dimension | Question |
|-----------|----------|
| Reversibility | Can this be undone? |
| Blast Radius | How much is affected? |
| Sensitivity | Does this touch protected data? |
| Authority Escalation | Does this change permissions? |
| Novelty | Has this action been seen before? |
| Velocity | Is this part of a rapid sequence? |

### Permission Tiers

| Tier | Score | Response |
|------|-------|----------|
| T0: Silent Allow | 0-1 | Execute immediately |
| T1: Log & Allow | 1-2.5 | Execute, log prominently |
| T2: Confirm | 2.5-4 | Pause, show risk, wait for approval |
| T3: Block | 4+ | Refuse, explain why |

### Trust Accumulation

Trust (0.0-1.0) grows with safe operation and decays with incidents. Higher trust = fewer interruptions = more autonomous work. Hard blocks (credential exposure, public access) never relax regardless of trust level.

## Current Status

| Component | Status |
|-----------|--------|
| Layer 0 Principles | v1.0 |
| Layer 1 Patterns | v1.0 |
| Claude Code Adapter | v1.0 |
| Pre-commit Security Scanner | v1.0 (credentials + anti-patterns) |
| Pre-push Security Scanner | v1.0 (credentials) |
| **Agent Teams** | **feature-flagged (experimental).** To enable: see [`adapters/claude-code/rules/agent-teams.md`](adapters/claude-code/rules/agent-teams.md). |
| Risk Engine Runtime | Planned (currently using pattern-match hooks) |
| Telemetry Collectors | Planned |
| Learning Loop | Planned |
| Management UI | Planned (v2.0) |
| Codex Adapter | Planned (v1.5) |

## Documentation

| Document | Location | Covers |
|----------|----------|--------|
| **Setup Guide** | [`SETUP.md`](SETUP.md) | Fresh-install walkthrough, two-layer config customization |
| **Best Practices** | [`docs/best-practices.md`](docs/best-practices.md) | Full catalog of encoded practices + rationale |
| Strategy & Roadmap | `docs/harness-strategy.md` | Vision, milestones, security maturity model |
| Architecture | `docs/harness-architecture.md` | Hook chains, agent table, credential layers |
| Developer Guide | `docs/harness-guide.md` | File-by-file reference, setup instructions |
| Hygiene Principle | `principles/harness-hygiene.md` | No sensitive data in harness code; two-layer config |
| Team Patterns | `docs/business-patterns-workflow.md` | Sharing credential patterns across a team |
| Permission Model | `principles/permission-model.md` | Risk dimensions, scoring, tiers |
| Progressive Autonomy | `principles/progressive-autonomy.md` | Trust model, autonomy ladder |
| UX Guidelines | `docs/ux-guidelines.md` | UI design principles |
| UX Checklist | `docs/ux-checklist.md` | 22-domain UX audit checklist |

## License

[MIT](LICENSE) — free to use, fork, and modify. Contributions welcome.

