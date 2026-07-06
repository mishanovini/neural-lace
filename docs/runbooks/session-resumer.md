# Runbook: session-resumer (OS-level session-death watchdog)

<!-- last-verified: 2026-07-06 (doctor-checked) -->

**What it is.** A Windows Scheduled Task that runs OUTSIDE the Claude Code
API entirely, so an API throttle (429/529/rate-limit/overloaded) cannot kill
the watchdog itself. It scans recent transcripts for a DEATH SIGNATURE — an
API-error tail, or a stale transcript (>30 min) with in-flight work signals
(`TodoWrite` in-progress entry, a `CONTINUING:` marker, or a referenced ACTIVE
plan with unchecked tasks) — and resumes the session via `claude -p --resume
<session-id> "<nudge>"` directly (Wave E task E.7).

Five ACTIVATION GUARDRAILS sit between classification and any real resume
action (operator concern 2026-07-06, BINDING before this is armed for real):
storm cap, tombstones, a liveness guard, shadow mode, and this kill switch.
**Do not register the scheduled task in armed mode.** Register it in SHADOW
MODE first (below) and only arm it after reviewing shadow output.

## The one command (what the scheduled task runs)

```bash
bash adapters/claude-code/scripts/session-resumer.sh
```

## Shadow mode -> armed rollout

**Step 1 — register in shadow mode.** The scheduled task's `/TR` command
wraps the script with `RESUMER_SHADOW=1` set. In shadow mode, classification
and every guardrail (storm cap, tombstone, liveness) run exactly as they
would live, but no `claude` process is ever spawned and no backoff state is
ever written — instead one digest-feed line per would-be action:

```json
{"ts":"...","session_id":"<id>","event":"would-have-resumed","detail":"would-have-resumed <id> (<reason>)"}
```

Register (orchestrator-supervised step):

```bash
schtasks /Create /SC MINUTE /MO 10 \
  /TN "NL-session-resumer" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd <nl-repo-root> && RESUMER_SHADOW=1 bash adapters/claude-code/scripts/session-resumer.sh'"
```

(`<nl-repo-root>` is the operator's neural-lace checkout — resolve via
`bash adapters/claude-code/hooks/lib/nl-paths.sh` sourced, same as every
other schtasks doc in this repo.)

**Step 2 — observe for at least 2 days.** Read the digest feed
(`~/.claude/state/resumer/digest-feed.jsonl`) or the shared ledger for
`would-have-resumed` lines. Confirm: (a) the sessions it names really were
dead (not false positives from an open-but-idle window — see the liveness
guard below), and (b) the volume is sane (the storm cap already bounds any
single reboot's burst, but shadow mode is where you actually SEE that bound
in action before it can do anything).

**Step 3 — arm.** Once shadow output looks right, re-register without
`RESUMER_SHADOW=1`:

```bash
schtasks /Change /TN "NL-session-resumer" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd <nl-repo-root> && bash adapters/claude-code/scripts/session-resumer.sh'"
```

**Step 4 — live kill-and-resume drill** (orchestrator-supervised, §E.W):
start a sacrificial `claude -p` session, kill its process mid-turn, wait one
watchdog cycle, verify the resume fired and the session continued (cite the
resumer ledger events + resumed transcript lines).

## Kill switch

Disable the scheduled task without deleting it (fastest, fully reversible):

```bash
schtasks /Change /TN "NL-session-resumer" /DISABLE
```

Re-enable:

```bash
schtasks /Change /TN "NL-session-resumer" /ENABLE
```

Delete entirely:

```bash
schtasks /Delete /TN "NL-session-resumer" /F
```

## The five activation guardrails

**1. Storm cap.** Machine-wide max resume/fallback actions per rolling hour
— default 2, override with `RESUMER_STORM_CAP` (0 = uncapped). A reboot can
leave many dead transcripts at once; the cap makes the watchdog trickle
resumes rather than detonate all of them in one 10-minute pass. Sessions
that can't fit in the current hour's budget are QUEUED (oldest-transcript-
mtime-first) and re-evaluated on the next pass — logged as event
`storm-cap-queued`, detail `"resume queued (storm cap)"`. Cap accounting
lives at `~/.claude/state/resumer/storm-cap.log` (one epoch-seconds line
per action taken in the last rolling hour; self-pruning).

Tune it:

```bash
export RESUMER_STORM_CAP=5   # allow up to 5 resumes/hour machine-wide
```

**2. Tombstones.** A session that was deliberately ended (not crashed)
should never be headlessly resumed. Mark it:

```bash
bash adapters/claude-code/scripts/session-resumer.sh --never <session-id>
```

This touches `~/.claude/state/session-resumer/never/<session-id>` — the
scan skips ANY transcript matching that id, permanently, until the marker
file is removed (`rm ~/.claude/state/session-resumer/never/<session-id>`).

Archiving a session via the CCD session store's own archive action is
**not** the same thing as a tombstone: archival is not exposed as a
mechanically-discoverable on-disk marker this script can read (verified by
inspecting a live `~/.claude/projects/<slug>/` tree — a session's own
`.jsonl`, plus for some ids a same-named directory holding `subagents/` +
`workflows/` subdirectories, neither of which reflects archived status).
If you archive a session through the UI/tool and also want the watchdog to
leave it alone forever, run `--never` on it too — `--never` is the one
explicit, durable channel.

**3. Liveness guard.** Skips any session whose repo (the transcript's own
`cwd`) has a FRESH interactive-session-lock signal — the same B.12 pattern
`sync-pt-to-personal.sh` respects (`adapters/claude-code/hooks/lib/
interactive-session-lock.sh`): either the explicit
`<repo>/.claude/state/interactive-session.lock` file, or any transcript
under that repo's own Claude-projects slug dir with mtime younger than
`ISL_WINDOW_MIN` (default 15 minutes). This guards against the exact
false-positive the mtime-staleness proxy alone can't distinguish: a human
mid-thought in a DIFFERENT session on the same repo, while THIS session
happens to look dead by the mtime heuristic. Logged as `classify-skip`,
detail `"liveness guard: interactive session live on <repo-root>"`.

**4. Shadow mode.** `RESUMER_SHADOW=1` — see the rollout section above.
Distinct from `--self-test`'s `HARNESS_SELFTEST=1` dry-run plumbing: shadow
mode runs against REAL transcripts with REAL classification and REAL
guardrail checks, it just never executes the final action or writes
backoff state.

**5. Kill switch.** This section.

## Where its output lands

Resumed sessions receive the nudge directly via the `claude` CLI's
`--resume` mechanism (not a file). Every action (classify-skip, resume-
attempt, resume-fallback, backoff-wait, escalation, storm-cap-queued,
would-have-resumed, tombstone) appends one line to
`~/.claude/state/resumer/digest-feed.jsonl` and calls `ledger_emit`. Per-
session backoff state lives at `~/.claude/state/resumer/<session-id>.json`.

## Check if it's registered

```bash
MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer"
```

`harness-doctor.sh --quick` WARNs (not RED) when this task is not yet
registered on the current machine — a documented, not-yet-wired state is
distinguished from an error.

## Self-test

```bash
bash adapters/claude-code/scripts/session-resumer.sh --self-test
```

Covers: dead-429 / stale-in-flight / natural-DONE / PAUSING classification,
backoff arithmetic, max-attempts escalation, unresumable fallback, storm cap
(3 dead + cap 2 -> 2 resumes + 1 queued), tombstone skip, liveness-guard
skip, and shadow-mode logs-but-does-not-execute. All state sandboxed; the
real `claude` binary is never invoked under `--self-test`.
