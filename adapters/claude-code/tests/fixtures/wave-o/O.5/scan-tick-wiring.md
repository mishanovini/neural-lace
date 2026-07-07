# O.5 scan-tick wiring (for the orchestrator's per-machine registration pass)

Per §O.0.1 rule 7/§O.5 deliverable 3: this is a PER-MACHINE, orchestrator-applied
change — a builder never edits scheduled-task registration or a live `.cmd` wrapper.
This fragment names the exact one-line addition and the reasoning; no task-verifier
checkbox depends on it (§O.5's own self-test + livesmoke already prove `scan` works
correctly when invoked — this fragment is purely the "make it tick every 5 minutes"
step).

## What to add

One line appended to the body of the **existing** 5-minute heartbeat tick wrapper
`.cmd` (the wrapper this wave's O.2 task registers per
`docs/runbooks/session-resumer.md` §"Registration pattern (REQUIRED — quoting lesson
2026-07-06)" — schtasks collapses nested quotes, so the tick body must live in a
`.cmd` file under `%USERPROFILE%\.claude\scripts\`, never inlined into `/TR`):

```
"C:\Program Files\Git\bin\bash.exe" -c "export PATH=/usr/bin:/mingw64/bin:$PATH; cd '<nl-repo-root-msys>' && bash adapters/claude-code/scripts/ntfy-push.sh scan >> <log> 2>&1"
```

Append this as an additional statement in the SAME wrapper `.cmd` the heartbeat tick
already runs (do not create a second scheduled task — §O.5 spec is explicit: "no new
scheduled task"). The exact invocation is the flagless shape self-tested by this
task's T12 scenario: `ntfy-push.sh scan`, no CLI flags, real production paths (the
script resolves `$HOME/.claude/state/ntfy`, `$HOME/.claude/state/needs-you`,
`$HOME/.claude/state/heartbeats`, `$HOME/.claude/state/digest/doctor-cache.json`, and
`$HOME/.claude/local/ntfy-topic` on its own — no env vars needed at the call site).

## Sequencing dependency (orchestrator TODO)

This wrapper `.cmd` does not exist yet as of this task's build (O.2 — the session-
heartbeat tick that owns it — is a sibling batch-1 task building in parallel; the
wrapper is created when O.2's own registration fragment/step lands). Orchestrator
sequencing:

1. Land O.2's heartbeat-tick wrapper `.cmd` + scheduled task registration first
   (per the runbook pattern: force-run, verify `Last Result: 0`).
2. Append the one line above to that same wrapper `.cmd`.
3. Force-run once more (`schtasks /Run /TN <task-name>`), then `schtasks /Query /V`
   and confirm `Last Result: 0` again (both the heartbeat touch AND the ntfy scan
   must have executed without error in the same tick).
4. Optional live-drill (after the operator supplies a real ntfy topic — NEEDS-YOU
   ask still open as of this build): create a throwaway NEEDS-YOU entry via
   `needs-you.sh add`, wait for the next tick (or force-run), confirm a push arrives
   on the operator's phone, confirm the SAME entry does not re-push on the next tick
   (dedup via `sent.jsonl`).

## Why this is fragment-only, not a direct edit

§O.0.1 rule 2 (file-disjoint ownership) + rule 7 (builders work only in their
assigned worktree/branch) — the wrapper `.cmd` is a per-machine artifact outside any
task's "Files owned" column in the §O.0.2 dispatch map, and scheduled-task
registration is explicitly called out in the runbook as a per-machine,
orchestrator-supervised step (the schtasks nested-quote collapse lesson: get it
wrong and the tick silently exits 1 forever). This task's job ends at "the scan verb
works correctly and self-tests green"; making it TICK is the orchestrator's
integration step, same as O.2's own heartbeat touch.
