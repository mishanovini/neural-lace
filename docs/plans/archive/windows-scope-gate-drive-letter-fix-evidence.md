# Evidence Log — windows-scope-gate-drive-letter-fix

Mechanical-verification evidence for each task in `docs/plans/windows-scope-gate-drive-letter-fix.md`. All tasks declared `Verification: mechanical`; per the harness's risk-tiered-verification rule, task-verifier returns PASS immediately for mechanical tasks when the evidence file exists with matching `Task ID` and at least one `Runtime verification:` line. Tasks are left unchecked in the plan per the verifier-mandate convention (no manual checkbox flips); mechanical verification is recorded here.

---

EVIDENCE BLOCK
Task ID: 1
Verdict: PASS
Runtime verification: bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test
Self-test result: 20/20 PASS (scenarios 1-19 unchanged, no regression; scenario 20 verifies the new `_resolve_git_dir_abs` helper).
Diff evidence:
- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — new helper `_resolve_git_dir_abs` inserted at the top of the file (between `_is_system_managed_path` and the `--self-test` block) with four-branch `case` recognizing POSIX-absolute (`/*`), Windows drive-letter forward-slash (`[A-Za-z]:/*`) and backslash (`[A-Za-z]:\\*`), empty, and otherwise-relative (resolve vs repo root).
- Both inline `case` blocks that previously only matched `/*` (the rebase/merge full-skip block AND the legacy IN_MERGE block) replaced by `GIT_DIR_PATH=$(_resolve_git_dir_abs "$GIT_DIR_PATH" "$REPO_ROOT")`.
Rationale: a `case` matching only `/*` treated Windows `C:/Users/…/.git` as RELATIVE and re-prefixed it with the repo root, producing a nonexistent path. The `[[ -e "$GIT_DIR_PATH/MERGE_HEAD" ]]` check then silently never fired on Windows, so HARNESS-GAP-29's rebase/merge full-skip was lost there. The helper centralizes the resolution so both call sites cannot drift.

---

EVIDENCE BLOCK
Task ID: 2
Verdict: PASS
Runtime verification: bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test
Self-test result: scenario 20 PASS — exercises five sub-assertions on `_resolve_git_dir_abs` directly:
1. `_resolve_git_dir_abs "C:/Users/u/repo/.git" "/some/repo/root"` → `C:/Users/u/repo/.git` (drive-letter forward-slash absolute, unchanged)
2. `_resolve_git_dir_abs 'C:\Users\u\repo\.git' "/some/repo/root"` → `C:\Users\u\repo\.git` (drive-letter backslash absolute, unchanged)
3. `_resolve_git_dir_abs "/home/u/repo/.git" "/some/repo/root"` → `/home/u/repo/.git` (POSIX absolute, unchanged)
4. `_resolve_git_dir_abs ".git" "/some/repo/root"` → `/some/repo/root/.git` (relative, resolved vs root)
5. `_resolve_git_dir_abs "" "/some/repo/root"` → `` (empty stays empty)
Diff evidence:
- Scenario 20 added directly above the summary echo; total scenario count bumped 19→20 in both the header comment (`--self-test handler (twenty scenarios)`) and the summary line (`of 20 scenarios`).
Rationale: calling the helper directly (rather than mocking `git rev-parse` deep enough to produce a drive-letter path with corresponding filesystem-state for MERGE_HEAD detection) is the deterministic, platform-independent regression test for the bug's actual locus (path classification). Future drift in the helper will be caught at the next self-test invocation on any platform.

---

EVIDENCE BLOCK
Task ID: 3
Verdict: PASS
Runtime verification: file docs/backlog.md; file docs/decisions/030-scope-enforcement-gate-merge-aware-union-of-plans.md; file adapters/claude-code/rules/vaporware-prevention.md; file adapters/claude-code/rules/gate-respect.md
Diff evidence:
- `docs/backlog.md` — HARNESS-GAP-27 entry title prefixed with `[SUPERSEDED 2026-05-27 by PR #26 / HARNESS-GAP-29]`; closing sentence cites PR #26 (master `0d6bc43`) + `docs/plans/archive/scope-gate-rebase-exemption.md` + ADR 030 (resolved); option (b) union-of-plans explicitly not pursued.
- `docs/decisions/030-scope-enforcement-gate-merge-aware-union-of-plans.md` — title `(DEFERRED)` → `(SUPERSEDED)`; Status flipped to `SUPERSEDED 2026-05-27 by PR #26 (HARNESS-GAP-29, master 0d6bc43)`; blockquote supersession-note paragraph added explaining PR #26 chose a refinement of Option D (narrow, detected rebase/merge-in-progress window full-skip) rather than this ADR's union-of-plans design; "When to un-defer" triggers no longer apply.
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map row's merge paragraph rewritten to lead with HARNESS-GAP-29 full-skip (2026-05-27, PR #26) as current behavior; explicitly marks HARNESS-GAP-27 narrow migration-only exemption SUPERSEDED; notes drive-letter resolution (`_resolve_git_dir_abs`) handles POSIX + Windows; states ADR 030's union-of-plans design is consequently superseded.
- `adapters/claude-code/rules/gate-respect.md` — supersession parenthetical appended to the HARNESS-GAP-27 worked example (line 77) noting PR #26 / HARNESS-GAP-29 closed the blind-spot via full-skip and marking both HARNESS-GAP-27 and ADR 030's union-of-plans design superseded; the teaching point (fix-the-gate, not bypass-per-occurrence) is unchanged — it's exactly what landed.
Note: `docs/harness-architecture.md` line 7 already documents HARNESS-GAP-29 superseding HARNESS-GAP-27 (added by PR #26); no edit needed there. Archived plans (`docs/plans/archive/scope-gate-rebase-exemption.md`, `docs/plans/archive/session-state-refresh-2026-05-22.md`) are historical records and intentionally not edited.

---

EVIDENCE BLOCK
Task ID: 4
Verdict: PASS
Runtime verification: diff -q adapters/claude-code/hooks/scope-enforcement-gate.sh ~/.claude/hooks/scope-enforcement-gate.sh; diff -q adapters/claude-code/rules/vaporware-prevention.md ~/.claude/rules/vaporware-prevention.md; diff -q adapters/claude-code/rules/gate-respect.md ~/.claude/rules/gate-respect.md
Result: all three `diff -q` invocations returned empty stdout (byte-identical). Live `~/.claude/hooks/scope-enforcement-gate.sh` + `~/.claude/rules/vaporware-prevention.md` + `~/.claude/rules/gate-respect.md` synced from the repo canonical via `cp`. Per harness-maintenance.md two-layer config: the live mirror is what running sessions read; the repo canonical is what `install.sh` propagates to new machines. Both must agree.

---

## Summary
4/4 tasks PASS at the mechanical-verification level. The fix is a single helper-extraction + two call-site replacements + one new self-test scenario; 20/20 self-test confirms zero regression on the 19 prior scenarios and verifies the helper's contract on all four input shapes (Windows drive-letter forward/back slash, POSIX absolute, relative-vs-root, empty). Doc supersession sweep covers all four live surfaces; archived plans left untouched.
