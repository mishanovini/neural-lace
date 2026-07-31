# 065 — macOS cockpit auto-start: launchd LaunchAgent, not a nohup spawn

**Date:** 2026-07-29
**Status:** DECIDED and DEPLOYED (real LaunchAgent installed + verified on the operator's
machine this session — see Evidence below).
**Tier:** 1 (reversible — `launchctl bootout gui/$UID/local.neurallace.workstreams-cockpit`
+ `rm ~/Library/LaunchAgents/local.neurallace.workstreams-cockpit.plist`; no data surgery,
no third parties, no unrecoverable spend)
**Operator directive (verbatim, 2026-07-29):** "Yes, I want the macOS launch permanent."

## Problem (cold-read context)

The observability cockpit (`neural-lace/workstreams-ui/server/server.js`, a node HTTP
server on port 7733) is auto-started on Windows by
`adapters/claude-code/scripts/ensure-cockpit.sh`, spliced into the existing
`session-start-digest.sh` SessionStart hook. That script was hard-guarded to Windows only
(`_ec_is_windows()`; the launcher it shells out to is a `.ps1`). On macOS the operator had
to start the cockpit by hand (`cd workstreams-ui && node server/server.js`), and it did not
survive a reboot — the exact gap this decision closes.

## Options considered

| Option | What happens | Cost / risk |
|---|---|---|
| A. `launchd` LaunchAgent (`~/Library/LaunchAgents/*.plist`, `RunAtLoad` + `KeepAlive`) | The OS registers the job once; launchd starts it at every login (including after a reboot, with zero NL session involved) and restarts it on crash | Slightly more code (plist generation, `launchctl bootstrap`/`bootout`/`print`); requires understanding launchd's KeepAlive semantics correctly (see below) |
| B. `nohup`-backgrounded spawn from the SessionStart hook (mirrors the Windows-launcher shape, minus the `.ps1`) | Trivial to write; identical code shape to the existing Windows nohup dispatch | Does NOT satisfy "permanent": the spawned process is a descendant of the Claude Code process tree — it dies with the terminal/session, and nothing re-spawns it at the next login unless an NL session happens to start and re-run the hook. A reboot with no NL session running leaves the cockpit down indefinitely |
| C. A `cron`/`launchd` *periodic* checker that starts the server if not running | Catches "it died" eventually | Adds polling latency (cron granularity is minutes, not "at login"); still needs a real one-shot mechanism for "start now" — doesn't replace A, at best complements it |

## Decision

**Option A — a `launchd` LaunchAgent.** The operator's own word, "permanent," is decisive:
option B provably fails it (a session-tied nohup child cannot survive a reboot with no
session running), and C doesn't solve the "start it" problem at all, only "notice it's
down" on a delay. A LaunchAgent is the macOS-native mechanism for exactly this: register
once, `launchd` owns the lifecycle forever.

### KeepAlive: the dict form, not bare `true`

`server.js` already has its own single-instance guard (nl-issue [55], FM-037): on
`EADDRINUSE` it logs one line and calls `process.exit(0)` — "the port is the mutex,
not a global lock" (server.js:1580-1613). If `KeepAlive` were the bare boolean `true`,
launchd would treat that clean `exit(0)` as "needs restart" and loop forever against
whatever OTHER process (including one the operator started by hand) already owns the
port. `KeepAlive` is instead the dict form `{SuccessfulExit: false}` — restart only on a
**non-zero** (crash) exit. A real crash still gets an automatic restart; a clean
EADDRINUSE-exit is respected as a no-op, matching server.js's own design intent instead of
fighting it.

### Liveness verified by polling the port, not launchctl's exit code

`launchctl bootstrap` succeeding only proves launchd accepted the job — not that node
actually bound the port (it could crash on the first tick, or CTREE_PORT could be wrong).
`ensure-cockpit.sh`'s darwin branch polls `127.0.0.1:$PORT` via bash's own `/dev/tcp`
pseudo-device (no `curl`/`nc` dependency in the shipped path) after every install/refresh,
and logs the real result either way.

### Idempotent + single-instance

The plist is only (re)written when its desired content differs from what's on disk.
`launchctl bootstrap` is only invoked when the label is not ALREADY loaded — checked via
`launchctl print`, never trusted-and-skipped. A content change while already loaded does
one `bootout` then `bootstrap`, never an additive second load. This is belt-and-suspenders
UNDER `server.js`'s own port-is-the-mutex guard, mirroring the documented relationship
between `launch-gui.ps1`'s `Test-ServerUp` probe and the same guard on Windows
(server.js:1587-1588).

