# Contributing to Neural Lace

Neural Lace is a harness for AI-assisted development. It is also itself a project under active development. This document explains how to work ON Neural Lace (not just how to use it).

## Neural Lace Has Two Identities

Neural Lace is both:

1. **A distributable harness kit** — code that gets installed into other developers' `~/.claude/` via `install.sh`. This layer must be identifier-free, generic, and safely shareable.
2. **A project with its own development work** — improving hooks, writing new rules, adding agents, fixing bugs. This development generates plans, decisions, and reviews like any other project.

Both identities coexist in the same repo. Understanding which identity a given file belongs to determines where it lives and how it's treated.

## Directory Semantics

### Files that BOTH identities share — sanitization required

These files are:
- Committed to the repo
- Shipped to downstream users via `install.sh`
- Scanned by `adapters/claude-code/hooks/harness-hygiene-scan.sh` at pre-commit time
- Required to contain NO personal names, company names, real email addresses, absolute paths with usernames, or identifiable incident details

Locations: `principles/`, `patterns/`, `adapters/`, `templates/`, `docs/best-practices.md`, `docs/harness-architecture.md`, `docs/harness-strategy.md`, `docs/harness-guide.md`, `README.md`, `SETUP.md`, `CONTRIBUTING.md`, and anything under `install.sh` or `scripts/`.

### Files that are for Neural Lace's OWN development — committed, scanned, but not shipped

These files are:
- Committed to the repo (tracked by git)
- NOT shipped to downstream users (they're not referenced by `install.sh`)
- Scanned by `harness-hygiene-scan.sh` (plans and documentation go through the same identifier check as other committed files)
- Required to be sanitized — use `the maintainer` or role nouns, not personal names

Locations: `docs/plans/`, `docs/backlog.md`, and anything tracking harness-dev work.

### Files that are purely local / ephemeral — gitignored

These files are:
- NOT committed (in `.gitignore`)
- Generated during a session or containing per-machine state
- May contain identifiers without triggering any check because they never enter the repo

Locations: `docs/decisions/`, `docs/reviews/`, `docs/sessions/`, `SCRATCHPAD.md`, and anything under `adapters/claude-code/settings.json` (the personal copy — the committed template is `settings.json.template`).

> Historical note: `docs/plans/` used to be in this category. It was moved to the "committed but scanned" category on 2026-04-23 after it became clear that Neural Lace's own development produces plans that need tracking. Keeping plans outside the repo led to plan files being lost to concurrent-session git operations. See `docs/backlog.md` for the incident record.

## Working on Neural Lace

### When you want to improve the harness itself

1. **Write a plan.** Put it in `docs/plans/<slug>.md` (committed, scanned). Use `templates/plan-template.md` as a starting point. Plans must include the required sections (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy) — this is enforced by `adapters/claude-code/hooks/plan-reviewer.sh`.

2. **Commit the plan immediately on creation.** This protects against concurrent-session wipes. The `plan-lifecycle.sh` hook (in development; see `docs/backlog.md`) will automate this.

3. **Execute the plan.** Make the changes in `~/.claude/` first (live), then mirror to `adapters/claude-code/` (tracked). Run `diff -q` to verify the mirror is clean.

4. **Respect the denylist at commit.** Plan files get scanned. Use `the maintainer` or role nouns. Strip product codenames and personal details.

5. **When the plan is COMPLETED / DEFERRED / ABANDONED / SUPERSEDED:** move the file to `docs/plans/archive/`. This will be automated by `plan-lifecycle.sh`.

### When you want to use Neural Lace in a project

Don't commit plans to the neural-lace repo. Commit them to your project's own repo. See `~/.claude/rules/planning.md` for the project-level planning protocol.

## Installation Flow (for reference)

`install.sh` copies files from `adapters/claude-code/` into `~/.claude/`:

- `adapters/claude-code/hooks/*.sh` → `~/.claude/hooks/`
- `adapters/claude-code/rules/*.md` → `~/.claude/rules/`
- `adapters/claude-code/agents/*.md` → `~/.claude/agents/`
- `adapters/claude-code/templates/*.md` → `~/.claude/templates/`
- `adapters/claude-code/skills/` → `~/.claude/skills/`
- `adapters/claude-code/docs/*.md` → `~/.claude/docs/`
- `adapters/claude-code/settings.json.template` → `~/.claude/settings.json` (only if user-settings doesn't exist; template changes get written as `.example` files to avoid clobbering user customization)

Files in `docs/plans/`, `docs/backlog.md`, and everything in section "gitignored" above are NOT copied. They are Neural Lace's own development artifacts and have no role in downstream users' installations.

## When You Hit a Harness-Hygiene Violation

The pre-commit scanner will block commits that match the denylist. Typical fixes:

- Replace personal names with `the maintainer` or a role noun.
- Replace product codenames with generic terms like "a project."
- Replace absolute paths containing a username with `$HOME` / `~/` / relative paths.
- Remove real email addresses (use `test@example.com` for fixtures).

If the match is a false positive, update the scanner's allowlist rather than bypassing with `--no-verify`. Bypassing hooks should never ship.

## Changes to `~/.claude/` Must Sync Back

If you edit files in `~/.claude/` (for testing or live debugging), sync them back to `adapters/claude-code/` before committing. The `check-harness-sync.sh` pre-commit hook catches drift between installed and source copies.

See `~/.claude/rules/harness-maintenance.md` for the full sync protocol.

## Where to Track What

- **New feature ideas or bugs:** `docs/backlog.md` (prioritized P0/P1/P2)
- **Active plans:** `docs/plans/*.md`
- **Completed/archived plans:** `docs/plans/archive/*.md`
- **Decisions that affect harness architecture:** `docs/decisions/NNN-*.md` (local-only; not committed — but a summary should be added to `docs/harness-architecture.md` if architecturally relevant)
- **Session retrospectives, incident reviews:** `docs/reviews/YYYY-MM-DD-*.md` (local-only)
- **Working state for the current session:** `SCRATCHPAD.md` (local-only, ephemeral)

## Recommended Workflow

1. Pull latest from git.
2. Read `docs/backlog.md` for prioritized work items.
3. Pick an item; write a plan in `docs/plans/<slug>.md`; commit the plan immediately.
4. Execute per the plan. Make changes in `~/.claude/` live, mirror to `adapters/claude-code/`, verify with `diff -q`, commit.
5. Run relevant hook self-tests (e.g., `bash adapters/claude-code/hooks/<hook-name>.sh --self-test`).
6. Push to all configured remotes as appropriate (this repo may have multiple — check `git remote -v`).

## Reference Docs

- `README.md` — what Neural Lace is (for users and readers)
- `SETUP.md` — installation instructions
- `docs/harness-strategy.md` — design philosophy and roadmap
- `docs/harness-architecture.md` — concrete enforcement inventory (current Gen 4+)
- `docs/best-practices.md` — the 25+ codified best practices with enforcement links
- `docs/claude-code-quality-strategy.md` — strategy for getting high-quality output from Claude Code (four core beliefs + automation maturity model)
- `principles/harness-hygiene.md` — the identifier-free / two-layer-config rules
- `~/.claude/rules/harness-maintenance.md` — sync protocol between `~/.claude/` and this repo
