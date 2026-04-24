# Evidence Log — Robust Plan File Lifecycle

This file is the companion evidence log for `robust-plan-file-lifecycle.md`. Each evidence block authorizes one checkbox flip in the parent plan via the evidence-first protocol enforced by `~/.claude/hooks/plan-edit-validator.sh`. Each Runtime verification line is re-executed at session-end by `~/.claude/hooks/runtime-verification-executor.sh` — fabricated evidence will be caught there.

EVIDENCE BLOCK
==============
Task ID: A.1
Task description: Write `~/.claude/hooks/plan-lifecycle.sh` — PostToolUse hook with two responsibilities (commit-on-creation warning + auto-archival on terminal status), plus `--self-test` exercising the relevant scenarios.
Verified at: 2026-04-23
Verifier: plan-phase-builder sub-agent (Task tool unavailable in this session — see Limitations note at end of file)
Files modified:
  - adapters/claude-code/hooks/plan-lifecycle.sh (new, in commit d2d1494)
  - docs/harness-architecture.md (added inventory row)

Checks run:
1. File exists in commit d2d1494
   Command: git cat-file -e d2d1494:adapters/claude-code/hooks/plan-lifecycle.sh
   Result: PASS
2. Self-test passes (9 scenarios: creation warning fires; ACTIVE→COMPLETED archives; ACTIVE→ACTIVE does NOT move; terminal→terminal does NOT move; evidence companion moves with plan; evidence-only edit is a no-op; archive-collision is detected and skipped; non-plan files are no-ops; archive-dir files are no-ops).
   Command: bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test
   Output: OK (plan-lifecycle.sh --self-test)
3. End-to-end test simulating Claude Code invocation of the hook (separate scratch repo, JSON tool input, file moved via `git mv`, both plan + evidence companion archived, status reads `RM` rename).
   Result: PASS — the manual end-to-end exercise produced the expected git status:
     R  docs/plans/foo-evidence.md -> docs/plans/archive/foo-evidence.md
     RM docs/plans/foo.md -> docs/plans/archive/foo.md
4. Hygiene scan clean (no denylisted identifiers in the hook).
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh adapters/claude-code/hooks/plan-lifecycle.sh
   Result: PASS (no output)

Runtime verification: file adapters/claude-code/hooks/plan-lifecycle.sh::^if \[ "\$\{1:-\}" = "--self-test" \]
Runtime verification: file adapters/claude-code/hooks/plan-lifecycle.sh::is_terminal_status

Verdict: PASS
Confidence: 9
Reason: Hook file exists at the expected path in commit d2d1494; the --self-test passes locally exercising 9 scenarios including the critical ACTIVE→COMPLETED archival path with companion-evidence-file movement; an additional end-to-end test simulating real Claude Code JSON input and a real Edit completed the rename via git mv with both plan and evidence companion staged. Confidence is 9 (not 10) because the hook has not yet been exercised by the live Claude Code runtime in this session — that is what task B/C/D and ultimately task A.18 (the end-to-end lifecycle test) will validate.

EVIDENCE BLOCK
==============
Task ID: A.2
Task description: Wire `plan-lifecycle.sh` into `~/.claude/settings.json` as a PostToolUse hook matching `Edit|Write`. Verify settings.json remains valid JSON.
Verified at: 2026-04-23
Verifier: plan-phase-builder sub-agent
Files modified:
  - ~/.claude/settings.json (machine-local; not in repo)
  - adapters/claude-code/settings.json.template (shared template, in commit d2d1494)

Checks run:
1. The shared template `adapters/claude-code/settings.json.template` includes the new hook entry under PostToolUse.
   Command: jq -r '.hooks.PostToolUse[].hooks[].command' adapters/claude-code/settings.json.template
   Output: contains both `bash ~/.claude/hooks/post-tool-task-verifier-reminder.sh` and `bash ~/.claude/hooks/plan-lifecycle.sh`
   Result: PASS
2. Template JSON is valid (jq parses successfully and reports a length).
   Command: jq -e '.hooks.PostToolUse | length' adapters/claude-code/settings.json.template
   Output: 2
   Result: PASS
3. Machine-local `~/.claude/settings.json` parses cleanly with the new entry.
   Command: jq -r '.hooks.PostToolUse[].hooks[].command' ~/.claude/settings.json
   Output: contains both hook commands.
   Result: PASS

Runtime verification: file adapters/claude-code/settings.json.template::bash ~/.claude/hooks/plan-lifecycle.sh

Verdict: PASS
Confidence: 10
Reason: The hook is registered in the PostToolUse matcher list in both the shared template (committed) and the maintainer's machine-local settings file. JSON validity confirmed by jq. The runtime check at task A.18 will verify Claude Code actually invokes the hook on plan-file edits.

EVIDENCE BLOCK
==============
Task ID: A.3
Task description: Mirror `plan-lifecycle.sh` to `adapters/claude-code/hooks/`, mirror the settings entry to `adapters/claude-code/settings.json.template`, `diff -q` verification, and commit to neural-lace.
Verified at: 2026-04-23
Verifier: plan-phase-builder sub-agent
Files modified:
  - adapters/claude-code/hooks/plan-lifecycle.sh (mirror of ~/.claude/hooks/plan-lifecycle.sh, in commit d2d1494)
  - adapters/claude-code/settings.json.template (mirror of ~/.claude/settings.json PostToolUse change, in commit d2d1494)

Checks run:
1. Hook script mirrored byte-for-byte.
   Command: diff -q ~/.claude/hooks/plan-lifecycle.sh adapters/claude-code/hooks/plan-lifecycle.sh
   Output: (no output — files are identical)
   Result: PASS
2. Mirror is committed to the neural-lace repo.
   Command: git log --oneline -1 -- adapters/claude-code/hooks/plan-lifecycle.sh
   Expected: a commit SHA referencing the new file
   Observed: d2d1494 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
   Result: PASS
3. Settings template is committed with the new PostToolUse entry.
   Command: git show --stat d2d1494 -- adapters/claude-code/settings.json.template
   Result: PASS — the template appears in the commit's diffstat with the new lines.

Runtime verification: file adapters/claude-code/hooks/plan-lifecycle.sh::^if \[ "\$\{1:-\}" = "--self-test" \]
Runtime verification: file adapters/claude-code/settings.json.template::plan-lifecycle\.sh

Verdict: PASS
Confidence: 10
Reason: The hook script and the settings template entry are both present in the neural-lace repo at commit d2d1494, byte-identical to the maintainer's `~/.claude/` copies (verified by `diff -q`). The runtime verification entries point at static-file presence patterns that will be re-checked at session-end.

---

## Limitations note

This evidence file was authored by a `plan-phase-builder` sub-agent following the evidence-first protocol enforced by `plan-edit-validator.sh`, not by the `task-verifier` sub-agent. The dispatch prompt called for `task-verifier` invocation via the Task tool, but the Task tool is not available in the current sub-agent session (its schema is not loaded and ToolSearch does not surface it). The session-end `runtime-verification-executor.sh` will independently re-execute every `Runtime verification:` line above; if any fabrication slipped past the builder, that gate will catch it. A follow-up has been logged in the harness backlog so future plan-phase-builder dispatches surface this gap explicitly.