### Naming

Label `local.neurallace.workstreams-cockpit` — the `local.` prefix is the standard launchd
convention for a user-installed, non-Apple, non-reverse-DNS-registered agent; "neurallace"
mirrors the repo's own existing internal name (used pervasively in file/directory names
already — `neural-lace/`, `ensure-cockpit.log`, etc.), not a new product name.

## Why this is mine to decide (and what would reverse it)

Reversible in two commands (see Tier above). The operator's own directive names the
outcome ("permanent") without prescribing the mechanism, and only one option actually
delivers it — this is a "can I defend one answer from principles + evidence" call per
constitution §3, not a business-intent/subjective-taste call. Reversal trigger: if the
operator ever wants the cockpit NOT to auto-start on macOS, the existing kill-switch
(`ENSURE_COCKPIT_DISABLE=1` or `~/.claude/local/cockpit-disabled`) already covers both
platforms without needing to touch this decision.

## Consequences

- `ensure-cockpit.sh` now has a real side effect on macOS: it writes a file under
  `~/Library/LaunchAgents/` and calls `launchctl`. This is new — the Windows path never
  touched anything outside `~/.claude/logs/`. Any future audit of "what does SessionStart
  touch on disk" must account for this.
- A machine reboot (or the operator manually stopping the current hand-started instance)
  is the only way to observe the LaunchAgent, rather than the current manual process,
  actually bind port 7733 in normal operation — see Evidence below for a same-session
  proxy proof (a scratch label + a free port) that does not require disrupting the
  operator's live session.
- **Prerequisite bug found and fixed in the same commit:** `ensure-cockpit.sh` was tracked
  in git as mode `100644` (non-executable) since its original introduction — the SAME
  defect class as the 2026-07-14 incident's I3 (`needs-you.sh`, `session-resumer.sh`).
  `session-start-digest.sh`'s splice invokes it by DIRECT exec (`"$HOOKS_DIR/../scripts/
  ensure-cockpit.sh"`, not `bash .../ensure-cockpit.sh`), so without the executable bit
  this hook silently never fires on ANY platform that respects POSIX permissions on
  checkout — the entire mechanism (Windows path included) was at risk of being a
  documented-but-inert mechanism. Fixed via `chmod +x` + `git add` in this commit; flagged
  here rather than silently bundled because it touches the file both platforms share,
  even though the FIX is a file-mode change, not a logic change to either platform's code.

## Evidence (this session, this machine)

- Self-test: `--self-test` run under BOTH `/bin/bash` (3.2.57) and
  `$(brew --prefix)/bin/bash` (5.3.15) — 40/46 pass on each (the 6 non-passing are a
  PRE-EXISTING, unrelated gap: S4/S6/S10a/S10b assume a real `powershell`/`powershell.exe`
  on PATH, which this Mac does not have — confirmed present on the unmodified pre-darwin
  script too; logged to `docs/backlog.md`, not fixed here — out of this task's scope).
- Real (non-self-test) install on this machine: `ensure-cockpit.sh` invoked directly wrote
  `~/Library/LaunchAgents/local.neurallace.workstreams-cockpit.plist`, ran
  `launchctl bootstrap` successfully, and the liveness probe found port 7733 responding
  (the operator's own hand-started instance, which the new LaunchAgent-managed process
  correctly deferred to via `server.js`'s EADDRINUSE guard — confirmed via
  `~/.claude/logs/workstreams-cockpit.stdout.log`:
  `"[server] http://127.0.0.1:7733 already owned by another instance — exiting 0..."`).
  A second real invocation logged `"already bootstrapped — no-op (idempotent)"` with no
  re-write of the plist.
- Real cold-start proof (no fakes, different port/label so the operator's live instance
  was never touched): with `CTREE_PORT=17733` and a scratch label, the SAME code, for
  real, installed a LaunchAgent that launchd started, node bound the port, and
  `curl http://127.0.0.1:17733/api/health` returned `{"ok":true,...}` from a genuinely
  separate, launchd-spawned `node` process (verified via `lsof -iTCP:17733`). Cleaned up
  immediately after (`launchctl bootout` + `rm` the scratch plist).
