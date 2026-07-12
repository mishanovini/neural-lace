# Runbook: session-resumer (OS-level session-death watchdog)

<!-- last-verified: 2026-07-06 (doctor-checked) -->

**What it is.** A Windows Scheduled Task that runs OUTSIDE the Claude Code
API entirely, so an API throttle (429/529/rate-limit/overloaded) cannot kill
the watchdog itself. Detection is a two-stage, heartbeat-first funnel
(ADR-061 D1 — `docs/decisions/061-session-continuity-supervision.md`):
stage 1 batch-reads the heartbeat directory joined with transcript mtimes
(cheap, bounded); stage 2 inspects transcripts ONLY for stale/crashed
candidates with in-flight-work signals (bounded by a per-pass candidate
ceiling, default 10, and a wall-clock budget, default 60s — both env-tunable,
both fail closed to "do less, log it"). Death signals: a FIELD-AWARE
API-error tail (`subtype=="api_error"` / `isApiErrorMessage` /
`apiErrorStatus` — never substring regex) past a 30-min cooldown floor, or a
stale transcript with in-flight work (`TodoWrite` in-progress entry, a
`CONTINUING:` marker, or a referenced ACTIVE plan with unchecked tasks).
`DONE:`/`PAUSING:`/`BLOCKED:` endings are never resumed. A `throttled`
session (pid alive + api-error tail) is DEFERRED on a widening schedule
(30m/60m/2h/5h; parked `awaiting-limit-reset` after 24h), never busy-retried
(ADR-061 D4). Eligible dead sessions are resumed via `claude -p --resume
<session-id> "<nudge>"` — at most ONE spawn per pass (ADR-061 D5). Every
pass emits one `supervisor-pass` digest record (elapsed_ms, candidates_seen,
candidates_classified, budget_tripped).

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
and every guardrail (storm cap, spawn breaker, tombstone, liveness, cooldown)
run exactly as they would live, but no `claude` process is ever spawned —
instead one digest-feed line per would-be action:

```json
{"ts":"...","session_id":"<id>","event":"would-have-resumed","detail":"would-have-resumed <id> (<reason>) [shadow attempt N/5]"}
```

Shadow mode EXERCISES the full backoff/escalation ladder (ADR-061 D5):
attempt counts advance, backoff windows apply, escalation fires at the
5-attempt cap — all state written under the shadow-scoped subdir
`~/.claude/state/resumer/shadow/` (backoff files, storm-cap log,
spawn-window log, cooldown marks, deferral records), so shadow observation
produces real evidence about post-arming ladder behavior without ever
touching the live-state files. Tombstones and the digest feed are shared
between modes.

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

This touches `~/.claude/state/resumer/never/<session-id>` — the
scan skips ANY transcript matching that id, permanently, until the marker
file is removed (`rm ~/.claude/state/resumer/never/<session-id>`).
(Path corrected per ADR-061 §2 — earlier docs said
`state/session-resumer/never/` while the code always used
`state/resumer/never/`; the docs now match the code.)

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
guardrail checks, and rehearses the full backoff/escalation ladder in the
shadow-scoped state subdir — it just never executes the final action.

**5. Kill switch.** This section. Additionally the supervisor disarms
ITSELF (ADR-061 D5/§7) when its OWN spawn-window log trips
`RESUMER_MAX_SPAWNS_PER_HOUR` while armed: the armed marker is renamed to
`resumer-armed.txt.auto-disarmed-<ts>`, a `supervisor-auto-disarmed` line
is emitted, and every later pass runs in shadow until the operator re-arms
(rename the marker back after review). Machine-wide live-process trips
only defer the pass — they never disarm.

## Where its output lands

Resumed sessions receive the nudge directly via the `claude` CLI's
`--resume` mechanism (not a file). Every action (classify-skip, resume-
attempt, resume-fallback, backoff-wait, escalation, storm-cap-queued,
would-have-resumed, tombstone, throttle-deferred, throttle-deferral-cleared,
parked-awaiting-limit-reset, tick-ceiling-deferred, pass-budget-exhausted,
supervisor-auto-disarmed) appends one line to
`~/.claude/state/resumer/digest-feed.jsonl` and calls `ledger_emit`; every
pass additionally appends one `supervisor-pass` record carrying elapsed_ms /
candidates_seen / candidates_classified / budget_tripped as top-level JSON
fields (the ADR-061 §7 metric source — p95 pass cost:
`jq 'select(.event=="supervisor-pass") | .elapsed_ms'` over the feed).
Per-session backoff state lives at `~/.claude/state/resumer/<session-id>.json`
(shadow passes: `~/.claude/state/resumer/shadow/...`); throttle-deferral
records at `~/.claude/state/resumer/deferrals/<session-id>.json`; park
markers at `~/.claude/state/resumer/never/<session-id>.awaiting-limit-reset`
(NOT tombstones — distinct suffix).

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

