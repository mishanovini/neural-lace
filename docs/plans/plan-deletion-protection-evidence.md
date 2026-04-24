# Evidence Log — plan-deletion-protection

This file documents evidence for each task in `docs/plans/plan-deletion-protection.md`. Per the harness's evidence-first protocol, the orchestrator (or task-verifier when available) flips checkboxes only after a corresponding evidence block is appended here.

---

## A.1 — Hook skeleton, tool-input parsing, exit-path contract

**Date:** 2026-04-23
**Files modified:**
- `~/.claude/hooks/plan-deletion-protection.sh` (NEW; 25KB)

**What was built:** PreToolUse Bash hook with:
- Standard Claude Code hook header (shebang, set -euo pipefail equivalent for Bash 3.2)
- Tool-input parsing via `jq -r '.tool_input.command // ""'` from stdin or `CLAUDE_TOOL_INPUT` env var (test-mode support)
- Shared functions: `emit_block(reason, detail)` (prints structured error to stderr, exits 1), `emit_warn(msg)` (prints warning to stderr, exits 0)
- Silent pass-through when no destructive pattern matched (exit 0)
- `tokenize()` / `clause_subcommand()` helpers for parsing chained commands (`&&`, `||`, `;`)

**Runtime verification:**
```bash
bash ~/.claude/hooks/plan-deletion-protection.sh --self-test
# → passed: 14 / 14, self-test: OK
```

**Verdict:** PASS

---

## A.2 — `rm` detection with precise path resolution

**Date:** 2026-04-23
**Files modified:** same hook (`detect_rm()` function)

**What was built:** Per-argv path resolution; checks each non-flag argument against `docs/plans/` (excluding `docs/plans/archive/`); BLOCKs with offending path; allows archive cleanup; ignores `-r`, `-rf`, `-f`, `-i` flags during target enumeration.

**Runtime verification:** self-test scenarios 1-4:
- `1.  rm docs/plans/foo.md → BLOCK` ✓
- `2.  rm -rf docs/plans/ → BLOCK` ✓
- `3.  rm docs/plans/archive/old.md → PASS (archive cleanup)` ✓
- `4.  rm README.md → PASS (non-plan file)` ✓

**Verdict:** PASS

---

## A.3 — `git clean` detection via dry-run probe

**Date:** 2026-04-23
**Files modified:** same hook (`detect_git_clean()` function)

**What was built:** Detects `git clean` invocations; runs dry-run probe `git clean -n [-d] [-x] [-X]` (substituting `-n` for `-f`); parses "Would remove ..." lines; checks both direct file matches and directory matches (enumerates plan files within); BLOCKs if any plan file at risk.

