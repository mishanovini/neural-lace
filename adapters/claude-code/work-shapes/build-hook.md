---
shape_id: build-hook
category: hook
required_files:
  - "adapters/claude-code/hooks/<name>.sh"
  - "~/.claude/hooks/<name>.sh"
  - "settings.json.template entry wiring the hook to its event"
mechanical_checks:
  - "test -x adapters/claude-code/hooks/<name>.sh"
  - "bash adapters/claude-code/hooks/<name>.sh --self-test 2>&1 | grep -F 'self-test: OK'"
  - "diff -q adapters/claude-code/hooks/<name>.sh ~/.claude/hooks/<name>.sh"
  - "grep -q '<name>.sh' adapters/claude-code/settings.json.template"
worked_example: adapters/claude-code/hooks/harness-hygiene-scan.sh
---

# Work Shape — Build Hook

## When to use

When the work creates or modifies a Claude Code hook script — a bash file under `adapters/claude-code/hooks/` invoked by Claude Code at a defined event boundary (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, `TaskCreated`, `TaskCompleted`, etc.). Hooks fire mechanically; their behavior cannot rely on agent discipline.

This shape composes the `write-self-test` shape inline — every hook ships with `--self-test`.

## Structure

A compliant hook produces three artifacts:

1. **The script itself** at `adapters/claude-code/hooks/<name>.sh`. Conventions:
   - Header comment block: classification, purpose, invocation modes, exempt paths, override semantics.
   - `#!/bin/bash` shebang; `set -euo pipefail` near top (or document why not).
   - At least four invocation modes covered in the header: pre-commit / event firing, full-tree or repeat invocation, specific-files (when applicable), `--self-test`.
   - Exit codes: `0` allow, `2` block (PreToolUse semantics) or generic non-zero for other events.
   - Error / block messages on stderr, with concrete remediation pointers.
2. **Live mirror** at `~/.claude/hooks/<name>.sh`, byte-identical to the canonical.
3. **`settings.json.template` wiring** under the appropriate event-matcher chain so Claude Code invokes the hook at runtime.

## Common pitfalls

- **Forgetting the live mirror.** Two-layer config: editing only the template leaves the running session reading the old version. Sync via `cp` or `install.sh` and verify `diff -q`.
- **No `--self-test` block.** Hooks without self-tests cannot be regression-tested when adjacent code changes. The `write-self-test` shape is mandatory.
- **stderr block message lacks remediation.** "BLOCKED" without "to proceed: do X" forces the user to read the source.
- **Hard-coded absolute paths.** Use `$HOME`, `$REPO_ROOT`, or relative paths discovered at invocation time; never `/Users/<name>/...`.
- **Pane-based teammate visibility (Agent Teams mode).** If the hook depends on parent-process visibility, document the mode-degradation per upstream Anthropic #24175.
- **No JSON output for PreToolUse decisions.** Modern hooks emit `{"decision": "block", "reason": "..."}` JSON in addition to stderr — the JSON is the structured channel.

## Worked example walk-through

`adapters/claude-code/hooks/harness-hygiene-scan.sh` exemplifies the shape:

- Header documents four invocation modes (pre-commit / `--full-tree` / specific files / `--self-test`).
- Exempt paths enumerated upfront (denylist file, SCRATCHPAD, `*.example`).
- Loads patterns from `adapters/claude-code/patterns/harness-denylist.txt` rather than embedding regexes — separation of mechanism and policy.
- `--self-test` exercises pass/fail scenarios with synthetic content, prints `self-test: OK` or `FAIL`.
- Lives at canonical + live-mirror locations; install.sh copies one to the other.
- Wired in `settings.json.template` under `hooks.PreToolUse.<bash matcher>`.
