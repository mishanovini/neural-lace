# O.1 template-wiring fragment

**None.** Per specs-o §O.0.1 rule 8 (hook-budget invariants are
doctor-enforced, F.1) and §O.1 deliverable 5: SessionStart is at cap
(8/8) and Stop is 4/6 — this task adds ZERO new settings.json.template
entries. Every emit call this task added lives INSIDE an already-wired
hook's existing invocation (`session-start-digest.sh`'s SessionStart
entry, `stop-verdict-dispatcher.sh` and `workstreams-stop-writer.sh`'s
Stop entries, `pre-compact-continuity.sh`'s PreCompact entries,
`workstreams-emit.sh`'s PreToolUse/PostToolUse entries) — no new
chain member, no new matcher, no new hook registration of any kind.
`scripts/session-resumer.sh` is schtasks-registered (not a
settings.json hook) and its registration is unaffected (only its
internal ledger-event vocabulary changed).
