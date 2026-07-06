# Runbook: session-resumer (OS-level session-death watchdog)

<!-- last-verified: 2026-07-05 (doctor-checked) -->

**What it is.** A Windows Scheduled Task that runs OUTSIDE the Claude Code
API entirely, so an API throttle (429/529/rate-limit/overloaded) cannot kill
the watchdog itself. It scans recent transcripts for a DEATH SIGNATURE — an
API-error tail, or a stale transcript (>30 min) with in-flight work signals
(`TodoWrite` in-progress entry, a `CONTINUING:` marker, or a referenced ACTIVE
plan with unchecked tasks) — and resumes the session via `claude -p --resume
<session-id> "<nudge>"` directly (Wave E task E.7).

**The one command (what the scheduled task runs):**

```bash
bash adapters/claude-code/scripts/session-resumer.sh
```

**Registration** (orchestrator-supervised step, not run by every session):

```bash
schtasks /Create /SC MINUTE /MO 10 \
  /TN "NL-session-resumer" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd <nl-repo-root> && bash adapters/claude-code/scripts/session-resumer.sh'"
```

**Where its output lands.** Resumed sessions receive the nudge directly via
the `claude` CLI's `--resume` mechanism (not a file). Its own run log/state
lives under `~/.claude/state/` (see the script header for the exact death-
signature state files it reads).

**Check if it's registered:**

```bash
MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer"
```

`harness-doctor.sh --quick` WARNs (not RED) when this task is not yet
registered on the current machine — a documented, not-yet-wired state is
distinguished from an error.