Covers: dead-429 (real rate_limit shape) / system-api_error retry shape /
stale-in-flight / natural-DONE / PAUSING / BLOCKED-skip-always
classification, the field-aware 529-in-UUID negative, the fresh-api-error
cooldown floor, backoff arithmetic, max-attempts escalation, unresumable
fallback, storm cap (3 dead + cap 2 -> 2 resumes + 1 queued), tombstone
skip, liveness-guard skip, shadow-mode ladder rehearsal (shadow-scoped
backoff advance + escalation), throttle deferral (record + widening + park
+ cooldown floor), auto-disarm (spawn-window trip renames the armed marker;
live-process trip never disarms), the per-tick spawn ceiling, and the
REQUIRED live-scale funnel regression (1,000-transcript estate: budget +
candidate ceiling hold, supervisor-pass record emitted). All state
sandboxed; the real `claude` binary is never invoked under `--self-test`.

## Registration pattern (REQUIRED — quoting lesson 2026-07-06, location + hidden-window lessons 2026-07-07)
Do NOT inline the bash -c command in /TR: schtasks collapses nested quotes (observed live: the
inner path quotes truncated the -c argument -> every tick exit 1, silently).

Wrapper files live in **%USERPROFILE%\.claude\state\task-wrappers\** — NEVER in
~/.claude/scripts: install.sh re-syncs that dir from the repo and machine-local
wrappers placed there were wiped by a later install (observed 2026-07-07: the task's
/TR pointed at a deleted .cmd; resumer popped a visible console per tick meanwhile).
state/ is machine state and is never purged.

Two files there:

1. `run-hidden.vbs` (shared launcher — schtasks running a .cmd directly flashes a
   visible console window every tick; wscript with window-style 0 is the fix):

       Set sh = CreateObject("WScript.Shell")
       cmd = ""
       For i = 0 To WScript.Arguments.Count - 1
         cmd = cmd & """" & WScript.Arguments(i) & """" & " "
       Next
       sh.Run Trim(cmd), 0, False

2. `resumer-shadow.cmd`:

       @echo off
       "C:\Program Files\Git\bin\bash.exe" -c "export PATH=/usr/bin:/mingw64/bin:$PATH; cd '<nl-repo-root-msys>' && RESUMER_SHADOW=1 bash adapters/claude-code/scripts/session-resumer.sh >> <log> 2>&1"

Register /TR as (all paths space-free, so quote-collapse-proof):

    schtasks /Change /TN "NL-session-resumer" /TR "C:\Windows\System32\wscript.exe C:\Users\<user>\.claude\state\task-wrappers\run-hidden.vbs C:\Users\<user>\.claude\state\task-wrappers\resumer-shadow.cmd"

Same pattern for NL-workstreams-heartbeat (its `heartbeat-tick.cmd` runs
`bash ~/.claude/hooks/workstreams-emit.sh --heartbeat` — the LIVE mirror path, never
a repo-worktree or /tmp path; the 0x80070002-every-5-min failure of 2026-07-06/07 was
a /TR pointing at a dead MSYS tempdir). Verify after registering: force one run
(schtasks /Run), then schtasks /Query /V must show Last Result: 0 (267009 = still
running; 267011 = not yet run). Per-machine step; auto-mode classifiers treat
schtasks /Change as persistence — expect to run this operator-supervised.

## Registration record — 2026-07-12 (this machine)
Registered during the overnight session (operator-prioritized): `NL-session-resumer`
/SC MINUTE /MO 10 via the wrapper pattern above, with ONE deviation from the older
`resumer-shadow.cmd` example: the wrapper is `resumer-tick.cmd` and bakes NO
`RESUMER_SHADOW=1` — per ADR-061 D5 the armed-marker file
(`~/.claude/local/resumer-armed.txt`) now governs live-vs-shadow, and an unarmed
machine already behaves as shadow. This makes arming a one-file action with no
schtasks edit (and un-arming = deleting the marker). `NL-workstreams-heartbeat`
was repointed the same way (its old /TR used MSYS paths → 0x80070002 every tick).
Verified: both LastTaskResult=0, resumer `tick-rc=0` in
`~/.claude/state/session-resumer/task.log`, clean `supervisor-pass` in the digest
feed with the liveness guard excluding a live interactive session.
