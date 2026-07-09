# GH-AUTH-AUTOSWITCH-WORKORG-01 — settings.json.template fragment

Per the dispatch note, `settings.json.template` is ORCHESTRATOR-ONLY. This
fragment names the exact hook entry the orchestrator should add.

## NEW entry — PreToolUse, matcher "Bash"

Insert alongside the existing `gh-account-blindness-hint.sh` PreToolUse-shaped
entries. Recommended position: immediately BEFORE the existing
`gh-account-blindness-hint.sh` PostToolUse `"Bash"` matcher block (so the
proactive switch runs ahead of the reactive advisory in read order — no
functional ordering dependency between the two, they react to different
events, but grouping them together in the file aids readability for anyone
auditing the dual-account mechanism).

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/gh-account-autoswitch.sh"
    }
  ]
}
```

Add this as its own PreToolUse array entry (matching the existing convention
of one hook per matcher block, e.g. the `wire-check-gate.sh` / `spec-freeze-gate.sh`
/ `local-edit-gate.sh` entries already in the `"Edit|Write|MultiEdit"` PreToolUse
section) — do NOT merge it into an existing `"Bash"` matcher block's `hooks[]`
array unless the orchestrator has verified execution order does not matter for
the other hooks sharing that matcher (it doesn't here, since gh-account-autoswitch.sh
only ever exits 0 and never emits blocking output, but the convention in this
file is one-hook-per-matcher-object regardless).

## Budget accounting

This adds ONE new PreToolUse entry (matcher "Bash"). It does not touch
SessionStart, Stop, or any blocking-gate budget — `blocking: false`,
`budget_class: "pretool"` (advisory/preparatory, never denies). If the
harness tracks a PreToolUse "Bash" matcher count budget, this is +1 to
that count; the existing `gh-account-blindness-hint.sh` PostToolUse
entry is unaffected (different event).

## No other settings.json.template changes

No SessionStart change: the existing inline directory-based switcher
(`nl_accounts_match_dir "$PWD"` command block) and the
`gh-account-blindness-hint.sh --session-start` L2 broadcast are both
untouched — this task's design explicitly leaves the SessionStart
directory-default as the authority at session start (see the hook file's
own header, "DESIGN CHOICE — leave-on-target").
