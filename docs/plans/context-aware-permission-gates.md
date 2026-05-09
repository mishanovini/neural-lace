# Plan: Context-aware permission gates — session-wrap worktree fall-back + local-edit authorization
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface — the change touches harness scripts, hooks, skills, and rules consumed only by Claude Code sessions.
tier: 2
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Close two adjacent harness gaps surfaced in the 2026-05-09 ad-hoc cleanup
session, both of which share the same shape: a default-block gate without
a context-aware authorized-edit path.

1. **`session-wrap.sh` worktree blind-spot** — the Stop hook reports
   absurd staleness from inside a worktree because it checks
   `<worktree-toplevel>/SCRATCHPAD.md`, but worktrees don't carry a
   SCRATCHPAD by convention; only the parent repo does. Cries-wolf
   weakens the signal everywhere.

2. **`~/.claude/local/` no-authorized-edit path** — six broad deny rules
   block agents from ever editing machine-local config files, even when
   the user has explicitly authorized the edit in the current message.
   The deny is the right default (prevents drift on credential-bearing
   files) but lacks an in-session escape hatch, forcing the user to
   hand-edit every machine-local file.

The user-observable outcome of this plan: (a) Stop hook PASSes from
worktrees without ceremony, and (b) the user can invoke
`/grant-local-edit <filename>` to authorize an agent to edit a specific
file under `~/.claude/local/` for ~30 minutes, after which the
authorization expires automatically.

## Scope
- IN:
  - Modify `adapters/claude-code/scripts/session-wrap.sh` to detect
    worktree context and use the parent repo's SCRATCHPAD when one
    differs from the worktree's toplevel.
  - Sync the script change to `~/.claude/scripts/session-wrap.sh`.
  - Author skill `adapters/claude-code/skills/grant-local-edit.md` (and
    sync to `~/.claude/skills/`) that writes a per-file authorization
    marker to `~/.claude/state/local-edit-<filename>-<ts>.txt`.
  - Author hook `adapters/claude-code/hooks/local-edit-gate.sh` (and
    sync to `~/.claude/hooks/`) that runs as PreToolUse on Edit/Write/
    MultiEdit when the target path is under `~/.claude/local/**`. Marker
    must exist for the specific filename, mtime < 30 min. Otherwise
    block with a clear "invoke /grant-local-edit <filename>" message.
  - Author rule `adapters/claude-code/rules/local-edit-authorization.md`
    (sync to `~/.claude/rules/`).
  - Wire the new hook in BOTH `adapters/claude-code/settings.json.template`
    AND `~/.claude/settings.json`.
  - Remove the six broad deny rules at `~/.claude/settings.json` lines
    70-75 (the new hook replaces them; mirror the removal in the
    template).
  - ADR 028: session-wrap.sh worktree fall-back.
  - ADR 029: local-edit authorization mechanism.
  - Update both discoveries (`2026-05-09-session-wrap-worktree-blind.md`
    and a new discovery for the local-edit mechanism if not already
    captured) with Decision + Implementation log.
  - Cross-reference both new mechanisms from
    `rules/vaporware-prevention.md` enforcement map.
- OUT:
  - Re-architecting `~/.claude/local/` itself (separate concern).
  - Tier-by-sensitivity classification of which local files need extra
    gates beyond the marker (deferred — current design treats every
    local file the same; per-file marker IS the sensitivity boundary).
  - Cross-machine syncing of grant markers (markers stay per-machine,
    just like everything else under `~/.claude/local/` and
    `~/.claude/state/`).
  - The `Claude Working Folder` allow-list cleanup spotted while
    reading settings.json (separate backlog item — flagged in
    discoveries).

## Tasks

