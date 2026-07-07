# O.5 template-wiring fragment

**None.** `ntfy-push.sh` is never invoked through `settings.json.template` (no new
hook, no new SessionStart/Stop/PreToolUse entry) — it is called (a) directly by
`needs-you.sh add`'s guarded call site, and (b) on a schedule via the per-machine
tick wrapper `.cmd` described in `scan-tick-wiring.md`. This is consistent with the
hook-budget invariants in §O.0.1 rule 8 (SessionStart at cap 8/8, Stop 4/6, blocking
gates 10/12 — Wave O adds zero new entries in any of those chains from this task).
