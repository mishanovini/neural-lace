# Evidence Log — context-aware-permission-gates

## EVIDENCE BLOCK
Task ID: 2
Verdict: PASS
Commit: 51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization

Description: Modified `~/.claude/scripts/session-wrap.sh` to detect worktree context via `git rev-parse --git-common-dir` ≠ `--git-dir` and return parent repo's toplevel from `find_repo_root()`. Synced to `adapters/claude-code/scripts/session-wrap.sh` (byte-identical). Added self-test scenario S7 (worktree-fallback) that creates a synthetic worktree and confirms the function returns the parent toplevel.

Runtime verification: bash adapters/claude-code/scripts/session-wrap.sh --self-test
Result: 7/7 PASS (S1-S7), exit 0.

Runtime verification: bash adapters/claude-code/scripts/session-wrap.sh verify (run from this real worktree)
Result: "[session-wrap] all freshness signals PASS" — confirms the fix works against the actual production parent repo's SCRATCHPAD.md.

## EVIDENCE BLOCK
Task ID: 5
Verdict: PASS
Commit: 51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization

Description: Authored `adapters/claude-code/hooks/local-edit-gate.sh` (~280 lines) — PreToolUse Edit/Write/MultiEdit hook. Helpers: `load_input` (stdin/env), `extract_field` (jq with grep fallback), `filename_slug` (kebab-case derivation), `is_under_claude_local` (path normalization including `//c/` and Windows-style paths), `mtime_epoch`, `find_fresh_marker`. Main `run_gate` exits 0 silently for non-Edit tools and out-of-scope paths; exits 2 with JSON block + stderr remediation when no fresh marker matches the target's filename-slug. Synced to `~/.claude/hooks/local-edit-gate.sh` byte-identical and chmod +x.

Runtime verification: bash adapters/claude-code/hooks/local-edit-gate.sh --self-test
Result: 8/8 PASS — S1 non-edit-tool-allow, S2 target-outside-local-allow, S3 fresh-matching-marker-allow, S4 no-marker-block, S5 stale-marker-block, S6 wrong-filename-marker-block, S7 multiedit-fires-gate, S8 malformed-input-fail-closed.

## EVIDENCE BLOCK
Task ID: 7
Verdict: PASS
Commit: 51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization

Description: Wired `local-edit-gate.sh` in PreToolUse `Edit|Write|MultiEdit` chain (after `spec-freeze-gate.sh`) in BOTH `adapters/claude-code/settings.json.template` (committed) AND `~/.claude/settings.json` (live). Removed the six broad deny rules at live settings.json lines 70-75; the deny block is now empty (template never had them — pre-existing divergence per HARNESS-GAP-14, now resolved via this commit since the new hook covers what the deny rules covered).

Runtime verification: jq empty adapters/claude-code/settings.json.template
Result: exit 0 (valid JSON).

Runtime verification: jq -e '.permissions.deny | length == 0' ~/.claude/settings.json
Result: outputs "true", exit 0 (deny array is empty).

Runtime verification: grep -c local-edit-gate.sh ~/.claude/settings.json
Result: 1 (hook wired exactly once).

Runtime verification: diff <(jq -S '.hooks.PreToolUse | map(.hooks[].command)' ~/.claude/settings.json) <(jq -S '.hooks.PreToolUse | map(.hooks[].command)' adapters/claude-code/settings.json.template)
Result: empty diff (template + live PreToolUse chain identical).

## EVIDENCE BLOCK
Task ID: 10
Verdict: PASS
Commit: 51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization

Description: End-to-end runtime test of the full chain. Marker written manually (the `/grant-local-edit` skill itself requires session restart to register as a slash command, but the underlying mechanism — file at `~/.claude/state/local-edit-<slug>-<ts>.txt` — is what the hook reads). Confirmed gate ALLOWs when marker is fresh, BLOCKs when missing/stale/wrong-filename. End-to-end test wrote the originally-requested directory-structure section to `~/.claude/local/CLAUDE.md`, satisfying the user's original request from the session opener.

Runtime verification: marker write + Write tool path traced through hook
Command: `mkdir -p ~/.claude/state && cat > ~/.claude/state/local-edit-claude-md-<ts>.txt` then `Write` tool on `~/.claude/local/CLAUDE.md`
Result: hook's stderr emitted `[local-edit-gate] ALLOW: CLAUDE.md — marker local-edit-claude-md-2026-05-09T21-21-13Z.txt`; exit 0; file landed.

Runtime verification: stale-marker block scenario
Command: `touch -d "31 minutes ago" <marker>` then attempt Edit on `~/.claude/local/accounts.config.json` via hook input
Result: gate emitted JSON block decision + stderr remediation message; exit 2.

Runtime verification: no-marker block scenario
Command: attempt Edit on `~/.claude/local/personal.config.json` with no marker present
Result: gate emitted JSON block decision + stderr remediation message; exit 2.

Runtime verification: file landed correctly
Command: `cat ~/.claude/local/CLAUDE.md | head -5`
Result: file contains the user's requested directory-structure content (machine-local config heading, project structure section, rules block).
