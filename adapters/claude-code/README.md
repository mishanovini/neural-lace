# adapters/claude-code — the Claude Code adapter

<!-- last-verified: 2026-07-05 (doctor-checked) -->

This directory is the entire Neural Lace payload for Claude Code: everything
under here gets synced into `~/.claude/` by `install.sh`. If you are looking
for "what does Neural Lace actually ship", this directory is the answer — the
repo root's `README.md` explains the philosophy, this one explains the
inventory and how to install/verify it.

## Install

```bash
cd adapters/claude-code
./install.sh                     # install or refresh
./install.sh --dry-run           # preview changes without applying them
./install.sh --verify            # install, then run harness-doctor.sh --quick
./install.sh --uninstall         # best-effort uninstall (restores most recent backup)
```

Re-running `install.sh` is always safe (idempotent refresh; existing files are
backed up before overwrite). `settings.json` is never overwritten unless you
pass `--replace-settings`. `~/.claude/local/` (your personal config layer) is
never touched except for `nl-repo-path`, which the installer refreshes every
run so hooks can resolve the repo root from any worktree.

## Directory inventory (as of this writing)

| Directory | Contents | Count |
|---|---|---|
| `hooks/` | Bash hooks wired to Claude Code lifecycle events (PreToolUse, PostToolUse, Stop, SessionStart, etc.) | 100 `.sh` files, 69 carry a `--self-test` |
| `agents/` | Subagent definitions (task-verifier, harness-reviewer, end-user-advocate, etc.) | 24 |
| `doctrine/` | Just-in-time doctrine files, injected by `doctrine-jit.sh` when a session touches the matching surface; generated index at `doctrine/INDEX.md` | 67 |
| `rules/` | Always-loaded operating rules (the ONLY files loaded into every session — ADR 058 D1) | `constitution.md` (budget-capped; doctor-enforced ≤ 24,000 bytes) |
| `skills/` | Claude Code skill definitions | 12 |
| `templates/` | Plan/PRD/comprehension templates | 8 |
| `schemas/` | JSON Schemas validating manifest/evidence/config artifacts | 10 |
| `scripts/` | Maintenance, checking, and generator scripts (doctor, manifest-check, gen-architecture-doc, etc.) | see individual script header comments — no separate `scripts/README.md`; each script documents itself |
| `attic/` | Retired hooks kept one release for live-session safety — see `attic/README.md` | |
| `manifest.json` | THE inventory: one entry per enforcement/doctrine unit (id, kind, hooks, events, wired_template, blocking, budget_class, honest_status) | 90 entries |
| `settings.json.template` | The hook-wiring template installed to `~/.claude/settings.json` | |

The generated, always-current version of this table (by event, by
blocking/warn, by budget class) lives at
[`docs/harness-architecture.md`](../../docs/harness-architecture.md),
regenerated from `manifest.json` by `scripts/gen-architecture-doc.sh` — this
README's counts are a point-in-time snapshot for orientation; that file is the
source of truth.

## Verify the install

```bash
bash hooks/harness-doctor.sh --quick     # <2s truth report: claimed vs actual enforcement
bash hooks/harness-doctor.sh --full      # slower: also runs every hook's --self-test
bash scripts/manifest-check.sh           # manifest <-> disk <-> template consistency
bash scripts/gen-architecture-doc.sh --check   # docs/harness-architecture.md drift check
```

## Where things are documented

- **What each mechanism enforces:** `docs/harness-architecture.md` (generated inventory) or `docs/harness-architecture-history.md` (frozen narrative history, pre-2026-07-05).
- **Why a mechanism exists / the tradeoffs:** the relevant `doctrine/<name>.md` file (see `doctrine/INDEX.md` for the id → doctrine-file mapping) or the ADR/decision record it cites.
- **How to add a new gate:** `~/.claude/doctrine/harness-dev.md` — new blocking gates require a named golden scenario, an expected false-positive rate, and a retirement condition (constitution §10).
- **Session lifecycle failure classes:** `docs/failure-modes.md`.
