# Local `--no-verify` friction wrapper

A local shell-function wrapper that intercepts `git commit --no-verify` (and the `-n` short form), prints a clear warning, requires an explicit confirmation string, and logs every attempt. It is one layer of a three-layer defense against pre-commit-hook bypass; see "Three-layer defense" below for how the layers compose.

## Why it exists

`git commit --no-verify` bypasses every pre-commit hook in one keystroke. The hooks are doing real work — credential scanning, harness-hygiene checks, plan-edit-validator, no-test-skip, scope enforcement. A casual `--no-verify` undoes all of it. The wrapper makes the easy thing (committing safely) easier than the wrong thing (silently bypassing) without taking away the option entirely.

The wrapper is deliberately friction, not a hard block. A determined user can still:
- Run `command git commit --no-verify ...` (skips the function)
- `unset -f git` or unalias
- Invoke `/usr/bin/git` directly

That's fine. The server-side enforcement workflow is the actual floor (see below); the wrapper exists to raise local friction so the floor doesn't have to be the only line of defense.

## Install

```bash
bash ~/claude-projects/neural-lace/adapters/claude-code/scripts/install-git-friction.sh
```

Detects bash and zsh, appends a single source-block to each detected shell's rc file. Idempotent — re-running adds nothing extra.

To verify the install:

```bash
bash ~/claude-projects/neural-lace/adapters/claude-code/scripts/install-git-friction.sh --check
```

To uninstall:

```bash
bash ~/claude-projects/neural-lace/adapters/claude-code/scripts/install-git-friction.sh --uninstall
```

After install, open a new shell or `source ~/.bashrc` / `source ~/.zshrc`. Then in any repo with unstaged changes, type:

```bash
git commit --no-verify -m "test"
```

You should see a multi-line warning and a confirmation prompt.

## What the friction prompt looks like

```
  >> --no-verify bypass detected <<

  You are about to commit with pre-commit hooks DISABLED. The local
  hook chain (credential scan, harness-hygiene, plan-edit-validator,
  no-test-skip, scope-enforcement, etc.) will NOT run on this commit.

  This is a defensive backstop, not a hard block. The server-side
  enforcement workflow still runs on push and branch-protection prevents
  the PR from merging if it fails -- so the local bypass is recoverable.

  To proceed, type the literal string below (case-sensitive, no quotes):

      I-AM-BYPASSING-SAFETY-DELIBERATELY

  Notes:
    - This attempt is logged to ~/.claude/logs/no-verify-attempts.log
    - To bypass this wrapper entirely: `command git commit --no-verify ...`

  Type confirmation >
```

If you type the literal string exactly, the commit proceeds (and is logged as `outcome: proceeded`). Any other input — including pressing Enter on an empty line — aborts the commit (logged as `outcome: aborted`).

## What gets logged

Every interception, whether proceeded or aborted, lands at `~/.claude/logs/no-verify-attempts.log` in this shape:

```
--- no-verify attempt 2026-05-23T22:30:00Z ---
cwd: /home/user/projects/some-repo
argv: git commit --no-verify -m 'wip: trying something'
outcome: proceeded (confirmation matched)
```

The log is append-only, never rotated by the wrapper, never sent anywhere. A future audit script can grep it for bypass frequency by repo / by message-shape. If it grows uncomfortable, manual `rm` is fine — the next attempt starts the file fresh.

## What is NOT intercepted

The wrapper deliberately fires ONLY on `git commit` with `--no-verify` or `-n`. It does not intercept:

- `git push --no-verify` — handled at the global pre-push level via `pre-push-scan.sh` (separate gate).
- `git rebase --no-verify` — rare; intentional when it happens.
- `git am --no-verify`, `git merge --no-verify`, etc. — out of scope.
- Non-bypass invocations — `git commit -m "..."` flows through unchanged with zero overhead.
- CI runners — they don't source the user's shell rc, so the wrapper is inert there. CI runs the server-side enforcement workflow instead, which is the right layer.

## Three-layer defense

```
+--------------------------------------------------------------+
| Layer 1: AI sessions in Claude Code                          |
|   PreToolUse Bash hook chain blocks --no-verify entirely.    |
|   AI agents cannot bypass.                                   |
+--------------------------------------------------------------+
                            v
+--------------------------------------------------------------+
| Layer 2: Human shells (with this wrapper installed)          |
|   Friction prompt + confirmation string + audit log.         |
|   Bypass is possible but visible and effortful.              |
+--------------------------------------------------------------+
                            v
+--------------------------------------------------------------+
| Layer 3: Server-side enforcement workflow                    |
|   .github/workflows/server-side-enforcement.yml runs on      |
|   every PR. Once branch-protection requires the              |
|   "All-checks summary" check, the PR cannot merge even       |
|   if Layers 1 and 2 are both bypassed.                       |
+--------------------------------------------------------------+
```

Each layer reduces the population of bypass scenarios:

- **Without any layer**: an agent or human can commit with `--no-verify`, push, and merge with zero signal that the perimeter was bypassed.
- **With Layer 1 only**: AI sessions are blocked, but humans can still bypass silently.
- **With Layers 1 + 2**: AI is blocked, humans see friction + leave an audit trail.
- **With all three**: even a determined bypass at Layers 1 and 2 cannot result in a merge that violates the gates — the server-side check refuses.

The wrapper is Layer 2. Server-side enforcement is the actual floor (Layer 3). The wrapper exists to make the floor a rare-fire safety net, not the only line of defense.

## Self-test

The wrapper's argument-detection logic and the installer's rc-file mutation logic both ship `--self-test` flags:

```bash
bash adapters/claude-code/scripts/git-no-verify-friction.sh --self-test  # 10 cases
bash adapters/claude-code/scripts/install-git-friction.sh --self-test    # 6 cases
```

Both exit 0 on success. Run them after editing either script before relying on the install.

## Cross-references

- `.github/workflows/server-side-enforcement.yml` — the Layer 3 floor (this PR introduces it).
- `adapters/claude-code/hooks/pre-push-scan.sh` — the pre-push half of the local gate chain.
- `~/.claude/rules/secret-hygiene.md` — the broader three-layer credential-leak defense (gitignore → pre-push → remote secret scanning) this wrapper composes with.
- `~/.claude/rules/gate-respect.md` — the "diagnose before bypass" discipline that documents when `--no-verify` is legitimate (rare false-positives with explicit per-occurrence user authorization).
- `~/.claude/rules/git-discipline.md` — companion rule covering force-push prohibition + post-merge sync + Stop-hook waivers.
