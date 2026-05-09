---
title: ~/.claude/local/ has no authorized-edit path
date: 2026-05-09
type: process
status: implemented
auto_applied: false
originating_context: ad-hoc cleanup session — user asked agent to add directory-structure section to ~/.claude/local/CLAUDE.md, agent could not because of broad deny rules
decision_needed: n/a — user authorized option C (session-scoped marker authorization)
predicted_downstream:
  - adapters/claude-code/skills/grant-local-edit.md
  - adapters/claude-code/hooks/local-edit-gate.sh
  - adapters/claude-code/rules/local-edit-authorization.md
  - adapters/claude-code/settings.json.template
  - ~/.claude/settings.json (live)
  - adapters/claude-code/rules/vaporware-prevention.md (enforcement-map row)
---

## What was discovered

`~/.claude/settings.json` carried six broad deny rules at lines 70-75
blocking Edit/Write/MultiEdit on `~/.claude/local/**` (both `~/` and
absolute path forms). The deny was the right *default* —
those files include credential-bearing config (`accounts.config.json`,
`personal.config.json`) that agents must not silently drift. But the
default had no escape hatch: when the user explicitly authorized an
edit in the current message, the agent still could not perform it.

This is the outlier shape vs. the rest of the harness:
- `bug-persistence-gate.sh` accepts session-scoped waiver markers.
- `dag-review-waiver-gate.sh` accepts per-session approval markers.
- `tool-call-budget.sh` accepts audit-pending flags.
- Local-edit was default-block with NO in-band authorized path.

The 2026-05-09 cleanup session surfaced this when the user asked the
agent to add a directory-structure convention to
`~/.claude/local/CLAUDE.md` and the agent had to surface "I can't do
this; please paste it manually."

## Why it matters

- Wastes user's time on edits the agent could perform safely.
- Surfaces a friction-only failure mode (agent has to surface "I can't"
  and ask the user to do it manually).
- Inconsistent with rest of harness's default-block + session-marker
  pattern.

## Options

### A. Narrow file-specific allow rules above the deny

Add `Write(~/.claude/local/CLAUDE.md)` etc. above the deny block.

- **Cost:** doesn't scale; settings.json edit per file; once allowed,
  agent edits unattended forever.
- **Benefit:** zero new mechanism.

### B. Tier the deny by sensitivity

Replace broad deny with file-specific denies on credential-bearing
files only.

- **Cost:** file-by-file classification; misclassification is silent.
- **Benefit:** non-credential files become freely editable.

### C. Session-scoped authorization marker (Recommended)

Skill `/grant-local-edit <filename>` writes per-file marker; hook
`local-edit-gate.sh` checks marker freshness on Edit/Write/MultiEdit;
broad deny rules removed.

- **Cost:** ~250 lines bash + skill + rule + ADR + settings wiring.
- **Benefit:** scalable, session-scoped, audit-trailed, consistent
  with rest of harness's fresh-marker pattern.

## Recommendation

C — session-scoped marker authorization.

Principle: machine-local config edits are exactly the case the harness
already solves elsewhere — default-block, session-scoped escape,
audit-trailed. Adding it for `~/.claude/local/` keeps the substrate
consistent rather than inventing a new shape.

## Decision

C. User authorized in 2026-05-09 session ("let's go with your
recommendations") after seeing options A/B/C with rationale.

Documented as ADR 029
(`docs/decisions/029-local-edit-authorization-mechanism.md`).

## Implementation log

- `~/.claude/skills/grant-local-edit.md` + `adapters/claude-code/skills/grant-local-edit.md`
  — new skill describing marker authoring (synced byte-identical).
- `~/.claude/hooks/local-edit-gate.sh` + `adapters/claude-code/hooks/local-edit-gate.sh`
  — new PreToolUse Edit/Write/MultiEdit gate; reads marker from
  `~/.claude/state/local-edit-<slug>-*.txt`; mtime within 30 min;
  filename-slug match. Self-test 8/8 PASS (S1 non-edit-tool, S2
  outside-local, S3 fresh-matching, S4 no-marker, S5 stale, S6
  wrong-filename, S7 multiedit, S8 malformed-input-fail-closed).
  chmod +x.
- `~/.claude/rules/local-edit-authorization.md` + `adapters/claude-code/rules/local-edit-authorization.md`
  — new rule (stub-style; mechanism enforced by hook).
- `~/.claude/settings.json` — six deny rules at lines 70-75 removed
  (deny array now empty); local-edit-gate.sh wired in PreToolUse
  Edit|Write|MultiEdit chain after spec-freeze-gate.sh. JSON validated.
- `adapters/claude-code/settings.json.template` — same hook wired in
  matching position; template never had the deny rules so no
  removal needed.
- `~/.claude/rules/vaporware-prevention.md` + adapter mirror —
  enforcement-map row added.
- End-to-end test verified in this session: marker written manually
  (skill needs session restart to register), Write tool invoked on
  `~/.claude/local/CLAUDE.md`, gate ALLOWed, file landed with the
  user's originally-requested directory-structure content. Block
  behavior verified for stale + missing markers (gate exits 2 with
  JSON decision + stderr remediation message).