- [ ] 1. Author ADR 028 — session-wrap.sh worktree fall-back. — Verification: contract
- [ ] 2. Modify `session-wrap.sh` `find_repo_root` to detect worktree context (via `git rev-parse --git-common-dir` ≠ `git rev-parse --git-dir`) and return parent repo's toplevel. Sync to live mirror. Extend self-test with a worktree scenario. — Verification: full
- [ ] 3. Author ADR 029 — local-edit authorization mechanism (skill + hook + per-file marker + 30-min freshness). — Verification: contract
- [ ] 4. Author skill `grant-local-edit.md` (committed + synced). The skill writes `~/.claude/state/local-edit-<filename-slug>-<ISO8601>.txt` with at least one substantive justification line. — Verification: mechanical
- [ ] 5. Author hook `local-edit-gate.sh` with `--self-test` covering 6+ scenarios (marker present + fresh, marker missing, marker stale, wrong filename, target outside `~/.claude/local/`, MultiEdit). Sync to live mirror, chmod +x. — Verification: full
- [ ] 6. Author rule `local-edit-authorization.md` documenting trigger, marker format, freshness window, scope. — Verification: mechanical
- [ ] 7. Wire hook in template + live `settings.json`; remove the six broad deny rules. — Verification: full
- [ ] 8. Cross-reference both mechanisms in `rules/vaporware-prevention.md` enforcement map. — Verification: mechanical
- [ ] 9. Update both 2026-05-09 discoveries with Decision + Implementation log; flip Status to `decided`. — Verification: mechanical
- [ ] 10. End-to-end test: invoke `/grant-local-edit CLAUDE.md`, then write the originally-requested CLAUDE.md content to `~/.claude/local/CLAUDE.md`. Verify gate allows it. Verify a SECOND edit attempt without re-granting still works (within freshness window). Verify expired marker blocks. — Verification: full
- [ ] 11. Commit, push, transition Status to COMPLETED via `close-plan.sh`. — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/scripts/session-wrap.sh` — extend `find_repo_root` for worktree fall-back; extend self-test (Task 2)
- `~/.claude/scripts/session-wrap.sh` — sync mirror (Task 2)
- `adapters/claude-code/skills/grant-local-edit.md` — new skill (Task 4)
- `~/.claude/skills/grant-local-edit.md` — sync mirror (Task 4)
- `adapters/claude-code/hooks/local-edit-gate.sh` — new PreToolUse hook (Task 5)
- `~/.claude/hooks/local-edit-gate.sh` — sync mirror (Task 5)
- `adapters/claude-code/rules/local-edit-authorization.md` — new rule (Task 6)
- `~/.claude/rules/local-edit-authorization.md` — sync mirror (Task 6)
- `adapters/claude-code/settings.json.template` — wire hook + remove deny rules (Task 7)
- `~/.claude/settings.json` — wire hook + remove deny rules (Task 7)
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map rows (Task 8)
- `~/.claude/rules/vaporware-prevention.md` — sync mirror (Task 8)
- `docs/decisions/028-session-wrap-worktree-fallback.md` — new ADR (Task 1)
- `docs/decisions/029-local-edit-authorization-mechanism.md` — new ADR (Task 3)
- `docs/DECISIONS.md` — add two index rows (Tasks 1, 3)
- `docs/discoveries/2026-05-09-session-wrap-worktree-blind.md` — Decision + Implementation log (Task 9)
- `docs/discoveries/2026-05-09-local-edit-authorization-mechanism.md` — capture this discovery if not already (Task 9)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- Claude Code's permissions model supports allow-over-deny precedence
  for narrow file paths, BUT removing the deny rules entirely (as
  designed) means the new hook is the SOLE mechanism protecting
  `~/.claude/local/`. If Claude Code introduces a bug where the hook
  fails open on certain inputs, agents could edit local config without
  authorization. Mitigation: hook fails CLOSED on any input parsing
  error.
- `git rev-parse --git-common-dir` returns the parent repo's `.git`
  directory from inside a worktree, and equals `--git-dir` when not in
  a worktree. (Confirmed manually in this session.)
- `~/.claude/state/` directory is gitignored and operational; markers
  there don't pollute git history.
- Filename slug derivation: kebab-case the basename, strip extension.
  Collisions across different files in `~/.claude/local/` with the
  same kebab-stem are unlikely (and the slug is filename-derived, not
  user-supplied, so the user can't accidentally collide).
- The user invokes `/grant-local-edit` from chat; the skill writes the
  marker; the agent THEN attempts the edit, which fires the hook,
  which finds the marker, allows the edit. Single-message ordering is
  expected to work because Claude Code processes messages sequentially.

## Edge Cases

- **Marker exists but for wrong filename.** Hook checks the marker's
  filename slug matches the target. If not, BLOCK.
- **Multiple markers for same file.** Hook accepts ANY marker for that
  filename newer than 30 min. Old markers age out naturally.
- **Marker mtime is in the future** (clock skew, manual touch). Hook
  treats as fresh (current behavior of mtime gates is to compare to
  now; a future-dated marker is fresh by definition).
- **Hook runs from a session where `$HOME` differs.** Hook resolves
  `~/.claude/state/` via `$HOME`; consistent with all other harness
  hooks.
- **User edits `~/.claude/local/personal.config.json` (credentials).**
  Same gate applies — user must invoke `/grant-local-edit personal.config.json`
  first. The marker IS the authorization. The hook does NOT add
  extra friction for "more sensitive" files in v1; if the per-file
  authorization model proves insufficient, a future iteration can add
  per-file allowlists. Decision deferred (see ADR 029 Alternatives).
- **Worktree fall-back on a non-git directory.** `find_repo_root`
  already returns empty/error in that case; behavior unchanged for
  non-git contexts.
- **Worktree fall-back when both worktree AND parent have a SCRATCHPAD.md.**
  Use the parent's. Worktree-local SCRATCHPADs are explicitly out of
  scope (orchestrator-pattern says worktrees are short-lived build
  isolation). The worktree-local SCRATCHPAD created in this session
  (as immediate workaround) becomes redundant after the hook is fixed
  and SHOULD be deleted in Task 2 cleanup.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-development; no product user).

## Out-of-scope scenarios
n/a — acceptance-exempt.

## Testing Strategy

- Each new hook ships with `--self-test` block (≥ 6 scenarios). Run
  before commit; tests must pass.
- session-wrap.sh self-test extended with worktree fall-back scenario.
- End-to-end runtime test (Task 10): in-session, invoke
  `/grant-local-edit CLAUDE.md`, then issue the Write tool call to
  `~/.claude/local/CLAUDE.md`. Capture the gate's stderr (allow vs.
  block) as evidence. Replay scenarios via `bash` commands that
  simulate stale markers (`touch -d "31 minutes ago" <marker>`) and
  capture the hook's exit code in each case.
- task-verifier invokes for each of the 11 tasks with appropriate
  verification level.

## Walking Skeleton

The smallest end-to-end vertical slice that proves the structure works:

1. Author the hook with stub allow-everything behavior.
2. Wire it in settings.json.
3. Remove the deny rules.
4. Verify a write to `~/.claude/local/CLAUDE.md` works (gate allowed).
5. Restore the gate's actual logic.
6. Verify the gate blocks without a marker.
7. Author the skill, invoke it, verify the marker appears, retry the
   write, verify it succeeds.

This proves the entire chain (deny-removed → hook fires → marker
checked → allow/block) before the rule + ADR + sync work lands.

## Decisions Log
[populated during implementation]

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code plan; pre-submission audit is design-mode-only per `~/.claude/rules/design-mode-planning.md` "When the audit doesn't apply".
- S2 (Existing-Code-Claim Verification): n/a — same.
- S3 (Cross-Section Consistency): n/a — same.
- S4 (Numeric-Parameter Sweep): n/a — same.
- S5 (Scope-vs-Analysis Check): n/a — same.

## Definition of Done
- [ ] All 11 tasks checked off (each via task-verifier per Verification level)
- [ ] Both ADRs landed and indexed in `docs/DECISIONS.md`
- [ ] Both discoveries flipped to `Status: decided` with Implementation log
- [ ] All hooks chmod +x; --self-test passes for both new/modified hooks
- [ ] settings.json template + live both updated; live deny rules at lines 70-75 removed
- [ ] End-to-end test passes (Task 10)
- [ ] Commit + push to feature branch
- [ ] Status: COMPLETED via `close-plan.sh` (auto-archives)
