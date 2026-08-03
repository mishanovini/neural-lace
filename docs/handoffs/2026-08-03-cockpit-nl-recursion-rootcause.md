# 2026-08-03 — cockpit `nl.sh status --json` "recursion" root cause

Status: DIAGNOSED (all claims PROVEN unless marked) · Fix: `killTree` in
`neural-lace/workstreams-ui/server/derive-cache.js` + `server.js` (this commit)
· Related: P-08, P-10, P-12, P-13 in
[2026-08-03-EXHAUSTIVE-issue-inventory.md](2026-08-03-EXHAUSTIVE-issue-inventory.md),
nl-issues.jsonl 2026-08-03T06:53Z, auditor.js NL-FINDING 2026-07-14.

## Symptom (operator, 2026-08-02 ~23:30–23:50)

Cockpit server child processes `bash -l .../nl.sh status --json` appeared to
recursively re-spawn themselves (bash→bash→bash chains of the identical
command line, deepening every ~3 min, ~10 spawns/sec bursts, 1.77M
syscalls/sec, 21% CPU sustained, 100% at boot). Server killed ~23:50; left
down deliberately.

## Answers to the three dispatch questions

### 1. Why does `nl.sh status --json` appear to spawn a child bash of the same command?

**It does not re-invoke itself.** Ruled out (PROVEN):
- `nl.sh` contains no self-invocation, no `exec`, no wrapper re-entry
  (read: `adapters/claude-code/scripts/nl.sh`, dispatch at line 242).
- No login-profile re-exec: `~/.bash_profile`, `~/.bashrc`, `~/.profile` are
  all ABSENT on this machine; `/etc/profile` spawns only transient helpers.
- `observability-derive.sh` (what `cmd_status` calls) invokes no external
  scripts — its old `needs-you.sh` call-outs were already replaced by
  direct jq reads.

**The chains are MSYS fork visibility.** On Windows/MSYS every bash command
substitution `$(...)` forks a child process that *displays the parent's full
command line* — so nl.sh's nested substitutions (`cmd_status` →
`$(od_sessions --json)` → inner `$(...)`) render in the Windows process
table as `bash -l nl.sh status --json` → same → same. PROVEN by live
capture 2026-08-03 08:28–08:36: chains 30472→27376→36036→27388 etc., all
identical cmdlines, mid-levels accumulating 5–16 CPU-seconds.

**What made the chains immortal and multiplying** (the actual defect):
- `derive-cache.js` `spawnAsync`'s timeout ran `child.kill()`, which on
  Windows terminates ONLY the direct child. `bashBin()` resolves to
  `Git\bin\bash.exe` — a LAUNCHER whose child is the real
  `usr\bin\bash.exe` — so every timeout killed the launcher and orphaned
  100% of the actual derivation tree.
- Windows never reaps orphans (P-12; the reaper P-13 exists but is
  disarmed). Orphaned trees kept deriving/forking ~20 min each (PROVEN:
  the 08:12:53 chain was gone by 08:36; the 08:18/08:23 chains were still
  burning CPU at 08:36).
- Cadence of manufacture: every refresh tick spawns a fresh `nl status`
  whose runtime under contention exceeds the 180s timeout → one new orphan
  tree per tick, feeding back into contention. PROVEN live: new chain
  roots at 08:12:53, 08:18:09, 08:23:35, 08:28:16, 08:33:47 — the 5-min
  anti-entropy floor (`ANTI_ENTROPY_FLOOR_DEFAULT_MS = 300000`) + jitter.
  Pre-push-conversion (the pinned checkout last night) the tick was the
  30s poll × 6 subcommands — the same engine at 10× the rate ("100% at
  boot": cold-cache refreshAll spawns all six at once).
- The operator's "deepening every ~3 min" ≈ the 180s status timeout: each
  timeout-kill visibly detached another level into the orphan population.

### 2. Does the pinned checkout predate the push conversion 0808f2d9?

**Yes.** `git merge-base --is-ancestor 0808f2d9 HEAD` in the pinned
ws-ui-server checkout (the sibling `workstreams-ui-server` clone, branch
`ws-ui-server-stable`, HEAD 9a739c0c) → NOT an ancestor. The main checkout
(master 7b5217d0) HAS it. But note: **the push conversion alone does not
stop the storm** — the instance running the morning of 2026-08-03 WAS the
push-converted main-checkout server and still manufactured one orphan tree
per 5-min anti-entropy tick (measured above, 1.53M syscalls/sec at 08:36).
Orphan manufacture (this fix) and spawn frequency (0808f2d9) are
independent factors.

### 3. Fix

`killTree()` added to `derive-cache.js` (exact class + fix already PROVEN
in this repo: auditor.js NL-FINDING 2026-07-14, "781 live bash.exe" —
learned there, never propagated here):
- `spawnAsync` timeout now `taskkill /T /F` the whole tree (POSIX:
  process-group kill).
- `server.js` `runAskRegistryCli` timeout previously resolved WITHOUT
  killing at all (pure leak); now killTree.
- Known residual (measured via livetest): MSYS runs external binaries
  (jq/grep/date) as fork+exec, whose exec shim exits — an in-flight
  external at kill time is orphan-linked and escapes `/T`; such leaves die
  on pipe EOF/EPIPE within ms. The immortal storm members were the bash
  FORK chains (live links), which `/T` provably kills (livetest:
  survivors=[]).

## Additional finding: the resurrection loop

`ensure-cockpit.sh` runs at EVERY SessionStart (via session-start-digest)
and relaunched the cockpit the operator had killed:
`~/.claude/logs/ensure-cockpit.log` shows launches 06:31Z (23:31 local,
post-reboot — the stormed instance), then 15:12:49Z (08:12:49 local — the
morning resurrection; node PID 13048 born 08:12:52). The operator's kill
can never stick without the documented off-switch
`~/.claude/local/cockpit-disabled` (set during this fix window, removed at
the sanctioned restart). Note `~/.claude/local/nl-repo-path` points
ensure-cockpit at the MAIN checkout — the pinned checkout is NOT what
SessionStart resurrects.

## Verification

- livetest (scratchpad killtree-livetest3.js): production-shaped fork tree
  (launcher → script bash → subshell) — before: 3 live; after killTree:
  survivors=[] → PASS.
- state-watch.selftest.js 25/25, maintenance-pane.selftest.js 9/9.
- server.selftest.js crashes at line 893 PRE-EXISTING on unmodified master
  (reproduced identically) — filed to nl-issues.jsonl 2026-08-03.
- Functional demonstration: 10-min post-restart observation window
  (bash count + syscalls/sec flat) — recorded in the session report.
