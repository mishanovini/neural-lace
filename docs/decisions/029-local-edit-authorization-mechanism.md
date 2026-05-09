# Decision 029 — Local-edit authorization mechanism (skill + hook + per-file marker)

- **Date:** 2026-05-09
- **Status:** Active
- **Stakeholders:** harness maintainer; every Claude Code session that needs to edit a file under `~/.claude/local/`

## Context

`~/.claude/local/` holds machine-local config: `accounts.config.json` (GitHub username + Supabase token mapping per directory), `personal.config.json`, `projects.config.json` (directory-to-account routing), `automation-mode.json`, `effort-policy.json.example`, and now `CLAUDE.md` (machine-local notes per the user's 2026-05-09 directive).

Six broad deny rules in `~/.claude/settings.json` block Edit/Write/MultiEdit on `~/.claude/local/**`. The deny is the right *default* — these files include credential-bearing config; agents drifting them silently is the failure mode the deny prevents. But the default has no escape hatch: when the user explicitly authorizes an edit in the current message, the agent still cannot perform it. The user has to hand-edit, which:

1. Wastes the user's time on edits the agent could perform safely.
2. Surfaces a friction-only failure mode (the agent has to surface "I can't do this" and ask the user to do it manually).
3. Is inconsistent with how the harness handles other default-block gates: `bug-persistence-gate` accepts session-scoped waiver markers; `dag-review-waiver-gate` accepts per-session approval markers; `tool-call-budget` accepts audit-pending flags. Local-edit is the outlier — default-block with no in-band authorized path.

The 2026-05-09 cleanup session surfaced this when the user asked the agent to add a directory-structure convention to `~/.claude/local/CLAUDE.md` and the agent could not.

## Decision

The mechanism mirrors the existing fresh-marker pattern used by `bug-persistence-gate.sh` and `dag-review-waiver-gate.sh`:

1. **Skill `/grant-local-edit <filename>`** writes a marker to `~/.claude/state/local-edit-<filename-slug>-<ISO8601>.txt` containing the user's stated authorization rationale.
2. **PreToolUse hook `local-edit-gate.sh`** fires on Edit/Write/MultiEdit when the target path is under `~/.claude/local/**`. The hook checks `~/.claude/state/` for a marker matching the target's filename-slug, mtime within 30 minutes. If found, allow. Otherwise BLOCK with a clear "invoke `/grant-local-edit <filename>` first" message.
3. **The six broad deny rules at lines 70-75 of `~/.claude/settings.json` are removed.** The hook is the sole protection.
4. **Markers are per-file, not session-global.** Authorizing edit of `CLAUDE.md` does NOT authorize edit of `accounts.config.json`; the user must invoke `/grant-local-edit` separately for each.
5. **Markers expire after 30 minutes** by mtime check. Stale markers are ignored (and may be cleaned up periodically by an unrelated state-cleanup hook).

The 30-minute window is consistent with other harness fresh-marker gates (`bug-persistence-gate`'s waivers, `tool-call-budget`'s audit-pending flag).

## Alternatives Considered

- **Option A — Narrow file-specific allow rules above the deny.** Add `Write(~/.claude/local/CLAUDE.md)` etc. above the deny block; rely on Claude Code's allow-over-deny precedence. **Rejected** because (a) doesn't scale: every new local file the user wants editable requires a settings.json edit; (b) once allowed, the agent can edit that file unattended forever (no session scoping); (c) different shape from the rest of the harness's default-block gates.
- **Option B — Tier the deny by sensitivity.** Replace the broad deny with file-specific denies on credential-bearing files only (`accounts.config.json`, `personal.config.json`); leave others freely editable. **Rejected** because (a) requires file-by-file classification and re-classification as new local files appear; (b) misclassification is silent (agent gains write access to a file we didn't intend); (c) doesn't address the "session-scoped authorization" goal — it just shifts the line of what's freely-edited.
- **Option D — Always-prompt mode.** Remove the deny entirely; rely on Claude Code's runtime permission prompt for every edit. **Rejected** because (a) the deny exists explicitly to prevent the agent from prompting on EVERY local-config touch the agent might consider; (b) prompts trained the user to click-through.
- **Option E — Dedicated MCP server / tool.** Build a separate tool the agent calls explicitly when the user authorizes a local edit. **Rejected as v1** because the existing skill+hook+marker pattern is well-understood and consistent with the rest of the harness; new tooling adds dependency surface for a problem an existing pattern solves.

## Consequences

- **Enables:** the user can authorize a one-shot local-config edit without hand-editing files. Authorization is auditable (markers are dated artifacts in `~/.claude/state/`) and session-scoped (markers expire after 30 min).
- **Costs:** one new skill (~100 lines), one new hook (~150 lines + self-tests), one new rule doc, removal of 6 deny rules, settings.json wiring. Per local-config edit, the user invokes the skill once before issuing the edit instruction (vs. zero ceremony when allow rules are wide-open and zero-edits-possible when deny is hard).
- **Reversibility:** medium-low. The deny rules can be restored from git history; the skill/hook/rule files can be deleted. Markers in `~/.claude/state/` would persist but become inert (the hook that reads them wouldn't exist). Single-commit revert.
- **Side-effects:** the hook fires on every Edit/Write/MultiEdit attempt but exits silently for paths outside `~/.claude/local/**`. Performance overhead is negligible (one path check + at most one ls of `~/.claude/state/`).
- **Security profile:** the marker's only authentication is mtime + filename-slug match. An adversary with write access to `~/.claude/state/` can forge a marker. This is the same trust model as the other fresh-marker gates — they all assume `~/.claude/state/` is operator-controlled. For credential-bearing files (`accounts.config.json`, `personal.config.json`), the marker provides the same authorization friction as for other files; if higher friction proves necessary in practice, a per-file allowlist (sub-decision deferred) can be added later.

## Implementation reference

- Skill: `adapters/claude-code/skills/grant-local-edit.md` → `~/.claude/skills/grant-local-edit.md`
- Hook: `adapters/claude-code/hooks/local-edit-gate.sh` → `~/.claude/hooks/local-edit-gate.sh`
- Rule: `adapters/claude-code/rules/local-edit-authorization.md` → `~/.claude/rules/local-edit-authorization.md`
- Wiring: `adapters/claude-code/settings.json.template` + `~/.claude/settings.json` — PreToolUse Edit|Write|MultiEdit; remove deny rules at lines 70-75 (live).
- Cross-reference: `adapters/claude-code/rules/vaporware-prevention.md` enforcement map.