**Bugs discovered + fixed during build:**
1. **Combined-flag stripping bug:** initial implementation used `sed -E 's/-f//g'` which turned `-fd` into `d` (no dash), making `git clean -n d` treat `d` as a path argument instead of `-d` flag. Fixed by parsing flags character-by-character, skipping `f`, re-emitting `-d`, `-x`, `-X` as separate tokens.
2. **Find pattern bug:** initial pattern `-path '*/docs/plans/*'` required a leading slash before `docs`, which doesn't match relative paths starting with `docs/plans/` (the typical `git clean -n` output for an untracked plan file is `Would remove docs/`, leaving the find to enumerate from `docs/`). Fixed by changing pattern to `-path '*docs/plans/*'`.

**Runtime verification:** self-test scenarios 5-7:
- `5.  git clean -fd with untracked plans → BLOCK` ✓ (was failing before fix; now passes)
- `6.  git clean -fd with no plans affected → PASS` ✓
- `7.  git clean -n -d (dry-run) → PASS` ✓ (dry-run flag bypasses the block by design)

**Verdict:** PASS

---

## A.4 — `git stash` detection

**Date:** 2026-04-23
**Files modified:** same hook (`detect_git_stash()` function)

**What was built:** Detects `git stash -u`, `--include-untracked`, `git stash push -u`, `git stash push --include-untracked`. Runs `git status --porcelain`, checks for untracked entries (`^??`) matching `docs/plans/.*\.md`. BLOCKs with `git add <path>` suggestion. Stash without `-u` is allowed (doesn't affect untracked files).

**Runtime verification:** self-test scenarios 8-9:
- `8.  git stash -u with untracked plans → BLOCK` ✓
- `9.  git stash (no -u) → PASS` ✓

**Verdict:** PASS

---

## A.5 — `git checkout` / `git restore` / `git reset --hard` detection

**Date:** 2026-04-23
**Files modified:** same hook (`detect_git_discard()` function)

**What was built:** For `git checkout .`, `git restore .`, `git checkout -- docs/plans/...`, `git restore docs/plans/...` — checks `git status --porcelain` for modified entries (`^.M` or `^MM`) matching `docs/plans/.*\.md`. BLOCKs with file list. For `git reset --hard` — performs same check but emits non-blocking WARN (exit 0 with WARN message in stderr) because hard reset is commonly used intentionally.

**Runtime verification:** self-test scenarios 10-11:
- `10. git checkout . with modified plans → BLOCK` ✓
- `11. git reset --hard with modified plans → WARN (not block)` ✓

**Verdict:** PASS

---

## A.6 — `mv` restriction for plan files

**Date:** 2026-04-23
**Files modified:** same hook (`detect_mv()` function)

**What was built:** Detects `mv` and `git mv` with source under `docs/plans/` (outside `archive/`). Checks destination: if not under `docs/plans/archive/`, BLOCKs. Allows archive→archive moves and archive→active restoration.

**Runtime verification:** self-test scenarios 12-14:
- `12. mv docs/plans/foo.md docs/plans/archive/foo.md → PASS` ✓
- `13. mv docs/plans/foo.md /tmp/foo.md → BLOCK` ✓
- `14. git mv docs/plans/foo.md docs/plans/archive/foo.md → PASS` ✓

**Verdict:** PASS

---

## A.7 — `--self-test` flag with 14 scenarios

**Date:** 2026-04-23
**Files modified:** same hook (`run_self_test()` function + scenario definitions)

**What was built:** `--self-test` flag handler that constructs minimal git-init fixtures per scenario, sets up plan-file state, invokes the hook with synthetic JSON tool-input, asserts expected block/pass/warn behavior. Cleans up fixtures after each scenario. Final summary shows `passed: N / 14` with explicit FAILURES list.

**Runtime verification:**
```bash
$ bash ~/.claude/hooks/plan-deletion-protection.sh --self-test
plan-deletion-protection self-test
===================================
  ok   1   1.  rm docs/plans/foo.md → BLOCK
  ok   2   2.  rm -rf docs/plans/ → BLOCK
  ok   3   3.  rm docs/plans/archive/old.md → PASS (archive cleanup)
  ok   4   4.  rm README.md → PASS (non-plan file)
  ok   5   5.  git clean -fd with untracked plans → BLOCK
  ok   6   6.  git clean -fd with no plans affected → PASS
  ok   7   7.  git clean -n -d (dry-run) → PASS
  ok   8   8.  git stash -u with untracked plans → BLOCK
  ok   9   9.  git stash (no -u) → PASS
  ok   10  10. git checkout . with modified plans → BLOCK
  ok   11  11. git reset --hard with modified plans → WARN (not block)
  ok   12  12. mv docs/plans/foo.md docs/plans/archive/foo.md → PASS
  ok   13  13. mv docs/plans/foo.md /tmp/foo.md → BLOCK
  ok   14  14. git mv docs/plans/foo.md docs/plans/archive/foo.md → PASS
===================================
passed: 14 / 14
self-test: OK
```

**Verdict:** PASS

---

## Limitations (already in backlog)

- Task tool unavailable in dispatched sub-agent sessions — checkbox flips done by orchestrator under evidence-first protocol per `plan-edit-validator.sh` 120s freshness window.
- Phase A's first dispatch hit usage limit before mirroring/evidence; orchestrator completed the remaining steps directly (mirror + evidence + checkbox flips + commits).
